# fix_vhub_db.ps1 — Stop FXServer, ensure mysql client, fix vh_users/vh_user_ids, restart server
param(
  [string]$ServerCfg = ".\server.cfg",
  [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

function Stop-FXServer {
  $fx = Get-Process -Name FXServer -ErrorAction SilentlyContinue
  if ($fx) {
    Write-Host "[INFO] Stopping FXServer (PIDs: $($fx.Id -join ', '))"
    $fx | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Seconds 1
  } else {
    Write-Host "[INFO] FXServer not running"
  }
}

function Ensure-Choco {
  $c = Get-Command choco -ErrorAction SilentlyContinue
  if ($c) {
    Write-Host "[INFO] Chocolatey found: $($c.Source)"
    return $true
  }
  Write-Host "[INFO] Chocolatey not found. Installing Chocolatey..."
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  $env:Path = $env:Path + ";C:\ProgramData\chocolatey\bin"
  Start-Sleep -Seconds 2
  $c = Get-Command choco -ErrorAction SilentlyContinue
  if ($c) { Write-Host "[INFO] Chocolatey installed."; return $true }
  throw "Chocolatey install failed or requires manual step."
}

function Ensure-MySQLClient {
  $m = Get-Command mysql.exe -ErrorAction SilentlyContinue
  if ($m) { Write-Host "[INFO] mysql.exe found: $($m.Source)"; return $m.Source }

  Ensure-Choco

  Write-Host "[INFO] Installing MariaDB (provides mysql.exe) via Chocolatey..."
  choco install mariadb -y --no-progress
  Start-Sleep -Seconds 6

  # Try to locate mysql.exe in common install locations
  $cands = @(
    'C:\\Program Files\\MariaDB*\\bin\\mysql.exe',
    'C:\\Program Files\\MySQL\\MySQL Server*\\bin\\mysql.exe',
    'C:\\xampp\\mysql\\bin\\mysql.exe',
    'C:\\wamp\\bin\\mysql\\mysql*\\bin\\mysql.exe'
  )
  foreach ($pat in $cands) {
    $found = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { Write-Host "[INFO] mysql.exe located: $($found.FullName)"; return $found.FullName }
  }

  $m = Get-Command mysql.exe -ErrorAction SilentlyContinue
  if ($m) { Write-Host "[INFO] mysql.exe found on PATH: $($m.Source)"; return $m.Source }

  throw "mysql.exe nao encontrado apos tentativas de instalacao. Instale o cliente MySQL/MariaDB manualmente."
}

function Parse-MysqlConnectionFromCfg {
  param([string]$cfgPath)
  if (-not (Test-Path -LiteralPath $cfgPath)) { throw "Config nao encontrado: $cfgPath" }
  $lines = Get-Content -LiteralPath $cfgPath
  foreach ($l in $lines) {
    $t = $l.Trim()
    if ($t -match '^set\s+mysql_connection_string\s+(.+)$') {
      $val = $Matches[1].Trim()
      # strip quotes
      if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
        $val = $val.Substring(1, $val.Length - 2)
      }
      return $val
    }
  }
  throw "mysql_connection_string nao encontrado em $cfgPath"
}

function Get-ConnObjFromUri($uriStr) {
  if ($uriStr -match '^mysql://') {
    $u = [Uri]$uriStr
    $user = ''
    $pass = ''
    if ($u.UserInfo) {
      $parts = $u.UserInfo.Split(':',2)
      $user = [Uri]::UnescapeDataString($parts[0])
      if ($parts.Length -gt 1) { $pass = [Uri]::UnescapeDataString($parts[1]) }
    }
    return [pscustomobject]@{ Host=$u.Host; Port = $(if ($u.Port -gt 0) { $u.Port } else { 3306 }); User = $(if ($user) { $user } else { 'root' }); Password=$pass; Database = $u.AbsolutePath.TrimStart('/') }
  }
  throw "mysql_connection_string formato nao suportado: $uriStr"
}

# --- Begin ---
Write-Host "[START] fix_vhub_db.ps1"

Stop-FXServer

$raw = Parse-MysqlConnectionFromCfg -cfgPath $ServerCfg
$conn = Get-ConnObjFromUri $raw
Write-Host "[INFO] DB alvo: $($conn.User)@$($conn.Host):$($conn.Port)/$($conn.Database)"

# Call Ensure-MySQLClient to install/find client, but get concrete path via Get-Command
# Call Ensure-MySQLClient and pick a valid mysql.exe path from its output or PATH
$ret = Ensure-MySQLClient
$candidates = @()
if ($ret) { $candidates += $ret }
$cmd = Get-Command mysql.exe -ErrorAction SilentlyContinue
if ($cmd) { $candidates += $cmd.Source }

# Prefer a candidate that actually exists as a file
$pathCandidate = $null
foreach ($c in $candidates) {
  if (-not $c) { continue }
  if ($c -is [string]) {
    # If the candidate itself is a valid path, use it
    try {
      if (Test-Path $c) { $pathCandidate = $c; break }
    } catch { }
    # Otherwise try to extract a path-like substring
    $matches = [regex]::Matches($c, '[A-Za-z]:\\[^\r\n]*mysql\.exe')
    foreach ($mm in $matches) {
      $p = $mm.Value
      try {
        if (Test-Path $p) { $pathCandidate = $p; break }
      } catch { }
    }
    if ($pathCandidate) { break }
  }
}
if (-not $pathCandidate) {
  # try to extract a path-like string from combined output
  $joined = @($ret) -join "`n"
  $m = [regex]::Match($joined, '[A-Za-z]:\\[^\r\n]*mysql\.exe')
  if ($m.Success) {
    $p = $m.Value
    if ((Test-Path $p) -eq $true) { $pathCandidate = $p }
  }
}
if (-not $pathCandidate) { throw "mysql.exe nao encontrado apos Ensure-MySQLClient." }
$mysqlExe = $pathCandidate
Write-Host "[INFO] Usando mysql.exe: $mysqlExe"

# Helper to run sql
function ExecSql($sql) {
  $args = @(
    '--protocol=tcp',
    "--host=$($conn.Host)",
    "--port=$($conn.Port)",
    "--user=$($conn.User)",
    "--database=$($conn.Database)",
    "--default-character-set=utf8mb4",
    "--batch",
    "--raw",
    "--skip-column-names",
    "--execute=$sql"
  )
  if ($conn.Password -and $conn.Password -ne '') {
    $env:MYSQL_PWD = $conn.Password
  }
  try {
    $out = & $mysqlExe @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("mysql.exe retornou codigo {0}: {1}" -f $LASTEXITCODE, ($out -join "`n")) }
    return $out
  }
  finally {
    if ($env:MYSQL_PWD) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
  }
}

