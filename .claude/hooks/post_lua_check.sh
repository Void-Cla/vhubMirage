#!/usr/bin/env bash
# post_lua_check.sh v2 — enforcement mecânico das leis (PostToolUse: Write|Edit|MultiEdit)
# Exit 2 = BLOQUEIA e devolve erro ao Claude | Exit 0 = passa (avisos vão no stderr)
# Cobre os padrões que JÁ furaram o projeto (auditoria 2026-06): L-13, L-15, L-14, L-16, L-17 + L-06/10/12.

INPUT=$(cat)

FILE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  ti = d.get('tool_input', {})
  print(ti.get('file_path') or ti.get('path') or '')
except Exception:
  print('')
" 2>/dev/null)

case "$FILE" in *.lua) ;; *) exit 0 ;; esac
[ -f "$FILE" ] || exit 0

ISSUES=""; WARNINGS=""
add_issue(){ ISSUES="$ISSUES\n  ❌ $1"; }
add_warn(){  WARNINGS="$WARNINGS\n  ⚠️  $1"; }

IS_CORE=0
case "$FILE" in *"resources/[CORE]/vhub/"*) IS_CORE=1 ;; esac

# ── L-13 (BLOQUEANTE): escrita de persistência fora do CORE ────────────────
if [ "$IS_CORE" -eq 0 ]; then
  HITS=$(grep -nE "set(V|U|C|G)Data\s*\(" "$FILE" | grep -v "commitVehicleState" || true)
  if [ -n "$HITS" ]; then
    add_issue "L-13: set*Data fora do CORE — use o contrato de commit (ex.: exports.vhub:commitVehicleState):\n$HITS"
  fi
fi

# ── L-14: getVHub em script (somente-leitura transitório) ───────────────────
if [ "$IS_CORE" -eq 0 ] && grep -qE "getVHub\s*\(" "$FILE"; then
  if grep -nE "getVHub" -A3 "$FILE" | grep -qE "\.state\s*[\.\[].*=|_sessions|setVData|setUData|setCData|setGData|grantPerm"; then
    add_issue "L-14: mutação de internos do kernel via getVHub() — proibido"
  else
    add_warn "L-14: getVHub() detectado — somente leitura; migrar para export dedicado"
  fi
fi

# ── L-15 (BLOQUEANTE): órfão do manifest + módulo-fantasma + lixo vendor ────
RES_DIR="$FILE"
MANIFEST=""
while [ "$RES_DIR" != "/" ] && [ "$RES_DIR" != "." ] && [ -n "$RES_DIR" ]; do
  RES_DIR=$(dirname "$RES_DIR")
  if [ -f "$RES_DIR/fxmanifest.lua" ]; then MANIFEST="$RES_DIR/fxmanifest.lua"; break; fi
done
BASE=$(basename "$FILE")
if [ -n "$MANIFEST" ] && [ "$BASE" != "fxmanifest.lua" ]; then
  REL="${FILE#"$RES_DIR"/}"
  FOUND=0
  # padrões citados no manifest (suporta globs: server/*.lua, **/*.lua)
  while IFS= read -r PAT; do
    [ -z "$PAT" ] && continue
    GLOB=$(echo "$PAT" | sed 's/\*\*/\*/g')
    case "$REL" in $GLOB) FOUND=1; break ;; esac
  done < <(grep -oE "['\"][^'\"]+\.lua['\"]" "$MANIFEST" | tr -d "'\"")
  if [ "$FOUND" -eq 0 ]; then
    add_issue "L-15: '$REL' não é referenciado por $MANIFEST — código morto: referencie no manifest ou delete no mesmo commit"
  fi
fi
# módulo-fantasma: interface depende do return top-level (sem global/exports/handlers)
if grep -qE "^return\s+[A-Za-z_]" "$FILE"; then
  if ! grep -qE "(vHub\.[A-Za-z_]+\s*=|exports\s*\(|RegisterNetEvent|AddEventHandler|RegisterNUICallback|RegisterCommand)" "$FILE"; then
    add_issue "L-15: módulo-fantasma — interface só via 'return' top-level; loader de manifest descarta o valor"
  fi
