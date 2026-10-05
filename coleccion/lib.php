<?php
/**
 * coleccion/lib.php — la UNICA lectura de The Collection en servidor. 2-oct-2026 (F5a).
 *
 * Quien necesite saber qué fichas publica la web (el <head> de /property/<id>, el sitemap,
 * y a partir de F7 el endpoint JSON de la SPA y el noscript) llama a lw_coleccion(). Nadie lee
 * data.json directamente: eran cuatro lectores con cuatro copias de la regla «visible», y esa
 * es la familia de fallo más cara del estudio (un hecho en varios sitios que se separan).
 *
 * EL DATO TIENE UN DUEÑO. Hoy el dueño de la ficha pública es data.json (lo escribe
 * admin.html → api/save.php). El destino (F2-F5b) es la intranet: tabla `fichas_publicas` →
 * RPC `coleccion_publica()`. Esta capa deja el cambio de dueño como UNA línea de servidor
 * (LW_COLECCION_FUENTE), reversible, sin tocar a quien consume. La copia que se hace aquí es
 * de LECTURA y envejece: de ahí la marca `stale` (la SPA debe pintar «sin dato», no
 * «disponible», cuando es true — hallazgo de Legal ya cerrado el 6-ago).
 *
 * LOS NIVELES (patrón de modelo/catalogo.php), en este orden y ninguno opcional:
 *   1. memo estático de la petición
 *   2. caché fresca en private/ (fallback al temporal del sistema si no se puede escribir)
 *   3. la fuente
 *   4. caché vieja, con stale=true
 *   5. respaldo versionado coleccion/respaldo.json, con stale=true
 *   6. vacío (con stale=true): una web sin fichas, nunca un fatal
 *
 * FUENTE 'datajson' (hoy): TTL 0 — se lee el fichero en cada petición. Es local y barato, y un
 * TTL aquí haría que un cambio hecho en admin.html tardase en verse en el <head> y el sitemap
 * respecto a la SPA, que sí lee data.json en vivo: cambiaría lo que ve el público. La caché se
 * escribe igualmente (como red de seguridad por si el fichero desaparece o llega corrupto).
 * FUENTE 'intranet' (F5b, 2-oct-2026): POST {} a la RPC `coleccion_publica()` de Supabase Lawang con la
 * clave PUBLICABLE (la misma de modelo/catalogo.php; el navegador nunca llama a la RPC). Una sola
 * llamada devuelve contenido y estado de unidades, y la caché fresca dura 60 s para todo; la regla es
 * «estado casi en tiempo real» y partir en dos TTL (60/300) exigiría dos llamadas o dos RPC para ahorrar
 * una petición por minuto. Si la RPC falla: caché vieja (stale) -> respaldo (stale). Un fallo reciente se
 * recuerda 30 s (marcador `.fallo` junto a la caché) para que, con Supabase caído, ningún visitante pague
 * el timeout de 4 s. «0 fichas» de la RPC se trata como FALLO (igual que catalogo.php): es mucho más probable
 * un despiste o una RPC rota que la intención de vaciar la web, y caer a caché vieja marca stale (la SPA pinta
 * «sin dato», nunca «disponible»). Vaciar a propósito = devolver LW_COLECCION_FUENTE a datajson.
 * settings (whatsapp/email/rates) y downloads globales SIGUEN viniendo de data.json: TRANSITORIO hasta que
 * tengan dueño en la intranet (la RPC no los emite; decisión de F5b). Si data.json no se lee, salen vacíos y
 * la SPA conserva sus valores por defecto.
 * Las rutas de imagen del bucket público `deck` (`proyecto/<uuid>.webp`, `modelo/<uuid>.webp`) se vuelven URL
 * aquí (la base es infraestructura); una ruta con «/» inicial o http(s) ya es URL y no se toca.
 * La fuente se elige EN SERVIDOR (LW_COLECCION_FUENTE o el argumento de lw_coleccion(), que solo pasa
 * código del servidor, nunca la petición); cada fuente tiene SU caché: no se mezclan.
 *
 * LA LISTA BLANCA (coleccion/contrato_publico.json) se aplica A LA SALIDA DE CADA NIVEL, también
 * al leer la caché y el respaldo: lo que está en disco pudo escribirse con un contrato más
 * antiguo. Una clave fuera de lista se descarta; una clave PROHIBIDA (notas, contrato_id, cuota*,
 * iban, email, comprador, agente, comision*, precio_suelo, precio_construccion) hace fallar ESA
 * fuente con error_log ruidoso y se sigue con el siguiente nivel: no se publica la fuga y
 * tampoco se tira la web pública. `visible === true` se filtra SOLO aquí.
 *
 * El respaldo NO es una segunda fuente y no se edita a mano:
 *   php coleccion/lib.php --respaldo <ruta a un data.json (el de produccion)>
 */

