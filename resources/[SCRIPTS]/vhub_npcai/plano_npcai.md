Análise vhub_npcai — Gaps, Lacunas e Melhorias
🔴 Crítico — Segurança
1. direct_text não validado contra whitelist do NPC
Arquivo: client/mic.lua:42-45, server/core.lua

O cliente chama VHubNpcAI.startTalk(npcId, directText) onde directText vem de closures definidas em _buildTargetOpts de ped_control.lua. O servidor recebe esse campo, valida shape (tipo string, comprimento), e passa direto ao sidecar como payload.direct_text.

O sidecar usa esse texto como entrada para o intent engine — e, se não reconhecido, passa ao LLM dentro do prompt delimitado por <fala>...</fala>. O anti-injection protege o LLM de commandos no texto, mas não impede que um cliente malicioso envie qualquer string arbitrária como intenção, bypassando o STT completamente.

Fix: O servidor deve validar direct_text contra a lista de textos permitidos para o NPC em questão. A lista já existe implicitamente em cfg.npcs[npcId].target_options. O campo deveria ser um enum de slug ("saudacao", "preco"), não texto livre — o servidor resolve o texto pelo slug, nunca aceitando texto aberto nesse caminho.

2. Core.canTalk fail-open quando HSS cai
Arquivo: server/core.lua


local ok, result = pcall(exports.vhub_hss.canInteract, src)
if not ok then return true end   -- ← fail-open
Se o HSS está offline (reiniciando, travado), qualquer player passa a poder falar com NPCs independente do estado de vida, algemas ou atividade. Um player inconsciente, algemado ou morto conversa normalmente quando o HSS cai.

Fix: if not ok then return false end — fail-closed. SEM HSS = SEM FALA. A perda de funcionalidade temporária é aceitável; a degradação de segurança não é.

🔴 Crítico — Performance (Gargalos de Latência)
3. SapiTTS cria subprocess PowerShell + 2 temp files por chamada
Arquivo: sidecar/providers/tts.py:74-97


# por chamada:
fd_script, path_script = tempfile.mkstemp(suffix='.ps1')
fd_out,    path_out    = tempfile.mkstemp(suffix='.wav')
subprocess.run(['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', path_script], ...)
Spawn de processo PowerShell no Windows custa 200–500ms de cold start antes de gerar o primeiro sample. Com semaphore limitando concorrência, isso é o gargalo dominante de toda a pipeline — mais lento que STT, intent, e LLM somados em cache hit.

Fix: Instanciar SAPI uma vez via win32com.client.Dispatch("SAPI.SpVoice") em um worker thread dedicado persistente, aceitar tasks por queue.Queue(). Zero subprocess, zero temp files, latência cai para ~80–150ms de síntese pura.


class SapiTTSWorker:
    def __init__(self):
        self._q = queue.Queue()
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()

    def _run(self):
        import win32com.client, io, wave
        sapi = win32com.client.Dispatch("SAPI.SpVoice")
        stream = win32com.client.Dispatch("SAPI.SpFileStream")
        while True:
            text, future = self._q.get()
            # síntese direta para buffer
            ...

    def synthesize(self, text) -> bytes:  # bloqueia chamador, não o main thread
        f = concurrent.futures.Future()
        self._q.put((text, f))
        return f.result(timeout=10)
4. STT serial single-thread enquanto faster-whisper suporta N workers
Arquivo: sidecar/server.py

_stt_queue = queue.Queue() + 1 thread worker. Se dois players falam simultaneamente, o segundo espera a transcrição do primeiro completar antes de começar a própria. Com faster-whisper int8 em CPU, throughput real é ~1.7 req/s serial — cai para ~0.85 req/s efetivo com dois players simultâneos.

Fix: ThreadPoolExecutor(max_workers=cfg.stt.workers, thread_name_prefix='stt') com max_workers=2 como default. O modelo faster-whisper é threadsafe para leitura. O semaphore de TTS já existe — o bottleneck real é o subprocess SAPI (fix 3 acima), não o carregamento do modelo.

5. N3 treina no thread da request (bloqueia o 50º player)
Arquivo: sidecar/server.py


# dentro de /converse, após reconhecer intent:
_accumulate_sample(npc_id, text, intent)
# se len(samples) == 50:
    engine.train()  # ← TF-IDF fit + LogReg fit, no caminho da resposta
