# vHub Inventory vNext — plano mestre de implementação

> Documento de execução. Não contém implementação.
>
> Baseline auditada: vhub_inventory 2.3.1 em 2026-07-17.
>
> Este documento substitui plano.md. Em divergência: código/manifests atuais → AGENTS.md /
> CLAUDE.md → contexto.md → este plano.


## 0. Veredito

O inventário atual não pode receber drops, P2P ou expansão visual antes de corrigir quatro
bloqueadores:

1. criação irrestrita de itens por /item;
2. porta-malas remoto/spoof por validação fail-open;
3. persistência sem ACK, revisão, CAS ou transação entre owners;
4. NUI otimista sem op_id/revision, capaz de divergir silenciosamente do servidor.

O remake será feito dentro do resource existente. Nenhum shim vRP, fork do CORE, CDN, framework
frontend ou segunda fonte de verdade será criado.


## 1. Escopo e fontes auditadas

### 1.1 Material lido

| Fonte | Escopo | Resultado |
|---|---:|---|
| resources/[SCRIPTS]/vhub_inventory | 38 arquivos / 179 KB | auditoria integral de Lua, JS, CSS, HTML, SQL e manifests |
| exemplos de base/resources/[dope nuis] | 31 arquivos / 7,55 MB | código legível auditado; binários e código opaco catalogados por tipo, tamanho e hash |
| exemplos de base/resources/[vrp]/vrp_chest | 765 arquivos / 14 MB | fluxo servidor/NUI auditado; 754 PNG catalogados |
| exemplos de base/resources/[vrp]/vrp_trunkchest | 762 arquivos / 10,8 MB | trunk/RMW auditados; 751 PNG catalogados |
| exemplos de base/resources/[vrp]/vrp_inventory | 878 arquivos / 34,5 MB | fluxo servidor/NUI auditado; 871 PNG catalogados |
| exemplos de base/resources/[vrp]/vrp_itemdrop | 3 arquivos / 5 KB | fluxo integral auditado |
| manual_dev_vhub.md, CLAUDE.md, contexto.md e agentes | contratos e governança | aplicados como bloqueadores de arquitetura |

Código ofuscado/minificado da Dope foi tratado como artefato não confiável e não foi executado:

- client-side/client.lua: 37.405 bytes;
- server-side/loader.lua: 38.544 bytes;
- server-side/server.js: 5.695.458 bytes;
- nui/jquery.js: 986.376 bytes.

Esses quatro arquivos não são fonte aceitável para portabilidade, auditoria ou produção.

### 1.2 O que aproveitar

| Referência | Aproveitar como conceito | Não portar |
|---|---|---|
| Dope NUI | filtros, busca, quantidade/metade/tudo, painel de detalhes, peso, feedback sonoro opcional | vRP/Tunnel, ThnAC, wildcard, código opaco, dinheiro/identidade/craft dentro do inventário, IP/CDN, polling e mutação do framework |
| vrp_inventory | P2P, drop, ações contextuais, animação/progresso de uso | monólito de itens, alvo/posição do cliente, innerHTML hostil, jQuery/CDN, Wait(1), efeitos de outros domínios |
| vrp_chest | leitura em duas colunas, peso/capacidade e UX de transferência | permissão só na abertura, SData RMW, cooldown como mutex, webhooks hardcoded, polling de todos os baús |
| vrp_trunkchest | separação visual mochila/porta-malas | ID por dono+modelo, acesso cacheado stale, RMW não atômico e broadcast -1 |
| vrp_itemdrop | TTL, feedback e animação curta de coleta | broadcast -1, lista global, nearest-player no cliente, varredura global a cada segundo |

### 1.3 Higiene obrigatória das referências

- Revogar e rotacionar os webhooks expostos nos exemplos vrp_chest/trunkchest.
- Nunca copiar URL, token, licença, loader, código ofuscado ou dependência externa.
- Não importar os 1.600+ ícones em massa.
- Criar lista fechada de assets usados pelo catálogo real, deduplicar por SHA-256 e otimizar.
- Manter exemplos fora do fxmanifest e fora do caminho de execução.


## 2. Objetivo final mensurável

O vHub Inventory vNext deve entregar:

- mochila slot-based por char_id;
- hotbar por instância/slot autoritativo;
- baús estáticos, de facção e porta-malas com sessão server-side;
- uso de itens por contrato idempotente com o dono do efeito;
- transferências mochila↔baú, P2P e drop/pickup sem duplicação;
- catálogo sanitizado e assets locais;
- NUI compacta, premium, responsiva e integralmente componentizada;
- operação replay-safe, observável e recuperável após falha;
- custo O(1) por player;
- NUI fechada 0,00 ms;
- client fora de contexto 0,00 ms;
- script idle ≤ 0,02 ms;
- tick ativo p95 ≤ 0,10 ms;
- teto declarado: OneSync Infinity 2.048 slots/processo, com 40% de folga.

Produção permanece bloqueada enquanto qualquer teste de conservação, replay ou crash falhar.


## 3. Invariantes não negociáveis

1. Servidor decide item, quantidade, owner, capacidade, distância, bucket e resultado.
2. char_id é identidade persistente; source é somente sessão efêmera.
3. Um item/serial pertence a exatamente um owner.
4. A soma global é conservada, exceto mint/burn explícito, autorizado e auditado.
5. Mesmo op_id produz o mesmo resultado sem segunda mutação.
6. Revisão antiga nunca sobrescreve revisão nova.
7. Metadata distinta nunca empilha.
8. Serial nunca é aceito do cliente, regenerado em transferência ou mesclado.
9. Estado inválido/corrompido nunca vira inventário vazio automaticamente.
10. Owner com save pendente nunca é descarregado.
11. Toda mutação tem validação, resultado tipado, auditoria e métrica.
12. Snapshot público é cópia profunda sanitizada.
13. Falha externa é isolada por pcall e termina em estado seguro.
14. Nenhum evento usa source/alvo/placa/coords enviados pelo cliente como verdade.
15. Nenhum estado contínuo usa broadcast global.


