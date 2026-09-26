/* Catálogo de herramientas de la suite — 15-ago-2026
   ----------------------------------------------------------------------------
   FUENTE ÚNICA de qué herramientas existen, cómo se llaman, adónde llevan y
   quién puede verlas.

   POR QUÉ SE MUDA AQUÍ. Vivía dentro de `intranet/index.html`, y por eso
   `topbar.js` decía por escrito que NO llevaba selector de herramientas: «el
   catálogo vive en /intranet/ con sus permisos, y una segunda lista aquí se
   quedaría vieja en cuanto se añadiera una herramienta». La objeción era
   correcta y sigue siéndolo — por eso el menú lateral no copia la lista: la
   lee de aquí, igual que el hub. Una herramienta nueva se añade UNA vez y
   aparece en los dos sitios.

   `estado` es una función que recibe las cifras del hub y devuelve
   `[texto, urgente]` o `null` si ese dato no ha llegado. Solo la usa el hub —
   el menú lateral no pinta estados — pero vive aquí para que el catálogo sea
   uno y no uno-y-medio.
*/
/* Puente al diccionario compartido (`assets/i18n.js`, 11-sep-2026). Nombre
   propio, como el `tbT` de topbar.js y por lo mismo: `function lwT(){}` a nivel
   de fichero en un script clasico pisaria el `window.lwT` de i18n.js. Y
   defensivo, porque herramientas.js lo cargan las quince paginas y no todas
   traen i18n.js todavia: donde falte, el catalogo sale en espanol. */
function hT(s, h) { return window.lwT ? window.lwT(s, h) : s; }

