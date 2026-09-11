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

    /* ---------- Usuarios ----------
       Los nombres de rol se traducen como ROTULO; la clave (`agente`,
       `sales_manager`…) es la de la base y la de la edge `admin-usuarios`, y
       no aparece aquí a propósito. «Sales manager» y «Project manager» ya
       estaban en inglés en el original: el equipo los llama así. */
    'Buscar nombre, email o rol…': 'Search name, email or role…',
    'Nuevo usuario': 'New user',
    'Elige un usuario': 'Choose a user',
    'Nadie con «%q».': 'Nobody matching “%q”.',
    'por %s': 'by %s',
    'Agente': 'Agent',
    'Sales manager': 'Sales manager',
    'Project manager': 'Project manager',
    'Administrador': 'Administrator',
    'Super admin': 'Super admin',
    'Rol': 'Role',
    'Identidad y rol': 'Identity and role',
    'Acceso': 'Access',
    'Activo': 'Active',
    'Desactivado — no entra a la suite': 'Deactivated — cannot enter the suite',
    'Desactivar es lo contrario de borrar: la persona deja de entrar pero se conserva qué documentos creó. Nunca se borra un usuario.':
      'Deactivating is the opposite of deleting: the person can no longer log in, but the record of what they created is kept. A user is never deleted.',
    'Esta es tu propia cuenta. Para no dejarte fuera por accidente, no puedes desactivarte ni cambiarte el rol desde aquí.':
      'This is your own account. So you cannot lock yourself out by accident, you cannot deactivate yourself or change your own role here.',
    'Solo un super admin puede modificar la cuenta de otro super admin.':
      'Only a super admin can modify another super admin’s account.',
    'Un': 'A',
    'Nace': 'Starts as',
    've las herramientas que le marques abajo (igual que un agente, no todas por defecto) y puede editar los documentos de cualquiera dentro de ellas. Un':
      'sees the tools you tick below (like an agent — not all of them by default) and can edit anyone’s documents inside them. A',
    've, crea y corrige contratos y facturas de': 'sees, creates and corrects contracts and invoices for',
    'vende él mismo': 'sells directly too',
    'sin ningún proyecto asignado': 'with no project assigned',
    'se marca desde la ficha de cada proyecto en': 'is set from each project’s record in',
    'todavía.': 'yet.',
    '. Solo un': '. Only a',
    '. La consulta de datos ya emitidos sigue abierta a todo el equipo: Operaciones cruza contratos, facturas y firmas, y filtrarlas por herramienta la dejaría en blanco.':
      '. Reading data already issued stays open to the whole team: Deals cross-references contracts, invoices and signatures, and filtering it by tool would leave it blank.',
    'Herramientas que ve': 'Tools they see',
    'Herramientas que verá': 'Tools they will see',
    'Controla lo que aparece en la intranet y lo que puede':
      'Controls what appears in the intranet and what they can',
    'Permisos actualizados': 'Permissions updated',
    'CRM de leads': 'Lead CRM',
    'Cuatro llaves distintas y a propósito:': 'Four separate keys, on purpose:',
    'Leads': 'Leads',
    'abre los datos de contacto de las personas que dejan su teléfono;':
      'opens the contact details of the people who leave their phone number;',
    'Ranking': 'Leaderboard',
    ', las cifras de cada comercial;': ', each rep’s figures;',
    'Reparto': 'Routing',
    ', quién atiende cada campaña;': ', who handles each campaign;',
    'Agenda': 'Calendar',
    ', las llamadas de venta. Quien tenga Ranking y Reparto a la vez puede mover el número que decide el reparto':
      ', the sales calls. Anyone holding both Leaderboard and Routing can move the very number that decides the routing',
    'el reparto — dáselas juntas solo si es a conciencia.':
      'the routing — give them together only deliberately.',
    'De salida no viene marcada ninguna, y es deliberado:': 'None is ticked by default, deliberately:',
    'abre los datos de contacto de personas reales y eso se decide una a una, nunca de regalo con el rol.':
      'opens the contact details of real people, and that is decided one by one — never thrown in with a role.',
    'Proyectos en los que trabaja': 'Projects they work on',
    'Proyectos que supervisa': 'Projects they supervise',
    'Marcar todos': 'Tick all',
    'Limita': 'Limits',
    'en qué proyectos puede crear y editar contratos':
      'which projects they can create and edit contracts in',
    'este usuario, sea agente o manager — un sales manager o project manager también vende. Sin ninguno marcado no puede crear contratos en ningún proyecto':
      'for this user, agent or manager — a sales manager or project manager sells too. With none ticked they cannot create contracts in any project',
    'pero': 'but',
    'a este usuario no le afecta': 'this user is not affected',
    'los administradores trabajan en todos los proyectos por definición':
      'administrators work across every project by definition',
    'No cambia lo que ve en Operaciones ni en Vencimientos, que siguen mostrando la actividad del equipo.':
      'It does not change what they see in Deals or in the Payment schedule, which keep showing the team’s activity.',
    'Esto no es de qué proyectos es encargado': 'This is not which projects they are in charge of',
    'eso es la lista de abajo.': 'that is the list below.',
    ', no aquí: lo de abajo es otra cosa, en qué proyectos':
      ', not here: the list below is a different thing — which projects',
    'De esto sí ve y corrige TODO lo que hagan sus agentes — contratos, facturas, obra, clientes, solicitudes — sea cual sea quien lo creó, y por eso':
      'Here they do see and correct EVERYTHING their agents do — contracts, invoices, construction, clients, requests — whoever created it, and that is why it',
    'se asigna desde la ficha de cada proyecto': 'is assigned from each project’s record',
    '(Proyectos → el lápiz junto a su carpeta), no desde aquí. Esto de abajo es solo un espejo de lo ya asignado, para verlo sin salir de esta ficha.':
      '(Projects → the pencil next to its folder), not from here. The list below only mirrors what is already assigned, so you can see it without leaving this record.',
    'Contratos que puede hacer': 'Contracts they can issue',
    'A este usuario': 'This user',
    'no le afecta': 'is not affected',
    'un sales manager o project manager no crea ni edita contratos, solo los lee.':
      'a sales manager or project manager does not create or edit contracts, only reads them.',
    'Sin ninguno marcado no puede emitir ningún contrato':
      'With none ticked they cannot issue any contract',
    'igual que en «Proyectos», arriba.': 'the same as in “Projects”, above.',
    'Lo comprueba la': 'It is checked by the',
    'base de datos': 'database',
    'al guardar, no solo el desplegable: esconder una opción no es impedirla.':
      'on save, not just by the dropdown: hiding an option is not the same as preventing it.',
    'un administrador emite cualquier tipo por definición.':
      'an administrator issues every type by definition.',
    'Preselección según el rol elegido arriba — sigue siendo editable.':
      'Preselected from the role chosen above — still editable.',
    'Preselección según el rol —': 'Preselected from the role —',
    'vacío marcado del todo equivale a "todos"': 'nothing ticked means “all”',
    ', así que conviene dejarlo tal cual salvo que sepas que este usuario necesita algo distinto.':
      ', so leave it as it is unless you know this user needs something different.',
    'Guardando…': 'Saving…',
    'Creando…': 'Creating…',
    'Crear usuario': 'Create user',
    'Datos de acceso': 'Login details',
    'Nombre y apellidos': 'Full name',
    'Contraseña provisional (mínimo 10 caracteres)': 'Temporary password (at least 10 characters)',
    'La verá al entrar; que la cambie después': 'They will see it on login; have them change it afterwards',
    'Mínimo 10 caracteres': 'At least 10 characters',
    'La contraseña necesita 10 caracteres o más': 'The password needs 10 characters or more',
    'Email no válido': 'Invalid email',
    'La contraseña se muestra en claro a propósito: hay que poder copiarla para dársela a la persona. No queda guardada en ningún sitio consultable.':
      'The password is shown in the clear on purpose: you have to be able to copy it to hand it over. It is not stored anywhere you can look it up again.',
    'Se crea la cuenta y se le da acceso de inmediato.': 'The account is created and access granted immediately.',
    'Usuario creado:': 'User created:',
    'No se pudo crear:': 'Could not create:',
    'Cambiar contraseña': 'Change password',
    'Nueva contraseña para %s (mínimo 10 caracteres).': 'New password for %s (at least 10 characters).',
    'Apúntala: no se puede volver a consultar.': 'Write it down: it cannot be looked up again.',
    'Contraseña cambiada': 'Password changed',
    'respuesta ilegible del servidor': 'unreadable response from the server',
    'No se pudo cargar el catálogo de proyectos. Vuelve a abrir el panel: sin él, guardar dejaría a esta persona sin ningún proyecto.':
      'Could not load the project catalogue. Reopen the panel: without it, saving would leave this person with no project at all.',
    'No tienes activada la herramienta «Usuarios». Pídesela a un super admin.':
      'You do not have the “Users” tool enabled. Ask a super admin for it.',
    'Solo un administrador gestiona usuarios': 'Only an administrator manages users',
    'tu rol es «%r»': 'your role is “%r”',
    /* Frenos saltados: el registro de quién se saltó qué. Se traduce el verbo,
       nunca la clave del evento (`desbloqueado`, `facturado_sin_bloquear`…). */
    'Frenos saltados': 'Overrides used',
    'Mirado ahora mismo:': 'Checked just now:',
    'nadie se ha saltado ningún freno': 'nobody has overridden anything',
    'no se ha podido leer': 'could not be read',
    'No se ha podido leer el registro de privilegios.': 'The override log could not be read.',
    'Esto NO quiere decir que nadie se haya saltado nada: quiere decir que no se ha mirado. Recarga la página.':
      'This does NOT mean nobody overrode anything: it means nothing was checked. Reload the page.',
    'desbloqueó un contrato firmado': 'unlocked a signed contract',
    'editó un contrato firmado': 'edited a signed contract',
    'facturó un contrato sin firmar': 'invoiced an unsigned contract',
    'aplicó un cobro al comprador de otro contrato': 'applied a payment to another contract’s buyer',
    'aplicó un cobro a una factura sin contrato': 'applied a payment to an invoice with no contract',
    'guardó un contrato sin ficha de comprador': 'saved a contract with no buyer record',
    'caja negra: no se ha podido leer': 'black box: could not be read',
    '%n documento borrado guardado en la caja negra': '%n deleted document kept in the black box',
    '%n documentos borrados guardados en la caja negra': '%n deleted documents kept in the black box',
    've el tablero y los datos de contacto de los leads': 'see the board and the leads’ contact details',
    'ver el tablero y los datos de contacto de los leads': 'see the board and the leads’ contact details',
    'ver y corregir cuánto firma y cobra cada comercial':
      'see and correct how much each rep signs and earns',
    'decidir qué closers atienden cada campaña': 'decide which closers handle each campaign',
    'la agenda de llamadas de venta': 'the sales-call calendar',

    /* ---------- Vencimientos (la caja de la empresa por fechas) ----------
       «Vencimiento» aquí es una fecha en la que ENTRA dinero, no un impago:
       payment / payment due. «Cartera» es el portfolio de contratos firmados.
       Los cuatro tramos del aging y los «Sin proyecto/Sin comprador» salen de
       `logica.js`, que llama al diccionario por su propio puente `vT`. */
    'Sin proyecto': 'No project',
    'Sin comprador': 'No buyer',
    '1–30 días': '1–30 days',
    '31–60 días': '31–60 days',
    '61–90 días': '61–90 days',
    '+90 días': '90+ days',
    'Parcial': 'Partial',
    'Cobrado': 'Collected',
    'Cartera': 'Portfolio',
    'Vence': 'Due',
    'Vence en 30 días': 'Due in 30 days',
    'Vence en 90 días': 'Due in 90 days',
    'pendiente con la fecha pasada': 'outstanding past its date',
    'nada con la fecha pasada': 'nothing past its date',
    'previsto en el próximo mes': 'expected next month',
    'previsto en el trimestre': 'expected this quarter',
    '%p% de la cartera': '%p% of the portfolio',
    'contratos firmados, sin contar las Cartas de Reserva':
      'signed contracts, Reservation Letters excluded',
    '%n contrato con precio y sin calendario de pagos':
      '%n contract with a price and no payment schedule',
    '%n contratos con precio y sin calendario de pagos':
      '%n contracts with a price and no payment schedule',
    '%n contrato cuyos hitos no suman 100%': '%n contract whose milestones do not add up to 100%',
    '%n contratos cuyos hitos no suman 100%': '%n contracts whose milestones do not add up to 100%',
    '%n sin firmar': '%n unsigned',
    '%n Carta de Reserva': '%n Reservation Letter',
    '%n Cartas de Reserva': '%n Reservation Letters',
    'Fuera de este panel:': 'Outside this panel:',
    'y': 'and',
    'de precio': 'in price',
    'Sobre todo en %s': 'Mostly in %s',
    'Aquí solo entran contratos firmados que no sean preliminares':
      'Only signed, non-preliminary contracts are counted here',
    'Previsión de caja por mes: cobrado, pendiente y vencido':
      'Cash forecast by month: collected, outstanding and overdue',
    'línea discontinua = mes actual': 'dashed line = current month',
    'Solo vencimientos con fecha: lo «sin fecha» no está aquí — está en su alerta.':
      'Only dated payments: anything “no date” is not here — it is in its own alert.',
    'Composición de la cartera': 'Portfolio breakdown',
    'Composición de la cartera: cobrado, pendiente y vencido':
      'Portfolio breakdown: collected, outstanding and overdue',
    'Sin cartera en esta moneda.': 'No portfolio in this currency.',
    'Dinero por trimestre (pendiente)': 'Money by quarter (outstanding)',
    'Pendiente por trimestre': 'Outstanding by quarter',
    'Pendiente sin vencer': 'Outstanding, not yet due',
    'en %n vencimiento': 'across %n payment',
    'en %n vencimientos': 'across %n payments',
    'Vencido por antigüedad': 'Overdue by age',
    'Vencido por antigüedad del retraso': 'Overdue by how late it is',
    '%e de retraso': '%e late',
    'Nada vencido en esta moneda. Que siga así.': 'Nothing overdue in this currency. Long may it last.',
    'Por proyecto': 'By project',
    'Sin proyectos en esta moneda.': 'No projects in this currency.',
    'cobrado': 'collected',
    'pendiente': 'outstanding',
    'vencido': 'overdue',
    'Cubierto': 'Covered',
    'Barra = cartera del proyecto, al ancho relativo del mayor. Verde cobrado · teal pendiente · rojo vencido':
      'Bar = the project’s portfolio, scaled to the largest. Green collected · teal outstanding · red overdue',
    'se enseñan los 8 mayores': 'the 8 largest are shown',
    'Necesitan atención': 'Need attention',
    'Vencidos': 'Overdue',
    'Próximos 90 días': 'Next 90 days',
    'Todos los vencimientos': 'All payments',
    'Incluir sin firmar': 'Include unsigned',
    'Mientras se da de alta el histórico, «sin firmar» significa «aún no marcado», no «aún no acordado»':
      'While the historical backlog is being loaded, “unsigned” means “not marked yet”, not “not agreed yet”',
    'Nada con este filtro.': 'Nothing with this filter.',
    'sin firmar': 'unsigned',
    'Cliente': 'Client',
    'Hito': 'Milestone',
    'Cambiar la fecha de este vencimiento': 'Change this payment’s date',
    'Fecha ajustada a mano': 'Date adjusted by hand',
    'Facturada': 'Invoiced',
    'El sistema ya emitió y envió la factura de este vencimiento':
      'The system already issued and sent the invoice for this payment',
    'Sin auto': 'No auto',
    'Este vencimiento no recibe factura automática': 'This payment gets no automatic invoice',
    'Nueva fecha de vencimiento': 'New due date',
    'Vencimiento el %f': 'Due on %f',
    'Fecha quitada — vuelve a «Sin fecha»': 'Date removed — back to “No date”',
    'Sin contratos en esta moneda.': 'No contracts in this currency.',
    'Factura': 'Invoice',
    'Facturas con vencimiento propio': 'Invoices with their own due date',
    'Vencida': 'Overdue',
    'En plazo': 'On time',
    'Ninguna factura con fecha de vencimiento en esta moneda.':
      'No invoice with a due date in this currency.',
    'No se pudieron leer los contratos:': 'Could not load the contracts:',
    'No se pudieron leer los vencimientos:': 'Could not load the payments:',
    'No se pudo calcular lo cobrado:': 'Could not calculate what has been collected:',
    'No se pudo guardar la fecha:': 'Could not save the date:',

    /* ---------- El hub (`/intranet/`) y el catálogo (`herramientas.js`) ----------
       `nombre`, `para` y `grupo` del catálogo siguen escritos en español: ese
       fichero es la FUENTE. Lo que se traduce es el rótulo al pintarlo, aquí
       y en el menú lateral de `topbar.js`. Las palabras de búsqueda (`claves`)
       no están en este diccionario: se AMPLIARON con el inglés en el propio
       catálogo, porque el buscador mira una sola cadena y tiene que encontrar
       lo mismo se escriba «facturas» o «invoices». */
    'Intranet': 'Intranet',
    'Herramientas': 'Tools',
    'Buenos días': 'Good morning',
    'Buenas tardes': 'Good afternoon',
    'Buenas noches': 'Good evening',
    'Esto es lo que necesita tu atención.': 'Here is what needs your attention.',
    'Esto es lo que necesita tu atención hoy,': 'Here is what needs your attention today,',
    'Acceso restringido: cada herramienta exige esta misma sesión.':
      'Restricted access: every tool requires this same session.',
    'Ninguna herramienta coincide con «%q».': 'No tool matches “%q”.',
    'No tienes acceso a «%h».': 'You do not have access to “%h”.',
    'Pídeselo a un administrador: en tu ficha se activa herramienta por herramienta.':
      'Ask an administrator for it: it is enabled tool by tool on your account.',
    'Tu cuenta está desactivada. Habla con un administrador.':
      'Your account is deactivated. Talk to an administrator.',
    'Correo': 'Email',
    'Contraseña': 'Password',
    'Entrar': 'Log in',
    'Salir': 'Log out',
    'Credenciales incorrectas': 'Wrong email or password',
    'Entra por el área de clientes →': 'Go to the client area →',
    /* cifras del hub */
    'Firmas esperando': 'Signatures waiting',
    'pendientes de que el comprador firme': 'waiting on the buyer to sign',
    'ninguna pendiente': 'none pending',
    '%n aún editables': '%n still editable',
    'Facturas emitidas': 'Invoices issued',
    'Unidades libres': 'Units available',
    'de %n en inventario': 'of %n in inventory',
    'con fase abierta': 'with an open stage',
    'sin unidades en obra': 'no units under construction',
    'la base no contestó': 'the database did not answer',
    '%n herramienta sin cifra: la base no contestó y no se inventa un cero.':
      '%n tool with no figure: the database did not answer, and a zero is not invented.',
    '%n herramientas sin cifra: la base no contestó y no se inventa un cero.':
      '%n tools with no figure: the database did not answer, and a zero is not invented.',
    'Cifras al día de %h.': 'Figures as of %h.',
    /* últimas operaciones */
    'Operaciones recientes': 'Recent activity',
    'Editable': 'Editable',
    'Recibí': 'Receipt',
    'Proforma': 'Proforma',
    'Anulada': 'Voided',
    'Emitida': 'Issued',
    /* riel de avisos */
    'Firmas que necesitan atención': 'Signatures needing attention',
    'Cadena parada': 'Chain stalled',
    'Sin email': 'No email',
    'Enlace caducado': 'Link expired',
    'Sin documento': 'No document',
    'aviso más': 'more alert',
    'avisos más': 'more alerts',
    'Una cadena parada deja el contrato editable después de firmado. Ábrelo en Contratos y genera el enlace que falta.':
      'A stalled chain leaves the contract editable after signing. Open it in Contracts and generate the missing link.',
    'las firmas pendientes': 'the pending signatures',
    'los vencimientos': 'the payment schedule',
    'Próximos vencimientos': 'Upcoming payments',
    'Nada a la vista': 'Nothing on the horizon',
    'No se ha podido comprobar': 'Could not be checked',
    'Esto NO quiere decir que no haya nada: quiere decir que no se ha mirado.':
      'This does NOT mean there is nothing: it means nothing was checked.',
    'Recarga la página; si sigue igual, avisa a desarrollo.':
      'Reload the page; if it persists, tell development.',
    /* cifras de cada tarjeta del catálogo */
    '%n sin contactar': '%n not contacted',
    'Todos contestados': 'Everyone answered',
    '%n firma esperando': '%n signature waiting',
    '%n firmas esperando': '%n signatures waiting',
    'Sin firmas pendientes': 'No signatures pending',
    '%n ticket abierto': '%n open ticket',
    '%n tickets abiertos': '%n open tickets',
    'Sin tickets abiertos': 'No open tickets',
    '%n sin fecha que vigilar': '%n with no date to watch',
    'Calendario al día': 'Schedule up to date',
    '%g guardados · %e editables': '%g saved · %e editable',
    'Sin documentos todavía': 'No documents yet',
    '%d documentos · %p proyectos': '%d documents · %p projects',
    '%n emitidas': '%n issued',
    '%n anuladas': '%n voided',
    '%n emitidos': '%n issued',
    '%n por resolver o pagar': '%n to decide or pay',
    'Sin solicitudes en vuelo': 'No requests in flight',
    'Sin inventario cargado': 'No inventory loaded',
    '%u unidades · %l disponibles': '%u units · %l available',
    '%n sin precio de catalogo': '%n with no catalogue price',
    '%m modelos · %p en la web': '%m models · %p live',
    'Sin unidades en obra': 'No units under construction',
    '%n en obra': '%n under construction',
    '%n fichas': '%n records',
    '%n con acceso': '%n with access',
    '%n desactivados': '%n deactivated',
    /* descripciones del catálogo (`para`) */
    'Los leads que entran por Meta y por la web: en qué punto está cada uno y quién lo lleva.':
      'The leads coming in from Meta and from the website: where each one stands and who owns it.',
    'Cuánto firma y cuánto cobra cada comercial, y a quién se atribuye cada venta.':
      'How much each rep signs and earns, and who each sale is credited to.',
    'Que closers atienden cada campana, su tope de leads sin contactar y el reparto automatico.':
      'Which closers handle each campaign, their cap on uncontacted leads, and automatic routing.',
    'La agenda de llamadas de venta del closer, dentro del CRM.':
      'The closer’s sales-call calendar, inside the CRM.',
    'Cómo va cada venta: estado de cuenta, documentos, firmas y vencimientos.':
      'How each sale is going: statement of account, documents, signatures and payments.',
    'Los tickets de los compradores desde su área de clientes, en una bandeja.':
      'Buyer tickets from their client area, in one inbox.',
    'Qué dinero debe entrar, cuándo, y cuál se está retrasando: la caja de la empresa por fechas.':
      'What money is due, when, and what is running late: the company’s cash by date.',
    'Reservas, PPJB, construcción y anexos.': 'Reservations, PPJB, construction and annexes.',
    'Dossiers de producto y piezas de pauta para Instagram y Facebook, con la revisión de legibilidad incorporada.':
      'Product brochures and paid-social assets for Instagram and Facebook, with the legibility check built in.',
    'Precios, planos y material de cada proyecto, en el almacén privado.':
      'Pricing, floor plans and material for each project, in the private store.',
    'Facturas, proformas y recibís, cada tipo con su serie.':
      'Invoices, proformas and receipts, each type with its own series.',
    'Justificantes de pago y señales.': 'Proof of payment and deposits.',
    'Pagos que piden los comerciales — comisiones y acordados: quién pide qué, y en qué quedó cada uno.':
      'Payments the reps request — commissions and agreed payments: who asked for what, and how each one ended.',
    'Inventario de parcelas y villas con su estado de venta, por proyecto.':
      'Inventory of plots and villas with their sales status, by project.',
    'La misma base de parcelas y villas, en tarjetas por proyecto con el estado de cuentas. En pruebas junto a Proyectos.':
      'The same plot and villa data, as cards per project with the account status. Under test alongside Projects.',
    'Que se puede construir: habitaciones, metros, precio, techos, extras y planos de cada tipo de vivienda.':
      'What can be built: rooms, square metres, price, roof types, add-ons and floor plans for each house model.',
    'Fase, fecha de entrega y fotos de cada unidad — lo que ve el comprador en su portal.':
      'Stage, handover date and photos for each unit — what the buyer sees in their portal.',
    'Ficha del comprador y documentación KYC, con caducidades.':
      'Buyer record and KYC documents, with expiry dates.',
    'Quién entra, con qué rol y qué herramientas ve cada uno.':
      'Who logs in, with what role, and which tools each of them sees.',

    /* ---------- Operaciones (el seguimiento de cada venta) ----------
       «Operación» aquí es UNA VENTA con todo lo que cuelga de ella: contrato,
       facturas, firmas y obra. En inglés es «deal», no «operation». */
    'Buscar comprador, proyecto, operador o nº…': 'Search buyer, project, agent or no.…',
    'Tabla': 'Table',
    'Embudo': 'Funnel',
    'Operador': 'Agent',
    'Precio': 'Price',
    'Precio pactado': 'Agreed price',
    'Situación': 'Where it stands',
    'Firmadas': 'Signed',
    'Con pendiente': 'With balance',
    'Firma enviada': 'Signature sent',
    'Sin facturar': 'Not invoiced',
    'Falta ficha': 'Record missing',
    'Quitar los filtros': 'Clear the filters',
    'Nada aquí': 'Nothing here',
    'Esta vista no lo está sumando todo: hay más de %l, y solo se han leído los más recientes. Los totales de abajo son parciales.':
      'This view is not adding everything up: there are more than %l, and only the most recent were read. The totals below are partial.',
    'y más de': 'and more than',
    'Contratos y facturación de esta venta, juntos.': 'Contracts and invoicing for this sale, together.',
    'Contratos de la operación': 'Contracts on this deal',
    'Documentos de la operación': 'Documents on this deal',
    'Documentación del comprador': 'Buyer documentation',
    'Hito de pago': 'Payment milestone',
    'Cargando los hitos de pago…': 'Loading the payment milestones…',
    'El contrato no fijó hitos de pago.': 'The contract set no payment milestones.',
    'No se pudieron cargar los hitos de pago:': 'Could not load the payment milestones:',
    'sin importe': 'no amount',
    'sin fijar': 'not set',
    'no calculable': 'cannot be calculated',
    'Sin precio total en el contrato no se puede calcular el pendiente ni convertir los hitos en %. Se rellena en Contratos.':
      'Without a total price on the contract, the balance cannot be calculated nor the milestones turned into %. It is filled in under Contracts.',
    'No suma': 'Not counted',
    'No cuenta %l — una Carta de Reserva declara el mismo importe que luego reparten el Bloqueo y la Construcción.':
      'Excludes %l — a Reservation Letter declares the same amount that the Plot Block and the Construction contract later split.',
    'Facturación': 'Invoicing',
    'Solo el recibí cuenta como cobrado — una factura o una proforma son lo que se debe, no lo pagado.':
      'Only the receipt counts as collected — an invoice or a proforma is what is owed, not what was paid.',
    'Cobros — documentos con vencimiento': 'Collections — documents with a due date',
    'Solo salen las que llevan vencimiento Y todavía tienen algo pendiente; es un campo opcional en Facturas, y una factura ya saldada por recibí no reclama nada.':
      'Only those with a due date AND something still outstanding appear; it is an optional field in Invoices, and an invoice already settled by a receipt claims nothing.',
    'Ninguna factura con vencimiento tiene algo pendiente de cobrar.':
      'No invoice with a due date has anything left to collect.',
    'Firmas': 'Signatures',
    'Firmas — enlaces pendientes': 'Signatures — pending links',
    'Firmante': 'Signer',
    'No hay enlaces de firma pendientes.': 'There are no pending signature links.',
    'No se ha enviado a firma remota.': 'It has not been sent for remote signing.',
    'Un enlace caducado no se recupera: se genera otro desde Contratos.':
      'An expired link cannot be recovered: generate another one from Contracts.',
    'Caduca': 'Expires',
    'Caducado': 'Expired',
    'Anulado': 'Voided',
    'Clase': 'Kind',
    'De': 'From',
    'Vía': 'Via',
    'Quién': 'Who',
    'Aviso': 'Notice',
    'Subido': 'Uploaded',
    'borrador': 'draft',
    'Ver documento': 'View document',
    'Ver PDF firmado': 'View signed PDF',
    'PDF firmado': 'Signed PDF',
    'Abrir en Contratos': 'Open in Contracts',
    'No se pudo abrir el PDF:': 'Could not open the PDF:',
    'Ese contrato ya no existe': 'That contract no longer exists',
    'Datos actualizados': 'Data updated',
    'El pasaporte y el KYC son de la': 'The passport and the KYC belong to the',
    ', no de una venta: salen en todas sus operaciones. Se suben desde':
      ', not to a sale: they show up on all of their deals. They are uploaded from',
    'Ningún documento subido todavía para este comprador.': 'No document uploaded yet for this buyer.',
    'Ningún documento subido todavía para estos compradores.': 'No document uploaded yet for these buyers.',
    'Sin ficha de comprador enlazada no hay documentación que mostrar.':
      'With no buyer record linked there is no documentation to show.',
    'Pulsa un nombre para abrir su ficha y su documentación.':
      'Click a name to open their record and their documents.',
    'Pulsa un número de contrato para ver su operación completa.':
      'Click a contract number to see the whole deal.',
    'Sus otros contratos': 'Their other contracts',
    'Adquiriente': 'Buyer',
    'sin pasaporte': 'no passport',
    'siempre que el comprador tenga pasaporte o email.': 'as long as the buyer has a passport or an email.',
    '(abierta)': '(open)',
    'firmado y bloqueado': 'signed and locked',
    'Borrar operación': 'Delete deal',
    'Borrar la operación': 'Delete the deal',
    'Borrar la operación de %c': 'Delete %c’s deal',
    'el contrato %n': 'contract %n',
    '%n enlace de firma quedará ANULADO': '%n signature link will be VOIDED',
    '%n enlaces de firma quedarán ANULADOS': '%n signature links will be VOIDED',
    '%n factura quedará ANULADA (no se borra: la serie no puede tener huecos)':
      '%n invoice will be VOIDED (not deleted: the series cannot have gaps)',
    '%n facturas quedarán ANULADAS (no se borran: la serie no puede tener huecos)':
      '%n invoices will be VOIDED (not deleted: the series cannot have gaps)',
    'La parcela vinculada vuelve a estar disponible.': 'The linked plot becomes available again.',
    'Operación borrada ·': 'Deal deleted ·',
    'No hay papelera.': 'There is no undo.',

    /* ---------- Compradores (ficha + KYC + portal del cliente) ---------- */
    'Buscar nombre, email o pasaporte…': 'Search name, email or passport…',
    'Contacto': 'Contact',
    'Nacionalidad': 'Nationality',
    'Pasaporte': 'Passport',
    'Docs.': 'Docs',
    'Identidad': 'Identity',
    'Tipo de comprador': 'Buyer type',
    'Persona física': 'Individual',
    'Empresa': 'Company',
    'Nombre completo': 'Full name',
    'Pasaporte / identificación fiscal': 'Passport / tax ID',
    'Pasaporte / NPWP': 'Passport / NPWP',
    'Domicilio': 'Address',
    'Fecha de nacimiento': 'Date of birth',
    'Razón social': 'Registered name',
    'País de constitución': 'Country of incorporation',
    'Identificación fiscal (NIF, NPWP, EIN…)': 'Tax ID (NIF, NPWP, EIN…)',
    'Domicilio social': 'Registered address',
    'Forma jurídica': 'Legal form',
    'Nº de registro mercantil': 'Company registration no.',
    'Representante legal': 'Legal representative',
    'Cargo del representante': 'Representative’s role',
    'Una empresa y su dueño pueden compartir correo: son dos fichas distintas y las dos son válidas.':
      'A company and its owner can share an email: they are two separate records and both are valid.',
    'Este correo es solo de contacto — cambiarlo NO cambia con qué email entra al portal. Eso se gestiona aparte, en «Portal del comprador» más abajo.':
      'This email is for contact only — changing it does NOT change which email they use to log in to the portal. That is handled separately, under “Buyer portal” below.',
    'Prefijo del país': 'Country code',
    'Estado KYC': 'KYC status',
    'Caduca el (opcional)': 'Expires on (optional)',
    'Fichero': 'File',
    'Elige un fichero': 'Choose a file',
    'El fichero supera los 20 MB': 'The file is over 20 MB',
    'Van a un bucket privado. Al abrirlos se genera un enlace temporal de 5 minutos, no una URL fija.':
      'They go to a private bucket. Opening one generates a temporary 5-minute link, not a fixed URL.',
    'Los documentos se suben después de crear la ficha.': 'Documents are uploaded after the record is created.',
    'Sin documentos todavía.': 'No documents yet.',
    'Documento subido': 'Document uploaded',
    'No se pudo subir:': 'Could not upload:',
    'No se pudieron leer los documentos:': 'Could not load the documents:',
    'Documento del comprador': 'Buyer document',
    'Se retira': 'Removing',
    'de la ficha, y su fichero del archivo privado.': 'from the record, and its file from the private archive.',
    'No hay papelera: si el documento sigue haciendo falta habrá que volver a subirlo.':
      'There is no undo: if the document is still needed it will have to be uploaded again.',
    'Retirar el documento': 'Remove the document',
    'Dejarlo': 'Leave it',
    'Retirando…': 'Removing…',
    'No se pudo retirar: ': 'Could not remove: ',
    'No se ha retirado: tu usuario no tiene permiso para borrar documentos.':
      'Not removed: your account has no permission to delete documents.',
    'Documento retirado de la ficha, pero su fichero sigue en el archivo (':
      'Document removed from the record, but its file is still in the archive (',
    'No se han retirado': 'Not removed',
    'Borrar la ficha de %c': 'Delete %c’s record',
    'este comprador': 'this buyer',
    'y sus': 'and its',
    '%n documento KYC': '%n KYC document',
    '%n documentos KYC': '%n KYC documents',
    'del archivo privado': 'from the private archive',
    'y te dice cuál — esta acción es para': 'and tells you which — this action is for',
    'duplicados sueltos': 'stray duplicates',
    'Borrar la ficha': 'Delete the record',
    'Borrando…': 'Deleting…',
    'Borrar comprador': 'Delete buyer',
    'Ficha borrada, pero': 'Record deleted, but',
    'Ese comprador ya no existe': 'That buyer no longer exists',
    'Ficha de': 'Record of',
    'Ficha actualizada': 'Record updated',
    'Comprador creado': 'Buyer created',
    'Crear comprador': 'Create buyer',
    'Guardando…': 'Saving…',
    'Subiendo…': 'Uploading…',
    'Subir documento': 'Upload document',
    'Falta el nombre': 'The name is missing',
    'Falta el email de acceso': 'The login email is missing',
    'Tu sesión ha caducado a mitad de guardar. Recarga la página, entra de nuevo y repite el cambio — no se ha guardado.':
      'Your session expired mid-save. Reload the page, log in again and redo the change — nothing was saved.',
    'Solo un administrador puede editar estos datos. Puedes consultarlos y gestionar la documentación de más abajo.':
      'Only an administrator can edit these details. You can read them and manage the documents below.',
    'Puedes editar los datos de la ficha': 'You can edit the record’s details',
    'Estado de cuentas': 'Account status',
    'Contratos firmados': 'Signed contracts',
    'Contrato · unidad': 'Contract · unit',
    'Avance de pago por proyecto': 'Payment progress by project',
    'Solo cuenta como cobrado el recibí — una factura o proforma es lo que se debe, no lo pagado.':
      'Only the receipt counts as collected — an invoice or proforma is what is owed, not what was paid.',
    'Ninguna factura emitida todavía en sus contratos.': 'No invoice issued yet on their contracts.',
    'Ninguna vigente: todas sus facturas están anuladas.': 'None live: all their invoices are voided.',
    'Ninguno enlazado todavía. El enlace se crea solo al guardar un contrato con su pasaporte o su email.':
      'None linked yet. The link is created automatically when a contract is saved with their passport or their email.',
    'Sin contrato enlazado todavía.': 'No contract linked yet.',
    'Sin contrato enlazado todavía, no hay a qué factura atarla.':
      'No contract linked yet, so there is nothing to attach an invoice to.',
    'Crear contrato': 'Create contract',
    'No se pudieron leer las facturas:': 'Could not load the invoices:',
    'No se pudo leer la cuota de reserva:': 'Could not read the reservation fee:',
    'Registro de envíos': 'Send log',
    'No se pudo leer el registro de envíos:': 'Could not read the send log:',
    'Sin correos registrados para sus contratos y facturas. El registro existe desde el 18-ago-2026: los envíos anteriores no dejaron rastro.':
      'No emails logged for their contracts and invoices. The log exists since 18 Aug 2026: earlier sends left no trace.',
    'Para': 'To',
    'Sin mensajes desde el área de clientes.': 'No messages from the client area.',
    'No se pudo leer Soporte:': 'Could not read Support:',
    'Todo resuelto': 'All resolved',
    '%n abierto': '%n open',
    '%n abiertos': '%n open',
    'Portal del comprador': 'Buyer portal',
    'Email de acceso': 'Login email',
    'correo de acceso': 'login email',
    'correo en la ficha': 'email on the record',
    'Acceso activo para': 'Active access for',
    '. Ve sus contratos, pagos, facturas y obra en /portal/.':
      '. They can see their contracts, payments, invoices and construction at /portal/.',
    'Sin acceso todavía. La entrada automática pide': 'No access yet. Automatic entry requires',
    'al menos un contrato': 'at least one contract',
    'o para darle acceso': 'or, to grant access',
    'con otro correo': 'with a different email',
    'Invitar al portal': 'Invite to the portal',
    'Reenviar enlace': 'Resend link',
    'Invitar a %e al portal': 'Invite %e to the portal',
    'Se le envía un': 'They are sent a',
    'y podrá ver en el portal todo lo de esta ficha: contratos, pagos, facturas y obra.':
      'and will be able to see everything on this record in the portal: contracts, payments, invoices and construction.',
    'Enviar la invitación': 'Send the invitation',
    'Invitación enviada': 'Invitation sent',
    'Acceso creado, pero el correo no salió: reenvía en un rato':
      'Access created, but the email did not go out: resend in a while',
    'Ponerle contraseña': 'Set a password',
    'Apúntala: no se puede volver a consultar, solo cambiar por otra.':
      'Write it down: it cannot be looked up again, only replaced.',
    'Contraseña puesta. Pásasela tú: no queda guardada en ningún sitio consultable.':
      'Password set. Hand it over yourself: it is not stored anywhere you can look it up.',
    'Revocar acceso': 'Revoke access',
    'Revocar el acceso': 'Revoke the access',
    'Revocar el acceso de %e': 'Revoke %e’s access',
    'Dejará de ver': 'They will stop seeing',
    'las fichas vinculadas a ese email, no solo ésta.': 'the records linked to that email, not just this one.',
    '. Se puede volver a invitar desde aquí — mientras haya una fila revocada, la entrada automática NO se la devuelve.':
      '. You can invite them again from here — while a revoked row exists, automatic entry will NOT give it back.',
    'Acceso revocado': 'Access revoked',
    'Invitar o revocar lo hace un administrador.': 'Inviting or revoking is done by an administrator.',
    'No se pudieron leer los accesos al portal:': 'Could not read the portal accounts:',
    'No se pudo generar el enlace': 'Could not generate the link',
    'mandarle el enlace ahora': 'send them the link now',
    'Entra': 'Logs in',
    'sin caducidad': 'no expiry',
    'sin estrenar': 'never used',

    /* ---------- Proyectos (inventario de parcelas y villas) ---------- */
    'Buscar código, proyecto o modelo…': 'Search code, project or model…',
    'Rejilla': 'Grid',
    'Carpetas': 'Folders',
    'Todavía no hay proyectos': 'No projects yet',
    'Da de alta uno con «+ Nuevo proyecto», arriba.': 'Create one with “+ New project”, above.',
    'Créala con «+ Nueva unidad», o cárgalas de la tabla de precios del proyecto.':
      'Create one with “+ New unit”, or load them from the project’s price table.',
    'sin modelo': 'no model',
    'Sin modelo decidido': 'No model chosen',
    'sin decidir': 'undecided',
    'Zona': 'Zone',
    '%n documento': '%n document',
    '%n documentos': '%n documents',
    'sin documentación': 'no documents',
    'Ficha del proyecto': 'Project record',
    'Resort': 'Resort',
    'Parcela máster (código)': 'Master plot (code)',
    'Ej. Balian Hills': 'e.g. Balian Hills',
    'Ej. W5': 'e.g. W5',
    'Ej. A12': 'e.g. A12',
    'Dune, Dream…': 'Dune, Dream…',
    'La ficha sí, los modelos no:': 'The record yes, the models no:',
    'no se tocan desde aquí': 'are not edited from here',
    'Para cambiar el': 'To change the',
    'del proyecto usa «Renombrar…» abajo — es otra operación, porque esa sí se propaga a unidades, contratos, facturas… y estos tres campos no.':
      'of the project use “Rename…” below — that is a different operation, because it does propagate to units, contracts, invoices… and these three fields do not.',
    'No tienes permiso para editar la ficha del proyecto (solo admin).':
      'You do not have permission to edit the project record (admins only).',
    'Qué se puede construir aquí': 'What can be built here',
    'de catálogo': 'catalogue',
    'lo usa %n parcela, no se puede retirar': 'used by %n plot, cannot be removed',
    'lo usan %n parcelas, no se puede retirar': 'used by %n plots, cannot be removed',
    'El catálogo de modelos está vacío o no tienes permiso para leerlo.':
      'The model catalogue is empty, or you have no permission to read it.',
    'Solo un administrador puede cambiar esta lista.': 'Only an administrator can change this list.',
    'Este proyecto no tiene modelos declarados, así que se ofrece el catálogo entero. Para acotarlo, «Qué se puede construir aquí» en la ficha del proyecto.':
      'This project has no models declared, so the whole catalogue is offered. To narrow it down, use “What can be built here” in the project record.',
    'Sales manager / Project manager de este proyecto': 'Sales manager / Project manager for this project',
    'A quien marques aquí es el': 'Whoever you tick here is the',
    '(su parte del contrato)': '(their side of the contract)',
    'Si este proyecto aparece en': 'If this project also appears under',
    ', que es en qué proyectos puede crear contratos él mismo: un encargado de este proyecto no tiene por qué vender aquí, y viceversa.':
      ', which is which projects they can create contracts in themselves: someone in charge of this project need not sell here, and vice versa.',
    'Todavía no hay ningún sales manager ni project manager dado de alta. Se crean desde':
      'No sales manager or project manager exists yet. They are created from',
    'Solo un administrador con la herramienta «usuarios» puede asignar managers.':
      'Only an administrator with the “users” tool can assign managers.',
    'desactivado': 'deactivated',
    'Renombrar…': 'Rename…',
    'Se actualizará en: %r.': 'It will be updated in: %r.',
    'No hay nada vinculado a este nombre todavía.': 'Nothing is linked to this name yet.',
    'Escribe un nombre': 'Type a name',
    'Proyecto renombrado': 'Project renamed',
    'No se pudo renombrar:': 'Could not rename:',
    'No se pudo actualizar el proyecto de:': 'Could not update the project of:',
    'Proyecto creado:': 'Project created:',
    'Nombre del proyecto nuevo:': 'Name of the new project:',
    'Borrar el proyecto': 'Delete the project',
    'Borrar el proyecto «%p» del catálogo': 'Delete the project “%p” from the catalogue',
    'Solo se puede si no tiene unidades, modelos de villa ni documentos subidos. Si tiene algo, el sistema lo rechaza y dice qué queda por vaciar.':
      'Only possible if it has no units, villa models or uploaded documents. If it has any, the system refuses and says what is left to clear.',
    'Proyecto borrado': 'Project deleted',
    'Nueva unidad': 'New unit',
    'Crear unidad': 'Create unit',
    'Unidad creada': 'Unit created',
    'El código es el mismo texto que imprime el contrato.': 'The code is the same text the contract prints.',
    'Debe coincidir con el que se escribe en el contrato: es lo que permite cruzarlos.':
      'It must match the one written on the contract: that is what lets them be cross-referenced.',
    'El código no puede quedar vacío': 'The code cannot be empty',
    'Ya hay una unidad con ese código en ese proyecto.': 'There is already a unit with that code in that project.',
    'no tienes permiso para guardar unidades': 'you have no permission to save units',
    'Elige un proyecto (o da uno de alta con «+ Nuevo proyecto…»)':
      'Choose a project (or create one with “+ New project…”)',
    '+ Nuevo proyecto…': '+ New project…',
    '+ Nuevo tipo…': '+ New type…',
    'Da de alta el tipo nuevo antes de guardar': 'Create the new type before saving',
    'Nombre del proyecto': 'Project name',
    'Nombre del tipo': 'Type name',
    'Modelo': 'Model',
    'Modelo de villa': 'Villa model',
    'Fase (masterplan)': 'Phase (masterplan)',
    'Superficie (m²)': 'Area (m²)',
    'Superficie bruta (m²)': 'Gross area (m²)',
    'Precio por m²': 'Price per m²',
    'Con la superficie, calcula el suelo solo': 'With the area, it works out the land price itself',
    'Desglose de precio': 'Price breakdown',
    'Precio de suelo': 'Land price',
    'Precio de construcción': 'Construction price',
    'Precio total': 'Total price',
    'Suelo': 'Land',
    'Precio según el modelo': 'Price from the model',
    'Precio recalculado para': 'Price recalculated for',
    'Lo que cambia entre modelos es la construcción; el suelo es de la parcela.':
      'What changes between models is the construction; the land belongs to the plot.',
    'el suelo (%s) es lo único fijo.': 'the land (%s) is the only fixed part.',
    'Sin modelo: la construcción y el total quedan sin fijar':
      'No model: construction and total are left unset',
    'El total no cuadra con suelo + construcción. Revisa cuál de los tres es el bueno.':
      'The total does not match land + construction. Check which of the three is right.',
    'Contrato asociado': 'Linked contract',
    'Operación': 'Deal',
    'Cobrado de esta unidad': 'Collected on this unit',
    '— elegir —': '— choose —',
    '— sin contrato —': '— no contract —',
    '— sin decidir —': '— undecided —',
    '· del catálogo': '· from the catalogue',
    '· elegido': '· chosen',
    'sin precio': 'no price',
    'sin código': 'no code',
    'Marcada como %e pero sin contrato asociado: no se podrá saber de quién es.':
      'Marked as %e but with no contract linked: there will be no way to know whose it is.',
    'Ese contrato ya está asociado a %u. Si no es una operación de varias unidades, revísalo.':
      'That contract is already linked to %u. Unless this is a multi-unit deal, check it.',
    'El estado lo lleva el contrato y el dinero, no una persona: una Carta de Reserva deja la parcela':
      'The status is driven by the contract and the money, not by a person: a Reservation Letter leaves the plot',
    '(firmarla no la mueve); un Bloqueo de Parcela firmado la deja':
      '(signing it does not move it); a signed Plot Block leaves it',
    '; el primer recibí real la pasa a': '; the first real receipt moves it to',
    ', y el 100% cobrado a': ', and 100% collected to',
    '. Si se le quita la parcela al contrato o se borra, vuelve a disponible sola.':
      '. If the plot is unlinked from the contract, or the contract is deleted, it goes back to available on its own.',
    'Esta parcela está vinculada a un contrato, así que su estado y su contrato':
      'This plot is linked to a contract, so its status and its contract',
    'no se actualiza solo': 'does not update on its own',
    'y hay que tocarlo a mano.': 'and has to be set by hand.',
    ': los lleva el contrato. Para soltarla, quítale la parcela al contrato o bórralo, y volverá a estar disponible sola.':
      ': the contract drives them. To free it, unlink the plot from the contract or delete it, and it will become available again on its own.',
    'Borrar la parcela': 'Delete the plot',
    'Borrar la parcela «%c»': 'Delete plot “%c”',
    'Solo se puede si no tiene un contrato ni fotos de obra colgando. Si tiene algo, el sistema lo rechaza y dice qué queda por soltar.':
      'Only possible if it has no contract and no construction photos attached. If it has any, the system refuses and says what is left to free.',
    'No se puede deshacer desde aquí.': 'It cannot be undone from here.',
    'Parcela borrada': 'Plot deleted',
    'Importar CSV': 'Import CSV',
    'Importar unidades desde CSV': 'Import units from CSV',
    'Leyendo…': 'Reading…',
    'Fila': 'Row',
    'filas leídas': 'rows read',
    'actualizan una unidad existente': 'update an existing unit',
    'con error, no se importan': 'with an error, not imported',
    'Alta nueva': 'New entry',
    'Actualiza': 'Updates',
    'Confirmar importación': 'Confirm import',
    'Confirmar importación (%n)': 'Confirm import (%n)',
    'Nada que importar': 'Nothing to import',
    'Importando…': 'Importing…',
    'Añadido': 'Added',


    /* ---------- KYC y documentos del comprador: un solo juego de rótulos ----------
       Los usan Operaciones y Compradores, cada uno con su mapa, y las claves
       (`pending`, `passport`, `proof_of_funds`…) son las de la base. */
    'En revisión': 'Under review',
    'Aprobado': 'Approved',
    'Rechazado': 'Rejected',
    'Visado': 'Visa',
    'Justificante de fondos': 'Proof of funds',
    'Justificante de domicilio': 'Proof of address',
    'Documento': 'Document',

    /* ---------- Portal del comprador: los motivos que devuelve la edge ---------- */
    'Ese correo ya es de un usuario del equipo. Una misma cuenta no puede ser del equipo y del portal a la vez.':
      'That email already belongs to a team user. One account cannot be both team and portal.',
    'Para probar el portal, usa otro correo (con Gmail vale tucorreo+portal@gmail.com: llega al mismo buzón y cuenta como distinto).':
      'To test the portal, use another email (with Gmail, youraddress+portal@gmail.com works: it lands in the same inbox and counts as different).',
    'Ese correo no tiene una forma válida.': 'That email is not a valid address.',
    'No se ha podido saber a qué ficha dar acceso. Recarga la página e inténtalo otra vez.':
      'Could not tell which record to grant access to. Reload the page and try again.',
    'Hace falta ser administrador para invitar o revocar accesos.':
      'You must be an administrator to invite or revoke access.',
    'La contraseña necesita 10 caracteres o más.': 'The password needs 10 characters or more.',
    'Ese email no tiene acceso al portal todavía — invítalo primero.':
      'That email has no portal access yet — invite them first.',


    'Desactivado': 'Deactivated',
    'Alcance': 'Scope',


    /* ---------- Facturas, proformas y recibís ----------
       VOCABULARIO, y conviene que no se mueva de aquí:
         factura  = invoice     (lo que se debe, con su serie INV)
         proforma = proforma    (informativa: anuncia el total, no factura)
         recibí   = receipt     (dinero que YA ha entrado, serie REC)
       El error caro de esta herramienta fue sumar las tres como si fueran lo
       mismo; que en inglés se llamen distinto es parte de que no vuelva a
       pasar. «Recibí» NUNCA es «received»: es el documento. */
    'Nuevo documento': 'New document',
    'Nueva factura': 'New invoice',
    'Crear recibí': 'Create receipt',
    'Factura proforma': 'Proforma invoice',
    'Tipo de documento': 'Document type',
    'Cada tipo lleva su propia serie: INV, PRO, REC': 'Each type has its own series: INV, PRO, REC',
    'Buscar nº, cliente, proyecto o contrato…': 'Search no., client, project or contract…',
    'Vigentes': 'Live',
    'Con anuladas': 'Including voided',
    'Lista': 'List',
    'Por contrato': 'By contract',
    'Nº de documento': 'Document no.',
    'Lo asigna la base al guardar': 'The database assigns it on save',
    'Fechas': 'Dates',
    'Fecha de emisión': 'Issue date',
    'Vencimiento (opcional)': 'Due date (optional)',
    'Emisor': 'Issuer',
    'Sociedad que factura': 'Invoicing company',
    'Cuenta donde se cobra': 'Account to be paid into',
    'Sin cuenta, el documento no imprime datos bancarios.':
      'With no account, the document prints no bank details.',
    'Otros — escribir la cuenta a mano': 'Other — type the account by hand',
    '— sin datos bancarios —': '— no bank details —',
    'Titular · Holder': 'Titular · Holder',
    'Banco · Bank': 'Banco · Bank',
    'Cuenta · Account': 'Cuenta · Account',
    'Swift / Routing': 'Swift / Routing',
    'Dirección del banco · Address': 'Dirección del banco · Address',
    'Nota · Note (opcional)': 'Nota · Note (optional)',
    'Si esta cuenta se va a repetir, pídenos darla de alta en la lista.':
      'If this account is going to come up again, ask us to add it to the list.',
    'Nombre o razón social': 'Name or registered name',
    'Pasaporte / NPWP / NIF': 'Passport / NPWP / tax ID',
    'Proyecto / unidad': 'Project / unit',
    'Ej. Palm Field — Cabana 2BR S2': 'e.g. Palm Field — Cabana 2BR S2',
    'Ábrelo para traer los datos de la ficha.': 'Open it to pull in the details from the record.',
    'Conceptos': 'Line items',
    '+ Añadir concepto': '+ Add line item',
    '+ Añadir otra factura': '+ Add another invoice',
    'Lo que se ha cobrado': 'What has been collected',
    'Importe cobrado': 'Amount collected',
    'Justificante de pago (obligatorio)': 'Proof of payment (required)',
    'Adjunta el justificante de pago': 'Attach the proof of payment',
    'Sin justificante': 'No proof of payment',
    'Un recibí admite hasta 8 justificantes (ya lleva ': 'A receipt takes up to 8 proofs of payment (it already has ',
    'Etiqueta': 'Label',
    'Ej. PPN': 'e.g. PPN',
    'Porcentaje': 'Percentage',
    'Ej. 11': 'e.g. 11',
    'En blanco, el documento no lleva impuesto.': 'Left blank, the document carries no tax.',
    'Condiciones de pago, referencia de transferencia…': 'Payment terms, transfer reference…',
    'Vista previa': 'Preview',
    'Asunto': 'Subject',
    '— elige un contrato —': '— choose a contract —',
    'Sin contrato': 'No contract',
    'Cargando contrato…': 'Loading contract…',
    'Elige el contrato al que corresponde este documento': 'Choose the contract this document belongs to',
    'Ese contrato no tiene hitos de pago que traer': 'That contract has no payment milestones to pull in',
    'De este contrato hay': 'On this contract there are',
    'Facturado': 'Invoiced',
    'Sin hitos facturados': 'No milestones invoiced',
    'Cobrado sin factura': 'Collected without an invoice',
    'Sin recibí': 'No receipt',
    '· Cobrado': '· Collected',
    'Abre el listado una vez para ver aquí cuánto lleva cobrado este contrato.':
      'Open the list once to see here how much has been collected on this contract.',
    'Total del proyecto': 'Project total',
    'El proyecto se factura de una vez': 'The project is invoiced in one go',
    'Una sola factura por el importe completo, sin hitos': 'A single invoice for the full amount, no milestones',
    'Se factura el hito que se haya alcanzado.': 'The milestone that has been reached is invoiced.',
    'Lo que se le comunica al cliente. Informativo: no factura ni vence':
      'What the client is told. Informational: it does not invoice and does not fall due',
    'Proforma precargada con el total del proyecto': 'Proforma preloaded with the project total',
    'Conceptos vaciados: el total del proyecto es de la proforma, no de una factura':
      'Line items cleared: the project total belongs on the proforma, not on an invoice',
    'El documento ya tiene conceptos. Poner': 'The document already has line items. Setting',
    'Sustituye los conceptos por': 'Replace the line items with',
    'los reemplaza por una sola línea con el importe completo.':
      'replaces them with a single line for the full amount.',
    'Toda la unidad · los dos contratos': 'The whole unit · both contracts',
    'Todo el contrato': 'The whole contract',
    'todo el contrato': 'the whole contract',
    'La venta está en dos contratos:': 'The sale sits across two contracts:',
    ': el precio total de cada uno de los dos contratos.': ': the total price of each of the two contracts.',
    'Dos líneas y no una a propósito: son dos relaciones jurídicas con el mismo comprador, y fundirlas borra a qué contrato corresponde cada euro.':
      'Two lines and not one, on purpose: they are two legal relationships with the same buyer, and merging them erases which contract each euro belongs to.',
    'dos líneas': 'two lines',
    'no son un contrato: no se suman entre sí': 'are not a contract: they do not add up together',
    'Se hace así a propósito: dejar los dos cobraría el total':
      'It is done this way on purpose: leaving both would charge the total',
    'Lo normal es': 'The usual thing is',
    'Quitad': 'Remove',
    'es el otro. Puedes cobrar los dos en este mismo documento.':
      'is the other. You can collect both on this same document.',
    '— pulsa para cobrarlo entero.': '— click to collect it in full.',
    'Factura por la unidad completa: ': 'Invoice for the whole unit: ',
    'Pero lo emite': 'But it is issued by',
    ', así que no se puede combinar en la misma factura: sería una sociedad cobrando el ingreso de otra.':
      ', so it cannot be combined on the same invoice: that would be one company collecting another’s income.',
    'Hay más de ': 'There are more than ',
    'Elige al menos una factura que salde este recibí': 'Choose at least one invoice this receipt settles',
    'Falta el importe aplicado a ': 'The amount applied to ',
    'Esa factura ya no tiene saldo pendiente, o está anulada — no hay nada que cobrar en un recibí.':
      'That invoice has no balance left, or is voided — there is nothing for a receipt to collect.',
    'Falta el nombre del cliente': 'The client’s name is missing',
    'El documento no tiene importe': 'The document has no amount',
    'Guardada como ': 'Saved as ',
    'El número': 'The number',
    'no se reutiliza': 'is not reused',
    'y ya no se podrá editar.': 'and it can no longer be edited.',
    'Factura ': 'Invoice ',
    'Factura anulada': 'Invoice voided',
    'Factura anulada: se abre como borrador nuevo': 'Invoice voided: it opens as a fresh draft',
    'La factura se queda en el registro marcada como anulada, así que el rastro no se pierde.':
      'The invoice stays in the record marked as voided, so the trail is not lost.',
    ': así queda el rastro y la serie no pierde un número.':
      ': that way the trail is kept and the series does not lose a number.',
    'Factura borrada': 'Invoice deleted',
    'Borrarla deja un': 'Deleting it leaves a',
    'hueco en la numeración': 'gap in the numbering',
    'que habrá que explicarle a un contable. No hay papelera.':
      'that will have to be explained to an accountant. There is no undo.',
    'No tienes permiso para borrar facturas': 'You do not have permission to delete invoices',
    'No se pudo anular: ': 'Could not void: ',
    'No se pudo anular: no es tuya o ya está anulada': 'Could not void: it is not yours, or it is already voided',
    'Esta factura ya está guardada, así que no se pierde. Se abre un recibí nuevo enganchado a ella.':
      'This invoice is already saved, so nothing is lost. A new receipt opens attached to it.',
    'Guarda la factura antes de crear un recibí desde ella': 'Save the invoice before creating a receipt from it',
    'El documento que tienes abierto ya está guardado, así que no se pierde. Se limpia el formulario para empezar otro.':
      'The document you have open is already saved, so nothing is lost. The form is cleared to start another.',
    'Guarda el documento antes de enviarlo': 'Save the document before sending it',
    'Guarda el documento para ver su registro': 'Save the document to see its log',
    'Sin correos registrados para este documento.': 'No emails logged for this document.',
    'Email de destinatario no válido': 'Invalid recipient email',
    'Enviada': 'Sent',
    'Enviado a ': 'Sent to ',
    'el hito, y el documento saldría creíble.': 'the milestone, and the document would come out looking plausible.',
    'Autor reasignado a ': 'Author reassigned to ',
    'No se encontró ese documento': 'That document was not found',
    'No se han podido cargar las cuentas de cobro: ': 'Could not load the collection accounts: ',
    'No se pudieron cargar las facturas abiertas: ': 'Could not load the open invoices: ',
    'No se pudo comprobar de quién son las facturas: ': 'Could not check whose the invoices are: ',
    'No se pudo cargar la lista de contratos: ': 'Could not load the contract list: ',
    'No se pudo abrir el justificante: ': 'Could not open the proof of payment: ',
    'No se pudo subir ': 'Could not upload ',
    'Error: ': 'Error: ',


    /* ---------- CRM de leads ----------
       Un «lead» es un lead en los dos idiomas: el equipo ya lo llama así y
       traducirlo a «prospect» solo añadiría una palabra que nadie usa.
       «Closer» y «Setter» igual. Lo que sí se traduce es todo lo demás. */
    'Mis leads': 'My leads',
    'Todo el equipo': 'Whole team',
    'Solo mías': 'Mine only',
    'tuyas': 'yours',
    'tú': 'you',
    'Lead': 'Lead',
    '%n lead': '%n lead',
    '%n leads': '%n leads',
    'Buscar por nombre, email o teléfono…': 'Search by name, email or phone…',
    'Buscar en la bandeja…': 'Search the inbox…',
    'Ningún lead con ese filtro.': 'No lead matches that filter.',
    'Todavía no ha entrado ningún lead.': 'No lead has come in yet.',
    'Todavía no ha entrado ningún lead, así que no hay campañas que configurar.':
      'No lead has come in yet, so there are no campaigns to configure.',
    /* las seis columnas del embudo */
    'Nuevo': 'New',
    'Acaba de entrar, nadie lo ha tocado': 'Just arrived, nobody has touched it',
    'Contactado': 'Contacted',
    'Se le ha escrito o llamado': 'They have been written to or called',
    'Visita': 'Visit',
    'Ha visto el terreno o la villa': 'They have seen the land or the villa',
    'Reserva': 'Reservation',
    'Carta de reserva firmada': 'Reservation letter signed',
    'Contrato de compraventa firmado': 'Sale contract signed',
    'Perdido': 'Lost',
    'No sigue adelante': 'Not going ahead',
    'Sin contactar': 'Not contacted',
    'Sin tocar': 'Untouched',
    'sin origen': 'no source',
    'Origen': 'Source',
    'Campaña': 'Campaign',
    '%n campañas': '%n campaigns',
    'todos los canales': 'all channels',
    'De un formulario de Meta a una tarjeta en el pipeline.':
      'From a Meta form to a card on the pipeline.',
    /* tarjeta y ficha del lead */
    'Sin dueño': 'Unowned',
    'Es mío': 'Mine',
    'Soltarlo': 'Release it',
    'Asignar': 'Assign',
    'Asignar a otra persona': 'Assign to someone else',
    'Pasárselo a': 'Hand it to',
    'Pasárselo a otra persona': 'Hand it to someone else',
    'Quién lo lleva': 'Who owns it',
    'Ya es tuyo.': 'It is yours now.',
    'Asignado a %q': 'Assigned to %q',
    'Lead devuelto al montón.': 'Lead returned to the pool.',
    'Nadie lo lleva todavía. Si lo coges, tus tareas y tu «mis leads» lo incluyen.':
      'Nobody owns it yet. If you take it, it joins your tasks and your “my leads”.',
    'Lo lleva otra persona. Para cambiarlo, habla con un administrador.':
      'Someone else owns it. To change that, talk to an administrator.',
    'Este lead está huérfano de hecho: conviene reasignarlo a alguien que lo trabaje.':
      'This lead is effectively orphaned: it should be reassigned to someone who will work it.',
    'Esa tarjeta la ha movido otra persona. Recargo la lista.':
      'Someone else moved that card. Reloading the list.',
    'Ese lead ha cambiado de manos mientras mirabas. Recargo.':
      'That lead changed hands while you were looking. Reloading.',
    'Ver contacto': 'View contact',
    'Acciones registradas': 'Logged actions',
    'Sin actuaciones registradas.': 'No actions logged.',
    'Última actividad': 'Last activity',
    'Última actuación': 'Last action',
    'Lo que han hecho': 'What they have done',
    'Qué hizo': 'What they did',
    'Cargando actividad…': 'Loading activity…',
    'Qué contestó en el formulario': 'What they answered on the form',
    'Presupuesto': 'Budget',
    'Cuándo compra': 'When they buy',
    'Para qué': 'What for',
    'Este lead no dejó email.': 'This lead left no email.',
    'Este lead no dejó ni email ni teléfono.': 'This lead left neither email nor phone.',
    'Queda registrado quién consulta los datos de contacto y cuándo.':
      'Who looks up contact details, and when, is logged.',
    'Nombre del lead': 'Lead name',
    'Teléfono del lead': 'Lead phone',
    'Notas del equipo': 'Team notes',
    'Notas del bot': 'Bot notes',
    'Añadir nota': 'Add note',
    'Sin notas.': 'No notes.',
    'No se pudo guardar la nota: ': 'Could not save the note: ',
    'Etiquetas': 'Tags',
    'Objeciones': 'Objections',
    'Por qué': 'Why',
    'Próximo paso': 'Next step',
    'Poner próximo paso': 'Set next step',
    'Próximo paso guardado.': 'Next step saved.',
    'Qué hay que hacer': 'What needs doing',
    'Escribe qué hay que hacer.': 'Write what needs doing.',
    'Falta la fecha.': 'The date is missing.',
    'Hecho': 'Done',
    'Hecho. Pon el siguiente paso cuando lo tengas.': 'Done. Set the next step when you have it.',
    'Lo que toca hoy': 'What is due today',
    'Para hoy': 'For today',
    'Con retraso': 'Overdue',
    'deberían estar hechas': 'should already be done',
    'de todo el equipo': 'of the whole team',
    'Prueba a mirar las de todo el equipo.': 'Try looking at the whole team’s.',
    'El próximo paso se pone desde la ficha de cada lead.':
      'The next step is set from each lead’s record.',
    'Vencidas y de hoy. El próximo paso de cada lead se pone desde su ficha.':
      'Overdue and due today. Each lead’s next step is set from its record.',
    '%n día de retraso': '%n day late',
    '%n días de retraso': '%n days late',
    'Abrir ficha': 'Open record',
    'Abrir el contrato': 'Open the contract',
    'hoy': 'today',
    'ayer': 'yesterday',
    'mañana': 'tomorrow',
    'Hoy': 'Today',
    'Mañana': 'Tomorrow',
    'En 3 días': 'In 3 days',
    'En una semana': 'In a week',
    '7 días': '7 days',
    'en %n días': 'in %n days',
    '%n días': '%n days',
    /* alcance y avisos */
    'Todavía no tienes ninguna campaña asignada.': 'You have no campaign assigned yet.',
    'aparece vacía: verás los leads en cuanto dirección te asigne una. No es un fallo de la herramienta.':
      'looks empty: you will see leads as soon as management assigns you one. It is not a fault in the tool.',
    'Ves los leads de tu campaña': 'You see the leads from your campaign',
    'Ves los leads de tus %n campañas': 'You see the leads from your %n campaigns',
    'Los de otras campañas los llevan otras personas.': 'The ones from other campaigns are owned by other people.',
    'Hay tipos de contrato sin columna asignada.': 'There are contract types with no column assigned.',
    'no aparecerá sugerido en Reserva ni en Contrato: ':
      'will not be suggested under Reservation or Contract: ',
    'Se arregla desde el estudio, añadiendo su fila en':
      'It is fixed from the studio, by adding its row in',
    'han firmado y siguen en otra columna': 'have signed and are still in another column',
    'Reserva o contrato': 'Reservation or contract',
    'Este lead está enlazado a su contrato de verdad, no por parecido de correo.':
      'This lead is linked to its real contract, not by a similar-looking email.',
    'Crear contrato para este lead': 'Create a contract for this lead',
    'Se abre su ficha de comprador (con los datos que dejó él) y de ahí el contrato.':
      'Their buyer record opens (with the details they left) and the contract from there.',
    'Una ficha de comprador necesita un identificador, así que hay que darla de alta a mano en':
      'A buyer record needs an identifier, so it has to be created by hand in',
    'Ya existe una ficha con ese correo: ': 'A record with that email already exists: ',
    'No se pudieron leer los leads: ': 'Could not load the leads: ',
    'No se pudo abrir la ficha.': 'Could not open the record.',
    'No se pudo abrir la ficha: ': 'Could not open the record: ',
    'No se pudo leer el lead.': 'Could not read the lead.',
    'No se pudo leer el contacto.': 'Could not read the contact details.',
    'No se pudo leer la actividad.': 'Could not read the activity.',
    'No se pudo leer la lista. Recarga la página.': 'Could not read the list. Reload the page.',
    'No se pudo leer.': 'Could not read it.',
    'No se pudo guardar el cambio: ': 'Could not save the change: ',
    'No se pudo cambiar el dueño: ': 'Could not change the owner: ',
    /* bandeja del bot de WhatsApp */
    'Conversaciones': 'Conversations',
    'Conversaciones del bot': 'Bot conversations',
    'con el bot de WhatsApp': 'with the WhatsApp bot',
    'Los mensajes del bot con cada lead, tal y como los ve el cliente.':
      'The bot’s messages with each lead, exactly as the client sees them.',
    'El bot de WhatsApp de Lawang, en vivo. Pausar detiene la IA para ese lead: a partir de ahí responde una persona.':
      'Lawang’s WhatsApp bot, live. Pausing stops the AI for that lead: from then on a person replies.',
    'Elige una conversación': 'Choose a conversation',
    'Sin conversaciones todavía.': 'No conversations yet.',
    'Sin mensajes.': 'No messages.',
    'No se pudo leer la conversación.': 'Could not read the conversation.',
    'La IA está atendiendo esta conversación.': 'The AI is handling this conversation.',
    'Pausa la IA': 'Pause the AI',
    'Pausada': 'Paused',
    'En pausa': 'Paused',
    'IA pausada para ese lead.': 'AI paused for that lead.',
    'IA reanudada para ese lead.': 'AI resumed for that lead.',
    'El bot todavía no ha sacado datos de esta conversación.':
      'The bot has not extracted any data from this conversation yet.',
    'Baja (STOP)': 'Opted out (STOP)',
    'Este lead pidió la baja (STOP). El sistema no le enviará nada más, ni bot ni persona.':
      'This lead opted out (STOP). The system will send them nothing further, bot or person.',
    'Frenada (testing)': 'Held back (testing)',
    'en solo lectura': 'read-only',
    'Escribir': 'Write',
    'Respuesta del equipo': 'Team reply',
    'arriba si quieres contestar tú.': 'above if you want to reply yourself.',
    'Elige una plantilla…': 'Choose a template…',
    'Cargando plantillas…': 'Loading templates…',
    'No hay ninguna plantilla aprobada todavía': 'There is no approved template yet',
    'No se pudieron leer las plantillas': 'Could not read the templates',
    'Rellena todos los datos de la plantilla.': 'Fill in all the template’s fields.',
    'Plantilla enviada.': 'Template sent.',
    'Enviado.': 'Sent.',
    'Explorando': 'Exploring',
    'Interesado': 'Interested',
    'Quiere reservar': 'Wants to book',
    'Escalado': 'Escalated',
    'Intención': 'Intent',
    'País': 'Country',
    'Fecha de viaje': 'Travel date',
    'Primer contacto': 'First contact',
    'Seguimientos enviados': 'Follow-ups sent',
    /* agenda de cierre */
    'Citas': 'Appointments',
    'Citas agendadas': 'Appointments booked',
    '%n cita agendada': '%n appointment booked',
    '%n citas agendadas': '%n appointments booked',
    'Sin citas agendadas.': 'No appointments booked.',
    'Sin citas agendadas todavía.': 'No appointments booked yet.',
    'Ninguna agendada.': 'None booked.',
    'nada agendado por delante': 'nothing booked ahead',
    'Nueva cita': 'New appointment',
    'Agendar llamada': 'Book a call',
    'Agenda la llamada de venta de un lead con su closer.':
      'Book a lead’s sales call with their closer.',
    'Llamada': 'Call',
    'Llamada de venta': 'Sales call',
    'Llamada de venta (Fathom.ai)': 'Sales call (Fathom.ai)',
    'Próxima llamada': 'Next call',
    'Próximas llamadas': 'Upcoming calls',
    'Fecha y hora': 'Date and time',
    'Falta la fecha y hora.': 'The date and time are missing.',
    'Contexto para quien atienda la llamada': 'Context for whoever takes the call',
    'Cita agendada.': 'Appointment booked.',
    'Cita actualizada.': 'Appointment updated.',
    'Cita borrada.': 'Appointment deleted.',
    'Borrar esta cita': 'Delete this appointment',
    'Si tiene evento de Calendar, se borra también.': 'If it has a Calendar event, that is deleted too.',
    'Cancelar edición': 'Cancel editing',
    'No se pudieron leer las citas: ': 'Could not read the appointments: ',
    'No se pudo guardar la cita: ': 'Could not save the appointment: ',
    'Rellena la fecha y guarda: el teléfono y el nombre ya van puestos.':
      'Fill in the date and save: the phone and the name are already filled in.',
    'Con Meet listo': 'With Meet ready',
    'Por confirmar': 'To confirm',
    'sin enlace todavía': 'no link yet',
    'El enlace de Google Meet se genera solo en cuanto el estudio active el acceso de Google Workspace. Hasta entonces, la cita se agenda igual — el closer comparte su propio enlace con el lead.':
      'The Google Meet link is generated automatically as soon as the studio enables Google Workspace access. Until then, the appointment is booked all the same — the closer shares their own link with the lead.',
    'Ver grabación': 'View recording',
    'Sin llamadas registradas todavía.': 'No calls logged yet.',
    'Unirse': 'Join',
    /* ranking de closers */
    'A quién se atribuye cada venta': 'Who each sale is credited to',
    'Quién vende': 'Who sells',
    'Closer': 'Closer',
    'Comercial': 'Rep',
    'Comerciales': 'Reps',
    'Venta': 'Sale',
    'Ventas': 'Sales',
    'Ticket medio': 'Average ticket',
    'Conversión': 'Conversion',
    'Solo contratos raíz': 'Root contracts only',
    'Todo lo firmado': 'Everything signed',
    'Contando solo el contrato raíz de cada cadena. El puesto lo decide el dinero cobrado.':
      'Counting only the root contract of each chain. The ranking is decided by money collected.',
    'Contando todo lo firmado, cadenas incluidas. El puesto lo decide el dinero cobrado.':
      'Counting everything signed, chains included. The ranking is decided by money collected.',
    'de cadena': 'from a chain',
    'con al menos una venta atribuida': 'with at least one sale credited',
    'El ranking todavía no está completo.': 'The leaderboard is not complete yet.',
    'Todavía no hay ninguna venta atribuida.': 'No sale has been credited yet.',
    'Todas las ventas están atribuidas.': 'Every sale is credited.',
    'Sin atribuir': 'Unattributed',
    '— sin atribuir —': '— unattributed —',
    '%n venta sin atribuir': '%n sale unattributed',
    '%n ventas sin atribuir': '%n sales unattributed',
    '%n ventas firmadas en total': '%n signed sales in total',
    'Quién lo cerró': 'Who closed it',
    'Otra persona ha cambiado esa atribución. Recargo.':
      'Someone else changed that attribution. Reloading.',
    'Cambiar': 'Change',
    'leads con contrato firmado': 'leads with a signed contract',
    /* reparto de leads */
    'Quién atiende cada campaña': 'Who handles each campaign',
    'Reparto automático': 'Automatic routing',
    'Reparto automático encendido.': 'Automatic routing on.',
    'Reparto automático apagado.': 'Automatic routing off.',
    'Tope guardado.': 'Cap saved.',
    'Reparto encendido pero sin nadie asignado.': 'Routing on but nobody assigned.',
    'Sus leads se quedarán sin dueño.': 'Its leads will be left unowned.',
    'todas con reparto automático': 'all with automatic routing',
    '%n sin reparto automático': '%n without automatic routing',
    'Cargando el equipo…': 'Loading the team…',
    'No hay nadie más con acceso al CRM.': 'Nobody else has access to the CRM.',
    'nadie tiene acceso al CRM todavía': 'nobody has access to the CRM yet',
    'Un administrador tiene que marcar la casilla «Leads» en':
      'An administrator has to tick the “Leads” box in',
    'antes de poder repartir leads.': 'before leads can be routed.',
    'Esa cuenta está desactivada.': 'That account is deactivated.',
    'vacío = tú mismo': 'empty = yourself',
    'las lleva una persona': 'a person handles them',
    /* campañas */
    'Rendimiento por campaña': 'Performance by campaign',
    'Leads recibidos': 'Leads received',
    'Leads recibidos frente a lo invertido en Meta. El gasto lo trae el vigilante cada 4 h.':
      'Leads received against what was spent on Meta. The spend is brought in by the watchdog every 4 h.',
    'Leads y gasto, semana a semana': 'Leads and spend, week by week',
    'Invertido': 'Spent',
    'Clics': 'Clicks',
    'Coste por lead': 'Cost per lead',
    'Coste/lead': 'Cost/lead',
    'Aún no hay datos de campañas.': 'No campaign data yet.',
    'Todavía no hay cifras de gasto.': 'No spend figures yet.',
    'Sin datos todavía.': 'No data yet.',
    /* automatismos */
    'Reglas activas': 'Active rules',
    'El flujo': 'The flow',
    'se revisan cada 4 horas': 'checked every 4 hours',
    'las últimas que constan': 'the latest on record',
    'Hay': 'There are',
    'Ojo:': 'Careful:',
    'Comprobando…': 'Checking…',
    'Pidiendo…': 'Requesting…',
    '· Dirección': '· Address',
    '· WhatsApp Bot': '· WhatsApp Bot',
    'WhatsApp': 'WhatsApp',


    'Ya existe una ficha con ese correo:': 'A record with that email already exists:',
    'El lead': 'The lead',


    'Acceso~puerta': 'Sign in',
    'Soy del equipo': 'I am staff',
    'Soy cliente': 'I am a client',


    /* ---------- Contratos (el generador) ----------
       ⚠️ SOLO LA INTERFAZ. El TEXTO DEL DOCUMENTO no está aquí ni puede
       estarlo: su idioma lo decide `LANG` (ES/EN/ID guardado con cada
       contrato), no la preferencia de quien lo emite. En `app.html` esa
       frontera está marcada con `/* lwT:no-tocar *​/`. */
    'Contratos guardados': 'Saved contracts',
    'Buscar por número, comprador, proyecto o autor…': 'Search by number, buyer, project or author…',
    'Creado': 'Created',
    'Creado por': 'Created by',
    'Detalle': 'Detail',
    'Qué': 'What',
    'quién': 'who',
    'cuándo': 'when',
    'Copia': 'Copy',
    'Cobro': 'Billing',
    'Rastro': 'Trail',
    'Contrato ': 'Contract ',
    'Tipo de contrato desconocido': 'Unknown contract type',
    'Es de tipología': 'It is of type',
    'No tienes ningún tipo de contrato asignado. Pídeselo a un administrador antes de empezar.':
      'You have no contract type assigned. Ask an administrator for one before you start.',
    'Plantilla no encontrada.': 'Template not found.',
    'Supabase no disponible': 'Supabase unavailable',
    'No se pudo abrir el contrato': 'Could not open the contract',
    'Esa ficha de cliente ya no existe: empieza el contrato buscándolo':
      'That client record no longer exists: start the contract by searching for them',
    'Ese resultado no tiene ficha: elige un cliente registrado':
      'That result has no record: choose a registered client',
    'El comprador de un contrato sale de su ficha de': 'A contract’s buyer comes from their record in',
    'búscalo': 'find them',
    'Si ya está registrado,': 'If they are already registered,',
    'Pon el nombre del comprador': 'Enter the buyer’s name',
    'Pon un email válido del comprador': 'Enter a valid email for the buyer',
    'Ponle el email en «Adquirientes adicionales» y vuelve a intentarlo.':
      'Put their email under “Additional buyers” and try again.',
    'Estos compradores están escritos a mano y no salen de ninguna ficha:':
      'These buyers were typed by hand and come from no record:',
    ', pero el enlace que hay en la base apunta a otra ficha.':
      ', but the link in the database points to a different record.',
    'Contrato nuevo para ': 'New contract for ',
    'Contrato nuevo con los datos de ': 'New contract using the details of ',
    'Nuevo contrato con estos datos': 'New contract with these details',
    /* edición del texto de la plantilla */
    'Edición ON · reescribe el texto libre; lo resaltado en dorado son campos del formulario y no se toca aquí':
      'Editing ON · rewrite the free text; anything highlighted in gold is a form field and is not edited here',
    'Texto original restaurado': 'Original text restored',
    'Se pierden': 'You lose',
    'tus ediciones de texto': 'your text edits',
    'en esta plantilla. Los campos rellenos y las cláusulas no se tocan.':
      'on this template. Filled-in fields and clauses are untouched.',
    'OJO: ': 'CAREFUL: ',
    'Ese campo está vacío en este contrato — no hay nada que imprima todavía':
      'That field is empty on this contract — there is nothing it prints yet',
    'Los Artículos 2 y 3 remiten a los Apéndices (planos y especificaciones), así que el comprador firmaría un contrato que se refiere a documentos que no están.':
      'Articles 2 and 3 refer to the Appendices (plans and specifications), so the buyer would be signing a contract that points to documents that are not there.',
    'y no lleva anexos adjuntos.': 'and carries no attached annexes.',
    'Espera: se está preparando el anexo de ': 'Hold on: the annex is being prepared for ',
    /* guardar */
    'Contrato bloqueado, no se puede guardar': 'Contract locked, it cannot be saved',
    'Este contrato está enviado a firma: pulsa «Editar (anula la firma)» para poder guardarlo':
      'This contract has been sent for signing: click “Edit (voids the signature)” to be able to save it',
    'Elige a qué parcela pertenece esta Construcción antes de guardarla':
      'Choose which plot this Construction contract belongs to before saving it',
    'Elige el contrato al que acompaña este Poder Notarial antes de guardarlo':
      'Choose the contract this Power of Attorney goes with before saving it',
    'El poder se guarda, pero sin pasaporte ni email del otorgante no se puede saber qué contratos cubre':
      'The power of attorney is saved, but without the grantor’s passport or email there is no way to tell which contracts it covers',
    'Contrato guardado, pero la proforma automática no se pudo crear: ':
      'Contract saved, but the automatic proforma could not be created: ',
    'Guardado, pero no se pudo enlazar con su lead: ': 'Saved, but it could not be linked to its lead: ',
    'Guardado, pero no se pudo registrar el salto: ': 'Saved, but the override could not be logged: ',
    'Las facturas y las unidades': 'The invoices and the units',
    'se borran: se quedan sin el vínculo.': 'are not deleted: they are left without the link.',
    'Se van con él': 'They go with it',
    'sus firmas y sus compradores enlazados': 'its signatures and its linked buyers',
    'Fecha guardada en formato antiguo en: ': 'Date stored in the old format in: ',
    'No se han podido cargar los campos del formulario (': 'Could not load the form fields (',
    'No se han podido cargar los datos del apoderado: ': 'Could not load the attorney-in-fact’s details: ',
    'No se han podido cargar las credenciales del firmante: ': 'Could not load the signer’s credentials: ',
    /* firma electrónica */
    'Firma automática': 'Electronic signature',
    'Enviar a firma': 'Send for signing',
    'El comprador firma desde el enlace. El PDF firmado entra solo y bloquea el contrato.':
      'The buyer signs from the link. The signed PDF comes in by itself and locks the contract.',
    'Generar enlace de firma': 'Generate signing link',
    'Genera primero el enlace': 'Generate the link first',
    'Enlace de firma generado': 'Signing link generated',
    'Enlaces de firma': 'Signing links',
    'Enlace copiado': 'Link copied',
    'Copiar enlace': 'Copy link',
    'Caduca en 30 días.': 'Expires in 30 days.',
    'Expira / Firmado': 'Expires / Signed',
    'En cuanto firme el anterior,': 'As soon as the previous one signs,',
    'la cadena se parará ahí': 'the chain will stop there',
    'El contrato no tiene ningún firmante con nombre': 'The contract has no named signer',
    'Guarda el contrato antes de enviarlo a firma': 'Save the contract before sending it for signing',
    'Guarda el contrato antes de enviarlo': 'Save the contract before sending it',
    'Guarda el contrato antes de subir el firmado': 'Save the contract before uploading the signed copy',
    'Guarda el contrato para ver su registro': 'Save the contract to see its log',
    'Guarda primero: sin guardar no hay número, y el PDF saldría idéntico a uno emitido sin existir en la base.':
      'Save first: unsaved there is no number, and the PDF would look identical to one issued without existing in the database.',
    'No se pudo generar: ': 'Could not generate: ',
    'No se pudo generar el enlace de descarga': 'Could not generate the download link',
    'No se pudo comprobar si este contrato está enviado a firma':
      'Could not check whether this contract has been sent for signing',
    'No se pudo comprobar el estado de las firmas: ': 'Could not check the status of the signatures: ',
    'Este contrato ya no tiene firmas vivas': 'This contract no longer has live signatures',
    'Hay': 'There are',
    'La copia de lo que se firmó se conserva como prueba. No se borra nada.':
      'The copy of what was signed is kept as evidence. Nothing is deleted.',
    'Desmárcalo si todavía no habían recibido el enlace.': 'Untick it if they had not received the link yet.',
    'Ningún firmante tiene email en el contrato: no se puede avisar a nadie.':
      'No signer has an email on the contract: nobody can be notified.',
    'No se pudieron anular las firmas: ': 'Could not void the signatures: ',
    'Firmas anuladas · ya puedes editar': 'Signatures voided · you can edit now',
    'Aviso enviado a ': 'Notice sent to ',
    'Avisado': 'Notified',
    'Aviso:': 'Notice:',
    'Reabre el modal de firma': 'Reopen the signing dialog',
    'Este contrato está': 'This contract is',
    'firmado y cerrado': 'signed and closed',
    'Queda registrado en el historial del contrato:': 'It is recorded in the contract’s history:',
    'lo desbloqueó y': 'unlocked it and',
    'Como super admin': 'As a super admin',
    'No se pudo desbloquear: ': 'Could not unlock: ',
    'Contrato desbloqueado y registrado': 'Contract unlocked and logged',
    /* PDF firmado a mano */
    'El archivo debe ser un PDF': 'The file must be a PDF',
    'El PDF supera los 100MB': 'The PDF is over 100 MB',
    'No se pudo bloquear: ': 'Could not lock: ',
    'Contrato bloqueado · PDF firmado guardado': 'Contract locked · signed PDF saved',
    'Cerrado, pero no se pudieron anular los enlaces de firma vivos: ':
      'Closed, but the live signing links could not be voided: ',
    'Enlace(s) de firma pendientes anulados al cerrar': 'Pending signing link(s) voided on closing',
    'Contrato cerrado. No se pudo abrir el aviso de copias: ':
      'Contract closed. The copies notice could not be opened: ',
    /* copias del contrato firmado */
    'Copias del contrato firmado': 'Copies of the signed contract',
    'El contrato ya está cerrado. ¿Se les manda ahora la copia del PDF firmado a los compradores?':
      'The contract is now closed. Should the signed PDF be sent to the buyers now?',
    'Se manda una copia del PDF firmado a:': 'A copy of the signed PDF is sent to:',
    'Copia enviada a ': 'Copy sent to ',
    'No salió a: ': 'Did not go out to: ',
    'Se puede hacer luego desde «Registro» → Copias del contrato firmado.':
      'It can be done later from “Log” → Copies of the signed contract.',
    'No hay PDF firmado guardado en este contrato, así que no hay copia que mandar.':
      'There is no signed PDF stored on this contract, so there is no copy to send.',
    'Este contrato no tiene ni firmas electrónicas ni compradores con datos, así que no hay a quién mandarle una copia.':
      'This contract has neither electronic signatures nor buyers with details, so there is nobody to send a copy to.',
    'Este contrato se cerró subiendo el PDF firmado a mano, no por firma electrónica: los destinatarios son los compradores del contrato, y nada se les ha mandado solo.':
      'This contract was closed by uploading the signed PDF by hand, not by electronic signature: the recipients are the contract’s buyers, and nothing has been sent to them automatically.',
    'Todos los firmantes de este contrato han firmado ya': 'Every signer on this contract has already signed',
    'Todos constan como ya avisados: esto es un': 'All are on record as already notified: this is a',
    'reenvío': 'resend',
    'Este contrato se firmó antes de que se registraran estos envíos: lo más probable es que ya recibieran su copia, así que esto es un':
      'This contract was signed before these sends were logged: they most likely already received their copy, so this is a',
    'Este contrato se firmó antes del 24-ago-2026, cuando el reparto automático todavía no dejaba registro. Lo más probable es que las copias salieran; aquí no se puede confirmar.':
      'This contract was signed before 24 Aug 2026, when automatic distribution left no log yet. The copies most likely went out; it cannot be confirmed here.',
    /* registro de envíos */
    'Registro de envíos': 'Send log',
    'Enlaces de firma de este contrato y a qué correos se ha enviado':
      'This contract’s signing links and which addresses they were sent to',
    'Correos enviados': 'Emails sent',
    'Sin registro': 'No log',
    'No consta enviada': 'No record of it being sent',
    'Enviada a ': 'Sent to ',
    'Email enviado a ': 'Email sent to ',
    'Enlace enviado a ': 'Link sent to ',
    'Sin correos registrados. El registro existe desde el 18-ago-2026: los envíos anteriores no dejaron rastro.':
      'No emails logged. The log exists since 18 Aug 2026: earlier sends left no trace.',
    'Este contrato no se ha enviado a firma electrónica.': 'This contract has not been sent for electronic signing.',
    'El enlace activo no se puede mostrar aquí (solo se guarda su huella, no el enlace). Para reenviarlo: «✍︎ Enviar a firma» → Enviar por email.':
      'The live link cannot be shown here (only its fingerprint is stored, not the link). To resend it: “✍︎ Send for signing” → Send by email.',
    'Selecciona y copia a mano': 'Select and copy by hand',
    'Sin eventos registrados.': 'No events logged.',
    'Historial del contrato': 'Contract history',
    'Está guardado con': 'It is saved with',
    'en papel': 'on paper',
    'Sin dirección': 'No address',
    'Avisa al estudio': 'Tell the studio',
    /* envío por email */
    'El mensaje está vacío': 'The message is empty',
    'El mensaje ya no incluye el enlace de firma': 'The message no longer includes the signing link',
    'Se envía la vista previa tal cual.': 'The preview is sent exactly as it looks.',
    'O adjúntalo tú mismo (opcional)': 'Or attach it yourself (optional)',
    'Descarga el PDF y hazlo llegar por el canal que corresponda.':
      'Download the PDF and get it to them through whichever channel applies.',
    'Generar': 'Generate',
    /* barra de la vista previa */
    'Vista previa del contrato': 'Contract preview',
    'Editar el texto fijo del contrato': 'Edit the contract’s fixed text',
    'Color de portada, logo y marca de agua': 'Cover colour, logo and watermark',
    'Restaurar texto original de la plantilla': 'Restore the template’s original text',
    'Genera otro contrato reutilizando estos datos': 'Generate another contract reusing these details',
    'Guarda el contrato en la base de datos': 'Save the contract to the database',
    'Enlace para que el comprador firme a distancia': 'Link for the buyer to sign remotely',
    'Anula el enlace y las firmas ya dadas, y desbloquea el formulario para editar':
      'Voids the link and any signatures given, and unlocks the form for editing',
    'Descargar el PDF ya firmado': 'Download the signed PDF',
    'Solo super admin: devuelve el contrato a editable. Queda registrado':
      'Super admin only: returns the contract to editable. It is logged',
    'PDF a mano': 'PDF by hand',
    'Sube el PDF firmado y bloquea el contrato': 'Upload the signed PDF and lock the contract',
    'Facturar': 'Invoice',
    'Abre Facturas con este contrato ya elegido': 'Opens Invoices with this contract already selected',
    'El contrato siempre incluye Bahasa Indonesia': 'The contract always includes Bahasa Indonesia',


    /* ---------- Creatividades y el constructor de dossiers ----------
       «Creatividad» en publicidad no es «creativity»: es una PIEZA, un
       creative. Los nombres de fuente (Jost, Cormorant) y los formatos de
       Meta (Feed 4:5, Story 9:16) no se traducen: son nombres propios. */
    'Creatividades de redes': 'Social creatives',
    'Dossiers': 'Brochures',
    'Todo lo que se produce para presentar un proyecto o venderlo: dossiers de producto y piezas de pauta para redes.':
      'Everything produced to present a project or sell it: product brochures and paid-social creatives.',
    'Documento de producto en A4 apaisado: portada, planos, especificaciones y galería, listo para exportar a PDF.':
      'Product document in A4 landscape: cover, floor plans, specifications and gallery, ready to export to PDF.',
    'Piezas para Instagram y Facebook con la revisión de legibilidad incorporada: contraste, tamaño mínimo y zona segura.':
      'Assets for Instagram and Facebook with the legibility check built in: contrast, minimum size and safe zone.',
    /* piezas de redes */
    'Formato y foto': 'Format and photo',
    'Story 9:16': 'Story 9:16',
    'Feed 4:5': 'Feed 4:5',
    'Imagen de fondo': 'Background image',
    'Textos': 'Text',
    'Titular — lo que pongas entre *asteriscos* sale en beige':
      'Headline — anything you put between *asterisks* comes out in beige',
    'Subtítulo': 'Subhead',
    'Cifra': 'Figure',
    'Lugar (burbuja)': 'Location (bubble)',
    'Botón': 'Button',
    'Dominio': 'Domain',
    'El precio va vacío a propósito: no hay precio propio cerrado y la landing tampoco lo publica. Escríbelo solo si el dato está confirmado.':
      'The price is left empty on purpose: there is no agreed price of its own and the landing page does not publish one either. Only write it in if the figure is confirmed.',
    'Arrastra el bloque de texto o el de contacto en la pieza para colocarlos. Los velos se recalculan solos: no son un degradado fijo, se dimensionan con el texto que tienen que sostener.':
      'Drag the text block or the contact block on the creative to place them. The scrims recalculate themselves: they are not a fixed gradient, they are sized to the text they have to carry.',
    'Revisión de legibilidad': 'Legibility check',
    'Sube una imagen para medir el contraste real.': 'Upload an image to measure the real contrast.',
    'se solapan': 'overlap',
    'sin subir': 'not uploaded',
    'Descargar PNG': 'Download PNG',
    'Sale a 1080 px de ancho, el tamaño que pide Meta, con el grano de marca aplicado.':
      'It comes out 1080 px wide, the size Meta asks for, with the brand grain applied.',
    'Descargada a ': 'Downloaded at ',
    /* constructor de dossiers */
    'Páginas': 'Pages',
    'Página ▾': 'Page ▾',
    'Añadir página': 'Add page',
    '+ Añadir página': '+ Add page',
    'Página añadida: ': 'Page added: ',
    'Añade antes una página': 'Add a page first',
    'Fila ': 'Row ',
    'Cargar': 'Load',
    'Ese archivo no es un dossier válido': 'That file is not a valid brochure',
    'Exportar': 'Export',
    'Exportar PDF': 'Export PDF',
    'Exportar a PDF': 'Export to PDF',
    'Guardar como PDF': 'Save as PDF',
    'Abrir diálogo de impresión': 'Open the print dialog',
    'Se abre el diálogo de impresión del navegador. Con estos tres ajustes el PDF sale idéntico a lo que ves:':
      'The browser’s print dialog opens. With these three settings the PDF comes out identical to what you see:',
    'No se pudo exportar: ': 'Could not export: ',
    'Elemento de plantilla': 'Template element',
    '— libéralo para poder moverlo': '— release it to be able to move it',
    'Liberado ✓ ya se mueve, gira, redimensiona y borra':
      'Released ✓ it now moves, rotates, resizes and deletes',
    'Ese hueco está vacío: ponle una imagen antes de liberarla':
      'That slot is empty: put an image in it before releasing it',
    'Ese texto está vacío: escríbelo antes de liberarlo':
      'That text is empty: write it before releasing it',
    'Imagen': 'Image',
    'Fondo': 'Background',
    'Color': 'Colour',
    'Relleno': 'Fill',
    'Rellenar': 'Fill',
    'Ajustar': 'Fit',
    'Encaje': 'Fitting',
    'Opacidad': 'Opacity',
    'Giro': 'Rotation',
    'Interl.': 'Leading',
    'Track': 'Tracking',


    /* ---------- Previsión y fotos del investor deck (11-sep-2026) ----------
       Bloques nuevos de Modelos y Proyectos, escritos hoy por la otra sesión
       del estudio y ya envueltos en `lwT`: aquí solo faltaba su traducción.
       Vocabulario del deck público: forecast, ROI, ADR — se dejan como los
       llama el propio deck, que sale en inglés. */
    'Previsión del deck': 'Deck forecast',
    'Previsión del investor deck': 'Investor deck forecast',
    'Previsión guardada': 'Forecast saved',
    'sin previsión': 'no forecast',
    'publicada': 'published',
    'Publicar en el deck público': 'Publish on the public deck',
    'Publicar el forecast de este proyecto': 'Publish this project’s forecast',
    'Sin esta casilla el modelo no sale en el forecast. Nace apagada a propósito: que un campo esté relleno no puede significar «publícalo».':
      'Without this box the model does not appear in the forecast. It starts off on purpose: a filled-in field cannot mean “publish it”.',
    'Si se apaga, el deck de este proyecto se queda sin bloque de previsión entero: el neto y el ROI salen de restar estos tres.':
      'If it is off, this project’s deck loses the whole forecast block: the net and the ROI come from subtracting these three.',
    'Lo que sale en «Year-1 Rental Forecast» del deck público de cada proyecto. Un modelo sin previsión publicada no aparece ahí — no se enseña media tarjeta.':
      'What appears under “Year-1 Rental Forecast” on each project’s public deck. A model with no published forecast does not show up there — half a card is never shown.',
    'Este modelo, en este proyecto': 'This model, in this project',
    'Este modelo no está declarado en ningún proyecto, así que no puede tener previsión.':
      'This model is not declared in any project, so it cannot have a forecast.',
    'Precio medio/noche · escenario medio (€)': 'Average nightly rate · mid scenario (€)',
    'Precio medio/noche · óptimo (€)': 'Average nightly rate · best case (€)',
    'Ocupación media (%)': 'Average occupancy (%)',
    'Ocupación óptima (%)': 'Best-case occupancy (%)',
    'el precio medio/noche': 'the average nightly rate',
    'el precio óptimo': 'the best-case rate',
    'la ocupación media': 'the average occupancy',
    'la ocupación óptima': 'the best-case occupancy',
    'la inversión base': 'the base investment',
    'Inversión total, base del ROI (€)': 'Total investment, the ROI base (€)',
    'base': 'base',
    'La ocupación es un porcentaje: no puede pasar de 100.':
      'Occupancy is a percentage: it cannot go above 100.',
    'Los porcentajes van entre 0 y 100.': 'Percentages go between 0 and 100.',
    'Falta o no es válido: ': 'Missing or invalid: ',
    'Gastos del proyecto': 'Project costs',
    'Gestión (%)': 'Management (%)',
    'Mantenimiento (%)': 'Maintenance (%)',
    'Impuesto de alquiler (%)': 'Rental tax (%)',
    'Contrato de gestión que los fija': 'Management contract that sets them',
    'Ej. CG-2026-01': 'e.g. CG-2026-01',
    'Estos tres son del contrato de gestión de alquiler, no de este modelo: cambiarlos mueve la tarjeta de TODOS los modelos de':
      'These three come from the rental management contract, not from this model: changing them moves the card for EVERY model in',
    'Los tres porcentajes juntos se comen el ingreso entero: el neto saldría negativo.':
      'The three percentages together eat the whole income: the net would come out negative.',
    'Ojo: la base no cuadra con construcción + la parcela más barata del proyecto':
      'Careful: the base does not match construction + the cheapest plot in the project',
    'Construcción + la parcela más barata de este proyecto sale':
      'Construction + the cheapest plot in this project comes to',
    'O es un precio de paquete pactado, o se ha quedado vieja.':
      'Either it is an agreed package price, or it has gone stale.',
    'Si pones otra cifra tiene que ser porque es un paquete pactado; el deck afirma que el ROI se calcula sobre construcción más suelo y enseña el inventario real dos secciones más arriba.':
      'If you put a different figure it has to be because it is an agreed package; the deck states that the ROI is calculated on construction plus land, and it shows the real inventory two sections above.',
    'No hay parcelas con precio en este proyecto, así que no se puede contrastar la cifra con nada.':
      'There are no priced plots in this project, so the figure cannot be checked against anything.',
    'Marcar como «El más solicitado» en el deck': 'Mark as “Most requested” on the deck',
    /* fotos del deck */
    'Fotos del deck…': 'Deck photos…',
    'Fotos públicas del deck': 'Public deck photos',
    'salen en todos los proyectos donde se construya': 'appear in every project where it is built',
    'No se ha cargado el gestor de fotos del deck.': 'The deck photo manager has not loaded.',
    'Este proyecto no está en la tabla `proyectos`; no se le pueden colgar fotos.':
      'This project is not in the `proyectos` table; photos cannot be attached to it.',
    'Ese proyecto no está en la tabla `proyectos`.': 'That project is not in the `proyectos` table.',
    'No tienes permiso (solo administrador).': 'You do not have permission (administrators only).',
    'Añadir…': 'Add…',
    'Editar…': 'Edit…',


    'Este proyecto no tiene ficha en la tabla `proyectos`; no se le pueden colgar fotos.':
      'This project has no record in the `proyectos` table; photos cannot be attached to it.',

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

      /* Segunda oportunidad: la MISMA frase con blanco de sobra a los lados.
         `'No se pudo guardar: '` lleva su espacio final porque detrás se le
         concatena el mensaje de error, y esa frase es la misma que
         `'No se pudo guardar:'`. Sin esto haría falta una entrada por cada
         variante de espaciado — dos entradas para una frase, que es la clase
         de duplicado que este diccionario existe para evitar. El blanco se
         devuelve tal cual estaba, así que la concatenación sigue igual. */
      if (v == null) {
        var trozos = base.match(/^(\s*)([\s\S]*?)(\s*)$/);
        var nucleo = trozos && trozos[2];
        if (nucleo && nucleo !== base &&
            Object.prototype.hasOwnProperty.call(EN, nucleo)) {
          v = trozos[1] + EN[nucleo] + trozos[3];
        }
      }

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

       <th data-lwt>Comprador</th>                  ← la clave es su texto
       <th data-lwt="Estado~unidad">Estado</th>     ← clave explícita
       <input data-lwt-ph placeholder="Buscar…">    ← el placeholder
       <button data-lwt-title title="Borrar">       ← el title
       <span data-lwt-aria aria-label="Cerrar">     ← el aria-label

     **`data-lwt` y no `data-t`**, que sería lo natural: `data-t` YA estaba
     cogido en este repo para dos cosas distintas, y las dos habrían roto.
     `intranet/vencimientos/` guarda en `data-t` las CIFRAS de cada barra del
     gráfico (`mes.dataset.t.split('·')`): traducirlo le habría borrado los
     `<span>` de los segmentos, o sea el gráfico entero, y solo en inglés.
     `intranet/facturas/v3/` lo usa para la clave del chip de tipo. Y el
     piloto de `Documentacion/` lo usa para SU diccionario, con claves
     inventadas: si algún día carga también este fichero, los dos applier se
     pisarían. Un atributo con dos significados es la misma familia de fallo
     que una lista escrita a mano en dos sitios.

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

    r.querySelectorAll('[data-lwt]').forEach(function (el) {
      var k = el.dataset.lwt || el.textContent.trim();
      if (!k) return;
      el.dataset.lwt = k;
      el.textContent = window.lwT(k);
    });
    r.querySelectorAll('[data-lwt-ph]').forEach(function (el) {
      var k = el.dataset.lwtPh || el.getAttribute('placeholder') || '';
      if (!k) return;
      el.dataset.lwtPh = k;
      el.setAttribute('placeholder', window.lwT(k));
    });
    r.querySelectorAll('[data-lwt-title]').forEach(function (el) {
      var k = el.dataset.lwtTitle || el.getAttribute('title') || '';
      if (!k) return;
      el.dataset.lwtTitle = k;
      el.setAttribute('title', window.lwT(k));
    });
    r.querySelectorAll('[data-lwt-aria]').forEach(function (el) {
      var k = el.dataset.lwtAria || el.getAttribute('aria-label') || '';
      if (!k) return;
      el.dataset.lwtAria = k;
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
