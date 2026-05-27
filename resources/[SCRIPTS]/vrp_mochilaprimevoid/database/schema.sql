-- Schema completo para void_mochila_prime

CREATE TABLE IF NOT EXISTS vrp_inventario_itens (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    serialkey VARCHAR(64) UNIQUE NOT NULL,
    user_id INT NOT NULL,
    item_name VARCHAR(60) NOT NULL,
    quantidade INT NOT NULL DEFAULT 1,
    peso_total DECIMAL(10,2) GENERATED ALWAYS AS (quantidade * 0.5) STORED,
    tipo_armazenamento ENUM('mochila','bau_veiculo','bau_faccao','marketplace') DEFAULT 'mochila',
    container_id VARCHAR(60),
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_alteracao TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    checksum VARCHAR(64),
    KEY idx_user (user_id),
    KEY idx_serialkey (serialkey),
    KEY idx_item_name (item_name),
    KEY idx_container (container_id),
    KEY idx_deleted (deleted_at),
    CONSTRAINT fk_user_inventario FOREIGN KEY (user_id) REFERENCES vrp_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vrp_inventario_transacoes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(64) UNIQUE NOT NULL,
    user_id INT NOT NULL,
    tipo_operacao ENUM('adicionar','remover','transferir','vender','comprar','dropar','recuperar','compra_loja','venda_loja') NOT NULL,
    item_name VARCHAR(60) NOT NULL,
    quantidade INT NOT NULL,
    serialkeys_envolvidas JSON,
    dados_transacao JSON,
    status ENUM('pendente','completa','falhada','revertida') DEFAULT 'pendente',
    erro_descricao TEXT,
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_conclusao TIMESTAMP NULL,
    KEY idx_user (user_id),
    KEY idx_transaction (transaction_id),
    KEY idx_status (status),
    KEY idx_tipo (tipo_operacao),
    CONSTRAINT fk_user_transacoes FOREIGN KEY (user_id) REFERENCES vrp_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vrp_inventario_auditoria (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(64) NOT NULL,
    user_id INT,
    acao VARCHAR(255) NOT NULL,
    detalhes JSON,
    ip_origem VARCHAR(45),
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_transaction (transaction_id),
    KEY idx_user (user_id),
    KEY idx_acao (acao),
    CONSTRAINT fk_audit_trans FOREIGN KEY (transaction_id) REFERENCES vrp_inventario_transacoes(transaction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vrp_inventario_marketplace (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    marketplace_id VARCHAR(64) UNIQUE NOT NULL,
    seller_id INT NOT NULL,
    seller_name VARCHAR(120) NOT NULL,
    item_name VARCHAR(60) NOT NULL,
    quantidade INT NOT NULL,
    preco INT NOT NULL,
    descricao VARCHAR(200),
    serialkeys_anunciadas JSON,
    comprador_id INT,
    data_venda TIMESTAMP NULL,
    status ENUM('ativo','vendido','cancelado') DEFAULT 'ativo',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_seller (seller_id),
    KEY idx_item (item_name),
    KEY idx_status (status),
    KEY idx_marketplace_id (marketplace_id),
    CONSTRAINT fk_seller FOREIGN KEY (seller_id) REFERENCES vrp_users(id),
    CONSTRAINT fk_comprador FOREIGN KEY (comprador_id) REFERENCES vrp_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vrp_lojas (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    loja_id VARCHAR(60) UNIQUE NOT NULL,
    nome VARCHAR(120) NOT NULL,
    descricao TEXT,
    proprietario VARCHAR(120),
    localizacao_x DECIMAL(10, 2) NOT NULL,
    localizacao_y DECIMAL(10, 2) NOT NULL,
    localizacao_z DECIMAL(10, 2) NOT NULL,
    raio_atuacao INT DEFAULT 3,
    tipo_loja ENUM('mercearia','farmacia','armas','veiculo','roupa','bar','padaria','general') DEFAULT 'general',
    saldo_caixa INT DEFAULT 0,
    ativa TINYINT(1) DEFAULT 1,
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_loja_id (loja_id),
    KEY idx_tipo (tipo_loja),
    KEY idx_ativa (ativa)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vrp_lojas_itens (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    loja_id VARCHAR(60) NOT NULL,
    item_name VARCHAR(60) NOT NULL,
    preco_compra INT NOT NULL,
    preco_venda INT,
    estoque_atual INT DEFAULT 0,
    estoque_maximo INT DEFAULT 999,
    desconto_percentual INT DEFAULT 0,
    ativo TINYINT(1) DEFAULT 1,
    data_atualizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_loja (loja_id),
    KEY idx_item (item_name),
    CONSTRAINT fk_loja_item FOREIGN KEY (loja_id) REFERENCES vrp_lojas(loja_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS vrp_lojas_vendas (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    venda_id VARCHAR(64) UNIQUE NOT NULL,
    loja_id VARCHAR(60) NOT NULL,
    user_id INT NOT NULL,
    item_name VARCHAR(60) NOT NULL,
    quantidade INT NOT NULL,
    preco_unitario INT NOT NULL,
    preco_total INT NOT NULL,
    tipo_transacao ENUM('compra','venda') NOT NULL,
    data_venda TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_loja (loja_id),
    KEY idx_user (user_id),
    KEY idx_tipo (tipo_transacao),
    CONSTRAINT fk_loja_venda FOREIGN KEY (loja_id) REFERENCES vrp_lojas(loja_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;