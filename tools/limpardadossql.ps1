<#
Wrapper para executar o script real em resources\[TOOLS]\vhub_testrunner\limpardadossql.ps1
Encaminha todos os argumentos recebidos para o script alvo. Use '.\tools\limpardadossql.ps1 Responde 'LIMPAR''
#>
$ErrorActionPreference = 'Stop'

# Caminho relativo do script alvo (relativo à pasta tools)
$targetRelative = "..\resources\[TOOLS]\vhub_testrunner\limpardadossql.ps1"
$targetPath = Join-Path -Path $PSScriptRoot -ChildPath $targetRelative

$resolved = $null
try {
  $resolved = (Resolve-Path -LiteralPath $targetPath -ErrorAction Stop).Path
} catch {
  Write-Error "Script alvo nao encontrado (literal): $targetPath"
  exit 1
}

# Encaminha todos os argumentos recebidos
Write-Host "[INFO] Encaminhando para: $resolved"
& "$resolved" @args
