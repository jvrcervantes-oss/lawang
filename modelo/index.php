<?php
/**
 * Landing de modelo de villa — /modelo/<id> (regla de reescritura en .htaccess).
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
require __DIR__ . '/lib.php';
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

$precio   = lw_precio_fmt(lw_modelo_precio_desde($m));
// Solo se anuncia la subida de 2027 MIENTRAS sigue vigente el precio de ahora — pasado el
// corte, no hay nada que anunciar (el precio activo ya es el nuevo).
$antes2027 = (new DateTime('now', new DateTimeZone(LW_TZ_BALI))) < new DateTime(LW_CORTE_2027, new DateTimeZone(LW_TZ_BALI));
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

$facts = [
    ['en' => 'Size',      'v_en' => $sizeTxt],
    ['en' => 'Layout',    'v_en' => $dorm . ' bed · ' . $banos . ' bath'],
    ['en' => 'Pool',      'v_en' => 'Included'],
    ['en' => 'Price',     'v_en' => 'From ' . $precioTxt],
];

// Tarifa de parcela ORIENTATIVA (revisión previa Seguridad+Administración, 2-sep): dos
// constantes fijas, nunca un total combinado con la villa — ver lw_parcela_tarifa_m2().
$parcelaPlaya = lw_precio_fmt(lw_parcela_tarifa_m2('playa'));
$parcelaOtras = lw_precio_fmt(lw_parcela_tarifa_m2('otras'));

$filasPrecio = [
    ['en' => 'Villa (roof of your choice)', 'v_en' => 'From ' . $precioTxt],
    ['en' => 'Plot — beachfront',           'v_en' => $parcelaPlaya . '/m²'],
    ['en' => 'Plot — other locations',      'v_en' => 'From ' . $parcelaOtras . '/m²'],
    ['en' => 'Closing costs',               'v_en' => 'Separate, in writing'],
];

$WA_NUM   = '6281138319862';
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text=' . rawurlencode("Hi, I'm interested in the " . $villa . ' from Lawang Tropical Properties.');
$WA_SHOW  = '+62 811-3831-9862';
$EMAIL    = 'sales@lawangproperties.com';
$CALENDLY = 'https://calendly.com/lawangproperties';
// Sin render propio todavía (Trinity/Temple): og:image y preload caen a una foto real del
// sitio (no del modelo concreto) en vez de a una ruta vacía — nunca un render inventado.
$ogImg = $portada ?? '/assets/img/lugar/costa.webp';
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($villa) ?> · Turnkey villa in Bali — Lawang Tropical Properties</title>
<meta name="description" content="<?= lw_e($villa) ?>: a new-build <?= lw_e($dormTxt) ?> villa, built on the plot you choose. Finishes, scope of works and call booking.">
<?php if (!$precio): ?>
<meta name="robots" content="noindex, nofollow"><!-- sin precio cerrado no se indexa -->
<?php endif; ?>
<link rel="canonical" href="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="<?= lw_e($villa) ?> · Turnkey villa in Bali">
<meta property="og:description" content="Turnkey new build, <?= lw_e($dormTxt) ?>. You choose the plot and finish; the price is locked in writing before you sign.">
<meta property="og:url" content="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($ogImg) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<link rel="preload" as="image" href="<?= lw_e($ogImg) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="preconnect" href="https://api.fontshare.com">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<link href="https://api.fontshare.com/v2/css?f[]=general-sans@400,500,600,700&display=swap" rel="stylesheet">
<!-- Widget real de reserva incrustado en la página (1-sep) — nada de saltar a
     calendly.com. defer, no bloquea el LCP de la foto de portada. -->
<link href="https://assets.calendly.com/assets/external/widget.css" rel="stylesheet">
<script src="https://assets.calendly.com/assets/external/widget.js" defer></script>
<style>
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
  --head:'Space Grotesk',sans-serif;
  --sans:'General Sans','Segoe UI',sans-serif;
  --gut:clamp(24px,7vw,140px);
}
*{box-sizing:border-box}
body{margin:0;background:var(--papel);color:var(--ink);font-family:var(--sans);
  line-height:1.55;-webkit-font-smoothing:antialiased;text-wrap:pretty}
img{max-width:100%;display:block}
a{color:inherit;text-decoration:none}
::selection{background:var(--verde);color:var(--papel)}
h1,h2{font-family:var(--head);font-weight:700;margin:0;letter-spacing:-.01em;line-height:1.05}
p{margin:0}
:focus-visible{outline:2px solid var(--verde);outline-offset:3px}

/* ── Idioma ───────────────────────────────────────────────────────────────────── */
/* Pivote a mercado australiano (2-sep): página solo en inglés, sin toggle. Se mantiene
   la regla (en vez de borrar el markup .i-es que aún queda en el FAQ/pie) porque es una
   línea y reversible por git — nunca un <span> ES visible por accidente. */
