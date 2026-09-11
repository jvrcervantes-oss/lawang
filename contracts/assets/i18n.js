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

    /* ---------- Obra ----------
       El NOMBRE de cada fase no está aquí: `obra_fases` ya tiene columna `en`
       con las siete rellenas, y el dato manda sobre el diccionario. */
    'Buscar código, proyecto o contrato…': 'Search code, project or contract…',
    'Todos los proyectos': 'All projects',
    'Código': 'Code',
    'Fase': 'Stage',
    'Fase actual': 'Current stage',
    'Entrega est.': 'Est. handover',
    'Entrega estimada': 'Estimated handover',
    'Fotos': 'Photos',
    'Fotos (%n)': 'Photos (%n)',
    'Actualizado': 'Updated',
    'En obra': 'Under construction',
    'Con contrato': 'With contract',
    'sin empezar': 'not started',
    '— sin empezar —': '— not started —',
    'Contrato %n': 'Contract %n',
    'Lo que marques aquí lo ve el comprador en su portal.':
      'Whatever you set here is what the buyer sees in their portal.',
    'Sin contrato vinculado: aún no lo ve ningún comprador.':
      'No contract linked: no buyer can see this yet.',
    'Subir fotos — se optimizan solas a tamaño web':
      'Upload photos — they are resized for web automatically',
    'Puedes documentar la obra igualmente: cuando la unidad se vincule a un contrato, el comprador verá el histórico completo.':
      'You can document the work anyway: once the unit is linked to a contract, the buyer will see the full history.',
    'Sin título': 'Untitled',
    'Título': 'Title',
    'Ocultar': 'Hide',
    'Mostrar': 'Show',
    'no se pudo convertir': 'could not be converted',
    'imagen ilegible': 'unreadable image',
    'sin permiso para la herramienta Obra': 'no permission for the Construction tool',
    '%n foto subida': '%n photo uploaded',
    '%n fotos subidas': '%n photos uploaded',
    'Título de la foto (lo ve el comprador):': 'Photo title (the buyer sees it):',
    'Borrar esta foto': 'Delete this photo',
    'Se quita también del portal del comprador. Esto no se puede deshacer.':
      'It is removed from the buyer portal too. This cannot be undone.',

    /* ---------- Solicitudes de pago ----------
       Ojo con el vocabulario: aquí «solicitud» es una PETICIÓN DE COBRO del
       agente a Lawang (comisión, pago acordado), no una solicitud de compra.
       En inglés eso es «payment request», nunca «application». */
    'Nueva solicitud': 'New request',
    'Nueva solicitud de pago': 'New payment request',
    'Editar SP-%n': 'Edit SP-%n',
    'Buscar concepto, contrato o compañero…': 'Search description, contract or colleague…',
    'Nº': 'No.',
    'Quién pide': 'Requested by',
    'Concepto': 'Description',
    'De la venta': 'From sale',
    'Moneda': 'Currency',
    'Pendientes': 'Pending',
    'Por pagar': 'To pay',
    'Aprobada': 'Approved',
    'Rechazada': 'Rejected',
    'Anulada': 'Cancelled',
    'Pagada': 'Paid',
    'Aprobar': 'Approve',
    'Rechazar…': 'Reject…',
    'Anular': 'Cancel request',
    'Marcar pagada…': 'Mark as paid…',
    'Crear solicitud': 'Create request',
    'Todos los agentes': 'All agents',
    'No se pudieron leer las solicitudes: ': 'Could not load the requests: ',
    'Tú': 'You',
    'contrato': 'contract',
    '%n pendiente de resolver': '%n awaiting your decision',
    '%n pendientes de resolver': '%n awaiting your decision',
    '%n aprobada por pagar': '%n approved, unpaid',
    '%n aprobadas por pagar': '%n approved, unpaid',
    'hace %n d': '%n d ago',
    'Fecha límite': 'Due date',
    'Fecha límite (opcional)': 'Due date (optional)',
    'Pedida': 'Requested',
    'Resolución': 'Decision',
    'Motivo': 'Reason',
    'Motivo del rechazo': 'Reason for rejection',
    'Resuelta por': 'Decided by',
    'Pagada por': 'Paid by',
    'Referencia del pago': 'Payment reference',
    'el pago se hace fuera (transferencia); aquí queda pedido, aprobado y pagado.':
      'the payment happens outside (bank transfer); this records the request, the approval and the payment.',
    'Solicitud aprobada — queda por pagar': 'Request approved — pending payment',
    'Marcada como pagada': 'Marked as paid',
    'Solicitud rechazada': 'Request rejected',
    'Solicitud anulada': 'Request cancelled',
    'Se le enseña al compañero tal cual — di qué falta o por qué no procede':
      'Your colleague sees this as written — say what is missing or why it does not apply',
    'Rechazar la solicitud': 'Reject the request',
    'El motivo es obligatorio: sin él la base no acepta el rechazo.':
      'A reason is required: without one the database will not accept the rejection.',
    'Cómo se ha pagado — transferencia, Wise, fecha… (opcional, pero al compañero le llega en el aviso)':
      'How it was paid — bank transfer, Wise, date… (optional, but your colleague gets it in the notification)',
    'Confirmar: pagada': 'Confirm: paid',
    'Anular la solicitud': 'Cancel the request',
    'SP-%n quedará anulada. No se borra: el registro se queda, sin efecto.':
      'SP-%n will be cancelled. It is not deleted: the record stays, with no effect.',
    'Pide un pago a Lawang — una comisión, un pago acordado. Administración lo aprueba y lo paga.':
      'Request a payment from Lawang — a commission, an agreed payment. Administration approves and pays it.',
    'Concepto — qué pago estás pidiendo': 'Description — what payment you are requesting',
    'Comisión venta W3.1-D1 · pago acordado septiembre…':
      'Commission on sale W3.1-D1 · agreed payment September…',
    'De qué venta viene, si viene de una (opcional)': 'Which sale it comes from, if any (optional)',
    'Elegir contrato…': 'Choose a contract…',
    '— Sin venta asociada —': '— No sale linked —',
    'La venta de la que viene el pago': 'The sale this payment comes from',
    'Nota para Administración (opcional)': 'Note for Administration (optional)',
    'El concepto no puede quedar vacío': 'The description cannot be empty',
    'El importe no se entiende — escribe un número mayor que cero':
      'The amount is not valid — enter a number greater than zero',
    'Solicitud actualizada': 'Request updated',
    'Solicitud creada — Administración ya tiene el aviso':
      'Request created — Administration has been notified',
    'Resueltas': 'Closed',

    /* ---------- Modelos (catálogo de tipos de vivienda) ----------
       Vocabulario fijado aquí y reutilizado por Proyectos y por Contratos:
       modelo = house model · techo = roof type · extra = add-on ·
       alcance de obra = scope of work · precio de catálogo = catalogue price.
       «Villa» y «Terraza» se quedan igual: son las mismas palabras en inglés
       y ya se usan así en la web pública. */
    'Nuevo modelo': 'New model',
    'Buscar modelo…': 'Search model…',
    'Publicados y no publicados': 'Published and unpublished',
    'Solo publicados en la web': 'Published on the website only',
    'Solo sin publicar': 'Unpublished only',
    '%n modelo': '%n model',
    '%n modelos': '%n models',
    '%n publicado en la web': '%n published on the website',
    '%n publicados en la web': '%n published on the website',
    '%n en la vista': '%n in view',
    'Ningún modelo con ese filtro.': 'No model matches that filter.',
    '%n dorm': '%n bed',
    '%n baños': '%n baths',
    'sin specs': 'no specs',
    'sin precio de catálogo': 'no catalogue price',
    'en la web': 'live',
    'sin publicar': 'unpublished',
    '%n proyecto': '%n project',
    '%n proyectos': '%n projects',
    '%n doc': '%n doc',
    '%n docs': '%n docs',
    'Publicado en /modelo/%s': 'Published at /modelo/%s',
    'No sale en la web': 'Not on the website',
    'renders pendientes': 'renders pending',
    'Ficha': 'Details',
    'Dormitorios': 'Bedrooms',
    'Baños': 'Bathrooms',
    'Villa': 'Villa',
    'Terraza': 'Terrace',
    'Villa (m²)': 'Villa (m²)',
    'Terraza (m²)': 'Terrace (m²)',
    'Descripción': 'Description',
    'Dirección en la web': 'Website address',
    '— cambiarla rompe los enlaces que ya estén publicados.':
      '— changing it breaks any links already published.',
    'Precio de construcción (catálogo)': 'Construction price (catalogue)',
    'Precio de catálogo': 'Catalogue price',
    'Construcción': 'Construction',
    'Techos': 'Roof types',
    'desde 2027: ': 'from 2027: ',
    'Sin variantes de techo. El precio de catálogo es el único.':
      'No roof variants. The catalogue price is the only one.',
    'Cuál de los dos precios está vigente lo decide el reloj del servidor, nunca un ajuste a mano.':
      'Which of the two prices applies is decided by the server clock, never by a manual switch.',
    'Este modelo no tiene variantes de techo.': 'This model has no roof variants.',
    'Primera columna: precio de hoy. Segunda: desde el 1-ene-2027.':
      'First column: today’s price. Second: from 1 Jan 2027.',
    'Precio de %s ahora': 'Price of %s now',
    'Precio de %s desde 2027': 'Price of %s from 2027',
    'Precio de %s': 'Price of %s',
    'Precio en %s': 'Price in %s',
    'Extras': 'Add-ons',
    'Extras disponibles': 'Available add-ons',
    'Ninguno dado de alta todavía.': 'None added yet.',
    'se ofrece': 'offered',
    'Sin precio, el extra no se ofrece en la web: no se estima a ojo.':
      'With no price the add-on is not offered on the website: it is never estimated by eye.',
    'Alcance de obra': 'Scope of work',
    'Incluido': 'Included',
    'No incluido': 'Not included',
    'Sin alcance de obra. Solo se rellena con lo verificado en el':
      'No scope of work. It is only filled in from what is verified in the',
    'anexo de obra de este modelo': 'construction annex of this model',
    ': copiarlo de otro es publicar un contrato que nadie ha firmado.':
      ': copying it from another one means publishing a contract nobody signed.',
    'Una línea por punto. Es lo que la ficha publica como «Included» y «Not included», así que':
      'One line per item. This is what the website publishes as “Included” and “Not included”, so',
    'solo se escribe lo que diga el anexo de obra de ESTE modelo':
      'only write what the construction annex of THIS model says',
    '. Copiarlo de otro modelo es publicar un contrato que nadie ha firmado.':
      '. Copying it from another model means publishing a contract nobody signed.',
    'Precio por proyecto': 'Price by project',
    'Vacío significa': 'Empty means',
    'hereda del catálogo': 'inherits the catalogue price',
    ', no «sin dato». Solo se rellena cuando ese proyecto tiene un precio propio pactado.':
      ', not “no data”. Fill it in only when that project has its own agreed price.',
    'heredado': 'inherited',
    'propio': 'own price',
    'Este modelo no está declarado en ningún proyecto todavía.':
      'This model is not declared in any project yet.',
    'Este modelo no está declarado en ningún proyecto.':
      'This model is not declared in any project.',
    'Dejar vacío = hereda el precio de catálogo. Rellenar solo si ese proyecto tiene precio propio pactado.':
      'Leave empty = inherits the catalogue price. Fill it in only if that project has its own agreed price.',
    'hereda %s': 'inherits %s',
    'Añadir a un proyecto…': 'Add to a project…',
    'Declararlo en un proyecto es lo que hace que aparezca en el desplegable de sus parcelas.':
      'Declaring it in a project is what makes it appear in that project’s plot dropdown.',
    'Es el nivel 1 de la cascada: lo heredan todos los proyectos que no tengan precio propio, y es lo que publica la web como «desde».':
      'This is level 1 of the cascade: every project without its own price inherits it, and it is what the website publishes as “from”.',
    'Documentos': 'Documents',
    'visible para el comprador': 'visible to the buyer',
    'Sin planos ni memoria de calidades todavía.':
      'No floor plans or specification sheets yet.',
    'Tipo de documento': 'Document type',
    'Plano · anexo del contrato': 'Floor plan · contract annex',
    'Memoria de calidades': 'Specification sheet',
    'Render': 'Render',
    'Otro': 'Other',
    'Añadir documento': 'Add document',
    'PDF o imagen, hasta 50 MB. Nace privado: que lo vea el comprador se decide fichero a fichero.':
      'PDF or image, up to 50 MB. Private by default: whether the buyer sees it is decided file by file.',
    'El de tipo': 'The one of type',
    'es el que el contrato de Construcción adjunta solo al elegir este modelo (el más reciente si hay varios). Sin ninguno, se sigue usando el PDF que el estudio tenga en el repo.':
      'is the one the Construction contract attaches automatically when this model is chosen (the most recent one if there are several). With none, the PDF held in the studio repo is used instead.',
    'Subiendo…': 'Uploading…',
    'Documento añadido': 'Document added',
    'El fichero pasa de 50 MB': 'The file is over 50 MB',
    'No se ha subido:': 'Not uploaded:',
    'No se ha guardado la ficha del documento:': 'The document record was not saved:',
    'No se ha podido abrir:': 'Could not open:',
    'sin enlace': 'no link',
    'No se ha podido cargar: ': 'Could not load: ',
    'Publicación': 'Publishing',
    'Activo (si se desmarca, deja de ofrecerse en toda la suite)':
      'Active (unchecked, it stops being offered across the whole suite)',
    'Renders pendientes — la ficha dirá «Renders in progress» en vez de enseñar una foto de otro modelo':
      'Renders pending — the page will say “Renders in progress” instead of showing a photo of another model',
    'Notas internas': 'Internal notes',
    'No sale nunca en la web: el RPC público no las devuelve.':
      'Never shown on the website: the public RPC does not return them.',
    'Editar datos': 'Edit details',
    'Los precios y las specs los edita un administrador. Tú sí puedes subir documentos.':
      'Prices and specs are edited by an administrator. You can still upload documents.',
    'Renombrar': 'Rename',
    'Renombrar «%a» a «%b»': 'Rename “%a” to “%b”',
    'El nombre nuevo se propaga solo a': 'The new name propagates on its own to',
    '%n unidad': '%n unit',
    '%n unidades': '%n units',
    'y a sus precios por proyecto. Lo ya impreso en un documento firmado no se toca.':
      'and to its per-project prices. Anything already printed on a signed document is untouched.',
    'El nombre no puede quedar vacío': 'The name cannot be empty',
    'La dirección solo admite minúsculas, números y guiones':
      'The address only accepts lowercase letters, numbers and hyphens',
    'Ya hay un modelo en esa dirección': 'There is already a model at that address',
    'No se ha guardado: ': 'Not saved: ',
    'No se ha guardado: cambiar precios y specs es de administrador.':
      'Not saved: changing prices and specs is for administrators.',
    'Dar de alta un modelo es de administrador': 'Creating a model is for administrators',
    'Tu ficha entra en Modelos para consultar y para subir documentos. Crear un modelo o cambiar un precio lo hace un administrador.':
      'Your account can open Models to look things up and to upload documents. Creating a model or changing a price is done by an administrator.',
    'Entendido': 'Got it',
    'Nace sin publicar. Las specs, los techos y los extras se rellenan después.':
      'It starts unpublished. Specs, roof types and add-ons are filled in afterwards.',
    'Dune, Granada…': 'Dune, Granada…',
    'Se rellena sola desde el nombre. Solo minúsculas, números y guiones.':
      'Filled in automatically from the name. Lowercase letters, numbers and hyphens only.',
    'IDR solo para los proyectos que llevan el inventario en rupias (Riverfront).':
      'IDR only for the projects whose inventory is kept in rupiah (Riverfront).',
    'Si el inventario ya usa este nombre, las unidades que lo nombran se enganchan solas al guardar: el enlace lo ata el propio trigger de la base.':
      'If the inventory already uses this name, the units naming it link themselves on save: the database trigger ties the link.',
    'Hacen falta el nombre y la dirección': 'The name and the address are required',
    'Crear': 'Create',
    'No se ha creado: ': 'Not created: ',
    'No se ha creado: dar de alta un modelo es de administrador.':
      'Not created: creating a model is for administrators.',
    'Modelo creado. Ahora sus datos.': 'Model created. Now its details.',
    'Se resuelve dando de alta el modelo con ese nombre, o corrigiendo el nombre en Proyectos. Mientras tanto se quedan como están, que es lo correcto.':
      'Fix it by creating the model under that name, or by correcting the name in Projects. In the meantime they stay as they are, which is the right thing.',
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
