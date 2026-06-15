Camada Lua — Server-Authoritative

velocimetro.lua

client/velocimetro.lua





Lê natives (speed, rpm, gear, fuel)



Lê State Bags (vh_fuel, vh_odo, vhub_seatbelt)



Dedup com threshold por campo



Envia velocimetro:update ao NUI



ADD: heading via GetEntityHeading

main.lua — HUD lifecycle

client/main.lua (+adições)





Detecta categoria ao entrar como motorista



Lê pref via GetResourceKvpString



Envia velo:loadHud (path + huds) ao NUI



NUICallback velo:saveHud → SetResourceKvp



Reset de veloCategory ao sair do veículo

server/main.lua

server/main.lua — sem alterações





Autoridade trava/motor



Broadcast applyLock / applyEngine



vHub CORE: vEnter/vLeave

▼ SendNUIMessage / NUICallback ▼

Camada NUI Parent — Orquestrador

velo-controller.js

html/velo-controller.js





Roteador de mensagens NUI



Gerencia iframe lifecycle (src, display)



Forward velocimetro:update → iframe



Popula galeria de HUDs



Controla troca de aba no painel

app.js

html/app.js (+tab switch)





Handlers de botões (portas, motor, etc)



updateFuel, setEmergency



ADD: switchTab('controls'|'velo')



Arraste do painel (sem alteração)

index.html

html/index.html (+iframe + aba)





Painel vc-panel com 2 abas



Galeria #velo-gallery na aba velo



<iframe id="velo-frame"> substitui <main>



Scripts: app.js + velo-controller.js

▼ iframe.contentWindow.postMessage ▼

Camada NUI HUD Engine — Biblioteca Universal

velo-core.js

html/velo-core.js — incluído em TODOS os HUDs via ../../velo-core.js





createGauge() — interpolação binary search



normalize(data) — payload null-safe + fallback



render() — atualiza IDs padrão (null-safe)



Odômetro RAF — para quando inativo



VeloCore.init(opts) — configura gauges, inicia listener



Hook window.veloCustomRender(state)



Preview mode automático fora do FiveM

▼ script incluído (sem iframe extra) ▼

Camada HUDs — UI Isolada por iframe

carro/vrm_classic

huds/carro/vrm_classic/index.html





11 IDs padrão completos



VeloCore.init({ fuelPoints:[...] })



SVG + CSS animado

moto/velo_moto_default

huds/moto/velo_moto_default/index.html





7 IDs (sem fuel/seatbelt)



veloCustomRender → arco RPM SVG



Remove localStorage

aero/helicoptero_default

huds/aero/helicoptero_default/index.html





3 IDs (speed-val, heading)



veloCustomRender → bússola tape



Troca bussola:update → velocimetro:update

Isolamento iframe: cada HUD roda em contexto isolado — CSS não vaza para o painel e vice-versa. O forward de mensagem (postMessage) é o único canal de comunicação. Adicionar um HUD bugado nunca quebra o painel.


velocimetro:update (SendNUIMessage)
type = 'velocimetro:update'
data.visible      bool   ← HUD visível?
data.active       bool   ← é o motorista
data.speed_kmh    0-999
data.rpm_percent  0-100
data.gear_label   str    ← N|R|1-9
data.fuel_percent  0-100 ← vh_fuel bag
data.odometer_km  num|nil ← vh_odo bag
data.turn_left    bool
data.turn_right   bool
data.seatbelt     bool   ← vhub_seatbelt
data.locked       bool
data.heading      0-360 ← ADD p/ aero
velo:loadHud (SendNUIMessage)
type = 'velo:loadHud'
path      str    ← 'huds/carro/vrm.../index.html'
category  str    ← 'carro'|'moto'|'aero'
hudId     str    ← id do HUD selecionado
huds      table  ← Config.Huds completo

-- Ao sair do veículo:
visible   false  ← oculta iframe
NUICallback velo:saveHud
-- NUI → Lua
data.category  str ← categoria a salvar
data.hudId     str ← id do HUD escolhido

