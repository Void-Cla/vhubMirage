// web/runtime/store.js — store por dominio (L3).
//
// Slices nomeados por dominio (A-04). Ownership UNICO por slice — quem
// declarou primeiro eh o owner (documentado em comentario do modulo).
//
// API:
//   const slice = vhub.store('panel')   pega/cria o slice
//   slice.get()                          objeto atual
//   slice.set(patch)                     merge raso
//
// REGRA (A-04): nenhum modulo muta slice de outro. Se um modulo precisa de
// estado de outro, comunica via bus — o owner do slice decide se aceita.


(() => {
    'use strict';


    // ============================================================
    // STATE
    // ============================================================

    const _slices = {};   // { [domain]: { get, set } }


    // ============================================================
    // SLICE FACTORY
    // ============================================================

    function makeSlice(initial) {
        let state = initial || {};

        return {
            // Retorna o objeto atual
            get() {
                return state;
            },

            // Merge raso. patch e sempre tabela plana.
            set(patch) {
                if (!patch || typeof patch !== 'object') return;
                state = Object.assign({}, state, patch);
            },
        };
    }


    // ============================================================
    // API PUBLICA
    // ============================================================

    // store(domain) retorna o slice (cria se nao existir).
    function store(domain) {
        if (typeof domain !== 'string' || domain === '') {
            throw new Error('[vhub.store] domain obrigatorio');
        }
        if (!_slices[domain]) _slices[domain] = makeSlice({});
        return _slices[domain];
    }


    window._vhubStore = store;

})();
