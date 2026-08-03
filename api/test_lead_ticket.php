<?php
/**
 * test_lead_ticket.php — CLI, sin framework:
 *
 *     php api/test_lead_ticket.php
 *
 * Comprueba lo no trivial del campo de presupuesto:
 *   1. que el rango que elige el lead llega intacto al CSV y que lo que no esta en la lista
 *      se guarda como "no contesto" en vez de colarse,
 *   2. que un CSV que YA existe con la cabecera vieja de 10 columnas se migra a 11 sin
 *      perder ni descolocar las filas anteriores.
 * El (2) es el camino que corre de verdad en produccion: alli el fichero existe desde hace
 * semanas, asi que la rama "fichero nuevo" no se ejecuta nunca.
 *
 * Corre sobre una COPIA del arbol en el temporal. `lead.php` escribe en `../private`, y un
 * test que mete filas falsas en el `leads_llamada.csv` de produccion es peor que no tener
 * test: ventas trabaja ese fichero. Un caso por proceso, porque `lead.php` acaba en exit().
 *
 * El hijo corre con el transporte de correo apuntando a la nada. `lead.php` avisa a ventas
 * en cada alta, y sin esto una pasada del test mete ~10 leads falsos en el buzon del
 * cliente. Se hace por transporte y NO con `disable_functions=mail`: en PHP 8 una funcion
 * deshabilitada pasa a ser inexistente y `@mail()` lanza un Error fatal en vez de devolver
 * false — el arnes moria antes de escribir el CSV. Asi, `mail()` existe, falla, la columna
 * `avisado` queda en "NO" y no sale nada del servidor.
 */
// Mismo guard que api/test_ghl.php, y por el mismo motivo: el fichero vive en el webroot de
// una landing que paga trafico. El patron del .htaccess raiz NO basta — `RedirectMatch` casa
// la URL, asi que /api/test_lead_ticket.php/x no acaba en `.php` y se colaba: verificado en
// produccion el 3-ago-2026 (500 = ejecuto; test_ghl.php respondio 404 porque lleva esta
// linea). Sin ella, un anonimo dispara el runner, que lanza un proceso php por caso y un
// correo a ventas en cada uno. El guard viaja con el fichero y sobrevive a un despliegue
// que se lleve el .htaccess.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

// ── Hijo: simula la peticion y deja que corra el lead.php de verdad ──────────────
if ($argc > 1) {
    $raiz = getenv('LW_TEST_ROOT');
    $_SERVER['REQUEST_METHOD'] = 'POST';
    $_SERVER['REMOTE_ADDR']    = '203.0.113.7';
    $_POST = [
        'name'        => 'Test Presupuesto',
        'email'       => 'test@example.com',
        'phone'       => '600111222',
        'consent'     => '1',
        'property'    => 'dali',
        'source'      => 'test-presupuesto',
        'presupuesto' => $argv[1],
    ];
    include $raiz . '/api/lead.php';
    exit;
}

// ── Utilidades del runner ───────────────────────────────────────────────────────
/** Arbol de mentira: copia de api/ bajo un raiz propio. */
function lw_arbol($sufijo)
{
    $tmp = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'lw_presu_' . getmypid() . '_' . $sufijo;
    @mkdir($tmp . '/api', 0777, true);
    @mkdir($tmp . '/private', 0777, true);
    foreach (glob(__DIR__ . '/*.php') as $f) {
        copy($f, $tmp . '/api/' . basename($f));
    }
    return $tmp;
}

function lw_corre($tmp, $valor)
{
    putenv('LW_TEST_ROOT=' . $tmp);
    $salida = [];
    // Windows manda por SMTP y un puerto muerto le hace devolver false. En Linux (el
    // servidor) hace falta `sendmail_path`, pero ese mismo ajuste en Windows es PEOR que no
    // ponerlo: PHP lanza el comando por popen y NO mira su codigo de salida, asi que
    // `mail()` devuelve true igual y el aislamiento queda de adorno. Por eso va por
    // plataforma y no "los dos por si acaso" — medido el 3-ago-2026.
    $sinCorreo = ' -d SMTP=127.0.0.1 -d smtp_port=1'
        . (DIRECTORY_SEPARATOR === '/' ? ' -d sendmail_path=/bin/false' : '');
    exec(escapeshellarg(PHP_BINARY) . $sinCorreo
        . ' ' . escapeshellarg($tmp . '/api/test_lead_ticket.php')
        . ' ' . escapeshellarg($valor) . ' 2>&1', $salida, $rc);
    // Un hijo que muere en silencio deja el CSV corto y el unico sintoma seria un recuento
    // de filas raro. La primera vez que corrio esto, `lead.php` petaba por una extension
    // ausente y el runner no dijo ni una palabra.
    if ($rc !== 0) {
        fwrite(STDERR, "FALLO: el hijo con presupuesto={$valor} salio con $rc:\n"
            . implode("\n", $salida) . "\n");
        exit(1);
    }
}

