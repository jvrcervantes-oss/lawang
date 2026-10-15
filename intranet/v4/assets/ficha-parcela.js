/* ficha-parcela.js — la ficha de la parcela con sus contratos, sus pagos y el avance de obra (Proyectos), 15-oct-2026
   ----------------------------------------------------------------------------
   QUÉ ES. El owner (15-oct): «en la ficha de la parcela me falta información, tanto de los pagos como de vinculación
   al contrato de construcción». datos.js (abrirDetalleUnidad) pinta los datos y el precio de la fila de
   `unidades_estado`; este módulo añade, al oír `lw:parcela-abierta`, cuatro cosas en sus propios contenedores:
     · «Contratos de la parcela»: la venta (raíz), sus hijos y TODAS las construcciones de esta parcela (hasta 3
       medidas el 15-oct), firmadas primero; no elige «la vigente», eso lo decide la base.
     · dentro de «Precio y cobro», los dos pendientes, que NO se suman y se rotulan distinto:
         «Pactado por cobrar» = precio de suelo + construcción − lo cobrado (las cifras de la fila: la regla «primero
         la parcela» vive solo en la base, _unidad_cobro_cascada; aquí solo se resta);
         «Facturado sin cobrar» = `contrato_saldo` de la venta (la misma cuenta con la que la base hace valer el tope).
     · «Documentos» plegado: facturas, recibís y proformas de los contratos que el usuario ve, y «Sin facturar».
     · «Avance de obra» (obra_fase del catálogo obra_fases), que no es la «Fase / zona del masterplan».
   Orden y rótulos: revisión previa de Experiencia (15-oct).

   QUIÉN DECIDE QUÉ. Solo LEE, y solo lo que el usuario ya puede ver: `contratos_equipo` y `facturas_equipo` (la RLS
   del equipo; `.from()` directo solo daría «lo mío») y `contrato_saldo` (DEFINER con su puerta). Nunca `datos` de
   contratos. Un 42501 es «no lo puedes ver», no «no hay»; una lectura caída lo dice en su bloque, nunca pinta 0.

   CÓMO SE ENGANCHA (norma del 29-sep-2026): por `data-lw="fp-*"`, nunca por un rótulo. Todo va por id: la raíz es
   `unidades_estado.contrato_id`, los hijos `contrato_padre_id`, la obra `unidad_id` + `contrato_tipo_etapa.es_obra`.

   PRUEBAS: intranet/v4/assets/ficha_parcela.test.js (node, con un sb falso). */
