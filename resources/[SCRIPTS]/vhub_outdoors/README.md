# vHub Outdoors

Outdoors globais administrados pelo servidor. Suporta:

- imagem Discord CDN ou Imgur direto: PNG, JPG, JPEG, WEBP e GIF;
- video Discord CDN: MP4 e WEBM;
- video YouTube por URL normalizada para `videoId`.

O DUI visual permanece mudo. O audio 3D e delegado ao `vhub_wow`, com no maximo tres fontes
proximas por jogador, atenuacao por distancia, ducking de voz em 90% e retry exponencial.

O cliente recusa midia acima de 8 megapixels, lado acima de 4096 px ou video Discord acima de
30 minutos.

## Comandos

```text
/outdoor
/outdoorremover <id>
/outdoorlistar
/outdoorcontrole <outdoor_id> <char_id>
```

`/outdoor` abre o criador visual. Escolha o tamanho, cole a URL pura sem `< >` ou `[ ]` e
confirme. A mesma interface lista e remove outdoors ativos com confirmacao dupla. O comando
direto antigo continua aceito:
`/outdoor <pequeno|medio|grande> <url> [titulo]`.

Presets fixos:

- `pequeno`: `prop_tv_flat_michael`, tela de 1,46 x 0,82 m;
- `medio`: `prop_huge_display_02`, tela de 8,49 x 4,79 m;
- `grande`: `prop_billboard_10`, painel de 12,00 x 3,92 m com estrutura de solo.

No pequeno e medio, mire no centro da parede. No grande, mire no ponto do chao onde a base deve
ficar. O prop fantasma mostra a posicao final; `E` confirma e `Backspace` cancela.

Permissao: owner `uid=1`, ACE `vhub.admin.full`, ACE `vhub.outdoors.manage` ou permissao
`outdoors.manage` no `vhub_groups`.

## Controle remoto

Cada outdoor criado por `/outdoor` entrega ao administrador um controle nao empilhavel,
desde que existam peso e slot livres. Cinco dispositivos com cinco slots livres geram cinco
controles separados. Se a mochila estiver cheia, libere um slot e use
`/outdoorcontrole <outdoor_id> <char_id>` para entregar ou reatribuir.
Cada item controla exatamente um dispositivo por `outdoor_id + access_key`. Emitir outro
controle para o mesmo dispositivo revoga o anterior; nenhum controle opera outro dispositivo.

Ao usar o item perto do dispositivo, o jogador pode:

- ajustar o volume persistido;
- trocar para YouTube, Discord CDN ou imagem/GIF direto do Imgur;
- reposicionar o mesmo prop com preview e confirmacao por `E`.

Toda acao revalida no servidor personagem, slot, serial, chave, distancia, URL e geometria.
`vhub_inventory` e owner do item; `vhub_outdoors` e owner da midia, volume e posicionamento.

## Exports server-side

Todos ficam default-deny por `VHubOutdoors.cfg.trusted_resources`.

```lua
exports.vhub_outdoors:CreateOutdoor(actorSource, {
  operation_id = 'pedido:123456',
  title = 'Evento da cidade',
  media_url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  size = 'medium',
  center = { x = 0.0, y = 0.0, z = 1.5 },
  normal = { x = 0.0, y = 1.0, z = 0.0 },
})

exports.vhub_outdoors:RemoveOutdoor(
  actorSource,
  outdoorId,
  'remocao:123456',
  'Campanha encerrada'
)

exports.vhub_outdoors:ListOutdoors()
```

Contratos:

- `CreateOutdoor` retorna `{ ok=true, id, replayed, size }` ou `{ ok=false, err }`;
- `size` aceita `small`, `medium`, `large` ou os aliases PT-BR;
- `CreateOutdoor` aceita somente `size + center + normal`; tamanho arbitrario e recusado;
- em exports, `center` e o ponto central da superficie; o renderer aplica `surface_offset`;
- `RemoveOutdoor` exige `operation_id` idempotente e retorna `{ ok=true, id, replayed }`;
- `ListOutdoors` retorna `{ ok=true, revision, items }`;
- erros estaveis: `forbidden`, `not_ready`, `invalid_payload`, `invalid_operation`,
  `invalid_reason`, `remote_media_rejected`, `offline`, `limit`, `busy`, `conflict`,
  `not_found` e `storage`.

