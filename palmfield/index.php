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
 *
 * ── 7-sep-2026: el configurador vuelve a ser por PASOS, sin parcela ni isla ────────────
 * Encargo del owner: «restablécelo quitando la parte de Land e island, quiero que avance
 * clicando y faltan los extras». El estimador de una sola pantalla (parcela + villa) pasa a
 * los tres pasos que ya tenía /dali —villa → techo → extras— con dos cambios de fondo:
 *   · **La parcela sale del cálculo.** El total es villa (con su techo) + extras. La tarifa
 *     de 125 €/m² sigue publicada, en el resumen y bajo el total, como línea aparte que se
 *     dimensiona en la llamada. Es lo que pidió el owner; si algún día se quiere volver a
 *     sumar, es una fila más en el resumen, no una reescritura.
 *   · **Avanza al hacer clic** en villa o techo. El paso de extras NO avanza solo: es
 *     multiselección y saltar al primer tick impediría marcar el segundo. Ahí el botón pasa
 *     a «See my figure» y baja al resumen.
 * Vuelve además la **tabla comparativa de vuelos y precio de vivienda en Australia**
 * (`#benchmark`), que /dali sí tenía y esta página perdió al nacer. Su columna de Lawang
 * ahora SÍ incluye la parcela que su rótulo promete (villa + la parcela más pequeña
 * disponible), en vez del precio de la villa a secas bajo un «+ land included».
 *
 * Precios: price list del owner (Google Sheet «UPDATED: SEPTEMBER 2026», leído el 7-sep).
 * Los de 2027 se ignoran por orden suya. Los siete extras y sus importes por modelo viven en
 * `modelo/modelos.php`; su nombre y descripción, en `lw_extras_meta()` de `modelo/datos.php`.
 *
 * ── 7-sep-2026 (2ª pasada): móvil primero, menos texto y titulares grandes ────────────
 * Encargo del owner: «la gran mayoría van a entrar por móvil; necesito mucho menos texto en
 * toda la web y claridad con títulos llamativos y grandes». Medido en producción a 390px
 * ANTES de tocar: 10,8 pantallas de scroll, el hero se llevaba 2,8 con 207 palabras, y en la
 * primera pantalla no entraba ni una foto. Los titulares caían a 30/26px sobre un cuerpo de
 * 15-16px — el «salto brutal de escala» del catálogo no existía en móvil (sí en escritorio).
 * Lo que se hizo, por orden de impacto:
 *   1. **El texto que sobraba, fuera** — no acortado, eliminado: el 2º párrafo del hero
 *      repetía punto por punto la sección «We do the land» de más abajo, y la píldora
 *      «Direct Australian Investor Gate · PMA Custody» dice lo mismo que el escritorio
 *      australiano del final. Los cuatro pasos del proyecto pasan a una línea cada uno; el
 *      detalle técnico ya vive en su `paso__pie`.
 *   2. **Titulares cortos**, porque un titular grande solo cabe si es corto. «We Buy The
 *      Land, Subdivide, Pipe Utilities & Clear Permits. You Own It Freehold.» ocupaba
 *      CUATRO líneas a 26px en un móvil.
 *   3. Escala y orden, en `assets/au-landing.css` (lo comparte /dali, verificar las dos).
 * **Lo que NO se toca al recortar** y hay que respetar en la siguiente pasada: el tipo de
 * cambio con su fecha, «plot sized on the call», la fecha de la lista de parcelas, los pies
 * de foto que dicen si es render o foto real, y el vocabulario de LAW-122. Son las líneas
 * que evitan que la página mienta, no relleno.
 */

require __DIR__ . '/../modelo/datos.php';

