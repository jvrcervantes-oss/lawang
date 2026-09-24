<?php
/**
 * FICHA PUBLICADA de modelo — /modelo/<id>. Desde el 24-sep-2026 (owner) es la antigua v2
 * (/modelo/v2/<id>, ahora 301 aqui); la anterior se guarda en modelo/v1.php (/modelo/v1/<id>).
 * Al publicarla se deshicieron las tres diferencias de prueba de abajo: urlBase y enlaces de
 * la coleccion van a /modelo/<id> y ViewContent vuelve a dispararse.
 * --- historia de la v2 ---
 * 24-sep-2026, pedido del owner: "haz lo mismo para /modelos/" — misma piel y composicion que
 * el investor deck v3 (home de lawangproperties.com). NO sustituye a modelo/index.php.
 * Identico a index.php: todo el bloque PHP de datos de abajo, el motor del configurador
 * (assets/au-landing-cfg.js, compartido con /dali, sin tocar) con los mismos ids/names/data-paso,
 * y todo el texto visible (i18n-landing.js casa por texto; FAQ aprobada por Legal).
 * Cambia: la piel, y tres cosas deliberadas del <script> — urlBase apunta a /modelo/v2/<id>
 * (el motor hace replaceState sobre esa ruta), NO se dispara ViewContent (una pagina de prueba
 * no debe contaminar las metricas de la campaña) y la barra se vuelve solida al bajar.
 * SEO: noindex SIEMPRE y la canonica apunta a la ficha de verdad (/modelo/<id>).
 *
 * --- docblock original de index.php ---
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
 * Vistas del hero cinemático + la foto de la sección "Distribución": buscadas por el
 * PIE real de cada foto (21-sep-2026, `lw_foto_por_pie()` en catalogo.php), no por
 * posición en el array — desde que las fotos vienen de `deck_fotos` (subidas y
 * reordenables desde /intranet/modelos/) un índice fijo se desincroniza en cuanto alguien
 * añade o reordena una foto ahí. Con respaldo posicional para el modelo que no tenga
 * pies que casen con estos patrones (uno nuevo, subido sin etiquetar bien).
 *
 * 22-sep-2026: $heroInterior pasa a priorizar "living room" sobre "bedroom" — Dune y
 * Dream ya resolvían así de facto (no tienen foto con pie "bedroom" literal, solo
 * "Room 1"/"Room 2"), Dali era la única que enseñaba el dormitorio en vez del salón
 * completo. Ahora las tres son consistentes: el hotspot "Interior" enseña el espacio
 * de estar, no solo la cama. Kitchen/Toilet/Bamboo Aerea son fotos reales nuevas
 * (mismo pie en las 3 fichas, comprobado en Supabase antes de escribir esto), sin
 * respaldo posicional — si un modelo no las tiene aún, el hotspot/vista no aparece
 * (mismo criterio que $techosComp: nunca enseñar un hueco vacío como si fuera un dato).
 */
$heroDay      = lw_foto_por_pie($m['id'], ['sirap', 'ulin exterior']) ?? $g[0] ?? null;
$heroTechoAlt = lw_foto_por_pie($m['id'], ['bamboo exterior', 'bambu exterior']) ?? $g[2] ?? $g[1] ?? $g[0] ?? null;
$heroInterior = lw_foto_por_pie($m['id'], ['living room', 'bedroom', 'interior']) ?? $g[6] ?? $g[1] ?? $g[0] ?? null;
$heroKitchen  = lw_foto_por_pie($m['id'], ['kitchen']);
$heroToilet   = lw_foto_por_pie($m['id'], ['toilet']);
$heroAerea    = lw_foto_por_pie($m['id'], ['bamboo aerea', 'aerea']);
// "Top View" es la planta cenital real ya renderizada por el estudio (no un CAD que haya
// que inventar) — encaja mejor con lo que pide la sección "Distribución" que cualquier
// otra foto exterior. Nunca mezclar `??`/`?:` sin parentesis (PHP lo rechaza como fatal
// de sintaxis) — de ahi la variable intermedia en vez de encadenar todo en una línea.
$ultimoImg    = $g ? end($g) : null;
$layoutImg    = lw_foto_por_pie($m['id'], ['top view']) ?? $ultimoImg ?? $portada;

$dormTxt  = $dorm . ' ' . ($dorm === 1 ? 'bedroom' : 'bedrooms');

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

// ── Snapshot financiero ───────────────────────────────────────────────────────────
// 22-sep-2026: Dali, Dune (1 dormitorio) y Dream (2 dormitorios) pasan del ejemplo de
// UNA parcela real (Palm Field W5) al forecast de MERCADO que calcula la propia
// empresa por tamaño de vivienda (hoja "Forecast Alquiler Tabanan/Balian", tablas
// "Scenario 1 BR"/"Scenario 2 BR" en EUR — fuentes AirROI + informe NF Group Bali
// Q3 2025). La hoja trae DOS bases de inversión para el escenario 1BR (60.000€ arriba
// vs 80.000€ en "G2 Tabanan"); el owner confirmó la de 60.000€ — vale para Dali Y Dune
// por ser el mismo tamaño, no se volvió a preguntar. 2BR no tiene ese conflicto (una
// sola tabla en la hoja). Números tal cual los da la empresa (no recalculados aquí):
// Total Villa Income - las tres comisiones = Net Income, cuadra en todos los casos.
$LW_FORECAST_MERCADO = [
    'dali' => [
        'deckEj'  => ['proyecto' => 'Tabanan / Balian', 'mercado' => true, 'moneda' => 'EUR',
            'adr_medio' => 81, 'adr_optimo' => 94, 'ocupacion_media' => 0.59, 'ocupacion_optima' => 0.66,
            'inversion_base' => 60000],
        'finCalc' => [
            'average' => ['adr' => 81, 'ocup' => 0.59, 'bruto' => 19521, 'costes' => 6832, 'neto' => 12689],
            'optimal' => ['adr' => 94, 'ocup' => 0.66, 'bruto' => 22654, 'costes' => 7929, 'neto' => 14725],
        ],
    ],
    'dune' => [
        // Mismo tamaño (1 dormitorio) que Dali → misma tabla "Scenario 1 BR" de la hoja.
        'deckEj'  => ['proyecto' => 'Tabanan / Balian', 'mercado' => true, 'moneda' => 'EUR',
            'adr_medio' => 81, 'adr_optimo' => 94, 'ocupacion_media' => 0.59, 'ocupacion_optima' => 0.66,
            'inversion_base' => 60000],
        'finCalc' => [
            'average' => ['adr' => 81, 'ocup' => 0.59, 'bruto' => 19521, 'costes' => 6832, 'neto' => 12689],
            'optimal' => ['adr' => 94, 'ocup' => 0.66, 'bruto' => 22654, 'costes' => 7929, 'neto' => 14725],
        ],
    ],
    'dream' => [
        // 2 dormitorios → tabla "Scenario 2 BR" de la misma hoja, sin tabla alternativa.
        'deckEj'  => ['proyecto' => 'Tabanan / Balian', 'mercado' => true, 'moneda' => 'EUR',
            'adr_medio' => 115, 'adr_optimo' => 132, 'ocupacion_media' => 0.48, 'ocupacion_optima' => 0.54,
            'inversion_base' => 85000],
        'finCalc' => [
            'average' => ['adr' => 115, 'ocup' => 0.48, 'bruto' => 22655, 'costes' => 7930, 'neto' => 14725],
            'optimal' => ['adr' => 132, 'ocup' => 0.54, 'bruto' => 26004, 'costes' => 9101, 'neto' => 16903],
        ],
    ],
];
if (isset($LW_FORECAST_MERCADO[$m['id']])) {
    $deckEj  = $LW_FORECAST_MERCADO[$m['id']]['deckEj'];
    $finCalc = $LW_FORECAST_MERCADO[$m['id']]['finCalc'];
} else {
    // lw_deck_forecast_ejemplo() devuelve el mapa de TODOS los modelos con ejemplo
    // confirmado — se extrae el de ESTE modelo. Un modelo sin entrada (Loftbung,
    // Temple, Trinity) da null y la sección se oculta para él, nunca cae al ejemplo
    // de otro.
    $deckEj = lw_deck_forecast_ejemplo()[$m['id']] ?? null;
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
}

// ── "More from the collection" — reutiliza $CAT, mismo criterio "sin render no se enseña" ──
$otrosModelos = [];
foreach ($CAT as $ocId => $ov) {
    if ($ocId === $m['id'] || $ov['sinRender']) continue;
    $otrosModelos[$ocId] = $ov;
}

$WA_NUM   = '6281138319862';
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text=' . rawurlencode("Hi, I'm interested in the " . $villa . ' from Lawang Tropical Properties.');
// Telefonos, email y oficina ya NO viven aqui (23-sep-2026): solo los usaba el pie, que
// ahora es /assets/lawang-pie.js, compartido con /investor-deck. Fuente unica: ese fichero.
// 21-sep-2026: $portada YA es una URL absoluta (bucket público de Supabase) desde que las
// fotos dejaron el disco — solo el respaldo sin foto ('/assets/img/lugar/costa.webp') sigue
// siendo una ruta relativa del propio sitio. Sin esta rama, el prefijo de dominio de abajo
// duplicaba el esquema ("lawangproperties.comhttps://...supabase.co/..."), un og:image roto.
$ogImg = $portada ?? '/assets/img/lugar/costa.webp';
$ogImgAbs = (strpos($ogImg, 'http') === 0) ? $ogImg : 'https://lawangproperties.com' . $ogImg;
$slugPath = lw_modelo_url_path($m['id']);

