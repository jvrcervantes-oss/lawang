/* Avisos de la campana — fuente única (23-sep-2026, S17 de
   encargos/20260919_lawang_v4_paridad_lanzamiento.md).
   ----------------------------------------------------------------------------
   Vivían dentro de `topbar.js` (función `cargar()`), así que la intranet v4,
   que no carga topbar.js, solo sabía contar `notificaciones` y se perdía las
   facturas por vencer y los enlaces de firma por caducar. Copiarlos a la v4
   habría sido la segunda lista que se separa de la primera al primer retoque
   (Regla 0 de contexto/suite_lawang.md), así que se MUDAN aquí y las dos
   campanas —la de las herramientas clásicas y la de la v4— llaman a lo mismo.

   DOS ORÍGENES, a propósito (ver contracts/sql/notificaciones.sql):
   · HECHOS — tabla `notificaciones`, escrita por disparadores.
   · ALERTAS DERIVADAS — facturas con fecha de vencimiento y firmas pendientes
     que caducan, calculadas aquí en cada carga.

   QUIÉN VE QUÉ. La barrera de verdad es la RLS: `facturas` y `contrato_firmas`
   ya filtran por `es_suyo(creado_por) OR es_manager_de(proyecto)` (verificado
   en pg_policies el 23-sep-2026 — el comentario viejo de topbar.js que decía
   «la RLS deja leer todas» ya no era cierto). Hasta el 23-sep había además un
   filtro en cliente (`creado_por === email` para quien no es admin), puesto
   por `es_suyo(null) = TRUE`, que una vez coló avisos ajenos. Se RETIRA
   (LAW-276): hoy `es_suyo` es `es_admin() OR coalesce(autor = email, false)`
   — null ya es false —, así que ese filtro no protegía de nada y a cambio le
   escondía a cada manager las facturas y firmas de su equipo, que la RLS sí
   le deja ver (`es_manager_de`). La campana avisa de lo que la sesión puede
   leer, ni más ni menos.

   `nuevo` NO significa lo mismo en los dos orígenes, y se conserva tal cual:
   un hecho es nuevo si es posterior a `vistoHasta`; una factura o una firma lo
   es mientras le queden 5 días o menos, aunque ya se haya abierto la campana.

   ENLACES: solo rutas del propio dominio (`/…`, nunca `//…`). Hoy los escriben
   solo disparadores, pero un `javascript:` en `notificaciones.enlace` se
   ejecutaría al pulsar el aviso — se cambia por `#` antes de llegar a nadie.
*/
var LW_AVISOS_VENC_DIAS = 15;      // se avisa desde 15 días antes
var LW_AVISOS_LIMITE = 40;       // avisos que se enseñan
var LW_AVISOS_FILAS = 400;       // filas crudas que se piden antes de agrupar

/* TONO DE CADA AVISO (23-sep-2026, owner: «más claros con colores»). Se decide
   aquí, en la fuente única, y no en cada campana: así la clásica puede usarlo
   el día que quiera sin volver a clasificar. Cada aviso lleva:
   · `clase`: 'alerta' (pide hacer algo) o 'hecho' (algo que ya pasó);
   · `nivel`: 'mal' (vencido/caducado/rechazado) · 'atencion' (pendiente de
     alguien: vence pronto, en firma) · 'ok' (hecho: firma, cobro) · 'neutro'
     (informativo: factura emitida, inventario). Mismo significado que las
     etiquetas de los listados y las fichas: una factura emitida es gris en
     todas partes.
     UN HECHO ES UNA FOTO, NO UN ESTADO VIVO (Administración, 23-sep): la
     notificación no se reescribe cuando la cosa avanza, así que un hecho
     nunca afirma un estado que pueda caducar — «Solicitud» y «Firma enviada»
     van en gris; lo que SIGUE pendiente lo avisan las alertas, que se
     calculan con el estado actual en cada carga.
     El azul de la primera versión se retiró (23-sep): no significaba nada
     en el resto de la suite;
   · `etiqueta`: la palabra corta que acompaña al color — el color solo no
     basta (daltonismo, impresión en gris).
   Un tipo de `notificaciones` que no esté en la lista cae en 'neutro' con su
   nombre: nunca desaparece por no estar clasificado. */
