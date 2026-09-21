<?php
/**
 * Landing de modelo de villa — /modelo/<id> (regla de reescritura en .htaccess).
 *
 * ── 21-sep-2026 · RECONSTRUCCIÓN DESDE CERO (v6, sustituye 352d9943/4c2312c5/c7287cb3) ──
 * Los tres restyles anteriores solo cambiaron CONTENIDO dentro del lenguaje visual de
 * siempre (chips, `.op`, tarjetas de texto) — el owner los vio en producción y ninguno
 * calcaba de verdad el mockup Tesla-style (`stitch_tesla_style_villa_configurator/…/
 * code.html` + `screen.png`). Esta vez: HTML/clases del mockup TAL CUAL, sección por
 * sección, sobre `assets/dali-tesla-tw.min.css` (Tailwind compilado con el
 * `tailwind.config` exacto del mockup — NUNCA el Play CDN de Tailwind, sin versión ni SRI).
 * El bloque de datos de abajo (precio, techos, extras, catálogo, snapshot financiero,
 * cross-sell) NO se reescribe: es el mismo que ya calculaba correctamente el restyle
 * anterior — la reconstrucción es de MARKUP, no de los datos que ya estaban bien.
 *
 * Lo que cambia de fondo frente al mockup (contenido inventado → real, decisiones ya
 * tomadas, no reabrir sin pasar otra vez por Legal):
 *   · Drawer de 6 pasos ficticios (Terreno/Estructura/Piscina/Interior/Domótica/ROI) →
 *     3 pasos reales: villa → techo → extras, con el motor YA VIVO en
 *     assets/au-landing-cfg.js (compartido con /dali) SIN TOCAR una línea. Los pasos 2 y 3
 *     los pinta ese JS con `class="op"`; el estilo de esas tarjetas vive en el <style> de
 *     abajo, calcado en valores (no en nombre de clase) del mismo `tailwind.config`.
 *   · Sin tab-bar de 6 botones sincronizado a mano: el motor solo mueve
 *     `#lw-paso-lb` + `#lw-puntos` (puntitos), así que la navegación de pasos usa ESO en
 *     vez de fabricar una barra de pestañas que el JS no sincroniza (fallo silencioso
 *     que solo se ve al hacer clic).
 *   · HUD/clima en vivo, audio ambiente, "Hak Pakai 80 Años", ROI 14,8%, escrow, PwC,
 *     Jakarta/Sumba/Londres/Madrid, Tesla Powerwall, Lutron, depósito reembolsable de
 *     2.500 €, plano CAD descargable: todo fuera — no hay fuente para ninguno en el
 *     proyecto (verificado, no supuesto) o directamente contradice Legal/lo que el
 *     estudio vende aquí. Detalle de cada sustitución en el encargo original
 *     (`encargos/20260921_*_modelo_dali_rebuild.md` si existe, o el historial del chat).
 *   · Modal de reserva del mockup (simula depósito + formulario propio) → NO se
 *     construye: el CTA final del drawer ("Completar Reserva & Dossier" en el mockup) es
 *     directamente el enlace de WhatsApp ya vivo (`$WA_LINK`), sin paso intermedio. Menos
 *     superficie que duplicar precio/resumen en un segundo sitio del DOM sin que el motor
 *     JS lo alimente — habría sido un dato estático that could drift from the real total.
 *   · FAQ: mismo contenido EXACTO ya aprobado por Legal (bloques `.i-en`/`.i-es`), dentro
 *     de tarjetas bordeadas individuales como pide el mockup pero con `<details>` nativo
 *     en vez de JS a mano — mismo aspecto, cero superficie de script nueva.
 *   · Sin el hack de `--sbw`/100vw breakout de la versión anterior: el mockup no rompe el
 *     ancho de ningún contenedor (todo vive dentro de `max-w-7xl` con gutter fijo), así
 *     que ese problema (y su arreglo) ya no aplica — no se traslada "por si acaso".
 *
 * ── 11-sep-2026: estas fichas NO agendan llamadas ─────────────────────────────────────
 * La conversión es WhatsApp (`ViewContent` al cargar; `Lead`/`AbrioCalendario` no existen
 * aquí — no hay calendario). Si se quiere medir conversión, el camino es CTWA, no
 * reetiquetar un clic a WhatsApp como `Lead`.
 */
require __DIR__ . '/datos.php';
$MODELOS = require __DIR__ . '/modelos.php';

$m = lw_modelo_get(isset($_GET['m']) ? $_GET['m'] : '', $MODELOS);
if (!$m) {
    header('Location: /thecollection', true, 302);
    exit;
}

// Sin renders todavía (Trinity/Temple): la plantilla degrada el hero cinemático a un
// único fondo estático ("renders en camino") y esconde dock de cámara y hotspots —
// nunca un placeholder de foto rota. Ver más abajo, sección HERO.
$sinRender = empty($m['imgs']);

$precioValor = lw_modelo_precio_desde($m);
$precio   = lw_precio_fmt($precioValor);
// Solo se anuncia la subida de 2027 MIENTRAS sigue vigente el precio de ahora — pasado el
// corte, el precio activo ya es el nuevo y no hay nada que anunciar. Restaurada 21-sep-2026
// (hallazgo de Administración en la consulta de deploy): el rebuild la habia dejado caer
// sin querer al limpiar una variable que parecia sin uso.
$antes2027 = lw_antes_del_corte_2027();
$nombre   = $m['nombre'];
$villa    = 'Villa ' . $nombre;
$dorm     = (int) $m['dormitorios'];
$banos    = (int) $m['banos'];

$g       = $m['imgs'];
$portada = $g[0] ?? null;

/**
 * Tres vistas del hero cinemático + la foto de la sección "Distribución": elegidas a
 * mano para Dali (día/techo Sirap = dali.webp, techo Bambú = dali3.webp, interior =
 * dali7.webp, planta = dali9.webp — verificado mirando las 9 fotos una por una, no por
 * nombre de fichero) y con índice de respaldo para cualquier otro modelo del catálogo
 * que entre por esta misma plantilla y no tenga ese mismo reparto curado.
 */
$heroDay      = $g[0] ?? null;
$heroTechoAlt = $g[2] ?? $g[1] ?? $g[0] ?? null;
$heroInterior = $g[6] ?? $g[1] ?? $g[0] ?? null;
// dali9.webp ES una planta cenital real ya renderizada por el estudio (no un CAD que
// haya que inventar) — se usa aquí en vez de "otra foto exterior cualquiera": es un
// asset real y encaja mejor con lo que pide la sección. Desviación señalada al owner.
// Nunca mezclar `??`/`?:` sin parentesis (PHP lo rechaza como fatal de sintaxis) — de ahi
// la variable intermedia en vez de encadenar `$g[8] ?? end($g) ?: $portada` en una linea.
$ultimoImg    = $g ? end($g) : null;
$layoutImg    = $g[8] ?? $ultimoImg ?? $portada;

$dormTxt  = $dorm . ' ' . ($dorm === 1 ? 'bedroom' : 'bedrooms');
$sizeTxt  = $m['villa_m2'] . 'm² + ' . $m['terraza_m2'] . 'm² terrace';

$precioTxt = $precio !== null ? $precio : 'Upon request';
$TITULO_SUFIJO = ' · Turnkey villa in Bali — Lawang Tropical Properties';

// ── Configurador villa → techo → extras — motor compartido, SIN TOCAR ────────────────
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

// ── Comparativa de cubiertas: solo si ESTE modelo tiene los dos techos resueltos ─────
$techosComp = (!empty($m['techos']['sirap']) && !empty($m['techos']['bambu'])) ? $m['techos'] : null;

