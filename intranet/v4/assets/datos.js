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

  /* 🔴 18-sep-2026 — `.textContent` → `.innerHTML` escapa `&`, `<` y `>` pero NO la
     comilla doble, y este `esc()` se usa DENTRO de atributos en 18 sitios
     (`data-lw-etq="' + esc(nombre) + '"`, `<option value="' + esc(id) + '">`…).
     Un nombre de proyecto con una comilla cierra el atributo y cuelga un
     `onclick` del botón de al lado — y `proyectos.nombre` lo escribe cualquier
     `es_admin()`, mientras que el botón que queda envenenado abre el editor de
     `cuentas_bancarias`, que solo toca un super_admin: el número al que
     transfiere el comprador. La CSP del proyecto es Report-Only y lleva
     'unsafe-inline', así que no frena nada.
     El `esc()` de editores.js sí escapaba la comilla; este no. Se iguala aquí,
     en la fuente, y no en cada punto de uso: una lista a mano de "los sitios
     peligrosos" ES el bug. `&quot;` dentro de texto se pinta como comilla, así
     que los usos que no son de atributo no cambian de aspecto.
     Lo cazó Seguridad en la consulta de deploy del 18-sep. */
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  function fmt(n, m) { return (typeof lwFormatoImporte === 'function') ? lwFormatoImporte(n, m) : (n + ' ' + (m || '')); }

  /* ===== Closer (atribución de venta) — 21-sep-2026, encargo del owner.
     Compartido entre el Expediente de Operaciones (pintaExpediente) y la
     ficha de contrato en cajón (fichaContrato): un solo candado, una sola
     lectura, un solo RPC de escritura — nada duplicado entre los dos sitios.
     MISMO candado que ya construyó Comisiones para esta misma tabla
     (intranet/solicitudes/index.html, PUEDE_ATRIBUIR): 'ranking' o
     super_admin, NUNCA 'admin' a secas (dos de los cuatro admin de Lawang no
     tienen 'ranking' y no deben ver ni tocar quién cierra cada venta).
     Se pinta siempre sobre la RAÍZ: el motor de comisiones
     (comisiones_evaluar_contrato_fn.sql) solo lee `contrato_closer` de ahí. */
  function closerPuede() {
    var f = window.LW_V4 && window.LW_V4.ficha;
    return !!f && (f.rol === 'super_admin' || (f.herramientas || []).indexOf('ranking') !== -1);
  }
  var CLOSER_CACHE = null; // promesa -> { map: {contrato_id: email|''}, equipo: [{email,nombre}] }
  /* Única vía de LECTURA: `contrato_closer` no admite SELECT directo ni para
     `authenticated` (revoke total en 20260911020137) — todo pasa por esta RPC,
     que ya trae "closer_email" por contrato y filtra ella misma por permiso
     (`where puede('ranking') or es_admin()`), así que no hay lógica de
     permisos que reinventar aquí, solo el filtrado por id en cliente. */
  function closerDatos(sb) {
    if (CLOSER_CACHE) return CLOSER_CACHE;
    CLOSER_CACHE = Promise.all([
      sb.rpc('crm_contratos_para_atribuir', { p_solo_pendientes: false }),
      sb.from('usuarios').select('email,nombre').eq('activo', true)
    ]).then(function (r) {
      var map = {};
      if (r[0].error) console.error('[v4 datos] closer:', r[0].error);
      else (r[0].data || []).forEach(function (c) { map[c.contrato_id] = c.closer_email || ''; });
      if (r[1].error) console.error('[v4 datos] equipo closer:', r[1].error);
      return { map: map, equipo: r[1].error ? [] : (r[1].data || []) };
    });
    return CLOSER_CACHE;
  }
  function closerOpcionesHtml(equipo, actual) {
    return '<option value="">— sin atribuir —</option>' + (equipo || []).map(function (u) {
      return '<option value="' + esc(u.email) + '"' + (actual && u.email.toLowerCase() === actual.toLowerCase() ? ' selected' : '') + '>' + esc(u.nombre || u.email) + '</option>';
    }).join('');
  }
  // Mismo patrón que atribuirVenta() en intranet/solicitudes/ (Comisiones):
  // p_previo es el testigo del bloqueo optimista, exigido por el propio RPC.
  function closerGuardar(sb, sel) {
    var id = sel.getAttribute('data-lw-closer-sel'), previo = sel.getAttribute('data-previo') || '', destino = sel.value;
    sel.disabled = true;
    sb.rpc('crm_contrato_closer_set', { p_contrato: id, p_email: destino || null, p_previo: previo || null }).then(function (r) {
      sel.disabled = false;
      if (r.error) {
        if (/ya no es la que tenias/i.test(r.error.message || '')) { toastMal('Otra persona ha cambiado esa atribución justo ahora — recarga la ficha para verla.'); sel.value = previo; return; }
        toastMal('No se pudo guardar el closer: ' + r.error.message);
        sel.value = previo;
        return;
      }
      sel.setAttribute('data-previo', destino || '');
      if (CLOSER_CACHE) CLOSER_CACHE.then(function (d) { d.map[id] = destino || ''; });
      toast('Closer actualizado.');
    });
  }
  /* Conversión ESTIMADA IDR→EUR, solo para Proyectos v4 (21-sep-2026, encargo
     del owner). dinero.js dice a propósito «no se convierte nada, no hay tipo
     de cambio en el sistema y meter uno inventado sería peor» — eso sigue
     siendo la norma en Facturas/Operaciones/Compradores, donde la cifra es un
     documento legal. Aquí es distinto: el owner pidió explícitamente ver
     Riverfront (única cartera en IDR) sumado en € aunque sea una cifra
     aproximada, así que se marca «estimado» en vez de mentir diciendo que es
     un precio real.
     Encontrado el mismo día: el cajón de unidades enseñaba el importe en
     rupias con el sufijo "EUR" pegado sin convertir nada (`fmt(u.precio,
     'EUR')` a pelo) — una casa de 2.759.500.000 IDR se leía como si costara
     2.759.500.000 €. Ese es el bug que se corrige aquí; la suma en € de abajo
     es la petición añadida.
     Tasa: cambio medio EUR/IDR del 21-sep-2026 (~20.400). Como cualquier tipo
     de cambio, envejece — revisar de vez en cuando, no hay automatismo que la
     refresque sola. */
  var TASA_IDR_EUR_ESTIMADA = 20400;
  var TASA_IDR_EUR_ESTIMADA_FECHA = '21-sep-2026';
  function estimaEUR(importeIDR) { return (Number(importeIDR) || 0) / TASA_IDR_EUR_ESTIMADA; }
  /* Texto de un importe que puede venir en IDR: enseña la cifra real en su
     moneda y, si no es EUR, el estimado en € al lado — nunca solo el
     estimado, para que quede claro de dónde sale. */
  function fmtConEstimado(n, moneda) {
    if (n == null) return '—';
    if ((moneda || 'EUR') === 'EUR') return fmt(n, 'EUR');
    return fmt(n, moneda) + ' (≈ ' + fmt(estimaEUR(n), 'EUR') + ' estimado, tasa del ' + TASA_IDR_EUR_ESTIMADA_FECHA + ')';
  }
  window.LW_V4 = window.LW_V4 || {};
  window.LW_V4.estimaEUR = estimaEUR;
  window.LW_V4.TASA_IDR_EUR_ESTIMADA = TASA_IDR_EUR_ESTIMADA;
  window.LW_V4.TASA_IDR_EUR_ESTIMADA_FECHA = TASA_IDR_EUR_ESTIMADA_FECHA;
  function tipoC(t) { return (typeof lwTipoContrato !== 'undefined') ? lwTipoContrato(t) : t; }
  function fFecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x).slice(0, 10) : d.toLocaleDateString('es-ES', { day: '2-digit', month: 'short', year: 'numeric' }); }
  /* Entrega estimada del PROYECTO en trimestres (16-sep-2026, encargo del
     owner: "Q1 de 2027 es para el primer trimestre de 2027") -- se guarda
     como el primer dia del trimestre (editores.js -> montaTrimestre()), aqui
     solo se lee al reves para mostrarla. NO usar para unidades.obra_fecha_entrega,
     que sigue siendo una fecha exacta por parcela. */
  function fTrimestre(x) { if (!x) return '—'; var d = new Date(x + 'T00:00:00'); if (isNaN(d)) return String(x).slice(0, 10); return 'Q' + (Math.floor(d.getMonth() / 3) + 1) + ' ' + d.getFullYear(); }
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
  /* Acciones de fila delegadas en un contenedor ESTATICO. Vive aqui arriba y no
     dentro de una pantalla porque la usan dos (Comision de administracion y
     Cuentas de cobro) y en esta suite un mismo bloque en dos sitios ES el bug,
     no la causa del bug (Regla 0 de `contexto/suite_lawang.md`).

     `stopPropagation` no es higiene: `maqueta.js` delega en `document` y llega
     por burbujeo DESPUES, asi que sin esto anunciaria el boton como «sin
     cablear» encima del editor que si respondio. */
  function delega(caja, pares) {
    if (!caja) return;
    caja.addEventListener('click', function (ev) {
      for (var i = 0; i < pares.length; i++) {
        var b = ev.target.closest && ev.target.closest('[' + pares[i][0] + ']');
        if (!b) continue;
        ev.preventDefault(); ev.stopPropagation();
        var fn = window.LW_V4 && window.LW_V4[pares[i][1]];
        if (fn) fn(b);
        else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
        return;
      }
    });
  }
  /* Lista real ANCLADA por `data-lw-lista`, en el sitio del layout donde vive
     de verdad — a diferencia de `panelReal`, que siempre se cuelga justo
     debajo del `<h1>` (útil cuando el marcado de Stitch no tiene hueco propio,
     pero en /obra/ el hueco YA existe: 18-sep-2026). Un item sin `url` cae al
     `verUrl` común — todas las filas de obra abren la misma herramienta real,
     no una ficha por unidad, así que no hace falta una URL por fila. */
  function pintaListaObra(clave, items, vacio, verUrl) {
    var cont = document.querySelector('[data-lw-lista="' + clave + '"]'); if (!cont) return;
    cont.innerHTML = items.length ? items.join('')
      : '<p style="font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474;margin:2px 0">' + esc(vacio) + '</p>';
    if (verUrl) {
      var its = cont.querySelectorAll('[data-mq-item]');
      for (var i = 0; i < its.length; i++) its[i].addEventListener('click', function () { location.href = verUrl; });
    }
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
      if (new Date(f.fecha_emision || f.created_at) < mesIni) return;   // el mes es el de EMISIÓN
      if ((f.moneda || 'EUR') === 'EUR') eur += Number(f.total) || 0; else otros++;
    });
    return { eur: eur, otros: otros };
  }

  /* ══════════════ registro por pantalla ══════════════ */
  /* ══════════════ ficha de CONTRATO en cajón lateral (18-sep-2026) ══════════════
     Una sola ficha para Contratos, Operaciones y Home: la misma función abierta
     desde tres pantallas, no tres fichas (Regla 0 de la suite). Solo lectura;
     lo que escribe (editar, emitir, firmar) sigue en la herramienta viva y las
     acciones del pie llevan allí. Se pide TODO al abrir y solo de ese contrato:
     el listado no carga cobros, hitos ni firmas de 200 contratos para pintar
     una tabla que no los enseña (hallazgo de Seguridad del 18-sep en
     Compradores, misma familia). */
  var CAMPOS_CONTRATO = 'id,numero,tipo,nombre_contrato,comprador_nombre,proyecto_nombre,parcela_codigo,precio_total,moneda,fecha_firma,bloqueado,pdf_firmado_path,pdf_firmado_hash,creado_por,created_at,contrato_padre_id,liberado_en,liberado_motivo';
  function URL_FACTURA(id) { return '/intranet/v4/facturas/?id=' + encodeURIComponent(id); }
  function tipoDoc(t) { return t === 'recibi' ? 'Recibí' : t === 'proforma' ? 'Proforma' : 'Factura'; }
  /* Una solicitud de firma «pendiente» con `expira_en` pasado ya no la puede usar el
     comprador (firma-submit devuelve 410): se pinta caducada y no cuenta como viva
     (Legal, consulta de deploy 19-sep). */
  function firmaCaducada(f) { return f.estado === 'pendiente' && !!f.expira_en && new Date(f.expira_en).getTime() < Date.now(); }
  /* Cartas de reserva y demás preliminares llevan el precio de la casa entera y solo
     cobran la señal: fuera de volúmenes y de «cobro pendiente» (Administración, 19-sep;
     tercera vez que este patrón reincide — `lwEsPreliminar` es la fuente única). */
  function esPreliminar(c) { return typeof lwEsPreliminar === 'function' && lwEsPreliminar(c.tipo); }
  function pill(texto, tono) {
    var c = { ok: ['#E4F0DA', '#3F5230'], espera: ['#FBF3E4', '#8A6A34'], mal: ['#FFDAD6', '#93000A'] }[tono] || ['#EAE8E2', '#2E3437'];
    return '<span style="display:inline-block;padding:2px 9px;border-radius:999px;font:600 11px/1.5 \'Neue Kabel\',sans-serif;letter-spacing:.04em;text-transform:uppercase;background:' + c[0] + ';color:' + c[1] + '">' + esc(texto) + '</span>';
  }
  var ABRIR = '<span style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Abrir</span>';
  function enlaceFichaContrato(x) {
    return '<a href="#" data-lw-ficha-contrato="' + esc(x.id) + '" style="color:#104C4F;font-weight:600;text-decoration:underline">' + esc(x.numero) + '</a>' +
      (x.tipo ? ' <span style="color:#8A8474">· ' + esc(tipoC(x.tipo)) + '</span>' : '');
  }
  function fichaContrato(sb, c0, opts) {
    opts = opts || {};
    var H = window.lwCajonHtml;
    if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
    var num = c0.numero || '';
    /* 19-sep-2026 (auditoría de paridad): las herramientas vivas leen el UUID
       en `?contrato=` (`openSavedContract(id)` en app.html y `traerContrato` →
       `.eq('id', …)` en facturas), no el número: con el número aterrizaban en
       «No se pudo cargar el contrato». Y «Emitir recibí» sin `tipo=recibi`
       abría una FACTURA (facturas/index.html: `nuevoDocumento(LTIPO || 'factura')`). */
    var acciones = [
      { texto: c0.bloqueado ? 'Ver en el generador' : 'Editar en el generador', href: '/contracts/app.html?contrato=' + encodeURIComponent(c0.id), tono: 'primario' },
      { texto: 'Emitir recibí', onClick: function () {
        if (window.LW_V4 && window.LW_V4.abrirEditorRecibi) window.LW_V4.abrirEditorRecibi({ contrato_id: c0.id });
        else toastMal('El editor de recibís aún está cargando — prueba de nuevo en un segundo.');
      } }
    ];
    if (!opts.sinExpediente) acciones.push({ texto: 'Expediente', href: '/intranet/v4/operaciones/?contrato=' + encodeURIComponent(num) });
    acciones.push({ texto: 'Cerrar', cerrar: true });
    var caj = window.lwCajon({
      sub: tipoC(c0.tipo) + (c0.bloqueado ? ' · firmado' : (c0.pdf_firmado_path ? ' · reabierto' : ' · borrador')),
      titulo: num,
      bajoTitulo: (c0.comprador_nombre || '—') + (c0.proyecto_nombre ? ' · ' + c0.proyecto_nombre : ''),
      cuerpo: '<p style="margin:0;font-size:13px;color:#8A8474">Trayendo la ficha…</p>',
      acciones: acciones
    });
    var id = c0.id;
    var porId = {};
    var familia = 'contrato_padre_id.eq.' + id + (c0.contrato_padre_id ? ',id.eq.' + c0.contrato_padre_id : '');
    Promise.all([
      sb.rpc('contratos_equipo').select(CAMPOS_CONTRATO).eq('id', id).maybeSingle(),
      sb.rpc('facturas_equipo').select('id,numero,tipo,total,moneda,anulada,fecha_emision,created_at').eq('contrato_id', id).order('created_at'),
      sb.from('contrato_vencimientos').select('orden,descripcion,pct,monto,fecha,factura_id,no_facturar').eq('contrato_id', id).order('orden'),
      sb.rpc('contrato_firmas_equipo').select('firmante_nombre,firmante_rol,estado,creado_en,firmado_en,expira_en').eq('contrato_id', id).order('creado_en'),
      sb.from('contrato_compradores').select('client_id,rol').eq('contrato_id', id),
      sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,contrato_padre_id,created_at').or(familia),
      sb.rpc('contratos_cobrado_equipo').select('contrato_id,cobrado').eq('contrato_id', id),
      /* Botón «Liberar reserva» (21-sep-2026): el catálogo real de qué tipos son
         Carta de Reserva sale de `contrato_tipo_etapa` —nunca una lista a mano,
         ver contexto/suite_lawang.md sobre por qué eso es lo que se rompe— y el
         criterio es EL MISMO que fijó la migración de `libera_reserva()`: etapa
         'reserva' menos 'reserva_parcela' (el Bloqueo no es lo que este botón
         libera). Solo lo lee quien tiene la herramienta CRM (`puede('leads')`,
         policy de la tabla): si falla o vuelve vacío el botón simplemente no
         sale, que es el lado seguro — el candado de verdad es el RPC. */
      sb.from('contrato_tipo_etapa').select('tipo').eq('etapa', 'reserva').neq('tipo', 'reserva_parcela'),
      /* La parcela que ocupa ESTE contrato hoy es la que tiene su `contrato_id`
         apuntando aquí (misma relación que usa `sincroniza_unidad_contrato()`
         en servidor) — nunca se resuelve por `parcela_codigo` a mano, que es un
         texto congelado y puede llevar varios códigos separados por coma. */
      sb.from('unidades').select('id,codigo,estado,proyecto,proyecto_id').eq('contrato_id', id)
    ]).then(function (r) {
      if (!document.getElementById('lw-cajon')) return;   // la cerraron antes de que llegara
      var c = r[0].data || c0;
      var cuerpo = '';
      var errs = r.filter(function (x) { return x.error; });
      if (errs.length) {
        console.error('[v4 datos] ficha de contrato', errs.map(function (x) { return x.error; }));
        cuerpo += H.nota('Parte de la ficha no se pudo leer (' + esc(errs[0].error.message || 'sin detalle') + '): lo que falta sale como vacío.');
      }
      var padre = null, hijos = [];
      (r[5].data || []).forEach(function (x) {
        porId[x.id] = x;
        if (x.id === c.contrato_padre_id) padre = x; else if (x.contrato_padre_id === c.id) hijos.push(x);
      });
      cuerpo += H.seccion('Contrato',
        H.dato('Estado', c.bloqueado ? H.tag('Firmado', 'ok') : (c.pdf_firmado_path ? H.tag('Reabierto', 'mal') : H.tag('Borrador', 'espera')), { html: 1 }) +
        H.dato('Tipo', tipoC(c.tipo)) +
        (c.nombre_contrato ? H.dato('Nombre', c.nombre_contrato) : '') +
        H.dato('Proyecto', c.proyecto_nombre) +
        H.dato('Parcela', c.parcela_codigo) +
        H.dato('Precio', c.precio_total != null ? fmt(c.precio_total, c.moneda) : null) +
        H.dato('Fecha de firma', c.fecha_firma ? fFecha(c.fecha_firma) : null) +
        H.dato('Creado', fFecha(c.created_at) + (c.creado_por ? ' · ' + c.creado_por : '')) +
        /* Liberación (21-sep-2026): eje aparte del Estado de arriba — un CR
           firmado puede liberarse igual que uno en borrador (el RPC no exige
           lo contrario), así que es un dato propio y no un tag más de Estado. */
        (c.liberado_en ? H.dato('Reserva', H.tag(c.liberado_motivo === 'desistida' ? 'Liberada · comprador desistió' : 'Liberada · plazo vencido', 'mal') +
          '<br><span style="font-size:11.5px;color:#8A8474">' + esc(fFecha(c.liberado_en)) + '</span>', { html: 1 }) : '') +
        (padre ? H.dato('Cuelga de', enlaceFichaContrato(padre), { html: 1 }) : '') +
        (hijos.length ? H.dato('Encadenados', hijos.map(enlaceFichaContrato).join('<br>'), { html: 1 }) : ''));

      /* Closer (21-sep-2026): SIEMPRE sobre la raíz de la cadena, nunca sobre
         el hijo que se esté viendo — igual que pintaExpediente() en
         Operaciones, y por la misma razón: el motor de comisiones solo lee
         `contrato_closer` de la raíz. Candado propio, oculto entero (no
         deshabilitado) para quien no lo cumple. Se rellena después de pintar
         (más abajo, junto al resto de secciones asíncronas de este cajón)
         porque la lectura pasa por un RPC y no hay que bloquear el resto de
         la ficha esperándola. */
      var raizCloser = padre || c;
      var puedeCloser = closerPuede();
      if (puedeCloser) {
        cuerpo += H.seccion('Cierre de la venta', '<p style="margin:0;font-size:12.5px;color:#8A8474">Trayendo…</p>', 'closer');
      }

      /* Botón «Liberar reserva (comprador desiste)» (21-sep-2026). Solo UX: el
         candado real es el propio RPC (rol + es_manager_de del proyecto de la
         unidad) — un sales_manager de otro proyecto ve el botón igual y recibe
         el 42501 del servidor tal cual, sin disfrazarlo (decisión del owner,
         ver la cabecera de la migración). */
      var tiposReserva = (r[7].data || []).map(function (x) { return x.tipo; });
      var unidadesLigadas = r[8].data || [];
      var unidadesReservadas = unidadesLigadas.filter(function (u) { return u.estado === 'reservada'; });
      var rolSesion = (window.LW_V4 && window.LW_V4.ficha && window.LW_V4.ficha.rol) || '';
      var puedeVerBoton = rolSesion === 'admin' || rolSesion === 'super_admin' || rolSesion === 'sales_manager';
      var esCartaReserva = tiposReserva.indexOf(c.tipo) !== -1;
      if (puedeVerBoton && esCartaReserva && !c.liberado_en && unidadesReservadas.length === 1) {
        cuerpo += H.seccion('Liberar reserva',
          H.nota('El comprador desiste antes de que venza el plazo: la parcela vuelve a "disponible". El contrato no se borra ni se edita — queda sellado como liberado, y el recibí ya cobrado (no reembolsable) no se toca.') +
          unidadesReservadas.map(function (u) {
            return '<button type="button" data-lw-liberar="' + esc(u.id) + '" style="justify-self:start;margin-top:4px;padding:9px 16px;border-radius:10px;border:1px solid #9E2F26;background:#fff;color:#9E2F26;font:600 13px \'Neue Kabel\',sans-serif;cursor:pointer">Liberar reserva (comprador desiste) — Parcela ' + esc(u.codigo || '—') + '</button>';
          }).join('<br>'));
      } else if (puedeVerBoton && esCartaReserva && !c.liberado_en && unidadesReservadas.length > 1) {
        /* 21-sep-2026, hallazgo de code-review + comprobado contra producción
           (CR00025 tiene HOY 3 parcelas reservadas a la vez): libera_reserva()
           marca `contratos.liberado_en` en cuanto libera la PRIMERA parcela, y
           su propio guard de idempotencia («if liberado_en is not null then
           return») convierte cualquier llamada siguiente para una parcela
           hermana en un ÉXITO MUDO que no toca nada — la parcela se queda
           reservada para siempre, sin ningún botón que la vuelva a ofrecer.
           Ofrecer un botón por parcela aquí sería un mensaje mudo por diseño:
           mejor no ofrecer ninguno que ofrecer uno que miente en el segundo
           clic. Pide una liberación por contrato que el RPC no da hoy —
           arreglarlo es tocar la función (Datos+Seguridad), no esta pantalla. */
        cuerpo += H.seccion('Liberar reserva',
          H.nota('Este contrato tiene ' + unidadesReservadas.length + ' parcelas reservadas a la vez (' +
            esc(unidadesReservadas.map(function (u) { return u.codigo || '—'; }).join(', ')) +
            '). Liberar una desde aquí marcaría el contrato entero como liberado y dejaría el resto reservadas sin ninguna forma de soltarlas después. Este botón no cubre ese caso todavía — pide a Desarrollo que la libere a mano.'));
      }

      /* Compradores: el nombre congelado en el contrato siempre; las fichas
         enlazadas (contrato_compradores) se resuelven a nombre en una segunda
         consulta y se pintan en su sección cuando llegan. */
      var vins = r[4].data || [];
      cuerpo += H.seccion('Comprador' + (vins.length > 1 ? 'es' : ''),
        H.dato('En el contrato', c.comprador_nombre) +
        (vins.length ? '<p style="margin:0;font-size:12px;color:#8A8474">Resolviendo ' + vins.length + ' ficha(s) enlazada(s)…</p>' : ''), 'compradores');

      var fs = r[1].data || [];
      /* Lo cobrado lo dice el oráculo vivo `contrato_cobrado()` (recibís aplicados,
         también los aplicados a facturas del contrato), no una suma propia: dos
         pantallas con dos «cobrado» distintos era el hallazgo (Administración/Legal, 19-sep). */
      var cobRow = (r[6] && r[6].data || [])[0];
      var cobrado = cobRow && cobRow.cobrado != null ? Number(cobRow.cobrado) || 0 : null;
      // el oráculo suma recibís sin mirar la moneda: si hay alguno en otra, se dice (hoy 0 casos)
      var otrasMon = fs.filter(function (f) { return f.tipo === 'recibi' && !f.anulada && (f.moneda || 'EUR') !== (c.moneda || 'EUR'); }).length;
      var pend = (cobrado != null && c.precio_total != null && !esPreliminar(c)) ? Math.max(0, Number(c.precio_total) - cobrado) : null;
      cuerpo += H.seccion('Cobros (' + fs.length + ' documento' + (fs.length === 1 ? '' : 's') + ')',
        H.dato('Cobrado (recibís aplicados)', (cobrado != null ? fmt(cobrado, c.moneda) : 'sin dato') + (otrasMon ? ' · incluye ' + otrasMon + ' recibí(s) en otra moneda a valor facial' : '')) +
        (pend != null ? H.dato('Pendiente sobre el precio', fmt(pend, c.moneda)) : '') +
        (esPreliminar(c) ? H.nota('Es un documento preliminar: el precio es el de la casa entera y solo se cobra la señal, así que no se calcula «pendiente».') : '') +
        (fs.length ? H.tabla(['Documento', 'Tipo', 'Importe', 'Fecha', ''], fs.map(function (f) {
          return [H.enlace(URL_FACTURA(f.id), f.numero), esc(tipoDoc(f.tipo)), esc(fmt(f.total, f.moneda)),
            esc(fFecha(f.fecha_emision || f.created_at)),
            f.anulada ? H.tag('Anulada', 'mal') : (f.tipo === 'recibi' ? H.tag('Cobrado', 'ok') : '')];
        })) : H.nota('Sin facturas ni recibís todavía.')));

      var vs = r[2].data || [];
      cuerpo += H.seccion('Calendario de pagos (' + vs.length + ')',
        vs.length ? H.tabla(['#', 'Concepto', 'Importe', 'Fecha', 'Facturado'], vs.map(function (v) {
          return [esc(v.orden != null ? v.orden : ''), esc(v.descripcion || '—'),
            esc(v.monto != null ? fmt(v.monto, c.moneda) : (v.pct != null ? v.pct + ' %' : '—')),
            esc(v.fecha ? fFecha(v.fecha) : 'sin fecha'),
            v.factura_id ? H.tag('Sí', 'ok') : (v.no_facturar ? '<span style="color:#8A8474">no se factura</span>' : H.tag('No', 'espera'))];
        })) : H.nota('Este contrato no tiene calendario de pagos registrado.'));

      var fi = r[3].data || [];
      cuerpo += H.seccion('Firmas (' + fi.length + ')',
        fi.length ? H.tabla(['Firmante', 'Rol', 'Estado', 'Fecha'], fi.map(function (f) {
          var cad = firmaCaducada(f);
          var tono = cad ? 'mal' : f.estado === 'firmado' ? 'ok' : f.estado === 'pendiente' ? 'espera' : 'mal';
          return [esc(f.firmante_nombre || '—'), esc(f.firmante_rol || '—'), H.tag(cad ? 'caducada' : (f.estado || '—'), tono),
            esc(f.firmado_en ? fFecha(f.firmado_en) : (f.expira_en ? 'expira ' + fFecha(f.expira_en) : fFecha(f.creado_en)))];
        })) : H.nota('Sin solicitudes de firma.'));

      if (c.pdf_firmado_path) {
        cuerpo += H.seccion('Documento firmado',
          (!c.bloqueado ? H.nota('El contrato se reabrió después de firmarse. Este PDF es la versión firmada y es la que vincula a las partes; el texto reabierto no tiene efecto hasta una nueva firma.') : '') +
          '<button type="button" data-lw-pdf="' + esc(c.pdf_firmado_path) + '" style="justify-self:start;padding:9px 16px;border-radius:10px;border:1px solid #c5c8bc;background:#fff;color:#104C4F;font:600 13px \'Neue Kabel\',sans-serif;cursor:pointer">Ver PDF firmado</button>' +
          (c.pdf_firmado_hash ? H.dato('SHA-256', c.pdf_firmado_hash) : ''));
      }
      caj.cuerpo.innerHTML = cuerpo;

      if (puedeCloser) {
        var secCloser = caj.cuerpo.querySelector('[data-cajon-sec="closer"] > div');
        if (secCloser) {
          closerDatos(sb).then(function (d) {
            if (!document.body.contains(secCloser)) return; // el cajón ya se cerró
            var actual = d.map[raizCloser.id];
            if (actual === undefined) {
              secCloser.innerHTML = H.nota('Este contrato aún no cuenta como venta firmada con precio (el motor de comisiones exige ambos): la atribución de closer no aplica todavía.');
              return;
            }
            secCloser.innerHTML = H.dato('Closer' + (raizCloser.id !== c.id ? ' (de ' + esc(raizCloser.numero) + ')' : ''),
              '<select data-lw-closer-sel="' + esc(raizCloser.id) + '" data-previo="' + esc(actual || '') + '" style="padding:6px 10px;border-radius:8px;border:1px solid #c5c8bc;font:500 13px \'Neue Kabel\',sans-serif;background:#fff">' +
                closerOpcionesHtml(d.equipo, actual) + '</select>', { html: 1 });
            var sel = secCloser.querySelector('[data-lw-closer-sel]');
            if (sel) sel.addEventListener('change', function () { closerGuardar(sb, sel); });
          });
        }
      }

      if (vins.length) {
        sb.from('clients').select('id,full_name').in('id', vins.map(function (v) { return v.client_id; })).then(function (rc) {
          var sec = caj.cuerpo.querySelector('[data-cajon-sec="compradores"] > div');
          if (!sec) return;
          if (rc.error) { sec.innerHTML = H.dato('En el contrato', c.comprador_nombre) + H.nota('No se pudieron resolver las fichas enlazadas.'); return; }
          var nombre = {}; (rc.data || []).forEach(function (k) { nombre[k.id] = k.full_name; });
          sec.innerHTML = H.dato('En el contrato', c.comprador_nombre) + vins.map(function (v) {
            return H.dato(v.rol || 'Comprador', H.enlace('/intranet/v4/compradores/?id=' + encodeURIComponent(v.client_id), nombre[v.client_id] || 'Ficha de comprador'), { html: 1 });
          }).join('');
        });
      }
      caj.cuerpo.addEventListener('click', function (ev) {
        var a = ev.target.closest && ev.target.closest('[data-lw-ficha-contrato]');
        if (a) { ev.preventDefault(); var x = porId[a.getAttribute('data-lw-ficha-contrato')]; if (x) fichaContrato(sb, x, opts); return; }
        var b = ev.target.closest && ev.target.closest('[data-lw-pdf]');
        if (b) {
          ev.preventDefault(); b.disabled = true; b.textContent = 'Abriendo…';
          // URL firmada de vida corta, como hace la herramienta viva; la policy del bucket decide quién la obtiene
          sb.storage.from('contratos-firmados').createSignedUrl(b.getAttribute('data-lw-pdf'), 300).then(function (u) {
            b.disabled = false; b.textContent = 'Ver PDF firmado';
            if (u.error || !u.data) { toast('No se pudo abrir el PDF: ' + (u.error && u.error.message || 'sin URL')); return; }
            window.open(u.data.signedUrl, '_blank', 'noopener');
          });
        }
        var lib = ev.target.closest && ev.target.closest('[data-lw-liberar]');
        if (lib) {
          ev.preventDefault();
          var uid = lib.getAttribute('data-lw-liberar');
          var uu = unidadesReservadas.filter(function (x) { return x.id === uid; })[0];
          if (!uu) return;
          if (typeof window.lwVentana !== 'function') { toast('El formulario aún no ha cargado — prueba de nuevo en un segundo.'); return; }
          window.lwVentana('Liberar reserva — Parcela ' + (uu.codigo || '—'), [
            { k: '_intro', tipo: 'nota', label: 'El comprador desiste: la parcela ' + (uu.codigo || '') + ' vuelve a «disponible». El contrato ' + num + ' no se borra ni se edita — solo queda sellado como liberado. Esto no tiene botón para deshacerlo.' },
            { k: 'nota', label: 'Motivo del desistimiento', tipo: 'textarea', req: 1, ayuda: 'Obligatorio: qué ha pasado, para el histórico del contrato.' }
          ], 'Liberar reserva', function (vals) {
            var nota = (vals.nota || '').trim();
            // El "req" del formulario ya descarta vacío/solo-espacios; esto además
            // descarta un relleno de un par de caracteres que no cuenta nada.
            if (nota.replace(/\s+/g, '').length < 6) {
              return { error: { message: 'Cuenta el motivo con algo más de detalle: con un par de letras no queda registrado para nadie que lo lea después.' } };
            }
            return sb.rpc('libera_reserva', { p_unidad_id: uu.id, p_contrato_id: c.id, p_motivo: 'desistida', p_nota: nota }).then(function (rr) {
              if (rr.error) return { error: rr.error };
              toast('Reserva liberada: la parcela ' + (uu.codigo || '') + ' ya está disponible.');
              fichaContrato(sb, c, opts);
              return {};
            });
          }, { sinRecarga: true, sub: 'Liberación manual · comprador desiste' });
          return;
        }
      });
    });
  }
  /* Registro de firmas: las últimas solicitudes de firma del equipo, en cajón.
     El botón de la cabecera de Contratos no hacía nada (18-sep). */
  function registroFirmas(sb, cs) {
    var H = window.lwCajonHtml;
    if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
    var porId = {}; (cs || []).forEach(function (c) { porId[c.id] = c; });
    var caj = window.lwCajon({ sub: 'Contratos', titulo: 'Registro de firmas', bajoTitulo: 'Solicitudes de firma del equipo, la más reciente primero',
      cuerpo: '<p style="margin:0;font-size:13px;color:#8A8474">Trayendo el registro…</p>' });
    sb.rpc('contrato_firmas_equipo').select('contrato_id,firmante_nombre,firmante_rol,estado,creado_en,firmado_en,expira_en')
      .order('creado_en', { ascending: false }).limit(80).then(function (r) {
        if (!document.getElementById('lw-cajon')) return;
        if (r.error) { caj.cuerpo.innerHTML = H.nota('No se pudo leer el registro: ' + esc(r.error.message || '')); return; }
        var fs = r.data || [];
        var pend = fs.filter(function (f) { return f.estado === 'pendiente' && !firmaCaducada(f); }).length;
        caj.cuerpo.innerHTML = H.seccion('Últimas ' + fs.length + ' solicitudes · ' + pend + ' pendiente' + (pend === 1 ? '' : 's'),
          fs.length ? H.tabla(['Contrato', 'Firmante', 'Estado', 'Fecha'], fs.map(function (f) {
            var c = porId[f.contrato_id];
            var cad = firmaCaducada(f);
            var tono = cad ? 'mal' : f.estado === 'firmado' ? 'ok' : f.estado === 'pendiente' ? 'espera' : 'mal';
            return [c ? enlaceFichaContrato({ id: c.id, numero: c.numero }) : '<span style="color:#8A8474">fuera de tu alcance</span>',
              esc(f.firmante_nombre || '—') + (f.firmante_rol ? ' <span style="color:#8A8474">· ' + esc(f.firmante_rol) + '</span>' : ''),
              H.tag(cad ? 'caducada' : (f.estado || '—'), tono),
              esc(f.firmado_en ? fFecha(f.firmado_en) : (f.expira_en && f.estado === 'pendiente' ? 'expira ' + fFecha(f.expira_en) : fFecha(f.creado_en)))];
          })) : H.nota('Ninguna solicitud de firma registrada.'));
        caj.cuerpo.addEventListener('click', function (ev) {
          var a = ev.target.closest && ev.target.closest('[data-lw-ficha-contrato]'); if (!a) return;
          ev.preventDefault(); var c = porId[a.getAttribute('data-lw-ficha-contrato')]; if (c) fichaContrato(sb, c);
        });
      });
  }

  /* ══════════════ ficha de DOCUMENTO (factura · proforma · recibí) en cajón (18-sep-2026) ══════════════
     La misma desde Facturas, Recibos y Home. Solo lectura: el documento se
     abre, imprime, envía o anula en la herramienta viva (/intranet/facturas/),
     que es la única que emite con numeración de la base. */
  var CAMPOS_FACTURA = 'id,numero,tipo,sociedad,cliente_nombre,proyecto_nombre,contrato_numero,contrato_id,total,moneda,fecha_emision,anulada,enviada,fecha_envio,creado_por,created_at,justificantes,justificante_path,client_id';
  function estadoDoc(f) { return f.anulada ? ['Anulada', 'mal'] : (f.enviada ? ['Enviada', 'ok'] : ['Emitida', 'espera']); }
  function fichaFactura(sb, f0) {
    var H = window.lwCajonHtml;
    if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
    var acciones = [{ texto: 'Abrir el documento', href: '/intranet/facturas/?id=' + encodeURIComponent(f0.id), tono: 'primario' }];
    // Editar (21-sep-2026): solo mientras el documento sigue vivo — un
    // congelado (anulado o ya enviado) no se toca, se reemite. El candado de
    // autoría/admin lo decide el propio editor (es_suyo-espejo), no esta
    // ficha: un solo sitio que sepa la regla, igual que el resto de la suite.
    if (!f0.anulada && !f0.enviada) {
      acciones.push({ texto: 'Editar', onClick: function () {
        if (!(window.LW_V4 && (window.LW_V4.abrirEditorFactura || window.LW_V4.abrirEditorRecibi))) {
          toastMal('El editor de documentos aún está cargando — prueba de nuevo en un segundo.'); return;
        }
        if (f0.tipo === 'recibi') window.LW_V4.abrirEditorRecibi({ id: f0.id });
        else window.LW_V4.abrirEditorFactura({ id: f0.id });
      } });
    }
    // UUID y tipo, no el número: ver la nota de fichaContrato (19-sep-2026)
    if (f0.contrato_id && f0.tipo !== 'recibi') acciones.push({ texto: 'Emitir recibí', onClick: function () {
      if (window.LW_V4 && window.LW_V4.abrirEditorRecibi) window.LW_V4.abrirEditorRecibi({ contrato_id: f0.contrato_id });
      else toastMal('El editor de recibís aún está cargando — prueba de nuevo en un segundo.');
    } });
    acciones.push({ texto: 'Cerrar', cerrar: true });
    var caj = window.lwCajon({
      sub: tipoDoc(f0.tipo) + (f0.anulada ? ' · anulada' : ''),
      titulo: f0.numero || '',
      bajoTitulo: (f0.cliente_nombre || '—') + (f0.contrato_numero ? ' · ' + f0.contrato_numero : ''),
      cuerpo: '<p style="margin:0;font-size:13px;color:#8A8474">Trayendo la ficha…</p>',
      acciones: acciones
    });
    Promise.all([
      sb.rpc('facturas_equipo').select(CAMPOS_FACTURA).eq('id', f0.id).maybeSingle(),
      f0.contrato_id ? sb.rpc('contratos_equipo').select(CAMPOS_CONTRATO).eq('id', f0.contrato_id).maybeSingle() : Promise.resolve({ data: null })
    ]).then(function (r) {
      if (!document.getElementById('lw-cajon')) return;
      var f = r[0].data || f0, c = r[1].data;
      var cuerpo = '';
      if (r[0].error) cuerpo += H.nota('No se pudo leer la ficha completa (' + esc(r[0].error.message || '') + '): se enseña lo que hay en el listado.');
      var est = estadoDoc(f);
      cuerpo += H.seccion('Documento',
        H.dato('Tipo', tipoDoc(f.tipo)) +
        H.dato('Estado', H.tag(est[0], est[1]), { html: 1 }) +
        H.dato('Importe', f.total != null ? fmt(f.total, f.moneda) : null) +
        H.dato('Fecha de emisión', f.fecha_emision ? fFecha(f.fecha_emision) : fFecha(f.created_at)) +
        H.dato('Enviado al cliente', f.enviada ? (f.fecha_envio ? fFecha(f.fecha_envio) : 'Sí') : 'No') +
        H.dato('Sociedad emisora', f.sociedad ? String(f.sociedad).replace(/_/g, ' ') : null) +
        H.dato('Emitido por', f.creado_por));
      cuerpo += H.seccion('Cliente y contrato',
        H.dato('Cliente', f.client_id ? H.enlace('/intranet/v4/compradores/?id=' + encodeURIComponent(f.client_id), f.cliente_nombre || 'Ficha de comprador') : f.cliente_nombre, { html: !!f.client_id }) +
        H.dato('Proyecto', f.proyecto_nombre) +
        H.dato('Contrato', c ? enlaceFichaContrato(c) : (f.contrato_numero || null), { html: !!c }) +
        (c && c.precio_total != null ? H.dato('Precio del contrato', fmt(c.precio_total, c.moneda)) : ''));
      if (f.tipo === 'recibi') {
        var js = Array.isArray(f.justificantes) ? f.justificantes.slice() : [];
        if (!js.length && f.justificante_path) js.push({ path: f.justificante_path });
        cuerpo += H.seccion('Justificantes de pago (' + js.length + ')',
          js.length ? js.map(function (j, i) {
            return '<button type="button" data-lw-just="' + esc(j.path) + '" style="justify-self:start;padding:8px 14px;border-radius:10px;border:1px solid #c5c8bc;background:#fff;color:#104C4F;font:600 13px \'Neue Kabel\',sans-serif;cursor:pointer">' + esc(j.nombre || ('Justificante ' + (i + 1))) + '</button>';
          }).join('') : H.nota('Este recibí no tiene justificante adjunto. Se adjunta desde la herramienta viva.'));
      }
      caj.cuerpo.innerHTML = cuerpo;
      caj.cuerpo.addEventListener('click', function (ev) {
        var a = ev.target.closest && ev.target.closest('[data-lw-ficha-contrato]');
        if (a && c) { ev.preventDefault(); fichaContrato(sb, c); return; }
        var b = ev.target.closest && ev.target.closest('[data-lw-just]');
        if (b) {
          ev.preventDefault(); b.disabled = true;
          sb.storage.from('justificantes').createSignedUrl(b.getAttribute('data-lw-just'), 300).then(function (u) {
            b.disabled = false;
            if (u.error || !u.data) { toast('No se pudo abrir el justificante: ' + (u.error && u.error.message || 'sin URL')); return; }
            window.open(u.data.signedUrl, '_blank', 'noopener');
          });
        }
      });
    });
  }

  /* ══════════════ chips con CUENTA REAL y filtro combinado (18-sep-2026) ══════════════
     Stitch traía «Firmados 41» escrito a mano. Aquí cada grupo de chips se
     regenera desde los datos: cada <tr> pintada lleva data-lw-<grupo>="clave"
     y el chip solo enseña/oculta. Varios grupos se combinan (Y) y el buscador
     también. `cablearChipsFiltro` (arriba) sirve para UN grupo con chips ya en
     el HTML; esto es para cuando los chips nacen de la base. */
  function chipsReales(cont, grupo, opciones, estado, aplicar) {
    if (!cont) return;
    while (cont.children.length > 1) cont.lastElementChild.remove();   // se conserva la etiqueta del grupo
    var ON = cont.getAttribute('data-lw-on') || 'bg-volcanic-ash text-surface-container-lowest';
    var OFF = cont.getAttribute('data-lw-off') || 'bg-surface-container-low text-volcanic-ash hover:bg-surface-container-high';
    var BASE = cont.getAttribute('data-lw-base') || 'px-3.5 py-1.5 rounded-full font-label-md text-body-sm transition-colors';
    opciones.forEach(function (o, i) {
      var b = document.createElement('button'); b.type = 'button'; b.setAttribute('data-real', '');
      b.className = BASE + ' ' + (i === 0 ? ON : OFF);
      b.textContent = o.texto + (o.n != null ? ' ' + o.n : '');
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        estado[grupo] = { attr: o.atributo || grupo, valor: o.clave };
        Array.prototype.forEach.call(cont.querySelectorAll('button'), function (x) { x.className = BASE + ' ' + (x === b ? ON : OFF); });
        aplicar();
      });
      cont.appendChild(b);
    });
  }
  function aplicaFiltros(tbody, estado, grupos, texto, alTerminar) {
    var n = 0;
    Array.prototype.forEach.call(tbody.querySelectorAll('tr[data-lw-fila]'), function (tr) {
      var ok = true;
      for (var i = 0; i < grupos.length && ok; i++) {
        var s = estado[grupos[i]];
        if (s && s.valor !== '*' && tr.getAttribute('data-lw-' + s.attr) !== s.valor) ok = false;
      }
      if (ok && texto && (tr.getAttribute('data-lw-pajar') || '').indexOf(texto) === -1) ok = false;
      tr.style.display = ok ? '' : 'none';
      if (ok) n++;
    });
    if (alTerminar) alTerminar(n);
  }
  /* CSV de lo que la pantalla ya tiene en memoria: sin ir a la base otra vez y
     sin fichero «generado» de mentira. Separador «;» (Excel en español), BOM
     para que abra con acentos, y las celdas que empiezan por = + - @ llevan
     apostrofo delante: una hoja de calculo las ejecutaria como formula. */
  function exportaCSV(nombre, cabeceras, filas) {
    var celda = function (v) {
      v = v == null ? '' : String(v);
      if (/^[=+\-@]/.test(v)) v = "'" + v;
      return /[";\r\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v;
    };
    var txt = '\uFEFF' + [cabeceras].concat(filas).map(function (f) { return f.map(celda).join(';'); }).join('\r\n');
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([txt], { type: 'text/csv;charset=utf-8' }));
    a.download = nombre; document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }
  function botonConTexto(rx) {
    var bs = document.querySelectorAll('main button');
    for (var i = 0; i < bs.length; i++) if (rx.test((bs[i].textContent || '').replace(/\s+/g, ' ').trim())) return bs[i];
    return null;
  }
  function buscadorDe(aplicar, alCambiar) {
    var inp = document.querySelector('main input[placeholder^="Buscar"]');
    if (!inp) return;
    inp.addEventListener('input', function () { alCambiar(inp.value.trim().toLowerCase()); aplicar(); });
    var q0 = new URLSearchParams(location.search).get('q');
    if (q0) { inp.value = q0; alCambiar(q0.trim().toLowerCase()); aplicar(); }
  }

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
      q(sb.rpc('facturas_equipo').select('id,tipo,total,moneda,anulada,enviada,created_at,fecha_emision,numero,cliente_nombre,proyecto_nombre,contrato_numero,contrato_id'), 'facturas').then(function (fs) {
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
          var d = new Date(f.fecha_emision || f.created_at);
          if (d >= iniPrev && d < ini) prev += Number(f.total) || 0;
        });
        // el «vs mes anterior» lo pone la propia tarjeta: aqui solo va la cifra
        pon2('k-cobrado-tend', prev ? ((s.eur >= prev ? '+' : '') + Math.round((s.eur - prev) / prev * 1000) / 10 + '%') : '—');
        var t = tablaPor([/TIPO/, /DOC/, /COMPRADOR|CLIENTE/, /IMPORTE/]);
        if (t) {
          var pl = plantillaFilas(t);
          var porIdF = {};
          var ult = fs.slice().sort(function (a, b) { return a.created_at < b.created_at ? 1 : -1; }).slice(0, 8);
          ult.forEach(function (f) {
            porIdF[f.id] = f;
            fila(pl, [tipoDoc(f.tipo), f.numero, f.cliente_nombre, f.proyecto_nombre || '—', fmt(f.total, f.moneda), fFecha(f.created_at), '']);
            var tr = pl.tbody.lastElementChild; tr.setAttribute('data-lw-id', f.id); tr.style.cursor = 'pointer';
            var tds = tr.querySelectorAll('td'); var est = estadoDoc(f);
            if (tds[6]) tds[6].innerHTML = pill(est[0], est[1]);
          });
          pon2('k-ult-n', String(ult.length));
          // la fila abre la ficha del documento en el cajon (antes saltaba a la herramienta clasica)
          pl.tbody.addEventListener('click', function (ev) {
            var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
            ev.stopPropagation(); var f = porIdF[tr.getAttribute('data-lw-id')]; if (f) fichaFactura(sb, f);
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
      // «15 por conciliar esta semana» era del diseño: se cuentan los hitos con fecha en 7 días
      var en7 = new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10);
      cnt(sb, 'contrato_vencimientos', function (x) { return x.gte('fecha', hoy).lte('fecha', en7).eq('contratos.bloqueado', true); }, '*, contratos!inner(id)')
        .then(function (n7) { pon2('k-venc-semana', n7 == null ? '—' : (n7 + ' con fecha en los próximos 7 días')); });
      // el buscador de Home busca en Contratos (Enter)
      var busca = document.querySelector('main input[placeholder^="Buscar"]');
      if (busca) busca.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' && busca.value.trim()) location.href = '/intranet/v4/contratos/?q=' + encodeURIComponent(busca.value.trim());
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
            '<a href="/intranet/v4/vencimientos/" style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Abrir tesorería →</a>';
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
            '<a href="/intranet/v4/operaciones/?filtro=firma" style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Verlos en Operaciones →</a>';
        });
    },

    contratos: function (sb) {
      var t = tablaPor([/CONTRATO|N[ºU°]/, /COMPRADOR/, /TIPO|ESTADO/]);
      var miEmail = (window.LW_V4 && window.LW_V4.miEmail) || '';
      Promise.all([
        q(sb.rpc('contratos_equipo').select(CAMPOS_CONTRATO).order('created_at', { ascending: false }).limit(1000), 'contratos', t),
        q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado,expira_en').eq('estado', 'pendiente'), 'firmas pendientes')
      ]).then(function (rr) {
          var cs = rr[0];
          var firmaDe = {}; (rr[1] || []).forEach(function (x) { if (!firmaCaducada(x)) firmaDe[x.contrato_id] = x; });
          if (!cs) return;
          // firmado > en firma (hay firma viva pendiente: ya no es editable) > borrador
          var estadoC = function (c) { return c.bloqueado ? 'firmado' : firmaDe[c.id] ? 'firma' : 'borrador'; };
          var ETQ_C = { firmado: ['Firmado', 'ok'], firma: ['En firma', 'espera'], borrador: ['Borrador', ''] };

          /* KPIs: los cuatro numeros de Stitch (210, 12.4M, 41, 18) eran
             inventados y se leian como reales. Nacen en «—» en el fichero y solo
             los llena la base. Dos etiquetas se reescribieron porque preguntaban
             algo que la base no responde sin mentir: firmado = `bloqueado`, y no
             hay fecha de firma fiable con la que acotar «del mes». */
          var eur = 0, otras = 0, firmados = 0, mios = 0, enFirma = 0;
          cs.forEach(function (c) {
            if (c.bloqueado) firmados++; else if (firmaDe[c.id]) enFirma++;
            if (miEmail && c.creado_por === miEmail) mios++;
            if (c.precio_total == null || esPreliminar(c)) return;   // cartas de reserva: fuera del volumen
            if ((c.moneda || 'EUR') === 'EUR') eur += Number(c.precio_total) || 0; else otras++;
          });
          pon2('k-activos', String(cs.length));
          pon2('k-volumen', fmt(eur, 'EUR'));
          pon2('k-firmados', String(firmados));
          pon2('k-pendientes', String(cs.length - firmados));
          if (otras) {
            bandaNota('El volumen es SOLO en euros y sin cartas de reserva: ' + otras + ' contrato(s) en otra moneda quedan fuera de la suma. ' +
              'No se mezclan monedas — el total saldria en una unidad que no existe.', '#8A6A34');
          }
          window.LW_V4 = window.LW_V4 || {};
          window.LW_V4.contratosLista = {};
          var porNum = {};
          cs.forEach(function (c) { window.LW_V4.contratosLista[c.id] = c; porNum[c.numero] = c; });

          // «Registro de firmas» (cabecera): cajón con las últimas solicitudes de firma del equipo
          var bReg = botonConTexto(/Registro de firmas/i);
          if (bReg) {
            bReg.setAttribute('data-real', '');
            bReg.addEventListener('click', function (ev) { ev.stopPropagation(); registroFirmas(sb, cs); });
          }

          if (!t) { console.info('[v4] contratos: tabla sin ancla'); return; }
          var pl = plantillaFilas(t);
          pon2('p-total', String(cs.length));
          pon2('p-desde', String(cs.length));
          /* Se pintan TODOS (la base ya acota a lo que la sesión puede ver): el
             tope de 120 dejaba fuera contratos sin decirlo, y el paginador
             «1 2 3 … 27» era dibujo. La fila abre la ficha en el cajón; el
             generador vivo queda como acción dentro de ella. */
          cs.forEach(function (c) {
            fila(pl, [c.numero, tipoC(c.tipo), c.comprador_nombre || '—', c.proyecto_nombre || '—',
              c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—',
              fFecha(c.created_at), c.creado_por || '—', '', '']);
            var tr = pl.tbody.lastElementChild;
            tr.setAttribute('data-lw-fila', ''); tr.setAttribute('data-lw-id', c.id);
            tr.setAttribute('data-lw-tipo', c.tipo || '');
            tr.setAttribute('data-lw-estado', estadoC(c));
            tr.setAttribute('data-lw-mio', miEmail && c.creado_por === miEmail ? '1' : '0');
            tr.setAttribute('data-lw-pajar', [c.numero, c.comprador_nombre, c.proyecto_nombre, c.creado_por, c.parcela_codigo, tipoC(c.tipo)].join(' ').toLowerCase());
            var tds = tr.querySelectorAll('td');
            if (tds[7]) tds[7].innerHTML = pill(ETQ_C[estadoC(c)][0], ETQ_C[estadoC(c)][1]);
            if (tds[8]) tds[8].innerHTML = ABRIR;
            tr.style.cursor = 'pointer';
          });
          pl.tbody.addEventListener('click', function (ev) {
            var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
            ev.stopPropagation();
            var c = window.LW_V4.contratosLista[tr.getAttribute('data-lw-id')];
            if (c) fichaContrato(sb, c);
          });

          /* Chips con la cuenta REAL: el grupo Tipo nace de los tipos que hay
             (no de una lista fija: «Cesión de Derechos 9» no existía en la base). */
          var estado = {}, texto = '';
          var porTipo = {}; cs.forEach(function (c) { var k = c.tipo || ''; porTipo[k] = (porTipo[k] || 0) + 1; });
          var opsTipo = [{ clave: '*', texto: 'Todos', n: cs.length }].concat(
            Object.keys(porTipo).sort(function (a, b) { return porTipo[b] - porTipo[a]; })
              .map(function (k) { return { clave: k, texto: k ? tipoC(k) : 'Sin tipo', n: porTipo[k] }; }));
          var opsEstado = [
            { clave: '*', texto: 'Todos', n: cs.length },
            { clave: 'borrador', texto: 'Borradores', n: cs.length - firmados - enFirma },
            { clave: 'firma', texto: 'En firma', n: enFirma },
            { clave: 'firmado', texto: 'Firmados', n: firmados }
          ];
          if (miEmail) opsEstado.push({ clave: '1', atributo: 'mio', texto: 'Míos', n: mios });
          var aplicar = function () {
            aplicaFiltros(pl.tbody, estado, ['tipo', 'estado'], texto, function (n) { pon2('p-desde', String(n)); });
          };
          chipsReales(document.querySelector('[data-lw-chips="tipo"]'), 'tipo', opsTipo, estado, aplicar);
          chipsReales(document.querySelector('[data-lw-chips="estado"]'), 'estado', opsEstado, estado, aplicar);
          buscadorDe(aplicar, function (v) { texto = v; });

          // ?contrato=NUM abre la ficha directamente (enlaces de la auditoría, de Home, etc.)
          var pedido = new URLSearchParams(location.search).get('contrato');
          if (pedido && porNum[pedido]) fichaContrato(sb, porNum[pedido]);
        });
    },

    facturas: function (sb) {
      /* Listado REAL de facturas y proformas (los recibís tienen su pantalla).
         La pantalla de Stitch era un editor de emisión dibujado; la emisión
         sigue en la herramienta viva (numeración por secuencia de la base). */
      var t = tablaPor([/DOCUMENTO|N[ºU°]/, /CLIENTE/, /TIPO|ESTADO/]);
      q(sb.rpc('facturas_equipo').select(CAMPOS_FACTURA).neq('tipo', 'recibi').order('created_at', { ascending: false }).limit(2000), 'facturas', t)
        .then(function (fs) {
          if (!fs) return;
          var ini = new Date(); ini.setDate(1); ini.setHours(0, 0, 0, 0);
          var mesEUR = 0, mesOtras = 0, nFac = 0, nFacAnu = 0, nPro = 0, nProAnu = 0;
          fs.forEach(function (f) {
            if (f.tipo === 'proforma') { nPro++; if (f.anulada) nProAnu++; } else { nFac++; if (f.anulada) nFacAnu++; }
            if (f.tipo !== 'proforma' && !f.anulada && new Date(f.fecha_emision || f.created_at) >= ini) {
              if ((f.moneda || 'EUR') === 'EUR') mesEUR += Number(f.total) || 0; else mesOtras++;
            }
          });
          pon2('k-mes', fmt(mesEUR, 'EUR'));
          pon2('k-mes-pie', 'facturas vigentes del mes en euros, impuestos incluidos' + (mesOtras ? ' · +' + mesOtras + ' en otra moneda' : ''));
          pon2('k-facturas', String(nFac));
          pon2('k-facturas-pie', nFacAnu + ' anulada' + (nFacAnu === 1 ? '' : 's') + ' · histórico completo');
          pon2('k-proformas', String(nPro));
          pon2('k-proformas-pie', nProAnu + ' anulada' + (nProAnu === 1 ? '' : 's') + ' · no facturan ni vencen');
          var porId = {}; fs.forEach(function (f) { porId[f.id] = f; });
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.facturasLista = porId;

          if (t) {
            var pl = plantillaFilas(t);
            pon2('p-total', String(fs.length)); pon2('p-desde', String(fs.length));
            fs.forEach(function (f) {
              var est = estadoDoc(f);
              fila(pl, [f.numero, tipoDoc(f.tipo), f.cliente_nombre || '—', f.contrato_numero || '—', f.proyecto_nombre || '—',
                fmt(f.total, f.moneda), fFecha(f.fecha_emision || f.created_at), '', '']);
              var tr = pl.tbody.lastElementChild;
              tr.setAttribute('data-lw-fila', ''); tr.setAttribute('data-lw-id', f.id);
              tr.setAttribute('data-lw-tipo', f.tipo === 'proforma' ? 'proforma' : 'factura');
              tr.setAttribute('data-lw-estado', f.anulada ? 'anulada' : (f.enviada ? 'enviada' : 'emitida'));
              tr.setAttribute('data-lw-pajar', [f.numero, f.cliente_nombre, f.contrato_numero, f.proyecto_nombre].join(' ').toLowerCase());
              var tds = tr.querySelectorAll('td');
              if (tds[7]) tds[7].innerHTML = pill(est[0], est[1]);
              if (tds[8]) tds[8].innerHTML = ABRIR;
              tr.style.cursor = 'pointer';
            });
            pl.tbody.addEventListener('click', function (ev) {
              var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
              ev.stopPropagation(); var f = porId[tr.getAttribute('data-lw-id')]; if (f) fichaFactura(sb, f);
            });
            var estado = {}, texto = '';
            var aplicar = function () { aplicaFiltros(pl.tbody, estado, ['tipo', 'estado'], texto, function (n) { pon2('p-desde', String(n)); }); };
            var cuenta = function (f) { return fs.filter(f).length; };
            chipsReales(document.querySelector('[data-lw-chips="tipo"]'), 'tipo', [
              { clave: '*', texto: 'Todos', n: fs.length },
              { clave: 'factura', texto: 'Facturas', n: nFac },
              { clave: 'proforma', texto: 'Proformas', n: nPro }], estado, aplicar);
            chipsReales(document.querySelector('[data-lw-chips="estado"]'), 'estado', [
              { clave: '*', texto: 'Todas', n: fs.length },
              { clave: 'emitida', texto: 'Emitidas', n: cuenta(function (f) { return !f.anulada && !f.enviada; }) },
              { clave: 'enviada', texto: 'Enviadas', n: cuenta(function (f) { return !f.anulada && f.enviada; }) },
              { clave: 'anulada', texto: 'Anuladas', n: nFacAnu + nProAnu }], estado, aplicar);
            buscadorDe(aplicar, function (v) { texto = v; });
          }
          /* ?id= abre la ficha. Si no está en este listado (un recibí, enlazado
             desde la ficha de un contrato) se pide ese documento solo. */
          var pedido = new URLSearchParams(location.search).get('id');
          if (pedido) {
            if (porId[pedido]) fichaFactura(sb, porId[pedido]);
            else sb.rpc('facturas_equipo').select(CAMPOS_FACTURA).eq('id', pedido).maybeSingle().then(function (r) {
              if (r.data) fichaFactura(sb, r.data); else toast('Ese documento no está a tu alcance o no existe.');
            });
          }
        });
    },

    recibos: function (sb) {
      var t = tablaPor([/RECIBO|N[ºU°]/, /PAGADOR|TITULAR/, /IMPORTE/]);
      q(sb.rpc('facturas_equipo').select(CAMPOS_FACTURA).eq('tipo', 'recibi').order('created_at', { ascending: false }).limit(2000), 'recibís', t)
        .then(function (rs) {
          if (!rs) return;
          var nJust = function (r) { return (Array.isArray(r.justificantes) && r.justificantes.length) || (r.justificante_path ? 1 : 0); };
          var s = sumaMesEUR(rs);
          pon2('k-cobrado-mes', fmt(s.eur, 'EUR'));
          pon2('k-cobrado-mes-pie', 'recibís vigentes del mes en euros, impuestos incluidos' + (s.otros ? ' · +' + s.otros + ' en otra moneda' : ''));
          var anul = rs.filter(function (r) { return r.anulada; }).length;
          var sinJ = rs.filter(function (r) { return !r.anulada && !nJust(r); }).length;
          pon2('k-emitidos', String(rs.length));
          pon2('k-emitidos-pie', anul + ' anulado' + (anul === 1 ? '' : 's') + ' · histórico completo');
          pon2('k-sinjust', String(sinJ));
          pon2('k-sinjust-pie', sinJ ? 'recibís vigentes sin justificante de pago adjunto' : 'todos los recibís vigentes tienen justificante');
          var porId = {}; rs.forEach(function (r) { porId[r.id] = r; });
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.facturasLista = porId;

          if (t) {
            var pl = plantillaFilas(t);
            pon2('p-total', String(rs.length)); pon2('p-desde', String(rs.length));
            var porMon = {};
            rs.forEach(function (r) {
              var m = r.moneda || 'EUR'; porMon[m] = (porMon[m] || 0) + 1;
              var nj = nJust(r), est = estadoDoc(r);
              fila(pl, [r.numero, r.contrato_numero || '—', r.cliente_nombre || '—', r.proyecto_nombre || '—', fmt(r.total, r.moneda),
                nj ? nj + ' adjunto' + (nj === 1 ? '' : 's') : 'sin justificante', fFecha(r.fecha_emision || r.created_at), '', '']);
              var tr = pl.tbody.lastElementChild;
              tr.setAttribute('data-lw-fila', ''); tr.setAttribute('data-lw-id', r.id);
              tr.setAttribute('data-lw-moneda', m);
              tr.setAttribute('data-lw-estado', r.anulada ? 'anulado' : 'emitido');
              tr.setAttribute('data-lw-just', nj ? '1' : '0');
              tr.setAttribute('data-lw-pajar', [r.numero, r.cliente_nombre, r.contrato_numero, r.proyecto_nombre].join(' ').toLowerCase());
              var tds = tr.querySelectorAll('td');
              if (tds[5] && !nj && !r.anulada) tds[5].innerHTML = pill('sin justificante', 'espera');
              if (tds[7]) tds[7].innerHTML = pill(r.anulada ? 'Anulado' : (r.enviada ? 'Enviado' : 'Emitido'), est[1]);
              if (tds[8]) tds[8].innerHTML = ABRIR;
              tr.style.cursor = 'pointer';
            });
            pl.tbody.addEventListener('click', function (ev) {
              var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
              ev.stopPropagation(); var r = porId[tr.getAttribute('data-lw-id')]; if (r) fichaFactura(sb, r);
            });
            var estado = {}, texto = '';
            var aplicar = function () { aplicaFiltros(pl.tbody, estado, ['moneda', 'estado'], texto, function (n) { pon2('p-desde', String(n)); }); };
            chipsReales(document.querySelector('[data-lw-chips="moneda"]'), 'moneda',
              [{ clave: '*', texto: 'Todas', n: rs.length }].concat(Object.keys(porMon).sort().map(function (m) { return { clave: m, texto: 'Divisa ' + m, n: porMon[m] }; })), estado, aplicar);
            chipsReales(document.querySelector('[data-lw-chips="estado"]'), 'estado', [
              { clave: '*', texto: 'Todos', n: rs.length },
              { clave: 'emitido', texto: 'Emitidos', n: rs.length - anul },
              { clave: 'anulado', texto: 'Anulados', n: anul },
              { clave: '0', atributo: 'just', texto: 'Sin justificante', n: rs.filter(function (r) { return !nJust(r); }).length }], estado, aplicar);
            buscadorDe(aplicar, function (v) { texto = v; });
          }
          var pedido = new URLSearchParams(location.search).get('id');
          if (pedido && porId[pedido]) fichaFactura(sb, porId[pedido]);
        });
    },

    compradores: function (sb) {
      /* Directorio completo (fase A3) y, desde el 18-sep-2026, la FICHA en un
         cajon propio de la v4 — antes cada fila mandaba a /intranet/compradores/
         (owner: «si abro un comprador me lleva a la version antigua»).

         La inversion NO suma contratos preliminares (lwEsPreliminar): la Carta
         reparte el mismo precio que su Bloqueo y sumarla cuenta la villa dos
         veces — la regla es de vocabulario.js, no de aqui.

         🔴 POR QUE `documentos_desactualizados` YA NO VA EN EL Promise.all
         (18-sep-2026, owner: «al abrirlo se abre un mock-up y tarda un monton
         en mostrar datos reales»). Medido en la base: esa vista tarda 12,7 s,
         porque `diferencias_con_ficha()` descomprime el jsonb `datos` ENTERO
         de cada contrato y cada factura (el TOAST de LAW: 97% de `contratos`
         son blobs). Todo lo demas de esta pantalla vuelve en milisegundos. Y
         el velo de carga se rinde a los 12 s (shell.css, `lw-rendirse`), asi
         que justo antes de llegar los datos destapaba la maqueta de Stitch.
         Ahora la vista se pide DESPUES de pintar, fuera del contador del velo,
         y su aviso «Ficha ≠» aparece cuando llega. La vista en si no se toca
         aqui: queda como pendiente de Datos (una columna materializada). */
      var t = tablaPor([/INVERSOR|TITULAR/, /CONTACTO|PA[IÍ]S/]);
      Promise.all([
        /* Solo lo que el LISTADO enseña. Pasaporte, registro, representante,
           notas y propietario se piden al abrir UNA ficha (abreFicha): traer
           500 pasaportes de golpe para pintar una tabla que no los enseña era
           un hallazgo MEDIA de Seguridad en la consulta de deploy (18-sep). */
        /* EL DIRECTORIO (14-sep-2026, decisión del owner, calcado de la viva):
           `clients` a pelo devuelve solo las fichas que TÚ diste de alta (RLS del
           11-sep) — un agente veía entre 1 y 14 de 179, no encontraba al
           comprador, lo creaba otra vez y la base se lo rechazaba contra una fila
           invisible (17 altas rechazadas en 18 minutos el 14-sep).
           `compradores_directorio()` devuelve la IDENTIDAD de todas, sin `notes`;
           lo del negocio de cada uno sigue filtrado por autor. Se piden solo las
           columnas que el LISTADO enseña (minimización, Seguridad 18-sep). */
        q(sb.rpc('compradores_directorio').select('id,full_name,email,phone,nationality,tipo,kyc_status,created_at').order('created_at', { ascending: false }), 'compradores', t),
        q(sb.rpc('contratos_equipo').select('id,numero,tipo,proyecto_nombre,fecha_firma,precio_total,moneda,bloqueado'), 'contratos'),
        q(sb.from('contrato_compradores').select('contrato_id,client_id,rol'), 'vinculos'),
        vig(sb.rpc('contratos_cobrado_equipo')).then(function (r) { return r.error ? (fallo('cobrado', r.error), null) : (r.data || []); }),
        q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado').eq('estado', 'pendiente'), 'firmas'),
        // nombre del agente que dio de alta cada ficha (`clients.propietario` es un email)
        q(sb.from('usuarios').select('email,nombre'), 'equipo')
      ]).then(function (r) {
        var cs = r[0], cts = r[1] || [], vin = r[2] || [], cob = r[3] || [], fir = r[4] || [], eq = r[5] || [];
        if (!cs) return;
        var esPre = function (tp) { return (typeof lwEsPreliminar === 'function') && lwEsPreliminar(tp); };
        var porC = {}; cts.forEach(function (c2) { porC[c2.id] = c2; });
        var cobId = {}; cob.forEach(function (x) { cobId[x.contrato_id] = Number(x.cobrado) || 0; });
        var firmaPend = {}; fir.forEach(function (x) { firmaPend[x.contrato_id] = 1; });
        var nombreEquipo = {}; eq.forEach(function (u) { if (u.email) nombreEquipo[u.email.toLowerCase()] = u.nombre || u.email; });
        var deCliente = {};
        vin.forEach(function (v) {
          var c2 = porC[v.contrato_id]; if (!c2) return;
          var d = deCliente[v.client_id] = deCliente[v.client_id] || { inv: 0, pag: 0, otras: 0, n: 0, firma: 0, proys: {} };
          d.n++;
          if (firmaPend[v.contrato_id]) d.firma++;
          if (c2.proyecto_nombre) d.proys[c2.proyecto_nombre] = 1;
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
        pon2('k-lista-pie', cs.length > 200 ? 'Se enseñan 200 de ' + cs.length + ' compradores — usa el buscador para el resto' : cs.length + (cs.length === 1 ? ' comprador' : ' compradores') + ' · pulsa uno para abrir su ficha');

        /* ================= LA FICHA (cajon compartido de editores.js) ================= */
        var KYC = { pending: ['Pendiente', 'espera'], submitted: ['En revisión', 'espera'], verified: ['Aprobado', 'ok'], rejected: ['Rechazado', 'mal'] };
        var IDIOMA = { es: 'Español', en: 'English', id: 'Bahasa Indonesia' };
        // mismas etiquetas que DOCS en /intranet/compradores/ (alli viven dentro del HTML: no hay fuente compartida que importar)
        var DOC_TIPO = { passport: 'Pasaporte', npwp: 'NPWP', visa: 'Visado', proof_of_funds: 'Justificante de fondos', proof_of_address: 'Justificante de domicilio', signed_contract: 'Contrato firmado', other: 'Otro' };
        var TIPO_DOC_FAC = { factura: 'Factura', proforma: 'Proforma', recibi: 'Recibí' };
        var porId = {}; cs.forEach(function (c2) { porId[c2.id] = c2; });

        /* Portal del comprador — misma Edge Function que /intranet/compradores/
           (portal-invitar): el body nunca decide el permiso, lo decide el JWT
           del admin en servidor. Códigos → mensaje humano, calcados de la viva
           (18-sep-2026, paridad S6). */
        var MOTIVOS_PORTAL = {
          ese_email_es_del_equipo: 'Ese correo ya es de un usuario del equipo. Una misma cuenta no puede ser del equipo y del portal a la vez. Para probar el portal, usa otro correo (con Gmail vale tucorreo+portal@gmail.com: llega al mismo buzón y cuenta como distinto).',
          email_invalido: 'Ese correo no tiene una forma válida.',
          sin_fichas: 'No se ha podido saber a qué ficha dar acceso. Recarga la página e inténtalo otra vez.',
          no_autorizado: 'Hace falta ser administrador para invitar o revocar accesos.',
          sin_sesion: 'Tu sesión ha caducado. Vuelve a entrar.',
          sesion_invalida: 'Tu sesión ha caducado. Vuelve a entrar.',
          password_corta: 'La contraseña necesita 10 caracteres o más.',
          no_es_cuenta_de_portal: 'Ese email no tiene acceso al portal todavía — invítalo primero.'
        };
        function motivoPortal(e) { return MOTIVOS_PORTAL[e] || e; }
        function llamaPortal(body) {
          return sb.auth.getSession().then(function (s) {
            /* Sesión caducada = `data.session` null, sin error de por medio.
               Sin esta comprobación, leer `.access_token` de null tira una
               excepción DENTRO del .then y ningún caller de llamaPortal lleva
               .catch — el botón se quedaba disabled para siempre y sin avisar
               (hallazgo code-review 21-sep-2026). Se devuelve el mismo código
               que ya traduce MOTIVOS_PORTAL, así el caller no cambia nada. */
            if (!(s && s.data && s.data.session && s.data.session.access_token)) {
              return { error: 'sin_sesion' };
            }
            return fetch('https://vtulllundrfennhjddhc.supabase.co/functions/v1/portal-invitar', {
              method: 'POST',
              headers: { 'content-type': 'application/json', authorization: 'Bearer ' + s.data.session.access_token },
              body: JSON.stringify(body)
            }).then(function (r) { return r.json(); }, function () { return { error: 'respuesta ilegible' }; });
          }, function () { return { error: 'sin_sesion' }; });
        }

        function quitaId() {
          var u2 = new URL(location.href);
          if (u2.searchParams.has('id')) { u2.searchParams.delete('id'); history.replaceState(null, '', u2.href); }
        }
        function seccionEstadoCuentas(vins, H) {
          if (!vins.length) return H.nota('Sin contrato enlazado todavía.');
          var suyos = vins.map(function (v) { return porC[v.contrato_id]; });
          var monedas = {}; suyos.forEach(function (x) { monedas[x.moneda || 'EUR'] = 1; });
          var lista = Object.keys(monedas);
          var cobrado = suyos.reduce(function (a, x) { return a + (cobId[x.id] || 0); }, 0);
          if (lista.length > 1) {
            return H.nota('Sus contratos están en monedas distintas (' + lista.join(', ') + '): no hay una sola cifra. El detalle por contrato está arriba.') +
              H.dato('Cobrado (recibís, todas las monedas)', suyos.map(function (x) { return fmt(cobId[x.id] || 0, x.moneda || 'EUR'); }).join(' · '));
          }
          var moneda = lista[0];
          var sumables = suyos.filter(function (x) { return !esPre(x.tipo); });
          if (!sumables.length) {
            return H.nota('Solo tiene Carta(s) de Reserva: el precio final de la villa lo fija el contrato que la sustituya. La cuota de reserva sí es exigible — se ve en la herramienta clásica.') +
              H.dato('Cobrado', fmt(cobrado, moneda));
          }
          var precio = sumables.reduce(function (a, x) { return a + (Number(x.precio_total) || 0); }, 0);
          var pendiente = precio - cobrado;
          return '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;text-align:center">' +
            ['Precio pactado', 'Cobrado', 'Pendiente'].map(function (etq, i) {
              var v = [precio, cobrado, pendiente][i];
              var color = i === 1 ? '#3F5230' : (i === 2 && pendiente > 0 ? '#9E2F26' : '#2E3437');
              return '<div><div style="font-size:10.5px;letter-spacing:.08em;text-transform:uppercase;color:#75786e">' + etq + '</div>' +
                '<div style="font-size:18px;font-weight:700;color:' + color + '">' + esc(fmt(v, moneda)) + '</div></div>';
            }).join('') + '</div>' +
            '<p style="margin:6px 0 0;font-size:11.5px;color:#75786e">Solo cuenta como cobrado el recibí — una factura o proforma es lo que se debe, no lo pagado.' +
            (sumables.length !== suyos.length ? ' El precio no cuenta las Cartas de Reserva.' : '') + '</p>';
        }
        /* La ficha COMPLETA se pide al abrir, y solo la de ese comprador. Si
           la consulta falla se pinta con lo que el listado ya sabe y se avisa:
           una ficha a medias sin decirlo es la familia de LAW-186. */
        var CAMPOS_FICHA = 'id,full_name,email,phone,nationality,passport_number,tipo,forma_juridica,registro_num,rep_nombre,rep_cargo,kyc_status,idioma_comunicacion,notes,propietario,created_at';
        function abreFicha(c0) {
          var H = window.lwCajonHtml;
          if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
          sb.from('clients').select(CAMPOS_FICHA).eq('id', c0.id).maybeSingle().then(function (r) {
            if (r.error || !r.data) {
              console.error('[v4 datos] ficha de comprador', r.error);
              toast('No se pudo leer la ficha completa: se enseña lo que hay en el listado.');
              pintaFicha(c0);
            } else pintaFicha(r.data);
          });
        }
        function pintaFicha(c2) {
          var H = window.lwCajonHtml;
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.comprador = c2;
          var esEmpresa = c2.tipo === 'empresa';
          var vins = vin.filter(function (v) { return v.client_id === c2.id && porC[v.contrato_id]; });
          var kyc = KYC[c2.kyc_status || 'pending'] || [c2.kyc_status, 'neutro'];
          var identidad =
            H.dato('Tipo', esEmpresa ? 'Empresa' : 'Persona física') +
            H.dato('Email', c2.email) +
            H.dato('Teléfono', c2.phone ? H.enlace('https://wa.me/' + String(c2.phone).replace(/[^0-9]/g, ''), c2.phone, true) : null, { html: 1 }) +
            H.dato(esEmpresa ? 'País de constitución' : 'Nacionalidad', c2.nationality) +
            H.dato(esEmpresa ? 'Identificación fiscal' : 'Pasaporte / NPWP', c2.passport_number) +
            (esEmpresa
              ? H.dato('Forma jurídica', c2.forma_juridica) + H.dato('Nº de registro', c2.registro_num) +
                H.dato('Representante legal', [c2.rep_nombre, c2.rep_cargo].filter(Boolean).join(' · '))
              : '') +
            H.dato('Idioma de comunicación', IDIOMA[c2.idioma_comunicacion || 'es'] || c2.idioma_comunicacion) +
            H.dato('KYC', H.tag(kyc[0], kyc[1]), { html: 1 }) +
            H.dato('Alta en la suite', fFecha(c2.created_at)) +
            (c2.notes ? H.dato('Notas', c2.notes) : '');
          var quienAlta = c2.propietario
            ? 'La dio de alta <b>' + esc(nombreEquipo[String(c2.propietario).toLowerCase()] || c2.propietario) + '</b>' +
              ((window.LW_V4.miEmail || '').toLowerCase() === String(c2.propietario).toLowerCase() ? ' (tú)' : '') + '.'
            : '<b>Nadie.</b> Ficha antigua sin autor: hoy solo la corrige un administrador.';
          /* Traspasar la ficha (14-sep en la clásica, paridad 21-sep). Sin RPC
             por defecto: la policy «admins actualizan clientes» ya deja a un
             admin escribir `propietario` — solo con la casilla de arrastrar
             contratos/facturas entra `traspasar_cliente_con_documentos`. */
          function seccionResponsable() {
            var base = H.nota(quienAlta, true);
            if (!window.LW_V4.esAdmin) return base;
            var opciones = eq.map(function (u) {
              return '<option value="' + esc(u.email) + '"' + (String(c2.propietario || '').toLowerCase() === String(u.email).toLowerCase() ? ' selected' : '') + '>' + esc(u.nombre || u.email) + '</option>';
            }).join('');
            var controles = '<div style="display:grid;gap:8px;margin-top:10px;padding-top:10px;border-top:1px solid rgba(228,220,203,.7)">' +
              '<div style="display:flex;gap:8px;align-items:flex-end;flex-wrap:wrap">' +
              '<label style="display:grid;gap:4px;font-size:11.5px;color:#75786e;flex:1;min-width:160px">Pasar la ficha a<select data-tr-sel style="width:100%;box-sizing:border-box;padding:7px 9px;border:1px solid #E4DCCB;border-radius:8px;font-size:13px;color:#2E3437;background:#fff">' + opciones + '</select></label>' +
              '<button type="button" data-tr-btn style="padding:9px 16px;border-radius:8px;border:0;background:#104C4F;color:#fff;font-weight:600;font-size:13px;cursor:pointer">Traspasar</button>' +
              '</div>';
            if (window.LW_V4.esSuperAdmin) {
              controles += '<label style="display:flex;gap:8px;align-items:flex-start;font-size:12px;color:#2E3437;margin-top:2px">' +
                '<input type="checkbox" data-tr-chk style="margin-top:2px">' +
                '<span>Arrastrar también sus contratos y facturas (solo los que sean de ' + esc(nombreEquipo[String(c2.propietario || '').toLowerCase()] || c2.propietario || '—') + ')</span></label>' +
                '<div data-tr-caja hidden style="display:grid;gap:4px">' +
                '<label style="font-size:11.5px;color:#75786e">Motivo<input type="text" data-tr-motivo maxlength="180" placeholder="Ej. Ana deja el equipo, sus clientes pasan a Carmen" style="width:100%;box-sizing:border-box;padding:7px 9px;border:1px solid #E4DCCB;border-radius:8px;font-size:13px;color:#2E3437;background:#fff"></label></div>';
            }
            controles += '<p style="margin:8px 0 0;font-size:11.5px;color:#75786e">Quien la reciba podrá abrirla y corregirla (mientras no cuelgue de un contrato firmado); los demás la seguirán viendo en el directorio, solo de consulta. Sin marcar la casilla, los contratos y las facturas NO se mueven: el traspaso es solo de la ficha.</p></div>';
            return base + controles;
          }
          var contratos = vins.length
            ? H.tabla(['Contrato', 'Proyecto', 'Rol', 'Estado'], vins.map(function (v) {
                var k = porC[v.contrato_id];
                return [
                  (k.numero ? H.enlace('/intranet/v4/contratos/?contrato=' + encodeURIComponent(k.numero), k.numero) : 'sin nº') +
                    '<div style="font-size:11px;color:#75786e">' + esc(tipoC(k.tipo)) + '</div>',
                  esc(k.proyecto_nombre || '—'),
                  esc(String(v.rol || '').replace('adquiriente_', 'Adquiriente ')),
                  k.bloqueado ? H.tag('Firmado', 'ok') : (firmaPend[k.id] ? H.tag('En firma', 'espera') : H.tag('Sin firmar', 'neutro'))
                ];
              }))
            : H.nota('Ninguno enlazado todavía. El enlace se crea solo al guardar un contrato con su pasaporte o su email.');
          var cuerpo =
            H.seccion('Identidad', identidad) +
            H.seccion('Responsable de la ficha', seccionResponsable()) +
            H.seccion('Contratos (' + vins.length + ')', contratos) +
            H.seccion('Estado de cuentas', seccionEstadoCuentas(vins, H)) +
            H.seccion('Facturas', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'facturas') +
            H.seccion('Documentación KYC', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'docs') +
            H.seccion('Portal del comprador', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'portal');
          var acciones = [
            { texto: 'Editar datos', tono: 'primario', onClick: function () {
              if (window.LW_V4.abreEditaComprador) window.LW_V4.abreEditaComprador(c2);
              else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
            } },
            // pestaña nueva a proposito: quien repasa fichas no quiere perder la lista
            { texto: 'Crear contrato', href: '/contracts/?cliente=' + encodeURIComponent(c2.id), nuevaPestana: true }
          ];
          /* Borrar: SOLO super_admin, calcado de la clásica — la puerta real es
             `borrar_comprador()` en la base (es_super_admin() + bloqueos por
             contrato/portal), esto solo evita ofrecer lo que fallaría. */
          if (window.LW_V4.esSuperAdmin) {
            acciones.push({ texto: 'Borrar la ficha', tono: 'peligro', onClick: function () {
              lwConfirmar({
                titulo: 'Borrar la ficha de ' + (c2.full_name || 'este comprador'),
                cuerpo: '<p>Se borra la ficha y sus documentos KYC del archivo privado, si los tuviera.</p>' +
                  '<p>Si estuviera vinculada a un contrato o tuviera acceso al portal, el sistema lo impide y te dice cuál — esta acción es para <b>duplicados sueltos</b>.</p>' +
                  '<p>No hay papelera.</p>',
                confirmar: 'Borrar la ficha', tono: 'peligro'
              }).then(function (ok) {
                if (!ok) return;
                sb.rpc('borrar_comprador', { p_client_id: c2.id }).then(function (r) {
                  if (r.error) { toastMal(r.error.message); return; }
                  var rutas = (r.data && r.data.rutas_kyc) || [];
                  var limpia = rutas.length ? sb.storage.from('kyc').remove(rutas) : Promise.resolve({});
                  limpia.then(function (rs) {
                    if (rs && rs.error) toastMal('Ficha borrada, pero ' + rutas.length + ' fichero(s) KYC no se pudieron quitar del bucket: ' + rs.error.message);
                    toast('Ficha de ' + ((r.data && r.data.nombre) || 'comprador') + ' borrada' + (rutas.length ? ' · ' + rutas.length + ' documento(s) retirados' : ''));
                    cj.cierra();
                    location.reload();
                  });
                });
              });
            } });
          }
          acciones.push({ texto: 'Cerrar', cerrar: true });
          var cj = window.lwCajon({ sub: esEmpresa ? 'Ficha de empresa compradora' : 'Ficha de comprador', titulo: c2.full_name || 'Sin nombre',
            bajoTitulo: [c2.nationality, c2.passport_number].filter(Boolean).join(' · ') || 'sin identificación',
            cuerpo: cuerpo, acciones: acciones, alCerrar: quitaId });
          var u2 = new URL(location.href);
          u2.searchParams.set('id', c2.id);
          history.replaceState(null, '', u2.href);

          /* Traspaso: wiring de los controles que seccionResponsable() acaba de
             pintar (viven en el cuerpo del cajon ya montado). */
          var bTr = cj.cuerpo.querySelector('[data-tr-btn]');
          if (bTr) {
            var chkTodo = cj.cuerpo.querySelector('[data-tr-chk]');
            var cajaMotivo = cj.cuerpo.querySelector('[data-tr-caja]');
            if (chkTodo) chkTodo.addEventListener('change', function () { if (cajaMotivo) cajaMotivo.hidden = !chkTodo.checked; });
            bTr.addEventListener('click', function () {
              var sel = cj.cuerpo.querySelector('[data-tr-sel]');
              var nuevo = sel && sel.value;
              if (!nuevo) return;
              if (String(c2.propietario || '').toLowerCase() === nuevo.toLowerCase()) { toastMal('Esa ficha ya es suya.'); return; }
              var conDocumentos = !!(chkTodo && chkTodo.checked);
              var motivoEl = cj.cuerpo.querySelector('[data-tr-motivo]');
              var motivo = ((motivoEl && motivoEl.value) || '').trim();
              if (conDocumentos && motivo.length < 3) { toastMal('Escribe el motivo: es lo que explica el traspaso dentro de un año.'); return; }
              var nombreNuevo = nombreEquipo[nuevo.toLowerCase()] || nuevo;
              lwConfirmar({
                titulo: 'Pasar la ficha de ' + (c2.full_name || '—') + ' a ' + nombreNuevo,
                cuerpo: '<p>' + (conDocumentos
                  ? 'Se traspasarán también los contratos y las facturas de ' + esc(nombreEquipo[String(c2.propietario || '').toLowerCase()] || c2.propietario || '—') + '. Lo que ya sea de otra persona, o esté firmado o anulado, no se mueve y queda a la vista para revisarlo a mano.'
                  : 'Podrá abrirla y corregirla. Sus contratos y sus facturas no se mueven.') + '</p>',
                confirmar: 'Traspasar'
              }).then(function (ok) {
                if (!ok) return;
                bTr.disabled = true;
                /* `.select('id')` en la rama sin documentos: un UPDATE que la
                   policy filtra no da error, devuelve 0 filas — sin comprobar
                   `r.data.length` el cajon diría «traspasada» sin haber
                   tocado nada (mismo fallo que `unaFila()` ya evita en
                   editores.js; hallazgo code-review 21-sep-2026). */
                var p = conDocumentos
                  ? sb.rpc('traspasar_cliente_con_documentos', { p_client_id: c2.id, p_nuevo_propietario: nuevo, p_motivo: motivo })
                  : sb.from('clients').update({ propietario: nuevo }).eq('id', c2.id).select('id');
                p.then(function (r) {
                  bTr.disabled = false;
                  if (r.error) { toastMal('No se pudo traspasar: ' + r.error.message); return; }
                  if (!conDocumentos && !(r.data && r.data.length)) {
                    toastMal('No se ha traspasado: la base no te ha dejado tocar esta ficha. Habla con un administrador — recargar no lo arregla.');
                    return;
                  }
                  if (conDocumentos) {
                    var res = (r.data && r.data[0]) || {};
                    lwConfirmar({
                      titulo: 'Traspaso de ' + (c2.full_name || '—'),
                      cuerpo: '<p>Contratos: ' + (res.contratos_movidos || 0) + ' movidos · ' + (res.contratos_omitidos_firmados || 0) + ' firmados sin tocar · ' + (res.contratos_omitidos_otro_autor || 0) + ' de otro autor · ' + (res.contratos_omitidos_sin_autor || 0) + ' sin autor.</p>' +
                        '<p>Facturas y recibís: ' + (res.facturas_movidas || 0) + ' movidas (' + (res.facturas_movidas_anuladas || 0) + ' anuladas incluidas) · ' + (res.facturas_omitidas_otro_autor || 0) + ' de otro autor · ' + (res.facturas_omitidas_sin_autor || 0) + ' sin autor.</p>',
                      confirmar: 'Entendido', cancelar: false
                    }).then(function () { cj.cierra(); location.reload(); });
                  } else {
                    toast('Ficha traspasada a ' + nombreNuevo);
                    cj.cierra(); location.reload();
                  }
                });
              });
            });
          }

          var pinta = function (id, html) {
            var s = cj.cuerpo.querySelector('[data-cajon-sec="' + id + '"] > div');
            if (s) s.innerHTML = html;
          };
          var ids = vins.map(function (v) { return v.contrato_id; });

          /* Lo que cuesta una consulta se pide al abrir, no al listar 200
             fichas: facturas de SUS contratos, sus documentos y su acceso al
             portal. `facturas_equipo` y no `.from('facturas')`: la RLS por
             agente dejaria fuera las de un contrato guardado por otro. */
          if (!ids.length) pinta('facturas', H.nota('Sin contrato enlazado, no hay a qué factura atarla.'));
          else sb.rpc('facturas_equipo').select('id,numero,tipo,contrato_numero,proyecto_nombre,total,moneda,fecha_emision,anulada')
            .in('contrato_id', ids).order('fecha_emision', { ascending: false }).then(function (rf) {
              if (rf.error) return pinta('facturas', H.nota('No se pudieron leer las facturas: ' + rf.error.message));
              var fs = rf.data || [];
              if (!fs.length) return pinta('facturas', H.nota('Ninguna factura emitida todavía en sus contratos.'));
              var vivas = fs.filter(function (x) { return !x.anulada; }), nulas = fs.filter(function (x) { return x.anulada; });
              var tabla = function (lista) {
                return H.tabla(['Nº', 'Tipo', 'Contrato · unidad', 'Fecha', 'Importe'], lista.map(function (x) {
                  return [
                    H.enlace(URL_FACTURA(x.id), x.numero || 'borrador', true),
                    esc(TIPO_DOC_FAC[x.tipo] || x.tipo || '—'),
                    esc([x.contrato_numero, x.proyecto_nombre].filter(Boolean).join(' · ') || '—'),
                    esc(fFecha(x.fecha_emision)),
                    '<span style="white-space:nowrap">' + esc(x.total != null ? fmt(Number(x.total), x.moneda) : '—') + '</span>'
                  ];
                }));
              };
              // las anuladas se APARTAN, no se esconden: un contador a la vista
              pinta('facturas', (vivas.length ? tabla(vivas) : H.nota('Ninguna vigente: todas sus facturas están anuladas.')) +
                (nulas.length ? '<details style="font-size:12px;color:#75786e"><summary style="cursor:pointer">' + nulas.length + (nulas.length === 1 ? ' anulada' : ' anuladas') + ' · no cuentan</summary>' + tabla(nulas) + '</details>' : ''));
            });

          /* Documentación KYC: tabla + subir + borrar (admin). Función nombrada
             porque se vuelve a llamar tras subir/retirar — sin recargar toda la
             página, igual que hace el resto del cajon. */
          function cargaDocs() {
            sb.from('documents').select('id,doc_type,storage_path,uploaded_at,caduca_el').eq('client_id', c2.id).order('uploaded_at', { ascending: false })
              .then(function (rd) {
                if (rd.error) return pinta('docs', H.nota('No se pudieron leer los documentos: ' + rd.error.message));
                var ds = rd.data || [];
                var hoy = new Date(); hoy.setHours(0, 0, 0, 0);
                var tablaDocs = ds.length ? H.tabla(['Documento', 'Subido', 'Caduca', ''], ds.map(function (d) {
                  var cad = '<span style="color:#75786e">sin caducidad</span>';
                  if (d.caduca_el) {
                    var dd = Math.round((new Date(d.caduca_el + 'T00:00:00') - hoy) / 86400000);
                    cad = dd < 0 ? H.tag('caducado hace ' + (-dd) + ' d', 'mal') : (dd <= 60 ? H.tag(fFecha(d.caduca_el), 'espera') : H.tag(fFecha(d.caduca_el), 'ok'));
                  }
                  var acciones2 = (d.storage_path ? '<button type="button" data-doc-path="' + esc(d.storage_path) + '" style="padding:4px 10px;border-radius:999px;border:1px solid #E4DCCB;background:#fff;font-size:12px;cursor:pointer;color:#104C4F;font-weight:600">Abrir</button>' : '') +
                    (window.LW_V4.esAdmin ? '<button type="button" data-doc-borrar="' + esc(d.id) + '" style="margin-left:6px;padding:4px 10px;border-radius:999px;border:1px solid #9E2F26;background:#fff;font-size:12px;cursor:pointer;color:#9E2F26;font-weight:600">Borrar</button>' : '');
                  return [esc(DOC_TIPO[d.doc_type] || d.doc_type || '—'), esc(fFecha(d.uploaded_at)), cad, acciones2];
                })) : H.nota('Sin documentos todavía.');
                var formSubida = '<div style="display:grid;gap:8px;margin-top:10px;padding-top:10px;border-top:1px solid rgba(228,220,203,.7)">' +
                  '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">' +
                  '<label style="display:grid;gap:4px;font-size:11.5px;color:#75786e">Tipo<select data-doc-tipo style="padding:7px 9px;border:1px solid #E4DCCB;border-radius:8px;font-size:13px;color:#2E3437;background:#fff">' +
                  Object.keys(DOC_TIPO).map(function (k) { return '<option value="' + esc(k) + '">' + esc(DOC_TIPO[k]) + '</option>'; }).join('') +
                  '</select></label>' +
                  '<label style="display:grid;gap:4px;font-size:11.5px;color:#75786e">Caduca el (opcional)<input type="date" data-doc-caduca style="padding:7px 9px;border:1px solid #E4DCCB;border-radius:8px;font-size:13px;color:#2E3437;background:#fff"></label>' +
                  '</div>' +
                  '<label style="display:grid;gap:4px;font-size:11.5px;color:#75786e">Fichero<input type="file" data-doc-file accept="application/pdf,image/*" style="font-size:13px"></label>' +
                  '<button type="button" data-doc-subir style="align-self:start;padding:9px 16px;border-radius:8px;border:0;background:#104C4F;color:#fff;font-weight:600;font-size:13px;cursor:pointer">Subir documento</button>' +
                  '<p style="margin:0;font-size:11px;color:#75786e">Van a un bucket privado. Al abrirlos se genera un enlace temporal de 5 minutos, no una URL fija.</p>' +
                  '</div>';
                pinta('docs', tablaDocs + formSubida);

                /* Bucket privado: enlace temporal de 5 minutos, nunca una URL fija
                   — igual que la herramienta clásica. */
                cj.cuerpo.querySelectorAll('[data-doc-path]').forEach(function (b) {
                  b.addEventListener('click', function () {
                    b.disabled = true;
                    sb.storage.from('kyc').createSignedUrl(b.getAttribute('data-doc-path'), 300).then(function (ru) {
                      b.disabled = false;
                      if (ru.error || !(ru.data && ru.data.signedUrl)) return toast('No se pudo abrir el documento' + (ru.error ? ': ' + ru.error.message : ''));
                      window.open(ru.data.signedUrl, '_blank', 'noopener');
                    });
                  });
                });
                /* 🔴 Con RLS activa un DELETE sin permiso no da error: devuelve 0
                   filas. Se comprueba `count`, no solo `error` (mismo fallo que
                   ya se corrigió en la clásica el 27-ago). */
                cj.cuerpo.querySelectorAll('[data-doc-borrar]').forEach(function (b) {
                  b.addEventListener('click', function () {
                    var idDoc = b.getAttribute('data-doc-borrar');
                    var d = ds.filter(function (x) { return x.id === idDoc; })[0];
                    if (!d) return;
                    var nombreDoc = DOC_TIPO[d.doc_type] || d.doc_type || 'documento';
                    lwConfirmar({
                      titulo: 'Retirar ' + nombreDoc,
                      cuerpo: '<p>Se retira <b>' + esc(nombreDoc) + '</b>' + (d.uploaded_at ? ' (subido el ' + esc(fFecha(d.uploaded_at)) + ')' : '') + ' de la ficha, y su fichero del archivo privado.</p><p>No hay papelera: si el documento sigue haciendo falta habrá que volver a subirlo.</p>',
                      confirmar: 'Retirar el documento', tono: 'peligro'
                    }).then(function (ok) {
                      if (!ok) return;
                      b.disabled = true; b.textContent = 'Retirando…';
                      sb.from('documents').delete({ count: 'exact' }).eq('id', idDoc).then(function (r) {
                        if (r.error || !r.count) {
                          b.disabled = false; b.textContent = 'Borrar';
                          toastMal(r.error ? 'No se pudo retirar: ' + r.error.message : 'No se ha retirado: tu usuario no tiene permiso para borrar documentos.');
                          return;
                        }
                        var limpia = d.storage_path ? sb.storage.from('kyc').remove([d.storage_path]) : Promise.resolve({});
                        limpia.then(function (rs) {
                          if (rs && rs.error) toastMal('Documento retirado de la ficha, pero su fichero sigue en el archivo (' + d.storage_path + '): ' + rs.error.message);
                          toast(nombreDoc + ' retirado');
                          cargaDocs();
                        });
                      });
                    });
                  });
                });
                var bSub = cj.cuerpo.querySelector('[data-doc-subir]');
                if (bSub) bSub.addEventListener('click', function () {
                  var fEl = cj.cuerpo.querySelector('[data-doc-file]');
                  var f = fEl && fEl.files && fEl.files[0];
                  if (!f) { toastMal('Elige un fichero'); return; }
                  if (f.size > 20 * 1024 * 1024) { toastMal('El fichero supera los 20 MB'); return; }
                  bSub.disabled = true; bSub.textContent = 'Subiendo…';
                  var tipoDoc = cj.cuerpo.querySelector('[data-doc-tipo]').value;
                  var caduca = cj.cuerpo.querySelector('[data-doc-caduca]').value || null;
                  var limpio = f.name.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^\w.-]/g, '_');
                  var path = c2.id + '/' + Date.now() + '_' + limpio;
                  sb.storage.from('kyc').upload(path, f, { upsert: false, contentType: f.type || 'application/octet-stream' }).then(function (up) {
                    if (up.error) { bSub.disabled = false; bSub.textContent = 'Subir documento'; toastMal('No se pudo subir: ' + up.error.message); return; }
                    // el fichero ya subió: si el insert falla no se reintenta el upload, se avisa igual
                    sb.from('documents').insert({ client_id: c2.id, doc_type: tipoDoc, storage_path: path, status: 'pending', caduca_el: caduca }).then(function (ins) {
                      bSub.disabled = false; bSub.textContent = 'Subir documento';
                      if (ins.error) { toastMal('El fichero se subió pero no se pudo registrar en la ficha: ' + ins.error.message); return; }
                      toast('Documento subido');
                      cargaDocs();
                    });
                  });
                });
              });
          }

          /* Portal del comprador: invitar/reenviar/contraseña/revocar (admin),
             vista previa (cualquiera) y acceso a tickets. */
          function cargaPortal() {
            sb.from('portal_accesos').select('email,activo,ultimo_acceso,accesos').eq('client_id', c2.id).then(function (rp) {
              if (rp.error) return pinta('portal', H.nota('No se pudo leer el acceso al portal: ' + rp.error.message));
              var suyos = rp.data || [], activos = suyos.filter(function (x) { return x.activo; });
              var rastro = function (a) {
                return !a.accesos ? H.tag('sin estrenar', 'espera')
                  : H.tag(a.accesos + (a.accesos === 1 ? ' entrada' : ' entradas'), 'ok') + (a.ultimo_acceso ? ' <span style="font-size:11px;color:#75786e">última: ' + esc(fFecha(a.ultimo_acceso)) + '</span>' : '');
              };
              var estado;
              if (activos.length) {
                estado = activos.map(function (a) { return H.dato(a.email, rastro(a), { html: 1 }); }).join('') +
                  '<p style="margin:4px 0 0;font-size:11.5px;color:#75786e">Ve sus contratos, pagos, facturas y obra en /portal/.</p>';
              } else if (suyos.length) {
                estado = H.nota('Acceso REVOCADO. Se puede volver a invitar desde aquí; mientras haya una fila revocada, la entrada automática no se la devuelve.');
              } else if (c2.email && vins.length) {
                estado = H.nota('Entra solo: con ' + esc(c2.email) + ' y sus contratos, el portal le abre la puerta sin invitación (salvo que ese correo sea de alguien del equipo).', true);
              } else {
                estado = H.nota('Sin acceso todavía. La entrada automática pide correo en la ficha y al menos un contrato — le falta ' + (c2.email ? 'el contrato' : 'el correo') + '.');
              }
              var botonesTop = '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:8px">' +
                '<button type="button" data-portal-preview style="padding:7px 14px;border-radius:8px;border:1px solid #E4DCCB;background:#fff;color:#104C4F;font-weight:600;font-size:12.5px;cursor:pointer">Vista previa del portal</button>' +
                '<button type="button" data-portal-tickets style="padding:7px 14px;border-radius:8px;border:1px solid #E4DCCB;background:#fff;color:#104C4F;font-weight:600;font-size:12.5px;cursor:pointer">Ver tickets →</button>' +
                '</div>';
              var controles;
              if (window.LW_V4.esAdmin) {
                var emailPre = (activos[0] && activos[0].email) || c2.email || '';
                controles = '<div style="display:grid;gap:8px;margin-top:10px;padding-top:10px;border-top:1px solid rgba(228,220,203,.7)">' +
                  '<label style="display:grid;gap:4px;font-size:11.5px;color:#75786e">Email de acceso<input type="email" data-portal-email value="' + esc(emailPre) + '" style="padding:7px 9px;border:1px solid #E4DCCB;border-radius:8px;font-size:13px;color:#2E3437;background:#fff"></label>' +
                  '<div style="display:flex;gap:8px;flex-wrap:wrap">' +
                  '<button type="button" data-portal-invitar style="padding:9px 16px;border-radius:8px;border:0;background:#104C4F;color:#fff;font-weight:600;font-size:13px;cursor:pointer">' + (activos.length ? 'Reenviar enlace' : 'Invitar al portal') + '</button>' +
                  (activos.length ? '<button type="button" data-portal-pass style="padding:9px 16px;border-radius:8px;border:1px solid #E4DCCB;background:#fff;color:#2E3437;font-weight:600;font-size:13px;cursor:pointer">Ponerle contraseña</button>' : '') +
                  (activos.length ? '<button type="button" data-portal-revocar style="padding:9px 16px;border-radius:8px;border:1px solid #9E2F26;background:#fff;color:#9E2F26;font-weight:600;font-size:13px;cursor:pointer">Revocar acceso</button>' : '') +
                  '</div></div>';
              } else {
                controles = '<p style="margin:8px 0 0;font-size:11.5px;color:#75786e">Invitar o revocar lo hace un administrador.</p>';
              }
              pinta('portal', botonesTop + estado + controles);

              var bPrev = cj.cuerpo.querySelector('[data-portal-preview]');
              if (bPrev) bPrev.addEventListener('click', abrePreviewPortal);
              var bTick = cj.cuerpo.querySelector('[data-portal-tickets]');
              if (bTick) bTick.addEventListener('click', function () {
                window.open('/intranet/soporte/?id=' + encodeURIComponent(c2.id), '_blank', 'noopener');
              });

              if (window.LW_V4.esAdmin) {
                var campoEmail = cj.cuerpo.querySelector('[data-portal-email]');
                var bInv = cj.cuerpo.querySelector('[data-portal-invitar]');
                if (bInv) bInv.addEventListener('click', function () {
                  var email = (campoEmail.value || '').trim().toLowerCase();
                  if (!email) { toastMal('Falta el email de acceso'); return; }
                  lwConfirmar({
                    titulo: 'Invitar a ' + email + ' al portal',
                    cuerpo: '<p>Se le envía un <b>correo de acceso</b> y podrá ver en el portal todo lo de esta ficha: contratos, pagos, facturas y obra.</p>',
                    confirmar: 'Enviar la invitación'
                  }).then(function (ok) {
                    if (!ok) return;
                    bInv.disabled = true;
                    llamaPortal({ accion: 'invitar', email: email, client_ids: [c2.id] }).then(function (r) {
                      bInv.disabled = false;
                      if (r.error) { toastMal(motivoPortal(r.error)); return; }
                      toast(r.aviso ? 'Acceso creado, pero el correo no salió: reenvía en un rato' : 'Invitación enviada');
                      cargaPortal();
                    });
                  });
                });
                var bPass = cj.cuerpo.querySelector('[data-portal-pass]');
                if (bPass) bPass.addEventListener('click', function () {
                  var email = (campoEmail.value || '').trim().toLowerCase() || (activos[0] && activos[0].email);
                  if (!email) return;
                  var p = prompt('Nueva contraseña para ' + email + ' (mínimo 10 caracteres).\nApúntala: no se puede volver a consultar, solo cambiar por otra.');
                  if (p === null) return;
                  if (p.length < 10) { toastMal('Mínimo 10 caracteres'); return; }
                  bPass.disabled = true;
                  llamaPortal({ accion: 'password', email: email, password: p }).then(function (r) {
                    bPass.disabled = false;
                    if (r.error) { toastMal(motivoPortal(r.error)); return; }
                    toast('Contraseña puesta. Pásasela tú: no queda guardada en ningún sitio consultable.');
                  });
                });
                var bRev = cj.cuerpo.querySelector('[data-portal-revocar]');
                if (bRev) bRev.addEventListener('click', function () {
                  var email = activos[0] && activos[0].email;
                  if (!email) return;
                  lwConfirmar({
                    titulo: 'Revocar el acceso de ' + email,
                    cuerpo: '<p>Dejará de ver <b>todas</b> las fichas vinculadas a ese email, no solo ésta.</p>',
                    confirmar: 'Revocar el acceso', tono: 'peligro'
                  }).then(function (ok) {
                    if (!ok) return;
                    bRev.disabled = true;
                    llamaPortal({ accion: 'revocar', email: email }).then(function (r) {
                      bRev.disabled = false;
                      if (r.error) { toastMal(motivoPortal(r.error)); return; }
                      toast('Acceso revocado');
                      cargaPortal();
                    });
                  });
                });
              }
            });
          }

          /* Vista previa del portal (paridad con la clásica, 15-sep): NO abre
             sesión del comprador — no hay Auth Admin API/service_role en este
             entorno para un magic-link real sin su contraseña (verificado). Lee
             en fresco con el permiso de equipo que esta ficha ya tiene. */
          function abrePreviewPortal() {
            var idsC = vins.map(function (v) { return v.contrato_id; });
            var pContratos = Promise.resolve({ data: vins.map(function (v) { return porC[v.contrato_id]; }).filter(Boolean) });
            var pFacturas = idsC.length
              ? sb.rpc('facturas_equipo').select('id,numero,tipo,contrato_numero,proyecto_nombre,total,moneda,fecha_emision,anulada').in('contrato_id', idsC).order('fecha_emision', { ascending: false })
              : Promise.resolve({ data: [] });
            var pDocs = sb.from('documents').select('id,doc_type,uploaded_at').eq('client_id', c2.id).order('uploaded_at', { ascending: false });
            Promise.all([pContratos, pFacturas, pDocs]).then(function (r) {
              var cts = r[0].data || [];
              var facs = (r[1] && r[1].data) || [];
              var docs = (r[2] && r[2].data) || [];
              var tContratos = cts.length ? H.tabla(['Nº', 'Tipo', 'Estado', 'Precio', 'Cobrado'], cts.map(function (x) {
                return [esc(x.numero || 'borrador'), esc(tipoC(x.tipo)), x.bloqueado ? 'Firmado' : 'Borrador',
                  (!esPre(x.tipo) && x.precio_total != null) ? esc(fmt(Number(x.precio_total), x.moneda)) : '—',
                  esc(fmt(cobId[x.id] || 0, x.moneda))];
              })) : H.nota('Sin contratos.');
              var tFacturas = facs.length ? H.tabla(['Nº', 'Fecha', 'Importe', 'Estado'], facs.map(function (f) {
                return [esc(f.numero || 'borrador'), esc(fFecha(f.fecha_emision)), f.total != null ? esc(fmt(Number(f.total), f.moneda)) : '—', f.anulada ? 'Anulada' : '—'];
              })) : H.nota('Sin facturas.');
              var tDocs = docs.length ? H.tabla(['Documento', 'Subido'], docs.map(function (d) {
                return [esc(DOC_TIPO[d.doc_type] || d.doc_type || '—'), esc(fFecha(d.uploaded_at))];
              })) : H.nota('Sin documentos.');
              lwConfirmar({
                titulo: 'Vista previa del portal — ' + (c2.full_name || ''),
                cuerpo: H.nota('Esto es lo que este comprador ve ahora mismo en /portal/. No se ha abierto ninguna sesión suya: se lee con tu permiso de equipo.') +
                  '<h4 style="margin:14px 0 6px;font-size:13px;color:#104C4F">Contratos</h4>' + tContratos +
                  '<h4 style="margin:14px 0 6px;font-size:13px;color:#104C4F">Facturas</h4>' + tFacturas +
                  '<h4 style="margin:14px 0 6px;font-size:13px;color:#104C4F">Documentos</h4>' + tDocs,
                confirmar: 'Cerrar', cancelar: false
              });
            });
          }

          cargaDocs();
          cargaPortal();
        }
        window.LW_V4 = window.LW_V4 || {};
        window.LW_V4.abreFichaComprador = function (id) { var c2 = porId[id]; if (c2) abreFicha(c2); };

        if (!t) return;
        var pl = plantillaFilas(t);
        cs.slice(0, 200).forEach(function (c2) {
          var d = deCliente[c2.id];
          fila(pl, [
            c2.full_name,
            (c2.email || '—') + (c2.nationality ? ' · ' + c2.nationality : ''),
            c2.tipo === 'empresa' ? 'Empresa' : 'Persona física',
            d ? Object.keys(d.proys).join(' · ') || (d.n + (d.n === 1 ? ' contrato' : ' contratos')) : '—',
            d && d.inv ? fmt(d.inv, 'EUR') : (d && d.otras ? 'otra moneda' : '—'),
            d && d.inv ? fmt(d.pag, 'EUR') + ' · ' + Math.round(d.pag / d.inv * 100) + '%' : (d ? fmt(d.pag, 'EUR') : '—'),
            (KYC[c2.kyc_status || 'pending'] || [c2.kyc_status])[0],
            ''
          ]);
          var tr = pl.tbody.lastElementChild;
          tr.style.cursor = 'pointer';
          tr.setAttribute('data-id', c2.id);
          tr.setAttribute('data-tiene-contrato', d ? '1' : '0');
          tr.setAttribute('data-en-firma', d && d.firma ? '1' : '0');
          tr.lastElementChild.innerHTML = '<button type="button" data-real title="Ver ficha" class="p-1 text-on-surface-variant hover:text-deep-lagoon transition-colors"><span class="material-symbols-outlined text-[18px]">visibility</span></button>';
        });
        pl.tbody.addEventListener('click', function (ev) {
          var tr = ev.target.closest && ev.target.closest('tr[data-id]');
          if (!tr) return;
          ev.preventDefault(); ev.stopPropagation();
          var c2 = porId[tr.getAttribute('data-id')];
          if (c2) abreFicha(c2);
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

        // el buscador de la cabecera: nombre, email, pasaporte o nacionalidad (sobre las filas pintadas)
        var busca = document.getElementById('buyerSearch');
        if (busca) busca.addEventListener('input', function () {
          var qq = busca.value.trim().toLowerCase();
          pl.tbody.querySelectorAll('tr[data-id]').forEach(function (tr) {
            var c2 = porId[tr.getAttribute('data-id')] || {};
            var pajar = [c2.full_name, c2.email, c2.nationality, c2.phone].join(' ').toLowerCase();
            tr.style.display = (!qq || pajar.indexOf(qq) !== -1) ? '' : 'none';
          });
        });

        // ?id= abre la ficha directamente: es adonde apuntan ahora los enlaces
        // «comprador» de Proyectos y Soporte, y adonde vuelve «Editar datos».
        var pedido = new URLSearchParams(location.search).get('id');
        if (pedido && porId[pedido]) setTimeout(function () { abreFicha(porId[pedido]); }, 0);

        /* Ficha≠: el control de divergencia de la suite. Se pide AL FINAL y
           fuera de `vig()` (ver cabecera: 12,7 s en la base) — la pantalla ya
           esta pintada y usable cuando llega. */
        sb.from('documentos_desactualizados').select('congelado,diferencias').limit(1000).then(function (rv) {
          if (rv.error) { console.error('[v4 datos] ficha≠', rv.error); return; }
          var difN = (rv.data || []).filter(function (x) { return x.diferencias && x.diferencias.length; }).length;
          if (difN) bandaNota('Ficha ≠: ' + difN + ' documento(s) emitidos difieren de la ficha del comprador — el detalle vive en la herramienta clásica (/intranet/compradores/).', '#C06C47');
        });
      });
    },
    operaciones: function (sb) {
      var t = tablaPor([/OPERACI|CONTRATO/, /COMPRADOR/, /IMPORTE|ESTADO/]);
      var hoy = new Date().toISOString().slice(0, 10);
      Promise.all([
        q(sb.rpc('contratos_equipo').select(CAMPOS_CONTRATO).order('created_at', { ascending: false }).limit(1000), 'operaciones', t),
        vig(sb.rpc('contratos_cobrado_equipo')).then(function (r) { return r.error ? (fallo('cobrado', r.error), null) : (r.data || []); }),
        q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado,expira_en').eq('estado', 'pendiente'), 'firmas pendientes'),
        q(sb.from('contrato_vencimientos').select('contrato_id,descripcion,fecha,monto').gte('fecha', hoy).order('fecha').limit(1000), 'próximos vencimientos')
      ]).then(function (r) {
        var cs = r[0], cob = r[1] || [], fi = r[2] || [], vs = r[3] || [];
        if (!cs) return;
        var cobId = {}; cob.forEach(function (x) { cobId[x.contrato_id] = Number(x.cobrado) || 0; });
        fi = fi.filter(function (x) { return !firmaCaducada(x); });   // una firma caducada no es «en firma»
        var firmaDe = {}; fi.forEach(function (x) { firmaDe[x.contrato_id] = x; });
        var proxDe = {}; vs.forEach(function (v) { if (!proxDe[v.contrato_id]) proxDe[v.contrato_id] = v; });   // ya vienen por fecha
        var porId = {}; cs.forEach(function (c) { porId[c.id] = c; });
        window.LW_V4 = window.LW_V4 || {}; window.LW_V4.contratosLista = porId;

        /* KPIs — SOLO en euros, como en Contratos: no se mezclan monedas. */
        var eur = 0, otras = 0, firmados = 0, cobEUR = 0, pendEUR = 0, cobBase = 0;
        cs.forEach(function (c) {
          if (c.bloqueado) firmados++;
          if ((c.moneda || 'EUR') !== 'EUR') { if (c.precio_total != null && !esPreliminar(c)) otras++; return; }
          cobEUR += cobId[c.id] || 0;                       // lo cobrado cuenta siempre (también la señal de una carta)
          if (c.precio_total == null || esPreliminar(c)) return;   // el precio de una carta es el de la casa entera: fuera
          var p = Number(c.precio_total) || 0, cb = cobId[c.id] || 0;
          eur += p; cobBase += cb;                           // misma base que el volumen: sin señales de cartas
          if (c.bloqueado) pendEUR += Math.max(0, p - cb);
        });
        pon2('k-volumen', fmt(eur, 'EUR'));
        pon2('k-volumen-pie', cs.length + ' contrato' + (cs.length === 1 ? '' : 's') + ' · ' + firmados + ' firmado' + (firmados === 1 ? '' : 's') + ' · sin cartas de reserva');
        if (otras) bandaNota('El volumen es SOLO en euros: ' + otras + ' contrato(s) en otra moneda fuera de la suma.', '#8A6A34');
        pon2('k-cobros', fmt(cobEUR, 'EUR'));
        var pct = eur ? Math.round(cobBase / eur * 1000) / 10 : 0;   // numerador y denominador con la misma base (Administración, 19-sep)
        pon2('k-cobros-pct', eur ? pct + ' % del volumen en euros, sin señales de cartas' : 'sin volumen en euros');
        var barra = document.querySelector('[data-lw-barra="k-cobros"]'); if (barra) barra.style.width = Math.min(100, pct) + '%';
        var nf = Object.keys(firmaDe).length;
        pon2('k-firmas', String(nf));
        var lim48 = Date.now() + 48 * 3600e3;
        var urg = fi.filter(function (x) { return x.expira_en && new Date(x.expira_en).getTime() < lim48; }).length;
        pon2('k-firmas-pie', nf ? (urg ? urg + ' expira' + (urg === 1 ? '' : 'n') + ' en menos de 48 h' : 'ninguna expira en 48 h') : 'nada esperando firma');
        pon2('k-pendiente', fmt(pendEUR, 'EUR'));

        /* Estado real de cada operación: en firma > en curso > cobrado / cobro pendiente. */
        function estadoDe(c) {
          if (firmaDe[c.id]) return 'firma';
          if (!c.bloqueado) return 'curso';
          if (esPreliminar(c)) return 'reserva';               // firmada: solo cobra la señal, no hay «pendiente»
          if (c.precio_total == null) return 'sinimporte';       // poderes, hak sewa notario…: nada que cobrar
          if ((cobId[c.id] || 0) >= Number(c.precio_total)) return 'cobrado';
          return 'pendiente';
        }
        var ETQ = { firma: ['En firma', 'espera'], curso: ['En curso', ''], cobrado: ['Cobrado', 'ok'], pendiente: ['Cobro pendiente', 'mal'], reserva: ['Reserva firmada', 'ok'], sinimporte: ['Firmado · sin importe', ''] };
        var nEst = { firma: 0, curso: 0, cobrado: 0, pendiente: 0, reserva: 0, sinimporte: 0 };
        cs.forEach(function (c) { nEst[estadoDe(c)]++; });

        if (t) {
          var pl = plantillaFilas(t);
          pon2('p-total', String(cs.length)); pon2('p-desde', String(cs.length)); pon2('p-vis', cs.length + ' visibles');
          cs.forEach(function (c) {
            var e = estadoDe(c), cb = cobId[c.id] || 0, pv = proxDe[c.id];
            var estr = tipoC(c.tipo);
            if (c.contrato_padre_id && porId[c.contrato_padre_id]) estr += ' · cuelga de ' + porId[c.contrato_padre_id].numero;
            var hijos = cs.filter(function (h) { return h.contrato_padre_id === c.id; });
            if (hijos.length) estr += ' · encadena ' + hijos.map(function (h) { return h.numero; }).join(', ');
            fila(pl, [c.numero, c.comprador_nombre || '—', (c.proyecto_nombre || '—') + (c.parcela_codigo ? ' · ' + c.parcela_codigo : ''), estr,
              c.precio_total != null ? fmt(c.precio_total, c.moneda) : '—',
              fmt(cb, c.moneda) + (c.precio_total ? ' (' + Math.round(cb / Number(c.precio_total) * 100) + ' %)' : ''),
              pv ? fFecha(pv.fecha) + (pv.descripcion ? ' · ' + pv.descripcion : '') : (c.bloqueado && !esPreliminar(c) ? 'sin hitos futuros' : '—'),
              '', '']);
            var tr = pl.tbody.lastElementChild;
            tr.setAttribute('data-lw-fila', ''); tr.setAttribute('data-lw-id', c.id);
            tr.setAttribute('data-lw-estado', e); tr.setAttribute('data-lw-proyecto', c.proyecto_nombre || '');
            tr.setAttribute('data-lw-pajar', [c.numero, c.comprador_nombre, c.proyecto_nombre, c.parcela_codigo, tipoC(c.tipo)].join(' ').toLowerCase());
            var tds = tr.querySelectorAll('td');
            // Legal (19-sep): una reserva firmada sin señal cobrada bloquea parcela sin contraprestación; un
            // «sin importe» solo es legítimo en un poder — en el resto es un precio que falta
            var etq = ETQ[e];
            if (e === 'reserva' && !(cb > 0)) etq = ['Reserva firmada · sin señal cobrada', 'mal'];
            if (e === 'sinimporte' && c.tipo !== 'poa') etq = ['Firmado · falta precio', 'espera'];
            if (tds[7]) tds[7].innerHTML = pill(etq[0], etq[1]);
            if (tds[8]) tds[8].innerHTML = ABRIR;
            tr.style.cursor = 'pointer';
          });
          pl.tbody.addEventListener('click', function (ev) {
            var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
            ev.stopPropagation();
            var c = porId[tr.getAttribute('data-lw-id')]; if (!c) return;
            pintaExpediente(c);
            fichaContrato(sb, c, { sinExpediente: true });
          });

          var estado = {}, texto = '';
          var aplicar = function () {
            aplicaFiltros(pl.tbody, estado, ['estado', 'proyecto'], texto, function (n) { pon2('p-desde', String(n)); pon2('p-vis', n + ' visibles'); });
          };
          var ops = [{ clave: '*', texto: 'Todas', n: cs.length }];
          ['curso', 'firma', 'pendiente', 'cobrado', 'reserva'].forEach(function (k) { ops.push({ clave: k, texto: ETQ[k][0], n: nEst[k] }); });
          var contChips = document.querySelector('[data-lw-chips="estado"]');
          chipsReales(contChips, 'estado', ops, estado, aplicar);
          buscadorDe(aplicar, function (v) { texto = v; });
          // el selector de «territorio» del diseño pasa a filtrar por proyecto REAL
          var sel = document.querySelector('main select');
          if (sel) {
            var proys = {}; cs.forEach(function (c) { if (c.proyecto_nombre) proys[c.proyecto_nombre] = (proys[c.proyecto_nombre] || 0) + 1; });
            sel.innerHTML = '<option value="*">Todos los proyectos</option>' + Object.keys(proys).sort().map(function (p) { return '<option value="' + esc(p) + '">' + esc(p) + ' (' + proys[p] + ')</option>'; }).join('');
            sel.setAttribute('data-real', '');
            sel.addEventListener('change', function () { estado.proyecto = { attr: 'proyecto', valor: sel.value }; aplicar(); });
          }
          // ?filtro=firma (enlace de Home «contratos en firma»)
          var filtro = new URLSearchParams(location.search).get('filtro');
          if (filtro && contChips) {
            var idx = ['*', 'curso', 'firma', 'pendiente', 'cobrado', 'reserva'].indexOf(filtro);
            var bs = contChips.querySelectorAll('button'); if (idx > 0 && bs[idx]) bs[idx].click();
          }
        }

        /* --- EXPEDIENTE (panel lateral): ?contrato= o el más reciente. El «notario
           con acta» y el «cobro SWIFT» del diseño eran inventados: el timeline real
           son los vencimientos del contrato, y la estructura encadenada es la de
           verdad (contrato_padre_id), con el cobrado de cada pieza. */
        var hitosVig = null;
        var closerVig = null;
        function pintaExpediente(el) {
          var raiz = el.contrato_padre_id ? (porId[el.contrato_padre_id] || el) : el;
          var hijos = cs.filter(function (c) { return c.contrato_padre_id === raiz.id; });
          pon2('x-id', el === raiz ? 'Expediente' : 'Expediente · abierto desde ' + el.numero);
          pon2('x-num', raiz.numero); pon2('x-h2', raiz.numero);
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
          pon2('x-mas', hijos.length > 1 ? 'La cadena tiene ' + hijos.length + ' contratos colgando; aquí se enseña el primero. Los demás, en la ficha de ' + raiz.numero + '.' : '');

          /* Closer (21-sep-2026): SIEMPRE sobre la raíz (`raiz`, nunca `el`) —
             el motor de comisiones solo lee `contrato_closer` de ahí. Mismo
             candado y misma fuente de datos que la sección gemela de
             fichaContrato() más abajo en este fichero: closerPuede() /
             closerDatos() / closerOpcionesHtml() / closerGuardar(). */
          var closerBloque = document.querySelector('[data-lw="closer-bloque"]');
          var closerSel = document.querySelector('[data-lw="x-closer-sel"]');
          if (closerBloque && closerSel) {
            if (!closerPuede()) {
              closerBloque.hidden = true;
            } else {
              closerBloque.hidden = false;
              closerSel.onchange = null;
              closerSel.disabled = true;
              closerSel.innerHTML = '<option>Cargando…</option>';
              var pedidoC = raiz.id;
              closerVig = pedidoC;
              closerDatos(sb).then(function (d) {
                if (closerVig !== pedidoC) return; // se cambió de expediente mientras llegaba
                var actual = d.map[raiz.id];
                if (actual === undefined) {
                  closerSel.innerHTML = '<option value="">— no aplica (sin firmar/sin precio) —</option>';
                  closerSel.disabled = true;
                  return;
                }
                closerSel.innerHTML = closerOpcionesHtml(d.equipo, actual);
                closerSel.setAttribute('data-lw-closer-sel', raiz.id);
                closerSel.setAttribute('data-previo', actual || '');
                closerSel.disabled = false;
                closerSel.onchange = function () { closerGuardar(sb, closerSel); };
              });
            }
          }

          var pedido2 = el;
          sb.from('contrato_vencimientos').select('descripcion,pct,monto,fecha,nota').eq('contrato_id', el.id).order('fecha', { ascending: true, nullsFirst: false }).limit(3)
            .then(function (rv) {
              if (rv.error || hitosVig !== pedido2) return;
              var vs2 = rv.data || [];
              for (var i2 = 0; i2 < 3; i2++) {
                var v = vs2[i2];
                pon2('h' + (i2 + 1) + '-t', v ? (v.descripcion || 'Hito ' + (i2 + 1)) : '—');
                pon2('h' + (i2 + 1) + '-s', v ? (v.monto ? fmt(v.monto, el.moneda) : (v.pct ? v.pct + ' %' : (v.nota || '—'))) : 'sin más hitos');
                pon2('h' + (i2 + 1) + '-f', v ? (v.fecha ? fFecha(v.fecha) : 'sin fecha') : '');
              }
            });
          hitosVig = pedido2;
          expedienteActual = { el: el, raiz: raiz };
        }
        var expedienteActual = null;
        var pedido = new URLSearchParams(location.search).get('contrato');
        var el0 = cs.filter(function (c) { return c.numero === pedido; })[0] || cs[0];
        if (!el0) return;
        pintaExpediente(el0);
        if (pedido && el0.numero === pedido) fichaContrato(sb, el0, { sinExpediente: true });

        // los botones del panel llevan a las herramientas reales, siempre sobre el expediente que se ve
        var botones = document.querySelectorAll('button');
        for (var i3 = 0; i3 < botones.length; i3++) {
          var tx = (botones[i3].textContent || '').trim(), ico = botones[i3].querySelector('.material-symbols-outlined');
          if (/Emitir recib/i.test(tx)) {
            botones[i3].setAttribute('data-real', '');
            // UUID y tipo, no el número: ver la nota de fichaContrato (19-sep-2026)
            botones[i3].addEventListener('click', function (ev) {
              ev.stopPropagation(); if (!expedienteActual) return;
              if (window.LW_V4 && window.LW_V4.abrirEditorRecibi) window.LW_V4.abrirEditorRecibi({ contrato_id: expedienteActual.el.id });
              else toastMal('El editor de recibís aún está cargando — prueba de nuevo en un segundo.');
            });
          } else if (/proforma encadenada|Abrir proforma/i.test(tx)) {
            botones[i3].setAttribute('data-real', '');
            botones[i3].addEventListener('click', function (ev) { ev.stopPropagation(); if (expedienteActual) location.href = '/contracts/app.html?contrato=' + encodeURIComponent(expedienteActual.raiz.id); });
          } else if (ico && ico.textContent.trim() === 'open_in_new' && tx === 'open_in_new') {
            botones[i3].setAttribute('data-real', ''); botones[i3].title = 'Ficha del expediente';
            botones[i3].addEventListener('click', function (ev) { ev.stopPropagation(); if (expedienteActual) fichaContrato(sb, expedienteActual.el, { sinExpediente: true }); });
          } else if (/Actualizar$/i.test(tx)) {
            botones[i3].setAttribute('data-real', '');
            botones[i3].addEventListener('click', function (ev) { ev.stopPropagation(); location.reload(); });
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
        /* La tarjeta del diseño era «Saldo en escrow notarial»: la suite no lleva
           el saldo del notario, lleva lo COBRADO (recibís), que no es lo mismo.
           Se enseña eso, que sí es un dato (19-sep-2026). */
        var cobradoCartera = 0;
        cs.forEach(function (c) { if (c.bloqueado && (c.moneda || 'EUR') === mon) cobradoCartera += cobradoPorId[c.id] || 0; });
        pon2('k-cobrado', fmt(cobradoCartera, mon));
        pon2('k-cobrado-pie', 'recibís de contratos firmados en ' + mon);
        // «Exportar previsión de caja»: CSV de la cascada que esta pantalla ya tiene en memoria
        var bExp = botonConTexto(/Exportar previsi/i);
        if (bExp) {
          bExp.setAttribute('data-real', '');
          bExp.addEventListener('click', function (ev) {
            ev.stopPropagation();
            var filas = m.filas.filter(function (f) { return f.estado !== 'cobrado'; })
              .sort(function (a, b) { return (a.fecha || '9999') < (b.fecha || '9999') ? -1 : 1; })
              .map(function (f) {
                return [f.fecha || 'sin fecha', f.descripcion || 'Hito', f.contrato.numero, tipoC(f.contrato.tipo), f.contrato.proyecto_nombre || '', f.contrato.comprador_nombre || '',
                  f.importe != null ? f.importe : '', f.pendiente != null ? f.pendiente : '', mon, f.estado, f.contrato.bloqueado ? 'firmado' : 'borrador'];
              });
            exportaCSV('prevision_caja_' + hoy + '.csv', ['Fecha', 'Hito', 'Contrato', 'Tipo', 'Proyecto', 'Comprador', 'Importe', 'Pendiente', 'Moneda', 'Estado', 'Contrato firmado'], filas);
          });
        }

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
            fila2.addEventListener('click', function () { fichaContrato(sb, f.contrato); });   // la ficha del contrato, en el cajón
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
      /* Estado del PROYECTO (17-sep-2026, encargo del owner) — ocho valores,
         distintos de los seis de una parcela: aquellos dicen si una parcela se
         puede vender, estos en qué punto de su vida está el proyecto entero.
         Se pintan con la misma familia de color que las parcelas para que la
         pantalla siga leyéndose igual, no con una paleta nueva.
         El estado NO se deriva de nada: lo pone una persona con
         proyecto_cambiar_estado(), y solo `en_construccion` habilita el disparo
         de vencimientos por avance de obra. */
      var PROY_ESTADO_COLOR = {
        en_venta: '#485B37',        // verde territorial — vivo, se está vendiendo
        no_disponible: '#75786e',   // outline — fuera de comercialización
        en_construccion: '#8C5E10', // ámbar — la obra está en marcha (y cobrando)
        construido: '#316669',      // secondary — obra terminada, sin entregar
        finalizado: '#104C4F',      // deep lagoon — entregado y cerrado
        gestionado: '#316669',      // en explotación
        stand_by: '#8A6A34',        // pausado
        cedido: '#75786e'           // ya no es nuestro
      };
      var PROY_ESTADO_ETIQUETA = {
        en_venta: 'En venta', no_disponible: 'No disponible',
        en_construccion: 'En construcción', construido: 'Construido',
        finalizado: 'Finalizado', gestionado: 'Gestionado',
        stand_by: 'Stand-by', cedido: 'Cedido'
      };
      function claveEstado(e) { return String(e || '').trim().toLowerCase().replace(/\s+/g, '_'); }
      function colorEstado(e) { return ESTADO_COLOR[claveEstado(e)] || '#75786e'; }
      function etiquetaEstado(e) { return ESTADO_ETIQUETA[claveEstado(e)] || (e || '—'); }
      function colorProyEstado(e) { return PROY_ESTADO_COLOR[claveEstado(e)] || '#75786e'; }
      function etiquetaProyEstado(e) { return PROY_ESTADO_ETIQUETA[claveEstado(e)] || (e || '—'); }

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
        volverAProyecto();   // por si quedaba abierta la vista de detalle de OTRO proyecto
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

        /* Estado del proyecto, umbral para iniciar obra y plazos de cobro
           (17-sep-2026, encargo del owner). Tres cosas que hasta hoy no existían
           en `proyectos`.

           El porcentaje vendido NO se recalcula aquí: sale de la RPC
           `proyecto_pct_vendido`, que cuenta vendida+cobrada+BLOQUEADA. Es a
           propósito un número distinto del KPI «vendidas» de esta misma
           pantalla (que cuenta solo ventas consumadas): aquel responde cuántas
           ventas hemos cerrado, éste si hay compromiso contractual suficiente
           para levantar la obra. Contarlo a mano aquí sería la tercera
           implementación del mismo criterio, que es exactamente como se rompen
           estas cosas. */
        var elEstado = document.querySelector('[data-lw="d-estado"]');
        if (elEstado) {
          elEstado.textContent = etiquetaProyEstado(elegido.estado);
          elEstado.style.background = colorProyEstado(elegido.estado);
          elEstado.style.color = '#fff';
        }

        pon('d-umbral', '—');
        vig(sb.rpc('proyecto_pct_vendido', { p_proyecto_id: elegido.id })).then(function (r) {
          if (r.error) { fallo('porcentaje vendido', r.error); return; }
          var pct = Number(r.data);
          var umbral = Number(elegido.pct_minimo_inicio);
          if (!isFinite(pct) || !isFinite(umbral)) return;
          var el = document.querySelector('[data-lw="d-umbral"]');
          if (!el) return;
          var llega = pct >= umbral;
          el.textContent = pct.toFixed(1).replace('.0', '') + '% de ' + umbral + '%' +
            (llega ? ' · puede iniciar obra' : '');
          // Ámbar, no rojo: no llegar al umbral no es un error, es el estado
          // normal de un proyecto que todavía se está vendiendo.
          el.style.color = llega ? '#485B37' : '#8A6A34';
        });

        /* Los cinco plazos de cobro, si están configurados. Sin configurar no es
           un fallo: es lo que hay hasta que alguien los fije, y obra_confirmar_avance
           lo dice con su propio mensaje si hace falta uno que no existe. */
        pon('d-plazos', '—');
        q(sb.from('proyecto_plazo_pago').select('orden_pago,dias')
            .eq('proyecto_id', elegido.id).order('orden_pago'), 'plazos de cobro')
          .then(function (pl) {
            var el = document.querySelector('[data-lw="d-plazos"]');
            if (!el) return;
            if (pl == null) { el.textContent = 'no se pudieron leer'; return; }
            if (!pl.length) { el.textContent = 'sin configurar'; el.style.color = '#8A6A34'; return; }
            el.style.color = '';
            el.textContent = pl.map(function (x) { return x.dias + 'd'; }).join(' · ') +
              (pl.length < 5 ? ' · faltan ' + (5 - pl.length) : '');
          });

        /* Fecha de entrega ESTIMADA del proyecto (16-sep-2026, encargo del
           owner), NO la fecha real de obra por parcela (unidades.obra_fecha_entrega,
           distinta). Sin tratamiento alarmante, solo honesto: una estimación de
           más de ~6 meses sin revisar se marca aparte, porque un dato volátil
           que envejece en silencio es justo lo que la casa pide evitar. */
        var elEntrega = document.querySelector('[data-lw="d-entrega"]');
        if (elEntrega) {
          if (!elegido.fecha_entrega_estimada_proyecto) {
            elEntrega.textContent = 'sin estimar';
            elEntrega.style.color = '';
          } else {
            var fEntrega = fTrimestre(elegido.fecha_entrega_estimada_proyecto);
            var vieja = false;
            if (elegido.fecha_entrega_estimada_fijada_en) {
              var meses = (Date.now() - new Date(elegido.fecha_entrega_estimada_fijada_en + 'T00:00:00').getTime()) / (1000 * 60 * 60 * 24 * 30.44);
              vieja = meses >= 6;
            }
            elEntrega.textContent = fEntrega + (vieja ? ' · estimación antigua' : '');
            elEntrega.style.color = vieja ? '#8A6A34' : '';
          }
        }

        /* Desglose de parcelas por estado, DENTRO del cajón de un proyecto
           (16-sep-2026, revisión previa Desarrollo/Diseño/Datos): reutiliza
           d.porEstado, la misma agregación que ya alimenta los chips globales
           de arriba — sin consulta nueva. Estado vacío propio si el proyecto
           no tiene parcelas, en vez de pintar tres ceros sin contexto. */
        var cajaResumen = document.querySelector('[data-lw="d-resumen-estados"]');
        var vacioResumen = document.querySelector('[data-lw="d-resumen-vacio"]');
        if (cajaResumen && vacioResumen) {
          if (!d.t) {
            cajaResumen.innerHTML = ''; cajaResumen.classList.add('hidden');
            vacioResumen.classList.remove('hidden');
          } else {
            vacioResumen.classList.add('hidden');
            cajaResumen.classList.remove('hidden');
            var porEstado = d.porEstado || {};
            cajaResumen.innerHTML = Object.keys(ESTADO_ETIQUETA).map(function (clave) {
              var n = porEstado[clave] || 0;
              if (!n) return '';
              return '<span style="display:inline-flex;align-items:center;gap:5px;font:600 11px sans-serif;color:#44483f">' +
                '<span style="width:7px;height:7px;border-radius:999px;flex:0 0 auto;background:' + colorEstado(clave) + '"></span>' +
                n + ' ' + etiquetaEstado(clave).toLowerCase() + '</span>';
            }).join('');
          }
        }

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
            // `codigo_orden` (16-sep-2026): orden NATURAL calculado por la base (columna
            // generada de `unidades`). `.order('codigo')` era orden de texto —SH-10 antes
            // que SH-2— y con `.limit(60)` sobre 228 parcelas Postgres devolvía las 60
            // primeras EN ESE orden: la SH-2 no llegaba y el cajón decía «60 unidades».
            // El límite es una red (el mayor proyecto tiene 228), no un tamaño de página.
            .eq('proyecto', elegido.nombre).order('codigo_orden').limit(500), 'unidades de ' + elegido.nombre)
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
            var barraUnidad = function (f, clave, cartera, cobrado, firmado, moneda) {
              var firmPct = cartera ? (firmado ? 100 : 0) : 0;
              /* `cobrado_suelo`/`cobrado_obra` llegan NULL cuando el contrato no es
                 visible para quien consulta (migración 20260916093309, LAW-186
                 mitad B). Eso no es «0,00 cobrado»: es «no he podido mirar», y se
                 dice así — como hace la herramienta viva («no visible — el
                 contrato no es tuyo»). Pintar 0 aquí era mentir (19-sep-2026). */
              var noVisible = cartera && cobrado == null;
              var cobPct = (cartera && !noVisible) ? Math.min(100, (Number(cobrado) || 0) / cartera * 100) : 0;
              var elCob = f.querySelector('[data-barra="u-' + clave + '-cobrado"]');
              var elFir = f.querySelector('[data-barra="u-' + clave + '-firmado"]');
              if (elCob) elCob.style.width = cobPct + '%';
              if (elFir) elFir.style.width = Math.max(0, firmPct - cobPct) + '%';
              /* 21-sep-2026: esto pintaba SIEMPRE "EUR" sin mirar `moneda` — las
                 diez parcelas de Riverfront (en IDR de verdad, ver migración
                 20260826124756) se leían como "2.759.500.000,00 EUR". Ahora se
                 respeta la moneda real y, si no es EUR, se añade el estimado en
                 € al lado (fmtConEstimado, arriba). */
              pon('u-' + clave + '-txt', !cartera ? 'sin cartera'
                : noVisible ? 'cobro no visible · ' + fmtConEstimado(cartera, moneda)
                : fmtConEstimado(cobrado, moneda) + ' / ' + fmtConEstimado(cartera, moneda), f);
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
              pon('u-total', fmtConEstimado(u.precio, u.moneda), f);
              // Enlaces directos a la ficha del comprador y al contrato
              // (11-sep-2026, encargo del owner). Sin ficha/contrato detrás no
              // se pone href — un enlace a "#" es peor que texto sin subrayar.
              var elC = f.querySelector('[data-lw="u-comprador-link"]');
              if (elC) {
                elC.textContent = u.comprador_nombre || '—';
                var clienteId = u.contrato_id ? COMPRADOR_ID_POR_CONTRATO[u.contrato_id] : null;
                if (clienteId) { elC.href = '/intranet/v4/compradores/?id=' + clienteId; elC.target = '_blank'; }
                else { elC.removeAttribute('href'); elC.removeAttribute('target'); elC.style.cursor = 'default'; elC.style.textDecoration = 'none'; }
              }
              var elK = f.querySelector('[data-lw="u-contrato-link"]');
              if (elK) {
                elK.textContent = u.contrato_numero || 'sin contrato';
                if (u.contrato_numero) { elK.href = '/intranet/v4/contratos/?contrato=' + encodeURIComponent(u.contrato_numero); elK.target = '_blank'; }
                else { elK.removeAttribute('href'); elK.removeAttribute('target'); elK.style.cursor = 'default'; elK.style.textDecoration = 'none'; }
              }
              barraUnidad(f, 'suelo', Number(u.precio_suelo) || 0, u.cobrado_suelo, !!u.contrato_firmado, u.moneda);
              barraUnidad(f, 'obra', Number(u.precio_construccion) || 0, u.cobrado_obra, !!u.obra_firmada, u.moneda);
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
          history.replaceState(null, '', u2.href);
        }
      }
      window.LW_V4 = window.LW_V4 || {}; window.LW_V4.abrirProyecto = abrirCajon;
      /* Lo que el editor del parcelario necesita de esta pantalla, y nada
         más: las unidades pintadas y el color/nombre de cada estado, para
         que el formulario enseñe el MISMO código de color que la lista. */
      window.LW_V4.unidades = UNIDADES_CAJON;
      window.LW_V4.estadoColor = colorEstado;
      window.LW_V4.estadoEtiqueta = etiquetaEstado;
      // Estados de PROYECTO para el editor (modal "Estado y obra"), misma
      // razón que los de parcela: fuente única, no dos listas a mano.
      window.LW_V4.proyEstados = PROY_ESTADO_ETIQUETA;
      window.LW_V4.proyEstadoEtiqueta = etiquetaProyEstado;

      /* Vista de detalle de UNA parcela, DENTRO del mismo cajón — patrón
         maestro→detalle, no un cajón anidado (Diseño, revisión previa
         16-sep-2026). Reutiliza la fila ya cacheada en UNIDADES_CAJON: la
         misma consulta `unidades_estado` que pinta la tarjeta compacta ya
         trae fase_masterplan/zona_masterplan/cobrado_suelo/cobrado_obra, así
         que no hace falta un fetch nuevo para "ver más detalle". */
      function abrirDetalleUnidad(id) {
        var u = UNIDADES_CAJON[id];
        if (!u) return;
        var vp = document.getElementById('cajon-vista-proyecto');
        var vd = document.getElementById('cajon-vista-parcela');
        if (!vp || !vd) return;
        pon('dp-proyecto', u.proyecto || 'este proyecto');
        pon('dp-codigo', u.codigo || '—');
        var nota = document.querySelector('[data-lw="dp-nota"]');
        if (nota) { nota.textContent = etiquetaEstado(u.estado).toUpperCase(); nota.style.background = colorEstado(u.estado); }
        pon('dp-tipo', u.modelo || '—');
        pon('dp-agente', u.contrato_creado_por ? (EQUIPO_NOMBRE[u.contrato_creado_por] || u.contrato_creado_por) : '—');
        var elC = document.querySelector('[data-lw="dp-comprador-link"]');
        if (elC) {
          elC.textContent = u.comprador_nombre || '—';
          var clienteId = u.contrato_id ? COMPRADOR_ID_POR_CONTRATO[u.contrato_id] : null;
          if (clienteId) { elC.href = '/intranet/v4/compradores/?id=' + clienteId; elC.target = '_blank'; }
          else { elC.removeAttribute('href'); elC.removeAttribute('target'); elC.style.cursor = 'default'; elC.style.textDecoration = 'none'; }
        }
        var elK = document.querySelector('[data-lw="dp-contrato-link"]');
        if (elK) {
          elK.textContent = u.contrato_numero || 'sin contrato';
          if (u.contrato_numero) { elK.href = '/intranet/v4/contratos/?contrato=' + encodeURIComponent(u.contrato_numero); elK.target = '_blank'; }
          else { elK.removeAttribute('href'); elK.removeAttribute('target'); elK.style.cursor = 'default'; elK.style.textDecoration = 'none'; }
        }
        pon('dp-superficie', u.superficie_m2 != null ? Number(u.superficie_m2).toLocaleString('es-ES') + ' m²' : '—');
        // fase_masterplan/zona_masterplan (sector del PLANO) — no confundir con
        // obra_fase (catálogo obra_fases, avance de CONSTRUCCIÓN): son dos
        // conceptos distintos, ver hallazgo de Desarrollo en la revisión previa.
        pon('dp-fase-zona', (u.fase_masterplan || u.zona_masterplan)
          ? [u.fase_masterplan ? 'Fase ' + u.fase_masterplan : null, u.zona_masterplan ? 'Zona ' + u.zona_masterplan : null].filter(Boolean).join(' · ')
          : 'sin registrar');
        pon('dp-total', u.precio != null ? fmt(u.precio, u.moneda || 'EUR') : '—');
        pon('dp-suelo', u.precio_suelo != null ? fmt(u.precio_suelo, u.moneda || 'EUR') + (u.cobrado_suelo == null ? ' · cobro no visible' : ' · cobrado ' + fmt(u.cobrado_suelo, u.moneda || 'EUR')) : '—');
        pon('dp-suelo-m2', (u.precio_suelo != null && u.superficie_m2) ? fmt(u.precio_suelo / u.superficie_m2, u.moneda || 'EUR') + '/m²' : '—');
        pon('dp-obra', u.precio_construccion != null ? fmt(u.precio_construccion, u.moneda || 'EUR') + (u.cobrado_obra == null ? ' · cobro no visible' : ' · cobrado ' + fmt(u.cobrado_obra, u.moneda || 'EUR')) : 'sin construcción asociada');
        vp.classList.add('hidden');
        vd.classList.remove('hidden');
        var cuerpo = vd.closest('.overflow-y-auto');
        if (cuerpo) cuerpo.scrollTop = 0;
      }
      function volverAProyecto() {
        var vp = document.getElementById('cajon-vista-proyecto');
        var vd = document.getElementById('cajon-vista-parcela');
        if (vd) vd.classList.add('hidden');
        if (vp) vp.classList.remove('hidden');
      }
      window.LW_V4.abrirDetalleUnidad = abrirDetalleUnidad;
      var cajaUnidadesClic = document.getElementById('d-unidades');
      if (cajaUnidadesClic) cajaUnidadesClic.addEventListener('click', function (ev) {
        // El lápiz de editar y los enlaces a comprador/contrato tienen su
        // propio comportamiento (editores.js escucha el mismo contenedor) —
        // aquí se descartan explícitamente para no abrir el detalle A LA VEZ.
        if (ev.target.closest('[data-lw-accion="editar-unidad"]') || ev.target.closest('a')) return;
        var tarjeta = ev.target.closest('[data-lw-accion="abrir-detalle-unidad"]');
        if (!tarjeta) return;
        var bEd = tarjeta.querySelector('[data-lw-accion="editar-unidad"]');
        var uid = bEd && bEd.getAttribute('data-uid');
        if (uid) abrirDetalleUnidad(uid);
      });
      var cajonDetalleClic = document.getElementById('cajon-detalle');
      if (cajonDetalleClic) cajonDetalleClic.addEventListener('click', function (ev) {
        if (ev.target.closest('[data-lw-accion="volver-a-proyecto"]')) volverAProyecto();
      });
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
        q(sb.from('proyectos').select('id,nombre,resort,parcela_master,parcela_master_m2,fecha_entrega_estimada_proyecto,fecha_entrega_estimada_fijada_en,estado,pct_minimo_inicio').eq('activo', true).order('nombre'), 'proyectos'),
        q(sb.from('unidades').select('proyecto,estado,moneda,precio,precio_suelo,precio_construccion'), 'unidades'),
        /* La RPC de EQUIPO, nunca `.from('facturas')`. `facturas` tiene RLS por
           agente (`es_suyo`), así que una lectura directa devuelve solo «lo mío»
           —menos filas, sin ningún error— y el cobrado de la cartera saldría
           bajo para todo el que no sea super admin. Está avisado en la cabecera
           de este fichero y aun así caí en ello al escribir esta pantalla. */
        q(sb.rpc('facturas_equipo').select('proyecto_id,proyecto_nombre,tipo,total,moneda,anulada'), 'facturas'),
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
        /* NOMBRE_POR_PROYECTO_ID (18-sep-2026): una factura/recibí que cuelga de
           un contrato con parcela_codigo se guarda con `proyecto_nombre` tipo
           "Soka Village W2 — B1" (intranet/facturas/index.html, campo "Proyecto
           / unidad" — correcto para el propio recibí, identifica la parcela).
           Sumar por ese texto exacto contra el nombre limpio del proyecto deja
           fuera cualquier recibí con sufijo de parcela: el sumario general
           enseñaba solo el dinero de las facturas SIN parcela vinculada,
           aunque hubiera cobros reales de sobra. `proyecto_id` no lleva sufijo
           nunca, así que es la clave de verdad. */
        var NOMBRE_POR_PROYECTO_ID = {};
        ps.forEach(function (p) { NOMBRE_POR_PROYECTO_ID[p.id] = p.nombre; });

        /* --- agregados, TODO EN EUR --- (21-sep-2026, encargo del owner: las
           unidades en IDR de Riverfront I/II se convierten a un estimado en €
           y entran en la misma suma, en vez de desaparecer de la cartera como
           antes — `fueraEstimado` cuenta cuántas son estimado, no cuántas se
           pierden. Una moneda SIN tasa de conversión (si apareciera USD/AUD)
           sigue fuera de la suma y de `fueraEstimado`: inventar una tasa para
           esa sí sería mentir sin que nadie lo haya pedido. */
        var tot = { cartera: 0, suelo: 0, obra: 0 }, fueraEstimado = 0, fueraSinTasa = 0;
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
          var moneda = u.moneda || 'EUR';
          var factor = moneda === 'EUR' ? 1 : (moneda === 'IDR' ? (1 / TASA_IDR_EUR_ESTIMADA) : null);
          if (factor == null) { fueraSinTasa++; return; }
          if (moneda !== 'EUR') fueraEstimado++;
          var precioEur = Number(u.precio || 0) * factor, sueloEur = Number(u.precio_suelo || 0) * factor, obraEur = Number(u.precio_construccion || 0) * factor;
          tot.cartera += precioEur; tot.suelo += sueloEur; tot.obra += obraEur;
          d.cartera += precioEur;
          d.suelo += sueloEur; d.obra += obraEur;
        });
        var cobrado = 0, facturado = 0;
        COB_P = {};
        fs.forEach(function (f) {
          if (f.anulada || (f.moneda || 'EUR') !== 'EUR') return;
          if (f.tipo === 'recibi') { cobrado += Number(f.total || 0); var k = NOMBRE_POR_PROYECTO_ID[f.proyecto_id] || f.proyecto_nombre || ''; COB_P[k] = (COB_P[k] || 0) + Number(f.total || 0); }
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
        // un párrafo). Ampliada 21-sep-2026: ahora dice también cuántas
        // unidades entran convertidas (estimado, no precio real) y, si
        // aparece una moneda sin tasa, que se quedó fuera de verdad.
        pon('k-cartera-pie', 'Volumen en ' + ps.length + ' desarrollos activos'
          + (fueraEstimado ? ' · incluye ' + fueraEstimado + ' unidad(es) en IDR convertida(s) a € (estimado, tasa del ' + TASA_IDR_EUR_ESTIMADA_FECHA + ')' : '')
          + (fueraSinTasa ? ' · ' + fueraSinTasa + ' unidad(es) sin tasa de conversión quedan fuera' : ''));
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
        var bExp = botonConTexto(/Exportar cat[aá]logo/i);
        if (bExp) {
          bExp.setAttribute('data-real', '');
          bExp.addEventListener('click', function (ev) {
            ev.stopPropagation();
            exportaCSV('catalogo_modelos.csv',
              ['Modelo', 'Slug', 'Dormitorios', 'Baños', 'Villa m²', 'Terraza m²', 'Precio construcción', 'Moneda', 'Publicado', 'Activo', 'Renders pendientes', 'Unidades enlazadas'],
              ms.map(function (m) { return [m.nombre, m.slug, m.dormitorios, m.banos, m.villa_m2, m.terraza_m2, m.precio_construccion, m.moneda, m.publicado ? 'sí' : 'no', m.activo ? 'sí' : 'no', m.renders_pendientes ? 'sí' : 'no', porModelo[m.id] || 0]; }));
          });
        }

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
        q(sb.from('unidades_estado').select('codigo,modelo,estado,contrato_numero,comprador_nombre').eq('proyecto', nombre).order('codigo_orden').limit(500), 'unidades de ' + nombre)
          .then(function (us) {
            if (us == null) return;
            panelReal('Unidades de ' + nombre + (pedido ? '' : ' (primer proyecto por orden — abre otro con ?proyecto=)'),
              us.map(function (u) {
                return itemPanel(esc(u.codigo) + ' · ' + esc(u.modelo || '—'),
                  (u.contrato_numero ? esc(u.contrato_numero) + ' · ' : '') + esc(u.comprador_nombre || 'sin comprador'),
                  (u.estado || '—').toUpperCase());
              }),
              us.map(function () { return '/intranet/v4/proyectos/?proyecto=' + encodeURIComponent(nombre); }),
              'Este proyecto no tiene unidades dadas de alta.', '/intranet/v4/proyectos/?proyecto=' + encodeURIComponent(nombre));
          });
      });
    },

    obra: function (sb) {
      /* Reescrito 18-sep-2026 (encargo del owner: "limpia lo que no sea un
         dato real, cablea hasta el final"). El HTML de Stitch traia dron,
         peritajes con firma digital y 82.000 € de escrow, ensayos de
         laboratorio, un calendario con ingenieros nombrados y una cuadrilla
         con supervisor nombrado — nada de eso existe en la base y se retiro
         del marcado (no solo del cableado). Lo que la suite SÍ guarda: fase +
         fecha de entrega por unidad, y desde el 17-sep el avance por
         fase-zona con partes de trabajo (obra_partes_trabajo) que además fija
         la fecha de cobro. Verificado en Supabase el 18-sep: los tres viven
         hoy a cero filas — ningún proyecto ha pasado a 'en_construccion'
         todavía —, así que el estado correcto de esta pantalla es un vacío
         honesto, no actividad inventada.

         `k-po` cuenta el CATÁLOGO (`proyectos.estado`), no una tabla
         derivada: contar "proyectos distintos con alguna unidad con fase"
         perdería un proyecto recién pasado a construcción que aún no tiene
         ningún parte — el mismo fallo, ya cazado dos veces en esta suite, de
         agrupar por la fila que todavía no existe. */
      Promise.all([
        q(sb.from('unidades_estado').select('codigo,proyecto,modelo,estado,obra_fase,obra_fecha_entrega,obra_actualizado,comprador_nombre').not('obra_fase', 'is', null).order('obra_actualizado', { ascending: false }).limit(60), 'unidades en obra'),
        q(sb.from('proyectos').select('id,nombre,estado').order('nombre'), 'proyectos'),
        cnt(sb, 'unidades_estado', function (qq) { return qq.not('obra_fecha_entrega', 'is', null); }),
        cnt(sb, 'obra_partes_trabajo'),
        q(sb.from('obra_partes_trabajo').select('fase_masterplan,zona_masterplan,fase_anterior,fase_nueva,fecha,autor,nota,dias_offset,proyecto_id').order('creado_en', { ascending: false }).limit(6), 'últimos partes de trabajo'),
        q(sb.from('obra_fases').select('clave,es').order('orden'), 'fases de obra')
      ]).then(function (r) {
        var us = r[0], proys = r[1] || [], nEntregas = r[2], nPartes = r[3], ultimosPartes = r[4], fases = r[5];
        if (us == null) return;

        var enConstruccion = proys.filter(function (p) { return p.estado === 'en_construccion'; });
        pon2('k-po', String(enConstruccion.length));
        pon2('k-po-pie', enConstruccion.length
          ? enConstruccion.map(function (p) { return p.nombre; }).slice(0, 3).join(', ')
          : 'ningún proyecto en construcción todavía');

        pon2('k-hitos', nEntregas == null ? '—' : String(nEntregas));
        pon2('k-hitos-pie', 'unidades con fecha de entrega puesta');

        pon2('k-partes', nPartes == null ? '—' : String(nPartes));

        var nombreFase = {}; (fases || []).forEach(function (f) { nombreFase[f.clave] = f.es || f.clave; });
        var nombreProy = {}; proys.forEach(function (p) { nombreProy[p.id] = p.nombre; });

        var hoy = new Date().toISOString().slice(0, 10);
        var conFecha = us.filter(function (u) { return u.obra_fecha_entrega && u.obra_fecha_entrega >= hoy; })
          .sort(function (a, b) { return a.obra_fecha_entrega < b.obra_fecha_entrega ? -1 : 1; });
        if (conFecha.length) {
          var sgu = conFecha[0];
          var d = Math.round((new Date(sgu.obra_fecha_entrega) - new Date(hoy)) / 864e5);
          pon2('sig-titulo', 'Entrega ' + sgu.codigo);
          pon2('sig-sub', (sgu.proyecto || '—') + ' · ' + fFecha(sgu.obra_fecha_entrega));
          pon2('sig-chip', 'en ' + d + (d === 1 ? ' día' : ' días'));
          pon2('sig-prio', nombreFase[sgu.obra_fase] || sgu.obra_fase || '—');
        } else {
          pon2('sig-titulo', 'Sin entregas con fecha futura');
          pon2('sig-sub', '—'); pon2('sig-chip', '—'); pon2('sig-prio', '—');
        }

        pintaListaObra('unidades-obra', us.map(function (u) {
          return itemPanel(esc(u.codigo) + ' · ' + esc(u.proyecto || '—'),
            esc(u.modelo || '—') + ' · ' + esc(u.comprador_nombre || 'sin comprador') + ' · entrega ' + fFecha(u.obra_fecha_entrega),
            esc(nombreFase[u.obra_fase] || u.obra_fase || '—'));
        }), 'Ninguna unidad con fase de obra abierta todavía. Se abre una desde «Registrar avance técnico».', '/intranet/obra/');

        pintaListaObra('proximas-entregas', conFecha.slice(0, 5).map(function (u) {
          return itemPanel(esc(u.codigo) + ' · ' + esc(u.proyecto || '—'), fFecha(u.obra_fecha_entrega), '');
        }), 'Ninguna unidad con fecha de entrega futura.', '/intranet/obra/');

        pintaListaObra('partes-trabajo', (ultimosPartes || []).map(function (p) {
          // itemPanel mete lo que se le da en innerHTML sin escapar: todo lo
          // que sale de la base pasa por esc() (el repo es publico y una
          // zona o un autor son texto libre).
          return itemPanel(
            esc((nombreProy[p.proyecto_id] || '—') + ' · fase ' + p.fase_masterplan + ' · ' + p.zona_masterplan),
            esc((p.fase_anterior ? p.fase_anterior + ' → ' : 'arranca en ') + p.fase_nueva +
              ' · ' + fFecha(p.fecha) + (p.autor ? ' · ' + p.autor : '')),
            p.dias_offset != null ? 'cobro +' + Number(p.dias_offset) + 'd' : '');
        }), 'Todavía no hay ningún parte de trabajo. Se crean desde «Nuevo parte de trabajo».');
      });
    },
    /* documentacion/: fusionada en Proyectos el 8-sep (decision del owner).
       La pagina es una redireccion; no queda nada que cablear aqui. */
    creatividades: function () {
      bandaNota('Creatividades y dossiers no viven en la base de datos: el catálogo real está en /intranet/creatividades/ — los botones de esta pantalla te llevan allí', '#485B37');
    },

    usuarios: function (sb) {
      /* Listado, FICHA EN CAJON y auditoria reales. La ficha sale de
         `usuarios.*` — la lista real que gobierna el guard — y la auditoria de
         la tabla `notificaciones` (hechos escritos por triggers). Las IPs y el
         2FA del diseno no existen en la suite: fuera.

         18-sep-2026, owner: «prefiero que al clickar en un agente se me abra un
         cajeton lateral». Hasta hoy la pantalla tenia un panel fijo a la
         derecha («Rol activo inspeccionado») con cuatro permisos del primer
         usuario de la lista — nadie sabia de quien hablaba ni por que de ese.
         Se retira: todo lo que decia, y lo que no decia (proyectos, tipos de
         contrato, alta), vive ahora en el cajon de cada fila. Y los dos KPIs
         que se quedaban en «—» (notarial, 2FA) con una banda excusandolos se
         cambian por dos que la base SI sabe: administradores y cuentas
         inactivas. */
      var t = tablaPor([/NOMBRE|USUARIO/, /ROL|HERRAMIENTAS/]);
      Promise.all([
        q(sb.from('usuarios').select('user_id,nombre,email,rol,activo,herramientas,proyectos,proyectos_supervisados,tipos_contrato,creado_en,creado_por').order('nombre'), 'usuarios', t),
        /* `enlace` es lo que hace que la auditoria sea navegable (owner: «que
           tenga enlaces vivos linkables»): la campana viva ya lo usa, aqui
           se leia solo el titulo. 30 y no 8: los que sobran de 6 se pliegan
           bajo «ver mas», sin segunda consulta. */
        q(sb.from('notificaciones').select('titulo,detalle,enlace,creado_en').order('creado_en', { ascending: false }).limit(30), 'auditoría'),
        // nombres de proyecto para la ficha: `usuarios.proyectos` guarda ids
        q(sb.from('proyectos').select('id,nombre'), 'proyectos')
      ]).then(function (r) {
        var us = r[0], ns = r[1] || [], proys = r[2] || [];
        if (!us) return;
        var nombreProy = {}; proys.forEach(function (p) { nombreProy[p.id] = p.nombre; });
        var act = us.filter(function (u) { return u.activo; });
        var esAdminRol = function (u) { return u.rol === 'admin' || u.rol === 'super_admin'; };
        pon2('k-usuarios', String(act.length));
        pon2('k-usuarios-pie', us.length + (us.length === 1 ? ' usuario' : ' usuarios') + ' dados de alta · pulsa uno para abrir su ficha');
        var roles = {}; us.forEach(function (u) { if (u.rol) roles[u.rol] = 1; });
        pon2('k-roles', String(Object.keys(roles).length));
        pon2('k-admins', String(act.filter(esAdminRol).length));
        pon2('k-inactivos', String(us.length - act.length));

        // ETIQ_ROL vive en editores.js (una sola lista de roles): se lee, no se copia
        var rolDe = function (u) {
          var E = (window.LW_V4 && window.LW_V4.ETIQ_ROL) || {};
          return E[u.rol] || u.rol || '—';
        };
        var nombresProy = function (ids) { return (ids || []).map(function (id) { return nombreProy[id] || id; }); };

        /* ---- la ficha, en el cajon compartido de editores.js ---- */
        function quitaU() {
          var u2 = new URL(location.href);
          if (u2.searchParams.has('u')) { u2.searchParams.delete('u'); history.replaceState(null, '', u2.href); }
        }
        function abreFicha(u) {
          var H = window.lwCajonHtml;
          if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.usuario = u;
          var hs = u.herramientas || [], pr = nombresProy(u.proyectos), sup = nombresProy(u.proyectos_supervisados);
          var tipos = (u.tipos_contrato || []).map(function (k) { return tipoC(k); });
          var soyAdmin = !!(window.LW_V4.esAdmin);
          var cuerpo =
            H.seccion('Cuenta',
              H.dato('Email', u.email) +
              H.dato('Rol', rolDe(u)) +
              H.dato('Estado', u.activo ? H.tag('Activo', 'ok') : H.tag('Inactivo', 'mal'), { html: 1 }) +
              H.dato('Alta', u.creado_en ? fFecha(u.creado_en) + (u.creado_por ? ' · por ' + u.creado_por : '') : null));
          /* El mapa de permisos (herramientas, proyectos, tipos) solo lo ve
             administracion: para el resto del equipo es la lista de que puede
             tocar cada admin, util solo para una cuenta comprometida (Seguridad,
             revision previa 18-sep). La policy de `usuarios` deja leerlo; esto
             es no enseñarlo. */
          if (soyAdmin) cuerpo +=
            H.seccion('Herramientas (' + hs.length + ')',
              hs.length ? H.chips(hs)
                : H.nota(u.rol === 'super_admin' ? 'Super admin: entra en todas las herramientas sin necesitar la lista.'
                                                  : 'Sin ninguna herramienta marcada: no puede abrir nada de la suite.')) +
            H.seccion('Proyectos en los que trabaja (' + pr.length + ')',
              pr.length ? H.chips(pr) : H.nota('Ninguno: no puede crear ni editar contratos en ningún proyecto.')) +
            H.seccion('Proyectos que supervisa como manager (' + sup.length + ')',
              sup.length ? H.chips(sup) : H.nota('Ninguno. Es una lista distinta de la de arriba: supervisar es ver y escribir lo del proyecto entero, no solo lo propio.')) +
            H.seccion('Contratos que puede hacer',
              tipos.length ? H.chips(tipos) : H.nota('Sin restricción: vacío = TODOS los tipos (al revés que Proyectos).'));
          var acciones = [];
          if (soyAdmin) {
            acciones.push({ texto: 'Editar permisos', tono: 'primario', onClick: function () {
              if (window.LW_V4.abreEditaUsuario) window.LW_V4.abreEditaUsuario(u);
              else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
            } });
            acciones.push({ texto: 'Cambiar contraseña', onClick: function () {
              if (window.LW_V4.abreCambiaPassword) window.LW_V4.abreCambiaPassword(u);
              else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
            } });
          } else {
            cuerpo += H.nota('Editar permisos o contraseñas es de administración: aquí solo se consulta.');
          }
          acciones.push({ texto: 'Cerrar', cerrar: true });
          window.lwCajon({ sub: 'Ficha de usuario', titulo: u.nombre || u.email || '—', bajoTitulo: u.nombre ? u.email : '',
                           cuerpo: cuerpo, acciones: acciones, alCerrar: quitaU });
          var u2 = new URL(location.href);
          u2.searchParams.set('u', u.email || '');
          history.replaceState(null, '', u2.href);
        }
        var porEmail = {}; us.forEach(function (u) { if (u.email) porEmail[u.email.toLowerCase()] = u; });

        if (t) {
          var pl = plantillaFilas(t);
          us.forEach(function (u) {
            fila(pl, [u.nombre || '—', u.email || '—', rolDe(u),
              (u.herramientas || []).length + (u.rol === 'super_admin' ? ' · todas' : ''),
              String((u.proyectos || []).length),
              u.activo ? 'ACTIVO' : 'INACTIVO', '']);
            var tr = pl.tbody.lastElementChild;
            tr.style.cursor = 'pointer';
            tr.setAttribute('data-email', u.email || '');
            tr.setAttribute('data-rol', u.rol || '');
            tr.setAttribute('data-herr', ' ' + (u.herramientas || []).join(' ') + ' ');
            tr.lastElementChild.innerHTML = '<button type="button" data-real class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px] transition-colors">Ver ficha</button>';
          });
          // una fila = una ficha; delegado porque los chips de filtro las esconden y enseñan
          pl.tbody.addEventListener('click', function (ev) {
            var tr = ev.target.closest && ev.target.closest('tr[data-email]');
            if (!tr) return;
            ev.preventDefault(); ev.stopPropagation();
            var u = porEmail[(tr.getAttribute('data-email') || '').toLowerCase()];
            if (u) abreFicha(u);
          });

          /* Los chips "Legal/Obra/Sales/Finance" del diseño de Stitch se
             renombraron el 15-sep (hallazgo de Legal): no corresponden a
             ningún valor real de `usuarios.rol` (solo existen
             super_admin/admin/agente, ver migración 20260729090521), así que
             llamarlos por un departamento inducía a leer un PERMISO de
             herramienta como si fuera la función de la persona. Ahora dicen
             qué filtran de verdad — acceso a esa herramienta. "Super Admin"
             sí es un rol real: filtra por igualdad exacta, no se mezcla con
             "admin". */
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

          // el buscador de la cabecera de la tabla: filtra por nombre, email o rol
          var busca = document.getElementById('userSearchInput');
          if (busca) busca.addEventListener('input', function () {
            var qq = busca.value.trim().toLowerCase();
            pl.tbody.querySelectorAll('tr[data-email]').forEach(function (tr) {
              tr.style.display = (!qq || tr.textContent.toLowerCase().indexOf(qq) !== -1) ? '' : 'none';
            });
          });
        }

        // ?u= abre la ficha directamente — es lo que hace que «Guardar permisos»
        // (que recarga la página) vuelva a la misma ficha, y lo que permite
        // enlazar a un usuario desde otra pantalla.
        var pedido = new URLSearchParams(location.search).get('u');
        var el = pedido ? porEmail[pedido.toLowerCase()] : null;
        if (el) setTimeout(function () { abreFicha(el); }, 0);

        /* ---- auditoria: hechos de `notificaciones`, con su enlace ---- */
        var caja = document.getElementById('auditoria');
        var mas = document.getElementById('lw-audit-mas');
        if (caja) {
          if (!ns.length) {
            caja.innerHTML = '<p class="text-body-sm text-on-surface-variant">Sin hechos registrados todavía.</p>';
          } else {
            caja.innerHTML = ns.map(function (nx, i) {
              var titulo = esc(nx.titulo || 'Hecho');
              /* Solo rutas propias: `//evil.com` y `/\evil.com` tambien empiezan por
                 «/» y el navegador los abre fuera (hallazgo ALTA de Seguridad en la
                 revision previa, 18-sep). Un http(s) solo si es este mismo origen. */
              var enlace = null;
              if (nx.enlace && /^\/(?![\/\\])/.test(nx.enlace)) enlace = nx.enlace;
              else if (nx.enlace && nx.enlace.indexOf(location.origin + '/') === 0) enlace = nx.enlace;
              return '<div class="flex items-start gap-3"' + (i >= 6 ? ' data-audit-mas hidden' : '') + '>' +
                '<div class="w-2 h-2 rounded-full ' + (enlace ? 'bg-deep-lagoon' : 'bg-stone-sand') + ' mt-1.5 shrink-0"></div>' +
                '<div class="flex flex-col min-w-0">' +
                (enlace
                  ? '<a href="' + esc(enlace) + '" class="text-body-sm text-deep-lagoon font-medium hover:underline">' + titulo + '</a>'
                  : '<span class="text-body-sm text-volcanic-ash font-medium">' + titulo + '</span>') +
                '<div class="flex items-center gap-2 text-stone-sand text-[11px] mt-0.5"><span>' + esc(nx.detalle || '') + '</span>' +
                (nx.detalle ? '<span>•</span>' : '') + '<span>' + esc(fFecha(nx.creado_en)) + '</span></div></div></div>';
            }).join('');
          }
          if (mas) {
            var ocultos = caja.querySelectorAll('[data-audit-mas]').length;
            if (ocultos) {
              mas.hidden = false;
              mas.textContent = 'Ver ' + ocultos + ' hechos anteriores';
              mas.addEventListener('click', function (ev) {
                ev.stopPropagation();
                caja.querySelectorAll('[data-audit-mas]').forEach(function (e) { e.hidden = false; });
                mas.hidden = true;
              });
            }
          }
        }

        /* El botón de cabecera «Registro de auditoría» llevaba a Operaciones
           (resto de un mapeo de Stitch, 21-sep-2026): esta misma pantalla YA
           tiene el registro real ahí abajo. Lleva ahí en vez de navegar. */
        var btnAudit = document.getElementById('btnAuditLog');
        var tarjetaAudit = document.getElementById('lwAuditCard');
        if (btnAudit && tarjetaAudit) btnAudit.addEventListener('click', function () {
          tarjetaAudit.scrollIntoView({ behavior: 'smooth', block: 'center' });
          tarjetaAudit.style.transition = 'box-shadow .25s ease';
          tarjetaAudit.style.boxShadow = '0 0 0 3px rgba(16,76,79,.35)';
          setTimeout(function () { tarjetaAudit.style.boxShadow = ''; }, 1200);
        });
      });
    },
    soporte: function (sb) {
      /* Bandeja y conversacion REALES (fase A2, 8-sep). hilo_soporte no guarda
         asunto, prioridad ni agente asignado — eso era del diseno. El asunto es
         el ultimo mensaje del hilo y la prioridad se sustituye por la categoria.
         Responder es fase C: va por la RPC portal_enviar_mensaje y cada mensaje
         dispara un email real al comprador, asi que aqui NI SE TOCA. */
      Promise.all([
        // sin `limit`: la viva carga todos los hilos y aquí 80 → 25 pintados dejaba
        // tickets fuera sin decirlo (auditoría 19-sep-2026)
        q(sb.from('hilo_soporte').select('id,client_id,categoria,estado,actualizado_en').order('actualizado_en', { ascending: false }), 'hilos'),
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
        /* Las tres tarjetas del diseño («Tiempo medio de respuesta», «Canal
           WhatsApp», «Satisfacción») median cosas que la suite no guarda y se
           quedaban en «—» con una banda explicándolo. Se cambian por tres que sí
           salen de la base (19-sep-2026): en espera, sin responder y resueltos. */
        var resueltos = hs.filter(function (h) { return /resuelt|cerrad/.test(h.estado || ''); });
        var sinResp = hs.filter(function (h) {
          var u = ultimo[h.id] || ultimo[h.client_id];
          return h.estado === 'abierto' && u && u.de !== 'equipo';   // el último mensaje lo escribió el comprador
        });
        pon2('k-espera', String(espera.length));
        pon2('k-espera-pie', espera.length ? 'marcados en espera de un tercero' : 'ningún hilo en espera');
        pon2('k-sinresp', String(sinResp.length));
        pon2('k-sinresp-pie', sinResp.length ? 'abiertos cuyo último mensaje es del comprador' : 'ningún hilo abierto espera respuesta del equipo');
        pon2('k-resueltos', String(resueltos.length));
        pon2('k-resueltos-pie', 'de ' + hs.length + ' hilos en total');
        pon2('c-todos', 'Todos (' + hs.length + ')');
        pon2('c-abiertos', 'Abiertos (' + abiertos.length + ')');
        pon2('c-espera', 'En espera (' + espera.length + ')');
        pon2('c-resueltos', 'Resueltos (' + resueltos.length + ')');
        pon2('n-hilos', abiertos.length + ' activos');

        var lista = document.getElementById('lista-hilos');
        if (!lista || !lista.firstElementChild) { console.info('[v4] soporte: sin molde'); return; }
        var molde = lista.firstElementChild.cloneNode(true);
        lista.innerHTML = '';
        if (!hs.length) {
          lista.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0;padding:6px 2px">Ningún hilo de soporte todavía.</p>';
        }
        hs.forEach(function (h) {
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
          f.setAttribute('data-lw-pajar', [c.full_name, c.email, h.categoria, u && u.texto].join(' ').toLowerCase());
          f.style.cursor = 'pointer';
          f.addEventListener('click', function () { location.search = '?hilo=' + encodeURIComponent(h.id); });
          lista.appendChild(f);
        });

        // buscador vivo sobre la bandeja (nombre, email, categoría y último mensaje)
        var inpS = document.querySelector('main input[placeholder^="Buscar"]');
        if (inpS) inpS.addEventListener('input', function () {
          var v = inpS.value.trim().toLowerCase();
          Array.prototype.forEach.call(lista.querySelectorAll('[data-estado-hilo]'), function (x) {
            x.style.display = (!v || (x.getAttribute('data-lw-pajar') || '').indexOf(v) !== -1) ? '' : 'none';
          });
        });
        var chipsSoporte = ['todos', 'abiertos', 'espera', 'resueltos'].map(function (k) {
          var sp = document.querySelector('[data-lw="c-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);
        cablearChipsFiltro(chipsSoporte, lista, '[data-estado-hilo]',
          function (btn) { return btn.getAttribute('data-chip-clave'); },
          'todos',
          function (fila, clave) {
            var e = fila.getAttribute('data-estado-hilo') || '';
            return clave === 'abiertos' ? e === 'abierto' : clave === 'resueltos' ? /resuelt|cerrad/.test(e) : /espera/.test(e);
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
          if (/Ver perfil/.test(t2)) enlaces[i2].href = '/intranet/v4/compradores/?id=' + el.client_id;
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
    /* generador-contratos y contratos-inversor eran diseños sin datos: desde el
       19-sep-2026 redirigen a la herramienta viva (como leads/), sin handler. */
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
        // TODAS las filas, como la viva (/intranet/solicitudes/): los chips contaban
        // sobre todas pero filtraban sobre las 25 pintadas (auditoría 19-sep-2026).
        tabla.innerHTML = ss.map(function (x) {
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

  /* ---------- Cuentas de cobro y su reparto ----------
     Esta pantalla decide ADONDE TRANSFIERE EL COMPRADOR, asi que lee el
     catalogo completo y no un recorte:

     🔴 18-sep-2026 — leia `plantillas_pago`, que NO es «las plantillas que
     cobran». Es la vista puente del 14-sep y su cuerpo entero es
     `SELECT slug, nombre, orden FROM plantillas_contrato`: SIN filtro. Con eso
     la tarjeta «Documentos que cobran» decia 20 cuando cobran 8, la tabla
     listaba los 15 tipos que el owner archivo justamente para quitar morralla,
     y «Sin cuenta marcada» daba 11 documentos mudos donde los 11 eran
     `cobra = false` — documentos que no llevan datos bancarios y por tanto no
     tienen ningun desplegable que llenar. Las once alarmas eran falsas y la
     unica cifra que importaba (contratos que COBRAN y no ofrecen ninguna
     cuenta) quedaba enterrada entre ellas.

     Ahora se lee `plantillas_contrato` con `cobra` y `archivada`, que es lo
     que hace /intranet/cuentas/ desde el 14-sep. La vista puente sigue en pie
     para `contracts/assets/entities.js` (retirarla es LAW-206). */
  REG.cuentas = function (sb) {
    var tbody = document.getElementById('lw-reparto');
    var cajaRep = tbody ? tbody.closest('section') : null;
    var tbodyProy = document.getElementById('lw-reparto-proyecto');
    var cajaProy = tbodyProy ? tbodyProy.closest('section') : null;
    var tbodyCu = document.getElementById('lw-reparto-cuenta');
    var cajaCu = document.getElementById('lw-cuentas');

    /* Las dos RPC son EXTRAS y estan gateadas a super admin en la base: a un
       admin normal le devuelven vacio, que es correcto (tampoco puede cambiar
       nada). Por eso no pasan por `q()`: un `fallo()` pintaria la seccion en
       rojo por no tener una cifra de adorno.

       Pero devuelve **null si no se pudo leer** y `[]` si de verdad no hay nada:
       «no he podido mirarlo» y «no se usa» se parecen mucho en pantalla y solo
       una es cierta. Sin esa distincion, el aviso rojo «esta cuenta esta en N
       contratos, y N ya FIRMADOS» desaparecia sin dejar rastro cuando la RPC
       fallaba, y se editaba el titular o el numero de una cuenta impresa en
       contratos firmados sin ver la advertencia. La herramienta viva ya degrada
       asi (/intranet/cuentas/, lineas 207-234). Cazado por Desarrollo en la
       consulta de deploy del 18-sep. */
    function qSuave(p) {
      return vig(p).then(function (r) { return (r && r.error) ? null : ((r && r.data) || []); },
                         function () { return null; });
    }

    function carga() {
      return Promise.all([
        /* `es_escrow` es una COLUMNA, no el prefijo `notario_` de la clave: la
           convencion de nombre valia mientras las cuentas nacian por SQL.
           Se piden TODAS, activas y no: este panel es justo donde hay que ver
           —y poder reactivar— una desactivada. Y se piden los campos enteros
           porque el editor de `editores.js` los rellena desde aqui, sin una
           segunda consulta. */
        q(sb.from('cuentas_bancarias')
            .select('clave,label,titular,banco,cuenta,codigo,direccion,extra,orden,activa,es_escrow,actualizado_en')
            .order('orden'), 'cuentas bancarias', cajaCu),
        q(sb.from('plantillas_contrato').select('slug,nombre,orden,cobra,archivada').order('orden'), 'tipos de contrato', cajaRep),
        q(sb.from('plantilla_cuentas').select('slug,clave,es_default'), 'reparto por contrato'),
        q(sb.from('proyecto_cuentas').select('proyecto_id,slug,clave,es_default'), 'reparto por proyecto', cajaProy),
        /* Falta desde el 14-sep (14-sep añadió proyecto_cuentas pero nunca trajo
           `proyectos`, así que «Por proyecto» no tenía con qué pintar filas —
           era la mitad que faltaba de las tres pestañas). */
        q(sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre'), 'proyectos', cajaProy),
        qSuave(sb.rpc('cuentas_uso')),
        qSuave(sb.rpc('plantillas_uso'))
      ]).then(function (r) { pinta(r[0], r[1], r[2], r[3], r[4], r[5], r[6]); });
    }

    function pinta(cus, pls, rep, repProy, proys, usoCu, usoTi) {
      if (!cus || !pls || !rep) return;

      var porClave = {};
      cus.forEach(function (c) { porClave[c.clave] = c; });
      var activas = cus.filter(function (c) { return c.activa; });
      var escrow = cus.filter(function (c) { return c.es_escrow; });
      var cobran = pls.filter(function (p) { return p.cobra; });
      var archivadas = pls.filter(function (p) { return p.archivada; });

      var porSlug = {};
      rep.forEach(function (x) { (porSlug[x.slug] = porSlug[x.slug] || []).push(x); });

      /* Lo emitido con cada cuenta, y lo emitido de cada tipo. `plantillas_uso`
         viene indexada por TIPO y no por slug (`reserva_parcela` vs
         `ppjb_parcela`), y quien traduce es `TIPO_SLUG` de vocabulario.js —
         el mismo mapa que usa /intranet/cuentas/, no una copia. */
      var USO = usoCu === null ? null : {};
      (usoCu || []).forEach(function (u) { USO[u.clave] = u; });
      var USO_TIPO = usoTi === null ? null : {};
      (usoTi || []).forEach(function (u) {
        var s = (typeof TIPO_SLUG !== 'undefined' && TIPO_SLUG[u.tipo]) || u.tipo;
        if (USO_TIPO) USO_TIPO[s] = u;
      });

      /* La alarma de verdad: un documento que COBRA, se sigue ofreciendo al
         crear un contrato y no tiene ninguna cuenta marcada — el agente lo abre
         y se encuentra vacío el desplegable donde va el destino del dinero. Los
         que no cobran no tienen desplegable, y los archivados ya no se ofrecen:
         ni unos ni otros son una alarma. */
      var mudos = cobran.filter(function (p) { return !p.archivada && !(porSlug[p.slug] || []).length; });
      var etiqueta = function (x) { var c = porClave[x.clave]; return c ? (c.label || c.clave) : x.clave; };

      pon2('k-activas', String(activas.length));
      pon2('k-total', String(cus.length));
      pon2('k-activas-pie', (cus.length - activas.length) + ' dadas de baja');
      pon2('k-plantillas', String(cobran.length));
      pon2('k-plantillas-pie', 'de ' + pls.length + ' tipos en el catálogo · ' + archivadas.length + ' archivados');
      pon2('k-huerfanas', String(mudos.length));
      pon2('k-huerfanas-pie', mudos.length
        ? mudos.slice(0, 3).map(function (p) { return p.nombre; }).join(' · ')
        : 'ningún documento vivo se queda sin cuenta');
      pon2('k-escrow', String(escrow.length));
      pon2('k-escrow-pie', escrow.length ? 'declaradas por columna, no por nombre' : 'ninguna marcada');

      var tag = function (txt, clase) {
        return '<span class="ml-2 text-[11px] uppercase tracking-wider ' + (clase || 'text-outline') + '">' + esc(txt) + '</span>';
      };
      var btnEditar = function (attr, valor, extra) {
        return '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
          attr + '="' + esc(valor) + '"' + (extra || '') + '>Editar</button>';
      };
      var vacia = function (cols, txt) {
        return '<tr><td colspan="' + cols + '" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">' + esc(txt) + '</td></tr>';
      };

      // ---------- Por contrato ----------
      if (tbody) {
        tbody.innerHTML = !pls.length ? vacia(5, 'Ningún tipo de contrato registrado.') : pls.map(function (p) {
          var filas = porSlug[p.slug] || [];
          var def = filas.filter(function (x) { return x.es_default; })[0];
          var u = USO_TIPO && USO_TIPO[p.slug];
          var ofrece = !p.cobra
            ? '<span class="text-outline">no lleva cuenta de cobro</span>'
            : (filas.length
                ? esc(filas.map(etiqueta).join(' · '))
                : '<span class="text-error">sin cuenta marcada</span>');
          return '<tr class="border-b border-outline-variant/30' + (p.archivada ? ' opacity-60' : '') + '">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(p.nombre || p.slug) +
              (p.archivada ? tag('archivado') : '') + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + ofrece + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' +
              (!p.cobra ? '—' : def ? esc(etiqueta(def)) : 'sin precargada') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline text-right">' +
              (u ? esc(u.contratos + ' · ' + u.firmados + ' firmados')
                 : (USO_TIPO === null ? '<span class="text-error">sin cifra</span>' : 'sin usar')) + '</td>' +
            '<td class="px-5 py-4 text-right">' + btnEditar('data-lw-cu-contrato', p.slug) + '</td></tr>';
        }).join('');
      }

      /* ---------- Por proyecto ----------
         `slug === '*'` es el mismo TODOS de /intranet/cuentas/ (vocabulario.js
         no lo exporta como constante, es un literal de esa pantalla): la
         excepción vale para cualquier tipo de contrato del proyecto. «Hereda»
         es el estado normal y sano, no una falta de configurar — con 1 sola
         fila en `proyecto_cuentas` hoy, casi todos los proyectos van a decir
         «hereda», y eso es correcto. */
      if (tbodyProy) {
        var nombrePl = {};
        pls.forEach(function (p) { nombrePl[p.slug] = p.nombre || p.slug; });
        tbodyProy.innerHTML = proys === null
          ? vacia(4, 'No se pudo leer el catálogo de proyectos.')
          : (!proys.length ? vacia(4, 'Ningún proyecto activo.') : proys.map(function (p) {
              var reglas = (repProy || []).filter(function (x) { return x.proyecto_id === p.id; });
              var vistos = {}, tipos = [];
              reglas.forEach(function (x) {
                var t2 = x.slug === '*' ? 'cualquier contrato' : (nombrePl[x.slug] || x.slug);
                if (!vistos[t2]) { vistos[t2] = 1; tipos.push(t2); }
              });
              return '<tr class="border-b border-outline-variant/30">' +
                '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(p.nombre) + '</td>' +
                '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' +
                  (reglas.length ? esc(tipos.join(' · ')) : '<span class="text-outline">hereda el reparto general</span>') + '</td>' +
                '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + (reglas.length ? String(reglas.length) : '—') + '</td>' +
                '<td class="px-5 py-4 text-right">' + btnEditar('data-lw-cu-proyecto', p.id, ' data-lw-etq="' + esc(p.nombre) + '"') + '</td></tr>';
            }).join(''));
      }

      // ---------- Por cuenta ----------
      if (tbodyCu) {
        tbodyCu.innerHTML = !cus.length ? vacia(5, 'Ninguna cuenta dada de alta.') : cus.map(function (c) {
          /* Ojo (hallazgo de Administración en la consulta de deploy,
             15-sep): "se ofrece en" tiene que sumar las DOS fuentes del
             reparto, no solo `rep` (plantilla_cuentas). Una cuenta atada
             SOLO por una excepción de `proyecto_cuentas` (por ejemplo un
             notario propio de un proyecto) seguía saliendo "ninguno"
             aunque estuviera en uso real — quien mirase esta tabla para
             decidir qué cuenta dar de baja podía desactivar una que un
             comprador de ese proyecto sigue viendo en su documento. */
          var usos = rep.filter(function (x) { return x.clave === c.clave; }).length +
                     (repProy || []).filter(function (x) { return x.clave === c.clave; }).length;
          var u = USO && USO[c.clave];
          return '<tr class="border-b border-outline-variant/30' + (c.activa ? '' : ' opacity-60') + '">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(c.label || c.clave) +
              (c.es_escrow ? tag('escrow', 'text-burnt-earth') : '') + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' +
              (usos ? esc(usos + (usos === 1 ? ' documento' : ' documentos')) : '<span class="text-outline">ninguno</span>') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + (c.activa ? 'activa' : 'de baja') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-right ' + (u && u.firmados ? 'text-error' : 'text-outline') + '">' +
              (u && u.contratos ? esc(u.contratos + ' · ' + u.firmados + ' firmados')
                 : (USO === null ? '<span class="text-error">sin cifra</span>' : '—')) + '</td>' +
            '<td class="px-5 py-4 text-right">' + btnEditar('data-lw-cu-cuenta', c.clave) + '</td></tr>';
        }).join('');
      }

      if (cajaCu) {
        cajaCu.innerHTML = cus.length
          ? cus.map(function (c) {
              return itemPanel(esc(c.label || c.clave) + (c.es_escrow ? ' · escrow' : ''),
                               esc([c.banco, c.cuenta].filter(Boolean).join(' — ') || '—'),
                               c.activa ? 'activa' : 'de baja');
            }).join('')
          : '<p style="font:400 13px \'Neue Kabel\',sans-serif;color:#44483f;margin:0">Ninguna cuenta dada de alta.</p>';
      }

      /* Lo que el editor necesita de esta pantalla, publicado igual que
         `window.LW_V4.unidades` en /v4/proyectos/: los datos ya leidos (para no
         volver a consultarlos al abrir un cajon) y la RECARGA. La recarga es lo
         que evita el `location.reload()` del modal generico — aqui se guardan
         casillas sueltas y recargar la pagina entera por cada una seria perder
         la pestaña abierta y el sitio de la tabla. */
      window.LW_V4 = window.LW_V4 || {};
      window.LW_V4.cuentas = {
        cuentas: cus, plantillas: pls, reparto: rep,
        repartoProyecto: repProy || [], proyectos: proys || [],
        uso: USO, usoTipo: USO_TIPO
      };
      window.LW_V4.recargaCuentas = carga;
    }

    /* Delegado en el <tbody> estatico y ANTES de cargar: las filas se reemplazan
       enteras en cada repintado (un listener directo moriria con ellas) y
       `maqueta.js` escucha en `document`, asi que llegaria despues y anunciaria
       el boton como «sin cablear». `delega` para con stopPropagation. */
    delega(tbody,     [['data-lw-cu-contrato', 'abreRepartoContrato']]);
    delega(tbodyProy, [['data-lw-cu-proyecto', 'abreRepartoProyecto']]);
    delega(tbodyCu,   [['data-lw-cu-cuenta',   'abreEditaCuenta']]);

    carga();
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
      // el editor de miembro ofrece el equipo en un select: la lista es esta, no otra consulta
      window.LW_V4.equiposLista = equipos.map(function (e) { return [e.id, e.nombre + (e.activo ? '' : ' (de baja)')]; });
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
            '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-edita-equipo="' + esc(e.id) + '" data-lw-nombre="' + esc(e.nombre) + '" data-lw-manager="' + esc(e.manager_email || '') + '">Editar</button>' +
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
            '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-2">' +
            '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-edita-miembro="' + esc(m.id) + '" data-lw-equipo="' + esc(m.equipo_id) + '" data-lw-email="' + esc(m.closer_email) + '" data-lw-desde="' + esc(m.desde || '') + '" data-lw-hasta="' + esc(m.hasta || '') + '">Editar</button>' +
            (activo
              ? '<button type="button" class="px-3 py-1 rounded-full text-error hover:bg-error-container/40 font-label-md text-[12px]" data-lw-baja="' + esc(m.id) + '" data-lw-email="' + esc(m.closer_email) + '">Dar de baja</button>'
              : '') + '</div></td></tr>';
        }).join('') : '<tr><td colspan="6" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Sin miembros para este filtro.</td></tr>';
      }
      pintaMiembros();
      if (selEq) selEq.addEventListener('change', pintaMiembros);

      // acciones — delegadas, con stopPropagation para ganar a maqueta.js (Regla 0)
      if (cuerpoEq) cuerpoEq.addEventListener('click', function (ev) {
        var bE = ev.target.closest && ev.target.closest('[data-lw-edita-equipo]');
        if (bE) {
          ev.preventDefault(); ev.stopPropagation();
          if (window.LW_V4 && window.LW_V4.abreEditaEquipo) window.LW_V4.abreEditaEquipo(bE);
          else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
          return;
        }
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
        var bE = ev.target.closest && ev.target.closest('[data-lw-edita-miembro]');
        if (bE) {
          ev.preventDefault(); ev.stopPropagation();
          if (window.LW_V4 && window.LW_V4.abreEditaMiembro) window.LW_V4.abreEditaMiembro(bE);
          else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
          return;
        }
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
      window.LW_V4.condicionesLista = {}; conds.forEach(function (c) { window.LW_V4.condicionesLista[c.id] = c; });

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
            '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-2"><button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
              'data-lw-toggle-cond="' + esc(c.id) + '" data-lw-etq="' + esc((equipoDe[c.equipo_id] || '') + ' · ' + (proyectoDe[c.proyecto_id] || '')) + '" data-lw-activo="' + (c.activo ? '1' : '0') + '">' +
              (c.activo ? 'Desactivar' : 'Reactivar') + '</button>' +
              /* Borrar solo la que ya esta desactivada (Seguridad, revision previa
                 18-sep): una activa puede estar aplicandose a contratos firmados
                 sin devengo todavia, y borrarla se llevaria sus tramos sin rastro.
                 Primero se desactiva —que deja de aplicarse— y entonces se borra. */
              (c.activo ? '' :
              '<button type="button" class="px-3 py-1 rounded-full text-error hover:bg-error-container/40 font-label-md text-[12px]" ' +
              'data-lw-borra-cond="' + esc(c.id) + '" data-lw-etq="' + esc((equipoDe[c.equipo_id] || '') + ' · ' + (proyectoDe[c.proyecto_id] || '')) + '">Borrar</button>') +
              '</div></td></tr>';
        }).join('') : '<tr><td colspan="7" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Ninguna condición para este filtro.</td></tr>';
      }
      pinta();
      if (selEquipo) selEquipo.addEventListener('change', pinta);
      if (selProyecto) selProyecto.addEventListener('change', pinta);

      if (cuerpo) cuerpo.addEventListener('click', function (ev) {
        var bB = ev.target.closest && ev.target.closest('[data-lw-borra-cond]');
        if (bB) {
          ev.preventDefault(); ev.stopPropagation();
          if (window.LW_V4 && window.LW_V4.abreBorraCondicion) window.LW_V4.abreBorraCondicion(bB);
          else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
          return;
        }
        var b = ev.target.closest && ev.target.closest('[data-lw-toggle-cond]');
        if (!b) return;
        ev.preventDefault(); ev.stopPropagation();
        if (window.LW_V4 && window.LW_V4.abreToggleCondicion) {
          window.LW_V4.abreToggleCondicion(b.getAttribute('data-lw-toggle-cond'), b.getAttribute('data-lw-etq'), b.getAttribute('data-lw-activo') === '1');
        } else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
      });
    });
  };

  /* ---------- Comisión de administración ----------
     Un porcentaje sobre todo el dinero que entra por la intranet. No tiene nada
     que ver con la comisión del equipo de ventas, que vive en «Comisiones».
     Pantalla de lectura: TODOS los importes los calcula un disparador de la base
     sobre cada recibí, y el grant de `comision_admin_lineas` para `authenticated`
     es solo SELECT + UPDATE de (estado, nota, revisar) — desde aquí es IMPOSIBLE
     tocar base, pct o importe aunque alguien lo intente por consola. Anular una
     comisión y editar una tarifa van por RPC, porque las dos hacen algo más que
     escribir una columna: una emite el abono si ya estaba facturada, y la otra
     guarda la versión anterior de la tarifa antes de pisarla. */
  REG['comision-admin'] = function (sb) {
    /* Super admin, no admin: la RLS de las dos tablas exige `es_super_admin()`,
       asi que un admin normal veria la pantalla montarse y todas las consultas
       devolver vacio — que se lee como «no hay nada» y no como «no es para ti». */
    if (!(window.LW_V4 && window.LW_V4.esSuperAdmin)) { notaSoloAdmin(); return; }

    var cuerpoTar = document.getElementById('lw-ca-tarifas');
    var cuerpoLin = document.getElementById('lw-ca-lineas');
    var cuerpoSoc = document.getElementById('lw-ca-sociedades');
    var selProy   = document.getElementById('lw-ca-proyecto');
    var selSoc    = document.getElementById('lw-ca-sociedad');
    var selEstado = document.getElementById('lw-ca-estado');
    var selMes    = document.getElementById('lw-ca-mes');

    /* El nombre de la sociedad sale de `SOCIEDADES` (entities.js), que desde el
       17-sep-2026 lo rellena `cargarSociedades(sb)` desde `public.sociedades` —
       ya no es un literal del fichero. Se lanza aqui sin await y se repinta al
       terminar: la pantalla no depende de ello para ser correcta, solo para
       enseñar la razon social en vez de la clave.
       `SOCIEDADES` es un const de nivel superior de ese fichero: se alcanza por
       ambito global, no por `window`. Si no ha cargado, se enseña la clave
       arreglada en vez de un hueco: `tepi_sungai` -> `Tepi Sungai`. */
    function nombreSociedad(clave) {
      if (!clave) return '(sin sociedad)';
      try {
        var soc = (typeof SOCIEDADES !== 'undefined') && SOCIEDADES[clave];
        if (soc && (soc.razon || soc.marca)) return soc.razon || soc.marca;
      } catch (e) { /* entities.js aun no ha cargado */ }
      return String(clave).replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
    }

    /* Paginador compartido de la suite (`paginacion.js`): el libro nace de una
       tabla que crece —87 lineas el primer dia— y la regla del estudio es que
       eso se decide el primer dia, no cuando molesta. Si no ha cargado, la
       tabla sale entera en vez de romperse. */
    var PAG = (typeof lwPaginador === 'function') ? lwPaginador('#lw-ca-pag') : null;
    var hoy       = new Date().toISOString().slice(0, 10);
    var mesActual = hoy.slice(0, 7);

    var ESTADOS = {
      pendiente: ['Pendiente', 'bg-surface-container-high text-on-surface-variant'],
      facturada: ['Facturada', 'bg-secondary-container text-on-secondary-container'],
      cobrada:   ['Cobrada',   'bg-primary-fixed text-on-primary-fixed'],
      exenta:    ['Exenta',    'bg-surface-container text-outline']
    };
    var TIPO_LINEA = { devengo: 'Devengo', ajuste: 'Ajuste', abono: 'Abono' };

    /* Suma POR MONEDA y nunca entre monedas: 500 EUR + 500 IDR no son «1.000
       nada». Devuelve el texto ya formateado, o «—» si no hay nada que sumar --
       un cero falso en un panel de control es peor que un hueco. */
    function sumaPorMoneda(lista) {
      var porM = {};
      lista.forEach(function (l) { porM[l.moneda] = (porM[l.moneda] || 0) + Number(l.importe || 0); });
      var claves = Object.keys(porM);
      if (!claves.length) return '—';
      return claves.sort().map(function (m) { return fmt(porM[m], m); }).join(' · ');
    }

    Promise.all([
      q(sb.from('comision_admin_tarifas').select('id,pct,efectivo_desde,nota,creado_por,created_at').order('efectivo_desde', { ascending: false }), 'tarifas de comisión', cuerpoTar),
      q(sb.from('comision_admin_lineas').select('id,tipo_linea,linea_origen_id,recibi_id,recibi_numero,sociedad,contrato_id,proyecto_id,devengado_el,fecha_recibi,base_total,moneda,pct_aplicado,importe,anulada,revisar,estado,nota').order('devengado_el', { ascending: false }), 'libro de comisión', cuerpoLin),
      q(sb.from('proyectos').select('id,nombre'), 'proyectos'),
      /* Sin `q()` a proposito: un fallo aqui NO puede tumbar la pantalla, solo
         deja el aviso de descuadres sin pintar. Con rama de rechazo propia --
         un fallo de red lanza y no devuelve `r.error`, y sin ella el
         Promise.all entero se cae y no se pinta ni el libro. */
      sb.rpc('comision_admin_descuadres')
        .then(function (r) { return r.error ? null : r.data; }, function () { return null; }),
      /* Las sociedades ya no son un literal de `entities.js`: las trae
         `cargarSociedades`. Va DENTRO del Promise.all para que la tabla ya este
         llena cuando `nombreSociedad` pinte; si no, se veria la clave cruda y
         luego saltaria sola al nombre. Un fallo aqui no tumba la pantalla: se
         cae al nombre derivado de la clave, que es legible. */
      (typeof cargarSociedades === 'function'
        ? cargarSociedades(sb).catch(function (e) { console.error('sociedades:', e); return null; })
        : null)
    ]).then(function (r) {
      var tarifas = r[0], lineas = r[1], proyectos = r[2], desc = r[3];
      /* `q()` ya ha pintado el cartel de fallo en el contenedor y ha devuelto
         null. Si siguieramos, `pinta()` lo sobrescribiria con «todavia no ha
         entrado dinero» y los KPI dirian «nada sin facturar»: una alarma rota
         que se lee igual que «todo tranquilo», que es el peor estado posible en
         un libro de dinero. Se para aqui y el cartel de fallo se queda. */
      if (!tarifas || !lineas) return;
      window.LW_V4 = window.LW_V4 || {};
      window.LW_V4.tarifas = tarifas;
      window.LW_V4.tarifaPorId = {};
      tarifas.forEach(function (t) { window.LW_V4.tarifaPorId[t.id] = t; });
      /* Las lineas, al alcance del editor: necesita la `nota` que ya tiene la
         fila para no borrarla al cambiar el estado. */
      window.LW_V4.caLineas = {};
      lineas.forEach(function (l) { window.LW_V4.caLineas[l.id] = l; });
      /* «No he podido leer los proyectos» y «esta linea no tiene proyecto» se
         veian los dos como «—». Se distinguen. */
      var proyectosRotos = !proyectos;
      proyectos = proyectos || [];

      var proyectoDe = {}; proyectos.forEach(function (p) { proyectoDe[p.id] = p.nombre; });
      var vigente = tarifas.filter(function (t) { return t.efectivo_desde <= hoy; })[0] || null;

      // ── KPIs ──────────────────────────────────────────────────────────────
      pon2('k-tarifa', vigente ? (Number(vigente.pct) + '%') : '—');
      pon2('k-tarifa-pie', vigente
        ? ('rige desde el ' + fFecha(vigente.efectivo_desde))
        : 'todavía no hay ninguna tarifa: no se está devengando nada');

      var vivas = lineas.filter(function (l) { return !l.anulada && l.estado !== 'exenta'; });
      var delMes = vivas.filter(function (l) { return (l.devengado_el || '').slice(0, 7) === mesActual; });
      pon2('k-mes', sumaPorMoneda(delMes));
      pon2('k-mes-pie', delMes.length
        ? (delMes.length + (delMes.length === 1 ? ' entrada de dinero' : ' entradas de dinero'))
        : 'ninguna entrada de dinero este mes');

      var pendientes = vivas.filter(function (l) { return l.estado === 'pendiente'; });
      pon2('k-pendiente', sumaPorMoneda(pendientes));
      pon2('k-pendiente-pie', pendientes.length ? (pendientes.length + ' líneas sin facturar') : 'nada sin facturar');

      var porRevisar = lineas.filter(function (l) { return l.revisar; });
      pon2('k-revisar', String(porRevisar.length));
      pon2('k-revisar-pie', porRevisar.length
        ? 'el recibí cambió después de facturarse, o desapareció'
        : 'ninguna línea pide una mirada');

      /* El banco de pruebas del silencio: el disparador traga sus propios fallos
         a propósito (un error calculando la comisión no puede impedir que se
         registre un cobro), así que lo que se perdería sin esto es dinero sin
         facturar. `comision_admin_descuadres()` lo recalcula desde la base. */
      var caja = document.getElementById('lw-ca-descuadres');
      if (caja && desc && !desc.sin_tarifa) {
        var avisos = [];
        if (desc.recibis_sin_linea)      avisos.push(desc.recibis_sin_linea + ' recibí(s) vivo(s) sin línea de comisión');
        if (desc.lineas_mal_calculadas)  avisos.push(desc.lineas_mal_calculadas + ' devengo(s) cuyo importe no cuadra con su base y su %');
        if (desc.devengos_con_base_cero) avisos.push(desc.devengos_con_base_cero + ' línea(s) con base 0');
        /* Los tres de abajo cubren lo que el contador del alta no veía: un recibí
           editado por fuera, y las dos rutas (anular / desanular) en las que el
           trigger se traga su propio fallo. */
        if (desc.devengos_con_base_distinta_del_recibi) avisos.push(desc.devengos_con_base_distinta_del_recibi + ' devengo(s) cuya base ya no coincide con su recibí');
        if (desc.anulados_con_devengo_vivo)             avisos.push(desc.anulados_con_devengo_vivo + ' recibí(s) anulado(s) con la comisión todavía viva');
        if (desc.vivos_con_devengo_anulado)             avisos.push(desc.vivos_con_devengo_anulado + ' recibí(s) vivo(s) con la comisión anulada (se repone desde administración)');
        if (avisos.length) {
          caja.hidden = false;
          caja.classList.add('flex');
          pon2('k-descuadres', 'Hay que mirar esto: ' + avisos.join(' · ') + '.');
        }
      }

      // ── Tarifas ───────────────────────────────────────────────────────────
      if (cuerpoTar) {
        cuerpoTar.innerHTML = tarifas.length ? tarifas.map(function (t) {
          var esVigente = vigente && t.id === vigente.id;
          var futura = t.efectivo_desde > hoy;
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(Number(t.pct)) + '%</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(fFecha(t.efectivo_desde)) + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              (esVigente ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-surface-container-high text-on-surface-variant') + '">' +
              (esVigente ? 'Vigente' : (futura ? 'Programada' : 'Histórica')) + '</span></td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(t.creado_por || '—') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline max-w-md">' + esc(t.nota || '—') + '</td>' +
            '<td class="px-5 py-4 text-right"><button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
              'data-lw-ca-tarifa="' + esc(t.id) + '">Editar</button></td></tr>';
        }).join('') : '<tr><td colspan="6" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Ninguna tarifa dada de alta: no se está devengando comisión.</td></tr>';
      }

      // ── Filtros del libro ─────────────────────────────────────────────────
      /* Una fila por sociedad: cada una es un deudor distinto y se le factura
         por separado, asi que nunca se suman entre si. Y dentro de cada una,
         por moneda, por lo mismo de siempre. Se calcula sobre TODAS las lineas
         (devengo, ajuste y abono) porque lo que se le factura a una sociedad es
         el neto, no solo los devengos. */
      function pintaSociedades() {
        if (!cuerpoSoc) return;
        var porSoc = {};
        lineas.filter(function (l) { return !l.anulada; }).forEach(function (l) {
          var k = l.sociedad || '';
          var e = porSoc[k] || (porSoc[k] = { n: 0, base: {}, com: {}, pend: {} });
          if (l.tipo_linea === 'devengo') e.n++;
          e.base[l.moneda] = (e.base[l.moneda] || 0) + Number(l.base_total || 0);
          e.com[l.moneda]  = (e.com[l.moneda]  || 0) + Number(l.importe || 0);
          if (l.estado === 'pendiente') e.pend[l.moneda] = (e.pend[l.moneda] || 0) + Number(l.importe || 0);
        });
        var claves = Object.keys(porSoc).sort();
        var porMoneda = function (m) {
          var ks = Object.keys(m);
          return ks.length ? ks.sort().map(function (x) { return fmt(m[x], x); }).join('<br>') : '—';
        };
        cuerpoSoc.innerHTML = claves.length ? claves.map(function (k) {
          var e = porSoc[k];
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(nombreSociedad(k)) + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant text-right">' + e.n + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant text-right">' + porMoneda(e.base) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface text-right">' + porMoneda(e.com) + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-burnt-earth text-right">' + porMoneda(e.pend) + '</td>' +
            '</tr>';
        }).join('') : '<tr><td colspan="5" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Todavía no hay ninguna entrada de dinero devengada.</td></tr>';
      }
      pintaSociedades();

      if (selSoc) {
        var socs = {};
        lineas.forEach(function (l) { socs[l.sociedad || ''] = 1; });
        selSoc.innerHTML = '<option value="">Todas las sociedades</option>' +
          Object.keys(socs).sort().map(function (k) {
            return '<option value="' + esc(k) + '">' + esc(nombreSociedad(k)) + '</option>';
          }).join('');
      }

      if (selProy) {
        selProy.innerHTML = '<option value="">Todos los proyectos</option>' +
          proyectos.slice().sort(function (a, b) { return (a.nombre || '').localeCompare(b.nombre || ''); })
            .map(function (p) { return '<option value="' + esc(p.id) + '">' + esc(p.nombre) + '</option>'; }).join('') +
          '<option value="__sin">(sin proyecto)</option>';
      }
      if (selMes) {
        var meses = {}; lineas.forEach(function (l) { if (l.devengado_el) meses[l.devengado_el.slice(0, 7)] = 1; });
        selMes.innerHTML = '<option value="">Todos los meses</option>' +
          Object.keys(meses).sort().reverse().map(function (m) { return '<option value="' + esc(m) + '">' + esc(m) + '</option>'; }).join('');
      }

      function pinta() {
        if (!cuerpoLin) return;
        var fp = selProy ? selProy.value : '', fe = selEstado ? selEstado.value : '',
            fm = selMes ? selMes.value : '', fs = selSoc ? selSoc.value : '';
        var lista = lineas.filter(function (l) {
          if (fp === '__sin') { if (l.proyecto_id) return false; }
          else if (fp && l.proyecto_id !== fp) return false;
          if (fs && (l.sociedad || '') !== fs) return false;
          if (fe && l.estado !== fe) return false;
          if (fm && (l.devengado_el || '').slice(0, 7) !== fm) return false;
          return true;
        });
        /* El paginador anuncia siempre el recorte («26–50 de 87») y vuelve solo
           a la pagina 1 al cambiar un filtro. Si no cargo, `pagina` no existe y
           la lista sale entera: recortada en silencio, nunca. */
        var enPantalla = PAG ? PAG.pagina(lista) : lista;

        cuerpoLin.innerHTML = enPantalla.length ? enPantalla.map(function (l) {
          var est = ESTADOS[l.estado] || [l.estado, 'bg-surface-container-high text-on-surface-variant'];
          var negativa = Number(l.importe) < 0;
          var etqTipo = l.tipo_linea === 'devengo' ? '' :
            '<br><span class="text-outline text-[11px] uppercase tracking-wider">' + esc(TIPO_LINEA[l.tipo_linea] || l.tipo_linea) + '</span>';
          var banderas = (l.anulada ? '<span class="ml-2 text-outline text-[11px] uppercase tracking-wider">anulada</span>' : '') +
                         (l.revisar ? '<span class="ml-2 text-error text-[11px] uppercase tracking-wider">revisar</span>' : '');
          /* El recibí borrado deja la línea huérfana a propósito (on delete set
             null): se enseña el número que tuvo, que es lo único que queda. */
          // 21-sep-2026: ya no navega fuera de v4 — abre el visor en cajón
          // (window.LW_V4.abreVerDocumento, wired más abajo con delegación,
          // que se registra UNA vez aunque pinta() se repinte varias).
          if (!window.__lwVerRecibiWired) {
            window.__lwVerRecibiWired = true;
            document.addEventListener('click', function (ev) {
              var a = ev.target.closest && ev.target.closest('[data-lw-ver-recibi]');
              if (!a) return;
              ev.preventDefault();
              if (window.LW_V4 && window.LW_V4.abreVerDocumento) window.LW_V4.abreVerDocumento(a.getAttribute('data-lw-ver-recibi'));
              else toastMal('El visor de documentos aún está cargando — prueba de nuevo en un segundo.');
            });
          }
          var recibi = l.recibi_id
            ? '<a class="text-deep-lagoon hover:underline" href="#" data-lw-ver-recibi="' + esc(l.recibi_id) + '">' + esc(l.recibi_numero) + '</a>'
            : esc(l.recibi_numero) + ' <span class="text-error text-[11px] uppercase tracking-wider">borrado</span>';

          return '<tr class="border-b border-outline-variant/30' + (l.anulada ? ' opacity-60' : '') + '">' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(fFecha(l.devengado_el)) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + recibi + etqTipo + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' +
              esc(!l.proyecto_id ? '(sin proyecto)'
                  : (proyectoDe[l.proyecto_id] || (proyectosRotos ? '(no se pudo leer)' : '(proyecto borrado)'))) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(nombreSociedad(l.sociedad)) + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant text-right">' + esc(fmt(l.base_total, l.moneda)) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-right ' + (negativa ? 'text-error' : 'text-on-surface') + '">' +
              esc(fmt(l.importe, l.moneda)) + '<br><span class="text-outline text-[11px]">' + esc(Number(l.pct_aplicado)) + '%</span></td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              est[1] + '">' + esc(est[0]) + '</span>' + banderas + '</td>' +
            '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-1">' + (l.anulada
              ? (l.tipo_linea === 'devengo' && l.recibi_id
                 ? '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
                   'data-lw-ca-repone="' + esc(l.id) + '" data-lw-etq="' + esc(l.recibi_numero) + '">Reponer</button>'
                 : '')
              : '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
                'data-lw-ca-estado="' + esc(l.id) + '" data-lw-etq="' + esc(l.recibi_numero) + '" data-lw-actual="' + esc(l.estado) + '">Estado</button>' +
                /* Anular SOLO el devengo: sus ajustes y abonos van detras de el y
                   se anulan con el, asi que ofrecerlo por separado invitaria a
                   dejar media serie viva. */
                (l.tipo_linea === 'devengo'
                 ? '<button type="button" class="px-3 py-1 rounded-full text-error hover:bg-error-container/40 font-label-md text-[12px]" ' +
                   'data-lw-ca-anula="' + esc(l.id) + '" data-lw-etq="' + esc(l.recibi_numero) + '" data-lw-estado="' + esc(l.estado) + '">Anular</button>'
                 : '')) +
            '</div></td></tr>';
        }).join('') : '<tr><td colspan="8" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">' +
          (lineas.length ? 'Ninguna línea para este filtro.' : 'Todavía no hay ninguna entrada de dinero en el libro.') + '</td></tr>';
      }
      pinta();
      if (PAG) PAG.alCambiar(pinta);
      [selProy, selSoc, selEstado, selMes].forEach(function (s) {
        if (s) s.addEventListener('change', function () { pinta(); pintaSociedades(); });
      });

      // acción delegada, con stopPropagation para ganar a maqueta.js (Regla 0)
      /* Una sola delegacion para todas las acciones de fila, de las dos tablas.
         `stopPropagation` para ganar a maqueta.js, que escucha en burbujeo. */
      delega(cuerpoLin, [['data-lw-ca-estado', 'abreEstadoComisionAdmin'],
                         ['data-lw-ca-anula',  'abreAnulaComisionAdmin'],
                         ['data-lw-ca-repone', 'abreReponeComisionAdmin']]);
      delega(cuerpoTar, [['data-lw-ca-tarifa', 'abreEditaTarifaComisionAdmin']]);
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

  /* ---------- Sociedades emisoras (21-sep-2026, S9) ----------
     La identidad de cada sociedad que emite un documento de Lawang: acaba
     impresa en cada contrato y cada factura. Pantalla SOLO de super_admin —
     mismo criterio y mismo motivo que Comision de administracion: lo que se
     toca aqui no es un dato de trabajo, es de quien es la firma.
     Se piden TODAS las sociedades, activas y no: la vista que filtra solo
     activas (`cargarSociedades`, entities.js) es para quien REDACTA un
     documento, no para quien administra el catalogo — aqui hace falta ver
     la desactivada para poder reactivarla. */
  REG['sociedades'] = function (sb) {
    if (!(window.LW_V4 && window.LW_V4.esSuperAdmin)) { notaSoloAdmin(); return; }

    var cuerpoLista = document.getElementById('lw-soc-lista');
    var cuerpoLog = document.getElementById('lw-soc-log');
    var selLog = document.getElementById('lw-soc-log-filtro');

    // Los mismos 7 campos que la herramienta clasica vigila en el historial:
    // los que el documento DICE. Retocar logo/folio/tinta no es identidad.
    var FISCALES = ['razon', 'marca', 'npwp', 'npwp_label', 'nib', 'domicilio', 'rep'];
    var ETIQ = {
      razon: 'Razón social', marca: 'Marca', npwp: 'Identificación fiscal',
      npwp_label: 'Etiqueta fiscal', nib: 'NIB', domicilio: 'Domicilio', rep: 'Representante'
    };
    function fFechaHora(x) {
      if (!x) return '—';
      var d = new Date(x);
      return isNaN(d) ? String(x).slice(0, 10) : d.toLocaleString('es-ES');
    }

    Promise.all([
      q(sb.from('sociedades').select('*').order('orden'), 'sociedades', cuerpoLista),
      q(sb.from('sociedades_log').select('clave,antes,accion,quien,cuando').order('cuando', { ascending: false }).limit(200), 'historial de sociedades', cuerpoLog)
    ]).then(function (r) {
      var socs = r[0], log = r[1];
      if (!socs) return;   // fallo() ya pinto el aviso en cuerpoLista

      window.LW_V4 = window.LW_V4 || {};
      window.LW_V4.sociedadesPorClave = {};
      socs.forEach(function (s) { window.LW_V4.sociedadesPorClave[s.clave] = s; });

      // ── Lista ────────────────────────────────────────────────────────
      if (cuerpoLista) {
        cuerpoLista.innerHTML = socs.length ? socs.map(function (s) {
          var npwpPendiente = s.es_indonesia !== false && !s.npwp;
          return '<tr class="border-b border-outline-variant/30' + (s.activa ? '' : ' opacity-60') + '">' +
            '<td class="px-5 py-4"><div class="flex items-center gap-2.5">' +
              '<span style="width:13px;height:13px;border-radius:2px;border:1px solid #E4DCCB;flex:none;display:inline-block;background:' + esc(s.folio || '#FFF') + '"></span>' +
              '<div><div class="font-label-md text-label-md text-on-surface">' + esc(s.razon) + '</div>' +
              '<div class="font-body-sm text-body-sm text-outline">' + esc(s.marca || s.label || '—') + '</div></div>' +
            '</div></td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(s.npwp_label || 'NPWP') + ': ' + esc(s.npwp || '—') + '</td>' +
            '<td class="px-5 py-4"><div class="flex flex-wrap gap-1">' +
              (s.es_indonesia === false ? '<span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider bg-surface-container-high text-on-surface-variant">No indonesa</span>' : '') +
              (npwpPendiente ? '<span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider bg-error-container/60 text-error">NPWP pendiente</span>' : '') +
            '</div></td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              (s.activa ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-error-container/60 text-error') + '">' + (s.activa ? 'Activa' : 'Desactivada') + '</span></td>' +
            '<td class="px-5 py-4 text-right"><button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-soc-editar="' + esc(s.clave) + '">Editar</button></td></tr>';
        }).join('') : '<tr><td colspan="5" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">No hay ninguna sociedad dada de alta.</td></tr>';
      }

      if (selLog) {
        selLog.innerHTML = '<option value="">Todas las sociedades</option>' +
          socs.map(function (s) { return '<option value="' + esc(s.clave) + '">' + esc(s.razon) + '</option>'; }).join('');
      }

      // ── Historial de identidad fiscal ───────────────────────────────
      // Mismo mecanismo de DIFF que la herramienta clasica: cada fila del
      // log guarda la version ANTERIOR entera, asi que hace falta la fila
      // de DESPUES (la siguiente en el tiempo, o la sociedad de hoy si es
      // la ultima) para poder ensenar que cambio.
      function pintaLog() {
        if (!cuerpoLog || !log) return;   // sin log: fallo() ya pinto el aviso
        var filtro = selLog ? selLog.value : '';
        var porClave = {};
        log.forEach(function (l) { (porClave[l.clave] = porClave[l.clave] || []).push(l); });
        Object.keys(porClave).forEach(function (k) {
          porClave[k].sort(function (a, b) { return new Date(a.cuando) - new Date(b.cuando); });
        });

        var filas = [];
        Object.keys(porClave).forEach(function (clave) {
          if (filtro && clave !== filtro) return;
          var serie = porClave[clave];   // antiguo -> reciente
          var hoy = window.LW_V4.sociedadesPorClave[clave] || {};
          for (var i = serie.length - 1; i >= 0; i--) {
            var l = serie[i];
            var despues = (i === serie.length - 1) ? hoy : serie[i + 1].antes;
            var cambios = FISCALES.filter(function (k) { return (l.antes[k] || '') !== (despues[k] || ''); });
            if (!cambios.length) continue;   // solo cambio aspecto: no es identidad
            filas.push({
              clave: clave, cuando: l.cuando, quien: l.quien,
              cambios: cambios.map(function (k) {
                return esc(ETIQ[k] || k) + ': <del>' + esc(l.antes[k] || '—') + '</del> → <ins>' + esc(despues[k] || '—') + '</ins>';
              }).join('<br>')
            });
          }
        });
        filas.sort(function (a, b) { return new Date(b.cuando) - new Date(a.cuando); });

        cuerpoLog.innerHTML = filas.length ? filas.map(function (f) {
          var nombre = (window.LW_V4.sociedadesPorClave[f.clave] || {}).razon || f.clave;
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(fFechaHora(f.cuando)) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(nombre) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(f.quien || '(sin registrar)') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-on-surface-variant">' + f.cambios + '</td></tr>';
        }).join('') : '<tr><td colspan="4" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">' +
          (filtro ? 'Ningún cambio de identidad fiscal registrado para esta sociedad.' : 'Ningún cambio de identidad fiscal registrado todavía.') + '</td></tr>';
      }
      pintaLog();
      if (selLog) selLog.addEventListener('change', pintaLog);

      delega(cuerpoLista, [['data-lw-soc-editar', 'abreEditaSociedad']]);
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
      /* Un peldano por encima: hay pantallas que ni los admin ven — hoy la
         Comision de administracion, que abre lo que el estudio le cobra al
         cliente. Se guarda aparte y no se deduce de `esAdmin`. */
      window.LW_V4.esSuperAdmin = rol === 'super_admin';
      // la ficha de sesion entera (herramientas incluidas), para quien decida por ella
      window.LW_V4.ficha = aut.ficha || null;
      window.LW_V4.fichaContrato = function (c, opts) { fichaContrato(aut.sb, c, opts); };
      window.LW_V4.fichaFactura = function (f) { fichaFactura(aut.sb, f); };

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