const LW_COLECCION_TTL_INTRANET = 60;  // s — contenido Y estado de unidades en una sola llamada (ver cabecera)
const LW_COLECCION_FALLO_TTL    = 30;  // s — tras un fallo de la RPC no se reintenta (no hacer esperar a cada visita)
const LW_COLECCION_SB_URL = 'https://vtulllundrfennhjddhc.supabase.co';
const LW_COLECCION_SB_KEY = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg'; // PUBLICABLE (igual que modelo/catalogo.php)
const LW_COLECCION_ESCRIBE_CADA = 300; // s — cada cuánto se refresca la caché con la fuente 'datajson'

/** Configuración efectiva. Las variables de entorno existen para el test y para el corte de F5b
 *  (se fijan en el servidor, nunca vienen de la petición). */
function lw_coleccion_cfg($forzada = null) {
    $raiz = dirname(__DIR__);
    $fuente = $forzada ?: getenv('LW_COLECCION_FUENTE');
    if (!in_array($fuente, ['datajson', 'intranet'], true)) {
        if ($fuente !== false && $fuente !== '') {
            error_log('lw_coleccion: LW_COLECCION_FUENTE desconocida (' . $fuente . '), se usa datajson');
        }
        $fuente = 'datajson';
    }
    $cache = getenv('LW_COLECCION_CACHE');
    if (!$cache) {
        $priv = $raiz . '/private';
        $nombre = $fuente === 'intranet' ? 'coleccion_intranet' : 'coleccion'; // una caché por fuente
        $cache = (is_dir($priv) && is_writable($priv))
            ? $priv . '/' . $nombre . '.json'
            : sys_get_temp_dir() . '/lw_' . $nombre . '.json';
    }
    return [
        'fuente'   => $fuente,
        'datajson' => getenv('LW_COLECCION_DATAJSON') ?: $raiz . '/data.json',
        'cache'    => $cache,
        'respaldo' => getenv('LW_COLECCION_RESPALDO') ?: __DIR__ . '/respaldo.json',
        'contrato' => __DIR__ . '/contrato_publico.json',
        'rpc'      => getenv('LW_COLECCION_RPC_URL') ?: LW_COLECCION_SB_URL . '/rest/v1/rpc/coleccion_publica', // env: solo test
        'bucket'   => rtrim(getenv('LW_COLECCION_BUCKET_URL') ?: LW_COLECCION_SB_URL . '/storage/v1/object/public/deck', '/'),
        'ttl'      => $fuente === 'intranet' ? LW_COLECCION_TTL_INTRANET : 0,
    ];
}

function lw_coleccion_contrato($ruta) {
    static $memo = [];
    if (isset($memo[$ruta])) return $memo[$ruta];
    $c = json_decode((string) @file_get_contents($ruta), true);
    if (!is_array($c) || empty($c['ficha']) || empty($c['raiz']) || !isset($c['prohibidas_exactas'])) {
        // Sin contrato no hay lista blanca: no se publica nada antes que publicarlo todo.
        throw new RuntimeException('contrato_publico.json ilegible o incompleto: ' . $ruta);
    }
    return $memo[$ruta] = $c;
}