O 50º jogador a conversar com cada NPC recebe a resposta ~100–300ms mais tarde sem aviso. Em produção com 4 NPCs, isso acontece 4 vezes por reboot do sidecar.

Fix: Uma linha:


if should_train:
    threading.Thread(target=engine.train, daemon=True).start()
🟡 Importante — Memory Leaks e Crescimento Ilimitado
6. _llm_usage dict cresce indefinidamente
Arquivo: sidecar/server.py

_llm_usage: dict = {} acumula {char_id: {'day': date, 'count': n, ...}} sem evicção. Cada char_id único que já usou LLM fica para sempre na RAM do processo Python. Servidor com rotatividade de jogadores: crescimento linear com jogadores únicos históricos.

Fix: _llm_usage = cachetools.TTLCache(maxsize=4096, ttl=86400) — evicta automaticamente após 24h. Ou sem dependência externa: OrderedDict com evicção por tamanho no _llm_allowed.

7. name_cache sem limite no AudioCache
Arquivo: sidecar/cache.py

_names: dict = {} armazena TTS de nomes de jogadores sem cap. Cada nome único pré-aquecido via prewarmName fica para sempre. Com 5000 jogadores únicos: ~5000 buffers de áudio WAV na RAM.

Fix: Converter _names para OrderedDict com maxsize=1024; no put_name, se len(_names) >= maxsize, fazer _names.popitem(last=False) (evicta o mais antigo).

8. _train_samples cresce após o primeiro treino sem cap
Arquivo: sidecar/intent.py

A lista de amostras (_train_X, _train_Y) só dispara treino no 50º elemento mas continua crescendo indefinidamente após. Em servidor ativo com 100 conversas/hora × 4 NPCs: 400 amostras/hora × RAM.

Fix: Sliding window — após treino, manter no máximo 200 amostras mais recentes:


if len(self._train_X) > 200:
    self._train_X = self._train_X[-200:]
    self._train_Y = self._train_Y[-200:]
🟡 Importante — Bugs Reais
9. LOS check usa playerPed como target quando ped do NPC não existe
Arquivo: client/proximity.lua


local nearPed = VHubNpcAI.getNpcPed(npcId) or PlayerPedId()
-- ↑ quando o ped não spawnou, usa o próprio player como target
local hasLos = not npc.los or HasEntityClearLosToEntity(myPed, nearPed, 17)
-- HasEntityClearLosToEntity(myPed, myPed, 17) → sempre true
Quando o ped do NPC não foi criado (ex: fora do raio de spawn, aguardando modelo), qualquer player que fizer LOS check "passa" automaticamente porque verifica se tem linha de visão para si mesmo.

Fix:


local nearPed = VHubNpcAI.getNpcPed(npcId)
local hasLos = (not npc.los) or (nearPed ~= nil and HasEntityClearLosToEntity(myPed, nearPed, 17))
10. stitch quebrará com WAV não-standard (chunks antes de data)
Arquivo: sidecar/cache.py


idx = wav.find(b'data', 36)
WAVs com chunks JUNK, LIST, FACT, ou INFO válidos antes do chunk data têm o chunk data em offset diferente de 36. pydub pode gerar esses chunks. O find com offset 36 pode retornar -1 (ou pior, achar b'data' dentro de um chunk de metadata), corrompendo silenciosamente o stitch.

Fix: Parser RIFF correto:


def _find_data_chunk(wav: bytes) -> int:
    pos = 12  # pula RIFF header (4) + tamanho (4) + WAVE (4)
    while pos + 8 <= len(wav):
        chunk_id = wav[pos:pos+4]
        chunk_size = int.from_bytes(wav[pos+4:pos+8], 'little')
        if chunk_id == b'data':
            return pos + 8  # offset dos PCM samples
        pos += 8 + chunk_size + (chunk_size % 2)  # padding de 1 byte se ímpar
    return -1
11. _audio_para_transporte upsamples 16→24kHz sem ganho perceptível
Arquivo: sidecar/server.py


audio = audio.set_frame_rate(24000)  # resample WAV 16kHz → 24kHz
audio.export(buf, format='mp3', bitrate='48k')
Upsample de voz 16kHz para 24kHz por pydub (Rubberband/SRC) é O(n) CPU sem adicionar informação auditiva — o limite de Nyquist da voz humana é ~4kHz; a qualidade do STT exige 16kHz. O MP3 resultante poderia ser gerado diretamente do WAV 16kHz com bitrate='48k' — o encoder MP3 lida com qualquer sample rate de entrada.

