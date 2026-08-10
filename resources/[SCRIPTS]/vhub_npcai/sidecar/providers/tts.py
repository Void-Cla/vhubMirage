"""
tts.py — provedores de VOZ (TTS) do vhub_npcai.

Contrato único: TTSProvider.synthesize(text, spec) -> bytes(WAV) | None
  spec = { provider, model, voice, rate, format }  (resolvido pela config Lua)

  • SAPI   — Windows local, subprocess isolado (evita deadlock COM). Sem custo de nuvem.
  • OpenAI — voz de alta qualidade (futuro). Ativa trocando voice.provider='openai'.

O controle de concorrência (máx. gerações ao vivo) fica no server.py (semáforo global),
para que o teto valha independentemente do provedor escolhido.
"""

from __future__ import annotations
import concurrent.futures
import os
import queue
import struct
import subprocess
import sys
import tempfile
import threading
from typing import Optional


# ============================================================
# BASE
# ============================================================

class TTSProvider:
    """Base de provedor de voz. Retorna WAV em bytes ou None (fail-closed)."""

    @property
    def name(self) -> str:
        return 'base'

    def available(self) -> bool:
        return False

    def synthesize(self, text: str, spec: dict) -> Optional[bytes]:
        raise NotImplementedError

    def stats(self) -> dict:
        return {'provider': self.name, 'available': self.available()}


# ============================================================
# SAPI (padrão)
# ------------------------------------------------------------
# Caminho rápido: worker persistente in-process (comtypes → SAPI.SpVoice), síntese
# direta para memória (SpMemoryStream), SEM subprocess e SEM arquivo temporário.
# Um único voice/worker serial (SAPI é serial por natureza) — latência ~80-150ms
# vs. ~600ms do spawn de processo anterior.
# Fallback: se o worker in-process falhar ao subir OU em runtime, cai para o
# subprocess pyttsx3 provado (comportamento idêntico ao anterior). Fail-safe.
# ============================================================

_SAPI_SCRIPT = r"""
import sys
import pyttsx3
engine = pyttsx3.init()
engine.setProperty('rate', int(sys.argv[2]) if len(sys.argv) > 2 else 160)
if len(sys.argv) > 4 and sys.argv[4]:
    for v in engine.getProperty('voices'):
        if sys.argv[4].lower() in (v.name or '').lower():
            engine.setProperty('voice', v.id); break
engine.save_to_file(sys.argv[1], sys.argv[3] if len(sys.argv) > 3 else 'output.wav')
engine.runAndWait()
"""

# SpeechAudioFormatType: 16kHz 16-bit mono (casa com o pipeline STT/stitch)
_SAFT_16K_16BIT_MONO = 18


def _wpm_to_sapi_rate(wpm: int) -> int:
    """Converte palavras/min (~200=neutro) para a escala SAPI Rate [-10..10]."""
    r = round((wpm / 200.0 - 1.0) * 10)
    return max(-10, min(10, int(r)))


