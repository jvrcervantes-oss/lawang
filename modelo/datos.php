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
 * Catálogo de las cinco villas resuelto para la plantilla: precio activo (2026 o 2027,
 * según el reloj del servidor en Bali) en EUR y en AUD, specs y render de portada.
 */
function lw_au_catalogo() {
    $modelos = require __DIR__ . '/modelos.php';
    $out = [];
    foreach ($modelos as $id => $m) {
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
