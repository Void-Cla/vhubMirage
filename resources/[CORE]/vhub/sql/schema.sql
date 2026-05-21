CREATE TABLE IF NOT EXISTS vh_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vh_user_ids (
  identifier VARCHAR(64) PRIMARY KEY,
  user_id INT NOT NULL,
  INDEX idx_vh_user_ids_user_id (user_id)
);

CREATE TABLE IF NOT EXISTS vh_characters (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_vh_characters_user_id (user_id)
);

CREATE TABLE IF NOT EXISTS vh_user_data (
  user_id INT NOT NULL,
  dkey VARCHAR(64) NOT NULL,
  dvalue MEDIUMBLOB,
  PRIMARY KEY(user_id, dkey)
);

CREATE TABLE IF NOT EXISTS vh_char_data (
  char_id INT NOT NULL,
  dkey VARCHAR(64) NOT NULL,
  dvalue MEDIUMBLOB,
  PRIMARY KEY(char_id, dkey)
);

CREATE TABLE IF NOT EXISTS vh_global_data (
  dkey VARCHAR(64) PRIMARY KEY,
  dvalue MEDIUMBLOB
);

CREATE TABLE IF NOT EXISTS vh_vehicles (
  plate VARCHAR(10) PRIMARY KEY,
  key_uid VARCHAR(64) DEFAULT NULL,
  INDEX idx_vh_vehicles_key_uid (key_uid)
);

CREATE TABLE IF NOT EXISTS vh_vehicle_data (
  plate VARCHAR(10) NOT NULL,
  dkey VARCHAR(64) NOT NULL,
  dvalue MEDIUMBLOB,
  PRIMARY KEY(plate, dkey)
);
