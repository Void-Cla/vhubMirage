-- schema.sql — vhub_df: meio de pagamento Pix (MercadoPago)
-- Aplicado de forma idempotente no boot do resource.

CREATE TABLE IF NOT EXISTS vhub_df_orders (
    id           INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    txid         VARCHAR(64)      NOT NULL,               -- payment_id do MercadoPago
    char_id      INT UNSIGNED     NOT NULL,               -- FK → vh_characters.id
    src          INT              NOT NULL,               -- player source no momento da criação
    product_key  VARCHAR(64)      NOT NULL,               -- chave opaca do produto (livre p/ consumidor)
    product_desc VARCHAR(120)     NOT NULL DEFAULT '',    -- descrição humana do produto
    amount_brl   DECIMAL(10,2)    NOT NULL,               -- valor cobrado em BRL
    metadata     TEXT             NULL,                   -- JSON livre (enviado pelo consumidor)
    status       ENUM('pending','approved','rejected','expired','cancelled')
                                  NOT NULL DEFAULT 'pending',
    created_at   DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   DATETIME         NOT NULL,
    paid_at      DATETIME         NULL,
    credited_at  DATETIME         NULL,                   -- quando a entrega foi confirmada
    PRIMARY KEY  (id),
    UNIQUE  KEY  uk_txid (txid),
    INDEX        ix_char_status (char_id, status),
    INDEX        ix_status_exp  (status, expires_at),
    CONSTRAINT   fk_df_char FOREIGN KEY (char_id)
        REFERENCES vh_characters (id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- log de auditoria imutável (append-only — nunca UPDATE/DELETE)
CREATE TABLE IF NOT EXISTS vhub_df_audit (
    id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    order_id   INT UNSIGNED  NOT NULL,
    txid       VARCHAR(64)   NOT NULL,
    event      VARCHAR(32)   NOT NULL,  -- 'created'|'approved'|'delivered'|'expired'|'error'
    actor      VARCHAR(64)   NOT NULL,  -- 'webhook'|'polling'|'admin'
    detail     TEXT          NULL,      -- JSON extra livre
    created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX ix_audit_order (order_id),
    INDEX ix_audit_txid  (txid)
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
