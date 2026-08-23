/* ═══════════════════════════════════════════════════════════════════════════
   MOVIMIENTO v3 · capa de comportamiento de la suite — 23-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   EXPLORACIÓN, NO PRODUCCIÓN. Este fichero no lo carga nadie por defecto: lo
   inyecta `activar-v3.js` cuando la URL trae `?v3=1`. Con `?v3=0` se apaga.

   QUÉ ES. La suite entera —doce pantallas— comparte `suite.css`, `topbar.css`
   y `topbar.js`, y todo su movimiento son transiciones CSS de 120-260 ms. Una
   transición no se puede agarrar a mitad de vuelo, no hereda la velocidad de
   la mano y no sabe hacia dónde ibas. Esta capa las sustituye por muelles,
   enganchándose a las clases que las doce YA usan:

     .sui-btn .lw-btn .lw-home .sui-chip .sui-ficha .lw-kpi .lw-rail-i  → acuse al pulsar
     .sui-cajon .lw-panel .lw-rail                                      → cajón agarrable
     .lw-dlg                                                            → se materializa
     .lw-topbar                                                         → borde de scroll

   Por eso no hay una v3 por herramienta: hay UNA capa y once herramientas que
   la heredan sin que se les toque una línea (regla 0 de la suite).

   Fuente de las reglas: skill `apple-design` (WWDC «Designing Fluid
   Interfaces», «The Details of UI Typography», «Principles of Great Design»).
   Los § del texto apuntan a sus secciones.
   ═══════════════════════════════════════════════════════════════════════════ */
