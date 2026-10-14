<?php
/**
 * Autochequeo de la lectura unica de The Collection:  php coleccion/tests/coleccion_test.php
 * (lo corre tools/test.py: tests/*_test.php, sale con 1 si algo falla). Solo CLI.
 *
 * QUE NO COMPRUEBA SIN CATALOGO (14-oct-2026). data.json esta en .gitignore: no lo tienen ni las copias de sesion
 * ni la copia que monta el control (tools/test.py), asi que EN EL CONTROL el apartado 7b no corre NUNCA. Sin el,
 * este verde NO dice:
 *   · que la lista blanca (contrato_publico.json) cubra todas las claves de las fichas visibles publicadas hoy
 *     (una clave nueva escrita desde el panel se recortaria en silencio y cambiaria un render);
 *   · que lw_coleccion() devuelva exactamente las visibles del catalogo real.
 * Todo lo demas (contrato, niveles, fuente envenenada, ids en los tres sitios) corre con datos sinteticos y con
 * el respaldo versionado. Sin catalogo acaba en «OK PARCIAL» y sale con 0: no puede ser un rojo donde lo normal
 * es no tener el fichero. Con `--exige-catalogo` sale con 3. ESA OPCION HOY NO LA LLAMA NADIE: esta para un
 * trabajo CON RED y fuera del control de push, que baje el data.json publicado y corra esto contra el. Para
 * eso falta ademas que 7b lea el catalogo de una ruta configurable (hoy solo mira la raiz del proyecto). Y el
 * data.json del clon principal NO vale como dato real: el 14-oct era una copia del 7-ago (por eso existe el
 * freno de publicar_data.py).
 *
 * Afirma HECHOS contra TODOS los sitios donde viven, no funciones sueltas — el fallo caro de
 * este estudio es el mismo dato en varios sitios que se separan:
 *   · que ficha se publica y que id vale: la tabla comun visibles_esperados.json, la misma que afirman
 *     assets/lawang-card.test.js (navegador) y test_publicar_data.py (14-oct-2026)
 *   · api/save.php no guarda lo que no tiene forma de catalogo: la regla a solas y el fichero ENTERO ejecutado en
 *     un arbol temporal (422 sin tocar data.json; 400, 401 y 405 como antes) (14-oct-2026)
 *   · ids de lw_coleccion() == ids del sitemap == ids que thecollection.php acepta (404 al resto)
 *   · con la fuente caida: cache vieja (stale) y luego respaldo (stale); nunca fatal
 *   · una clave prohibida hace FALLAR la fuente (log ruidoso) y no llega a la salida
 *   · la lista blanca cubre TODAS las claves que las fichas visibles traen hoy (si hay un
 *     data.json local) y el respaldo versionado cumple el contrato
 */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

$RAIZ = dirname(__DIR__, 2);
require $RAIZ . '/coleccion/lib.php';

$fallos = 0;
function ok($cond, $msg) {
    global $fallos;
    if (!$cond) { $fallos++; echo "FALLO: $msg\n"; }
}

$tmp = sys_get_temp_dir() . '/lw_coleccion_test_' . getmypid();
@mkdir($tmp, 0777, true);
$log = $tmp . '/php.log';
ini_set('log_errors', '1');
ini_set('error_log', $log);
function log_txt() { global $log; return is_file($log) ? (string) file_get_contents($log) : ''; }
function log_limpia() { global $log; @unlink($log); }
function escribe($ruta, $d) { file_put_contents($ruta, is_string($d) ? $d : json_encode($d)); }

function ficha($id, $extra = []) {
    return array_merge([
        'id' => $id, 'visible' => true, 'line' => 'signature', 'region' => 'Bali',
        'title' => ['en' => "Villa $id"], 'sub' => ['en' => 'sub'], 'desc' => ['en' => 'desc'],
        'priceEUR' => 250000, 'images' => ["/assets/img/$id.webp"],
        'extras' => [['name' => 'Pool', 'price' => 100]],
    ], $extra);
}
function doc($props) {
    return ['settings' => ['rates' => ['EUR' => 1], 'whatsapp' => '62811', 'email' => 'sales@x.test'],
            'properties' => $props, 'downloads' => ['signature' => [['name' => 'Brochure', 'url' => '']]]];
}
function cfg($tmp, array $o = []) {
    return array_merge([
        'fuente' => 'datajson', 'datajson' => $tmp . '/data.json', 'cache' => $tmp . '/cache.json',
        'respaldo' => $tmp . '/respaldo.json', 'contrato' => dirname(__DIR__) . '/contrato_publico.json', 'ttl' => 0,
        'rpc' => 'http://127.0.0.1:1/rpc', 'bucket' => 'https://sb.test/deck',
    ], $o);
}
function ids(array $d) { return array_map(function ($p) { return $p['id']; }, $d['properties']); }

// ── 1. Contrato: filtra visibles, descarta claves fuera de lista, SOLO lo publico ──────────
$fx = doc([ficha('uno'), ficha('dos', ['secreto_nuevo' => 'x']), ficha('oculta', ['visible' => false]),
           ficha('sin-flag', ['visible' => 'true']), ficha('tres'), ficha('mal id!')]);
$fx['settings']['clave_interna'] = 'x';
$r = lw_coleccion_aplica_contrato($fx, cfg($tmp)['contrato']);
ok(ids($r) === ['uno', 'dos', 'tres'], 'solo visible===true (no "true", no ocultas) y solo ids validos: ' . json_encode(ids($r)));
ok(!array_key_exists('secreto_nuevo', $r['properties'][1]), 'una clave fuera de la lista blanca se descarta');
ok(isset($r['properties'][0]['priceEUR'], $r['properties'][0]['extras']), 'las claves de la lista blanca pasan intactas');
ok(array_keys($r['settings']) === ['rates', 'whatsapp', 'email'] || array_diff(array_keys($r['settings']), ['rates', 'whatsapp', 'email']) === [], 'settings solo con claves permitidas');
ok(!isset($r['settings']['clave_interna']), 'una clave de settings fuera de contrato se descarta');
ok(array_keys($r) === ['properties', 'settings', 'downloads'], 'la salida es solo {properties, settings, downloads}');

// ── 1b. QUE FICHA SE PUBLICA y QUE ID VALE: la tabla comun (14-oct-2026) ───────────────────
// La MISMA tabla la afirman assets/lawang-card.test.js (LawangCard.publicada y esPublicada de admin.html) y
// coleccion/tests/test_publicar_data.py (ID_VALIDO y _visibles): una regla, cuatro implementaciones. Antes el
// navegador pintaba «todo lo que no sea false» y aqui «solo true»; y el `$` de PCRE aceptaba "cube\n".
$tablaVis = json_decode((string) file_get_contents(__DIR__ . '/visibles_esperados.json'), true);
ok(is_array($tablaVis) &&count($tablaVis['fichas'] ?? []) >= 15 && count($tablaVis['ids'] ?? []) >= 15 && strlen($tablaVis['id_permitidos'] ?? '') === 63,
   'la tabla comun de visibles (visibles_esperados.json) se lee y trae sus casos');
