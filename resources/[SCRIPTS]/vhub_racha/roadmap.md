# vHub Racha — Masterplan de Rework Completo

> Projeto: `vhub_racha`
> Framework alvo: vHub Mirage (CORE FROZEN v1.0)
> Objetivo: transformar o sistema atual em uma plataforma premium de corridas clandestinas com UX moderna, arquitetura limpa, resmon baixo, experiência cinematográfica e fluxo competitivo completo.

---

# Bugs corrigidos em 2026-05-23 (patch 3.0.1)

## ✅ Fix B1 — "vhub indisponível após 30s" + `/racha` recusa abrir

**Sintoma:** cliente loga `vhub indisponivel apos 30s — comandos podem nao responder`. `/racha` mostra "Mirage Racha ainda nao esta pronto". F8 debug exibe `state_ready=true` mas `auth_ready=false` e `global_vhub=nil`. `racha_editor` abre normalmente (não checa READY).

**Causa raiz:** race condition entre core `vHub` e o cliente do `vhub_racha`. O servidor emite `vHub:initDone` quando o jogador autentica, mas o cliente às vezes registra o `RegisterNetEvent('vHub:initDone')` **depois** desse evento ter sido disparado — o trigger é perdido.

**Correção aplicada:**

- **`server/bootstrap.lua`**: novo handler idempotente `vhub_racha:request_initDone` que reemite `vHub:initDone` apenas para o solicitante quando o usuário já está autenticado. Sem efeito colateral, sem modificar o core.

  ```lua
  RegisterNetEvent('vhub_racha:request_initDone')
  AddEventHandler('vhub_racha:request_initDone', function()
    local src = source
    if not B.READY or not B.vHub or not B.vHub.Auth then return end
    local ok, user = pcall(function() return B.vHub.Auth:getUser(src) end)
    if not ok or type(user) ~= 'table' then return end
    TriggerClientEvent('vHub:initDone', src, user.id or user.user_id, user.char_id, false)
  end)
  ```

- **`client/bootstrap.lua`**: solicita re-emissão em 3 momentos espalhados (200ms / 3s / 8s após load). Cobre boot rápido e recuperação em boot lento. Loop de fallback expandido para 60s (120 × 500ms) com retry automático.

**Arquivos tocados:** `server/bootstrap.lua`, `client/bootstrap.lua`.

---

## ✅ Fix B2 — Editor aparece cursor do mouse e trava o veículo

**Sintoma:** ao clicar "Iniciar edição" na aba Editor do `/racha`, o cursor do mouse continua na tela e o jogador não consegue dirigir o carro. O editor deveria ser **only-keyboard** in-game.

**Causa raiz:** `client/nui.lua` chamava `SetNuiFocus(true, true)` ao receber `EDITOR_OPENED` do servidor, mantendo o cursor ativo e bloqueando os inputs do veículo. Mas o editor é controlado **100% por teclas in-game** (E adiciona, H undo, G próxima fase) via `client/editor.lua` — o cursor não deveria existir nessa fase.

**Correção aplicada:**

- **`client/nui.lua`** no handler `EDITOR_OPENED`:
  - **Removido** `SetNuiFocus(true, true)` (era a causa direta).
  - Agora **fecha o painel principal** `/racha` automaticamente (`SetNuiFocus(false, false)` + `action: 'close'`) caso esteja aberto. Cursor sai, inputs voltam, jogador dirige normal.
  - Substituído `SendNUIMessage({action='editor_open'})` por toast nativo: `"Editor ativo. Use comandos in-game: E adicionar | H undo | G proxima fase."`

- **`client/nui.lua`** no handler `EDITOR_PHASE`: quando `phase == 'meta'` e painel está fechado, dispara `TriggerServerEvent(E.NUI_OPEN)` para reabrir o `/racha` automaticamente na aba Editor (já preparada para o form de metadados).

- **`nui/js/app.js`** em `editorStart()`: removido `switchTab('editor')` e `toast(...)` — o painel vai fechar de qualquer jeito (controle de UX migra para NotifyFeed nativo do GTA).

**Fluxo correto agora:**