.i-es{display:none}

.wrap{max-width:1440px;margin-inline:auto;padding-inline:var(--gut)}

/* ── Nav ──────────────────────────────────────────────────────────────────────── */
.nav{position:sticky;top:0;z-index:50;background:rgba(245,240,230,.93);
  backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);border-bottom:1px solid var(--linea)}
.nav__in{display:flex;align-items:center;justify-content:space-between;gap:16px;padding-block:20px}
.nav__brand{font-family:var(--head);font-size:15px;font-weight:700;letter-spacing:.06em;
  text-transform:uppercase;white-space:nowrap}
.nav__right{display:flex;align-items:center;gap:16px}
.nav__links{display:flex;align-items:center;gap:22px}
.nav__links a{font-size:13px;font-weight:500;color:var(--ink2);text-transform:uppercase;
  letter-spacing:.04em;white-space:nowrap}
.nav__links a:hover{color:var(--verde)}
@media(max-width:940px){.nav__links{display:none}}
.btn{display:inline-flex;align-items:center;gap:10px;background:var(--verde);color:#fff;
  border:0;cursor:pointer;font-family:var(--sans);font-size:13px;font-weight:700;
  text-transform:uppercase;letter-spacing:.03em;padding:12px 20px;border-radius:4px;
  transition:background .16s ease}
.btn:hover{background:var(--verde-osc)}
.btn--block{width:100%;justify-content:center;padding:16px 24px;font-size:14px}

/* ── Layout de dos columnas ───────────────────────────────────────────────────── */
/* 300px (antes) se quedaba corto: el ancho útil tras el padding de .cal caía por debajo
   de los 320px que el propio widget de Calendly pide como mínimo, y salía con scroll
   horizontal interno. 360px deja sitio real. */
.grid{display:grid;grid-template-columns:minmax(0,1fr) 360px;gap:40px;align-items:start}
@media(max-width:1100px){.grid{grid-template-columns:minmax(0,1fr)}}

/* ── Hero ─────────────────────────────────────────────────────────────────────── */
/* La imagen es la prueba del producto en un vistazo: columna más ancha (.62/1.38),
   más alta y con sombra propia para que se despegue del papel en vez de ir a la par
   del texto. */
.hero{display:grid;grid-template-columns:minmax(0,.62fr) minmax(0,1.38fr);gap:56px;
  align-items:center;padding:72px 0 56px}
@media(max-width:900px){.hero{grid-template-columns:1fr;padding-top:44px}}
.hero__eyebrow{font-size:13px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--verde)}
.hero h1{font-size:clamp(34px,5vw,68px);margin-top:.3em;max-width:16ch}
/* Insignia sólida, no solo texto en color: es el dato que más pesa para quien
   compara varias fichas, así que tiene que competir en peso visual con el titular. */
.hero__precio{display:inline-flex;align-items:baseline;gap:6px;font-family:var(--head);
  font-size:30px;font-weight:700;color:#fff;background:var(--verde);
  padding:11px 22px;border-radius:100px;margin-top:.6em;
  box-shadow:0 14px 30px -10px rgba(72,91,55,.55)}
