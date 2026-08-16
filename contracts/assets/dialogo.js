/* Diálogo de confirmación de la suite — 15-ago-2026
   ----------------------------------------------------------------------------
   `lwConfirmar()` — la ÚNICA forma de parar al usuario en toda la suite.

   POR QUÉ EXISTE. Cada herramienta paraba a su manera: unas con un aviso que se
   va solo, otras con el `confirm()` del navegador, otras sin preguntar nada. Y
   `confirm()` no vale aquí por tres motivos, no por estética: bloquea el hilo,
   no se puede estilar, y en esta suite —que se opera desde la extensión de
   Chrome— un diálogo nativo CONGELA la extensión y deja de responder a todo.

   CUÁNDO SE USA:
     · la acción no se deshace (borrar un contrato, una factura, un documento);
     · se pierde trabajo (Nuevo / Limpiar con cambios sin guardar);
     · cambia una cifra de dinero que ya estaba escrita;
     · sale algo hacia un comprador real.
   Para confirmar que algo YA pasó («Guardado como RP00040») va `toast()`, que no
   interrumpe. La prueba: si el usuario puede perder trabajo o dinero por no
   haber leído, es diálogo — un aviso de 4,2 s no sirve para eso, porque cuando
   termina de leerlo ya ha pasado.

   POR QUÉ ES UN FICHERO APARTE y no va en suite-comun.js: `contracts/app.html`
   define su propio `esc()` (con un segundo parámetro que el compartido no tiene)
   y su propio `toast()`. Dos declaraciones del mismo nombre en el ámbito global
   revientan la página ENTERA con «Identifier has already been declared». Aquí no
   se declara nada global salvo `window.lwConfirmar`, así que lo carga cualquiera
   —incluida la herramienta más grande— sin chocar. Mismo criterio que
   vocabulario.js.

   SE AUTOINYECTA: no hay que pegar marcado en cada página. Una sola instancia
   reutilizada, creada la primera vez que se llama.

   USO:
     const ok = await lwConfirmar({
       titulo:    'Borrar la factura INV00012',
       cuerpo:    'Se borra el documento y su PDF. Esto no se puede deshacer.',
       confirmar: 'Borrar la factura',
       tono:      'peligro',      // opcional
     });
     if(!ok) return;

   REDACCIÓN, que es la mitad del trabajo:
     · el título nombra el objeto concreto — «Borrar la factura INV00012», no
       «¿Estás seguro?», que no dice qué se borra ni cuántos;
     · el botón dice LO QUE HACE, nunca «Aceptar» ni «Sí»: quien lee solo los
       botones tiene que poder elegir bien;
     · el cuerpo dice la consecuencia y si se puede deshacer.
*/
(function(){
  var fondo, caja, elT, elC, bOk, bNo, resolverActual = null, focoPrevio = null;

  function construir(){
    fondo = document.createElement('div');
    fondo.className = 'lw-dlg-fondo';
    fondo.setAttribute('role', 'presentation');
    fondo.innerHTML =
      '<div class="lw-dlg" role="alertdialog" aria-modal="true">' +
        '<div class="lw-dlg-cab"><div class="lw-dlg-marca"></div><h2></h2></div>' +
        '<div class="lw-dlg-cuerpo"></div>' +
        '<div class="lw-dlg-pie">' +
          '<button type="button" class="btn primary"></button>' +
          '<button type="button" class="btn"></button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(fondo);
    caja = fondo.querySelector('.lw-dlg');
    elT  = fondo.querySelector('.lw-dlg-cab h2');
    elC  = fondo.querySelector('.lw-dlg-cuerpo');
    bOk  = fondo.querySelector('.lw-dlg-pie .btn.primary');
    bNo  = fondo.querySelector('.lw-dlg-pie .btn:last-child');
    // ids únicos para que aria-labelledby funcione sin chocar con la página
    elT.id = 'lw-dlg-t'; elC.id = 'lw-dlg-c';
    caja.setAttribute('aria-labelledby', 'lw-dlg-t');
    caja.setAttribute('aria-describedby', 'lw-dlg-c');
    bOk.addEventListener('click', function(){ cerrar(true); });
    bNo.addEventListener('click', function(){ cerrar(false); });
    // solo el clic en el fondo, y en mousedown: con `click` bastaba con soltar
    // el ratón fuera tras arrastrar dentro del diálogo para cerrarlo sin querer.
    fondo.addEventListener('mousedown', function(e){ if(e.target === fondo) cerrar(false); });
  }

  function cerrar(v){
    if(!resolverActual) return;
    var f = resolverActual; resolverActual = null;
    fondo.classList.remove('abierto');
    document.removeEventListener('keydown', teclas, true);
    if(focoPrevio && focoPrevio.focus) { try{ focoPrevio.focus(); }catch(_){} }
    f(v);
  }

  function teclas(e){
    if(e.key === 'Escape'){ e.preventDefault(); cerrar(false); return; }
    if(e.key !== 'Tab') return;
    // El foco no se sale del diálogo: si se fuera, se estaría tabulando por la
    // página de detrás sin poder verla ni saber dónde se está.
    var f = [bOk, bNo].filter(function(b){ return b.style.display !== 'none'; });
    var i = f.indexOf(document.activeElement);
    e.preventDefault();
    f[(i + (e.shiftKey ? f.length - 1 : 1)) % f.length].focus();
  }

  window.lwConfirmar = function(o){
    o = o || {};
    return new Promise(function(res){
      if(!fondo) construir();
      cerrar(false);                     // si había uno abierto, se resuelve en falso
      focoPrevio = document.activeElement;
      elT.textContent   = o.titulo || '¿Seguimos?';
      elC.innerHTML     = o.cuerpo || '';
      elC.style.display = o.cuerpo ? '' : 'none';
      bOk.textContent   = o.confirmar || 'Continuar';
      // `cancelar: false` -> un solo boton. Para mensajes que PARAN y no ofrecen
      // alternativa: dos botones ahi son mentira, porque no hay nada que elegir.
      bNo.textContent   = o.cancelar === false ? '' : (o.cancelar || 'Cancelar');
      bNo.style.display = o.cancelar === false ? 'none' : '';
      var peligro = o.tono === 'peligro';
      caja.setAttribute('data-tono', peligro ? 'peligro' : 'normal');
      bOk.className = 'btn ' + (peligro ? 'peligro' : 'primary');
      resolverActual = res;
      fondo.classList.add('abierto');
      document.addEventListener('keydown', teclas, true);
      // El foco arranca en CANCELAR, no en el botón que actúa: un Enter de
      // inercia no puede borrar una factura.
      (o.cancelar === false ? bOk : bNo).focus();
    });
  };
})();

