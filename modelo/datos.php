<?php
/**
 * Datos de la landing australiana /dali — 4-sep-2026.
 *
 * Existe para que la plantilla no calcule nada: aquí se resuelve TODO (precios activos,
 * conversión a AUD, catálogo de villas, tarifas de parcela) y `index.php` solo pinta.
 *
 * Reutiliza `modelo/lib.php` y `modelo/modelos.php` a propósito: los precios de las cinco
 * villas tienen UNA fuente y es esa. Duplicar aquí la tabla habría creado la segunda copia
 * del dato más caro del proyecto — exactamente la familia de fallo de «El dato tiene un
 * dueño» (contexto/patrones_tecnicos.md), que en este mismo proyecto ya costó 141 parcelas
 * con el precio mal el 28-ago.
 */

require_once __DIR__ . '/lib.php';
// `catalogo.php` trae LW_SB_URL/LW_SB_KEY/LW_CAT_TTL, que lw_deck_forecast_ejemplo() (mas
// abajo) reutiliza para no inventar una segunda conexion a Supabase. `require_once` es
// idempotente: modelos.php YA lo requiere, esto solo evita depender del ORDEN en que
// index.php cargue los ficheros — sin esto, llamar a lw_deck_forecast_ejemplo() antes de
// requerir modelos.php (un futuro caller que no sea esta landing) rompería con
// "constante indefinida" en vez de fallar de forma obvia en el require.
require_once __DIR__ . '/catalogo.php';

/**
 * Tipo de cambio EUR→AUD.
 *
 * ⚠️ Es un valor FIJO con fecha, no una cotización en vivo: el estudio no tiene contratado
 * ningún proveedor de FX, y una cifra que se presenta como "live" sin serlo envejece en
 * silencio — que es justo lo que la casa tiene escrito que no se hace ("cada dato volátil
 * lleva su fecha"). Por eso la página rotula los importes en AUD como indicativos y con la
 * fecha del tipo, y el importe que manda a ventas sigue siendo el EUR.
 *
 * Revisar cuando el euro se mueva más de un ~5% contra el dólar australiano.
 */
const LW_AUD_TASA  = 1.62;
const LW_AUD_FECHA = '4 Sep 2026';

/**
 * Tabla de divisas de las landings. UNA sola, y aqui, porque este fichero ya es el que
 * resuelve los precios de /dali y /palmfield: si la tabla viviera en el JS de la pagina,
 * el selector convertiria con un tipo y el estimador con otro — misma villa, dos precios,
 * una sola pagina. Esa es la familia de fallo de LAW-123 y del deposito de B2K.
 *
 * AUD va a LW_AUD_TASA (1,62). Unificado el 16-sep-2026 (decision del owner, LAW-173):
 * esta tabla de precios en EUR es la que manda, y el investor deck y
 * `assets/lawang-card.js` (que antes usaban 1,65, un tipo distinto) se ajustaron a este
 * mismo 1,62 para que no haya dos precios AUD distintos para la misma villa.
 *
 * USD e IDR salen de la misma tabla que el resto de la casa (`assets/lawang-card.js`).
 * Como el AUD: valores FIJOS con fecha, nunca cotizacion en vivo — el estudio no tiene
 * proveedor de FX y una cifra presentada como "live" sin serlo envejece en silencio.
 * El contrato va SIEMPRE en EUR; el resto es orientativo.
 */
const LW_DIV_FECHA = '11 Sep 2026';
function lw_divisas() {
    return [
        'EUR' => ['tasa' => 1.0,          'sim' => '€',         'dec' => 0],
        'USD' => ['tasa' => 1.08,         'sim' => '$',         'dec' => 0],
        'AUD' => ['tasa' => LW_AUD_TASA,  'sim' => 'A$',        'dec' => 0],
        'IDR' => ['tasa' => 17500.0,      'sim' => 'Rp ',       'dec' => 0],
    ];
}

/** EUR → AUD, redondeado a la decena para no fingir una precisión que el tipo fijo no da. */
function lw_aud($eur) {
    if ($eur === null) return null;
    return (int) (round(($eur * LW_AUD_TASA) / 10) * 10);
}

/** "$110,160 AUD" — formato australiano: separador de millares y símbolo delante. */
function lw_aud_fmt($eur) {
    $a = lw_aud($eur);
    return $a === null ? null : '$' . number_format($a, 0, '.', ',') . ' AUD';
}

