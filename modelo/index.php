<?php
/**
 * Landing de modelo de villa — /modelo/<id> (ver la regla de reescritura en .htaccess).
 *
 * Una plantilla para los 5 modelos. Los datos viven en modelos.php y las imágenes se
 * leen de assets/img/buildings/<id>/web/, así que publicar Dune el día que haya renders
 * no toca este fichero.
 *
 * TIPOGRAFÍA: Cormorant Garamond a propósito, NO "The Seasons" de la marca. Los OTF de
 * The Seasons que tiene el proyecto son DEMO y corrompen el glifo `4`. Una página cuyo
 * trabajo es enseñar un precio no puede usar una fuente que rompe dígitos.
 *
 * PRECIOS: no hay ninguno inventado. Sin precio cerrado sale el chip "pendiente" y la
 * página se marca `noindex` sola, para no indexar una ficha de producto sin producto.
 */
require __DIR__ . '/lib.php';
$MODELOS = require __DIR__ . '/modelos.php';

$m = lw_modelo_get(isset($_GET['m']) ? $_GET['m'] : '', $MODELOS);
if (!$m) {
    // Modelo inexistente o todavía sin renders: al catálogo, nunca a una landing vacía.
    header('Location: /thecollection', true, 302);
    exit;
}

$otros   = lw_modelos_publicables($MODELOS, $m['id']);
$precio  = lw_precio_fmt($m['precio_desde_eur']);
$hero    = $m['imgs'][0];
$galeria = array_slice($m['imgs'], 1);
$nombre  = $m['nombre'];
?><!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($nombre) ?> · Villa llave en mano en Bali — Lawang Estate</title>
<meta name="description" content="<?= lw_e($nombre) ?>: villa de obra nueva de <?= (int) $m['dormitorios'] ?> <?= $m['dormitorios'] == 1 ? 'dormitorio' : 'dormitorios' ?> en Bali, llave en mano sobre la parcela que elijas.">
<?php if (!$precio): ?>
<meta name="robots" content="noindex, nofollow"><!-- sin precio cerrado no se indexa -->
<?php endif; ?>
<link rel="canonical" href="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="<?= lw_e($nombre) ?> · Villa llave en mano en Bali">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($hero) ?>">
<meta property="og:type" content="website">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&family=Jost:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
:root{
  --tg:#485B37; --tg-dark:#364429; --tg-light:#EDF1E8;
  --dl:#104C4F; --sc:#8F9B7A;
  --ink:#2E3437; --bone:#F5F0E6; --bone-2:#EBE4D6; --line:#D4CCBA;
  --surface:#FDFAF5;
  --serif:"Cormorant Garamond",Georgia,serif;
  --sans:"Jost",ui-sans-serif,system-ui,sans-serif;
  --wrap:1240px; --gut:clamp(20px,5vw,72px);
  --ease:cubic-bezier(.16,1,.3,1);
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bone);color:var(--ink);font-family:var(--sans);
  font-size:16px;line-height:1.65;-webkit-font-smoothing:antialiased}
img{max-width:100%;display:block}
a{color:inherit}
.wrap{max-width:var(--wrap);margin-inline:auto;padding-inline:var(--gut)}
.eyebrow{font-size:11px;letter-spacing:.24em;text-transform:uppercase;
  font-weight:500;color:var(--sc)}

/* Nav */
.nav{position:fixed;inset:0 0 auto;z-index:50;height:64px;display:flex;
  align-items:center;backdrop-filter:blur(14px);
  background:rgba(245,240,230,.82);border-bottom:1px solid var(--line)}
.nav .wrap{display:flex;align-items:center;justify-content:space-between;width:100%}
.nav__mark{font-family:var(--serif);font-size:21px;letter-spacing:.14em;
  text-transform:uppercase;text-decoration:none}
.nav__back{font-size:12px;letter-spacing:.14em;text-transform:uppercase;
  text-decoration:none;color:var(--sc);transition:color .3s var(--ease)}