var LW_AVISOS_TONO_HECHO = {
  contrato_firmado:   ['ok', 'Firmado'],
  contrato_bloqueado: ['ok', 'Firmado'],
  operacion_saldada:  ['ok', 'Saldado'],
  unidad_cobrada:     ['ok', 'Cobrado'],
  solicitud_pago:     ['neutro', 'Solicitud'],   // afinado por el título abajo
  factura_emitida:    ['neutro', 'Emitida'],
  firma_enviada:      ['neutro', 'Firma enviada'],
  unidad_reservada:   ['neutro', 'Inventario'],
  unidad_bloqueada:   ['neutro', 'Inventario'],
  unidad_vendida:     ['neutro', 'Inventario'],
  unidad_disponible:  ['neutro', 'Inventario'],
  unidad_estado:      ['neutro', 'Inventario']
};
function lwAvisoTonoHecho(tipo, titulo) {
  // una solicitud de pago puede ser buena o mala noticia: lo dice su título
  if (tipo === 'solicitud_pago') {
    if (/rechazad/i.test(titulo || '')) return ['mal', 'Rechazada'];
    if (/pagad/i.test(titulo || '')) return ['ok', 'Pagada'];
    if (/aprobad/i.test(titulo || '')) return ['atencion', 'Aprobada'];   // aprobada ≠ pagada: sigue pendiente del pago
  }
  return LW_AVISOS_TONO_HECHO[tipo] || ['neutro', String(tipo || 'Aviso').replace(/_/g, ' ')];
}

/* Importe como en el resto de la suite: `lwFormatoImporte` de dinero.js
   («1.500,00 EUR», «200.000.000 IDR»). Administración, consulta de deploy
   23-sep: con Intl es-ES a pelo salía «1500 EUR» y «250,5 EUR». Si la página
   no cargó dinero.js, la misma regla escrita igual (de-DE, 0 decimales en IDR). */