// ── Snapshot financiero: SIEMPRE Villa Dali en Palm Field W5 (decisión del owner) ────
$deckEj = lw_deck_forecast_ejemplo();
$finCalc = null;
if ($deckEj) {
    $clavesReq = ['proyecto', 'moneda', 'adr_medio', 'adr_optimo', 'ocupacion_media',
                  'ocupacion_optima', 'inversion_base', 'pct_gestion', 'pct_mantenimiento', 'pct_impuesto'];
    $completo = true;
    foreach ($clavesReq as $k) {
        if (!array_key_exists($k, $deckEj)) { $completo = false; break; }
    }
    if ($completo && $deckEj['moneda'] === 'EUR') {
        $costesPct = (float) $deckEj['pct_gestion'] + (float) $deckEj['pct_mantenimiento'] + (float) $deckEj['pct_impuesto'];
        $finCalc = [];
        foreach (['average' => ['adr_medio', 'ocupacion_media'], 'optimal' => ['adr_optimo', 'ocupacion_optima']] as $caso => $claves) {
            $adr  = (float) $deckEj[$claves[0]];
            $ocup = (float) $deckEj[$claves[1]];
            $bruto  = (int) round($adr * 365 * $ocup);
            $costes = (int) round($bruto * $costesPct);
            $finCalc[$caso] = [
                'adr' => $adr, 'ocup' => $ocup, 'bruto' => $bruto,
                'costes' => $costes, 'neto' => $bruto - $costes,
            ];
        }
    }
}
if (!$finCalc) $deckEj = null;

// ── "More from the collection" — reutiliza $CAT, mismo criterio "sin render no se enseña" ──
$otrosModelos = [];
foreach ($CAT as $ocId => $ov) {
    if ($ocId === $m['id'] || $ov['sinRender']) continue;
    $otrosModelos[$ocId] = $ov;
}

$WA_NUM   = '6281138319862';
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text=' . rawurlencode("Hi, I'm interested in the " . $villa . ' from Lawang Tropical Properties.');
$WA_SHOW  = '+62 811-3831-9862';
$EMAIL    = 'sales@lawangproperties.com';

$OFICINA = 'Jl. Gn. Tangkuban Perahu No.145, 2nd Floor, Padangsambian Klod, '
         . 'Kec. Denpasar Bar., Kota Denpasar, Bali 80117';
$TELEFONOS = [
    ['show' => '+62 811-3830-5240', 'tel' => '+6281138305240'],
    ['show' => '+62 811-3830-5237', 'tel' => '+6281138305237'],
];
$ogImg = $portada ?? '/assets/img/lugar/costa.webp';
$slugPath = lw_modelo_url_path($m['id']);

// Etiqueta real del snapshot financiero (nombre del proyecto de ejemplo, nunca "este modelo").
$deckEtiqueta = $deckEj['proyecto'] ?? '';
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<script src="/assets/idioma-web.js?v=20260908113407"></script>
<script src="/assets/i18n-landing.js?v=20260911114520" defer></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($villa . $TITULO_SUFIJO) ?></title>
<meta name="description" content="<?= lw_e($villa) ?>: a new-build <?= lw_e($dormTxt) ?> villa, built on the plot you choose. Finishes, scope of works and price, configured live.">
<?php if (!$precio): ?>
<meta name="robots" content="noindex, nofollow">
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
<!-- Fuentes del mockup TAL CUAL (Cormorant Garamond / Instrument Sans / Jost): el CSS
     compilado abajo mapea font-headline-*/font-kpi-number/font-body-*/font-label-md a
     estas familias exactas — cambiarlas rompería la tipografía sin tocar una clase. -->
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,500;0,600;0,700;1,400;1,600&family=Instrument+Sans:wght@400;500;600;700&family=Jost:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap" rel="stylesheet">
<!-- Tailwind COMPILADO (npx tailwindcss sobre el mockup, mismo tailwind.config) — NUNCA
     el Play CDN: sin versión fija, sin SRI, y la CSP de seguridad_2026.md lo prohíbe. -->
<link rel="stylesheet" href="/assets/dali-tesla-tw.min.css?v=20260921164216">
<style>
/* Material Symbols Outlined: el link de Google Fonts trae el glifo, pero NO esta clase —
   sin ella el navegador pinta el nombre del icono como texto plano ("roofing"), no el
   icono. Verificado: no existe en dali-tesla-tw.min.css (Tailwind no genera CSS para una
   clase que no reconoce como utilidad), así que va aquí, el snippet estándar de Google. */
.material-symbols-outlined{font-family:'Material Symbols Outlined';font-weight:normal;
  font-style:normal;font-size:24px;line-height:1;letter-spacing:normal;text-transform:none;
  display:inline-block;white-space:nowrap;word-wrap:normal;direction:ltr;
  -webkit-font-feature-settings:'liga';-webkit-font-smoothing:antialiased}
/* Reset mínimo que el mockup traía inline (scrollbar fina + glass-panel/glass-dock/
   corner-accent) — estas tres NO las genera Tailwind (son CSS de autor en el <style> del
   propio code.html), así que se copian aquí literal, no desde el .min.css. */
