@echo off
REM vhub_npcai — Inicia o servidor Whisper (reconhecimento de voz local)
REM Modelos: tiny (~1GB RAM), base (~1GB), small (~2GB), medium (~5GB)
REM Porta padrao: 7512

set PYTHON=C:\Users\fox\AppData\Local\Programs\Python\Python312\python.exe
set WHISPER_MODEL=base
set WHISPER_PORT=7512
set LOG_LEVEL=INFO

echo [vhub_npcai] Iniciando servidor Whisper (modelo=%WHISPER_MODEL%, porta=%WHISPER_PORT%)...
echo [vhub_npcai] Prima Ctrl+C para encerrar.
echo.

"%PYTHON%" "%~dp0server.py"
pause