const LW_HERRAMIENTAS = [
  /* Nueva 9-sep-2026 (encargo del owner: un CRM propio para los leads de Meta,
     que hasta hoy solo se veían desde el panel de AxisWorks). Va la PRIMERA de
     Seguimiento porque es el principio del embudo: antes de que haya una venta
     que seguir, hay un lead al que contestar.
     PERMISO PROPIO 'leads' y no 'operaciones' —al revés que Vencimientos,
     Modelos y Solicitudes—: lo que abre son los datos de contacto de un
     centenar de personas reales, y eso tiene que poder darse cuenta a cuenta.
     Aquellas tres compartieron clave porque dar de alta una nueva exigía
     redesplegar la edge admin-usuarios y estaba bloqueada (LAW-70); hoy la
     edge está activa, así que ese motivo ya no vale. */
  { grupo:'Seguimiento', nombre:'CRM', icon:'ph-user-focus', href:'/intranet/leads/', herr:'leads',
    para:'Los leads que entran por Meta y por la web: en qué punto está cada uno y quién lo lleva.',
    claves:'leads crm meta ads formulario campañas contactos pipeline embudo kanban prospectos interesados leads crm inbox contacts funnel board prospects enquiries',
    /* La cifra del hub es "sin contactar" y no "leads totales": el total no
       pide nada a nadie, y lo que hay que mirar cada mañana es a cuánta gente
       se ha dejado sin contestar. */
    estado:d => d.leadsNuevos == null ? null
      : [d.leadsNuevos ? hT('%n sin contactar', { n: d.leadsNuevos }) : hT('Todos contestados'),
         d.leadsNuevos > 0] },
  /* `ranking` (11-sep-2026) — mismo tratamiento que 'closers', su vecina de abajo:
     vive DENTRO del CRM (pestaña «Closers») y por eso lleva
     `soloPermiso`, pero necesita existir como permiso propio en
     /intranet/usuarios/. No cuelga de 'leads' porque lo que abre es cuánto
     factura y cuánto cobra cada comercial, y con ocho de ellos eso no son
     estadísticas: el ticket medio por el número de contratos devuelve el
     importe exacto, y quien tiene un solo contrato ES ese contrato (hallazgo
     de Seguridad en la revisión previa). */
  { grupo:'Seguimiento', nombre:'Ranking de closers', icon:'ph-trophy', href:'/intranet/leads/?v=closers', herr:'ranking',
    soloPermiso:true,
    para:'Cuánto firma y cuánto cobra cada comercial, y a quién se atribuye cada venta.',
    claves:'ranking closers comerciales comisiones rendimiento estadisticas atribucion ventas leaderboard closers reps commissions performance stats attribution sales' },
  /* `closers` REPUESTO el 11-sep-2026 por el owner, y conviene dejar claro el malentendido
     para que no se repita: cuando dijo «quita Agenda de cierre del menú» quería quitar el
     ATAJO del menú lateral, no dar de baja la herramienta — «necesitamos que exista una
     agenda para los closers en el CRM sin duda, pero no es un acceso directo desde el menú
     como estaba». Se retiró entera por error, y eso dejó la pestaña «Agenda» viva dentro
     del CRM pero imposible de conceder a nadie: solo la veía un super_admin.
     `soloPermiso` es justo la forma de decir las dos cosas a la vez — existe como casilla
     en /intranet/usuarios/, y NO aparece como entrada del menú. */
  /* `reparto` (11-sep-2026) — TERCERA llave del CRM, y las tres estan separadas a
     proposito. Seguridad lo pidio asi: quien tiene `ranking` puede editar a quien se
     atribuye cada venta, o sea mover el ranking por cobrado, o sea mover su PROPIA cuota
     en el reparto. Si ademas configurase quien entra en cada origen, cerraria el circulo
     — decidiria que el #1 es el, y que el #1 se lleva el doble de leads.
     Por eso: `leads` = ver el CRM · `ranking` = ver y corregir comisiones ·
     `reparto` = configurar quien atiende que campana. Nunca la misma persona las tres
     salvo que se decida a conciencia. */
  { grupo:'Seguimiento', nombre:'Reparto de leads', icon:'ph-shuffle', href:'/intranet/leads/?v=closers', herr:'reparto',
    soloPermiso:true,
    para:'Que closers atienden cada campana, su tope de leads sin contactar y el reparto automatico.',
    claves:'reparto asignacion automatica leads campanas origenes tope closers ronda cuota routing assignment automatic campaigns sources cap round robin quota' },
  { grupo:'Seguimiento', nombre:'Agenda de cierre', icon:'ph-video-camera', href:'/intranet/leads/?v=agenda', herr:'closers',
    soloPermiso:true,
    para:'La agenda de llamadas de venta del closer, dentro del CRM.',
    claves:'closers agenda citas llamadas venta cierre meet closers calendar appointments calls sales closing meet' },
  { grupo:'Seguimiento', nombre:'Operaciones', icon:'ph-chart-line-up', href:'/intranet/operaciones/', herr:'operaciones',
    para:'Cómo va cada venta: estado de cuenta, documentos, firmas y vencimientos.',
    claves:'ventas seguimiento estado cuenta sales deals pipeline statement account tracking',
    estado:d => d.firmasPendientes == null ? null
      : [d.firmasPendientes ? hT(d.firmasPendientes === 1 ? '%n firma esperando' : '%n firmas esperando', { n: d.firmasPendientes }) : hT('Sin firmas pendientes'),
         d.firmasPendientes > 0] },
  /* PERMISO PROPIO desde el 18-ago-2026 (2ª vuelta). Nació compartiendo
     `herr:'operaciones'` por una razón que ya no existe: una clave nueva hay que
     darla de alta en la edge admin-usuarios y REDESPLEGARLA, y aquel día la edge
     estaba bloqueada por LAW-70, así que una clave nueva habría dejado a los
     usuarios nuevos sin la herramienta en silencio. La edge se desplegó esa misma
     noche, y el owner lo vio por donde se ve: «hay una nueva herramienta y no
     sale en la lista» — porque no tenía permiso propio que listar.
     Al darle clave propia, quien tenía «Operaciones» recibe también
     «Vencimientos» (migración en sql/permiso_vencimientos.sql): sin eso, diez
     personas habrían perdido de golpe una herramienta que ya usaban. */
  /* Nueva 1-sep-2026 (owner: "Soporte lo has metido en la ficha de cliente,
     ahí no se ve. Necesita su propia sección"). Antes eran dos fieldsets
     (Soporte + Mensajes) dentro de la ficha de un comprador en
     /intranet/compradores/ — invisibles salvo que se abriera esa ficha
     concreta, y el owner los veía como la misma cosa duplicada. Unificado
     en un hilo único (1-sep mañana) y, esa misma tarde, corregido a
     TICKETS por comprador — con su propia bandeja en las dos versiones. */
  /* Reservas por vencer (23-sep-2026, owner): Cartas de Reserva vivas sin
     Bloqueo y cuándo vencen. Clave propia desde el primer día. */
  { grupo:'Seguimiento', nombre:'Reservas por vencer', icon:'ph-hourglass-medium', href:'/intranet/v4/reservas/', herr:'reservas',
    para:'Cartas de Reserva que aún no tienen Bloqueo de Parcela y cuándo vencen.',
    claves:'reservas vencer vencimiento carta reserva bloqueo parcela gracia prorroga reservations expiring hold plot extension' },

  { grupo:'Documentación', nombre:'Contratos', icon:'ph-file-text', href:'/contracts/', herr:'contratos',
    para:'Reservas, PPJB, construcción y anexos.',
    claves:'contratos ppjb reserva construccion anexos contracts reservation construction annexes deeds',
    estado:d => d.contratos == null ? null
      : [hT('%g guardados · %e editables', { g: d.contratos, e: d.contratosEditables }), false] },
  /* Nueva 22-sep-2026 (encargo del owner: «apoyo de una IA que nos ayude a
     responder» las dudas que un comprador manda a su agente —
     encargos/20260922_lawang_bot_apoyo_agentes.md). Va PEGADA a Contratos
     porque es su otra cara: allí se emite el ejemplar, aquí se responde
     citándolo. Redacta un BORRADOR y nada más — no envía, no tiene WhatsApp
     ni email: el agente lo revisa y lo reenvía él (owner y Legal, misma
     fecha). Quien redacta es la Edge Function bot-agentes, que lee el
     contrato con el JWT del agente: la RLS de `contratos` es la puerta real.
     `herr:'contratos'` A PROPÓSITO, no una clave nueva (decisión CEO en el
     encargo): quien ve el contrato puede pedir el borrador, y una clave nueva
     obliga a redesplegar la edge admin-usuarios (LAW-70) — mismo precedente
     que Vencimientos, Modelos y Solicitudes. Al compartir clave dos
     tarjetas, la etiqueta del permiso va en LW_ETIQUETA_PROPIA (abajo).
     Sin `estado`: no hay nada que vigilar cada mañana — se usa cuando llega
     una pregunta, no al revés. */
  /* Asistente: SEPARADAS 23-sep-2026 (owner: «hay herramientas que no se controla la vista
     desde usuarios como las demás» → «separa todo»). Clave propia de VISTA;
     guardar en la base sigue pidiendo el permiso de la herramienta madre.
     La migración 20260923180500_permisos_propios se la dio a quien ya tenía la madre. */
  { grupo:'Documentación', nombre:'Asistente', icon:'ph-robot', href:'/intranet/v4/asistente/', herr:'asistente',
    para:'Pide lo que no puedes hacer tú: cambiar un dato, anular o borrar un documento, borrar una operación. Lo aprueba dirección.',
    claves:'asistente peticion pedir solicitud cambiar dato borrar anular factura recibi operacion contrato comprador aprobar request change delete cancel invoice approval' },
  // Dossier y Creatividades, unificadas en UNA tarjeta (7-ago-2026): antes
  // eran dos entradas sueltas para dos herramientas de producción de
  // contenido que casi siempre se usan seguidas. `herr` como ARRAY = ve la
  // tarjeta quien tenga cualquiera de las dos (ver `puede()` más abajo);
  // dentro, el visor de /intranet/creatividades/ reparte a cada herramienta, que
  // sigue exigiendo SU permiso propio para entrar de verdad.
  // 24-sep-2026 (encargo Creatividades v4): tercera llave 'creatividades_ver' — el
  // comercial VE y descarga lo aprobado, sin crear nada (la RLS lo garantiza). La
  // tarjeta lleva a la portada v4, que es la biblioteca y reparte a cada herramienta.
  { grupo:'Documentación', nombre:'Creatividades', icon:'ph-image-square', href:'/intranet/v4/creatividades/', herr:['dossier','creatividades','creatividades_ver'],
    para:'Piezas para redes y dossiers de cada proyecto, con las fotos de la intranet, su revisión y la biblioteca de lo aprobado.',
    claves:'creatividades dossier anuncios pauta instagram facebook meta ads imagen story feed pdf maqueta producto creative assets brochure ads artwork image story feed mockup product' },   // sin `estado`: ninguna de las dos vive en la base de datos
  { grupo:'Documentación', nombre:'Documentación', icon:'ph-folders', href:'/intranet/documentacion/', herr:'documentacion',
    para:'Precios, planos y material de cada proyecto, en el almacén privado.',
    claves:'documentacion documentos precios planos parcelas material proyecto archivo documents files pricing floor plans plots material project archive',
    estado:d => d.documentos == null ? null
      : d.documentos === 0 ? [hT('Sin documentos todavía'), true]
      : [hT('%d documentos · %p proyectos', { d: d.documentos, p: d.proyectosConDocs }), false] },

  /* SECCIÓN «FINANZAS» (24-sep-2026, owner, opción A): lo que antes era
     «Administración», más Vencimientos (venía de Seguimiento) y Cuentas bancarias
     (venía de Equipo). Todo lo que mueve dinero, junto. Vencimientos va la
     primera: es lo que toca cobrar. Mismo orden en la sidebar v4 (nav.js,
     ORDEN_FINANZAS). Cambiar de grupo no cambia quién la ve: eso es `herr`. */
  { grupo:'Finanzas', nombre:'Vencimientos', icon:'ph-calendar-check', href:'/intranet/vencimientos/', herr:'vencimientos',
    para:'Qué dinero debe entrar, cuándo, y cuál se está retrasando: la caja de la empresa por fechas.',
    claves:'vencimientos pagos hitos caja cashflow finanzas dinero calendario vencido dashboard payments due milestones cash finance money schedule overdue',
    /* La cifra del hub es "sin fecha" y NO "vencidos", a propósito: saber si un
       vencimiento pasado sigue debiéndose exige la cascada de cobros (la calcula
       la propia herramienta), y un conteo crudo de fechas pasadas contaría
       también lo ya pagado — un número que asusta de más se deja de mirar, que
       es el mismo fallo que un cero falso. "Sin fecha" sí es exacto con un
       count, y es además lo primero que hay que dejar a cero para que el
       dashboard vigile de verdad. */
    estado:d => d.vencSinFecha == null ? null
      : [d.vencSinFecha ? hT('%n sin fecha que vigilar', { n: d.vencSinFecha }) : hT('Calendario al día'),
         d.vencSinFecha > 0] },
  { grupo:'Finanzas', nombre:'Facturas', icon:'ph-receipt', href:'/intranet/facturas/', herr:'facturas',
    para:'Facturas, proformas y recibís, cada tipo con su serie.',
    claves:'facturas proforma serie inv cobro impuesto invoices proforma series billing tax vat',
    estado:d => d.facturas == null ? null
      : [hT('%n emitidas', { n: d.facturas }) + (d.facturasAnuladas ? ' · ' + hT('%n anuladas', { n: d.facturasAnuladas }) : ''), false] },
  /* Recibos: SEPARADAS 23-sep-2026 (owner: «hay herramientas que no se controla la vista
     desde usuarios como las demás» → «separa todo»). Clave propia de VISTA;
     guardar en la base sigue pidiendo el permiso de la herramienta madre.
     La migración 20260923180500_permisos_propios se la dio a quien ya tenía la madre. */
  { grupo:'Finanzas', nombre:'Recibos', icon:'ph-hand-coins', href:'/intranet/facturas/?tipo=recibi', herr:'recibos',
    para:'Justificantes de pago y señales.',
    claves:'recibi recibos justificante señal pago receipts proof of payment deposit',
    estado:d => d.recibis == null ? null : [hT('%n emitidos', { n: d.recibis }), false] },
  /* Nueva 9-sep-2026 (owner: «un apartado donde los comerciales nos puedan
     crear solicitudes de pago» — y su corrección del mismo día: «las ponen los
     agentes para pedirle a Lawang que les pague ciertos importes como pueden
     ser comisiones o pagos acordados, no para cargarlas sobre los
     compradores»). El agente pide un pago a Lawang; el admin lo aprueba,
     lo rechaza con motivo, o lo marca pagado al hacer la transferencia.
     `herr:'operaciones'` A PROPÓSITO, no una clave nueva: un permiso nuevo
     exige redesplegar la edge admin-usuarios (pendiente por LAW-70) y dejaría
     a los usuarios nuevos sin la herramienta en silencio — mismo precedente
     que Vencimientos (18-ago) y Modelos (7-sep). Al compartir clave dos
     tarjetas, la etiqueta del permiso va en LW_ETIQUETA_PROPIA (abajo).
     La cifra cuenta pendientes + aprobadas sin pagar (lo que espera acción del
     admin) y hereda la RLS: el admin las cuenta todas, cada agente las suyas. */
  /* PERMISO PROPIO desde el 23-sep-2026 (owner: «comisiones no quiero que las
     vea nadie ahora mismo»). Compartir 'operaciones' hacía imposible quitarla
     sin quitar Operaciones. Nace concedida a NADIE: solo la ve un super_admin. */
  { grupo:'Finanzas', nombre:'Solicitudes', icon:'ph-coins', href:'/intranet/solicitudes/', herr:'comisiones',
    para:'Pagos que piden los comerciales — comisiones y acordados: quién pide qué, y en qué quedó cada uno.',
    claves:'solicitudes pago pagos comisiones comerciales agentes pedir comision payment requests commissions agents reps payout',
    estado:d => d.solicitudesVivas == null ? null
      : [d.solicitudesVivas ? hT('%n por resolver o pagar', { n: d.solicitudesVivas }) : hT('Sin solicitudes en vuelo'),
         d.solicitudesVivas > 0] },
  /* COMISIONES, UNA ENTRADA CON CUATRO PESTAÑAS (23-sep-2026, plan aprobado
     por el owner: «Necesitamos agrupar y controlar lo que se ve por
     permisos»). Cada pestaña es una casilla en Usuarios: 'comisiones' (arriba)
     es «Pagos de Lawang», y estas tres son las otras. `soloPermiso`: casilla sí,
     tarjeta propia en el hub no — la entrada del menú es una sola, «Comisiones»,
     y la barra de pestañas la pinta nav.js. La casilla decide si la pestaña
     aparece; lo que se ve dentro lo decide el ROL en la base (cada uno lo suyo). */
  { grupo:'Finanzas', nombre:'Comisiones · Reparto a closers', icon:'ph-hand-coins', href:'/intranet/v4/reparto/', herr:'comisiones_reparto',
    soloPermiso:true,
    para:'Lo que le toca a cada closer y qué le ha pagado su manager. Un closer solo ve lo suyo.',
    claves:'reparto closers comisiones equipo pagado manager mis comisiones team payout split' },
  { grupo:'Finanzas', nombre:'Comisiones · Condiciones', icon:'ph-percent', href:'/intranet/v4/condiciones/', herr:'comisiones_condiciones',
    soloPermiso:true,
    para:'Cuánto cobra cada closer y cada manager. Un Sales Manager solo las de sus closers.',
    claves:'condiciones comision porcentaje tramos closer manager conditions commission rate tiers' },
  { grupo:'Finanzas', nombre:'Comisiones · Equipos', icon:'ph-users-four', href:'/intranet/v4/equipos-venta/', herr:'comisiones_equipos',
    soloPermiso:true,
    para:'Los equipos de venta, su manager y sus closers. Un Sales Manager solo ve el suyo.',
    claves:'equipos venta manager closers miembros sales teams members' },

  /* Gastos y proveedores (24-sep-2026, owner: «Hazlo», módulo 1.º de la tabla B
     de encargos/20260924_lawang_dashboard_finanzas.md). `soloPermiso`: casilla
     en Usuarios, sin tarjeta en el hub — es pantalla de la v4 y se llega desde
     su Panel de control. La puerta de verdad es la RLS: es_admin() Y
     puede('gastos'); nace concedida a nadie (solo la ve un super_admin). */
  { grupo:'Finanzas', nombre:'Gastos y proveedores', icon:'ph-receipt', href:'/intranet/v4/gastos/', herr:'gastos',
    soloPermiso:true,
    para:'Lo que paga la empresa: facturas de proveedores, retenciones y su justificante.',
    claves:'gastos proveedores costes pagos facturas proveedor retencion pph expenses suppliers costs payables' },
  /* Bancos y conciliación (24-sep-2026, owner: «Hazlo. Usan Statrys, bancos de
     Hong Kong y Singapur»). Misma forma que Gastos: `soloPermiso`, se llega
     desde el menú de la v4, y la puerta de verdad es la RLS y las RPC:
     es_admin() Y puede('bancos'). Nace concedida a nadie. */
  { grupo:'Finanzas', nombre:'Bancos y conciliación', icon:'ph-bank', href:'/intranet/v4/bancos/', herr:'bancos',
    soloPermiso:true,
    para:'Los extractos de las cuentas de la sociedad y qué documento explica cada movimiento.',
    claves:'bancos extracto conciliacion conciliar statrys dbs ocbc hsbc saldo movimientos traspaso bank statement reconciliation balance' },

  /* «Comisión de administración» y «Sociedades emisoras» ya NO salen en este
     catálogo (owner, 22-sep-2026): son pantallas de la v4 y solo se llega a
     ellas desde su «Panel de control» (`intranet/v4/assets/nav.js`,
     PANEL_CONTROL_SUPER), solo super admin. La puerta de verdad sigue siendo la
     RLS (`es_super_admin()`), no este menú. */

  /* SECCIÓN «COMUNICACIÓN» (24-sep-2026, owner: «Comunicación necesita su sección»):
     Soporte (tickets de compradores) sale de Seguimiento. Los comunicados al equipo
     son de la v4 y no tienen tarjeta aquí. Mismo orden en la sidebar v4 (nav.js,
     ORDEN_COMUNICACION). Lo que se ve lo sigue decidiendo `herr`. */
  { grupo:'Comunicación', nombre:'Soporte', icon:'ph-headset', href:'/intranet/soporte/', herr:'soporte',
    para:'Los tickets de los compradores desde su área de clientes, en una bandeja.',
    claves:'soporte mensajes tickets chat compradores atencion consultas support messages tickets chat buyers enquiries inbox',
    estado:d => d.hilosAbiertos == null ? null
      : [d.hilosAbiertos ? hT(d.hilosAbiertos === 1 ? '%n ticket abierto' : '%n tickets abiertos', { n: d.hilosAbiertos }) : hT('Sin tickets abiertos'),
         d.hilosAbiertos > 0] },

  { grupo:'Base de datos', nombre:'Proyectos', icon:'ph-buildings', href:'/intranet/proyectos/', herr:'unidades',
    para:'Inventario de parcelas y villas con su estado de venta, por proyecto.',
    claves:'proyectos unidades parcelas villas inventario disponible carpetas projects units plots villas inventory available folders',
    estado:d => d.unidades == null ? null
      : d.unidades === 0 ? [hT('Sin inventario cargado'), true]
      : [hT('%u unidades · %l disponibles', { u: d.unidades, l: d.unidadesLibres }), false] },
  /* Nueva 11-sep-2026 (encargo del owner: traer /v4/proyectos a la version
     actual sin retirar la de siempre — "mantener los 2 enlaces desde el
     menu"). Va PEGADA a Proyectos porque son la misma base de datos vista de
     dos formas: tabla ancha editable de toda la vida vs. tarjetas por
     proyecto + cajon de cuentas de la v4. Mismo `herr:'unidades'` que su
     hermana, mismo motivo que Modelos de arriba: una clave nueva exige
     redesplegar la edge admin-usuarios (LAW-70 sigue pendiente) y dejaria a
     los usuarios nuevos sin la herramienta en silencio. Sin `estado`: son las
     mismas cifras que ya cuenta la ficha de Proyectos, repetir el aviso ahi
     seria ruido, no informacion nueva. */
  { grupo:'Base de datos', nombre:'Proyectos (nueva vista)', icon:'ph-squares-four', href:'/intranet/v4/proyectos/', herr:'unidades',
    para:'La misma base de parcelas y villas, en tarjetas por proyecto con el estado de cuentas. En pruebas junto a Proyectos.',
    claves:'proyectos v4 tarjetas nueva vista cuentas beta prueba projects cards new view accounts' },
  /* Nueva 7-sep-2026 (encargo del owner: dar de alta los tipos de vivienda igual
     que se dan de alta las parcelas). Va JUSTO detras de Proyectos porque es su
     otra mitad: alli esta el terreno, aqui la casa que se levanta encima, y el
     precio de una unidad es la suma de los dos.
     `herr:'unidades'` — el mismo permiso que Proyectos, a proposito y no una
     clave nueva: una clave nueva exige redesplegar la edge admin-usuarios, que
     sigue pendiente por LAW-70, y dejaria a los usuarios nuevos sin la
     herramienta en silencio. Mismo precedente que Vencimientos con
     'operaciones'. Quien administra el inventario administra que se construye
     en el, asi que el criterio de acceso tampoco abre ningun hueco. */
  /* Modelos: SEPARADAS 23-sep-2026 (owner: «hay herramientas que no se controla la vista
     desde usuarios como las demás» → «separa todo»). Clave propia de VISTA;
     guardar en la base sigue pidiendo el permiso de la herramienta madre.
     La migración 20260923180500_permisos_propios se la dio a quien ya tenía la madre. */
  { grupo:'Base de datos', nombre:'Modelos', icon:'ph-house-line', href:'/intranet/modelos/', herr:'modelos',
    para:'Que se puede construir: habitaciones, metros, precio, techos, extras y planos de cada tipo de vivienda.',
    claves:'modelos tipologias villas tipos vivienda specs precio techos extras planos catalogo dormitorios metros house models types specs price roofs add-ons floor plans catalogue bedrooms sqm',
    /* El estado dice lo que hay que ARREGLAR, no cuantas filas hay: un modelo
       sin precio de catalogo es el que hace que un proyecto herede un hueco. */
    estado:d => d.modelos == null ? null
      : d.modelosSinPrecio ? [hT('%n sin precio de catalogo', { n: d.modelosSinPrecio }), true]
      : [hT('%m modelos · %p en la web', { m: d.modelos, p: d.modelosPublicados }), false] },
  { grupo:'Base de datos', nombre:'Obra', icon:'ph-crane-tower', href:'/intranet/obra/', herr:'obra',
    para:'Fase, fecha de entrega y fotos de cada unidad — lo que ve el comprador en su portal.',
    claves:'obra construccion fases fotos avance portal entrega construction site stages photos progress handover',
    estado:d => d.obraActivas == null ? null
      : d.obraActivas === 0 ? [hT('Sin unidades en obra'), true]
      : [hT('%n en obra', { n: d.obraActivas }), false] },
  { grupo:'Base de datos', nombre:'Compradores', icon:'ph-identification-card', href:'/intranet/compradores/', herr:'compradores',
    para:'Ficha del comprador y documentación KYC, con caducidades.',
    claves:'compradores kyc pasaporte fichas clientes caducidad buyers kyc passport records clients expiry',
    estado:d => d.compradores == null ? null : [hT('%n fichas', { n: d.compradores }), false] },

  { grupo:'Equipo', nombre:'Usuarios', icon:'ph-users-three', href:'/intranet/usuarios/', herr:'usuarios', soloAdmin:true,
    para:'Quién entra, con qué rol y qué herramientas ve cada uno.',
    claves:'usuarios permisos roles equipo acceso users permissions roles team access',
    estado:d => d.usuarios == null ? null
      : [hT('%n con acceso', { n: d.usuarios }) + (d.usuariosInactivos ? ' · ' + hT('%n desactivados', { n: d.usuariosInactivos }) : ''), false] },

  /* Nueva 14-sep-2026 (encargo del owner: «tenemos muchas cuentas bancarias y
     no son editables ni marcables lo que quiero que aparezca en cada una»).
     Iba en «Equipo» junto a Usuarios; desde el 24-sep-2026 va en «Finanzas»
     (owner, opción A): es la tesorería, adónde entra el dinero.
     `soloAdmin` es la puerta del menú, pero la de verdad es la RLS: escribir
     estas dos tablas exige `es_super_admin()` en la base. Un admin normal que
     llegue por la URL puede MIRAR el reparto —le sirve para entender por qué un
     contrato ofrece las cuentas que ofrece— y no puede cambiar nada. Es el dato
     que decide adónde va el dinero de un comprador: ahí no hay delegación. */
  { grupo:'Finanzas', nombre:'Cuentas bancarias', icon:'ph-bank', href:'/intranet/cuentas/', herr:'cuentas', soloAdmin:true,
    para:'Las cuentas de cobro y qué cuenta se ofrece en cada tipo de contrato.',
    claves:'cuentas bancarias banco iban swift cobro pago escrow notario destino plantillas contratos bank accounts payment details escrow beneficiary',
    estado:d => d.cuentas == null ? null
      : [hT('%n cuentas', { n: d.cuentas }), false] },

  /* Ajustes (22-sep-2026): los números que gobiernan las reservas (días de
     gracia, prórrogas, techos) viven en la tabla `parametros` y el owner los
     cambia aquí sin tocar código. Sin `herr` a propósito: no es un permiso
     repartible — lo ve cualquier admin (soloAdmin) y escribe solo super admin
     (parametro_set, en la base). Vive en la v4. */
  { grupo:'Equipo', nombre:'Ajustes', icon:'ph-sliders-horizontal', href:'/intranet/v4/ajustes/', soloAdmin:true,
    para:'Días de gracia, prórrogas y techos de las reservas: lo que el sistema aplica solo.',
    claves:'ajustes parametros configuracion reservas gracia prorroga prorrogas topes settings parameters reservation grace extension limits' },

];

