# VHUB Race Cinema System (VRCS)

> **Documento de design e arquitetura.** Não é código. Define ownership, contratos, fronteiras,
> modelo de segurança e faseamento do subsistema de replay cinematográfico do vHub Mirage.
> Escopo travado pelos agentes (`vhub_arquiteto` + `vhub_guardiao_seguranca` + `vhub_guardiao_simplicidade`)
> em 2026-06-25.

| Campo | Valor |
|-------|-------|
| Status | **DESIGN APROVADO — implementação aguardando ordem explícita do dono** |
| Tipo | Subsistema independente de eSports (replay → cinema), acoplado ao `vhub_racha` |
| Dono institucional do domínio replay | `vhub_vrcs` (resource novo, a criar) |
| Relação com o racha | **Consumidor passivo** da telemetria que o racha já valida (nunca 2ª fonte — L-04) |
| Fase atual | Apenas este documento. Nenhuma linha de código autorizada antes do gate do arquiteto por fase |

---


## ============================================================
## 1. FILOSOFIA DE ENGENHARIA
## ============================================================

**Nunca grave vídeo. Grave dados.**

Dados são leves, reproduzíveis infinitamente e versionáveis. Vídeo é apenas uma renderização
temporária e descartável desses dados. É o mesmo princípio que jogos competitivos usam para
oferecer replay cinematográfico sem sacrificar performance.

O VRCS **não** é um "gravador de replay". É um **subsistema de eSports**: a corrida gera
telemetria; a telemetria vira um arquivo proprietário leve (`.vhr`); esse arquivo pode ser
reproduzido, renderizado e publicado **fora** do servidor de jogo, de forma assíncrona e
desacoplada — sem que o servidor principal jamais renderize, encode ou faça upload de vídeo.

```
Corrida → telemetria validada → .vhr (leve) → fila → renderer isolado → vídeo → publicação
   ↑ servidor principal (barato)              ↑ fora do servidor de jogo (caro, assíncrono)
```


## ============================================================
## 2. PRINCÍPIOS FUNDAMENTAIS (CONTRATO INVIOLÁVEL)
## ============================================================

### O servidor principal NUNCA deve

- ❌ Gravar a tela dos jogadores.
- ❌ Usar Rockstar Editor ou captura OBS durante a corrida.
- ❌ Renderizar vídeo, fazer encoding em tempo real ou rodar FFmpeg.
- ❌ Gerar thumbnails ou fazer upload de vídeo.
- ❌ Depender da máquina do jogador para qualquer parte do pipeline.
- ❌ Fazer `PerformHttpRequest` externo (webhook) em produção.

### O subsistema DEVE

- ✅ Registrar **somente telemetria já validada** pelo servidor (server-authoritative).
- ✅ Ser assíncrono, desacoplado e tolerante a falhas.
- ✅ Ter o servidor principal carregando **só** o gravador leve (alvo: CPU 0.5–1%, RAM 10–30 MB).
- ✅ Mover toda renderização/encoding/upload para uma instância isolada, fora do jogo.
- ✅ Ser orientado a eventos (sem polling no caminho quente).
- ✅ Falhar de forma segura: o replay nunca pode quebrar o fim de corrida, o PDL ou o pagamento.


## ============================================================
## 3. DECISÕES DE ARQUITETURA (CRAVADAS PELOS AGENTES)
## ============================================================

### 3.1 Ownership e placement

| Componente | Onde vive | Roda no main? | Ownership |
|------------|-----------|---------------|-----------|
| **`vhub_vrcs`** | `resources/[SCRIPTS]/vhub_vrcs/` | **Sim** (leve) | **Escritor único** do domínio replay: arquivo `.vhr`, meta `vh_race_replays`, fila `vh_vrcs_jobs` |
| **`vhub_vrcs_renderer`** | `resources/[TOOLS]/vhub_vrcs_renderer/` | **Nunca** | Consumidor da fila (claim atômico). Instância FiveM dedicada, sem jogadores, **fora** do `resources.cfg` de produção |
| **Encoder (FFmpeg)** | processo externo | Não | Não é resource FiveM — binário/serviço orquestrado pelo renderer |
| **Publisher (Discord)** | processo externo / daemon | Não | Não é resource FiveM — consome jobs `done` e dispara o webhook |

