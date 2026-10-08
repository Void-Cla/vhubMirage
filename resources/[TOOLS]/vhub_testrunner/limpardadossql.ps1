# limpardadossql.ps1 - VARREDURA TOTAL do banco: zera TODAS as base tables descobertas via
# information_schema (DELETE + reset de AUTO_INCREMENT). Pega tabelas herdadas de updates
# (vrp_*, vh_*, vhub_*, qualquer coisa) sem lista fixa. Use p/ resetar ambiente de TESTE.
#
#   Uso comum:
#     .\tools\limpardadossql.ps1                     # zera TUDO (confirma com LIMPAR)
#     .\tools\limpardadossql.ps1 -DryRun             # so lista o que seria zerado
#     .\tools\limpardadossql.ps1 -Force              # sem prompt (cuidado)
#     .\tools\limpardadossql.ps1 -Excluir tabela_a   # preserva tabelas
#     .\tools\limpardadossql.ps1 -Somente tabela_a   # limpa somente estas
#
# ============================================================================================
# WIPE REALMENTE DO ZERO = 3 PASSOS (a ordem importa). Fazer com o FXServer DESLIGADO:
#   1. Este script (SQL): DELETE + AUTO_INCREMENT=1 em todas as tabelas + VERIFICACAO de 0 linhas.
#      (Usa DELETE, nao TRUNCATE: no MariaDB o TRUNCATE de tabela-pai com FK e BLOQUEADO mesmo com
#       FK_CHECKS=0 -> com --force o erro era mascarado e conta/char SOBREVIVIAM. Era a causa dos
#       "bugs bizarros": conta admin fantasma, char ja criado, char_id orfao com FK error.)
#   2. KVP do FiveM (nao e SQL, vive em db/default/ RocksDB): apagar a pasta db/default/ inteira
#      com o servidor parado (recria vazia no boot). Limpa hss_outbox:* (aparencia sobrevivente =
#      "cabelo herdado") e o pepper de login. Alternativa cirurgica com servidor no ar: comando de
#      console 'vhub_hss_wipe_outbox' (exige vhub_test_mode=1).
#   3. Ligar o FXServer. So agora o alocador _next_char_id / _next_user_id re-semeia de MAX+1=1.
# Pular o passo 1 ou 2 = wipe incompleto = estado herdado = bug bizarro. Apagar o banco no XAMPP
# equivale so ao passo 1; NAO substitui o passo 2 (KVP nao e SQL).
# ============================================================================================
param(
  [string]$ConfigPath = "",
  [switch]$Force,
  [switch]$DryRun,
  [switch]$SkipServerCheck,
  [string[]]$Somente = @(),
  [string[]]$Excluir = @()
)

$ErrorActionPreference = "Stop"

function Obter-RaizProjeto {
  $dir = (Resolve-Path -LiteralPath $PSScriptRoot).Path

  while ($dir) {
    $databaseCfg = Join-Path -Path $dir -ChildPath "config\database.cfg"
    $gitDir = Join-Path -Path $dir -ChildPath ".git"

    if ((Test-Path -LiteralPath $databaseCfg) -or (Test-Path -LiteralPath $gitDir)) {
      return $dir
    }

    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
  }

  return (Get-Location).ProviderPath
}

$script:RaizProjeto = Obter-RaizProjeto

function Resolver-Caminho {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "Caminho vazio."
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  $candidatos = @(
    (Join-Path -Path (Get-Location).ProviderPath -ChildPath $Path),
    (Join-Path -Path $script:RaizProjeto -ChildPath $Path)
  )

  foreach ($candidato in $candidatos) {
    if (Test-Path -LiteralPath $candidato) {
      return (Resolve-Path -LiteralPath $candidato).Path
    }
  }

  return [System.IO.Path]::GetFullPath(
    (Join-Path -Path (Get-Location).ProviderPath -ChildPath $Path)
  )
}

