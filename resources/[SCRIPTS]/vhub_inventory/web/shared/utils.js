// shared/utils.js — helpers puros de NUI (formatacao, icone CDN, DOM).

(function () {
  vhub.util = {

    // peso em kg com 1 casa
    fmtWeight(n) {
      return (Number(n) || 0).toFixed(1);
    },

    // cor da barra de peso por percentual (verde -> dourado -> laranja -> vermelho)
    weightColor(pct) {
      if (pct >= 100) return 'var(--vh-danger)';
      if (pct >= 85)  return 'linear-gradient(90deg, #e0a85a, #e06a5a)';
      if (pct >= 60)  return 'linear-gradient(90deg, var(--vh-gold), var(--vh-sand))';
      return 'linear-gradient(90deg, #6bd06b, #b9e2a0)';
    },

    // URL do icone via CDN dinamico: base + '/<id>.png' (so o identificador)
    itemIcon(id) {
      const base = (vhub.config && vhub.config.cdn) || '';
      return `${base}/${id}.png`;
    },

    // rotulo do item a partir do catalogo recebido no handshake
    itemName(id) {
      const c = vhub.config && vhub.config.catalog && vhub.config.catalog[id];
      return (c && c.nome) || id;
    },

    itemDef(id) {
      return (vhub.config && vhub.config.catalog && vhub.config.catalog[id]) || null;
    },

    // cria elemento com classe e atributos
    el(tag, cls, attrs) {
      const e = document.createElement(tag);
      if (cls) e.className = cls;
      if (attrs) for (const k in attrs) e.setAttribute(k, attrs[k]);
      return e;
    },

    // preenche uma celula `.slot` com icone (CDN + fallback), quantidade, placa e tooltip.
    // Compartilhado por mochila e baú (DRY). `entry` = { id, amount, meta }.
    fillSlot(cell, entry) {
      cell.dataset.filled = '1';
      const def = vhub.util.itemDef(entry.id);

      const ic = vhub.util.el('div', 'ic');
      ic.style.backgroundImage = `url(${vhub.util.itemIcon(entry.id)})`;
      const probe = new Image();                 // fallback se o CDN falhar
      probe.onerror = () => {
        ic.style.backgroundImage = 'none';
        const ini = vhub.util.el('div', 'ini');
        ini.textContent = ((def && def.nome) ? def.nome : entry.id).charAt(0).toUpperCase();
        cell.appendChild(ini);
      };
      probe.src = vhub.util.itemIcon(entry.id);
      cell.appendChild(ic);

      if ((entry.amount || 1) > 1) {
        const qt = vhub.util.el('div', 'qt'); qt.textContent = 'x' + entry.amount; cell.appendChild(qt);
      }
      if (entry.meta && entry.meta.plate) {
        const pl = vhub.util.el('div', 'pl'); pl.textContent = entry.meta.plate; cell.appendChild(pl);
      }
      const nm = (def && def.nome) || entry.id;
      let title = nm + (entry.meta && entry.meta.plate ? ' • ' + entry.meta.plate : '');
      // dossiê do veículo (chave): campo OPCIONAL vindo do prontuário — nunca assumir presença
      const vd = entry.meta && entry.meta.veiculo;
      if (vd) {
        if (typeof vd.fuel === 'number')          title += `\nCombustível: ${Math.round(vd.fuel)}%`;
        if (typeof vd.engine_health === 'number') title += `\nMotor: ${Math.round(vd.engine_health / 10)}%`;
        if (typeof vd.body_health === 'number')   title += `\nLataria: ${Math.round(vd.body_health / 10)}%`;
        if (typeof vd.odometer_km === 'number')   title += `\nOdômetro: ${vd.odometer_km.toFixed(1)} km`;
        if (vd.model)                             title += `\nModelo: ${vd.model}`;
      }
      cell.title = title;
    },
  };
})();
