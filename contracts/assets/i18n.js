/* ============================================================================
   i18n.js — la interfaz de la suite en inglés (11-sep-2026)
   ----------------------------------------------------------------------------
   POR QUÉ EXISTE
   El interruptor ES/EN se montó el 12-ago-2026 (`idioma.js` + el botón de
   `topbar.js`) porque hay agentes de habla inglesa, y el encargo de entonces
   decía «que se aplique a las nueve herramientas». Se aplicó a UNA:
   `intranet/Documentacion/`. Las demás cargaban el interruptor y seguían en
   español. Esto lo termina.

   POR QUÉ LA CLAVE ES EL PROPIO TEXTO EN ESPAÑOL, y no un nombre inventado
   (`btnGuardar`) como en el piloto de Documentación:

   1. **El español no puede romperse.** `lwT()` devuelve su entrada tal cual
      cuando el idioma es español. No hay un valor `es:` que pueda tener una
      errata, ni una clave que pueda quedarse huérfana e imprimir
      «btnGuardar» en pantalla. Con ~900 frases, el riesgo de estropear la
      vista española al traducir deja de existir por construcción — no por
      revisión.
   2. **Una frase, un sitio.** «Guardar cambios» sale en siete herramientas.
      Con claves propias serían siete entradas `{es,en}` que divergen; con el
      texto como clave es una. Es la regla que esta suite ya tiene escrita:
      una lista a mano en dos sitios ES el bug (`contexto/suite_lawang.md`).
   3. **Se lee.** `data-t` en el HTML no esconde el texto: el HTML sigue
      diciendo «Guardar cambios» y el atributo solo marca que hay que
      traducirlo.

   El piloto de `Documentacion/` sigue con su mecanismo propio a propósito:
   funciona y ya está en inglés. Migrarlo es limpieza opcional, no parte de
   esto — cambiar lo que ya sirve para que se parezca a lo nuevo es riesgo
   sin beneficio para nadie.

   QUÉ **NO** SE TRADUCE, nunca: los DATOS del negocio. Nombre de un
   proyecto, de un comprador, de una carpeta, el texto de un mensaje, el
   concepto de una factura, y sobre todo las CLAVES guardadas en la base
   (`abierto`, `resuelto`, `hak_sewa`…). Se traduce el marco: botones,
   cabeceras, filtros, avisos, mensajes de error. Si una etiqueta visible
   sale de una clave de la base, se traduce la etiqueta y se deja la clave.

   CARGA: en `<head>`, justo detrás de `idioma.js` y SIN `defer` — igual que
   aquél y por el mismo motivo: el <script> propio de cada herramienta tiene
   que encontrar `lwT` ya definido cuando arranca.
   ========================================================================== */