/* ═══ lwElegir / lwPicker — elegir de una lista larga — 16-ago-2026 ═══════════
   ----------------------------------------------------------------------------
   POR QUÉ EXISTE. En Compradores el prefijo del teléfono y la nacionalidad no
   eran desplegables: eran `<input list="…">` con un `<datalist>` detrás. Un
   `<input list>` se pinta EXACTAMENTE igual que un campo de texto — sin flecha,
   sin borde distinto, sin nada — así que no hay forma de saber que detrás hay
   182 prefijos y 195 países. El owner lo dijo tal cual: «aquí no queda claro que
   es desplegable».

   Y en móvil es peor que poco claro: el desplegable de un `<datalist>` no se
   puede estilar, se abre pegado a un campo de 132 px y en algunos navegadores no
   se abre en absoluto. Sobre 195 opciones, eso es un campo que no se puede
   rellenar sin saberse el dato de memoria.

   LA DECISIÓN: la lista se elige EN EL MODAL, y el buscador va DENTRO. No se
   pierde el escribir a máquina —que es como trabaja un agente con prisa— solo
   cambia de sitio: se abre con Enter y se teclea «esp» igual que antes. Lo que
   se gana es que el control se ve, se puede leer entero y funciona igual en el
   móvil que en el portátil.

   DÓNDE SÍ Y DÓNDE NO. Esto es para listas LARGAS que no caben en la cabeza.
   Un `<select>` de tres opciones ya se ve, ya se entiende y el nativo del móvil
   es mejor que cualquier cosa que montemos: ésos NO se tocan. La frontera está
   en `LW_ELEGIR_DESDE`.

   USO:
     const v = await lwElegir({ titulo:'Nacionalidad', opciones:NACIONALIDADES });
     lwPicker(document.querySelector('#f-nac'), NACIONALIDADES, {titulo:'Nacionalidad'});

   `opciones` admite cadenas sueltas o `{valor, texto, nota}`. */