$esperadas = [];
foreach ($tablaVis['fichas'] as $c) {
    ok(lw_coleccion_publicada($c['ficha']) === $c['publicada'], "publicada ({$c['nota']}): dio " . var_export(lw_coleccion_publicada($c['ficha']), true));
    if ($c['publicada']) $esperadas[] = $c['ficha']['id'];
}
foreach ($tablaVis['ids'] as $c) {
    ok(lw_coleccion_id_valido($c['id']) === $c['valido'], 'id ' . json_encode($c['id']) . ' valido=' . var_export($c['valido'], true));
}
for ($n = 0; $n < 256; $n++) {
    ok(lw_coleccion_id_valido('a' . chr($n) . 'b') === (strpos($tablaVis['id_permitidos'], chr($n)) !== false), "caracter $n dentro de un id");
}
// y el filtro real (lo que sale por lw_coleccion) deja pasar exactamente las que la tabla dice
$r = lw_coleccion_aplica_contrato(['properties' => array_map(function ($c) { return $c['ficha']; }, $tablaVis['fichas'])], cfg($tmp)['contrato']);
ok(ids($r) === $esperadas && count($esperadas) === 2, 'lw_coleccion_aplica_contrato publica solo las de la tabla: ' . json_encode(ids($r)));

// ── 1c. api/save.php: la FORMA del catalogo, ANTES de escribir (14-oct-2026) ───────────────
// Hasta ese dia solo rechazaba lo que no era JSON: `[]`, un numero o un objeto sin `properties` se guardaban como
// catalogo y dejaban la web sin fichas. (a) la regla, a solas; (b) api/save.php ENTERO, en un arbol temporal.
$SECRETO = 'CONTENIDO-QUE-NO-DEBE-SALIR';
$f = function ($id, array $extra = []) use ($SECRETO) { return ['id' => $id, 'title' => ['en' => $SECRETO]] + $extra; };
$forma = function ($json) { return lw_coleccion_forma_invalida(json_decode($json, true)); }; // como save.php: decodifica y valida
$validos = [
    'catalogo normal'               => json_encode(['settings' => [], 'properties' => [$f('uno', ['visible' => true]), $f('dos', ['visible' => false])], 'downloads' => []]),
    'ficha sin la clave visible'    => json_encode(['properties' => [$f('uno')]]),
    'sin propiedades (el panel lo publica a proposito, tras confirmar)' => '{"properties":[]}',
    'el respaldo versionado'        => (string) file_get_contents(dirname(__DIR__) . '/respaldo.json'),
];
foreach ($validos as $nombre => $json) ok($forma($json) === null, "save: «$nombre» es un catalogo valido: " . var_export($forma($json), true));
$invalidos = [
    'lista vacia `[]`'              => ['[]', 'properties'],
    'un numero'                     => ['5', 'properties'],
    'un texto'                      => ['"hola"', 'properties'],
    'true'                          => ['true', 'properties'],
    'objeto sin properties'         => ['{"settings":{},"downloads":{}}', 'properties'],
    'una lista de catalogos'        => ['[{"properties":[]}]', 'properties'],
    'properties null'               => ['{"properties":null}', 'must be a list'],
    'properties texto'              => ['{"properties":"no"}', 'must be a list'],
    'properties objeto con nombres' => [json_encode(['properties' => ['uno' => $f('uno')]]), 'must be a list'],
    'una entrada que no es ficha'   => [json_encode(['properties' => [$f('uno'), 'texto']]), '#2 is not an object'],
    'ficha sin id'                  => [json_encode(['properties' => [['title' => ['en' => $SECRETO]]]]), '#1 has no valid id'],
    'ficha que es una lista'        => ['{"properties":[[1,2]]}', '#1 has no valid id'],
    'id repetido'                   => [json_encode(['properties' => [$f('uno'), $f('dos'), $f('uno')]]), '#3 repeats the id of property #1'],
    'visible "true" en texto'       => [json_encode(['properties' => [$f('uno', ['visible' => 'true'])]]), '#1: "visible" must be true or false'],
    'visible null'                  => [json_encode(['properties' => [$f('uno', ['visible' => null])]]), '#1: "visible" must be true or false'],
    'visible 1'                     => [json_encode(['properties' => [$f('uno'), $f('dos', ['visible' => 1])]]), '#2: "visible" must be true or false'],
    'visible 0'                     => [json_encode(['properties' => [$f('uno', ['visible' => 0])]]), '#1: "visible" must be true or false'],
];
foreach ($tablaVis['ids'] as $c) {   // los ids de la tabla comun: lo que la web no publicaria, save.php no lo guarda
    $json = json_encode(['properties' => [['id' => $c['id'], 'visible' => true]]]);
    if ($c['valido']) ok($forma($json) === null, 'save: id ' . json_encode($c['id']) . ' se acepta');
    else $invalidos['id ' . json_encode($c['id'])] = [$json, '#1 has no valid id'];
}
foreach ($invalidos as $nombre => $caso) {
    $e = $forma($caso[0]);
    ok(is_string($e) && strpos($e, $caso[1]) !== false, "save: «$nombre» se rechaza diciendo «{$caso[1]}»: " . var_export($e, true));
    ok(is_string($e) && strpos($e, $SECRETO) === false && strpos($e, 'mal id') === false, "save: el rechazo de «$nombre» no vuelca contenido");
}