/* Quién ve qué. `soloAdmin` es la puerta dura; si no, basta con tener la
   herramienta en la ficha. Un admin lo ve todo, y una herramienta sin `herr`
   declarado es de todos. Se acepta la ficha por parámetro (y no una global)
   para que el hub y la barra la usen sin depender de cómo se llame su variable. */
const lwEsAdmin = f => !!f && (f.rol === 'super_admin' || f.rol === 'admin');
const lwEsSuper = f => !!f && f.rol === 'super_admin';
/* LOS ADMIN TAMBIÉN PASAN POR SU LISTA — 18-ago-2026, owner: «son gente del
   equipo interno pero no todos deben tener acceso a todo».
   Antes el que se saltaba la comprobación era `lwEsAdmin`, y como ocho de los
   dieciocho usuarios son admin, el reparto por herramienta solo gobernaba a la
   mitad del equipo. Ahora el único sin límite es el super admin (hay uno), que
   tiene que poder llegar a todo aunque su propia ficha no lo tenga marcado —
   la del owner no lleva ni «Obra» ni «Creatividades».
   Las dos condiciones se SUMAN, no se sustituyen: una tarjeta `soloAdmin`
   sigue exigiendo rol de admin, y además ahora su herramienta.
   ⚠️ Esta regla es la del navegador. Quien manda de verdad es `puede()` en la
   base (sql/permisos_admin_por_herramienta.sql). Si cambia una, cambia la otra
   o el menú ofrecerá una herramienta que rebota al guardar. */
