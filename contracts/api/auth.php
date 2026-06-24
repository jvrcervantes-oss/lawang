<?php
require __DIR__ . '/bootstrap.php';

$action = $_GET['action'] ?? '';

// Estado de sesión + token CSRF para el front
if ($action === 'me') {
  $a = current_agent();
  json_out(['ok' => true, 'agent' => $a ? ['name' => $a['name'], 'email' => $a['email'], 'role' => $a['role']] : null, 'csrf' => csrf_token()]);
}

if ($action === 'login' && $_SERVER['REQUEST_METHOD'] === 'POST') {
  require_same_origin();
  $in = json_in();
  $email = strtolower(trim($in['email'] ?? ''));
  $pass  = (string)($in['password'] ?? '');
  if ($email === '' || $pass === '') fail('Faltan credenciales');

  // rate-limit muy básico por sesión
  $_SESSION['login_tries'] = ($_SESSION['login_tries'] ?? 0) + 1;
  if ($_SESSION['login_tries'] > 8) fail('Demasiados intentos. Espera un momento.', 429);

  $st = db()->prepare('SELECT * FROM agents WHERE email = ? AND active = 1 LIMIT 1');
  $st->execute([$email]);
  $ag = $st->fetch();
  if (!$ag || !password_verify($pass, $ag['password_hash'])) {
    usleep(300000); // ralentizar fuerza bruta
    fail('Credenciales incorrectas', 401);
  }
  // rotar id de sesión al autenticar
  session_regenerate_id(true);
  $_SESSION['login_tries'] = 0;
  $_SESSION['agent'] = ['id' => (int)$ag['id'], 'name' => $ag['name'], 'email' => $ag['email'], 'role' => $ag['role']];
  json_out(['ok' => true, 'agent' => ['name' => $ag['name'], 'email' => $ag['email'], 'role' => $ag['role']], 'csrf' => csrf_token()]);
}

if ($action === 'logout') {
  $_SESSION = [];
  session_destroy();
  json_out(['ok' => true]);
}

fail('Acción no válida', 404);
