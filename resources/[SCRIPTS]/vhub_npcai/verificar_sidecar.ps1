param(
    [ValidateRange(1, 300)]
    [int] $LimiteSegundos = 5
)

$tokenArquivo = Join-Path $PSScriptRoot '.sidecar-token'
$prazo = (Get-Date).AddSeconds($LimiteSegundos)

do {
    try {
        if (Test-Path -LiteralPath $tokenArquivo) {
            $token = (Get-Content -Raw -LiteralPath $tokenArquivo).Trim()
            $headers = @{ 'X-NPCAI-Token' = $token }
            $resposta = Invoke-RestMethod `
                -Uri 'http://127.0.0.1:7513/health' `
                -Headers $headers `
                -TimeoutSec 2

            if ($resposta.ok -and $resposta.service -eq 'vhub_npcai') {
                exit 0
            }
        }
    } catch {
        # O launcher ainda pode estar instalando dependencias ou carregando o modelo.
    }

    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $prazo)

exit 1
