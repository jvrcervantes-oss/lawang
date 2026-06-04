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

$images = [];
if (is_dir(IMAGES_DIR)) {
    $files = glob(IMAGES_DIR . '*.{jpg,jpeg,png,webp}', GLOB_BRACE);
    if ($files) {
        usort($files, function($a, $b){ return filemtime($b) - filemtime($a); }); // newest first
        foreach ($files as $f) {
            $images[] = [
                'url'  => IMAGES_URL . basename($f),
                'name' => basename($f),
                'size' => round(filesize($f) / 1024) . ' KB'
            ];
        }
    }
}
echo json_encode($images);
