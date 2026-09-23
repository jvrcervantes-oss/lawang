<?php
/**
 * /portfolio — landing de seleccion de modelo de villa (23-sep-2026).
 *
 * Pedido del owner: «al clicar "The Portfolio" en lawangproperties.com necesito que nos
 * lleve a una landing intermedia de seleccion de modelo, con los 5 modelos y sus enlaces,
 * con la estetica lo mas parecida a lawangproperties.com».
 *
 * DATOS: la MISMA fuente que /modelo/<id> — lw_au_catalogo() (Supabase `catalogo_publico()`,
 * con cache y respaldo en frio, ver modelo/catalogo.php). Nada escrito a mano aqui: un modelo
 * que se publique o retire en /intranet/modelos/ aparece o desaparece solo. El «desde» es el
 * techo mas barato de cada villa (nunca la suma de los dos), mismo criterio que la ficha.
 *
 * ESTETICA: la de la home y /thecollection — barra sólida crema con el menu en pildora y el
 * CTA de WhatsApp, fondo crema con la textura de /thecollection, Neue Kabel + The Seasons
 * (locales, mismos ficheros), portada centrada como «OWN A PIECE OF INDONESIA» y las tarjetas
 * `.lw-prop` de assets/lawang-card.css (la misma tarjeta que la home). Pie compartido
 * assets/lawang-pie.js. Solo ingles, como /modelo (sin hreflang hasta que haya traduccion).
 *
 * PIXEL: sin ViewContent aqui a proposito — cada /modelo/<id> ya lo dispara; repetirlo en el
 * paso intermedio duplicaria el evento por visita (revision previa de Marketing).
 */
require __DIR__ . '/modelo/datos.php';
$MODELOS = require __DIR__ . '/modelo/modelos.php';
$CAT = lw_au_catalogo();
// Orden de la villa mas pequena a la mas grande (superficie villa + terraza).
uasort($CAT, function ($a, $b) { return ($a['villa_m2'] + $a['terraza_m2']) <=> ($b['villa_m2'] + $b['terraza_m2']); });

$WA_LINK = 'https://wa.me/6281138319862?text=' . rawurlencode("Hi LAWANG, I'm looking at your villa models and I'd like to know more.");
$SITE = 'https://lawangproperties.com';
$ogImg = null;
foreach ($CAT as $v) { if (!empty($v['thumb'])) { $ogImg = $v['thumb']; break; } }
$ogImgAbs = $ogImg ? ((strpos($ogImg, 'http') === 0) ? $ogImg : $SITE . $ogImg) : $SITE . '/assets/img/lugar/costa.webp';
$n = count($CAT);
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Villa Models · Turnkey villas in Bali — Lawang Tropical Properties</title>
<meta name="description" content="Choose your villa: <?= (int) $n ?> turnkey villa models by Lawang Tropical Properties, each with its floor area, bedrooms and starting price. Same construction system across the range — only the size changes the price.">
<link rel="canonical" href="<?= lw_e($SITE) ?>/portfolio">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Lawang Tropical Properties">
<meta property="og:title" content="Villa Models — Lawang Tropical Properties">
<meta property="og:description" content="<?= (int) $n ?> turnkey villa models in Bali. Choose yours.">
<meta property="og:url" content="<?= lw_e($SITE) ?>/portfolio">
<meta property="og:image" content="<?= lw_e($ogImgAbs) ?>">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;1,300&family=Jost:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/assets/lawang-card.css?v=20260807170527">
<style>
/* ── Tipografias de marca (locales, mismos ficheros que la home y /thecollection) ── */
@font-face{font-family:'The Seasons';src:url('/assets/fonts/TheSeasons-Light.otf') format('opentype');font-weight:300;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Light.otf') format('opentype');font-weight:300;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Book.otf') format('opentype');font-weight:400;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Medium.otf') format('opentype');font-weight:500;font-style:normal;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Bold.otf') format('opentype');font-weight:600 700;font-style:normal;font-display:swap}

:root{ --tg:#485B37; --tg-d:#364429; --dl:#104C4F; --be:#42210B; --sc:#8F9B7A; --va:#2E3437; --ss:#BEB3A5; --rl:#F5F0E6; --line:#D4CCBA;
  --sans:'Neue Kabel','Jost',ui-sans-serif,system-ui,sans-serif; --serif:'The Seasons','Cormorant Garamond',Georgia,serif;
  --ease:cubic-bezier(.16,1,.3,1); --gut:clamp(20px,5vw,72px); }
