<?php
/**
 * Comprobacion de ghl.php. Se ejecuta por CLI y no toca la red:
 *   php api/test_ghl.php
 * Solo cubre lo que puede romper en silencio — un telefono mal formado o un modelo fuera
 * del desplegable no dan error en GHL: entran mal y nadie se entera hasta llamar.
 */
// Este fichero vive en el webroot de una landing que paga trafico: sin esto respondia 200
// a cualquiera que pidiera /api/test_ghl.php. El .htaccess raiz tambien lo bloquea por
// patron; el guard viaja con el fichero y sobrevive a un despliegue que se lleve el htaccess.
if (php_sapi_name() !== 'cli') { http_response_code(404); exit; }

require_once __DIR__ . '/ghl.php';

$fallos = 0;
$es = function ($esperado, $obtenido, $que) use (&$fallos) {
    if ($esperado !== $obtenido) {
        $fallos++;
        echo "FALLO  $que: esperaba '$esperado', obtuve '$obtenido'\n";
    }
};

// Telefono -> E.164
$es('+34601170044', lawang_ghl_tel('601 170 044'),    'movil espanol sin prefijo');
$es('+34601170044', lawang_ghl_tel('+34 601 170 044'), 'con prefijo y espacios');
$es('+34601170044', lawang_ghl_tel('0034601170044'),   '00 se convierte en +');
$es('+34601170044', lawang_ghl_tel('601-170-044'),     'guiones');
// Un numero de otro pais con prefijo NO se toca; sin prefijo y sin 9 digitos, tampoco.
$es('+447700900123', lawang_ghl_tel('+44 7700 900123'), 'internacional intacto');
$es('12345', lawang_ghl_tel('12345'), 'basura no se inventa prefijo');

// Modelo -> opcion exacta del desplegable de GHL
$es('Dali', lawang_ghl_modelo('dali'), 'id del catalogo');
$es('Sin definir', lawang_ghl_modelo('villa-x'), 'modelo desconocido cae en Sin definir');
$es('Sin definir', lawang_ghl_modelo(''), 'vacio cae en Sin definir');

$es('+34601170044', lawang_ghl_tel('(+34) 601-170-044'), 'parentesis y guiones juntos');

// Fail-open: sin private/ghl.json no revienta, devuelve false y el lead sigue su camino.
if (!is_file(__DIR__ . '/../private/ghl.json')) {
    $es(false, lawang_ghl_upsert('Ana Perez', 'a@b.com', '600000000', 'dali', 'web', ''),
        'sin credenciales devuelve false sin lanzar');
}

echo $fallos === 0 ? "OK — todas las comprobaciones pasan\n" : "$fallos fallo(s)\n";
exit($fallos === 0 ? 0 : 1);
