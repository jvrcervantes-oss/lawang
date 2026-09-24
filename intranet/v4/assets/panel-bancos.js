/* panel-bancos.js — la pantalla /v4/bancos/ (24-sep-2026). Módulo `bancos`.
 *
 * Extractos de las cuentas PROPIAS de la sociedad (Statrys, bancos de Hong Kong
 * y Singapur) y la conciliación de cada movimiento con lo que lo explica: un
 * recibí, un gasto pagado, una retención ingresada, una comisión pagada o un
 * traspaso entre dos cuentas propias.
 *
 * Misma forma que panel-gastos.js: carga → cálculo (bancos.js, en
 * contracts/assets/, con test) → pintado. Aquí NO se escribe en las tablas:
 * todo pasa por las RPC de la migración 20260924101052_bancos_conciliacion.sql
 * (bancos_importar / conciliar / desconciliar / ignorar / designorar), que
 * validan los dos lados (signo, moneda, lo ya conciliado del movimiento y del
 * documento). La única escritura directa es el perfil de columnas de cada
 * cuenta (bancos_perfiles), que es solo el mapeo del CSV.
 *
 * Reglas que se cumplen aquí, con su porqué:
 *  - El concepto bancario lo escribe QUIEN TRANSFIERE: es texto hostil. Todo
 *    pasa por esc() al pintar y por bancosCeldaSegura() al exportar (#67).
 *  - Solo CSV en v1: la única librería de Excel en cdnjs (SheetJS 0.18.5) tiene
 *    vulnerabilidades conocidas (#67, Seguridad). Todos los bancos exportan CSV.
 *  - Una diferencia de importe NUNCA se cierra sola: la comisión del banco va
 *    en su propia línea (Administración, #67).
 *  - Formularios y fichas con los cajones compartidos (lwVentana, lwCajon). */
