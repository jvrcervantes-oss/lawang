/* datos.js — cableado de la v4 a DATOS REALES (4-sep-2026). SOLO LECTURA.
 *
 * Reglas (revisión previa Seguridad+Datos+Desarrollo, 4-sep):
 *  - Espera window.LW_AUTH (guard.js de la suite) y usa SU cliente (window.LW_SB).
 *  - Listados de contratos/facturas por las RPC de equipo `contratos_equipo()` /
 *    `facturas_equipo()` — un .from() directo solo devuelve «lo mío» (es_suyo)
 *    y daría MENOS filas sin error. Nunca se selecciona el jsonb `datos` (TOAST).
 *  - Importes con lwFormatoImporte (dinero.js) y tipos con lwTipoContrato /
 *    lwEsPreliminar (vocabulario.js): fuente única, nada copiado.
 *  - Firmado = bloqueado === true. Nunca fecha_firma.
 *  - Fallos RUIDOSOS: console.error + estado visible. «—» solo para una cifra
 *    suelta; un listado que no carga lo dice en el propio contenedor. Una
 *    respuesta vacía en tabla que sabemos poblada se pinta «—», no 0.
 *  - Antes de consultar, las cifras mock de Stitch que este fichero cablea se
 *    vacían a «—»: un número solo puede venir de la base.
 *  - La pantalla se identifica por el ÚLTIMO segmento de la ruta (vale en
 *    /intranet/v4/ y en cualquier otro despliegue). */
