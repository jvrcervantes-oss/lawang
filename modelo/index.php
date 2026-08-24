<?php
/**
 * Landing de modelo de villa — /modelo/<id> (regla de reescritura en .htaccess).
 *
 * ── 3-ago-2026 · CUARTA versión, reescrita de cero. ─────────────────────────
 * El owner rechazó la anterior en las cuatro dimensiones a la vez (color y tipografía,
 * estructura, mecánica de conversión y contenido) y eligió sobre opciones concretas la
 * dirección **DOSSIER DE INVERSIÓN**. Es la lectura literal de PRODUCT.md: "como un banco
 * privado que construye villas". Lo que eso significa aquí, y por qué:
 *
 *   · DENSIDAD EN VEZ DE PANTALLAZOS. Fuera las 9 pantallas cinemáticas y el scroll-snap.
 *     El lector es un inversor escéptico que compara: quiere los datos juntos y arriba,
 *     no una idea por pantalla. La página es un documento, se puede imprimir y se lee de
 *     arriba abajo sin gestos.
 *   · LA FOTO ES PRUEBA, NO ESPECTÁCULO. Ninguna imagen a sangre. Todas van contenidas,
 *     con su pie diciendo si es render o fotografía real. PRODUCT.md prohíbe expresamente
 *     el "drone footage con sunsets"; a sangre y a pantalla completa es justo eso.
 *   · EL FORMULARIO ESTÁ SIEMPRE VISIBLE. Columna fija (sticky) en escritorio; en móvil
 *     entra justo detrás de la ficha técnica, a un scroll. Sustituye al <dialog> detrás
 *     de un clic de la versión anterior, que el owner señala como el fallo de conversión.
 *     Consecuencia medida en el píxel: `InitiateCheckout` ya no puede dispararse "al abrir
 *     el panel" porque no hay panel — ahora salta al primer foco en un campo, que es el
 *     equivalente real de "esta persona ha empezado".
 *   · TIPOGRAFÍA IBM PLEX (serif titulares · sans texto · mono cifras y etiquetas). Una
 *     superfamilia, tres voces. La mono en los datos es lo que hace que una tabla se lea
 *     como una ficha y no como una web. Fuera Archivo y sus mayúsculas de peso 800.
 *   · PALETA PAPEL + TINTA + UN VERDE. Desaparece la tierra saturada (teja) y el verde
 *     hondo de la marca se queda como ÚNICO acento. Todos los pares usados pasan AA:
 *     tinta 15,1:1 · secundario 6,0:1 · verde 8,8:1 sobre papel, y el verde en inverso
 *     (botón) da el mismo 8,8:1.
 *
 * LO QUE NO SE TOCA AUNQUE CAMBIE EL DISEÑO — cada línea costó una corrección:
 *   · Los textos de la FAQ son los que redactó Legal. "Freehold" NO vuelve (ver el
 *     comentario largo en la sección de preguntas).
 *   · El checkbox de consentimiento apunta a /legal-es (español), no a /legal.
 *   · El desplegable de presupuesto conserva sus cuatro opciones, incluida "todavía no lo
 *     tengo claro": es lo que sostiene que el campo pueda ser obligatorio sin convertirse
 *     en condición de acceso (RGPD 6.1.b).
 *   · Reglas de campos con lista separada por comas, nunca `:is()` — la pauta de Meta abre
 *     WebViews viejas que descartan la regla entera.
 *   · Sin precio cerrado: no se enseña cifra y la página se marca `noindex` sola.
 *   · Sin renders: no hay landing, se redirige al catálogo.
 *
 * SIN DATOS QUE NO TENEMOS: no hay superficie construida, superficie de parcela ni plazo
 * de obra en ninguna fuente del repo (en data.json los cuatro campos están a 0). En una
 * ficha técnica esas filas son las primeras que busca un inversor, así que están pedidas
 * al owner — pero NO se inventan ni se dejan como guion.
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

$g       = $m['imgs'];
$portada = $g[0];
$resto   = array_slice($g, 1);   // el resto va a la lámina de renders, contenidos

/**
 * Ficha técnica. Solo entra lo verificado en el pliego del contratista (anexo de obra) y
 * en modelos.php. Cada fila es una afirmación que el comprador puede exigir por escrito.
 */
