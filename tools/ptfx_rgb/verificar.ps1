# Executar de qualquer diretório; verifica artefatos aprovados, não a aparência FiveM.
$ErrorActionPreference = 'Stop'
$raizFx = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$customFx = Join-Path $raizFx 'resources/[SCRIPTS]/vhub_custom'
$totalFx = 0
function Confirmar-Fx([bool] $condicao, [string] $mensagem) {
    if (-not $condicao) { throw $mensagem }
    $script:totalFx++
}
$artefatosFx = @(
    @('client/core.ypt', 13912617, '43E8E73A739AD8316D868CB771801CD89C162E60F7D679E52FCD0898E25B2104'),
    @('client/veh_xs_vehicle_mods.ypt', 69922, '3D27E30A9343EC7DA7FB81CDDE47D3AA3DE0400273D0967276BF731AE72402F6'),
    @('stream/mirage_backfire_rgb.ypt', 537717, 'AD7AB03D813E4461855FD831E4D4748E120D1D70F8F9491B372CECB1D43F4811'),
    @('stream/mirage_nitrous_rgb.ypt', 522293, '96BD8A216A6A79B1C294C6F229E2871836D819C7CC177794BA158EBFC44F27FB')
)
foreach ($artefatoFx in $artefatosFx) {
    $caminhoFx = Join-Path $customFx $artefatoFx[0]
    Confirmar-Fx ((Get-Item -LiteralPath $caminhoFx).Length -eq $artefatoFx[1]) "Tamanho divergente: $caminhoFx"
    Confirmar-Fx ((Get-FileHash -LiteralPath $caminhoFx -Algorithm SHA256).Hash -eq $artefatoFx[2]) "Hash divergente: $caminhoFx"
    $dadosFx = [IO.File]::ReadAllBytes($caminhoFx)
    Confirmar-Fx ([BitConverter]::ToUInt32($dadosFx, 0) -eq 0x37435352 -and [BitConverter]::ToUInt32($dadosFx, 4) -eq 68) "RSC7/versao invalida: $caminhoFx"
}
$manifestoFx = Get-Content -LiteralPath (Join-Path $customFx 'fxmanifest.lua') -Raw
foreach ($nomeFx in @('mirage_backfire_rgb', 'mirage_nitrous_rgb')) {
    Confirmar-Fx ($manifestoFx.Contains("'stream/$nomeFx.ypt'")) "Asset ausente no manifesto: $nomeFx"
}
$streamFx = @(Get-ChildItem -LiteralPath (Join-Path $customFx 'stream') -File -Filter '*.ypt')
Confirmar-Fx (-not @($streamFx | Where-Object { $_.Name -in @('core.ypt', 'veh_xs_vehicle_mods.ypt') }).Count) 'Override global proibido'
Confirmar-Fx (-not ($manifestoFx -match "client/(core|veh_xs_vehicle_mods)\.ypt")) 'Original montado indevidamente'
Write-Output "PTFX: $totalFx verificacoes aprovadas. Gate visual FiveM pendente."
