-- fix_duplicate_users.sql — Corrige users duplicados gerados pelo bug do _resolveUID
-- Execute UMA vez no phpMyAdmin ou via linha de comando antes de reiniciar o servidor.
-- ATENÇÃO: faça backup antes de rodar.
-- 
-- O bug criava múltiplos vh_users para o mesmo jogador porque cada conexão
-- gerava um novo id. Apenas o user que tem vh_user_data é o "real".
-- Os demais são fantasmas sem dados.

-- Passo 1: ver o diagnóstico antes de rodar
-- SELECT u.id, COUNT(d.user_id) as tem_dados, COUNT(i.user_id) as tem_ids
-- FROM vh_users u
-- LEFT JOIN vh_user_data d ON d.user_id = u.id
-- LEFT JOIN vh_user_ids  i ON i.user_id = u.id
-- GROUP BY u.id
-- ORDER BY u.id;

-- Passo 2: apaga users fantasmas
-- (users sem nenhum identifier vinculado E sem nenhum dado)
DELETE u FROM vh_users u
LEFT JOIN vh_user_ids  i ON i.user_id = u.id
LEFT JOIN vh_user_data d ON d.user_id = u.id
WHERE i.user_id IS NULL
  AND d.user_id IS NULL;

-- Passo 3: reconfirma
SELECT 
  COUNT(*) AS users_restantes,
  MIN(id)  AS menor_id,
  MAX(id)  AS maior_id
FROM vh_users;

-- Passo 4: após rodar este script, o vHub vai re-seed o alocador
-- corretamente na próxima inicialização e não vai mais criar duplicados.
