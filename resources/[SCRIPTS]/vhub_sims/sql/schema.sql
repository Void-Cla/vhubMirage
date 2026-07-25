CREATE TABLE IF NOT EXISTS vhub_sims_outfits (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  char_id INT UNSIGNED NOT NULL,
  label VARCHAR(48) NOT NULL,
  outfit BLOB NOT NULL,
  group_name VARCHAR(32) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_sims_outfits_char (char_id),
  CONSTRAINT fk_sims_outfits_char FOREIGN KEY (char_id) REFERENCES vh_characters(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vhub_sims_sagas (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  char_id INT UNSIGNED NOT NULL,
  request_id VARCHAR(96) NOT NULL,
  session_id VARCHAR(96) NOT NULL,
  mode VARCHAR(16) NOT NULL,
  state ENUM('prepared','charged','customized','completed','refunded','manual_reconcile') NOT NULL,
  operation_id VARCHAR(96) DEFAULT NULL,
  payload MEDIUMTEXT NOT NULL,
  digest VARCHAR(64) NOT NULL,
  amount INT UNSIGNED NOT NULL DEFAULT 0,
  last_error VARCHAR(64) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sims_saga_request (request_id),
  UNIQUE KEY uq_sims_saga_session (char_id, session_id),
  KEY idx_sims_saga_recovery (state, mode),
  CONSTRAINT fk_sims_sagas_char FOREIGN KEY (char_id) REFERENCES vh_characters(id)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