$CAT = lw_au_catalogo();

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
        // Los extras van POR MODELO porque dos de los siete escalan con la villa. El JS los
        // pinta desde aquí: si un modelo llegara sin ellos, su paso 3 sale vacío en vez de
        // heredar los precios de otro modelo.
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
<script src="/assets/idioma-web.js?v=20260908111654"></script>
<script src="/assets/i18n-landing.js?v=20260908112452" defer></script>
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
<link rel="stylesheet" href="/assets/au-landing.css?v=20260907173345">
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
      <a href="#desk">Perth &amp; Sydney Desk</a>
    </nav>
    <div class="nav__cta">
      <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer">
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
        <span>WhatsApp Desk</span>
      </a>
      <?php /* 7-sep-2026: era una flecha generica. Un calendario dice a donde lleva el
               boton antes de pulsarlo, y en movil (donde el <span> se oculta por debajo de
               560px) el icono es LO UNICO que queda: una flecha ahi no significa nada. */ ?>
      <a class="btn btn--terra" href="#book">
        <span>Schedule Call</span>
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10zM7 12h5v5H7v-5z"/></svg>
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
      <?php /* 7-sep-2026: eran TRES píldoras y en el móvil se apilaban en tres líneas por
               encima del titular. «Direct Australian Investor Gate · PMA Custody» sale de
               aquí — es jerga, y lo mismo ya lo dice la sección del escritorio australiano
               al final. Las dos que quedan son las dos cosas que un comprador pregunta
               primero: qué compra y cuándo lo tiene. */ ?>
      <span class="pill pill--verde"><span class="dot"></span> Freehold (HGB)</span>
      <span class="pill pill--terra">Handover <?= lw_e($PF_ENTREGA) ?></span>
    </div>

    <h1>Palm Field</h1>

    <?php
      // ── El gancho (opción A del owner, 7-sep-2026) ───────────────────────────────────
      // La pregunta funciona porque la propia página la demuestra cinco pantallas más
      // abajo: la tabla #benchmark ya publica la mediana de Perth (785.000 AUD, CoreLogic
      // 2024/25). Sacar ese argumento al hero es usar el dato que ya estaba enterrado.
      //
      // ⚠️ Y por eso la línea de debajo NO es relleno: «el precio de una entrada en Perth»
      // solo es cierto con un porcentaje concreto. Al 20% son 157.140 AUD y la entrada de
      // Palm Field (128.390) cabe holgada; al 10% (78.514) NO cabe y la frase sería falsa.
      // Se publica el porcentaje y las dos cifras para que la afirmación se pueda
      // comprobar sin fiarse — mismo criterio que el resto de la página, y el que pide un
      // público australiano (ACL s18, ver LAW-122).
      // Las dos cifras se CALCULAN de las mismas constantes que pinta la tabla; si mañana
      // cambia el tipo de cambio o el precio de entrada, esta frase cambia sola en vez de
      // quedarse mintiendo.
      $PF_PERTH_MEDIANA = 785000;   // AUD · CoreLogic 2024/25, la misma fila que #benchmark
      $PF_PERTH_ENTRADA = 0.20;     // el % que hace cierta la comparación; si baja, no cabe
      $pfEntradaPerth   = (int) round($PF_PERTH_MEDIANA * $PF_PERTH_ENTRADA);
      $pfDesdeAud       = lw_aud($desdeTotal);
    ?>
    <p class="hero__gancho">What could you own in Bali for the price of a Perth deposit?</p>

    <p class="hero__sub">Palm Field starts at
      <b><?= lw_e(lw_aud_fmt($desdeTotal)) ?></b> with the freehold plot included — less than
      the <?= (int) round($PF_PERTH_ENTRADA * 100) ?>% deposit on a median Perth house
      ($<?= lw_e(number_format($pfEntradaPerth, 0, '.', ',')) ?> AUD).</p>

    <div class="hero__cta">
      <a class="btn btn--terra" href="#estimator">See Your Figure</a>
      <a class="btn btn--lag" href="#book">
        <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10zM7 12h5v5H7v-5z"/></svg>
        Book a Call
      </a>
    </div>

    <div class="chips">
      <div class="chip">
        <span class="chip__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-1.2 15L7 12.2l1.4-1.4 2.4 2.4 5-5L17.2 9l-6.4 7z"/></svg></span>
        <span><span class="chip__lb">Tenure</span>
              <span class="chip__vl">Freehold · HGB</span></span>
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
      <?php /* Cada pie dice si es render o foto real — misma regla que /modelo/<id>. Aquí
               importa el doble: Palm Field entrega en Q1 2027, así que una vista aérea del
               complejo terminado SIN rotular se lee como que ya está construido. Y la foto
               del solar no es «tu villa», es la explanación: mal rotulada engaña, bien
               rotulada es la prueba de que la infraestructura existe de verdad. */ ?>
      <figure>
        <img src="<?= lw_e($IMG_AEREA) ?>" alt="Palm Field masterplan visualisation: villas laid out between the river and the rice terraces, Balian Hills, Bali" fetchpriority="high">
        <figcaption>
          <span class="mos__et">Masterplan · visualisation</span>
          <span class="mos__tt">Palm Field, Balian Hills</span>
          <span class="mos__sub">Private pool villas between the river and the rice terraces</span>
        </figcaption>
      </figure>
      <figure>
        <img src="<?= lw_e($IMG_2) ?>" alt="Palm Field site: terracing, retaining walls and drainage under construction" loading="lazy">
        <figcaption>
          <span class="mos__tt">The land, already worked</span>
          <span class="mos__sub">Site photo · terracing and retaining walls</span>
        </figcaption>
      </figure>
      <figure>
        <img src="<?= lw_e($IMG_3) ?>" alt="Villa model at Palm Field, evening" loading="lazy">
        <figcaption>
          <span class="mos__tt">Your own villa</span>
          <span class="mos__sub">Render · Palm Field</span>
        </figcaption>
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

    <?php /* 7-sep-2026: los tres campos y el boton nacen ocultos y aparecen al elegir dia.
             Antes se veian de entrada: pedirle el telefono a alguien que todavia no sabe si
             hay hueco es pedir antes de dar. `hidden` de HTML, no display:none en CSS, para
             que el navegador tampoco los cuente al tabular ni el lector de pantalla los lea
             mientras no existan. */ ?>
    <div id="lw-form" hidden>
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
    </div>

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
      <span class="pill pill--verde">3-Step</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">Pick an option and it moves on</span>
    </div>
    <div class="sec__hd">
      <h2>Three questions. Your figure.</h2>
    </div>

    <div class="cfg">
      <!-- Pasos -->
      <div class="cfg__card">
        <div class="cfg__hd">
          <span class="cfg__paso" id="pf-paso-lb">Step 1 of 3</span>
          <span class="divisas" role="group" aria-label="Currency">
            <button type="button" class="divisa is-on" data-div="AUD">AUD ($)</button>
            <button type="button" class="divisa" data-div="EUR">EUR (€)</button>
          </span>
        </div>

        <!-- Paso 1: villa -->
        <div class="cfg__step" data-paso="1">
          <p class="cfg__q">Which villa?</p>
          <p class="cfg__nota">All five models can be built on any Palm Field plot. The price
            shown is the villa with its cheaper roof; you pick the roof next.</p>
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

        <!-- Paso 2: techo. Lo pinta el JS: el precio es el de la villa ya elegida. -->
        <div class="cfg__step" data-paso="2" hidden>
          <p class="cfg__q">Which roof?</p>
          <p class="cfg__nota">What each finish adds over the base roof. Both are complete villa
            prices, not add-ons — the full figure is on the right.</p>
          <div class="ops" id="pf-techos"></div>
        </div>

        <!-- Paso 3: extras. Multiseleccion, asi que este NO avanza solo al hacer clic. -->
        <div class="cfg__step" data-paso="3" hidden>
          <p class="cfg__q">Any extras?</p>
          <p class="cfg__nota">Optional, and none of them is needed to move in. Tick as many as
            you want — the figure on the right updates as you go.</p>
          <div class="ops" id="pf-extras"></div>
        </div>

        <div class="cfg__nav">
          <button type="button" class="cfg__atras" id="pf-atras" hidden>← Back</button>
          <span class="puntos" id="pf-puntos" aria-hidden="true"></span>
          <button type="button" class="btn btn--lag" id="pf-siguiente">
            Next <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 5l7 7-7 7v-4H4v-6h9V5z"/></svg>
          </button>
        </div>
      </div>

      <!-- Resumen en vivo -->
      <div class="res">
        <div class="res__card">
          <div class="res__hd">
            <span class="res__tt">Your Palm Field figure</span>
            <span class="pill pill--canopy">Freehold</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="pf-r-villa">Villa</span>
                  <span class="res__sub" id="pf-r-villa-sub">Turnkey build</span></span>
            <span class="res__vl" id="pf-r-villa-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb" id="pf-r-extras">Extras</span>
                  <span class="res__sub" id="pf-r-extras-sub">None selected</span></span>
            <span class="res__vl" id="pf-r-extras-pr">—</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Roads &amp; approvals</span>
                  <span class="res__sub">PBG / SLF licences, PLN connection</span></span>
            <span class="res__vl">Included</span>
          </div>
          <div class="res__fila">
            <span><span class="res__lb">Freehold plot</span>
                  <span class="res__sub"><?= lw_e(lw_precio_fmt($PF_TARIFA)) ?>/m² · sized on the call</span></span>
            <span class="res__vl">Separate</span>
          </div>
        </div>

        <div class="total">
          <span class="total__lb">Villa turnkey, your spec</span>
          <span class="total__vl" id="pf-total">—</span>
          <span class="total__alt" id="pf-total-alt"></span>
          <a class="btn btn--terra btn--block total__cta" href="#book">
            Book a 30-Min Call on This Figure
          </a>
        </div>
        <p class="res__sync">AUD at <?= lw_e(number_format(LW_AUD_TASA, 2)) ?>
          (<?= lw_e(LW_AUD_FECHA) ?>) · contract in EUR · plot apart</p>
      </div>
    </div>
  </div>
