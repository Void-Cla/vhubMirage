"""
Teste do servidor Whisper — gera amostras de audio sintetico e envia para transcricao.
Uso: python test_whisper.py [url_servidor]
"""

import sys
import io
import wave
import struct
import math
import urllib.request
import urllib.parse
import json
import os

SERVER = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:7512"


# ============================================================
# GERACAO DE AUDIO SINTETICO (tom simples para checar pipeline)
# ============================================================

def gerar_tom_wav(freq_hz=440, duracao_s=1.0, sample_rate=16000):
    """Gera WAV mono de tom puro — util para testar o pipeline sem mic."""
    samples = [
        int(32767 * math.sin(2 * math.pi * freq_hz * t / sample_rate))
        for t in range(int(sample_rate * duracao_s))
    ]
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    return buf.getvalue()


# ============================================================
# CHAMADA AO SERVIDOR
# ============================================================

def transcrever(audio_bytes, filename="audio.wav", language=None):
    boundary = "----WhisperBoundary"
    body_parts = []

    # campo "file"
    body_parts.append(f"--{boundary}\r\n".encode())
    body_parts.append(
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode()
    )
    body_parts.append(b"Content-Type: audio/wav\r\n\r\n")
    body_parts.append(audio_bytes)
    body_parts.append(b"\r\n")

    # campo "language" opcional
    if language:
        body_parts.append(f"--{boundary}\r\n".encode())
        body_parts.append(b'Content-Disposition: form-data; name="language"\r\n\r\n')
        body_parts.append(language.encode())
        body_parts.append(b"\r\n")

    body_parts.append(f"--{boundary}--\r\n".encode())

    body = b"".join(body_parts)

    req = urllib.request.Request(
        f"{SERVER}/transcribe",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


# ============================================================
# TESTES
# ============================================================

def testar_health():
    try:
        with urllib.request.urlopen(f"{SERVER}/health", timeout=5) as r:
            data = json.loads(r.read().decode())
            print(f"[HEALTH] ok={data.get('ok')}  model={data.get('model')}")
            return True
    except Exception as e:
        print(f"[HEALTH] FALHOU: {e}")
        return False


def testar_audio_sintetico():
    """Envia tom puro — Whisper deve retornar texto vazio ou musica."""
    print("\n[TESTE] Audio sintetico (tom 440 Hz, 2s)...")
    wav = gerar_tom_wav(440, 2.0)
    res = transcrever(wav)
    texto = res.get("text", "")
    lang  = res.get("language", "?")
    print(f"  texto    : '{texto}'")
    print(f"  language : {lang}")
    print(f"  ok       : {res.get('ok')}")


def testar_arquivo_real(caminho, lang_hint=None):
    """Envia arquivo de audio real para transcricao."""
    if not os.path.exists(caminho):
        print(f"[SKIP] Arquivo nao encontrado: {caminho}")
        return
    print(f"\n[TESTE] Arquivo: {caminho}  (lang_hint={lang_hint})")
    with open(caminho, "rb") as fh:
        dados = fh.read()
    res = transcrever(dados, filename=os.path.basename(caminho), language=lang_hint)
    print(f"  texto    : '{res.get('text')}'")
    print(f"  language : {res.get('language')}")
    print(f"  ok       : {res.get('ok')}")
    if not res.get("ok"):
        print(f"  erro     : {res.get('error')}")


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":
    print(f"Servidor alvo: {SERVER}\n")

    if not testar_health():
        print("Servidor nao esta rodando. Inicie com: start_whisper.bat")
        sys.exit(1)

    # Teste basico com audio sintetico
    testar_audio_sintetico()

    # Testes com arquivos reais (coloque WAV/MP3 aqui para testar PT-BR e EN)
    # Exemplo: python test_whisper.py http://127.0.0.1:7512
    #   Coloque sample_ptbr.wav e sample_en.wav na pasta vhub_npcai/
    testar_arquivo_real("sample_ptbr.wav", lang_hint="pt")
    testar_arquivo_real("sample_en.wav",   lang_hint="en")

    print("\nTeste concluido.")
