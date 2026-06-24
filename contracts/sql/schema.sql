-- ============================================================
-- Lawang Contracts — esquema MySQL
-- Ejecutar una vez en phpMyAdmin (Hostinger) sobre la BD del proyecto.
-- ============================================================

-- Agentes que pueden generar contratos (sin auto-registro; alta manual)
CREATE TABLE IF NOT EXISTS agents (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name          VARCHAR(120)  NOT NULL,
  email         VARCHAR(160)  NOT NULL,
  password_hash VARCHAR(255)  NOT NULL,
  role          ENUM('admin','agent') NOT NULL DEFAULT 'agent',
  active        TINYINT(1)    NOT NULL DEFAULT 1,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_agents_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Contratos generados (metadatos + ruta al PDF en private/contratos/)
CREATE TABLE IF NOT EXISTS contracts (
  id            CHAR(36)      NOT NULL,            -- uuid v4
  template_slug VARCHAR(80)   NOT NULL,
  template_name VARCHAR(160)  NOT NULL,
  agent_id      INT UNSIGNED  NOT NULL,
  buyer_name    VARCHAR(200)  NULL,
  project_name  VARCHAR(200)  NULL,
  signed        TINYINT(1)    NOT NULL DEFAULT 0,  -- ¿llevaba firma en pantalla?
  data_json     LONGTEXT      NOT NULL,            -- valores rellenados (sin imágenes de firma)
  pdf_file      VARCHAR(120)  NOT NULL,            -- nombre del archivo en private/contratos/
  pdf_bytes     INT UNSIGNED  NULL,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_contracts_agent (agent_id, created_at),
  KEY idx_contracts_tpl (template_slug),
  CONSTRAINT fk_contracts_agent FOREIGN KEY (agent_id) REFERENCES agents (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
