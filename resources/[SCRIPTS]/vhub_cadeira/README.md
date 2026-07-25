# vhub_cadeira — Sentar em Props

**Versão:** 1.0.0 | **Owner:** vhub_cadeira

Permite sentar em qualquer cadeira, sofá, banco ou cama do mapa via `vhub_target`. 100% client-side (física efêmera — L-02), zero framework externo, zero servidor. Adaptado do Caticus Chairs para o padrão vHub.

---

## O que faz

- Catálogo de ~177 modelos de props sentáveis em `shared/props.lua`
- Interação por mira: opção "Sentar" aparece ao mirar o prop via `vhub_target`
- Altura de assento correta por modelo (offset calibrado)
- Sair via target ou automaticamente ao andar
- Anti-empilhamento: prop ocupado não mostra a opção para outro player

---

## Dependências

```
vhub_target
```

---

## Exports

Nenhum — é UX pura client-side, sem verdade crítica. Não há o que outro resource consumir.

---

## Como adicionar um novo prop sentável

Adicione o modelo (e offset, se necessário) em `shared/props.lua`:

```lua
-- shared/props.lua
PROPS['prop_minha_cadeira'] = {
  offset_z = 0.49,   -- altura do assento em relação à origem do prop
  heading  = 180.0,  -- rotação relativa para o ped ficar de frente
}
```

O `client/init.lua` registra as opções no `vhub_target` no boot; o registro é efêmero (limpo em `onClientResourceStop` pelo próprio target).

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-02 | Sentar = física efêmera client-side; nenhuma verdade persiste |
| L-05 | Natives diretos (`TaskStartScenarioAtPosition`/anim) — sem infra custom |
| L-06 | Sem polling próprio — a detecção de proximidade é do vhub_target |
| L-15 | Todos os arquivos referenciados no fxmanifest |