var LW_ELEGIR_DESDE = 8;   // menos que esto se ve de una ojeada: no hace falta modal
(function(){
  var fondo, caja, elT, elQ, elL, resolver = null, focoPrevio = null, items = [], marcado = -1;

  /* Sin tildes y en minúsculas: quien busca «espana» o «Mexico» tiene que
     encontrar «España» y «México». Es el fallo clásico de un buscador de países
     en español, y aquí las dos listas son de países. */
  function llano(v){
    return String(v == null ? '' : v).toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }
  function normaliza(o){
    return (o || []).map(function(x){
      if (x && typeof x === 'object') return { valor:String(x.valor), texto:String(x.texto == null ? x.valor : x.texto), nota:x.nota || '' };
      return { valor:String(x), texto:String(x), nota:'' };
    });
  }

  function construir(){
    fondo = document.createElement('div');
    fondo.className = 'lw-dlg-fondo lw-elegir-fondo';
    fondo.innerHTML =
      '<div class="lw-dlg lw-elegir" role="dialog" aria-modal="true">' +
        '<div class="lw-dlg-cab"><div class="lw-dlg-marca"></div><h2></h2></div>' +
        '<input type="text" class="lw-elegir-q" autocomplete="off" spellcheck="false">' +
        '<div class="lw-elegir-lista" role="listbox"></div>' +
      '</div>';
    document.body.appendChild(fondo);
    caja = fondo.querySelector('.lw-elegir');
    elT  = fondo.querySelector('h2');
    elQ  = fondo.querySelector('.lw-elegir-q');
    elL  = fondo.querySelector('.lw-elegir-lista');
    elQ.addEventListener('input', function(){ pintar(); });
    elL.addEventListener('click', function(e){
      var b = e.target.closest('[data-v]'); if(b) cerrar(b.dataset.v);
    });
    fondo.addEventListener('mousedown', function(e){ if(e.target === fondo) cerrar(null); });
  }

  function visibles(){
    var q = llano(elQ.value);
    if(!q) return items;
    /* Lo que EMPIEZA por lo tecleado va primero. Buscando «+34» interesa España
       antes que cualquier país cuyo prefijo contenga un 34 por el medio. */
    var a = [], b = [];
    items.forEach(function(it){
      var t = llano(it.texto) + ' ' + llano(it.valor) + ' ' + llano(it.nota);
      if(t.indexOf(q) === 0 || llano(it.valor).indexOf(q) === 0) a.push(it);
      else if(t.indexOf(q) >= 0) b.push(it);
    });
    return a.concat(b);
  }

  function pintar(){
    var v = visibles();
    marcado = v.length ? 0 : -1;
    elL.innerHTML = v.length
      ? v.map(function(it, i){
          return '<button type="button" role="option" data-v="' + it.valor.replace(/"/g,'&quot;') + '"' +
                 ' class="lw-elegir-op' + (i === 0 ? ' marcado' : '') + '">' +
                 '<span>' + it.texto.replace(/</g,'&lt;') + '</span>' +
                 (it.nota ? '<em>' + it.nota.replace(/</g,'&lt;') + '</em>' : '') + '</button>';
        }).join('')
      : '<p class="lw-elegir-nada">Nada coincide con «' + elQ.value.replace(/</g,'&lt;') + '»</p>';
    elL.scrollTop = 0;
  }

  function mover(d){
    var ops = elL.querySelectorAll('.lw-elegir-op'); if(!ops.length) return;
    if(marcado >= 0 && ops[marcado]) ops[marcado].classList.remove('marcado');
    marcado = (marcado + d + ops.length) % ops.length;
    ops[marcado].classList.add('marcado');
    ops[marcado].scrollIntoView({ block:'nearest' });
  }

  function teclas(e){
    if(e.key === 'Escape'){ e.preventDefault(); cerrar(null); return; }
    if(e.key === 'ArrowDown'){ e.preventDefault(); mover(1); return; }
    if(e.key === 'ArrowUp'){ e.preventDefault(); mover(-1); return; }
    if(e.key === 'Enter'){
      e.preventDefault();
      var ops = elL.querySelectorAll('.lw-elegir-op');
      if(marcado >= 0 && ops[marcado]) cerrar(ops[marcado].dataset.v);
      return;
    }
    // Tab no sale: dentro solo hay el buscador y la lista, y la lista se recorre
    // con las flechas. Dejar tabular por 195 botones no es navegar, es perderse.
    if(e.key === 'Tab'){ e.preventDefault(); elQ.focus(); }
  }

  function cerrar(v){
    if(!resolver) return;
    var f = resolver; resolver = null;
    fondo.classList.remove('abierto');
    document.removeEventListener('keydown', teclas, true);
    if(focoPrevio && focoPrevio.focus){ try{ focoPrevio.focus(); }catch(_){} }
    f(v);
  }

  window.lwElegir = function(o){
    o = o || {};
    return new Promise(function(res){
      if(!fondo) construir();
      cerrar(null);
      focoPrevio = document.activeElement;
      items = normaliza(o.opciones);
      elT.textContent = o.titulo || 'Elige una opción';
      elQ.placeholder = o.buscarPh || 'Escribe para buscar…';
      elQ.value = '';
      pintar();
      resolver = res;
      fondo.classList.add('abierto');
      document.addEventListener('keydown', teclas, true);
      elQ.focus();
      /* Si ya había un valor, se marca el suyo y se le lleva la vista: al abrir
         un campo relleno lo primero que se quiere ver es qué pone ahora.

         ⚠️ VA DESPUÉS DE `.abierto`, no antes. Estaba antes y `scrollIntoView`
         no hacía nada: mientras el diálogo es `display:none` no tiene caja, y
         desplazar algo que no ocupa sitio no desplaza nada. Se veía marcado
         «Turquía» con la lista arriba del todo — `scrollTop` 0 de 7658 medidos
         en producción — o sea, el valor actual a 7.000 px de la vista. */
      if(o.valor){
        var ops = elL.querySelectorAll('.lw-elegir-op');
        for(var i = 0; i < ops.length; i++){
          if(ops[i].dataset.v === String(o.valor)){
            if(marcado >= 0 && ops[marcado]) ops[marcado].classList.remove('marcado');
            marcado = i; ops[i].classList.add('marcado');
            ops[i].scrollIntoView({ block:'center' });
            break;
          }
        }
      }
    });
  };

  /* Convierte un campo en disparador del selector. El campo QUEDA como estaba
     para todo lo demás —mismo `id`, mismo `name`, mismo sitio en el formulario—
     así que quien lo lea con `.value` no se entera de nada.

     Se le quita el `list=`: si no, el navegador enseñaría su propio desplegable
     ADEMÁS del modal, y son dos interfaces distintas para el mismo campo. */
  window.lwPicker = function(input, opciones, o){
    if(!input || input.dataset.lwPicker) return;
    o = o || {};
    input.dataset.lwPicker = '1';
    input.removeAttribute('list');
    input.readOnly = true;                 // `readonly` y no `disabled`: sigue enviándose y sigue siendo enfocable
    input.classList.add('lw-elegible');
    input.setAttribute('aria-haspopup', 'listbox');
    if(!input.getAttribute('title')) input.title = 'Pulsa para elegir';
    var abrir = function(e){
      if(e) e.preventDefault();
      if(input.disabled) return;
      lwElegir({ titulo:o.titulo || '', opciones:(typeof opciones === 'function' ? opciones() : opciones), valor:input.value })
        .then(function(v){
          if(v === null) return;
          input.value = v;
          // Los dos eventos, porque la suite escucha unas veces uno y otras el
          // otro. `bubbles` para que valga un listener puesto en el formulario.
          input.dispatchEvent(new Event('input',  { bubbles:true }));
          input.dispatchEvent(new Event('change', { bubbles:true }));
          if(o.despues) o.despues(v);
        });
    };
    input.addEventListener('mousedown', abrir);
    input.addEventListener('keydown', function(e){
      if(e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowDown') abrir(e);
    });
  };
})();
