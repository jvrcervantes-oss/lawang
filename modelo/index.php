<?php
/**
 * Landing de modelo de villa — /modelo/<id> (regla de reescritura en .htaccess).
 *
 * Reescrita de cero el 30-jul-2026 con la dirección elegida por el owner:
 *   · Estructura CINEMÁTICA: una idea por pantalla, la foto manda, el texto es mínimo.
 *   · Tipografía GROTESCA ARQUITECTÓNICA: una sola familia (Archivo) y todo el contraste
 *     confiado al peso y al tamaño. Los números se leen como datos, con cifras tabulares.
 *   · Paleta TIERRA SATURADA: la teja es fondo de verdad, no un matiz. El verde hondo de
 *     Lawang se queda como acento, que es lo que ata esta página a la marca del sitio
 *     (el owner pidió evolucionar dentro de la marca, no romper con ella).
 *   · El formulario NO está en el primer pantallazo: el CTA abre un panel sobre la foto.
 *     Es lo que se decidió; el coste conocido es un clic más antes de convertir, y la
 *     contrapartida es que el panel llega con la persona ya decidida a pedir la llamada.
 *
 * La teja del panel de color es #A34A26 y no el #B4552F elegido: con crema encima, aquel
 * da 4,31:1 y se queda corto para texto. #B4552F sigue vivo como acento sobre crema.
 *
 * PRECIOS: no hay ninguno inventado. Sin precio cerrado la página no enseña cifra y se
 * marca `noindex` sola, para no indexar una ficha de producto sin producto.
 */
require __DIR__ . '/lib.php';
$MODELOS = require __DIR__ . '/modelos.php';

$m = lw_modelo_get(isset($_GET['m']) ? $_GET['m'] : '', $MODELOS);
if (!$m) {
    // Modelo inexistente o todavía sin renders: al catálogo, nunca a una landing vacía.
    header('Location: /thecollection', true, 302);
    exit;
}

$precio  = lw_precio_fmt($m['precio_desde_eur']);
$nombre  = $m['nombre'];
$dorm    = (int) $m['dormitorios'];
$dormTxt = $dorm . ' ' . ($dorm === 1 ? 'dormitorio' : 'dormitorios');

// La composición es fija por pantalla, no una galería genérica: en una estructura
// cinematográfica una foto decisiva vale más que cinco medianas. Con `?:` para que un
// modelo con menos renders siga sirviendo página en vez de romperse.
$g      = $m['imgs'];
$hero   = $g[0];
$dentroA = isset($g[3]) ? $g[3] : $g[0];
$dentroB = isset($g[4]) ? $g[4] : $g[0];
$plano   = isset($g[5]) ? $g[5] : (isset($g[1]) ? $g[1] : $g[0]);
?><!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($nombre) ?> · Villa llave en mano en Bali — Lawang Estate</title>
<meta name="description" content="<?= lw_e($nombre) ?>: villa de obra nueva de <?= lw_e($dormTxt) ?> en la costa de Bali, llave en mano y construida sobre la parcela que elijas.">
<?php if (!$precio): ?>
<meta name="robots" content="noindex, nofollow"><!-- sin precio cerrado no se indexa -->
<?php endif; ?>
<link rel="canonical" href="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="<?= lw_e($nombre) ?> · Villa llave en mano en Bali">
<meta property="og:description" content="Villa de obra nueva de <?= lw_e($dormTxt) ?> en la costa de Bali, construida sobre la parcela que elijas.">
<meta property="og:url" content="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($hero) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<!-- El render del hero es el LCP: se precarga antes que nada. -->
<link rel="preload" as="image" href="<?= lw_e($hero) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@300;400;500;600;800&display=swap" rel="stylesheet">
<style>
:root{
  /* Tierra saturada. El verde hondo es el puente con la marca del sitio. */
  --teja:#A34A26;        /* fondo de bloque; con crema encima da 5,17:1 */
  --teja-vivo:#B4552F;   /* acento sobre crema, nunca texto pequeño */
  --crema:#F7EFE6;
  --crema-2:#EFE4D6;
  --tinta:#23150F;
  --tinta-2:#5F5147;     /* secundario sobre crema, 6,7:1 */
  --verde:#1F4A3D;
  --linea:#E2D6C8;
  --sans:"Archivo",ui-sans-serif,system-ui,-apple-system,sans-serif;
  --gut:clamp(20px,5vw,72px);
  --wrap:1360px;
  --ease:cubic-bezier(.23,1,.32,1);
  --ease-soft:cubic-bezier(.32,.72,0,1);
}
*{box-sizing:border-box}
html{
  /* Snap por proximidad y NO mandatory, y sin scroll-behavior:smooth: en este mismo
     proyecto la combinación de smooth + mandatory ya rompió el scroll en WebKit, y con
     mandatory una sección más alta que la pantalla (la FAQ) atrapa el gesto. */
  scroll-snap-type:y proximity;
}
body{margin:0;background:var(--crema);color:var(--tinta);font-family:var(--sans);
  font-size:17px;line-height:1.55;font-weight:300;-webkit-font-smoothing:antialiased}
img{max-width:100%;display:block}
a{color:inherit}
h1,h2,h3{margin:0;font-weight:800;letter-spacing:-.025em;line-height:.98;
  text-transform:uppercase;text-wrap:balance}
