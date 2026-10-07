<?php
/**
 * /thecollection-v2 — RUTA DE PRUEBA de The Collection leyendo de la intranet (F5b 2-oct-2026; F7 6-oct-2026).
 *
 * Es la misma pagina y la misma SPA que /thecollection (thecollection.php), pero las fichas salen de
 * lw_coleccion('intranet') (RPC coleccion_publica) en vez de data.json, y el SERVIDOR las inyecta en la
 * pagina como window.LW_COLECCION_PRELOAD (con `live` y `stale`): el navegador no pide nada a Supabase
 * (ni a data.json). La fuente la fija ESTE fichero, en servidor: no hay parametro, cookie ni cabecera de
 * la peticion que la cambie, y lo publico (/thecollection, /property/<id>, el sitemap) sigue leyendo
 * LW_COLECCION_FUENTE (datajson). Todo lo nuevo de F7 (chip de estado, «Sold out», bloque Availability)
 * solo se activa cuando el documento es `live`; con datajson la web es la de siempre.
 *
 * Fuera de buscadores: X-Robots-Tag + meta robots noindex + canonical a /thecollection, y no esta en
 * sitemap.php. La URL limpia /thecollection-v2 sale de la regla 2 de .htaccess (como /portfolio); el
 * .php con extension redirige a ella (regla 1). Se retira al cortar (F10a): borrar este fichero y poner
 * LW_COLECCION_FUENTE=intranet.
 * Las fichas se abren con #property/<id> en esta misma URL (LW_COLECCION_V2 en portfolio-app.js): abrir
 * /property/<id> mezclaria la fuente de v1 con la de v2. Un F5 en una ficha vuelve a abrirla desde la v2.
 */
define('LW_COLECCION_V2', true);
header('X-Robots-Tag: noindex, nofollow', true);
header('Cache-Control: no-store');
unset($_GET['property']); // esta ruta es solo el listado
require __DIR__ . '/thecollection.php';