-- Lua faz:
SetResourceKvp('vhub_velo:'..cat, hudId)
-- E re-envia velo:loadHud com path
VeloCore.init(opts) — API da lib
VeloCore.init({
  speedPoints: [[0,-135],[400,135]]
  rpmPoints:   [[0,-135],[10,60]]
  fuelPoints:  [[0,-120],[50,-25],[100,70]]
})
// Gauge points são opcionais:
// - omitir = usa defaults acima
// - null = não renderiza aquela agulha
IDs DOM padrão por categoria de HUD
ID DOM	Carro/Caminhão	Moto/Bicicleta	Aero/Barco	Nota
#vehicle-speed-prefix + #vehicle-speed	✓ obrigatório	✓ obrigatório	~ #speed-val	split 3 dígitos
#speed-needle	✓	✓	–	rotate CSS
#rpm-needle	✓	~ customRender	–	arco SVG no moto
#fuel-needle	✓	–	–	rotate CSS
#vehicle-gear	✓	✓	–	texto N/R/1-9
[data-odo-digit] .odoColumn	✓	~ simples	–	RAF auto
#status-turn-left/right	✓	✓	–	data-status on|off
#status-seatbelt	✓	–	–	cinto
#status-lock	✓	✓	–	cadeado
#heading-deg + #heading-card + #tape-track	–	–	✓ customRender	bússola tape


velo-core.js — estrutura interna completa
// html/velo-core.js — biblioteca universal incluída por todos HUDs
const VeloCore = (function() {

  // ── GAUGE ENGINE (binary search — de script-velocimetro.js) ──
  function createGauge(points) {
    // segments = [[v1,v2,a1,slope],...] sorted
    // get(value) → ângulo com binary search O(log n) + cache lastIndex
    // clamp automático nos extremos
    return { get };
  }

  // ── ESTADO ──────────────────────────────────────────────────
  const fallback = { visible:false, active:false, speed_kmh:0,
    rpm_percent:0, gear_label:'N', fuel_percent:0,
    odometer_km:null, turn_left:false, turn_right:false,
    seatbelt:false, locked:false, heading:0 };
  let state = {...fallback}, opts = {};

  // ── DOM HELPERS (null-safe) ──────────────────────────────────
  const $ = id => document.getElementById(id);
  function setText(id, v) { const e=$(id); if(e) e.textContent=v; }
  function setRot(id, deg) { const e=$(id); if(e) e.style.transform=`rotate(${deg}deg)`; }
  function setStatus(id, on) { const e=$(id); if(e) e.dataset.status=on?'on':'off'; }
  function setActive(on) { const e=$('velo-root'); if(e) e.classList.toggle('velo-active',on); }

  // ── ODÔMETRO RAF (para quando inativo — zero CPU idle) ───────
  let odoKm=0, lastTick=null, odoRaf=null, lastDigits=[-1,-1,-1,-1,-1,-1];
  const odoDigits = [];
  // tickOdo() → easing suave → renderOdo() → translateY scroll
  // ensureOdoLoop(): só inicia RAF quando active=true

  // ── NORMALIZE ────────────────────────────────────────────────
  function normalize(d) { /* clamp+parse todos campos, fallback seguro */ }

  // ── RENDER (null-safe para IDs inexistentes) ─────────────────
  function render() {
    const s=state, active=s.visible&&s.active;
    setActive(active);
    // speed split 3 dígitos
    if(opts.speedGauge) setRot('speed-needle', opts.speedGauge.get(s.speed_kmh));
    if(opts.rpmGauge) setRot('rpm-needle', opts.rpmGauge.get(s.rpm_percent/10));
    if(opts.fuelGauge) setRot('fuel-needle', opts.fuelGauge.get(s.fuel_percent));
    // gear, status icons, odômetro
    if(typeof window.veloCustomRender === 'function')
      window.veloCustomRender(s); // hook por HUD
  }

  // ── API PÚBLICA ───────────────────────────────────────────────
  function init(userOpts={}) {
    opts.speedGauge = userOpts.speedPoints ? createGauge(userOpts.speedPoints)
      : createGauge([[0,-135],[400,135]]);
    opts.rpmGauge = userOpts.rpmPoints ? createGauge(userOpts.rpmPoints)
      : ($('rpm-needle') ? createGauge([[0,-135],[10,60]]) : null);
    opts.fuelGauge = userOpts.fuelPoints ? createGauge(userOpts.fuelPoints)
      : ($('fuel-needle') ? createGauge([[0,-120],[50,-25],[100,70]]) : null);
    document.querySelectorAll('[data-odo-digit] .odoColumn').forEach(c=>odoDigits.push(c));
    window.addEventListener('message', e => {
      if(e.data?.type === 'velocimetro:update')
        apply(e.data.data || fallback);
    });
    // preview fora do FiveM
    const fivem = String(location.hostname).startsWith('cfx-nui-');
    apply(fivem ? fallback : { visible:true, active:true, speed_kmh:128,
      rpm_percent:67, gear_label:'4', fuel_percent:60, locked:true });
  }
  function apply(d) { state=normalize(d); render(); ensureOdoLoop(); }
  return { init, apply, createGauge };
})();
velo-controller.js — estrutura interna
// html/velo-controller.js — carregado no index.html (escopo próprio)
(function() {
  const frame = document.getElementById('velo-frame');
  let currentCategory = null, allHuds = {}, selectedHud = {};

  // ── ROTEADOR ÚNICO DE MENSAGENS ──────────────────────────────
  window.addEventListener('message', e => {
    const d = e.data; if(!d?.type) return;
    switch(d.type) {
      case 'velo:loadHud':         loadHud(d); break;
      case 'velocimetro:update':   forwardToFrame(d); break;
      case 'velo:openGallery':    openGallery(d); break;
    }
  });

  function loadHud(d) {
    if(d.huds) allHuds = d.huds;
    if(d.category) { currentCategory=d.category; populateGallery(d.category); }
    if(d.visible === false) { frame.style.display='none'; return; }
    if(d.path) { frame.src=d.path; frame.style.display='block'; }
  }

  function forwardToFrame(msg) {
    try { frame.contentWindow?.postMessage(msg, '*'); } catch(_){}
  }

  function selectHud(cat, id, path) {
    selectedHud[cat] = id; loadHud({ path, category:cat }); populateGallery(cat);
    fetch(`https://${GetParentResourceName()}/velo:saveHud`,
      { method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ category:cat, hudId:id }) }).catch(()=>{});
  }
})();
Adições em client/main.lua (inserir no loop vc_ existente)
-- Variáveis de estado (declarar no topo junto de vc_veh)
local veloCategory = nil

