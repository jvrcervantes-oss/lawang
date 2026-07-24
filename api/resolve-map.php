<?php
// Resuelve un enlace de Google Maps (incluido el corto maps.app.goo.gl) a sus coordenadas, siguiendo
// los redirects del lado servidor. El navegador no puede: el enlace corto redirige a una página que
// bloquea el <iframe> y CORS impide leer las coordenadas. Aquí (Hostinger) sí se puede.
require_once 'config.php';
session_start();
header('Content-Type: application/json');
header('Cache-Control: no-store');

if (!($_SESSION['lawang_auth'] ?? false)) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
    exit;
}

$url = trim($_GET['url'] ?? $_POST['url'] ?? '');
if ($url === '' || !preg_match('#^https?://#i', $url)) {
    echo json_encode(['ok' => false, 'error' => 'Missing url']);
    exit;
}

// SSRF guard: SOLO hosts de Google Maps (no seguimos redirects a cualquier sitio).
$host = strtolower(parse_url($url, PHP_URL_HOST) ?? '');
$allowedHosts = ['maps.app.goo.gl', 'goo.gl', 'maps.google.com', 'www.google.com', 'google.com'];
$hostOk = false;
foreach ($allowedHosts as $h) {
    if ($host === $h || substr($host, -strlen('.' . $h)) === '.' . $h) { $hostOk = true; break; }
}
if (!$hostOk) {
    echo json_encode(['ok' => false, 'error' => 'Not a Google Maps URL']);
    exit;
}

// Busca coordenadas en un texto: @lat,lng · !3dLAT!4dLNG · q=/ll=/center=lat,lng
function lw_find_coords($text) {
    if (preg_match('/@(-?\d+\.\d+),(-?\d+\.\d+)/', $text, $m)) return [$m[1], $m[2]];
    if (preg_match('/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/', $text, $m)) return [$m[1], $m[2]];
    if (preg_match('/[?&](?:q|ll|center|daddr|destination)=(-?\d+\.\d+),\s*(-?\d+\.\d+)/', $text, $m)) return [$m[1], $m[2]];
    return null;
}

// Quizá el enlace ya trae coordenadas (URL larga de la barra de direcciones) — sin salir a red.
if ($c = lw_find_coords($url)) {
    echo json_encode(['ok' => true, 'lat' => $c[0], 'lng' => $c[1], 'resolved' => $url]);
    exit;
}

if (!function_exists('curl_init')) {
    echo json_encode(['ok' => false, 'error' => 'cURL no disponible en el servidor']);
    exit;
}

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS      => 8,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 12,
    CURLOPT_CONNECTTIMEOUT => 8,
    CURLOPT_SSL_VERIFYPEER => true,
    // UA de navegador: Google sirve la página de mapa (con coords) en vez de una interstitial de app.
    CURLOPT_USERAGENT      => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    CURLOPT_HTTPHEADER     => ['Accept-Language: en'],
]);
$body  = curl_exec($ch);
$final = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
$err   = curl_error($ch);
curl_close($ch);

// Primero la URL final (lo más fiable), luego el HTML por si las coords viven ahí.
$coords = lw_find_coords((string) $final);
if (!$coords && is_string($body) && $body !== '') $coords = lw_find_coords($body);

if ($coords) {
    echo json_encode(['ok' => true, 'lat' => $coords[0], 'lng' => $coords[1], 'resolved' => $final]);
    exit;
}

echo json_encode(['ok' => false, 'error' => 'No se encontraron coordenadas en el enlace', 'resolved' => $final ?: null, 'curl' => $err ?: null]);
