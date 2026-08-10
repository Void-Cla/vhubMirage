# vhub_npcai — Plano Mestre de Arquitetura

> **Resource:** `resources/[SCRIPTS]/vhub_npcai`
> **Domínio:** NPCs conversacionais por voz (STT → intenção → resposta em áudio), server-authoritative.
> **Status:** DESIGN CONGELADO EM DOCUMENTO — nenhum script de controle escrito ainda. Este arquivo é a
> fonte única de *o quê / por quê / para quê* de cada decisão. Implementação vem depois, por fases, sob gate.
> **Premissa de plataforma:** Windows + FiveM (FX Server, OneSync Infinity, 500+ players) + sidecar Python
> (`server.py`) já validado em benchmark nesta máquina.
> **Lei-mestra herdada do `manual_dev_vhub.md`:** *peça ao dono, nunca escreva no que não é seu.*
> O sidecar de IA é um **serviço interno** (`127.0.0.1`); o **FiveM server é a autoridade** — decide
> proximidade, permissão, rate, e só ele fala com o Python.

---

## 0. Índice

1. Objetivo, escopo e não-escopo
2. A verdade dura do benchmark (o que a máquina realmente entrega)
3. Metas mensuráveis (o contrato de performance)
4. Arquitetura em camadas (onde cada peça mora)
5. O pipeline canônico de uma fala (fim-a-fim)
6. Proximidade, grupos e conversa privada
7. Reconhecimento de intenção — as 3 abordagens (60% → 80% → 90%)
8. Banco de gatilhos por NPC (saudação + profissão)
9. Cache de áudio e montagem (stitching, nome dinâmico, murmúrios, transições)
10. Fila de geração ao vivo (o anti-gargalo)
11. Fallback Gemini (menor modelo, prompt por NPC, compactação)
12. Auto-evolução (o sistema que aprende sozinho)
13. Memória progressiva por personagem (isolada por NPC)
14. Os quatro NPCs de exemplo (Marcus, Rebeca, Carvalho, Jorjão)
15. Segurança (zero-trust, anti-abuso, prompt-injection, PII)
16. Ownership e integração com o core vHub
17. Orçamentos e a doutrina de escala (por que o FX tick nunca sofre)
18. Gaps e lacunas identificados + soluções
19. Estrutura de arquivos, schema SQL e config
20. Roadmap faseado + gates de governança

---


## 1. Objetivo, escopo e não-escopo

### 1.1 O que este projeto é

Um sistema em que **peds do mundo viram NPCs que ouvem e respondem por voz**, com personalidade,
vocabulário e memória próprios. O jogador chega perto de um NPC, fala no microfone, e o NPC responde
com áudio — de forma **rápida, natural, barata e segura**, mesmo com centenas de players na cidade e
dezenas de NPCs ativos.

O eixo de engenharia é **não gerar ao vivo o que já foi gerado antes**. A fala do jogador *sempre* passa
por STT (não há como cachear a voz de um jogador desconhecido), mas a **resposta** do NPC é resolvida,
na maioria esmagadora das vezes, por **áudio pré-gravado montado em tempo real** — sem TTS, sem LLM.
Só o que é genuinamente novo escala para a fila de geração ao vivo (TTS) e, em último caso, para a API
do Gemini.

### 1.2 Escopo desta fase

- Motor de voz: STT (Whisper) + TTS (SAPI subprocess) — **já construído e validado** (`server.py`).
- Motor de intenção em 3 níveis (keywords → regex+contexto → classificador leve) + auto-evolução.
- Cache de áudio com montagem (saudação + nome + corpo + murmúrio + transição).
- Fila de geração ao vivo com teto rígido (anti-gargalo).
- Fallback Gemini com compactação e segurança.
- Memória progressiva por (personagem × NPC), isolada.
- Definição narrativa e de gatilhos de 4 NPCs-exemplo.

### 1.3 Não-escopo (explícito, para não inflar — L-15/simplicidade)

- **Controle do ped em si** (spawn, animação, olhar, lip-sync): o dono virá depois; o dono do ped é
  `vhub_hss` (L-16). Este plano **assume** um contrato de controle e o especifica, mas não o implementa.
- **Transporte de microfone definitivo:** integra com o projeto `vhub_voicePMA` (em design). Aqui
  fixamos o contrato mínimo (push-to-talk → blob → server → sidecar) e marcamos como gap #1.
- **Diálogo com múltiplos turnos longos / "chatbot"**: o NPC é um personagem de RP com respostas curtas,
  não um assistente. Compactação é feature, não limitação.
- **Tradução multi-idioma ampla:** PT-BR é primário; EN é suportado pelo motor mas não é foco narrativo.


## 2. A verdade dura do benchmark (fonte: teste desta máquina, 2026-07-27)

> Honestidade técnica precede tudo (diretriz do CLAUDE.md). Nenhum número deste plano é aspiracional:
> ou saiu do benchmark, ou está marcado como **estimativa** a validar.

Hardware do teste: 8 núcleos físicos / 16 lógicos, 15,7 GB RAM, Whisper `base` CPU-only.

| Métrica medida | Valor | Implicação de projeto |
|---|---|---|
| **STT `base` — throughput** | **1,07 req/s constante** | Serial, CPU-only. Independe de carga: 10, 40 ou 80 chamadas rendem o mesmo throughput. **É o teto real.** |
| STT — 10 simultâneos | avg 5,17 s · max 9,34 s | Latência escala **linear O(N)** com a fila. |
| STT — 40 simultâneos | avg 19,2 s · max 37,4 s | 40 na fila = último espera ~37 s. Inaceitável para conversa. |
| STT — 80 simultâneos | avg 37,9 s · max 74,9 s | Confirma: fila serial é o inimigo. |
| STT — CPU / RAM | ~52% CPU · ~10,2 GB pico | Sobra de CPU: a serialização é do modelo, não de saturação de núcleos. |
| **TTS subprocess** | **100% confiável**, 0 erros | Isolamento por subprocess resolveu o freeze COM do SAPI. |
| TTS — latência | 0,54 s (baixa carga) → 2,13 s (80 simult.) | Escala suave; semáforo controla. TTS **não** é o gargalo. |
| **Erros totais** (260 chamadas) | **0** | Motor estável. |

### 2.1 A conclusão que define toda a arquitetura

**O gargalo é o STT, e o STT é inevitável por fala.** Cachear resposta (TTS/Gemini) é ótimo, mas
**não remove o custo de transcrever o jogador.** Portanto o plano ataca o STT em duas frentes:

1. **Reduzir o custo de cada STT** (engine mais rápido, VAD, teto de duração, modelo certo).
2. **Reduzir o número de STTs** (push-to-talk só perto do NPC, nunca escuta ambiente contínuo).

