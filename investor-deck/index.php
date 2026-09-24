<?php
/* Investor Deck genérico — 15-sep-2026.
   Generaliza el piloto de investor-deck/palmfield/ (que sigue existiendo, sin
   tocar, como su propia carpeta física con su propio flujo de reserva de
   autoservicio) a cualquier proyecto de la cartera que tenga slug + config.
   Revisión previa hecha (Seguridad + Datos + Diseño, CEO/flujos/revision_previa.md)
   y 3 rondas de confirmación del owner en la misma sesión, 15-sep-2026.

   Decisiones que dan forma a este fichero, cada una con su motivo:
   1. SIN reserva de autoservicio. El piloto de Palm Field tiene su propia
      config legal (investor_deck_config, validez/plazo/jurisdicción) ya
      revisada; generalizar ese flujo a 29 proyectos sin una fila de config
      por proyecto habría emitido Cartas de Reserva con los términos del
      primer proyecto activado para todos los demás (hallazgo de Datos). El
      owner decidió (15-sep) resolverlo quitando la reserva de autoservicio
      del deck genérico entero: cada parcela usa "Contact us"
      (mailto:sales@lawangproperties.com), el mismo camino que Palm Field ya
      usa para las parcelas sin cuota_reserva configurada.
   2. SIN plano interactivo por defecto. Las coordenadas de un masterplan se
      miden a mano sobre la imagen concreta de CADA proyecto (ver ZONAS en
      investor-deck/palmfield/index.html) — no es derivable de una plantilla.
      Gate `config.masterplan_activo`: si es false, la lista de parcelas en
      vivo (investor_deck_parcelas, que no depende de coordenadas) se sigue
      viendo igual; solo se oculta la imagen+hotspots.
   3. Nunca placeholders (Diseño). Sin fotos/KPIs/título propios, esas
      secciones no caen a contenido de Palm Field ni a nada inventado: se
      omiten o muestran un estado vacío honesto.
   4. `deck_config_publico(slug)` es la ÚNICA llamada que decide si esta
      página tiene algo que enseñar. Cero filas = proyecto sin deck activo
      todavía, y la página lo dice en vez de dejar huecos en blanco. */

$slug = preg_replace('/[^A-Za-z0-9-]/', '', $_GET['slug'] ?? '');
if ($slug === '') { http_response_code(404); exit; }
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Investor Deck | Lawang Properties</title>
<meta name="description" content="Project documentation, live plot inventory and a Year-1 forecast, for your own due diligence.">
<meta name="robots" content="noindex, nofollow">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600;700&family=Jost:ital,wght@0,400;0,500;0,600;1,400&family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap" rel="stylesheet">
<style>
  /* Mismos tokens visuales que investor-deck/palmfield/ (Diseño, revisión
     previa: la piel es reutilizable tal cual, lo que no lo es es el
     contenido). */
  @font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-ExtraLight.otf') format('opentype');font-weight:200;font-style:normal;font-display:swap}
  @font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Light.otf') format('opentype');font-weight:300;font-style:normal;font-display:swap}
  @font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Book.otf') format('opentype');font-weight:400;font-style:normal;font-display:swap}
  @font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Medium.otf') format('opentype');font-weight:500;font-style:normal;font-display:swap}
  @font-face{font-family:'Neue Kabel';src:url('../assets/fonts/NeueKabel-Bold.otf') format('opentype');font-weight:700;font-style:normal;font-display:swap}
  @layer base {
    html, body { margin: 0; padding: 0; }
    body { overscroll-behavior: none; }
    main > :first-child { margin-top: 0 !important; }
  }
  ::-webkit-scrollbar { display: none; }
  .material-symbols-outlined { font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24; vertical-align: middle; }
  .lw-money { white-space: nowrap; font-variant-numeric: tabular-nums; }
  .lw-wide  { max-width: 1400px; margin-inline: auto; width: 100%; }
  .lw-prose { max-width: 46rem; }
  h1, h2 { text-wrap: balance; }
  p { text-wrap: pretty; }
  .lw-fade-in { animation: lwFadeIn .35s ease both; }
  @keyframes lwFadeIn { from { opacity:0; transform:translateY(4px);} to { opacity:1; transform:none;} }
</style>
<script src="/investor-deck/i18n.js?v=20260915"></script>
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<script>
  tailwind.config = {
    theme: {
      extend: {
        colors: {
          "territorial-green": "#485B37", "deep-lagoon": "#104C4F", "burnt-earth": "#42210B",
          "soft-canopy": "#8F9B7A", "volcanic-ash": "#2E3437", "stone-sand": "#BEB3A5",
          "raw-linen": "#F5F0E6", "surface": "#fbf9f4", "surface-alt": "#F1EBDD",
          "surface-container-low": "#f5f4ee", "surface-container": "#efeee8",
          "surface-container-lowest": "#ffffff", "on-surface": "#1b1c19",
          "on-surface-variant": "#44483f", "control-border": "#8A8474"
        },
        borderRadius: { "DEFAULT": "0.25rem", "lg": "0.5rem", "xl": "0.75rem", "full": "9999px" },
        spacing: { "margin-mobile": "16px", "element-gap": "16px", "gutter": "24px", "margin-desktop": "48px" },
        fontFamily: {
          "label-md": ["Jost", "sans-serif"], "kpi-number": ["Instrument Sans", "sans-serif"],
          "body-sm": ["Jost", "sans-serif"], "headline-md": ["Neue Kabel", "Jost", "sans-serif"],
          "body-md": ["Jost", "sans-serif"], "body-lg": ["Jost", "sans-serif"],
          "headline-lg": ["Neue Kabel", "Jost", "sans-serif"], "headline-sm": ["Neue Kabel", "Jost", "sans-serif"]
        },
        fontSize: {
          "label-md": ["14px", { lineHeight: "20px", fontWeight: "600" }],
          "kpi-number": ["36px", { lineHeight: "40px", fontWeight: "600" }],
          "body-sm": ["13px", { lineHeight: "20px", fontWeight: "500" }],
          "body-md": ["15px", { lineHeight: "24px", fontWeight: "500" }],
          "body-lg": ["18px", { lineHeight: "28px", fontWeight: "500" }],
          "headline-lg": ["40px", { lineHeight: "48px", fontWeight: "600" }],
          "headline-sm": ["24px", { lineHeight: "32px", fontWeight: "600" }]
        }
      }
    }
  };
</script>
</head>
<body class="bg-surface font-body-md text-body-md text-on-surface antialiased selection:bg-soft-canopy selection:text-surface-container-lowest">

<!-- Estado "deck no disponible": nace visible, el JS lo apaga si hay config. -->
<div id="deck-no-disponible" class="min-h-screen flex items-center justify-center px-6 text-center">
  <div class="max-w-md flex flex-col items-center gap-4">
    <img src="/assets/img/lawang-logo-v3.webp" alt="Lawang" class="h-8 w-auto">
    <p class="font-headline-sm text-xl text-deep-lagoon font-semibold">This project does not have its Investor Deck available yet.</p>
    <p class="font-body-sm text-body-sm text-on-surface-variant">Please contact our team for the latest documentation and availability.</p>
    <a class="mt-2 px-5 py-2.5 rounded-full bg-deep-lagoon text-white font-label-md text-label-md" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>
  </div>
</div>

<div id="deck-contenido" class="hidden">

