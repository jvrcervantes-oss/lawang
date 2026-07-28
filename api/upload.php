<?php
require_once 'config.php';
session_start();
lawang_require_same_origin();  // el 401 de abajo mira la sesion; esto mira DE DONDE viene la peticion
header('Content-Type: application/json');
header('Cache-Control: no-store');

if (!($_SESSION['lawang_auth'] ?? false)) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !isset($_FILES['image'])) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'No file received']);
    exit;
}

$file    = $_FILES['image'];
$allowed = ['jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'];
$ext     = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));

if (!array_key_exists($ext, $allowed)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'File type not allowed. Use JPG, PNG or WebP.']);
    exit;
}

// Verify MIME type via magic bytes, not just extension
$finfo = finfo_open(FILEINFO_MIME_TYPE);
$mime  = finfo_file($finfo, $file['tmp_name']);
finfo_close($finfo);
if (!in_array($mime, $allowed)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid file content.']);
    exit;
}

if ($file['size'] > MAX_UPLOAD_MB * 1024 * 1024) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'File exceeds ' . MAX_UPLOAD_MB . ' MB limit.']);
    exit;
}

if (!is_dir(IMAGES_DIR)) {
    mkdir(IMAGES_DIR, 0755, true);
}

// ── Reescalado + re-encode ────────────────────────────────────────────────────
// Dos motivos, no uno: (1) el playbook de seguridad exige re-encodar las imágenes con
// GD — reconstruir el bitmap tira EXIF y cualquier payload escondido en los metadatos;
// (2) el panel acepta originales de cámara de hasta 25 MB, pero la web NO puede servir
// eso: sin este paso, subir la foto buena hundiría el LCP de la ficha.
// Si GD no está o la imagen no cabe en memoria, se guarda el original tal cual: mejor
// una foto pesada que un panel que no deja subir nada.
ini_set('memory_limit', '256M');

$info = @getimagesize($file['tmp_name']);
if ($info === false) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid image file.']);
    exit;
}
list($srcW, $srcH) = $info;

// PNG sin canal alfa -> se guarda como JPEG (una foto en PNG pesa varias veces más).
// El tipo de color vive en el byte 25 del IHDR: 0=gris, 2=truecolor (ninguno lleva alfa);
// 3=paleta (puede traer tRNS), 4 y 6 sí llevan alfa. Es fiable y no cuesta recorrer píxeles.
$outExt = $ext === 'jpeg' ? 'jpg' : $ext;
if ($outExt === 'png') {
    $head = @file_get_contents($file['tmp_name'], false, null, 24, 2);
    if ($head !== false && strlen($head) === 2) {
        $colorType = ord($head[1]);
        if ($colorType === 0 || $colorType === 2) $outExt = 'jpg';
    }
}

// GD necesita ~4 bytes por píxel, y durante el reescalado conviven origen y destino.
$estimate  = ($srcW * $srcH * 4) * 1.8;
$loaders   = ['jpg' => 'imagecreatefromjpeg', 'jpeg' => 'imagecreatefromjpeg',
              'png' => 'imagecreatefrompng',  'webp' => 'imagecreatefromwebp'];
$loader    = $loaders[$ext] ?? null;
$canResize = $loader && function_exists($loader) && $estimate < 200 * 1024 * 1024;

$filename  = date('Ymd') . '_' . bin2hex(random_bytes(16)) . '.' . $outExt;
$dest      = IMAGES_DIR . $filename;
$processed = false;

if ($canResize) {
    $src = @$loader($file['tmp_name']);
    if ($src) {
        $scale = min(1, MAX_IMAGE_DIM / max($srcW, $srcH));
        $dstW  = max(1, (int) round($srcW * $scale));
        $dstH  = max(1, (int) round($srcH * $scale));
        $dst   = imagecreatetruecolor($dstW, $dstH);

        if ($outExt === 'png' || $outExt === 'webp') {
            // Sin esto el alfa se aplana a negro al copiar
            imagealphablending($dst, false);
            imagesavealpha($dst, true);
        } else {
            // JPEG no tiene alfa: lo transparente iría a negro, así que se pone blanco
            imagefilledrectangle($dst, 0, 0, $dstW, $dstH, imagecolorallocate($dst, 255, 255, 255));
        }

        if (imagecopyresampled($dst, $src, 0, 0, 0, 0, $dstW, $dstH, $srcW, $srcH)) {
            if     ($outExt === 'png')  $processed = imagepng($dst, $dest, 8);
            elseif ($outExt === 'webp') $processed = imagewebp($dst, $dest, IMAGE_QUALITY);
            else                        $processed = imagejpeg($dst, $dest, IMAGE_QUALITY);
        }
        imagedestroy($dst);
        imagedestroy($src);
    }
}

if (!$processed) {
    // Fallback: sin GD (o imagen demasiado grande para memoria) se guarda el original,
    // con su extensión real — el $outExt calculado arriba ya no vale.
    if ($outExt !== $ext) {
        $filename = date('Ymd') . '_' . bin2hex(random_bytes(16)) . '.' . $ext;
        $dest     = IMAGES_DIR . $filename;
    }
    if (!move_uploaded_file($file['tmp_name'], $dest)) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'Upload failed. Check server permissions.']);
        exit;
    }
}

echo json_encode([
    'ok'        => true,
    'url'       => IMAGES_URL . $filename,
    'name'      => $filename,
    'optimized' => $processed,                       // false = se guardó el original
    'bytes'     => @filesize($dest) ?: null,
]);