> **Por que `vhub_vrcs` é resource próprio e não uma pasta dentro do `vhub_racha`:** colocar VRCS
> dentro do racha cria um módulo sem ownership/lifecycle próprios sob o dono errado (L-07/L-15).
> O racha continua dono soberano da telemetria; o VRCS é um **leitor** com domínio separado.
>
> Este documento (`vrcs.md`) é apenas um **artefato de planejamento** e pode viver onde está; o
> **código** do subsistema NÃO nasce dentro de `vhub_racha/`.

### 3.2 Fronteira racha ↔ vrcs (direção única, sem 2ª fonte de verdade)

O racha é e continua sendo o **escritor único** de toda verdade de corrida (telemetria, anti-cheat,
ranking, history). O VRCS:

- **NÃO** toca em nenhuma tabela `vh_race_*` do racha.
- **NÃO** cria um 2º stream de telemetria pelo cliente.
- **NÃO** recalcula nem revalida estado de corrida.

A telemetria que o VRCS grava é **exatamente** a que o racha já validou no ato. Direção:
**racha EMPURRA (push) → vrcs RECEBE.**

**Ponto de tap único** (auditado no código real do racha):

| Gancho | Arquivo | Papel |
|--------|---------|-------|
| `apply_telemetry` | `vhub_racha/server/runtime.lua:69` | **Fonte única** de telemetria (chamada por `on_tick:189` e `on_checkpoint:162`). Único ponto legítimo de captura de frame. |
| `HIS.finalize` | `vhub_racha/server/runtime.lua:281` | Gatilho de "corrida finalizada" — onde o `.vhr` fecha e o job é enfileirado. Já é replay-safe (finalize 1×). |

**Mecanismo recomendado — export do VRCS + soft-dependency:**

```lua
-- no racha (consumidor invertido): chama o VRCS se ele existir, sob pcall.
-- precedente: vhub_wow (soft-dep + pcall — o produtor nunca cai se o consumidor estiver off).
pcall(function()
  exports['vhub_vrcs']:onFrame(raceId, frame)   -- a cada apply_telemetry
end)
-- ...
pcall(function()
  exports['vhub_vrcs']:onRaceClose(raceId, meta) -- no finalize
end)
```

- Se `vhub_vrcs` estiver ausente/parado → o racha **não quebra**; o replay simplesmente não grava.
- Os exports do VRCS são **sensíveis**: `_invoker_allowed()` + `GetInvokingResource()`, **default-DENY**,
  `TRUSTED = { vhub_racha }` (espelha o padrão N0-2 dos exports do racha).
- **Não existe `RegisterNetEvent` no VRCS para "frame de replay"** — o cliente nunca alcança o VRCS.

> Alternativa (mais desacoplada, exige tocar contrato): o racha publica eventos institucionais
> `vhub_racha:telemetry` / `:raceClosed` no `shared/events.lua` e o VRCS escuta. Custo: passa pelo
> gate `vhub_guardiao_contrato` e exige replay-safety (L-17). Decisão: **export+pcall** no MVP.


## ============================================================
## 4. ESTRUTURA REUSÁVEL — CORE/KERNEL + BINDINGS
## ============================================================

O dono pediu explicitamente um **core/kernel que exporta funções, com as regras de negócio em
outro arquivo, reaproveitável em outros projetos**. Isso se materializa em **2 camadas reais**
(não na cerimônia "Clean Architecture" de 7 pastas do PRD — isso seria inflação sem ganho, L-09):

```
[SCRIPTS]/vhub_vrcs/
├── core/                         ← KERNEL agnóstico de corrida (exporta funções; REUSÁVEL)
│   ├── shared/
│   │   ├── vhr_schema.lua        ← contrato .vhr (versão, layout, validador) — FONTE ÚNICA
│   │   └── codec.lua             ← encode/decode .vhr (puro, sem I/O, sem side-effect)
│   └── server/
│       ├── recorder.lua          ← L1: abre / append (buffer RAM) / fecha replay (flush atômico)
│       └── queue.lua             ← L1: FIFO de render — enfileira; claim atômico
│
├── bindings/                     ← REGRAS DE NEGÓCIO (específico do racha; troca por projeto)
│   └── racha.lua                 ← mapeia a telemetria do racha → frame .vhr (CONSOME o core)
│
├── server/
│   └── init.lua                  ← composição: registra o binding e expõe os exports do core
├── config/
│   └── config.lua                ← Hz alvo, retenção .vhr, paths, flags de fase, convars
├── sql/
│   └── schema.sql                ← vh_race_replays + vh_vrcs_jobs (DDL idempotente)
└── fxmanifest.lua
```