<header class="fixed top-0 left-0 right-0 z-50 bg-deep-lagoon shadow-[0_2px_16px_rgba(0,0,0,0.18)]">
  <div class="h-[72px] w-full px-6 md:px-margin-desktop flex items-center justify-between gap-4">
    <a class="flex items-center min-w-0 shrink-0" href="#vision" aria-label="Lawang Properties">
      <img src="/assets/img/lawang-logo-v3.webp" alt="Lawang" class="h-6 md:h-8 w-auto">
    </a>
    <nav class="hidden xl:flex items-center gap-1 bg-white/10 p-1.5 rounded-full border border-white/15">
      <a class="px-3.5 py-1.5 rounded-full font-label-md text-label-md text-white/85 hover:text-deep-lagoon hover:bg-white transition-all" href="#vision">Project &amp; Photos</a>
      <a class="px-3.5 py-1.5 rounded-full font-label-md text-label-md text-white/85 hover:text-deep-lagoon hover:bg-white transition-all" href="#modelos">Villa Models</a>
      <a class="px-3.5 py-1.5 rounded-full font-label-md text-label-md text-white/85 hover:text-deep-lagoon hover:bg-white transition-all" href="#masterplan">Masterplan &amp; Plots</a>
      <a class="px-3.5 py-1.5 rounded-full font-label-md text-label-md text-white/85 hover:text-deep-lagoon hover:bg-white transition-all" href="#rendimientos">Financial Forecast</a>
      <a class="px-3.5 py-1.5 rounded-full font-label-md text-label-md text-white/85 hover:text-deep-lagoon hover:bg-white transition-all" href="#faq">FAQ</a>
    </nav>
    <div class="flex items-center gap-2 sm:gap-3 shrink-0">
      <div class="flex items-center gap-1" id="deck-selectores" data-no-i18n
           style="--lw-lang-ink:rgba(255,255,255,.92);--lw-lang-bg:#0c3c3f;--lw-lang-line:rgba(255,255,255,.18);--lw-lang-menu-ink:#F5F0E6;--lw-lang-hover:rgba(255,255,255,.12)"></div>
      <a id="cta-dosier" class="hidden items-center gap-2 px-4 sm:px-5 py-2.5 rounded-full bg-white text-deep-lagoon font-label-md text-label-md hover:bg-soft-canopy hover:text-white transition-all shadow-sm whitespace-nowrap" href="#" target="_blank" rel="noopener">
        <span class="material-symbols-outlined text-[17px]">download</span>
        <span class="hidden sm:inline">Download dossier</span><span class="sm:hidden">Dossier</span>
      </a>
      <a id="cta-whatsapp" class="inline-flex items-center gap-2 px-3.5 sm:px-5 py-2.5 rounded-full bg-[#25D366] text-[#0b3d25] font-label-md text-label-md hover:brightness-95 transition-all shadow-sm whitespace-nowrap" href="https://wa.me/6281138319862" target="_blank" rel="noopener" aria-label="Ask on WhatsApp">
        <svg viewBox="0 0 24 24" class="w-[17px] h-[17px] shrink-0" fill="currentColor" aria-hidden="true"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51l-.57-.01c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.41-.07-.12-.27-.2-.57-.35zM12.04 21.5h-.01a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.51-.23-.36a9.49 9.49 0 0 1-1.45-5.05c0-5.24 4.27-9.5 9.52-9.5a9.46 9.46 0 0 1 9.51 9.51c0 5.24-4.27 9.5-9.51 9.5zM20.52 3.49A11.78 11.78 0 0 0 12.04 0C5.46 0 .1 5.36.1 11.94c0 2.1.55 4.16 1.6 5.98L0 24l6.25-1.64a11.92 11.92 0 0 0 5.79 1.47h.01c6.58 0 11.94-5.36 11.94-11.94a11.86 11.86 0 0 0-3.47-8.4z"/></svg>
        <span class="hidden sm:inline">Questions? WhatsApp</span><span class="sm:hidden">WhatsApp</span>
      </a>
    </div>
  </div>
</header>

<main class="w-full pt-[72px] bg-surface min-h-[calc(100vh-72px)]">
<div class="flex flex-col w-full">

<!-- SECCIÓN 1: HERO -->
<section class="w-full px-6 md:px-margin-desktop pt-6 pb-10 relative overflow-hidden" id="vision">
<div class="lw-wide flex flex-col gap-6">
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">

    <div class="flex flex-col gap-4">
    <div class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center gap-3">
        <span class="px-3 py-1 rounded-full bg-[#E4DFD5] text-[#2E3437] border border-[#D8D2C5] font-label-md text-body-sm tracking-wider uppercase font-semibold">Investor Deck · Due Diligence</span>
      </div>
      <h1 id="deck-titulo" class="font-headline-lg text-[32px] md:text-[42px] leading-[1.06] text-deep-lagoon tracking-tight font-normal"></h1>
      <p class="font-body-md text-body-md text-[#44483f] lw-prose leading-relaxed">
        Not a security or investment product. Real documentation, live plot inventory and a Year-1 forecast, for your own due diligence — the land tenure structure for this specific project is confirmed by your Lawang contact.
      </p>
    </div>

      <div class="m-0 relative rounded-2xl overflow-hidden shadow-lg" id="hero-carrusel">
        <div id="hero-track" class="flex overflow-x-auto snap-x snap-mandatory scroll-smooth lw-carrusel h-[32vh] min-h-[220px] lg:h-[34vh] lg:max-h-[330px] bg-[#E4DFD5]"><!-- lo llena el JS --></div>
        <button type="button" id="hero-prev" aria-label="Previous photos"
          class="hidden md:flex absolute left-3 top-1/2 -translate-y-1/2 z-20 w-9 h-9 items-center justify-center rounded-full bg-surface/90 backdrop-blur-md border border-[#D8D2C5] shadow-md text-deep-lagoon hover:bg-deep-lagoon hover:text-white transition-all disabled:opacity-0 disabled:pointer-events-none">
          <span class="material-symbols-outlined text-[20px]">chevron_left</span></button>
        <button type="button" id="hero-next" aria-label="More photos"
          class="hidden md:flex absolute right-3 top-1/2 -translate-y-1/2 z-20 w-9 h-9 items-center justify-center rounded-full bg-surface/90 backdrop-blur-md border border-[#D8D2C5] shadow-md text-deep-lagoon hover:bg-deep-lagoon hover:text-white transition-all disabled:opacity-0 disabled:pointer-events-none">
          <span class="material-symbols-outlined text-[20px]">chevron_right</span></button>
        <div id="hero-puntos" class="absolute right-4 bottom-3.5 z-20 flex gap-1.5"></div>
      </div>

      <!-- KPIs: fila entera ausente si config.kpis es null/vacio (Diseño,
           revision previa -- nunca los 4 KPIs de Palm Field reciclados). -->
      <div class="hidden grid-cols-2 gap-3" id="kpis-grid"><!-- lo llena el JS --></div>
    </div>

    <aside id="faq" class="flex flex-col rounded-2xl border border-[#D8D2C5] bg-surface-container-lowest shadow-lg overflow-hidden lg:max-h-[calc(100vh-112px)]">
      <div class="shrink-0 px-5 py-3.5 bg-[#E4DFD5] border-b border-[#D8D2C5] flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h2 class="font-headline-sm text-xl text-deep-lagoon font-semibold m-0">Documentation &amp; FAQ</h2>
        <span class="font-body-sm text-xs text-[#5F6257]">Everything you need to start your due diligence, on this screen.</span>
      </div>
      <div class="min-h-0 overflow-y-auto px-5 py-4 flex flex-col gap-5">
        <div id="docs-bloque" class="hidden flex-col gap-2">
          <h3 class="font-body-md text-[11px] uppercase tracking-wider text-[#5F6257] font-bold m-0">Project documents</h3>
          <div id="docs-lista" class="grid grid-cols-1 sm:grid-cols-2 gap-3"><!-- lo llena el JS --></div>
        </div>
        <div class="flex flex-col gap-2">
          <h3 class="font-body-md text-[11px] uppercase tracking-wider text-[#5F6257] font-bold m-0">Frequently Asked Questions</h3>
          <div id="faq-lista" class="flex flex-col gap-2"><!-- lo llena el JS --></div>
        </div>
        <div class="flex flex-wrap gap-2 pt-1 border-t border-[#D8D2C5]">
          <span class="font-body-sm text-xs text-[#5F6257] w-full pt-2">The full detail, further down:</span>
          <a class="px-3 py-1.5 rounded-full bg-[#E4DFD5] hover:bg-deep-lagoon hover:text-white text-deep-lagoon text-xs font-label-md font-semibold transition-all border border-[#D8D2C5]" href="#modelos">Villa Models</a>
          <a class="px-3 py-1.5 rounded-full bg-[#E4DFD5] hover:bg-deep-lagoon hover:text-white text-deep-lagoon text-xs font-label-md font-semibold transition-all border border-[#D8D2C5]" href="#masterplan">Masterplan &amp; Plots</a>
          <a class="px-3 py-1.5 rounded-full bg-[#E4DFD5] hover:bg-deep-lagoon hover:text-white text-deep-lagoon text-xs font-label-md font-semibold transition-all border border-[#D8D2C5]" href="#rendimientos">Financial Forecast</a>
        </div>
      </div>
    </aside>
  </div>
