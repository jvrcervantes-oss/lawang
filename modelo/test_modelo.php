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

// 2-sep: pivote a mercado australiano, catálogo completo de 5 modelos.
ok(count($M) === 5, 'el catálogo son los 5 modelos reales');
foreach (['dali', 'dune', 'dream', 'trinity', 'temple'] as $id) {
    ok(isset($M[$id]), "falta el modelo $id en el catálogo");
}

// Dali/Dune/Dream tienen renders reales en assets/img/buildings/<id>/web/.
foreach (['dali' => 'dali', 'dune' => 'dune', 'dream' => 'dream'] as $id => $stem) {
    $mm = lw_modelo_get($id, $M);
    ok($mm !== null && count($mm['imgs']) >= 5, "$id debe ser publicable con sus renders");
    // El primer render es el del hero: orden natural, <id>.webp antes que <id>2.webp.
    ok(substr($mm['imgs'][0], -(strlen($stem) + 5)) === $stem . '.webp',
        "el hero de $id debe ser $stem.webp, no {$stem}2.webp");
}

// Trinity/Temple: publicados SIN render por decisión expresa del owner (2-sep), pero solo
// porque marcan `renders_pendientes` a propósito — no porque la regla se haya apagado.
foreach (['trinity', 'temple'] as $id) {
    $mm = lw_modelo_get($id, $M);
    ok($mm !== null, "$id debe publicarse igual (renders_pendientes)");
    ok($mm['imgs'] === [], "$id no tiene renders todavía, la lista debe salir vacía");
    ok(!empty($M[$id]['renders_pendientes']), "$id debe marcar renders_pendientes explícitamente");
}

// Un modelo NUEVO que no marque el flag sigue cayendo al catálogo si no tiene imágenes —
// la excepción es por modelo, no un apagado general de la regla.
$sinFlag = $M;
$sinFlag['fantasma'] = ['nombre' => 'Fantasma', 'dormitorios' => 1, 'banos' => 1,
    'villa_m2' => 1, 'terraza_m2' => 1, 'techos' => ['sirap' => ['nombre' => 'x', 'now' => 1, 'y2027' => 1], 'bambu' => ['nombre' => 'y', 'now' => 1, 'y2027' => 1]]];
ok(lw_modelo_get('fantasma', $sinFlag) === null, 'sin renders_pendientes, un modelo sin fotos sigue sin publicarse');

// La id viene de la URL: nada de rutas ni comodines llegando al glob.
ok(lw_modelo_get('../../etc/passwd', $M) === null, 'path traversal debe caer');
ok(lw_modelo_get('dali/../dream', $M) === null, 'barras en la id deben caer');
ok(lw_modelo_get('', $M) === null, 'id vacia debe caer');
ok(lw_modelo_get('DALI', $M) !== null, 'la id no distingue mayusculas');

// Precio: sin número cerrado no se pinta nada. Un 0 tampoco es un precio de venta.
ok(lw_precio_fmt(null) === null, 'sin precio no se formatea nada');
ok(lw_precio_fmt('') === null, 'cadena vacia no es precio');
ok(lw_precio_fmt(69000) === '69.000 €', 'formato español de miles');

// Techos: los 5 modelos llevan Sirap y Bambú, con precio 'now'/'y2027' numérico, y Sirap
// siempre por debajo de Bambú (si dejara de serlo, "Desde" tomaría el precio equivocado
// como protagonista — es la asunción que usa lw_modelo_precio_desde()).
foreach ($M as $id => $mm) {
    foreach (['sirap', 'bambu'] as $tk) {
        ok(isset($mm['techos'][$tk]), "$id debe tener techo $tk");
        ok(is_numeric($mm['techos'][$tk]['now']) && is_numeric($mm['techos'][$tk]['y2027']),
            "$id/$tk debe tener precio 'now' y 'y2027' numéricos");
        ok($mm['techos'][$tk]['y2027'] >= $mm['techos'][$tk]['now'],
            "$id/$tk: el precio de 2027 no debería bajar respecto a hoy");
    }
    ok($mm['techos']['sirap']['now'] <= $mm['techos']['bambu']['now'],
        "$id: Sirap debe seguir siendo el techo más barato (o lw_modelo_precio_desde apunta al equivocado)");
}

// El corte de precio se decide con el reloj de Bali, nunca con un valor que pase el
// llamador — antes de 2027 debe devolver 'now', en/después de 2027 debe devolver 'y2027'.
ok(lw_techo_precio_activo(['now' => 100, 'y2027' => 200]) === 100,
    'hoy (2026) el precio activo debe ser el de "now"');

// Tarifa de parcela: dos constantes fijas, nunca null salvo zona desconocida.
ok(lw_parcela_tarifa_m2('playa') === 200, 'tarifa de playa debe ser 200€/m²');
ok(lw_parcela_tarifa_m2('otras') === 125, 'tarifa de otras ubicaciones debe ser 125€/m² (suelo)');
ok(lw_parcela_tarifa_m2('luna') === null, 'una zona desconocida no debe devolver una tarifa inventada');

// Las fotos reales del sitio: si faltan, la seccion "La costa, no el render" sale rota.
foreach (['costa', 'rio'] as $f) {
    ok(is_file(dirname(__DIR__) . "/assets/img/lugar/$f.jpg"), "falta la foto real $f.jpg");
}

// El pliego que se publica tiene que estar completo por los dos lados (solo Dali lo tiene
// verificado hoy — los otros 4 se quedan sin `alcance` a propósito, ver modelos.php).
ok(!empty($M['dali']['alcance']['incluido']) && !empty($M['dali']['alcance']['no_incluido']),
    'un alcance de obra sin "no incluido" es una reclamacion');
foreach (['dune', 'dream', 'trinity', 'temple'] as $id) {
    ok(empty($M[$id]['alcance']),
        "$id no tiene anexo de obra verificado: no debe llevar 'alcance' inventado de Dali");
}

// Pivote a solo-inglés (2-sep): lw_i18n ya no emite los dos <span>, solo el inglés.
ok(lw_i18n('Hola', 'Hi') === 'Hi', 'lw_i18n debe pintar solo el inglés cuando se da');
ok(lw_i18n('Hola') === 'Hola', 'sin EN explícito, lw_i18n cae al primer argumento');
ok(strpos(lw_i18n('x', '<b>y</b>'), '&lt;b&gt;') !== false, 'lw_i18n debe escapar el HTML');

echo $fallos === 0 ? "OK — todo pasa\n" : "$fallos fallo(s)\n";
exit($fallos === 0 ? 0 : 1);