// (b) api/save.php de verdad: copia de api/config.php + api/save.php + coleccion/lib.php en un arbol temporal, con su
// .passhash de mentira y su data.json. Sin servidor ni red: un proceso php por caso con la cabecera de origen, la sesion
// y php://input simulados. Afirma lo que importa: QUE responde y SI el data.json cambio.
$sitio = $tmp . '/sitio';
foreach (['/api', '/coleccion', '/sesiones'] as $d) @mkdir($sitio . $d, 0777, true);
copy($RAIZ . '/api/config.php', $sitio . '/api/config.php');
copy($RAIZ . '/api/save.php', $sitio . '/api/save.php');
copy($RAIZ . '/coleccion/lib.php', $sitio . '/coleccion/lib.php');
file_put_contents($sitio . '/api/.passhash', '$2y$10$hashdementirasolovaleparaqueconfigphpnocorte');
$ANTES = '{"properties":[{"id":"antes","visible":true}]}';
file_put_contents($sitio . '/api/corre_save.php', <<<'PHP'
<?php
// Arnes de coleccion_test.php: ejecuta api/save.php con una peticion simulada. argv: cuerpo.json, 1|0 (con sesion), metodo.
class EntradaFalsa {   // php://input en CLI esta vacio: se sustituye el envoltorio `php` por el cuerpo de la prueba
    public static $cuerpo = ''; public $context; private $pos = 0;
    public function stream_open() { $this->pos = 0; return true; }
    public function stream_read($n) { $r = substr(self::$cuerpo, $this->pos, $n); $this->pos += strlen($r); return $r; }
    public function stream_eof() { return $this->pos >= strlen(self::$cuerpo); }
    public function stream_stat() { return []; }
}
EntradaFalsa::$cuerpo = (string) file_get_contents($argv[1]);
ini_set('session.save_path', dirname(__DIR__) . '/sesiones');
if ($argv[2] === '1') {   // una sesion ya iniciada, como la deja api/auth.php tras el login
    session_id('lwpruebasave');
    session_start();
    $_SESSION['lawang_auth'] = true;
    session_write_close();
}
$_SERVER['REQUEST_METHOD'] = $argv[3];
$_SERVER['HTTP_HOST'] = 'lawang.test';
$_SERVER['HTTP_ORIGIN'] = 'https://lawang.test';
$_SERVER['SCRIPT_FILENAME'] = __DIR__ . '/save.php';
register_shutdown_function(function () { echo "\n#", (int) http_response_code(); });
stream_wrapper_unregister('php');
stream_wrapper_register('php', 'EntradaFalsa');
require __DIR__ . '/save.php';
PHP
);
$guarda = function ($cuerpo, $sesion = true, $metodo = 'POST') use ($sitio, $ANTES) {
    file_put_contents($sitio . '/data.json', $ANTES);
    file_put_contents($sitio . '/cuerpo.json', $cuerpo);
    $out = corre([$sitio . '/api/corre_save.php', $sitio . '/cuerpo.json', $sesion ? '1' : '0', $metodo], null, $sitio . '/api');
    $p = strrpos($out, "\n#");
    return ['resp' => json_decode(substr($out, 0, (int) $p), true), 'codigo' => (int) substr($out, (int) $p + 2), 'crudo' => $out,
            'escrito' => (string) file_get_contents($sitio . '/data.json'), 'tmp' => file_exists($sitio . '/data.json.tmp')];
};
$bueno = json_encode(['settings' => ['whatsapp' => '62811'], 'properties' => [$f('uno', ['visible' => true]), $f('dos', ['visible' => false])], 'downloads' => []]);
$r = $guarda($bueno);
ok(($r['resp']['ok'] ?? null) === true && $r['codigo'] !== 422, 'save.php: un catalogo valido se guarda (ok): ' . $r['crudo']);
ok(json_decode($r['escrito'], true) === json_decode($bueno, true) && !$r['tmp'], 'save.php: lo escrito es el catalogo enviado, sin dejar el .tmp');
$r = $guarda('{"properties":[]}');
ok(($r['resp']['ok'] ?? null) === true && json_decode($r['escrito'], true) === ['properties' => []], 'save.php: «sin propiedades» se sigue pudiendo publicar: ' . $r['crudo']);
foreach (['lista vacia `[]`', 'un numero', 'objeto sin properties', 'id repetido', 'visible "true" en texto', 'ficha sin id', 'id "uno\n"'] as $nombre) {
    ok(isset($invalidos[$nombre]), "save.php: el caso «$nombre» existe en la lista de invalidos");
    $r = $guarda($invalidos[$nombre][0]);
    ok($r['codigo'] === 422 && ($r['resp']['ok'] ?? null) === false && strpos((string) ($r['resp']['error'] ?? ''), 'Invalid catalogue: ') === 0,
       "save.php: «$nombre» responde 422 con su motivo: " . $r['crudo']);
    ok($r['escrito'] === $ANTES && !$r['tmp'], "save.php: «$nombre» NO toca data.json ni deja un .tmp");
    ok(strpos($r['crudo'], $SECRETO) === false, "save.php: el 422 de «$nombre» no vuelca contenido");
}
$r = $guarda('esto no es json');
ok($r['codigo'] === 400 && $r['escrito'] === $ANTES, 'save.php: lo que no es JSON sigue siendo 400 y no se escribe: ' . $r['crudo']);
$r = $guarda($bueno, false);
ok($r['codigo'] === 401 && $r['escrito'] === $ANTES, 'save.php: sin sesion sigue siendo 401 y no se escribe (la validacion no se adelanta a la sesion): ' . $r['crudo']);
$r = $guarda('[]', false);
ok($r['codigo'] === 401 && strpos($r['crudo'], 'Invalid catalogue') === false, 'save.php: sin sesion no se dice nada de la forma del catalogo: ' . $r['crudo']);
$r = $guarda($bueno, true, 'GET');
ok($r['codigo'] === 405 && $r['escrito'] === $ANTES, 'save.php: GET sigue siendo 405: ' . $r['crudo']);
foreach (['/api/config.php', '/api/save.php', '/api/.passhash', '/api/corre_save.php', '/coleccion/lib.php', '/data.json', '/cuerpo.json'] as $x) @unlink($sitio . $x);
foreach (glob($sitio . '/sesiones/*') ?: [] as $x) @unlink($x);
foreach (['/sesiones', '/api', '/coleccion', ''] as $d) @rmdir($sitio . $d);

// ── 2. Claves prohibidas: la fuente FALLA, a cualquier profundidad, sin importar mayusculas ─
$prohibidas = ['notas', 'contrato_id', 'iban', 'email', 'comprador', 'agente', 'precio_suelo', 'precio_construccion',
               'cuota_reserva', 'cuotaMensual', 'comision', 'comision_pct', 'Notas', 'IBAN'];
foreach ($prohibidas as $k) {
    foreach ([['top', ficha('p', [$k => 'x'])], ['anidada', ficha('p', ['extras' => [['name' => 'a', $k => 1]]])]] as $caso) {
        $lanzo = false;
        try { lw_coleccion_aplica_contrato(doc([$caso[1]]), cfg($tmp)['contrato']); }
        catch (RuntimeException $e) { $lanzo = strpos($e->getMessage(), 'prohibida') !== false; }
        ok($lanzo, "la clave prohibida '$k' ($caso[0]) debe hacer fallar el contrato");
    }
}
$lanzo = false;
try { $d = doc([ficha('p')]); $d['downloads'] = ['x' => [['iban' => 'ES00']]]; lw_coleccion_aplica_contrato($d, cfg($tmp)['contrato']); }
catch (RuntimeException $e) { $lanzo = true; }
ok($lanzo, 'una clave prohibida dentro de downloads tambien hace fallar');
// una prohibida en una ficha OCULTA no se publica: no hace falta que falle (nunca sale)
$lanzo = false;
try { $r = lw_coleccion_aplica_contrato(doc([ficha('p'), ficha('h', ['visible' => false, 'notas' => 'x'])]), cfg($tmp)['contrato']); }
catch (RuntimeException $e) { $lanzo = true; }
ok(!$lanzo && ids($r) === ['p'], 'una ficha oculta con notas no sale ni rompe las visibles');

