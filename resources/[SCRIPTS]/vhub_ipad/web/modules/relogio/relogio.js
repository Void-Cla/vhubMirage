// modules/relogio/relogio.js — app demo (relógio). Prova o fluxo da Loja (per-char).
// Timer pausa no onHide e morre no onDestroy (A-07) — zero custo com app fora de cena.

(() => {
  'use strict';

  const DAYS   = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
  const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  const pad    = (n) => String(n).padStart(2, '0');

  vhub.createModule('relogio', {

    _timer: null,

    onMount(el) {
      this._time = el.querySelector('[data-el="time"]');
      this._date = el.querySelector('[data-el="date"]');
      this._tick();
    },

    onShow() { this._start(); },
    onHide() { this._stop(); },     // A-07: pausa quando escondido
    onDestroy() { this._stop(); },  // A-07: limpa o interval

    _start() {
      if (this._timer) return;
      this._tick();
      this._timer = setInterval(() => this._tick(), 1000);
    },

    _stop() {
      if (this._timer) { clearInterval(this._timer); this._timer = null; }
    },

    _tick() {
      const d = new Date();
      if (this._time) this._time.textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
      if (this._date) this._date.textContent = `${DAYS[d.getDay()]}, ${d.getDate()} de ${MONTHS[d.getMonth()]}`;
    },

  });
})();
