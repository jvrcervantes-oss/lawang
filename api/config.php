<?php
// Prevent direct web access
if (basename($_SERVER['SCRIPT_FILENAME'] ?? '') === 'config.php') {
    header('HTTP/1.0 403 Forbidden'); exit;
}

define('LAWANG_ADMIN', true);

// ── Sesión endurecida (se fija AQUÍ porque config.php se carga antes del session_start
//    de cada endpoint; si se pusiera después, la cookie ya estaría emitida y no valdría) ──
// Secure: solo por HTTPS · HttpOnly: invisible a JS · SameSite=Strict: anti-CSRF.
// use_strict_mode NO es el default de PHP: sin él, el navegador puede imponer un id de
// sesión elegido por un tercero (fijación de sesión).
ini_set('session.use_strict_mode', '1');
session_set_cookie_params([
    'lifetime' => 0,
    'path'     => '/',
    'secure'   => true,
    'httponly' => true,
    'samesite' => 'Strict',
]);

// ── Anti-CSRF: lo que muta estado tiene que venir del propio sitio ──
// La sesión sola no basta: con la cookie viva, un formulario en otra web podía disparar
// un guardado contra este panel. Portado de B2K (b2k_require_same_origin), en producción
// desde jul-2026. SameSite=Strict ya cubre casi todo; esto es el cinturón del tirante.
function lawang_require_same_origin() {
    $host    = $_SERVER['HTTP_HOST'] ?? '';
    $origin  = $_SERVER['HTTP_ORIGIN'] ?? '';
    $referer = $_SERVER['HTTP_REFERER'] ?? '';
    $ok = false;
    foreach ([$origin, $referer] as $src) {
        if ($src === '') continue;
        $h = parse_url($src, PHP_URL_HOST);
        if ($h !== null && $host !== '' && strcasecmp($h, $host) === 0) { $ok = true; break; }
    }
    // Sin Origin ni Referer no se puede verificar el origen → se rechaza.
    if (!$ok) {
        http_response_code(403);
        header('Content-Type: application/json');
        echo json_encode(['ok' => false, 'error' => 'Bad origin']);
        exit;
    }
}

// Password stored as bcrypt hash in .passhash file.
// FALLA CERRADO: si .passhash falta o está vacío NO se recrea con una clave por defecto
// (antes ponía 'lawang2026', pública en este repo → cualquier wipe del fichero reabría el
// admin con clave conocida; ya pasó una vez en la migración de dominio). Se responde 500 y
// se corta. Para provisionar de cero (instalación nueva), sembrar el hash a mano una vez:
//   php -r "file_put_contents('.passhash', password_hash('LA_QUE_SEA', PASSWORD_BCRYPT));"
$hashFile = __DIR__ . DIRECTORY_SEPARATOR . '.passhash';
if (!file_exists($hashFile) || trim(file_get_contents($hashFile)) === '') {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'Admin not provisioned']);
    exit;
}
define('ADMIN_PASS_HASH', trim(file_get_contents($hashFile)));

define('DATA_FILE',    dirname(__DIR__) . DIRECTORY_SEPARATOR . 'data.json');
define('IMAGES_DIR',   dirname(__DIR__) . DIRECTORY_SEPARATOR . 'assets' . DIRECTORY_SEPARATOR . 'img' . DIRECTORY_SEPARATOR . 'properties' . DIRECTORY_SEPARATOR);
define('IMAGES_URL',   '/assets/img/properties/');
// 25 MB de entrada: cubre originales de cámara y de móvil sin acercarse al techo de
// transporte (upload_max_filesize/post_max_size = 60M en api/.user.ini).
// Lo que se GUARDA no es lo que se sube: upload.php reescala a MAX_IMAGE_DIM y re-encoda,
// así que una foto de 20 MB acaba pesando cientos de KB en la web.
define('MAX_UPLOAD_MB', 25);
define('MAX_DOC_UPLOAD_MB', 50);
// Lado largo máximo del JPEG/PNG/WebP servido al público. 2560 cubre pantallas 4K
// (las fotos se pintan como máximo a ancho completo) sin guardar originales de 8000px.
define('MAX_IMAGE_DIM', 2560);
define('IMAGE_QUALITY', 82);
