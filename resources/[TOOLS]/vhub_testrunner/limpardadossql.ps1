param(
  [string]$ConfigPath = ".\server.cfg",
  [switch]$Force,
  [switch]$DryRun,
  [switch]$SkipServerCheck,
  [string[]]$TabelasExtras = @()
)

$ErrorActionPreference = "Stop"

$TabelasVrp = @(
  "vrp_character_business",
  "vrp_character_homes",
  "vrp_character_identities",
  "vrp_login_users",
  "vrp_character_data",
  "vrp_user_data",
  "vrp_user_ids",
  "vrp_characters",
  "vrp_server_data",
  "vrp_global_data",
  "vrp_users"
)

function Resolver-Caminho {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path (Get-Location) $Path)
}

function Ler-ConexaoMysql {
  param([string]$Path)

  $fullPath = Resolver-Caminho $Path
  if (-not (Test-Path -LiteralPath $fullPath)) {
    throw "Config nao encontrado: $fullPath"
  }

  $valor = $null
  foreach ($linha in Get-Content -LiteralPath $fullPath) {
    $t = $linha.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    if ($t -match '^set\s+mysql_connection_string\s+(.+)$') {
      $valor = $Matches[1].Trim()
      break
    }
  }

  if (-not $valor) {
    throw "mysql_connection_string nao encontrado em $fullPath"
  }

  if (($valor.StartsWith('"') -and $valor.EndsWith('"')) -or ($valor.StartsWith("'") -and $valor.EndsWith("'"))) {
    $valor = $valor.Substring(1, $valor.Length - 2)
  }

  if ($valor -match '^mysql://') {
    $uri = [Uri]$valor
    $user = ""
    $pass = ""
    if ($uri.UserInfo) {
      $parts = $uri.UserInfo.Split(":", 2)
      $user = [Uri]::UnescapeDataString($parts[0])
      if ($parts.Length -gt 1) { $pass = [Uri]::UnescapeDataString($parts[1]) }
    }

    return [pscustomobject]@{
      Host = $uri.Host
      Port = $(if ($uri.Port -gt 0) { $uri.Port } else { 3306 })
      User = $(if ($user) { $user } else { "root" })
      Password = $pass
      Database = [Uri]::UnescapeDataString($uri.AbsolutePath.TrimStart("/"))
      Raw = $valor
    }
  }

  $map = @{}
  foreach ($part in $valor.Split(";")) {
    if ($part -match '^\s*([^=]+)\s*=\s*(.*)\s*$') {
      $map[$Matches[1].Trim().ToLowerInvariant()] = $Matches[2].Trim()
    }
  }

  $hostName = $map["server"]
  if (-not $hostName) { $hostName = $map["host"] }
  $userName = $map["uid"]
  if (-not $userName) { $userName = $map["user"] }
  if (-not $userName) { $userName = $map["userid"] }
  if (-not $userName) { $userName = $map["username"] }
  $database = $map["database"]
  if (-not $database) { $database = $map["db"] }
  $port = 3306
  if ($map["port"]) { $port = [int]$map["port"] }

  if (-not $hostName -or -not $userName -or -not $database) {
    throw "mysql_connection_string invalido; esperado mysql://user:pass@host/db ou server=...;uid=...;database=..."
  }

  return [pscustomobject]@{
    Host = $hostName
    Port = $port
    User = $userName
    Password = $(if ($map.ContainsKey("password")) { $map["password"] } elseif ($map.ContainsKey("pwd")) { $map["pwd"] } else { "" })
    Database = $database
    Raw = $valor
  }
}

function Encontrar-MysqlCli {
  $cmd = Get-Command mysql.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidatos = @(
    "C:\xampp\mysql\bin\mysql.exe",
    "C:\wamp64\bin\mysql\mysql*\bin\mysql.exe",
    "C:\laragon\bin\mysql\mysql-*\bin\mysql.exe",
    "C:\Program Files\MySQL\MySQL Server *\bin\mysql.exe",
    "C:\Program Files (x86)\MySQL\MySQL Server *\bin\mysql.exe"
  )

  foreach ($padrao in $candidatos) {
    $achado = Get-ChildItem -Path $padrao -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($achado) { return $achado.FullName }
  }

  throw "mysql.exe nao encontrado. Instale MySQL client ou adicione mysql.exe ao PATH."
}

