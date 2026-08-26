/* ============================================================================
   COMPORTAMIENTO COMPARTIDO DE LA SUITE — cajón, densidad y orden de tabla
   31-jul-2026 · compañero de suite.css
   ----------------------------------------------------------------------------
   Tres piezas que TODAS las herramientas necesitan y que, copiadas, divergen:
   un cajón lateral que se cierra bien, una densidad que se recuerda y un orden
   de columnas que no miente con los números.

   Sin módulos, igual que entities.js y totales.js: las páginas son HTML plano.
   ========================================================================== */

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

/* ── CONFIRMAR EN SERIO — MUDADO ────────────────────────────────────────────
   Aqui vivia `suiConfirmar()`. Se retira el 15-ago-2026 porque la suite acabo
   con DOS dialogos: este y `lwConfirmar` (assets/dialogo.js), y facturas/ los
   usaba los dos a la vez -- dos aspectos distintos en la misma pantalla.

   Se conserva `lwConfirmar` y no este, por meritos y no por antiguedad:
     · admite HTML en el cuerpo (aqui solo texto plano), y varios avisos
       necesitan resaltar una cifra o un numero de contrato;
     · atrapa el foco mientras esta abierto (aqui se podia tabular a la pagina
       de detras sin verla);
     · tiene modo de UN boton para los mensajes que paran sin alternativa;
     · y sobre todo FUNCIONA EN contracts/app.html, que no carga suite.js --
       por eso aquella herramienta seguia con diez `confirm()` nativos.
   Lo que este si tenia bien y se conservo al migrar: el foco arranca en
   Cancelar, y Escape y el clic en el velo cuentan como «no».

   El CSS `.sui-conf*` se queda en suite.css: no lo usa nadie, pero quitarlo es
   tocar una hoja compartida por trece herramientas para no ganar nada visible.
   ---------------------------------------------------------------------------- */

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
/* ORDENAR UNA LISTA DE PARCELAS/UNIDADES POR SU CÓDIGO — 26-ago-2026.
   `.order('codigo')` de Postgres es orden de TEXTO: pone SH-10 y SH-100 antes
   que SH-2. En un inventario de 228 unidades eso significa bajar cien filas para
   encontrar la SH-2, y que dos parcelas contiguas en el plano no lo estén en la
   lista. El owner lo vio en Sumba Hills.
   La corrección ya existía escrita a mano en `parcela_inventario.js` (con su
   comentario explicando justo esto) y hacía falta en Obra y en Proyectos v3, que
   no la tenían: tres sitios, la misma regla. Aquí una vez.
   Se apoya en `suiComparar`, que ya sabe comparar con `numeric:true`. */
function suiOrdenarPorCodigo(filas, codigoDe){
  const cod = codigoDe || (x => x && x.codigo);
  return (filas || []).slice().sort((a, b) => suiComparar(cod(a), cod(b), 'asc'));
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
  module.exports = { suiComparar, suiOrdenar, suiOrdenarPorCodigo };
