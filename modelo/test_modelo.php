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
ok(lw_precio_fmt(69000) === '€69,000', 'formato inglés de miles (coma), no español — pivote australiano');

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
// llamador en produccion — antes de 2027 debe devolver 'now', en/después de 2027 debe
// devolver 'y2027'. El $hoy opcional SOLO existe para poder probar aquí la rama 2027 sin
// esperar a que llegue el año (index.php/sitemap.php nunca lo pasan).
ok(lw_techo_precio_activo(['now' => 100, 'y2027' => 200]) === 100,
    'hoy (2026) el precio activo debe ser el de "now"');
$tz = new DateTimeZone(LW_TZ_BALI);
ok(lw_techo_precio_activo(['now' => 100, 'y2027' => 200], new DateTime('2026-12-31 23:59:59', $tz)) === 100,
    'un segundo antes del corte sigue siendo el precio de "now"');
ok(lw_techo_precio_activo(['now' => 100, 'y2027' => 200], new DateTime('2027-01-01 00:00:00', $tz)) === 200,
    'justo en el corte ya debe ser el precio de "y2027"');
ok(lw_techo_precio_activo(['now' => 100, 'y2027' => 200], new DateTime('2027-06-01', $tz)) === 200,
    'bien pasado el corte sigue siendo el precio de "y2027"');
ok(lw_antes_del_corte_2027(new DateTime('2026-06-01', $tz)) === true, 'lw_antes_del_corte_2027: antes del corte es true');
ok(lw_antes_del_corte_2027(new DateTime('2027-06-01', $tz)) === false, 'lw_antes_del_corte_2027: despues del corte es false');

// Tarifa de parcela: dos constantes fijas, nunca null salvo zona desconocida.
// 2-sep, corregidas y ampliadas en la misma sesion (el owner subio beachfront de 200 a
// 250 y dio las 4 vistas + Sumba): la cifra vieja de 200 NO debe reaparecer en ningun sitio.
ok(lw_parcela_tarifa_m2('beachfront') === 250, 'tarifa de beachfront debe ser 250€/m² (corregida, no 200)');
foreach (['cliff', 'ricefield', 'riverfront', 'sumba', 'otras'] as $zona) {
    ok(lw_parcela_tarifa_m2($zona) === 125, "tarifa de $zona debe ser 125€/m²");
}
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

// ── Configurador con presupuesto (3-sep) ────────────────────────────────────────────
$OP = lw_picker_opciones();

// Catálogo del picker: una sola fuente. Cada tarifa que sale por aquí tiene que coincidir
// con lw_parcela_tarifa_m2() — es el test que impide que una cifra vieja (el beachfront de
// 200, corregido el 2-sep) reaparezca por una tercera vía.
ok(array_keys($OP['view']) === ['cliff', 'ricefield', 'riverfront', 'beachfront'],
    'las 4 vistas del picker, en orden y sin colarse ninguna');
foreach ($OP['view'] as $k => $o) {
    ok($o['rate'] === lw_parcela_tarifa_m2($k), "la tarifa de $k debe salir de lw_parcela_tarifa_m2, no de una copia");
}
ok($OP['island']['sumba']['rate'] === 125, 'Sumba debe llevar SU tarifa en el propio botón de isla');
// Bali no lleva tarifa a propósito: la pone la vista. Si alguien se la pone, hay dos
// fuentes para el mismo número y vuelve el fallo de las dos copias.
ok($OP['island']['bali']['rate'] === null, 'Bali NO debe tener tarifa propia: la da la vista');
ok(array_keys($OP['extras']) === ['airbnb-kit', 'sauna', 'cold-plunge'], 'los 3 extras del catálogo');

// Tarifa resuelta por combinación isla+vista.
ok(lw_tarifa_de('sumba', null) === 125, 'Sumba tiene tarifa sin necesitar vista');
ok(lw_tarifa_de('sumba', 'beachfront') === 125, 'la vista no manda en Sumba: el catálogo de vistas es de Bali');
ok(lw_tarifa_de('bali', null) === null, 'Bali sin vista elegida todavía no tiene tarifa');
ok(lw_tarifa_de('bali', 'beachfront') === 250, 'Bali beachfront = 250€/m²');
ok(lw_tarifa_de('bali', 'luna') === null, 'una vista inventada no debe caer a 125 por defecto');
ok(lw_tarifa_de(null, null) === null, 'sin isla no hay tarifa');

