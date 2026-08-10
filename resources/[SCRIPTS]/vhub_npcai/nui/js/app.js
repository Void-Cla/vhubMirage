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

let _recorder      = null;   // MediaRecorder ativo
let _recChunks     = [];     // chunks do MediaRecorder
let _recTimerId    = null;   // setTimeout de timeout máximo
let _recStart      = 0;      // timestamp de início
let _vuRaf         = null;   // requestAnimationFrame do VU meter
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

function _startVU(stream) {
    const ctx      = _getCtx();
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 256;
    const src      = ctx.createMediaStreamSource(stream);
    src.connect(analyser);

    const buf = new Uint8Array(analyser.frequencyBinCount);

    function _tick() {
        analyser.getByteFrequencyData(buf);
        let sum = 0;
        for (const v of buf) sum += v;
        const level = Math.min(1, (sum / buf.length) / 80);
        $vuFill.style.width = (level * 100).toFixed(1) + '%';
        _vuRaf = requestAnimationFrame(_tick);
    }
    _vuRaf = requestAnimationFrame(_tick);
}

function _stopVU() {
    if (_vuRaf) { cancelAnimationFrame(_vuRaf); _vuRaf = null; }
    $vuFill.style.width = '0%';
}


// ============================================================
// MEDIA RECORDER — captura de microfone
// ============================================================

async function _startRecording(maxMs) {
    let stream;
    try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
    } catch (e) {
        _luaCallback('micError', { err: 'getUserMedia: ' + e.message });
        return;
    }

    _recChunks = [];
    _recorder  = new MediaRecorder(stream, { mimeType: 'audio/webm' });

    _recorder.ondataavailable = e => { if (e.data.size > 0) _recChunks.push(e.data); };

    _recorder.onstop = () => {
        stream.getTracks().forEach(t => t.stop());
        _stopVU();
        const blob   = new Blob(_recChunks, { type: 'audio/webm' });
        const reader = new FileReader();
        reader.onloadend = () => {
            // extrai somente a parte base64 do data URL
            const b64 = reader.result.split(',')[1];
            _luaCallback('micAudioReady', { audio: b64 });
        };
        reader.readAsDataURL(blob);
    };

    _recorder.start();
    _startVU(stream);
    _recStart = Date.now();

    // timer de tempo na UI
    const _tick = () => {
        if (!_recorder || _recorder.state === 'inactive') return;
        $recTime.textContent = ((Date.now() - _recStart) / 1000).toFixed(1) + 's';
        setTimeout(_tick, 100);
    };
    _tick();

    // timeout máximo (corte automático)
    _recTimerId = setTimeout(() => { _stopRecording(); }, maxMs || 5000);
}

function _stopRecording() {
    if (_recTimerId) { clearTimeout(_recTimerId); _recTimerId = null; }
    if (_recorder && _recorder.state !== 'inactive') {
        _recorder.stop();
    }
    _recorder = null;
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
