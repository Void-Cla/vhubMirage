# vhub_spawselector — Seletor de Spawn (UI Pura)

**Versão:** 2.1.1 | **Owner:** vhub_spawselector

Provedor de coordenada de spawn do `vhub_hss`. UI pura: o jogador escolhe onde nascer (último local, motel, pontos da cidade); a coordenada escolhida é **devolvida ao owner do ped** — este resource **nunca toca o ped** (L-16). Adaptado do FiveStar-SpawnSelector para o padrão vHub.

---

## O que faz

- Intercepta o fluxo `chooseSpawn` do `vhub_hss` (provider pattern)
- UI com pontos de spawn configuráveis (motel, LSPD, mecânica, estacionamento, Sandy...)
- Opção "último local" (posição persistida pelo core)
- Pontos restritos por grupo (ex.: spawn LSPD só para policiais, via `vhub_groups`)
- Devolve a coordenada escolhida por export/callback ao `vhub_hss`, que executa o spawn

---

## Dependências

```
vhub, vhub_groups, vhub_hss
```

---

## Exports disponíveis

```lua
-- client: abre a UI do seletor manualmente (o fluxo normal é automático no characterLoad)
exports.vhub_spawselector:Open()

-- server: remove um ponto de spawn dinâmico por id (admin)
exports.vhub_spawselector:adminDeleteThing(id)
```

---

## Como adicionar um ponto de spawn

Em `shared/config.lua`:

```lua
Config.Spawns[#Config.Spawns + 1] = {
  id    = 'mecanica',
  label = 'Oficina Mecânica',
  img   = 'images/mechanic.png',        -- deve constar no files{} (A-10)
  coord = { x = -347.0, y = -133.0, z = 39.0, h = 250.0 },  -- flat (L-19)
  perm  = nil,                          -- ou 'lspd.spawn' para restringir por grupo
}
```

A coordenada é armazenada **flat** (`{x,y,z,h}`) porque cruza a fronteira NUI/evento (L-19).

---

## Fluxo (provider pattern do player_state)

```
1. vHub:characterLoad → vhub_hss pergunta ao provider registrado
2. spawselector abre a UI (client) → player escolhe ponto
3. escolha validada server-side (perm do grupo, ponto existe)
4. coordenada devolvida ao vhub_hss → spawnAt(src, coord)
```

**Nunca** chame `SetEntityCoords`/`NetworkResurrectLocalPlayer` daqui — o único escritor de spawn é o `vhub_hss` (L-16).

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-16 | UI devolve coordenada; quem move o ped é o owner (`vhub_hss`) |
| L-01 | Escolha validada server-side (perm + ponto válido) antes do spawn |
| L-19 | Coordenadas flat `{x,y,z,h}` no config e nos eventos |
| A-10 | Imagens da UI declaradas em `files{}` — sem CDN externo |
