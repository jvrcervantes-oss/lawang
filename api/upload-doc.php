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

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !isset($_FILES['file'])) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'No file received']);
    exit;
}

$file = $_FILES['file'];
$allowed = ['pdf', 'doc', 'docx', 'zip'];
$ext  = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));

if (!in_array($ext, $allowed)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'File type not allowed. Use PDF, DOC, DOCX or ZIP.']);
    exit;
}

if ($file['size'] > 20 * 1024 * 1024) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'File exceeds 20 MB limit.']);
    exit;
}

$docsDir = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'docs' . DIRECTORY_SEPARATOR;
if (!is_dir($docsDir)) {
    mkdir($docsDir, 0755, true);
}

$safeName = preg_replace('/[^a-zA-Z0-9_\-.]/', '_', $file['name']);
$filename = date('Ymd') . '_' . $safeName;
if (file_exists($docsDir . $filename)) {
    $filename = date('Ymd') . '_' . bin2hex(random_bytes(4)) . '_' . $safeName;
}

if (!move_uploaded_file($file['tmp_name'], $docsDir . $filename)) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Upload failed. Check server permissions.']);
    exit;
}

$sizeBytes = filesize($docsDir . $filename);
$sizeFmt   = $sizeBytes >= 1048576
    ? round($sizeBytes / 1048576, 1) . ' MB'
    : round($sizeBytes / 1024) . ' KB';

echo json_encode([
    'ok'   => true,
    'url'  => '/docs/' . $filename,
    'ext'  => strtoupper($ext),
    'size' => $sizeFmt
]);