.hero__precio i{font-style:normal;font-family:var(--sans);font-size:14px;font-weight:600;
  opacity:.85}
.hero__sub{font-size:17px;color:var(--ink2);max-width:440px;margin-top:.6em}
.hero__ctas{display:flex;gap:12px;margin-top:24px;flex-wrap:wrap}
.btn--ghost{background:transparent;color:var(--ink);border:1px solid var(--verde-tenue)}
.btn--ghost:hover{background:var(--panel)}
.hero__fig{position:relative;border-radius:10px;overflow:hidden;aspect-ratio:4/3.6;
  box-shadow:0 24px 60px -20px rgba(46,52,55,.35)}
.hero__fig img{width:100%;height:100%;object-fit:cover}
/* Estado "renders en camino": mismo peso visual que una foto real, nunca un gris muerto. */
.hero__fig--pend{display:flex;flex-direction:column;align-items:center;justify-content:center;
  gap:14px;text-align:center;background:var(--verde-osc);color:var(--papel);padding:40px}
.hero__fig--pend svg{width:64px;height:auto;color:var(--verde-tenue)}
.hero__fig--pend-tt{font-family:var(--head);font-size:clamp(20px,2.4vw,26px);font-weight:700}
.hero__fig--pend-sub{font-size:14px;color:rgba(245,240,230,.72);max-width:34ch}

/* ── Ficha rápida ─────────────────────────────────────────────────────────────── */
.facts{display:grid;grid-template-columns:repeat(4,1fr);border-top:1px solid var(--linea);
  border-bottom:1px solid var(--linea)}
@media(max-width:640px){.facts{grid-template-columns:1fr 1fr}}
.facts__it{padding:24px 18px 24px 0}
.facts__lb{font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--ink2);margin-bottom:8px}
.facts__vl{font-family:var(--head);font-size:19px;font-weight:600}

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

/* ── Cross-selling (los 5 modelos) ───────────────────────────────────────────── */
/* Mismo patrón que .precio__tabla: borde inferior por fila, sin rejilla completa. */
.cross{border:1px solid var(--linea);border-radius:10px;overflow:hidden;margin-top:28px}
.cross__row{display:grid;grid-template-columns:56px 1fr auto;gap:18px;align-items:center;
  padding:16px 22px;border-bottom:1px solid var(--linea);background:var(--papel);
  transition:background .15s ease}
.cross__row:last-child{border-bottom:0}
a.cross__row:hover{background:var(--panel)}
.cross__row.is-current{background:var(--panel);cursor:default}
.cross__thumb{width:56px;height:56px;border-radius:6px;overflow:hidden;flex:0 0 auto;
  background:var(--verde-osc);display:flex;align-items:center;justify-content:center}
.cross__thumb img{width:100%;height:100%;object-fit:cover}
.cross__thumb svg{width:30px;height:auto;color:var(--verde-tenue)}
.cross__name{grid-row:1;grid-column:2;font-family:var(--head);font-size:16px;font-weight:600}
.cross__name i{font-style:normal;font-family:var(--sans);font-size:12px;font-weight:500;
  color:var(--verde);margin-left:6px}
.cross__specs{grid-row:2;grid-column:2;font-size:13px;color:var(--ink2)}
.cross__price{grid-row:1 / span 2;grid-column:3;text-align:right;font-family:var(--head);
  font-size:17px;font-weight:600;white-space:nowrap}
.cross__price i{display:block;font-style:normal;font-family:var(--sans);font-size:11.5px;
  font-weight:500;color:var(--ink2);margin-top:3px}
@media(max-width:560px){
  .cross__row{grid-template-columns:44px 1fr;padding:14px 16px}
  .cross__thumb{width:44px;height:44px}
  .cross__price{grid-row:3;grid-column:1 / span 2;text-align:left;margin-top:6px}
}

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

