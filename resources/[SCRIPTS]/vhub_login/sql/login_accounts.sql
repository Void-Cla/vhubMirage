-- login_accounts — credencial, contatos cifrados e consentimento do vhub_login.
-- Camada ACIMA do uid identifier-based do core: NÃO duplica identidade, apenas
-- anexa um par username/senha a um user_id já resolvido pelo core (L-04 OK).
-- Sem FK física para vh_users (resource externo não acopla DDL ao core frozen) —
-- a amarra user_id→vh_users(id) é validada em runtime.

CREATE TABLE IF NOT EXISTS login_accounts (
  account_id  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED  NOT NULL,                -- = vh_users.id (1 license/uid)
  username    VARCHAR(32)   NOT NULL,
  pass_hash   VARCHAR(255)  NOT NULL,
  salt        CHAR(32)      NOT NULL,
  hash_version SMALLINT UNSIGNED NOT NULL DEFAULT 2,
  email_cipher VARBINARY(512) NULL,
  email_lookup BINARY(32) NULL,
  whatsapp_cipher VARBINARY(256) NULL,
  whatsapp_lookup BINARY(32) NULL,
  terms_version VARCHAR(32) NULL,
  terms_accepted_at DATETIME(3) NULL,
  age_18      TINYINT(1)    NULL,
  last_ip_digest BINARY(32) NULL,
  status      TINYINT       NOT NULL DEFAULT 1,       -- 1=ativa, 0=bloqueada
  created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login  DATETIME      NULL,
  last_seen_at DATETIME     NULL,
  PRIMARY KEY (account_id),
  UNIQUE KEY uq_username (username),
  UNIQUE KEY uq_user_id  (user_id),                   -- 1 conta por license/uid
  UNIQUE KEY uq_email_lookup (email_lookup),
  UNIQUE KEY uq_whatsapp_lookup (whatsapp_lookup)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ban_vectors — vetores de banimento multi-canal (L-04: escritor único = vhub_login).
-- Digests derivados via secret(scope) interno de contas.lua — nunca em claro.
-- account_id nullable: ban pode existir antes de conta criada (ban por IP de entrada).
-- identifier_digest: UNHEX(SHA2(CONCAT(raw_identifier, secret("identifier")), 256))
--   cobre license:, steam:, discord:, fivem: e hardware tokens do FiveM — um INSERT por vetor.
CREATE TABLE IF NOT EXISTS login_ban_vectors (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  account_id      INT UNSIGNED    NULL,
  ip_digest       BINARY(32)      NULL,       -- UNHEX(SHA2(CONCAT(ip, secret("ip")), 256))
  email_lookup    BINARY(32)      NULL,       -- copia de login_accounts.email_lookup
  whatsapp_lookup BINARY(32)      NULL,       -- copia de login_accounts.whatsapp_lookup
  identifier_digest BINARY(32)   NULL,       -- license/steam/discord/fivem/hardware token
  banned_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  banned_by       VARCHAR(64)     NOT NULL,   -- username do admin resolvido server-side
  reason          VARCHAR(255)    NOT NULL,
  expires_at      DATETIME        NULL,       -- NULL = permanente
  PRIMARY KEY (id),
  KEY idx_ban_ip           (ip_digest),
  KEY idx_ban_email        (email_lookup),
  KEY idx_ban_whatsapp     (whatsapp_lookup),
  KEY idx_ban_identifier   (identifier_digest),
  CONSTRAINT fk_ban_account FOREIGN KEY (account_id)
    REFERENCES login_accounts(account_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS login_account_schema_migrations (
  version     SMALLINT UNSIGNED NOT NULL,
  applied_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
