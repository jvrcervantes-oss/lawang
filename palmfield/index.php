<?php
/**
 * /palmfield — landing de campaña del proyecto Palm Field. 4-sep-2026.
 *
 * Encargo del owner: «en vez de enfocarlo a tickets vamos a enfocarlo a un proyecto
 * llamado Palm Field. Disponibilidad de las villas: todas las que ya hay.» Es la landing
 * a la que apunta la campaña de Australia; sustituye a /dali como destino del anuncio.
 *
 * ── MISMO DISEÑO QUE /dali, NO UNA COPIA ──────────────────────────────────────────────
 * Comparte `assets/au-landing.css` — el CSS se extrajo de dali/index.php al nacer esta
 * segunda página justamente para no tener dos copias divergiendo (`tools/unificar.py`).
 * Si hay que retocar la piel, se toca ahí y cambian las dos.
 *
 * ── DE DÓNDE SALE CADA DATO (ninguno escrito a mano) ───────────────────────────────────
 *   · Precio de las 5 villas .......... modelo/modelos.php, vía modelo/datos.php
 *   · Tarifa de parcela (125 €/m²) .... lw_parcela_tarifa_m2(), modelo/lib.php
 *   · Tamaños de parcela .............. los 5 que HOY están `disponible` en Supabase para
 *                                       «Palm Field W5» (250·255·310·330·355 m²), leídos
 *                                       el 4-sep. Van en LW_PF_PARCELAS con su fecha.
 *   · Entrega, tenencia, ubicación .... data.json (ficha `palm-field-bali`)
 *   · Tipo EUR→AUD ................... LW_AUD_TASA, fijo y fechado
 *
 * ⚠️ DECISIÓN DEL OWNER (4-sep): mandan los precios del 2-sep — Dune 68.000 €, parcela
 * 125 €/m². `data.json` publica todavía los viejos (Dune 64.000 €, 130 €/m², «26 units»)
 * en /property/palm-field-bali, y NO se puede corregir desde el repo: ese fichero lo
 * gestiona el panel y manda la copia del servidor. Queda para el owner → LAW-123.
 * Mientras no lo corrija, la misma web publica dos precios para la misma villa.
 *
 * ⚠️ NO se publica el recuento de parcelas libres (hoy 23). Un número así envejece solo y
 * esta página no tiene acceso a Supabase; publicarlo sería la misma familia de fallo que
 * el «Only 4 Plots Left» que se descartó del mockup. Se publican los TAMAÑOS, que cambian
 * mucho más despacio, y la disponibilidad exacta se confirma en la llamada.
 *
 * Sobre «freehold» y las cifras de rentabilidad: decisión expresa del owner, ver el
 * docblock de dali/index.php y LAW-122. El propio dossier del cliente titula una página
 * «Your own freehold villa», así que aquí se usa su misma terminología.
 */

require __DIR__ . '/../modelo/datos.php';

$CAT = lw_au_catalogo();
$OPC = lw_picker_opciones();

// Tarifa de la parcela: Palm Field está en Balian (costa oeste, no beachfront), así que le
// aplica el tramo general de 125 €/m². Sale de lib.php, no escrita aquí.
$PF_TARIFA = lw_parcela_tarifa_m2('riverfront');

// Tamaños realmente disponibles, leídos de Supabase el 4-sep-2026. Se listan con su fecha
// porque son un dato vivo: al venderse una medida entera, esta lista se queda por detrás.
const LW_PF_PARCELAS_FECHA = '4 Sep 2026';
$PF_PARCELAS = [250, 255, 310, 330, 355];

$PF_ENTREGA  = 'Q1 2027';
$PF_ZONA     = 'Balian Hills, West Bali';
$PF_MAPA     = 'https://www.google.com/maps?q=-8.4862792,114.9606773';

$WA_NUM   = '6281138319862';
$WA_SHOW  = '+62 811-3831-9862';
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text='
          . rawurlencode("Hi, I'm an Australian investor interested in Palm Field, Bali.");
$EMAIL    = 'sales@lawangproperties.com';
$CALENDLY = 'https://calendly.com/lawangproperties';