const lwPermitida = (t, ficha) =>
  !t.soloPermiso &&
  (!t.soloAdmin || lwEsAdmin(ficha)) &&
  /* `soloSuper` es un peldano por encima de `soloAdmin`: no basta con ser admin.
     Hizo falta para la Comision de administracion, que abre lo que el estudio le
     cobra al cliente — un dato que los cuatro admin no tienen por que ver. */
  (!t.soloSuper || lwEsSuper(ficha)) &&
  (!ficha || lwEsSuper(ficha) || !t.herr ||
   [].concat(t.herr).some(h => (ficha.herramientas || []).includes(h)));

/* ═══════════════════════════════════════════════════════════════════════════
   LOS PERMISOS SALEN DE ESTE MISMO CATÁLOGO — 17-ago-2026 (auditoría)
   ═══════════════════════════════════════════════════════════════════════════
   `/intranet/usuarios/` tenía su propia lista de las diez herramientas, con sus etiquetas
   escritas a mano, y ya había divergido: la casilla del inventario decía
   «Unidades» mientras el hub y el menú lateral dicen «Proyectos». Es letra por
   letra el fallo de `TIPO_ES` contra `TIPO_LABEL` que se cerró el 14-ago, esta
   vez sobre los nombres de las propias herramientas — y en la pantalla donde se
   reparte el acceso, que es la peor para llamar a algo por un nombre que no usa
   nadie más.

   Se DERIVA del catálogo en vez de escribirse otra vez:
     · un permiso por cada valor de `herr`, aplanando las tarjetas que agrupan
       dos herramientas (Creatividades = dossier + creatividades);
     · la etiqueta es el `nombre` de la tarjeta cuando la tarjeta es de UNA sola
       herramienta, así que renombrar una en el catálogo la renombra también en
       los permisos;
     · las que comparten tarjeta necesitan nombre propio y solo esas están en
       `ETIQUETA_PROPIA`. Si mañana se agrupa otra y nadie le pone etiqueta, el
       `console.warn` de abajo lo dice en la consola de /intranet/usuarios/ en vez de
       enseñar la clave cruda de la base de datos, que es como se colaron seis
       contratos con jerga en pantalla.
   ═══════════════════════════════════════════════════════════════════════════ */