function lwAvisoImporte(n, moneda) {
  if (typeof lwFormatoImporte === 'function') return lwFormatoImporte(n, moneda);
  var d = moneda === 'IDR' ? 0 : 2;
  return new Intl.NumberFormat('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d })
    .format(Number(n) || 0) + (moneda ? ' ' + moneda : '');
}

function lwAvisoEnlace(e) {
  e = String(e == null ? '' : e).trim();
  // ni espacios ni controles ni barra invertida en ningún sitio: el navegador
  // quita tabuladores y saltos de la URL, y «/\t/x» acabaría siendo «//x»
  if (/[\u0000- \u007f\\]/.test(e)) return '#';
  return (e.charAt(0) === '/' && e.charAt(1) !== '/') ? e : '#';
}

/* Pura: recibe las cuatro respuestas ya resueltas y devuelve los avisos. Aparte
   de `lwAvisos` para poder probarla en node sin base de datos (avisos.test.js). */
function lwAvisosArmar(r, opts) {
  opts = opts || {};
  var ahora = opts.ahora ? new Date(opts.ahora) : new Date();
  var vistoHasta = opts.vistoHasta ? new Date(opts.vistoHasta) : null;
  var esAdmin = !!opts.esAdmin, email = opts.email || '';
  var dias = function (f) { return f ? Math.round((new Date(f) - ahora) / 86400000) : null; };
  var datos = function (i) { return (r[i] && !r[i].error && r[i].data) || []; };

  /* UNA VEZ POR SUCESO (23-sep-2026, owner: «tengo muchísimas notificaciones
     repetidas»). Un manager solo recibe de la base SU copia, pero un admin
     las recibe TODAS: `_avisar_managers` guarda una por manager del proyecto
     (7-8 por cambio) y un cambio de parcela además deja su aviso general
     («Parcela C4 vuelve a estar disponible») junto a la copia de manager
     («Unidad C4 — disponible»). Aquí se agrupan: mismo tipo + texto +
     segundo = el mismo suceso; y la copia de manager de un cambio de parcela
     que ya tiene su aviso general, si no va dirigida a quien mira, sobra. */
  var yo = String(email || '').toLowerCase();
  var segundo = function (x) { return String(x || '').slice(0, 19); };
  var crudos = datos(0);
  /* La clave es segundo + CÓDIGO DE LA PARCELA, no el segundo solo
     (Desarrollo, consulta de deploy): varias parcelas cambian en la misma
     transacción y comparten `now()`; y `no_disponible` no deja aviso general.
     Con el segundo solo, el «Unidad Y — no_disponible» de una parcela se
     escondía porque OTRA parcela tenía aviso general en ese segundo. Los dos
     disparadores ponen el código en el título: «Parcela C4 …» (general) y
     «Unidad C4 — …» (copia de manager). */
  var codigoGeneral = function (t) {
    var m = /^Parcela (.+?) (?:reservada|bloqueada|vendida|cobrada al 100%|vuelve a estar disponible)$/.exec(t || '');
    return m ? m[1] : null;
  };
  var codigoCopia = function (t) { var m = /^Unidad (.+?) — /.exec(t || ''); return m ? m[1] : null; };
  var generalUnidad = {};
  crudos.forEach(function (n) {
    if (!/^unidad_/.test(n.tipo || '') || n.tipo === 'unidad_estado') return;
    var cod = codigoGeneral(n.titulo);
    if (cod) generalUnidad[segundo(n.creado_en) + '|' + cod] = true;
  });
  var vistos = {};
  var avisos = [];
  /* «TU …» DE OTRO (23-sep-2026, owner: «he rechazado la solicitud de un
     agente y me pone a mí como si fuese rechazada para mí»). El aviso personal
     «Tu solicitud SP-8 — rechazada» va dirigido al comercial que la pidió;
     un admin lo recibe de la base porque puede leerlo todo, y se le leía como
     suyo. Para quien NO es el destinatario se le quita el «Tu»: queda
     «Solicitud SP-8 — rechazada», que además se funde con la copia de los
     managers del mismo segundo. No se esconde: si la solicitud no tenía
     contrato no hay copia de managers, y el admin se quedaría sin saberlo. */
  var ajeno = function (n) { return !!n.destinatario && String(n.destinatario).toLowerCase() !== yo; };
  var sinTu = function (t) { var r = String(t || '').replace(/^Tu /, ''); return r.charAt(0).toUpperCase() + r.slice(1); };
  crudos.forEach(function (n) {
    var seg = segundo(n.creado_en);
    if (n.tipo === 'unidad_estado' && ajeno(n) && generalUnidad[seg + '|' + codigoCopia(n.titulo)]) return;
    if (ajeno(n) && /^Tu /.test(n.titulo || '')) n = Object.assign({}, n, { titulo: sinTu(n.titulo) });
    var clave = (n.tipo || '') + '|' + (n.titulo || '') + '|' + seg;
    if (vistos[clave]) return;
    vistos[clave] = true;
    var tono = lwAvisoTonoHecho(n.tipo, n.titulo);
    avisos.push({ titulo: n.titulo, detalle: n.detalle, enlace: lwAvisoEnlace(n.enlace), cuando: n.creado_en,
             nuevo: !vistoHasta || new Date(n.creado_en) > vistoHasta,
             clase: 'hecho', nivel: tono[0], etiqueta: tono[1] });
  });

  var pendientes = {};
  datos(3).forEach(function (x) { pendientes[x.factura_id] = Number(x.pendiente) || 0; });
  /* Sin lo cobrado no hay avisos de facturas (Administración, 23-sep-2026): con
     la RPC caída se tomaba el total como pendiente y las facturas YA pagadas
     salían «sin cobrar» — el mismo fallo que se cerró el 19-ago, volviendo por
     la puerta del error. Mejor callar esas y decir que falta un dato
     (`cobroSinComprobar`) que avisar de deudas que no existen. */
  var cobroSinComprobar = !r[3] || !!r[3].error;

  if (!cobroSinComprobar) datos(1).forEach(function (f) {
    if (f.anulada || f.tipo === 'proforma' || f.tipo === 'recibi' || !f.venc) return;
    // ya cobrada: no es una deuda, y decir «sin cobrar» de algo cobrado
    // es peor que no avisar (19-ago-2026)
    var queda = pendientes[f.id] != null ? pendientes[f.id] : Number(f.total) || 0;
    if (!(queda > 0.005)) return;
    var d = dias(f.venc);
    if (d === null || d > LW_AVISOS_VENC_DIAS) return;
    avisos.push({
      titulo: 'Factura ' + (f.numero || 'sin nº') + (d < 0 ? ' vencida hace ' + (-d) + ' d'
              : d === 0 ? ' vence hoy' : ' vence en ' + d + ' d'),
      // lo que QUEDA, no el total: con un pago a cuenta el total exageraba la deuda
      detalle: lwAvisoImporte(queda, f.moneda) + ' sin cobrar',
      enlace: f.contrato_id ? '/intranet/operaciones/?contrato=' + encodeURIComponent(f.contrato_id) : '/intranet/facturas/',
      cuando: f.venc, nuevo: d <= 5,
      clase: 'alerta', nivel: d < 0 ? 'mal' : 'atencion', etiqueta: d < 0 ? 'Vencida' : (d === 0 ? 'Vence hoy' : 'Por vencer'),
    });
  });

  datos(2).forEach(function (s) {
    var c = s.contratos || {};
    var d = dias(s.expira_en);
    if (d === null || d > LW_AVISOS_VENC_DIAS) return;
    avisos.push({
      titulo: 'Enlace de firma de ' + (c.numero || 'un contrato') +
              (d < 0 ? ' caducado' : d === 0 ? ' caduca hoy' : ' caduca en ' + d + ' d'),
      detalle: s.firmante_nombre || '',
      enlace: '/intranet/operaciones/?contrato=' + encodeURIComponent(s.contrato_id),
      cuando: s.expira_en, nuevo: d <= 5,
      clase: 'alerta', nivel: d < 0 ? 'mal' : 'atencion', etiqueta: d < 0 ? 'Firma caducada' : 'Firma por caducar',
    });
  });

  avisos.sort(function (a, b) { return new Date(b.cuando) - new Date(a.cuando); });
  var lista = avisos.slice(0, LW_AVISOS_LIMITE);
  return { avisos: lista, sinLeer: avisos.filter(function (a) { return a.nuevo; }).length, cobroSinComprobar: cobroSinComprobar };
}

/* Las cuatro consultas + el armado. Devuelve una promesa de
   `{avisos, sinLeer, fallos}`; `fallos` cuenta las consultas que volvieron con
   error, para que quien pinta no confunda «no hay avisos» con «no se pudieron
   leer». */
function lwAvisos(sb, opts) {
  /* Se piden más filas de las que se enseñan (LW_AVISOS_FILAS): un admin
     recibe de la base una copia por manager de cada aviso, y se agrupan en
     lwAvisosArmar — con 40 filas crudas apenas cabían 5 sucesos. */
  var q = sb.from('notificaciones')
    .select('tipo,titulo,detalle,enlace,creado_en,destinatario')
    .order('creado_en', { ascending: false }).limit(LW_AVISOS_FILAS);
  // Vencimientos: facturas con fecha puesta y sin anular. `venc` vive dentro
  // del jsonb, igual que en Operaciones — no hay columna propia.
  /* El filtro va EN la consulta (Administración, 23-sep-2026): antes era un
     `.limit(200)` a pelo y el descarte de proformas/recibís/anuladas se hacía
     después, en el navegador. Con 434 facturas, un admin recibía 200
     cualesquiera y podía perder avisos de las que sí vencen. Se conserva la
     misma regla (fuera proforma y recibí, fuera anuladas, con fecha puesta);
     el filtro de abajo se queda igual como red. */
  var qf = sb.from('facturas')
    .select('id,numero,total,moneda,contrato_id,creado_por,anulada,tipo,venc:datos->fields->>fecha_vencimiento')
    .not('tipo', 'in', '(proforma,recibi)')
    .eq('anulada', false)
    .not('datos->fields->>fecha_vencimiento', 'is', null)
    .order('datos->fields->>fecha_vencimiento', { ascending: true })
    .limit(1000);
  var qs = sb.from('contrato_firmas')
    .select('firmante_nombre,estado,expira_en,contrato_id,contratos(numero,creado_por)')
    .eq('estado', 'pendiente').limit(100);
  /* Lo que queda por cobrar de cada factura — 19-ago-2026. La campana avisaba
     de facturas vencidas SIN mirar si ya estaban cobradas. */
  var qp = sb.rpc('facturas_pendiente_equipo');
  return Promise.all([q, qf, qs, qp]).then(function (r) {
    var out = lwAvisosArmar(r, opts);
    out.fallos = r.filter(function (x) { return !x || x.error; }).length;
    return out;
  });
}

if (typeof module !== 'undefined') module.exports = { lwAvisosArmar: lwAvisosArmar, lwAvisoEnlace: lwAvisoEnlace, lwAvisoTonoHecho: lwAvisoTonoHecho };