$OFICINA = 'Jl. Gn. Tangkuban Perahu No.145, 2nd Floor, Padangsambian Klod, '
         . 'Kec. Denpasar Bar., Kota Denpasar, Bali 80117';
$TELEFONOS = [
    ['show' => '+62 811-3830-5240', 'tel' => '+6281138305240'],
    ['show' => '+62 811-3830-5237', 'tel' => '+6281138305237'],
];

// Fotos REALES del proyecto, ya públicas (las sirve también la ficha /property).
// El owner ha dicho que manda imágenes nuevas: cuando lleguen se sustituyen aquí y en
// ningún sitio más — la plantilla no las lista dos veces.
$IMG_AEREA  = '/assets/img/palm-field-aerial.webp';
$IMG_2      = '/assets/img/properties/palm-field-2.jpg';
$IMG_3      = '/assets/img/properties/palm-field-3.jpg';
$IMG_PLANO  = '/assets/img/properties/palm-field-4.jpg';
$ogImg      = $IMG_AEREA;

// El más barato del catálogo, para el «desde» del hero: villa más pequeña + parcela más
// pequeña. Se calcula, no se escribe.
$desdeVilla = min(array_map(function ($v) { return $v['desde_eur']; }, $CAT));
$desdeTotal = $desdeVilla + $PF_TARIFA * min($PF_PARCELAS);

$calTz   = new DateTimeZone('Asia/Makassar');
$calHoy  = new DateTimeImmutable('today', $calTz);
$calQ    = 0;
$calFin  = $calHoy->modify('last day of this month');
for ($c = $calHoy; $c <= $calFin; $c = $c->modify('+1 day')) {
    if ((int) $c->format('N') < 6) { $calQ++; }
}
$calIni  = $calHoy->modify($calQ < 5 ? 'first day of next month' : 'first day of this month');
$calPad  = (int) $calIni->format('N') - 1;
$calDias = (int) $calIni->format('t');

$cfgJs = ['tasaAud' => LW_AUD_TASA, 'tarifa' => $PF_TARIFA, 'modelos' => []];
foreach ($CAT as $id => $v) {
    $cfgJs['modelos'][$id] = [
        'villa'  => $v['villa'],
        'specs'  => $v['specs'],
        'techos' => [
            'sirap' => ['nombre' => $v['techos']['sirap']['nombre'], 'eur' => $v['techos']['sirap']['eur']],
            'bambu' => ['nombre' => $v['techos']['bambu']['nombre'], 'eur' => $v['techos']['bambu']['eur']],
        ],
    ];
}
$JSON = JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT;
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Palm Field — Freehold Villas in Balian Hills, Bali | Lawang Tropical Properties</title>
<meta name="description" content="Palm Field: freehold villa plots in Balian Hills, West Bali, five minutes from the beach. Land ready with power, water and permits. Five villa models, handover <?= lw_e($PF_ENTREGA) ?>. From <?= lw_e(lw_aud_fmt($desdeTotal)) ?>.">
<link rel="canonical" href="https://lawangproperties.com/palmfield">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="Palm Field — Freehold Villas in Balian Hills, Bali">
<meta property="og:description" content="Freehold plots five minutes from the beach, land ready, five villa models. From <?= lw_e(lw_aud_fmt($desdeTotal)) ?>.">
<meta property="og:url" content="https://lawangproperties.com/palmfield">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($ogImg) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<link rel="preload" as="image" href="<?= lw_e($ogImg) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Jost:wght@400;500;600;700&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<link href="https://assets.calendly.com/assets/external/widget.css" rel="stylesheet">
<script src="https://assets.calendly.com/assets/external/widget.js" defer></script>
<link rel="stylesheet" href="/assets/au-landing.css?v=1">
</head>
<body>

<header class="nav">
  <div class="wrap nav__in">
    <a href="/" aria-label="Lawang Tropical Properties">
      <img class="nav__brand" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
    </a>
    <nav class="nav__links">
      <a href="#estimator">Plots &amp; Villas</a>
      <a href="#project">The Project</a>
      <a href="#location">Location</a>
      <a href="#desk">Perth &amp; Sydney Desk</a>
    </nav>
    <div class="nav__cta">
      <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
        <span>WhatsApp Desk</span>
      </a>
      <a class="btn btn--terra" href="#book">
        <span>Schedule Call</span>
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 5l7 7-7 7v-4H4v-6h9V5z"/></svg>
      </a>
    </div>
  </div>
