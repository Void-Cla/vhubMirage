-- ============================================================
-- vhub_coinshop — INSTALL/SQL/install.sql
-- Aplica o schema idempotente. Pode ser executado com segurança em produção.
-- Pré-requisito: o core vHub já deve ter criado `vh_characters` (FK resolvida).
-- ============================================================

SOURCE sql/schema.sql;

-- (o seed de categorias e itens padrão é aplicado automaticamente
--  pelo `server/init.lua` na primeira carga do resource — não é necessário
--  rodar manualmente)
