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
        ];
    }
    return $out;
}