function lw_coleccion_es_prohibida($k, array $c) {
    $k = strtolower((string) $k);
    if (in_array($k, $c['prohibidas_exactas'], true)) return true;
    foreach ($c['prohibidas_prefijo'] ?? [] as $pre) {
        if (strpos($k, $pre) === 0) return true;
    }
    return false;
}

/** Recorre el valor a cualquier profundidad y lanza si alguna CLAVE es prohibida. */
function lw_coleccion_busca_prohibidas($v, array $c, $donde) {
    if (!is_array($v)) return;
    foreach ($v as $k => $sub) {
        if (is_string($k) && lw_coleccion_es_prohibida($k, $c)) {
            throw new RuntimeException("clave prohibida '$k' en $donde");
        }
        lw_coleccion_busca_prohibidas($sub, $c, $donde . '/' . $k);
    }
}

/**
 * Filtra un documento al contrato público. Entrada: {properties, settings, downloads, ...}.
 * Salida: solo {properties (visible===true, solo claves de la lista blanca), settings (solo las
 * permitidas), downloads}. Lanza RuntimeException si hay claves prohibidas o la forma no vale.
 * Función pura: no toca disco salvo el contrato.
 */
function lw_coleccion_aplica_contrato($doc, $rutaContrato = null) {
    $c = lw_coleccion_contrato($rutaContrato ?? __DIR__ . '/contrato_publico.json');
    if (!is_array($doc) || !isset($doc['properties']) || !is_array($doc['properties'])) {
        throw new RuntimeException('documento sin properties');
    }
    $blanca = array_flip($c['ficha']);
    $props = [];
    foreach ($doc['properties'] as $p) {
        if (!is_array($p) || ($p['visible'] ?? null) !== true) continue; // el UNICO filtro de visibilidad
        $id = $p['id'] ?? '';
        if (!is_string($id) || !preg_match('/^[A-Za-z0-9-]+$/', $id)) continue; // misma regla que acepta thecollection.php
        lw_coleccion_busca_prohibidas($p, $c, 'ficha ' . $id);
        $props[] = array_intersect_key($p, $blanca);
    }
    $settings = [];
    if (isset($doc['settings']) && is_array($doc['settings'])) {
        $settings = array_intersect_key($doc['settings'], array_flip($c['settings']));
    }
    $downloads = $doc['downloads'] ?? [];
    lw_coleccion_busca_prohibidas($downloads, $c, 'downloads');
    return ['properties' => $props, 'settings' => $settings, 'downloads' => $downloads];
}

/** Lee un JSON de disco y le aplica el contrato. null (y log) si no vale. Un documento con
 *  CERO fichas visibles se trata como fallo: es casi seguro un despiste o un fichero cortado,
 *  y la web sin ninguna ficha no es más segura que la de hace un rato (igual que catalogo.php). */
function lw_coleccion_lee($ruta, $etiqueta, array $cfg) {
    if (!is_file($ruta)) return null;
    $d = json_decode((string) @file_get_contents($ruta), true);
    if (!is_array($d)) { error_log("lw_coleccion: $etiqueta ilegible ($ruta)"); return null; }
    try {
        $r = lw_coleccion_aplica_contrato($d, $cfg['contrato']);
    } catch (RuntimeException $e) {
        error_log("lw_coleccion: $etiqueta RECHAZADO por el contrato publico: " . $e->getMessage());
        return null;
    }
    if (!$r['properties']) { error_log("lw_coleccion: $etiqueta sin fichas visibles, se ignora"); return null; }
    return $r;
}

/** Escritura atómica (rename): dos visitas a la vez no leen un JSON a medias. */
function lw_coleccion_escribe($ruta, array $doc) {
    $tmp = $ruta . '.' . getmypid() . '.tmp';
    if (@file_put_contents($tmp, json_encode($doc, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)) !== false) {
        @rename($tmp, $ruta);
    }
}

/** Ruta de bucket -> URL pública. Solo se compone una ruta con la forma `carpeta/fichero.ext` sin «/»
 *  inicial, sin «..» ni esquema; cualquier otra cosa (URL del servidor, http, texto raro) pasa tal cual. */
