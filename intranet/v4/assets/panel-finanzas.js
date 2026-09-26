/* panel-finanzas.js — la pantalla /v4/finanzas/ (24-sep-2026). SOLO LECTURA.
 *
 * Tres piezas y cada una en su sitio, que es la forma de un módulo del
 * AxisWorks ERP (encargos/20260924_estudio_erp_modular.md):
 *   · cargar(sb)  → trae las filas por las MISMAS vías que el resto de la
 *                   suite (RPC de equipo, nunca un .from() de contratos o
 *                   facturas, que solo devuelve «lo mío»), y las normaliza al
 *                   contrato de entrada de finModelo().
 *   · finModelo() → el cálculo, en contracts/assets/finanzas.js, puro y con
 *                   su test (contracts/finanzas.test.js).
 *   · pinta*()    → este fichero, un bloque cada una.
 * Este fichero no vive en datos.js a propósito: son 8.000 líneas compartidas
 * por 30 pantallas y con sesiones en paralelo encima; un módulo que se va a
 * mover al producto no puede nacer dentro de otro.
 *
 * Reglas (revisión previa #62, Administración + Datos, 24-sep):
 *  - Monedas NUNCA sumadas: un selector elige cuál se ve, EUR primero.
 *  - Un bloque cuya consulta falla dice que falló, en su sitio; los demás
 *    siguen. «—» en una cifra suelta, nunca un 0 falso.
 *  - Solicitudes y comisiones solo se piden si la ficha tiene la casilla que
 *    la RLS exige; sin ella el bloque dice «sin permiso», no «0 €» — la RLS
 *    devolvería 0 filas sin error y se leería como «no se debe nada».
 *  - Se lee todo PAGINADO: PostgREST corta en su máximo de filas sin avisar,
 *    y un total cortado que no avisa es un número que miente.
 *  - Nunca `contratos.datos` (140 MB de jsonb en TOAST): solo columnas. */
