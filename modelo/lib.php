<?php
/**
 * lib.php — resolución de modelo e imágenes para las landings /modelo/<id>.
 * Sin estado ni salida: todo lo que hay aquí se puede probar con `php modelo/test_modelo.php`.
 */

/** Huso de Bali (WITA). El corte de precio 2026→2027 se decide con ESTE reloj, nunca con
 * el del visitante ni con nada que llegue por request — cazado en revisión previa (Seguridad,
 * 2-sep): un `?preview2027=1` o una `Date` de JS reintroduce el mismo problema que se evita
 * al quitar el flag manual. Fecha+hora+huso fijos, no "cuando cambie el año" (ambiguo por el
 * huso del visitante, y sin eso no hay forma de saber qué precio vio un lead concreto —
 * hallazgo de Administración en la misma revisión). */
define('LW_TZ_BALI', 'Asia/Makassar');
define('LW_CORTE_2027', '2027-01-01 00:00:00');

/** Renders publicables de un modelo, en orden natural (dali.webp antes que dali2.webp). */
function lw_modelo_imgs($id, $root = null) {
    $root = $root !== null ? $root : dirname(__DIR__);
    $dir  = $root . '/assets/img/buildings/' . $id . '/web';
    $f = glob($dir . '/*.{jpg,jpeg,png,webp}', GLOB_BRACE);
    if (!$f) return [];
    // Original + .webp conviven en disco (conversion 24-ago sin borrar el original,
    // cache CDN 7 dias) — sin esto cada render sale duplicado en la galeria.
    $porStem = [];
    foreach ($f as $p) {
        $stem = pathinfo($p, PATHINFO_FILENAME);
        $esWebp = strtolower(pathinfo($p, PATHINFO_EXTENSION)) === 'webp';
        if (!isset($porStem[$stem]) || $esWebp) $porStem[$stem] = $p;
    }
    $f = array_values($porStem);
    sort($f, SORT_NATURAL);
    $urls = [];
    foreach ($f as $p) {
        $urls[] = '/assets/img/buildings/' . $id . '/web/' . basename($p);
    }
    return $urls;
}

/**
 * Devuelve el modelo listo para pintar, o null si no se puede publicar.
 *
 * Sin renders no hay landing — SALVO que el propio modelo marque `renders_pendientes`
 * a propósito. Decisión del owner (2-sep, pivote a mercado australiano): publicar el
 * catálogo completo de 5 modelos mientras se terminan los renders que faltan ("estamos
 * creándola y no estamos en producción aún"), en vez de esperar a tener los 5 completos.
 * Es una excepción CONSCIENTE por modelo, no un apagado general de la regla: un modelo
 * nuevo que no marque el flag sigue cayendo al catálogo si le faltan imágenes.
 */
function lw_modelo_get($id, array $modelos, $root = null) {
    $id = strtolower(preg_replace('/[^A-Za-z0-9-]/', '', (string) $id));
    if ($id === '' || !isset($modelos[$id])) return null;
    $imgs = lw_modelo_imgs($id, $root);
    $m = $modelos[$id];
    if (!$imgs && empty($m['renders_pendientes'])) return null;
    $m['id']   = $id;
    $m['imgs'] = $imgs;
    return $m;
}

/**
 * "€69,000" · null si no hay precio cerrado (nunca un número plausible).
 * Formato inglés (coma de millar), no español — cazado por Marketing en la capa 1 del
 * deploy del pivote australiano (2-sep): "48.000" con punto se lee como "casi 48" para
 * un angloparlante, no como cuarenta y ocho mil.
 */
function lw_precio_fmt($eur) {
    if ($eur === null || $eur === '' || !is_numeric($eur)) return null;
    return '€' . number_format((float) $eur, 0, '.', ',');
}

