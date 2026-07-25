// hud.js — lifecycle e render delta do HUD HSS

'use strict';

const state = {
    health: 1,
    food: 1,
    water: 1,
    armour: 0,
    effective_energy: 1,
    oxygen: 1,
    oxygen_visible: false,
    adrenaline: 0,
    blood: 1,
    bleeding: 0,
    pain: 0,
    trauma: 0,
    body_temp: 37,
    stress: 0,
    consciousness: 'awake',
};

const numericFields = new Set([
    'health', 'food', 'water', 'armour', 'effective_energy', 'oxygen',
    'adrenaline', 'blood', 'bleeding', 'pain', 'trauma', 'body_temp', 'stress',
]);

let elements = null;


// ============================================================
// EXPAND / COLLAPSE COM TIMER DE 5 SEGUNDOS
// ============================================================

const EXPAND_MS = 5000;
const _timers   = {};
const _tracked  = {};

// expande a track se o valor mudou; agenda colapso após EXPAND_MS
function tryExpand(key, value, trackEl, epsilon) {
    if (!trackEl) return;
    epsilon = (epsilon !== undefined) ? epsilon : 0.005;
    const prev    = _tracked[key];
    const changed = prev === undefined
        || (typeof value === 'number' ? Math.abs(value - prev) > epsilon : value !== prev);
    _tracked[key] = value;
    if (!changed) return;

    if (_timers[key]) clearTimeout(_timers[key]);
    trackEl.classList.remove('hss-track--hidden');
    _timers[key] = setTimeout(function () {
        trackEl.classList.add('hss-track--hidden');
        delete _timers[key];
    }, EXPAND_MS);
}

function clearAllTimers() {
    for (var k in _timers) { clearTimeout(_timers[k]); delete _timers[k]; }
    for (var k in _tracked) { delete _tracked[k]; }
}


// ============================================================
// RENDER
// ============================================================

function conditional(element, visible) {
    element.classList.toggle('hss-cond--hidden', !visible);
}

// atualiza preenchimento e cor crítica (não toca na track)
function bar(fill, value, critical) {
    var normalized = Math.max(0, Math.min(1, value));
    fill.style.transform = 'scaleX(' + normalized + ')';
    fill.classList.toggle('hss-critical', normalized <= critical);
}

function render() {
    // barras principais — ícones sempre visíveis, tracks expandem por mudança
    bar(elements.fillHealth, state.health, 0.25);
    tryExpand('health', state.health, elements.barHealth);

    bar(elements.fillFood, state.food, 0.18);
    tryExpand('food', state.food, elements.barFood);

    bar(elements.fillWater, state.water, 0.18);
    tryExpand('water', state.water, elements.barWater);

    // colete — row some quando zerado; track expande por timer
    var hasArmour = state.armour > 0.01;
    conditional(elements.rowArmour, hasArmour);
    if (hasArmour) {
        bar(elements.fillArmour, state.armour, 0.15);
        tryExpand('armour', state.armour, elements.barArmour);
    }

    // energia — row sempre visível; track expande por timer
    bar(elements.fillEnergy, state.effective_energy, 0.20);
    tryExpand('energy', state.effective_energy, elements.barEnergy);

    // oxigênio — row condicional; track expande por timer quando visível
    conditional(elements.rowOxygen, state.oxygen_visible);
    if (state.oxygen_visible) {
        bar(elements.fillOxygen, state.oxygen, 0.25);
        tryExpand('oxygen', state.oxygen, elements.barOxygen);
    }

    // adrenalina — row condicional; track expande por timer quando visível
    var hasAdr = state.adrenaline > 0.12;
    conditional(elements.rowAdrenaline, hasAdr);
    if (hasAdr) {
        bar(elements.fillAdrenaline, state.adrenaline, -1);
        tryExpand('adrenaline', state.adrenaline, elements.barAdrenaline);
    }

    // alertas de status
    var alerts = {
        bleeding:    state.bleeding >= 1,
        pain:        state.pain >= 0.45,
        trauma:      state.trauma >= 0.15,
        temperature: state.body_temp <= 35.4 || state.body_temp >= 39.2,
        stress:      state.stress >= 0.62,
    };
    conditional(elements.alertBleeding,    alerts.bleeding);
    conditional(elements.alertPain,        alerts.pain);
    conditional(elements.alertTrauma,      alerts.trauma);
    conditional(elements.alertTemperature, alerts.temperature);
    conditional(elements.alertStress,      alerts.stress);
    conditional(elements.alerts, Object.values(alerts).some(Boolean));

    var bpm = Math.round(Math.min(190,
        68 + state.adrenaline * 72 + state.stress * 22 + state.pain * 15));
    conditional(elements.bpm, bpm >= 95);
    if (bpm >= 95) elements.bpmValue.textContent = String(bpm);

    var unconscious = state.consciousness === 'unconscious';
    var mood = '';
    if (state.adrenaline >= 0.80)      mood = 'ADRENALINA MÁXIMA';
    else if (state.adrenaline >= 0.50) mood = 'PULSO ACELERADO';
    else if (state.stress >= 0.65)     mood = 'SOB TENSÃO';
    conditional(elements.mood, mood !== '' && !unconscious);
    elements.mood.textContent = mood;
    conditional(elements.unconscious, unconscious);
}