(function () {
  'use strict';

  var seg = location.pathname.replace(/\/(index\.html)?$/, '').split('/').pop();

  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
  function fmt(n, m) { return (typeof lwFormatoImporte === 'function') ? lwFormatoImporte(n, m) : (n + ' ' + (m || '')); }
  function tipoC(t) { return (typeof lwTipoContrato !== 'undefined') ? lwTipoContrato(t) : t; }
  function fFecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x).slice(0, 10) : d.toLocaleDateString('es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); }

  /* ---- localizar por TEXTO en el marcado minificado de Stitch ---- */
  function hojaConTexto(rx, raiz) {
    var all = (raiz || document.body).querySelectorAll('span,p,h1,h2,h3,h4,div,th,button');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.children.length > 2) continue;
      if (rx.test(el.textContent.replace(/\s+/g, ' ').trim()) && el.textContent.length < 90) return el;
    }
    return null;
  }
  function tarjetaDe(el) { var t = el; for (var i = 0; i < 6 && t.parentElement; i++) { t = t.parentElement; if (/rounded|card|bg-/.test(t.className) && t.querySelectorAll('*').length > 3) break; } return t; }
  function numeroGrande(card) {
    var mejor = null, tam = 0;
    card.querySelectorAll('span,p,div,h2,h3').forEach(function (el) {
      if (el.children.length > 1) return;
      var t = el.textContent.trim();
      if (!/[0-9—]/.test(t) || t.length > 24) return;
      var fs = parseFloat(getComputedStyle(el).fontSize) || 0;
      if (fs > tam) { tam = fs; mejor = el; }
    });
    return mejor;
  }
  function kpi(labelRx, valor, pie) {
    var lab = hojaConTexto(labelRx); if (!lab) { console.info('[v4] KPI sin ancla:', labelRx); return; }
    var card = tarjetaDe(lab); var num = numeroGrande(card);
    if (num) num.textContent = valor;
    if (pie != null) {
      var pieEl = null;
      card.querySelectorAll('span,p,div').forEach(function (el) {
        if (pieEl || el === num || el === lab || el.children.length) return;
        var fs = parseFloat(getComputedStyle(el).fontSize) || 0;
        if (fs <= 14 && el.textContent.trim().length > 3) pieEl = el;
      });
      if (pieEl) pieEl.textContent = pie;
    }
  }
  function vaciaKpis(labels) { labels.forEach(function (rx) { kpi(rx, '—'); }); }

  function tablaPor(headRxs) {
    var tablas = document.querySelectorAll('table');
    for (var i = 0; i < tablas.length; i++) {
      var txt = (tablas[i].tHead ? tablas[i].tHead.textContent : tablas[i].textContent).toUpperCase();
      var hits = headRxs.filter(function (r) { return r.test(txt); }).length;
      if (hits >= Math.min(2, headRxs.length)) return tablas[i];
    }
    return null;
  }
  /* Plantilla de fila NORMALIZADA (Desarrollo, 4-sep): la 1ª fila de Stitch suele
     ser la "seleccionada"; se toma la 2ª si existe, se quita su onclick falso y
     las filas estáticas restantes SE BORRAN — nunca se añade detrás del mock. */
  function plantillaFilas(tabla) {
    var tb = tabla.tBodies[0]; if (!tb || !tb.rows.length) return null;
    var base = tb.rows[Math.min(1, tb.rows.length - 1)].cloneNode(true);
    base.removeAttribute('onclick');
    base.querySelectorAll('[onclick]').forEach(function (x) { x.removeAttribute('onclick'); });
    while (tb.rows.length) tb.deleteRow(0);
    return { tbody: tb, base: base };
  }
  function fila(pl, celdas, url) {
    var tr = pl.base.cloneNode(true);
    var tds = tr.querySelectorAll('td');
    for (var i = 0; i < tds.length; i++) {
      if (i < celdas.length && celdas[i] != null) tds[i].innerHTML = '<span class="font-body-md">' + esc(celdas[i]) + '</span>';
      else if (i >= celdas.length) tds[i].innerHTML = '';
    }
    if (url) { tr.style.cursor = 'pointer'; tr.addEventListener('click', function () { location.href = url; }); }
    pl.tbody.appendChild(tr);
  }

  function fallo(donde, err, contenedor) {
    var code = err && (err.code || err.status) ? ' (' + (err.code || err.status) + ')' : '';
    console.error('[v4 datos] ' + donde + ' no cargó' + code, err);
    if (contenedor) contenedor.innerHTML = '<div style="padding:18px;font:500 13px \'Neue Kabel\',sans-serif;color:#93000a;background:#ffdad6;border-radius:8px">No se ha podido cargar «' + esc(donde) + '»' + code + ' — revisa sesión/permisos.</div>';
  }
  function bandaNota(texto, color) {
    var d = document.createElement('div');
    d.style.cssText = 'position:sticky;top:0;z-index:60;background:' + (color || '#104C4F') + ';color:#F5F0E6;text-align:center;font:600 12px/1.4 "Neue Kabel",sans-serif;letter-spacing:.06em;padding:7px 12px';
    d.textContent = texto;
    document.body.prepend(d);
  }

  function q(p, nombre, cont) {
    return p.then(function (r) {
      if (r.error) { fallo(nombre, r.error, cont); return null; }
      return r.data || [];
    }, function (e) { fallo(nombre, e, cont); return null; });
  }
  function cnt(sb, tabla, mod, cols) {
    var qq = sb.from(tabla).select(cols || '*', { count: 'exact', head: true });
    if (mod) qq = mod(qq);
    return qq.then(function (r) { return r.error ? (fallo('count ' + tabla, r.error), null) : (r.count || 0); });
  }

  var mesIni = new Date(); mesIni.setDate(1); mesIni.setHours(0, 0, 0, 0);
  function sumaMesEUR(recibis) {
    var eur = 0, otros = 0;
    (recibis || []).forEach(function (f) {
      if (f.anulada) return;
      if (new Date(f.created_at) < mesIni) return;
      if ((f.moneda || 'EUR') === 'EUR') eur += Number(f.total) || 0; else otros++;
    });
    return { eur: eur, otros: otros };
  }

  /* ══════════════ registro por pantalla ══════════════ */
  var REG = {

    home: function (sb) {
      vaciaKpis([/CONTRATOS ACTIVOS/i, /COBRADO ESTE MES/i, /VENCIMIENTOS/i, /UNIDADES LIBRES/i]);
      q(sb.rpc('contratos_equipo').select('id,bloqueado'), 'contratos').then(function (cs) {
        if (!cs) return;
        var firmados = cs.filter(function (c) { return c.bloqueado; }).length;
        kpi(/CONTRATOS ACTIVOS/i, String(cs.length), firmados + ' firmados · ' + (cs.length - firmados) + ' editables');
      });
      q(sb.rpc('facturas_equipo').select('tipo,total,moneda,anulada,created_at,numero,cliente_nombre,proyecto_nombre'), 'facturas').then(function (fs) {
        if (!fs) return;
        var s = sumaMesEUR(fs.filter(function (f) { return f.tipo === 'recibi'; }));
        kpi(/COBRADO ESTE MES/i, fmt(s.eur, 'EUR'), s.otros ? '+' + s.otros + ' cobros en otra moneda' : 'recibís del mes en curso');
        var t = tablaPor([/TIPO/, /DOC/, /COMPRADOR|CLIENTE/, /IMPORTE/]);
        if (t) {
          var pl = plantillaFilas(t);
          fs.slice().sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 6).forEach(function (f) {
            fila(pl, [f.tipo === 'recibi' ? 'Recibí' : f.tipo === 'proforma' ? 'Proforma' : 'Factura',
              f.numero, f.cliente_nombre, f.proyecto_nombre || '—', fmt(f.total, f.moneda), fFecha(f.created_at),
              f.anulada ? 'ANULADA' : 'EMITIDA'], '/intranet/facturas/');
          });
        }
      });
      var hoy = new Date().toISOString().slice(0, 10);
      var en30 = new Date(Date.now() + 30 * 864e5).toISOString().slice(0, 10);
      cnt(sb, 'contrato_vencimientos', function (x) { return x.gte('fecha', hoy).lte('fecha', en30).eq('contratos.bloqueado', true); }, '*, contratos!inner(id)')
        .then(function (n) { if (n != null) kpi(/VENCIMIENTOS/i, String(n), 'con fecha en los próximos 30 días'); });
      Promise.all([cnt(sb, 'unidades'), cnt(sb, 'unidades', function (x) { return x.eq('estado', 'libre'); })]).then(function (r) {
        if (r[1] != null) kpi(/UNIDADES LIBRES/i, String(r[1]), r[0] != null ? 'de ' + r[0] + ' en inventario' : null);
      });
    },

    contratos: function (sb) {
      var t = tablaPor([/CONTRATO|N[ºU]/, /COMPRADOR/, /TIPO|ESTADO/]);
      q(sb.rpc('contratos_equipo').select('numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,created_at'), 'contratos', t)
        .then(function (cs) {
          if (!cs) return;
          if (!cs.length) { kpi(/Todos/i, '—'); return; }
          var chip = hojaConTexto(/^Todos\b/i); if (chip) chip.textContent = 'Todos ' + cs.length;
          if (!t) { console.info('[v4] contratos: tabla sin ancla'); return; }
          var pl = plantillaFilas(t);
          cs.sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 120).forEach(function (c) {
            fila(pl, [c.numero, tipoC(c.tipo), c.comprador_nombre || '—', c.proyecto_nombre || '—',
              c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—',
              c.bloqueado ? 'FIRMADO' : 'BORRADOR', fFecha(c.created_at)],
              '/contracts/app.html?contrato=' + encodeURIComponent(c.numero));
          });
        });
    },

    facturas: function (sb) {
      var t = tablaPor([/DOC|FACTURA|N[ºU]/, /CLIENTE|COMPRADOR/, /IMPORTE|TOTAL/]);
      q(sb.rpc('facturas_equipo').select('id,numero,tipo,cliente_nombre,contrato_numero,total,moneda,anulada,created_at'), 'facturas', t)
        .then(function (fs) {
          if (!fs || !t) return;
          var pl = plantillaFilas(t);
          function pinta(filtro) {
            while (pl.tbody.rows.length) pl.tbody.deleteRow(0);
            fs.filter(function (f) { return !filtro || f.tipo === filtro; })
              .sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 120)
              .forEach(function (f) {
                fila(pl, [f.numero, f.tipo === 'recibi' ? 'Recibí' : f.tipo === 'proforma' ? 'Proforma' : 'Factura',
                  f.cliente_nombre || '—', f.contrato_numero || '—', fmt(f.total, f.moneda),
                  f.anulada ? 'ANULADA' : 'EMITIDA', fFecha(f.created_at)],
                  '/intranet/facturas/?id=' + f.id);
              });
          }
          pinta(null);
          // chips de tipo: cableados de verdad (data-real) — filtran esta lista
          [['Proforma', 'proforma'], ['Factura', 'factura'], ['Recib', 'recibi'], ['Todos|Listado', null]].forEach(function (par) {
            var b = hojaConTexto(new RegExp('^' + par[0], 'i'));
            if (b && b.tagName === 'BUTTON') { b.setAttribute('data-real', '1'); b.addEventListener('click', function () { pinta(par[1]); }); }
          });
        });
    },

    recibos: function (sb) {
      vaciaKpis([/TOTAL COBRADO/i, /CONCILIADOS|EMITIDOS/i]);
      var t = tablaPor([/RECIBO|N[ºU]/, /PAGADOR|TITULAR/, /IMPORTE/]);
      q(sb.rpc('facturas_equipo').select('id,numero,tipo,cliente_nombre,contrato_numero,total,moneda,anulada,created_at'), 'recibís', t)
        .then(function (fs) {
          if (!fs) return;
          var rs = fs.filter(function (f) { return f.tipo === 'recibi'; });
          var s = sumaMesEUR(rs);
          kpi(/TOTAL COBRADO/i, fmt(s.eur, 'EUR'), 'recibís EUR del mes' + (s.otros ? ' · +' + s.otros + ' en otra moneda' : ''));
          kpi(/CONCILIADOS|EMITIDOS/i, rs.length + ' emitidos', 'histórico completo');
          if (!t) return;
          var pl = plantillaFilas(t);
          rs.sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 120).forEach(function (f) {
            fila(pl, [f.numero, f.contrato_numero || '—', f.cliente_nombre || '—', '', fmt(f.total, f.moneda), '',
              fFecha(f.created_at), f.anulada ? 'ANULADA' : 'EMITIDA'], '/intranet/facturas/?id=' + f.id);
          });
        });
      // el botón de emitir abre el formulario REAL, no el cajón de la maqueta
      var b = hojaConTexto(/Emitir recib/i);
      if (b) { var btn = b.closest('button') || b; btn.removeAttribute('onclick'); }
    },

    compradores: function (sb) {
      vaciaKpis([/INVERSORES REGISTRADOS/i]);
      var t = tablaPor([/INVERSOR|TITULAR/, /CONTACTO|PA[IÍ]S/]);
      q(sb.from('clients').select('id,full_name,email,nationality,tipo,created_at').order('created_at', { ascending: false }).limit(200), 'compradores', t)
        .then(function (cs) {
          if (!cs) return;
          if (!cs.length) { kpi(/INVERSORES REGISTRADOS/i, '—', 'sin filas: revisar permisos'); return; }
          kpi(/INVERSORES REGISTRADOS/i, String(cs.length), 'fichas en Compradores');
          if (!t) return;
          var pl = plantillaFilas(t);
          cs.slice(0, 120).forEach(function (c) {
            fila(pl, [c.full_name, (c.email || '—') + (c.nationality ? ' · ' + c.nationality : ''),
              c.tipo === 'empresa' ? 'Empresa' : 'Persona física', '', '', ''],
              '/intranet/compradores/?id=' + c.id);
          });
        });
    },

    operaciones: function (sb) {
      var t = tablaPor([/OPERACI|CONTRATO/, /COMPRADOR/, /IMPORTE|ESTADO/]);
      q(sb.rpc('contratos_equipo').select('numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,created_at'), 'operaciones', t)
        .then(function (cs) {
          if (!cs) return;
          var chip = hojaConTexto(/^Todas\b/i); if (chip) chip.textContent = 'Todas (' + cs.length + ')';
          if (!t) return;
          var pl = plantillaFilas(t);
          cs.sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 120).forEach(function (c) {
            fila(pl, [c.numero, tipoC(c.tipo), c.comprador_nombre || '—', c.proyecto_nombre || '—',
              c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—',
              c.bloqueado ? 'FIRMADO' : 'EN CURSO', fFecha(c.created_at)],
              '/intranet/operaciones/?contrato=' + encodeURIComponent(c.numero));
          });
        });
    },

    vencimientos: function (sb) {
      vaciaKpis([/PREVISI[ÓO]N DE ENTRADAS/i, /CR[IÍ]TICOS/i, /SIN REGULARIZAR|SIN FECHA/i]);
      var hoy = new Date().toISOString().slice(0, 10);
      var en30 = new Date(Date.now() + 30 * 864e5).toISOString().slice(0, 10);
      cnt(sb, 'contrato_vencimientos', function (x) { return x.is('fecha', null).eq('contratos.bloqueado', true); }, '*, contratos!inner(id)')
        .then(function (n) { if (n != null) kpi(/SIN REGULARIZAR|SIN FECHA/i, String(n), 'vencimientos sin fecha que vigilar'); });
      cnt(sb, 'contrato_vencimientos', function (x) { return x.gte('fecha', hoy).lte('fecha', en30).eq('contratos.bloqueado', true); }, '*, contratos!inner(id)')
        .then(function (n) { if (n != null) kpi(/CR[IÍ]TICOS/i, String(n), 'con fecha en 30 días'); });
      kpi(/PREVISI[ÓO]N DE ENTRADAS/i, '—', 'la cascada exacta vive en la herramienta');
      // lista: próximos vencimientos de contratos firmados
      q(sb.from('contrato_vencimientos')
          .select('descripcion,pct,monto,fecha,contratos!inner(numero,bloqueado)')
          .eq('contratos.bloqueado', true).gte('fecha', hoy).order('fecha').limit(12), 'próximos vencimientos')
        .then(function (vs) {
          if (!vs || !vs.length) return;
          var anc = hojaConTexto(/Urgentes \/ Vencidos|Esta Semana/i);
          if (!anc) { console.info('[v4] vencimientos: sin ancla de lista'); return; }
          var cont = tarjetaDe(anc).parentElement;
          var html = vs.map(function (v) {
            var imp = v.monto ? esc(v.monto) : (v.pct ? esc(v.pct) + ' %' : '—');
            return '<div style="display:flex;justify-content:space-between;gap:12px;padding:12px 16px;background:#fff;border:1px solid #e4e2dd;border-radius:10px;margin:8px 0;font-family:\'Neue Kabel\',sans-serif">' +
              '<div><div style="font-weight:600">' + esc(v.descripcion || 'Hito') + ' · ' + esc(v.contratos.numero) + '</div>' +
              '<div style="font-size:12px;color:#8A8474">' + fFecha(v.fecha) + '</div></div>' +
              '<div style="font-weight:700;white-space:nowrap">' + imp + '</div></div>';
          }).join('');
          cont.innerHTML = '<p style="font:600 15px \'The Seasons\',serif;margin:6px 0 2px">Próximos vencimientos (contratos firmados)</p>' + html +
            '<a href="/intranet/vencimientos/" style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Cascada completa en la herramienta →</a>';
        });
    },

    proyectos: function (sb) {
      Promise.all([
        q(sb.from('proyectos').select('nombre,resort').order('nombre'), 'proyectos'),
        q(sb.from('unidades_estado').select('proyecto,estado'), 'unidades')
      ]).then(function (r) {
        var ps = r[0], us = r[1];
        if (!ps) return;
        var porP = {};
        (us || []).forEach(function (u) { var k = u.proyecto || '¿?'; (porP[k] = porP[k] || { t: 0, l: 0 }); porP[k].t++; if (u.estado === 'libre') porP[k].l++; });
        // tarjetas-carpeta: plantilla = primera tarjeta con un h3 dentro del grid
        var h3 = document.querySelector('main h3, .grid h3');
        if (!h3) { console.info('[v4] proyectos: sin ancla de tarjetas'); return; }
        var card = h3.closest('a,div');
        for (var t = card; t && t.parentElement; t = t.parentElement) if (t.parentElement.children.length >= 3) { card = t; break; }
        var grid = card.parentElement, base = card.cloneNode(true);
        base.removeAttribute('onclick'); base.querySelectorAll('[onclick]').forEach(function (x) { x.removeAttribute('onclick'); });
        grid.innerHTML = '';
        ps.forEach(function (p) {
          var c = base.cloneNode(true);
          var hh = c.querySelector('h3'); if (hh) hh.textContent = p.nombre;
          var d = porP[p.nombre] || { t: 0, l: 0 };
          var pie = c.querySelector('p,span'); if (pie) pie.textContent = d.t + ' unidades · ' + d.l + ' libres' + (p.resort ? ' · ' + p.resort : '');
          c.style.cursor = 'pointer';
          c.addEventListener('click', function () { location.href = '/intranet/proyectos/?proyecto=' + encodeURIComponent(p.nombre); });
          grid.appendChild(c);
        });
        var chip = hojaConTexto(/^Todos\b/i); if (chip) chip.textContent = 'Todos ' + ps.length;
      });
    },

    'proyectos-cuentas': function (sb) {
      var pedido = new URLSearchParams(location.search).get('proyecto');
      q(sb.from('proyectos').select('nombre').order('nombre'), 'proyectos').then(function (ps) {
        if (!ps || !ps.length) return;
        var nombre = pedido || ps[0].nombre;
        var h2 = hojaConTexto(/Master Plan|Horizon S1/i); if (h2) h2.textContent = nombre + ' · Master Plan & Cuentas';
        var t = tablaPor([/UNIDAD|LOTE|C[ÓO]DIGO/, /ESTADO|MODELO/]);
        q(sb.from('unidades_estado').select('codigo,modelo,estado,contrato_numero,comprador_nombre').eq('proyecto', nombre).order('codigo').limit(120), 'unidades de ' + nombre, t)
          .then(function (us) {
            if (!us || !t) return;
            var pl = plantillaFilas(t);
            us.forEach(function (u) {
              fila(pl, [u.codigo, u.modelo || '—', (u.estado || '—').toUpperCase(),
                u.contrato_numero || '—', u.comprador_nombre || '—', ''],
                '/intranet/proyectos/?proyecto=' + encodeURIComponent(nombre));
            });
          });
      });
    },

    obra: function (sb) {
      vaciaKpis([/EN OBRA|ACTIVAS/i]);
      var t = tablaPor([/UNIDAD|VILLA|C[ÓO]DIGO/, /FASE|AVANCE/]);
      q(sb.from('unidades_estado').select('codigo,proyecto,modelo,obra_fase,obra_fecha_entrega,comprador_nombre').not('obra_fase', 'is', null).order('obra_actualizado', { ascending: false }).limit(60), 'obra', t)
        .then(function (us) {
          if (!us) return;
          kpi(/EN OBRA|ACTIVAS/i, String(us.length), 'unidades con fase abierta');
          if (!t) { console.info('[v4] obra: sin tabla ancla'); return; }
          var pl = plantillaFilas(t);
          us.forEach(function (u) {
            fila(pl, [u.codigo + ' · ' + (u.proyecto || ''), u.modelo || '—', u.obra_fase || '—',
              u.comprador_nombre || '—', fFecha(u.obra_fecha_entrega), ''], '/intranet/obra/');
          });
        });
    },

    documentacion: function (sb) {
      vaciaKpis([/EXPEDIENTES|DOCUMENTOS/i]);
      q(sb.from('documentos_proyecto').select('proyecto'), 'documentación').then(function (ds) {
        if (!ds) return;
        var porP = {}; ds.forEach(function (d) { porP[d.proyecto] = (porP[d.proyecto] || 0) + 1; });
        kpi(/EXPEDIENTES|DOCUMENTOS/i, String(ds.length), Object.keys(porP).length + ' proyectos con documentación');
        bandaNota('Bóveda real: ' + ds.length + ' documentos en ' + Object.keys(porP).length + ' proyectos — el listado y las descargas viven en la herramienta (/intranet/documentacion/)', '#485B37');
      });
    },

    creatividades: function () {
      bandaNota('Creatividades y dossiers no viven en la base de datos: el catálogo real está en /intranet/creatividades/ — los botones de esta pantalla te llevan allí', '#485B37');
    },

    usuarios: function (sb) {
      vaciaKpis([/USUARIOS ACTIVOS|MIEMBROS/i]);
      var t = tablaPor([/MIEMBRO|NOMBRE|USUARIO/, /ROL|ACCESO/]);
      q(sb.from('usuarios').select('nombre,email,rol,activo').order('nombre'), 'usuarios', t).then(function (us) {
        if (!us) return;
        var act = us.filter(function (u) { return u.activo; });
        kpi(/USUARIOS ACTIVOS|MIEMBROS/i, String(act.length), 'de ' + us.length + ' fichas');
        if (!t) return;
        var pl = plantillaFilas(t);
        us.forEach(function (u) {
          fila(pl, [u.nombre || '—', u.email || '—', u.rol || '—', u.activo ? 'ACTIVO' : 'INACTIVO', '', ''], '/intranet/usuarios/');
        });
      });
    },

    soporte: function (sb) {
      vaciaKpis([/ABIERTOS|TICKETS/i]);
      Promise.all([
        q(sb.from('hilo_soporte').select('client_id,categoria,estado,actualizado_en').order('actualizado_en', { ascending: false }).limit(60), 'soporte'),
        q(sb.from('clients').select('id,full_name'), 'clientes de soporte')
      ]).then(function (r) {
        var hs = r[0], cs = r[1] || [];
        if (!hs) return;
        var nom = {}; cs.forEach(function (c) { nom[c.id] = c.full_name; });
        var abiertos = hs.filter(function (h) { return h.estado === 'abierto'; }).length;
        kpi(/ABIERTOS|TICKETS/i, String(abiertos), 'de ' + hs.length + ' hilos');
        var chip = hojaConTexto(/^Todos\b/i); if (chip) chip.textContent = 'Todos (' + hs.length + ')';
        var t = tablaPor([/CLIENTE|COMPRADOR|ASUNTO/, /ESTADO|CATEGOR/]);
        if (!t) { console.info('[v4] soporte: sin tabla ancla'); return; }
        var pl = plantillaFilas(t);
        hs.forEach(function (h) {
          fila(pl, [nom[h.client_id] || h.client_id, h.categoria || '—',
            (h.estado || '—').toUpperCase(), fFecha(h.actualizado_en), '', ''],
            '/intranet/soporte/?id=' + h.client_id);
        });
      });
    },

    'generador-contratos': function () {
      bandaNota('Diseño v4 del generador — el generador REAL (con todas sus validaciones) es /contracts/app.html; los botones de esta pantalla te llevan allí');
    },

    'contratos-inversor': function () {
      bandaNota('VISTA PREVIA del portal del comprador — datos de demostración. El portal real vive en /portal/ con su propio acceso', '#C06C47');
    }
  };

  function arranca() {
    if (!window.LW_AUTH) { console.error('[v4 datos] sin guard: no se cablea nada'); return; }
    window.LW_AUTH.then(function (aut) {
      document.body.setAttribute('data-datos', 'reales');
      var raiz = document.querySelector('script[src*="datos.js"]').src.replace(/assets\/datos\.js.*$/, '');
      function ponBanner() {
        var b = document.getElementById('lw-maqueta');
        if (!b) { setTimeout(ponBanner, 250); return; }   // nav.js lo crea en DOMContentLoaded: puede llegar después
        b.innerHTML = 'V4 · DATOS EN VIVO · <a href="' + raiz + '" style="color:#DFB376;text-decoration:underline">Hub</a>';
      }
      ponBanner();
      var fn = REG[seg];
      if (fn) { try { fn(aut.sb); } catch (e) { fallo('pantalla ' + seg, e); } }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
