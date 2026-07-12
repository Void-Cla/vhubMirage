#!/usr/bin/env bash
# session_lifecycle_hint.sh v1 — heurística de gestão de contexto (UserPromptSubmit)
# Objetivo: Claude precisa DECIDIR entre /clear (troca de assunto) e /compact (mesma
# tarefa, contexto grande) em vez de deixar a sessão crescer até o auto-compact (~95%).
# Não bloqueia nada (sempre exit 0) — só injeta uma dica em texto puro no contexto.
# Formato de saída: texto puro (não JSON) — evita bug conhecido do hookSpecificOutput
# na primeira mensagem de sessão nova (Claude Code issue #17550).

set -euo pipefail

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null || true)
TRANSCRIPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$PROJECT_DIR/.claude/.session_state"
mkdir -p "$STATE_DIR"
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('session_id','default'))
except Exception:
    print('default')
" 2>/dev/null || echo default)
KEYWORDS_FILE="$STATE_DIR/${SESSION_ID}_keywords.txt"

# ── 1. Tamanho do transcript como proxy de tokens (~4 bytes/token) ──────────
BYTES=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  BYTES=$(wc -c < "$TRANSCRIPT" | tr -d ' ')
fi
# thresholds calibrados p/ contexto ~200k tokens padrão:
# ~400KB  ≈ 100k tokens (aviso leve)   ~600KB ≈ 150k tokens (aviso forte)
WATCH=400000
HIGH=600000

# ── 2. Extrair palavras-chave do prompt atual (PT-BR, sem stopwords) ───────
NEW_KW=$(printf '%s' "$PROMPT" | python3 -c "
import sys, re
stop = {'para','como','esse','essa','isso','aquele','aquela','sobre','onde','quando',
        'porque','ainda','tambem','também','depois','antes','dessa','desse','fazer',
        'preciso','quero','pode','poderia','estou','está','esta','sendo','tudo','muito',
        'mais','menos','entao','então','agora','aqui','você','voce','claude'}
text = sys.stdin.read().lower()
words = re.findall(r'[a-zà-ú_]{4,}', text)
kw = sorted(set(w for w in words if w not in stop))[:40]
print(' '.join(kw))
" 2>/dev/null || true)

OLD_KW=""
[ -f "$KEYWORDS_FILE" ] && OLD_KW=$(cat "$KEYWORDS_FILE")

# ── 3. Overlap (Jaccard aproximado) ─────────────────────────────────────────
OVERLAP_PCT=100
if [ -n "$OLD_KW" ] && [ -n "$NEW_KW" ]; then
  OVERLAP_PCT=$(python3 -c "
old = set('''$OLD_KW'''.split())
new = set('''$NEW_KW'''.split())
if not old or not new:
    print(100)
else:
    inter = len(old & new)
    union = len(old | new)
    print(int(100 * inter / union) if union else 100)
" 2>/dev/null || echo 100)
fi

# persiste keywords atuais para a próxima chamada
printf '%s' "$NEW_KW" > "$KEYWORDS_FILE"

# ── 4. Decisão ───────────────────────────────────────────────────────────────
if [ "$BYTES" -ge "$HIGH" ] && [ "$OVERLAP_PCT" -lt 15 ]; then
  echo "[gestao-sessao] Contexto grande (~${BYTES} bytes de transcript) + prompt parece ser assunto novo (overlap ${OVERLAP_PCT}% com o anterior). Antes de continuar: avise o usuário que este é um bom ponto para '/clear' (reset total) em vez de acumular mais contexto, a menos que a continuidade da tarefa anterior seja necessária."
elif [ "$BYTES" -ge "$HIGH" ]; then
  echo "[gestao-sessao] Contexto grande (~${BYTES} bytes de transcript), mesma linha de trabalho (overlap ${OVERLAP_PCT}%). Sugira '/compact foco na tarefa atual' ao usuário antes de prosseguir, em vez de esperar o auto-compact."
elif [ "$BYTES" -ge "$WATCH" ] && [ "$OVERLAP_PCT" -lt 15 ]; then
  echo "[gestao-sessao] Prompt parece trocar de assunto (overlap ${OVERLAP_PCT}%) e a sessão já acumulou contexto moderado. Se a tarefa anterior está mesmo encerrada, considere sugerir '/clear'."
fi

exit 0
