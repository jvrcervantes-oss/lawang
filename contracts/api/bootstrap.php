<?php
/**
 * Bootstrap común a todos los endpoints: config, sesión, BD (PDO) y helpers.
 * Incluir SIEMPRE al principio de cada api/*.php
 */
declare(strict_types=1);

// ---- localizar private/ (un nivel por encima del webroot del módulo) ----
$CONF_PATHS = [
  __DIR__ . '/../private/config.php',      // contracts/private/config.php
  __DIR__ . '/../../private/config.php',   // por si private/ se sube fuera de contracts/
];
$CONFIG = null;
foreach ($CONF_PATHS as $p) { if (is_file($p)) { $CONFIG = require $p; break; } }
if (!$CONFIG) { http_response_code(500); exit('Config no encontrada'); }

// ---- errores ----
if (!empty($CONFIG['debug'])) { ini_set('display_errors', '1'); error_reporting(E_ALL); }
else { ini_set('display_errors', '0'); error_reporting(0); }

// ---- sesión endurecida ----
session_set_cookie_params([
  'lifetime' => 0,
  'path' => '/',
  'httponly' => true,
  'secure' => (($_SERVER['HTTPS'] ?? '') === 'on') || (($_SERVER['SERVER_PORT'] ?? '') == 443),
  'samesite' => 'Lax',
]);
session_name('lwc_sess');
session_start();

// ---- BD (PDO) perezosa ----
function db(): PDO {
  static $pdo = null;
  global $CONFIG;
  if ($pdo === null) {
    $dsn = "mysql:host={$CONFIG['db_host']};dbname={$CONFIG['db_name']};charset=utf8mb4";
    $pdo = new PDO($dsn, $CONFIG['db_user'], $CONFIG['db_pass'], [
      PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
      PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
      PDO::ATTR_EMULATE_PREPARES => false,
    ]);
  }
  return $pdo;
}

// ---- helpers de respuesta ----
function json_out($data, int $code = 200): void {
  http_response_code($code);
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode($data, JSON_UNESCAPED_UNICODE);
  exit;
}
function json_in(): array {
  $raw = file_get_contents('php://input');
  $d = json_decode($raw ?: '[]', true);
  return is_array($d) ? $d : [];
}
function fail(string $msg, int $code = 400): void { json_out(['ok' => false, 'error' => $msg], $code); }

// ---- CSRF (token en sesión, validado en métodos que mutan) ----
function csrf_token(): string {
  if (empty($_SESSION['csrf'])) { $_SESSION['csrf'] = bin2hex(random_bytes(32)); }
  return $_SESSION['csrf'];
}
function csrf_check(): void {
  $sent = $_SERVER['HTTP_X_CSRF'] ?? ($_POST['csrf'] ?? '');
  if (!hash_equals($_SESSION['csrf'] ?? '', (string)$sent)) { fail('CSRF inválido', 403); }
}

// ---- sesión de agente ----
function current_agent(): ?array { return $_SESSION['agent'] ?? null; }
function require_agent(): array {
  $a = current_agent();
  if (!$a) { fail('No autenticado', 401); }
  return $a;
}

// ---- same-origin guard (defensa extra para métodos que mutan) ----
function require_same_origin(): void {
  global $CONFIG;
  $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
  if ($origin === '') return; // peticiones same-site sin Origin (navegación) — ok
  $allowed = $CONFIG['allowed_origin'] ?? '';
  if ($allowed && rtrim($origin, '/') !== rtrim($allowed, '/')) { fail('Origen no permitido', 403); }
}