function lw_coleccion_url_bucket($v, $base) {
    if (!is_string($v) || !preg_match('#^[A-Za-z0-9_-]+(/[A-Za-z0-9._-]+)+\.(webp|jpe?g|png|avif|svg)$#i', $v) || strpos($v, '..') !== false) return $v;
    return $base . '/' . implode('/', array_map('rawurlencode', explode('/', $v)));
}

/** Compone las URLs del bucket en las claves de imagen de una ficha de la RPC. */
function lw_coleccion_compone_imagenes(array $p, $base) {
    if (isset($p['images']) && is_array($p['images'])) {
        $p['images'] = array_map(function ($u) use ($base) { return lw_coleccion_url_bucket($u, $base); }, $p['images']);
    }
    if (isset($p['masterplanImage'])) $p['masterplanImage'] = lw_coleccion_url_bucket($p['masterplanImage'], $base);
    if (isset($p['homeModels']) && is_array($p['homeModels'])) {
        foreach ($p['homeModels'] as $i => $m) {
            if (is_array($m) && isset($m['image'])) $p['homeModels'][$i]['image'] = lw_coleccion_url_bucket($m['image'], $base);
        }
    }
    return $p;
}

/** POST {} a la RPC. Devuelve el array decodificado o null. Timeouts cortos: está en el camino de una página
 *  pública (mejor la caché vieja que hacer esperar a alguien que llegó por un anuncio). */
