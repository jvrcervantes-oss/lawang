<?php
/* Investor Deck genérico — v3 (24-sep-2026).
   El owner decidió el 24-sep-2026: «v3 es el diseño estándar ahora de todos los
   investor-deck». v3 es investor-deck/palmfield/index.html: la piel y la
   COMPOSICIÓN de la home pública (topbar transparente que se vuelve sólida al
   bajar, menú móvil <1180px, hero a sangre 100svh con el panel de documentos+FAQ
   en cristal oscuro a la derecha, secciones .sec-lino/.sec-foto, tarjetas de
   villa altas a foto completa, pie compartido /assets/lawang-pie.js). Este
   fichero lleva esa piel alimentada por los datos genéricos. La versión anterior
   queda en index_v1.php, servida en /investor-deck/v1/<slug> (regla 3e-v1 del
   .htaccess) por si hay que restaurarla.

   Qué se mantiene de la v1, igual: las 7 llamadas (deck_config_publico y las 6
   investor_deck_*), la aritmética del forecast, los escapes (esc/textContent/
   urlSegura) y los textos en inglés ya aprobados — i18n.js casa por texto
   completo. Qué entra de la v3 y qué no, cada cosa con su motivo, en el
   comentario de la sección correspondiente.

   Cambios de lógica frente a la v1 (los únicos):
   · urlSegura() vivía DENTRO de pintaDocs y el .then de documentos la llamaba
     desde fuera: ReferenceError tragado por el .catch vacío, y el botón
     "Download dossier" de cabecera no se encendía NUNCA. Ahora vive en el ámbito
     del IIFE, como en la v3.
   · Cero filas ya no es un error. Modelos/forecast con [] pintaban «We could not
     load…»: con 4 de los 5 decks abiertos sin forecast, eso era un aviso de fallo
     falso en cada visita. Ahora: [] → la sección se omite (decisión 3 de abajo);
     fallo de red → el aviso, que es cuando es verdad. Las dos cosas se ven
     distintas en pantalla, que es la regla.
   · Tailwind Play CDN retirado (prohibido en producción): se reutiliza el build
     de la v3, /investor-deck/palmfield/v2.min.css, y todo el marcado propio usa
     clases de este <style>, no utilidades que el build podría no tener.

   Decisiones de la v1 que SE MANTIENEN (15-sep-2026, revisión previa Seguridad +
   Datos + Diseño y 3 rondas de confirmación del owner), cada una con su motivo:
   1. SIN reserva de autoservicio. El piloto de Palm Field tiene su propia
      config legal (investor_deck_config, validez/plazo/jurisdicción) ya
      revisada; generalizar ese flujo a 29 proyectos sin una fila de config
      por proyecto habría emitido Cartas de Reserva con los términos del
      primer proyecto activado para todos los demás (hallazgo de Datos). El
      owner decidió (15-sep) resolverlo quitando la reserva de autoservicio
      del deck genérico entero. SIGUE EN PIE: nunca un botón "Reserve".
      Lo único que cambia (24-sep-2026, owner: «v3 es el diseño estándar»;
      consulta de deploy capa 1, Marketing) es el CANAL de contacto: cada
      parcela disponible lleva "Talk to us on WhatsApp" con el proyecto y el
      código ya escritos en el mensaje, como la v3 de Palm Field desde el
      22-sep; antes era "Contact us" (mailto:sales@lawangproperties.com).
   2. SIN plano interactivo por defecto. Las coordenadas de un masterplan se
      miden a mano sobre la imagen concreta de CADA proyecto — no es derivable
      de una plantilla. Gate `config.masterplan_activo`: si es false, la lista
      de parcelas en vivo (investor_deck_parcelas) se sigue viendo igual, a
      ancho completo; solo se omite la imagen+hotspots.
   3. Nunca placeholders (Diseño). Sin fotos/KPIs/forecast propios, esas
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
<link href="https://fonts.googleapis.com/css2?family=Jost:ital,wght@0,300;0,400;0,500;0,600;1,400&family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap" rel="stylesheet">
<!-- Build Tailwind de la v3: de aqui SOLO sale el reset (preflight). Las 4 reglas de
     posicion del plano que antes se tomaban de sus utilidades viven ya en el <style> de
     abajo (#plan-wrap/#plan-hotspots, consulta de deploy capa 1, 24-sep), para que el
     deck generico no dependa de que el build del piloto siga teniendolas.
     Ruta ABSOLUTA: esta pagina se sirve en /investor-deck/<slug>. -->
<link rel="stylesheet" href="/investor-deck/palmfield/v2.min.css?v=20260924a">
<style>
/* ════ v3 — piel de lawangproperties.com (home), calcada de investor-deck/palmfield/ ════
   Sin The Seasons a proposito: es una fuente DEMO que corrompe & - + 4, y aqui el
   titular sale de la base (p.ej. "Sari Village W1, 1.1 & 1.2"): no hay forma de
   garantizar que no los lleve. Todo va en Neue Kabel, como las cifras de la v3. */
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-ExtraLight.otf') format('opentype');font-weight:200;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Light.otf') format('opentype');font-weight:300;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Book.otf') format('opentype');font-weight:400;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Medium.otf') format('opentype');font-weight:500;font-display:swap}
@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/NeueKabel-Bold.otf') format('opentype');font-weight:700;font-display:swap}

:root{
  --tg:#485B37; --pg:#587040; --tg-dark:#364429; --dl:#104C4F; --be:#42210B; --sc:#8F9B7A;
  --va:#2E3437; --ss:#BEB3A5; --rl:#F5F0E6; --rl2:#EFE8DA; --cbr:#FBF8F1;
  --ci:#2E3437; --ci2:#5A5048; --ci3:#8A7A6A; --cl:#DED5C3; --ob:#0A0C09; --card:#11150E;
  --sa:'Neue Kabel','Jost',system-ui,sans-serif;
  --cpd:clamp(22px,5vw,72px); --cmx:1280px; --menu-h:35px;
  --fs-display:clamp(44px,30px + 3.4vw,92px);
  --fs-h-xl:clamp(36px,30px + 1.9vw,60px);
  --fs-body-l:clamp(16px,15.5px + .15vw,18px);
  --fs-cap:clamp(11px,10.6px + .12vw,13px);
  --ease:cubic-bezier(.16,1,.3,1);
}
[hidden]{display:none!important}
html{scroll-behavior:smooth;scroll-padding-top:64px}
html,body{margin:0;padding:0}
body{background:var(--rl);color:var(--ci);font-family:var(--sa);-webkit-font-smoothing:antialiased;overscroll-behavior:none}
::-webkit-scrollbar{display:none}
h1,h2{text-wrap:balance} p{text-wrap:pretty}
.material-symbols-outlined{font-variation-settings:'FILL' 0,'wght' 300,'GRAD' 0,'opsz' 24;vertical-align:middle}
.lw-money{white-space:nowrap;font-variant-numeric:tabular-nums}
.sr{position:absolute!important;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.wrap{max-width:var(--cmx);margin:0 auto;padding-inline:var(--cpd);width:100%;box-sizing:border-box}
a.enlace{color:inherit;text-decoration:underline}

/* ── Estado "deck no disponible" (decision 4): nace visible, el JS lo apaga ── */
#deck-no-disponible{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px;text-align:center;background:var(--ob);color:var(--rl)}
#deck-no-disponible > div{max-width:28rem;display:flex;flex-direction:column;align-items:center;gap:16px}
#deck-no-disponible img{height:30px;width:auto}
#deck-no-disponible p{margin:0;font-size:14px;line-height:1.7;color:rgba(245,240,230,.75)}
#deck-no-disponible p.grande{font-weight:300;font-size:22px;line-height:1.3;letter-spacing:.04em;text-transform:uppercase;color:var(--rl)}

/* ── Topbar: calco de #topbar de la home. Transparente sobre la hero, solida al bajar ── */
#topbar{position:fixed;top:0;left:0;right:0;z-index:50;display:flex;align-items:center;justify-content:space-between;gap:1rem;
  padding:clamp(.68rem,1.65vh,1.05rem) clamp(1.1rem,4vw,3.4rem);transition:background .3s,box-shadow .3s,padding .3s}
#topbar.solid{background:rgba(247,244,239,.94);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);
  box-shadow:0 1px 0 rgba(190,179,165,.3);padding-top:clamp(.5rem,1.2vh,.8rem);padding-bottom:clamp(.5rem,1.2vh,.8rem)}
#logo{display:flex;align-items:center;flex:1 1 0;min-width:0}
#logo img{height:28px;width:auto;display:block;transition:height .3s}
#logo .lg-d{display:none}
#topbar.solid #logo .lg-w{display:none}
#topbar.solid #logo .lg-d{display:block}
#topbar.solid #logo img{height:24px}
#nav-principal{flex:none;display:none;align-items:center;gap:clamp(1rem,1.7vw,1.7rem);height:var(--menu-h);padding:0 1.5rem;
  background:rgba(20,18,14,.22);border:1px solid rgba(190,179,165,.45);border-radius:40px;
  backdrop-filter:blur(5px);-webkit-backdrop-filter:blur(5px);transition:background .3s,border-color .3s}
@media(min-width:1180px){#nav-principal{display:flex}}
#topbar.solid #nav-principal{background:rgba(255,255,255,.5);border-color:rgba(72,91,55,.28)}
.nav-link{position:relative;font-family:var(--sa);font-weight:300;font-size:.64rem;letter-spacing:.13em;text-transform:uppercase;
  color:rgba(245,240,230,.92);text-decoration:none;text-shadow:0 1px 8px rgba(0,0,0,.55);white-space:nowrap;transition:color .3s}
.nav-link::after{content:"";position:absolute;left:0;right:0;bottom:-7px;height:1.5px;background:var(--ss);transform:scaleX(0);transition:transform .32s var(--ease)}
.nav-link:hover{color:#fff}
.nav-link:hover::after,.nav-link.lw-nav-activa::after{transform:scaleX(1)}
#topbar.solid .nav-link{color:rgba(26,22,18,.72);text-shadow:none}
#topbar.solid .nav-link:hover,#topbar.solid .nav-link.lw-nav-activa{color:var(--pg)}
#topbar.solid .nav-link::after{background:var(--pg)}
#acciones{display:flex;align-items:center;justify-content:flex-end;gap:clamp(.6rem,1.6vw,1.4rem);flex:1 1 0;min-width:0}
#deck-selectores{--lw-lang-ink:#f5f0e6;--lw-lang-bg:rgba(18,16,12,.85);--lw-lang-line:rgba(190,179,165,.38);--lw-lang-menu-ink:#f5f0e6;--lw-lang-hover:rgba(190,179,165,.18)}
#deck-selectores{display:flex;align-items:center;gap:4px;flex-wrap:nowrap}
#deck-selectores > *{flex:none}
#deck-selectores *{font-family:var(--sa)!important;letter-spacing:.14em}
#topbar:not(.solid) #deck-selectores{text-shadow:0 1px 8px rgba(0,0,0,.55)}
#topbar.solid #deck-selectores{--lw-lang-ink:#2e3437;--lw-lang-bg:#fff;--lw-lang-line:rgba(72,91,55,.2);--lw-lang-menu-ink:#2e3437;--lw-lang-hover:rgba(72,91,55,.1)}
@media (max-width:1023px){ #topbar .lw-lang__btn{min-height:40px} }
/* CTA "Download dossier" = .nav-cta de la home: ghost sobre la foto, verde al bajar.
   Nace oculto ([hidden]): solo se enciende si el proyecto tiene un dosier comercial. */
#cta-dosier{display:inline-flex;align-items:center;gap:.45rem;height:var(--menu-h);padding:0 16px 0 12px;border-radius:30px;
  border:1px solid rgba(245,240,230,.5);color:var(--rl);background:transparent;text-decoration:none;
  font-family:var(--sa);font-weight:400;font-size:11px;letter-spacing:.14em;text-transform:uppercase;white-space:nowrap;transition:all .35s}
#cta-dosier:hover{background:rgba(245,240,230,.14);border-color:rgba(245,240,230,.78)}
#cta-dosier .material-symbols-outlined{font-size:16px}
#topbar.solid #cta-dosier{background:var(--pg);border-color:var(--pg)}
#topbar.solid #cta-dosier:hover{background:#3a4a2c;border-color:#3a4a2c}
@media(max-width:640px){#cta-dosier{display:none!important}}
@media(min-width:1180px) and (max-width:1560px){#cta-dosier span:not(.material-symbols-outlined){display:none}#cta-dosier{padding:0 10px}}
#menu-btn{display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;border-radius:50%;cursor:pointer;
  background:transparent;border:1px solid rgba(245,240,230,.5);color:var(--rl);transition:all .3s}
#topbar.solid #menu-btn{border-color:rgba(72,91,55,.3);color:var(--ci)}
@media(min-width:1180px){#menu-btn{display:none}}
#menu-movil{position:fixed;top:64px;left:12px;right:12px;z-index:49;display:flex;flex-direction:column;gap:2px;padding:10px;border-radius:18px;
  background:rgba(18,16,12,.82);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);border:1px solid rgba(190,179,165,.38)}
#menu-movil a{font-family:var(--sa);font-size:12px;font-weight:300;letter-spacing:.18em;text-transform:uppercase;
  color:rgba(245,240,230,.88);padding:14px 16px;border-radius:10px;text-decoration:none}
#menu-movil a:hover,#menu-movil a.lw-nav-activa{background:rgba(190,179,165,.18);color:#fff}

/* WhatsApp flotante: circulo verde de la home */
#cta-whatsapp{position:fixed;right:clamp(16px,2.5vw,28px);bottom:clamp(16px,2.5vw,28px);z-index:40;width:58px;height:58px;border-radius:50%;
  display:flex;align-items:center;justify-content:center;background:#25D366;color:#fff;box-shadow:0 10px 30px rgba(0,0,0,.28);
  transition:transform .25s var(--ease)}
