<?php
require_once 'config.php';
session_start();
header('Content-Type: application/json');
header('Cache-Control: no-store');

if (!($_SESSION['lawang_auth'] ?? false)) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'Method not allowed']);
    exit;
}

$body     = json_decode(file_get_contents('php://input'), true) ?? [];
$password = $body['password'] ?? '';

if (strlen($password) < 8) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Password must be at least 8 characters.']);
    exit;
}

$hash     = password_hash($password, PASSWORD_BCRYPT);
$hashFile = __DIR__ . DIRECTORY_SEPARATOR . '.passhash';

if (file_put_contents($hashFile, $hash) === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Could not save new password.']);
    exit;
}

echo json_encode(['ok' => true]);
