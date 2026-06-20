# carskill — Plano de teste em jogo (engine de skill, decisão #27)

Roteiro para validar o engine **em jogo** quando voltar. O cálculo puro já está coberto e
verde (`tools/test_tier_rules.lua`, 577 asserts); aqui ficam só os passos que exigem servidor +
mãos no jogo. Ver `vhub_vehcontrol/PLANO.md` para a arquitetura e `[CAR]/carskill.md` (banner do
topo) para o que é real × roadmap.

> **F5 (FÍSICA) AGORA ESTÁ LIGADA (decisão #28).** O build passou a virar handling REAL no carro
> que você dirige (potência/grip/freio/aero/suspensão via `SetVehicleHandlingFloat`,
> server-authoritative + re-clampado). O que falta é só a **prova em jogo do risco nº1**
> (`SetVehicleHandlingFloat` é *model-wide* no cliente — §6). Carro de terceiros aparece com handling
> base (fallback aceito). Ligado/desligado por `Config.skillApplyHandling` em
> `vhub_vehcontrol/shared/config.lua`.

---

## 0. Pré-voo

- [ ] Resources iniciados: `vhub`, `vhub_conce`, `vhub_inventory`, `vhub_money`, `vhub_vehcontrol`, `vhub_custom`.
- [ ] Carro de teste = um dos que têm bloco `p1` no catálogo: **TOYOTASUPRA, SKYLINER34, NISSAN370Z, F8T, FUSCA68, M3E46**. Carro sem `p1` = sem ficha de skill (é o comportamento correto, fail-closed).
- [ ] Ter no inventário 1+ `caixadeferramentas` (porta toolbox) e saldo ≥ R$2500 (porta oficina).
- [ ] `Config.skillDebug` está `true` em `vhub_vehcontrol/shared/config.lua` — útil agora (mostra a resolução da ficha no chat). **Desligar para `false` ao terminar a validação.**
- [ ] **F5 ligada:** `Config.skillApplyHandling = true` (a física é aplicada). As faixas por eixo ficam em `Config.skillHandling` — é AÍ que você recalibra o "feel".
- [ ] **Para o brute test:** ligar `Config.skillBruteTest = true` (libera cada eixo de 0% a 100% do budget → builds extremas). **Voltar para `false` em produção.** É seguro ligar/desligar: um build extremo salvo é puxado de volta para a faixa normal na leitura da ficha (`coerceAlloc`), não trava o carro.

## 1. Testes automatizados

- [ ] **Offline (sem servidor):** na raiz do repo → `lua tools/test_tier_rules.lua` → espera `0 falhas`.
- [ ] **In-server:** no console do servidor → `vhub_run_tests` → procurar a linha `test_vehicle_sheet_export -> ok=true, result=true` (cria/destrói um veículo-sentinela TRSK01 e exercita os exports reais).

## 2. Ficha read-only (leitura da verdade derivada)

- [ ] Entrar no carro de teste e abrir o painel: **segurar `L`** (~1s) ou usar a **chave** do inventário.
- [ ] Aba **Ficha**: confere `Tier`, `Score`, barras de **distribuição** (POT/GRIP/FRE/AERO/SUSP) e barras de **Afinidade** (reta/curva/montanha/drift/cidade). Os números são REAIS (vêm do servidor, não do JS).
- [ ] Carro **sem p1** (ex.: sultan) → a ficha aparece vazia/indisponível (correto).

## 3. Porta A — Caixa de Ferramentas (perto do veículo)

- [ ] Perto do carro, **usar o item `caixadeferramentas`** → o painel abre **direto na Ficha em modo edição** (sliders).
- [ ] Arrastar um eixo p/ cima → os outros caem (soma trava no budget). Os limites do slider respeitam mín/máx por eixo.
- [ ] **Salvar** → notificação de sucesso, **1 caixa de ferramentas é consumida**, a ficha recarrega com tier/score novos.
- [ ] Reabrir a ficha → o build novo **persiste** (não voltou ao default).
- [ ] Sem o item no inventário → tentar salvar → erro "Você precisa de uma Caixa de Ferramentas." (e o item NÃO é consumido ao só abrir).

## 4. Porta B — Oficina (mecânico, vhub_custom)

- [ ] Ir à zona da oficina e abrir o menu do mecânico.
- [ ] **Comprar uma peça de performance** (motor/turbo/freio/câmbio/suspensão/blindagem) → o **budget/score sobe** (mais pontos p/ distribuir).
- [ ] Entrar em **calibrar** → ao arrastar os sliders, a **prévia ao vivo** mostra ATUAL × CALIBRADO (score/tier). Se a prévia ficar "Calculando…" travada, é bug (era o defeito corrigido — reportar).
- [ ] **Salvar** → **R$2500 cobrados**, persiste. Reabrir → reflete o build novo.
- [ ] Saldo < 2500 → erro "Saldo insuficiente."

## 5. Integração peça × redistribuição (o coração do híbrido)

- [ ] Build base → anotar o range de cada eixo.
- [ ] Comprar peça na oficina → reabrir a ficha → o **range aumentou** (metade fixa no eixo da peça, metade livre p/ realocar).
- [ ] Redistribuir os pontos novos → salvar → relogar/respawnar o carro → o build continua lá.

## 6. Anti-abuso (rápido)

- [ ] Spam de salvar (2x em <5s) → "Aguarde um instante."
- [ ] Recalibrar carro que não é seu / sem chave → "Sem autorização para este veículo."

## 6b. F5 — física do build + brute test

Com `Config.skillApplyHandling = true`, o build vira handling real no carro que você dirige. A física
reaplica ao **entrar** no carro e a cada **recalibração**; ao **sair**, o carro volta ao handling base.

- [ ] **Sentir a diferença (normal):** dirija → calibre grip no máximo (cola na pista) → recalibre com grip no mínimo (escorrega). Grip e potência são os eixos mais perceptíveis.
- [ ] **Brute test (o teu plano):** ligue `Config.skillBruteTest = true` → calibre **0% potência / tudo em freio** → o carro fica lerdo. Inverta (**tudo em potência/grip**) → "grita". Se o comportamento muda de forma óbvia entre os extremos, **a F5 funciona**.
- [ ] **Reverte ao sair:** saia do carro e entre num **carro do mesmo modelo sem build** (ou no tráfego) → ele deve estar com handling NORMAL (a restauração desfez o override model-wide).

## 6c. Risco nº1 — model-wide (a prova que só você faz em jogo)

`SetVehicleHandlingFloat` no GTA é *model-wide no cliente*: muda todas as instâncias do modelo na SUA
máquina. O código mitiga (aplica só no carro dirigido + restaura ao sair), mas **a prova é em jogo**:

- [ ] **1 player, 2 carros mesmo modelo:** spawne 2 do mesmo modelo. Calibre um e dirija. O OUTRO (parado/tráfego) muda junto enquanto você dirige o calibrado? Ao sair, ambos voltam ao base?
- [ ] **2 players, mesmo modelo, builds diferentes:** cada um sente o PRÓPRIO build? O carro do outro aparece com handling base? (Esse é o teste que decide se dá pra ter builds distintas convivendo — se "vazar", a gente parte pro plano de propagação por entidade.)

## 7. Dívida conhecida (não é bug de teste)

- **R-3 (ordem cobrança→persistência):** hoje cobra o item/dinheiro **antes** de persistir. Se o save falhar (raro — placa fora do registro), o jogador perde a porta sem recalibrar. Decisão de design da #27 (fail-toward-house); pendente de sessão dedicada com `vhub_guardiao_seguranca` + `vhub_guardiao_contrato` para transação com rollback. **Não bloqueia o teste.**
- **Risco nº1 (model-wide):** mitigado por código, mas a prova in-game (§6c) é sua. Carro de terceiros aparece com handling base (fallback aceito).

## 8. Encerramento

- [ ] `Config.skillDebug = false` em `vhub_vehcontrol/shared/config.lua`.
- [ ] `Config.skillBruteTest = false` (volta às faixas anti-P2W de produção).