// Etiqueta real del snapshot financiero (nombre del proyecto de ejemplo, nunca "este modelo").
$deckEtiqueta = $deckEj['proyecto'] ?? '';
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<script src="/assets/idioma-web.js?v=20260908113407"></script>
<script src="/assets/i18n-landing.js?v=20260923093252" defer></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($villa . $TITULO_SUFIJO) ?></title>
<meta name="description" content="<?= lw_e($villa) ?>: a new-build <?= lw_e($dormTxt) ?> villa, built on the plot you choose. Finishes, scope of works and price, configured live.">
<meta name="robots" content="noindex, nofollow">
<link rel="canonical" href="https://lawangproperties.com/<?= lw_e($slugPath) ?>">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="<?= lw_e($villa) ?> · Turnkey villa in Bali">
<meta property="og:description" content="Turnkey new build, <?= lw_e($dormTxt) ?>. You choose the plot and finish; the price is locked in writing before you sign.">
<meta property="og:url" content="https://lawangproperties.com/<?= lw_e($slugPath) ?>">
<meta property="og:image" content="<?= lw_e($ogImgAbs) ?>">
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
<style>
/* ════ /modelo v2 — piel de lawangproperties.com (home), mismo lenguaje que el investor
   deck v3 (24-sep, owner). Fuentes de marca self-hosted; The Seasons es DEMO y corrompe
   & - + 4: solo en el nombre de la villa y titulos sin esos glifos. ═══════════════════ */
@font-face{font-family:'The Seasons';src:url('/assets/fonts/TheSeasons-Light.otf') format('opentype');font-weight:300;font-display:swap}
@font-face{font-family:'The Seasons';src:url('/assets/fonts/TheSeasons-Regular.otf') format('opentype');font-weight:400;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-ExtraLight.otf') format('opentype');font-weight:200;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Light.otf') format('opentype');font-weight:300;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Book.otf') format('opentype');font-weight:400;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Medium.otf') format('opentype');font-weight:500;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Bold.otf') format('opentype');font-weight:700;font-display:swap}
:root{
  --tg:#485B37; --pg:#587040; --tg-dark:#364429; --dl:#104C4F; --be:#42210B; --sc:#8F9B7A;
  --va:#2E3437; --ss:#BEB3A5; --rl:#F5F0E6; --rl2:#EFE8DA; --cbr:#FBF8F1; --card:#11150E;
  --ci:#2E3437; --ci2:#5A5048; --ci3:#8A7A6A; --ob:#0A0C09;
  --se:'The Seasons','Cormorant Garamond',Georgia,serif;
  --sa:'Neue Kabel','Jost',system-ui,sans-serif;
  --cpd:clamp(22px,5vw,72px); --cmx:1280px; --menu-h:35px;
  --fs-display:clamp(52px,38px + 3.6vw,100px);
  --fs-h-xl:clamp(34px,28px + 1.9vw,58px);
  --fs-body-l:clamp(16px,15.5px + .15vw,18px);
  --fs-cap:clamp(11px,10.6px + .12vw,13px);
  --ease:cubic-bezier(.16,1,.3,1);
  --pw:420px;
}
html{scroll-behavior:smooth;scroll-padding-top:64px}
html,body{margin:0;padding:0}
body{background:var(--rl)!important;color:var(--ci);font-family:var(--sa)!important;-webkit-font-smoothing:antialiased}
h1,h2{text-wrap:balance} p{text-wrap:pretty}
.material-symbols-outlined{font-family:'Material Symbols Outlined';font-weight:normal;font-style:normal;font-size:24px;line-height:1;letter-spacing:normal;
  text-transform:none;display:inline-block;white-space:nowrap;word-wrap:normal;direction:ltr;-webkit-font-feature-settings:'liga';-webkit-font-smoothing:antialiased;
  font-variation-settings:'FILL' 0,'wght' 300,'GRAD' 0,'opsz' 24}
html[data-lang="es"] .i-en{display:none !important}
html:not([data-lang="es"]) .i-es{display:none !important}
.wrap{max-width:var(--cmx);margin:0 auto;padding-inline:var(--cpd);width:100%;box-sizing:border-box}

/* ── Topbar: #topbar de la home. Transparente sobre la foto, solida al bajar ── */
#lw-topbar{position:fixed;top:0;left:0;right:0;z-index:50;display:flex;align-items:center;justify-content:space-between;gap:1rem;
  padding:clamp(.68rem,1.65vh,1.05rem) clamp(1.1rem,4vw,3.4rem);transition:background .3s,box-shadow .3s,padding .3s}
#lw-topbar.solid{background:rgba(247,244,239,.94);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);
  box-shadow:0 1px 0 rgba(190,179,165,.3);padding-top:clamp(.5rem,1.2vh,.8rem);padding-bottom:clamp(.5rem,1.2vh,.8rem)}
#logo{display:flex;align-items:center;flex:1 1 0;min-width:0}
#logo img{height:28px;width:auto;display:block;flex:none}
#logo .lg-d{display:none}
#lw-topbar.solid #logo .lg-w{display:none}
#lw-topbar.solid #logo .lg-d{display:block}
#lw-topbar.solid #logo img{height:24px}
@media(max-width:640px){#logo img{height:22px}#lw-topbar.solid #logo img{height:20px}}
#lw-topbar nav{flex:none;display:none;align-items:center;gap:clamp(1rem,1.9vw,1.9rem);height:var(--menu-h);padding:0 1.5rem;
  background:rgba(20,18,14,.22);border:1px solid rgba(190,179,165,.45);border-radius:40px;backdrop-filter:blur(5px);-webkit-backdrop-filter:blur(5px);transition:background .3s,border-color .3s}
