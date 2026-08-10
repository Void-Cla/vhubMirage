"""Prepara o ambiente Python local do sidecar de forma atomica e idempotente."""

from __future__ import annotations

import csv
import hashlib
import msvcrt
import os
import secrets
import subprocess
import sys
import time
from pathlib import Path


RECURSO = Path(__file__).resolve().parent.parent
AMBIENTE = RECURSO / ".venv"
PYTHON = AMBIENTE / "Scripts" / "python.exe"
REQUISITOS = Path(__file__).resolve().parent / "requirements.txt"
SELO = AMBIENTE / ".requirements.sha256"
TOKEN = RECURSO / ".sidecar-token"
TRAVA = RECURSO / ".bootstrap.lock"

VERSOES_OBRIGATORIAS = {
    "Flask": "3.1.3",
    "waitress": "3.0.2",
    "faster-whisper": "1.2.1",
    "pydub": "0.25.1",
    "scikit-learn": "1.9.0",
    "numpy": "2.5.1",
    "pyttsx3": "2.99",
    "google-genai": "2.15.0",
    "openai": "2.50.0",
}


def _adquirir_trava(limite_segundos: int = 300):
    arquivo = TRAVA.open("a+b")
    arquivo.seek(0, os.SEEK_END)
    if arquivo.tell() == 0:
        arquivo.write(b"\0")
        arquivo.flush()

    prazo = time.monotonic() + limite_segundos
    while True:
        try:
            arquivo.seek(0)
            msvcrt.locking(arquivo.fileno(), msvcrt.LK_NBLCK, 1)
            return arquivo
        except OSError:
            if time.monotonic() >= prazo:
                arquivo.close()
                raise RuntimeError("tempo esgotado aguardando trava de bootstrap")
            time.sleep(0.25)


def _liberar_trava(arquivo) -> None:
    arquivo.seek(0)
    msvcrt.locking(arquivo.fileno(), msvcrt.LK_UNLCK, 1)
    arquivo.close()


def _sid_usuario() -> str:
    resultado = subprocess.run(
        ["whoami", "/user", "/fo", "csv", "/nh"],
        capture_output=True,
        check=True,
        text=True,
    )
    campos = next(csv.reader([resultado.stdout.strip()]))
    sid = campos[-1].strip()
    if not sid.startswith("S-1-"):
        raise RuntimeError("SID do usuario invalido")
    return sid


def _restringir_acl(arquivo: Path) -> None:
    sid = _sid_usuario()
    subprocess.run(
        [
            "icacls",
            str(arquivo),
            "/inheritance:r",
            "/grant:r",
            f"*{sid}:(F)",
            "*S-1-5-18:(F)",
            "*S-1-5-32-544:(F)",
        ],
        capture_output=True,
        check=True,
    )


def _escrever_atomico(destino: Path, conteudo: str, restrito: bool = False) -> None:
    temporario = destino.with_name(f"{destino.name}.{os.getpid()}.tmp")
    temporario.write_text(conteudo, encoding="ascii")
    if restrito:
        _restringir_acl(temporario)
    os.replace(temporario, destino)


def _ambiente_integro() -> bool:
    if not PYTHON.is_file():
        return False

    verificacao = (
        "import flask,faster_whisper,numpy,openai,pydub,pyttsx3,sklearn,waitress;"
        "from google import genai;"
        "from importlib.metadata import version;"
        "import struct,sys;"
        "v=" + repr(VERSOES_OBRIGATORIAS) + ";"
        "ok=sys.version_info[:2]==(3,12) and struct.calcsize('P')==8;"
        "raise SystemExit(not (ok and all(version(p)==e for p,e in v.items())))"
    )
    imports_ok = subprocess.run(
        [str(PYTHON), "-W", "ignore", "-c", verificacao],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0
    if not imports_ok:
        return False

    return subprocess.run(
        [str(PYTHON), "-m", "pip", "check"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def _preparar_token() -> None:
    try:
        atual = TOKEN.read_text(encoding="ascii").strip() if TOKEN.is_file() else ""
    except (OSError, UnicodeError):
        atual = ""

    if len(atual) == 64 and all(char in "0123456789abcdef" for char in atual):
        _restringir_acl(TOKEN)
        return
    _escrever_atomico(TOKEN, secrets.token_hex(32) + "\n", restrito=True)


def _preparar_dependencias() -> None:
    if not PYTHON.is_file():
        print("[npcai] Criando ambiente Python local...")
        subprocess.run([sys.executable, "-m", "venv", str(AMBIENTE)], check=True)

    hash_atual = hashlib.sha256(REQUISITOS.read_bytes()).hexdigest().upper()
    try:
        hash_instalado = SELO.read_text(encoding="ascii").strip() if SELO.is_file() else ""
    except (OSError, UnicodeError):
        hash_instalado = ""

    if hash_atual == hash_instalado and _ambiente_integro():
        return

    print("[npcai] Instalando dependencias no ambiente local...")
    subprocess.run(
        [
            str(PYTHON),
            "-m",
            "pip",
            "--isolated",
            "install",
            "--quiet",
            "--disable-pip-version-check",
            "--no-input",
            "--only-binary=:all:",
            "-r",
            str(REQUISITOS),
        ],
        check=True,
    )

    if not _ambiente_integro():
        raise RuntimeError("ambiente incompleto apos instalacao")
    _escrever_atomico(SELO, hash_atual + "\n")


def main() -> int:
    if sys.version_info[:2] != (3, 12):
        raise RuntimeError("bootstrap exige Python 3.12")

    trava = _adquirir_trava()
    try:
        _preparar_dependencias()
        _preparar_token()
    finally:
        _liberar_trava(trava)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
