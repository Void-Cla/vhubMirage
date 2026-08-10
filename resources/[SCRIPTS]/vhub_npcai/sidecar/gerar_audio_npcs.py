"""
gerar_audio_npcs.py — gerador offline de áudio pré-sintetizado para NPCs.

Roda ANTES de subir o sidecar (ou a qualquer momento). Não precisa de Flask,
token, sidecar rodando ou FiveM ativo. Usa o mesmo SapiTTS do server.py.

Saída:
  nui/audio/
    murmur_generic_1..5.wav          ← murmúrios genéricos (tapam silêncio imediato)
    thinking/<npc_id>/
      thinking_00.wav .. N.wav       ← frases de "estou pensando" do NPC
    greet/<npc_id>/
      greet_default_00.wav .. N.wav  ← segmentos da saudação padrão (resposta fria mais comum)

Uso:
  cd resources/[SCRIPTS]/vhub_npcai
  .venv/Scripts/python sidecar/gerar_audio_npcs.py

  Opções:
    --force          re-gera mesmo se WAV já existe
    --npc jorjao     gera apenas para este NPC
    --sapi-rate 160  velocidade de fala (palavras/min)
    --voice ""       nome da voz SAPI (vazio = padrão do Windows)
"""

from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# ── paths relativos ao script ─────────────────────────────────────────────────
SIDECAR_DIR  = Path(__file__).resolve().parent
RESOURCE_DIR = SIDECAR_DIR.parent
NUI_AUDIO    = RESOURCE_DIR / 'nui' / 'audio'
NPCS_DIR     = SIDECAR_DIR / 'npcs'


# ============================================================
# TTS SAPI (sem depender do providers/tts.py — standalone)
# ============================================================

_SAPI_SCRIPT = r"""
import sys, pyttsx3
engine = pyttsx3.init()
engine.setProperty('rate', int(sys.argv[2]) if len(sys.argv) > 2 else 160)
if len(sys.argv) > 4 and sys.argv[4]:
    for v in engine.getProperty('voices'):
        if sys.argv[4].lower() in (v.name or '').lower():
            engine.setProperty('voice', v.id)
            break
engine.save_to_file(sys.argv[1], sys.argv[3] if len(sys.argv) > 3 else 'out.wav')
engine.runAndWait()
"""


def tts(text: str, dest: Path, rate: int = 160, voice: str = '') -> bool:
    """Sintetiza `text` em WAV salvo em `dest`. Retorna True se gerou arquivo."""
    if not text or not text.strip():
        return False

    script_file = tempfile.NamedTemporaryFile(
        mode='w', suffix='.py', delete=False, encoding='utf-8'
    )
    script_file.write(_SAPI_SCRIPT)
    script_file.close()

    tmp_wav = dest.with_suffix('.tmp.wav')
    try:
        result = subprocess.run(
            [sys.executable, script_file.name, text, str(rate), str(tmp_wav), voice],
            timeout=15,
            capture_output=True,
        )
        if result.returncode != 0:
            stderr = result.stderr.decode('utf-8', errors='replace').strip()
            if stderr:
                print(f'  [sapi stderr] {stderr[:200]}')

        if tmp_wav.exists() and tmp_wav.stat().st_size > 0:
            tmp_wav.replace(dest)
            return True
        return False
    except subprocess.TimeoutExpired:
        print(f'  [timeout] SAPI não respondeu em 15s para: {text!r}')
        return False
    except Exception as e:
        print(f'  [erro] {e}')
        return False
    finally:
        for p in (script_file.name, str(tmp_wav)):
            try:
                os.unlink(p)
            except OSError:
                pass


# ============================================================
# MURMÚRIOS GENÉRICOS
# ============================================================

MURMUR_TEXTOS = [
    'Hmm...',
    'Deixa eu pensar...',
    'É...',
    'Um segundo...',
    'Aha...',
]


def gerar_murmurios(force: bool, rate: int, voice: str) -> None:
    print('\n[murmúrios genéricos]')
    NUI_AUDIO.mkdir(parents=True, exist_ok=True)

    for i, texto in enumerate(MURMUR_TEXTOS, start=1):
        dest = NUI_AUDIO / f'murmur_generic_{i}.wav'
        if dest.exists() and not force:
            print(f'  skip (já existe): {dest.name}')
            continue
        ok = tts(texto, dest, rate=rate, voice=voice)
        status = 'OK' if ok else 'FAIL'
        print(f'  [{status}] {dest.name}')


# ============================================================
# THINKING FRASES (por NPC)
# ============================================================

