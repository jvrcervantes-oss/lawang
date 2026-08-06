/* ============================================================================
   COMPORTAMIENTO COMPARTIDO DE LA SUITE — cajón, densidad y orden de tabla
   31-jul-2026 · compañero de suite.css
   ----------------------------------------------------------------------------
   Tres piezas que TODAS las herramientas necesitan y que, copiadas, divergen:
   un cajón lateral que se cierra bien, una densidad que se recuerda y un orden
   de columnas que no miente con los números.

   Sin módulos, igual que entities.js y totales.js: las páginas son HTML plano.
   ========================================================================== */

/* ── DENSIDAD ────────────────────────────────────────────────────────────
   Se guarda por navegador y se aplica ANTES de pintar, para que la tabla no
   nazca con un alto y salte al siguiente cuadro. */
const SUI_DENS = ['compacta', 'normal', 'amplia'];
function suiDensidad(valor){
  if(valor){ try{ localStorage.setItem('lawang_densidad', valor); }catch(_){} }
  let d = valor;
  if(!d){ try{ d = localStorage.getItem('lawang_densidad'); }catch(_){} }
  if(!SUI_DENS.includes(d)) d = 'normal';
  document.documentElement.setAttribute('data-densidad', d);
  document.querySelectorAll('[data-dens]').forEach(b => b.classList.toggle('on', b.dataset.dens === d));
  return d;
}
function suiMontarDensidad(caja){
  if(!caja) return;
  caja.innerHTML = SUI_DENS.map(d =>
    `<button type="button" data-dens="${d}" title="Densidad ${d}">${d[0].toUpperCase() + d.slice(1)}</button>`).join('');
  caja.addEventListener('click', e => {
    const b = e.target.closest('[data-dens]'); if(b) suiDensidad(b.dataset.dens);
  });
  suiDensidad();
}

/* ── CAJÓN LATERAL ───────────────────────────────────────────────────────
   No es modal a propósito (ver la cabecera de suite.css). Aun así cierra por
   Esc y por clic fuera, porque un panel que solo se cierra con su aspa se
   queda abierto: la gente prueba primero fuera.

   `onCerrar` avisa a la herramienta para que quite la fila marcada — si no, la
   tabla se queda con una selección de algo que ya no se está viendo. */
let _suiCajonCerrar = null;
function suiAbrirCajon({ titulo, sub, cuerpo, pie, onCerrar }){
  const velo  = document.getElementById('suiVelo');
  const cajon = document.getElementById('suiCajon');
  if(!velo || !cajon) return;
  cajon.innerHTML =
    `<div class="sui-cajon-cab">
       <div style="min-width:0">
         <h2>${titulo || ''}</h2>
         ${sub ? `<p class="sub">${sub}</p>` : ''}
       </div>
       <button type="button" class="sui-cajon-x" id="suiCajonX" aria-label="Cerrar" title="Cerrar (Esc)">✕</button>
     </div>
     <div class="sui-cajon-cuerpo">${cuerpo || ''}</div>
     ${pie ? `<div class="sui-cajon-pie">${pie}</div>` : ''}`;
  velo.classList.add('on');
  cajon.classList.add('on');
  // El empuje del contenido (adosado, 6-ago-2026) vive en el <html>: asi alcanza
  // a toda pagina con .sui-stage, tenga o no .sui-centro — que fue justo lo que
  // falló en el apartado del 31-jul.
  document.documentElement.classList.add('sui-cajon-on');
  cajon.setAttribute('aria-hidden', 'false');
  _suiCajonCerrar = onCerrar || null;
  document.getElementById('suiCajonX').onclick = suiCerrarCajon;
  // Foco al cajón: quien navega con teclado se quedaba en la tabla de detrás,
  // tabulando por filas que ya no son el tema.
  cajon.querySelector('.sui-cajon-cuerpo').setAttribute('tabindex', '-1');
  cajon.querySelector('.sui-cajon-cuerpo').focus({ preventScroll:true });
}
function suiCerrarCajon(){
  const velo  = document.getElementById('suiVelo');
  const cajon = document.getElementById('suiCajon');
  if(!cajon || !cajon.classList.contains('on')) return;
  velo?.classList.remove('on');
  cajon.classList.remove('on');
  document.documentElement.classList.remove('sui-cajon-on');
  cajon.setAttribute('aria-hidden', 'true');
  const f = _suiCajonCerrar; _suiCajonCerrar = null;
  if(f) f();
}
function suiCajonAbierto(){ return !!document.getElementById('suiCajon')?.classList.contains('on'); }

