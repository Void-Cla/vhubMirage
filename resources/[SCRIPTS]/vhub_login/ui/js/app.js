// ui/js/app.js — runtime da NUI do gate de entrada (Mirage).
// A-01: NÃO decide regra de negócio (validação real é server-side); só UI + relay.
// Anti-XSS: todo texto vai por textContent, nunca innerHTML.
(function () {
  'use strict';

  var RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'vhub_login';

  var app    = document.getElementById('app');
  var vLogin = document.getElementById('view-login');
  var vChar  = document.getElementById('view-charselect');
  var inUser = document.getElementById('in-user');
  var inPass = document.getElementById('in-pass');
  var btn    = document.getElementById('btn-submit');
  var form   = document.getElementById('form-auth');
  var msg    = document.getElementById('msg');
  var msg2   = document.getElementById('msg2');
  var list   = document.getElementById('char-list');

  var mode = 'login';     // 'login' | 'register'
  var busy = false;

  // códigos do servidor → texto amigável PT-BR
  var ERR = {
    credencial_invalida:  'Usuário ou senha incorretos.',
    senha_invalida:       'Senha entre 6 e 64 caracteres.',
    username_invalido:    'Usuário: 3 a 20 (letras, números, _).',
    username_em_uso:      'Esse usuário já existe.',
    uid_ja_tem_conta:     'Já existe conta nesta licença. Faça login.',
    conta_outra_licenca:  'Conta vinculada a outra licença.',
    conta_bloqueada:      'Conta bloqueada.',
    bloqueado_temporario: 'Muitas tentativas. Aguarde um momento.',
    rate_limit:           'Muitas tentativas. Aguarde um momento.',
    char_invalido:        'Personagem inválido.',
    criacao_indisponivel: 'Criação de personagem chega em breve.',
    estado_invalido:      'Sessão expirada. Reconecte.',
    falha_db:             'Falha no servidor. Tente novamente.',
    erro:                 'Algo deu errado.'
  };


  // ============================================================
  // HELPERS
  // ============================================================

  function nui(name, data) {
    return fetch('https://' + RES + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {})
    }).catch(function () {});
  }

  function show(el, on) { el.classList.toggle('hidden', !on); }
  function setMsg(node, text, ok) { node.textContent = text || ''; node.classList.toggle('ok', !!ok); }
  function setBusy(b) { busy = b; btn.disabled = b; }
  function activeMsg() { return vChar.classList.contains('hidden') ? msg : msg2; }


  // ============================================================
  // LOGIN
  // ============================================================

  document.querySelectorAll('.tab').forEach(function (t) {
    t.addEventListener('click', function () {
      document.querySelectorAll('.tab').forEach(function (x) { x.classList.remove('active'); });
      t.classList.add('active');
      mode = t.getAttribute('data-tab');
      btn.textContent = (mode === 'register') ? 'Criar conta' : 'Entrar';
      setMsg(msg, '');
    });
  });

  // lê o campo re-consultando o DOM (robustez contra ref obsoleta)
  function readField(id) {
    var el = document.getElementById(id);
    return el ? (el.value || '') : '';
  }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (busy) return;
    var u = readField('in-user').trim();
    var p = readField('in-pass');
    // mensagens ESPECÍFICAS + diagnóstico (lido:N) p/ distinguir "curto" de "vazio"
    if (u.length < 3) { setMsg(msg, 'Usuário: mínimo 3 caracteres. (lido: ' + u.length + ')'); return; }
    if (p.length < 6) { setMsg(msg, 'Senha: mínimo 6 caracteres. (lido: ' + p.length + ')'); return; }
    setBusy(true); setMsg(msg, '');
    nui(mode === 'register' ? 'register' : 'login', { username: u, password: p });
  });


  // ============================================================
  // PERSONAGENS
  // ============================================================

  function renderChars(chars) {
    list.textContent = '';
    if (!chars || !chars.length) {
      var e = document.createElement('div');
      e.className = 'char-empty';
      e.textContent = 'Nenhum personagem ainda. Crie o primeiro.';
      list.appendChild(e);
      return;
    }
    chars.forEach(function (c, i) {
      var cid = (c.id != null) ? c.id : c.char_id;
      var card = document.createElement('div');
      card.className = 'char-card';

      var left = document.createElement('div');
      var name = document.createElement('div');
      name.className = 'c-name';
      name.textContent = 'Personagem ' + (i + 1);   // nome real virá do futuro perfil
      var idl = document.createElement('div');
      idl.className = 'c-id';
      idl.textContent = 'ID ' + cid;
      left.appendChild(name); left.appendChild(idl);

      var go = document.createElement('div');
      go.className = 'c-go';
      go.textContent = '›';

      card.appendChild(left); card.appendChild(go);
      card.addEventListener('click', function () {
        if (busy) return;
        setBusy(true); setMsg(msg2, '');
        nui('pickChar', { cid: cid });
      });
      list.appendChild(card);
    });
  }

  document.getElementById('btn-create').addEventListener('click', function () {
    if (busy) return;
    nui('createChar', {});
  });


  // ============================================================
  // MENSAGENS DO CLIENTE LUA
  // ============================================================

  window.addEventListener('message', function (ev) {
    var d = ev.data || {};
    switch (d.action) {
      case 'open':
        show(app, true); show(vLogin, true); show(vChar, false);
        setBusy(false); setMsg(msg, ''); setMsg(msg2, '');
        inUser.value = ''; inPass.value = '';
        setTimeout(function () { inUser.focus(); }, 50);
        break;
      case 'view':
        show(vLogin, d.view === 'login');
        show(vChar, d.view === 'charselect');
        setBusy(false); setMsg(msg, ''); setMsg(msg2, '');
        break;
      case 'chars':
        renderChars(d.chars);
        break;
      case 'error':
        setBusy(false);
        setMsg(activeMsg(), ERR[d.err] || ERR.erro);
        break;
      case 'close':
        show(app, false); setBusy(false);
        break;
    }
  });
})();