@media(min-width:1180px){#lw-topbar nav{display:flex}}
#lw-topbar.solid nav{background:rgba(255,255,255,.5);border-color:rgba(72,91,55,.28)}
.nav-link{position:relative;font-family:var(--sa);font-weight:300;font-size:.64rem;letter-spacing:.13em;text-transform:uppercase;
  color:rgba(245,240,230,.92);text-decoration:none;text-shadow:0 1px 8px rgba(0,0,0,.55);white-space:nowrap;transition:color .3s}
.nav-link::after{content:"";position:absolute;left:0;right:0;bottom:-7px;height:1.5px;background:var(--ss);transform:scaleX(0);transition:transform .32s var(--ease)}
.nav-link:hover{color:#fff}
.nav-link:hover::after,.nav-link.lw-nav-activa::after{transform:scaleX(1)}
#lw-topbar.solid .nav-link{color:rgba(26,22,18,.72);text-shadow:none}
#lw-topbar.solid .nav-link:hover,#lw-topbar.solid .nav-link.lw-nav-activa{color:var(--pg)}
#lw-topbar.solid .nav-link::after{background:var(--pg)}
#acciones{display:flex;align-items:center;justify-content:flex-end;gap:clamp(.7rem,1.6vw,1.4rem);flex:1 1 0;min-width:0}
.tb-precio{display:flex;flex-direction:column;align-items:flex-end;line-height:1.1;color:var(--rl);text-shadow:0 1px 8px rgba(0,0,0,.55)}
.tb-precio span:first-child{font-family:var(--sa);font-size:9.5px;letter-spacing:.22em;text-transform:uppercase;opacity:.8}
.tb-precio span:last-child{font-family:var(--sa);font-weight:300;font-size:17px;letter-spacing:.02em;white-space:nowrap}
#lw-topbar.solid .tb-precio{color:var(--ci);text-shadow:none}
@media(max-width:639px){.tb-precio{display:none}}
.tb-wa{display:inline-flex;align-items:center;gap:.5rem;text-decoration:none;height:var(--menu-h);padding:0 16px 0 7px;border-radius:30px;
  border:1px solid rgba(245,240,230,.5);color:var(--rl);font-family:var(--sa);font-weight:400;font-size:11px;letter-spacing:.14em;text-transform:uppercase;white-space:nowrap;transition:all .35s}
.tb-wa .wa{width:22px;height:22px;border-radius:50%;background:#25D366;display:flex;align-items:center;justify-content:center;color:#fff;flex:none}
.tb-wa .wa .material-symbols-outlined{font-size:14px}
.tb-wa:hover{background:rgba(245,240,230,.14)}
#lw-topbar.solid .tb-wa{background:var(--pg);border-color:var(--pg)}
#lw-topbar.solid .tb-wa:hover{background:#3a4a2c}
@media(max-width:820px){.tb-wa{display:none}}
/* idioma (i18n-landing.js lo monta en .nav__cta) + divisa: texto como la home, sin caja */
.lw-cur{position:relative;display:inline-flex;flex:none}
.lw-meta{display:flex;align-items:center;gap:6px;--lw-lang-ink:#f5f0e6;--lw-lang-bg:rgba(18,16,12,.88);--lw-lang-line:rgba(190,179,165,.38);--lw-lang-menu-ink:#f5f0e6;--lw-lang-hover:rgba(190,179,165,.18)}
.lw-meta .lw-cur,.lw-meta .lw-lang{display:flex}
.lw-meta *{font-family:var(--sa)!important;letter-spacing:.14em}
#lw-topbar:not(.solid) .lw-meta{text-shadow:0 1px 8px rgba(0,0,0,.55)}
#lw-topbar.solid .lw-meta{--lw-lang-ink:#2e3437;--lw-lang-bg:#fff;--lw-lang-line:rgba(72,91,55,.2);--lw-lang-menu-ink:#2e3437;--lw-lang-hover:rgba(72,91,55,.1)}
@media (max-width:1023px){ header .lw-lang__btn{min-height:40px} }

/* ── Titulares y botones de la home ── */
.kicker{display:inline-flex;align-items:center;gap:12px;font-family:var(--sa);font-size:var(--fs-cap);font-weight:500;letter-spacing:.26em;text-transform:uppercase;color:var(--tg);margin:0}
.kicker::before{content:"";width:30px;height:1px;background:currentColor;opacity:.5}
.center .kicker::before{display:none}
.titulo{font-family:var(--sa);font-weight:700;text-transform:uppercase;line-height:1.02;letter-spacing:.005em;color:var(--ci);font-size:var(--fs-h-xl);margin:0}
.entrada{font-family:var(--sa);font-size:var(--fs-body-l);line-height:1.75;color:var(--ci2);max-width:60ch;margin:0}
.cab{display:flex;flex-direction:column;gap:14px}
.cab.center{align-items:center;text-align:center;margin-inline:auto;max-width:860px}
.cab.center .entrada{margin-inline:auto}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;padding:14px 28px;border-radius:40px;font-family:var(--sa);font-size:11px;font-weight:500;
  letter-spacing:.14em;text-transform:uppercase;text-decoration:none;border:1px solid transparent;cursor:pointer;transition:transform .16s cubic-bezier(.23,1,.32,1),background .22s,color .22s,border-color .22s}
.btn:active{transform:scale(.97)}
.btn-hueso{border-color:rgba(245,240,230,.5);color:var(--rl);background:rgba(245,240,230,.06)} .btn-hueso:hover{background:rgba(245,240,230,.14)}
.btn-linea{border-color:rgba(46,52,55,.35);color:var(--ci)} .btn-linea:hover{border-color:var(--tg);color:var(--tg)}
.reveal{opacity:0;transform:translateY(28px);filter:blur(4px);transition:opacity .85s var(--ease),transform .85s var(--ease),filter .85s var(--ease)}
.reveal.in{opacity:1;transform:none;filter:none}
@media(prefers-reduced-motion:reduce){.reveal{transform:none;filter:none;transition:opacity .4s}}
.sec{position:relative;padding:clamp(4.5rem,11vh,8rem) 0}
.sec > .wrap{position:relative}
.sec-lino{background:var(--rl) url('/assets/img/bg-ecosystem.webp?v=2') center/cover}
.sec-lino::before{content:"";position:absolute;inset:0;background:rgba(245,240,230,.72);pointer-events:none}
.oscura{position:relative;background:var(--card);color:var(--rl);border-radius:16px;box-shadow:0 30px 60px -30px rgba(20,26,17,.6)}
.oscura.marco::after{content:"";position:absolute;inset:8px;border:1px solid rgba(245,240,230,.16);border-radius:10px;pointer-events:none}

/* ── HERO + CONFIGURADOR. Movil: foto arriba (alto fijo, dock y hotspots alcanzables) y
   panel debajo en flujo (leccion del 22-sep: nada se superpone en pantalla pequeña).
   Desde 1024px: foto a sangre 100svh y el panel de cristal oscuro flotando a la derecha. ── */
#hero-configurator{position:relative;background:var(--ob);color:var(--rl)}
#hero-visual{position:relative;width:100%;height:78svh;min-height:520px;overflow:hidden}
#viewport-canvas{position:absolute;inset:0;overflow:hidden;user-select:none}
.view-layer{position:absolute;inset:0;background-size:cover;background-position:center;transition:opacity .7s ease-out,transform .7s ease-out}
.view-layer.opacity-0{opacity:0}.view-layer.opacity-100{opacity:1}
.view-layer.scale-105{transform:scale(1.05)}.view-layer.scale-100{transform:scale(1)}
.view-layer.pointer-events-none{pointer-events:none}
.view-layer > div{position:absolute;inset:0;background:linear-gradient(to top,rgba(10,12,9,.86) 0%,rgba(10,12,9,.35) 40%,rgba(10,12,9,.05) 62%,rgba(10,12,9,.4) 100%)}
.hotspot{position:absolute;z-index:20;transform:translate(-50%,-50%);cursor:pointer;transition:opacity .3s ease,transform .15s ease}
.hotspot:hover{transform:translate(-50%,-50%) scale(1.1)}
.hs-pulso{position:absolute;inset:-10px;border-radius:50%;background:rgba(245,240,230,.25);animation:hsPing 2s cubic-bezier(0,0,.2,1) infinite}
@keyframes hsPing{75%,100%{transform:scale(1.8);opacity:0}}
.hs-punto{position:relative;display:flex;align-items:center;justify-content:center;width:34px;height:34px;border-radius:50%;
  background:rgba(12,14,10,.55);border:1px solid rgba(245,240,230,.6);color:var(--rl);backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px)}
.hs-punto .material-symbols-outlined{font-size:16px}
.hs-tip{position:absolute;left:44px;top:50%;transform:translateY(-50%);display:none;flex-direction:column;gap:2px;white-space:nowrap;min-width:150px;padding:8px 14px;border-radius:12px;
  background:rgba(12,14,10,.8);border:1px solid rgba(190,179,165,.35);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);pointer-events:none}
.hotspot:hover .hs-tip{display:flex}
.hs-tip span:first-child{font-family:var(--sa);font-size:9.5px;letter-spacing:.22em;text-transform:uppercase;color:var(--ss)}
.hs-tip span:last-child{font-family:var(--sa);font-size:13px;color:var(--rl)}
.sin-render{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;text-align:center;padding:0 24px}
.sin-render p:first-of-type{font-family:var(--sa);font-weight:500;font-size:22px;letter-spacing:.08em;text-transform:uppercase;margin:0}
.sin-render p:last-of-type{font-family:var(--sa);font-size:14px;color:rgba(245,240,230,.72);max-width:28rem;margin:0}
.hero-texto{position:absolute;z-index:25;left:var(--cpd);right:var(--cpd);bottom:clamp(96px,15vh,150px);pointer-events:none}
.hero-texto .kicker{color:var(--ss)} .hero-texto .kicker::before{background:var(--ss)}
.hero-texto h1{font-family:var(--se);font-weight:400;font-size:var(--fs-display);line-height:.92;letter-spacing:.01em;text-transform:uppercase;margin:.3em 0 0;color:var(--rl)}
.hero-texto .hero-sub{font-family:var(--sa);font-weight:500;font-size:clamp(12px,1vw,15px);letter-spacing:.14em;text-transform:uppercase;color:rgba(245,240,230,.88);margin:16px 0 0}
.hero-pie{position:absolute;z-index:30;left:var(--cpd);right:var(--cpd);bottom:clamp(22px,4vh,40px);display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.dock{display:flex;align-items:center;gap:2px;padding:4px;border-radius:40px;background:rgba(20,18,14,.35);border:1px solid rgba(190,179,165,.45);backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px)}
.cam-btn{display:flex;align-items:center;gap:8px;padding:8px 14px;border-radius:40px;border:0;cursor:pointer;background:transparent;color:rgba(245,240,230,.88);
  font-family:var(--sa);font-size:10.5px;font-weight:500;letter-spacing:.16em;text-transform:uppercase;transition:all .25s}
.cam-btn .material-symbols-outlined{font-size:17px}
.cam-btn:hover{background:rgba(245,240,230,.12);color:#fff}
.cam-btn.bg-surface{background:rgba(245,240,230,.94);color:var(--ci)}
.cam-btn .hidden{display:none}
@media(min-width:768px){.cam-btn .md\:inline{display:inline}}
.hero-cta{display:none;align-items:center;gap:10px;padding:11px 22px;border-radius:40px;white-space:nowrap;text-decoration:none;
  font-family:var(--sa);font-weight:500;font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--rl);
  border:1px solid rgba(190,179,165,.55);background:rgba(72,91,55,.35) url('/assets/img/TexturasBotones.webp') center/cover;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);transition:background-color .3s}
.hero-cta:hover{background-color:rgba(72,91,55,.6)}
.hero-cta .material-symbols-outlined{font-size:17px}
@media(min-width:1280px){.hero-cta{display:inline-flex}}

/* Panel del configurador: cristal oscuro, como el panel de la hero del deck v3 */
#hero-configurator aside{position:relative;z-index:40;display:flex;flex-direction:column;background:var(--ob);color:var(--rl)}
.cfg-cab{padding:26px var(--cpd) 20px;border-bottom:1px solid rgba(245,240,230,.14)}
.cfg-cab .kicker{color:var(--sc)} .cfg-cab .kicker::before{background:var(--sc)}
.cfg-sub{font-family:var(--sa);font-size:13.5px;line-height:1.6;color:rgba(245,240,230,.75);margin:10px 0 0}
/* Superficie + distribución en dos columnas y el precio en fila propia: los tres datos que
   decide el comprador, en cifra grande (peso 300, nunca negrita) — 24-sep-2026, owner. */