function Remover-AspasConfig {
  param([string]$Value)

  $valor = $Value.Trim()
  if (($valor.StartsWith('"') -and $valor.EndsWith('"')) -or
      ($valor.StartsWith("'") -and $valor.EndsWith("'"))) {
    return $valor.Substring(1, $valor.Length - 2)
  }

  return $valor
}

function Resolver-ConfigPadrao {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path)) {
    return Resolver-Caminho $Path
  }

  $bases = @((Get-Location).ProviderPath, $script:RaizProjeto) | Select-Object -Unique
  $relativos = @("config\database.cfg", "config\server.cfg", "server.cfg")

  foreach ($base in $bases) {
    foreach ($relativo in $relativos) {
      $candidato = Join-Path -Path $base -ChildPath $relativo
      if (Test-Path -LiteralPath $candidato) {
        return (Resolve-Path -LiteralPath $candidato).Path
      }
    }
  }

  throw "Config MySQL nao encontrado. Use -ConfigPath config\database.cfg."
}

function Resolver-ExecConfig {
  param(
    [string]$ExecPath,
    [string]$BasePath
  )

  $path = Remover-AspasConfig $ExecPath
  if ([System.IO.Path]::IsPathRooted($path)) {
    if (Test-Path -LiteralPath $path) { return (Resolve-Path -LiteralPath $path).Path }
    return $null
  }

  $bases = @(
    $script:RaizProjeto,
    (Get-Location).ProviderPath,
    (Split-Path -Parent $BasePath)
  ) | Where-Object { $_ } | Select-Object -Unique

  foreach ($base in $bases) {
    $candidato = Join-Path -Path $base -ChildPath $path
    if (Test-Path -LiteralPath $candidato) {
      return (Resolve-Path -LiteralPath $candidato).Path
    }
  }

  return $null
}

function Ler-ValorConexaoMysql {
  param(
    [string]$Path,
    [hashtable]$Visitados
  )

  $fullPath = Resolver-Caminho $Path
  if (-not (Test-Path -LiteralPath $fullPath)) {
    throw "Config nao encontrado: $fullPath"
  }

  $chave = $fullPath.ToLowerInvariant()
  if ($Visitados.ContainsKey($chave)) { return $null }
  $Visitados[$chave] = $true

  $valor = $null
  foreach ($linha in Get-Content -LiteralPath $fullPath) {
    $t = $linha.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }

    if ($t -match '^set\s+mysql_connection_string\s+(.+)$') {
      $valor = Remover-AspasConfig $Matches[1]
      continue
    }

    if ($t -match '^exec\s+(.+)$') {
      $include = Resolver-ExecConfig -ExecPath $Matches[1] -BasePath $fullPath
      if (-not $include) {
        throw "Config referenciado por exec nao encontrado: $($Matches[1]) (em $fullPath)"
      }

      $valorInclude = Ler-ValorConexaoMysql -Path $include -Visitados $Visitados
      if ($valorInclude) { $valor = $valorInclude }
    }
  }

  return $valor
}