const LW_ETIQUETA_PROPIA = {
  dossier:       'Dossier',
  creatividades: 'Creatividades',
  creatividades_ver: 'Creatividades · ver y descargar lo aprobado',
  comisiones:    'Comisiones · Pagos de %marca',   // la pestaña «Pagos de %marca» (23-sep-2026); %marca, de la ficha
  usuarios:      'Usuarios (admin)',     // el «(admin)» avisa de que además exige rol
};

const LW_PERMISOS = (function () {
  const vistos = [], nombreDe = {};
  LW_HERRAMIENTAS.forEach(function (t) {
    const claves = [].concat(t.herr || []);
    claves.forEach(function (h) {
      if (vistos.indexOf(h) < 0) vistos.push(h);
      // el nombre de la tarjeta solo sirve si la tarjeta es de UNA herramienta
      if (claves.length === 1 && !nombreDe[h]) nombreDe[h] = t.nombre;
    });
  });
  return vistos.map(function (h) {
    const etiqueta = LW_ETIQUETA_PROPIA[h] || nombreDe[h];
    if (!etiqueta) console.warn('herramientas.js: el permiso «' + h + '» no tiene etiqueta — ponle una en LW_ETIQUETA_PROPIA');
    /* La etiqueta puede llevar %marca (F3 2b, 26-sep-2026). En las páginas clásicas este fichero carga
       ANTES que la ficha de la instancia, así que se rellena al LEERLA, no aquí. */
    const par = [h, null];
    Object.defineProperty(par, 1, { enumerable: true, get: function () {
      const e = etiqueta || h;
      return typeof window !== 'undefined' && window.lwMarca ? window.lwMarca(e) : e;
    } });
    return par;
  });
})();

