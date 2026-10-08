# Conversor PTFX RGB — offline

Extrai apenas as chamas necessárias dos YPT fornecidos. Não executa no FXServer, não altera originais e não monta dicionários globais.

## Artefatos

| Arquivo | Bytes | SHA256 |
|---|---:|---|
| `client/core.ypt` original | 13912617 | `43E8E73A739AD8316D868CB771801CD89C162E60F7D679E52FCD0898E25B2104` |
| `client/veh_xs_vehicle_mods.ypt` original | 69922 | `3D27E30A9343EC7DA7FB81CDDE47D3AA3DE0400273D0967276BF731AE72402F6` |
| `stream/mirage_backfire_rgb.ypt` | 537717 | `AD7AB03D813E4461855FD831E4D4748E120D1D70F8F9491B372CECB1D43F4811` |
| `stream/mirage_nitrous_rgb.ypt` | 522293 | `96BD8A216A6A79B1C294C6F229E2871836D819C7CC177794BA158EBFC44F27FB` |

Todos relativos a `resources/[SCRIPTS]/vhub_custom/`. Saídas RSC7 versão 68 (GTA Legacy), dicionários privados e efeito `chama_rgb`.

- Backfire: 1 efeito, 4 emissores, 4 partículas, 4 texturas; 44 keyframes RGB neutralizados.
- Nitrous: 1 efeito, 3 emissores, 3 partículas, 3 texturas; 15 keyframes RGB neutralizados. Texturas antes externas agora incluídas.
- Chama/glow: `RGBCanTint=1`, curvas RGB=1; difusas BGRA neutras pelo máximo dos canais, em todos os mips. Alpha, tempos e intensidade luminosa preservados.
- Fumaça/normal haze intactos. Zoom base/evoluído do efeito fixado em **1%**, não escala neutra; loops contínuos removidos para emissão por pulsos.

### Correção de unidade — custom 2.10.7