.cfg-datos{display:grid;grid-template-columns:1fr 1fr;margin-top:18px;border-top:1px solid rgba(245,240,230,.14);border-bottom:1px solid rgba(245,240,230,.14)}
.cfg-datos > div{display:flex;flex-direction:column;gap:6px;padding:14px 14px 14px 0;min-width:0}
.cfg-datos > div + div{border-left:1px solid rgba(245,240,230,.14);padding-left:16px}
.cfg-datos .dt-lb{font-family:var(--sa);font-size:9.5px;font-weight:500;letter-spacing:.2em;text-transform:uppercase;color:var(--ss)}
.cfg-datos .dt-v{font-family:var(--sa);font-weight:300;font-size:26px;line-height:1.05;letter-spacing:-.01em;color:var(--rl);white-space:nowrap}
.cfg-datos .dt-v small{font-size:.55em;letter-spacing:.02em;margin-left:3px;opacity:.8}
.cfg-datos .dt-sub{font-family:var(--sa);font-size:11.5px;line-height:1.35;color:rgba(245,240,230,.6)}
.cfg-datos .desde{grid-column:1 / -1;flex-direction:row;align-items:baseline;justify-content:space-between;gap:12px;border-left:0!important;padding-left:0!important;padding-right:0;border-top:1px solid rgba(245,240,230,.14)}
.cfg-datos .desde .dt-v{font-size:34px;color:#C3D9A6}
#lw-paso-lb{display:block;margin-top:14px;font-family:var(--sa);font-size:10px;font-weight:500;letter-spacing:.22em;text-transform:uppercase;color:rgba(245,240,230,.6)!important;text-align:center}
.res{flex:1;min-height:0;overflow-y:auto;padding:22px var(--cpd);display:flex;flex-direction:column;gap:20px;scrollbar-width:thin;scrollbar-color:rgba(245,240,230,.25) transparent}
.cfg__step{display:flex;flex-direction:column;gap:10px}
.cfg__step[hidden]{display:none}
.lista{display:flex;flex-direction:column;gap:10px}
.lista[hidden]{display:none}
.paso-tit{font-family:var(--sa);font-weight:500;font-size:15px;letter-spacing:.12em;text-transform:uppercase;color:var(--rl)}
.paso-txt{font-family:var(--sa);font-size:13px;line-height:1.55;color:rgba(245,240,230,.68);margin:4px 0 4px}
.op,.vcard{cursor:pointer;display:flex;align-items:center;gap:12px;padding:13px 15px;border-radius:12px;border:1px solid rgba(245,240,230,.16);background:rgba(245,240,230,.04);transition:border-color .15s,background .15s}
.vcard{justify-content:space-between}
.op:hover,.vcard:hover{border-color:rgba(245,240,230,.4)}
.op:has(input:checked),.vcard:has(input:checked){background:rgba(143,155,122,.16);border-color:var(--sc)}
.op input,.vcard input{width:16px;height:16px;accent-color:#8F9B7A;flex:none;margin:2px 0 0}
.op>span:nth-child(2){display:flex;flex-direction:column;flex:1;min-width:0}
.op__nb{font-family:var(--sa);font-size:14px;font-weight:500;letter-spacing:.03em;color:var(--rl)}
.op__sp{font-family:var(--sa);font-size:11.5px;color:rgba(245,240,230,.62);margin-top:2px}
.op__pr{text-align:right;flex:none}
.op__pr b{font-family:var(--sa);font-size:13px;font-weight:500;color:#C3D9A6;white-space:nowrap;display:block}
.op__pr i{font-style:normal;font-size:10px;color:rgba(245,240,230,.55);white-space:nowrap}
.op__th{width:44px;height:36px;border-radius:8px;object-fit:cover;background:#222;flex:none}
.vcard-izq{display:flex;align-items:flex-start;gap:12px}
.vcard-izq > div{display:flex;flex-direction:column}
.vcard-nb{font-family:var(--sa);font-size:14px;font-weight:500;color:var(--rl)}
.vcard-sp{font-family:var(--sa);font-size:11.5px;color:rgba(245,240,230,.62)}
.vcard-pr{font-family:var(--sa);font-size:12px;font-weight:500;color:#C3D9A6;white-space:nowrap}
#lw-parcela-nota{font-family:var(--sa);font-size:11.5px;color:rgba(245,240,230,.62);margin:2px 0 0}
.cfg-pie{padding:18px var(--cpd) 22px;border-top:1px solid rgba(245,240,230,.14);display:flex;flex-direction:column;gap:14px}
.resumen{padding-bottom:12px;border-bottom:1px solid rgba(245,240,230,.12);display:flex;flex-direction:column;gap:6px;font-family:var(--sa);font-size:12px;color:rgba(245,240,230,.65)}
.resumen .fila{display:flex;justify-content:space-between;gap:12px}
.resumen .fila span:first-child{color:var(--rl);font-weight:500}
.resumen .fila span:last-child{color:#C3D9A6}
.total-fila{display:flex;align-items:center;justify-content:space-between;gap:12px}
.total-fila > div:first-child{display:flex;flex-direction:column}
.total-lb{font-family:var(--sa);font-size:9.5px;font-weight:500;letter-spacing:.22em;text-transform:uppercase;color:var(--ss)}
#lw-total{font-family:var(--sa);font-weight:200;font-size:30px;line-height:1.1;color:var(--rl)}
#lw-total-alt{font-family:var(--sa);font-size:11px;color:rgba(245,240,230,.55)}
.nav-pasos{display:flex;align-items:center;gap:8px}
#lw-atras{width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;background:transparent;border:1px solid rgba(245,240,230,.4);color:var(--rl)}
#lw-atras[hidden]{display:none}
#lw-atras:disabled{opacity:.4;pointer-events:none}
#lw-siguiente{display:inline-flex;align-items:center;gap:4px;padding:10px 18px;border-radius:40px;cursor:pointer;border:1px solid var(--rl);background:var(--rl);color:var(--ci);
  font-family:var(--sa);font-size:11px;font-weight:500;letter-spacing:.14em;text-transform:uppercase;transition:background .2s}
#lw-siguiente:hover{background:#fff}
#lw-siguiente .material-symbols-outlined,#lw-atras .material-symbols-outlined{font-size:17px}
#lw-puntos{display:flex;align-items:center;justify-content:center;gap:6px}
.punto{width:6px;height:6px;border-radius:50%;background:rgba(245,240,230,.3)}
.punto.is-on{background:var(--rl);width:18px;border-radius:999px}
#lw-wa-cta{display:flex;align-items:center;justify-content:center;gap:10px;padding:14px 20px;border-radius:40px;background:#25D366;color:#0b3d25;text-decoration:none;
  font-family:var(--sa);font-size:11.5px;font-weight:500;letter-spacing:.14em;text-transform:uppercase;transition:filter .2s}
#lw-wa-cta:hover{filter:brightness(.95)}
#lw-wa-cta .material-symbols-outlined{font-size:18px}
@media(min-width:1024px){
  #hero-configurator{height:100svh;min-height:640px;overflow:hidden}
  #hero-visual{position:absolute;inset:0;height:auto;min-height:0}
  #hero-configurator aside{position:absolute;top:clamp(76px,10vh,92px);right:var(--cpd);bottom:clamp(22px,4vh,40px);width:var(--pw);
    border-radius:16px;overflow:hidden;background:rgba(12,14,10,.66);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px);
    border:1px solid rgba(190,179,165,.3);box-shadow:0 30px 70px -30px rgba(0,0,0,.7)}
  .cfg-cab,.res,.cfg-pie{padding-left:26px;padding-right:26px}
  .hero-texto,.hero-pie{right:calc(var(--pw) + var(--cpd) + 36px)}
}
@media(min-width:1280px){:root{--pw:460px}}

/* ── 01 · DISTRIBUCION ── */
.lay-grid{display:grid;grid-template-columns:1fr;gap:clamp(20px,2.4vw,36px);margin-top:clamp(2.5rem,5vh,3.5rem);align-items:start}
@media(min-width:1024px){.lay-grid{grid-template-columns:7fr 5fr}}
.lay-foto{padding:14px}
.lay-foto .caja{position:relative;aspect-ratio:1/1;border-radius:10px;overflow:hidden;background:var(--va)}
.lay-foto img{width:100%;height:100%;object-fit:cover;transition:transform 1.2s var(--ease)}
.lay-foto:hover img{transform:scale(1.04)}
.area{position:absolute;top:18px;right:18px;display:flex;flex-direction:column;align-items:flex-end;gap:2px;padding:10px 16px;border-radius:12px;
  background:rgba(12,14,10,.72);border:1px solid rgba(190,179,165,.35);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px)}
.area span:nth-child(1){font-family:var(--sa);font-size:9.5px;font-weight:500;letter-spacing:.22em;text-transform:uppercase;color:var(--ss)}
.area span:nth-child(2){font-family:var(--sa);font-weight:200;font-size:26px;line-height:1.1;color:var(--rl)}
.area span:nth-child(3){font-family:var(--sa);font-size:11px;color:#C3D9A6}
.lay-der{display:flex;flex-direction:column;gap:18px}
.epc{padding:28px 28px 26px}
.epc .kicker{color:var(--sc);font-size:11px}
.epc .kicker .material-symbols-outlined{font-size:17px}
.epc .kicker::before{display:none}
.epc h3{font-family:var(--sa);font-weight:500;font-size:clamp(20px,1vw + 12px,26px);letter-spacing:.08em;text-transform:uppercase;margin:12px 0 10px;color:var(--rl)}
.epc p{font-family:var(--sa);font-size:14px;line-height:1.7;color:rgba(245,240,230,.75);margin:0}
.specs{padding:8px 24px}
.spec{display:flex;align-items:center;gap:14px;padding:14px 0;font-family:var(--sa);font-size:14px;color:var(--rl)}
.spec + .spec{border-top:1px solid rgba(245,240,230,.1)}
.spec .material-symbols-outlined{font-size:20px;color:var(--sc);flex:none}
.lay-der .btn{width:100%;box-sizing:border-box}
.lay-der .btn .material-symbols-outlined{font-size:18px}

/* ── 02 · CUBIERTAS: tarjetas altas a foto completa con marco interior (como las villas) ── */
.techos{display:grid;grid-template-columns:1fr;gap:clamp(18px,2.2vw,32px);margin-top:clamp(2.5rem,5vh,3.5rem)}
@media(min-width:768px){.techos{grid-template-columns:1fr 1fr}}
.tcard{position:relative;display:block;min-height:clamp(460px,62vh,600px);border-radius:14px;overflow:hidden;background:var(--va);color:var(--rl);box-shadow:0 30px 60px -30px rgba(20,26,17,.55);transition:transform .5s var(--ease)}
.tcard:hover{transform:translateY(-6px)}
.tcard > img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;transition:transform 1.2s var(--ease)}
.tcard:hover > img{transform:scale(1.05)}
.tcard::before{content:"";position:absolute;inset:0;z-index:1;background:linear-gradient(to top,rgba(14,17,12,.94) 0%,rgba(14,17,12,.6) 38%,rgba(14,17,12,0) 64%)}
.tcard::after{content:"";position:absolute;inset:14px;z-index:2;border:1px solid rgba(245,240,230,.38);border-radius:8px;pointer-events:none}
.tcard-cuerpo{position:absolute;z-index:3;left:32px;right:32px;bottom:32px;display:flex;flex-direction:column;align-items:center;text-align:center;gap:12px}
.tcard-nb{font-family:var(--sa);font-weight:500;font-size:clamp(22px,1.2vw + 12px,30px);letter-spacing:.06em;text-transform:uppercase;line-height:1.05}
.tcard-pr{font-family:var(--sa);font-weight:500;font-size:12px;letter-spacing:.24em;text-transform:uppercase;color:var(--ss);padding:6px 16px;border-radius:30px;border:1px solid rgba(190,179,165,.5)}
.tcard-cuerpo p{font-family:var(--sa);font-size:13.5px;line-height:1.65;color:rgba(245,240,230,.82);margin:0;max-width:46ch}
.tcard-cuerpo p.y27{font-size:11.5px;color:rgba(245,240,230,.6)}

/* ── 03 · INVERSION + FAQ: foto a sangre con tarjetas de cristal oscuro (forecast del deck) ── */
.sec-foto{color:var(--rl);background:var(--ob) url('<?= lw_e($heroDay ?: '/assets/img/lugar/costa.webp') ?>') center/cover}
.sec-foto::before{content:"";position:absolute;inset:0;pointer-events:none;background:linear-gradient(to bottom,rgba(10,12,9,.7),rgba(10,12,9,.82) 45%,rgba(14,20,11,.95))}
.sec-foto .kicker{color:var(--ss)} .sec-foto .titulo{color:var(--rl)}
.fin-grid{display:grid;grid-template-columns:1fr;gap:clamp(18px,2vw,28px);margin-top:clamp(2.5rem,6vh,4rem);align-items:start}
@media(min-width:1024px){.fin-grid{grid-template-columns:1fr 1fr}}
.cristal{position:relative;padding:28px 28px 24px;border-radius:16px;background:rgba(12,14,10,.78);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);
  border:1px solid rgba(190,179,165,.3);box-shadow:0 30px 60px -30px rgba(0,0,0,.7)}