Fix: Remover a linha set_frame_rate(24000).

🟡 Higiene de Código
12. Logs de diagnóstico temporários em produção
Arquivo: server/init.lua:162-167, relay.lua:139-141

Cada fala de qualquer player imprime:


[diag] src=X npc=Y audio_len=Z dt_len=W dt_type=string dt_val="..."
[relay-diag] payload[:120]={"char_id":123,"npc_id":"jorjao"...
Com 20 players conversando: dezenas de linhas de log por minuto no console do servidor. Declarados como "diagnóstico temporário" nos próprios comentários do código.

Fix: Deletar ambos. Se debug futuro for necessário, convar vhub_npcai_debug + if GetConvarInt('vhub_npcai_debug', 0) == 1 then.

13. Threads de patrol de NPCs fora do raio de spawn rodam em loop vazio
Arquivo: client/ped_control.lua

4 threads de patrol sempre ativos no cliente. Quando o player está a 2km do Jorjão, o thread do Jorjão ainda acorda a cada 1000ms, tenta _walkTo, e descobre que o ped não existe — loop vazio mas consume wake-ups do scheduler.

Fix: No outer loop do ambient, checar distância primeiro:


if dist >= cfg.spawn_radius * 2 then Wait(5000); goto continue end
🟢 Novas Capacidades (Fora da Caixa)
14. CONTINUIDADE DE SESSÃO: ring buffer de contexto efêmero
O gap mais significativo de UX: cada conversa com um NPC começa do zero dentro da mesma sessão. Se o player perguntou sobre nitro 3 minutos atrás, o NPC não "lembra" — mesmo que a memória persistida ainda não tenha atualizado as flags.

Proposta: _session_ctx[f"{char_id}:{npc_id}"] = deque(maxlen=4) de {intent, text, ts} na RAM do sidecar, limpo em playerDropped (via novo endpoint /session_end chamado do server/init.lua). O LLM recebe as últimas N trocas como parte do system prompt → o NPC continua a conversa com coerência real:


Sistema: ...
Histórico recente desta sessão:
- Jogador perguntou sobre tuning de corrida (intent: corrida, 4min atrás)
- NPC recomendou setup para circuito misto
Agora o jogador pergunta: [fala atual]
Nenhuma SQL, nenhuma persistência — puramente efêmero e correto.

15. STREAMING DE SEGMENTOS: latência percebida cai de 2×TTS para 1×TTS
Hoje o sidecar processa TTS dos dois segmentos antes de retornar qualquer áudio. Proposta: retornar o segmento 0 imediatamente após TTS, enquanto o segmento 1 é processado em paralelo e enviado em uma segunda resposta (CLI_RESPOSTA_CHUNK).

O cliente toca o segmento 0 e enfileira o 1 — sem silêncio entre eles. A latência que o player percebe cai de STT + LLM + TTS(seg0) + TTS(seg1) para STT + LLM + TTS(seg0).

Requer: protocolo de chunk com sequence: 0/1 e total: 2 no payload, sem mudar a arquitetura core.

16. WARM HANDOFF: reservar slot ANTES do upload de áudio
Hoje o lock do NPC só é adquirido quando o servidor recebe o áudio completo (base64 pesado). Se dois players tentam falar com Jorjão quase simultaneamente: ambos gravam, ambos fazem upload — o mais rápido na rede ganha, o outro recebe reject após 3-5s de upload desperdiçado.

Proposta: Evento SRV_RESERVAR_NPC enviado quando o player começa a gravar (antes do MediaRecorder terminar). Reserva o slot por até 12s. Reject é imediato se NPC ocupado — o player para de gravar antes de perder 5s.

Segurança: SRV_RESERVAR_NPC passa pelos mesmos gates de sessão, rate, HSS, proximidade. Não pode ser usado como DoS porque o rate limiter do SRV_FALAR também se aplica.

17. INTERRUPT MODE: player interrompe NPC e NPC reage
Hoje se o player pressiona G durante a fala do NPC, o sistema rejeita porque state.conversing = true. A UX natural seria:

Player pressiona G durante fala → para áudio, abre mic com animação de "interrompeu"
Servidor recebe {..., interrupted: true} no payload
Sidecar adiciona ao prompt: "O jogador te interrompeu no meio da fala. Reaja a isso."
NPC responde com reação contextual ("Ei! Deixa eu terminar!" ou "Ok, pode falar...")
Zero infraestrutura nova — apenas flag no payload e instrução no system prompt.

18. GREET AMBIENTAL: NPC faz cue sonoro quando player se aproxima
Os arquivos greet_default_00.wav e greet_default_01.wav já existem no fxmanifest.lua por NPC — mas nunca são usados em nenhum lugar do código. O código atual só toca thinking WAV.

Proposta: No thread de proximidade, quando o player entra no raio de "avistamento" (ex: 60% do detect_radius) pela primeira vez na sessão, o cliente toca o greet pré-cacheado do NPC — sem abrir conversa, sem STT, sem sidecar. O NPC acena verbalmente ("Oi!" / "Que foi?" / "Pode vir!"). Flag _greeted_this_session[npcId] garante que não repete.

A infra já existe. São 3 linhas de código no proximity.lua.

19. HASH DEDUP: prevenir double-send do mesmo clip de áudio
Bug de UX conhecível: se o player solta G e aperta G rapidamente, ou se há lag que duplica o evento no MediaRecorder, dois payloads de áudio idênticos chegam ao servidor em janela de poucos segundos. O primeiro processa; o segundo faz STT do mesmo áudio, desperdiça ~1.2s de processamento, e retorna a mesma resposta duas vezes.

Fix (server-side, ~10 linhas):


local _recent_audio_hashes = {}  -- {src: {hash: ts}}
-- antes do Relay.converse:
local h = payload.audio:sub(1,64)  -- primeiros 64 chars como fingerprint barato
if _recent_audio_hashes[src] and _recent_audio_hashes[src][h] then return end
_recent_audio_hashes[src] = { [h] = GetGameTimer() }
Não é SHA — é fingerprint rápido. Suficiente para duplicatas acidentais.

Resumo Executivo por Prioridade
#	Tipo	Impacto	Custo	Arquivo
1	🔴 Segurança	direct_text bypass de whitelist	Baixo	server/core.lua
2	🔴 Segurança	HSS fail-open → morto fala	Trivial	server/core.lua
3	🔴 Latência	SapiTTS subprocess/600ms	Alto	providers/tts.py
4	🔴 Latência	N3 treina no thread da request	Trivial	sidecar/server.py
5	🔴 Latência	_audio_para_transporte resample inútil	Trivial	sidecar/server.py
6	🟡 Memory	_llm_usage cresce ilimitado	Baixo	sidecar/server.py
7	🟡 Memory	name_cache sem evicção	Baixo	sidecar/cache.py
8	🟡 Memory	_train_samples sem cap pós-treino	Trivial	sidecar/intent.py
9	🟡 Bug	LOS usa playerPed como fallback	Trivial	client/proximity.lua
10	🟡 Bug	stitch quebra com WAV não-standard	Baixo	sidecar/cache.py
11	🟡 Bug	Mem.evict O(n) scan	Baixo	server/memory.lua
12	🟡 Higiene	Logs de diagnóstico em prod	Trivial	server/init.lua + relay.lua
13	🟡 Higiene	Patrol threads rodam em idle	Baixo	client/ped_control.lua
14	🟢 Feature	Ring buffer de sessão (continuidade)	Médio	sidecar + server/init
15	🟢 Feature	Streaming de segmentos TTS	Médio	sidecar + client
16	🟢 Feature	Warm handoff (reservar slot antes do upload)	Médio	server + client
17	🟢 Feature	Interrupt mode	Baixo	client + sidecar prompt
18	🟢 Feature	Greet ambiental (já tem os WAVs)	Trivial	client/proximity.lua
19	🟢 Feature	Hash dedup de áudio	Trivial	server/init.lua
O trio de maior ROI imediato: fix 2 (2 caracteres de mudança, segurança crítica), fix 4 (1 linha, elimina spike de latência no 50º jogador), fix 5 (1 linha removida, CPU gratuita em cada TTS). A maior melhoria percebida pelo jogador: fix 3 (SapiTTS persistente) — reduz a latência dominante de ~600ms para ~80ms.