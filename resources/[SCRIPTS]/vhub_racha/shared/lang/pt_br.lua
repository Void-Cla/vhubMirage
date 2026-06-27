-- shared/lang/pt_br.lua — textos PT-BR centralizados.
-- Resolve labels cruas tipo 'race_time_left' aparecendo na UI.
-- Uso: VHubRachaLang.t('lobby.waiting') ou VHubRachaLang.t('race.cp_distance', { dist = 1.24 })

VHubRachaLang = VHubRachaLang or {}
local L = VHubRachaLang

L.strings = {
  -- ── Brand ───────────────────────────────────────────────────────────────
  ['brand.title']            = 'Mirage Racha',
  ['brand.tagline']          = 'Liga clandestina premium',

  -- ── Lobby ───────────────────────────────────────────────────────────────
  ['lobby.waiting']          = 'Aguardando jogadores',
  ['lobby.starting_soon']    = 'A corrida vai comecar',
  ['lobby.starting_in_sec']  = 'Largada em %d s',
  ['lobby.confirm_presence'] = 'Confirme presenca na largada',
  ['lobby.you_have_min']     = 'Voce tem %d min para confirmar presenca.',
  ['lobby.press_e_confirm']  = '[E] Confirmar presenca',
  ['lobby.confirmed']        = 'Presenca confirmada',
  ['lobby.canceled']         = 'Lobby cancelado',
  ['lobby.full']             = 'Lobby cheio',
  ['lobby.no_session']       = 'Sessao nao encontrada',
  ['lobby.already_in']       = 'Voce ja esta nesse lobby',
  ['lobby.already_racing']   = 'Voce ja esta em uma corrida',
  ['lobby.fee_paid']         = 'Taxa paga: R$ %s',
  ['lobby.not_enough_money'] = 'Saldo insuficiente para a taxa',
  ['lobby.too_few_players']  = 'Jogadores insuficientes para iniciar',
  ['lobby.no_grid_slot']     = 'Sem espaco na grade',
  ['lobby.host_left']        = 'O organizador saiu — lobby cancelado',
  ['lobby.expired']          = 'Tempo do lobby esgotou',
  ['lobby.only_host_start']  = 'Apenas o organizador pode iniciar',
  ['lobby.created']          = 'Lobby criado. Aguardando jogadores.',
  ['lobby.you_joined']       = 'Voce entrou no lobby',
  ['lobby.you_left']         = 'Voce saiu do lobby',
  ['lobby.outside_ready_zone'] = 'Va ate o ponto de largada para confirmar',
  ['lobby.training_badge']   = 'MODO TREINO',

  -- ── Race ────────────────────────────────────────────────────────────────
  ['race.cp_label']          = 'CP %d',
  ['race.cp_distance_km']    = '%.2f KM',
  ['race.cp_distance_m']     = '%d M',
  ['race.lap']               = 'VOLTA',
  ['race.lap_x_of_y']        = '%d/%d',
  ['race.position']          = 'POSICAO',
  ['race.position_x_of_y']   = '%d/%d',
  ['race.record']            = 'Recorde',
  ['race.next_cp']           = 'PROXIMO CP',
  ['race.you_finished']      = 'Voce cruzou a linha de chegada',
  ['race.finished_pos']      = 'Voce terminou em #%d',
  ['race.dnf']               = 'Voce nao terminou (DNF)',
  ['race.aborted']           = 'Corrida abandonada (%s)',
  ['race.left_vehicle']      = 'Voce abandonou o veiculo',
  ['race.died']              = 'Voce morreu durante a corrida',
  ['race.payout']            = 'Premio: R$ %s',
  ['race.timeout']           = 'Tempo limite esgotado',
  ['race.go']                = 'GO!',
  ['race.training_no_reward'] = 'Modo treino: sem premio',

  -- ── Police ──────────────────────────────────────────────────────────────
  ['police.alert_title']     = 'Racha ilegal reportado',
  ['police.alert_body']      = 'Atividade ilegal em %s (%s).',
  ['police.blip_label']      = 'Racha ilegal — %s',

  -- ── Errors ─────────────────────────────────────────────────────────────
  ['err.unknown']            = 'Erro desconhecido',
  ['err.track_not_found']    = 'Pista nao encontrada',
  ['err.forbidden']          = 'Operacao nao permitida',
  ['err.lobby_closed']       = 'Esse lobby ja foi iniciado',
  ['err.not_confirmed']      = 'Voce nao confirmou presenca',
  ['err.bad_payload']        = 'Pedido invalido',
  ['err.cp_invalidated']     = 'Checkpoint invalidado pelo servidor (%s)',

  -- ── Editor ─────────────────────────────────────────────────────────────
  ['editor.welcome']         = 'Editor de pistas ativo',
  ['editor.need_vehicle']    = 'Entre em um veiculo para editar',
  ['editor.no_permission']   = 'Sem permissao para editor',
  ['editor.phase_grid']      = 'FASE 1: Posicione os carros da largada',
  ['editor.phase_grid_help'] = '[E] / Buzina = salvar slot   [G] = proxima fase',
  ['editor.phase_cps']       = 'FASE 2: Dirija marcando checkpoints',
  ['editor.phase_cps_help']  = '[E] = adicionar CP   [T] = remover ultimo   [G] = finalizar',
  ['editor.phase_meta']      = 'FASE 3: Preencha os metadados no painel',
  ['editor.grid_saved']      = 'Slot %d salvo',
  ['editor.cp_saved']        = 'CP %d salvo',
  ['editor.undo']            = 'Ultimo CP removido (restam %d)',
  ['editor.saved']           = 'Pista "%s" salva (%d CPs, %d slots)',
  ['editor.discarded']       = 'Edicao descartada',
  ['editor.id_invalid']      = 'ID invalido',
  ['editor.id_conflict']     = 'Esse ID e do config (use outro)',
  ['editor.id_taken']        = 'Esse ID pertence a outro criador',
  ['editor.need_grid']       = 'Adicione pelo menos 1 slot de grade',
  ['editor.need_cps']        = 'Adicione pelo menos 1 checkpoint',
  ['editor.max_cps']         = 'Maximo de checkpoints atingido',
  ['editor.max_grid']        = 'Maximo de slots atingido',

  -- ── Notify (toast) ─────────────────────────────────────────────────────
  ['Modo de treino']   = 'Modo treino: sem ranking nem premio',
  ['Mode de ranqued']     = 'Corrida rankeada — boa sorte!',
}

-- Tradutor com interpolacao: t('lobby.starting_in_sec', { 5 }) → 'Largada em 5 s'
-- Aceita tanto array { 5 } quanto map { sec = 5 } (string.format simples).
function L.t(key, args)
  local s = L.strings[tostring(key)]
  if not s then return tostring(key) end
  if type(args) ~= 'table' then return s end
  -- Array de args para string.format
  if #args > 0 then
    local ok, out = pcall(string.format, s, table.unpack(args))
    return ok and out or s
  end
  return s
end
