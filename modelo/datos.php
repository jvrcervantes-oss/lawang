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
 * Nombre y descripción de los siete extras. El PRECIO no está aquí: vive en `modelos.php`
 * porque dos de los siete (Airbnb Kit y Oasis Pool) escalan con el modelo.
 *
 * Las descripciones son las de la columna «EXTRAS INFO» del price list del owner (Google
 * Sheet, 7-sep-2026), traducidas al inglés porque estas landings son solo inglés desde el
 * pivote australiano del 2-sep. `airbnb` se queda SIN descripción a propósito: el price
 * list no trae ninguna para ese, y rellenarla con algo plausible sería inventarse qué
 * incluye un extra de 5.000-8.000 € en una página de tráfico de pago.
 *
 * El ORDEN de este array es el que se pinta.
 */
function lw_extras_meta() {
    return [
        'airbnb'   => ['nombre' => 'Airbnb Kit',        'desc' => null],
        'zero'     => ['nombre' => 'Zero Chemical Pool', 'desc' => 'Ozone purification, no chlorine'],
        // Ampersand CRUDO, no `&amp;`: estas descripciones viajan en JSON al JS y se pintan
        // con textContent, que NO decodifica entidades — con `&amp;` se lee literal en la
        // pagina. Si algun dia se pintaran con innerHTML habria que escaparlas ahi.
        'recovery' => ['nombre' => 'Recovery',          'desc' => 'Fire & Ice 2 m pools'],
        'sauna'    => ['nombre' => 'Sauna',             'desc' => '2 × 1.5 m — fits four'],
        'rooftop'  => ['nombre' => 'Rooftop',           'desc' => 'Sofa, BBQ and shade included'],
        'oasis'    => ['nombre' => 'Oasis Pool',        'desc' => 'White cement pool with a beach finish, natural rock and palms'],
        'gym'      => ['nombre' => 'Exterior Gym',      'desc' => 'Three-level pull-up bar, dip bar, dumbbell kit, press bench, flat bench'],
    ];
}

/** Cruza `lw_extras_meta()` con los precios del modelo. Lista ordenada y lista para pintar. */
function lw_extras_resueltos(array $m) {
    $precios = isset($m['extras']) && is_array($m['extras']) ? $m['extras'] : [];
    $out = [];
    foreach (lw_extras_meta() as $id => $meta) {
        if (!isset($precios[$id])) continue;   // sin precio no se ofrece: no se estima a ojo
        $out[] = [
            'id'     => $id,
            'nombre' => $meta['nombre'],
            'desc'   => $meta['desc'],
            'eur'    => (int) $precios[$id],
        ];
    }
    return $out;
}

/**
 * Snapshot financiero de ejemplo — sección "Snapshot financiero" de /modelo/<id>
 * (21-sep-2026, restyle Modo calco). SIEMPRE la economía de Villa Dali en Palm Field W5:
 * es un ejemplo fijo elegido por el owner en la revisión previa, no el proyecto de la
 * página que se esté viendo — por eso el texto de la plantilla lo rotula explícitamente
 * como "economics on a Palm Field W5 plot", nunca como una cifra universal del modelo.
 *
 * Lee la RPC pública `deck_forecast_ejemplo_publico()` (contracts/sql/, migración
 * 20260921060245) — NUNCA las tablas `deck_forecast`/`deck_forecast_proyecto` a secas:
 * están protegidas por RLS a es_agente()/es_admin() (son el investor deck privado) y la
 * RPC es la única ventana de solo lectura que un visitante anónimo puede usar.
 *
 * Mismo patrón de caché en 3 niveles que lw_catalogo() (arriba en este mismo fichero):
 * una landing pública no puede depender de que Supabase responda en cada visita, y sin
 * NADA que servir (sin caché, sin red) la sección se OCULTA — nunca un cero ni un dato
 * inventado. `static $memo` usa `false` como centinela de "aún no resuelto" porque `null`
 * es una respuesta válida (recurso sin caché y sin red).
 */
function lw_deck_forecast_cache_path() {
    $priv = __DIR__ . '/../private';
    if (is_dir($priv) && is_writable($priv)) return $priv . '/deck_forecast_ejemplo.json';
    return sys_get_temp_dir() . '/lw_deck_forecast_ejemplo.json';
}

/**
 * Devuelve, sin ambigüedad, TRES cosas distintas (hallazgo de code-review, 21-sep-2026 —
 * la primera versión las confundía):
 *   - array  → la RPC respondió 200 con datos: la fila sigue publicada.
 *   - null   → la RPC respondió 200 con el JSON `null`: es una respuesta VÁLIDA y
 *     AUTORITATIVA — la fila dejó de estar publicada. No es un fallo de red.
 *   - false  → no se pudo ni preguntar (sin curl, timeout, HTTP != 200, JSON inválido):
 *     esto SÍ es un fallo de red, y es el único caso en el que vale la pena caer a la
 *     caché vieja en vez de creer la respuesta.
 * Antes ambos casos devolvían `null` y lw_deck_forecast_ejemplo() no podía distinguir
 * "la fila se despublicó, hay que ocultar" de "Supabase no respondió, sirve lo de antes"
 * — con eso, una vez que había CUALQUIER caché en disco, despublicar la fila en la
 * intranet nunca llegaba a ocultar la sección en la web: cada 5 minutos volvía a fallar
 * "network" y volvía a caer a la misma caché vieja, para siempre.
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
    if ($d === null) return null;      // JSON `null` de verdad: autoritativo, fila despublicada
    return is_array($d) ? $d : false;  // cualquier otra forma: no es lo que se esperaba
}

function lw_deck_forecast_ejemplo() {
    static $memo = false; // false = "aún no resuelto"; distinto de null (resuelto y vacío)
    if ($memo !== false) return $memo;

    $cache  = lw_deck_forecast_cache_path();
    $fresca = is_file($cache) && (time() - filemtime($cache) < LW_CAT_TTL);

    if ($fresca) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d)) return $memo = $d;
    }

    $d = lw_deck_forecast_fetch();
    if ($d === null) {
        // Autoritativo: la fila dejó de estar publicada. La caché vieja NO puede seguir
        // sirviendo un dato que ya no es cierto — se borra, no se conserva "por si acaso".
        @unlink($cache);
        return $memo = null;
    }
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
    // Sin caché y sin red: null. La plantilla oculta la sección entera.
    return $memo = null;
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
