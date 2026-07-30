<?php
/**
 * Landing de modelo de villa — /modelo/<id> (regla de reescritura en .htaccess).
 *
 * Página de destino de la pauta de Meta hacia compradores españoles. No es una ficha de
 * catálogo: su único trabajo es conseguir una llamada. De ahí las tres decisiones que
 * mandan sobre el resto:
 *
 *  1. FORMULARIO EN EL PRIMER PANTALLAZO. En tráfico de pago la conversión no puede estar
 *     a tres scrolls; el hero es split, copy a la izquierda y formulario a la derecha.
 *  2. SIN SALIDAS. Nada de menú ni enlaces al catálogo: quien llega de un anuncio o
 *     convierte o se va. Los únicos enlaces son los legales, que son obligatorios.
 *  3. UN SOLO CTA, UNA SOLA ETIQUETA: "Reservar mi llamada", igual en los cuatro sitios
 *     donde aparece. Dos etiquetas para la misma intención dividen la atención.
 *
 * TIPOGRAFÍA: display en Cormorant Garamond y NO en "The Seasons" de la marca, aunque el
 * resto del sitio use esa. Los OTF de The Seasons del proyecto son DEMO y corrompen el
 * glifo `4`, entre otros. Una página cuyo trabajo es enseñar un precio no puede usar una
 * fuente que rompe dígitos. El cuerpo sí es la sans de marca (Neue Kabel, ya autoalojada),
 * así que solo queda una petición externa de fuente.
 *
 * TEMA: claro y bloqueado, como el resto del sitio. La banda verde oscura del CTA final es
 * el único bloque de color, deliberado y una sola vez.
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
$hero    = $m['imgs'][0];
$galeria = array_slice($m['imgs'], 1);
$nombre  = $m['nombre'];
$dorm    = (int) $m['dormitorios'];
$dormTxt = $dorm . ' ' . ($dorm === 1 ? 'dormitorio' : 'dormitorios');
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
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;1,300&display=swap" rel="stylesheet">
<style>
/* Neue Kabel: la sans de la marca, ya autoalojada para el resto del sitio. */
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Light.otf') format('opentype');font-weight:300;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Book.otf') format('opentype');font-weight:400;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Medium.otf') format('opentype');font-weight:500;font-display:swap}

:root{
  --tg:#485B37; --tg-dark:#374729; --tg-light:#EDF1E8;
  --dl:#123F35; --sc:#8F9B7A; --sc-ink:#586646;
  --ink:#2A2F31; --ink-2:#5B6461; --bone:#F5F0E6; --bone-2:#EAE3D4; --line:#D9D2C2;
  --surface:#FDFAF5;
  --serif:"Cormorant Garamond",Georgia,serif;
  --sans:"Neue Kabel",ui-sans-serif,system-ui,sans-serif;
  --wrap:1280px; --gut:clamp(20px,5vw,64px);
  --ease:cubic-bezier(.16,1,.3,1);
  /* Radios: una sola regla para toda la página. Botones píldora, superficies 14 px,
     campos 10 px. Mezclar radios sin regla es lo que hace que una página parezca
     ensamblada por piezas sueltas. */
  --r-surface:14px; --r-field:10px;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bone);color:var(--ink);font-family:var(--sans);
  font-size:16.5px;line-height:1.6;font-weight:300;-webkit-font-smoothing:antialiased}
img{max-width:100%;display:block}
a{color:inherit}
h1,h2,h3{font-family:var(--serif);font-weight:300;letter-spacing:-.01em;margin:0}
.wrap{max-width:var(--wrap);margin-inline:auto;padding-inline:var(--gut)}
.eyebrow{font-size:11px;letter-spacing:.22em;text-transform:uppercase;font-weight:500;
  color:var(--sc-ink);margin:0}
section{padding-block:clamp(64px,9vw,132px)}
.sec-h{font-size:clamp(30px,4.4vw,54px);line-height:1.06}
.lede{max-width:56ch;color:var(--ink-2);font-size:17px;margin:1.1em 0 0}