### Regra de dependência (o que torna o core reaproveitável)

- `core/` **NUNCA** importa `bindings/`. É agnóstico: só conhece `{ t, entities[], events[] }`.
  Não sabe o que é "checkpoint", "drift" ou "racha".
- `bindings/` importa `core/`. Conhece o racha e traduz `apply_telemetry → frame`.
- `server/init.lua` é o **único** que conhece os dois (composição).

Resultado: a pasta `core/` inteira é **copiável** para outro projeto sem arrastar nada do racha
(ex.: um core de replay para perseguição policial usaria outro `bindings/`).

### Padrão de módulo (estilo vHub, não enterprise)

```lua
-- recorder.lua — gravador de replay (escritor único do .vhr)
local M = {}; M.__index = M; VRCS.Recorder = M

function M:open(raceId, meta) ... end   -- inicia buffer em RAM
function M:append(raceId, frame) ... end -- acumula frame (NÃO grava em disco por frame)
function M:close(raceId) ... end         -- serializa + flush atômico + enfileira

return M
```

Exports do core (regra de negócio chama de fora):
`vhub_vrcs:onFrame`, `:onRaceClose`, `:enqueue`, `:claimJob`, `:markDone` — todos com
`_invoker_allowed()`.


## ============================================================
## 5. CAMADAS, OWNERSHIP E LIFECYCLE (L-07)
## ============================================================

| Peça | Local | Ownership | Lifecycle |
|------|-------|-----------|-----------|
| **Recorder** | `core/server/recorder.lua` | escritor único do `.vhr` + `vh_race_replays` | nasce no 1º frame da corrida; vive em **buffer RAM** durante a corrida (nunca 1 I/O por frame); fecha no `onRaceClose` (flush atômico → enfileira). `onResourceStop` flusha buffers pendentes. |
| **Queue** | `core/server/queue.lua` | escritor único de `vh_vrcs_jobs` | item criado no close; estados `pending → claimed → done / failed`; **sem thread no main** (é tabela + exports). |
| **Renderer remoto** | `[TOOLS]/vhub_vrcs_renderer` | consumidor da fila (claim atômico) | **FASE 2.** Instância dedicada; faz `claim`, carrega `.vhr`, spawna veículos/peds, aplica frames (`SetEntityCoords`/`SetEntityRotation` — L-05), grava saída, marca `done`. |
| **Encoder** | processo externo (FFmpeg) | — | **FASE 4.** Disparado pelo renderer ao fim do passe de câmera. Timeout + privilégio mínimo. |
| **Publisher** | processo externo / daemon | — | **FASE 5.** Consome jobs `done` → webhook Discord. |

Cada peça tem cleanup explícito (`onResourceStop`). Sem `while true`; a fila é event/poll-gated
com condição de saída (L-06).


## ============================================================
## 6. CONTRATO `.vhr` (VHUB REPLAY) — VERSÃO 2
## ============================================================

`.vhr` = **VHUB Replay**. Arquivo proprietário, leve, versionado. **JSON puro** (ou binário de
campos fixos numa fase futura) — **NUNCA** serialização Lua executável (`load`/`loadstring`).

> **v1 → v2 (sem compatibilidade retroativa):** a v2 expande o frame para análise técnica de
> pilotagem (telemetria por roda, inputs, luzes) e muda o modelo de transporte (§7). Os 7 `.vhr`
> v1 existentes continuam em disco mas não são mais listados/reproduzíveis — `client/player.lua`
> recusa qualquer replay com `schema` diferente da versão atual (sem branch de compat permanente,
> custo de manter 2 formatos > benefício de reproduzir testes antigos).

### 6.1 Cabeçalho / meta da corrida

```json
{
  "schema": "vhub_racha.vhr.v2",
  "raceId": "UUID",
  "track": "city_night",
  "category": "ranqueada",
  "startTime": "ISO8601",
  "duration": 312,
  "winnerCharId": 17,
  "trust": { "authoritative": ["x","y","z","t","s","placement","timeMs"], "cosmetic": ["..."] },
  "players": []
}
```

