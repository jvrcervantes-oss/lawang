<?php
/**
 * Landing de modelo de villa — /modelo/<id> (regla de reescritura en .htaccess).
 *
 * ── 11-sep-2026: estas fichas ya NO agendan llamadas ──────────────────────────────────
 * Encargo del owner: la landing de publicidad pasa a ser /palmfield y /dali se convierte
 * en ficha de producto; estas fichas dejan de pedir cita. Se quita el widget de Calendly,
 * el selector de dia, su columna lateral y el aviso a /api/booking-notify.php.
 *
 * ⚠️ NO se deja la pagina sin punto de conversion, y el motivo es medible: /modelo/dali es
 * el destino documentado de la campana ES `es_ticket` (tres creatividades con UTM, ver
 * Marketing/anuncios_es_manual.md). Borrar el agendado a secas dejaria esos anuncios
 * apuntando a una pagina desde la que nadie puede contactar. En su lugar la conversion es
 * WhatsApp, que ya estaba en la pagina como canal secundario y ahora es el principal.
 *
 * Consecuencias para el pixel, explicitas para que nadie las lea como un descuido:
 *   · `Lead` desaparece. Colgaba del `postMessage` de Calendly, que era el unico sitio
 *     donde constaba una cita de verdad. Un clic en WhatsApp no es un lead.
 *   · `AbrioCalendario` desaparece: ya no hay calendario que abrir.
 *   · `ViewContent` se mantiene.
 * Si se quiere volver a medir conversion aqui, el camino es CTWA (clic a WhatsApp con
 * atribucion de Meta), no reetiquetar un clic como Lead.
 *
 * ── 1-sep-2026 · QUINTA versión, sustituye por completo a la anterior ──────────────
 * Diseño importado tal cual desde Claude Design (proyecto "Landings Lawang Bali",
 * archivo "Villa Dali Landing.dc.html") y traducido a este stack (PHP + CSS + JS
 * vainilla: el sitio no corre React ni el runtime de Claude Design en producción).
 * Decisión del owner, confirmada explícitamente antes de tocar código: implementar el
 * diseño TAL CUAL, incluida su mecánica de reserva por Calendly.
 *
 * ⚠️ CAMBIO DE FONDO frente a la versión anterior (dossier de inversión, `b4b7ea0`):
 * desaparece el <form> propio (nombre/email/teléfono/presupuesto + checkbox RGPD que
 * mandaba a /api/lead.php y de ahí al CRM de GoHighLevel). La reserva ahora se hace
 * en Calendly (enlace externo, mismo para el CTA principal y el widget lateral). Eso
 * significa que:
 *   · La captación de datos del lead pasa a hacerla Calendly, fuera del CRM propio.
 *   · No hay checkbox de consentimiento propio ni segmentación por presupuesto.
 *   · `InitiateCheckout` y `Lead` de Meta YA NO se disparan (no hay campos que enfocar
 *     ni envío que confirmar en esta página). Se mantiene `ViewContent` al cargar, y
 *     se añade un evento propio `AbrioCalendario` (no estándar, sin `value`) al pulsar
 *     cualquiera de los dos botones que llevan a Calendly — mismo criterio que la
 *     versión anterior ya aplicaba a su botón de calendario GHL: es un clic, no una
 *     cita confirmada, así que no se etiqueta como `Schedule` ni lleva importe.
 * Si el owner quiere recuperar el alta directa en el CRM, hay que reabrir esta
 * decisión con Datos (webhook de Calendly → GHL) o volver a montar un formulario propio.
 *
 * LO QUE SE MANTIENE DEL DISEÑO IMPORTADO, SIN CAMBIOS DE FONDO:
 *   · Estructura y contenido de las 8 secciones (hero, ficha rápida, sobre el modelo,
 *     galería, acabados, alcance de obra, ubicación, proceso, precio, FAQ, reserva).
 *   · El texto de la FAQ ya venía escrito sin "freehold" ni lenguaje de estructura
 *     nominee — coincide en sustancia con lo que Legal aprobó el 30-jul. Aun así se usa
 *     aquí la redacción ES ya aprobada por Legal (la de la versión anterior), no la
 *     paráfrasis del archivo importado, para no reabrir esa revisión sin necesidad.
 *   · Paleta, tipografía (Space Grotesk + General Sans) y layout con la columna del
 *     calendario fija en escritorio: tal cual el archivo .dc.html.
 *
 * LO QUE SE CORRIGE AL IMPLEMENTAR (no es interpretación libre, es un defecto medible):
 *   · Varios textos secundarios del diseño usaban opacity:.5–.68 sobre el papel, lo que
 *     baja de 4,5:1 (falla WCAG AA — y PRODUCT.md de este proyecto exige "AA minimum"
 *     explícitamente). Aquí el texto secundario es un color sólido rgba(46,52,55,.74),
 *     medido en 4,9:1. Ver --ink2 más abajo.
 *   · La fila de "Stats" (+5 años en Indonesia, +200 propiedades, +100 terrenos, +50
 *     obras) NO tiene ninguna fuente en el repo — no aparece en index.html, en ninguna
 *     ficha de proyecto ni en contexto/. Son cifras inventadas del mockup. Se omite la
 *     sección entera en vez de publicarlas: "nada con placeholders sale del estudio".
 *     Pendiente registrado en contexto/pendientes.md para que el owner las confirme.
 *   · brand = "Lawang Tropical Properties" (el de verdad, el de index.html/logo), no
 *     "Lawang Estate" que traía el mockup por defecto ni el que usaba la v4 anterior.
 *   · Teléfono y email del pie/reserva son los reales del sitio (WhatsApp
 *     +62 811-3831-9862, sales@lawangproperties.com), no los "+62 812 0000 0000" /
 *     "hola@lawangproperties.com" de relleno del mockup.
 *
 * LO QUE NO SE TOCA AUNQUE CAMBIE EL DISEÑO:
 *   · Sin precio cerrado: no se enseña cifra y la página se marca `noindex` sola.
 *   · Sin renders: no hay landing, se redirige al catálogo (lw_modelo_get).
 *   · Acabados y alcance de obra vienen de modelos.php (fuente única, ahora bilingüe
 *     ES/EN): ver `_en` en cada entrada.
 *
 * ── 1-sep-2026 (mismo día, tres rondas más, pedidas directamente por el owner) ──────
 *   · Precio real (69.000 €, dado por el owner en la propia sesión) sustituye a
 *     `null` en modelos.php. Quita el `noindex`.
 *   · Se retira la mención a "Calendly" del texto visible (botones, nota del
 *     calendario) — sigue siendo el mecanismo real por dentro, solo cambia el copy.
 *   · `--panel` sube de contraste (era casi indistinguible de `--papel`) y el precio
 *     del hero pasa de texto en color a insignia sólida.
 *   · **Integración total del widget de Calendly** (ya no un enlace que abre
 *     calendly.com en pestaña nueva): `calendly-inline-widget` real incrustado en la
 *     columna lateral, con `widget.js`/`widget.css` oficiales de Calendly. Esto
 *     REACTIVA `Lead` (arriba decía que ya no se disparaba — dejó de ser cierto):
 *     al completar una reserva sin salir de la página, Calendly manda
 *     `postMessage({event:'calendly.event_scheduled'})` al propio iframe, y eso
 *     dispara `Lead` de verdad, no en el clic. Relevante para LAW-113 (adset pausado
 *     que optimizaba sobre `Lead`): el nombre del evento vuelve a coincidir.
 *     LAW-111 (nadie del equipo se entera de la reserva) SIGUE abierto: esto mejora
 *     el píxel, no añade CRM ni aviso al equipo.
 */
