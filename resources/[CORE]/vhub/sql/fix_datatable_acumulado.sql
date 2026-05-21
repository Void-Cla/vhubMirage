-- fix_datatable_acumulado.sql
-- Limpa o datatable corrompido (acumulado) do banco.
-- Execute UMA VEZ no phpMyAdmin antes de reiniciar o servidor.
-- Após isso, o servidor recria o datatable limpo no próximo login.

-- Apaga o datatable de TODOS os usuários (será recriado limpo no próximo login)
DELETE FROM vh_user_data WHERE dkey = 'datatable';

-- Confirma limpeza
SELECT COUNT(*) AS datatables_restantes FROM vh_user_data WHERE dkey = 'datatable';
