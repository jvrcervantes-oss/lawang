<?php
/**
 * Autochequeo de la regla «ficha de modelo indexable = publicable y con precio cerrado»:
 *   php modelo/tests/indexable_test.php
 * (lo corre tools/test.py de la agencia: tests/*_test.php, sale con 1 si algo falla). Solo CLI.
 *
 * Afirma UN hecho contra TODOS los sitios donde vive, no una funcion suelta:
 *   · modelo/index.php  — la ficha con precio NO lleva <meta name="robots">; la que no tiene, SI
 *   · modelo/v1.php     — la ficha archivada la lleva SIEMPRE, tenga o no precio
 *   · sitemap.php       — lista exactamente las fichas que se han pintado sin noindex
 *   · modelo/lib.php    — lw_modelo_indexable() es la unica que escribe la condicion
 *
 * Porque existe (14-oct-2026): al publicar la v2 como ficha (24-sep) se arrastro su noindex
 * fijo y las fichas con precio pidieron a Google no salir durante 20 dias mientras el sitemap
 * las listaba. Nada lo detecto: no habia nada que mirase las dos cosas a la vez.
 *
 * NO fija datos de hoy («dali si, loftbung no»): el dia que el owner ponga precio a un modelo
 * desde la intranet esto tiene que seguir en verde. Lo que fija es que los sitios coincidan
 * con la regla. Las dos ramas de la regla se prueban siempre con dobles (seccion 1); con las
 * fichas reales se prueba lo que el catalogo de ese dia permita, y se DICE si una rama no se
 * ha podido ejercitar con ellas.
 */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

$RAIZ = dirname(__DIR__, 2);
require $RAIZ . '/modelo/datos.php'; // tambien carga lib.php y catalogo.php
$M = require $RAIZ . '/modelo/modelos.php';

$fallos = 0;
function ok($cond, $msg) {
    global $fallos;
    if (!$cond) { $fallos++; echo "FALLO: $msg\n"; }
}

/** Corre un PHP aparte (cada plantilla hace `exit`, declara funciones y pinta) y devuelve su
 *  salida. stderr va a la papelera del sistema: leerlo despues de stdout por una tuberia
 *  puede dejar colgados a los dos si se llena. */
function corre(array $args, $cwd) {
    $nul = PHP_OS_FAMILY === 'Windows' ? 'NUL' : '/dev/null';
    $p = proc_open(array_merge([PHP_BINARY], $args), [1 => ['pipe', 'w'], 2 => ['file', $nul, 'w']], $pipes, $cwd);
    if (!is_resource($p)) return '';
    $out = stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    proc_close($p);
    return (string) $out;
}
function pinta($plantilla, $id, $raiz) {
    $runner = '$_GET["m"]=$argv[1]; require ' . var_export($raiz . '/modelo/' . $plantilla, true) . ';';
    return corre(['-r', $runner, $id], $raiz);
}
/** «No lleva noindex» tambien lo cumple una pagina vacia o rota: antes de mirar la etiqueta
 *  se comprueba que la ficha se ha pintado entera (su canonica y el cierre del documento). */
function pintada($html, $id) {
    return strpos($html, '<link rel="canonical" href="https://lawangproperties.com/modelo/' . $id . '">') !== false
        && strpos($html, '</html>') !== false;
}
function lleva_noindex($html) {
    return (bool) preg_match('~<meta\s+name="robots"\s+content="[^"]*noindex~i', $html);
}

// ── 1. La regla, con dobles: las dos ramas, sin depender del catalogo de hoy ──────────────
$techo = ['now' => 100000, 'y2027' => 110000];
ok(lw_modelo_indexable(['id' => 'doble', 'imgs' => [], 'techos' => ['plano' => $techo]]) === true,
    'doble CON precio cerrado: tiene que ser indexable');
ok(lw_modelo_indexable(['id' => 'doble', 'imgs' => []]) === false,
    'doble SIN techos (sin precio): no puede ser indexable');
ok(lw_modelo_indexable(['id' => 'doble', 'imgs' => [], 'techos' => []]) === false,
    'doble con techos vacios: no puede ser indexable');
// Un techo que solo se vende en un proyecto no da precio a la ficha generica (lw_techos_para):
// esa ficha enseña «Upon request», asi que tampoco se indexa.
ok(lw_modelo_indexable(['id' => 'doble', 'imgs' => [], 'techos' => ['plano' => $techo + ['proyectos' => ['palmfield']]]]) === false,
    'doble cuyo unico techo es de un proyecto: la ficha generica no tiene precio, no es indexable');
ok(lw_modelo_indexable(null) === false, 'un modelo que no se puede publicar (null) nunca es indexable');