1. `/racha` → aba Editor → clica "Iniciar edição"
2. Servidor cria draft em VRAM, envia `EDITOR_OPENED` ao cliente
3. Cliente **fecha o painel** (`SetNuiFocus(false, false)` + `SendNUIMessage({action:'close'})`)
4. Toast nativo: "Editor ativo. Use comandos in-game…"
5. Overlay in-game renderiza via `client/editor.lua`: banner de fase, contagem de slots/CPs, render dos pontos salvos. **Sem cursor**, **sem painel**, **carro anda normal**.
6. Jogador dirige e usa teclas:
   - **E** → adiciona slot de grade (Fase 1) ou checkpoint (Fase 2)
   - **H** → remove último CP (Fase 2)
   - **G** → avança para próxima fase
7. Ao chegar na **Fase Meta**, o cliente reabre o `/racha` automaticamente na aba Editor com o form de metadados preenchível.
8. Preenche `id`, `label`, `kind`, `laps`, etc. → salva.

**Arquivos tocados:** `client/nui.lua`, `nui/js/app.js`.

---

## Como testar (após aplicar)

```
restart vhub_racha
```

1. Login no servidor → digitar `/racha` → painel deve abrir sem aviso "ainda nao esta pronto".
2. Console do cliente (F8) deve mostrar `[vhub_racha][client] pronto em XXms`.
3. Aba **Editor** → "Iniciar edição" → painel fecha, banner in-game aparece, cursor some, **carro anda**.
4. Dirigir → E adiciona CP, H undo, G muda de fase.
5. Na fase Meta → painel reabre automaticamente com o form → preencher + Salvar.

Se o B1 persistir, F8 mostra diagnóstico detalhado com flags `global_vhub/exports_vhub/auth_ready/state_ready/b_user/b_char` para análise.

---

# Diretiva do dono (preservada)

> Antes de mais nada, apagar pastas e arquivos mortos dando organização lógica separada por responsabilidades para `resources/[SCRIPTS]/vhub_racha`. Dessa vez é permitido que esse script seja mais client-side do que server-side: deixar server-side apenas as lógicas de organização do lobby, ranking e dinheiro — o que de fato não for crítico pode ser client-side em cache. Lógica de espectador também client-side.

---

# 1. Diagnóstico Atual

## 1.1 Problema crítico de inicialização

### Sintoma

O resource inicia normalmente no boot do servidor e aparece no console como carregado, porém:

* sistema não funciona;
* callbacks/eventos ficam mortos;
* somente volta a funcionar após `ensure vhub_racha` manual.

---

## 1.2 Possíveis causas técnicas

### A) Ordem de dependências

O `vhub_racha` depende de:

* `vhub`
* `vhub_money`
* `vhub_identity`
* `vhub_groups`
* `oxmysql`

Possível cenário:

* `vhub_racha` inicia antes do core finalizar bootstrap;
* exports ainda não existem;
* callbacks falham silenciosamente;
* cache inicial fica inválido.

---

### B) Bootstrap prematuro

Provável ocorrência:

* `CreateThread` rodando antes do framework estar pronto;
* chamadas de exports no topo do arquivo;
* queries SQL executando antes do schema terminar;
* registros de corrida carregando antes do banco responder.

---

### C) Race condition em carregamento de cache

Muito provável:

* tabelas internas (`Races`, `Lobbies`, `Players`, `Rankings`) iniciam vazias;
* sincronização inicial falha;
* segundo `ensure` repopula corretamente.

---

## 1.3 Correção arquitetural obrigatória

## Implementar handshake oficial estilo Mirage

### Regra

O sistema NÃO deve bootar lógica própria até:

```lua
exports.vhub:getVHub()
```

estar disponível.

---

## Fluxo correto

### Boot Stage 1

Carrega:

* enums
* config
* funções puras
* cache vazio

### Boot Stage 2

Aguardar:

```lua
local vHub = exports.vhub:getVHub()
```

com retry seguro.

### Boot Stage 3

Executar:

* SQL bootstrap
* preload races
* preload ranking
* preload history
* preload leaderboard
* preload hot cache
* registrar callbacks
* registrar loops
* marcar:

```lua
RACHA_READY = true
```

---

## 1.4 Solução recomendada

### Criar:

```lua
server/bootstrap.lua
```

Responsável por:

* esperar dependências;
* carregar cache;
* validar schema;
* iniciar manager;
* iniciar ranking;
* iniciar matchmaking;
* iniciar autosave.

---

# 2. Problemas de UX/UI Atuais

## 2.1 Textos quebrados

### Problema

Existem labels assim:

```text
race_time_left
best_lap_time
player_position
```

aparecendo na interface.

---

## Causa

Sistema usando keys cruas ao invés de locale.

---

## Solução obrigatória

Criar:

```text
shared/lang/pt_br.lua
```

Com:

```lua
Lang = {
  lobby_waiting = 'Aguardando jogadores',
  race_starting = 'Corrida iniciando',
  confirm_presence = 'Confirme presença na largada',
}
```

---

# 3. HUD Atual — Problemas

## Problemas identificados

* HUD conflitando com velocímetro;
* informações muito próximas;
* visual genérico;
* pouca legibilidade;
* excesso de texto;
* sem hierarquia visual;
* checkpoint feio;
* marcador genérico GTA;
* ausência de experiência cinematográfica.

---

# 4. Nova Filosofia Visual

## Tema obrigatório

### “Liga clandestina premium do deserto dourado”

Seguindo:

* Liquid Glass;
* areia dourada;
* partículas;
* HUD minimalista;
* UX cinematográfica;
* inspiração:

  * Forza Horizon;
  * The Crew;
  * NFS Heat;
  * Midnight Club;
  * GT7 HUD minimal.

---

# 5. Novo Sistema de Checkpoint

## REMOVER COMPLETAMENTE

* blip GTA padrão;
* marker padrão;
* checkpoint padrão;
* seta vanilla.

---

# 6. Novo Totem de Checkpoint

## Conceito

Um “portal/tótem” gigante translúcido.

---

## Visual

### Estrutura

* largura: ~1m;
* altura: ~50m;
* semi-transparente;
* areia dourada;
* glow leve;
* partículas flutuando;
* animação vertical suave.

---

## Elementos do totem

### Topo do totem

Mostrar:

```text
CP 4
1.24 KM
```

---

## Corpo

* linhas verticais luminosas;
* efeito holográfico;
* distorção leve;
* partículas de areia.

---

## Base

* círculo fino no chão;
* quase invisível;
* sem poluição visual.

---

## Regras técnicas

### Obrigatório

* DrawSprite + PolyZone;
* LOD dinâmico;
* partículas pausadas fora de range;
* resmon baixo;
* distância adaptativa.

---

# 7. Novo HUD de Corrida

## Layout obrigatório

### Topo central

```text
00:00:00
```

Timer principal.

---

## Abaixo do timer

```text
Recorde: 00:52:81
```

Menor fonte.

---

## Direita superior

```text
POSIÇÃO
1/5
```

---

## Esquerda superior

```text
VOLTA
2/3
```

---

## Inferior esquerda

```text
PRÓXIMO CP
1.24 KM
```

---

## Regras do HUD

### NÃO pode:

* sobrepor velocímetro;
* usar fundo opaco;
* usar caixa pesada;
* usar texto branco puro;
* usar bordas retas.

---

## DEVE:

* usar areia dourada;
* blur;
* glass;
* animação suave;
* fade in/out;
* responsividade;
* detectar resolução.

---

# 8. Fluxo Novo de Lobby

## Problema atual

Player entra no lobby:

* instantaneamente;
* de qualquer lugar do mapa;
* sem imersão;
* sem preparação.

Fica feio.

---

# 9. Novo Fluxo Competitivo

## Etapa 1 — Entrar no lobby

Player entra via painel.

---

## Etapa 2 — Estado “Pendente”

Após entrar:

```text
Você possui 5 minutos para confirmar presença na largada.
```

---

## Etapa 3 — Área física de confirmação

Criar:

* PolyZone;
* área próxima da largada;
* visual premium.

---

## Regra

Somente players dentro da área:

* podem confirmar;
* entram na corrida;
* são teleportados para grid.

---

## Benefícios

* imersão;
* evita teleport ridículo;
* cria preparação;
* gera clima competitivo;
* aproxima jogadores.

---

# 10. Sistema Ready Check

## Novo fluxo

### Ao entrar na zona

Player aperta:

```text
E = Confirmar presença
```

---

## Estados

### Pendente

Cinza.

### Confirmado

Dourado.

### Ausente

Expirado.

---

## Regras

### Se todos confirmarem

Corrida inicia imediatamente.

---

### Se timer zerar

* remover ausentes;
* iniciar com presentes.

---

# 11. Sistema de Treino Solo

## Problema atual

Corridas exigem múltiplos jogadores.

---

## Problema disso

* impossível treinar;
* impossível aprender pista;
* impossível testar carro.

---

# 12. Novo modo “Treino”

## Regras

### Pode iniciar solo

* sem ranking;
* sem dinheiro;
* sem recompensa;
* sem XP.

---

## Objetivo

Treino livre.

---

## Lobby treino

### Permitir:

* 1 jogador;
* reset rápido;
* restart instantâneo;
* espectador livre.

---

## Badge visual

```text
MODO TREINO
```

---

# 13. Novo Sistema de Slots

## Problema atual

Quantidade fixa.

---

## Novo comportamento

### Host define:

```text
Min Players
Max Players
```

---

## Regras

### Corrida rankeada

* mínimo 2;
* máximo = grid.

---

### Treino

* mínimo 1;
* máximo configurável.

---

# 14. Sistema de Sair do Lobby

## Problema atual

Player preso.

---

## Novo sistema

### Antes da corrida

Player pode:

```text
SAIR DO LOBBY
```

---

## Regras

### Se host sair

* lobby dissolve;
* ou host migra.

---

### Se player sair

* slot libera.

---

# 15. Sistema de Espectador

## Funcionalidade obrigatória

Após corrida iniciar:

* outros jogadores podem assistir.

---

# 16. Modos de espectador

## A) Auto TV

### Funcionamento

* alterna carros;
* troca a cada 5 segundos;
* câmera cinematográfica.

---

## B) Manual

Player escolhe:

```text
Espectar: FOX
Espectar: MIRAGE
Espectar: VOID
```

---

## C) Livre

Drone livre.

---

# 17. Câmeras cinematográficas

## Tipos

### Chase Cam

Atrás do carro.

### Wheel Cam

Pneu.

### Hood Cam

Capô.

### Drone Cam

Aérea.

### Side Cam

Lateral cinematográfica.

---

# 18. Ranking Competitivo

## Necessário

Separar:

* treino;
* casual;
* rankeado.

---

## Ranking deve registrar

* vitórias;
* derrotas;
* DNFs;
* tempo record;
* melhor volta;
* elo;
* winrate;
* histórico.

---

# 19. Sistema Anti-Abuso

## Necessário

### Detectar:

* teleport;
* noclip;
* speedhack;
* atravessar checkpoint;
* cortar pista;
* ghost exploit.

---

## Implementar

### Sistema de validação:

* direção;
* sequência;
* distância máxima;
* tempo impossível.

---

# 20. Novo Editor de Corridas

## REMOVER COMPLETAMENTE

Editor por comando.

---

# 21. Novo Editor Dinâmico

## Fluxo completo

### Painel principal

```text
Corridas
  → Editor
    → Iniciar edição
```

---

## Regras

### Só funciona dentro do carro.

---

# 22. Fase 1 — Grid de largada

## Instrução

```text
Posicione os veículos da largada.
```

---

## Fluxo

Player:

* posiciona carro;
* aperta buzina OU E;
* slot salvo.

---

## Limites

* mínimo: 1;
* máximo: 8.

---

## Próximo estágio

```text
G = Próxima etapa
```

---

# 23. Visualização do grid

## Mostrar

* linhas no chão;
* holograma do slot;
* número da posição.

---

# 24. Fase 2 — Checkpoints

## Fluxo

Player dirige:

```text
E = criar checkpoint
```

---

## Remover último

```text
T = remover último checkpoint
```

---

## Próxima etapa

```text
G = finalizar checkpoints
```

---

# 25. Fase 3 — Metadados da corrida

## Interface NUI

Campos:

* nome;
* descrição;
* tipo;
* dificuldade;
* voltas;
* mínimo players;
* máximo players;
* valor mínimo;
* buy-in;
* imagem;
* tags;
* clima recomendado;
* horário recomendado.

---

# 26. Tipos de corrida

## Modos

* Sprint;
* Circuito;
* Drag;
* Drift;
* Radar;
* Time Attack;
* Freerun.

---

# 27. Melhorias obrigatórias no editor

## Deve possuir

### Undo/Redo

### Preview da pista

### Simulação rápida

### Auto geração de minimapa

### Test drive instantâneo

### Duplicar corrida

### Importar/exportar JSON

### Salvar rascunho

---

# 28. Sistema de Persistência

## Separar corretamente

### Corrida

Dados permanentes.

### Lobby

Dados temporários.

### Race Runtime

Dados vivos.

---

# 29. Arquitetura recomendada

## Estrutura ideal

```text
server/
  bootstrap.lua
  lobby.lua
  runtime.lua
  matchmaking.lua
  ranking.lua
  anti_cheat.lua
  rewards.lua
  spectator.lua
  editor.lua
  telemetry.lua

client/
  hud.lua
  checkpoints.lua
  spectator.lua
  race.lua
  lobby.lua
  editor.lua
  cinematic.lua

nui/
  lobby/
  hud/
  editor/
  spectator/
```

