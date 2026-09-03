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

// Payload del configurador (2-sep, revisión previa Seguridad+Diseño): lista blanca
// explícita, campo a campo — nunca el array $MODELOS/$mm crudo, que trae el par
// now/y2027 sin resolver. Cada precio pasa por lw_techo_precio_activo()/lw_precio_fmt()
// aquí, en servidor, antes de tocar json_encode; el JS solo pinta lo que ya llegó resuelto.
$configuradorModelos = [];
foreach ($MODELOS as $cmId => $cm) {
    $cmImgs   = lw_modelo_imgs($cmId);
    $cmSirap  = $cm['techos']['sirap'];
    $cmBambu  = $cm['techos']['bambu'];
    $configuradorModelos[$cmId] = [
        'id'        => $cmId,
        'villa'     => 'Villa ' . $cm['nombre'],
        'sub'       => $cm['sub_en'] ?? $cm['sub'] ?? '',
        'sizeTxt'   => $cm['villa_m2'] . 'm² + ' . $cm['terraza_m2'] . 'm² terrace',
        'layoutTxt' => (int) $cm['dormitorios'] . ' bed · ' . (int) $cm['banos'] . ' bath',
        'precioTxt' => 'From ' . lw_precio_fmt(lw_modelo_precio_desde($cm)),
        'precioValor' => lw_modelo_precio_desde($cm),
        'thumb'     => $cmImgs[0] ?? null,
        'sinRender' => empty($cmImgs),
        // `precio` (numérico) es la ÚNICA fuente para la aritmética del panel; `precioTxt`
        // solo para pintar. El JS jamás re-parsea "€48,000" para volver a obtener 48000:
        // sería la misma copia con otra cara, y se rompe el día que cambie el formato
        // (hallazgo de Desarrollo, revisión previa 3-sep). Los dos salen de la MISMA
        // llamada a lw_techo_precio_activo(), así que no pueden discrepar.
        'techos'    => [
            'sirap' => [
                'nombre'    => $cmSirap['nombre'],
                'desc'      => $cmSirap['desc'] ?? '',
                'precio'    => lw_techo_precio_activo($cmSirap),
                'precioTxt' => lw_precio_fmt(lw_techo_precio_activo($cmSirap)),
            ],
            'bambu' => [
                'nombre'    => $cmBambu['nombre'],
                'desc'      => $cmBambu['desc'] ?? '',
                'precio'    => lw_techo_precio_activo($cmBambu),
                'precioTxt' => lw_precio_fmt(lw_techo_precio_activo($cmBambu)),
            ],
        ],
    ];
}

// Tarifa de parcela ORIENTATIVA. Hasta el 3-sep esto alimentaba una .precio__tabla propia
// dentro de Finishes; se DISUELVE porque con el panel de presupuesto pasaba a ser la
// TERCERA copia de las mismas cifras en la misma pantalla (tabla + filas del picker +
// panel), y ya hubo que corregir beachfront 200→250 en dos sitios el 2-sep. Ahora la cifra
// vive una sola vez como dato vivo (las filas del picker, con su data-rate renderizado por
// PHP) y una sola vez como texto legible por rastreadores y motores generativos, aquí
// abajo — que era la condición que puso Desarrollo para poder quitar la tabla: sin esto,
// las tarifas dejaban de existir como texto en la página.
$parcelaPlaya = lw_precio_fmt(lw_parcela_tarifa_m2('beachfront'));
$parcelaOtras = lw_precio_fmt(lw_parcela_tarifa_m2('otras'));
$resumenTarifas = 'Plot rates: beachfront ' . $parcelaPlaya . '/m², all other locations '
    . $parcelaOtras . '/m². Indicative rates per m², not a quote for a specific plot.';

// Opciones del configurador y estado inicial del panel, los dos desde la fuente única de
// lib.php. El estado inicial se pinta EN SERVIDOR a propósito: sin JS (o con el JS aún sin
// ejecutar) el panel enseña el precio real de la villa y una instrucción en la línea de
// parcela, nunca huecos vacíos que se leen como página rota.
$PICKER  = lw_picker_opciones();

// ── Preselección: la opción MÁS BARATA de cada paso, marcada al entrar ────────────────
// Pedido del owner (3-sep): "siempre deja marcada la primera opción, que debe ser la más
// barata". No se escriben a mano: se DERIVAN ordenando por precio, así que el día que una
// tarifa cambie el orden, la preselección se mueve sola en vez de quedarse mintiendo.
// Consecuencia buscada: el formulario nunca arranca sin cifra, y la cifra de arranque es el
// suelo real de la página — nunca una combinación cara presentada como punto de partida.
$techosOrd = $m['techos'];
uasort($techosOrd, function ($a, $b) { return lw_techo_precio_activo($a) <=> lw_techo_precio_activo($b); });
$techoIni = array_key_first($techosOrd);

// Los modelos también se ordenan por precio para el paso 1: hoy el catálogo ya está en
// orden ascendente, pero por casualidad, no por invariante.
$modelosOrd = $MODELOS;
uasort($modelosOrd, function ($a, $b) { return lw_modelo_precio_desde($a) <=> lw_modelo_precio_desde($b); });

// Isla y vista: la vista más barata de Bali. Bali y Sumba están al mismo tramo (125 €/m²),
// así que "más barata" no las separa — manda Bali por ser el catálogo con vistas.
$vistasOrd = $PICKER['view'];
uasort($vistasOrd, function ($a, $b) { return $a['rate'] <=> $b['rate']; });
$islaIni  = 'bali';
$vistaIni = array_key_first($vistasOrd);
$m2Ini    = min(LW_M2_PRESETS);

$estIni  = lw_estimacion($m, $techoIni, $islaIni, $vistaIni, $m2Ini);

// ── Formulario de un campo por pantalla — SOLO DALI (3-sep, decisión del owner) ──────
// "Trabaja en el modelo Dali por ahora y no en todas, cuando tengamos todos los cambios
// los replicamos a todos." Las otras cuatro villas mantienen el bloque de cuatro secciones
// desplegado esta misma mañana, intacto. Replicar = borrar esta condición, no reescribir
// nada: las dos ramas comparten estado, aritmética, payload y endpoint; lo único que cambia
// es cómo se presentan los mismos controles.
$wizard = ($m['id'] === 'dali');

/**
 * El panel de presupuesto, en UNA sola definición.
 *
 * Lo pintan las dos ramas (el formulario de Dali y el bloque de secciones de las otras
 * cuatro). Duplicar este marcado sería duplicar el rotulado legal que costó una revisión
 * entera: la etiqueta del total que cambia de estado, el "no es una oferta", el PPN. La
 * segunda copia envejecería sola en cuanto Legal retocara una frase.
 */
$renderPanel = function () use ($nombre, $m, $techoIni, $estIni, $antes2027, $PICKER, $vistaIni, $m2Ini) {
    // Con la preselección del 3-sep el panel ya arranca COMPLETO, así que su estado inicial
    // de servidor tiene que decir la verdad: línea de parcela con cifra y etiqueta de total
    // "villa + parcela". Antes arrancaba sin parcela y esos dos textos eran fijos.
    $tieneParcela = $estIni['parcela'] !== null;
    $vistaLb = strtolower($PICKER['view'][$vistaIni]['label']);
    ?>
    <div class="est" id="lw-estimacion">
      <div class="est__head">
        <span class="est__tt">Your estimate</span>
        <span class="est__flag">Indicative only — not a quote</span>
      </div>

      <div class="est__fila">
        <span class="est__lb" id="lw-est-villa-lb">Villa — <?= lw_e($nombre . ', ' . $m['techos'][$techoIni]['nombre']) ?> roof
          <?php /* 3-sep, capa 1 (Legal): "Starting figure for this roof, confirmed by the
                 developer in writing" no distinguía si lo confirmado por escrito es la
                 cifra que el visitante tiene DELANTE o el precio final antes de firmar. Era
                 la única frase del panel que empujaba hacia "precio cerrado", y encima
                 pegada al número. */ ?>
          <i>Today's starting figure for this roof. Your final price is confirmed by the developer in writing before you sign. Indonesian VAT (PPN) included.</i></span>
        <span class="est__vl" id="lw-est-villa">From <?= lw_e(lw_precio_fmt($estIni['villa'])) ?></span>
      </div>

      <div class="est__fila">
        <span class="est__lb" id="lw-est-parcela-lb"><?= $tieneParcela
            ? lw_e('Plot — ' . $vistaLb . ', ' . number_format($estIni['m2'], 0, '.', ',') . ' m² at ' . lw_precio_fmt($estIni['tarifa']) . '/m²')
            : 'Plot' ?>
          <i>Indicative rate per m². Not a quote for a specific plot.</i></span>
        <span class="est__vl<?= $tieneParcela ? '' : ' is-pend' ?>" id="lw-est-parcela"><?= $tieneParcela
            ? lw_e(lw_precio_fmt($estIni['parcela'])) : 'Choose an island and a size' ?></span>
      </div>

      <div class="est__fila">
        <span class="est__lb" id="lw-est-extras-lb">Extras — none selected</span>
        <span class="est__vl is-pend" id="lw-est-extras">Priced on the call</span>
      </div>

      <div class="est__fila">
        <span class="est__lb">Notary, permits and transfer costs</span>
        <span class="est__vl is-pend">Separate, in writing</span>
      </div>

      <!-- aria-live en el CONTENEDOR, no solo en el importe (Desarrollo, capa 1 de deploy):
           la etiqueta es quien alterna entre "Villa only — plot not included yet" e
           "Indicative starting figure, villa + plot", y con la región viva solo en la cifra
           un lector de pantalla anunciaba el importe sin decir nunca si la parcela estaba
           dentro. Toda la defensa del panel es esa etiqueta: dejarla muda la anula. -->
      <div class="est__total" aria-live="polite">
        <span class="est__lb" id="lw-est-total-lb"><?= $tieneParcela
            ? 'Indicative starting figure, villa + plot' : 'Villa only — plot not included yet' ?></span>
        <span class="est__vl" id="lw-est-total">from around <?= lw_e(lw_precio_fmt($estIni['total'])) ?></span>
      </div>
      <div class="est__pie">
        <p id="lw-est-excluye">Excludes notary, permits and transfer costs.</p>
        <?php /* Recortado a petición del owner (3-sep). Se conserva lo que hace trabajo
               legal —no es oferta, no es reserva, el precio final depende de la parcela y
               se confirma por escrito— y se van la frase que repetía el rótulo "Indicative
               only" de la cabecera y la coletilla de vigencia de 2026, que el owner también
               ha retirado del paso del techo. Ver la nota del final del turno: sin ninguna
               mención a 2027, un lead que reserve en diciembre y sea atendido en enero no
               tiene aviso escrito de la subida. */ ?>
        <p>Not an offer or a reservation. Your final price depends on the specific plot and is confirmed in writing before you sign.</p>
      </div>
      <div class="est__cta"><a class="btn btn--block" href="#agendar">Book a call for the real numbers</a></div>
    </div>
<?php };

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
<title><?= lw_e($villa . $TITULO_SUFIJO) ?></title>
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
   la regla (en vez de borrar el markup .i-es que aún queda en el FAQ/reserva/pie) porque
   es una línea y reversible por git — nunca un <span> ES visible por accidente.
   !important a propósito: sin él, selectores más específicos definidos MÁS ABAJO en esta
   misma hoja (`.reserva__card b`, `.reserva__card span`, que fijan su propio `display`)
   ganaban por especificidad y el español volvía a verse — encontrado en QA responsive del
   2-sep, español e inglés apilados en la tarjeta de reserva. Este selector no compite por
   estética, solo apaga contenido muerto: nada le disputa el `!important` a propósito. */
.i-es{display:none !important}

.wrap{max-width:1440px;margin-inline:auto;padding-inline:var(--gut)}

/* ── Nav ──────────────────────────────────────────────────────────────────────── */
.nav{position:sticky;top:0;z-index:50;background:rgba(245,240,230,.93);
  backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);border-bottom:1px solid var(--linea)}
.nav__in{display:flex;align-items:center;justify-content:space-between;gap:16px;padding-block:20px}
.nav__brand{display:block;height:18px;width:auto}
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
/* 1400px, no 900: la columna del calendario (.grid, 360px fijos desde los 1100px) deja el
   hero apretado en un intervalo que el breakpoint viejo no cubría — encontrado en QA
   responsive del 2-sep, texto partido a media palabra entre ~1100 y ~1300px de viewport
   real (la columna de texto del hero se queda en ~220-340px de ancho útil). Por debajo de
   1100px el sidebar ya baja y el hero tiene toda la página para él, así que apilarlo hasta
   1400px no pierde nada ahí — ver el mismo criterio en .grid más abajo. */
@media(max-width:1400px){.hero{grid-template-columns:1fr;padding-top:44px}}
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
/* Mismo bug de especificidad que el picker-toggle (`[hidden]` pierde contra `.btn{display:
   inline-flex}`): el link a la galería se oculta con `hidden` cuando no hay renders
   todavía, selector por id para que gane seguro. */
#lw-hero-gallery-link[hidden]{display:none}
.btn--ghost{background:transparent;color:var(--ink);border:1px solid var(--verde-tenue)}
.btn--ghost:hover{background:var(--panel)}
.hero__fig{position:relative;border-radius:10px;overflow:hidden;aspect-ratio:4/3.6;
  box-shadow:0 24px 60px -20px rgba(46,52,55,.35)}
.hero__fig img{width:100%;height:100%;object-fit:cover}
/* Crossfade del configurador (2-sep): seleccionarModelo() precarga la imagen y solo
   entonces baja la opacidad a 0 y la sube — nunca un "flash" del contenido a medio
   cargar. Mismo mecanismo sirve para pasar de foto real a la ilustración "pending". */
