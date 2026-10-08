// app.js — motor NUI do vhub_npcai
// Responsabilidades: MediaRecorder (mic), Web Audio API (spatial 3D), VU meter, mensagens Lua


// ============================================================
// ELEMENTOS DO DOM
// ============================================================

const $hint    = document.getElementById('hint-panel');
const $hintKey = document.getElementById('hint-key');
const $hintLbl = document.getElementById('hint-label');
const $rec     = document.getElementById('rec-panel');
const $vuFill  = document.getElementById('vu-fill');
const $recTime = document.getElementById('rec-timer');
const $caption = document.getElementById('caption-panel');
const $capName = document.getElementById('caption-name');
const $capText = document.getElementById('caption-text');


// ============================================================
// ESTADO LOCAL
// ============================================================

let _capture       = null;   // sessão única de captura
let _captureSeq    = 0;      // invalida callbacks de sessões obsoletas
let _audioCtx      = null;   // AudioContext (criado na interação)
let _pannerNode    = null;   // PannerNode atual
let _gainNode      = null;   // GainNode de volume
let _srcNode       = null;   // BufferSourceNode atual
let _currentNpcPos = null;   // { x, y, z } do NPC falando
let _playerPos     = null;   // { x, y, z, fwd } do jogador (atualizado por Lua)
let _playbackNpcId = null;   // npc_id da reprodução atual


// ============================================================
// WEB AUDIO API — context e posicionamento do ouvinte
// ============================================================

function _getCtx() {
    if (!_audioCtx) {
        _audioCtx = new AudioContext();
    }
    if (_audioCtx.state === 'suspended') _audioCtx.resume();
    return _audioCtx;
}

// atualiza posição do ouvinte no AudioContext (player)
function _updateListenerPos(pos) {
    if (!_audioCtx || !pos) return;
    const px = Number(pos.x), py = Number(pos.y), pz = Number(pos.z);
    if (!isFinite(px) || !isFinite(py) || !isFinite(pz)) return;
    const L = _audioCtx.listener;
    const t = _audioCtx.currentTime;
    L.positionX.setTargetAtTime(px, t, 0.05);
    L.positionY.setTargetAtTime(py, t, 0.05);
    L.positionZ.setTargetAtTime(pz, t, 0.05);
    if (pos.fwd) {
        const fx = Number(pos.fwd.x), fy = Number(pos.fwd.y);
        if (isFinite(fx) && isFinite(fy)) {
            L.forwardX.setTargetAtTime(fx, t, 0.05);
            L.forwardY.setTargetAtTime(fy, t, 0.05);
            L.forwardZ.setTargetAtTime(0,  t, 0.05);
        }
    }
}

// monta grafo de áudio 3D e reproduce buffer (base64 WAV ou data URL)
async function _playAudio3D(b64OrUrl, npcPos, murmur) {
    if (!b64OrUrl || b64OrUrl.length < 4) return;
    const ctx = _getCtx();
    _stopCurrentAudio();

    let arrayBuf;
    try {
        if (b64OrUrl.startsWith('audio/')) {
            // caminho local de murmúrio (src relativo)
            const resp = await fetch(b64OrUrl);
            if (!resp.ok) { console.warn('[npcai] fetch murmur falhou', resp.status); return; }
            arrayBuf   = await resp.arrayBuffer();
        } else {
            // base64 WAV/MP3 do sidecar
            const binStr = atob(b64OrUrl);
            const bytes  = new Uint8Array(binStr.length);
            for (let i = 0; i < binStr.length; i++) bytes[i] = binStr.charCodeAt(i);
            arrayBuf = bytes.buffer;
        }
    } catch (e) { console.warn('[npcai] prepare audio falhou', e); return; }

    let decoded;
    try { decoded = await ctx.decodeAudioData(arrayBuf); }
    catch (e) { console.warn('[npcai] decode falhou', e); return; }

    _srcNode  = ctx.createBufferSource();
    _srcNode.buffer = decoded;

    _gainNode = ctx.createGain();
    _gainNode.gain.value = 1.0;

    if (npcPos && !murmur) {
        _pannerNode = ctx.createPanner();
        _pannerNode.panningModel    = 'HRTF';
        _pannerNode.distanceModel   = 'inverse';
        _pannerNode.refDistance     = 3;
        _pannerNode.maxDistance     = 25;
        _pannerNode.rolloffFactor   = 1.2;
        _pannerNode.positionX.value = npcPos.x;
        _pannerNode.positionY.value = npcPos.y;
        _pannerNode.positionZ.value = npcPos.z;

        _srcNode.connect(_pannerNode);
        _pannerNode.connect(_gainNode);
    } else {
        _srcNode.connect(_gainNode);
    }

    _gainNode.connect(ctx.destination);
    _srcNode.start(0);

    _luaCallback('audioStarted', {});

    _srcNode.onended = () => {
        _luaCallback('audioStopped', {});
        if (!murmur) {
            _luaCallback('audioEnded', { npc_id: _playbackNpcId });
        }
    };
}

