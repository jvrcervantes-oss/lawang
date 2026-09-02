<?php
/**
 * booking-notify.php — aviso interno cuando el widget de Calendly de /modelo/<id>
 * confirma una reserva (LAW-111: hasta el 2-sep nadie del equipo se enteraba).
 *
 * Lo llama el JS de modelo/index.php al recibir el postMessage
 * `calendly.event_scheduled` del iframe. Calendly NO expone nombre/email/teléfono
 * del invitado en ese mensaje — solo la URI del evento y de la invitación — así que
 * este endpoint nunca ve datos de contacto y no llama a la API de Calendly (no hay
 * token) ni crea contacto en GHL (sin nombre/email no hay con qué hacer upsert).
 * El lead completo sigue viviendo solo dentro de Calendly; esto es solo la campanita.
 *
 * NO se puede verificar que la reserva sea real: cualquiera puede llamar a este
 * endpoint con un POST inventado (no hay auth, igual que lead.php). Por eso el
 * correo y la fila del CSV dicen explícitamente "sin verificar", para que ventas
 * no llame a un lead que no existe basándose solo en este aviso.
 */
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'method']);
    exit;
}

// Cubo propio, no compartido con lead_/llamada_ (misma landing, tres formularios):
// si comparte cubo, el visitante que ya gastó su cupo pidiendo info se queda sin
// margen para que su reserva real dispare el aviso, o al revés.
require_once __DIR__ . '/throttle.php';
$__ip   = $_SERVER['REMOTE_ADDR'] ?? 'sin-ip';
$__cubo = 'booking_' . $__ip;
if (lawang_throttle_blocked($__cubo, 15, 600)) {
    http_response_code(429);
    header('Retry-After: 600');
    echo json_encode(['ok' => false, 'error' => 'too_many']);
    exit;
}
lawang_throttle_register($__cubo, 600);

$clean = function ($s) {
    $s = preg_replace('/[\r\n]+/', ' ', (string) $s);
    $s = mb_substr($s, 0, 300);
    // Anti inyección de fórmula CSV (Excel ejecuta celdas que empiezan por = + - @)
    if ($s !== '' && strpos('=+-@', $s[0]) !== false) $s = "'" . $s;
    return $s;
};

$modelo   = $clean($_POST['modelo']   ?? '');
// Contra el catálogo real, no solo $clean() (Seguridad, revisión previa 2-sep): el
// configurador puede mandar cualquier id tras el cambio a "cambia en la misma página" —
// sin este check, un modelo inventado (o un valor manipulado a mano) pasaba tal cual al
// correo y al CSV de ventas.
$__MODELOS = require __DIR__ . '/../modelo/modelos.php';
if (!array_key_exists($modelo, $__MODELOS)) { $modelo = ''; }
$source   = $clean($_POST['source']   ?? '');
$campana  = $clean($_POST['campana']  ?? '');
$eventUri = $clean($_POST['event_uri']   ?? '');
$inviteeUri = $clean($_POST['invitee_uri'] ?? '');
// Selecciones del picker de la ficha (2-sep): lo que el visitante marcó ANTES de
// reservar (extras/isla/vista) — no es un pedido cerrado, solo orienta a ventas. Mismo
// $clean() que el resto de campos: son texto libre que controla quien llama al endpoint.
$extras   = $clean($_POST['extras'] ?? '');
$isla     = $clean($_POST['island'] ?? '');
$vista    = $clean($_POST['view']   ?? '');

// Filtro de formato mínimo: sin esto, cualquier texto libre pasa a correo y CSV.
// No es verificación real (para eso haría falta la API de Calendly, que no tenemos),
// solo descarta el ruido más burdo.
$calendlyUri = fn($s) => strpos($s, 'https://api.calendly.com/') === 0;
if (!$calendlyUri($eventUri) || !$calendlyUri($inviteeUri)) {
    http_response_code(422);
    echo json_encode(['ok' => false, 'error' => 'uri']);
    exit;
}

$dir = __DIR__ . '/../private';
if (!is_dir($dir)) { @mkdir($dir, 0755, true); }
$file = $dir . '/bookings_calendly.csv';

$new = !file_exists($file);
$fh  = @fopen($file, 'a');
if ($fh === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'write']);
    exit;
}

// Aviso a ventas. Mismo patrón que api/lead.php: mail() con envelope sender del
// propio dominio (sin -f, Hostinger manda con el usuario del sistema y el SPF de
// lawangproperties.com falla, así que el aviso cae en spam).
$enviado = @mail(
    'sales@lawangproperties.com',
    'Reserva sin verificar en Calendly - ' . ($modelo !== '' ? $modelo : 'web'),
    "AVISO AUTOMATICO SIN VERIFICAR CONTRA CALENDLY: alguien completo el widget de\n"
    . "reserva en la web. Revisar el calendario de Calendly para confirmar y ver\n"
    . "nombre/email/telefono reales (este aviso no los tiene).\n\n"
    . "Modelo: $modelo\nOrigen: $source\nCampana: $campana\n"
    . "PREFERENCIAS MARCADAS ANTES DE RESERVAR (no es un pedido cerrado, se confirma en\n"
    . "la llamada): Isla: " . ($isla !== '' ? $isla : '(sin marcar)')
    . " · Vista: " . ($vista !== '' ? $vista : '(sin marcar)')
    . " · Extras: " . ($extras !== '' ? $extras : '(sin marcar)') . "\n\n"
    . "Evento Calendly: $eventUri\nInvitado Calendly: $inviteeUri\nFecha: " . date('c'),
    "From: no-reply@lawangproperties.com\r\nContent-Type: text/plain; charset=UTF-8\r\n",
    '-fno-reply@lawangproperties.com'
) ? 'si' : 'NO';

if ($new) {
    fputcsv($fh, ['timestamp', 'modelo', 'source', 'campana', 'event_uri', 'invitee_uri', 'extras', 'island', 'view', 'ip', 'avisado']);
}
fputcsv($fh, [
    date('c'), $modelo, $source, $campana, $eventUri, $inviteeUri, $extras, $isla, $vista,
    $_SERVER['REMOTE_ADDR'] ?? '', $enviado,
]);
fclose($fh);

echo json_encode(['ok' => true]);