// ── 3. Niveles: fuente -> cache vieja -> respaldo -> vacio; siempre con stale honesto ───────
$c = cfg($tmp);
@unlink($c['cache']); @unlink($c['respaldo']);
escribe($c['datajson'], doc([ficha('uno'), ficha('dos'), ficha('oculta', ['visible' => false])]));
escribe($c['respaldo'], ['_aviso' => 'x'] + doc([ficha('resp-a'), ficha('resp-b')]));
$d = lw_coleccion_carga($c);
ok(ids($d) === ['uno', 'dos'] && $d['stale'] === false && $d['fuente'] === 'datajson', 'fuente viva: fichas visibles, stale=false');
ok(is_file($c['cache']), 'la fuente viva deja una cache escrita');
// data.json en vivo: un cambio (admin.html lo guarda) se ve a la siguiente lectura — TTL 0 con datajson
escribe($c['datajson'], doc([ficha('uno'), ficha('dos'), ficha('nuevo')]));
ok(ids(lw_coleccion_carga($c)) === ['uno', 'dos', 'nuevo'], 'datajson no se cachea: el cambio se ve de inmediato');
// fuente caida (fichero ausente) -> cache vieja
escribe($c['cache'], doc([ficha('uno'), ficha('dos'), ficha('nuevo')]));
@unlink($c['datajson']);
$d = lw_coleccion_carga($c);
ok(ids($d) === ['uno', 'dos', 'nuevo'] && $d['stale'] === true && $d['fuente'] === 'cache', 'fuente caida: sirve la cache vieja con stale=true');
// fuente corrupta (cortada por el CDN) -> tambien cache
escribe($c['datajson'], '{"properties":[{"id":"uno","visi');
$d = lw_coleccion_carga($c);
ok($d['stale'] === true && $d['fuente'] === 'cache', 'data.json truncado = fuente caida, no pagina rota');
// sin cache -> respaldo
@unlink($c['cache']);
$d = lw_coleccion_carga($c);
ok(ids($d) === ['resp-a', 'resp-b'] && $d['stale'] === true && $d['fuente'] === 'respaldo', 'sin fuente ni cache: respaldo versionado con stale=true');
ok(!isset($d['_aviso']) && !array_key_exists('_aviso', $d), 'el _aviso del respaldo no sale');
// nada -> vacio, sin fatal
@unlink($c['respaldo']);
log_limpia();
$d = lw_coleccion_carga($c);
ok($d['properties'] === [] && $d['stale'] === true && $d['fuente'] === 'ninguna', 'sin nada: vacio y stale, nunca fatal');
ok(strpos(log_txt(), 'ni fuente, ni cache, ni respaldo') !== false, 'quedarse sin nada se dice en el log');
// un documento valido pero SIN fichas visibles se trata como fallo (despiste), no como "web vacia"
escribe($c['datajson'], doc([ficha('x', ['visible' => false])]));
escribe($c['respaldo'], doc([ficha('resp-a')]));
ok(ids(lw_coleccion_carga($c)) === ['resp-a'], 'fuente con 0 visibles cae al respaldo');

// ── 4. Fuente envenenada: no se publica, se dice, y se sirve lo ultimo bueno ────────────────
$c = cfg($tmp);
escribe($c['respaldo'], doc([ficha('resp-a')]));
escribe($c['cache'], doc([ficha('cache-bueno')]));
escribe($c['datajson'], doc([ficha('uno'), ficha('dos', ['notas' => 'LEAK-DATO-INTERNO'])]));
log_limpia();
$d = lw_coleccion_carga($c);
ok(ids($d) === ['cache-bueno'] && $d['stale'] === true, 'fuente con clave prohibida: cae a la cache buena');
ok(strpos(json_encode($d), 'LEAK-DATO-INTERNO') === false, 'el dato prohibido NO esta en la salida');
ok(strpos(log_txt(), 'RECHAZADO') !== false && strpos(log_txt(), "'notas'") !== false, 'el rechazo se dice en el log con la clave');
// cache tambien envenenada -> respaldo
escribe($c['cache'], doc([ficha('c', ['contrato_id' => 'LEAK2'])]));
$d = lw_coleccion_carga($c);
ok(ids($d) === ['resp-a'] && strpos(json_encode($d), 'LEAK') === false, 'cache envenenada: se ignora y se sirve el respaldo');
// respaldo envenenado tambien se rechaza -> vacio
escribe($c['respaldo'], doc([ficha('r', ['iban' => 'LEAK3'])]));
$d = lw_coleccion_carga($c);
ok($d['properties'] === [] && strpos(json_encode($d), 'LEAK') === false, 'respaldo envenenado: vacio, nunca la fuga');

// ── 5. Fuente 'intranet' (RPC coleccion_publica) contra un servidor simulado ──────────────────
// Un `php -S` real sirve una respuesta que se controla desde un fichero (modo): así se prueba cURL de verdad,
// no un doble. Modos: ok | http500 | basura.
$sock = stream_socket_server('tcp://127.0.0.1:0', $en, $es); $port = (int) substr(strrchr(stream_socket_get_name($sock, false), ':'), 1); fclose($sock);
$modoF = $tmp . '/modo.txt'; $fixF = $tmp . '/rpc_fixture.json';
file_put_contents($tmp . '/router.php', '<?php $m=trim((string)@file_get_contents(' . var_export($modoF, true) . '));'
  . 'if($m==="una_vez"){$cf=' . var_export($tmp . '/una_vez.cnt', true) . ';$n=(int)@file_get_contents($cf);file_put_contents($cf,$n+1);if($n<1){http_response_code(500);echo "{}";return;}}'
  . 'if($m==="http500"){http_response_code(500);echo "{}";return;}if($m==="basura"){echo "<html>no json";return;}'
  . 'header("Content-Type: application/json");echo file_get_contents(' . var_export($fixF, true) . ');');
