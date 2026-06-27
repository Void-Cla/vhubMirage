# vhub_vrcs — VHUB Race Cinema System (Fase 1 / MVP)

Gravador leve de **telemetria autoritativa** de corridas do `vhub_racha`. Por corrida
ranqueada, produz **1 arquivo `.vhr`** (replay em dados) + **1 job na fila de render**.
Nenhum vídeo é renderizado aqui — isso é o renderer isolado (Fase 2+).

> **Design completo:** ver [`vrcs.md`](./vrcs.md) (arquitetura, segurança, faseamento, leis).

---

## O que esta fase faz

- Liga ao racha por **2 hooks** (`begin_racing` / `finish`) via `exports.vhub_vrcs:onRaceStart`
  / `:onRaceClose`, chamados pelo racha **sob `pcall`** (se o VRCS cair, a corrida não quebra).
- **Gravação CLIENT-DRIVEN:** cada participante grava o **próprio carro** a 10 Hz (pos/rotação
  completa + rpm/marcha/volante/freio + aparência real do piloto). CPU desprezível, **zero GPU**;
  só roda durante a corrida. Envia em chunks (a cada 12s + flush final). **O servidor não amostra.**
- O servidor abre o replay com a identidade/aparência do carro pela **placa**
  (`vhub_conce:getVehicleState` — cor, mods, rodas, neon, tint), recebe os chunks e no fim (após um
  grace) monta **1 `.vhr` único** → `replays/<uuid>.vhr` + `vh_race_replays` + `vh_vrcs_jobs`.
- **TESTE:** grava **somente corridas ranqueadas** por padrão (`config/config.lua → RECORD.ranked_only`).
- **Discord:** ao finalizar, posta o **resultado + char_ids de todos** e **anexa o `.vhr`**.
- **`/replays` (download sob demanda):** o painel lista os replays disponíveis (vêm do servidor);
  ao escolher, o client **baixa o `.vhr` uma vez**, guarda em cache local (KVP) e reproduz in-game.
  Controles: play/pause, timeline, velocidade 0.5x–4x, trocar piloto e **câmera** (chase/orbit/side/front/drone).
- **Fidelidade do playback:** motorista no volante com a roupa real, **áudio do motor** (RPM gravado),
  **rodas esterçando** (ângulo real do volante), **rodas girando no eixo** (`VIEWER.WHEEL_MODE`:
  `spin` visual / `physics` por velocidade real) e rotação completa.
- **Fluidez:** amostragem a **20 Hz** + interpolação a 60 fps + **câmera suavizada** (glide,
  `VIEWER.CAM_SMOOTH`).

> **Sobre o `.mp4`:** GTA/FiveM **não renderiza vídeo no servidor** (precisa do jogo rodando numa
> máquina com GPU). O `.mp4` cinematográfico é o **renderer** (F2–F5): uma instância dedicada que
> carrega o `.vhr`, reproduz com câmeras e captura via FFmpeg, depois posta o vídeo consumindo a
> fila `vh_vrcs_jobs`. Até essa máquina existir, o canal recebe o `.vhr` (que já identifica a corrida
> e todos os pilotos).

## Setup

1. `ensure vhub_vrcs` no `resources.cfg` (já adicionado, logo após `vhub_racha`).
2. Webhook do Discord via **convar** no `server.cfg` (**já configurado** com a URL do canal de replays):
   ```cfg
   set vrcs_discord_webhook "https://discord.com/api/webhooks/...."
   ```
   Vazio = publisher desligado (fail-closed).
3. Tabelas criadas automaticamente no boot (`sql/schema.sql`, idempotente).

## Estrutura

```
core/                  KERNEL agnóstico (reaproveitável em outros projetos)
  shared/  vhr_schema.lua  codec.lua  logger.lua
  server/  recorder.lua    queue.lua
bindings/  racha.lua          REGRA DE NEGÓCIO (mapeia o racha → .vhr; troca por projeto)
client/    recorder.lua       grava o próprio carro (10Hz) e envia ao servidor
           cache.lua  player.lua  nui.lua
server/    publisher.lua (Discord)  library.lua (lista/download)  init.lua
web/       index.html  style.css  app.js   (painel /replays)
config/    config.lua    sql/ schema.sql    replays/ (.vhr em runtime)
```

`core/` nunca importa `bindings/` — é copiável para outro projeto sem arrastar o racha.

## Próximas fases (não construídas)

`F2` renderer isolado (`[TOOLS]/vhub_vrcs_renderer`) · `F3` câmeras cinematográficas ·
`F4` FFmpeg → `.mp4` · `F5` publisher de vídeo (move o HTTP para fora do main).