</header>

<main>

<!-- ═══ HERO ═══════════════════════════════════════════════════════════════════════ -->
<div class="wrap">
<section class="hero">
  <div>
    <div class="hero__pills">
      <span class="pill pill--verde"><span class="dot"></span> Freehold (Hak Milik) / HGB</span>
      <span class="pill pill--lag">Direct Australian Investor Gate · PMA Custody</span>
      <span class="pill pill--terra">Handover <?= lw_e($PF_ENTREGA) ?></span>
    </div>

    <h1>Palm Field</h1>
    <p class="hero__sub" style="font-size:19px;color:var(--primary);margin-top:8px">
      Freehold villa plots in <?= lw_e($PF_ZONA) ?>, five minutes from the beach.</p>
    <p class="hero__sub">Land bought outright, subdivided, and delivered with underground
      power, water and building permits already cleared. You choose the plot and the villa;
      the price is fixed in writing before you sign.</p>

    <div class="chips">
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-1.2 15L7 12.2l1.4-1.4 2.4 2.4 5-5L17.2 9l-6.4 7z"/></svg></span>
        <span><span class="chip__lb">Tenure</span>
              <span class="chip__vl">Freehold · Hak Milik / HGB</span></span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/></svg></span>
        <span><span class="chip__lb">Plot + villa from</span>
              <span class="chip__vl"><?= lw_e(lw_aud_fmt($desdeTotal)) ?></span></span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10z"/></svg></span>
        <span><span class="chip__lb">Handover</span>
              <span class="chip__vl"><?= lw_e($PF_ENTREGA) ?></span></span>
      </div>
    </div>

    <div class="mosaico">
      <figure>
        <img src="<?= lw_e($IMG_AEREA) ?>" alt="Palm Field from the air: villas laid out between the river and the jungle, Balian Hills, Bali" fetchpriority="high">
        <figcaption>
          <span class="mos__et">The masterplan, built</span>
          <span class="mos__tt">Palm Field, Balian Hills</span>
          <span class="mos__sub">Private pool villas between the river and the rice terraces</span>
        </figcaption>
      </figure>
      <figure>
        <img src="<?= lw_e($IMG_2) ?>" alt="Palm Field villa exterior" loading="lazy">
        <figcaption><span class="mos__tt">Your own villa</span></figcaption>
      </figure>
      <figure>
        <img src="<?= lw_e($IMG_3) ?>" alt="Palm Field surroundings, west Bali" loading="lazy">
        <figcaption><span class="mos__tt">Five minutes from the beach</span></figcaption>
      </figure>
    </div>
  </div>

  <!-- ── Tarjeta de reserva ────────────────────────────────────────────────────── -->
  <aside class="book" id="book">
    <div class="book__hd">
      <div>
        <div class="book__live">
          <span class="dot live"></span>
          <b>Live Australian Desk</b>
          <span class="pill pill--canopy">Active Now</span>
        </div>
        <span class="book__zone">Sydney (AEST) &amp; Perth (AWST) direct sync</span>
      </div>
      <span class="pill pill--lag">Palm Field</span>
    </div>

    <div class="cal" id="lw-cal">
      <div class="cal__hd">
        <span class="cal__mes">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10z"/></svg>
          <?= lw_e($calIni->format('F Y')) ?> · Site Review Slots
        </span>
        <span class="cal__tz">WITA · Bali</span>
      </div>
      <div class="cal__dow" aria-hidden="true">
        <span>M</span><span>T</span><span>W</span><span>T</span><span>F</span><span>S</span><span>S</span>
      </div>
      <div class="cal__grid">
        <?php for ($i = 0; $i < $calPad; $i++): ?><span class="cal__no"></span><?php endfor; ?>
        <?php for ($d = 1; $d <= $calDias; $d++):
          $cd    = $calIni->modify('+' . ($d - 1) . ' days');
          $libre = (int) $cd->format('N') < 6 && $cd >= $calHoy;
        ?>
          <?php if ($libre): ?>
          <button type="button" class="cal__d" data-fecha="<?= lw_e($cd->format('Y-m-d')) ?>"
                  data-larga="<?= lw_e($cd->format('l, j F Y')) ?>"><?= $d ?></button>
          <?php else: ?>
          <span class="cal__no"><?= $d ?></span>
          <?php endif; ?>
        <?php endfor; ?>
      </div>
      <div class="cal__sel">
        <span id="lw-cal-sel">Select a day — Mon to Fri</span>
        <span id="lw-cal-hint">Real times load below</span>
      </div>
    </div>

    <div class="cal__wid" id="lw-wid"></div>

    <div class="campos">
      <div class="campo">
        <label for="lw-nombre">Full Name</label>
        <input id="lw-nombre" type="text" autocomplete="name" placeholder="First and last name">
      </div>
      <div class="campo">
        <label for="lw-tel">Mobile / WhatsApp</label>
        <input id="lw-tel" type="tel" autocomplete="tel" placeholder="+61 400 000 000">
      </div>
    </div>
    <div class="campo">
      <label for="lw-email">Email Address (for calendar invite &amp; plot list)</label>
      <input id="lw-email" type="email" autocomplete="email" placeholder="name@domain.com.au">
    </div>

    <button class="btn btn--terra btn--block" type="button" id="lw-confirmar">
      Book Your Palm Field Review
    </button>

    <div class="book__pie">
      <span class="book__np">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4z"/></svg>
        No high pressure
      </span>
      <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer" id="lw-wa">
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
        Chat on WhatsApp
      </a>
    </div>
  </aside>