.nav__back:hover{color:var(--tg)}

/* Hero */
.hero{position:relative;min-height:100svh;display:flex;align-items:flex-end;
  padding-top:96px;                                 /* el h1 no se cuela bajo la nav */
  padding-bottom:clamp(48px,7vw,96px);overflow:hidden}
.hero__bg{position:absolute;inset:0}
.hero__bg img{width:100%;height:100%;object-fit:cover}
/* El render es claro justo donde va la copy: sin este segundo tramo oscuro a media
   altura el texto se lee a trompicones sobre la piscina. */
.hero__bg::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,
  rgba(46,52,55,.50) 0%, rgba(46,52,55,.10) 28%,
  rgba(46,52,55,.58) 64%, rgba(46,52,55,.94) 100%)}
.hero__in{position:relative;z-index:2;color:var(--bone);width:100%}
.hero .eyebrow{color:rgba(245,240,230,.78)}
.hero h1{font-family:var(--serif);font-weight:300;margin:.18em 0 .1em;
  font-size:clamp(56px,12vw,148px);line-height:.9;letter-spacing:-.02em}
.hero h1 em{font-style:italic;color:var(--sc)}
.hero__sub{max-width:46ch;font-size:clamp(15px,1.5vw,18px);
  color:rgba(245,240,230,.92);font-weight:300;
  text-shadow:0 1px 18px rgba(30,34,32,.55)}
.hero__foot{display:flex;flex-wrap:wrap;gap:32px;
  align-items:flex-end;justify-content:space-between;
  margin-top:clamp(28px,4vw,52px)}
.hero__ctas{display:flex;gap:14px;flex-wrap:wrap}

.price__label{font-size:11px;letter-spacing:.2em;text-transform:uppercase;
  color:rgba(245,240,230,.6);margin-bottom:6px}
.price__val{font-family:var(--serif);font-size:clamp(30px,4.6vw,52px);
  line-height:1;font-weight:300;margin:0}
/* El hueco del precio es visible A PROPÓSITO: no es un placeholder olvidado. */
.price__pending{display:inline-flex;align-items:center;gap:9px;
  border:1px dashed rgba(245,240,230,.5);border-radius:999px;padding:9px 18px;
  font-family:var(--sans);font-size:12px;letter-spacing:.14em;
  text-transform:uppercase;color:rgba(245,240,230,.9)}