/* ── Barra superior: solo la marca. Un menú aquí solo sirve para que se vayan. ── */
.top{position:absolute;inset:0 0 auto;z-index:30;height:72px;display:flex;align-items:center}
.top .wrap{display:flex;align-items:center;justify-content:space-between;width:100%}
.top__mark{font-family:var(--serif);font-size:22px;letter-spacing:.16em;
  text-transform:uppercase;color:var(--bone)}
.top__meta{font-size:11.5px;letter-spacing:.16em;text-transform:uppercase;
  color:rgba(245,240,230,.72)}

/* ── Hero: split. Copy a la izquierda, conversión a la derecha. ─────────────── */
.hero{position:relative;min-height:100svh;display:flex;align-items:center;
  padding-top:104px;padding-bottom:clamp(40px,6vw,72px);overflow:hidden}
.hero__bg{position:absolute;inset:0}
.hero__bg img{width:100%;height:100%;object-fit:cover}
/* Dos tramos oscuros: uno arriba para la marca y otro que baja por la izquierda,
   que es donde cae el texto. Sin el segundo, la copy se lee a trompicones sobre
   la piscina. */
.hero__bg::after{content:"";position:absolute;inset:0;background:
  linear-gradient(180deg,rgba(28,32,30,.58) 0%,rgba(28,32,30,.12) 26%,rgba(28,32,30,.30) 68%,rgba(28,32,30,.72) 100%),
  linear-gradient(90deg,rgba(28,32,30,.72) 0%,rgba(28,32,30,.34) 46%,rgba(28,32,30,.05) 78%)}
.hero__grid{position:relative;z-index:2;display:grid;gap:clamp(32px,4vw,64px);
  grid-template-columns:1.02fr .98fr;align-items:center;width:100%}
.hero__copy{color:var(--bone)}
.hero__copy .eyebrow{color:rgba(245,240,230,.78)}
/* El titular cabe en DOS líneas o el hero deja de leerse de un vistazo. Con el
   formulario al lado la columna es estrecha, así que el tope es 62px y no 80. */