/**
 * Cruza los extras YA RESUELTOS del catálogo (nombre+desc+precio+orden, `catalogo_publico()`)
 * en una lista ordenada y lista para pintar.
 *
 * ⚠️ 21-sep-2026: hasta hoy el nombre y la descripción de los 7 extras vivían en un array
 * fijo aquí mismo (`lw_extras_meta()`, ya retirada) — una copia a mano de la columna
 * `extras.descripcion` de Supabase, que SÍ es editable desde /intranet/modelos/ pero cuyo
 * cambio nunca llegaba a la web pública porque esta seguía leyendo la copia. Mismo patrón
 * de "el dato tiene un dueño" que ya mordió con las fotos de modelo el mismo día. Ahora
 * nombre/desc/orden salen del propio `$m['extras'][id]`, que ya trae eso resuelto.
 *
 * `airbnb` seguía sin descripción en el price list del owner (7-sep-2026) cuando esto se
 * escribió — si algún día se rellena en Supabase, aparece aquí sin tocar código.
 */
function lw_extras_resueltos(array $m) {
    $extras = isset($m['extras']) && is_array($m['extras']) ? $m['extras'] : [];
    $out = [];
    foreach ($extras as $id => $e) {
        if (!isset($e['precio'])) continue;   // sin precio no se ofrece: no se estima a ojo
        $out[] = [
            'id'     => $id,
            'nombre' => $e['nombre_en'] ?? ($e['nombre'] ?? ''),
            'desc'   => $e['desc_en'] ?: null,
            'eur'    => (int) $e['precio'],
            'orden'  => $e['orden'] ?? 999,
        ];
    }
    usort($out, function ($a, $b) { return $a['orden'] <=> $b['orden']; });
    return $out;
}

/**
 * Snapshot financiero de ejemplo — sección "Snapshot financiero" de /modelo/<id>.
 *
 * ⚠️ 21-sep-2026: pasa de UN ejemplo fijo (siempre Villa Dali en Palm Field W5, se mirara
 * la ficha que se mirara) a un OBJETO por slug de modelo, con los 3 pares (modelo,proyecto)
 * confirmados por el owner como datos reales — Dali/Dream/Dune, todos en Palm Field W5
 * (`deck_forecast_ejemplo_publico()`, migración `deck_forecast_ejemplo_publico_por_modelo`).
 * `deck_forecast` tiene MÁS filas publicadas de las que parecen fiables (Bonian Village
 * para Dali está `publicado=true` y `destacado=true` con 5% de ocupación — dato de prueba,
 * no real) así que el par se sigue fijando a mano en la RPC, nunca "el primero publicado".
 * Un modelo SIN par confirmado (Loftbung, Temple, Trinity) no sale en el objeto — la
 * plantilla debe OCULTAR la sección entera para ese modelo, no caer al ejemplo de otro.
 *
 * Lee la RPC pública `deck_forecast_ejemplo_publico()` — NUNCA las tablas
 * `deck_forecast`/`deck_forecast_proyecto` a secas: están protegidas por RLS a
 * es_agente()/es_admin() (son el investor deck privado) y la RPC es la única ventana de
 * solo lectura que un visitante anónimo puede usar.
 *
 * Mismo patrón de caché en 3 niveles que lw_catalogo() (arriba en este mismo fichero): una
 * landing pública no puede depender de que Supabase responda en cada visita, y sin NADA
 * que servir (sin caché, sin red) la sección se OCULTA — nunca un cero ni un dato inventado.
 */
function lw_deck_forecast_cache_path() {
    $priv = __DIR__ . '/../private';
    if (is_dir($priv) && is_writable($priv)) return $priv . '/deck_forecast_ejemplo.json';
    return sys_get_temp_dir() . '/lw_deck_forecast_ejemplo.json';
}

/**
 * `false` = fallo de red/HTTP/JSON inválido (no fiable, cae a la caché vieja). `array` = la
 * RPC respondió 200 con un objeto — SIEMPRE un objeto, `{}` incluido si ningún modelo tiene
 * ejemplo confirmado ahora mismo (a diferencia de la versión de un solo modelo, esta RPC ya
 * no devuelve `null` a nivel raíz: `coalesce(..., '{}'::jsonb)` en el propio SQL). Un objeto
 * vacío SÍ es autoritativo y se cachea igual: significa "hoy nadie tiene ejemplo publicado",
 * no "no se pudo preguntar".
 */
function lw_deck_forecast_fetch() {
    if (!function_exists('curl_init')) return false;
    $ch = curl_init(LW_SB_URL . '/rest/v1/rpc/deck_forecast_ejemplo_publico');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => '{}',
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 4,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER     => [
            'apikey: ' . LW_SB_KEY,
            'Content-Type: application/json',
        ],
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($body) || $body === '') return false;
    $d = json_decode($body, true);
    if (json_last_error() !== JSON_ERROR_NONE) return false; // cuerpo no es JSON: no fiable
    return is_array($d) ? $d : false; // cualquier otra forma: no es lo que se esperaba
}

