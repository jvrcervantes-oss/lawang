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
