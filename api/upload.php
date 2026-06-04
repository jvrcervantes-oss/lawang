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

// Safe filename: timestamp + random + extension
$filename = date('Ymd') . '_' . bin2hex(random_bytes(6)) . '.' . $ext;
$dest     = IMAGES_DIR . $filename;

if (!move_uploaded_file($file['tmp_name'], $dest)) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Upload failed. Check server permissions.']);
    exit;
}

echo json_encode(['ok' => true, 'url' => IMAGES_URL . $filename, 'name' => $filename]);
