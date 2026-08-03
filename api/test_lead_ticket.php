<?php
/**
 * test_lead_ticket.php — CLI, sin framework:
 *
 *     php api/test_lead_ticket.php
 *
 * Comprueba lo unico no trivial que trajo el campo de presupuesto: que el suelo del rango
 * llega entero al CSV, y que cualquier valor fuera de la lista cae a 0 en vez de colarse.
 * Importa porque esa cifra es la que separa el seguimiento por gama en el CRM: un valor
 * inventado que se cuela manda a un lead de 200k a la cola de entrada, y al reves.
 *
 * Corre sobre una COPIA del arbol en el temporal. `lead.php` escribe en `../private`, y un
 * test que mete filas falsas en el `leads_llamada.csv` de produccion es peor que no tener
 * test: ventas trabaja ese fichero. Un caso por proceso, porque `lead.php` acaba en exit().
 */

// ── Hijo: simula la peticion y deja que corra el lead.php de verdad ──────────────
if (PHP_SAPI === 'cli' && $argc > 1) {
    $raiz = getenv('LW_TEST_ROOT');
    $_SERVER['REQUEST_METHOD'] = 'POST';
    $_SERVER['REMOTE_ADDR']    = '203.0.113.7';
    $_POST = [
        'name'     => 'Test Ticket',
        'email'    => 'test@example.com',
        'phone'    => '600111222',
        'consent'  => '1',
        'property' => 'dali',
        'source'   => 'test-ticket',
        'ticket'   => $argv[1],
    ];
    include $raiz . '/api/lead.php';
    exit;
}

// ── Runner ──────────────────────────────────────────────────────────────────────
$tmp = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'lw_ticket_' . getmypid();
@mkdir($tmp . '/api', 0777, true);
foreach (glob(__DIR__ . '/*.php') as $f) {
    copy($f, $tmp . '/api/' . basename($f));
}
putenv('LW_TEST_ROOT=' . $tmp);

// [valor que manda el navegador, entero que debe acabar en el CSV]
$casos = [
    ['175000',        175000],  // gama alta
    ['100000',        100000],
    ['25000',         25000],
    ['0',             0],       // "todavia no lo tengo claro"
    ['',              0],       // el select llego sin elegir
    ['99999',         0],       // numero plausible pero fuera de la lista
    ['abc',           0],
    ['250000',        0],       // por encima del ultimo tramo: no existe, no se inventa
    // Basura que al castear cae JUSTO sobre un tramo real. Guarda 175000 y esta bien: lo
    // que protege el CRM no es adivinar la intencion de quien manipula el formulario, es
    // que del endpoint solo salgan enteros de la lista. Este caso existe para que quede
    // escrito, porque al escribirlo di por hecho lo contrario y el test me corrigio.
    ['175000 OR 1=1', 175000],
];

foreach ($casos as $c) {
    $salida = [];
    exec(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($tmp . '/api/test_lead_ticket.php')
        . ' ' . escapeshellarg($c[0]) . ' 2>&1', $salida, $rc);
    // Un hijo que muere en silencio deja el CSV corto y el unico sintoma seria un recuento
    // de filas raro. La primera vez que corrio esto, `lead.php` petaba por una extension
    // ausente y el runner no dijo ni una palabra.
    if ($rc !== 0) {
        fwrite(STDERR, "FALLO: el hijo con ticket={$c[0]} salio con $rc:\n"
            . implode("\n", $salida) . "\n");
        exit(1);
    }
}

$csv = $tmp . '/private/leads_llamada.csv';
// Una sonda que no consigue leer lo que iba a comparar tiene que abortar: si el CSV no
// existe, cero comparaciones pasan cero asserts y el test dice "OK" sin haber probado nada.
if (!is_file($csv)) {
    fwrite(STDERR, "FALLO: lead.php no escribio $csv — ningun caso llego a guardarse.\n");
    exit(1);
}

$filas = array_map('str_getcsv', file($csv, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES));
$cab   = array_shift($filas);

assert(end($cab) === 'ticket', 'la cabecera del CSV no acaba en la columna ticket');
assert(count($filas) === count($casos),
    'se esperaban ' . count($casos) . ' filas y hay ' . count($filas));

// El contrato de verdad, por encima de caso a caso: pase lo que pase por el formulario,
// del endpoint solo sale uno de estos cuatro enteros. Es lo que hace que la rama del
// seguimiento en GHL no tenga que defenderse de valores raros.
$tramos = [0, 25000, 100000, 175000];

$fallos = 0;
foreach ($casos as $i => $c) {
    $visto = (int) end($filas[$i]);
    assert(in_array($visto, $tramos, true), "se guardo un valor fuera de los tramos: $visto");
    if ($visto !== $c[1]) {
        fwrite(STDERR, sprintf("FALLO caso %d: enviado %s -> esperado %d, guardado %d\n",
            $i, var_export($c[0], true), $c[1], $visto));
        $fallos++;
    }
}

// El consentimiento y el modelo siguen viajando: el campo nuevo no puede haber corrido
// ninguna columna de las que ya habia.
assert($filas[0][4] === 'dali',  'la columna modelo se ha desplazado');
assert($filas[0][7] === 'si',    'la columna consentimiento se ha desplazado');

array_map('unlink', glob($tmp . '/api/*') ?: []);
array_map('unlink', glob($tmp . '/private/ratelimit/*') ?: []);
@unlink($csv);
@rmdir($tmp . '/private/ratelimit');
@rmdir($tmp . '/private');
@rmdir($tmp . '/api');
@rmdir($tmp);

if ($fallos) { fwrite(STDERR, "$fallos caso(s) mal.\n"); exit(1); }
echo 'OK — ' . count($casos) . " casos: el rango llega intacto y lo que no esta en la lista vale 0.\n";
