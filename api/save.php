<?php
require_once 'config.php';
require_once dirname(__DIR__) . '/coleccion/lib.php'; // lw_coleccion_forma_invalida(): qué es un catálogo que se puede guardar
session_start();
lawang_require_same_origin();  // el 401 de abajo mira la sesion; esto mira DE DONDE viene la peticion
header('Content-Type: application/json');
header('Cache-Control: no-store');

if (!($_SESSION['lawang_auth'] ?? false)) {
    http_response_code(401);
    echo json_encode(['ok' => false, 'error' => 'Unauthorized']);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'Method not allowed']);
    exit;
}

$body = file_get_contents('php://input');
$data = json_decode($body, true);

if ($data === null) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'Invalid JSON']);
    exit;
}

// JSON valido no es un catalogo (14-oct-2026). Lo que se guarda aqui SUSTITUYE el catalogo entero de la web, y
// hasta hoy solo se rechazaba lo que no decodificaba: `[]`, un numero o un objeto sin `properties` se escribian
// tal cual y dejaban la web sin fichas. La sesion no lo cubre: quien tiene el navegador manda lo que quiere
// (un panel con una carga a medias, un script, publicar_data.py con un fichero equivocado). Se valida la FORMA
// de lo mismo que se escribe ($data) y ANTES de tocar el disco. El 422 dice que ficha y que regla, por su
// posicion; nunca devuelve contenido. La regla y sus casos: lw_coleccion_forma_invalida en coleccion/lib.php,
// probada en coleccion/tests/coleccion_test.php (que ademas ejecuta este fichero entero).
$forma = lw_coleccion_forma_invalida($data);
if ($forma !== null) {
    http_response_code(422);
    echo json_encode(['ok' => false, 'error' => 'Invalid catalogue: ' . $forma]);
    exit;
}

$json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
$tmp  = DATA_FILE . '.tmp';

// `$json === false` (no se pudo codificar) escribiria un fichero VACIO, y un rename que falla dejaba el catalogo
// viejo mientras se respondia «ok»: en los dos casos el panel decia «publicado» sin serlo. Ahora dan 500.
if ($json === false || file_put_contents($tmp, $json) === false || !rename($tmp, DATA_FILE)) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'Could not write file']);
    exit;
}

echo json_encode(['ok' => true]);