// ── 2. Las fichas reales: lo que se pinta coincide con la regla ───────────────────────────
// El oraculo se escribe aqui a proposito, sin llamar a lw_modelo_indexable(): si alguien
// cambia la funcion, tiene que cambiar tambien esta linea, que es la regla dicha en claro.
$publicables = []; $sinNoindex = []; $conPrecio = 0; $sinPrecio = 0;
foreach (array_keys($M) as $id) {
    $mm = lw_modelo_get($id, $M);
    if ($mm === null) continue; // sin landing: index.php redirige, no hay ficha que mirar
    $id = $mm['id'];
    $publicables[] = $id;
    $tienePrecio = lw_precio_fmt(lw_modelo_precio_desde($mm)) !== null;
    $tienePrecio ? $conPrecio++ : $sinPrecio++;
    ok(lw_modelo_indexable($mm) === $tienePrecio, "$id: lw_modelo_indexable() no coincide con «tiene precio cerrado»");

    $html = pinta('index.php', $id, $RAIZ);
    if (!pintada($html, $id)) { ok(false, "$id: modelo/index.php no ha pintado la ficha entera (no se puede mirar su noindex)"); continue; }
    $noindex = lleva_noindex($html);
    ok($noindex === !$tienePrecio, $tienePrecio
        ? "$id tiene precio y su ficha lleva noindex: pide a Google no salir"
        : "$id no tiene precio y su ficha NO lleva noindex");
    if (!$noindex) $sinNoindex[] = $id;

    $v1 = pinta('v1.php', $id, $RAIZ);
    if (!pintada($v1, $id)) { ok(false, "$id: modelo/v1.php no ha pintado la ficha entera (no se puede mirar su noindex)"); continue; }
    ok(lleva_noindex($v1), "$id: la ficha archivada (modelo/v1.php) tiene que llevar noindex siempre");
}
ok(count($publicables) > 0, 'el catalogo no trae ninguna ficha publicable: no se ha podido comprobar nada');

// ── 3. El sitemap lista exactamente las fichas que se han pintado sin noindex ─────────────
$sitemap = corre([$RAIZ . '/sitemap.php'], $RAIZ);
ok(function_exists('simplexml_load_string') && @simplexml_load_string($sitemap) !== false, 'sitemap.php no devuelve un XML bien formado');
preg_match_all('~<loc>https://lawangproperties\.com/modelo/([^<]+)</loc>~', $sitemap, $mt);
$enSitemap = $mt[1];
sort($enSitemap); sort($sinNoindex);
ok($enSitemap === $sinNoindex,
    'modelos del sitemap ' . json_encode($enSitemap) . ' != fichas pintadas sin noindex ' . json_encode($sinNoindex));
ok(strpos($sitemap, '/modelo/v1/') === false, 'el sitemap no puede listar la ficha archivada (/modelo/v1/…)');

// ── 4. Nadie ha vuelto a escribir la condicion por su cuenta ──────────────────────────────
// Con el catalogo de un dia cualquiera, dos condiciones distintas pueden dar lo mismo (si
// todas las fichas tienen precio, «siempre» y «con precio» coinciden). Esto mira el codigo:
// la unica etiqueta robots de index.php cuelga de la funcion, y el sitemap la llama.
$src = (string) file_get_contents($RAIZ . '/modelo/index.php');
ok(substr_count($src, 'name="robots"') === 1, 'modelo/index.php tiene que tener UNA sola etiqueta robots');
ok((bool) preg_match('~<\?php if \(!lw_modelo_indexable\(\$m\)\):[^\n]*\?>\s*<meta name="robots" content="noindex, nofollow">\s*<\?php endif; \?>~', $src),
    'la etiqueta robots de modelo/index.php tiene que colgar de !lw_modelo_indexable($m), no de una condicion propia');
$srcMap = (string) file_get_contents($RAIZ . '/sitemap.php');
ok(strpos($srcMap, 'lw_modelo_indexable(') !== false && strpos($srcMap, 'lw_modelo_precio_desde(') === false,
    'sitemap.php tiene que decidir con lw_modelo_indexable(), no con una condicion de precio propia');

if ($fallos) { echo "\n$fallos FALLO(S)\n"; exit(1); }
// Una rama que el catalogo de hoy no deja ejercitar con fichas reales se dice, no se calla:
// queda cubierta solo por los dobles (1) y por la lectura del codigo (4).
if ($conPrecio === 0) echo "(aviso: hoy ninguna ficha publicable tiene precio; «con precio → sin noindex» solo se ha probado con dobles)\n";
if ($sinPrecio === 0) echo "(aviso: hoy todas las fichas publicables tienen precio; «sin precio → con noindex» solo se ha probado con dobles)\n";
echo 'OK: indexable = con precio, en la ficha, en la archivada y en el sitemap ('
    . count($publicables) . " fichas: $conPrecio con precio, $sinPrecio sin).\n";
