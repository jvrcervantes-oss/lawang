/* Visor modal compartido de la suite interna de Lawang.
   Regla de la suite (29-jul-2026): cualquier documento que se CONSULTE desde
   una herramienta se abre en este pop-up, sin cambiar de ventana — nunca en
   pestaña nueva ni cargando la herramienta entera. Para documentos de Facturas,
   pasar la URL con `&vista=1` (modo solo-documento) como url y la URL sin
   `vista` como urlCompleta.

   Uso:  <script src="/contracts/assets/visor.js" defer></script>
         LW_VISOR.abrir(url, titulo, urlCompleta)
   - url:         lo que carga el iframe (documento, PDF, imagen, vista de app)
   - titulo:      texto de la cabecera del visor
   - urlCompleta: opcional — enlace «Abrir completo →» (edición/pestaña propia);
                  si se omite se usa url.
   Cierra con el botón, clic fuera o Escape; al cerrar el iframe vuelve a
   about:blank para descargar del todo lo embebido. */
(function(){
  'use strict';
  var listo = false;

  function asegurar(){
    if(listo) return; listo = true;
    var css = document.createElement('style');
    css.textContent =
      '.lwv-overlay{position:fixed;inset:0;background:rgba(46,52,55,.5);z-index:400;display:none;align-items:center;justify-content:center;padding:22px}' +
      '.lwv-overlay.open{display:flex}' +
      '.lwv-modal{background:#fffdf8;border-radius:14px;width:min(1080px,100%);height:min(88vh,100%);display:flex;flex-direction:column;overflow:hidden;box-shadow:0 24px 60px rgba(0,0,0,.28)}' +
      '.lwv-head{display:flex;align-items:center;gap:14px;padding:10px 16px;border-bottom:1px solid #e4ddcf;font-family:inherit}' +
      '.lwv-head b{font-size:13px;letter-spacing:.06em}' +
      '.lwv-abrir{font-size:12.5px;color:#104C4F;text-decoration:none;border-bottom:1px solid rgba(16,76,79,.3)}' +
      '.lwv-abrir:hover{border-bottom-color:#104C4F}' +
      '.lwv-close{margin-left:auto;font:inherit;font-size:12.5px;padding:6px 14px;border:1px solid #e4ddcf;border-radius:999px;background:none;cursor:pointer;color:inherit}' +
      '.lwv-close:hover{background:#efeade}' +
      '.lwv-frame{flex:1;border:none;width:100%;background:#fff}';
    document.head.appendChild(css);

    var ov = document.createElement('div');
    ov.className = 'lwv-overlay'; ov.id = 'lwvOverlay';
    // sin innerHTML con datos: todo lo variable se asigna por textContent/href
    var modal = document.createElement('div'); modal.className = 'lwv-modal';
    var head = document.createElement('div'); head.className = 'lwv-head';
    var tit = document.createElement('b'); tit.id = 'lwvTitle';
    var abrir = document.createElement('a'); abrir.id = 'lwvAbrir'; abrir.className = 'lwv-abrir';
    abrir.target = '_blank'; abrir.rel = 'noopener'; abrir.textContent = 'Abrir completo →';
    var cerrar = document.createElement('button'); cerrar.type = 'button';
    cerrar.className = 'lwv-close'; cerrar.textContent = 'Cerrar';
    var frame = document.createElement('iframe'); frame.id = 'lwvFrame';
    frame.className = 'lwv-frame'; frame.title = 'Documento';
    head.appendChild(tit); head.appendChild(abrir); head.appendChild(cerrar);
    modal.appendChild(head); modal.appendChild(frame);
    ov.appendChild(modal);
    document.body.appendChild(ov);

    cerrar.addEventListener('click', LW_VISOR.cerrar);
    ov.addEventListener('click', function(e){ if(e.target === ov) LW_VISOR.cerrar(); });
    document.addEventListener('keydown', function(e){
      if(e.key === 'Escape' && ov.classList.contains('open')) LW_VISOR.cerrar();
    });
  }

  window.LW_VISOR = {
    abrir: function(url, titulo, urlCompleta){
      asegurar();
      document.getElementById('lwvTitle').textContent = titulo || 'Documento';
      document.getElementById('lwvAbrir').href = urlCompleta || url;
      document.getElementById('lwvFrame').src = url;
      document.getElementById('lwvOverlay').classList.add('open');
    },
    cerrar: function(){
      var ov = document.getElementById('lwvOverlay'); if(!ov) return;
      ov.classList.remove('open');
      document.getElementById('lwvFrame').src = 'about:blank';
    }
  };
})();
