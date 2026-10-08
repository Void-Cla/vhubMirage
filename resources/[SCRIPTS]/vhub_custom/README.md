# vhub_custom — Oficina, Bennys e Mec

**Versão:** 2.10.7 | **Owner:** `vhub_custom`

Serviço veicular unificado: estética, performance, calibração, nitro, reparo e reboque.

## Autoridade

Antes de abrir qualquer NUI, o servidor valida:

- sessão, zona e velocidade;
- `netId`, entidade veicular, placa e modelo registrado;
- bucket, distância jogador↔zona↔veículo;
- status `out`, chave/dono e motorista.

O servidor emite lease efêmero vinculado a `src + char_id + domínio + placa + netId + bucket`.
Toda mutação revalida a lease e usa lock tokenizado por placa.

## Domínios

- **Bennys:** RGB, cores extras, neon, fumaça, xenon, vidros, placas, rodas 0–12, buzina, liveries e kits 0–49 permitidos.
- **Oficina:** motor, freios, câmbio, suspensão, blindagem, turbo, calibração autoritativa e kit de nitro.
- **Mec:** pneus, motor, lataria e reboque com destino configurado e movimento server-side.

O cap de stage deriva de `vtype/category/tier_max` persistidos. Classe enviada pelo cliente não participa.

## Persistência e pagamento

| Dado | Escritor único |
|---|---|
| Customização, health, damage e posição | `vhub_conce` |
| Dinheiro e compensação exata | `vhub_money` |
| `customization.handling` | `vhub_vehcontrol` via export gated |
| `customization.nitro` | `vhub_custom/server/nitro.lua` |
| Saga e guard por placa (`prepared/charged/applied/refunded`) | `vhub_custom` |
| Auditoria veicular append-only | `vhub_conce` → `vhub_vehicle_log` |

Fluxo: `validar → lock → prepared → charged → revalidar → persistir → applied → auditar`.
Os ledgers `vh_custom_operations`/`vh_custom_operation_guards` cobrem operações pagas e gratuitas. UNIQUE por request, guard exclusivo por placa e claim CAS de 300s impedem concorrência. Recovery limitado (20/30s) confirma o estado aplicado ou estorna offline, exceto reparos com resultado físico ambíguo.

Reparo: `lease → lock → barreira/revisão de telemetria → inspeção do owner → orçamento/pagamento → aplicação física/ACK → SQL → applied → liberar barreira`.
O marker `damage_log[].operation_id` é gravado no mesmo UPSERT do reparo, após o ACK; recovery exige essa prova, não apenas health/damage iguais ao resultado desejado.
Health considera o menor valor entre prontuário e réplica. Lataria corrige deformação, portas e vidros; preserva motor, combustível e pneus. Possui tarifa mínima de uma unidade (`lataria_parcial`), pois deformação não possui snapshot canônico. Pneus abrangem `0..7`, `45` e `47`, sem cobrança duplicada de pneu/aro.

Falha anterior ao envio do RPC físico permite estorno. Depois do envio, recusa declarada pelo client não prova ausência de aplicação. Perda de ACK/SQL mantém operação `charged`, guard da placa e auditoria `physical_unknown`/`physical_applied_save_failed`; não anuncia sucesso nem estorna um reparo possivelmente entregue. Reconciliação física nesses casos exige inspeção administrativa, usando os owners existentes; não editar ledgers manualmente. Auditoria de recovery: `repair_requires_physical_reconciliation`.

Telemetria carrega `_physical_net_id`/`_physical_revision` para o escritor. Revisão/barreira são privadas em `vhub_conce`; bags são apenas espelhos, não fontes de autoridade. Snapshots antigos e durante manutenção são rejeitados. Writes/merges são serializados por placa; leitura em voo não repovoa cache com versão anterior. Snapshot final exige vínculo recente de motorista previamente validado, placa/entidade/bucket/distância e consumo único.

## Dependências

```text
oxmysql
vhub
vhub_conce
vhub_money
vhub_vehcontrol
vhub_inventory
vhub_target
```

## Mapa de integração

Eventos registrados são exclusivamente a borda client→server da intenção do jogador.
Integração server→server preventiva: `beginService(src, domain, zone_id, plate, net_id)`,
gated para `vhub_admin`/`vhub_garage` e com a mesma prova física/rate do jogador.