require __DIR__ . '/datos.php';
$MODELOS = require __DIR__ . '/modelos.php';

$m = lw_modelo_get(isset($_GET['m']) ? $_GET['m'] : '', $MODELOS);
if (!$m) {
    header('Location: /thecollection', true, 302);
    exit;
}

// Sin renders todavía (Trinity/Temple, 2-sep): decisión consciente del owner de publicar
// igual — ver el porqué en lw_modelo_get(), lib.php. La plantilla salta las secciones que
// dependen de una foto real y muestra en su lugar el estado "renders en camino".
$sinRender = empty($m['imgs']);

$precioValor = lw_modelo_precio_desde($m);
$precio   = lw_precio_fmt($precioValor);
// Solo se anuncia la subida de 2027 MIENTRAS sigue vigente el precio de ahora — pasado el
// corte, no hay nada que anunciar (el precio activo ya es el nuevo).
$antes2027 = lw_antes_del_corte_2027();
$nombre   = $m['nombre'];
$villa    = 'Villa ' . $nombre;
$dorm     = (int) $m['dormitorios'];
$banos    = (int) $m['banos'];

$g        = $m['imgs'];
$portada  = $g[0] ?? null;
$resto    = array_slice($g, 1);      // el resto de renders, en orden natural
$about    = $resto[0] ?? $portada;   // "Sobre el modelo": el segundo render (dali2)
$galeria  = array_slice($resto, 1);  // el resto de renders (dali3, dali4…), sin repetir $about

$dormTxt  = $dorm . ' ' . ($dorm === 1 ? 'bedroom' : 'bedrooms');
$banosTxt = $banos . ' ' . ($banos === 1 ? 'bathroom' : 'bathrooms');
$sizeTxt  = $m['villa_m2'] . 'm² + ' . $m['terraza_m2'] . 'm² terrace';

$precioTxt = $precio !== null ? $precio : 'Upon request';

// Sufijo del <title>, en una sola variable porque lo usan dos sitios: la etiqueta que pinta
// el servidor y el título que el configurador reescribe al cambiar de modelo sin recargar.
// Escrito dos veces sería la misma cadena en PHP y en JS, divergiendo en cuanto se retoque.
$TITULO_SUFIJO = ' · Turnkey villa in Bali — Lawang Tropical Properties';

// ── Configurador villa → techo → extras (14-sep-2026) ────────────────────────────────
// Copiado de /palmfield (encargo del owner: mismo diseño y estructura de la landing de
// campaña para las fichas de modelo). Sustituye al bloque de cuatro secciones (The range,
// Finishes, Island&view, Plot size&extras) Y al wizard de 5 pasos que solo tenía Dali: la
// parcela SALE del configurador (125 €/m² sigue publicado como línea aparte, "sized on the
// call") y entran los 7 extras reales por modelo que ni el bloque ni el wizard tenían
// precio para (lw_extras_resueltos(), modelo/datos.php). Motor compartido con /dali en
// assets/au-landing-cfg.js — misma pieza en dos páginas de producto, no una copia que
// pueda divergir. `$CAT` ya resuelve precio activo (2026/2027), specs, techos y extras de
// las 5 villas; es la misma llamada que usan /dali y /palmfield.
$CAT = lw_au_catalogo();
$cfgJs = ['divisas' => lw_divisas(), 'divFecha' => LW_DIV_FECHA, 'modelos' => []];
foreach ($CAT as $cmId => $v) {
    $cfgJs['modelos'][$cmId] = [
        'villa'  => $v['villa'],
        'specs'  => $v['specs'],
        'thumb'  => $v['thumb'],
        'techos' => [
            'sirap' => ['nombre' => $v['techos']['sirap']['nombre'], 'eur' => $v['techos']['sirap']['eur']],
            'bambu' => ['nombre' => $v['techos']['bambu']['nombre'], 'eur' => $v['techos']['bambu']['eur']],
        ],
        'extras' => $v['extras'],
    ];
}

$WA_NUM   = '6281138319862';
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text=' . rawurlencode("Hi, I'm interested in the " . $villa . ' from Lawang Tropical Properties.');
$WA_SHOW  = '+62 811-3831-9862';
$EMAIL    = 'sales@lawangproperties.com';

// Domicilio y líneas directas: mismos datos que /dali y /palmfield (el owner los dio el
// 4-sep-2026) — pie de página copiado de esas dos, 14-sep-2026.
$OFICINA = 'Jl. Gn. Tangkuban Perahu No.145, 2nd Floor, Padangsambian Klod, '
         . 'Kec. Denpasar Bar., Kota Denpasar, Bali 80117';
$TELEFONOS = [
    ['show' => '+62 811-3830-5240', 'tel' => '+6281138305240'],
    ['show' => '+62 811-3830-5237', 'tel' => '+6281138305237'],
];
// Sin render propio todavía (Trinity/Temple): og:image y preload caen a una foto real del
// sitio (no del modelo concreto) en vez de a una ruta vacía — nunca un render inventado.
$ogImg = $portada ?? '/assets/img/lugar/costa.webp';
// Mismo criterio que $configuradorModelos['path'] más abajo: Dali es el único modelo
// con alias raíz (/dali). El canonical y el og:url tienen que decir la URL real, o el
// primer pantallazo (antes de que corra el JS) ya contradice lo que el visitante ve.
$slugPath = $m['id'] === 'dali' ? 'dali' : 'modelo/' . $m['id'];
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<!-- Idioma de la web publica (EN/ES/ID). idioma-web.js va SIN defer y lo antes
     posible: fija el idioma y la tipografia antes del primer pintado. El
     diccionario de landings sí puede diferirse: traduce sobre el DOM ya montado. -->
<script src="/assets/idioma-web.js?v=20260908113407"></script>
<script src="/assets/i18n-landing.js?v=20260911114520" defer></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($villa . $TITULO_SUFIJO) ?></title>
<meta name="description" content="<?= lw_e($villa) ?>: a new-build <?= lw_e($dormTxt) ?> villa, built on the plot you choose. Finishes, scope of works and call booking.">
<?php if (!$precio): ?>
<meta name="robots" content="noindex, nofollow"><!-- sin precio cerrado no se indexa -->
<?php endif; ?>
<link rel="canonical" href="https://lawangproperties.com/<?= lw_e($slugPath) ?>">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="<?= lw_e($villa) ?> · Turnkey villa in Bali">
<meta property="og:description" content="Turnkey new build, <?= lw_e($dormTxt) ?>. You choose the plot and finish; the price is locked in writing before you sign.">
<meta property="og:url" content="https://lawangproperties.com/<?= lw_e($slugPath) ?>">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($ogImg) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<link rel="preload" as="image" href="<?= lw_e($ogImg) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="preconnect" href="https://api.fontshare.com">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<link href="https://api.fontshare.com/v2/css?f[]=general-sans@400,500,600,700&display=swap" rel="stylesheet">
<!-- Nav, hero, configurador y pie: piel compartida con /palmfield y /dali (14-sep-2026).
     Carga ANTES del <style> propio de esta página a propósito: lo que sigue abajo define
     su PROPIO :root (con --verde/--lagoon/etc, que usan las secciones que se conservan de
     este diseño) y solo las reglas de esas secciones — nunca `.nav`, `.hero`, `.cfg`,
     `.pie` ni `.btn`, que son de au-landing.css y no se redeclaran aquí. Cargar esta hoja
     despues dejaria que gane el cascade con los valores viejos. -->
<link rel="stylesheet" href="/assets/au-landing.css?v=20260914174048">
<style>
/* Display de marca: Neue Kabel, igual que el investor deck y las landings
   (11-sep-2026). Rutas relativas a /modelo/, de ahi el ../assets/. */