(function () {
  'use strict';
  if (!/\/bancos\/?(index\.html)?$/.test(location.pathname)) return;

  var T = function (s) { return (typeof lwT === 'function') ? lwT(s) : s; };
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  /* CON CÉNTIMOS, a propósito (owner 24-sep-2026, opción A): la v4 enseña los
     importes sin decimales (datos.js envuelve lwFormatoImporte y fuerza 0), pero
     un extracto y su conciliación van al céntimo — sin ellos 1.000,90 salía
     «1.001» y una diferencia de 0,80 salía «falta 1». Solo esta pantalla: los
     decimales de cada moneda los da LW_DECIMALES (dinero.js; IDR sin decimales). */
  function fmt(n, m) {
    if (n == null) return '—';
    var d = (typeof LW_DECIMALES !== 'undefined' && LW_DECIMALES[m] != null) ? LW_DECIMALES[m] : (m === 'IDR' ? 0 : 2);
    return new Intl.NumberFormat('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d }).format(Number(n) || 0) + (m ? ' ' + m : '');
  }
  function fmtS(n, m) { return (Number(n) < 0 ? '− ' : '+ ') + fmt(Math.abs(Number(n) || 0), m); }
  function hoyLocal() {
    var d = new Date();
    return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  }
  function fFecha(x) { if (!x) return '—'; var d = new Date(String(x).slice(0, 10) + 'T12:00:00'); return isNaN(d) ? String(x) : d.toLocaleDateString(typeof lwLocale === 'function' ? lwLocale() : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); }
  function dias(a, b) { return Math.round((Date.parse(String(a).slice(0, 10) + 'T12:00:00Z') - Date.parse(String(b).slice(0, 10) + 'T12:00:00Z')) / 86400000); }
  function r2(n) { return Math.round(Number(n) * 100) / 100; }
  var $ = function (id) { return document.getElementById(id); };
  function pon(k, t) { document.querySelectorAll('[data-ban="' + k + '"]').forEach(function (e) { e.textContent = t; }); }
  function aviso(texto, tono) {
    var caja = $('lw-ban-avisos'); if (!caja) return;
    var p = document.createElement('div'); p.setAttribute('role', 'status');
    p.className = 'rounded-xl border px-5 py-4 font-body-sm text-body-sm ' + (tono === 'mal' ? 'border-error/40 bg-error-container/40 text-on-surface' : tono === 'bien' ? 'border-primary/30 bg-primary-fixed/40 text-on-surface' : 'border-burnt-earth/30 bg-surface-alt text-on-surface-variant');
    p.textContent = texto; caja.appendChild(p);
  }
  function limpiaAvisos() { var c = $('lw-ban-avisos'); if (c) c.innerHTML = ''; }
  function avisoRapido(texto, mal) {
    if (mal && typeof toastMal === 'function') return toastMal(texto);
    if (!mal && typeof toastBien === 'function') return toastBien(texto);
    aviso(texto, mal ? 'mal' : 'bien');
  }
  function errDe(r, pre) { return (pre ? pre + ': ' : '') + ((r && r.error && (r.error.message || r.error)) || T('error desconocido')); }

  var ESTADO = {
    pendiente: ['Por conciliar', 'bg-surface-container-high text-on-surface-variant'],
    parcial: ['A medias', 'bg-secondary-container text-on-secondary-container'],
    conciliado: ['Conciliado', 'bg-primary-fixed text-on-primary-fixed'],
    ignorado: ['Ignorado', 'bg-surface-container text-outline']
  };
  var TIPO = {
    recibi: 'Recibí', gasto: 'Gasto pagado', pph: 'Retención ingresada (PPh)', comision: 'Comisión pagada',
    traspaso: 'Traspaso entre cuentas propias', comision_bancaria: 'Comisión del banco', retencion_sufrida: 'Retención que nos aplicaron', otro: 'Otro'
  };
  var NATURALEZA = [['interno', 'Movimiento interno de tesorería'], ['capital', 'Aportación de capital'], ['prestamo', 'Préstamo entre sociedades'], ['pago', 'Pago entre sociedades']];
  var MONEDAS = ['EUR', 'USD', 'HKD', 'SGD', 'IDR', 'CNY', 'AUD', 'GBP'];
  function pill(estado) { var e = ESTADO[estado] || [estado, '']; return '<span class="inline-block px-2.5 py-0.5 rounded-full text-[11px] font-semibold uppercase tracking-wide ' + e[1] + '">' + esc(T(e[0])) + '</span>'; }

  var sb, hoy = hoyLocal(), PAG = null;
  var D = { movs: [], lineas: [], cuentas: [], perfiles: {}, resumen: null, recibis: [], gastos: [], comisiones: [], leidos: { gastos: true, comisiones: true } };
  var movPorId = {}, cuentaPorClave = {};

  /* ── CARGA ─────────────────────────────────────────────────────────────── */
  var PAGINA = 1000;
  function todas(hacer, que, col) {
    var filas = [];
    function pag(desde) {
      return hacer().order(col || 'id', { ascending: true }).range(desde, desde + PAGINA - 1).then(function (r) {
        if (r.error) { console.error('[bancos] ' + que + ':', r.error); throw new Error(que); }
        filas = filas.concat(r.data || []);
        return (r.data || []).length === PAGINA && desde < 50000 ? pag(desde + PAGINA) : filas;
      });
    }
    return pag(0);
  }
  // Lo que explica un movimiento puede vivir en módulos que este usuario no ve
  // (Gastos, Comisiones): se carga sin tumbar la pantalla y se dice qué falta.
  function opcional(p, que) { return p.then(function (f) { return f; }, function () { D.leidos[que] = false; return []; }); }
  function cargar() {
    D.leidos = { gastos: true, comisiones: true };
    return Promise.all([
      todas(function () { return sb.from('bancos_movimientos').select('id,cuenta_clave,fecha,fecha_valor,concepto,referencia,importe,moneda,saldo,orden,conciliado,estado,ignorado_motivo,ignorado_en,creado_en'); }, 'movimientos'),
      todas(function () { return sb.from('bancos_conciliacion').select('id,movimiento_id,tipo,ref_id,importe_mov,importe_doc,moneda_doc,tipo_cambio,naturaleza,nota,creado_por,creado_en').is('anulado_en', null); }, 'conciliación'),
      sb.from('cuentas_bancarias').select('clave,label,banco,titular,es_escrow,es_propia,activa,orden').order('orden').then(function (r) { if (r.error) throw new Error('cuentas'); return r.data || []; }),
      sb.from('bancos_perfiles').select('cuenta_clave,mapeo').then(function (r) { return r.error ? [] : (r.data || []); }),
      sb.rpc('bancos_resumen', { p_anio: Number(hoy.slice(0, 4)) }).then(function (r) { return r.error ? null : r.data; }),
      todas(function () { return sb.rpc('facturas_equipo').select('id,numero,tipo,sociedad,total,moneda,anulada,fecha_emision,created_at,proyecto_nombre').eq('tipo', 'recibi'); }, 'recibís').catch(function () { return []; }),
      opcional(todas(function () { return sb.from('gastos').select('id,concepto,referencia,total,pph_retenido,pph_ingresado_el,moneda,estado,pagado_el,cuenta_pago').neq('estado', 'anulado'); }, 'gastos'), 'gastos'),
      opcional(todas(function () { return sb.from('comisiones_devengadas').select('id,estado,importe,importe_ajustado,moneda,pagado_en').eq('estado', 'pagada'); }, 'comisiones'), 'comisiones')
    ]).then(function (r) {
      D.movs = r[0].sort(function (a, b) { return a.fecha < b.fecha ? 1 : a.fecha > b.fecha ? -1 : (b.orden || 0) - (a.orden || 0); });
      D.lineas = r[1]; D.cuentas = r[2];
      D.perfiles = {}; r[3].forEach(function (p) { D.perfiles[p.cuenta_clave] = p.mapeo; });
      D.resumen = r[4];
      D.recibis = r[5].filter(function (f) { return !f.anulada; });
      D.gastos = r[6]; D.comisiones = r[7];
      movPorId = {}; D.movs.forEach(function (m) { movPorId[m.id] = m; });
      cuentaPorClave = {}; D.cuentas.forEach(function (c) { cuentaPorClave[c.clave] = c; });
    });
  }
  function nombreCuenta(clave) {
    var c = cuentaPorClave[clave]; if (!c) return clave;
    var l = c.label || c.clave;
    // «Statrys HK · Statrys»: el banco solo se añade si la etiqueta no lo dice ya
    return l + (c.banco && l.toLowerCase().indexOf(String(c.banco).toLowerCase()) === -1 ? ' · ' + c.banco : '');
  }
  function cuentasImportables() { return D.cuentas.filter(function (c) { return c.es_propia === true && !c.es_escrow && c.activa !== false; }); }
  function restante(m) { return r2(Number(m.importe) - Number(m.conciliado || 0)); }
  function lineasDe(movId) { return D.lineas.filter(function (l) { return l.movimiento_id === movId; }); }

  /* ── DOCUMENTOS CANDIDATOS ─────────────────────────────────────────────── */
  // Lo ya conciliado de cada documento, en SU moneda (igual que lo mide la base)
  function yaConciliado() {
    var ya = {};
    D.lineas.forEach(function (l) { if (l.ref_id) { var k = l.tipo + ':' + l.ref_id; ya[k] = (ya[k] || 0) + Math.abs(Number(l.importe_doc != null ? l.importe_doc : l.importe_mov)); } });
    return ya;
  }
  // Todos los documentos (también los ya conciliados del todo: la ficha los nombra)
  function documentos() {
    var ya = yaConciliado(), out = [];
    var mete = function (tipo, id, importe, moneda, fecha, numero, texto) {
      if (!id || !(Number(importe) > 0)) return;
      out.push({ tipo: tipo, id: id, importe: r2(importe), pendiente: r2(Number(importe) - (ya[tipo + ':' + id] || 0)), moneda: moneda || 'EUR', fecha: fecha ? String(fecha).slice(0, 10) : null, numero: numero || '', texto: texto || '' });
    };
    D.recibis.forEach(function (f) { mete('recibi', f.id, f.total, f.moneda, f.fecha_emision || f.created_at, f.numero, f.proyecto_nombre); });
    D.gastos.forEach(function (g) {
      if (g.estado === 'pagado') mete('gasto', g.id, Number(g.total) - Number(g.pph_retenido || 0), g.moneda, g.pagado_el, g.referencia, g.concepto);
      if (Number(g.pph_retenido) > 0 && g.pph_ingresado_el) mete('pph', g.id, g.pph_retenido, g.moneda, g.pph_ingresado_el, g.referencia, T('Retención de') + ' ' + g.concepto);
    });
    D.comisiones.forEach(function (c) { mete('comision', c.id, c.importe_ajustado != null ? c.importe_ajustado : c.importe, c.moneda, c.pagado_en, '', T('Comisión pagada')); });
    return out;
  }
  // Movimientos de OTRA cuenta propia, de signo contrario y con algo por explicar
  function traspasosPara(m) {
    return D.movs.filter(function (o) {
      return o.id !== m.id && o.cuenta_clave !== m.cuenta_clave && Math.sign(o.importe) !== Math.sign(m.importe) && o.estado !== 'ignorado' && Math.abs(restante(o)) > 0.005;
    }).map(function (o) {
      return { tipo: 'traspaso', id: o.id, importe: Math.abs(restante(o)), pendiente: Math.abs(restante(o)), moneda: o.moneda, fecha: o.fecha, numero: '', texto: nombreCuenta(o.cuenta_clave) + ' · ' + (o.concepto || '') };
    });
  }
  function candidatosPara(m) {
    return documentos().filter(function (c) { return c.pendiente > 0.005; }).concat(traspasosPara(m));
  }
  function nombraDoc(tipo, refId, docs) {
    if (tipo === 'traspaso') { var o = movPorId[refId]; return o ? nombreCuenta(o.cuenta_clave) + ' · ' + fFecha(o.fecha) + ' · ' + fmtS(o.importe, o.moneda) : T('Movimiento de otra cuenta'); }
    var d = (docs || documentos()).filter(function (x) { return x.tipo === tipo && x.id === refId; })[0];
    return d ? [d.numero, d.texto, fFecha(d.fecha)].filter(Boolean).join(' · ') : (refId ? T('Documento') + ' ' + String(refId).slice(0, 8) : '');
  }

  /* ── FILTROS Y LISTA ───────────────────────────────────────────────────── */
  function filtrados() {
    var b = ($('lw-ban-buscar').value || '').trim().toLowerCase();
    var fc = $('lw-ban-f-cuenta').value, fe = $('lw-ban-f-estado').value, fm = $('lw-ban-f-mes').value;
    return D.movs.filter(function (m) {
      if (fc && m.cuenta_clave !== fc) return false;
      if (fe === 'abiertos' && m.estado !== 'pendiente' && m.estado !== 'parcial') return false;
      if (fe && fe !== 'abiertos' && m.estado !== fe) return false;
      if (fm && String(m.fecha).slice(0, 7) !== fm) return false;
      if (b && ((m.concepto || '') + ' ' + (m.referencia || '')).toLowerCase().indexOf(b) === -1) return false;
      return true;
    });
  }
  function llenaFiltros() {
    var opt = function (v, t) { return '<option value="' + esc(v) + '">' + esc(t) + '</option>'; };
    var sel = function (id, primera, opciones) { var el = $(id); var v = el.value; el.innerHTML = primera + opciones.join(''); el.value = v; if (el.value !== v) el.value = ''; };
    var conMovs = {}; D.movs.forEach(function (m) { conMovs[m.cuenta_clave] = 1; });
    sel('lw-ban-f-cuenta', opt('', T('Todas las cuentas')), Object.keys(conMovs).map(function (k) { return opt(k, nombreCuenta(k)); }));
    var meses = {}; D.movs.forEach(function (m) { meses[String(m.fecha).slice(0, 7)] = 1; });
    sel('lw-ban-f-mes', opt('', T('Todos los meses')), Object.keys(meses).sort().reverse().map(function (x) { return opt(x, x); }));
  }
  function pintaCuentas() {
    var caja = $('lw-ban-cuentas'); if (!caja) return;
    var tarjeta = function (inner) { return '<div class="bg-surface-container-lowest rounded-xl p-5 shadow-sm flex flex-col gap-2">' + inner + '</div>'; };
    if (D.resumen == null) {
      caja.innerHTML = tarjeta('<p class="font-body-md text-body-md text-on-surface-variant">' + esc(T('Tu usuario no ve los bancos: hace falta ser admin y tener «Bancos» marcado en Usuarios.')) + '</p>'); return;
    }
    if (!D.resumen.length) {
      var nProp = cuentasImportables().length;
      caja.innerHTML = tarjeta('<p class="font-label-md text-label-md text-on-surface">' + esc(T('Todavía no hay ningún extracto importado.')) + '</p>' +
        '<p class="font-body-sm text-body-sm text-on-surface-variant">' + esc(nProp ? T('Empieza con «Importar extracto».') : T('Antes, marca en Cuentas qué cuentas son de la sociedad: solo esas se pueden importar.')) + '</p>');
      return;
    }
    caja.innerHTML = D.resumen.map(function (c) {
      var viejo = c.ultimo && dias(hoy, c.ultimo) > 7;
      return tarjeta(
        '<span class="font-label-md text-[11px] tracking-[0.14em] uppercase text-outline font-bold">' + esc(nombreCuenta(c.cuenta)) + ' · ' + esc(c.moneda) + '</span>' +
        '<span class="fin-kpi font-headline-md text-deep-lagoon">' + (c.saldo != null ? esc(fmt(c.saldo, c.moneda)) : '<span class="text-outline">—</span>') + '</span>' +
        '<span class="font-body-sm text-body-sm text-on-surface-variant">' + esc(c.saldo != null ? T('Saldo que da el banco a') + ' ' + fFecha(c.saldo_fecha) : T('El extracto no trae saldo')) + '</span>' +
        '<span class="font-body-sm text-body-sm ' + (viejo ? 'text-error font-semibold' : 'text-on-surface-variant') + '">' + esc(T('Extracto hasta') + ' ' + fFecha(c.ultimo) + (viejo ? ' · ' + dias(hoy, c.ultimo) + ' ' + T('días de antigüedad') : '')) + '</span>' +
        '<span class="font-body-sm text-body-sm text-on-surface-variant">' + esc(T('En el año') + ': ' + T('entra') + ' ' + fmt(Math.abs(Number(c.entradas) || 0), c.moneda) + ' · ' + T('sale') + ' ' + fmt(Math.abs(Number(c.salidas) || 0), c.moneda)) +
          (Number(c.traspasos_in) || Number(c.traspasos_out) ? '<span class="block text-outline">' + esc(T('sin contar traspasos entre cuentas propias')) + '</span>' : '') + '</span>' +
        '<span class="font-label-md text-label-md ' + (c.pendientes ? 'text-burnt-earth' : 'text-primary') + '">' + esc(c.pendientes ? c.pendientes + ' ' + T(c.pendientes === 1 ? 'movimiento por conciliar' : 'movimientos por conciliar') : T('Todo conciliado')) + '</span>');
    }).join('');
  }
  function pintaLista() {
    var tb = $('lw-ban-lista'); if (!tb) return;
    var fs = filtrados();
    var vacia = function (t) { tb.innerHTML = '<tr><td colspan="6" class="px-5 py-10 text-center font-body-md text-body-md text-on-surface-variant">' + esc(t) + '</td></tr>'; pon('suma', ''); };
    if (!D.movs.length) return vacia(T('Todavía no hay movimientos. Importa el extracto de una cuenta.'));
    if (!fs.length) return vacia($('lw-ban-f-estado').value === 'abiertos' ? T('Nada por conciliar con estos filtros.') : T('Ningún movimiento con estos filtros.'));
    var trozo = PAG ? PAG.pagina(fs) : fs;
    tb.innerHTML = trozo.map(function (m) {
      var falta = m.estado === 'parcial' ? '<span class="block font-body-sm text-body-sm text-outline fin-num">' + esc(T('falta') + ' ' + fmt(Math.abs(restante(m)), m.moneda)) + '</span>' : '';
      return '<tr class="ban-fila border-b border-outline-variant/30 hover:bg-surface-container-low" tabindex="0" data-ban-id="' + esc(m.id) + '">' +
        '<td class="px-5 py-3 fin-num font-body-sm text-body-sm">' + esc(fFecha(m.fecha)) + '</td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + esc(nombreCuenta(m.cuenta_clave)) + '</td>' +
        '<td class="px-5 py-3"><span class="font-label-md text-label-md text-on-surface" style="overflow-wrap:break-word">' + esc(m.concepto || '—') + '</span>' +
          (m.referencia ? '<span class="block font-body-sm text-body-sm text-outline">' + esc(m.referencia) + '</span>' : '') + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md ' + (m.importe > 0 ? 'text-primary' : 'text-on-surface') + '">' + esc(fmtS(m.importe, m.moneda)) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-body-sm text-body-sm text-on-surface-variant">' + (m.saldo != null ? esc(fmt(m.saldo, m.moneda)) : '—') + '</td>' +
        '<td class="px-5 py-3">' + pill(m.estado) + falta + '</td></tr>';
    }).join('');
    // suma de lo filtrado: entradas y salidas por moneda, nunca entre monedas
    var porM = {}; fs.forEach(function (m) { var x = porM[m.moneda] = porM[m.moneda] || { e: 0, s: 0 }; if (m.importe > 0) x.e += Number(m.importe); else x.s += Number(m.importe); });
    pon('suma', fs.length + ' ' + T(fs.length === 1 ? 'movimiento' : 'movimientos') + ' · ' + Object.keys(porM).sort().map(function (k) { return fmtS(porM[k].e, k) + ' / ' + fmtS(porM[k].s, k); }).join(' · '));
  }
  function pintaTodo() { llenaFiltros(); pintaCuentas(); pintaLista(); if (typeof lwIdiomaAplicar === 'function') { try { lwIdiomaAplicar(); } catch (_) { /* MUDO A PROPOSITO: traducir no tumba la pantalla */ } } }
  function refrescar() {
    return cargar().then(pintaTodo, function (e) { aviso(T('No se pudieron volver a leer los bancos') + ' (' + e.message + '). ' + T('Recarga la página.'), 'mal'); });
  }

  /* ── IMPORTAR ──────────────────────────────────────────────────────────── */
  function leeFichero(f) {
    return f.arrayBuffer().then(function (buf) {
      var t = new TextDecoder('utf-8').decode(buf);
      // algunos bancos exportan en Windows-1252: si UTF-8 deja caracteres rotos, se relee
      if (t.indexOf('�') !== -1) { try { t = new TextDecoder('windows-1252').decode(buf); } catch (_) { /* MUDO A PROPOSITO: se queda la lectura UTF-8, solo con algún acento roto */ } }
      return t;
    });
  }
  function importar() {
    var cuentas = cuentasImportables();
    if (!cuentas.length) {
      window.lwVentana(T('Importar extracto'), [{ tipo: 'nota', label: T('No hay ninguna cuenta marcada como propia de la sociedad. Ve a Cuentas, da de alta la cuenta (por ejemplo la de Statrys) y marca «De la sociedad». Luego vuelve aquí.') }],
        T('Entendido'), function () { return null; }, { sinRecarga: true, sub: T('Bancos') });
      return;
    }
    window.lwVentana(T('Importar extracto'), [
      { k: 'cuenta', label: T('Cuenta'), tipo: 'select', req: true, valor: cuentas[0].clave, opciones: cuentas.map(function (c) { return [c.clave, nombreCuenta(c.clave) + (D.perfiles[c.clave] ? ' · ' + T('columnas ya guardadas') : '')]; }) },
      { k: 'fichero', label: T('Extracto en CSV'), tipo: 'file', req: true, accept: '.csv,text/csv,text/plain' },
      { tipo: 'nota', label: T('En la banca online, exporta los movimientos en formato CSV. Si solo te deja Excel, ábrelo y guárdalo como CSV.') }
    ], T('Siguiente'), function (v) {
      var f = v.fichero;
      if (!f) return { error: { message: T('Falta el fichero.') } };
      if (/\.(xlsx?|xlsm|ods|pdf)$/i.test(f.name)) return { error: { message: T('Ese fichero no es CSV. Ábrelo en Excel y usa «Guardar como» → CSV.') } };
      if (f.size > 5 * 1024 * 1024) return { error: { message: T('El fichero pasa de 5 MB: exporta un periodo más corto.') } };
      return leeFichero(f).then(function (texto) {
        var filas = bancosCSV(texto);
        if (filas.length < 2) return { error: { message: T('El fichero no trae filas que se puedan leer.') } };
        setTimeout(function () { mapeo(v.cuenta, f.name, filas); }, 60);
        return null;
      });
    }, { sinRecarga: true, sub: T('Bancos') });
  }
  var PAPELES = [
    ['fecha', 'Fecha del movimiento', true], ['fechaValor', 'Fecha valor'], ['concepto', 'Concepto / descripción'], ['referencia', 'Referencia'],
    ['importe', 'Importe (con signo)'], ['cargo', 'Cargo / salida'], ['abono', 'Abono / entrada'], ['saldo', 'Saldo'], ['moneda', 'Moneda (columna)']
  ];
  function mapeo(cuenta, nombre, filas) {
    var perfil = Object.assign({}, D.perfiles[cuenta] || bancosProponerPerfil(filas));
    var H = window.lwCajonHtml;
    var sel = function (k, opciones, valor) {
      return '<select data-map="' + k + '" style="width:100%;padding:7px 10px;border:1px solid #E4DCCB;border-radius:8px;font-size:13px;background:#fff">' +
        opciones.map(function (o) { return '<option value="' + esc(o[0]) + '"' + (String(valor) === String(o[0]) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') + '</select>';
    };
    var fila = function (etq, control) { return '<label style="display:grid;grid-template-columns:40% 1fr;gap:10px;align-items:center;font-size:13px;color:#44483f">' + esc(etq) + control + '</label>'; };
    var cuerpo = H.nota(T('Indica qué columna del extracto es cada cosa. Se guarda para esta cuenta y la próxima vez sale solo. Hace falta la fecha y, o bien una columna de importe con signo, o bien cargo y abono.')) +
      H.seccion(T('Columnas'), '<div data-map-cols style="display:grid;gap:8px"></div>') +
      H.seccion(T('Vista previa'), '<div data-map-prev style="font-size:12.5px"></div>');
    window.lwCajon({
      titulo: T('Importar extracto'), sub: nombreCuenta(cuenta), bajoTitulo: nombre, cuerpo: cuerpo, ancho: 'min(900px,98vw)',
      acciones: [
        { texto: T('Importar'), tono: 'primario', onClick: function (ev) { guardaImportacion(cuenta, nombre, filas, perfil, ev.currentTarget); } },
        { texto: T('Cancelar'), cerrar: true }
      ]
    });
    var caja = $('lw-cajon'); if (!caja) return;
    var cont = caja.querySelector('[data-map-cols]'), prev = caja.querySelector('[data-map-prev]');
    function columnas() {
      var cab = filas[perfil.cabecera || 0] || [];
      var n = Math.max.apply(null, filas.slice(0, 30).map(function (f) { return f.length; }));
      var ops = [['', T('— ninguna —')]];
      for (var i = 0; i < n; i++) ops.push([String(i), T('Columna') + ' ' + (i + 1) + (cab[i] ? ' · ' + String(cab[i]).slice(0, 40) : '')]);
      var filasCab = []; for (var j = 0; j < Math.min(filas.length, 15); j++) filasCab.push([String(j), T('Fila') + ' ' + (j + 1) + ' · ' + filas[j].join(' | ').slice(0, 60)]);
      cont.innerHTML =
        fila(T('Fila de los títulos'), sel('cabecera', filasCab, perfil.cabecera || 0)) +
        PAPELES.map(function (p) { return fila(T(p[1]) + (p[2] ? ' *' : ''), sel(p[0], ops, perfil[p[0]] == null ? '' : perfil[p[0]])); }).join('') +
        fila(T('Formato de la fecha'), sel('formatoFecha', [['auto', T('Detectar')], ['dmy', T('Día / mes / año')], ['mdy', T('Mes / día / año')]], perfil.formatoFecha || 'auto')) +
        fila(T('Moneda si no hay columna'), sel('monedaFija', [['', '—']].concat(MONEDAS.map(function (m) { return [m, m]; })), perfil.monedaFija || ''));
    }
    function vista() {
      var r = bancosLeer(filas, perfil, cuenta, perfil.monedaFija || 'EUR');
      perfil._leido = r;
      var falta = perfil.fecha == null ? T('Falta la columna de la fecha.') : (perfil.importe == null && perfil.cargo == null && perfil.abono == null) ? T('Falta el importe (o cargo y abono).') : '';
      var porM = {}; r.movimientos.forEach(function (m) { porM[m.moneda] = (porM[m.moneda] || 0) + 1; });
      prev.innerHTML = (falta ? H.nota(falta) :
          '<p style="margin:0 0 8px">' + esc(r.movimientos.length + ' ' + T('movimientos leídos') + ' (' + Object.keys(porM).map(function (k) { return porM[k] + ' ' + k; }).join(', ') + ')' +
            (r.movimientos.length ? ' · ' + T('del') + ' ' + fFecha(r.movimientos.reduce(function (a, m) { return m.fecha < a ? m.fecha : a; }, '9999')) + ' ' + T('al') + ' ' + fFecha(r.movimientos.reduce(function (a, m) { return m.fecha > a ? m.fecha : a; }, '0000')) : '') +
            ' · ' + T('formato de fecha') + ': ' + r.formatoFecha) + '</p>') +
        (r.errores.length ? H.nota(r.errores.length + ' ' + T('filas no se pueden leer y NO se importarán') + ': ' + r.errores.slice(0, 5).map(function (e) { return T('línea') + ' ' + e.linea + ' (' + e.motivo + ')'; }).join('; ') + (r.errores.length > 5 ? '…' : '')) : '') +
        (r.movimientos.length ? '<div style="overflow-x:auto;margin-top:8px"><table class="ban-prev"><thead><tr><th>' + esc(T('Fecha')) + '</th><th>' + esc(T('Concepto')) + '</th><th>' + esc(T('Referencia')) + '</th><th style="text-align:right">' + esc(T('Importe')) + '</th><th style="text-align:right">' + esc(T('Saldo')) + '</th></tr></thead><tbody>' +
          r.movimientos.slice(0, 10).map(function (m) {
            return '<tr><td>' + esc(m.fecha) + '</td><td title="' + esc(m.concepto) + '">' + esc(m.concepto || '') + '</td><td>' + esc(m.referencia || '') + '</td><td style="text-align:right">' + esc(fmtS(m.importe, m.moneda)) + '</td><td style="text-align:right">' + esc(m.saldo != null ? fmt(m.saldo, m.moneda) : '') + '</td></tr>';
          }).join('') + '</tbody></table></div>' : '');
    }
    cont.addEventListener('change', function (ev) {
      var s = ev.target.closest && ev.target.closest('[data-map]'); if (!s) return;
      var k = s.getAttribute('data-map'), v = s.value;
      if (k === 'cabecera') { perfil.cabecera = Number(v); columnas(); }
      else if (k === 'formatoFecha') perfil.formatoFecha = v;
      else if (k === 'monedaFija') perfil.monedaFija = v || null;
      else {
        perfil[k] = v === '' ? null : Number(v);
        // importe con signo y cargo/abono son excluyentes: se lee uno u otro
        if (k === 'importe' && perfil.importe != null) { perfil.cargo = null; perfil.abono = null; columnas(); }
        if ((k === 'cargo' || k === 'abono') && perfil[k] != null && perfil.importe != null) { perfil.importe = null; columnas(); }
      }
      vista();
    });
    columnas(); vista();
  }
  function guardaImportacion(cuenta, nombre, filas, perfil, boton) {
    var r = perfil._leido || bancosLeer(filas, perfil, cuenta, perfil.monedaFija || 'EUR');
    if (!r.movimientos.length) { avisoRapido(T('No hay ningún movimiento que importar con estas columnas.'), true); return; }
    if (r.movimientos.length > 5000) { avisoRapido(T('Máximo 5.000 movimientos por importación: exporta el extracto por meses.'), true); return; }
    if (boton) { boton.disabled = true; boton.textContent = T('Importando…'); }
    var mapeoLimpio = {}; ['cabecera', 'fecha', 'fechaValor', 'concepto', 'referencia', 'importe', 'cargo', 'abono', 'saldo', 'moneda', 'formatoFecha', 'monedaFija'].forEach(function (k) { mapeoLimpio[k] = perfil[k] == null ? null : perfil[k]; });
    // El perfil es comodidad: si no se guarda, la importación sigue igual.
    // Insert o update a mano: un upsert reescribe la clave, y el GRANT de update es solo de `mapeo`.
    var guardaPerfil = (D.perfiles[cuenta]
      ? sb.from('bancos_perfiles').update({ mapeo: mapeoLimpio }).eq('cuenta_clave', cuenta).select('cuenta_clave')
      : sb.from('bancos_perfiles').insert({ cuenta_clave: cuenta, mapeo: mapeoLimpio }).select('cuenta_clave')
    ).then(function (x) { return !(x.error || !x.data || !x.data.length); }, function () { return false; });
    var carga = r.movimientos.map(function (m) { return { fecha: m.fecha, fecha_valor: m.fecha_valor, concepto: m.concepto, referencia: m.referencia, importe: m.importe, moneda: m.moneda, saldo: m.saldo, orden: m.linea, huella: m.huella }; });
    guardaPerfil.then(function (perfilOk) {
      return sb.rpc('bancos_importar', { p_cuenta: cuenta, p_fichero: nombre, p_filas: carga }).then(function (res) {
        if (res.error) { if (boton) { boton.disabled = false; boton.textContent = T('Importar'); } avisoRapido(errDe(res, T('No se pudo importar')), true); return; }
        if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
        var d = res.data || {};
        limpiaAvisos();
        aviso(nombreCuenta(cuenta) + ': ' + (d.nuevas || 0) + ' ' + T('movimientos nuevos') + ', ' + (d.duplicadas || 0) + ' ' + T('ya estaban importados') +
          (r.errores.length ? ', ' + r.errores.length + ' ' + T('filas sin leer') : '') + '.' + (perfilOk ? '' : ' ' + T('Las columnas no se han podido guardar: la próxima vez habrá que indicarlas otra vez.')), 'bien');
        $('lw-ban-f-cuenta').value = ''; $('lw-ban-f-estado').value = 'abiertos';
        return refrescar();
      });
    });
  }

  /* ── CONCILIAR ─────────────────────────────────────────────────────────── */
  function conciliar(m, lineas) {
    return sb.rpc('bancos_conciliar', { p_mov: m.id, p_lineas: lineas }).then(function (r) { return r.error ? { error: { message: errDe(r) } } : r; });
  }
  // Un traspaso se apunta en LOS DOS movimientos: la salida de una cuenta y la entrada en la otra
  function contrapartida(m, otroId, importeMov, naturaleza) {
    var o = movPorId[otroId]; if (!o) return Promise.resolve(null);
    var imp = Math.min(Math.abs(importeMov), Math.abs(restante(o)));
    if (imp <= 0.005) return Promise.resolve(null);
    return conciliar(o, [{ tipo: 'traspaso', ref_id: m.id, importe_mov: r2(Math.sign(o.importe) * imp), naturaleza: naturaleza || 'interno' }]);
  }
  /* Conciliar desde una sugerencia. La diferencia (una SWIFT recortada, la
     comisión del banco sumada a un pago) nunca desaparece:
      - ENTRADA que llega recortada: la línea explica todo lo que entró y el
        documento queda cubierto entero (importe_doc = lo que valía); la
        diferencia queda escrita en la línea, visible en la ficha.
      - SALIDA mayor que el documento: línea del documento + línea de
        «Comisión del banco» por la diferencia. */
  function conciliaSugerencia(m, c) {
    var falta = restante(m), signo = Math.sign(m.importe), abs = Math.abs(falta), obj = r2(c.pendiente != null ? c.pendiente : c.importe);
    var lineas;
    if (c.tipo === 'traspaso') lineas = [{ tipo: 'traspaso', ref_id: c.id, importe_mov: r2(signo * Math.min(abs, obj)), naturaleza: 'interno' }];
    else if (abs >= obj) {
      lineas = [{ tipo: c.tipo, ref_id: c.id, importe_mov: r2(signo * obj), importe_doc: obj }];
      if (signo < 0 && abs - obj > 0.005 && abs - obj <= bancosTolerancia(abs)) lineas.push({ tipo: 'comision_bancaria', importe_mov: r2(signo * (abs - obj)), nota: T('Diferencia con') + ' ' + (c.numero || TIPO[c.tipo]) });
    } else lineas = [{ tipo: c.tipo, ref_id: c.id, importe_mov: r2(signo * abs), importe_doc: obj, nota: T('Llegó') + ' ' + fmt(abs, m.moneda) + ' ' + T('de') + ' ' + fmt(obj, c.moneda) + ' (' + T('diferencia') + ' ' + fmt(r2(obj - abs), m.moneda) + ')' }];
    return conciliar(m, lineas).then(function (r) {
      if (r.error) return r;
      return c.tipo === 'traspaso' ? contrapartida(m, c.id, lineas[0].importe_mov, 'interno').then(function (r2_) { return r2_ && r2_.error ? { error: { message: T('El traspaso quedó apuntado en esta cuenta, pero no en la otra') + ': ' + r2_.error.message } } : r; }) : r;
    });
  }
  function opcionesDoc(m, tipo, cands) {
    return [['', T('— elige —')]].concat(cands.filter(function (c) { return c.tipo === tipo; })
      .sort(function (a, b) { return Math.abs(dias(a.fecha || '2000-01-01', m.fecha)) - Math.abs(dias(b.fecha || '2000-01-01', m.fecha)); })
      .slice(0, 300)
      .map(function (c) { return [c.id, [c.numero, fFecha(c.fecha), fmt(c.pendiente, c.moneda) + (c.pendiente !== c.importe ? ' ' + T('pendiente de') + ' ' + fmt(c.importe, c.moneda) : ''), String(c.texto || '').slice(0, 50)].filter(Boolean).join(' · ')]; }));
  }
  function conciliaMano(m) {
    var entra = m.importe > 0, cands = candidatosPara(m);
    var tipos = (entra ? ['recibi', 'traspaso', 'retencion_sufrida', 'otro'] : ['gasto', 'pph', 'comision', 'traspaso', 'comision_bancaria', 'otro']);
    var conDoc = ['recibi', 'gasto', 'pph', 'comision', 'traspaso'];
    var campos = [{ k: 'tipo', label: T('Qué lo explica'), tipo: 'select', req: true, valor: tipos[0], opciones: tipos.map(function (t) { return [t, T(TIPO[t])]; }) }];
    tipos.filter(function (t) { return conDoc.indexOf(t) !== -1; }).forEach(function (t) {
      campos.push({ k: 'doc_' + t, label: T('Cuál'), tipo: 'select', valor: '', opciones: opcionesDoc(m, t, cands), visibleSi: { k: 'tipo', valores: [t] } });
    });
    if (!D.leidos.gastos && !entra) campos.push({ tipo: 'nota', label: T('No ves los gastos: para enlazar con uno hace falta la casilla «Gastos y proveedores».'), visibleSi: { k: 'tipo', valores: ['gasto', 'pph'] } });
    if (!D.leidos.comisiones && !entra) campos.push({ tipo: 'nota', label: T('No ves las comisiones: para enlazar con una hace falta la casilla de Comisiones.'), visibleSi: { k: 'tipo', valores: ['comision'] } });
    campos.push(
      { k: 'importe_mov', label: T('Importe de esta línea en el banco (sin signo)'), req: true, medio: 1, valor: String(Math.abs(restante(m))) },
      { k: 'importe_doc', label: T('Importe en la moneda del documento'), medio: 1, valor: '', ayuda: T('Solo si el documento está en otra moneda.'), visibleSi: { k: 'tipo', valores: ['recibi', 'gasto', 'pph', 'comision', 'traspaso'] } },
      { k: 'naturaleza', label: T('Qué es este traspaso'), tipo: 'select', valor: 'interno', opciones: NATURALEZA.map(function (n) { return [n[0], T(n[1])]; }), visibleSi: { k: 'tipo', valores: ['traspaso'] } },
      { tipo: 'nota', label: T('Si el traspaso va a una cuenta de otra sociedad del grupo, elige si es capital, préstamo o pago: cuenta para el reporting entre sociedades.'), visibleSi: { k: 'tipo', valores: ['traspaso'] } },
      { k: 'nota', label: T('Nota'), tipo: 'textarea', valor: '' }
    );
    window.lwVentana(T('Conciliar a mano'), campos, T('Conciliar'), function (v) {
      var imp = typeof lwParseImporte === 'function' ? lwParseImporte(v.importe_mov) : Number(String(v.importe_mov).replace(',', '.'));
      if (!(imp > 0)) return { error: { message: T('El importe no es válido.') } };
      if (imp > Math.abs(restante(m)) + 0.005) return { error: { message: T('Supera lo que falta por explicar de este movimiento') + ' (' + fmt(Math.abs(restante(m)), m.moneda) + ').' } };
      var l = { tipo: v.tipo, importe_mov: r2(Math.sign(m.importe) * imp), nota: v.nota || null };
      if (conDoc.indexOf(v.tipo) !== -1) {
        l.ref_id = v['doc_' + v.tipo]; if (!l.ref_id) return { error: { message: T('Elige el documento.') } };
        if (v.importe_doc) { var d = typeof lwParseImporte === 'function' ? lwParseImporte(v.importe_doc) : Number(v.importe_doc); if (!(d > 0)) return { error: { message: T('El importe del documento no es válido.') } }; l.importe_doc = r2(d); }
      }
      if (v.tipo === 'traspaso') l.naturaleza = v.naturaleza || 'interno';
      if (v.tipo === 'otro' && !l.nota) return { error: { message: T('Con «Otro» hace falta explicar qué es en la nota.') } };
      return conciliar(m, [l]).then(function (r) {
        if (r.error) return r;
        var sigue = v.tipo === 'traspaso' ? contrapartida(m, l.ref_id, l.importe_mov, l.naturaleza) : Promise.resolve(null);
        return sigue.then(function (x) {
          if (x && x.error) avisoRapido(T('El traspaso quedó apuntado en esta cuenta, pero no en la otra') + ': ' + x.error.message, true);
          if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
          refrescar(); return null;
        });
      });
    }, { sinRecarga: true, sub: nombreCuenta(m.cuenta_clave) + ' · ' + fmtS(m.importe, m.moneda) });
  }
  function deshacer(m, linea) {
    return lwConfirmar({ titulo: T('Deshacer esta línea'), cuerpo: esc(T('El movimiento vuelve a quedar por conciliar en esa parte. La línea no se borra: queda anulada en el historial.')), confirmar: T('Deshacer') }).then(function (ok) {
      if (!ok) return;
      return sb.rpc('bancos_desconciliar', { p_linea: linea.id }).then(function (r) {
        if (r.error) { avisoRapido(errDe(r, T('No se pudo deshacer')), true); return; }
        // un traspaso tiene su pareja en la otra cuenta: se deshace también
        var pareja = linea.tipo === 'traspaso' ? D.lineas.filter(function (x) { return x.tipo === 'traspaso' && x.movimiento_id === linea.ref_id && x.ref_id === m.id; })[0] : null;
        return (pareja ? sb.rpc('bancos_desconciliar', { p_linea: pareja.id }) : Promise.resolve({})).then(function (r2_) {
          if (r2_ && r2_.error) avisoRapido(errDe(r2_, T('Deshecho aquí, pero no en la otra cuenta')), true);
          if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
          return refrescar();
        });
      });
    });
  }
  function ignora(m) {
    window.lwVentana(T('Ignorar movimiento'), [
      { tipo: 'nota', label: T('Para movimientos que no hay que explicar con ningún documento (por ejemplo, un cargo devuelto el mismo día). Queda con su motivo y se puede deshacer.') },
      { k: 'motivo', label: T('Motivo'), tipo: 'textarea', req: true, valor: '' }
    ], T('Ignorar'), function (v) {
      return sb.rpc('bancos_ignorar', { p_mov: m.id, p_motivo: v.motivo }).then(function (r) {
        if (r.error) return { error: { message: errDe(r) } };
        if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
        refrescar(); return null;
      });
    }, { sinRecarga: true, sub: fmtS(m.importe, m.moneda) });
  }
  function designora(m) {
    sb.rpc('bancos_designorar', { p_mov: m.id }).then(function (r) {
      if (r.error) { avisoRapido(errDe(r, T('No se pudo quitar la marca')), true); return; }
      if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
      refrescar();
    });
  }

  /* ── FICHA ─────────────────────────────────────────────────────────────── */
  function ficha(m) {
    var H = window.lwCajonHtml, docs = documentos(), falta = restante(m), ls = lineasDe(m.id);
    var sugs = (m.estado !== 'ignorado' && Math.abs(falta) > 0.005) ? bancosSugerencias({ importe: falta, moneda: m.moneda, fecha: m.fecha, concepto: m.concepto, referencia: m.referencia }, candidatosPara(m)) : [];
    var btn = function (attr, i, texto) { return '<button type="button" ' + attr + '="' + i + '" style="border:1px solid #E4DCCB;background:#fff;border-radius:8px;padding:5px 10px;font-weight:600;font-size:12.5px;cursor:pointer;white-space:nowrap">' + esc(texto) + '</button>'; };
    var cuerpo = H.seccion(T('Movimiento'),
        H.dato(T('Estado'), pill(m.estado), { html: true }) + H.dato(T('Cuenta'), nombreCuenta(m.cuenta_clave)) +
        H.dato(T('Fecha'), fFecha(m.fecha)) + H.dato(T('Fecha valor'), m.fecha_valor ? fFecha(m.fecha_valor) : null) +
        H.dato(T('Importe'), fmtS(m.importe, m.moneda)) + H.dato(T('Saldo tras el movimiento'), m.saldo != null ? fmt(m.saldo, m.moneda) : null) +
        H.dato(T('Referencia'), m.referencia) + H.dato(T('Concepto'), m.concepto) +
        (m.estado === 'parcial' ? H.dato(T('Falta por explicar'), fmt(Math.abs(falta), m.moneda)) : '')) +
      (m.estado === 'ignorado' ? H.nota(T('Ignorado') + ': ' + (m.ignorado_motivo || '')) : '') +
      H.seccion(T('Lo explica'), ls.length ? H.tabla([T('Qué'), T('Documento'), T('En el banco'), T('En el documento'), ''], ls.map(function (l, i) {
        var dif = l.importe_doc != null && (l.moneda_doc || m.moneda) === m.moneda && Math.abs(Math.abs(l.importe_doc) - Math.abs(l.importe_mov)) > 0.005;
        return [esc(T(TIPO[l.tipo] || l.tipo)) + (l.naturaleza && l.naturaleza !== 'interno' ? '<br><small style="color:#75786e">' + esc(T((NATURALEZA.filter(function (n) { return n[0] === l.naturaleza; })[0] || ['', l.naturaleza])[1])) + '</small>' : ''),
          esc(nombraDoc(l.tipo, l.ref_id, docs) || '—') + (l.nota ? '<br><small style="color:#75786e">' + esc(l.nota) + '</small>' : ''),
          '<span class="fin-num">' + esc(fmtS(l.importe_mov, m.moneda)) + '</span>',
          '<span class="fin-num">' + (l.importe_doc != null ? esc(fmt(l.importe_doc, l.moneda_doc || m.moneda)) : '—') + '</span>' + (dif ? '<br><small style="color:#9E2F26">' + esc(T('diferencia') + ' ' + fmt(r2(Math.abs(l.importe_doc) - Math.abs(l.importe_mov)), m.moneda)) + '</small>' : '') +
            (l.tipo_cambio ? '<br><small style="color:#75786e">' + esc(T('cambio') + ' ' + Number(l.tipo_cambio).toFixed(4)) + '</small>' : ''),
          btn('data-ban-deshacer', i, T('Deshacer'))];
      })) : '<p style="margin:0;font-size:13px;color:#75786e">' + esc(T('Nada todavía.')) + '</p>') +
      ((m.estado !== 'ignorado' && Math.abs(falta) > 0.005) ? H.seccion(T('Sugerencias'), sugs.length ? H.tabla([T('Qué'), T('Documento'), T('Importe'), ''], sugs.map(function (s, i) {
          return [esc(T(TIPO[s.tipo])) + (s.nombra ? '<br><small style="color:#104C4F;font-weight:600">' + esc(T('el concepto lo nombra')) + '</small>' : ''),
            esc([s.numero, s.texto, fFecha(s.fecha)].filter(Boolean).join(' · ')) + '<br><small style="color:#75786e">' + esc(s.dias === 0 ? T('mismo día') : s.dias + ' ' + T(s.dias === 1 ? 'día de diferencia' : 'días de diferencia')) + '</small>',
            '<span class="fin-num">' + esc(fmt(s.pendiente != null ? s.pendiente : s.importe, s.moneda)) + '</span>' + (s.diferencia ? '<br><small style="color:#9E2F26">' + esc(fmt(Math.abs(s.diferencia), m.moneda) + ' ' + T(s.diferencia < 0 ? 'menos en el banco' : 'más en el banco')) + '</small>' : ''),
            btn('data-ban-sug', i, T('Conciliar'))];
        })) : '<p style="margin:0;font-size:13px;color:#75786e">' + esc(T('Ningún documento con el mismo importe y fecha cercana. Concílialo a mano.')) + '</p>') : '');
    var acciones = [];
    if (m.estado !== 'ignorado' && Math.abs(falta) > 0.005) acciones.push({ texto: T('Conciliar a mano'), tono: 'primario', onClick: function () { conciliaMano(m); } });
    if (m.estado !== 'ignorado' && !ls.length) acciones.push({ texto: T('Ignorar'), onClick: function () { ignora(m); } });
    if (m.estado === 'ignorado') acciones.push({ texto: T('Quitar «ignorado»'), onClick: function () { designora(m); } });
    acciones.push({ texto: T('Cerrar'), cerrar: true });
    window.lwCajon({ titulo: m.concepto || T('Movimiento'), sub: nombreCuenta(m.cuenta_clave) + ' · ' + fFecha(m.fecha), bajoTitulo: fmtS(m.importe, m.moneda), cuerpo: cuerpo, acciones: acciones, ancho: 'min(760px,98vw)' });
    var caja = $('lw-cajon'); if (!caja) return;
    caja.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-ban-sug],[data-ban-deshacer]'); if (!b) return;
      if (b.hasAttribute('data-ban-deshacer')) { var l = ls[Number(b.getAttribute('data-ban-deshacer'))]; if (l) deshacer(m, l); return; }
      var s = sugs[Number(b.getAttribute('data-ban-sug'))]; if (!s) return;
      b.disabled = true; b.textContent = T('Conciliando…');
      conciliaSugerencia(m, s).then(function (r) {
        if (r && r.error) { b.disabled = false; b.textContent = T('Conciliar'); avisoRapido(r.error.message, true); return; }
        if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
        refrescar().then(function () { var nuevo = movPorId[m.id]; if (nuevo && nuevo.estado === 'parcial') ficha(nuevo); });
      });
    });
  }

  /* ── CSV ───────────────────────────────────────────────────────────────── */
  function exportaCSV() {
    var q = function (v) { v = bancosCeldaSegura(v == null ? '' : String(v)); return /[;"\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    var filas = [['Fecha', 'Cuenta', 'Concepto', 'Referencia', 'Importe', 'Moneda', 'Saldo', 'Estado', 'Conciliado', 'Lo explica', 'Motivo si ignorado']]
      .concat(filtrados().map(function (m) {
        return [m.fecha, nombreCuenta(m.cuenta_clave), m.concepto, m.referencia, m.importe, m.moneda, m.saldo, T((ESTADO[m.estado] || [m.estado])[0]), m.conciliado,
          lineasDe(m.id).map(function (l) { return T(TIPO[l.tipo] || l.tipo); }).join(' + '), m.ignorado_motivo];
      }));
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob(['﻿' + filas.map(function (f) { return f.map(q).join(';'); }).join('\r\n')], { type: 'text/csv;charset=utf-8' }));
    a.download = 'bancos_' + hoy + '.csv'; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  }

  /* ── ARRANQUE ──────────────────────────────────────────────────────────── */
  function monta(aut) {
    sb = aut.sb;
    if (typeof bancosLeer !== 'function' || typeof window.lwVentana !== 'function' || typeof window.lwCajon !== 'function') {
      aviso(T('No cargaron las piezas de la pantalla (bancos.js / editores.js). Recarga la página; si sigue, avisa a Desarrollo.'), 'mal'); return;
    }
    PAG = (typeof lwPaginador === 'function') ? lwPaginador('#lw-ban-pag', { porPagina: 50 }) : null;
    if (PAG) PAG.alCambiar(pintaLista);
    cargar().then(function () {
      pintaTodo();
      var viejos = (D.resumen || []).filter(function (c) { return c.ultimo && dias(hoy, c.ultimo) > 7; });
      if (viejos.length) aviso(T('Extractos con más de 7 días') + ': ' + viejos.map(function (c) { return nombreCuenta(c.cuenta) + ' (' + fFecha(c.ultimo) + ')'; }).join(', ') + '. ' + T('Lo que ha pasado después no está aquí: importa el extracto nuevo.'));
      if (D.resumen && !D.leidos.gastos) aviso(T('No ves los gastos: las salidas no se podrán enlazar con un gasto hasta que te marquen «Gastos y proveedores» en Usuarios.'));
    }, function (e) {
      aviso(T('No se pudieron leer los bancos') + ' (' + e.message + '). ' + T('Si eres admin, pide que te marquen «Bancos» en Usuarios.'), 'mal');
      $('lw-ban-lista').innerHTML = ''; $('lw-ban-cuentas').innerHTML = '';
    });
    ['lw-ban-f-cuenta', 'lw-ban-f-estado', 'lw-ban-f-mes'].forEach(function (id) { $(id).addEventListener('change', pintaLista); });
    var tb; $('lw-ban-buscar').addEventListener('input', function () { clearTimeout(tb); tb = setTimeout(pintaLista, 150); });
    $('lw-ban-importar').addEventListener('click', function (ev) { ev.stopPropagation(); importar(); });
    $('lw-ban-csv').addEventListener('click', exportaCSV);
    var abre = function (ev) {
      if (ev.type === 'keydown' && ev.key !== 'Enter' && ev.key !== ' ') return;
      var tr = ev.target.closest && ev.target.closest('tr[data-ban-id]'); if (!tr) return;
      if (ev.type === 'keydown') ev.preventDefault();
      var m = movPorId[tr.getAttribute('data-ban-id')]; if (m) ficha(m);
    };
    $('lw-ban-lista').addEventListener('click', abre); $('lw-ban-lista').addEventListener('keydown', abre);
  }
  function arranca() {
    if (!window.LW_AUTH) { aviso(T('Sin sesión: no se carga nada.'), 'mal'); return; }
    window.LW_AUTH.then(function (aut) {
      var rol = aut.ficha && aut.ficha.rol;
      if (rol !== 'admin' && rol !== 'super_admin') { aviso(T('Esta pantalla es de dirección (admin).'), 'mal'); return; }
      monta(aut);
    });
  }
  /* Espera a DOMContentLoaded (mismo motivo que panel-gastos.js: este script
     es `defer` y va antes que editores.js y dialogo.js). */
  var arrancado = false;
  function unaVez() { if (!arrancado) { arrancado = true; arranca(); } }
  if (document.readyState === 'complete') unaVez();
  else { document.addEventListener('DOMContentLoaded', unaVez); window.addEventListener('load', unaVez); }
})();
