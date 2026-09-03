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
// utm_source/utm_campaign son los ÚNICOS campos de texto libre que llegan a un correo que
// ventas recibe desde un remitente propio con SPF válido — o sea, el vector de ingeniería
// social hacia el equipo (Seguridad, capa 1 de deploy 3-sep). Son valores generados por
// máquina, así que acotarlos al alfabeto de una utm cierra eso y, de paso, la inyección de
// fórmula de Excel por esta vía. El $clean() de abajo se mantiene como segunda barrera.
$utm = function ($s) { return substr(preg_replace('/[^A-Za-z0-9._-]/', '', (string) $s), 0, 64); };
$source   = $clean($utm($_POST['source']  ?? ''));
$campana  = $clean($utm($_POST['campana'] ?? ''));
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
// array_unique además de array_intersect: intersect CONSERVA duplicados, así que un
// "extras=sauna,sauna" escribía "sauna,sauna" en el CSV y en el correo a ventas.
$extrasOk = array_values(array_unique(array_intersect(array_map('trim', $extrasIn), array_keys($__OP['extras']))));
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
// El hedge viaja PEGADO al número (Administración, capa 1 de deploy): la pantalla dice
// "from around €173,000" y el correo decía "€173,000" a secas — y el comercial lee la cifra
// de arriba, no la aclaración de la línea siguiente.
$estTxt = $est['total'] !== null
    ? 'desde ~' . lw_precio_fmt($est['total']) . ' EUR' . ($est['parcela'] === null ? ' (villa sola, sin parcela)' : '')
    // Si el techo no valida, el visitante SÍ vio una cifra igualmente (el panel arranca con
    // sirap pintado en servidor): decir "(sin calcular)" bajo un encabezado que afirma "lo
    // que vio en pantalla" sería falso. Se dice qué pasó de verdad.
    : '(no reconstruible: la seleccion no llego completa)';

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

// ── Purga a 90 días ────────────────────────────────────────────────────────────────
// Las dos políticas de privacidad PROMETEN 90 días de conservación de este aviso interno,
// y hasta hoy no había nada que lo cumpliera: una regla escrita sin guardrail. Ahora que el
// fichero guarda además una estimación económica junto a la IP, la promesa tenía que
// empezar a ser cierta. Se hace aquí, de forma oportunista al escribir, en vez de con un
// cron: no hace falta acceso a la infraestructura y este endpoint es el único que escribe.
// Cubre también el v1 congelado del 2-sep, que si no se quedaría eterno.
$purga = function ($ruta) {
    if (!is_file($ruta) || filesize($ruta) === 0) return;
    $corte = strtotime('-90 days');
    $fh = @fopen($ruta, 'r');
    if ($fh === false) return;
    $vivas = [];
    $cabecera = fgetcsv($fh);
    while (($f = fgetcsv($fh)) !== false) {
        // La fecha es siempre la primera columna, en las dos versiones del fichero. Una
        // fila con fecha ilegible se CONSERVA: ante la duda no se borra un dato.
        $ts = isset($f[0]) ? strtotime($f[0]) : false;
        if ($ts === false || $ts >= $corte) $vivas[] = $f;
    }
    fclose($fh);
    // Solo se reescribe si de verdad hay algo que quitar.
    if (count($vivas) === 0 && $cabecera === false) return;
    $antes = 0;
    $c = @file($ruta, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($c !== false) $antes = max(0, count($c) - 1);
    if ($antes <= count($vivas)) return;
    $tmpF = $ruta . '.tmp';
    $out = @fopen($tmpF, 'w');
    if ($out === false) return;
    if ($cabecera !== false) fputcsv($out, $cabecera);
    foreach ($vivas as $f) { fputcsv($out, $f); }
    fclose($out);
    @rename($tmpF, $ruta);
};
$purga($file);
$purga($dir . '/bookings_calendly.csv');

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
    // Los dos matices que hacen que ventas cite otro numero en la llamada (Administracion,
    // capa 1 de deploy): sumar el 11% que ya esta dentro, o dar el euro como si fuera la
    // moneda del contrato cuando el propio FAQ de la pagina dice que se firma en rupias.
    . "  SI incluye el PPN indonesio: no se le suma un 11% encima en la llamada.\n"
    . "  EUR orientativo. El contrato se firma en IDR al cambio de la fecha.\n"
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