A [pesquisa primária de KFPs](https://github.com/krzysiula3000/gta-ypt-research/blob/main/KFPs.md) identifica `ptxEffectRule:m_zoomScalarKFP` como Min/Max **percentuais** (e `m_sizeScalarKFP` como WHD percentuais). A interpretação anterior de ~20 como amplificação ~20× estava errada: trocar 20,21928–20,28087 por 1 reduziu a dimensão para 1%, explicando a chama microscópica mesmo após a 2.10.6. Esta fonte é engenharia reversa, não contrato publicado pela Rockstar.

Somente o evento com `EmitterRule=ParticleRule=veh_exhaust_backfire`: `ZoomScalarMin/Max` de 1,4/2 para **14/20**. Com WHD ×2 da 2.10.6, a compensação ×10 recompõe aproximadamente a dimensão original da chama (2×10/20,2 ≈0,99), mantendo a escala escolhida na oficina. Raiz 1%, glow/haze/fumaça, RGB/alpha/DDS, posição, duração/vida, velocidade, taxa/quantidade e Lua permanecem iguais à 2.10.6. Não amplia o efeito inteiro nem cria um emissor de nitro adicional.

Baseline 2.10.6: 537727 B, SHA256 `C85CC9519E5991805B2CF82CA4B9E627C55B46CF3929FF80D62153969CE5B443`. Gate independente: layout expandido 6340608 B idêntico, somente seis bytes alterados nos dois floats do evento, zero delta externo; quatro DDS SHA idênticos. Round-trip exige identidade única do evento e preservação exata dos dois scalars. A área projetada da chama pode aumentar ~100× contra a versão microscópica; quantidade/vida iguais não significam custo igual. Validar FPS, 16 saídas e observador remoto no FiveM. Após atualizar: `restart vhub_custom` e reconectar para carregar o YPT novo.

### Calibração da chama — custom 2.10.6

Somente backfire: `veh_exhaust_backfire`, quatro curvas. WHD min/max `x/y ×2`, vida `x/y ×1,5` (119,65–184,54 ms base), speed scalar `x/y ×1,25`. Frames/UV, alpha, glow, fumaça, haze, taxa/quantidade emitida por pulso, root zoom, playback e evoluções preservados. Nitro usa este mesmo backfire, sem efeito paralelo. `mirage_nitrous_rgb` alternativo não foi recalibrado.

Baseline anterior: 537732 B, SHA256 `2A20F9A4470F8047FDCDAF2146B3E87015FC3D068B908A7571EEF61B759C0DBB`. Gate independente dos binários expandidos: 6340608 B com apenas 27 bytes alterados, todos dentro dos `x/y` das quatro curvas; zero delta externo. Quatro DDS byte-idênticos. Round-trip valida curvas calibradas com tolerância de float `1e-6` para valores `x/y`; tempos e `z/w` exatos.

Calibração experimental após relato de chama fina/curta no SkylineGTR com RGB funcionando; usuário relatou que a 2.10.6 continuou minúscula. WHD maior eleva fill-rate; vida maior aumenta partículas simultâneas mesmo sem mudar taxa/quantidade total por pulso. Vida base ≤185 ms não certifica cauda real: medir pulso, FPS/resmon e observador em dois clientes, inclusive 16 saídas. Não alterar o zoom raiz para corrigir somente a chama.

## Reproduzir

Requer .NET SDK 8 e checkout local do [CodeWalker](https://github.com/dexyfex/CodeWalker) no commit `485d56bec00262ed7fa472261cce7bbc6202b96e`. Dependências declaradas pelo Core: SharpDX/SharpDX.Mathematics 4.2.0. Build validado com SDK 8.0.425. SDK/checkout/DLLs não são distribuídos neste repositório.

Executar na raiz; substituir o caminho do checkout. Pastas de saída devem ser novas.

```powershell
dotnet build tools/ptfx_rgb/PtfxRgb.csproj -p:CodeWalkerSource=C:/Ferramentas/CodeWalker --configuration Release
$conversorFx = 'tools/ptfx_rgb/bin/Release/net8.0/PtfxRgb.dll'
$customFx = 'resources/[SCRIPTS]/vhub_custom'
dotnet $conversorFx inspecionar "$customFx/client/core.ypt" tools/ptfx_rgb/out/core
dotnet $conversorFx inspecionar "$customFx/client/veh_xs_vehicle_mods.ypt" tools/ptfx_rgb/out/nitrous
dotnet $conversorFx gerar tools/ptfx_rgb/out/core/origem.ypt.xml tools/ptfx_rgb/out/core/origem.ypt.xml veh_backfire mirage_backfire_rgb tools/ptfx_rgb/out/backfire-rgb
dotnet $conversorFx gerar tools/ptfx_rgb/out/nitrous/origem.ypt.xml tools/ptfx_rgb/out/core/origem.ypt.xml veh_nitrous mirage_nitrous_rgb tools/ptfx_rgb/out/nitrous-rgb
powershell -NoProfile -File tools/ptfx_rgb/verificar.ps1
```

Conversão valida closure e referências, tint, curvas/alpha, quatro curvas calibradas do backfire e pixels após salvar/reler o binário. Vida base calibrada acima de 250 ms é rejeitada. Entrada comprimida ≤16 MiB, expansão/XML ≤64 MiB, DTD proibido. Não é serviço de conversão de arquivos hostis: executar somente offline com os arquivos identificados acima. Copiar para `stream/` apenas os dois `.ypt` gerados; nunca XML/DDS auxiliares nem os originais.

Gate independente: cabeçalhos/flags/curvas binárias verificados; 2.446.656 pixels comparados nos quatro difusos, sem divergência de alpha; haze/fumaça byte-idênticos. Não equivale a teste FiveM. Medir RGB primário, vida do pulso, escala, saídas múltiplas e observador em dois clientes após `restart vhub_custom`.

## Proveniência

Origens fornecidas pelo usuário, acompanhadas de `client/ReadMe.txt` para OpenIV/singleplayer. Autor/licença dos assets não documentados: esclarecer antes de distribuir/publicar. O `Readme_Src.txt` do CodeWalker restringe o código a finalidade educacional; consultar os termos do projeto antes de qualquer redistribuição. Nenhum código/binário CodeWalker integra o resource.
