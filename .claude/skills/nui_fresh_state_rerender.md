# Skill — NUI: re-render por estado fresco do servidor (sem 2ª verdade otimista)

> **Validado em:** ADR #82 F2.3 (2026-08-09) — oficina de peças (`vhub_custom/web/oficina.js`).
> Gates designer+runtime: APROVAR. Lei central: **A-04** (estado por domínio, sem 2ª fonte na NUI).

## Quando usar

Uma ação da NUI **muda estado que o servidor é dono** (instalar peça, comprar, aplicar cosmético). Depois da
ação, a UI precisa refletir o novo estado. Há duas formas — uma certa, uma armadilha:

- ❌ **Patch otimista local:** a NUI atualiza seu próprio cache (`_installed[id] = true`) sem esperar o server.
  Rápido, mas cria uma **2ª verdade** que diverge se o server recusar, aplicar diferente, ou outro fluxo mexer
  no mesmo dado. Viola A-04.
- ✅ **Re-render por estado fresco:** o server, ao confirmar a ação, **devolve o estado autoritativo novo**
  (o subset que a UI desenha); a NUI só troca `_data.*` por esse payload e re-renderiza. Uma verdade.

## Receita

**Server** — o handler da ação devolve, no OK, um snapshot fresco (não só "ok"):
```lua
-- snapshot AUTORITATIVO do que a UI desenha (ids instalados + ficha derivada), pós-mutação
local function freshState(plate)
  local st = getState(plate)                 -- lê o estado já persistido
  local installed = truthyKeysOf(st.customization.parts)
  local sheet = deriveSheet(plate)           -- ficha recomposta (inclui derivados novos)
  return { installed_parts = installed, sheet = sheet }
end
-- no sucesso:
reply(true, 'Instalada!', freshState(plate)) -- 3º arg = estado fresco
```
```lua
-- client: repassa o estado fresco à NUI
AddEventHandler(E.INSTALL_OK, function(ok, msg, fresh)
  if not inMenu then return end
  SendNUIMessage({ action = 'instalarParteResultado', ok = ok, data = type(fresh)=='table' and fresh or nil })
end)
```

**NUI (JS)** — aplica o fresco e re-renderiza TUDO que depende dele; nunca mantém cache paralelo:
```js
function onInstalarParteResultado(ok, data) {
  _installing = false;                       // solta a trava anti-duplo-clique
  if (ok && data && _data) {
    if (data.installed_parts) _data.installed_parts = data.installed_parts;  // troca, não faz merge
    if (data.sheet)           _data.sheet = data.sheet;
    renderEngEffect();
  }
  renderFamNav(); renderParts(); renderStats();   // re-render a partir de _data (fonte única)
}
```

## Regras de ouro (checadas em gate runtime)

1. **A ação NUI é discreta (clique)** → dispara via o bridge central (`window.vhub.request(endpoint, payload)`),
   nunca `fetch` espalhado (A-06). Não é hot-path → sem batching (A-08).
2. **Trava anti-duplo-clique** (`_installing = true` + botão `disabled`) até o OK chegar; solta no resultado.
   Sem isso, dois cliques rápidos = duas requisições (o server é idempotente por `requestId`, mas a UI não
   deve nem tentar).
3. **A NUI NÃO decide verdade crítica** (A-01): preço, cap, ownership, pagamento são revalidados server-side.
   O estado da peça que a NUI mostra (`installed_parts`) vem do server, não é computado na UI.
4. **Estado por domínio em `_data`** (A-04): um único objeto é a fonte; render lê dele. Trocar chaves inteiras
   do payload fresco, não fazer merge otimista que possa divergir.
5. **Cleanup obrigatório** (A-07): `clearTimeout` de qualquer debounce no `onHide`/`onDestroy`;
   `removeEventListener` dos handlers registrados no `onInit`; listeners de elementos recriados por
   `innerHTML=''` são descartados com o nó (documentar com comentário para não gerar dúvida em revisão).
6. **Deletar é entrega (L-15):** ao migrar a NUI de um modelo de dado para outro, remover no MESMO commit as
   funções/consts/estado do modelo antigo (render antigo, cálculos de UI órfãos, callbacks Lua que a NUI parou
   de disparar, e o CSS de classes que sumiram do HTML). Conferir com grep que nenhum id/classe removido é
   referenciado por JS/HTML antes de apagar o CSS.

## Identidade visual (A-09/A-10/A-11) ao redesenhar in-place

- Reusar os **tokens do design system** já existentes (`--vh-gold`, `--vh-ok`, `--vh-danger`, `--glass-bg`) e
  as classes de layout reaproveitáveis (nav, detail). Tokens NOVOS do módulo vão no seletor raiz
  (`.mod-<nome> { --x: … }`), nunca em `:root` (A-11).
- Ícones: SVG inline / unicode — **sem asset novo**, sem CDN (A-10). Ícone desconhecido cai no fallback do
  target/engine (sem 404).
- `backdrop-filter` proibido sobre o jogo (A-09) — glass é simulado com fundo translúcido em camadas, salvo
  quando há `#bg` opaco atrás (receita já usada na oficina).

## Validação antes do smoke in-game

`node --check` no JS; `luac -p` no Lua; balanço de chaves no CSS
(`awk '{o+=gsub(/{/,"{");c+=gsub(/}/,"}")}END{print o==c}'`); conferir que todo `id`/`action` que o JS usa
existe no HTML e casa com o `SendNUIMessage` do Lua (grep cruzado). Smoke in-game é o único juiz do fluxo real
— declarar **NÃO TESTADO IN-GAME** até o dono confirmar.
