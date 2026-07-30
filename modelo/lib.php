<?php
/**
 * lib.php — resolución de modelo e imágenes para las landings /modelo/<id>.
 * Sin estado ni salida: todo lo que hay aquí se puede probar con `php modelo/test_modelo.php`.
 */

/** Renders publicables de un modelo, en orden natural (dali.jpg antes que dali2.jpg). */
function lw_modelo_imgs($id, $root = null) {
    $root = $root !== null ? $root : dirname(__DIR__);
    $dir  = $root . '/assets/img/buildings/' . $id . '/web';
    $f    = glob($dir . '/*.{jpg,jpeg,png,webp}', GLOB_BRACE);
    if (!$f) return [];
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

/** Los otros modelos que sí tienen landing, para el cross-selling del pie. */
function lw_modelos_publicables(array $modelos, $excluir = '', $root = null) {
    $out = [];
    foreach ($modelos as $id => $m) {
        if ($id === $excluir) continue;
        $imgs = lw_modelo_imgs($id, $root);
        if (!$imgs) continue;
        $m['id']   = $id;
        $m['imgs'] = $imgs;
        $out[$id]  = $m;
    }
    return $out;
}

/** "69.000 €" · null si no hay precio cerrado (nunca un número plausible). */
function lw_precio_fmt($eur) {
    if ($eur === null || $eur === '' || !is_numeric($eur)) return null;
    return number_format((float) $eur, 0, ',', '.') . ' €';
}

function lw_e($s) { return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8'); }
