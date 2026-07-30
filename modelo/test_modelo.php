<?php
/**
 * Autochequeo de las landings de modelo:  php modelo/test_modelo.php
 * Solo CLI — si alguien lo pide por web devuelve 404, no es una página del sitio.
 */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

require __DIR__ . '/lib.php';
$M = require __DIR__ . '/modelos.php';

$fallos = 0;
function ok($cond, $msg) {
    global $fallos;
    if (!$cond) { $fallos++; echo "FALLO: $msg\n"; }
}

// Un modelo con renders se publica; uno sin ellos, no (hoy: Dune/Trinity/Temple).
$dali = lw_modelo_get('dali', $M);
ok($dali !== null && count($dali['imgs']) >= 5, 'dali debe ser publicable con sus renders');
ok(lw_modelo_get('dune', $M) === null, 'dune no tiene renders: no puede servir landing');

// El primer render es el del hero: orden natural, dali.jpg antes que dali2.jpg.
ok(substr($dali['imgs'][0], -8) === 'dali.jpg', 'el hero debe ser dali.jpg, no dali2.jpg');

// La id viene de la URL: nada de rutas ni comodines llegando al glob.
ok(lw_modelo_get('../../etc/passwd', $M) === null, 'path traversal debe caer');
ok(lw_modelo_get('dali/../dream', $M) === null, 'barras en la id deben caer');
ok(lw_modelo_get('', $M) === null, 'id vacia debe caer');
ok(lw_modelo_get('DALI', $M) !== null, 'la id no distingue mayusculas');

// Precio: sin número cerrado no se pinta nada. Un 0 tampoco es un precio de venta.
ok(lw_precio_fmt(null) === null, 'sin precio no se formatea nada');
ok(lw_precio_fmt('') === null, 'cadena vacia no es precio');
ok(lw_precio_fmt(69000) === '69.000 €', 'formato español de miles');
foreach ($M as $id => $m) {
    ok($m['precio_desde_eur'] === null || is_numeric($m['precio_desde_eur']),
        "precio de $id debe ser null o numero");
}

// Cross-selling: nunca se enlaza a sí mismo ni a una landing que redirige.
$otros = lw_modelos_publicables($M, 'dali');
ok(!isset($otros['dali']), 'el cross-selling no se enlaza a si mismo');
ok(!isset($otros['dune']), 'el cross-selling no enlaza modelos sin renders');
foreach ($otros as $id => $o) { ok(!empty($o['imgs']), "$id en cross-selling sin imagenes"); }

echo $fallos === 0 ? "OK — todo pasa\n" : "$fallos fallo(s)\n";
exit($fallos === 0 ? 0 : 1);
