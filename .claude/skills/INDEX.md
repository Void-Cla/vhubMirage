# Índice de Skills — vHub Mirage

> Padrões JÁ VALIDADOS (aprovados em gate) para aplicar, não reinventar. Dono do índice: `vhub_skills`.
> Leia a linha, abra só o skill pertinente à tarefa (economia de tokens). Skill sem linha aqui = órfão; linha sem skill = drift → `vhub_skills` corrige.

## CORE / veículos
- [mapa_core_v2](mapa_core_v2.md) — LEIA ANTES de tocar em veículo/CORE; estado consolidado do descongelamento v2 (#37–#65)
- [contrato_commit_veicular](contrato_commit_veicular.md) — como ESCREVER estado físico de veículo no CORE via `commitVehicleState` (nunca `set*Data` fora do CORE)
- [validacao_fisica_replica](validacao_fisica_replica.md) — net event de veículo sem confiar no client; validar na réplica server-side
- [derivador_onread_cross_resource](derivador_onread_cross_resource.md) — resource B traduz dado bruto de A on-read (derivado nunca persiste; 2ª fonte proibida)

## Auth / segurança
- [ban_digest_multi_vetor](ban_digest_multi_vetor.md) — ban multi-vetor server-side (IP+email+whatsapp) com digest BINARY(32) pepper-derivado; lookup materializado, nunca re-derivado

## Persistência / SQL
- [batch_sql_resiliencia](batch_sql_resiliencia.md) — batch SQL resiliente: poison-op isolado + âncora FK antes do 1º write
- [plano_drift_reconciliacao](plano_drift_reconciliacao.md) — reconciliar plano/prompt externo com a arquitetura real antes de executar

## Sessão / isolamento
- [routing_bucket_isolation](routing_bucket_isolation.md) — isolar sessão/dimensão por routing bucket (escritor único de bucket)
- [ipad_relay_zero_trust](ipad_relay_zero_trust.md) — relay de app do iPad zero-trust (`ipadRelay`, broker opaco)

## Interação / NUI
- [interacao_target_migration](interacao_target_migration.md) — migrar interação proximidade+[E] → `vhub_target` (olho)
- [nui_fresh_state_rerender](nui_fresh_state_rerender.md) — NUI re-renderiza por estado fresco do servidor (sem 2ª verdade otimista)
- [velo_hud_svg](velo_hud_svg.md) — HUD de velocímetro por dial-spec (`VeloDials`), SVG sem var() em atributo (CEF)
