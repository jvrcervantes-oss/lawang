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
    claves:'ventas seguimiento estado cuenta vencimientos',
    estado:d => d.firmasPendientes == null ? null
      : [d.firmasPendientes ? d.firmasPendientes + (d.firmasPendientes === 1 ? ' firma esperando' : ' firmas esperando') : 'Sin firmas pendientes',
         d.firmasPendientes > 0] },

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

  { grupo:'Base de datos', nombre:'Proyectos', icon:'ph-house-line', href:'/proyectos/', herr:'unidades',
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
const lwPermitida = (t, ficha) => t.soloAdmin ? lwEsAdmin(ficha)
  : (!ficha || lwEsAdmin(ficha) || !t.herr ||
     [].concat(t.herr).some(h => (ficha.herramientas || []).includes(h)));

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
