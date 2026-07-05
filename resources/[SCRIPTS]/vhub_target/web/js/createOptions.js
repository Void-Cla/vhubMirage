// createOptions.js — renderiza uma opção de interação na lista (script clássico)
// Ícone via mapa SVG local (icons.js) — sem FontAwesome/CDN (A-10).
// Label via textContent (anti-XSS: label vem de consumidores diversos).
'use strict';

(function () {
  const optionsWrapper = document.getElementById('options-wrapper');

  function onClick() {
    // pointer-events off no click: sem isso o hover fica preso quando o foco NUI cai
    this.style.pointerEvents = 'none';

    fetchNui('select', [this.targetType, this.targetId, this.zoneId]);
    setTimeout(() => (this.style.pointerEvents = 'auto'), 100);
  }

  window.createOptions = function (type, data, id, zoneId) {
    if (data.hide) return;

    const option = document.createElement('div');
    option.className = 'option-container';
    option.innerHTML = vhIcon(data.icon);

    if (data.iconColor) {
      const svg = option.querySelector('.option-icon');
      if (svg) svg.style.color = data.iconColor;
    }

    const label = document.createElement('p');
    label.className = 'option-label';
    label.textContent = data.label || '';
    option.appendChild(label);

    option.targetType = type;
    option.targetId = id;
    option.zoneId = zoneId;

    option.addEventListener('click', onClick);
    optionsWrapper.appendChild(option);
  };
})();
