"""
vhub_npcai — Teste de Gargalo
Mede capacidade, latência e uso de recursos sob carga simultânea.
Testa /transcribe (Whisper/STT) e /speak (TTS) com 10, 40 e 80 workers.

Uso: python stress_test.py [url_servidor]
"""

import time
import json
import threading
import statistics
import psutil
import os
import sys
import urllib.request
import math
from concurrent.futures import ThreadPoolExecutor, as_completed, wait, FIRST_COMPLETED
from datetime import datetime

# Garante UTF-8 no terminal Windows (box-drawing chars)
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SERVER      = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:7512"
TIMEOUT_STT = 180   # Whisper pode demorar em fila longa
TIMEOUT_TTS = 60    # TTS serial — se >60s é claramente travado


# ============================================================
# MONITOR DE RECURSOS (amostragem a 4 Hz)
# ============================================================

class ResourceMonitor:
    """Coleta CPU global, CPU do processo, RAM global e RAM do processo."""

    def __init__(self, pid=None):
        self._pid     = pid
        self._proc    = None
        if pid:
            try:
                self._proc = psutil.Process(pid)
            except psutil.NoSuchProcess:
                pass
        self.samples  = []
        self._running = False
        self._thread  = None

    def start(self):
        self.samples  = []
        self._running = True
        # warmup — psutil cpu_percent precisa de uma leitura inicial
        psutil.cpu_percent(interval=None)
        if self._proc:
            self._proc.cpu_percent(interval=None)
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)

    def _loop(self):
        while self._running:
            s = {
                "ts":          time.time(),
                "cpu_global":  psutil.cpu_percent(interval=None),
                "ram_used_mb": psutil.virtual_memory().used / 1_048_576,
                "ram_pct":     psutil.virtual_memory().percent,
            }
            if self._proc:
                try:
                    s["proc_cpu_pct"] = self._proc.cpu_percent(interval=None)
                    s["proc_ram_mb"]  = self._proc.memory_info().rss / 1_048_576
                    s["proc_threads"] = self._proc.num_threads()
                except psutil.NoSuchProcess:
                    pass
            self.samples.append(s)
            time.sleep(0.25)

    def summary(self):
        if not self.samples:
            return {}
        def peak(key):  return round(max(s[key] for s in self.samples if key in s), 1)
        def avg(key):   return round(statistics.mean(s[key] for s in self.samples if key in s), 1)
        r = {
            "cpu_global_avg":  avg("cpu_global"),
            "cpu_global_peak": peak("cpu_global"),
            "ram_used_avg_mb": avg("ram_used_mb"),
            "ram_used_peak_mb": peak("ram_used_mb"),
        }
        if any("proc_cpu_pct" in s for s in self.samples):
            r["proc_cpu_avg"]  = avg("proc_cpu_pct")
            r["proc_cpu_peak"] = peak("proc_cpu_pct")
            r["proc_ram_mb"]   = peak("proc_ram_mb")
            r["proc_threads"]  = peak("proc_threads")
        return r


# ============================================================
# FUNÇÕES DE REQUISIÇÃO
# ============================================================

def _post_multipart(endpoint, fields, file_field, file_bytes, file_name, file_mime):
    boundary = "----VHubStress"
    parts = []
    # arquivo
    parts += [
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_name}"\r\n'.encode(),
        f"Content-Type: {file_mime}\r\n\r\n".encode(),
        file_bytes,
        b"\r\n",
    ]
    # campos extras
    for k, v in (fields or {}).items():
        parts += [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode(),
            v.encode(),
            b"\r\n",
        ]
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    req  = urllib.request.Request(
        f"{SERVER}{endpoint}", data=body, method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT_STT) as r:
        return json.loads(r.read().decode())


def call_transcribe(audio_bytes, lang):
    t0 = time.perf_counter()
    try:
        fields = {"language": lang} if lang else {}
        data = _post_multipart("/transcribe", fields, "file", audio_bytes, "audio.wav", "audio/wav")
        ok = data.get("ok", False)
        return time.perf_counter() - t0, ok, None, data.get("text", "")
    except Exception as e:
        return time.perf_counter() - t0, False, str(e)[:120], ""


def call_speak(text, lang):
    t0 = time.perf_counter()
    try:
        body = json.dumps({"text": text, "lang": lang}).encode()
        req  = urllib.request.Request(
            f"{SERVER}/speak", data=body, method="POST",
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT_TTS) as r:
            size = len(r.read())
        ok = size > 500
        return time.perf_counter() - t0, ok, None, f"{size}B"
    except Exception as e:
        return time.perf_counter() - t0, False, str(e)[:120], ""