-- Helpers (adicionar após as funções existentes)
local function getHudPath(cat, id)
  for _,h in ipairs(Config.Huds[cat] or {}) do
    if h.id == id then return h.path end
  end
  return Config.Huds[cat] and Config.Huds[cat][1] and Config.Huds[cat][1].path
end
local function getUserHud(cat)
  local v = GetResourceKvpString('vhub_velo:'..cat)
  return (v and v~='') and v or Config.DefaultHuds[cat]
end

-- INSERIR no loop vc_ após detectar GetPedInVehicleSeat(v,-1)==ped:
local cat = Config.VehicleCategories[GetVehicleClass(v)] or 'carro'
if cat ~= veloCategory then
  veloCategory = cat
  local id = getUserHud(cat)
  local path = getHudPath(cat, id)
  SendNUIMessage({ type='velo:loadHud', category=cat, hudId=id,
                    path=path, huds=Config.Huds })
end

-- INSERIR na função reportLeave (ao sair do veículo):
veloCategory = nil

-- NUICallback para salvar preferência:
RegisterNUICallback('velo:saveHud', function(data, cb)
  if type(data.category)=='string' and type(data.hudId)=='string' then
    SetResourceKvp('vhub_velo:'..data.category, data.hudId)
    local p = getHudPath(data.category, data.hudId)
    if p then SendNUIMessage({ type='velo:loadHud', path=p }) end
  end
  cb('ok')
end)










✓ Após a fusão estar completa, adicionar um novo HUD requer apenas 2 ações — zero mudança em Lua, zero mudança no controller.
1
Criar a pasta e o index.html NOVO arquivo
Estrutura mínima obrigatória. O HUD inclui velo-core.js e chama VeloCore.init(). O restante é HTML/CSS livre — qualquer visual.
<!-- html/huds/carro/meu_hud_novo/index.html -->
<!DOCTYPE html><html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <link rel="stylesheet" href="style.css"> <!-- seu CSS -->
</head>
<body>
<div id="velo-root"> <!-- raiz: velo-core seta .velo-active -->

  <!-- IDs padrão: coloque os que usar -->
  <div id="speed-needle"></div>
  <span id="vehicle-speed-prefix">00</span><span id="vehicle-speed">0</span>
  <span id="vehicle-gear">N</span>
  <!-- Adicione #rpm-needle, #fuel-needle, etc. conforme precisar -->

