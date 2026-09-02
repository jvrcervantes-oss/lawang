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

/** "69.000 €" · null si no hay precio cerrado (nunca un número plausible). */
function lw_precio_fmt($eur) {
    if ($eur === null || $eur === '' || !is_numeric($eur)) return null;
    return number_format((float) $eur, 0, ',', '.') . ' €';
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
function lw_techo_precio_activo(array $techo) {
    $corte = new DateTime(LW_CORTE_2027, new DateTimeZone(LW_TZ_BALI));
    $hoy   = new DateTime('now', new DateTimeZone(LW_TZ_BALI));
    return $hoy >= $corte ? $techo['y2027'] : $techo['now'];
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
 * Administración, 2-sep): son dos constantes fijas, nunca un valor que llegue por
 * request, y NO tocan el inventario real de Supabase (que sigue con su precio fijo por
 * parcela real). 'playa' es una cifra cerrada; 'otras' es un SUELO ("desde"), así que
 * cualquier total que se calcule con ella se rotula igual como "desde", nunca como cifra
 * exacta — mismo motivo por el que esto vive aparte del precio de la villa, nunca sumado
 * en un único total: un "desde" combinado sin la parcela concreta puede leerse como precio
 * total vinculante (hallazgo de Administración).
 */
function lw_parcela_tarifa_m2($zona) {
    $tarifas = ['playa' => 200, 'otras' => 125];
    return $tarifas[$zona] ?? null;
}