*{margin:0;padding:0;box-sizing:border-box}
html{scroll-padding-top:80px}
body{font-family:var(--sans);color:var(--va);background:var(--rl) url('/assets/img/bg-ecommerce.webp') top center / 100% auto no-repeat;min-height:100vh;
  -webkit-font-smoothing:antialiased}
img{display:block;max-width:100%}
a{color:inherit;text-decoration:none}
a:focus-visible,button:focus-visible{outline:2px solid var(--tg);outline-offset:2px}
::selection{background:var(--tg);color:var(--rl)}

/* ── Barra superior: la de /thecollection (menu importado de index.html) ── */
#topbar{position:sticky;top:0;z-index:150;display:flex;align-items:center;justify-content:space-between;gap:16px;
  padding:clamp(.5rem,1.2vh,.8rem) clamp(1.4rem,4vw,3.4rem);background:rgba(247,244,239,.94);
  -webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);box-shadow:0 1px 0 rgba(190,179,165,.3)}
#logo-inner{display:flex;align-items:center;padding:6px 0}
#logo-inner .ll-dark{display:block;height:23px;width:165px;background-color:#587040;
  -webkit-mask:url('/assets/img/lawang-logo-v3-dark.webp') left center/contain no-repeat;mask:url('/assets/img/lawang-logo-v3-dark.webp') left center/contain no-repeat}
#nav{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);display:flex;align-items:center;gap:clamp(1.2rem,2.6vw,2.4rem);
  background:rgba(255,255,255,.5);border:1px solid rgba(72,91,55,.28);border-radius:40px;padding:.6rem 1.7rem}
.nav-link{position:relative;font-weight:400;font-size:.64rem;letter-spacing:.22em;color:rgba(26,22,18,.72);text-transform:uppercase;white-space:nowrap;
  transition:color .3s,letter-spacing .3s}
.nav-link::after{content:"";position:absolute;left:0;right:0;bottom:-7px;height:1.5px;background:var(--tg);transform:scaleX(0);transition:transform .32s var(--ease)}
.nav-link:hover{color:var(--tg);letter-spacing:.25em}
.nav-link:hover::after,.nav-link.active::after{transform:scaleX(1)}
.nav-link.active{color:var(--tg);font-weight:500}
#nav-actions{display:flex;align-items:center;gap:.8rem;flex:none}
.nav-cta{display:inline-flex;align-items:center;gap:.55rem;border:1px solid var(--tg);padding:8px 20px 8px 9px;border-radius:30px;
  font-weight:400;font-size:.6rem;letter-spacing:.22em;color:var(--rl);text-transform:uppercase;background:var(--tg);transition:all .35s}
