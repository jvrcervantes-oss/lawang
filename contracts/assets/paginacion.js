/* Paginación de listas — pieza compartida de la suite de Lawang. 26-ago-2026.

   POR QUÉ EXISTE
   --------------
   El owner ha tenido que pedir lo mismo tres veces («las listas son muy largas,
   necesitan paginación, no debo repetirte esto cada vez, no?»). No debería: una
   lista que sale de una consulta nace de una tabla que CRECE, así que la
   decisión ya está tomada el primer día. Cuando se escribió esto, Facturas iba
   por 165 filas y Operaciones por 95, y de las nueve herramientas solo
   Vencimientos paginaba.

   Y se saca aquí, no se copia ocho veces, por la razón de siempre en esta suite:
   un bloque escrito ocho veces son ocho reglas, y para el noveno mes tres se han
   separado. La implementación es la de `vencimientos/index.html` (18-ago) mudada
   a la capa común — no es una décima versión, es esa.

   LO QUE NO SE NEGOCIA
   --------------------
   · **El recorte se ANUNCIA siempre.** El pie dice «26–50 de 165», nunca solo
     las flechas. Una lista recortada en silencio es una lista en la que falta
     algo y nadie lo sabe: el mismo error que un estado vacío que puede
     significar «no hay nada» o «no he podido mirar».
   · **Al cambiar el filtro se vuelve a la página 1.** Sin esto te quedas en la
     página 4 de un resultado que ahora tiene una, la lista sale vacía y parece
     que el filtro no encuentra nada. Es el fallo clásico de todo paginador y por
     eso `pagina()` lo detecta solo, comparando el total con el anterior.
   · **Si cabe entero, el paginador no aparece.** Un control que no hace nada
     enseña que hay algo que hacer.

   USO
   ---
       <script src="/contracts/assets/paginacion.js"></script>

       const PAG = lwPaginador('#caja-tabla');   // el pie se cuelga ahí debajo
       ...
       function pintar(){
         const filas = visibles();               // ya filtradas y ordenadas
         cuerpo.innerHTML = PAG.pagina(filas).map(fila).join('');
       }
       PAG.alCambiar(pintar);                    // las flechas repintan

   `pagina()` devuelve el trozo que toca y deja el pie al día. No pinta nada más:
   cada herramienta sigue siendo dueña de sus filas.                           */

/* 25 por página: caben sin desplazar en un portátil y el pie queda a la vista sin
   scroll. El número vive AQUÍ y no en cada herramienta — que media suite pagine
   de 25 y la otra media de 40 es la misma divergencia con otro disfraz. */
const LW_POR_PAGINA = 25;

function lwPaginador(dondeCuelga, opciones){
  const o = opciones || {};
  const porPagina = o.porPagina || LW_POR_PAGINA;
  let pagina = 0, ultimoTotal = null, alCambiar = null;

  /* El marcado lo pone la pieza, no la página. Es el mismo motivo por el que la
     barra superior la inyecta `topbar.js`: si cada herramienta escribe su pie,
     en tres meses hay tres pies distintos. */
  const pie = document.createElement('div');
  pie.className = 'sui-pager';
  pie.hidden = true;
  pie.innerHTML =
    '<button type="button" class="sui-chip" data-pag="antes">← Anteriores</button>' +
    '<span class="n" aria-live="polite"></span>' +
    '<button type="button" class="sui-chip" data-pag="despues">Siguientes →</button>';

  const ancla = typeof dondeCuelga === 'string' ? document.querySelector(dondeCuelga) : dondeCuelga;
  /* Sin ancla NO se revienta: la herramienta se queda sin paginador y con su
     lista entera, que es exactamente como estaba antes. Una pieza de adorno no
     puede tumbar una pantalla que enseña dinero. */
  if (ancla && ancla.parentNode) ancla.parentNode.insertBefore(pie, ancla.nextSibling);

  const antes   = pie.querySelector('[data-pag="antes"]');
  const despues = pie.querySelector('[data-pag="despues"]');
  const info    = pie.querySelector('.n');

  function mueve(d){
    pagina += d;
    if (alCambiar) alCambiar();
    /* Al cambiar de página el ojo tiene que volver arriba de la lista, no
       quedarse donde estaba: si no, la página nueva empieza a media tabla y se
       lee como que no ha pasado nada. Solo si el ancla ya no se ve entera. */
    if (ancla && ancla.getBoundingClientRect().top < 0)
      ancla.scrollIntoView({ block:'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  }
  antes.addEventListener('click', () => { if (pagina > 0) mueve(-1); });
  despues.addEventListener('click', () => { mueve(1); });

  return {
    /* Recorta y deja el pie al día. Devuelve SIEMPRE un array. */
    pagina(filas){
      const todas = filas || [];
      /* Cambió el conjunto (otro filtro, otra búsqueda, llegaron datos): a la
         primera. Se detecta por el total y no se pide a la herramienta que se
         acuerde de llamar a `reinicia()`, porque acordarse es justo lo que
         falla. */
      if (ultimoTotal !== null && todas.length !== ultimoTotal) pagina = 0;
      ultimoTotal = todas.length;

      const ultima = Math.max(0, Math.ceil(todas.length / porPagina) - 1);
      if (pagina > ultima) pagina = ultima;

      const desde = pagina * porPagina;
      const trozo = todas.slice(desde, desde + porPagina);

      pie.hidden = todas.length <= porPagina;
      info.textContent = todas.length
        ? (desde + 1) + '–' + (desde + trozo.length) + ' de ' + todas.length
        : '';
      antes.disabled = pagina === 0;
      despues.disabled = desde + trozo.length >= todas.length;
      return trozo;
    },
    /* Para cuando la herramienta SÍ sabe que ha cambiado el conjunto sin que
       cambie el total (reordenar no, eso no mueve de página; cambiar de pestaña
       sí). */
    reinicia(){ pagina = 0; },
    alCambiar(fn){ alCambiar = fn; },
    get indice(){ return pagina; },
  };
}

/* Node lo necesita para el test; el navegador lo ignora. */
if (typeof module !== 'undefined' && module.exports)
  module.exports = { lwPaginador, LW_POR_PAGINA };