function lw_lee_csv($tmp)
{
    $csv = $tmp . '/private/leads_llamada.csv';
    // Una sonda que no consigue leer lo que iba a comparar tiene que abortar: si el CSV no
    // existe, cero comparaciones pasan cero asserts y el test dice "OK" sin probar nada.
    if (!is_file($csv)) {
        fwrite(STDERR, "FALLO: lead.php no escribio $csv — ningun caso llego a guardarse.\n");
        exit(1);
    }
    return array_map('str_getcsv', file($csv, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES));
}

function lw_limpia($tmp)
{
    foreach (['/api/*', '/private/ratelimit/*', '/private/*'] as $g) {
        array_map('unlink', array_filter(glob($tmp . $g) ?: [], 'is_file'));
    }
    @rmdir($tmp . '/private/ratelimit'); @rmdir($tmp . '/private');
    @rmdir($tmp . '/api');              @rmdir($tmp);
}

$fallos = 0;

// ── 1. Fichero nuevo: el rango llega intacto y la basura no se cuela ─────────────
$casos = [
    ['alto',      'Mas de 175.000 EUR'],
    ['medio',     'Entre 100.000 y 175.000 EUR'],
    ['bajo',      'Menos de 100.000 EUR'],
    ['nose',      'Todavia no lo tiene claro'],   // respuesta, no silencio
    ['',          ''],                            // el select llego sin elegir
    ['ALTO',      ''],                            // la lista distingue mayusculas
    ['175000',    ''],                            // el codigo viejo, por si vuelve un cache
    ['<script>',  ''],
];

$t1 = lw_arbol('nuevo');
foreach ($casos as $c) lw_corre($t1, $c[0]);

$filas = lw_lee_csv($t1);
$cab   = array_shift($filas);

assert(end($cab) === 'presupuesto', 'la cabecera del CSV no acaba en la columna presupuesto');
assert(count($filas) === count($casos),
    'se esperaban ' . count($casos) . ' filas y hay ' . count($filas));

// El contrato de verdad, por encima de caso a caso: del endpoint solo sale una de estas
// cinco cadenas. Es lo que hace que la rama del seguimiento en GHL no tenga que defenderse
// de valores raros, y lo que evita que GHL descarte el contacto por una opcion invalida.
$opciones = ['', 'Menos de 100.000 EUR', 'Entre 100.000 y 175.000 EUR',
             'Mas de 175.000 EUR', 'Todavia no lo tiene claro'];

foreach ($casos as $i => $c) {
    $visto = end($filas[$i]);
    assert(in_array($visto, $opciones, true), "se guardo un valor fuera de la lista: $visto");
    if ($visto !== $c[1]) {
        fwrite(STDERR, sprintf("FALLO caso %d: enviado %s -> esperado %s, guardado %s\n",
            $i, var_export($c[0], true), var_export($c[1], true), var_export($visto, true)));
        $fallos++;
    }
}

// El campo nuevo no puede haber corrido ninguna columna de las que ya habia.
assert($filas[0][4] === 'dali', 'la columna modelo se ha desplazado');
assert($filas[0][7] === 'si',   'la columna consentimiento se ha desplazado');
// Y no puede haber salido ni un correo: si esto falla, el test esta escribiendo a ventas.
assert($filas[0][9] === 'NO',   'el hijo mando correo — mail() no quedo deshabilitada');

lw_limpia($t1);

// ── 2. Fichero que YA existe con la cabecera vieja (el caso de produccion) ───────
$t2  = lw_arbol('viejo');
$vieja = ['timestamp','nombre','email','telefono','modelo','source','campana',
          'consentimiento','ip','avisado'];
$previa = ['2026-07-31T10:00:00+00:00','Lead Antiguo','viejo@example.com','+34600000000',
           'dali','landing-modelo','','si','198.51.100.9','si'];
$fh = fopen($t2 . '/private/leads_llamada.csv', 'w');
fputcsv($fh, $vieja);
fputcsv($fh, $previa);
fclose($fh);

lw_corre($t2, 'alto');

$filas2 = lw_lee_csv($t2);
$cab2   = array_shift($filas2);

if (end($cab2) !== 'presupuesto') {
    fwrite(STDERR, "FALLO migracion: la cabecera vieja no se actualizo — quedo: "
        . implode(',', $cab2) . "\n");
    $fallos++;
}
if (count($filas2) !== 2) {
    fwrite(STDERR, 'FALLO migracion: se esperaban 2 filas y hay ' . count($filas2) . "\n");
    $fallos++;
} else {
    // La fila anterior tiene que seguir entera y en su sitio: una migracion que reescribe
    // el fichero es justo donde se pierden los leads que ya estaban dentro.
    if (array_slice($filas2[0], 0, 10) !== $previa) {
        fwrite(STDERR, "FALLO migracion: la fila anterior se altero.\n");
        $fallos++;
    }
    if (end($filas2[1]) !== 'Mas de 175.000 EUR') {
        fwrite(STDERR, "FALLO migracion: la fila nueva no trae el rango.\n");
        $fallos++;
    }
}
// Que no queden restos del temporal de la migracion.
assert(!is_file($t2 . '/private/leads_llamada.csv.tmp'), 'quedo un .tmp sin renombrar');

lw_limpia($t2);

if ($fallos) { fwrite(STDERR, "$fallos comprobacion(es) mal.\n"); exit(1); }
echo 'OK — ' . count($casos) . " casos + migracion de cabecera vieja.\n";
