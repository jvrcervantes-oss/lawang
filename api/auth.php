<?php
require_once 'config.php';
require_once 'throttle.php';
session_start();
header('Content-Type: application/json');
header('Cache-Control: no-store');

// Sin freno, la única defensa del panel era la longitud de la contraseña: bcrypt es
// lento para el atacante pero no impide 10.000 intentos. 10 fallos por IP / 10 min.
$ip     = $_SERVER['REMOTE_ADDR'] ?? 'sin-ip';
$llave  = 'login_' . $ip;
$MAXINT = 10;
$VENTANA = 600;

// GET — check if session is active
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    echo json_encode(['ok' => isset($_SESSION['lawang_auth'])]);
    exit;
}

// POST — login or logout
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    if (($body['action'] ?? '') === 'logout') {
        session_destroy();
        echo json_encode(['ok' => true]);
        exit;
    }

    // El bloqueo se mira ANTES de comprobar la contraseña: si no, cada intento seguiría
    // costando un bcrypt y el freno no ahorraría nada al servidor.
    if (lawang_throttle_blocked($llave, $MAXINT, $VENTANA)) {
        http_response_code(429);
        header('Retry-After: ' . $VENTANA);
        echo json_encode(['ok' => false, 'error' => 'Demasiados intentos. Prueba en unos minutos.']);
        exit;
    }

    $password = $body['password'] ?? '';
    if (password_verify($password, ADMIN_PASS_HASH)) {
        lawang_throttle_clear($llave);
        $_SESSION['lawang_auth'] = true;
        session_regenerate_id(true);
        echo json_encode(['ok' => true]);
    } else {
        lawang_throttle_register($llave, $VENTANA);
        http_response_code(401);
        echo json_encode(['ok' => false, 'error' => 'Invalid password']);
    }
    exit;
}

http_response_code(405);
echo json_encode(['ok' => false, 'error' => 'Method not allowed']);