/* ── Acabados / alcance de obra (fondo panel) ────────────────────────────────── */
.panel{background:var(--panel);border-radius:12px;padding:clamp(32px,5vw,64px)}
.rows{display:grid;grid-template-columns:repeat(2,1fr);gap:18px;margin-top:36px}
@media(max-width:760px){.rows{grid-template-columns:1fr}}
.rows__it{background:var(--papel);border-radius:8px;padding:26px 22px}
.rows__it .n{font-family:var(--head);font-size:13px;color:var(--verde);display:block;margin-bottom:12px}
.rows__it h3{font-size:17px;font-weight:600;margin:0 0 8px}
.rows__it p{font-size:14px;color:var(--ink2)}
.rows__it .rows__precio{font-family:var(--head);font-size:16px;font-weight:700;
  color:var(--ink);margin-top:14px}

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
.ubic{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center}
@media(max-width:820px){.ubic{grid-template-columns:1fr}}
.ubic__pts{display:flex;flex-direction:column;gap:11px;margin-top:22px}
.ubic__pt{display:flex;justify-content:space-between;border-bottom:1px solid var(--linea);
  padding-bottom:9px;font-size:14px}
.ubic__pt span:first-child{color:var(--ink2)}
.ubic__pt span:last-child{font-weight:600}
.ubic__nota{font-size:12px;color:var(--ink2);margin-top:16px;font-style:italic}
.ubic__fig{border-radius:8px;overflow:hidden;aspect-ratio:4/5}
.ubic__fig img{width:100%;height:100%;object-fit:cover}

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

/* ── Reserva ──────────────────────────────────────────────────────────────────── */
.reserva{text-align:center;padding-bottom:20px}
.reserva h2{font-size:clamp(28px,4vw,44px);margin-top:.25em}
.reserva__desc{font-size:16px;color:var(--ink2);max-width:480px;margin:.85em auto 0}
.reserva__card{border:1px solid var(--linea);border-radius:10px;padding:40px 30px;
  background:var(--panel);max-width:620px;margin:32px auto 0}
.reserva__card b{display:block;font-size:15px;font-weight:600;margin-bottom:6px}
.reserva__card span{display:block;font-size:13px;color:var(--ink2);margin-bottom:22px}
.reserva__contact{display:flex;justify-content:center;gap:32px;margin-top:28px;font-size:14px;
  color:var(--ink2);flex-wrap:wrap}
.reserva__contact a:hover{color:var(--verde)}

/* ── Columna del calendario (fija en escritorio) ─────────────────────────────── */
/* max-height+overflow: en pantallas bajas (portátil, o con el aviso de cookies de
   consent.js todavía en pantalla, fixed a bottom:20px) el calendario no cabía entero
   y su nota final quedaba tapada. Verificado con capture real, no a ojo. */
.cal{position:sticky;top:96px;max-height:calc(100vh - 116px);overflow-y:auto;
  background:var(--papel);border:1px solid var(--linea);
  border-radius:12px;padding:22px 20px;box-shadow:0 12px 32px rgba(46,52,55,.1);
  display:flex;flex-direction:column;gap:16px}
@media(max-width:1100px){.cal{position:static;margin-top:44px;max-height:none}}
.cal__tt{font-size:15px;font-weight:700}
.cal__sub{font-size:12px;color:var(--ink2);margin-top:2px}
/* 320px es el mínimo real que pide el propio widget de Calendly; con la columna a
   360px y el padding de .cal (20px por lado) hay margen de sobra. */
.cal__widget{min-width:320px;height:600px}

/* ── Pie ──────────────────────────────────────────────────────────────────────── */
.pie{border-top:1px solid var(--linea)}
.pie .wrap{padding-block:34px;display:flex;justify-content:space-between;align-items:center;
  flex-wrap:wrap;gap:16px}
.pie__brand{font-family:var(--head);font-size:15px;font-weight:700;text-transform:uppercase}
.pie__legal{font-size:12px;color:var(--ink2);margin-top:2px}
.pie__links{font-size:13px;color:var(--ink2)}
.pie__links a:hover{color:var(--verde)}

