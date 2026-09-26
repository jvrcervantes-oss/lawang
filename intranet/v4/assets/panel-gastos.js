/* panel-gastos.js — la pantalla /v4/gastos/ (24-sep-2026). Módulo `gastos`.
 *
 * Misma forma que panel-finanzas.js: carga → cálculo (finGastos, en
 * contracts/assets/finanzas.js, con test) → pintado. Escribe por las tablas
 * `gastos` y `proveedores` directamente: la puerta es la RLS (es_admin() Y
 * puede('gastos')) y lo que la base protege no se repite aquí (autoría, log,
 * anulado inmutable, escrow, CHECK de pagado/anulado/PPh — migración
 * 20260924075945_gastos_proveedores.sql).
 *
 * Reglas de la suite que se cumplen aquí, con su porqué:
 *  - Toda escritura pide `.select('id')` y 0 filas = la RLS denegó: nunca
 *    «guardado» sobre nada (reference_supabase_grant_manda_antes_que_la_policy).
 *  - Formularios y fichas con los cajones compartidos (`lwVentana`, `lwCajon`,
 *    editores.js); confirmar con `lwConfirmar` (dialogo.js). Nada propio.
 *  - Un importe TECLEADO se lee con lwParseImporte; uno que viene de la base
 *    ya es número.
 *  - Los nombres (proyecto, proveedor, sociedad) se leen por su id al pintar:
 *    ni texto suelto ni espejo. */