function Sql-String {
  param([string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Sql-Ident {
  param([string]$Name)
  if ($Name -notmatch '^[A-Za-z0-9_]+$') {
    throw "Nome de tabela recusado: $Name"
  }
  return "``$Name``"
}

function Invocar-Mysql {
  param(
    [string]$MysqlExe,
    [object]$Conn,
    [string]$Sql
  )

  $oldPwdExiste = Test-Path Env:MYSQL_PWD
  $oldPwd = $env:MYSQL_PWD

  try {
    if ($Conn.Password) {
      $env:MYSQL_PWD = $Conn.Password
    } elseif ($oldPwdExiste) {
      Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    }

    $args = @(
      "--protocol=tcp",
      "--host=$($Conn.Host)",
      "--port=$($Conn.Port)",
      "--user=$($Conn.User)",
      "--database=$($Conn.Database)",
      "--default-character-set=utf8mb4",
      "--batch",
      "--raw",
      "--skip-column-names",
      "--execute=$Sql"
    )

    $out = & $MysqlExe @args 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "mysql.exe falhou ($LASTEXITCODE): $out"
    }

    return $out
  }
  finally {
    if ($oldPwdExiste) {
      $env:MYSQL_PWD = $oldPwd
    } else {
      Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    }
  }
}

$conn = Ler-ConexaoMysql -Path $ConfigPath
if (-not $conn.Database) { throw "Database vazio na mysql_connection_string." }

$tabelasAlvo = @($TabelasVrp + $TabelasExtras | Select-Object -Unique)
foreach ($tabela in $tabelasAlvo) { [void](Sql-Ident $tabela) }

Write-Host "[INFO] Banco alvo: $($conn.User)@$($conn.Host):$($conn.Port)/$($conn.Database)"
Write-Host "[INFO] Tabelas alvo: $($tabelasAlvo -join ', ')"

if ($DryRun) {
  Write-Host "[DRY-RUN] Nenhuma alteracao executada."
  exit 0
}

if (-not $SkipServerCheck) {
  $fx = Get-Process -Name FXServer -ErrorAction SilentlyContinue
  if ($fx) {
    throw "FXServer.exe esta ativo. Pare o servidor antes de limpar o banco, ou use -SkipServerCheck por sua conta."
  }
}

if (-not $Force) {
  $confirmacao = Read-Host "Digite LIMPAR para truncar dados vRP do banco '$($conn.Database)'"
  if ($confirmacao -ne "LIMPAR") {
    throw "Operacao cancelada."
  }
}

$mysql = Encontrar-MysqlCli
Write-Host "[INFO] mysql.exe: $mysql"

$listaSql = ($tabelasAlvo | ForEach-Object { Sql-String $_ }) -join ","
$existentesSql = @"
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ($listaSql)
ORDER BY FIELD(TABLE_NAME, $listaSql)
"@

$existentes = @(Invocar-Mysql -MysqlExe $mysql -Conn $conn -Sql $existentesSql | Where-Object { $_ -and $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
if ($existentes.Count -eq 0) {
  Write-Host "[AVISO] Nenhuma tabela vRP conhecida encontrada. Nada foi limpo."
  exit 0
}

$truncate = "SET FOREIGN_KEY_CHECKS=0; " + (($existentes | ForEach-Object { "TRUNCATE TABLE " + (Sql-Ident $_) }) -join "; ") + "; SET FOREIGN_KEY_CHECKS=1;"
Invocar-Mysql -MysqlExe $mysql -Conn $conn -Sql $truncate | Out-Null

Write-Host "[OK] Dados limpos: $($existentes -join ', ')"
Write-Host "[OK] AUTO_INCREMENT resetado; proximo usuario novo deve receber user_id = 1."
