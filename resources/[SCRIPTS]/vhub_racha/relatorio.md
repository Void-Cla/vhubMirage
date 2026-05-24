# Relatório técnico — problema: "vhub indisponível" e `/racha` não abre

Data: 2026-05-23
Autor: Assistente (preparado para Claud)

## 1) Resumo executivo

Sintoma: no cliente aparece a mensagem

```
[vhub_racha][client] vhub indisponivel apos 30s — comandos podem nao responder.
```

Além disso o `/racha` no menu principal apresenta "Mirage Racha ainda nao esta pronto." — enquanto o `racha_editor` abre normalmente. No servidor a autenticação do jogador ocorre corretamente (`vHub.Auth:connect ok`), indicando que o problema é de sincronização/handshake entre o core `vHub` e o cliente do `vhub_racha`.

## 2) Passos para reproduzir

1. Subir `vhub` e `vhub_racha` no server (`ensure vhub`, `ensure vhub_racha`).
2. Conectar ao servidor com o cliente.
3. Observar F8 do cliente após ~30s e o comportamento do menu `/racha`.

## 3) Logs/evidências relevantes (coletadas)

- Cliente (F8):

```
[vhub_racha][client] vhub indisponivel apos 30s — comandos podem nao responder. debug: global_vhub=nil exports_vhub=true auth_ready=false state_ready=true b_user=nil b_char=nil
```

- Servidor (console):

```
vHub.boot: ready received src=1
vHub.Auth:connect attempt src=1
vHub.Auth:connect ok src=1 uid=1
```

Observação: o cliente reporta `state_ready=true` (State Bag indica vHub presente), mas `auth_ready=false` e `global_vhub=nil` — ou seja, o cliente não recebeu/registrou o `vHub:initDone` por algum motivo.

## 4) Diagnóstico técnico

- Causa principal: race condition / ordem de carga entre `vHub` (core) e o client do `vhub_racha`:
  - o servidor emite o `vHub:initDone` quando um jogador autentica (server-side), mas o cliente do `vhub_racha` às vezes registra os seus listeners depois desse evento ter sido emitido.
  - `exports.vhub:getVHub()` é uma API server-side e não garante que o cliente tenha recebido `vHub:initDone`.
  - Em algumas execuções o State Bag (`LocalPlayer.state.vhub_pronto`) está presente cedo — isto permite detectar readiness, mas não é um substituto do evento `vHub:initDone` em todas as situações.

## 5) Correção mínima e segura (recomendada)

Objetivo: reemitir `vHub:initDone` sob demanda para clientes que perderam o evento, sem modificar o core `vHub`.

- **Server (adicionar handler idempotente):** em `vhub_racha/server/bootstrap.lua` adicionar:

```lua
RegisterNetEvent('vhub_racha:request_initDone')
AddEventHandler('vhub_racha:request_initDone', function()
  local src = source
  local ok, vh = pcall(function() return exports.vhub:getVHub() end)
  if not ok or type(vh) ~= 'table' or not vh.Auth then return end
  local user = vh.Auth:getUser(src)
  if user then
    -- reenvia initDone apenas para o solicitante
    TriggerClientEvent('vHub:initDone', src, user.id, user.char_id, false)
  end
end)
```

- **Client (solicitar re-emissão no start):** em `vhub_racha/client/bootstrap.lua` adicionar no startup:

```lua
CreateThread(function()
  Citizen.Wait(200) -- curto delay para permitir binding inicial
  TriggerServerEvent('vhub_racha:request_initDone')
end)
```

Racional: cliente que perder o `vHub:initDone` pode pedir explicitamente; o servidor responde apenas ao solicitante com dados de sessão já autenticada. Trecho idempotente e de baixo risco.

## 6) Alternativas / melhorias

- Modificar o core `vHub` para reemitir `vHub:initDone` em `onResourceStart` para resources que iniciam depois (mais invasivo — requer revisão do core).
- Permitir o abrir da UI (`/racha`) mesmo sem `READY`, com avisos, para facilitar testes (não recomendado em produção).

## 7) Testes sugeridos

1. Aplicar os dois patches acima (server + client).
2. Reiniciar `vhub` e `vhub_racha`:

```powershell
ensure vhub
ensure vhub_racha
```

3. No cliente, observar F8 por: `vHub:initDone->` ou a mensagem debug que adicionámos.
4. Verificar se o `/racha` abre sem o aviso "ainda nao esta pronto".

## 8) Riscos e rollback

- O patch é de baixo risco: apenas adiciona um endpoint que reenvia um evento já existente para o solicitante. Em caso de problema, remova as duas inserções e reinicie o recurso.

## 9) Arquivos a alterar

- `vhubMirage/resources/[SCRIPTS]/vhub_racha/server/bootstrap.lua`
- `vhubMirage/resources/[SCRIPTS]/vhub_racha/client/bootstrap.lua`

## 10) Prazo estimado

- Implementação + teste: 5–15 minutos.

## 11) Próximos passos para o Claud

1. Aplique os dois patches (posso aplicá-los agora, se desejar).
2. Reinicie os recursos e reproduza o caso (cole logs F8/servidor se persistir).
3. Se confirmado, remova logs de debug adicionados ao cliente.

---
Se quiser, aplico os patches agora e testo; indique se devo proceder automaticamente.
