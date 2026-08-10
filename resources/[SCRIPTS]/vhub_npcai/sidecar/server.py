"""
server.py — sidecar Python do vhub_npcai (porta 7513, loopback only)
Estende o motor STT/TTS do whisper/server.py com /converse, /prewarm_name, /reload_npcs
"""

from __future__ import annotations
import base64
import concurrent.futures
import hmac
import io
import json
import logging
import msvcrt
import os
import queue
import tempfile
import threading
import time
from collections import OrderedDict, deque
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional

from flask import Flask, jsonify, request
from waitress import serve
from werkzeug.exceptions import HTTPException


def _adquirir_instancia():
    arquivo = (Path(__file__).resolve().parent.parent / '.sidecar.lock').open('a+b')
    arquivo.seek(0, os.SEEK_END)
    if arquivo.tell() == 0:
        arquivo.write(b'\0')
        arquivo.flush()
    try:
        arquivo.seek(0)
        msvcrt.locking(arquivo.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError as exc:
        arquivo.close()
        raise RuntimeError('sidecar vhub_npcai ja esta em execucao') from exc
    return arquivo


_INSTANCE_LOCK = _adquirir_instancia()

# ── faster-whisper (upgrade do whisper base) ─────────────────────────────────
try:
    from faster_whisper import WhisperModel
    _WHISPER_BACKEND = 'faster-whisper'
except ImportError:
    try:
        import whisper as _whisper_orig
        _WHISPER_BACKEND = 'whisper'
    except ImportError:
        _WHISPER_BACKEND = 'none'

from intent    import IntentEngine
from cache     import AudioCache
from providers import get_llm, get_tts, reset_llm_registry, reset_tts_registry

# ── configuração ──────────────────────────────────────────────────────────────
HOST      = '127.0.0.1'
PORT      = 7513
LOG_LEVEL = logging.INFO
NPCS_DIR  = Path(__file__).parent / 'npcs'
MODEL_SIZE = os.environ.get('NPCAI_WHISPER_MODEL', 'base')
AUTH_TOKEN = os.environ.get('NPCAI_TOKEN', '').strip()

if len(AUTH_TOKEN) != 64 or any(char not in '0123456789abcdef' for char in AUTH_TOKEN):
    raise RuntimeError('NPCAI_TOKEN ausente ou invalido; use start_npcai.bat')

logging.basicConfig(level=LOG_LEVEL, format='[npcai] %(levelname)s %(message)s')
log = logging.getLogger('npcai')

_LOG_DIR = Path(__file__).parent / 'logs'
_LOG_DIR.mkdir(exist_ok=True)
_file_handler = RotatingFileHandler(
    _LOG_DIR / 'sidecar.log',
    maxBytes=1024 * 1024,
    backupCount=2,
    encoding='utf-8',
)
_file_handler.setFormatter(logging.Formatter(
    '%(asctime)s [%(levelname)s] %(message)s'
))
log.addHandler(_file_handler)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 512 * 1024


@app.before_request
def _autenticar_requisicao():
    recebido = request.headers.get('X-NPCAI-Token', '')
    if not hmac.compare_digest(recebido, AUTH_TOKEN):
        return jsonify({'ok': False, 'err': 'unauthorized'}), 401


@app.errorhandler(Exception)
def _erro_interno(exc):
    if isinstance(exc, HTTPException):
        return jsonify({
            'ok': False,
            'err': f'http_{exc.code}',
        }), exc.code
    log.exception('excecao interna em %s', request.path)
    return jsonify({'ok': False, 'err': 'internal_error'}), 500

# ── estado global ─────────────────────────────────────────────────────────────
_whisper_model = None
_whisper_lock  = threading.Lock()
_stt_queue: queue.Queue = queue.Queue()

_npc_configs: dict[str, dict] = {}     # npc_id → config + IntentEngine
# cache com biblioteca em disco: segmentos determinísticos sobrevivem a restart e
# são reusados (sistema evolui sozinho; custo de TTS cai a cada gameplay).
_audio_cache  = AudioCache(capacity=512, persist_dir=Path(__file__).parent / 'audio_cache')

# pool para síntese de segmentos em paralelo (alinhado ao teto global de TTS)
_seg_pool = concurrent.futures.ThreadPoolExecutor(
    max_workers=max(1, int(os.environ.get('NPCAI_MAX_LIVE_TTS', '2'))),
    thread_name_prefix='seg-tts',
)

# ── thinking audio — frases de transição pré-sintetizadas (cache 0-latência) ─
_thinking_cache: dict[str, list[bytes]] = {}  # npc_id → lista de WAVs
_thinking_lock  = threading.Lock()

# ── training samples (para N3) ────────────────────────────────────────────────
_train_samples: dict[str, list[dict]] = {}  # npc_id → [{text, intent}] (janela)
_train_since:   dict[str, int]        = {}  # npc_id → amostras desde o último treino
_train_lock    = threading.Lock()
_TRAIN_MIN     = 50    # re-treina a cada 50 amostras novas
_TRAIN_MAX     = 200   # janela deslizante: no máx. 200 amostras por NPC na RAM

# ── memória curta EFÊMERA de sessão (ring buffer por char×npc, RAM só) ─────────
# Continuidade dentro da sessão: o NPC "lembra" os últimos assuntos e o que ele
# mesmo respondeu. Guarda só (intent, npc_text) — NUNCA a fala crua do jogador —
# então não reintroduz superfície de prompt-injection. Limpo em /session_end.
_session_ctx:  "OrderedDict[str, deque]" = OrderedDict()  # 'charId:npcId' → deque
_session_lock  = threading.Lock()
_SESSION_TURNS = 4        # trocas lembradas por par char×npc
_SESSION_CAP   = 2048     # teto de pares vivos (evict LRU se estourar)


# ============================================================
# INICIALIZAÇÃO
# ============================================================

def _load_whisper():
    global _whisper_model
    with _whisper_lock:
        if _whisper_model is not None:
            return
        log.info(f'carregando Whisper ({_WHISPER_BACKEND}, model={MODEL_SIZE})')
        if _WHISPER_BACKEND == 'faster-whisper':
            _whisper_model = WhisperModel(MODEL_SIZE, device='cpu', compute_type='int8')
        elif _WHISPER_BACKEND == 'whisper':
            _whisper_model = _whisper_orig.load_model(MODEL_SIZE)
        else:
            log.warning('nenhum backend STT disponível')
    log.info('Whisper pronto')


def _load_npc_configs():
    global _npc_configs
    configs = {}
    if not NPCS_DIR.exists():
        log.warning(f'diretório de NPCs não encontrado: {NPCS_DIR}')
        return
    for f in NPCS_DIR.glob('*.json'):
        try:
            with open(f, encoding='utf-8') as fh:
                cfg = json.load(fh)
            npc_id = cfg.get('id', f.stem)
            cfg['_engine'] = IntentEngine(cfg)
            configs[npc_id] = cfg
            log.info(f'NPC carregado: {npc_id}')
        except Exception as e:
            log.error(f'erro ao carregar {f}: {e}')
    _npc_configs = configs


_MURMUR_GENERIC = [
    'Hmm...',
    'Deixa eu pensar...',
    'É...',
    'Um segundo...',
    'Aha...',
]

_NUI_AUDIO_DIR = Path(__file__).parent.parent / 'nui' / 'audio'


def _prewarm_thinking():
    """Pré-sintetiza frases de pensamento e murmúrios genéricos em background thread."""
    def _worker():
        # ── thinking_frases por NPC ────────────────────────────
        for npc_id, npc in list(_npc_configs.items()):
            frases = npc.get('thinking_frases') or []
            if not frases:
                continue
            wavs = []
            for frase in frases:
                try:
                    wav = _tts(str(frase)[:120], _DEFAULT_VOICE)
                    if wav:
                        wavs.append(wav)
                except Exception as e:
                    log.warning(f'thinking prewarm falhou [{npc_id}]: {e}')
            if wavs:
                with _thinking_lock:
                    _thinking_cache[npc_id] = wavs
                log.info(f'thinking cache pronto: {npc_id} ({len(wavs)} frases)')

        # ── murmúrios genéricos → nui/audio/ (assets estáticos) ─
        try:
            _NUI_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
            for i, frase in enumerate(_MURMUR_GENERIC, start=1):
                dest = _NUI_AUDIO_DIR / f'murmur_generic_{i}.wav'
                if dest.exists():
                    continue  # não re-gera se já existe
                wav = _tts(frase, _DEFAULT_VOICE)
                if wav:
                    dest.write_bytes(wav)
                    log.info(f'murmur gerado: {dest.name}')
        except Exception as e:
            log.warning(f'geracao de murmurios falhou: {e}')

    t = threading.Thread(target=_worker, daemon=True, name='thinking-prewarm')
    t.start()


def _start_stt_worker():
    """Fila serial para STT — 1 req/s (faster-whisper: ~3-5x mais rápido)."""
    def _worker():
        while True:
            job = _stt_queue.get()
            if job is None:
                break
            fn, audio_bytes, result_holder, evt = job
            try:
                result_holder['text'] = fn(audio_bytes)
            except Exception as e:
                result_holder['error'] = str(e)
                result_holder['text']  = ''
            finally:
                evt.set()
    t = threading.Thread(target=_worker, daemon=True)
    t.start()


# ============================================================
# STT
# ============================================================

def _transcribe_bytes(audio_bytes: bytes, language: str = 'pt') -> str:
    """Transcreve áudio WAV (bytes) via Whisper, fila serial (thread-safe)."""
    if _WHISPER_BACKEND == 'none':
        return ''

    result_holder: dict = {}
    evt = threading.Event()
    _stt_queue.put((lambda ab: _do_transcribe(ab, language), audio_bytes, result_holder, evt))
    evt.wait(timeout=15)
    return result_holder.get('text', '')


def _do_transcribe(audio_bytes: bytes, language: str = 'pt') -> str:
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name
    try:
        if _WHISPER_BACKEND == 'faster-whisper':
            segments, _ = _whisper_model.transcribe(tmp_path, language=language, beam_size=5)
            return ' '.join(s.text for s in segments).strip()
        elif _WHISPER_BACKEND == 'whisper':
            result = _whisper_model.transcribe(tmp_path, language=language)
            return result.get('text', '').strip()
    finally:
        os.unlink(tmp_path)
    return ''


# ============================================================
# DECODIFICAÇÃO DE ÁUDIO (webm → WAV via pydub)
# ============================================================

def _decode_audio(b64_audio: str) -> Optional[bytes]:
    """Decodifica base64 + converte webm→WAV 16kHz mono via pydub."""
    try:
        raw = base64.b64decode(b64_audio)
    except Exception:
        return None
    try:
        from pydub import AudioSegment
        seg = AudioSegment.from_file(io.BytesIO(raw))
        seg = seg.set_frame_rate(16000).set_channels(1).set_sample_width(2)
        buf = io.BytesIO()
        seg.export(buf, format='wav')
        return buf.getvalue()
    except Exception as e:
        log.warning(f'decode audio falhou: {e}')
        return None


# ============================================================
# TTS — roteado por provedor (SAPI | OpenAI), teto de concorrência
# ============================================================

# teto de gerações TTS ao vivo simultâneas (config Lua ai.voice.max_live_tts)
def _audio_para_transporte(wav_bytes: Optional[bytes]) -> str:
    """Compacta WAV em MP3 mono; reduz HTTP/evento sem alterar o cache interno."""
    if not wav_bytes:
        return ''
    try:
        from pydub import AudioSegment
        seg = AudioSegment.from_file(io.BytesIO(wav_bytes))
        # mantém a taxa nativa (16kHz) — voz humana < 4kHz Nyquist; upsample seria
        # custo de CPU sem ganho perceptível. Só garante mono antes do MP3.
        seg = seg.set_channels(1)
        buf = io.BytesIO()
        seg.export(buf, format='mp3', bitrate='48k')
        return base64.b64encode(buf.getvalue()).decode()
    except Exception as exc:
        log.warning(f'compactacao de audio falhou: {exc}')
        return base64.b64encode(wav_bytes).decode()


_tts_sem = threading.Semaphore(int(os.environ.get('NPCAI_MAX_LIVE_TTS', '2')))

_DEFAULT_VOICE = {'provider': 'sapi', 'rate': 160}

def _tts(text: str, voice_spec: dict) -> Optional[bytes]:
    """Sintetiza texto para WAV via o provedor escolhido (semáforo global de concorrência)."""
    if not text:
        return None
    spec = voice_spec or _DEFAULT_VOICE
    provider = get_tts(spec.get('provider', 'sapi'))
    if not provider:
        return None
    with _tts_sem:
        try:
            return provider.synthesize(text, spec)
        except Exception as e:
            log.warning(f'TTS falhou ({spec.get("provider")}): {e}')
            return None


# ============================================================
# PIPELINE /converse
# ============================================================

def _eval_conditions(cond: dict, memory: dict) -> bool:
    """Avalia condições de variante contra o mapa de memória."""
    for k, v in cond.items():
        # suporte a sufixo _gte para comparação numérica
        if k.endswith('_gte'):
            base_key = k[:-4]
            try:
                if int(memory.get(base_key, '0')) < int(v):
                    return False
            except (ValueError, TypeError):
                return False
        else:
            if memory.get(k) != str(v):
                return False
    return True


def _select_variant(intent_cfg: dict, memory: dict) -> dict:
    """Seleciona a variante mais específica cujas condições de memória são satisfeitas."""
    variants = intent_cfg.get('variants')
    if not variants:
        return intent_cfg

    # testa variantes na ordem declarada (primeira que satisfaz vence)
    for vname, vdata in variants.items():
        if vname == 'default':
            continue
        cond = vdata.get('if_memory', {})
        if _eval_conditions(cond, memory):
            return vdata

    return variants.get('default', {})


def _pick_response(npc_cfg: dict, intent: str, memory: dict,
                   voice_spec: dict, char_name: str) -> tuple[str, bytes | None, dict]:
    """
    Monta a resposta cacheada: escolhe variante por memória, sintetiza segmentos pelo
    provedor de voz atual e concatena (stitch). O token '[nome]' vira o nome do jogador
    (áudio pré-aquecido/cache de nome). Cache é por (npc, intenção, variante, PROVEDOR).
    """
    respostas = npc_cfg.get('respostas', {})
    intent_cfg = respostas.get(intent) or respostas.get('fallback') or {}

    selected = _select_variant(intent_cfg, memory)
    segments_text: list = selected.get('segments', [])
    mem_delta: dict = selected.get('memory_delta', intent_cfg.get('memory_delta', {}))

    if not segments_text:
        return '', None, mem_delta

    import random
    npc_id      = npc_cfg['id']
    provider    = (voice_spec or {}).get('provider', 'sapi')
    variant_tag = 'v' + str(hash(str(selected.get('if_memory', {}))) & 0xFFFF)

    # ── 1ª passada (serial, barata): resolve cache-hits e lista o que falta TTS ──
    display_parts: list[str]              = []
    slots:         list[Optional[bytes]]  = []   # bytes prontos ou None (pendente)
    pending:       list[tuple]            = []   # (slot_idx, kind, key, text)

    for i, seg in enumerate(segments_text):
        chosen = random.choice(seg) if isinstance(seg, list) else seg
        idx = len(slots)

        if chosen == '[nome]':  # slot de nome do jogador
            display_parts.append(char_name)
            name_wav = _audio_cache.get_name(npc_id, char_name)
            slots.append(name_wav)
            if not name_wav:
                pending.append((idx, 'name', char_name, char_name))
            continue

        display_parts.append(chosen)
        cache_key = f'{intent}_{variant_tag}_{provider}_{i}'
        cached = _audio_cache.get(npc_id, cache_key)
        slots.append(cached)
        if not cached:
            pending.append((idx, 'seg', cache_key, chosen))

    # ── síntese em paralelo dos segmentos faltantes (ordem preservada por índice) ──
    if pending:
        futs = {_seg_pool.submit(_tts, text, voice_spec): (idx, kind, key)
                for (idx, kind, key, text) in pending}
        for fut in concurrent.futures.as_completed(futs):
            idx, kind, key = futs[fut]
            try:
                wav = fut.result()
            except Exception:
                wav = None
            if not wav:
                continue
            slots[idx] = wav
            if kind == 'name':
                _audio_cache.put_name(npc_id, char_name, wav)
            else:
                _audio_cache.put(npc_id, key, wav)

    wav_segments = [w for w in slots if w]
    full_text = ' '.join(display_parts)
    if wav_segments:
        return full_text, AudioCache.stitch(wav_segments), mem_delta
    return full_text, None, mem_delta


def _compute_visit_delta(memory: dict) -> dict:
    """Incrementa contador de visitas e define marcos de relacionamento."""
    try:
        visitas = max(0, int(memory.get('visitas', '0'))) + 1
    except (TypeError, ValueError):
        visitas = 1
    delta: dict = {'visitas': {'val': str(visitas), 'weight': 1}}
    if visitas == 1:
        delta['met'] = {'val': 'true', 'weight': 1}
    if visitas >= 3 and not memory.get('regular'):
        delta['regular'] = {'val': 'true', 'weight': 1}
    return delta


def _accumulate_sample(npc_id: str, text: str, intent: str):
    """Acumula sample e dispara treino do N3 em BACKGROUND (nunca no caminho da resposta)."""
    snapshot = None
    with _train_lock:
        lst = _train_samples.setdefault(npc_id, [])
        lst.append({'text': text, 'intent': intent})
        # janela deslizante: mantém no máx. _TRAIN_MAX amostras recentes (anti-leak)
        if len(lst) > _TRAIN_MAX:
            del lst[:len(lst) - _TRAIN_MAX]
        # conta amostras desde o último treino (independe do tamanho da janela)
        _train_since[npc_id] = _train_since.get(npc_id, 0) + 1
        if _train_since[npc_id] >= _TRAIN_MIN:
            _train_since[npc_id] = 0
            snapshot = list(lst)  # cópia para treinar fora do lock e da request

    if snapshot is None:
        return

    npc = _npc_configs.get(npc_id)
    if not npc:
        return
    engine: IntentEngine = npc['_engine']

    def _bg():
        try:
            if engine.train(snapshot):
                log.info(f'N3 treinado para {npc_id} com {len(snapshot)} amostras')
        except Exception as e:
            log.warning(f'treino N3 falhou [{npc_id}]: {e}')

    threading.Thread(target=_bg, daemon=True, name=f'n3-train-{npc_id}').start()


# ============================================================
# CAP DE LLM POR PERSONAGEM (anti-custo — enforcement real, §15)
# ============================================================

_llm_usage: "OrderedDict[object, dict]" = OrderedDict()  # char_id → tetos (LRU capado)
_llm_usage_lock = threading.Lock()
_LLM_USAGE_CAP  = 4096                 # teto de chars rastreados (evict LRU do mais antigo)

def _llm_allowed(char_id, per_min: int, per_day: int) -> bool:
    """True se o char ainda pode chamar o LLM dentro dos tetos (0 = sem teto)."""
    if not char_id or (not per_min and not per_day):
        return True
    now = time.time()
    with _llm_usage_lock:
        u = _llm_usage.get(char_id)
        if u is None:
            u = {'min_ts': now, 'min_n': 0, 'day_ts': now, 'day_n': 0}
            _llm_usage[char_id] = u
            if len(_llm_usage) > _LLM_USAGE_CAP:
                _llm_usage.popitem(last=False)  # descarta o char mais antigo
        else:
            _llm_usage.move_to_end(char_id)     # LRU touch
        if now - u['min_ts'] >= 60:
            u['min_ts'] = now; u['min_n'] = 0
        if now - u['day_ts'] >= 86400:
            u['day_ts'] = now; u['day_n'] = 0
        if per_min and u['min_n'] >= per_min:
            return False
        if per_day and u['day_n'] >= per_day:
            return False
        u['min_n'] += 1
        u['day_n'] += 1
        return True


# ============================================================
# MEMÓRIA CURTA DE SESSÃO (ring buffer efêmero por char×npc)
# ============================================================

def _session_key(char_id, npc_id) -> str:
    return f'{char_id}:{npc_id}'


def _session_get(char_id, npc_id) -> list:
    """Retorna as trocas recentes [{intent, npc_text}] (cópia) desta sessão."""
    with _session_lock:
        dq = _session_ctx.get(_session_key(char_id, npc_id))
        return list(dq) if dq else []


def _session_push(char_id, npc_id, intent: str, npc_text: str):
    """Registra a troca atual — só (intent, resposta do NPC), nunca a fala crua do jogador."""
    if not char_id or not npc_text:
        return
    k = _session_key(char_id, npc_id)
    with _session_lock:
        dq = _session_ctx.get(k)
        if dq is None:
            dq = deque(maxlen=_SESSION_TURNS)
            _session_ctx[k] = dq
            if len(_session_ctx) > _SESSION_CAP:
                _session_ctx.popitem(last=False)  # evict o par mais antigo
        else:
            _session_ctx.move_to_end(k)
        dq.append({'intent': str(intent or 'unknown'), 'npc_text': str(npc_text)[:200]})


def _session_clear(char_id):
    """Descarta toda a memória curta do char (playerDropped via /session_end)."""
    prefix = f'{char_id}:'
    with _session_lock:
        for k in [key for key in _session_ctx if key.startswith(prefix)]:
            del _session_ctx[k]


def _npc_for_prompt(npc: dict, meta: dict) -> dict:
    """Identidade (nome/profissao/idioma) da config Lua sobrescreve o JSON (L-04: Lua é dono)."""
    if not meta:
        return npc
    merged = dict(npc)
    for k in ('nome', 'profissao', 'idioma'):
        if meta.get(k):
            merged[k] = meta[k]
    return merged


# ============================================================
# ROTAS
# ============================================================

@app.route('/health')
def health():
    # instancia (singleton) e reporta os provedores conhecidos — diz ao dono
    # exatamente qual IA está pronta (chave presente/SDK instalado).
    def _pstat(getter, names):
        out = {}
        for n in names:
            p = getter(n)
            out[n] = p.stats() if p else None
        return out
    return jsonify({
        'ok':      True,
        'service': 'vhub_npcai',
        'npcs':    list(_npc_configs.keys()),
        'stt':     _WHISPER_BACKEND,
        'llm':     _pstat(get_llm, ('gemini', 'openai')),
        'tts':     _pstat(get_tts, ('sapi', 'openai')),
        'cache':   _audio_cache.stats(),
    })


@app.route('/prewarm_name', methods=['POST'])
def prewarm_name():
    data       = request.get_json(force=True) or {}
    npc_id     = data.get('npc_id', '')
    charname   = data.get('char_name', '')
    voice_spec = data.get('voice', _DEFAULT_VOICE)  # voz resolvida do NPC (config Lua)
    if not npc_id or not charname:
        return jsonify({'ok': False, 'err': 'missing_params'}), 400
    npc = _npc_configs.get(npc_id)
    if not npc:
        return jsonify({'ok': False, 'err': 'npc_unknown'}), 404

    def _prewarm():
        if not _audio_cache.get_name(npc_id, charname):
            wav = _tts(charname, voice_spec)
            if wav:
                _audio_cache.put_name(npc_id, charname, wav)

    threading.Thread(target=_prewarm, daemon=True).start()
    return jsonify({'ok': True})


@app.route('/config', methods=['POST'])
def config():
    """
    Recebe chaves de API do servidor Lua (convar → loopback) e re-inicializa os
    provedores. Loga só os NOMES alterados, NUNCA o valor. Loopback-only.
    Corpo: { gemini_key?, openai_key? }
    """
    data = request.get_json(force=True) or {}
    changed = []
    gk = (data.get('gemini_key') or '').strip()
    ok = (data.get('openai_key') or '').strip()
    if gk:
        os.environ['GEMINI_API_KEY'] = gk; changed.append('gemini')
    if ok:
        os.environ['OPENAI_API_KEY'] = ok; changed.append('openai')
    if changed:
        reset_llm_registry(); reset_tts_registry()  # re-init com as chaves novas
        log.info(f'[config] chaves de IA atualizadas: {changed}')
    return jsonify({'ok': True, 'set': changed})


@app.route('/reload_npcs', methods=['POST'])
def reload_npcs():
    _load_npc_configs()
    return jsonify({'ok': True, 'npcs': list(_npc_configs.keys())})


@app.route('/session_end', methods=['POST'])
def session_end():
    """Descarta a memória curta efêmera do char (chamado no playerDropped do servidor)."""
    data = request.get_json(force=True) or {}
    try:
        char_id = max(0, int(data.get('char_id', 0)))
    except (TypeError, ValueError):
        char_id = 0
    if char_id:
        _session_clear(char_id)
    return jsonify({'ok': True})


@app.route('/thinking_audio/<npc_id>', methods=['GET'])
def thinking_audio(npc_id: str):
    """Retorna uma frase de pensamento aleatória pré-sintetizada para o NPC."""
    npc_id = npc_id[:48]
    with _thinking_lock:
        wavs = _thinking_cache.get(npc_id, [])
    if not wavs:
        return jsonify({'ok': False, 'err': 'thinking_not_ready'}), 503
    import random
    wav = random.choice(wavs)
    audio_b64 = _audio_para_transporte(wav)
    if not audio_b64:
        return jsonify({'ok': False, 'err': 'transport_fail'}), 500
    return jsonify({'ok': True, 'audio_b64': audio_b64})


@app.route('/converse', methods=['POST'])
def converse():
    """
    Corpo: { char_id, char_name, npc_id, lang, audio(b64 webm), memory, ai }
      ai = { llm{provider,model,max_tokens,temperature}, voice{provider,...}, stt{language} }
    Resposta: { ok, stage, intent, text, audio_b64, stt_text, memory_delta }
    """
    t_start = time.monotonic()
    data = request.get_json(force=True) or {}
    if not isinstance(data, dict):
        return jsonify({'ok': False, 'err': 'payload_invalid'}), 400

    npc_id = data.get('npc_id', '')
    if not isinstance(npc_id, str):
        npc_id = ''
    npc_id = npc_id[:48]

    try:
        char_id = max(0, int(data.get('char_id', 0)))
    except (TypeError, ValueError):
        char_id = 0

    char_name = data.get('char_name', 'Jogador')
    char_name = str(char_name)[:64] if char_name is not None else 'Jogador'

    # json.encode do FiveM serializa nil como null; tratar None como ausente
    _audio_raw  = data.get('audio')
    audio_b64   = _audio_raw if isinstance(_audio_raw, str) and _audio_raw else ''

    _dt_raw     = data.get('direct_text')
    direct_text = (_dt_raw if isinstance(_dt_raw, str) else '').strip()[:300]

    interrupted = bool(data.get('interrupted'))

    memory = data.get('memory') or {}
    if not isinstance(memory, dict):
        memory = {}

    # ── config de IA + identidade resolvidas pela camada Lua (autoridade) ──
    ai = data.get('ai') or {}
    ai = ai if isinstance(ai, dict) else {}
    meta       = data.get('meta') or {}
    meta = meta if isinstance(meta, dict) else {}
    llm_spec = ai.get('llm') or {}
    llm_spec = llm_spec if isinstance(llm_spec, dict) else {}
    voice_spec = ai.get('voice') or _DEFAULT_VOICE
    voice_spec = voice_spec if isinstance(voice_spec, dict) else _DEFAULT_VOICE
    stt_spec = ai.get('stt') or {}
    stt_spec = stt_spec if isinstance(stt_spec, dict) else {}
    language   = stt_spec.get('language') or data.get('lang') or 'pt'

    # validação básica — aceita áudio OU texto direto
    if not npc_id or (not audio_b64 and not direct_text):
        log.warning('missing_params: npc_id=%r audio_len=%d dt_len=%d',
                    npc_id, len(audio_b64), len(direct_text))
        return jsonify({'ok': False, 'err': 'missing_params'}), 400

    npc = _npc_configs.get(npc_id)
    if not npc:
        return jsonify({'ok': False, 'err': 'npc_unknown'}), 404

    # ── STT ou texto direto ──────────────────────────────────
    if direct_text:
        # intenção pré-definida via target — skip STT
        stt_text = direct_text
    else:
        wav_bytes = _decode_audio(audio_b64)
        if not wav_bytes:
            return jsonify({'ok': False, 'err': 'audio_decode_fail'}), 422
        stt_text = _transcribe_bytes(wav_bytes, language)
        if not stt_text.strip():
            return jsonify({'ok': True, 'stage': 'stt_empty', 'intent': 'unknown',
                            'text': '', 'audio_b64': '', 'stt_text': ''})

    # ── reconhecimento de intenção (cascade N1→N2→N3→LLM) ─────
    engine: IntentEngine = npc['_engine']
    intent, confidence, stage = engine.recognize(stt_text, memory=memory)

    response_text = ''
    audio_b64_out = ''
    memory_delta  = {}

    if stage == 'gemini' or intent is None:
        # MISS real → provedor de LLM (Gemini padrão / OpenAI futuro / none), com teto anti-custo
        per_min = int(llm_spec.get('per_min_cap_per_char', 0) or 0)
        per_day = int(llm_spec.get('daily_cap_per_char', 0) or 0)
        llm = get_llm(llm_spec.get('provider', 'gemini'))
        if llm and _llm_allowed(char_id, per_min, per_day):
            history = _session_get(char_id, npc_id)  # continuidade dentro da sessão
            llm_text = llm.ask(_npc_for_prompt(npc, meta), stt_text, memory, llm_spec,
                               history=history, interrupted=interrupted)
        else:
            llm_text = None  # sem provedor OU teto atingido → fallback (fail-closed)
        if llm_text:
            response_text = llm_text
            stage         = 'llm'
            intent        = 'llm'
            wav_out = _tts(llm_text, voice_spec)
            if wav_out:
                _audio_cache.put(npc_id, f'llm_{hash(llm_text) & 0xFFFF}', wav_out)
                audio_b64_out = _audio_para_transporte(wav_out)
        else:
            # LLM indisponível/breaker → fallback cacheável (fail-closed, nunca trava)
            fb_text = npc.get('respostas', {}).get('fallback_text', 'Hmm, interessante.')
            response_text = fb_text
            stage         = 'fallback'
            intent        = 'unknown'
            wav_out = _tts(fb_text, voice_spec)
            if wav_out:
                audio_b64_out = _audio_para_transporte(wav_out)
    else:
        # intenção reconhecida — resposta do config com variante de memória
        response_text, wav_out, memory_delta = _pick_response(npc, intent, memory, voice_spec, char_name)
        if wav_out:
            audio_b64_out = _audio_para_transporte(wav_out)
        # acumula sample para treino N3
        _accumulate_sample(npc_id, stt_text, intent)

    # incrementa visitas e define marcos — sempre (qualquer intenção reconhecida)
    if intent not in ('unknown', None):
        visit_delta = _compute_visit_delta(memory)
        memory_delta = {**visit_delta, **memory_delta}  # intent delta tem prioridade

    # registra a troca na memória curta de sessão (só intent + resposta do NPC)
    if response_text:
        _session_push(char_id, npc_id, intent, response_text)

    elapsed = round((time.monotonic() - t_start) * 1000)
    log.info(f'[{npc_id}] char={char_id} intent={intent} stage={stage} {elapsed}ms')

    return jsonify({
        'ok':           True,
        'stage':        stage,
        'intent':       intent or 'unknown',
        'text':         response_text,
        'stt_text':     stt_text,
        'audio_b64':    audio_b64_out,
        'memory_delta': memory_delta,
        'elapsed_ms':   elapsed,
    })


# ============================================================
# BOOT
# ============================================================

if __name__ == '__main__':
    _load_npc_configs()
    _load_whisper()
    _start_stt_worker()
    _prewarm_thinking()
    log.info(f'sidecar vhub_npcai ouvindo em {HOST}:{PORT}')
    serve(
        app,
        host=HOST,
        port=PORT,
        threads=4,
        connection_limit=32,
        channel_timeout=60,
        max_request_body_size=512 * 1024,
    )
