(() => {
  "use strict";

  const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : "vhub_spawselector";
  const app = document.getElementById("spawn-app");
  const list = document.getElementById("locations");
  const counter = document.getElementById("counter");
  const number = document.getElementById("selected-number");
  const name = document.getElementById("selected-name");
  const description = document.getElementById("selected-description");
  const confirm = document.getElementById("confirm");
  const backButton = document.getElementById("back-characters");
  const lastButton = document.getElementById("last-location");
  const lastName = document.getElementById("last-name");
  const lastDescription = document.getElementById("last-description");
  const notice = document.getElementById("notice");

  let items = [];
  let selected = 0;
  let open = false;
  let busy = false;

  const safeImage = value => /^[\w.-]+$/.test(String(value || "")) ? String(value) : "parking.png";
  const label = value => String(value == null ? "" : value).slice(0, 96);

  function post(endpoint, payload) {
    return fetch(`https://${resource}/${endpoint}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(payload || {})
    }).catch(() => null);
  }

  function showNotice(message) {
    notice.textContent = label(message).replace(/_/g, " ").toUpperCase();
    notice.classList.toggle("is-visible", Boolean(message));
  }

  function select(index) {
    if (!open || busy || !items[index]) return;
    selected = index;
    const item = items[index];
    number.textContent = String(index + 1).padStart(2, "0");
    name.textContent = label(item.Name) || "DESTINO";
    description.textContent = label(item.Description) || "Ponto de chegada selecionado";
    counter.textContent = `${index + 1} / ${items.length}`;
    [...list.children].forEach((element, position) => {
      const active = position === index;
      element.classList.toggle("is-selected", active);
      element.setAttribute("aria-pressed", String(active));
    });
    showNotice("");
  }

  function build(payload) {
    items = Array.isArray(payload.data) ? payload.data.slice(0, 24) : [];
    list.replaceChildren();

    items.forEach((item, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "location";
      button.innerHTML = `<img class="thumb" alt=""><span><strong></strong><small></small></span><span class="arrow">›</span>`;
      button.querySelector("img").src = `images/${safeImage(item.Image)}`;
      button.querySelector("strong").textContent = label(item.Name) || `Destino ${index + 1}`;
      button.querySelector("small").textContent = label(item.Description) || "Local disponível";
      button.addEventListener("click", () => select(index));
      list.appendChild(button);
    });

    const last = payload.last && typeof payload.last === "object" ? payload.last : {};
    lastName.textContent = label(last.Name) || "ÚLTIMA LOCALIZAÇÃO";
    lastDescription.textContent = label(last.Description) || "Retomar de onde parou";
    selected = 0;
    select(0);
  }

  function show(payload) {
    busy = false;
    open = true;
    confirm.disabled = false;
    confirm.textContent = "CONFIRMAR DESTINO  →";
    showNotice("");
    backButton.hidden = payload.canBack !== true;
    build(payload);
    document.body.style.display = "block";
    app.setAttribute("aria-hidden", "false");
    requestAnimationFrame(() => {
      document.body.classList.add("is-open");
      post("ready", {});
    });
  }

  function hide() {
    open = false;
    busy = false;
    document.body.classList.remove("is-open");
    app.setAttribute("aria-hidden", "true");
    window.setTimeout(() => {
      if (!open) document.body.style.display = "none";
    }, 230);
  }

  function submit(useLast) {
    if (!open || busy || (!useLast && !items[selected])) return;
    busy = true;
    confirm.disabled = true;
    confirm.textContent = "VALIDANDO ROTA…";
    showNotice("");
    post("teleport", { index: selected + 1, useLast: useLast === true });
  }

  function back() {
    if (!open || busy || backButton.hidden) return;
    busy = true;
    confirm.disabled = true;
    confirm.textContent = "RETORNANDO…";
    showNotice("");
    post("back", {});
  }

  confirm.addEventListener("click", () => submit(false));
  lastButton.addEventListener("click", () => submit(true));
  backButton.addEventListener("click", back);

  window.addEventListener("keydown", event => {
    if (!open || busy) return;
    if (event.key === "ArrowUp" || event.key === "ArrowLeft") select((selected - 1 + items.length) % items.length);
    else if (event.key === "ArrowDown" || event.key === "ArrowRight") select((selected + 1) % items.length);
    else if (event.key === "Enter") submit(false);
    else if (event.key === "Escape") backButton.hidden ? submit(true) : back();
  });

  window.addEventListener("message", event => {
    const message = event.data || {};
    if (message.action === "open") show(message);
    else if (message.action === "close") hide();
    else if (message.action === "busy") {
      busy = true;
      confirm.disabled = true;
      confirm.textContent = message.label || "VALIDANDO ROTA…";
    } else if (message.action === "accepted") {
      busy = true;
      confirm.disabled = true;
      confirm.textContent = "PREPARANDO PERSONAGEM…";
    } else if (message.action === "result" && message.ok !== true) {
      busy = false;
      confirm.disabled = false;
      confirm.textContent = "TENTAR NOVAMENTE  →";
      showNotice(message.err || "Falha ao validar destino");
    }
  });

  hide();
})();