$srv = proc_open([PHP_BINARY, '-S', "127.0.0.1:$port", $tmp . '/router.php'], [1 => ['file', $tmp . '/srv.out', 'w'], 2 => ['file', $tmp . '/srv.err', 'w']], $sp);
for ($i = 0; $i < 50; $i++) { $f = @fsockopen('127.0.0.1', $port, $e1, $e2, 0.2); if ($f) { fclose($f); break; } usleep(100000); }
function rpc_modo($m, $props = null) {
    global $modoF, $fixF;
    file_put_contents($modoF, $m);
    $p = $props ?? [ficha('rpc-a', ['priceMode' => 'from', 'priceEUR' => 63875, 'unitsAvailable' => 23, 'unitsTotal' => 36,
                       'parcelas' => [['codigo' => 'A1', 'superficie_m2' => 200, 'estado' => 'disponible']],
                       'images' => ['proyecto/80af3c78-e1f7-4d96-a831-f6843fbe5975.webp', '/assets/img/x.jpg', 'https://otro.test/a.jpg'],
                       'masterplanImage' => 'proyecto/mp-1.webp',
                       'homeModels' => [['name' => 'Dune', 'priceEUR' => 100, 'image' => 'modelo/a6054863-017f-4b8e-bc7d-000000000000.webp']]]),
                ficha('rpc-b')];
    file_put_contents($fixF, json_encode(['properties' => $p, 'generated_at' => '2026-10-02T00:00:00Z'], JSON_UNESCAPED_SLASHES));
}
$ci = function ($o = []) use ($tmp, $port) {
    $c = cfg($tmp, array_merge(['fuente' => 'intranet', 'ttl' => LW_COLECCION_TTL_INTRANET,
        'rpc' => "http://127.0.0.1:$port/rest/v1/rpc/coleccion_publica", 'bucket' => 'https://sb.test/storage/v1/object/public/deck'], $o));
    @unlink($c['cache']); @unlink($c['cache'] . '.fallo');
    return $c;
};
ok(LW_COLECCION_TTL_INTRANET === 60, 'TTL del estado casi en tiempo real: 60 s');
$c = $ci();
escribe($c['datajson'], ['settings' => ['rates' => ['EUR' => 1, 'USD' => 1.1], 'whatsapp' => '62811', 'clave_interna' => 'x'],
                         'downloads' => ['signature' => [['name' => 'Brochure', 'url' => '']]], 'properties' => [ficha('de-datajson')]]);