| Resource | Exports consumidos |
|---|---|
| `vhub_conce` | `canOperate`, `getVehicle`, `getVehicleState`, `saveVehicleState`, `iniciarManutencaoVeicular`, `encerrarManutencaoVeicular`, `updatePosition`, `getCatalog`, `appendVehicleAudit` |
| `vhub_money` | `commitPayment`, `refundPayment` |
| `vhub_vehcontrol` | `getVehicleSheet`, `getVehicleSheetPreview`, `reserveWorkshopRecalibration`, `commitWorkshopRecalibration`, `cancelWorkshopRecalibration` |
| `vhub_custom` (nitro integrado) | `getNitro`, `installKit` |

Nomes de eventos pertencem exclusivamente a `shared/events.lua`.

## NUI

- runtime modular com lifecycle completo;
- bridge HTTP único em `web/runtime.js`;
- CSP sem scripts externos;
- preview cosmético limitado a 10 Hz;
- órbita e zoom coalescidos a 30 Hz;
- timers/listeners removidos no fechamento;
- HTML/CSS transparentes, sem CDN e sem `backdrop-filter` sobre o GTA.

`web/design.css` define Mirage Garage: grafite/areia/dourado, superfícies legíveis, animações de entrada e status de transação. Layouts permanecem específicos: Bennys com palco transparente, oficina com diagrama, mecânica com diagnóstico lateral. O runtime permite um único módulo visível; estado/callbacks continuam isolados por domínio. Respostas Bennys/oficina vinculam lease/request; previews usam geração própria.

## Escapamento e nitro — 2.10.7

`client/exhaust.lua` é o único emissor de PTFX para backfire/preview/nitro. Usa coordenadas de `GetWorldPositionOfEntityBone`, não o alias ambíguo `GetEntityBonePosition_2`. Nitro só emite se `exhaust_fx.enabled=true` na oficina: não há fogo independente do kit nitro nem fallback RGB legado. Ambos usam a mesma escala/cor atuais do bag. Na 2.10.5, escala visual padrão = escala selecionada × `0.5`, com teto `1.5`: sutil `0.3`, normal `0.5`, forte `0.9`, brutal `1.5`. Máximo 50% maior que o teto anterior, sem saturar antes da seleção `3.0`; não restaura piso exclusivo do nitro. Deslocamento mantido em 12 cm para testar tamanho sem misturar uma mudança de posição. É calibração experimental, não correção comprovada de bone/ocultação; aparência depende do modelo/asset e exige teste em jogo.

Preview/backfire/nitro compartilham cooldown de 450 ms (inclusive tentativa com retorno false), sem pulsos simultâneos dos scripts. Menu permite somente preview local; condução exige motorista com controle para efeitos de rede. Cache de uma entidade, até 16 saídas únicas por célula espacial de 5 cm; bones distintos coincidentes não duplicam. Budget: 500 ms ocioso/menu, 60 ms dirigindo com FX ativo, padrão ≤2,23 levas/s. Geometria é resolvida somente na tentativa de emissão, não a cada tick de condução. Não cria loop remoto por carro. Backfire automático do GTA/modelo não é um segundo emissor Lua nem é globalmente desativado por este script.

### Identificação e orientação das saídas