.cristal .kicker{font-size:10.5px;color:var(--ss)}
.cristal h3{font-family:var(--sa);font-weight:500;font-size:clamp(20px,1vw + 12px,26px);letter-spacing:.08em;text-transform:uppercase;margin:10px 0 8px;color:var(--rl)}
.cristal .nota{font-family:var(--sa);font-size:13px;line-height:1.65;color:rgba(245,240,230,.78);margin:0 0 16px}
.esc{padding:14px 0;border-top:1px solid rgba(245,240,230,.16)}
.esc-top{display:flex;align-items:baseline;justify-content:space-between;gap:10px}
.esc-top > span{font-family:var(--sa);font-size:10px;letter-spacing:.22em;text-transform:uppercase;color:var(--ss)}
.esc-top b{font-family:var(--sa);font-weight:200;font-size:clamp(22px,1.1vw + 12px,28px);color:var(--rl);white-space:nowrap}
.esc p{font-family:var(--sa);font-size:12px;line-height:1.6;color:rgba(245,240,230,.8);margin:6px 0 0}
.cristal .base{font-family:var(--sa);font-size:12px;line-height:1.65;color:rgba(245,240,230,.72);margin:6px 0 0;padding-top:14px;border-top:1px solid rgba(245,240,230,.16)}
.faq-item{border:0;border-top:1px solid rgba(245,240,230,.18);border-radius:0;background:transparent}
.faq-item:last-child{border-bottom:1px solid rgba(245,240,230,.18)}
.faq-item summary{list-style:none;cursor:pointer;padding:16px 0;display:flex;align-items:center;justify-content:space-between;gap:16px;
  font-family:var(--sa);font-size:13px;font-weight:500;letter-spacing:.03em;text-transform:uppercase;color:var(--rl);line-height:1.4}
.faq-item summary::-webkit-details-marker{display:none}
.faq-item summary .mi{font-size:0!important;width:14px;height:14px;position:relative;flex:none}
.faq-item summary .mi::before,.faq-item summary .mi::after{content:"";position:absolute;left:0;right:0;top:50%;height:1px;background:rgba(245,240,230,.8)}
.faq-item summary .mi::after{transform:rotate(90deg);transition:transform .3s var(--ease)}
.faq-item[open] summary .mi::after{transform:rotate(0)}
.faq-item__body{padding:0 0 18px;font-family:var(--sa);font-size:14px;line-height:1.75;color:rgba(245,240,230,.75)}
.faq-item__body p{margin:0}
.faq-lista{margin-top:14px}

/* ── 04 · COLECCION: tarjetas altas de villa (como Villa Typologies del deck) ── */
.col-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr));gap:clamp(18px,2vw,28px);margin-top:clamp(2.5rem,5vh,3.5rem)}
.villa{position:relative;display:block;aspect-ratio:3/4.3;border-radius:14px;overflow:hidden;background:var(--va);color:var(--rl);text-decoration:none;box-shadow:0 30px 60px -30px rgba(20,26,17,.55);transition:transform .5s var(--ease)}
.villa:hover{transform:translateY(-6px)}
.villa > img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;transition:transform 1.2s var(--ease)}
.villa:hover > img{transform:scale(1.05)}
.villa::before{content:"";position:absolute;inset:0;z-index:1;background:linear-gradient(to top,rgba(14,17,12,.92) 0%,rgba(14,17,12,.5) 36%,rgba(14,17,12,0) 60%)}
.villa::after{content:"";position:absolute;inset:12px;z-index:2;border:1px solid rgba(245,240,230,.38);border-radius:8px;pointer-events:none}
.villa-cuerpo{position:absolute;z-index:3;left:24px;right:24px;bottom:24px;display:flex;flex-direction:column;align-items:center;text-align:center;gap:10px}
.villa-nombre{font-family:var(--sa);font-weight:500;font-size:clamp(20px,1vw + 12px,26px);letter-spacing:.06em;text-transform:uppercase;line-height:1}
.villa-precio{font-family:var(--sa);font-weight:500;font-size:11px;letter-spacing:.24em;text-transform:uppercase;color:var(--ss)}
.villa-sp{font-family:var(--sa);font-size:11.5px;line-height:1.5;color:rgba(245,240,230,.78)}
.villa-btn{width:100%;display:flex;align-items:center;justify-content:center;gap:8px;padding:11px 16px;border-radius:40px;box-sizing:border-box;
  border:1px solid rgba(245,240,230,.55);font-family:var(--sa);font-size:10.5px;font-weight:500;letter-spacing:.18em;text-transform:uppercase;transition:background .3s,color .3s}
.villa-btn .material-symbols-outlined{font-size:15px}
.villa:hover .villa-btn{background:var(--rl);color:var(--ci)}
.col-volver{display:flex;justify-content:center;margin-top:clamp(2rem,4vh,3rem)}
.col-volver .material-symbols-outlined{font-size:17px}
</style>

</head>
<body>

<!-- ═══ HEADER — #topbar de la home: transparente sobre la foto, solida al bajar ═══════ -->
<header id="lw-topbar">
<a id="logo" href="/" aria-label="Lawang Tropical Properties">
<img class="lg-w" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
<img class="lg-d" src="/assets/img/lawang-logo-v3-dark.webp" alt="" aria-hidden="true">
</a>
<nav aria-label="Sections">
<a class="nav-link" href="#section-layout"><?= lw_i18n('Distribución', 'Layout') ?></a>
<a class="nav-link" href="#section-cubiertas"><?= lw_i18n('Cubiertas', 'Roofs') ?></a>
<a class="nav-link" href="#section-financial"><?= lw_i18n('Rentabilidad', 'Returns & FAQ') ?></a>
<a class="nav-link" href="#section-collection"><?= lw_i18n('Colección', 'Collection') ?></a>
</nav>
<div id="acciones">
<div class="tb-precio">
<span><?= lw_i18n('Desde', 'From') ?></span>
<span<?= $precioValor !== null ? ' data-eur-fijo="' . (int) $precioValor . '"' : '' ?>><?= lw_e($precioTxt) ?></span>
</div>
<a class="tb-wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
<span class="wa"><span class="material-symbols-outlined">support_agent</span></span>
<span><?= lw_i18n('Escríbenos', 'WhatsApp') ?></span>
</a>
<!-- nav__cta: hook de i18n-landing.js (monta aqui el selector EN/ES/ID), junto a la divisa. -->
<div class="lw-meta nav__cta">
<div class="lw-cur" id="lw-div-sel" data-no-i18n></div>
</div>
</div>
</header>

<!-- ═══ HERO: foto a sangre + configurador en panel de cristal oscuro ═════════════════ -->
<section id="hero-configurator">
<div id="hero-visual">
<?php if ($sinRender): ?>
<div class="sin-render">
  <span class="material-symbols-outlined" style="font-size:52px;color:#8F9B7A">architecture</span>
  <p>Renders in progress</p>
  <p>Reserve before they exist — the roof price is confirmed by the developer today.</p>
</div>
<?php else: ?>
<div id="viewport-canvas">
<div class="view-layer opacity-100 scale-100" id="layer-day" style="background-image:url('<?= lw_e($heroDay) ?>')"><div></div></div>
<div class="view-layer opacity-0 scale-105 pointer-events-none" id="layer-roof" style="background-image:url('<?= lw_e($heroTechoAlt) ?>')"><div></div></div>
<div class="view-layer opacity-0 scale-105 pointer-events-none" id="layer-interior" style="background-image:url('<?= lw_e($heroInterior) ?>')"><div></div></div>
<?php if ($heroKitchen): ?>
<div class="view-layer opacity-0 scale-105 pointer-events-none" id="layer-kitchen" style="background-image:url('<?= lw_e($heroKitchen) ?>')"><div></div></div>
<?php endif; ?>
<?php if ($heroToilet): ?>
<div class="view-layer opacity-0 scale-105 pointer-events-none" id="layer-toilet" style="background-image:url('<?= lw_e($heroToilet) ?>')"><div></div></div>
<?php endif; ?>
<?php if ($heroAerea): ?>
<div class="view-layer opacity-0 scale-105 pointer-events-none" id="layer-aerea" style="background-image:url('<?= lw_e($heroAerea) ?>')"><div></div></div>
<?php endif; ?>