@media print{ .nav,.cal{display:none} }
</style>
</head>
<body>

<header class="nav">
  <div class="wrap nav__in">
    <span class="nav__brand">Lawang Tropical Properties</span>
    <div class="nav__right">
      <nav class="nav__links">
        <a href="#modelos">The range</a>
        <a href="#acabados"><?= lw_i18n('Acabados', 'Finishes') ?></a>
        <a href="#ubicacion"><?= lw_i18n('Ubicación', 'Location') ?></a>
        <a href="#precios"><?= lw_i18n('Precio', 'Price') ?></a>
        <a href="#faq"><?= lw_i18n('Preguntas', 'FAQ') ?></a>
      </nav>
      <a class="btn" href="#agendar"><?= lw_i18n('Agendar llamada', 'Book a call') ?></a>
    </div>
  </div>
</header>

<div class="wrap">
<div class="grid">
<div>

  <!-- ── Hero ──────────────────────────────────────────────────────────────── -->
  <section class="hero">
    <div>
      <p class="hero__eyebrow">Bali, Indonesia — New build, turnkey</p>
      <h1><?= lw_e($villa) ?></h1>
      <p class="hero__precio"><i>From</i> <?= lw_e($precioTxt) ?></p>
      <p class="hero__sub"><?= lw_e($m['sub_en']) ?></p>
      <div class="hero__ctas">
        <a class="btn" href="#agendar">Book a call</a>
        <?php if (!$sinRender): ?>
        <a class="btn btn--ghost" href="#galeria">View gallery</a>
        <?php endif; ?>
      </div>
    </div>
    <?php if ($sinRender): ?>
    <!-- Estado "renders en camino" (Diseño, revisión previa 2-sep): nunca un placeholder
         gris ni un icono de imagen rota — un bloque a página completa con el mismo peso
         tipográfico del hero, honesto sobre lo que falta sin parecer un error. -->
    <figure class="hero__fig hero__fig--pend">
      <svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/><path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg>
      <p class="hero__fig--pend-tt">Renders in progress</p>
      <p class="hero__fig--pend-sub">Reserve before they exist — the price and spec are already locked in.</p>
    </figure>
    <?php else: ?>
    <figure class="hero__fig">
      <img src="<?= lw_e($portada) ?>" alt="<?= lw_e($villa) ?>, Lawang Tropical Properties: exterior with overflow pool" fetchpriority="high">
    </figure>
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

  <!-- ── Ficha rápida ──────────────────────────────────────────────────────── -->
  <div class="facts">
    <?php foreach ($facts as $f): ?>
    <div class="facts__it">
      <div class="facts__lb"><?= lw_e($f['en']) ?></div>
      <div class="facts__vl"><?= lw_e($f['v_en']) ?></div>
    </div>
    <?php endforeach; ?>
  </div>

  <!-- ── Cross-selling: los 5 modelos ─────────────────────────────────────────
       Pedido del owner (2-sep): entrar por cualquier ficha enseña las otras. Reutiliza
       el patrón de fila con borde inferior de .precio__tabla (Diseño, revisión previa) —
       nunca una tabla con rejilla completa. Un solo precio protagonista por fila (el más
       barato, techo Sirap); la diferencia de Bambú es nota secundaria, no una segunda
       cifra en paridad visual. Nunca el precio 2027 aquí (eso vive en la sección de
       Acabados de cada ficha, aparte del precio activo). -->
  <section class="sec" id="modelos">
    <p class="et">The range</p>
    <h2>Five models, one build system</h2>
    <p class="sec__desc">Same construction system and roof choice across the range — only the size changes the price. Pick what fits, or come back to this later.</p>
    <div class="cross">
      <?php foreach ($MODELOS as $mid => $mm):
        $mmImgs   = lw_modelo_imgs($mid);
        $mmThumb  = $mmImgs[0] ?? null;
        $mmActual = $mid === $m['id'];
        $mmSirap  = lw_precio_fmt(lw_techo_precio_activo($mm['techos']['sirap']));
        $mmBambu  = lw_precio_fmt(lw_techo_precio_activo($mm['techos']['bambu']));
        $mmTag    = $mmActual ? 'div' : 'a';
      ?>
      <<?= $mmTag ?> class="cross__row<?= $mmActual ? ' is-current' : '' ?>"<?= $mmActual ? '' : ' href="/modelo/' . lw_e($mid) . '"' ?>>
        <span class="cross__thumb">
          <?php if ($mmThumb): ?>
          <img src="<?= lw_e($mmThumb) ?>" alt="" loading="lazy">
          <?php else: ?>
          <svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="4"/></svg>
          <?php endif; ?>
        </span>
        <span class="cross__name"><?= lw_e($mm['nombre']) ?><?= $mmActual ? ' <i>— viewing now</i>' : '' ?></span>
        <span class="cross__specs"><?= lw_e($mm['villa_m2'] . 'm² + ' . $mm['terraza_m2'] . 'm² terrace · ' . $mm['dormitorios'] . ' bed · ' . $mm['banos'] . ' bath') ?></span>
        <span class="cross__price">From <?= lw_e($mmSirap) ?><i>Bambú roof from <?= lw_e($mmBambu) ?></i></span>
      </<?= $mmTag ?>>
      <?php endforeach; ?>
    </div>
    <p class="sec__desc" style="margin-top:18px;font-size:13px">Villa price only, roof included. Plot priced separately — see Investment below.</p>
  </section>

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

  <!-- ── Acabados / precio de techo ────────────────────────────────────────────
       Reescrito 2-sep: antes eran 3 acabados descriptivos sin precio propio. Ahora son
       los 2 techos reales que dio el owner, cada uno con su precio — "la cubierta es lo
       único que cambia el presupuesto" pasa de eslogan a precio de verdad. El aviso de
       la subida de 2027 vive AQUÍ, aparte del precio activo y sin el mismo peso visual
       (Diseño, revisión previa): nunca tachado ni junto a la cifra, como haría una
       landing de SaaS con descuento — esta página ya evita ese tono a propósito. -->
  <section class="sec panel" id="acabados">
    <div class="num">02</div>
    <p class="et">Finishes</p>
    <h2>The roof is the only thing that changes the price</h2>
    <p class="sec__desc">The rest of the villa doesn't vary between the two roof options. It's chosen before locking in numbers.</p>
    <div class="rows">
      <?php foreach ($m['techos'] as $tk => $t):
        $tPrecio = lw_precio_fmt(lw_techo_precio_activo($t));
      ?>
      <div class="rows__it">
        <span class="n"><?= $tk === 'sirap' ? '01' : '02' ?></span>
        <h3><?= lw_e($t['nombre']) ?></h3>
        <?php if (!empty($t['desc'])): ?><p><?= lw_e($t['desc']) ?></p><?php endif; ?>
        <p class="rows__precio">From <?= lw_e($tPrecio) ?></p>
      </div>
      <?php endforeach; ?>
    </div>
    <?php if ($antes2027): ?>
    <p class="sec__desc" style="margin-top:24px;font-size:13.5px">Prices shown are valid through 31 December 2026 (Bali time). Villa prices rise on 1 January 2027 — the plot rate above is unaffected.</p>
    <?php endif; ?>
  </section>

  <!-- ── Alcance de obra ───────────────────────────────────────────────────── -->
  <?php if (!empty($m['alcance'])): ?>
  <section class="sec">
    <div class="num">03</div>
    <p class="et"><?= lw_i18n('Alcance de obra — Qué incluye el precio', "Scope of works — What's included") ?></p>
    <div class="doscol">
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
          'The plot and closing costs (taxes, notary, permits) are quoted separately and detailed in writing before signing.'
        ) ?></p>
      </div>
    </div>
  </section>
  <?php endif; ?>

  <!-- ── Ubicación ──────────────────────────────────────────────────────────── -->
  <section class="sec ubic" id="ubicacion">
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
  </section>

  <!-- ── Proceso ────────────────────────────────────────────────────────────── -->
  <section class="sec panel">
    <h2><?= lw_i18n('Cómo se compra', "How it's purchased") ?></h2>
    <div class="pasos">
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
  </section>

  <!-- ── Precio ─────────────────────────────────────────────────────────────── -->
  <section class="sec precio" id="precios">
    <div class="precio__box">
      <p class="et"><?= lw_i18n('Inversión', 'Investment') ?></p>
      <h2><?= lw_i18n('El precio, cerrado antes de firmar', 'A fixed price before you sign') ?></h2>
      <div class="precio__tabla">
        <?php foreach ($filasPrecio as $r): ?>
        <div class="precio__fila">
          <span><?= lw_e($r['en']) ?></span>
          <span><?= lw_e($r['v_en']) ?></span>
        </div>
        <?php endforeach; ?>
      </div>
      <p class="precio__nota">Villa prices are confirmed directly by the developer. Plot rates above are an estimate, not a quote for a specific plot — taxes, notary and permit costs are separate and are all detailed in writing before you sign.</p>
      <div class="precio__cta"><a class="btn" href="#agendar">Request a quote</a></div>
    </div>
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
        <p class="i-es">La obra completa según el pliego del contratista, con el acabado de cubierta que
          elijas. La parcela y los gastos de compraventa (impuestos, notaría y licencias) se
          presupuestan aparte y se detallan por escrito antes de firmar nada.</p>
        <p class="i-en">The full build with the roof finish you choose, confirmed by the
          developer in writing before you sign. The plot and closing costs (taxes, notary,
          permits) are quoted separately.</p>
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
    <h2><?= lw_i18n('Reserva tu llamada', 'Book your call') ?></h2>
    <p class="reserva__desc"><?= lw_i18n(
      'Media hora. Te damos el presupuesto cerrado del acabado que te interese y las parcelas disponibles donde puede construirse.',
      "Half an hour. We'll give you a fixed quote for the finish you're interested in and the available plots it can be built on."
    ) ?></p>
    <div class="reserva__card">
      <b class="i-es">Calendario de disponibilidad</b><b class="i-en">Availability calendar</b>
      <span class="i-es">Elige día y hora directamente en el calendario.</span>
      <span class="i-en">Pick a day and time directly on the calendar.</span>
      <a class="btn" id="lw-cal-cta" href="#lw-cal">
        <?= lw_i18n('Ver horarios disponibles', 'See available times') ?>
      </a>
    </div>
    <div class="reserva__contact">
      <a href="mailto:<?= lw_e($EMAIL) ?>"><?= lw_e($EMAIL) ?></a>
      <a href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener"><?= lw_e($WA_SHOW) ?></a>
    </div>
  </section>

