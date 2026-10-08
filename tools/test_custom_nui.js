'use strict';
// Regressão da lógica real da NUI em VM; DOM double. Não substitui renderização no CEF.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const raiz = 'resources/[SCRIPTS]/vhub_custom/web/';
let total = 0;
function verificar(fn) { fn(); total++; }
function ambiente() {
  const elementos = new Map();
  const timers = new Map();
  const listeners = new Map();
  let seq = 0;
  const elemento = () => ({ disabled: false, textContent: '', dataset: {}, classList: {
    valores: new Set(), add(v) { this.valores.add(v); }, remove(v) { this.valores.delete(v); },
    toggle(v, on) { if (on) this.add(v); else this.remove(v); }, contains(v) { return this.valores.has(v); },
  }, addEventListener() {}, removeEventListener() {}, querySelectorAll() { return []; } });
  const window = { addEventListener(nome, fn) { listeners.set(nome, fn); } };
  const document = { body: elemento(), getElementById(id) {
    if (!elementos.has(id)) elementos.set(id, elemento());
    return elementos.get(id);
  }, querySelectorAll() { return []; } };
  const contexto = vm.createContext({ window, document, console, AbortController,
    setTimeout(fn) { timers.set(++seq, fn); return seq; }, clearTimeout(id) { timers.delete(id); },
    fetch: async () => ({ ok: true, text: async () => '{"ok":true}' }),
  });
  return { contexto, window, document, listeners, timers };
}
const runtime = ambiente();
vm.runInContext(fs.readFileSync(raiz + 'runtime.js', 'utf8'), runtime.contexto);
let fechado = 0;
const bennys = runtime.window.vhub.createModule('bennys', { onHide() { fechado++; } });
const mec = runtime.window.vhub.createModule('mec', {});
bennys.show({}); mec.show({});
verificar(() => assert.equal(fechado, 1));
verificar(() => assert.equal(bennys.isVisible(), false));
verificar(() => assert.equal(mec.isVisible(), true));
verificar(() => assert.equal(runtime.document.body.dataset.servico, 'mec'));
runtime.window.vhub.ocupado(true);
verificar(() => assert.equal(runtime.document.body.classList.contains('service-busy'), true));
mec.hide();
verificar(() => assert.equal(runtime.document.body.classList.contains('service-busy'), false));
verificar(() => assert.equal(runtime.document.body.dataset.servico, undefined));
runtime.window.vhub.aviso('<script>hostil</script>', 'error');
verificar(() => assert.equal(runtime.document.getElementById('service-notice').textContent, '<script>hostil</script>'));

const ui = ambiente();
ui.window.vhub = { request: async () => ({ ok: true }), createModule: () => ({ hide() {} }), ocupado() {}, aviso() {} };
let fonte = fs.readFileSync(raiz + 'bennys.js', 'utf8');
const ponto = fonte.lastIndexOf('})();');
assert.ok(ponto > 0);
fonte = fonte.slice(0, ponto) + `
window.teste = {
  iniciar(dados, atual, pendente) { _data = dados; _cur = atual; _pending = pendente || {}; _aplicando = false; },
  curColourPair, setMod, calcTotal, pushPreview, renderFooter,
  pending() { return _pending; },
  controlesVisuais() {
    const controles = {};
    block = (_, titulo) => titulo;
    switchRow = () => {};
    chips = (titulo, _, __, fn) => { controles[titulo] = fn; };
    mountPicker = (titulo, _, fn) => { controles[titulo] = fn; };
    rangeStepper = () => {};
    renderControls = () => {};
    renderVisual({});
    return controles;
  },
};
` + fonte.slice(ponto);
vm.runInContext(fonte, ui.contexto);
const t = ui.window.teste;
const dados = { prices: { mod_cosmetic: 100, fumaca: 20, xenon: 30, cor_primaria: 50,
  cor_secundaria: 50, stance: 80 }, glass_armor_tiers: [{ id: 0, price: 0 }] };
t.iniciar(dados, { colours: [0, 27], mods: { '23': 2 } });
verificar(() => assert.deepEqual(Array.from(t.curColourPair()), [0, 27]));
t.setMod(23, -1);
verificar(() => assert.equal(t.pending().mods['23'], -1));
verificar(() => assert.equal(t.calcTotal(), 100));
t.iniciar(dados, { smoke: true, xenon: true }, { smoke: false, xenon: false });
verificar(() => assert.equal(t.calcTotal(), 50));
t.iniciar(dados, { exhaust_fx: { enabled: true } }, { exhaust_fx: { enabled: false } });
t.renderFooter();
verificar(() => assert.equal(t.calcTotal(), 0));
verificar(() => assert.equal(ui.document.getElementById('bn-btn-apply').disabled, false));
t.iniciar(dados, { stance: { r: 0, tf: 0, tr: 0, sz: 0, wd: 0 } }, { stance: { r: 0, tf: 0, tr: 0, sz: 0, wd: 0 } });
t.pushPreview();
verificar(() => assert.equal(Object.keys(t.pending()).length, 0));
t.iniciar(dados, { mods: { '23': 2 } }, { mods: { '23': 2 } });
t.pushPreview();
verificar(() => assert.equal(Object.keys(t.pending()).length, 0));

const chama = { enabled: true, r: 12, g: 30, b: 210, scale: 1.8 };
t.iniciar({ ...dados, exhaust_rgb: false }, { exhaust_fx: chama });
let controles = t.controlesVisuais();
verificar(() => assert.equal(controles['Cor das chamas'], undefined));
controles['Tamanho das chamas'](0.6);
verificar(() => assert.deepEqual(JSON.parse(JSON.stringify(t.pending().exhaust_fx)),
  { ...chama, scale: 0.6 }));
t.iniciar({ ...dados, exhaust_rgb: true }, { exhaust_fx: chama });
controles = t.controlesVisuais();
controles['Cor das chamas']([200, 0, 15]);
verificar(() => assert.deepEqual(JSON.parse(JSON.stringify(t.pending().exhaust_fx)),
  { ...chama, r: 200, g: 0, b: 15 }));
console.log(`PASS: ${total} verificações NUI; DOM simulado.`);
