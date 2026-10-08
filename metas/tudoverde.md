# vHub Mirage — contexto geral, operação e gate de produção

> Status: **STAGING / REPROVADO PARA PRODUÇÃO**
> Baseline documental: 2026-10-03
> Fonte de verdade: código e manifests → `CLAUDE.md` → `.claude/contexto.md` → este resumo.

## 1. Objetivo

Framework FiveM GTARP server-authoritative, Lua 5.4, focado em cidade de corrida.
Compatibilidade vRP removida (`compat: none`). Cliente declara intenção; servidor valida,
executa e persiste. Estado crítico possui owner único.

## 2. Arquitetura

| Camada | Responsabilidade |
|---|---|
| `resources/[CORE]/vhub` | kernel, autenticação base, estado, persistência, auditoria e contratos |
| `resources/[SCRIPTS]/vhub_*` | domínios de jogo, sempre consumidores dos contratos do CORE |
| `resources/[CORE]/oxmysql` | driver MySQL upstream |
| `resources/[CORE]/vhub_oxmysql` | adaptação do vHub ao oxmysql |
| `resources/[TOOLS]/vhub_testrunner` | testes server-side controlados |
| `config/` | boot, rede, banco, identidade, ACL e ordem dos resources |
| `.claude/` | memória institucional, decisões e gates |
| `tools/` | guardião, RAG, testes e operação |

Fluxo de entrada canônico:

```text
vhub_login → vhub_sims → vhub_spawselector → vhub_hss
autenticação   criação       destino          ped/spawn/bucket/HUD
```

Domínios ativos incluem identidade, dinheiro, inventário, grupos, target, veículos,
concessionária, garagem, leilão, corrida, voz, NPC AI, polícia, administração, Pix/DF,
coinshop, loading e iPad. A lista executável está em `config/resources.cfg`.

## 3. Contratos invariáveis

- Servidor autoritativo para dinheiro, identidade, inventário, permissão, veículo e spawn.
- Escritor único por dado; nenhuma verdade paralela em UI/resource periférico.
- Escrita crítica atômica, idempotente, auditável e fail-safe.
- Payload externo validado por tipo, tamanho, autoridade, rate, replay e ownership.
- `set*Data` somente no CORE; terceiros usam contratos de commit.
- Spawn físico pertence ao `vhub_hss`.
- Estado contínuo usa State Bag; evento representa transição discreta.
- Resource ativo precisa estar em `config/resources.cfg` e no próprio `fxmanifest.lua`.
- P0 congela release; P1 bloqueia merge/promoção.

Detalhes normativos: `CLAUDE.md` e `.claude/AGENTS.md`.

## 4. Inicialização local

Pré-requisitos:

- Windows com FXServer em `build/`;
- MariaDB acessível em `127.0.0.1:3306`;
- `config/database.cfg`, `config/identity.cfg` e `config/local.cfg` locais e ignorados;
- templates públicos em `config/*.example.cfg`;
- portas TCP/UDP 30120 disponíveis.

Executar:

```powershell
cd "C:\vHUB Mirage\vhubMirage"
.\server.bat
```

O launcher falha de forma segura quando o MariaDB não responde. Configuração principal:
`config/server.cfg`; rede: `config/network.cfg`; resources: `config/resources.cfg`.

