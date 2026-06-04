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

$body = file_get_contents('php://input');
$data = json_decode($body, true);

if ($data === null) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid JSON']);
    exit;
}

$json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
$tmp  = DATA_FILE . '.tmp';

if (file_put_contents($tmp, $json) === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Could not write file']);
    exit;
}

rename($tmp, DATA_FILE);
echo json_encode(['ok' => true]);