## Migracao 3.1.0

Adiciona controle remoto 1:1, volume persistido, auditoria de updates, GIF/Imgur e ducking
individual via `vhub_wow`. IDs SQL usam `AUTO_INCREMENT`; a VRAM so muda apos releitura e
validacao do commit. O plano do telao medio passa de 15 mm para 50 mm a frente do fundo para
eliminar z-fighting a media e longa distancia. Ativacao, revogacao, controlador e auditoria
do controle fecham na mesma transacao, com unicidade SQL de um grant ativo por outdoor.
Falha definitiva de imagem ou video recicla o slot DUI com backoff.

## Migracao 3.0.7

Offset do plano DUI agora respeita o depth buffer de cada prop: TV 6 mm, telao medio
15 mm e billboard 1 mm. Evita o fundo original cobrir o video conforme a distancia.

## Migracao 3.0.6

Distancia visual por preset, independente do audio:

- `pequeno`: carrega em 100 m e descarrega em 150 m;
- `medio`: carrega em 180 m e descarrega em 200 m;
- `grande`: carrega em 250 m e descarrega em 300 m.

O frustum da camera serve apenas para priorizar slots; sair da tela nao destroi mais o DUI.
O LOD do prop acompanha a distancia de descarregamento do preset.

## Migracao 3.0.5

Cada slot mantem `TXD + TXN + DUI + texture` durante todo o runtime. Trocas de outdoor usam
`SetDuiUrl`; o DUI so e destruido no stop do resource. Isso elimina textura duplicada,
primeiro frame congelado e falhas intermitentes apos unload/reload.

O canvas DUI permanece 16:9 e a viewport compensa o aspecto fisico do prop antes do
mapeamento, evitando distorcao no outdoor largo. Playback so fica pronto apos avanco real
de `currentTime`, com retry de 1 Hz e um unico reload. Audio aguarda lifecycle `ready`
por 15 s antes de destruir e recriar a fonte com backoff.

## Migracao 3.0.4

Captura e retem o handle `int64` da runtime texture via `Citizen.InvokeNative`, evitando
snapshot no primeiro frame. YouTube aguarda `onReady` antes de forcar playback. O
`prop_billboard_10` usa a face local correta, sem imagem no verso.

## Migracao 3.0.3

O plano DUI dos props fica exatamente 1 mm a frente da tela original pela normal mundial.
Os tres presets podem manter video e audio simultaneos no mesmo cliente.

## Migracao 3.0.2

Compatibilidade temporaria com artifacts cujo binding nomeado retorna `nil`. Substituida em
3.0.4 pela captura raw explicita do handle `int64`.

## Migracao 3.0.1

Corrige o lifecycle da textura DUI aguardando o DUI antes da criacao. Videos e
YouTube recebem audio 3D pelo `vhub_wow`, inclusive registros legados sem prop. A NUI passa a
listar e remover outdoors ativos sem exclusao fisica do historico SQL.

## Migracao 3.0.0

O schema adiciona a coluna nullable `size`. Novos registros persistem o preset e criam props
locais sem colisao; registros antigos sem preset continuam como paineis planos, sem
reposicionamento destrutivo. Cada outdoor ativo ocupa um dos quatro slots DUI persistentes.
Cada cliente carrega no maximo quatro outdoors proximos e tres midias de video simultaneas.

As dimensoes dos tres presets mudaram para acompanhar a area real de cada modelo. A viewport
precompensa o aspecto de cada tela para preencher o prop sem barras nem deformacao final.

## Migracao 2.0.0

O payload antigo de `CreateOutdoor` com `top_left` e `bottom_right` foi removido. Consumidores
devem enviar `size`, `center` e `normal`. Nenhum consumidor interno do vHub usava o contrato
antigo.

O schema `sql/schema.sql` e aplicado no boot. A tabela vendor antiga `posters` nao e alterada
nem apagada. Links assinados do Discord podem expirar no provedor; o resource nao contorna essa
expiracao.