.hero__fig.is-swapping{opacity:0}
.hero__fig,.hero__fig--pend{transition:opacity .18s ease}
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
/* Dos estados (Diseño, revisión previa 2-sep): is-current = el modelo DE ESTA PÁGINA
   (fijo, servidor, solo la etiqueta ".cross__tag" — About/Galería/Alcance de abajo
   siguen hablando de él pase lo que pase arriba). is-configured = lo que se está
   previsualizando ahora en el configurador (fondo sólido, lo mueve el JS). Al cargar
   la página las dos coinciden en la misma fila. */
.cross__row.is-configured{background:var(--panel)}
.cross__tag{white-space:nowrap}
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
.ubic__intro{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center}
@media(max-width:820px){.ubic__intro{grid-template-columns:1fr}}
.ubic__pts{display:flex;flex-direction:column;gap:11px;margin-top:22px}
.ubic__pt{display:flex;justify-content:space-between;border-bottom:1px solid var(--linea);
  padding-bottom:9px;font-size:14px}
.ubic__pt span:first-child{color:var(--ink2)}
.ubic__pt span:last-child{font-weight:600}
.ubic__nota{font-size:12px;color:var(--ink2);margin-top:16px;font-style:italic}

/* ── Picker (extras/isla/vista) — siempre visible, sin botón (2-sep, pedido owner) ── */
.picker__group{margin-top:32px}
.picker__gh{display:flex;align-items:baseline;justify-content:space-between;gap:12px}
.picker__gh h4{font-family:var(--head);font-size:15px;font-weight:600;margin:0}
.picker__status{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--verde-tenue)}
/* Los estatus que llevan el VALOR elegido (3-sep) no van en versalitas: "350 m²" salía
   como "350 M²" y un nombre propio de acabado tampoco se lee bien gritado. Los estatus
   fijos ("PRICED ON THE CALL") sí siguen en mayúsculas, que es su registro. */
.picker__status--val{text-transform:none;letter-spacing:.02em;font-size:11.5px}
.picker__rows{border:1px solid var(--linea);border-radius:10px;overflow:hidden;margin-top:12px}
.picker__row{display:flex;align-items:center;justify-content:space-between;width:100%;
  text-align:left;border:0;border-bottom:1px solid var(--linea);background:var(--papel);
  font:inherit;font-size:14.5px;color:var(--ink);padding:14px 20px;cursor:pointer;
  transition:background .15s ease}