@font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-ExtraLight.otf') format('opentype');font-weight:200;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Light.otf') format('opentype');font-weight:300;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Book.otf') format('opentype');font-weight:400;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Medium.otf') format('opentype');font-weight:500;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Bold.otf') format('opentype');font-weight:700;font-style:normal;font-display:swap}
:root{
  --papel:#F5F0E6;
  /* #EDF1E8 (antes) casi no se distinguía de --papel (diferencia de 2-8 puntos por canal,
     imperceptible) — más saturado y con más salto real, verificado en 4,84:1 con --ink2
     encima (sigue AA). */
  --panel:#DCE7CB;
  --ink:#2E3437;
  /* rgba(46,52,55,.74) sobre --papel = 4,9:1 — el mockup traía opacity:.5-.68 en estos
     mismos usos (secundarios, notas, nav), que bajaba de 4,5:1 (falla AA). Un solo tono
     para todo lo "secundario" en vez de una escala de opacities sin medir. */
  --ink2:rgba(46,52,55,.74);
  --linea:#E0DBD0;
  --linea-fuerte:#D3CCBC;
  --verde:#485B37;
  --verde-osc:#37472B;
  --verde-tenue:#8F9B7A;
  /* Deep Lagoon y Terracotta entran con el diseño de Stitch (4-sep). NO son colores
     nuevos inventados: `--dl` ya es el acento de acción de la marca en
     `contracts/assets/brand.css` (y lo que manda 8b sobre 1a en lawang_espec_visual.md);
     aquí pasa de no usarse a ser el color dominante de barra y titulares. Terracotta es
     el único añadido real, y solo como CTA — medido: #B85433 sobre blanco da 4,58:1 y
     blanco sobre #B85433 da 4,58:1, así que el texto del botón cumple AA. */
  --lagoon:#104C4F;
  --lagoon-cl:#185D61;
  --terracota:#B85433;
  --terracota-osc:#A14425;
  --head:'Space Grotesk',sans-serif;
  --sans:'General Sans','Segoe UI',sans-serif;
  /* Cormorant Garamond para titulares, del diseño de Stitch. Convive con Space Grotesk,
     que se queda en cifras y etiquetas (`.font-mono-caps` del mockup): es justo lo que
     hace que un importe se lea como dato y no como texto corrido. */
  --display:'Neue Kabel','Jost','Segoe UI',sans-serif;
  --gut:clamp(24px,7vw,140px);
}
*{box-sizing:border-box}
body{margin:0;background:var(--papel);color:var(--ink);font-family:var(--sans);
  line-height:1.55;-webkit-font-smoothing:antialiased;text-wrap:pretty}
img{max-width:100%;display:block}
a{color:inherit;text-decoration:none}
::selection{background:var(--verde);color:var(--papel)}
/* Titulares en Cormorant (4-sep, diseño de Stitch) y en Deep Lagoon. El `letter-spacing`
   negativo se retira: era compensación para Space Grotesk, que es una grotesca ancha; en
   una garamond aprieta las serifas y ensucia el titular a tamaño grande. */
h1,h2{font-family:var(--display);font-weight:700;margin:0;letter-spacing:0;line-height:1.06;
  color:var(--lagoon)}
p{margin:0}
:focus-visible{outline:2px solid var(--verde);outline-offset:3px}

/* ── Idioma ───────────────────────────────────────────────────────────────────── */
/* Pivote a mercado australiano (2-sep): página solo en inglés, sin toggle. Se mantiene
   la regla (en vez de borrar el markup .i-es que aún queda en el FAQ/reserva/pie) porque
   es una línea y reversible por git — nunca un <span> ES visible por accidente.
   !important a propósito: sin él, selectores más específicos definidos MÁS ABAJO en esta
   misma hoja (`.reserva__card b`, `.reserva__card span`, que fijan su propio `display`)
   ganaban por especificidad y el español volvía a verse — encontrado en QA responsive del
   2-sep, español e inglés apilados en la tarjeta de reserva. Este selector no compite por
   estética, solo apaga contenido muerto: nada le disputa el `!important` a propósito. */
/* 8-sep-2026 · EL IDIOMA VUELVE, y ahora son tres (EN/ES/ID).
   La regla de arriba explica por que el markup `.i-es` se dejo en su sitio en vez de
   borrarlo: «es una linea y reversible por git». Esta es esa reversion. El español no
   se ha vuelto a traducir — es el que ya estaba escrito aqui, que es mejor que
   cualquier traduccion nueva del ingles.
   `:not([data-lang="es"])` cubre tambien el instante ANTES de que el modulo escriba el
   atributo: sin `data-lang` el selector casa, asi que el español nace oculto y nunca
   aparece apilado bajo el ingles — que es exactamente el fallo que se caza en el QA
   responsive del 2-sep y el motivo del `!important`.
   En bahasa se muestra el bloque `.i-en` y lo traduce `assets/i18n-landing.js`: no hay
   markup `.i-id`, y montarlo habria significado una tercera copia del FAQ en el HTML. */
html[data-lang="es"] .i-en{display:none !important}
html:not([data-lang="es"]) .i-es{display:none !important}

/* .wrap vive en assets/au-landing.css (1280px, mismo ancho que /palmfield y /dali) —
   retirado de aquí el 14-sep-2026 para que no gane el cascade con un ancho distinto. */

/* ── Nav, Hero, Configurador, Pie: viven en assets/au-landing.css desde el 14-sep-2026
   (copiados de /palmfield y /dali). Las reglas propias de esta página que llevaban esos
   mismos nombres de clase (`.nav`, `.btn`, `.hero`, `.pie`...) se han retirado de aquí a
   propósito: si se hubieran dejado, al cargar DESPUÉS de au-landing.css en el <head>
   habrían ganado el cascade y pisado la piel compartida con los valores viejos. ────── */

/* ── Layout de dos columnas ───────────────────────────────────────────────────── */
/* 300px (antes) se quedaba corto: el ancho útil tras el padding de .cal caía por debajo
   de los 320px que el propio widget de Calendly pide como mínimo, y salía con scroll
   horizontal interno. 360px deja sitio real. */
/* Una sola columna desde el 11-sep-2026: la ficha perdio su columna de calendario.
   Se acota al ancho que el contenido YA tenia cuando habia lateral (wrap - 360 - 40)
   y se centra: si se deja a 1fr, los parrafos se estiran a 1228px y los titulares con
   max-width propio se quedan pegados a la izquierda. */
.grid{display:grid;grid-template-columns:minmax(0,1fr);gap:40px;align-items:start;
  max-width:830px;margin-inline:auto}

/* ── Secciones ────────────────────────────────────────────────────────────────── */
.sec{padding-block:clamp(40px,5vw,64px);border-top:1px solid var(--linea)}
.sec:first-of-type{border-top:0}
.et{font-family:var(--sans);font-size:13px;font-weight:600;letter-spacing:.1em;
  text-transform:uppercase;color:var(--verde)}
/* El numeral de fondo ("01","02"...) apenas se notaba a .16 de opacidad — acentuado a .34,
   sigue siendo un adorno tipográfico, no compite con el titular de la sección. */
.num{font-family:var(--head);font-size:52px;font-weight:700;color:rgba(72,91,55,.34);
  margin-bottom:-6px}
.sec h2{font-size:clamp(25px,2.8vw,34px);margin-top:.3em;max-width:22ch}
.sec__desc{font-size:16px;color:var(--ink2);max-width:56ch;margin-top:.9em}