(function(){
'use strict';
if(window.LW3) return;                       // idempotente: dos <script> no duplican el motor

/* ─── EL INTERRUPTOR ─────────────────────────────────────────────────────────
   Sin `?v3=1` este fichero sale por aquí y no toca NADA: no añade la clase
   `v3` al <html>, así que `suite-v3.css` —que está entera bajo `html.v3`—
   tampoco pinta nada. Las once herramientas siguen exactamente como estaban.

     /facturas/?v3=1   enciende la v3 y la deja encendida en ESTA pestaña
     /facturas/?v3=0   la apaga
     /facturas/        hereda lo que hubiera en la pestaña

   Por qué `sessionStorage` y no reescribir los enlaces: la suite navega en
   estrella —del panel a una herramienta y vuelta— y esos enlaces no llevan el
   parámetro. Sin memoria de pestaña la v3 se caería al primer clic. Muere al
   cerrar la pestaña, que es lo que se quiere de una prueba.

   ⚠️ POR QUÉ ESTO NO ES UN `activar-v3.js` APARTE, que es como nació.
   Aquel cargaba el CSS y el motor inyectando <link>/<script> desde JS, con el
   sello de caché escrito a mano en una constante. `tools/sella_assets.py` solo
   reescribe el `?v=` que encuentra en HTML: un sello puesto a mano dentro de un
   .js no lo toca nadie, así que al cambiar el CSS el CDN de Hostinger habría
   seguido sirviendo el viejo hasta 7 días. Es el fallo de `consent.js` con el
   píxel de Meta, otra vez. Ahora las dos etiquetas están en el HTML de cada
   herramienta y las sella el hook, sin que nadie tenga que acordarse. */
/* EL PANEL v3 ES v3 SIEMPRE, sin parametro. Parece obvio y por no escribirlo se
   desplego roto el 23-ago-2026: `/intranet/v3/` cargaba este motor, que no veia
   ni `?v3=1` ni la llave de sesion —la pone el guion de la propia pagina, que
   corre DESPUES— y se apagaba solo. Resultado: el panel v3 se pintaba con la
   piel vieja y era indistinguible del que ya estaba en produccion. El owner lo
   dijo en una linea: «no veo ninguna diferencia».
   Lo decide la RUTA, que es un dato que existe antes que cualquier guion. */
var v3ON = /^\/intranet\/v3(\/|$)/.test(location.pathname);
try{
  var v3p=new URLSearchParams(location.search);
  if(v3p.has('v3')){ v3ON = v3p.get('v3')!=='0'; sessionStorage.setItem('lw3-on', v3ON?'1':'0'); }
  else if(v3ON) sessionStorage.setItem('lw3-on','1');   // y queda encendida al saltar a una herramienta
  else v3ON = sessionStorage.getItem('lw3-on')==='1';
}catch(_){ /* sessionStorage lanza en ventana privada: la v3 sigue, solo no se recuerda */ }
if(!v3ON) return;

/* El hub viejo y el v3 son dos ficheros distintos. Si la v3 está encendida, el
   «← Intranet» de la barra tiene que llevar al v3: si no, salir de una
   herramienta te devuelve a la pantalla vieja con la v3 aún puesta en la
   pestaña, y eso se lee como que el rediseño se ha caído. */
if(/^\/intranet\/(index\.html)?$/.test(location.pathname)){
  location.replace('/intranet/v3/');
  return;
}

const MENOS_MOV = matchMedia('(prefers-reduced-motion: reduce)');

/* ─── 1 · MUELLES ────────────────────────────────────────────────────────────
   Apple cambió el trío de física (masa/rigidez/amortiguación) por dos
   parámetros de diseñador y son los que se usan aquí:
     · amortiguación — 1.0 crítico, sin rebote; <1 rebota.
     · respuesta, en segundos — lo rápido que llega. NO es duración: un muelle
       no tiene duración, el asentamiento emerge de los parámetros.
   Con masa 1:  k = (2π/respuesta)²    c = 4π·amortiguación/respuesta          */
class Muelle{
  constructor(v=0,p={}){ this.v=v; this.obj=v; this.vel=0; this.quieto=true; this.params(p); }
  params({amort=1,resp=.4}={}){
    this.amort=amort; this.resp=resp;
    this.k=Math.pow(2*Math.PI/resp,2);
    this.c=4*Math.PI*amort/resp;
  }
  /* Retarget. `vel` entrega la velocidad del gesto (§5); si no se pasa se
     CONSERVA la que llevaba — eso es lo que evita el muro de ladrillo al
     invertir un gesto a mitad (§3: mezclar velocidad, no cortarla). */
  a(obj,o={}){
    if(o.amort!=null||o.resp!=null) this.params({amort:o.amort??this.amort, resp:o.resp??this.resp});
    this.obj=obj;
    if(o.vel!=null) this.vel=o.vel;
    this.quieto=false;
    /* §14 — con movimiento reducido lo que desaparece es el RECORRIDO. Un
       muelle marcado `suave` (opacidad, color) sigue corriendo: ayuda a
       entender qué cambió y no mueve nada por el campo visual. */
    if(MENOS_MOV.matches && !o.suave){ this.v=obj; this.vel=0; this.quieto=true; }
  }
  /* Durante un arrastre 1:1 el muelle no manda: manda la mano. Se le fija el
     valor presentado para que al soltar arranque exactamente de ahí. */
  fija(v,vel=0){ this.v=v; this.vel=vel; this.obj=v; this.quieto=true; }
  paso(dt){
    if(this.quieto) return false;
    const n=Math.max(1,Math.ceil(dt*240)), h=dt/n;   // subpasos: estable a 240 Hz
    for(let i=0;i<n;i++){
      const acc=-this.k*(this.v-this.obj)-this.c*this.vel;
      this.vel+=acc*h; this.v+=this.vel*h;
    }
    if(Math.abs(this.v-this.obj)<.02 && Math.abs(this.vel)<.05){ this.v=this.obj; this.vel=0; this.quieto=true; }
    return true;
  }
}

/* §11 — un solo rAF para todo (el CADisplayLink de la web), y se apaga solo
   cuando no queda nada vivo: un bucle eterno es batería tirada. */
const VIVOS=new Set(); let RAF=0, T0=0;
function tic(t){
  const dt=T0?Math.min(.034,(t-T0)/1000):1/60; T0=t;
  VIVOS.forEach(j=>{ try{ if(!j.paso(dt)) VIVOS.delete(j); }catch(e){ VIVOS.delete(j); console.warn('v3:',e); } });
  if(VIVOS.size) RAF=requestAnimationFrame(tic); else { RAF=0; T0=0; }
}
function mueve(j){ VIVOS.add(j); if(!RAF){ T0=0; RAF=requestAnimationFrame(tic); } }

/* Estado de transformación por elemento: x, y, escala, opacidad y desenfoque
   compuestos en UNA sola escritura (§11: solo transform y opacity). */
function fx(el){
  if(el.__fx3) return el.__fx3;
  const s={ x:new Muelle(0), y:new Muelle(0), s:new Muelle(1), o:null, b:null,
    pinta(){
      el.style.transform='translate3d('+s.x.v.toFixed(2)+'px,'+s.y.v.toFixed(2)+'px,0) scale('+s.s.v.toFixed(4)+')';
      if(s.o) el.style.opacity=s.o.v.toFixed(3);
      if(s.b) el.style.filter=s.b.v>.05?'blur('+s.b.v.toFixed(2)+'px)':'';
    },
    paso(dt){
      let algo=false;
      [s.x,s.y,s.s,s.o,s.b].forEach(m=>{ if(m&&m.paso(dt)) algo=true; });
      s.pinta();
      return algo;
    }
  };
  el.__fx3=s; return s;
}
const arranca=el=>mueve(fx(el));

/* §6 — proyección de momento: la función EXACTA del código de ejemplo de Apple
   (decaimiento exponencial), no la de v²/2a de los libros de texto. */
const proyecta=(v,d=.998)=>(v/1000)*d/(1-d);
/* §9 — goma: cuanto más pasas del borde, menos te sigue. Nunca un tope seco. */
const goma=(exceso,dim,c=.55)=>(exceso*dim*c)/(dim+c*Math.abs(exceso));
const masCerca=(x,p)=>p.reduce((a,b)=>Math.abs(b-x)<Math.abs(a-x)?b:a);

/* Historial corto: la velocidad al soltar sale de las últimas muestras, no del
   último evento suelto, que casi siempre llega con delta cero (§2). */
function rastro(){
  const h=[];
  return {
    push(v){ h.push({v,t:performance.now()}); if(h.length>6) h.shift(); },
    vel(){ if(h.length<2) return 0;
           const a=h[0], b=h[h.length-1], dt=(b.t-a.t)/1000;
           return dt>.004 ? (b.v-a.v)/dt : 0; },
    limpia(){ h.length=0; }
  };
}

/* ─── 2 · §13 · FEEDBACK MULTIMODAL ──────────────────────────────────────────
   Causalidad, armonía, utilidad. Armonía = el MISMO fotograma, por eso se
   llama justo donde se cambia el objetivo del muelle y nunca en un setTimeout.
   Utilidad = solo momentos con significado. El sonido nace APAGADO: dárselo a
   alguien sin que lo pida entrena a ignorar todo el feedback. */
let SONIDO=false;
try{ SONIDO = localStorage.getItem('lw3-sonido')==='1'; }catch(_){}
let AC=null;
function pitido(hz,ms,vol){
  if(!SONIDO) return;
  try{
    AC=AC||new (window.AudioContext||window.webkitAudioContext)();
    const o=AC.createOscillator(), g=AC.createGain();
    o.type='sine'; o.frequency.value=hz;
    g.gain.setValueAtTime(0,AC.currentTime);
    g.gain.linearRampToValueAtTime(vol,AC.currentTime+.006);
    g.gain.exponentialRampToValueAtTime(.0001,AC.currentTime+ms/1000);
    o.connect(g); g.connect(AC.destination); o.start(); o.stop(AC.currentTime+ms/1000+.02);
  }catch(e){}
}
function sensacion(tipo){
  const v=navigator.vibrate?navigator.vibrate.bind(navigator):null;
  if(tipo==='encaje'){      v&&v(8);          pitido(1180,40,.035); }
  else if(tipo==='hecho'){  v&&v([10,40,14]); pitido(760,70,.05); }
  else if(tipo==='error'){  v&&v([22,60,22]); pitido(200,120,.05); }
  else if(tipo==='roce'){   v&&v(4); }
}

/* ─── 3 · §1 §8 §10 · PULSABLES ──────────────────────────────────────────────
   «El momento en que aparece el retardo, la sensación de directo se cae por un
   precipicio.» Por eso el acuse va en el DOWN, no en el click.
   Y el detalle que casi nadie hace: se puede CANCELAR arrastrando fuera y
   volver a armar arrastrando dentro, con 10 px de holgura alrededor.

   Va por DELEGACIÓN en `document`, no elemento a elemento: las once
   herramientas repintan sus listas constantemente, y cualquier cosa que se
   enganche una vez al arrancar se queda sin efecto en cuanto se repinta. */
const PULSABLES = '.sui-btn, .lw-btn, .lw-home, .sui-chip, .sui-ficha, .lw-kpi,'
                + '.lw-rail-i, .lw-usuario-btn, .sui-cajon-x, .lw-panel-x, .lw-elegir-op,'
                + '.lw-menu-list a, [data-v3-pulsable]';
const ESCALA = el =>
    el.dataset && el.dataset.v3Escala ? +el.dataset.v3Escala
  : el.matches('.sui-ficha, .lw-kpi') ? .987      // superficie grande: encoge menos
  : el.matches('.lw-rail-i, .sui-cajon-x, .lw-panel-x') ? .9
  : .965;

{
  let act=null;   // { el, f, id, dentro, empuja }
  const cerca=(e,r,h)=>e.clientX>r.left-h&&e.clientX<r.right+h&&e.clientY>r.top-h&&e.clientY<r.bottom+h;
  const marca=(el,on)=>el.classList.toggle('v3-pulsada',on);

  document.addEventListener('pointerdown',e=>{
    if(e.button!==undefined&&e.button!==0) return;
    const el=e.target.closest&&e.target.closest(PULSABLES);
    if(!el||el.disabled) return;
    /* §8 — el empuje apunta a donde lleva el control: una fila con flecha
       empuja hacia la flecha; un botón normal no empuja, solo encoge. */
    const empuja = (el.dataset && el.dataset.v3Empuja) ? +el.dataset.v3Empuja
                 : el.matches('.lw-menu-list a, .lw-rail-i') ? 2 : 0;
    const f=fx(el);
    act={el,f,id:e.pointerId,dentro:true,empuja};
    if(MENOS_MOV.matches){ marca(el,true); return; }
    f.s.a(ESCALA(el),{amort:1,resp:.22});
    if(empuja) f.x.a(empuja,{amort:1,resp:.25});
    arranca(el);
  },{passive:true});

  document.addEventListener('pointermove',e=>{
    if(!act||e.pointerId!==act.id) return;
    const d=cerca(e,act.el.getBoundingClientRect(),10);
    if(d===act.dentro) return;
    act.dentro=d;
    if(MENOS_MOV.matches){ marca(act.el,d); return; }
    act.f.s.a(d?ESCALA(act.el):1,{amort:1,resp:.22});
    if(act.empuja) act.f.x.a(d?act.empuja:0,{amort:1,resp:.25});
    arranca(act.el);
  },{passive:true});

  const suelta=hecho=>{
    if(!act) return;
    const {el,f,dentro,empuja}=act; act=null;
    marca(el,false);
    if(MENOS_MOV.matches) return;
    /* Rebote leve SOLO al confirmar: el gesto llevaba intención. Al cancelar,
       vuelta crítica y sin gracia (§4: el rebote se gana, no se regala). */
    f.s.a(1,{amort:(hecho&&dentro)?.78:1, resp:.34});
    if(empuja) f.x.a(0,{amort:.8,resp:.3});
    arranca(el);
  };
  document.addEventListener('pointerup',()=>suelta(true),{passive:true});
  document.addEventListener('pointercancel',()=>suelta(false),{passive:true});
}

/* ─── 4 · §2 §3 §5 §6 §9 · CAJONES AGARRABLES ────────────────────────────────
   Las tres superficies deslizantes de la suite —el cajón de detalle
   (`.sui-cajon`), el panel de cuenta (`.lw-panel`) y el menú lateral
   (`.lw-rail`) en móvil— se abren hoy con `transition:transform 260ms`. Eso
   significa que no se pueden agarrar, que no saben con qué fuerza las
   empujaste y que cerrarlas exige apuntar a un aspa de 32 px.

   No se reescribe ninguna herramienta: se MIDE el estado cerrado que ya
   declara su CSS —`translateX(100%)` en escritorio, `translateY(101%)` en
   móvil— y a partir de ahí manda el muelle. Como el eje se deduce de la propia
   hoja de estilos, la misma línea sirve para el cajón que entra por la derecha
   y para el que sube desde abajo, sin preguntar por el ancho de pantalla. */

/* Mide lo que el CSS dice cuando está cerrado, sin que nuestro transform en
   línea contamine la lectura. */
function mideCerrado(el, claseAbierta){
  const enLinea=el.style.transform;
  const abierto=el.classList.contains(claseAbierta);
  el.style.transform='';
  if(abierto) el.classList.remove(claseAbierta);
  const t=getComputedStyle(el).transform;
  if(abierto) el.classList.add(claseAbierta);
  el.style.transform=enLinea;
  if(!t||t==='none') return null;                 // no es una hoja deslizante (el rail de escritorio)
  let m; try{ m=new DOMMatrixReadOnly(t); }catch(_){ return null; }
  const eje = Math.abs(m.f)>=Math.abs(m.e) ? 'y' : 'x';
  const cerrado = eje==='y' ? m.f : m.e;
  return Math.abs(cerrado)<4 ? null : { eje, cerrado };
}

function cajon(el, o={}){
  if(el.__cajon3) return el.__cajon3;
  const claseAbierta = o.clase || 'on';
  const velo = o.velo || null;
  const f=fx(el);
  let eje='y', cerrado=0, anclas=[0,0], abierto=false, medido=false;

  function mide(){
    const m=mideCerrado(el, claseAbierta);
    if(!m) return false;
    eje=m.eje; cerrado=m.cerrado;
    /* §6 — un cajón que ocupa casi toda la pantalla merece una parada
       intermedia: es la diferencia entre «cerrar» y «apartar para mirar
       detrás». Uno lateral estrecho no la necesita: solo abierto o cerrado. */
    const alto=el.offsetHeight||0;
    anclas = (eje==='y' && alto > innerHeight*.6) ? [0, Math.round(cerrado*.45), cerrado] : [0, cerrado];
    medido=true;
    return true;
  }

  const prog=()=>Math.max(0,Math.min(1, 1-Math.abs(f[eje].v)/Math.abs(cerrado||1)));
  function pintaVelo(){
    if(!velo) return;
    velo.style.opacity=(prog()).toFixed(3);
    velo.style.pointerEvents=prog()>.02?'auto':'none';
  }
  const trabajo={ paso(dt){
    const vivo=f.paso(dt);
    pintaVelo();
    if(!vivo && !abierto && Math.abs(f[eje].v-cerrado)<1){
      /* Cerrado del todo: se devuelve el mando al CSS. Si se dejara el
         transform en línea con un valor en píxeles, al girar el móvil (el
         cajón pasa de lateral a inferior) ese número ya no significaría nada. */
      el.style.transform=''; el.style.willChange='';
      if(velo){ velo.style.opacity=''; velo.style.pointerEvents=''; }
      medido=false;
    }
    return vivo;
  }};

  function abre(){
    if(!medido && !mide()) return;
    el.style.willChange='transform';
    if(!abierto) f[eje].fija(cerrado);
    /* PINTAR AQUÍ, no en el primer fotograma. Entre que la herramienta pone la
       clase `on` y que corre el primer rAF hay un fotograma en el que no existe
       transform en línea — y en ese hueco manda `.sui-cajon.on{transform:none}`,
       o sea el cajón ENTERO ya abierto. Se veía como un parpadeo al abrir, y
       solo aparece con la pestaña delante: con el rAF acelerado no se nota. */
    f.pinta(); pintaVelo();
    abierto=true;
    f[eje].a(0,{amort:.8,resp:.3});          // valores de Apple para cajón/hoja
    mueve(trabajo); sensacion('roce');
  }
  function cierra(vel){
    if(!medido) return;
    abierto=false;
    f[eje].a(cerrado,{vel:vel??null, amort:1, resp:.32});   // sin rebote al salir
    mueve(trabajo);
  }
  /* Cerrar de verdad = pulsar el aspa que la herramienta ya tiene, no quitarle
     la clase por detrás: la herramienta suele tener estado propio (qué ficha
     está abierta, si hay cambios sin guardar) y saltárselo lo desincroniza. */
  function cierraDeVerdad(){
    const x=el.querySelector(o.aspa||'.sui-cajon-x, .lw-panel-x, [data-cerrar]');
    if(x){ x.click(); return; }
    el.classList.remove(claseAbierta);
    if(velo) velo.classList.remove('on');
  }

  /* ── el gesto ─────────────────────────────────────────────────────────── */
  const r=rastro(); let id=null, p0=0, base=0, arrastrando=false;
  const coord=e=>eje==='y'?e.clientY:e.clientX;
  const haciaFuera=v=>cerrado>0 ? v>0 : v<0;      // el lado por el que se va

  function agarrar(e){
    if(!medido && !mide()) return;
    if(e.target.closest('input,textarea,select,button,a')) return;
    id=e.pointerId;
    try{ e.currentTarget.setPointerCapture(id); }catch(_){}
    p0=coord(e); base=f[eje].v;                  // §3: el valor EN PANTALLA, no el objetivo
    f[eje].fija(base); arrastrando=true;
    el.classList.add('v3-agarrando');
    r.limpia(); r.push(base);
  }
  function mover(e){
    if(id===null||!arrastrando) return;
    let v=base+(coord(e)-p0);
    /* §9 — pasado el tope de abierto, goma: resistencia creciente en vez de un
       muro. Un tope seco se lee como «se ha colgado». */
    if(!haciaFuera(v) && v!==0) v = -goma(-v, Math.abs(cerrado));
    f[eje].fija(v); f.pinta(); pintaVelo(); r.push(v);
  }
  function soltar(e){
    if(id===null) return;
    try{ e.currentTarget.releasePointerCapture(id); }catch(_){}
    id=null; arrastrando=false; el.classList.remove('v3-agarrando');
    const vel=r.vel();
    const destino=masCerca(f[eje].v+proyecta(vel), anclas);   // §6: adónde IBA, no dónde soltaste
    if(Math.abs(destino-cerrado)<1){
      abierto=false;
      f[eje].a(cerrado,{vel,amort:1,resp:.32}); mueve(trabajo);
      cierraDeVerdad();
      sensacion('hecho');
    }else{
      abierto=true;
      f[eje].a(destino,{vel,amort:.8,resp:.3});   // §5: la velocidad no se corta
      mueve(trabajo);
      if(Math.abs(destino-f[eje].v)>4) sensacion('encaje');
    }
  }
  function zonaAgarre(z){
    if(!z||z.__agarre3) return; z.__agarre3=true;
    z.style.touchAction='none';
    z.addEventListener('pointerdown',agarrar);
    z.addEventListener('pointermove',mover);
    z.addEventListener('pointerup',soltar);
    z.addEventListener('pointercancel',soltar);
  }

  /* La barra de agarre solo se pone cuando la hoja sube desde abajo: en un
     cajón lateral no significaría nada y §16.4 dice que un elemento que se
     parece a algo tiene que comportarse como ese algo. */
  function ponAgarre(){
    if(eje!=='y') return;
    let g=el.querySelector(':scope > .v3-agarre');
    if(!g){
      g=document.createElement('div');
      g.className='v3-agarre'; g.setAttribute('aria-hidden','true');
      el.insertBefore(g, el.firstChild);
    }
    zonaAgarre(g);
  }

  new MutationObserver(()=>{
    const on=el.classList.contains(claseAbierta);
    if(on===abierto) return;
    if(on){ if(mide()){ ponAgarre(); (o.agarres||'.sui-cajon-cab, .lw-panel-quien, .lw-rail-pie').split(',')
        .forEach(sel=>el.querySelectorAll(sel.trim()).forEach(zonaAgarre)); abre(); } }
    else cierra();
  }).observe(el,{attributes:true, attributeFilter:['class']});

  /* Tocar el velo cierra: §16 wayfinding — de una tarea modal siempre se sale,
     y por el mismo sitio por el que se entró. */
  if(velo && !velo.__velo3){
    velo.__velo3=true;
    velo.addEventListener('pointerdown',()=>{ if(abierto){ cierra(); cierraDeVerdad(); } });
  }
  addEventListener('resize',()=>{ if(!abierto) medido=false; else mide(); });

  const api={ abre, cierra, mide, get abierto(){ return abierto; } };
  el.__cajon3=api; return api;
}

/* ─── 5 · §12 · DIÁLOGOS QUE SE MATERIALIZAN ─────────────────────────────────
   `.lw-dlg-fondo` se enseña y se esconde con `display`, que no se puede
   animar. En vez de tocar el JS de cada herramienta se vigila el atributo y se
   anima alrededor: al entrar, desenfoque y escala JUNTOS —así llega como una
   superficie real y no como una opacidad—; al salir, el mismo camino invertido
   (§7), sosteniendo el `display` con una clase propia el tiempo justo. */
function materializa(fondo){
  if(fondo.__dlg3) return; fondo.__dlg3=true;
  const caja=fondo.querySelector('.lw-dlg')||fondo.firstElementChild;
  if(!caja) return;
  const ff=fx(fondo), fc=fx(caja);
  ff.o=new Muelle(0); fc.o=new Muelle(0); fc.b=new Muelle(14); fc.s.fija(.94);
  let visible=false;
  const seVe=()=>getComputedStyle(fondo).display!=='none';

  function entra(){
    visible=true; fondo.classList.remove('v3-saliendo');
    fc.s.fija(.94); fc.b.fija(14); fc.o.fija(0); ff.o.fija(0);
    ff.pinta(); fc.pinta();                   // mismo parpadeo que el cajón, misma cura
    ff.o.a(1,{amort:1,resp:.22,suave:true});
    fc.o.a(1,{amort:1,resp:.22,suave:true}); fc.b.a(0,{amort:1,resp:.34}); fc.s.a(1,{amort:.82,resp:.34});
    arranca(fondo); arranca(caja);
  }
  function sale(){
    visible=false;
    fondo.classList.add('v3-saliendo');        // el CSS sostiene el display mientras sale
    ff.o.a(0,{amort:1,resp:.18,suave:true});
    fc.o.a(0,{amort:1,resp:.18,suave:true}); fc.b.a(10,{amort:1,resp:.18}); fc.s.a(.95,{amort:1,resp:.18});
    arranca(fondo); arranca(caja);
    mueve({ paso(){ if(ff.o.quieto){ fondo.classList.remove('v3-saliendo'); return false; } return true; } });
  }
  new MutationObserver(()=>{
    const v=seVe()&&!fondo.classList.contains('v3-saliendo');
    if(v===visible) return;
    if(v) entra(); else sale();
  }).observe(fondo,{attributes:true, attributeFilter:['style','class']});

  /* `dialogo.js` CONSTRUYE el diálogo y lo abre en el mismo bloque síncrono, la
     primera vez que alguien confirma algo. Cuando este observador se engancha,
     ese primer diálogo ya está en pantalla — y un observador solo ve lo que pasa
     DESPUÉS. Sin esta línea, la primera confirmación de cada sesión aparecía de
     golpe y las siguientes se materializaban: el fallo que más desconcierta,
     porque no se puede repetir. */
  if(seVe()) entra();
}

/* ─── 6 · §12 · BORDE DE SCROLL ──────────────────────────────────────────────
   No es un `border-bottom` permanente: es un desenfoque que se funde
   exactamente cuando hay contenido pasando por debajo del cromo, y solo
   entonces. La barra deja de ser una franja opaca que se come 64 px. */
function bordeDeScroll(barra){
  if(barra.__borde3) return; barra.__borde3=true;
  const b=document.createElement('div');
  b.className='v3-borde'; b.setAttribute('aria-hidden','true');
  barra.insertAdjacentElement('afterend', b);
  let pedido=false;
  const pinta=()=>{ b.style.opacity=Math.min(1, (scrollY||document.documentElement.scrollTop)/44).toFixed(3); };
  addEventListener('scroll',()=>{
    if(pedido) return; pedido=true;
    requestAnimationFrame(()=>{ pedido=false; pinta(); });
  },{passive:true});
  pinta();
}

/* ─── 7 · §12 §7 · POPOVER ANCLADO ───────────────────────────────────────────
   `transform-origin` en la esquina del control que lo abrió: la relación entre
   el botón y lo que despliega tiene que ser evidente, no adivinarse. */
let POP=null;
function pop(ancla, opciones){
  if(!POP){
    POP=document.createElement('div');
    POP.className='v3-pop'; POP.setAttribute('role','menu');
    document.body.appendChild(POP);
    const f=fx(POP); f.o=new Muelle(0); f.b=new Muelle(10); f.s.fija(.9);
    addEventListener('pointerdown',e=>{ if(POP.classList.contains('viva')&&!e.target.closest('.v3-pop')) popCierra(); },true);
    addEventListener('keydown',e=>{ if(e.key==='Escape') popCierra(); });
  }
  const f=fx(POP);
  POP.innerHTML='';
  opciones.forEach(o=>{
    const b=document.createElement('button');
    b.type='button'; b.setAttribute('role','menuitem');
    if(o.icono) b.innerHTML='<i class="ph '+o.icono+'"></i>';
    b.appendChild(document.createTextNode(o.txt));
    b.onclick=()=>{ popCierra(); o.fn(); };
    POP.appendChild(b);
  });
  const r=ancla.getBoundingClientRect();
  POP.style.visibility='hidden'; POP.classList.add('viva');
  const w=POP.offsetWidth||190;
  POP.style.left=Math.max(10, Math.min(innerWidth-w-10, r.right-w))+'px';
  POP.style.top=(r.bottom+8)+'px';
  POP.style.transformOrigin='top right';
  POP.style.visibility='';
  f.s.fija(.9); f.b.fija(10); f.o.fija(0);
  f.s.a(1,{amort:.85,resp:.3}); f.b.a(0,{amort:1,resp:.3}); f.o.a(1,{amort:1,resp:.22,suave:true});
  arranca(POP);
}
function popCierra(){
  if(!POP||!POP.classList.contains('viva')) return;
  POP.classList.remove('viva');
  const f=fx(POP);
  f.s.a(.93,{amort:1,resp:.2}); f.b.a(8,{amort:1,resp:.2}); f.o.a(0,{amort:1,resp:.2,suave:true});
  arranca(POP);
}

/* ─── 8 · §16.2 · AVISOS CON DESHACER ────────────────────────────────────────
   Un diálogo de confirmación solo se gana con lo destructivo e irreversible;
   para todo lo demás se hace y se ofrece deshacer. La suite ya tiene `toast()`
   en suite-comun.js y esta capa NO lo sustituye: añade el que lleva acción,
   que es el que permite quitar la confirmación previa de en medio. */
function tosta(txt, o={}){
  let caja=document.querySelector('.v3-tostador');
  if(!caja){ caja=document.createElement('div'); caja.className='v3-tostador'; document.body.appendChild(caja); }
  const el=document.createElement('div');
  el.className='v3-tosta';
  el.innerHTML='<i class="ph '+(o.icono||'ph-check-circle')+'"></i><span></span>';
  el.querySelector('span').textContent=txt;
  if(o.accion){
    const b=document.createElement('button');
    b.type='button'; b.textContent=o.accion.txt;
    b.onclick=()=>{ o.accion.fn(); fuera(); };
    el.appendChild(b);
  }
  caja.appendChild(el);
  const f=fx(el); f.o=new Muelle(0); f.y.fija(16); f.s.fija(.96);
  f.o.a(1,{amort:1,resp:.3,suave:true}); f.y.a(0,{amort:.8,resp:.34}); f.s.a(1,{amort:.8,resp:.34});
  arranca(el);
  let ido=false;
  function fuera(){
    if(ido) return; ido=true;
    f.o.a(0,{amort:1,resp:.26,suave:true}); f.y.a(14,{amort:1,resp:.26}); arranca(el);   // §7: sale por donde entró
    mueve({ paso(){ if(f.o.quieto){ el.remove(); return false; } return true; } });
  }
  setTimeout(fuera, o.ms||4200);
  return el;
}

/* ─── 9 · ARRANQUE ───────────────────────────────────────────────────────────
   Se engancha a lo que hay AHORA y a lo que aparezca después: `topbar.js`
   monta el menú lateral y el panel de cuenta cuando le llega la ficha del
   usuario, o sea después de esto. Sin el observador, justo esas dos
   superficies —las únicas que están en las doce pantallas— se quedaban fuera. */
const VELO_DE={ 'sui-cajon':'.sui-velo', 'lw-panel':'.lw-velo', 'lw-rail':'.lw-rail-velo, .lw-velo' };

/* Toma una superficie concreta. Idempotente: `cajon()` y `materializa()` ya se
   guardan de engancharse dos veces. */
function toma(el){
  if(el.classList.contains('lw-dlg-fondo')){ materializa(el); return; }
  const clave=['sui-cajon','lw-panel','lw-rail'].find(c=>el.classList.contains(c));
  if(!clave || el.__cajon3) return;
  cajon(el,{ clase: clave==='lw-rail'?'abierto':'on',
             velo: document.querySelector(VELO_DE[clave]) });
}
const OJO='.sui-cajon, .lw-panel, .lw-rail, .lw-dlg-fondo';
function escanea(n){
  if(!n || n.nodeType!==1) return;
  if(n.matches && n.matches(OJO)) toma(n);
  if(n.querySelectorAll) n.querySelectorAll(OJO).forEach(toma);
}
function engancha(){
  escanea(document.body);
  const barra=document.querySelector('.lw-topbar');
  if(barra) bordeDeScroll(barra);
}
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',engancha);
else engancha();

/* ⚠️ AQUÍ HUBO UN DEBOUNCE POR requestAnimationFrame Y ERA UN FALLO.
   `topbar.js` monta el menú lateral y el panel de cuenta cuando le llega la
   ficha del usuario —o sea bastante después de esto—, así que hace falta
   vigilar. Lo que fallaba era el agrupador: ponía un cerrojo, pedía un rAF y lo
   soltaba dentro del fotograma. Con la pestaña en segundo plano el navegador NO
   da fotogramas, el cerrojo se quedaba echado y a partir de ahí no se enganchaba
   nada más — el menú y el panel se quedaban sin gesto sin decir una palabra.
   Se vio en Facturas con datos reales; en las pruebas nunca salió, porque ahí
   esas dos superficies las escribía yo a mano y ya estaban en el HTML.

   La cura no es un cerrojo mejor: es no necesitarlo. Se miran solo los nodos
   AÑADIDOS en vez de rebarrer el documento, así que da igual que el observador
   salte mil veces al repintar una tabla de 146 filas — cada salto cuesta lo que
   cuesta ese puñado de nodos, y se hace en el acto. */
new MutationObserver(ms=>{
  for(const m of ms) for(const n of m.addedNodes) escanea(n);
}).observe(document.documentElement,{childList:true,subtree:true});
document.documentElement.classList.add('v3');

window.LW3={ Muelle, fx, mueve, arranca, proyecta, goma, masCerca, rastro,
             sensacion, cajon, pop, popCierra, tosta, MENOS_MOV,
             get sonido(){ return SONIDO; },
             set sonido(v){ SONIDO=!!v; try{ localStorage.setItem('lw3-sonido',v?'1':'0'); }catch(_){} } };
})();
