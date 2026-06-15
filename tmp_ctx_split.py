# -*- coding: utf-8 -*-
# tmp_ctx_split.py — manutenção de cap do contexto.md (2026-06-11)
# Passo 1: backup byte-idêntico + arquivos temáticos VERBATIM + medições.
import os

BASE = r"C:\vHUB Mirage\vhubMirage\.claude"
SRC = os.path.join(BASE, "contexto.md")
ARQ = os.path.join(BASE, "contexto_arquivo")
os.makedirs(ARQ, exist_ok=True)

raw = open(SRC, "rb").read()
print("original_bytes:", len(raw))

# ---- backup byte-idêntico ----
bk = os.path.join(ARQ, "contexto_completo_2026-06-11.md")
open(bk, "wb").write(raw)
assert open(bk, "rb").read() == raw, "BACKUP DIFERE DO ORIGINAL"
print("backup_ok_bytes:", os.path.getsize(bk))

text = raw.decode("utf-8")
lines = text.splitlines(keepends=True)
print("total_lines:", len(lines))


def sl(a, b):
    """fatia VERBATIM de linhas 1-based inclusivas"""
    return "".join(lines[a - 1:b])


def w(name, content):
    p = os.path.join(ARQ, name)
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(content)
    print("wrote:", name, os.path.getsize(p))


PROV = ("_Migrado VERBATIM de `.claude/contexto.md` em 2026-06-11 "
        "(manutenção de cap 20 KB; escritor: vhub_guardiao_revisao). "
        "Snapshot completo pré-manutenção: `contexto_completo_2026-06-11.md`._\n\n")

# ---- fatias temáticas (verbatim) ----
w("decisoes_07_a_22.md",
  "# Decisões congeladas 7–22 — texto integral\n\n" + PROV + sl(101, 148))
w("racha.md",
  "# vhub_racha — ownership e decisões de arquitetura (integral)\n\n" + PROV + sl(154, 183))
w("inventory.md",
  "# vhub_inventory — ownership, regras INV-2, riscos residuais e sprints (integral)\n\n" + PROV + sl(185, 213))
w("lspdtool_epico.md",
  "# vhub_lspdtool — épico LSPD-1..7 (integral)\n\n" + PROV + sl(215, 282))
w("velo.md",
  "# vhub_velo — decisão SEPARAR, invariante L-04, contrato NUI e sprints (integral)\n\n" + PROV + sl(284, 312))
w("veiculos_conce_ferinha_vehcontrol.md",
  "# vhub_conce / vhub_ferinha / vhub_vehcontrol — reorg veículos (integral)\n\n" + PROV + sl(316, 355))
w("contratos_api.md",
  "# Contratos de API pública (integral)\n\n" + PROV + sl(359, 469))
w("frozen_core_sprints.md",
  "# Status das sprints + ferramentas + próximos passos + Estado de congelamento (integral)\n\n"
  + PROV + sl(473, 499) + "\n" + sl(503, 514) + "\n" + sl(528, len(lines)))

# ---- medições para calibrar o contexto.md enxuto ----
enc = lambda s: len(s.encode("utf-8"))
print("MED sl(1,1) titulo:", enc(sl(1, 1)))
print("MED sl(3,92) identidade..riscos:", enc(sl(3, 92)))
print("MED sl(65,90) riscos table:", enc(sl(65, 90)))
print("MED sl(95,100) decisoes 1-6:", enc(sl(95, 100)))
print("MED sl(516,524) bloqueios:", enc(sl(516, 524)))
print("MED sl(27,46) ownership core table:", enc(sl(27, 46)))

# eco de fronteiras para validar fatias
for n in (101, 148, 154, 183, 185, 213, 215, 282, 284, 312, 316, 355, 359, 469, 473, 499, 503, 514, 516, 524, 528):
    print("L%d: %s" % (n, lines[n - 1][:70].rstrip()))