function Ler-ConexaoMysql {
  param([string]$Path)

  $fullPath = Resolver-ConfigPadrao $Path
  $valor = Ler-ValorConexaoMysql -Path $fullPath -Visitados @{}

  if (-not $valor) {
    throw "mysql_connection_string nao encontrado em $fullPath"
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
      ConfigPath = $fullPath
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
    ConfigPath = $fullPath
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

# valida os nomes passados manualmente (anti-injecao) antes de qualquer query
foreach ($t in @($Somente + $Excluir)) { [void](Sql-Ident $t) }

$mysql = Encontrar-MysqlCli
Write-Host "[INFO] Config MySQL: $($conn.ConfigPath)"
Write-Host "[INFO] Banco alvo: $($conn.User)@$($conn.Host):$($conn.Port)/$($conn.Database)"
Write-Host "[INFO] mysql.exe: $mysql"

# DESCOBERTA: varre TODAS as base tables do banco (information_schema) - sem lista
# fixa, pega tabelas herdadas de qualquer update. Views/sequences ficam de fora.
$descobertaSql = @"
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME
"@
$todas = @(Invocar-Mysql -MysqlExe $mysql -Conn $conn -Sql $descobertaSql `
  | Where-Object { $_ -and $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })

if ($todas.Count -eq 0) {
  Write-Host "[AVISO] Nenhuma tabela encontrada no banco '$($conn.Database)'. Nada a fazer."
  exit 0
}

# alvo = TODAS, ou somente as de -Somente; menos as de -Excluir (case-insensitive)
$alvo = $todas
if ($Somente.Count -gt 0) {
  $setSomente = @{}; foreach ($s in $Somente) { $setSomente[$s.ToLowerInvariant()] = $true }
  $alvo = $alvo | Where-Object { $setSomente.ContainsKey($_.ToLowerInvariant()) }
}
if ($Excluir.Count -gt 0) {
  $setExcluir = @{}; foreach ($e in $Excluir) { $setExcluir[$e.ToLowerInvariant()] = $true }
  $alvo = $alvo | Where-Object { -not $setExcluir.ContainsKey($_.ToLowerInvariant()) }
}
$alvo = @($alvo)

Write-Host "[INFO] Tabelas no banco: $($todas.Count) | a zerar: $($alvo.Count)"
if ($Excluir.Count -gt 0) { Write-Host "[INFO] Preservadas (-Excluir): $($Excluir -join ', ')" }

if ($alvo.Count -eq 0) {
  Write-Host "[AVISO] Nenhuma tabela apos os filtros. Nada foi limpo."
  exit 0
}

# VARREDURA: lista sempre o que sera zerado (e o ponto do -DryRun)
Write-Host "[VARREDURA] Tabelas que serao ZERADAS (TRUNCATE):"
$alvo | Sort-Object | ForEach-Object { Write-Host "  - $_" }

if ($DryRun) {
  Write-Host "[DRY-RUN] Nenhuma alteracao executada. ($($alvo.Count) tabela(s) seriam truncadas.)"
  exit 0
}

if (-not $SkipServerCheck) {
  $fx = Get-Process -Name FXServer -ErrorAction SilentlyContinue
  if ($fx) {
    throw "FXServer.exe esta ativo. Pare o servidor antes de limpar o banco, ou use -SkipServerCheck por sua conta."
  }
}

if (-not $Force) {
  Write-Host "[ATENCAO] Isto vai ZERAR $($alvo.Count) tabela(s) do banco '$($conn.Database)' (TRUNCATE, IRREVERSIVEL)."
  $confirmacao = Read-Host "Digite LIMPAR para confirmar"
  if ($confirmacao -ne "LIMPAR") {
    throw "Operacao cancelada."
  }
}

# revalida cada ident DESCOBERTO antes de injetar no SQL (defesa em profundidade)
foreach ($t in $alvo) { [void](Sql-Ident $t) }

# DELETE + ALTER AUTO_INCREMENT, NAO TRUNCATE. Motivo (causa raiz de wipe falho, 2026-08-16):
# no MariaDB/InnoDB, TRUNCATE numa tabela-PAI referenciada por FK e BLOQUEADO mesmo com
# FOREIGN_KEY_CHECKS=0 ("Cannot truncate a table referenced in a foreign key constraint").
# vh_characters/vh_users/login_accounts tem 26+ filhas com FK -> o TRUNCATE delas falhava e o
# --force MASCARAVA o erro, reportando "sucesso" enquanto conta/char/estado SOBREVIVIAM ao wipe.
# DELETE FROM RESPEITA FK_CHECKS=0 (apaga a pai mesmo com filhas), e ALTER ... AUTO_INCREMENT=1
# reseta o contador que o TRUNCATE zerava de graca. Ordem irrelevante com FK_CHECKS=0.
$tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
try {
  $linhas = @("SET FOREIGN_KEY_CHECKS=0;")
  foreach ($t in $alvo) {
    $id = Sql-Ident $t
    $linhas += "DELETE FROM $id;"
    $linhas += "ALTER TABLE $id AUTO_INCREMENT = 1;"
  }
  $linhas += "SET FOREIGN_KEY_CHECKS=1;"
  [System.IO.File]::WriteAllLines($tempSql, $linhas, [System.Text.UTF8Encoding]::new($false))

  $mysqlArgs = @(
    "--protocol=tcp",
    "--host=$($conn.Host)",
    "--port=$($conn.Port)",
    "--user=$($conn.User)",
    "--database=$($conn.Database)",
    "--default-character-set=utf8mb4",
    "--batch"
    # SEM --force: um erro real DEVE parar o wipe, nunca ser mascarado (era a raiz do falso-sucesso)
  )

  $oldPwdExiste = Test-Path Env:MYSQL_PWD
  $oldPwd = $env:MYSQL_PWD
  try {
    if ($conn.Password) { $env:MYSQL_PWD = $conn.Password }
    elseif ($oldPwdExiste) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }

    Get-Content -LiteralPath $tempSql | & $mysql @mysqlArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "mysql.exe retornou $LASTEXITCODE ao executar o wipe via stdin."
    }
  } finally {
    if ($oldPwdExiste) { $env:MYSQL_PWD = $oldPwd }
    else { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
  }
} finally {
  if (Test-Path -LiteralPath $tempSql) { Remove-Item -LiteralPath $tempSql -Force }
}

# VERIFICACAO PoS-WIPE (fecha o buraco do falso-sucesso): reconta as linhas de TODAS as tabelas
# alvo. Se QUALQUER uma sobreviveu, o wipe FALHOU de verdade e o script grita — nunca mais
# reporta "OK" com estado remanescente. Uma unica linha residual e um wipe incompleto.
$verifSql = "SELECT COALESCE(SUM(n),0) FROM ("
$partes = @()
foreach ($t in $alvo) { $partes += "SELECT COUNT(*) AS n FROM " + (Sql-Ident $t) }
$verifSql += ($partes -join " UNION ALL ") + ") AS w"
$restantes = (Invocar-Mysql -MysqlExe $mysql -Conn $conn -Sql $verifSql | Where-Object { $_ -match '\d' } | Select-Object -First 1)
$restantes = [int]($restantes -replace '\D', '')

if ($restantes -gt 0) {
  throw "[FALHA] Wipe INCOMPLETO: $restantes linha(s) sobreviveram nas tabelas alvo. " +
        "Verifique FKs/permissoes. O banco NAO esta limpo."
}

Write-Host "[OK] $($alvo.Count) tabela(s) zerada(s) no banco '$($conn.Database)' (DELETE + AUTO_INCREMENT=1)."
Write-Host "[OK] VERIFICADO: 0 linhas remanescentes nas tabelas alvo. Proximo id = 1."
Write-Host ""
Write-Host "[!] WIPE INCOMPLETO SEM O PASSO 2 - o banco SQL foi zerado, MAS o KVP do FiveM (RocksDB"
Write-Host "    em db/default/) NAO e SQL e NAO foi tocado por este script. O 'hss_outbox:<char_id>'"
Write-Host "    sobrevive e, com char_id reusado, REINSTALA a aparencia de um personagem antigo"
Write-Host "    (bug do 'cabelo herdado'). Apagar/recriar o banco no XAMPP NAO resolve isso."
Write-Host ""
Write-Host "    PASSO 2 (limpar o KVP) - no CONSOLE do FXServer, com vhub_test_mode=1:"
Write-Host "        vhub_hss_wipe_outbox"
Write-Host ""
Write-Host "    Para um reset TOTALMENTE do zero, alternativa nuclear: parar o servidor e apagar a"
Write-Host "    pasta db/default/ inteira (o FXServer recria vazia no proximo boot). Isso limpa TODO"
Write-Host "    KVP de uma vez (inclui o pepper de login, que sera re-derivado do sv_licenseKey)."
