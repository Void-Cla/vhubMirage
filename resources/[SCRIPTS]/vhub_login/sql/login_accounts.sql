-- login_accounts — credencial de conta (username/senha) do vhub_login.
-- Camada ACIMA do uid identifier-based do core: NÃO duplica identidade, apenas
-- anexa um par username/senha a um user_id já resolvido pelo core (L-04 OK).
-- Sem FK física para vh_users (resource externo não acopla DDL ao core frozen) —
-- a amarra user_id→vh_users(id) é validada em runtime.

CREATE TABLE IF NOT EXISTS login_accounts (
  account_id  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED  NOT NULL,                -- = vh_users.id (1 license/uid)
  username    VARCHAR(32)   NOT NULL,
  pass_hash   CHAR(64)      NOT NULL,                 -- SHA-256 hex de (salt || senha)
  salt        CHAR(32)      NOT NULL,
  status      TINYINT       NOT NULL DEFAULT 1,       -- 1=ativa, 0=bloqueada
  created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login  DATETIME      NULL,
  PRIMARY KEY (account_id),
  UNIQUE KEY uq_username (username),
  UNIQUE KEY uq_user_id  (user_id)                    -- 1 conta por license/uid
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