p{margin:0;text-wrap:pretty}
:focus-visible{outline:2px solid var(--verde);outline-offset:3px}

/* Cifras y datos: tabulares siempre. Es media identidad de la página. */
.num{font-variant-numeric:tabular-nums;font-feature-settings:"tnum" 1}

.wrap{width:100%;max-width:var(--wrap);margin-inline:auto;padding-inline:var(--gut)}
.esc{position:relative;min-height:100svh;display:flex;flex-direction:column;
  justify-content:center;scroll-snap-align:start;overflow:hidden}
.esc--auto{min-height:0;scroll-snap-align:none;padding-block:clamp(72px,10vw,140px)}
.et{font-size:11px;font-weight:600;letter-spacing:.2em;text-transform:uppercase}
.tit{font-size:clamp(34px,5.6vw,76px)}
.dice{font-size:clamp(15px,1.35vw,18px);max-width:52ch;color:var(--tinta-2);
  font-weight:300;margin-top:1.2em}

/* ── Marca fija ───────────────────────────────────────────────────────────── */
.marca{position:absolute;inset:0 0 auto;z-index:20;height:66px;display:flex;
  align-items:center;pointer-events:none}
.marca .wrap{display:flex;justify-content:space-between;align-items:center}
.marca span{color:var(--crema);text-shadow:0 1px 14px rgba(24,12,6,.6);font-size:14px;font-weight:600;letter-spacing:.26em;
  text-transform:uppercase}
.marca em{font-style:normal;font-size:11px;font-weight:400;letter-spacing:.2em;
  color:var(--crema);opacity:.85;text-shadow:0 1px 14px rgba(24,12,6,.6)}

/* ── 01 · Hero a sangre ───────────────────────────────────────────────────── */
.hero{justify-content:flex-end;padding-bottom:clamp(28px,5vw,64px);color:var(--crema)}
.hero__foto{position:absolute;inset:0}
.hero__foto img{width:100%;height:100%;object-fit:cover}
.hero__foto::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,
  rgba(24,12,6,.52) 0%, rgba(24,12,6,.06) 30%, rgba(24,12,6,.42) 70%, rgba(24,12,6,.88) 100%)}
.hero .wrap{position:relative;z-index:2}
.hero h1{font-size:clamp(34px,5.4vw,80px);max-width:14ch}
.hero__et{color:rgba(247,239,230,.82);margin-bottom:1.6em}
.hero .dice{color:rgba(247,239,230,.9);max-width:40ch}
.hero__pie{display:flex;flex-wrap:wrap;align-items:flex-end;gap:clamp(20px,4vw,56px);
  justify-content:space-between;margin-top:clamp(26px,4vw,48px)}
.hero__datos{display:flex;flex-wrap:wrap;gap:clamp(18px,3vw,44px)}
.hero__datos div{min-width:96px}
.hero__datos b{display:block;font-size:clamp(20px,2.2vw,28px);font-weight:600;
  letter-spacing:-.02em}
.hero__datos small{display:block;font-size:10.5px;font-weight:500;letter-spacing:.18em;
  text-transform:uppercase;color:rgba(247,239,230,.88);margin-top:4px}

/* ── Botón ────────────────────────────────────────────────────────────────── */
.btn{display:inline-flex;align-items:center;gap:16px;border:0;cursor:pointer;
  background:var(--verde);color:var(--crema);font-family:inherit;font-size:12.5px;
  font-weight:600;letter-spacing:.16em;text-transform:uppercase;text-decoration:none;
  padding:19px 26px;
  transition:transform .18s var(--ease),background .22s var(--ease)}
.btn svg{width:15px;height:15px;stroke:currentColor;stroke-width:1.8;fill:none;
  transition:transform .28s var(--ease)}
