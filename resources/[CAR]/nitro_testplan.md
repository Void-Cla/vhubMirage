# nitro — Plano de teste em jogo (vhub_nitro + ficha do vehcontrol, decisão #30)

Roteiro para validar o nitro **em jogo**. Segue a **Doutrina da Placa**: tudo mora na PLACA
(`customization.nitro = {kit, qty, enabled, level}`), com **escritor único = `vhub_nitro`**.
A FICHA do veículo (`vhub_vehcontrol`) só EXIBE e DELEGA via exports (`setEnabled`/`setLevel`/
`chargeFromItem`). O uso por proximidade foi **aposentado** (#30). Estático/luac já validado.

## 0. Pré-voo
- [ ] Resources no ar: `vhub`, `vhub_conce`, `vhub_inventory`, `vhub_money`, `vhub_custom`,
      `vhub_vehcontrol`, `vhub_nitro`. **Dê restart** nos quatro últimos para subir a #30.
- [ ] Carro de teste seu (com chave/propriedade — o `canOperate` exige). Modelo fora da blacklist
      (kuruma é bloqueado por padrão).
- [ ] Ter saldo ≥ R$5.000 (kit) e pelo menos 1 item **Garrafa de Nitro** (`/giveitem`, id `nitro`).

## 1. Instalar o KIT na oficina (inalterado)
- [ ] Abra a oficina (perto do carro). No rodapé há **⛽ KIT NITRO (R$ 5.000)**.
- [ ] Clique → cobra R$5.000, "Kit de nitro instalado!". Clicar de novo → "já tem kit" (sem cobrar).
- [ ] Sem saldo → "Saldo insuficiente". Sem o kit, a ficha mostra "instale o Kit na oficina".

## 2. A FICHA do veículo (novo fluxo)
- [ ] Abra a ficha (chave-item / segurar **L** / caixa de ferramentas) → aba **Ficha**.
- [ ] Role até a seção **Nitro**. **Sem kit**: aparece a instrução. **Com kit**: aparecem os controles.

## 3. Ligar / desligar + nível
- [ ] Clique no botão **Desligado/Ligado** → alterna (LED verde quando ligado). Notifica o resultado.
- [ ] Arraste o slider **Durabilidade ↔ Velocidade** (1..10). Ao **soltar**, salva o nível
      (notifica "Nível ajustado"). Sem kit, os controles não respondem.

## 4. Abastecer pela ficha
- [ ] Clique **Abastecer (+1 Garrafa)** → consome 1 Garrafa de Nitro, carga vai a 100, "Nitro abastecido!".
- [ ] Sem garrafa → "sem Garrafa de Nitro". Carga cheia → botão desabilitado.

## 5. Usar o NITRO (Shift Direito)
- [ ] Dirigindo (banco do motorista), com nitro **Ligado** e carga > 0, **segure o Shift Direito**
      → potência/topspeed + **fogo no escapamento**. Soltar → para. Nitro **desligado** na ficha = não ativa.
- [ ] **Trade-off do nível**: nível **1** (durabilidade) → ganho pequeno, carga dura muito.
      Nível **10** (velocidade) → ganho ~dobro, carga acaba rápido. Compare dois níveis no mesmo carro.
- [ ] A carga **diminui** enquanto usa; ao soltar, o gasto **persiste** (servidor). Carga 0 → não ativa.
- [ ] Como passageiro NÃO ativa (só motorista, seat -1).

## 6. Persistência (Doutrina da Placa)
- [ ] Ajuste nível/ligado, gaste parte da carga, **respawne/relogue** → kit, carga, ligado e nível
      voltam como estavam (vêm da placa, não resetam).

## 7. Anti-leak / anti-abuso
- [ ] **Trocar de carro segurando o nitro**: entre noutro carro sem soltar o shift → o carro ANTIGO
      volta ao normal (sem ficar turbinado para sempre).
- [ ] Tecla rebindável: Shift Direito em Configurações > Atribuição ("Veículo: ativar nitro").
- [ ] Spam de toggle/nível/abastecer é absorvido pelo rate-limit server-side (350ms) — sem dup de item.

## 8. Calibrar depois (sem tocar código de boost)
Tudo em `resources/[SCRIPTS]/vhub_nitro/cfg/config.lua`:
- `LEVELS[1..10] = {powerMult, consumeMult}` → a curva durabilidade↔velocidade dos 10 níveis.
- `durationSec` (base do consumo no nível 1), `topSpeedBoost`, `torqueBoost`, `fireSize`, `chargePerUse`,
  `blacklist`. Preço do kit em `vhub_custom/server/oficina.lua` (`NITRO_KIT_PRICE`).

## 9. Diferenças vs. #29
- O uso por **proximidade** (usar a garrafa perto do carro) foi **removido**: abastecer é pela ficha.
- O nitro ganhou **liga/desliga** e **nível 1..10** (trade-off), calibrados na ficha.
- `vhub_nitro` continua escritor único; o vehcontrol só delega (exports). Item 'nitro' segue no catálogo.