<!-- Hotspots: mismas posiciones y textos que v1, calibrados sobre la foto de dia. -->
<div class="hotspot" id="hotspot-interior" style="top:48%;left:48%" onclick="lwSetView('interior')">
<span class="hs-pulso"></span><span class="hs-punto"><span class="material-symbols-outlined">weekend</span></span>
<div class="hs-tip"><span><?= lw_i18n('Salón', 'Living room') ?></span><span>AC &amp; hot water included</span></div>
</div>
<div class="hotspot" id="hotspot-terraza" style="top:79%;left:63%" onclick="lwSetView('day')">
<span class="hs-pulso"></span><span class="hs-punto"><span class="material-symbols-outlined">deck</span></span>
<div class="hs-tip"><span><?= lw_i18n('Terraza', 'Terrace') ?></span><span>Exterior terrace, included</span></div>
</div>
<?php if ($heroKitchen): ?>
<div class="hotspot" id="hotspot-kitchen" style="top:50%;left:58%" onclick="lwSetView('kitchen')">
<span class="hs-pulso"></span><span class="hs-punto"><span class="material-symbols-outlined">kitchen</span></span>
<div class="hs-tip"><span><?= lw_i18n('Cocina', 'Kitchen') ?></span><span>Kitchenette, see photo</span></div>
</div>
<?php endif; ?>
<?php if ($heroToilet): ?>
<div class="hotspot" id="hotspot-toilet" style="top:58%;left:37%" onclick="lwSetView('toilet')">
<span class="hs-pulso"></span><span class="hs-punto"><span class="material-symbols-outlined">bathroom</span></span>
<div class="hs-tip"><span><?= lw_i18n('Baño', 'Bathroom') ?></span><span>En-suite bathroom, see photo</span></div>
</div>
<?php endif; ?>
</div>
<?php endif; ?>

<!-- Nombre de la villa sobre la foto (patron hero de la home), en The Seasons. -->
<div class="hero-texto">
<p class="kicker"><?= lw_i18n('Costa oeste de Bali', "Bali's west coast") ?></p>
<h1><?= lw_e($villa) ?></h1>
<p class="hero-sub"><?= lw_e($m['sub_en'] ?? '') ?></p>
</div>

<?php if (!$sinRender): ?>
<!-- Dock de camara: las mismas vistas reales, en pildora de cristal como el menu de la home -->
<div class="hero-pie">
<div class="dock">
<button class="cam-btn bg-surface" id="cam-day" onclick="lwSetView('day')">
<span class="material-symbols-outlined">wb_sunny</span>
<span class="hidden md:inline"><?= lw_i18n('Día', 'Day') ?></span>
</button>
<button class="cam-btn" id="cam-roof" onclick="lwSetView('roof')">
<span class="material-symbols-outlined">roofing</span>
<span class="hidden md:inline"><?= lw_i18n('Techo firma', 'Signature roof') ?></span>
</button>
<button class="cam-btn" id="cam-interior" onclick="lwSetView('interior')">
<span class="material-symbols-outlined">weekend</span>
<span class="hidden md:inline"><?= lw_i18n('Salón', 'Living room') ?></span>
</button>
<?php if ($heroAerea): ?>
<button class="cam-btn" id="cam-aerea" onclick="lwSetView('aerea')">
<span class="material-symbols-outlined">flight</span>
<span class="hidden md:inline"><?= lw_i18n('Aérea', 'Aerial') ?></span>
</button>
<?php endif; ?>
</div>
<a class="hero-cta" href="#section-layout">
<span><?= lw_i18n('Explorar proyecto', 'Explore project') ?></span>
<span class="material-symbols-outlined">arrow_downward</span>
</a>
</div>
<?php endif; ?>
</div>

<!-- ═══ CONFIGURADOR villa → techo → isla → parcela → extras. Motor real
     (assets/au-landing-cfg.js), mismos ids/names/data-paso que v1: solo cambia la piel. ═══ -->
<aside>
<div class="cfg-cab">
<p class="kicker">New build · Turnkey</p>
<div class="cfg-datos">
<div><span class="dt-lb"><?= lw_i18n('Superficie', 'Built area') ?></span><span class="dt-v"><?= (int) $m['villa_m2'] + (int) $m['terraza_m2'] ?><small>m²</small></span><span class="dt-sub"><?= (int) $m['villa_m2'] ?> m² interior + <?= (int) $m['terraza_m2'] ?> m² terrace</span></div>
<div><span class="dt-lb"><?= lw_i18n('Distribución', 'Layout') ?></span><span class="dt-v"><?= (int) $dorm ?><small>bed</small> · <?= (int) $banos ?><small>bath</small></span><span class="dt-sub"><?= lw_e($dormTxt) ?>, <?= (int) $banos ?> <?= (int) $banos === 1 ? 'bathroom' : 'bathrooms' ?></span></div>
<div class="desde"><span class="dt-lb"><?= lw_i18n('Desde', 'From') ?></span><span class="dt-v"<?= $precioValor !== null ? ' data-eur-fijo="' . (int) $precioValor . '"' : '' ?>><?= lw_e($precioTxt) ?></span></div>
</div>
<span id="lw-paso-lb">Step 1 of 4</span>
</div>

<div class="res">
<div class="cfg__step" data-paso="1" hidden>
<div>
<span class="paso-tit"><?= lw_i18n('¿Qué villa?', 'Which villa?') ?></span>
<p class="paso-txt">Same construction system across the range — only the size changes the price.</p>
</div>
<?php foreach ($CAT as $cmId => $v): ?>
<label class="vcard">
<div class="vcard-izq">
<input type="radio" name="lw-villa" value="<?= lw_e($cmId) ?>"<?= $cmId === $m['id'] ? ' checked' : '' ?>>
<?php if ($v['thumb']): ?><img class="op__th" src="<?= lw_e($v['thumb']) ?>" alt="" loading="lazy"><?php endif; ?>
<div>
<span class="vcard-nb"><?= lw_e($v['villa']) ?></span>
<span class="vcard-sp"><?= lw_e($v['specs']) ?></span>
</div>
</div>
<span class="vcard-pr"><?= lw_e(lw_precio_fmt($v['desde_eur'])) ?></span>
</label>
<?php endforeach; ?>
</div>

<div class="cfg__step" data-paso="2" hidden>
<div>
<span class="paso-tit"><?= lw_i18n('¿Qué techo?', 'Which roof?') ?></span>
<p class="paso-txt">Two complete villa prices, not an add-on — the roof you choose is the price of the villa.</p>
</div>
<div id="lw-techos" class="lista"></div>
</div>

<div class="cfg__step" data-paso="3" hidden>
<div>
<span class="paso-tit"><?= lw_i18n('¿Qué isla?', 'Which island?') ?></span>
<p class="paso-txt">The plot is priced separately, sized on the call.</p>
</div>
<label class="op"><input type="radio" name="lw-isla" value="bali" checked><span><span class="op__nb">Bali</span><span class="op__sp">Cliff, ricefield, riverfront or beachfront</span></span></label>
<label class="op"><input type="radio" name="lw-isla" value="sumba"><span><span class="op__nb">Sumba</span><span class="op__sp">Beachfront only</span></span></label>
</div>

<div class="cfg__step" data-paso="4" hidden>
<div>
<span class="paso-tit"><?= lw_i18n('Ubicación de la parcela', 'Plot location') ?></span>
</div>
<div id="lw-zona-wrap" class="lista">
<label class="op"><input type="radio" name="lw-zona" value="otras" checked><span><span class="op__nb">Cliff · Ricefield · Riverfront</span></span><span class="op__pr"><b>€<?= lw_e((string) lw_parcela_tarifa_m2('otras')) ?>/m²</b></span></label>
<label class="op"><input type="radio" name="lw-zona" value="beachfront"><span><span class="op__nb">Beachfront</span></span><span class="op__pr"><b>€<?= lw_e((string) lw_parcela_tarifa_m2('beachfront')) ?>/m²</b></span></label>
</div>
<div id="lw-zona-sumba-wrap" class="lista" hidden>
<div class="op" style="cursor:default"><span style="display:flex;flex-direction:column;flex:1;min-width:0"><span class="op__nb">Beachfront</span><span class="op__sp">Inside Sumba Hills — the only plot on offer today</span></span><span class="op__pr"><b>€<?= lw_e((string) lw_parcela_tarifa_m2('sumba')) ?>/m²</b></span></div>
</div>
<p id="lw-parcela-nota"></p>
</div>

<div class="cfg__step" data-paso="5" hidden>
<div>
<span class="paso-tit"><?= lw_i18n('¿Algún extra?', 'Any extras?') ?></span>
<p class="paso-txt">Optional — none of them is needed to move in.</p>
</div>
<div id="lw-extras" class="lista"></div>
</div>
</div>

<div class="cfg-pie">
<div class="resumen">
<div class="fila"><span id="lw-r-villa"></span><span id="lw-r-villa-pr"></span></div>
<div id="lw-r-villa-sub"></div>
<div class="fila"><span id="lw-r-extras"></span><span id="lw-r-extras-pr"></span></div>
<div id="lw-r-extras-sub"></div>
</div>
<div class="total-fila">
<div>
<span class="total-lb"><?= lw_i18n('Total configurado', 'Configured total') ?></span>
<span id="lw-total"></span>
<span id="lw-total-alt"></span>
</div>
<div class="nav-pasos">
<button id="lw-atras" hidden><span class="material-symbols-outlined">chevron_left</span></button>
<button id="lw-siguiente"><span>Next </span><span class="material-symbols-outlined">chevron_right</span></button>
</div>
</div>
<div id="lw-puntos"></div>
<a id="lw-wa-cta" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
<span class="material-symbols-outlined">chat</span>
<span><?= lw_i18n('Escribir por WhatsApp', 'Message us on WhatsApp') ?></span>
</a>
</div>
</aside>
</section>