.btn:active{transform:scale(.98)}
.btn--crema{background:var(--crema);color:var(--tinta)}
.btn--ancho{width:100%;justify-content:center}
@media (hover:hover) and (pointer:fine){
  .btn:hover{background:#163529}
  .btn:hover svg{transform:translateX(4px)}
  .btn--crema:hover{background:#fff}
}

/* ── 02 · Bloque de cifras, teja entera ───────────────────────────────────── */
.cifras{background:var(--teja);color:var(--crema)}
.cifras .et{color:var(--crema)}
.cifras__rej{display:grid;gap:clamp(28px,4vw,56px);margin-top:clamp(36px,5vw,64px);
  grid-template-columns:repeat(auto-fit,minmax(170px,1fr))}
.cifras__rej > div{border-top:1px solid rgba(247,239,230,.28);padding-top:18px}
.cifras b{display:block;font-size:clamp(44px,6.4vw,88px);font-weight:800;
  letter-spacing:-.045em;line-height:.9}
.cifras small{display:block;font-size:11px;font-weight:500;letter-spacing:.16em;
  text-transform:uppercase;color:var(--crema);margin-top:14px;max-width:20ch}

/* ── 03 · Acabados: foto a sangre + lista ─────────────────────────────────── */
.dos{display:grid;grid-template-columns:1fr 1fr;min-height:100svh}
.dos__foto{position:relative;background:var(--crema-2)}
.dos__foto img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.dos__txt{display:flex;flex-direction:column;justify-content:center;
  padding:clamp(48px,6vw,96px) clamp(24px,4.5vw,84px)}
.acab{margin-top:clamp(26px,3.4vw,44px)}
.acab__f{display:grid;grid-template-columns:auto 1fr;gap:20px;align-items:baseline;
  padding:20px 0;border-top:1px solid var(--linea)}
.acab__f:last-child{border-bottom:1px solid var(--linea)}
.acab__n{font-size:12px;font-weight:600;letter-spacing:.14em;color:var(--teja-vivo)}
.acab__f h3{font-size:clamp(19px,1.7vw,23px);letter-spacing:-.015em}
.acab__f p{font-size:14.5px;color:var(--tinta-2);margin-top:8px;max-width:44ch}

/* ── 04 · Pantallas de foto ───────────────────────────────────────────────── */
.foto{padding:0;justify-content:stretch}
.foto__rej{display:grid;grid-template-columns:1fr 1fr;flex:1}
.foto img{width:100%;height:100%;object-fit:cover;min-height:100svh}
.foto__rej img{min-height:100svh}
.pie{position:absolute;left:0;right:0;bottom:0;z-index:2;padding:26px 0;
  background:linear-gradient(0deg,rgba(24,12,6,.78),transparent)}
.pie .wrap{display:flex;justify-content:space-between;gap:20px;flex-wrap:wrap;
  color:rgba(247,239,230,.92);font-size:12px;font-weight:500;letter-spacing:.16em;
  text-transform:uppercase}

/* ── 05 · Alcance de obra, tabla técnica ──────────────────────────────────── */
.obra{background:var(--crema-2)}
.obra__rej{display:grid;gap:clamp(32px,5vw,80px);grid-template-columns:1.1fr .9fr;
  margin-top:clamp(32px,4vw,56px)}
.obra h3{font-size:12px;font-weight:600;letter-spacing:.18em;margin-bottom:18px}
.obra ul{list-style:none;margin:0;padding:0}
.obra li{display:grid;grid-template-columns:26px 1fr;gap:6px;padding:11px 0;
  border-top:1px solid var(--linea);font-size:15px}
.obra li:last-child{border-bottom:1px solid var(--linea)}
.obra li i{font-style:normal;font-weight:600;color:var(--teja-vivo)}
.obra--no li i{color:var(--tinta-2)}
.obra__nota{font-size:13.5px;color:var(--tinta-2);margin-top:22px;max-width:46ch}

/* ── 06 · El sitio ────────────────────────────────────────────────────────── */
.sitio{color:var(--crema);justify-content:flex-end;padding-bottom:clamp(40px,6vw,88px)}
.sitio__foto{position:absolute;inset:0;display:grid;grid-template-columns:1.35fr 1fr}
.sitio__foto img{width:100%;height:100%;object-fit:cover}
.sitio::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,
  rgba(24,12,6,.10) 40%, rgba(24,12,6,.86) 100%)}
.sitio .wrap{position:relative;z-index:2}
.sitio .dice{color:rgba(247,239,230,.9)}

/* ── 07 · Pasos, verde hondo ──────────────────────────────────────────────── */
.pasos{background:var(--verde);color:var(--crema)}
.pasos .et{color:rgba(247,239,230,.7)}
.pasos__rej{display:grid;gap:clamp(28px,4vw,64px);grid-template-columns:repeat(3,1fr);
  margin-top:clamp(38px,5vw,68px)}
.pasos__rej > div{border-top:1px solid rgba(247,239,230,.3);padding-top:20px}
.pasos b{display:block;font-size:clamp(30px,3.6vw,46px);font-weight:800;
  letter-spacing:-.04em;color:rgba(247,239,230,.5)}
.pasos h3{font-size:clamp(17px,1.6vw,21px);margin:14px 0 10px}
.pasos p{font-size:14.5px;color:rgba(247,239,230,.82);max-width:34ch}

/* ── 08 · Preguntas ───────────────────────────────────────────────────────── */
.faq{max-width:860px;margin-top:clamp(28px,3.4vw,46px)}
.faq details{border-top:1px solid var(--linea)}
.faq details:last-of-type{border-bottom:1px solid var(--linea)}
.faq summary{cursor:pointer;list-style:none;padding:22px 44px 22px 0;position:relative;
  font-size:clamp(16px,1.5vw,19px);font-weight:500;letter-spacing:-.01em}
.faq summary::-webkit-details-marker{display:none}
.faq summary::after{content:"";position:absolute;right:10px;top:50%;width:13px;height:13px;
  margin-top:-6px;border-right:1.5px solid var(--teja-vivo);
  border-bottom:1.5px solid var(--teja-vivo);transform:translateY(-3px) rotate(45deg);
  transition:transform .28s var(--ease)}
.faq details[open] summary::after{transform:translateY(2px) rotate(-135deg)}
.faq p{padding:0 0 24px;font-size:15px;color:var(--tinta-2);max-width:62ch}
@media (hover:hover) and (pointer:fine){.faq summary:hover{color:var(--teja-vivo)}}
@supports (interpolate-size:allow-keywords){
  @media (prefers-reduced-motion:no-preference){
    :root{interpolate-size:allow-keywords}
    .faq details::details-content{block-size:0;overflow:hidden;opacity:0;
      transition:block-size .34s var(--ease-soft),opacity .26s var(--ease),
                 content-visibility .34s allow-discrete}
    .faq details[open]::details-content{block-size:auto;opacity:1}
  }
}

