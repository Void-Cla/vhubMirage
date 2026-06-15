#!/usr/bin/env bash
# guard_sql_danger.sh — bloqueia comandos SQL destrutivos antes da execução
# Exit 2 = bloquear + feed de erro para Claude | Exit 0 = permitir

INPUT=$(cat)

# Extrai o comando bash do payload JSON
if command -v python3 &>/dev/null; then
  CMD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  print(d.get('tool_input', {}).get('command', ''))
except:
  print('')
" 2>/dev/null)
else
  CMD=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
fi

# Padrões destrutivos bloqueados
BLOCKED_PATTERNS=(
  "DROP TABLE"
  "TRUNCATE TABLE"
  "DROP DATABASE"
  "DELETE FROM vh_users"
  "DELETE FROM vh_characters"
  "DELETE FROM vh_vehicles WHERE 1"
  "UPDATE vh_users SET"
  "git push --force"
  "git reset --hard HEAD~"
)

CMD_UPPER=$(echo "$CMD" | tr '[:lower:]' '[:upper:]')

for PATTERN in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$CMD_UPPER" | grep -q "$PATTERN"; then
    echo "BLOQUEADO [guard_sql_danger]: Operação destrutiva detectada: '$PATTERN'" >&2
    echo "Para executar manualmente: copie o comando e rode diretamente no terminal." >&2
    exit 2
  fi
done

exit 0