function _stopCurrentAudio() {
    if (_srcNode) {
        try { _srcNode.stop(); } catch (_) {}
        _srcNode = null;
    }
    _pannerNode = null;
    _gainNode   = null;
}


// ============================================================
// VU METER
// ============================================================

function _cleanupCapture(session) {
    if (session.timeout) { clearTimeout(session.timeout); session.timeout = null; }
    if (session.raf) { cancelAnimationFrame(session.raf); session.raf = null; }
    try { session.source.disconnect(); } catch (_) {}
    try { session.analyser.disconnect(); } catch (_) {}
    session.stream.getTracks().forEach(track => track.stop());
    $vuFill.style.width = '0%';
}

function _finishCapture(session, publish) {
    if (!session || session.finalized) return;
    session.finalized = true;
    session.publish = publish;

    if (session.timeout) { clearTimeout(session.timeout); session.timeout = null; }
    if (session.raf) { cancelAnimationFrame(session.raf); session.raf = null; }
    try { session.source.disconnect(); } catch (_) {}
    try { session.analyser.disconnect(); } catch (_) {}

    try {
        if (session.recorder.state !== 'inactive') session.recorder.stop();
    } catch (_) {
        session.publish = false;
    }
    session.stream.getTracks().forEach(track => track.stop());
}

function _runCaptureLoop(session) {
    const now = performance.now();
    const delta = Math.min(100, now - session.lastTick);
    session.lastTick = now;
    session.analyser.getFloatTimeDomainData(session.samples);

    let energy = 0;
    for (const sample of session.samples) energy += sample * sample;
    const rms = Math.sqrt(energy / session.samples.length);
    const level = Math.min(1, rms / 0.15);
    $vuFill.style.width = (level * 100).toFixed(1) + '%';
    $recTime.textContent = ((now - session.startedAt) / 1000).toFixed(1) + 's';

    if (session.vadEnabled) {
        const gate = session.speechSeen ? session.threshold * 0.70 : session.threshold;
        if (rms >= gate) {
            session.speechSeen = true;
            session.voiceMs += delta;
            session.lastVoiceAt = now;
        } else if (
            session.speechSeen &&
            session.voiceMs >= session.minSpeechMs &&
            now - session.lastVoiceAt >= session.silenceMs
        ) {
            _finishCapture(session, true);
            return;
        }
    }

    if (!session.finalized) {
        session.raf = requestAnimationFrame(() => _runCaptureLoop(session));
    }
}


// ============================================================
// MEDIA RECORDER — captura de microfone
// ============================================================