Na 2.10.4, `exhaust` e `exhaust_1..16` são pesquisados por nome; índices e bocas coincidentes são deduplicados. Posição mundial e [rotação local do bone](https://raw.githubusercontent.com/citizenfx/natives/master/ENTITY/GetEntityBoneRotationLocal.md) são relidas por pulso. O efeito recebe os três ângulos locais; não reutiliza rotação mundial nem orienta toda saída para a traseira. A origem avança `outlet_push=0.12` metros no eixo -Y rotacionado dos YPT privados. Teto configurável: 0,5 m. Cache de índices invalida em troca de entidade/modelo/mod4/extras 0..20. Vetores não finitos, offsets fora de ±20 m e bone dentro de 5 cm do centro são rejeitados. Sem saída válida: log limitado ao cache atual e nenhuma chama; removido fallback que inventava dois escapamentos pela dimensão do chassi.

Com o carro ocupado ou aberto na oficina, executar `/vhub_escapamento` (chat) ou `vhub_escapamento` (F8). Log F8 informa modelo/hash, mod4, extras, quantidade de bocas resolvidas e `pos/rot` locais por saída. Durante 10 segundos, boca laranja, origem da chama verde e linha verde da direção prevista; repetir interrompe. Apenas visual/read-only: não dispara fogo nem salva ajuste. Se houver preview/nitro/backfire nesse período, log `PTFX tentativa` registra o veículo, escala real enviada, RGB, contagem e origem/rotação da primeira saída, no máximo 1 Hz; não infere escala do bag salvo durante preview nem confirma sucesso da native. Resolver a 4 Hz, desenhar por frame somente enquanto solicitado, destruir no stop. A ordem Euler específica do PTFX/bone não é documentada: extrusão usa `Rz·Rx·Ry`; comparar seta com a chama em saídas laterais/verticais e carro inclinado antes de aprovar visualmente.

**Limite da engine:** quantidade de bones não prova quantidade de tubos visíveis. Há [relato aberto no FiveM](https://github.com/citizenfx/fivem/issues/2999) de bones originais preservados após trocar peças. Modelos/addons ou mods com bocas deslocadas exigem perfil medido, não heurística genérica. `model_outlets` substitui integralmente a lista automática na variante correspondente:

```lua
-- shared/config.lua → exhaust_fx.model_outlets; EXEMPLO de formato, não medidas de um carro real.
[joaat('modelo')] = {
  [-1] = { -- mod4=-1: original
    { pos=vec3(-0.7,-2.1,0.3), rot=vec3(0,0,-90) },
    { pos=vec3( 0.7,-2.1,0.3), rot=vec3(0,0, 90) },
  },
  [0] = { { pos=vec3(0,-2.2,0.4), rot=vec3(0,0,0) } }, -- mod4=0
  [1] = {}, -- variante explicitamente sem saídas; não cai para bones
  -- default = {...}, -- opcional: demais variantes do mesmo modelo
},
```

Perfis confiáveis locais, máximo 16 saídas; nunca enviados pela NUI/bag/DB. Lista vazia não emite. Perfis não distinguem extras: se extra altera os tubos físicos, conferir geometria específica antes de cadastrar perfil comum. Não há dados fictícios de modelos instalados nesta tabela.

### Assets RGB isolados

Na 2.10.6, `mirage_backfire_rgb.ypt` recebeu WHD da chama `x/y ×2`, vida base `×1,5` (119,65–184,54 ms) e velocidade `×1,25`; usuário confirmou RGB no SkylineGTR, mas a chama continuou minúscula. Na 2.10.7 foi identificado o erro de unidade: `m_zoomScalarKFP` é percentual; a conversão anterior de ~20,2 para 1 reduzia o zoom a **1%**, não removia amplificação ~20×. A raiz permanece em 1% para preservar glow/fumaça/haze; somente `ZoomScalarMin/Max` do evento da chama recebem compensação `1,4/2 → 14/20`. Com WHD ×2, recupera aproximadamente a dimensão original desse sprite, mantendo cor/tamanho selecionados e um emissor único para oficina/nitro. Dois floats alterados, sem mudar RGB/alpha/texturas, origem, cadência, vida, velocidade ou Lua. A área da chama pode crescer ~100× contra a versão microscópica: validar FPS/cauda/16 saídas e observador em dois clientes antes de produção. Fonte de unidades: [pesquisa primária de KFPs](https://github.com/krzysiula3000/gta-ypt-research/blob/main/KFPs.md), engenharia reversa, não contrato Rockstar. Executar `restart vhub_custom` e reconectar para carregar o YPT novo; aparência/replicação universal continuam pendentes.

O padrão é `mirage_backfire_rgb/chama_rgb`, com `colour_mode='rgb'`. Os dois YPT de `stream/` foram extraídos dos arquivos fornecidos em `client/`, que permanecem intactos e não são montados. Não substituem `core` nem `veh_xs_vehicle_mods` globais. Regras de chama/glow permitem tint; curvas e texturas difusas são neutras em RGB, com alpha/tempos preservados. Fumaça e normal de haze não foram recoloridos. A escala selecionada continua pertencendo à oficina, sobre o perfil percentual do YPT acima.

`mirage_nitrous_rgb/chama_rgb` é uma variante disponível no mesmo resource, não um segundo emissor. Para usá-la, alterar somente `asset` abaixo: oficina, preview e nitro usam todos o mesmo perfil. Ambos são autocontidos e configurados para pulsos não-loopados. Não combinar os dois assets por meio de outro script de fogo.

```lua
-- shared/config.lua → exhaust_fx
asset = 'mirage_backfire_rgb', effect = 'chama_rgb', resource = nil,
colour_mode = 'rgb', scale_factor = 0.5, max_scale = 1.5, interval_ms = 450,
```

Asset/effect/resource vêm somente da configuração confiável, nunca da NUI/bag/DB. Dicionário que não carregar em 5 s ou recurso externo parado desabilita a emissão e gera diagnóstico limitado no F8, sem fallback silencioso para outro efeito. Executar `restart vhub_custom` após atualizar os assets/configuração. O seletor aparece apenas com modo RGB declarado e PTFX carregado.

Conversão reproduzível, hashes e proveniência: [tools/ptfx_rgb](../../../tools/ptfx_rgb/README.md). Os originais não têm licença documentada; confirmar direitos antes de publicar/distribuir. A [referência Cfx](https://raw.githubusercontent.com/citizenfx/natives/master/GRAPHICS/SetParticleFxNonLoopedColour.md) registra limitações de tint. Estrutura/alpha neutros não certificam aparência: validar vermelho/verde/azul, escala e replicação em dois clientes FiveM.

Teste offline: `lua tools/test_custom_exhaust.lua` (64 verificações com natives simuladas) e `powershell -NoProfile -File tools/ptfx_rgb/verificar.ps1` (integridade dos assets e montagem). Gate em jogo: escapamento original/custom de uma/duas/quatro saídas, lateral/vertical, pitch/roll do carro e bones, trocar/cancelar mod4/extras, verificar marcas e boca física; preview/cancelar/comprar, entrar em carro já no streaming, nitro logo após alterar escala/cor, kit chamas desligado, observador remoto, troca de motorista e resource restart; confirmar chamas visíveis sem incêndio/dano e medir resmon/rede. Testes offline não certificam aparência/RGB nem funcionamento de um YPT real.

## Validação 2.10.0

Offline, na raiz do repositório:

```text
lua tools/test_custom.lua
node tools/test_custom_nui.js
lua tools/test_compat.lua
lua tools/test_engineering.lua
```

Natives, rede, DOM e SQL simulados não comprovam execução em FiveM. Reiniciar conjuntamente `vhub_conce`, `vhub_vehcontrol` e `vhub_custom` em ambiente de teste; há mudança no contrato de telemetria e nos recibos da NUI. Sem migração SQL nova.

Gate em jogo: pneus 6/7/45/47; lataria com motor avariado e pneus furados; reparar durante snapshot e guardar/retirar; RGB→paleta→respawn; preview→cancelar/stock; instalar/remover com owner diferente; fechar/reabrir com respostas atrasadas; falha de controle/ACK/SQL; NUI em 1280×720 e 1920×1080, cursor e ESC. Não promover sem esse smoke test.

Limite legado ainda existente: `takeItem/giveItem` do inventário alteram cache com flush posterior. Consumo de peça e saga SQL não constituem uma transação durável única em crash do processo; resolver isso exige contrato idempotente do owner `vhub_inventory`, não um segundo escritor no custom.

## Configuração

Cada entrada de `VHubCustom.cfg.zones` usa coordenadas flat. Zona mecânica exige destino de reboque:

```lua
{
  id = 'mec_ls', domain = 'mec',
  x = 136.0, y = -1082.0, z = 29.1,
  tow_drop = { x = 142.0, y = -1081.0, z = 29.2, h = 0.0 },
}
```

## Migração 1.x → 2.0

Removidos: `BENNYS_OPEN`, `OFICINA_OPEN`, `OFICINA_AUTH*`, `MEC_TOW_DO`, `mecTowDone`,
`REQ_CATALOG`, `REQ_VEH_DATA`, `VEH_DATA` e `ZONE_ENTER/LEAVE`.

Payloads de `BENNYS_APPLY`, `MEC_REPAIR`, `MEC_TOW_REQ`, `OFICINA_TUNE`,
`OFICINA_PREVIEW` e `OFICINA_NITRO_KIT` agora exigem lease; não há compatibilidade insegura.
