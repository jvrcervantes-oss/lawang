<?php
/**
 * /dali — landing de PRODUCTO de Villa Dali.
 *
 * ── 11-sep-2026: deja de agendar llamadas ─────────────────────────────────────────────
 * Encargo del owner: «/dali era lo que yo estaba preparando para ser la landing para la
 * publicidad. Pero ahora la landing para publicidad es /palmfield». Esta pagina pasa a ser
 * la ficha de producto de la villa: informa, no capta.
 *   · FUERA el calendario, el widget de Calendly y los tres campos (nombre/telefono/email).
 *     Decision del owner el 11-sep: la pagina NO pide datos al visitante.
 *   · La conversion es WhatsApp, que ya estaba y ya se sincroniza con lo elegido en el
 *     configurador (`sincronizaWA`): el mensaje llega con villa, techo y extras dentro.
 *   · El configurador SE QUEDA: calcula y ensena, no captura nada.
 *   · /palmfield conserva su calendario — es la landing de campana activa.
 * El evento de pixel `Lead` colgaba de `calendly.event_scheduled`, que era la unica cita
 * que constaba de verdad. Sin Calendly no hay cita que confirmar, asi que ese `Lead`
 * desaparece en vez de dispararse sobre un clic: un clic en WhatsApp no es un lead, y
 * etiquetarlo como tal ensucia justo la senal sobre la que Meta optimiza.
 *
 * Implementa el diseño del owner (Stitch, «Bali Villa Investment Landing», fichero
 * `stitch_bali_villa_investment_landing/code.html`) sobre el stack real del sitio: PHP +
 * CSS vainilla. NO se usa el CDN de Tailwind del mockup — es un <script> de 3 MB que
 * compila en el navegador y bloquea el render de una página de tráfico de pago, y el sitio
 * no corre Tailwind en ningún otro sitio.
 *
 * ── DE DÓNDE SALEN LOS DATOS ───────────────────────────────────────────────────────────
 * De `modelo/modelos.php` vía `dali/datos.php`, nunca escritos a mano aquí. Los importes en
 * AUD del mockup son los precios reales en EUR × 1,62; ese tipo vive en `LW_AUD_TASA`, con
 * su fecha, y la página lo rotula.
 *
 * ── QUÉ SE PUBLICA, POR DECISIÓN EXPRESA DEL OWNER (4-sep-2026) ────────────────────────
 * El owner ordenó publicar el diseño tal cual, con el hallazgo delante y por escrito:
 * «me da igual lo que digan los departamentos sobre freehold o sobre las rentabilidades».
 * Queda anotado aquí, en comentario de PHP y no de HTML, qué se le advirtió — para que
 * dentro de seis meses nadie lo lea como un descuido del estudio:
 *   · «Freehold» / «perpetual title»: Legal lo tumbó el 30-jul-2026 (ver el comentario de
 *     `modelo/index.php`) y un extranjero no puede tener Hak Milik en Indonesia.
 *   · «14-18% ROI»: Legal lo marcó el 4-sep como línea ASIC (producto financiero) y
 *     ACL s18 (conducta engañosa) para público australiano.
 * Decisión del owner, registrada en LAW-122. Revertirlo es cosa suya, no del estudio.
 *
 * Lo que NO se ha publicado porque el owner no lo mencionó y contradice datos propios:
 *   · «Only 4 Plots Left in Q2 Release» → la base dice 121 parcelas disponibles. Se usa el
 *     número real, que además sigue siendo un argumento.
 *   · Oficina «Sunset Road No. 88, Seminyak» y las cuentas escrow: no constan en ninguna
 *     fuente del repo. Fuera hasta que alguien las confirme.
 *   · «© 2024» → 2026. Y el placeholder «e.g. Lachlan Murdoch» (persona real) → genérico.
 */

require __DIR__ . '/../modelo/datos.php';

$CAT   = lw_au_catalogo();
$DALI  = $CAT['dali'];