</section>
</div>

<!-- ═══ CONFIGURADOR: parcela + villa ══════════════════════════════════════════════ -->
<section class="sec sec--surface" id="estimator">
  <div class="wrap">
    <div class="et">
      <span class="pill pill--verde">2 choices</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">Plot + villa = your figure</span>
    </div>
    <div class="sec__hd">
      <h2>Pick your plot, pick your villa</h2>
      <p class="sec__desc">Every villa model can be built on every plot. Land is
        <?= lw_e(lw_precio_fmt($PF_TARIFA)) ?>/m² at Palm Field. Prices shown at a fixed rate of
        <?= lw_e(number_format(LW_AUD_TASA, 2)) ?> AUD/EUR (<?= lw_e(LW_AUD_FECHA) ?>) — the
        contract figure is the euro one.</p>
    </div>

    <div class="cfg">
      <div class="cfg__card">
        <div class="cfg__hd">
          <span class="cfg__paso">Plot size</span>
          <span class="divisas" role="group" aria-label="Currency">
            <button type="button" class="divisa is-on" data-div="AUD">AUD ($)</button>
            <button type="button" class="divisa" data-div="EUR">EUR (€)</button>
          </span>
        </div>

        <p class="cfg__nota">Plot sizes available at Palm Field as of
          <?= lw_e(LW_PF_PARCELAS_FECHA) ?>. Exact plots are confirmed on the call.</p>
        <div class="ops" style="margin-bottom:22px">
          <?php foreach ($PF_PARCELAS as $i => $m2): ?>
          <label class="op">
            <input type="radio" name="pf-m2" value="<?= (int) $m2 ?>"<?= $i === 0 ? ' checked' : '' ?>>
            <span><span class="op__nb"><?= (int) $m2 ?> m²</span>
                  <span class="op__sp">Land only · <?= lw_e(lw_precio_fmt($PF_TARIFA)) ?>/m²</span></span>
            <span class="op__pr" data-eur="<?= (int) ($PF_TARIFA * $m2) ?>">
              <b><?= lw_e(lw_aud_fmt($PF_TARIFA * $m2)) ?></b>
              <i><?= lw_e(lw_precio_fmt($PF_TARIFA * $m2)) ?></i>
            </span>
          </label>
          <?php endforeach; ?>
        </div>

        <div class="cfg__hd"><span class="cfg__paso">Villa model — all five available</span></div>
        <div class="ops">
          <?php foreach ($CAT as $id => $v): ?>
          <label class="op">
            <input type="radio" name="pf-villa" value="<?= lw_e($id) ?>"<?= $id === 'dune' ? ' checked' : '' ?>>
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
              <b><?= lw_e(lw_aud_fmt($v['desde_eur'])) ?></b>
              <i><?= lw_e(lw_precio_fmt($v['desde_eur'])) ?></i>
            </span>
          </label>
          <?php endforeach; ?>
        </div>
      </div>

      <div class="res">
        <div class="res__card">
          <div class="res__hd">
            <span class="res__tt">Your Palm Field figure</span>
            <span class="pill pill--canopy">Freehold included</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="pf-r-plot">250 m² plot</span>
                  <span class="res__sub">Subdivided freehold · power, water, permits</span></span>
            <span class="res__vl" id="pf-r-plot-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="pf-r-villa">Villa</span>
                  <span class="res__sub" id="pf-r-villa-sub">Turnkey build</span></span>
            <span class="res__vl" id="pf-r-villa-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Roads &amp; approvals</span>
                  <span class="res__sub">PBG / SLF licences, PLN connection</span></span>
            <span class="res__vl">Included</span>
          </div>
        </div>

        <div class="total">
          <span class="total__lb">Plot + villa, turnkey</span>
          <span class="total__vl" id="pf-total">—</span>
          <span class="total__alt" id="pf-total-alt"></span>
          <p class="total__nota">Fixed-price written EPC contract. Notary, permits and
            transfer costs are quoted separately. Handover <?= lw_e($PF_ENTREGA) ?>.</p>
          <a class="btn btn--terra btn--block total__cta" href="#book">
            Book a 30-Min Call on This Figure
          </a>
        </div>
        <p class="res__sync">Perth &amp; Sydney working hours · direct sync</p>
      </div>
    </div>
  </div>