`trust` formaliza em schema a classificação de autoridade da §6.3 (mesmo bloco que
`core/shared/vhr_schema.lua:S.TRUST` grava em cada replay novo).

### 6.2 Jogador

```json
{
  "charId": 17,
  "vehicle": "sultanrs",
  "events": [],
  "frames": []
}
```

> **PII (L-04 + segurança): o `.vhr` identifica o piloto SOMENTE por `charId`.** Nunca `identifier`,
> license, steam, IP ou nome. O nome de exibição é resolvido **só na hora de compor o embed**
> (via `resolve_nicks`/`vh_identity`, mesmo caminho do perfil) e **nunca** persiste no arquivo.
> Assim, `.vhr` e `.mp4` em repouso não são dado pessoal.

### 6.3 Frame (20 Hz / 50 ms — nunca 60 fps)

```json
{
  "t": 15.2,
  "x": 120.12, "y": 421.11, "z": 31.90,
  "rx": 0, "ry": 0, "rz": 182,
  "s": 181, "rpm": 0.82, "g": 5, "st": -12.3, "hb": 0,
  "vv": { "x": 0.1, "y": 25.4, "z": -0.3 },
  "cl": 0.0, "th": 0.92, "eh": 1000,
  "tp": [0.1, 0.1, 0.2, 0.1], "bp": [0,0,0,0],
  "ws": [78.2, 78.1, 79.0, 78.9], "wc": [0.3, 0.3, 0.4, 0.4],
  "bf": 1, "lf": 5
}
```

**Classificação de autoridade dos campos** (decisão de segurança — evita campo fabricado no cliente):

| Campo | Autoridade | Origem |
|-------|-----------|--------|
| `x,y,z` | **Autoritativo** | posição final/colocação/tempo já decididos pelo `vhub_racha` antes da montagem do replay |
| `t`, `s`, `placement`, `timeMs` | **Autoritativo** | mesmo motivo — a verdade competitiva precede a existência deste artefato |
| `rx,ry,rz`, `rpm`, `g`, `st`, `hb` | cosmético, best-effort, NÃO-autoritativo | já era a classificação da v1 |
| `vv`,`cl`,`th`,`eh`,`tp`,`bp`,`ws`,`wc`,`bf`,`lf` (v2) | **cosmético, best-effort, NÃO-autoritativo** | gravado 100% client-side, sem validação server-side |

> **Concessão de segurança (v2, decisão do dono do projeto, 2026):** os campos cosméticos da v2
> podem ser manipulados pelo cliente sem risco de exploit, porque **quando o replay é montado a
> corrida já terminou**: colocação, tempo e premiação já foram decididos e persistidos pelo
> `vhub_racha` (autoritativo, fora do escopo deste arquivo). O `.vhr` é artefato de análise
> técnica pós-corrida — nunca fonte de verdade competitiva. Esta concessão **NÃO** se estende a
> nenhum campo da lista `trust.authoritative`, nem a qualquer dado que o `vhub_racha` já valida.

### 6.4 Coordenadas e fronteira (L-19)

No `.vhr` (JSON), coordenadas são **primitivos flat** (`{x,y,z,rx,ry,rz}` e `vv={x,y,z}`) — nunca
`vec3`/`vec4`. O vetor nativo só é reconstruído **no ponto de uso** (client/player.lua). Idem na
fronteira client→servidor: a coord cruza como `{x=,y=,z=[,h=]}` (msgpack/json destroem o vetor).

### 6.5 Eventos (registrados separadamente dos frames)

```json
{ "time": 55.1, "type": "overtake", "source": 17, "target": 22 }
```

Tipos: `OVERTAKE`, `COLLISION`, `DRIFT`, `NITRO`, `CHECKPOINT`, `JUMP`, `WINNER`, `PHOTO_FINISH`.
Cada evento também deriva de estado autoritativo do racha (nunca de declaração do cliente).

### 6.6 Consumo estimado (validação do "leve")

Corrida de 5 min, 10 jogadores, 20 amostras/s → 6.000 frames/jogador → ~60.000 registros →
frame v2 é ~3x mais pesado que v1 (36 valores vs ~12) → **teto `MAX_REPLAY_BYTES` 64 MB** cobre
corrida longa de 10 jogadores com margem. Buffer 100% em RAM durante a corrida; upload sequencial
fatiado só após o fim (§7).


