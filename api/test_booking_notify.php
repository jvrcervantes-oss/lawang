<?php
/**
 * Autochequeo de api/booking-notify.php:  php api/test_booking_notify.php
 *
 * Creado el 3-sep-2026 con el configurador con presupuesto. Existe porque a partir de ese
 * día este endpoint deja de ser "la campanita" y pasa a producir la CIFRA que ventas lee
 * antes de llamar al lead — y no tiene auth, así que todo lo que llega por POST es hostil
 * por defecto. Lo que se afirma aquí no se puede afirmar en test_modelo.php: aquel prueba
 * la aritmética, este prueba que el endpoint no se cree lo que le cuentan.
 *
 * Solo CLI — si alguien lo pide por web devuelve 404, no es una página del sitio.
 * Ver [[reference_htaccess_pathinfo_bypass]] para el porqué del guard.
 */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

$RAIZ = dirname(__DIR__);
$tmp  = sys_get_temp_dir() . '/lw_booking_' . getmypid();
@mkdir($tmp . '/api', 0777, true);
@mkdir($tmp . '/modelo', 0777, true);
foreach (glob($RAIZ . '/api/*.php') as $f) { copy($f, $tmp . '/api/' . basename($f)); }
foreach (glob($RAIZ . '/modelo/*.php') as $f) { copy($f, $tmp . '/modelo/' . basename($f)); }

$fallos = 0;
function ok($c, $m) { global $fallos; if (!$c) { $fallos++; echo "FALLO: $m\n"; } }

/**
 * Lanza una petición real contra una copia del endpoint, en su propio proceso.
 * El correo se aísla con SMTP a un puerto muerto y se asierta sobre la columna `avisado`:
 * `-d disable_functions=mail` NO vale (en PHP 8 la función pasa a inexistente y @mail()
 * lanza un Error fatal), y en Windows `sendmail_path` tampoco (PHP no mira el código de
 * salida del comando y mail() devuelve true igual).
 */
function llama($tmp, array $post) {
    $arn = $tmp . '/arnes.php';
    // base64 y no JSON crudo: en Windows escapeshellarg() SUSTITUYE las comillas dobles por
    // espacios, así que el JSON llegaba destrozado, json_decode devolvía null y el endpoint
    // respondía 422 sin escribir nada — el test "fallaba" sin que el código tuviera nada.
    file_put_contents($arn, '<?php $_POST = json_decode(base64_decode($argv[1]), true);'
        . ' $_SERVER["REQUEST_METHOD"]="POST"; $_SERVER["REMOTE_ADDR"]="203.0.113." . rand(1,250);'
        . ' require ' . var_export($tmp . '/api/booking-notify.php', true) . ';');
    $aisla = stripos(PHP_OS, 'WIN') === 0
        ? '-d SMTP=127.0.0.1 -d smtp_port=1'
        : '-d sendmail_path=/bin/false';
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . $aisla . ' '
         . escapeshellarg($arn) . ' ' . escapeshellarg(base64_encode(json_encode($post)));
    exec($cmd . ' 2>&1', $out);
    $r = implode("\n", $out);
    // Toda sonda aborta si no consigue lo que iba a comparar: un arnés roto que devuelve
    // "todo bien" es peor que un test que no existe.
    if (strpos($r, '"ok":true') === false) { echo "ARNES: la llamada no fue OK -> $r\n"; }
    return $r;
}

$base = [
    'modelo' => 'dali', 'source' => 'ig', 'campana' => 'test',
    'event_uri'   => 'https://api.calendly.com/scheduled_events/AAA',
    'invitee_uri' => 'https://api.calendly.com/scheduled_events/AAA/invitees/BBB',
];

// 1. Caso bueno: Dali/bambú (50.000) + Bali/beachfront 500 m² a 250 = 175.000.
llama($tmp, $base + ['techo' => 'bambu', 'island' => 'bali', 'view' => 'beachfront',
                     'parcela_m2' => '500', 'extras' => 'sauna']);
// 2. El navegador manda un importe inventado: no puede aparecer en ningún sitio.
llama($tmp, $base + ['techo' => 'sirap', 'island' => 'sumba', 'parcela_m2' => '300',
                     'estimacion' => '999999999', 'total' => '1']);
// 3. Todo fuera de catálogo + m² hostil + inyección de fórmula CSV.
llama($tmp, $base + ['techo' => '<script>', 'island' => 'marte', 'view' => 'volcano',
                     'extras' => 'sauna,jacuzzi-inventado,=cmd|calc', 'parcela_m2' => '1e9']);
