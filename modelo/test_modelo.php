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

// Solo Dali existe (30-jul): los demas modelos se retiraron del funnel.
$dali = lw_modelo_get('dali', $M);
ok($dali !== null && count($dali['imgs']) >= 5, 'dali debe ser publicable con sus renders');
ok(count($M) === 1, 'el catalogo del funnel es solo Dali');
ok(lw_modelo_get('dune', $M) === null, 'un modelo retirado no puede servir landing');

// El primer render es el del hero: orden natural, dali.webp antes que dali2.webp.
ok(substr($dali['imgs'][0], -8) === 'dali.webp', 'el hero debe ser dali.webp, no dali2.webp');

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

// Las fotos reales del sitio: si faltan, la seccion "La costa, no el render" sale rota.
foreach (['costa', 'rio'] as $f) {
    ok(is_file(dirname(__DIR__) . "/assets/img/lugar/$f.jpg"), "falta la foto real $f.jpg");
}

// El pliego que se publica tiene que estar completo por los dos lados.
ok(!empty($dali['alcance']['incluido']) && !empty($dali['alcance']['no_incluido']),
    'un alcance de obra sin "no incluido" es una reclamacion');

echo $fallos === 0 ? "OK — todo pasa\n" : "$fallos fallo(s)\n";
exit($fallos === 0 ? 0 : 1);