</div>
</section>

<!-- SECCIÓN 2: MODELOS -->
<section class="w-full px-6 md:px-margin-desktop py-14 bg-[#DFD7C6] border-y border-[#C9BFA9]" id="modelos">
<div class="lw-wide flex flex-col gap-8">
  <div class="flex flex-col gap-2 lw-prose">
    <h2 class="font-headline-lg text-headline-lg text-deep-lagoon font-normal">Villa Typologies</h2>
    <p class="font-body-md text-body-md text-on-surface-variant leading-relaxed">Prices below are <b>construction only</b> — land price depends on the plot chosen in the masterplan.</p>
  </div>
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 items-stretch" id="modelos-grid"><!-- filled by JS --></div>
</div>
</section>

<!-- SECCIÓN 3: MASTERPLAN & DISPONIBILIDAD -->
<section class="w-full px-6 md:px-margin-desktop py-14 bg-surface border-y border-[#D8D2C5]" id="masterplan">
<div class="lw-wide flex flex-col gap-8">
  <div class="flex flex-col md:flex-row md:items-end justify-between gap-6">
    <div class="flex flex-col gap-2 lw-prose">
      <h2 class="font-headline-lg text-headline-lg text-deep-lagoon font-normal">Masterplan &amp; Plot Availability</h2>
      <p id="masterplan-nota" class="font-body-md text-body-md text-on-surface-variant"></p>
    </div>
    <div class="flex items-center gap-4 bg-surface-container-low p-2.5 rounded-full border border-[#D8D2C5] text-xs font-label-md">
      <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded-full bg-territorial-green"></span><span class="text-on-surface font-semibold">Available</span></div>
      <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded-full bg-amber-500"></span><span class="text-on-surface font-semibold">Reserved</span></div>
      <div class="flex items-center gap-1.5"><span class="w-3 h-3 rounded-full bg-[#B3261E]"></span><span class="text-on-surface-variant">Sold / Blocked</span></div>
    </div>
  </div>

  <div class="grid grid-cols-1 lg:grid-cols-12 gap-gutter items-start">
    <!-- Plano interactivo: SOLO si config.masterplan_activo. Nace oculto por
         defecto (decision 2 -- trabajo manual por proyecto, no derivable). -->
    <div class="hidden lg:col-span-7 bg-surface-container-lowest p-5 rounded-2xl shadow-md border border-[#D8D2C5] flex-col gap-3" id="masterplan-imagen-bloque">
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <span class="font-headline-sm text-lg font-bold text-deep-lagoon">Masterplan</span>
        <div class="flex items-center gap-3 text-[11px] font-label-md">
          <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-territorial-green"></span>Available</span>
          <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-amber-500"></span>Reserved</span>
          <span class="flex items-center gap-1.5"><span class="w-2.5 h-2.5 rounded-full bg-[#B3261E]"></span>Sold</span>
        </div>
      </div>
      <div class="hidden gap-2 flex-wrap" id="plan-paginas"></div>
      <div class="relative w-full select-none" id="plan-wrap">
        <img id="masterplan-img" src="" alt="Masterplan showing every plot code and surface area" loading="lazy" class="w-full rounded-xl border border-[#D8D2C5] bg-[#F0ECE1] object-contain block">
        <div class="absolute inset-0" id="plan-hotspots"></div>
      </div>
      <p class="font-body-sm text-xs text-[#5F6257]">Status is live; surface areas shown are project/design measurements, confirmed by survey at Plot Lock — not the registered legal area.</p>
    </div>

    <div class="lg:col-span-5 flex flex-col gap-4 lg:sticky lg:top-24" id="masterplan-lista-col">
      <div class="bg-surface-container-lowest rounded-2xl shadow-md border border-[#D8D2C5] overflow-hidden">
        <div class="p-4 bg-[#E4DFD5] border-b border-[#D8D2C5] flex items-center justify-between">
          <span class="font-label-md text-xs uppercase font-bold text-deep-lagoon tracking-wider">Live plot inventory</span>
          <span class="text-xs font-body-sm text-territorial-green font-semibold" id="plots-count">Loading…</span>
        </div>
        <div class="divide-y divide-[#D8D2C5]/70 max-h-[520px] overflow-y-auto" id="plots-wrap">
          <div class="p-6 text-sm text-[#5F6257]">Loading live plot data…</div>
        </div>
      </div>
    </div>
  </div>
</div>
</section>

<!-- SECCIÓN 4: FINANCIAL FORECAST -->
<section class="w-full px-6 md:px-margin-desktop py-14 bg-[#DFD7C6] border-y border-[#C9BFA9]" id="rendimientos">
<div class="lw-wide flex flex-col gap-8">
  <div class="flex flex-col gap-2 lw-prose">
    <h2 class="font-headline-lg text-headline-lg text-deep-lagoon font-normal" id="forecast-titulo">Year-1 Rental Forecast</h2>
    <p class="font-body-md text-body-md text-on-surface-variant leading-relaxed">A first-year operating forecast under two scenarios (Average / Optimal occupancy). This is a forecast, not a guarantee — actual results depend on the rental operator, market conditions and property management agreement in force.</p>
  </div>
  <div class="grid grid-cols-1 md:grid-cols-3 gap-6" id="forecast-grid"><!-- filled by JS --></div>
  <p id="forecast-nota" class="font-body-sm text-xs text-[#5F6257] lw-prose">Figures shown are a Year-1 operating forecast provided by Lawang, not a guaranteed or historical return. ROI is calculated on the total investment (construction plus land) stated on each card; the land figure depends on the plot chosen. Management fee, maintenance and rental tax percentages are indicative and are confirmed in the rental-management agreement you sign; they may change.</p>
</div>
</section>

<!-- SECCIÓN 5: SEGURIDAD JURÍDICA — retirada 15-sep-2026 (hallazgo Legal en la
     consulta de deploy capa 1): esta sección afirmaba Hak Sewa + escrow notarial
     como un HECHO fijo para cualquier proyecto que use esta plantilla. Esa es la
     estructura real de Palm Field (consulta legal 9-sep-2026), no algo que se
     pueda asumir por plantilla para los otros 28 proyectos de la cartera — cada
     uno necesita su propia verificación de tenencia antes de poder afirmar nada
     aquí. No se sustituye por texto genérico: mientras no exista un campo de
     tenencia por proyecto en deck_config_proyecto, esta sección se omite entera
     en el deck genérico. Palm Field mantiene la suya intacta en
     investor-deck/palmfield/index.html, fuera de este sistema. -->

<!-- SECCIÓN 6: SITE & DELIVERED VILLAS -->
<section class="w-full px-6 md:px-margin-desktop py-14 bg-surface border-t border-[#D8D2C5]" id="documentation">
<div class="lw-wide flex flex-col gap-8">
  <div class="flex flex-col gap-2 lw-prose">
    <h2 class="font-headline-lg text-headline-lg text-deep-lagoon font-normal">Site &amp; Delivered Villas</h2>
    <p class="font-body-md text-body-md text-on-surface-variant leading-relaxed">Plots, surrounding land and villa models already delivered on neighbouring phases.</p>
  </div>
  <div class="relative">
    <div id="gallery" class="flex gap-4 overflow-x-auto scroll-smooth snap-x snap-mandatory pb-3 -mx-1 px-1 lw-carrusel"><!-- filled by JS --></div>
    <button type="button" id="gal-prev" aria-label="Previous photos"
      class="hidden md:flex absolute left-0 top-1/2 -translate-y-1/2 -translate-x-1/2 z-10 w-11 h-11 items-center justify-center rounded-full bg-surface-container-lowest border border-[#D8D2C5] shadow-md text-deep-lagoon hover:bg-deep-lagoon hover:text-white transition-all disabled:opacity-0 disabled:pointer-events-none">
      <span class="material-symbols-outlined">chevron_left</span></button>
    <button type="button" id="gal-next" aria-label="More photos"
      class="hidden md:flex absolute right-0 top-1/2 -translate-y-1/2 translate-x-1/2 z-10 w-11 h-11 items-center justify-center rounded-full bg-surface-container-lowest border border-[#D8D2C5] shadow-md text-deep-lagoon hover:bg-deep-lagoon hover:text-white transition-all disabled:opacity-0 disabled:pointer-events-none">
      <span class="material-symbols-outlined">chevron_right</span></button>
  </div>
  <!-- Estado vacio honesto: sin fotos de proyecto ni de modelo, nunca se cae a
       las fotos de Palm Field ni a ninguna otra (Diseño, revision previa). -->
  <div id="galeria-vacia" class="hidden p-8 rounded-2xl border border-dashed border-[#D8D2C5] text-center text-sm text-[#5F6257]">Photography in preparation.</div>
