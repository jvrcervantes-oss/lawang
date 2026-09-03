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
    // ltrim ANTES del chequeo de fórmula (3-sep): Excel también honra una celda que empieza
    // por tabulador o espacio y sigue con "=", así que "\t=cmd|..." se colaba entero por el
    // strpos de abajo, que solo miraba el primer carácter literal.
    $s = ltrim($s, " \t\v\0");
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
require_once __DIR__ . '/../modelo/lib.php';
$__MODELOS = require __DIR__ . '/../modelo/modelos.php';
if (!array_key_exists($modelo, $__MODELOS)) { $modelo = ''; }
$source   = $clean($_POST['source']   ?? '');
$campana  = $clean($_POST['campana']  ?? '');
$eventUri = $clean($_POST['event_uri']   ?? '');
$inviteeUri = $clean($_POST['invitee_uri'] ?? '');

// ── Selecciones del configurador ───────────────────────────────────────────────────
// 3-sep: hasta hoy isla/vista/extras pasaban SOLO por $clean(), o sea 300 caracteres de
// texto libre que iban derechos al correo de ventas y al CSV. Es la misma clase de
// agujero que ya se cerró para `modelo` el 2-sep, y ahora pesa más porque estos campos
// entran en un cálculo de dinero. Todo se valida contra lw_picker_opciones(), que es la
// misma fuente con la que la página pintó los botones: lo que no esté en catálogo no se
// guarda "raro", se guarda vacío.
$__OP     = lw_picker_opciones();
$techo    = (string) ($_POST['techo'] ?? '');
if ($modelo === '' || !isset($__MODELOS[$modelo]['techos'][$techo])) { $techo = ''; }
$isla     = (string) ($_POST['island'] ?? '');
if (!isset($__OP['island'][$isla])) { $isla = ''; }
$vista    = (string) ($_POST['view'] ?? '');
if (!isset($__OP['view'][$vista])) { $vista = ''; }
// Coherencia: el catálogo de vistas es de Bali. Con Sumba (o sin isla) una vista es
// imposible en la interfaz y trivial por POST — se ignora en vez de viajar al correo.
if ($isla !== 'bali') { $vista = ''; }
$extrasIn = explode(',', (string) ($_POST['extras'] ?? ''));
$extrasOk = array_values(array_intersect(array_map('trim', $extrasIn), array_keys($__OP['extras'])));
$extras   = implode(',', $extrasOk);
$m2       = lw_m2_clamp($_POST['parcela_m2'] ?? null);

// ── La cifra la calcula el SERVIDOR, nunca llega por POST ──────────────────────────
// Este endpoint no tiene auth (lo dice su propia cabecera): un importe que llegue del
// navegador es un número que cualquiera puede escribirle al correo de ventas. Como todos
// los ingredientes son constantes de servidor, se recalcula aquí con las mismas funciones
// que pintaron el panel. Se guarda además el TRAMO de precio explícito (2026/2027) y no
// solo el timestamp: si algún día se mueve LW_CORTE_2027, el histórico no se reescribe solo.
$est = ($modelo !== '' && $techo !== '')
    ? lw_estimacion($__MODELOS[$modelo], $techo, $isla, $vista, $m2)
    : ['villa' => null, 'tarifa' => null, 'm2' => null, 'parcela' => null, 'total' => null, 'tramo' => ''];
$estTxt = $est['total'] !== null
    ? lw_precio_fmt($est['total']) . ($est['parcela'] === null ? ' (villa sola, sin parcela)' : '')
    : '(sin calcular)';

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
// Defensa en profundidad: la carpeta ya está cubierta por el RedirectMatch de /private/ en
// el .htaccess de la raíz, pero ese casa la URL, no el fichero — y desde hoy aquí dentro
// hay además una estimación económica por lead. Un Deny propio cuesta una línea.
if (!is_file($dir . '/.htaccess')) {
    @file_put_contents($dir . '/.htaccess', "Require all denied\n<IfModule !mod_authz_core.c>\nDeny from all\n</IfModule>\n");
}

// Fichero NUEVO a propósito (3-sep): `bookings_calendly.csv` ya existe en el servidor desde
// el 2-sep con su cabecera de 11 columnas, y este endpoint solo escribe cabecera si el
// fichero no existe. Añadir campos al viejo dejaba filas de 16 valores bajo una cabecera de
// 11, en silencio y para siempre. El histórico anterior se queda intacto donde está.
$file = $dir . '/bookings_calendly_v2.csv';

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
// La cifra va ARRIBA del todo y etiquetada: el modo de fallo real de ventas es llegar a la
// llamada citando un número distinto del que el lead tuvo delante en pantalla.
$enviado = @mail(
    'sales@lawangproperties.com',
    'Reserva sin verificar en Calendly - ' . ($modelo !== '' ? $modelo : 'web'),
    "CIFRA QUE VIO EL VISITANTE EN PANTALLA: $estTxt\n"
    . "  (" . ($modelo !== '' ? $modelo : '?') . " · techo " . ($techo !== '' ? $techo : '?')
    . " · " . ($isla !== '' ? $isla : 'sin isla') . ($vista !== '' ? "/$vista" : '')
    . " · " . ($m2 !== null ? $m2 . ' m2 a ' . ($est['tarifa'] ?? '?') . ' EUR/m2' : 'sin parcela')
    . " · tramo " . ($est['tramo'] !== '' ? $est['tramo'] : '?') . ")\n"
    . "  NO incluye: extras (" . ($extras !== '' ? $extras : 'ninguno marcado')
    . "), notaria, permisos ni gastos de transmision. El precio de villa es un DESDE.\n"
    . "  Recalculada en servidor, no es lo que dijo el navegador.\n\n"
    . "AVISO AUTOMATICO SIN VERIFICAR CONTRA CALENDLY: alguien completo el widget de\n"
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

// Cabecera y fila derivadas del MISMO array (3-sep): mientras eran dos listas escritas a
// mano podían desincronizarse en silencio, que es justo lo que este endpoint iba a hacer
// al crecer. Columnas nuevas siempre al final, por si algún día se reaprovecha el fichero.
$fila = [
    'timestamp'      => date('c'),
    'schema_version' => 2,
    'modelo'         => $modelo,
    'source'         => $source,
    'campana'        => $campana,
    'event_uri'      => $eventUri,
    'invitee_uri'    => $inviteeUri,
    'extras'         => $extras,
    'island'         => $isla,
    'view'           => $vista,
    'techo'          => $techo,
    'parcela_m2'     => $m2 !== null ? $m2 : '',
    'tarifa_m2'      => $est['tarifa'] !== null ? $est['tarifa'] : '',
    'precio_villa'   => $est['villa'] !== null ? $est['villa'] : '',
    'subtotal_parcela' => $est['parcela'] !== null ? $est['parcela'] : '',
    'total_servidor' => $est['total'] !== null ? $est['total'] : '',
    'tramo'          => $est['tramo'],
    'moneda'         => 'EUR',
    'ip'             => $_SERVER['REMOTE_ADDR'] ?? '',
    'avisado'        => $enviado,
];
if ($new) { fputcsv($fh, array_keys($fila)); }
fputcsv($fh, array_values($fila));
fclose($fh);

echo json_encode(['ok' => true]);
