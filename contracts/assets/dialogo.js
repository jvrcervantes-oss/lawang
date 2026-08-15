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