## ============================================================
## 7. CAPTURA E TRANSPORTE DE TELEMETRIA (CLIENT-DRIVEN, UPLOAD PÓS-CORRIDA)
## ============================================================

- **Captura client-driven:** cada client amostra o próprio carro a 20Hz (`SAMPLE_MS`) via natives
  FiveM (`client/recorder.lua:sample()`) e acumula 100% em RAM (`R.buf`). **Zero rede durante a
  corrida** — elimina qualquer risco de lag/hitch na prova por causa do replay.
- **Upload único, sequencial, com ACK — disparado só após `recStop`:** ao fim da corrida o buffer
  é enviado em blocos de `SEND_CHUNK_FRAMES`, cada bloco aguarda confirmação do servidor
  (`vhub_vrcs:recAck`) antes do próximo, com retry (`SEND_MAX_RETRY`) e timeout por bloco
  (`SEND_TIMEOUT_MS`). Isto NÃO é chunking durante a corrida — é só o timing do envio que muda
  (tudo depois do fim), o mecanismo de ingest (`bindings/racha.lua:recData`) é o mesmo de antes.
- **Servidor não amostra.** Recebe blocos, valida remetente (`tr.srcs`), acumula via
  `core/server/recorder.lua:append_chunk` (sem I/O por frame — 1 flush atômico no close).
- **Fechamento orientado a confirmação, não a timer fixo:** `bindings/racha.lua:on_race_close`
  espera ativamente até todos os participantes rastreados confirmarem `final=true` OU o teto
  `SEND_TIMEOUT_TOTAL_MS` (60s) vencer — o que vier primeiro. Um participante lento/desconectado
  não trava o fechamento do replay dos demais (replay sai truncado só para quem não confirmou).
- Threads são **gateadas por `R.active`** e morrem em `onResourceStop` (L-06 — sem loop sem
  condição de saída).


## ============================================================
## 8. FILA DE RENDER (vh_vrcs_jobs)
## ============================================================

A fila **nunca** renderiza imediatamente. É FIFO, assíncrona, em banco (não em arquivo
compartilhado — evita TOCTOU/path traversal entre hosts).

```sql
-- vh_vrcs_jobs (escritor único: vhub_vrcs/core/server/queue.lua)
race_id     VARCHAR(36) NOT NULL,        -- UUID validado
vhr_path    VARCHAR(255) NOT NULL,
status      ENUM('pending','claimed','done','failed') DEFAULT 'pending',
attempts    INT UNSIGNED DEFAULT 0,
created_at  INT UNSIGNED NOT NULL
```

**Claim atômico (L-12)** — impede dois renderers pegarem o mesmo job:

```sql
UPDATE vh_vrcs_jobs SET status='claimed', attempts=attempts+1
 WHERE status='pending' ORDER BY created_at LIMIT 1;
-- + checagem de linhas afetadas / SELECT do job recém-marcado
```

**Circuit-breaker:** `attempts` máximo por job; ao exceder → `failed` + alerta admin
(sem retry infinito, L-06).


## ============================================================
## 9. MODELO DE SEGURANÇA (ZERO-TRUST, OBRIGATÓRIO)
## ============================================================

> **VRCS é consumidor passivo de verdade já validada.** Não introduz nenhuma nova fonte de verdade
> sobre a corrida (L-04). Toda telemetria que entra no `.vhr` é a MESMA que o `vhub_racha` já validou
> server-side. Zero-trust (L-01/L-02): payload = intenção, nunca verdade. O renderer é uma instância
> **cega e muda** — só lê arquivo/fila, nunca aceita comando.

### 9.1 Fonte da telemetria — client-driven, fail-closed na fronteira
Frame vem de `RegisterNetEvent('vhub_vrcs:recData', ...)` (`bindings/racha.lua`) — client-driven,
NÃO server-push. Isso é seguro porque todo campo do frame é **cosmético/não-autoritativo**
(`Schema.TRUST.cosmetic`, §6.3): a verdade competitiva (posição final, tempo, colocação, prêmio)
já foi decidida pelo `vhub_racha` ANTES deste evento existir — o VRCS nunca recebe nem persiste
um campo que o racha trataria como autoritativo. Fail-closed na fronteira mesmo assim: remetente
não-participante (`tr.srcs[src]`) ou corrida desconhecida (`find_by_rid`) descarta o bloco em
silêncio, sem ACK — o client trata como falha e re-tenta/desiste (L-01, L-02, L-03, L-04).