Validação local:

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 30120
Invoke-RestMethod http://127.0.0.1:30120/info.json
Invoke-RestMethod http://127.0.0.1:30120/players.json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/guardiao.ps1
python tools/rag/rag.py status
```

## 5. Publicação e rede

Para acesso externo:

1. liberar TCP/UDP 30120 no Firewall do Windows;
2. encaminhar TCP/UDP 30120 no roteador para o IP local do host;
3. confirmar ausência de CGNAT/bloqueio do provedor;
4. validar de outra rede com `connect IP_PUBLICO:30120`;
5. nunca publicar licença, senha, pepper, token ou connection string.

Exemplo de firewall, executado como administrador:

```powershell
New-NetFirewallRule -DisplayName "FiveM Server 30120 TCP" -Direction Inbound -Protocol TCP -LocalPort 30120 -Action Allow
New-NetFirewallRule -DisplayName "FiveM Server 30120 UDP" -Direction Inbound -Protocol UDP -LocalPort 30120 -Action Allow
```

Configuração atual: `0.0.0.0:30120`, `sv_lan 0`, OneSync ativo e máximo de 64 clientes.

## 6. Evidência validada

Em 2026-10-03:

- Guardião local: `aprovado=True`, `erros=0`, `avisos=0` no HEAD
  `01aec0f71a51157de20225dbc238293983ef93f4`;
- secret scan do HEAD, rastreados+ignorados, runtime state e handling: aprovados;
- 139 arquivos JavaScript validados;
- testes locais `test_b64_roundtrip.lua` e `test_tier_rules.lua`: aprovados;
- RAG: 799 fontes, 3.272 trechos, zero fonte desatualizada antes desta consolidação;
- boot anterior comprovou Cfx autenticado, MariaDB conectado, 81 tabelas e HTTP 200;
- cadastro/autenticação concorrente: 70 identidades sintéticas, sem resíduo;
- backup/restore isolado foi validado;
- workflow Guardião executa em `pull_request`, `push` de `main` e manualmente.

Essas evidências não equivalem a aprovação de produção: o worktree atual contém centenas de
alterações não consolidadas e não existe prova completa do runtime multiplayer.

## 7. Bloqueadores reais

### P0

1. **Dinheiro não é atômico em todos os fluxos.** `vhub_money/server/transfer.lua` ainda debita
   VRAM e credita online/offline por caminhos separados. Falha entre efeitos pode criar ou destruir
   saldo. Migrar transferência e mutadores legados para ledger/operação idempotente em transação SQL.
2. **Credencial Cfx historicamente exposta.** O HEAD está limpo, porém a chave antiga deve ser
   revogada no portal e removida do histórico coordenadamente. Não registrar o valor em documentação.

### P1

1. **Sem prova multiplayer:** faltam 64 clientes reais, profiler, stress, soak e restart sob carga.
2. **Pentest incompleto:** inventário estático existe, mas faltam fuzz autenticado, replay, corrida,
   bucket, queda de banco e abuso de eventos/exports críticos.
3. **Runtime funcional incompleto:** falta matriz comprovada de cadastro → login → criação → seleção →
   spawn → relog, além de dinheiro, inventário, veículos, corrida, admin e recovery.
4. **NUI depende de CDN externo:** `vhub_groups`, `vhub_garage` e `vhub_loading` carregam fontes,
   ícones ou bibliotecas remotas. Vendorizar e declarar assets no manifest.
5. **Garage possui renderização por `innerHTML`:** dados de domínio devem usar DOM seguro/
   `textContent` para eliminar stored-XSS.
6. **Operação não comprovada:** falta validação externa do endpoint, alertas remotos, branch protection,
   rollback ensaiado e release versionada em clone limpo.
7. **Worktree não promovível:** mudanças de vários domínios estão misturadas; separar commits por
   ownership, executar CI e produzir release reproduzível.

### Lacunas a confirmar antes de classificar como fechadas

- autoridade server-side de dano/saúde mecânica de veículo;
- payout de corrida usando contrato idempotente de dinheiro;
- concorrência de criação/merge de identidade;
- migrações SQL com versão, checksum e lock;
- métricas, alertas e DLQ para falhas críticas;
- smoke das correções recentes de SIMS/HSS/login após restart limpo.

## 8. Ordem mínima para produção

1. Revogar/rotacionar credenciais comprometidas; validar clone sem segredo.
2. Consolidar o worktree em commits pequenos, revisáveis e reversíveis.
3. Fechar atomicidade do dinheiro e payouts com crash/replay tests.
4. Remover dependências CDN e sinks `innerHTML` hostis.
5. Executar smoke ponta a ponta em banco descartável, incluindo falhas e restart.
6. Pentestar eventos/exports/NUI autenticados.
7. Executar 1/8/32/64 jogadores, profiler e soak mínimo de uma hora.
8. Validar backup, restore, rollback, alertas e endpoint externo.
9. Proteger `main`, exigir Guardião/CI e gerar release versionada.
10. Promover por allowlist/canário; abrir ao público somente com zero P0/P1.

## 9. Critério de “Tudo Verde”

- worktree limpo e clone reproduzível;
- Guardião/CI obrigatórios e verdes;
- zero segredo válido no HEAD/histórico operacional;
- zero P0/P1 aberto;
- smoke, pentest, stress, soak e profiler com evidência datada;
- dinheiro e persistência resistentes a crash/replay;
- backup restaurado e rollback ensaiado;
- monitoramento e alertas ativos;
- endpoint público validado fora da rede local;
- release imutável, versionada e reversível.

Até cumprir todos os itens, manter staging/allowlist.