(function () {
  'use strict';
  if (!/\/gastos\/?(index\.html)?$/.test(location.pathname)) return;

  var T = function (s) { return (typeof lwT === 'function') ? lwT(s) : s; };
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  function fmt(n, m) {
    if (n == null) return '—';
    if (typeof lwFormatoImporte === 'function') return lwFormatoImporte(n, m);
    return new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 }).format(Math.round(Number(n) || 0)) + (m ? ' ' + m : '');
  }
  function hoyLocal() {
    var d = new Date();
    return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  }
  function fFecha(x) { if (!x) return '—'; var d = new Date(String(x).slice(0, 10) + 'T12:00:00'); return isNaN(d) ? String(x) : d.toLocaleDateString(typeof lwLocale === 'function' ? lwLocale() : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); }
  var $ = function (id) { return document.getElementById(id); };
  function pon(k, t) { document.querySelectorAll('[data-gas="' + k + '"]').forEach(function (e) { e.textContent = t; }); }
  function aviso(texto, tono) {
    var caja = $('lw-gas-avisos'); if (!caja) return;
    var p = document.createElement('div'); p.setAttribute('role', 'status');
    p.className = 'rounded-xl border px-5 py-4 font-body-sm text-body-sm ' + (tono === 'mal' ? 'border-error/40 bg-error-container/40 text-on-surface' : 'border-burnt-earth/30 bg-surface-alt text-on-surface-variant');
    p.textContent = texto; caja.appendChild(p);
  }
  var errorHumano = function (e, pre) { return (window.lwErrorHumano ? window.lwErrorHumano(e, pre) : (pre + ': ' + (e && e.message || e))); };
  /* 0 filas sin error = la RLS denegó (o la fila ya no estaba). Se dice. */
  /* Por el servidor (frontera frontend/backend, 26-sep-2026): las RPCs de gastos comprueban el
     permiso y dan error si no pueden; no devuelven filas que contar. */
  function rpcOk(r, que) { return (r && r.error) ? { error: { message: que + ': ' + (r.error.message || r.error) } } : {}; }
  function nombreSociedad(clave) {
    try { var s = (typeof SOCIEDADES !== 'undefined') && SOCIEDADES[clave]; if (s && (s.razon || s.marca)) return s.razon || s.marca; } catch (e) { /* entities.js aún no cargó */ }
    return String(clave || '').replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  var ESTADO = { pendiente: ['Pendiente', 'bg-surface-container-high text-on-surface-variant'], pagado: ['Pagado', 'bg-primary-fixed text-on-primary-fixed'], anulado: ['Anulado', 'bg-surface-container text-outline line-through'], vencido: ['Vencido', 'bg-error-container text-on-error-container'] };
  var TIPO_PROV = [['constructora', 'Constructora'], ['proveedor', 'Proveedor'], ['profesional', 'Profesional'], ['administracion', 'Administración'], ['otro', 'Otro']];
  var PPH = [['', 'Sin retención'], ['pph23', 'PPh 23 (servicios)'], ['pph4_2', 'PPh 4(2) (construcción, alquiler)'], ['pph21', 'PPh 21 (persona física)'], ['pph26', 'PPh 26 (no residente)'], ['otro', 'Otra']];
  var MONEDAS = [['EUR', 'EUR'], ['IDR', 'IDR'], ['USD', 'USD']];
  function pill(estado) { var e = ESTADO[estado] || [estado, '']; return '<span class="inline-block px-2.5 py-0.5 rounded-full text-[11px] font-semibold uppercase tracking-wide ' + e[1] + '">' + esc(T(e[0])) + '</span>'; }
  function estadoVisible(g, hoy) { return g.estado === 'pendiente' && g.vence_el && g.vence_el < hoy ? 'vencido' : g.estado; }
  function limpiaNombre(n) { return String(n || 'fichero').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9._-]+/g, '_').slice(-80); }

  var sb, hoy = hoyLocal(), D = { gastos: [], proveedores: [], categorias: [], proyectos: [], cuentas: [], usuarios: {} };
  var catPorClave = {}, provPorId = {}, proyPorId = {};
  var VISTA = 'gastos', PAG = null;

  /* ── CARGA ─────────────────────────────────────────────────────────────── */
  function cargar() {
    var q = function (p, que) { return p.then(function (r) { if (r.error) { console.error('[gastos] ' + que, r.error); throw new Error(que); } return r.data || []; }); };
    return Promise.all([
      q(sb.from('gastos').select('id,sociedad,proyecto_id,proveedor_id,categoria,concepto,referencia,fecha,vence_el,base,impuesto,total,pph_retenido,pph_tipo,pph_ingresado_el,moneda,estado,pagado_el,cuenta_pago,justificantes,anulado_motivo,notas,creado_por,creado_en,actualizado_en').order('fecha', { ascending: false }).limit(5000), 'gastos'),
      q(sb.from('proveedores').select('id,nombre,tipo,npwp,contacto,email,telefono,notas,activo').order('nombre'), 'proveedores'),
      q(sb.from('gasto_categorias').select('clave,nombre,grupo,orden,activa').order('orden'), 'categorías'),
      q(sb.from('proyectos').select('id,nombre,activo').order('nombre'), 'proyectos'),
      q(sb.from('cuentas_bancarias').select('clave,label,banco,titular,es_escrow,es_propia,activa').order('orden'), 'cuentas'),
      (typeof cargarSociedades === 'function' ? cargarSociedades(sb).catch(function () { return null; }) : Promise.resolve(null)),
      sb.from('usuarios').select('user_id,nombre,email').then(function (r) { return r.error ? [] : (r.data || []); }, function () { return []; })
    ]).then(function (r) {
      D.gastos = r[0]; D.proveedores = r[1]; D.categorias = r[2]; D.proyectos = r[3]; D.cuentas = r[4];
      D.usuarios = {}; r[6].forEach(function (u) { D.usuarios[u.user_id] = u.nombre || u.email; });
      catPorClave = {}; D.categorias.forEach(function (c) { catPorClave[c.clave] = c; });
      provPorId = {}; D.proveedores.forEach(function (p) { provPorId[p.id] = p; });
      proyPorId = {}; D.proyectos.forEach(function (p) { proyPorId[p.id] = p; });
    });
  }
  function sociedades() {
    try { if (typeof SOCIEDADES !== 'undefined') return Object.keys(SOCIEDADES).filter(function (k) { return SOCIEDADES[k].activa !== false; }); } catch (e) { /* MUDO A PROPOSITO: sin entities.js se cae justo debajo a las sociedades que ya tienen gastos; la lista sale, más corta, no vacía */ }
    var s = {}; D.gastos.forEach(function (g) { s[g.sociedad] = 1; }); return Object.keys(s);
  }
  // Para el cálculo compartido: cada gasto con el nombre de su proyecto y el grupo de su categoría
  function paraCalculo(gs) {
    return gs.map(function (g) {
      var c = catPorClave[g.categoria];
      return { estado: g.estado, moneda: g.moneda, total: g.total, base: g.base, pph_retenido: g.pph_retenido, pph_ingresado_el: g.pph_ingresado_el,
               fecha: g.fecha, vence_el: g.vence_el, pagado_el: g.pagado_el, sociedad: g.sociedad,
               proyecto_nombre: g.proyecto_id && proyPorId[g.proyecto_id] ? proyPorId[g.proyecto_id].nombre : '', grupo: c ? c.grupo : 'general' };
    });
  }

  /* ── FILTROS Y LISTA ───────────────────────────────────────────────────── */
  function filtrados() {
    var b = ($('lw-gas-buscar').value || '').trim().toLowerCase();
    var fs = $('lw-gas-f-sociedad').value, fp = $('lw-gas-f-proyecto').value, fc = $('lw-gas-f-categoria').value, fe = $('lw-gas-f-estado').value, fm = $('lw-gas-f-mes').value;
    return D.gastos.filter(function (g) {
      if (fs && g.sociedad !== fs) return false;
      if (fp === '__general') { if (g.proyecto_id) return false; } else if (fp && g.proyecto_id !== fp) return false;
      if (fc && g.categoria !== fc) return false;
      var ev = estadoVisible(g, hoy);
      if (fe === 'vivos' && g.estado === 'anulado') return false;
      if (fe === 'vencido' && ev !== 'vencido') return false;
      if (fe && fe !== 'vivos' && fe !== 'vencido' && g.estado !== fe) return false;
      if (fm && String(g.fecha).slice(0, 7) !== fm) return false;
      if (b) {
        var prov = g.proveedor_id && provPorId[g.proveedor_id] ? provPorId[g.proveedor_id].nombre : '';
        if ((g.concepto + ' ' + (g.referencia || '') + ' ' + prov).toLowerCase().indexOf(b) === -1) return false;
      }
      return true;
    });
  }
  function llenaFiltros() {
    var opt = function (v, t) { return '<option value="' + esc(v) + '">' + esc(t) + '</option>'; };
    var sel = function (id, primera, opciones) { var el = $(id); var v = el.value; el.innerHTML = primera + opciones.join(''); el.value = v; };
    sel('lw-gas-f-sociedad', opt('', T('Todas las sociedades')), sociedades().map(function (k) { return opt(k, nombreSociedad(k)); }));
    sel('lw-gas-f-proyecto', opt('', T('Todos los proyectos')) + opt('__general', T('General (sin proyecto)')),
        D.proyectos.filter(function (p) { return D.gastos.some(function (g) { return g.proyecto_id === p.id; }); }).map(function (p) { return opt(p.id, p.nombre); }));
    sel('lw-gas-f-categoria', opt('', T('Todas las categorías')), D.categorias.map(function (c) { return opt(c.clave, c.nombre); }));
    var meses = {}; D.gastos.forEach(function (g) { if (g.fecha) meses[String(g.fecha).slice(0, 7)] = 1; });
    sel('lw-gas-f-mes', opt('', T('Todos los meses')), Object.keys(meses).sort().reverse().map(function (m) { return opt(m, m); }));
  }
  function pintaKpis() {
    var calc = finGastos(paraCalculo(D.gastos), hoy);
    var monedas = Object.keys(calc); if (!monedas.length) monedas = ['EUR'];
    var linea = function (k) { return monedas.map(function (m) { return fmt((calc[m] || {})[k] || 0, m); }).join(' · '); };
    pon('k-pendiente', linea('pendientePagar'));
    pon('k-pendiente-pie', monedas.map(function (m) { return (calc[m] ? calc[m].nPendientes : 0); }).reduce(function (a, b) { return a + b; }, 0) + ' ' + T('gastos por pagar'));
    pon('k-vencido', linea('vencidoPagar'));
    var nv = monedas.map(function (m) { return (calc[m] ? calc[m].nVencidos : 0); }).reduce(function (a, b) { return a + b; }, 0);
    pon('k-vencido-pie', nv ? nv + ' ' + T('con la fecha de pago pasada') : T('Ninguno con la fecha de pago pasada'));
    pon('k-mes', linea('pagadoMes'));
    pon('k-mes-pie', T('En el año') + ': ' + linea('pagadoAnio'));
    pon('k-pph', linea('pphPorIngresar'));
  }
  function pintaLista() {
    var tb = $('lw-gas-lista'); if (!tb) return;
    var fs = filtrados();
    if (!D.gastos.length) { tb.innerHTML = '<tr><td colspan="7" class="px-5 py-10 text-center font-body-md text-body-md text-on-surface-variant">' + esc(T('Todavía no hay ningún gasto. Empieza con «Nuevo gasto».')) + '</td></tr>'; pon('suma', ''); return; }
    if (!fs.length) { tb.innerHTML = '<tr><td colspan="7" class="px-5 py-10 text-center font-body-md text-body-md text-on-surface-variant">' + esc(T('Ningún gasto con estos filtros.')) + '</td></tr>'; pon('suma', ''); return; }
    var trozo = PAG ? PAG.pagina(fs) : fs;
    tb.innerHTML = trozo.map(function (g) {
      var prov = g.proveedor_id && provPorId[g.proveedor_id] ? provPorId[g.proveedor_id].nombre : '';
      var proy = g.proyecto_id && proyPorId[g.proyecto_id] ? proyPorId[g.proyecto_id].nombre : T('General');
      var cat = catPorClave[g.categoria] ? catPorClave[g.categoria].nombre : g.categoria;
      var just = (g.justificantes || []).length ? ' <span class="material-symbols-outlined text-[16px] text-outline align-middle" title="' + esc(T('Con justificante')) + '">attach_file</span>' : '';
      return '<tr class="gas-fila border-b border-outline-variant/30 hover:bg-surface-container-low" tabindex="0" data-gas-id="' + esc(g.id) + '">' +
        '<td class="px-5 py-3 fin-num font-body-sm text-body-sm">' + esc(fFecha(g.fecha)) + '</td>' +
        '<td class="px-5 py-3"><span class="font-label-md text-label-md text-on-surface">' + esc(g.concepto) + '</span>' + just +
          '<span class="block font-body-sm text-body-sm text-outline">' + esc([prov, g.referencia, nombreSociedad(g.sociedad)].filter(Boolean).join(' · ')) + '</span></td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + esc(proy) + '</td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + esc(cat) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + esc(fmt(g.total, g.moneda)) +
          (Number(g.pph_retenido) > 0 ? '<span class="block font-body-sm text-body-sm text-outline">' + esc(T('PPh') + ' ' + fmt(g.pph_retenido, g.moneda)) + '</span>' : '') + '</td>' +
        '<td class="px-5 py-3">' + pill(estadoVisible(g, hoy)) + '</td>' +
        '<td class="px-5 py-3 fin-num font-body-sm text-body-sm">' + (g.estado === 'pagado' ? esc(T('Pagado') + ' ' + fFecha(g.pagado_el)) : esc(fFecha(g.vence_el))) + '</td></tr>';
    }).join('');
    // suma de lo filtrado, por moneda y nunca entre monedas
    var porM = {}; fs.forEach(function (g) { if (g.estado !== 'anulado') porM[g.moneda] = (porM[g.moneda] || 0) + Number(g.total || 0); });
    pon('suma', fs.length + ' ' + T(fs.length === 1 ? 'gasto' : 'gastos') + (Object.keys(porM).length ? ' · ' + T('total sin anulados') + ': ' + Object.keys(porM).sort().map(function (m) { return fmt(porM[m], m); }).join(' · ') : ''));
  }
  function pintaProveedores() {
    var tb = $('lw-gas-proveedores'); if (!tb) return;
    if (!D.proveedores.length) { tb.innerHTML = '<tr><td colspan="6" class="px-5 py-10 text-center font-body-md text-body-md text-on-surface-variant">' + esc(T('Todavía no hay proveedores. Empieza con «Nuevo proveedor».')) + '</td></tr>'; return; }
    tb.innerHTML = D.proveedores.map(function (p) {
      var suyos = D.gastos.filter(function (g) { return g.proveedor_id === p.id && g.estado !== 'anulado'; });
      var pend = {}; suyos.forEach(function (g) { if (g.estado === 'pendiente') pend[g.moneda] = (pend[g.moneda] || 0) + Number(g.total || 0) - Number(g.pph_retenido || 0); });
      var tipo = (TIPO_PROV.filter(function (t) { return t[0] === p.tipo; })[0] || [p.tipo, p.tipo])[1];
      return '<tr class="gas-fila border-b border-outline-variant/30 hover:bg-surface-container-low" tabindex="0" data-prov-id="' + esc(p.id) + '">' +
        '<td class="px-5 py-3 font-label-md text-label-md text-on-surface">' + esc(p.nombre) + (p.npwp ? '<span class="block font-body-sm text-body-sm text-outline">NPWP ' + esc(p.npwp) + '</span>' : '') + '</td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + esc(T(tipo)) + '</td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + esc([p.contacto, p.email, p.telefono].filter(Boolean).join(' · ') || '—') + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + suyos.length + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + (Object.keys(pend).length ? esc(Object.keys(pend).map(function (m) { return fmt(pend[m], m); }).join(' · ')) : '—') + '</td>' +
        '<td class="px-5 py-3">' + (p.activo ? pill('pagado').replace(esc(T('Pagado')), esc(T('Activo'))) : '<span class="text-outline font-body-sm text-body-sm">' + esc(T('Desactivado')) + '</span>') + '</td></tr>';
    }).join('');
  }
  function pintaTodo() { llenaFiltros(); pintaKpis(); pintaLista(); pintaProveedores(); if (typeof lwIdiomaAplicar === 'function') { try { lwIdiomaAplicar(); } catch (_) { /* traducir no tumba */ } } }

  /* ── FORMULARIOS ───────────────────────────────────────────────────────── */
  /* «Pagado desde la cuenta»: solo cuentas marcadas como PROPIAS en Cuentas
     (24-sep-2026, LAW-305). La tabla cuentas_bancarias mezcla las de la
     sociedad con las del contratista, los vendedores de suelo y los notarios;
     ofrecerlas todas invitaba a apuntar un pago «desde» la cuenta de un tercero.
     La base lo exige igual (trigger _gastos_antes): propia y nunca escrow. */
  function opcionesCuentas(actual) {
    // Nunca una cuenta de escrow (también lo frena la base); ni desactivadas salvo la que ya tiene
    return [['', T('— sin indicar —')]].concat(D.cuentas.filter(function (c) { return !c.es_escrow && c.es_propia === true && (c.activa || c.clave === actual); })
      .map(function (c) { return [c.clave, (c.label || c.clave) + (c.banco ? ' · ' + c.banco : '')]; }));
  }
  // El campo, o una nota si todavía no hay ninguna cuenta marcada como propia
  function campoCuenta(actual, extra) {
    var ops = opcionesCuentas(actual);
    if (ops.length > 1) { var c = { k: 'cuenta_pago', label: T('Pagado desde la cuenta'), tipo: 'select', valor: actual || '', opciones: ops }; for (var k in (extra || {})) c[k] = extra[k]; return c; }
    var n = { tipo: 'nota', label: T('Para indicar desde qué cuenta se paga, marca en Cuentas cuáles son de la sociedad.') }; if (extra && extra.visibleSi) n.visibleSi = extra.visibleSi; return n;
  }
  function camposGasto(g) {
    g = g || {};
    var socs = sociedades();
    return [
      { k: 'sociedad', label: T('Sociedad que paga'), tipo: 'select', req: true, medio: 1, valor: g.sociedad || socs[0], opciones: socs.map(function (k) { return [k, nombreSociedad(k)]; }) },
      { k: 'proyecto_id', label: T('Proyecto'), tipo: 'select', medio: 1, valor: g.proyecto_id || '', opciones: [['', T('General (sin proyecto)')]].concat(D.proyectos.filter(function (p) { return p.activo !== false || p.id === g.proyecto_id; }).map(function (p) { return [p.id, p.nombre]; })) },
      { k: 'proveedor_id', label: T('Proveedor'), tipo: 'select', medio: 1, valor: g.proveedor_id || '', opciones: [['', T('— sin proveedor —')]].concat(D.proveedores.filter(function (p) { return p.activo || p.id === g.proveedor_id; }).map(function (p) { return [p.id, p.nombre]; })), ayuda: T('¿No está? Créalo en la pestaña Proveedores.') },
      { k: 'categoria', label: T('Categoría'), tipo: 'select', req: true, medio: 1, valor: g.categoria || '', opciones: [['', T('— elige —')]].concat(D.categorias.filter(function (c) { return c.activa || c.clave === g.categoria; }).map(function (c) { return [c.clave, c.nombre]; })) },
      { k: 'concepto', label: T('Concepto'), req: true, valor: g.concepto || '' },
      { k: 'referencia', label: T('Nº de factura del proveedor'), medio: 1, valor: g.referencia || '' },
      { k: 'moneda', label: T('Moneda'), tipo: 'select', medio: 1, valor: g.moneda || 'EUR', opciones: MONEDAS },
      { k: 'fecha', label: T('Fecha de la factura'), tipo: 'date', req: true, medio: 1, valor: g.fecha || hoy },
      { k: 'vence_el', label: T('Vence el'), tipo: 'date', medio: 1, valor: g.vence_el || '' },
      { k: 'base', label: T('Base (sin impuesto)'), req: true, medio: 1, valor: g.base != null ? String(g.base) : '' },
      { k: 'impuesto', label: T('Impuesto soportado (PPN/IVA)'), medio: 1, valor: g.impuesto != null && Number(g.impuesto) ? String(g.impuesto) : '' },
      { k: 'pph_tipo', label: T('Retención PPh'), tipo: 'select', medio: 1, valor: g.pph_tipo || '', opciones: PPH },
      { k: 'pph_retenido', label: T('Importe retenido'), medio: 1, valor: g.pph_retenido != null && Number(g.pph_retenido) ? String(g.pph_retenido) : '', visibleSi: { k: 'pph_tipo', valores: ['pph23', 'pph4_2', 'pph21', 'pph26', 'otro'] }, ayuda: T('Se paga al proveedor el total menos esto; la retención se ingresa luego en Hacienda.') },
      { k: 'notas', label: T('Notas'), tipo: 'textarea', valor: g.notas || '' }
    ];
  }
  function leeImporte(v, que, obligatorio) {
    if (v == null || String(v).trim() === '') return obligatorio ? { error: que } : { n: 0 };
    var n = typeof lwParseImporte === 'function' ? lwParseImporte(v) : Number(String(v).replace(',', '.'));
    if (n == null || !isFinite(n) || n < 0) return { error: que };
    return { n: Math.round(n * 100) / 100 };
  }
  function payloadDe(v) {
    var base = leeImporte(v.base, T('La base no es un importe válido'), true);
    if (base.error) return { error: { message: base.error } };
    var imp = leeImporte(v.impuesto, T('El impuesto no es un importe válido'));
    if (imp.error) return { error: { message: imp.error } };
    var pph = v.pph_tipo ? leeImporte(v.pph_retenido, T('El importe retenido no es válido'), true) : { n: 0 };
    if (pph.error) return { error: { message: pph.error } };
    if (pph.n > base.n + imp.n) return { error: { message: T('La retención no puede ser mayor que el total de la factura.') } };
    return { p: {
      sociedad: v.sociedad, proyecto_id: v.proyecto_id || null, proveedor_id: v.proveedor_id || null, categoria: v.categoria,
      concepto: v.concepto, referencia: v.referencia || null, moneda: v.moneda || 'EUR', fecha: v.fecha, vence_el: v.vence_el || null,
      base: base.n, impuesto: imp.n, pph_tipo: v.pph_tipo || null, pph_retenido: pph.n, notas: v.notas || null
    } };
  }
  function subeJustificante(g, fichero) {
    if (!fichero) return Promise.resolve(null);
    if (fichero.size > 10 * 1024 * 1024) return Promise.resolve({ error: { message: T('El fichero pasa de 10 MB.') } });
    var ruta = g.id + '/' + Date.now() + '_' + limpiaNombre(fichero.name);
    return sb.storage.from('gastos').upload(ruta, fichero, { upsert: false, contentType: fichero.type || 'application/octet-stream' }).then(function (up) {
      if (up.error) return { error: { message: T('No se pudo subir el justificante') + ': ' + up.error.message } };
      // La entrada de la lista la construye el servidor, que comprueba que el fichero existe en la carpeta de ESTE gasto.
      return sb.rpc('gasto_anade_justificante', { p_id: g.id, p_ruta: ruta, p_nombre: fichero.name }).then(function (r) { return rpcOk(r, T('No se pudo anotar el justificante')); });
    });
  }
  function nuevoGasto() {
    var campos = camposGasto().concat([
      { k: 'estado', label: T('¿Ya está pagado?'), tipo: 'select', medio: 1, valor: 'pendiente', opciones: [['pendiente', T('No, pendiente de pagar')], ['pagado', T('Sí, ya pagado')]] },
      { k: 'pagado_el', label: T('Pagado el'), tipo: 'date', medio: 1, valor: hoy, visibleSi: { k: 'estado', valores: ['pagado'] } },
      campoCuenta('', { visibleSi: { k: 'estado', valores: ['pagado'] } }),
      { k: 'fichero', label: T('Justificante (PDF o imagen, máx. 10 MB)'), tipo: 'file', accept: 'application/pdf,image/jpeg,image/png,image/webp' }
    ]);
    window.lwVentana(T('Nuevo gasto'), campos, T('Guardar gasto'), function (v) {
      var pl = payloadDe(v); if (pl.error) return pl;
      pl.p.estado = v.estado === 'pagado' ? 'pagado' : 'pendiente';
      if (pl.p.estado === 'pagado') { pl.p.pagado_el = v.pagado_el || hoy; pl.p.cuenta_pago = v.cuenta_pago || null; }
      return sb.rpc('gasto_guarda', { p_id: null, p_datos: pl.p }).then(function (r) {
        if (r.error || !r.data) return rpcOk(r.error ? r : { error: { message: '—' } }, T('No se pudo guardar el gasto'));
        return subeJustificante({ id: r.data, justificantes: [] }, v.fichero).then(function (u) {
          // el gasto YA está guardado aunque falle el fichero: se dice y se sigue
          /* La pantalla se recarga al guardar: el aviso viaja en sessionStorage
             y se enseña al volver (nunca alert(): congela la extensión de Chrome). */
          if (u && u.error) { try { sessionStorage.setItem('lw_gas_aviso', u.error.message + ' ' + T('El gasto sí se ha guardado: sube el justificante desde su ficha.')); } catch (_) { /* MUDO: sin sessionStorage se pierde solo el aviso */ } }
          return null;
        });
      });
    }, { sub: T('Gastos y proveedores') });
  }
  function editaGasto(g) {
    window.lwVentana(T('Editar gasto'), camposGasto(g), T('Guardar cambios'), function (v) {
      var pl = payloadDe(v); if (pl.error) return pl;
      return sb.rpc('gasto_guarda', { p_id: g.id, p_datos: pl.p }).then(function (r) { return rpcOk(r, T('No se pudo guardar')); });
    }, { sub: g.concepto });
  }
  function marcaPagado(g) {
    window.lwVentana(T('Marcar como pagado'), [
      { k: 'pagado_el', label: T('Pagado el'), tipo: 'date', req: true, medio: 1, valor: hoy },
      campoCuenta(g.cuenta_pago, { medio: 1 }),
      { k: 'nota', tipo: 'nota', label: Number(g.pph_retenido) > 0 ? T('Al proveedor se le paga') + ' ' + fmt(Number(g.total) - Number(g.pph_retenido), g.moneda) + ' (' + T('total menos la retención') + ').' : T('Importe') + ': ' + fmt(g.total, g.moneda) }
    ], T('Marcar pagado'), function (v) {
      return sb.rpc('gasto_marca_pagado', { p_id: g.id, p_pagado_el: v.pagado_el, p_cuenta: v.cuenta_pago || null }).then(function (r) { return rpcOk(r, T('No se pudo marcar como pagado')); });
    }, { sub: g.concepto });
  }
  function marcaPph(g) {
    window.lwVentana(T('Retención ingresada en Hacienda'), [
      { k: 'pph_ingresado_el', label: T('Ingresada el'), tipo: 'date', req: true, valor: hoy },
      { k: 'nota', tipo: 'nota', label: T('No crees otro gasto por este ingreso: ya cuenta aquí.') }
    ], T('Guardar'), function (v) {
      return sb.rpc('gasto_pph_ingresado', { p_id: g.id, p_fecha: v.pph_ingresado_el }).then(function (r) { return rpcOk(r, T('No se pudo guardar')); });
    }, { sub: g.concepto });
  }
  function anula(g) {
    window.lwVentana(T('Anular gasto'), [
      { k: 'nota', tipo: 'nota', label: T('Un gasto anulado deja de contar en todo y ya no se puede editar. No se borra: queda en el libro con su motivo.') },
      { k: 'motivo', label: T('Motivo'), tipo: 'textarea', req: true, valor: '' }
    ], T('Anular'), function (v) {
      return lwConfirmar({ titulo: T('Anular este gasto'), cuerpo: T('No se puede deshacer.'), confirmar: T('Anular'), tono: 'peligro' }).then(function (ok) {
        if (!ok) return { error: { message: T('Cancelado.') } };
        return sb.rpc('gasto_anula', { p_id: g.id, p_motivo: v.motivo }).then(function (r) { return rpcOk(r, T('No se pudo anular')); });
      });
    }, { sub: g.concepto });
  }
  function anadeJustificante(g) {
    window.lwVentana(T('Añadir justificante'), [
      { k: 'fichero', label: T('PDF o imagen, máx. 10 MB'), tipo: 'file', req: true, accept: 'application/pdf,image/jpeg,image/png,image/webp' }
    ], T('Subir'), function (v) { return subeJustificante(g, v.fichero); }, { sub: g.concepto });
  }

  /* ── FICHA ─────────────────────────────────────────────────────────────── */
  function ficha(g) {
    var H = window.lwCajonHtml;
    var prov = g.proveedor_id && provPorId[g.proveedor_id] ? provPorId[g.proveedor_id].nombre : null;
    var proy = g.proyecto_id && proyPorId[g.proyecto_id] ? proyPorId[g.proyecto_id].nombre : T('General (sin proyecto)');
    var cat = catPorClave[g.categoria] ? catPorClave[g.categoria].nombre : g.categoria;
    var cuenta = g.cuenta_pago ? (D.cuentas.filter(function (c) { return c.clave === g.cuenta_pago; })[0] || {}).label || g.cuenta_pago : null;
    var pphLbl = (PPH.filter(function (p) { return p[0] === g.pph_tipo; })[0] || ['', ''])[1];
    var cuerpo = H.seccion(T('Factura'),
        H.dato(T('Estado'), pill(estadoVisible(g, hoy)), { html: true }) + H.dato(T('Sociedad'), nombreSociedad(g.sociedad)) + H.dato(T('Proyecto'), proy) +
        H.dato(T('Proveedor'), prov) + H.dato(T('Categoría'), cat) + H.dato(T('Nº de factura'), g.referencia) +
        H.dato(T('Fecha'), fFecha(g.fecha)) + H.dato(T('Vence'), g.vence_el ? fFecha(g.vence_el) : null)) +
      H.seccion(T('Importes'),
        H.dato(T('Base'), fmt(g.base, g.moneda)) + H.dato(T('Impuesto soportado'), Number(g.impuesto) ? fmt(g.impuesto, g.moneda) : null) +
        H.dato(T('Total'), fmt(g.total, g.moneda)) +
        (Number(g.pph_retenido) > 0 ? H.dato(T('Retención') + ' ' + pphLbl, fmt(g.pph_retenido, g.moneda)) + H.dato(T('Al proveedor'), fmt(Number(g.total) - Number(g.pph_retenido), g.moneda)) +
          H.dato(T('Retención ingresada'), g.pph_ingresado_el ? fFecha(g.pph_ingresado_el) : T('Pendiente')) : '')) +
      (g.estado === 'pagado' ? H.seccion(T('Pago'), H.dato(T('Pagado el'), fFecha(g.pagado_el)) + H.dato(T('Desde la cuenta'), cuenta)) : '') +
      (g.estado === 'anulado' ? H.nota(T('Anulado') + ': ' + (g.anulado_motivo || '')) : '') +
      H.seccion(T('Justificantes'), (g.justificantes || []).length ? (g.justificantes || []).map(function (j, i) {
        return '<div style="display:flex;justify-content:space-between;gap:10px;align-items:center;font-size:13px"><span style="overflow-wrap:anywhere">' + esc(j.nombre || j.path) + '</span>' +
          '<button type="button" data-gas-just="' + i + '" style="border:1px solid #E4DCCB;background:#fff;border-radius:8px;padding:5px 10px;font-weight:600;cursor:pointer">' + esc(T('Ver')) + '</button></div>';
      }).join('') : '<p style="margin:0;font-size:13px;color:#75786e">' + esc(T('Sin justificante todavía.')) + '</p>') +
      (g.notas ? H.seccion(T('Notas'), '<p style="margin:0;font-size:13px;white-space:pre-wrap">' + esc(g.notas) + '</p>') : '') +
      H.seccion(T('Historial'), '<div data-gas-log><p style="margin:0;font-size:13px;color:#75786e">' + esc(T('Cargando…')) + '</p></div>');
    var acciones = [];
    if (g.estado === 'pendiente') acciones.push({ texto: T('Marcar pagado'), tono: 'primario', onClick: function () { marcaPagado(g); } });
    if (g.estado !== 'anulado' && Number(g.pph_retenido) > 0 && !g.pph_ingresado_el) acciones.push({ texto: T('Retención ingresada'), onClick: function () { marcaPph(g); } });
    if (g.estado !== 'anulado') {
      acciones.push({ texto: T('Añadir justificante'), onClick: function () { anadeJustificante(g); } });
      acciones.push({ texto: T('Editar datos'), onClick: function () { editaGasto(g); } });
      acciones.push({ texto: T('Anular'), tono: 'peligro', onClick: function () { anula(g); } });
    }
    acciones.push({ texto: T('Cerrar'), cerrar: true });
    window.lwCajon({ titulo: g.concepto, sub: T('Gasto') + ' · ' + fmt(g.total, g.moneda), bajoTitulo: prov || '', cuerpo: cuerpo, acciones: acciones, ancho: 'min(640px,96vw)' });
    var caja = document.getElementById('lw-cajon'); if (!caja) return;
    caja.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-gas-just]'); if (!b) return;
      var j = (g.justificantes || [])[Number(b.getAttribute('data-gas-just'))]; if (!j) return;
      // URL firmada de vida corta: 2 minutos (Seguridad, #64)
      sb.storage.from('gastos').createSignedUrl(j.path, 120).then(function (u) {
        if (u.error || !u.data) { var m = T('No se pudo abrir el justificante') + ': ' + (u.error && u.error.message); if (typeof toastMal === 'function') toastMal(m); else aviso(m, 'mal'); return; }
        window.open(u.data.signedUrl, '_blank', 'noopener');
      });
    });
    sb.from('gastos_log').select('accion,quien,cuando,antes,despues').eq('gasto_id', g.id).order('cuando', { ascending: false }).limit(8).then(function (r) {
      var cont = caja.querySelector('[data-gas-log]'); if (!cont) return;
      if (r.error) { cont.innerHTML = '<p style="margin:0;font-size:13px;color:#93000a">' + esc(T('No se pudo leer el historial.')) + '</p>'; return; }
      cont.innerHTML = (r.data || []).map(function (x) {
        var que = x.accion === 'insert' ? T('Alta') : (x.antes && x.despues && x.antes.estado !== x.despues.estado ? T('Estado') + ': ' + T((ESTADO[x.despues.estado] || [x.despues.estado])[0]) : T('Cambio de datos'));
        return '<div style="display:flex;justify-content:space-between;gap:10px;font-size:12.5px;padding:4px 0;border-bottom:1px solid rgba(228,220,203,.7)"><span>' + esc(que) + '</span><span style="color:#75786e">' +
          esc((D.usuarios[x.quien] || '—') + ' · ' + new Date(x.cuando).toLocaleString(typeof lwLocale === 'function' ? lwLocale() : 'es-ES')) + '</span></div>';
      }).join('') || '<p style="margin:0;font-size:13px;color:#75786e">—</p>';
    });
  }

  /* ── PROVEEDORES ───────────────────────────────────────────────────────── */
  function formProveedor(p) {
    var nuevo = !p; p = p || { tipo: 'proveedor', activo: true };
    var campos = [
      { k: 'nombre', label: T('Nombre o razón social'), req: true, valor: p.nombre || '' },
      { k: 'tipo', label: T('Tipo'), tipo: 'select', medio: 1, valor: p.tipo, opciones: TIPO_PROV.map(function (t) { return [t[0], T(t[1])]; }) },
      { k: 'npwp', label: 'NPWP', medio: 1, valor: p.npwp || '' },
      { k: 'contacto', label: T('Persona de contacto'), medio: 1, valor: p.contacto || '' },
      { k: 'telefono', label: T('Teléfono'), medio: 1, valor: p.telefono || '' },
      { k: 'email', label: T('Email'), tipo: 'email', valor: p.email || '' },
      { k: 'notas', label: T('Notas'), tipo: 'textarea', valor: p.notas || '' }
    ];
    if (!nuevo) campos.push({ k: 'activo', label: T('Activo (se ofrece al apuntar un gasto)'), tipo: 'check', valor: !!p.activo });
    window.lwVentana(nuevo ? T('Nuevo proveedor') : T('Editar proveedor'), campos, T('Guardar'), function (v) {
      var pl = { nombre: v.nombre, tipo: v.tipo, npwp: v.npwp || null, contacto: v.contacto || null, telefono: v.telefono || null, email: v.email || null, notas: v.notas || null };
      if (!nuevo) pl.activo = !!v.activo;
      // Por el servidor (frontera frontend/backend, 26-sep-2026).
      return sb.rpc('proveedor_guarda', { p_id: nuevo ? null : p.id, p_datos: pl }).then(function (r) {
        if (r.error && /duplicate|unique|23505/i.test(r.error.message + ' ' + r.error.code)) return { error: { message: T('Ya existe un proveedor con ese nombre.') } };
        return rpcOk(r, T('No se pudo guardar el proveedor'));
      });
    }, { sub: T('Proveedores') });
  }

  /* ── CSV ───────────────────────────────────────────────────────────────── */
  function exportaCSV() {
    var q = function (v) { v = v == null ? '' : String(v); return /[;"\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    var filas = [['Fecha', 'Sociedad', 'Proyecto', 'Proveedor', 'Categoría', 'Concepto', 'Nº factura', 'Base', 'Impuesto', 'Total', 'Retención PPh', 'Tipo PPh', 'Retención ingresada', 'Moneda', 'Estado', 'Vence', 'Pagado el', 'Cuenta de pago', 'Motivo anulación']]
      .concat(filtrados().map(function (g) {
        return [g.fecha, nombreSociedad(g.sociedad), g.proyecto_id && proyPorId[g.proyecto_id] ? proyPorId[g.proyecto_id].nombre : 'General',
          g.proveedor_id && provPorId[g.proveedor_id] ? provPorId[g.proveedor_id].nombre : '', catPorClave[g.categoria] ? catPorClave[g.categoria].nombre : g.categoria,
          g.concepto, g.referencia, g.base, g.impuesto, g.total, g.pph_retenido, g.pph_tipo, g.pph_ingresado_el, g.moneda, estadoVisible(g, hoy), g.vence_el, g.pagado_el, g.cuenta_pago, g.anulado_motivo];
      }));
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + filas.map(function (f) { return f.map(q).join(';'); }).join('\r\n')], { type: 'text/csv;charset=utf-8' }));
    a.download = 'gastos_' + hoy + '.csv'; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  }

  /* ── ARRANQUE ──────────────────────────────────────────────────────────── */
  function cambiaVista(v) {
    VISTA = v;
    document.querySelectorAll('[data-gas-vista]').forEach(function (b) { var on = b.getAttribute('data-gas-vista') === v; b.setAttribute('aria-pressed', String(on)); b.setAttribute('aria-selected', String(on)); });
    $('lw-gas-vista-gastos').hidden = v !== 'gastos';
    $('lw-gas-vista-proveedores').hidden = v !== 'proveedores';
    $('lw-gas-nuevo-txt').textContent = v === 'gastos' ? T('Nuevo gasto') : T('Nuevo proveedor');
    $('lw-gas-csv').hidden = v !== 'gastos';
  }
  function monta(aut) {
    sb = aut.sb;
    if (typeof finGastos !== 'function' || typeof window.lwVentana !== 'function' || typeof window.lwCajon !== 'function') {
      aviso(T('No cargaron las piezas de la pantalla (finanzas.js / editores.js). Recarga la página; si sigue, avisa a Desarrollo.'), 'mal'); return;
    }
    PAG = (typeof lwPaginador === 'function') ? lwPaginador('#lw-gas-pag', { porPagina: 50 }) : null;
    if (PAG) PAG.alCambiar(pintaLista);
    try { var pend = sessionStorage.getItem('lw_gas_aviso'); if (pend) { sessionStorage.removeItem('lw_gas_aviso'); aviso(pend, 'mal'); } } catch (_) { /* MUDO: sin sessionStorage */ }
    cargar().then(function () {
      pintaTodo();
      if (!D.categorias.length) aviso(T('Tu usuario no ve el catálogo de categorías: hace falta ser admin y tener «Gastos y proveedores» marcado en Usuarios. La base no enseña nada sin ese permiso.'), 'mal');
    }, function (e) {
      aviso(T('No se pudieron leer los gastos') + ' (' + e.message + '). ' + T('Si eres admin, pide que te marquen «Gastos y proveedores» en Usuarios.'), 'mal');
      $('lw-gas-lista').innerHTML = '';
    });
    ['lw-gas-f-sociedad', 'lw-gas-f-proyecto', 'lw-gas-f-categoria', 'lw-gas-f-estado', 'lw-gas-f-mes'].forEach(function (id) { $(id).addEventListener('change', pintaLista); });
    var tb; $('lw-gas-buscar').addEventListener('input', function () { clearTimeout(tb); tb = setTimeout(pintaLista, 150); });
    document.querySelectorAll('[data-gas-vista]').forEach(function (b) { b.addEventListener('click', function () { cambiaVista(b.getAttribute('data-gas-vista')); }); });
    $('lw-gas-nuevo').addEventListener('click', function (ev) { ev.stopPropagation(); if (VISTA === 'gastos') nuevoGasto(); else formProveedor(null); });
    $('lw-gas-csv').addEventListener('click', exportaCSV);
    var abre = function (ev) {
      if (ev.type === 'keydown' && ev.key !== 'Enter' && ev.key !== ' ') return;
      var tr = ev.target.closest && ev.target.closest('tr[data-gas-id],tr[data-prov-id]'); if (!tr) return;
      if (ev.type === 'keydown') ev.preventDefault();
      if (tr.hasAttribute('data-gas-id')) { var g = D.gastos.filter(function (x) { return x.id === tr.getAttribute('data-gas-id'); })[0]; if (g) ficha(g); }
      else { var p = provPorId[tr.getAttribute('data-prov-id')]; if (p) formProveedor(p); }
    };
    ['lw-gas-lista', 'lw-gas-proveedores'].forEach(function (id) { $(id).addEventListener('click', abre); $(id).addEventListener('keydown', abre); });
  }
  function arranca() {
    if (!window.LW_AUTH) { aviso(T('Sin sesión: no se carga nada.'), 'mal'); return; }
    window.LW_AUTH.then(function (aut) {
      var rol = aut.ficha && aut.ficha.rol;
      if (rol !== 'admin' && rol !== 'super_admin') { aviso(T('Esta pantalla es de dirección (admin).'), 'mal'); return; }
      monta(aut);
    });
  }
  /* Espera a DOMContentLoaded aunque el documento ya no esté en 'loading': este
     script es `defer` y va ANTES que editores.js y dialogo.js, que también lo
     son. DOMContentLoaded salta cuando han corrido TODOS los diferidos; en
     'interactive' todavía no, y arrancar ahí dejaba lwVentana sin definir si la
     sesión resolvía rápido (cazado con el arnés). */
  var arrancado = false;
  function unaVez() { if (!arrancado) { arrancado = true; arranca(); } }
  if (document.readyState === 'complete') unaVez();
  else { document.addEventListener('DOMContentLoaded', unaVez); window.addEventListener('load', unaVez); }
})();