$ficha = [
    ['Modelo',                 $nombre],
    ['Dormitorios',            $dorm . ($dorm === 1 ? ' en suite' : ' en suite')],
    ['Acabados de cubierta',   count($m['acabados']) . ' a elegir'],
    ['Piscina',                'Overflow, piedra sukabumi'],
    ['Terraza',                'Exterior'],
    ['Climatización',          'Aire acondicionado y agua caliente'],
    ['Acometida eléctrica',    'PLN 3.500 W'],
    ['Parcela',                'A elegir del catálogo'],
    ['Precio',                 $precio !== null ? $precio : 'Bajo consulta'],
    ['Moneda del contrato',    'Rupia indonesia (IDR)'],
    ['Promotor',               'PT Tepi Sun Gai'],
];
?><!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= lw_e($nombre) ?> · Ficha de producto — Lawang Estate, Bali</title>
<meta name="description" content="<?= lw_e($nombre) ?>: ficha técnica de la villa de obra nueva de <?= lw_e($dormTxt) ?> de Lawang Estate. Alcance de obra, acabados y proceso de compra.">
<?php if (!$precio): ?>
<meta name="robots" content="noindex, nofollow"><!-- sin precio cerrado no se indexa -->
<?php endif; ?>
<link rel="canonical" href="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<link rel="icon" href="/favicon.png">
<meta property="og:title" content="<?= lw_e($nombre) ?> · Villa llave en mano en Bali">
<meta property="og:description" content="Ficha técnica de la villa de <?= lw_e($dormTxt) ?> de Lawang Estate: alcance de obra, acabados y proceso de compra.">
<meta property="og:url" content="https://lawangproperties.com/modelo/<?= lw_e($m['id']) ?>">
<meta property="og:image" content="https://lawangproperties.com<?= lw_e($portada) ?>">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">

<!-- La foto de portada es el LCP: se precarga antes que nada. -->
<link rel="preload" as="image" href="<?= lw_e($portada) ?>" fetchpriority="high">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@400;500&display=swap" rel="stylesheet">
<style>
:root{
  /* Papel, tinta y un solo acento: el verde de la marca. */
  --papel:#F4F1EA;
  --papel2:#EAE5DA;
  --tinta:#1A1D1B;      /* 15,1:1 sobre papel */
  --tinta2:#575C58;     /*  6,0:1 sobre papel — secundario, sigue siendo AA */
  --verde:#1F4A3D;      /*  8,8:1 sobre papel, y papel sobre verde da lo mismo */
  --verde-osc:#16362C;
  --linea:#D8D2C6;
  --linea-fuerte:#C2B9A8;
  --serif:"IBM Plex Serif",Georgia,"Times New Roman",serif;
  --sans:"IBM Plex Sans",ui-sans-serif,system-ui,-apple-system,sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
  --gut:clamp(18px,4vw,48px);
  --barra:54px;
}
*{box-sizing:border-box}
/* El papel, en dos capas y sin una sola petición de red: grano SVG que viaja con el scroll
   + un lavado vertical fijo (más claro arriba, más hondo abajo). Un color plano en toda la
   página delataba la pantalla; con esto el fondo se lee como una hoja.

   El 20% del grano NO se eligió a ojo: medido sobre la captura PNG (sin compresión, que se
   come justo este rango), el papel oscila entre 227 y 243 con desviación 2,1 sobre 255 —
   textura visible que no ensucia la mono de la ficha. Los dos intentos previos se quedaron
   cortos y se veían planos: 4,5% daba 0,84 y 7,5% daba 0,96. La opacidad de un `rect` sobre
   `feTurbulence` NO escala lineal (el ruido trae su propio alfa), así que subirla el doble
   no dobla nada: hay que medir. Con el papel en su punto más oscuro el texto secundario
   sigue dando 5,1:1, o sea AA. */