(function (root) {
  'use strict';

  var COLS_C = 'id,numero,tipo,bloqueado,pdf_firmado_path,precio_total,moneda,fecha_firma,contrato_padre_id,unidad_id,liberado_en,created_at';
  var COLS_F = 'id,numero,tipo,total,moneda,fecha_emision,anulada,contrato_id';
  var TOPE_GRUPO = 10, TOPE_ABIERTAS = 5;

  function T(s, h) {
    if (root && typeof root.lwT === 'function') return root.lwT(s, h);
    var v = String(s); for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) v = v.split('%' + k).join(h[k]);
    return v;
  }
  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function fmt(n, m) {
    if (root && typeof root.lwFormatoImporte === 'function') return root.lwFormatoImporte(n, m, { decimales: 0 });
    return Math.round(Number(n) || 0).toLocaleString('es-ES') + ' ' + (m || '');
  }
  function fecha(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString(root && root.lwLocale ? root.lwLocale() : 'es-ES', { day: 'numeric', month: 'short', year: 'numeric' });
  }
  function r2(n) { return Math.round((Number(n) || 0) * 100) / 100; }
  function sinPermiso(e) { return !!e && (e.code === '42501' || e.hint === 'sin_permiso'); }
  /* Sin prefijo: la frase de cada bloque («No se pudieron leer los contratos…: %e») ya lo pone. */
  function errTxt(e) {
    if (root && typeof root.lwErrorHumano === 'function') return root.lwErrorHumano(e);
    return (e && (e.message || e.code)) || '—';
  }

  /* Una lectura → {data, error}, también si la promesa revienta (red caída). */
  function lee(p) {
    return Promise.resolve(p).then(function (r) { return { data: r ? r.data : null, error: r ? r.error : null }; },
                                   function (e) { return { data: null, error: e || { message: '—' } }; });
  }

  /* Los catálogos (14 tipos, las fases de obra) no cambian dentro de una sesión: se leen una vez. */
  var CACHE = {};
  function leeObra(sb) {
    if (CACHE.obra) return Promise.resolve({ data: CACHE.obra });
    return lee(sb.from('contrato_tipo_etapa').select('tipo,es_obra')).then(function (r) {
      if (r.error) return r;
      /* Vacío no es «ningún tipo es de obra»: la base se lo devuelve vacío a quien no es agente (revisor, 15-oct). Sin
         catálogo no se sabe cuál es la construcción ni cuál es de otra parcela: se trata como «sin permiso». */
      if (!(r.data || []).length) return { data: null, error: { code: '42501', message: 'catálogo de tipos vacío' } };
      var o = {};
      (r.data || []).forEach(function (t) { if (t.es_obra) o[t.tipo] = true; });
      CACHE.obra = o;
      return { data: o };
    });
  }
  function leeFases(sb) {
    if (CACHE.fases) return Promise.resolve({ data: CACHE.fases });
    return lee(sb.from('obra_fases').select('clave,es,en')).then(function (r) {
      if (!r.error) CACHE.fases = r.data || [];
      return r;
    });
  }

  /* Los contratos que son de ESTA parcela: el filtro por `contrato_padre_id` trae también la construcción de otra
     parcela de la misma venta (7 ventas de varias parcelas, 15-oct), y ni ella ni sus documentos son de esta. */
  function dePropia(cs, esObra, U) {
    return (cs || []).filter(function (c) { return !(esObra[c.tipo] && c.unidad_id && c.unidad_id !== U); });
  }

  /* ---------- carga: dos vueltas a la base ----------
     1.ª: los contratos de la parcela, el catálogo de obra y las fases.
     2.ª: los documentos de esos contratos y el saldo de cada uno (su lista de facturas con lo cobrado; las cifras de
     la venta se toman una vez por venta). */
  function fpCarga(sb, u) {
    var R = u.contrato_id, U = u.id;
    var filtro = (R ? 'id.eq.' + R + ',contrato_padre_id.eq.' + R + ',' : '') + 'unidad_id.eq.' + U;
    return Promise.all([
      lee(sb.rpc('contratos_equipo').select(COLS_C).or(filtro)),
      leeObra(sb),
      u.obra_fase ? leeFases(sb) : Promise.resolve({ data: null })
    ]).then(function (v) {
      var out = { contratos: v[0], obra: v[1], fases: v[2], facturas: { data: [] }, saldos: {} };
      if (v[0].error || v[1].error) return out;           // sin el catálogo no se sabe cuáles son de esta parcela
      var cs = dePropia(v[0].data, v[1].data || {}, U);
      if (!cs.length) return out;
      var ids = cs.map(function (c) { return c.id; });
      return Promise.all([lee(sb.rpc('facturas_equipo').select(COLS_F).in('contrato_id', ids))].concat(
        ids.map(function (id) { return lee(sb.rpc('contrato_saldo', { p_contrato: id })); })
      )).then(function (w) {
        out.facturas = w[0];
        ids.forEach(function (id, i) { out.saldos[id] = w[i + 1]; });
        return out;
      });
    });
  }

  /* ---------- modelo: qué se enseña (sin DOM, para poder probarlo) ----------
     h.precioParte(u, parte) y h.sueloSinFirmar(u) son los de datos.js (window.LW_V4): el precio que enseña
     «Precio y cobro» y el que resta «Pactado por cobrar» salen de la misma función. h.parcelasDeVenta = cuántas
     parcelas cuelgan de la misma venta. */
  function estadoContrato(c) {
    if (c.liberado_en) return 'liberado';
    if (c.bloqueado) return 'firmado';
    return c.pdf_firmado_path ? 'reabierto' : 'borrador';
  }

  function fpModelo(u, carga, h) {
    var R = u.contrato_id, U = u.id, m = { venta: null, contratos: [], contratosError: null, obraOculta: false,
      pactado: null, cadenas: [], docs: null, obra: null, fuga: false };
    var esObra = (carga.obra && carga.obra.data) || {};
    m.venta = R ? { numero: u.contrato_numero || '', parcelas: h.parcelasDeVenta || 1 } : null;

    /* Contratos. Una construcción hija de la venta que es de OTRA parcela de la misma venta no es de esta. */
    if (carga.contratos.error) m.contratosError = carga.contratos.error;
    else if (carga.obra.error) m.contratosError = carga.obra.error;   // sin el catálogo no se sabe cuál es la construcción
    else {
      dePropia(carga.contratos.data, esObra, U).forEach(function (c) {
        var obra = !!esObra[c.tipo];
        m.contratos.push({ id: c.id, numero: c.numero, tipo: c.tipo, obra: obra, raiz: c.id === R,
          deLaVenta: obra && !c.unidad_id, estado: estadoContrato(c), fechaFirma: c.fecha_firma,
          importe: c.precio_total, moneda: c.moneda, creado: c.created_at });
      });
      var peso = function (c) { return c.raiz ? 0 : c.estado === 'liberado' ? 4 : c.obra ? (c.estado === 'firmado' ? 1 : 2) : 3; };
      m.contratos.sort(function (a, b) {
        return (peso(a) - peso(b)) || String(a.fechaFirma || a.creado || '').localeCompare(String(b.fechaFirma || b.creado || ''));
      });
      // Una obra LIBERADA no tapa a la vigente que no se ve.
      var hayObraViva = m.contratos.some(function (c) { return c.obra && c.estado !== 'liberado'; });
      /* La fila dice que hay construcción (firmada, o con precio de contrato) y la lectura no trae ninguna: existe y
         este usuario no la ve. «No hay» sería mentira. */
      m.obraOculta = !hayObraViva && (u.obra_firmada === true || u.obra_de_contrato === true);
      // La parcela tiene venta y la lectura no la trae: existe y no se ve («no tiene contratos» sería mentira).
      m.ventaOculta = !!R && !m.contratos.some(function (c) { return c.raiz; });
    }

    /* Pactado por cobrar: las cifras de la fila, restadas. Sin cobro visible no se calcula. Sin venta (la parcela
       no tiene contrato) no hay nada por cobrar: el precio de catálogo no se le debe a nadie y la ayuda hablaría de
       «la venta» (Calidad, 15-oct-2026: SH-128 enseñaba «Por cobrar del precio 260.875 EUR»). */
    var suelo = h.precioParte(u, 'suelo'), obra = h.precioParte(u, 'obra');
    // Con algo cobrado sí se calcula aunque la fila no traiga la venta: el resto (o lo cobrado de más) no se esconde.
    // Y con el cobro NO visible (sin permiso), una parcela reservada, bloqueada, vendida o cobrada se trata como con
    // venta aunque la fila no traiga `contrato_id`: sale «no visible», no nada. Solo entonces: «bloqueada» se puede
    // poner a mano en una parcela sin contrato, y con el cobro visible eso volvería a enseñar un «por cobrar» sin
    // venta (SH-128; revisor, 15-oct-2026).
    var conVenta = !!R || u.obra_de_contrato === true || u.obra_firmada === true ||
      ((u.cobrado_suelo == null || u.cobrado_obra == null) && ['reservada', 'bloqueada', 'vendida', 'cobrada'].indexOf(u.estado) >= 0) ||
      (Number(u.cobrado_suelo) || 0) + (Number(u.cobrado_obra) || 0) > 0;
    if (conVenta && (suelo != null || obra != null)) {
      if (u.cobrado_suelo == null || u.cobrado_obra == null) m.pactado = { noVisible: true };
      else {
        var cobrado = (Number(u.cobrado_suelo) || 0) + (Number(u.cobrado_obra) || 0);
        var resto = r2((suelo || 0) + (obra || 0) - cobrado);
        /* De dónde sale cada precio: la base lo dice (suelo_de_contrato / obra_de_contrato). Sin esas columnas (una
           base sin la migración) no se afirma «pactado». */
        var conOrigen = ('suelo_de_contrato' in u) && ('obra_de_contrato' in u);
        var catalogo = [];
        if (conOrigen) {
          if (suelo != null && !u.suelo_de_contrato) catalogo.push('suelo');
          if (obra != null && !u.obra_de_contrato) catalogo.push('obra');
        }
        var obraSinFirmar = u.obra_de_contrato === true && u.obra_firmada === false;
        m.pactado = { importe: Math.max(resto, 0), deMas: resto < 0 ? -resto : 0, moneda: u.moneda || 'EUR',
          pactado: conOrigen && !catalogo.length, catalogo: catalogo,
          sinFirmar: !!(h.sueloSinFirmar(u) || obraSinFirmar) };
      }
    }

    /* Por venta: el saldo de la cadena se toma una vez (todas las llamadas de una venta devuelven las mismas cifras). */
    var vistas = {}, abiertas = [], docsPorId = {}, mios = {};
    m.contratos.forEach(function (c) { mios[c.id] = 1; });
    var fs = carga.facturas.error ? [] : (carga.facturas.data || []).filter(function (f) { return !f.anulada && mios[f.contrato_id]; });
    fs.forEach(function (f) { docsPorId[f.id] = f; });
    m.contratos.forEach(function (c) {
      var s = carga.saldos[c.id];
      if (!s) return;
      if (s.error) {
        if (!vistas['!' + c.id]) m.cadenas.push({ numero: c.numero, noVisible: sinPermiso(s.error), error: sinPermiso(s.error) ? null : s.error });
        vistas['!' + c.id] = 1;
        return;
      }
      var d = s.data || {};
      /* Con impuestos, «Facturado sin cobrar» (total de las facturas) ya no es parte del precio pactado (sin impuestos):
         la ayuda «ya está dentro» deja de ser verdad. Medido el 15-oct: 0 de 175 facturas vivas llevan impuesto. */
      var conImpuesto = (d.facturas || []).some(function (f) { return f.subtotal != null && Math.abs((Number(f.total) || 0) - (Number(f.subtotal) || 0)) > 0.005; });
      if (d.cadena && vistas[d.cadena] && conImpuesto) m.cadenas.forEach(function (x) { if (x.numero === d.cadena) x.conImpuesto = true; });
      if (d.cadena && !vistas[d.cadena]) {
        vistas[d.cadena] = 1;
        m.cadenas.push({ numero: d.cadena, moneda: d.moneda, porCobrar: Number(d.por_cobrar) || 0,
          porFacturar: d.por_facturar == null ? null : Number(d.por_facturar), sinPrecio: !!d.sin_precio,
          deMas: Number(d.facturado_de_mas) > 0.005 ? Number(d.facturado_de_mas) : 0, conImpuesto: conImpuesto });
      }
      (d.facturas || []).forEach(function (f) {
        var pend = r2((Number(f.total) || 0) - (Number(f.cobrado) || 0));
        if (pend > 0.005) abiertas.push({ id: f.id, numero: f.numero, pendiente: pend, moneda: (docsPorId[f.id] || {}).moneda || d.moneda,
          fecha: (docsPorId[f.id] || {}).fecha_emision, contrato: c.numero });
      });
    });
    /* Con un error de saldo por contrato que la venta YA cubre (el hijo no visible de una venta visible), basta la venta. */
    if (m.cadenas.some(function (x) { return !x.error && !x.noVisible; }))
      m.cadenas = m.cadenas.filter(function (x) { return !x.noVisible; });
    abiertas.sort(function (a, b) { return String(a.fecha || '').localeCompare(String(b.fecha || '')); });
    m.abiertas = abiertas;
    m.fuga = m.obraOculta && m.cadenas.some(function (x) { return !x.error && !x.noVisible; });

    if (carga.facturas.error) m.docs = { error: carga.facturas.error };
    else if (m.contratos.length) {
      var g = { factura: [], recibi: [], proforma: [] }, conDocs = {};
      fs.forEach(function (f) { if (g[f.tipo]) { g[f.tipo].push(f); conDocs[f.contrato_id] = 1; } });
      Object.keys(g).forEach(function (k) {
        g[k].sort(function (a, b) { return String(b.fecha_emision || '').localeCompare(String(a.fecha_emision || '')); });
      });
      m.docs = { grupos: g, contratosConDocs: conDocs };
    }

    if (u.obra_fase) {
      var fila = ((carga.fases && carga.fases.data) || []).filter(function (f) { return f.clave === u.obra_fase; })[0];
      m.obra = { fase: fila ? (root && root.lwNombreFase ? root.lwNombreFase(fila) : (fila.es || fila.clave)) : u.obra_fase,
        entrega: u.obra_fecha_entrega, actualizado: u.obra_actualizado };
    }
    return m;
  }

  /* ---------- HTML ---------- */
  var ESTADO = { firmado: ['Firmado', 'background:#E7EFE3;color:#2F5D3A'], reabierto: ['Reabierto', 'background:#FBF3E4;color:#8A6A34'],
                 borrador: ['Sin firmar', 'background:#f5f4ee;color:#75786e'], liberado: ['Liberado', 'background:#F6E1DE;color:#9E2F26'] };
  /* `lwTipoContrato` es un `const` de vocabulario.js: está en el ámbito global de los scripts, no en `window`
     (revisor, 15-oct). Se pregunta por el nombre, como datos.js. */
  function tipoTxt(t) { return typeof lwTipoContrato === 'function' ? lwTipoContrato(t) : t; }   // eslint-disable-line no-undef
  function pastilla(txt, estilo, lw) {
    return '<span data-lw="' + lw + '" style="flex:0 0 auto;padding:1px 8px;border-radius:999px;font-size:10.5px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;' + estilo + '">' + esc(txt) + '</span>';
  }
  function aviso(txt, lw) {
    return '<p data-lw="' + lw + '" style="margin:0;padding:8px 10px;border-radius:10px;background:#FBF3E4;border:1px solid #EBDCB4;color:#8A6A34;line-height:1.45">' + esc(txt) + '</p>';
  }
  function mal(txt, lw) {
    return '<p role="alert" data-lw="' + lw + '" style="margin:0;padding:8px 10px;border-radius:10px;background:#9E2F26;color:#fff;font-weight:600;line-height:1.4">' + esc(txt) + '</p>';
  }
  function fila(k, v, ayuda, lw) {
    return '<div data-lw="' + lw + '"><div class="flex items-center justify-between gap-3"><span class="text-on-surface-variant font-medium">' + esc(k) + '</span>' +
      '<span class="font-kpi-number font-bold text-volcanic-ash" style="white-space:nowrap">' + v + '</span></div>' +
      (ayuda ? '<p style="margin:3px 0 0;color:#75786e;font-size:11px;line-height:1.4">' + esc(ayuda) + '</p>' : '') + '</div>';
  }
  function enlaceContrato(n) {
    return n ? '<a class="font-bold text-deep-lagoon hover:underline" target="_blank" rel="noopener" href="/intranet/v4/contratos/?contrato=' + encodeURIComponent(n) + '">' + esc(n) + '</a>' : '—';
  }

  function htmlContratos(m) {
    if (m.contratosError && sinPermiso(m.contratosError)) return aviso(T('No tienes permiso para ver los contratos de esta parcela. Los ve un administrador de la empresa.'), 'fp-contratos-sin-permiso');
    if (m.contratosError) return mal(T('No se pudieron leer los contratos de la parcela: %e', { e: errTxt(m.contratosError) }), 'fp-contratos-error');
    var out = '';
    // Si la venta no se ve, su número tampoco: el aviso de abajo basta.
    if (m.venta && m.venta.parcelas > 1 && !m.ventaOculta)
      out += '<p data-lw="fp-venta" style="margin:0;color:#75786e">' + esc(T('Venta %v · %n parcelas', { v: m.venta.numero, n: m.venta.parcelas })) + '</p>';
    if (m.ventaOculta) out += aviso(T('Esta parcela tiene un contrato de venta que no puedes ver. Lo ve un administrador de la empresa.'), 'fp-venta-oculta');
    if (!m.contratos.length && !m.obraOculta && !m.ventaOculta) out += '<p data-lw="fp-sin-contratos" style="margin:0;color:#75786e">' + esc(T('Esta parcela no tiene contratos.')) + '</p>';
    if (m.contratos.length) out += '<ul style="list-style:none;margin:0;padding:0;display:grid;gap:8px">' + m.contratos.map(function (c) {
      var e = ESTADO[c.estado];
      var meta = [tipoTxt(c.tipo)];   // el tipo ya dice «Construcción» (o el nombre de su modelo): no se repite
      if (c.deLaVenta) meta.push(T('de toda la venta, sin parcela asignada'));
      if (c.fechaFirma && c.estado !== 'borrador') meta.push(T('firmado el %f', { f: fecha(c.fechaFirma) }));
      // La construcción se distingue con un filete a la izquierda (sin otra pastilla al lado de la de estado).
      return '<li data-lw="fp-contrato" data-obra="' + (c.obra ? '1' : '0') + '" style="padding:9px 11px;border:1px solid #E4DCCB;' +
        (c.obra ? 'border-left:3px solid #104C4F;' : '') + 'border-radius:10px;background:#fff">' +
        '<div class="flex items-center justify-between gap-2">' + enlaceContrato(c.numero) + pastilla(T(e[0]), e[1], 'fp-estado') + '</div>' +
        '<div class="flex items-baseline justify-between gap-2" style="margin-top:2px;font-size:11px;color:#75786e">' +
        '<span style="min-width:0;overflow-wrap:anywhere">' + esc(meta.join(' · ')) + '</span>' +
        '<span class="font-kpi-number" style="white-space:nowrap">' + (c.importe != null ? esc(fmt(c.importe, c.moneda)) : '—') + '</span></div></li>';
    }).join('') + '</ul>';
    if (m.obraOculta) out += aviso(T('Hay un contrato de construcción que no puedes ver. Lo ve un administrador de la empresa.'), 'fp-obra-oculta');
    return out;
  }

  function htmlPendientes(m) {
    var out = '';
    var et = m.pactado && m.pactado.pactado ? T('Pactado por cobrar') : T('Por cobrar del precio');
    if (m.pactado) {
      if (m.pactado.noVisible) out += fila(et, esc(T('sin permiso para ver el cobro')), '', 'fp-pactado');
      else {
        var p = m.pactado, ayuda = T('Precio de suelo y construcción menos lo cobrado. El cobro se aplica primero al suelo.');
        if (p.catalogo.length) ayuda += ' ' + (p.catalogo.length === 2 ? T('Los dos precios son de catálogo: la venta aún no tiene contrato con precio.')
          : p.catalogo[0] === 'suelo' ? T('El precio del suelo es de catálogo: la venta aún no tiene contrato con precio de suelo.')
          : T('El precio de construcción es de catálogo: aún no hay contrato de construcción con precio.'));
        if (p.pactado) ayuda = T('Precio pactado de suelo y construcción menos lo cobrado. El cobro se aplica primero al suelo.');
        out += fila(et, esc(fmt(p.importe, p.moneda)) + (p.sinFirmar ? '<span style="font-weight:500;color:#8A6A34"> · ' + esc(T('incluye contrato sin firmar')) + '</span>' : ''), ayuda, 'fp-pactado');
        if (p.deMas) out += aviso(T('Se ha cobrado %a más que el precio de la parcela.', { a: fmt(p.deMas, p.moneda) }), 'fp-de-mas');
      }
    }
    var buenas = m.cadenas.filter(function (x) { return !x.error && !x.noVisible; });
    buenas.forEach(function (x) {
      var varias = buenas.length > 1 || (m.venta && m.venta.parcelas > 1);
      var k = varias ? T('Facturado sin cobrar · venta %v', { v: x.numero }) : T('Facturado sin cobrar');
      // «Ya está dentro» solo si es verdad: una parcela, sin exceso facturado y sin impuestos en las facturas.
      var ayuda = (m.venta && m.venta.parcelas > 1) ? T('Es de toda la venta (%n parcelas).', { n: m.venta.parcelas })
        : x.conImpuesto ? T('Con impuestos: no se resta del precio pactado.')
        : m.pactado && !m.pactado.noVisible && !x.deMas ? T('Ya está dentro de «%k»: no se suman.', { k: et }) : '';
      out += fila(k, esc(fmt(x.porCobrar, x.moneda)), ayuda, 'fp-facturado-sin-cobrar');
      /* `facturado_de_mas` (contrato_saldo, 15-oct-2026): «por facturar» se queda en 0 y no enseña el exceso. */
      /* Sin precio no hay tope: la base deja facturar sin freno (RP00079, 15-oct). Una fila de pendientes no la ve nadie
         desde aquí; el aviso sí (consulta de Administración). */
      if (x.sinPrecio) out += aviso(T('La venta %v no tiene tope de facturación: a uno de sus contratos le falta el precio. Ponlo en el contrato.', { v: x.numero }), 'fp-sin-tope');
      if (x.deMas) out += aviso(T('La venta %v tiene facturado %a más que su precio: algún documento sobra. Revísalo en Facturas y anula el que no corresponda.',
        { v: x.numero, a: fmt(x.deMas, x.moneda) }), 'fp-facturado-de-mas');
    });
    m.cadenas.forEach(function (x) {
      if (x.noVisible) out += fila(T('Facturado sin cobrar'), esc(T('sin permiso para ver el cobro')), '', 'fp-facturado-sin-cobrar');
      else if (x.error) out += mal(T('No se pudo leer lo facturado de %c: %e', { c: x.numero || '—', e: errTxt(x.error) }), 'fp-saldo-error');
    });
    if (m.abiertas && m.abiertas.length) {
      out += '<ul data-lw="fp-abiertas" style="list-style:none;margin:0;padding:0;display:grid;gap:4px">' + m.abiertas.slice(0, TOPE_ABIERTAS).map(function (a) {
        return '<li class="flex items-baseline justify-between gap-2" style="font-size:11.5px"><span style="min-width:0;overflow-wrap:anywhere">' +
          esc(T('Factura %n', { n: a.numero })) + (a.fecha ? ' <span style="color:#75786e">· ' + esc(fecha(a.fecha)) + '</span>' : '') + '</span>' +
          '<span class="font-kpi-number" style="white-space:nowrap;color:#8A6A34">' + esc(T('falta %a', { a: fmt(a.pendiente, a.moneda) })) + '</span></li>';
      }).join('') + '</ul>' +
        (m.abiertas.length > TOPE_ABIERTAS ? '<p style="margin:0;color:#75786e;font-size:11px">' + esc(T('Y %n facturas abiertas más, en Documentos.', { n: m.abiertas.length - TOPE_ABIERTAS })) + '</p>' : '');
    }
    if (m.fuga) out += '<p data-lw="fp-fuga" style="margin:0;color:#75786e;font-size:11px;line-height:1.4">' + esc(T('Los totales de la venta incluyen documentos que no puedes abrir.')) + '</p>';
    return out;
  }

  function htmlDocsResumen(m) {
    if (!m.docs) return '';
    if (m.docs.error) return esc(T('Documentos'));
    // Singular y plural son dos claves enteras (i18n.js): «1 facturas» / «1 invoices» salía así hasta el 15-oct.
    var cuenta = function (n, uno, varios) { return T(n === 1 ? uno : varios, { n: n }); };
    var g = m.docs.grupos, partes = [cuenta(g.factura.length, '%n factura', '%n facturas'), cuenta(g.recibi.length, '%n recibí', '%n recibís'),
      cuenta(g.proforma.length, '%n proforma', '%n proformas')];
    var sf = m.cadenas.filter(function (x) { return !x.error && !x.noVisible; });
    // En una venta de varias parcelas «Sin facturar» es de la venta: se dice en el cuerpo, no en el resumen.
    if (sf.length === 1 && !(m.venta && m.venta.parcelas > 1))
      partes.push(sf[0].porFacturar == null ? T('Sin facturar —') : T('Sin facturar %a', { a: fmt(sf[0].porFacturar, sf[0].moneda) }));
    return esc(T('Documentos')) + ' <span style="font-weight:500;text-transform:none;letter-spacing:0;color:#75786e">· ' + esc(partes.join(' · ')) + '</span>';
  }
  function htmlDocsCuerpo(m) {
    if (!m.docs) return '';
    if (m.docs.error) return mal(T('No se pudieron leer los documentos: %e', { e: errTxt(m.docs.error) }), 'fp-docs-error');
    var g = m.docs.grupos, out = '';
    var sf = m.cadenas.filter(function (x) { return !x.error && !x.noVisible; });
    sf.forEach(function (x) {
      out += fila(sf.length > 1 || (m.venta && m.venta.parcelas > 1) ? T('Sin facturar · venta %v', { v: x.numero }) : T('Sin facturar'),
        x.porFacturar == null ? '—' : esc(fmt(x.porFacturar, x.moneda)),
        x.sinPrecio ? T('Algún contrato de esta venta no tiene precio fijado: sin precio no se puede calcular.') : T('Precio de la venta menos lo ya facturado, sin impuestos.'), 'fp-sin-facturar');
    });
    [['factura', 'Facturas'], ['recibi', 'Recibís'], ['proforma', 'Proformas']].forEach(function (par) {
      var l = g[par[0]];
      if (!l.length) return;
      out += '<div data-lw="fp-grupo" data-tipo="' + par[0] + '"><p style="margin:0 0 4px;font-weight:700;color:#2E3437">' + esc(T(par[1])) + '</p>' +
        '<ul style="list-style:none;margin:0;padding:0;display:grid;gap:3px">' + l.slice(0, TOPE_GRUPO).map(function (f) {
          return '<li class="flex items-baseline justify-between gap-2" style="font-size:11.5px"><span style="min-width:0;overflow-wrap:anywhere">' + esc(f.numero || '—') +
            (f.fecha_emision ? ' <span style="color:#75786e">· ' + esc(fecha(f.fecha_emision)) + '</span>' : '') + '</span>' +
            '<span class="font-kpi-number" style="white-space:nowrap">' + esc(fmt(f.total, f.moneda)) + '</span></li>';
        }).join('') + '</ul>' +
        (l.length > TOPE_GRUPO ? '<p style="margin:3px 0 0;color:#75786e;font-size:11px">' + esc(T('Se enseñan los %n más recientes.', { n: TOPE_GRUPO })) + '</p>' : '') + '</div>';
    });
    if (!g.factura.length && !g.recibi.length && !g.proforma.length)
      out += '<p style="margin:0;color:#75786e">' + esc(T('Todavía no hay documentos de estos contratos.')) + '</p>';
    /* Un enlace por contrato con documentos: el buscador de Facturas encuentra por el número del contrato del que
       cuelga cada documento, y el de la venta no trae los de la construcción. */
    var conDocs = m.contratos.filter(function (c) { return (m.docs.contratosConDocs || {})[c.id]; });
    if (conDocs.length)
      out += '<p data-lw="fp-ver-facturas" style="margin:0">' + esc(T('Ver en Facturas')) + ': ' + conDocs.map(function (c) {
        return '<a class="font-bold text-deep-lagoon hover:underline" target="_blank" rel="noopener" href="/intranet/v4/facturas/?q=' +
          encodeURIComponent(c.numero) + '">' + esc(c.numero) + '</a>';
      }).join(' · ') + '</p>';
    return out;
  }

  function htmlObra(m) {
    if (!m.obra) return '';
    var o = m.obra;
    return fila(T('Fase de obra'), esc(o.fase || '—'), '', 'fp-obra-fase') +
      fila(T('Entrega prevista'), esc(fecha(o.entrega) || T('sin fecha')), '', 'fp-obra-entrega') +
      (o.actualizado ? '<p style="margin:0;color:#75786e;font-size:11px">' + esc(T('Actualizado el %f', { f: fecha(o.actualizado) })) + '</p>' : '');
  }

  /* ---------- DOM ---------- */
  function q(k) { return document.querySelector('[data-lw="' + k + '"]'); }
  function muestra(el, si) { if (el) el.classList.toggle('hidden', !si); }
  var cur = { id: null, tok: 0 };

  function limpia() {
    ['fp-contratos', 'fp-pendientes', 'fp-docs', 'fp-obra'].forEach(function (k) { muestra(q(k), false); });
    ['fp-contratos-cuerpo', 'fp-pendientes', 'fp-docs-resumen', 'fp-docs-cuerpo', 'fp-obra-cuerpo'].forEach(function (k) { var e = q(k); if (e) e.innerHTML = ''; });
    var d = q('fp-docs'); if (d) d.open = false;
  }

  function pinta(m) {
    var c = q('fp-contratos-cuerpo'); if (c) c.innerHTML = htmlContratos(m);
    muestra(q('fp-contratos'), true);
    var p = q('fp-pendientes'), hp = htmlPendientes(m);
    if (p) p.innerHTML = hp;
    muestra(p, !!hp);
    var rs = q('fp-docs-resumen'), dc = q('fp-docs-cuerpo');
    if (rs) rs.innerHTML = htmlDocsResumen(m);
    if (dc) dc.innerHTML = htmlDocsCuerpo(m);
    muestra(q('fp-docs'), !!m.docs);
    var o = q('fp-obra-cuerpo'); if (o) o.innerHTML = htmlObra(m);
    muestra(q('fp-obra'), !!m.obra);
  }

  function abre(id) {
    var V4 = root.LW_V4 || {}, u = V4.unidades && V4.unidades[id];
    limpia();
    var tok = ++cur.tok;                                  // antes de cualquier salida: una carga vieja nunca pinta aquí
    if (!u || !q('fp-contratos')) return;
    var c = q('fp-contratos-cuerpo');
    if (c) c.innerHTML = '<p style="margin:0;color:#75786e">' + esc(T('Trayendo los contratos…')) + '</p>';
    muestra(q('fp-contratos'), true);
    var parcelas = 1;
    if (u.contrato_id) parcelas = Object.keys(V4.unidades).filter(function (k) { return V4.unidades[k] && V4.unidades[k].contrato_id === u.contrato_id; }).length || 1;
    var h = { precioParte: V4.precioParte, sueloSinFirmar: V4.sueloSinFirmar, parcelasDeVenta: parcelas };
    (root.LW_AUTH ? root.LW_AUTH.then(function (a) { return a.sb; }) : Promise.reject(new Error(T('Sin sesión'))))
      .then(function (sb) { return fpCarga(sb, u); })
      .then(function (carga) {
        if (tok !== cur.tok) return;                       // ya hay otra parcela abierta
        pinta(fpModelo(u, carga, h));
      })
      .then(null, function (e) {
        if (tok !== cur.tok) return;
        if (c) c.innerHTML = mal(T('No se pudieron leer los contratos de la parcela: %e', { e: errTxt(e) }), 'fp-contratos-error');
      });
  }

  var api = { fpCarga: fpCarga, fpModelo: fpModelo, fpHTML: { contratos: htmlContratos, pendientes: htmlPendientes,
    docsResumen: htmlDocsResumen, docsCuerpo: htmlDocsCuerpo, obra: htmlObra }, _reinicia: function () { CACHE = {}; } };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }

  document.addEventListener('lw:parcela-abierta', function (ev) {
    var d = (ev && ev.detail) || {};
    cur.id = d.id || null;
    if (cur.id) abre(cur.id);
  });
  document.addEventListener('lw:parcela-cerrada', function () { cur.id = null; cur.tok++; limpia(); });
})(typeof window !== 'undefined' ? window : this);
