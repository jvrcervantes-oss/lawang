<?php
/**
 * COPIA este archivo a  private/config.php  EN EL SERVIDOR y rellena los valores.
 * NUNCA subir private/config.php a git (ver .gitignore).
 */
return [
  // Base de datos (Hostinger → MySQL)
  'db_host' => 'localhost',
  'db_name' => 'uXXXXXXXX_lawang_contracts',
  'db_user' => 'uXXXXXXXX_lawang',
  'db_pass' => 'CAMBIAR_POR_LA_REAL',

  // Secreto de la app (sesiones / firmas internas). Generar uno largo y aleatorio.
  'app_secret' => 'CAMBIAR_por_64_chars_aleatorios',

  // Entorno: en producción -> false (no mostrar errores al cliente)
  'debug' => false,

  // Origen permitido para las llamadas del front (mismo dominio en prod)
  'allowed_origin' => 'https://contratos.lawang.example',
];