<!-- ═══ 01 · DISTRIBUCION — lino + tarjetas oscuras con filete (como el resto de modulos) ═══ -->
<section class="sec sec-lino" id="section-layout">
<div class="wrap">
<div class="cab center reveal">
<p class="kicker">01 · <?= lw_i18n('Distribución', 'Layout') ?></p>
<h2 class="titulo"><?= lw_i18n('Distribución bioclimática', 'Bioclimatic layout') ?></h2>
</div>
<div class="lay-grid">
<div class="oscura marco lay-foto">
<div class="caja">
<?php if ($layoutImg): ?>
<img alt="<?= lw_e($villa) ?> floor plan" src="<?= lw_e($layoutImg) ?>" loading="lazy">
<?php endif; ?>
<div class="area">
<span><?= lw_i18n('Superficie total', 'Total area') ?></span>
<span><?= (int) $m['villa_m2'] + (int) $m['terraza_m2'] ?> m²</span>
<span><?= (int) $m['villa_m2'] ?> m² interior + <?= (int) $m['terraza_m2'] ?> m² deck</span>
</div>
</div>
</div>
<div class="lay-der">
<div class="oscura marco epc">
<p class="kicker"><span class="material-symbols-outlined">eco</span><span><?= lw_i18n('Diseño pasivo', 'Passive design') ?></span></p>
<h3>Turnkey EPC, fixed price</h3>
<p>Every project runs on a guaranteed fixed-price written EPC contract — Indonesian VAT (PPN) included, closing costs quoted separately and detailed before you sign.</p>
</div>
<?php
// Icono segun LO QUE DICE la linea, no segun su posicion (23-sep-2026, igual que v1).
$specIcons = [
    '/pool|piscina/i'                                   => 'pool',
    '/roof|techo|cubierta|atap/i'                       => 'roofing',
    '/terrace|terraza|deck|teras/i'                     => 'deck',
    '/air.?con|aire acond|hot water|agua caliente|AC\b/i' => 'ac_unit',
    '/electric|el[eé]ctric|PLN|\d+\s*W\b|listrik/i'      => 'bolt',
    '/structure|estructura|architect|arquitect|install|instalac/i' => 'architecture',
    '/main building|edificio|building|bangunan/i'       => 'home',
];
$incluido = (array) ($m['alcance']['incluido'] ?? []);
$filas = [];
foreach ($incluido as $it) {
    $txt = is_array($it) ? ($it['en'] ?? $it['es'] ?? '') : (string) $it;
    if ($txt === '') continue;
    $ic = 'check_circle';
    foreach ($specIcons as $re => $icono) { if (preg_match($re, $txt)) { $ic = $icono; break; } }
    $filas[] = [$ic, $txt];
}
?>
<?php if ($filas): ?>
<div class="oscura specs">
<?php foreach ($filas as $f): ?>
<div class="spec"><span class="material-symbols-outlined"><?= lw_e($f[0]) ?></span><span><?= lw_e($f[1]) ?></span></div>
<?php endforeach; ?>
</div>
<?php endif; ?>
<a class="btn btn-linea" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
<span class="material-symbols-outlined">description</span>
<span><?= lw_i18n('Solicitar el dossier completo', 'Request the full dossier') ?></span>
</a>
</div>
</div>
</div>
</section>

<?php if ($techosComp): ?>
<!-- ═══ 02 · CUBIERTAS — tarjetas altas a foto completa con marco interior ════════════ -->
<section class="sec sec-lino" id="section-cubiertas">
<div class="wrap">
<div class="cab center reveal">
<p class="kicker"><?= lw_i18n('Materialidad', 'Craft & materiality') ?></p>
<h2 class="titulo">Roof finishes</h2>
<p class="entrada">Two complete villa prices, not an add-on — the roof you choose is the price of the villa.</p>
</div>
<div class="techos">
<div class="tcard reveal">
<?php if ($heroDay): ?><img alt="<?= lw_e($techosComp['sirap']['nombre']) ?>" src="<?= lw_e($heroDay) ?>" loading="lazy"><?php endif; ?>
<div class="tcard-cuerpo">
<span class="tcard-nb"><?= lw_e($techosComp['sirap']['nombre']) ?></span>
<span class="tcard-pr"><?= lw_e(lw_precio_fmt($techosComp['sirap']['now'] ?? null)) ?></span>
<p><?= lw_e($techosComp['sirap']['desc'] ?? '') ?></p>
<?php if ($antes2027 && !empty($techosComp['sirap']['y2027'])): ?>
<p class="y27">2026 price shown. From 2027: <?= lw_e(lw_precio_fmt($techosComp['sirap']['y2027'])) ?>.</p>
<?php endif; ?>
</div>
</div>
<div class="tcard reveal">
<?php if ($heroTechoAlt): ?><img alt="<?= lw_e($techosComp['bambu']['nombre']) ?>" src="<?= lw_e($heroTechoAlt) ?>" loading="lazy"><?php endif; ?>
<div class="tcard-cuerpo">
<span class="tcard-nb"><?= lw_e($techosComp['bambu']['nombre']) ?></span>
<span class="tcard-pr"><?= lw_e(lw_precio_fmt($techosComp['bambu']['now'] ?? null)) ?></span>
<p><?= lw_e($techosComp['bambu']['desc'] ?? '') ?></p>
<?php if ($antes2027 && !empty($techosComp['bambu']['y2027'])): ?>
<p class="y27">2026 price shown. From 2027: <?= lw_e(lw_precio_fmt($techosComp['bambu']['y2027'])) ?>.</p>
<?php endif; ?>
</div>
</div>
</div>
</div>
</section>
<?php endif; ?>

<!-- ═══ 03 · INVERSION + FAQ — foto a sangre y tarjetas de cristal (forecast del deck v3) ═══ -->
<section class="sec sec-foto" id="section-financial">
<div class="wrap">
<div class="cab center reveal">
<p class="kicker">03 · <?= lw_i18n('Inversión', 'Investment') ?></p>
</div>
<div class="fin-grid">
<?php if ($finCalc): ?>
<div class="cristal reveal">
<?php if (!empty($deckEj['mercado'])): ?>
<p class="kicker"><?= lw_i18n('Previsión de mercado', 'Market forecast') ?></p>
<h3><?= lw_e($deckEtiqueta) ?></h3>
<p class="nota">Rental forecast for a <?= $dorm ?>-bedroom villa in this area — not tied to a specific plot, and never a promise of yield. Source: internal market analysis (AirROI + NF Group Bali market report, Q3 2025), reviewed September 2026.</p>
<?php else: ?>
<p class="kicker"><?= lw_i18n('Ejemplo real', 'Real example') ?></p>
<h3><?= lw_e($deckEtiqueta) ?></h3>
<p class="nota">Economics of one specific plot at <?= lw_e($deckEtiqueta) ?> — figures vary by plot and are confirmed on the call, never a promise of yield.</p>
<?php endif; ?>
<?php foreach ($finCalc as $caso => $f): $label = $caso === 'average' ? 'Average' : 'Optimal'; ?>
<div class="esc">
<div class="esc-top"><span><?= lw_e($label) ?></span><b><?= lw_e(lw_precio_fmt($f['neto'])) ?>/yr net</b></div>
<p><?= lw_e(lw_precio_fmt($f['adr'])) ?> ADR × <?= (int) round($f['ocup'] * 100) ?>% occupancy — gross <?= lw_e(lw_precio_fmt($f['bruto'])) ?>, minus management + maintenance + tax (<?= lw_e(lw_precio_fmt($f['costes'])) ?>)</p>
</div>
<?php endforeach; ?>
<p class="base"><?= !empty($deckEj['mercado']) ? 'Investment base used in this forecast (company estimate for this scenario)' : 'Total investment used in this example' ?>: <?= lw_e(lw_precio_fmt($deckEj['inversion_base'])) ?>. Indicative only, not a quote or financial advice — actual rental income depends on the plot, the season and how the villa is managed.</p>
</div>
<?php endif; ?>
<div class="cristal reveal">
<p class="kicker"><?= lw_i18n('Dudas legales', 'Legal & practical') ?></p>
<h3><?= lw_i18n('Preguntas frecuentes', 'Frequently asked questions') ?></h3>
<div class="faq-lista">
<details class="faq-item">
<summary><span><?= lw_i18n('¿Qué compro exactamente y en qué régimen?', 'What exactly am I buying, and under what title?') ?></span><span class="material-symbols-outlined mi">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">La villa construida y el derecho sobre la parcela en la que se levanta. En Indonesia ese derecho no funciona como la propiedad española y no todas las parcelas están en el mismo régimen ni con el mismo plazo. Es la primera cosa que repasamos en la llamada, parcela por parcela y con el documento delante, antes de hablar de dinero.</p>
<p class="i-en">The built villa and the right over the plot it stands on. In Indonesia that right doesn't work like Spanish-style ownership, and not every plot sits under the same scheme or term. We review it plot by plot on the call, document in hand, before talking numbers.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Qué incluye el precio?', "What's included in the price?") ?></span><span class="material-symbols-outlined mi">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">La obra completa según el pliego del contratista, con el acabado de cubierta que elijas. El precio de la villa ya incluye el IVA indonesio (PPN). La parcela y los gastos de compraventa (impuesto de transmisión, notaría y licencias) se presupuestan aparte y se detallan por escrito antes de firmar nada.</p>
<p class="i-en">The full build with the roof finish you choose. The villa price already includes Indonesian VAT (PPN). The plot, and the closing costs on the purchase (transfer tax, notary and permits), are quoted separately and detailed in writing before you sign.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Puedo elegir dónde se construye?', 'Can I choose where it gets built?') ?></span><span class="material-symbols-outlined mi">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">Sí. El modelo es el mismo y se levanta sobre la parcela que elijas del catálogo. Cambian la vista, la orientación y el precio del terreno. No todas las parcelas admiten cualquier modelo: eso se concreta en la llamada.</p>
<p class="i-en">Yes. The model stays the same and is built on the plot you choose from the catalog. The view, orientation, and land price change. Not every plot takes every model — that's confirmed on the call.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿En qué moneda se firma?', 'What currency is the contract in?') ?></span><span class="material-symbols-outlined mi">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">El contrato se formaliza en rupias indonesias, como exige la ley indonesia para operaciones dentro del país. La equivalencia en euros se incluye a título informativo con el tipo de cambio de la fecha.</p>
<p class="i-en">The contract is executed in Indonesian rupiah, as required by Indonesian law for transactions inside the country. Other-currency equivalents are given for reference only, at the exchange rate on the date.</p>
</div>
</details>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Cómo se formaliza la compra?', 'How is the purchase formalized?') ?></span><span class="material-symbols-outlined mi">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">Primero un contrato de reserva sobre la parcela. Después el PPJB, que es el contrato de compraventa indonesio, y el contrato de construcción. Los tres son documentos propios del promotor y se revisan antes de firmar.</p>
<p class="i-en">First a reservation contract on the plot. Then the PPJB — the Indonesian sale contract — and the construction contract. All three are the developer's own documents and are reviewed before signing.</p>
</div>
</details>
<?php /* «Who builds it?» — texto revisado por Legal el 23-sep-2026, copiado tal cual de v1. */ ?>
<details class="faq-item">
<summary><span><?= lw_i18n('¿Quién construye?', 'Who builds it?') ?></span><span class="material-symbols-outlined mi">expand_more</span></summary>
<div class="faq-item__body">
<p class="i-es">Lawang construye tu villa. El contrato de construcción se firma con una sociedad de Lawang registrada en Indonesia; su denominación legal completa y sus datos registrales figuran en el contrato, que revisas antes de firmar. En la llamada te enseñamos obras entregadas y las que están en marcha ahora mismo.</p>
<p class="i-en">Lawang builds your villa. The construction contract is signed with a Lawang company registered in Indonesia; its full legal name and registration details are written in the contract, which you review before signing. On the call we show you delivered projects and the ones underway right now.</p>
</div>
</details>
</div>
</div>
</div>
</div>
</section>

