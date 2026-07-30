<?php
/**
 * lead.php — captura de contacto. Dos formularios, dos ficheros:
 *   · verja de descargas de la ficha de producto  → private/leads.csv       (solo email)
 *   · "Solicitar llamada" de /modelo/<id>         → private/leads_llamada.csv (nombre+tel+consentimiento)
 *
 * Ficheros separados a propósito: son datos de forma distinta y el histórico de leads.csv
 * lleva una cabecera de 5 columnas en producción. Meter filas de 8 bajo esa cabecera deja
 * un CSV que se lee mal justo el día que empiece a entrar volumen desde la pauta.
 * Sin dependencias externas.
 */
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'method']);
    exit;
}

// Trampa de bots: el campo va oculto por CSS, un humano no lo ve. Si viene relleno se
// responde "ok" y no se guarda nada — un 4xx le diría al bot qué corregir.
if (trim(isset($_POST['website']) ? $_POST['website'] : '') !== '') {
    echo json_encode(['ok' => true]);
    exit;
}

// Freno de caudal: este endpoint es publico por diseno (lo llama el formulario), asi que
// nada impedia meter miles de filas en Supabase y disparar otros tantos correos SMTP.
// Cubo separado por formulario, y mas holgado en el de llamada: la pauta va a moviles
// españoles bajo CGNAT, donde cientos de visitantes comparten IP publica. Con el cubo
// compartido de 8, el 9º visitante de la campaña recibia un 429 sin haber enviado nada.
require_once __DIR__ . '/throttle.php';
$__ip     = $_SERVER['REMOTE_ADDR'] ?? 'sin-ip';
$__llamada = trim(isset($_POST['name']) ? $_POST['name'] : '') !== ''
          || trim(isset($_POST['phone']) ? $_POST['phone'] : '') !== '';
$__cubo   = ($__llamada ? 'llamada_' : 'lead_') . $__ip;
$__tope   = $__llamada ? 15 : 8;
if (lawang_throttle_blocked($__cubo, $__tope, 600)) {
    http_response_code(429);
    header('Retry-After: 600');
    echo json_encode(['ok' => false, 'error' => 'too_many']);
    exit;
}
lawang_throttle_register($__cubo, 600);

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
// El email tambien: `filter_var` da por bueno un local-part que empieza por = + - @
// (ej. "=cmd|'/c calc'!A0"@x.com) y ventas abre este CSV en Excel.
$email    = $clean($email);
// Atribucion de campaña. Sin esto no hay coste por lead por anuncio ni forma de subir
// la conversion offline cuando la venta se cierre por telefono semanas despues.
$campana  = $clean(isset($_POST['campana']) ? trim($_POST['campana']) : '');

// private/ no es servible por web (fuera del docroot lógico); se crea si falta
$dir = __DIR__ . '/../private';
if (!is_dir($dir)) { @mkdir($dir, 0755, true); }

// ── Solicitud de llamada (landing /modelo/<id>) ────────────────────────────────
// Se distingue por traer nombre o teléfono. Aquí los tres campos son obligatorios:
// un lead de ticket alto sin teléfono no se puede trabajar, y sin consentimiento
// expreso no se puede contactar a un residente en la UE (RGPD).
$name  = $clean(isset($_POST['name'])  ? trim($_POST['name'])  : '');
$phone = $clean(isset($_POST['phone']) ? trim($_POST['phone']) : '');

if ($name !== '' || $phone !== '') {
    $consent = isset($_POST['consent']) && $_POST['consent'] === '1';
    if ($name === '' || $phone === '' || !$consent) {
        http_response_code(422);
        echo json_encode(['ok' => false, 'error' => 'campos']);
        exit;
    }

    $file = $dir . '/leads_llamada.csv';
    $new  = !file_exists($file);
    $fh   = @fopen($file, 'a');
    if ($fh === false) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'write']);
        exit;
    }

    // Aviso a ventas. Un formulario que solo escribe en un CSV que nadie abre no es
    // captación: el lead se enfría en el disco. Se guarda si el envío salió o no,
    // que es lo único que permite darse cuenta de que el correo dejó de salir.
    $enviado = @mail(
        'sales@lawangproperties.com',
        'Nueva solicitud de llamada - ' . ($property !== '' ? $property : 'web'),
        "Modelo: $property\nNombre: $name\nEmail: $email\nTelefono: $phone\n"
        . "Origen: $source\nCampana: $campana\nFecha: " . date('c'),
        // From de un buzón del propio dominio: con un remitente ajeno el correo cae en spam.
        "From: no-reply@lawangproperties.com\r\nReply-To: $email\r\n"
        . "Content-Type: text/plain; charset=UTF-8\r\n",
        // Envelope sender. Sin -f, Hostinger manda con el usuario del sistema como
        // remitente de sobre, el SPF de lawangproperties.com falla y el aviso cae en
        // spam. Mismo parametro que usa contracts/api/send_email.php.
        '-fno-reply@lawangproperties.com'
    ) ? 'si' : 'NO';

    if ($new) {
        fputcsv($fh, ['timestamp', 'nombre', 'email', 'telefono', 'modelo', 'source', 'campana', 'consentimiento', 'ip', 'avisado']);
    }
    fputcsv($fh, [
        date('c'), $name, $email, $phone, $property, $source, $campana, 'si',
        isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '',
        $enviado,
    ]);
    fclose($fh);

    echo json_encode(['ok' => true]);
    exit;
}

// ── Verja de descargas (solo email) ────────────────────────────────────────────
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