// 4. Vista de Bali junto a Sumba: imposible en la interfaz, trivial por POST.
llama($tmp, $base + ['techo' => 'sirap', 'island' => 'sumba', 'view' => 'beachfront',
                     'parcela_m2' => '400']);

$csv = $tmp . '/private/bookings_calendly_v2.csv';
ok(is_file($csv), 'debe escribirse el CSV v2 (el v1 ya existe en produccion con 11 columnas)');
ok(is_file($tmp . '/private/.htaccess'), 'private/ debe recibir su propio .htaccess de denegacion');
if (!is_file($csv)) { echo "1 fallo(s)\n"; exit(1); }

$crudo = file_get_contents($csv);
$filas = array_map('str_getcsv', array_filter(explode("\n", trim($crudo))));
$cab   = array_shift($filas);
// La cabecera y la fila salen del MISMO array asociativo: si alguien añade un campo a uno
// y no al otro, esto lo dice en vez de escribir filas desalineadas en silencio para siempre.
foreach ($filas as $i => $f) {
    ok(count($f) === count($cab), 'la fila ' . ($i + 1) . ' debe tener tantas columnas como la cabecera');
}
$r = array_map(function ($f) use ($cab) { return array_combine($cab, $f); }, $filas);
ok(count($r) === 4, 'deben escribirse 4 filas, salieron ' . count($r));

ok($r[0]['total_servidor'] === '175000', 'bambu + beachfront 500m2 = 175000, salio ' . $r[0]['total_servidor']);
ok($r[0]['precio_villa'] === '50000', 'el techo elegido manda: bambu son 50000, no el 48000 del sirap');
ok($r[0]['tarifa_m2'] === '250', 'beachfront debe cotizar a 250');
ok($r[0]['tramo'] === '2026', 'el tramo de precio se registra explicito, no se deduce del timestamp');
ok($r[0]['avisado'] === 'NO', 'AISLAMIENTO ROTO: si esto dice "si", el test esta mandando correos de verdad a ventas');

ok($r[1]['total_servidor'] === '85500', 'sumba 300m2 = 48000+37500 = 85500, salio ' . $r[1]['total_servidor']);
ok(strpos($crudo, '999999999') === false, 'el importe que mando el navegador NO puede aparecer: la cifra la calcula el servidor');

ok($r[2]['techo'] === '', 'un techo fuera de catalogo se guarda vacio, no "raro"');
ok($r[2]['island'] === '', 'una isla inventada se guarda vacia');
ok($r[2]['view'] === '', 'una vista inventada se guarda vacia');
ok($r[2]['extras'] === 'sauna', 'solo sobreviven los extras del catalogo, salio "' . $r[2]['extras'] . '"');
ok(strpos($crudo, 'jacuzzi-inventado') === false, 'un extra inventado no llega al CSV ni al correo');
ok(strpos($crudo, 'calc') === false, 'la inyeccion de formula de Excel no llega al CSV');
ok($r[2]['parcela_m2'] === '1500', '1e9 m2 debe toparse a 1500, salio ' . $r[2]['parcela_m2']);
ok($r[2]['total_servidor'] === '', 'sin techo valido no hay total (vacio, nunca un 0)');

ok($r[3]['view'] === '', 'una vista de Bali junto a Sumba debe ignorarse');
ok($r[3]['tarifa_m2'] === '125', 'Sumba mantiene su tarifa aunque llegue una vista de Bali');
ok($r[3]['total_servidor'] === '98000', 'sumba 400m2 = 48000+50000 = 98000, salio ' . $r[3]['total_servidor']);

// Limpieza: el arnés no deja basura en el temporal del sistema.
foreach (['/private/bookings_calendly_v2.csv', '/private/.htaccess', '/arnes.php'] as $f) { @unlink($tmp . $f); }
foreach (glob($tmp . '/api/*') as $f) { @unlink($f); }
foreach (glob($tmp . '/modelo/*') as $f) { @unlink($f); }
foreach (glob($tmp . '/private/*') as $f) { @unlink($f); }
@rmdir($tmp . '/private'); @rmdir($tmp . '/api'); @rmdir($tmp . '/modelo'); @rmdir($tmp);

echo $fallos === 0 ? "OK — el endpoint aguanta\n" : "$fallos fallo(s)\n";
exit($fallos === 0 ? 0 : 1);