/* ═══════════════════════════════════════════════════════════════════════════
   COMPARTIDO CON LA v4 (paridad 21-sep-2026, alta nativa de /v4/usuarios/)
   ═══════════════════════════════════════════════════════════════════════════
   Estos tres catálogos vivían SOLO dentro del <script> de /intranet/usuarios/,
   escritos a mano. La v4 necesita exactamente lo mismo para su propio
   formulario de alta — con qué llave es CRM y con qué se preselecciona cada
   rol — y una segunda copia de "qué toca a cada rol" es la clase de fallo que
   ya le ha costado dinero al estudio: dos sitios deciden el permiso de
   arranque de un agente nuevo, y el día que diverjan lo deciden distinto según
   por dónde se dé de alta (ver contexto/patrones_tecnicos.md → «El dato tiene
   un dueño»). Se sella aquí, la clásica y la v4 lo LEEN. */

/* Las llaves del CRM van en su PROPIO grupo, no mezcladas con el resto
   (encargo del owner, 11-sep-2026): reparten con un criterio distinto entre
   sí y distinto del resto de la suite — Leads abre los datos de contacto de
   un centenar de personas, Ranking las cifras de cada comercial, Reparto
   quién atiende cada campaña, Agenda la agenda de llamadas de venta. */
const LW_PERMISOS_CRM = ['leads', 'ranking', 'reparto', 'closers'];

