"""
vhub_npcai - Servidor Whisper + TTS para NPC AI
/transcribe  — audio -> texto  (STT, Whisper)
/speak       — texto -> audio  (TTS, SAPI via subprocess isolado)
/            — UI de teste no browser

Arquitetura de concorrência:
  STT (Whisper): não é thread-safe → worker thread único + queue serial.
  TTS (SAPI):    cada chamada roda em subprocess Python isolado (COM fresco).
                 Semáforo limita subprocessos simultâneos. Flask processa as
                 chamadas em suas próprias worker threads normalmente.
"""

import io
import os
import queue
import subprocess
import sys
import tempfile
import threading
import logging
from flask import Flask, request, jsonify, send_file, send_from_directory

import whisper

# ============================================================
# CONFIGURACAO
# ============================================================

PORT       = int(os.environ.get("WHISPER_PORT", 7512))
MODEL_SIZE = os.environ.get("WHISPER_MODEL", "base")
LOG_LEVEL  = os.environ.get("LOG_LEVEL", "INFO")

# Máximo de subprocessos TTS simultâneos (SAPI é leve em CPU, mas spawns custam memória)
TTS_MAX_CONCURRENT = int(os.environ.get("TTS_MAX_CONCURRENT", 16))

logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("vhub_whisper")

app = Flask(__name__, static_folder="static")

# Python 3.12 path — mesmo executável que roda o server
_PYTHON = sys.executable


# ============================================================
# STT — fila serial (Whisper não é thread-safe)
# ============================================================

_stt_queue = queue.Queue()


class _Job:
    """Empacota tarefa + evento de conclusão para comunicação inter-thread."""
    def __init__(self, payload):
        self.payload = payload
        self.result  = None
        self.error   = None
        self.done    = threading.Event()


def _stt_worker():
    """Thread única que processa todos os jobs de Whisper em sequência."""
    log.info(f"STT worker iniciado (modelo={MODEL_SIZE})")
    model = whisper.load_model(MODEL_SIZE)
    log.info(f"Modelo '{MODEL_SIZE}' carregado. Servidor pronto na porta {PORT}.")

    while True:
        job = _stt_queue.get()
        if job is None:
            break
        try:
            tmp_path, opts = job.payload
            job.result = model.transcribe(tmp_path, **opts)
        except Exception as e:
            job.error = e
        finally:
            job.done.set()
            _stt_queue.task_done()


threading.Thread(target=_stt_worker, daemon=True, name="stt-worker").start()


# ============================================================
# TTS — subprocess isolado por chamada (evita travamento COM)
# ============================================================

# Script mínimo que roda dentro do subprocess — sem imports pesados
_TTS_SUBPROCESS_SCRIPT = """\
import sys, pyttsx3
text, lang, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
VOICES = {'pt': 'Microsoft Maria Desktop', 'en': 'Microsoft Zira Desktop'}
engine = pyttsx3.init()
engine.setProperty('rate', 160)
target = VOICES.get(lang, VOICES.get('pt', ''))
for v in engine.getProperty('voices'):
    if target and target in v.name:
        engine.setProperty('voice', v.id)
        break
engine.save_to_file(text, out_path)
engine.runAndWait()
engine.stop()
"""

# Semáforo limita subprocessos TTS simultâneos
_tts_sem = threading.Semaphore(TTS_MAX_CONCURRENT)


def _synthesize(text: str, lang: str) -> bytes:
    """Sintetiza texto em WAV via subprocess isolado. Thread-safe e sem travamento COM."""
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
        tmp_path = tmp.name

    try:
        with _tts_sem:
            result = subprocess.run(
                [_PYTHON, "-c", _TTS_SUBPROCESS_SCRIPT, text, lang, tmp_path],
                timeout=30,
                capture_output=True,
            )

        if result.returncode != 0:
            err = result.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"TTS subprocess falhou (rc={result.returncode}): {err}")

        with open(tmp_path, "rb") as fh:
            return fh.read()

    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ============================================================
# ROTAS
# ============================================================

@app.route("/")
def index():
    return send_from_directory(os.path.dirname(__file__), "ui.html")


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "ok":        True,
        "model":     MODEL_SIZE,
        "stt_queue": _stt_queue.qsize(),
        "tts_mode":  "subprocess",
        "tts_max":   TTS_MAX_CONCURRENT,
    })


@app.route("/transcribe", methods=["POST"])
def transcribe():
    """Recebe audio (multipart ou raw bytes) e retorna transcricao JSON."""
    if "file" not in request.files and not request.data:
        return jsonify({"error": "sem audio"}), 400

    language = request.form.get("language", None)
    task     = request.form.get("task", "transcribe")

    suffix = ".wav"
    if "file" in request.files:
        f      = request.files["file"]
        suffix = os.path.splitext(f.filename or "audio.wav")[-1] or ".wav"
        data   = f.read()
    else:
        data = request.data

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(data)
        tmp_path = tmp.name

    try:
        opts = {"task": task}
        if language and language != "auto":
            opts["language"] = language

        job = _Job((tmp_path, opts))
        _stt_queue.put(job)
        job.done.wait()

        if job.error:
            raise job.error

        result = job.result
        return jsonify({
            "ok":       True,
            "text":     result["text"].strip(),
            "language": result.get("language", "?"),
            "segments": [
                {"start": s["start"], "end": s["end"], "text": s["text"].strip()}
                for s in result.get("segments", [])
            ],
        })

    except Exception as e:
        log.exception("Erro na transcricao")
        return jsonify({"ok": False, "error": str(e)}), 500

    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


@app.route("/speak", methods=["POST"])
def speak():
    """Recebe JSON {text, lang} e devolve WAV com a fala sintetizada."""
    body = request.get_json(silent=True) or {}
    text = (body.get("text") or request.form.get("text", "")).strip()
    lang = (body.get("lang") or request.form.get("lang", "pt")).strip()

    if not text:
        return jsonify({"error": "sem texto"}), 400

    try:
        audio_bytes = _synthesize(text, lang)
        return send_file(
            io.BytesIO(audio_bytes),
            mimetype="audio/wav",
            as_attachment=False,
            download_name="fala.wav",
        )

    except Exception as e:
        log.exception("Erro no TTS")
        return jsonify({"ok": False, "error": str(e)}), 500


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=PORT, debug=False, threaded=True)
