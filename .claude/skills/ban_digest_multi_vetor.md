# Skill — Ban multi-vetor com digest BINARY(32)

> Validado em: ADR #86/#87/#88 — domínio crítico auth/ban
> Owner de referência: `vhub_login` → `server/dominio/contas.lua` (`verificarBan`/`registrarBan`)
> Gate: segurança + persistência (1× em domínio crítico = criar imediatamente)

## Quando usar

Toda vez que gravar ou checar ban por identificador sensível (IP, e-mail, telefone).
Nunca guardar IP/e-mail/whatsapp em plaintext — sempre digest pepper-derivado.

## A receita

```lua
-- ============================================================
-- DIGEST (server-only, nunca no client)
-- ============================================================

-- IP: SHA2 com pepper de escopo isolado
UNHEX(SHA2(CONCAT(ip, secret("ip")), 256))   -- BINARY(32)

-- E-mail / whatsapp: copiar o lookup materializado do row da conta
-- NUNCA re-derivar para comparação (ver Regras de ouro #2)
acc.email_lookup   -- já é BINARY(32) gravado no INSERT da conta

-- ============================================================
-- SCHEMA (tabela ban_vectors)
-- ============================================================
-- account_id INT UNSIGNED NULL   ← FK nullable, ON DELETE SET NULL
-- ip_lookup      BINARY(32) NULL
-- email_lookup   BINARY(32) NULL
-- whatsapp_lookup BINARY(32) NULL

-- ============================================================
-- CHECK PRÉ-AUTH (IP only, antes de criar sessão)
-- ============================================================
SELECT 1 FROM login_ban_vectors
WHERE ip_lookup = UNHEX(SHA2(CONCAT(ip, secret("ip")), 256))
  AND ativo = 1 LIMIT 1

-- ============================================================
-- CHECK PÓS-AUTH (IP + email + whatsapp após autenticar)
-- ============================================================
SELECT 1 FROM login_ban_vectors
WHERE (ip_lookup = ? OR email_lookup = ? OR whatsapp_lookup = ?)
  AND ativo = 1 LIMIT 1
-- parâmetros: ip_bin, acc.email_lookup, acc.whatsapp_lookup

-- ============================================================
-- GUARD antes do INSERT
-- ============================================================
if not ip_bin and not email_lookup and not whatsapp_lookup then
  return false, "sem_vetor"   -- ban inócuo proibido
end
```

## Regras de ouro

1. **IP nunca em plaintext** — sempre `UNHEX(SHA2(CONCAT(ip, secret("scope")), 256))` no servidor.
2. **Lookup materializado, nunca re-derivado** — copiar `acc.email_lookup`/`acc.whatsapp_lookup` do row; re-derivar com salt divergente é o bug histórico do `@dkey` (perdeu bans em produção).
3. **Dois momentos de check**: pré-auth (IP, antes de autenticar) + pós-auth (IP+email+whatsapp, após identidade confirmada).
4. **Guard `sem_vetor`** antes de qualquer `INSERT` — nunca gravar ban sem pelo menos um vetor.
5. **FK nullable** (`account_id NULL`, `ON DELETE SET NULL`) — ban sobrevive ao delete da conta.

## Anti-padrões

- `WHERE email_lookup = SHA2(email_raw, 256)` — re-derivação ignora pepper; lookup pode diferir → ban silenciosamente ineficaz.
- Gravar IP plaintext "para debug" — P0 imediato (`tools/guardiao.ps1` detecta).
- Ban apenas por `account_id` — conta deletada zera o ban.
- Check só pós-auth — jogador banido pode criar sessão antes de ser bloqueado.

## Teste / checklist

- [ ] Round-trip BINARY(32): `registrarBan(ip)` → `verificarBan(ip)` retorna banido com o **mesmo digest real** (não mock).
- [ ] Ban pré-conta funciona: ban por IP antes de conta existir; ao criar conta o ban pega.
- [ ] `sem_vetor` retorna `false` e não insere row.
- [ ] Delete da conta: `account_id` vira NULL, ban permanece ativo.
- [ ] Vetor único por tipo: dois bans no mesmo IP não duplicam row (upsert ou check EXISTS).
