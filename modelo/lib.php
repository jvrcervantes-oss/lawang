<?php
/**
 * lib.php — resolución de modelo e imágenes para las landings /modelo/<id>.
 * Sin estado ni salida: todo lo que hay aquí se puede probar con `php modelo/test_modelo.php`.
 */

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
 * Sin renders no hay landing: una página de venta sin una sola imagen del producto
 * hace más daño que un 404, y a Dune/Trinity/Temple les pasa hoy.
 */
function lw_modelo_get($id, array $modelos, $root = null) {
    $id = strtolower(preg_replace('/[^A-Za-z0-9-]/', '', (string) $id));
    if ($id === '' || !isset($modelos[$id])) return null;
    $imgs = lw_modelo_imgs($id, $root);
    if (!$imgs) return null;
    $m = $modelos[$id];
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
 * Par ES/EN como dos <span> hermanos: el CSS (html[data-lang]) esconde el que no toca y el
 * toggle de idioma solo cambia un atributo, sin reconstruir texto por JS. $en=null repite el
 * ES (para lo que no cambia entre idiomas, p.ej. un nombre propio).
 */
function lw_i18n($es, $en = null) {
    if ($en === null) $en = $es;
    return '<span class="i-es">' . lw_e($es) . '</span><span class="i-en">' . lw_e($en) . '</span>';
}
