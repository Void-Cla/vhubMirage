# vhub_animacao — Motor de Emotes e Animações

**Versão:** 1.0.0 | **Owner:** vhub_animacao

Motor de emotes server-authoritative com catálogo de ~270 entradas. Integra com `vhub_hss` para bloqueio contextual (algemas, inconsciente, arma sacada). Não tem exports públicos — controle via comandos.

---

## O que faz

- Catálogo de animações: emotes, cenários, props, animações de veículo
- Validação server-side: tipo certo (a pé vs. no carro), bloqueios HSS
- Props: attach/detach de objetos ao ped durante a animação
- Cancelamento automático ao movimento do player
- Integração HSS: `getAnimBlocks` bloqueia se algemado ou inconsciente

---

## Dependências

```
vhub_hss
```

---

## Comandos disponíveis (player)

```
/e <nome>       — reproduz o emote pelo nome do catálogo
/cancelar       — cancela o emote atual
```

Exemplos:
```
/e danca        — toca animação de dança
/e dirigir      — animação só no carro (valida automaticamente)
```

---

## Catálogo de emotes

O catálogo vive em `shared/config.lua` (`VHubAnimacao.Cfg.CATALOG`). Cada entrada pode ter:

```lua
-- Estrutura de uma entrada no catálogo
{
  dict  = 'anim@emotes@dances@listo',   -- dicionário de animação GTA
  name  = 'Listo',                       -- nome dentro do dict
  loop  = true,                          -- true = loop contínuo
  carros = false,                        -- true = só dentro de veículo
  prop  = {                              -- opcional: objeto preso ao ped
    model     = 'prop_phone_ing',
    bone      = 57005,
    offset    = vec3(0,0,0),
    rotation  = vec3(0,0,0),
  },
}
```

Para adicionar um novo emote, insira no catálogo e declare a chave como nome do comando:

```lua
-- shared/config.lua
VHubAnimacao.Cfg.CATALOG['meuemote'] = {
  dict = 'missione_bailar',
  name  = 'WAIT',
  loop  = true,
  carros = false,
}
```

---

## Integração com vhub_hss

O bloqueio é automático: o servidor consulta `exports.vhub_hss:getAnimBlocks(src)` antes de disparar qualquer emote.

| Bloco HSS | Efeito |
|-----------|--------|
| `handcuffed` | Bloqueia todos os emotes |
| `unconscious` | Bloqueia todos os emotes |
| `weapon_drawn` | Bloqueia emotes marcados como `Adv` (vantagem) |

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 / L-02 | Servidor valida; cliente só executa a animação recebida |
| L-09 | Catálogo centralizado — sem duplicatas de dict/anim |
| §2.5 | Soft-dep HSS via `pcall` — sem o HSS, emote funciona sem bloqueio |
| §3.9 | Props limpos em `cancelEmote` (DeleteObject client-side) |
