<?php
/**
 * ALTA DE AGENTE — USO ÚNICO.
 * 1) Sube este archivo, ábrelo en el navegador con los parámetros:
 *      tools/make_admin.php?key=APP_SECRET&name=Pablo&email=pablo@lawang.com&pass=ClaveFuerte&role=admin
 * 2) Verifica el mensaje de éxito.
 * 3) BORRA este archivo del servidor inmediatamente.
 *
 * El parámetro key DEBE coincidir con app_secret de private/config.php.
 */
require __DIR__ . '/../api/bootstrap.php';

header('Content-Type: text/plain; charset=utf-8');

$key = $_GET['key'] ?? '';
if (!hash_equals((string)($GLOBALS['CONFIG']['app_secret'] ?? ''), (string)$key)) {
  http_response_code(403); exit("Clave incorrecta.\n");
}

$name  = trim($_GET['name'] ?? '');
$email = strtolower(trim($_GET['email'] ?? ''));
$pass  = (string)($_GET['pass'] ?? '');
$role  = ($_GET['role'] ?? 'agent') === 'admin' ? 'admin' : 'agent';

if ($name === '' || $email === '' || strlen($pass) < 8) {
  exit("Faltan datos o contraseña < 8 caracteres.\n");
}

$hash = password_hash($pass, PASSWORD_DEFAULT);
$st = db()->prepare(
  'INSERT INTO agents (name, email, password_hash, role) VALUES (?,?,?,?)
   ON DUPLICATE KEY UPDATE name=VALUES(name), password_hash=VALUES(password_hash), role=VALUES(role), active=1'
);
$st->execute([$name, $email, $hash, $role]);

echo "OK · agente '{$email}' ({$role}) creado/actualizado.\n";
echo "AHORA BORRA tools/make_admin.php DEL SERVIDOR.\n";