.picker__row:last-child{border-bottom:0}
.picker__row:hover{background:var(--panel)}
.picker__row.is-on{background:var(--verde);color:#fff}
.picker__row.is-on span,.picker__row.is-on i{color:#fff}
.picker__row span{font-family:var(--head);font-weight:600;font-size:13.5px;color:var(--ink2)}
.picker__row i{font-style:normal;font-size:11.5px;color:var(--ink2);margin-left:10px}
.picker__group[hidden]{display:none}
.picker__nota{font-size:12.5px;color:var(--ink2);margin-top:20px;max-width:60ch}
.ubic__fig{border-radius:8px;overflow:hidden;aspect-ratio:4/5}
.ubic__fig img{width:100%;height:100%;object-fit:cover}

/* ── Configurador con presupuesto (3-sep) ────────────────────────────────────────
   Controles NATIVOS, no <button aria-pressed> (Desarrollo, revisión previa): techo,
   isla y vista son "elige uno de N" y eso es un radiogroup — dos botones con
   aria-pressed se anuncian como dos interruptores independientes y la exclusividad se
   pierde para un lector de pantalla. El input real va oculto visualmente pero sigue
   recibiendo foco; lo que se ve es el <label>.
   El estado pintado se apoya en la CLASE que pone el JS como enganche principal y en
   :checked solo como refuerzo — nunca al revés: el tráfico de esta landing llega del
   WebView in-app de Instagram/Facebook, donde un selector moderno que el motor no
   entiende tira la regla entera y el visitante deja de ver qué eligió. */
.cfg__set{border:0;margin:0;padding:0;min-width:0}
.cfg__set legend{padding:0}
.cfg__in{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;
  clip:rect(0 0 0 0);white-space:nowrap;border:0}
/* Foco visible: el input está oculto, así que el anillo lo pinta la etiqueta hermana. */
.cfg__in:focus-visible + .rows__it,
.cfg__in:focus-visible + .picker__row{outline:2px solid var(--verde);outline-offset:3px}

/* Tarjeta de techo seleccionable — misma .rows__it de siempre, ahora como <label>. */
label.rows__it{display:block;cursor:pointer;border:1px solid transparent;
  transition:background .15s ease,border-color .15s ease}
label.rows__it:hover{border-color:var(--verde-tenue)}
.rows__it.is-on{background:var(--verde);border-color:var(--verde)}
.cfg__in:checked + .rows__it{background:var(--verde);border-color:var(--verde)}
.rows__it.is-on h3,.rows__it.is-on p,.rows__it.is-on .rows__precio{color:#fff}
.cfg__in:checked + .rows__it h3,.cfg__in:checked + .rows__it p,
.cfg__in:checked + .rows__it .rows__precio{color:#fff}
.rows__it.is-on p,.cfg__in:checked + .rows__it p{color:rgba(255,255,255,.82)}

/* La fila del picker pasa a ser <label>; conserva su aspecto exacto. */
label.picker__row{cursor:pointer}
.cfg__in:checked + .picker__row{background:var(--verde);color:#fff}
.cfg__in:checked + .picker__row span,.cfg__in:checked + .picker__row i{color:#fff}

/* Paso 4: tamaño de parcela. Preajustes con la misma fila clicable del resto — un
   inversor que todavía no tiene parcela no sabe cuántos m² quiere, y un campo vacío
   ahí mata el paso (Diseño). El campo libre solo aparece al elegir "Other". */
.cfg__m2{display:flex;align-items:center;justify-content:space-between;gap:12px;
  padding:14px 20px;border-top:1px solid var(--linea);background:var(--papel)}
.cfg__m2 label{font-family:var(--head);font-weight:600;font-size:13.5px;color:var(--ink2)}
.cfg__m2 span{display:inline-flex;align-items:baseline;gap:6px;font-family:var(--head);
  font-weight:600;font-size:15px}
.cfg__m2 input{width:5.5em;border:0;border-bottom:1px solid var(--linea-fuerte);
  background:transparent;font:inherit;font-family:var(--head);font-weight:600;font-size:15px;
  color:var(--ink);text-align:right;padding:2px 0;-moz-appearance:textfield}
.cfg__m2 input::-webkit-outer-spin-button,
.cfg__m2 input::-webkit-inner-spin-button{-webkit-appearance:none;margin:0}
.cfg__m2[hidden]{display:none}
.cfg__aviso{font-size:12.5px;color:var(--verde);margin-top:10px}
.cfg__aviso[hidden]{display:none}

/* ── Panel "Your estimate" ───────────────────────────────────────────────────────
   Estático al final del bloque y ANTES del marcador de transición, ni sticky ni en la
   columna del calendario (Diseño): esa columna ya va justa —el widget son 600px fijos
   dentro de un max-height de viewport— y además ya posee la única llamada a la acción
   de la página. Mismo idioma visual que la .precio__tabla que la sección ya usaba. */
.est{border:1px solid var(--linea-fuerte);border-radius:12px;background:var(--papel);
  overflow:hidden;margin-top:36px;box-shadow:0 12px 32px -18px rgba(46,52,55,.3)}
.est__head{display:flex;align-items:baseline;justify-content:space-between;gap:14px;
  flex-wrap:wrap;padding:20px 26px;border-bottom:1px solid var(--linea);background:var(--panel)}
.est__tt{font-family:var(--head);font-size:15px;font-weight:700;letter-spacing:.06em;
  text-transform:uppercase}
.est__flag{font-size:12px;color:var(--ink2)}
.est__fila{display:flex;justify-content:space-between;align-items:baseline;gap:18px;
  padding:16px 26px;border-bottom:1px solid var(--linea)}
.est__lb{font-size:14px}
.est__lb i{display:block;font-style:normal;font-size:12.5px;color:var(--ink2);margin-top:4px;
  max-width:46ch}
.est__vl{font-family:var(--head);font-size:18px;font-weight:600;white-space:nowrap;
  text-align:right;transition:opacity .15s ease}
.est__vl.is-pend{font-family:var(--sans);font-size:13px;font-weight:500;color:var(--ink2)}
.est__vl.is-swapping{opacity:0}
.est__total{display:flex;justify-content:space-between;align-items:baseline;gap:18px;
  padding:22px 26px;background:var(--panel)}
.est__total .est__lb{font-size:13px;text-transform:uppercase;letter-spacing:.04em;
  color:var(--ink2)}
.est__total .est__vl{font-size:26px;font-weight:700}
.est__pie{padding:0 26px 24px;background:var(--panel)}
.est__pie p{font-size:12.5px;color:var(--ink2);max-width:64ch;margin-top:10px}
.est__cta{padding:24px 26px;border-top:1px solid var(--linea)}
@media(max-width:560px){
  .est__fila,.est__total{flex-direction:column;align-items:flex-start;gap:6px}
  .est__vl{text-align:left}
}

/* ── Formulario de un campo por pantalla (3-sep, solo Dali) ──────────────────────
   El owner pidió que el configurador viva "en un solo sitio, que no se mueva y sea como
   un formulario que avanza por campos". Consecuencias de diseño, no preferencias:
   · Se acabó el auto-scroll. Era la mecánica de la versión de secciones y aquí sería
     exactamente lo que se ha pedido evitar.
   · El área de la pregunta lleva min-height: sin ella, pasar de 5 villas a 2 techos
     encoge la tarjeta 90px y el total salta bajo el cursor justo cuando lo vas a leer.
   · El total y su etiqueta de estado NUNCA se ocultan, en ningún paso. Es lo que sostiene
     todo el rotulado legal del panel: una captura del paso 2 tiene que explicarse sola.
   · El desglose por líneas aparece en el último paso, cuando ya hay algo que desglosar. */
.wiz{border:1px solid var(--linea-fuerte);border-radius:14px;background:var(--papel);
  overflow:hidden;box-shadow:0 18px 44px -26px rgba(46,52,55,.4);max-width:760px}
.wiz__head{display:flex;align-items:baseline;justify-content:space-between;gap:14px;
  flex-wrap:wrap;padding:18px 26px;border-bottom:1px solid var(--linea);background:var(--panel)}
.wiz__tt{font-family:var(--head);font-size:13px;font-weight:700;letter-spacing:.08em;
  text-transform:uppercase;color:var(--verde)}
.wiz__flag-in{font-size:12px;color:var(--ink2)}
.wiz__cuerpo{padding:26px;min-height:288px}
@media(max-width:560px){.wiz__cuerpo{padding:20px 16px;min-height:0}.wiz__head{padding:16px}}
.wiz__q{font-family:var(--head);font-size:21px;font-weight:700;line-height:1.15;margin:0 0 4px}
/* El foco de la pregunta es PROGRAMÁTICO y existe solo para que un lector de pantalla
   anuncie qué se está preguntando al cambiar de paso. Un titular no es un control: pintarle
   el anillo de foco encima deja un recuadro raro tras cada clic de ratón, sin informar de
   nada. El anillo sigue intacto en los controles reales, que es donde importa. */
.wiz__q:focus{outline:none}
.wiz__ayuda{font-size:13.5px;color:var(--ink2);max-width:52ch;margin-bottom:18px}
.wiz__campo[hidden]{display:none}

/* Fila de opción, común a los cinco pasos: un solo patrón para todo el formulario. */
.wiz__op{display:grid;grid-template-columns:1fr auto;gap:4px 16px;align-items:center;
  width:100%;text-align:left;border:1px solid var(--linea);border-radius:8px;
  background:var(--papel);font-size:15px;color:var(--ink);padding:13px 18px;cursor:pointer;
  margin-bottom:8px;transition:background .15s ease,border-color .15s ease}
.wiz__op:last-child{margin-bottom:0}
.wiz__op:hover{border-color:var(--verde-tenue);background:var(--panel)}
.cfg__in:checked + .wiz__op{background:var(--verde);border-color:var(--verde);color:#fff}
.wiz__op.is-on{background:var(--verde);border-color:var(--verde);color:#fff}
.wiz__nom{font-family:var(--head);font-weight:600}
.wiz__nom i{font-style:normal;font-family:var(--sans);font-size:12px;font-weight:500;
  color:var(--verde);margin-left:8px}
.cfg__in:checked + .wiz__op .wiz__nom i,.wiz__op.is-on .wiz__nom i{color:rgba(255,255,255,.9)}
.wiz__sub{grid-column:1;font-size:12.5px;color:var(--ink2)}
.wiz__cifra{grid-column:2;grid-row:1 / span 2;font-family:var(--head);font-size:15px;
  font-weight:600;white-space:nowrap;text-align:right}
.cfg__in:checked + .wiz__op .wiz__sub,.wiz__op.is-on .wiz__sub{color:rgba(255,255,255,.82)}
.cfg__in:focus-visible + .wiz__op{outline:2px solid var(--verde);outline-offset:3px}
/* Foto de la opción — 150×100 (3-sep, owner: "más grandes, dale más presencia porque ahora
   no se ve"). Venía de una miniatura de 44px en la que no se distinguía nada de la villa.
   Mismo componente para el paso del modelo y para el del techo cuando tenga fotos. */
.wiz__foto{grid-row:1 / span 2;grid-column:1;width:150px;height:94px;border-radius:8px;
  overflow:hidden;background:var(--verde-osc);display:flex;align-items:center;
  justify-content:center;flex:0 0 auto}
.wiz__foto img{width:100%;height:100%;object-fit:cover}
.wiz__foto svg{width:44px;height:auto;color:var(--verde-tenue)}
.wiz__op--mod,.wiz__op--foto{grid-template-columns:150px 1fr auto;padding:10px;margin-bottom:6px}
/* La foto ocupa dos filas de 47px, así que centrar cada celda en su fila separaba el nombre
   y las specs con un hueco muerto en medio. Se pegan al centro: nombre abajo de su fila,
   specs arriba de la suya. */
.wiz__op--mod .wiz__nom,.wiz__op--foto .wiz__nom{grid-column:2;grid-row:1;font-size:17px;align-self:end}
.wiz__op--mod .wiz__sub,.wiz__op--foto .wiz__sub{grid-column:2;grid-row:2;align-self:start;margin-top:2px}
.wiz__op--mod .wiz__cifra,.wiz__op--foto .wiz__cifra{grid-column:3;grid-row:1 / span 2}
@media(max-width:560px){
  .wiz__op{grid-template-columns:1fr}
  .wiz__cifra{grid-column:1;grid-row:auto;text-align:left;margin-top:4px}
  /* En móvil la foto pasa a ocupar todo el ancho, encima del texto: a 150px de ancho fijo
     dentro de una columna de 343 no quedaba sitio legible para nombre, specs y precio. */
  .wiz__op--mod,.wiz__op--foto{grid-template-columns:1fr}
  .wiz__foto{grid-row:auto;grid-column:1;width:100%;height:150px;margin-bottom:10px}
  .wiz__op--mod .wiz__nom,.wiz__op--foto .wiz__nom,
  .wiz__op--mod .wiz__sub,.wiz__op--foto .wiz__sub,
  .wiz__op--mod .wiz__cifra,.wiz__op--foto .wiz__cifra{grid-column:1;grid-row:auto}
}

/* Sub-pregunta de vista: aparece dentro del paso de ubicación al elegir Bali. */
.wiz__sub-q{margin-top:20px;padding-top:18px;border-top:1px solid var(--linea)}
.wiz__sub-q[hidden]{display:none}
.wiz__sub-q h4{font-family:var(--head);font-size:14px;font-weight:600;margin:0 0 12px}

/* Campo libre de m², dentro del paso de parcela. */
.wiz__m2{display:flex;align-items:center;gap:10px;margin-top:12px;padding:12px 18px;
  border:1px dashed var(--linea-fuerte);border-radius:8px}
.wiz__m2[hidden]{display:none}
.wiz__m2 label{font-size:13.5px;color:var(--ink2)}
.wiz__m2 input{width:6em;border:0;border-bottom:1px solid var(--linea-fuerte);
  background:transparent;font:inherit;font-family:var(--head);font-weight:600;font-size:16px;
  color:var(--ink);text-align:right;padding:2px 0;-moz-appearance:textfield}
.wiz__m2 input::-webkit-outer-spin-button,
.wiz__m2 input::-webkit-inner-spin-button{-webkit-appearance:none;margin:0}

/* Resumen: total siempre; el desglose solo en el último paso.
   El panel es el MISMO componente que usa la rama de secciones (un solo marcado, ver
   $renderPanel en el PHP), así que aquí solo se le quitan la caja y el margen propios: ya
   está dentro de la tarjeta del formulario, que pone los suyos. */
.wiz__resumen{border-top:1px solid var(--linea);background:var(--panel)}
.wiz .est{margin-top:0;border:0;border-radius:0;box-shadow:none;background:transparent}
/* El calificador ya va en la cabecera de la tarjeta, visible en los cinco pasos. Repetirlo
   aquí solo lo duplicaba en el último. */
.wiz .est__head{display:none}
.wiz .est__fila{display:none}
.wiz.is-final .est__fila{display:flex}
/* El párrafo legal largo vive con el desglose, en el último paso. En los intermedios el
   calificador lo lleva la cabecera de la tarjeta ("Indicative only — not a quote"), que sí
   está en los cinco: la captura sigue explicándose sola, y el paso 1 —el más alto, por las
   fotos de villa— recupera ~110px para que el total quepa en pantalla. */
.wiz .est__pie{display:none;padding:0 26px 20px}
.wiz.is-final .est__pie{display:block}
.wiz .est__total{padding:18px 26px}
.wiz .est__cta{display:none;border-top:1px solid var(--linea)}
.wiz.is-final .est__cta{display:block}
@media(max-width:560px){.wiz .est__total,.wiz .est__pie,.wiz .est__fila{padding-inline:16px}}

/* Barra de navegación. */
.wiz__nav{display:flex;align-items:center;justify-content:space-between;gap:12px;
  padding:16px 26px;border-top:1px solid var(--linea)}
@media(max-width:560px){.wiz__nav{padding:14px 16px}}
.wiz__atras{border:0;background:transparent;font:inherit;font-size:13px;font-weight:600;
  color:var(--ink2);cursor:pointer;padding:8px 4px;text-transform:uppercase;letter-spacing:.04em}
.wiz__atras:hover{color:var(--verde)}
.wiz__atras[disabled]{opacity:.35;cursor:default}
.wiz__atras[disabled]:hover{color:var(--ink2)}
.wiz__puntos{display:flex;gap:6px}
.wiz__punto{width:6px;height:6px;border-radius:50%;background:var(--linea-fuerte)}
.wiz__punto.is-on{background:var(--verde)}
.wiz__punto.is-hecho{background:var(--verde-tenue)}

/* Movimiento: el fichero no tenía ni una media query de reduced-motion — el crossfade
   del hero tampoco la respetaba. Se cierra aquí para las dos cosas a la vez. */
@media(prefers-reduced-motion:reduce){
  *,*::before,*::after{transition-duration:.001ms !important;animation-duration:.001ms !important}
  .hero__fig.is-swapping,.est__vl.is-swapping{opacity:1}
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
    <a href="/" aria-label="Lawang Tropical Properties"><img class="nav__brand" src="/assets/img/lawang-logo-v3-dark.webp" alt="Lawang Tropical Properties"></a>
    <div class="nav__right">
      <nav class="nav__links">
        <!-- Etiquetas alineadas con los pasos del configurador (3-sep). "Finishes & price"
             apuntaba a #acabados, que ahora es el paso 2 "Roof" — renumerar las secciones
             sin tocar el menú lo deja mintiendo (hallazgo de Diseño). #lw-estimacion entra
             en el menú porque es el desenlace del bloque: hasta hoy no había nada que
             enlazar ahí. -->
        <?php if ($wizard): ?>
        <a href="#lw-wizard">Build your estimate</a>
        <?php else: ?>
        <a href="#modelos">The range</a>
        <a href="#acabados">Roof</a>
        <a href="#lw-estimacion">Your estimate</a>
        <?php endif; ?>
        <a href="#ubicacion"><?= lw_i18n('Ubicación', 'Location') ?></a>
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
  <!-- IDs estables (2-sep, configurador): seleccionarModelo() los actualiza en vivo al
       elegir otro modelo en "The Range" — ver el porqué de todo el bloque en el script
       de cierre de página. -->
  <section class="hero">
    <div>
      <p class="hero__eyebrow">Bali, Indonesia — New build, turnkey</p>
      <h1 id="lw-hero-title"><?= lw_e($villa) ?></h1>
      <p class="hero__precio"><i>From</i> <span id="lw-hero-price"><?= lw_e($precioTxt) ?></span></p>
      <p class="hero__sub" id="lw-hero-sub"><?= lw_e($m['sub_en']) ?></p>
      <div class="hero__ctas">
        <a class="btn" href="#agendar">Book a call</a>
        <a class="btn btn--ghost" href="#galeria" id="lw-hero-gallery-link"<?= $sinRender ? ' hidden' : '' ?>>View gallery</a>
      </div>
    </div>
    <?php if ($sinRender): ?>
    <!-- Estado "renders en camino" (Diseño, revisión previa 2-sep): nunca un placeholder
         gris ni un icono de imagen rota — un bloque a página completa con el mismo peso
         tipográfico del hero, honesto sobre lo que falta sin parecer un error. -->
    <figure class="hero__fig hero__fig--pend" id="lw-hero-fig">
      <svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/><path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg>
      <p class="hero__fig--pend-tt">Renders in progress</p>
      <p class="hero__fig--pend-sub">Reserve before they exist — the roof price is confirmed by the developer today.</p>
    </figure>
    <?php else: ?>
    <figure class="hero__fig" id="lw-hero-fig">
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
    <div class="facts__it">
      <div class="facts__lb">Size</div>
      <div class="facts__vl" id="lw-fact-size"><?= lw_e($sizeTxt) ?></div>
    </div>
    <div class="facts__it">
      <div class="facts__lb">Layout</div>
      <div class="facts__vl" id="lw-fact-layout"><?= lw_e($dorm . ' bed · ' . $banos . ' bath') ?></div>
    </div>
    <div class="facts__it">
      <div class="facts__lb">Pool</div>
      <div class="facts__vl">Included</div>
    </div>
    <div class="facts__it">
      <div class="facts__lb">Price</div>
      <div class="facts__vl" id="lw-fact-price">From <?= lw_e($precioTxt) ?></div>
    </div>
  </div>

  <?php if ($wizard): ?>
  <!-- ══ FORMULARIO DE UN CAMPO POR PANTALLA — solo Dali (3-sep, decisión del owner) ══
       "Lo quiero en un solo sitio, es decir, que no se mueva y sea como un formulario que
       avanza por campos." Sustituye a las cuatro secciones de la rama de abajo, en su mismo
       punto de la página. Mismos controles, mismo estado, misma aritmética: lo único que
       cambia es que se presentan de uno en uno.
       Sin auto-scroll en ningún paso — era la mecánica de la versión de secciones y aquí
       sería exactamente lo que se ha pedido evitar.
       Los cinco pasos siguen siendo radios y checkboxes NATIVOS dentro de un <fieldset>, y
       todos existen en el DOM desde el primer render: `hidden` solo esconde los que no
       tocan. Así, sin JS, se ven los cinco campos seguidos y la página sigue siendo
       utilizable y rastreable, en vez de quedarse en un paso 1 muerto. -->
  <section class="sec" id="lw-wizard">
    <p class="et">Build your estimate</p>
    <h2>Five questions, and you'll have a figure</h2>
    <p class="sec__desc" style="margin-bottom:28px">Nothing here is a quote. It's the same figure we'd start from on the call, so you arrive knowing the ballpark.</p>

    <div class="wiz" id="lw-wiz">
      <!-- La cabecera de la tarjeta NO repite el título: ya lo dicen el kicker y el <h2>
           justo encima, y el resumen de abajo vuelve a decir "Your estimate". Tres veces
           lo mismo en una pantalla es ruido. Aquí solo va lo que cambia (el paso) y lo que
           tiene que viajar en cualquier captura (el calificador). -->
      <div class="wiz__head">
        <span class="wiz__tt" id="lw-wiz-paso">Step 1 of 5</span>
        <span class="wiz__flag-in">Indicative only — not a quote</span>
      </div>

      <div class="wiz__cuerpo">
        <!-- ── 1 · Modelo ────────────────────────────────────────────────────────── -->
        <fieldset class="cfg__set wiz__campo" data-paso="1">
          <legend class="cfg__in">Which villa</legend>
          <p class="wiz__q">Which villa?</p>
          <p class="wiz__ayuda">Same construction system and roof choice across the range — only the size changes the price.</p>
          <!-- Foto grande, no miniatura (3-sep, owner: "dale más presencia porque ahora no
               se ve"). Se pasa de 44px a 150×100 en escritorio. El paso 1 queda más alto
               que los otros cuatro; es el precio de que la villa se vea, y no rompe el "que
               no se mueva": lo que no se mueve es la POSICIÓN de la tarjeta, verificado. -->
          <div id="lw-cross">
            <?php foreach ($modelosOrd as $mid => $mm):
              $mmImgs   = lw_modelo_imgs($mid);
              $mmThumb  = $mmImgs[0] ?? null;
              $mmEsEste = $mid === $m['id'];
              $mmDesde  = lw_precio_fmt(lw_modelo_precio_desde($mm));
            ?>
            <input class="cfg__in" type="radio" name="lw-modelo" id="lw-modelo-<?= lw_e($mid) ?>" value="<?= lw_e($mid) ?>"<?= $mmEsEste ? ' checked' : '' ?>>
            <label class="wiz__op wiz__op--mod<?= $mmEsEste ? ' is-on' : '' ?>" for="lw-modelo-<?= lw_e($mid) ?>" data-model-id="<?= lw_e($mid) ?>">
              <span class="wiz__foto">
                <?php if ($mmThumb): ?>
                <img src="<?= lw_e($mmThumb) ?>" alt="<?= lw_e('Villa ' . $mm['nombre']) ?>" loading="lazy">
                <?php else: ?>
                <svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="5"/></svg>
                <?php endif; ?>
              </span>
              <span class="wiz__nom"><?= lw_e($mm['nombre']) ?><i class="cross__tag"<?= $mmEsEste ? '' : ' hidden' ?>>— this page</i></span>
              <span class="wiz__sub"><?= lw_e($mm['villa_m2'] . 'm² + ' . $mm['terraza_m2'] . 'm² terrace · ' . $mm['dormitorios'] . ' bed · ' . $mm['banos'] . ' bath') ?></span>
              <span class="wiz__cifra">From <?= lw_e($mmDesde) ?></span>
            </label>
            <?php endforeach; ?>
          </div>
        </fieldset>

        <!-- ── 2 · Techo ─────────────────────────────────────────────────────────── -->
        <fieldset class="cfg__set wiz__campo" data-paso="2" hidden>
          <legend class="cfg__in">Which roof</legend>
          <p class="wiz__q">Which roof?</p>
          <p class="wiz__ayuda">The rest of the villa doesn't vary between the two. It's the only thing that changes the price.</p>
          <?php /* Bucle sobre los techos YA ORDENADOS por precio: así el primero es siempre
                 el más barato, que es el que va preseleccionado, sin depender del orden en
                 que estén escritos en modelos.php. Los ids se mantienen (lw-techo-<clave>)
                 porque seleccionarModelo() los actualiza por id al cambiar de villa.
                 El hueco de FOTO (assets/img/roofs/<clave>.webp) se descubre en disco: el
                 día que lleguen las fotos es soltar los ficheros, sin tocar código. Mientras
                 no exista, no se renderiza marco ninguno — un espacio gris reservado es un
                 placeholder, y de esos no sale ninguno del estudio. */ ?>
          <?php foreach ($techosOrd as $tk => $tv): $tImg = lw_techo_img($tk); ?>
          <input class="cfg__in" type="radio" name="lw-techo" id="lw-techo-<?= lw_e($tk) ?>" value="<?= lw_e($tk) ?>"<?= $techoIni === $tk ? ' checked' : '' ?>>
          <label class="wiz__op<?= $tImg ? ' wiz__op--foto' : '' ?><?= $techoIni === $tk ? ' is-on' : '' ?>" for="lw-techo-<?= lw_e($tk) ?>">
            <?php if ($tImg): ?>
            <span class="wiz__foto wiz__foto--techo" id="lw-techo-<?= lw_e($tk) ?>-foto"><img src="<?= lw_e($tImg) ?>" alt="<?= lw_e($tv['nombre']) ?> roof finish" loading="lazy"></span>
            <?php endif; ?>
            <span class="wiz__nom" id="lw-techo-<?= lw_e($tk) ?>-nombre"><?= lw_e($tv['nombre']) ?></span>
            <span class="wiz__sub" id="lw-techo-<?= lw_e($tk) ?>-desc"<?= empty($tv['desc']) ? ' hidden' : '' ?>><?= lw_e($tv['desc'] ?? '') ?></span>
            <span class="wiz__cifra">From <span id="lw-techo-<?= lw_e($tk) ?>-precio"><?= lw_e(lw_precio_fmt(lw_techo_precio_activo($tv))) ?></span></span>
          </label>
          <?php endforeach; ?>
        </fieldset>

        <!-- ── 3 · Ubicación ─────────────────────────────────────────────────────
             Isla y vista comparten paso a propósito: son una sola pregunta ("¿dónde?") y
             separarlas haría que el contador de pasos cambiara de 5 a 6 según la isla, que
             es peor que revelar cuatro filas más. La vista solo aplica a Bali; Sumba lleva
             su tarifa en el propio botón de isla, así que elegirla no deja el paso sin
             cifra. -->
        <fieldset class="cfg__set wiz__campo" data-paso="3" hidden>
          <legend class="cfg__in">Where</legend>
          <p class="wiz__q">Where do you want it built?</p>
          <p class="wiz__ayuda">The plot rate depends on the location. We confirm real availability on the call.</p>
          <?php foreach ($PICKER['island'] as $k => $o): ?>
          <input class="cfg__in" type="radio" name="lw-island" id="lw-island-<?= lw_e($k) ?>" value="<?= lw_e($k) ?>"<?= $o['rate'] !== null ? ' data-rate="' . (int) $o['rate'] . '"' : '' ?><?= $islaIni === $k ? ' checked' : '' ?>>
          <label class="wiz__op<?= $islaIni === $k ? ' is-on' : '' ?>" for="lw-island-<?= lw_e($k) ?>">
            <span class="wiz__nom"><?= lw_e($o['label']) ?></span>
            <?php if ($k === 'sumba'): ?><span class="wiz__sub">Subject to availability</span><?php endif; ?>
            <?php if ($o['rate'] !== null): ?><span class="wiz__cifra"><?= lw_e(lw_precio_fmt($o['rate'])) ?>/m²</span><?php endif; ?>
          </label>
          <?php endforeach; ?>

          <?php /* Vistas ordenadas por tarifa y la más barata preseleccionada; visible de
                 salida porque la isla por defecto es Bali. */ ?>
          <div class="wiz__sub-q" id="lw-picker-view"<?= $islaIni === 'bali' ? '' : ' hidden' ?>>
            <h4>And which view?</h4>
            <?php foreach ($vistasOrd as $k => $o): ?>
            <input class="cfg__in" type="radio" name="lw-view" id="lw-view-<?= lw_e($k) ?>" value="<?= lw_e($k) ?>" data-rate="<?= (int) $o['rate'] ?>"<?= $vistaIni === $k ? ' checked' : '' ?>>
            <label class="wiz__op<?= $vistaIni === $k ? ' is-on' : '' ?>" for="lw-view-<?= lw_e($k) ?>">
              <span class="wiz__nom"><?= lw_e($o['label']) ?></span>
              <span class="wiz__cifra"><?= lw_e(lw_precio_fmt($o['rate'])) ?>/m²</span>
            </label>
            <?php endforeach; ?>
          </div>
        </fieldset>

        <!-- ── 4 · Parcela ───────────────────────────────────────────────────────── -->
        <fieldset class="cfg__set wiz__campo" data-paso="4" hidden>
          <legend class="cfg__in">Plot size</legend>
          <p class="wiz__q">How much land?</p>
          <p class="wiz__ayuda">These are the sizes that actually come up in our plot catalog. Pick the closest — the exact plot is confirmed on the call.</p>
          <?php foreach (LW_M2_PRESETS as $p): ?>
          <input class="cfg__in" type="radio" name="lw-m2" id="lw-m2-<?= (int) $p ?>" value="<?= (int) $p ?>"<?= $m2Ini === $p ? ' checked' : '' ?>>
          <label class="wiz__op<?= $m2Ini === $p ? ' is-on' : '' ?>" for="lw-m2-<?= (int) $p ?>"><span class="wiz__nom"><?= number_format($p, 0, '.', ',') ?> m²</span></label>
          <?php endforeach; ?>
          <input class="cfg__in" type="radio" name="lw-m2" id="lw-m2-other" value="other">
          <label class="wiz__op" for="lw-m2-other"><span class="wiz__nom">Another size</span></label>
          <div class="wiz__m2" id="lw-m2-custom" hidden>
            <label for="lw-m2-input">Plot size</label>
            <input type="number" id="lw-m2-input" inputmode="numeric"
                   min="<?= (int) LW_M2_MIN ?>" max="<?= (int) LW_M2_MAX ?>" step="<?= (int) LW_M2_STEP ?>"
                   placeholder="<?= (int) LW_M2_MIN ?>–<?= (int) LW_M2_MAX ?>">
            <span>m²</span>
          </div>
          <!-- Al topar el rango se AVISA, nunca se reescribe en silencio lo que tecleó el
               visitante (Administración): un clamp mudo es una trampa, y dejar pasar un 1e9
               pinta "€125.000.000.000" en una landing con tráfico de pago. -->
          <p class="cfg__aviso" id="lw-m2-aviso" hidden></p>
        </fieldset>

        <!-- ── 5 · Extras ────────────────────────────────────────────────────────── -->
        <fieldset class="cfg__set wiz__campo" data-paso="5" hidden>
          <legend class="cfg__in">Extras</legend>
          <p class="wiz__q">Anything else?</p>
          <p class="wiz__ayuda">Optional, and priced on the call — they're not part of the figure below.</p>
          <?php foreach ($PICKER['extras'] as $k => $label): ?>
          <input class="cfg__in" type="checkbox" name="lw-extras" id="lw-extra-<?= lw_e($k) ?>" value="<?= lw_e($k) ?>">
          <label class="wiz__op" for="lw-extra-<?= lw_e($k) ?>">
            <span class="wiz__nom"><?= lw_e($label) ?></span>
            <span class="wiz__cifra">Priced on the call</span>
          </label>
          <?php endforeach; ?>
        </fieldset>
      </div>

      <!-- El total y su etiqueta de estado no se ocultan en NINGÚN paso: es lo que hace
           que una captura del paso 2 se explique sola. El desglose por líneas aparece en
           el último, cuando ya hay algo que desglosar. -->
      <div class="wiz__resumen"><?php $renderPanel(); ?></div>

      <div class="wiz__nav">
        <button type="button" class="wiz__atras" id="lw-wiz-atras" disabled>← Back</button>
        <div class="wiz__puntos" id="lw-wiz-puntos" aria-hidden="true"></div>
        <button type="button" class="btn" id="lw-wiz-next">Next →</button>
      </div>
    </div>

    <p class="sec__desc" style="margin-top:18px;font-size:13px"><?= lw_e($resumenTarifas) ?></p>
  </section>
  <?php endif; ?>

  <?php if (!$wizard): ?>
  <!-- ── Configurador, paso 1: los 5 modelos ───────────────────────────────────
       Pedido del owner (2-sep): entrar por cualquier ficha enseña las otras — y elegir
       otra fila aquí reconfigura hero+ficha rápida+Finishes EN ESTA MISMA página, sin
       recargar (revisión previa Seguridad+Diseño, 2-sep). Cada fila sigue siendo un
       <a href> real a su propia URL (progresivo: sin JS, o para un rastreador, sigue
       siendo un enlace normal) — el JS solo intercepta el clic cuando puede.
       Dos estados, no uno (Diseño): `.is-current` es el modelo DE ESTA PÁGINA/URL —
       fijo, servidor, nunca lo mueve el JS, porque About/Galería/Alcance de abajo
       siguen hablando de él pase lo que pase aquí arriba. `.is-configured` es lo que
       se está previsualizando ahora — empieza en la misma fila y el JS lo mueve al
       elegir otra. Nunca el precio 2027 aquí (vive en Finishes, aparte del activo). -->
  <!-- Numeración de pasos EN EL TEXTO del kicker `.et`, nunca como numeral tipográfico
       (Diseño, revisión previa 3-sep). El `.num` de 52px sigue significando "capítulo del
       documento" y solo sobrevive del marcador de transición hacia abajo ("01 About the
       model") — es la extensión de la decisión que ya se tomó el 2-sep al quitarle el
       `.num` a Finishes. Dos numeraciones a la vez en la misma página no se entienden.
       Y nada de barra de progreso ni ticks: PRODUCT.md descarta expresamente la estética
       de "numbered sections and kickers on every heading". El estado de cada paso se
       escribe con palabras en `.picker__status`, que es donde ya vivía. -->
  <section class="sec" id="modelos">
    <p class="et">Step 1 — The range</p>
    <h2>Five models, one build system</h2>
    <p class="sec__desc">Same construction system and roof choice across the range — only the size changes the price. Pick a model to configure it below, or come back to this later.</p>
    <div class="cross" id="lw-cross">
      <?php foreach ($MODELOS as $mid => $mm):
        $mmImgs   = lw_modelo_imgs($mid);
        $mmThumb  = $mmImgs[0] ?? null;
        $mmOriginal = $mid === $m['id'];
        $mmSirap  = lw_precio_fmt(lw_techo_precio_activo($mm['techos']['sirap']));
        $mmBambu  = lw_precio_fmt(lw_techo_precio_activo($mm['techos']['bambu']));
        $mmClases = 'cross__row' . ($mmOriginal ? ' is-current is-configured' : '');
      ?>
      <a class="<?= $mmClases ?>" href="/modelo/<?= lw_e($mid) ?>" data-model-id="<?= lw_e($mid) ?>">
        <span class="cross__thumb">
          <?php if ($mmThumb): ?>
          <img src="<?= lw_e($mmThumb) ?>" alt="" loading="lazy">
          <?php else: ?>
          <svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="4"/></svg>
          <?php endif; ?>
        </span>
        <span class="cross__name"><?= lw_e($mm['nombre']) ?><i class="cross__tag"<?= $mmOriginal ? '' : ' hidden' ?>>— this page</i></span>
        <span class="cross__specs"><?= lw_e($mm['villa_m2'] . 'm² + ' . $mm['terraza_m2'] . 'm² terrace · ' . $mm['dormitorios'] . ' bed · ' . $mm['banos'] . ' bath') ?></span>
        <span class="cross__price">From <?= lw_e($mmSirap) ?><i><?= lw_e($mm['techos']['bambu']['nombre']) ?> roof from <?= lw_e($mmBambu) ?></i></span>
      </a>
      <?php endforeach; ?>
    </div>
    <!-- Esta nota remitía a una sección «Investment» que este mismo push renombró a
         "Step 2 — Roof" (Legal, capa 1 de deploy): la referencia se quedó huérfana. El
         texto viejo no se cita literal aquí a propósito, para que un grep del string
         visible no tropiece con el comentario que explica su retirada. -->
    <p class="sec__desc" style="margin-top:18px;font-size:13px" id="lw-cross-nota">Villa price only, roof included. Plot priced separately — build your estimate below.</p>
  </section>

  <!-- ── Acabados + Precio, fusionados (2-sep) ─────────────────────────────────
       Reestructuración pedida por el owner ("es demasiado larga"): antes eran DOS
       secciones separadas (Acabados con las tarjetas de techo, Precio con la tabla de
       parcela) que repetían el precio de la villa cada una a su manera — cuarta vez que
       aparecía en la página, contando el hero y la ficha rápida. Una sola sección: las
       tarjetas de techo siguen mostrando SU precio (fuente real), la tabla de abajo ya
       no repite la villa, solo parcela y gastos de cierre. El aviso de la subida de 2027
       sigue aparte del precio activo y sin su mismo peso visual (Diseño, revisión
       previa): nunca tachado ni junto a la cifra, como haría una landing de SaaS con
       descuento — esta página ya evita ese tono a propósito. -->
  <!-- Sin `.num` (2-sep, configurador): esto ya no es "capítulo 02 de la ficha de
       Dali" — es un panel vivo del configurador (paso 2). Pegado a Range, no después de
       About+Galería (Diseño, revisión previa 2-sep): un configurador con dos secciones
       estáticas en medio de sus propios pasos no se lee como configurador — Range,
       Finishes y el picker de Extras/Isla/Vista quedan juntos, About+Galería pasan a
       vivir DESPUÉS del bloque de configuración, antes de Alcance/Ubicación. -->
  <!-- Paso 2 — el techo, ahora SELECCIONABLE. Fuera el `01`/`02` de las tarjetas
       (Diseño): eran adorno inofensivo mientras solo informaban, pero en cuanto son
       controles se leen como ranking o como sub-pasos y chocan con "Step 2".
       ⚠️ Cada techo lleva el precio COMPLETO de la villa con ese techo, no un sobrecoste
       (Sirap 48.000 / Bambú 50.000 en Dali son dos precios de villa). Por eso el panel de
       abajo enseña UNA línea de villa y nunca "villa + techo" como dos sumandos. -->
  <section class="sec panel" id="acabados">
    <p class="et">Step 2 — Roof</p>
    <h2 id="lw-techos-h2">The roof is the only thing that changes the price</h2>
    <p class="sec__desc">The rest of the villa doesn't vary between the two roof options. Pick one and the estimate below updates.</p>
    <fieldset class="cfg__set">
      <legend class="cfg__in">Roof finish</legend>
      <div class="rows">
        <input class="cfg__in" type="radio" name="lw-techo" id="lw-techo-sirap" value="sirap"<?= $techoIni === 'sirap' ? ' checked' : '' ?>>
        <label class="rows__it<?= $techoIni === 'sirap' ? ' is-on' : '' ?>" for="lw-techo-sirap">
          <h3 id="lw-techo-sirap-nombre"><?= lw_e($m['techos']['sirap']['nombre']) ?></h3>
          <p id="lw-techo-sirap-desc"<?= empty($m['techos']['sirap']['desc']) ? ' hidden' : '' ?>><?= lw_e($m['techos']['sirap']['desc'] ?? '') ?></p>
          <p class="rows__precio">From <span id="lw-techo-sirap-precio"><?= lw_e(lw_precio_fmt(lw_techo_precio_activo($m['techos']['sirap']))) ?></span></p>
        </label>
        <input class="cfg__in" type="radio" name="lw-techo" id="lw-techo-bambu" value="bambu"<?= $techoIni === 'bambu' ? ' checked' : '' ?>>
        <label class="rows__it<?= $techoIni === 'bambu' ? ' is-on' : '' ?>" for="lw-techo-bambu">
          <h3 id="lw-techo-bambu-nombre"><?= lw_e($m['techos']['bambu']['nombre']) ?></h3>
          <p id="lw-techo-bambu-desc"<?= empty($m['techos']['bambu']['desc']) ? ' hidden' : '' ?>><?= lw_e($m['techos']['bambu']['desc'] ?? '') ?></p>
          <p class="rows__precio">From <span id="lw-techo-bambu-precio"><?= lw_e(lw_precio_fmt(lw_techo_precio_activo($m['techos']['bambu']))) ?></span></p>
        </label>
      </div>
    </fieldset>
    <?php if ($antes2027): ?>
    <p class="sec__desc" style="margin-top:24px;font-size:13.5px">Prices shown are valid through 31 December 2026 (Bali time). Villa prices rise on 1 January 2027 — plot rates are unaffected.</p>
    <?php endif; ?>
    <p class="sec__desc" style="margin-top:16px;font-size:13.5px">Villa prices are confirmed directly by the developer and include Indonesian VAT (PPN). Notary, permit and transfer costs are separate and are all detailed in writing before you sign.</p>
  </section>

  <!-- ── Picker: extras + isla + vista — pasos 3-4 del configurador (2-sep) ────────
       Movido aquí desde Ubicación (Diseño, revisión previa): si es un paso del
       configurador tiene que vivir pegado a Range+Finishes, no varias secciones
       estáticas más abajo. Siempre visible, sin botón "Customize" — un configurador
       con pasos escondidos no lee como configurador. Nada aquí es una cotización: no
       depende del modelo elegido arriba, cualifica al lead, no suma un total (decisión
       del owner). Las selecciones viajan por el camino de conversión real de la página
       — el widget de Calendly vía api/booking-notify.php — no por el wa.me secundario
       del pie. -->
  <!-- Todas las opciones y sus tarifas se renderizan desde lw_picker_opciones() (fuente
       única en lib.php). Hasta el 3-sep las cuatro vistas estaban escritas a mano aquí con
       su cifra al lado: la misma "lista a mano dentro del guardrail" que ya obligó a
       corregir beachfront 200→250 en dos sitios el 2-sep. El JS sigue sin ver ninguna
       tarifa: lee el `data-rate` que ya renderizó PHP. -->
  <section class="sec" id="lw-picker">
    <p class="et">Step 3 — Island &amp; view</p>
    <h2>Where do you want it built?</h2>
    <p class="sec__desc">The plot rate depends on the location. Nothing here is a quote — we confirm real availability and exact pricing on the call.</p>

    <!-- El <legend> va oculto y solo da nombre accesible al grupo; la cabecera visible es
         un <div> aparte. Un legend con display:flex es históricamente frágil entre motores
         y aquí el WebView in-app de Instagram es tráfico real, no un caso de borde. -->
    <fieldset class="cfg__set picker__group">
      <legend class="cfg__in">Island</legend>
      <div class="picker__gh"><h4>Island</h4><span class="picker__status picker__status--val" id="lw-st-island">— choose one</span></div>
      <div class="picker__rows" data-group="island">
        <?php foreach ($PICKER['island'] as $k => $o): ?>
        <input class="cfg__in" type="radio" name="lw-island" id="lw-island-<?= lw_e($k) ?>" value="<?= lw_e($k) ?>"<?= $o['rate'] !== null ? ' data-rate="' . (int) $o['rate'] . '"' : '' ?>>
        <label class="picker__row" for="lw-island-<?= lw_e($k) ?>"><?= lw_e($o['label']) ?><?php if ($k === 'sumba'): ?><i>subject to availability</i><?php endif; ?><?php if ($o['rate'] !== null): ?><span><?= lw_e(lw_precio_fmt($o['rate'])) ?>/m²</span><?php endif; ?></label>
        <?php endforeach; ?>
      </div>
    </fieldset>

    <!-- El grupo de vista solo aplica a Bali: el catálogo de vistas es de la costa oeste.
         Sumba lleva su propia tarifa en el botón de isla, así que elegir Sumba no deja el
         paso sin cifra (agujero que señaló Diseño en el plan). Se oculta con `hidden`, no
         con aria-hidden: `hidden` saca del orden de tabulación de verdad. -->
    <fieldset class="cfg__set picker__group" id="lw-picker-view" hidden>
      <legend class="cfg__in">View</legend>
      <div class="picker__gh"><h4>View</h4><span class="picker__status picker__status--val" id="lw-st-view">— choose one</span></div>
      <div class="picker__rows" data-group="view">
        <?php foreach ($PICKER['view'] as $k => $o): ?>
        <input class="cfg__in" type="radio" name="lw-view" id="lw-view-<?= lw_e($k) ?>" value="<?= lw_e($k) ?>" data-rate="<?= (int) $o['rate'] ?>">
        <label class="picker__row" for="lw-view-<?= lw_e($k) ?>"><?= lw_e($o['label']) ?><span><?= lw_e(lw_precio_fmt($o['rate'])) ?>/m²</span></label>
        <?php endforeach; ?>
      </div>
    </fieldset>

    <p class="picker__nota"><?= lw_e($resumenTarifas) ?> Sumba plots are subject to availability and confirmed on the call.</p>
  </section>

  <section class="sec" id="lw-picker2">
    <p class="et">Step 4 — Plot size &amp; extras</p>
    <h2>How much land are you after?</h2>
    <p class="sec__desc">Sizes below are the ones that actually come up in our plot catalog. Pick the closest — the exact plot is confirmed on the call.</p>

    <fieldset class="cfg__set picker__group">
      <legend class="cfg__in">Plot size</legend>
      <div class="picker__gh"><h4>Plot size</h4><span class="picker__status picker__status--val" id="lw-st-m2">— choose one</span></div>
      <div class="picker__rows" data-group="m2">
        <?php foreach (LW_M2_PRESETS as $p): ?>
        <input class="cfg__in" type="radio" name="lw-m2" id="lw-m2-<?= (int) $p ?>" value="<?= (int) $p ?>">
        <label class="picker__row" for="lw-m2-<?= (int) $p ?>"><?= number_format($p, 0, '.', ',') ?> m²</label>
        <?php endforeach; ?>
        <input class="cfg__in" type="radio" name="lw-m2" id="lw-m2-other" value="other">
        <label class="picker__row" for="lw-m2-other">Another size</label>
        <div class="cfg__m2" id="lw-m2-custom" hidden>
          <label for="lw-m2-input">Plot size</label>
          <span><input type="number" id="lw-m2-input" inputmode="numeric"
                 min="<?= (int) LW_M2_MIN ?>" max="<?= (int) LW_M2_MAX ?>" step="<?= (int) LW_M2_STEP ?>"
                 placeholder="<?= (int) LW_M2_MIN ?>–<?= (int) LW_M2_MAX ?>">m²</span>
        </div>
      </div>
      <!-- Al topar el rango se AVISA, nunca se reescribe en silencio lo que tecleó el
           visitante (Administración): un clamp mudo es una trampa, y dejar pasar un 1e9
           pinta "€125.000.000.000" en una landing con tráfico de pago. -->
      <p class="cfg__aviso" id="lw-m2-aviso" hidden></p>
    </fieldset>

    <fieldset class="cfg__set picker__group">
      <legend class="cfg__in">Extras</legend>
      <div class="picker__gh"><h4>Extras</h4><span class="picker__status">priced on the call</span></div>
      <div class="picker__rows" data-group="extras">
        <?php foreach ($PICKER['extras'] as $k => $label): ?>
        <input class="cfg__in" type="checkbox" name="lw-extras" id="lw-extra-<?= lw_e($k) ?>" value="<?= lw_e($k) ?>">
        <label class="picker__row" for="lw-extra-<?= lw_e($k) ?>"><?= lw_e($label) ?></label>
        <?php endforeach; ?>
      </div>
    </fieldset>

    <!-- ── Panel de presupuesto ────────────────────────────────────────────────────
         Estado inicial pintado EN SERVIDOR (lw_estimacion): sin JS enseña el precio real
         de la villa y una instrucción en la línea de parcela, nunca huecos vacíos que se
         leen como página rota.
         La etiqueta del TOTAL cambia con el estado, y eso es lo que sostiene la decisión
         del owner de tenerlo siempre visible: mientras no haya parcela dice literalmente
         "Villa only — plot not included yet", así que una captura hecha a medias —que es
         lo que de verdad circula por WhatsApp— se explica sola. -->
    <?php $renderPanel(); ?>
  </section>
  <?php endif; /* /rama de secciones */ ?>

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
      <a href="<?= lw_e($WA_LINK) ?>" id="lw-wa-link" target="_blank" rel="noopener"><?= lw_e($WA_SHOW) ?></a>
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
  // Flags de escape en todo json_encode que viaja dentro de <script> (3-sep): hoy los
  // nombres son inocuos, pero el payload crece con el configurador y una etiqueta de
  // cierre de script, o un "&", en un campo de catálogo rompería el bloque entero.
  // (Esa etiqueta no se escribe literal ni en este comentario: dentro de un <script> la
  // cierra igual, aunque vaya comentada — cazado por tools/sintaxis_js.py al ampliarlo
  // a .php en esta misma tarea, que es exactamente para lo que servía ampliarlo.)
  var MODELO = <?= json_encode($m['id'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  // 2-sep: los 5 modelos tienen precio real (antes solo Dali) — el pixel ya puede pujar
  // por valor, no solo por volumen. null si algún día vuelve a faltar el precio.
  var PRECIO_VALOR = <?= json_encode(lw_modelo_precio_desde($m)) ?>;
  // Configurador (2-sep): payload ya resuelto por PHP, ver el porqué de la lista blanca
  // junto a $configuradorModelos más arriba. MODELO_ORIGEN es el modelo DE ESTA URL — no
  // lo mueve seleccionarModelo(), lo necesitan pushState (volver atrás) y el marcador de
  // transición antes de "About the model".
  var CONFIGURADOR = <?= json_encode($configuradorModelos, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  var MODELO_ORIGEN = MODELO;
  var html = document.documentElement;

  // Estado ÚNICO del configurador (3-sep). Se declara aquí arriba, antes del píxel, porque
  // `track('ViewContent')` ya lee el techo para su `value`. `techo` arranca en 'sirap'
  // igual que el radio marcado por el servidor: el panel nunca sale vacío.
  // La aritmética la manda lib.php (lw_estimacion); esto es su espejo en cliente para
  // pintar. Lo que se GUARDA y lo que se manda a ventas lo recalcula el servidor.
  // El techo por defecto sale de PHP, no escrito a mano aquí: hasta la capa 1 de deploy
  // vivía en cuatro sitios (la variable de PHP, el `checked` del radio, este objeto y la
  // comparación de syncURL), y cambiarlo en uno dejaba el panel del servidor pintando un
  // techo y el radio marcando otro desde el primer frame, sin que saltara ningún test.
  var TECHO_INI = <?= json_encode($techoIni, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  // Preselección por defecto de cada paso: la opción más barata, derivada en servidor
  // ordenando por precio (ver $techoIni/$islaIni/$vistaIni/$m2Ini). El JS no elige nada:
  // solo necesita saber cuáles son para (a) restaurar ese estado cuando la URL no dice otra
  // cosa y (b) no ensuciar la URL repitiendo lo que ya es el valor por defecto.
  var DEFAULTS = {
    techo:  TECHO_INI,
    island: <?= json_encode($islaIni, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
    view:   <?= json_encode($vistaIni, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>,
    m2:     <?= (int) $m2Ini ?>
  };
  // Rama de presentación: formulario de un campo por pantalla (solo Dali hoy) o el bloque
  // de cuatro secciones. Cambia dónde se pintan los controles, nunca la aritmética.
  var WIZARD = <?= $wizard ? 'true' : 'false' ?>;
  var LW_CFG = {techo: DEFAULTS.techo, island: DEFAULTS.island, view: DEFAULTS.view,
                m2: DEFAULTS.m2, m2mode: String(DEFAULTS.m2), extras: []};
  var LW_M2 = {min: <?= (int) LW_M2_MIN ?>, max: <?= (int) LW_M2_MAX ?>, step: <?= (int) LW_M2_STEP ?>};

  // ── Píxel: ViewContent al cargar, con `value`/`currency` cuando hay precio cerrado. ──
  // `value` = precio de villa DEL TECHO ELEGIDO, y de nada más. Dos reglas detrás:
  //  · Hasta el 3-sep leía PRECIO_VALOR, que es min(sirap,bambu): con Bambú marcado el
  //    píxel disparaba con el precio del Sirap (hallazgo de Desarrollo).
  //  · NUNCA suma la parcela, aunque el panel sí la sume. `value` alimenta la puja y hay
  //    un adset optimizando sobre `Lead` (LAW-113): meter ahí una cifra que depende de los
  //    m² que teclee el visitante deja que cualquiera mueva la señal de optimización
  //    escribiendo un número grande, y rompe la comparabilidad con el histórico. La
  //    estimación completa viaja como propiedad propia, nunca como `value`.
  function precioActivo() {
    var cfg = CONFIGURADOR[MODELO];
    var t = cfg && cfg.techos && cfg.techos[LW_CFG.techo];
    return (t && typeof t.precio === 'number') ? t.precio : PRECIO_VALOR;
  }
  function track(ev, extra) {
    if (typeof window.lwTrack !== 'function') return;
    var p = Object.assign({content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO}, extra || {});
    var v = precioActivo();
    if (v !== null && !('value' in p)) { p.value = v; p.currency = 'EUR'; }
    window.lwTrack(ev, p);
  }
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  // Clic al botón que lleva al widget: evento propio, no `Schedule` — es un clic hacia
  // el calendario, no una cita confirmada. Esa sí sale del propio widget, más abajo.
  var ctaCal = document.getElementById('lw-cal-cta');
  if (ctaCal) ctaCal.addEventListener('click', function () { track('AbrioCalendario', {}); });

  // ── Configurador: cambiar de modelo EN ESTA MISMA página, sin recargar (2-sep, pedido
  //    explícito del owner — la alternativa barata era navegar a /modelo/<id> y se
  //    descartó). Una única función atómica: todo lo que depende del modelo (hero, ficha
  //    rápida, acabados, fila activa en "The range", MODELO/PRECIO_VALOR del píxel y de
  //    booking-notify.php, URL) se actualiza junto — nunca a medias, o el píxel dispara
  //    con el modelo viejo mientras la pantalla ya enseña el nuevo (Seguridad, revisión
  //    previa). Los enlaces de "The range" siguen siendo <a href> reales: sin JS, o para
  //    un rastreador, funcionan igual que antes — esto solo intercepta el clic. ─────────
  // Generación del configurador (hallazgo Desarrollo, revisión de deploy 2-sep): dos
  // clicks seguidos en "The range" (o un click + `popstate` antes de los 180ms del
  // crossfade) dejaban dos temporizadores/onload en vuelo a la vez — el primero en
  // resolver podía reescribir el hero con el modelo VIEJO encima del nuevo, o revelar
  // (opacity 1) una imagen todavía sin decodificar. Cada llamada saca su propio número;
  // los callbacks diferidos comprueban que siguen siendo la selección vigente antes de
  // tocar el DOM, y si no lo son, simplemente no hacen nada (el swap que sí es vigente
  // ya se está encargando de dejar el hero correcto).
  var lwConfigGen = 0;
  // La IIFE del picker (más abajo) reasigna esto a su updateWaLink real una vez arranca
  // — no-op mientras tanto, por si seleccionarModelo() llegara a dispararse antes.
  var lwUpdateWaLink = function () {};
  // La IIFE del configurador (más abajo) reasigna esto a su aplicarQuery real — lo necesita
  // `popstate`, que se declara antes.
  var lwAplicarQuery = function () {};
  // La reasigna la IIFE de navegación del formulario; no-op mientras tanto y en la rama de
  // secciones, que no tiene pasos que avanzar.
  var lwAvanzar = function () {};

  function seleccionarModelo(id, opts) {
    var cfg = CONFIGURADOR[id];
    if (!cfg || id === MODELO) return;
    opts = opts || {};
    var gen = ++lwConfigGen;

    MODELO = id;
    PRECIO_VALOR = cfg.precioValor;

    var title = document.getElementById('lw-hero-title');
    var price = document.getElementById('lw-hero-price');
    var sub   = document.getElementById('lw-hero-sub');
    var fig   = document.getElementById('lw-hero-fig');
    var galleryLink = document.getElementById('lw-hero-gallery-link');
    if (title) title.textContent = cfg.villa;
    if (price) price.textContent = cfg.precioTxt.replace(/^From /, '');
    if (sub) sub.textContent = cfg.sub;
    if (galleryLink) galleryLink.hidden = !!cfg.sinRender;

    // Precarga la imagen antes de mostrarla: nunca un frame con la foto vieja seguida de
    // un flash gris a mitad de carga (fig.is-swapping cruza opacidad, ver CSS).
    if (fig) {
      fig.classList.add('is-swapping');
      window.setTimeout(function () {
        if (gen !== lwConfigGen) return; // otra selección más nueva ya tomó el relevo
        // La clase de swap se mantiene mientras se reconstruye el contenido — si aquí se
        // pierde, la opacidad vuelve a 1 con la imagen todavía sin decodificar (el mismo
        // "flash" que esto existe para evitar).
        fig.className = 'hero__fig is-swapping' + (cfg.sinRender ? ' hero__fig--pend' : '');
        if (cfg.sinRender) {
          fig.innerHTML = '<svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/><path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg><p class="hero__fig--pend-tt">Renders in progress</p><p class="hero__fig--pend-sub">Reserve before they exist — the roof price is confirmed by the developer today.</p>';
          window.setTimeout(function () { if (gen === lwConfigGen) fig.classList.remove('is-swapping'); }, 30);
        } else {
          var img = new Image();
          // Sin `onerror` (hallazgo Desarrollo): un 404/blip de red dejaba el hero en
          // opacity:0 para siempre, sin `onload` que lo rescatara — a diferencia del
          // <img> estático original, que al menos enseña el icono roto + alt. Aquí cae
          // al mismo estado "pending" que un modelo sin renders, nunca a un hueco vacío.
          img.onload = function () { if (gen === lwConfigGen) fig.classList.remove('is-swapping'); };
          img.onerror = function () {
            if (gen !== lwConfigGen) return;
            fig.className = 'hero__fig is-swapping hero__fig--pend';
            fig.innerHTML = '<svg viewBox="0 0 120 90" aria-hidden="true"><path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/><rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/><path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg><p class="hero__fig--pend-tt">Renders in progress</p><p class="hero__fig--pend-sub">Reserve before they exist — the roof price is confirmed by the developer today.</p>';
            window.setTimeout(function () { if (gen === lwConfigGen) fig.classList.remove('is-swapping'); }, 30);
          };
          img.fetchPriority = 'high';
          img.alt = cfg.villa + ', Lawang Tropical Properties: exterior with overflow pool';
          img.src = cfg.thumb;
          fig.innerHTML = '';
          fig.appendChild(img);
        }
      }, 180);
    }

    var fSize = document.getElementById('lw-fact-size');
    var fLayout = document.getElementById('lw-fact-layout');
    var fPrice = document.getElementById('lw-fact-price');
    if (fSize) fSize.textContent = cfg.sizeTxt;
    if (fLayout) fLayout.textContent = cfg.layoutTxt;
    if (fPrice) fPrice.textContent = cfg.precioTxt;

    var tSirapN = document.getElementById('lw-techo-sirap-nombre');
    var tSirapD = document.getElementById('lw-techo-sirap-desc');
    var tSirapP = document.getElementById('lw-techo-sirap-precio');
    var tBambuN = document.getElementById('lw-techo-bambu-nombre');
    var tBambuD = document.getElementById('lw-techo-bambu-desc');
    var tBambuP = document.getElementById('lw-techo-bambu-precio');
    if (tSirapN) tSirapN.textContent = cfg.techos.sirap.nombre;
    if (tSirapD) { tSirapD.textContent = cfg.techos.sirap.desc; tSirapD.hidden = !cfg.techos.sirap.desc; }
    if (tSirapP) tSirapP.textContent = cfg.techos.sirap.precioTxt;
    if (tBambuN) tBambuN.textContent = cfg.techos.bambu.nombre;
    if (tBambuD) { tBambuD.textContent = cfg.techos.bambu.desc; tBambuD.hidden = !cfg.techos.bambu.desc; }
    if (tBambuP) tBambuP.textContent = cfg.techos.bambu.precioTxt;

    var marker = document.getElementById('lw-static-marker-name');
    if (marker) marker.textContent = cfg.villa;

    // Título de la pestaña y canonical (3-sep, hallazgo del verificador en producción):
    // al cambiar de modelo cambiaban el <h1> y la URL, pero el título seguía diciendo el
    // modelo con el que se abrió la página. Con varias pestañas abiertas comparando villas
    // —que es justo lo que invita a hacer el configurador— todas se llamaban igual.
    document.title = cfg.villa + <?= json_encode($TITULO_SUFIJO, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    var canon = document.querySelector('link[rel="canonical"]');
    if (canon) canon.href = 'https://lawangproperties.com/modelo/' + id;

    // Rama de secciones: fila de "The range". Rama de formulario: opción del paso 1. Las
    // dos usan el mismo atributo, así que un solo selector cubre ambas.
    document.querySelectorAll('#lw-cross [data-model-id]').forEach(function (row) {
      var esEste = row.getAttribute('data-model-id') === id;
      row.classList.toggle('is-configured', esEste);
      if (row.classList.contains('wiz__op')) row.classList.toggle('is-on', esEste);
    });
    var radioMod = document.getElementById('lw-modelo-' + id);
    if (radioMod) radioMod.checked = true;

    if (!opts.skipHistory) {
      window.history.pushState({modelo: id}, '', '/modelo/' + id);
    }

    // El link de WhatsApp del picker (más abajo) menciona el modelo por nombre — sin
    // esto, alguien configura Temple, marca extras y pulsa el link, y a ventas le llega
    // "interested in the Villa Dali" con las preferencias de Temple pegadas detrás
    // (hallazgo del advisor, ninguna de las 4 revisiones de deploy lo cazó: es una línea
    // que el diff no tocaba, solo dejó de ser cierta). `lwUpdateWaLink` vive en el scope
    // de arriba porque la IIFE del picker se declara DESPUÉS de esta función.
    lwUpdateWaLink();
  }

  document.querySelectorAll('#lw-cross .cross__row[data-model-id]').forEach(function (row) {
    row.addEventListener('click', function (e) {
      var id = row.getAttribute('data-model-id');
      if (!CONFIGURADOR[id]) return; // deja el <a href> normal si algo no cuadra
      e.preventDefault();
      seleccionarModelo(id);
    });
  });

  window.addEventListener('popstate', function (e) {
    var id = (e.state && e.state.modelo) || MODELO_ORIGEN;
    seleccionarModelo(id, {skipHistory: true});
    // Y se relee la configuración de la URL a la que se ha vuelto: sin esto, atrás
    // cambiaba el modelo pero mantenía techo/isla/vista/m² del estado del que venías, y el
    // syncURL siguiente reescribía esa entrada del historial con ese estado ajeno.
    lwAplicarQuery();
  });

  // ── Configurador con presupuesto (3-sep) ────────────────────────────────────────────
  //  Los controles son radios y checkboxes NATIVOS (ver el porqué en el CSS de .cfg__in).
  //  La clase `.is-on` se mantiene como enganche principal del estado pintado y `:checked`
  //  solo como refuerzo: el tráfico de esta landing llega del WebView in-app de
  //  Instagram/Facebook, donde un selector que el motor no entiende tira la regla entera
  //  y el visitante deja de ver qué había elegido.
  //  Las tarifas NUNCA se escriben aquí: se leen del `data-rate` del input seleccionado,
  //  que ya renderizó PHP desde lw_picker_opciones(). El JS no tiene tabla de precios.
  (function () {
    var waLink    = document.getElementById('lw-wa-link');
    var viewGroup = document.getElementById('lw-picker-view');
    var m2Custom  = document.getElementById('lw-m2-custom');
    var m2Input   = document.getElementById('lw-m2-input');
    var m2Aviso   = document.getElementById('lw-m2-aviso');
    var reduce    = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // Formato forzado a en-US. Sin el locale explícito, un visitante con el navegador en
    // español ve "€48.000", que se lee como "casi 48" — es exactamente el fallo que
    // lw_precio_fmt() arregló en servidor el 2-sep, y aquí volvería a entrar por el JS.
    function fmt(n) { return '€' + Math.round(n).toLocaleString('en-US'); }

    // parseInt("1e9") devuelve 1, no mil millones: "sanear" con parseInt convierte un
    // valor hostil en uno diminuto que pasa todos los topes y da una estimación
    // absurdamente baja, que es peor que la alta. Number() + isFinite + floor + clamp.
    // Devuelve {v: int|null, topado: 'min'|'max'|null}.
    // Espejo exacto de lw_m2_clamp() en PHP, ajuste al paso incluido — si divergen, el
    // visitante ve una cifra y a ventas le llega otra.
    function clampM2(raw) {
      if (raw === null || raw === undefined) return {v: null, topado: null};
      var s = String(raw).trim();
      if (s === '') return {v: null, topado: null};
      var n = Number(s);
      if (!isFinite(n) || n <= 0) return {v: null, topado: null};
      n = Math.round(n / LW_M2.step) * LW_M2.step;
      if (n < LW_M2.min) return {v: LW_M2.min, topado: 'min'};
      if (n > LW_M2.max) return {v: LW_M2.max, topado: 'max'};
      return {v: n, topado: null};
    }

    // Tarifa vigente: se CONSULTA en el momento al input marcado, nunca se guarda en el
    // estado. Sumba lleva la suya en el propio botón de isla; Bali la pone la vista.
    function tarifa() {
      var sel = document.querySelector('input[name="lw-island"]:checked');
      if (sel && sel.value === 'sumba' && sel.dataset.rate) return Number(sel.dataset.rate);
      if (LW_CFG.island === 'bali') {
        var v = document.querySelector('input[name="lw-view"]:checked');
        if (v && v.dataset.rate) return Number(v.dataset.rate);
      }
      return null;
    }

    function txt(id, s) { var e = document.getElementById(id); if (e) e.textContent = s; }
    function pend(id, on) {
      var e = document.getElementById(id);
      if (e) e.classList.toggle('is-pend', !!on);
    }
    function setStatus(id, s) { txt(id, s); }

    // Un cambio de cifra usa el MISMO idioma de movimiento que el resto de la página (el
    // crossfade corto del hero), no un contador animado: un count-up es el tic de landing
    // de SaaS que PRODUCT.md descarta, y además deja el número ilegible medio segundo.
    // El valor pendiente vive en el elemento, no en el closure: dos cambios seguidos
    // (elegir techo y a los 100ms una vista) dejaban DOS temporizadores en vuelo y el
    // primero en resolver escribía la cifra vieja encima de la nueva. Es la misma familia
    // de fallo que ya obligó a poner la guardia de generación en el crossfade del hero el
    // 2-sep; aquí se resuelve con un único temporizador por elemento que, al vencer,
    // escribe siempre el ÚLTIMO valor pedido.
    function pinta(id, s) {
      var e = document.getElementById(id);
      if (!e) return;
      if (reduce) { e.textContent = s; return; }
      if (e.textContent === s && !e.lwT) return;
      e.lwNext = s;
      if (e.lwT) return; // ya hay un swap en vuelo; escribirá este valor, no el anterior
      e.classList.add('is-swapping');
      e.lwT = window.setTimeout(function () {
        e.textContent = e.lwNext;
        e.classList.remove('is-swapping');
        e.lwT = null;
      }, 150);
    }

    var EXTRA_LB = <?= json_encode($PICKER['extras'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    var VIEW_LB  = <?= json_encode(array_map(function ($o) { return $o['label']; }, $PICKER['view']), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    var ISLAND_LB = <?= json_encode(array_map(function ($o) { return $o['label']; }, $PICKER['island']), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;

    function recalcular() {
      var cfg = CONFIGURADOR[MODELO] || {};
      var t   = (cfg.techos && cfg.techos[LW_CFG.techo]) || null;
      var villa = t ? t.precio : null;

      // Villa: una sola línea. El techo NO es un sobrecoste — su precio ES el de la villa
      // con ese techo (Sirap 48.000 / Bambú 50.000 en Dali son dos precios de villa).
      var nom = (cfg.villa || '').replace(/^Villa /, '');
      var lb = document.getElementById('lw-est-villa-lb');
      if (lb && t) {
        lb.firstChild.nodeValue = 'Villa — ' + nom + ', ' + t.nombre + ' roof';
      }
      if (villa !== null) pinta('lw-est-villa', 'From ' + fmt(villa));

      // Parcela: sin tarifa o sin m² NO hay cifra. Nunca €0 — un cero se lee como "el
      // terreno es gratis", no como "todavía no se puede calcular" (Administración).
      var r = tarifa(), parcela = null;
      if (r !== null && LW_CFG.m2 !== null) parcela = r * LW_CFG.m2;

      var pLb = document.getElementById('lw-est-parcela-lb');
      if (pLb) {
        // Sumba va con mayúscula (es un topónimo); las vistas en minúscula, que es como se
        // leen dentro de la frase ("Plot — beachfront, 500 m² at…").
        var donde = LW_CFG.island === 'sumba' ? 'Sumba'
                  : (LW_CFG.view ? VIEW_LB[LW_CFG.view].toLowerCase() : null);
        pLb.firstChild.nodeValue = (donde && LW_CFG.m2 !== null)
          ? 'Plot — ' + donde + ', ' + LW_CFG.m2.toLocaleString('en-US') + ' m² at ' + fmt(r) + '/m²'
          : 'Plot';
      }
      if (parcela !== null) { pinta('lw-est-parcela', fmt(parcela)); pend('lw-est-parcela', false); }
      else {
        pinta('lw-est-parcela', r === null ? 'Choose an island and a size' : 'Choose a plot size');
        pend('lw-est-parcela', true);
      }

      // Extras: fila SIEMPRE presente y con texto en la columna del importe. Nunca "—",
      // celda vacía ni €0: la ausencia tiene que leerse "se cotiza", no "va incluido".
      var nomEx = LW_CFG.extras.map(function (k) { return EXTRA_LB[k] || k; });
      txt('lw-est-extras-lb', nomEx.length ? 'Extras — ' + nomEx.join(', ').toLowerCase() : 'Extras — none selected');

      // El pie del total NOMBRA lo que deja fuera. Es la regla comprobable que impide que
      // marcar sauna y ver el total quieto se lea como "la sauna va incluida".
      txt('lw-est-excluye', nomEx.length
        ? 'Excludes ' + nomEx.join(', ').toLowerCase() + ', plus notary, permits and transfer costs.'
        : 'Excludes notary, permits and transfer costs.');

      // TOTAL. Siempre visible (decisión del owner, 3-sep). Lo que impide que una captura
      // hecha a medias mienta es que su ETIQUETA cambia con el estado: con la villa sola
      // dice, literalmente, que la parcela todavía no está dentro.
      var total = (villa || 0) + (parcela || 0);
      if (villa !== null) {
        pinta('lw-est-total', 'from around ' + fmt(total));
        txt('lw-est-total-lb', parcela !== null
          ? 'Indicative starting figure, villa + plot'
          : 'Villa only — plot not included yet');
      }

      // Estatus por paso, con palabras y en el sitio donde ya vivían (.picker__status).
      // Un paso hecho se reconoce porque aquí aparece su valor y la fila está en verde:
      // no hace falta un tick encima de un fondo verde.
      setStatus('lw-st-island', LW_CFG.island ? (LW_CFG.island === 'sumba' ? 'Sumba' : 'Bali') : '— choose one');
      setStatus('lw-st-view', LW_CFG.view ? VIEW_LB[LW_CFG.view] : '— choose one');
      setStatus('lw-st-m2', LW_CFG.m2 !== null ? LW_CFG.m2.toLocaleString('en-US') + ' m²' : '— choose one');

      updateWaLink();
      syncURL();
    }

    // La configuración viaja en la query: sin esto, pulsar "atrás" restauraba el modelo
    // pero dejaba el techo y los m² del estado "futuro" (hallazgo de Desarrollo). De paso
    // hace el enlace compartible, que en un funnel es un regalo.
    function syncURL() {
      // Se PARTE de la query que ya hay y solo se borran las claves propias. Partir de un
      // URLSearchParams vacío —como hacía la primera versión de hoy— barría `utm_*` y
      // `fbclid` milisegundos después de cargar: las tres URLs de anuncio vivas los llevan,
      // el POST de reserva los lee de `location.search`, y a ventas le llegaba TODO lead de
      // pago sin origen ni campaña (hallazgo de Desarrollo, capa 1 de deploy). Además el
      // píxel no podía sembrar `_fbc`, porque carga tras el consentimiento y para entonces
      // el `fbclid` ya no estaba.
      // Borrar lo propio en vez de copiar una lista blanca de lo ajeno es lo que hace que
      // esto siga funcionando con el parámetro que Meta invente el año que viene.
      var p = new URLSearchParams(location.search);
      ['roof', 'island', 'view', 'plot', 'extras'].forEach(function (k) { p.delete(k); });
      // Solo se escribe lo que se APARTA del valor por defecto: con la preselección del
      // 3-sep, escribirlo todo dejaba "?island=bali&view=cliff&plot=160" pegado a cada
      // carga de un anuncio sin que el visitante hubiera tocado nada.
      if (LW_CFG.techo && LW_CFG.techo !== DEFAULTS.techo) p.set('roof', LW_CFG.techo);
      if (LW_CFG.island && LW_CFG.island !== DEFAULTS.island) p.set('island', LW_CFG.island);
      if (LW_CFG.view && LW_CFG.view !== DEFAULTS.view) p.set('view', LW_CFG.view);
      if (LW_CFG.m2 !== null && LW_CFG.m2 !== DEFAULTS.m2) p.set('plot', String(LW_CFG.m2));
      if (LW_CFG.extras.length) p.set('extras', LW_CFG.extras.join(','));
      var q = p.toString();
      window.history.replaceState(window.history.state, '', '/modelo/' + MODELO + (q ? '?' + q : ''));
    }

    function updateWaLink() {
      if (!waLink) return;
      // El nombre del modelo se lee de MODELO/CONFIGURADOR en cada llamada, nunca de un
      // valor capturado al cargar la página — si no, el texto se queda pegado al modelo
      // con el que abrió la página aunque el configurador ya enseñe otro (hallazgo del
      // advisor). Cae al villa server-rendered solo si CONFIGURADOR[MODELO] no existiera.
      var cfg = CONFIGURADOR[MODELO];
      var villaAhora = (cfg && cfg.villa) || <?= json_encode($villa, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
      var waBase = "Hi, I'm interested in the " + villaAhora + " from Lawang Tropical Properties.";
      var bits = [];
      // Etiquetas del catálogo, no las claves internas (capa 1 de deploy, Administración):
      // el mensaje lo manda el propio lead desde su WhatsApp, y "Extras: airbnb-kit" se lee
      // como una máquina hablando. ISLAND_LB/VIEW_LB/EXTRA_LB ya están en este mismo scope.
      var t = cfg && cfg.techos && cfg.techos[LW_CFG.techo];
      if (t) bits.push('Roof: ' + t.nombre);
      if (LW_CFG.island) bits.push('Island: ' + (ISLAND_LB[LW_CFG.island] || LW_CFG.island));
      if (LW_CFG.view) bits.push('View: ' + (VIEW_LB[LW_CFG.view] || LW_CFG.view));
      if (LW_CFG.m2 !== null) bits.push('Plot: ' + LW_CFG.m2 + ' m2');
      if (LW_CFG.extras.length) {
        bits.push('Extras: ' + LW_CFG.extras.map(function (k) { return EXTRA_LB[k] || k; }).join(', '));
      }
      // Sin la cifra del total a propósito: en WhatsApp esto llega como un mensaje escrito
      // por el propio lead, y un importe ahí pesa mucho más que en pantalla, fuera de todo
      // el rotulado del panel que existe justo para matizarlo. Viajan las selecciones; el
      // número se lo da ventas en la llamada.
      var text = bits.length ? waBase + ' ' + bits.join(' · ') + ' (my selection, to confirm on the call).' : waBase;
      waLink.href = 'https://wa.me/<?= $WA_NUM ?>?text=' + encodeURIComponent(text);
    }
    lwUpdateWaLink = recalcular;

    // Mantiene .is-on sincronizada con el radio/checkbox marcado de cada grupo.
    function pintaGrupo(name) {
      document.querySelectorAll('input[name="' + name + '"]').forEach(function (i) {
        var lb = document.querySelector('label[for="' + i.id + '"]');
        if (lb) lb.classList.toggle('is-on', i.checked);
      });
    }

    function scrollA(id) {
      if (reduce) return; // saltar la página bajo reduced-motion marea más que ayuda
      var el = document.getElementById(id);
      if (!el) return;
      var top = el.getBoundingClientRect().top + window.scrollY - 76; // nav sticky
      window.scrollTo({top: top, behavior: 'smooth'});
    }

    function verVista() {
      if (!viewGroup) return;
      var mostrar = LW_CFG.island === 'bali';
      viewGroup.hidden = !mostrar;
      if (!mostrar && LW_CFG.view) {
        LW_CFG.view = null;
        document.querySelectorAll('input[name="lw-view"]').forEach(function (i) { i.checked = false; });
        pintaGrupo('lw-view');
      }
    }

    // ── Techo (paso 2) ────────────────────────────────────────────────────────────
    // El auto-scroll cuelga del CLIC en la etiqueta, no del `change` del radio: en un grupo
    // de radios las flechas del teclado marcan y disparan `change`, así que quien navegaba
    // Sirap↔Bambú con el teclado se llevaba un scroll a la sección siguiente en cada
    // pulsación, sacando de pantalla el control que tenía enfocado (Desarrollo, capa 1).
    function alClicar(sel, destino) {
      document.querySelectorAll(sel).forEach(function (lb) {
        lb.addEventListener('click', function () { scrollA(destino); });
      });
    }

    document.querySelectorAll('input[name="lw-techo"]').forEach(function (i) {
      i.addEventListener('change', function () {
        if (!i.checked) return;
        LW_CFG.techo = i.value;
        pintaGrupo('lw-techo');
        recalcular();
      });
    });
    // Nunca dentro de seleccionarModelo(): ahí `popstate` secuestraría la restauración de
    // scroll del navegador al pulsar atrás. Y NUNCA en el formulario de un campo por
    // pantalla: ahí todo ocurre en la misma tarjeta y mover la página es exactamente lo
    // que el owner pidió evitar ("que no se mueva").
    if (!WIZARD) alClicar('label[for^="lw-techo-"]', 'lw-picker');

    // ── Paso 1 del formulario: el modelo. En la rama de secciones esto lo hacen los
    //    <a href> de "The range"; aquí es un radio más, y delega en la misma función
    //    atómica de siempre para que hero, ficha rápida, techos, píxel y URL se muevan
    //    juntos. ─────────────────────────────────────────────────────────────────────
    document.querySelectorAll('input[name="lw-modelo"]').forEach(function (i) {
      i.addEventListener('change', function () {
        if (!i.checked) return;
        seleccionarModelo(i.value);
      });
    });

    // ── Isla y vista (paso 3) ─────────────────────────────────────────────────────
    document.querySelectorAll('input[name="lw-island"]').forEach(function (i) {
      i.addEventListener('change', function () {
        if (!i.checked) return;
        LW_CFG.island = i.value;
        pintaGrupo('lw-island');
        verVista();
        recalcular();
      });
    });
    // Elegir Bali revela el grupo Vista justo debajo: mover además el suelo bajo un
    // elemento que acaba de aparecer marea (Diseño). Solo se avanza con Sumba, que no abre
    // nada. En el formulario no se avanza nunca solo: manda el botón Next.
    if (!WIZARD) {
      document.querySelectorAll('label[for^="lw-island-"]').forEach(function (lb) {
        lb.addEventListener('click', function () {
          if (lb.getAttribute('for') !== 'lw-island-bali') scrollA('lw-picker2');
        });
      });
    }
    document.querySelectorAll('input[name="lw-view"]').forEach(function (i) {
      i.addEventListener('change', function () {
        if (!i.checked) return;
        LW_CFG.view = i.value;
        pintaGrupo('lw-view');
        recalcular();
      });
    });

    // ── Tamaño de parcela y extras (paso 4) ───────────────────────────────────────
    function avisa(topado) {
      if (!m2Aviso) return;
      if (!topado) { m2Aviso.hidden = true; m2Aviso.textContent = ''; return; }
      m2Aviso.hidden = false;
      m2Aviso.textContent = topado === 'max'
        ? 'The estimator caps at ' + LW_M2.max.toLocaleString('en-US') + ' m² — larger plots are priced on the call.'
        : 'Our smallest available plots are around ' + LW_M2.min + ' m² — we’ll confirm what fits on the call.';
    }

    // `deb` vive fuera del bloque del input porque el handler de los preajustes tiene que
    // poder CANCELARLO: teclear 900 en "Another size" y pulsar "350 m²" antes de los 350ms
    // dejaba el debounce en vuelo, que al vencer leía la caja (oculta pero con "900"
    // dentro) y pisaba el 350 recién elegido. La interfaz enseñaba 350 y a ventas le
    // llegaba 900 — justo el fallo que el correo existe para evitar (Desarrollo, capa 1).
    var deb = null;

    document.querySelectorAll('input[name="lw-m2"]').forEach(function (i) {
      i.addEventListener('change', function () {
        if (!i.checked) return;
        window.clearTimeout(deb);
        LW_CFG.m2mode = i.value;
        pintaGrupo('lw-m2');
        if (m2Custom) m2Custom.hidden = (i.value !== 'other');
        if (i.value === 'other') {
          var c = clampM2(m2Input && m2Input.value);
          LW_CFG.m2 = c.v;
          avisa(c.topado);
          if (m2Input) m2Input.focus();
        } else {
          LW_CFG.m2 = Number(i.value);
          avisa(null);
        }
        recalcular();
      });
    });

    if (m2Input) {
      m2Input.addEventListener('input', function () {
        window.clearTimeout(deb);
        deb = window.setTimeout(function () {
          var c = clampM2(m2Input.value);
          LW_CFG.m2 = c.v;
          avisa(c.topado);
          recalcular();
        }, 350);
      });
      // Al salir del campo sí se escribe el valor topado en la caja: hasta entonces el
      // visitante sigue teniendo delante lo que tecleó, con el aviso al lado.
      m2Input.addEventListener('blur', function () {
        var c = clampM2(m2Input.value);
        if (c.v !== null && String(c.v) !== m2Input.value.trim()) m2Input.value = String(c.v);
      });
    }

    document.querySelectorAll('input[name="lw-extras"]').forEach(function (i) {
      i.addEventListener('change', function () {
        var k = i.value, n = LW_CFG.extras.indexOf(k);
        if (i.checked && n === -1) LW_CFG.extras.push(k);
        if (!i.checked && n !== -1) LW_CFG.extras.splice(n, 1);
        pintaGrupo('lw-extras');
        recalcular();
      });
    });

    // ── Estado desde la query (enlace compartido, recarga o vuelta atrás) ─────────
    // Es una función y no una IIFE de arranque porque `popstate` también tiene que poder
    // llamarla: hasta la capa 1 de deploy, pulsar atrás cambiaba el modelo pero dejaba el
    // techo y los m² del estado "futuro", y encima reescribía la URL de esa entrada del
    // historial para que cuadrara — con lo que el enlace configurado que el visitante tenía
    // en el back-stack se perdía en silencio (Desarrollo).
    function aplicarQuery() {
      var q = new URLSearchParams(location.search);

      // Un parámetro ausente cae al VALOR POR DEFECTO, no a "sin elegir": desde la
      // preselección del 3-sep el formulario nunca arranca vacío, y volver atrás o abrir un
      // enlace sin query tiene que dejar el mismo estado que entrar de cero.
      var roof = q.get('roof');
      var ri = roof ? document.getElementById('lw-techo-' + roof) : null;
      // Sin lista de techos escrita a mano: vale el que exista como control en la página,
      // que es exactamente el catálogo que renderizó PHP.
      LW_CFG.techo = ri ? roof : DEFAULTS.techo;
      var riIni = document.getElementById('lw-techo-' + LW_CFG.techo);
      if (riIni) riIni.checked = true;

      var isl = q.get('island');
      var ii  = isl ? document.getElementById('lw-island-' + isl) : null;
      LW_CFG.island = ii ? isl : DEFAULTS.island;
      document.querySelectorAll('input[name="lw-island"]').forEach(function (n) { n.checked = false; });
      var iiIni = document.getElementById('lw-island-' + LW_CFG.island);
      if (iiIni) iiIni.checked = true;
      verVista();

      var vw = q.get('view');
      if (LW_CFG.island === 'bali') {
        var vi = vw ? document.getElementById('lw-view-' + vw) : null;
        LW_CFG.view = vi ? vw : DEFAULTS.view;
      } else {
        LW_CFG.view = null; // el catálogo de vistas es de Bali
      }
      document.querySelectorAll('input[name="lw-view"]').forEach(function (n) { n.checked = false; });
      var viIni = LW_CFG.view ? document.getElementById('lw-view-' + LW_CFG.view) : null;
      if (viIni) viIni.checked = true;

      var pl = q.get('plot') !== null ? clampM2(q.get('plot')) : {v: DEFAULTS.m2, topado: null};
      if (pl.v === null) pl = {v: DEFAULTS.m2, topado: pl.topado};
      LW_CFG.m2 = pl.v;
      LW_CFG.m2mode = null;
      document.querySelectorAll('input[name="lw-m2"]').forEach(function (n) { n.checked = false; });
      if (m2Custom) m2Custom.hidden = true;
      if (pl.v !== null) {
        var exacto = document.getElementById('lw-m2-' + pl.v);
        if (exacto) { exacto.checked = true; LW_CFG.m2mode = String(pl.v); }
        else {
          var otro = document.getElementById('lw-m2-other');
          if (otro) { otro.checked = true; LW_CFG.m2mode = 'other'; }
          if (m2Custom) m2Custom.hidden = false;
          if (m2Input) m2Input.value = String(pl.v);
        }
      }
      // El aviso de tope también al llegar por enlace: si no, quien abre un enlace con
      // ?plot=9999 ve 1.500 sin ninguna explicación de por qué no es lo que pedía.
      avisa(pl.topado);

      // Guarda contra duplicados: `?extras=sauna,sauna` metía la clave dos veces, y al
      // desmarcar la casilla el splice borraba una sola — quedaba un extra fantasma en el
      // panel y en lo que se manda a ventas, con la casilla desmarcada (Desarrollo).
      LW_CFG.extras = [];
      document.querySelectorAll('input[name="lw-extras"]').forEach(function (n) { n.checked = false; });
      (q.get('extras') || '').split(',').filter(Boolean).forEach(function (k) {
        var ei = document.getElementById('lw-extra-' + k);
        if (ei && LW_CFG.extras.indexOf(k) === -1) { ei.checked = true; LW_CFG.extras.push(k); }
      });

      ['lw-techo', 'lw-island', 'lw-view', 'lw-m2', 'lw-extras'].forEach(pintaGrupo);
      recalcular();
    }
    lwAplicarQuery = aplicarQuery;
    aplicarQuery();

    // ── Navegación por pasos (solo en la rama de formulario) ──────────────────────
    // Todos los campos existen en el DOM desde el primer render y `hidden` esconde los que
    // no tocan: sin JS se ven los cinco seguidos y la página sigue siendo utilizable, en
    // vez de quedarse clavada en un paso 1 muerto.
    (function () {
      var wiz = document.getElementById('lw-wiz');
      if (!wiz) return;
      var campos = Array.prototype.slice.call(wiz.querySelectorAll('.wiz__campo'));
      var TOTAL  = campos.length;
      var elPaso = document.getElementById('lw-wiz-paso');
      var elPuntos = document.getElementById('lw-wiz-puntos');
      var bAtras = document.getElementById('lw-wiz-atras');
      var bNext  = document.getElementById('lw-wiz-next');
      var actual = 1;
      var visitado = 1; // el paso más lejano al que se ha llegado, para los puntos

      // Los puntos son decorativos (aria-hidden en el marcado): quien usa lector de
      // pantalla ya recibe "Step N of 5" en texto y el foco puesto en la pregunta.
      for (var i = 0; i < TOTAL; i++) {
        var d = document.createElement('span');
        d.className = 'wiz__punto';
        elPuntos.appendChild(d);
      }
      var puntos = Array.prototype.slice.call(elPuntos.children);

      function mostrar(n, mueveFoco) {
        actual = Math.min(Math.max(n, 1), TOTAL);
        if (actual > visitado) visitado = actual;
        campos.forEach(function (c) {
          c.hidden = Number(c.getAttribute('data-paso')) !== actual;
        });
        puntos.forEach(function (p, k) {
          p.classList.toggle('is-on', k + 1 === actual);
          p.classList.toggle('is-hecho', k + 1 < visitado && k + 1 !== actual);
        });
        elPaso.textContent = 'Step ' + actual + ' of ' + TOTAL;
        bAtras.disabled = actual === 1;
        // En el último paso desaparece Next: el siguiente gesto es el CTA del propio
        // resumen, que es donde acaba el formulario.
        bNext.hidden = actual === TOTAL;
        wiz.classList.toggle('is-final', actual === TOTAL);

        // El foco va al titular de la pregunta, no al primer control: así un lector de
        // pantalla anuncia QUÉ se está preguntando antes de empezar a leer opciones.
        if (mueveFoco) {
          var q = campos[actual - 1].querySelector('.wiz__q');
          if (q) { q.setAttribute('tabindex', '-1'); q.focus({preventScroll: true}); }
        }
      }

      bNext.addEventListener('click', function () { mostrar(actual + 1, true); });
      bAtras.addEventListener('click', function () { mostrar(actual - 1, true); });
      lwAvanzar = function () { mostrar(actual + 1, true); };

      // ── Avance automático al elegir (3-sep, pedido del owner: "cuando clique en algo
      //    que pase ya al siguiente punto") ──────────────────────────────────────────
      // Cuelga del CLIC en la etiqueta, nunca del `change` del radio: con las flechas del
      // teclado se recorren las opciones de un grupo disparando `change` en cada una, y
      // avanzar ahí haría imposible comparar antes de decidir. Mismo motivo por el que el
      // auto-scroll de la rama de secciones también cuelga del clic.
      // El retardo deja ver el relleno verde de la opción antes de que cambie la pregunta:
      // sin él, el paso desaparece antes de que el ojo confirme qué ha marcado.
      wiz.addEventListener('click', function (e) {
        if (!e.target.closest) return;
        var lb = e.target.closest('label.wiz__op');
        if (!lb) return;
        var f = lb.getAttribute('for') || '';
        // Extras es multi-selección Y el último paso: no hay a dónde avanzar, y avanzar
        // tras la primera marca daría por terminado algo que no lo está.
        if (f.indexOf('lw-extra-') === 0) return;
        // Elegir Bali revela la sub-pregunta de la vista DENTRO de este mismo paso:
        // avanzar aquí se saltaría justo lo que fija la tarifa de parcela.
        if (f === 'lw-island-' + 'bali') return;
        // "Another size" abre el campo libre: hay que dejar escribir.
        if (f === 'lw-m2-other') return;
        window.setTimeout(function () { lwAvanzar(); }, 260);
      });

      mostrar(1, false);
    })();
  })();

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
      // Selecciones del configurador: lo que el lead marcó antes de reservar, para que
      // ventas llegue a la llamada sabiendo qué quiere — no es un pedido cerrado, se
      // etiqueta igual en el propio correo que manda el endpoint.
      // NO se manda el importe: el endpoint no tiene auth, así que un total que llegue por
      // POST es un número que cualquiera puede escribirle al correo de ventas. Van los
      // INGREDIENTES y el servidor recalcula la cifra con las mismas funciones que la
      // pintaron (lw_estimacion). Ver el porqué en api/booking-notify.php.
      fd.set('extras', LW_CFG.extras.join(','));
      fd.set('island', LW_CFG.island || '');
      fd.set('view', LW_CFG.view || '');
      fd.set('techo', LW_CFG.techo || '');
      fd.set('parcela_m2', LW_CFG.m2 !== null ? String(LW_CFG.m2) : '');
      // `keepalive`: Calendly puede navegar o el visitante cerrar la pestaña justo después
      // de reservar, y sin esto el aviso se pierde en vuelo. Y el .catch() es obligatorio
      // aunque no haga nada: sin él queda una promesa rechazada sin manejar, que el
      // try/catch NO cubre por ser asíncrona (hallazgo de Desarrollo).
      fetch('/api/booking-notify.php', {method: 'POST', body: fd, keepalive: true})
        .catch(function () { /* MUDO A PROPOSITO: la reserva ya esta en Calendly, esto solo es la campanita */ });
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
