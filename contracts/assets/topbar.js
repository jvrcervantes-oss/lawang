/* Comportamiento de los desplegables <details> de la suite (barra superior y
   barra de vista previa) — 28-jul-2026.

   <details> se abre solo, pero no se cierra ni al elegir una acción ni al
   pinchar fuera: sin esto se queda abierto tapando lo que hay debajo. Vive aquí
   y no copiado en cada app por lo mismo que topbar.css.

   Reglas:
   · solo un menú abierto a la vez,
   · elegir una acción (button/a de la lista) cierra,
   · un control que se usa varias veces seguidas (zoom) lleva data-keep y NO cierra,
   · clic fuera o Escape cierra todos.
   Un <select> o <label> dentro del menú tampoco cierra: hay que poder desplegarlo. */
(function () {
  var SEL = 'details.lw-menu, details.pv-menu';
  var LISTA = '.lw-menu-list, .pv-menu-list';

  function cerrarTodos(salvo) {
    document.querySelectorAll(SEL).forEach(function (d) { if (d !== salvo) d.open = false; });
  }

  document.addEventListener('click', function (e) {
    var menu = e.target.closest ? e.target.closest(SEL) : null;
    if (!menu) { cerrarTodos(null); return; }
    cerrarTodos(menu);
    var accion = e.target.closest(LISTA) && e.target.closest('button, a');
    if (accion && !accion.hasAttribute('data-keep')) menu.open = false;
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') cerrarTodos(null);
  });
})();
