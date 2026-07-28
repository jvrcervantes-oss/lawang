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

// Freno de caudal: este endpoint es publico por diseno (lo llama el formulario), asi que
// nada impedia meter miles de filas en Supabase y disparar otros tantos correos SMTP.
// 8 envios por IP cada 10 min: de sobra para una persona, inutil para un bucle.
require_once __DIR__ . '/throttle.php';
$__ip = $_SERVER['REMOTE_ADDR'] ?? 'sin-ip';
if (lawang_throttle_blocked('lead_' . $__ip, 8, 600)) {
    http_response_code(429);
    header('Retry-After: 600');
    echo json_encode(['ok' => false, 'error' => 'too_many']);
    exit;
}
lawang_throttle_register('lead_' . $__ip, 600);

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
    $s = mb_substr($s, 0, 200);
    // Anti inyección de fórmula CSV (Excel ejecuta celdas que empiezan por = + - @)
    if ($s !== '' && strpos('=+-@', $s[0]) !== false) {
        $s = "'" . $s;
    }
    return $s;
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