.price__pending::before{content:"";width:7px;height:7px;border-radius:50%;
  background:#C9A227;box-shadow:0 0 0 4px rgba(201,162,39,.22)}

.btn{display:inline-block;border:1px solid;border-radius:999px;
  padding:15px 34px;font-size:12px;letter-spacing:.16em;text-transform:uppercase;
  font-weight:500;text-decoration:none;cursor:pointer;font-family:inherit;
  transition:transform .35s var(--ease),background .35s var(--ease),color .35s var(--ease)}
.btn--solid{background:var(--bone);border-color:var(--bone);color:var(--ink)}
.btn--solid:hover{transform:translateY(-2px);background:#fff}
.btn--ghost{background:none;border-color:rgba(245,240,230,.45);color:var(--bone)}
.btn--ghost:hover{border-color:var(--bone);transform:translateY(-2px)}
.btn--clay{background:var(--tg);border-color:var(--tg);color:var(--bone)}
.btn--clay:hover{background:var(--tg-dark);border-color:var(--tg-dark);transform:translateY(-2px)}
.btn[disabled]{opacity:.55;cursor:default;transform:none}

/* Secciones */
section{padding-block:clamp(72px,10vw,148px)}
.sec-h{font-family:var(--serif);font-weight:300;font-size:clamp(32px,5vw,60px);
  line-height:1.04;letter-spacing:-.01em;margin:.24em 0 0}
.lede{max-width:52ch;color:#5c6560;margin-top:1.1em;font-weight:300;font-size:17px}

/* Paso 1 — el formulario va arriba a propósito: es la conversión, no el epílogo */
.step{background:var(--tg-light);border-block:1px solid var(--line)}
.step__grid{display:grid;gap:clamp(32px,5vw,72px);align-items:start;
  grid-template-columns:repeat(auto-fit,minmax(320px,1fr))}
.form{background:var(--surface);border:1px solid var(--line);border-radius:18px;
  padding:clamp(26px,3.4vw,40px)}
.form label{display:block;font-size:11px;letter-spacing:.16em;text-transform:uppercase;
  color:#6b736e;margin:0 0 7px;font-weight:500}
.form .field{margin-bottom:18px}
.form input[type=text],.form input[type=email],.form input[type=tel]{
  width:100%;font-family:inherit;font-size:15px;color:var(--ink);
  background:#fff;border:1px solid var(--line);border-radius:10px;padding:13px 15px;
  transition:border-color .3s var(--ease)}
.form input:focus{outline:none;border-color:var(--tg)}
.form .consent{display:flex;gap:11px;align-items:flex-start;font-size:13px;
  color:#5c6560;line-height:1.5;margin-bottom:22px}
.form .consent input{margin-top:3px;accent-color:var(--tg);flex:0 0 auto}
.form .hp{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.form__msg{margin:14px 0 0;font-size:14px;min-height:1.2em}
.form__msg--err{color:#9C3B2E}
.form__ok{font-family:var(--serif);font-size:26px;font-weight:400;margin:0 0 .5em}

/* Selector de acabado */
.roofs{display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(232px,1fr));
  margin-top:clamp(32px,4vw,52px)}
.roof{background:var(--surface);border:1px solid var(--line);border-radius:16px;
  padding:26px;cursor:pointer;transition:all .38s var(--ease);
  text-align:left;font-family:inherit}
.roof:hover{border-color:var(--sc);transform:translateY(-3px)}
.roof[aria-pressed="true"]{border-color:var(--tg);background:var(--tg-light);
  box-shadow:0 14px 34px -20px rgba(72,91,55,.5)}
.roof__n{font-family:var(--serif);font-size:25px;font-weight:400;margin:.3em 0 .18em}
.roof__d{font-size:13.5px;color:#6b736e;line-height:1.55}

/* Incluye / No incluye */
.cols{display:grid;gap:clamp(28px,4vw,60px);
  grid-template-columns:repeat(auto-fit,minmax(300px,1fr));
  margin-top:clamp(36px,4vw,56px)}
.card{background:var(--surface);border:1px solid var(--line);border-radius:18px;
  padding:clamp(28px,3.4vw,42px)}
.card--out{background:transparent;border-style:dashed}
.card h3{font-family:var(--serif);font-weight:400;font-size:26px;margin:0 0 .7em}
.list{list-style:none;margin:0;padding:0}
.list li{position:relative;padding-left:28px;margin-bottom:13px;font-size:15px;color:#4d5551}
.list li::before{position:absolute;left:0;top:-1px;font-size:15px}
.list--in li::before{content:"—";color:var(--tg)}
.list--out li::before{content:"\00D7";color:#b9a08a}

/* Galería */
.gal{display:grid;gap:14px;grid-template-columns:repeat(12,1fr);
  margin-top:clamp(36px,4vw,56px)}
.gal figure{margin:0;overflow:hidden;border-radius:14px;background:var(--bone-2)}
.gal img{width:100%;height:100%;object-fit:cover;transition:transform 1.1s var(--ease)}
.gal figure:hover img{transform:scale(1.045)}
.gal figure:nth-child(3n+1){grid-column:span 8;aspect-ratio:16/10}
.gal figure:nth-child(3n+2){grid-column:span 4;aspect-ratio:4/5}
.gal figure:nth-child(3n+3){grid-column:span 6;aspect-ratio:3/2}
.gal figure:nth-child(3n+4){grid-column:span 6;aspect-ratio:3/2}
@media(max-width:760px){.gal figure{grid-column:span 12 !important;aspect-ratio:16/10 !important}}

/* Dónde construirla */
.resorts{background:var(--dl);color:var(--bone)}
.resorts .sec-h,.resorts .eyebrow{color:var(--bone)}
.resorts .lede{color:rgba(245,240,230,.74)}
.resorts .btn{margin-top:clamp(24px,3vw,38px)}

/* Otros modelos — flex y no grid a propósito: con auto-fit, la única tarjeta que hay hoy
   (Dream) se estiraba a todo el ancho y su render 4/3 ocupaba media pantalla. */
.more{display:flex;flex-wrap:wrap;gap:20px;margin-top:clamp(32px,4vw,52px)}
.mcard{flex:0 1 300px;text-decoration:none;border:1px solid var(--line);border-radius:16px;
  overflow:hidden;background:var(--surface);transition:transform .38s var(--ease)}
.mcard:hover{transform:translateY(-4px)}
.mcard img{aspect-ratio:4/3;object-fit:cover;width:100%}
.mcard__b{padding:20px 22px 24px}
.mcard__n{font-family:var(--serif);font-size:26px;font-weight:400;margin:.1em 0 .1em}
.mcard__d{font-size:13px;color:#6b736e}

.cta{text-align:center}
.cta .lede{margin-inline:auto}
footer{border-top:1px solid var(--line);padding-block:40px;font-size:12.5px;color:#8b938d}
footer .wrap{display:flex;justify-content:space-between;gap:20px;flex-wrap:wrap}
footer a{text-decoration:none}
</style>
</head>
<body>

<nav class="nav">
  <div class="wrap">
    <a class="nav__mark" href="/">Lawang</a>
    <a class="nav__back" href="/thecollection">&larr; The Collection</a>
  </div>
</nav>

<header class="hero">
  <div class="hero__bg">
    <img src="<?= lw_e($hero) ?>" alt="Villa <?= lw_e($nombre) ?> — vista exterior" fetchpriority="high">
  </div>
  <div class="wrap hero__in">
    <p class="eyebrow">Modelo de villa · Bali</p>
    <h1><?= lw_e($nombre) ?><em>.</em></h1>
    <p class="hero__sub"><?= lw_e($m['sub']) ?></p>

    <div class="hero__foot">
      <div>
        <p class="price__label">Llave en mano · parcela + construcción</p>
        <?php if ($precio): ?>
          <p class="price__val">desde <?= lw_e($precio) ?></p>
        <?php else: ?>
          <span class="price__pending">Precio bajo consulta</span>
        <?php endif; ?>
      </div>
      <div class="hero__ctas">
        <a class="btn btn--solid" href="#contacto">Solicitar llamada</a>
        <?php if ($m['acabados']): ?><a class="btn btn--ghost" href="#acabados">Ver acabados</a><?php endif; ?>
      </div>
    </div>
  </div>
</header>

<section class="step" id="contacto">
  <div class="wrap step__grid">
    <div>
      <p class="eyebrow">Paso 1</p>
      <h2 class="sec-h">Hablemos de tu <?= lw_e($nombre) ?>.</h2>
      <p class="lede">Déjanos tus datos y te contactamos para darte el presupuesto cerrado
        del acabado que te interese y las parcelas disponibles donde puede construirse.</p>
    </div>

    <form class="form" id="lw-form" novalidate>
      <div class="field">
        <label for="lw-nombre">Nombre y apellidos</label>
        <input type="text" id="lw-nombre" name="name" autocomplete="name" required maxlength="120">
      </div>
      <div class="field">
        <label for="lw-email">Email</label>
        <input type="email" id="lw-email" name="email" autocomplete="email" required maxlength="180">
      </div>
      <div class="field">
        <label for="lw-tel">Teléfono</label>
        <input type="tel" id="lw-tel" name="phone" autocomplete="tel" required maxlength="40">
      </div>
      <!-- Trampa de bots: un humano nunca la ve, así que si viene rellena, es un bot. -->
      <div class="hp" aria-hidden="true"><label for="lw-web">No rellenar</label>
        <input type="text" id="lw-web" name="website" tabindex="-1" autocomplete="off"></div>
      <label class="consent">
        <input type="checkbox" id="lw-consent" name="consent" value="1" required>
        <span>He leído y acepto la <a href="/legal#privacy" target="_blank" rel="noopener">Política de Privacidad</a>
          y que Lawang Estate me contacte sobre este modelo.</span>
      </label>
      <button class="btn btn--clay" type="submit" id="lw-submit">Solicitar llamada</button>
      <p class="form__msg" id="lw-msg" role="status" aria-live="polite"></p>
    </form>
  </div>
</section>

<?php if ($m['acabados']): ?>
<section id="acabados">
  <div class="wrap">
    <p class="eyebrow">Elige tu cubierta</p>
    <h2 class="sec-h">Tres acabados,<br>tres presupuestos.</h2>
    <p class="lede">El resto de la villa no cambia. La cubierta sí mueve el precio final,
      así que se elige antes de cerrar el presupuesto.</p>

    <div class="roofs" role="group" aria-label="Acabado de cubierta">
      <?php foreach ($m['acabados'] as $i => $a): ?>
      <button class="roof" type="button" aria-pressed="<?= $i === 0 ? 'true' : 'false' ?>">
        <span class="eyebrow">Opción <?= str_pad($i + 1, 2, '0', STR_PAD_LEFT) ?></span>
        <p class="roof__n"><?= lw_e($a['n']) ?></p>
        <p class="roof__d"><?= lw_e($a['d']) ?></p>
      </button>
      <?php endforeach; ?>
    </div>
  </div>
</section>
<?php endif; ?>

<?php if ($m['alcance']): ?>
<section style="background:var(--bone-2)">
  <div class="wrap">
    <p class="eyebrow">Alcance de obra</p>
    <h2 class="sec-h">Qué entra en el precio<br>y qué no.</h2>
    <p class="lede">Tal cual figura en el pliego del contratista. Sin letra pequeña:
      lo que no está incluido está escrito igual de grande.</p>

    <div class="cols">
      <div class="card">
        <h3>Incluido</h3>
        <ul class="list list--in">
          <?php foreach ($m['alcance']['incluido'] as $li): ?><li><?= lw_e($li) ?></li><?php endforeach; ?>
        </ul>
      </div>
      <div class="card card--out">
        <h3>No incluido</h3>
        <ul class="list list--out">
          <?php foreach ($m['alcance']['no_incluido'] as $li): ?><li><?= lw_e($li) ?></li><?php endforeach; ?>
        </ul>
      </div>
    </div>
  </div>
</section>
<?php endif; ?>

<?php if ($galeria): ?>
<section>
  <div class="wrap">
    <p class="eyebrow">El proyecto</p>
    <h2 class="sec-h"><?= lw_e($nombre) ?>, por dentro.</h2>
    <div class="gal">
      <?php foreach ($galeria as $src): ?>
      <figure><img src="<?= lw_e($src) ?>" alt="Villa <?= lw_e($nombre) ?>" loading="lazy"></figure>
      <?php endforeach; ?>
    </div>
  </div>
</section>
<?php endif; ?>

<section class="resorts">
  <div class="wrap">
    <p class="eyebrow">Dónde construirla</p>
    <h2 class="sec-h">Tú eliges la parcela.</h2>
    <p class="lede">El modelo es el mismo; cambian la vista, la orientación y el precio del
      terreno. Las parcelas disponibles están en el catálogo, y en la llamada te decimos
      cuáles admiten este modelo.</p>
    <a class="btn btn--ghost" href="/thecollection">Ver parcelas disponibles</a>
  </div>
</section>

<?php if ($otros): ?>
<section>
  <div class="wrap">
    <p class="eyebrow">Otros modelos</p>
    <h2 class="sec-h">La misma obra,<br>otra medida.</h2>
    <div class="more">
      <?php foreach ($otros as $o): ?>
      <a class="mcard" href="/modelo/<?= lw_e($o['id']) ?>">
        <img src="<?= lw_e($o['imgs'][0]) ?>" alt="Villa <?= lw_e($o['nombre']) ?>" loading="lazy">
        <div class="mcard__b">
          <p class="mcard__n"><?= lw_e($o['nombre']) ?></p>
          <p class="mcard__d"><?= (int) $o['dormitorios'] ?> <?= $o['dormitorios'] == 1 ? 'dormitorio' : 'dormitorios' ?></p>
        </div>
      </a>
      <?php endforeach; ?>
    </div>
  </div>
</section>
<?php endif; ?>

<section class="cta">
  <div class="wrap">
    <p class="eyebrow">Siguiente paso</p>
    <h2 class="sec-h">¿Hablamos?</h2>
    <p class="lede">Una llamada para ver números, parcela y plazos. Sin compromiso.</p>
    <p style="margin-top:clamp(24px,3vw,38px)"><a class="btn btn--clay" href="#contacto">Solicitar llamada</a></p>
  </div>
</section>

<footer>
  <div class="wrap">
    <span>Lawang Estate · Bali, Indonesia</span>
    <span><a href="/legal">Aviso legal y privacidad</a></span>
  </div>
</footer>

<script src="/assets/consent.js?v=20260730103319" defer></script>
<script>
(function () {
  var MODELO = <?= json_encode($m['id']) ?>;
  var VALUE  = <?= $m['precio_desde_eur'] === null ? 'null' : (float) $m['precio_desde_eur'] ?>;

  // ViewContent: la semilla del público BOFU. Se manda aunque no haya precio cerrado;
  // `value` solo viaja cuando el número es real, porque Meta optimiza por ese importe.
  function track(ev, extra) {
    if (typeof window.lwTrack !== 'function') return;   // consent.js sin PIXEL_ID o sin consentimiento
    var p = {content_ids: [MODELO], content_type: 'product', content_name: 'modelo-' + MODELO};
    if (VALUE !== null) { p.value = VALUE; p.currency = 'EUR'; }
    for (var k in (extra || {})) p[k] = extra[k];
    window.lwTrack(ev, p);
  }
  // consent.js va con defer: si aún no ha definido lwTrack, se reintenta al cargar todo.
  if (typeof window.lwTrack === 'function') track('ViewContent');
  else window.addEventListener('load', function () { track('ViewContent'); });

  document.querySelectorAll('.roof').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.roof').forEach(function (o) {
        o.setAttribute('aria-pressed', String(o === b));
      });
    });
  });

  var form = document.getElementById('lw-form');
  var msg  = document.getElementById('lw-msg');
  var btn  = document.getElementById('lw-submit');

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    msg.className = 'form__msg';
    if (!form.checkValidity()) {
      msg.className = 'form__msg form__msg--err';
      msg.textContent = 'Revisa los campos: necesitamos nombre, email, teléfono y tu consentimiento.';
      return;
    }
    btn.disabled = true;
    msg.textContent = 'Enviando…';

    var body = new FormData(form);
    body.append('source', 'landing-modelo');
    body.append('property', MODELO);

    fetch('/api/lead.php', {method: 'POST', body: body})
      .then(function (r) { return r.json().then(function (j) { return {ok: r.ok, j: j}; }); })
      .then(function (res) {
        if (!res.ok || !res.j.ok) throw new Error(res.j.error || 'error');
        track('Lead');
        // textContent y no innerHTML: el nombre lo escribe el visitante y volvería a la página.
        var h = document.createElement('p'); h.className = 'form__ok';
        h.textContent = 'Gracias, ' + document.getElementById('lw-nombre').value.trim().split(' ')[0] + '.';
        var p = document.createElement('p'); p.style.color = '#5c6560'; p.style.margin = '0';
        p.textContent = 'Hemos recibido tu solicitud. Te contactamos para agendar la llamada.';
        form.textContent = '';
        form.appendChild(h); form.appendChild(p);
      })
      .catch(function (err) {
        btn.disabled = false;
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