/* ── 09 · Cierre ──────────────────────────────────────────────────────────── */
.cierre{background:var(--teja);color:var(--crema);text-align:center}
.cierre .tit{max-width:16ch;margin-inline:auto}
.cierre .dice{color:var(--crema);margin-inline:auto}
.cierre .btn{margin-top:clamp(30px,4vw,48px)}

.pieweb{background:var(--tinta);color:rgba(247,239,230,.62);padding-block:30px;
  font-size:12px;letter-spacing:.04em}
.pieweb .wrap{display:flex;justify-content:space-between;gap:18px;flex-wrap:wrap}
.pieweb a{text-decoration:none;border-bottom:1px solid transparent}
.pieweb a:hover{border-bottom-color:currentColor}

/* ── Panel del formulario ─────────────────────────────────────────────────── */
.panel{border:0;padding:0;background:transparent;max-width:min(560px,calc(100vw - 32px));
  width:100%;max-height:calc(100svh - 32px);color:var(--tinta)}
.panel::backdrop{background:rgba(24,12,6,.72);backdrop-filter:blur(6px);
  -webkit-backdrop-filter:blur(6px)}
.panel__in{background:var(--crema);padding:clamp(26px,3.4vw,42px)}
.panel h2{font-size:clamp(24px,2.6vw,32px)}
.panel__x{position:absolute;top:14px;right:14px;width:38px;height:38px;border:0;
  background:none;cursor:pointer;color:var(--tinta);font-size:22px;line-height:1;
  font-family:inherit}
.campo{margin-top:18px}
.campo label{display:block;font-size:10.5px;font-weight:600;letter-spacing:.16em;
  text-transform:uppercase;color:var(--tinta-2);margin-bottom:7px;
  transition:color .2s var(--ease)}
.campo:focus-within label{color:var(--verde)}
.campo input{width:100%;font-family:inherit;font-size:16px;font-weight:400;
  color:var(--tinta);background:#fff;border:1px solid var(--linea);border-radius:0;
  padding:13px 14px;transition:border-color .2s var(--ease),box-shadow .2s var(--ease)}
.campo input:focus{outline:none;border-color:var(--verde);
  box-shadow:0 0 0 3px rgba(31,74,61,.14)}