# ============================================================
# RUNNER DE BATCH
# ============================================================

def run_batch(n_workers, task_fn, monitor):
    """
    Dispara n_workers chamadas simultâneas de task_fn.
    Retorna dict com latências, erros, recursos e throughput.
    """
    monitor.start()
    t_start = time.perf_counter()

    with ThreadPoolExecutor(max_workers=n_workers) as pool:
        futures = [pool.submit(task_fn) for _ in range(n_workers)]
        done    = [f.result() for f in as_completed(futures)]

    wall = time.perf_counter() - t_start
    monitor.stop()

    latencies = [r[0] for r in done]
    ok_list   = [r[1] for r in done]
    errs      = [r[2] for r in done if r[2]]

    lat_sorted = sorted(latencies)

    def pct(p):
        idx = min(int(math.ceil(len(lat_sorted) * p / 100)) - 1, len(lat_sorted) - 1)
        return round(lat_sorted[max(idx, 0)], 3)

    return {
        "n":          n_workers,
        "ok":         sum(ok_list),
        "errors":     len(errs),
        "error_pct":  round(100 * len(errs) / n_workers, 1),
        "wall_s":     round(wall, 2),
        "throughput": round(n_workers / wall, 2),   # req/s completadas
        "lat_min":    round(min(latencies), 3),
        "lat_avg":    round(statistics.mean(latencies), 3),
        "lat_median": round(statistics.median(latencies), 3),
        "lat_p95":    pct(95),
        "lat_p99":    pct(99),
        "lat_max":    round(max(latencies), 3),
        "lat_stdev":  round(statistics.stdev(latencies) if len(latencies) > 1 else 0, 3),
        "resources":  monitor.summary(),
        "err_samples": errs[:5],
    }


# ============================================================
# FORMATAÇÃO
# ============================================================

def _bar(value, max_val, width=20):
    filled = int(round(width * min(value, max_val) / max_val))
    return "█" * filled + "░" * (width - filled)

def _fmt_lat(s):
    return f"{s:.2f}s" if s < 10 else f"{s:.1f}s"

def print_result(label, r):
    res = r["resources"]
    print(f"\n  ┌─ {label} — {r['n']} simultâneos ─────────────────────────")
    print(f"  │  Sucesso : {r['ok']}/{r['n']}  ({100-r['error_pct']:.0f}%)   "
          f"Erros: {r['errors']}  Wall: {r['wall_s']}s  "
          f"Throughput: {r['throughput']} req/s")
    print(f"  │  Latência│ min={_fmt_lat(r['lat_min'])}  "
          f"avg={_fmt_lat(r['lat_avg'])}  "
          f"p50={_fmt_lat(r['lat_median'])}  "
          f"p95={_fmt_lat(r['lat_p95'])}  "
          f"p99={_fmt_lat(r['lat_p99'])}  "
          f"max={_fmt_lat(r['lat_max'])}")
    if res:
        g_cpu = res.get('cpu_global_peak', 0)
        g_ram = res.get('ram_used_peak_mb', 0)
        p_cpu = res.get('proc_cpu_peak', 0)
        p_ram = res.get('proc_ram_mb', 0)
        print(f"  │  CPU glob│ avg={res.get('cpu_global_avg')}%  "
              f"peak={g_cpu}%  {_bar(g_cpu, 100)}")
        print(f"  │  RAM glob│ peak={g_ram:.0f} MB  "
              f"{_bar(g_ram, psutil.virtual_memory().total/1_048_576)}")
        if p_cpu:
            print(f"  │  Processo│ cpu_peak={p_cpu}%  "
                  f"ram={p_ram:.0f} MB  "
                  f"threads={res.get('proc_threads',0):.0f}")
    if r["err_samples"]:
        print(f"  │  Erros(amostra): {r['err_samples'][:2]}")
    print(f"  └{'─' * 59}")


# ============================================================
# MAIN
# ============================================================