/* Inserta el armazón del cajón sin que cada página lo copie en su HTML. */
function suiMontarCajon(){
  if(document.getElementById('suiCajon')) return;
  const velo = document.createElement('div');
  velo.className = 'sui-velo'; velo.id = 'suiVelo';
  velo.addEventListener('click', suiCerrarCajon);
  const cajon = document.createElement('aside');
  cajon.className = 'sui-cajon'; cajon.id = 'suiCajon';
  cajon.setAttribute('role', 'complementary');
  cajon.setAttribute('aria-hidden', 'true');
  document.body.append(velo, cajon);
  document.addEventListener('keydown', e => { if(e.key === 'Escape') suiCerrarCajon(); });
}

/* ── CONFIRMAR EN SERIO (7a) ─────────────────────────────────────────────
   `suiConfirmar({titulo, mensaje, accion, tono}) -> Promise<boolean>`.
   Sustituye a window.confirm() en lo destructivo. El foco arranca en CANCELAR:
   un Enter distraido no puede borrar nada. Esc y clic en el velo son «no». */
function suiConfirmar({ titulo, mensaje, accion, tono } = {}){
  return new Promise(resolver => {
    const velo = document.createElement('div');
    velo.className = 'sui-conf-velo';
    velo.innerHTML =
      `<div class="sui-conf" role="alertdialog" aria-modal="true" aria-label="${(titulo||'Confirmar').replace(/"/g,'&quot;')}">
         <h3></h3><p></p>
         <div class="botones">
           <button type="button" class="sui-btn" data-no>Cancelar</button>
           <button type="button" class="sui-btn ${tono==='peligro' ? 'peligro-solido' : 'primario'}" data-si></button>
         </div>
       </div>`;
    velo.querySelector('h3').textContent = titulo || 'Confirmar';
    velo.querySelector('p').textContent = mensaje || '';
    velo.querySelector('[data-si]').textContent = accion || 'Confirmar';
    const cerrar = ok => { velo.remove(); document.removeEventListener('keydown', porTecla); resolver(ok); };
    const porTecla = e => { if(e.key === 'Escape'){ e.stopPropagation(); cerrar(false); } };
    velo.addEventListener('click', e => { if(e.target === velo) cerrar(false); });
    velo.querySelector('[data-no]').onclick = () => cerrar(false);
    velo.querySelector('[data-si]').onclick = () => cerrar(true);
    document.addEventListener('keydown', porTecla);
    document.body.appendChild(velo);
    velo.querySelector('[data-no]').focus();
  });
}

/* ── ORDEN DE COLUMNAS ───────────────────────────────────────────────────
   `orden` = {campo, dir}. El comparador distingue número de texto: ordenar
   importes como cadenas pone "9.000" por encima de "130.875", y ese es
   exactamente el error que hace desconfiar de una tabla.
   Los vacíos van SIEMPRE al final, suba o baje el orden: un hueco no es ni el
   más caro ni el más barato. */
function suiComparar(a, b, dir){
  const vacio = v => v === null || v === undefined || v === '';
  if(vacio(a) && vacio(b)) return 0;
  if(vacio(a)) return 1;
  if(vacio(b)) return -1;
  const na = typeof a === 'number' ? a : NaN, nb = typeof b === 'number' ? b : NaN;
  const cmp = (!isNaN(na) && !isNaN(nb))
    ? na - nb
    : String(a).localeCompare(String(b), 'es', { numeric:true, sensitivity:'base' });
  return dir === 'desc' ? -cmp : cmp;
}
/* Engancha las cabeceras marcadas con `data-orden="campo"`. `valorDe(fila,campo)`
   lo pone la herramienta: solo ella sabe si una columna es texto o dinero. */
function suiOrdenable(tabla, estado, valorDe, repintar){
  tabla.querySelectorAll('th[data-orden]').forEach(th => {
    if(!th.querySelector('.fl')) th.insertAdjacentHTML('beforeend', '<span class="fl">▲</span>');
    th.onclick = () => {
      const c = th.dataset.orden;
      estado.dir = (estado.campo === c && estado.dir === 'asc') ? 'desc' : 'asc';
      estado.campo = c;
      tabla.querySelectorAll('th[data-orden]').forEach(x => x.classList.remove('asc','desc'));
      th.classList.add(estado.dir);
      repintar();
    };
  });
}
function suiOrdenar(filas, estado, valorDe){
  if(!estado.campo) return filas;
  return filas.slice().sort((x, y) =>
    suiComparar(valorDe(x, estado.campo), valorDe(y, estado.campo), estado.dir));
}

if(typeof module !== 'undefined')
  module.exports = { suiComparar, suiOrdenar };