</div><!-- /col -->

<!-- ── Columna del calendario ─────────────────────────────────────────────── -->
<!-- Widget real de Calendly incrustado (1-sep, pedido del owner: "integración total",
     nada de saltar a calendly.com). Días y horas de aquí abajo son los REALES de la
     cuenta, no una vista previa — sustituye al calendario decorativo de la versión
     anterior, que nunca comprobaba disponibilidad real. -->
<aside class="cal" id="lw-cal">
  <div>
    <div class="cal__tt i-es">Reserva tu llamada</div><div class="cal__tt i-en">Book your call</div>
    <div class="cal__sub i-es">Media hora, sin compromiso.</div><div class="cal__sub i-en">Half an hour, no commitment.</div>
  </div>
  <?php
    // Calendly no deja cambiar su tipografía ni la disposición del calendario (eso es
    // suyo), pero sí tintarlo por parámetros en la URL — así el widget no desentona
    // con la paleta papel/tinta/verde del resto de la página (2-sep, pedido del owner).
    $calParams = http_build_query([
      'hide_gdpr_banner' => '1',
      'background_color' => 'F5F0E6', // --papel
      'text_color'       => '2E3437', // --ink
      'primary_color'    => '485B37', // --verde
    ]);
  ?>
  <div class="cal__widget calendly-inline-widget" data-url="<?= lw_e($CALENDLY) ?>?<?= $calParams ?>"></div>
