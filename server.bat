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

:: ── [3] VOIP (opcional) ───────────────────────────────────────────────────────

if not exist ".\resources\[CORE]\voip_server\main.js" goto :iniciar

if not exist ".\resources\[CORE]\voip_server\node_modules\ws" (
  echo [AVISO] voip_server sem node_modules\ws. Rode: npm i ws wrtc em resources\[CORE]\voip_server
  goto :iniciar
)
if not exist ".\resources\[CORE]\voip_server\node_modules\wrtc" (
  echo [AVISO] voip_server sem node_modules\wrtc. Rode: npm i ws wrtc em resources\[CORE]\voip_server
  goto :iniciar
)

start "VOIP_SERVER" /min cmd /c "cd /d ""%~dp0resources\[CORE]\voip_server"" && node main.js"

:: ── [4] FXServer ──────────────────────────────────────────────────────────────

:iniciar
start "FXSERVER" /min /D "%BASE_DIR%" ".\build\FXServer.exe" +exec "%SERVER_CFG%"
exit /b 0

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