<?php if ($otrosModelos): ?>
<!-- ═══ 04 · COLECCION — tarjetas altas de villa, enlazan a la v2 de cada una ═════════ -->
<section class="sec sec-lino" id="section-collection">
<div class="wrap">
<div class="cab center reveal">
<p class="kicker"><?= lw_i18n('Catálogo', 'Catalog') ?></p>
<h2 class="titulo">More from the collection</h2>
<p class="entrada">Same construction system and roof choice across the range — only the size changes the price.</p>
</div>
<div class="col-grid">
<?php foreach ($otrosModelos as $ocId => $ov): ?>
<a class="villa reveal" href="/<?= lw_e(lw_modelo_url_path($ocId)) ?>">
<?php if ($ov['thumb']): ?><img alt="<?= lw_e($ov['villa']) ?>" src="<?= lw_e($ov['thumb']) ?>" loading="lazy"><?php endif; ?>
<div class="villa-cuerpo">
<span class="villa-nombre"><?= lw_e($ov['villa']) ?></span>
<span class="villa-precio"><?= lw_e(lw_precio_fmt($ov['desde_eur'])) ?></span>
<span class="villa-sp"><?= lw_e($ov['specs']) ?></span>
<span class="villa-btn"><span><?= lw_i18n('Ver ficha', 'View model') ?></span><span class="material-symbols-outlined">arrow_outward</span></span>
</div>
</a>
<?php endforeach; ?>
</div>
<div class="col-volver">
<a class="btn btn-linea" href="#hero-configurator">
<span><?= lw_i18n('Volver al configurador', 'Back to configurator') ?></span>
<span class="material-symbols-outlined">north</span>
</a>
</div>
</div>
</section>
<?php endif; ?>

<!-- ═══ FOOTER ═══════════════════════════════════════════════════════════════════════ -->
<!-- Pie COMPARTIDO con /investor-deck (23-sep-2026, pedido del owner: comprimido y con el
     contacto bien destacado). Lo pinta /assets/lawang-pie.js: una sola fuente para los
     telefonos, la oficina y el aviso legal. Antes este pie ocupaba ~700px con columnas
     Collection/Information que repetian el menu y la seccion "More from the collection".
     data-wa: el enlace de siempre, con el nombre de esta villa en el mensaje.
     data-cookies: esta pagina SI carga consent.js; el manejador de #lw-cookies sigue
     mas abajo, en el script inline (este JS va antes, sin defer, a proposito). -->
<footer data-lw-pie data-cookies data-wa="<?= lw_e($WA_LINK) ?>"></footer>
<script src="/assets/lawang-pie.js?v=20260923153722"></script>

<!-- consent.js: gate del banner de cookies Y de window.lwTrack/Meta Pixel — SIN esto,
     track('ViewContent') de mas abajo comprueba `typeof window.lwTrack==='function'`,
     no lo encuentra, y no hace nada: la campana ES `es_ticket` apunta aqui y se quedaria
     sin pixel ni banner de consentimiento sin un solo error visible. Mismo fichero y
     mismo sello que /dali. -->
<script src="/assets/consent.js?v=20260908111654" defer></script>
<!-- Motor del configurador ANTES del script inline que lo invoca (window.lwAuCfgInit
     tiene que existir cuando se llama más abajo) — sin defer a propósito, o el inline
     que sigue se ejecutaría primero y fallaría "lwAuCfgInit is not a function". -->
<script src="/assets/au-landing-cfg.js?v=20260922203350"></script>
<script>
(function () {
  'use strict';
  // ── Crossfade + dock de cámara del hero. Kitchen/Toilet no tienen botón en el dock
  //    (se llega por su hotspot); si el modelo no tiene esa foto, el <div id="layer-...">
  //    ni existe (PHP lo omite) y getElementById da null — lwSetView ya lo contempla. ──
  var LAYERS = {day: 'layer-day', roof: 'layer-roof', interior: 'layer-interior',
                kitchen: 'layer-kitchen', toilet: 'layer-toilet', aerea: 'layer-aerea'};
  var BTNS   = {day: 'cam-day', roof: 'cam-roof', interior: 'cam-interior', aerea: 'cam-aerea'};
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
    // 22-sep-2026: los hotspots estan calibrados a ojo sobre la foto de DIA — en
    // cualquier otra vista (techo, cocina, bano, salon, aerea) no senalan nada real
    // de esa foto, asi que solo se ven cuando la vista activa es 'day'. El propio
    // hotspot que se acaba de pulsar (p.ej. Kitchen) se oculta con el resto: para
    // volver a verlos hay que volver a 'Day' desde el dock.
    document.querySelectorAll('.hotspot').forEach(function (h) {
      var enDia = key === 'day';
      h.style.opacity = enDia ? '' : '0';
      h.style.pointerEvents = enDia ? '' : 'none';
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

  // ── Configurador villa → techo → extras: motor compartido con /dali. La única opción
  //    propia de esta página es ocultarVilla (22-sep-2026, ver el paso data-paso="1" más
  //    arriba) — el resto del motor sigue sin tocarse. ─────────────────────────────────
  window.lwAuCfgInit({
    cfg: CFG,
    waNum: WA_NUM,
    urlBase: '/<?= lw_e($slugPath) ?>',
    villaDefault: MODELO,
    waIntro: "Hi, I'm interested in the ",
    ocultarVilla: true
  });

  // ── Parcela: isla + ubicación → tarifa real por m² (lw_parcela_tarifa_m2(), modelo/
  //    lib.php — misma fuente que /palmfield, nunca un número copiado a mano). Solo
  //    informativo: no entra en "Total configurado" (decisión ya tomada en /palmfield
  //    el 7-sep-2026, ver su docblock) ni en el mensaje de WhatsApp. ──────────────────
  (function () {
    var TARIFAS = <?= json_encode([
        'beachfront' => lw_parcela_tarifa_m2('beachfront'),
        'otras'      => lw_parcela_tarifa_m2('otras'),
        'sumba'      => lw_parcela_tarifa_m2('sumba'),
    ]) ?>;
    var zonaWrap      = document.getElementById('lw-zona-wrap');
    var zonaSumbaWrap = document.getElementById('lw-zona-sumba-wrap');
    var nota          = document.getElementById('lw-parcela-nota');
    if (!zonaWrap || !nota) return;
    function refresca() {
      var isla = document.querySelector('input[name="lw-isla"]:checked');
      var esSumba = !!isla && isla.value === 'sumba';
      zonaWrap.hidden = esSumba;
      if (zonaSumbaWrap) zonaSumbaWrap.hidden = !esSumba;
      var tarifa;
      if (esSumba) {
        tarifa = TARIFAS.sumba;
      } else {
        var zona = document.querySelector('input[name="lw-zona"]:checked');
        tarifa = TARIFAS[zona ? zona.value : 'otras'];
      }
      nota.textContent = 'Plot rate for this selection: €' + tarifa + '/m² — size confirmed on the call, not included in the total above.';
    }
    // 22-sep-2026: isla y ubicación ahora son cada una su propio paso (como villa/techo
    // ya hacían) — elegir una avanza sola al siguiente, reutilizando el botón "Next" del
    // motor compartido (no expone un avanza() propio, así que se simula el click).
    document.querySelectorAll('input[name="lw-isla"], input[name="lw-zona"]').forEach(function (r) {
      r.addEventListener('change', function () {
        refresca();
        var siguiente = document.getElementById('lw-siguiente');
        if (siguiente) siguiente.click();
      });
    });
    refresca();
  }());

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
<script>
/* Seccion activa del menu (barra T3, 23-sep-2026) -- mismo mecanismo que el investor deck. */
(function(){
  var links = [].slice.call(document.querySelectorAll('#lw-topbar nav a[href^="#"]'));
  var secs = links.map(function(a){ return document.getElementById(a.getAttribute('href').slice(1)); }).filter(Boolean);
  if(!secs.length || !('IntersectionObserver' in window)) return;
  var io = new IntersectionObserver(function(es){
    es.forEach(function(e){
      if(!e.isIntersecting) return;
      links.forEach(function(a){ a.classList.toggle('lw-nav-activa', a.getAttribute('href') === '#' + e.target.id); });
    });
  }, { rootMargin: '-45% 0px -50% 0px' });
  secs.forEach(function(sct){ io.observe(sct); });
})();
</script>
<script>
/* v2: barra transparente sobre la foto y solida al bajar (como la home), y fundido .reveal. */
(function(){
  var bar = document.getElementById('lw-topbar');
  function pinta(){ bar.classList.toggle('solid', window.scrollY > 60); }
  window.addEventListener('scroll', pinta, { passive: true }); pinta();
  if(!('IntersectionObserver' in window)){ document.querySelectorAll('.reveal').forEach(function(e){ e.classList.add('in'); }); return; }
  var io = new IntersectionObserver(function(es){ es.forEach(function(e){ if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target); } }); }, { rootMargin: '0px 0px -8% 0px' });
  document.querySelectorAll('.reveal').forEach(function(e){ io.observe(e); });
})();
</script>
</body>
</html>
