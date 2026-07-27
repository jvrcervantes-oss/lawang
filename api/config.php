<?php
// Prevent direct web access
if (basename($_SERVER['SCRIPT_FILENAME'] ?? '') === 'config.php') {
    header('HTTP/1.0 403 Forbidden'); exit;
}

define('LAWANG_ADMIN', true);

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