# 1) Show current state
Write-Host "[INFO] Estado atual:";
ExecSql "SELECT COUNT(*) AS user_count, COALESCE(MAX(id),0) AS maxid FROM vh_users;" | Write-Host
ExecSql "SELECT user_id, COUNT(*) AS cnt FROM vh_user_ids GROUP BY user_id ORDER BY user_id;" | Write-Host

# 2) Insert missing vh_users for referenced ids (safe)
Write-Host "[INFO] Inserindo vh_users faltantes para ids referenciados em vh_user_ids..."
$insertSql = @"
SET FOREIGN_KEY_CHECKS=0;
INSERT INTO vh_users (id, created_at)
SELECT DISTINCT ui.user_id, NOW()
FROM vh_user_ids ui
LEFT JOIN vh_users u ON ui.user_id = u.id
WHERE u.id IS NULL;
SET FOREIGN_KEY_CHECKS=1;
"@
ExecSql $insertSql | Write-Host

# 3) Recalculate nextid and set AUTO_INCREMENT
Write-Host "[INFO] Ajustando AUTO_INCREMENT..."
$next = ExecSql "SELECT COALESCE(MAX(id),0)+1 FROM vh_users;"
$next = $next.Trim()
if (-not $next -or -not ($next -as [int])) { throw "Nao foi possivel determinar nextid: '$next'" }
Write-Host "[INFO] Next id calculado: $next"
ExecSql "SET FOREIGN_KEY_CHECKS=0; ALTER TABLE vh_users AUTO_INCREMENT = $next; SET FOREIGN_KEY_CHECKS=1;" | Write-Host

Write-Host "[OK] Correcoes aplicadas."

if (-not $NoRestart) {
  Write-Host "[INFO] Reiniciando servidor (server.bat)..."
  $args = @('/c','start','"FXSERVER"','/min','/D',$PWD,'.\server.bat')
  Start-Process -FilePath 'cmd.exe' -ArgumentList $args -WorkingDirectory $PWD | Out-Null
  Write-Host "[INFO] server.bat iniciado."
}

Write-Host "[END] fix_vhub_db.ps1"