def gerar_thinking(npc: dict, force: bool, rate: int, voice: str) -> None:
    npc_id = npc.get('id', 'unknown')
    frases = npc.get('thinking_frases') or []
    if not frases:
        print(f'  sem thinking_frases em {npc_id}')
        return

    dest_dir = NUI_AUDIO / 'thinking' / npc_id
    dest_dir.mkdir(parents=True, exist_ok=True)

    for i, frase in enumerate(frases):
        dest = dest_dir / f'thinking_{i:02d}.wav'
        if dest.exists() and not force:
            print(f'  skip: {dest.name}')
            continue
        ok = tts(str(frase)[:120], dest, rate=rate, voice=voice)
        status = 'OK' if ok else 'FAIL'
        print(f'  [{status}] {dest.name}  "{frase}"')


# ============================================================
# SAUDAÇÕES PRÉ-CACHEADAS (segmentos do variant "default" de "saudacao")
# ============================================================

def gerar_saudacao(npc: dict, force: bool, rate: int, voice: str) -> None:
    npc_id = npc.get('id', 'unknown')
    respostas = npc.get('respostas') or {}
    saudacao  = respostas.get('saudacao') or {}

    # tenta primeiro o variant 'default', cai no primeiro variant disponível
    variants = saudacao.get('variants') or {}
    segmentos = None
    for key in ('default', *variants.keys()):
        v = variants.get(key) or {}
        segs = v.get('segments') or []
        if segs:
            segmentos = segs
            break

    # fallback: 'saudacao' pode ter 'segments' diretamente (sem variants)
    if segmentos is None:
        segmentos = saudacao.get('segments') or []

    if not segmentos:
        print(f'  sem segmentos de saudação em {npc_id}')
        return

    dest_dir = NUI_AUDIO / 'greet' / npc_id
    dest_dir.mkdir(parents=True, exist_ok=True)

    # cada "segment" é uma lista de frases alternativas; pega a primeira de cada
    for i, seg in enumerate(segmentos):
        texto = seg[0] if isinstance(seg, list) and seg else str(seg)
        dest  = dest_dir / f'greet_default_{i:02d}.wav'
        if dest.exists() and not force:
            print(f'  skip: {dest.name}')
            continue
        ok = tts(texto[:200], dest, rate=rate, voice=voice)
        status = 'OK' if ok else 'FAIL'
        print(f'  [{status}] {dest.name}')


# ============================================================
# ENTRY POINT
# ============================================================

def main() -> None:
    parser = argparse.ArgumentParser(description='Gera WAVs offline para NPCs do vhub_npcai')
    parser.add_argument('--force',     action='store_true', help='re-gera mesmo se WAV existe')
    parser.add_argument('--npc',       default=None,        help='gera apenas este npc_id')
    parser.add_argument('--sapi-rate', type=int, default=160, dest='rate', help='velocidade SAPI (palavras/min)')
    parser.add_argument('--voice',     default='',          help='nome da voz SAPI (vazio=padrão)')
    args = parser.parse_args()

    # valida pyttsx3
    try:
        import pyttsx3  # noqa: F401
    except ImportError:
        print('[ERRO] pyttsx3 não encontrado. Rode: .venv/Scripts/pip install pyttsx3')
        sys.exit(1)

    print(f'Saída: {NUI_AUDIO}')
    print(f'Rate:  {args.rate} palavras/min  |  Voice: {args.voice or "(padrão Windows)"}')

    # murmúrios genéricos
    gerar_murmurios(force=args.force, rate=args.rate, voice=args.voice)

    # NPCs
    if not NPCS_DIR.exists():
        print(f'[AVISO] pasta npcs/ não encontrada: {NPCS_DIR}')
        return

    npc_files = sorted(NPCS_DIR.glob('*.json'))
    if not npc_files:
        print('[AVISO] nenhum NPC .json encontrado')
        return

    for f in npc_files:
        try:
            npc = json.loads(f.read_text(encoding='utf-8'))
        except Exception as e:
            print(f'[ERRO] {f.name}: {e}')
            continue

        npc_id = npc.get('id', f.stem)
        if args.npc and npc_id != args.npc:
            continue

        enabled = npc.get('enabled', True)
        print(f'\n[NPC: {npc_id}]{"" if enabled else "  (disabled — gerando mesmo assim)"}')

        print('  -- thinking frases')
        gerar_thinking(npc, force=args.force, rate=args.rate, voice=args.voice)

        print('  -- saudacao padrao')
        gerar_saudacao(npc, force=args.force, rate=args.rate, voice=args.voice)

    print('\n[concluído]')
    print(f'Arquivos em: {NUI_AUDIO}')
    print('Próximo passo: restart vhub_npcai no servidor FiveM.')


if __name__ == '__main__':
    main()