#cta-whatsapp:hover{transform:translateY(-2px) scale(1.04)}
#cta-whatsapp svg{width:30px;height:30px}

/* ── Titulares compartidos: .lw-kicker / .lw-title de la home ── */
.kicker{display:inline-flex;align-items:center;gap:12px;font-family:var(--sa);font-size:var(--fs-cap);font-weight:500;
  letter-spacing:.26em;text-transform:uppercase;color:var(--tg);margin:0}
.kicker::before{content:"";width:30px;height:1px;background:currentColor;opacity:.5}
.center .kicker::before{display:none}
.titulo{font-family:var(--sa);font-weight:700;text-transform:uppercase;line-height:1.02;letter-spacing:.005em;color:var(--ci);font-size:var(--fs-h-xl);margin:0}
.entrada{font-family:var(--sa);font-size:var(--fs-body-l);line-height:1.75;color:var(--ci2);max-width:56ch;margin:0}
.cab{display:flex;flex-direction:column;gap:14px}
.cab.center{align-items:center;text-align:center;margin-inline:auto;max-width:860px}
.cab.center .entrada{margin-inline:auto}
.btn{display:inline-flex;align-items:center;gap:10px;padding:14px 28px;border-radius:40px;font-family:var(--sa);font-size:11px;font-weight:500;
  letter-spacing:.14em;text-transform:uppercase;text-decoration:none;border:1px solid transparent;cursor:pointer;
  transition:transform .16s cubic-bezier(.23,1,.32,1),background .22s,color .22s,border-color .22s}
.btn:active{transform:scale(.97)}
.btn-hueso{border-color:rgba(245,240,230,.5);color:var(--rl);background:rgba(245,240,230,.06)} .btn-hueso:hover{background:rgba(245,240,230,.14)}
.btn-verde{background:var(--tg);color:var(--rl)} .btn-verde:hover{background:var(--tg-dark)}
.reveal{opacity:0;transform:translateY(28px);filter:blur(4px);transition:opacity .85s var(--ease),transform .85s var(--ease),filter .85s var(--ease)}
.reveal.in{opacity:1;transform:none;filter:none}
@media(prefers-reduced-motion:reduce){.reveal{transform:none;filter:none;transition:opacity .4s}}
/* Estado de aviso (fallo de carga) sobre fondo claro u oscuro: hereda el color. */
.aviso{grid-column:1/-1;padding:22px 24px;border-radius:14px;border:1px dashed currentColor;font-size:14px;line-height:1.7;opacity:.85}

/* ── 1 · HERO a pantalla completa (patron .hero-panel de la home) ── */
#vision{position:relative;min-height:600px;background:var(--ob);color:var(--rl)}
#hero-visual{position:relative;height:100svh;min-height:600px}
@media(min-width:1024px){#hero-visual{position:absolute;inset:0;height:auto}}
#hero-track{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scroll-behavior:smooth;width:100%;height:100%;scrollbar-width:none}
#hero-track figure{margin:0;flex:none;width:100%;height:100%;scroll-snap-align:center;position:relative}
#hero-track img{width:100%;height:100%;object-fit:cover;display:block}
/* Pie de cada foto de la hero, arriba a la izquierda. La v3 de Palm Field lo quito;
   aqui se queda: varias fotos de proyecto son renders, y el render publicado tiene que
   declararse (Permendag 19/2026 para la imagen generada; en la UE integra la oferta). */
#hero-track figcaption{position:absolute;z-index:3;top:clamp(78px,11vh,96px);left:var(--cpd);max-width:min(60%,520px);
  padding:6px 12px;border-radius:30px;background:rgba(10,12,9,.45);backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px);
  font-family:var(--sa);font-size:10.5px;letter-spacing:.14em;text-transform:uppercase;color:rgba(245,240,230,.88)}
.hero-vacia{width:100%;height:100%;display:flex;align-items:center;justify-content:center;font-size:12px;letter-spacing:.2em;text-transform:uppercase;color:rgba(245,240,230,.6);background:#1B1F18}
.hero-velo{position:absolute;inset:0;pointer-events:none;
  background:linear-gradient(to top,rgba(10,12,9,.86) 0%,rgba(10,12,9,.45) 38%,rgba(10,12,9,.08) 62%,rgba(10,12,9,.38) 100%)}
.hero-flecha{position:absolute;top:50%;transform:translateY(-50%);z-index:5;width:46px;height:46px;border-radius:50%;display:none;align-items:center;justify-content:center;
  border:1px solid rgba(245,240,230,.45);background:rgba(20,18,14,.22);color:var(--rl);cursor:pointer;backdrop-filter:blur(6px);transition:all .3s}
.hero-flecha:hover{background:rgba(245,240,230,.16)}
.hero-flecha:disabled{opacity:0;pointer-events:none}
@media(min-width:768px){.hero-flecha{display:flex}}
#hero-prev{left:clamp(14px,2.5vw,36px)} #hero-next{right:clamp(14px,2.5vw,36px)}
.hero-texto{position:absolute;z-index:4;left:var(--cpd);right:var(--cpd);top:calc(100svh - clamp(96px,17vh,170px));transform:translateY(-100%);max-width:1100px}
#vision h1{font-family:var(--sa);font-weight:200;font-size:var(--fs-display);line-height:.95;letter-spacing:.01em;text-transform:uppercase;margin:0;color:var(--rl)}
.hero-sub{font-family:var(--sa);font-weight:500;font-size:clamp(13px,1.05vw,17px);letter-spacing:.12em;text-transform:uppercase;color:rgba(245,240,230,.9);margin:18px 0 0}
.hero-pie{position:absolute;z-index:4;left:var(--cpd);right:var(--cpd);top:calc(100svh - clamp(22px,4vh,40px));transform:translateY(-100%);display:flex;align-items:flex-end;justify-content:space-between;gap:24px}
/* Cifras: SOLO si deck_config_proyecto.kpis trae filas (nunca las de Palm Field). */
.cifras{display:grid;grid-template-columns:repeat(4,auto);gap:0;border-top:1px solid rgba(245,240,230,.28);padding-top:14px}
.cifra{display:flex;flex-direction:column;gap:4px;padding:0 clamp(14px,2.2vw,34px);border-left:1px solid rgba(245,240,230,.28)}
.cifra:first-child{padding-left:0;border-left:0}
.cifra b{font-family:var(--sa);font-weight:200;font-size:clamp(20px,1.6vw + 8px,34px);line-height:1;color:var(--rl);white-space:nowrap;letter-spacing:.01em}
.cifra span{font-family:var(--sa);font-weight:500;font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:var(--ss)}
.hero-cta{display:inline-flex;align-items:center;gap:12px;padding:14px 26px;border-radius:40px;white-space:nowrap;text-decoration:none;
  font-family:var(--sa);font-weight:500;font-size:14px;letter-spacing:.1em;text-transform:uppercase;color:var(--rl);
  border:1px solid rgba(190,179,165,.55);background:rgba(72,91,55,.35) url('/assets/img/TexturasBotones.webp') center/cover;
  backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);transition:background-color .3s,transform .2s}
.hero-cta:hover{background-color:rgba(72,91,55,.6);transform:translateY(-1px)}
#hero-puntos{position:absolute;z-index:4;left:50%;transform:translateX(-50%);top:calc(100svh - 20px);display:flex;gap:6px}
#hero-puntos span{width:6px;height:6px;border-radius:6px;background:rgba(255,255,255,.5);transition:all .3s}
#hero-puntos span.on{width:16px;background:#fff}
@media(max-width:900px){
  .hero-pie{flex-direction:column;align-items:flex-start}
  .cifras{grid-template-columns:repeat(2,auto);row-gap:14px}
  .cifra:nth-child(3){padding-left:0;border-left:0}
  .hero-texto{top:calc(100svh - clamp(250px,36vh,300px))}
  #vision.sin-cifras .hero-texto{top:calc(100svh - clamp(110px,17vh,140px))}
}

/* ── 1b · PANEL DE LA HERO: documentos + FAQ. Movil: debajo de la foto, en flujo (leccion
   de la v2: un panel largo superpuesto en pantalla pequena es un callejon sin salida).
   Desde 1024px flota a la derecha sobre la foto, en cristal oscuro. ── */
