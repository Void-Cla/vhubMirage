-- ============================================================
-- vhub_coinshop — INSTALL/SQL/drop.sql
-- Remove todas as tabelas do recurso (NÃO remove moedas CData nem settings GData,
-- que vivem no KV do core vHub — para limpá-los, use exports.vhub:deleteCData).
-- Use apenas em ambiente de DEV para reset completo do coinshop.
-- ============================================================

DROP TABLE IF EXISTS `vhub_coinshop_redeems`;
DROP TABLE IF EXISTS `vhub_coinshop_pix_tx`;
DROP TABLE IF EXISTS `vhub_coinshop_codes`;
DROP TABLE IF EXISTS `vhub_coinshop_deals`;
DROP TABLE IF EXISTS `vhub_coinshop_purchases`;
DROP TABLE IF EXISTS `vhub_coinshop_categories`;
DROP TABLE IF EXISTS `vhub_coinshop_items`;

-- Para limpar moedas de todos os personagens (CData key 'coinshop_coins'):
--   DELETE FROM vh_character_data WHERE dkey = 'coinshop_coins';
-- Para limpar settings globais de UI (GData key 'coinshop_ui_settings'):
--   DELETE FROM vh_global_data WHERE dkey = 'coinshop_ui_settings';
