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
      '<p style="font:600 20px \'Neue Kabel\',sans-serif;color:#314322;margin:0 0 10px">' + esc(titulo) + '</p>' +
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
        pon2('k-contratos', String(cs.length));
        pon2('k-encurso', String(cs.length - firmados));
        pon2('k-firmados-pie', firmados + ' firmados');
      });
      q(sb.rpc('facturas_equipo').select('tipo,total,moneda,anulada,created_at,numero,cliente_nombre,proyecto_nombre'), 'facturas').then(function (fs) {
        if (!fs) return;
        var s = sumaMesEUR(fs.filter(function (f) { return f.tipo === 'recibi'; }));
        kpi(/COBRADO ESTE MES/i, fmt(s.eur, 'EUR'), s.otros ? '+' + s.otros + ' cobros en otra moneda' : 'recibís del mes en curso');
        pon2('k-cobrado', fmt(s.eur, 'EUR'));
        /* «+18,4% vs mes anterior» era del diseno. Se calcula de verdad, y si no
           hay con que comparar se dice, en vez de ensenar una flecha verde. */
        var ini = new Date(); ini.setDate(1); ini.setHours(0, 0, 0, 0);
        var iniPrev = new Date(ini); iniPrev.setMonth(iniPrev.getMonth() - 1);
        var prev = 0;
        fs.forEach(function (f) {
          if (f.tipo !== 'recibi' || f.anulada || (f.moneda || 'EUR') !== 'EUR') return;
          var d = new Date(f.created_at);
          if (d >= iniPrev && d < ini) prev += Number(f.total) || 0;
        });
        // el «vs mes anterior» lo pone la propia tarjeta: aqui solo va la cifra
        pon2('k-cobrado-tend', prev ? ((s.eur >= prev ? '+' : '') + Math.round((s.eur - prev) / prev * 1000) / 10 + '%') : '—');
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
        .then(function (n) {
          if (n == null) return;
          kpi(/VENCIMIENTOS/i, String(n), 'con fecha en los próximos 30 días');
          pon2('k-operaciones', String(n));   // la tarjeta es «Vencimientos (30 días)»
        });
      /* 'libre' NO es un estado de `unidades` — el real es 'disponible'. Esta
         consulta llevaba devolviendo cero desde el 4-sep sin dar ningun error, y
         el KPI ensenaba «0 unidades libres» sobre un inventario lleno. Es la
         misma familia que la RLS que recorta sin avisar: la respuesta vacia se
         lee igual que la respuesta correcta. */
      Promise.all([
        cnt(sb, 'unidades'),
        cnt(sb, 'unidades', function (x) { return x.eq('estado', 'disponible'); }),
        cnt(sb, 'unidades', function (x) { return x.eq('estado', 'reservada'); })
      ]).then(function (r) {
        if (r[1] == null) return;
        kpi(/UNIDADES LIBRES/i, String(r[1]), r[0] != null ? 'disponibles de ' + r[0] + ' en inventario' : null);
        pon2('k-unidades', String(r[1]));
        pon2('k-unidades-sub', r[0] != null ? 'de ' + r[0] + ' parcelas' : 'en inventario');
        pon2('k-reservadas', r[2] != null ? String(r[2]) : '—');
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
          card.innerHTML = '<p style="font:600 18px \'Neue Kabel\',sans-serif;margin:0 0 10px">Vencimientos críticos</p>' +
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
          card.innerHTML = '<p style="font:600 18px \'Neue Kabel\',sans-serif;margin:0 0 10px">Firmas pendientes</p>' +
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

          /* drawer de previsualizacion: cabecera real del contrato elegido
             (?contrato= o el ultimo). La minuta renderizada es fase de editores:
             el boton Editar lleva al generador real mientras tanto. */
          var pedido = new URLSearchParams(location.search).get('contrato');
          var elg = cs.filter(function (c) { return c.numero === pedido; })[0] ||
                    cs.slice().sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; })[0];
          if (elg) {
            pon2('dw-num', 'Minuta ' + elg.numero);
            pon2('dw-estado', elg.bloqueado ? 'Firmado' : 'Borrador');
            pon2('dw-tipo', tipoC(elg.tipo) + (elg.proyecto_nombre ? ' · ' + elg.proyecto_nombre : ''));
            var be = document.querySelectorAll('button');
            for (var i4 = 0; i4 < be.length; i4++) {
              if (/Editar Minuta/i.test(be[i4].textContent || '')) {
                (function (num) { be[i4].addEventListener('click', function () { location.href = '/contracts/app.html?contrato=' + encodeURIComponent(num); }); })(elg.numero);
              }
            }
          }
          if (otras) {
            bandaNota('El volumen es SOLO en euros: ' + otras + ' contrato(s) en otra moneda quedan fuera de la suma. ' +
              'No se mezclan monedas — el total saldria en una unidad que no existe.', '#8A6A34');
          }

          if (!cs.length) return;
          var chip = hojaConTexto(/^Todos\b/i); if (chip) chip.textContent = 'Todos ' + cs.length;
          if (!t) { console.info('[v4] contratos: tabla sin ancla'); return; }
          var pl = plantillaFilas(t);
          var pintadas = Math.min(cs.length, 120);
          pon2('p-desde', pintadas ? '1-' + pintadas : '0');
          pon2('p-total', String(cs.length));   // el pie decia «de 210», fijo
          cs.sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 120).forEach(function (c) {
            fila(pl, [c.numero, tipoC(c.tipo), c.comprador_nombre || '—', c.proyecto_nombre || '—',
              c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—',
              c.bloqueado ? 'FIRMADO' : 'BORRADOR', fFecha(c.created_at)],
              '/contracts/app.html?contrato=' + encodeURIComponent(c.numero));
          });
        });
    },

    facturas: function (sb) {
      /* Esta pantalla de Stitch es el EDITOR de emision: cablearlo a escribir es
         la fase de editores (mismas vias que la herramienta viva, con encadenado
         y anulacion — emitir un recibi ademas mueve el estado del contrato). Lo
         que ya es real aqui: el panel de emitidos y el selector de contratos. */
      bandaNota('El formulario de abajo es diseño todavía: la emisión real (con validaciones, encadenado y numeración) vive en /intranet/facturas/ hasta que el editor v4 esté cableado.', '#8A6A34');
      q(sb.rpc('contratos_equipo').select('numero,comprador_nombre,created_at'), 'contratos para el selector').then(function (cs2) {
        if (!cs2 || !cs2.length) return;
        var sels = document.querySelectorAll('select');
        for (var i5 = 0; i5 < sels.length; i5++) {
          if (/CC00082|COMPRADOR/.test(sels[i5].textContent || '')) {
            sels[i5].innerHTML = cs2.sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 40)
              .map(function (c) { return '<option>' + esc(c.numero + ' · ' + (c.comprador_nombre || '')) + '</option>'; }).join('');
            break;
          }
        }
      });
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
          var pintadas = Math.min(rs.length, 120);
          pon2('p-desde', String(pintadas));    // el pie decia «Mostrando 5 de 16»
          pon2('p-total', String(rs.length));
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
      /* Directorio completo (fase A3). La inversion NO suma contratos
         preliminares (lwEsPreliminar): la Carta reparte el mismo precio que su
         Bloqueo y sumarla cuenta la villa dos veces — la regla es de
         vocabulario.js, no de aqui. El aviso Ficha≠ viene de la vista
         documentos_desactualizados, igual que en la herramienta viva. */
      var t = tablaPor([/INVERSOR|TITULAR/, /CONTACTO|PA[IÍ]S/]);
      Promise.all([
        q(sb.from('clients').select('id,full_name,email,phone,nationality,tipo,kyc_status,created_at').order('created_at', { ascending: false }).limit(500), 'compradores', t),
        q(sb.rpc('contratos_equipo').select('id,tipo,precio_total,moneda,bloqueado'), 'contratos'),
        q(sb.from('contrato_compradores').select('contrato_id,client_id'), 'vinculos'),
        sb.rpc('contratos_cobrado_equipo').then(function (r) { return r.error ? (fallo('cobrado', r.error), null) : (r.data || []); }),
        q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado').eq('estado', 'pendiente'), 'firmas'),
        q(sb.from('documentos_desactualizados').select('congelado,diferencias').limit(1000), 'ficha≠')
      ]).then(function (r) {
        var cs = r[0], cts = r[1] || [], vin = r[2] || [], cob = r[3] || [], fir = r[4] || [], div = r[5] || [];
        if (!cs) return;
        var esPre = function (tp) { return (typeof lwEsPreliminar === 'function') && lwEsPreliminar(tp); };
        var porC = {}; cts.forEach(function (c2) { porC[c2.id] = c2; });
        var cobId = {}; cob.forEach(function (x) { cobId[x.contrato_id] = Number(x.cobrado) || 0; });
        var firmaPend = {}; fir.forEach(function (x) { firmaPend[x.contrato_id] = 1; });
        var deCliente = {};
        vin.forEach(function (v) {
          var c2 = porC[v.contrato_id]; if (!c2) return;
          var d = deCliente[v.client_id] = deCliente[v.client_id] || { inv: 0, pag: 0, otras: 0, n: 0, firma: 0 };
          d.n++;
          if (firmaPend[v.contrato_id]) d.firma++;
          if ((c2.moneda || 'EUR') !== 'EUR') { d.otras++; }
          else {
            if (!esPre(c2.tipo)) d.inv += Number(c2.precio_total) || 0;
            d.pag += cobId[v.contrato_id] || 0;
          }
        });

        pon2('k-compradores', String(cs.length));
        var ver = cs.filter(function (c2) { return c2.kyc_status === 'verified'; }).length;
        pon2('k-verificados', cs.length ? Math.round(ver / cs.length * 100) + '%' : '—');
        pon2('k-verificados-pie', ver + ' de ' + cs.length + ' con KYC verificado');
        var q0 = new Date(); q0.setMonth(Math.floor(q0.getMonth() / 3) * 3, 1); q0.setHours(0, 0, 0, 0);
        var nuevos = cs.filter(function (c2) { return new Date(c2.created_at) >= q0; }).length;
        pon2('k-nuevos', '+' + nuevos + ' este trimestre');
        var capital = 0, pagado = 0, fueraEur = 0;
        Object.keys(deCliente).forEach(function (k) { capital += deCliente[k].inv; pagado += deCliente[k].pag; fueraEur += deCliente[k].otras; });
        pon2('k-capital', fmt(capital, 'EUR'));
        pon2('k-capital-chip', capital ? Math.round(pagado / capital * 100) + '% cobrado' : 'sin contratos EUR');
        if (fueraEur) bandaNota('El capital es SOLO en euros: ' + fueraEur + ' contrato(s) en otra moneda quedan fuera de la suma.', '#8A6A34');

        // nacionalidades reales, no las cuatro del diseno
        var nacs = {}; cs.forEach(function (c2) { if (c2.nationality) nacs[c2.nationality] = (nacs[c2.nationality] || 0) + 1; });
        var caja = document.getElementById('nacs');
        if (caja && caja.firstElementChild) {
          var moldeN = caja.firstElementChild.cloneNode(true);
          caja.innerHTML = '';
          Object.keys(nacs).sort(function (a, b) { return nacs[b] - nacs[a]; }).slice(0, 4).forEach(function (k) {
            var e = moldeN.cloneNode(true); e.textContent = k + ' · ' + nacs[k]; caja.appendChild(e);
          });
        }

        var conContrato = cs.filter(function (c2) { return deCliente[c2.id]; });
        var enFirma = cs.filter(function (c2) { return deCliente[c2.id] && deCliente[c2.id].firma; });
        pon2('cc-todos', 'Todos (' + cs.length + ')');
        pon2('cc-contrato', 'Con contrato (' + conContrato.length + ')');
        pon2('cc-firma', 'En firma (' + enFirma.length + ')');
        pon2('cc-prospectos', 'Sin contrato (' + (cs.length - conContrato.length) + ')');

        // Ficha≠: el control de divergencia de la suite, no puede perderse aqui
        var difN = div.filter(function (x) { return x.diferencias && x.diferencias.length; }).length;
        if (difN) bandaNota('Ficha ≠: ' + difN + ' documento(s) emitidos difieren de la ficha del comprador — el detalle vive en la herramienta (/intranet/compradores/).', '#C06C47');

        if (!t) return;
        var pl = plantillaFilas(t);
        cs.slice(0, 200).forEach(function (c2) {
          var d = deCliente[c2.id];
          fila(pl, [
            c2.full_name,
            (c2.email || '—') + (c2.nationality ? ' · ' + c2.nationality : ''),
            c2.tipo === 'empresa' ? 'Empresa' : 'Persona física',
            d ? d.n + (d.n === 1 ? ' contrato' : ' contratos') : '—',
            d && d.inv ? fmt(d.inv, 'EUR') : (d && d.otras ? 'otra moneda' : '—'),
            d && d.inv ? fmt(d.pag, 'EUR') + ' · ' + Math.round(d.pag / d.inv * 100) + '%' : (d ? fmt(d.pag, 'EUR') : '—'),
            c2.kyc_status === 'verified' ? 'KYC VERIFICADO' : 'KYC PENDIENTE',
            ''
          ], '/intranet/compradores/?id=' + c2.id);
        });
      });
    },
    operaciones: function (sb) {
      var t = tablaPor([/OPERACI|CONTRATO/, /COMPRADOR/, /IMPORTE|ESTADO/]);
      Promise.all([
        q(sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,contrato_padre_id,created_at'), 'operaciones', t),
        sb.rpc('contratos_cobrado_equipo').then(function (r) { return r.error ? (fallo('cobrado', r.error), null) : (r.data || []); }),
        q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado').eq('estado', 'pendiente'), 'firmas pendientes')
      ]).then(function (r) {
        var cs = r[0], cob = r[1] || [], fi = r[2] || [];
        if (!cs) return;
        var cobId = {}; cob.forEach(function (x) { cobId[x.contrato_id] = Number(x.cobrado) || 0; });
        var chip = hojaConTexto(/^Todas\b/i); if (chip) chip.textContent = 'Todas (' + cs.length + ')';
        var eur = 0, otras = 0;
        cs.forEach(function (c) {
          if (c.precio_total == null) return;
          if ((c.moneda || 'EUR') === 'EUR') eur += Number(c.precio_total) || 0; else otras++;
        });
        pon2('k-volumen', fmt(eur, 'EUR'));
        if (otras) bandaNota('El volumen es SOLO en euros: ' + otras + ' contrato(s) en otra moneda fuera de la suma.', '#8A6A34');
        pon2('k-escrow', '—');
        var cobT = 0; cob.forEach(function (x) { cobT += Number(x.cobrado) || 0; });
        pon2('k-cobros', fmt(cobT, 'EUR'));
        var nf = {}; fi.forEach(function (x) { nf[x.contrato_id] = 1; });
        pon2('k-firmas', String(Object.keys(nf).length));

        if (t) {
          var pl = plantillaFilas(t);
          cs.slice().sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 120).forEach(function (c) {
            fila(pl, [c.numero, tipoC(c.tipo), c.comprador_nombre || '—', c.proyecto_nombre || '—',
              c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—',
              c.bloqueado ? 'FIRMADO' : 'EN CURSO', fFecha(c.created_at)],
              '/intranet/operaciones/?contrato=' + encodeURIComponent(c.numero));
          });
        }

        /* --- EXPEDIENTE: ?contrato= o el mas reciente. El «notario con acta» y
           el «cobro SWIFT» del diseno eran inventados: el timeline real son los
           vencimientos del contrato, y la estructura encadenada es la de verdad
           (contrato_padre_id), con el cobrado de cada pieza. */
        var pedido = new URLSearchParams(location.search).get('contrato');
        var el = cs.filter(function (c) { return c.numero === pedido; })[0] ||
                 cs.slice().sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; })[0];
        if (!el) return;
        var raiz = el.contrato_padre_id ? (cs.filter(function (c) { return c.id === el.contrato_padre_id; })[0] || el) : el;
        var hijos = cs.filter(function (c) { return c.contrato_padre_id === raiz.id; });
        pon2('x-id', 'Expediente');
        pon2('x-num', raiz.numero);
        pon2('x-sub', (raiz.comprador_nombre || '—') + (raiz.proyecto_nombre ? ' · ' + raiz.proyecto_nombre : ''));
        var totalCadena = 0, monEl = raiz.moneda || 'EUR';
        [raiz].concat(hijos).forEach(function (c) {
          if ((c.moneda || 'EUR') === monEl && !(typeof lwEsPreliminar === 'function' && lwEsPreliminar(c.tipo))) totalCadena += Number(c.precio_total) || 0;
        });
        pon2('x-total', 'Total: ' + fmt(totalCadena, monEl));
        var pinta = function (pref, c) {
          if (!c) {
            pon2(pref + '-titulo', 'Sin contrato encadenado');
            pon2(pref + '-sub', 'esta operación es de una sola pieza');
            pon2(pref + '-importe', '');
            return;
          }
          pon2(pref + '-titulo', c.numero + ' · ' + tipoC(c.tipo));
          var cb2 = cobId[c.id] || 0;
          pon2(pref + '-sub', 'Cobrado ' + fmt(cb2, c.moneda) + (c.precio_total != null ? ' / ' + fmt(c.precio_total, c.moneda) : ''));
          pon2(pref + '-importe', c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—');
        };
        pinta('e1', raiz);
        pinta('e2', hijos[0]);
        if (hijos.length > 1) bandaNota('La cadena de ' + raiz.numero + ' tiene ' + hijos.length + ' contratos colgando; aquí se enseña el primero. La cadena completa vive en la herramienta (/intranet/operaciones/).', '#485B37');

        q(sb.from('contrato_vencimientos').select('descripcion,pct,monto,fecha,nota').eq('contrato_id', el.id).order('fecha', { ascending: true, nullsFirst: false }).limit(3), 'hitos del expediente')
          .then(function (vs) {
            if (vs == null) return;
            for (var i2 = 0; i2 < 3; i2++) {
              var v = vs[i2];
              pon2('h' + (i2 + 1) + '-t', v ? (v.descripcion || 'Hito ' + (i2 + 1)) : '—');
              pon2('h' + (i2 + 1) + '-s', v ? (v.monto ? String(v.monto) : (v.pct ? v.pct + ' %' : (v.nota || '—'))) : 'sin más hitos');
              pon2('h' + (i2 + 1) + '-f', v ? (v.fecha ? fFecha(v.fecha) : 'sin fecha') : '');
            }
          });

        // los dos botones del cajon llevan a las herramientas reales
        var botones = document.querySelectorAll('button');
        for (var i3 = 0; i3 < botones.length; i3++) {
          var tx = (botones[i3].textContent || '').trim();
          if (/Emitir recib/i.test(tx)) {
            (function (num) { botones[i3].addEventListener('click', function () { location.href = '/intranet/facturas/?contrato=' + encodeURIComponent(num); }); })(el.numero);
          } else if (/proforma encadenada|Abrir proforma/i.test(tx)) {
            (function (num) { botones[i3].addEventListener('click', function () { location.href = '/contracts/app.html?contrato=' + encodeURIComponent(num); }); })(raiz.numero);
          }
        }
      });
    },
    vencimientos: function (sb) {
      /* Cuerpo REAL (fase A, 8-sep). La aritmetica no se rehace: la pagina carga
         intranet/vencimientos/logica.js — el modulo puro y testeado que la suite
         extrajo el 18-ago para que ninguna pantalla reinvente la cascada — y aqui
         solo se llama a modeloFinanciero() y se pinta. Manda el monto escrito;
         sin monto, el pct sobre el precio; sin ninguno, null (nunca 0). */
      if (typeof modeloFinanciero !== 'function') {
        fallo('vencimientos', 'logica.js no cargada: el cuerpo se queda en maqueta');
        return;
      }
      var hoy = new Date().toISOString().slice(0, 10);
      Promise.all([
        q(sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,contrato_padre_id,created_at').limit(1000), 'contratos'),
        sb.rpc('contratos_cobrado_equipo').then(function (r) { if (r.error) { fallo('cobrado', r.error); return null; } return r.data || []; }),
        q(sb.from('contrato_vencimientos').select('id,contrato_id,orden,descripcion,pct,monto,fecha,ajustado,nota,factura_id,no_facturar').limit(3000), 'vencimientos')
      ]).then(function (r) {
        var cs = r[0], cb = r[1], vs = r[2];
        if (!cs || !vs) return;
        var cobradoPorId = {};
        (cb || []).forEach(function (x) { cobradoPorId[x.contrato_id] = Number(x.cobrado) || 0; });
        var MOD = modeloFinanciero({ hoyISO: hoy, contratos: cs, cobradoPorId: cobradoPorId, vencimientos: vs, incluirSinFirmar: false });
        var monedas = Object.keys(MOD).sort(function (a, b) { return MOD[b].cartera - MOD[a].cartera; });
        var mon = monedas[0] || 'EUR';
        var m = MOD[mon] || { filas: [], vencido: 0, proximos30: 0, nSinFecha: 0 };
        var dias = function (f) { return Math.round((new Date(f) - new Date(hoy)) / 864e5); };

        pon2('k-prevision', fmt(m.proximos30, mon));
        pon2('k-prevision-chip', 'con fecha en los próximos 30 días');
        var d7 = new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10);
        var semana = m.filas.filter(function (f) { return f.estado !== 'vencido' && f.estado !== 'cobrado' && f.fecha && f.fecha >= hoy && f.fecha <= d7; });
        var sumaCrit = semana.reduce(function (a, f) { return a + (f.pendiente != null ? f.pendiente : (f.importe || 0)); }, 0);
        pon2('k-criticos', semana.length + (semana.length === 1 ? ' cobro' : ' cobros'));
        pon2('k-criticos-total', 'Total: ' + fmt(sumaCrit, mon));
        var venc = m.filas.filter(function (f) { return f.estado === 'vencido'; })
          .sort(function (a, b) { return (a.fecha || '') < (b.fecha || '') ? -1 : 1; });
        var nCon = {}; venc.forEach(function (f) { nCon[f.contrato_id] = 1; });
        var nc = Object.keys(nCon).length;
        pon2('k-vencidos-n', nc + (nc === 1 ? ' contrato' : ' contratos'));
        pon2('k-vencidos-total', 'Total: ' + fmt(m.vencido, mon));
        pon2('k-vencidos-chip', venc.length ? 'el más antiguo, del ' + fFecha(venc[0].fecha) : 'nada vencido');
        /* La suite no lleva el saldo de la cuenta del notario — lleva lo COBRADO,
           que no es lo mismo: el escrow también se libera. Guion a propósito. */
        pon2('k-escrow', '—');

        var avisos = [];
        if (m.nSinFecha) avisos.push(m.nSinFecha + ' vencimiento(s) sin fecha, que no se pueden vigilar');
        if (monedas.length > 1) avisos.push('cifras SOLO en ' + mon + ' — hay cartera también en ' + monedas.slice(1).join(', ') + ' y no se mezclan monedas');
        if (avisos.length) bandaNota('Vigilancia: ' + avisos.join(' · ') + '. La cascada completa, el aging y la vista por proyecto viven en la herramienta (/intranet/vencimientos/).', '#8A6A34');

        var caja = document.getElementById('lista-vencidos');
        if (!caja || !caja.firstElementChild) { console.info('[v4] vencimientos: sin molde'); return; }
        var molde = caja.firstElementChild.cloneNode(true);
        // los botones del mock («Reactivar enlace», «Aviso urgente») no existen
        // como funcion real: un boton que miente es peor que ninguno
        molde.querySelectorAll('button').forEach(function (b) { b.remove(); });

        var chipDe = function (f) {
          if (f.estado === 'vencido') { var d = -dias(f.fecha); return 'Vencido hace ' + d + (d === 1 ? ' día' : ' días'); }
          if (f.estado === 'parcial') return 'Parcial';
          if (f.estado === 'sin_fecha') return 'Sin fecha';
          if (f.fecha) { var e = dias(f.fecha); return e === 0 ? 'Vence hoy' : 'Vence en ' + e + (e === 1 ? ' día' : ' días'); }
          return 'Pendiente';
        };
        var notaDe = function (f) {
          if (f.nota) return f.nota;
          if (f.estado === 'parcial' && f.cubierto) return 'Cubierto ' + fmt(f.cubierto, mon) + ' de ' + fmt(f.importe, mon);
          if (f.estado === 'vencido') return 'Pendiente de cobro';
          return f.contrato && f.contrato.bloqueado ? 'Contrato firmado' : 'Contrato en borrador';
        };
        var pinta = function (listaId, filas) {
          var c2 = document.getElementById(listaId);
          if (!c2) return;
          c2.innerHTML = '';
          if (!filas.length) {
            c2.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0;padding:4px 2px">Nada en este tramo. Que siga así.</p>';
            return;
          }
          filas.slice(0, 10).forEach(function (f) {
            var fila2 = molde.cloneNode(true);
            var pon3 = function (k, v) { var e = fila2.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v; };
            pon3('v-titulo', (f.descripcion || 'Hito') + ' · ' + (f.contrato.numero || 'sin nº'));
            pon3('v-chip', chipDe(f));
            pon3('v-desc', tipoC(f.contrato.tipo) + (f.contrato.proyecto_nombre ? ' · ' + f.contrato.proyecto_nombre : '') + (f.contrato.comprador_nombre ? ' · ' + f.contrato.comprador_nombre : ''));
            pon3('v-importe', f.pendiente != null ? fmt(f.pendiente, mon) : (f.importe != null ? fmt(f.importe, mon) : '—'));
            pon3('v-nota', notaDe(f));
            fila2.style.cursor = 'pointer';
            fila2.addEventListener('click', function () { location.href = '/intranet/vencimientos/'; });
            c2.appendChild(fila2);
          });
          if (filas.length > 10) {
            c2.insertAdjacentHTML('beforeend', '<p style="font:500 12px/1.4 sans-serif;color:#8A8474;margin:2px 0 0;padding:0 2px">y ' + (filas.length - 10) + ' más en la herramienta completa.</p>');
          }
        };
        var prox = m.filas.filter(function (f) { return f.estado !== 'vencido' && f.estado !== 'cobrado' && f.fecha && f.fecha > d7 && dias(f.fecha) <= 60; })
          .sort(function (a, b) { return a.fecha < b.fecha ? -1 : 1; });
        pon2('n-vencidos', venc.length + (venc.length === 1 ? ' VENCIDO' : ' VENCIDOS'));
        pon2('n-semana', semana.length + ' EN 7 DÍAS');
        pon2('n-prox', prox.length + ' EN CALENDARIO');
        pinta('lista-vencidos', venc);
        pinta('lista-semana', semana.sort(function (a, b) { return a.fecha < b.fecha ? -1 : 1; }));
        pinta('lista-prox', prox);
      });
    },
    proyectos: function (sb) {
      var $ = function (k, raiz) { return (raiz || document).querySelector('[data-lw="' + k + '"]'); };
      var pon = function (k, v, raiz) { var e = $(k, raiz); if (e) e.textContent = v; };
      // Sin `vaciaKpis` aquí a propósito: en esta pantalla las cifras de Stitch
      // ya se borraron del PROPIO fichero (los `data-lw` nacen en «—»), así que
      // no hay nada que vaciar en caliente. Si la consulta falla, se queda el
      // guion y no un número inventado — que es justo lo que se busca.

      /* --- estado del listado (búsqueda + los 2 ejes de chip + página) ---
         11-sep-2026: antes eran TRES mecanismos sueltos que se pisaban entre sí
         (un script de Stitch que buscaba sobre nodos que datos.js ya había
         reemplazado — no filtraba nada — y unos chips que solo pintaban su
         propio contador sin filtrar la rejilla). Ahora hay un único estado y
         un único render: cualquier control cambia el estado y llama a
         renderizar(), que es quien decide qué tarjetas tocan en esta página. */
      var PAGE_SIZE = 9;
      var EST = { q: '', chipP: 'todos', chipU: 'todas', pag: 1 };
      var PS = [], POR_P = {}, COB_P = {}, DOC_P = {}, EQUIPO_NOMBRE = {}, MGRS = [];
      var MOLDE = null;

      function proyectosFiltrados() {
        return PS.filter(function (p) {
          var d = POR_P[p.nombre] || { t: 0, disp: 0, porEstado: {} };
          if (EST.chipP === 'comercializacion' && !(d.t && d.disp)) return false;
          if (EST.chipP === 'completados' && !(d.t && !d.disp)) return false;
          if (EST.chipP === 'estudio' && d.t) return false;
          if (EST.chipU !== 'todas' && !((d.porEstado || {})[EST.chipU] > 0)) return false;
          if (EST.q) {
            var hay = (p.nombre || '').toLowerCase().indexOf(EST.q) !== -1 ||
                      (p.resort || '').toLowerCase().indexOf(EST.q) !== -1;
            if (!hay) return false;
          }
          return true;
        });
      }

      /* Cajón de detalle de UN proyecto — antes solo corría una vez, al cargar
         (el de la URL o el de más unidades). Ahora es una función que cualquier
         tarjeta puede invocar: abre SU proyecto, no el que cargó primero. */
      function abrirCajon(nombre, opts) {
        opts = opts || {};
        var elegido = PS.filter(function (p) { return p.nombre === nombre; })[0];
        if (!elegido) return;
        window.LW_V4 = window.LW_V4 || {};
        window.LW_V4.proyecto = elegido; window.LW_V4.managers = MGRS; window.LW_V4.equipoNombre = EQUIPO_NOMBRE;
        var d = POR_P[elegido.nombre] || { t: 0, cartera: 0 }, cob = COB_P[elegido.nombre] || 0;
        pon('d-cartera', fmt(d.cartera, 'EUR'));
        pon('d-cobrado', fmt(cob, 'EUR'));
        pon('d-pendiente', fmt(d.cartera - cob, 'EUR'));
        pon('d-pct', d.cartera ? '(' + (Math.round(cob / d.cartera * 1000) / 10) + '%)' : '(—)');
        pon('d-pct2', 'Recaudado ' + (d.cartera ? (Math.round(cob / d.cartera * 1000) / 10) : 0) + '%');
        pon('d-objetivo', 'Cartera ' + fmt(d.cartera, 'EUR'));
        pon('d-master', elegido.parcela_master || 'sin registrar');
        pon('d-sup', elegido.parcela_master_m2 ? elegido.parcela_master_m2 + ' m² (' + d.t + ' parcelas)' : d.t + ' parcelas');
        pon('d-docs', (DOC_P[elegido.nombre] || 0) + ' documentos');

        /* Managers de este proyecto (11-sep-2026) — quién es el encargado,
           pintado como chips de solo lectura; asignar/desasignar es una
           escritura y vive en editores.js, con su propio gate de permiso. */
        var cajaM = document.getElementById('d-managers');
        if (cajaM) {
          var supervisan = MGRS.filter(function (m) { return (m.proyectos_supervisados || []).indexOf(elegido.id) !== -1; });
          cajaM.innerHTML = supervisan.length
            ? supervisan.map(function (m) {
                return '<span style="display:inline-flex;align-items:center;gap:5px;padding:3px 10px;border-radius:999px;' +
                  'background:#efeee8;border:1px solid #E4DCCB;font:600 11px sans-serif;color:#1b1c19' + (m.activo ? '' : ';opacity:.55') + '">' +
                  esc(m.nombre || m.email) + '<span style="font-weight:500;color:#75786e">· ' +
                  (m.rol === 'sales_manager' ? 'Sales manager' : 'Project manager') + (m.activo ? '' : ' · desactivado') + '</span></span>';
              }).join('')
            : '<span style="font:500 13px sans-serif;color:#75786e">Sin encargado asignado.</span>';
        }

        /* Documentacion FUSIONADA aqui (decision owner 8-sep): la boveda son
           hoy 6 FAQ y 10 enlaces, todos con proyecto — una pestana propia no
           se sostenia. La lectura es de equipo (es_agente); el alta seguira
           exigiendo puede('documentacion'), la misma llave de siempre. */
        var docsEl = DS_ACTUAL.filter(function (d2) { return d2.proyecto === elegido.nombre; });
        var enl = docsEl.filter(function (d2) { return d2.categoria !== 'faq'; });
        var faq = docsEl.filter(function (d2) { return d2.categoria === 'faq'; });
        var cajaE = document.getElementById('d-enlaces');
        if (cajaE && cajaE.firstElementChild) {
          var mE = cajaE.firstElementChild.cloneNode(true);
          cajaE.innerHTML = '';
          if (!enl.length) cajaE.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Este proyecto no tiene enlaces guardados.</p>';
          enl.forEach(function (d2) {
            var f = mE.cloneNode(true);
            var p3 = function (k, v2) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v2; };
            p3('en-titulo', d2.titulo || 'Enlace');
            p3('en-meta', (d2.categoria || '—') + (d2.visible_portal ? ' · visible al comprador' : '') + (d2.confidencial ? ' · confidencial' : ''));
            if (d2.url) f.href = d2.url; else { f.removeAttribute('href'); f.style.cursor = 'default'; }
            cajaE.appendChild(f);
          });
        }
        var cajaF = document.getElementById('d-faqs');
        if (cajaF && cajaF.firstElementChild) {
          var mF = cajaF.firstElementChild.cloneNode(true);
          cajaF.innerHTML = '';
          if (!faq.length) cajaF.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Sin preguntas frecuentes para este proyecto.</p>';
          faq.forEach(function (d2) {
            var f = mF.cloneNode(true);
            var p3 = function (k, v2) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v2; };
            p3('fq-pregunta', d2.titulo || 'Pregunta');
            p3('fq-respuesta', d2.descripcion || '—');
            cajaF.appendChild(f);
          });
        }
        pon('d-pendiente2', fmt(d.cartera - cob, 'EUR'));
        pon('d-presu', '—');
        // Anclado por data-lw, no por texto (11-sep-2026): hojaConTexto()
        // excluye a propósito cualquier cosa dentro de un <aside>, y el título
        // del cajón vive en uno — por eso se quedaba fijo en "Horizon S1" al
        // abrir cualquier otro proyecto.
        pon('d-titulo', elegido.nombre + ' · Master Plan & Cuentas');

        /* La lista de unidades del cajón, con datos reales del proyecto
           elegido. `unidades_estado` es la vista que ya trae el contrato y el
           comprador vinculados — no se vuelve a cruzar aquí a mano. */
        q(sb.from('unidades_estado').select('codigo,modelo,estado,precio,contrato_numero,comprador_nombre,contrato_creado_por')
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
              // Agente que creó el contrato (11-sep-2026, encargo del owner: ver
              // de un vistazo qué agente hizo el contrato de cada unidad). Sin
              // ficha en `usuarios` (cuentas legacy) se enseña el email a secas.
              pon('u-agente', u.contrato_creado_por ? (EQUIPO_NOMBRE[u.contrato_creado_por] || u.contrato_creado_por) : '—', f);
              caja.appendChild(f);
            });
          });

        if (opts.mostrar) {
          var cajon = document.getElementById('cajon-detalle'), velo = document.getElementById('cajon-backdrop');
          if (cajon) cajon.classList.remove('translate-x-full');
          if (velo) velo.classList.remove('hidden');
        }
        if (opts.empujarUrl !== false) {
          var u2 = new URL(location.href);
          u2.searchParams.set('proyecto', nombre);
          history.replaceState(null, '', u2.pathname + u2.search);
        }
      }
      window.LW_V4 = window.LW_V4 || {}; window.LW_V4.abrirProyecto = abrirCajon;

      /* Rejilla + resumen + paginación de la página actual, sobre el filtro
         vigente. Nunca vuelve a pedir datos: PS/POR_P/COB_P ya están en
         memoria desde la carga inicial. */
      function renderizar() {
        var grid = document.getElementById('projects-grid');
        if (!grid) return;
        if (!MOLDE) MOLDE = grid.firstElementChild ? grid.firstElementChild.cloneNode(true) : null;
        if (!MOLDE) return;

        var filtrados = proyectosFiltrados();
        var totalPaginas = Math.max(1, Math.ceil(filtrados.length / PAGE_SIZE));
        if (EST.pag > totalPaginas) EST.pag = totalPaginas;
        var desde = (EST.pag - 1) * PAGE_SIZE;
        var pagina = filtrados.slice(desde, desde + PAGE_SIZE);

        grid.innerHTML = '';
        if (!pagina.length) {
          grid.innerHTML = '<p style="grid-column:1/-1;font:500 14px sans-serif;color:#75786e;padding:24px 4px">' +
            (PS.length ? 'Ningún proyecto coincide con el filtro.' : 'Todavía no hay proyectos dados de alta.') + '</p>';
        }
        pagina.forEach(function (p) {
          var c = MOLDE.cloneNode(true);
          var d = POR_P[p.nombre] || { t: 0, disp: 0, vend: 0, cartera: 0 };
          var cob = COB_P[p.nombre] || 0;
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
          var abre = function (ev) { if (ev) ev.stopPropagation(); abrirCajon(p.nombre, { mostrar: true }); };
          c.addEventListener('click', abre);
          var btn = c.querySelector('[data-abrir-cajon]');
          if (btn) btn.addEventListener('click', abre);
          grid.appendChild(c);
        });

        var resumen = document.getElementById('resumen-listado');
        if (resumen) {
          resumen.textContent = filtrados.length
            ? 'Mostrando ' + (desde + 1) + '–' + Math.min(desde + PAGE_SIZE, filtrados.length) + ' de ' + filtrados.length +
              (filtrados.length !== PS.length ? ' proyectos (filtrado de ' + PS.length + ' en total)' : (filtrados.length === 1 ? ' proyecto activo' : ' proyectos activos'))
            : (PS.length ? 'Ningún proyecto coincide con este filtro (' + PS.length + ' en total).' : 'Todavía no hay proyectos.');
        }
        var cajaPag = document.getElementById('pag-paginas');
        if (cajaPag) {
          cajaPag.innerHTML = '';
          for (var i = 1; i <= totalPaginas; i++) {
            (function (n) {
              var b = document.createElement('button');
              b.type = 'button'; b.textContent = String(n);
              b.className = n === EST.pag
                ? 'w-8 h-8 rounded-full bg-deep-lagoon text-surface-bright text-xs font-label-md shadow-sm font-semibold'
                : 'w-8 h-8 rounded-full bg-surface-container-lowest text-on-surface-variant hover:bg-surface-container text-xs font-label-md transition-colors border border-warm-border shadow-xs';
              b.addEventListener('click', function () { EST.pag = n; renderizar(); });
              cajaPag.appendChild(b);
            })(i);
          }
        }
        var btnAnt = document.getElementById('btn-pag-anterior'), btnSig = document.getElementById('btn-pag-siguiente');
        if (btnAnt) btnAnt.disabled = EST.pag <= 1;
        if (btnSig) btnSig.disabled = EST.pag >= totalPaginas;
      }

      /* Clases de "activo"/"inactivo" se leen UNA VEZ del propio HTML (el
         primer botón de cada fila ya nace activo: Todos/Todas) — así no hay
         que mantener aquí una copia a mano de las clases de Tailwind. */
      function chipClases(cont) {
        if (!cont) return null;
        var botones = cont.querySelectorAll('button');
        if (botones.length < 2) return null;
        return { activo: botones[0].className, inactivo: botones[1].className };
      }
      function marcaChip(cont, attr, valor, clases) {
        if (!cont || !clases) return;
        cont.querySelectorAll('button[' + attr + ']').forEach(function (b) {
          b.className = b.getAttribute(attr) === valor ? clases.activo : clases.inactivo;
        });
      }

      function wireControles() {
        var contP = document.getElementById('chips-proyecto');
        var contU = document.getElementById('chips-estado');
        var clasesP = chipClases(contP), clasesU = chipClases(contU);
        if (contP) contP.querySelectorAll('[data-chip-p]').forEach(function (b) {
          b.addEventListener('click', function () {
            EST.chipP = b.getAttribute('data-chip-p'); EST.pag = 1;
            marcaChip(contP, 'data-chip-p', EST.chipP, clasesP);
            renderizar();
          });
        });
        if (contU) contU.querySelectorAll('[data-chip-u]').forEach(function (b) {
          b.addEventListener('click', function () {
            EST.chipU = b.getAttribute('data-chip-u'); EST.pag = 1;
            marcaChip(contU, 'data-chip-u', EST.chipU, clasesU);
            renderizar();
          });
        });
        var buscador = document.getElementById('project-search');
        if (buscador) buscador.addEventListener('input', function () {
          EST.q = buscador.value.toLowerCase().trim(); EST.pag = 1; renderizar();
        });
        var btnAnt = document.getElementById('btn-pag-anterior');
        if (btnAnt) btnAnt.addEventListener('click', function () { if (EST.pag > 1) { EST.pag--; renderizar(); } });
        var btnSig = document.getElementById('btn-pag-siguiente');
        if (btnSig) btnSig.addEventListener('click', function () {
          var totalPaginas = Math.max(1, Math.ceil(proyectosFiltrados().length / PAGE_SIZE));
          if (EST.pag < totalPaginas) { EST.pag++; renderizar(); }
        });
      }

      var DS_ACTUAL = [];

      Promise.all([
        q(sb.from('proyectos').select('id,nombre,resort,parcela_master,parcela_master_m2').eq('activo', true).order('nombre'), 'proyectos'),
        q(sb.from('unidades').select('proyecto,estado,moneda,precio,precio_suelo,precio_construccion'), 'unidades'),
        /* La RPC de EQUIPO, nunca `.from('facturas')`. `facturas` tiene RLS por
           agente (`es_suyo`), así que una lectura directa devuelve solo «lo mío»
           —menos filas, sin ningún error— y el cobrado de la cartera saldría
           bajo para todo el que no sea super admin. Está avisado en la cabecera
           de este fichero y aun así caí en ello al escribir esta pantalla. */
        q(sb.rpc('facturas_equipo').select('proyecto_nombre,tipo,total,moneda,anulada'), 'facturas'),
        q(sb.from('documentos_proyecto').select('id,proyecto,categoria,titulo,descripcion,url,carpeta,visible_portal,confidencial,creado_en'), 'documentación'),
        /* Managers de cada proyecto (11-sep-2026, encargo del owner: sincronizar
           v4 con lo nuevo de Proyectos). Sin permiso esto vuelve vacío por RLS
           ("el equipo se ve entre sí" ya deja leer la fila; quien no es admin
           simplemente no tiene el botón de asignar, en editores.js), nunca un
           error — igual que ya hace el resto de esta pantalla con documentación. */
        q(sb.from('usuarios').select('user_id,email,nombre,rol,proyectos_supervisados,activo')
            .in('rol', ['sales_manager', 'project_manager']).order('nombre'), 'managers'),
        // Email→nombre del equipo, para enseñar «Agente» en vez del email crudo
        // en la lista de unidades del cajón (mismo dato que ya resuelve /proyectos/).
        q(sb.from('usuarios').select('email,nombre'), 'equipo')
      ]).then(function (r) {
        var ps = r[0], us = r[1] || [], fs = r[2] || [], ds = r[3] || [], mgrs = r[4] || [], eq = r[5] || [];
        if (!ps) return;
        /* Orden de la CARTERA: primero las W, luego las S, luego las G, y al
           final los proyectos sin codigo de parcela master (11-sep-2026,
           peticion del owner; mismo cambio en /intranet/proyectos/). Se ordena
           AQUI y no en el `.order('nombre')` de arriba porque Postgres ordenaria
           el nombre como texto —"W13" antes que "W2"— y ademas el codigo puede
           venir de la columna `parcela_master` y no del nombre ("Bonian
           Village" es la W8). El criterio lo pone `lwOrdenProyectos`
           (contracts/assets/vocabulario.js), compartido con la otra pantalla.
           Sin argumento: aqui cada fila YA trae su `parcela_master` dentro.
           Ordenar `PS` de una vez basta para la rejilla, el buscador, los chips
           y la paginacion: todos salen de `proyectosFiltrados()`, que filtra
           sobre PS sin reordenar. */
        ps.sort(lwOrdenProyectos());
        PS = ps; MGRS = mgrs; DS_ACTUAL = ds;
        EQUIPO_NOMBRE = {};
        eq.forEach(function (e) { if (e.email) EQUIPO_NOMBRE[e.email] = e.nombre || e.email; });

        /* --- agregados, SOLO EUR --- */
        var tot = { cartera: 0, suelo: 0, obra: 0 }, fueraEur = 0;
        var ests = { disponible: 0, reservada: 0, bloqueada: 0, vendida: 0, cobrada: 0, no_disponible: 0 };
        POR_P = {};
        us.forEach(function (u) {
          var k = u.proyecto || '¿?';
          var d = POR_P[k] = POR_P[k] || { t: 0, disp: 0, vend: 0, cartera: 0, suelo: 0, obra: 0, porEstado: {} };
          d.t++;
          if (u.estado === 'disponible') d.disp++;
          if (u.estado === 'vendida' || u.estado === 'cobrada') d.vend++;
          var eNorm = (u.estado || '').replace(/\s+/g, '_');
          d.porEstado[eNorm] = (d.porEstado[eNorm] || 0) + 1;
          if (eNorm in ests) ests[eNorm]++;
          if (!u.moneda || u.moneda !== 'EUR') { fueraEur++; return; }
          tot.cartera += Number(u.precio || 0); tot.suelo += Number(u.precio_suelo || 0); tot.obra += Number(u.precio_construccion || 0);
          d.cartera += Number(u.precio || 0);
        });
        var cobrado = 0, facturado = 0;
        COB_P = {};
        fs.forEach(function (f) {
          if (f.anulada || (f.moneda || 'EUR') !== 'EUR') return;
          if (f.tipo === 'recibi') { cobrado += Number(f.total || 0); var k = f.proyecto_nombre || ''; COB_P[k] = (COB_P[k] || 0) + Number(f.total || 0); }
          else if (f.tipo === 'factura') facturado += Number(f.total || 0);
        });
        DOC_P = {}; ds.forEach(function (d) { DOC_P[d.proyecto] = (DOC_P[d.proyecto] || 0) + 1; });

        /* --- KPIs --- */
        pon('k-cartera', fmt(tot.cartera, 'EUR'));
        // Nota corta y solo cuando aplica (decisión del owner, 11-sep-2026:
        // el aviso largo de antes "no aportaba nada" — esto es un aviso, no
        // un párrafo). Sin unidades fuera de EUR, no hay nada que decir.
        pon('k-cartera-pie', 'Volumen en ' + ps.length + ' desarrollos activos' + (fueraEur ? ' · cifras en EUR' : ''));
        pon('k-cobrado', fmt(cobrado, 'EUR'));
        pon('k-cobrado-pie', facturado ? (Math.round(cobrado / facturado * 1000) / 10) + '% de lo facturado (' + fmt(facturado, 'EUR') + ')' : 'sin facturas emitidas');
        pon('k-pendiente', fmt(tot.cartera - cobrado, 'EUR'));
        pon('k-pendiente-pie', 'Cartera menos lo cobrado');
        pon('k-suelo-v', fmt(tot.suelo, 'EUR'));
        pon('k-obra', fmt(tot.obra, 'EUR'));
        var base = tot.suelo + tot.obra;
        pon('k-mix-pie', base ? 'Suelo: ' + (Math.round(tot.suelo / base * 1000) / 10) + '% · Construcción: ' + (Math.round(tot.obra / base * 1000) / 10) + '%' : '—');

        /* --- contadores de los chips: SIEMPRE globales, no cambian con el
           filtro activo — son "cuánto habría si eligieras este chip", no
           "cuánto hay ahora mismo visible". */
        pon('p-todos', String(ps.length));
        /* Los chips «En comercializacion / Completados / En estudio» pedian una
           clasificacion que `proyectos` NO tiene (solo hay `activo`). En vez de
           dejar 14/6/4 inventados o poner tres guiones, se derivan del inventario
           con el MISMO criterio que ya usa el badge de cada tarjeta: hay
           disponibles / todo asignado / sin unidades. */
        var cl = { com: 0, fin: 0, est: 0 };
        ps.forEach(function (p) {
          var d = POR_P[p.nombre];
          if (!d || !d.t) cl.est++;
          else if (d.disp) cl.com++;
          else cl.fin++;
        });
        pon('c-comercializacion', String(cl.com));
        pon('c-completados', String(cl.fin));
        pon('c-estudio', String(cl.est));
        pon('uds-todas', String(us.length));
        Object.keys(ests).forEach(function (e) { pon('uds-' + e, String(ests[e])); });

        wireControles();
        renderizar();

        /* Llegar con ?proyecto= en la URL abre ESE cajón — quien navega con un
           enlace concreto ya eligió, se le enseña. Una carga a secas se queda
           con el cajón cerrado (11-sep-2026: antes se abría solo con el
           proyecto de más unidades, y parecía un desplegable roto). */
        var pedido = new URLSearchParams(location.search).get('proyecto');
        if (pedido && ps.some(function (p) { return p.nombre === pedido; })) {
          abrirCajon(pedido, { mostrar: true, empujarUrl: false });
        }
      });
    },

    /* Modelos — pantalla construida por el estudio (Stitch no la tiene: la
       herramienta nacio el 7-sep-2026, despues de la descarga del lienzo).
       Como el fichero es NUESTRO, aqui se ancla por `data-lw` y no por texto. */
    modelos: function (sb) {
      var $ = function (k, raiz) { return (raiz || document).querySelector('[data-lw="' + k + '"]'); };
      var pon = function (k, v, raiz) { var e = $(k, raiz); if (e) e.textContent = v; };

      Promise.all([
        q(sb.from('modelos').select('id,slug,nombre,dormitorios,banos,villa_m2,terraza_m2,descripcion,precio_construccion,moneda,publicado,activo,renders_pendientes,orden').order('orden', { ascending: true, nullsFirst: false }), 'modelos'),
        q(sb.from('unidades').select('modelo_id,proyecto'), 'unidades por modelo'),
        q(sb.from('modelo_documentos').select('modelo_id,nombre,tipo,tamano_bytes,subido_en,visible_portal'), 'documentos de modelo')
      ]).then(function (r) {
        var ms = r[0], us = r[1] || [], ds = r[2] || [];
        if (!ms) return;

        /* «Sin ficha tecnica» es el dato que de verdad manda en esta pantalla:
           un modelo sin dormitorios, banos ni superficie no puede heredar nada a
           la unidad ni publicarse. Se define por lo que falta, no por un estado
           que la tabla no tiene. */
        var sinFicha = function (m) {
          return m.dormitorios == null && m.banos == null && m.villa_m2 == null && m.terraza_m2 == null;
        };
        var porModelo = {}, proyModelo = {};
        us.forEach(function (u) {
          if (!u.modelo_id) return;
          porModelo[u.modelo_id] = (porModelo[u.modelo_id] || 0) + 1;
          var d = proyModelo[u.modelo_id] = proyModelo[u.modelo_id] || {};
          var k = u.proyecto || 'Sin proyecto';
          d[k] = (d[k] || 0) + 1;
        });
        var docsModelo = {};
        ds.forEach(function (d) { (docsModelo[d.modelo_id] = docsModelo[d.modelo_id] || []).push(d); });

        var activos = ms.filter(function (m) { return m.activo; }).length;
        var publicados = ms.filter(function (m) { return m.publicado; }).length;
        var faltan = ms.filter(sinFicha).length;
        var sinRender = ms.filter(function (m) { return m.renders_pendientes; }).length;
        var enlazadas = Object.keys(porModelo).reduce(function (a, k) { return a + porModelo[k]; }, 0);

        pon('k-activos', String(activos));
        pon('k-total', String(ms.length));
        pon('k-activos-pie', enlazadas + ' unidades enlazadas a un modelo');
        pon('k-publicados', String(publicados));
        pon('k-publicados-pie', publicados ? 'los unicos que ve un comprador en la web' : 'ninguno visible fuera');
        pon('k-sinficha', String(faltan));
        pon('k-sinficha-pie', faltan ? 'sin dormitorios, banos ni superficie: no pueden heredar nada' : 'todos con ficha completa');
        pon('k-sinrender', String(sinRender));
        pon('k-sinrender-pie', sinRender ? 'marcados como pendientes de imagen' : 'todos con render');

        pon('c-todos', String(ms.length));
        pon('c-publicados', String(publicados));
        pon('c-sinficha', String(faltan));
        pon('c-sinrender', String(sinRender));

        /* Monedas mezcladas: se dice, no se suma. Mismo criterio que Proyectos. */
        var monedas = {}; ms.forEach(function (m) { if (m.precio_construccion != null) monedas[m.moneda || 'EUR'] = 1; });
        if (Object.keys(monedas).length > 1) {
          bandaNota('El catalogo tiene precios en mas de una moneda (' + Object.keys(monedas).join(' y ') +
            '). Cada modelo ensena la suya; aqui no se suma nada entre monedas.', '#8A6A34');
        }

        /* --- rejilla, desde el molde --- */
        var grid = document.getElementById('modelos-grid');
        if (!grid || !grid.firstElementChild) { console.info('[v4] modelos: sin molde de tarjeta'); return; }
        var molde = grid.firstElementChild.cloneNode(true);
        grid.innerHTML = '';
        if (!ms.length) {
          grid.innerHTML = '<p style="font:500 14px/1.5 sans-serif;color:#75786e;margin:0">El catalogo no tiene ningun modelo dado de alta.</p>';
          return;
        }
        ms.forEach(function (m) {
          var c = molde.cloneNode(true);
          pon('m-nombre', m.nombre || '—', c);
          pon('m-slug', m.slug ? '/' + m.slug : 'sin slug', c);
          pon('m-estado', sinFicha(m) ? 'Sin ficha' : (m.publicado ? 'Publicado' : 'Borrador'), c);
          var sp = [];
          if (m.dormitorios != null) sp.push(m.dormitorios + ' dorm.');
          if (m.banos != null) sp.push(m.banos + ' banos');
          if (m.villa_m2 != null) sp.push(m.villa_m2 + ' m² villa');
          if (m.terraza_m2 != null) sp.push(m.terraza_m2 + ' m² terraza');
          pon('m-specs', sp.length ? sp.join(' · ') : 'Ficha tecnica sin rellenar', c);
          pon('m-precio', m.precio_construccion != null ? fmt(m.precio_construccion, m.moneda) : '—', c);
          var n = porModelo[m.id] || 0;
          pon('m-unidades', n ? n + (n === 1 ? ' unidad' : ' unidades') : 'sin unidades', c);
          c.style.cursor = 'pointer';
          c.addEventListener('click', function () { location.search = '?modelo=' + encodeURIComponent(m.slug || m.nombre); });
          grid.appendChild(c);
        });

        /* --- ficha: la de ?modelo= o la que mas unidades arrastra --- */
        var pedido = new URLSearchParams(location.search).get('modelo');
        var el = ms.filter(function (m) { return m.slug === pedido || m.nombre === pedido; })[0] ||
                 ms.slice().sort(function (a, b) { return (porModelo[b.id] || 0) - (porModelo[a.id] || 0); })[0];
        if (!el) return;
        window.LW_V4 = window.LW_V4 || {}; window.LW_V4.modelo = el;
        pon('d-nombre', el.nombre || '—');
        pon('d-slug', el.slug ? '/' + el.slug : 'sin slug');
        pon('d-estado', sinFicha(el) ? 'Sin ficha' : (el.publicado ? 'Publicado' : 'Borrador'));
        pon('d-dorm', el.dormitorios != null ? String(el.dormitorios) : '—');
        pon('d-banos', el.banos != null ? String(el.banos) : '—');
        pon('d-villa', el.villa_m2 != null ? el.villa_m2 + ' m²' : '—');
        pon('d-terraza', el.terraza_m2 != null ? el.terraza_m2 + ' m²' : '—');
        pon('d-precio', el.precio_construccion != null ? fmt(el.precio_construccion, el.moneda) : '—');
        pon('d-desc', el.descripcion || 'Este modelo no tiene descripcion escrita. La web publica la toma de aqui, asi que mientras este vacia no hay nada que publicar.');

        var caja = document.getElementById('d-proyectos');
        if (caja && caja.firstElementChild) {
          var base = caja.firstElementChild.cloneNode(true);
          caja.innerHTML = '';
          var mapa = proyModelo[el.id] || {};
          var claves = Object.keys(mapa).sort(function (a, b) { return mapa[b] - mapa[a]; });
          if (!claves.length) {
            caja.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Ninguna unidad usa este modelo todavia.</p>';
          } else {
            claves.forEach(function (k) {
              var f = base.cloneNode(true);
              pon('p-nombre', k, f);
              pon('p-n', String(mapa[k]), f);
              caja.appendChild(f);
            });
          }
        }

        var cd = document.getElementById('d-docs');
        if (cd && cd.firstElementChild) {
          var moldeD = cd.firstElementChild.cloneNode(true);
          cd.innerHTML = '';
          var dd = docsModelo[el.id] || [];
          if (!dd.length) {
            cd.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Ningun documento adjunto a este modelo. La tabla existe y el boton tambien; todavia no se ha subido nada.</p>';
          } else {
            dd.forEach(function (d) {
              var f = moldeD.cloneNode(true);
              pon('doc-titulo', d.nombre || 'Documento', f);
              pon('doc-meta', (d.tipo || '—') + ' · ' + fFecha(d.subido_en) + (d.visible_portal ? ' · visible al comprador' : ''), f);
              cd.appendChild(f);
            });
          }
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
      /* Cuerpo real (fase A3). La suite guarda POR UNIDAD: fase, fecha de
         entrega y ultima actualizacion — no guarda contratista, % de avance,
         fecha de inicio ni camaras. Lo que no existe se queda en guion con el
         motivo a la vista; el 68% del diseno era un numero inventado. */
      q(sb.from('unidades_estado').select('codigo,proyecto,modelo,estado,obra_fase,obra_fecha_entrega,obra_actualizado,comprador_nombre').not('obra_fase', 'is', null).order('obra_actualizado', { ascending: false }).limit(60), 'obra')
        .then(function (us) {
          if (us == null) return;
          kpi(/EN OBRA|ACTIVAS/i, String(us.length), 'unidades con fase abierta');
          var proys = {}; us.forEach(function (u) { if (u.proyecto) proys[u.proyecto] = 1; });
          pon2('k-po', String(Object.keys(proys).length));
          pon2('k-po-pie', Object.keys(proys).slice(0, 3).join(', ') || 'sin proyectos en obra');
          pon2('k-hitos', String(us.filter(function (u) { return u.obra_fecha_entrega; }).length));
          pon2('k-hitos-pie', 'unidades con fecha de entrega puesta');
          pon2('k-certificaciones', '—');
          bandaNota('«Certificaciones», «% completado», contratista, fecha de inicio y las cámaras se quedan en «—»: la suite no guarda ninguno de esos datos. Lo que sí guarda por unidad — fase, entrega y última actualización — es lo que ves.', '#8A6A34');

          // siguiente entrega: la fecha futura mas cercana
          var hoy = new Date().toISOString().slice(0, 10);
          var conFecha = us.filter(function (u) { return u.obra_fecha_entrega && u.obra_fecha_entrega >= hoy; })
            .sort(function (a, b) { return a.obra_fecha_entrega < b.obra_fecha_entrega ? -1 : 1; });
          if (conFecha.length) {
            var sgu = conFecha[0];
            var d = Math.round((new Date(sgu.obra_fecha_entrega) - new Date(hoy)) / 864e5);
            pon2('sig-titulo', 'Entrega ' + sgu.codigo);
            pon2('sig-sub', (sgu.proyecto || '—') + ' · ' + fFecha(sgu.obra_fecha_entrega));
            pon2('sig-chip', 'en ' + d + (d === 1 ? ' día' : ' días'));
            pon2('sig-prio', (sgu.obra_fase || '—'));
          } else {
            pon2('sig-titulo', 'Sin entregas con fecha futura');
            pon2('sig-sub', '—'); pon2('sig-chip', '—'); pon2('sig-prio', '—');
          }

          // tarjeta destacada: la unidad con actividad mas reciente
          var u0 = us[0];
          if (u0) {
            pon2('o-estado', (u0.estado || '—').toUpperCase() + ' · ' + (u0.obra_fase || 'sin fase'));
            pon2('o-codigo', 'Código: ' + u0.codigo);
            pon2('o-titulo', (u0.proyecto || '—') + ' · ' + (u0.modelo || u0.codigo));
            pon2('o-lugar', u0.comprador_nombre ? 'Comprador: ' + u0.comprador_nombre : 'Sin comprador vinculado');
            pon2('o-contratista', 'Contratista: — (no se registra)');
            pon2('o-pct', '—');
            pon2('o-inicio', 'Inicio: — (no se registra)');
            pon2('o-hito', 'Fase actual: ' + (u0.obra_fase || '—'));
            pon2('o-entrega', 'Entrega: ' + (u0.obra_fecha_entrega ? fFecha(u0.obra_fecha_entrega) : 'sin fecha'));
          }

          panelReal('Unidades en obra', us.map(function (u) {
            return itemPanel(esc(u.codigo) + ' · ' + esc(u.proyecto || ''),
              esc(u.modelo || '—') + ' · ' + esc(u.comprador_nombre || 'sin comprador') + ' · entrega ' + fFecha(u.obra_fecha_entrega),
              esc(u.obra_fase || '—'));
          }), us.map(function () { return '/intranet/obra/'; }),
          'Ninguna unidad con fase de obra abierta.', '/intranet/obra/');
        });
    },
    /* documentacion/: fusionada en Proyectos el 8-sep (decision del owner).
       La pagina es una redireccion; no queda nada que cablear aqui. */
    creatividades: function () {
      bandaNota('Creatividades y dossiers no viven en la base de datos: el catálogo real está en /intranet/creatividades/ — los botones de esta pantalla te llevan allí', '#485B37');
    },

    usuarios: function (sb) {
      /* Perfil, matriz y auditoria reales (fase A5). La matriz sale de
         usuarios.herramientas — la lista real que gobierna el guard — y la
         auditoria de la tabla notificaciones (hechos escritos por triggers).
         Las IPs y el 2FA del diseno no existen en la suite: fuera. */
      var t = tablaPor([/MIEMBRO|NOMBRE|USUARIO/, /ROL|ACCESO/]);
      Promise.all([
        q(sb.from('usuarios').select('nombre,email,rol,activo,herramientas').order('nombre'), 'usuarios', t),
        q(sb.from('notificaciones').select('titulo,detalle,creado_en').order('creado_en', { ascending: false }).limit(8), 'auditoría')
      ]).then(function (r) {
        var us = r[0], ns = r[1] || [];
        if (!us) return;
        var act = us.filter(function (u) { return u.activo; });
        pon2('k-usuarios', String(act.length));
        var roles = {}; us.forEach(function (u) { if (u.rol) roles[u.rol] = 1; });
        pon2('k-roles', String(Object.keys(roles).length));
        pon2('k-notarial', '—');
        pon2('k-2fa', '—');
        bandaNota('«Supervisión notarial» y «2FA» se quedan en «—»: la suite no guarda ninguno de esos datos.', '#8A6A34');

        if (t) {
          var pl = plantillaFilas(t);
          us.forEach(function (u) {
            fila(pl, [u.nombre || '—', u.email || '—', u.rol || '—', u.activo ? 'ACTIVO' : 'INACTIVO',
              (u.herramientas || []).length + ' herramientas', ''],
              '/intranet/v4/usuarios/?u=' + encodeURIComponent(u.email || ''));
          });
        }

        /* perfil: ?u= o el primero. La matriz refleja usuarios.herramientas —
           exactamente lo que el guard aplica, ni mas ni menos. */
        var pedido = new URLSearchParams(location.search).get('u');
        var el = us.filter(function (u) { return u.email === pedido; })[0] || us[0];
        if (el) {
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.usuario = el;
          pon2('u-perfil', 'Perfil: ' + (el.nombre || el.email) + ' · ' + (el.rol || '—'));
          var hs = el.herramientas || [];
          var tiene = function (h) { return el.rol === 'super_admin' || hs.indexOf(h) !== -1; };
          pon2('m1', tiene('contratos') ? 'Autorizado' : 'Sin acceso');
          pon2('m2', tiene('facturas') ? 'Autorizado' : 'Sin acceso');
          pon2('m3', tiene('unidades') ? 'Autorizado' : 'Sin acceso');
          pon2('m4', tiene('compradores') ? 'Autorizado' : 'Sin acceso');
        }

        var caja = document.getElementById('auditoria');
        if (caja && caja.firstElementChild) {
          var molde = null;
          for (var i6 = 0; i6 < caja.children.length; i6++) {
            if (caja.children[i6].querySelector && caja.children[i6].querySelector('[data-lw="a-titulo"]')) { molde = caja.children[i6].cloneNode(true); break; }
          }
          if (molde) {
            caja.innerHTML = '';
            if (!ns.length) {
              caja.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Sin hechos registrados todavía.</p>';
            }
            ns.forEach(function (nx) {
              var f = molde.cloneNode(true);
              var p3 = function (k, v) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v; };
              p3('a-titulo', nx.titulo || 'Hecho');
              p3('a-sub', nx.detalle || '');
              p3('a-fecha', fFecha(nx.creado_en));
              caja.appendChild(f);
            });
          }
        }
      });
    },
    soporte: function (sb) {
      /* Bandeja y conversacion REALES (fase A2, 8-sep). hilo_soporte no guarda
         asunto, prioridad ni agente asignado — eso era del diseno. El asunto es
         el ultimo mensaje del hilo y la prioridad se sustituye por la categoria.
         Responder es fase C: va por la RPC portal_enviar_mensaje y cada mensaje
         dispara un email real al comprador, asi que aqui NI SE TOCA. */
      Promise.all([
        q(sb.from('hilo_soporte').select('id,client_id,categoria,estado,actualizado_en').order('actualizado_en', { ascending: false }).limit(80), 'hilos'),
        q(sb.from('clients').select('id,full_name,email,phone,tipo'), 'clientes de soporte'),
        q(sb.from('mensajes_comprador').select('hilo_id,client_id,de,autor,texto,creado_en').order('creado_en', { ascending: false }).limit(600), 'mensajes')
      ]).then(function (r) {
        var hs = r[0], cs = r[1] || [], ms = r[2] || [];
        if (hs == null) return;
        var cli = {}; cs.forEach(function (c) { cli[c.id] = c; });
        var ultimo = {}, deHilo = {};
        ms.forEach(function (x) {
          var k = x.hilo_id || x.client_id;
          if (!ultimo[k]) ultimo[k] = x;                    // vienen DESC: el primero es el ultimo
          (deHilo[k] = deHilo[k] || []).push(x);
        });

        var abiertos = hs.filter(function (h) { return h.estado === 'abierto'; });
        var espera = hs.filter(function (h) { return /espera/.test(h.estado || ''); });
        pon2('k-abiertos', String(abiertos.length));
        pon2('k-abiertos-pie', 'de ' + hs.length + ' hilos en total');
        pon2('k-whatsapp', '—');
        pon2('k-satisfaccion', '—');
        pon2('k-tmr', '—');
        pon2('k-tmr-chip', 'no se mide');
        bandaNota('«Tiempo medio de respuesta», «Canal WhatsApp» y «Satisfacción» se quedan en «—»: la suite no mide ninguno de los tres, y las cifras que había eran del diseño.', '#8A6A34');
        pon2('c-todos', 'Todos (' + hs.length + ')');
        pon2('c-abiertos', 'Abiertos (' + abiertos.length + ')');
        pon2('c-espera', 'En espera (' + espera.length + ')');
        pon2('n-hilos', abiertos.length + ' activos');

        var lista = document.getElementById('lista-hilos');
        if (!lista || !lista.firstElementChild) { console.info('[v4] soporte: sin molde'); return; }
        var molde = lista.firstElementChild.cloneNode(true);
        lista.innerHTML = '';
        if (!hs.length) {
          lista.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0;padding:6px 2px">Ningún hilo de soporte todavía.</p>';
        }
        hs.slice(0, 25).forEach(function (h) {
          var f = molde.cloneNode(true);
          var pon3 = function (k, v) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v; };
          var c = cli[h.client_id] || {};
          var u = ultimo[h.id] || ultimo[h.client_id];
          pon3('t-num', '#' + String(h.id).slice(0, 6));
          pon3('t-nombre', c.full_name || 'Cliente');
          pon3('t-estado', (h.estado || '—').replace(/_/g, ' ').toUpperCase());
          pon3('t-asunto', u ? u.texto : 'Sin mensajes en el hilo');
          pon3('t-cat', h.categoria || 'general');
          pon3('t-quien', u ? (u.de === 'equipo' ? 'Equipo' : 'Comprador') : '—');
          pon3('t-fecha', fFecha(h.actualizado_en));
          f.style.cursor = 'pointer';
          f.addEventListener('click', function () { location.search = '?hilo=' + encodeURIComponent(h.id); });
          lista.appendChild(f);
        });

        /* --- el hilo elegido: ?hilo= o el mas reciente --- */
        var pedido = new URLSearchParams(location.search).get('hilo');
        var el = hs.filter(function (h) { return String(h.id) === pedido; })[0] || hs[0];
        if (!el) return;
        var c = cli[el.client_id] || {};
        window.LW_V4 = window.LW_V4 || {}; window.LW_V4.hilo = el; window.LW_V4.hiloCliente = c;
        var msgs = (deHilo[el.id] || deHilo[el.client_id] || []).slice().reverse();
        pon2('h-num', 'Hilo #' + String(el.id).slice(0, 6));
        pon2('h-nombre', c.full_name || 'Cliente');
        pon2('h-sub', (el.categoria || 'general') + ' · ' + msgs.length + (msgs.length === 1 ? ' mensaje' : ' mensajes') + ' · ' + (el.estado || '—'));
        pon2('h-chip', c.tipo === 'empresa' ? 'Empresa' : 'Persona física');
        pon2('cv-tel', c.phone || 'sin teléfono en ficha');
        pon2('cv-email', c.email || 'sin email en ficha');
        pon2('cv-cat', 'Categoría: ' + (el.categoria || 'general'));
        var ta = document.querySelector('textarea');
        if (ta) ta.placeholder = 'Escribe la respuesta para ' + (c.full_name || 'el comprador') + '… (se envía desde la herramienta: cada mensaje manda un email real)';
        // «Ver perfil» → la ficha real; «WhatsApp» solo si hay teléfono (norma wa.me)
        var enlaces = document.querySelectorAll('a[href="#"]');
        for (var i2 = 0; i2 < enlaces.length; i2++) {
          var t2 = (enlaces[i2].textContent || '').trim();
          if (/Ver perfil/.test(t2)) enlaces[i2].href = '/intranet/compradores/?id=' + el.client_id;
          else if (/WhatsApp/.test(t2)) {
            if (c.phone) enlaces[i2].href = 'https://wa.me/' + String(c.phone).replace(/[^0-9]/g, '');
            else enlaces[i2].style.display = 'none';
          }
        }

        var convo = document.getElementById('convo');
        if (!convo) return;
        var bloques = Array.prototype.slice.call(convo.children);
        var moldeIzq = null, moldeDer = null;
        bloques.forEach(function (b) {
          if (!moldeDer && /justify-end/.test(b.className)) moldeDer = b.cloneNode(true);
          else if (!moldeIzq && /items-start/.test(b.className) && !/justify-center/.test(b.className)) moldeIzq = b.cloneNode(true);
        });
        convo.innerHTML = '';
        if (!msgs.length) {
          convo.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0;text-align:center">Este hilo no tiene mensajes.</p>';
          return;
        }
        var iniciales = (c.full_name || 'C').split(/\s+/).slice(0, 2).map(function (w) { return w[0] || ''; }).join('').toUpperCase();
        msgs.forEach(function (msg) {
          var esEquipo = msg.de === 'equipo';
          var b = (esEquipo ? moldeDer : moldeIzq);
          if (!b) return;
          var f = b.cloneNode(true);
          var burbuja = f.querySelector('[class*="rounded-2xl"]');
          if (burbuja) burbuja.textContent = msg.texto;     // pisa tambien los adjuntos mock
          var hora = f.querySelector('span[class*="text-[11px]"]');
          if (hora) hora.textContent = fFecha(msg.creado_en) + ' · ' + (esEquipo ? (msg.autor || 'Equipo') : 'Comprador');
          var avatar = f.querySelector('div[class*="rounded-full"]');
          if (avatar && !esEquipo) avatar.textContent = iniciales;
          convo.appendChild(f);
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

  /* Las 3 pantallas moviles comparten datos con sus hermanas de escritorio:
     misma tabla, mismos handlers. El registro va por ultimo segmento de ruta,
     asi que "contratos.html" (movil) apunta al mismo handler que "contratos".
     proyectos-cuentas movil no tiene las anclas data-lw del escritorio: lleva
     un panel en vivo propio, que es el trato honesto para una maqueta movil. */
  REG['contratos.html'] = REG['contratos'];
  REG['seguimiento.html'] = REG['operaciones'];
  REG['proyectos-cuentas.html'] = function (sb) {
    Promise.all([
      q(sb.from('proyectos').select('nombre,resort').eq('activo', true).order('nombre'), 'proyectos'),
      q(sb.from('unidades').select('proyecto,estado'), 'unidades')
    ]).then(function (r) {
      var ps = r[0], us2 = r[1] || [];
      if (!ps) return;
      var porP = {};
      us2.forEach(function (u) {
        var d = porP[u.proyecto] = porP[u.proyecto] || { t: 0, disp: 0 };
        d.t++; if (u.estado === 'disponible') d.disp++;
      });
      panelReal('Proyectos (' + ps.length + ')', ps.map(function (p2) {
        var d = porP[p2.nombre] || { t: 0, disp: 0 };
        return itemPanel(esc(p2.nombre), esc(p2.resort || '—'), d.t + ' uds · ' + d.disp + ' disp.');
      }), ps.map(function (p2) { return '/intranet/v4/proyectos/?proyecto=' + encodeURIComponent(p2.nombre); }),
      'Sin proyectos activos.', '/intranet/v4/proyectos/');
    });
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