</div>

<!-- OBRIGATÓRIO: inclui a lib -->
<script src="../../velo-core.js"></script>
<script>
  // Gauges customizados (opcional — omitir = usa defaults)
  window.veloOpts = {
    speedPoints: [[0,-120],[200,0],[400,120]] // curva personalizada
  };

  // Lógica extra (opcional)
  window.veloCustomRender = function(state) {
    // ex: mudar cor da agulha por velocidade
    document.getElementById('speed-needle').style.background =
      state.speed_kmh > 200 ? '#ff2a2a' : '#ffffff';
  };

  document.addEventListener('DOMContentLoaded', () => VeloCore.init(window.veloOpts || {}));
</script>
</body></html>
huds/carro/meu_hud_novo/index.html
huds/carro/meu_hud_novo/style.css
2
Registrar no Config.Huds 1 linha
Adicionar uma entrada na tabela da categoria correta em shared/config.lua.
Config.Huds = {
  ["carro"] = {
    { id = "vrm_classic",   name = "VRM Clássico",   path = "huds/carro/vrm_classic/index.html" },
    { id = "meu_hud_novo", name = "Meu HUD", path = "huds/carro/meu_hud_novo/index.html" }, ← ADD
  },
  ...
}
shared/config.lua
✓
Pronto — sem mais nada
O glob html/huds/**/*.html no fxmanifest já cobre o novo arquivo. O velo-controller.js já lida com qualquer HUD da galeria. Ao entrar no veículo, o jogador verá o novo HUD disponível na aba Velocímetro do painel.




Iframe sandbox
ATIVO
Cada HUD corre em iframe isolado. CSS não vaza para o painel. JS do HUD não tem acesso ao DOM do painel. Um HUD bugado ou malicioso não pode interferir na lógica do vehcontrol. O único canal de comunicação é postMessage com payload controlado.
🔒
Preferências via KVP client-side
SEGURO
HUD preference = dado de UI, não crítico. GetResourceKvpString/SetResourceKvp é por jogador, por recurso, no client local. Não passa por server. Não pode ser explorado para dupe ou bypass de inventário. Se um jogador editar o KVP, o pior resultado é ver um HUD diferente.
🔒
NUICallback velo:saveHud com validação de tipo
VALIDADO
O callback valida type(data.category)=='string' e type(data.hudId)=='string'. Se um cliente enviar payload malformado, retorna cb('ok') silenciosamente sem SetResourceKvp. Não expõe erro, não crasha.
🔒
Remoção do localStorage nos HUDs
NECESSÁRIO
O HUD moto original usava localStorage. Em FiveM NUI, localStorage é bloqueado em iframes por política CSP em algumas builds. Removendo e usando apenas KVP Lua, a preferência funciona 100% das vezes.
⚠️
Heading no dedup com threshold 2°
ATENÇÃO
GetEntityHeading muda a cada frame em aeronaves. Sem threshold, o dedup de velocimetro.lua enviaria updates a 80ms mesmo parado. Arredondar para 2° (math.floor(heading/2+0.5)*2) reduz ruído sem impactar a bússola visualmente.
🔒
velo-controller.js em IIFE — sem poluição global
ISOLADO
Envolver em (function(){ ... })() garante que nenhuma variável interna (frame, currentCategory, etc.) vaze para o escopo global do index.html e conflite com app.js. Expõe apenas window.veloController para comunicação mínima necessária.
O que NÃO muda (segurança preservada)
// server/main.lua — ZERO alterações
// hasAccess() com chave + dono continua intocado
// trava/motor continuam server-authoritative
// broadcast applyLock/applyEngine continua com anti-spoof placa+netId

// client/velocimetro.lua — só 2 adições
// + heading = math.floor(GetEntityHeading(veiculo)/2+0.5)*2
// + heading no dedup (último_estado.heading)
// + heading no payload do SendNUIMessage