// m²: el clamp es lo único que para "1e9" y los negativos (is_numeric los acepta), y nunca
// devuelve 0 — un cero en el panel se leería como "el terreno es gratis".
ok(LW_M2_MIN < LW_M2_MAX && LW_M2_MIN > 0, 'el rango de m² debe ser positivo y creciente');
ok(lw_m2_clamp('1e9') === LW_M2_MAX, '1e9 debe toparse al máximo, no colarse');
ok(lw_m2_clamp('-500') === null, 'un negativo no es una superficie');
ok(lw_m2_clamp('0') === null, 'cero no es una superficie');
ok(lw_m2_clamp('') === null, 'vacío no es una superficie');
ok(lw_m2_clamp('abc') === null, 'texto no es una superficie');
ok(lw_m2_clamp(null) === null, 'null no es una superficie');
ok(lw_m2_clamp(' 350 ') === 350, 'los espacios alrededor no invalidan el número');
ok(lw_m2_clamp('10') === LW_M2_MIN, 'por debajo del mínimo se topa al mínimo');
ok(lw_m2_clamp((string) LW_M2_MAX) === LW_M2_MAX, 'el máximo exacto es válido');

// El PASO se aplica de verdad, no solo como atributo del <input> (capa 1 de deploy,
// Seguridad): durante unas horas ?plot=337 daba una parcela de 42.125€ y un total de
// 90.125€, o sea justo la cifra con pinta de cotización exacta que el comentario de
// lib.php juraba imposible por construcción — y encima compartible por URL.
ok(LW_M2_STEP > 0 && LW_M2_MIN % LW_M2_STEP === 0 && LW_M2_MAX % LW_M2_STEP === 0,
    'mínimo y máximo deben caer en el paso, o el propio rango produce cifras fuera de paso');
ok(lw_m2_clamp('337') === 350, '337 m² debe ajustarse al paso de 50, no colarse tal cual');
ok(lw_m2_clamp('301') === 300, 'el ajuste al paso es al más cercano');
ok(lw_m2_clamp('300.7') === 300, 'decimal + paso: 300.7 cae en 300, nunca en 300.7');
foreach (['337', '1', '99999', '412.9'] as $raw) {
    $v = lw_m2_clamp($raw);
    ok($v !== null && $v % LW_M2_STEP === 0, "lw_m2_clamp('$raw') debe caer siempre en el paso, salió " . var_export($v, true));
}

// Los preajustes tienen que caer DENTRO del rango y EN el paso, o la interfaz ofrece un
// botón que el propio clamp corrige a espaldas del visitante.
foreach (LW_M2_PRESETS as $p) {
    ok($p >= LW_M2_MIN && $p <= LW_M2_MAX, "el preajuste de $p m² debe estar dentro del rango del estimador");
    ok($p % LW_M2_STEP === 0, "el preajuste de $p m² debe caer en el paso de " . LW_M2_STEP);
    ok(lw_m2_clamp((string) $p) === $p, "el preajuste de $p m² debe sobrevivir intacto al clamp");
}

// Identidad de techos: es lo que sostiene que la selección se mantenga POR CLAVE al cambiar
// de modelo. Los nombres visibles SÍ difieren entre modelos (Dali "Sirap Ulin" vs Dune
// "Sirap") — por eso no se puede keyear por nombre.
foreach ($M as $id => $mm) {
    ok(count($mm['techos']) === 2, "$id debe tener exactamente 2 techos, ni uno más");
    ok(array_key_exists('sirap', $mm['techos']) && array_key_exists('bambu', $mm['techos']),
        "$id debe usar las claves 'sirap'/'bambu': la selección del configurador se mantiene por clave");
    // El invariante que ata el "From" del hero con el precio numérico del panel.
    ok(lw_modelo_precio_desde($mm) === min(lw_techo_precio_activo($mm['techos']['sirap']),
                                            lw_techo_precio_activo($mm['techos']['bambu'])),
        "$id: el 'From' del hero debe ser el mínimo de los dos techos activos");
}
ok($M['dali']['techos']['sirap']['nombre'] !== $M['dune']['techos']['sirap']['nombre'],
    'los nombres de techo difieren entre modelos: por eso el configurador keyea por clave y no por nombre');