</section>

<!-- ═══ EL PROYECTO ════════════════════════════════════════════════════════════════ -->
<section class="sec sec--cont" id="project">
  <div class="wrap" style="text-align:center">
    <div class="et" style="justify-content:center">
      <span class="pill pill--canopy">Zero Bureaucratic Risk</span>
    </div>
    <h2 style="max-width:24ch;margin-inline:auto">We Buy The Land, Subdivide, Pipe Utilities
      &amp; Clear Permits. You Own It Freehold.</h2>
    <p class="sec__desc" style="max-width:64ch;margin-inline:auto">Australian investors never
      deal with village negotiations or missing electric poles. Palm Field is delivered
      plot-ready before you break ground.</p>

    <div class="pasos" style="text-align:left">
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-1.2 15L7 12.2l1.4-1.4 2.4 2.4 5-5L17.2 9l-6.4 7z"/></svg></span>
        <span class="paso__n">01 · Title Deed</span>
        <h3>Clean Freehold Acquisition</h3>
        <p>Land purchased outright with clean notary titles, legally subdivided and ready for
          direct transfer under registered PMA legal custody.</p>
        <span class="paso__pie">Hak Milik / HGB</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2v11h3v9l7-12h-4l4-8z"/></svg></span>
        <span class="paso__n">02 · Utilities</span>
        <h3>Underground Power &amp; Water</h3>
        <p>Subterranean PLN electricity conduits — no overhead wires spoiling the view — deep
          potable well connections and high-capacity soakaways.</p>
        <span class="paso__pie">PLN 3,500W+ Active</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h2v16H4V4zm7 0h2v16h-2V4zm7 0h2v16h-2V4z"/></svg></span>
        <span class="paso__n">03 · Civil Works</span>
        <h3>Paved Access Roads</h3>
        <p>Full topographic grading, retaining walls, stormwater drainage and paved access
          roads right up to your parcel.</p>
        <span class="paso__pie">Direct Heavy Vehicle Access</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg></span>
        <span class="paso__n">04 · Legal Approvals</span>
        <h3>PBG &amp; SLF Building Licences</h3>
        <p>Pre-approved municipal construction licences and commercial tourism zoning
          (Pariwisata / Komersial) for legal short-term rental.</p>
        <span class="paso__pie">Airbnb &amp; Booking Ready</span>
      </div>
    </div>
  </div>