</section>

<!-- ═══ COMPARATIVA ════════════════════════════════════════════════════════════════ -->
<?php
  // Columna "Palm Field Turnkey Freehold" de la tabla: villa + la parcela MAS PEQUEÑA
  // disponible hoy. En /dali esta misma columna ponia solo el precio de la villa bajo el
  // rotulo "+ land included" — decia una cosa y sumaba otra. Aqui la cifra incluye de
  // verdad la parcela que el rotulo promete, y el rotulo dice de que tamaño es.
  $pfMin = min($PF_PARCELAS);
?>
<section class="sec" id="benchmark">
  <div class="wrap">
    <div class="et">
      <span class="pill pill--canopy">Flight &amp; Capital Benchmark</span>
      <span class="mono" style="font-size:11px;color:var(--ink2)">CoreLogic 2024/2025 Data</span>
    </div>
    <div class="sec__hd">
      <h2>Closer than Perth. A fraction of the price.</h2>
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
              <th>Palm Field Turnkey Freehold</th><th style="text-align:right">Capital Multiple</th>
            </tr>
          </thead>
          <tbody>
            <?php
              // Villa que se compara en cada fila. Perth se compara con Dali (la de entrada)
              // y el resto con Dune, igual que el diseño del owner en /dali.
              $filas = [
                ['SYD','Sydney','NSW · AEST','~6h 15m','Daily direct: Qantas, Jetstar, Virgin','1620000','dune','~14x More Affordable',false],
                ['MEL','Melbourne','VIC · AEST','~6h 00m','Daily direct: Jetstar, Virgin, Garuda','940000','dune','~8.5x More Affordable',false],
                ['PER','Perth','WA · AWST (0h time diff)','~3h 40m','Multiple daily: Jetstar, AirAsia, Batik','785000','dali','~10x More Affordable',true],
                ['BNE','Brisbane','QLD · AEST','~6h 10m','Daily direct: Virgin, Jetstar','890000','dune','~8x More Affordable',false],
                ['ADL','Adelaide','SA · ACST','~5h 15m','Direct seasonal &amp; 1-stop options','790000','dune','~7x More Affordable',false],
              ];
              foreach ($filas as $f):
                list($iata,$ciudad,$estado,$vuelo,$aerolineas,$mediana,$vid,$mult,$destaca) = $f;
                $vv    = $CAT[$vid];
                $vvTot = $vv['desde_eur'] + $PF_TARIFA * $pfMin;
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
              <td><span class="cel-m"><?= lw_e(lw_aud_fmt($vvTot)) ?></span>
                  <span class="cel-s" style="color:var(--secondary);font-weight:600"><?= lw_e($vv['villa']) ?> + <?= (int) $pfMin ?> m² plot</span></td>
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
        <span>Australian figures: CoreLogic capital city median dwelling, 2024/25. Palm Field
          includes the freehold plot (<?= (int) $pfMin ?> m², smallest available
          <?= lw_e(LW_PF_PARCELAS_FECHA) ?>) plus the turnkey build, at
          <?= lw_e(number_format(LW_AUD_TASA, 2)) ?> AUD/EUR
          (<?= lw_e(LW_AUD_FECHA) ?>).</span>
        <a class="btn btn--lag" href="#book">Lock Strategy Slot</a>
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
    <h2 style="max-width:18ch;margin-inline:auto">We do the land. You own it freehold.</h2>

    <div class="pasos" style="text-align:left">
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1L3 5v6c0 5.6 3.8 10.7 9 12 5.2-1.3 9-6.4 9-12V5l-9-4zm-1.2 15L7 12.2l1.4-1.4 2.4 2.4 5-5L17.2 9l-6.4 7z"/></svg></span>
        <span class="paso__n">01 · Title Deed</span>
        <h3>Clean Freehold Acquisition</h3>
        <p>Bought outright, clean notary titles, subdivided and ready to transfer under PMA
          custody.</p>
        <span class="paso__pie">HGB</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2v11h3v9l7-12h-4l4-8z"/></svg></span>
        <span class="paso__n">02 · Utilities</span>
        <h3>Underground Power &amp; Water</h3>
        <p>PLN power underground — no wires across the view — plus deep potable wells.</p>
        <span class="paso__pie">PLN 3,500W+ Active</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h2v16H4V4zm7 0h2v16h-2V4zm7 0h2v16h-2V4z"/></svg></span>
        <span class="paso__n">03 · Civil Works</span>
        <h3>Paved Access Roads</h3>
        <p>Grading, retaining walls, drainage and paved road up to your parcel.</p>
        <span class="paso__pie">Direct Heavy Vehicle Access</span>
      </div>
      <div class="paso">
        <span class="paso__ico"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg></span>
        <span class="paso__n">04 · Legal Approvals</span>
        <h3>PBG &amp; SLF Building Licences</h3>
        <p>Municipal building licences and Pariwisata tourism zoning, already approved.</p>
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
      <h2>Ready to see your plot?</h2>
      <p>Thirty minutes: the plots still free, the notary deeds, drone footage of the site
        today, and your fixed turnkey cost in AUD.</p>
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
    <b id="pf-movil"><?= lw_e(lw_aud_fmt($desdeVilla)) ?></b>
    <span>Palm Field · villa turnkey</span>
  </span>
  <a class="btn btn--terra" href="#book">Book Call</a>
  <a class="btn btn--wa" href="<?= lw_e($WA_LINK) ?>" target="_blank" rel="noopener noreferrer" aria-label="Chat on WhatsApp">
    <svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M17.5 14.4c-.3-.2-1.7-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.7 1-.9 1.2-.2.2-.3.2-.6.1-.3-.2-1.2-.5-2.3-1.4-.9-.8-1.4-1.7-1.6-2-.2-.3 0-.5.1-.6l.5-.5c.1-.2.2-.3.3-.5 0-.2 0-.4-.1-.5l-1-2.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.4s1.1 2.8 1.2 3c.2.2 2.1 3.2 5.1 4.4 1.9.7 2.5.8 3.4.7.6-.1 1.7-.7 1.9-1.4.2-.7.2-1.2.2-1.4-.1-.1-.3-.2-.6-.3zM12 2a10 10 0 0 0-8.6 15L2 22l5.2-1.4A10 10 0 1 0 12 2zm0 18.2c-1.5 0-3-.4-4.3-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2z"/></svg>
  </a>