body{margin:0;color:var(--tinta);font-family:var(--sans);
  font-size:16px;line-height:1.6;-webkit-font-smoothing:antialiased;
  background-image:
    url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.82' numOctaves='3'/%3E%3CfeColorMatrix type='saturate' values='0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.20'/%3E%3C/svg%3E"),
    linear-gradient(180deg,#F9F6F0 0%,var(--papel) 30%,var(--papel) 62%,#ECE7DC 100%);
  background-repeat:repeat,no-repeat;
  background-attachment:scroll,fixed}
img{max-width:100%;display:block}
a{color:var(--verde)}
p{margin:0}
h1,h2,h3{margin:0;font-family:var(--serif);font-weight:400;letter-spacing:-.012em;
  line-height:1.12;text-wrap:balance}
:focus-visible{outline:2px solid var(--verde);outline-offset:3px}

/* Etiqueta de sección: mono, no versal grotesca. Es lo que da el aire de documento. */
.et{font-family:var(--mono);font-size:11px;font-weight:500;letter-spacing:.14em;
  text-transform:uppercase;color:var(--tinta2)}
.num{font-family:var(--mono);font-variant-numeric:tabular-nums}
.dice{color:var(--tinta2);max-width:62ch;margin-top:.9em}

/* ── Cabecera ─────────────────────────────────────────────────────────────── */
/* Translúcida y no `var(--papel)` a secas: con el lavado detrás, un color plano cortaba una
   banda visible justo bajo el borde. El `backdrop-filter` es adorno, y si el motor no lo
   entiende queda el mismo color casi opaco. */
.barra{position:sticky;top:0;z-index:30;height:var(--barra);
  background:rgba(249,246,240,.93);backdrop-filter:blur(8px);
  -webkit-backdrop-filter:blur(8px);
  border-bottom:1px solid var(--linea);display:flex;align-items:center}
.barra__in{width:100%;max-width:1320px;margin-inline:auto;padding-inline:var(--gut);
  display:flex;justify-content:space-between;align-items:center;gap:16px}
.barra b{font-weight:600;font-size:13px;letter-spacing:.2em;text-transform:uppercase}
.barra span{font-family:var(--mono);font-size:11px;letter-spacing:.1em;color:var(--tinta2);
  text-transform:uppercase}

/* ── Rejilla del documento ────────────────────────────────────────────────── */
/* Tres hijos directos: portada · formulario · resto. En escritorio el formulario ocupa la
   segunda columna y se queda pegado; al colapsar a una columna cae por orden de documento,
   o sea justo detrás de la ficha técnica. Sin duplicar el <form> ni reordenar con `order`. */
.doc{width:100%;max-width:1320px;margin-inline:auto;padding:0 var(--gut) 0;
  display:grid;grid-template-columns:minmax(0,1fr) 366px;
  column-gap:clamp(32px,4.5vw,80px)}
.doc > .col{grid-column:1;min-width:0}
.doc > .rail{grid-column:2;grid-row:1 / span 2;align-self:start;
  position:sticky;top:calc(var(--barra) + 24px);padding-top:clamp(36px,5vw,64px)}

.sec{padding-block:clamp(34px,4.5vw,58px);border-top:1px solid var(--linea)}
.sec:first-child{border-top:0}
.sec h2{font-size:clamp(23px,2.4vw,31px);margin-top:.35em}

/* ── Portada ──────────────────────────────────────────────────────────────── */
.port{padding-top:clamp(36px,5vw,64px)}
.port h1{font-size:clamp(31px,4.1vw,52px);margin-top:.28em;max-width:17ch}
.port__fig{margin:clamp(26px,3.4vw,40px) 0 0}
.port__fig img{width:100%;aspect-ratio:16/10;object-fit:cover;border:1px solid var(--linea)}
figcaption{font-family:var(--mono);font-size:11px;letter-spacing:.08em;color:var(--tinta2);
  margin-top:9px;display:flex;justify-content:space-between;gap:14px;flex-wrap:wrap;
  text-transform:uppercase}

/* ── Ficha técnica ────────────────────────────────────────────────────────── */
/* La ficha va sobre su propio panel tintado: es el bloque más denso de la página y, suelto
   sobre el papel, se leía como una tabla que alguien se dejó ahí. Es también lo que da el
   ritmo de bandas que le faltaba al documento. */
.ficha{margin-top:clamp(28px,3.4vw,42px);background:rgba(234,229,218,.62);
  border:1px solid var(--linea);padding:clamp(20px,2.4vw,28px)}
.ficha dl{margin:14px 0 0;display:grid;grid-template-columns:minmax(150px,.85fr) 1.15fr}
.ficha dt,.ficha dd{margin:0;padding:11px 0;border-top:1px solid var(--linea);
  font-size:14.5px}
.ficha dt{color:var(--tinta2)}
.ficha dd{font-family:var(--mono);font-size:13.5px;font-variant-numeric:tabular-nums;
  padding-left:16px}
.ficha dl > :nth-last-child(-n+2){border-bottom:1px solid var(--linea)}
.ficha__nota{font-size:13px;color:var(--tinta2);margin-top:14px;max-width:56ch}

/* ── Botón ────────────────────────────────────────────────────────────────── */
/* Es el único elemento de la página al que se le permite levantar la voz: en una ficha
   sobria, el sitio donde se pincha tiene que ser el que más pesa. Gana cuerpo (altura,
   tamaño y una flecha que avanza), no color chillón — el verde sigue siendo el único
   acento. La sombra es del propio verde y muy abierta: hunde el botón en el papel en vez
   de simular una capa flotante de interfaz. */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:12px;border:0;
  cursor:pointer;background:var(--verde);color:#fff;font-family:var(--sans);
  font-size:15.5px;font-weight:600;letter-spacing:.01em;text-decoration:none;
  padding:19px 24px;width:100%;box-shadow:0 6px 22px -10px rgba(31,74,61,.85);
  transition:background .18s ease,box-shadow .18s ease,transform .12s ease}
.btn svg{width:16px;height:16px;stroke:currentColor;stroke-width:1.9;fill:none;
  transition:transform .24s cubic-bezier(.23,1,.32,1)}
.btn:hover{background:var(--verde-osc);box-shadow:0 10px 26px -10px rgba(31,74,61,.9)}
.btn:hover svg{transform:translateX(4px)}
.btn:active{transform:translateY(1px)}
.btn[disabled]{opacity:.6;cursor:default;box-shadow:none}
@media(prefers-reduced-motion:reduce){
  .btn,.btn svg{transition:none}
  .btn:hover svg{transform:none}
}

