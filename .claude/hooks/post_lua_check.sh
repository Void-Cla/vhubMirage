#!/usr/bin/env bash
# post_lua_check.sh — verifica violações de qualidade após escrita de arquivo .lua
# Exit 2 = avisar Claude (não bloqueia) | Exit 0 = sem problemas

INPUT=$(cat)

# Extrai o caminho do arquivo escrito
if command -v python3 &>/dev/null; then
  FILE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  print(d.get('tool_input', {}).get('file_path', ''))
except:
  print('')
" 2>/dev/null)
else
  FILE=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | cut -d'"' -f4)
fi

# Só verifica arquivos .lua
if ! echo "$FILE" | grep -qE "\.lua$"; then
  exit 0
fi

# Arquivo não existe ainda
[ ! -f "$FILE" ] && exit 0

ISSUES=""
WARNINGS=""

# L-01/L-12: SQL inline fora de sql.lua/state.lua no CORE
if echo "$FILE" | grep -q "resources/\[CORE\]/vhub/"; then
  if ! echo "$FILE" | grep -qE "(sql\.lua|state\.lua|bootstrap\.lua)"; then
    if grep -qn "oxmysql\|MySQL\.\|S:prepare\|S:query" "$FILE"; then
      ISSUES="$ISSUES\n  ❌ SQL inline no CORE fora de sql.lua/state.lua (L-12)"
    fi
  fi
fi

# L-08: print() fora de logger.lua/bootstrap.lua
if ! echo "$FILE" | grep -qE "(logger\.lua|bootstrap\.lua|base\.lua)"; then
  if grep -Pqn "^\s*print\s*\(" "$FILE"; then
    ISSUES="$ISSUES\n  ❌ print() direto: usar vHub.Logger (L-08)"
  fi
fi

# L-06: while true do sem Citizen.Wait visível
if grep -Pqn "while\s+true\s+do" "$FILE"; then
  if ! grep -qn "Citizen\.Wait\|Wait(" "$FILE"; then
    WARNINGS="$WARNINGS\n  ⚠️  while true sem Citizen.Wait detectado (L-06)"
  fi
fi

# L-10: funções públicas sem comentário PT-BR acima
# (heurística simples: function M: sem -- acima)
UNCOMMENTED=$(grep -Pn "^function [A-Z]\w+:" "$FILE" | while IFS= read -r line; do
  LINENUM=$(echo "$line" | cut -d: -f1)
  PREV=$((LINENUM - 1))
  if [ "$PREV" -gt 0 ]; then
    PREV_LINE=$(sed -n "${PREV}p" "$FILE")
    if ! echo "$PREV_LINE" | grep -q "^--"; then
      echo "  linha $LINENUM"
    fi
  fi
done)
if [ -n "$UNCOMMENTED" ]; then
  WARNINGS="$WARNINGS\n  ⚠️  Funções públicas sem comentário PT-BR (L-10):$UNCOMMENTED"
fi

# Reportar
if [ -n "$ISSUES" ]; then
  echo -e "VIOLAÇÕES em $FILE:$ISSUES" >&2
  echo -e "Corrija antes de commitar." >&2
  exit 2
fi

if [ -n "$WARNINGS" ]; then
  echo -e "AVISOS em $FILE:$WARNINGS" >&2
fi

exit 0
