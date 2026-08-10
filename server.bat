@echo off
setlocal
cd /d "%~dp0"

set "BASE_DIR=%~dp0"
set "SERVER_CFG=%BASE_DIR%config\server.cfg"
set "RESOURCE_ROOT=%BASE_DIR%resources"
set "CORE_DIR=%RESOURCE_ROOT%\[CORE]"

:: ── [1] Pré-requisitos ────────────────────────────────────────────────────────

if not exist ".\build\FXServer.exe" (
  echo [ERRO] FXServer.exe nao encontrado em .\build\
  exit /b 1
)

if not exist "%SERVER_CFG%" (
  echo [ERRO] Config nao encontrada: config\server.cfg
  exit /b 1
)

if not exist "%CORE_DIR%" (
  echo [ERRO] Diretorio core nao encontrado: resources\[CORE]
  exit /b 1
)

call :validar_recurso_core oxmysql      || exit /b 1
call :validar_recurso_core vhub_oxmysql || exit /b 1
call :validar_recurso_core vhub         || exit /b 1

:: ── [2] Porta 30120 ───────────────────────────────────────────────────────────

set "PORTPID="
set "PORTPROC="
for /f %%P in ('powershell -NoProfile -Command "$p=(Get-NetTCPConnection -LocalPort 30120 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess); if($p){$p}"') do set "PORTPID=%%P"
if defined PORTPID for /f %%N in ('powershell -NoProfile -Command "(Get-Process -Id %PORTPID% -ErrorAction SilentlyContinue).ProcessName"') do set "PORTPROC=%%N"
if defined PORTPID (
  if not defined PORTPROC set "PORTPROC=ProcessoDesconhecido"
  echo [ERRO] Porta 30120 em uso por PID %PORTPID% ^(%PORTPROC%^).
  echo        Feche a instancia atual antes de iniciar outra.
  exit /b 1
)

:: ── [3] Sidecar de IA (vhub_npcai) ────────────────────────────────────────────

set "NPCAI_DIR=%RESOURCE_ROOT%\[SCRIPTS]\vhub_npcai"
set "NPCAI_PID="
for /f %%P in ('powershell -NoProfile -Command "$p=(Get-NetTCPConnection -LocalPort 7513 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess); if($p){$p}"') do set "NPCAI_PID=%%P"
if defined NPCAI_PID (
  call :aguardar_sidecar 5
  if errorlevel 1 (
    echo [ERRO] Porta 7513 ocupada por processo que nao e o sidecar autorizado.
    exit /b 1
  )
  echo [npcai] Sidecar autorizado ja ativo na porta 7513 ^(PID %NPCAI_PID%^).
) else (
  if exist "%NPCAI_DIR%\start_npcai.bat" (
    echo [npcai] Iniciando sidecar de IA ^(porta 7513, carrega Whisper ~10s^)...
    start "vHub NPCAI Sidecar" /min /D "%NPCAI_DIR%" cmd /c start_npcai.bat
    call :aguardar_sidecar 300
    if errorlevel 1 (
      echo [ERRO] Sidecar NPCAI nao ficou pronto em 300 segundos.
      exit /b 1
    )
  ) else (
    echo [ERRO] start_npcai.bat ausente.
    exit /b 1
  )
)

:: ── [4] FXServer ──────────────────────────────────────────────────────────────

start "FXSERVER" /min /D "%BASE_DIR%" ".\build\FXServer.exe" +exec "%SERVER_CFG%"
exit /b 0

:: aguarda o sidecar autenticado responder /health
:aguardar_sidecar
set "NPCAI_TIMEOUT=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%NPCAI_DIR%\verificar_sidecar.ps1" -LimiteSegundos %NPCAI_TIMEOUT%
exit /b %errorlevel%

:: ─────────────────────────────────────────────────────────────────────────────
:validar_recurso_core
set "RECURSO=%~1"
if exist "%RESOURCE_ROOT%\%RECURSO%" (
  echo [ERRO] %RESOURCE_ROOT%\%RECURSO% existe fora de [CORE]. Mova para resources\[CORE].
  exit /b 1
)
if not exist "%CORE_DIR%\%RECURSO%\fxmanifest.lua" (
  echo [ERRO] Nao encontrado: resources\[CORE]\%RECURSO%\fxmanifest.lua
  exit /b 1
)
exit /b 0