#faq{position:relative;z-index:6;background:var(--ob);color:var(--rl);padding:40px var(--cpd) 48px}
#faq .kicker{color:var(--sc)}
#faq h2{font-family:var(--sa);font-weight:200;font-size:clamp(28px,1.4vw + 16px,40px);line-height:1.05;text-transform:uppercase;margin:12px 0 0;color:var(--rl)}
.dd-lema{font-family:var(--sa);font-size:14px;line-height:1.7;color:rgba(245,240,230,.75);margin:14px 0 0}
#faq h3{font-family:var(--sa);font-size:11px;font-weight:500;letter-spacing:.24em;text-transform:uppercase;color:var(--sc);margin:0 0 6px}
.dd-cab{padding-bottom:22px;border-bottom:1px solid rgba(245,240,230,.16)}
.dd-cuerpo{display:flex;flex-direction:column;gap:30px;padding-top:24px}
.dd-cols{display:flex;flex-direction:column;gap:30px}
@media(min-width:1280px){
  .dd-cols{flex-direction:row;align-items:flex-start;gap:28px}
  .dd-cols > div{flex:1 1 0;min-width:0}
}
@media(min-width:1024px){
  #vision{height:100svh;--pw:min(40%,560px)}
  #faq{position:absolute;top:clamp(78px,11vh,96px);right:var(--cpd);bottom:clamp(22px,4vh,40px);width:var(--pw);min-width:400px;
    padding:0;display:flex;flex-direction:column;overflow:hidden;border-radius:16px;
    background:rgba(12,14,10,.62);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px);
    border:1px solid rgba(190,179,165,.3);box-shadow:0 30px 70px -30px rgba(0,0,0,.7);box-sizing:border-box}
  .dd-cab{padding:26px 28px 20px;flex:none}
  .dd-cuerpo{flex:1;min-height:0;overflow-y:auto;padding:20px 28px 26px;scrollbar-width:thin;scrollbar-color:rgba(245,240,230,.25) transparent}
  .hero-texto,.hero-pie{right:calc(var(--pw) + var(--cpd) + 40px)}
  #hero-next{right:calc(var(--pw) + var(--cpd) + 20px)}
  #hero-puntos{left:calc((100% - var(--pw) - var(--cpd)) / 2);top:auto;bottom:clamp(8px,1.6vh,14px);transform:translateX(-50%)}
  .hero-pie{flex-direction:column;align-items:flex-start;gap:22px;top:auto;transform:none;bottom:clamp(22px,4vh,40px)}
  .hero-texto{top:auto;transform:none;bottom:clamp(170px,26vh,230px)}
  #vision.sin-cifras .hero-texto{bottom:clamp(110px,16vh,140px)}
}
@media(min-width:1280px){ #vision{--pw:min(52%,760px)} }
/* Sin panel (ni documentos ni FAQ): el texto y las flechas recuperan el ancho entero */
@media(min-width:1024px){
  #vision.sin-panel .hero-texto,#vision.sin-panel .hero-pie{right:var(--cpd)}
  #vision.sin-panel #hero-next{right:clamp(14px,2.5vw,36px)}
  #vision.sin-panel #hero-puntos{left:50%}
}
@media(min-width:1024px) and (max-width:1640px){
  .cifras{grid-template-columns:repeat(2,auto);row-gap:14px} .cifra:nth-child(3){padding-left:0;border-left:0}
  #vision:not(.sin-cifras) .hero-texto{bottom:clamp(220px,32vh,280px)}
}
/* Documentos: filas con filete, como la v3 */
#docs-bloque{display:flex;flex-direction:column}
#docs-lista{display:grid;grid-template-columns:1fr;gap:0}
.doc{display:flex;flex-direction:column;gap:8px;padding:14px 0;border-top:1px solid rgba(245,240,230,.16)}
.doc:last-child{border-bottom:1px solid rgba(245,240,230,.16)}
.doc-cab{display:flex;align-items:flex-start;gap:10px}
.doc-cab .material-symbols-outlined{font-size:18px;color:var(--sc);flex:none}
.doc-txt{display:flex;flex-direction:column;min-width:0}
.doc-tit{font-size:14px;font-weight:500;letter-spacing:.04em;color:var(--rl);overflow-wrap:anywhere}
.doc-sub{font-size:10.5px;letter-spacing:.2em;text-transform:uppercase;color:var(--ss)}
.doc-des{font-size:12px;line-height:1.6;color:rgba(245,240,230,.7);margin-top:4px}
.doc-acc{display:flex;flex-wrap:wrap;gap:8px}
.doc-btn{display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border-radius:30px;text-decoration:none;
  font-size:10.5px;letter-spacing:.16em;text-transform:uppercase;color:var(--rl);border:1px solid rgba(245,240,230,.4);transition:background .25s}
.doc-btn:hover{background:rgba(245,240,230,.12)}
.doc-btn .material-symbols-outlined{font-size:15px}
/* FAQ: acordeon con + / − de la home */
#faq-lista{display:flex;flex-direction:column}
.faq-item{border-top:1px solid rgba(245,240,230,.18)}
.faq-item:last-child{border-bottom:1px solid rgba(245,240,230,.18)}
.faq-item summary{list-style:none;cursor:pointer;padding:15px 0;display:flex;align-items:center;justify-content:space-between;gap:16px;
  font-family:var(--sa);font-size:13px;font-weight:500;letter-spacing:.03em;text-transform:uppercase;color:var(--rl);line-height:1.4}
.faq-item summary::-webkit-details-marker{display:none}
.faq-item .mi{width:14px;height:14px;position:relative;flex:none}
.faq-item .mi::before,.faq-item .mi::after{content:"";position:absolute;left:0;right:0;top:50%;height:1px;background:rgba(245,240,230,.8)}
.faq-item .mi::after{transform:rotate(90deg);transition:transform .3s var(--ease)}
.faq-item[open] .mi::after{transform:rotate(0)}
.faq-item__body{padding:0 0 20px;font-family:var(--sa);font-size:14px;line-height:1.75;color:rgba(245,240,230,.72);max-width:64ch}
.dd-atajos{display:flex;flex-wrap:wrap;gap:8px;padding-top:4px}
.dd-atajos .btn{padding:10px 16px;font-size:10px}

/* ── 2 · MODELOS: "FOUR WAYS, ONE LEGACY" — tarjetas altas con marco interior ── */
.sec{position:relative;padding:clamp(4.5rem,11vh,8rem) 0}
.sec-lino{background:var(--rl) url('/assets/img/bg-ecosystem.webp?v=2') center/cover}
.sec-lino::before{content:"";position:absolute;inset:0;background:rgba(245,240,230,.72);pointer-events:none}
.sec > .wrap{position:relative}
/* Tope de 400px por tarjeta y centrado: con 1 o 2 modelos (Horizon S1 tiene uno) el 1fr
   de Palm Field estiraba la tarjeta a todo el ancho y a 3/4.4 salia de 1.700px de alto. */
#modelos-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,280px),400px));justify-content:center;gap:clamp(18px,2.2vw,32px);margin-top:clamp(2.5rem,5vh,3.5rem)}
.villa{position:relative;display:block;aspect-ratio:3/4.4;border-radius:14px;overflow:hidden;background:var(--va);color:var(--rl);text-decoration:none;
  box-shadow:0 30px 60px -30px rgba(20,26,17,.55);transition:transform .5s var(--ease)}
/* .villa pisa el `transition` de .reveal (misma especificidad, va despues): sin esta
   linea la tarjeta entraba de golpe, sin el fundido ni el desenfoque (code-review 24-sep). */
.villa.reveal{transition:transform .5s var(--ease),opacity .85s var(--ease),filter .85s var(--ease)}
a.villa:hover{transform:translateY(-6px)}
.villa [data-foto]{position:absolute;inset:0}
.villa [data-foto] img{width:100%;height:100%;object-fit:cover;transition:transform 1.2s var(--ease)}
a.villa:hover [data-foto] img{transform:scale(1.05)}
.villa::before{content:"";position:absolute;inset:0;z-index:1;pointer-events:none;
  background:linear-gradient(to top,rgba(14,17,12,.92) 0%,rgba(14,17,12,.55) 36%,rgba(14,17,12,0) 60%)}
.villa::after{content:"";position:absolute;inset:14px;z-index:2;border:1px solid rgba(245,240,230,.38);border-radius:8px;pointer-events:none}
.villa-cuerpo{position:absolute;z-index:3;left:28px;right:28px;bottom:28px;display:flex;flex-direction:column;align-items:center;text-align:center;gap:14px}
.villa-nombre{font-family:var(--sa);font-weight:500;font-size:clamp(24px,1.3vw + 12px,30px);letter-spacing:.06em;text-transform:uppercase;line-height:1}
.villa-precio{font-family:var(--sa);font-weight:500;font-size:11px;letter-spacing:.24em;text-transform:uppercase;color:var(--ss)}
.villa-precio b{color:var(--rl);font-weight:500;letter-spacing:.14em}
.villa-stats{display:grid;grid-template-columns:repeat(4,1fr);width:100%;border-top:1px solid rgba(245,240,230,.25);border-bottom:1px solid rgba(245,240,230,.25)}
.villa-stats div{display:flex;flex-direction:column;align-items:center;gap:3px;padding:10px 2px}
.villa-stats div + div{border-left:1px solid rgba(245,240,230,.18)}
.villa-stats b{font-family:var(--sa);font-weight:300;font-size:16px;white-space:nowrap}
.villa-stats span{font-family:var(--sa);font-size:8.5px;letter-spacing:.16em;text-transform:uppercase;color:rgba(245,240,230,.7)}
.villa-nota{font-family:var(--sa);font-size:11px;line-height:1.5;color:rgba(245,240,230,.78)}
.villa-btn{width:100%;box-sizing:border-box;display:flex;align-items:center;justify-content:center;gap:8px;padding:12px 18px;border-radius:40px;
  border:1px solid rgba(245,240,230,.55);font-family:var(--sa);font-size:11px;font-weight:500;letter-spacing:.18em;text-transform:uppercase;transition:background .3s,color .3s}
.villa-btn .material-symbols-outlined{font-size:15px}
a.villa:hover .villa-btn{background:var(--rl);color:var(--ci)}
.villa-sello{position:absolute;z-index:3;top:26px;left:50%;transform:translateX(-50%);font-family:var(--sa);font-size:10px;font-weight:500;letter-spacing:.22em;
  text-transform:uppercase;color:var(--rl);padding:6px 14px;border-radius:30px;background:rgba(72,91,55,.85);white-space:nowrap}
/* Sin foto del modelo: el dibujo honesto de /modelo/, nunca una foto de otro sitio */
.sin-render{width:100%;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:flex-start;padding-top:22%;box-sizing:border-box;gap:8px;background:#E4DFD5;color:rgba(16,76,79,.7)}
.sin-render svg{width:80px;height:auto}
.sin-render p{margin:0;font-size:12px;letter-spacing:.16em;text-transform:uppercase}

/* ── 3 · MASTERPLAN: plano + inventario en tarjetas oscuras con filete interior ── */
.leyenda{display:flex;gap:18px;flex-wrap:wrap;justify-content:center;margin-top:6px;font-family:var(--sa);font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--ci2)}
.leyenda i{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:8px;vertical-align:1px}
.mp-grid{display:grid;grid-template-columns:1fr;gap:clamp(20px,2.4vw,36px);margin-top:clamp(2rem,4.5vh,3rem);align-items:start}
@media(min-width:1024px){.mp-grid{grid-template-columns:7fr 5fr}}
/* Sin plano (decision 2): el inventario a ancho de lectura, centrado, no huerfano en 5/12 */
.mp-grid.sin-plano{grid-template-columns:1fr;max-width:860px;margin-inline:auto}
.marco,.inv{position:relative;background:var(--card);color:var(--rl);border-radius:16px;box-shadow:0 30px 60px -30px rgba(20,26,17,.6)}
.marco{padding:18px}
.marco::after{content:"";position:absolute;inset:8px;border:1px solid rgba(245,240,230,.16);border-radius:10px;pointer-events:none}
#plan-paginas{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 14px;position:relative;z-index:1}
.plan-pagina-btn{font-family:var(--sa);font-size:10.5px;font-weight:500;letter-spacing:.14em;text-transform:uppercase;padding:8px 14px;border-radius:30px;cursor:pointer;
  background:transparent;color:rgba(245,240,230,.8);border:1px solid rgba(190,179,165,.45);transition:all .25s}
.plan-pagina-btn:hover{border-color:var(--rl);color:var(--rl)}
.plan-pagina-btn.on{background:var(--tg);border-color:var(--tg);color:var(--rl)}
#plan-wrap{position:relative;width:100%;-webkit-user-select:none;user-select:none}
#plan-hotspots{position:absolute;inset:0}
#masterplan-img{width:100%;display:block;border-radius:8px;background:#1B1F18}
.mp-nota{font-family:var(--sa);font-size:12px;line-height:1.6;color:rgba(245,240,230,.65);margin:14px 6px 4px}
.hs{position:absolute;inset:0;cursor:pointer;transition:background .2s}
.hs-libre:hover{background:rgba(72,91,55,.35)}
.hs-ocupada{background:rgba(0,0,0,.45)} .hs-ocupada:hover{background:rgba(0,0,0,.3)}
.hs.lw-plano-activo{background:rgba(16,76,79,.55)}
.sello{position:absolute;pointer-events:none;transform:translate(-50%,-50%);color:#fff;font-family:var(--sa);font-weight:700;letter-spacing:.12em;
  font-size:9px;padding:2px 6px;border-radius:2px;box-shadow:0 1px 3px rgba(0,0,0,.3)}
@media(min-width:640px){.sello{font-size:10px}}
.sello-res{background:rgba(245,158,11,.9)} .sello-no{background:rgba(179,38,30,.95)}
.inv{overflow:hidden}
.inv-cab{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:20px 24px;border-bottom:1px solid rgba(245,240,230,.14)}
.inv-cab strong{font-family:var(--sa);font-weight:500;font-size:12px;letter-spacing:.22em;text-transform:uppercase;display:flex;align-items:center;gap:10px}
.inv-cab strong::before{content:"";width:7px;height:7px;border-radius:50%;background:#25D366;box-shadow:0 0 0 4px rgba(37,211,102,.18)}
#plots-count{font-family:var(--sa);font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:var(--ss);white-space:nowrap}
#plots-wrap{max-height:440px;overflow-y:auto;scroll-behavior:smooth;position:relative;scrollbar-width:thin;scrollbar-color:rgba(245,240,230,.25) transparent}
@media(min-width:1024px){#plots-wrap{max-height:680px}}
.inv-vacio{padding:24px;font-size:14px;line-height:1.7;color:rgba(245,240,230,.68)}
.fila{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px;padding:14px 18px 14px 22px;scroll-margin-top:96px;transition:background .2s}
.fila + .fila{border-top:1px solid rgba(245,240,230,.1)}
.fila:hover{background:rgba(245,240,230,.04)}
.fila-disp{box-shadow:inset 4px 0 0 #485B37}
.fila-res{box-shadow:inset 4px 0 0 #F59E0B;opacity:.8}
.fila-no{box-shadow:inset 4px 0 0 #B3261E;opacity:.75}
.fila-info{display:flex;flex-direction:column;gap:3px;min-width:0}
.fila-cab{display:flex;align-items:center;gap:10px}
.fila-cod{font-size:18px;font-weight:500;letter-spacing:.06em;color:var(--rl)}
.pill{padding:2px 9px;border-radius:30px;font-size:10.5px;font-weight:500;letter-spacing:.06em}
.pill-disp{background:rgba(143,155,122,.2);color:#C3D9A6}
.pill-res{background:rgba(245,158,11,.18);color:#F4C979}
.pill-no{background:rgba(179,38,30,.22);color:#EFA39B}
.fila-det{font-size:12.5px;line-height:1.5;color:rgba(245,240,230,.68)}
.fila-btn{display:inline-flex;align-items:center;padding:9px 16px;border-radius:30px;text-decoration:none;white-space:nowrap;
  font-size:10.5px;font-weight:500;letter-spacing:.14em;text-transform:uppercase;color:var(--rl);border:1px solid rgba(245,240,230,.55);transition:all .25s}
.fila-btn:hover{background:var(--rl);color:var(--ci)}
/* WhatsApp por parcela: mismo aspecto que la v3 (#plots-wrap a[href*="wa.me"] de palmfield) */
.fila-wa{gap:6px;border-color:rgba(37,211,102,.7);padding:9px 14px}
.fila-wa .material-symbols-outlined{font-size:16px;color:#25D366}
.fila-wa:hover{background:#25D366;color:#0b3d25}
.fila-wa:hover .material-symbols-outlined{color:#0b3d25}
.fila-guion{font-size:12px;color:rgba(245,240,230,.4);padding:6px 12px}
.lw-fila-activa{background:rgba(143,155,122,.2)!important}
.lw-destello{animation:lwDestello 2s ease-out}
@keyframes lwDestello{0%,30%{background:rgba(72,91,55,.32)}100%{background:rgba(143,155,122,.16)}}

/* ── 4 · FORECAST: "FROM LAND TO LEGACY" — sobre foto a sangre. La foto es la primera
   FOTO real del proyecto (nunca un render, nunca la de Palm Field); sin ella, obsidiana. ── */
.sec-foto{color:var(--rl);background:var(--ob) center/cover no-repeat}
.sec-foto::before{content:"";position:absolute;inset:0;pointer-events:none;
  background:linear-gradient(to bottom,rgba(10,12,9,.62),rgba(10,12,9,.78) 45%,rgba(14,20,11,.94))}
.sec-foto .kicker{color:var(--ss)}
.sec-foto .titulo{color:var(--rl)}
.sec-foto .entrada{color:rgba(245,240,230,.82)}
#forecast-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),380px));justify-content:center;gap:clamp(18px,2vw,28px);margin-top:clamp(2.5rem,6vh,4rem)}
.prev{position:relative;padding:14px 14px 18px;border-radius:16px;
  background:rgba(12,14,10,.78);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);
  border:1px solid rgba(190,179,165,.3);box-shadow:0 30px 60px -30px rgba(0,0,0,.7)}
.prev > :not(.prev-foto):not(.villa-sello){margin-left:10px;margin-right:10px}
.prev-foto{position:relative;height:170px;border-radius:10px;overflow:hidden;margin-bottom:22px;background:var(--va)}
.prev-foto img{width:100%;height:100%;object-fit:cover}
.prev-foto .sin-render{padding-top:0;justify-content:center}
.prev .kicker{font-size:10px;color:var(--ss)}
.prev h3{font-family:var(--sa);font-weight:500;font-size:clamp(20px,1vw + 12px,26px);letter-spacing:.08em;text-transform:uppercase;margin:10px 0 8px;color:var(--rl)}
.prev-base{font-family:var(--sa);font-size:13px;line-height:1.6;color:rgba(245,240,230,.85);margin:0 0 12px}
.prev-base b{color:var(--rl);font-weight:500}
.prev table{width:calc(100% - 20px);border-collapse:collapse;font-size:12.5px}
.prev th{font-size:10px;font-weight:500;letter-spacing:.2em;text-transform:uppercase;color:var(--ss);text-align:right;padding:10px 0 8px}
.prev th:first-child{text-align:left}
.prev td{padding:8px 0;border-top:1px solid rgba(245,240,230,.12);color:rgba(245,240,230,.82)}
.prev td + td{text-align:right;padding-left:10px}
.prev tr.neto td{font-weight:500;color:var(--rl);border-top:1px solid rgba(245,240,230,.4)}
.prev tr.roi td{font-weight:500;font-size:15px;color:#cfe0b8}
#forecast-nota{font-family:var(--sa);font-size:12px;line-height:1.7;color:rgba(245,240,230,.72);max-width:74ch;margin:clamp(2rem,4vh,3rem) auto 0;padding-top:18px;border-top:1px solid rgba(245,240,230,.2)}

/* ── 5 · GALERIA — fotos verticales con marco interior, como las tarjetas de la home ── */
.cab-fila{display:flex;align-items:flex-end;justify-content:space-between;gap:24px;flex-wrap:wrap}
#gallery{display:flex;gap:18px;overflow-x:auto;scroll-snap-type:x mandatory;scroll-behavior:smooth;padding-bottom:6px;scrollbar-width:none;margin-top:clamp(2rem,4.5vh,3rem)}
#gallery figure{margin:0;flex:none;width:82vw;scroll-snap-align:start;position:relative;border-radius:14px;overflow:hidden;background:var(--va)}
@media(min-width:640px){#gallery figure{width:46vw}}
@media(min-width:1024px){#gallery figure{width:31%}}
#gallery figure > div{aspect-ratio:4/5;overflow:hidden}
#gallery img{width:100%;height:100%;object-fit:cover;display:block;transition:transform .8s var(--ease)}
#gallery figure:hover img{transform:scale(1.04)}
#gallery figcaption{position:absolute;left:0;right:0;bottom:0;padding:40px 18px 16px;background:linear-gradient(to top,rgba(10,12,9,.8),rgba(10,12,9,0));
  color:var(--rl);font-family:var(--sa);font-size:11px;letter-spacing:.18em;text-transform:uppercase}
#gallery figure::after{content:"";position:absolute;inset:12px;border:1px solid rgba(245,240,230,.3);border-radius:8px;pointer-events:none}
.gal-flechas{display:flex;gap:10px}
.gal-flechas button{width:46px;height:46px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;
  border:1px solid rgba(46,52,55,.3);background:transparent;color:var(--ci);transition:all .3s}
.gal-flechas button:hover{background:var(--ci);color:var(--rl)}
.gal-flechas button:disabled{opacity:.3;pointer-events:none}
#galeria-vacia{margin-top:clamp(2rem,4.5vh,3rem);padding:40px 24px;border-radius:14px;border:1px dashed rgba(46,52,55,.3);text-align:center;
  font-size:12px;letter-spacing:.2em;text-transform:uppercase;color:var(--ci2)}

#fx-nota{padding:14px var(--cpd);background:var(--rl2)}
#fx-nota p{max-width:var(--cmx);margin:0 auto;font-family:var(--sa);font-size:12px;color:var(--ci2)}
/* Ubicación (24-sep-2026) */
.ubic-marco{margin-top:clamp(28px,4vw,48px);border-radius:14px;overflow:hidden;box-shadow:0 30px 60px -34px rgba(20,26,17,.5);background:#e9e4d8}
.ubic-marco iframe{display:block;width:100%;height:min(62vh,520px);border:0}
.ubic-pie{display:flex;justify-content:center;margin-top:28px}
</style>
<script src="/investor-deck/i18n.js?v=20260924u"></script>
</head>
<body>

<!-- Estado "deck no disponible": nace visible, el JS lo apaga si hay config. -->
<div id="deck-no-disponible">
  <div>
    <img src="/assets/img/lawang-logo-v3.webp" alt="Lawang">
    <p class="grande">This project does not have its Investor Deck available yet.</p>
    <p>Please contact our team for the latest documentation and availability.</p>
    <a class="btn btn-hueso" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>
  </div>
</div>

<div id="deck-contenido" hidden>

<!-- TOP BAR — calco de #topbar de lawangproperties.com: transparente sobre la foto y
     solida en lino al bajar. La clase .solid la pone el script del final. -->
<header id="topbar">
  <a id="logo" href="#vision" aria-label="Lawang Properties">
    <img class="lg-w" src="/assets/img/lawang-logo-v3.webp" alt="Lawang">
    <img class="lg-d" src="/assets/img/lawang-logo-v3-dark.webp" alt="" aria-hidden="true">
  </a>
  <!-- Sin "Legal Security": esa seccion se retiro del deck generico el 15-sep (ver el
       comentario de la seccion 5 mas abajo). Los enlaces a una seccion omitida se
       ocultan por JS (ocultaSeccion), aqui y en el menu movil. -->
  <nav id="nav-principal" aria-label="Sections">
    <a class="nav-link" href="#vision">Project &amp; Photos</a>
    <a class="nav-link" href="#modelos">Villa Models</a>
    <a class="nav-link" href="#masterplan">Masterplan &amp; Plots</a>
    <a class="nav-link" href="#rendimientos">Financial Forecast</a>
    <a class="nav-link" href="#faq">FAQ</a>
  </nav>
  <div id="acciones">
    <a id="cta-dosier" aria-label="Download dossier" hidden href="#" target="_blank" rel="noopener">
      <span class="material-symbols-outlined">download</span>
      <span>Download dossier</span>
    </a>
    <div id="deck-selectores" data-no-i18n></div>
    <button type="button" id="menu-btn" aria-label="Menu" aria-expanded="false" aria-controls="menu-movil">
      <span class="material-symbols-outlined" id="menu-ico">menu</span>
    </button>
  </div>
</header>
<nav id="menu-movil" hidden></nav>

<!-- WhatsApp flotante: el circulo verde de la home. El href con el nombre del proyecto
     lo pone el JS al resolver la config (y el mismo al boton del pie). -->
<a id="cta-whatsapp" href="https://wa.me/6281138319862" target="_blank" rel="noopener" aria-label="Questions? WhatsApp">
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.47 14.38c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.07-.3-.15-1.26-.46-2.4-1.48-.89-.79-1.49-1.77-1.66-2.07-.17-.3-.02-.46.13-.61.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.02-.52-.07-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51l-.57-.01c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.46 1.07 2.88 1.22 3.08.15.2 2.1 3.2 5.08 4.49.71.31 1.26.49 1.69.63.71.22 1.36.19 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.7.25-1.29.17-1.41-.07-.12-.27-.2-.57-.35zM12.04 21.5h-.01a9.5 9.5 0 0 1-4.84-1.33l-.35-.2-3.6.94.96-3.51-.23-.36a9.49 9.49 0 0 1-1.45-5.05c0-5.24 4.27-9.5 9.52-9.5a9.46 9.46 0 0 1 9.51 9.51c0 5.24-4.27 9.5-9.51 9.5zM20.52 3.49A11.78 11.78 0 0 0 12.04 0C5.46 0 .1 5.36.1 11.94c0 2.1.55 4.16 1.6 5.98L0 24l6.25-1.64a11.92 11.92 0 0 0 5.79 1.47h.01c6.58 0 11.94-5.36 11.94-11.94a11.86 11.86 0 0 0-3.47-8.4z"/></svg>
  <span class="sr">Questions? WhatsApp</span>
</a>

<main>

<!-- 1 · HERO — patron .hero-panel de la home: foto a sangre 100svh con velo desde abajo,
     titular abajo a la izquierda, cifras (solo si hay KPIs propios) y CTA en pildora
     texturada. Carrusel con las fotos DE PROYECTO de investor_deck_fotos. -->
<section id="vision" class="sin-cifras">
  <div id="hero-visual">
    <div id="hero-track" class="lw-carrusel"><!-- lo llena el JS --></div>
    <div class="hero-velo"></div>
    <button type="button" id="hero-prev" class="hero-flecha" aria-label="Previous photos"><span class="material-symbols-outlined">chevron_left</span></button>
    <button type="button" id="hero-next" class="hero-flecha" aria-label="More photos"><span class="material-symbols-outlined">chevron_right</span></button>
  </div>

  <div class="hero-texto">
    <h1 id="deck-titulo"></h1>
    <p class="hero-sub">by Lawang Properties</p>
  </div>

  <div class="hero-pie">
    <!-- KPIs: fila entera ausente si config.kpis es null/vacio (Diseño, revision
         previa -- nunca las cifras de Palm Field recicladas). -->
    <div class="cifras" id="kpis-grid" hidden></div>
    <a class="hero-cta" href="#masterplan"><span class="material-symbols-outlined" aria-hidden="true">south</span><span>Masterplan &amp; Plots</span></a>
  </div>

  <div id="hero-puntos"></div>

  <?php /* Panel de due diligence DENTRO de la hero, como la v3. La cabecera de Palm Field
       ("A land-plot development in the Balian river valley" + la linea de Hak Sewa) es
       de ESE proyecto: aqui va el titulo y la advertencia genericos ya aprobados de la v1. */ ?>
  <aside id="faq">
    <div class="dd-cab">
      <p class="kicker">Investor Deck · Due Diligence</p>
      <h2>Documentation &amp; FAQ</h2>
      <p class="dd-lema">Not a security or investment product. Real documentation, live plot inventory and a Year-1 forecast, for your own due diligence — the land tenure structure for this specific project is confirmed by your Lawang contact.</p>
    </div>
    <div class="dd-cuerpo">
      <div class="dd-cols">
        <div id="docs-bloque" hidden>
          <h3>Project documents</h3>
          <div id="docs-lista"><!-- lo llena el JS --></div>
        </div>
        <div id="faq-bloque">
          <h3>Frequently Asked Questions</h3>
          <div id="faq-lista"><!-- lo llena el JS --></div>
        </div>
      </div>
      <div class="dd-atajos">
        <a class="btn btn-hueso" href="#modelos">Villa Models</a>
        <a class="btn btn-hueso" href="#masterplan">Masterplan &amp; Plots</a>
        <a class="btn btn-hueso" href="#rendimientos">Financial Forecast</a>
      </div>
    </div>
  </aside>
</section>

<!-- 2 · MODELOS — patron "FOUR WAYS, ONE LEGACY": kicker centrado, titulo en mayusculas,
     tarjetas altas a foto completa con marco interior. Se omite entera si el proyecto
     no tiene modelos publicados (decision 3). -->
<section class="sec sec-lino" id="modelos">
<div class="wrap">
  <div class="cab center reveal">
    <p class="kicker">Catalog</p>
    <h2 class="titulo">Villa Typologies</h2>
    <p class="entrada">Prices below are <b>construction only</b> — land price depends on the plot chosen in the masterplan.</p>
  </div>
  <div id="modelos-grid"><!-- filled by JS --></div>
</div>
</section>

<?php /* 3 · MASTERPLAN — cabecera centrada, plano (solo si config.masterplan_activo, con
     pestañas si el manifiesto trae varias hojas) e inventario en vivo. El "Reservation
     Protocol" de la v3 (deposito de 3.000 €, 10 dias, Hak Sewa) son condiciones de Palm
     Field: no entra. */ ?>
<section class="sec sec-lino" id="masterplan">
<div class="wrap">
  <div class="cab center reveal">
    <p class="kicker">Masterplan &amp; Plots</p>
    <h2 class="titulo">Masterplan &amp; Plot Availability</h2>
    <p class="entrada" id="masterplan-nota"></p>
    <div class="leyenda">
      <span><i style="background:#485B37"></i>Available</span>
      <span><i style="background:#F59E0B"></i>Reserved</span>
      <span><i style="background:#B3261E"></i>Sold / Blocked</span>
    </div>
  </div>

  <div class="mp-grid sin-plano" id="mp-grid">
    <div class="marco" id="masterplan-imagen-bloque" hidden>
      <div id="plan-paginas" hidden></div>
      <div id="plan-wrap">
        <!-- Sin src en el HTML: un src="" pide la propia pagina como imagen. Lo pone el JS. -->
        <img id="masterplan-img" alt="Masterplan showing every plot code and surface area" loading="lazy">
        <div id="plan-hotspots"></div>
      </div>
      <p class="mp-nota"><span>Tap a plot to find it in the live inventory.</span> <span>Status is live; surface areas shown are project/design measurements, confirmed by survey at Plot Lock — not the registered legal area.</span></p>
    </div>

    <div class="inv">
      <div class="inv-cab">
        <strong>Live plot inventory</strong>
        <span id="plots-count">Loading…</span>
      </div>
      <div id="plots-wrap">
        <div class="inv-vacio">Loading live plot data…</div>
      </div>
    </div>
  </div>
</div>
</section>

<!-- 3b · UBICACIÓN (24-sep-2026, owner: «muéstrala en los investor-decks»). Sale de
     proyectos.ubicacion_maps por deck_ubicacion_publica() — misma puerta que el resto del
     deck. Oculta entera si el proyecto no la tiene: nunca un mapa aproximado. -->
<section class="sec sec-lino" id="ubicacion" hidden>
<div class="wrap">
  <div class="cab center">
    <p class="kicker">Location</p>
    <h2 class="titulo">Where the Project Is</h2>
  </div>
  <div class="ubic-marco" id="ubic-marco" hidden><iframe id="ubic-mapa" title="Project location on Google Maps" loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe></div>
  <p class="ubic-pie"><a class="btn btn-verde" id="ubic-abrir" target="_blank" rel="noopener" href="#"><span class="material-symbols-outlined" aria-hidden="true">location_on</span><span>Open in Google Maps</span></a></p>
</div>
</section>

<!-- 4 · FORECAST — patron "FROM LAND TO LEGACY": foto a sangre con velo, cabecera
     centrada y una tarjeta por modelo. Se omite entera si el proyecto no tiene
     forecast publicado (decision 3); un fallo de carga, en cambio, SI se avisa. -->
<section class="sec sec-foto" id="rendimientos">
<div class="wrap">
  <div class="cab center reveal">
    <p class="kicker">Investment</p>
    <h2 class="titulo" id="forecast-titulo">Year-1 Rental Forecast</h2>
    <p class="entrada">A first-year operating forecast under two scenarios (Average / Optimal occupancy). This is a forecast, not a guarantee — actual results depend on the rental operator, market conditions and property management agreement in force.</p>
  </div>
  <div id="forecast-grid"><!-- filled by JS --></div>
  <p id="forecast-nota">Figures shown are a Year-1 operating forecast provided by Lawang, not a guaranteed or historical return. ROI is calculated on the total investment (construction plus land) stated on each card; the land figure depends on the plot chosen. Management fee, maintenance and rental tax percentages are indicative and are confirmed in the rental-management agreement you sign; they may change.</p>
</div>
</section>

<?php /* 5 · SEGURIDAD JURÍDICA — retirada 15-sep-2026 (hallazgo Legal en la consulta de
     deploy capa 1) y sigue fuera en la v3: afirmaba Hak Sewa + escrow notarial como un
     HECHO fijo para cualquier proyecto que use esta plantilla. Esa es la estructura real
     de Palm Field (consulta legal 9-sep-2026), no algo que se pueda asumir por plantilla
     para el resto de la cartera. Mientras no exista un campo de tenencia por proyecto en
     deck_config_proyecto, esta seccion se omite entera. Palm Field mantiene la suya en
     investor-deck/palmfield/index.html, fuera de este sistema. */ ?>

<!-- 6 · SITE & DELIVERED VILLAS — galeria de fotos de proyecto con marco interior. -->
<section class="sec sec-lino" id="documentation">
<div class="wrap">
  <div class="cab-fila reveal">
    <div class="cab">
      <h2 class="titulo">Site &amp; Delivered Villas</h2>
      <p class="entrada">Plots, surrounding land and villa models already delivered on neighbouring phases.</p>
    </div>
    <div class="gal-flechas" id="gal-flechas">
      <button type="button" id="gal-prev" aria-label="Previous photos"><span class="material-symbols-outlined">chevron_left</span></button>
      <button type="button" id="gal-next" aria-label="More photos"><span class="material-symbols-outlined">chevron_right</span></button>
    </div>
  </div>
  <div id="gallery" class="lw-carrusel"><!-- filled by JS --></div>
  <!-- Estado vacio honesto: sin fotos de proyecto, nunca se cae a las de Palm Field. -->
  <div id="galeria-vacia" hidden>Photography in preparation</div>
</div>
</section>

</main>

<div id="fx-nota" style="display:none">
  <p id="fx-nota-txt"></p>
</div>

<!-- FOOTER compartido con /modelo y el deck de Palm Field (una sola fuente con sus tres
     idiomas: /assets/lawang-pie.js). Aqui solo va lo propio del deck: el aviso de que no
     es una oferta de valores (lo traduce el walker de i18n.js). -->
<footer data-lw-pie data-wa="https://wa.me/6281138319862">
  <span data-pie-nota>This page does not replace legal or financial advice. Nothing here is an offer to sell securities or a solicitation of investment.</span>
</footer>
<script src="/assets/lawang-pie.js?v=20260923153722"></script>

</div><!-- /#deck-contenido -->

<script>
(function(){
  'use strict';
  var SB_URL = 'https://vtulllundrfennhjddhc.supabase.co';
  // Publishable key (no el anon JWT legacy): mismo alcance publico, formato nuevo.
  var SB_KEY = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';
  // Saneado en PHP (preg_replace [^A-Za-z0-9-]) y de nuevo aqui: defensa en
  // profundidad, aunque el .htaccess ya restringe el patron de la URL.
  var SLUG = <?= json_encode($slug) ?>;
  if(!/^[a-z0-9-]+$/i.test(SLUG)) return;   // #deck-no-disponible ya esta visible

  var PROYECTO = null;   // se fija tras resolver deck_config_publico
  var WA_NUM = '6281138319862';
  var BUCKET = SB_URL + '/storage/v1/object/public/deck/';

  function $(id){ return document.getElementById(id); }
  function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
  // esc() sobre la moneda: viene de la base y el resultado acaba en innerHTML (Seguridad, capa 1).
  function fmtMoney(n, cur){ if(n==null) return '—'; return window.lwMoney ? lwMoney(n) : (esc(cur||'EUR') + ' ' + Number(n).toLocaleString('en-GB')); }
  function eur(v){ return '<span data-eur="'+Math.round(v)+'">'+(window.lwMoney?lwMoney(v):'€'+Math.round(v).toLocaleString('en-GB'))+'</span>'; }
  function num(v){ var n = Number(v); return isFinite(n) ? n : '—'; }
  // Texto multiidioma venido de la base: cada fila trae sus idiomas dentro, cae al ingles.
  function lwTxt(campo){
    if(!campo) return '';
    var lang = window.lwLang ? lwLang() : 'en';
    return String(campo[lang] || campo.en || '');
  }
  // Frase fija en ingles → idioma del visitante via el diccionario/patrones de i18n.js
  // (para textos que se arman en JS con un dato dentro, p.ej. el mensaje de WhatsApp).
  function traduceFrase(txt){
    var lang = window.lwLang ? lwLang() : 'en';
    return (lang !== 'en' && window.lwT) ? (lwT(txt, lang) || txt) : txt;
  }
  function traduce(el){ if(window.lwDeck && el) lwDeck.traduce(el); }
  // Un render o una imagen generada no puede pasar por fotografia: se declara a la vista.
  function etiquetaTipo(tipo){
    if(tipo === 'render') return ' · Render';
    if(tipo === 'ia')     return ' · AI-generated image';
    return '';
  }
  // El `url` lo teclea una persona en la intranet y esto es una pagina publica sin
  // login: un `javascript:` pegado ahi se ejecutaria al hacer clic. Solo http(s).
  // En el ambito del IIFE (en la v1 vivia dentro de pintaDocs y el boton de cabecera
  // la llamaba desde fuera: ReferenceError mudo, el dosier nunca se encendia).
  function urlSegura(u){
    if(!u) return '';
    try{ var p = new URL(String(u), location.href); return (p.protocol === 'http:' || p.protocol === 'https:') ? p.href : ''; }catch(_){ return ''; }
  }
  function aviso(queFallo){
    return '<div class="aviso">We could not load ' + queFallo + ' right now. Please contact ' +
      '<a class="enlace" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>.</div>';
  }
  // Seccion sin datos (decision 3): fuera ella y todo enlace que apunte a ella —
  // menu, menu movil y atajos del panel—, para que ninguno lleve a un hueco.
  function ocultaSeccion(id){
    var s = $(id); if(s) s.hidden = true;
    Array.prototype.forEach.call(document.querySelectorAll('a[href="#' + id + '"]'), function(a){ a.hidden = true; });
  }
  function rpc(fn, cuerpo){
    return fetch(SB_URL + '/rest/v1/rpc/' + fn, {
      method:'POST', headers:{'Content-Type':'application/json','apikey':SB_KEY,'Authorization':'Bearer '+SB_KEY},
      body: JSON.stringify(cuerpo)
    }).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); });
  }

  // ── carruseles (hero y galeria comparten mecanica: una funcion, no dos copias) ──
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
        for(var i = 0; i < puntos.children.length; i++) puntos.children[i].className = (i === n ? 'on' : '');
      }
    }
    prev.addEventListener('click', function(){ track.scrollBy({ left: -paso(), behavior: 'smooth' }); });
    next.addEventListener('click', function(){ track.scrollBy({ left:  paso(), behavior: 'smooth' }); });
    track.addEventListener('scroll', pinta);
    window.addEventListener('resize', pinta);
    pinta();
  }

  function pintaHero(fotos){
    var track = $('hero-track'), puntos = $('hero-puntos');
    if(!track) return;
    track.innerHTML = '';
    if(puntos) puntos.innerHTML = '';
    if(!fotos.length){
      // Estado vacio honesto: nunca una caja en blanco sin explicacion.
      var v = document.createElement('div'); v.className = 'hero-vacia'; v.textContent = 'Photography in preparation';
      track.appendChild(v);
      $('hero-prev').hidden = true; $('hero-next').hidden = true;
      traduce(track);
      return;
    }
    fotos.forEach(function(f, i){
      var fig = document.createElement('figure');
      var img = document.createElement('img');
      img.src = f.src; img.alt = f.pie;
      // Solo la primera es LCP; marcarlas todas es lo mismo que no marcar ninguna.
      if(i === 0) img.setAttribute('fetchpriority', 'high'); else img.loading = 'lazy';
      var cap = document.createElement('figcaption');
      cap.textContent = f.pie + etiquetaTipo(f.tipo);   // textContent: el pie lo teclea el equipo
      fig.appendChild(img); fig.appendChild(cap);
      track.appendChild(fig);
      if(puntos && fotos.length > 1){
        var d = document.createElement('span');
        if(i === 0) d.className = 'on';
        puntos.appendChild(d);
      }
    });
    montaFlechas(track, $('hero-prev'), $('hero-next'), puntos);
    traduce(track);
  }

  function pintaGaleria(fotos){
    var g = $('gallery'), vacia = $('galeria-vacia');
    if(!g) return;
    g.innerHTML = '';
    if(!fotos.length){ g.hidden = true; $('gal-flechas').hidden = true; vacia.hidden = false; traduce(vacia); return; }
    g.hidden = false; $('gal-flechas').hidden = false; vacia.hidden = true;
    fotos.forEach(function(f){
      var fig = document.createElement('figure');
      var marco = document.createElement('div');
      var img = document.createElement('img');
      img.src = f.src; img.alt = f.pie; img.loading = 'lazy';
      var cap = document.createElement('figcaption');
      cap.textContent = f.pie + etiquetaTipo(f.tipo);
      marco.appendChild(img); fig.appendChild(marco); fig.appendChild(cap);
      g.appendChild(fig);
    });
    montaFlechas(g, $('gal-prev'), $('gal-next'), null);
    traduce(g);
  }

  // Sin SEMILLA: un deck sin fotos propias muestra el estado vacio honesto,
  // nunca fotos de otro proyecto (Diseño, revision previa).
  function fotosVacias(){ pintaHero([]); pintaGaleria([]); }

  // Fondo del forecast: la primera FOTO real del proyecto. Nunca un render (iria sin su
  // etiqueta, debajo de un velo) ni una imagen de Palm Field; sin foto, obsidiana lisa.
  function fondoForecast(proyecto){
    var f = proyecto.filter(function(x){ return x.tipo === 'foto'; })[0];
    var sec = $('rendimientos');
    if(f && sec) sec.style.backgroundImage = 'url("' + String(f.src).replace(/["\\]/g, '\\$&') + '")';
  }

  // ── documentos del proyecto: salen de la intranet, o no sale nada ──────────
  var DOC_ICONO = { comercial:'description', legal:'gavel', tecnico:'architecture', precios:'payments', portada:'image', otros:'draft' };
  var DOC_ETIQUETA = { comercial:'Commercial', legal:'Legal', tecnico:'Technical', precios:'Plots & pricing', portada:'Image', otros:'Document' };
  // Drive: /file/d/<id>/view ABRE el visor; uc?export=download descarga. Si el enlace no
  // es de Drive no se inventa una ruta de descarga: la tarjeta se queda con "View".
  function enlaceDescarga(href){
    var m = /drive\.google\.com\/file\/d\/([^/?#]+)/.exec(href) || /drive\.google\.com\/open\?id=([^&#]+)/.exec(href);
    return m ? 'https://drive.google.com/uc?export=download&id=' + m[1] : '';
  }
  function accionDoc(href, icono, etiqueta){
    var a = document.createElement('a');
    a.href = href; a.target = '_blank'; a.rel = 'noopener'; a.className = 'doc-btn';
    var i = document.createElement('span'); i.className = 'material-symbols-outlined'; i.textContent = icono;
    var t = document.createElement('span'); t.textContent = etiqueta;
    a.appendChild(i); a.appendChild(t); return a;
  }
  function pintaDocs(docs){
    var bloque = $('docs-bloque'), cont = $('docs-lista');
    if(!bloque || !cont) return;
    cont.innerHTML = '';
    var pintados = 0;
    docs.forEach(function(d){
      var href = urlSegura(d.url);
      if(!href) return;
      // La tarjeta NO es un enlace: lleva dos acciones, y un <a> dentro de otro no es HTML valido.
      var card = document.createElement('div'); card.className = 'doc';
      var cab = document.createElement('div'); cab.className = 'doc-cab';
      var ico = document.createElement('span'); ico.className = 'material-symbols-outlined'; ico.textContent = DOC_ICONO[d.categoria] || DOC_ICONO.otros;
      var texto = document.createElement('div'); texto.className = 'doc-txt';
      var tit = document.createElement('span'); tit.className = 'doc-tit'; tit.setAttribute('data-no-i18n', ''); tit.textContent = d.titulo || '';
      var sub = document.createElement('span'); sub.className = 'doc-sub'; sub.textContent = DOC_ETIQUETA[d.categoria] || DOC_ETIQUETA.otros;
      texto.appendChild(tit); texto.appendChild(sub);
      if(d.descripcion){
        var des = document.createElement('span'); des.className = 'doc-des'; des.setAttribute('data-no-i18n', ''); des.textContent = d.descripcion;
        texto.appendChild(des);
      }
      cab.appendChild(ico); cab.appendChild(texto);
      var acciones = document.createElement('div'); acciones.className = 'doc-acc';
      acciones.appendChild(accionDoc(href, 'visibility', 'View'));
      var bajar = enlaceDescarga(href);
      if(bajar) acciones.appendChild(accionDoc(bajar, 'download', 'Download'));
      card.appendChild(cab); card.appendChild(acciones);
      cont.appendChild(card);
      pintados++;
    });
    if(!pintados) return;                       // nada publicable: el bloque sigue oculto
    bloque.hidden = false;
    traduce(bloque);
  }

  // ── tipologias de villa ──────────────────────────────────────────────────
  var SLUG_MODELO_OK = /^[a-z0-9-]+$/;
  var DESTACADO = null;   // config.modelo_destacado_slug
  var SIN_RENDER =
    '<div class="sin-render">' +
      '<svg viewBox="0 0 120 90" aria-hidden="true">' +
        '<path d="M10 48 L60 12 L110 48" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>' +
        '<rect x="24" y="48" width="72" height="34" fill="none" stroke="currentColor" stroke-width="2.5"/>' +
        '<path d="M48 82 V58 H72 V82" fill="none" stroke="currentColor" stroke-width="2.5"/></svg>' +
      '<p>Renders in progress</p></div>';

  // Foto del modelo: la primera de `deck_fotos` de ESE modelo, o el estado honesto. Sin
  // respaldo a /assets/img/buildings/ (retirada 24-sep-2026) ni a fotos de otro proyecto.
  function fotoModelo(slug, nombre, fotosModelo){
    if(!SLUG_MODELO_OK.test(slug)) return SIN_RENDER;
    var propia = (fotosModelo && fotosModelo.length) ? fotosModelo[0].src : null;
    if(!propia) return SIN_RENDER;
    return '<img src="' + esc(propia) + '" alt="' + esc(nombre) + ' villa model" loading="lazy" data-render>';
  }
  // Si la foto no carga, su caja ([data-foto]) cae sola al estado honesto. Una funcion
  // para las dos tarjetas que la usan (catalogo y forecast).
  function enganchaSinRender(card){
    var img = card.querySelector('[data-render]');
    if(!img) return;
    img.addEventListener('error', function(){
      var caja = card.querySelector('[data-foto]');
      if(!caja) return;
      caja.innerHTML = SIN_RENDER;
      traduce(caja);
    });
  }
  // `data-eur` solo si de verdad viene en EUR: etiquetar como EUR otra moneda seria
  // publicar una cifra falsa al convertir.
  function precioModelo(precio, moneda){
    if(precio == null) return '<b>Upon request</b>';
    var n = Number(precio);
    if(!isFinite(n)) return '<b>Upon request</b>';
    if((moneda || 'EUR') === 'EUR') return '<b class="lw-money" data-eur="' + n + '">' + (window.lwMoney ? lwMoney(n) : '€' + n.toLocaleString('en-GB')) + '</b>';
    return '<b>' + esc(moneda) + ' ' + n.toLocaleString('en-GB') + '</b>';
  }

  var mg = $('modelos-grid');
  function pintaModelos(rows, porModelo){
    mg.innerHTML = '';
    var STATS = [
      [function(m){ return num(m.villa_m2) + ' m²'; },       'Built'],
      [function(m){ return '+' + num(m.terraza_m2) + ' m²'; }, 'Terrace & pool'],
      [function(m){ return num(m.dormitorios); },            'Bedrooms'],
      [function(m){ return num(m.banos); },                  'Bathrooms']
    ];
    rows.forEach(function(m){
      var slug = String(m.slug == null ? '' : m.slug);
      var enlaza = SLUG_MODELO_OK.test(slug);
      var statsHtml = STATS.map(function(s){ return '<div><b>' + esc(s[0](m)) + '</b><span>' + s[1] + '</span></div>'; }).join('');
      // Enlaza a la ficha publica de la villa (/modelo/<slug>, en produccion). Los modelos
      // son del catalogo comun, no del proyecto: la ficha vale para cualquier deck.
      var card = document.createElement(enlaza ? 'a' : 'div');
      if(enlaza) card.href = '/modelo/' + slug;
      card.className = 'villa reveal';
      card.innerHTML =
        (DESTACADO && slug === DESTACADO ? '<span class="villa-sello">Most requested</span>' : '') +
        '<div data-foto>' + fotoModelo(slug, m.nombre, porModelo[slug]) + '</div>' +
        '<div class="villa-cuerpo">' +
          '<span class="villa-nombre">' + esc(m.nombre) + '</span>' +
          '<span class="villa-precio"><span>Construction from</span> ' + precioModelo(m.precio, m.moneda) + '</span>' +
          '<div class="villa-stats">' + statsHtml + '</div>' +
          '<span class="villa-nota">+ land price, per plot chosen below</span>' +
          (enlaza ? '<span class="villa-btn"><span>View model</span><span class="material-symbols-outlined">arrow_outward</span></span>' : '') +
        '</div>';
      enganchaSinRender(card);
      mg.appendChild(card);
    });
    traduce($('modelos'));
    if(window.lwRepintaDinero) lwRepintaDinero();
  }
  function modelosCaidos(){
    mg.innerHTML = aviso('the villa models');
    traduce(mg);
  }

  // ── prevision de alquiler, Año 1 ─────────────────────────────────────────
  // ⚠️ La aritmetica vive aqui y solo aqui (el RPC devuelve DATOS, no resultados), y es
  // la de la v1 sin tocar: cada escenario con SU ocupacion, ROI sobre inversion_base.
  function pintaForecast(filas, porModelo){
    var fg = $('forecast-grid');
    if(!fg) return;
    fg.innerHTML = '';
    var f0 = filas[0];
    var GASTOS = [
      ['Management fee', Number(f0.pct_gestion)],
      ['Maintenance',    Number(f0.pct_mantenimiento)],
      ['Rental tax',     Number(f0.pct_impuesto)]
    ];
    var retencion = GASTOS.reduce(function(a, g){ return a + g[1]; }, 0);
    var tit = $('forecast-titulo');
    if(tit){
      var nombres = filas.map(function(r){ return r.modelo_nombre; });
      var lista = nombres.length > 1 ? nombres.slice(0, -1).join(', ') + ' & ' + nombres[nombres.length - 1] : nombres[0];
      tit.textContent = 'Year-1 Rental Forecast — ' + lista;   // formato que ya traduce el PAT de i18n.js
    }
    filas.forEach(function(m){
      var adr = [Number(m.adr_medio), Number(m.adr_optimo)];
      var occ = [Number(m.ocupacion_media), Number(m.ocupacion_optima)];
      var base = Number(m.inversion_base);
      var bruto = [0,1].map(function(i){ return adr[i] * 365 * occ[i]; });
      var neto  = bruto.map(function(g){ return g * (1 - retencion); });
      var filasHtml = '';
      filasHtml += '<tr><td>ADR</td><td class="lw-money">'+eur(adr[0])+'</td><td class="lw-money">'+eur(adr[1])+'</td></tr>';
      filasHtml += '<tr><td>Occupancy</td><td class="lw-money">'+Math.round(occ[0]*100)+'%</td><td class="lw-money">'+Math.round(occ[1]*100)+'%</td></tr>';
      filasHtml += '<tr><td>Gross villa income</td><td class="lw-money">'+eur(bruto[0])+'</td><td class="lw-money">'+eur(bruto[1])+'</td></tr>';
      GASTOS.forEach(function(g){
        filasHtml += '<tr><td><span>'+esc(g[0])+'</span> ('+Math.round(g[1]*100)+'%)</td>' +
          '<td class="lw-money">'+eur(-bruto[0]*g[1])+'</td><td class="lw-money">'+eur(-bruto[1]*g[1])+'</td></tr>';
      });
      filasHtml += '<tr class="neto"><td>Net income</td><td class="lw-money">'+eur(neto[0])+'</td><td class="lw-money">'+eur(neto[1])+'</td></tr>';
      filasHtml += '<tr class="roi"><td>ROI</td><td class="lw-money">'+(neto[0]/base*100).toFixed(1)+'%</td><td class="lw-money">'+(neto[1]/base*100).toFixed(1)+'%</td></tr>';
      var dorm = m.dormitorios === 1 ? '1 bedroom' : (m.dormitorios || 0) + ' bedrooms';
      var slug = String(m.modelo_slug == null ? '' : m.modelo_slug);
      var card = document.createElement('div');
      card.className = 'prev reveal';
      // El nombre lo teclea una persona en la intranet: esc() SIEMPRE (XSS almacenado ya cazado aqui).
      card.innerHTML =
        '<div class="prev-foto" data-foto>' + fotoModelo(slug, m.modelo_nombre, porModelo[slug]) + '</div>' +
        (m.destacado ? '<span class="villa-sello" style="top:18px">Most requested</span>' : '') +
        '<p class="kicker">Market forecast</p>' +
        '<h3>' + esc(m.modelo_nombre) + ' · <span>' + esc(dorm) + '</span></h3>' +
        '<p class="prev-base"><span>Construction:</span> <b>' + eur(Number(m.precio_construccion)) + '</b><br>' +
          '<span>Total investment (ROI base):</span> ' + eur(base) + '</p>' +
        '<table><thead><tr><th></th><th>Average</th><th>Optimal</th></tr></thead><tbody>' + filasHtml + '</tbody></table>';
      enganchaSinRender(card);
      fg.appendChild(card);
    });
    traduce($('rendimientos'));
    if(window.lwRepintaDinero) lwRepintaDinero();
  }
  function forecastCaido(){
    var fg = $('forecast-grid');
    if(!fg) return;
    fg.innerHTML = aviso('the rental forecast');
    traduce(fg);
  }

  // ── FAQ: sale de deck_faq. textContent SIEMPRE (la escribe una persona en la intranet). ──
  function pintaFaq(filas){
    var cont = $('faq-lista');
    if(!cont) return;
    cont.innerHTML = '';
    filas.forEach(function(q, i){
      var d = document.createElement('details');
      d.className = 'faq-item';
      if(i === 0) d.open = true;
      var sum = document.createElement('summary');
      var txt = document.createElement('span'); txt.textContent = lwTxt(q.pregunta);
      var ico = document.createElement('span'); ico.className = 'mi'; ico.setAttribute('aria-hidden', 'true');
      sum.appendChild(txt); sum.appendChild(ico);
      var cuerpo = document.createElement('div'); cuerpo.className = 'faq-item__body'; cuerpo.textContent = lwTxt(q.respuesta);
      d.appendChild(sum); d.appendChild(cuerpo);
      cont.appendChild(d);
    });
  }
  function faqCaida(){
    var cont = $('faq-lista');
    if(!cont) return;
    cont.innerHTML = aviso('the questions');
    traduce(cont);
  }

  // ── masterplan interactivo (solo con config.masterplan_activo) ─────────────
  // ZONAS: poligonos reales en % por pagina del manifiesto — [[x1,y1],[x2,y2],...].
  var ZONAS = null;
  var ULTIMAS_FILAS = null;   // para repintar al cambiar de pagina sin refetch
  var PAGINAS_MP = [];
  // 'reservada' NO se marca SOLD: la leyenda y la lista la distinguen.
  var SELLO = {
    disponible:    null,
    reservada:     ['RESERVED', 'sello-res'],
    bloqueada:     ['SOLD',     'sello-no'],
    no_disponible: ['SOLD',     'sello-no'],
    vendida:       ['SOLD',     'sello-no'],
    cobrada:       ['SOLD',     'sello-no']
  };
  var ESTADO_PLANO = { disponible:'Available', reservada:'Reserved', bloqueada:'Sold', no_disponible:'Sold', vendida:'Sold', cobrada:'Sold' };
  var ESTADO_LISTA = { disponible:'Available', reservada:'Reserved', bloqueada:'Blocked', no_disponible:'Not available', vendida:'Sold', cobrada:'Sold' };

  function centroide(pts){
    var x=0,y=0; pts.forEach(function(p){ x+=p[0]; y+=p[1]; });
    return [x/pts.length, y/pts.length];
  }
  // El codigo lo teclea el equipo: para un id o un href se queda solo con [A-Za-z0-9-].
  function idParcela(codigo){ return String(codigo == null ? '' : codigo).replace(/[^A-Za-z0-9-]/g, ''); }

  // Toda parcela del plano es clicable y lleva a su fila del inventario (v3, owner
  // 22-sep): el contacto vive en la fila, un solo sitio donde se actua sobre una parcela.
  function pintaPlano(rows){
    var wrap = $('plan-hotspots');
    if(!wrap || !ZONAS) return;
    wrap.innerHTML = '';
    rows.forEach(function(row){
      var pts = ZONAS[row.codigo];
      if(!pts || pts.length < 3) return;   // sin poligono en esta pagina -> sigue en la lista
      var id = idParcela(row.codigo);
      var el = document.createElement('a');
      el.href = '#plot-' + id;
      el.setAttribute('data-plano', id);
      el.className = 'hs ' + (row.estado === 'disponible' ? 'hs-libre' : 'hs-ocupada');
      el.style.clipPath = 'polygon(' + pts.map(function(p){ return Number(p[0])+'% '+Number(p[1])+'%'; }).join(',') + ')';
      var precio = row.precio != null ? ' · ' + fmtMoney(row.precio, row.moneda) : '';
      el.title = row.codigo + ' · ' + row.superficie_m2 + ' m2 (project measurement)' + precio + ' · ' + (ESTADO_PLANO[row.estado] || row.estado);
      el.setAttribute('aria-label', el.title);
      el.addEventListener('click', function(e){ e.preventDefault(); irAParcela(row.codigo); });
      wrap.appendChild(el);
      var sello = SELLO[row.estado];
      if(sello){
        var c = centroide(pts);
        var badge = document.createElement('span');
        badge.className = 'sello ' + sello[1];
        badge.style.left = c[0]+'%'; badge.style.top = c[1]+'%';
        badge.textContent = sello[0];
        wrap.appendChild(badge);
      }
    });
  }

  // Clic en el plano → su fila: centrada DENTRO de la lista (que scrollea sola) y, si
  // queda fuera de pantalla (movil, lista debajo del plano), la pagina baja lo justo.
  // Ojo al verificar: `behavior:'smooth'` no anima en Edge headless.
  function irAParcela(codigo){
    var id = idParcela(codigo);
    var fila = $('plot-' + id);
    if(!fila) return;
    var lista = $('plots-wrap');
    if(lista && lista.scrollHeight > lista.clientHeight){
      lista.scrollTo({ top: fila.offsetTop - lista.clientHeight / 2 + fila.offsetHeight / 2, behavior: 'smooth' });
    }
    var r = fila.getBoundingClientRect();
    if(r.top < 80 || r.bottom > window.innerHeight) fila.scrollIntoView({ block: 'center', behavior: 'smooth' });
    Array.prototype.forEach.call(document.querySelectorAll('.lw-fila-activa'), function(f){ f.classList.remove('lw-fila-activa'); });
    Array.prototype.forEach.call(document.querySelectorAll('.lw-plano-activo'), function(p){ p.classList.remove('lw-plano-activo'); });
    fila.classList.add('lw-fila-activa');
    var poli = document.querySelector('[data-plano="' + id + '"]');
    if(poli) poli.classList.add('lw-plano-activo');
    fila.classList.remove('lw-destello'); void fila.offsetWidth; fila.classList.add('lw-destello');
  }

  // Cambia de pagina del masterplan (proyectos con varias hojas). Repinta con las mismas
  // filas ya cargadas, sin refetch.
  function pintaPaginaMasterplan(i){
    var pag = PAGINAS_MP[i];
    if(!pag) return;
    $('masterplan-img').src = pag.imagen;
    ZONAS = pag.zonas || null;
    $('plan-hotspots').innerHTML = '';
    Array.prototype.forEach.call(document.querySelectorAll('.plan-pagina-btn'), function(b, idx){
      b.classList.toggle('on', idx === i);
      b.setAttribute('aria-pressed', idx === i ? 'true' : 'false');
    });
    if(ULTIMAS_FILAS) pintaPlano(ULTIMAS_FILAS);
  }

  // WhatsApp por parcela (calco de enlaceWaParcela de palmfield/index.html), con el
  // proyecto dentro. Traducido con el mismo patron de i18n.js que el boton flotante.
  function enlaceWaParcela(codigo){
    var txt = traduceFrase('Hello LAWANG, I’m interested in plot ' + codigo + ' at ' + PROYECTO + '.');
    return 'https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(txt);
  }

  function pintaListaParcelas(rows){
    var plotsWrap = $('plots-wrap'), plotsCount = $('plots-count');
    ULTIMAS_FILAS = rows;
    if(!rows || !rows.length){
      plotsWrap.innerHTML = '<div class="inv-vacio">No plots published yet.</div>';
      plotsCount.textContent = '';
      traduce(plotsWrap);
      return;
    }
    if(ZONAS) pintaPlano(rows);
    var disponibles = rows.filter(function(r){ return r.estado === 'disponible'; }).length;
    plotsCount.textContent = disponibles + ' of ' + rows.length + ' plots available';
    plotsWrap.innerHTML = '';
    rows.forEach(function(row){
      var tono = row.estado === 'disponible' ? 'disp' : (row.estado === 'reservada' ? 'res' : 'no');
      var fila = document.createElement('div');
      fila.id = 'plot-' + idParcela(row.codigo);
      fila.className = 'fila fila-' + tono;
      // Sin reserva de autoservicio (decision 1, sigue en pie): la parcela libre lleva
      // WhatsApp con el proyecto y el codigo ya escritos, en el idioma del visitante
      // (v3, 24-sep; antes mailto "Contact us"); las demas, un guion.
      var accion = row.estado === 'disponible'
        ? '<a class="fila-btn fila-wa" target="_blank" rel="noopener" href="' + esc(enlaceWaParcela(row.codigo)) + '"' +
            ' aria-label="Talk to us on WhatsApp about plot ' + esc(row.codigo) + '">' +
            '<span class="material-symbols-outlined" aria-hidden="true">chat</span><span>Talk to us on WhatsApp</span></a>'
        : '<span class="fila-guion">—</span>';
      var precioM2 = (row.precio_suelo != null && row.superficie_m2) ? row.precio_suelo / row.superficie_m2 : null;
      var linea1 = precioM2 != null
        ? esc(row.superficie_m2) + ' m² · ' + fmtMoney(precioM2, row.moneda) + '/m² land'
        : esc(row.superficie_m2) + ' m²';
      // Sin precio de construccion no se escribe "Construction — = total": solo el suelo.
      var linea2 = row.precio_construccion != null
        ? 'Land ' + fmtMoney(row.precio_suelo, row.moneda) + ' + Construction ' + fmtMoney(row.precio_construccion, row.moneda) + ' = ' + fmtMoney(row.precio, row.moneda) + ' total'
        : (row.precio_suelo != null ? 'Land ' + fmtMoney(row.precio_suelo, row.moneda) : '');
      fila.innerHTML =
        '<div class="fila-info"><div class="fila-cab"><span class="fila-cod">' + esc(row.codigo) + '</span>' +
          '<span class="pill pill-' + tono + '">' + esc(ESTADO_LISTA[row.estado] || row.estado) + '</span></div>' +
          '<span class="fila-det">' + linea1 + '</span>' +
          (linea2 ? '<span class="fila-det">' + linea2 + '</span>' : '') + '</div>' +
        '<div>' + accion + '</div>';
      plotsWrap.appendChild(fila);
    });
    traduce($('masterplan'));
    if(window.lwRepintaDinero) lwRepintaDinero();
  }

  // ── menu por debajo de 1180px: clona los enlaces de #nav-principal ANTES de traducir,
  //    para que el walker de i18n traduzca las dos copias en la misma pasada. ──
  (function(){
    var nav = $('nav-principal'), menu = $('menu-movil'), btn = $('menu-btn'), ico = $('menu-ico');
    if(!nav || !menu || !btn) return;
    Array.prototype.forEach.call(nav.querySelectorAll('a'), function(a){
      var c = document.createElement('a');
      c.href = a.getAttribute('href');
      c.textContent = a.textContent;
      menu.appendChild(c);
    });
    function abre(si){
      menu.hidden = !si;
      btn.setAttribute('aria-expanded', si ? 'true' : 'false');
      if(ico) ico.textContent = si ? 'close' : 'menu';
    }
    btn.addEventListener('click', function(){ abre(menu.hidden); });
    menu.addEventListener('click', function(e){ if(e.target.closest('a')) abre(false); });
    document.addEventListener('keydown', function(e){ if(e.key === 'Escape') abre(false); });
    window.addEventListener('resize', function(){ if(window.innerWidth >= 1180) abre(false); });
  })();

  // ── seccion activa en el menu. #faq es el panel DENTRO de la hero: no cuenta. ──
  (function(){
    var secs = ['vision','modelos','masterplan','rendimientos','documentation'].map($).filter(Boolean);
    if(!secs.length || !('IntersectionObserver' in window)) return;
    function marca(id){
      Array.prototype.forEach.call(document.querySelectorAll('#nav-principal a, #menu-movil a'), function(a){
        a.classList.toggle('lw-nav-activa', a.getAttribute('href') === '#' + id);
      });
    }
    var io = new IntersectionObserver(function(es){
      es.forEach(function(e){ if(e.isIntersecting) marca(e.target.id); });
    }, { rootMargin: '-45% 0px -50% 0px' });
    secs.forEach(function(s){ io.observe(s); });
    marca('vision');
  })();

  // ── arranque: resolver la config del deck por slug, y solo entonces pedir el resto ──
  rpc('deck_config_publico', { p_slug: SLUG })
    .then(function(rows){
      if(!rows || !rows.length) throw new Error('sin_config');
      var cfg = rows[0];
      PROYECTO = cfg.proyecto;
      DESTACADO = cfg.modelo_destacado_slug || null;

      $('deck-no-disponible').hidden = true;
      $('deck-contenido').hidden = false;

      var titulo = lwTxt(cfg.titulo);
      document.title = titulo + ' | Lawang Properties';
      var metaDesc = document.querySelector('meta[name="description"]');
      if(metaDesc) metaDesc.setAttribute('content', lwTxt(cfg.meta_desc));
      // Titular de la hero: el titulo configurado sin su coletilla "- Investor('s) Deck"
      // (el kicker del panel ya lo dice, y a tamaño display repetido pesa). Solo se quita
      // ESA coletilla exacta; cualquier otro titulo sale tal cual.
      var h1 = $('deck-titulo');
      if(h1) h1.textContent = titulo.replace(/\s+[-–—]\s+investor[’']?s?\s+deck\s*$/i, '') || titulo;
      $('logo').setAttribute('aria-label', 'Lawang Properties — ' + PROYECTO);

      // WhatsApp: mensaje con el proyecto, en el idioma del visitante (patron de i18n.js),
      // al flotante y al boton del pie (lawang-pie.js marca el suyo con data-wa-enlace).
      var waHref = 'https://wa.me/' + WA_NUM + '?text=' + encodeURIComponent(
        traduceFrase('Hello LAWANG, I’m looking at the ' + PROYECTO + ' investor deck and I have a few questions.'));
      $('cta-whatsapp').href = waHref;
      Array.prototype.forEach.call(document.querySelectorAll('[data-wa-enlace]'), function(x){ x.href = waHref; });

      $('masterplan-nota').textContent = "Individually cadastred plots. Live inventory read directly from " + PROYECTO + "'s records — sizes, prices and status are informational and confirmed at Plot Lock.";

      // KPIs: solo si config.kpis trae filas reales (nunca placeholder).
      if(cfg.kpis && cfg.kpis.length){
        var kg = $('kpis-grid');
        kg.innerHTML = '';
        cfg.kpis.forEach(function(k){
          var box = document.createElement('div'); box.className = 'cifra';
          var b = document.createElement('b'); b.setAttribute('data-no-i18n', ''); b.textContent = lwTxt(k.valor);
          var s = document.createElement('span'); s.setAttribute('data-no-i18n', ''); s.textContent = lwTxt(k.label);
          box.appendChild(b); box.appendChild(s);
          kg.appendChild(box);
        });
        kg.hidden = false;
        $('vision').classList.remove('sin-cifras');
      }

      // Masterplan interactivo: solo si esta activo Y hay manifiesto
      // ({ paginas: [{imagen, etiqueta?, zonas}] }, medido a mano por proyecto en
      // investor-deck/masterplan/<slug>.json). Si el fetch falla, el deck sigue sin plano:
      // la lista (investor_deck_parcelas) no depende de esto.
      if(cfg.masterplan_activo && cfg.masterplan_imagen){
        fetch(cfg.masterplan_imagen).then(function(r){ return r.ok ? r.json() : Promise.reject(r.status); })
          .then(function(manifest){
            if(!manifest || !manifest.paginas || !manifest.paginas.length) throw new Error('manifiesto_vacio');
            PAGINAS_MP = manifest.paginas;
            $('masterplan-imagen-bloque').hidden = false;
            $('mp-grid').classList.remove('sin-plano');
            if(PAGINAS_MP.length > 1){
              var tabs = $('plan-paginas');
              tabs.innerHTML = '';
              PAGINAS_MP.forEach(function(pag, idx){
                var b = document.createElement('button');
                b.type = 'button';
                b.className = 'plan-pagina-btn';
                b.textContent = pag.etiqueta || ('Plan ' + (idx + 1));
                b.addEventListener('click', function(){ pintaPaginaMasterplan(idx); });
                tabs.appendChild(b);
              });
              tabs.hidden = false;
            }
            pintaPaginaMasterplan(0);
          })
          .catch(function(){ /* MUDO A PROPOSITO: sin manifiesto el deck queda exactamente
               como un proyecto con masterplan_activo=false (lista a ancho completo, sin
               plano), que es un estado valido y completo; el inventario en vivo, que es
               el dato, tiene su propio aviso si falla. */ ZONAS = null; });
      }

  /* Ubicación (24-sep-2026): mapa incrustado si hay coordenadas; con un enlace corto de
     Maps (no trae coordenadas y el navegador no puede seguirlo) solo el botón. Mismos
     patrones que el cajón de la intranet (mapaProyecto en intranet/v4/assets/datos.js). */
  function ubicMapa(t){
    t = (t || '').trim(); if(!t) return null;
    var m = t.match(/^(-?\d{1,2}(?:\.\d+)?)\s*[,;]\s*(-?\d{1,3}(?:\.\d+)?)$/);
    if(m) return { abrir: 'https://www.google.com/maps?q=' + m[1] + ',' + m[2], embed: 'https://maps.google.com/maps?q=' + m[1] + ',' + m[2] + '&z=14&output=embed' };
    if(!/^https:\/\/([a-z0-9-]+\.)*(google\.[a-z.]+|goo\.gl)\//i.test(t)) return null;
    var c = t.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/) || t.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/) ||
            t.match(/[?&](?:q|ll|query|center)=(-?\d+\.\d+)(?:,|%2C)\s*(-?\d+\.\d+)/i);
    return { abrir: t, embed: c ? 'https://maps.google.com/maps?q=' + c[1] + ',' + c[2] + '&z=14&output=embed' : null };
  }
  function pintaUbicacion(valor){
    var u = ubicMapa(typeof valor === 'string' ? valor : '');
    var sec = document.getElementById('ubicacion');
    if(!u || !sec) return;
    document.getElementById('ubic-abrir').href = u.abrir;
    if(u.embed){ document.getElementById('ubic-mapa').src = u.embed; document.getElementById('ubic-marco').hidden = false; }
    sec.hidden = false;
  }
      rpc('deck_ubicacion_publica', { p_proyecto: PROYECTO }).then(pintaUbicacion, function(){});

      // Resuelve siempre (nunca rechaza): modelos y forecast esperan este resultado
      // para saber la foto de cada villa, y un fallo aqui no puede tumbarlos.
      var fotosListo = rpc('investor_deck_fotos', { p_proyecto: PROYECTO })
        .then(function(rows){
          // El RPC mezcla fotos DEL PROYECTO (sin modelo_slug) y de CADA MODELO: la hero y
          // la galeria son del sitio; las de modelo van a su tarjeta.
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
          fondoForecast(proyecto);
          return porModelo;
        })
        .catch(function(){ fotosVacias(); return {}; });

      var docsListo = rpc('investor_deck_documentos', { p_proyecto: PROYECTO })
        .then(function(docs){
          if(!docs || !docs.length) return;          // sin nada publicado, ni boton ni bloque
          pintaDocs(docs);
          // "Download dossier" solo puede apuntar al dosier: se ata a la categoria.
          var d = docs.filter(function(x){ return x.categoria === 'comercial' && urlSegura(x.url); })[0];
          if(!d) return;
          var cta = $('cta-dosier');
          cta.href = urlSegura(d.url);
          if(d.titulo) cta.setAttribute('title', d.titulo);
          cta.hidden = false;
        })
        .catch(function(){ /* MUDO A PROPOSITO: el estado de reposo de las dos piezas ya es
             'oculto', asi que un fallo aqui deja lo mismo que 'este proyecto no tiene nada
             publicado'. No se promete ninguna descarga que luego falle. Lo que si tiene que
             verse (modelos, parcelas, forecast) tiene su propio aviso. */ });

      rpc('investor_deck_modelos', { p_proyecto: PROYECTO })
        .then(function(rows){
          if(!rows || !rows.length){ ocultaSeccion('modelos'); return; }   // sin dato: se omite
          return fotosListo.then(function(porModelo){ pintaModelos(rows, porModelo || {}); });
        })
        .catch(modelosCaidos);

      rpc('investor_deck_forecast', { p_proyecto: PROYECTO })
        .then(function(rows){
          if(!rows || !rows.length){ ocultaSeccion('rendimientos'); return; }   // sin dato: se omite
          return fotosListo.then(function(porModelo){ pintaForecast(rows, porModelo || {}); });
        })
        .catch(forecastCaido);

      var faqListo = rpc('investor_deck_faq', { p_proyecto: PROYECTO })
        .then(function(rows){
          if(!rows || !rows.length){
            // Sin preguntas publicadas: fuera el bloque y el enlace «FAQ» del menu (y su
            // clon del menu movil), que si no llevaria a un panel sin preguntas.
            $('faq-bloque').hidden = true;
            Array.prototype.forEach.call(document.querySelectorAll('#nav-principal a[href="#faq"], #menu-movil a[href="#faq"]'), function(a){ a.hidden = true; });
            return;
          }
          pintaFaq(rows);
        })
        .catch(faqCaida);   // un fallo SI se ve (aviso dentro del panel): no es lo mismo que "no hay"

      // Ni documentos ni FAQ: fuera el panel de cristal entero en vez de una caja vacia
      // (consulta de deploy capa 1, 24-sep). Las dos promesas resuelven siempre.
      Promise.all([docsListo, faqListo]).then(function(){
        if(!$('docs-bloque').hidden || !$('faq-bloque').hidden) return;
        ocultaSeccion('faq');
        $('vision').classList.add('sin-panel');
      });

      rpc('investor_deck_parcelas', { p_proyecto: PROYECTO })
        .then(pintaListaParcelas)
        .catch(function(){
          $('plots-wrap').innerHTML = '<div class="inv-vacio">We could not load live plot data right now. Please contact <a class="enlace" href="mailto:sales@lawangproperties.com">sales@lawangproperties.com</a>.</div>';
          $('plots-count').textContent = '';
          traduce($('plots-wrap'));
        });

      if(window.lwDeck){ lwDeck.montaSelectores('#deck-selectores'); lwDeck.traduce(document.body); }
      if(window.lwRepintaDinero) lwRepintaDinero();
    })
    .catch(function(){
      $('deck-contenido').hidden = true;
      $('deck-no-disponible').hidden = false;
      traduce($('deck-no-disponible'));
    });
})();
</script>
<script>
// v3: la barra es transparente sobre la hero y se vuelve solida al salir de ella, y los
// bloques .reveal entran con el mismo fundido que la home. Presentacion pura.
(function(){
  var bar = document.getElementById('topbar');
  function pinta(){ bar.classList.toggle('solid', window.scrollY > 60); }
  window.addEventListener('scroll', pinta, { passive: true });
  window.addEventListener('resize', pinta);
  pinta();
  // El menu movil se abre sobre la foto: con la barra transparente se leeria mal.
  var btn = document.getElementById('menu-btn');
  if(btn) btn.addEventListener('click', function(){ setTimeout(function(){
    if(btn.getAttribute('aria-expanded') === 'true') bar.classList.add('solid'); else pinta();
  }, 0); });
  if(!('IntersectionObserver' in window)){ document.querySelectorAll('.reveal').forEach(function(e){ e.classList.add('in'); }); return; }
  var io = new IntersectionObserver(function(es){
    es.forEach(function(e){ if(e.isIntersecting){ e.target.classList.add('in'); io.unobserve(e.target); } });
  }, { rootMargin: '0px 0px -8% 0px' });
  function observa(){ document.querySelectorAll('.reveal:not(.in)').forEach(function(e){ io.observe(e); }); }
  observa();
  // Las tarjetas las pinta el JS de datos mas tarde: se vuelven a observar al llegar.
  new MutationObserver(observa).observe(document.querySelector('main'), { childList: true, subtree: true });
})();
</script>
</body>
</html>