/* ── Columna del formulario ───────────────────────────────────────────────── */
/* Filete verde arriba: con el papel ya texturado, un recuadro blanco a secas se leía como
   un hueco. El filete lo convierte en la pieza a la que va el ojo, y cuesta una línea. */
.caja{background:#fff;border:1px solid var(--linea-fuerte);border-top:3px solid var(--verde);
  padding:clamp(20px,2.2vw,26px);box-shadow:0 18px 44px -34px rgba(26,29,27,.55)}
.caja h2{font-size:22px}
.caja .dice{font-size:13.5px;margin-top:.6em}
.campo{margin-top:15px}
.campo label{display:block;font-family:var(--mono);font-size:10.5px;font-weight:500;
  letter-spacing:.1em;text-transform:uppercase;color:var(--tinta2);margin-bottom:6px}
/* Lista separada por comas y NO `:is(input,select)`: un motor que no entiende `:is()`
   descarta la regla ENTERA, y entonces no es que el desplegable se vea raro — es que los
   cuatro campos pierden ancho, borde y padding. La pauta de Meta abre el navegador in-app
   (WebView de Android sin actualizar, Safari viejo), que es justo donde eso pasa. */
.campo input,.campo select{width:100%;font-family:var(--sans);font-size:16px;
  color:var(--tinta);background:var(--papel);border:1px solid var(--linea-fuerte);
  border-radius:0;padding:11px 12px;transition:border-color .16s ease,box-shadow .16s ease}
/* El select nativo pinta su propia flecha y su propio radio segun el SO. Se apaga y se
   dibuja una igual que el resto: en iOS un desplegable con esquinas redondeadas dentro de
   campos de esquina viva se lee como un fallo de la pagina, no como estilo del sistema. */