</div>

<script src="/assets/consent.js?v=20260908111654" defer></script>
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

  // Estado del configurador. `extras` es un objeto id->true (multiseleccion). El precio de
  // cada extra depende del MODELO (Airbnb Kit y Oasis Pool escalan con la villa), asi que se
  // lee siempre de CFG.modelos[S.villa].extras y nunca de una copia guardada al marcarlo.
  var S = {villa: 'dune', techo: 'sirap', extras: {}, div: 'AUD'};
  var PASOS = 3, paso = 1;

  function eur(n) { return '€' + Number(n).toLocaleString('en-US'); }
  function audf(n) { return '$' + (Math.round(n * CFG.tasaAud / 10) * 10).toLocaleString('en-US') + ' AUD'; }
  function pinta(n) { return S.div === 'AUD' ? audf(n) : eur(n); }
  function alterna(n) { return S.div === 'AUD' ? eur(n) : audf(n); }

  function $(id) { return document.getElementById(id); }
  function txt(id, s) { var e = $(id); if (e) e.textContent = s; }

  function modelo() { return CFG.modelos[S.villa] || null; }
  function techoActivo() {
    var m = modelo();
    if (!m) return null;
    return m.techos[S.techo] || m.techos.sirap || null;
  }
  function precioVilla() {
    var t = techoActivo();
    return t ? t.eur : 0;
  }
  /** Extras marcados que EXISTEN en el modelo actual. Cambiar de villa no borra la seleccion:
   *  si el modelo nuevo no ofreciera uno, simplemente no entra en la cuenta. */
  function extrasElegidos() {
    var m = modelo(), out = [];
    if (!m) return out;
    (m.extras || []).forEach(function (x) { if (S.extras[x.id]) out.push(x); });
    return out;
  }

  // ── Pasos 2 (techos) y 3 (extras): se repintan al cambiar de villa, porque los dos llevan
  //    precios del modelo elegido. Mismo patron que ya usaba /dali con los techos.
  function pintaTechos() {
    var m = modelo(), cont = $('pf-techos');
    if (!m || !cont) return;
    // El paso 2 enseña lo que SUMA cada techo, no el precio entero de la villa (pedido del
    // owner, 7-sep): en el paso 1 acabas de ver 110.160 y volver a ver 110.160 y 113.400 no
    // deja claro que la diferencia son 3.240. La base es el techo mas barato del modelo,
    // calculada — no "sirap" fijo — para que siga siendo cierto si algun dia se le da la
    // vuelta al precio. El total entero sigue estando en el resumen de la derecha, que es
    // donde la regla de "el techo es el precio de la villa, no un recargo" se sostiene.
    var base = Math.min.apply(null, ['sirap', 'bambu']
      .filter(function (k) { return m.techos[k]; })
      .map(function (k) { return m.techos[k].eur; }));
    cont.innerHTML = '';
    ['sirap', 'bambu'].forEach(function (k) {
      var t = m.techos[k];
      if (!t) return;
      var d = t.eur - base;
      var l = document.createElement('label');
      l.className = 'op';
      // Sin `data-eur` cuando no suma nada: asi el repintado por cambio de moneda no lo pisa
      // con un "+ $0 AUD", que es ruido — se queda en "Included".
      l.innerHTML =
        '<input type="radio" name="pf-techo" value="' + k + '"' + (k === S.techo ? ' checked' : '') + '>' +
        '<span><span class="op__nb"></span></span>' +
        (d ? '<span class="op__pr" data-eur="' + d + '"><b></b><i></i></span>'
           : '<span class="op__pr"><b>Included</b></span>');
      l.querySelector('.op__nb').textContent = t.nombre;
      if (d) {
        l.querySelector('b').textContent = '+ ' + pinta(d);
        l.querySelector('i').textContent = '+ ' + alterna(d);
      }
      cont.appendChild(l);
    });
  }
  function pintaExtras() {
    var m = modelo(), cont = $('pf-extras');
    if (!m || !cont) return;
    cont.innerHTML = '';
    (m.extras || []).forEach(function (x) {
      var l = document.createElement('label');
      l.className = 'op';
      l.innerHTML =
        '<input type="checkbox" name="pf-extra" value="' + x.id + '"' + (S.extras[x.id] ? ' checked' : '') + '>' +
        '<span><span class="op__nb"></span><span class="op__sp"></span></span>' +
        '<span class="op__pr" data-eur="' + x.eur + '"><b></b><i></i></span>';
      l.querySelector('.op__nb').textContent = x.nombre;
      // El price list del owner no trae descripcion para todos (hoy falta la del Airbnb Kit):
      // se deja el hueco vacio en vez de inventarse que incluye un extra de 5.000-8.000 €.
      l.querySelector('.op__sp').textContent = x.desc || '';
      l.querySelector('b').textContent = '+ ' + pinta(x.eur);
      l.querySelector('i').textContent = '+ ' + alterna(x.eur);
      cont.appendChild(l);
    });
  }

  // ── Navegacion por pasos ─────────────────────────────────────────────────────────
  function muestraPaso(n) {
    paso = n;
    document.querySelectorAll('.cfg__step').forEach(function (s) {
      s.hidden = Number(s.getAttribute('data-paso')) !== n;
    });
    txt('pf-paso-lb', 'Step ' + n + ' of ' + PASOS);
    var a = $('pf-atras'); if (a) a.hidden = n === 1;
    var sig = $('pf-siguiente');
    if (sig && sig.firstChild) sig.firstChild.textContent = n === PASOS ? 'See my figure ' : 'Next ';
    var p = $('pf-puntos');
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
    var n = paso + dir;
    if (n < 1) n = 1;
    if (n > PASOS) {
      var r = document.querySelector('.res');
      if (r) r.scrollIntoView({behavior: 'smooth', block: 'center'});
      return;
    }
    muestraPaso(n);
  }
  var sigB = $('pf-siguiente'); if (sigB) sigB.addEventListener('click', function () { avanza(1); });
  var atrB = $('pf-atras');     if (atrB) atrB.addEventListener('click', function () { avanza(-1); });

  function recalcular() {
    var m = modelo();
    if (!m) return;
    var t   = techoActivo();
    var pv  = precioVilla();
    var els = extrasElegidos();
    var pe  = 0;
    els.forEach(function (x) { pe += x.eur; });
    var total = pv + pe;

    txt('pf-r-villa', m.villa);
    txt('pf-r-villa-sub', (t ? t.nombre + ' roof · ' : '') + m.specs);
    txt('pf-r-villa-pr', pinta(pv));
    txt('pf-r-extras', els.length ? 'Extras (' + els.length + ')' : 'Extras');
    txt('pf-r-extras-sub', els.length
      ? els.map(function (x) { return x.nombre; }).join(', ')
      : 'None selected');
    txt('pf-r-extras-pr', els.length ? pinta(pe) : '—');
    txt('pf-total', pinta(total));
    txt('pf-total-alt', '≈ ' + alterna(total));
    txt('pf-movil', pinta(total));

    document.querySelectorAll('.cfg .op__pr[data-eur]').forEach(function (nodo) {
      var v   = Number(nodo.getAttribute('data-eur'));
      // Techos y extras se enseñan como lo que SUMAN; el paso 1 (villa), en absoluto.
      var mas = (nodo.closest('#pf-extras') || nodo.closest('#pf-techos')) ? '+ ' : '';
      var b   = nodo.querySelector('b'), i = nodo.querySelector('i');
      if (b) b.textContent = mas + pinta(v);
      if (i) i.textContent = mas + alterna(v);
    });

    // Se PARTE de la query que ya hay y solo se borran las claves propias: barrerla entera se
    // llevaria `utm_*` y `fbclid`, que es de donde sale la atribucion de la campaña.
    var p = new URLSearchParams(location.search);
    ['villa', 'roof', 'extras', 'cur', 'plot'].forEach(function (k) { p.delete(k); });
    if (S.villa !== 'dune')  p.set('villa', S.villa);
    if (S.techo !== 'sirap') p.set('roof', S.techo);
    if (els.length) p.set('extras', els.map(function (x) { return x.id; }).join(','));
    if (S.div !== 'AUD') p.set('cur', S.div);
    var q = p.toString();
    history.replaceState(history.state, '', '/palmfield' + (q ? '?' + q : ''));

    var wt = "Hi, I'm an Australian investor interested in Palm Field: " + m.villa
           + (t ? ' with a ' + t.nombre + ' roof' : '')
           + (els.length ? ', plus ' + els.map(function (x) { return x.nombre; }).join(', ') : '')
           + ' (' + eur(total) + ' for the villa, plot quoted separately).';
    var href = 'https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(wt);
    document.querySelectorAll('a[href*="wa.me/"]').forEach(function (a) { a.href = href; });
  }

  // Un clic en una opcion de paso simple AVANZA solo (pedido del owner, 7-sep-2026). El paso
  // de extras no avanza: es multiseleccion, y saltar al primer tick impediria marcar el resto.
  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t) return;
    if (t.type === 'radio') {
      if (t.name === 'pf-villa') { S.villa = t.value; pintaTechos(); pintaExtras(); }
      else if (t.name === 'pf-techo') { S.techo = t.value; }
      else { return; }
      recalcular();
      if (paso < PASOS) avanza(1);
      return;
    }
    if (t.type === 'checkbox' && t.name === 'pf-extra') {
      if (t.checked) S.extras[t.value] = true; else delete S.extras[t.value];
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
      // Los datos personales solo se piden cuando ya hay dia elegido (7-sep-2026).
      var form = $('lw-form');
      if (form) form.hidden = false;
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
    var m = modelo(), pe = 0;
    extrasElegidos().forEach(function (x) { pe += x.eur; });
    // Valor del lead = la cifra que la pagina le ha enseñado (villa + extras). La parcela no
    // entra porque no se elige aqui: meterla inflaria el valor con un m² que nadie ha pedido.
    track('Lead', {content_name: 'Palm Field · ' + (m ? m.villa : ''),
      value: precioVilla() + pe, currency: 'EUR'});
  });

  var ck = $('lw-cookies');
  if (ck) ck.addEventListener('click', function (ev) {
    ev.preventDefault();
    if (window.lwConsentReopen) window.lwConsentReopen();
  });

  // Estado desde la query (enlace compartible)
  var q  = new URLSearchParams(location.search);
  var vq = q.get('villa'); if (vq && CFG.modelos[vq]) S.villa = vq;
  var tq = q.get('roof');  if (tq === 'sirap' || tq === 'bambu') S.techo = tq;
  var cq = q.get('cur');   if (cq === 'EUR' || cq === 'AUD') S.div = cq;
  // Lista blanca contra el catalogo del MODELO ya resuelto: un id que ese modelo no ofrece no
  // entra en el estado, asi que ?extras= no puede meter en la cuenta nada sin precio propio.
  var validos = {};
  ((CFG.modelos[S.villa] || {}).extras || []).forEach(function (x) { validos[x.id] = true; });
  (q.get('extras') || '').split(',').forEach(function (id) {
    if (validos[id]) S.extras[id] = true;
  });

  var rv = document.querySelector('input[name="pf-villa"][value="' + S.villa + '"]');
  if (rv) rv.checked = true;
  document.querySelectorAll('.divisa').forEach(function (b) {
    b.classList.toggle('is-on', b.getAttribute('data-div') === S.div);
  });

  pintaTechos();
  pintaExtras();
  muestraPaso(1);
  recalcular();
}());
</script>
</body>
</html>