</aside>

</div><!-- /grid -->
</div><!-- /wrap -->

<footer class="pie">
  <div class="wrap">
    <div>
      <div class="pie__brand">Lawang Tropical Properties</div>
      <div class="pie__legal">PT Tepi Sun Gai · Bali, Indonesia</div>
    </div>
    <div class="pie__links">
      <a href="/legal-es" class="i-es">Aviso legal y privacidad</a><a href="/legal" class="i-en">Legal &amp; privacy</a>
      · <span class="i-es">© 2026 Lawang Tropical Properties. Todos los derechos reservados.</span><span class="i-en">© 2026 Lawang Tropical Properties. All rights reserved.</span>
      · <a href="#" id="lw-cookies" class="i-es">Preferencias de cookies</a><a href="#" id="lw-cookies-en" class="i-en">Cookie preferences</a>
    </div>
  </div>
</footer>

<script src="/assets/consent.js?v=20260901" defer></script>
<script>
(function () {
  'use strict';
  var MODELO = <?= json_encode($m['id']) ?>;
  // 2-sep: los 5 modelos tienen precio real (antes solo Dali) — el pixel ya puede pujar
  // por valor, no solo por volumen. null si algún día vuelve a faltar el precio.
  var PRECIO_VALOR = <?= json_encode(lw_modelo_precio_desde($m)) ?>;
  var html = document.documentElement;

  // ── Píxel: ViewContent al cargar, con `value`/`currency` cuando hay precio cerrado. ──
  function track(ev, extra) {
    if (typeof window.lwTrack !== 'function') return;
    var p = Object.assign({content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO}, extra || {});
    if (PRECIO_VALOR !== null && !('value' in p)) { p.value = PRECIO_VALOR; p.currency = 'EUR'; }
    window.lwTrack(ev, p);
  }
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  // Clic al botón que lleva al widget: evento propio, no `Schedule` — es un clic hacia
  // el calendario, no una cita confirmada. Esa sí sale del propio widget, más abajo.
  var ctaCal = document.getElementById('lw-cal-cta');
  if (ctaCal) ctaCal.addEventListener('click', function () { track('AbrioCalendario', {}); });

  // ── Reserva confirmada DE VERDAD, no un clic: Calendly manda este mensaje al propio
  //    iframe cuando el visitante completa la reserva sin salir de la página. Con el
  //    <form> propio esto lo daba el `Lead` del envío; con Calendly incrustado, esto
  //    es lo más parecido que existe a esa confirmación real. ──────────────────────
  window.addEventListener('message', function (e) {
    // Igualdad exacta, no `indexOf`: con substring, "https://calendly.com.attacker.example"
    // también contiene "calendly.com" y colaba un Lead falso (cazado en revisión previa, 2-sep).
    if (e.origin !== 'https://calendly.com') return;
    if (!e.data || e.data.event !== 'calendly.event_scheduled') return;
    track('Lead', {});

    // Aviso al equipo (LAW-111): Calendly no da nombre/email en este mensaje, solo las
    // URIs del evento y del invitado — el endpoint las usa para un aviso "sin verificar",
    // ventas confirma en el propio Calendly. Best-effort: si falla, la reserva sigue
    // intacta en Calendly, solo se pierde el aviso automático.
    try {
      var payload = e.data.payload || {};
      var params = new URLSearchParams(location.search);
      var fd = new URLSearchParams();
      fd.set('modelo', MODELO);
      fd.set('source', params.get('utm_source') || '');
      fd.set('campana', params.get('utm_campaign') || '');
      fd.set('event_uri', (payload.event && payload.event.uri) || '');
      fd.set('invitee_uri', (payload.invitee && payload.invitee.uri) || '');
      fetch('/api/booking-notify.php', {method: 'POST', body: fd});
    } catch (err) { /* no bloquea el pixel ni la reserva */ }
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