// Aritmética del presupuesto. El precio del techo es el precio COMPLETO de la villa con ese
// techo, NO un sobrecoste: 48.000 y 50.000 son dos precios de villa de Dali.
$e = lw_estimacion($M['dali'], 'sirap', 'bali', 'ricefield', 350);
ok($e['villa'] === 48000, 'Dali/Sirap: la villa son 48.000, el precio completo con ese techo');
ok($e['parcela'] === 350 * 125, 'la parcela es tarifa × m², sin más');
ok($e['total'] === 48000 + 350 * 125, 'el total es villa + parcela, y nada más');
ok($e['tramo'] === '2026', 'hoy el tramo activo es 2026');

$e2 = lw_estimacion($M['dali'], 'bambu', 'bali', 'ricefield', 350);
ok($e2['villa'] === 50000, 'Dali/Bambú son 50.000 de villa, no 48.000 + 2.000');

// Sin ingredientes NO hay línea de parcela — pero el total con la villa sola SÍ existe
// (decisión del owner del 3-sep: total siempre visible). Lo que impide que engañe es la
// etiqueta del panel, no esconder la cifra.
$e3 = lw_estimacion($M['dali'], 'sirap', null, null, null);
ok($e3['parcela'] === null, 'sin isla ni m² no hay subtotal de parcela (nunca 0)');
ok($e3['total'] === 48000, 'con la villa sola el total es la villa');
$e4 = lw_estimacion($M['dali'], 'sirap', 'bali', 'ricefield', null);
ok($e4['parcela'] === null, 'con tarifa pero sin m² tampoco hay subtotal');
$e5 = lw_estimacion($M['dali'], 'sirap', 'bali', null, 350);
ok($e5['parcela'] === null, 'con m² pero sin vista en Bali tampoco hay subtotal');
$e6 = lw_estimacion($M['dali'], 'inventado', 'bali', 'cliff', 350);
ok($e6['villa'] === null && $e6['total'] === null, 'un techo fuera de catálogo no produce cifra ninguna');
// m² hostil: el clamp actúa DENTRO de la estimación, no solo en la interfaz.
$e7 = lw_estimacion($M['dali'], 'sirap', 'sumba', null, '1e9');
ok($e7['m2'] === LW_M2_MAX, 'un m² absurdo se topa dentro de la propia estimación');
ok($e7['parcela'] === LW_M2_MAX * 125, 'Sumba estima con su tarifa aunque no haya vista');

// La rama 2027 se prueba inyectando $hoy, igual que arriba: el presupuesto tiene que subir
// solo el día del corte, sin que nadie toque un flag.
$tz2 = new DateTimeZone(LW_TZ_BALI);
$e27 = lw_estimacion($M['dali'], 'sirap', 'bali', 'ricefield', 350, new DateTime('2027-06-01', $tz2));
ok($e27['villa'] === 52000, 'pasado el corte, la villa de la estimación es la de 2027');
ok($e27['total'] === 52000 + 350 * 125, 'el total de 2027 usa el precio de 2027');
ok($e27['tramo'] === '2027', 'el tramo se registra explícito, no se deduce del timestamp');
ok($e27['parcela'] === $e['parcela'], 'la tarifa de parcela NO cambia con el corte de 2027');

// Pivote a solo-inglés (2-sep): lw_i18n ya no emite los dos <span>, solo el inglés.
ok(lw_i18n('Hola', 'Hi') === 'Hi', 'lw_i18n debe pintar solo el inglés cuando se da');
ok(lw_i18n('Hola') === 'Hola', 'sin EN explícito, lw_i18n cae al primer argumento');
ok(strpos(lw_i18n('x', '<b>y</b>'), '&lt;b&gt;') !== false, 'lw_i18n debe escapar el HTML');

echo $fallos === 0 ? "OK — todo pasa\n" : "$fallos fallo(s)\n";
exit($fallos === 0 ? 0 : 1);
