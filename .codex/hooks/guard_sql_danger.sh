#!/usr/bin/env bash
# guard_sql_danger.sh v2 — bloqueia SQL/git destrutivo antes da execução (PreToolUse: Bash)
# Exit 2 = bloquear + erro para Claude | Exit 0 = permitir

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  print(d.get('tool_input', {}).get('command', ''))
except Exception:
  print('')
" 2>/dev/null)

CMD_UPPER=$(echo "$CMD" | tr '[:lower:]' '[:upper:]')

BLOCKED=(
  "DROP TABLE" "DROP DATABASE" "TRUNCATE TABLE" "DROP COLUMN"
  "DELETE FROM VH_USERS" "DELETE FROM VH_CHARACTERS"
  "DELETE FROM VH_VEHICLES" "DELETE FROM VH_VEHICLE_DATA"
  "DELETE FROM VHUB_VEHICLES"
  "UPDATE VH_USERS SET" "ALTER TABLE VH_"
  "GIT PUSH --FORCE" "GIT RESET --HARD HEAD~" "GIT CLEAN -F"
  "RM -RF RESOURCES" "RM -RF .CLAUDE"
)

for PATTERN in "${BLOCKED[@]}"; do
  if echo "$CMD_UPPER" | grep -qF "$PATTERN"; then
    echo "BLOQUEADO [guard_sql_danger]: padrão destrutivo '$PATTERN'." >&2
    echo "Operações destrutivas só manualmente no terminal, fora do agente." >&2
    exit 2
  fi
done
exit 0