escribe($c['respaldo'], doc([ficha('resp-a')]));
rpc_modo('ok'); log_limpia();
$d = lw_coleccion_carga($c);
ok(ids($d) === ['rpc-a', 'rpc-b'] && $d['fuente'] === 'intranet' && $d['stale'] === false, "RPC viva: fichas de la RPC (no de data.json), stale=false: " . json_encode(ids($d)));
$a = $d['properties'][0];
ok($a['priceMode'] === 'from' && $a['priceEUR'] === 63875 && $a['unitsAvailable'] === 23 && $a['unitsTotal'] === 36 && $a['parcelas'][0]['estado'] === 'disponible', 'las claves nuevas del contrato (priceMode, unidades, parcelas) pasan');
ok($a['images'][0] === 'https://sb.test/storage/v1/object/public/deck/proyecto/80af3c78-e1f7-4d96-a831-f6843fbe5975.webp', 'ruta del bucket -> URL publica');
ok($a['images'][1] === '/assets/img/x.jpg' && $a['images'][2] === 'https://otro.test/a.jpg', 'una URL del servidor o absoluta no se toca');
ok($a['masterplanImage'] === 'https://sb.test/storage/v1/object/public/deck/proyecto/mp-1.webp' && lw_coleccion_url_bucket('proyecto/../../etc.webp', 'B') === 'proyecto/../../etc.webp' && lw_coleccion_url_bucket('a b.webp', 'B') === 'a b.webp', 'masterplanImage compuesta; rutas con .. o espacios no se componen');
ok(strpos($a['homeModels'][0]['image'], 'https://sb.test/') === 0, 'homeModels[].image compuesta');
ok(($d['settings']['whatsapp'] ?? '') === '62811' && !isset($d['settings']['clave_interna']) && isset($d['downloads']['signature']), 'settings/downloads vienen de data.json (transitorio) y pasan por la lista blanca');
ok(is_file($c['cache']), 'la RPC viva deja caché');
// TTL: dentro de 60 s no se vuelve a llamar (la fuente cambia y la salida NO)
rpc_modo('ok', [ficha('cambiado')]);
$d = lw_coleccion_carga($c);
ok(ids($d) === ['rpc-a', 'rpc-b'] && $d['fuente'] === 'cache' && $d['stale'] === false, 'dentro del TTL sirve la caché fresca sin llamar a la RPC');
touch($c['cache'], time() - 120);
ok(ids(lw_coleccion_carga($c)) === ['cambiado'], 'pasado el TTL vuelve a llamar a la RPC');
// RPC caída -> caché vieja (stale) -> respaldo
foreach (['http500', 'basura'] as $m) {
    rpc_modo($m); touch($c['cache'], time() - 120); @unlink($c['cache'] . '.fallo'); log_limpia();
    $d = lw_coleccion_carga($c);
    ok(ids($d) === ['cambiado'] && $d['stale'] === true && $d['fuente'] === 'cache', "RPC $m: cache vieja con stale=true");
    ok(strpos(log_txt(), 'coleccion_publica no responde') !== false, "RPC $m: se dice en el log");
}
$c2 = $ci(['rpc' => 'http://127.0.0.1:1/rpc']); // puerto cerrado: conexion rechazada
escribe($c2['respaldo'], doc([ficha('resp-a')]));
$d = lw_coleccion_carga($c2);
ok(ids($d) === ['resp-a'] && $d['stale'] === true && $d['fuente'] === 'respaldo', 'RPC caida y sin cache: respaldo con stale=true');
ok(is_file($c2['cache'] . '.fallo'), 'el fallo se recuerda (marcador)');
rpc_modo('ok');
$c2b = $c2; $c2b['rpc'] = "http://127.0.0.1:$port/rest/v1/rpc/coleccion_publica";
$d = lw_coleccion_carga($c2b);
ok($d['fuente'] === 'respaldo' && $d['stale'] === true, 'con un fallo reciente no se reintenta la RPC (aunque ya responda): sirve respaldo');
unlink($c2b['cache'] . '.fallo');
ok(ids(lw_coleccion_carga($c2b)) === ['rpc-a', 'rpc-b'], 'caducado el marcador, la RPC se vuelve a intentar y recupera');
// Cache FRIA + un fallo aislado de la RPC: se reintenta una vez y NO cae a stale (F7, 6-oct-2026: la primera
// carga tras desplegar salia con las 9 tarjetas en «Ask for availability» aunque la RPC estaba sana).
$c6 = $ci(); escribe($c6['respaldo'], doc([ficha('resp-a')]));
@unlink($tmp . '/una_vez.cnt'); rpc_modo('una_vez'); log_limpia();
$d = lw_coleccion_carga($c6);
ok($d['stale'] === false && $d['fuente'] === 'intranet' && ids($d) === ['rpc-a', 'rpc-b'], 'cache fria + 1 fallo aislado: reintenta y sirve la RPC, stale=false');
ok(!is_file($c6['cache'] . '.fallo') && strpos(log_txt(), 'un reintento') !== false, 'el reintento se dice en el log y no deja marcador de fallo');
// Con cache vieja NO se reintenta (ya hay con que servir): exactamente 1 peticion
$c7 = $ci(); escribe($c7['cache'], doc([ficha('vieja')])); touch($c7['cache'], time() - 120);
@unlink($tmp . '/una_vez.cnt'); rpc_modo('una_vez');
$d = lw_coleccion_carga($c7);
ok($d['stale'] === true && ids($d) === ['vieja'] && (int) file_get_contents($tmp . '/una_vez.cnt') === 1, 'con cache vieja no se reintenta: 1 sola peticion y stale=true');
// Cache fria y RPC caida de verdad: 2 intentos UNA vez, y el marcador cierra la puerta al resto
$c8 = $ci(['rpc' => 'http://127.0.0.1:1/rpc']); escribe($c8['respaldo'], doc([ficha('resp-a')]));
$d = lw_coleccion_carga($c8);
ok($d['stale'] === true && $d['fuente'] === 'respaldo' && is_file($c8['cache'] . '.fallo'), 'cache fria y RPC caida: respaldo stale y marcador de fallo');
// 0 fichas = fallo (documentado), no web vacia
$c3 = $ci(); escribe($c3['respaldo'], doc([ficha('resp-a')])); rpc_modo('ok', []); log_limpia();
$d = lw_coleccion_carga($c3);
ok(ids($d) === ['resp-a'] && $d['stale'] === true, "RPC con 0 fichas: se trata como fallo y cae al respaldo, no publica una web vacia");
ok(strpos(log_txt(), '0 fichas') !== false, 'las 0 fichas se dicen en el log');
rpc_modo('ok', [ficha('x', ['visible' => false])]); @unlink($c3['cache'] . '.fallo');
ok(ids(lw_coleccion_carga($c3)) === ['resp-a'], 'RPC solo con fichas no visibles: igual que 0');
// Clave prohibida en la RPC: rechazo, log, no sale
$c4 = $ci(); escribe($c4['respaldo'], doc([ficha('resp-a')])); log_limpia();
rpc_modo('ok', [ficha('ok1'), ficha('malo', ['extras' => [['name' => 'a', 'comision_pct' => 3]]])]);
$d = lw_coleccion_carga($c4);
ok(ids($d) === ['resp-a'] && $d['stale'] === true && strpos(json_encode($d), 'comision') === false, 'clave prohibida en la RPC: la RPC entera se rechaza, nada sale');
ok(strpos(log_txt(), 'RPC RECHAZADA') !== false && strpos(log_txt(), 'comision_pct') !== false, 'el rechazo dice la clave');
rpc_modo('ok', [ficha('ok1', ['notas' => 'LEAK-RPC'])]); @unlink($c4['cache'] . '.fallo');
ok(strpos(json_encode(lw_coleccion_carga($c4)), 'LEAK-RPC') === false, 'notas en la RPC no llega a la salida');
rpc_modo('ok', [ficha('ok1', ['columna_nueva' => 'x'])]); @unlink($c4['cache'] . '.fallo'); @unlink($c4['cache']);
$d = lw_coleccion_carga($c4);
ok(ids($d) === ['ok1'] && !isset($d['properties'][0]['columna_nueva']), 'clave fuera de la lista blanca: descartada');
// La RPC real (lo que devolvio el 2-oct-2026) cumple el contrato: ninguna clave se recorta
$fx = $RAIZ . '/coleccion/tests/rpc_real_20261002.json';
if (is_file($fx)) {
    $real = json_decode((string) file_get_contents($fx), true);
    $con = lw_coleccion_contrato($RAIZ . '/coleccion/contrato_publico.json');
    $fuera = [];
    foreach ($real['properties'] as $p) foreach (array_diff(array_keys($p), $con['ficha']) as $k) $fuera[$k] = 1;
    ok($fuera === [] && count($real['properties']) === 11, 'la RPC real: 11 fichas y todas sus claves en la lista blanca: ' . json_encode(array_keys($fuera)));
    rpc_modo('ok', $real['properties']); $c5 = $ci();
    $d = lw_coleccion_carga($c5); $pf = null;
    foreach ($d['properties'] as $p) if ($p['id'] === 'palm-field-bali') $pf = $p;
    ok(count($d['properties']) === 11 && $pf && $pf['priceMode'] === 'from' && $pf['priceEUR'] === 63875, 'fixture de la RPC real: 11 fichas, palm-field-bali from 63875');
}
proc_terminate($srv);
ok(lw_coleccion_cfg('intranet')['fuente'] === 'intranet' && lw_coleccion_cfg()['fuente'] === 'datajson', 'por defecto datajson; intranet solo si el servidor la pide');
ok(lw_coleccion_cfg('intranet')['cache'] !== lw_coleccion_cfg('datajson')['cache'], 'cada fuente tiene su cache (no se mezclan)');
putenv('LW_COLECCION_FUENTE=otra-cosa'); log_limpia();
ok(lw_coleccion_cfg()['fuente'] === 'datajson' && strpos(log_txt(), 'desconocida') !== false, 'fuente desconocida -> datajson y log');
putenv('LW_COLECCION_FUENTE');

// ── 6. El MISMO conjunto de ids en los tres sitios, de verdad (procesos reales) ──────────────
$c = cfg($tmp);
@unlink($c['cache']);
$vis = ['alfa', 'beta', 'gamma'];
escribe($c['datajson'], doc(array_merge(array_map('ficha', $vis), [ficha('oculta', ['visible' => false]), ficha('0culta2', ['visible' => 0])])));
$env = array_merge($_ENV, getenv(), [
    'LW_COLECCION_DATAJSON' => $c['datajson'], 'LW_COLECCION_CACHE' => $c['cache'],
    'LW_COLECCION_RESPALDO' => $c['respaldo'], 'LW_COLECCION_FUENTE' => 'datajson',
]);
function corre($args, $env, $cwd) {
    $p = proc_open(array_merge([PHP_BINARY], $args), [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, $cwd, $env);
    $out = stream_get_contents($pipes[1]); stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]); proc_close($p);
    return $out;
}
$sitemap = corre([$RAIZ . '/sitemap.php'], $env, $RAIZ);
preg_match_all('~<loc>https://lawangproperties\.com/property/([^<]+)</loc>~', $sitemap, $m);
$enSitemap = $m[1];
$runner = '$_GET["property"]=$argv[1]; require ' . var_export($RAIZ . '/thecollection.php', true) . ';';
$aceptados = [];
foreach (array_merge($vis, ['oculta', '0culta2', 'no-existe', 'mal_id']) as $id) {
    $html = corre(['-r', $runner, $id], $env, $RAIZ);
    if (strpos($html, "This property page doesn't exist.") === false && strpos($html, '/property/' . $id . '"') !== false) $aceptados[] = $id;
    elseif (strpos($html, "This property page doesn't exist.") === false) ok(false, "thecollection.php no dio ni ficha ni 404 para $id");
}
$enLib = lw_coleccion_ids_de($c);
function lw_coleccion_ids_de($c) { return ids(lw_coleccion_carga($c)); }
sort($enSitemap); sort($aceptados); $esperado = $vis; sort($esperado); sort($enLib);
ok($enLib === $esperado, 'ids de lw_coleccion(): ' . json_encode($enLib));
ok($enSitemap === $esperado, 'ids del sitemap.xml: ' . json_encode($enSitemap));
ok($aceptados === $esperado, 'ids que thecollection.php acepta (200): ' . json_encode($aceptados));