.campo input[aria-invalid="true"]{border-color:#9C3B2E;box-shadow:0 0 0 3px rgba(156,59,46,.12)}
.campo .err{display:none;font-size:12.5px;color:#8E3527;margin-top:6px}
.campo input[aria-invalid="true"] ~ .err{display:block}
.acepto{display:flex;gap:11px;align-items:flex-start;font-size:13px;color:var(--tinta-2);
  line-height:1.45;margin:22px 0 22px}
.acepto input{margin-top:2px;accent-color:var(--verde);flex:0 0 auto;width:17px;height:17px}
.acepto a{color:var(--verde)}
.trampa{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.aviso{margin-top:14px;font-size:13.5px;color:var(--tinta-2);min-height:1.1em}
.aviso--mal{color:#8E3527}
.gracias h2{margin-bottom:.4em}

/* CTA fijo en móvil: con el formulario detrás de un clic, el clic tiene que estar
   siempre a mano. */
.fijo{position:fixed;left:0;right:0;bottom:0;z-index:40;display:none;
  padding:12px 16px calc(12px + env(safe-area-inset-bottom));background:var(--crema);
  border-top:1px solid var(--linea);transform:translateY(110%);
  transition:transform .34s var(--ease-soft)}
.fijo.on{transform:translateY(0)}

/* ── Entradas ─────────────────────────────────────────────────────────────── */
.js .rv{opacity:0;transform:translateY(20px);
  transition:opacity .75s var(--ease),transform .75s var(--ease)}
.js .rv.in{opacity:1;transform:none}

@media(max-width:900px){
  .dos,.foto__rej,.sitio__foto{grid-template-columns:1fr}
  .dos__foto{min-height:58svh}
  .dos{min-height:0}
  .foto__rej img,.foto img{min-height:52svh}
  .obra__rej{grid-template-columns:1fr}
  .pasos__rej{grid-template-columns:1fr}
  .sitio__foto{grid-template-rows:1fr 1fr}
  .hero{padding-bottom:150px}
  .hero__pie .btn{display:none}
  .fijo{display:block;transform:translateY(0)}
  /* consent.js inyecta su <style> DESPUÉS de este y con la misma especificidad ganaba
     por orden: el aviso se sentaba encima de la barra fija. */
  body #lw-consent-bar{bottom:88px}
}
@media(prefers-reduced-motion:reduce){
  html{scroll-snap-type:none}
  .js .rv{opacity:1;transform:none;transition:none}
  .btn,.btn svg,.fijo,.faq summary::after{transition:none}
}
/* Sin JavaScript el panel se abre como ancla: el formulario nunca queda inalcanzable. */
.panel:target{display:block;position:static;margin:0 auto clamp(48px,8vw,96px);
  max-width:min(560px,calc(100vw - 32px))}
</style>
<script>document.documentElement.className += ' js';</script>
</head>
<body>

<header class="marca">
  <div class="wrap">
    <span>Lawang</span>
    <em>Bali, Indonesia</em>
  </div>
</header>

<!-- 01 ───────────────────────────────────────────────────────────────────── -->
<section class="esc hero">
  <div class="hero__foto">
    <img src="<?= lw_e($hero) ?>" alt="Villa <?= lw_e($nombre) ?> de Lawang Estate, exterior con piscina" fetchpriority="high">
  </div>
  <div class="wrap">
    <p class="et hero__et">Modelo <?= lw_e($nombre) ?> · Lawang Estate</p>
    <h1>Villa llave en mano en Bali</h1>
    <p class="dice"><?= lw_e($m['sub']) ?></p>
    <div class="hero__pie">
      <div class="hero__datos num">
        <div><b><?= $dorm ?></b><small><?= $dorm === 1 ? 'Dormitorio' : 'Dormitorios' ?></small></div>
        <div><b>3</b><small>Acabados</small></div>
        <div><b>Overflow</b><small>Piscina</small></div>
      </div>
      <button class="btn" type="button" data-abre>
        Reservar mi llamada
        <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2 8h12M9 3l5 5-5 5"/></svg>
      </button>
    </div>
  </div>
</section>

<!-- 02 ───────────────────────────────────────────────────────────────────── -->
<section class="esc cifras">
  <div class="wrap">
    <p class="et rv">Lo que se compra</p>
    <div class="cifras__rej num">
      <div class="rv"><b><?= $dorm ?></b><small><?= $dorm === 1 ? 'Dormitorio en suite' : 'Dormitorios en suite' ?></small></div>
      <div class="rv"><b>3</b><small>Acabados de cubierta a elegir</small></div>
      <div class="rv"><b>3.500</b><small>Vatios de acometida eléctrica</small></div>
      <div class="rv"><b>1</b><small>Parcela, la que elijas del catálogo</small></div>
    </div>
  </div>
</section>

<?php if ($m['acabados']): ?>
<!-- 03 ───────────────────────────────────────────────────────────────────── -->
<section class="esc dos" style="scroll-snap-align:start">
  <div class="dos__foto">
    <img src="/assets/img/modelo/dali-cubierta.jpg" alt="Cubierta de alang-alang de la villa <?= lw_e($nombre) ?>" loading="lazy" width="1100" height="1375">
  </div>
  <div class="dos__txt">
    <p class="et rv">Acabados</p>
    <h2 class="tit rv" style="margin-top:.2em">La cubierta decide el presupuesto</h2>
    <p class="dice rv">El resto de la villa no cambia. Se elige antes de cerrar números.</p>
    <div class="acab">
      <?php foreach ($m['acabados'] as $i => $a): ?>
      <div class="acab__f rv">
        <span class="acab__n num"><?= str_pad($i + 1, 2, '0', STR_PAD_LEFT) ?></span>
        <div>
          <h3><?= lw_e($a['n']) ?></h3>
          <p><?= lw_e($a['d']) ?></p>
        </div>
      </div>
      <?php endforeach; ?>
    </div>
  </div>
</section>
<?php endif; ?>

<!-- 04 ───────────────────────────────────────────────────────────────────── -->
<section class="esc foto">
  <div class="foto__rej">
    <img src="<?= lw_e($dentroA) ?>" alt="Interior de la villa <?= lw_e($nombre) ?>" loading="lazy">
    <img src="<?= lw_e($dentroB) ?>" alt="Baño de la villa <?= lw_e($nombre) ?>" loading="lazy">
  </div>
  <div class="pie"><div class="wrap"><span><?= lw_e($nombre) ?>, por dentro</span><span class="num">Render de proyecto</span></div></div>
</section>

<?php if ($m['alcance']): ?>
<!-- 05 ───────────────────────────────────────────────────────────────────── -->
<section class="esc esc--auto obra">
  <div class="wrap">
    <p class="et rv">Alcance de obra</p>
    <h2 class="tit rv" style="margin-top:.2em">Qué entra y qué no</h2>
    <div class="obra__rej">
      <div class="rv">
        <h3>Incluido</h3>
        <ul>
          <?php foreach ($m['alcance']['incluido'] as $k => $li): ?>
          <li><i class="num"><?= str_pad($k + 1, 2, '0', STR_PAD_LEFT) ?></i><span><?= lw_e($li) ?></span></li>
          <?php endforeach; ?>
        </ul>
      </div>
      <div class="rv">
        <h3>No incluido</h3>
        <ul class="obra--no">
          <?php foreach ($m['alcance']['no_incluido'] as $li): ?>
          <li><i>&ndash;</i><span><?= lw_e($li) ?></span></li>
          <?php endforeach; ?>
        </ul>
        <p class="obra__nota">Tal cual figura en el pliego del contratista. La parcela y los
          gastos de compraventa (impuestos, notaría y licencias) se presupuestan aparte y se
          detallan por escrito antes de firmar nada.</p>
      </div>
    </div>
  </div>
</section>
<?php endif; ?>

<!-- 06 ───────────────────────────────────────────────────────────────────── -->
<section class="esc sitio">
  <div class="sitio__foto">
    <img src="/assets/img/lugar/costa.jpg" alt="Desembocadura del río y playa de arena volcánica en la costa oeste de Bali, vista cenital" loading="lazy">
    <img src="/assets/img/lugar/rio.jpg" alt="Valle y río junto a la costa, vista aérea" loading="lazy">
  </div>
  <div class="wrap">
    <p class="et rv">El sitio</p>
    <h2 class="tit rv" style="margin-top:.2em;max-width:14ch">La costa, no el render</h2>
    <p class="dice rv">Estas dos fotografías son de la zona, tomadas con dron. En la llamada
      te decimos qué parcelas quedan y cómo se llega a cada una.</p>
  </div>
</section>

<!-- 07 ───────────────────────────────────────────────────────────────────── -->
<section class="esc pasos">
  <div class="wrap">
    <p class="et rv">Cómo se compra</p>
    <div class="pasos__rej num">
      <div class="rv"><b>01</b><h3>Llamada</h3><p>Media hora para ver qué parcela encaja, con qué presupuesto y en qué plazos.</p></div>
      <div class="rv"><b>02</b><h3>Presupuesto y parcela</h3><p>Precio cerrado del acabado elegido, parcela concreta y calendario de pagos.</p></div>
      <div class="rv"><b>03</b><h3>Reserva y obra</h3><p>Contrato de reserva, después el PPJB de compraventa, y arranca la construcción.</p></div>
    </div>
  </div>
</section>

<!-- 08 ───────────────────────────────────────────────────────────────────── -->
<section class="esc esc--auto">
  <div class="wrap">
    <p class="et rv">Antes de la llamada</p>
    <h2 class="tit rv" style="margin-top:.2em">Lo que suelen preguntar</h2>
    <div class="faq rv">
<?php /* Comentario de PHP y no de HTML A PROPÓSITO: esto no debe viajar al navegador.

         La titularidad abre el bloque por decisión de marca (PRODUCT.md: "Freehold first,
         es el diferenciador más fuerte").

         OJO AL TEXTO: Legal tumbó el 30-jul la primera versión, que decía "hay parcelas en
         freehold" y que la titularidad de un extranjero "se estructura a través de una
         sociedad indonesia". En España freehold se lee como pleno dominio perpetuo y en
         Indonesia un extranjero nunca obtiene Hak Milik; y la segunda frase, suelta, se lee
         como oferta de estructura nominee. Hasta que Legal redacte la versión definitiva,
         esta respuesta dice solo lo que es cierto sin cualificar.
         NO reintroducir "freehold" aquí sin el OK de Legal. */ ?>
      <details>
        <summary>¿Qué compro exactamente y en qué régimen?</summary>
        <p>La villa construida y el derecho sobre la parcela en la que se levanta. En
          Indonesia ese derecho no funciona como la propiedad española y no todas las
          parcelas están en el mismo régimen ni con el mismo plazo. Es la primera cosa que
          repasamos en la llamada, parcela por parcela y con el documento delante, antes de
          hablar de dinero.</p>
      </details>
      <details>
        <summary>¿Qué incluye el precio?</summary>
        <p>La obra completa según el pliego del contratista, con el acabado de cubierta que
          elijas. La parcela y los gastos de compraventa (impuestos, notaría y licencias) se
          presupuestan aparte y se detallan por escrito antes de firmar nada.</p>
      </details>
      <details>
        <summary>¿Puedo elegir dónde se construye?</summary>
        <p>Sí. El modelo es el mismo y se levanta sobre la parcela que elijas del catálogo.
          Cambian la vista, la orientación y el precio del terreno. No todas las parcelas
          admiten cualquier modelo: eso se concreta en la llamada.</p>
      </details>
      <details>
        <summary>¿En qué moneda se firma?</summary>
        <p>El contrato se formaliza en rupias indonesias, como exige la ley indonesia para
          operaciones dentro del país. La equivalencia en euros se incluye a título
          informativo con el tipo de cambio de la fecha.</p>
      </details>
      <details>
        <summary>¿Cómo se formaliza la compra?</summary>
        <p>Primero un contrato de reserva sobre la parcela. Después el PPJB, que es el
          contrato de compraventa indonesio, y el contrato de construcción. Los tres son
          documentos propios del promotor y se revisan antes de firmar.</p>
      </details>
      <details>
        <summary>¿Quién construye?</summary>
        <p>Lawang Estate, sociedad indonesia PT Tepi Sun Gai. En la llamada te enseñamos
          obras entregadas y las que están en marcha ahora mismo.</p>
      </details>
    </div>
  </div>
</section>

<!-- 09 ───────────────────────────────────────────────────────────────────── -->
<section class="esc cierre">
  <div class="wrap">
    <h2 class="tit rv">Hablamos y te pasamos números</h2>
    <p class="dice rv">Una llamada para ver parcela, presupuesto y plazos. Sin compromiso.</p>
    <p><button class="btn btn--crema rv" type="button" data-abre>
      Reservar mi llamada
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2 8h12M9 3l5 5-5 5"/></svg>
    </button></p>
  </div>
</section>

<footer class="pieweb">
  <div class="wrap">
    <span>Lawang Estate · PT Tepi Sun Gai · Bali, Indonesia</span>
    <span><a href="/legal">Aviso legal y privacidad</a> ·
      <!-- Retirar el consentimiento tiene que ser tan facil como darlo (RGPD art. 7.3). -->
      <a href="#" onclick="window.lwConsentReopen&&window.lwConsentReopen();return false">Preferencias de cookies</a></span>
  </div>
</footer>

<div class="fijo" id="lw-fijo">
  <a class="btn btn--ancho" href="#lw-panel" data-abre>
    Reservar mi llamada
    <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2 8h12M9 3l5 5-5 5"/></svg>
  </a>
</div>

<dialog class="panel" id="lw-panel" aria-labelledby="lw-panel-h">
  <div class="panel__in" style="position:relative">
    <button class="panel__x" type="button" data-cierra aria-label="Cerrar">&times;</button>
    <form id="lw-form" novalidate>
      <h2 id="lw-panel-h">Reserva tu llamada</h2>
      <p class="dice" style="margin-top:.7em;font-size:14px">Te damos el presupuesto cerrado
        del acabado que te interese y las parcelas disponibles donde puede construirse.</p>

      <div class="campo">
        <label for="lw-nombre">Nombre y apellidos</label>
        <input type="text" id="lw-nombre" name="name" autocomplete="name" required maxlength="120">
        <span class="err">Dinos cómo te llamas.</span>
      </div>
      <div class="campo">
        <label for="lw-email">Email</label>
        <input type="email" id="lw-email" name="email" autocomplete="email" required maxlength="180">
        <span class="err">Revisa el email: no parece válido.</span>
      </div>
      <div class="campo">
        <label for="lw-tel">Teléfono</label>
        <input type="tel" id="lw-tel" name="phone" autocomplete="tel" required maxlength="40">
        <span class="err">Necesitamos un teléfono para llamarte.</span>
      </div>

      <!-- Trampa de bots: un humano nunca la ve, así que si viene rellena, es un bot. -->
      <div class="trampa" aria-hidden="true"><label for="lw-web">No rellenar</label>
        <input type="text" id="lw-web" name="website" tabindex="-1" autocomplete="off"></div>

      <label class="acepto" for="lw-consent">
        <input type="checkbox" id="lw-consent" name="consent" value="1" required>
        <span>He leído y acepto la <a href="/legal#privacy" target="_blank" rel="noopener">Política de Privacidad</a>
          y que Lawang Estate me contacte sobre este modelo.</span>
      </label>

      <button class="btn btn--ancho" type="submit" id="lw-submit">
        <span>Reservar mi llamada</span>
        <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2 8h12M9 3l5 5-5 5"/></svg>
      </button>
      <p class="aviso" id="lw-aviso" role="status" aria-live="polite"></p>
    </form>
  </div>
</dialog>

<script src="/assets/consent.js?v=20260730" defer></script>
<script>
(function () {
  'use strict';
  var MODELO = <?= json_encode($m['id']) ?>;
  var VALUE  = <?= $m['precio_desde_eur'] === null ? 'null' : (float) $m['precio_desde_eur'] ?>;

  // ── Píxel ──────────────────────────────────────────────────────────────────
  // `value` solo viaja cuando el número es real, porque Meta puja por ese importe.
  function track(ev) {
    if (typeof window.lwTrack !== 'function') return;   // sin consentimiento no sale nada
    var p = {content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO};
    if (VALUE !== null) { p.value = VALUE; p.currency = 'EUR'; }
    window.lwTrack(ev, p);
  }
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  // ── Panel ─────────────────────────────────────────────────────────────────
  var panel = document.getElementById('lw-panel');
  var abierto = false;
  function abrir(e) {
    if (e) e.preventDefault();
    if (typeof panel.showModal !== 'function') { location.hash = 'lw-panel'; return; }
    panel.showModal();
    // Con el formulario detrás de un clic, abrirlo ES el paso intermedio del embudo.
    // Sin este evento solo hay "vio la página" y "dejó los datos", sin nada en medio
    // con lo que Meta pueda optimizar.
    if (!abierto) { track('InitiateCheckout'); abierto = true; }
    setTimeout(function () { document.getElementById('lw-nombre').focus(); }, 80);
  }
  [].forEach.call(document.querySelectorAll('[data-abre]'), function (b) {
    b.addEventListener('click', abrir);
  });
  [].forEach.call(document.querySelectorAll('[data-cierra]'), function (b) {
    b.addEventListener('click', function () { panel.close(); });
  });
  // Clic en el fondo del diálogo: el <dialog> ocupa todo, así que se compara el punto.
  panel.addEventListener('click', function (e) {
    var c = panel.getBoundingClientRect();
    if (e.clientX < c.left || e.clientX > c.right || e.clientY < c.top || e.clientY > c.bottom) panel.close();
  });

  // ── Entradas al aparecer ──────────────────────────────────────────────────
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var revs = document.querySelectorAll('.rv');
  function revelarTodo() { for (var k = 0; k < revs.length; k++) revs[k].classList.add('in'); }
  window.addEventListener('beforeprint', revelarTodo);

  if (reduce || !('IntersectionObserver' in window)) {
    revelarTodo();
  } else {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (!e.isIntersecting) return;
        var sibs = Array.prototype.slice.call(e.target.parentNode.children);
        e.target.style.transitionDelay = (Math.min(sibs.indexOf(e.target), 5) * 70) + 'ms';
        e.target.classList.add('in');
        io.unobserve(e.target);
      });
    }, {threshold: 0.15, rootMargin: '0px 0px -6% 0px'});
    for (var j = 0; j < revs.length; j++) io.observe(revs[j]);

    // El observador solo avisa cuando CAMBIA la intersección: arrastrando la barra de
    // scroll de golpe, una sección pasa de "debajo" a "encima" sin un solo aviso y se
    // queda invisible para siempre. `scrollend` salta una vez al parar, no por frame.
    if ('onscrollend' in window) {
      window.addEventListener('scrollend', function () {
        for (var q = 0; q < revs.length; q++) {
          if (!revs[q].classList.contains('in') &&
              revs[q].getBoundingClientRect().top < window.innerHeight) {
            revs[q].classList.add('in');
            io.unobserve(revs[q]);
          }
        }
      }, {passive: true});
    }
  }

  // ── Barra fija de móvil: aparece cuando el hero sale de pantalla ──────────
  var fijo = document.getElementById('lw-fijo');
  var hero = document.querySelector('.hero');
  var ioFijo = null;
  if ('IntersectionObserver' in window) {
    ioFijo = new IntersectionObserver(function (es) {
      fijo.classList.toggle('on', !es[0].isIntersecting);
    }, {threshold: 0.2});
    ioFijo.observe(hero);
  }

  // ── Envío ─────────────────────────────────────────────────────────────────
  var form = document.getElementById('lw-form');
  var aviso = document.getElementById('lw-aviso');
  var btn = document.getElementById('lw-submit');
  var campos = ['lw-nombre', 'lw-email', 'lw-tel'];

  function marca(el, malo) { el.setAttribute('aria-invalid', malo ? 'true' : 'false'); }
  campos.forEach(function (id) {
    var el = document.getElementById(id);
    el.addEventListener('input', function () {
      if (el.getAttribute('aria-invalid') === 'true') marca(el, !el.checkValidity());
    });
  });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    aviso.className = 'aviso';

    var malo = null;
    campos.forEach(function (id) {
      var el = document.getElementById(id);
      var ok = el.checkValidity() && el.value.trim() !== '';
      marca(el, !ok);
      if (!ok && !malo) malo = el;
    });
    var cons = document.getElementById('lw-consent');
    if (!cons.checked) {
      aviso.className = 'aviso aviso--mal';
      aviso.textContent = 'Falta aceptar la política de privacidad.';
      if (!malo) { cons.focus(); return; }
    }
    if (malo) { malo.focus(); return; }
    if (!cons.checked) return;

    btn.disabled = true;
    btn.setAttribute('aria-busy', 'true');
    // Solo la etiqueta: `btn.textContent` se llevaría por delante el icono.
    var label = btn.querySelector('span');
    var etiqueta = label.textContent;
    label.textContent = 'Enviando';
    aviso.textContent = '';

    var body = new FormData(form);
    body.append('source', 'landing-modelo');
    body.append('property', MODELO);
    // Atribución: sin esto el lead entra sin anuncio de origen y no hay coste por lead
    // por anuncio ni forma de subir la venta como conversión offline.
    var q = new URLSearchParams(location.search), camp = [];
    ['utm_source','utm_medium','utm_campaign','utm_content','utm_term','fbclid']
      .forEach(function (k) { if (q.get(k)) camp.push(k + '=' + q.get(k)); });
    body.append('campana', camp.join('&'));

    var nombre = document.getElementById('lw-nombre').value.trim().split(' ')[0];

    fetch('/api/lead.php', {method: 'POST', body: body})
      .then(function (r) { return r.json().then(function (j) { return {ok: r.ok, j: j}; }); })
      .then(function (res) {
        if (!res.ok || !res.j.ok) throw new Error(res.j.error || 'error');
        track('Lead');
        // textContent y no innerHTML: el nombre lo escribe el visitante y vuelve a la página.
        var h = document.createElement('h2');
        h.textContent = 'Gracias, ' + nombre + '.';
        var p = document.createElement('p');
        p.className = 'dice';
        p.style.marginTop = '.7em';
        p.textContent = 'Hemos recibido tu solicitud. Te contactamos para agendar la llamada.';
        form.textContent = '';
        form.className = 'gracias';
        form.appendChild(h); form.appendChild(p);
        // La barra fija seguía ofreciendo "Reservar mi llamada" a quien acababa de
        // reservarla: se desconecta el observador y se retira.
        if (ioFijo) ioFijo.disconnect();
        fijo.remove();
      })
      .catch(function (err) {
        btn.disabled = false;
        btn.removeAttribute('aria-busy');
        label.textContent = etiqueta;
        aviso.className = 'aviso aviso--mal';
        aviso.textContent = String(err.message) === 'too_many'
          ? 'Has enviado varias solicitudes seguidas. Inténtalo dentro de un rato.'
          : 'No hemos podido enviar la solicitud. Escríbenos a sales@lawangproperties.com.';
      });
  });
})();
</script>
</body>
</html>
