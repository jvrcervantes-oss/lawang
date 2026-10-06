<?php
/**
 * /thecollection-v2 — RUTA DE PRUEBA de The Collection leyendo de la intranet (F5b, 2-oct-2026).
 *
 * Es la misma página y la misma SPA que /thecollection (thecollection.php), pero las fichas salen de
 * lw_coleccion('intranet') (RPC coleccion_publica) en vez de data.json, inyectadas en la página como
 * window.LW_COLECCION_PRELOAD. La fuente la fija ESTE fichero, en servidor: no hay parámetro, cookie
 * ni cabecera de la petición que la cambie, y lo público (/thecollection, /property/<id>, el sitemap)
 * sigue leyendo LW_COLECCION_FUENTE (datajson). Nada de lo que muestra no está ya publicado: son las
 * mismas fichas visibles, filtradas por la misma lista blanca.
 *
 * Fuera de buscadores: X-Robots-Tag + meta robots noindex + canonical a /thecollection, y no está en
 * sitemap.php. La URL limpia /thecollection-v2 sale de la regla 2 de .htaccess (como /portfolio); el
 * .php con extensión redirige a ella (regla 1). Se retira al cortar F5b: borrar este fichero.
 * Limitación conocida: abrir una ficha desde aquí navega a /property/<id>, que sigue en datajson.
 */
define('LW_COLECCION_V2', true);
header('X-Robots-Tag: noindex, nofollow', true);
header('Cache-Control: no-store');
unset($_GET['property']); // esta ruta es solo el listado
require __DIR__ . '/thecollection.php';
