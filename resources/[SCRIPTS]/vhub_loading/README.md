# vhub_loading — Tela de Carregamento

**Owner:** vhub_loading

Loadscreen do servidor (tela exibida durante o download/carregamento inicial do FiveM). Resource passivo: só HTML/CSS/JS estático + `config.json` — sem scripts Lua, sem servidor, sem exports.

---

## O que faz

- Exibe a tela de carregamento (`ui/index.html`) enquanto o cliente baixa os assets
- Cursor habilitado durante o loading (`loadscreen_cursor 'yes'`)
- Configuração visual/textos em `config.json`

---

## O que NÃO faz

- Login/seleção de personagem → `vhub_login`
- Seleção de spawn → `vhub_spawselector`
- Nenhuma verdade de jogo — é puramente visual, antes do jogo existir

---

## Como customizar

Edite `config.json` (textos, música, imagens) e os assets em `ui/`. Todo asset novo já é coberto pelos globs do `files{}` no fxmanifest (`ui/**/*.*`).

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| A-10 | Assets locais cobertos pelos globs do `files{}`; sem CDN externo |
| L-07 | Ownership: só a tela de load — sem sobreposição com login/spawn |