## 4. Diagnóstico atual priorizado

### 4.1 P0 — bloqueadores de produção

| Achado | Evidência atual | Correção obrigatória |
|---|---|---|
| /item público | config/inventory.lua:103; server/dev.lua | comando ausente no build produtivo ou flag false com hard-fail no boot |
| porta-malas fail-open | server/containers.lua:224-231 | netId obrigatório; entidade, placa, bucket e distância validados fail-closed |
| placa controlada pelo cliente | server/containers.lua:261-269 | placa lida da entidade e confrontada com owner veicular |
| acesso stale | server/transfer.lua usa somente _open[src] | revalidar lease, vida, chave, entidade, bucket e distância em cada mutação |
| dirty limpo antes do ACK | backpack.lua:44-49; containers.lua:79-83 | snapshot imutável; limpar apenas a versão confirmada |
| eviction durante save | backpack.lua:104-112; containers.lua:312-323 | unload aguarda ACK ou mantém owner em drain/deadletter |
| transferência não atômica | server/transfer.lua | coordenador com locks ordenados, revisão, op_id e commit conjunto |
| load concorrente de container | containers.lua:281-309 | singleflight por cid + generation token |
| persistência cega | server/sql.lua; sql/schema.sql | schema versionado, CAS, journal de operação e recovery |
| estado hostil vira vazio | server/sql.lua:50-85 | quarentena do blob, fail-closed e reconciliação |
| UI diverge silenciosamente | módulos backpack/container + cooldown | protocolo request/ACK/revision; canonical state nunca é otimista |
| A-09/A-10 quebradas | backdrop-filter e jsDelivr | vidro simulado; assets locais declarados; CSP sem rede |

### 4.2 P1 — segurança e consistência

- validQty trunca fração e limita excesso; deve rejeitar entrada inválida.
- Metadata é rasa, ilimitada e sem schema.
- Serial usa os.time + math.random sem unicidade persistente.
- giveToSlot não garante slot, peso, max-stack nem fingerprint de metadata.
- Bind da hotbar identifica item, não a instância/slot/revisão.
- REQUEST_SYNC, HUD_REQ e SET_BIND não têm rate limit específico.
- Cooldown silencioso não é mutex, replay-guard ou idempotência.
- Leitura de inventário completo é ampla demais para recursos confiados genericamente.
- TrustedResources concede capacidades diferentes por uma lista única.
- item_use remove antes do efeito e reembolsa cegamente após resultado incerto.
- DELTA de container não vincula cid + session_id + revision.
- bridge NUI converte falha de fetch em objeto vazio e esconde erro.
- módulos rerenderizam grids completos após delta simples.
- context menu/modal podem sobreviver ao unmount.
- catálogo inteiro e URL de asset atravessam NUI sem política local fechada.

### 4.3 P2 — completude e UX

- eventos DROP/PICKUP/P2P existem, mas não têm implementação canônica;
- playerhud, hotbar e inventário não compartilham uma política visual coerente;
- ausência de estados pending, empty, denied, stale, retry e offline;
- ausência de atalhos acessíveis, foco visível e reduced-motion;
- layout atual é largo e visualmente pesado;
- não existe pipeline de assets, orçamento CEF ou teste de resolução.


## 5. Ownership e arquitetura-alvo

### 5.1 Registro de ownership

| Domínio | Owner | Chave canônica | Lifecycle |
|---|---|---|---|
| mochila/hotbar | Backpack | player:<char_id> | load no characterLoad; drain no unload/drop |
| baú estático/facção | Containers | container:<config_id> | singleflight no primeiro open; eviction após último viewer + ACK |
| porta-malas | Containers | trunk:<plate canônica> | lease enquanto entidade/acesso válidos |
| drop | Drops | drop:<drop_id> | create → available → claimed/expired → tombstone |
| operação | Transaction | op_id | received → committed/rejected → TTL/GC |
| catálogo | Items | item_id | boot imutável; alteração somente por restart/versionamento |
| efeito de uso | resource dono | handler_id | reserve → effect → finalize/compensate |
| UI | módulo NUI | slice próprio | init → mount → show/hide → destroy |

Transfer é coordenador, nunca owner. SQL é fronteira única de persistência do resource, nunca
fonte concorrente de regra. Estado vivo validado permanece em VRAM; persistência registra commits
duráveis e permite recovery.

Ownership veicular usado pelo trunk:

- vhub_conce é o único owner de placa persistente, posse, chaves lógicas e dossier/capacidade;
- o CORE é owner somente do registro físico/netId/estado veicular efêmero;
- vhub_garage executa workflow de spawn/garage e nunca autoriza acesso ao trunk;
- inventory confronta entidade física + placa server-side com o contrato do vhub_conce;
- ausência de export necessário no vhub_conce exige gate de contrato; não autoriza SQL direto.

### 5.2 Estrutura proposta

Manter o resource atual e separar somente responsabilidades comprovadas:

| Arquivo/módulo | Responsabilidade única |
|---|---|
| shared/events.lua | nomes de eventos e callbacks |
| shared/utils.lua | validações puras, deep-copy, fingerprint canônico |
| server/items.lua | catálogo imutável e schema de metadata |
| server/state.lua | owner records, generation, singleflight e snapshots |
| server/locks.lua | locks ordenados sem lease temporal |
| server/transaction.lua | pipeline atômico/replay-safe |
| server/sql.lua | única fronteira oxmysql |
| server/migrations.lua | migrações numeradas e boot gate |
| server/backpack.lua | ações de mochila/hotbar |
| server/containers.lua | resolução de container e lease de acesso |
| server/drops.lua | lifecycle, interesse espacial e claim |
| server/item_use.lua | reserva/saga/finalização |
| server/exports.lua | API pública gated por capacidade |
| client/bridge.lua | foco NUI, sessão e mensagens tipadas |
| client/containers.lua | HAL de entidade/porta; nunca autoridade |
| client/drops.lua | props/target locais dentro do escopo recebido |
| web/runtime/* | bus, store, router, native bridge e lifecycle |
| web/modules/* | backpack, container, hotbar e hud; inspector é componente presentacional compartilhado |
| assets/icons/* | somente ícones locais usados |

Antes de criar cada arquivo: registrar no fxmanifest no mesmo commit. Arquivo órfão é reprovação.
Enums/limites permanecem em seus owners. Criar shared/contracts.lua somente se dois ou mais módulos
reais precisarem do mesmo contrato. Auditoria durável vive em vhub_inv_ops; usar vHub.Logger e
métricas existentes, sem módulo audit duplicado.

Higiene de implementação:

- código e símbolos em inglês; comentários/saídas PT-BR;
- toda função pública recebe uma linha objetiva de comentário PT-BR;
- função pública com Citizen.Await usa vHub.assertThread();
- fronteira externa usa pcall e falha explícita;
- zero print(), SQL inline fora de server/sql.lua ou thread por request;
- arquivo/evento/adaptador substituído é removido no mesmo commit após migrar seu último caller.

### 5.3 Estado de owner

Cada owner mantém:

| Campo | Regra |
|---|---|
| id | chave canônica imutável |
| state | slots/hotbar/capacidade normalizados |
| revision | monotônico; incrementa por commit |
| persisted_revision | última revisão confirmada |
| generation | invalida callbacks de sessão anterior |
| loading | promise singleflight |
| in_flight | no máximo uma persistência por owner |
| dirty | revisão ainda não confirmada |
| retries | contador limitado por snapshot/op |
| viewers | set de sessões autorizadas |
| poisoned | bloqueia apenas este owner até reconciliação |

Snapshot de save é deep-copy imutável. ACK da revisão N nunca limpa dirty se o owner já está em N+1.


## 6. Modelo de item

### 6.1 Definição canônica

Cada item deve declarar:

- id ASCII lowercase validado por pattern e limite;
- label e descrição PT-BR sanitizadas;
- category enum;
- weight_g inteiro não negativo;
- max_stack inteiro positivo;
- unique boolean;
- usable, droppable e transferable;
- consume_policy fechado: on_applied ou never;
- políticas de container permitidas;
- handler_owner e handler_id quando utilizável;
- metadata_schema;
- icon local;
- versão da definição.

Peso usa gramas inteiras. Quantidade aceita somente inteiro finito, positivo e dentro do limite da
ação. Nada de floor, clamp ou coerção silenciosa.

### 6.2 Metadata

- whitelist por item;
- tipos permitidos: boolean, integer, string limitada e tabela fechada necessária;
- profundidade máxima 3;
- máximo de chaves e bytes serializados;
- sem metatable, function, userdata, vector ou chave numérica arbitrária;
- normalização determinística antes de fingerprint;
- dados sensíveis excluídos do payload NUI e logs;
- metadata do cliente sempre ignorada/rejeitada;
- alteração de metadata é mutação própria, revisada e auditada.

Fingerprint de stack = item_id + versão do schema + metadata canônica. Somente fingerprints iguais
podem empilhar.

### 6.3 Itens únicos

- serial gerado somente no servidor;
- unicidade garantida no storage, não por probabilidade;
- serial preservado em mochila, baú, P2P, drop e pickup;
- item unique sempre max_stack = 1;
- colisão gera retry controlado e auditoria;
- registro garante que um serial não esteja em dois owners.

### 6.4 Hotbar

Bind canônico:

- slot da hotbar 1..5;
- owner revision;
- inventory slot;
- serial para unique ou fingerprint para stack;
- item_id somente para exibição.

Ao mover/consumir a instância, o servidor corrige ou invalida o bind e envia patch. Tecla do cliente
envia somente hotbar_slot + envelope da sessão.


## 7. Persistência e atomicidade

### 7.1 Decisão estrutural

Quantidade e troca de ownership exigem commit durável antes do ACK de sucesso. Rearranjo puramente
visual pode usar flush agrupado somente se a política de perda em crash for explicitamente aceita;
por padrão, também usa o mesmo pipeline para simplificar a prova.

Como isso endurece a política antiga “drop efêmero/SQL backup”, a implementação exige ADR numerada,
gate do vhub_arquiteto e do guardião de persistência antes do primeiro código.

### 7.2 Schema-alvo

Migração idempotente, InnoDB, utf8mb4_unicode_ci:

| Tabela | Finalidade mínima |
|---|---|
| vhub_inv_schema_migrations | version, checksum, applied_at |
| vhub_inv_player | char_id FK, payload BLOB, revision, schema_version, checksum, updated_at |
| vhub_inv_containers | container_id, kind, owner_ref, payload BLOB, capacity, revision, schema_version |
| vhub_inv_ops | op_id UNIQUE; UNIQUE actor/session/request/action; payload_fingerprint, resultado e TTL |
| vhub_inv_serials | índice derivado de unicidade: serial UNIQUE, item_id, owner_ref e revision |
| vhub_inv_drops | drop_id, payload, bucket, x/y/z primitivos, status, revision, expires_at |

Regras:

- nunca escrever em vh_*;
- FK de char_id INT UNSIGNED;
- coluna BLOB; payload serializado tem hard cap ≤ 60 KB; MEDIUMBLOB proibido sem novo gate;
- coordenadas cruzam fronteira como {x,y,z}, nunca vec3/vec4;
- queries preparadas;
- migração falha deixa Inventory.ready=false;
- blob original inválido é preservado em quarentena e nunca sobrescrito por vazio.

vhub_inv_serials é índice de integridade, não fonte de leitura de ownership. Estado canônico continua
no aggregate; índice é atualizado no mesmo commit e pode ser reconstruído. Nenhum consumidor decide
posse por essa tabela.

### 7.3 Pipeline de mutação

1. autenticar source/resource e vincular char_id + generation;
2. validar envelope, tamanho e payload_fingerprint;
3. resolver owners canônicos;
4. adquirir locks em ordem lexical: D:, C:, P:;
5. revalidar acesso e revision sob lock;
6. clonar estados e simular a mutação;
7. validar slots, stack, metadata, peso e conservação;
8. criar op_id server-side;
9. dentro da mesma transação, deduplicar pela UNIQUE actor/session/request/action;
10. request_id existente com fingerprint diferente retorna request_conflict;
11. gravar todos os owners, índice de serial e operação com CAS;
12. após ACK, publicar candidatos na VRAM;
13. emitir patches somente aos viewers autorizados;
14. auditar, medir e liberar locks em finally.

Falha antes do commit: nenhum estado muda. Falha depois do commit e antes do swap: recovery pelo
op_id/revision publica o estado confirmado. Replay retorna o resultado persistido.

### 7.4 Locks

- chave por owner;
- aquisição ordenada para impedir deadlock;
- sem lease de 300 ms;
- timeout apenas para cancelar a requisição sem liberar lock de operação viva;
- token de posse obrigatório no unlock;
- release em finally;
- P2P A→B e B→A adquirem os mesmos owners na mesma ordem;
- owner poisoned não bloqueia owners independentes.

### 7.5 Load, flush e unload

- load singleflight;
- linha ausente cria estado inicial uma única vez;
- decoder normaliza slot para integer e valida integralmente;
- item desconhecido entra em quarentena; não é descartado;
- resposta de load confere generation antes de publicar;
- uma escrita em voo por owner;
- retry do mesmo snapshot/op, máximo 5;
- backoff limitado com jitter;
- após limite: deadletter + owner bloqueado para mutação, leitura segura preservada;
- unload aguarda drain; se DB indisponível, mantém snapshot/recovery explícito;
- onResourceStop executa drain com deadline e relatório, sem fingir sucesso.

### 7.6 Auditoria

Toda mutação registra:

- op_id, request_id, action;
- source, char_id e invoking_resource;
- owners afetados;
- before/after revision;
- item_id, amount e serial quando aplicável;
- resultado/reason;
- timestamps e latência;
- sem metadata sensível.

Fila tem cap, lote, retry e deadletter. Falha de audit não desfaz commit, mas aciona alerta e métrica.


## 8. Contratos públicos

### 8.1 Envelope único

Toda intenção NUI/cliente:

| Campo | Regra |
|---|---|
| request_id | UUID/string fechada, tamanho limitado; colisão do próprio ator só causa replay próprio |
| session_id | nonce criado pelo servidor e vinculado a char_id/generation |
| expected_revision | revisão exibida pela UI |
| payload | schema específico, limite de bytes e sem campos calculáveis |

Toda resposta:

| Campo | Regra |
|---|---|
| ok | boolean |
| code | enum estável PT-BR somente na tradução visual |
| request_id/op_id | correlação |
| revision | nova revisão ou revisão canônica atual |
| patches | somente slots/owners autorizados |
| retryable | boolean explícito |

Servidor nunca ignora intenção silenciosamente.
Idempotência é decidida dentro da transação pela chave única ator/session/request/action. A consulta
prévia em VRAM é somente fast path; não autoriza commit.

### 8.2 Eventos

- todos os nomes em shared/events.lua;
- remover eventos declarados sem owner ou implementá-los na mesma fase;
- evento institucional tem replay-guard;
- eventos de delta incluem owner_id, session_id e revision;
- nenhum TriggerClientEvent(-1) para inventário/drop;
- snapshot completo somente em open/resync controlado;
- alterações normais usam patch.

### 8.3 Exports e capacidades

Substituir lista ampla por ACL por capacidade:

| Capacidade | Exemplos |
|---|---|
| catalog.read | catálogo sanitizado |
| inventory.summary | peso/contagem sem slots/meta |
| inventory.read | snapshot sanitizado do alvo autorizado |
| inventory.mint | give explícito, recursos mínimos e auditados |
| inventory.burn | take explícito |
| inventory.transfer | mutação entre owners |
| item_use.register | registro de handler próprio |

Todo export sensível:

- GetInvokingResource default-deny;
- args e alvo online validados;
- resource só atua no domínio autorizado;
- cópia profunda no retorno;
- op_id/idempotency key;
- resultado tipado;
- auditoria.

item_use.register exige GetInvokingResource() igual ao handler_owner declarado no catálogo. Primeiro
owner válido vence. onResourceStop revoga todos os handlers daquele resource e bloqueia novos usos
até registro íntegro.

Manter exports atuais por adaptador de depreciação por uma versão. Mutadores antigos não podem
receber garantia falsa de sucesso: migrar callers antes do corte.

### 8.4 Contrato de uso de item

Novo handler tipado:

1. inventário cria e persiste a reserva por op_id;
2. libera locks; nunca mantém lock ou transação SQL durante export externo;
3. chama o owner registrado com payload sanitizado;
4. owner valida seu domínio e executa efeito idempotente pelo mesmo op_id;
5. owner retorna applied, rejected ou uncertain; nunca decide a quantidade consumida;
6. inventário aplica consume_policy do catálogo e finaliza a reserva em novo commit;
7. timeout/crash retorna uncertain; nunca reembolsa cegamente;
8. recovery consulta o owner pelo op_id e finaliza exatamente uma vez.

Água/comida pertencem ao HSS. O inventário apenas reserva/consome e solicita o efeito. Veículo,
armas, saúde, documentos e telefone continuam com seus respectivos owners.


## 9. Segurança por fluxo

### 9.1 Porta-malas

Na abertura e em toda mutação:

- netId obrigatório e numérico;
- NetworkDoesEntityExistWithNetworkId;
- entidade diferente de zero e tipo veículo;
- entidade e player no mesmo routing bucket;
- ped válido, vivo e não em troca de personagem;
- distância server-side ≤ limite;
- placa lida server-side da entidade, normalizada e igual à do owner;
- placa, posse, chave lógica e capacidade vêm somente do vhub_conce;
- netId/registro físico vêm do CORE/natives; vhub_garage não decide acesso;
- chave/posse/permissão revalidada;
- entity netId, placa canônica, bucket e cid vinculados ao session_id;
- entidade removida, placa alterada, chave revogada, morte, bucket ou distância inválida fecham lease.

Se o vhub_conce ainda não expõe dossier/capacidade por contrato, parar e abrir gate de contrato.
Não inventar fallback por modelo, placa cliente, vhub_garage ou SQL direto.

### 9.2 Baú estático/facção

- config usa vec3 local;
- servidor mede distância;
- permissão vem do owner de grupos;
- config_id fechado, nunca nome livre do cliente;
- permissão e distância revalidadas em cada ação;
- viewer removido em close, disconnect, character switch e resource stop;
- load concorrente não cria duas instâncias.

### 9.3 P2P

- request contém target server id somente como intenção;
- servidor resolve target online/char_id;
- ambos vivos, mesma bucket e distância server-side;
- item transferable e metadata elegível;
- destino tem slot, peso e stack;
- locks dos dois players em ordem;
- débito/crédito no mesmo commit;
- animação somente após commit;
- disconnect de qualquer lado antes do commit cancela tudo.

Revistar/saquear não entra como P2P genérico. Exige resource owner próprio, motivo, permissão,
estado/consentimento e lease de busca.

### 9.4 Drop e pickup

- coords e bucket capturados no servidor;
- item droppable;
- criação remove do owner e cria drop no mesmo commit;
- drop possui drop_id, revision, status, TTL e tombstone;
- interesse por spatial grid + bucket; sem GetPlayers por tick;
- clientes recebem somente drops próximos;
- prop é local/efêmero e nunca fonte de verdade;
- vhub_target pode declarar intenção, mas servidor revalida distância;
- pickup faz CAS available→claimed;
- give e remoção/tombstone no mesmo commit;
- dois pickups produzem um vencedor;
- expiração concorre pelo mesmo CAS;
- restart recarrega available não expirados e reconcilia claimed.

### 9.5 Rate limit

Token bucket independente por source + ação:

- open/sync;
- move;
- use/hotbar;
- store/retrieve;
- P2P;
- drop/pickup;
- set_bind;
- exports por invoking_resource.

Adicionar limite secundário por container/drop/alvo. Excesso retorna rate_limited com retry_after;
nunca descarta silenciosamente. Rate limit não substitui lock ou idempotência.


## 10. NUI premium compacta

### 10.1 Direção visual

- minimalismo funcional; sem ornamento gratuito;
- painel principal de 780–860 px em 1080p, dimensionado por clamp;
- camada #vhub-bg Areia com opacidade 0,50; máximo absoluto 0,62;
- vidro simulado com camadas rgba opacas 0,78–0,86;
- body/html sempre transparentes;
- sem backdrop-filter;
- paleta canônica Areia + Dourado; âmbar reservado a alerta;
- Barlow Condensed local para títulos e Inter local para interface;
- corpo 13 px, metadata 11,5 px e máximo três pesos;
- logo oficial local com 28–36 px;
- raio, spacing e sombra por tokens;
- animações de 120–180 ms, somente transform/opacity;
- identidade de corrida sutil: precisão, telemetria e energia, não “gamer neon”.

### 10.2 Wireframe

| Área | Conteúdo |
|---|---|
| Topbar | título, busca, peso/capacidade, estado de sincronização, fechar |
| Filtros | todos, consumíveis, ferramentas, armas, documentos e favoritos |
| Grid | slots compactos, hotkey, quantidade, durabilidade e pending |
| Inspector | ícone, nome, descrição, metadata sanitizada e ações permitidas |
| Footer | atalhos de teclado e erro/feedback contextual |

Container usa duas colunas simétricas com topbars independentes e um único inspector compartilhado.
Em 720p, o inspector vira drawer; em ultrawide/4K, largura máxima impede esticamento.

### 10.3 Estados visuais obrigatórios

- loading/skeleton;
- vazio;
- item selecionado;
- drag válido/inválido;
- pending por slot/operação;
- stale revision;
- rate limited;
- acesso revogado;
- container fechado;
- DB/recovery indisponível;
- sucesso confirmado;
- rollback/reload explícito;
- ícone ausente local.

Canonical store nunca é alterada otimisticamente. A UI mantém pending overlay e aplica somente ACK
com revision válida. Resposta tardia de session_id antigo é descartada.

### 10.4 Interação

- duplo clique usa somente quando ação é inequívoca;
- clique abre inspector;
- drag-and-drop com origem/destino e quantidade explícitos;
- contexto por botão/teclado, não apenas mouse direito;
- QTD aceita inteiro; botões 1, metade, máximo;
- máximo é calculado pelo servidor; UI só sugere;
- Escape fecha modal → menu → inventário nessa ordem;
- Enter confirma; Tab percorre foco; setas navegam grid;
- foco restaurado após fechar modal;
- hotbar exibe pending/cooldown real;
- nenhum áudio toca sem configuração e limite;
- notificações não cobrem slot/alvo.

### 10.5 Acessibilidade

- focus-visible consistente;
- contraste WCAG AA;
- texto mínimo legível em 720p;
- não depender somente de cor;
- aria-label/role nos controles;
- prefers-reduced-motion desativa transições não essenciais;
- escala testada em 1280×720, 1920×1080, 2560×1080, 2560×1440 e 3840×2160;
- teclado completo sem mouse.

### 10.6 Runtime e lifecycle

Cada módulo implementa onInit, onMount, onShow, onHide e onDestroy:

- router faz lazy load; unmount remove DOM, referências e estado local;
- listeners registrados uma vez;
- off/removeEventListener no destroy;
- RAF, interval, setTimeout e observers cancelados/desconectados;
- subscriptions do bus/store executam off() no destroy;
- modal/context menu pertencem ao módulo e morrem no unmount;
- owner único por slice: backpack, container, hotbar e hud;
- feedback é estado local/eventbus, nunca slice global;
- inspector é presentacional; recebe props e não lê DOM/store de outro módulo;
- comunicação somente por bus;
- nenhum DOM cruzado entre módulos;
- native bridge centralizado;
- fetch apenas no service/bridge;
- erro de fetch é tipado, nunca convertido em {};
- patch atualiza somente slots tocados;
- grid completo só renderiza em mount/snapshot.

Hotbar/HUD sempre visíveis são exceção explícita ao lazy load: montam uma vez, pausam toda atividade
quando ocultos e mantêm lifecycle por visibilidade.

Em hot path, SendNUIMessage usa emissor único por tipo, batching/throttle máximo de 10 Hz. Mensagem
crítica discreta não espera batch; telemetria/estado repetido usa delta.

### 10.7 Assets e CSP

- assets/icons/<item_id>.webp ou .png;
- fallback SVG local neutro;
- logo oficial local, fonte e ícones declarados em files{};
- nomes lowercase sem espaço;
- dimensões-alvo 128×128; textura maior somente com justificativa;
- orçamento sugerido: ≤ 25 KB por ícone e ≤ 2 MB no catálogo inicial;
- deduplicação por hash;
- files{} cobre todo asset carregado;
- nenhuma URL externa; HTTPS permitido somente para callback NUI local;
- CSP: default/img/media/font/style/script somente 'self';
- connect-src permite exclusivamente https://vhub_inventory/<callback>;
- object-src 'none' e base-uri 'none';
- remover bootstrap inline de index.html;
- dados de item entram via textContent/createElement; nunca HTML de metadata.


## 11. Performance e escalabilidade

### 11.1 Loops

- zero while true sem condição explícita;
- thread fria somente com zonas configuradas, cadência mínima de 1.000 ms;
- thread quente somente perto da interação, cadência mínima de 100 ms;
- drops usam índice espacial e eventos de entrada/saída de célula;
- audit/GC processam no máximo 800 operações a cada 3.000 ms;
- migração/recovery usam cursor, lotes ≤ 800 e yield entre lotes;
- nenhum GetPlayers por tick;
- nenhum export dentro de frame loop;
- nenhuma NUI/RAF ativa quando fechada.

Migrar interação de baús configurados para vhub_target quando o contrato estiver disponível. Manter
fallback nativo somente com duas fases fria/quente e lifecycle explícito.

### 11.2 Rede

- snapshots somente em open/resync;
- patches por slots tocados;
- catálogo enviado uma vez por version/hash;
- metadata sanitizada e limitada;
- interest management por bucket/célula para drops;
- zero broadcast global;
- tamanho máximo de payload medido e rejeitado.

Fingerprint é calculado/cacheado em load, mint e mutação de metadata. Proibido repetir json.encode
sob lock ou caminho quente.

### 11.3 SQL

- queries preparadas;
- transação cobre todos os owners afetados;
- uma operação humana = uma transação lógica, nunca N+1 por slot;
- audit/GC em batch;
- retry máximo 5 e deadletter;
- índices em revision, status, expires_at e owner;
- EXPLAIN registrado para queries novas;
- p95/p99 de commit, conflito CAS e fila observados.

### 11.4 Orçamentos de aceite

| Cenário | Meta |
|---|---:|
| NUI fechada | 0,00 ms |
| client fora de chest/drop próximo | 0,00 ms |
| resource idle | ≤ 0,02 ms |
| ação ativa | p95 ≤ 0,10 ms de CPU/script |
| custo por player | O(1) |
| payload delta comum | somente owner/slots alterados |
| listeners após 100 open/close | sem crescimento |
| objetos locais após sair do escopo | zero órfãos |

Latência SQL é métrica separada da CPU e precisa de SLO definido após baseline. Não inventar número
antes do benchmark no banco real.


## 12. Plano de execução

### Fase 0 — congelamento e baseline

Objetivo: impedir expansão sobre fundação insegura.

Tarefas:

- marcar plano.md como substituído sem apagar histórico;
- inventariar consumidores de todos os exports/eventos;
- capturar schema, contagens, pesos, slots, seriais e checksums atuais;
- medir resmon/profiler/rede/SQL nos cenários idle, mochila e baú;
- desligar drops/P2P incompletos;
- remover wildcard/asset externo do plano de portabilidade;
- criar cutover monotônico default-off: inventory_vnext; persistence/protocol nunca operam separados;
- drops e p2p permanecem flags default-off após o cutover; nui_v2 só ativa com protocol v2 ready;
- registrar ADR para persistência/drop durável e contrato veicular;
- definir rollback por fase.

Gate:

- vhub_arquiteto;
- vhub_guardiao_contrato;
- vhub_guardiao_seguranca;
- vhub_guardiao_persistencia;
- vhub_guardiao_performance;
- vhub_guardiao_simplicidade.

Aceite:

- mapa completo de callers;
- migração explícita de vhub_ipad/server/init.lua, vhub_vehcontrol/server/item_handlers.lua e
  vhub_coinshop/server/ipad_relay.lua;
- baseline anexada;
- zero funcionalidade nova habilitada;
- rollback testado.

### Fase 1 — P0 imediato

Arquivos principais:

- config/inventory.lua;
- server/dev.lua;
- server/containers.lua;
- server/transfer.lua;
- client/containers.lua;
- web CSS/config.

Tarefas:

- hard-fail se give_command estiver true fora de ambiente dev explícito;
- ACL administrativa real ou remoção completa de /item;
- substituir print por vHub.Logger;
- trunk fail-closed;
- placa/entity/bucket/distance server-side;
- fechar sessão em morte, distância, bucket, entity delete, key revoke e disconnect;
- revalidar acesso por mutação;
- remover CDN e backdrop-filter;
- bridge retorna erros tipados;
- desligar otimismo cego: antes do cutover inventory_vnext, forçar resync confirmado após operação.

Aceite:

- todos os testes negativos de trunk passam;
- jogador comum não cria item;
- NUI não faz request externo;
- nenhuma divergência silenciosa em cooldown.

Rollback:

- desabilitar trunk/container e NUI v2; nunca reativar comportamento fail-open.

### Fase 2 — schema, migrations e state kernel

Arquivos principais:

- sql/schema.sql;
- server/migrations.lua;
- server/sql.lua;
- server/state.lua;
- shared/utils.lua;
- server/items.lua.

Tarefas:

- criar schema_migrations e migrações numeradas;
- adicionar revision/schema_version/checksum;
- criar ops, serials e drops;
- implementar boot ready gate;
- normalizar/validar payload legado;
- preservar inválidos em quarentena;
- deep-copy, canonical encoding e metadata schema;
- singleflight e generation;
- snapshot/version/ACK/retry/deadletter;
- drain seguro.

Aceite:

- fresh install, upgrade e rerun idempotente;
- blob inválido preservado;
- ACK antigo não limpa revisão nova;
- source reuse/char switch não publica estado antigo;
- falha SQL mantém owner seguro.

Rollback:

- backup pré-migração;
- migrações forward-only;
- código antigo continua lendo snapshot legado durante janela controlada, sem dual-write concorrente.

### Fase 3 — transaction kernel e protocolo v2

Arquivos principais:

- server/locks.lua;
- server/transaction.lua;
- server/backpack.lua;
- server/containers.lua;
- server/transfer.lua;
- server/init.lua;
- shared/events.lua;
- client/bridge.lua;
- web/runtime/*.

Tarefas:

- envelope request/session/revision;
- locks ordenados;
- CAS + op_id;
- commit multi-owner;
- replay result;
- rate limits tipados;
- patch revisionado;
- pending overlay na NUI;
- resync somente por stale explícito;
- auditoria estruturada.

Aceite:

- 50 retiradas concorrentes sobre 1 unidade: um sucesso;
- replay: zero segunda mutação;
- crash injection em todos os pontos;
- soma conservada após 1.000 operações concorrentes;
- nenhum deadlock A→B/B→A.

Rollback:

- rollback pelo cutover único inventory_vnext;
- mutations v1 ficam read-only durante cutover; nunca dois writers.

### Fase 4 — containers completos

Tarefas:

- sessão nonce por viewer;
- static/faction/trunk com resolver separado;
- capacity/dossier vindos somente do vhub_conce;
- revalidação em cada mutação;
- doors/props somente HAL client;
- vhub_target para interação;
- cache eviction após viewer zero + ACK;
- auditoria de acesso negado sem spam.

Aceite:

- dois players operam mesmo baú sem perda/dupe;
- load concorrente retorna uma instância;
- chave revogada após open bloqueia próxima ação;
- troca de bucket fecha UI/lease;
- delete do veículo fecha porta/lease e limpa client.

### Fase 5 — uso de item e hotbar

Tarefas:

- handler registry por owner;
- saga reserve/effect/finalize;
- op_id propagado ao HSS e demais owners;
- timeout uncertain reconciliável;
- hotbar por slot/serial/fingerprint;
- cooldown/status autoritativo;
- água testada via mochila e tecla;
- políticas on_applied/never definidas no catálogo;
- animação iniciada/cancelada pelo owner do efeito, não pelo inventário.

Aceite:

- água consome uma vez e altera sede uma vez;
- replay/timeout não duplica efeito nem item;
- mover/consumir unique invalida bind;
- resource handler indisponível não destrói item;
- character switch cancela reserva antiga.

### Fase 6 — P2P e drops

Tarefas:

- P2P server-distance/bucket/live/capacity;
- commit debit+credit;
- drops persistentes e bucket-scoped;
- spatial grid;
- vhub_target;
- claim CAS;
- tombstone/TTL/restart reconciliation;
- feedback/animação somente pós-commit;
- anti-spam por ator/célula/item.

Aceite:

- P2P spoof/offline/lotado/morto/outra bucket sem débito;
- dois pickups: um vencedor;
- pickup×expiry consistente;
- restart sem dupe/perda;
- zero broadcast -1;
- custo não cresce com total global de drops fora da célula.

### Fase 7 — remake NUI

Arquivos principais:

- web/index.html;
- web/runtime/*;
- web/shared/*;
- web/modules/*;
- assets/icons/*;
- fxmanifest.lua.

Tarefas:

- tokens e layout compactos;
- módulos com lifecycle completo;
- inspector compartilhado;
- pending/stale/error states;
- patch por slot;
- acessibilidade/teclado/reduced-motion;
- assets locais e CSP;
- remover HTML inline, CDN e blur;
- hotbar/HUD coerentes;
- testes de resolução e leak.

Gates:

- vhub_designer;
- vhub_guardiao_designer;
- vhub_guardiao_runtime;
- vhub_guardiao_performance;
- vhub_guardiao_seguranca.

Aceite:

- A-01..A-10;
- 100 ciclos open/close sem listener/DOM/RAF crescente;
- nenhuma request externa;
- teclado completo;
- todas as resoluções-alvo aprovadas;
- NUI fechada 0,00 ms.

### Fase 8 — observabilidade, stress e cutover

Tarefas:

- dashboards/logs de op, CAS, retry, deadletter, lock e latência;
- fuzz de payload;
- stress com concorrência;
- canary por grupo;
- reconciliação de checksums/seriais;
- documentação de operação;
- verificar que cada adaptador deprecated já foi removido na fase que migrou seu último caller;
- verificar ausência de código morto já removido nas fases donas;
- bump de versão e changelog;
- atualizar contexto.md somente pelo gate de revisão.

Aceite:

- zero P0/P1;
- conservação comprovada;
- resmon dentro do orçamento;
- recovery e rollback ensaiados;
- pentest/stress anexados;
- vhub_guardiao_revisao aprovado.


## 13. Matriz de testes obrigatória

### 13.1 Unidade/propriedade

- validQty rejeita NaN, infinito, fração, negativo, zero, string e inteiro enorme;
- slot aceita somente integer no range;
- peso inteiro sem drift;
- stack respeita max e fingerprint;
- deep-copy não compartilha referência;
- canonical metadata gera fingerprint estável;
- serial unique nunca empilha;
- conservação em sequências aleatórias de move/split/merge.

### 13.2 Persistência/crash

- fresh schema, upgrade, rerun e falha no meio da migration;
- mutation during save;
- SQL falha 1–N vezes;
- deadletter e recuperação;
- crash antes do commit;
- crash após commit antes do ACK;
- crash antes do swap VRAM;
- disconnect/unload/resource stop durante load/save;
- source reuse e character switch;
- blob truncado, JSON malformado, item desconhecido e metadata profunda.

### 13.3 Concorrência

- move simultâneo no mesmo slot;
- dois viewers no mesmo container;
- store×retrieve do mesmo item;
- P2P A→B/B→A;
- replay duplicado;
- requests fora de ordem;
- ACK antigo após revisão nova;
- pickup×pickup;
- pickup×expiry;
- close/reopen enquanto load está pendente.

### 13.4 Segurança

- export de resource não confiável;
- snapshot mutado pelo caller;
- target/source/char_id spoof;
- trunk netId nil/inválido/outra placa/outra bucket/longe;
- chave revogada;
- container_id livre;
- metadata com HTML/URL/function/metatable;
- payload acima do limite;
- flood por ação/alvo;
- request_id reutilizado com payload diferente;
- UI recebe string com tags/script sem execução.

### 13.5 NUI/CEF

- sem rede externa no DevTools;
- CSP sem erro legítimo;
- nenhum innerHTML com dado variável;
- sem ES modules, eval ou Function dinâmico;
- DOM montado abaixo de 1.500 nodes;
- nenhum fetch em app.js; somente runtime bridge/services;
- foco correto em modal/close;
- Escape/Enter/Tab/setas;
- drag mouse e teclado;
- reduced-motion;
- 720p/1080p/ultrawide/1440p/4K;
- 100/1.000 ciclos mount/unmount;
- heap/listeners/RAF estáveis;
- patch não rerenderiza grid inteiro.

### 13.6 Integração RP

- água via inventário e hotbar;
- item com consume_policy=never;
- handler offline;
- item unique com metadata;
- baú de facção com permissão revogada;
- porta-malas com veículo deletado;
- P2P perto/longe;
- drop por bucket;
- death/respawn/character switch;
- restart do resource e servidor.


## 14. Métricas e observabilidade

| Métrica | Labels limitadas |
|---|---|
| inv_operation_total | action, result |
| inv_operation_latency_ms | action |
| inv_lock_wait_ms | owner_kind |
| inv_cas_conflict_total | owner_kind |
| inv_replay_total | action |
| inv_sql_retry_total | operation |
| inv_deadletter_total | owner_kind, reason |
| inv_active_sessions | kind |
| inv_drop_active | bucket/cell agregados, sem drop_id |
| inv_nui_resync_total | reason |
| inv_payload_bytes | direction, message |

Logs não incluem token, webhook, payload bruto, metadata sensível ou cardinalidade infinita.
Alertas mínimos:

- deadletter > 0;
- retry sustentado;
- conflito CAS anormal;
- lock acima do SLO;
- checksum/serial divergente;
- fila de audit/recovery no limite;
- rate-limit distribuído suspeito.


## 15. Migração e rollback

1. backup consistente das tabelas atuais;
2. preflight valida schema, tamanho de BLOB, itens, slots, peso e hotbar;
3. migrador gera relatório sem mutar;
4. migração numerada cria novo formato;
5. checksums e somas antes/depois;
6. canary read-only;
7. cutover com writer antigo desativado;
8. canary de mutação;
9. expansão gradual;
10. remover compat somente após todos os callers migrarem.

Proibido dual-write sem owner único. Rollback volta o código/flag e restaura backup somente quando
compatível; nunca converte silenciosamente estado novo em legado.


## 16. Definition of Done

- [ ] /item impossível para jogador comum e desabilitado em produção.
- [ ] trunk fail-closed em open e mutação.
- [ ] char_id/generation em todo lifecycle.
- [ ] singleflight por owner.
- [ ] revision/CAS/op_id/replay implementados.
- [ ] transferência multi-owner atômica e durável.
- [ ] serial único e metadata schema.
- [ ] item use idempotente; água funciona em inventário e hotbar.
- [ ] P2P e drops server-authoritative.
- [ ] drops bucket/cell-scoped sem broadcast.
- [ ] exports gated por capacidade.
- [ ] eventos somente em shared/events.lua.
- [ ] NUI sem CDN, backdrop-filter, inline bootstrap ou dado em innerHTML.
- [ ] lifecycle e cleanup completos.
- [ ] assets locais declarados no fxmanifest.
- [ ] testes de crash, replay, fuzz, concorrência e conservação aprovados.
- [ ] resmon/profiler/rede/SQL antes/depois anexados.
- [ ] nenhum arquivo órfão, código morto, print ou vRP.
- [ ] versão/changelog/migração/rollback documentados.
- [ ] contexto.md atualizado exclusivamente pelo gate de revisão.
- [ ] vhub_guardiao_revisao: APROVADO.


## 17. Ordem rígida de implementação

F0 baseline → F1 P0 → F2 persistência → F3 transação/protocolo → F4 containers →
F5 item use/hotbar → F6 P2P/drops → F7 NUI → F8 stress/cutover.

Não antecipar visual ou feature. Sem F2/F3 aprovadas, F4–F7 permanecem bloqueadas.