// Renders por nombre de fichero. dali2 y dali3 son las DOS variantes de techo que el
// dossier documenta (p3 «Traditional Elegance» = Sirap Ulin; p4 «Timeless Craftsmanship»
// = bambu + Ulin) y que el configurador vende como `sirap` y `bambu`. Se busca por nombre
// y no por posicion: anadir un render mas desplazaria los indices y el mosaico pasaria a
// ensenar otra cosa sin que nadie se entere. Si falta el fichero, la figura no se pinta.
$IMG = [];
foreach ($DALI['imgs'] as $u) { $IMG[pathinfo($u, PATHINFO_FILENAME)] = $u; }
// Divisas: UNA tabla, la de modelo/datos.php, que es la misma que ya resuelve los precios
// de esta pagina. Si el selector convirtiera con un tipo propio, el estimador y el topbar
// darian dos importes distintos para la misma villa.
$DIVISAS = lw_divisas();

$WA_NUM   = '6281138319862';
$WA_SHOW  = '+62 811-3831-9862';
$WA_TXT   = "Hi, I'd like information about Villa Dali by Lawang in Bali.";
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text=' . rawurlencode($WA_TXT);
$EMAIL    = 'sales@lawangproperties.com';

// Domicilio y líneas directas: los dio el owner el 4-sep-2026. Sustituyen a la oficina de
// «Sunset Road No. 88, Seminyak» que traía el mockup y que no constaba en ninguna fuente
// del repo.
// ⭐ `+62 811-3830-5237` es el número que LAW-46 llevaba desde el 5-ago dando por huérfano
// (aparecía en la pantalla de gracias de los formularios v3 de Meta y no estaba en ninguna
// de las dos webs). El owner lo confirma como suyo: los leads que pulsaron «Message us on
// WhatsApp» aterrizaron en una línea real de Lawang, no se perdieron. Cierra LAW-46.
$OFICINA = 'Jl. Gn. Tangkuban Perahu No.145, 2nd Floor, Padangsambian Klod, '
         . 'Kec. Denpasar Bar., Kota Denpasar, Bali 80117';
$TELEFONOS = [
    ['show' => '+62 811-3830-5240', 'tel' => '+6281138305240'],
    ['show' => '+62 811-3830-5237', 'tel' => '+6281138305237'],
];

$portada  = $DALI['thumb'];
$ogImg    = $portada ?? '/assets/img/lugar/costa.webp';

