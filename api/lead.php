<?php
/**
 * lead.php — captura de email (verja de descargas de la ficha de producto).
 * Añade una fila a private/leads.csv. Sin dependencias externas.
 */
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'method']);
    exit;
}

$email    = isset($_POST['email'])    ? trim($_POST['email'])    : '';
$source   = isset($_POST['source'])   ? trim($_POST['source'])   : '';
$property = isset($_POST['property']) ? trim($_POST['property']) : '';

// Validación de email
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(422);
    echo json_encode(['ok' => false, 'error' => 'email']);
    exit;
}

// Recorta campos para evitar inyección de CSV / payloads enormes
$clean = function ($s) {
    $s = preg_replace('/[\r\n]+/', ' ', $s);
    return mb_substr($s, 0, 200);
};
$source   = $clean($source);
$property = $clean($property);

// private/ no es servible por web (fuera del docroot lógico); se crea si falta
$dir = __DIR__ . '/../private';
if (!is_dir($dir)) { @mkdir($dir, 0755, true); }
$file = $dir . '/leads.csv';

$new = !file_exists($file);
$fh  = @fopen($file, 'a');
if ($fh === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'write']);
    exit;
}
if ($new) {
    fputcsv($fh, ['timestamp', 'email', 'source', 'property', 'ip']);
}
fputcsv($fh, [
    date('c'),
    $email,
    $source,
    $property,
    $_SERVER['REMOTE_ADDR'] ?? '',
]);
fclose($fh);

echo json_encode(['ok' => true]);
