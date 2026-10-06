/* ═══════════════════════════════════════════════════════════════════════════
   asistente-contrato.js — ASISTENTE DE NUEVO CONTRATO (F7, 30-sep-2026)
   ═══════════════════════════════════════════════════════════════════════════
   QUÉ ES. Una capa encima del generador de siempre (contracts/app.html), no
   otra página: pregunta lo mínimo paso a paso y, al final, RELLENA el mismo
   formulario con las mismas funciones del motor (resetBorrador, loadTemplate,
   enlazarFicha, cargarUnidadesDelProyecto, derivarContrato…). Lo que guarda,
   valida, numera y firma sigue siendo el editor. Encargo:
   encargos/20260930_lawang_equipos_venta_asistente.md (decisiones W1-W4 del
   owner y maqueta aprobada).

   POR QUÉ UNA CAPA Y NO UNA PÁGINA. El 26-sep una copia de app.html se quedó
   vieja en el mismo aterrizaje (entraron tres arreglos de otra sesión solo en
   una). Un solo motor, dos entradas.

   CONVIVE. `?nuevo=1` a pelo es el formulario clásico, exactamente como hoy:
   este fichero no hace nada sin `?asistente=1` (lo llama init() de app.html).
   Desde el 30-sep-2026 (noche, owner: «muéstralo ya a todo el mundo, quiero que
   lo testeen») el botón de /intranet/v4/contratos/ manda aquí a TODOS los roles,
   sin bandera — ver `contratos` en intranet/v4/assets/editores.js. Lo que la
   bandera tapaba sigue sin hacer: el servidor aún no guarda el modo (F5b).
   «Saltar el asistente» también sale para todos (owner, 30-sep: «Encender y
   abrir a todos»): lleva al mismo formulario clásico que ya está debajo.
   `?asistente=1` ya no es una bandera de acceso, es solo la ruta que distingue
   las dos entradas; quien lo tenga guardado en un enlace entra al asistente.

   «CON MI EQUIPO / POR MI CUENTA». Se pregunta aquí y, al montar el borrador,
   pasa al campo «Venta» del editor (siembraVenta, F5b 30-sep-2026), que es lo
   único que viaja a `contrato_guarda` como la clave `venta` (nunca en `datos`:
   ningún campo con `name=` en #form). Su dueño es `contrato_closer.modo`.
   Ese campo vive también en este fichero: ver «CAMPO VENTA» más abajo.

   ESTADO. En `sessionStorage` (por pestaña) solo como comodidad: si cierras y
   vuelves, o vas al alta de cliente y vuelves, sigues donde estabas. No es la
   fuente de nada: se borra al crear el borrador, y sin él se empieza de cero.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var T = function (s) { return (typeof window.lwT === 'function') ? window.lwT(s) : s; };
  var LLAVE = 'lw-asistente-contrato';
  var UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  /* Los tres tipos que SIGUEN a una venta que ya existe (cuelgan de otro
     contrato): en «venta nueva» salen apagados con el motivo, y se hacen desde
     «Seguir una venta». Es la definición del camino, no un catálogo: el nombre,
     el permiso y el orden siguen saliendo de TEMPLATES y CONTRACT_TIPO. */
  var SIGUE_A_VENTA = ['construccion', 'poa', 'adenda'];
  var ORIGENES = [
    ['contacto_personal', 'Contacto personal'],
    ['referido_cliente', 'Referido de un cliente mío'],
    ['redes_propias', 'Mis redes propias'],
    ['otro', 'Otro']
  ];
  var DESC = { reserva_parcela: 'Compra del suelo con su calendario de pagos.', hak_sewa_notario: 'Arrendamiento del terreno ante notario.',
               acuerdo_comercial: 'Con un colaborador o una agencia.' };
  var ICO = { reserva_parcela: 'lock', construccion: 'foundation', hak_sewa_notario: 'gavel',
              poa: 'approval_delegation', adenda: 'post_add', acuerdo_comercial: 'handshake',
              protocolo_operativo: 'engineering' };

  var S = null;          // lo que contesta la persona (se persiste)
  var RT = {};           // lo que se lee o se calcula (no se persiste)
  var raiz = null;       // el nodo del asistente, mientras está abierto
  var montando = false;

  /* ── los avisos del editor no tapan el asistente (30-sep-2026, visto por el CEO en la captura B1) ──
     Con la capa abierta, el editor de debajo sigue trabajando: al cargar la plantilla por defecto
     lanzaba «Esta plantilla no tiene ninguna cuenta de cobro…» ENCIMA del asistente, y hablaba de
     una plantilla que la persona ni ha elegido. toast()/toastMal() de app.html preguntan a
     `retiene()` y, mientras la capa está abierta, sus avisos esperan en COLA:
       · al montar el borrador se descartan SOLO los avisos que hablan de la plantilla por defecto
         (DE_PLANTILLA: la plantilla montada los repite si le tocan); un fallo de carga de init()
         —campos sin leer, cuenta del proyecto, credenciales de firmantes— NO se tira nunca
         (revisión de código, 30-sep: descartarlo todo callaba justo esos);
       · todo lo demás se enseña al cerrar la capa, junto: los rojos en un aviso, los de
         confirmación en otro, con «Borrador montado» al final (un toast pisaba al anterior);
       · «Saltar el asistente» sí enseña lo retenido: esa plantilla es la que se queda delante.
     Empieza a retener al evaluarse este fichero —va sin defer, antes de init()—, porque init()
     construye el formulario por defecto ANTES de abrir el asistente. Los avisos del propio
     asistente (avisa/avisaMal) no se retienen salvo durante el montaje. Sin `?asistente=1` no se
     retiene nada: el camino clásico no cambia. */
  var COLA = [], propio = false;
  var reteniendo = (function () {
    try { var p = new URLSearchParams(location.search); return p.get('asistente') === '1' && p.has('nuevo') && !p.get('contrato'); }
    catch (_) { return false; /* MUDO A PROPOSITO: sin URLSearchParams no hay asistente que abrir; no se retiene nada */ }
  })();
  function retiene(tipo, msg) {
    if (!reteniendo || (propio && !montando)) return false;
    COLA.push([tipo, msg]); return true;
  }
  function vaciaCola(mostrar) {
    var c = COLA; COLA = [];
    if (!mostrar || !c.length) return;
    var malos = [], buenos = [];
    c.forEach(function (x) { var l = x[0] === 'mal' ? malos : buenos; if (l.indexOf(x[1]) === -1) l.push(x[1]); });
    var antes = reteniendo; reteniendo = false;
    try { if (buenos.length) toast(buenos.join(' · ')); if (malos.length) toastMal(malos.join('\n')); } finally { reteniendo = antes; }
  }
  // Avisos que solo hablan de la plantilla cargada: al montar otra, los de la de por defecto sobran.
  var DE_PLANTILLA = ['Esta plantilla no tiene ninguna cuenta de cobro habilitada. Un super admin las marca en Cuentas bancarias (Intranet).'];
  function sueltaAvisosDePlantilla() {
    var fuera = DE_PLANTILLA.map(T);
    COLA = COLA.filter(function (x) { return fuera.indexOf(x[1]) === -1; });
  }
  function avisa(m) { propio = true; try { toast(m); } finally { propio = false; } }
  function avisaMal(m) { propio = true; try { toastMal(m); } finally { propio = false; } }

  function nuevoEstado() {
    return { v: 1, quien: (typeof MI_EMAIL !== 'undefined' ? MI_EMAIL : ''), camino: null, paso: 0,
      modo: null, origen: '', frase: '', slug: null, cliente: null, proyecto: '', parcelas: [],
      carta: { importe: '', fecha: '', validez: '' }, bloqueo: { pct: '', motivo: '' },
      obra: { modelo: '', techoId: '', fpago: 'estandar' }, clausulas: '', venta: null, montado: false };
  }
  function guarda() {
    /* Con el borrador ya montado no se guarda nada más: el siguiente «Nuevo contrato» no puede
       arrancar con el cliente y la parcela de este (revisión de código, 30-sep). */
    if (S && S.montado) return;
    try { sessionStorage.setItem(LLAVE, JSON.stringify(S)); } catch (_) { /* MUDO A PROPOSITO: sin sessionStorage (privado, bloqueado) el asistente funciona igual; solo no recuerda al volver */ }
  }
  function lee() {
    try {
      var x = JSON.parse(sessionStorage.getItem(LLAVE) || 'null');
      if (x && x.v === 1 && x.quien === (typeof MI_EMAIL !== 'undefined' ? MI_EMAIL : '')) return x;
    } catch (_) { /* MUDO A PROPOSITO: un estado ilegible es un asistente que empieza de cero, que es lo seguro */ }
    return null;
  }
  function olvida() {
    try { sessionStorage.removeItem(LLAVE); } catch (_) { /* MUDO A PROPOSITO: ver guarda() */ }
  }

  function e(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function q(sel) { return raiz ? raiz.querySelector(sel) : null; }
  function tipoDe(slug) { return slug ? CONTRACT_TIPO[slug] : null; }
  function plantilla(slug) { return TEMPLATES.find(function (t) { return t.slug === slug; }) || null; }
  function nombre(slug) { var t = plantilla(slug); return t ? L(t.name) : ''; }
  function esCarta(slug) { return !!slug && lwEsPreliminar(tipoDe(slug)); }
  function ofrecida(slug) { return plantillasOfrecidas().some(function (t) { return t.slug === slug; }); }
  function slugDeTipo(tipo) { return TIPO_SLUG[tipo]; }

  /* ── qué pide cada plantilla: se mira su propio texto, no una lista a mano ── */
  RT.marcas = {};
  function marcas(slug) {
    if (RT.marcas[slug]) return Promise.resolve(RT.marcas[slug]);
    var t = plantilla(slug);
    if (!t) return Promise.resolve({ cliente: false, proyecto: false, parcela: false, reserva: false, fecha: false, validez: false });
    return fetch(t.file + '?v=' + Date.now()).then(function (r) { return r.text(); }).then(function (h) {
      var m = { cliente: h.indexOf('{{adq1_nombre}}') !== -1, proyecto: h.indexOf('{{proyecto_nombre}}') !== -1,
        parcela: h.indexOf('{{parcela_codigo}}') !== -1, reserva: h.indexOf('{{precio_reserva}}') !== -1,
        fecha: h.indexOf('{{fecha_pago_reserva}}') !== -1, validez: h.indexOf('{{validez_dias}}') !== -1 };
      RT.marcas[slug] = m; return m;
    }, function () {
      // Sin la plantilla no se sabe qué pide: se preguntan todos los pasos, que es lo seguro.
      return { cliente: true, proyecto: true, parcela: true, reserva: true, fecha: true, validez: true, fallo: true };
    });
  }

  /* ── ¿está en un equipo de venta activo? (lo lee la RLS: su fila y su equipo) ── */
  function equipoDelUsuario() {
    if (RT.equipo) return Promise.resolve(RT.equipo);
    var yo = String(MI_EMAIL || '').toLowerCase(), hoy = hoyLocalISO();
    return Promise.all([
      Promise.resolve(cargarEquipo()).catch(function () { /* MUDO A PROPOSITO: sin nombres se enseña el email del Sales Manager, que también lo identifica */ }),
      sb.from('equipo_miembros').select('equipo_id,closer_email,desde,hasta'),
      sb.from('equipos_venta').select('id,nombre,manager_email,activo').eq('activo', true)
    ]).then(function (r) {
      r = r.slice(1);
      if (r[0].error || r[1].error) return (RT.equipo = { fallo: true });
      var eqs = r[1].data || [];
      var mia = (r[0].data || []).find(function (m) {
        return String(m.closer_email || '').toLowerCase() === yo && (!m.desde || m.desde <= hoy) && (!m.hasta || m.hasta >= hoy)
          && eqs.some(function (x) { return x.id === m.equipo_id; });
      });
      /* Solo cuenta ser MIEMBRO (F5b, 30-sep): es lo que mira el servidor (contrato_closer.equipo_id sale de
         equipo_miembros a la fecha de la venta). Un SM que dirige un equipo sin ser miembro vende «sin equipo»
         para el servidor: antes se le preguntaba igual y «Con mi equipo» acababa en «No estás en ningún equipo».
         Si es miembro Y manager de su equipo, «por su cuenta» sale apagado: cobra la fee de manager. */
      var eq = mia ? eqs.find(function (x) { return x.id === mia.equipo_id; }) : null;
      return (RT.equipo = eq ? { en: true, nombre: eq.nombre, sm: eq.manager_email,
        soySM: String(eq.manager_email || '').toLowerCase() === yo } : { en: false });
    }, function () { return (RT.equipo = { fallo: true }); });
  }
  /* ¿Exige ya el servidor declarar la venta? (interruptor comisiones_interruptor.modo_obligatorio, solo el
     booleano por modo_obligatorio_activo). true / false, o null si no se ha podido mirar: entonces se dice
     que no se sabe y decide el servidor al guardar. Se pregunta solo a quien está en un equipo. */
  function obligatorio() {
    if (RT.oblig !== undefined) return Promise.resolve(RT.oblig);
    return Promise.resolve(sb.rpc('modo_obligatorio_activo')).then(function (r) {
      return (RT.oblig = r.error ? null : r.data === true);
    }, function () { return (RT.oblig = null); });
  }
  function avisoPrueba() {
    if (RT.oblig === true) return '';
    if (RT.oblig === null) return aviso('aviso', 'help', e(T('No he podido comprobar si esta respuesta ya es obligatoria: al guardar lo decide el servidor.')));
    return aviso('info', 'info', e(T('Prueba: esta respuesta todavía no se guarda en el contrato. Se activará cuando el servidor la compruebe.')));
  }
  var MOTIVO_SM = 'Eres el Sales Manager de este equipo: tu venta cobra la fee de manager, no es por tu cuenta.';
  function smVisible() { return RT.equipo && RT.equipo.sm ? autorVisible(RT.equipo.sm) : ''; }

  /* ── cláusulas negociadas (REV03, 2-oct-2026, owner) ─────────────────────── */
  /* Paso SOLO para admin/super_admin y solo en las dos plantillas que llevan el selector
     `clausulas_negociadas` (Bloqueo de Parcela y Construcción). Pide elegir a conciencia:
     «Estándar» o «Negociadas (REV03)», sin valor por defecto, porque una Construcción que
     sigue a una Parcela REV03 llega con el valor heredado y «estándar» tiene que poder
     quitarlo. Un agente no ve el paso; el candado real es el trigger
     clausulas_negociadas_rol de la base. */
  var SLUGS_REV03 = ['ppjb_parcela', 'ppjb_construccion'];
  /* Lo que se preselecciona: lo que ya lleva la venta que se continúa (derivarContrato lo copia),
     para que QUITARLO sea una elección visible y no un clic sin saberlo (revisor, 2-oct-2026).
     Venta nueva: nada, se elige. Se recalcula al cambiar de venta o de tipo. */
  function clausulasDeSalida() { return (S.camino === 'existente' && S.venta && S.venta.rev03) ? 'rev03' : ''; }
  function pideClausulas() {
    return SLUGS_REV03.indexOf(S.slug) !== -1 && typeof MI_ROL !== 'undefined' && ['super_admin', 'admin'].indexOf(MI_ROL) !== -1;
  }

  /* ── los pasos ─────────────────────────────────────────────────────────── */
  function pasos() {
    var p = [['inicio', T('Nuevo o existente')]];
    if (!S.camino) return p;
    var m = S.slug ? RT.marcas[S.slug] : null;
    if (S.camino === 'existente') {
      p.push(['venta', T('La venta')], ['tipo', T('Qué contrato sigue')]);
      if (!S.slug || pideCondiciones()) p.push(['cond', T('Lo que falta')]);
      if (pideClausulas()) p.push(['clausulas', T('Cláusulas')]);
      p.push(['rev', T('Revisión')]);
      return p;
    }
    if (RT.equipo && (RT.equipo.en || RT.equipo.fallo)) p.push(['modo', T('Equipo o tu cuenta')]);
    p.push(['tipo', T('Tipo de contrato')]);
    if (!m || m.cliente) p.push(['cliente', T('Cliente')]);
    if (!m || m.proyecto || m.parcela) p.push(['parcela', T('Proyecto y parcela')]);
    if (!S.slug || pideCondiciones()) p.push(['cond', T('Condiciones')]);
    if (pideClausulas()) p.push(['clausulas', T('Cláusulas')]);
    p.push(['rev', T('Revisión')]);
    return p;
  }
  function pideCondiciones() {
    var t = tipoDe(S.slug), m = RT.marcas[S.slug] || {};
    if (esCarta(S.slug)) return !!(m.reserva || m.fecha || m.validez);
    return t === 'reserva_parcela' || t === 'construccion';
  }
  function pasoActual() { var ps = pasos(); if (S.paso > ps.length - 1) S.paso = ps.length - 1; return ps[S.paso][0]; }

  function num(v) { return (typeof parseImporte === 'function') ? (parseImporte(v) || 0) : (parseFloat(v) || 0); }
  /* El % de descuento se lee con el MISMO parseo que el importe del editor (parseImporte →
     lwParseImporte: «7,5» y «7.5» valen 7,5). app.html no tiene función de tope en %: lo
     comprueba en guardarContrato() contra el importe (dc > base × 0,15, sin tope para super
     admin) y el trigger lo repite. Esto solo evita llegar al editor con algo que va a rechazar. */
  var TOPE_DESCUENTO_PCT = 15;
  function pctDescuento() { return num(S.bloqueo.pct); }
  function descuentoFueraDeTope(pct) { return !ES_SUPER && pct > TOPE_DESCUENTO_PCT; }
  function listo(k) {
    if (k === 'inicio') return !!S.camino;
    if (k === 'modo') return !!S.modo && !(S.modo === 'propia' && (RT.equipo.soySM || !S.origen || (S.origen === 'otro' && !S.frase.trim())));
    if (k === 'venta') return !!(S.venta && !S.venta.liberado_en);
    if (k === 'tipo') return !!S.slug && (S.camino === 'existente'
      ? !!opcionExistente(S.slug) && !opcionExistente(S.slug).off
      : ofrecida(S.slug) && SIGUE_A_VENTA.indexOf(tipoDe(S.slug)) === -1);
    if (k === 'cliente') return !!S.cliente;
    if (k === 'clausulas') return S.clausulas === 'estandar' || S.clausulas === 'rev03';
    if (k === 'parcela') {
      var m = RT.marcas[S.slug] || {};
      if (!S.proyecto) return false;
      if (!m.parcela) return true;
      if (!S.parcelas.length) return false;
      // Con el inventario a la vista, cada elegida tiene que poder cogerse con el tipo de AHORA
      // (una parcela de Carta vale para un Bloqueo y no para otra Carta).
      if (RT.inv && RT.inv.proyecto === S.proyecto && RT.inv.lista) {
        return S.parcelas.every(function (c) { var u = RT.inv.lista.find(function (x) { return x.codigo === c; }); return u && estadoParcela(u).ok; });
      }
      return false;
    }
    if (k === 'cond') {
      var t = tipoDe(S.slug), mm = RT.marcas[S.slug] || {};
      if (esCarta(S.slug)) {
        if (mm.reserva && !(num(S.carta.importe) > 0)) return false;
        if (mm.fecha && !/^\d{4}-\d{2}-\d{2}$/.test(S.carta.fecha)) return false;
        if (mm.validez && S.carta.validez !== '' && (parseInt(S.carta.validez, 10) || 0) < VALIDEZ_DIAS_MINIMO) return false;
        return true;
      }
      if (t === 'reserva_parcela') {
        var pct = pctDescuento();
        if (pct < 0 || descuentoFueraDeTope(pct) || pct >= 100) return false;
        return !(pct > 0 && !S.bloqueo.motivo.trim());
      }
      if (t === 'construccion') {
        if (RT.modelos && RT.modelos.lista && RT.modelos.lista.length && !S.obra.modelo) return false;
        if (S.obra.modelo && RT.techos && RT.techos.modelo === S.obra.modelo && (RT.techos.lista || []).length && !S.obra.techoId) return false;
        return !!S.obra.fpago;
      }
      return true;
    }
    return true;
  }

  /* ── opciones de «venta existente» ─────────────────────────────────────── */
  function opcionesExistente() {
    var v = S.venta; if (!v) return [];
    var ops = [], parcelas = String(v.parcela_codigo || '').split(',').map(function (x) { return x.trim(); }).filter(Boolean);
    if (lwEsPreliminar(v.tipo)) ops.push({ slug: 'ppjb_parcela', toca: true, texto: T('Pasar a Bloqueo de Parcela'),
      desc: T('Copia cliente y parcela, y descuenta al guardar lo ya cobrado con la Carta.') });
    if (v.tipo === 'reserva_parcela') {
      var hechas = RT.construcciones == null ? 0 : RT.construcciones;
      var lleno = RT.construcciones != null && hechas >= Math.max(parcelas.length, 1);
      ops.push({ slug: 'ppjb_construccion', toca: !lleno, texto: nombre('ppjb_construccion'),
        desc: T('Se enlaza a este Bloqueo con su cliente y su parcela; el precio de la obra sale del modelo y el techo.'),
        off: lleno ? T('Este Bloqueo ya tiene un Contrato de Construcción por cada parcela.') : null });
    }
    ops.push({ slug: slugDeTipo('poa'), texto: nombre(slugDeTipo('poa')), desc: T('Para que un apoderado firme por el cliente.') });
    ops.push({ slug: slugDeTipo('adenda'), texto: nombre(slugDeTipo('adenda')), desc: T('Cambia este contrato firmado sin rehacerlo.'),
      off: v.bloqueado ? null : T('Una Adenda cambia un contrato ya firmado. Este aún no lo está: se corrige en el propio contrato.') });
    ops.forEach(function (o) { if (!o.off && !ofrecida(o.slug)) o.off = T('No lo tienes permitido.'); });
    return ops;
  }
  function opcionExistente(slug) { return opcionesExistente().find(function (o) { return o.slug === slug; }) || null; }

  /* ── pintar ─────────────────────────────────────────────────────────────── */
  function opcion(accion, valor, sel, ico, titulo, desc, extra) {
    extra = extra || {};
    var off = !!extra.off;
    return '<button type="button" class="asi-op' + (sel ? ' sel' : '') + (off ? ' off' : '') + '"' +
      (off ? ' disabled aria-disabled="true" title="' + e(extra.off) + '"' : ' data-asi="' + accion + '" data-v="' + e(valor) + '"') +
      ' aria-pressed="' + (sel ? 'true' : 'false') + '">' +
      '<span class="asi-ico" data-ico="' + e(ico) + '" aria-hidden="true"></span>' +
      '<b>' + e(titulo) + '</b>' + (desc ? '<small>' + e(desc) + '</small>' : '') +
      (off ? '<small class="asi-motivo">' + e(extra.off) + '</small>' : '') +
      (extra.tag ? '<span class="asi-tag">' + e(extra.tag) + '</span>' : '') + '</button>';
  }
  function aviso(tono, ico, html) {
    return '<div class="asi-aviso ' + tono + '" role="status"><span data-ico="' + ico + '" aria-hidden="true"></span><span>' + html + '</span></div>';
  }
  function modoTxt() {
    if (S.camino === 'existente') return T('Equipo o por su cuenta: se hereda de la venta');
    if (!RT.equipo || (!RT.equipo.en && !RT.equipo.fallo)) return T('Sin equipo');
    if (S.modo === 'equipo') return T('Con mi equipo') + (smVisible() ? ' · ' + smVisible() : '');
    if (S.modo === 'propia') return T('Por mi cuenta');
    return '';
  }

  var P = {
    inicio: function () {
      return '<h2 id="asi-h">' + e(T('¿Qué vas a hacer?')) + '</h2><p class="asi-q">' +
        e(T('Si continúas una venta, copio lo que ya tiene y solo te pregunto lo que falta.')) + '</p><div class="asi-ops">' +
        opcion('camino', 'nueva', S.camino === 'nueva', 'add_circle', T('Empezar una venta nueva'), T('Carta de Reserva, Bloqueo de Parcela directo, Hak Sewa u otro documento.')) +
        opcion('camino', 'existente', S.camino === 'existente', 'link', T('Seguir una venta que ya existe'), T('Construcción de un Bloqueo, pasar una Carta a Bloqueo, Poder Notarial o Adenda.')) +
        '</div>';
    },
    modo: function () {
      var h = '<h2 id="asi-h">' + e(T('¿Esta venta es con tu equipo o por tu cuenta?')) + '</h2>';
      if (RT.equipo.fallo) h += aviso('mal', 'error', e(T(RT.oblig === true ? 'No se ha podido comprobar si estás en un equipo de venta. Elige igualmente; si no lo estás, elige «Por mi cuenta»: el servidor rechaza «Con mi equipo».' : 'No se ha podido comprobar si estás en un equipo de venta. Elige igualmente: si no lo estás, no cambia nada.')));
      else h += '<p class="asi-q">' + e(T('Estás en el equipo')) + ' <b>' + e(RT.equipo.nombre || '') + '</b>' +
        (smVisible() ? ' · ' + e(T('Sales Manager')) + ': <b>' + e(smVisible()) + '</b>' : '') + '.</p>';
      h += '<div class="asi-ops">' +
        opcion('modo', 'equipo', S.modo === 'equipo', 'groups', T('Con mi equipo'), T('Entra el equipo entero del día de la venta. El reparto lo lleva tu Sales Manager.')) +
        opcion('modo', 'propia', S.modo === 'propia', 'person', T('Por mi cuenta'), T('Cliente tuyo, sin el equipo. Tu Sales Manager tiene 7 días para objetar.'),
          { off: RT.equipo.soySM ? T(MOTIVO_SM) : '' }) + '</div>';
      if (S.modo === 'propia') {
        h += '<div class="asi-dos"><div class="asi-fld"><label for="asi-origen">' + e(T('¿De dónde sale este cliente?')) + '</label>' +
          '<select id="asi-origen" data-asi-campo="origen"><option value="">' + e(T('Elige una opción')) + '</option>' +
          ORIGENES.map(function (o) { return '<option value="' + o[0] + '"' + (S.origen === o[0] ? ' selected' : '') + '>' + e(T(o[1])) + '</option>'; }).join('') +
          '</select></div><div class="asi-fld"><label for="asi-frase">' + e(T('En una frase')) + (S.origen === 'otro' ? '' : ' <i>(' + e(T('opcional')) + ')</i>') + '</label>' +
          '<input id="asi-frase" data-asi-campo="frase" maxlength="200" value="' + e(S.frase) + '"></div></div>';
      }
      h += avisoPrueba();
      return h;
    },
    tipo: function () {
      if (S.camino === 'existente') {
        var v = S.venta;
        return '<h2 id="asi-h">' + e(T('¿Qué contrato sigue?')) + '</h2><p class="asi-q">' + e(v.numero) + ' · ' + e(v.comprador_nombre || '—') + '</p>' +
          (RT.construcciones === 'fallo' ? aviso('mal', 'error', e(T('No se ha podido comprobar si este Bloqueo ya tiene Construcción.'))) : '') +
          '<div class="asi-ops">' + opcionesExistente().map(function (o) {
            return opcion('tipo', o.slug, S.slug === o.slug, ICO[tipoDe(o.slug)] || 'description', o.texto, o.desc,
              { off: o.off, tag: o.toca && !o.off ? T('Le toca') : '' });
          }).join('') + '</div>';
      }
      var ofre = plantillasOfrecidas().filter(function (t) { return tipoDe(t.slug); });
      var sigue = function (t) { return SIGUE_A_VENTA.indexOf(tipoDe(t.slug)) !== -1; };
      var cartas = ofre.filter(function (t) { return esCarta(t.slug); });
      var resto = ofre.filter(function (t) { return !esCarta(t.slug) && !sigue(t); });
      var principal = resto.filter(function (t) { return t.num; });
      var otros = resto.filter(function (t) { return !t.num; });
      var siguen = ofre.filter(sigue);
      var vetadas = TEMPLATES.filter(function (t) { return !t.disabled && tipoDe(t.slug) && !puedeEmitir(t.slug) && !estaArchivada(t.slug); });
      var card = function (t) { return opcion('tipo', t.slug, S.slug === t.slug, ICO[tipoDe(t.slug)] || 'description', L(t.name), DESC[tipoDe(t.slug)] ? T(DESC[tipoDe(t.slug)]) : ''); };
      var h = '<h2 id="asi-h">' + e(T('¿Qué contrato vas a hacer?')) + '</h2><p class="asi-q">' + e(T('Solo ves los tipos que tienes permitidos.')) + '</p><div class="asi-ops">';
      if (cartas.length) {
        var selCarta = esCarta(S.slug);
        h += opcion('carta', (selCarta ? S.slug : cartas[0].slug), selCarta, 'bookmark_added', T('Carta de Reserva'),
          T('El cliente paga una reserva y aparta la parcela unos días.'), { tag: cartas.length > 1 ? cartas.length + ' ' + T('variantes') : '' });
      }
      h += principal.map(card).join('') + '</div>';
      if (esCarta(S.slug) && cartas.length > 1) {
        h += '<div class="asi-fld asi-corto"><label for="asi-variante">' + e(T('Variante de Carta')) + '</label><select id="asi-variante" data-asi-campo="variante">' +
          cartas.map(function (t) { return '<option value="' + e(t.slug) + '"' + (t.slug === S.slug ? ' selected' : '') + '>' + e(L(t.name)) + '</option>'; }).join('') + '</select></div>';
      }
      if (otros.length) h += '<div class="asi-grp">' + e(T('Otros')) + '</div><div class="asi-ops asi-ops-3">' + otros.map(card).join('') + '</div>';
      /* Apagados CON su motivo, en una línea cada grupo: lo que sigue a una venta existente
         (se hace por el otro camino) y lo que su permiso no incluye. */
      if (siguen.length) h += '<p class="asi-apagados"><span data-ico="link" aria-hidden="true"></span><span><b>' + e(siguen.map(function (t) { return L(t.name); }).join(' · ')) + '</b>: ' +
        e(T('siguen a una venta que ya existe: vuelve al primer paso y elige «Seguir una venta».')) + '</span></p>';
      if (vetadas.length) h += '<p class="asi-apagados"><span data-ico="lock" aria-hidden="true"></span><span><b>' + e(vetadas.map(function (t) { return L(t.name); }).join(' · ')) + '</b>: ' +
        e(T('no los tienes permitidos. Pídeselos a un administrador.')) + '</span></p>';
      if (!ofre.length) h += aviso('mal', 'block', e(T('No tienes ningún tipo de contrato asignado. Pídeselo a un administrador antes de empezar.')));
      return h;
    },
    cliente: function () {
      var h = '<h2 id="asi-h">' + e(T('¿Para qué cliente?')) + '</h2>';
      if (S.cliente) {
        h += '<div class="asi-elegido"><span class="asi-av">' + e(iniciales(S.cliente.full_name)) + '</span><div><b>' + e(S.cliente.full_name || '—') + '</b><small>' +
          e([S.cliente.email, S.cliente.passport_number].filter(Boolean).join(' · ') || T('sin email ni pasaporte')) + '</small></div>' +
          '<button type="button" class="asi-btn fantasma" data-asi="cambia-cliente">' + e(T('Cambiar de cliente')) + '</button></div>';
      } else {
        h += '<p class="asi-q">' + e(T('Búscalo y elígelo, o dalo de alta si es nuevo.')) + '</p>' +
          '<div class="asi-buscar cli-buscar"><span data-ico="search" aria-hidden="true"></span><input type="search" id="asi-buscar-cliente" autocomplete="off" aria-label="' + e(T('Buscar cliente')) + '" placeholder="' + e(T('Nombre, email o pasaporte…')) + '">' +
          '<div class="cli-resultados" id="asi-res-cliente" hidden></div></div>';
      }
      /* F5b: los cruces por identidad (tel., email, pasaporte) los hace el servidor AL GUARDAR; no hay
         previsualización. Se avisa aquí de lo que puede pasar, y el resultado llega al guardar. */
      if (S.camino === 'nueva' && S.modo === 'propia' && RT.equipo && RT.equipo.en)
        h += aviso('info', 'info', e(T('Por tu cuenta: al guardar se comprueba este cliente contra los leads de tu equipo. Si es un lead que te asignó tu Sales Manager, la venta no podrá ser por tu cuenta; si vino de campañas o lo llevaba otra persona del equipo, tu Sales Manager recibe el aviso.')));
      h += '<div class="asi-alta"><button type="button" class="asi-btn fantasma" data-asi="alta-cliente"><span data-ico="person_add" aria-hidden="true"></span>' + e(T('Dar de alta un cliente nuevo')) + '</button>' +
        '<span>' + e(T('Al guardarlo vuelves aquí con él elegido.')) + '</span></div>';
      return h;
    },
    parcela: function () {
      var m = RT.marcas[S.slug] || {};
      var h = '<h2 id="asi-h">' + e(m.parcela ? T('¿Qué proyecto y qué parcela?') : T('¿Qué proyecto?')) + '</h2>';
      if (!RT.proyectos) return h + '<p class="asi-q">' + e(T('Cargando…')) + '</p>';
      if (RT.proyectos.fallo) return h + aviso('mal', 'error', e(T('No se han podido leer los proyectos. Recarga la página.')));
      if (!RT.proyectos.lista.length) return h + aviso('mal', 'block', e(T('No tienes ningún proyecto asignado. Pídeselo a un administrador.')));
      h += '<div class="asi-fld asi-corto"><label for="asi-proyecto">' + e(T('Proyecto (solo los tuyos)')) + '</label><select id="asi-proyecto" data-asi-campo="proyecto"><option value=""></option>' +
        RT.proyectos.lista.map(function (p) { return '<option value="' + e(p.nombre) + '"' + (p.nombre === S.proyecto ? ' selected' : '') + '>' + e(p.nombre) + '</option>'; }).join('') + '</select></div>';
      if (!m.parcela || !S.proyecto) return h;
      var inv = RT.inv;
      if (!inv || inv.proyecto !== S.proyecto) return h + '<p class="asi-q">' + e(T('Cargando el inventario…')) + '</p>';
      if (inv.fallo) return h + aviso('mal', 'error', e(T('No se ha podido leer el inventario de este proyecto. La parcela no se puede elegir hasta que cargue: recarga la página.')));
      if (!inv.lista.length) return h + aviso('aviso', 'warning', e(T('Este proyecto no tiene parcelas en el inventario. Cárgalas en Proyectos y vuelve: la parcela no se escribe a mano.')));
      var malas = S.parcelas.filter(function (c) { var u = inv.lista.find(function (x) { return x.codigo === c; }); return !u || !estadoParcela(u).ok; });
      if (malas.length) h += aviso('mal', 'block', e(T('Con este tipo de contrato no se puede coger:')) + ' <b>' + e(malas.join(', ')) + '</b>. ' + e(T('Quítala para seguir.')));
      h += '<p class="asi-q">' + e(T('Puedes elegir varias.')) + '</p><div class="asi-plots">' + inv.lista.map(function (u) {
        var st = estadoParcela(u), sel = S.parcelas.indexOf(u.codigo) !== -1;
        // elegida y ya no válida (se cambió de tipo o de cliente): apagada pero pulsable, para poder
        // QUITARLA; y la de otro agente, pulsable para preguntar a la base
        var pulsable = st.ok || sel || st.pulsable;
        return '<button type="button" class="asi-plot' + (sel ? ' sel' : '') + (st.ok || st.pulsable ? '' : ' off') + '"' +
          (pulsable ? ' data-asi="parcela" data-v="' + e(u.codigo) + '"' + (st.ok ? '' : ' title="' + e(st.nota) + '"') : ' disabled title="' + e(st.nota) + '"') +
          ' aria-pressed="' + (sel ? 'true' : 'false') + '"><b>' + e(u.codigo) + '</b><small>' + e(st.nota) + '</small></button>';
      }).join('') + '</div>';
      return h;
    },
    cond: function () {
      var t = tipoDe(S.slug), m = RT.marcas[S.slug] || {};
      if (esCarta(S.slug)) {
        var h = '<h2 id="asi-h">' + e(T('Condiciones de la Carta')) + '</h2><p class="asi-q">' + e(T('Lo mínimo. El resto lo completas en el editor viendo el documento.')) + '</p><div class="asi-dos">';
        if (m.reserva) h += '<div class="asi-fld"><label for="asi-importe">' + e(T('Importe de reserva')) + '</label><input id="asi-importe" inputmode="decimal" data-asi-campo="importe" value="' + e(S.carta.importe) + '"></div>';
        if (m.fecha) h += '<div class="asi-fld"><label for="asi-fecha">' + e(T('Fecha de pago de la cuota')) + '</label><input id="asi-fecha" type="date" data-asi-campo="fecha" value="' + e(S.carta.fecha) + '"></div>';
        h += '</div>';
        if (m.validez) h += '<div class="asi-fld asi-corto"><label for="asi-validez">' + e(T('La reserva se mantiene (días)')) + ' <i>(' + e(T('mínimo')) + ' ' + VALIDEZ_DIAS_MINIMO + ')</i></label><input id="asi-validez" type="number" min="' + VALIDEZ_DIAS_MINIMO + '" step="1" data-asi-campo="validez" value="' + e(S.carta.validez) + '" placeholder="' + VALIDEZ_DIAS_MINIMO + '"></div>';
        return h;
      }
      if (t === 'reserva_parcela') {
        var h2 = '<h2 id="asi-h">' + e(T('Condiciones del Bloqueo')) + '</h2>';
        if (S.camino === 'existente') h2 += aviso('ok', 'check_circle', e(T('Lo ya cobrado con la Carta se descontará solo al guardar el Bloqueo.')));
        h2 += '<p class="asi-q">' + e(T('El precio es el del suelo en el inventario. Un descuento comercial resta de él.')) + '</p>';
        var puede = typeof puedeFijosEstudio === 'function' && puedeFijosEstudio();
        var tope = ES_SUPER ? '' : ' · ' + T('máximo') + ' ' + TOPE_DESCUENTO_PCT;
        h2 += '<div class="asi-dos"><div class="asi-fld"><label for="asi-pct">' + e(T('Descuento (%)')) + e(tope) + '</label><input id="asi-pct" inputmode="decimal" data-asi-campo="pct" value="' + e(S.bloqueo.pct) + '"' +
          (puede ? '' : ' disabled title="' + e(T('El descuento comercial solo lo ponen un Sales Manager o administración.')) + '"') + ' placeholder="0"></div>';
        var pct = pctDescuento();
        if (pct > 0) h2 += '<div class="asi-fld"><label for="asi-motivo">' + e(T('Motivo del descuento')) + '</label><input id="asi-motivo" data-asi-campo="motivo" maxlength="200" value="' + e(S.bloqueo.motivo) + '"></div>';
        h2 += '</div>';
        if (!puede) h2 += aviso('info', 'info', e(T('El descuento comercial solo lo ponen un Sales Manager o administración.')));
        if (descuentoFueraDeTope(pct)) h2 += aviso('mal', 'block', e(T('El descuento comercial no puede superar el 15% del precio del suelo.')));
        return h2;
      }
      if (t === 'construccion') {
        var h3 = '<h2 id="asi-h">' + e(T('Condiciones de la Construcción')) + '</h2><p class="asi-q">' + e(T('Cliente y parcela vienen del Bloqueo.')) + '</p>';
        if (!RT.modelos) return h3 + '<p class="asi-q">' + e(T('Cargando…')) + '</p>';
        if (RT.modelos.fallo) h3 += aviso('mal', 'error', e(T('No se ha podido leer el catálogo de modelos: el modelo y el techo se eligen en el editor.')));
        else if (!RT.modelos.lista.length) h3 += aviso('aviso', 'warning', e(T('Este proyecto no tiene modelos declarados: el modelo se elige en el editor.')));
        else {
          h3 += '<div class="asi-fld asi-corto"><label for="asi-modelo">' + e(T('Modelo de villa')) + '</label><select id="asi-modelo" data-asi-campo="modelo"><option value=""></option>' +
            RT.modelos.lista.map(function (x) { return '<option value="' + e(x) + '"' + (x === S.obra.modelo ? ' selected' : '') + '>' + e(x) + '</option>'; }).join('') + '</select></div>';
          if (S.obra.modelo) {
            var tt = RT.techos;
            if (!tt || tt.modelo !== S.obra.modelo) h3 += '<p class="asi-q">' + e(T('Cargando los techos…')) + '</p>';
            else if (tt.fallo) h3 += aviso('mal', 'error', e(T('No se han podido leer los techos de este modelo: se elige en el editor.')));
            else if (tt.lista.length) {
              h3 += '<div class="asi-grp">' + e(T('Techo')) + '</div><div class="asi-ops asi-ops-3">' + tt.lista.map(function (x) {
                return opcion('techo', x.techo_id, String(S.obra.techoId) === String(x.techo_id), 'roofing', x.nombre || '—',
                  fmtImporte(Number(x.precio)) + ' ' + (x.moneda || ''));
              }).join('') + '</div>';
            }
          }
        }
        h3 += '<div class="asi-grp">' + e(T('Forma de pago')) + '</div><div class="asi-ops asi-ops-3">' + FORMAS_PAGO.map(function (f) {
          return opcion('fpago', f.cal, S.obra.fpago === f.cal, f.ico, L(f.tit), L(f.rep));
        }).join('') + '</div>';
        return h3;
      }
      return '';
    },
    venta: function () {
      var h = '<h2 id="asi-h">' + e(T('¿Qué venta continúas?')) + '</h2><div class="asi-buscar"><span data-ico="search" aria-hidden="true"></span>' +
        '<input type="search" id="asi-buscar-venta" data-asi-campo="buscar-venta" autocomplete="off" aria-label="' + e(T('Buscar venta')) + '" placeholder="' + e(T('Cliente o número de contrato')) + '" value="' + e(RT.qVenta || '') + '"></div>';
      h += '<div class="asi-res" id="asi-res-venta">' + resultadosVenta() + '</div>';
      h += '<p class="asi-q asi-nota">' + e(T('Solo salen las ventas que puedes ver. Cliente y parcela se heredan.')) + '</p>';
      return h;
    },
    clausulas: function () {
      return '<h2 id="asi-h">' + e(T('¿Qué cláusulas lleva este contrato?')) + '</h2><div class="asi-ops">' +
        opcion('clausulas', 'estandar', S.clausulas === 'estandar', 'check', T('Estándar'),
          T('El texto de siempre, el que firman todos los compradores.')) +
        opcion('clausulas', 'rev03', S.clausulas === 'rev03', 'gavel', T('Negociadas (REV03)'),
          T('Las cláusulas pactadas por escrito con este comprador (ver «Cláusulas negociadas» en el editor).')) +
        '</div>' + (S.venta && S.venta.rev03 ? aviso('aviso', 'info', e(T('La venta que continúas lleva cláusulas negociadas (REV03). Si eliges «Estándar», este contrato sale sin ellas.'))) : '') +
        '<p class="asi-q asi-nota">' + e(T('Solo lo ves tú como administración. Se puede cambiar después en el editor, en «Gestión del contrato».')) + '</p>';
    },
    rev: function () {
      var m = RT.marcas[S.slug] || {}, t = tipoDe(S.slug);
      var cli = S.camino === 'existente' ? (S.venta.comprador_nombre || '—') + ' · ' + T('heredado') : (S.cliente ? S.cliente.full_name : '—');
      var par = S.camino === 'existente'
        ? [S.venta.proyecto_nombre, S.venta.parcela_codigo].filter(Boolean).join(' · ') + ' · ' + T('heredada')
        : [S.proyecto, S.parcelas.join(', ')].filter(Boolean).join(' · ') || '—';
      var cond = '—';
      if (esCarta(S.slug)) cond = [m.reserva ? fmtImporte(num(S.carta.importe)) : '', m.fecha ? T('pago') + ' ' + S.carta.fecha : '',
        m.validez ? (S.carta.validez || VALIDEZ_DIAS_MINIMO) + ' ' + T('días') : ''].filter(Boolean).join(' · ');
      else if (t === 'reserva_parcela') cond = (pctDescuento()) > 0 ? T('Descuento') + ' ' + S.bloqueo.pct + ' % · ' + S.bloqueo.motivo : T('Sin descuento');
      else if (t === 'construccion') {
        var tc = RT.techos && (RT.techos.lista || []).find(function (x) { return String(x.techo_id) === String(S.obra.techoId); });
        var fp = FORMAS_PAGO.find(function (f) { return f.cal === S.obra.fpago; });
        cond = [S.obra.modelo, tc ? tc.nombre : '', fp ? L(fp.tit) : ''].filter(Boolean).join(' · ') || '—';
      }
      var filas = [];
      if (modoTxt()) filas.push([T('Venta'), modoTxt()]);
      filas.push([T('Contrato'), nombre(S.slug)]);
      if (S.camino === 'existente') filas.push([T('Sigue a'), S.venta.numero]);
      if (S.camino === 'existente' || m.cliente) filas.push([T('Cliente'), cli]);
      if (S.camino === 'existente' || m.proyecto || m.parcela) filas.push([T('Parcela'), par]);
      if (pideCondiciones()) filas.push([T('Condiciones'), cond]);
      if (pideClausulas()) filas.push([T('Cláusulas'), S.clausulas === 'rev03' ? T('Negociadas (REV03)')
        : T('Estándar') + (S.venta && S.venta.rev03 ? ' · ' + T('quita las negociadas de la venta') : '')]);
      var prueba = S.camino === 'nueva' && S.modo;
      var h = '<h2 id="asi-h">' + e(T('Revisa y crea el borrador')) + '</h2><dl class="asi-sum">' +
        filas.map(function (f) { return '<dt>' + e(f[0]) + '</dt><dd>' + e(f[1]) + '</dd>'; }).join('') + '</dl>' +
        '<p class="asi-q asi-nota">' + e(T('Se abre el editor de siempre con el documento montado. Nada se guarda, se envía ni se firma todavía.')) + '</p>' +
        (prueba ? avisoPrueba() : '');
      if (S.camino === 'existente' && tipoDe(S.slug) === 'construccion') {
        var n = String(S.venta.parcela_codigo || '').split(',').filter(function (x) { return x.trim(); }).length;
        if (n > 1) h += aviso('info', 'info', e(T('Este Bloqueo tiene varias parcelas: en el editor eliges cuál es esta Construcción (una por parcela).')));
      }
      return h;
    }
  };
  function iniciales(n) { return String(n || '?').trim().split(/\s+/).slice(0, 2).map(function (x) { return x.charAt(0); }).join('').toUpperCase(); }

  /* ¿Se puede coger esta parcela con el tipo y el cliente contestados? La regla es la del
     editor (eleccionParcela → estadoTraspaso, parcela_inventario.js) con el contexto del
     asistente; aquí solo se pone en palabras. Nada se oculta: lo que no se puede coger sale
     apagado con su motivo real (revisión de código, 30-sep: la copia propia que había aquí
     daba por buenas las Cartas de otro comprador y el agente se enteraba al guardar). */
  function ctxParcela() { return { tipo: tipoDe(S.slug), ids: identificadoresDeFicha(S.cliente) }; }
  function claveCliente() { return identificadoresDeFicha(S.cliente).join('|'); }
  function estadoParcela(u) {
    var destino = tipoDe(S.slug);
    var precio = destino === 'reserva_parcela' ? u.precio_suelo : u.precio;
    var dato = [u.superficie_m2 ? u.superficie_m2 + ' m²' : '', precio != null ? fmtImporte(Number(precio)) + ' ' + (u.moneda || 'EUR') : ''].filter(Boolean).join(' · ');
    var el = eleccionParcela(u, ctxParcela());
    if (!el.tomada) return el.bloqueada ? { ok: false, nota: u.estado || T('no disponible') } : { ok: true, nota: dato || T('libre') };
    var suNum = (u.ocupante && u.ocupante.numero) || (u.traspasoRemoto && u.traspasoRemoto.numero) || T('una Carta de Reserva');
    if (el.modo === 'ok') return { ok: true, nota: T('reservada en') + ' ' + suNum + ' · ' + T('es de este cliente: pasa a este Bloqueo') };
    if (el.modo === 'otro') return { ok: false, nota: T('reservada en') + ' ' + suNum + ' · ' + T('de otro comprador') };
    if (el.modo === 'sin_datos') return { ok: false, nota: T('reservada en') + ' ' + suNum + ' · ' + T('falta el pasaporte o el email del cliente para traspasarla') };
    if (el.modo === 'por_comprobar') {
      // De otro agente: se pregunta a la base al pulsarla. Si la pregunta falló, se dice (no es «de otro comprador»).
      if (RT.comprobando === u.codigo) return { ok: false, pulsable: false, nota: T('comprobando con la base…') };
      if (u.traspasoFallo === claveCliente()) return { ok: false, pulsable: true, nota: T('no se ha podido comprobar · pulsa para reintentar') };
      return { ok: false, pulsable: true, nota: T('ocupada por un contrato de otro agente · se comprueba al elegirla') };
    }
    return { ok: false, nota: T('ya asignada') + (u.ocupante && u.ocupante.numero ? ' · ' + u.ocupante.numero : '') };
  }
  /* Parcela de otro agente: la base dice si la Carta es de ESTE cliente (parcela_traspaso_estado,
     el mismo núcleo que usa el editor). El código se fija antes del await y la parcela se congela
     mientras contesta, como en wireCampoParcela. */
  function compruebaYElige(u) {
    var codigo = u.codigo, proyecto = S.proyecto, clave = claveCliente();
    RT.comprobando = codigo; u.traspasoFallo = null; pinta();
    consultarTraspasoRemoto(u, proyecto, identificadoresDeFicha(S.cliente)).then(function () {
      if (S.proyecto !== proyecto || claveCliente() !== clave) return;
      if (estadoParcela(u).ok && S.parcelas.indexOf(codigo) === -1) S.parcelas.push(codigo);
    }, function () { u.traspasoFallo = clave; }).then(function () {
      if (RT.comprobando === codigo) RT.comprobando = null;
      guarda(); pinta();
    });
  }

  function resultadosVenta() {
    var r = RT.ventas;
    if (!r) return '<p class="asi-q">' + e(T('Cargando…')) + '</p>';
    if (r.fallo) return aviso('mal', 'error', e(T('No se han podido leer las ventas. Recarga la página.')));
    if (!r.lista.length) return '<p class="asi-q">' + e(T('Sin coincidencias.')) + '</p>';
    return r.lista.map(function (v, i) {
      var off = v.liberado_en ? T('Liberada: su parcela se soltó y ya no sigue.') : '';
      var sel = S.venta && S.venta.id === v.id;
      return '<button type="button" class="asi-ri' + (sel ? ' sel' : '') + (off ? ' off' : '') + '"' + (off ? ' disabled title="' + e(off) + '"' : ' data-asi="venta" data-v="' + i + '"') +
        ' aria-pressed="' + (sel ? 'true' : 'false') + '"><span class="asi-av"><span data-ico="description" aria-hidden="true"></span></span><div><b>' +
        e(v.numero) + ' · ' + e(TIPO_LABEL[v.tipo] || v.tipo) + '</b><small>' +
        e([v.comprador_nombre, [v.proyecto_nombre, v.parcela_codigo].filter(Boolean).join(' '), v.bloqueado ? T('firmado') : T('sin firmar'), off].filter(Boolean).join(' · ')) +
        '</small></div></button>';
    }).join('');
  }

  function pinta() {
    if (!raiz) return;
    var ps = pasos(), k = pasoActual();
    var foco = document.activeElement && document.activeElement.id;
    raiz.innerHTML =
      '<div class="asi-caja">' +
      '<nav class="asi-pasos" aria-label="' + e(T('Pasos')) + '"><h4 id="asi-titulo">' + e(T('Nuevo contrato')) + '</h4>' +
      ps.map(function (p, n) {
        var hecho = n < S.paso;
        return '<button type="button" class="asi-paso' + (n === S.paso ? ' on' : '') + (hecho ? ' hecho' : '') + '"' +
          (hecho ? ' data-asi="salta" data-v="' + n + '"' : ' disabled') + (n === S.paso ? ' aria-current="step"' : '') +
          '><span class="asi-d">' + (hecho ? '<span data-ico="check" aria-hidden="true"></span>' : (n + 1)) + '</span>' + e(p[1]) + '</button>';
      }).join('') +
      '<div class="asi-pie-lado">' + (!S.montado ? '<button type="button" class="asi-link" data-asi="saltar">' + e(T('Saltar el asistente')) + '</button>' : '') +
      '<span>' + e(T('Lo que contestes se guarda si cierras y vuelves.')) + '</span></div></nav>' +
      '<div class="asi-main"><div class="asi-top"><span class="asi-ctx">' + e(T('Paso')) + ' ' + (S.paso + 1) + ' ' + e(T('de')) + ' ' + ps.length +
      (S.paso > 0 && modoTxt() ? ' · ' + e(modoTxt()) : '') + '</span>' +
      // la misma salida en el móvil, donde el riel de pasos no se ve (suite-v4-generador.css)
      (!S.montado ? '<button type="button" class="asi-link asi-saltar-movil" data-asi="saltar">' + e(T('Saltar el asistente')) + '</button>' : '') +
      '<button type="button" class="asi-x" data-asi="cierra" aria-label="' + e(T('Cerrar')) + '"><span data-ico="close" aria-hidden="true"></span></button></div>' +
      '<div class="asi-cuerpo">' + P[k]() + '</div>' +
      '<div class="asi-pie"><button type="button" class="asi-btn fantasma" data-asi="atras"' + (S.paso === 0 ? ' disabled' : '') + '><span data-ico="arrow_back" aria-hidden="true"></span>' + e(T('Atrás')) + '</button>' +
      '<span class="asi-hint" aria-live="polite"></span>' +
      '<button type="button" class="asi-btn pri" data-asi="sigue">' + (k === 'rev'
        ? '<span data-ico="note_add" aria-hidden="true"></span>' + e(T('Crear borrador'))
        : e(T('Siguiente')) + '<span data-ico="arrow_forward" aria-hidden="true"></span>') + '</button></div>' +
      '</div></div>';
    pintaPie();
    if (k === 'cliente' && !S.cliente) cableaBuscadorCliente();
    var f = foco && q('#' + foco);
    if (f) { f.focus(); if (f.setSelectionRange && /text|search/.test(f.type)) { try { var n = f.value.length; f.setSelectionRange(n, n); } catch (_) { /* MUDO A PROPOSITO: tipos de input sin selección (number, date) */ } } }
    else { var h = q('#asi-h'); if (h) { h.setAttribute('tabindex', '-1'); h.focus({ preventScroll: true }); } }
  }
  function pintaPie() {
    var k = pasoActual(), ok = listo(k) && !montando;
    var b = q('[data-asi="sigue"]'), hint = q('.asi-hint');
    if (b) { b.disabled = !ok; if (montando) b.textContent = T('Montando el borrador…'); }
    if (hint) hint.textContent = (!listo(k) && !montando) ? T('Completa este paso para seguir') : '';
  }

  /* ── cargas por paso ─────────────────────────────────────────────────────── */
  function preparaPaso() {
    var k = pasoActual();
    if (k === 'parcela' && !RT.proyectos) {
      Promise.resolve(cargarProyectos()).then(function () {
        if (!PROYECTOS_DB) RT.proyectos = { fallo: true };
        else RT.proyectos = { lista: MIS_PROYECTOS ? PROYECTOS_DB.filter(function (p) { return MIS_PROYECTOS.indexOf(p.id) !== -1; }) : PROYECTOS_DB };
        pinta(); preparaPaso();
      });
    }
    if (k === 'parcela' && S.proyecto && (RT.marcas[S.slug] || {}).parcela) {
      if (!RT.inv || RT.inv.proyecto !== S.proyecto) cargaInventario();
      else if (RT.inv.lista && S.parcelas.length) revalidaElegidas(false);   // el cliente pudo cambiar: se vuelve a preguntar por las de otro agente
    }
    if (k === 'venta' && !RT.ventas) buscaVentas('');
    if (k === 'cond' && tipoDe(S.slug) === 'construccion' && !RT.modelos) cargaModelos();
  }
  function cargaInventario() {
    var p = S.proyecto;
    RT.inv = { proyecto: p, cargando: true };
    leerInventarioProyecto(p).then(function (r) {
      if (S.proyecto !== p) return;
      RT.inv = { proyecto: p, lista: r.lista, fallo: r.fallo };
      revalidaElegidas(true);
    });
  }
  /* Lo elegido antes, contra el inventario de ahora y el cliente de ahora. La de otro agente
     se vuelve a preguntar a la base (lo comprobado vive en la fila leída, que se acaba de
     releer). Con `soltar` (inventario recién leído) lo que ya no se puede coger —otro lo tomó
     entretanto— se suelta y SE DICE: soltarlo callado era el mismo fallo que ofrecerlo. Sin
     `soltar` (volver al paso) se queda elegida y apagada con su motivo, para quitarla a mano. */
  function revalidaElegidas(soltar) {
    var inv = RT.inv; if (!inv || !inv.lista || inv.proyecto !== S.proyecto) return;
    var fuera = [], pendientes = [];
    S.parcelas = S.parcelas.filter(function (c) {
      var u = inv.lista.find(function (x) { return x.codigo === c; });
      var st = u ? estadoParcela(u) : null;
      if (st && st.ok) return true;
      if (st && st.pulsable && u.traspasoFallo !== claveCliente()) { pendientes.push(u); return true; }
      if (!soltar) return true;
      fuera.push(c); return false;
    });
    if (fuera.length) avisaMal(T('Ya no se puede coger con este contrato y este cliente:') + ' ' + fuera.join(', ') + '. ' + T('La he quitado.'));
    guarda(); pinta();
    pendientes.forEach(function (u) {
      var proyecto = S.proyecto, clave = claveCliente();
      consultarTraspasoRemoto(u, proyecto, identificadoresDeFicha(S.cliente)).then(function () {
        if (S.proyecto !== proyecto || claveCliente() !== clave) return;
        if (soltar && !estadoParcela(u).ok) {
          S.parcelas = S.parcelas.filter(function (c) { return c !== u.codigo; });
          avisaMal(T('Ya no se puede coger con este contrato y este cliente:') + ' ' + u.codigo + ' · ' + estadoParcela(u).nota);
        }
      }, function () { u.traspasoFallo = clave; }).then(function () { guarda(); pinta(); });
    });
  }
  function proyectoDeObra() { return S.camino === 'existente' ? (S.venta.proyecto_nombre || '') : S.proyecto; }
  function cargaModelos() {
    RT.modelos = null;
    Promise.all([Promise.resolve(cargarModelos()), Promise.resolve(cargarProyectos())]).then(function () {
      if (!CATALOGO_MODELOS) RT.modelos = { fallo: true };
      else RT.modelos = { lista: proyectoDeObra() ? lwModelosDeProyecto(proyectoDeObra(), CATALOGO_MODELOS.villas, CATALOGO_MODELOS.catalogo).lista.map(function (m) { return m.modelo; }) : [] };
      if (S.obra.modelo && RT.modelos.lista && RT.modelos.lista.indexOf(S.obra.modelo) === -1) { S.obra.modelo = ''; S.obra.techoId = ''; }
      pinta();
      if (S.obra.modelo) cargaTechos();
    }, function () { RT.modelos = { fallo: true }; pinta(); });
  }
  function cargaTechos() {
    var modelo = S.obra.modelo, ficha = fichaDelModelo(modelo);
    var proy = (PROYECTOS_DB || []).find(function (p) { return p.nombre === proyectoDeObra(); });
    RT.techos = null;
    if (!ficha) { RT.techos = { modelo: modelo, lista: [] }; pinta(); return; }
    Promise.resolve(leerTechosModelo(ficha.id, proy ? proy.id : null)).then(function (r) {
      if (S.obra.modelo !== modelo) return;
      RT.techos = { modelo: modelo, lista: r.error ? [] : (r.data || []), fallo: !!r.error };
      if (S.obra.techoId && !RT.techos.lista.some(function (x) { return String(x.techo_id) === String(S.obra.techoId); })) S.obra.techoId = '';
      guarda(); pinta();
    }, function () { RT.techos = { modelo: modelo, lista: [], fallo: true }; pinta(); });
  }
  var tVenta = null;
  function buscaVentas(texto) {
    RT.qVenta = texto;
    var limpio = String(texto || '').replace(/[%_,()*\\]/g, '').trim();
    var consulta = sb.rpc('contratos_equipo')
      .select('id,numero,tipo,comprador_nombre,proyecto_nombre,parcela_codigo,bloqueado,liberado_en,fecha_firma,created_at,rev03:datos_fields->>clausulas_negociadas');
    if (limpio.length >= 2) consulta = consulta.or('numero.ilike.%' + limpio + '%,comprador_nombre.ilike.%' + limpio + '%');
    var yo = texto;
    Promise.resolve(consulta.not('numero', 'is', null).order('created_at', { ascending: false }).limit(10)).then(function (r) {
      if (RT.qVenta !== yo) return;
      RT.ventas = r.error ? { fallo: true } : { lista: r.data || [] };
      var caja = q('#asi-res-venta'); if (caja) caja.innerHTML = resultadosVenta(); else pinta();
    }, function () { RT.ventas = { fallo: true }; var caja = q('#asi-res-venta'); if (caja) caja.innerHTML = resultadosVenta(); });
  }
  function cuentaConstrucciones(v, alLlegar) {
    Promise.resolve(sb.rpc('contratos_equipo').select('id').eq('contrato_padre_id', v.id).eq('tipo', 'construccion')).then(function (r) {
      if (!S.venta || S.venta.id !== v.id) return;
      RT.construcciones = r.error ? 'fallo' : (r.data || []).length;
      if (alLlegar) alLlegar();
      pinta();
    }, function () { RT.construcciones = 'fallo'; pinta(); });
  }
  function eligeVenta(v) {
    S.venta = { id: v.id, numero: v.numero, tipo: v.tipo, comprador_nombre: v.comprador_nombre, proyecto_nombre: v.proyecto_nombre,
      parcela_codigo: v.parcela_codigo, bloqueado: !!v.bloqueado, fecha_firma: v.fecha_firma, liberado_en: v.liberado_en,
      rev03: v.rev03 === 'si' };
    S.slug = null; RT.construcciones = null; RT.modelos = null; RT.techos = null;
    S.clausulas = clausulasDeSalida();
    S.obra = { modelo: '', techoId: '', fpago: 'estandar' };
    if (v.tipo === 'reserva_parcela') cuentaConstrucciones(v, preseleccionaExistente);
    else preseleccionaExistente();
  }
  function preseleccionaExistente() {
    var toca = opcionesExistente().find(function (o) { return o.toca && !o.off; });
    if (toca && !S.slug) S.slug = toca.slug;
    guarda();
  }
  function cableaBuscadorCliente() {
    var input = q('#asi-buscar-cliente'), res = q('#asi-res-cliente');
    wireClienteBuscadorEn(input, res, function (datos, fila) {
      if (!fila || !fila.id) { avisaMal(T('Ese resultado no tiene ficha: elige un cliente registrado')); return; }
      S.cliente = { id: fila.id, full_name: fila.full_name, email: fila.email, passport_number: fila.passport_number, tipo: fila.tipo };
      guarda(); pinta();
    });
  }

  /* ── navegación ──────────────────────────────────────────────────────────── */
  function siguiente() {
    var k = pasoActual();
    if (!listo(k) || montando) return;
    if (k === 'rev') {
      var ps = pasos(), falta = -1;
      for (var n = 0; n < ps.length - 1; n++) if (!listo(ps[n][0])) { falta = n; break; }
      if (falta !== -1) { S.paso = falta; guarda(); pinta(); preparaPaso(); avisaMal(T('Falta completar este paso antes de crear el borrador.')); return; }
      monta(); return;
    }
    var paso = function () { S.paso++; guarda(); pinta(); preparaPaso(); };
    if (k === 'tipo' && S.slug) { marcas(S.slug).then(paso); return; }
    paso();
  }
  function alClic(ev) {
    var b = ev.target.closest('[data-asi]'); if (!b || b.disabled || !raiz.contains(b)) return;
    var a = b.getAttribute('data-asi'), v = b.getAttribute('data-v');
    if (a === 'cierra') return cierra();
    if (a === 'saltar') return saltar();
    if (a === 'sigue') return siguiente();
    if (a === 'atras') { S.paso = Math.max(0, S.paso - 1); guarda(); pinta(); preparaPaso(); return; }
    if (a === 'salta') { S.paso = +v; guarda(); pinta(); preparaPaso(); return; }
    if (a === 'camino') { if (S.camino !== v) { var viejo = S; S = nuevoEstado(); S.camino = v; S.cliente = viejo.cliente; } }
    else if (a === 'modo') { S.modo = v; if (v !== 'propia') { S.origen = ''; S.frase = ''; } }
    else if (a === 'tipo' || a === 'carta') { if (S.slug !== v) { S.slug = v; S.parcelas = S.parcelas || []; S.clausulas = clausulasDeSalida(); } marcas(v).then(function () { pinta(); }); }
    else if (a === 'venta') { var r = RT.ventas && RT.ventas.lista && RT.ventas.lista[+v]; if (r) eligeVenta(r); }
    else if (a === 'cambia-cliente') { S.cliente = null; }
    else if (a === 'alta-cliente') return altaCliente();
    else if (a === 'parcela') {
      var i = S.parcelas.indexOf(v);
      if (i !== -1) S.parcelas.splice(i, 1);
      else {
        var u = RT.inv && RT.inv.lista && RT.inv.lista.find(function (x) { return x.codigo === v; });
        if (!u || RT.comprobando) return;
        var st = estadoParcela(u);
        if (st.ok) S.parcelas.push(v);
        else if (st.pulsable) return compruebaYElige(u);
        else return;
      }
    }
    else if (a === 'techo') { S.obra.techoId = v; }
    else if (a === 'fpago') { S.obra.fpago = v; }
    else if (a === 'clausulas') { S.clausulas = v; }
    else return;
    guarda(); pinta();
  }
  function alCambiar(ev) {
    var c = ev.target.getAttribute && ev.target.getAttribute('data-asi-campo'); if (!c) return;
    var val = ev.target.value;
    if (c === 'origen') { S.origen = val; guarda(); pinta(); return; }
    if (c === 'variante') { S.slug = val; S.clausulas = clausulasDeSalida(); marcas(val).then(function () { guarda(); pinta(); }); return; }
    if (c === 'proyecto') { S.proyecto = val; S.parcelas = []; RT.inv = null; guarda(); pinta(); preparaPaso(); return; }
    if (c === 'modelo') { S.obra.modelo = val; S.obra.techoId = ''; RT.techos = null; guarda(); pinta(); if (val) cargaTechos(); return; }
  }
  function alTeclear(ev) {
    var c = ev.target.getAttribute && ev.target.getAttribute('data-asi-campo'); if (!c) return;
    var val = ev.target.value;
    if (c === 'frase') S.frase = val;
    else if (c === 'importe') S.carta.importe = val;
    else if (c === 'fecha') S.carta.fecha = val;
    else if (c === 'validez') S.carta.validez = val;
    else if (c === 'motivo') S.bloqueo.motivo = val;
    else if (c === 'pct') { S.bloqueo.pct = val; guarda(); pinta(); return; }   // repinta: el motivo y el tope aparecen según la cifra
    else if (c === 'buscar-venta') { clearTimeout(tVenta); tVenta = setTimeout(function () { buscaVentas(val); }, 280); return; }
    else return;
    guarda(); pintaPie();
  }
  function alTecla(ev) {
    if (ev.key === 'Escape' && raiz && !montando) { ev.preventDefault(); cierra(); return; }
    if (ev.key === 'Tab' && raiz) {   // el foco no se escapa del diálogo
      var f = raiz.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled])');
      if (!f.length) return;
      var pri = f[0], ult = f[f.length - 1];
      if (ev.shiftKey && document.activeElement === pri) { ev.preventDefault(); ult.focus(); }
      else if (!ev.shiftKey && document.activeElement === ult) { ev.preventDefault(); pri.focus(); }
    }
  }

  function montaCapa() {
    if (raiz) return;
    raiz = document.createElement('div');
    raiz.className = 'asi-velo';
    raiz.setAttribute('role', 'dialog');
    raiz.setAttribute('aria-modal', 'true');
    raiz.setAttribute('aria-labelledby', 'asi-titulo');
    raiz.addEventListener('click', alClic);
    raiz.addEventListener('change', alCambiar);
    raiz.addEventListener('input', alTeclear);
    document.addEventListener('keydown', alTecla);
    document.body.appendChild(raiz);
    document.documentElement.classList.add('asi-abierto');
    reteniendo = true;
  }
  function quitaCapa() {
    if (!raiz) return;
    document.removeEventListener('keydown', alTecla);
    raiz.remove(); raiz = null;
    document.documentElement.classList.remove('asi-abierto');
    reteniendo = false; vaciaCola(true);   // el editor ya se ve: lo retenido sale ahora
  }
  function quitaParametro() {
    try {
      var par = new URLSearchParams(location.search);
      par.delete('asistente'); par.delete('asistente_cliente');
      history.replaceState(null, '', location.pathname + '?' + par.toString());
    } catch (_) { /* MUDO A PROPOSITO: sin historial solo queda el parámetro en la barra; recargar volvería a abrir el asistente, nada más */ }
  }
  /* Cerrar (✕ o Esc): con el borrador ya montado solo se cierra la capa y se
     queda el editor; sin montar, se vuelve al listado (lo contestado queda
     guardado para cuando vuelva). */
  function cierra() {
    if (S && S.montado) { quitaCapa(); return; }
    location.href = '/intranet/v4/contratos/';
  }
  function saltar() {   // cualquier rol: el formulario clásico, en blanco, ya está debajo
    olvida(); S = null; quitaCapa(); quitaParametro();
  }
  function altaCliente() {
    guarda();
    location.href = '/intranet/v4/compradores/?nuevo=1&volver=asistente';
  }

  /* ── montar el borrador: el motor de siempre, en el orden de derivarContrato ── */
  function esperar(cond, ms) {
    return new Promise(function (ok) {
      var t0 = Date.now();
      (function mira() { if (cond() || Date.now() - t0 > ms) return ok(cond()); setTimeout(mira, 100); })();
    });
  }
  async function montaCondiciones() {
    var t = tipoDe(S.slug), m = RT.marcas[S.slug] || {};
    if (esCarta(S.slug)) {
      var f = {};
      if (m.reserva && num(S.carta.importe) > 0) f.precio_reserva = fmtImporte(num(S.carta.importe));
      if (m.fecha && S.carta.fecha) f.fecha_pago_reserva = S.carta.fecha;
      if (m.validez && S.carta.validez) f.validez_dias = String(parseInt(S.carta.validez, 10));
      populateForm(f);
    }
    if (t === 'reserva_parcela') {
      var pct = pctDescuento();
      if (pct > 0 && typeof puedeFijosEstudio === 'function' && puedeFijosEstudio()) {
        var lista = listaSueloVigente();
        if (lista == null) avisaMal(T('No se ha podido aplicar el descuento: falta el precio del suelo de la parcela en el inventario. Ponlo en el editor.'));
        else {
          // hacia abajo al céntimo: redondear podía dejar un 15 % un céntimo por ENCIMA del tope y el editor lo rechazaba al guardar
          populateForm({ descuento_comercial: fmtImporte(Math.floor(lista * pct) / 100), descuento_comercial_motivo: S.bloqueo.motivo.trim() });
          aplicarDescuentoSuelo();
        }
      }
    }
    if (t === 'construccion' && S.obra.modelo) {
      var sel = document.querySelector('[name="tipologia_construccion"]');
      if (sel) {
        populateForm({ tipologia_construccion: S.obra.modelo });
        aplicarReglasCampos();   // syncTipologiaModelos → cargarTechosYExtras (sin await: se espera abajo)
        var ficha = fichaDelModelo(S.obra.modelo);
        var proy = (PROYECTOS_DB || []).find(function (p) { return p.nombre === proyectoDeObra(); });
        var firma = ficha ? ficha.id + '§' + (proy ? proy.id : '') : null;
        if (firma) await esperar(function () { return TECHO_MODELO_HECHO === firma && !TECHO_CARGANDO; }, 8000);
        var ts = document.getElementById('techoSel');
        if (ts && S.obra.techoId && [].some.call(ts.options, function (o) { return o.value === String(S.obra.techoId); })) {
          ts.value = String(S.obra.techoId);
          // por el oyente del motor: él quita `por_defecto` (lo eligió una persona, no el software)
          ts.dispatchEvent(new Event('change', { bubbles: true }));
        } else if (S.obra.techoId) avisaMal(T('No se ha podido poner el techo elegido: elígelo en el editor.'));
      }
    }
    if (t === 'construccion' && S.obra.fpago) cambiaCalendario(S.obra.fpago);
    /* REV03: se escribe a mano y no con populateForm, que se salta los vacíos — «Estándar»
       tiene que poder QUITAR el 'si' que trae una Construcción derivada de una Parcela REV03. */
    if (pideClausulas() && (S.clausulas === 'estandar' || S.clausulas === 'rev03')) {
      var cn = document.querySelector('[name="clausulas_negociadas"]');
      if (cn) { cn.value = S.clausulas === 'rev03' ? 'si' : ''; cn.dispatchEvent(new Event('change', { bubbles: true })); }
      else if (S.clausulas === 'rev03') avisaMal(T('No se han podido poner las cláusulas negociadas: actívalas en el editor, en «Gestión del contrato».'));
    }
  }
  async function montaNueva() {
    var slug = S.slug;
    resetBorrador(slug);
    await loadTemplate(slug);
    $('#tplPick').value = slug;
    buildForm();
    if (S.cliente) {
      var r = await sb.rpc('comprador_ficha', { p_id: S.cliente.id }).maybeSingle();
      if (r.data) enlazarFicha(r.data);
      else avisaMal(T('No se ha podido leer la ficha del cliente: búscalo en el editor.'));
    }
    var proyEl = document.querySelector('[name="proyecto_nombre"]');
    if (proyEl && S.proyecto) {
      populateForm({ proyecto_nombre: S.proyecto });
      await cargarUnidadesDelProyecto(S.proyecto);
    }
    var parEl = document.querySelector('[name="parcela_codigo"]');
    /* Cierre con la regla del EDITOR, que ya tiene el tipo y el comprador reales del formulario:
       lo que el asistente eligió se vuelve a mirar aquí (la de otro agente, preguntando a la base
       con comprobarTraspasoRemoto) antes de escribirlo en el campo. Lo que no pase no se escribe
       y se dice; el guardado y el trigger siguen siendo la autoridad. */
    var validas = [], caidas = [];
    for (var i = 0; parEl && i < S.parcelas.length; i++) {
      var cod = S.parcelas[i];
      var u = (UNIDADES_PROY.lista || []).find(function (x) { return x.codigo === cod; });
      var el = u ? eleccionParcela(u) : null;
      var vale = !!el && !el.bloqueada && el.modo !== 'por_comprobar';
      if (el && el.modo === 'por_comprobar') vale = await comprobarTraspasoRemoto(u);
      (vale ? validas : caidas).push(cod);
    }
    if (caidas.length) avisaMal(T('No se ha puesto la parcela, no se puede coger con este contrato:') + ' ' + caidas.join(', ') + '. ' + T('Elígela en el editor.'));
    if (parEl && validas.length) {
      parEl.value = validas.join(', ');
      pintarSelectorParcela();
      syncDatosDeUnidad();
    }
    await montaCondiciones();
    return true;
  }
  async function montaExistente() {
    var v = S.venta, slug = S.slug;
    await openSavedContract(v.id);
    // Si no se pudo abrir, derivarContrato copiaría «el borrador actual» (la Carta en blanco de debajo)
    if (!SAVED_CONTRACT || SAVED_CONTRACT.id !== v.id) { avisaMal(T('No se ha podido abrir la venta elegida. No se ha creado nada.')); return false; }
    await derivarContrato(slug);
    var t = tipoDe(slug);
    if (t === 'poa') {
      populateForm({ poa_hs_vinculado: v.numero });
      if (!(VINCULABLES_POA || []).some(function (c) { return c.numero === v.numero; }))
        avisaMal(T('Ese contrato no está en la lista de vinculables: comprueba el vínculo del poder en el editor.'));
      aplicarReglasCampos();
    }
    if (t === 'adenda') populateForm({ adenda_contrato: v.numero, adenda_contrato_fecha: v.fecha_firma || '' });
    if (t === 'reserva_parcela' && lwEsPreliminar(v.tipo)) avisa(T('Bloqueo de Parcela con los datos de') + ' ' + v.numero + ' · ' + T('el abono ya pagado en la Carta se descontará al guardar.'));
    await montaCondiciones();
    return true;
  }
  async function monta() {
    // montar sustituye el borrador del editor: los anexos aún sin guardar se perderían (2-oct-2026)
    if (typeof confirmaSoltarPendientes === 'function' && !confirmaSoltarPendientes()) return;
    montando = true; pintaPie();
    sueltaAvisosDePlantilla();   // hablaban de la plantilla por defecto, que se va a sustituir; los fallos de carga se quedan
    var ok = false;
    try {
      ok = S.camino === 'existente' ? await montaExistente() : await montaNueva();
      if (ok) {
        aplicarReglasCampos();
        refreshHitos(); updateSaveButton(); editBtnIdle(); render();
      }
    } catch (err) {
      avisaMal(T('No se ha podido montar el borrador: ') + ((err && err.message) || err));
      ok = false;
    }
    montando = false;
    if (!ok) { vaciaCola(true); pintaPie(); return; }   // la capa sigue: lo que explicó el fallo, ahora
    S.montado = true;
    // F5b: lo que contestó en «¿con tu equipo o por tu cuenta?» pasa al campo «Venta» del editor, que es lo
    // único que viaja a contrato_guarda (una sola fuente al guardar; la persona lo ve y lo puede corregir).
    if (S.camino === 'nueva') siembraVenta(window.lwAsistente.ventaDeclarada());
    olvida();          // creado: lo que queda es el editor, no un asistente a medias
    COLA.push(['ok', T('Borrador montado. Complétalo viendo el documento y guárdalo.')]);   // sale al final, con lo retenido
    quitaCapa();
    quitaParametro();
    pintaBanda();
  }

  /* La banda del editor montado con el asistente: qué venta es y «Cambiar tipo». */
  function pintaBanda() {
    var vieja = document.querySelector('[data-asi-banda]'); if (vieja) vieja.remove();
    var inner = document.querySelector('.pane-form .inner'); if (!inner) return;
    var d = document.createElement('div');
    d.className = 'asi-banda';
    d.setAttribute('data-asi-banda', '1');
    d.innerHTML = '<span data-ico="auto_awesome" aria-hidden="true"></span><span class="asi-banda-t">' + e(T('Montado con el asistente.')) + '</span>' +
      (modoTxt() ? '<span class="asi-chip"' + (RT.oblig === true ? '' : ' title="' + e(T('Prueba: esta respuesta todavía no se guarda en el contrato. Se activará cuando el servidor la compruebe.')) + '"') + '>' +
        e(modoTxt()) + (S.camino === 'nueva' && S.modo && RT.oblig !== true ? ' · ' + e(T('prueba')) : '') + '</span>' : '') +
      '<button type="button" class="asi-btn fantasma" data-accion="asistente-cambiar-tipo"><span data-ico="swap_horiz" aria-hidden="true"></span>' + e(T('Cambiar tipo')) + '</button>' +
      '<small class="asi-motivo" data-asi-banda-motivo hidden></small>';
    inner.insertBefore(d, inner.firstChild);
    d.querySelector('[data-accion="asistente-cambiar-tipo"]').addEventListener('click', function () {
      if (guardado()) { refrescaBanda(); return; }
      reabreEnTipo(null);
    });
    refrescaBanda();
  }
  /* Guardado, el tipo ya no se cambia desde el asistente (misma regla que interceptaCambioTipo):
     el botón queda apagado CON el motivo a la vista. Lo llama updateSaveButton() de app.html,
     que es lo que corre tras cada guardado. */
  function guardado() { return !!(SAVED_CONTRACT && SAVED_CONTRACT.id); }
  function refrescaBanda() {
    var b = document.querySelector('[data-accion="asistente-cambiar-tipo"]'); if (!b) return;
    var m = document.querySelector('[data-asi-banda-motivo]');
    var off = guardado(), motivo = T('Ya está guardado: el tipo se cambia desde el selector de plantilla, como siempre.');
    b.disabled = off;
    if (off) { b.setAttribute('aria-disabled', 'true'); b.title = motivo; } else { b.removeAttribute('aria-disabled'); b.removeAttribute('title'); }
    if (m) { m.textContent = off ? motivo : ''; m.hidden = !off; }
  }
  function reabreEnTipo(slug) {
    if (slug) S.slug = slug;
    montaCapa();
    var ps = pasos();
    for (var n = 0; n < ps.length; n++) if (ps[n][0] === 'tipo') { S.paso = n; break; }
    pinta();
  }

  /* ═══ CAMPO «VENTA» DEL FORMULARIO CLÁSICO (F5b, 30-sep-2026) ══════════════
     «Venta: con mi equipo / por mi cuenta» encima del formulario, con o sin
     asistente (el asistente solo lo siembra al montar: siembraVenta). Vive aquí
     y no en app.html porque comparte con el asistente la lectura del equipo
     (equipoDelUsuario), el interruptor (obligatorio) y la lista de orígenes: una
     sola definición de cada cosa.
     · Sin equipo activo: NO se pinta nada ni se envía nada — el clásico queda
       exactamente como hoy (el servidor lo toma por «por su cuenta» implícito).
     · Solo el ALTA de un contrato RAÍZ lo declara: guardado, o colgado de otra
       venta (el mismo contrato_padre_id que resuelve contractPayload, que es lo
       que mira contrato_guarda), sale apagado con el motivo.
     · Fuera de #form y sin `name=`: collect() no lo serializa en `datos`. Su
       dueño es contrato_closer.modo; viaja SOLO como la clave `venta` de
       contrato_guarda (paraGuardar, llamado desde guardarContrato).
     · Obligatorio en pantalla solo con el interruptor encendido; apagado se
       envía igual y el servidor lo ignora (se dice: «prueba»). */
  var V = { modo: null, origen: '', frase: '', visto: null, atado: false, pedido: false };
  function siembraVenta(d) {
    if (!d) return;
    V.modo = d.modo; V.origen = d.origen || ''; V.frase = d.frase || '';
    pintaVenta();
  }
  function padreDelBorrador() {
    try { return contractPayload().contrato_padre_id || null; }
    catch (_) { return null; /* MUDO A PROPOSITO: sin plantilla cargada no hay vínculo que leer; se trata como raíz y el servidor decide */ }
  }
  function ventaAplica() { return !!(RT.equipo && (RT.equipo.en || RT.equipo.fallo)); }
  /* por qué no se puede tocar ahora mismo ('' = se puede) */
  function motivoVenta() {
    if (SAVED_CONTRACT && SAVED_CONTRACT.id) return T('Ya está guardado: lo declarado queda en la venta y solo lo cambia un administrador.');
    if (padreDelBorrador()) return T('Este contrato sigue a otra venta: hereda de ella si es con el equipo o por tu cuenta.');
    return '';
  }
  function pintaVenta() {
    var inner = document.querySelector('.pane-form .inner');
    if (!inner || typeof sb === 'undefined' || !sb) return;
    if (!V.pedido) {
      V.pedido = true;
      equipoDelUsuario().then(function () { return ventaAplica() ? obligatorio() : null; }).then(pintaVenta, pintaVenta);
      return;
    }
    var viejo = inner.querySelector('[data-venta-bloque]');
    if (!RT.equipo || !ventaAplica()) { if (viejo) viejo.remove(); return; }
    // de guardado a borrador nuevo («Limpiar», «Nuevo»): se empieza sin declarar
    var idAhora = SAVED_CONTRACT && SAVED_CONTRACT.id ? SAVED_CONTRACT.id : null;
    if (V.visto && !idAhora) { V.modo = null; V.origen = ''; V.frase = ''; }
    V.visto = idAhora;
    var off = motivoVenta(), sm = !!RT.equipo.soySM;
    if (sm && V.modo === 'propia') V.modo = null;
    var chip = off ? '' : RT.oblig === true ? T('Obligatorio') : RT.oblig === false ? T('Prueba') : '';
    var opVenta = function (v, ico, tit, desc, motivo) {
      var apag = off || motivo, sel = V.modo === v && !off;
      return '<button type="button" class="asi-op' + (sel ? ' sel' : '') + (apag ? ' off' : '') + '" data-accion="venta-modo" data-v="' + v + '"' +
        (apag ? ' disabled aria-disabled="true" title="' + e(apag) + '"' : '') + ' aria-pressed="' + (sel ? 'true' : 'false') + '">' +
        '<span class="asi-ico" data-ico="' + ico + '" aria-hidden="true"></span><b>' + e(tit) + '</b><small>' + e(desc) + '</small>' +
        (motivo && !off ? '<small class="asi-motivo">' + e(motivo) + '</small>' : '') + '</button>';
    };
    var h = '<div class="asi-venta-cab"><span data-ico="groups" aria-hidden="true"></span><b id="venta-h">' + e(T('Venta')) + '</b>' +
      (RT.equipo.en && RT.equipo.nombre ? '<span class="asi-venta-eq">' + e(RT.equipo.nombre) + '</span>' : '') +
      (chip ? '<span class="asi-chip">' + e(chip) + '</span>' : '') + '</div>' +
      '<div class="asi-ops asi-venta-ops" role="group" aria-labelledby="venta-h">' +
      opVenta('equipo', 'groups', T('Con mi equipo'), T('Entra el equipo entero del día de la venta.'), '') +
      opVenta('propia', 'person', T('Por mi cuenta'), T('Cliente tuyo, sin el equipo. Tu Sales Manager tiene 7 días para objetar.'), sm ? T(MOTIVO_SM) : '') +
      '</div>';
    if (!off && V.modo === 'propia') {
      h += '<div class="asi-dos"><div class="asi-fld"><label for="venta-origen">' + e(T('¿De dónde sale este cliente?')) + '</label>' +
        '<select id="venta-origen" data-venta-campo="origen"><option value="">' + e(T('Elige una opción')) + '</option>' +
        ORIGENES.map(function (o) { return '<option value="' + o[0] + '"' + (V.origen === o[0] ? ' selected' : '') + '>' + e(T(o[1])) + '</option>'; }).join('') +
        '</select></div><div class="asi-fld"><label for="venta-frase">' + e(T('En una frase')) + (V.origen === 'otro' ? '' : ' <i>(' + e(T('opcional')) + ')</i>') + '</label>' +
        '<input id="venta-frase" data-venta-campo="frase" maxlength="200" value="' + e(V.frase) + '"></div></div>';
    }
    if (off) h += '<p class="asi-venta-motivo">' + e(off) + '</p>';
    else if (RT.equipo.fallo) h += aviso('mal', 'error', e(T(RT.oblig === true ? 'No se ha podido comprobar si estás en un equipo de venta. Elige igualmente; si no lo estás, elige «Por mi cuenta»: el servidor rechaza «Con mi equipo».' : 'No se ha podido comprobar si estás en un equipo de venta. Elige igualmente: si no lo estás, no cambia nada.')));
    if (!off) h += avisoPrueba();
    var caja = viejo;
    if (!caja) {
      caja = document.createElement('section');
      caja.className = 'asi-venta';
      caja.setAttribute('data-venta-bloque', '1');
      var banda = inner.querySelector('[data-asi-banda]');
      inner.insertBefore(caja, banda ? banda.nextSibling : inner.firstChild);
    }
    caja.innerHTML = h;
    if (!V.atado) atarVenta();
  }
  function atarVenta() {
    V.atado = true;
    var inner = document.querySelector('.pane-form .inner');
    inner.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-accion="venta-modo"]');
      if (!b || b.disabled) return;
      // pulsar la opción ya elegida la quita: se puede volver a «sin declarar»
      V.modo = V.modo === b.getAttribute('data-v') ? null : b.getAttribute('data-v');
      if (V.modo !== 'propia') { V.origen = ''; V.frase = ''; }
      pintaVenta();
      var f = document.querySelector('[data-accion="venta-modo"][data-v="' + V.modo + '"]'); if (f) f.focus();
    });
    inner.addEventListener('input', function (ev) {
      var c = ev.target.getAttribute && ev.target.getAttribute('data-venta-campo');
      if (c === 'frase') V.frase = ev.target.value;
    });
    inner.addEventListener('change', function (ev) {
      var c = ev.target.getAttribute && ev.target.getAttribute('data-venta-campo');
      if (c === 'origen') { V.origen = ev.target.value; pintaVenta(); var s = document.getElementById('venta-origen'); if (s) s.focus(); return; }
      // un cambio del formulario puede colgarlo de otra venta (o soltarlo): se vuelve a mirar
      if (!c && ev.target.closest && ev.target.closest('#form')) pintaVenta();
    });
  }
  /* Lo que añade guardarContrato a contrato_guarda. { venta } o { error } (no se guarda y se dice por qué),
     o {} si no hay nada que enviar. padreId = el contrato_padre_id del mismo payload que se envía. */
  function ventaParaGuardar(eraNuevo, padreId) {
    if (!eraNuevo || padreId || !ventaAplica()) return {};
    if (!V.modo) return RT.oblig === true ? { error: T('Indica arriba del formulario si la venta es con tu equipo o por tu cuenta.') } : {};
    if (V.modo === 'propia') {
      /* Solo se frena el guardado con el interruptor ENCENDIDO. Apagado (o sin poder leerlo) el campo es
         «prueba»: una declaración a medias no se envía y no para un contrato real (revisión, 30-sep). */
      var falta = RT.equipo.soySM ? T(MOTIVO_SM)
        : !V.origen ? T('Por tu cuenta: indica de dónde viene el cliente.')
        : (V.origen === 'otro' && V.frase.trim().length < 3) ? T('Por tu cuenta: explica en una frase de dónde viene el cliente.') : '';
      if (falta) return RT.oblig === true ? { error: falta } : {};
    }
    return { venta: { modo: V.modo, origen: V.modo === 'propia' ? V.origen : null,
                      origen_texto: V.modo === 'propia' ? (V.frase.trim() || null) : null } };
  }
  /* Tras un alta con `venta`: lo que se añade al aviso de guardado. Sin lectura extra: los cruces van al SM
     (sin datos del cliente); el bloqueo ya habría llegado como error. Con el interruptor apagado no se dice
     nada, porque el servidor no lo ha guardado. */
  function ventaTrasGuardar(v) {
    if (!v || RT.oblig !== true) return '';
    return v.modo === 'propia'
      ? ' · ' + T('Venta por tu cuenta: tu Sales Manager tiene 7 días para objetar.')
      : ' · ' + T('Venta con tu equipo.');
  }
  window.lwVenta = { pinta: pintaVenta, paraGuardar: ventaParaGuardar, trasGuardar: ventaTrasGuardar };

  /* ── API ─────────────────────────────────────────────────────────────────── */
  window.lwAsistente = {
    abrir: async function (o) {
      o = o || {};
      if (!sb) { reteniendo = false; vaciaCola(true); return; }
      S = lee() || nuevoEstado();
      S.montado = false;
      montaCapa();
      raiz.innerHTML = '<div class="asi-caja asi-cargando"><p>' + e(T('Cargando…')) + '</p></div>';
      await equipoDelUsuario();
      if (RT.equipo.en || RT.equipo.fallo) await obligatorio();
      if (S.slug) await marcas(S.slug);
      if (o.clienteNuevo && UUID.test(o.clienteNuevo)) {
        var r = await sb.rpc('comprador_ficha', { p_id: o.clienteNuevo }).maybeSingle();
        if (r.data) {
          S.cliente = { id: r.data.id, full_name: r.data.full_name, email: r.data.email, passport_number: r.data.passport_number, tipo: r.data.tipo };
          if (!S.camino) S.camino = 'nueva';
          var ps = pasos(), ks = ps.map(function (p) { return p[0]; });
          // Sin estado guardado (sessionStorage vacío o bloqueado) no se sabe el tipo: se vuelve a él.
          var i = S.slug ? ks.indexOf('cliente') + 1 : ks.indexOf('tipo');
          if (i > 0) S.paso = Math.min(i, ps.length - 1);
          avisa(T('Cliente dado de alta y elegido: ') + (r.data.full_name || ''));
        } else avisaMal(T('No se ha podido leer la ficha recién creada: búscala en el paso del cliente.'));
        try { var par = new URLSearchParams(location.search); par.delete('asistente_cliente'); history.replaceState(null, '', location.pathname + '?' + par.toString()); }
        catch (_) { /* MUDO A PROPOSITO: ver quitaParametro() */ }
      }
      // Solo se vuelve a contar: lo que ya había elegido (tipo, modelo, techo) se conserva.
      if (S.camino === 'existente' && S.venta && S.venta.tipo === 'reserva_parcela') cuentaConstrucciones(S.venta, null);
      guarda(); pinta(); preparaPaso();
    },
    /* El #tplPick del editor montado por el asistente: vuelve al paso «tipo»
       conservando cliente y parcela, en vez de vaciar el borrador. Solo antes
       de guardar; un contrato guardado cambia de tipo como siempre. */
    interceptaCambioTipo: function (slug) {
      if (!S || !S.montado || (SAVED_CONTRACT && SAVED_CONTRACT.id)) return false;
      var sel = document.getElementById('tplPick'); if (sel) sel.value = CURRENT.slug;
      reabreEnTipo(slug);
      return true;
    },
    refrescaBanda: refrescaBanda,
    retiene: retiene,
    /* F5 · lo contestado en el paso «modo». Lo lee siembraVenta al montar el borrador; al servidor solo
       llega a través del campo «Venta» (lwVenta.paraGuardar, junto a contrato_guarda en app.html). */
    ventaDeclarada: function () {
      if (!S || S.camino !== 'nueva' || !S.modo) return null;
      return { modo: S.modo, origen: S.modo === 'propia' ? S.origen : null, frase: S.modo === 'propia' ? (S.frase.trim() || null) : null };
    }
  };
})();