</div>
</section>

</div>
</main>

<div id="fx-nota" class="w-full px-6 md:px-margin-desktop py-3 bg-[#E9E3D6] border-t border-[#D8D2C5]" style="display:none">
  <p class="lw-wide font-body-sm text-xs text-[#5F6257]" id="fx-nota-txt"></p>
</div>

<footer class="w-full bg-surface-container-low py-10 border-t border-[#D8D2C5]">
  <div class="lw-wide px-6 md:px-margin-desktop flex flex-col md:flex-row items-center justify-between gap-6">
    <div class="flex items-center gap-4">
      <div class="w-8 h-8 rounded-full bg-deep-lagoon flex items-center justify-center text-white text-sm font-bold">L</div>
      <div class="flex flex-col">
        <span class="font-headline-sm text-lg font-bold text-deep-lagoon" id="footer-titulo">Lawang Properties</span>
      </div>
    </div>
    <div class="flex flex-wrap items-center gap-6 text-on-surface-variant font-body-sm text-xs text-center md:text-left">
      <span>This page does not replace legal or financial advice. Nothing here is an offer to sell securities or a solicitation of investment.</span>
      <a class="text-deep-lagoon underline whitespace-nowrap" id="footer-email" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>
      <a class="text-deep-lagoon underline whitespace-nowrap" href="/legal" target="_blank" rel="noopener">Privacy &amp; Terms</a>
    </div>
  </div>
</footer>

</div><!-- /#deck-contenido -->