async function _startRecording(options) {
    _cancelRecording();
    const token = ++_captureSeq;
    const maxMs = Math.max(1000, Math.min(Number(options.max_ms) || 5000, 5000));
    let stream;
    try {
        stream = await navigator.mediaDevices.getUserMedia({
            audio: {
                channelCount: 1,
                sampleRate: 16000,
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
            },
            video: false,
        });
    } catch (e) {
        if (token === _captureSeq) {
            _luaCallback('micError', { err: 'getUserMedia: ' + e.message });
        }
        return;
    }

    if (token !== _captureSeq) {
        stream.getTracks().forEach(track => track.stop());
        return;
    }
    if (!MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
        stream.getTracks().forEach(track => track.stop());
        _luaCallback('micError', { err: 'webm_opus_unsupported' });
        return;
    }

    let recorder;
    try {
        recorder = new MediaRecorder(stream, { mimeType: 'audio/webm;codecs=opus' });
    } catch (e) {
        stream.getTracks().forEach(track => track.stop());
        _luaCallback('micError', { err: 'MediaRecorder: ' + e.message });
        return;
    }

    const ctx = _getCtx();
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    const source = ctx.createMediaStreamSource(stream);
    source.connect(analyser);

    const session = {
        token,
        stream,
        recorder,
        source,
        analyser,
        samples: new Float32Array(analyser.fftSize),
        chunks: [],
        timeout: null,
        raf: null,
        startedAt: performance.now(),
        lastTick: performance.now(),
        lastVoiceAt: 0,
        voiceMs: 0,
        speechSeen: false,
        finalized: false,
        published: false,
        publish: false,
        vadEnabled: options.vad_enabled !== false,
        threshold: Math.max(0.005, Math.min(Number(options.vad_threshold) || 0.020, 0.20)),
        silenceMs: Math.max(300, Math.min(Number(options.silence_ms) || 650, 1500)),
        minSpeechMs: Math.max(100, Math.min(Number(options.min_speech_ms) || 250, 1000)),
    };
    _capture = session;

    recorder.ondataavailable = event => {
        if (event.data.size > 0) session.chunks.push(event.data);
    };

    recorder.onerror = event => {
        if (session.token !== _captureSeq) return;
        _finishCapture(session, false);
        _luaCallback('micError', { err: 'MediaRecorder: ' + (event.error?.message || 'erro') });
    };

    recorder.onstop = () => {
        _cleanupCapture(session);
        if (_capture === session) _capture = null;
        if (!session.publish || session.published || session.token !== _captureSeq) return;
        session.published = true;
        const blob = new Blob(session.chunks, { type: 'audio/webm' });
        const reader = new FileReader();
        reader.onloadend = () => {
            if (session.token !== _captureSeq || typeof reader.result !== 'string') return;
            const b64 = reader.result.split(',')[1] || '';
            if (b64) _luaCallback('micAudioReady', { audio: b64 });
        };
        reader.onerror = () => {
            if (session.token === _captureSeq) _luaCallback('micError', { err: 'FileReader' });
        };
        reader.readAsDataURL(blob);
    };

    try {
        recorder.start(100);
    } catch (e) {
        _finishCapture(session, false);
        _luaCallback('micError', { err: 'MediaRecorder.start: ' + e.message });
        return;
    }
    session.timeout = setTimeout(() => _finishCapture(session, true), maxMs);
    session.raf = requestAnimationFrame(() => _runCaptureLoop(session));
}

function _stopRecording() {
    _finishCapture(_capture, true);
}

function _cancelRecording() {
    _finishCapture(_capture, false);
}


// ============================================================
// HELPER — callback para Lua via fetch NUI
// ============================================================

function _luaCallback(name, data) {
    fetch('https://vhub_npcai/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}


// ============================================================
// HANDLERS DE MENSAGEM LUA → NUI
// ============================================================

window.addEventListener('message', async e => {
    const { action, data } = e.data || {};
    if (!action || !data) return;

    switch (action) {

        // ── hint ──────────────────────────────────────────────
        case 'showHint':
            $hintKey.textContent = data.key  || 'G';
            $hintLbl.textContent = 'Falar com ' + (data.nome || 'NPC');
            $hint.hidden = false;
            break;

        case 'hideHint':
            $hint.hidden = true;
            break;

        // ── gravação ──────────────────────────────────────────
        case 'showRec':
            $rec.hidden = false;
            $recTime.textContent = '0s';
            await _startRecording(data.max_ms || 5000);
            break;

        case 'hideRec':
            _stopRecording();
            $rec.hidden = true;
            break;

        // ── áudio de resposta ─────────────────────────────────
        case 'playAudio': {
            const pos = (data.npc_x != null) ? { x: data.npc_x, y: data.npc_y, z: data.npc_z } : null;
            _currentNpcPos = pos;
            _playbackNpcId = data.npc_id || null;
            const src = data.b64 || data.src;
            if (src) await _playAudio3D(src, pos, !!data.murmur);
            break;
        }

        case 'stopAudio':
            _stopCurrentAudio();
            break;

        // ── legenda ───────────────────────────────────────────
        case 'showCaption':
            $capName.textContent = data.nome || '';
            $capText.textContent = data.text || '';
            $caption.hidden = false;
            break;

        case 'hideCaption':
            $caption.hidden = true;
            break;

        // ── VU meter manual ───────────────────────────────────
        case 'vuLevel':
            $vuFill.style.width = ((data.level || 0) * 100).toFixed(1) + '%';
            break;

        // ── posição do jogador (áudio espacial) ───────────────
        case 'playerPos':
            _playerPos = data;
            _updateListenerPos(data);
            // atualiza posição do panner se NPC ainda falando
            if (_pannerNode && _currentNpcPos) {
                // posição do NPC é fixa; só o ouvinte move
            }
            break;
    }
});
