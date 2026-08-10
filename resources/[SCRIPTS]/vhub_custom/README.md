# vhub_custom — Oficina, Bennys e Mec

**Versão:** 2.1.0 | **Owner:** `vhub_custom`

Serviço veicular unificado: estética, performance, calibração, nitro, reparo e reboque.

## Autoridade

Antes de abrir qualquer NUI, o servidor valida:

- sessão, zona e velocidade;
- `netId`, entidade veicular, placa e modelo registrado;
- bucket, distância jogador↔zona↔veículo;
- status `out`, chave/dono e motorista.

O servidor emite lease efêmero vinculado a `src + char_id + domínio + placa + netId + bucket`.
Toda mutação revalida a lease e usa lock tokenizado por placa.

## Domínios

- **Bennys:** RGB, cores extras, neon, fumaça, xenon, vidros, placas, rodas 0–12, buzina, liveries e kits 0–49 permitidos.
- **Oficina:** motor, freios, câmbio, suspensão, blindagem, turbo, calibração autoritativa e kit de nitro.
- **Mec:** pneus, motor, lataria e reboque com destino configurado e movimento server-side.

O cap de stage deriva de `vtype/category/tier_max` persistidos. Classe enviada pelo cliente não participa.

## Persistência e pagamento

| Dado | Escritor único |
|---|---|
| Customização, health, damage e posição | `vhub_conce` |
| Dinheiro e compensação exata | `vhub_money` |
| `customization.handling` | `vhub_vehcontrol` via export gated |
| `customization.nitro` | `vhub_nitro` |
| Saga e guard por placa (`prepared/charged/applied/refunded`) | `vhub_custom` |
| Auditoria veicular append-only | `vhub_conce` → `vhub_vehicle_log` |

Fluxo: `validar → lock → prepared → charged → revalidar → persistir → applied → auditar`.
Os ledgers `vh_custom_operations`/`vh_custom_operation_guards` cobrem operações pagas e gratuitas. UNIQUE por request, guard exclusivo por placa e claim CAS de 300s impedem concorrência. Recovery limitado (20/30s) confirma o estado aplicado ou estorna offline.

## Dependências

```text
oxmysql
vhub
vhub_conce
vhub_money
vhub_vehcontrol
vhub_nitro
```

## Mapa de integração

Eventos registrados são exclusivamente a borda client→server da intenção do jogador.
Integração server→server preventiva: `beginService(src, domain, zone_id, plate, net_id)`,
gated para `vhub_admin`/`vhub_garage` e com a mesma prova física/rate do jogador.

| Resource | Exports consumidos |
|---|---|
| `vhub_conce` | `canOperate`, `getVehicle`, `getVehicleState`, `saveVehicleState`, `updatePosition`, `getCatalog`, `appendVehicleAudit` |
| `vhub_money` | `commitPayment`, `refundPayment` |
| `vhub_vehcontrol` | `getVehicleSheet`, `getVehicleSheetPreview`, `reserveWorkshopRecalibration`, `commitWorkshopRecalibration`, `cancelWorkshopRecalibration` |
| `vhub_nitro` | `getNitro`, `installKit` |

Nomes de eventos pertencem exclusivamente a `shared/events.lua`.

## NUI

- runtime modular com lifecycle completo;
- bridge HTTP único em `web/runtime.js`;
- CSP sem scripts externos;
- preview cosmético limitado a 10 Hz;
- órbita e zoom coalescidos a 30 Hz;
- timers/listeners removidos no fechamento;
- HTML/CSS transparentes, sem CDN e sem `backdrop-filter` sobre o GTA.

## Configuração

Cada entrada de `VHubCustom.cfg.zones` usa coordenadas flat. Zona mecânica exige destino de reboque:

```lua
{
  id = 'mec_ls', domain = 'mec',
  x = 136.0, y = -1082.0, z = 29.1,
  tow_drop = { x = 142.0, y = -1081.0, z = 29.2, h = 0.0 },
}
```

## Migração 1.x → 2.0

Removidos: `BENNYS_OPEN`, `OFICINA_OPEN`, `OFICINA_AUTH*`, `MEC_TOW_DO`, `mecTowDone`,
`REQ_CATALOG`, `REQ_VEH_DATA`, `VEH_DATA` e `ZONE_ENTER/LEAVE`.

Payloads de `BENNYS_APPLY`, `MEC_REPAIR`, `MEC_TOW_REQ`, `OFICINA_TUNE`,
`OFICINA_PREVIEW` e `OFICINA_NITRO_KIT` agora exigem lease; não há compatibilidade insegura.