function lw_e($s) { return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8'); }

/**
 * Pivote a mercado australiano (2-sep): la página pasa a ser solo inglés. Se mantiene esta
 * función (en vez de tocar los ~40 sitios que la llaman) para que el cambio sea de una
 * línea y reversible por git si se retoma el bilingüe — pero ya no hay dos <span>: solo
 * sale el inglés. $en=null repite $es (para lo que no tiene traducción propia todavía).
 */
function lw_i18n($es, $en = null) {
    return lw_e($en !== null ? $en : $es);
}

/**
 * Precio de un techo ya resuelto al tramo activo (2026 o 2027), decidido SOLO por el
 * reloj del servidor en hora de Bali — ver LW_CORTE_2027 arriba. $techo = ['now'=>int,
 * 'y2027'=>int].
 */
// $hoy es SOLO para test_modelo.php (probar la rama 2027 sin esperar a que llegue el año) —
// index.php/sitemap.php nunca lo pasan, así que en producción siempre es el reloj real del
// servidor. No confundir con un parámetro de request: nadie fuera de un test CLI lo toca.
function lw_antes_del_corte_2027(?DateTime $hoy = null) {
    $corte = new DateTime(LW_CORTE_2027, new DateTimeZone(LW_TZ_BALI));
    $hoy   = $hoy ?? new DateTime('now', new DateTimeZone(LW_TZ_BALI));
    return $hoy < $corte;
}

function lw_techo_precio_activo(array $techo, ?DateTime $hoy = null) {
    return lw_antes_del_corte_2027($hoy) ? $techo['now'] : $techo['y2027'];
}

/** El techo más barato de un modelo, ya resuelto al precio activo — es el "Desde X €"
 * del hero y de la tabla de cross-selling. null si el modelo no tiene techos definidos. */
function lw_modelo_precio_desde(array $m) {
    if (empty($m['techos'])) return null;
    $precios = array_map('lw_techo_precio_activo', $m['techos']);
    return min($precios);
}

/**
 * Tarifa ORIENTATIVA de parcela por m² — decisión de revisión previa (Seguridad +
 * Administración, 2-sep): constantes fijas en servidor, nunca un valor que llegue por
 * request, y NO tocan el inventario real de Supabase (que sigue con su precio fijo por
 * parcela real). Sigue siendo un SUELO orientativo, no una cifra exacta por parcela
 * concreta — nunca se suma al precio de la villa en un único total (un "desde" combinado
 * sin la parcela concreta puede leerse como precio total vinculante, hallazgo de
 * Administración).
 *
 * Corregida y ampliada el mismo 2-sep (misma sesión, mismo owner dando el dato en el chat
 * CEO — misma autoridad que la primera versión): 'playa'/'otras' (200/125) eran una
 * simplificación de arranque; el owner dio después las 4 vistas reales con su tarifa y
 * confirmó Sumba al mismo tramo de 125. 'beachfront' sube de 200 a 250 — la cifra vieja
 * NO se reintroduce en ningún sitio. 'otras' se deja como alias del tramo de 125€ para el
 * resumen de la sección Precio, que no lista las 4 vistas una a una.
 *
 * ⚠️ 3-sep-2026: la frase «nunca se suma al precio de la villa en un único total» que vivía
 * aquí ha sido REVOCADA por el owner de forma expresa, con el hallazgo viejo delante, al
 * pedir el configurador con presupuesto (ver lw_estimacion() justo debajo). Sigue siendo
 * cierto que es un SUELO orientativo por m², no una cifra por parcela concreta: lo que
 * cambia es que ahora sí se compone un total, y el trabajo de que no se lea como
 * vinculante lo hace el ROTULADO del panel, no la ausencia de la suma.
 */
function lw_parcela_tarifa_m2($zona) {
    $tarifas = [
        'cliff'      => 125,
        'ricefield'  => 125,
        'riverfront' => 125,
        'beachfront' => 250,
        'sumba'      => 125,
        'otras'      => 125, // alias de resumen, ver arriba
    ];
    return $tarifas[$zona] ?? null;
}

/**
 * Superficie de parcela que admite el estimador — 3-sep-2026.
 *
 * NO son cifras inventadas ni "tamaños típicos" plausibles: salen de las 121 parcelas
 * **disponibles** del inventario real (Supabase Lawang, tabla `unidades`, tipo='parcela',
 * estado='disponible', consultado el 3-sep-2026): mínimo 150 m², mediana 300 m², máximo
 * 1.528 m². El tope se deja en 1.500 redondo — por encima hay 10 parcelas y son
 * conversación de llamada, no de estimador.
 *
 * Los tres preajustes cubren el grueso real del catálogo: 41 parcelas entre 200-299 m²,
 * 50 entre 300-399 y 27 por encima de 400. Por eso 250/350/500 y no 300/600/900.
 *
 * El PASO de 50 m² no es cosmético (Administración, revisión previa 3-sep): con tarifas de
 * 125 y 250 €/m², cada incremento vale 6.250 € o 12.500 €, así que toda línea de parcela
 * cae en un número redondo POR CONSTRUCCIÓN y es imposible que salga un "€187.437" con
 * pinta de cotización exacta.
 */
define('LW_M2_MIN', 150);
define('LW_M2_MAX', 1500);
define('LW_M2_STEP', 50);
const LW_M2_PRESETS = [250, 350, 500];

/**
 * Normaliza los m² que teclea el visitante. Devuelve int dentro de rango, o null si no hay
 * nada utilizable — NUNCA 0, que en el panel se leería como "el terreno es gratis".
 *
 * Se usa en los DOS lados (PHP para lo que se guarda y se envía a ventas, JS para pintar),
 * porque el POST a booking-notify.php no tiene auth y ahí no vale fiarse de lo que llegue.
 */
function lw_m2_clamp($raw) {
    if (is_string($raw)) $raw = trim($raw);
    if ($raw === '' || $raw === null || !is_numeric($raw)) return null;
    $n = (float) $raw;
    // is_numeric() acepta "1e9" y "-500": el rango es lo único que los para de verdad.
    if (!is_finite($n) || $n <= 0) return null;
    $n = (int) floor($n);
    if ($n < LW_M2_MIN) return LW_M2_MIN;
    if ($n > LW_M2_MAX) return LW_M2_MAX;
    return $n;
}

/**
 * Catálogo ÚNICO de lo que se puede elegir en el configurador (pasos 3-4).
 *
 * Existe para que las mismas claves y tarifas las use quien pinta (index.php), quien
 * valida (api/booking-notify.php) y quien afirma (test_modelo.php). Hasta el 3-sep las
 * cuatro vistas estaban escritas a mano en el HTML con su tarifa al lado — la misma
 * "lista a mano dentro del guardrail" que ya costó una corrección el 2-sep (beachfront
 * 200→250 en dos sitios). El JS nunca ve esta tabla: lee el `data-rate` del elemento que
 * PHP ya renderizó.
 *
 * Nota deliberada: 'bali' NO lleva tarifa propia — la pone la vista. Si algún día la
 * llevara, habría dos fuentes para el mismo número. Hay un assert que lo vigila.
 */
function lw_picker_opciones() {
    return [
        'extras' => [
            'airbnb-kit'  => 'Airbnb kit',
            'sauna'       => 'Sauna',
            'cold-plunge' => 'Cold plunge pool',
        ],
        'island' => [
            'bali'  => ['label' => 'Bali',  'rate' => null],
            'sumba' => ['label' => 'Sumba', 'rate' => lw_parcela_tarifa_m2('sumba')],
        ],
        'view' => [
            'cliff'      => ['label' => 'Cliff',      'rate' => lw_parcela_tarifa_m2('cliff')],
            'ricefield'  => ['label' => 'Ricefield',  'rate' => lw_parcela_tarifa_m2('ricefield')],
            'riverfront' => ['label' => 'Riverfront', 'rate' => lw_parcela_tarifa_m2('riverfront')],
            'beachfront' => ['label' => 'Beachfront', 'rate' => lw_parcela_tarifa_m2('beachfront')],
        ],
    ];
}

/**
 * Tarifa €/m² que aplica a una combinación isla+vista, o null si todavía no hay bastante
 * elegido para saberlo. Sumba tiene tarifa propia y NO usa vista (el catálogo de vistas es
 * de Bali); Bali sin vista elegida todavía no tiene tarifa.
 */
function lw_tarifa_de($isla, $vista) {
    $op = lw_picker_opciones();
    if ($isla === 'sumba') return $op['island']['sumba']['rate'];
    if ($isla === 'bali' && isset($op['view'][$vista])) return $op['view'][$vista]['rate'];
    return null;
}

/**
 * La estimación completa, calculada EN SERVIDOR — 3-sep-2026.
 *
 * Es la única aritmética válida del presupuesto: la pinta index.php al cargar, la recalcula
 * booking-notify.php antes de escribir nada, y test_modelo.php la afirma. El importe que
 * llegue por POST desde el navegador NUNCA se guarda como bueno (el endpoint no tiene auth:
 * cualquiera puede mandar el número que quiera al correo de ventas).
 *
 * ⚠️ El precio del techo es el precio COMPLETO de la villa con ese techo, no un sobrecoste
 * — Sirap 48.000 y Bambú 50.000 en Dali son dos precios de villa, no 48.000 + 2.000. Es el
 * error que cazó Diseño en la revisión previa del 3-sep, y por eso el panel enseña UNA
 * línea de villa, nunca "villa + techo" como dos sumandos.
 *
 * Devuelve null en 'total' mientras falte cualquier ingrediente: nunca un 0, que se leería
 * como "gratis" en vez de como "todavía no se puede calcular".
 */
function lw_estimacion(array $m, $techoKey, $isla, $vista, $m2, ?DateTime $hoy = null) {
    $out = ['villa' => null, 'techo' => null, 'tarifa' => null, 'm2' => null,
            'parcela' => null, 'total' => null, 'tramo' => lw_antes_del_corte_2027($hoy) ? '2026' : '2027'];

    if (!isset($m['techos'][$techoKey])) return $out;
    $out['techo'] = $techoKey;
    $out['villa'] = lw_techo_precio_activo($m['techos'][$techoKey], $hoy);

    $out['tarifa'] = lw_tarifa_de($isla, $vista);
    $out['m2']     = lw_m2_clamp($m2);

    if ($out['tarifa'] !== null && $out['m2'] !== null) {
        $out['parcela'] = $out['tarifa'] * $out['m2'];
    }

    // El total existe con la villa sola (decisión del owner, 3-sep: "total siempre
    // visible"). Lo que impide que una captura a medias mienta NO es esconder la cifra,
    // es que la etiqueta del total diga en ese estado "Villa only — plot not included
    // yet" — ver el panel en index.php.
    $out['total'] = $out['villa'] + ($out['parcela'] ?? 0);
    return $out;
}