// Payload del configurador. Lista blanca campo a campo, con los precios YA resueltos en
// servidor: el JS pinta, no calcula precios de catálogo (revisión previa Seguridad+Diseño,
// 2-sep). Los extras (7, por modelo) salen de lw_au_catalogo() -> lw_extras_resueltos(),
// misma fuente que /palmfield — copiado el 14-sep-2026 al adoptar su configurador aquí.
$cfgJs = [
    'tasaAud'  => LW_AUD_TASA,
    'divisas'  => $DIVISAS,
    'divFecha' => LW_DIV_FECHA,
    'modelos'  => [],
];
foreach ($CAT as $id => $v) {
    $cfgJs['modelos'][$id] = [
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

$JSON = JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT;
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
<title>100% Freehold Architectural Villas in Bali &amp; Sumba — Lawang Tropical Properties</title>
<meta name="description" content="Turnkey architectural villas in Bali &amp; Sumba. Fixed-price written EPC contract, land ready with power, water and permits. From <?= lw_e(lw_aud_fmt($DALI['desde_eur'])) ?>.">
<link rel="canonical" href="https://lawangproperties.com/dali">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="100% Freehold Architectural Villas in Bali &amp; Sumba">
<meta property="og:description" content="Turnkey villas in Bali &amp; Sumba. Fixed price, land ready, permits cleared. From <?= lw_e(lw_aud_fmt($DALI['desde_eur'])) ?>.">
<meta property="og:url" content="https://lawangproperties.com/dali">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($ogImg) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<link rel="preload" as="image" href="<?= lw_e($ogImg) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600;700&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/assets/au-landing.css?v=20260914174048">
</head>
<body>

<header class="nav">
  <div class="wrap nav__in">
    <a href="/" aria-label="Lawang Tropical Properties">
      <img class="nav__brand" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
    </a>
    <nav class="nav__links">
      <a href="#estimator">Your Estimate</a>
      <a href="#land-ready">Land Ready Infrastructure</a>
      <a href="#desk">Contact</a>
    </nav>
    <div class="nav__cta">
      <!-- Selector de divisa. Usa las clases del selector de idioma (.lw-lang), que
           idioma-web.js ya inyecta en esta pagina: mismo boton y mismo desplegable que
           en el investor deck, sin una segunda hoja de estilos. `data-no-i18n` para que
           i18n-landing.js no intente traducir "EUR"/"AUD". -->
      <div class="lw-cur" id="lw-div-sel" data-no-i18n></div>
      <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
        <span>WhatsApp Desk</span>
      </a>
    </div>
  </div>
</header>

<main>

<!-- ═══ HERO ═══════════════════════════════════════════════════════════════════════ -->
<div class="wrap">
<section class="hero hero--solo">
  <div>
    <div class="hero__pills">
      <span class="pill pill--verde"><span class="dot"></span> 100% Freehold (Not 25-Yr Lease)</span>
      <span class="pill pill--lag">PMA Foreign Legal Custody</span>
      <span class="pill pill--terra">Q4 2026 Release Open</span>
    </div>

    <?php /* 7-sep-2026: era «100% Freehold Architectural Villas in Bali & Sumba», y con la
             escala de móvil nueva (h1 con suelo de 46px) la palabra ARCHITECTURAL sola es más
             ancha que un móvil de 390 — se salía de la página en horizontal. Un titular grande
             solo cabe si es corto; ese es el intercambio, y aquí la palabra que sobraba no
             aportaba nada que no diga ya el subtítulo. «Freehold» se queda: es vocabulario
             de LAW-122, decisión expresa del owner. */ ?>
    <h1>Freehold Villas in Bali &amp; Sumba</h1>

    <p class="hero__sub">Fixed price, perpetual title, zero leases. Land prepped with power and
      water underground before you break ground.</p>

    <div class="chips">
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-1.2 15L7 12.2l1.4-1.4 2.4 2.4 5-5L17.2 9l-6.4 7z"/></svg></span>
        <span>
          <span class="chip__lb">Perpetual Security</span>
          <span class="chip__vl">100% Freehold Title</span>
        </span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/></svg></span>
        <span>
          <span class="chip__lb">Starting Turnkey</span>
          <span class="chip__vl" data-eur-fijo="<?= (int) $DALI['desde_eur'] ?>"><?= lw_e(lw_precio_fmt($DALI['desde_eur'])) ?></span>
        </span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5L21 16z"/></svg></span>
        <span>
          <span class="chip__lb">Built Area</span>
          <span class="chip__vl">30 m² + 16 m² terrace</span>
        </span>
      </div>
    </div>

    <?php if (!$DALI['sinRender']): ?>
    <div class="mosaico">
      <figure>
        <img src="<?= lw_e($DALI['imgs'][0]) ?>" alt="Villa Dali with its private pool, set in the jungle — Lawang Tropical Properties" fetchpriority="high">
        <figcaption>
          <span class="mos__et">Featured Design</span>
          <span class="mos__tt">Villa Dali with its Private Pool</span>
          <span class="mos__sub">Freehold deed + fixed EPC contract included</span>
        </figcaption>
      </figure>
      <?php /* Las dos tejas que se eligen en el configurador, cada una con su foto del
               dossier. Antes aqui habia un interior y una foto generica de la costa de
               Bali, que no es la villa. */ ?>
      <?php if (isset($IMG['dali2'])): ?>
      <figure>
        <img src="<?= lw_e($IMG['dali2']) ?>" alt="Villa Dali with the Sirap Ulin shingle roof, Lawang Tropical Properties" loading="lazy">
        <figcaption><span class="mos__tt">Sirap Ulin roof</span></figcaption>
      </figure>
      <?php endif; ?>
      <?php if (isset($IMG['dali3'])): ?>
      <figure>
        <img src="<?= lw_e($IMG['dali3']) ?>" alt="Villa Dali with the Bamboo and Ulin shingle roof, Lawang Tropical Properties" loading="lazy">
        <figcaption><span class="mos__tt">Bamboo &amp; Ulin shingle roof</span></figcaption>
      </figure>
      <?php endif; ?>
    </div>
    <?php endif; ?>
  </div>

</section>
</div>

<!-- ═══ CONFIGURADOR: villa → techo → extras (14-sep-2026) ═══════════════════════════
     Copiado de /palmfield (encargo del owner: mismo diseño y estructura que la landing
     de campaña para las páginas de modelo). Sustituye al wizard de 5 pasos (villa, techo,
     isla, vista, parcela): la parcela SALE del configurador — 125 €/m² sigue publicado en
     el pie de página como línea aparte, "sized on the call" — y entran los 7 extras reales
     por modelo (lw_extras_resueltos(), modelo/datos.php) que el wizard viejo no tenía
     precio para. Motor compartido con /modelo/<id> en assets/au-landing-cfg.js: es la
     misma pieza en dos páginas de producto, no una copia que pueda divergir. -->
<section class="sec sec--surface" id="estimator">
  <div class="wrap">
    <div class="et">
      <span class="pill pill--verde">3-Step</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">Pick an option and it moves on</span>
    </div>
    <div class="sec__hd">
      <h2>Three questions. Your figure.</h2>
      <p class="sec__desc">Prices shown in the currency you pick, converted at fixed rates
        (<?= lw_e(LW_DIV_FECHA) ?>) — the contract figure is the euro one. The plot is quoted
        separately, sized on the call.</p>
    </div>

    <div class="cfg">
      <!-- Pasos -->
      <div class="cfg__card">
        <div class="cfg__hd">
          <span class="cfg__paso" id="lw-paso-lb">Step 1 of 3</span>
        </div>

        <!-- Paso 1: villa -->
        <div class="cfg__step" data-paso="1">
          <p class="cfg__q">Which villa?</p>
          <p class="cfg__nota">Identical German-grade engineering, sukabumi pool and ironwood
            decking standard across all models. The price shown is the villa with its cheaper
            roof; you pick the roof next.</p>
          <div class="ops">
            <?php foreach ($CAT as $id => $v): ?>
            <label class="op">
              <input type="radio" name="lw-villa" value="<?= lw_e($id) ?>"<?= $id === 'dali' ? ' checked' : '' ?>>
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
            <span class="res__tt">Live Estimate Summary</span>
            <span class="pill pill--canopy">100% Freehold Included</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="lw-r-villa">Villa Dali</span>
                  <span class="res__sub" id="lw-r-villa-sub">Turnkey build</span></span>
            <span class="res__vl" id="lw-r-villa-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="lw-r-extras">Extras</span>
                  <span class="res__sub" id="lw-r-extras-sub">None selected</span></span>
            <span class="res__vl" id="lw-r-extras-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Roads &amp; approvals</span>
                  <span class="res__sub">PBG / SLF licences, PLN connection</span></span>
            <span class="res__vl">Included</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Freehold plot</span>
                  <span class="res__sub"><?= lw_e(lw_precio_fmt(lw_parcela_tarifa_m2('riverfront'))) ?>/m² · sized on the call</span></span>
            <span class="res__vl">Separate</span>
          </div>
        </div>

        <div class="total">
          <span class="total__lb">Total Freehold Investment</span>
          <span class="total__vl" id="lw-total">—</span>
          <span class="total__alt" id="lw-total-alt"></span>
          <p class="total__nota" id="lw-total-nota">Fixed-price written EPC contract. No
            contractor escalation clauses. Notary, permits, plot and transfer costs are quoted
            separately.</p>
          <a class="btn btn--terra btn--block total__cta" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
            Send this configuration on WhatsApp
          </a>
        </div>
        <p class="res__sync">We reply during Bali hours (WITA)</p>
      </div>
    </div>
  </div>
</section>

<!-- ═══ COMPARATIVA ════════════════════════════════════════════════════════════════ -->

<!-- ═══ LAND READY ═════════════════════════════════════════════════════════════════ -->
<section class="sec sec--cont" id="land-ready">
  <div class="wrap" style="text-align:center">
    <div class="et" style="justify-content:center">
      <span class="pill pill--canopy">Zero Bureaucratic Risk</span>
    </div>
    <h2 style="max-width:22ch;margin-inline:auto">We Buy The Land, Subdivide, Pipe Utilities
      &amp; Clear Permits. You Own It Freehold.</h2>
    <p class="sec__desc" style="max-width:64ch;margin-inline:auto">You never deal with
      village negotiations or missing electric poles. Groundbreaking within 14 days
      of contract.</p>

    <div class="pasos" style="text-align:left">
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-1.2 15L7 12.2l1.4-1.4 2.4 2.4 5-5L17.2 9l-6.4 7z"/></svg></span>
        <span class="paso__n">01 · Title Deed</span>
        <h3>Clean Freehold Acquisition</h3>
        <p>Purchased outright with clean notary titles. Legally subdivided and ready for direct
          transfer under registered PMA legal custody.</p>
        <span class="paso__pie">100% Perpetual Title</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2v11h3v9l7-12h-4l4-8z"/></svg></span>
        <span class="paso__n">02 · Utilities</span>
        <h3>Underground Power &amp; Water</h3>
        <p>Subterranean PLN electricity conduits — no overhead wires spoiling sunset views —
          deep potable well connections, and high-capacity soakaways.</p>
        <span class="paso__pie">PLN 3,500W+ Active</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h2v16H4V4zm7 0h2v16h-2V4zm7 0h2v16h-2V4z"/></svg></span>
        <span class="paso__n">03 · Civil Works</span>
        <h3>Paved Access Roads</h3>
        <p>Full topographic grading, cliffside retaining walls, stormwater drainage, and 5-metre
          wide paved access roads right up to your parcel.</p>
        <span class="paso__pie">Direct Heavy Vehicle Access</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg></span>
        <span class="paso__n">04 · Legal Approvals</span>
        <h3>PBG &amp; SLF Building Licences</h3>
        <p>Pre-approved municipal construction licences and commercial tourism zoning
          (Pariwisata / Komersial) for 100% legal short-term rental revenue.</p>
        <span class="paso__pie">Airbnb &amp; Booking Ready</span>
      </div>
    </div>
  </div>
</section>

<!-- ═══ CTA ════════════════════════════════════════════════════════════════════════ -->
<div class="wrap" style="padding-block:52px" id="desk">
  <section class="cta">
    <div>
      <div class="et">
        <span class="pill pill--terra">Direct Investor Desk</span>
        <span class="mono" style="font-size:11px;color:#6EE7B7">Bali (WITA)</span>
      </div>
      <h2>Ready to Review Freehold Coordinates &amp; Pricing?</h2>
      <p>Message our desk on WhatsApp and we will send you the available surveyed freehold
        coordinates, notary deed proofs, infrastructure videos and exact fixed turnkey costs
        in the currency you choose.</p>
      <div class="cta__garantias">
        <span class="cta__g"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> 100% Freehold perpetual title guarantee</span>
        <span class="cta__g"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> Guaranteed fixed-price written EPC contract</span>
      </div>
    </div>
    <div class="cta__btns">
      <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
        Chat on WhatsApp (<?= lw_e($WA_SHOW) ?>)
      </a>
    </div>
  </section>
</div>

</main>

<footer class="pie">
  <div class="wrap">
    <div class="pie__cols">
      <div>
        <img class="pie__brand" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
        <p style="margin:0">PT Tepi Sun Gai · Registered Developer &amp; Property Advisory.
          Developing verified freehold parcels and turnkey luxury architectural villas across
          Tabanan, Uluwatu, and Sumba.</p>
        <div class="pie__sellos">
          <span class="sello">100% Freehold — PMA Foreign Legal Custody</span>
        </div>
      </div>
      <div>
        <h4>Investor Desk</h4>
        <p class="pie__dl">
          <span>Email: <a href="mailto:<?= lw_e($EMAIL) ?>"><b><?= lw_e($EMAIL) ?></b></a></span>
          <span>WhatsApp Direct: <a href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer"><b><?= lw_e($WA_SHOW) ?></b></a></span>
          <?php foreach ($TELEFONOS as $t): ?>
          <span>Direct line: <a href="tel:<?= lw_e($t['tel']) ?>"><b><?= lw_e($t['show']) ?></b></a></span>
          <?php endforeach; ?>
          <span>Working hours: <b>Bali time (WITA)</b></span>
          <?php /* "Office", no "Registered Office" como el mockup: que esta sea la sede
                   inscrita de PT TEPI SUN GAI en el NIB/SK no consta en ninguna fuente que
                   el estudio pueda comprobar, y es un término legal concreto. "Office" es
                   cierto en los dos casos. */ ?>
          <span style="margin-top:5px">Office:<br><b><?= lw_e($OFICINA) ?></b></span>
        </p>
      </div>
      <div>
        <h4>Turnkey EPC Standard</h4>
        <p style="margin:0">Every project operates under guaranteed fixed-price written
          agreements with progress audits at each construction milestone.</p>
        <div class="pie__sellos">
          <span class="sello">100% Freehold</span>
          <span class="sello">Clean Deeds</span>
          <span class="sello">Investor Desk</span>
        </div>
      </div>
    </div>
    <div class="pie__legal">
      <span>© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). 100% foreign freehold
        ownership via registered PMA structure.</span>
      <span>
        <a href="/legal">Legal &amp; privacy</a> ·
        <a href="#" id="lw-cookies">Cookie preferences</a>
      </span>
    </div>
  </div>
</footer>

<!-- Barra inferior en móvil, del diseño -->
<div class="movil">
  <span class="movil__pr">
    <b id="lw-movil-pr" data-eur-fijo="<?= (int) $DALI['desde_eur'] ?>"><?= lw_e(lw_precio_fmt($DALI['desde_eur'])) ?></b>
    <span>100% Freehold Bali</span>
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
  var CFG      = <?= json_encode($cfgJs, $JSON) ?>;
  var WA_NUM   = <?= json_encode($WA_NUM, $JSON) ?>;

  // ── Píxel ────────────────────────────────────────────────────────────────────────
  // `Lead` YA NO se dispara en esta página (11-sep-2026). Antes salía del postMessage de
  // Calendly, que era el único sitio donde constaba una cita de verdad; sin agendado no
  // hay nada que confirmar. Un clic en WhatsApp NO es un lead: etiquetarlo así ensuciaría
  // la señal sobre la que Meta optimiza. Se mantiene `ViewContent`.
  function track(ev, extra) {
    if (typeof window.lwTrack === 'function') { window.lwTrack(ev, extra || {}); return; }
    if (typeof window.fbq === 'function') { window.fbq('track', ev, extra || {}); }
  }
  function trackVista() {
    track('ViewContent', {content_name: 'Villa Dali', content_type: 'product',
      value: <?= (int) $DALI['desde_eur'] ?>, currency: 'EUR'});
  }
  if (document.readyState === 'complete') trackVista();
  else window.addEventListener('load', trackVista);

  // ── Configurador villa → techo → extras: motor compartido con /modelo/<id>, ver
  //    assets/au-landing-cfg.js. La divisa arranca en EUR (es la del contrato) y se
  //    recuerda entre visitas en localStorage. ─────────────────────────────────────
  window.lwAuCfgInit({
    cfg: CFG,
    waNum: WA_NUM,
    urlBase: '/dali',
    villaDefault: 'dali',
    waIntro: "Hi, I'd like information about the "
  });

  // ── Cookies ──────────────────────────────────────────────────────────────────────
  var ck = document.getElementById('lw-cookies');
  if (ck) ck.addEventListener('click', function (ev) {
    ev.preventDefault();
    if (window.lwConsentReopen) window.lwConsentReopen();
  });
}());
</script>
</body>
</html>
