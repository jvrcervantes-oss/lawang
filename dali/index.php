<?php
/**
 * /dali — landing australiana de Villa Dali. 4-sep-2026.
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

require __DIR__ . '/datos.php';

$CAT   = lw_au_catalogo();
$DALI  = $CAT['dali'];
$OPC   = lw_picker_opciones();

$WA_NUM   = '6281138319862';
$WA_SHOW  = '+62 811-3831-9862';
$WA_TXT   = "Hi, I'm an Australian investor interested in Lawang villas in Bali.";
$WA_LINK  = 'https://wa.me/' . $WA_NUM . '?text=' . rawurlencode($WA_TXT);
$EMAIL    = 'sales@lawangproperties.com';
$CALENDLY = 'https://calendly.com/lawangproperties';

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

// Rejilla del calendario: días laborables REALES en hora de Bali. Si al mes en curso le
// quedan menos de 5, se pinta el siguiente — si no, quien entra un día 29 ve una rejilla
// casi entera en gris y parece que no hay agenda.
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

// Payload del configurador. Lista blanca campo a campo, con los precios YA resueltos en
// servidor: el JS pinta, no calcula precios de catálogo (revisión previa Seguridad+Diseño,
// 2-sep). Las tarifas de parcela salen de lw_picker_opciones(), fuente única.
$cfgJs = [
    'tasaAud'  => LW_AUD_TASA,
    'modelos'  => [],
    'tarifas'  => ['sumba' => $OPC['island']['sumba']['rate']],
    'extras'   => $OPC['extras'],
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
    ];
}
foreach ($OPC['view'] as $k => $vw) { $cfgJs['tarifas'][$k] = $vw['rate']; }

$JSON = JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT;
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>100% Freehold Architectural Villas in Bali &amp; Sumba — Lawang Tropical Properties</title>
<meta name="description" content="Turnkey architectural villas in Bali &amp; Sumba for Australian investors. Fixed-price written EPC contract, land ready with power, water and permits. From <?= lw_e(lw_aud_fmt($DALI['desde_eur'])) ?>.">
<link rel="canonical" href="https://lawangproperties.com/dali">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="100% Freehold Architectural Villas in Bali &amp; Sumba">
<meta property="og:description" content="Turnkey villas for Australian investors. Fixed price, land ready, permits cleared. From <?= lw_e(lw_aud_fmt($DALI['desde_eur'])) ?>.">
<meta property="og:url" content="https://lawangproperties.com/dali">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($ogImg) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<link rel="preload" as="image" href="<?= lw_e($ogImg) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Jost:wght@400;500;600;700&family=Space+Grotesk:wght@500;600;700&display=swap" rel="stylesheet">
<link href="https://assets.calendly.com/assets/external/widget.css" rel="stylesheet">
<script src="https://assets.calendly.com/assets/external/widget.js" defer></script>
<link rel="stylesheet" href="/assets/au-landing.css?v=20260904131317">
</head>
<body>

<header class="nav">
  <div class="wrap nav__in">
    <a href="/" aria-label="Lawang Tropical Properties">
      <img class="nav__brand" src="/assets/img/lawang-logo-v3.webp" alt="Lawang Tropical Properties">
    </a>
    <nav class="nav__links">
      <a href="#estimator">Instant Estimator</a>
      <a href="#land-ready">Land Ready Infrastructure</a>
      <a href="#benchmark">Bali vs Australia</a>
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
      <span class="pill pill--verde"><span class="dot"></span> 100% Freehold (Not 25-Yr Lease)</span>
      <span class="pill pill--lag">Direct Australian Investor Gate · PMA Custody</span>
      <span class="pill pill--terra">Q4 2026 Release Open</span>
    </div>

    <h1>100% Freehold Architectural Villas in Bali &amp; Sumba</h1>

    <p class="hero__sub">Fixed Price. Perpetual Title. Zero Leases. Fully Prepped Land with
      Subterranean Power &amp; Water Before You Break Ground.</p>

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
          <span class="chip__vl"><?= lw_e(lw_aud_fmt($DALI['desde_eur'])) ?></span>
        </span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 16v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5L21 16z"/></svg></span>
        <span>
          <span class="chip__lb">Direct Flight Access</span>
          <span class="chip__vl">3.5h Perth / 6h Syd</span>
        </span>
      </div>
    </div>

    <?php if (!$DALI['sinRender']): ?>
    <div class="mosaico">
      <figure>
        <img src="<?= lw_e($DALI['imgs'][0]) ?>" alt="Villa Dali pavilion with sukabumi stone pool, Lawang Tropical Properties" fetchpriority="high">
        <figcaption>
          <span class="mos__et">Featured Design</span>
          <span class="mos__tt">Villa Dali Pavilion with Sukabumi Pool</span>
          <span class="mos__sub">Freehold deed + fixed EPC contract included</span>
        </figcaption>
      </figure>
      <?php if (isset($DALI['imgs'][1])): ?>
      <figure>
        <img src="<?= lw_e($DALI['imgs'][1]) ?>" alt="Villa Dali interior, warm linen and teak finishes" loading="lazy">
        <figcaption><span class="mos__tt">Warm Linen &amp; Teak</span></figcaption>
      </figure>
      <?php endif; ?>
      <figure>
        <img src="/assets/img/lugar/costa.webp" alt="West coast of Bali, Lawang land" loading="lazy">
        <figcaption><span class="mos__tt">Bali West Coast</span></figcaption>
      </figure>
    </div>
    <?php endif; ?>
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
      <span class="pill pill--lag">Freehold Direct</span>
    </div>

    <div class="cal" id="lw-cal">
      <div class="cal__hd">
        <span class="cal__mes">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10z"/></svg>
          <?= lw_e($calIni->format('F Y')) ?> · Investment Slots
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

    <!-- Calendly de verdad: aparece al elegir día, ya situado en esa fecha y con los datos
         del formulario prellenados. Es quien tiene las horas libres y quien cierra la
         reserva — aquí no se inventa disponibilidad ni se confirma nada por nuestra cuenta. -->
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
      <label for="lw-email">Email Address (for calendar invite &amp; deed dossier)</label>
      <input id="lw-email" type="email" autocomplete="email" placeholder="name@domain.com.au">
    </div>

    <button class="btn btn--terra btn--block" type="button" id="lw-confirmar">
      Confirm Freehold Strategy Call
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

<!-- ═══ CONFIGURADOR ═══════════════════════════════════════════════════════════════ -->
<section class="sec sec--surface" id="estimator">
  <div class="wrap">
    <div class="et">
      <span class="pill pill--verde">5-Step</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">Instant Accurate Baseline</span>
    </div>
    <div class="sec__hd">
      <h2>Five questions, and you'll have an exact figure</h2>
      <p class="sec__desc">Select your villa size, roof finish, and land plot. Prices shown in
        your currency at a fixed rate of <?= lw_e(number_format(LW_AUD_TASA, 2)) ?> AUD/EUR
        (<?= lw_e(LW_AUD_FECHA) ?>) — the contract figure is the euro one.</p>
    </div>

    <div class="cfg">
      <!-- Pasos -->
      <div class="cfg__card">
        <div class="cfg__hd">
          <span class="cfg__paso" id="lw-paso-lb">Step 1 of 5</span>
          <span class="divisas" role="group" aria-label="Currency">
            <button type="button" class="divisa is-on" data-div="AUD">AUD ($)</button>
            <button type="button" class="divisa" data-div="EUR">EUR (€)</button>
          </span>
        </div>

        <!-- Paso 1: villa -->
        <div class="cfg__step" data-paso="1">
          <p class="cfg__q">Which villa?</p>
          <p class="cfg__nota">Identical German-grade engineering, sukabumi pool and ironwood
            decking standard across all models.</p>
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
                <b><?= lw_e(lw_aud_fmt($v['desde_eur'])) ?></b>
                <i><?= lw_e(lw_precio_fmt($v['desde_eur'])) ?></i>
              </span>
            </label>
            <?php endforeach; ?>
          </div>
        </div>

        <!-- Paso 2: techo -->
        <div class="cfg__step" data-paso="2" hidden>
          <p class="cfg__q">Which roof?</p>
          <p class="cfg__nota">Two complete villa prices, not an add-on: the roof you choose is
            the price of the villa.</p>
          <div class="ops" id="lw-techos"></div>
        </div>

        <!-- Paso 3: isla -->
        <div class="cfg__step" data-paso="3" hidden>
          <p class="cfg__q">Which island?</p>
          <p class="cfg__nota">Land is quoted per square metre and depends on where it sits.</p>
          <div class="ops">
            <label class="op">
              <input type="radio" name="lw-isla" value="bali" checked>
              <span><span class="op__nb">Bali</span><span class="op__sp">Tabanan &amp; Uluwatu · choose your view next</span></span>
              <span class="op__pr"><i>From <?= lw_e(lw_precio_fmt(lw_parcela_tarifa_m2('cliff'))) ?>/m²</i></span>
            </label>
            <label class="op">
              <input type="radio" name="lw-isla" value="sumba">
              <span><span class="op__nb">Sumba</span><span class="op__sp">Sumba Hills · subject to availability</span></span>
              <span class="op__pr"><i><?= lw_e(lw_precio_fmt(lw_parcela_tarifa_m2('sumba'))) ?>/m²</i></span>
            </label>
          </div>
        </div>

        <!-- Paso 4: vista -->
        <div class="cfg__step" data-paso="4" hidden>
          <p class="cfg__q">Which view?</p>
          <p class="cfg__nota">The land rate changes with the setting.</p>
          <div class="ops">
            <?php foreach ($OPC['view'] as $k => $vw): ?>
            <label class="op">
              <input type="radio" name="lw-vista" value="<?= lw_e($k) ?>"<?= $k === 'cliff' ? ' checked' : '' ?>>
              <span><span class="op__nb"><?= lw_e($vw['label']) ?></span></span>
              <span class="op__pr" data-eur-m2="<?= (int) $vw['rate'] ?>">
                <b><?= lw_e(lw_aud_fmt($vw['rate'])) ?>/m²</b>
                <i><?= lw_e(lw_precio_fmt($vw['rate'])) ?>/m²</i>
              </span>
            </label>
            <?php endforeach; ?>
          </div>
        </div>

        <!-- Paso 5: parcela -->
        <div class="cfg__step" data-paso="5" hidden>
          <p class="cfg__q">How much land?</p>
          <p class="cfg__nota">Sizes taken from the plots actually available today.</p>
          <div class="ops">
            <?php foreach ([160, 250, 350, 500] as $sz): ?>
            <label class="op">
              <input type="radio" name="lw-m2" value="<?= $sz ?>"<?= $sz === 160 ? ' checked' : '' ?>>
              <span><span class="op__nb"><?= $sz ?> m²</span></span>
              <span class="op__pr"></span>
            </label>
            <?php endforeach; ?>
          </div>
          <div class="m2">
            <label for="lw-m2-libre">Another size</label>
            <input id="lw-m2-libre" type="number" min="150" max="1500" step="10" placeholder="m²">
            <span class="op__sp">150–1,500 m². Larger plots are quoted on the call.</span>
          </div>
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
                  <span class="res__sub" id="lw-r-techo">Sirap Ulin roof</span></span>
            <span class="res__vl" id="lw-r-villa-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="lw-r-tierra">Bali · Cliff</span>
                  <span class="res__sub" id="lw-r-tierra-sub">Subdivided freehold · power &amp; water</span></span>
            <span class="res__vl" id="lw-r-tierra-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Civil Infra &amp; Approvals</span>
                  <span class="res__sub">Roads, PLN connection, building licences</span></span>
            <span class="res__vl">Included</span>
          </div>
        </div>

        <div class="total">
          <span class="total__lb">Total Freehold Investment</span>
          <span class="total__vl" id="lw-total">—</span>
          <span class="total__alt" id="lw-total-alt"></span>
          <p class="total__nota" id="lw-total-nota">Fixed-price written EPC contract. No
            contractor escalation clauses. Notary, permits and transfer costs are quoted
            separately.</p>
          <a class="btn btn--terra btn--block total__cta" href="#book">
            Lock Estimate &amp; Book 30-Min Call
          </a>
        </div>
        <p class="res__sync">Perth &amp; Sydney working hours · direct sync</p>
      </div>
    </div>
  </div>
</section>

<!-- ═══ COMPARATIVA ════════════════════════════════════════════════════════════════ -->
<section class="sec" id="benchmark">
  <div class="wrap">
    <div class="et">
      <span class="pill pill--canopy">Flight &amp; Capital Benchmark</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">CoreLogic 2024/2025 Data</span>
    </div>
    <div class="sec__hd">
      <h2>Closer than Sydney to Perth — at a Fraction of the Property Price</h2>
      <p class="sec__desc">Direct flight times from key Australian capitals and average median
        house price compared to a turnkey freehold villa in Bali &amp; Sumba (AUD).</p>
    </div>

    <div class="stats">
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 10.6V6h-2v7.4l5.2 3.1 1-1.7-4.2-2.2z"/></svg></span>
        <span><span class="chip__lb">Zero Jetlag from WA</span>
              <span class="chip__vl">Perth: 0h diff · 3h 40m flight</span></span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 18l2.3-2.3-4.9-4.9-4 4L2 7.4 3.4 6l6 6 4-4 6.3 6.3L22 12v6h-6z"/></svg></span>
        <span><span class="chip__lb">Entry Capital Efficiency</span>
              <span class="chip__vl">Up to 14x less capital</span></span>
      </div>
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zm10 9a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM5.4 19.4L19.4 5.4 18 4 4 18l1.4 1.4z"/></svg></span>
        <span><span class="chip__lb">Rental Yield Spread</span>
              <span class="chip__vl" style="color:var(--secondary)">14 – 18% ROI (vs ~3% AU)</span></span>
      </div>
    </div>

    <div class="tabla-caja">
      <div class="tabla-scroll">
        <table>
          <thead>
            <tr>
              <th>Australian City</th><th>Direct Flight Time</th><th>AU Median House</th>
              <th>Lawang Turnkey Freehold</th><th style="text-align:right">Capital Multiple</th>
            </tr>
          </thead>
          <tbody>
            <?php
              // Villa que se compara en cada fila. Perth se compara con Dali (la de entrada)
              // y el resto con Dune, igual que el diseño del owner.
              $filas = [
                ['SYD','Sydney','NSW · AEST','~6h 15m','Daily direct: Qantas, Jetstar, Virgin','1620000','dune','~14x More Affordable',false],
                ['MEL','Melbourne','VIC · AEST','~6h 00m','Daily direct: Jetstar, Virgin, Garuda','940000','dune','~8.5x More Affordable',false],
                ['PER','Perth','WA · AWST (0h time diff)','~3h 40m','Multiple daily: Jetstar, AirAsia, Batik','785000','dali','~10x More Affordable',true],
                ['BNE','Brisbane','QLD · AEST','~6h 10m','Daily direct: Virgin, Jetstar','890000','dune','~8x More Affordable',false],
                ['ADL','Adelaide','SA · ACST','~5h 15m','Direct seasonal &amp; 1-stop options','790000','dune','~7x More Affordable',false],
              ];
              foreach ($filas as $f):
                list($iata,$ciudad,$estado,$vuelo,$aerolineas,$mediana,$vid,$mult,$destaca) = $f;
                $vv = $CAT[$vid];
            ?>
            <tr<?= $destaca ? ' class="destacada"' : '' ?>>
              <td>
                <span class="ciudad">
                  <span class="iata<?= $destaca ? ' iata--on' : '' ?>"><?= lw_e($iata) ?></span>
                  <span><span class="cel-b"><?= lw_e($ciudad) ?></span>
                        <span class="cel-s"><?= $estado ?></span></span>
                </span>
              </td>
              <td><span class="cel-m"><?= lw_e($vuelo) ?></span><span class="cel-s"><?= $aerolineas ?></span></td>
              <td><span class="cel-m">~$<?= lw_e(number_format((int) $mediana, 0, '.', ',')) ?> AUD</span>
                  <span class="cel-s mono" style="font-size:9.5px">CoreLogic 2024/25</span></td>
              <td><span class="cel-m"><?= lw_e(lw_aud_fmt($vv['desde_eur'])) ?></span>
                  <span class="cel-s" style="color:var(--secondary);font-weight:600"><?= lw_e($vv['villa']) ?> + land included</span></td>
              <td style="text-align:right">
                <span class="pill <?= $destaca ? 'pill--verde' : 'pill--canopy' ?>"><?= lw_e($mult) ?></span>
                <span class="cel-s" style="margin-top:4px"><?= $destaca ? 'Zero jetlag · weekend commute' : '100% perpetual title' ?></span>
              </td>
            </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
      <div class="tabla-pie">
        <span>Australian benchmark figures based on CoreLogic capital city median dwelling data
          (2024/2025). Villa figures include 100% freehold land + turnkey architectural build,
          converted at <?= lw_e(number_format(LW_AUD_TASA, 2)) ?> AUD/EUR (<?= lw_e(LW_AUD_FECHA) ?>).</span>
        <a class="btn btn--lag" href="#book">Lock Strategy Slot</a>
      </div>
    </div>
  </div>
</section>

<!-- ═══ LAND READY ═════════════════════════════════════════════════════════════════ -->
<section class="sec sec--cont" id="land-ready">
  <div class="wrap" style="text-align:center">
    <div class="et" style="justify-content:center">
      <span class="pill pill--canopy">Zero Bureaucratic Risk</span>
    </div>
    <h2 style="max-width:22ch;margin-inline:auto">We Buy The Land, Subdivide, Pipe Utilities
      &amp; Clear Permits. You Own It Freehold.</h2>
    <p class="sec__desc" style="max-width:64ch;margin-inline:auto">Australian investors never
      deal with village negotiations or missing electric poles. Groundbreaking within 14 days
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
        <span class="pill pill--terra">Direct Australian Investor Desk</span>
        <span class="mono" style="font-size:11px;color:#6EE7B7">Sydney (AEST) &amp; Perth (AWST)</span>
      </div>
      <h2>Ready to Review Freehold Coordinates &amp; Pricing?</h2>
      <p>In 30 minutes, our desk will walk you through available surveyed freehold coordinates,
        notary deed proofs, infrastructure videos, and exact fixed turnkey costs in AUD.</p>
      <div class="cta__garantias">
        <span class="cta__g"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> 100% Freehold perpetual title guarantee</span>
        <span class="cta__g"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> Guaranteed fixed-price written EPC contract</span>
      </div>
    </div>
    <div class="cta__btns">
      <a class="btn btn--terra" href="#book">Select Strategy Slot ↑</a>
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
          Tabanan, Uluwatu, and Sumba for Australian investors.</p>
        <div class="pie__sellos">
          <span class="sello">100% Freehold — PMA Foreign Legal Custody</span>
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
          <span class="sello">Australian Desk</span>
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
    <b id="lw-movil-pr"><?= lw_e(lw_aud_fmt($DALI['desde_eur'])) ?></b>
    <span>100% Freehold Bali</span>
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

  // ── Píxel ────────────────────────────────────────────────────────────────────────
  // Mismo criterio que /modelo/<id>: `Lead` NO se dispara aquí. Sale del postMessage de
  // Calendly, que es el único sitio donde consta que una cita existe de verdad.
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

  // ── Estado ───────────────────────────────────────────────────────────────────────
  var S = {villa: 'dali', techo: 'sirap', isla: 'bali', vista: 'cliff', m2: 160, div: 'AUD'};
  var PASOS = 5, paso = 1;

  function eur(n) { return '€' + Number(n).toLocaleString('en-US'); }
  function aud(n) { return '$' + Math.round(n * CFG.tasaAud / 10) * 10 + ' AUD'; }
  function audFmt(n) {
    return '$' + (Math.round(n * CFG.tasaAud / 10) * 10).toLocaleString('en-US') + ' AUD';
  }
  // El importe se pinta en la divisa elegida y SIEMPRE con la otra debajo: el contrato se
  // firma en euros, así que el AUD nunca puede quedarse solo en pantalla.
  function pinta(n) { return S.div === 'AUD' ? audFmt(n) : eur(n); }
  function alterna(n) { return S.div === 'AUD' ? eur(n) : audFmt(n); }

  function tarifa() {
    if (S.isla === 'sumba') return CFG.tarifas.sumba;
    return CFG.tarifas[S.vista] != null ? CFG.tarifas[S.vista] : null;
  }
  function precioVilla() {
    var m = CFG.modelos[S.villa];
    return m && m.techos[S.techo] ? m.techos[S.techo].eur : null;
  }

  // ── Pintado del resumen ──────────────────────────────────────────────────────────
  function $(id) { return document.getElementById(id); }
  function txt(id, s) { var e = $(id); if (e) e.textContent = s; }

  function recalcular() {
    var m = CFG.modelos[S.villa];
    if (!m) return;
    var pv = precioVilla(), tf = tarifa();
    var parcela = (tf != null && S.m2) ? tf * S.m2 : null;
    var total   = (pv != null && parcela != null) ? pv + parcela : null;

    txt('lw-r-villa', m.villa);
    txt('lw-r-techo', m.techos[S.techo].nombre + ' roof');
    txt('lw-r-villa-pr', pv != null ? pinta(pv) : '—');

    var donde = S.isla === 'sumba' ? 'Sumba'
      : 'Bali · ' + S.vista.charAt(0).toUpperCase() + S.vista.slice(1);
    txt('lw-r-tierra', donde + (S.m2 ? ' (' + S.m2 + ' m²)' : ''));
    txt('lw-r-tierra-sub', tf != null
      ? 'Subdivided freehold · ' + pinta(tf) + '/m²'
      : 'Choose a view to price the land');
    var tp = $('lw-r-tierra-pr');
    if (tp) {
      tp.textContent = parcela != null ? pinta(parcela) : 'Pending';
      tp.classList.toggle('res__vl--pend', parcela == null);
    }

    txt('lw-total', total != null ? pinta(total) : '—');
    txt('lw-total-alt', total != null ? '≈ ' + alterna(total) : '');
    txt('lw-movil-pr', pv != null ? pinta(pv) : '—');

    // El pie del total nombra lo que queda fuera. Si no, ver el total quieto con extras
    // marcados se lee como que van incluidos.
    var nota = 'Fixed-price written EPC contract. No contractor escalation clauses. ';
    nota += total != null
      ? 'Notary, permits and transfer costs are quoted separately.'
      : 'Complete the five steps for the full figure.';
    txt('lw-total-nota', nota);

    // Los precios del paso 1 y del paso 4 se repintan en la divisa activa.
    document.querySelectorAll('.op__pr[data-eur]').forEach(function (n) {
      var v = Number(n.getAttribute('data-eur'));
      n.querySelector('b').textContent = pinta(v);
      n.querySelector('i').textContent = alterna(v);
    });
    document.querySelectorAll('.op__pr[data-eur-m2]').forEach(function (n) {
      var v = Number(n.getAttribute('data-eur-m2'));
      n.querySelector('b').textContent = pinta(v) + '/m²';
      n.querySelector('i').textContent = alterna(v) + '/m²';
    });

    sincronizaURL();
    actualizaWa();
  }

  // ── Paso 2 (techos): se repinta al cambiar de villa ──────────────────────────────
  function pintaTechos() {
    var m = CFG.modelos[S.villa], cont = $('lw-techos');
    if (!m || !cont) return;
    cont.innerHTML = '';
    ['sirap', 'bambu'].forEach(function (k) {
      var t = m.techos[k];
      var l = document.createElement('label');
      l.className = 'op';
      var marcado = k === S.techo ? ' checked' : '';
      l.innerHTML =
        '<input type="radio" name="lw-techo" value="' + k + '"' + marcado + '>' +
        '<span><span class="op__nb"></span></span>' +
        '<span class="op__pr" data-eur="' + t.eur + '"><b></b><i></i></span>';
      l.querySelector('.op__nb').textContent = t.nombre;
      l.querySelector('b').textContent = pinta(t.eur);
      l.querySelector('i').textContent = alterna(t.eur);
      cont.appendChild(l);
    });
  }

  // ── Navegación por pasos ─────────────────────────────────────────────────────────
  function visible(n) {
    // El paso 4 (vista) solo aplica a Bali: en Sumba la tarifa no depende de la vista.
    if (n === 4 && S.isla === 'sumba') return false;
    return true;
  }
  function muestraPaso(n) {
    paso = n;
    document.querySelectorAll('.cfg__step').forEach(function (s) {
      s.hidden = Number(s.getAttribute('data-paso')) !== n;
    });
    txt('lw-paso-lb', 'Step ' + n + ' of ' + PASOS);
    var a = $('lw-atras'); if (a) a.hidden = n === 1;
    var sig = $('lw-siguiente');
    if (sig) sig.firstChild.textContent = n === PASOS ? 'See full estimate ' : 'Next ';
    var p = $('lw-puntos');
    if (p) {
      p.innerHTML = '';
      for (var i = 1; i <= PASOS; i++) {
        var d = document.createElement('span');
        d.className = 'punto' + (i === n ? ' is-on' : '');
        p.appendChild(d);
      }
    }
  }
  function avanza(dir) {
    var n = paso;
    do { n += dir; } while (n > 0 && n <= PASOS && !visible(n));
    if (n < 1) n = 1;
    if (n > PASOS) { // último paso: al resumen
      document.querySelector('.res').scrollIntoView({behavior: 'smooth', block: 'center'});
      return;
    }
    muestraPaso(n);
  }
  var sig = $('lw-siguiente'); if (sig) sig.addEventListener('click', function () { avanza(1); });
  var atr = $('lw-atras');     if (atr) atr.addEventListener('click', function () { avanza(-1); });

  // ── Entradas ─────────────────────────────────────────────────────────────────────
  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t || t.type !== 'radio') return;
    if (t.name === 'lw-villa') { S.villa = t.value; pintaTechos(); }
    else if (t.name === 'lw-techo') S.techo = t.value;
    else if (t.name === 'lw-isla')  S.isla  = t.value;
    else if (t.name === 'lw-vista') S.vista = t.value;
    else if (t.name === 'lw-m2') {
      S.m2 = Number(t.value);
      var lib = $('lw-m2-libre'); if (lib) lib.value = '';
    } else return;
    recalcular();
  });

  var libre = $('lw-m2-libre');
  if (libre) libre.addEventListener('input', function () {
    var v = parseInt(libre.value, 10);
    if (!isNaN(v) && v >= 150 && v <= 1500) {
      S.m2 = v;
      document.querySelectorAll('input[name="lw-m2"]').forEach(function (r) { r.checked = false; });
      recalcular();
    }
  });

  document.querySelectorAll('.divisa').forEach(function (b) {
    b.addEventListener('click', function () {
      document.querySelectorAll('.divisa').forEach(function (o) { o.classList.remove('is-on'); });
      b.classList.add('is-on');
      S.div = b.getAttribute('data-div');
      recalcular();
    });
  });

  // ── URL compartible ──────────────────────────────────────────────────────────────
  // Se PARTE de la query que ya hay y solo se borran las claves propias: barrerla entera
  // se llevaría `utm_*` y `fbclid`, que es de donde sale la atribución de la campaña.
  function sincronizaURL() {
    var p = new URLSearchParams(location.search);
    ['villa', 'roof', 'island', 'view', 'plot', 'cur'].forEach(function (k) { p.delete(k); });
    if (S.villa !== 'dali')  p.set('villa', S.villa);
    if (S.techo !== 'sirap') p.set('roof', S.techo);
    if (S.isla  !== 'bali')  p.set('island', S.isla);
    if (S.vista !== 'cliff') p.set('view', S.vista);
    if (S.m2    !== 160)     p.set('plot', String(S.m2));
    if (S.div   !== 'AUD')   p.set('cur', S.div);
    var q = p.toString();
    history.replaceState(history.state, '', '/dali' + (q ? '?' + q : ''));
  }
  function aplicaQuery() {
    var q = new URLSearchParams(location.search);
    var v = q.get('villa'); if (v && CFG.modelos[v]) S.villa = v;
    var r = q.get('roof');  if (r === 'sirap' || r === 'bambu') S.techo = r;
    var i = q.get('island');if (i === 'bali' || i === 'sumba')  S.isla = i;
    var w = q.get('view');  if (w && CFG.tarifas[w] != null)    S.vista = w;
    var pl = parseInt(q.get('plot'), 10);
    if (!isNaN(pl) && pl >= 150 && pl <= 1500) S.m2 = pl;
    var c = q.get('cur');   if (c === 'EUR' || c === 'AUD')     S.div = c;

    var rb = document.querySelector('input[name="lw-villa"][value="' + S.villa + '"]');
    if (rb) rb.checked = true;
    var ri = document.querySelector('input[name="lw-isla"][value="' + S.isla + '"]');
    if (ri) ri.checked = true;
    var rv = document.querySelector('input[name="lw-vista"][value="' + S.vista + '"]');
    if (rv) rv.checked = true;
    var rm = document.querySelector('input[name="lw-m2"][value="' + S.m2 + '"]');
    if (rm) rm.checked = true;
    else if (libre) libre.value = S.m2;
    document.querySelectorAll('.divisa').forEach(function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-div') === S.div);
    });
  }

  // ── WhatsApp: el texto lleva la configuración vigente ────────────────────────────
  // Se lee del estado en cada cambio, nunca de un valor capturado al cargar: si no, a
  // ventas le llega "interested in the Villa Dali" con la configuración de otra villa.
  function actualizaWa() {
    var m = CFG.modelos[S.villa];
    if (!m) return;
    var t = "Hi, I'm an Australian investor interested in the " + m.villa + '.';
    var pv = precioVilla(), tf = tarifa();
    if (pv != null) t += ' ' + m.techos[S.techo].nombre + ' roof, ' + eur(pv) + '.';
    if (tf != null && S.m2) t += ' Plot: ' + (S.isla === 'sumba' ? 'Sumba' : 'Bali/' + S.vista)
      + ', ' + S.m2 + ' m².';
    var href = 'https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(t);
    document.querySelectorAll('a[href*="wa.me/"]').forEach(function (a) { a.href = href; });
  }

  // ── Calendario -> Calendly ───────────────────────────────────────────────────────
  (function () {
    var cal = $('lw-cal'), wid = $('lw-wid');
    if (!cal || !wid) return;
    var fecha = null;

    function abre() {
      if (!fecha) return;
      var u = CALENDLY + '?hide_gdpr_banner=1&background_color=FAF7F0&text_color=22282A'
            + '&primary_color=104C4F&month=' + fecha.slice(0, 7) + '&date=' + fecha;
      // Prellenado: Calendly acepta `name` y `email` por query. Le ahorra al lead teclear
      // dos veces lo que ya escribió aquí arriba.
      var n = ($('lw-nombre') || {}).value, e = ($('lw-email') || {}).value;
      if (n) u += '&name=' + encodeURIComponent(n);
      if (e) u += '&email=' + encodeURIComponent(e);

      wid.classList.add('is-on');
      // Se reconstruye el iframe con initInlineWidget en vez de tocarle el `src`: el widget
      // guarda estado interno y cambiárselo por debajo lo deja mudo, o sea deja de emitir
      // el postMessage de reserva — que es lo único que confirma que la cita existe.
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

  // ── Reserva confirmada DE VERDAD: la anuncia Calendly, no nosotros ───────────────
  window.addEventListener('message', function (e) {
    // Igualdad exacta, no indexOf: con substring, "https://calendly.com.attacker.example"
    // también contendría "calendly.com" y colaría un Lead falso.
    if (e.origin !== 'https://calendly.com') return;
    if (!e.data || e.data.event !== 'calendly.event_scheduled') return;
    var pv = precioVilla(), tf = tarifa();
    var total = (pv != null && tf != null && S.m2) ? pv + tf * S.m2 : pv;
    track('Lead', {content_name: (CFG.modelos[S.villa] || {}).villa || 'Villa Dali',
      value: total || 0, currency: 'EUR'});
  });

  // ── Cookies ──────────────────────────────────────────────────────────────────────
  var ck = $('lw-cookies');
  if (ck) ck.addEventListener('click', function (ev) {
    ev.preventDefault();
    if (window.lwConsentReopen) window.lwConsentReopen();
  });

  // ── Arranque ─────────────────────────────────────────────────────────────────────
  aplicaQuery();
  pintaTechos();
  muestraPaso(1);
  recalcular();
}());
</script>
</body>
</html>