(function () {
  'use strict';
  if (!/\/finanzas\/?(index\.html)?$/.test(location.pathname)) return;

  var T = function (s) { return (typeof lwT === 'function') ? lwT(s) : s; };
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  function fmt(n, m) {
    if (n == null) return '—';
    if (typeof lwFormatoImporte === 'function') return lwFormatoImporte(n, m);
    return new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 }).format(Math.round(Number(n) || 0)) + (m ? ' ' + m : '');
  }
  function num(n) { return new Intl.NumberFormat('es-ES').format(n); }
  function hoyLocal() {   // fecha LOCAL (Bali, UTC+8), no toISOString(): revisión previa #57
    var d = new Date();
    return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
  }
  var $ = function (id) { return document.getElementById(id); };
  function pon(clave, texto) { document.querySelectorAll('[data-fin="' + clave + '"]').forEach(function (e) { e.textContent = texto; }); }
  function falloEn(el, que) {
    if (el) el.innerHTML = '<p class="py-6 text-center font-body-md text-body-md text-error">' + esc(T('No se pudo cargar') + ' ' + que + '. ' + T('Recarga la página; si sigue, avisa a Desarrollo.')) + '</p>';
  }
  function aviso(texto, tono) {
    var caja = $('lw-fin-avisos'); if (!caja) return;
    var p = document.createElement('div');
    p.setAttribute('role', 'status');
    p.className = 'rounded-xl border px-5 py-4 flex items-start gap-3 font-body-sm text-body-sm ' +
      (tono === 'mal' ? 'border-error/40 bg-error-container/40 text-on-surface' : 'border-burnt-earth/30 bg-surface-alt text-on-surface-variant');
    p.innerHTML = '<span class="material-symbols-outlined text-[20px] shrink-0 ' + (tono === 'mal' ? 'text-error' : 'text-burnt-earth') + '">' + (tono === 'mal' ? 'report' : 'info') + '</span><p>' + esc(texto) + '</p>';
    caja.appendChild(p);
  }
  function nombreSociedad(clave) {
    if (!clave) return T('(sin sociedad)');
    try {
      var soc = (typeof SOCIEDADES !== 'undefined') && SOCIEDADES[clave];
      if (soc && (soc.razon || soc.marca)) return soc.razon || soc.marca;
    } catch (e) { /* entities.js aún no ha cargado: cae a la clave arreglada */ }
    return String(clave).replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  /* ── CARGA ─────────────────────────────────────────────────────────────── */
  var PAGINA = 1000;
  /* Pide de 1.000 en 1.000 hasta que una página llega corta. `hacer()`
     construye la consulta de cero cada vez (un builder de supabase-js no se
     reutiliza). Orden por id: sin orden estable, dos páginas pueden repetir o
     saltarse filas. */
  function todas(hacer, que, col) {
    var filas = [];
    function pag(desde) {
      return hacer().order(col || 'id', { ascending: true }).range(desde, desde + PAGINA - 1).then(function (r) {
        if (r.error) { console.error('[finanzas] ' + que + ':', r.error); throw new Error(que); }
        filas = filas.concat(r.data || []);
        return (r.data || []).length === PAGINA && desde < 20000 ? pag(desde + PAGINA) : filas;
      });
    }
    return pag(0);
  }
  function puede(ficha, casilla) {
    return !!ficha && (ficha.rol === 'super_admin' || (ficha.herramientas || []).indexOf(casilla) !== -1);
  }

  function cargar(sb, ficha) {
    /* Cada tabla pide SU casilla (RLS): solicitudes → `comisiones`,
       comisiones devengadas → `comisiones_reparto`. Se piden por separado: con
       una sola casilla se ve media cifra, y el bloque dice cuál falta. */
    var verSol = puede(ficha, 'comisiones'), verCom = puede(ficha, 'comisiones_reparto');
    /* Gastos (módulo `gastos`, 24-sep): la RLS exige es_admin() Y la casilla;
       sin ella se devolverían 0 filas sin error. Se decide aquí y el panel dice
       «sin permiso», nunca «0 € de gastos». */
    var verGas = puede(ficha, 'gastos');
    /* Quién cerró cada venta: MISMO candado que el resto de la suite
       ('ranking' o super_admin, nunca 'admin' a secas: closerPuede() en
       datos.js). La RPC ya filtra por puede('ranking'); sin la casilla
       devolvería 0 filas y la tabla diría «nadie ha vendido nada». */
    var verCloser = puede(ficha, 'ranking');
    var fuentes = {
      contratos: todas(function () { return sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,contrato_padre_id,created_at,liberado_en'); }, 'contratos'),
      cobrado: todas(function () { return sb.rpc('contratos_cobrado_equipo').select('contrato_id,cobrado'); }, 'cobrado por contrato', 'contrato_id'),
      vencimientos: todas(function () { return sb.from('contrato_vencimientos').select('id,contrato_id,orden,descripcion,pct,monto,fecha,no_facturar'); }, 'calendario de pagos'),
      facturas: todas(function () { return sb.rpc('facturas_equipo').select('id,numero,tipo,sociedad,total,moneda,anulada,fecha_emision,created_at,contrato_id,proyecto_nombre,cuenta:datos->fields->>cuenta,venc:datos->fields->>fecha_vencimiento'); }, 'facturas'),
      /* De quién es cada cuenta (LAW-305): la lee cualquier sesión. Si falla,
         todo recibí queda «sin clasificar» y se dice. */
      cuentas: todas(function () { return sb.from('cuentas_bancarias').select('clave,es_propia,es_escrow'); }, 'cuentas bancarias', 'clave'),
      pendiente: todas(function () { return sb.rpc('facturas_pendiente_equipo').select('factura_id,pendiente'); }, 'pendiente por factura', 'factura_id'),
      unidades: todas(function () { return sb.from('unidades').select('id,proyecto,estado,precio,moneda'); }, 'unidades'),
      solicitudes: verSol ? todas(function () { return sb.from('solicitudes_pago').select('id,estado,importe,moneda'); }, 'solicitudes de pago') : Promise.resolve(null),
      comisiones: verCom ? todas(function () { return sb.from('comisiones_devengadas').select('id,estado,importe,importe_ajustado,moneda,solicitud_id,pagado_en,anulado_en,contrato_raiz_id'); }, 'comisiones devengadas') : Promise.resolve(null),
      gastos: verGas ? todas(function () { return sb.from('gastos').select('id,estado,moneda,total,base,pph_retenido,pph_ingresado_el,fecha,vence_el,pagado_el,sociedad,proyectos(nombre),gasto_categorias(grupo)'); }, 'gastos') : Promise.resolve(null),
      closer: verCloser ? todas(function () { return sb.rpc('crm_contratos_para_atribuir', { p_solo_pendientes: false }).select('contrato_id,closer_email'); }, 'closers', 'contrato_id') : Promise.resolve(null),
      bancos: sb.rpc('bancos_resumen', { p_anio: new Date().getFullYear() }).then(function (r) { if (r.error) { console.error('[finanzas] bancos:', r.error); throw new Error('bancos'); } return r.data; }),
      equipo: sb.from('usuarios').select('email,nombre').then(function (r) { return r.error ? [] : (r.data || []); }, function () { return []; }),
      sociedades: (typeof cargarSociedades === 'function') ? cargarSociedades(sb).catch(function (e) { console.error('[finanzas] sociedades:', e); return null; }) : Promise.resolve(null)
    };
    var claves = Object.keys(fuentes);
    return Promise.all(claves.map(function (k) {
      return fuentes[k].then(function (v) { return { ok: true, v: v }; }, function (e) { return { ok: false, e: e }; });
    })).then(function (rs) {
      var out = { fallos: {}, verSol: verSol, verCom: verCom, verGas: verGas, verCloser: verCloser };
      rs.forEach(function (r, i) { if (r.ok) out[claves[i]] = r.v; else out.fallos[claves[i]] = true; });
      return out;
    });
  }

  function normaliza(d, hoy) {
    var cobradoPorId = {};
    (d.cobrado || []).forEach(function (x) { cobradoPorId[x.contrato_id] = Number(x.cobrado) || 0; });
    var pend = {};
    (d.pendiente || []).forEach(function (x) { pend[x.factura_id] = Number(x.pendiente) || 0; });
    var facturas = d.facturas || [];
    var cuentaDe = {};
    (d.cuentas || []).forEach(function (c) { cuentaDe[c.clave] = c; });
    var destinoDe = function (clave) {
      /* Recibí SIN cuenta o con «otros»: caja de la sociedad (owner, 24-sep-2026:
         «Todo cuenta», sobre los 16 recibís de 2026 que no dicen cuenta,
         478.600 €). Una clave que NO está en la tabla (cuenta borrada o mal
         escrita) sigue «sin clasificar»: esa sí hay que mirarla. */
      if (!clave || clave === 'otros') return 'propia';
      var c = cuentaDe[clave];
      if (!c) return 'sin_clasificar';
      if (c.es_escrow) return 'escrow';
      return c.es_propia === true ? 'propia' : c.es_propia === false ? 'tercero' : 'sin_clasificar';
    };
    // firmado = bloqueado, nunca fecha_firma (suite_lawang.md)
    var firmado = {};
    (d.contratos || []).forEach(function (c) { firmado[c.id] = !!c.bloqueado && !c.liberado_en; });
    return {
      hoyISO: hoy,
      contratos: d.contratos || [],
      cobradoPorId: cobradoPorId,
      vencimientos: d.vencimientos || [],
      recibis: facturas.filter(function (f) { return f.tipo === 'recibi'; }).map(function (f) {
        return { tipo: 'recibi', contrato_id: f.contrato_id, total: f.total, moneda: f.moneda, anulada: f.anulada, sociedad: f.sociedad, proyecto_nombre: f.proyecto_nombre, destino: destinoDe(f.cuenta), fecha: f.fecha_emision || String(f.created_at || '').slice(0, 10) };
      }),
      /* Sin la RPC de pendiente no se inventa: una factura sin su pendiente
         calculado NO entra (se diría que se debe el total de facturas ya
         cobradas). El bloque avisa del fallo. */
      facturas: d.fallos.pendiente ? [] : facturas.filter(function (f) { return f.tipo === 'factura'; }).map(function (f) {
        var c = f.contrato_id && firmado.hasOwnProperty(f.contrato_id) ? firmado[f.contrato_id] : null;
        return { tipo: f.tipo, sociedad: f.sociedad, moneda: f.moneda, anulada: f.anulada, venc: f.venc, fecha_emision: f.fecha_emision, pendiente: f.id in pend ? pend[f.id] : null, contrato_firmado: c };
      }),
      unidades: d.unidades || [],
      solicitudes: d.solicitudes == null ? null : d.solicitudes,
      comisiones: d.comisiones == null ? null : d.comisiones,
      closerDe: (d.closer == null || d.fallos.closer) ? null : (function () { var m = {}; d.closer.forEach(function (x) { if (x.closer_email) m[x.contrato_id] = x.closer_email; }); return m; })(),
      gastos: (d.gastos == null || d.fallos.gastos) ? null : d.gastos.map(function (g) {
        return { estado: g.estado, moneda: g.moneda, total: g.total, base: g.base, pph_retenido: g.pph_retenido, pph_ingresado_el: g.pph_ingresado_el,
                 fecha: g.fecha, vence_el: g.vence_el, pagado_el: g.pagado_el, sociedad: g.sociedad,
                 proyecto_nombre: g.proyectos ? g.proyectos.nombre : '', grupo: g.gasto_categorias ? g.gasto_categorias.grupo : 'general' };
      })
    };
  }

  /* ── PINTADO ───────────────────────────────────────────────────────────── */
  var ESTADO_STOCK = { disponible: 'Disponible', reservada: 'Reservada', bloqueada: 'Bloqueada', vendida: 'Vendida', cobrada: 'Cobrada', no_disponible: 'No disponible' };
  var ORDEN_STOCK = ['disponible', 'reservada', 'bloqueada', 'vendida', 'cobrada', 'no_disponible'];
  var COLOR = { pagado: '#B06A3B', cobrado: '#104C4F', vencido: '#ba1a1a', d30: '#104C4F', d90: '#4E8386', mas90: '#9AC0C2', sinFecha: '#BEB3A5', resto: '#e4e2dd' };

  function vacio(el, texto) { if (el) el.innerHTML = '<p class="py-6 text-center font-body-md text-body-md text-on-surface-variant">' + esc(texto) + '</p>'; }
  function pct(a, b) { return b ? Math.round(a / b * 1000) / 10 : null; }
  function variacion(a, b) {
    if (!b) return null;
    var v = Math.round((a - b) / b * 1000) / 10;
    return (v >= 0 ? '+' : '') + String(v).replace('.', ',') + ' %';
  }

  function pintaKpis(pm, d, anio) {
    var m = pm.moneda;
    if (d.fallos.facturas) { pon('k-mes', '—'); pon('k-mes-pie', T('No se pudieron leer los recibís')); pon('k-anio', '—'); pon('k-anio-pie', T('No se pudieron leer los recibís')); }
    else {
      var c = pm.cobros || { mes: 0, mesAnterior: 0, anio: 0, anioAnteriorMismoTramo: 0 };
      pon('k-mes', fmt(c.mes, m));
      var v1 = variacion(c.mes, c.mesAnterior);
      pon('k-mes-pie', T('Mes anterior') + ': ' + fmt(c.mesAnterior, m) + (v1 ? ' · ' + v1 : ''));
      pon('k-anio', fmt(c.anio, m));
      var v2 = variacion(c.anio, c.anioAnteriorMismoTramo);
      pon('k-anio-pie', c.anioAnteriorMismoTramo ? (T('Mismo tramo de') + ' ' + (anio - 1) + ': ' + fmt(c.anioAnteriorMismoTramo, m) + (v2 ? ' · ' + v2 : '')) : T('Sin cobros en el mismo tramo de') + ' ' + (anio - 1));
    }
    var sinCartera = d.fallos.contratos || d.fallos.cobrado || d.fallos.vencimientos;
    var car = pm.cartera;
    if (sinCartera) {
      ['k-pendiente', 'k-vencido'].forEach(function (k) { pon(k, '—'); pon(k + '-pie', T('No se pudo calcular la cartera')); });
    } else if (!car) {
      pon('k-pendiente', fmt(0, m)); pon('k-pendiente-pie', T('No hay contratos firmados en') + ' ' + m);
      pon('k-vencido', fmt(0, m)); pon('k-vencido-pie', '');
    } else {
      pon('k-pendiente', fmt(car.pendiente, m));
      var p = pct(car.cobradoFirmado, car.cartera);
      pon('k-pendiente-pie', T('de') + ' ' + fmt(car.cartera, m) + ' ' + T(MODELO_ACTUAL && MODELO_ACTUAL.incluirSinFirmar ? 'contratados' : 'firmados') + (p != null ? ' · ' + String(p).replace('.', ',') + ' % ' + T('cobrado') : ''));
      var dg = car.desglose;
      pon('k-vencido', dg ? fmt(dg.vencido, m) : '—');
      pon('k-vencido-pie', dg ? (dg.nVencido ? num(dg.nVencido) + ' ' + T(dg.nVencido === 1 ? 'hito con la fecha pasada' : 'hitos con la fecha pasada') : T('Ningún hito con la fecha pasada')) : '');
    }
  }

  /* El gráfico de caja: columnas, un solo eje, sin librería. Una serie con dos
     estados (cobrado / previsto), mismo tono: lo previsto va rayado, que es la
     segunda codificación que exige que no dependa solo del color (dataviz). El
     mes en curso apila lo cobrado y lo que falta de él, con 2 px de hueco. */
  var SERIE = null;
  function pintaCaja(pm, d, hoy) {
    var caja = $('lw-fin-caja'), tabla = $('lw-fin-caja-tabla');
    if (!caja) return;
    if (d.fallos.facturas) { falloEn(caja, T('los recibís')); return; }
    var m = pm.moneda;
    SERIE = finSerieCaja(pm, hoy, 12, 6);
    var sinPrev = d.fallos.contratos || d.fallos.cobrado || d.fallos.vencimientos;
    if (tabla) tabla.innerHTML = SERIE.map(function (s) {
      return '<tr class="border-b border-outline-variant/30"><td class="py-1.5 pr-4">' + esc(etiquetaMes(s.mes, true)) + (s.esHoy ? ' · ' + esc(T('en curso')) : '') + '</td>' +
        '<td class="py-1.5 pr-4 text-right fin-num">' + (s.cobrado == null ? '' : esc(fmt(s.cobrado, m))) + '</td>' +
        '<td class="py-1.5 pr-4 text-right fin-num">' + (s.previsto == null || sinPrev ? '' : esc(fmt(s.previsto, m))) + '</td>' +
        '<td class="py-1.5 pr-4 text-right fin-num">' + (s.pagado == null ? '' : esc(fmt(s.pagado, m))) + '</td>' +
        '<td class="py-1.5 pr-4 text-right fin-num">' + (s.aPagar == null ? '' : esc(fmt(s.aPagar, m))) + '</td>' +
        '<td class="py-1.5 pr-4 text-right fin-num font-label-md">' + (s.neto == null ? '' : esc(fmt(s.neto, m))) + '</td></tr>';
    }).join('');
    dibujaCaja(caja, m, sinPrev);
    var ley = document.getElementById('lw-fin-ley-salidas');
    if (ley) ley.hidden = !(pm.gastos);
    var nota = document.getElementById('lw-fin-caja-sinsal');
    if (nota) nota.hidden = !!pm.gastos;
  }
  var MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  function etiquetaMes(ym, conAnio) {
    var p = ym.split('-');
    return T(MESES[Number(p[1]) - 1]) + (conAnio ? ' ' + p[0] : '');
  }
  function corto(n) {
    var a = Math.abs(n);
    if (a >= 1e9) return (Math.round(n / 1e8) / 10).toString().replace('.', ',') + ' mil M';
    if (a >= 1e6) return (Math.round(n / 1e5) / 10).toString().replace('.', ',') + ' M';
    if (a >= 1e3) return Math.round(n / 1e3) + ' k';
    return String(Math.round(n));
  }
  function escalaBonita(max) {
    if (!(max > 0)) return { tope: 1, paso: 1 };
    var bruto = max / 4, mag = Math.pow(10, Math.floor(Math.log10(bruto)));
    var paso = [1, 2, 2.5, 5, 10].map(function (f) { return f * mag; }).filter(function (p) { return p >= bruto; })[0];
    return { tope: paso * Math.ceil(max / paso), paso: paso };
  }
  function dibujaCaja(caja, m, sinPrev) {
    var W = Math.max(300, caja.clientWidth - 8), H = W < 560 ? 220 : 280;
    var izq = 56, der = 8, arr = 16, aba = 28;
    var n = SERIE.length, banda = (W - izq - der) / n, ancho = Math.min(24, banda * 0.62);
    var maxV = 0, maxAbajo = 0;
    SERIE.forEach(function (s) {
      maxV = Math.max(maxV, (s.cobrado || 0) + (sinPrev ? 0 : (s.previsto || 0)));
      maxAbajo = Math.max(maxAbajo, (s.pagado || 0) + (s.aPagar || 0));
    });
    /* Un solo eje (dataviz): las SALIDAS van por debajo del cero con la misma
       escala, así entrada y salida del mismo mes se comparan a ojo sin un
       segundo eje. El paso de la rejilla sale del mayor de los dos lados. */
    var esc_ = escalaBonita(Math.max(maxV, maxAbajo));
    var suelo = maxAbajo > 0 ? esc_.paso * Math.ceil(maxAbajo / esc_.paso) : 0;
    var alto0 = H - arr - aba;
    var y = function (v) { return arr + alto0 * (esc_.tope - v) / (esc_.tope + suelo); };
    var cada = W < 560 ? 3 : (W < 820 ? 2 : 1);
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="' + W + '" height="' + H + '" role="img" aria-label="' + esc(T('Cobrado por mes y previsto por calendario')) + '">' +
      '<defs><pattern id="fin-raya" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="rgba(16,76,79,.16)"/><rect width="2" height="6" fill="#104C4F"/></pattern>' +
      '<pattern id="fin-raya-sal" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(135)"><rect width="6" height="6" fill="rgba(176,106,59,.16)"/><rect width="2" height="6" fill="#B06A3B"/></pattern></defs>';
    for (var t = -suelo; t <= esc_.tope + 1e-9; t += esc_.paso) {
      var yy = Math.round(y(t)) + 0.5;
      svg += '<line x1="' + izq + '" x2="' + (W - der) + '" y1="' + yy + '" y2="' + yy + '" stroke="' + (t === 0 ? '#c5c8bc' : '#e9e8e3') + '" stroke-width="1"/>' +
        '<text x="' + (izq - 8) + '" y="' + (yy + 4) + '" text-anchor="end" font-size="11" fill="#75786e" font-family="Neue Kabel, system-ui">' + esc(corto(Math.abs(t) < 1e-9 ? 0 : t)) + '</text>';
    }
    SERIE.forEach(function (s, i) {
      var cx = izq + banda * i + banda / 2, x = cx - ancho / 2, base = y(0);
      var vc = s.cobrado || 0, vp = sinPrev ? 0 : (s.previsto || 0);
      if (vc > 0) svg += barra(x, y(vc), ancho, base - y(vc), COLOR.cobrado, vp > 0 ? 'abajo' : 'ambos');
      if (vp > 0) {
        var arranque = vc > 0 ? y(vc) - 2 : base;
        var alto = (base - y(vp));
        svg += barra(x, arranque - alto, ancho, alto, 'url(#fin-raya)', vc > 0 ? 'arriba' : 'ambos');
      }
      // salidas: hacia abajo desde el cero; lo pagado pegado al eje y lo que falta pagar debajo, rayado
      var vpag = s.pagado || 0, vapa = s.aPagar || 0;
      if (vpag > 0) svg += barraAbajo(x, base, ancho, y(-vpag) - base, COLOR.pagado, vapa > 0 ? 'arriba' : 'ambos');
      if (vapa > 0) {
        var ini = vpag > 0 ? y(-vpag) + 2 : base;
        svg += barraAbajo(x, ini, ancho, y(-vapa) - base, 'url(#fin-raya-sal)', vpag > 0 ? 'abajo' : 'ambos');
      }
      if (i % cada === 0 || s.esHoy) {
        var etq = etiquetaMes(s.mes, s.mes.slice(5) === '01' || i === 0);
        svg += '<text x="' + cx + '" y="' + (H - 8) + '" text-anchor="middle" font-size="11" fill="' + (s.esHoy ? '#1b1c19' : '#75786e') + '" font-weight="' + (s.esHoy ? '600' : '500') + '" font-family="Neue Kabel, system-ui">' + esc(etq) + '</text>';
      }
      svg += '<rect class="fin-hit" data-i="' + i + '" x="' + (izq + banda * i) + '" y="' + arr + '" width="' + banda + '" height="' + (H - arr - aba) + '" fill="transparent"/>';
    });
    svg += '</svg><div class="fin-tip" hidden></div>';
    caja.innerHTML = svg;
    var tip = caja.querySelector('.fin-tip');
    caja.querySelectorAll('.fin-hit').forEach(function (r) {
      var mostrar = function () {
        var s = SERIE[Number(r.getAttribute('data-i'))];
        var h = '<b>' + esc(etiquetaMes(s.mes, true)) + (s.esHoy ? ' · ' + esc(T('en curso')) : '') + '</b>';
        if (s.cobrado != null) h += '<br>' + esc(T('Entró en la sociedad')) + ': ' + esc(fmt(s.cobrado, m));
        if (s.aTerceros) h += '<br>' + esc(T('Cobrado en cuentas de terceros')) + ': ' + esc(fmt(s.aTerceros, m));
        if (s.previsto != null && !sinPrev) h += '<br>' + esc(T('Previsto')) + ': ' + esc(fmt(s.previsto, m));
        if (s.pagado != null) h += '<br>' + esc(T('Pagado')) + ': ' + esc(fmt(s.pagado, m));
        if (s.aPagar != null && s.aPagar) h += '<br>' + esc(T('A pagar')) + ': ' + esc(fmt(s.aPagar, m));
        if (s.neto != null) h += '<br><b>' + esc(T('Neto')) + ': ' + esc(fmt(s.neto, m)) + '</b>';
        tip.innerHTML = h; tip.hidden = false;
        var bx = Number(r.getAttribute('x')) + Number(r.getAttribute('width')) / 2;
        var escala = caja.querySelector('svg').getBoundingClientRect().width / W;
        tip.style.left = Math.min(Math.max(bx * escala + 16, 80), caja.clientWidth - 60) + 'px';
        tip.style.top = (arr + 24) + 'px';
      };
      r.addEventListener('mouseenter', mostrar);
      r.addEventListener('focus', mostrar);
      r.addEventListener('mouseleave', function () { tip.hidden = true; });
    });
  }
  /* La misma barra hacia ABAJO del eje: base cuadrada en el cero, extremo
     redondeado abajo. `lado` = 'arriba' deja cuadrado el extremo (va apilada). */
  function barraAbajo(x, y0, w, h, fill, lado) {
    if (h <= 0) return '';
    var r = Math.min(4, h / 2, w / 2);
    if (lado === 'arriba') return '<rect x="' + x + '" y="' + y0 + '" width="' + w + '" height="' + h + '" fill="' + fill + '"/>';
    var yb = y0 + h;
    return '<path d="M' + x + ',' + y0 + 'V' + (yb - r) + 'Q' + x + ',' + yb + ' ' + (x + r) + ',' + yb + 'H' + (x + w - r) + 'Q' + (x + w) + ',' + yb + ' ' + (x + w) + ',' + (yb - r) + 'V' + y0 + 'Z" fill="' + fill + '"/>';
  }
  /* Extremo de datos redondeado 4 px, base cuadrada (dataviz). `lado` dice qué
     extremo redondear cuando la columna va apilada. */
  function barra(x, y, w, h, fill, lado) {
    if (h <= 0) return '';
    var r = Math.min(4, h / 2, w / 2);
    var arriba = lado === 'ambos' || lado === 'arriba';
    if (!arriba) return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" fill="' + fill + '"/>';
    return '<path d="M' + x + ',' + (y + h) + 'V' + (y + r) + 'Q' + x + ',' + y + ' ' + (x + r) + ',' + y + 'H' + (x + w - r) + 'Q' + (x + w) + ',' + y + ' ' + (x + w) + ',' + (y + r) + 'V' + (y + h) + 'Z" fill="' + fill + '"/>';
  }

  function filaTramo(color, etiqueta, importe, total, m, extra, rayado) {
    var p = total == null ? null : pct(importe, total);
    return '<div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-0.5 py-2 border-b border-outline-variant/30">' +
      '<span class="flex items-center gap-2.5 min-w-0"><span class="inline-block w-3 h-3 rounded-sm shrink-0' + (rayado ? ' fin-rayado' : '') + '" style="' + (rayado ? '' : 'background:' + color) + '"></span>' +
      '<span class="font-body-md text-body-md text-on-surface">' + esc(etiqueta) + '</span>' + (extra ? '<span class="font-body-sm text-body-sm text-outline shrink-0">' + esc(extra) + '</span>' : '') + '</span>' +
      '<span class="flex items-baseline gap-3 shrink-0 ml-auto"><span class="font-label-md text-label-md text-on-surface fin-num">' + esc(fmt(importe, m)) + '</span>' +
      '<span class="font-body-sm text-body-sm text-outline fin-num w-12 text-right">' + (p != null ? esc(String(p).replace('.', ',') + ' %') : '') + '</span></span></div>';
  }

  function pintaDesglose(pm, d) {
    var el = $('lw-fin-desglose'); if (!el) return;
    if (d.fallos.contratos || d.fallos.cobrado || d.fallos.vencimientos) { falloEn(el, T('la cartera')); return; }
    var car = pm.cartera, m = pm.moneda;
    if (!car || !car.desglose || !car.pendiente) { vacio(el, T('No hay nada firmado pendiente de cobro en') + ' ' + m + '.'); return; }
    var dg = car.desglose, tot = car.pendiente;
    var tramos = [
      ['vencido', T('Vencido'), dg.vencido, dg.nVencido ? num(dg.nVencido) + ' ' + T('hitos') : ''],
      ['d30', T('Próximos 30 días'), dg.d30, ''],
      ['d90', T('De 31 a 90 días'), dg.d31a90, ''],
      ['mas90', T('Más adelante'), dg.mas90, ''],
      ['sinFecha', T('Hitos sin fecha'), dg.sinFecha, dg.nSinFecha ? num(dg.nSinFecha) + ' ' + T('hitos') : ''],
      ['resto', T('Sin calendario que lo explique'), dg.resto, '']
    ];
    var h = '<div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 mb-4"><span class="font-kpi-number text-kpi-number text-on-surface tracking-tight fin-num">' + esc(fmt(tot, m)) + '</span>' +
      '<a class="font-label-md text-label-md text-deep-lagoon hover:underline" href="../vencimientos/">' + esc(T('Ver hito a hito')) + ' →</a></div>';
    h += '<div class="fin-barra mb-4" aria-hidden="true">' + tramos.filter(function (t) { return t[2] > 0; }).map(function (t) {
      return t[0] === 'resto' ? '<span class="fin-rayado" style="flex:' + t[2] + ';opacity:.35"></span>'
                              : '<span style="flex:' + t[2] + ';background:' + COLOR[t[0]] + '"></span>';
    }).join('') + '</div>';
    h += tramos.filter(function (t) { return t[2] > 0 || t[0] === 'vencido'; }).map(function (t) { return filaTramo(COLOR[t[0]], t[1], t[2], tot, m, t[3], t[0] === 'resto'); }).join('');
    if (!dg.cuadra) h += '<p class="mt-4 font-body-sm text-body-sm text-error">' + esc(T('Los hitos prometen') + ' ' + fmt(dg.exceso, m) + ' ' + T('más de lo que queda por cobrar: algún calendario no descuenta lo ya pagado. La previsión está inflada en esa cifra; revisa los calendarios en Vencimientos.')) + '</p>';
    if (dg.nSinImporte) h += '<p class="mt-3 font-body-sm text-body-sm text-outline">' + esc(num(dg.nSinImporte) + ' ' + T('hitos no tienen importe ni porcentaje y no se pueden sumar.')) + '</p>';
    el.innerHTML = h;
  }

  function pintaFacturado(pm, d) {
    var el = $('lw-fin-facturado'); if (!el) return;
    if (d.fallos.facturas || d.fallos.pendiente) { falloEn(el, T('lo pendiente de las facturas')); return; }
    var f = pm.facturado, m = pm.moneda;
    if (!f || !f.total) { vacio(el, T('Ninguna factura en') + ' ' + m + ' ' + T('queda por cobrar.')); return; }
    var max = Math.max.apply(null, f.tramos.map(function (t) { return t.importe; })) || 1;
    var h = '<div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 mb-4"><span class="font-kpi-number text-kpi-number text-on-surface tracking-tight fin-num">' + esc(fmt(f.total, m)) + '</span>' +
      '<a class="font-label-md text-label-md text-deep-lagoon hover:underline" href="../facturas/">' + esc(num(f.n) + ' ' + T(f.n === 1 ? 'factura' : 'facturas')) + ' →</a></div>';
    h += '<div class="flex flex-col gap-3">' + f.tramos.map(function (t) {
      var ancho = t.importe ? Math.max(2, t.importe / max * 100) : 0;
      var color = t.clave === 'al_dia' ? '#104C4F' : (t.clave === 'd30' ? '#8A6A34' : '#ba1a1a');
      return '<div class="grid items-center gap-3" style="grid-template-columns:96px 1fr auto">' +
        '<span class="font-body-sm text-body-sm text-on-surface-variant">' + esc(T(t.etiqueta)) + '</span>' +
        '<span class="h-2.5 rounded-full bg-surface-container overflow-hidden"><span class="block h-full rounded-r" style="width:' + ancho + '%;background:' + color + '"></span></span>' +
        '<span class="font-label-md text-label-md text-on-surface fin-num text-right" style="min-width:110px">' + esc(fmt(t.importe, m)) + (t.n ? ' <span class="font-body-sm text-body-sm text-outline">· ' + t.n + '</span>' : '') + '</span></div>';
    }).join('') + '</div>';
    var pie = document.querySelector('[data-fin="facturado-pie"]');
    if (f.deSinFirmar) h += '<p class="mt-4 font-body-sm text-body-sm text-on-surface-variant">' + esc(T('De ello,') + ' ' + fmt(f.deSinFirmar, m) + ' (' + f.nSinFirmar + ' ' + T(f.nSinFirmar === 1 ? 'factura' : 'facturas') + ') ' + T('son de contratos todavía sin firmar, que no cuentan en «Firmado por cobrar».')) + '</p>';
    el.innerHTML = h;
    if (pie) pie.textContent = T('Se solapa con «Firmado por cobrar» (una factura reclama un hito): no se suman.') + ' ' +
      T('Antigüedad desde el vencimiento de la factura') + ' (' + f.porVencimiento + ')' + (f.porEmision ? ', ' + T('o desde su emisión si no lo tiene') + ' (' + f.porEmision + ')' : '') + '.';
  }

  function pintaTrimestres(pm, d) {
    var el = $('lw-fin-trimestres'); if (!el) return;
    if (d.fallos.contratos || d.fallos.cobrado || d.fallos.vencimientos) { falloEn(el, T('el calendario')); return; }
    var car = pm.cartera, m = pm.moneda;
    if (!car || !car.trimestres || !car.trimestres.length) { vacio(el, T('Sin calendario firmado en') + ' ' + m + '.'); return; }
    var max = Math.max.apply(null, car.trimestres.map(function (t) { return t.importe; })) || 1;
    el.innerHTML = '<div class="flex flex-col gap-4">' + car.trimestres.map(function (t, i) {
      return '<div class="grid items-center gap-3" style="grid-template-columns:88px 1fr auto">' +
        '<span class="font-label-md text-label-md text-on-surface">' + esc(t.trimestre) + (i === 0 ? '<span class="block font-body-sm text-body-sm text-outline">' + esc(T('lo que queda')) + '</span>' : '') + '</span>' +
        '<span class="h-2.5 rounded-full bg-surface-container overflow-hidden"><span class="block h-full rounded-r" style="width:' + (t.importe ? Math.max(2, t.importe / max * 100) : 0) + '%;background:#104C4F"></span></span>' +
        '<span class="font-label-md text-label-md text-on-surface fin-num text-right" style="min-width:120px">' + esc(fmt(t.importe, m)) + ' <span class="font-body-sm text-body-sm text-outline">· ' + t.n + ' ' + esc(T('hitos')) + '</span></span></div>';
    }).join('') + '</div><p class="mt-5 font-body-sm text-body-sm text-outline">' + esc(T('Incluye lo vencido del trimestre en curso. Lo vencido de trimestres anteriores está en «Vencido».')) + '</p>';
  }

  function pintaStock(pm, d) {
    var el = $('lw-fin-stock'); if (!el) return;
    if (d.fallos.unidades) { falloEn(el, T('las unidades')); return; }
    var s = pm.stock, m = pm.moneda;
    if (MODELO_ACTUAL && MODELO_ACTUAL.noSeReparte) { vacio(el, T('El stock no se reparte por sociedad: una unidad no tiene sociedad hasta que se vende. Quita el filtro para verlo.')); return; }
    if (!s) { vacio(el, T('Ninguna unidad con precio en') + ' ' + m + '.'); return; }
    var estados = ORDEN_STOCK.filter(function (k) { return s.estados[k]; }).concat(Object.keys(s.estados).filter(function (k) { return ORDEN_STOCK.indexOf(k) === -1; }));
    var h = '<table class="w-full text-left border-collapse"><thead><tr class="border-b border-outline-variant/60">' +
      '<th class="py-2 font-label-md text-[11px] uppercase tracking-wider text-outline">' + esc(T('Estado')) + '</th>' +
      '<th class="py-2 font-label-md text-[11px] uppercase tracking-wider text-outline text-right">' + esc(T('Unidades')) + '</th>' +
      '<th class="py-2 font-label-md text-[11px] uppercase tracking-wider text-outline text-right">' + esc(T('Valor de lista')) + '</th></tr></thead><tbody>';
    h += estados.map(function (k) {
      var e = s.estados[k];
      return '<tr class="border-b border-outline-variant/30"><td class="py-2.5 font-body-md text-body-md text-on-surface">' + esc(T(ESTADO_STOCK[k] || k)) + '</td>' +
        '<td class="py-2.5 text-right fin-num font-body-md text-body-md">' + num(e.n) + '</td>' +
        '<td class="py-2.5 text-right fin-num font-label-md text-label-md text-on-surface">' + esc(fmt(e.valor, m)) + '</td></tr>';
    }).join('') + '</tbody></table>';
    if (s.sinPrecio) h += '<p class="mt-3 font-body-sm text-body-sm text-outline">' + esc(num(s.sinPrecio) + ' ' + T('unidades sin precio no suman valor.')) + '</p>';
    el.innerHTML = h;
  }

  function pintaProyectos(pm, d) {
    var tb = $('lw-fin-proyectos'); if (!tb) return;
    var sinCartera = d.fallos.contratos || d.fallos.cobrado || d.fallos.vencimientos;
    if (sinCartera && d.fallos.unidades) { tb.innerHTML = '<tr><td colspan="10" class="px-5 py-8 text-center text-error">' + esc(T('No se pudo cargar la cartera ni las unidades.')) + '</td></tr>'; return; }
    var m = pm.moneda, filas = pm.porProyecto || [];
    if (!filas.length) { tb.innerHTML = '<tr><td colspan="10" class="px-5 py-8 text-center text-on-surface-variant">' + esc(T('Ningún proyecto con contratos firmados ni stock en') + ' ' + m + '.') + '</td></tr>'; return; }
    var guion = function (v, falla) { return falla ? '—' : esc(fmt(v, m)); };
    var stockFuera = d.fallos.unidades || pm.stock == null;
    var tot = { cartera: 0, cobrado: 0, pendiente: 0, vencido: 0, proximos90: 0, stockValor: 0, stockN: 0, gastosBase: 0, cajaNeta: 0 };
    var conGas = filas.some(function (p) { return p.gastosBase != null; });
    var h = filas.map(function (p, i) {
      Object.keys(tot).forEach(function (k) { tot[k] += p[k] || 0; });
      var barra = p.pctCobrado == null ? '<span class="text-outline">—</span>' :
        '<span class="flex items-center gap-2"><span class="w-20 h-1.5 rounded-full bg-surface-container overflow-hidden"><span class="block h-full" style="width:' + Math.min(100, p.pctCobrado) + '%;background:#104C4F"></span></span><span class="fin-num">' + esc(String(p.pctCobrado).replace('.', ',')) + ' %</span></span>';
      /* La fila se despliega con «quién debe». El estado abierto se guarda por
         NOMBRE de proyecto (no por posición): al cambiar de moneda o de
         sociedad la tabla se reordena y la posición ya no es el mismo proyecto. */
      var abierto = !!ABIERTOS[p.proyecto], hay = !sinCartera && p.personas && p.personas.length;
      var nombre = hay
        ? '<button type="button" class="fin-abre" data-real data-fin-p="' + esc(p.proyecto) + '" aria-expanded="' + abierto + '" aria-controls="lw-fin-p' + i + '"><span class="material-symbols-outlined" aria-hidden="true">chevron_right</span>' + esc(p.proyecto) + '</button>'
        : '<span style="padding-left:24px">' + esc(p.proyecto) + '</span>';
      return '<tr class="border-b border-outline-variant/30 hover:bg-surface-container-low">' +
        '<td class="px-5 py-3 font-label-md text-label-md text-on-surface">' + nombre + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + guion(p.cartera, sinCartera) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + guion(p.cobrado, sinCartera) + '</td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + (sinCartera ? '—' : barra) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + guion(p.pendiente, sinCartera) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num' + (p.vencido > 0 ? ' text-error' : '') + '">' + guion(p.vencido, sinCartera) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + guion(p.proximos90, sinCartera) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + (p.gastosBase == null ? '—' : esc(fmt(p.gastosBase, m))) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md' + (p.cajaNeta != null && p.cajaNeta < 0 ? ' text-error' : '') + '">' + (p.cajaNeta == null ? '—' : esc(fmt(p.cajaNeta, m))) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + (stockFuera ? '—' : esc(fmt(p.stockValor, m)) + ' <span class="text-outline font-body-sm text-body-sm">· ' + num(p.stockN) + '</span>') + '</td></tr>' +
        (hay ? '<tr id="lw-fin-p' + i + '"' + (abierto ? '' : ' hidden') + '><td colspan="10" class="px-5 pb-4 pt-1 bg-surface-container-low/60">' + tablaPersonas(p.personas, m) + '</td></tr>' : '');
    }).join('');
    h += '<tr class="bg-surface-container-low"><td class="px-5 py-3 font-label-md text-label-md text-on-surface">' + esc(T('Total')) + '</td>' +
      ['cartera', 'cobrado'].map(function (k) { return '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + guion(tot[k], sinCartera) + '</td>'; }).join('') +
      '<td class="px-5 py-3 font-body-sm text-body-sm fin-num">' + (sinCartera || !tot.cartera ? '—' : esc(String(pct(tot.cobrado, tot.cartera)).replace('.', ',')) + ' %') + '</td>' +
      ['pendiente', 'vencido', 'proximos90'].map(function (k) { return '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + guion(tot[k], sinCartera) + '</td>'; }).join('') +
      ['gastosBase', 'cajaNeta'].map(function (k) { return '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + (conGas ? esc(fmt(tot[k], m)) : '—') + '</td>'; }).join('') +
      '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + (stockFuera ? '—' : esc(fmt(tot.stockValor, m)) + ' <span class="text-outline font-body-sm text-body-sm">· ' + num(tot.stockN) + '</span>') + '</td></tr>';
    tb.innerHTML = h;
  }

  /* «Quién debe» dentro de un proyecto: las diez primeras personas (lo
     vencido primero, que es a quien hay que llamar) y cuántas más hay. La
     lista entera va en el CSV. */
  var ABIERTOS = {};
  function tablaPersonas(personas, m) {
    var top = personas.slice(0, 10);
    var th = function (t, der) { return '<th class="py-2 pr-4 font-label-md text-[11px] uppercase tracking-wider text-outline' + (der ? ' text-right' : '') + '">' + esc(T(t)) + '</th>'; };
    var h = '<table class="w-full text-left border-collapse"><thead><tr>' +
      th('Comprador') + th('Contratos') + th('Cobrado', true) + th('Por cobrar', true) + th('Vencido', true) + '</tr></thead><tbody>';
    h += top.map(function (x) {
      var cs = [];
      if (x.firmados) cs.push(x.firmados + ' ' + T(x.firmados === 1 ? 'firmado' : 'firmados'));
      if (x.sinFirmar) cs.push(x.sinFirmar + ' ' + T('sin firmar'));
      return '<tr class="border-t border-outline-variant/30"><td class="py-2 pr-4 font-body-md text-body-md text-on-surface">' + esc(x.nombre) + '</td>' +
        '<td class="py-2 pr-4 font-body-sm text-body-sm text-on-surface-variant">' + esc(cs.join(' · ')) + '</td>' +
        '<td class="py-2 pr-4 text-right fin-num">' + esc(fmt(x.cobrado, m)) + '</td>' +
        '<td class="py-2 pr-4 text-right fin-num font-label-md text-label-md">' + esc(fmt(x.pendiente, m)) + '</td>' +
        '<td class="py-2 pr-4 text-right fin-num' + (x.vencido > 0 ? ' text-error' : ' text-outline') + '">' + esc(fmt(x.vencido, m)) + '</td></tr>';
    }).join('') + '</tbody></table>';
    if (personas.length > top.length) h += '<p class="mt-2 font-body-sm text-body-sm text-outline">' + esc(T('y') + ' ' + (personas.length - top.length) + ' ' + T('más: la lista completa sale en el CSV.')) + '</p>';
    return h;
  }

  /* Por closer: firmado y cobrado de las operaciones que cerró cada uno. */
  function pintaCloser(pm, d) {
    var tb = $('lw-fin-closer'); if (!tb) return;
    var m = pm.moneda;
    if (!d.verCloser) { tb.innerHTML = '<tr><td colspan="5" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">' + esc(T('Sin permiso: ver quién cierra cada venta exige la casilla «Ranking» en Usuarios.')) + '</td></tr>'; return; }
    if (d.fallos.closer) { tb.innerHTML = '<tr><td colspan="5" class="px-5 py-8 text-center text-error">' + esc(T('No se pudo leer quién cerró cada venta.')) + '</td></tr>'; return; }
    var filas = pm.porCloser || [];
    if (!filas.length) { tb.innerHTML = '<tr><td colspan="5" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">' + esc(T('Ninguna venta firmada en') + ' ' + m + '.') + '</td></tr>'; return; }
    var nombre = {}; (d.equipo || []).forEach(function (u) { if (u.email) nombre[u.email.toLowerCase()] = u.nombre || u.email; });
    var tot = { firmado: 0, cobradoAnio: 0, operaciones: 0 };
    tb.innerHTML = filas.map(function (f) {
      tot.firmado += f.firmado; tot.cobradoAnio += f.cobradoAnio; tot.operaciones += f.operaciones;
      var quien = f.closer ? (nombre[f.closer.toLowerCase()] || f.closer) : T('Sin atribuir');
      var barra = f.pctCobrado == null ? '<span class="text-outline">—</span>' :
        '<span class="flex items-center gap-2"><span class="w-20 h-1.5 rounded-full bg-surface-container overflow-hidden"><span class="block h-full" style="width:' + Math.min(100, f.pctCobrado) + '%;background:#104C4F"></span></span><span class="fin-num">' + esc(String(f.pctCobrado).replace('.', ',')) + ' %</span></span>';
      return '<tr class="border-b border-outline-variant/30' + (f.closer ? '' : ' text-on-surface-variant') + '">' +
        '<td class="px-5 py-3 font-label-md text-label-md">' + esc(quien) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + num(f.operaciones) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + esc(fmt(f.firmado, m)) + '</td>' +
        '<td class="px-5 py-3 text-right fin-num">' + esc(fmt(f.cobradoAnio, m)) + '</td>' +
        '<td class="px-5 py-3 font-body-sm text-body-sm">' + barra + '</td></tr>';
    }).join('') +
      '<tr class="bg-surface-container-low"><td class="px-5 py-3 font-label-md text-label-md">' + esc(T('Total')) + '</td>' +
      '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + num(tot.operaciones) + '</td>' +
      '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + esc(fmt(tot.firmado, m)) + '</td>' +
      '<td class="px-5 py-3 text-right fin-num font-label-md text-label-md">' + esc(fmt(tot.cobradoAnio, m)) + '</td><td></td></tr>';
  }

  /* Bancos (24-sep-2026): el saldo que da el propio banco en el último
     extracto importado, por cuenta y moneda. `bancos_resumen` devuelve null sin
     la casilla «Bancos» (nunca un 0 que parezca una cuenta vacía). Todas las
     monedas a la vez: un saldo bancario no se convierte ni se suma entre monedas. */
  function pintaBancos(d) {
    var el = $('lw-fin-bancos'); if (!el) return;
    if (d.fallos.bancos) { falloEn(el, T('los bancos')); return; }
    if (d.bancos == null) { vacio(el, T('Falta la casilla «Bancos»: los saldos bancarios no se ven.')); return; }
    if (!d.bancos.length) { vacio(el, T('Todavía no hay ningún extracto importado.')); return; }
    var hoyD = new Date(), fF = function (x) { if (!x) return '—'; var t = new Date(String(x).slice(0, 10) + 'T12:00:00'); return isNaN(t) ? String(x) : t.toLocaleDateString(typeof lwLocale === 'function' ? lwLocale() : 'es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); };
    var th = function (t, der) { return '<th class="py-2 pr-4 font-label-md text-[11px] uppercase tracking-wider text-outline' + (der ? ' text-right' : '') + '">' + esc(T(t)) + '</th>'; };
    el.innerHTML = '<table class="w-full text-left border-collapse" style="min-width:640px"><thead><tr class="border-b border-outline-variant/60">' +
      th('Cuenta') + th('Saldo', 1) + th('Extracto hasta') + th('Entra en el año', 1) + th('Sale en el año', 1) + th('Por conciliar', 1) + '</tr></thead><tbody>' +
      d.bancos.map(function (c) {
        var viejo = c.ultimo && (hoyD - new Date(c.ultimo + 'T12:00:00')) / 86400000 > 7;
        return '<tr class="border-b border-outline-variant/30">' +
          '<td class="py-3 pr-4 font-label-md text-label-md text-on-surface">' + esc((c.label || c.cuenta) + ' · ' + c.moneda) + '</td>' +
          '<td class="py-3 pr-4 text-right fin-num font-label-md text-label-md">' + (c.saldo != null ? esc(fmt(c.saldo, c.moneda)) : '<span class="text-outline">' + esc(T('sin saldo')) + '</span>') + '</td>' +
          '<td class="py-3 pr-4 fin-num font-body-sm text-body-sm ' + (viejo ? 'text-error font-semibold' : 'text-on-surface-variant') + '">' + esc(fF(c.ultimo)) + '</td>' +
          '<td class="py-3 pr-4 text-right fin-num font-body-sm text-body-sm">' + esc(fmt(Math.abs(Number(c.entradas) || 0), c.moneda)) + '</td>' +
          '<td class="py-3 pr-4 text-right fin-num font-body-sm text-body-sm">' + esc(fmt(Math.abs(Number(c.salidas) || 0), c.moneda)) + '</td>' +
          '<td class="py-3 text-right fin-num font-body-sm text-body-sm ' + (c.pendientes ? 'text-burnt-earth font-semibold' : 'text-on-surface-variant') + '">' + esc(String(c.pendientes || 0)) + '</td></tr>';
      }).join('') + '</tbody></table>' +
      '<p class="mt-4 font-body-sm text-body-sm text-outline">' + esc(T('Entradas y salidas sin contar los traspasos entre cuentas propias. En rojo, extractos de hace más de 7 días.')) + '</p>';
  }

  function pintaSociedades(pm, d) {
    var el = $('lw-fin-sociedades'); if (!el) return;
    if (d.fallos.facturas) { falloEn(el, T('los recibís')); return; }
    var c = pm.cobros, m = pm.moneda;
    var socs = c ? Object.keys(c.porSociedadAnio).sort(function (a, b) { return c.porSociedadAnio[b] - c.porSociedadAnio[a]; }) : [];
    if (!socs.length) { vacio(el, T('Ningún cobro este año en') + ' ' + m + '.'); return; }
    el.innerHTML = socs.map(function (s) { return filaTramo('#104C4F', nombreSociedad(s), c.porSociedadAnio[s], c.anio, m, '', false); }).join('') +
      '<p class="mt-4 font-body-sm text-body-sm text-outline">' + esc(T('Cada sociedad es una empresa distinta: la suma solo sirve de referencia, no es la caja de ninguna.')) + '</p>';
  }

  function pintaSalidas(pm, d) {
    var el = $('lw-fin-salidas'); if (!el) return;
    var m = pm.moneda, filas = [], total = 0, faltan = [];
    if (MODELO_ACTUAL && MODELO_ACTUAL.noSeReparte) faltan.push(T('Las comisiones no se reparten por sociedad.'));
    else if (d.fallos.solicitudes || d.fallos.comisiones) faltan.push(T('No se pudieron leer las solicitudes y comisiones.'));
    else {
      var s = pm.salidas;
      if (d.verSol && s) { filas.push(['#104C4F', T('Solicitudes de pago vivas'), s.solicitudes.importe, num(s.solicitudes.n)]); total += s.solicitudes.importe; }
      if (d.verCom && s) { filas.push(['#9AC0C2', T('Comisiones sin solicitud todavía'), s.comisiones.importe, num(s.comisiones.n)]); total += s.comisiones.importe; }
      if (!d.verSol) faltan.push(T('Falta la casilla «Pagos de %marca»: las solicitudes de pago no están sumadas.'));
      if (!d.verCom) faltan.push(T('Falta la casilla «Reparto a closers»: las comisiones sin solicitud no están sumadas.'));
    }
    if (d.fallos.gastos) faltan.push(T('No se pudieron leer los gastos.'));
    else if (!d.verGas) faltan.push(T('Falta la casilla «Gastos y proveedores»: las facturas de proveedores no están sumadas.'));
    else if (pm.gastos) {
      var g = pm.gastos;
      filas.push(['#B06A3B', T('Facturas de proveedores por pagar'), g.pendientePagar, num(g.nPendientes)]); total += g.pendientePagar;
      if (g.pphPorIngresar) { filas.push(['#D8A984', T('Retenciones PPh por ingresar'), g.pphPorIngresar, '']); total += g.pphPorIngresar; }
    }
    total = Math.round(total * 100) / 100;
    var notas = faltan.map(function (t) { return '<p class="mt-3 font-body-sm text-body-sm text-on-surface-variant">' + esc(t) + '</p>'; }).join('');
    if (!filas.length) { el.innerHTML = '<p class="py-4 font-body-md text-body-md text-on-surface-variant">' + esc(T('Sin permiso para ver lo que se debe pagar: no es que no se deba nada, es que esta sesión no lo puede ver.')) + '</p>' + notas; return; }
    el.innerHTML = '<div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 mb-4"><span class="font-kpi-number text-kpi-number text-on-surface tracking-tight fin-num">' + esc(fmt(total, m)) + '</span>' +
      (d.verGas ? '<a class="font-label-md text-label-md text-deep-lagoon hover:underline" href="../gastos/">' + esc(T('Ver en Gastos')) + ' →</a>' : '<a class="font-label-md text-label-md text-deep-lagoon hover:underline" href="../comisiones/">' + esc(T('Ver en Comisiones')) + ' →</a>') + '</div>' +
      filas.map(function (f) { return filaTramo(f[0], f[1], f[2], total, m, f[3], false); }).join('') + notas;
  }

  /* Caja del año: lo que ha entrado menos lo que ha salido, desglosado, y los
     gastos del año por tipo con el suelo APARTE (es inversión, #64). */
  function pintaCajaAnio(pm, d, anio) {
    var el = $('lw-fin-anio'), el2 = $('lw-fin-tipos'); if (!el || !el2) return;
    var m = pm.moneda;
    if (d.fallos.gastos) { falloEn(el, T('los gastos')); falloEn(el2, T('los gastos')); return; }
    if (!pm.gastos) {
      var msg = T('Falta la casilla «Gastos y proveedores» en Usuarios: sin ella no se ve lo que sale.');
      vacio(el, msg); vacio(el2, msg); return;
    }
    var g = pm.gastos, cp = pm.comPagadas, cob = pm.cobros || {};
    var dest = cob.porDestinoAnio || { propia: 0, tercero: 0, escrow: 0, sin_clasificar: cob.anio || 0 };
    var entr = cob.anioCaja != null ? cob.anioCaja : (cob.anio || 0);
    var com = cp ? cp.anio : null;
    var sal = g.pagadoAnio + (com || 0);
    var neto = Math.round((entr - sal) * 100) / 100;
    el.innerHTML = '<div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 mb-4"><span class="font-kpi-number text-kpi-number tracking-tight fin-num ' + (neto < 0 ? 'text-error' : 'text-on-surface') + '">' + esc(fmt(neto, m)) + '</span>' +
      '<span class="font-body-sm text-body-sm text-outline">' + esc(T('neto de caja en') + ' ' + anio) + '</span></div>' +
      filaTramo('#104C4F', T('Entradas en cuentas de la sociedad'), dest.propia, null, m, '', false) +
      (dest.sin_clasificar ? filaTramo('#9AC0C2', T('Entradas sin clasificar (cuenta sin marcar o recibí sin cuenta)'), dest.sin_clasificar, null, m, '', false) : '') +
      filaTramo('#B06A3B', T('Pagado a proveedores y retenciones'), g.pagadoAnio, null, m, '', false) +
      (com == null ? '<p class="mt-2 font-body-sm text-body-sm text-on-surface-variant">' + esc(T('Comisiones pagadas: falta la casilla «Reparto a closers»; no están restadas.')) + '</p>'
                   : filaTramo('#D8A984', T('Comisiones pagadas a closers'), com, null, m, '', false)) +
      ((dest.tercero || dest.escrow) ? '<div class="mt-4 pt-3 border-t border-outline-variant/40"><p class="font-body-sm text-body-sm text-on-surface-variant mb-1">' + esc(T('No es caja de la sociedad (no entra en el neto):')) + '</p>' +
        (dest.tercero ? filaTramo('#BEB3A5', T('Cobrado en cuentas de terceros (contratista, vendedor de suelo)'), dest.tercero, null, m, '', false) : '') +
        (dest.escrow ? filaTramo('#BEB3A5', T('Cobrado en cuentas de escrow (notario)'), dest.escrow, null, m, '', false) : '') + '</div>' : '') +
      (dest.sin_clasificar ? '<p class="mt-3 font-body-sm text-body-sm text-error">' + esc(T('Hay entradas sin clasificar: el neto las cuenta como de la sociedad. Marca en Cuentas de quién es cada cuenta para que la cifra sea exacta.')) + ' <a class="underline" href="../cuentas/">' + esc(T('Ir a Cuentas')) + '</a></p>' : '') +
      '<p class="mt-4 font-body-sm text-body-sm text-outline">' + esc(T('Es caja, no resultado: no descuenta amortizaciones ni lo que aún no se ha registrado en Gastos.')) + '</p>';
    var grupos = g.baseAnioPorGrupo || {}, NOM = { construccion: 'Construcción', comercial: 'Comercial', marketing: 'Marketing', personal: 'Personal', general: 'General', impuestos: 'Impuestos y tasas', financiero: 'Financiero' };
    var expl = Object.keys(grupos).filter(function (k) { return k !== 'suelo'; }).sort(function (a, b) { return grupos[b] - grupos[a]; });
    var totExpl = expl.reduce(function (a, k) { return a + grupos[k]; }, 0);
    el2.innerHTML = (expl.length ? expl.map(function (k) { return filaTramo('#B06A3B', T(NOM[k] || k), grupos[k], totExpl, m, '', false); }).join('')
                                 : '<p class="py-2 font-body-md text-body-md text-on-surface-variant">' + esc(T('Ningún gasto de explotación registrado este año.')) + '</p>') +
      (grupos.suelo ? '<div class="mt-4 pt-3 border-t border-outline-variant/40">' + filaTramo('#8F9B7A', T('Inversión en suelo (no es gasto de explotación)'), grupos.suelo, null, m, '', false) + '</div>' : '') +
      '<p class="mt-4 font-body-sm text-body-sm text-outline">' + esc(T('Por la base, sin el impuesto soportado: el PPN se compensa y no es coste.')) + '</p>';
  }

  function pintaFuera(pm, d) {
    var sec = $('lw-fin-fuera'), ul = $('lw-fin-fuera-lista'); if (!sec || !ul) return;
    var li = [], car = pm.cartera, m = pm.moneda;
    if (car && car.fuera) {
      if (car.fuera.sinFirmar) li.push(num(car.fuera.sinFirmar) + ' ' + T('contratos sin firmar: todavía no son un compromiso y no suman a lo firmado (lo que ya cobraron sí cuenta).'));
      if (car.fuera.preliminares) li.push(num(car.fuera.preliminares) + ' ' + T('Cartas de Reserva: su precio lo repite el contrato que las sustituye; su cobro sí cuenta.'));
    }
    if (car && car.liberadas && car.liberadas.n) li.push(num(car.liberadas.n) + ' ' + T('contratos firmados y liberados (venta caída), por') + ' ' + fmt(car.liberadas.precio, m) + ': ' + T('no se le deben a nadie.'));
    if (car && car.avisos && car.avisos.length) {
      var sinCal = car.avisos.filter(function (a) { return a.tipo === 'sin_calendario'; }).length;
      var no100 = car.avisos.filter(function (a) { return a.tipo === 'pct_no_100'; }).length;
      if (sinCal) li.push(num(sinCal) + ' ' + T('contratos firmados sin calendario de pagos: su pendiente sale en «Sin calendario que lo explique».'));
      if (no100) li.push(num(no100) + ' ' + T('calendarios cuyos porcentajes no suman 100 %.'));
    }
    li.push(d.verGas ? T('Gastos: solo los que se apuntan en Gastos (el módulo existe desde el 24-sep-2026). Los saldos bancarios todavía no se registran.')
                     : T('Gastos: esta sesión no tiene la casilla «Gastos y proveedores». Los saldos bancarios todavía no se registran.'));
    ul.innerHTML = li.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('');
    sec.hidden = false;
  }

  /* CSV de lo que se está viendo (moneda elegida): la tabla por proyecto y el
     resumen. Separador «;» y BOM: es lo que abre bien Excel en español. */
  var EMPRESA_CSV = 'todas', SIN_FIRMAR_CSV = false, MODELO_ACTUAL = null;
  function exportaCSV(pm, hoy) {
    var m = pm.moneda, car = pm.cartera || {}, dg = car.desglose || {};
    var q = function (v) { v = v == null ? '' : String(v); return /[;"\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    var filas = [['Resumen', m, hoy, EMPRESA_CSV, SIN_FIRMAR_CSV ? 'incluye sin firmar' : 'solo firmados'], ['Cobrado este mes', pm.cobros ? pm.cobros.mes : ''], ['Cobrado en el año', pm.cobros ? pm.cobros.anio : ''],
      ['Firmado', car.cartera], ['Cobrado de lo firmado', car.cobrado], ['Firmado por cobrar', car.pendiente], ['Vencido', dg.vencido],
      ['Próximos 30 días', dg.d30], ['De 31 a 90 días', dg.d31a90], ['Más adelante', dg.mas90], ['Hitos sin fecha', dg.sinFecha], ['Sin calendario', dg.resto],
      ['Facturado sin cobrar', pm.facturado ? pm.facturado.total : ''],
      ['Gastos pendientes de pagar', pm.gastos ? pm.gastos.pendientePagar : 'sin permiso'], ['Retenciones PPh por ingresar', pm.gastos ? pm.gastos.pphPorIngresar : 'sin permiso'],
      ['Pagado a proveedores en el año', pm.gastos ? pm.gastos.pagadoAnio : 'sin permiso'], ['Comisiones pagadas en el año', pm.comPagadas ? pm.comPagadas.anio : 'sin permiso'], [],
      ['Proyecto', 'Firmado', 'Cobrado', '% cobrado', 'Por cobrar', 'Vencido', 'Próximos 90 días', 'Gastos (base)', 'Caja neta', 'Stock disponible (valor)', 'Stock disponible (unidades)']]
      .concat((pm.porProyecto || []).map(function (p) { return [p.proyecto, p.cartera, p.cobrado, p.pctCobrado, p.pendiente, p.vencido, p.proximos90, p.gastosBase, p.cajaNeta, p.stockValor, p.stockN]; }))
      .concat([[], ['Quién debe'], ['Proyecto', 'Comprador', 'Firmados', 'Sin firmar', 'Cobrado', 'Por cobrar', 'Vencido']])
      .concat([].concat.apply([], (pm.porProyecto || []).map(function (p) {
        return (p.personas || []).map(function (x) { return [p.proyecto, x.nombre, x.firmados, x.sinFirmar, x.cobrado, x.pendiente, x.vencido]; });
      })));
    var txt = '﻿' + filas.map(function (f) { return f.map(q).join(';'); }).join('\r\n');
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([txt], { type: 'text/csv;charset=utf-8' }));
    a.download = 'finanzas_' + m + '_' + hoy + '.csv';
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  }

  /* ── ARRANQUE ──────────────────────────────────────────────────────────── */
  function monta(aut) {
    var sb = aut.sb, hoy = hoyLocal(), anio = Number(hoy.slice(0, 4));
    if (typeof finModelo !== 'function' || typeof modeloFinanciero !== 'function') {
      aviso(T('No cargó el cálculo de finanzas (finanzas.js / logica.js). Recarga la página; si sigue, avisa a Desarrollo.'), 'mal');
      return;
    }
    cargar(sb, aut.ficha).then(function (d) {
      var nombres = { contratos: 'contratos', cobrado: 'cobrado por contrato', vencimientos: 'calendario de pagos', facturas: 'facturas y recibís', pendiente: 'pendiente por factura', unidades: 'unidades', solicitudes: 'solicitudes de pago', comisiones: 'comisiones', gastos: 'gastos' };
      var fallidas = Object.keys(d.fallos).filter(function (k) { return nombres[k]; }).map(function (k) { return T(nombres[k]); });
      if (fallidas.length) aviso(T('No se pudieron leer') + ': ' + fallidas.join(', ') + '. ' + T('Los bloques que dependen de eso lo dicen; el resto es correcto.'), 'mal');
      /* Preferencias de VISTA (no datos): moneda, sociedad y «sin firmar».
         En localStorage con try/catch mudo: sin él, valores por defecto. */
      var lee = function (k, def) { try { var v = localStorage.getItem(k); return v == null ? def : v; } catch (_) { /* MUDO: preferencia de vista */ return def; } };
      var guarda = function (k, v) { try { localStorage.setItem(k, v); } catch (_) { /* MUDO: preferencia de vista, no dato */ } };
      var RAW = normaliza(d, hoy);
      var EMPRESA = lee('lw_fin_empresa', 'todas');
      var SIN_FIRMAR = lee('lw_fin_sin_firmar', '0') === '1';
      var SOC_LISTA = false;           // ¿llegó ya la sociedad de cada contrato?
      var MODELO = null, MON = null;

      /* EL camino de recálculo, uno solo: cualquier control pasa por aquí
         («cerrar una salida no cierra a sus hermanas», 9-sep-2026). Sin la
         sociedad de los contratos cargada no se filtra: se ve «Todas». */
      function recalcula() {
        var empresa = SOC_LISTA ? EMPRESA : 'todas';
        var entrada = finFiltraEmpresa(RAW, empresa);
        entrada.incluirSinFirmar = SIN_FIRMAR;
        MODELO = finModelo(entrada);
        MODELO_ACTUAL = MODELO; EMPRESA_CSV = empresa; SIN_FIRMAR_CSV = SIN_FIRMAR;
        window.LW_V4 = window.LW_V4 || {}; window.LW_V4.finanzas = MODELO;   // para depurar desde consola
        if (!MON || (MODELO.monedas.length && MODELO.monedas.indexOf(MON) === -1)) {
          var elegida = lee('lw_fin_moneda', null);
          MON = MODELO.monedas.indexOf(elegida) !== -1 ? elegida : (MODELO.monedas[0] || 'EUR');
        }
      }
      try { recalcula(); }
      catch (e) { console.error('[finanzas] modelo:', e); aviso(T('Falló el cálculo del panel. Avisa a Desarrollo.'), 'mal'); return; }

      if (MODELO.monedas.length > 1) aviso(T('Hay importes en') + ' ' + MODELO.monedas.join(' y ') + '. ' + T('No se convierten ni se suman entre sí: elige la moneda arriba.'));

      var chips = $('lw-fin-monedas'), selSoc = $('lw-fin-sociedad'), bSin = $('lw-fin-sinfirmar');
      function pintaChips() {
        if (chips) chips.innerHTML = (MODELO.monedas.length ? MODELO.monedas : ['EUR']).map(function (m) {
          return '<button type="button" class="fin-chip" data-real data-moneda="' + esc(m) + '" aria-pressed="' + (m === MON) + '">' + esc(m) + '</button>';
        }).join('');
        if (bSin) bSin.setAttribute('aria-pressed', String(SIN_FIRMAR));
      }
      /* Lo que cambia el SIGNIFICADO de las cifras se dice en fijo, no en un
         toast: quien mira la pantalla tiene que saber qué está viendo. */
      function pintaModo() {
        var caja = $('lw-fin-modo'); if (!caja) return;
        var t = [];
        if (SIN_FIRMAR) t.push(T('Incluye contratos SIN FIRMAR: la cartera y la previsión suman borradores, que todavía no son un compromiso. Útil mientras dure el alta de histórico.'));
        if (SOC_LISTA && EMPRESA !== 'todas') t.push(T('Viendo solo') + ' ' + nombreSociedad(EMPRESA) + '. ' + T('El stock y las comisiones no se reparten por sociedad.'));
        caja.innerHTML = t.map(function (x) {
          return '<div role="status" class="rounded-xl border border-deep-lagoon/30 bg-secondary-container/30 px-5 py-3 flex items-start gap-3 font-body-sm text-body-sm text-on-surface">' +
            '<span class="material-symbols-outlined text-[20px] text-deep-lagoon shrink-0">filter_alt</span><p>' + esc(x) + '</p></div>';
        }).join('');
        pon('t-pendiente', T(SIN_FIRMAR ? 'Contratado por cobrar' : 'Firmado por cobrar'));
      }
      function pintaTodo() {
        var pm = MODELO.porMoneda[MON] || { moneda: MON, porProyecto: [] };
        pintaChips();
        pintaModo();
        pintaKpis(pm, d, anio);
        pintaCaja(pm, d, hoy);
        pintaDesglose(pm, d);
        pintaFacturado(pm, d);
        pintaTrimestres(pm, d);
        pintaStock(pm, d);
        pintaProyectos(pm, d);
        pintaCloser(pm, d);
        pintaBancos(d);
        pintaSociedades(pm, d);
        pintaSalidas(pm, d);
        pintaCajaAnio(pm, d, anio);
        pintaFuera(pm, d);
        if (typeof lwIdiomaAplicar === 'function') { try { lwIdiomaAplicar(); } catch (_) { /* traducir no puede tumbar el panel */ } }
      }
      function repinta() {
        try { recalcula(); } catch (e) { console.error('[finanzas] modelo:', e); aviso(T('Falló el cálculo del panel. Avisa a Desarrollo.'), 'mal'); return; }
        pintaTodo();
      }

      if (chips) chips.addEventListener('click', function (ev) {
        var b = ev.target.closest && ev.target.closest('[data-moneda]'); if (!b) return;
        MON = b.getAttribute('data-moneda'); guarda('lw_fin_moneda', MON);
        pintaTodo();
      });
      if (bSin) bSin.addEventListener('click', function () {
        SIN_FIRMAR = !SIN_FIRMAR; guarda('lw_fin_sin_firmar', SIN_FIRMAR ? '1' : '0');
        repinta();
      });
      if (selSoc) selSoc.addEventListener('change', function () {
        EMPRESA = selSoc.value || 'todas'; guarda('lw_fin_empresa', EMPRESA);
        repinta();
      });
      var tbProy = $('lw-fin-proyectos');
      if (tbProy) tbProy.addEventListener('click', function (ev) {
        var b = ev.target.closest && ev.target.closest('[data-fin-p]'); if (!b) return;
        var fila = document.getElementById(b.getAttribute('aria-controls'));
        var abrir = b.getAttribute('aria-expanded') !== 'true';
        b.setAttribute('aria-expanded', String(abrir));
        if (fila) fila.hidden = !abrir;
        ABIERTOS[b.getAttribute('data-fin-p')] = abrir;
      });
      var bImp = $('lw-fin-imprimir');
      if (bImp) bImp.addEventListener('click', function () {
        var cab = $('lw-fin-cab-impresa');
        if (cab) cab.textContent = T('Informe de finanzas') + ' · ' + hoy + ' · ' + MON + (SOC_LISTA && EMPRESA !== 'todas' ? ' · ' + nombreSociedad(EMPRESA) : '') + (SIN_FIRMAR ? ' · ' + T('incluye sin firmar') : '');
        window.print();
      });
      var bCsv = $('lw-fin-csv');
      if (bCsv) bCsv.addEventListener('click', function () { exportaCSV(MODELO.porMoneda[MON] || { moneda: MON }, hoy); });
      var tRes = null;
      window.addEventListener('resize', function () {
        clearTimeout(tRes);
        tRes = setTimeout(function () { var c = $('lw-fin-caja'); if (c && SERIE) dibujaCaja(c, MON, d.fallos.contratos || d.fallos.cobrado || d.fallos.vencimientos); }, 150);
      });
      pintaTodo();

      /* LA SOCIEDAD DE CADA CONTRATO, en segundo plano y DESPUÉS de pintar.
         Vive en `contratos.datos` (jsonb en TOAST: nombrar una rama obliga a
         descomprimir la fila entera, ver operaciones-cuentas.js), así que se
         pide solo `id` + esa rama, paginado, y sin bloquear el panel: hasta que
         llega, el selector está desactivado y se ve «Todas». Si falla, el
         filtro se queda desactivado y lo dice; el resto del panel no cambia. */
      if (selSoc && !d.fallos.contratos) {
        todas(function () { return sb.rpc('contratos_equipo').select('id,soc:datos->fields->>sociedad_firmante'); }, 'sociedad de los contratos')
          .then(function (filas) {
            var soc = {}; filas.forEach(function (x) { soc[x.id] = x.soc; });
            RAW.contratos.forEach(function (c) { c.soc = soc[c.id] || null; });
            var emps = (typeof empresasFinancieras === 'function') ? empresasFinancieras({ contratos: RAW.contratos }, RAW.facturas.concat(RAW.recibis)) : [];
            selSoc.innerHTML = '<option value="todas">' + esc(T('Todas las sociedades')) + '</option>' +
              emps.map(function (k) { return '<option value="' + esc(k) + '">' + esc(nombreSociedad(k)) + '</option>'; }).join('');
            if (emps.indexOf(EMPRESA) === -1) EMPRESA = 'todas';
            selSoc.value = EMPRESA;
            selSoc.disabled = false;
            SOC_LISTA = true;
            if (EMPRESA !== 'todas') repinta();
          }, function () {
            selSoc.title = T('No se pudo leer la sociedad de los contratos: el filtro no está disponible.');
          });
      }
    }).catch(function (e) {
      console.error('[finanzas]', e);
      aviso(T('No se pudo cargar el panel. Recarga la página; si sigue, avisa a Desarrollo.'), 'mal');
    });
  }

  function arranca() {
    if (!window.LW_AUTH) { aviso(T('Sin sesión: no se carga nada.'), 'mal'); return; }
    window.LW_AUTH.then(function (aut) {
      /* Mismo peldaño que la puerta (`data-rol="admin"` en guard.js): la RLS
         de contratos y facturas ya devuelve todo a un admin, pero a un rol
         inferior le daría SOLO lo suyo, y un panel de empresa con la cartera
         de un comercial se leería como la de la empresa. */
      var rol = aut.ficha && aut.ficha.rol;
      if (rol !== 'admin' && rol !== 'super_admin') { aviso(T('Esta pantalla es de dirección (admin).'), 'mal'); return; }
      monta(aut);
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