E ataca a **resposta** de forma independente: cache de áudio elimina TTS/Gemini em 80%+ dos casos,
e a fila de geração ao vivo protege os 20% restantes contra gargalo.


## 3. Metas mensuráveis (o contrato de performance)

| Meta | Alvo | Como é atingida |
|---|---|---|
| **STT ao vivo simultâneo sem gargalo** | **≥ 20** (aspiração do dono), **5 garantido hoje** | Migrar para `faster-whisper` int8 + VAD + teto de 5 s por fala + pool de workers. §17. |
| Latência percebida até "NPC reage" | **≤ 250 ms** | **Murmúrio instantâneo** tocado no gatilho, antes de qualquer geração. §9/§10. |
| Latência até resposta cacheada completa | **≤ 400 ms** | Montagem de WAV pré-gravado (concatenação PCM). §9. |
| Latência até resposta ao vivo (TTS) | **≤ 2,5 s** | Compactação Gemini → texto curto → TTS curto → fila com teto 2–3. §10/§11. |
| Custo no **FX Server tick** | **~0 ms** (idle 0,00 / ativo O(1)) | Toda a IA roda no **sidecar Python**, fora do tick do FiveM. §17. |
| Custo do resource Lua | idle ≤ 0,02 ms · ativo p95 ≤ 0,10 ms | Threads fria/quente de proximidade, sem polling de todos os players. §6/§17. |
| Cobertura sem Gemini (regime maduro) | **≥ 80%** das falas | 3 níveis de intenção + cache auto-evolutivo. §7/§12. |
| Chamadas Gemini / player / min | **teto rígido** (ex.: 6) | Rate-limit + circuit breaker + cache. §11/§15. |
| Confiabilidade do motor | **0 erros sob carga** | Já validado (§2). Subprocess TTS + fila serial STT + pcall nas fronteiras. |

> **Regra de honestidade:** "20 ao vivo sem gargalo em máquina fraca" **não** sai do Whisper `base`
> serial de hoje (que dá 5). Sai da soma de: engine 3–5× mais rápido + VAD + falas curtas + cache
> removendo a resposta + pool. O caminho está em §17. Enquanto não migrado, o **teto seguro é 5**, e
> o sistema **degrada com graça** (murmúrio + "peraí") acima disso — nunca trava, nunca mente.


## 4. Arquitetura em camadas (onde cada peça mora)

