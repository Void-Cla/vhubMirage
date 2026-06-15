# vhub_lspdtool — Suíte Policial NATIVA vHub (roadmap)

> **Substitui** o plano antigo (fundir os escrow `l2s-dispatch` + `sd-policeradar`). Aquela abordagem
> foi **descartada**: o objetivo agora é uma **versão vHub 100% nativa** dos três exemplos de base
> (`helicam` + `l2s-dispatch` + `sd-policeradar`), enxuta, server-authoritative, sem dependência de escrow.

## Princípios
- **Server-authoritative (L-01):** quem é policial, coords e BOLO são decididos no servidor (`server/main.lua`
  pipeline `processScan` + `server/bolo.lua`). O cliente lê placa/velocidade só para a UI.
- **Pipeline único:** todo scan (radar terrestre ou aéreo) entra por `PLATE_SCANNED` → `processScan`
  (auth → normalize → rate → dedup → coords server-side → BOLO → dispatch → auditoria). Sem segunda porta.
- **NUI modular (1 `ui_page`):** `web/` hospeda múltiplos overlays passivos (radar, helicam, MDT) como
  componentes leves com um dispatcher mínimo — sem engine pesado (decisão do arquiteto, L-05/simplicidade).
- **Native-first (L-05):** câmeras, raycast, spotlight, blips via natives GTA.

## Fases
| Fase | Sprint | Escopo | Status |
|------|--------|--------|--------|
| — | LSPD-1/2/3 | Pipeline server, BOLO+dispatch NATIVOS (escrow `l2s-dispatch` eliminado) | ✅ |
| **A** | **LSPD-5** | **Radar NATIVO** (raycast LOS frente/trás, placa+velocidade, lock, overlay) — escrow `sd-policeradar` removido | ✅ |
| **B** | **LSPD-6** | **Helicam NATIVO** (cam de heli, zoom, visão FLIR/nightvision, spotlight, lock → leitura de placa aérea `kind='air'`) | ⏳ |
| **C** | **LSPD-7** | **Dispatch/MDT UI** (lista de BOLOs + scans recentes + chamados; consome exports nativos já existentes) | ⏳ |

## Arquitetura de arquivos (alvo)
```
shared/   config.lua · events.lua (E + UI message types)
server/   main.lua (pipeline + radar auth)  ·  bolo.lua (BOLO nativo)
client/   police.lua (NOTIFY/BOLO alert)  ·  radar.lua (FASE A)  ·  helicam.lua (FASE B)
web/      index.html (mount points)  ·  app.js (dispatcher mínimo)
          modules/radar/{radar.js,radar.css}  ·  modules/helicam/…  ·  modules/mdt/…   (FASE B+)
sql/      schema.sql (vhub_lspd_scans · vhub_lspd_bolos)
```

## Não-fazer
- Não reintroduzir escrow nem segunda fonte de BOLO (a pasta `web/` antiga era um spike rogue — deletada).
- Não decidir verdade crítica no cliente/JS. Não acumular `fetch` na NUI (A-06). Cleanup obrigatório (A-07).