function lw_coleccion_rpc_fetch(array $cfg) {
    if (!function_exists('curl_init')) return null;
    $ch = curl_init($cfg['rpc']);
    curl_setopt_array($ch, [
        CURLOPT_POST => true, CURLOPT_POSTFIELDS => '{}', CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 4, CURLOPT_CONNECTTIMEOUT => 3, CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER => ['apikey: ' . LW_COLECCION_SB_KEY, 'Content-Type: application/json'],
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($body) || $body === '') return null;
    $d = json_decode($body, true);
    return (is_array($d) && isset($d['properties']) && is_array($d['properties'])) ? $d : null;
}

/** Fuente 'intranet': RPC + settings/downloads de data.json (transitorio) + lista blanca. */
function lw_coleccion_fuente_intranet(array $cfg) {
    $fallo = $cfg['cache'] . '.fallo';
    if (is_file($fallo) && time() - (int) filemtime($fallo) < LW_COLECCION_FALLO_TTL) return null;
    $rpc = lw_coleccion_rpc_fetch($cfg);
    if ($rpc === null) {
        error_log('lw_coleccion: la RPC coleccion_publica no responde o devuelve basura; se sirve cache vieja/respaldo');
        @touch($fallo);
        return null;
    }
    $legacy = is_file($cfg['datajson']) ? json_decode((string) @file_get_contents($cfg['datajson']), true) : null;
    $legacy = is_array($legacy) ? $legacy : [];
    $props = [];
    foreach ($rpc['properties'] as $p) {
        $props[] = is_array($p) ? lw_coleccion_compone_imagenes($p, $cfg['bucket']) : $p;
    }
    $doc = ['properties' => $props, 'settings' => $legacy['settings'] ?? [], 'downloads' => $legacy['downloads'] ?? []];
    try {
        $r = lw_coleccion_aplica_contrato($doc, $cfg['contrato']);
    } catch (RuntimeException $e) {
        error_log('lw_coleccion: RPC RECHAZADA por el contrato publico: ' . $e->getMessage());
        @touch($fallo);
        return null;
    }
    if (!$r['properties']) {
        error_log('lw_coleccion: la RPC devolvio 0 fichas visibles, se trata como fallo (ver cabecera)');
        @touch($fallo);
        return null;
    }
    @unlink($fallo);
    return $r;
}

/** La fuente. Devuelve el documento ya filtrado, o null si no pudo. */
function lw_coleccion_fuente(array $cfg) {
    if ($cfg['fuente'] === 'intranet') return lw_coleccion_fuente_intranet($cfg);
    return lw_coleccion_lee($cfg['datajson'], 'data.json', $cfg);
}

/** Carga completa por los niveles, sin memo. `$cfg` inyectable (test). */
function lw_coleccion_carga(array $cfg) {
    $con = function (array $r, $fuente, $stale) {
        $r['fuente'] = $fuente;
        $r['stale']  = $stale;
        return $r;
    };
    $cache = $cfg['cache'];
    $edad  = is_file($cache) ? time() - (int) filemtime($cache) : PHP_INT_MAX;

    if ($cfg['ttl'] > 0 && $edad < $cfg['ttl']) {
        if ($r = lw_coleccion_lee($cache, 'cache', $cfg)) return $con($r, 'cache', false);
    }
    if ($r = lw_coleccion_fuente($cfg)) {
        if ($edad >= ($cfg['ttl'] > 0 ? $cfg['ttl'] : LW_COLECCION_ESCRIBE_CADA)) {
            lw_coleccion_escribe($cache, $r);
        }
        return $con($r, $cfg['fuente'], false);
    }
    if ($r = lw_coleccion_lee($cache, 'cache vieja', $cfg)) return $con($r, 'cache', true);
    if ($r = lw_coleccion_lee($cfg['respaldo'], 'respaldo', $cfg)) return $con($r, 'respaldo', true);
    error_log('lw_coleccion: ni fuente, ni cache, ni respaldo — The Collection sale vacia');
    return ['properties' => [], 'settings' => [], 'downloads' => [], 'fuente' => 'ninguna', 'stale' => true];
}

/** El documento publico de The Collection: {properties, settings, downloads, fuente, stale}.
 *  Misma forma que data.json (menos lo no publicable) para que la SPA solo cambie de fuente. */
function lw_coleccion($fuente = null) {
    static $memo = [];
    $k = $fuente ?: 'env';
    if (!isset($memo[$k])) $memo[$k] = lw_coleccion_carga(lw_coleccion_cfg($fuente));
    return $memo[$k];
}

function lw_coleccion_props($fuente = null) { return lw_coleccion($fuente)['properties']; }

function lw_coleccion_ids() {
    return array_map(function ($p) { return $p['id']; }, lw_coleccion_props());
}

/** La ficha pública de un id, o null. «No existe» y «no es visible» son indistinguibles a
 *  propósito (un 404 distinto permitiría enumerar los ids ocultos): aquí lo oculto no llega. */
function lw_coleccion_ficha($id, $fuente = null) {
    foreach (lw_coleccion_props($fuente) as $p) {
        if ($p['id'] === $id) return $p;
    }
    return null;
}

/* Regenerar el respaldo:  php coleccion/lib.php --respaldo <data.json de produccion>
   Solo CLI y solo si este fichero es el que se ejecuta (no al incluirlo desde un test). */
if (PHP_SAPI === 'cli' && isset($argv[0], $argv[1]) && realpath($argv[0]) === realpath(__FILE__) && $argv[1] === '--respaldo') {
    $origen = $argv[2] ?? '';
    $d = json_decode((string) @file_get_contents($origen), true);
    if (!is_array($d)) { fwrite(STDERR, "Uso: php coleccion/lib.php --respaldo <ruta a data.json>\n"); exit(1); }
    try {
        $r = lw_coleccion_aplica_contrato($d);
    } catch (RuntimeException $e) { fwrite(STDERR, 'Contrato: ' . $e->getMessage() . "\n"); exit(1); }
    if (!$r['properties']) { fwrite(STDERR, "Sin fichas visibles: no se genera respaldo vacio.\n"); exit(1); }
    $out = ['_aviso' => 'FOTO GENERADA — no editar a mano. Solo fichas visibles y solo claves del contrato '
          . 'publico (coleccion/contrato_publico.json). Se regenera con `php coleccion/lib.php --respaldo <data.json>`. '
          . 'Un cambio hecho aqui vive hasta que la fuente responda y luego desaparece sin avisar.'] + $r;
    file_put_contents(__DIR__ . '/respaldo.json',
        json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");
    echo 'Respaldo regenerado: ' . count($r['properties']) . " fichas visibles.\n";
}
