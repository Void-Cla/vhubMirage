// ui/js/app.js — UI single-shot do gate Mirage; autoridade permanece no servidor.

// Guard global: erros JS não-capturados aparecem no #msg para facilitar debug no CEF.
window.onerror = function (msg, src, line, col) {
  var el = document.getElementById('msg') || document.getElementById('msg2');
  if (el) el.textContent = '[JS ERR] ' + msg + ' (' + line + ':' + col + ')';
};

(function () {
  'use strict';

  var RES = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName()
    : 'vhub_login';

  var refs = {
    app: document.getElementById('app'),
    loginView: document.getElementById('view-login'),
    charView: document.getElementById('view-charselect'),
    title: document.getElementById('auth-title'),
    tabs: document.getElementById('auth-tabs'),
    loginForm: document.getElementById('form-login'),
    registerForm: document.getElementById('form-register'),
    recoveryForm: document.getElementById('form-recovery'),
    msg: document.getElementById('msg'),
    msg2: document.getElementById('msg2'),
    charList: document.getElementById('char-list'),
    modal: document.getElementById('terms-modal'),
    btnCreateWrap: document.getElementById('btn-create-wrap')
  };

  var busy = false;
  var termsVersion = '';
  var listeners = [];
  var characterListeners = [];

  var ERR = {
    credencial_invalida: 'Usuário ou senha incorretos.',
    username_invalido: 'Use 3 a 20 caracteres: letras, números ou _.',
    senha_invalida: 'A senha deve ter entre 8 e 64 caracteres.',
    senha_confirmacao: 'As senhas não coincidem.',
    email_invalido: 'Informe um e-mail válido.',
    whatsapp_invalido: 'Informe um WhatsApp válido com DDD.',
    contato_invalido: 'Informe o e-mail ou WhatsApp cadastrado.',
    termos_obrigatorios: 'Confirme que possui 18 anos e aceite os termos.',
    termos_desatualizados: 'Os termos mudaram. Reabra a tela e tente novamente.',
    cadastro_atualizacao_necessaria: 'Atualize o cliente para criar uma conta.',
    cadastro_indisponivel: 'Não foi possível criar a conta com esses dados.',
    conta_bloqueada: 'Conta bloqueada.',
    bloqueado_temporario: 'Muitas tentativas. Aguarde um momento.',
    rate_limit: 'Muitas tentativas. Aguarde um momento.',
    operacao_em_andamento: 'Aguarde a operação atual.',
    char_invalido: 'Personagem inválido.',
    dependency: 'Criador indisponível. Tente novamente.',
    already_created: 'Este personagem já concluiu a criação.',
    not_ready: 'Preparando seu piloto… toque em Entrar novamente em instantes.',
    conflict: 'A operação conflitou. Atualize e tente novamente.',
    invalid_request: 'Solicitação inválida.',
    limit: 'Limite de três personagens atingido.',
    storage: 'Falha de persistência. Tente novamente.',
    offline: 'Sessão indisponível. Reconecte.',
    estado_invalido: 'Sessão expirada. Reconecte.',
    falha_db: 'Falha no servidor. Tente novamente.',
    native: 'Falha ao preparar o cenário. Tente novamente.',
    hss_indisponivel: 'Serviço de personagem indisponível. Tente novamente.',
    core_indisponivel: 'Servidor ocupado. Tente novamente.',
    no_character: 'Personagem não encontrado. Atualize e tente novamente.',
    not_pending: 'Preparando seu piloto… toque em Entrar novamente em instantes.',
    forbidden: 'Ação não permitida.',
    erro: 'Algo deu errado. Tente novamente.'
  };


  // ============================================================
  // SERVIÇO / HELPERS
  // ============================================================

  function nui(name, data) {
    return fetch('https://' + RES + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {})
    }).catch(function () {
      setBusy(false);
      setMessage(activeMessage(), ERR.erro);
    });
  }

  function on(node, event, handler) {
    node.addEventListener(event, handler);
    listeners.push(function () { node.removeEventListener(event, handler); });
  }

  function onCharacter(node, event, handler) {
    node.addEventListener(event, handler);
    characterListeners.push(function () { node.removeEventListener(event, handler); });
  }

  function clearCharacterListeners() {
    while (characterListeners.length) characterListeners.pop()();
  }

  function show(node, visible) {
    node.classList.toggle('hidden', !visible);
  }

  function value(id) {
    var node = document.getElementById(id);
    return node ? node.value || '' : '';
  }

  function setMessage(node, text, success) {
    node.textContent = text || '';
    node.classList.toggle('ok', !!success);
  }

  function activeMessage() {
    return refs.charView.classList.contains('hidden') ? refs.msg : refs.msg2;
  }

  function setBusy(next) {
    busy = next;
    document.querySelectorAll('button[type="submit"]').forEach(function (button) {
      button.disabled = next;
    });
  }

  function clearSensitive() {
    [
      'login-pass', 'register-pass', 'register-confirm',
      'recovery-contact', 'recovery-pass', 'recovery-confirm'
    ].forEach(function (id) {
      var node = document.getElementById(id);
      if (node) node.value = '';
    });
    document.getElementById('register-terms').checked = false;
  }

  function setMode(next) {
    show(refs.loginForm, next === 'login');
    show(refs.registerForm, next === 'register');
    show(refs.recoveryForm, next === 'recovery');
    show(refs.tabs, next !== 'recovery');

    refs.title.textContent = next === 'register'
      ? 'Sua história começa aqui'
      : next === 'recovery'
        ? 'Recupere seu acesso'
        : 'Bem-vindo de volta';

    document.querySelectorAll('.tab').forEach(function (tab) {
      tab.classList.toggle('active', tab.getAttribute('data-mode') === next);
    });
    setMessage(refs.msg, '');
    setBusy(false);
  }

  function openTerms() {
    show(refs.modal, true);
    document.getElementById('btn-close-terms').focus();
  }

  function closeTerms() {
    show(refs.modal, false);
  }


  // ============================================================
  // AUTENTICAÇÃO
  // ============================================================

  document.querySelectorAll('.tab').forEach(function (tab) {
    on(tab, 'click', function () {
      if (!busy) setMode(tab.getAttribute('data-mode'));
    });
  });

  on(document.getElementById('btn-forgot'), 'click', function () {
    if (!busy) setMode('recovery');
  });

  on(document.getElementById('btn-back-login'), 'click', function () {
    if (!busy) setMode('login');
  });

  on(refs.loginForm, 'submit', function (event) {
    event.preventDefault();
    if (busy) return;
    var username = value('login-user').trim();
    var password = value('login-pass');
    if (username.length < 3 || password.length < 6) {
      setMessage(refs.msg, ERR.credencial_invalida);
      return;
    }
    setBusy(true);
    setMessage(refs.msg, '');
    nui('login', { username: username, password: password });
  });

  on(refs.registerForm, 'submit', function (event) {
    event.preventDefault();
    if (busy) return;
    var password = value('register-pass');
    var confirmation = value('register-confirm');
    var accepted = document.getElementById('register-terms').checked;
    if (password.length < 8) return setMessage(refs.msg, ERR.senha_invalida);
    if (password !== confirmation) return setMessage(refs.msg, ERR.senha_confirmacao);
    if (!accepted) return setMessage(refs.msg, ERR.termos_obrigatorios);

    setBusy(true);
    setMessage(refs.msg, '');
    nui('register', {
      username: value('register-user').trim(),
      password: password,
      password_confirmation: confirmation,
      email: value('register-email').trim(),
      whatsapp: value('register-whatsapp').trim(),
      terms_accepted: true,
      age_18: true,
      terms_version: termsVersion
    });
  });

  on(refs.recoveryForm, 'submit', function (event) {
    event.preventDefault();
    if (busy) return;
    var password = value('recovery-pass');
    var confirmation = value('recovery-confirm');
    if (!value('recovery-contact').trim()) return setMessage(refs.msg, ERR.contato_invalido);
    if (password.length < 8) return setMessage(refs.msg, ERR.senha_invalida);
    if (password !== confirmation) return setMessage(refs.msg, ERR.senha_confirmacao);

    setBusy(true);
    setMessage(refs.msg, '');
    nui('recovery', {
      contact: value('recovery-contact').trim(),
      password: password,
      password_confirmation: confirmation
    });
  });


  // ============================================================
  // TERMOS
  // ============================================================

  on(document.getElementById('btn-terms'), 'click', function (event) {
    event.preventDefault();
    event.stopPropagation();
    openTerms();
  });
  on(document.getElementById('btn-privacy'), 'click', openTerms);
  on(document.getElementById('btn-close-terms'), 'click', closeTerms);
  on(document.getElementById('btn-understood'), 'click', closeTerms);
  on(refs.modal, 'click', function (event) {
    if (event.target === refs.modal) closeTerms();
  });
  on(document, 'keydown', function (event) {
    if (event.key === 'Escape' && !refs.modal.classList.contains('hidden')) closeTerms();
  });


  // ============================================================
  // PERSONAGENS
  // ============================================================

  function renderCharacters(characters) {
    clearCharacterListeners();
    refs.charList.textContent = '';

    var slotInfo = document.getElementById('cs-slot-info');
    if (slotInfo) {
      var total = characters ? characters.length : 0;
      slotInfo.textContent = total + ' / 3 slots';
      show(refs.btnCreateWrap, total < 3);
    }

    if (!characters || !characters.length) {
      var empty = document.createElement('div');
      empty.className = 'char-empty';

      var icon = document.createElement('span');
      icon.className = 'char-empty-icon';
      icon.textContent = '🏎';
      empty.appendChild(icon);

      var txt = document.createElement('span');
      txt.textContent = 'Nenhum piloto ainda. Crie o primeiro.';
      empty.appendChild(txt);

      refs.charList.appendChild(empty);
      return;
    }

    characters.forEach(function (character, index) {
      var cid = character.id != null ? character.id : character.char_id;
      var label = character.name || ('Piloto ' + (index + 1));
      var initial = label.charAt(0).toUpperCase();

      var card = document.createElement('button');
      card.type = 'button';
      card.className = 'char-card';
      card.style.animationDelay = (index * 40) + 'ms';

      /* topo com avatar */
      var top = document.createElement('div');
      top.className = 'char-card-top';

      var avatar = document.createElement('div');
      avatar.className = 'char-avatar';
      avatar.textContent = initial;
      top.appendChild(avatar);

      var badge = document.createElement('span');
      badge.className = 'char-index-badge';
      badge.textContent = '#' + (index + 1);
      top.appendChild(badge);

      card.appendChild(top);

      /* corpo */
      var body = document.createElement('div');
      body.className = 'char-card-body';

      var nameEl = document.createElement('div');
      nameEl.className = 'char-card-name';
      nameEl.textContent = label;
      body.appendChild(nameEl);

      var idEl = document.createElement('div');
      idEl.className = 'char-card-id';
      idEl.textContent = 'ID ' + cid;
      body.appendChild(idEl);

      var details = document.createElement('div');
      details.className = 'char-card-details';
      var profile = character.model === 'mp_f_freemode_01'
        ? 'Feminino'
        : character.model === 'mp_m_freemode_01' ? 'Masculino' : 'Perfil pendente';
      details.textContent = (character.age ? character.age + ' anos · ' : '') + profile;
      body.appendChild(details);

      /* botão decorativo "Entrar" */
      var enterBtn = document.createElement('div');
      enterBtn.className = 'char-enter-btn';
      enterBtn.innerHTML = 'Entrar <span class="char-enter-arrow">→</span>';
      body.appendChild(enterBtn);

      card.appendChild(body);

      onCharacter(card, 'click', function () {
        if (busy) return;
        setBusy(true);
        setMessage(refs.msg2, '');
        nui('pickChar', { cid: cid });
      });

      refs.charList.appendChild(card);
    });
  }

  on(document.getElementById('btn-create'), 'click', function () {
    if (busy) return;
    setBusy(true);
    setMessage(refs.msg2, '');
    nui('createChar', {});
  });


  // ============================================================
  // BRIDGE LUA → NUI / CLEANUP
  // ============================================================

  on(window, 'message', function (event) {
    var message = event.data || {};
    var data = message.data || {};
    switch (message.type) {
      case 'login:open':
        termsVersion = typeof data.termsVersion === 'string' ? data.termsVersion : '';
        show(refs.app, true);
        show(refs.loginView, true);
        show(refs.charView, false);
        closeTerms();
        clearSensitive();
        setMode('login');
        document.getElementById('login-user').value = '';
        document.getElementById('login-user').focus();
        break;
      case 'login:view':
        show(refs.loginView, data.view === 'login');
        show(refs.charView, data.view === 'charselect');
        setBusy(false);
        setMessage(refs.msg, '');
        setMessage(refs.msg2, '');
        break;
      case 'login:chars':
        renderCharacters(data.chars);
        break;
      case 'login:error':
        setBusy(false);
        setMessage(activeMessage(), ERR[data.err] || ERR.erro);
        break;
      case 'login:recoveryDone':
        clearSensitive();
        setMode('login');
        setMessage(refs.msg, 'Se o contato coincidiu, sua senha foi redefinida.', true);
        break;
      case 'login:creationReturn':
        show(refs.app, true);
        show(refs.loginView, false);
        show(refs.charView, true);
        renderCharacters(data.chars || []);
        setBusy(false);
        setMessage(refs.msg2, data.err ? (ERR[data.err] || ERR.erro) : '');
        break;
      case 'login:close':
        clearSensitive();
        clearCharacterListeners();
        closeTerms();
        show(refs.app, false);
        setBusy(false);
        break;
    }
  });

  on(window, 'beforeunload', function () {
    clearSensitive();
    clearCharacterListeners();
    while (listeners.length) listeners.pop()();
  });
})();