</section>

<!-- ═══ UBICACIÓN ══════════════════════════════════════════════════════════════════ -->
<section class="sec" id="location">
  <div class="wrap">
    <div class="cfg" style="margin-top:0">
      <div>
        <div class="et"><span class="pill pill--canopy">Location</span></div>
        <h2><?= lw_e($PF_ZONA) ?></h2>
        <p class="sec__desc">Palm Field sits on the west coast, above the Balian river and
          five minutes from the beach — the stretch of Bali that is being developed now,
          away from the traffic of the south.</p>
        <div class="chips" style="grid-template-columns:repeat(2,minmax(0,1fr))">
          <div class="chip">
            <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2C8.1 2 5 5.1 5 9c0 5.2 7 13 7 13s7-7.8 7-13c0-3.9-3.1-7-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z"/></svg></span>
            <span><span class="chip__lb">To the beach</span><span class="chip__vl">5 minutes</span></span>
          </div>
          <div class="chip">
            <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5L21 16z"/></svg></span>
            <span><span class="chip__lb">From Perth</span><span class="chip__vl">3h 40m direct</span></span>
          </div>
        </div>
        <p style="margin-top:20px">
          <a class="btn btn--lag" href="<?= lw_e($PF_MAPA) ?>" target="_blank" rel="noopener noreferrer">
            Open in Google Maps
            <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 5l7 7-7 7v-4H4v-6h9V5z"/></svg>
          </a>
        </p>
      </div>
      <figure style="margin:0;border-radius:16px;overflow:hidden;border:1px solid var(--borde)">
        <img src="<?= lw_e($IMG_PLANO) ?>" alt="Palm Field masterplan, Balian Hills" loading="lazy">
      </figure>
    </div>
  </div>
</section>

<!-- ═══ CTA ════════════════════════════════════════════════════════════════════════ -->
<div class="wrap" style="padding-block:52px" id="desk">
  <section class="cta">
    <div>
      <div class="et">
        <span class="pill pill--terra">Direct Australian Investor Desk</span>
        <span class="mono" style="font-size:11px;color:#6EE7B7">Sydney (AEST) &amp; Perth (AWST)</span>
      </div>
      <h2>Ready to Review Palm Field Plots &amp; Pricing?</h2>
      <p>In 30 minutes our desk walks you through the plots still available, the notary deed
        proofs, drone footage of the site as it stands today, and your exact fixed turnkey
        cost in AUD.</p>
      <div class="cta__garantias">
        <span class="cta__g"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> Freehold title, transferred to you</span>
        <span class="cta__g"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> Guaranteed fixed-price written EPC contract</span>
      </div>
    </div>
    <div class="cta__btns">
      <a class="btn btn--terra" href="#book">Book Your Review ↑</a>
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
          Developing verified freehold parcels and turnkey architectural villas across
          Tabanan, Uluwatu and Sumba for Australian investors.</p>
        <div class="pie__sellos">
          <span class="sello">Freehold — PMA Foreign Legal Custody</span>
        </div>
      </div>
      <div>
        <h4>Australian Investor Desk</h4>
        <p class="pie__dl">
          <span>Email: <a href="mailto:<?= lw_e($EMAIL) ?>"><b><?= lw_e($EMAIL) ?></b></a></span>
          <span>WhatsApp Direct: <a href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer"><b><?= lw_e($WA_SHOW) ?></b></a></span>
          <?php foreach ($TELEFONOS as $t): ?>
          <span>Direct line: <a href="tel:<?= lw_e($t['tel']) ?>"><b><?= lw_e($t['show']) ?></b></a></span>
          <?php endforeach; ?>
          <span>Working Hours Sync: <b>8:00 AM – 7:00 PM AEST / AWST</b></span>
          <span style="margin-top:5px">Office:<br><b><?= lw_e($OFICINA) ?></b></span>
        </p>
      </div>
      <div>
        <h4>Turnkey EPC Standard</h4>
        <p style="margin:0">Every project operates under guaranteed fixed-price written
          agreements with progress audits at each construction milestone.</p>
        <div class="pie__sellos">
          <span class="sello">Freehold</span>
          <span class="sello">Clean Deeds</span>
          <span class="sello">Australian Desk</span>
        </div>
      </div>
    </div>
    <div class="pie__legal">
      <span>© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Foreign freehold ownership
        via registered PMA structure.</span>
      <span><a href="/legal">Legal &amp; privacy</a> · <a href="#" id="lw-cookies">Cookie preferences</a></span>
    </div>
  </div>