### 9.2 Superfície export/evento — default-deny, direção única
Exports do VRCS com `_invoker_allowed()` + `GetInvokingResource()`, **default-DENY**,
`TRUSTED={vhub_racha}` (N0-2). Direção única racha→vrcs. Rate-limit por origem espelhando
`_rl[src][tag]` + cleanup em `playerDropped`. Coord na fronteira = primitivo (L-19).

### 9.3 Renderer isolado
- Sem porta pública, sem RCON exposto, sem `RegisterCommand` acessível, sem net event de cliente.
- Toda entrada é **pull** de `vh_vrcs_jobs` (claim atômico, L-12) + leitura de `.vhr`.
- Bind em loopback/rede interna; firewall nega ingress externo (pré-requisito de deploy).
- FFmpeg com **timeout**, **quota de tentativas** e **privilégio mínimo** (usuário sem privilégio).

### 9.4 Discord webhook
- Segredo via **convar**: `GetConvar('vrcs_discord_webhook', '')`, de `server.cfg`/env, **nunca**
  versionado. Vazio → feature desligada (fail-closed, não erro).
- Embed: só nick + métricas de corrida (posição, tempo, divisão). **Zero PII sensível.**
- Nick é **dado hostil**: strip de menções (`@everyone`, `@here`, `<@id>`) + limite de comprimento
  antes de montar o JSON (princípio textContent/escape do `vhub_notify`, adaptado p/ Discord).
- `PerformHttpRequest` **só no renderer**; backoff em 429; webhook nunca bloqueia corrida/render.