// ============================================================
// LIFECYCLE
// ============================================================

vhub.createModule('hss', {
    onInit() {
        window.addEventListener('message', onMessage);
    },

    onMount() {
        var id = function (v) { return document.getElementById(v); };
        elements = {
            root:          id('hss-hud'),
            rowHealth:     id('row-health'),     barHealth:     id('bar-health'),     fillHealth:     id('fill-health'),
            rowFood:       id('row-food'),        barFood:       id('bar-food'),       fillFood:       id('fill-food'),
            rowWater:      id('row-water'),       barWater:      id('bar-water'),      fillWater:      id('fill-water'),
            rowArmour:     id('row-armour'),      barArmour:     id('bar-armour'),     fillArmour:     id('fill-armour'),
            rowEnergy:     id('row-energy'),      barEnergy:     id('bar-energy'),     fillEnergy:     id('fill-energy'),
            rowOxygen:     id('row-oxygen'),      barOxygen:     id('bar-oxygen'),     fillOxygen:     id('fill-oxygen'),
            rowAdrenaline: id('row-adrenaline'),  barAdrenaline: id('bar-adrenaline'), fillAdrenaline: id('fill-adrenaline'),
            alerts:          id('hss-alerts'),
            alertBleeding:   id('alert-bleeding'), alertPain:        id('alert-pain'),
            alertTrauma:     id('alert-trauma'),   alertTemperature: id('alert-temperature'),
            alertStress:     id('alert-stress'),
            bpm:             id('hss-bpm'),         bpmValue:     id('hss-bpm-value'),
            mood:            id('hss-mood'),         unconscious:  id('hss-unconscious'),
        };
    },

    onShow() {
        elements.root.classList.remove('hss-hud--hidden');
        elements.root.setAttribute('aria-hidden', 'false');
        render();
    },

    onHide() {
        if (!elements) return;
        elements.root.classList.add('hss-hud--hidden');
        elements.root.setAttribute('aria-hidden', 'true');
    },

    onDestroy() {
        window.removeEventListener('message', onMessage);
        clearAllTimers();
        this.onHide();
        elements = null;
    },
});

function applyDelta(delta) {
    if (!delta || typeof delta !== 'object') return false;
    var changed = false;

    for (var field in delta) {
        if (!(field in state)) continue;
        var raw = delta[field];
        var value = raw;
        if (numericFields.has(field)) {
            if (typeof raw !== 'number' || !isFinite(raw)) continue;
            value = field === 'body_temp' ? Math.max(30, Math.min(45, raw))
                  : field === 'bleeding'  ? Math.max(0, Math.min(4, Math.floor(raw)))
                                          : Math.max(0, Math.min(1, raw));
        } else if (field === 'oxygen_visible') {
            value = raw === true;
        } else if (field === 'consciousness') {
            value = raw === 'unconscious' ? 'unconscious' : 'awake';
        }
        if (state[field] !== value) {
            state[field] = value;
            changed = true;
        }
    }
    return changed;
}

function onMessage(event) {
    var message = event.data;
    if (!message || typeof message !== 'object') return;
    if (message.type === 'hss:hide') {
        vhub.hide('hss');
        return;
    }
    if (message.type !== 'hss:update') return;

    var changed = applyDelta(message.data);
    if (!vhub.isVisible('hss')) vhub.show('hss');
    else if (changed) render();
}

vhub.mount('hss');
