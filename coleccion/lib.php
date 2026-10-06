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

/** POST {} a la RPC. Devuelve el array decodificado o null; `$diag` recibe por qué falló (para el log: sin
 *  él, «no responde» no distingue un timeout de una conexión rechazada de un 401). Timeouts cortos: está en el
 *  camino de una página pública (mejor la caché vieja que hacer esperar a alguien que llegó por un anuncio). */
function lw_coleccion_rpc_fetch(array $cfg, &$diag = null) {
    if (!function_exists('curl_init')) { $diag = 'sin extension curl'; return null; }
    $ch = curl_init($cfg['rpc']);
    curl_setopt_array($ch, [
        CURLOPT_POST => true, CURLOPT_POSTFIELDS => '{}', CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 4, CURLOPT_CONNECTTIMEOUT => 3, CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER => ['apikey: ' . LW_COLECCION_SB_KEY, 'Content-Type: application/json'],
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $t = round((float) curl_getinfo($ch, CURLINFO_TOTAL_TIME), 2);
    $err = curl_error($ch);
    curl_close($ch);
    $diag = "http=$code t={$t}s" . ($err !== '' ? " curl=\"$err\"" : '');
    if ($code !== 200 || !is_string($body) || $body === '') return null;
    $d = json_decode($body, true);
    if (!(is_array($d) && isset($d['properties']) && is_array($d['properties']))) { $diag .= ' cuerpo no valido'; return null; }
    return $d;
}

/** Fuente 'intranet': RPC + settings/downloads de data.json (transitorio) + lista blanca. */
function lw_coleccion_fuente_intranet(array $cfg) {
    $fallo = $cfg['cache'] . '.fallo';
    if (is_file($fallo) && time() - (int) filemtime($fallo) < LW_COLECCION_FALLO_TTL) return null;
    $rpc = lw_coleccion_rpc_fetch($cfg, $diag);
    // CACHE FRIA (nada en disco que servir como «vieja»): un solo fallo aislado —handshake lento del primer
    // contacto tras un despliegue, un reinicio de PHP— dejaba la primera pagina en `stale` (todas las tarjetas
    // en «Ask for availability») aunque la RPC estuviera sana. Con cache vieja NO se reintenta: ya hay con que
    // servir sin hacer esperar. El peor caso (cache fria y Supabase caido de verdad) son 2 intentos UNA vez
    // cada LW_COLECCION_FALLO_TTL, porque el marcador de fallo cierra la puerta al resto.
    if ($rpc === null && !(is_file($cfg['cache']) && filesize($cfg['cache']) > 0)) {
        error_log('lw_coleccion: RPC coleccion_publica fallo con la cache fria (' . $diag . '); un reintento');
        usleep(300000);
        $rpc = lw_coleccion_rpc_fetch($cfg, $diag);
    }
    if ($rpc === null) {
        error_log('lw_coleccion: la RPC coleccion_publica no responde o devuelve basura (' . $diag . '); se sirve cache vieja/respaldo');
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
    // `live` = esta lectura es de la fuente en vivo (intranet): es la señal que activa en la SPA y en la
    // tarjeta TODO lo nuevo de F7 (estado de unidad, «Sold out», bloque Availability). Sin ella (datajson,
    // que no sabe de unidades) la web pinta exactamente lo de siempre.
    $live = $cfg['fuente'] === 'intranet';
    $con = function (array $r, $fuente, $stale) use ($live) {
        $r['fuente'] = $fuente;
        $r['stale']  = $stale;
        $r['live']   = $live;
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
    return ['properties' => [], 'settings' => [], 'downloads' => [], 'fuente' => 'ninguna', 'stale' => true, 'live' => $live];
}

/** El documento publico de The Collection: {properties, settings, downloads, fuente, stale}.
 *  Misma forma que data.json (menos lo no publicable) para que la SPA solo cambie de fuente. */
function lw_coleccion($fuente = null) {
    static $memo = [];
    $k = $fuente ?: 'env';
    if (!isset($memo[$k])) $memo[$k] = lw_coleccion_carga(lw_coleccion_cfg($fuente));
    return $memo[$k];
}

/** El documento tal como sale al NAVEGADOR (endpoint de la home y precarga de la SPA): una sola función,
 *  para que nadie añada una clave por un lado y no por el otro. Sin `fuente` (infraestructura). `stale`
 *  y `live` van siempre: sin ellos la SPA no puede distinguir «no hay dato» de «hay dato fresco». */
function lw_coleccion_para_navegador(array $doc) {
    return [
        'properties' => $doc['properties'], 'settings' => $doc['settings'], 'downloads' => $doc['downloads'],
        'live' => !empty($doc['live']), 'stale' => !empty($doc['stale']),
    ];
}

/**
 * Estado de disponibilidad de una ficha, derivado SOLO de `parcelas` (la lista del dueño, en tiempo real).
 * UNA regla para el servidor (JSON-LD, noscript); su gemela en JS es LawangCard.estado (assets/lawang-card.js)
 * y los dos tests (coleccion/tests/coleccion_test.php y assets/lawang-card.test.js) afirman la MISMA tabla
 * (coleccion/tests/estados_esperados.json) contra la RPC real: si una cambia y la otra no, el gate falla.
 *   k: na    no se puede afirmar nada: sin parcelas, dato viejo (stale), estado desconocido o unitsAvailable que no cuadra
 *      ok    queda alguna libre (n>1 de t, o t==1 casa única «Available»)   few  queda 1 libre de >=2
 *      held  ninguna libre y alguna reservada   gone  todo vendido
 * d/r/v/t = libres/reservadas/vendidas/total.
 * CRITERIO de «sin parcelas» (decision del owner, 6-oct-2026; antes salia sin chip): riverfront-iii y rurung-anyar no
 * tienen ninguna fila en `unidades` (0 de 0) porque el dueño del dato (la intranet) aun no las ha cargado, no por un
 * fallo de la web. Se muestra «Ask for availability» (`na`): no se afirma ni «Available» ni «Sold», se invita a
 * consultar. En cuanto el equipo cree sus unidades, el chip pasa a su estado real solo. El JSON-LD sigue OMITIENDO
 * `availability` (no hay dato fiable) y `none` ya no existe en esta regla (solo lo usa el JS como centinela data.json).
 */
function lw_coleccion_estado(array $p, $stale = false) {
    $d = $r = $v = $x = 0;
    foreach ((isset($p['parcelas']) && is_array($p['parcelas']) ? $p['parcelas'] : []) as $u) {
        $e = is_array($u) ? ($u['estado'] ?? '') : '';
        if ($e === 'disponible') $d++; elseif ($e === 'reservada') $r++; elseif ($e === 'vendida') $v++; else $x++;
    }
    $t = $d + $r + $v + $x;
    $out = function ($k) use ($d, $r, $v, $t) { return ['k' => $k, 'd' => $d, 'r' => $r, 'v' => $v, 't' => $t]; };
    if ($stale || $t === 0) return $out('na'); // dato viejo, o ficha sin unidades cargadas: «Ask for availability», nunca un estado inventado
    if ($x > 0) return $out('na');
    $ua = $p['unitsAvailable'] ?? null;
    if ($ua !== null && $ua !== '') { // dos contadores que no cuadran (o que no son un entero): no se afirma ninguno
        $un = is_numeric($ua) ? $ua + 0 : null;
        if ($un === null || floor((float) $un) != (float) $un || (int) $un !== $d) return $out('na');
    }
    if ($d > 1 || ($d === 1 && $t === 1)) return $out('ok');
    if ($d === 1) return $out('few');
    return $out($r > 0 ? 'held' : 'gone');
}

/** Texto de precio para quien no ejecuta JS (noscript) y para el JSON-LD: misma regla que la tarjeta.
 *  Vendida (y dato fresco) -> «Sold out»; priceMode fixed -> «€X»; from o ausente (data.json no lo tiene) -> «From €X». */
function lw_coleccion_precio_txt(array $p, $stale = false) {
    $eur = $p['priceEUR'] ?? null;
    if (lw_coleccion_estado($p, $stale)['k'] === 'gone') return 'Sold out';
    if (!is_numeric($eur) || $eur <= 0) return '';
    $n = '€' . number_format((int) $eur, 0, '.', ',');
    return (($p['priceMode'] ?? 'from') === 'fixed') ? $n : 'From ' . $n;
}

/** `offers` del JSON-LD de una ficha, o null si no hay precio. UNA función para la ficha (/property/<id>) y para
 *  el listado (ItemList de The Collection): la regla de disponibilidad no puede vivir en dos sitios.
 *  Con datajson (`$live` false: no sabe de unidades) queda InStock como siempre. Con la intranet la disponibilidad
 *  se DERIVA (lw_coleccion_estado): vendida -> SoldOut, queda 1 -> LimitedAvailability, hay libres -> InStock, y
 *  sin dato fiable (stale, sin parcelas, contadores que no cuadran) o todo reservado se OMITE la clave:
 *  nunca se afirma InStock sin base. */
function lw_coleccion_jsonld_oferta(array $p, $live, $stale) {
    $eur = $p['priceEUR'] ?? null;
    if (!$eur) return null;
    $o = ['@type' => 'Offer', 'price' => (string) $eur, 'priceCurrency' => 'EUR', 'availability' => 'https://schema.org/InStock'];
    if ($live) {
        $k = lw_coleccion_estado($p, $stale)['k'];
        if ($k === 'gone') $o['availability'] = 'https://schema.org/SoldOut';
        elseif ($k === 'few') $o['availability'] = 'https://schema.org/LimitedAvailability';
        elseif ($k !== 'ok') unset($o['availability']);
    }
    return $o;
}

/** JSON-LD de la página de listado (The Collection): CollectionPage de siempre; con datos en vivo, además un
 *  ItemList con una RealEstateListing por ficha publicada (enlace canónico /property/<id>, no la ruta de prueba). */
function lw_coleccion_jsonld_listado(array $doc, $site) {
    $ld = [
        '@context' => 'https://schema.org', '@type' => 'CollectionPage',
        'name' => 'The Collection · Lawang Tropical Properties', 'url' => $site . '/thecollection',
        'description' => 'Land, villas, and resorts in Bali and Sumba. Freehold titled properties by Lawang Tropical Properties.',
        'isPartOf' => ['@type' => 'WebSite', 'name' => 'Lawang Tropical Properties', 'url' => $site . '/'],
    ];
    if (empty($doc['live'])) return $ld;
    $items = [];
    foreach ($doc['properties'] as $p) {
        $id = (string) ($p['id'] ?? '');
        if ($id === '') continue;
        $it = ['@type' => 'RealEstateListing', 'name' => (string) ($p['title']['en'] ?? $id), 'url' => $site . '/property/' . $id];
        if (($p['region'] ?? '') !== '') {
            $it['address'] = ['@type' => 'PostalAddress', 'addressLocality' => (string) $p['region'], 'addressCountry' => 'ID'];
        }
        $of = lw_coleccion_jsonld_oferta($p, true, !empty($doc['stale']));
        if ($of) $it['offers'] = $of;
        $items[] = ['@type' => 'ListItem', 'position' => count($items) + 1, 'item' => $it];
    }
    if ($items) $ld['mainEntity'] = ['@type' => 'ItemList', 'numberOfItems' => count($items), 'itemListElement' => $items];
    return $ld;
}

/** El <noscript> de The Collection para crawlers sin JS, generado del MISMO documento que la página (antes lo
 *  horneaba build_seo.py a mano: incluía fichas ocultas y «From» en precios fijos, y envejecía en silencio). */
function lw_coleccion_noscript(array $doc) {
    $e = function ($v) { return htmlspecialchars((string) $v, ENT_QUOTES | ENT_HTML5, 'UTF-8'); };
    $tenure = ['tenure.freehold' => 'Freehold (HGB)', 'tenure.leasehold' => 'Leasehold — 30 yrs'];
    $status = ['status.ready' => 'Built', 'status.construction' => 'Under construction', 'status.offplan' => 'Off-plan', 'status.land' => 'Titled land'];
    $stale = !empty($doc['stale']);
    $cards = [];
    foreach ($doc['properties'] as $p) {
        $id = (string) ($p['id'] ?? '');
        $title = (string) ($p['title']['en'] ?? $id);
        $region = (string) ($p['region'] ?? '');
        $img = isset($p['images'][0]) ? (string) $p['images'][0] : '';
        $sp = [];
        if (!empty($p['beds']))  $sp[] = $p['beds'] . ' bed';
        if (!empty($p['baths'])) $sp[] = $p['baths'] . ' bath';
        if (!empty($p['built'])) $sp[] = $p['built'] . ' m² built';
        if (!empty($p['land']))  $sp[] = $p['land'] . ' m² land';
        $ho = trim((string) ($p['handover'] ?? ''));
        if (in_array($ho, ['—', '–', '-', '', 'N/A', 'n/a'], true)) $ho = '';
        $meta = array_filter([$status[$p['status'] ?? ''] ?? '', $tenure[$p['tenure'] ?? ''] ?? '', $ho !== '' ? 'Handover ' . $ho : '']);
        $price = lw_coleccion_precio_txt($p, $stale);
        $line = function ($cls, $txt) use ($e) { return $txt === '' ? '' : "
      <p class=\"$cls\">" . $e($txt) . '</p>'; };
        $cards[] = "    <article class=\"seo-prop\">
      "
            . ($img !== '' ? '<img src="' . $e($img) . '" alt="' . $e($title) . ' — ' . $e($region) . '" loading="lazy" width="800" height="600">' : '')
            . "
      <h3><a href=\"/property/" . $e($id) . '">' . $e($title) . '</a></h3>'
            . $line('seo-region', $region) . $line('seo-price', $price) . $line('seo-specs', implode(' · ', $sp))
            . $line('seo-meta', implode(' · ', $meta)) . $line('seo-sub', (string) ($p['sub']['en'] ?? ''))
            . $line('seo-desc', (string) ($p['desc']['en'] ?? '')) . "
    </article>";
    }
    return "<noscript>
  <section class=\"seo-fallback\" aria-label=\"Lawang property portfolio\">
"
        . "    <h1>Lawang — Property Portfolio in Bali &amp; Sumba</h1>
"
        . "    <p>Signature homes, land parcels, villas and resort units across Bali and Sumba, Indonesia. Freehold and leasehold opportunities with managed rental income.</p>
"
        . implode("
", $cards) . "
  </section>
</noscript>";
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