// ── 7. Contra lo real: la lista blanca cubre lo que las fichas visibles traen hoy ────────────
// (a) el respaldo versionado cumple el contrato y no pierde nada al filtrarlo otra vez
$resp = json_decode((string) file_get_contents($RAIZ . '/coleccion/respaldo.json'), true);
ok(is_array($resp) && !empty($resp['properties']), 'coleccion/respaldo.json existe y trae fichas');
if (is_array($resp)) {
    $f = lw_coleccion_aplica_contrato($resp);
    ok($f['properties'] === $resp['properties'], 'el respaldo es ya un punto fijo del contrato (no trae nada fuera de lista)');
    ok(count($f['properties']) === count(array_filter($resp['properties'], function ($p) { return $p['visible'] === true; })), 'el respaldo solo trae visibles');
}
// (b) si hay un data.json local (produccion o copia), TODAS las claves de sus visibles estan en la lista blanca
$real = $RAIZ . '/data.json';
$sinCatalogo = false;
if (is_file($real)) {
    $dj = json_decode((string) file_get_contents($real), true);
    $con = lw_coleccion_contrato($RAIZ . '/coleccion/contrato_publico.json');
    $fuera = [];
    foreach ($dj['properties'] ?? [] as $p) {
        if (($p['visible'] ?? null) !== true) continue;
        foreach (array_diff(array_keys($p), $con['ficha']) as $k) $fuera[$k] = ($fuera[$k] ?? 0) + 1;
    }
    ok($fuera === [], 'claves de fichas visibles de data.json que la lista blanca recortaria (cambiaria un render): ' . json_encode($fuera));
    $esperadoReal = array_values(array_map(function ($p) { return $p['id']; }, array_filter($dj['properties'], function ($p) { return ($p['visible'] ?? null) === true; })));
    $real_ids = ids(lw_coleccion_carga(cfg($tmp, ['datajson' => $real, 'cache' => $tmp . '/real_cache.json'])));
    ok($real_ids === $esperadoReal, 'con el data.json real, lw_coleccion() devuelve exactamente sus visibles');
} else {
    // 14-oct-2026. Este apartado es el unico que mira datos reales, y sin catalogo no corre. Hasta hoy lo decia
    // entre parentesis y la prueba acababa en el mismo «OK» de siempre: en el control (tools/test.py solo ensena la
    // salida de lo que falla) se leia igual que haberlo comprobado. Las copias de sesion NO tienen data.json
    // (esta en .gitignore), asi que ahi esto es lo normal y no puede ser un rojo: se dice con nombre aqui y en la
    // ultima linea, y el codigo de salida solo lo distingue (3) si se pide con --exige-catalogo.
    $sinCatalogo = true;
    echo "AVISO sin catalogo: apartado de datos reales NO ejecutado (7b: no hay data.json en la raiz del proyecto).\n";
}

// ── 8. F7: estado de unidades, v2 sin credenciales de base, noscript y JSON-LD desde lw_coleccion ──────────
// (a) la regla de estado: la MISMA tabla que assets/lawang-card.test.js (una regla, dos implementaciones)
$tabla = json_decode((string) file_get_contents(__DIR__ . '/estados_esperados.json'), true);
$rpc6 = json_decode((string) file_get_contents(__DIR__ . '/rpc_real_20261006.json'), true)['properties'];
foreach ($rpc6 as $p) {
    ok(lw_coleccion_estado($p)['k'] === ($tabla['rpc_6oct'][$p['id']] ?? '?'), 'estado PHP de ' . $p['id']);
}
foreach ($tabla['sinteticos'] as $c) {
    $f = ['parcelas' => $c['parcelas']] + (isset($c['unitsAvailable']) ? ['unitsAvailable' => $c['unitsAvailable']] : []);
    ok(lw_coleccion_estado($f, !empty($c['stale']))['k'] === $c['esperado'], 'estado PHP sintetico: ' . $c['nota']);
}
// (b) lo que sale al navegador: solo estas claves, y `live`/`stale` siempre
$nav = lw_coleccion_para_navegador(['properties' => [], 'settings' => [], 'downloads' => [], 'fuente' => 'cache', 'stale' => true, 'live' => true, 'otra' => 1]);
ok(array_keys($nav) === ['properties', 'settings', 'downloads', 'live', 'stale'] && $nav['live'] === true && $nav['stale'] === true, 'lw_coleccion_para_navegador: claves exactas, sin `fuente`');
// (c) noscript desde el mismo documento: fijo sin «From», «desde» con From, vendida «Sold out», stale no afirma vendida
$docFresco = ['properties' => $rpc6, 'stale' => false, 'live' => true];
$ns = lw_coleccion_noscript($docFresco);
ok(substr_count($ns, 'class="seo-prop"') === count($rpc6), 'noscript: una ficha por ficha del documento');
ok(strpos($ns, '<p class="seo-price">€930,000</p>') !== false && strpos($ns, 'From €930,000') === false, 'noscript: precio fijo sin From');
ok(strpos($ns, 'From €63,875') !== false, 'noscript: precio «desde» con From');
ok(strpos($ns, 'riverfront-ii-big') === false, 'noscript: no lista la ficha no publicada');
$vend = $rpc6[0]; $vend['parcelas'] = [['codigo' => 'U0', 'estado' => 'vendida']];
ok(strpos(lw_coleccion_noscript(['properties' => [$vend], 'stale' => false, 'live' => true]), 'Sold out') !== false, 'noscript: vendida -> Sold out');
ok(strpos(lw_coleccion_noscript(['properties' => [$vend], 'stale' => true, 'live' => true]), 'Sold out') === false, 'noscript: con dato viejo no se afirma vendida');
// (d) las paginas, ejecutadas de verdad, con la RPC inaccesible (cae a respaldo = stale)
escribe($tmp . '/s_data.json', doc([ficha('tirta-hikari'), ficha('otra')]));
escribe($tmp . '/s_resp.json', doc([ficha('tirta-hikari'), ficha('otra')]));
$envS = array_merge($env, ['LW_COLECCION_DATAJSON' => $tmp . '/s_data.json', 'LW_COLECCION_RESPALDO' => $tmp . '/s_resp.json', 'LW_COLECCION_CACHE' => $tmp . '/s_cache.json']);
$envI = array_merge($envS, ['LW_COLECCION_FUENTE' => 'intranet', 'LW_COLECCION_RPC_URL' => 'http://127.0.0.1:1/rpc', 'LW_COLECCION_CACHE' => $tmp . '/intranet_cache.json']);
$v2 = corre(['-r', 'require ' . var_export($RAIZ . '/thecollection-v2.php', true) . ';'], $envI, $RAIZ);
ok(preg_match('~(sb_publishable|sb_secret|/rest/v1|supabaseKey|supabaseUrl|apikey)~i', $v2) === 0, 'la v2 no lleva ninguna credencial ni llamada a la base en la pagina');
ok(strpos($v2, 'window.LW_COLECCION_PRELOAD=') !== false && strpos($v2, '"live":true') !== false && strpos($v2, '"stale":true') !== false, 'v2: precarga con live=true y stale=true cuando la RPC cae');
ok(strpos($v2, 'noindex') !== false && strpos($v2, 'rel="canonical" href="https://lawangproperties.com/thecollection"') !== false, 'v2: noindex y canonical a /thecollection');
ok(strpos($v2, 'SEO_FALLBACK_START') === false && substr_count($v2, '<noscript>') >= 1 && substr_count($v2, 'class="seo-prop"') === 2, 'v2: noscript generado de lw_coleccion (una ficha por ficha del documento)');
$v1 = corre(['-r', 'require ' . var_export($RAIZ . '/thecollection.php', true) . ';'], $envS, $RAIZ);
ok(strpos($v1, 'LW_COLECCION_PRELOAD') === false && strpos($v1, 'supabaseUrl') !== false, 'v1 (datajson): sin precarga y con su configuracion de siempre');
$ld = corre(['-r', '$_GET["property"]="tirta-hikari"; require ' . var_export($RAIZ . '/thecollection.php', true) . ';'], $envI, $RAIZ);
ok(strpos($ld, 'RealEstateListing') !== false && strpos($ld, 'schema.org/InStock') === false, 'JSON-LD con dato viejo: no afirma InStock');
$ld1 = corre(['-r', '$_GET["property"]="tirta-hikari"; require ' . var_export($RAIZ . '/thecollection.php', true) . ';'], $envS, $RAIZ);
ok(strpos($ld1, 'schema.org/InStock') !== false, 'JSON-LD con datajson: InStock como siempre');
$api = json_decode(corre([$RAIZ . '/api/coleccion.php'], $envI, $RAIZ), true);
ok(is_array($api) && array_keys($api) === ['properties', 'settings', 'downloads', 'live', 'stale'], 'api/coleccion.php devuelve el documento del navegador');