(function () {
  'use strict';

  /* Frases sin traducción encontradas en modo inglés. Es la lista de lo que
     falta, y se lee desde la consola (`[...LW_T_MISSES]`) al verificar una
     herramienta: comprobar la traducción deja de ser mirar la pantalla a ojo
     y pasa a ser una lista. Vacía en español, que no traduce nada. */
  window.LW_T_MISSES = (typeof Set === 'function') ? new Set() : null;

  /* ==========================================================================
     EL DICCIONARIO — clave: el texto en español, exactamente como se escribe
     en el código. Ordenado por temas para poder leerlo, no alfabéticamente.

     · `%n`, `%s`, `%x`… son huecos que rellena el segundo argumento de
       `lwT()`. Se usan SIEMPRE que el texto lleve un número o un nombre
       dentro: `'Hay %n tickets'` y no `'Hay ' + n + ' tickets'`, porque lo
       segundo parte la frase en trozos que no se pueden traducir (en inglés
       el orden de las palabras no es el mismo).
     · Singular y plural son DOS claves enteras, no una con cirugía de
       cadenas: hay idiomas donde no basta con una «s».
     · `frase~contexto` desambigua cuando la misma palabra española es dos
       cosas distintas en inglés. Lo que se imprime en español es siempre lo
       de antes del `~`.
     ========================================================================== */
  var EN = {

    /* ---------- acciones: los botones de toda la suite ---------- */
    'Guardar': 'Save',
    'Guardar cambios': 'Save changes',
    'Guardar en base de datos': 'Save to database',
    'Cancelar': 'Cancel',
    'Cerrar': 'Close',
    'Borrar': 'Delete',
    'Editar': 'Edit',
    'Editar datos': 'Edit details',
    'Editar nombre': 'Edit name',
    'Enviar': 'Send',
    'Enviar por email': 'Send by email',
    'Descargar': 'Download',
    'Descargar PDF': 'Download PDF',
    'Volver': 'Back',
    'Aceptar': 'OK',
    'Añadir': 'Add',
    'Quitar': 'Remove',
    'Duplicar': 'Duplicate',
    'Buscar': 'Search',
    'Ver': 'View',
    'Abrir': 'Open',
    'Copiar': 'Copy',
    'Copiado': 'Copied',
    'Continuar': 'Continue',
    'Reintentar': 'Try again',

    /* ---------- estados y palabras de tabla que se repiten ---------- */
    'Estado': 'Status',
    'Tipo': 'Type',
    'Fecha': 'Date',
    'Cuándo': 'When',
    'Importe': 'Amount',
    'Total': 'Total',
    'Nombre': 'Name',
    'Email': 'Email',
    'Teléfono': 'Phone',
    'Proyecto': 'Project',
    'Unidad': 'Unit',
    'Comprador': 'Buyer',
    'Compradores': 'Buyers',
    'Contrato': 'Contract',
    'Contratos': 'Contracts',
    'Notas': 'Notes',
    'Nota': 'Note',
    'Todos': 'All',
    'Todas': 'All',
    'Ninguno': 'None',
    'Ninguna': 'None',
    'Otros': 'Other',
    'Sin nombre': 'No name',
    'sin nombre': 'no name',
    'Sin fecha': 'No date',
    'sin fecha': 'no date',
    'sin proyecto': 'no project',
    'sin comprador': 'no buyer',
    'sin nº': 'no number',
    'no se sabe': 'unknown',
    'Cargando…': 'Loading…',
    'Pendiente': 'Pending',
    'Pagado': 'Paid',
    'Vencido': 'Overdue',
    'Abierto': 'Open',
    'Abiertos': 'Open',
    'Resuelto': 'Resolved',
    'Resueltos': 'Resolved',
    'Sin firmar': 'Unsigned',
    'Firmado': 'Signed',
    'Contrato firmado': 'Signed contract',

    /* ---------- mensajes de error y de confirmación compartidos ----------
       El sufijo «: » va DENTRO de la clave porque el mensaje de la base se
       concatena después; sin él la frase en inglés quedaría sin puntuación. */
    'No se pudo guardar: ': 'Could not save: ',
    'No se pudo guardar:': 'Could not save:',
    'No se pudo borrar: ': 'Could not delete: ',
    'No se pudo borrar:': 'Could not delete:',
    'No se pudo enviar: ': 'Could not send: ',
    'No se pudo enviar:': 'Could not send:',
    'No se pudo cerrar: ': 'Could not close: ',
    'No se pudo cambiar el estado: ': 'Could not change the status: ',
    'No se pudo cargar: ': 'Could not load: ',
    'No se pudo: ': 'Could not: ',
    'Guardado': 'Saved',
    'Borrado': 'Deleted',
    'Enviado': 'Sent',
    'Nada que enseñar con este filtro.': 'Nothing to show with this filter.',
    'Prueba a quitar algún filtro.': 'Try removing a filter.',
    'Esto no se puede deshacer.': 'This cannot be undone.',
    'Tu sesión ha caducado. Vuelve a entrar.': 'Your session has expired. Please log in again.',

    /* ---------- dialogo.js: parar al usuario y elegir de una lista ---------- */
    '¿Seguimos?': 'Are you sure?',
    'Elige una opción': 'Choose an option',
    'Escribe para buscar…': 'Type to search…',
    'Pulsa para elegir': 'Click to choose',
    'Nada coincide con «%q»': 'Nothing matches “%q”',

    /* ---------- topbar.js: lo que le quedaba suelto ---------- */
    'Plegar o desplegar el menú': 'Collapse or expand the menu',
    'Buscar herramienta…': 'Search tools…',

    /* ---------- herramientas.js: grupos del menú y del hub ---------- */
    'Seguimiento': 'Pipeline',
    'Documentación~grupo': 'Documents',
    'Administración': 'Administration',
    'Base de datos': 'Database',
    'Equipo': 'Team',

    /* ---------- herramientas.js: nombre de cada herramienta ---------- */
    'CRM': 'CRM',
    'Ranking de closers': 'Closer leaderboard',
    'Reparto de leads': 'Lead routing',
    'Agenda de cierre': 'Closing calendar',
    'Operaciones': 'Deals',
    'Soporte': 'Support',
    'Vencimientos': 'Payment schedule',
    'Creatividades': 'Creative',
    'Documentación': 'Documents',
    'Facturas': 'Invoices',
    'Recibos': 'Receipts',
    'Solicitudes': 'Payment requests',
    'Proyectos': 'Projects',
    'Proyectos (nueva vista)': 'Projects (new view)',
    'Modelos': 'House models',
    'Obra': 'Construction',
    'Usuarios': 'Users',

    /* ---------- Soporte ---------- */
    'Buscar comprador…': 'Search buyer…',
    'Ticket': 'Ticket',
    'Último mensaje': 'Last message',
    'No se pudieron leer los tickets: ': 'Could not load the tickets: ',
    'Tú: ': 'You: ',
    'Equipo': 'Team',
    'Responder…': 'Reply…',
    'Marcar resuelto': 'Mark as resolved',
    'Reabrir': 'Reopen',
    'Marcado como resuelto': 'Marked as resolved',
    'Reabierto': 'Reopened',
    'Escribe a través de la intranet, igual que él ve tu respuesta en su área de clientes.':
      'You are writing through the intranet, the same way they see your reply in their client area.',
  };

  window.LW_EN = EN;

  /* `es-ES` estaba escrito a mano en cada `toLocaleDateString` de la suite, y
     con la interfaz en inglés eso imprime «11 sept 2026» debajo de una
     cabecera que dice «Date». Una sola forma de pedir el locale. Se queda en
     `en-GB` y no `en-US`: el equipo y los compradores son europeos y
     asiáticos, y 03/09 tiene que seguir siendo 3 de septiembre. */
  window.lwLocale = function () {
    return window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES';
  };

  /* ==========================================================================
     lwT(texto, huecos) — la única forma de traducir.

     En español devuelve su entrada: la vista española es IDÉNTICA a la de
     antes de envolver el texto, y no por haberlo comprobado sino porque no
     hay otro camino posible por el código.
     ========================================================================== */
  window.lwT = function (s, huecos) {
    if (s == null) return s;
    var base = String(s);
    var corte = base.indexOf('~');          // 'Documentación~grupo' → se imprime 'Documentación'
    var visible = corte === -1 ? base : base.slice(0, corte);

    if (window.LW_IDIOMA === 'en') {
      var v = Object.prototype.hasOwnProperty.call(EN, base) ? EN[base] : null;
      if (v == null) {
        if (window.LW_T_MISSES) window.LW_T_MISSES.add(base);
      } else {
        visible = v;
      }
    }

    if (huecos) {
      for (var k in huecos) {
        if (Object.prototype.hasOwnProperty.call(huecos, k)) {
          visible = visible.split('%' + k).join(huecos[k]);
        }
      }
    }
    return visible;
  };

  /* ==========================================================================
     lwIdiomaAplicar(raiz) — traduce la HTML que ya está escrita en la página.

     El marcado estático (botones de la barra, cabeceras de tabla, buscador)
     ya está en el DOM cuando arranca el script de la herramienta. En vez de
     generarlo por JS se marca en el HTML y se reescribe aquí una vez:

       <th data-t>Comprador</th>                    ← la clave es su texto
       <th data-t="Estado~unidad">Estado</th>       ← clave explícita
       <input data-t-ph placeholder="Buscar…">      ← el placeholder
       <button data-t-title title="Borrar">         ← el title
       <span data-t-aria aria-label="Cerrar">       ← el aria-label

     En ESPAÑOL sale sin tocar el DOM: no se normaliza ni un espacio en
     blanco. En inglés escribe la clave derivada en el atributo antes de
     sustituir, así que volver a llamarla sobre el mismo nodo es inofensivo
     (una herramienta que repinte su cabecera no se queda en inglés a medias).

     No traduce HTML, solo texto: el marcado dentro de una frase no se mete
     en el diccionario. Si una frase lleva negrita, se parte en nodos o se
     compone con %huecos.
     ========================================================================== */
  window.lwIdiomaAplicar = function (raiz) {
    if (window.LW_IDIOMA !== 'en') return;
    var r = raiz || document;

    r.querySelectorAll('[data-t]').forEach(function (el) {
      var k = el.dataset.t || el.textContent.trim();
      if (!k) return;
      el.dataset.t = k;
      el.textContent = window.lwT(k);
    });
    r.querySelectorAll('[data-t-ph]').forEach(function (el) {
      var k = el.dataset.tPh || el.getAttribute('placeholder') || '';
      if (!k) return;
      el.dataset.tPh = k;
      el.setAttribute('placeholder', window.lwT(k));
    });
    r.querySelectorAll('[data-t-title]').forEach(function (el) {
      var k = el.dataset.tTitle || el.getAttribute('title') || '';
      if (!k) return;
      el.dataset.tTitle = k;
      el.setAttribute('title', window.lwT(k));
    });
    r.querySelectorAll('[data-t-aria]').forEach(function (el) {
      var k = el.dataset.tAria || el.getAttribute('aria-label') || '';
      if (!k) return;
      el.dataset.tAria = k;
      el.setAttribute('aria-label', window.lwT(k));
    });

    /* El título de la pestaña. Todas las páginas de la suite se llaman
       «Lawang · ⟨herramienta⟩», así que basta traducir el último tramo — y
       el nombre de cada herramienta ya está en el diccionario porque lo
       necesita el menú. Sin esto, con ocho pestañas abiertas en inglés
       todas siguen rotuladas en español, que es justo donde se distinguen. */
    if (document.title.indexOf(' · ') !== -1) {
      var tramos = document.title.split(' · ');
      var ultimo = tramos.pop();
      document.title = tramos.concat(window.lwT(ultimo)).join(' · ');
    }

    /* El idioma del documento, para el lector de pantalla y el corrector del
       navegador. Una página que dice `lang="es"` y enseña inglés se lee con
       la voz equivocada. */
    if (document.documentElement) document.documentElement.lang = 'en';
  };
})();