.nav-cta .wa{width:20px;height:20px;border-radius:50%;background:#25D366;flex:none;display:flex;align-items:center;justify-content:center;color:#fff}
.nav-cta .wa svg{width:13px;height:13px}
.nav-cta:hover{background:#3a4a2c;border-color:#3a4a2c}
.nav-burger{display:none;width:40px;height:40px;border-radius:50%;border:1px solid rgba(72,91,55,.28);background:rgba(255,255,255,.5);cursor:pointer;
  flex-direction:column;align-items:center;justify-content:center;gap:4px}
.nav-burger span{display:block;width:16px;height:1.5px;background:var(--va);transition:transform .3s,opacity .3s}
#topbar.nav-open .nav-burger span:nth-child(1){transform:translateY(5.5px) rotate(45deg)}
#topbar.nav-open .nav-burger span:nth-child(2){opacity:0}
#topbar.nav-open .nav-burger span:nth-child(3){transform:translateY(-5.5px) rotate(-45deg)}
@media(max-width:1000px){
  .nav-burger{display:inline-flex}
  #nav{display:none;position:absolute;top:100%;left:0;right:0;transform:none;flex-direction:column;align-items:stretch;gap:0;
    border-radius:0;border:0;border-top:1px solid rgba(190,179,165,.4);background:rgba(247,244,239,.98);padding:.5rem var(--gut) 1rem}
  #topbar.nav-open #nav{display:flex}
  .nav-link{padding:14px 0;font-size:.72rem}
  .nav-link::after{bottom:8px;right:auto;width:28px}
}
@media(max-width:700px){ .nav-cta span:not(.wa){display:none} .nav-cta{padding:9px} #topbar{padding-inline:1rem} }
@media(max-width:560px){ #logo-inner .ll-dark{height:20px;width:144px} }

/* ── Portada: la de /thecollection («OWN A PIECE OF / INDONESIA») ── */
.pf-hero{text-align:center;padding:clamp(56px,9vw,110px) var(--gut) clamp(28px,4vw,48px)}
.pf-hero .l1{display:block;font-weight:400;font-size:clamp(20px,2.6vw,34px);letter-spacing:.14em;text-transform:uppercase;color:var(--va)}
.pf-hero .l2{display:block;font-family:var(--serif);font-weight:300;font-size:clamp(64px,10vw,132px);line-height:.95;letter-spacing:.01em;text-transform:uppercase;color:#1c1f17;margin-top:.1em}
.pf-hero .l3{display:block;margin-top:clamp(18px,2.4vw,30px);font-weight:400;font-size:clamp(12px,1.25vw,17px);letter-spacing:.32em;text-transform:uppercase;color:var(--ss)}
.pf-hero p{max-width:40rem;margin:clamp(18px,2vw,26px) auto 0;font-size:15px;line-height:1.6;color:#5d625a}

/* ── Rejilla de modelos: tarjetas .lw-prop de la home ── */
/* LISTA de tarjetas horizontales (23-sep, owner: «tarjetas de 2 columnas, izquierda foto y
   derecha datos, y que vayan hacia abajo»). Sustituye a la escalera. Misma tarjeta .lw-prop de la
   home, girada: foto 46% a la izquierda, datos a la derecha. Bajo 760px, foto arriba. */
.pf-grid{max-width:1120px;margin:0 auto;padding:0 var(--gut) clamp(64px,8vw,110px);display:flex;flex-direction:column;gap:22px}
.pf-grid .lw-prop > a{flex-direction:row;height:auto;min-height:340px}
.pf-grid .lw-prop-media{flex:0 0 46%;margin:8px 0 8px 8px;min-height:320px}
.pf-grid .lw-prop-body{padding:28px 34px 28px;gap:12px;justify-content:center}
.pf-grid .lw-prop-pills{justify-content:flex-start}
.pf-grid .lw-prop-title{font-size:clamp(26px,2.6vw,34px);min-height:0;-webkit-line-clamp:1}
.pf-grid .lw-prop-sub{min-height:0;-webkit-line-clamp:3}
.pf-grid .lw-prop-foot{justify-content:space-between;gap:12px}
@media(max-width:760px){
  .pf-grid .lw-prop > a{flex-direction:column}
  .pf-grid .lw-prop-media{flex:0 0 240px;min-height:240px;margin:8px 8px 0}
  .pf-grid .lw-prop-body{padding:18px 22px 22px}
  .pf-grid .lw-prop-title{-webkit-line-clamp:2}
}
.pf-grid .lw-prop-loc{display:flex;align-items:center;gap:8px}
.pf-grid .lw-prop-foot{justify-content:space-between;gap:12px}
.pf-view{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--tg);
  transition:gap .3s var(--ease)}
.lw-prop:hover .pf-view{gap:10px}
.pf-sinrender{position:absolute;inset:0;z-index:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;color:rgba(245,240,230,.85);
  font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase}
@media(prefers-reduced-motion:reduce){ .lw-prop,.lw-prop-img,.pf-view{transition:none!important} }
</style>
</head>
<body>

<header id="topbar">
  <a id="logo-inner" href="/" aria-label="Lawang — home"><span class="ll-dark" role="img" aria-label="Lawang Tropical Properties"></span></a>
  <nav id="nav" aria-label="Main">
    <a class="nav-link" href="/thecollection#land">The Land</a>
    <a class="nav-link" href="/thecollection#villas">The Villas</a>
    <a class="nav-link" href="/#expedition">The Soul</a>
    <a class="nav-link active" href="/portfolio" aria-current="page">The Portfolio</a>
  </nav>
  <div id="nav-actions">
    <a class="nav-cta" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener" aria-label="Ask us anything on WhatsApp">
      <span class="wa"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51l-.57-.01c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.41-.07-.12-.27-.2-.57-.35zM12.04 21.5a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.51-.23-.36a9.49 9.49 0 0 1-1.45-5.05c0-5.24 4.27-9.5 9.52-9.5a9.46 9.46 0 0 1 9.51 9.51c0 5.24-4.27 9.5-9.51 9.5zM20.52 3.49A11.78 11.78 0 0 0 12.04 0C5.46 0 .1 5.36.1 11.94c0 2.1.55 4.16 1.6 5.98L0 24l6.25-1.64a11.92 11.92 0 0 0 5.79 1.47c6.58 0 11.94-5.36 11.94-11.94a11.86 11.86 0 0 0-3.47-8.4z"/></svg></span>
      <span>Ask us anything</span>
    </a>
    <button class="nav-burger" id="navBurger" type="button" aria-label="Menu" aria-expanded="false" aria-controls="nav"><span></span><span></span><span></span></button>
  </div>
</header>

<main>
  <section class="pf-hero">
    <h1><span class="l1">Choose your</span><span class="l2">Villa</span><span class="l3">Turnkey villa models</span></h1>
    <p>Same construction system and roof choice across the range — only the size changes the price. Prices are for the villa build; the plot is priced separately.</p>
  </section>

  <section class="pf-grid" aria-label="Villa models">
<?php $i = 0; foreach ($CAT as $id => $v):
    // Mismas reglas que /modelo (revision previa de Marketing, 23-sep): solo los modelos que
    // /modelo/<id> sirve de verdad (lw_modelo_get: con fotos o con renders_pendientes) y el
    // «desde» con lw_modelo_precio_desde (mismo corte de 2027) — nunca una regla paralela.
    $m = lw_modelo_get($id, $MODELOS);
    if (!$m) continue;
    $sub  = $m['sub_en'] ?? ($m['sub'] ?? '');
    $href = '/' . lw_modelo_url_path($id);
    $precio = lw_precio_fmt(lw_modelo_precio_desde($m));
    $i++;
?>
    <article class="lw-prop">
      <a href="<?= lw_e($href) ?>">
        <div class="lw-prop-media ph-jungle">
<?php if (!empty($v['thumb'])): ?>
          <img class="lw-prop-img" src="<?= lw_e($v['thumb']) ?>" alt="<?= lw_e($v['villa']) ?>, turnkey villa model by Lawang" loading="lazy">
<?php else: ?>
          <span class="pf-sinrender">Renders in progress</span>
<?php endif; ?>
          <span class="lw-prop-line"><img class="lw-line-ico" src="/assets/img/cream-villas.webp" alt="" loading="lazy">Villa model</span>
        </div>
        <div class="lw-prop-body">
          <div class="lw-prop-pills"><span class="pf-pill ten"><?= (int) $v['dorm'] ?> bed</span><span class="pf-pill plan"><?= (int) $v['banos'] ?> bath</span></div>
          <span class="lw-prop-loc"><b>Turnkey</b> villa</span>
          <h2 class="lw-prop-title"><?= lw_e($v['villa']) ?></h2>
          <p class="lw-prop-sub"><?= lw_e($sub) ?></p>
          <div class="lw-prop-meta"><span class="lw-m"><b><?= (int) $v['villa_m2'] ?> m²</b> built</span><span class="lw-m"><b>+<?= (int) $v['terraza_m2'] ?> m²</b> terrace</span></div>
          <div class="lw-prop-foot">
            <span class="lw-prop-price"><?php if ($precio !== null): ?><span class="from">From</span><?= lw_e($precio) ?><?php else: ?><span class="from">Price</span>Upon request<?php endif; ?></span>
            <span class="pf-view">View model <span aria-hidden="true">→</span></span>
          </div>
        </div>
      </a>
    </article>
<?php endforeach; ?>
  </section>
</main>

<footer data-lw-pie data-cookies data-wa="<?= lw_e($WA_LINK) ?>"></footer>
<script src="/assets/lawang-pie.js?v=20260923153722"></script>
<script>
(function () {
  'use strict';
  var tb = document.getElementById('topbar'), b = document.getElementById('navBurger');
  if (b) b.addEventListener('click', function () {
    var open = tb.classList.toggle('nav-open');
    b.setAttribute('aria-expanded', open ? 'true' : 'false');
  });
  // /modelo lee utm_* y fbclid de su URL (au-landing-cfg.js): las tarjetas se los pasan para no
  // perder la atribucion de campaña en este paso intermedio.
  if (location.search) document.querySelectorAll('.pf-grid a[href^="/modelo/"]').forEach(function (a) {
    a.href = a.getAttribute('href') + location.search;
  });
  var ck = document.getElementById('lw-cookies');
  if (ck) ck.addEventListener('click', function (e) { e.preventDefault(); if (window.lwConsentReopen) window.lwConsentReopen(); });
})();
</script>
<script src="/assets/consent.js?v=20260908111654" defer></script>
</body>
</html>