/** El mapa {slug: ejemplo} completo, o `[]` si nadie tiene ejemplo confirmado ahora mismo.
 *  El llamador (index.php) extrae `$mapa[$m['id']] ?? null` para EL modelo de esta página. */
function lw_deck_forecast_ejemplo() {
    static $memo = null;
    if ($memo !== null) return $memo;

    $cache  = lw_deck_forecast_cache_path();
    $fresca = is_file($cache) && (time() - filemtime($cache) < LW_CAT_TTL);

    if ($fresca) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d)) return $memo = $d;
    }

    $d = lw_deck_forecast_fetch();
    if (is_array($d)) {
        $tmp = $cache . '.' . getmypid() . '.tmp';
        if (@file_put_contents($tmp, json_encode($d, JSON_UNESCAPED_UNICODE)) !== false) {
            @rename($tmp, $cache);
        }
        return $memo = $d;
    }
    // $d === false: fallo de red/HTTP, NO autoritativo — la caché vieja, si la hay, sigue
    // siendo mejor que nada, y nunca se borra por un fallo de red.
    if (is_file($cache)) {
        $cached = json_decode((string) @file_get_contents($cache), true);
        if (is_array($cached)) return $memo = $cached;
    }
    // Sin caché y sin red: mapa vacío. La plantilla oculta la sección para todos.
    return $memo = [];
}

/**
 * Catálogo de las cinco villas resuelto para la plantilla: precio activo (2026 o 2027,
 * según el reloj del servidor en Bali) en EUR y en AUD, specs y render de portada.
 */
function lw_au_catalogo() {
    $modelos = require __DIR__ . '/modelos.php';
    $out = [];
    foreach ($modelos as $id => $m) {
        // FIX DE EMERGENCIA (21-sep-2026, hallazgo de code-review + caída real en
        // produccion): un modelo publicado sin filas en `modelo_techos` (Loftbung, desde
        // el 15-sep) llegaba aqui con `$m['techos']` sin definir. `lw_techo_precio_activo()`
        // exige `array $techo` sin admitir null, asi que `$m['techos']['sirap']` sobre un
        // array inexistente lanzaba un TypeError SIN CAPTURAR — fatal, y esta funcion la
        // llaman TODAS las paginas de producto (/dali, /modelo/<id>, /palmfield) para
        // montar el selector de villa del configurador: un modelo mal cargado tiraba abajo
        // las tres. Mismo criterio que "sin render no se enseña": un modelo sin los dos
        // techos resueltos no puede participar en el configurador (necesita precio de
        // villa por techo) y se omite del catálogo entero en vez de reventar la página.
        if (empty($m['techos']['sirap']) || empty($m['techos']['bambu'])) continue;
        $imgs  = lw_modelo_imgs($id);
        $sirap = lw_techo_precio_activo($m['techos']['sirap']);
        $bambu = lw_techo_precio_activo($m['techos']['bambu']);
        $out[$id] = [
            'id'        => $id,
            'nombre'    => $m['nombre'],
            'villa'     => 'Villa ' . $m['nombre'],
            'dorm'      => (int) $m['dormitorios'],
            'banos'     => (int) $m['banos'],
            'villa_m2'  => (int) $m['villa_m2'],
            'terraza_m2'=> (int) $m['terraza_m2'],
            'specs'     => $m['villa_m2'] . 'm² + ' . $m['terraza_m2'] . 'm² terrace · '
                           . (int) $m['dormitorios'] . ' bed · ' . (int) $m['banos'] . ' bath',
            'thumb'     => $imgs[0] ?? null,
            'sinRender' => empty($imgs),
            'imgs'      => $imgs,
            'techos'    => [
                'sirap' => ['nombre' => $m['techos']['sirap']['nombre'], 'eur' => $sirap],
                'bambu' => ['nombre' => $m['techos']['bambu']['nombre'], 'eur' => $bambu],
            ],
            // El "desde" de cada villa es su techo más barato — nunca la suma de los dos,
            // que es el error que ya cazó Diseño el 3-sep: Sirap y Bambú son dos PRECIOS
            // de villa alternativos, no un precio y un recargo.
            'desde_eur' => min($sirap, $bambu),
            // Extras resueltos: metadatos comunes + el precio de ESTE modelo. Un modelo sin
            // la clave `extras` (los que lleguen nuevos al catálogo) sale con la lista vacía
            // y la plantilla oculta el paso — nunca con un precio heredado de otro modelo.
            'extras'    => lw_extras_resueltos($m),
        ];
    }
    return $out;
}