O vHub opera em 4 camadas (CLAUDE.md). O `vhub_npcai` respeita a fronteira de cada uma e **adiciona
uma quinta peça externa**: o sidecar de IA.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  L1 — KERNEL (Lua server)  ── AUTORIDADE                                       │
│  vhub_npcai/server/*.lua                                                       │
│  • valida proximidade (coords server-side)   • rate-limit por char            │
│  • decide QUAL npc, se pode falar, idioma     • dono da memória (SQL)          │
│  • relay para o sidecar (HTTP 127.0.0.1)      • gate HSS (vivo? algemado?)     │
│  • NUNCA renderiza, NUNCA confia no cliente                                    │
└───────────────┬───────────────────────────────────────────────┬──────────────┘
                │ (HTTP loopback, server→sidecar apenas)          │ (exports vHub)
                ▼                                                 ▼
┌───────────────────────────────┐              ┌────────────────────────────────┐
│  SIDECAR IA (Python, externo) │              │  CORE vHub (getUser, char_id,  │
│  server.py  +  motor de       │              │  KV, vhub_hss ped, money...)   │
│  intenção/cache/gemini        │              └────────────────────────────────┘
│  • STT (faster-whisper pool)  │
│  • intenção 3 níveis          │  ⇦ TODO o custo de CPU/RAM pesado vive AQUI,
│  • cache de áudio + montagem  │     fora do tick do FX Server.
│  • TTS (SAPI subprocess)      │
│  • Gemini fallback            │
└───────────────────────────────┘
                ▲
                │ (áudio do mic; blob via NUI callback → server)
┌───────────────┴───────────────────────────────────────────────────────────────┐
│  L2 — HAL (Lua client)   vhub_npcai/client/*.lua                                │
│  • proximidade local (thread fria/quente)   • push-to-talk (tecla perto do NPC) │
│  • captura mic (NUI MediaRecorder)          • toca WAV recebido (spatial)        │
│  • NÃO decide verdade; só propõe e executa                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│  L3/L4 — NUI (opcional)   indicador visual "[E] falar", legenda, VU do mic       │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Decisão-chave e o porquê:** o cliente **nunca** fala com o sidecar Python. O áudio do mic vai do
cliente para o **FiveM server** (evento/NUI callback), e só o server relaya para `127.0.0.1:7512`.
Isso satisfaz L-01 (server é autoridade), impede que um jogador chame o STT direto para abusar de CPU,
e mantém o sidecar invisível à rede externa. O sidecar **só escuta em loopback** (já é o caso no
`server.py`: `host="127.0.0.1"`).


## 5. O pipeline canônico de uma fala (fim-a-fim)

```
(1) Cliente perto do NPC (≤10 m)  →  UI mostra "[E] Falar com Marcus"
(2) Jogador segura push-to-talk   →  NUI MediaRecorder captura (cap 5 s, VAD corta silêncio)
(3) Solta a tecla                 →  blob de áudio → NUI callback → SERVER (Lua)
        ├─ SERVER valida: char vivo? não algemado? proximidade real (coords server)? rate ok?
        ├─ SERVER anexa contexto: char_id, npc_id, idioma, sessão de conversa
        └─ SERVER → POST /converse  (sidecar)          ← 1 round-trip HTTP loopback
(4) SIDECAR: STT (faster-whisper) transcreve  →  texto normalizado
(5) SIDECAR: dispara MURMÚRIO imediato          ──────────────┐  (resposta ≤250 ms:
        (áudio "hmm, deixa eu ver..." já em cache, devolvido    │   preenche o silêncio
         no ACK enquanto o resto processa)                      │   enquanto (6..) roda)
(6) SIDECAR: motor de intenção 3 níveis sobre o texto           │
        ├─ N1 keywords  (≥conf?) ─── HIT ─┐                     │
        ├─ N2 regex+ctx (≥conf?) ─── HIT ─┤                     │
        ├─ N3 classif.  (≥conf?) ─── HIT ─┤                     │
        │                                 ▼                     │
        │                       (7a) CACHE HIT:                 │
        │                       montar WAV = saudação + nome + corpo (+transição)
        │                       → devolve áudio final (sem TTS, sem Gemini)
        │                                                       │
        └─ MISS (conf<thr) ───► (7b) GEMINI:                    │
                menor modelo + prompt do NPC + memória do char + "compacte em ≤N palavras"
                → texto curto → entra na FILA de TTS (teto 2–3)
                → TTS gera WAV → SALVA no cache (auto-evolução) → devolve
(8) SERVER recebe áudio final  →  TriggerClientEvent(alvo) com o WAV/stream
(9) CLIENTE: espera o murmúrio atual terminar  →  toca resposta (spatial, no ped)
(10) SIDECAR/SERVER: registra interação (intenção, memória nova, sample p/ treino N3)
```

**Por que murmúrio em (5) e não esperar (6/7):** conversa com silêncio de 2 s é constrangedora. O
murmúrio custa zero (já cacheado), toca imediato, e compra tempo para a geração real sem o jogador
perceber espera. É o mesmo truque de "hmm, deixa eu pensar" que humanos usam.


## 6. Proximidade, grupos e conversa privada

### 6.1 O NPC nunca "escuta o ambiente"

Não há escuta contínua. O jogador **decide falar** (push-to-talk) e só **quando está no raio**. Isso:
- Reduz drasticamente o nº de STTs (só fala intencional entra na fila).
- Elimina captação de conversa alheia / privacidade.
- Torna o custo **O(1) por interação**, não O(players × tempo).

### 6.2 Threads de proximidade (padrão do manual §4.1 — fria + quente)

```lua
-- client: thread FRIA (1 Hz) marca "perto de algum NPC"
--         thread QUENTE (só quando perto) desenha "[E] Falar" e arma push-to-talk
```
Nenhuma iteração de todos os players por tick (doutrina de escala §4.7 do manual). Cada cliente só
mede a própria distância aos NPCs de config — custo local O(nº NPCs próximos), tipicamente 0–1.

### 6.3 Autoridade de proximidade é do SERVER

O cliente propõe "quero falar com o NPC X". O **server reconfere** a distância com coords
server-side (`GetEntityCoords` do ped no OneSync, ou coords fixas do NPC de config) antes de aceitar.
Cliente mentindo distância = rejeitado (L-01, anti-teleport). Config do NPC carrega `vec3` da posição
e `raio` (L-19: `vec3` para ponto sem orientação; nunca cruza fronteira como vetor — vira `{x,y,z}`).

### 6.4 Grupo vs privado (múltiplos char_id perto do mesmo NPC)

- **Cada fala é de UM falante** (o char_id que segurou o push-to-talk). O NPC responde **ao falante**.
- **Lock de fala por NPC:** o NPC só diz uma coisa por vez. Enquanto fala/gera, novos pedidos ao MESMO
  NPC entram numa micro-fila por NPC (máx. curta) ou recebem murmúrio "peraí, já te atendo". Isso evita
  vozes sobrepostas do mesmo ped.
- **Contexto de grupo (opcional, fase futura):** o server sabe quem está no raio; pode injetar no
  prompt "há mais gente por perto" para o NPC ajustar o tom. Não é necessário na fase 1.
- **Áudio espacial:** a resposta toca no ped (posição 3D), então quem está perto ouve naturalmente —
  "privado" é emergente da distância, não precisa de canal dedicado. Se o RP exige sigilo real,
  fase futura pode restringir o `TriggerClientEvent` só ao falante.

### 6.5 Saudação individual por personagem (aceleração progressiva)

Primeira vez que o `char_id` cumprimenta o NPC, geramos e **cacheamos a saudação com o nome dele**
(`name_cache/<slug>.wav`). Da segunda vez em diante, a saudação é instantânea e pessoal. Nomes são
finitos no servidor → custo de geração amortizado a zero. É a base da sensação de "o NPC me reconhece".


## 7. Reconhecimento de intenção — as 3 abordagens

O texto transcrito é normalizado (minúsculas, sem acento, sem pontuação, tokens) e passa por uma
**escada de escalonamento**: cada nível é mais caro e mais preciso que o anterior. Para no primeiro
que bater a confiança mínima. **A maioria para no Nível 1.**

### 7.1 Nível 1 — Simples: keywords no texto (~60% dos casos)

- **O quê:** conjuntos de gatilhos por NPC — `gatilhos_saudacao` e `gatilhos_profissao`.
- **Como:** interseção ponderada entre tokens da fala e os conjuntos do NPC atual. Score = soma de
  pesos dos gatilhos encontrados. Confiança = score normalizado.
- **Custo:** O(nº tokens) com lookup em `set`/`dict` — ~1 ms. Zero dependência externa.
- **Cobre:** saudações ("e aí", "salve", "bom dia"), pedidos óbvios de profissão ("conserta", "preço").
- **Exemplo (Jorjão, mecânico):** "e ae jojão conserta meu carro" → saudação=`e ae` + profissão=`conserta`
  + objeto=`carro` → intenção `saudacao+servico_reparo` com alta confiança.

### 7.2 Nível 2 — Médio: regex por intenção + contexto do NPC (~80%)

- **O quê:** padrões regex nomeados por intenção, **específicos do domínio do NPC**, mais o **estado da
  conversa** (já cumprimentou? está no meio de uma negociação? última intenção?).
- **Como:** cada intenção tem 1..N regex (`\b(quanto|pre[çc]o|valor|custa)\b.*\b(carro|moto|caranga)\b`
  → `perguntar_preco`). Slots extraídos por grupos de captura (qual carro, qual serviço). O contexto
  desempata intenções ambíguas ("quanto?" logo após ver um carro = preço daquele carro).
- **Custo:** O(nº regex do NPC) — dezenas, pré-compiladas — ~1–3 ms.
- **Cobre:** pedidos estruturados com variação linguística que keyword sozinho erra.

### 7.3 Nível 3 — Avançado: classificador leve (~90%)

- **O quê:** um classificador de texto→intenção **por domínio de NPC**, treinado nos exemplos
  acumulados (inclusive nos **erros típicos do STT** — ver §7.5).
- **Escolha de motor (decisão para máquina fraca):** **TF-IDF + regressão logística / SVM linear
  (`scikit-learn`)** como padrão. É leve (poucos MB, inferência sub-ms, treino em segundos), não exige
  GPU e é interpretável. **Embeddings locais (MiniLM/sentence-transformers)** ficam como *opção de fase
  futura* — dão robustez a paráfrase, mas somam ~90 MB + CPU de inferência; só valem quando o volume
  justificar. Documentado como trade-off, não adotado por padrão (simplicidade / L-15).
- **Custo:** inferência TF-IDF ~1 ms; treino offline (§12) fora do caminho quente.
- **Cobre:** paráfrases, gírias, transcrições ruidosas que regex não previu.

### 7.4 A escada de escalonamento (o coração da economia)

```
texto ─► N1 keyword ──conf≥0.75?──► HIT (cache)
            │ não
            ▼
         N2 regex+ctx ──conf≥0.70?──► HIT (cache)
            │ não
            ▼
         N3 classif. ──conf≥0.65?──► HIT (cache)
            │ não
            ▼
         GEMINI (miss real) ──► gera ──► cacheia ──► vira treino p/ N3
```

Limiares de confiança são **config por NPC** (calibráveis). Cada degrau evitado é CPU e latência
poupadas. O objetivo do sistema maduro: **N1+N2+N3 resolvem ≥80%**, Gemini fica para o genuinamente novo.

### 7.5 Robustez a erro de STT (crítico e frequentemente esquecido — gap resolvido)

O STT erra com gíria, nome próprio e ruído. Defesas:
- **`initial_prompt` do Whisper** enviesado ao vocabulário do NPC ("Jorjão, oficina, caranga, turbo…")
  aumenta acerto de termos do domínio.
- **Fuzzy match** (distância de edição) nos gatilhos N1 para absorver pequenos erros ("jojão"≈"jorjão").
- **N3 treinado sobre a saída real do STT** (não sobre texto ideal) — aprende os erros sistemáticos.
- **Normalização agressiva** (sem acento, sem pontuação, colapso de repetição).


## 8. Banco de gatilhos por NPC (saudação + profissão)

Config declarativa, uma tabela por NPC. **Escritor único = config** (recarregável a quente). Exemplo
canônico (Jorjão, mecânico):

```lua
Jorjao = {
  id       = 'jorjao',
  nome     = 'Jorjão',
  profissao= 'mecanico',
  idioma   = 'pt',

  gatilhos_saudacao  = { 'e ae','eae','oi','ola','salve','bom dia','boa tarde',
                         'boa noite','tudo bem','fala','opa','beleza' },

  gatilhos_profissao = { 'conserta','arruma','tuna','trato','olhada','ver','revisa',
                         'carro','moto','caranga','bomba','turbo','motor','pane','oleo' },

  -- respostas montáveis: segmentos + slot [nome] (áudio pré-gravado com a voz do NPC)
  respostas_reparo = {
    { 'salve_',  '[nome]', '_olhadinha_bomba' },   -- "Salve <nome>, vou dar uma olhadinha nessa bomba!"
    { 'opa_',    '[nome]', '_manda_ver' },          -- "Opa <nome>, manda ver que eu resolvo!"
    { 'fala_',   '[nome]', '_que_que_deu' },        -- "Fala <nome>, que que deu no carro?"
  },

  murmurios   = { 'hmm_deixa_ver', 'peraí_ja_vejo', 'uhum_saca_so' },
  transicoes  = { 'entao_', 'olha_so_', 'pois_e_' },
  conf_min    = { n1 = 0.75, n2 = 0.70, n3 = 0.65 },
}
```

**Regra de ouro do banco:** a variação é escolhida **aleatoriamente** entre as opções → o NPC nunca
soa robótico repetindo a mesma frase. E como cada segmento é um WAV curto, a montagem cobre dezenas de
combinações com poucos arquivos.


## 9. Cache de áudio e montagem (stitching)

### 9.1 As quatro classes de áudio

| Classe | Papel | Quando toca | Origem |
|---|---|---|---|
| **Murmúrio** | tapa-buraco instantâneo | no gatilho, antes da resposta | pré-gravado por NPC |
| **Saudação** | abertura personalizada | início da resposta | pré-gravado (segmento) |
| **Nome** | identidade do falante | encaixado na saudação | gerado 1× por char, cacheado |
| **Corpo/transição** | conteúdo da resposta | após saudação | cache (hit) ou TTS (miss) |

### 9.2 Montagem = concatenação PCM (rápida, sem re-encode)

WAV do SAPI é PCM linear. Se todos os segmentos compartilham `sample rate`/canais/bits (garantido ao
gerar), montar é **copiar frames** — sub-50 ms, sem TTS:

```python
# stitch(segmentos) -> bytes  (concatena WAVs homogêneos)
def stitch(paths: list[str]) -> bytes:
    out = io.BytesIO()
    with wave.open(out, 'wb') as dst:
        for i, p in enumerate(paths):
            with wave.open(p, 'rb') as src:
                if i == 0: dst.setparams(src.getparams())
                dst.writeframes(src.readframes(src.getnframes()))
    return out.getvalue()
```

Exemplo Jorjão: `stitch(['salve_.wav', 'name_cache/joao.wav', '_olhadinha_bomba.wav'])`
→ "Salve João, vou dar uma olhadinha nessa bomba!" — **zero** chamada a TTS ou Gemini.

### 9.3 Nome dinâmico gerado uma vez

No primeiro contato do char (ou no login, pré-aquecendo), gera `TTS(nome) → name_cache/<slug>.wav`.
Slug sanitizado (sem path traversal, sem caractere estranho — §15). Reuso eterno.

### 9.4 Chave de cache determinística (evita duplicar e permite compartilhar)

Chave = `hash(npc_id + intenção + variante + idioma)`, **com o nome como slot separado** — assim a
mesma intenção com nomes diferentes **compartilha o corpo** e só troca o `name_cache`. Arquivo:
`audio_cache/<npc_id>/<intencao>__<variante>.wav`.

### 9.5 Gestão de disco (gap resolvido)

- **Dedup por hash de conteúdo** (mesmo áudio, uma cópia).
- **LRU com teto por NPC** (ex.: 500 MB) — evicta o menos usado.
- **Seed no deploy:** murmúrios, saudações e respostas comuns já vêm gravados (cold-start sem silêncio).


## 10. Fila de geração ao vivo (o anti-gargalo)

Dois recursos escassos, duas filas independentes:

### 10.1 Fila STT (serial — Whisper não é thread-safe)

- Já existe (`_stt_queue` + worker). **Otimização P0:** trocar `openai-whisper` por
  **`faster-whisper` (CTranslate2, int8)** — 3–5× mais rápido, menos RAM, VAD embutido. Isso sobe o
  teto de ~5 para a faixa de 15–20 simultâneos **sem trocar hardware**. §17 detalha.
- **Teto de duração por fala: 5 s** (push-to-talk cap + VAD corta silêncio) → cada STT é curto.
- **Pool opcional:** N workers = N instâncias do modelo, cada uma com poucos threads, dimensionado aos
  núcleos livres (respeitando o baseline do FiveM). Escala horizontal dentro da máquina.

### 10.2 Fila TTS (subprocess isolado — já validado)

- Semáforo limita subprocessos simultâneos. **Para máquina fraca em produção: teto 2–3** (não 16),
  como o dono pediu — geração ao vivo conservadora, cache faz o volume.
- **Cache-first sempre:** só chega no TTS quem deu *miss* real. A resposta cacheada **não** entra aqui.

### 10.3 O contrato "no máximo 2 áudios ao vivo por vez + espera murmúrio"

```
gatilho ─► murmúrio (instantâneo) ──────────────────────────────────┐
                                                                     │ toca já
miss ─► Gemini ─► [FILA TTS: máx 2 slots] ─► WAV ─► pronto ──────────┤
                                                                     ▼
cliente: quando o murmúrio atual TERMINA ─► toca a resposta real (sem corte, sem overlap)
```

Se a fila TTS está cheia, o pedido **espera** com o murmúrio cobrindo — nunca há silêncio, nunca há
duas falas do mesmo NPC ao mesmo tempo. Degradação graciosa por design.


## 11. Fallback Gemini (menor modelo, prompt por NPC, compactação)

Só quando os 3 níveis de intenção deram *miss*.

### 11.1 Decisões e porquês

| Decisão | Por quê |
|---|---|
| **Menor modelo disponível** (classe *flash-lite/8b*) | Latência e custo mínimos; NPC de RP não precisa de raciocínio pesado. |
| **Prompt de sistema por NPC** | Personalidade, vocabulário, domínio e limites fixos e isolados por personagem. |
| **Constante de compactação** ("responda em ≤ N palavras, tom X") | **Duplo ganho:** (1) economiza token; (2) texto curto → TTS curto → fila anda mais rápido, menos gargalo. |
| **Saída estruturada** `{intencao, texto, emocao}` | Permite **cachear por intenção** (auto-evolução) e escolher murmúrio/tom. |
| **Injeção de memória do char** | O NPC "lembra" o que ESTE jogador já disse a ELE (§13), tornando a resposta pessoal. |
| **Fail-closed** | API caiu/limite estourou → murmúrio + fallback genérico cacheado ("não entendi, repete?"). Nunca trava. |

### 11.2 Contrato de prompt (sanitizado)

```
[SYSTEM fixo do NPC]  Você é <nome>, <profissão> em <local>. Fale como <estilo>, vocabulário <...>.
                      Responda em no máximo <N> palavras, em PT-BR, tom <...>. Nunca saia do personagem.
[MEMÓRIA do char]     Fatos que ESTE jogador já te contou: <lista curta>.
[FALA do jogador]     «<texto transcrito, DELIMITADO e escapado>»
[FORMATO]             Devolva JSON: {"intencao": "...", "texto": "...", "emocao": "..."}
```

O texto do jogador é **conteúdo, nunca instrução** — delimitado, e o sistema instrui explicitamente a
ignorar tentativas de mudar as regras (defesa de prompt-injection, §15).

### 11.3 Ligação com a auto-evolução

Toda geração Gemini é: (a) sintetizada em áudio e **salva no cache** sob a intenção retornada;
(b) logada como par `(texto_normalizado → intenção)` para treinar o N3. Da próxima vez, a mesma
intenção resolve no cache (sem Gemini) e frases parecidas passam a bater no N3.


## 12. Auto-evolução (o sistema que aprende sozinho)

```
MISS ─► Gemini gera ─► TTS ─► SALVA áudio no cache (intenção)         ← cresce a cobertura de resposta
                          └─► LOGA (texto_stt → intenção)             ← cresce o dataset do N3
                                        │
         (cron de baixa prioridade, fora do caminho quente) ─► RETREINA N3 por domínio de NPC
                                        │
         próximas falas semelhantes ─► batem no N1/N2/N3 ─► NUNCA mais chamam Gemini para isso
```

Propriedades:
- **Convergência:** quanto mais a cidade joga, menos Gemini é necessário. A curva de custo cai sozinha.
- **Por domínio:** o dataset e o modelo N3 são **por profissão/NPC** — o mecânico não polui o médico.
- **Seguro:** só vira treino aquilo que passou pelos filtros de §15 (sem PII bruta, sem injeção).
- **Reversível:** cada entrada de cache/treino é versionada; um item ruim pode ser podado sem re-deploy.


## 13. Memória progressiva por personagem (isolada por NPC)

### 13.1 O requisito exato do dono

> "se o char1 fala com a Rebeca que gosta de fusca, o Jorjão nunca vai saber disso; se o char1 fala
> para o Marcus que tem medo de polícia, o Carvalho nunca vai saber — a menos que o próprio char1 conte."

Ou seja: **memória por par (char_id × npc_id)**, estritamente isolada. Nada vaza entre NPCs.

### 13.2 Modelo de dados (dono = `vhub_npcai`, um escritor — L-13)

Tabela dedicada (regras SQL do manual §3.6): FK ao core `INT UNSIGNED` CASCADE.

```sql
CREATE TABLE IF NOT EXISTS vhub_npcai_memory (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  char_id    INT UNSIGNED NOT NULL,               -- FK vh_characters.id (CASCADE)
  npc_id     VARCHAR(48)  NOT NULL,               -- 'marcus','rebeca','carvalho','jorjao'
  mkey       VARCHAR(64)  NOT NULL,               -- 'gosta_de','medo_de','ultimo_servico'...
  mval       VARCHAR(255) NOT NULL,               -- valor curto (fato)
  weight     SMALLINT     NOT NULL DEFAULT 1,     -- relevância / recência
  updated_at TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mem (char_id, npc_id, mkey),
  KEY idx_lookup (char_id, npc_id),
  CONSTRAINT fk_mem_char FOREIGN KEY (char_id)
     REFERENCES vh_characters(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

- **Isolamento garantido pela PK/UNIQUE** `(char_id, npc_id, mkey)`: a leitura para o prompt do
  Marcus filtra `npc_id='marcus'` — é fisicamente impossível o Carvalho ler a memória do Marcus.
- **Escrita:** só quando o char *conta algo relevante* (extraído da intenção/Gemini) — não a cada fala.
- **Leitura no caminho quente:** cacheada em VRAM (KV do core / dict do sidecar), invalidada em update
  e em `playerDropped`. Sem round-trip SQL síncrono na conversa (manual §4.3).
- **Quem extrai o "fato":** o Gemini (saída estruturada) ou uma regra N2 ("eu gosto de X" → `gosta_de=X`).
  O **server valida e persiste** (L-01) — a memória é verdade do servidor, não do cliente.

### 13.3 Custo e escala

Memória é **por interação relevante**, não por tick. Leitura O(1) por conversa (índice
`(char_id, npc_id)`). Não há loop varrendo players. Cabe no orçamento.


## 14. Os quatro NPCs de exemplo

> Servem de **molde**: mostram como personalidade, vocabulário, gatilhos, ações e memória mudam por
> NPC. Marcus é o mais detalhado (é o pedido do dono para colocar no mundo). Nenhum é implementado
> aqui — são fichas de design + config.

### 14.1 Marcus — vendedor de carros da Motorsport

| Campo | Valor |
|---|---|
| **Ped** | `s_m_m_highsec_01` |
| **Posição** | `vec3(-56.5367, -1098.6465, 26.4223)` (Motorsport) |
| **Raio de conversa** | 10 m |
| **Idioma** | pt |
| **História** | Marcus é o vendedor-estrela da Motorsport. Ex-piloto de arrancada que trocou a pista pelo showroom depois de um acidente. Fala rápido, simpático, sempre puxando pro fechamento — mas honesto sobre o que o carro aguenta. Conhece cada modelo do pátio de cor. |
| **Tom / vocabulário** | Vendedor carismático: "chefia", "essa belezinha", "sai rodando hoje", "tô te fazendo um preço de amigo". |
| **Intenções principais** | `saudacao`, `perguntar_preco`, `ver_modelo`, `test_drive`, `negociar`, `fechar_compra`, `financiamento`, `despedida`. |
| **Gatilhos saudação** | e aí, salve, bom dia, opa, fala Marcus, tudo bem. |
| **Gatilhos profissão** | carro, preço, quanto, comprar, ver, modelo, test drive, financiar, desconto, tabela, esportivo, pátio. |
| **Ações (contrato futuro c/ dono do ped/loja)** | destacar veículo no showroom, abrir catálogo NUI, encaminhar para `vhub_conce` (compra real). **Marcus só conversa; a compra é do `vhub_conce`** (L-04). |
| **Memória típica** | `gosta_de=<modelo>`, `orcamento=<faixa>`, `ja_comprou=<placa>`, `medo_de=policia`. |
| **Exemplo** | "e aí Marcus, quanto tá aquele esportivo?" → N2 `perguntar_preco`+slot modelo → cache `marcus/preco__esportivo` = "Opa chefia, essa belezinha sai por um precinho de amigo, bora ver de perto?" |

### 14.2 Rebeca — médica no hospital

| Campo | Valor |
|---|---|
| **Ped** | (a definir — ex.: `s_f_y_scrubs_01`) |
| **Posição** | (a definir — recepção do hospital) |
| **História** | Plantonista calma e objetiva. Já viu de tudo, não se assusta com bala nem com desculpa esfarrapada. Trata com cuidado, mas manda a real. |
| **Tom / vocabulário** | Profissional acolhedor: "respira fundo", "deixa eu ver esse machucado", "vai ficar tudo bem", "toma cuidado lá fora". |
| **Intenções** | `saudacao`, `pedir_atendimento`, `curar`, `perguntar_sintoma`, `orientacao`, `despedida`. |
| **Gatilhos profissão** | dói, machuquei, remédio, curar, sangue, ferido, atende, doutora, ajuda, hospital. |
| **Ações (contrato futuro)** | encaminhar cura para o dono do sistema médico / `vhub_hss:setHealth` **via contrato** — Rebeca não escreve HP direto. |
| **Memória típica** | `alergia=<x>`, `ultimo_atendimento=<data>`, `tipo_sanguineo=<x>`. |

### 14.3 Carvalho — policial

| Campo | Valor |
|---|---|
| **História** | Veterano da corporação, durão mas justo. Desconfiado por ofício. Odeia mentira e adora um papo reto. |
| **Tom / vocabulário** | Autoridade seca: "documento na mão", "circulando", "tá me achando com cara de otário?", "colabora que é melhor pra você". |
| **Intenções** | `saudacao`, `denunciar`, `perguntar_procurado`, `pedir_ajuda`, `provocar` (→ resposta ríspida), `despedida`. |
| **Gatilhos profissão** | polícia, denúncia, roubaram, procurado, ajuda, delegacia, boletim, suspeito, documento. |
| **Isolamento de memória (o exemplo do dono)** | Se o char contou ao Marcus que "tem medo de polícia", **Carvalho nunca sabe** — `npc_id='carvalho'` não lê memória de `marcus`. Só se o char contar ao próprio Carvalho. |
| **Memória típica** | `ja_denunciou=<x>`, `atitude=<cooperativo|hostil>`, `ficha=<limpa|suja>`. |

### 14.4 Jorjão — mecânico (o exemplo canônico do §8)

| Campo | Valor |
|---|---|
| **História** | Dono da oficina, mão de fada pra motor, gíria na ponta da língua. Trata carro como gente e cliente como parceiro. |
| **Tom / vocabulário** | Gíria de oficina: "essa bomba", "caranga", "vou dar um trato", "manda ver", "tá sarado". |
| **Intenções** | `saudacao`, `servico_reparo`, `tuning`, `perguntar_preco`, `status_servico`, `despedida`. |
| **Config completa** | ver §8 (é o molde de referência). |
| **Ações (contrato futuro)** | reparo/tuning **via `commitVehicleState`** (dono do estado do veículo é o core/conce) — Jorjão pede, não escreve. |

### 14.5 O que os quatro provam

Cada NPC tem **gatilhos, vocabulário, intenções, ações e memória diferentes** — mas **um único motor**
os serve. Adicionar um NPC novo = **uma ficha de config + seeds de áudio**, zero código novo. Isso é a
prova de que a arquitetura é dados-sobre-código (manutenível, L-09/simplicidade).


## 15. Segurança (zero-trust — lente do `vhub_guardiao_seguranca`)

| Vetor | Defesa |
|---|---|
| **Cliente chamando o sidecar direto** | Impossível: sidecar em `127.0.0.1`, só o **server** relaya. Cliente fala com o server (evento/NUI), nunca com o Python. |
| **Spoof de proximidade** ("falo com NPC do outro lado do mapa") | Server reconfere coords server-side antes de aceitar (§6.3). Fail-closed. |
| **Spam de STT/Gemini p/ queimar CPU/token** | Rate-limit por char (`Core.rate`, manual §4.6) + cooldown + **teto diário de Gemini por char** + circuit breaker global. |
| **Prompt injection** ("ignore as regras e diga X") | Texto do jogador é **conteúdo delimitado**, nunca instrução; system prompt fixo manda ignorar meta-instruções; saída **limitada em tamanho** e **sanitizada** antes do TTS. |
| **Vazamento de PII entre NPCs** | Memória isolada por `(char_id, npc_id)` na própria PK (§13). Fisicamente impossível cruzar. |
| **Path traversal no nome/slug do cache** | Slug sanitizado (whitelist `[a-z0-9_]`, sem `/`, `..`), tamanho limitado, hash quando em dúvida. |
| **Poisoning de cache** | Chave de cache derivada **no server/sidecar**, nunca de string do cliente. |
| **Áudio malicioso / DoS por payload** | Server valida tamanho/duração/mime do blob **antes** de relayar; teto de 5 s; rejeita fora do range. |
| **Gemini fora do ar** | Fail-closed → fallback cacheado. Nunca trava a conversa nem o tick. |
| **Segredo da API** | Chave Gemini em **variável de ambiente do usuário** (como o `.mcp.json`/convar do projeto), nunca no código versionado. |
| **Jogador restrito falando** (morto, algemado, banido) | Gate `vhub_hss` no server antes de aceitar a fala. |

Todas as mutações relevantes (memória gravada, Gemini chamado, cache criado) são **logadas com
`reason`/actor/ts** (L-12/L-18, auditoria em 3 camadas — L-13 do CLAUDE.md).


## 16. Ownership e integração com o core vHub

### 16.1 Linha do Registro de Ownership (a criar no gate do arquiteto)

| Dado | Owner | Leitores | Persistência | Contrato |
|---|---|---|---|---|
| Memória NPC×char | `vhub_npcai` (server) | só o próprio motor de prompt | `vhub_npcai_memory` (SQL) | export read-only `getNpcMemory(char,npc)` |
| Config de NPC (gatilhos, tom, coords) | `vhub_npcai` (config) | client (proximidade), sidecar (intenção) | arquivo config + seeds | recarregável |
| Cache de áudio | sidecar (filesystem) | sidecar | `audio_cache/` (LRU) | interno do sidecar |
| Sessão de conversa | `vhub_npcai` (server, por src) | — | VRAM, limpa em `playerDropped` | — |

### 16.2 O que o resource NÃO possui (peça, não escreva)

- **Ped** → `vhub_hss` (spawn, teleport, anim, HP). Marcus/Rebeca/etc. são fichas; o controle é do HSS.
- **Estado de veículo** (reparo do Jorjão) → `commitVehicleState` (core/conce).
- **HP** (cura da Rebeca) → contrato do dono do sistema médico / `vhub_hss:setHealth`.
- **Compra de carro** (Marcus) → `vhub_conce`. Marcus **conversa**, o conce **vende**.
- **Dinheiro** → exports do `vhub_money`.

### 16.3 Export-first (convenção do dono)

Todo o público do `vhub_npcai` nasce como export **gated default-deny** (`_invoker_allowed` +
`GetInvokingResource`), mesmo sem consumidor hoje: `getNpcMemory`, `setNpcMemory` (via contrato
interno), `listNpcs`, `reloadNpcConfig`. Assim outro resource pluga regra sem gambiarra (manual §3.7).

### 16.4 Ciclo de vida (L-07)

- **Boot:** sidecar sobe (`start_whisper.bat`), server aplica schema idempotente, carrega config,
  pré-aquece cache (seeds), registra replay-guard nos handlers institucionais (L-17).
- **`vHub:characterLoad`:** abre sessão, pré-gera `name_cache` do char (opcional, ocioso).
- **`playerDropped`:** limpa sessão/rate/cache-VRAM por src (sem leak — manual §4.6).


## 17. Orçamentos e a doutrina de escala

### 17.1 Por que 500 players não derrubam o servidor

A carga pesada (STT, intenção, TTS, Gemini) roda **no processo Python**, **fora do tick do FX Server**.
O resource Lua só faz: medir distância local (cliente), validar/relayar (server), tocar WAV (cliente).
Isso é **O(1) por interação** e **zero por player ocioso**. O FX tick nunca vê a IA.

| Componente | Orçamento | Como cumpre |
|---|---|---|
| Client idle (longe de NPC) | 0,00 ms | thread fria 1 Hz; quente só perto (manual §4.1) |
| Client ativo (perto) | ≤ 0,05 ms | desenha "[E]" + arma push-to-talk; sem loop 0 constante |
| Server por fala | O(1) | valida + 1 POST loopback; sem varrer players |
| FX tick pela IA | ~0 ms | IA é sidecar externo |
| Sidecar CPU | limitado por pool/semáforo | teto de workers STT + teto 2–3 TTS ao vivo |

### 17.2 O caminho para "20 ao vivo em máquina fraca"

Ordem de implementação por impacto (P0 → P2):

1. **P0 — `faster-whisper` int8 + VAD** (substitui `openai-whisper`): 3–5× throughput, menos RAM. É o
   maior salto (de ~5 para ~15–20) e **não custa hardware**.
2. **P0 — teto de 5 s por fala + push-to-talk:** cada STT curto; VAD remove silêncio.
3. **P1 — cache-first agressivo:** 80%+ das respostas sem TTS/Gemini → a fila ao vivo quase vazia.
4. **P1 — pool de workers STT** dimensionado aos núcleos livres (respeitando baseline FiveM).
5. **P2 — modelo `tiny` para primeira passada de intenção**, escalando para `base` só quando preciso.

**Degradação graciosa** enquanto não maduro: acima do teto, murmúrio + "peraí" segura o jogador; nunca
trava. Isto é o que permite **prometer 5 hoje e mirar 20** sem mentir (§3).


## 18. Gaps e lacunas identificados + soluções

> Seção perfeccionista: cada risco previsto **antes** de escrever código.

| # | Gap / risco | Solução adotada |
|---|---|---|
| 1 | **Transporte de mic no FiveM** (como o áudio chega ao server) | Push-to-talk → NUI `MediaRecorder` → NUI callback → server → sidecar. Integra com `vhub_voicePMA` (contrato mínimo aqui). |
| 2 | **STT é o teto real** (cache não remove STT) | `faster-whisper` + VAD + cap 5 s + pool (§17). |
| 3 | **Grupo vs privado** | Fala é de 1 falante; lock de fala por NPC; áudio espacial dá privacidade emergente (§6.4). |
| 4 | **Falantes concorrentes ao mesmo NPC** | Micro-fila por NPC + murmúrio "peraí"; nunca vozes sobrepostas (§10.3). |
| 5 | **Cold start (cache vazio)** | Seeds no deploy: murmúrios/saudações/respostas comuns pré-gravadas (§9.5). |
| 6 | **Erro de STT (gíria, nome)** | `initial_prompt` enviesado + fuzzy match + N3 treinado na saída real do STT (§7.5). |
| 7 | **Silêncio constrangedor** | Murmúrio instantâneo antes da geração (§5/§9). |
| 8 | **Gemini fora do ar / rate limit** | Circuit breaker + fallback cacheado, fail-closed (§11/§15). |
| 9 | **Idioma (pt/en)** | Idioma por NPC na config; detecção como fallback. |
| 10 | **Disco do cache cresce** | Dedup por hash + LRU com teto por NPC (§9.5). |
| 11 | **Nome de char exótico no TTS** | Sanitização + geração 1× + cache; slug seguro (§9.3/§15). |
| 12 | **Muitas vozes de NPC num aglomerado** | Áudio espacial + limite de talkers simultâneos por área. |
| 13 | **Chave de cache não-determinística** | Nome como slot; chave = hash(npc+intenção+variante+idioma) (§9.4). |
| 14 | **Abuso p/ queimar token/CPU** | Rate + cooldown + teto diário Gemini + circuit breaker (§15). |
| 15 | **Config quente de NPC** | Config dados-sobre-código, recarregável via export gated (§16.3). |
| 16 | **Prompt injection** | Texto como conteúdo delimitado + saída limitada e sanitizada (§11.2/§15). |
| 17 | **PII cruzando NPCs** | Isolamento por PK `(char_id, npc_id)` (§13). |
| 18 | **Lip-sync / ação do ped** | Fora de escopo; contrato com `vhub_hss` na fase futura (§1.3/§16.2). |


## 19. Estrutura de arquivos, schema e config

### 19.1 Árvore do resource (padrão do manual §1)

```
resources/[SCRIPTS]/vhub_npcai/
├── shared/
│   ├── config.lua          ← NPCs (coords vec3, raio, idioma), rates, limiares
│   ├── events.lua          ← VHubNpcAI.E.* (global, sem return)
│   └── utils.lua           ← normalização de texto, slug seguro (puros)
├── server/
│   ├── sql.lua             ← queries via exports.oxmysql (memória)
│   ├── core.lua            ← sessões, hasPerm, rate (§4.6), gate HSS
│   ├── init.lua            ← schema idempotente, replay-guard, seeds
│   ├── relay.lua           ← ponte server → sidecar (HTTP loopback, pcall)
│   ├── memory.lua          ← dono da memória (escritor único, L-13)
│   └── exports.lua         ← API pública gated (getNpcMemory, listNpcs, reload)
├── client/
│   ├── init.lua            ← estado local, NUI focus
│   ├── proximity.lua       ← thread fria/quente, "[E] falar" (§4.1)
│   ├── mic.lua             ← push-to-talk, MediaRecorder, envia blob
│   └── playback.lua        ← toca WAV recebido (spatial), fila local por NPC
├── nui/                    ← indicador "[E]", legenda, VU (opcional, tema vHub)
├── sql/
│   └── schema.sql          ← vhub_npcai_memory (§13.2)
├── sidecar/                ← Python (já existe server.py; motor novo aqui)
│   ├── server.py           ← STT/TTS (feito) + /converse (novo)
│   ├── intent.py           ← 3 níveis + escalada + auto-evolução
│   ├── cache.py            ← stitch, chave, dedup, LRU, name_cache
│   ├── gemini.py           ← fallback, prompt por NPC, compactação, circuit breaker
│   └── npcs/               ← fichas + seeds de áudio por NPC
├── audio_cache/            ← gerado em runtime (LRU) — no .gitignore
├── start_whisper.bat       ← sobe o sidecar
├── plano_npcai.md          ← este documento
└── fxmanifest.lua
```

> Cada `.lua` entra no `fxmanifest.lua` **no mesmo commit** (L-15). O Python **não** é resource FiveM
> — é sidecar externo declarado no `start_whisper.bat` e documentado aqui.

### 19.2 Contrato HTTP server↔sidecar (loopback)

```
POST /converse   { char_id, char_name, npc_id, lang, audio(base64|multipart) }
  → 200 { ok, stage: 'cache'|'gemini', intent, audio(wav base64), murmur(wav base64), memory_delta? }
  → 200 { ok:false, reason }   (fail-closed → server usa fallback local)
```
Endpoints atuais (`/transcribe`, `/speak`, `/health`) permanecem para teste. `/converse` orquestra o
pipeline §5. Server envolve tudo em `pcall`/timeout — sidecar lento nunca prende o tick.

### 19.3 Config de NPC (esqueleto — dados-sobre-código)

Ver §8 (Jorjão completo) e §14 (Marcus/Rebeca/Carvalho). Cada NPC: `id, nome, profissao, idioma,
coords(vec3), raio, gatilhos_saudacao[], gatilhos_profissao[], intencoes{regex,slots}, respostas{},
murmurios[], transicoes[], conf_min{n1,n2,n3}, memoria_keys[]`.


## 20. Roadmap faseado + gates de governança

> Cada fase é um PR; cada PR passa os gates nomeados **antes** do merge (fluxo multi-agente do CLAUDE.md).
> Nenhuma fase toca o CORE (`[CORE]/vhub`) — só consome exports. Se alguma vier a tocar, exige ADR + bump.

| Fase | Entrega | Gates obrigatórios |
|---|---|---|
| **F0 — Motor de voz** *(FEITO)* | STT serial + TTS subprocess, 0 erros, benchmark | — (validado nesta sessão) |
| **F1 — Otimizar STT** | `faster-whisper` int8 + VAD + cap 5 s + pool | `performance` (orçamento), `simplicidade` |
| **F2 — Intenção N1+N2** | keywords + regex+contexto + escada; cache + stitch; murmúrio | `arquiteto` (ownership/linha do Registro), `contrato` (exports), `performance` |
| **F3 — Cache + montagem + name_cache** | dedup/LRU, saudação+nome+corpo, seeds | `natives` (áudio/entidade no client), `designer` (se NUI), `performance` |
| **F4 — Memória por char×NPC** | schema + escritor único + injeção no prompt | `persistencia` (L-13, schema, FK), `seguranca` (isolamento PII) |
| **F5 — Gemini fallback** | menor modelo, prompt/NPC, compactação, circuit breaker | `seguranca` (injeção, segredo, rate), `contrato` |
| **F6 — Intenção N3 + auto-evolução** | TF-IDF/SVM por domínio, retrain cron, log→treino | `simplicidade` (não inflar), `performance` (fora do quente) |
| **F7 — Proximidade + mic + playback** | threads fria/quente, push-to-talk, spatial | `natives` (ped/spatial), `seguranca` (proximidade server), `designer` |
| **F8 — NPCs de exemplo no mundo** | Marcus (+Rebeca/Carvalho/Jorjão) fichas+seeds | `arquiteto`, `guardiao_revisao` (gate final + contexto.md) |
| **F9 — Integração de ações** | contratos com `vhub_hss`/`vhub_conce`/médico | `contrato`, `arquiteto` |

**Gate final de cada fase:** `vhub_guardiao_revisao` (DoD do manual §6 + escrita no `contexto.md`).

---

### Resumo em uma linha

> **"A voz do jogador sempre custa STT; a voz do NPC quase nunca custa nada. Cacheia o que repete,
> gera só o que é novo, lembra por NPC sem vazar, e mantém toda a IA fora do tick do FiveM — o server
> decide, o cliente executa, e nada trava: no pior caso, o NPC dá um 'peraí' e segue o baile."**

— Plano `vhub_npcai` — vHub Mirage — v1.0 (design) — 2026-07-27







Remover npc do mundo e barcos e trens com opção de ajustar transito do mundo.


Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        -- Desativa o trânsito de veículos
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
        
        -- Desativa pedestres/NPCs
        SetPedDensityMultiplierThisFrame(0.0)
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        
        -- Remove barcos e trens aleatórios
        SetRandomBoats(false)
        SetGarbageTrucks(false)
    end
end)

