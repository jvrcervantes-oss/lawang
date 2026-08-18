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
const LW_HERRAMIENTAS = [
  { grupo:'Seguimiento', nombre:'Operaciones', icon:'ph-chart-line-up', href:'/operaciones/', herr:'operaciones',
    para:'Cómo va cada venta: estado de cuenta, documentos, firmas y vencimientos.',
    claves:'ventas seguimiento estado cuenta',
    estado:d => d.firmasPendientes == null ? null
      : [d.firmasPendientes ? d.firmasPendientes + (d.firmasPendientes === 1 ? ' firma esperando' : ' firmas esperando') : 'Sin firmas pendientes',
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
  { grupo:'Seguimiento', nombre:'Vencimientos', icon:'ph-calendar-check', href:'/vencimientos/', herr:'vencimientos',
    para:'Qué dinero debe entrar, cuándo, y cuál se está retrasando: la caja de la empresa por fechas.',
    claves:'vencimientos pagos hitos caja cashflow finanzas dinero calendario vencido dashboard',
    /* La cifra del hub es "sin fecha" y NO "vencidos", a propósito: saber si un
       vencimiento pasado sigue debiéndose exige la cascada de cobros (la calcula
       la propia herramienta), y un conteo crudo de fechas pasadas contaría
       también lo ya pagado — un número que asusta de más se deja de mirar, que
       es el mismo fallo que un cero falso. "Sin fecha" sí es exacto con un
       count, y es además lo primero que hay que dejar a cero para que el
       dashboard vigile de verdad. */
    estado:d => d.vencSinFecha == null ? null
      : [d.vencSinFecha ? d.vencSinFecha + ' sin fecha que vigilar' : 'Calendario al día',
         d.vencSinFecha > 0] },

  { grupo:'Documentación', nombre:'Contratos', icon:'ph-file-text', href:'/contracts/app.html', herr:'contratos',
    para:'Reservas, PPJB, construcción y anexos.',
    claves:'contratos ppjb reserva construccion anexos',
    estado:d => d.contratos == null ? null
      : [d.contratos + ' guardados · ' + d.contratosEditables + ' editables', false] },
  // Dossier y Creatividades, unificadas en UNA tarjeta (7-ago-2026): antes
  // eran dos entradas sueltas para dos herramientas de producción de
  // contenido que casi siempre se usan seguidas. `herr` como ARRAY = ve la
  // tarjeta quien tenga cualquiera de las dos (ver `puede()` más abajo);
  // dentro, el visor de /creatividades/ reparte a cada herramienta, que
  // sigue exigiendo SU permiso propio para entrar de verdad.
  { grupo:'Documentación', nombre:'Creatividades', icon:'ph-image-square', href:'/creatividades/', herr:['dossier','creatividades'],
    para:'Dossiers de producto y piezas de pauta para Instagram y Facebook, con la revisión de legibilidad incorporada.',
    claves:'creatividades dossier anuncios pauta instagram facebook meta ads imagen story feed pdf maqueta producto' },   // sin `estado`: ninguna de las dos vive en la base de datos
  { grupo:'Documentación', nombre:'Documentación', icon:'ph-folders', href:'/documentacion/', herr:'documentacion',
    para:'Precios, planos y material de cada proyecto, en el almacén privado.',
    claves:'documentacion documentos precios planos parcelas material proyecto archivo',
    estado:d => d.documentos == null ? null
      : d.documentos === 0 ? ['Sin documentos todavía', true]
      : [d.documentos + ' documentos · ' + d.proyectosConDocs + ' proyectos', false] },

  { grupo:'Administración', nombre:'Facturas', icon:'ph-receipt', href:'/facturas/', herr:'facturas',
    para:'Facturas, proformas y recibís, cada tipo con su serie.',
    claves:'facturas proforma serie inv cobro impuesto',
    estado:d => d.facturas == null ? null
      : [d.facturas + ' emitidas' + (d.facturasAnuladas ? ' · ' + d.facturasAnuladas + ' anuladas' : ''), false] },
  { grupo:'Administración', nombre:'Recibos', icon:'ph-hand-coins', href:'/facturas/?tipo=recibi', herr:'facturas',
    para:'Justificantes de pago y señales.',
    claves:'recibi recibos justificante señal pago',
    estado:d => d.recibis == null ? null : [d.recibis + ' emitidos', false] },

  { grupo:'Base de datos', nombre:'Proyectos', icon:'ph-buildings', href:'/proyectos/', herr:'unidades',
    para:'Inventario de parcelas y villas con su estado de venta, por proyecto.',
    claves:'proyectos unidades parcelas villas inventario disponible carpetas',
    estado:d => d.unidades == null ? null
      : d.unidades === 0 ? ['Sin inventario cargado', true]
      : [d.unidades + ' unidades · ' + d.unidadesLibres + ' disponibles', false] },
  { grupo:'Base de datos', nombre:'Obra', icon:'ph-crane-tower', href:'/obra/', herr:'obra',
    para:'Fase, fecha de entrega y fotos de cada unidad — lo que ve el comprador en su portal.',
    claves:'obra construccion fases fotos avance portal entrega',
    estado:d => d.obraActivas == null ? null
      : d.obraActivas === 0 ? ['Sin unidades en obra', true]
      : [d.obraActivas + ' en obra', false] },
  { grupo:'Base de datos', nombre:'Compradores', icon:'ph-identification-card', href:'/compradores/', herr:'compradores',
    para:'Ficha del comprador y documentación KYC, con caducidades.',
    claves:'compradores kyc pasaporte fichas clientes caducidad',
    estado:d => d.compradores == null ? null : [d.compradores + ' fichas', false] },

  { grupo:'Equipo', nombre:'Usuarios', icon:'ph-users-three', href:'/usuarios/', herr:'usuarios', soloAdmin:true,
    para:'Quién entra, con qué rol y qué herramientas ve cada uno.',
    claves:'usuarios permisos roles equipo acceso',
    estado:d => d.usuarios == null ? null
      : [d.usuarios + ' con acceso' + (d.usuariosInactivos ? ' · ' + d.usuariosInactivos + ' desactivados' : ''), false] },
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
  (!t.soloAdmin || lwEsAdmin(ficha)) &&
  (!ficha || lwEsSuper(ficha) || !t.herr ||
   [].concat(t.herr).some(h => (ficha.herramientas || []).includes(h)));

/* ═══════════════════════════════════════════════════════════════════════════
   LOS PERMISOS SALEN DE ESTE MISMO CATÁLOGO — 17-ago-2026 (auditoría)
   ═══════════════════════════════════════════════════════════════════════════
   `/usuarios/` tenía su propia lista de las diez herramientas, con sus etiquetas
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
       `console.warn` de abajo lo dice en la consola de /usuarios/ en vez de
       enseñar la clave cruda de la base de datos, que es como se colaron seis
       contratos con jerga en pantalla.
   ═══════════════════════════════════════════════════════════════════════════ */
const LW_ETIQUETA_PROPIA = {
  dossier:       'Dossier',
  creatividades: 'Creatividades',
  facturas:      'Facturas y recibís',   // dos tarjetas (Facturas y Recibos), un solo permiso
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
    return [h, etiqueta || h];
  });
})();

/* Con qué entra un usuario nuevo. Vivía escrito dentro del formulario de alta de
   `/usuarios/`; está aquí para que se lea junto a la lista que gobierna. */
const LW_PERMISOS_POR_DEFECTO = ['contratos', 'facturas', 'operaciones', 'vencimientos'];

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