</footer>

<div class="movil">
  <span class="movil__pr">
    <b id="pf-movil"><?= lw_e(lw_aud_fmt($desdeTotal)) ?></b>
    <span>Palm Field · plot + villa</span>
  </span>
  <a class="btn btn--terra" href="#book">Book Call</a>
  <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer" aria-label="Chat on WhatsApp">
    <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
  </a>
</div>

<script src="/assets/consent.js?v=20260901" defer></script>
<script>
(function () {
  'use strict';
  var CFG      = <?= json_encode($cfgJs, $JSON) ?>;
  var CALENDLY = <?= json_encode($CALENDLY, $JSON) ?>;
  var WA_NUM   = <?= json_encode($WA_NUM, $JSON) ?>;

  function track(ev, extra) {
    if (typeof window.lwTrack === 'function') { window.lwTrack(ev, extra || {}); return; }
    if (typeof window.fbq === 'function') { window.fbq('track', ev, extra || {}); }
  }
  function vista() {
    track('ViewContent', {content_name: 'Palm Field', content_type: 'product',
      value: <?= (int) $desdeTotal ?>, currency: 'EUR'});
  }
  if (document.readyState === 'complete') vista();
  else window.addEventListener('load', vista);

  var S = {m2: <?= (int) $PF_PARCELAS[0] ?>, villa: 'dune', div: 'AUD'};

  function eur(n) { return '€' + Number(n).toLocaleString('en-US'); }
  function audf(n) { return '$' + (Math.round(n * CFG.tasaAud / 10) * 10).toLocaleString('en-US') + ' AUD'; }
  function pinta(n) { return S.div === 'AUD' ? audf(n) : eur(n); }
  function alterna(n) { return S.div === 'AUD' ? eur(n) : audf(n); }

  function $(id) { return document.getElementById(id); }
  function txt(id, s) { var e = $(id); if (e) e.textContent = s; }

  function recalcular() {
    var m = CFG.modelos[S.villa];
    if (!m) return;
    // El techo Sirap es el "desde" de cada villa; el otro se elige en la llamada. Igual que
    // en /dali, el precio del techo es el precio COMPLETO de la villa, no un recargo.
    var pv = Math.min(m.techos.sirap.eur, m.techos.bambu.eur);
    var parcela = CFG.tarifa * S.m2;
    var total = pv + parcela;

    txt('pf-r-plot', S.m2 + ' m² plot');
    txt('pf-r-plot-pr', pinta(parcela));
    txt('pf-r-villa', m.villa);
    txt('pf-r-villa-sub', m.specs);
    txt('pf-r-villa-pr', pinta(pv));
    txt('pf-total', pinta(total));
    txt('pf-total-alt', '≈ ' + alterna(total));
    txt('pf-movil', pinta(total));

    document.querySelectorAll('.op__pr[data-eur]').forEach(function (n) {
      var v = Number(n.getAttribute('data-eur'));
      n.querySelector('b').textContent = pinta(v);
      n.querySelector('i').textContent = alterna(v);
    });

    var p = new URLSearchParams(location.search);
    ['plot', 'villa', 'cur'].forEach(function (k) { p.delete(k); });
    if (S.m2 !== <?= (int) $PF_PARCELAS[0] ?>) p.set('plot', String(S.m2));
    if (S.villa !== 'dune') p.set('villa', S.villa);
    if (S.div !== 'AUD') p.set('cur', S.div);
    var q = p.toString();
    history.replaceState(history.state, '', '/palmfield' + (q ? '?' + q : ''));

    var t = "Hi, I'm an Australian investor interested in Palm Field: " + m.villa
          + ' on a ' + S.m2 + ' m² plot (' + eur(total) + ').';
    var href = 'https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(t);
    document.querySelectorAll('a[href*="wa.me/"]').forEach(function (a) { a.href = href; });
  }

  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t || t.type !== 'radio') return;
    if (t.name === 'pf-m2') S.m2 = Number(t.value);
    else if (t.name === 'pf-villa') S.villa = t.value;
    else return;
    recalcular();
  });

  document.querySelectorAll('.divisa').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.divisa').forEach(function (o) { o.classList.remove('is-on'); });
      b.classList.add('is-on');
      S.div = b.getAttribute('data-div');
      recalcular();
    });
  });

  // ── Calendario -> Calendly (idéntico a /dali) ────────────────────────────────────
  (function () {
    var cal = $('lw-cal'), wid = $('lw-wid');
    if (!cal || !wid) return;
    var fecha = null;
    function abre() {
      if (!fecha) return;
      var u = CALENDLY + '?hide_gdpr_banner=1&background_color=FAF7F0&text_color=22282A'
            + '&primary_color=104C4F&month=' + fecha.slice(0, 7) + '&date=' + fecha;
      var n = ($('lw-nombre') || {}).value, e = ($('lw-email') || {}).value;
      if (n) u += '&name=' + encodeURIComponent(n);
      if (e) u += '&email=' + encodeURIComponent(e);
      wid.classList.add('is-on');
      if (window.Calendly && typeof window.Calendly.initInlineWidget === 'function') {
        wid.innerHTML = '';
        window.Calendly.initInlineWidget({url: u, parentElement: wid});
      }
      track('AbrioCalendario', {});
    }
    cal.addEventListener('click', function (ev) {
      var b = ev.target.closest('.cal__d');
      if (!b || !cal.contains(b)) return;
      cal.querySelectorAll('.cal__d.is-on').forEach(function (o) { o.classList.remove('is-on'); });
      b.classList.add('is-on');
      fecha = b.getAttribute('data-fecha');
      txt('lw-cal-sel', 'Selected: ' + b.getAttribute('data-larga'));
      txt('lw-cal-hint', 'Pick a time below');
      abre();
    });
    var conf = $('lw-confirmar');
    if (conf) conf.addEventListener('click', function () {
      if (!fecha) {
        var p = cal.querySelector('.cal__d');
        if (p) { p.focus(); cal.scrollIntoView({behavior: 'smooth', block: 'center'}); }
        txt('lw-cal-hint', 'Pick a day first');
        return;
      }
      abre();
      wid.scrollIntoView({behavior: 'smooth', block: 'center'});
    });
  }());

  window.addEventListener('message', function (e) {
    if (e.origin !== 'https://calendly.com') return;
    if (!e.data || e.data.event !== 'calendly.event_scheduled') return;
    var m = CFG.modelos[S.villa];
    var pv = m ? Math.min(m.techos.sirap.eur, m.techos.bambu.eur) : 0;
    track('Lead', {content_name: 'Palm Field · ' + (m ? m.villa : ''),
      value: pv + CFG.tarifa * S.m2, currency: 'EUR'});
  });

  var ck = $('lw-cookies');
  if (ck) ck.addEventListener('click', function (ev) {
    ev.preventDefault();
    if (window.lwConsentReopen) window.lwConsentReopen();
  });

  // Estado desde la query (enlace compartible)
  var q = new URLSearchParams(location.search);
  var pl = parseInt(q.get('plot'), 10);
  if (<?= json_encode($PF_PARCELAS) ?>.indexOf(pl) !== -1) S.m2 = pl;
  var vq = q.get('villa'); if (vq && CFG.modelos[vq]) S.villa = vq;
  var cq = q.get('cur');   if (cq === 'EUR' || cq === 'AUD') S.div = cq;
  var rm = document.querySelector('input[name="pf-m2"][value="' + S.m2 + '"]');
  if (rm) rm.checked = true;
  var rv = document.querySelector('input[name="pf-villa"][value="' + S.villa + '"]');
  if (rv) rv.checked = true;
  document.querySelectorAll('.divisa').forEach(function (b) {
    b.classList.toggle('is-on', b.getAttribute('data-div') === S.div);
  });

  recalcular();
}());
</script>
</body>
</html>