### 9.5 Arquivo `.vhr`
- `raceId` = **UUID validado por regex** (`^[0-9a-fA-F-]{36}$`) antes de tocar em qualquer path.
- **Path traversal fechado:** rejeitar `..`, `/`, `\`; caminho = `BASE_DIR + uuid + '.vhr'` com
  `BASE_DIR` fixo + canonicalização (caminho resolvido tem de permanecer sob `BASE_DIR`).
- **Desserialização segura:** JSON/binário versionado; **nunca** `load`/`loadstring`. Parser valida
  `schema`/versão e rejeita campo desconhecido (sem code-exec).
- **Quota** de bytes por `.vhr` (10 Hz × duração máxima = cap previsível); estourou → trunca/aborta + job inválido.

### 9.6 Checklists de segurança por fase (gate de entrada de cada fase)

**Fase A — Captura (.vhr writer):**
- [ ] Frame deriva de `apply_telemetry` + pos do ped server-side (L-01); zero net event de cliente (L-04).
- [ ] Sem 2ª fonte de verdade; reaproveita estado do racha (L-04/L-09).
- [ ] Quota de bytes + cap de duração; sem loop sem saída (L-06); thread morre em `onResourceStop`.
- [ ] `charId` como única identidade no arquivo (sem PII).

**Fase B — Fila / canal main↔renderer:**
- [ ] Export de ingest com `_invoker_allowed()` default-DENY, `TRUSTED={vhub_racha}` (N0-2).
- [ ] `vh_vrcs_jobs` com claim atômico (L-12); sem SQL inline fora da camada de dados.
- [ ] Direção única racha→vrcs; renderer só faz pull. Coord cruza como primitivo (L-19).

**Fase C — Renderer isolado:**
- [ ] Sem porta pública, sem RCON, sem net event de cliente, sem `RegisterCommand` exposto.
- [ ] `raceId` UUID validado + path sob `BASE_DIR` canonicalizado (sem traversal).
- [ ] `.vhr` desserializado como dado versionado, sem `load`/`loadstring`.
- [ ] FFmpeg com timeout + privilégio mínimo + quota de tentativas.

**Fase D — Discord webhook:**
- [ ] Segredo via convar/env, fail-closed se ausente; nunca versionado.
- [ ] Embed sem PII sensível (só nick + métricas).
- [ ] Nick sanitizado (strip menção/limite) — dado hostil.
- [ ] `PerformHttpRequest` só no renderer; backoff em 429.

**Gate transversal (toda fase):** logs sem credencial/identifier/IP completo; broadcast `-1` nunca
carrega dado privado; rate-limit por origem com cleanup em `playerDropped`.


## ============================================================
## 10. FASEAMENTO (MVP + ROADMAP)
## ============================================================

### FASE 1 — MVP (único escopo autorizado a especificar/construir agora)

1. **Contrato `.vhr`** (v1 congelado, evoluído para v2 — §6): `vhr_schema.lua` + `codec.lua` + validador.
2. **Recorder client-driven**: cada client grava o próprio carro e envia pós-corrida
   (`bindings/racha.lua` consome via `recData`/`recAck`); `finalize` do racha (export + pcall) →
   1 `.vhr` por corrida. Buffer RAM, flush atômico no close.
3. **Persistência + queue**: `.vhr` em disco + `vh_race_replays` (meta) + `vh_vrcs_jobs` (FIFO).
4. **Critério de sucesso:** ao fim de uma corrida existe **1 `.vhr` válido** em disco e
   **1 linha `pending`** na fila. Nenhum frame de vídeo ainda. Custo no main provado.

### Roadmap (NÃO construir até gate do arquiteto por fase)

| Fase | Entrega | Pré-requisito |
|------|---------|---------------|
| F2 | `vhub_vrcs_renderer` (instância isolada): reprodução por `SetEntityCoords/Rotation` | MVP estável + `.vhr` validado em jogo |
| F3 | Motor de câmera cinematográfica (chase/drone/side/front/orbit/finish + decisão por prioridade de evento) | F2 |
| F4 | FFmpeg encode → `.mp4` (libx264, 1080p60, `-crf 20`, `+faststart`) | F3 |
| F5 | Discord Publisher (embed + arquivo) | F4 + convar de webhook |


## ============================================================
## 11. ANTI-INFLAÇÃO — CONDIÇÕES DE PARADA OBRIGATÓRIA
## ============================================================

O `relatorio.md` ("PRD Enterprise Edition") é **NORTE de longo prazo, NÃO um plano de construção**.
Construir os sistemas especulativos agora viola L-07/L-15/L-09. **PARAR** ao detectar:

- ❌ Qualquer um dos sistemas especulativos sem consumidor in-game funcional + gate do arquiteto:
  seasons, achievements, reputação, IA analítica, spectator ao vivo, ghost, API externa,
  observabilidade, feature-flags, highlight engine, pódio automático, câmeras IA.
- ❌ Camada nova além de **CORE + BINDINGS** sem ganho mensurável (sem `Repository/Controller/Infrastructure` — cerimônia enterprise, L-09).
- ❌ Recorder que comece a **validar/recalcular** estado de corrida → vira 2ª fonte de verdade (L-04).
- ❌ Pipeline externo (FFmpeg/Discord/renderer) sem ownership e lifecycle documentados (L-07).
- ❌ `.vhr` persistindo dado que já é verdade no racha, ou campo fabricado no cliente (L-04).
- ❌ "Distribuído/escalável/N renderers/balanceamento" como requisito do MVP — é 1 renderer, 1 fila.
  Escala é problema do dia em que houver fila.


## ============================================================
## 12. RISCOS REGISTRADOS
## ============================================================

| # | Risco | Mitigação |
|---|-------|-----------|
| R1 | 2ª fonte de verdade (L-04): recorder decidindo verdade competitiva por conta própria | VRCS só persiste campos `Schema.TRUST.cosmetic`; posição/tempo/colocação/prêmio nunca se originam no `.vhr` — ownership permanece 100% do `vhub_racha` |
| R2 | Custo no main por I/O de frame a 20 Hz × N players | Buffer 100% em RAM no client durante a corrida; servidor só recebe blocos pós-corrida via `append_chunk` (sem I/O por frame); 1 flush atômico no close |
| R3 | Campos fabricados/manipulados no cliente (v1: `rpm`/`gear`; v2: `vv,cl,th,eh,tp,bp,ws,wc,bf,lf`) = dado não-confiável | **Concessão explícita do dono do projeto (v2):** aceitável porque todos esses campos são `Schema.TRUST.cosmetic` — a verdade competitiva já foi decidida pelo `vhub_racha` antes da montagem do replay. `.vhr` v2 nunca persiste estes campos como `trust.authoritative`; se algum dia precisar, exige validação server-side antes de entrar nessa lista |
| R4 | Acoplamento de runtime racha→vrcs (vrcs off derruba o finalize) | Soft-dependency + `pcall` (precedente `vhub_wow`); falha do recorder nunca afeta finalize/PDL/pagamento |
| R5 | Módulo-fantasma/placement (L-07/L-15): VRCS dentro do racha | VRCS é resource próprio (`[SCRIPTS]/vhub_vrcs`); este doc é só planejamento |
| R6 | Queue sem claim atômico (corrida de renderers) | `UPDATE ... WHERE status='pending' LIMIT 1` + checagem de linhas afetadas (L-12) |
| R7 | Retenção de `.vhr` (disco infinito) | TTL/limpeza configurável; `.vhr` migra p/ o renderer e sai do main após `done` |


## ============================================================
## 13. ORÇAMENTO DE PERFORMANCE
## ============================================================

| Onde | Durante a corrida | No fechamento (pós-`recStop`) |
|------|--------------------|-------------------------------|
| Client (gravando o próprio carro) | CPU: amostragem local 20Hz, **zero rede** | upload sequencial fatiado (`SEND_CHUNK_FRAMES`), só após `recStop` |
| Servidor principal (recorder) | **0% rede** (nenhum bloco chega antes do fim) | recebe blocos com ACK, até `SEND_TIMEOUT_TOTAL_MS` (60s) por corrida; CPU/RAM seguem o teto antigo: **0.5% – 1% CPU**, **10 MB – 30 MB RAM** |
| Renderer isolado (durante render) | — | 15% – 35% CPU, 1 GB – 2 GB RAM |

**Mudança de perfil v1→v2:** o custo de rede deixou de ser distribuído (flush periódico a cada
`FLUSH_MS` durante a corrida) e passou a ser concentrado no fechamento (upload sequencial com ACK
após `recStop`) — trade-off deliberado do usuário: zero risco de lag na prova, custo todo pago de
uma vez no momento em que ninguém mais depende de baixa latência. Frame v2 é ~3x mais pesado
(36 valores vs ~12), mas isso só infla o payload do upload pós-corrida, nunca o hot path da prova.

Escala (referência, não requisito de MVP): 1 renderer ≈ 100 corridas/dia; cada renderer adicional
soma linearmente (a fila é o ponto de extensão).


## ============================================================
## 14. LEIS APLICÁVEIS
## ============================================================

- **L-01 / L-02 / L-03** — servidor autoritativo; cliente efêmero; fallback não inventa dado-cliente.
- **L-04** — sem 2ª fonte de verdade: VRCS é consumidor passivo; racha mantém ownership de telemetria/anti-cheat/ranking/history.
- **L-05** — native-first no renderer (`SetEntityCoords`/`SetEntityRotation`).
- **L-06** — sem loop/retry sem condição de saída (fila/circuit-breaker com cap).
- **L-07** — ownership + lifecycle explícitos de cada peça; especulativos sem consumidor proibidos.
- **L-09** — 2 camadas reais (CORE + BINDINGS), não 7.
- **L-12** — claim de job e transações de fila atômicos, server-side.
- **L-13** — escritor único do `.vhr`, de `vh_race_replays` e de `vh_vrcs_jobs`.
- **L-15** — sem código morto: renderer/FFmpeg/Discord/IA só com consumidor real.
- **L-17** — replay-safety se a fronteira virar evento institucional.
- **L-19** — coordenada como primitivo no `.vhr` e no trânsito; vetor reconstruído no ponto de uso.
- **N0-2** — exports default-DENY com `_invoker_allowed()`.


## ============================================================
## 15. NOME DE ARQUIVO E ARTEFATOS
## ============================================================

- Replay de dados: `<raceId>.vhr` (UUID validado).
- Vídeo (F4): `RACE_AAAAMMDD_HHMMSS.mp4` (1920×1080, 60 fps, H.264).
- Artefatos futuros (opcionais, sem ownership ainda): `corrida.webp`, `thumbnail.png`,
  `highlight.mp4`, `ranking.json`.

---

**Gates de aprovação deste design:** `vhub_arquiteto` (ownership/placement/fronteira/faseamento) +
`vhub_guardiao_seguranca` (modelo zero-trust + checklists por fase) + `vhub_guardiao_simplicidade`
(escopo travado, 2 camadas, anti-inflação). Implementação aguarda ordem explícita do dono e gate do
arquiteto **por fase**.