/* ── Sobre el modelo ──────────────────────────────────────────────────────────── */
.sobre{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:start}
@media(max-width:820px){.sobre{grid-template-columns:1fr}}
.sobre--full{grid-template-columns:1fr;max-width:64ch}
.sobre__fig{border-radius:8px;overflow:hidden;aspect-ratio:4/5}
.sobre__fig img{width:100%;height:100%;object-fit:cover}
.sobre__tx p{font-size:16px;color:var(--ink2);margin-top:.9em}

/* ── Galería ──────────────────────────────────────────────────────────────────── */
.gal__head{display:flex;justify-content:space-between;align-items:baseline;gap:24px;margin-bottom:22px}
.gal__note{font-size:12.5px;color:var(--ink2);font-style:italic;max-width:280px;text-align:right}
.gal__strip{display:flex;gap:16px;overflow-x:auto;padding-bottom:10px;scroll-snap-type:x mandatory}
.gal__strip figure{flex:0 0 min(78vw,400px);scroll-snap-align:start;margin:0}
.gal__strip img{width:100%;aspect-ratio:4/5;object-fit:cover;border-radius:8px}

/* ── Alcance de obra (acordeón) ──────────────────────────────────────────────── */
.doscol{display:grid;grid-template-columns:1fr 1fr;gap:clamp(24px,3vw,54px);margin-top:24px}
@media(max-width:640px){.doscol{grid-template-columns:1fr}}
.doscol h3{font-size:13px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;margin:0 0 16px}
.doscol ul{list-style:none;margin:0;padding:0}
.doscol li{display:grid;grid-template-columns:22px 1fr;gap:8px;padding:11px 0;
  border-top:1px solid var(--linea);font-size:14.5px}
.doscol li:last-child{border-bottom:1px solid var(--linea)}
.doscol li i{font-style:normal;font-family:var(--head);font-size:12px;color:var(--verde)}
.doscol--no h3,.doscol--no li{color:var(--ink2)}
.doscol--no li i{color:var(--ink2)}
.doscol__nota{font-size:12.5px;color:var(--ink2);margin-top:22px}

/* ── Ubicación ────────────────────────────────────────────────────────────────── */
.ubic__intro{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center}
@media(max-width:820px){.ubic__intro{grid-template-columns:1fr}}
.ubic__pts{display:flex;flex-direction:column;gap:11px;margin-top:22px}
.ubic__pt{display:flex;justify-content:space-between;border-bottom:1px solid var(--linea);
  padding-bottom:9px;font-size:14px}
.ubic__pt span:first-child{color:var(--ink2)}
.ubic__pt span:last-child{font-weight:600}
.ubic__nota{font-size:12px;color:var(--ink2);margin-top:16px;font-style:italic}

.ubic__fig{border-radius:8px;overflow:hidden;aspect-ratio:4/5}
.ubic__fig img{width:100%;height:100%;object-fit:cover}

