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
  // busca `valor` en una lista de pares [valor, etiqueta] (Equipos de venta / Condiciones)
  function etiquetaDe(lista, valor) {
    var f = (lista || []).filter(function (x) { return x[0] === valor; })[0];
    return f ? f[1] : (valor || '—');
  }

  /* ---- localizar por TEXTO en el marcado minificado de Stitch ---- */
  function hojaConTexto(rx, raiz) {
    var all = (raiz || document.body).querySelectorAll('span,p,h1,h2,h3,h4,div,th,button');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.children.length > 2) continue;
      // nunca anclar en la cáscara: la sidebar tiene "Vencimientos", "Recibos"…
      // y el primer intento le escribió el pie de un KPI al subtítulo del logo
      if (el.closest('aside,nav,header,#lw-editor,#lw-cargando,#lw-maqueta')) continue;
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
  /* Aviso de acceso para las dos pantallas de administración pura (Equipos de
     venta, Condiciones). nav.js ya las oculta del menú para quien no es
     admin/super_admin, así que llegar aquí exige teclear la URL a mano — pero
     el candado real es la RLS (`es_admin()`), esto es solo no enseñar
     controles que la base va a rechazar. Sustituye el contenido de `main` y
     deja la cáscara (sidebar, topbar) intacta. */
  function notaSoloAdmin() {
    quitaVelo();
    var main = document.querySelector('main');
    if (!main) return;
    main.innerHTML = '<div style="max-width:32rem;margin:6rem auto 0;background:#fff;border-radius:12px;' +
      'padding:2rem;box-shadow:0 1px 3px rgba(0,0,0,.08);display:flex;flex-direction:column;align-items:center;' +
      'gap:10px;text-align:center;font-family:\'Neue Kabel\',sans-serif">' +
      '<span class="material-symbols-outlined" style="font-size:32px;color:#42210B">lock</span>' +
      '<h1 style="margin:0;font-size:22px;font-weight:700;color:#104C4F">Solo administración</h1>' +
      '<p style="margin:0;font-size:14px;color:#44483f">Esta pantalla es de administración (roles admin / super_admin) — tu sesión no tiene ese rol.</p>' +
      '<a href="../home/" style="margin-top:6px;padding:10px 20px;border-radius:999px;background:#485b37;color:#fff;font-weight:600;font-size:13px;text-decoration:none">Volver al inicio</a></div>';
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

  /* ══════════════ chips de filtro REALES (15-sep-2026) ══════════════
     Mismo patrón que ya usaba en solitario el panel «Reparto de equipo» de
     Comisiones (`cablearFiltrosEquipo`, más abajo): cada fila/tarjeta ya
     pintada lleva un atributo con su categoría, y el chip solo
     enseña/oculta por ese atributo — no repinta nada, así que no puede
     perder un listener de fila. Se sube aquí porque el mismo hueco se
     repetía en seis pantallas (Regla 0: una lista/patrón copiado en varios
     sitios es la duplicación que se paga después).

     Por qué NO se reutiliza `conmutaChip` de maqueta.js para el aspecto: esa
     función se apaga a propósito en cuanto hay datos reales ("un chip que
     se enciende sin filtrar miente"), así que el aspecto tiene que venir de
     aquí también, junto al filtro de verdad — no se puede pedir prestada
     media función y la otra media no.

     `chips`: NodeList de botones. `claveDe(btn)`: cómo se saca la categoría
     de CADA botón (varía: unos la llevan en un data-*, otros solo en su
     span contador). `todas`: la clave que no filtra nada. `coincide(fila,
     clave)`: si esa fila/tarjeta ya pintada entra en esa categoría — no es
     una simple igualdad de atributo porque algunas categorías se solapan
     (un modelo puede estar publicado Y sin render a la vez), así que cada
     pantalla decide su propia comprobación. `alActivar` pinta el aspecto:
     cada pantalla usa sus propias clases de Tailwind para "encendido" (no
     hay una sola, y adivinarla por frecuencia de className —que es lo que
     hace `conmutaChip`— falla en cuanto dos chips inactivos no comparten
     clase exacta), así que aquí se recibe explícito, como ya hace
     `cablearFiltrosEquipo` más abajo. */
  function cablearChipsFiltro(chips, contenedorFilas, selectorFilas, claveDe, todas, coincide, alActivar) {
    if (!chips.length) return;
    chips.forEach(function (btn) {
      btn.addEventListener('click', function (ev) {
        ev.stopPropagation();   // si no, maqueta.js la ve pasar y avisa «sin cablear»
        if (alActivar) chips.forEach(function (b) { alActivar(b, b === btn); });
        var clave = claveDe(btn);
        contenedorFilas.querySelectorAll(selectorFilas).forEach(function (fila) {
          fila.style.display = (clave === todas || coincide(fila, clave)) ? '' : 'none';
        });
      });
    });
  }
  /* Las pestañas por `data-lw-tab` (Comisiones: Lawang/Equipo propio; Cuentas:
     por contrato/proyecto/cuenta) NO entran aquí: cada una lleva su propio
     script al pie de página, con `stopPropagation` para escapar de
     maqueta.js — verificado antes de tocar nada, ya filtran/muestran de
     verdad. Añadir un segundo wiring aquí sería la duplicación que la Regla
     0 de la suite prohíbe. */

  /* ══════════════ velo de carga (14-sep-2026, encargo del owner) ══════════════
     Cada pantalla de la v4 nace con todos sus numeros en «—» y los rellena este
     fichero cuando vuelven las consultas. Ese segundo y medio de rejilla de
     guiones NO se lee como «cargando»: se lee como «no hay datos», que es
     justo lo contrario de lo que pasa. El velo tapa el contenido hasta que no
     queda ninguna consulta en vuelo.

     COMO SABE QUE HA TERMINADO. No preguntando a cada handler —son dieciocho y
     habria que tocarlos todos, y el diecinueve naceria sin avisar— sino
     contando las consultas en vuelo por el unico sitio por donde pasan todas.
     `vig()` es ese sitio; `q()` y `cnt()` lo usan, y las cuatro llamadas que
     tenian su propio `.then` se envuelven sin tocarles una coma.

     LO QUE NO PUEDE PASAR, y como se evita cada cosa:
     · Una consulta que FALLA no puede dejar el velo puesto — por eso `sale()`
       es lo primero de las DOS ramas, la de exito y la de rechazo.
     · Si el JS muere entre el velo y el destape, un `setTimeout` suyo moriria
       con el y la pantalla quedaria tapada para siempre. Por eso el destape de
       emergencia es CSS (`animation: lw-rendirse`, en shell.css): sobrevive a
       un JS muerto porque no depende de el.
     · Una pantalla SIN handler (la puerta de `entrar/`) no se tapa: el velo
       solo se pone si `REG[seg]` existe.
     · El contador puede tocar 0 entre dos tandas —una consulta que dispara
       otra dentro de su `.then` baja el contador antes de que la siguiente lo
       suba—, asi que el destape se confirma en el tick siguiente. */
  var enVuelo = 0, veloEl = null, veloMuerto = false;

  function ponVelo() {
    if (veloEl || veloMuerto) return;
    /* Se llama antes que nada, asi que puede llegar sin <body> si algun dia
       este fichero deja de ir con `defer`. Sin esto seria un throw que se
       lleva por delante el cableado entero de la pantalla. */
    if (!document.body) { document.addEventListener('DOMContentLoaded', ponVelo); return; }
    veloEl = document.createElement('div');
    veloEl.id = 'lw-cargando';
    veloEl.setAttribute('role', 'status');
    veloEl.setAttribute('aria-live', 'polite');
    veloEl.innerHTML =
      '<p class="lw-c-marca">LAWANG</p>' +
      '<div class="lw-c-frases">' +
        '<p class="lw-c-dice">Trayendo los datos de la pantalla</p>' +
        '<p class="lw-c-tarda">Sigue viniendo — la consulta esta tardando mas de lo normal</p>' +
      '</div>' +
      '<div class="lw-c-barra"><i></i></div>';
    document.body.appendChild(veloEl);
    var m = document.querySelector('main');
    if (m) m.setAttribute('aria-busy', 'true');
  }

  function quitaVelo() {
    veloMuerto = true;                      // que una consulta tardia no lo reponga
    /* La clase es lo que destapa el contenido (shell.css). Va ANTES del
       retorno de abajo a proposito: hay caminos que destapan sin que haya
       llegado a existir velo — una pantalla sin handler, o una sesion que no
       resolvio— y en todos ellos el contenido tiene que aparecer igual. */
    if (document.body) document.body.classList.add('lw-listo');
    var m = document.querySelector('main');
    if (m) m.removeAttribute('aria-busy');
    if (!veloEl) return;
    veloEl.classList.add('lw-c-fuera');     // 180 ms de fundido, y fuera
    var el = veloEl; veloEl = null;
    setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 260);
  }

  /* Cuenta una consulta. Devuelve la MISMA promesa: quien la llama sigue
     encadenando su `.then` exactamente igual que antes. */
  function vig(p) {
    enVuelo++;
    var baja = function () {
      enVuelo--;
      if (enVuelo > 0) return;
      setTimeout(function () { if (enVuelo === 0) quitaVelo(); }, 80);
    };
    p.then(baja, baja);
    return p;
  }

  function q(p, nombre, cont) {
    return vig(p).then(function (r) {
      if (r.error) { fallo(nombre, r.error, cont); return null; }
      return r.data || [];
    }, function (e) { fallo(nombre, e, cont); return null; });
  }
  function cnt(sb, tabla, mod, cols) {
    var qq = sb.from(tabla).select(cols || '*', { count: 'exact', head: true });
    if (mod) qq = mod(qq);
    /* La rama de rechazo no existia: un fallo de red aqui no daba `r.error`,
       lanzaba — y sin ella el contador del velo no bajaria nunca. */
    return vig(qq).then(function (r) { return r.error ? (fallo('count ' + tabla, r.error), null) : (r.count || 0); },
                        function (e) { fallo('count ' + tabla, e); return null; });
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
            pl.tbody.lastElementChild.setAttribute('data-moneda', f.moneda || 'EUR');
          });

          /* Chips de filtro: solo "Todos" y las dos divisas tienen un dato real
             detrás (`moneda`). "Reservas", "Estructura & Hitos" y "Honorarios
             notariales" son categorías del diseño de Stitch que no existen en
             ningún campo del recibí (no hay `categoria` ni se puede derivar
             del tipo de documento) — se dejan tal cual, sin fingir un filtro
             que no filtra nada; caen en el aviso genérico de maqueta.js hasta
             que se decida de dónde sale esa categoría. */
          var chipsMoneda = Array.prototype.slice.call(document.querySelectorAll('#filter-container .filter-chip')).filter(function (b) {
            var txt = b.textContent.replace(/\s+/g, ' ').trim();
            if (/^Todos/i.test(txt)) { b.setAttribute('data-chip-clave', 'todos'); return true; }
            if (/Divisa EUR/i.test(txt)) { b.setAttribute('data-chip-clave', 'EUR'); return true; }
            if (/Divisa IDR/i.test(txt)) { b.setAttribute('data-chip-clave', 'IDR'); return true; }
            return false;
          });
          cablearChipsFiltro(chipsMoneda, pl.tbody, 'tr[data-moneda]',
            function (btn) { return btn.getAttribute('data-chip-clave'); },
            'todos',
            function (fila2, clave) { return fila2.getAttribute('data-moneda') === clave; },
            null);   // el aspecto ya lo pinta el script propio de esta página (línea ~765)
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
        vig(sb.rpc('contratos_cobrado_equipo')).then(function (r) { return r.error ? (fallo('cobrado', r.error), null) : (r.data || []); }),
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
          var tr = pl.tbody.lastElementChild;
          tr.setAttribute('data-tiene-contrato', d ? '1' : '0');
          tr.setAttribute('data-en-firma', d && d.firma ? '1' : '0');
        });

        var chipsCompradores = ['todos', 'contrato', 'firma', 'prospectos'].map(function (k) {
          var sp = document.querySelector('[data-lw="cc-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);
        cablearChipsFiltro(chipsCompradores, pl.tbody, 'tr[data-tiene-contrato]',
          function (btn) { return btn.getAttribute('data-chip-clave'); },
          'todos',
          function (fila2, clave) {
            if (clave === 'contrato') return fila2.getAttribute('data-tiene-contrato') === '1';
            if (clave === 'firma') return fila2.getAttribute('data-en-firma') === '1';
            if (clave === 'prospectos') return fila2.getAttribute('data-tiene-contrato') === '0';
            return true;
          },
          function (btn, on) {
            btn.classList.toggle('bg-deep-lagoon', on);
            btn.classList.toggle('text-on-primary', on);
            btn.classList.toggle('font-semibold', on);
            btn.classList.toggle('bg-surface-container-low', !on);
            btn.classList.toggle('text-on-surface-variant', !on);
            btn.classList.toggle('font-medium', !on);
          });
      });
    },
    operaciones: function (sb) {
      var t = tablaPor([/OPERACI|CONTRATO/, /COMPRADOR/, /IMPORTE|ESTADO/]);
      Promise.all([
        q(sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,contrato_padre_id,created_at'), 'operaciones', t),
        vig(sb.rpc('contratos_cobrado_equipo')).then(function (r) { return r.error ? (fallo('cobrado', r.error), null) : (r.data || []); }),
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
        vig(sb.rpc('contratos_cobrado_equipo')).then(function (r) { if (r.error) { fallo('cobrado', r.error); return null; } return r.data || []; }),
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
      // FAM_P: firmado/cobrado por proyecto y familia (parcela/obra). FIRM_P:
      // firmado combinado por proyecto (para la barra sencilla de la tarjeta).
      // COVER_P: URL firmada de la foto de portada, si hay una subida.
      var FAM_P = {}, FIRM_P = {}, COVER_P = {};
      // COMPRADOR_ID_POR_CONTRATO: contrato_id -> client_id del Adquiriente I,
      // para el enlace directo a /compradores/ de cada parcela (11-sep-2026).
      var COMPRADOR_ID_POR_CONTRATO = {};
      var MOLDE = null, MOLDE_ENLACE = null, MOLDE_FAQ = null, MOLDE_UNIDAD = null;
      // Las unidades del proyecto abierto, por id, tal y como se pintaron.
      // Es lo que lee el editor del parcelario (editores.js) para abrir el
      // formulario ya relleno. Se vacía en cada repintado del cajón.
      var UNIDADES_CAJON = {};
      /* FUENTE ÚNICA del color y del nombre de cada estado de unidad
         (14-sep-2026). Antes este mapa pintaba SOLO la pastilla del parcelario
         y un comentario pedía «acuérdate de cambiar también los chips»: eso es
         una lista a mano en dos sitios, que en esta suite siempre acaba
         divergiendo. Ahora de aquí salen los tres sitios donde el estado se ve
         — el punto del chip de filtro, la pastilla de la tarjeta y su filo
         izquierdo — y no hay nada que sincronizar.

         Los colores se separaron por TONO, no por luminosidad (encargo del
         owner, 14-sep-2026: «marca más disponible / reservada / bloqueada para
         verlo de un vistazo»). Los seis de antes eran verde-oliva, teal,
         ciruela, teal oscuro, verde oscuro y gris: cuatro de ellos del mismo
         par de tonos y todos a la misma luminosidad, así que a tamaño de
         pastilla no se distinguían. Los tres estados que el equipo mira a
         diario pasan a leerse como un semáforo — verde libre, ámbar retenida
         blanda, rojo retenida dura — y los dos terminales (vendida, cobrada) se
         quedan en la familia teal de marca, que es donde ya vivían.

         Ámbar y rojo NO son inventados: son los colores «por significado» de la
         especificación visual de la suite (contexto/lawang_espec_visual.md,
         medidos del mockup 1a). */
      var ESTADO_COLOR = {
        disponible: '#485B37',     // verde territorial — libre, se puede vender
        reservada: '#8C5E10',      // ámbar de la espec — retención blanda (Carta de Reserva)
        bloqueada: '#9E2F26',      // rojo de la espec — retención dura (Bloqueo firmado)
        vendida: '#104C4F',        // deep lagoon — terminal
        cobrada: '#316669',        // secondary — terminal, cobrada al 100%
        no_disponible: '#75786e'   // outline — fuera de comercialización
      };
      // El nombre que se enseña. `estado` viene de la base con guión bajo
      // (`no_disponible`) y la pastilla lo escribía en mayúsculas tal cual:
      // «NO_DISPONIBLE». Mismo vocabulario que ESTADOS en la herramienta viva.
      var ESTADO_ETIQUETA = {
        disponible: 'Disponible', reservada: 'Reservada', bloqueada: 'Bloqueada',
        vendida: 'Vendida', cobrada: 'Cobrada', no_disponible: 'No disponible'
      };
      function claveEstado(e) { return String(e || '').trim().toLowerCase().replace(/\s+/g, '_'); }
      function colorEstado(e) { return ESTADO_COLOR[claveEstado(e)] || '#75786e'; }
      function etiquetaEstado(e) { return ESTADO_ETIQUETA[claveEstado(e)] || (e || '—'); }

      /* El punto de color de cada chip de filtro «Unidades». Se inyecta desde
         aquí y no se escribe en la HTML a propósito: marcaChip() reescribe el
         className entero del botón al cambiar de filtro — los hijos sobreviven,
         una clase de color no — y además así el color sigue saliendo del mapa
         de arriba y no de una segunda lista. */
      function pintaPuntosChips() {
        var cont = document.getElementById('chips-estado');
        if (!cont) return;
        cont.querySelectorAll('button[data-chip-u]').forEach(function (b) {
          var clave = b.getAttribute('data-chip-u');
          if (clave === 'todas' || b.querySelector('[data-lw-punto]')) return;
          var punto = document.createElement('span');
          punto.setAttribute('data-lw-punto', '1');
          punto.style.cssText = 'width:8px;height:8px;border-radius:999px;flex:0 0 auto;background:' + colorEstado(clave);
          b.insertBefore(punto, b.firstChild);
        });
      }

      /* LAW-186 (15-sep-2026): «Total Cartera Proyecto» sale de `unidades`, filtrado
         por `unidad_visible()` — visible a TODO agente con el proyecto asignado.
         «Total Cobrado»/firmado salen de contratos_equipo()/contratos_cobrado_equipo(),
         que desde el 11-sep filtran por es_suyo()+es_manager_de() — solo lo propio.
         Mismo proyecto, dos alcances distintos sin avisar en pantalla. Se decide NO
         tocar la RLS (privacidad ya cerrada el 11-sep a propósito) y en su lugar
         avisar cuándo el % no es el progreso real del proyecto: cuando quien mira no
         es manager de ESE proyecto ni admin/super_admin. `p.id` viene de la carga de
         `proyectos` (Promise.all de abajo); `MGRS` trae `proyectos_supervisados`. */
      function esMiProyecto(p) {
        if (window.LW_V4 && window.LW_V4.esAdmin) return true;
        var email = ((window.LW_V4 && window.LW_V4.miEmail) || '').toLowerCase();
        if (!email || !p) return false;
        return MGRS.some(function (m) {
          return (m.email || '').toLowerCase() === email &&
                 (m.proyectos_supervisados || []).indexOf(p.id) !== -1;
        });
      }

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
        // LAW-186: ver el porqué en el comentario de esMiProyecto() más arriba.
        // `vePropio` se calcula SIEMPRE, no solo si existe la nota — si dependiera
        // del `if` de abajo, un `notaAlcance` que no se encuentre (markup futuro
        // sin el elemento) dejaría `vePropio` en `undefined`, que las líneas de
        // abajo leerían como "no es tuyo" y pondrían "(tuyo)" hasta a un admin.
        var vePropio = esMiProyecto(elegido);
        var notaAlcance = document.querySelector('[data-lw="d-alcance-nota"]');
        if (notaAlcance) {
          notaAlcance.classList.toggle('hidden', vePropio);
          if (!vePropio) notaAlcance.textContent = '«Total Cobrado» y la barra son solo TUS contratos en este proyecto — «Total Cartera Proyecto» es el inventario completo del equipo.';
        }
        pon('d-master', elegido.parcela_master || 'sin registrar');
        pon('d-sup', elegido.parcela_master_m2 ? elegido.parcela_master_m2 + ' m² (' + d.t + ' parcelas)' : d.t + ' parcelas');
        pon('d-docs', (DOC_P[elegido.nombre] || 0) + ' documentos');

        /* Foto de portada en el Expediente, si hay una subida. */
        var imgCover = document.querySelector('[data-lw="d-cover-img"]');
        if (imgCover) {
          var urlCover = COVER_P[elegido.nombre];
          if (urlCover) { imgCover.src = urlCover; imgCover.classList.remove('hidden'); }
          else { imgCover.removeAttribute('src'); imgCover.classList.add('hidden'); }
        }

        /* Recaudación por familia (11-sep-2026) — ver comentario largo en el
           Promise.all de arriba. `d.suelo`/`d.obra` son la cartera REAL de
           `unidades` (catálogo, venda o no); `fam.parcela/obra` son lo firmado
           y lo cobrado por contratos de esa familia. Dos colores en la misma
           barra: oscuro = cobrado, claro = firmado sin cobrar todavía. */
        var fam = FAM_P[elegido.nombre] || { parcela: { firmado: 0, cobrado: 0 }, obra: { firmado: 0, cobrado: 0 }, sinAtribuir: 0 };
        var tieneSplit = (d.suelo || 0) + (d.obra || 0) > 0;
        var cajaDoble = document.getElementById('cajon-recaudacion-doble');
        var cajaSimple = document.getElementById('cajon-recaudacion-simple');
        var barraFamilia = function (clave, cartera, datos) {
          var firmPct = cartera ? Math.min(100, datos.firmado / cartera * 100) : 0;
          // Cobrado se clampa a 100%, NUNCA a firmPct (hallazgo de Desarrollo,
          // deploy del 11-sep): una Carta de Reserva puede cobrar ANTES de que
          // su Bloqueo esté bloqueado=true, así que cobrado > firmado es un
          // caso real, no un dato corrupto. Clamparlo a firmPct dejaba la
          // barra oscura en 0% con dinero de verdad ya cobrado — el texto de
          // al lado (d-*-cifras) decía el importe correcto y la barra lo
          // contradecía.
          var cobPct = cartera ? Math.min(100, datos.cobrado / cartera * 100) : 0;
          var elCob = document.querySelector('[data-barra="' + clave + '-cobrado"]');
          var elFir = document.querySelector('[data-barra="' + clave + '-firmado"]');
          if (elCob) elCob.style.width = cobPct + '%';
          if (elFir) elFir.style.width = Math.max(0, firmPct - cobPct) + '%';
          pon('d-' + clave + '-pct', cartera ? (Math.round(firmPct * 10) / 10) + '% firmado' + (vePropio ? '' : ' (tuyo)') : 'sin cartera registrada');
          pon('d-' + clave + '-cifras', cartera
            ? 'Cobrado ' + fmt(datos.cobrado, 'EUR') + ' · Firmado ' + fmt(datos.firmado, 'EUR') + ' · Total ' + fmt(cartera, 'EUR')
            : '—');
        };
        if (tieneSplit) {
          if (cajaDoble) cajaDoble.classList.remove('hidden');
          if (cajaSimple) cajaSimple.classList.add('hidden');
          barraFamilia('parcela', d.suelo || 0, fam.parcela);
          barraFamilia('obra', d.obra || 0, fam.obra);
        } else {
          // Sin precio_suelo/precio_construccion repartido: se cae a UNA barra
          // combinada de dos colores, sobre el total de `d.cartera` — mismo
          // criterio que la tarjeta, para no enseñar dos bloques vacíos.
          if (cajaDoble) cajaDoble.classList.add('hidden');
          if (cajaSimple) cajaSimple.classList.remove('hidden');
          var firmTotal = (fam.parcela.firmado || 0) + (fam.obra.firmado || 0);
          var firmPctS = d.cartera ? Math.min(100, firmTotal / d.cartera * 100) : 0;
          var cobPctS = d.cartera ? Math.min(100, cob / d.cartera * 100) : 0;
          var elCobS = document.querySelector('[data-barra="simple-cobrado"]');
          var elFirS = document.querySelector('[data-barra="simple-firmado"]');
          if (elCobS) elCobS.style.width = cobPctS + '%';
          if (elFirS) elFirS.style.width = Math.max(0, firmPctS - cobPctS) + '%';
          pon('d-pct2', 'Recaudado ' + (d.cartera ? (Math.round(cob / d.cartera * 1000) / 10) : 0) + '%' + (vePropio ? '' : ' (tuyo)'));
          pon('d-objetivo', 'Cartera ' + fmt(d.cartera, 'EUR'));
        }
        var notaSin = document.getElementById('cajon-nota-sin-atribuir');
        if (notaSin) {
          if (fam.sinAtribuir > 0) {
            notaSin.classList.remove('hidden');
            pon('d-sin-atribuir', fmt(fam.sinAtribuir, 'EUR') + ' cobrados sin Bloqueo de Parcela o Construcción asociado todavía (p. ej. una Carta de Reserva suelta) — no entran en las barras de arriba.');
          } else notaSin.classList.add('hidden');
        }

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
        // Molde cacheado UNA vez (11-sep-2026): antes se releía de
        // `firstElementChild` en cada apertura, así que un proyecto sin
        // enlaces dejaba el párrafo "no tiene enlaces" como único hijo, y el
        // SIGUIENTE proyecto clonaba ESE párrafo como si fuera la plantilla —
        // roto para cualquier apertura en secuencia. Mismo patrón que MOLDE
        // de la rejilla, arriba.
        if (!MOLDE_ENLACE && cajaE && cajaE.firstElementChild) MOLDE_ENLACE = cajaE.firstElementChild.cloneNode(true);
        if (cajaE && MOLDE_ENLACE) {
          var mE = MOLDE_ENLACE.cloneNode(true);
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
        if (!MOLDE_FAQ && cajaF && cajaF.firstElementChild) MOLDE_FAQ = cajaF.firstElementChild.cloneNode(true);
        if (cajaF && MOLDE_FAQ) {
          var mF = MOLDE_FAQ.cloneNode(true);
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
           elegido. `unidades_estado` es la vista que ya trae el contrato, el
           comprador y el cobrado partido en suelo/obra (unidad_parte_cobrada_split,
           11-sep-2026) — no se vuelve a cruzar ni repartir aquí a mano. */
        q(sb.from('unidades_estado').select('id,codigo,proyecto,tipo,modelo,estado,precio,precio_guardado,precio_suelo,precio_construccion,superficie_m2,moneda,notas,fase_masterplan,zona_masterplan,contrato_id,contrato_numero,comprador_nombre,contrato_firmado,cobrado_suelo,cobrado_obra,obra_firmada,contrato_creado_por')
            .eq('proyecto', elegido.nombre).order('codigo').limit(60), 'unidades de ' + elegido.nombre)
          .then(function (uu) {
            var caja = document.getElementById('d-unidades');
            if (!caja || uu == null) return;
            if (!MOLDE_UNIDAD && caja.firstElementChild) MOLDE_UNIDAD = caja.firstElementChild.cloneNode(true);
            if (!MOLDE_UNIDAD) return;
            var base = MOLDE_UNIDAD.cloneNode(true);
            caja.innerHTML = '';
            UNIDADES_CAJON = {}; window.LW_V4.unidades = UNIDADES_CAJON;
            pon('d-uds-n', uu.length + (uu.length === 1 ? ' unidad' : ' unidades'));
            if (!uu.length) {
              // grid-column entera: dentro de una rejilla, un aviso suelto se
              // quedaria encogido en la primera columna como si fuera una tarjeta.
              caja.innerHTML = '<p style="grid-column:1/-1;font:500 13px/1.5 sans-serif;color:#75786e;margin:0">' +
                'Este proyecto no tiene unidades dadas de alta.</p>';
              return;
            }
            // Barra de pago de UNA familia (suelo u obra) de UNA parcela.
            // «Firmado» es aquí un booleano ya resuelto por la base (contrato
            // bloqueado para el suelo, obra_firmada para la obra): se pinta la
            // familia entera como comprometida, sin inventar un prorrateo que
            // la base no da. El cobrado SÍ es la cifra exacta —
            // cobrado_suelo/cobrado_obra vienen partidos de
            // unidad_parte_cobrada_split, no se reparten aquí.
            var barraUnidad = function (f, clave, cartera, cobrado, firmado) {
              var firmPct = cartera ? (firmado ? 100 : 0) : 0;
              var cobPct = cartera ? Math.min(100, (Number(cobrado) || 0) / cartera * 100) : 0;
              var elCob = f.querySelector('[data-barra="u-' + clave + '-cobrado"]');
              var elFir = f.querySelector('[data-barra="u-' + clave + '-firmado"]');
              if (elCob) elCob.style.width = cobPct + '%';
              if (elFir) elFir.style.width = Math.max(0, firmPct - cobPct) + '%';
              pon('u-' + clave + '-txt', cartera ? fmt(cobrado, 'EUR') + ' / ' + fmt(cartera, 'EUR') : 'sin cartera', f);
            };
            uu.forEach(function (u) {
              var f = base.cloneNode(true);
              pon('u-codigo', u.codigo, f);
              pon('u-tipo', u.modelo || '—', f);
              /* Estado destacado (11-sep-2026) y reforzado el 14-sep-2026: la
                 pastilla sola no bastaba para leer una columna de parcelas de un
                 vistazo, así que el mismo color entra también por el filo
                 izquierdo de la tarjeta — que es lo que se ve al recorrer la
                 lista sin pararse a leer. Color y nombre salen de la fuente
                 única de arriba, la misma que pinta el punto de los chips. */
              var estadoColor = colorEstado(u.estado);
              var nota = f.querySelector('[data-lw="u-nota"]');
              if (nota) {
                nota.textContent = etiquetaEstado(u.estado).toUpperCase();
                nota.style.background = estadoColor;
              }
              f.style.borderLeft = '4px solid ' + estadoColor;
              /* La fila cruda se guarda para que el editor (editores.js) abra
                 con lo que ya está en pantalla, sin una segunda consulta que
                 podría traer otra cosa. `unidades_estado` ya trae las columnas
                 que el formulario escribe. */
              UNIDADES_CAJON[u.id] = u;
              var bEd = f.querySelector('[data-lw-accion="editar-unidad"]');
              if (bEd) { bEd.setAttribute('data-uid', u.id); bEd.title = 'Editar ' + (u.codigo || 'unidad'); }
              pon('u-total', u.precio != null ? fmt(u.precio, 'EUR') : '—', f);
              // Enlaces directos a la ficha del comprador y al contrato
              // (11-sep-2026, encargo del owner). Sin ficha/contrato detrás no
              // se pone href — un enlace a "#" es peor que texto sin subrayar.
              var elC = f.querySelector('[data-lw="u-comprador-link"]');
              if (elC) {
                elC.textContent = u.comprador_nombre || '—';
                var clienteId = u.contrato_id ? COMPRADOR_ID_POR_CONTRATO[u.contrato_id] : null;
                if (clienteId) { elC.href = '/intranet/compradores/?id=' + clienteId; elC.target = '_blank'; }
                else { elC.removeAttribute('href'); elC.removeAttribute('target'); elC.style.cursor = 'default'; elC.style.textDecoration = 'none'; }
              }
              var elK = f.querySelector('[data-lw="u-contrato-link"]');
              if (elK) {
                elK.textContent = u.contrato_numero || 'sin contrato';
                if (u.contrato_numero) { elK.href = '/intranet/v4/contratos/?contrato=' + encodeURIComponent(u.contrato_numero); elK.target = '_blank'; }
                else { elK.removeAttribute('href'); elK.removeAttribute('target'); elK.style.cursor = 'default'; elK.style.textDecoration = 'none'; }
              }
              barraUnidad(f, 'suelo', Number(u.precio_suelo) || 0, u.cobrado_suelo, !!u.contrato_firmado);
              barraUnidad(f, 'obra', Number(u.precio_construccion) || 0, u.cobrado_obra, !!u.obra_firmada);
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
      /* Lo que el editor del parcelario necesita de esta pantalla, y nada
         más: las unidades pintadas y el color/nombre de cada estado, para
         que el formulario enseñe el MISMO código de color que la lista. */
      window.LW_V4.unidades = UNIDADES_CAJON;
      window.LW_V4.estadoColor = colorEstado;
      window.LW_V4.estadoEtiqueta = etiquetaEstado;
      window.LW_V4.estados = ESTADO_ETIQUETA;
      // email -> nombre del equipo. Lo necesita el editor del parcelario para
      // no ensenar el correo del agente justo al lado de la tarjeta que ya
      // ensena su nombre. Cuenta legacy sin ficha: se queda el email, igual
      // que hace la herramienta viva.
      window.LW_V4.equipoNombre = EQUIPO_NOMBRE;

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
          // LAW-186: "tuyo" avisa de que cob es SOLO lo cobrado por quien mira,
          // no lo del proyecto entero, cuando no es su manager ni admin — ver
          // esMiProyecto() más arriba.
          pon('pct', d.cartera ? (Math.round(cob / d.cartera * 1000) / 10) + '% cobrado' + (esMiProyecto(p) ? '' : ' (tuyo)') : 'sin cartera', c);
          pon('master', p.parcela_master || '—', c);
          // Dos colores en la misma barra (11-sep-2026): oscuro = cobrado,
          // claro = firmado (bloqueado=true) pero todavía sin cobrar. FIRM_P
          // es el firmado de Parcela+Construcción combinado — el desglose por
          // familia vive en el cajón, donde hay sitio para dos barras.
          var firmado = FIRM_P[p.nombre] || 0;
          var firmPct = d.cartera ? Math.min(100, firmado / d.cartera * 100) : 0;
          var cobPct = d.cartera ? Math.min(100, cob / d.cartera * 100) : 0;
          var bCob = c.querySelector('[data-barra="cobrado"]'), bFir = c.querySelector('[data-barra="firmado"]');
          if (bCob) bCob.style.width = cobPct + '%';
          if (bFir) bFir.style.width = Math.max(0, firmPct - cobPct) + '%';
          // Foto de portada, si se ha subido una desde "Editar proyecto";
          // si no, se queda el degradado + la decoración de fábrica.
          var cover = c.querySelector('[data-lw="cover"]');
          var coverUrl = COVER_P[p.nombre];
          if (cover && coverUrl) {
            cover.style.backgroundImage = 'url(' + coverUrl.replace(/'/g, '%27') + ')';
            c.querySelectorAll('[data-lw-deco]').forEach(function (x) { x.style.display = 'none'; });
            var ov = c.querySelector('[data-lw-cover-overlay]'); if (ov) ov.classList.remove('hidden');
          }
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

      /* Pestañas Enlaces / FAQ del cajón (11-sep-2026, encargo del owner: antes
         iban a dos columnas, ahora se conmutan). DOM estático desde la carga
         de la página —no depende de qué proyecto esté abierto—, así que se
         cablea UNA vez, no en cada abrirCajon(). */
      function wireTabsDoc() {
        var cont = document.getElementById('cajon-tabs-doc');
        if (!cont) return;
        var botones = cont.querySelectorAll('[data-tab-btn]');
        var activo = botones[0] ? botones[0].className : '';
        var inactivo = botones[1] ? botones[1].className : '';
        cont.querySelectorAll('[data-tab-btn]').forEach(function (b) {
          b.addEventListener('click', function () {
            var clave = b.getAttribute('data-tab-btn');
            cont.querySelectorAll('[data-tab-btn]').forEach(function (b2) {
              b2.className = b2.getAttribute('data-tab-btn') === clave ? activo : inactivo;
            });
            document.querySelectorAll('[data-tab-panel]').forEach(function (p) {
              p.classList.toggle('hidden', p.getAttribute('data-tab-panel') !== clave);
            });
          });
        });
      }

      function wireControles() {
        var contP = document.getElementById('chips-proyecto');
        var contU = document.getElementById('chips-estado');
        var clasesP = chipClases(contP), clasesU = chipClases(contU);
        pintaPuntosChips();
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
        q(sb.from('usuarios').select('email,nombre'), 'equipo'),
        /* Firmado/cobrado POR FAMILIA (11-sep-2026, encargo del owner: separar
           Parcela de Construcción, y dentro de cada barra separar firmado de
           cobrado). Mismas dos RPC que ya usan operaciones/compradores en
           este fichero — nunca `.from('contratos')` a pelo, por el mismo
           motivo que `facturas_equipo` de arriba: RLS por agente. */
        q(sb.rpc('contratos_equipo').select('id,tipo,precio_total,moneda,bloqueado,proyecto_nombre,contrato_padre_id'), 'contratos (familia)'),
        vig(sb.rpc('contratos_cobrado_equipo')).then(function (r2) { return r2.error ? (fallo('cobrado por contrato', r2.error), []) : (r2.data || []); }),
        /* Foto de portada de cada proyecto (11-sep-2026): la más reciente de
           categoria='portada' por proyecto. Es documentos_proyecto + el bucket
           'documentacion' de siempre (Regla 0 — nunca una tabla/bucket nuevo
           para lo que ya tiene sitio), nunca una columna imagen_url en
           `proyectos`: si el cliente puede subir varias, la fuente es la
           lista, no un campo suelto que la próxima portada pisaría en silencio. */
        q(sb.from('documentos_proyecto').select('proyecto,path,creado_en').eq('categoria', 'portada').order('creado_en', { ascending: false }), 'portadas'),
        /* Adquiriente I de cada contrato (11-sep-2026): para el enlace directo
           a /compradores/ desde cada parcela. `contrato_compradores` no tiene
           RLS por autoría (solo es_agente()), así que se lee entero una vez,
           igual que managers/equipo de arriba. */
        q(sb.from('contrato_compradores').select('contrato_id,client_id').eq('rol', 'adquiriente_1'), 'compradores por contrato')
      ]).then(function (r) {
        var ps = r[0], us = r[1] || [], fs = r[2] || [], ds = r[3] || [], mgrs = r[4] || [], eq = r[5] || [];
        var cts = r[6] || [], cobPorContrato = r[7] || [], portadas = r[8] || [], adq1 = r[9] || [];
        if (!ps) return;
        COMPRADOR_ID_POR_CONTRATO = {};
        adq1.forEach(function (x) { COMPRADOR_ID_POR_CONTRATO[x.contrato_id] = x.client_id; });
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
          d.suelo += Number(u.precio_suelo || 0); d.obra += Number(u.precio_construccion || 0);
        });
        var cobrado = 0, facturado = 0;
        COB_P = {};
        fs.forEach(function (f) {
          if (f.anulada || (f.moneda || 'EUR') !== 'EUR') return;
          if (f.tipo === 'recibi') { cobrado += Number(f.total || 0); var k = f.proyecto_nombre || ''; COB_P[k] = (COB_P[k] || 0) + Number(f.total || 0); }
          else if (f.tipo === 'factura') facturado += Number(f.total || 0);
        });
        DOC_P = {}; ds.forEach(function (d) { DOC_P[d.proyecto] = (DOC_P[d.proyecto] || 0) + 1; });

        /* --- FAM_P: firmado/cobrado por familia (parcela/obra), 11-sep-2026 ---
           `reserva_parcela` es el Bloqueo de Parcela (suelo); `construccion` y
           `cc00014_timon` son obra (contexto/suite_lawang.md → "El modelo de
           venta"). Una Carta de Reserva es PRELIMINAR: su precio no suma nunca
           (lwEsPreliminar, igual que en operaciones/compradores), pero su
           COBRADO sí es dinero real — se le busca la familia subiendo por
           `contrato_padre_id` hasta el Bloqueo del que cuelga («la Carta
           cuelga del Bloqueo», LAW-51/LAW-50). Si no tiene padre resuelto (o
           es un tipo fuera de las dos familias, como `contrato_general`), el
           cobrado no se pierde: va a `sinAtribuir` y se dice en el cajón en
           vez de desaparecer sin explicación. */
        var FAMILIA_TIPO = { reserva_parcela: 'parcela', construccion: 'obra', cc00014_timon: 'obra' };
        var porIdContrato = {}; cts.forEach(function (c) { porIdContrato[c.id] = c; });
        function familiaDe(c, visto) {
          visto = visto || {};
          if (!c || visto[c.id]) return null;
          visto[c.id] = true;
          if (FAMILIA_TIPO[c.tipo]) return FAMILIA_TIPO[c.tipo];
          if ((typeof lwEsPreliminar === 'function') && lwEsPreliminar(c.tipo) && c.contrato_padre_id) {
            return familiaDe(porIdContrato[c.contrato_padre_id], visto);
          }
          return null;
        }
        var cobPorId = {}; cobPorContrato.forEach(function (x) { cobPorId[x.contrato_id] = Number(x.cobrado) || 0; });
        FAM_P = {}; FIRM_P = {};
        cts.forEach(function (c) {
          if ((c.moneda || 'EUR') !== 'EUR') return;
          var k = c.proyecto_nombre || '';
          var f = FAM_P[k] = FAM_P[k] || { parcela: { firmado: 0, cobrado: 0 }, obra: { firmado: 0, cobrado: 0 }, sinAtribuir: 0 };
          var fam = familiaDe(c);
          var esPre = (typeof lwEsPreliminar === 'function') && lwEsPreliminar(c.tipo);
          var cobradoC = cobPorId[c.id] || 0;
          if (fam) {
            if (!esPre && c.bloqueado) {
              f[fam].firmado += Number(c.precio_total) || 0;
              FIRM_P[k] = (FIRM_P[k] || 0) + (Number(c.precio_total) || 0);
            }
            f[fam].cobrado += cobradoC;
          } else {
            f.sinAtribuir += cobradoC;
          }
        });

        /* --- Foto de portada: la más reciente por proyecto, en signed URLs
           de una sola tirada (createSignedUrls admite un array de paths —
           evita N llamadas por N tarjetas). Bucket 'documentacion' es
           privado: sin URL firmada no hay <img> que la enseñe. */
        var PORTADA_PATH = {};
        portadas.forEach(function (d2) { if (!PORTADA_PATH[d2.proyecto]) PORTADA_PATH[d2.proyecto] = d2.path; });
        COVER_P = {};
        var pathsPortada = Object.keys(PORTADA_PATH).map(function (k) { return PORTADA_PATH[k]; });
        (pathsPortada.length ? sb.storage.from('documentacion').createSignedUrls(pathsPortada, 3600) : Promise.resolve({ data: [] }))
          .then(function (rs) {
            var porPath = {};
            (rs.data || []).forEach(function (x) { if (x.signedUrl) porPath[x.path] = x.signedUrl; });
            Object.keys(PORTADA_PATH).forEach(function (k) {
              var url = porPath[PORTADA_PATH[k]];
              if (url) COVER_P[k] = url;
            });
            renderizar();
            // Si el cajón ya estaba abierto cuando llegan las URLs firmadas
            // (llegan async, después del primer render), se refresca sin
            // reabrir ni empujar la URL — solo para que la portada aparezca.
            var actual = window.LW_V4 && window.LW_V4.proyecto;
            if (actual) abrirCajon(actual.nombre, { mostrar: false, empujarUrl: false });
          });

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
        wireTabsDoc();
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
        q(sb.from('modelos').select('id,slug,nombre,dormitorios,banos,villa_m2,terraza_m2,descripcion,precio_construccion,moneda,publicado,activo,renders_pendientes,alcance,notas,orden').order('orden', { ascending: true, nullsFirst: false }), 'modelos'),
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
          /* Para los chips de filtro (Publicados/Sin ficha/Sin render): las tres
             categorías se solapan (un modelo puede estar publicado Y sin
             render a la vez), así que van en tres atributos, no en un único
             "estado". */
          c.setAttribute('data-publicados', m.publicado ? '1' : '0');
          c.setAttribute('data-sinficha', sinFicha(m) ? '1' : '0');
          c.setAttribute('data-sinrender', m.renders_pendientes ? '1' : '0');
          c.style.cursor = 'pointer';
          c.addEventListener('click', function () { location.search = '?modelo=' + encodeURIComponent(m.slug || m.nombre); });
          grid.appendChild(c);
        });

        var chipsModelos = ['todos', 'publicados', 'sinficha', 'sinrender'].map(function (k) {
          var sp = document.querySelector('[data-lw="c-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);
        cablearChipsFiltro(chipsModelos, grid, '[data-publicados]',
          function (btn) { return btn.getAttribute('data-chip-clave'); },
          'todos',
          function (fila, clave) { return fila.getAttribute('data-' + clave) === '1'; },
          function (btn, on) {
            btn.classList.toggle('bg-primary-container', on);
            btn.classList.toggle('text-on-primary', on);
            btn.classList.toggle('bg-surface-container-low', !on);
            btn.classList.toggle('text-on-surface-variant', !on);
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
        q(sb.from('usuarios').select('user_id,nombre,email,rol,activo,herramientas,proyectos,tipos_contrato').order('nombre'), 'usuarios', t),
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
            var tr = pl.tbody.lastElementChild;
            tr.setAttribute('data-rol', u.rol || '');
            tr.setAttribute('data-herr', ' ' + (u.herramientas || []).join(' ') + ' ');
          });

          /* Los chips "Legal/Obra/Sales/Finance" del diseño de Stitch se
             renombraron el 15-sep (hallazgo de Legal): no corresponden a
             ningún valor real de `usuarios.rol` (solo existen
             super_admin/admin/agente, ver migración 20260729090521), así que
             llamarlos por un departamento inducía a leer un PERMISO de
             herramienta como si fuera la función de la persona. Ahora dicen
             qué filtran de verdad — acceso a esa herramienta, mismo mapeo que
             ya usa la matriz de abajo (m1-m4). "Super Admin" sí es un rol
             real: filtra por igualdad exacta, no se mezcla con "admin". */
          var mapaRolChip = { legal: 'contratos', obra: 'unidades', sales: 'compradores', finance: 'facturas' };
          function coincideChipUsuario(fila2, clave) {
            if (clave === 'admin') return fila2.getAttribute('data-rol') === 'super_admin';
            if (fila2.getAttribute('data-rol') === 'super_admin') return true;
            var h = mapaRolChip[clave];
            return !!h && fila2.getAttribute('data-herr').indexOf(' ' + h + ' ') !== -1;
          }
          var chipsUsuarios = Array.prototype.slice.call(document.querySelectorAll('[data-role]'));
          /* Hallazgo de Administración, 15-sep: el número entre paréntesis de
             cada chip venía fijo del mockup de Stitch ("Todos (16)"…) y nunca
             se refrescaba — un chip que ya filtra de verdad pero enseña un
             recuento falso al lado es MÁS engañoso que uno que no filtraba
             nada. Se recalcula aquí, sobre las filas ya pintadas. */
          chipsUsuarios.forEach(function (btn) {
            var clave = btn.getAttribute('data-role');
            var n = clave === 'all' ? us.length : us.filter(function (u) {
              return coincideChipUsuario({ getAttribute: function (k) { return k === 'data-rol' ? (u.rol || '') : (' ' + (u.herramientas || []).join(' ') + ' '); } }, clave);
            }).length;
            btn.textContent = btn.textContent.replace(/\(\s*[^)]*\s*\)\s*$/, '(' + n + ')');
          });
          cablearChipsFiltro(chipsUsuarios, pl.tbody, 'tr[data-rol]',
            function (btn) { return btn.getAttribute('data-role'); },
            'all',
            coincideChipUsuario,
            function (btn, on) {
              btn.classList.toggle('bg-territorial-green', on);
              btn.classList.toggle('text-on-primary', on);
              btn.classList.toggle('shadow-sm', on);
              btn.classList.toggle('bg-surface-container-lowest', !on);
              btn.classList.toggle('text-on-surface-variant', !on);
              btn.classList.toggle('hover:bg-surface-container-high', !on);
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
          f.setAttribute('data-estado-hilo', h.estado || '');
          f.style.cursor = 'pointer';
          f.addEventListener('click', function () { location.search = '?hilo=' + encodeURIComponent(h.id); });
          lista.appendChild(f);
        });

        var chipsSoporte = ['todos', 'abiertos', 'espera'].map(function (k) {
          var sp = document.querySelector('[data-lw="c-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);
        cablearChipsFiltro(chipsSoporte, lista, '[data-estado-hilo]',
          function (btn) { return btn.getAttribute('data-chip-clave'); },
          'todos',
          function (fila, clave) {
            var e = fila.getAttribute('data-estado-hilo') || '';
            return clave === 'abiertos' ? e === 'abierto' : /espera/.test(e);
          },
          function (btn, on) {
            btn.classList.toggle('bg-primary', on);
            btn.classList.toggle('text-on-primary', on);
            btn.classList.toggle('font-semibold', on);
            btn.classList.toggle('bg-surface-container-low', !on);
            btn.classList.toggle('text-on-surface-variant', !on);
            btn.classList.toggle('hover:bg-surface-container-high', !on);
            btn.classList.toggle('transition-colors', !on);
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
        pon2('h-toggle-estado', el.estado === 'abierto' ? 'Marcar resuelto' : 'Reabrir');
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


  /* ══════════════ las tres que la maqueta no tenia (14-sep-2026) ══════════════
     CRM, Solicitudes y Cuentas ya estaban vivas en /intranet/ y la v4 se habia
     quedado atras. Sus pantallas se construyeron con la cascara de `modelos/` y
     sus anclas son `data-lw` propias — no hace falta el rastreo por TEXTO que
     usan las pantallas heredadas de Stitch. Siguen las mismas reglas de la
     cabecera de este fichero: solo lectura, importes por `lwFormatoImporte`,
     fallo ruidoso, y el marcado no trae ni un dato real (este repo es publico:
     lo real entra aqui, en tiempo de ejecucion y detras de guard.js). */

  function diasDesde(x) { return x ? Math.floor((Date.now() - new Date(x).getTime()) / 86400000) : null; }

  /* El CRM ya no tiene pantalla en la v4: conserva su vista propia en
     /intranet/leads/ (owner, 14-sep-2026). Su handler vivio aqui unas horas
     y se retira con la pantalla — un REG que nadie puede disparar es codigo
     muerto que el siguiente lee como si contara algo. Recuperable en git
     (commit baa6291) si la v4 llega a absorber el CRM algun dia. */

  /* ---------- Comisiones (antes «Solicitudes de pago», renombrada 14-sep-2026) ----------
     Dos pestañas, dos tablas, dos orígenes de datos — nunca se mezclan en una lista, o el
     lector no podría distinguir lo que Lawang paga de lo que el equipo se reparte entre sí:
      · «A Lawang» = `solicitudes_pago`, igual que antes — con una marca visual para las
        que nacieron solas (`origen='comision_automatica'`, el alta automática de una
        comisión de nivel manager) frente a las que escribió un agente a mano.
      · «Reparto de equipo» = `comisiones_devengadas` con `nivel='closer'`. La RLS ya filtra
        qué fila ve cada sesión (closer: la suya; manager: las de su equipo; admin: todas) —
        aquí solo se pinta y se decide si tiene sentido ENSEÑAR el botón «Marcar pagada»: el
        gate real es la policy de UPDATE (`_equipo_de_condicion_comision` + `equipo_miembros`
        activo), esto solo lo refleja. `equipos_venta` y `equipo_miembros` son de lectura
        abierta (`qual=true`) a propósito: sin eso un manager no podría saber qué closers son
        «su equipo» para decidir si pintar el botón. */
  var RESUELTAS = ['pagada', 'rechazada', 'anulada'];
  var ETIQUETA = { pendiente: 'Pendiente', aprobada: 'Aprobada', rechazada: 'Rechazada', anulada: 'Anulada', pagada: 'Pagada' };
  var ETIQUETA_EQ = { pendiente: 'Pendiente', pagada: 'Pagada', en_disputa: 'En disputa' };
  var TAGCLASE_EQ = { pendiente: 'bg-error-container/60 text-error', pagada: 'bg-primary-container/30 text-territorial-green', en_disputa: 'bg-burnt-earth/15 text-burnt-earth' };

  function miembroActivo(em, hoyISO) { return em.desde <= hoyISO && (!em.hasta || em.hasta >= hoyISO); }

  REG.comisiones = function (sb) {
    var tabla = document.getElementById('lw-filas');
    var caja = tabla ? tabla.closest('section') : null;
    var tablaEq = document.getElementById('lw-filas-equipo');
    var cajaEq = tablaEq ? tablaEq.closest('section') : null;

    Promise.all([
      q(sb.from('solicitudes_pago').select('numero,concepto,importe,moneda,estado,creado_en,creado_por,contrato_id,pagado_en,origen').order('creado_en', { ascending: false }), 'solicitudes de pago', caja),
      q(sb.from('contratos').select('id,numero,tipo,proyecto_nombre'), 'contratos'),
      /* Si la RLS de `usuarios` solo deja leer la propia ficha, el mapa se queda
         corto y el fallback pinta «—»: no es un fallo, es lo que esa sesion ve. */
      q(sb.from('usuarios').select('user_id,nombre,email'), 'usuarios'),
      q(sb.from('comisiones_devengadas').select('id,contrato_raiz_id,beneficiario_email,nivel,importe,moneda,estado,disparado_en,pagado_por,pagado_en').eq('nivel', 'closer').order('disparado_en', { ascending: false }), 'reparto de equipo', cajaEq),
      q(sb.from('equipos_venta').select('id,nombre,manager_email,activo'), 'equipos de venta'),
      q(sb.from('equipo_miembros').select('equipo_id,closer_email,desde,hasta'), 'miembros de equipo')
    ]).then(function (r) {
      var ss = r[0], contratosRows = r[1] || [], usuariosRows = r[2] || [], cd = r[3], eqs = r[4] || [], miembros = r[5] || [];
      var ct = {}; contratosRows.forEach(function (c) { ct[c.id] = c; });
      var us = {}; usuariosRows.forEach(function (u) { us[u.user_id] = u; });
      var porEmail = {}; usuariosRows.forEach(function (u) { if (u.email) porEmail[u.email.toLowerCase()] = u; });

      if (ss) pintaLawang(ss);
      if (cd) pintaEquipo(cd, eqs, miembros);

      function pintaLawang(ss) {
        var pend = ss.filter(function (x) { return x.estado === 'pendiente'; });
        var aprob = ss.filter(function (x) { return x.estado === 'aprobada'; });
        /* Suma por moneda y NUNCA entre monedas: 500 EUR + 500 USD no son «1.000
           nada» (regla del modelo de venta, `contexto/patrones_tecnicos.md`). */
        var porMoneda = {};
        aprob.forEach(function (x) { var m = x.moneda || 'EUR'; porMoneda[m] = (porMoneda[m] || 0) + (Number(x.importe) || 0); });
        var sumas = Object.keys(porMoneda).sort().map(function (m) { return fmt(porMoneda[m], m); }).join(' · ');
        var pagadasMes = ss.filter(function (x) { return x.estado === 'pagada' && x.pagado_en && new Date(x.pagado_en) >= mesIni; });
        var tarde = ss.filter(function (x) {
          return (x.estado === 'pendiente' || x.estado === 'aprobada') && diasDesde(x.creado_en) >= 14;
        });

        pon2('k-pendientes', String(pend.length));
        pon2('k-pendientes-pie', pend.length ? 'la mas vieja lleva ' + diasDesde(pend[pend.length - 1].creado_en) + ' dias' : 'nada esperando');
        pon2('k-aprobadas', String(aprob.length));
        pon2('k-aprobadas-pie', aprob.length ? sumas : 'nada aprobado sin pagar');
        pon2('k-pagadas', String(pagadasMes.length));
        pon2('k-pagadas-pie', 'desde el 1 de mes');
        pon2('k-tarde', String(tarde.length));
        pon2('k-tarde-pie', tarde.length ? 'pendientes o aprobadas sin cerrar' : 'nada atascado');

        pon2('c-todas', String(ss.length));
        pon2('c-pendiente', String(pend.length));
        pon2('c-aprobada', String(aprob.length));
        pon2('c-resueltas', String(ss.filter(function (x) { return RESUELTAS.indexOf(x.estado) >= 0; }).length));

        if (!tabla) return;
        if (!ss.length) {
          tabla.innerHTML = '<tr><td colspan="8" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Ninguna solicitud registrada.</td></tr>';
          return;
        }
        tabla.innerHTML = ss.slice(0, 25).map(function (x) {
          var c = ct[x.contrato_id]; var u = us[x.creado_por];
          /* Marca visual: solo las nacidas solas de una comisión de manager llevan
             el badge — el resto (`origen='manual'`) es lo que ya se veía antes. */
          var origenHtml = x.origen === 'comision_automatica'
            ? '<span style="display:inline-flex;align-items:center;gap:4px;padding:2px 9px;border-radius:999px;background:#104C4F;color:#fff;font:600 10.5px \'Neue Kabel\',sans-serif;text-transform:uppercase;letter-spacing:.04em"><span class="material-symbols-outlined" style="font-size:13px;line-height:1">bolt</span>Automática</span>'
            : '<span style="font:500 11px \'Neue Kabel\',sans-serif;color:#8A8474">Manual</span>';
          return '<tr class="border-b border-outline-variant/30" data-estado="' + esc(x.estado) + '">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface"><b>SP-' + esc(x.numero) + '</b></td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(u ? (u.nombre || u.email) : '—') + '</td>' +
            '<td class="px-5 py-4">' + origenHtml + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(x.concepto || '—') + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(fmt(x.importe, x.moneda || 'EUR')) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(c ? [c.numero, tipoC(c.tipo), c.proyecto_nombre].filter(Boolean).join(' · ') : '—') + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full bg-surface-container-high font-label-md text-[11px] uppercase tracking-wider">' + esc(ETIQUETA[x.estado] || x.estado) + '</span></td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline text-right">' + diasDesde(x.creado_en) + ' d</td>' +
            '</tr>';
        }).join('');

        var chipsComisiones = ['todas', 'pendiente', 'aprobada', 'resueltas'].map(function (k) {
          var sp = document.querySelector('[data-lw="c-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);
        cablearChipsFiltro(chipsComisiones, tabla, 'tr[data-estado]',
          function (btn) { return btn.getAttribute('data-chip-clave'); },
          'todas',
          function (fila, clave) {
            return clave === 'resueltas' ? RESUELTAS.indexOf(fila.getAttribute('data-estado')) >= 0
                                          : fila.getAttribute('data-estado') === clave;
          },
          function (btn, on) {
            btn.classList.toggle('bg-primary-container', on);
            btn.classList.toggle('text-on-primary', on);
            btn.classList.toggle('bg-surface-container-low', !on);
            btn.classList.toggle('text-on-surface-variant', !on);
          });
      }

      function pintaEquipo(cd, eqs, miembros) {
        var hoyISO = new Date().toISOString().slice(0, 10);
        var miEmail = ((window.LW_V4 && window.LW_V4.miEmail) || '').toLowerCase();
        var esAdminSesion = !!(window.LW_V4 && window.LW_V4.esAdmin);

        var miEquipoIds = eqs.filter(function (e) { return (e.manager_email || '').toLowerCase() === miEmail; }).map(function (e) { return e.id; });
        var misCloserEmails = {};
        miembros.forEach(function (em) {
          if (miEquipoIds.indexOf(em.equipo_id) !== -1 && miembroActivo(em, hoyISO)) misCloserEmails[(em.closer_email || '').toLowerCase()] = true;
        });
        // equipo ACTUAL de cada closer (columna «Equipo» + filtro): membresía activa hoy.
        var eqPorId = {}; eqs.forEach(function (e) { eqPorId[e.id] = e; });
        var equipoDe = {};
        miembros.forEach(function (em) {
          if (!miembroActivo(em, hoyISO)) return;
          var e = eqPorId[em.equipo_id]; if (!e) return;
          equipoDe[(em.closer_email || '').toLowerCase()] = e.nombre;
        });

        var pend = cd.filter(function (x) { return x.estado === 'pendiente'; }).length;
        var pag = cd.filter(function (x) { return x.estado === 'pagada'; }).length;
        var disp = cd.filter(function (x) { return x.estado === 'en_disputa'; }).length;
        pon2('ceq-todos', String(cd.length));
        pon2('ceq-pendiente', String(pend));
        pon2('ceq-pagada', String(pag));
        pon2('ceq-en_disputa', String(disp));

        // selector de equipos: solo los que de verdad aparecen en este reparto
        var selEq = document.getElementById('lw-eq-equipo');
        if (selEq && selEq.options.length <= 1) {
          var nombres = {};
          cd.forEach(function (x) { var n = equipoDe[(x.beneficiario_email || '').toLowerCase()]; if (n) nombres[n] = true; });
          Object.keys(nombres).sort().forEach(function (n) {
            var o = document.createElement('option'); o.value = n; o.textContent = n; selEq.appendChild(o);
          });
        }

        if (!tablaEq) return;
        if (!cd.length) {
          tablaEq.innerHTML = '<tr><td colspan="7" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Nada que repartir todavía — aquí aparecerá cada comisión de closer en cuanto se devengue una.</td></tr>';
          return;
        }
        /* El registro va por ID, nunca por nombre (esc() no basta contra comillas
           dentro de un `onclick` de string): `marcarComisionPagada` solo recibe el
           id y busca la etiqueta aquí. */
        window.LW_V4 = window.LW_V4 || {};
        window.LW_V4.comisionesPorId = {};
        tablaEq.innerHTML = cd.slice(0, 150).map(function (x) {
          var email = x.beneficiario_email || '';
          var u = porEmail[email.toLowerCase()];
          var etiqueta = u ? (u.nombre || email) : email;
          var c = ct[x.contrato_raiz_id];
          var equipoNombre = equipoDe[email.toLowerCase()] || '—';
          window.LW_V4.comisionesPorId[x.id] = { etiqueta: etiqueta };
          var puedeMarcar = x.estado === 'pendiente' && (esAdminSesion || misCloserEmails[email.toLowerCase()]);
          var accion = puedeMarcar
            ? '<button type="button" data-eq-pagar="' + esc(x.id) + '" style="padding:7px 16px;border-radius:999px;border:0;background:#104C4F;color:#fff;font:600 12px \'Neue Kabel\',sans-serif;cursor:pointer">Marcar pagada</button>'
            : '<span style="font:500 12px \'Neue Kabel\',sans-serif;color:#8A8474">—</span>';
          return '<tr class="border-b border-outline-variant/30" data-eq-estado="' + esc(x.estado) + '" data-eq-equipo="' + esc(equipoNombre) + '">' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(etiqueta) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(equipoNombre) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(fmt(x.importe, x.moneda || 'EUR')) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(c ? [c.numero, tipoC(c.tipo), c.proyecto_nombre].filter(Boolean).join(' · ') : '—') + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' + (TAGCLASE_EQ[x.estado] || 'bg-surface-container-high') + '">' + esc(ETIQUETA_EQ[x.estado] || x.estado) + '</span></td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + fFecha(x.disparado_en) + '</td>' +
            '<td class="px-5 py-4 text-right">' + accion + '</td>' +
            '</tr>';
        }).join('');

        cablearFiltrosEquipo();
      }

      /* ---------- filtro de la pestaña «Reparto de equipo» ----------
         Puramente cliente: las filas ya están todas pintadas (la RLS ya decidió
         cuáles llegan), esto solo enseña/oculta. Se cablea una vez por carga de
         página — no hay repintado de esta tabla salvo recarga completa. */
      function cablearFiltrosEquipo() {
        var buscar = document.getElementById('lw-eq-buscar');
        var selEq = document.getElementById('lw-eq-equipo');
        var chips = document.querySelectorAll('.lw-eq-chip');
        if (!tablaEq || tablaEq.getAttribute('data-filtros-listos')) return;
        tablaEq.setAttribute('data-filtros-listos', '1');
        var filtroEstado = 'todos';
        function aplica() {
          var q = (buscar && buscar.value || '').toLowerCase();
          var eq = selEq ? selEq.value : '';
          tablaEq.querySelectorAll('tr[data-eq-estado]').forEach(function (tr) {
            var okEstado = filtroEstado === 'todos' || tr.getAttribute('data-eq-estado') === filtroEstado;
            var okEquipo = !eq || tr.getAttribute('data-eq-equipo') === eq;
            var okTexto = !q || tr.textContent.toLowerCase().indexOf(q) !== -1;
            tr.style.display = (okEstado && okEquipo && okTexto) ? '' : 'none';
          });
        }
        if (buscar) buscar.addEventListener('input', aplica);
        if (selEq) selEq.addEventListener('change', aplica);
        chips.forEach(function (b) {
          b.addEventListener('click', function (ev) {
            ev.stopPropagation();   // si no, maqueta.js la ve pasar y avisa «sin cablear»
            filtroEstado = b.getAttribute('data-eq-f') || 'todos';
            chips.forEach(function (h) {
              var on = h === b;
              h.classList.toggle('bg-primary-container', on);
              h.classList.toggle('text-on-primary', on);
              h.classList.toggle('bg-surface-container-low', !on);
              h.classList.toggle('text-on-surface-variant', !on);
            });
            aplica();
          });
        });
        // clic en «Marcar pagada»: delega en editores.js (ED.comisiones), que es
        // quien tiene la sesión/policy para escribir. Aquí solo se localiza el id.
        tablaEq.addEventListener('click', function (ev) {
          var b = ev.target.closest && ev.target.closest('[data-eq-pagar]');
          if (!b) return;
          ev.preventDefault(); ev.stopPropagation();
          var id = b.getAttribute('data-eq-pagar');
          var info = (window.LW_V4 && window.LW_V4.comisionesPorId && window.LW_V4.comisionesPorId[id]) || {};
          if (window.LW_V4 && typeof window.LW_V4.marcarComisionPagada === 'function') {
            window.LW_V4.marcarComisionPagada(id, info.etiqueta || '');
          } else {
            toast('El editor de comisiones aún no ha cargado — prueba de nuevo en un segundo.');
          }
        });
      }
    });
  };

  /* ---------- Cuentas de cobro y su reparto ---------- */
  REG.cuentas = function (sb) {
    var tbody = document.getElementById('lw-reparto');
    var cajaRep = tbody ? tbody.closest('section') : null;
    var tbodyProy = document.getElementById('lw-reparto-proyecto');
    var cajaProy = tbodyProy ? tbodyProy.closest('section') : null;
    var tbodyCu = document.getElementById('lw-reparto-cuenta');
    var cajaCu = document.getElementById('lw-cuentas');

    Promise.all([
      /* `es_escrow` es una COLUMNA, no el prefijo `notario_` de la clave: la
         convencion de nombre valia mientras las cuentas nacian por SQL. */
      q(sb.from('cuentas_bancarias').select('clave,label,titular,banco,activa,es_escrow,orden').order('orden'), 'cuentas bancarias', cajaCu),
      q(sb.from('plantillas_pago').select('slug,nombre,orden').order('orden'), 'plantillas de pago', cajaRep),
      q(sb.from('plantilla_cuentas').select('slug,clave,es_default'), 'reparto por contrato'),
      q(sb.from('proyecto_cuentas').select('proyecto_id,slug,clave,es_default'), 'reparto por proyecto', cajaProy),
      /* Falta desde el 14-sep (14-sep añadió proyecto_cuentas pero nunca trajo
         `proyectos`, así que «Por proyecto» no tenía con qué pintar filas —
         era la mitad que faltaba de las tres pestañas). */
      q(sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre'), 'proyectos', cajaProy)
    ]).then(function (r) {
      var cus = r[0], pls = r[1], rep = r[2], repProy = r[3], proys = r[4];
      if (!cus || !pls || !rep) return;

      var porClave = {};
      cus.forEach(function (c) { porClave[c.clave] = c; });
      var activas = cus.filter(function (c) { return c.activa; });
      var escrow = cus.filter(function (c) { return c.es_escrow; });

      var porSlug = {};
      rep.forEach(function (x) { (porSlug[x.slug] = porSlug[x.slug] || []).push(x); });
      var huerfanas = pls.filter(function (p) { return !(porSlug[p.slug] || []).length; });
      var etiqueta = function (x) { var c = porClave[x.clave]; return c ? (c.label || c.clave) : x.clave; };

      pon2('k-activas', String(activas.length));
      pon2('k-total', String(cus.length));
      pon2('k-activas-pie', (cus.length - activas.length) + ' dadas de baja');
      pon2('k-plantillas', String(pls.length));
      pon2('k-plantillas-pie', (repProy || []).length + ' excepciones por proyecto');
      pon2('k-huerfanas', String(huerfanas.length));
      /* Una plantilla sin cuentas marcadas lo dice en voz alta: un desplegable
         vacio sin explicacion acaba en una cuenta escrita a mano. */
      pon2('k-huerfanas-pie', huerfanas.length
        ? huerfanas.slice(0, 3).map(function (p) { return p.nombre; }).join(' · ')
        : 'todas ofrecen alguna cuenta');
      pon2('k-escrow', String(escrow.length));
      pon2('k-escrow-pie', escrow.length ? 'declaradas por columna, no por nombre' : 'ninguna marcada');

      // ---------- Por contrato ----------
      var t = tbody && tbody.closest('table');
      if (t) {
        var pl = plantillaFilas(t);
        if (pl) {
          if (!pls.length) {
            pl.tbody.innerHTML = '<tr><td colspan="3" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Ningun documento de pago registrado.</td></tr>';
          } else {
            pls.forEach(function (p) {
              var filas = porSlug[p.slug] || [];
              var def = filas.filter(function (x) { return x.es_default; })[0];
              fila(pl, [
                p.nombre || p.slug,
                filas.length ? filas.map(etiqueta).join(' · ') : 'sin cuenta marcada',
                def ? etiqueta(def) : '—'
              ]);
            });
          }
        }
      }

      /* ---------- Por proyecto ----------
         `slug === '*'` es el mismo TODOS de /intranet/cuentas/ (vocabulario.js
         no lo exporta como constante, es un literal de esa pantalla): la
         excepción vale para cualquier tipo de contrato del proyecto. «Hereda»
         es el estado normal y sano, no una falta de configurar — con 1 sola
         fila en `proyecto_cuentas` hoy, casi todos los proyectos van a decir
         «hereda», y eso es correcto. */
      var tProy = tbodyProy && tbodyProy.closest('table');
      if (tProy) {
        var plProy = plantillaFilas(tProy);
        if (plProy) {
          if (proys === null) {
            plProy.tbody.innerHTML = '<tr><td colspan="3" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#93000a">No se pudo leer el catalogo de proyectos.</td></tr>';
          } else if (!proys.length) {
            plProy.tbody.innerHTML = '<tr><td colspan="3" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Ningun proyecto activo.</td></tr>';
          } else {
            var porProy = {};
            (repProy || []).forEach(function (x) { (porProy[x.proyecto_id] = porProy[x.proyecto_id] || []).push(x); });
            proys.forEach(function (p) {
              var reglas = porProy[p.id] || [];
              var tiposVistos = {}, tipos = [];
              reglas.forEach(function (x) {
                var t2 = x.slug === '*' ? 'cualquier contrato' : x.slug;
                if (!tiposVistos[t2]) { tiposVistos[t2] = 1; tipos.push(t2); }
              });
              fila(plProy, [
                p.nombre,
                reglas.length ? tipos.join(' · ') : 'hereda el reparto general',
                reglas.length ? String(reglas.length) : '—'
              ]);
            });
          }
        }
      }

      // ---------- Por cuenta ----------
      var tCu = tbodyCu && tbodyCu.closest('table');
      if (tCu) {
        var plCu = plantillaFilas(tCu);
        if (plCu) {
          if (!cus.length) {
            plCu.tbody.innerHTML = '<tr><td colspan="3" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Ninguna cuenta dada de alta.</td></tr>';
          } else {
            cus.forEach(function (c) {
              /* Ojo (hallazgo de Administración en la consulta de deploy,
                 15-sep): "se ofrece en" tiene que sumar las DOS fuentes del
                 reparto, no solo `rep` (plantilla_cuentas). Una cuenta atada
                 SOLO por una excepción de `proyecto_cuentas` (por ejemplo un
                 notario propio de un proyecto) seguía saliendo "ninguno"
                 aunque estuviera en uso real — quien mirase esta tabla para
                 decidir qué cuenta dar de baja podía desactivar una que un
                 comprador de ese proyecto sigue viendo en su documento. */
              var usos = rep.filter(function (x) { return x.clave === c.clave; }).length
                + (repProy || []).filter(function (x) { return x.clave === c.clave; }).length;
              fila(plCu, [
                c.label || c.clave,
                usos ? (usos + (usos === 1 ? ' documento' : ' documentos')) : 'ninguno',
                c.activa ? 'activa' : 'de baja'
              ]);
            });
          }
        }
      }

      if (cajaCu) {
        cajaCu.innerHTML = cus.length
          ? cus.map(function (c) {
              return itemPanel(esc(c.label || c.clave) + (c.es_escrow ? ' · escrow' : ''),
                               esc([c.banco, c.titular].filter(Boolean).join(' — ') || '—'),
                               c.activa ? 'activa' : 'de baja');
            }).join('')
          : '<p style="font:400 13px \'Neue Kabel\',sans-serif;color:#44483f;margin:0">Ninguna cuenta dada de alta.</p>';
      }
    });
  };

  /* ---------- Equipos de venta y Condiciones de comisión (14-sep-2026) ----------
     Dos pantallas SOLO admin/super_admin: nav.js ya las esconde del menú para
     cualquier otra sesión, y aquí se repite el gate (defensa en profundidad,
     no el candado — ese es `es_admin()` en la RLS de las cuatro tablas,
     verificado con sesión no-admin simulada). Las acciones de escritura viven
     en editores.js (ED['equipos-venta'] / ED.condiciones, expuestas en
     `window.LW_V4`); aquí solo se lee y se pinta. */
  REG['equipos-venta'] = function (sb) {
    if (!(window.LW_V4 && window.LW_V4.esAdmin)) { notaSoloAdmin(); return; }
    var cuerpoEq = document.getElementById('lw-equipos-filas');
    var cuerpoMi = document.getElementById('lw-miembros-filas');
    var selEq = document.getElementById('lw-mi-equipo');
    var hoy = new Date().toISOString().slice(0, 10);

    Promise.all([
      q(sb.from('equipos_venta').select('id,nombre,manager_email,activo,created_at').order('nombre'), 'equipos de venta', cuerpoEq),
      q(sb.from('equipo_miembros').select('id,equipo_id,closer_email,desde,hasta').order('desde', { ascending: false }), 'miembros de equipo', cuerpoMi),
      q(sb.from('usuarios').select('email,nombre'), 'usuarios')
    ]).then(function (r) {
      var equipos = r[0], miembros = r[1] || [], usuarios = r[2] || [];
      if (!equipos) return;
      var nombrePorEmail = {};
      usuarios.forEach(function (u) { if (u.email) nombrePorEmail[u.email.toLowerCase()] = u.nombre || u.email; });
      var nombreDe = function (email) { return email ? (nombrePorEmail[email.toLowerCase()] || email) : '—'; };
      var estaActivo = function (m) { return !m.hasta || m.hasta >= hoy; };

      var porEquipo = {};
      miembros.forEach(function (m) { (porEquipo[m.equipo_id] = porEquipo[m.equipo_id] || []).push(m); });

      var equiposActivos = equipos.filter(function (e) { return e.activo; });
      var miembrosActivos = miembros.filter(estaActivo);
      var managers = {}; equiposActivos.forEach(function (e) { if (e.manager_email) managers[e.manager_email.toLowerCase()] = 1; });
      var sinMiembros = equiposActivos.filter(function (e) { return !(porEquipo[e.id] || []).some(estaActivo); });

      pon2('k-equipos-activos', String(equiposActivos.length));
      pon2('k-equipos-pie', (equipos.length - equiposActivos.length) + ' dados de baja');
      pon2('k-miembros-activos', String(miembrosActivos.length));
      pon2('k-miembros-pie', (miembros.length - miembrosActivos.length) + ' históricos de baja');
      pon2('k-managers', String(Object.keys(managers).length));
      pon2('k-managers-pie', 'al frente de un equipo activo');
      pon2('k-sin-miembros', String(sinMiembros.length));
      pon2('k-sin-miembros-pie', sinMiembros.length
        ? sinMiembros.slice(0, 3).map(function (e) { return e.nombre; }).join(' · ')
        : 'todos con closers activos');

      if (selEq) {
        var actual = selEq.value;
        selEq.innerHTML = '<option value="">Todos los equipos</option>' +
          equipos.map(function (e) { return '<option value="' + esc(e.id) + '">' + esc(e.nombre) + (e.activo ? '' : ' (de baja)') + '</option>'; }).join('');
        selEq.value = actual;
      }

      if (cuerpoEq) {
        cuerpoEq.innerHTML = equipos.length ? equipos.map(function (e) {
          var activosDelEquipo = (porEquipo[e.id] || []).filter(estaActivo).length;
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(e.nombre) + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(nombreDe(e.manager_email)) + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + activosDelEquipo + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              (e.activo ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-surface-container-high text-on-surface-variant') + '">' +
              (e.activo ? 'Activo' : 'De baja') + '</span></td>' +
            '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-2">' +
            '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-miembro="' + esc(e.id) + '" data-lw-nombre="' + esc(e.nombre) + '">+ Miembro</button>' +
            '<button type="button" class="px-3 py-1 rounded-full text-burnt-earth hover:bg-surface-container-high font-label-md text-[12px]" data-lw-toggle-equipo="' + esc(e.id) + '" data-lw-nombre="' + esc(e.nombre) + '" data-lw-activo="' + (e.activo ? '1' : '0') + '">' +
            (e.activo ? 'Desactivar' : 'Reactivar') + '</button>' +
            '</div></td></tr>';
        }).join('') : '<tr><td colspan="5" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Ningún equipo dado de alta todavía.</td></tr>';
      }

      function pintaMiembros() {
        if (!cuerpoMi) return;
        var filtro = selEq ? selEq.value : '';
        var lista = filtro ? miembros.filter(function (m) { return m.equipo_id === filtro; }) : miembros;
        cuerpoMi.innerHTML = lista.length ? lista.map(function (m) {
          var eq = equipos.filter(function (e) { return e.id === m.equipo_id; })[0];
          var activo = estaActivo(m);
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(nombreDe(m.closer_email)) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(eq ? eq.nombre : '—') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(fFecha(m.desde)) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + (m.hasta ? esc(fFecha(m.hasta)) : '—') + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              (activo ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-surface-container-high text-on-surface-variant') + '">' +
              (activo ? 'Activo' : 'De baja') + '</span></td>' +
            '<td class="px-5 py-4 text-right">' + (activo
              ? '<button type="button" class="px-3 py-1 rounded-full text-error hover:bg-error-container/40 font-label-md text-[12px]" data-lw-baja="' + esc(m.id) + '" data-lw-email="' + esc(m.closer_email) + '">Dar de baja</button>'
              : '') + '</td></tr>';
        }).join('') : '<tr><td colspan="6" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Sin miembros para este filtro.</td></tr>';
      }
      pintaMiembros();
      if (selEq) selEq.addEventListener('change', pintaMiembros);

      // acciones — delegadas, con stopPropagation para ganar a maqueta.js (Regla 0)
      if (cuerpoEq) cuerpoEq.addEventListener('click', function (ev) {
        var bM = ev.target.closest && ev.target.closest('[data-lw-miembro]');
        if (bM) {
          ev.preventDefault(); ev.stopPropagation();
          if (window.LW_V4 && window.LW_V4.abreAnadirMiembro) window.LW_V4.abreAnadirMiembro(bM.getAttribute('data-lw-miembro'), bM.getAttribute('data-lw-nombre'));
          else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
          return;
        }
        var bT = ev.target.closest && ev.target.closest('[data-lw-toggle-equipo]');
        if (bT) {
          ev.preventDefault(); ev.stopPropagation();
          if (window.LW_V4 && window.LW_V4.abreToggleEquipo) {
            window.LW_V4.abreToggleEquipo(bT.getAttribute('data-lw-toggle-equipo'), bT.getAttribute('data-lw-nombre'), bT.getAttribute('data-lw-activo') === '1');
          } else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
        }
      });
      if (cuerpoMi) cuerpoMi.addEventListener('click', function (ev) {
        var b = ev.target.closest && ev.target.closest('[data-lw-baja]');
        if (!b) return;
        ev.preventDefault(); ev.stopPropagation();
        if (window.LW_V4 && window.LW_V4.abreDarBaja) window.LW_V4.abreDarBaja(b.getAttribute('data-lw-baja'), b.getAttribute('data-lw-email'));
        else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
      });
    });
  };

  REG.condiciones = function (sb) {
    if (!(window.LW_V4 && window.LW_V4.esAdmin)) { notaSoloAdmin(); return; }
    // vocabulario compartido con editores.js (montaTramos, el select de la base
    // de cálculo): una sola lista, aquí, leída por window.LW_V4 — Regla 0.
    window.LW_V4.DISPARADORES = [
      ['contrato_firmado', 'Al firmar el contrato'],
      ['obra_firmada', 'Al firmar la obra'],
      ['pct_cobrado_suelo', '% cobrado del suelo'],
      ['pct_cobrado_obra', '% cobrado de la obra'],
      ['pct_cobrado_total', '% cobrado del total']
    ];
    window.LW_V4.BASES_CALCULO = [
      ['precio_total', 'Precio total'],
      ['precio_suelo', 'Precio de suelo'],
      ['precio_construccion', 'Precio de construcción'],
      ['importe_fijo', 'Importe fijo']
    ];

    var cuerpo = document.getElementById('lw-condiciones-filas');
    var selEquipo = document.getElementById('lw-co-equipo');
    var selProyecto = document.getElementById('lw-co-proyecto');

    Promise.all([
      q(sb.from('condiciones_comision').select('id,equipo_id,proyecto_id,nivel,closer_email,pct_comision,base_calculo,importe_fijo,activo,created_at').order('created_at', { ascending: false }), 'condiciones de comisión', cuerpo),
      q(sb.from('equipos_venta').select('id,nombre'), 'equipos de venta'),
      q(sb.from('proyectos').select('id,nombre'), 'proyectos'),
      q(sb.from('condicion_tramos').select('id,condicion_id,orden,disparador_tipo,umbral,pct_tramo').order('orden'), 'tramos de comisión'),
      q(sb.from('usuarios').select('email,nombre'), 'usuarios')
    ]).then(function (r) {
      var conds = r[0], equipos = r[1] || [], proyectos = r[2] || [], tramos = r[3] || [], usuarios = r[4] || [];
      if (!conds) return;
      var equipoDe = {}; equipos.forEach(function (e) { equipoDe[e.id] = e.nombre; });
      var proyectoDe = {}; proyectos.forEach(function (p) { proyectoDe[p.id] = p.nombre; });
      var nombrePorEmail = {}; usuarios.forEach(function (u) { if (u.email) nombrePorEmail[u.email.toLowerCase()] = u.nombre || u.email; });
      var tramosDe = {}; tramos.forEach(function (t) { (tramosDe[t.condicion_id] = tramosDe[t.condicion_id] || []).push(t); });

      pon2('k-cond-activas', String(conds.filter(function (c) { return c.activo; }).length));
      pon2('k-cond-total', String(conds.length));
      pon2('k-cond-manager', String(conds.filter(function (c) { return c.nivel === 'manager'; }).length));
      pon2('k-cond-closer', String(conds.filter(function (c) { return c.nivel === 'closer'; }).length));

      if (selEquipo) selEquipo.innerHTML = '<option value="">Todos los equipos</option>' +
        equipos.map(function (e) { return '<option value="' + esc(e.id) + '">' + esc(e.nombre) + '</option>'; }).join('');
      if (selProyecto) selProyecto.innerHTML = '<option value="">Todos los proyectos</option>' +
        proyectos.map(function (p) { return '<option value="' + esc(p.id) + '">' + esc(p.nombre) + '</option>'; }).join('');

      function pinta() {
        if (!cuerpo) return;
        var fe = selEquipo ? selEquipo.value : '', fp = selProyecto ? selProyecto.value : '';
        var lista = conds.filter(function (c) { return (!fe || c.equipo_id === fe) && (!fp || c.proyecto_id === fp); });
        cuerpo.innerHTML = lista.length ? lista.map(function (c) {
          var t = (tramosDe[c.id] || []).slice().sort(function (a, b) { return a.orden - b.orden; });
          var resumenTramos = t.length
            ? t.map(function (x) { return x.pct_tramo + '% ' + etiquetaDe(window.LW_V4.DISPARADORES, x.disparador_tipo); }).join(' · ')
            : '—';
          var quien = c.nivel === 'closer'
            ? (c.closer_email ? esc(nombrePorEmail[c.closer_email.toLowerCase()] || c.closer_email) + ' (override)' : 'todo el equipo · closer')
            : 'manager';
          var importeOBase = c.base_calculo === 'importe_fijo' ? fmt(c.importe_fijo, 'EUR') : (c.pct_comision + '%');
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(equipoDe[c.equipo_id] || '—') + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(proyectoDe[c.proyecto_id] || '—') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + quien + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(importeOBase) +
              '<br><span class="text-outline text-[11px]">' + esc(etiquetaDe(window.LW_V4.BASES_CALCULO, c.base_calculo)) + '</span></td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline max-w-xs">' + esc(resumenTramos) + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              (c.activo ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-surface-container-high text-on-surface-variant') + '">' +
              (c.activo ? 'Activa' : 'Inactiva') + '</span></td>' +
            '<td class="px-5 py-4 text-right"><button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
              'data-lw-toggle-cond="' + esc(c.id) + '" data-lw-etq="' + esc((equipoDe[c.equipo_id] || '') + ' · ' + (proyectoDe[c.proyecto_id] || '')) + '" data-lw-activo="' + (c.activo ? '1' : '0') + '">' +
              (c.activo ? 'Desactivar' : 'Reactivar') + '</button></td></tr>';
        }).join('') : '<tr><td colspan="7" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Ninguna condición para este filtro.</td></tr>';
      }
      pinta();
      if (selEquipo) selEquipo.addEventListener('change', pinta);
      if (selProyecto) selProyecto.addEventListener('change', pinta);

      if (cuerpo) cuerpo.addEventListener('click', function (ev) {
        var b = ev.target.closest && ev.target.closest('[data-lw-toggle-cond]');
        if (!b) return;
        ev.preventDefault(); ev.stopPropagation();
        if (window.LW_V4 && window.LW_V4.abreToggleCondicion) {
          window.LW_V4.abreToggleCondicion(b.getAttribute('data-lw-toggle-cond'), b.getAttribute('data-lw-etq'), b.getAttribute('data-lw-activo') === '1');
        } else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
      });
    });
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
    if (!window.LW_AUTH) { console.error('[v4 datos] sin guard: no se cablea nada'); quitaVelo(); return; }
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
      /* Identidad de la sesión, para pantallas que deciden algo por email/rol
         (hoy: «Reparto de equipo» — es el manager del equipo, o admin). Se
         guarda aquí y no dentro de cada REG[seg], que solo recibe `sb`. */
      window.LW_V4 = window.LW_V4 || {};
      window.LW_V4.miEmail = (aut.session && aut.session.user && aut.session.user.email) || '';
      window.LW_V4.esAdmin = rol === 'admin' || rol === 'super_admin';

      /* La cabecera de Home traia «3 de Septiembre de 2026» escrito a mano: la
         fecha de la captura de Stitch. Una fecha congelada no envejece con un
         aviso, envejece en silencio — y en una consola operativa lo que dice es
         que lo de debajo es de ese dia. Se pinta la de hoy, aqui y no en el HTML,
         que es donde ya se pintan el usuario y el rol. */
      var hoy = new Date().toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' });
      document.querySelectorAll('[data-lw-hoy]').forEach(function (e) { e.textContent = hoy; });

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
      if (fn) {
        try { fn(aut.sb); } catch (e) { fallo('pantalla ' + seg, e); quitaVelo(); }
        /* Si el handler no llego a lanzar ni una consulta, no hay nada que
           esperar: el contador nunca subira y nadie lo bajaria. */
        setTimeout(function () { if (enVuelo === 0) quitaVelo(); }, 400);
      }
    });
  }
  /* EL VELO SE PONE ANTES DE ESPERAR A NADIE. Estuvo dentro de `LW_AUTH.then`
     y tardaba 652 ms en aparecer (medido en produccion, 14-sep): lo que
     esperaba era que guard.js resolviese la sesion, y durante ese medio
     segundo se veia justo la rejilla de guiones que el velo viene a tapar.
     Aqui solo hace falta saber si esta pantalla tiene datos que traer, y eso
     se sabe ya: `REG[seg]` es sincrono. Si luego resulta que no hay sesion,
     `arranca()` lo quita — y si algo se tuerce antes, lo quita el CSS. */
  if (REG[seg]) ponVelo();
  /* Una pantalla de la v4 que cargue shell.css y NO tenga handler nace oculta
     por la regla de arriba y nadie la destaparia hasta el rescate de los 12 s.
     Aqui se sabe ya que no hay nada que esperar. */
  else quitaVelo();

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
