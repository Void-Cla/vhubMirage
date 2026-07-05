// fetchNui.js — POST tipado para o callback NUI do resource (script clássico, sem ES module)
'use strict';

(function () {
  const resource = GetParentResourceName();

  window.fetchNui = async function (eventName, data) {
    const resp = await fetch(`https://${resource}/${eventName}`, {
      method: 'post',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    });

    return await resp.json();
  };
})();