def _pcm_to_wav(pcm: bytes, sample_rate: int = 16000, channels: int = 1, bits: int = 16) -> bytes:
    """Envolve PCM cru em um cabeçalho RIFF/WAVE válido (para pydub/stitch lerem)."""
    byte_rate   = sample_rate * channels * (bits // 8)
    block_align = channels * (bits // 8)
    header = struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF', 36 + len(pcm), b'WAVE',
        b'fmt ', 16, 1, channels,
        sample_rate, byte_rate, block_align, bits,
        b'data', len(pcm),
    )
    return header + pcm


class _SapiWorker:
    """Thread dedicada que segura um SAPI.SpVoice e sintetiza serialmente para memória."""

    def __init__(self):
        self._q: queue.Queue = queue.Queue()
        self._ready = threading.Event()
        self._ok = False
        self._voice = None
        self._voice_tokens = []      # [(name_lower, token)]
        self._cur_voice_name = None
        self._t = threading.Thread(target=self._run, daemon=True, name='sapi-tts')
        self._t.start()

    def _run(self):
        try:
            import comtypes
            import comtypes.client
            comtypes.CoInitialize()
            self._voice = comtypes.client.CreateObject('SAPI.SpVoice')
            try:
                self._voice_tokens = [
                    ((tok.GetDescription() or '').lower(), tok)
                    for tok in self._voice.GetVoices()
                ]
            except Exception:
                self._voice_tokens = []
            self._ok = True
        except Exception:
            self._ok = False
            self._ready.set()
            return
        self._ready.set()

        while True:
            job = self._q.get()
            if job is None:
                break
            text, rate, voice_name, fut = job
            try:
                fut.set_result(self._synth(text, rate, voice_name))
            except Exception as exc:
                fut.set_exception(exc)

    def _synth(self, text: str, rate: int, voice_name: str) -> Optional[bytes]:
        import comtypes.client
        stream = comtypes.client.CreateObject('SAPI.SpMemoryStream')
        stream.Format.Type = _SAFT_16K_16BIT_MONO
        self._voice.AudioOutputStream = stream
        self._voice.Rate = _wpm_to_sapi_rate(rate)

        # seleção de voz (só re-resolve quando muda de nome — evita GetVoices por call)
        if voice_name and voice_name != self._cur_voice_name:
            for name_lower, tok in self._voice_tokens:
                if voice_name.lower() in name_lower:
                    self._voice.Voice = tok
                    self._cur_voice_name = voice_name
                    break

        self._voice.Speak(text, 0)  # flag 0 = síncrono
        raw = bytes(bytearray(stream.GetData()))
        if not raw:
            return None
        return _pcm_to_wav(raw, 16000, 1, 16)

    def synthesize(self, text: str, rate: int, voice_name: str) -> Optional[bytes]:
        """Bloqueia o chamador (não o main); retorna WAV bytes ou levanta exceção."""
        self._ready.wait(timeout=20)
        if not self._ok:
            raise RuntimeError('sapi worker indisponivel')
        fut: concurrent.futures.Future = concurrent.futures.Future()
        self._q.put((text, rate, voice_name, fut))
        return fut.result(timeout=12)


class SapiTTS(TTSProvider):
    def __init__(self):
        self._worker: Optional[_SapiWorker] = None
        self._worker_failed = False   # in-process desativado → usa subprocess
        self._lock = threading.Lock()

    @property
    def name(self) -> str:
        return 'sapi'

    def available(self) -> bool:
        try:
            import pyttsx3  # noqa: F401
            return True
        except ImportError:
            return False

    def _get_worker(self) -> Optional[_SapiWorker]:
        if self._worker_failed:
            return None
        if self._worker is None:
            with self._lock:
                if self._worker is None and not self._worker_failed:
                    self._worker = _SapiWorker()
        return self._worker

    def synthesize(self, text: str, spec: dict) -> Optional[bytes]:
        rate  = int(spec.get('rate', 160))
        voice = str(spec.get('voice', '') or '')

        # ── caminho rápido: worker in-process ──────────────────
        worker = self._get_worker()
        if worker is not None:
            try:
                wav = worker.synthesize(text, rate, voice)
                if wav:
                    return wav
            except Exception:
                # desativa o in-process de vez e cai para o subprocess provado
                self._worker_failed = True

        # ── fallback: subprocess pyttsx3 (comportamento anterior) ──
        return self._synthesize_subprocess(text, rate, voice)

    @staticmethod
    def _synthesize_subprocess(text: str, rate: int, voice: str) -> Optional[bytes]:
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            tmp_path = tmp.name
        script = tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False, encoding='utf-8')
        script.write(_SAPI_SCRIPT)
        script.close()
        try:
            subprocess.run(
                [sys.executable, script.name, text, str(rate), tmp_path, voice],
                timeout=10, capture_output=True,
            )
            if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
                with open(tmp_path, 'rb') as f:
                    return f.read()
        except Exception:
            pass
        finally:
            for p in (tmp_path, script.name):
                try: os.unlink(p)
                except OSError: pass
        return None


# ============================================================
# OPENAI TTS (futuro — voz de alta qualidade)
# ============================================================

class OpenAITTS(TTSProvider):
    def __init__(self):
        self._client = None
        try:
            from openai import OpenAI
            key = os.environ.get('OPENAI_API_KEY', '')
            if key:
                self._client = OpenAI(api_key=key, timeout=10.0, max_retries=0)
        except ImportError:
            self._client = None

    @property
    def name(self) -> str:
        return 'openai'

    def available(self) -> bool:
        return self._client is not None

    def synthesize(self, text: str, spec: dict) -> Optional[bytes]:
        if not self._client:
            return None
        model = spec.get('model') or 'gpt-4o-mini-tts'
        voice = spec.get('voice') or 'onyx'
        try:
            resp = self._client.audio.speech.create(
                model=model, voice=voice, input=text, response_format='wav',
            )
            raw = resp.read() if hasattr(resp, 'read') else bytes(resp.content)
            return _to_wav_16k_mono(raw)  # homogeneíza p/ concatenação (stitch)
        except Exception:
            return None


# ============================================================
# NORMALIZAÇÃO — WAV 16kHz mono (compatível com o stitch)
# ============================================================

def _to_wav_16k_mono(raw: bytes) -> Optional[bytes]:
    """Converte WAV arbitrário para 16kHz mono 16-bit (pydub/ffmpeg do path de STT)."""
    try:
        import io
        from pydub import AudioSegment
        seg = AudioSegment.from_file(io.BytesIO(raw))
        seg = seg.set_frame_rate(16000).set_channels(1).set_sample_width(2)
        out = io.BytesIO()
        seg.export(out, format='wav')
        return out.getvalue()
    except Exception:
        return raw  # sem pydub: devolve como veio (stitch lê params do 1º segmento)


# ============================================================
# FÁBRICA — instância única por provedor (cache)
# ============================================================

_REGISTRY: dict[str, TTSProvider] = {}
_reg_lock = threading.Lock()

_FACTORY = {
    'sapi':   SapiTTS,
    'openai': OpenAITTS,
}


def get_tts(provider: str) -> Optional[TTSProvider]:
    """Retorna a instância (singleton) do provedor de voz, ou None se 'none'/desconhecido."""
    if not provider or provider == 'none':
        return None
    with _reg_lock:
        inst = _REGISTRY.get(provider)
        if inst is None:
            cls = _FACTORY.get(provider)
            if cls is None:
                return None
            inst = cls()
            _REGISTRY[provider] = inst
        return inst


def reset_tts_registry():
    """Descarta as instâncias — força re-init com chaves/config atualizadas."""
    with _reg_lock:
        _REGISTRY.clear()
