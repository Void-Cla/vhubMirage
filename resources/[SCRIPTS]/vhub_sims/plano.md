# vhub_sims — Plano Técnico (Character Creator Definitivo vHub)

> **Status:** ADR #74 implementada em SIMS 1.0.1; smoke FiveM/DB e resmon pendentes.
> **Data:** 2026-07-19 · **Base analisada:** CLAUDE.md (L-01..L-19, A-01..A-10), `manual_dev_vhub.md` v2.0,
> `contexto.md` (#70/#71), código real de `vhub_hss` 2.0.2, `vhub_identity`, `vhub_login`, `vhub_spawselector`,
> `vhub_money`, `vhub_target`, CORE v2.0.0-alpha.5 + 7 exemplos arquivados em
> `metas/vhub_sims_exemplos/`.
>
> ⚠️ **Correção de premissa da task:** o contexto fixo menciona "Core: vRP2 oficial". O código real é
> **CORE vHub `compat: none`** (shim vRP removido em Frozen v1.0). Pela hierarquia de verdade
> (código > doc), todo o plano usa exclusivamente `exports.vhub:*` e contratos vHub. Nenhuma
> API vRP será consumida — os exemplos vRP servem só como referência de UX/feature-set.

---

## 0. Errata vinculante de implementação — ADR #74

Esta seção substitui qualquer contrato incompatível descrito abaixo. O código vivo mostrou que
`spawnAt` consome o pending do HSS, `setCustomization` substitui o perfil inteiro e o pagamento
dry→commit→real não é recuperável. A implementação usa os contratos abaixo.

### 0.1 Matriz pública estável

Todos os retornos usam `{ok:boolean, err?:string, ...}`. Repetir o mesmo `request_id`/`operation_id`
com o mesmo payload retorna o mesmo resultado; payload divergente retorna `conflict`.

| Owner | Export | Allowlist | Escopo | Sucesso | Erros estáveis |
|---|---|---|---|---|---|
| CORE | `createCharacter(src, request_id)` | `vhub_login` | online; UID derivado; cap 3 | `{ok=true,char_id,replayed}` | `forbidden,offline,invalid_request,limit,conflict,storage` |
| CORE | `getSimsCreation(src)` | `vhub_login,vhub_sims,vhub_hss` | online; char atual derivado | `{ok=true,created,apv}` | `forbidden,offline,no_character,storage` |
| CORE | `commitSimsCreation(src, request_id, apv)` | `vhub_sims` | online; char atual derivado | `{ok=true,created=true,replayed}` | `forbidden,offline,no_character,invalid_request,conflict,storage` |
| CORE | `getCharacterIds(src)` | `vhub_login,vhub_hss,vhub_identity,vhub_sims` | online; UID derivado; cap 3 | `{ok=true,items=[char_id...]}` | `forbidden,offline,storage` |
| HSS | `beginPendingStage(src, session_id)` | `vhub_sims` | pending+char; destino fixo server | `{ok=true,stage_token}` | `forbidden,offline,not_pending,conflict,native` |
| HSS | `endPendingStage(src, stage_token)` | `vhub_sims` | restaura hold/bucket 999; não consome pending | `{ok=true,replayed}` | `forbidden,offline,invalid_token,conflict,native` |
| HSS | `getCustomization(src)` | `vhub_sims,vhub_login` | char atual; cópia | `{ok=true,customization,revision}` | `forbidden,offline,not_ready,no_character,storage` |
| HSS | `sanitizeCustomizationPatch(patch)` | `vhub_sims` | tamanho ≤8 KiB; normalização canônica APV2 | `{ok=true,patch}` | `forbidden,invalid_patch` |
| HSS | `getCharacterSummaries(src)` | `vhub_login` | IDs derivados no CORE; cap 3 | `{ok=true,items=[{char_id,customization,revision}]}` | `forbidden,offline,storage` |
| HSS | `commitCustomization(src, patch, expected_revision, operation_id)` | `vhub_sims` | merge canônico APV2; CAS | `{ok=true,customization,new_revision,rollback_token,replayed}` | `forbidden,offline,invalid_patch,conflict,storage,native` |
| HSS | `rollbackCustomization(src, rollback_token)` | `vhub_sims` | one-shot; CAS na revisão posterior | `{ok=true,new_revision,replayed}` | `forbidden,offline,invalid_token,conflict,storage,native` |
| Identity | `getCharacterSummaries(src)` | `vhub_login` | IDs derivados no CORE; cap 3; só campos públicos | `{ok=true,items=[{char_id,firstname,lastname,age}]}` | `forbidden,offline,storage` |
| Identity | `setIdentity(src, data, operation_id)` | `vhub_sims` | nome/idade; preserva RG/telefone | `{ok=true,identity,replayed}` | `forbidden,offline,invalid_identity,conflict,storage` |
| Money | `commitPayment(src, amount, operation_id, reason)` | `vhub_sims` | char atual; débito atômico | `{ok=true,charged,wallet_debit,bank_debit,replayed}` | `forbidden,offline,invalid_amount,insufficient,conflict,storage` |
| Money | `refundPayment(operation_id)` | `vhub_sims` | offline-safe; char/split derivados da operação | `{ok=true,refunded,replayed}` | `forbidden,not_found,conflict,storage` |
| SIMS | `needsCreation(src)` | `vhub_login` | consulta CORE | `{ok=true,needed}` | `forbidden,offline,not_ready,conflict,storage` |
| SIMS | `beginCreation(src, request_id)` | `vhub_login` | abre estágio HSS e sessão | `{ok=true,session_id}` | `forbidden,offline,not_ready,invalid_request,already_created,conflict,dependency,storage` |

Exports sensíveis são default-deny por `GetInvokingResource()`. APIs batch recebem somente `src`:
nenhum caller envia `char_id`. Client/NUI nunca recebe destino de bucket ou permissão de spawn.

### 0.2 Persistência, ownership e migração

| Tabela/alteração | Owner/escritor | Invariante |
|---|---|---|
| `vh_character_requests` | CORE | PK `(user_id,request_id)`, UNIQUE `char_id`, FKs user/char; criação bloqueia `vh_users FOR UPDATE` e grava personagem+request na mesma transação |
| `vh_sims_creation` | CORE | PK `char_id`, UNIQUE `request_id`, FK char; INSERT-once e re-read antes do ACK |
| `vhub_hss_state.customization_revision` | HSS | revisão exclusiva de aparência; independente da revisão fisiológica global |
| `vhub_hss_customization_ops` | HSS | PK `operation_id`; digest imutável, snapshots before/after, revisões before/after e estado `committed|rolled_back` |
| `vh_identity_operations` | Identity | PK `operation_id`; char, digest e resultado persistidos; replay após restart e conflito de payload |
| `vh_money_operations` | Money | PK `operation_id`; digest, valor e split carteira/banco imutáveis; estado `charged|refunded` |
| `vhub_sims_sagas` | SIMS | UNIQUE `(char_id,session_id)` e UNIQUE `request_id`; mapping durável request→session, estados `prepared|charged|customized|completed|refunded|manual_reconcile`; payload/digest/valor imutáveis |
| `vhub_sims_outfits` | SIMS | presets por char; nomes normalizados; FK do personagem |

Schemas usam `CREATE TABLE IF NOT EXISTS` e `ALTER ... ADD COLUMN IF NOT EXISTS`; nenhum rename ou
remoção. A saga é retomada no login/boot: `charged` sem customização tenta refund; `customized`
finaliza identidade+flag; conflito vai para `manual_reconcile` com log explícito.

### 0.3 Fluxo canônico corrigido

`charselect → creating(session_id,char_id) → charselect`; somente `spawning` abre o selector.
Personagem sem `sims_created` nunca avança ao spawn. O login fecha por `CREATION_HANDOFF`, sem disparar
o evento `CHAR_OK`. O HSS mantém pending e bucket 999 durante todo o criador.

No checkout pago: persistir saga → `commitPayment` → `commitCustomization` CAS → concluir. Falha HSS
executa `refundPayment(operation_id)` idempotente e offline-safe; retry/outbox permanece durável. Na criação gratuita:
customização HSS → identidade com ACK/re-read → `commitSimsCreation` por último.

Câmera, foco, rotação, snapshot/restore, preview efêmero, modelo, coordenadas e cleanup pertencem ao
client HSS. O client SIMS apenas encaminha intenções da NUI. Cancel/stop chama `endPendingStage`,
reaplica APV2 autoritativo e permanece no hold 999.

Versões desta ADR: CORE `2.0.0-alpha.6`; HSS `2.2.1`; Identity `1.1.1`;
Money `2.1.1`; Login `0.3.0`; Spawn Selector `2.1.1`; SIMS `1.0.1`.

## 1. Resumo executivo

`vhub_sims` é **um único resource** com **uma engine de aparência** e **N vitrines** (modos de menu
compostos por subconjuntos de abas — padrão validado no `bl_appearance`):

| Vitrine | Abas | Cobrança | Gatilho |
|---|---|---|---|
| **Criador** (1º spawn) | herança, rosto, cabelo, sobrancelha/barba, maquiagem, roupas básicas + wizard de identidade | grátis | pós-pick do `vhub_login` (ponte já reservada no código) ou fallback 1º spawn |
| **Barbearia/Maquiador** | cabelo, barba, sobrancelha, maquiagem, batom, blush | por categoria alterada | zona `vhub_target` |
| **Tatuador** | tatuagens por zona corporal | por tatuagem aplicada/removida | zona `vhub_target` |
| **Loja de roupas** | drawables + props (vestuário) | por peça alterada | zona `vhub_target` |
| **Cirurgião** (fase final) | herança + rosto | premium | zona `vhub_target` |

**Decisão de ownership central (L-04/R4):** `vhub_sims` **não persiste aparência**. A verdade da
aparência já tem dono — `vhub_hss` (`profile.customization`, por `char_id`, com fila SQL
revisão+digest do #70). O vhub_sims é **editor + regra de negócio**: monta o patch, valida, cobra,
e **comita via `exports.vhub_hss:setCustomization`** (contrato gated existente). O que o vhub_sims
possui de dado próprio: **outfits** (presets nomeados, tabela própria), **flag de criação concluída**
(chave CData própria) e **catálogo/preços** (config estática).

**Pré-requisito estrutural:** o shape de customização do HSS hoje é v1 (drawable/prop/overlay/
hair_color, head blend fake em `native_bridge.lua:140`). O plano inclui a **extensão para v2**
(herança real, 20 face features, cor de olho, tatuagens) — diff gated no HSS, detalhado no §6.3.

---

## 2. Achados da FASE 1 — varredura de `exemplos/`

### 2.1 Classificação (1 categoria por exemplo, conforme task)

| Exemplo | Categoria | Stack | Estado do código | Aproveitável |
|---|---|---|---|---|
| `bl_appearance-main` | **Criador** (cobre as 3) | TS client/server + Svelte + oxmysql | limpo, moderno, legível | arquitetura de menus-por-abas, câmera por bone, toggles com hook, outfits por job, blacklist, tattoo c/ opacidade |
| `dpn_criacao` | **Criador** | Lua vRP decompilado + jQuery NUI | decompilado, globals vazando | feature-set (19 face features, presets, cutscene), sala subterrânea, fluxo wizard |
| `disney-character` | **Criador** | Lua vRP + Vue NUI | legível, antigo | wizard 3 passos, câmera céu→chão, máquina de estados `spawnController` |
| `nation_skinshop` | **Criador** (vestuário/loja) | Lua vRP + NUI própria | legível, globals | **modelo de carrinho**: preço por peça/textura, insert/remove listing, câmera por categoria, esconder players |
| `vrp_skinshop` | **Criador** (vestuário/loja) | Lua vRP + NUI | simples | contrato mínimo de loja; preço random no server (anti-exemplo) |
| `vrp_barbershop` | **Cabeleireiro/Maquiador** | Lua vRP + NUI | legível | escopo exato de abas de barbearia (6 overlays + cabelo), cancelar restaura, share do schema com criador |
| `york_barbershop` | **Cabeleireiro/Maquiador** | Lua ofuscado ("prime-auth") + React build | **caixa-preta** | só UX: cadeiras individuais por loja, catálogo fotográfico por gênero |

*(nenhum exemplo é puramente "Tatuador"; a referência de tattoo vem do `bl_appearance` — dados, zonas corporais e aplicação.)*

### 2.2 Base mínima comum (o que TODOS fazem)

- Preview ao vivo no próprio ped (native aplicada na hora, sem screenshot).
- Câmera scriptada com foco por região (corpo/rosto/pernas) + rotação do ped controlada pela NUI.
- Cancelar restaura estado anterior capturado na abertura.
- Persistência JSON por identificador de personagem; re-aplicação no spawn.
- Congelar ped + esconder HUD durante edição.

### 2.3 Diferenciais únicos (o melhor de cada um)

| Origem | Diferencial a absorver |
|---|---|
| `bl_appearance` | menus = subconjuntos de abas (1 engine, N lojas); câmera orbital por **bone** (31086/24818/…) com interp 250ms + DOF raso; toggle de peça com **hook** (tirar camisa ajusta torso); outfits: salvar/renomear/apagar/**compartilhar por job+rank**/outfit-como-item; blacklist por job/gang (modelo, drawable, textura); tattoo com opacidade (N× `AddPedDecorationFromHashes`); bucket por player; comando admin para abrir no alvo; migração de schemas legados |
| `dpn_criacao` | cobertura completa de sliders nomeados (19 `SetPedFaceFeature` + 11 overlays com cor por tipo); presets por gênero; sala subterrânea (`402.6, -997.2, -98.3`); cutscene `mp_intro` com clone do ped; formulário nome/sobrenome/idade integrado |
| `disney-character` | wizard em etapas com validação antes de avançar; câmera descendo do céu (chegada cinematográfica); estado de criação como máquina de estados persistida |
| `nation_skinshop` | **carrinho com preço por peça** (default por categoria → override por drawable → por textura; modos insert/remove); câmera automática por categoria em edição; total só do **diff** vs roupa inicial |
| `vrp_barbershop` | recorte exato de abas de barbearia; barbearia grava no MESMO schema do criador (1 verdade) |
| `york_barbershop` | UX de **cadeira** (spots individuais com heading/câmera fixos por cadeira); catálogo com foto por gênero |

### 2.4 Gaps (o que NENHUM exemplo faz bem) → viram requisitos

1. **Servidor autoritativo de verdade**: todos aceitam JSON/total do client (vrp_skinshop até sorteia preço). → vhub_sims: servidor recalcula preço pelo diff e sanitiza todo patch (§7).
2. **Validação de shape/range**: nenhum clampa índices server-side. → `clean_custom` v2 no HSS + pré-validação no sims.
3. **Resmon**: threads `Wait(0)`/`Wait(1)` permanentes (nation esconde players a 60fps; vrp_barbershop rasteja marcadores a 25ms). → zero thread idle; zonas via `vhub_target`; câmera callback-driven.
4. **Replay/reconexão**: nenhum tolera re-disparo de spawn/queda no meio da criação. → replay-guard L-17 + sessão server-side com cleanup.
5. **Atomicidade pagamento↔aplicação**: nenhum trata falha entre cobrar e salvar. → ordem dry-run→aplicar→cobrar→(rollback) §7.5.
6. **Identidade visual/CEF**: CDN de imagem (dpn), fonts remotas, React build. → A-09/A-10: tudo local, vidro simulado, sem build step.
7. **Terceirização de aplicação no spawn**: cada um re-aplica por conta própria. → aplicação no spawn JÁ é do HSS; sims não toca esse ciclo.

---

## 3. Arquitetura proposta

### 3.1 Posição nas camadas

```
L1 (kernel vhub_sims/core/server) → sessão de edição, catálogo/preço, diff, cobrança, commit p/ HSS,
                                    outfits SQL, blacklist, gates
L2 (HAL vhub_sims/core/client)    → câmera orbital, preview local (natives), conceal de players,
                                    snapshot/undo local, ponte NUI
L3 (web/runtime)                  → engine NUI própria (router/store/eventbus/native bridge)
L4 (web/modules/*)                → studio (abas de edição), wizard (identidade), checkout (carrinho)
FORA do vhub_sims                 → verdade da aparência (vhub_hss), identidade (vhub_identity),
                                    dinheiro (vhub_money), zonas (vhub_target), spawn (hss/selector/login)
```

### 3.2 Árvore de arquivos (estrutura recomendada do CLAUDE.md para resource novo)

```
vhub_sims/
├── fxmanifest.lua                  ← todo arquivo listado no MESMO commit (L-15)
├── config/
│   ├── catalog.lua                 ← categorias, componentes, faixas de preço, modos de vitrine
│   ├── shops.lua                   ← zonas/cadeiras {x,y,z,h} (vec4 LOCAL; flat na fronteira, L-19)
│   ├── blacklist.lua               ← drawable/textura bloqueados + liberações por grupo
│   └── tattoos.lua                 ← coleções DLC vanilla: {dlc, hash, zone, label, price}
├── core/
│   ├── shared/
│   │   ├── config.lua              ← `VHubSims = VHubSims or {}` + cfg + cfg.rates (global, sem return)
│   │   ├── events.lua              ← VHubSims.E.* (R9 — única fonte de nomes de evento)
│   │   └── apshape.lua             ← helpers PUROS do shape apv2 (diff, clamp espelho, merge) — usados por server E client
│   ├── server/
│   │   ├── sql.lua                 ← promise-wrap oxmysql (padrão §3.6 do manual)
│   │   ├── core.lua                ← hasPerm, rate O(1) c/ cleanup em playerDropped
│   │   ├── init.lua                ← schema idempotente, sessões, replay-guards L-17
│   │   ├── session.lua             ← máquina de estados por src (idle→studio→checkout→committing)
│   │   ├── pricing.lua             ← preço = f(diff, catálogo, vitrine) — ÚNICO calculador
│   │   ├── creation.lua            ← fluxo criador: gatilho, wizard, finalize (custom+identity+flag)
│   │   ├── shops.lua               ← registro de zonas no target, abertura por vitrine, gate de grupo
│   │   ├── outfits.lua             ← CRUD vhub_sims_outfits + aplicar preset (via commit HSS)
│   │   └── exports.lua             ← API pública gated default-deny (export-first, R3)
│   └── client/
│       ├── init.lua                ← estado local, abre/fecha NUI, SetNuiFocus(false,false) em TODO close
│       ├── camera.lua              ← câmera orbital por bone (estilo bl) — callback-driven, zero loop idle
│       ├── preview.lua             ← aplicação LOCAL de patch p/ preview + snapshot/undo/redo efêmeros
│       └── conceal.lua             ← NetworkConcealPlayer nos demais players enquanto studio aberto (1 Hz frio)
├── web/
│   ├── bootstrap/index.html        ← entrada única; html/body transparentes (A-09)
│   ├── runtime/                    ← mini-engine: router.js, store.js, eventbus.js, native.js (A-06)
│   ├── shared/                     ← tokens vHub (Areia+Dourado), componentes slider/stepper/color-swatch
│   └── modules/
│       ├── studio/                 ← abas de edição (heranca/rosto/cabelo/maquiagem/roupas/tattoo)
│       │   ├── index.html · style.css (`.mod-studio`) · app.js (lifecycle A-02 completo)
│       │   ├── store.js · events.js · services/ · views/<aba>.js
│       ├── wizard/                 ← identidade (nome/sobrenome/idade) — só no modo criador
│       └── checkout/               ← carrinho/diff/total/confirmar — só em vitrine paga
├── sql/
│   └── schema.sql                  ← APENAS vhub_sims_outfits (aparência NÃO tem tabela aqui)
└── assets/                         ← ícones SVG locais; SEM CDN (A-10). Fotos de catálogo = fase futura
```

**Responsabilidade única por arquivo** (L-09). Nenhum módulo NUI sem `onDestroy` (A-07).
Módulos lazy (padrão #71): `wizard`/`checkout` só montam quando navegados (A-05).

### 3.3 O que fica FORA (anti-inflação, gate simplicidade)

- ❌ Tabela própria de aparência (usaria L-04 como falso argumento — dono é HSS).
- ❌ Re-aplicação no spawn (HSS já re-aplica; segundo aplicador = corrida).
- ❌ Migração automática qb/esx/illenium (sem dado legado neste servidor; extension point via export, §4.4).
- ❌ Cutscene `mp_intro` no v1 (28s de risco de soft-lock; entra como polish opcional F6 com kill-switch).
- ❌ Screenshot/galeria de outfit (não há infra de imagem; nome + aplicar resolve).

---

## 4. Contratos de dados

### 4.1 Shape de aparência **apv2** (extensão do `profile.customization` do HSS)

Formato flat-key compatível com o v1 existente (chaves novas são aditivas; consumidor v1 ignora):

```
{
  model      = 'mp_m_freemode_01' | 'mp_f_freemode_01',        -- whitelist HSS existente
  heritage   = { shape_first=0..45, shape_second=0..45,        -- SetPedHeadBlendData real
                 skin_first=0..45,  skin_second=0..45,
                 shape_mix=0.0..1.0, skin_mix=0.0..1.0 },
  ['face:N']     = float -1.0..1.0,          -- N = 0..19 (SetPedFaceFeature)
  ['drawable:N'] = {d, t, palette},          -- N = 0..11 (mantém v1)
  ['prop:N']     = {d, t},                   -- N = 0..7  (mantém v1; -1 = clear)
  ['overlay:N']  = {value, c1, c2, opacity}, -- N = 0..12 (mantém v1; colourType derivado do N)
  hair_color = {c1 0..63, c2 0..63},         -- mantém v1
  eye_color  = 0..31,                        -- NOVO (SetPedEyeColor)
  tattoos    = { {dlc='<collection>', hash='<overlay>', zone=0..7}, ... },  -- NOVO, cap 40
}
```

Regras: strings de dlc/hash `^[a-zA-Z0-9_]+$` ≤64; números clampados; chaves desconhecidas
descartadas (forward-compat); cap total de chaves sobe de 48 → **96** no `clean_custom`.
Versionamento: campo `apv=2` gravado junto; ausência ⇒ v1 (defaults para chaves novas — **zero migração**).

**Fronteira (L-19):** o shape só carrega primitivos — atravessa NUI/eventos/exports como está.

### 4.2 SQL próprio (único)

```sql
CREATE TABLE IF NOT EXISTS vhub_sims_outfits (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  char_id    INT UNSIGNED NOT NULL,               -- FK vh_characters (INT UNSIGNED, errno 150)
  label      VARCHAR(48)  NOT NULL,
  outfit     BLOB         NOT NULL,               -- só drawables/props (json), NUNCA rosto/tattoo
  group_name VARCHAR(32)  DEFAULT NULL,           -- compartilhado por grupo (vhub_groups) — fase F5
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id), KEY idx_char (char_id),
  CONSTRAINT fk_simsoutfit_char FOREIGN KEY (char_id) REFERENCES vh_characters(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Cap: 10 outfits/char (config). Outfit é **preset de vestuário** — aplicá-lo passa pelo mesmo
pipeline diff→preço→commit (sem bypass de cobrança em vitrine paga). Aplicar outfit fora de zona
não existe no v1; entra como item futuro via inventory (extension point).

### 4.3 Chaves KV do domínio (batch do core — exige trust convar)

| Chave | Tipo | Conteúdo |
|---|---|---|
| `sims_created` | CData(char_id) | `{at=ts, apv=2}` — personagem passou pelo criador |

Registro de Ownership (L-07): 3 linhas novas — `vhub_sims_outfits` (owner sims), `sims_created`
(owner sims), e a linha existente `profile.customization` (owner **HSS**) ganha nota "shape apv2;
editor autorizado: vhub_sims via setCustomization".

### 4.4 Exports públicos do vhub_sims (R3 export-first, todos gated default-deny)

| Export | Assinatura | Invokers previstos |
|---|---|---|
| `needsCreation` | `(src) → bool` | vhub_login (ponte), vhub_admin |
| `beginCreation` | `(src) → bool` | vhub_login (ponte `REQUEST_CREATE`/pós-pick) |
| `openStudio` | `(src, mode, shop_id) → bool` | vhub_admin, scripts de job (futuro) |
| `resetAppearance` | `(src) → bool` | vhub_admin (re-roda criador no próximo fluxo) |
| `getOutfits` | `(src) → {…} \| nil` (cópia) | vhub_admin, inventory (futuro outfit-item) |
| `importAppearance` | `(char_id, apv2_table) → bool` | ferramenta de migração futura (valida+delega ao HSS) |

Todos: `_invoker_allowed()` + `GetInvokingResource()` + validação de args + alvo online (padrão §3.7 do manual).

### 4.5 Eventos (R9 — nascem em `core/shared/events.lua`, prefixo `vhub_sims:`)

| Constante | Direção | Payload (shape validado) |
|---|---|---|
| `SRV_OPEN_REQUEST` | client→server | `{shop_id}` — pedido por zona target (server revalida raio) |
| `SRV_CHECKOUT` | client→server | `{session_id, patch=apv2_parcial, outfit_id?}` — intenção final |
| `SRV_WIZARD_SUBMIT` | client→server | `{session_id, firstname, lastname, age}` (só modo criador) |
| `SRV_CANCEL` | client→server | `{session_id}` |
| `CLI_STUDIO_OPEN` | server→client | `{mode, tabs, catalog_slice, current=apv2, prices, session_id}` |
| `CLI_STUDIO_CLOSE` | server→client | `{reason}` |
| `CLI_CHECKOUT_RESULT` | server→client | `{ok, err?, charged?}` |
| (interno server) | TriggerEvent local | `vhub_sims:creationDone(char_id)` — p/ consumidores server-side |

*Não existe evento de preview*: mudança de slider é 100% local no client (nada sobe por interação).
Rates declarados em `cfg.rates` (checkout 1500ms, open 1000ms, wizard 1000ms, cancel 500ms) — §4.6 do manual.

### 4.6 Contratos externos consumidos (inalterados)

- `exports.vhub_hss:setCustomization(src, apv2)` / `spawnAt` / `teleport` / `beginActivity` / `endActivity` / `isConscious`.
- `exports.vhub_money:tryFullPayment(src, valor, dry)` (dry-run para checagem, real para débito).
- `exports.vhub_target:addBoxZone(...)` (zonas taggeadas `data.resource='vhub_sims'` → cleanup automático no stop).
- `exports.vhub:getUser(src)` / `listCharacters` / `getCData/setCData` (chave própria).
- `exports.vhub_groups:hasPermission` (blacklist/uniformes por grupo).
- `TriggerClientEvent('vHub:notify', src, kind_ptbr, msg)` (canal canônico #31).
- **Colon-call SEMPRE dentro de `pcall(function() return exports.x:y(...) end)`** (lição #58a — dot-call descarta o 1º arg).

---

## 5. Fluxo de UX detalhado

### 5.1 Criador (primeiro spawn)

```
login OK → PICK_CHAR OK → [login consulta sims:needsCreation]
  ├─ false → PROCEED_SPAWN (selector normal — fluxo atual intocado)
  └─ true  → sims:beginCreation(src):
      1. session[src] = {mode='creator', char_id, step='studio', session_id}
      2. HSS beginActivity(src)  → bucket de atividade (isolamento)
      3. HSS spawnAt(src, studio_pos)  → sala subterrânea (402.6,-997.2,-98.3 — interior sempre carregado)
      4. CLI_STUDIO_OPEN {mode='creator', tabs=[wizard, heranca, rosto, cabelo, pelos, maquiagem, roupas]}
      5. client: câmera orbital + FreezeEntityPosition + conceal 1Hz + NUI focus
      6. Wizard (etapa 1 obrigatória): nome/sobrenome/idade → SRV_WIZARD_SUBMIT (validação server §7.3)
      7. Edição livre: slider → preview.lua aplica native LOCAL (zero rede); modelo M↔F → commit imediato de {model} (§9.1)
      8. "Concluir" → SRV_CHECKOUT {patch=apv2_completo}
      9. server: sanitiza → HSS setCustomization → identity setIdentity → setCData sims_created
         → endActivity → CLI_STUDIO_CLOSE → client dispara selector RequestOpen (evento público existente)
     10. selector abre normalmente → spawn na cidade
```

- **Sem seleção de spawn dentro do criador** — devolve ao dono do fluxo (spawselector).
- **Voltar/Undo**: pilha de patches na NUI (client-only). "Resetar tudo" re-aplica snapshot da abertura.
- **Presets de partida**: 6 por gênero (config) — 1 clique aplica patch local.
- **Login desativado (`enabled=false`, dev)**: fallback no `vHub:playerSpawn` (com replay-guard L-17 +
  checagem `sims_created`) dispara o MESMO `beginCreation`. Um único caminho de estúdio.

### 5.2 Barbearia / Maquiador

```
olho (vhub_target) na cadeira → SRV_OPEN_REQUEST {shop_id}
  → server: revalida raio server-side (coords da config, 3.0m) + isConscious + rate
  → session {mode='barber'} (SEM beginActivity — edição in-place, mundo normal)
  → CLI_STUDIO_OPEN {tabs=[cabelo, sobrancelha, barba, maquiagem, batom, blush], prices}
  → client: cadeira = ponto de interação (scenario de sentar = polish F6);
     câmera orbital foca bone da cabeça; conceal ligado
  → edição → carrinho no rodapé mostra TOTAL do diff (recalculado localmente p/ UX;
     o total REAL é sempre recomputado no server)
  → "Pagar" → SRV_CHECKOUT {patch parcial só das chaves permitidas pelo modo}
  → server: filtra patch pela whitelist do modo (barber NÃO altera drawable/heritage/tattoo)
     → diff vs customização atual → preço → dry-run → commit → cobrança (§7.5)
  → CLI_CHECKOUT_RESULT — sucesso: toast + fecha; falha: mantém aberto com erro PT-BR
  → "Cancelar"/ESC: preview.lua re-aplica snapshot da abertura; só SRV_CANCEL sobe
```

### 5.3 Tatuador

Igual ao 5.2 com: `tabs=[tattoos]`; navegação por **zona corporal** (8 zonas, dados de
`config/tattoos.lua`); preview aplica/remove decoração local; preço por tatuagem nova
(remoção cobra taxa fixa); cap 40 tatuagens; patch final = lista `tattoos` completa desejada
(o diff server calcula adições/remoções).

### 5.4 Loja de roupas

Igual ao 5.2 com: `tabs=[roupas, acessorios]`; câmera automática por categoria
(mapa componente→bone, estilo nation); preço por peça (categoria→override por drawable→por
textura, modos insert/remove no catálogo); toggle "tirar/pôr" com hook de compensação
(máscara↔chapéu, torso↔camisa — tabela de toggles do bl); blacklist por grupo
(uniforme police só com `vhub_groups`).

### 5.5 Regras transversais de UX

- ESC sempre cancela com restauração local; `SetNuiFocus(false,false)` em TODO caminho de fechamento.
- Morte/inconsciência (HSS bag `hss_*`) durante studio → fechamento forçado com cancel.
- HUD: nada de `DisplayRadar` hijack (lição #69); ocultação de HUD delegada ao dono se houver canal.
- PT-BR em toda superfície; identidade Areia+Dourado; vidro **simulado** (A-09 — studio flutua sobre o jogo).

---

## 6. Integrações — diffs mínimos por resource

### 6.1 `vhub_identity` (alvo da task)

**Diff mínimo (aditivo, ~30 linhas; APIs legadas intocadas — restrição de compat):**

1. Novo export gated `setIdentity(src, {firstname, lastname, age})`:
   - `TRUSTED = { vhub_sims=true }` + `GetInvokingResource()`;
   - reusa `sanitizaNome`/faixa de idade/`upsertIdentity` existentes;
   - atualiza `user.identity` em memória + re-push `vhub_identity:load` (HUD sincroniza na hora);
   - `registration`/`phone` **não mudam** (documentos continuam gerados — produção real do nome, não dos docs).
2. Nenhuma mudança no fluxo random: continua sendo o fallback para personagem que (por corrida
   ou criador desativado) chegar sem identidade — **produção real** = criador sobrescreve depois.
3. (Opcional F2, decisão do dono) convar `identity_defer_random=1`: adia a geração random se
   `sims_created` ausente, evitando nome aleatório piscando no HUD antes do wizard. Sem a convar,
   comportamento atual preservado.

**Ordem no finalize do criador:** `setCustomization` → `setIdentity` → `setCData(sims_created)`.
Falha em `setIdentity` NÃO desfaz aparência (identidade tem fallback random; loga ERROR + notify).

### 6.2 `vhub_login` (ponte já reservada no código)

- `E.PICK_CHAR` (callback de sucesso): antes de `CHAR_OK`, `pcall exports.vhub_sims:needsCreation(src)`
  → true: `beginCreation(src)` e NÃO envia `PROCEED_SPAWN`; false/ausente/pcall-fail: fluxo atual
  (fail-open para o selector — aparência não é credencial; o gate de login continua fail-closed).
- `E.REQUEST_CREATE` (`init.lua:310`, TODO explícito): permanece `CREATE_UNAVAILABLE` no v1.
  Ligar exige export novo **gated no CORE** `createCharacter(src)` (o `Auth:createCharacter` existe
  em `auth.lua:277` mas não é exportado; hoje só o boot auto-cria o 1º char em `boot.lua:183`) →
  **ADR própria + gate arquiteto + bump de CORE** — programado como F7, fora do caminho crítico.

### 6.3 `vhub_hss` (diff gated — o maior; exige guardiões natives+segurança+persistência)

| Arquivo | Mudança |
|---|---|
| `server/ped.lua` | `clean_custom` v2: aceitar `heritage{}` (6 campos clampados), `face:N` (float -1..1, N 0..19), `eye_color` (0..31), `tattoos[]` (cap 40, strings validadas), cap total 48→96; grava `apv=2` |
| `server/state.lua` | `sanitize_customization` espelha o clean v2 (idealmente mesma função-fonte movida p/ shared do HSS) |
| `client/native_bridge.lua` | `apply_customization` v2: `SetPedHeadBlendData` REAL (heritage; substitui o fake da linha 140), loop `SetPedFaceFeature`, `SetPedEyeColor`, `ClearPedDecorationsLeaveScars` + loop `AddPedDecorationFromHashes` (1× por tattoo — SEM truque de opacidade N×, custo determinístico), ordem: model→heritage→features→overlays→hair→drawables→props→decorations |
| `shared/config.lua` | `PED_TRUSTED += vhub_sims`; `ACTIVITY_TRUSTED += vhub_sims` |
| versão | 2.0.2 → **2.1.1** + entrada no contexto.md via gate de revisão |

Compat: consumidores atuais de `setCustomization` (admin/coinshop/groups/spawselector) enviam
shape v1 — continua válido (aditivo). O monitor de réplica do HSS (`ped.lua:396-407`) já re-aplica
`profile.customization` quando o modelo diverge — troca de modelo no criador **passa pelo commit**
(nunca `SetPlayerModel` direto no sims; L-16 e o monitor brigariam).

### 6.4 `config/server.cfg`

`setr vhub_trusted_resources` **+= `vhub_sims`** (necessário p/ `setCData` da flag — lição #58c:
fora do trust, escrita KV é negada e a falha é silenciosa no fluxo).

### 6.5 `vhub_target` / `vhub_money` / `vhub_spawselector`

**Zero diff.** Target: zonas registradas 1× no boot com `data.resource='vhub_sims'` (cleanup
automático já existente no stop). Money: `tryFullPayment` dry+real. Selector: reaproveita o evento
público `vhub_spawselector:server:RequestOpen` no pós-criação.

---

## 7. Segurança e validações server-side

### 7.1 Zero-trust no payload

Todo handler: **shape → rate → getUser/char_id → sessão válida → domínio** (ordem fixa).
`patch` passa por: (a) whitelist de chaves **do modo** (barber não manda `drawable:*`; tattoo só
`tattoos`); (b) clamp espelho do `clean_custom` v2 (`apshape.lua` compartilhado); (c) cap de tamanho
(≤8KB pós-encode); (d) blacklist de drawable/textura (config) com bypass por grupo checado em
`vhub_groups` **no server**.

### 7.2 O client nunca decide

- Preço: recomputado do zero no server pelo **diff** (customização atual do HSS vs patch). O total
  da NUI é cosmético.
- Raio: `SRV_OPEN_REQUEST` revalida distância à zona server-side (coords da config, não do client).
- Identidade: `sanitizaNome` + faixa de idade no server (client só coleta).
- Modo: `session[src].mode` é server-side; chave de patch fora do modo = descartada + log warn.

### 7.3 Sessão como máquina de estados (anti multi-tab / anti-replay)

`idle → studio(session_id) → committing → idle`. Um `session_id` por abertura; `SRV_CHECKOUT`
com session_id divergente/ausente = no-op logado. `committing` bloqueia segundo checkout
(idempotência R14: reenvio do mesmo patch com mesmo session_id devolve o resultado anterior).
`playerDropped` limpa sessão + rate buckets + `endActivity` se criador.

### 7.4 Anti-dupe / anti-bypass

- Aparência não é item — sem superfície de dupe direta. O vetor real é **cobrança**: mitigado por
  preço-server + estado `committing` + rate 1500ms.
- Bypass de zona (abrir studio longe): impossível — abertura só via target→server-revalida ou
  exports gated.
- Uniforme/peça restrita via patch manual: blacklist roda no commit, não só na UI.

### 7.5 Ordem transacional do checkout pago (L-12 + compensação)

```
1. price = pricing(diff)            → 0? aplica sem cobrar (nada pago mudou) e encerra
2. tryFullPayment(src, price, DRY)  → false: 'saldo_insuficiente', mantém studio aberto
3. before = customização atual (cópia)
4. ok = HSS setCustomization(patch) → false: aborta sem cobrar
5. paid = tryFullPayment(src, price, REAL)
6. paid=false (corrida de saldo entre 2 e 5) → setCustomization(before) [compensação] + notify
7. audit: Logger + evento interno com {char_id, mode, price, diff_keys, session_id}
```

Mutação SQL própria (outfits) é single-statement atômica; nada de transação distribuída.

### 7.6 Replay-safety (L-17)

Handlers institucionais (`vHub:characterLoad`, `vHub:playerSpawn` no fallback dev) com snapshot de
`user.spawns`; `onResourceStart` do sims NÃO abre studio para ninguém (sessões zeradas; studio é
sempre re-solicitado). Restart do sims com studio aberto: client detecta stop → fecha NUI+câmera
local (`onClientResourceStop` próprio).

---

## 8. Performance / resmon (L-18 — orçamento como contrato)

| Contexto | Orçamento | Como |
|---|---|---|
| Server idle | ≤0.02ms | zero thread permanente; tudo evento/target |
| Client idle (fora de studio) | **0.00ms** | zero thread; zonas no target (custo vive no scan do olho) |
| Client studio aberto | ≤0.10ms p95 | zero thread quente; câmera e rotação somente por callback NUI; preview em delta coalescido a 10 Hz |
| Conceal | 1 Hz frio | lista de players ativos, conceal novos, unconceal total no close (sem o loop 60fps do nation) |
| NUI fechada | 0.00ms | RAF/interval/observer mortos no `onHide`/`onDestroy` (A-07) + guard `.hidden * {animation-play-state: paused}` (padrão #55) |
| Rede | ~0 no hot path | preview 100% local; sobe payload SÓ em open (catálogo fatiado do modo) e checkout (patch diff). Nada por slider (A-08 por construção) |
| SQL | frio | outfits CRUD sob demanda; flag via batch do core (setCData) |
| Custo por player | O(1) | sessões/rate por src com cleanup em drop |

Streaming de asset: componentes/props o GTA já faz sob demanda; troca de modelo usa
`RequestModel`+timeout+`SetModelAsNoLongerNeeded` (padrão HSS). Tatuagem: 1 chamada por item
(cap 40) só em preview/aplicação. Fallback de asset ausente: índice clampado pelos
`GetNumberOfPed*Variations` do ped vivo na NUI; coleção de tattoo inválida → pcall+skip+warn
no boot do catálogo.

---

## 9. Riscos e mitigação

| # | Risco | Mitigação |
|---|---|---|
| 1 | **Monitor do HSS re-seta o modelo durante o criador** (ped.lua re-aplica se modelo ≠ perfil) | troca M↔F no studio comita `setCustomization({model=...})` imediatamente (patch mínimo) — perfil acompanha o preview; nunca `SetPlayerModel` local |
| 2 | Bucket de atividade **compartilhado** (limitação conhecida do range do HSS — memória coinshop) | estúdio com N spots espaçados + conceal local; aceitável (criadores se verem é cosmético). Bucket per-src no HSS = dívida anotada, fora de escopo |
| 3 | Extensão do HSS reprovada nos gates | shape aditivo + sanitize espelhado + cap explícito; sem a extensão, plano B funcional: criador limita-se ao shape v1 (sem heritage/tattoo) |
| 4 | Corrida `characterLoad` random-identity × wizard | ordem natural: random roda no load, wizard sobrescreve no finalize; convar opcional §6.1.3 elimina o flash |
| 5 | Player cai/relog no meio da criação | nada persiste até finalize → flag ausente → criador reabre limpo; `endActivity`+cleanup no drop |
| 6 | Pagamento entre dry e real muda saldo | compensação §7.5.6 (revert + notify) |
| 7 | `AddPedDecorationFromHashes` com hash inválido (coleção ausente) | pcall por item + skip + warn; catálogo validado no boot |
| 8 | CEF: studio sobre o jogo com blur | A-09 desde o design: vidro simulado em camadas; ZERO `backdrop-filter` |
| 9 | NUI multi-tab / callback fantasma / double-submit | session_id + máquina de estados §7.3 |
| 10 | Drift doc×código (task menciona vRP2) | nota no topo deste plano; registrar no contexto.md via gate de revisão |
| 11 | `vh_identity` viola prefixo `vhub_<dom>_*` (drift herdado) | manter (compat legada exigida pela task); anotar dívida, não renomear |
| 12 | Ofuscados nos exemplos (york, dpn parcial) | nenhum código copiado; referências arquivadas fora do resource em `metas/vhub_sims_exemplos/` (L-15) |

---

## 10. Roadmap de implementação (ordem de build + dependências)

| Fase | Entrega | Depende de | Gates |
|---|---|---|---|
| **F0** | Contratos: HSS apv2 (§6.3) + trust convar + identity `setIdentity` + linhas de Ownership | — | arquiteto + natives + segurança + persistência + contrato |
| **F1** | Esqueleto do resource (árvore §3.2, manifest, schema, sessões, rates, exports stub) + engine NUI shell + câmera HAL | F0 | simplicidade + runtime + designer |
| **F2** | **Criador completo** (wizard identidade + herança/rosto/cabelo/roupas grátis + ponte login + fallback dev + finalize) | F1 | segurança + revisão |
| **F3** | **Barbearia/Maquiador** (zonas target, pricing por categoria, checkout pago §7.5) | F2 (reusa engine) | segurança + performance |
| **F4** | **Tatuador** (catálogo vanilla, zonas corporais, preço por unidade) | F3 (reusa checkout) | natives |
| **F5** | **Loja de roupas + outfits** (carrinho por peça, toggles c/ hook, blacklist por grupo, CRUD outfits) | F3 | contrato + persistência |
| **F6** | Polish: cirurgião (heritage+face pago), scenario de cadeira, presets fotográficos locais, cutscene opcional | F2..F5 | designer |
| **F7** | Multichar "criar personagem": export CORE `createCharacter` gated (**ADR + bump CORE**) + ligar `REQUEST_CREATE` do login | F2 | gate CORE completo |

**Definition of Done por fase** (além do checklist §6 do manual): smoke in-game descrito; resmon
antes/depois anexado; grep de fechamento (`SetPlayerModel|SetEntityCoords` fora de owner = 0 no
sims; `setCData` só em chave própria); rollback em 1 linha
(`git checkout HEAD -- "resources/[SCRIPTS]/vhub_sims/"` + reverter diffs externos por arquivo).

**Testes (vhub_testrunner, SOMENTE ambiente de teste):** unit server-side para `apshape.diff`,
normalização HSS APV2 (fuzz de payload hostil: NaN/inf/strings/nested), pricing (tabela de casos por modo),
máquina de sessão (transições ilegais), blacklist com/sem grupo. In-game: matriz criador
(login on/off × relog no meio × replay onResourceStart), checkout (saldo insuficiente, corrida
dry→real simulada), tattoo com DLC ausente, M↔F com monitor ativo.

---

*Plano gerado a partir de leitura integral dos 7 exemplos e do código vivo dos resources
integrados. Implementação F0–F8 concluída; smoke FiveM/DB, stress e resmon seguem obrigatórios antes de produção.*