fi
if grep -qE "os\.exit\s*\(|PerformHttpRequest\s*\(\s*['\"]https?://" "$FILE"; then
  case "$FILE" in *"[TOOLS]"*) : ;; *) add_issue "L-15/Segurança: os.exit()/HTTP externo em runtime de produção — proibido (vendor anti-tamper já derrubou histórico)" ;; esac
fi

# ── L-16: escrita de spawn fora do owner (aviso com allowlist) ───────────────
case "$FILE" in
  *vhub_player_state/client.lua|*"[CORE]/vhub/client/bootstrap.lua"|*vhub_admin/*) : ;;
  *)
    if grep -qE "SetPlayerModel\s*\(|NetworkResurrectLocalPlayer\s*\(" "$FILE"; then
      add_warn "L-16: escrita de ped (model/resurrect) fora do owner vhub_player_state — UI devolve coordenada via spawnAt"
    fi
    if grep -qE "SetEntityCoords(NoOffset)?\s*\(\s*PlayerPedId" "$FILE"; then
      add_warn "L-16: SetEntityCoords no próprio ped fora do owner — use exports.vhub_player_state:teleport/spawnAt"
    fi ;;
esac

# ── L-17: handler institucional sem replay-guard (aviso) ────────────────────
if grep -qE "AddEventHandler\(\s*['\"]vHub:(playerSpawn|characterLoad)['\"]" "$FILE"; then
  if ! grep -qE "spawns|replay|_spawn_seen|idempot" "$FILE"; then
    add_warn "L-17: handler de vHub:playerSpawn/characterLoad sem replay-guard — CORE re-dispara em onResourceStart de QUALQUER resource"
  fi
fi

# ── L-12: SQL inline no CORE fora de sql/state ───────────────────────────────
if [ "$IS_CORE" -eq 1 ]; then
  case "$FILE" in
    *sql.lua|*state.lua|*bootstrap.lua) : ;;
    *) if grep -qnE "oxmysql|MySQL\.|S:prepare|S:query" "$FILE"; then
         add_issue "L-12: SQL inline no CORE fora de sql.lua/state.lua"
       fi ;;
  esac
fi

# ── L-06: while true sem Wait na MESMA região (heurística por bloco) ────────
while IFS=: read -r LN _; do
  [ -z "$LN" ] && continue
  if ! sed -n "${LN},$((LN+12))p" "$FILE" | grep -qE "Citizen\.Wait|[^A-Za-z]Wait\s*\("; then
    add_warn "L-06: while true na linha $LN sem Wait nas 12 linhas seguintes"
  fi
done < <(grep -nE "while\s+true\s+do" "$FILE" || true)

# ── L-08/L-10: print fora de logger; função pública sem comentário ──────────
case "$FILE" in
  *logger.lua|*bootstrap.lua|*base.lua|*test_runner.lua) : ;;
  *) grep -qE "^\s*print\s*\(" "$FILE" && add_warn "print() direto — usar vHub.Logger (exceto logger/bootstrap)" ;;
esac
UNC=$(grep -nE "^function [A-Z][A-Za-z_]*[:.]" "$FILE" | while IFS=: read -r LN _; do
  P=$((LN-1)); [ "$P" -gt 0 ] && ! sed -n "${P}p" "$FILE" | grep -q "^--" && echo "  linha $LN"
done)
[ -n "$UNC" ] && add_warn "L-10: funções públicas sem comentário PT-BR:\n$UNC"

# ── Veredito ─────────────────────────────────────────────────────────────────
if [ -n "$ISSUES" ]; then
  echo -e "VIOLAÇÕES BLOQUEANTES em $FILE:$ISSUES" >&2
  [ -n "$WARNINGS" ] && echo -e "Avisos:$WARNINGS" >&2
  echo -e "Corrija e regrave. Leis: ver CLAUDE.md." >&2
  exit 2
fi
[ -n "$WARNINGS" ] && echo -e "AVISOS em $FILE:$WARNINGS" >&2
exit 0
