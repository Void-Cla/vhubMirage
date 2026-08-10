@echo off
setlocal EnableExtensions

title vHub NPCAI Sidecar

set "RECURSO=%~dp0"
set "SIDECAR=%RECURSO%sidecar"
set "PYTHON=%RECURSO%.venv\Scripts\python.exe"
set "TOKEN_ARQUIVO=%RECURSO%.sidecar-token"

if not exist "%SIDECAR%\server.py" (
    echo [npcai] ERRO: sidecar\server.py ausente.
    exit /b 1
)

where py >nul 2>&1
if errorlevel 1 (
    echo [npcai] ERRO: Python Launcher ausente. Instale Python 3.12 x64.
    exit /b 1
)

py -3.12 -c "import struct; raise SystemExit(0 if struct.calcsize('P') == 8 else 1)" >nul 2>&1
if errorlevel 1 (
    echo [npcai] ERRO: Python 3.12 x64 ausente.
    exit /b 1
)

py -3.12 "%SIDECAR%\preparar_ambiente.py"
if errorlevel 1 (
    echo [npcai] ERRO: falha ao preparar ambiente local.
    exit /b 1
)

set "NPCAI_TOKEN="
if exist "%TOKEN_ARQUIVO%" set /p NPCAI_TOKEN=<"%TOKEN_ARQUIVO%"
if not defined NPCAI_TOKEN (
    echo [npcai] ERRO: token interno ausente.
    exit /b 1
)

cd /d "%SIDECAR%"
echo [npcai] Iniciando sidecar na porta 7513...
"%PYTHON%" -u server.py
set "CODIGO=%ERRORLEVEL%"

if not "%CODIGO%"=="0" echo [npcai] ERRO: sidecar encerrou com codigo %CODIGO%
exit /b %CODIGO%
