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
      // nunca anclar en la cáscara: la sidebar tiene "Vencimientos", "Recibos"…
      // y el primer intento le escribió el pie de un KPI al subtítulo del logo
      if (el.closest('aside,nav,header,#lw-modal,#lw-maqueta')) continue;
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
    if (num) {
      num.textContent = valor;
      // las coletillas mock pegadas al número ("unidades", "€") mienten al lado
      // de un valor real: se vacían las hojas pequeñas hermanas del número
      var hermanos = num.parentElement ? num.parentElement.children : [];
      for (var i = 0; i < hermanos.length; i++) {
        var h = hermanos[i];
        if (h !== num && h.children.length === 0 && h.textContent.trim().length < 26) h.textContent = '';
      }
    }
    if (pie != null) {
      var pieEl = null;
      card.querySelectorAll('span,p,div').forEach(function (el) {
        if (pieEl || el === num || el === lab || el.children.length) return;
        if (lab.contains(el) || el.contains(lab)) return;
        // el pie va DEBAJO del número: solo vale un elemento que lo siga en el DOM
        if (num && !(num.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)) return;
        var fs = parseFloat(getComputedStyle(el).fontSize) || 0;
        if (fs <= 14 && el.textContent.trim().length > 3) pieEl = el;
      });
      if (pieEl) pieEl.textContent = pie;
    }
  }
  /* Anclaje por `data-lw`: deterministico, para las pantallas cuyo fichero ya es
     nuestro. El anclaje por TEXTO (kpi/hojaConTexto) sigue siendo lo correcto
     donde el marcado de Stitch no se toca. */
  function pon2(k, v) { var e = document.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v; }

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

  /* Panel «DATOS EN VIVO» tras la cabecera: para pantallas cuya maqueta no usa
     <table>. Siempre se pinta — con filas reales o con el estado vacío honesto —
     y avisa de que lo de debajo es diseño. */
  function itemPanel(izq, sub, der) {
    return '<div style="display:flex;justify-content:space-between;gap:12px;padding:11px 14px;background:#fff;border:1px solid #e4e2dd;border-radius:10px;font-family:\'Neue Kabel\',sans-serif;cursor:pointer" data-mq-item>' +
      '<div style="min-width:0"><div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' + izq + '</div>' +
      (sub ? '<div style="font-size:12px;color:#8A8474">' + sub + '</div>' : '') + '</div>' +
      (der != null ? '<div style="font-weight:700;white-space:nowrap;align-self:center">' + der + '</div>' : '') + '</div>';
  }
  function panelReal(titulo, items, urls, vacio, verMasUrl) {
    var h1 = document.querySelector('h1'); if (!h1) return;
    var cab = h1; for (var i = 0; i < 4 && cab.parentElement; i++) { cab = cab.parentElement; if (cab.parentElement && cab.parentElement.tagName === 'MAIN') break; }
    var d = document.createElement('section');
    d.style.cssText = 'margin:18px 0 26px;padding:16px 18px;background:#F1EBDD;border:1px solid #c5c8bc;border-radius:14px';
    d.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:baseline;gap:10px;margin-bottom:10px">' +
      '<span style="font:700 11px \'Neue Kabel\',sans-serif;letter-spacing:.18em;color:#485B37">● DATOS EN VIVO</span>' +
      '<span style="font:400 11px \'Neue Kabel\',sans-serif;color:#8A8474">lo de debajo es diseño de la maqueta</span></div>' +
      '<p style="font:600 20px \'The Seasons\',serif;color:#314322;margin:0 0 10px">' + esc(titulo) + '</p>' +
      (items.length ? '<div style="display:grid;gap:8px">' + items.join('') + '</div>'
                    : '<p style="font:400 13px \'Neue Kabel\',sans-serif;color:#44483f;margin:0">' + esc(vacio || 'Sin registros.') + '</p>') +
      (verMasUrl ? '<a href="' + verMasUrl + '" style="display:inline-block;margin-top:10px;font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Abrir la herramienta completa →</a>' : '');
    cab.insertAdjacentElement('afterend', d);
    var its = d.querySelectorAll('[data-mq-item]');
    for (var j = 0; j < its.length; j++) (function (k) {
      if (urls && urls[k]) its[k].addEventListener('click', function () { location.href = urls[k]; });
      else its[k].style.cursor = 'default';
    })(j);
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
        if (r[1] != null) kpi(/UNIDADES LIBRES/i, String(r[1]), r[0] != null ? 'disponibles de ' + r[0] + ' en inventario' : null);
      });
      // módulos laterales: nunca dejar las tarjetas mock como "verdad"
      q(sb.from('contrato_vencimientos').select('descripcion,pct,monto,fecha,contratos!inner(numero,bloqueado)')
          .eq('contratos.bloqueado', true).gte('fecha', hoy).order('fecha').limit(3), 'vencimientos críticos')
        .then(function (vs) {
          if (vs == null) return;
          var anc = hojaConTexto(/Cr[ií]ticos/i);
          if (!anc) { console.info('[v4] home: sin ancla de críticos'); return; }
          var card = tarjetaDe(anc);
          for (var i = 0; i < 3 && card.parentElement && card.querySelectorAll('*').length < 12; i++) card = card.parentElement;
          card.innerHTML = '<p style="font:600 18px \'The Seasons\',serif;margin:0 0 10px">Vencimientos críticos</p>' +
            (vs.length ? vs.map(function (v) { return itemPanel(esc(v.descripcion || 'Hito') + ' · ' + esc(v.contratos.numero), fFecha(v.fecha), v.monto ? esc(v.monto) : (v.pct ? esc(v.pct) + ' %' : '—')); }).join('')
                       : '<p style="font:400 13px \'Neue Kabel\',sans-serif;color:#44483f">Ninguno con fecha futura en contratos firmados.</p>') +
            '<a href="/intranet/vencimientos/" style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Abrir tesorería →</a>';
        });
      q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado').eq('estado', 'pendiente'), 'firmas pendientes')
        .then(function (fs2) {
          if (fs2 == null) return;
          var n = {}; fs2.forEach(function (x) { n[x.contrato_id] = 1; });
          var total = Object.keys(n).length;
          var anc = hojaConTexto(/Firmas/i);
          if (!anc) { console.info('[v4] home: sin ancla de firmas'); return; }
          var card = tarjetaDe(anc);
          for (var j = 0; j < 3 && card.parentElement && card.querySelectorAll('*').length < 12; j++) card = card.parentElement;
          card.innerHTML = '<p style="font:600 18px \'The Seasons\',serif;margin:0 0 10px">Firmas pendientes</p>' +
            '<p style="font:700 30px \'Neue Kabel\',sans-serif;margin:0">' + total + '</p>' +
            '<p style="font:400 12px \'Neue Kabel\',sans-serif;color:#8A8474;margin:2px 0 10px">contratos esperando la firma del comprador</p>' +
            '<a href="/intranet/operaciones/?filtro=firma_viva" style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Verlos en Operaciones →</a>';
        });
    },

    contratos: function (sb) {
      var t = tablaPor([/CONTRATO|N[ºU]/, /COMPRADOR/, /TIPO|ESTADO/]);
      q(sb.rpc('contratos_equipo').select('numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,created_at'), 'contratos', t)
        .then(function (cs) {
          if (!cs) return;

          /* KPIs: los cuatro numeros de Stitch (210, 12.4M, 41, 18) eran
             inventados y se leian como reales. Nacen en «—» en el fichero y solo
             los llena la base. Dos etiquetas se reescribieron porque preguntaban
             algo que la base no responde sin mentir: firmado = `bloqueado`, y no
             hay fecha de firma fiable con la que acotar «del mes». */
          var pon = pon2;
          var eur = 0, otras = 0, firmados = 0;
          cs.forEach(function (c) {
            if (c.bloqueado) firmados++;
            if (c.precio_total == null) return;
            if ((c.moneda || 'EUR') === 'EUR') eur += Number(c.precio_total) || 0; else otras++;
          });
          pon('k-activos', String(cs.length));
          pon('k-volumen', fmt(eur, 'EUR'));
          pon('k-firmados', String(firmados));
          pon('k-pendientes', String(cs.length - firmados));
          if (otras) {
            bandaNota('El volumen es SOLO en euros: ' + otras + ' contrato(s) en otra moneda quedan fuera de la suma. ' +
              'No se mezclan monedas — el total saldria en una unidad que no existe.', '#8A6A34');
          }

          if (!cs.length) return;
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
      // esta pantalla de Stitch es un EDITOR de documento, no un listado: el
      // panel en vivo trae las últimas emitidas y la emisión real va a la herramienta
      q(sb.rpc('facturas_equipo').select('id,numero,tipo,cliente_nombre,contrato_numero,total,moneda,anulada,created_at'), 'facturas')
        .then(function (fs) {
          if (fs == null) return;
          var ult = fs.slice().sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 10);
          panelReal('Últimos documentos emitidos (' + fs.length + ' en total)',
            ult.map(function (f) {
              return itemPanel(esc(f.numero) + ' · ' + (f.tipo === 'recibi' ? 'Recibí' : f.tipo === 'proforma' ? 'Proforma' : 'Factura'),
                esc(f.cliente_nombre || '—') + (f.contrato_numero ? ' · ' + esc(f.contrato_numero) : '') + ' · ' + fFecha(f.created_at),
                fmt(f.total, f.moneda) + (f.anulada ? ' · ANULADA' : ''));
            }),
            ult.map(function (f) { return '/intranet/facturas/?id=' + f.id; }),
            'Sin documentos emitidos.', '/intranet/facturas/');
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
      /* El «96% verificados» de Stitch era invencion, y ademas halagadora: el KYC
         real esta casi todo en `pending`. Un porcentaje inventado en una pantalla
         de cumplimiento es de lo peor que puede quedarse en una maqueta. */
      q(sb.from('clients').select('id,full_name,email,nationality,tipo,kyc_status,created_at').order('created_at', { ascending: false }).limit(500), 'compradores', t)
        .then(function (cs) {
          if (!cs) return;
          pon2('k-compradores', String(cs.length));
          var ver = cs.filter(function (c) { return c.kyc_status === 'verified'; }).length;
          pon2('k-verificados', cs.length ? Math.round(ver / cs.length * 100) + '%' : '—');
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
      // lista SIEMPRE pintada (con 0 filas, estado vacío honesto — las tarjetas
      // de la maqueta de abajo no pueden quedarse como única "verdad")
      q(sb.from('contrato_vencimientos')
          .select('descripcion,pct,monto,fecha,contratos!inner(numero,bloqueado)')
          .eq('contratos.bloqueado', true).gte('fecha', hoy).order('fecha').limit(12), 'próximos vencimientos')
        .then(function (vs) {
          if (vs == null) return;
          var items = vs.map(function (v) {
            return itemPanel(esc(v.descripcion || 'Hito') + ' · ' + esc(v.contratos.numero), fFecha(v.fecha),
              v.monto ? esc(v.monto) : (v.pct ? esc(v.pct) + ' %' : '—'));
          });
          panelReal('Próximos vencimientos de contratos firmados', items,
            vs.map(function () { return '/intranet/vencimientos/'; }),
            'Ningún vencimiento con fecha futura en contratos firmados — la cascada de cobros y lo vencido se miran en la herramienta.',
            '/intranet/vencimientos/');
        });
    },

    /* PROYECTOS — rehecha el 7-sep-2026 sobre el diseño de Stitch «Proyectos &
       Estado de Cuentas». Antes anclaba por texto, como el resto de pantallas,
       porque el marcado de Stitch no se podía tocar. Esta pantalla SÍ es
       nuestra: sus campos llevan `data-lw` y aquí se rellenan por selector.
       Buscar por texto era la respuesta correcta a un problema que ya no
       tenemos, y un ancla de texto se rompe el día que alguien cambia una
       etiqueta.

       DOS REGLAS DEL DINERO QUE NO SE PUEDEN RELAJAR:
       1. NO se suman monedas distintas. La cartera se da en EUR y lo que queda
          fuera se DICE en un aviso, no se esconde: hoy 10 unidades en IDR y 45
          sin moneda (LAW-101, pendiente abierto). Sumarlas daría un número que
          parece la cartera y no lo es.
       2. Lo cobrado sale de los RECIBÍS no anulados, que es la fuente que ya usa
          el resto de la suite. Una quinta forma de calcular dinero es una quinta
          forma de que dos pantallas no coincidan. */
    proyectos: function (sb) {
      var $ = function (k, raiz) { return (raiz || document).querySelector('[data-lw="' + k + '"]'); };
      var pon = function (k, v, raiz) { var e = $(k, raiz); if (e) e.textContent = v; };
      // Sin `vaciaKpis` aquí a propósito: en esta pantalla las cifras de Stitch
      // ya se borraron del PROPIO fichero (los `data-lw` nacen en «—»), así que
      // no hay nada que vaciar en caliente. Si la consulta falla, se queda el
      // guion y no un número inventado — que es justo lo que se busca.

      Promise.all([
        q(sb.from('proyectos').select('id,nombre,resort,parcela_master,parcela_master_m2').eq('activo', true).order('nombre'), 'proyectos'),
        q(sb.from('unidades').select('proyecto,estado,moneda,precio,precio_suelo,precio_construccion'), 'unidades'),
        /* La RPC de EQUIPO, nunca `.from('facturas')`. `facturas` tiene RLS por
           agente (`es_suyo`), así que una lectura directa devuelve solo «lo mío»
           —menos filas, sin ningún error— y el cobrado de la cartera saldría
           bajo para todo el que no sea super admin. Está avisado en la cabecera
           de este fichero y aun así caí en ello al escribir esta pantalla. */
        q(sb.rpc('facturas_equipo').select('proyecto_nombre,tipo,total,moneda,anulada'), 'facturas'),
        q(sb.from('documentos_proyecto').select('proyecto'), 'documentación')
      ]).then(function (r) {
        var ps = r[0], us = r[1] || [], fs = r[2] || [], ds = r[3] || [];
        if (!ps) return;

        /* --- agregados, SOLO EUR --- */
        var EUR = function (u) { return (u.moneda || 'EUR') === 'EUR' && u.moneda; };
        var tot = { cartera: 0, suelo: 0, obra: 0 }, fuera = { idr: 0, sin: 0 };
        var porP = {};
        us.forEach(function (u) {
          var k = u.proyecto || '¿?';
          var d = porP[k] = porP[k] || { t: 0, disp: 0, vend: 0, cartera: 0, suelo: 0, obra: 0 };
          d.t++;
          if (u.estado === 'disponible') d.disp++;
          if (u.estado === 'vendida' || u.estado === 'cobrada') d.vend++;
          if (!u.moneda) { fuera.sin++; return; }
          if (u.moneda !== 'EUR') { fuera.idr++; return; }
          tot.cartera += Number(u.precio || 0); tot.suelo += Number(u.precio_suelo || 0); tot.obra += Number(u.precio_construccion || 0);
          d.cartera += Number(u.precio || 0);
        });
        var cobrado = 0, facturado = 0, cobP = {};
        fs.forEach(function (f) {
          if (f.anulada || (f.moneda || 'EUR') !== 'EUR') return;
          if (f.tipo === 'recibi') { cobrado += Number(f.total || 0); var k = f.proyecto_nombre || ''; cobP[k] = (cobP[k] || 0) + Number(f.total || 0); }
          else if (f.tipo === 'factura') facturado += Number(f.total || 0);
        });
        var docP = {}; ds.forEach(function (d) { docP[d.proyecto] = (docP[d.proyecto] || 0) + 1; });

        /* --- KPIs --- */
        pon('k-cartera', fmt(tot.cartera, 'EUR'));
        pon('k-cartera-pie', 'Volumen en ' + ps.length + ' desarrollos activos');
        pon('k-cobrado', fmt(cobrado, 'EUR'));
        pon('k-cobrado-pie', facturado ? (Math.round(cobrado / facturado * 1000) / 10) + '% de lo facturado (' + fmt(facturado, 'EUR') + ')' : 'sin facturas emitidas');
        pon('k-pendiente', fmt(tot.cartera - cobrado, 'EUR'));
        pon('k-pendiente-pie', 'Cartera menos lo cobrado');
        pon('k-suelo-v', fmt(tot.suelo, 'EUR'));
        pon('k-obra', fmt(tot.obra, 'EUR'));
        var base = tot.suelo + tot.obra;
        pon('k-mix-pie', base ? 'Suelo: ' + (Math.round(tot.suelo / base * 1000) / 10) + '% · Construcción: ' + (Math.round(tot.obra / base * 1000) / 10) + '%' : '—');

        /* Lo que la vista NO está sumando se dice. Un aviso que no está es la
           forma más barata de que un número se lea como si lo incluyera todo. */
        if (fuera.idr || fuera.sin) {
          bandaNota('Estas cifras son SOLO en euros. Fuera de la suma: ' +
            (fuera.idr ? fuera.idr + ' unidades en rupias (Riverfront)' : '') +
            (fuera.idr && fuera.sin ? ' y ' : '') +
            (fuera.sin ? fuera.sin + ' unidades sin moneda asignada (pendiente LAW-101)' : '') +
            '. No se mezclan monedas: el total saldría en una unidad que no existe.', '#8A6A34');
        }

        /* --- chips --- */
        pon('p-todos', String(ps.length));
        var ests = { disponible: 0, reservada: 0, bloqueada: 0, vendida: 0, cobrada: 0, no_disponible: 0 };
        us.forEach(function (u) { var e = (u.estado || '').replace(/\s+/g, '_'); if (e in ests) ests[e]++; });
        pon('uds-todas', String(us.length));
        Object.keys(ests).forEach(function (e) { pon('uds-' + e, String(ests[e])); });

        /* --- tarjetas: se siembran del CATÁLOGO, no de las unidades ---
           Agrupar por `unidades.proyecto` pierde todo proyecto sin unidades, y
           justo ése suele ser el que hay que ver, porque es el que falta por
           hacer. Es el fallo que el owner cazó el 26-ago (11 carpetas donde la
           herramienta viva enseña 29). */
        var grid = document.getElementById('projects-grid');
        if (!grid) { console.info('[v4] proyectos: sin #projects-grid'); return; }
        var plantilla = grid.firstElementChild;
        if (!plantilla) { console.info('[v4] proyectos: grid sin plantilla'); return; }
        var molde = plantilla.cloneNode(true);
        grid.innerHTML = '';
        ps.forEach(function (p) {
          var c = molde.cloneNode(true);
          var d = porP[p.nombre] || { t: 0, disp: 0, vend: 0, cartera: 0 };
          var cob = cobP[p.nombre] || 0;
          pon('nombre', p.nombre, c);
          pon('sitio', p.resort || 'Sin ubicación asignada', c);
          pon('sub', p.parcela_master ? 'Parcela máster ' + p.parcela_master + (p.parcela_master_m2 ? ' · ' + p.parcela_master_m2 + ' m²' : '') : 'Sin parcela máster registrada', c);
          pon('badge', d.t === 0 ? 'Sin inventario' : (d.disp ? 'Con disponibles' : 'Todo asignado'), c);
          pon('uds', String(d.t), c);
          pon('vendidas', d.vend + ' vendidas', c);
          pon('disp', d.disp + ' disp.', c);
          pon('cobrado', fmt(cob, 'EUR'), c);
          pon('total', '/ ' + fmt(d.cartera, 'EUR'), c);
          pon('pct', d.cartera ? (Math.round(cob / d.cartera * 1000) / 10) + '% cobrado' : 'sin cartera', c);
          pon('master', p.parcela_master || '—', c);
          var barra = c.querySelector('.bg-fiduciary-green');
          if (barra && barra.style) barra.style.width = (d.cartera ? Math.min(100, cob / d.cartera * 100) : 0) + '%';
          c.style.cursor = 'pointer';
          c.addEventListener('click', function () { location.href = '/intranet/proyectos/?proyecto=' + encodeURIComponent(p.nombre); });
          grid.appendChild(c);
        });

        /* --- cajón de detalle: el proyecto de ?proyecto= o el de más unidades --- */
        var pedido = new URLSearchParams(location.search).get('proyecto');
        var elegido = ps.filter(function (p) { return p.nombre === pedido; })[0] ||
                      ps.slice().sort(function (a, b) { return (porP[b.nombre] || { t: 0 }).t - (porP[a.nombre] || { t: 0 }).t; })[0];
        if (elegido) {
          var d = porP[elegido.nombre] || { t: 0, cartera: 0 }, cob = cobP[elegido.nombre] || 0;
          pon('d-cartera', fmt(d.cartera, 'EUR'));
          pon('d-cobrado', fmt(cob, 'EUR'));
          pon('d-pendiente', fmt(d.cartera - cob, 'EUR'));
          pon('d-pct', d.cartera ? '(' + (Math.round(cob / d.cartera * 1000) / 10) + '%)' : '(—)');
          pon('d-pct2', 'Recaudado ' + (d.cartera ? (Math.round(cob / d.cartera * 1000) / 10) : 0) + '%');
          pon('d-objetivo', 'Cartera ' + fmt(d.cartera, 'EUR'));
          pon('d-master', elegido.parcela_master || 'sin registrar');
          pon('d-sup', elegido.parcela_master_m2 ? elegido.parcela_master_m2 + ' m² (' + d.t + ' parcelas)' : d.t + ' parcelas');
          pon('d-docs', (docP[elegido.nombre] || 0) + ' documentos');
          pon('d-pendiente2', fmt(d.cartera - cob, 'EUR'));
          pon('d-presu', '—');
          var h2 = hojaConTexto(/Master Plan/i);
          if (h2) h2.textContent = elegido.nombre + ' · Master Plan & Cuentas';

          /* La lista de unidades del cajón, con datos reales del proyecto
             elegido. `unidades_estado` es la vista que ya trae el contrato y el
             comprador vinculados — no se vuelve a cruzar aquí a mano. */
          q(sb.from('unidades_estado').select('codigo,modelo,estado,precio,contrato_numero,comprador_nombre')
              .eq('proyecto', elegido.nombre).order('codigo').limit(60), 'unidades de ' + elegido.nombre)
            .then(function (uu) {
              var caja = document.getElementById('d-unidades');
              if (!caja || uu == null) return;
              var molde = caja.firstElementChild;
              if (!molde) return;
              var base = molde.cloneNode(true);
              caja.innerHTML = '';
              pon('d-uds-n', uu.length + (uu.length === 1 ? ' unidad' : ' unidades'));
              if (!uu.length) {
                caja.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">' +
                  'Este proyecto no tiene unidades dadas de alta.</p>';
                return;
              }
              uu.forEach(function (u) {
                var f = base.cloneNode(true);
                pon('u-titulo', u.codigo + (u.comprador_nombre ? ' · ' + u.comprador_nombre : ''), f);
                pon('u-tipo', u.modelo || (u.estado || '—'), f);
                pon('u-total', u.precio != null ? fmt(u.precio, 'EUR') : '—', f);
                // Sin recibí por unidad: el cobro cuelga del CONTRATO, no de la
                // parcela. Se dice cuál es el contrato en vez de inventar un
                // reparto por unidad que la base no respalda.
                pon('u-cobrado', u.contrato_numero || 'sin contrato', f);
                pon('u-nota', (u.estado || '—').toUpperCase(), f);
                caja.appendChild(f);
              });
            });
        }
      });
    },

    'proyectos-cuentas': function (sb) {
      var pedido = new URLSearchParams(location.search).get('proyecto');
      Promise.all([
        q(sb.from('proyectos').select('nombre').order('nombre'), 'proyectos'),
        q(sb.from('unidades_estado').select('proyecto'), 'unidades para elegir proyecto')
      ]).then(function (rr) {
        var ps = rr[0], uu = rr[1] || [];
        if (!ps || !ps.length) return;
        var conteo = {}; uu.forEach(function (u) { conteo[u.proyecto] = (conteo[u.proyecto] || 0) + 1; });
        var mayor = ps.slice().sort(function (x, y) { return (conteo[y.nombre] || 0) - (conteo[x.nombre] || 0); })[0];
        var nombre = pedido || mayor.nombre;
        var h2 = hojaConTexto(/Master Plan|Horizon S1/i); if (h2) h2.textContent = nombre + ' · Master Plan & Cuentas';
        q(sb.from('unidades_estado').select('codigo,modelo,estado,contrato_numero,comprador_nombre').eq('proyecto', nombre).order('codigo').limit(120), 'unidades de ' + nombre)
          .then(function (us) {
            if (us == null) return;
            panelReal('Unidades de ' + nombre + (pedido ? '' : ' (primer proyecto por orden — abre otro con ?proyecto=)'),
              us.map(function (u) {
                return itemPanel(esc(u.codigo) + ' · ' + esc(u.modelo || '—'),
                  (u.contrato_numero ? esc(u.contrato_numero) + ' · ' : '') + esc(u.comprador_nombre || 'sin comprador'),
                  (u.estado || '—').toUpperCase());
              }),
              us.map(function () { return '/intranet/proyectos/?proyecto=' + encodeURIComponent(nombre); }),
              'Este proyecto no tiene unidades dadas de alta.', '/intranet/proyectos/?proyecto=' + encodeURIComponent(nombre));
          });
      });
    },

    obra: function (sb) {
      vaciaKpis([/EN OBRA|ACTIVAS/i]);
      q(sb.from('unidades_estado').select('codigo,proyecto,modelo,obra_fase,obra_fecha_entrega,comprador_nombre').not('obra_fase', 'is', null).order('obra_actualizado', { ascending: false }).limit(60), 'obra')
        .then(function (us) {
          if (us == null) return;
          kpi(/EN OBRA|ACTIVAS/i, String(us.length), 'unidades con fase abierta');
          panelReal('Unidades en obra', us.map(function (u) {
            return itemPanel(esc(u.codigo) + ' · ' + esc(u.proyecto || ''),
              esc(u.modelo || '—') + ' · ' + esc(u.comprador_nombre || 'sin comprador') + ' · entrega ' + fFecha(u.obra_fecha_entrega),
              esc(u.obra_fase || '—'));
          }), us.map(function () { return '/intranet/obra/'; }),
          'Ninguna unidad con fase de obra abierta.', '/intranet/obra/');
        });
    },

    documentacion: function (sb) {
      vaciaKpis([/EXPEDIENTES|DOCUMENTOS/i]);
      q(sb.from('documentos_proyecto').select('proyecto'), 'documentación').then(function (ds) {
        if (!ds) return;
        var porP = {}; ds.forEach(function (d) { porP[d.proyecto] = (porP[d.proyecto] || 0) + 1; });
        pon2('k-docs', String(ds.length));
        // «100% convalidados» no sale de ningun sitio: la boveda no guarda estado
        // de convalidacion. Guion y motivo, nunca un porcentaje que suene bien.
        pon2('k-convalidados', '—');
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
        pon2('k-usuarios', String(act.length));
        var roles = {}; us.forEach(function (u) { if (u.rol) roles[u.rol] = 1; });
        pon2('k-roles', String(Object.keys(roles).length));
        /* Estas dos tarjetas de Stitch preguntan por datos que la suite NO guarda.
           Se quedan en «—» con el motivo escrito: un numero plausible aqui es
           exactamente el fallo que trajo el fideicomiso a las otras doce pantallas. */
        pon2('k-notarial', '—');
        pon2('k-2fa', '—');
        bandaNota('«Supervision notarial» y «Autenticacion 2FA» se quedan en «—» a proposito: ' +
          'la suite no guarda ninguno de esos dos datos, asi que cualquier cifra ahi seria inventada.', '#8A6A34');
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
        pon2('k-abiertos', String(abiertos));
        pon2('k-whatsapp', '—');
        pon2('k-satisfaccion', '—');
        bandaNota('«Canal WhatsApp» y «Satisfaccion cliente» se quedan en «—»: no hay ninguna ' +
          'medida de eso en la base. El 94% y el 9,8 que habia eran del diseno, no datos.', '#8A6A34');
        kpi(/ABIERTOS|TICKETS/i, String(abiertos), 'de ' + hs.length + ' hilos');
        var chip = hojaConTexto(/^Todos\b/i); if (chip) chip.textContent = 'Todos (' + hs.length + ')';
        panelReal('Hilos de soporte', hs.map(function (h) {
          return itemPanel(esc(nom[h.client_id] || 'Cliente'), esc(h.categoria || 'general') + ' · ' + fFecha(h.actualizado_en),
            (h.estado || '—').toUpperCase());
        }), hs.map(function (h) { return '/intranet/soporte/?id=' + h.client_id; }),
        'Ningún hilo de soporte todavía.', '/intranet/soporte/');
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

      /* La topbar enseñaba un nombre REAL del equipo hardcodeado por Stitch
         (venía copiado de las capturas). El usuario de sesión se pinta aquí,
         nunca en el HTML: este repo es público. */
      var quien = (aut.ficha && aut.ficha.nombre) ||
                  ((aut.session && aut.session.user && aut.session.user.email || '').split('@')[0]) || 'Sesión activa';
      var rol = (aut.ficha && aut.ficha.rol) || '—';
      document.querySelectorAll('[data-lw-user]').forEach(function (e) { e.textContent = quien; });
      document.querySelectorAll('[data-lw-rol]').forEach(function (e) { e.textContent = rol; });

      /* La campana marcaba «18» en las 18 pantallas: un numero de Stitch. Aqui se
         cuentan los HECHOS reales de `notificaciones` posteriores al ultimo visto.
         La campana viva (topbar.js) suma ademas alertas derivadas de facturas y
         firmas; NO se replican aqui — al graduar la v4 la barra se comparte, no se
         copia (Regla 0 de contexto/suite_lawang.md). */
      var desde = (aut.ficha && aut.ficha.notif_visto_hasta) || '1970-01-01T00:00:00Z';
      aut.sb.from('notificaciones').select('id', { count: 'exact', head: true })
        .gt('creado_en', desde)
        .then(function (r) {
          var v = r.error ? '—' : String(r.count || 0);
          if (r.error) console.error('[v4 datos] avisos:', r.error);
          document.querySelectorAll('[data-lw="k-avisos"]').forEach(function (e) { e.textContent = v; });
        });
      var fn = REG[seg];
      if (fn) { try { fn(aut.sb); } catch (e) { fallo('pantalla ' + seg, e); } }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