::-webkit-scrollbar{width:6px;height:6px}
::-webkit-scrollbar-thumb{background:rgba(143,155,122,.5);border-radius:4px}
::-webkit-scrollbar-track{background:#f5f4ee}
.glass-panel{background:rgba(251,249,244,.92);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px)}
.glass-dock{background:rgba(46,52,55,.85);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px)}
.corner-accent::before{content:'';position:absolute;width:14px;height:14px;border-top:2px solid #485B37;border-left:2px solid #485B37;top:14px;left:14px}
.corner-accent::after{content:'';position:absolute;width:14px;height:14px;border-bottom:2px solid #485B37;border-right:2px solid #485B37;bottom:14px;right:14px}

/* ── Idioma: EN/ES/ID, igual que el resto de landings (idioma-web.js/i18n-landing.js) ── */
html[data-lang="es"] .i-en{display:none !important}
html:not([data-lang="es"]) .i-es{display:none !important}

/* ── Tarjetas de opción (pasos del configurador): valores EXACTOS del tailwind.config
   del mockup (primary #314322, on-surface #1b1c19, on-surface-variant #44483f,
   surface-container-low #f5f4ee, surface-container-highest #e4e2dd), no nombres de clase
   Tailwind — el paso 1 (villa) SÍ usa las clases Tailwind reales sobre `.vcard`; los
   pasos 2 y 3 los pinta assets/au-landing-cfg.js con `class="op"` a pelo (motor
   compartido, sin tocar), así que su aspecto vive aquí como CSS plano con los mismos
   valores, para que las tres tarjetas salgan indistinguibles a ojo. */
.vcard:has(input:checked),.op:has(input:checked){
  background:rgba(49,67,34,.05);border-color:#314322;box-shadow:0 1px 2px rgba(0,0,0,.04)}
.op{cursor:pointer;display:flex;align-items:center;gap:12px;padding:12px 14px;
  border-radius:12px;border:1px solid #e4e2dd;background:#f5f4ee;
  transition:border-color .15s ease,background .15s ease}
.op:hover{border-color:rgba(49,67,34,.5)}
.op input{width:16px;height:16px;accent-color:#314322;flex:none;margin:2px 0 0}
.op>span:nth-child(2){display:flex;flex-direction:column;flex:1;min-width:0}
.op__nb{font-family:'Jost',sans-serif;font-size:14px;font-weight:600;color:#1b1c19}
.op__sp{font-family:'Jost',sans-serif;font-size:11px;color:#44483f;margin-top:2px}
.op__pr{text-align:right;flex:none}
.op__pr b{font-family:'Jost',sans-serif;font-size:12px;font-weight:700;color:#314322;
  white-space:nowrap;display:block}
.op__pr i{font-style:normal;font-size:10px;color:#44483f;white-space:nowrap}
.op__th{width:44px;height:36px;border-radius:8px;object-fit:cover;background:#e4e2dd;flex:none}

/* ── Paginación de pasos (puntitos + "Step N of 3") — el motor solo mueve ESTO, no una
   barra de pestañas de 6 botones como el mockup: sincronizar una barra propia habría
   sido JS nuevo sobre un motor que ya funciona, con riesgo de desincronizarse en
   silencio (justo el fallo que este mismo proyecto ya sufrió con marcado a medias). */
.punto{width:6px;height:6px;border-radius:50%;background:#c5c8bc}
.punto.is-on{background:#314322;width:16px;border-radius:999px}
.cfg__step[hidden]{display:none}

/* ── Hero cinemático: capas cross-fade (día / techo bambú / interior) ──────────────── */
.view-layer{transition:opacity .7s ease-out,transform .7s ease-out}

/* ── FAQ: acordeón de tarjetas bordeadas con <details> nativo (mismo aspecto que el
   mockup, sin JS propio — menos superficie, misma jerarquía visual). ────────────────── */
.faq-item{border:1px solid #e4e2dd;border-radius:16px;background:#fbf9f4;overflow:hidden}
.faq-item + .faq-item{margin-top:14px}
.faq-item summary{list-style:none;cursor:pointer;padding:20px;display:flex;
  align-items:center;justify-content:space-between;gap:16px;
  font-family:'Jost',sans-serif;font-size:15px;font-weight:700;color:#314322}
.faq-item summary::-webkit-details-marker{display:none}
.faq-item summary .mi{transition:transform .2s ease}
.faq-item[open] summary .mi{transform:rotate(180deg)}
.faq-item__body{padding:0 20px 20px;border-top:1px solid rgba(228,226,221,.6);
  padding-top:12px;font-family:'Jost',sans-serif;font-size:13.5px;line-height:1.6;color:#44483f}
</style>
</head>
<body class="bg-surface font-body-md text-body-md text-on-surface antialiased selection:bg-soft-canopy selection:text-surface">

<!-- ═══ HEADER ═══════════════════════════════════════════════════════════════════════ -->
<header class="fixed top-0 left-0 w-full z-50 bg-surface/90 backdrop-blur-xl border-b border-surface-container-highest/60 shadow-[0_2px_12px_rgba(0,0,0,0.03)]">
<div class="h-20 w-full px-4 md:px-margin-desktop flex items-center justify-between gap-4">
<div class="flex items-center gap-5">
<a class="flex items-center" href="/">
<img class="h-8" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
</a>
<div class="h-8 w-px bg-surface-container-highest hidden md:block"></div>
<div class="hidden md:flex items-center gap-2 bg-surface-container-low/90 border border-surface-container-highest px-3.5 py-1.5 rounded-full shadow-sm">
<span class="w-2 h-2 rounded-full bg-territorial-green animate-pulse"></span>
<span class="font-body-sm text-body-sm text-on-surface-variant">Villa:</span>
<span class="font-label-md text-label-md text-deep-lagoon font-semibold tracking-wide"><?= lw_e($villa) ?></span>
</div>
</div>
<nav class="hidden xl:flex items-center gap-1 bg-surface-container-low/90 p-1.5 rounded-full border border-surface-container-highest">
<a class="px-3.5 py-1.5 rounded-full text-on-surface-variant hover:text-primary transition-all font-label-md text-body-sm" href="#section-layout"><?= lw_i18n('Distribución', 'Layout') ?></a>
<a class="px-3.5 py-1.5 rounded-full text-on-surface-variant hover:text-primary transition-all font-label-md text-body-sm" href="#section-cubiertas"><?= lw_i18n('Cubiertas', 'Roofs') ?></a>
<a class="px-3.5 py-1.5 rounded-full text-on-surface-variant hover:text-primary transition-all font-label-md text-body-sm" href="#section-financial"><?= lw_i18n('Rentabilidad', 'Returns & FAQ') ?></a>
<a class="px-3.5 py-1.5 rounded-full text-on-surface-variant hover:text-primary transition-all font-label-md text-body-sm" href="#section-collection"><?= lw_i18n('Colección', 'Collection') ?></a>
</nav>
<!-- nav__cta: hook de i18n-landing.js (monta aquí el selector EN/ES/ID) + divisa + CTA -->
<div class="nav__cta flex items-center gap-3 md:gap-element-gap">
<div class="lw-cur" id="lw-div-sel" data-no-i18n></div>
<div class="flex flex-col text-right pl-2 border-l border-surface-container-highest">
<span class="font-body-sm text-[11px] text-on-surface-variant uppercase tracking-wider"><?= lw_i18n('Desde', 'From') ?></span>
<span class="font-kpi-number text-lg md:text-headline-sm text-primary tracking-tight font-bold"<?= $precioValor !== null ? ' data-eur-fijo="' . (int) $precioValor . '"' : '' ?>><?= lw_e($precioTxt) ?></span>
</div>
<a class="hidden sm:flex items-center gap-1.5 px-4 py-2 rounded-full bg-deep-lagoon hover:bg-secondary text-on-secondary font-label-md text-xs font-semibold shadow-sm transition-all" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
<span class="material-symbols-outlined text-[16px]">support_agent</span>
<span><?= lw_i18n('Escríbenos', 'WhatsApp') ?></span>
</a>
</div>
</div>
</header>

<!-- ═══ HERO: CONFIGURADOR A PANTALLA COMPLETA ══════════════════════════════════════ -->
<section class="w-full h-screen pt-20 relative overflow-hidden bg-volcanic-ash" id="hero-configurator">
<div class="relative w-full h-full">
<?php if ($sinRender): ?>
<!-- Sin renders: fondo estático "en camino", sin dock de cámara ni hotspots — nunca una
     foto rota ni un hueco vacío con el mismo peso visual que una foto real. -->
<div class="absolute inset-0 w-full h-full flex flex-col items-center justify-center gap-3 text-center px-6">
  <span class="material-symbols-outlined text-soft-canopy" style="font-size:52px">architecture</span>
  <p class="font-headline-md text-2xl text-white font-bold">Renders in progress</p>
  <p class="font-body-sm text-body-sm text-white/70 max-w-md">Reserve before they exist — the roof price is confirmed by the developer today.</p>
</div>
<?php else: ?>
<div class="absolute inset-0 w-full h-full overflow-hidden select-none" id="viewport-canvas">
<div class="view-layer absolute inset-0 w-full h-full bg-cover bg-center opacity-100 scale-100" id="layer-day" style="background-image:url('<?= lw_e($heroDay) ?>')">
<div class="absolute inset-0 bg-gradient-to-t from-volcanic-ash/80 via-transparent to-volcanic-ash/35"></div>
</div>
<div class="view-layer absolute inset-0 w-full h-full bg-cover bg-center opacity-0 scale-105 pointer-events-none" id="layer-roof" style="background-image:url('<?= lw_e($heroTechoAlt) ?>')">
<div class="absolute inset-0 bg-gradient-to-t from-volcanic-ash/80 via-transparent to-volcanic-ash/30"></div>
</div>
<div class="view-layer absolute inset-0 w-full h-full bg-cover bg-center opacity-0 scale-105 pointer-events-none" id="layer-interior" style="background-image:url('<?= lw_e($heroInterior) ?>')">
<div class="absolute inset-0 bg-gradient-to-t from-volcanic-ash/80 via-transparent to-volcanic-ash/30"></div>
</div>

<!-- Hotspots: reposicionados SOBRE la foto real (heroDay), no los % del mockup -->
<div class="hotspot group absolute z-20 -translate-x-1/2 -translate-y-1/2 cursor-pointer transition-transform hover:scale-110" id="hotspot-roof" style="top:24%;left:50%" onclick="lwSetView('roof')">
<span class="absolute -inset-2.5 rounded-full bg-surface/30 animate-ping"></span>
<span class="relative flex items-center justify-center w-8 h-8 rounded-full bg-surface/95 text-territorial-green shadow-xl border border-surface-container-highest">
<span class="material-symbols-outlined text-[16px]">roofing</span>
</span>
<div class="absolute left-10 top-1/2 -translate-y-1/2 hidden group-hover:flex flex-col bg-surface/95 text-on-surface backdrop-blur-md px-3.5 py-1.5 rounded-xl shadow-xl pointer-events-none whitespace-nowrap min-w-[150px] border border-surface-container-highest">
<span class="text-[10px] uppercase tracking-wider text-on-surface-variant font-medium"><?= lw_i18n('Techo', 'Roof') ?></span>
<span class="font-label-md text-body-sm text-primary font-semibold" id="hs-roof-nb"><?= lw_e($techosComp['sirap']['nombre'] ?? 'Roof') ?></span>
</div>
</div>
<div class="hotspot group absolute z-20 -translate-x-1/2 -translate-y-1/2 cursor-pointer transition-transform hover:scale-110" id="hotspot-pool" style="top:74%;left:33%" onclick="lwSetView('day')">
<span class="absolute -inset-2.5 rounded-full bg-secondary-fixed/40 animate-ping"></span>
<span class="relative flex items-center justify-center w-8 h-8 rounded-full bg-deep-lagoon text-on-secondary shadow-xl border border-white/20">
<span class="material-symbols-outlined text-[16px]">pool</span>
</span>
<div class="absolute left-10 top-1/2 -translate-y-1/2 hidden group-hover:flex flex-col bg-surface/95 text-on-surface backdrop-blur-md px-3.5 py-1.5 rounded-xl shadow-xl pointer-events-none whitespace-nowrap min-w-[150px] border border-surface-container-highest">
<span class="text-[10px] uppercase tracking-wider text-on-surface-variant font-medium"><?= lw_i18n('Piscina', 'Pool') ?></span>
<span class="font-label-md text-body-sm text-deep-lagoon font-semibold">Overflow pool, sukabumi stone</span>
</div>
</div>
<div class="hotspot group absolute z-20 -translate-x-1/2 -translate-y-1/2 cursor-pointer transition-transform hover:scale-110" id="hotspot-interior" style="top:48%;left:48%" onclick="lwSetView('interior')">
<span class="absolute -inset-2.5 rounded-full bg-tertiary-fixed/30 animate-ping"></span>
<span class="relative flex items-center justify-center w-8 h-8 rounded-full bg-surface/95 text-primary shadow-xl border border-surface-container-highest">
<span class="material-symbols-outlined text-[16px]">bed</span>
</span>
<div class="absolute left-10 top-1/2 -translate-y-1/2 hidden group-hover:flex flex-col bg-surface/95 text-on-surface backdrop-blur-md px-3.5 py-1.5 rounded-xl shadow-xl pointer-events-none whitespace-nowrap min-w-[150px] border border-surface-container-highest">
<span class="text-[10px] uppercase tracking-wider text-on-surface-variant font-medium"><?= lw_i18n('Interior', 'Interior') ?></span>
<span class="font-label-md text-body-sm text-primary font-semibold">AC &amp; hot water included</span>
</div>
</div>
</div>

<!-- HUD superior: real y estático, sin clima en vivo ni audio inventado -->
<div class="absolute top-4 left-6 md:left-margin-desktop z-30 flex items-center gap-3">
<div class="glass-panel px-4 py-2 rounded-full shadow-md flex items-center gap-2.5 border border-surface-container-highest/80">
<span class="w-2.5 h-2.5 rounded-full bg-territorial-green animate-pulse"></span>
<span class="font-label-md text-body-sm text-primary font-semibold"><?= lw_e($villa) ?></span>
<span class="text-stone-sand text-xs">|</span>
<span class="font-body-sm text-body-sm text-on-surface-variant"><?= lw_i18n('Costa oeste de Bali', "Bali's west coast") ?></span>
</div>
</div>

<!-- Dock de cámara: solo las 3 vistas reales -->
<div class="absolute bottom-8 md:bottom-10 left-6 md:left-margin-desktop z-30 flex items-center gap-3">
<div class="glass-dock p-1.5 rounded-full shadow-2xl flex items-center gap-1 border border-white/10">
<button class="cam-btn flex items-center gap-2 px-3.5 py-1.5 rounded-full font-label-md text-body-sm bg-surface text-primary shadow-sm font-semibold transition-all" id="cam-day" onclick="lwSetView('day')">
<span class="material-symbols-outlined text-[17px]">wb_sunny</span>
<span class="hidden md:inline"><?= lw_i18n('Día', 'Day') ?></span>
</button>
<button class="cam-btn flex items-center gap-2 px-3.5 py-1.5 rounded-full font-label-md text-body-sm text-white/90 hover:text-white hover:bg-white/10 transition-all" id="cam-roof" onclick="lwSetView('roof')">
<span class="material-symbols-outlined text-[17px]">roofing</span>
<span class="hidden md:inline"><?= lw_i18n('Techo firma', 'Signature roof') ?></span>
</button>
<button class="cam-btn flex items-center gap-2 px-3.5 py-1.5 rounded-full font-label-md text-body-sm text-white/90 hover:text-white hover:bg-white/10 transition-all" id="cam-interior" onclick="lwSetView('interior')">
<span class="material-symbols-outlined text-[17px]">bed</span>
<span class="hidden md:inline"><?= lw_i18n('Interior', 'Interior') ?></span>
</button>
</div>
<a class="hidden xl:flex items-center gap-2 glass-panel px-4 py-2 rounded-full shadow-md border border-surface-container-highest/80 text-primary hover:text-deep-lagoon hover:bg-white transition-all group" href="#section-layout">
<span class="text-xs font-label-md font-semibold tracking-wider uppercase"><?= lw_i18n('Explorar proyecto', 'Explore project') ?></span>
<span class="material-symbols-outlined text-[18px] group-hover:translate-y-0.5 transition-transform">arrow_downward</span>
</a>
</div>
<?php endif; ?>

<!-- ═══ CAJÓN DEL CONFIGURADOR: villa → techo → extras (motor real, sin tocar) ═══════ -->
<aside class="absolute top-4 right-4 md:right-8 bottom-8 md:bottom-10 z-40 w-[92vw] sm:w-[460px] glass-panel rounded-2xl shadow-2xl border border-surface-container-highest/80 flex flex-col overflow-hidden">
<div class="p-5 pb-3 border-b border-surface-container-highest/70 flex flex-col gap-2">
<div class="flex items-center justify-between">
<span class="px-3 py-0.5 rounded-full bg-soft-canopy/20 text-territorial-green font-label-md text-xs uppercase tracking-widest font-semibold">New build · Turnkey</span>
<div class="flex items-center gap-1 text-deep-lagoon text-xs font-semibold">
<span class="material-symbols-outlined text-[15px]">verified</span>
<span>PT Tepi Sun Gai · Registered Developer</span>
</div>
</div>
<div class="flex items-baseline justify-between">
<div>
<h1 class="font-headline-md text-[28px] leading-tight text-primary font-bold"><?= lw_e($villa) ?></h1>
<p class="font-body-sm text-body-sm text-on-surface-variant"><?= lw_e($m['sub_en'] ?? '') ?></p>
</div>
</div>
<div class="grid grid-cols-3 gap-2 pt-1">
<div class="bg-surface-container/70 p-2 rounded-xl border border-surface-container-highest/50 flex flex-col">
<span class="text-[10px] text-on-surface-variant uppercase tracking-wider"><?= lw_i18n('Superficie', 'Built area') ?></span>
<span class="font-kpi-number text-sm text-on-surface font-bold"><?= lw_e($sizeTxt) ?></span>
</div>
<div class="bg-surface-container/70 p-2 rounded-xl border border-surface-container-highest/50 flex flex-col">
<span class="text-[10px] text-on-surface-variant uppercase tracking-wider"><?= lw_i18n('Distribución', 'Layout') ?></span>
<span class="font-kpi-number text-sm text-on-surface font-bold"><?= lw_e($dorm . ' bed · ' . $banos . ' bath') ?></span>
</div>
<div class="bg-primary/10 p-2 rounded-xl border border-primary/20 flex flex-col">
<span class="text-[10px] text-primary uppercase tracking-wider font-semibold"><?= lw_i18n('Desde', 'From') ?></span>
<span class="font-kpi-number text-sm text-territorial-green font-bold"<?= $precioValor !== null ? ' data-eur-fijo="' . (int) $precioValor . '"' : '' ?>><?= lw_e($precioTxt) ?></span>
</div>
</div>
<div class="flex items-center justify-center gap-1.5 pt-2">
<span class="font-label-md text-xs text-on-surface-variant font-semibold" id="lw-paso-lb">Step 1 of 3</span>
</div>
</div>

<!-- Cuerpo scrollable: paso 1 villa (server-render, clases Tailwind reales) + paso 2/3
     (contenedores vacíos, los pinta assets/au-landing-cfg.js con class="op") -->
<div class="flex-1 overflow-y-auto p-5 space-y-5 res">
<div class="cfg__step space-y-3" data-paso="1">
<div class="flex flex-col mb-1">
<span class="font-headline-sm text-headline-sm text-primary font-semibold"><?= lw_i18n('¿Qué villa?', 'Which villa?') ?></span>
<p class="font-body-sm text-body-sm text-on-surface-variant">Same construction system across the range — only the size changes the price.</p>
</div>
<?php foreach ($CAT as $cmId => $v): ?>
<label class="vcard cursor-pointer p-3.5 rounded-xl border-2 border-surface-container-highest bg-surface-container-low transition-all flex items-start justify-between gap-3 hover:border-primary/50">
<div class="flex items-start gap-3">
<input type="radio" name="lw-villa" value="<?= lw_e($cmId) ?>"<?= $cmId === $m['id'] ? ' checked' : '' ?> class="mt-1 text-primary focus:ring-primary h-4 w-4">
<?php if ($v['thumb']): ?><img class="op__th" src="<?= lw_e($v['thumb']) ?>" alt="" loading="lazy"><?php endif; ?>
<div class="flex flex-col">
<span class="font-label-md text-body-md text-on-surface font-semibold"><?= lw_e($v['villa']) ?></span>
<span class="font-body-sm text-xs text-on-surface-variant"><?= lw_e($v['specs']) ?></span>
</div>
</div>
<span class="font-label-md text-xs text-primary font-bold whitespace-nowrap"><?= lw_e(lw_precio_fmt($v['desde_eur'])) ?></span>
</label>
<?php endforeach; ?>
</div>

<div class="cfg__step space-y-2" data-paso="2" hidden>
<div class="flex flex-col mb-1">
<span class="font-headline-sm text-headline-sm text-primary font-semibold"><?= lw_i18n('¿Qué techo?', 'Which roof?') ?></span>
<p class="font-body-sm text-body-sm text-on-surface-variant">Two complete villa prices, not an add-on — the roof you choose is the price of the villa.</p>
</div>
<div id="lw-techos" class="space-y-2"></div>
</div>

<div class="cfg__step space-y-2" data-paso="3" hidden>
<div class="flex flex-col mb-1">
<span class="font-headline-sm text-headline-sm text-primary font-semibold"><?= lw_i18n('¿Algún extra?', 'Any extras?') ?></span>
<p class="font-body-sm text-body-sm text-on-surface-variant">Optional — none of them is needed to move in. The plot is priced separately, sized on the call (from €125/m²).</p>
</div>
<div id="lw-extras" class="space-y-2"></div>
</div>

<!-- Resumen — lo escribe recalcular() en au-landing-cfg.js -->
<div class="pt-3 border-t border-surface-container-highest/70 space-y-2 text-xs text-on-surface-variant">
<div class="flex justify-between gap-3"><span id="lw-r-villa" class="font-semibold text-on-surface"></span><span id="lw-r-villa-pr" class="font-kpi-number text-primary"></span></div>
<div id="lw-r-villa-sub"></div>
<div class="flex justify-between gap-3"><span id="lw-r-extras" class="font-semibold text-on-surface"></span><span id="lw-r-extras-pr" class="font-kpi-number text-primary"></span></div>
<div id="lw-r-extras-sub"></div>
</div>
</div>

<!-- Pie: navegación de pasos + precio en vivo + CTA WhatsApp directo (sin modal) -->
<div class="p-4 md:p-5 border-t border-surface-container-highest/80 bg-surface/95 flex flex-col gap-3">
<div class="flex items-center justify-between">
<div class="flex flex-col">
<span class="text-[10px] text-on-surface-variant uppercase tracking-wider font-semibold"><?= lw_i18n('Total configurado', 'Configured total') ?></span>
<span class="font-kpi-number text-2xl text-primary font-bold" id="lw-total"></span>
<span class="text-[11px] text-on-surface-variant" id="lw-total-alt"></span>
</div>
<div class="flex items-center gap-2">
<button class="w-9 h-9 rounded-full bg-surface-container hover:bg-surface-container-high border border-surface-container-highest flex items-center justify-center text-on-surface disabled:opacity-40 disabled:pointer-events-none transition-all" id="lw-atras" hidden>
<span class="material-symbols-outlined text-[18px]">chevron_left</span>
</button>
<button class="px-4 py-2 rounded-full bg-primary hover:bg-territorial-green text-on-primary font-label-md text-xs font-semibold shadow-md transition-all flex items-center gap-1" id="lw-siguiente"><span>Next </span><span class="material-symbols-outlined text-[15px]">chevron_right</span></button>
</div>
</div>
<div class="flex items-center justify-center gap-1.5" id="lw-puntos"></div>
<a class="w-full py-3 rounded-full bg-deep-lagoon hover:bg-secondary text-on-secondary font-label-md text-body-sm font-semibold shadow-lg transition-all flex items-center justify-center gap-2" id="lw-wa-cta" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
<span class="material-symbols-outlined text-[17px]">chat</span>
<span><?= lw_i18n('Escribir por WhatsApp', 'Message us on WhatsApp') ?></span>
</a>
</div>
</aside>
</div>
</section>

<!-- ═══ 1 · DISTRIBUCIÓN ═════════════════════════════════════════════════════════════ -->
<section class="py-24 px-6 md:px-margin-desktop bg-surface relative border-b border-surface-container-highest/80" id="section-layout">
<div class="max-w-7xl mx-auto">
<div class="flex items-center gap-2 mb-3">
<span class="w-2.5 h-2.5 rounded-full bg-territorial-green"></span>
<span class="font-label-md text-xs uppercase tracking-widest text-primary font-semibold">01 · <?= lw_i18n('Distribución', 'Layout') ?></span>
</div>
<div class="flex flex-col md:flex-row md:items-end justify-between gap-4 mb-12">
<div>
<h2 class="font-headline-lg text-3xl md:text-[44px] text-primary leading-tight font-bold"><?= lw_i18n('Distribución bioclimática', 'Bioclimatic layout') ?></h2>
<p class="font-body-lg text-on-surface-variant max-w-2xl mt-2">Open-plan pavilion under a single roof, with cross-ventilation and a private plunge pool.</p>
</div>
</div>
<div class="grid grid-cols-1 lg:grid-cols-12 gap-10 lg:gap-14 items-center">
<div class="lg:col-span-7 relative group">
<div class="relative rounded-3xl overflow-hidden shadow-2xl bg-surface-container-high border border-surface-container-highest/90 corner-accent">
<?php if ($layoutImg): ?>
<img alt="<?= lw_e($villa) ?> floor plan" class="w-full h-auto max-h-[700px] object-cover object-center group-hover:scale-105 transition-transform duration-700" src="<?= lw_e($layoutImg) ?>" loading="lazy">
<?php endif; ?>
<div class="absolute top-6 right-6 glass-panel px-4 py-2 rounded-2xl shadow-xl border border-surface-container-highest flex flex-col items-end">
<span class="text-[10px] uppercase font-bold tracking-widest text-on-surface-variant"><?= lw_i18n('Superficie total', 'Total area') ?></span>
<span class="font-kpi-number text-xl text-primary font-bold"><?= (int) $m['villa_m2'] + (int) $m['terraza_m2'] ?> m²</span>
<span class="text-[11px] text-territorial-green font-medium"><?= (int) $m['villa_m2'] ?> m² interior + <?= (int) $m['terraza_m2'] ?> m² deck</span>
</div>
</div>
</div>
<div class="lg:col-span-5 flex flex-col space-y-6">
<div class="bg-surface-container-low p-6 rounded-2xl border border-surface-container-highest space-y-3">
<div class="flex items-center gap-2 text-territorial-green text-xs font-bold uppercase tracking-wider">
<span class="material-symbols-outlined text-[17px]">eco</span>
<span><?= lw_i18n('Diseño pasivo', 'Passive design') ?></span>
</div>
<h3 class="font-headline-md text-2xl text-primary font-bold">Turnkey EPC, fixed price</h3>
<p class="font-body-md text-on-surface-variant leading-relaxed">Every project runs on a guaranteed fixed-price written EPC contract — Indonesian VAT (PPN) included, closing costs quoted separately and detailed before you sign.</p>
</div>
<!-- Specs desde el alcance real de obra ($m['alcance']['incluido']), no la poesía del mockup -->
<div class="space-y-3.5">
<?php
$specIcons = ['bed', 'roofing', 'pool', 'air', 'bolt', 'engineering'];
$incluido  = (array) ($m['alcance']['incluido'] ?? []);
$i = 0;
foreach ($incluido as $it):
    $txt = is_array($it) ? ($it['en'] ?? $it['es'] ?? '') : (string) $it;
    if ($txt === '') continue;
    $ic = $specIcons[$i % count($specIcons)];
    $i++;
?>
<div class="flex items-start gap-3.5 p-3.5 rounded-xl bg-surface-container/60 border border-surface-container-highest hover:bg-surface-container transition-colors">
<span class="w-8 h-8 rounded-full bg-territorial-green/10 text-territorial-green flex items-center justify-center shrink-0 mt-0.5">
<span class="material-symbols-outlined text-[18px]"><?= lw_e($ic) ?></span>
</span>
<span class="font-label-md text-body-md text-primary font-semibold"><?= lw_e($txt) ?></span>
</div>
<?php endforeach; ?>
</div>
<!-- Sin PDF publico (modelo_documentos.visible_portal=false para Dali) — CTA a WhatsApp -->
<div class="pt-2">
<a class="w-full py-3 px-5 rounded-full border border-primary text-primary hover:bg-primary hover:text-on-primary transition-all font-label-md text-body-sm font-semibold flex items-center justify-center gap-2" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
<span class="material-symbols-outlined text-[18px]">description</span>
<span><?= lw_i18n('Solicitar el dossier completo', 'Request the full dossier') ?></span>
</a>
</div>
</div>
</div>
</div>
</section>

<?php if ($techosComp): ?>
<!-- ═══ 2 · CUBIERTAS ════════════════════════════════════════════════════════════════ -->
<section class="py-24 px-6 md:px-margin-desktop bg-surface-container-low relative border-b border-surface-container-highest/80" id="section-cubiertas">
<div class="max-w-7xl mx-auto">
<div class="text-center max-w-3xl mx-auto mb-16 space-y-3">
<div class="inline-flex items-center gap-2 px-3.5 py-1 rounded-full bg-soft-canopy/15 border border-soft-canopy/30 text-territorial-green text-xs font-semibold uppercase tracking-widest">
<span><?= lw_i18n('Materialidad', 'Craft & materiality') ?></span>
</div>
<h2 class="font-headline-lg text-3xl md:text-[44px] text-primary font-bold leading-tight">Roof finishes</h2>
<p class="font-body-lg text-on-surface-variant leading-relaxed">Two complete villa prices, not an add-on — the roof you choose is the price of the villa.</p>
</div>
<div class="grid grid-cols-1 md:grid-cols-2 gap-8 lg:gap-10">
<div class="bg-surface rounded-3xl overflow-hidden border border-surface-container-highest/90 shadow-xl flex flex-col group hover:-translate-y-1.5 transition-all duration-300">
<div class="relative h-72 lg:h-80 overflow-hidden bg-volcanic-ash">
<?php if ($heroDay): ?><img alt="<?= lw_e($techosComp['sirap']['nombre']) ?>" class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" src="<?= lw_e($heroDay) ?>" loading="lazy"><?php endif; ?>
<div class="absolute inset-0 bg-gradient-to-t from-volcanic-ash/70 via-transparent to-transparent"></div>
<div class="absolute bottom-4 left-4 right-4 flex items-end justify-between">
<span class="font-headline-md text-2xl text-white font-bold"><?= lw_e($techosComp['sirap']['nombre']) ?></span>
<span class="font-kpi-number text-lg text-surface font-bold bg-primary/80 px-3 py-1 rounded-lg backdrop-blur-sm"><?= lw_e(lw_precio_fmt($techosComp['sirap']['now'] ?? null)) ?></span>
</div>
</div>
<div class="p-6 md:p-8 flex flex-col justify-between flex-1 space-y-6">
<div class="space-y-3">
<h3 class="font-headline-sm text-2xl text-primary font-bold"><?= lw_e($techosComp['sirap']['nombre']) ?></h3>
<p class="font-body-md text-on-surface-variant leading-relaxed"><?= lw_e($techosComp['sirap']['desc'] ?? '') ?></p>
<?php if ($antes2027 && !empty($techosComp['sirap']['y2027'])): ?>
<p class="text-[11px] text-on-surface-variant">2026 price shown. From 2027: <?= lw_e(lw_precio_fmt($techosComp['sirap']['y2027'])) ?>.</p>
<?php endif; ?>
</div>
</div>
</div>
<div class="bg-surface rounded-3xl overflow-hidden border-2 border-primary/40 shadow-xl flex flex-col group hover:-translate-y-1.5 transition-all duration-300 relative">
<div class="relative h-72 lg:h-80 overflow-hidden bg-volcanic-ash">
<?php if ($heroTechoAlt): ?><img alt="<?= lw_e($techosComp['bambu']['nombre']) ?>" class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" src="<?= lw_e($heroTechoAlt) ?>" loading="lazy"><?php endif; ?>
<div class="absolute inset-0 bg-gradient-to-t from-volcanic-ash/70 via-transparent to-transparent"></div>
<div class="absolute bottom-4 left-4 right-4 flex items-end justify-between">
<span class="font-headline-md text-2xl text-white font-bold"><?= lw_e($techosComp['bambu']['nombre']) ?></span>
<span class="font-kpi-number text-lg text-white font-bold bg-deep-lagoon/90 px-3 py-1 rounded-lg backdrop-blur-sm"><?= lw_e(lw_precio_fmt($techosComp['bambu']['now'] ?? null)) ?></span>
</div>
</div>
<div class="p-6 md:p-8 flex flex-col justify-between flex-1 space-y-6">
<div class="space-y-3">
<h3 class="font-headline-sm text-2xl text-primary font-bold"><?= lw_e($techosComp['bambu']['nombre']) ?></h3>
<p class="font-body-md text-on-surface-variant leading-relaxed"><?= lw_e($techosComp['bambu']['desc'] ?? '') ?></p>
<?php if ($antes2027 && !empty($techosComp['bambu']['y2027'])): ?>
<p class="text-[11px] text-on-surface-variant">2026 price shown. From 2027: <?= lw_e(lw_precio_fmt($techosComp['bambu']['y2027'])) ?>.</p>
<?php endif; ?>
</div>
</div>
</div>
</div>
</div>
</section>
<?php endif; ?>

<!-- ═══ 3 · SNAPSHOT FINANCIERO + FAQ ════════════════════════════════════════════════ -->
<section class="py-24 px-6 md:px-margin-desktop bg-surface relative border-b border-surface-container-highest/80" id="section-financial">
<div class="max-w-7xl mx-auto">
<div class="flex items-center gap-2 mb-3">
<span class="w-2.5 h-2.5 rounded-full bg-territorial-green"></span>
<span class="font-label-md text-xs uppercase tracking-widest text-primary font-semibold">03 · <?= lw_i18n('Inversión', 'Investment') ?></span>
</div>
<div class="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-16 items-start">
<div class="lg:col-span-6 space-y-4">
<?php if ($finCalc): ?>
<div class="bg-surface-container-low rounded-3xl p-6 md:p-8 border border-surface-container-highest shadow-xl space-y-6">
<div class="border-b border-surface-container-highest/80 pb-4">
<span class="font-label-md text-xs text-territorial-green uppercase tracking-widest font-semibold"><?= lw_i18n('Ejemplo real', 'Real example') ?></span>
<h3 class="font-headline-md text-2xl md:text-3xl text-primary font-bold"><?= lw_e($deckEtiqueta) ?></h3>
<p class="font-body-sm text-body-sm text-on-surface-variant mt-1">Economics of one plot at Palm Field — not this page's model, and not a promise of yield.</p>
</div>
<?php foreach ($finCalc as $caso => $f): $label = $caso === 'average' ? 'Average' : 'Optimal'; ?>
<div class="bg-surface p-4 rounded-2xl border border-surface-container-highest space-y-2">
<div class="flex items-center justify-between">
<span class="font-label-md text-xs uppercase tracking-wider text-on-surface-variant font-semibold"><?= lw_e($label) ?></span>
<span class="font-kpi-number text-lg <?= $caso === 'optimal' ? 'text-deep-lagoon' : 'text-territorial-green' ?> font-bold"><?= lw_e(lw_precio_fmt($f['neto'])) ?>/yr net</span>
</div>
<div class="text-[11px] text-on-surface-variant"><?= lw_e(lw_precio_fmt($f['adr'])) ?> ADR × <?= (int) round($f['ocup'] * 100) ?>% occupancy — gross <?= lw_e(lw_precio_fmt($f['bruto'])) ?>, minus management + maintenance + tax (<?= lw_e(lw_precio_fmt($f['costes'])) ?>)</div>
</div>
<?php endforeach; ?>
<p class="text-[11px] text-on-surface-variant leading-relaxed">Total investment used in this example: <?= lw_e(lw_precio_fmt($deckEj['inversion_base'])) ?>. Indicative only, not a quote or financial advice — actual rental income depends on the plot, the season and how the villa is managed.</p>
</div>
<?php endif; ?>
</div>
<div class="lg:col-span-6 space-y-4">
<div>
<span class="font-label-md text-xs text-territorial-green uppercase tracking-widest font-semibold"><?= lw_i18n('Dudas legales', 'Legal & practical') ?></span>
<h3 class="font-headline-md text-2xl md:text-3xl text-primary font-bold mb-2"><?= lw_i18n('Preguntas frecuentes', 'Frequently asked questions') ?></h3>
</div>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Qué compro exactamente y en qué régimen?', 'What exactly am I buying, and under what title?') ?></span><span class="material-symbols-outlined mi text-on-surface-variant text-[20px]">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">La villa construida y el derecho sobre la parcela en la que se levanta. En Indonesia ese derecho no funciona como la propiedad española y no todas las parcelas están en el mismo régimen ni con el mismo plazo. Es la primera cosa que repasamos en la llamada, parcela por parcela y con el documento delante, antes de hablar de dinero.</p>
<p class="i-en">The built villa and the right over the plot it stands on. In Indonesia that right doesn't work like Spanish-style ownership, and not every plot sits under the same scheme or term. We review it plot by plot on the call, document in hand, before talking numbers.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Qué incluye el precio?', "What's included in the price?") ?></span><span class="material-symbols-outlined mi text-on-surface-variant text-[20px]">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">La obra completa según el pliego del contratista, con el acabado de cubierta que elijas. El precio de la villa ya incluye el IVA indonesio (PPN). La parcela y los gastos de compraventa (impuesto de transmisión, notaría y licencias) se presupuestan aparte y se detallan por escrito antes de firmar nada.</p>
<p class="i-en">The full build with the roof finish you choose. The villa price already includes Indonesian VAT (PPN). The plot, and the closing costs on the purchase (transfer tax, notary and permits), are quoted separately and detailed in writing before you sign.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Puedo elegir dónde se construye?', 'Can I choose where it gets built?') ?></span><span class="material-symbols-outlined mi text-on-surface-variant text-[20px]">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">Sí. El modelo es el mismo y se levanta sobre la parcela que elijas del catálogo. Cambian la vista, la orientación y el precio del terreno. No todas las parcelas admiten cualquier modelo: eso se concreta en la llamada.</p>
<p class="i-en">Yes. The model stays the same and is built on the plot you choose from the catalog. The view, orientation, and land price change. Not every plot takes every model — that's confirmed on the call.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿En qué moneda se firma?', 'What currency is the contract in?') ?></span><span class="material-symbols-outlined mi text-on-surface-variant text-[20px]">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">El contrato se formaliza en rupias indonesias, como exige la ley indonesia para operaciones dentro del país. La equivalencia en euros se incluye a título informativo con el tipo de cambio de la fecha.</p>
<p class="i-en">The contract is executed in Indonesian rupiah, as required by Indonesian law for transactions inside the country. Other-currency equivalents are given for reference only, at the exchange rate on the date.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Cómo se formaliza la compra?', 'How is the purchase formalized?') ?></span><span class="material-symbols-outlined mi text-on-surface-variant text-[20px]">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">Primero un contrato de reserva sobre la parcela. Después el PPJB, que es el contrato de compraventa indonesio, y el contrato de construcción. Los tres son documentos propios del promotor y se revisan antes de firmar.</p>
<p class="i-en">First a reservation contract on the plot. Then the PPJB — the Indonesian sale contract — and the construction contract. All three are the developer's own documents and are reviewed before signing.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Quién construye?', 'Who builds it?') ?></span><span class="material-symbols-outlined mi text-on-surface-variant text-[20px]">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">Lawang Tropical Properties, a través de la sociedad indonesia PT Tepi Sun Gai. En la llamada te enseñamos obras entregadas y las que están en marcha ahora mismo.</p>
<p class="i-en">Lawang Tropical Properties, through the Indonesian company PT Tepi Sun Gai. On the call we show you delivered projects and the ones underway right now.</p>
</div>
</details>
</div>
</div>
</div>
</section>

<?php if ($otrosModelos): ?>
<!-- ═══ 4 · COLECCIÓN (CROSS-SELL) ═══════════════════════════════════════════════════ -->
<section class="py-24 px-6 md:px-margin-desktop bg-surface-container-low relative" id="section-collection">
<div class="max-w-7xl mx-auto">
<div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-14">
<div>
<span class="font-label-md text-xs uppercase tracking-widest text-territorial-green font-semibold"><?= lw_i18n('Catálogo', 'Catalog') ?></span>
<h2 class="font-headline-lg text-3xl md:text-[44px] text-primary font-bold leading-tight mt-1">More from the collection</h2>
<p class="font-body-lg text-on-surface-variant max-w-2xl mt-2">Same construction system and roof choice across the range — only the size changes the price.</p>
</div>
<a class="inline-flex items-center gap-2 px-5 py-2.5 rounded-full border border-primary text-primary hover:bg-primary hover:text-on-primary font-label-md text-body-sm font-semibold transition-all" href="#hero-configurator">
<span><?= lw_i18n('Volver al configurador', 'Back to configurator') ?></span>
<span class="material-symbols-outlined text-[17px]">north</span>
</a>
</div>
<div class="grid grid-cols-1 md:grid-cols-3 gap-8">
<?php foreach ($otrosModelos as $ocId => $ov): ?>
<a class="bg-surface rounded-3xl overflow-hidden border border-surface-container-highest shadow-lg flex flex-col group hover:-translate-y-2 transition-all duration-300" href="/<?= lw_e(lw_modelo_url_path($ocId)) ?>">
<div class="relative h-60 overflow-hidden bg-volcanic-ash">
<?php if ($ov['thumb']): ?><img alt="<?= lw_e($ov['villa']) ?>" class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" src="<?= lw_e($ov['thumb']) ?>" loading="lazy"><?php endif; ?>
<div class="absolute inset-0 bg-gradient-to-t from-volcanic-ash/80 via-transparent to-transparent"></div>
<div class="absolute bottom-4 left-4 right-4 flex justify-between items-end">
<span class="text-white font-headline-sm text-xl font-bold"><?= lw_e($ov['villa']) ?></span>
<span class="text-surface-container-lowest font-kpi-number text-lg font-bold"><?= lw_e(lw_precio_fmt($ov['desde_eur'])) ?></span>
</div>
</div>
<div class="p-6 flex-1 flex flex-col justify-between space-y-4">
<p class="font-body-sm text-xs text-on-surface-variant leading-relaxed"><?= lw_e($ov['specs']) ?></p>
<span class="w-full py-2.5 rounded-full bg-surface-container hover:bg-primary hover:text-on-primary text-primary font-label-md text-xs font-semibold tracking-wide border border-surface-container-highest transition-all flex items-center justify-center gap-1.5">
<span><?= lw_i18n('Ver ficha', 'View model') ?></span>
<span class="material-symbols-outlined text-[15px]">arrow_outward</span>
</span>
</div>
</a>
<?php endforeach; ?>
</div>
</div>
</section>
<?php endif; ?>

<!-- ═══ FOOTER ═══════════════════════════════════════════════════════════════════════ -->
<footer class="bg-surface-alt border-t border-surface-container-highest pt-20 pb-12 px-6 md:px-margin-desktop text-on-surface">
<div class="max-w-7xl mx-auto space-y-16">
<div class="grid grid-cols-1 lg:grid-cols-12 gap-12 items-start">
<div class="lg:col-span-5 space-y-4">
<img class="h-9" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
<p class="font-body-md text-sm text-on-surface-variant leading-relaxed max-w-md">PT Tepi Sun Gai · Registered Developer &amp; Property Advisory. Developing turnkey architectural villas in Bali, with fixed-price EPC contracts and titles transferred in writing.</p>
<div class="flex items-center gap-3 pt-2">
<span class="px-3 py-1 rounded-full bg-primary/10 text-primary text-xs font-semibold flex items-center gap-1">
<span class="material-symbols-outlined text-[14px]">receipt_long</span> Fixed-Price EPC
</span>
<span class="px-3 py-1 rounded-full bg-deep-lagoon/10 text-deep-lagoon text-xs font-semibold flex items-center gap-1">
<span class="material-symbols-outlined text-[14px]">verified</span> PPN Included
</span>
</div>
</div>
<div class="lg:col-span-4 grid grid-cols-2 gap-8">
<div class="space-y-3">
<span class="font-label-md text-xs uppercase tracking-wider text-primary font-bold"><?= lw_i18n('Colección', 'Collection') ?></span>
<ul class="space-y-2 text-xs font-body-sm text-on-surface-variant">
<?php foreach ($CAT as $lcId => $lv):
    // Mismo filtro que el cross-sell de mas abajo: un modelo sin render hace que
    // lw_modelo_get() devuelva null y rebote a /thecollection — un enlace de pie de
    // pagina que aterriza en un sitio distinto al que promete es peor que no listarlo.
    if ($lv['sinRender']) continue;
?>
<li><a class="hover:text-primary transition-colors" href="/<?= lw_e(lw_modelo_url_path($lcId)) ?>"><?= lw_e($lv['villa']) ?></a></li>
<?php endforeach; ?>
</ul>
</div>
<div class="space-y-3">
<span class="font-label-md text-xs uppercase tracking-wider text-primary font-bold"><?= lw_i18n('Información', 'Information') ?></span>
<ul class="space-y-2 text-xs font-body-sm text-on-surface-variant">
<li><a class="hover:text-primary transition-colors" href="#section-financial">Legal &amp; returns</a></li>
<li><a class="hover:text-primary transition-colors" href="#section-cubiertas">Roof finishes</a></li>
<li><a class="hover:text-primary transition-colors" href="#section-layout">Layout</a></li>
<li><a class="hover:text-primary transition-colors" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">WhatsApp</a></li>
</ul>
</div>
</div>
<div class="lg:col-span-3 space-y-2 bg-surface p-5 rounded-2xl border border-surface-container-highest">
<span class="font-label-md text-xs uppercase tracking-wider text-primary font-bold"><?= lw_i18n('WhatsApp', 'WhatsApp') ?></span>
<p class="font-body-sm text-xs text-on-surface-variant i-es">Te respondemos en horario de Bali (WITA).</p>
<p class="font-body-sm text-xs text-on-surface-variant i-en">We reply during Bali hours (WITA).</p>
<a class="w-full py-2 rounded-xl bg-primary hover:bg-territorial-green text-on-primary text-xs font-label-md font-semibold transition-all flex items-center justify-center" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer"><?= lw_e($WA_SHOW) ?></a>
</div>
</div>
<div class="pt-8 border-t border-surface-container-highest/80 grid grid-cols-1 md:grid-cols-2 gap-6 text-xs text-on-surface-variant">
<div>
<span class="font-bold text-primary block mb-1">Bali Office</span>
<span><?= lw_e($OFICINA) ?></span>
</div>
<div>
<span class="font-bold text-primary block mb-1"><?= lw_i18n('Líneas directas', 'Direct lines') ?></span>
<?php foreach ($TELEFONOS as $t): ?><span class="block"><a class="hover:text-primary" href="tel:<?= lw_e($t['tel']) ?>"><?= lw_e($t['show']) ?></a></span><?php endforeach; ?>
<span class="block"><a class="hover:text-primary" href="mailto:<?= lw_e($EMAIL) ?>"><?= lw_e($EMAIL) ?></a></span>
</div>
</div>
<div class="pt-6 border-t border-surface-container-highest/60 flex flex-col md:flex-row items-center justify-between gap-4 text-xs text-on-surface-variant/80">
<span class="i-es">© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Todos los derechos reservados.</span>
<span class="i-en">© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). All rights reserved.</span>
<div class="flex items-center gap-6">
<a class="hover:text-primary i-es" href="/legal-es">Aviso legal y privacidad</a>
<a class="hover:text-primary i-en" href="/legal">Legal &amp; privacy</a>
· <a class="hover:text-primary i-es" href="#" id="lw-cookies">Preferencias de cookies</a><a class="hover:text-primary i-en" href="#" id="lw-cookies-en">Cookie preferences</a>
</div>
</div>
</div>
</footer>

<!-- consent.js: gate del banner de cookies Y de window.lwTrack/Meta Pixel — SIN esto,
     track('ViewContent') de mas abajo comprueba `typeof window.lwTrack==='function'`,
     no lo encuentra, y no hace nada: la campana ES `es_ticket` apunta aqui y se quedaria
     sin pixel ni banner de consentimiento sin un solo error visible. Mismo fichero y
     mismo sello que /dali. -->
<script src="/assets/consent.js?v=20260908111654" defer></script>
<!-- Motor del configurador ANTES del script inline que lo invoca (window.lwAuCfgInit
     tiene que existir cuando se llama más abajo) — sin defer a propósito, o el inline
     que sigue se ejecutaría primero y fallaría "lwAuCfgInit is not a function". -->
<script src="/assets/au-landing-cfg.js?v=20260921160100"></script>
<script>
(function () {
  'use strict';
  // ── Crossfade + dock de cámara del hero (3 vistas reales) ─────────────────────────
  var LAYERS = {day: 'layer-day', roof: 'layer-roof', interior: 'layer-interior'};
  var BTNS   = {day: 'cam-day', roof: 'cam-roof', interior: 'cam-interior'};
  window.lwSetView = function (key) {
    if (!LAYERS[key]) return;
    Object.keys(LAYERS).forEach(function (k) {
      var layer = document.getElementById(LAYERS[k]);
      var btn   = document.getElementById(BTNS[k]);
      if (!layer) return;
      if (k === key) {
        layer.classList.remove('opacity-0', 'scale-105', 'pointer-events-none');
        layer.classList.add('opacity-100', 'scale-100');
        if (btn) btn.className = 'cam-btn flex items-center gap-2 px-3.5 py-1.5 rounded-full font-label-md text-body-sm bg-surface text-primary shadow-sm font-semibold transition-all';
      } else {
        layer.classList.remove('opacity-100', 'scale-100');
        layer.classList.add('opacity-0', 'scale-105', 'pointer-events-none');
        if (btn) btn.className = 'cam-btn flex items-center gap-2 px-3.5 py-1.5 rounded-full font-label-md text-body-sm text-white/90 hover:text-white hover:bg-white/10 transition-all';
      }
    });
  };

  var MODELO = <?= json_encode($m['id'], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  var CFG    = <?= json_encode($cfgJs, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
  var WA_NUM = <?= json_encode($WA_NUM, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;

  // ── Píxel: ViewContent al cargar, con value/currency cuando hay precio cerrado ────
  function track(ev, extra) {
    if (typeof window.lwTrack !== 'function') return;
    var p = Object.assign({content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO}, extra || {});
    var v = <?= json_encode($precioValor) ?>;
    if (v !== null && !('value' in p)) { p.value = v; p.currency = 'EUR'; }
    window.lwTrack(ev, p);
  }
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  // ── Configurador villa → techo → extras: motor compartido con /dali, SIN TOCAR ────
  window.lwAuCfgInit({
    cfg: CFG,
    waNum: WA_NUM,
    urlBase: '/<?= lw_e($slugPath) ?>',
    villaDefault: MODELO,
    waIntro: "Hi, I'm interested in the "
  });

  // ── Cookies: reabrir el aviso de consent.js ───────────────────────────────────────
  ['lw-cookies', 'lw-cookies-en'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.addEventListener('click', function (e) {
      e.preventDefault();
      if (window.lwConsentReopen) window.lwConsentReopen();
    });
  });
}());
</script>
</body>
</html>