<script>
(function(){
  'use strict';
  var SB_URL = 'https://vtulllundrfennhjddhc.supabase.co';
  // Publishable key (no el anon JWT legacy que usa el piloto de Palm Field):
  // mismo alcance publico, formato nuevo -- gate de deploy pide sb_publishable_
  // para todo lo que se escriba a partir de ahora, sin tocar lo ya desplegado.
  var SB_KEY = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';
  // Saneado en PHP (preg_replace [^A-Za-z0-9-]) y de nuevo aqui: defensa en
  // profundidad, aunque el .htaccess ya restringe el patron de la URL.
  var SLUG = <?= json_encode($slug) ?>;
  var SLUG_OK = /^[a-z0-9-]+$/i;
  if(!SLUG_OK.test(SLUG)){ document.getElementById('deck-no-disponible').classList.remove('hidden'); return; }

  var PROYECTO = null;   // se fija tras resolver deck_config_publico

  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
  function fmtMoney(n, cur){ if(n==null) return '—'; return window.lwMoney ? lwMoney(n) : ((cur||'EUR') + ' ' + Number(n).toLocaleString('en-GB')); }
  function lwTxt(campo){
    if(!campo) return '';
    var lang = window.lwLang ? lwLang() : 'en';
    return String(campo[lang] || campo.en || '');
  }
  function etiquetaTipo(tipo){
    if(tipo === 'render') return ' · Render';
    if(tipo === 'ia')     return ' · AI-generated image';
    return '';
  }
  var BUCKET = SB_URL + '/storage/v1/object/public/deck/';

  function montaFlechas(track, prev, next, puntos){
    if(!track || !prev || !next) return;
    function paso(){
      var f = track.firstElementChild;
      return f ? f.getBoundingClientRect().width + 16 : track.clientWidth * 0.8;
    }
    function pinta(){
      var fin = track.scrollWidth - track.clientWidth;
      prev.disabled = track.scrollLeft <= 8;
      next.disabled = track.scrollLeft >= fin - 8;
      if(puntos && puntos.children.length){
        var n = Math.round(track.scrollLeft / Math.max(1, paso()));
        for(var i = 0; i < puntos.children.length; i++){
          puntos.children[i].className = 'w-1.5 h-1.5 rounded-full transition-all ' +
            (i === n ? 'bg-white w-4' : 'bg-white/50');
        }
      }
    }
    prev.addEventListener('click', function(){ track.scrollBy({ left: -paso(), behavior: 'smooth' }); });
    next.addEventListener('click', function(){ track.scrollBy({ left:  paso(), behavior: 'smooth' }); });
    track.addEventListener('scroll', pinta);
    window.addEventListener('resize', pinta);
    pinta();
  }

  function pintaHero(fotos){
    var track  = document.getElementById('hero-track');
    var puntos = document.getElementById('hero-puntos');
    if(!track) return;
    track.innerHTML = '';
    if(puntos) puntos.innerHTML = '';
    // Estado vacio honesto: nunca una caja en blanco sin explicacion (Diseño,
    // revision previa) -- mismo texto que usa la galeria de mas abajo.
    if(!fotos.length){
      track.innerHTML = '<div class="w-full h-full flex items-center justify-center text-deep-lagoon/60 font-label-md text-label-md">Photography in preparation</div>';
      return;
    }
    fotos.forEach(function(f, i){
      var fig = document.createElement('figure');
      fig.className = 'm-0 relative shrink-0 snap-center w-full h-full';
      var img = document.createElement('img');
      img.src = f.src; img.alt = f.pie; img.className = 'w-full h-full object-cover';
      if(i === 0) img.setAttribute('fetchpriority', 'high'); else img.loading = 'lazy';
      var cap = document.createElement('figcaption');
      cap.className = 'absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent text-stone-sand font-body-sm text-xs px-5 pt-10 pb-4 pr-24';
      cap.textContent = f.pie + etiquetaTipo(f.tipo);
      fig.appendChild(img); fig.appendChild(cap);
      track.appendChild(fig);
      if(puntos && fotos.length > 1){
        var d = document.createElement('span');
        d.className = 'w-1.5 h-1.5 rounded-full transition-all ' + (i === 0 ? 'bg-white w-4' : 'bg-white/50');
        puntos.appendChild(d);
      }
    });
    montaFlechas(track, document.getElementById('hero-prev'), document.getElementById('hero-next'), puntos);
    if(window.lwDeck) lwDeck.traduce(track);
  }

  function pintaGaleria(fotos){
    var g = document.getElementById('gallery');
    var vacia = document.getElementById('galeria-vacia');
    if(!g) return;
    g.innerHTML = '';
    if(!fotos.length){ g.classList.add('hidden'); if(vacia) vacia.classList.remove('hidden'); return; }
    g.classList.remove('hidden'); if(vacia) vacia.classList.add('hidden');
    fotos.forEach(function(f){
      var fig = document.createElement('figure');
      fig.className = 'm-0 shrink-0 snap-start relative overflow-hidden rounded-xl border border-[#D8D2C5] w-[82vw] sm:w-[46vw] lg:w-[31%] aspect-[4/3] bg-[#F0ECE1] group';
      var img = document.createElement('img');
      img.src = f.src; img.alt = f.pie; img.loading = 'lazy';
      img.className = 'w-full h-full object-cover transition-transform duration-500 group-hover:scale-105';
      var cap = document.createElement('figcaption');
      cap.className = 'absolute left-0 right-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent text-white font-body-sm text-body-sm px-4 pt-10 pb-3';
      cap.textContent = f.pie + etiquetaTipo(f.tipo);
      fig.appendChild(img); fig.appendChild(cap);
      g.appendChild(fig);
    });
    montaFlechas(g, document.getElementById('gal-prev'), document.getElementById('gal-next'), null);
    if(window.lwDeck) lwDeck.traduce(g);
  }

  // Sin SEMILLA: un deck sin fotos propias muestra el estado vacio honesto,
  // nunca fotos de otro proyecto (Diseño, revision previa).
  function fotosVacias(){ pintaHero([]); pintaGaleria([]); }

  var fotosListo = null; // se resuelve tras conocer PROYECTO

  function pintaDocs(docs){
    var bloque = document.getElementById('docs-bloque');
    var cont   = document.getElementById('docs-lista');
    if(!bloque || !cont) return;
    cont.innerHTML = '';
    var pintados = 0;
    var DOC_ICONO = { comercial:'description', legal:'gavel', tecnico:'architecture', precios:'payments', portada:'image', otros:'draft' };
    var DOC_ETIQUETA = { comercial:'Commercial', legal:'Legal', tecnico:'Technical', precios:'Plots & pricing', portada:'Image', otros:'Document' };
    function urlSegura(u){
      if(!u) return '';
      try{ var p = new URL(String(u), location.href); return (p.protocol === 'http:' || p.protocol === 'https:') ? p.href : ''; }catch(_){ return ''; }
    }
    function enlaceDescarga(href){
      var m = /drive\.google\.com\/file\/d\/([^/?#]+)/.exec(href) || /drive\.google\.com\/open\?id=([^&#]+)/.exec(href);
      return m ? 'https://drive.google.com/uc?export=download&id=' + m[1] : '';
    }
    function accionDoc(href, icono, etiqueta, primaria){
      var a = document.createElement('a');
      a.href = href; a.target = '_blank'; a.rel = 'noopener';
      a.className = 'inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full no-underline font-label-md text-[12px] transition-all ' +
        (primaria ? 'bg-deep-lagoon text-white hover:bg-territorial-green' : 'border border-[#D8D2C5] text-deep-lagoon hover:border-territorial-green hover:bg-[#E4DFD5]/60');
      var i = document.createElement('span'); i.className = 'material-symbols-outlined text-[16px]'; i.textContent = icono;
      var t = document.createElement('span'); t.textContent = etiqueta;
      a.appendChild(i); a.appendChild(t); return a;
    }
    docs.forEach(function(d){
      var href = urlSegura(d.url);
      if(!href) return;
      var card = document.createElement('div');
      card.className = 'flex flex-col gap-2 bg-surface-container-low/60 border border-[#D8D2C5] rounded-xl px-4 py-3 hover:border-territorial-green transition-colors';
      var cab = document.createElement('div'); cab.className = 'flex items-start gap-2 text-deep-lagoon';
      var ico = document.createElement('span'); ico.className = 'material-symbols-outlined text-[18px] shrink-0 text-territorial-green'; ico.textContent = DOC_ICONO[d.categoria] || DOC_ICONO.otros;
      var texto = document.createElement('div'); texto.className = 'flex flex-col min-w-0 grow';
      var tit = document.createElement('span'); tit.className = 'font-body-md text-body-sm font-bold text-deep-lagoon break-words'; tit.setAttribute('data-no-i18n', ''); tit.textContent = d.titulo || '';
      texto.appendChild(tit);
      var sub = document.createElement('span'); sub.className = 'font-body-sm text-[11px] uppercase tracking-wider text-[#5F6257]'; sub.textContent = DOC_ETIQUETA[d.categoria] || DOC_ETIQUETA.otros;
      texto.appendChild(sub);
      if(d.descripcion){
        var des = document.createElement('span'); des.className = 'font-body-sm text-xs text-[#44483f] leading-relaxed mt-1'; des.setAttribute('data-no-i18n', ''); des.textContent = d.descripcion;
        texto.appendChild(des);
      }
      cab.appendChild(ico); cab.appendChild(texto);
      var acciones = document.createElement('div'); acciones.className = 'flex flex-wrap items-center gap-2 mt-auto pt-1';
      acciones.appendChild(accionDoc(href, 'visibility', 'View', true));
      var bajar = enlaceDescarga(href);
      if(bajar) acciones.appendChild(accionDoc(bajar, 'download', 'Download', false));
      card.appendChild(cab); card.appendChild(acciones);
      cont.appendChild(card);
      pintados++;
    });
    if(!pintados) return;
    bloque.classList.remove('hidden'); bloque.classList.add('flex');
    if(window.lwDeck) lwDeck.traduce(bloque);
  }

  var SLUG_MODELO_OK = /^[a-z0-9-]+$/;
  var SIN_RENDER =
    '<div class="w-full aspect-[4/3] relative overflow-hidden bg-[#E4DFD5] flex flex-col items-center justify-center gap-2 text-deep-lagoon/70">' +
      '<svg viewBox="0 0 120 90" aria-hidden="true" class="w-20 h-auto">' +
        '<path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>' +
        '<rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/>' +
        '<path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg>' +
      '<p class="font-label-md text-label-md m-0">Renders in progress</p></div>';

  function fotoModelo(slug, nombre, fotosModelo){
    if(!SLUG_MODELO_OK.test(slug)) return SIN_RENDER;
    var propia = (fotosModelo && fotosModelo.length) ? fotosModelo[0].src : null;
    if(!propia) return SIN_RENDER;   // sin fallback a assets/img/buildings/<slug> de Palm Field: cada modelo cuelga de deck_fotos o no se enseña
    return '<div class="w-full aspect-[4/3] relative overflow-hidden bg-[#F0ECE1]" data-foto>' +
      '<img src="' + esc(propia) + '" alt="' + esc(nombre) + ' villa model" loading="lazy" class="w-full h-full object-cover"></div>';
  }

  function precioModelo(precio, moneda){
    if(precio == null) return '<span class="font-headline-sm text-xl font-bold text-deep-lagoon">Upon request</span>';
    var n = Number(precio);
    if(!isFinite(n)) return '<span class="font-headline-sm text-xl font-bold text-deep-lagoon">Upon request</span>';
    if((moneda || 'EUR') === 'EUR') return '<span class="font-headline-sm text-xl font-bold text-deep-lagoon lw-money" data-eur="' + n + '">' + lwMoney(n) + '</span>';
    return '<span class="font-headline-sm text-xl font-bold text-deep-lagoon">' + esc(moneda) + ' ' + n.toLocaleString('en-GB') + '</span>';
  }
  function num(v){ var n = Number(v); return isFinite(n) ? n : '—'; }

  var mg = document.getElementById('modelos-grid');
  var DESTACADO = null;   // config.modelo_destacado_slug

  function pintaModelos(rows, porModelo){
    mg.innerHTML = '';
    rows.forEach(function(m, i){
      var slug = String(m.slug == null ? '' : m.slug);
      var destacado = DESTACADO && slug === DESTACADO;
      var tag = 'Type ' + (i + 1 < 10 ? '0' : '') + (i + 1);
      var card = document.createElement('div');
      card.className = 'bg-surface-container-lowest rounded-2xl overflow-hidden flex flex-col justify-between shadow-md hover:-translate-y-1 transition-all border' +
        (destacado ? ' border-2 border-territorial-green relative' : ' border-[#D8D2C5]');
      card.innerHTML =
        (destacado ? '<span class="absolute top-3 right-3 z-10 bg-territorial-green text-white text-[10px] font-label-md font-bold px-3 py-0.5 rounded-full tracking-wider uppercase">Most requested</span>' : '') +
        fotoModelo(slug, m.nombre, porModelo[slug]) +
        '<span class="absolute top-3 left-3 bg-deep-lagoon text-white px-2.5 py-0.5 rounded-full text-xs font-label-md uppercase font-semibold" data-tag>' + esc(tag) + '</span>' +
        '<div class="flex flex-col gap-4 p-6">' +
          '<h3 class="font-headline-sm text-2xl font-bold text-deep-lagoon">' + esc(m.nombre) + '</h3>' +
          '<div class="grid grid-cols-2 gap-2 text-xs font-body-sm text-[#44483f] bg-surface-container-low p-3 rounded-lg border border-[#D8D2C5]">' +
            '<div><strong>Built</strong><br>' + num(m.villa_m2) + ' m²</div>' +
            '<div><strong>Terrace &amp; pool</strong><br>+' + num(m.terraza_m2) + ' m²</div>' +
            '<div><strong>Bedrooms</strong><br>' + num(m.dormitorios) + '</div>' +
            '<div><strong>Bathrooms</strong><br>' + num(m.banos) + '</div></div></div>' +
        '<div class="px-6 pb-6 pt-5 border-t border-[#D8D2C5] flex flex-col gap-3">' +
          '<div class="flex items-baseline justify-between gap-3"><span class="text-xs text-[#5F6257] font-body-sm uppercase">Construction from</span>' + precioModelo(m.precio, m.moneda) + '</div>' +
          '<span class="text-[11px] text-[#5F6257]">+ land price, per plot chosen below</span>' +
        '</div>';
      var marco = card.querySelector('[data-foto]') || card.firstElementChild;
      var tagEl = card.querySelector('[data-tag]');
      if(marco && tagEl && marco !== tagEl) marco.appendChild(tagEl);
      var img = card.querySelector('img');
      if(img){
        img.addEventListener('error', function(){
          var caja = img.parentNode;
          if(!caja || !caja.parentNode) return;
          var tmp = document.createElement('div'); tmp.innerHTML = SIN_RENDER;
          var nuevo = tmp.firstChild;
          if(tagEl) nuevo.appendChild(tagEl);
          caja.parentNode.replaceChild(nuevo, caja);
          if(window.lwDeck) lwDeck.traduce(nuevo);
        });
      }
      mg.appendChild(card);
    });
    if(window.lwDeck) lwDeck.traduce(document.getElementById('modelos'));
    if(window.lwRepintaDinero) lwRepintaDinero();
  }

  function modelosCaidos(){
    mg.innerHTML = '<div class="col-span-full p-6 rounded-2xl border border-[#D8D2C5] bg-surface-container-lowest text-sm text-[#5F6257]">' +
      'We could not load the villa models right now. Please contact ' +
      '<a class="text-deep-lagoon underline" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>.</div>';
    if(window.lwDeck) lwDeck.traduce(mg);
  }

  function eur(v){ return '<span data-eur="'+Math.round(v)+'">'+(window.lwMoney?lwMoney(v):'€'+Math.round(v).toLocaleString('en-GB'))+'</span>'; }

  function pintaForecast(filas){
    var fg = document.getElementById('forecast-grid');
    if(!fg) return;
    fg.innerHTML = '';
    var f0 = filas[0];
    var GASTOS = [
      ['Management fee', Number(f0.pct_gestion)],
      ['Maintenance',    Number(f0.pct_mantenimiento)],
      ['Rental tax',     Number(f0.pct_impuesto)]
    ];
    var retencion = GASTOS.reduce(function(a, g){ return a + g[1]; }, 0);
    var tit = document.getElementById('forecast-titulo');
    if(tit){
      var nombres = filas.map(function(r){ return r.modelo_nombre; });
      var lista = nombres.length > 1 ? nombres.slice(0, -1).join(', ') + ' & ' + nombres[nombres.length - 1] : nombres[0];
      tit.textContent = 'Year-1 Rental Forecast — ' + lista;
    }
    filas.forEach(function(m){
      var adr = [Number(m.adr_medio), Number(m.adr_optimo)];
      var occ = [Number(m.ocupacion_media), Number(m.ocupacion_optima)];
      var base = Number(m.inversion_base);
      var bruto = [0,1].map(function(i){ return adr[i] * 365 * occ[i]; });
      var neto  = bruto.map(function(g){ return g * (1 - retencion); });
      var filasHtml = '';
      filasHtml += '<tr><td>ADR</td><td class="text-right lw-money">'+eur(adr[0])+'</td><td class="text-right lw-money">'+eur(adr[1])+'</td></tr>';
      filasHtml += '<tr><td>Occupancy</td><td class="text-right lw-money">'+Math.round(occ[0]*100)+'%</td><td class="text-right lw-money">'+Math.round(occ[1]*100)+'%</td></tr>';
      filasHtml += '<tr><td>Gross villa income</td><td class="text-right lw-money">'+eur(bruto[0])+'</td><td class="text-right lw-money">'+eur(bruto[1])+'</td></tr>';
      GASTOS.forEach(function(g){
        filasHtml += '<tr><td><span>'+esc(g[0])+'</span> ('+Math.round(g[1]*100)+'%)</td>' +
          '<td class="text-right lw-money">'+eur(-bruto[0]*g[1])+'</td>' +
          '<td class="text-right lw-money">'+eur(-bruto[1]*g[1])+'</td></tr>';
      });
      filasHtml += '<tr class="font-semibold text-deep-lagoon border-t-2 border-[#D8D2C5]"><td>Net income</td><td class="text-right lw-money">'+eur(neto[0])+'</td><td class="text-right lw-money">'+eur(neto[1])+'</td></tr>';
      filasHtml += '<tr class="font-bold text-territorial-green text-base"><td>ROI</td><td class="text-right lw-money">'+(neto[0]/base*100).toFixed(1)+'%</td><td class="text-right lw-money">'+(neto[1]/base*100).toFixed(1)+'%</td></tr>';
      var dorm = m.dormitorios === 1 ? '1 bedroom' : (m.dormitorios || 0) + ' bedrooms';
      var card = document.createElement('div');
      card.className = 'bg-surface-container-lowest rounded-2xl shadow-md overflow-hidden relative border' + (m.destacado ? '-2 border-territorial-green' : ' border-[#D8D2C5]');
      card.innerHTML =
        (m.destacado ? '<span class="absolute top-3 right-3 z-10 bg-territorial-green text-white text-[10px] font-label-md font-bold px-3 py-0.5 rounded-full tracking-wider uppercase">Most requested</span>' : '') +
        '<div class="p-5 bg-[#E4DFD5] border-b border-[#D8D2C5]">' +
          '<span class="font-headline-sm text-xl font-bold text-deep-lagoon">'+esc(m.modelo_nombre)+' · '+esc(dorm)+'</span>' +
          '<div class="text-xs text-[#44483f] font-body-sm mt-1"><span>Construction:</span> <b>'+eur(Number(m.precio_construccion))+'</b></div>' +
          '<div class="text-xs text-[#5F6257] font-body-sm"><span>Total investment (ROI base):</span> '+eur(base)+'</div>' +
        '</div>' +
        '<table class="w-full text-sm"><thead><tr class="text-[11px] uppercase tracking-wide text-[#5F6257] font-label-md">' +
          '<th class="text-left font-medium px-5 pt-4 pb-2"></th><th class="text-right font-medium px-5 pt-4 pb-2">Average</th>' +
          '<th class="text-right font-medium px-5 pt-4 pb-2">Optimal</th></tr></thead>' +
          '<tbody class="[&_td]:px-5 [&_td]:py-2 [&_tr]:border-t [&_tr]:border-[#EFEAE0]">'+filasHtml+'</tbody></table>';
      fg.appendChild(card);
    });
    if(window.lwDeck) lwDeck.traduce(document.getElementById('rendimientos'));
    if(window.lwRepintaDinero) lwRepintaDinero();
  }

  function forecastCaido(){
    var fg = document.getElementById('forecast-grid');
    if(!fg) return;
    fg.innerHTML = '<div class="col-span-full p-6 rounded-2xl border border-[#D8D2C5] bg-surface-container-lowest text-sm text-[#5F6257]">' +
      'We could not load the rental forecast right now. Please contact ' +
      '<a class="text-deep-lagoon underline" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>.</div>';
    if(window.lwDeck) lwDeck.traduce(fg);
  }

  function pintaFaq(filas){
    var cont = document.getElementById('faq-lista');
    if(!cont) return;
    cont.innerHTML = '';
    filas.forEach(function(q, i){
      var d = document.createElement('details');
      d.className = 'group bg-surface-container-low/60 px-4 py-3 rounded-xl border border-[#D8D2C5] transition-all open:bg-surface-container-lowest';
      if(i === 0) d.open = true;
      var sum = document.createElement('summary');
      sum.className = 'flex items-start gap-3 justify-between cursor-pointer list-none text-deep-lagoon font-body-md text-body-md font-semibold';
      var txt = document.createElement('span'); txt.textContent = lwTxt(q.pregunta);
      var ico = document.createElement('span'); ico.className = 'material-symbols-outlined text-[20px] shrink-0 text-territorial-green transition-transform group-open:rotate-180'; ico.textContent = 'expand_more';
      sum.appendChild(txt); sum.appendChild(ico);
      var cuerpo = document.createElement('div');
      cuerpo.className = 'pt-3 font-body-sm text-body-sm text-[#44483f] leading-relaxed border-t border-[#D8D2C5] mt-3';
      cuerpo.textContent = lwTxt(q.respuesta);
      d.appendChild(sum); d.appendChild(cuerpo);
      cont.appendChild(d);
    });
  }
  function faqCaida(){
    var cont = document.getElementById('faq-lista');
    if(!cont) return;
    cont.innerHTML = '<p class="font-body-sm text-body-sm text-[#5F6257] m-0">We could not load the questions right now. Please contact ' +
      '<a class="text-deep-lagoon underline" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>.</p>';
    if(window.lwDeck) lwDeck.traduce(cont);
  }

  // ZONAS: rellenado por pagina del manifiesto de masterplan (ver mas abajo).
  // Cada entrada es un poligono real en % -- [[x1,y1],[x2,y2],...] -- nunca un
  // rectangulo left/top/width/height: las parcelas irregulares (esquinas,
  // ladera) necesitan el contorno real, y un rectangulo es solo un poligono
  // de 4 puntos, asi que un unico formato cubre ambos casos sin rama aparte.
  var ZONAS = null;
  var ULTIMAS_FILAS = null;   // ultimas filas de investor_deck_parcelas, para repintar al cambiar de pagina sin refetch
  var PAGINAS_MP = [];
  var PAGINA_ACTUAL = 0;
  var SELLO = {
    disponible:    null,
    reservada:     ['RESERVED', 'bg-amber-500/90'],
    bloqueada:     ['SOLD',     'bg-[#B3261E]/95'],
    no_disponible: ['SOLD',     'bg-[#B3261E]/95'],
    vendida:       ['SOLD',     'bg-[#B3261E]/95'],
    cobrada:       ['SOLD',     'bg-[#B3261E]/95']
  };

  function centroide(pts){
    var x=0,y=0; pts.forEach(function(p){ x+=p[0]; y+=p[1]; });
    return [x/pts.length, y/pts.length];
  }

  // Sin flujo de reserva de autoservicio (decision 2, 15-sep): cada parcela
  // disponible usa "Contact us" directo, nunca un modal ni un RPC de reserva.
  function pintaPlano(rows){
    var wrap = document.getElementById('plan-hotspots');
    if(!wrap || !ZONAS) return;
    wrap.innerHTML = '';
    rows.forEach(function(row){
      var pts = ZONAS[row.codigo];
      if(!pts || pts.length < 3) return;   // sin poligono para este codigo en esta pagina -> sigue en la lista, sin marcador en el plano
      var libre = row.estado === 'disponible';
      var el = document.createElement(libre ? 'a' : 'div');
      el.className = 'absolute inset-0 transition-all duration-200 ' +
        (libre ? 'hover:bg-territorial-green/35 cursor-pointer' : 'bg-black/45');
      el.style.clipPath = 'polygon(' + pts.map(function(p){ return p[0]+'% '+p[1]+'%'; }).join(',') + ')';
      var precio = row.precio != null ? ' · ' + fmtMoney(row.precio, row.moneda) : '';
      el.title = row.codigo + ' · ' + esc(row.superficie_m2) + ' m2 (project measurement)' + precio + ' · ' +
        ({disponible:'Available',reservada:'Reserved',bloqueada:'Sold',no_disponible:'Sold',vendida:'Sold',cobrada:'Sold'}[row.estado] || row.estado);
      if(libre){ el.href = 'mailto:sales@lawangproperties.com?subject=' + encodeURIComponent(PROYECTO + ' ' + row.codigo); el.setAttribute('aria-label', 'Contact us about plot ' + row.codigo); }
      wrap.appendChild(el);
      var sello = SELLO[row.estado];
      if(sello){
        var c = centroide(pts);
        var badge = document.createElement('span');
        badge.className = 'absolute pointer-events-none ' + sello[1] + ' text-white font-label-md font-bold tracking-widest text-[8px] px-1.5 py-0.5 rounded-sm shadow';
        badge.style.left = c[0]+'%'; badge.style.top = c[1]+'%'; badge.style.transform = 'translate(-50%,-50%)';
        badge.textContent = sello[0];
        wrap.appendChild(badge);
      }
    });
  }

  // Cambia de pagina del masterplan (proyectos con mas de un plano/hoja).
  // Vuelve a pintar con las mismas filas ya cargadas, sin refetch a Supabase.
  function pintaPaginaMasterplan(i){
    var pag = PAGINAS_MP[i];
    if(!pag) return;
    PAGINA_ACTUAL = i;
    document.getElementById('masterplan-img').src = pag.imagen;
    ZONAS = pag.zonas || null;
    Array.prototype.forEach.call(document.querySelectorAll('.plan-pagina-btn'), function(b, idx){
      b.className = 'plan-pagina-btn px-3 py-1 rounded-full text-xs font-label-md font-semibold transition-colors ' +
        (idx === i ? 'bg-deep-lagoon text-white' : 'bg-[#E4DFD5] text-deep-lagoon hover:bg-[#D8D2C5]');
    });
    if(ULTIMAS_FILAS) pintaPlano(ULTIMAS_FILAS);
  }

  function pintaListaParcelas(rows){
    var plotsWrap = document.getElementById('plots-wrap');
    var plotsCount = document.getElementById('plots-count');
    ULTIMAS_FILAS = rows;
    if(!rows || !rows.length){ plotsWrap.innerHTML = '<div class="p-6 text-sm text-[#5F6257]">No plots published yet.</div>'; plotsCount.textContent=''; return; }
    if(ZONAS) pintaPlano(rows);
    var disponibles = rows.filter(function(r){ return r.estado === 'disponible'; }).length;
    plotsCount.textContent = disponibles + ' of ' + rows.length + ' plots available';
    plotsWrap.innerHTML = '';
    rows.forEach(function(row){
      var estadoLabel = { disponible:'Available', reservada:'Reserved', bloqueada:'Blocked', no_disponible:'Not available', vendida:'Sold', cobrada:'Sold' }[row.estado] || row.estado;
      var pillClass = row.estado === 'disponible' ? 'bg-territorial-green/15 text-territorial-green' : (row.estado === 'reservada' ? 'bg-amber-100 text-amber-800' : 'bg-[#FBE9E7] text-[#B3261E]');
      var row_ = document.createElement('div');
      row_.className = 'p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-[#E4DFD5]/30 transition-colors';
      var actionHtml;
      if(row.estado === 'disponible'){
        actionHtml = '<a class="px-3.5 py-1.5 rounded-full bg-deep-lagoon hover:bg-territorial-green text-white text-xs font-label-md font-semibold transition-colors" href="mailto:sales@lawangproperties.com?subject='+encodeURIComponent(PROYECTO + ' ' + row.codigo)+'">Contact us</a>';
      } else {
        actionHtml = '<span class="text-xs font-label-md text-[#5F6257] bg-[#F0ECE1] px-3 py-1.5 rounded-full">—</span>';
      }
      var precioM2 = (row.precio_suelo != null && row.superficie_m2) ? row.precio_suelo / row.superficie_m2 : null;
      row_.innerHTML = '<div class="flex flex-col"><div class="flex items-center gap-2"><span class="font-headline-sm text-lg font-bold text-deep-lagoon">'+esc(row.codigo)+'</span>' +
        '<span class="px-2 py-0.5 rounded-full text-[11px] font-label-md font-semibold '+pillClass+'">'+esc(estadoLabel)+'</span></div>' +
        '<span class="text-xs text-[#44483f] font-body-sm">'+esc(row.superficie_m2)+' m² · '+fmtMoney(precioM2, row.moneda)+'/m² land</span>' +
        '<span class="text-xs text-[#5F6257] font-body-sm">Land '+fmtMoney(row.precio_suelo, row.moneda)+' + Construction '+fmtMoney(row.precio_construccion, row.moneda)+' = '+fmtMoney(row.precio, row.moneda)+' total</span></div>' +
        '<div>'+actionHtml+'</div>';
      plotsWrap.appendChild(row_);
    });
    if(window.lwDeck){ lwDeck.traduce(document.getElementById('masterplan')); }
    if(window.lwRepintaDinero) lwRepintaDinero();
  }

  // ── arranque: resolver la config del deck por slug, y solo entonces pedir
  //    el resto (mismo PROYECTO que ya usan las 6 funciones investor_deck_*) ──
  fetch(SB_URL + '/rest/v1/rpc/deck_config_publico', {
    method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
    body: JSON.stringify({ p_slug: SLUG })
  }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function(rows){
      if(!rows || !rows.length) throw new Error('sin_config');
      var cfg = rows[0];
      PROYECTO = cfg.proyecto;
      DESTACADO = cfg.modelo_destacado_slug || null;

      document.getElementById('deck-no-disponible').classList.add('hidden');
      document.getElementById('deck-contenido').classList.remove('hidden');

      document.title = lwTxt(cfg.titulo) + ' | Lawang Properties';
      var metaDesc = document.querySelector('meta[name="description"]');
      if(metaDesc) metaDesc.setAttribute('content', lwTxt(cfg.meta_desc));
      var h1 = document.getElementById('deck-titulo');
      if(h1) h1.textContent = lwTxt(cfg.titulo);
      var footerTit = document.getElementById('footer-titulo');
      if(footerTit) footerTit.textContent = 'Lawang Properties — ' + PROYECTO;
      var waCta = document.getElementById('cta-whatsapp');
      if(waCta) waCta.href = 'https://wa.me/6281138319862?text=' + encodeURIComponent('Hello LAWANG, I’m looking at the ' + PROYECTO + ' investor deck and I have a few questions.');
      var masterplanNota = document.getElementById('masterplan-nota');
      if(masterplanNota) masterplanNota.textContent = "Individually cadastred plots. Live inventory read directly from " + PROYECTO + "'s records — sizes, prices and status are informational and confirmed at Plot Lock.";

      // KPIs: solo si config.kpis trae filas reales (nunca placeholder).
      if(cfg.kpis && cfg.kpis.length){
        var kg = document.getElementById('kpis-grid');
        kg.innerHTML = '';
        cfg.kpis.forEach(function(k){
          var box = document.createElement('div');
          box.className = 'bg-surface-container-lowest p-4 rounded-xl flex flex-col gap-0.5 shadow-sm border border-[#D8D2C5]';
          box.innerHTML = '<span class="font-body-sm text-[11px] font-semibold tracking-wider uppercase text-[#44483f]" data-no-i18n></span>' +
            '<span class="font-kpi-number text-[26px] leading-tight text-deep-lagoon" data-no-i18n></span>';
          box.querySelector('[class*="text-[11px]"]').textContent = lwTxt(k.label);
          box.querySelector('.font-kpi-number').textContent = lwTxt(k.valor);
          kg.appendChild(box);
        });
        kg.classList.remove('hidden'); kg.classList.add('grid');
      }

      // Masterplan interactivo: solo si esta activo Y hay manifiesto.
      // cfg.masterplan_imagen apunta a un JSON { paginas: [{imagen, etiqueta?, zonas}, ...] },
      // medido a mano por proyecto (ver investor-deck/masterplan/<slug>.json) -- no derivable
      // de plantilla (revision previa de Datos, 15-sep). Si el fetch falla o el
      // formato no es el esperado, el deck sigue funcionando sin plano interactivo:
      // la lista de la derecha (investor_deck_parcelas) no depende de esto.
      if(cfg.masterplan_activo && cfg.masterplan_imagen){
        fetch(cfg.masterplan_imagen).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
          .then(function(manifest){
            if(!manifest || !manifest.paginas || !manifest.paginas.length) throw new Error('manifiesto_vacio');
            PAGINAS_MP = manifest.paginas;
            document.getElementById('masterplan-imagen-bloque').classList.remove('hidden');
            document.getElementById('masterplan-imagen-bloque').classList.add('flex');
            document.getElementById('masterplan-lista-col').className = 'lg:col-span-5 flex flex-col gap-4 lg:sticky lg:top-24';
            if(PAGINAS_MP.length > 1){
              var tabs = document.getElementById('plan-paginas');
              tabs.innerHTML = '';
              PAGINAS_MP.forEach(function(pag, idx){
                var b = document.createElement('button');
                b.type = 'button';
                b.className = 'plan-pagina-btn px-3 py-1 rounded-full text-xs font-label-md font-semibold transition-colors';
                b.textContent = pag.etiqueta || ('Plan ' + (idx + 1));
                b.addEventListener('click', function(){ pintaPaginaMasterplan(idx); });
                tabs.appendChild(b);
              });
              tabs.classList.remove('hidden'); tabs.classList.add('flex');
            }
            pintaPaginaMasterplan(0);
          })
          .catch(function(){ ZONAS = null; });
      }

      fotosListo = fetch(SB_URL + '/rest/v1/rpc/investor_deck_fotos', {
        method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
        body: JSON.stringify({ p_proyecto: PROYECTO })
      }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function(rows){
          var porModelo = {}; var proyecto = [];
          (rows || []).forEach(function(r){
            var f = { uso:r.uso, tipo:r.tipo, src: BUCKET + r.path, pie: lwTxt(r.pie) };
            if(r.modelo_slug){ (porModelo[r.modelo_slug] = porModelo[r.modelo_slug] || []).push(f); }
            else { proyecto.push(f); }
          });
          if(!proyecto.length){ fotosVacias(); return porModelo; }
          var hero = proyecto.filter(function(f){ return f.uso === 'hero'; });
          var gal  = proyecto.filter(function(f){ return f.uso === 'galeria'; });
          pintaHero(hero.length ? hero : gal.slice(0, 6));
          pintaGaleria(gal.length ? gal : hero);
          return porModelo;
        })
        .catch(function(){ fotosVacias(); return {}; });

      fetch(SB_URL + '/rest/v1/rpc/investor_deck_documentos', {
        method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
        body: JSON.stringify({ p_proyecto: PROYECTO })
      }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function(docs){
          if(!docs || !docs.length) return;
          pintaDocs(docs);
          var d = docs.filter(function(x){ return x.categoria === 'comercial'; })[0];
          if(!d) return;
          var cta = document.getElementById('cta-dosier');
          if(!cta) return;
          var ctaHref = urlSegura(d.url);
          if(!ctaHref) return;
          cta.href = ctaHref; cta.classList.remove('hidden'); cta.classList.add('inline-flex');
          if(d.titulo) cta.setAttribute('title', d.titulo);
        })
        .catch(function(){});

      fetch(SB_URL + '/rest/v1/rpc/investor_deck_modelos', {
        method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
        body: JSON.stringify({ p_proyecto: PROYECTO })
      }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function(rows){
          if(!rows || !rows.length) throw new Error('vacio');
          return fotosListo.then(function(porModelo){ pintaModelos(rows, porModelo || {}); });
        })
        .catch(modelosCaidos);

      fetch(SB_URL + '/rest/v1/rpc/investor_deck_forecast', {
        method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
        body: JSON.stringify({ p_proyecto: PROYECTO })
      }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function(rows){ if(!rows || !rows.length) throw new Error('vacio'); pintaForecast(rows); })
        .catch(forecastCaido);

      fetch(SB_URL + '/rest/v1/rpc/investor_deck_faq', {
        method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
        body: JSON.stringify({ p_proyecto: PROYECTO })
      }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
        .then(function(rows){ if(!rows || !rows.length) throw new Error('vacio'); pintaFaq(rows); })
        .catch(faqCaida);

      fetch(SB_URL + '/rest/v1/rpc/investor_deck_parcelas', {
        method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
        body: JSON.stringify({ p_proyecto: PROYECTO })
      }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
        .then(pintaListaParcelas)
        .catch(function(){
          document.getElementById('plots-wrap').innerHTML = '<div class="p-6 text-sm text-[#5F6257]">We could not load live plot data right now. Please contact <a class="text-deep-lagoon underline" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>.</div>';
          document.getElementById('plots-count').textContent = '';
        });

      if(window.lwDeck){ lwDeck.montaSelectores('#deck-selectores'); lwDeck.traduce(document.body); }
      if(window.lwRepintaDinero) lwRepintaDinero();
    })
    .catch(function(){
      document.getElementById('deck-contenido').classList.add('hidden');
      document.getElementById('deck-no-disponible').classList.remove('hidden');
      if(window.lwDeck){ lwDeck.traduce(document.getElementById('deck-no-disponible')); }
    });
})();
</script>
</body>
</html>