/* Con qué herramientas y qué tipos de contrato nace cada rol (11-sep-2026,
   encargo del owner) — solo PRESELECCIÓN al crear: sigue siendo editable
   después, ficha a ficha. `tipos_contrato` vacío en la tabla significa
   "TODOS" (al revés que `proyectos`), así que sin esto un agente nuevo podía
   emitir cualquier tipo de contrato desde el minuto uno — se rellena
   explícito para que la restricción sea real desde el alta. */
const LW_HERR_POR_ROL = {
  // Comisiones (23-sep-2026, plan del owner): el closer ve su reparto; el Sales
  // Manager, reparto + condiciones + equipo («Pagos de Lawang» se le da a mano
  // mientras esa pestaña no le filtre solo lo suyo); el admin gestiona
  // condiciones y equipos sin ver importes.
  agente:          ['contratos','compradores','documentacion','unidades','facturas','operaciones','asistente','recibos','modelos','reservas','comisiones_reparto','creatividades_ver'],
  project_manager: ['contratos','compradores','documentacion','unidades','facturas','obra','operaciones','asistente','recibos','modelos','reservas','comisiones_reparto','creatividades_ver'],
  sales_manager:   ['contratos','compradores','documentacion','unidades','facturas','operaciones','asistente','recibos','modelos','reservas','comisiones_reparto','comisiones_condiciones','comisiones_equipos','creatividades_ver'],
  admin:           ['contratos','compradores','documentacion','unidades','facturas','operaciones','asistente','recibos','modelos','reservas','comisiones_condiciones','comisiones_equipos'],
  super_admin:     ['contratos','compradores','documentacion','unidades','facturas','obra','operaciones','asistente','recibos','modelos','reservas','comisiones','comisiones_reparto','comisiones_condiciones','comisiones_equipos'],
};
const LW_TIPOS_POR_ROL = {
  agente:          ['carta_reserva','reserva_parcela','construccion'],
  project_manager: ['carta_reserva','reserva_parcela','construccion'],
  sales_manager:   ['carta_reserva','reserva_parcela','construccion','hak_sewa_notario','poa'],
  admin:           ['carta_reserva','reserva_parcela','construccion','hak_sewa_notario','poa'],
  super_admin:     ['carta_reserva','reserva_parcela','construccion','hak_sewa_notario','poa'],
};


/* Orden de los grupos, para que el menú lateral no repita cabeceras si el
   catálogo trae entradas del mismo grupo separadas. El hub no lo necesita
   -pinta por grupos- pero el menú va en una sola columna. */
const LW_GRUPOS = LW_HERRAMIENTAS.reduce(function (a, t) {
  if (t.grupo && a.indexOf(t.grupo) < 0) a.push(t.grupo);
  return a;
}, []);
const lwPorGrupo = function (lista) {
  return lista.slice().sort(function (a, b) {
    return LW_GRUPOS.indexOf(a.grupo) - LW_GRUPOS.indexOf(b.grupo);
  });
};
