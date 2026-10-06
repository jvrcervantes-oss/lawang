<?php
/**
 * api/coleccion.php — The Collection para quien no es la SPA de /thecollection. F7, 6-oct-2026.
 *
 * LLAMADOR (uno, con nombre): index.html (la home), que pinta las tarjetas del escaparate y la ficha
 * destacada. Antes lo leia de data.json directamente, que ademas es un fichero publico con las 44 fichas
 * (ocultas incluidas). Aqui sale lw_coleccion() — la UNICA lectura — y su lista blanca.
 * La SPA de /thecollection no lo usa: recibe el mismo documento inyectado por el servidor.
 *
 * Solo GET, sin parametros: la fuente la fija el servidor (LW_COLECCION_FUENTE), nunca la peticion.
 * Con datajson sale lo mismo que la home leia antes; tras el corte de F10a sale la intranet, con
 * `live` y `stale` para que la tarjeta pinte «sin dato» y no «disponible» si el origen esta caido.
 * Sin cache (CDN incluido): el estado de unidades es tiempo casi real.
 */
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    http_response_code(405);
    header('Allow: GET');
    exit;
}
require __DIR__ . '/../coleccion/lib.php';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Robots-Tag: noindex');
header('X-Content-Type-Options: nosniff');
echo json_encode(lw_coleccion_para_navegador(lw_coleccion()), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP);