/* ── Configurador villa→techo→extras, Nav, Hero y Pie: en assets/au-landing.css desde
   el 14-sep-2026 (copiados de /palmfield y /dali). El bloque de presupuesto por
   secciones y el formulario de un campo por pantalla (wizard, solo Dali) que vivían
   aquí — `.cfg__set/.cfg__in/.est*/.wiz*` — se retiraron con el HTML que pintaban. ──── */
/* Movimiento: respeta prefers-reduced-motion globalmente. */
@media(prefers-reduced-motion:reduce){
  *,*::before,*::after{transition-duration:.001ms !important;animation-duration:.001ms !important}
}

/* ── Proceso ──────────────────────────────────────────────────────────────────── */
.pasos{display:grid;grid-template-columns:repeat(3,1fr);gap:30px;margin-top:12px}
@media(max-width:760px){.pasos{grid-template-columns:1fr}}
.pasos h2{margin-bottom:8px}
.pasos__it .bola{width:28px;height:28px;border-radius:50%;background:var(--verde);color:#fff;
  display:flex;align-items:center;justify-content:center;font-family:var(--head);font-size:12.5px;
  font-weight:700;margin-bottom:16px}
.pasos__it h3{font-size:17px;font-weight:600;margin:0 0 8px}
.pasos__it p{font-size:14px;color:var(--ink2)}

/* ── Precio ───────────────────────────────────────────────────────────────────── */
.precio{display:flex;justify-content:center}
.precio__box{max-width:540px;width:100%}
.precio .et,.precio h2{text-align:center}
.precio h2{margin:0 0 32px}
.precio__tabla{border:1px solid var(--linea);border-radius:10px;overflow:hidden}
.precio__fila{display:flex;justify-content:space-between;align-items:baseline;padding:18px 26px;
  border-bottom:1px solid var(--linea);background:var(--papel)}
.precio__fila:last-child{border-bottom:0}
.precio__fila span:first-child{font-size:13px;color:var(--ink2);text-transform:uppercase;letter-spacing:.03em}
.precio__fila span:last-child{font-family:var(--head);font-size:18px;font-weight:600}
.precio__nota{font-size:12.5px;color:var(--ink2);margin-top:16px;text-align:center}
.precio__cta{text-align:center;margin-top:26px}

/* ── FAQ ──────────────────────────────────────────────────────────────────────── */
.faq{display:flex;justify-content:center}
.faq__box{max-width:700px;width:100%}
.faq details{border-top:1px solid var(--linea)}
.faq details:last-of-type{border-bottom:1px solid var(--linea)}
.faq summary{cursor:pointer;list-style:none;padding:18px 34px 18px 0;position:relative;
  font-size:15.5px;font-weight:600}
.faq summary::-webkit-details-marker{display:none}
.faq summary::after{content:"+";position:absolute;right:4px;top:16px;color:var(--verde);
  font-family:var(--head);font-size:19px}
.faq details[open] summary::after{content:"–"}
.faq p{padding:0 0 20px;font-size:14.5px;color:var(--ink2);max-width:64ch}

/* ── Acordeón genérico (alcance, proceso) — 2-sep, reestructuración: mismo lenguaje
   visual que el FAQ de arriba, generalizado fuera de .faq para que cualquier bloque
   secundario pueda cerrarse por defecto sin perder ni una palabra de contenido. ──── */
.acc summary{cursor:pointer;list-style:none;padding:4px 34px 4px 0;position:relative;
  font-family:var(--head);font-size:19px;font-weight:600}
.acc summary::-webkit-details-marker{display:none}
.acc summary::after{content:"+";position:absolute;right:4px;top:2px;color:var(--verde);
  font-family:var(--head);font-size:20px}
.acc[open] summary::after{content:"–"}
.acc__body{margin-top:28px}

/* ── Reserva ──────────────────────────────────────────────────────────────────── */
.reserva{text-align:center;padding-bottom:20px}
.reserva h2{font-size:clamp(28px,4vw,44px);margin-top:.25em;margin-inline:auto}
.reserva__desc{font-size:16px;color:var(--ink2);max-width:480px;margin:.85em auto 0}
.reserva__card{border:1px solid var(--linea);border-radius:10px;padding:40px 30px;
  background:var(--panel);max-width:620px;margin:32px auto 0}
.reserva__card b{display:block;font-size:15px;font-weight:600;margin-bottom:6px}
.reserva__card span{display:block;font-size:13px;color:var(--ink2);margin-bottom:22px}
.reserva__contact{display:flex;justify-content:center;gap:32px;margin-top:28px;font-size:14px;
  color:var(--ink2);flex-wrap:wrap}
.reserva__contact a:hover{color:var(--verde)}

/* La columna de calendario y el widget de Calendly se retiraron el 11-sep-2026 (esta
   ficha ya no agenda cita); el .pie de 3 columnas vive en assets/au-landing.css. */
@media print{ .nav{display:none} }
</style>
</head>
<body>

<!-- ═══ TOPBAR (copiado de /palmfield y /dali, 14-sep-2026) ═══════════════════════════ -->
<header class="nav">
  <div class="wrap nav__in">
    <a href="/" aria-label="Lawang Tropical Properties">
      <img class="nav__brand" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
    </a>
    <nav class="nav__links">
      <a href="#estimator"><?= lw_i18n('Tu presupuesto', 'Your estimate') ?></a>
      <a href="#ubicacion"><?= lw_i18n('Ubicación', 'Location') ?></a>
      <a href="#faq"><?= lw_i18n('Preguntas', 'FAQ') ?></a>
    </nav>
    <div class="nav__cta">
      <!-- Selector de divisa: mismo componente que /dali (11-sep-2026), inyectado por
           assets/au-landing-cfg.js con las clases .lw-lang que idioma-web.js ya trae. -->
      <div class="lw-cur" id="lw-div-sel" data-no-i18n></div>
      <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
        <span><?= lw_i18n('Escríbenos', 'WhatsApp') ?></span>
      </a>
    </div>
  </div>
</header>

<div class="wrap">
<div class="grid">
<div>

  <!-- ── Hero (copiado de /palmfield y /dali, 14-sep-2026) ─────────────────────
       Una sola columna (`hero--solo`, la misma que /dali desde el 11-sep): esta ficha
       ya no agenda cita, así que no hay tarjeta lateral que llenar el segundo hueco.
       El precio va en un chip, como en /dali — no en la insignia `.hero__precio` que
       traía el diseño anterior (retirada, no forma parte de au-landing.css). -->
  <section class="hero hero--solo">
    <div>
      <div class="hero__pills">
        <span class="pill pill--verde"><span class="dot"></span> New build · Turnkey</span>
        <?php if ($antes2027): ?><span class="pill pill--terra">2026 price</span><?php endif; ?>
      </div>
      <h1 id="lw-hero-title"><?= lw_e($villa) ?></h1>
      <p class="hero__sub" id="lw-hero-sub"><?= lw_e($m['sub_en'] ?? '') ?></p>

      <div class="chips">
        <div class="chip">
          <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5L21 16z"/></svg></span>
          <span><span class="chip__lb">Size</span>
                <span class="chip__vl" id="lw-fact-size"><?= lw_e($sizeTxt) ?></span></span>
        </div>
        <div class="chip">
          <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h2v16H4V4zm7 0h2v16h-2V4zm7 0h2v16h-2V4z"/></svg></span>
          <span><span class="chip__lb">Layout</span>
                <span class="chip__vl" id="lw-fact-layout"><?= lw_e($dorm . ' bed · ' . $banos . ' bath') ?></span></span>
        </div>
        <div class="chip">
          <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/></svg></span>
          <span><span class="chip__lb">From</span>
                <span class="chip__vl" id="lw-hero-price"<?= $precioValor !== null ? ' data-eur-fijo="' . (int) $precioValor . '"' : '' ?>><?= lw_e($precioTxt) ?></span></span>
        </div>
      </div>

      <div class="hero__cta">
        <a class="btn btn--terra" href="#estimator">See Your Figure</a>
        <a class="btn btn--lag" href="#galeria" id="lw-hero-gallery-link"<?= $sinRender ? ' hidden' : '' ?>>View gallery</a>
      </div>
    </div>

    <?php if ($sinRender): ?>
    <!-- Estado "renders en camino" (Diseño, revisión previa 2-sep): nunca un placeholder
         gris ni un icono de imagen rota — el mismo peso visual que el mosaico con fotos,
         honesto sobre lo que falta sin parecer un error. Clase compartida en
         assets/au-landing.css (`.mosaico--pend`), nacida aquí el 14-sep-2026. -->
    <div class="mosaico mosaico--pend" id="lw-hero-fig">
      <figure>
        <svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/><path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg>
        <p class="mos__tt">Renders in progress</p>
        <p class="mos__sub">Reserve before they exist — the roof price is confirmed by the developer today.</p>
      </figure>
    </div>
    <?php else: ?>
    <div class="mosaico" id="lw-hero-fig">
      <figure>
        <img src="<?= lw_e($portada) ?>" alt="<?= lw_e($villa) ?>, Lawang Tropical Properties: exterior with overflow pool" fetchpriority="high">
        <figcaption>
          <span class="mos__et">Render</span>
          <span class="mos__tt"><?= lw_e($villa) ?></span>
        </figcaption>
      </figure>
      <?php foreach (array_slice($resto, 0, 2) as $i => $extraImg): ?>
      <figure>
        <img src="<?= lw_e($extraImg) ?>" alt="Project render of the <?= lw_e($villa) ?> (<?= $i + 2 ?> of <?= count($g) ?>)" loading="lazy">
      </figure>
      <?php endforeach; ?>
    </div>
    <?php endif; ?>
  </section>

  <!-- Botón + modal de vídeo del diseño importado, RETIRADOS a propósito (1-sep): sin un
       vídeo real que enseñar, el modal solo mostraba el texto de instrucciones para el
       equipo ("Aquí va tu vídeo... conecta tu MP4") a un lead real que pulsara el botón —
       hallazgo de Desarrollo en la revisión de deploy. "Nada con placeholders sale del
       estudio". Reintroducir cuando haya un vídeo real: el markup queda en el Backup de
       esta misma fecha (Backups/20260901_1320_modelo-index_pre-dali-v5.php es la versión
       ANTERIOR a este diseño, no sirve de referencia para esto — el botón/modal viven en
       el primer commit de esta v5, `03aad68`, si hace falta recuperarlos). -->

  <!-- ═══ CONFIGURADOR: villa → techo → extras (14-sep-2026) ═══════════════════════════
       Copiado de /palmfield (encargo del owner: mismo diseño y estructura de la landing
       de campaña para las fichas de modelo). Sustituye al bloque de cuatro secciones (The
       range, Finishes, Island&view, Plot size&extras) Y al wizard de 5 pasos que solo
       tenía Dali — la rama `$wizard` desaparece, las dos convergen en este único bloque.
       La parcela SALE del configurador: 125 €/m² sigue publicado como línea aparte,
       "sized on the call". Entran los 7 extras reales por modelo (lw_extras_resueltos(),
       modelo/datos.php) que ni el bloque ni el wizard tenían precio para. Motor
       compartido con /dali en assets/au-landing-cfg.js: es la misma pieza en dos páginas
       de producto, no una copia que pueda divergir. -->
  <section class="sec sec--surface" id="estimator">
    <p class="et">
      <span class="pill pill--verde">3-Step</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">Pick an option and it moves on</span>
    </p>
    <h2>Three questions. Your figure.</h2>
    <p class="sec__desc">Prices confirmed directly by the developer and include Indonesian VAT
      (PPN). The plot is quoted separately, sized on the call.</p>

    <div class="cfg">
      <!-- Pasos -->
      <div class="cfg__card">
        <div class="cfg__hd">
          <span class="cfg__paso" id="lw-paso-lb">Step 1 of 3</span>
        </div>

        <!-- Paso 1: villa -->
        <div class="cfg__step" data-paso="1">
          <p class="cfg__q">Which villa?</p>
          <p class="cfg__nota">Same construction system and roof choice across the range — only
            the size changes the price. The price shown is the villa with its cheaper roof; you
            pick the roof next.</p>
          <div class="ops">
            <?php foreach ($CAT as $cmId => $v): ?>
            <label class="op">
              <input type="radio" name="lw-villa" value="<?= lw_e($cmId) ?>"<?= $cmId === $m['id'] ? ' checked' : '' ?>>
              <?php if ($v['thumb']): ?>
                <img class="op__th" src="<?= lw_e($v['thumb']) ?>" alt="" loading="lazy">
              <?php else: ?>
                <span class="op__th op__th--vacio"><svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke-linejoin="round"/><rect x="24" y="48" width="72" height="34" fill="none"/></svg></span>
              <?php endif; ?>
              <span>
                <span class="op__nb"><?= lw_e($v['villa']) ?></span>
                <span class="op__sp"><?= lw_e($v['specs']) ?></span>
              </span>
              <span class="op__pr" data-eur="<?= (int) $v['desde_eur'] ?>">
                <b><?= lw_e(lw_precio_fmt($v['desde_eur'])) ?></b>
                <i></i>
              </span>
            </label>
            <?php endforeach; ?>
          </div>
        </div>

        <!-- Paso 2: techo. Lo pinta el JS: el precio es el de la villa ya elegida. -->
        <div class="cfg__step" data-paso="2" hidden>
          <p class="cfg__q">Which roof?</p>
          <p class="cfg__nota">Two complete villa prices, not an add-on: the roof you choose is
            the price of the villa.</p>
          <div class="ops" id="lw-techos"></div>
        </div>

        <!-- Paso 3: extras. Multiseleccion, asi que este NO avanza solo al hacer clic. -->
        <div class="cfg__step" data-paso="3" hidden>
          <p class="cfg__q">Any extras?</p>
          <p class="cfg__nota">Optional, and none of them is needed to move in. Tick as many as
            you want — the figure on the right updates as you go.</p>
          <div class="ops" id="lw-extras"></div>
        </div>

        <div class="cfg__nav">
          <button type="button" class="cfg__atras" id="lw-atras" hidden>← Back</button>
          <span class="puntos" id="lw-puntos" aria-hidden="true"></span>
          <button type="button" class="btn btn--lag" id="lw-siguiente">
            Next <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 5l7 7-7 7v-4H4v-6h9V5z"/></svg>
          </button>
        </div>
      </div>

      <!-- Resumen en vivo -->
      <div class="res">
        <div class="res__card">
          <div class="res__hd">
            <span class="res__tt">Your estimate</span>
            <span class="pill pill--canopy">Indicative</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="lw-r-villa"><?= lw_e($villa) ?></span>
                  <span class="res__sub" id="lw-r-villa-sub">Turnkey build</span></span>
            <span class="res__vl" id="lw-r-villa-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="lw-r-extras">Extras</span>
                  <span class="res__sub" id="lw-r-extras-sub">None selected</span></span>
            <span class="res__vl" id="lw-r-extras-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Notary, permits &amp; transfer</span>
                  <span class="res__sub">Detailed in writing before you sign</span></span>
            <span class="res__vl">Separate</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Freehold plot</span>
                  <span class="res__sub"><?= lw_e(lw_precio_fmt(lw_parcela_tarifa_m2('otras'))) ?>/m² · sized on the call</span></span>
            <span class="res__vl">Separate</span>
          </div>
        </div>

        <div class="total">
          <span class="total__lb">Villa turnkey, your spec</span>
          <span class="total__vl" id="lw-total">—</span>
          <span class="total__alt" id="lw-total-alt"></span>
          <p class="total__nota">Indicative only — not a quote or a reservation. Confirmed by the
            developer in writing before you sign.</p>
          <a class="btn btn--terra btn--block total__cta" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
            Send this configuration on WhatsApp
          </a>
        </div>
        <p class="res__sync">We reply during Bali hours (WITA)</p>
      </div>
    </div>
  </section>

  <!-- ── Marcador de transición (2-sep, Diseño: sin esto, "01 About the model" que
       viene justo después puede leerse como si describiera lo que acabas de configurar
       arriba, cuando en realidad sigue siendo el modelo de ESTA página/URL). ────────── -->
  <p class="sec__desc" id="lw-static-marker" style="text-align:center;padding-block:28px 0;font-size:13px">
    From here on, this page describes <strong id="lw-static-marker-name"><?= lw_e($villa) ?></strong> — switch models above to compare price and specs.
  </p>

  <!-- ── Sobre el modelo ───────────────────────────────────────────────────── -->
  <section class="sec sobre<?= $sinRender ? ' sobre--full' : '' ?>">
    <?php if (!$sinRender): ?>
    <div class="sobre__fig">
      <img src="<?= lw_e($about) ?>" alt="Interior or architectural detail of the <?= lw_e($villa) ?>" loading="lazy">
    </div>
    <?php endif; ?>
    <div class="sobre__tx">
      <div class="num">01</div>
      <p class="et">About the model</p>
      <h2><?= lw_e($villa) ?>, a new turnkey build</h2>
      <p>Lawang Tropical Properties develops turnkey villas in Bali: you choose the plot and the finish, and the budget is locked in writing before you sign anything.</p>
      <p>The rest of the villa doesn't change between finishes: structure, architecture, and installations stay the same. Only the roof changes with the option you pick.</p>
    </div>
  </section>

  <!-- ── Galería ────────────────────────────────────────────────────────────── -->
  <?php if (!$sinRender): ?>
  <section class="sec" id="galeria">
    <div class="gal__head">
      <h2><?= lw_e($villa) ?>, inside</h2>
      <p class="gal__note">Project renders, not photographs of a finished villa.</p>
    </div>
    <div class="gal__strip">
      <?php foreach ($galeria as $i => $img): ?>
      <figure><img src="<?= lw_e($img) ?>" alt="Project render of the <?= lw_e($villa) ?> (<?= $i + 3 ?> of <?= count($g) ?>)" loading="lazy"></figure>
      <?php endforeach; ?>
      <figure><img src="/assets/img/lugar/costa.webp" alt="River mouth and volcanic-sand beach on Bali's west coast" loading="lazy"></figure>
    </div>
  </section>
  <?php endif; ?>

  <!-- ── Alcance de obra — acordeón (2-sep, cerrado por defecto): mismo contenido de
       siempre, no una palabra menos, solo un clic para verlo en vez de 601px fijos. ── -->
  <?php if (!empty($m['alcance'])): ?>
  <section class="sec">
    <details class="acc">
      <summary><?= lw_i18n('Alcance de obra — Qué incluye el precio', "Scope of works — what's included") ?></summary>
      <div class="acc__body doscol">
        <div>
          <h3><?= lw_i18n('Incluido', 'Included') ?></h3>
          <ul>
            <?php foreach ($m['alcance']['incluido'] as $k => $li): $en = $m['alcance']['incluido_en'][$k] ?? $li; ?>
            <li><i><?= str_pad($k + 1, 2, '0', STR_PAD_LEFT) ?></i><span><?= lw_i18n($li, $en) ?></span></li>
            <?php endforeach; ?>
          </ul>
        </div>
        <div class="doscol--no">
          <h3><?= lw_i18n('No incluido', 'Not included') ?></h3>
          <ul>
            <?php foreach ($m['alcance']['no_incluido'] as $k => $li): $en = $m['alcance']['no_incluido_en'][$k] ?? $li; ?>
            <li><i>&ndash;</i><span><?= lw_i18n($li, $en) ?></span></li>
            <?php endforeach; ?>
          </ul>
          <p class="doscol__nota"><?= lw_i18n(
            'La parcela y los gastos de compraventa (impuestos, notaría y licencias) se presupuestan aparte y se detallan por escrito antes de firmar.',
            // Mismo ajuste que el FAQ (3-sep, Legal): "taxes" a secas contradecía el panel,
            // que declara el PPN incluido en el precio de villa.
            'The villa price includes Indonesian VAT (PPN). The plot and the closing costs on the purchase (transfer tax, notary, permits) are quoted separately and detailed in writing before signing.'
          ) ?></p>
        </div>
      </div>
    </details>
  </section>
  <?php endif; ?>

  <!-- ── Ubicación ──────────────────────────────────────────────────────────── -->
  <section class="sec ubic" id="ubicacion">
    <div class="ubic__intro">
      <div>
        <p class="et"><?= lw_i18n('El sitio', 'The site') ?></p>
        <h2><?= lw_i18n('Tú eliges la parcela', 'You choose the plot') ?></h2>
        <p class="sec__desc"><?= lw_i18n(
          'El modelo se levanta sobre la parcela que elijas de nuestro catálogo en la costa oeste de Bali. En la llamada te decimos qué parcelas quedan y cómo se llega a cada una.',
          "The model is built on the plot you choose from our catalog on Bali's west coast. On the call, we'll tell you which plots are available and how to reach each one."
        ) ?></p>
        <div class="ubic__pts">
          <div class="ubic__pt"><span><?= lw_i18n('Parcela', 'Plot') ?></span><span><?= lw_i18n('A elegir del catálogo', 'Chosen from the catalog') ?></span></div>
          <div class="ubic__pt"><span><?= lw_i18n('Zona', 'Area') ?></span><span><?= lw_i18n('Costa oeste de Bali', "Bali's west coast") ?></span></div>
          <div class="ubic__pt"><span><?= lw_i18n('Régimen', 'Title') ?></span><span><?= lw_i18n('Se revisa por parcela', 'Reviewed per plot') ?></span></div>
        </div>
        <p class="ubic__nota"><?= lw_i18n('Fotografía real con dron · Costa oeste de Bali', "Real drone photograph · Bali's west coast") ?></p>
      </div>
      <div class="ubic__fig">
        <img src="/assets/img/lugar/rio.jpg" alt="Valle y río junto a la costa, vista aérea" loading="lazy">
      </div>
    </div>

  </section>

  <!-- ── Proceso — acordeón (2-sep, cerrado por defecto) ─────────────────────── -->
  <section class="sec">
    <details class="acc">
      <summary><?= lw_i18n('Cómo se compra', "How it's purchased") ?></summary>
      <div class="acc__body pasos">
        <div class="pasos__it">
          <span class="bola">01</span>
          <h3><?= lw_i18n('Llamada', 'Call') ?></h3>
          <p><?= lw_i18n('Media hora para ver qué parcela encaja, con qué presupuesto y en qué plazos.', 'Half an hour to see which plot fits, with what budget and timeline.') ?></p>
        </div>
        <div class="pasos__it">
          <span class="bola">02</span>
          <h3><?= lw_i18n('Presupuesto y parcela', 'Budget & plot') ?></h3>
          <p><?= lw_i18n('Precio cerrado del acabado elegido, parcela concreta y calendario de pagos.', 'Fixed price for the chosen finish, a specific plot, and a payment schedule.') ?></p>
        </div>
        <div class="pasos__it">
          <span class="bola">03</span>
          <h3><?= lw_i18n('Reserva y obra', 'Reservation & construction') ?></h3>
          <p><?= lw_i18n('Contrato de reserva, después el PPJB de compraventa y el contrato de construcción, y arranca la obra.', 'Reservation contract, then the sale (PPJB) and construction contracts, and construction begins.') ?></p>
        </div>
      </div>
    </details>
  </section>

  <!-- ── FAQ ────────────────────────────────────────────────────────────────── -->
  <section class="sec faq" id="faq">
    <div class="faq__box">
      <h2 style="margin-bottom:28px"><?= lw_i18n('Preguntas frecuentes', 'Frequently asked questions') ?></h2>

      <?php /* Comentario de PHP y no de HTML A PROPÓSITO — no debe viajar al navegador.
             Texto ES = el que Legal aprobó el 30-jul para la versión anterior (ver Backups/
             …_pre-dali-v5.php). El mockup importado traía una paráfrasis casi idéntica pero
             no exacta; se usa la redacción ya validada para no reabrir esa revisión.
             NO reintroducir "freehold" ni "estructurado a través de una sociedad indonesia"
             como forma de titularidad de un extranjero: es justo lo que Legal tumbó. */ ?>
      <details>
        <summary><?= lw_i18n('¿Qué compro exactamente y en qué régimen?', 'What exactly am I buying, and under what title?') ?></summary>
        <p class="i-es">La villa construida y el derecho sobre la parcela en la que se levanta. En
          Indonesia ese derecho no funciona como la propiedad española y no todas las
          parcelas están en el mismo régimen ni con el mismo plazo. Es la primera cosa que
          repasamos en la llamada, parcela por parcela y con el documento delante, antes de
          hablar de dinero.</p>
        <p class="i-en">The built villa and the right over the plot it stands on. In Indonesia
          that right doesn't work like Spanish-style ownership, and not every plot sits
          under the same scheme or term. We review it plot by plot on the call, document in
          hand, before talking numbers.</p>
      </details>
      <details>
        <summary><?= lw_i18n('¿Qué incluye el precio?', "What's included in the price?") ?></summary>
        <?php /* La copia ES no se ve hoy (la página es solo inglés desde el pivote
               australiano, .i-es va a display:none) pero se corrige igual: si algún día se
               reactiva el bilingüe, resucitaría la misma contradicción del PPN que se acaba
               de cerrar en la versión inglesa, y nadie se acordaría de mirarlo. */ ?>
        <p class="i-es">La obra completa según el pliego del contratista, con el acabado de cubierta que
          elijas. El precio de la villa ya incluye el IVA indonesio (PPN). La parcela y los
          gastos de compraventa (impuesto de transmisión, notaría y licencias) se
          presupuestan aparte y se detallan por escrito antes de firmar nada.</p>
        <?php /* 3-sep, capa 1 de deploy (Legal): decía "closing costs (taxes, notary,
               permits) are quoted separately" a secas. Desde que el panel de presupuesto
               afirma que el PPN va DENTRO del precio de villa, un lead leía las dos frases
               y concluía razonablemente que le iban a sumar el 11%. Los contratos dan la
               razón al panel (el PPJB de construcción dice que el precio del contrato
               incluye todos los impuestos), así que lo obsoleto era esta frase: ahora
               nombra los gastos concretos en vez de "taxes" a secas, y dice explícitamente
               que el PPN ya está dentro. */ ?>
        <p class="i-en">The full build with the roof finish you choose. The villa price
          already includes Indonesian VAT (PPN). The plot, and the closing costs on the
          purchase (transfer tax, notary and permits), are quoted separately and detailed in
          writing before you sign.</p>
      </details>
      <details>
        <summary><?= lw_i18n('¿Puedo elegir dónde se construye?', 'Can I choose where it gets built?') ?></summary>
        <p class="i-es">Sí. El modelo es el mismo y se levanta sobre la parcela que elijas del catálogo.
          Cambian la vista, la orientación y el precio del terreno. No todas las parcelas
          admiten cualquier modelo: eso se concreta en la llamada.</p>
        <p class="i-en">Yes. The model stays the same and is built on the plot you choose from the
          catalog. The view, orientation, and land price change. Not every plot takes every
          model — that's confirmed on the call.</p>
      </details>
      <details>
        <summary><?= lw_i18n('¿En qué moneda se firma?', 'What currency is the contract in?') ?></summary>
        <p class="i-es">El contrato se formaliza en rupias indonesias, como exige la ley indonesia para
          operaciones dentro del país. La equivalencia en euros se incluye a título
          informativo con el tipo de cambio de la fecha.</p>
        <p class="i-en">The contract is executed in Indonesian rupiah, as required by Indonesian law
          for transactions inside the country. Other-currency equivalents are given for
          reference only, at the exchange rate on the date.</p>
      </details>
      <details>
        <summary><?= lw_i18n('¿Cómo se formaliza la compra?', 'How is the purchase formalized?') ?></summary>
        <p class="i-es">Primero un contrato de reserva sobre la parcela. Después el PPJB, que es el
          contrato de compraventa indonesio, y el contrato de construcción. Los tres son
          documentos propios del promotor y se revisan antes de firmar.</p>
        <p class="i-en">First a reservation contract on the plot. Then the PPJB — the Indonesian sale
          contract — and the construction contract. All three are the developer's own
          documents and are reviewed before signing.</p>
      </details>
      <details>
        <summary><?= lw_i18n('¿Quién construye?', 'Who builds it?') ?></summary>
        <p class="i-es">Lawang Tropical Properties, a través de la sociedad indonesia PT Tepi Sun Gai. En
          la llamada te enseñamos obras entregadas y las que están en marcha ahora mismo.</p>
        <p class="i-en">Lawang Tropical Properties, through the Indonesian company PT Tepi Sun Gai. On
          the call we show you delivered projects and the ones underway right now.</p>
      </details>
    </div>
  </section>

  <!-- ── Reserva ────────────────────────────────────────────────────────────── -->
  <section class="sec reserva" id="agendar">
    <p class="et"><?= lw_i18n('Siguiente paso', 'Next step') ?></p>
    <h2><?= lw_i18n('Escríbenos', 'Talk to us') ?></h2>
    <p class="reserva__desc"><?= lw_i18n(
      'Te damos el presupuesto cerrado del acabado que te interese y las parcelas disponibles donde puede construirse.',
      "We'll give you a fixed quote for the finish you're interested in and the available plots it can be built on."
    ) ?></p>
    <div class="reserva__card">
      <b class="i-es">WhatsApp</b><b class="i-en">WhatsApp</b>
      <span class="i-es">Te respondemos en horario de Bali (WITA).</span>
      <span class="i-en">We reply during Bali hours (WITA).</span>
      <a class="btn btn--terra" id="lw-wa-cta" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
        <?= lw_i18n('Escribir por WhatsApp', 'Message us on WhatsApp') ?>
      </a>
    </div>
    <div class="reserva__contact">
      <a href="mailto:<?= lw_e($EMAIL) ?>"><?= lw_e($EMAIL) ?></a>
      <a href="<?= lw_e($WA_LINK) ?>" id="lw-wa-link" target="_blank" rel="noopener"><?= lw_e($WA_SHOW) ?></a>
    </div>
  </section>

</div><!-- /col -->


</div><!-- /grid -->
</div><!-- /wrap -->

<!-- ═══ PIE (copiado de /palmfield y /dali, 14-sep-2026) ═════════════════════════════ -->
<footer class="pie">
  <div class="wrap">
    <div class="pie__cols">
      <div>
        <img class="pie__brand" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
        <p style="margin:0">PT Tepi Sun Gai · Registered Developer &amp; Property Advisory.
          Developing verified freehold parcels and turnkey architectural villas across
          Tabanan, Uluwatu and Sumba.</p>
      </div>
      <div>
        <h4><?= lw_i18n('Contacto', 'Investor Desk') ?></h4>
        <p class="pie__dl">
          <span>Email: <a href="mailto:<?= lw_e($EMAIL) ?>"><b><?= lw_e($EMAIL) ?></b></a></span>
          <span>WhatsApp: <a href="<?= lw_e($WA_LINK) ?>" id="lw-wa-link" target="_blank" rel="noopener noreferrer"><b><?= lw_e($WA_SHOW) ?></b></a></span>
          <?php foreach ($TELEFONOS as $t): ?>
          <span>Direct line: <a href="tel:<?= lw_e($t['tel']) ?>"><b><?= lw_e($t['show']) ?></b></a></span>
          <?php endforeach; ?>
          <span>Working hours: <b>Bali time (WITA)</b></span>
          <span style="margin-top:5px">Office:<br><b><?= lw_e($OFICINA) ?></b></span>
        </p>
      </div>
      <div>
        <h4>Turnkey EPC Standard</h4>
        <p style="margin:0">Every project operates under guaranteed fixed-price written
          agreements with progress audits at each construction milestone.</p>
        <div class="pie__sellos">
          <span class="sello">Fixed-Price EPC</span>
          <span class="sello">PPN Included</span>
        </div>
      </div>
    </div>
    <div class="pie__legal">
      <span class="i-es">© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Todos los derechos reservados.</span>
      <span class="i-en">© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). All rights reserved.</span>
      <span>
        <a href="/legal-es" class="i-es">Aviso legal y privacidad</a><a href="/legal" class="i-en">Legal &amp; privacy</a>
        · <a href="#" id="lw-cookies" class="i-es">Preferencias de cookies</a><a href="#" id="lw-cookies-en" class="i-en">Cookie preferences</a>
      </span>
    </div>
  </div>
</footer>

<!-- Barra inferior en móvil (copiada de /palmfield y /dali, 14-sep-2026) -->
<div class="movil">
  <span class="movil__pr">
    <b id="lw-movil-pr"><?= lw_e($precioTxt) ?></b>
    <span><?= lw_e($villa) ?></span>
  </span>
  <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer" aria-label="Chat on WhatsApp">
    <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
  </a>
</div>

<script src="/assets/consent.js?v=20260908111654" defer></script>
<!-- Sin `defer`: la llama el script inline de abajo en el mismo pase de parseo, y un
     `defer` aqui la dejaria definida DESPUES de que el inline intente llamarla (los
     `defer` se ejecutan al final del parseo, los inline no). -->
<script src="/assets/au-landing-cfg.js?v=20260914174048"></script>
<script>
(function () {
  'use strict';
  // Flags de escape en todo json_encode que viaja dentro de <script> (3-sep): hoy los
  // nombres son inocuos, pero el payload crece con el configurador y una etiqueta de
  // cierre de script, o un "&", en un campo de catálogo rompería el bloque entero.
  // (Esa etiqueta no se escribe literal ni en este comentario: dentro de un <script> la
  // cierra igual, aunque vaya comentada — cazado por tools/sintaxis_js.py al ampliarlo
  // a .php en esta misma tarea, que es exactamente para lo que servía ampliarlo.)
  var MODELO = <?= json_encode($m['id'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  var CFG    = <?= json_encode($cfgJs, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  var WA_NUM = <?= json_encode($WA_NUM, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;

  // ── Píxel: ViewContent al cargar, con `value`/`currency` cuando hay precio cerrado.
  //    `value` es el precio de la villa DE ESTA PÁGINA con su techo más barato — el mismo
  //    dato que ya pintó PHP en $precioValor, nunca lo que esté eligiendo el configurador
  //    (que puede estar explorando otra villa sin haber navegado a su ficha). ───────────
  function track(ev, extra) {
    if (typeof window.lwTrack !== 'function') return;
    var p = Object.assign({content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO}, extra || {});
    var v = <?= json_encode($precioValor) ?>;
    if (v !== null && !('value' in p)) { p.value = v; p.currency = 'EUR'; }
    window.lwTrack(ev, p);
  }
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  // ── Configurador villa → techo → extras: motor compartido con /dali, ver
  //    assets/au-landing-cfg.js. Empieza en el modelo DE ESTA PÁGINA. ─────────────────
  window.lwAuCfgInit({
    cfg: CFG,
    waNum: WA_NUM,
    urlBase: '/<?= lw_e($slugPath) ?>',
    villaDefault: MODELO,
    waIntro: "Hi, I'm interested in the "
  });


  // ── Cookies: reabrir el aviso de consent.js ──────────────────────────────────
  ['lw-cookies', 'lw-cookies-en'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.addEventListener('click', function (e) {
      e.preventDefault();
      if (window.lwConsentReopen) window.lwConsentReopen();
    });
  });
})();
</script>
</body>
</html>