def main():
    PY = "C:/Users/fox/AppData/Local/Programs/Python/Python312/python.exe"

    now = datetime.now()
    print()
    print("╔══════════════════════════════════════════════════════════╗")
    print("║     vhub NPC AI — TESTE DE GARGALO  (stress_test.py)    ║")
    print(f"║     {now.strftime('%Y-%m-%d %H:%M:%S')}                               ║")
    print("╚══════════════════════════════════════════════════════════╝")

    # ── Health check ───────────────────────────────────────────
    try:
        with urllib.request.urlopen(f"{SERVER}/health", timeout=5) as r:
            hd = json.loads(r.read().decode())
        print(f"\nServidor: {SERVER}  modelo={hd.get('model')}  OK")
    except Exception as e:
        print(f"\nSERVIDOR OFFLINE: {e}")
        sys.exit(1)

    # ── PID do servidor ────────────────────────────────────────
    server_pid = None
    for proc in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            cmd = " ".join(proc.info["cmdline"] or [])
            if "server.py" in cmd:
                server_pid = proc.info["pid"]
                break
        except Exception:
            pass
    print(f"PID monitorado : {server_pid or 'não encontrado'}")
    print(f"RAM total      : {psutil.virtual_memory().total / 1_048_576:.0f} MB")
    print(f"Núcleos CPU    : {psutil.cpu_count(logical=False)} físicos / "
          f"{psutil.cpu_count()} lógicos")

    # ── Carregar amostras de áudio ─────────────────────────────
    def load(path):
        if not os.path.exists(path):
            raise FileNotFoundError(f"Arquivo não encontrado: {path}")
        with open(path, "rb") as f:
            return f.read()

    audio_pt = load("sample_ptbr.wav")
    audio_en = load("sample_en.wav")
    print(f"Áudio PT-BR    : {len(audio_pt)/1024:.0f} KB")
    print(f"Áudio EN       : {len(audio_en)/1024:.0f} KB")

    # ── Pré-aquecimento (elimina cold-start do 1º transcribe) ─
    print("\nPré-aquecendo Whisper... ", end="", flush=True)
    call_transcribe(audio_pt, "pt")
    call_transcribe(audio_en, "en")
    print("pronto.")

    resultados = []

    # ──────────────────────────────────────────────────────────
    # BLOCO 1 — /transcribe (Whisper STT)
    # ──────────────────────────────────────────────────────────
    print("\n" + "═" * 62)
    print("  ENDPOINT /transcribe  (Whisper — reconhecimento de fala)")
    print("═" * 62)

    stt_pool = [audio_pt, audio_en] * 40  # 80 entradas alternadas
    stt_langs = ["pt", "en"] * 40
    stt_idx  = [0]
    stt_lock = threading.Lock()

    def fn_stt():
        with stt_lock:
            i = stt_idx[0] % len(stt_pool)
            stt_idx[0] += 1
        return call_transcribe(stt_pool[i], stt_langs[i])

    for n in [10, 40, 80]:
        stt_idx[0] = 0
        print(f"\n  Iniciando {n:>2} workers STT... ", end="", flush=True)
        monitor = ResourceMonitor(server_pid)
        r = run_batch(n, fn_stt, monitor)
        r["endpoint"] = "STT"
        print("concluído.")
        print_result("STT /transcribe", r)
        resultados.append(r)
        if n < 80:
            print(f"  Aguardando 5s para o servidor respirar...")
            time.sleep(5)

    # ──────────────────────────────────────────────────────────
    # BLOCO 2 — /speak (pyttsx3 TTS)
    # ──────────────────────────────────────────────────────────
    print("\n" + "═" * 62)
    print("  ENDPOINT /speak  (TTS — pyttsx3/SAPI síntese de fala)")
    print("═" * 62)

    tts_pool = [
        ("Bem vindo à concessionária vHub, como posso ajudar?", "pt"),
        ("Hello, welcome to the dealership, how can I help you?",  "en"),
        ("Preciso de ajuda com meu veículo, ele está danificado.", "pt"),
        ("Officer, I was just driving around the city.", "en"),
        ("Qual é o preço do modelo esportivo?", "pt"),
        ("Can you show me the fastest car available?", "en"),
    ] * 14   # 84 entradas
    tts_idx  = [0]
    tts_lock = threading.Lock()

    def fn_tts():
        with tts_lock:
            i = tts_idx[0] % len(tts_pool)
            tts_idx[0] += 1
        txt, lg = tts_pool[i]
        return call_speak(txt, lg)

    for n in [10, 40, 80]:
        tts_idx[0] = 0
        print(f"\n  Iniciando {n:>2} workers TTS... ", end="", flush=True)
        monitor = ResourceMonitor(server_pid)
        r = run_batch(n, fn_tts, monitor)
        r["endpoint"] = "TTS"
        print("concluído.")
        print_result("TTS /speak", r)
        resultados.append(r)
        if n < 80:
            print(f"  Aguardando 5s para o servidor respirar...")
            time.sleep(5)

    # ──────────────────────────────────────────────────────────
    # RESUMO FINAL
    # ──────────────────────────────────────────────────────────
    print("\n" + "╔" + "═" * 60 + "╗")
    print("║  RESUMO — TABELA COMPARATIVA                           ║")
    print("╚" + "═" * 60 + "╝")
    print(f"  {'Endpoint':<10} {'N':>4}  {'OK%':>5}  "
          f"{'avg':>7}  {'p95':>7}  {'p99':>7}  "
          f"{'CPU%':>6}  {'RAM MB':>7}  {'RPS':>6}")
    print(f"  {'-'*10} {'-'*4}  {'-'*5}  "
          f"{'-'*7}  {'-'*7}  {'-'*7}  "
          f"{'-'*6}  {'-'*7}  {'-'*6}")
    for r in resultados:
        res    = r["resources"]
        ok_pct = f"{100 - r['error_pct']:.0f}%"
        cpu    = f"{res.get('cpu_global_peak', '?')}%" if res else "?"
        ram    = f"{res.get('ram_used_peak_mb', 0):.0f}" if res else "?"
        print(f"  {r['endpoint']:<10} {r['n']:>4}  {ok_pct:>5}  "
              f"{_fmt_lat(r['lat_avg']):>7}  "
              f"{_fmt_lat(r['lat_p95']):>7}  "
              f"{_fmt_lat(r['lat_p99']):>7}  "
              f"{cpu:>6}  {ram:>7}  "
              f"{r['throughput']:>6}")

    # ──────────────────────────────────────────────────────────
    # DIAGNÓSTICO AUTOMÁTICO
    # ──────────────────────────────────────────────────────────
    print("\n" + "╔" + "═" * 60 + "╗")
    print("║  DIAGNÓSTICO                                           ║")
    print("╚" + "═" * 60 + "╝")

    stt_results = [r for r in resultados if r["endpoint"] == "STT"]
    tts_results = [r for r in resultados if r["endpoint"] == "TTS"]

    for label, rlist in [("STT/Whisper", stt_results), ("TTS/pyttsx3", tts_results)]:
        if not rlist:
            continue
        print(f"\n  [{label}]")
        r10  = next((r for r in rlist if r["n"] == 10),  None)
        r40  = next((r for r in rlist if r["n"] == 40),  None)
        r80  = next((r for r in rlist if r["n"] == 80),  None)
        base = r10["lat_avg"] if r10 else 1

        if r40:
            deg40 = r40["lat_avg"] / base
            print(f"  • 40 workers: latência {deg40:.1f}x a de 10  "
                  f"({'aceitável ✓' if deg40 < 4 else 'degradação severa ✗'})")
        if r80:
            deg80 = r80["lat_avg"] / base
            print(f"  • 80 workers: latência {deg80:.1f}x a de 10  "
                  f"({'aceitável ✓' if deg80 < 8 else 'degradação severa ✗'})")
        if r80 and r80["errors"] > 0:
            print(f"  • ERROS em 80 workers: {r80['errors']} timeout/falhas — "
                  f"limite real está entre 40 e 80")
        if r80:
            cpu80 = r80["resources"].get("cpu_global_peak", 0)
            if cpu80 > 90:
                print(f"  • CPU saturada em 80 workers ({cpu80}%) — "
                      f"gargalo é processamento, não rede")
        any_errs = sum(r["errors"] for r in rlist)
        if any_errs == 0:
            print(f"  • Zero erros em todos os níveis ✓")

    print("\n  RECOMENDAÇÕES PARA PRODUÇÃO:")
    print("  1. Flask dev server é single-process — usar waitress/gunicorn")
    print("     para FiveM produção: pip install waitress")
    print("     comando: waitress-serve --port=7512 server:app")
    print("  2. Whisper CPU é o bottleneck principal — considerar modelo 'tiny'")
    print("     para latência <1s, ou GPU dedicada para 'small'/'medium'")
    print("  3. pyttsx3 tem lock global — limita TTS a ~1 simultâneo real")
    print("     alternativa: edge-tts (async) ou cache de frases fixas de NPC")
    print("  4. Para 200 jogadores: 5-10% usando NPC simultaneamente = 10-20 req/s")
    print("     Modelo 'base' CPU provavelmente aguenta 200 jogadores se NPC é esporádico")

    # ──────────────────────────────────────────────────────────
    # SALVAR JSON
    # ──────────────────────────────────────────────────────────
    ts    = now.strftime("%Y%m%d_%H%M%S")
    fname = f"stress_result_{ts}.json"
    payload = {
        "timestamp":  now.isoformat(),
        "server":     SERVER,
        "model":      hd.get("model"),
        "server_pid": server_pid,
        "system": {
            "ram_total_mb":  psutil.virtual_memory().total // 1_048_576,
            "cpu_cores_phy": psutil.cpu_count(logical=False),
            "cpu_cores_log": psutil.cpu_count(),
        },
        "results": resultados,
    }
    with open(fname, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    print(f"\n  Resultado completo salvo em: {fname}")
    print()

    return payload


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    main()
