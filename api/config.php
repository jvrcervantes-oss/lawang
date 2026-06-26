<?php
// Prevent direct web access
if (basename($_SERVER['SCRIPT_FILENAME'] ?? '') === 'config.php') {
    header('HTTP/1.0 403 Forbidden'); exit;
}

define('LAWANG_ADMIN', true);

// Password stored as bcrypt hash in .passhash file.
// Default password: lawang2026 — change it from the admin panel on first login.
$hashFile = __DIR__ . DIRECTORY_SEPARATOR . '.passhash';
if (!file_exists($hashFile) || trim(file_get_contents($hashFile)) === '') {
    file_put_contents($hashFile, password_hash('lawang2026', PASSWORD_BCRYPT));
}
define('ADMIN_PASS_HASH', trim(file_get_contents($hashFile)));

define('DATA_FILE',    dirname(__DIR__) . DIRECTORY_SEPARATOR . 'data.json');
define('IMAGES_DIR',   dirname(__DIR__) . DIRECTORY_SEPARATOR . 'assets' . DIRECTORY_SEPARATOR . 'img' . DIRECTORY_SEPARATOR . 'properties' . DIRECTORY_SEPARATOR);
define('IMAGES_URL',   '/assets/img/properties/');
define('MAX_UPLOAD_MB', 8);