// (e) JSON-LD del LISTADO (F7, 6-oct-2026: la v2 salia sin ningun bloque ld+json): misma regla que lw_coleccion_estado
$site = 'https://lawangproperties.com';
$jl = lw_coleccion_jsonld_listado($docFresco, $site);
ok($jl['@type'] === 'CollectionPage' && $jl['url'] === $site . '/thecollection', 'JSON-LD listado: CollectionPage de /thecollection');
$els = $jl['mainEntity']['itemListElement'];
ok(count($els) === count($rpc6) && $jl['mainEntity']['numberOfItems'] === count($rpc6), 'JSON-LD listado: un item por ficha');
$por = []; foreach ($els as $e) { $por[basename($e['item']['url'])] = $e['item']; }
ok($por['pura-dalem']['offers']['availability'] === 'https://schema.org/LimitedAvailability', 'JSON-LD: queda 1 libre -> LimitedAvailability');
ok($por['riverfront-i']['offers']['availability'] === 'https://schema.org/InStock', 'JSON-LD: hay libres -> InStock');
ok(!isset($por['riverfront-iii']['offers']['availability']) && $por['riverfront-iii']['offers']['price'] === '250000', 'JSON-LD: sin parcelas (na) -> sin availability, con precio');
$jv = lw_coleccion_jsonld_listado(['properties' => [$vend], 'stale' => false, 'live' => true], $site);
ok($jv['mainEntity']['itemListElement'][0]['item']['offers']['availability'] === 'https://schema.org/SoldOut', 'JSON-LD: vendida -> SoldOut');
$js = lw_coleccion_jsonld_listado(['properties' => $rpc6, 'stale' => true, 'live' => true], $site);
$hay = false; foreach ($js['mainEntity']['itemListElement'] as $e) { if (isset($e['item']['offers']['availability'])) $hay = true; }
ok(!$hay, 'JSON-LD con dato viejo: ninguna availability afirmada');
ok(!isset(lw_coleccion_jsonld_listado(['properties' => $rpc6, 'stale' => false, 'live' => false], $site)['mainEntity']), 'JSON-LD con datajson: CollectionPage de siempre, sin ItemList');
$h2 = corre(['-r', 'require ' . var_export($RAIZ . '/thecollection-v2.php', true) . ';'], $envI, $RAIZ);
ok(substr_count($h2, 'application/ld+json') === 1 && strpos($h2, '"@type":"CollectionPage"') !== false && strpos($h2, 'schema.org/InStock') === false, 'v2 servida: 1 bloque ld+json (CollectionPage) y con la RPC caida no afirma InStock');
$h1 = corre(['-r', 'require ' . var_export($RAIZ . '/thecollection.php', true) . ';'], $envS, $RAIZ);
ok(substr_count($h1, 'application/ld+json') === 1 && strpos($h1, '"@type":"CollectionPage"') !== false && strpos($h1, 'ItemList') === false, 'v1 servida (datajson): 1 bloque ld+json, CollectionPage sin ItemList');

// limpieza
foreach (array_merge(glob($tmp . '/*') ?: [], glob($tmp . '/.*') ?: []) as $f) if (is_file($f)) @unlink($f);
@rmdir($tmp);

if ($fallos) { echo "\n$fallos FALLO(S)\n"; exit(1); }
if ($sinCatalogo) {
    echo "OK PARCIAL: lo demas en verde; sin catalogo: apartado de datos reales NO ejecutado "
       . "(no se ha comprobado que la lista blanca cubra las fichas publicadas hoy, ni que lw_coleccion() devuelva sus visibles).\n";
    exit(in_array('--exige-catalogo', $argv, true) ? 3 : 0);
}
echo "OK: lectura unica de The Collection (contrato, niveles, fuente envenenada, ids en los tres sitios).\n";