.campo select{-webkit-appearance:none;appearance:none;cursor:pointer;
  background-image:url("data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 8'%3E%3Cpath d='M1 1.5 6 6.5l5-5' fill='none' stroke='%23575C58' stroke-width='1.6'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:right 12px center;background-size:12px 8px;
  padding-right:34px}
/* En alto contraste el UA fuerza sus colores pero respeta el `background-image`: la flecha
   dibujada se queda por debajo de 3:1 y, con `appearance:none`, el campo pierde a la vez la
   flecha nativa y la nuestra — se lee como un texto que no deja escribir. Se devuelve el
   control al sistema, que es lo que el usuario de ese modo espera. */
@media (forced-colors:active){
  .campo select{background-image:none;-webkit-appearance:auto;appearance:auto;padding-right:12px}
}
.campo input:focus,.campo select:focus{outline:none;border-color:var(--verde);
  box-shadow:0 0 0 3px rgba(31,74,61,.15)}
.campo input[aria-invalid="true"],.campo select[aria-invalid="true"]{
  border-color:#8E3527;box-shadow:0 0 0 3px rgba(142,53,39,.12)}
.campo .err{display:none;font-size:12.5px;color:#8E3527;margin-top:5px}
.campo input[aria-invalid="true"] ~ .err,
.campo select[aria-invalid="true"] ~ .err{display:block}
.acepto{display:flex;gap:10px;align-items:flex-start;font-size:12.5px;color:var(--tinta2);
  line-height:1.45;margin:18px 0}
.acepto input{margin-top:2px;accent-color:var(--verde);flex:0 0 auto;width:16px;height:16px}
.trampa{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
.aviso{margin-top:12px;font-size:13px;color:var(--tinta2);min-height:1.1em}
.aviso--mal{color:#8E3527}
.gracias h2{margin-bottom:.4em}

/* ── Listas técnicas (acabados, alcance, pasos) ───────────────────────────── */
.filas{margin-top:18px}
.fila{display:grid;grid-template-columns:38px 1fr;gap:14px;padding:15px 0;
  border-top:1px solid var(--linea)}
.fila:last-child{border-bottom:1px solid var(--linea)}
.fila > .n{font-family:var(--mono);font-size:12.5px;color:var(--verde);padding-top:3px}
.fila h3{font-family:var(--sans);font-weight:600;font-size:15.5px;letter-spacing:0}
.fila p{font-size:14px;color:var(--tinta2);margin-top:5px;max-width:56ch}

.dosc{display:grid;grid-template-columns:1fr 1fr;gap:clamp(24px,3vw,54px);margin-top:20px}
.dosc h3{font-family:var(--mono);font-size:11px;font-weight:500;letter-spacing:.14em;
  text-transform:uppercase;color:var(--tinta2)}
.dosc ul{list-style:none;margin:12px 0 0;padding:0}
.dosc li{display:grid;grid-template-columns:24px 1fr;gap:8px;padding:9px 0;
  border-top:1px solid var(--linea);font-size:14.5px}
.dosc li:last-child{border-bottom:1px solid var(--linea)}
.dosc li i{font-style:normal;font-family:var(--mono);font-size:12px;color:var(--verde);
  padding-top:2px}
.dosc--no li i{color:var(--tinta2)}
.dosc__nota{font-size:13px;color:var(--tinta2);margin-top:16px;max-width:52ch}

/* ── Láminas de imagen (siempre contenidas, nunca a sangre) ───────────────── */
.laminas{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:20px}
.laminas img{width:100%;aspect-ratio:4/3;object-fit:cover;border:1px solid var(--linea)}

/* ── Preguntas ────────────────────────────────────────────────────────────── */
.faq{margin-top:18px;max-width:74ch}
.faq details{border-top:1px solid var(--linea)}
.faq details:last-of-type{border-bottom:1px solid var(--linea)}
.faq summary{cursor:pointer;list-style:none;padding:15px 36px 15px 0;position:relative;
  font-size:15.5px;font-weight:500}
.faq summary::-webkit-details-marker{display:none}
.faq summary::after{content:"+";position:absolute;right:6px;top:14px;font-family:var(--mono);
  color:var(--verde);font-size:16px}
.faq details[open] summary::after{content:"–"}
.faq details p{padding:0 0 18px;font-size:14.5px;color:var(--tinta2);max-width:68ch}
.faq summary:hover{color:var(--verde)}

/* ── Pie ──────────────────────────────────────────────────────────────────── */
.pieweb{border-top:1px solid var(--linea);margin-top:clamp(36px,5vw,64px);
  padding-block:26px;font-size:12.5px;color:var(--tinta2)}
.pieweb .in{width:100%;max-width:1320px;margin-inline:auto;padding-inline:var(--gut);
  display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap}

/* ── Barra fija de móvil ──────────────────────────────────────────────────── */
.fijo{position:fixed;left:0;right:0;bottom:0;z-index:40;display:none;
  padding:10px 14px calc(10px + env(safe-area-inset-bottom));
  background:rgba(244,241,234,.94);backdrop-filter:blur(8px);
  -webkit-backdrop-filter:blur(8px);border-top:1px solid var(--linea-fuerte)}
.fijo.off{display:none}

@media(max-width:1040px){
  .doc{grid-template-columns:minmax(0,1fr)}
  .doc > .col,.doc > .rail{grid-column:1;grid-row:auto}
  /* Sin columna, la caja deja de estar pegada: pasa a ser una sección más del documento,
     colocada justo detrás de la ficha técnica. */
  .doc > .rail{position:static;padding-top:0;padding-bottom:clamp(30px,4vw,44px);
    border-top:1px solid var(--linea);margin-top:clamp(30px,4vw,44px)}
  .fijo{display:block}
  /* consent.js inyecta su <style> DESPUÉS de este y con la misma especificidad ganaba
     por orden: el aviso se sentaba encima de la barra fija. */
  body #lw-consent-bar{bottom:76px}
}
@media(max-width:640px){
  .dosc,.laminas{grid-template-columns:1fr}
  .ficha dl{grid-template-columns:1fr 1fr}
}
/* A 390 px la coletilla de la cabecera queda pegada a la marca y las dos se leen como una
   sola línea de ruido. Es decoración: se retira antes que apretar el cuerpo. */
@media(max-width:520px){ .barra span{display:none} }
@media print{
  .barra,.fijo,.rail{display:none}
  body{background:#fff}
  .faq details{display:block}
}
</style>
</head>
<body>

<!-- Sin menú ni enlace al catálogo A PROPÓSITO: es tráfico de pago, y toda salida que no
     sea el formulario o los legales es un clic pagado que se va. -->
<header class="barra">
  <div class="barra__in">
    <b>Lawang Estate</b>
    <span>Ficha de producto · <?= lw_e($nombre) ?></span>
  </div>
</header>

<div class="doc">

<!-- ── Columna 1 · Portada y ficha ──────────────────────────────────────── -->
<div class="col port">
  <p class="et">Modelo <?= lw_e($nombre) ?> · Obra nueva · Bali, Indonesia</p>
  <h1>Villa llave en mano de <?= lw_e($dormTxt) ?>, construida sobre la parcela que elijas</h1>
  <p class="dice"><?= lw_e($m['sub']) ?></p>

  <figure class="port__fig">
    <img src="<?= lw_e($portada) ?>" alt="Villa <?= lw_e($nombre) ?> de Lawang Estate: exterior con piscina overflow" fetchpriority="high">
    <figcaption><span><?= lw_e($nombre) ?> · Exterior</span><span>Render de proyecto</span></figcaption>
  </figure>

  <div class="ficha">
    <p class="et">Ficha técnica</p>
    <dl>
      <?php foreach ($ficha as $f): ?>
      <dt><?= lw_e($f[0]) ?></dt><dd><?= lw_e($f[1]) ?></dd>
      <?php endforeach; ?>
    </dl>
    <p class="ficha__nota">Los datos proceden del pliego del contratista. Superficie construida,
      superficie de parcela y plazo de obra se concretan por parcela y se entregan por escrito
      con el presupuesto.</p>
  </div>
</div>

<!-- ── Columna 2 · Formulario, siempre a la vista ───────────────────────── -->
<aside class="rail" id="lw-rail">
  <div class="caja">
    <form id="lw-form" novalidate>
      <p class="et">Solicitud</p>
      <h2>Reserva tu llamada</h2>
      <p class="dice">Media hora. Te damos el presupuesto cerrado del acabado que te interese
        y las parcelas disponibles donde puede construirse.</p>

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
        <!-- Con `type=tel` a secas vale cualquier cosa, y GHL rechaza el alta entera por el
             telefono: se pierden tambien nombre y email, sin que el visitante vea nada.
             Minimo 9 digitos, admite prefijo, espacios, guiones y parentesis. -->
        <input type="tel" id="lw-tel" name="phone" autocomplete="tel" required maxlength="40"
               pattern="[+]?[0-9\s().-]{9,}" inputmode="tel">
        <span class="err">Necesitamos un teléfono para llamarte.</span>
      </div>

      <div class="campo">
        <label for="lw-presupuesto">Presupuesto que manejas</label>
        <?php /* Comentario de PHP y NO de HTML, misma razon que el de "freehold" mas abajo:
             este texto cita CIFRAS DE PRECIO, y en un comentario HTML viajaria al navegador
             y saldria en "ver codigo fuente" de una pagina que paga trafico. Lo pillo el
             verificador el 3-ago-2026, con la version en HTML ya en produccion.

             El rango lo declara el LEAD; no se deduce del modelo que mira. Este campo es lo
             que reparte el seguimiento por gama en el CRM: sin el, las tres gamas caen en la
             misma cola y habria que abrir tres campanas en Meta para lo mismo.
             Tres decisiones que no se revierten sin motivo:
             · Son RANGOS, no importes. Un importe obliga a inventar el suelo de cada tramo
               (nuestros precios no estan cerrados) y a decidir a que tramo va quien maneja
               justo la cifra de la frontera.
             · El tramo bajo NO enseña un suelo. Enseñarlo publicaba un punto de entrada que
               no existe: la unica referencia que tenemos para una Dali es la de otro
               operador, muy por encima, y captabamos gente convencida de que con esa cifra
               se compra una villa.
             · "Todavia no lo tengo claro" no se quita. Es lo que sostiene el `required`:
               con base 6.1.b solo cabe exigir lo necesario para atender la solicitud, y el
               presupuesto no hace falta para devolver una llamada. Sin esa salida, el campo
               pasa a ser condicion de acceso a un servicio que no la requiere. */ ?>
        <select id="lw-presupuesto" name="presupuesto" required aria-describedby="lw-presupuesto-err">
          <option value="" selected disabled>Elige un rango</option>
          <option value="bajo">Menos de 100.000 €</option>
          <option value="medio">Entre 100.000 y 175.000 €</option>
          <option value="alto">Más de 175.000 €</option>
          <option value="nose">Todavía no lo tengo claro</option>
        </select>
        <span class="err" id="lw-presupuesto-err">Dinos por dónde te mueves para preparar la llamada.</span>
      </div>

      <!-- Trampa de bots: un humano nunca la ve, así que si viene rellena, es un bot. -->
      <div class="trampa" aria-hidden="true"><label for="lw-web">No rellenar</label>
        <input type="text" id="lw-web" name="website" tabindex="-1" autocomplete="off"></div>

      <label class="acepto" for="lw-consent">
        <input type="checkbox" id="lw-consent" name="consent" value="1" required>
        <!-- A la version ESPAÑOLA. El checkbox esta en español y remitia a un texto solo en
             ingles: un consentimiento cuya unica explicacion esta en otro idioma es
             atacable (art. 12.1 RGPD), y aqui es la base declarada del tratamiento. -->
        <span>He leído y acepto la <a href="/legal-es#privacidad" target="_blank" rel="noopener">Política de Privacidad</a>
          y que Lawang Estate guarde mis datos en su sistema de gestión de clientes para
          contactarme sobre este modelo.</span>
      </label>

      <button class="btn" type="submit" id="lw-submit"><span>Reservar mi llamada</span>
        <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2 8h12M9 3l5 5-5 5"/></svg>
      </button>
      <p class="aviso" id="lw-aviso" role="status" aria-live="polite"></p>
    </form>
  </div>
</aside>

<!-- ── Columna 1 · Resto del documento ──────────────────────────────────── -->
<div class="col">

<?php if ($m['acabados']): ?>
  <section class="sec">
    <p class="et">01 · Acabados</p>
    <h2>La cubierta es lo único que cambia el presupuesto</h2>
    <p class="dice">El resto de la villa no varía entre las tres opciones. Se elige antes de
      cerrar números, y el precio de cada una se entrega por escrito.</p>
    <div class="filas">
      <?php foreach ($m['acabados'] as $i => $a): ?>
      <div class="fila">
        <span class="n"><?= str_pad($i + 1, 2, '0', STR_PAD_LEFT) ?></span>
        <div>
          <h3><?= lw_e($a['n']) ?></h3>
          <p><?= lw_e($a['d']) ?></p>
        </div>
      </div>
      <?php endforeach; ?>
    </div>
    <figure class="port__fig">
      <img src="/assets/img/modelo/dali-cubierta.jpg" alt="Detalle de la cubierta de alang-alang de la villa <?= lw_e($nombre) ?>" loading="lazy">
      <figcaption><span>Cubierta de alang-alang</span><span>Render de proyecto</span></figcaption>
    </figure>
  </section>
<?php endif; ?>

<?php if ($m['alcance']): ?>
  <section class="sec">
    <p class="et">02 · Alcance de obra</p>
    <h2>Qué entra en el precio y qué no</h2>
    <div class="dosc">
      <div>
        <h3>Incluido</h3>
        <ul>
          <?php foreach ($m['alcance']['incluido'] as $k => $li): ?>
          <li><i><?= str_pad($k + 1, 2, '0', STR_PAD_LEFT) ?></i><span><?= lw_e($li) ?></span></li>
          <?php endforeach; ?>
        </ul>
      </div>
      <div>
        <h3>No incluido</h3>
        <ul class="dosc--no">
          <?php foreach ($m['alcance']['no_incluido'] as $li): ?>
          <li><i>&ndash;</i><span><?= lw_e($li) ?></span></li>
          <?php endforeach; ?>
        </ul>
        <p class="dosc__nota">Tal cual figura en el pliego del contratista. La parcela y los
          gastos de compraventa (impuestos, notaría y licencias) se presupuestan aparte y se
          detallan por escrito antes de firmar nada.</p>
      </div>
    </div>
  </section>
<?php endif; ?>

<?php if ($resto): ?>
  <section class="sec">
    <p class="et">03 · El producto</p>
    <h2><?= lw_e($nombre) ?>, por dentro</h2>
    <div class="laminas">
      <?php foreach ($resto as $i => $img): ?>
      <img src="<?= lw_e($img) ?>" alt="Render del proyecto de la villa <?= lw_e($nombre) ?> (<?= $i + 2 ?> de <?= count($g) ?>)" loading="lazy">
      <?php endforeach; ?>
    </div>
    <p class="ficha__nota">Todas las imágenes de esta sección son renders del proyecto, no
      fotografías de una villa terminada.</p>
  </section>
<?php endif; ?>

  <section class="sec">
    <p class="et">04 · El sitio</p>
    <h2>La costa, fotografiada</h2>
    <p class="dice">Estas dos imágenes no son renders: son fotografías tomadas con dron en la
      zona. En la llamada te decimos qué parcelas quedan y cómo se llega a cada una.</p>
    <div class="laminas">
      <img src="/assets/img/lugar/costa.jpg" alt="Desembocadura del río y playa de arena volcánica en la costa oeste de Bali, vista cenital" loading="lazy">
      <img src="/assets/img/lugar/rio.jpg" alt="Valle y río junto a la costa, vista aérea" loading="lazy">
    </div>
    <p class="ficha__nota">Fotografía real con dron · Costa oeste de Bali</p>
  </section>

  <section class="sec">
    <p class="et">05 · Proceso</p>
    <h2>Cómo se compra</h2>
    <div class="filas">
      <div class="fila"><span class="n">01</span><div><h3>Llamada</h3>
        <p>Media hora para ver qué parcela encaja, con qué presupuesto y en qué plazos.</p></div></div>
      <div class="fila"><span class="n">02</span><div><h3>Presupuesto y parcela</h3>
        <p>Precio cerrado del acabado elegido, parcela concreta y calendario de pagos.</p></div></div>
      <div class="fila"><span class="n">03</span><div><h3>Reserva y obra</h3>
        <p>Contrato de reserva, después el PPJB de compraventa y el contrato de construcción, y arranca la obra.</p></div></div>
    </div>
  </section>

  <section class="sec">
    <p class="et">06 · Preguntas</p>
    <h2>Lo que suelen preguntar antes de la llamada</h2>
    <div class="faq">
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
  </section>

</div><!-- /col -->
</div><!-- /doc -->

<footer class="pieweb">
  <div class="in">
    <span>Lawang Estate · PT Tepi Sun Gai · Bali, Indonesia</span>
    <span><a href="/legal">Aviso legal y privacidad</a> ·
      <!-- Retirar el consentimiento tiene que ser tan facil como darlo (RGPD art. 7.3). -->
      <a href="#" onclick="window.lwConsentReopen&&window.lwConsentReopen();return false">Preferencias de cookies</a></span>
  </div>
</footer>

<div class="fijo" id="lw-fijo">
  <a class="btn" href="#lw-rail">Reservar mi llamada
    <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2 8h12M9 3l5 5-5 5"/></svg>
  </a>
</div>

<script src="/assets/consent.js?v=20260731100255" defer></script>
<script>
(function () {
  'use strict';
  var MODELO = <?= json_encode($m['id']) ?>;
  // Calendario "Llamada Lawang" de GoHighLevel. Los huecos que ve el lead salen en su
  // propia zona horaria; los del comercial estan definidos en la location (Asia/Singapore).
  var CALENDARIO = 'https://api.leadconnectorhq.com/widget/booking/mfWBXvZPd703uOwOV3F0';
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

  var form = document.getElementById('lw-form');
  var aviso = document.getElementById('lw-aviso');
  var btn = document.getElementById('lw-submit');
  var fijo = document.getElementById('lw-fijo');
  var rail = document.getElementById('lw-rail');
  var campos = ['lw-nombre', 'lw-email', 'lw-tel', 'lw-presupuesto'];

  // ── Paso intermedio del embudo ────────────────────────────────────────────
  // La version anterior lo emitia al abrir el <dialog>. Sin panel, el equivalente honesto
  // de "esta persona ha empezado" es el primer foco en un campo: sin este evento Meta solo
  // ve "vio la pagina" y "dejo los datos", y no tiene nada intermedio que optimizar.
  var empezado = false;
  form.addEventListener('focusin', function () {
    if (empezado) return;
    empezado = true;
    track('InitiateCheckout');
  });

  // ── Barra fija de movil: se retira cuando el formulario ya esta en pantalla ──
  var ioFijo = null;
  if ('IntersectionObserver' in window) {
    ioFijo = new IntersectionObserver(function (es) {
      fijo.classList.toggle('off', es[0].isIntersecting);
    }, {threshold: 0.25});
    ioFijo.observe(rail);
  }

  // ── Envío ─────────────────────────────────────────────────────────────────
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
        p.textContent = 'Elige tú la hora y hablamos cuando te venga bien. Si no, te llamamos nosotros.';
        // El lead ya esta guardado; esto es el paso que de verdad vale. Nueva pestana y no
        // iframe: el widget de GHL se redimensiona con su propio script y dentro de una
        // columna estrecha se queda cortado en movil, que es donde llega la pauta.
        var cal = document.createElement('a');
        cal.className = 'btn';
        cal.style.marginTop = '1.4em';
        // Sin nombre, email ni telefono en la URL: quedarian en el historial del navegador,
        // en los logs de leadconnectorhq.com y en el Referer que esa pagina manda a sus
        // terceros. El dato ya viaja al CRM por API; en la URL es exposicion de mas.
        cal.href = CALENDARIO;
        cal.target = '_blank';
        cal.rel = 'noopener noreferrer';
        cal.textContent = 'Elegir hora para la llamada';
        // Evento PROPIO, no el `Schedule` estandar: esto es un clic en el boton, no una cita
        // reservada. El widget vive en otro dominio sin pixel y nunca devuelve confirmacion,
        // asi que emitir `Schedule` aqui le ensena al algoritmo a buscar gente que abre
        // calendarios y se va. La cita real se cerrara por CAPI desde un workflow de GHL.
        // Sin `value` a proposito: ya lo llevan ViewContent, InitiateCheckout y Lead, y un
        // mismo visitante contaria la misma villa cuatro veces en cualquier columna de ROAS.
        cal.addEventListener('click', function () {
          if (typeof window.lwTrack === 'function') {
            window.lwTrack('AbrioCalendario', {content_ids: [MODELO], content_type: 'product'}, true);
          }
        });
        // El widget de GHL etiqueta los huecos en la zona de la CUENTA (hoy Asia/Singapore,
        // la misma hora que Bali) y no acepta forzarla por URL — probadas ?timezone,
        // ?timeZone y ?tz, ninguna la cambia. Sin este aviso el lead espanol abre el
        // calendario, lee "16:00" y se va creyendo que no hay horas de mañana. Las horas
        // son correctas en absoluto: 16:00-23:00 de Bali son las 10:00-17:00 de Madrid.
        // Esta linea SE BORRA en cuanto el owner ponga la location en Europe/Madrid.
        var tzAviso = document.createElement('p');
        tzAviso.className = 'dice';
        tzAviso.style.fontSize = '13px';
        tzAviso.textContent = 'El calendario abre en hora de Bali. Cámbiala a la tuya con el '
          + 'selector de zona horaria que hay bajo el calendario.';
        form.textContent = '';
        form.className = 'gracias';
        form.appendChild(h); form.appendChild(p); form.appendChild(cal); form.appendChild(tzAviso);
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