---

# 30. Sistema de Runtime

## Estado correto

### Race Definition

Imutável.

### Lobby

Pré-corrida.

### Session

Corrida viva.

### Spectator Session

Assistindo.

---

# 31. Melhorias de Performance

## Necessárias

### Remover loops 0ms.

### Usar distância adaptativa.

### LOD em checkpoints.

### Threads pausáveis.

### NUI render sob demanda.

### Stop total quando fora de corrida.

---

# 32. Regras de NUI

## Obrigatório seguir Guardião Designer

### Visual

* areia dourada;
* liquid glass;
* partículas;
* blur;
* glow dourado.

---

## Proibido

* azul;
* roxo;
* HUD opaco;
* fonte genérica;
* borda reta;
* texto técnico cru.

---

# 33. Sistema de Recompensas

## Corrida rankeada

### Recompensas

* dinheiro;
* XP;
* elo;
* estatística.

---

## Treino

### Não concede

* dinheiro;
* ranking;
* XP.

---

# 34. Sistema de Replay

## Futuro obrigatório

Salvar:

* trajetória;
* velocidade;
* posição;
* eventos.

---

## Objetivo

### Permitir:

* replay;
* highlights;
* análise;
* fantasmas.

---

# 35. Sistema Ghost

## Time Attack

Mostrar:

* fantasma do recorde;
* fantasma pessoal;
* fantasma mundial.

---

# 36. Sistema de Matchmaking

## Futuro ideal

Separar:

* casual;
* competitivo;
* treino;
* privado.

---

# 37. Sistema de Clima Dinâmico

## Corrida pode definir

* noite;
* chuva;
* neblina;
* amanhecer;
* entardecer.

---

# 38. Sistema de Punição

## Detectar

### Quit Rage

Sair no meio.

### AFK

Parado.

### Obstrução

Bloquear pista.

---

# 39. Melhorias UX adicionais

## Necessárias

### Contagem cinematográfica

```text
3
2
1
GO
```

---

### Tremor leve de câmera

### Som de largada

### Efeito sonoro em checkpoint

### Música dinâmica opcional

### Voz sintetizada opcional

---

# 40. Melhorias sociais

## Necessárias

### Histórico de corridas

### Perfil do piloto

### Estatísticas públicas

### Melhor pista do jogador

### Recordes globais

### Amigos/rivais

---

# 41. Recursos removíveis

## Recomendado remover

### Comandos antigos.

### HUD legado.

### Checkpoint vanilla.

### TextDraw improvisado.

### Strings técnicas.

### Fluxo instantâneo sem presença.

### Lobby sem estado.

---

# 42. Objetivo Final

## O sistema deve parecer:

### “Uma liga clandestina viva dentro do GTA.”

E NÃO:

### “Um script simples de corrida.”

---

# 43. Resultado esperado

## Experiência final

Player:

* encontra corrida;
* entra no lobby;
* dirige até o ponto;
* confirma presença;
* vê outros pilotos;
* sente tensão;
* corrida inicia cinematograficamente;
* checkpoints gigantes aparecem no horizonte;
* HUD limpa e premium;
* espectadores assistem;
* ranking salva;
* replay existe;
* experiência parece AAA.

---

# 44. Prioridade de Implementação

## PRIORIDADE CRÍTICA

### P0

* corrigir boot;
* corrigir startup race;
* corrigir textos quebrados;
* reorganizar HUD;
* remover conflito velocímetro.

---

## PRIORIDADE ALTA

### P1

* sistema presença;
* treino solo;
* sair lobby;
* max/min player;
* editor visual.

---

## PRIORIDADE MÉDIA

### P2

* espectador;
* replay;
* ghost;
* câmera cinematográfica.

---

## PRIORIDADE FUTURA

### P3

* matchmaking;
* seasons;
* elo avançado;
* replay compartilhado.

---

# 45. Veredito Arquitetural

## Estado atual

### Funcional:

SIM.

### Estruturalmente pronto:

PARCIAL.

### UX moderna:

NÃO.

### Compatível com padrão vHub Mirage:

PARCIAL.

---

# 46. Meta Final

Transformar o `vhub_racha` no:

## “Melhor sistema de corrida FiveM da comunidade BR.”

Com:

* UX AAA;
* arquitetura limpa;
* resmon baixo;
* experiência cinematográfica;
* competição real;
* editor moderno;
* integração total com vHub Mirage.