.hero h1{font-size:clamp(38px,4.8vw,62px);line-height:1.06;margin:.24em 0 .3em}
.hero h1 i{font-style:italic;color:#C9D2BC;line-height:1.1;padding-bottom:.06em}
.hero__sub{max-width:30ch;font-size:clamp(15.5px,1.4vw,18px);color:rgba(245,240,230,.94);
  margin:0;text-shadow:0 1px 16px rgba(24,28,26,.5)}
.hero__facts{display:flex;flex-wrap:wrap;gap:0;margin-top:clamp(26px,3vw,40px)}
.hero__facts span{font-size:12.5px;letter-spacing:.06em;color:rgba(245,240,230,.9);
  padding:0 16px;border-left:1px solid rgba(245,240,230,.3)}
.hero__facts span:first-child{padding-left:0;border-left:0}

/* ── Formulario ─────────────────────────────────────────────────────────────── */
.form{background:var(--surface);border-radius:var(--r-surface);
  padding:clamp(24px,2.6vw,34px);box-shadow:0 30px 70px -34px rgba(24,32,26,.6)}
.form__h{font-size:27px;line-height:1.15;margin:0 0 .35em}
.form__lede{font-size:14px;color:var(--ink-2);margin:0 0 22px}
.field{margin-bottom:15px}
.field label{display:block;font-size:11px;letter-spacing:.14em;text-transform:uppercase;
  color:#5F6763;font-weight:500;margin-bottom:6px}
.field input{width:100%;font-family:inherit;font-size:15.5px;font-weight:300;color:var(--ink);
  background:#fff;border:1px solid var(--line);border-radius:var(--r-field);padding:12px 14px;
  transition:border-color .25s var(--ease),box-shadow .25s var(--ease)}
.field input:focus{outline:none;border-color:var(--tg);box-shadow:0 0 0 3px rgba(72,91,55,.16)}
.field input[aria-invalid="true"]{border-color:#9C3B2E;box-shadow:0 0 0 3px rgba(156,59,46,.13)}
.field .err{display:none;font-size:12.5px;color:#8E3527;margin-top:5px}
.field input[aria-invalid="true"] ~ .err{display:block}
.consent{display:flex;gap:10px;align-items:flex-start;font-size:13px;color:var(--ink-2);
  line-height:1.5;margin:18px 0 20px}
.consent input{margin-top:3px;accent-color:var(--tg);flex:0 0 auto;width:16px;height:16px}
.consent a{color:var(--tg)}
.hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.form__msg{margin:12px 0 0;font-size:13.5px;color:var(--ink-2);min-height:1.1em}
.form__msg--err{color:#8E3527}
.form__ok{font-family:var(--serif);font-size:26px;margin:0 0 .4em}

.btn{display:inline-block;border:1px solid var(--tg);background:var(--tg);color:#FBF8F2;
  border-radius:999px;padding:15px 32px;font-family:inherit;font-size:12.5px;font-weight:500;
  letter-spacing:.14em;text-transform:uppercase;text-decoration:none;cursor:pointer;
  transition:transform .3s var(--ease),background .3s var(--ease),box-shadow .3s var(--ease)}
.btn:hover{background:var(--tg-dark);border-color:var(--tg-dark);transform:translateY(-2px);
  box-shadow:0 14px 30px -16px rgba(55,71,41,.8)}
.btn:active{transform:translateY(0) scale(.985)}
.btn:disabled{opacity:.55;cursor:default;transform:none;box-shadow:none}
.btn--wide{width:100%}
.btn--onDark{background:var(--bone);border-color:var(--bone);color:var(--ink)}
.btn--onDark:hover{background:#fff;border-color:#fff}

/* ── Datos duros: sin tarjetas, filetes verticales ──────────────────────────── */
.facts{border-top:1px solid var(--line);border-bottom:1px solid var(--line);
  padding-block:clamp(28px,3.4vw,44px)}
/* minmax 150 y no 190: con 190 el móvil solo cabía una columna y los cuatro datos
   ocupaban una pantalla entera de scroll para decir cuatro palabras. */
.facts .wrap{display:grid;gap:clamp(20px,3vw,40px);
  grid-template-columns:repeat(auto-fit,minmax(150px,1fr))}
.fact__k{font-family:var(--serif);font-size:clamp(26px,2.6vw,34px);line-height:1.1}
.fact__v{font-size:13px;color:var(--ink-2);margin:.5em 0 0}

/* ── Acabados: imagen grande + lista, no tres tarjetas iguales ──────────────── */
.roofs{display:grid;gap:clamp(28px,4vw,64px);grid-template-columns:.9fr 1.1fr;
  align-items:center}
.roofs__img{border-radius:var(--r-surface);overflow:hidden;background:var(--bone-2)}
.roofs__img img{aspect-ratio:4/5;object-fit:cover;width:100%}
.roof{padding:22px 0;border-bottom:1px solid var(--line)}
.roof:last-child{border-bottom:0;padding-bottom:0}
.roof h3{font-size:25px;margin:0 0 .18em}
.roof p{margin:0;font-size:14.5px;color:var(--ink-2);max-width:46ch}
.note{font-size:13.5px;color:var(--ink-2);margin-top:26px;padding-left:16px;
  border-left:2px solid var(--sc-ink);max-width:52ch}

/* ── Galería: bento con tantas celdas como fotos hay ────────────────────────── */
.gal{display:grid;gap:12px;grid-template-columns:repeat(6,1fr);
  margin-top:clamp(30px,3.4vw,48px)}
.gal figure{margin:0;overflow:hidden;border-radius:var(--r-surface);background:var(--bone-2)}
.gal img{width:100%;height:100%;object-fit:cover;transition:transform 1.2s var(--ease)}
.gal figure:hover img{transform:scale(1.04)}
/* Cinco renders, cinco celdas, tres filas completas (4+2 · 3+3 · 6). Una celda vacía al
   final delata que la retícula se copió sin contar las fotos que hay. */
.gal figure:nth-child(1){grid-column:span 4;aspect-ratio:16/10}
.gal figure:nth-child(2){grid-column:span 2;aspect-ratio:3/4}
.gal figure:nth-child(3){grid-column:span 3;aspect-ratio:3/2}
.gal figure:nth-child(4){grid-column:span 3;aspect-ratio:3/2}
.gal figure:nth-child(5){grid-column:span 6;aspect-ratio:21/9}
.gal figure:nth-child(n+6){grid-column:span 3;aspect-ratio:3/2}

/* ── Alcance de obra ────────────────────────────────────────────────────────── */
.scope{background:var(--bone-2)}
.scope__grid{display:grid;gap:clamp(28px,4vw,72px);grid-template-columns:1fr 1fr;
  margin-top:clamp(30px,3.4vw,46px)}
.list{list-style:none;margin:0;padding:0;columns:2;column-gap:32px}
.list--out{columns:1}
.list li{position:relative;padding-left:22px;margin-bottom:11px;font-size:15px;
  color:#4B534F;break-inside:avoid}
.list li::before{position:absolute;left:0;top:0;color:var(--tg)}
.list--in li::before{content:"+"}
.list--out li::before{content:"\2013";color:#A9998A}
.scope h3{font-size:22px;margin:0 0 .8em}

/* ── El sitio: fotografía real, a sangre ────────────────────────────────────── */
.place{position:relative;padding:0}
.place__band{display:grid;grid-template-columns:1.4fr 1fr;gap:12px}
.place__band img{width:100%;height:100%;object-fit:cover;aspect-ratio:3/2}
.place__copy{padding-block:clamp(40px,5vw,72px)}

/* ── Cómo funciona ──────────────────────────────────────────────────────────── */
.steps{display:grid;gap:clamp(24px,3vw,48px);grid-template-columns:repeat(3,1fr);
  margin-top:clamp(30px,3.4vw,48px)}
.step h3{font-size:22px;margin:.45em 0 .3em}
.step p{margin:0;font-size:14.5px;color:var(--ink-2)}
/* Después de `.step p` a propósito: con la misma especificidad gana la última regla, y
   antes el número salía a 14,5 px. */
.step p.step__n{font-family:var(--serif);font-size:42px;line-height:1;color:#74815F}

/* ── Preguntas ──────────────────────────────────────────────────────────────── */
.faq{max-width:820px;margin-top:clamp(26px,3vw,40px)}
.faq details{border-bottom:1px solid var(--line)}
.faq summary{cursor:pointer;list-style:none;padding:20px 40px 20px 0;position:relative;
  font-size:18px;font-family:var(--serif);transition:color .25s var(--ease)}
.faq summary::-webkit-details-marker{display:none}
.faq summary:hover{color:var(--tg)}
.faq summary::after{content:"+";position:absolute;right:6px;top:19px;font-size:20px;
  color:var(--sc-ink);transition:transform .3s var(--ease)}
.faq details[open] summary::after{transform:rotate(45deg)}
.faq p{margin:0 0 22px;font-size:15px;color:var(--ink-2);max-width:64ch}

/* ── Cierre: el único bloque de color de la página ──────────────────────────── */
.close{background:var(--dl);color:var(--bone);text-align:center}
.close h2{font-size:clamp(30px,4.4vw,52px);line-height:1.08}
.close p{color:rgba(245,240,230,.8);max-width:46ch;margin:1.1em auto 0}
.close .btn{margin-top:clamp(26px,3vw,40px)}

footer{padding-block:34px;font-size:12.5px;color:#5F6763}
footer .wrap{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap}
footer a{text-decoration:none;border-bottom:1px solid transparent}
footer a:hover{border-bottom-color:currentColor}

/* ── Barra fija de móvil: en el teléfono el formulario queda lejos ──────────── */
.sticky{position:fixed;left:0;right:0;bottom:0;z-index:40;display:none;
  padding:10px 16px calc(10px + env(safe-area-inset-bottom));
  background:rgba(245,240,230,.94);backdrop-filter:blur(12px);
  border-top:1px solid var(--line);transform:translateY(110%);
  transition:transform .35s var(--ease)}
.sticky.on{transform:translateY(0)}
.sticky .btn{width:100%;text-align:center}

/* ── Aparición al entrar en pantalla. IntersectionObserver, nunca scroll listener ──
   El estado oculto cuelga de `.js`, que pone un script en el <head>. Si el JS falla o
   está bloqueado, el contenido se ve: una landing que esconde su copy con CSS y la
   enseña con JS es una landing en blanco el día que el JS no carga. */
.js .rv{opacity:0;transform:translateY(22px);
  transition:opacity .7s var(--ease),transform .7s var(--ease)}
.js .rv.in{opacity:1;transform:none}

@media(max-width:960px){
  .hero{min-height:auto;padding-top:96px}
  .hero__grid{grid-template-columns:1fr;gap:30px}
  .hero__sub{max-width:44ch}
  .roofs,.scope__grid,.steps,.place__band{grid-template-columns:1fr}
  .roofs__img img{aspect-ratio:16/10}
  .list{columns:1}
  .gal{grid-template-columns:1fr}
  .gal figure{grid-column:span 1 !important;aspect-ratio:16/10 !important}
  .sticky{display:block}
  /* El aviso de cookies vive en consent.js con bottom:20px y en móvil se sentaba justo
     encima de la barra fija: dos cosas peleando por el mismo sitio y el CTA tapado. */
  #lw-consent-bar{bottom:86px}
}
@media(prefers-reduced-motion:reduce){
  html{scroll-behavior:auto}
  .js .rv{opacity:1;transform:none;transition:none}
  .btn,.gal img,.sticky{transition:none}
}
</style>
<script>document.documentElement.className += ' js';</script>
</head>
<body>

<header class="top">
  <div class="wrap">
    <span class="top__mark">Lawang</span>
    <span class="top__meta">Bali, Indonesia</span>
  </div>
</header>

<section class="hero">
  <div class="hero__bg">
    <img src="<?= lw_e($hero) ?>" alt="Villa <?= lw_e($nombre) ?> de Lawang Estate, exterior con piscina" fetchpriority="high">
  </div>
  <div class="wrap hero__grid">
    <div class="hero__copy">
      <p class="eyebrow">Modelo <?= lw_e($nombre) ?> · Lawang Estate</p>
      <h1>Villa llave en mano<br>en la costa de <i>Bali</i>.</h1>
      <p class="hero__sub"><?= lw_e($m['sub']) ?></p>
      <div class="hero__facts">
        <span><?= lw_e(ucfirst($dormTxt)) ?></span>
        <span>Piscina privada</span>
        <span>Parcela a elegir</span>
      </div>
    </div>

    <form class="form" id="lw-form" novalidate>
      <h2 class="form__h">Reserva tu llamada</h2>
      <p class="form__lede">Te damos el presupuesto cerrado del acabado que te interese y
        las parcelas disponibles donde puede construirse.</p>

      <div class="field">
        <label for="lw-nombre">Nombre y apellidos</label>
        <input type="text" id="lw-nombre" name="name" autocomplete="name" required maxlength="120">
        <span class="err">Dinos cómo te llamas.</span>
      </div>
      <div class="field">
        <label for="lw-email">Email</label>
        <input type="email" id="lw-email" name="email" autocomplete="email" required maxlength="180">
        <span class="err">Revisa el email: no parece válido.</span>
      </div>
      <div class="field">
        <label for="lw-tel">Teléfono</label>
        <input type="tel" id="lw-tel" name="phone" autocomplete="tel" required maxlength="40">
        <span class="err">Necesitamos un teléfono para llamarte.</span>
      </div>

      <!-- Trampa de bots: un humano nunca la ve, así que si viene rellena, es un bot. -->
      <div class="hp" aria-hidden="true"><label for="lw-web">No rellenar</label>
        <input type="text" id="lw-web" name="website" tabindex="-1" autocomplete="off"></div>

      <label class="consent" for="lw-consent">
        <input type="checkbox" id="lw-consent" name="consent" value="1" required>
        <span>He leído y acepto la <a href="/legal#privacy" target="_blank" rel="noopener">Política de Privacidad</a>
          y que Lawang Estate me contacte sobre este modelo.</span>
      </label>

      <button class="btn btn--wide" type="submit" id="lw-submit">Reservar mi llamada</button>
      <p class="form__msg" id="lw-msg" role="status" aria-live="polite"></p>
    </form>
  </div>
</section>

<div class="facts">
  <div class="wrap">
    <div class="rv"><p class="fact__k"><?= $dorm ?></p><p class="fact__v"><?= $dorm === 1 ? 'Dormitorio en suite' : 'Dormitorios' ?></p></div>
    <div class="rv"><p class="fact__k">3</p><p class="fact__v">Acabados de cubierta a elegir</p></div>
    <div class="rv"><p class="fact__k">Overflow</p><p class="fact__v">Piscina en piedra sukabumi</p></div>
    <div class="rv"><p class="fact__k">Llave en mano</p><p class="fact__v">Obra, instalaciones y acometida</p></div>
  </div>
</div>

<?php if ($m['acabados']): ?>
<section>
  <div class="wrap roofs">
    <div class="roofs__img rv">
      <!-- Recorte del render de exterior: es la única imagen donde se ve la cubierta, que
           es de lo que habla la sección. Poner aquí un interior era ilustrar otra cosa. -->
      <img src="/assets/img/modelo/dali-cubierta.jpg" alt="Cubierta de alang-alang de la villa <?= lw_e($nombre) ?>" loading="lazy" width="1100" height="1375">
    </div>
    <div>
      <h2 class="sec-h">La cubierta decide<br>el presupuesto.</h2>
      <p class="lede">El resto de la villa no cambia. Se elige antes de cerrar números,
        porque es lo único que mueve el precio final de la obra.</p>
      <div style="margin-top:clamp(24px,3vw,40px)">
        <?php foreach ($m['acabados'] as $a): ?>
        <div class="roof rv">
          <h3><?= lw_e($a['n']) ?></h3>
          <p><?= lw_e($a['d']) ?></p>
        </div>
        <?php endforeach; ?>
      </div>
    </div>
  </div>
</section>
<?php endif; ?>

<?php if ($galeria): ?>
<section style="padding-top:0">
  <div class="wrap">
    <h2 class="sec-h rv"><?= lw_e($nombre) ?>, por dentro.</h2>
    <div class="gal">
      <?php foreach ($galeria as $src): ?>
      <figure class="rv"><img src="<?= lw_e($src) ?>" alt="Villa <?= lw_e($nombre) ?>" loading="lazy"></figure>
      <?php endforeach; ?>
    </div>
  </div>
</section>
<?php endif; ?>

<?php if ($m['alcance']): ?>
<section class="scope">
  <div class="wrap">
    <h2 class="sec-h rv">Qué entra en la obra<br>y qué no.</h2>
    <p class="lede rv">Tal cual figura en el pliego del contratista. La parcela y los gastos
      de compraventa van aparte y se detallan en la propuesta.</p>
    <div class="scope__grid">
      <div class="rv">
        <h3>Incluido</h3>
        <ul class="list list--in">
          <?php foreach ($m['alcance']['incluido'] as $li): ?><li><?= lw_e($li) ?></li><?php endforeach; ?>
        </ul>
      </div>
      <div class="rv">
        <h3>No incluido</h3>
        <ul class="list list--out">
          <?php foreach ($m['alcance']['no_incluido'] as $li): ?><li><?= lw_e($li) ?></li><?php endforeach; ?>
        </ul>
      </div>
    </div>
  </div>
</section>
<?php endif; ?>

<section class="place">
  <div class="place__band rv">
    <img src="/assets/img/lugar/costa.jpg" alt="Costa oeste de Bali al atardecer, vista aérea" loading="lazy">
    <img src="/assets/img/lugar/rio.jpg" alt="Valle y río junto a la costa, vista aérea" loading="lazy">
  </div>
  <div class="wrap place__copy rv">
    <h2 class="sec-h">La costa, no el render.</h2>
    <p class="lede">Estas dos fotografías son de la zona, tomadas con dron. Playa de arena
      volcánica, arrozales y río, en la costa oeste de Bali. En la llamada te decimos
      exactamente qué parcelas quedan y cómo se llega a cada una.</p>
  </div>
</section>

<section style="background:var(--bone-2)">
  <div class="wrap">
    <h2 class="sec-h rv">Cómo se compra.</h2>
    <div class="steps">
      <div class="step rv">
        <p class="step__n">01</p>
        <h3>Llamada</h3>
        <p>Media hora para ver qué parcela encaja, con qué presupuesto y en qué plazos.</p>
      </div>
      <div class="step rv">
        <p class="step__n">02</p>
        <h3>Presupuesto y parcela</h3>
        <p>Precio cerrado del acabado elegido, parcela concreta y calendario de pagos.</p>
      </div>
      <div class="step rv">
        <p class="step__n">03</p>
        <h3>Reserva y obra</h3>
        <p>Contrato de reserva, después el PPJB de compraventa, y arranca la construcción.</p>
      </div>
    </div>
  </div>
</section>

<section>
  <div class="wrap">
    <p class="eyebrow rv">Antes de la llamada</p>
    <h2 class="sec-h rv">Lo que suelen preguntar.</h2>
    <div class="faq rv">
      <details>
        <summary>¿Qué incluye el precio?</summary>
        <p>La obra completa según el pliego del contratista, con el acabado de cubierta que
          elijas. La parcela y los gastos de compraventa (impuestos, notaría y licencias) se
          presupuestan aparte y se detallan por escrito antes de firmar nada.</p>
      </details>
      <details>
        <summary>¿Puedo elegir dónde se construye?</summary>
        <p>Sí. El modelo es el mismo y se levanta sobre la parcela que elijas del catálogo.
          Cambian la vista, la orientación y el precio del terreno. Hay parcelas en freehold
          y en leasehold, y no todas admiten cualquier modelo: eso se concreta en la llamada.</p>
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

<section class="close">
  <div class="wrap">
    <h2>Hablamos y te pasamos números.</h2>
    <p>Una llamada para ver parcela, presupuesto y plazos. Sin compromiso.</p>
    <p><a class="btn btn--onDark" href="#lw-form" data-cta="cierre">Reservar mi llamada</a></p>
  </div>
</section>

<footer>
  <div class="wrap">
    <span>Lawang Estate · PT Tepi Sun Gai · Bali, Indonesia</span>
    <span><a href="/legal">Aviso legal y privacidad</a> ·
      <!-- Retirar el consentimiento tiene que ser tan facil como darlo (RGPD art. 7.3). -->
      <a href="#" onclick="window.lwConsentReopen&&window.lwConsentReopen();return false">Preferencias de cookies</a></span>
  </div>
</footer>

<div class="sticky" id="lw-sticky">
  <a class="btn" href="#lw-form">Reservar mi llamada</a>
</div>

<script src="/assets/consent.js?v=20260730" defer></script>
<script>
(function () {
  'use strict';
  var MODELO = <?= json_encode($m['id']) ?>;
  var VALUE  = <?= $m['precio_desde_eur'] === null ? 'null' : (float) $m['precio_desde_eur'] ?>;

  // ── Píxel ──────────────────────────────────────────────────────────────────
  // ViewContent es la semilla del público BOFU. Se manda aunque no haya precio cerrado;
  // `value` solo viaja cuando el número es real, porque Meta puja por ese importe.
  function track(ev, extra) {
    if (typeof window.lwTrack !== 'function') return;   // sin consentimiento no se manda nada
    var p = {content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO};
    if (VALUE !== null) { p.value = VALUE; p.currency = 'EUR'; }
    for (var k in (extra || {})) p[k] = extra[k];
    window.lwTrack(ev, p);
  }
  // consent.js va con defer: si aún no ha definido lwTrack, se reintenta al cargar todo.
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  // ── Aparición al entrar en pantalla ───────────────────────────────────────
  // IntersectionObserver y no un listener de scroll: el listener corre en cada frame.
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var revs = document.querySelectorAll('.rv');
  if (reduce || !('IntersectionObserver' in window)) {
    for (var i = 0; i < revs.length; i++) revs[i].classList.add('in');
  } else {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (!e.isIntersecting) return;
        // Escalonado por posición dentro del grupo: el orden de lectura se nota.
        var sibs = Array.prototype.slice.call(e.target.parentNode.children);
        e.target.style.transitionDelay = (Math.min(sibs.indexOf(e.target), 5) * 70) + 'ms';
        e.target.classList.add('in');
        io.unobserve(e.target);
      });
    }, {threshold: 0.18, rootMargin: '0px 0px -8% 0px'});
    for (var j = 0; j < revs.length; j++) io.observe(revs[j]);
  }

  // ── Barra fija de móvil: aparece cuando el formulario ya no se ve ─────────
  var form = document.getElementById('lw-form');
  var sticky = document.getElementById('lw-sticky');
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (es) {
      sticky.classList.toggle('on', !es[0].isIntersecting);
    }, {threshold: 0.25}).observe(form);
  }

  // ── Envío ─────────────────────────────────────────────────────────────────
  var msg = document.getElementById('lw-msg');
  var btn = document.getElementById('lw-submit');
  var campos = ['lw-nombre', 'lw-email', 'lw-tel'];

  function marca(el, malo) { el.setAttribute('aria-invalid', malo ? 'true' : 'false'); }
  campos.forEach(function (id) {
    var el = document.getElementById(id);
    el.addEventListener('input', function () { if (el.getAttribute('aria-invalid') === 'true') marca(el, !el.checkValidity()); });
  });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    msg.className = 'form__msg';

    var malo = null;
    campos.forEach(function (id) {
      var el = document.getElementById(id);
      var ok = el.checkValidity() && el.value.trim() !== '';
      marca(el, !ok);
      if (!ok && !malo) malo = el;
    });
    var cons = document.getElementById('lw-consent');
    if (!cons.checked) {
      msg.className = 'form__msg form__msg--err';
      msg.textContent = 'Falta aceptar la política de privacidad.';
      if (!malo) { cons.focus(); return; }
    }
    if (malo) { malo.focus(); return; }
    if (!cons.checked) return;

    btn.disabled = true;
    var etiqueta = btn.textContent;
    btn.textContent = 'Enviando';
    msg.textContent = '';

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
        var h = document.createElement('h2'); h.className = 'form__ok';
        h.textContent = 'Gracias, ' + nombre + '.';
        var p = document.createElement('p'); p.className = 'form__lede';
        p.textContent = 'Hemos recibido tu solicitud. Te contactamos para agendar la llamada.';
        form.textContent = '';
        form.appendChild(h); form.appendChild(p);
        sticky.classList.remove('on');
      })
      .catch(function (err) {
        btn.disabled = false;
        btn.textContent = etiqueta;
        msg.className = 'form__msg form__msg--err';
        msg.textContent = String(err.message) === 'too_many'
          ? 'Has enviado varias solicitudes seguidas. Inténtalo dentro de un rato.'
          : 'No hemos podido enviar la solicitud. Escríbenos a sales@lawangproperties.com.';
      });
  });
})();
</script>
</body>
</html>
