-- ============================================================
-- Lawang Contracts — esquema MySQL
-- Ejecutar una vez en phpMyAdmin (Hostinger) sobre la BD del proyecto.
--
-- Esta BD ya NO guarda contratos (eso vive en Supabase, tabla `contratos`,
-- todos los tipos numerados). Su único trabajo es el LOGIN: app.php exige
-- sesión de un agente de esta tabla antes de servir la página (y con ella,
-- la key pública de Supabase que necesita el navegador).
-- ============================================================

-- Agentes que pueden entrar a la herramienta (sin auto-registro; alta manual
-- vía tools/make_admin.php)
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
