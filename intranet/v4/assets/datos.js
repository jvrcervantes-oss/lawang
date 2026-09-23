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
  /* SIN DECIMALES EN TODA LA V4 (23-sep-2026, owner: «quita decimales de toda la
     intranet v4»). Una regla en UN sitio: se envuelve la `lwFormatoImporte`
     global de dinero.js, y así la cumplen datos.js, editores.js y cualquier
     script de página que la llame. Solo cargan datos.js las páginas v4: la
     intranet clásica, los PDF y los contratos siguen con sus céntimos. Los
     CAMPOS de importe (lwImporteCanonico) no se tocan: lo que se teclea se
     guarda tal cual; esto es solo cómo se enseña. */
  if (typeof window.lwFormatoImporte === 'function' && !window.lwFormatoImporte.v4SinDecimales) {
    var lwFormatoImporteConDecimales = window.lwFormatoImporte;
    window.lwFormatoImporte = function (n, moneda, opts) {
      var o = {}; for (var k in (opts || {})) o[k] = opts[k];
      o.decimales = 0;
      return lwFormatoImporteConDecimales(Math.round(Number(n) || 0), moneda, o);
    };
    window.lwFormatoImporte.v4SinDecimales = true;
  }
  // sin dinero.js (Ajustes, Asistente, Comunicación, Reservas, Sociedades): mismo aspecto
  function fmt(n, m) {
    if (typeof lwFormatoImporte === 'function') return lwFormatoImporte(n, m);
    return new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 }).format(Math.round(Number(n) || 0)) + (m ? ' ' + m : '');
  }

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
        toastMal(lwErrorHumano(r.error, 'No se pudo guardar el closer'));
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

  /* QUIÉN LO CREÓ — una sola forma de convertir el autor guardado en un nombre
     (23-sep-2026, owner: «en toda la v4 quiero trazabilidad de qué agente ha
     creado un contrato, un recibí, una factura o lo que sea»).
     La base ya guarda el autor: como EMAIL en contratos/facturas/recibís
     (`creado_por`, default auth.email()) y en `clients.propietario`; como
     USER_ID en solicitudes_pago y comunicados. Este mapa resuelve las dos claves.
     `usuarios` lo lee cualquier agente (policy «el equipo se ve entre si»,
     es_agente()) y se piden también los DESACTIVADOS: un documento de quien ya
     no está sigue siendo suyo. Sin nombre conocido se enseña el valor guardado
     tal cual; sin valor, «sin registrar» (filas de antes de que la columna
     tuviera default) — nunca se atribuye a nadie por aproximación. Corregir un
     autor es cosa de LW_AUTORIA (super_admin, con rastro), no de aquí. */
  var AUTORES_P = null;
  function autores(sb) {
    if (!AUTORES_P) AUTORES_P = Promise.resolve(sb.from('usuarios').select('user_id,email,nombre')).then(function (r) {
      var m = {};
      if (r && r.error) console.error('[v4 datos] autores:', r.error);
      ((r && r.data) || []).forEach(function (u) {
        var n = u.nombre || u.email;
        if (u.email) m[String(u.email).toLowerCase()] = n;
        if (u.user_id) m[String(u.user_id).toLowerCase()] = n;
      });
      return m;
    }, function (e) { console.error('[v4 datos] autores:', e); return {}; });
    return AUTORES_P;
  }
  function nombreAutor(mapa, v) { return v ? ((mapa && mapa[String(v).toLowerCase()]) || String(v)) : ''; }
  function htmlAutor(mapa, v) {
    var tr = function (x) { return (typeof lwT === 'function') ? lwT(x) : x; };
    var n = nombreAutor(mapa, v);
    return n ? '<span class="font-body-md" title="' + esc(v) + '">' + esc(n) + '</span>'
      : '<span style="color:#BEB3A5" title="' + esc(tr('Documento anterior al registro de autor')) + '">' + esc(tr('sin registrar')) + '</span>';
  }
  window.LW_V4 = window.LW_V4 || {};
  window.LW_V4.autores = autores; window.LW_V4.nombreAutor = nombreAutor;

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
  function pintaListaObra(clave, items, vacio, verUrl, urls) {
    var cont = document.querySelector('[data-lw-lista="' + clave + '"]'); if (!cont) return;
    cont.innerHTML = items.length ? items.join('')
      : '<p style="font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474;margin:2px 0">' + esc(vacio) + '</p>';
    /* `urls[i]` (S16, 23-sep-2026): una URL por fila cuando la herramienta
       viva sabe abrir esa unidad concreta (`/intranet/obra/?id=`); si no,
       el `verUrl` común de siempre. */
    if (verUrl || urls) {
      var its = cont.querySelectorAll('[data-mq-item]');
      for (var i = 0; i < its.length; i++) (function (el, u) {
        if (u) el.addEventListener('click', function () { location.href = u; });
      })(its[i], (urls && urls[i]) || verUrl);
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
  /* PALETA ÚNICA DE ESTADOS DE LA V4 (23-sep-2026, owner: «¿usamos los mismos
     colores en toda la suite? que facturas tenga el mismo color en todos
     lados»). Había dos copias idénticas (pill() aquí y H.tag en editores.js)
     y la campana estrenó un ámbar y un azul propios. Ahora hay UNA, global,
     que leen los listados, las fichas y la campana. Un color = un significado:
       ok (verde)     hecho: firmado, cobrado, facturado, saldado, activo
       espera (ámbar) pendiente de alguien: en firma, sin cobrar, por vencer
       mal (rojo)     vencido, caducado, rechazado, anulado, liberado
       neutro (gris)  informativo: borrador, sin firmar, emitida, inventario
     `borde` e `icono` los usa la campana; `fondo`/`tinta` son la etiqueta. */
  var LW_TONOS = window.LW_TONOS = {
    ok:     { fondo: '#E4F0DA', tinta: '#3F5230', borde: '#3F5230', suave: '#F6FAF2', icono: 'check_circle' },
    espera: { fondo: '#FBF3E4', tinta: '#8A6A34', borde: '#C9892B', suave: '#FFFAF0', icono: 'schedule' },
    mal:    { fondo: '#FFDAD6', tinta: '#93000A', borde: '#BA1A1A', suave: '#FFF4F2', icono: 'error' },
    // en curso (lago): trámite en marcha que ya no espera a nadie más que al último paso
    // — p. ej. una solicitud APROBADA que falta pagar (23-sep-2026, owner: «diferencia
    // los estados por colores» en Comisiones; con solo ámbar, pendiente y aprobada eran iguales)
    curso:  { fondo: '#D9ECEC', tinta: '#104C4F', borde: '#104C4F', suave: '#F2F8F8', icono: 'sync' },
    neutro: { fondo: '#EAE8E2', tinta: '#2E3437', borde: '#B9B5A8', suave: '#FFFFFF', icono: 'info' }
  };
  function pill(texto, tono) {
    var t = LW_TONOS[tono] || LW_TONOS.neutro, c = [t.fondo, t.tinta];
    return '<span style="display:inline-block;padding:2px 9px;border-radius:999px;font:600 11px/1.5 \'Neue Kabel\',sans-serif;letter-spacing:.04em;text-transform:uppercase;background:' + c[0] + ';color:' + c[1] + '">' + esc(texto) + '</span>';
  }
  var ABRIR = '<span style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline">Abrir</span>';
  function enlaceFichaContrato(x) {
    return '<a href="#" data-lw-ficha-contrato="' + esc(x.id) + '" style="color:#104C4F;font-weight:600;text-decoration:underline">' + esc(x.numero) + '</a>' +
      (x.tipo ? ' <span style="color:#8A8474">· ' + esc(tipoC(x.tipo)) + '</span>' : '');
  }
  /* Borrar operación (S13, 22-sep-2026): mismo RPC y mismo gate que la
     clásica (intranet/operaciones/index.html, borrarOperacion/967-1044),
     releído hoy porque `borrar_operacion()` se tocó 5 veces en las últimas
     horas por hallazgos de Legal/Administración AJENOS a este encargo. La
     versión aplicada (20260922143000_borrar_operacion_gate_pagada_cubre_closer)
     purga comisiones_devengadas + su solicitud_pago al vuelo, y solo para en
     seco si alguna comisión de la cadena (closer O manager) está ya
     'pagada' — el owner decidió purgar automáticamente el resto (22-sep,
     migración 134500). El recuento de aquí es solo UX, igual que en «Borrar
     proyecto»: el RPC es quien decide de verdad y puede desincronizarse
     entre este cálculo y el clic — el mensaje real del gate se enseña tal
     cual si para. */
  /* `dialogo.js` (lwConfirmar) es un módulo bajo demanda de editores.js
     (aseguraModulosDoc, no expuesto en window) — Operaciones no dispara
     ningún otro flujo que lo cargue antes de este botón (prorroga_reserva/
     libera_reserva usan `lwVentana`, otro módulo). Verificado en producción
     (22-sep-2026): sin este loader propio, el primer clic en «Borrar
     operación» se quedaba en «prueba de nuevo en un segundo» para siempre,
     porque nada más en la página iba a cargarlo. Se pide UNA vez; si ya está
     (otra pantalla lo cargó antes), se resuelve al instante. */
  var _cargaDialogo = null;
  function aseguraDialogoV4() {
    if (typeof lwConfirmar === 'function') return Promise.resolve();
    if (_cargaDialogo) return _cargaDialogo;
    _cargaDialogo = new Promise(function (res, rej) {
      var s = document.createElement('script');
      s.src = '/contracts/assets/dialogo.js?v=cefc9e4e';
      s.onload = res;
      s.onerror = function () { _cargaDialogo = null; rej(new Error('no se pudo cargar dialogo.js')); };
      document.head.appendChild(s);
    });
    return _cargaDialogo;
  }
  /* ══════════════ la campana (S17, 23-sep-2026) ══════════════
     Marcaba «18» en las 18 pantallas (un número de Stitch) y luego solo contaba
     `notificaciones`. Ahora sale de `lwAvisos` (contracts/assets/avisos.js), la
     MISMA función que usa la campana de las herramientas clásicas: hechos +
     facturas por vencer + enlaces de firma por caducar, con sus mismos filtros
     y su misma idea de «nuevo». Aquí solo se pinta: contador en el botón y la
     lista en el cajón compartido. Abrirla da los hechos por vistos, como la
     viva (`marcar_notificaciones_leidas`, sin parámetros: usa auth.uid()).
     Los enlaces de Operaciones se quedan dentro de la v4 (su `?contrato=`
     acepta el id desde hoy); el resto van a la herramienta de siempre. */
  /* COLORES DE LA CAMPANA (23-sep-2026, owner: «más claros con colores»).
     El nivel y la etiqueta los decide avisos.js (fuente única); aquí solo se
     pintan. Misma paleta que las etiquetas del cajón (H.tag): rojo = vencido o
     caducado, ámbar = vence pronto, verde = buena noticia, lago = trámite en
     marcha, gris = movimiento de inventario. Siempre con icono y palabra: el
     color solo no basta. Lo que pide acción va arriba y aparte. */
  // la paleta ÚNICA de la v4 (LW_TONOS, arriba): el nivel de avisos.js se traduce a ella
  var NIVEL_A_TONO = { mal: 'mal', atencion: 'espera', ok: 'ok', neutro: 'neutro' };
  function tonoAviso(nivel) { return LW_TONOS[NIVEL_A_TONO[nivel] || 'neutro']; }
  /* VISTA DE FILAS (23-sep-2026, owner: «la información está concentrada y
     muy vacía»). El cajón vuelve a su ancho de siempre y cada aviso es UNA
     fila que reparte lo que dice por el ancho, como una tabla: estado ·
     aviso · detalle · fecha. En móvil (menos de 720 px) la fila se apila en
     dos líneas. Colores: los de la paleta única (LW_TONOS). */
  function pintaAvisos(avisos, aV4) {
    var alertas = avisos.filter(function (a) { return a.clase === 'alerta'; })
      // lo más urgente primero: vencido antes que por vencer, y dentro, lo más antiguo
      .sort(function (a, b) { return (a.nivel === 'mal' ? 0 : 1) - (b.nivel === 'mal' ? 0 : 1) || new Date(a.cuando) - new Date(b.cuando); });
    var hechos = avisos.filter(function (a) { return a.clase !== 'alerta'; });
    var nMal = alertas.filter(function (a) { return a.nivel === 'mal'; }).length;
    var nAt = alertas.length - nMal;
    var nNuevos = hechos.filter(function (a) { return a.nuevo; }).length;
    var chip = function (n, texto, t) {
      return n ? '<span style="display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:999px;background:' + t.fondo + ';color:' + t.tinta + ';font-size:12px;font-weight:700">' +
        '<span class="material-symbols-outlined" style="font-size:15px">' + t.icono + '</span>' + n + ' ' + esc(texto) + '</span>' : '';
    };
    var resumen = (nMal || nAt || nNuevos)
      ? '<div style="display:flex;flex-wrap:wrap;gap:6px">' +
          chip(nMal, nMal === 1 ? 'vencido o caducado' : 'vencidos o caducados', LW_TONOS.mal) +
          chip(nAt, 'por vencer', LW_TONOS.espera) +
          chip(nNuevos, nNuevos === 1 ? 'novedad sin ver' : 'novedades sin ver', LW_TONOS.neutro) + '</div>'
      : '';
    var hoyAnio = new Date().getFullYear();
    var fechaCorta = function (x) {
      if (!x) return '';
      var d = new Date(String(x).length === 10 ? x + 'T00:00:00' : x);
      if (isNaN(d)) return String(x).slice(0, 10);
      return d.toLocaleDateString('es-ES', d.getFullYear() === hoyAnio ? { day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short', year: 'numeric' });
    };
    var css = '<style>' +
      '.lw-av{display:grid;grid-template-columns:22px 170px minmax(0,1.35fr) minmax(0,1fr) 78px;align-items:center;gap:12px;padding:9px 14px;border-radius:10px;border:1px solid #E4DCCB;color:#1b1c19;text-decoration:none;transition:filter .15s}' +
      '.lw-av:hover{filter:brightness(.97)}' +
      '.lw-av-cab{display:grid;grid-template-columns:22px 170px minmax(0,1.35fr) minmax(0,1fr) 78px;gap:12px;padding:0 15px 2px;font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:#8A8474}' +
      '.lw-av-t{font-size:13px;line-height:1.35;overflow-wrap:anywhere}' +
      '.lw-av-d{font-size:12px;color:#44483f;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.lw-av-f{font-size:11.5px;color:#75786e;text-align:right;white-space:nowrap}' +
      '@media (max-width:720px){.lw-av-cab{display:none}.lw-av{grid-template-columns:20px minmax(0,1fr) auto;gap:4px 10px}' +
      '.lw-av .lw-av-e{grid-column:2;grid-row:2}.lw-av .lw-av-t{grid-column:2;grid-row:1}.lw-av .lw-av-d{grid-column:2 / 4;grid-row:3;white-space:normal}.lw-av .lw-av-f{grid-column:3;grid-row:1}}' +
      '</style>';
    var fila = function (a) {
      var t = tonoAviso(a.nivel);
      var fondo = (a.clase === 'alerta' || a.nuevo) ? t.suave : '#FFFFFF';
      return '<a class="lw-av" href="' + esc(aV4(a.enlace)) + '" title="' + esc(a.titulo + (a.detalle ? ' — ' + a.detalle : '')) + '" style="border-left:4px solid ' + t.borde + ';background:' + fondo + '">' +
        '<span class="material-symbols-outlined" style="font-size:19px;color:' + t.borde + '">' + t.icono + '</span>' +
        '<span class="lw-av-e" style="display:flex;flex-wrap:wrap;gap:4px">' +
          '<span style="padding:1px 8px;border-radius:999px;background:' + t.fondo + ';color:' + t.tinta + ';font-size:10.5px;line-height:18px;font-weight:700;letter-spacing:.04em;text-transform:uppercase">' + esc(a.etiqueta || 'Aviso') + '</span>' +
          (a.nuevo && a.clase !== 'alerta' ? '<span style="padding:1px 8px;border-radius:999px;background:#2E3437;color:#fff;font-size:10.5px;line-height:18px;font-weight:700;letter-spacing:.04em;text-transform:uppercase">Nuevo</span>' : '') +
        '</span>' +
        '<span class="lw-av-t" style="font-weight:' + (a.nuevo || a.clase === 'alerta' ? '700' : '500') + '">' + esc(a.titulo) + '</span>' +
        '<span class="lw-av-d">' + esc(a.detalle || '') + '</span>' +
        '<span class="lw-av-f">' + esc(fechaCorta(a.cuando)) + '</span>' +
      '</a>';
    };
    var bloque = function (titulo, lista) {
      return lista.length ? '<section style="display:grid;gap:6px">' +
        '<h4 style="margin:6px 0 2px;font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:#75786e">' + esc(titulo) + ' (' + lista.length + ')</h4>' +
        '<div class="lw-av-cab"><span></span><span>Estado</span><span>Aviso</span><span>Detalle</span><span style="text-align:right">Fecha</span></div>' +
        lista.map(fila).join('') + '</section>' : '';
    };
    return css + resumen + bloque('Requiere atención', alertas) + bloque('Actividad reciente', hechos);
  }

  function campanaV4(aut, rol) {
    var badges = document.querySelectorAll('[data-lw="k-avisos"]');
    var boton = badges.length ? badges[0].closest('button') : null;
    var ULTIMO = null;
    function pintaContador(n, avisos) {
      // el número toma el color de lo más grave que haya sin atender
      var peor = (avisos || []).filter(function (a) { return a.nuevo; }).reduce(function (acc, a) {
        return acc === 'mal' || a.nivel === 'mal' ? 'mal' : (acc === 'atencion' || a.nivel === 'atencion' ? 'atencion' : 'neutro');
      }, null);
      badges.forEach(function (e) {
        e.textContent = n == null ? '—' : (n > 99 ? '99+' : String(n));
        e.style.display = n === 0 ? 'none' : '';
        e.style.backgroundColor = !peor ? '' : (peor === 'neutro' ? '#2E3437' : tonoAviso(peor).borde);
        e.style.color = peor ? '#fff' : '';
      });
    }
    function aV4(href) {
      return href.indexOf('/intranet/operaciones/') === 0 ? '/intranet/v4/operaciones/' + href.slice('/intranet/operaciones/'.length) : href;
    }
    function carga() {
      if (typeof lwAvisos !== 'function') { console.error('[v4 datos] falta contracts/assets/avisos.js'); pintaContador(null); return Promise.resolve(null); }
      var ficha = aut.ficha || {};
      var email = (aut.session && aut.session.user && aut.session.user.email) || '';
      return lwAvisos(aut.sb, { esAdmin: rol === 'admin' || rol === 'super_admin', email: email, vistoHasta: ficha.notif_visto_hasta || null })
        .then(function (out) { ULTIMO = out; pintaContador(out.sinLeer, out.avisos); return out; },
              function (e) { console.error('[v4 datos] avisos:', e); pintaContador(null); return null; });
    }
    function abre() {
      if (typeof window.lwCajon !== 'function') { toast('El panel aún no ha cargado — prueba de nuevo en un segundo.'); return; }
      var H = window.lwCajonHtml;
      var pinta = function (out) {
        var cuerpo;
        // una consulta caída no se lee como «nada nuevo»: la nota va antes que la lista, haya lista o no
        var notaFallo = (out && out.fallos) ? H.nota(out.cobroSinComprobar ? 'No se pudo comprobar lo cobrado: las facturas por vencer no se muestran.' : 'Alguna de las consultas de avisos falló: la lista puede estar incompleta.') : '';
        if (!out) cuerpo = H.nota('No se pudieron cargar los avisos. Prueba a recargar la página.');
        else if (!out.avisos.length) cuerpo = notaFallo + '<p style="margin:0;font-size:13px;color:#8A8474">Nada nuevo.</p>';
        else cuerpo = notaFallo + pintaAvisos(out.avisos, aV4);
        // ancho de siempre (owner: «que fuese muy amplia nunca fue un problema»);
        // `desde`: el cajón crece desde la campana y se recoge hacia ella
        window.lwCajon({ titulo: 'Avisos', sub: 'Lo que ha pasado y lo que vence en los próximos 15 días.', cuerpo: cuerpo, desde: boton,
          // el 60% de siempre en escritorio; en móvil casi toda la pantalla (el 60% eran ~230 px)
          ancho: 'max(60vw, min(96vw, 560px))' });
      };
      // abrir = dar los hechos por vistos (las alertas de ≤5 días siguen contando, como en la viva)
      if (ULTIMO && ULTIMO.sinLeer) {
        aut.sb.rpc('marcar_notificaciones_leidas').then(function (r) { if (r && r.error) console.error('[v4 datos] marcar avisos:', r.error); });
        pintaContador(0);
      }
      if (ULTIMO) pinta(ULTIMO); else carga().then(pinta);
    }
    if (boton) {
      boton.setAttribute('data-real', '');   // maqueta.js deja en paz lo cableado
      boton.addEventListener('click', function (ev) { ev.stopPropagation(); abre(); });
    }
    carga();
  }

  /* ══════════════ FAQ del Investor Deck en el cajón de Proyectos (23-sep-2026) ══════════════
     Decisión del owner («la pestaña de FAQ no se ve, replanteemos eso»): las
     7 FAQ PÚBLICAS de cada proyecto viven en `deck_faq` ({es,en,id}) y hasta
     hoy no se veían en ninguna pantalla de la intranet — el cajón solo leía
     las preguntas internas de inversores. Leer: RLS `es_agente()`. Escribir
     (editores.js): RLS `es_admin()`, con auditoría en `deck_publicaciones`.
     Todo se pinta con textContent (revisión previa de Seguridad): la respuesta
     la escribe un admin y la ve todo el equipo. */
  var FAQ_DECK_PROYECTO = null;
  function textoIdioma(o) {
    o = o || {};
    var l = window.LW_IDIOMA === 'en' ? 'en' : 'es';
    return o[l] || o.es || o.en || o.id || '';
  }
  /* S10 (23-sep-2026): una unidad sin modelo (hoy 67, todas parcelas sueltas)
     decía «—» en su tipo; la clásica enseña el tipo de la unidad. */
  function tipoUnidad(u) {
    var t = String((u && u.tipo) || '').trim();
    return t ? t.charAt(0).toUpperCase() + t.slice(1) : '—';
  }
  function pintaDeckFaq(sb, proyecto) {
    var caja = document.getElementById('d-deckfaq');
    if (!caja || !proyecto) return;
    FAQ_DECK_PROYECTO = proyecto;
    window.LW_V4 = window.LW_V4 || {};
    window.LW_V4.deckFaqProyecto = proyecto;
    window.LW_V4.repintaDeckFaq = function () { pintaDeckFaq(sb, FAQ_DECK_PROYECTO); };
    caja.textContent = 'Cargando…';
    if (!proyecto.id) { caja.textContent = 'Este proyecto no tiene id en el catálogo: no se pueden leer sus FAQ.'; return; }
    sb.from('deck_faq').select('id,pregunta,respuesta,orden,publicado,actualizado_en')
      .eq('proyecto_id', proyecto.id).order('orden', { ascending: true })
      .then(function (r) {
        if (FAQ_DECK_PROYECTO !== proyecto) return;          // se abrió otro proyecto mientras tanto
        caja.textContent = '';
        if (r.error) { caja.textContent = 'No se pudieron leer las FAQ del deck: ' + r.error.message; return; }
        var filas = r.data || [];
        var mapa = {}; filas.forEach(function (x) { mapa[x.id] = x; });
        window.LW_V4.deckFaq = mapa;
        var nPub = filas.filter(function (x) { return x.publicado; }).length;
        var n = document.querySelector('[data-lw="dq-n"]');
        if (n) n.textContent = filas.length ? '· ' + nPub + ' publicada' + (nPub === 1 ? '' : 's') + (filas.length > nPub ? ' de ' + filas.length : '') : '';
        if (!filas.length) {
          var vacio = document.createElement('p');
          vacio.style.cssText = 'font:500 13px/1.5 sans-serif;color:#75786e;margin:0';
          vacio.textContent = 'El deck de este proyecto no tiene preguntas frecuentes.';
          caja.appendChild(vacio); return;
        }
        var admin = !!(window.LW_V4 && window.LW_V4.esAdmin);
        filas.forEach(function (x) {
          var fila = document.createElement('div');
          fila.className = 'px-2.5 py-1.5 rounded-lg bg-surface-container-low';
          fila.setAttribute('data-deckfaq-id', x.id);
          var fl = document.createElement('div'); fl.className = 'flex items-start justify-between gap-2';
          var det = document.createElement('details'); det.className = 'flex-1 min-w-0';
          var sum = document.createElement('summary'); sum.className = 'font-body-sm text-body-sm text-on-surface cursor-pointer';
          sum.textContent = textoIdioma(x.pregunta) || '(sin pregunta)';
          var resp = document.createElement('p'); resp.className = 'font-body-sm text-body-sm text-on-surface-variant mt-1.5';
          resp.style.whiteSpace = 'pre-line';
          resp.textContent = textoIdioma(x.respuesta) || '—';
          var meta = document.createElement('span');
          meta.style.cssText = 'display:block;margin-top:4px;font-size:10.5px;color:#8A8474';
          var faltan = ['en', 'id'].filter(function (l) { return !((x.pregunta || {})[l] && (x.respuesta || {})[l]); });
          meta.textContent = (x.publicado ? 'Publicada' : 'No publicada — no sale en el deck') +
            (faltan.length ? ' · falta ' + faltan.join('/').toUpperCase() : '') +
            (x.actualizado_en ? ' · cambiada el ' + fFecha(x.actualizado_en) : '');
          if (!x.publicado) meta.style.color = '#8A6A34';
          det.appendChild(sum); det.appendChild(resp); det.appendChild(meta);
          fl.appendChild(det);
          if (admin) {
            var ed = document.createElement('button');
            ed.type = 'button'; ed.setAttribute('data-deckfaq-editar', ''); ed.setAttribute('data-real', '');
            ed.title = 'Editar'; ed.setAttribute('aria-label', 'Editar pregunta del deck');
            ed.className = 'p-1 rounded text-outline hover:text-deep-lagoon hover:bg-surface-container-lowest shrink-0';
            var ic = document.createElement('span'); ic.className = 'material-symbols-outlined text-[15px]'; ic.textContent = 'edit';
            ed.appendChild(ic); fl.appendChild(ed);
          }
          fila.appendChild(fl);
          caja.appendChild(fila);
        });
      }, function (e) { caja.textContent = 'No se pudieron leer las FAQ del deck: ' + ((e && e.message) || e); });
  }

  function borrarOperacionV4(sb, c0) {
    var fam = 'id.eq.' + c0.id + ',contrato_padre_id.eq.' + c0.id;
    sb.rpc('contratos_equipo').select('id,numero').or(fam).then(function (rc) {
      if (rc.error) { toastMal(lwErrorHumano(rc.error, 'No se pudo preparar el borrado')); return; }
      var contratos = (rc.data && rc.data.length) ? rc.data : [{ id: c0.id, numero: c0.numero }];
      var ids = contratos.map(function (x) { return x.id; });
      Promise.all([
        sb.rpc('facturas_equipo').select('id,anulada').in('contrato_id', ids),
        sb.rpc('contrato_firmas_equipo').select('id,contrato_id,estado,snapshot_path').in('contrato_id', ids).in('estado', ['pendiente', 'procesando']),
        sb.from('comisiones_devengadas').select('id,estado,solicitud_id').in('contrato_raiz_id', ids)
      ]).then(function (r) {
        var facturasVivas = (r[0].error ? [] : (r[0].data || [])).filter(function (f) { return !f.anulada; }).length;
        var firmasVivas = r[1].error ? [] : (r[1].data || []);
        var comisiones = r[2].error ? [] : (r[2].data || []);
        var yaPagadas = comisiones.filter(function (x) { return x.estado === 'pagada'; }).length;
        var detalle = [];
        detalle.push(contratos.length > 1
          ? contratos.length + ' contratos (' + contratos.map(function (x) { return x.numero || 'sin nº'; }).join(', ') + ')'
          : 'el contrato ' + (c0.numero || 'sin nº'));
        if (firmasVivas.length) detalle.push(firmasVivas.length + ' ' + (firmasVivas.length === 1 ? 'enlace de firma quedará ANULADO' : 'enlaces de firma quedarán ANULADOS'));
        if (facturasVivas) detalle.push(facturasVivas + ' ' + (facturasVivas === 1 ? 'factura quedará ANULADA (no se borra: la serie no puede tener huecos)' : 'facturas quedarán ANULADAS (no se borran: la serie no puede tener huecos)'));
        if (comisiones.length) detalle.push(comisiones.length + ' comisión(es) devengada(s) y su solicitud de pago (si la tienen) se PURGARÁN' +
          (yaPagadas ? ' — OJO: ' + yaPagadas + ' ya está' + (yaPagadas === 1 ? '' : 'n') + ' PAGADA(S): el sistema va a parar el borrado entero' : ''));
        detalle.push('La parcela vinculada vuelve a estar disponible.');
        aseguraDialogoV4().then(function () {
          return lwConfirmar({
            titulo: 'Borrar la operación de ' + (c0.comprador_nombre || 'sin comprador'),
            cuerpo: '<p>Se borra ' + detalle[0] + '.</p>' +
              (detalle.length > 1 ? '<ul style="margin:0 0 10px;padding-left:18px">' + detalle.slice(1).map(function (x) { return '<li>' + x + '</li>'; }).join('') + '</ul>' : '') +
              '<p>No hay papelera. Si hay una comisión ya pagada (de closer o de manager), el sistema para el borrado entero y hay que resolverlo a mano.</p>',
            confirmar: 'Borrar la operación', tono: 'peligro'
          });
        }, function () {
          toastMal('No se pudo cargar el diálogo de confirmación — prueba de nuevo.');
          return false;
        }).then(function (ok) {
          if (!ok) return;
          var rutas = [];
          ids.forEach(function (cid) { rutas.push('pendientes/' + cid + '.html'); });
          firmasVivas.forEach(function (f) { if (f.snapshot_path) rutas.push(f.snapshot_path); });
          rutas = rutas.filter(function (x, i, a) { return x && x.indexOf('pendientes/') === 0 && a.indexOf(x) === i; });
          sb.rpc('borrar_operacion', { p_contrato_id: c0.id }).then(function (rr) {
            if (rr.error) { toastMal(lwErrorHumano(rr.error, 'No se pudo borrar')); return; }
            // Los borradores de firma del ALMACENAMIENTO no los borra el RPC (no
            // alcanza a un bucket): se limpian aparte, DESPUÉS de que el borrado
            // haya ido bien — un fallo aquí es basura huérfana, no un motivo para
            // parar (mismo criterio que la clásica).
            if (rutas.length) {
              sb.storage.from('contratos-firmados').remove(rutas).then(function (rs) {
                if (rs.error) console.warn('Operación borrada; sus borradores de firma siguen en el almacenamiento:', rs.error.message);
              });
            }
            var d = rr.data || {};
            toast('Operación borrada · ' + (d.contratos_borrados || 0) + ' contrato(s), ' + (d.facturas_anuladas || 0) + ' factura(s) anulada(s)' +
              (d.comisiones_purgadas ? ', ' + d.comisiones_purgadas + ' comisión(es) purgada(s)' : ''));
            if (window.lwCierraCajon) window.lwCierraCajon();
            location.reload();
          });
        });
      });
    });
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
    /* Solo lo que es DEL CONTRATO (owner, 22-sep-2026). «Emitir recibí» y
       «Nueva proforma» se quitaron de aquí: un recibí va contra una factura,
       no contra un contrato (79 de 82 recibís reales están aplicados a una
       factura; se crea desde la factura con «Crear recibí»), y la proforma
       se emite desde Facturas. */
    var acciones = [
      { texto: c0.bloqueado ? 'Ver en el generador' : 'Editar en el generador', href: '/contracts/app.html?contrato=' + encodeURIComponent(c0.id), tono: 'primario' }
    ];
    // «Ver en Operaciones» (antes «Expediente», 22-sep-2026): la fila de la
    // operación entera —cadena y dinero de toda ella— con esta ficha abierta.
    if (!opts.sinExpediente) acciones.push({ texto: 'Ver en Operaciones', href: '/intranet/v4/operaciones/?contrato=' + encodeURIComponent(num) });
    // Borrar operación (S13, 22-sep-2026): mismo botón que la clásica
    // (intranet/operaciones/index.html:967, id="btnBorrarOp") — nunca oculto
    // por rol, el gate de verdad es el propio RPC (es_agente / es_super_admin).
    acciones.push({ texto: 'Borrar operación', tono: 'peligro', onClick: function () { borrarOperacionV4(sb, c0); } });
    acciones.push({ texto: 'Cerrar', cerrar: true });
    /* Trazabilidad en la barra (22-sep-2026, owner): en /v4/contratos/ la ficha
       abierta se refleja como `?contrato=NUM` — lo mismo que el listado ya sabe
       abrir al cargar (más abajo, «?contrato=NUM abre la ficha directamente»),
       así que la URL se puede copiar, compartir y recargar. Al cerrar se quita.
       replaceState, no pushState: el botón Atrás del navegador sigue saliendo
       de la herramienta, no rebobinando fichas. */
    var enContratos = location.pathname.indexOf('/v4/contratos/') !== -1 ||
                      location.pathname.indexOf('/v4/operaciones/') !== -1;   // Operaciones también abre por ?contrato= (22-sep)
    if (enContratos && num) { try { history.replaceState(null, '', '?contrato=' + encodeURIComponent(num)); } catch (e) { /* sin historial (iframe, file:) */ } }
    var caj = window.lwCajon({
      sub: tipoC(c0.tipo) + (c0.bloqueado ? ' · firmado' : (c0.pdf_firmado_path ? ' · reabierto' : ' · borrador')),
      titulo: num,
      bajoTitulo: (c0.comprador_nombre || '—') + (c0.proyecto_nombre ? ' · ' + c0.proyecto_nombre : '') + (c0.parcela_codigo ? ' · Parcela ' + c0.parcela_codigo : ''),
      cuerpo: '<p style="margin:0;font-size:13px;color:#8A8474">Trayendo la ficha…</p>',
      acciones: acciones,
      alCerrar: function () { if (enContratos) { try { history.replaceState(null, '', location.pathname); } catch (e) {} } }
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
      sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,parcela_codigo,precio_total,moneda,bloqueado,contrato_padre_id,created_at,liberado_en,pdf_firmado_path').or(familia),
      // SIN filtro de contrato (S13, 22-sep-2026): el estado de cuenta
      // CONSOLIDADO de la cadena (más abajo) necesita lo cobrado de la raíz Y
      // de cada hijo, no solo de `id`. Mismo coste que ya paga el listado
      // (`operaciones:`, más arriba en este fichero), que pide esta misma RPC
      // sin filtrar.
      sb.rpc('contratos_cobrado_equipo').select('contrato_id,cobrado'),
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
      sb.from('unidades').select('id,codigo,estado,proyecto,proyecto_id').eq('contrato_id', id),
      /* Vencimiento y prórrogas de una Carta de Reserva (22-sep-2026): la fecha
         la dice la BASE (`reserva_vence_el`, base + última prórroga), nunca se
         suma aquí fecha_pago_reserva + validez — es la misma función que usa
         el cron que libera, así que la ficha y el automatismo no pueden
         discrepar. Para un contrato que no es Carta devuelve null y no se pinta. */
      sb.rpc('reserva_vence_el', { p_contrato_id: id }),
      sb.from('contrato_prorrogas').select('n,dias,desde,hasta,motivo,comunicado_al_comprador,quien,creado_en').eq('contrato_id', id).order('n'),
      // los topes de la prórroga y los días de gracia los pone el owner en /v4/ajustes/ (22-sep)
      sb.from('parametros').select('clave,valor').like('clave', 'reservas.%')
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
      // Carta de Reserva viva: catálogo real (contrato_tipo_etapa), ver el botón Liberar más abajo
      var tiposReservaCat = (r[7].data || []).map(function (x) { return x.tipo; });
      var esCartaViva = tiposReservaCat.indexOf(c.tipo) !== -1 && !c.liberado_en;
      var venceEl = (r[9] && !r[9].error && r[9].data) ? String(r[9].data).slice(0, 10) : null;
      var prorrogas = (r[10] && r[10].data) || [];
      var PARAM = {};
      ((r[11] && r[11].data) || []).forEach(function (x) { PARAM[x.clave] = x.valor; });
      function param(k, def) { var v = PARAM[k]; return (typeof v === 'number' && isFinite(v)) ? v : def; }
      var diasGracia = param('reservas.dias_gracia', 3);
      var maxProrrogasManager = param('reservas.prorrogas_max_manager', 2);
      var maxDiasManager = param('reservas.prorroga_dias_max_manager', 30);
      var maxDiasAdmin = param('reservas.prorroga_dias_max_admin', 180);
      var diasDefecto = param('reservas.prorroga_dias_defecto', 15);
      var hoyISO = new Date().toISOString().slice(0, 10);
      function masDias(iso, n) { var d = new Date(iso + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
      /* ---------- RESUMEN DE LA VENTA (22-sep-2026, owner: «el cajetín al
         abrir una operación sigue sin estar claro») ----------
         La ficha respondía «qué es el contrato RP00198» cuando la pregunta,
         viniendo de Operaciones, es «dónde está esta venta y qué toca ahora».
         Así que lo primero es eso: la situación con LA MISMA palabra que la
         fila del listado (etapaOperacion), el dinero de la cadena entera
         (cuentaGrupo — Regla 0, cero aritmética propia) y el siguiente paso
         deducido solo de datos que ya tenemos (nunca se inventa). El detalle
         contrato a contrato va después. */
      var fs = r[1].data || [], vs = r[2].data || [], fi = r[3].data || [];
      var cobradoPorId = {};
      (r[6] && r[6].data || []).forEach(function (x) { cobradoPorId[x.contrato_id] = Number(x.cobrado) || 0; });
      var cobrado = cobradoPorId[c.id] != null ? cobradoPorId[c.id] : null;
      var otrasMon = fs.filter(function (f) { return f.tipo === 'recibi' && !f.anulada && (f.moneda || 'EUR') !== (c.moneda || 'EUR'); }).length;
      var pend = (cobrado != null && c.precio_total != null && !esPreliminar(c)) ? Math.max(0, Number(c.precio_total) - cobrado) : null;
      /* La cadena: desde Operaciones llega entera y con las firmas de cada
         pieza (opts.cadena); desde el resto de pantallas se arma con lo que
         trae `familia` (padre + hijos de `c`). Cada pieza lleva su cobrado del
         oráculo y se le da a cuentaGrupo/etapaOperacion la forma que esperan. */
      c.firmas = fi; c.facturas = fs;
      var piezas = (opts.cadena && opts.cadena.length) ? opts.cadena.slice()
        : (padre ? [padre, c].concat(hijos) : [c].concat(hijos));
      piezas.sort(function (a, b) { return String(a.created_at || '').localeCompare(String(b.created_at || '')); });
      piezas.forEach(function (x) { x.cobrado = cobradoPorId[x.id] || 0; if (!x.firmas) x.firmas = []; if (x.id !== c.id) porId[x.id] = porId[x.id] || x; });
      var grupoRaiz = Object.assign({}, piezas[0], { padre: null, hijos: piezas.slice(1) });
      var hayCadena = piezas.length > 1;
      var cg = (typeof cuentaGrupo === 'function') ? cuentaGrupo(grupoRaiz) : null;
      var etapaV = (typeof etapaOperacion === 'function') ? etapaOperacion(grupoRaiz) : null;
      var ETQ2 = { liberada: 'Reserva liberada' }; (typeof ETAPAS !== 'undefined' ? ETAPAS : []).forEach(function (e) { ETQ2[e[0]] = e[1]; });
      var TONO2 = { sin_firmar: 'espera', firma_viva: 'espera', cobro_pend: 'mal', cobro_ok: 'ok', liberada: '' };
      function estadoPieza(x) {
        if (x.liberado_en) return ['liberada', 'mal'];
        if (x.bloqueado) return ['firmado', 'ok'];
        if ((x.firmas || []).some(function (f) { return f.estado === 'pendiente' && !firmaCaducada(f); })) return ['en firma', 'espera'];
        if (x.pdf_firmado_path) return ['reabierto', 'espera'];
        return ['borrador', 'neutro'];
      }
      var firmasVivas = fi.filter(function (f) { return f.estado === 'pendiente' && !firmaCaducada(f); });
      var sigPaso;
      if (c.liberado_en) {
        sigPaso = 'Reserva liberada el ' + fFecha(c.liberado_en) + (c.liberado_motivo === 'desistida' ? ' (el comprador desistió)' : ' (plazo vencido)') + '. No queda nada exigible.';
      } else if (!c.bloqueado) {
        if (firmasVivas.length) sigPaso = 'Esperando la firma de ' + firmasVivas.map(function (f) { return f.firmante_nombre || f.firmante_rol || 'firmante'; }).join(', ') + (firmasVivas[0].expira_en ? ' · caduca el ' + fFecha(firmasVivas[0].expira_en) : '') + '.';
        else if (c.pdf_firmado_path) sigPaso = 'Se reabrió después de firmarse: hay que volver a enviarlo a firma.';
        else sigPaso = 'Borrador: falta enviarlo a firma.';
      } else if (esCartaViva) {
        sigPaso = 'Reserva firmada' + (venceEl ? ' · vence el ' + fFecha(venceEl) : '') + (hijos.length ? '.' : ' · siguiente paso: crear el Bloqueo de Parcela.');
      } else {
        var proxHito = vs.filter(function (v) { return !v.factura_id && !v.no_facturar; })[0];
        var pendV = cg ? cg.pendiente : pend;
        if (proxHito) sigPaso = 'Próximo pago: ' + (proxHito.monto != null ? fmt(proxHito.monto, c.moneda) : (proxHito.pct != null ? proxHito.pct + ' %' : '')) + (proxHito.fecha ? ' el ' + fFecha(proxHito.fecha) : ' (sin fecha)') + (proxHito.descripcion ? ' · ' + proxHito.descripcion : '') + '.';
        else if (pendV != null && pendV > 0) sigPaso = 'Todo facturado; pendiente de cobro ' + fmt(pendV, c.moneda) + '.';
        else if (pendV === 0) sigPaso = 'Cobrado del todo.';
        else sigPaso = 'Firmado sin precio: no hay nada que cobrar registrado.';
      }
      var precioR = cg ? cg.precio : c.precio_total, cobradoR = cg ? cg.facturado : cobrado, pendR = cg ? cg.pendiente : pend;
      var cajita = function (etq, val, sub) {
        return '<div style="background:#fff;border:1px solid #E4DCCB;border-radius:10px;padding:10px 12px;min-width:0"><div style="font-size:10.5px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:#75786e">' + esc(etq) + '</div>' +
          '<div style="margin-top:4px;font:700 18px/1.2 \'Neue Kabel\',sans-serif;color:#104C4F;overflow-wrap:anywhere">' + val + '</div>' +
          (sub ? '<div style="font-size:11px;color:#8A8474;margin-top:2px">' + esc(sub) + '</div>' : '') + '</div>';
      };
      var sub = hayCadena ? 'de la venta completa (' + piezas.length + ' contratos)' : '';
      cuerpo += H.seccion('Resumen de la venta',
        '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px">' +
          cajita('Situación', etapaV ? H.tag(ETQ2[etapaV] || etapaV, TONO2[etapaV] || '') : H.tag(c.bloqueado ? 'Firmado' : 'Borrador', c.bloqueado ? 'ok' : 'espera'), sub) +
          cajita('Precio', precioR != null ? esc(fmt(precioR, c.moneda)) : '<span style="color:#8A8474;font-size:14px">sin fijar</span>', hayCadena ? 'suma de la cadena; la Carta no suma' : (esPreliminar(c) ? 'el de la casa entera; aquí solo se cobra la señal' : '')) +
          cajita('Cobrado', cobradoR != null ? esc(fmt(cobradoR, c.moneda)) : '—', 'por recibís') +
          ((cg && cg.soloPreliminar) ? cajita('Pendiente', '—', 'una reserva no debe el precio de la casa')
                                     : cajita('Pendiente', pendR != null ? esc(fmt(pendR, c.moneda)) : '—', '')) +
        '</div>' +
        '<div style="margin-top:8px;font-size:13px;color:#2E3437"><span style="font-weight:700;color:#75786e;font-size:11px;letter-spacing:.1em;text-transform:uppercase;margin-right:8px">Siguiente paso</span>' + esc(sigPaso) + '</div>');
      if (hayCadena) {
        cuerpo += H.seccion('Contratos de esta venta (' + piezas.length + ')',
          H.tabla(['Contrato', 'Tipo', 'Estado', 'Precio', 'Cobrado'], piezas.map(function (x) {
            var st = estadoPieza(x), esEste = x.id === c.id;
            return [esEste ? '<b>' + esc(x.numero || '—') + '</b> <span style="font-size:11px;color:#8A8474">esta ficha</span>'
                           : '<a href="#" data-lw-ficha-contrato="' + esc(x.id) + '" style="color:#104C4F;font-weight:600;text-decoration:underline">' + esc(x.numero || '—') + '</a>',
              esc(tipoC(x.tipo)), H.tag(st[0], st[1]),
              esc(x.precio_total != null ? fmt(x.precio_total, x.moneda) : '—') + (esPreliminar(x) ? ' <span style="font-size:11px;color:#8A8474">no suma</span>' : ''),
              esc(fmt(cobradoPorId[x.id] || 0, x.moneda))];
          })));
      }
      var dos = function (html) { return '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:0 24px">' + html + '</div>'; };
      cuerpo += H.seccion('Datos del contrato', dos(
        // mismos tonos que la tabla de la cadena de arriba (estadoPieza): reabierto = pendiente, borrador = informativo
        H.dato('Estado', c.bloqueado ? H.tag('Firmado', 'ok') : (c.pdf_firmado_path ? H.tag('Reabierto', 'espera') : H.tag('Borrador', 'neutro')), { html: 1 }) +
        H.dato('Precio', c.precio_total != null ? fmt(c.precio_total, c.moneda) : null) +
        (c.nombre_contrato ? H.dato('Nombre', c.nombre_contrato) : '') +
        H.dato('Parcela', c.parcela_codigo) +
        /* «Fecha de firma» solo en firmados: se rellena al CREAR el contrato
           (contexto/suite_lawang.md), así que en un borrador leía como una
           contradicción — «Borrador · Fecha de firma 22 sept». */
        (c.bloqueado ? H.dato('Fecha de firma', c.fecha_firma ? fFecha(c.fecha_firma) : null) : '') +
        H.dato('Creado', fFecha(c.created_at) + (c.creado_por ? ' · ' + c.creado_por : '')) +
        /* Liberación (21-sep-2026): eje aparte del Estado de arriba — un CR
           firmado puede liberarse igual que uno en borrador (el RPC no exige
           lo contrario), así que es un dato propio y no un tag más de Estado. */
        (c.liberado_en ? H.dato('Reserva', H.tag(c.liberado_motivo === 'desistida' ? 'Liberada · comprador desistió' : 'Liberada · plazo vencido', 'mal') +
          '<br><span style="font-size:11.5px;color:#8A8474">' + esc(fFecha(c.liberado_en)) + '</span>', { html: 1 }) : '') +
        /* «Vence el» (22-sep-2026): solo Cartas vivas. Tras el vencimiento hay 3
           días de gracia antes de que el cron libere (aviso a managers el día
           que vence); se dice aquí para que nadie descubra la liberación por
           sorpresa. Sin fecha = la Carta no tiene fecha de pago o validez y el
           cron la salta (no se inventa). */
        (esCartaViva ? H.dato('Vence el', (venceEl
            ? esc(fFecha(venceEl)) + (venceEl < hoyISO ? ' ' + H.tag('Vencida · se libera el ' + fFecha(masDias(venceEl, diasGracia)), 'mal') : (venceEl === hoyISO ? ' ' + H.tag('Vence hoy', 'espera') : ''))
            : '<span style="color:#8A8474">sin plazo (falta fecha de pago o validez en la Carta)</span>') +
          (prorrogas.length ? '<br><span style="font-size:11.5px;color:#8A8474">' + prorrogas.length + ' prórroga(s): ' +
            esc(prorrogas.map(function (x) { return '+' + x.dias + 'd hasta ' + fFecha(x.hasta) + ' (' + (x.quien || '—') + (x.comunicado_al_comprador ? ', comunicada al comprador' : '') + ')'; }).join(' · ')) + '</span>' : ''),
          { html: 1 }) : '')));

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
      // la sección «Cierre de la venta» se añade AL FINAL de la ficha (owner, 22-sep:
      // es de comisiones, no del día a día del contrato) — ver justo antes de pintar.

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
      /* Liberar y Prorrogar van JUNTAS en una sección «Reserva», a dos columnas
         (22-sep-2026, owner): son las dos salidas de la misma situación y se
         leen de un vistazo. Cada una conserva su candado real en el RPC. */
      var colProrrogar = '', colLiberar = '';
      if (puedeVerBoton && esCartaReserva && !c.liberado_en && unidadesReservadas.length >= 1) {
        var esAdminSesion = rolSesion === 'admin' || rolSesion === 'super_admin';
        var topeAlcanzado = prorrogas.length >= maxProrrogasManager && !esAdminSesion;
        colProrrogar = H.nota(venceEl
            ? 'Alarga el plazo desde el vencimiento actual (' + fFecha(venceEl) + '). Máximo ' + maxProrrogasManager + ' prórroga(s) de un sales manager; después, solo admin. Gracia al vencer: ' + diasGracia + ' día(s). Los números se cambian en Ajustes.'
            : 'Sin fecha de pago de la reserva o plazo de validez no hay vencimiento que prorrogar (y el automatismo tampoco la libera).') +
          (venceEl && !topeAlcanzado
            ? '<button type="button" data-lw-prorrogar="1" style="justify-self:start;margin-top:4px;padding:9px 16px;border-radius:10px;border:1px solid #2F5D9E;background:#fff;color:#2F5D9E;font:600 13px \'Neue Kabel\',system-ui;cursor:pointer">Prorrogar reserva</button>'
            : (topeAlcanzado ? H.nota('Ya tiene ' + prorrogas.length + ' prórroga(s): la siguiente solo la puede dar un admin.') : ''));
      }
      if (puedeVerBoton && esCartaReserva && !c.liberado_en && unidadesReservadas.length === 1) {
        colLiberar = H.nota('El comprador desiste: la parcela vuelve a disponible. El contrato queda sellado como liberado y el recibí ya cobrado (no reembolsable) no se toca.') +
          unidadesReservadas.map(function (u) {
            return '<button type="button" data-lw-liberar="' + esc(u.id) + '" style="justify-self:start;margin-top:4px;padding:9px 16px;border-radius:10px;border:1px solid #9E2F26;background:#fff;color:#9E2F26;font:600 13px \'Neue Kabel\',sans-serif;cursor:pointer">Liberar reserva — Parcela ' + esc(u.codigo || '—') + '</button>';
          }).join('<br>');
      } else if (puedeVerBoton && esCartaReserva && !c.liberado_en && unidadesReservadas.length > 1) {
        /* 21-sep-2026, hallazgo de code-review + comprobado contra producción
           (CR00025 tiene HOY 3 parcelas reservadas a la vez): libera_reserva()
           marca `contratos.liberado_en` en cuanto libera la PRIMERA parcela, y
           su guard de idempotencia convierte la llamada para una hermana en un
           ÉXITO MUDO. Mejor no ofrecer botón que uno que miente en el segundo
           clic. Pide una liberación por contrato que el RPC no da hoy. */
        colLiberar = H.nota('Este contrato tiene ' + unidadesReservadas.length + ' parcelas reservadas a la vez (' +
            esc(unidadesReservadas.map(function (u) { return u.codigo || '—'; }).join(', ')) +
            '). Liberar una marcaría el contrato entero como liberado y dejaría el resto sin forma de soltarlas. Este caso no está cubierto todavía — pide a Desarrollo que la libere a mano.');
      }
      if (colProrrogar || colLiberar) {
        var col = function (titulo, html) {
          return '<div style="display:grid;gap:6px;align-content:start;min-width:0"><div style="font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#8A8474">' + titulo + '</div>' + html + '</div>';
        };
        cuerpo += H.seccion('Reserva', (colProrrogar && colLiberar)
          ? '<div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start">' + col('Prorrogar', colProrrogar) + col('Liberar', colLiberar) + '</div>'
          : (colProrrogar ? col('Prorrogar', colProrrogar) : col('Liberar', colLiberar)));
      }
      /* «Deshacer liberación» (22-sep-2026, owner): solo admin. El cron del
         22-sep liberó parcelas con el comprador aún en ello, y una Carta
         liberada no se podía prorrogar. El RPC `deshace_liberacion` devuelve la
         Carta a viva, re-engancha sus parcelas (solo si ninguna la ocupa hoy
         otro contrato vivo — si no, lo dice con nombre) y la prorroga en el
         mismo acto para que no vuelva a estar vencida. */
      if ((rolSesion === 'admin' || rolSesion === 'super_admin') && esCartaReserva && c.liberado_en) {
        cuerpo += H.seccion('Deshacer liberación',
          H.nota('La reserva se liberó (' + esc(c.liberado_motivo === 'desistida' ? 'el comprador desistió' : 'plazo vencido') + ', ' + esc(fFecha(c.liberado_en)) + '). Si el comprador sigue en ello, esto devuelve la Carta a viva, vuelve a enganchar su parcela y la prorroga en el mismo acto. Solo si ninguna otra operación ocupa ya la parcela.') +
          '<button type="button" data-lw-deshacer="1" style="justify-self:start;margin-top:4px;padding:9px 16px;border-radius:10px;border:1px solid #2F5D9E;background:#fff;color:#2F5D9E;font:600 13px \'Neue Kabel\',system-ui;cursor:pointer">Deshacer liberación</button>');
      }

      /* Compradores: el nombre congelado en el contrato siempre; las fichas
         enlazadas (contrato_compradores) se resuelven a nombre en una segunda
         consulta y se pintan en su sección cuando llegan. */
      var vins = r[4].data || [];
      /* Comprador en lenguaje llano (owner, 22-sep): la persona con su ficha
         y su KYC; el nombre congelado del documento solo se enseña si NO
         coincide con la ficha. El rol técnico (adquiriente_1) no se imprime. */
      cuerpo += H.seccion('Comprador' + (vins.length > 1 ? 'es' : ''),
        H.dato('Comprador', c.comprador_nombre) +
        (vins.length ? '<p style="margin:0;font-size:12px;color:#8A8474">Trayendo la ficha de comprador…</p>'
                     : H.nota('Sin ficha de comprador enlazada: solo consta el nombre del documento. Se enlaza desde el generador (pasaporte + email).')), 'compradores');
      // Documentación KYC: desde el 22-sep (owner) ya no es una sección con
      // tabla — el pasaporte es de la persona, no de la venta. Queda como UNA
      // línea dentro de Comprador (cuántos documentos y la caducidad más
      // cercana) con enlace a la ficha, que es donde se gestiona.

      cuerpo += H.seccion('Facturas y recibís (' + fs.length + ')',
        dos(H.dato('Cobrado' + (hayCadena ? ' (este contrato)' : ''), (cobrado != null ? fmt(cobrado, c.moneda) : 'sin dato') + (otrasMon ? ' · incluye ' + otrasMon + ' recibí(s) en otra moneda a valor facial' : '')) +
            (pend != null ? H.dato('Pendiente' + (hayCadena ? ' (este contrato)' : ''), fmt(pend, c.moneda)) : '')) +
        (esPreliminar(c) ? H.nota('Documento preliminar: solo se cobra la señal.') : '') +
        (fs.length ? H.tabla(['Documento', 'Tipo', 'Importe', 'Fecha', 'Estado'], fs.map(function (f) {
          return [H.enlace(URL_FACTURA(f.id), f.numero), esc(tipoDoc(f.tipo)), esc(fmt(f.total, f.moneda)),
            esc(fFecha(f.fecha_emision || f.created_at)),
            f.anulada ? H.tag('Anulada', 'mal') : (f.tipo === 'recibi' ? H.tag('Cobrado', 'ok') : H.tag('Emitida', 'neutro'))];
        })) : H.nota('Sin facturas ni recibís todavía.')));

      cuerpo += H.seccion('Calendario de pagos (' + vs.length + ')',
        vs.length ? H.tabla(['#', 'Concepto', 'Importe', 'Fecha', 'Estado'], vs.map(function (v) {
          return [esc(v.orden != null ? v.orden : ''), esc(v.descripcion || '—'),
            esc(v.monto != null ? fmt(v.monto, c.moneda) : (v.pct != null ? v.pct + ' %' : '—')),
            esc(v.fecha ? fFecha(v.fecha) : 'sin fecha'),
            v.factura_id ? H.tag('Facturado', 'ok') : (v.no_facturar ? '<span style="color:#8A8474">no se factura</span>' : H.tag('Pendiente', 'espera'))];
        })) : H.nota('Sin calendario de pagos registrado.'));

      // Firmas: solo si hay alguna — «Firmas (0) · Sin solicitudes» era ruido;
      // el estado sin firma ya lo dice el «Siguiente paso» del resumen.
      if (fi.length) cuerpo += H.seccion('Firmas (' + fi.length + ')',
        H.tabla(['Firmante', 'Rol', 'Estado', 'Fecha'], fi.map(function (f) {
          var cad = firmaCaducada(f);
          var tono = cad ? 'mal' : f.estado === 'firmado' ? 'ok' : f.estado === 'pendiente' ? 'espera' : 'mal';
          return [esc(f.firmante_nombre || '—'), esc(f.firmante_rol || '—'), H.tag(cad ? 'caducada' : (f.estado || '—'), tono),
            esc(f.firmado_en ? fFecha(f.firmado_en) : (f.expira_en ? 'expira ' + fFecha(f.expira_en) : fFecha(f.creado_en)))];
        })));
      /* COPIAR EL ENLACE DEL FIRMANTE PENDIENTE (23-sep-2026, owner, con el correo
         caído): en una firma en cadena, cuando firma el primero, `firma-submit`
         genera SOLO el enlace del siguiente y lo intenta mandar por correo. Si el
         correo falla, el enlace existe igual (contrato_firmas.enlace_firma) pero
         nadie lo veía: había que regenerarlo a mano. Aquí se copia tal cual, para
         mandarlo por WhatsApp. El enlace NO viaja en la ficha: se pide al pulsar,
         con la RLS de siempre (quien hizo el contrato o el manager del proyecto,
         los mismos que pueden generarlo). */
      var pendFirma = fi.filter(function (f) { return f.estado === 'pendiente' && !firmaCaducada(f); }).slice(-1)[0];
      if (pendFirma) {
        var hechasFirma = fi.filter(function (f) { return f.estado === 'firmado'; }).length;
        cuerpo += H.seccion(hechasFirma ? 'Siguiente firmante' : 'Enlace de firma pendiente',
          H.dato('Le toca a', (pendFirma.firmante_nombre || '—') + (pendFirma.firmante_rol ? ' · ' + pendFirma.firmante_rol.replace('adquiriente_', 'Adquiriente ') : '')) +
          (hechasFirma ? H.dato('Ya han firmado', String(hechasFirma)) : '') +
          (pendFirma.expira_en ? H.dato('El enlace caduca', fFecha(pendFirma.expira_en)) : '') +
          '<button type="button" data-lw-copiar-firma="' + esc(id) + '" style="justify-self:start;padding:9px 16px;border-radius:10px;border:0;background:#104C4F;color:#fff;font:600 13px \'Neue Kabel\',sans-serif;cursor:pointer">Copiar enlace de firma</button>' +
          H.nota('Mándaselo por WhatsApp o por el canal que uséis. Es personal: si lo abre otra persona, firmará en nombre de ' + (pendFirma.firmante_nombre || 'este firmante') + '.'));
      }

      if (c.pdf_firmado_path) {
        cuerpo += H.seccion('Documento firmado',
          (!c.bloqueado ? H.nota('El contrato se reabrió después de firmarse. Este PDF es la versión firmada y es la que vincula a las partes; el texto reabierto no tiene efecto hasta una nueva firma.') : '') +
          '<button type="button" data-lw-pdf="' + esc(c.pdf_firmado_path) + '" style="justify-self:start;padding:9px 16px;border-radius:10px;border:1px solid #c5c8bc;background:#fff;color:#104C4F;font:600 13px \'Neue Kabel\',sans-serif;cursor:pointer">Ver PDF firmado</button>' +
          (c.pdf_firmado_hash ? H.dato('SHA-256', c.pdf_firmado_hash) : ''));
      }
      if (puedeCloser) {
        cuerpo += H.seccion('Cierre de la venta', '<p style="margin:0;font-size:12.5px;color:#8A8474">Trayendo…</p>', 'closer');
      }
      caj.cuerpo.innerHTML = cuerpo;

      if (puedeCloser) {
        var secCloser = caj.cuerpo.querySelector('[data-cajon-sec="closer"] > div');
        if (secCloser) {
          closerDatos(sb).then(function (d) {
            if (!document.body.contains(secCloser)) return; // el cajón ya se cerró
            var actual = d.map[raizCloser.id];
            if (actual === undefined) {
              // sin venta firmada con precio no hay closer que atribuir: la sección sobra
              var secVacia = secCloser.closest('section'); if (secVacia) secVacia.remove();
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

      /* Compradores + KYC inline + «Sus otros contratos» + documentación KYC
         (S13, 22-sep-2026): un solo Promise.all — antes solo resolvía el
         nombre; ahora también el tag de estado KYC (sin salir a Compradores)
         y las operaciones NO emparentadas del mismo comprador (POR_CLIENTE de
         la clásica, líneas 869-881). La documentación va como una línea al
         final de esta misma sección (22-sep, owner) y se pinta aunque no haya
         vins (un documento colgado directo del contrato_id). */
      var clientIds = vins.map(function (v) { return v.client_id; });
      var KYC_ES = { pending: 'Pendiente', submitted: 'En revisión', verified: 'Aprobado', rejected: 'Rechazado' };
      var DOC_ES = { passport: 'Pasaporte', npwp: 'NPWP', visa: 'Visado', proof_of_funds: 'Justificante de fondos', proof_of_address: 'Justificante de domicilio', signed_contract: 'Contrato firmado', other: 'Otro' };
      Promise.all([
        clientIds.length ? sb.from('clients').select('id,full_name,kyc_status').in('id', clientIds) : Promise.resolve({ data: [] }),
        clientIds.length ? sb.from('contrato_compradores').select('client_id,contrato_id').in('client_id', clientIds) : Promise.resolve({ data: [] }),
        sb.from('documents').select('doc_type,uploaded_at,caduca_el,client_id').or(clientIds.length ? 'contrato_id.eq.' + id + ',client_id.in.(' + clientIds.join(',') + ')' : 'contrato_id.eq.' + id)
      ]).then(function (rr) {
        var rc = rr[0], rv2 = rr[1], rd = rr[2];
        var ficha = {}; (rc.error ? [] : (rc.data || [])).forEach(function (k) { ficha[k.id] = k; });
        var sec = caj.cuerpo.querySelector('[data-cajon-sec="compradores"] > div');
        /* La línea de documentación (KYC) que se cuelga al final de Comprador:
           cuántos hay y el que caduca antes. Se calcula aquí y se pone después
           de pintar las fichas (pintaComp), que reescribe la sección. */
        var lineaDocs = '';
        (function () {
          if (rd.error) { lineaDocs = H.dato('Documentación', '<span style="color:#8A8474">no se pudo leer</span>', { html: 1 }); return; }
          var docs = rd.data || [];
          var enlaceFicha = vins.length ? ' · ' + H.enlace('/intranet/v4/compradores/?id=' + encodeURIComponent(vins[0].client_id), 'ver ficha') : '';
          if (!docs.length) {
            lineaDocs = H.dato('Documentación', '<span style="color:#8A8474">sin documentos subidos</span>' + enlaceFicha, { html: 1 });
            return;
          }
          var peor = null;
          docs.forEach(function (d) {
            if (!d.caduca_el) return;
            var dd = Math.round((new Date(d.caduca_el) - new Date()) / 86400000);
            if (peor === null || dd < peor.dd) peor = { dd: dd, tipo: DOC_ES[d.doc_type] || d.doc_type || 'documento' };
          });
          var cad = !peor ? '' : (peor.dd < 0
            ? ' · ' + H.tag(peor.tipo + ' caducado hace ' + (-peor.dd) + ' d', 'mal')
            : (peor.dd <= 60 ? ' · ' + H.tag(peor.tipo + ' caduca en ' + peor.dd + ' d', 'espera') : ''));
          lineaDocs = H.dato('Documentación', docs.length + ' documento' + (docs.length === 1 ? '' : 's') + cad + enlaceFicha, { html: 1 });
        })();
        var ponDocs = function () { if (sec && lineaDocs) sec.insertAdjacentHTML('beforeend', lineaDocs); };
        if (sec && !vins.length) ponDocs();
        if (sec && vins.length) {
          if (rc.error) {
            sec.innerHTML = H.dato('Comprador', c.comprador_nombre) + H.nota('No se pudo leer la ficha de comprador.');
            ponDocs();
          } else {
            var otrosIds = {};
            (rv2.error ? [] : (rv2.data || [])).forEach(function (v2) {
              if (v2.contrato_id === c.id) return;
              (otrosIds[v2.client_id] = otrosIds[v2.client_id] || []).push(v2.contrato_id);
            });
            var idsOtros = [];
            Object.keys(otrosIds).forEach(function (cid) { otrosIds[cid].forEach(function (x) { if (idsOtros.indexOf(x) === -1) idsOtros.push(x); }); });
            var pintaComp = function (porIdOtros) {
              var nombresDoc = String(c.comprador_nombre || '').split(' · ');
              sec.innerHTML = vins.map(function (v, i) {
                var k = ficha[v.client_id] || {};
                var nombreDoc = (nombresDoc[i] || (i === 0 ? c.comprador_nombre : '') || '').trim();
                var difiere = k.full_name && nombreDoc && k.full_name.trim().toUpperCase() !== nombreDoc.toUpperCase();
                var kycTono = k.kyc_status === 'verified' ? 'ok' : (k.kyc_status === 'rejected' ? 'mal' : 'espera');
                var kycTx = KYC_ES[k.kyc_status] || (k.kyc_status || 'pendiente');
                var otros = (otrosIds[v.client_id] || []).map(function (oid) { return porIdOtros[oid]; }).filter(Boolean);
                return H.dato(vins.length > 1 ? 'Comprador ' + (i + 1) : 'Comprador',
                  H.enlace('/intranet/v4/compradores/?id=' + encodeURIComponent(v.client_id), k.full_name || 'Ficha de comprador') +
                  ' ' + H.tag('KYC ' + kycTx, kycTono) +
                  (difiere ? '<br><span style="font-size:11.5px;color:#8A6A34">En el documento figura como «' + esc(nombreDoc) + '»</span>' : '') +
                  (otros.length ? '<br><span style="font-size:11.5px;color:#8A8474">Sus otros contratos: ' +
                    otros.map(function (o) { return H.enlace('/intranet/v4/operaciones/?contrato=' + encodeURIComponent(o.numero), o.numero); }).join(' · ') + '</span>' : ''),
                  { html: 1 });
              }).join('');
              ponDocs();
            };
            if (idsOtros.length) {
              sb.rpc('contratos_equipo').select('id,numero').in('id', idsOtros).then(function (ro) {
                var porIdOtros = {}; (ro.error ? [] : (ro.data || [])).forEach(function (o) { porIdOtros[o.id] = o; });
                pintaComp(porIdOtros);
              });
            } else pintaComp({});
          }
        }
      });
      caj.cuerpo.addEventListener('click', function (ev) {
        var a = ev.target.closest && ev.target.closest('[data-lw-ficha-contrato]');
        if (a) { ev.preventDefault(); var x = porId[a.getAttribute('data-lw-ficha-contrato')]; if (x) fichaContrato(sb, x, opts); return; }
        var bCf = ev.target.closest && ev.target.closest('[data-lw-copiar-firma]');
        if (bCf) {
          ev.preventDefault(); bCf.disabled = true; bCf.textContent = 'Buscando el enlace…';
          sb.from('contrato_firmas').select('enlace_firma,firmante_nombre,expira_en')
            .eq('contrato_id', bCf.getAttribute('data-lw-copiar-firma')).eq('estado', 'pendiente')
            .order('creado_en', { ascending: false }).limit(1).maybeSingle()
            .then(function (rf) {
              bCf.disabled = false; bCf.textContent = 'Copiar enlace de firma';
              if (rf.error) { toastMal('No se pudo leer el enlace: ' + rf.error.message); return; }
              var enl = rf.data && rf.data.enlace_firma;
              if (!enl) { toastMal('Este enlace no se guardó (es anterior al 1-sep): genéralo de nuevo desde «Enviar a firma» en la herramienta de contratos.'); return; }
              var hecho = function () { bCf.textContent = '✓ Enlace copiado'; setTimeout(function () { bCf.textContent = 'Copiar enlace de firma'; }, 2500); };
              if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(enl).then(hecho, function () { window.prompt('Copia el enlace:', enl); });
              } else { window.prompt('Copia el enlace:', enl); }
            });
          return;
        }
        var b = ev.target.closest && ev.target.closest('[data-lw-pdf]');
        if (b) {
          ev.preventDefault(); b.disabled = true; b.textContent = 'Abriendo…';
          // URL firmada de vida corta, como hace la herramienta viva; la policy del bucket decide quién la obtiene
          sb.storage.from('contratos-firmados').createSignedUrl(b.getAttribute('data-lw-pdf'), 300).then(function (u) {
            b.disabled = false; b.textContent = 'Ver PDF firmado';
            if (u.error || !u.data) { toastMal('No se pudo abrir el PDF: ' + (u.error && u.error.message || 'sin URL')); return; }
            window.open(u.data.signedUrl, '_blank', 'noopener');
          });
        }
        var des = ev.target.closest && ev.target.closest('[data-lw-deshacer]');
        if (des) {
          ev.preventDefault();
          if (typeof window.lwVentana !== 'function') { toast('El formulario aún no ha cargado — prueba de nuevo en un segundo.'); return; }
          window.lwVentana('Deshacer liberación — ' + num, [
            { k: '_intro', tipo: 'nota', label: 'La Carta vuelve a viva y su parcela vuelve a "reservada" a su nombre. Como el plazo ya venció, se prorroga en el mismo acto: sin eso el automatismo la liberaría otra vez tras la gracia.' },
            { k: 'dias', label: 'Días de prórroga desde el vencimiento', tipo: 'number', valor: diasDefecto, req: 1, medio: 1, ayuda: 'Un admin puede dar hasta ' + maxDiasAdmin + '.' },
            { k: 'motivo', label: 'Motivo', tipo: 'textarea', req: 1, ayuda: 'Obligatorio: por qué se deshace (el comprador sigue en ello, se liberó por error…).' },
            { k: 'comunicado', label: 'Se lo he comunicado al comprador', tipo: 'check', valor: false }
          ], 'Deshacer liberación', function (vals) {
            var dias = parseInt(vals.dias, 10);
            var motivo = (vals.motivo || '').trim();
            if (!(dias >= 1)) return { error: { message: 'Pon un número de días (mínimo 1).' } };
            if (motivo.replace(/\s+/g, '').length < 6) {
              return { error: { message: 'Cuenta el motivo con algo más de detalle: queda en el histórico del contrato.' } };
            }
            return sb.rpc('deshace_liberacion', { p_contrato_id: c.id, p_motivo: motivo, p_dias: dias, p_comunicado: !!vals.comunicado }).then(function (rr) {
              if (rr.error) return { error: rr.error };
              toast('Liberación deshecha: la reserva vuelve a estar viva y vence el ' + fFecha(rr.data) + '.');
              fichaContrato(sb, c, opts);
              return {};
            });
          }, { sinRecarga: true, sub: 'Deshacer liberación · admin' });
          return;
        }
        var pro = ev.target.closest && ev.target.closest('[data-lw-prorrogar]');
        if (pro) {
          ev.preventDefault();
          if (typeof window.lwVentana !== 'function') { toast('El formulario aún no ha cargado — prueba de nuevo en un segundo.'); return; }
          window.lwVentana('Prorrogar reserva — ' + num, [
            { k: '_intro', tipo: 'nota', label: 'La reserva vence el ' + fFecha(venceEl) + '. Los días se suman a esa fecha. El contrato no se toca: la prórroga queda registrada aparte y el automatismo la respeta.' },
            { k: 'dias', label: 'Días de prórroga', tipo: 'number', valor: diasDefecto, req: 1, medio: 1, ayuda: 'De 1 a ' + maxDiasManager + ' (un admin, hasta ' + maxDiasAdmin + ').' },
            { k: 'motivo', label: 'Motivo', tipo: 'textarea', req: 1, ayuda: 'Obligatorio: por qué se alarga (el comprador está en ello, espera transferencia…), para el histórico del contrato.' },
            { k: 'comunicado', label: 'Se lo he comunicado al comprador', tipo: 'check', valor: false, ayuda: 'Solo constancia. El sistema no avisa al comprador: la prórroga va a su favor y no necesita su firma.' }
          ], 'Prorrogar', function (vals) {
            var dias = parseInt(vals.dias, 10);
            var motivo = (vals.motivo || '').trim();
            if (!(dias >= 1)) return { error: { message: 'Pon un número de días (mínimo 1).' } };
            if (motivo.replace(/\s+/g, '').length < 6) {
              return { error: { message: 'Cuenta el motivo con algo más de detalle: con un par de letras no queda registrado para nadie que lo lea después.' } };
            }
            return sb.rpc('prorroga_reserva', { p_contrato_id: c.id, p_dias: dias, p_motivo: motivo, p_comunicado: !!vals.comunicado }).then(function (rr) {
              if (rr.error) return { error: rr.error };
              toast('Reserva prorrogada: ahora vence el ' + fFecha(rr.data) + '.');
              fichaContrato(sb, c, opts);
              return {};
            });
          }, { sinRecarga: true, sub: 'Prórroga de la reserva' });
          return;
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

  /* ══ Anular / Borrar (S14, 21-sep-2026 — encargo 20260919, revisión previa
     #34) ══ Calcado del comportamiento de /intranet/facturas/, con el mismo
     texto y el mismo `unaFila` (exportado por editores.js: «0 filas» es la
     RLS denegando en silencio, nunca un fallo aparte que se reescriba a mano
     — reference_supabase_grant_manda_antes_que_la_policy). */
  function periodoFiscalTranscurrido(fechaISO) {
    if (!fechaISO) return false;
    var d = new Date(fechaISO + 'T00:00:00');
    if (isNaN(d)) return false;
    var hoy = new Date();
    return d.getFullYear() < hoy.getFullYear() || (d.getFullYear() === hoy.getFullYear() && d.getMonth() < hoy.getMonth());
  }
  function anularDocumento(sb, f0) {
    // Recordatorio en pantalla, nunca automatizado (hard-stop de CLAUDE.md:
    // mandar algo a un tercero real no se hace solo). Solo para factura/recibí
    // ya enviados de verdad — una proforma nunca sale del sistema así.
    var avisoEnviado = !!f0.enviada && (f0.tipo === 'factura' || f0.tipo === 'recibi');
    var avisoPeriodo = periodoFiscalTranscurrido(f0.fecha_emision);
    var cuerpo = '<p>El número no se reutiliza y ya no se podrá editar. La factura queda en el registro marcada como anulada.</p>';
    if (avisoEnviado) cuerpo += '<p><b>Este documento ya se envió</b> — recuerda avisar al comprador de que queda anulado.</p>';
    if (avisoPeriodo) cuerpo += '<p>La fecha de emisión cae en un periodo fiscal ya transcurrido (PPN mensual / LKPM trimestral puede estar ya declarado): conviene avisarlo a Administración.</p>';
    lwConfirmar({ titulo: 'Anular ' + (f0.numero || 'el documento'), cuerpo: cuerpo, confirmar: 'Anular', tono: 'peligro' }).then(function (ok) {
      if (!ok) return;
      sb.from('facturas').update({ anulada: true }).eq('id', f0.id).select('id').then(function (r) {
        var u = (window.LW_V4 && window.LW_V4.unaFila) ? window.LW_V4.unaFila(r) : r;
        if (u.error) { toastMal(lwErrorHumano(u.error, 'No se pudo anular')); return; }
        toast('Documento anulado');
        if (window.lwCierraCajon) window.lwCierraCajon();
        location.reload();
      });
    });
  }
  function borrarDocumento(sb, f0) {
    lwConfirmar({
      titulo: 'Borrar ' + (f0.numero || 'el documento'),
      cuerpo: '<p>Lo normal es <b>anularla</b>: así queda el rastro y la serie no pierde un número.</p>' +
        '<p>Borrarla deja un <b>hueco en la numeración</b> que habrá que explicarle a un contable. No hay papelera.</p>',
      confirmar: 'Borrar de todos modos', cancelar: 'Mejor anularla', tono: 'peligro'
    }).then(function (ok) {
      if (!ok) return;
      sb.from('facturas').delete().eq('id', f0.id).select('id').then(function (r) {
        var u = (window.LW_V4 && window.LW_V4.unaFila) ? window.LW_V4.unaFila(r) : r;
        if (u.error) { toastMal(lwErrorHumano(u.error, 'No se pudo borrar')); return; }
        toast('Documento borrado');
        if (window.lwCierraCajon) window.lwCierraCajon();
        location.reload();
      });
    });
  }
  function fichaFactura(sb, f0) {
    var H = window.lwCajonHtml;
    if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
    var V4 = window.LW_V4 || {};
    // El visor v4 (editores.js), no la herramienta antigua (22-sep-2026, owner:
    // «abrir recibís me lleva a la intranet antigua»). Al cerrarlo, vuelve a
    // esta ficha. Si editores.js aún no ha cargado, el enlace clásico de siempre.
    var acciones = [{ texto: 'Abrir el documento', tono: 'primario', onClick: function () {
      if (window.LW_V4 && typeof window.LW_V4.verDocumento === 'function') window.LW_V4.verDocumento(f0.id, function () { fichaFactura(sb, f0); });
      else location.href = '/intranet/facturas/?id=' + encodeURIComponent(f0.id);
    } }];
    // Editar (21-sep-2026): solo mientras el documento sigue vivo — un
    // congelado (anulado o ya enviado) no se toca, se reemite. El candado de
    // autoría/admin lo decide el propio editor (es_suyo-espejo), no esta
    // ficha: un solo sitio que sepa la regla, igual que el resto de la suite.
    // Una PROFORMA no se edita (22-sep-2026, owner): la genera el contrato al
    // guardarse y la actualiza la firma; se consulta (PDF, email, registro).
    // Una FACTURA anulada se reemite como copia (abrir() del clásico la abría
    // «como borrador nuevo»): mismo contrato, cliente y conceptos, número nuevo.
    if (f0.anulada && f0.tipo === 'factura') {
      acciones.push({ texto: 'Emitir copia', onClick: function () {
        if (window.LW_V4 && window.LW_V4.abrirEditorFactura) window.LW_V4.abrirEditorFactura({ copia_de: f0.id });
        else toastMal('El editor de documentos aún está cargando — prueba de nuevo en un segundo.');
      } });
    }
    // Sin «Editar» (22-sep-2026, owner: «¿por qué Abrir no es editar
    // directamente? son dos modelos y debería ser uno»): «Abrir el documento»
    // abre el editor; si el documento no admite cambios (proforma, anulado,
    // enviado, de otra persona), la misma pantalla sale bloqueada con el
    // motivo arriba. Un solo botón, un solo modelo.
    // UUID y tipo, no el número: ver la nota de fichaContrato (19-sep-2026)
    if (f0.contrato_id && f0.tipo !== 'recibi') acciones.push({ texto: 'Emitir recibí', onClick: function () {
      if (window.LW_V4 && window.LW_V4.abrirEditorRecibi) window.LW_V4.abrirEditorRecibi({ contrato_id: f0.contrato_id, factura_id: f0.id });
      else toastMal('El editor de recibís aún está cargando — prueba de nuevo en un segundo.');
    } });
    // Los botones de la barra de la previa del clásico (22-sep-2026, owner:
    // «te faltan todos los botones de herramientas que había en la intranet
    // antigua»). Los implementa editores.js (misma función en editor, visor
    // y aquí); esta ficha solo los ofrece. Email solo sobre un documento
    // vivo — uno anulado no se manda.
    var V4acc = function (nombre, arg) {
      return function () {
        if (window.LW_V4 && typeof window.LW_V4[nombre] === 'function') window.LW_V4[nombre](arg);
        else toastMal('Las acciones del documento aún están cargando — prueba de nuevo en un segundo.');
      };
    };
    acciones.push({ texto: 'Descargar PDF', onClick: V4acc('imprimirDocumento', f0.id) });
    if (!f0.anulada) acciones.push({ texto: 'Enviar por email', onClick: V4acc('enviarDocumento', f0.id) });
    acciones.push({ texto: '📨 Registro', onClick: V4acc('registroEnvios', f0.id) });
    // Anular (S14): se ofrece a cualquiera que vea el documento — la RLS es la
    // que de verdad decide (autor o admin, con la herramienta 'facturas');
    // esto solo evita ofrecerlo sobre algo que ya no se puede tocar.
    if (!f0.anulada) acciones.push({ texto: 'Anular', tono: 'peligro', onClick: function () { anularDocumento(sb, f0); } });
    // Borrar (S14): desde el 21-sep NI SIQUIERA super_admin borra un documento
    // ya enviado — coincide con la policy que Datos aplica en paralelo
    // (contracts/sql/facturas_enviada_no_se_borra.sql). super_admin lo ve
    // directo (nace ya cumpliendo el resto de la policy); un admin normal
    // necesita ADEMÁS que no esté anulado y que ningún recibí lo tenga
    // aplicado — eso exige preguntar a la base, así que se resuelve aparte
    // (más abajo) y se añade al pie SOLO si la respuesta lo permite. Nunca se
    // pinta un botón que la RLS vaya a rechazar con un 42501 genérico.
    if (!f0.enviada && V4.esSuperAdmin) acciones.push({ texto: 'Borrar', tono: 'peligro', onClick: function () { borrarDocumento(sb, f0); } });
    acciones.push({ texto: 'Cerrar', cerrar: true });
    var caj = window.lwCajon({
      sub: tipoDoc(f0.tipo) + (f0.anulada ? ' · anulada' : ''),
      titulo: f0.numero || '',
      bajoTitulo: (f0.cliente_nombre || '—') + (f0.contrato_numero ? ' · ' + f0.contrato_numero : ''),
      cuerpo: '<p style="margin:0;font-size:13px;color:#8A8474">Trayendo la ficha…</p>',
      acciones: acciones
    });
    // Borrar para un admin normal (no super_admin): solo si nada lo referencia
    // desde `recibi_aplicaciones`, exactamente el resto de la policy. Un
    // vistazo ligero (LIMIT 1, indexado) antes de ofrecer el botón — el que
    // llega tarde no rompe nada porque el pie ya tiene «Cerrar».
    if (!f0.anulada && !f0.enviada && V4.esAdmin && !V4.esSuperAdmin) {
      sb.from('recibi_aplicaciones').select('id').or('factura_id.eq.' + f0.id + ',recibi_id.eq.' + f0.id).limit(1).then(function (r) {
        if (!document.getElementById('lw-cajon')) return;             // la cerraron antes de que llegara
        if (r.error || (r.data && r.data.length)) return;              // referenciado, o no se pudo comprobar: no se ofrece
        var b = document.createElement('button'); b.type = 'button'; b.textContent = 'Borrar';
        b.style.cssText = 'padding:11px 18px;border-radius:10px;font-weight:600;font-size:14px;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;gap:6px;border:1px solid #9E2F26;background:#ffffff;color:#9E2F26;margin-left:auto';
        b.addEventListener('click', function () { borrarDocumento(sb, f0); });
        caj.pie.appendChild(b);
      });
    }
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
      // Reasignar autor (S14): el propio módulo se lo enseña solo al
      // super_admin (window.LW_AUTORIA.puede) — aquí solo se reserva el hueco
      // cuando el script está cargado, para no dejar un <div> vacío al resto.
      // `editable:true` SIEMPRE (corrección de la revisión previa #34: LAW-71
      // deja EXPRESAMENTE que un super_admin reasigne el autor de un
      // documento anulado — es el único cambio que el trigger permite sobre
      // una fila anulada — al revés de lo que decía el plan original).
      if (window.LW_AUTORIA && window.LW_AUTORIA.puede(V4.ficha)) cuerpo += '<div data-lw-autoria-host style="justify-self:start"></div>';
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
      var hostAutoria = caj.cuerpo.querySelector('[data-lw-autoria-host]');
      if (hostAutoria && window.LW_AUTORIA) {
        window.LW_AUTORIA.montar(hostAutoria, {
          sb: sb, ficha: V4.ficha, tabla: 'facturas', filaId: f.id, actual: f.creado_por, editable: true,
          onCambio: function (nuevo) { toast('Autor reasignado a ' + nuevo); f.creado_por = nuevo; }
        });
      }
      caj.cuerpo.addEventListener('click', function (ev) {
        var a = ev.target.closest && ev.target.closest('[data-lw-ficha-contrato]');
        if (a && c) { ev.preventDefault(); fichaContrato(sb, c); return; }
        var b = ev.target.closest && ev.target.closest('[data-lw-just]');
        if (b) {
          ev.preventDefault(); b.disabled = true;
          sb.storage.from('justificantes').createSignedUrl(b.getAttribute('data-lw-just'), 300).then(function (u) {
            b.disabled = false;
            if (u.error || !u.data) { toastMal('No se pudo abrir el justificante: ' + (u.error && u.error.message || 'sin URL')); return; }
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
        q(sb.rpc('contrato_firmas_equipo').select('contrato_id,estado,expira_en').eq('estado', 'pendiente'), 'firmas pendientes'),
        autores(sb)
      ]).then(function (rr) {
          var cs = rr[0], AUT = rr[2] || {};
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
            tr.setAttribute('data-lw-pajar', [c.numero, c.comprador_nombre, c.proyecto_nombre, c.creado_por, nombreAutor(AUT, c.creado_por), c.parcela_codigo, tipoC(c.tipo)].join(' ').toLowerCase());
            var tds = tr.querySelectorAll('td');
            if (tds[6]) tds[6].innerHTML = htmlAutor(AUT, c.creado_por);
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
      Promise.all([
        q(sb.rpc('facturas_equipo').select(CAMPOS_FACTURA).neq('tipo', 'recibi').order('created_at', { ascending: false }).limit(2000), 'facturas', t),
        // Cuánto lleva cobrada cada factura (22-sep-2026, owner): la misma
        // función que usa el recibí para saber qué puede saldar — nunca una
        // segunda forma de restar recibís a facturas.
        vig(sb.rpc('facturas_pendiente_equipo')).then(function (r) { return r.error ? (fallo('pendiente de cobro', r.error), null) : (r.data || []); }),
        autores(sb)
      ]).then(function (rr) {
          var fs = rr[0], hayPend = !!rr[1], pendPor = {}, AUT = rr[2] || {};
          (rr[1] || []).forEach(function (x) { pendPor[x.factura_id] = Number(x.pendiente) || 0; });
          if (!fs) return;
          // 'cobrada' | 'parcial' | 'pendiente' | 'na' (proforma, anulada o sin dato)
          function cobroDe(f) {
            if (f.tipo !== 'factura' || f.anulada || !hayPend) return 'na';
            var p = pendPor[f.id]; if (p == null) p = Number(f.total) || 0;
            var tot = Number(f.total) || 0;
            return p <= 0.005 ? 'cobrada' : (tot - p <= 0.005 ? 'pendiente' : 'parcial');
          }
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
          // KPI «Pendiente de cobro» en el sitio de «Proformas» (22-sep-2026):
          // las proformas son automáticas y no facturan; lo pendiente es lo
          // que de verdad se mira aquí.
          var pendEUR = 0, pendOtras = 0, nPend = 0;
          fs.forEach(function (f) {
            var c = cobroDe(f); if (c !== 'pendiente' && c !== 'parcial') return;
            nPend++; if ((f.moneda || 'EUR') === 'EUR') pendEUR += pendPor[f.id] || 0; else pendOtras++;
          });
          pon2('k-pendiente', hayPend ? fmt(pendEUR, 'EUR') : '—');
          pon2('k-pendiente-pie', hayPend
            ? (nPend + ' factura' + (nPend === 1 ? '' : 's') + ' vigente' + (nPend === 1 ? '' : 's') + ' con saldo pendiente, en euros' + (pendOtras ? ' · +' + pendOtras + ' en otra moneda' : ''))
            : 'no se pudo calcular lo pendiente de cobro');
          var porId = {}; fs.forEach(function (f) { porId[f.id] = f; });
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.facturasLista = porId;

          if (t) {
            var pl = plantillaFilas(t);
            pon2('p-total', String(fs.length)); pon2('p-desde', String(fs.length));

            // Una fila de documento: la usan tanto el listado plano como la
            // vista por contrato (S14) — el marcado y los atributos de filtro
            // son IDÉNTICOS en las dos, solo cambia el orden en que se llaman.
            // `grupo`, si se pasa, marca de qué cabecera de contrato cuelga —
            // lo necesita `sincronizaCabecerasGrupo()` para saber si a esa
            // cabecera le queda alguna fila visible tras filtrar/buscar.
            function pintaFilaDoc(f, grupo) {
              var est = estadoDoc(f);
              fila(pl, [f.numero, tipoDoc(f.tipo), f.cliente_nombre || '—', f.contrato_numero || '—', f.proyecto_nombre || '—',
                fmt(f.total, f.moneda), '', fFecha(f.fecha_emision || f.created_at), '', '', '']);
              var tr = pl.tbody.lastElementChild;
              tr.setAttribute('data-lw-fila', ''); tr.setAttribute('data-lw-id', f.id);
              tr.setAttribute('data-lw-tipo', f.tipo === 'proforma' ? 'proforma' : 'factura');
              tr.setAttribute('data-lw-estado', f.anulada ? 'anulada' : (f.enviada ? 'enviada' : 'emitida'));
              var cobro = cobroDe(f); tr.setAttribute('data-lw-cobro', cobro);
              tr.setAttribute('data-lw-pajar', [f.numero, f.cliente_nombre, f.contrato_numero, f.proyecto_nombre, f.creado_por, nombreAutor(AUT, f.creado_por)].join(' ').toLowerCase());
              if (grupo) tr.setAttribute('data-lw-grupo', grupo);
              var tds = tr.querySelectorAll('td');
              if (tds[6]) {
                var tot = Number(f.total) || 0, pend = pendPor[f.id] == null ? tot : pendPor[f.id];
                tds[6].innerHTML = cobro === 'cobrada' ? pill('Cobrada', 'ok')
                  : cobro === 'pendiente' ? pill('Sin cobrar', 'espera')
                  : cobro === 'parcial' ? pill('Parcial', 'espera') + '<div style="margin-top:3px;font-size:11.5px;color:#75786e;white-space:nowrap">' +
                      esc(fmt(tot - pend, f.moneda)) + ' de ' + esc(fmt(tot, f.moneda)) + '</div>'
                  : '<span style="color:#BEB3A5">—</span>';
              }
              if (tds[8]) tds[8].innerHTML = htmlAutor(AUT, f.creado_por);
              if (tds[9]) tds[9].innerHTML = pill(est[0], est[1]);
              if (tds[10]) tds[10].innerHTML = ABRIR;
              tr.style.cursor = 'pointer';
            }
            function pintaListado() { pl.tbody.innerHTML = ''; fs.forEach(function (f) { pintaFilaDoc(f); }); }
            /* Vista por contrato (S14, 21-sep-2026): agrupa lo que este
               listado YA tiene (facturas+proformas — los recibís viven en su
               propia pantalla), solo lectura. Calco simplificado de
               `pintarPorContrato()` de la clásica: aquí no se cruza con
               recibís, así que no hay «cobrado»/«sin recibí» que calcular —
               solo cuántos documentos y de quién, que es lo único que este
               listado puede afirmar por sí solo. Un solo cajón «Sin
               contrato», nunca uno por cliente: sumarlos daría un total de un
               conjunto que no es un conjunto (mismo motivo que la clásica,
               26-ago-2026). */
            function pintaPorContrato() {
              pl.tbody.innerHTML = '';
              var grupos = {}, orden = [];
              fs.forEach(function (f) {
                var clave = f.contrato_id || '__sin_contrato__';
                if (!grupos[clave]) {
                  grupos[clave] = { sinContrato: !f.contrato_id, numero: f.contrato_numero, cliente: f.cliente_nombre, proyecto: f.proyecto_nombre, docs: [] };
                  orden.push(clave);
                }
                grupos[clave].docs.push(f);
              });
              orden.forEach(function (k) {
                var g = grupos[k];
                var n = g.docs.length + (g.docs.length === 1 ? ' documento' : ' documentos');
                var etiqueta = g.sinContrato ? 'Sin contrato' : (g.numero || '—');
                var sub = g.sinContrato ? (n + ' · no son un contrato: no se suman entre sí')
                  : ((g.cliente || 'sin cliente') + ' · ' + (g.proyecto || 'sin proyecto') + ' · ' + n);
                pl.tbody.insertAdjacentHTML('beforeend',
                  '<tr data-lw-grupo-cab="' + esc(k) + '" style="background:#F5F4EE"><td colspan="11" style="padding:9px 20px;font:700 12.5px \'Neue Kabel\',sans-serif;color:#104C4F">' +
                  esc(etiqueta) + ' <span style="margin-left:8px;font-weight:500;font-size:11.5px;color:#8A8474">' + esc(sub) + '</span></td></tr>');
                g.docs.forEach(function (f) { pintaFilaDoc(f, k); });
              });
            }
            /* Hallazgo del code-review de esta misma subtarea (21-sep-2026):
               `aplicaFiltros` solo esconde `tr[data-lw-fila]` — las cabeceras
               de grupo se quedaban SIEMPRE visibles aunque el chip/buscador
               dejara el grupo entero sin una sola fila debajo (cabecera
               huérfana con un «3 documentos» que ya no hay). Se corrige aquí,
               sin tocar `aplicaFiltros` (la usan otras 6 pantallas): tras cada
               filtrado, una cabecera se esconde si NINGUNA de sus filas
               (mismo `data-lw-grupo`) sigue visible. Solo aplica en la vista
               agrupada — en «Listado» no hay cabeceras que sincronizar. */
            function sincronizaCabecerasGrupo() {
              var visibles = {};
              Array.prototype.forEach.call(pl.tbody.querySelectorAll('tr[data-lw-grupo]'), function (tr) {
                if (tr.style.display !== 'none') visibles[tr.getAttribute('data-lw-grupo')] = true;
              });
              Array.prototype.forEach.call(pl.tbody.querySelectorAll('tr[data-lw-grupo-cab]'), function (cab) {
                cab.style.display = visibles[cab.getAttribute('data-lw-grupo-cab')] ? '' : 'none';
              });
            }
            pintaListado();
            pl.tbody.addEventListener('click', function (ev) {
              var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
              ev.stopPropagation(); var f = porId[tr.getAttribute('data-lw-id')]; if (f) fichaFactura(sb, f);
            });
            // Proformas FUERA por defecto (22-sep-2026, owner): son automáticas
            // (176 de 187 las crea el contrato) y duplicaban el ruido del
            // listado. El chip inicial es «Facturas»; «Proformas» y «Todos»
            // siguen a un clic.
            var estado = { tipo: { attr: 'tipo', valor: 'factura' } }, texto = '', vista = 'lista';
            var aplicar = function () {
              aplicaFiltros(pl.tbody, estado, ['tipo', 'estado', 'cobro'], texto, function (n) { pon2('p-desde', String(n)); });
              sincronizaCabecerasGrupo();
            };
            var cuenta = function (f) { return fs.filter(f).length; };
            chipsReales(document.querySelector('[data-lw-chips="tipo"]'), 'tipo', [
              { clave: 'factura', texto: 'Facturas', n: nFac },
              { clave: 'proforma', texto: 'Proformas', n: nPro },
              { clave: '*', texto: 'Todos', n: fs.length }], estado, aplicar);
            chipsReales(document.querySelector('[data-lw-chips="cobro"]'), 'cobro', [
              { clave: '*', texto: 'Todo', n: null },
              { clave: 'pendiente', texto: 'Sin cobrar', n: cuenta(function (f) { return cobroDe(f) === 'pendiente'; }) },
              { clave: 'parcial', texto: 'Parciales', n: cuenta(function (f) { return cobroDe(f) === 'parcial'; }) },
              { clave: 'cobrada', texto: 'Cobradas', n: cuenta(function (f) { return cobroDe(f) === 'cobrada'; }) }], estado, aplicar);
            chipsReales(document.querySelector('[data-lw-chips="estado"]'), 'estado', [
              { clave: '*', texto: 'Todas', n: fs.length },
              { clave: 'emitida', texto: 'Emitidas', n: cuenta(function (f) { return !f.anulada && !f.enviada; }) },
              { clave: 'enviada', texto: 'Enviadas', n: cuenta(function (f) { return !f.anulada && f.enviada; }) },
              { clave: 'anulada', texto: 'Anuladas', n: nFacAnu + nProAnu }], estado, aplicar);
            buscadorDe(aplicar, function (v) { texto = v; });
            aplicar();   // el chip inicial «Facturas» filtra desde el primer pintado

            var vistaBox = document.querySelector('[data-lw-vista]');
            if (vistaBox) vistaBox.addEventListener('click', function (ev) {
              var b = ev.target.closest && ev.target.closest('[data-lw-vista-btn]'); if (!b) return;
              ev.stopPropagation();
              var modo = b.getAttribute('data-lw-vista-btn');
              if (modo === vista) return;
              vista = modo;
              Array.prototype.forEach.call(vistaBox.querySelectorAll('button'), function (x) {
                var on = x === b;
                x.classList.toggle('bg-deep-lagoon', on); x.classList.toggle('text-on-secondary', on); x.classList.toggle('shadow-sm', on);
                x.classList.toggle('bg-surface-container', !on); x.classList.toggle('text-on-surface-variant', !on);
              });
              if (vista === 'contrato') pintaPorContrato(); else pintaListado();
              aplicar();
            });
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
      Promise.all([
        q(sb.rpc('facturas_equipo').select(CAMPOS_FACTURA).eq('tipo', 'recibi').order('created_at', { ascending: false }).limit(2000), 'recibís', t),
        // Qué factura(s) salda cada recibí (22-sep-2026, owner): es la razón de
        // ser del documento y no estaba en la tabla. La RLS de
        // recibi_aplicaciones deja ver las de los recibís que uno ve.
        vig(sb.from('recibi_aplicaciones').select('recibi_id,factura_id,importe_aplicado')).then(function (r) { return r.error ? (fallo('facturas saldadas', r.error), []) : (r.data || []); }),
        vig(sb.rpc('facturas_equipo').select('id,numero').eq('tipo', 'factura')).then(function (r) { return r.error ? [] : (r.data || []); }),
        autores(sb)
      ]).then(function (rr) {
          var rs = rr[0]; if (!rs) return;
          var AUT = rr[3] || {};
          var numFac = {}; rr[2].forEach(function (x) { numFac[x.id] = x.numero; });
          var saldaDe = {}; rr[1].forEach(function (a) { (saldaDe[a.recibi_id] = saldaDe[a.recibi_id] || []).push(numFac[a.factura_id] || 'factura fuera de tu alcance'); });
          var justifDe = function (r) { return Array.isArray(r.justificantes) && r.justificantes.length ? r.justificantes : (r.justificante_path ? [{ path: r.justificante_path, nombre: '' }] : []); };
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
              var salda = (saldaDe[r.id] || []).join(' · ');
              fila(pl, [r.numero, r.contrato_numero || '—', salda || '—', r.cliente_nombre || '—', r.proyecto_nombre || '—', fmt(r.total, r.moneda),
                nj ? nj + ' adjunto' + (nj === 1 ? '' : 's') : 'sin justificante', fFecha(r.fecha_emision || r.created_at), '', '', '']);
              var tr = pl.tbody.lastElementChild;
              tr.setAttribute('data-lw-fila', ''); tr.setAttribute('data-lw-id', r.id);
              tr.setAttribute('data-lw-moneda', m);
              tr.setAttribute('data-lw-estado', r.anulada ? 'anulado' : 'emitido');
              tr.setAttribute('data-lw-just', nj ? '1' : '0');
              tr.setAttribute('data-lw-pajar', [r.numero, r.cliente_nombre, r.contrato_numero, r.proyecto_nombre, salda, r.creado_por, nombreAutor(AUT, r.creado_por)].join(' ').toLowerCase());
              var tds = tr.querySelectorAll('td');
              if (tds[6] && !nj && !r.anulada) tds[6].innerHTML = pill('sin justificante', 'espera');
              if (tds[8]) tds[8].innerHTML = htmlAutor(AUT, r.creado_por);
              if (tds[9]) tds[9].innerHTML = pill(r.anulada ? 'Anulado' : (r.enviada ? 'Enviado' : 'Emitido'), est[1]);
              // «Ver el justificante desde la fila» (22-sep-2026, owner): con uno,
              // se abre; con varios, la ficha los lista todos.
              if (tds[10]) tds[10].innerHTML = (nj ? '<span data-lw-ver-just="' + esc(r.id) + '" style="font:600 12px \'Neue Kabel\',sans-serif;color:#104C4F;text-decoration:underline;margin-right:12px">Justificante</span>' : '') + ABRIR;
              tr.style.cursor = 'pointer';
            });
            pl.tbody.addEventListener('click', function (ev) {
              var vj = ev.target.closest && ev.target.closest('[data-lw-ver-just]');
              if (vj) {
                ev.stopPropagation();
                var rj = porId[vj.getAttribute('data-lw-ver-just')], js = rj ? justifDe(rj) : [];
                if (!js.length) return;
                if (js.length > 1) { fichaFactura(sb, rj); return; }
                sb.storage.from('justificantes').createSignedUrl(js[0].path, 300).then(function (u) {
                  if (u.error || !u.data) return toastMal('No se pudo abrir el justificante' + (u.error ? ': ' + u.error.message : ''));
                  window.open(u.data.signedUrl, '_blank', 'noopener');
                });
                return;
              }
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
        q(sb.rpc('compradores_directorio').select('id,full_name,email,phone,nationality,tipo,kyc_status,propietario,created_at').order('created_at', { ascending: false }), 'compradores', t),
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
        pon2('k-lista-pie', cs.length + (cs.length === 1 ? ' comprador' : ' compradores') + ' · pulsa uno para abrir su ficha');

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
            /* La cuota de reserva ES exigible (Legal ALTA, 12-ago-2026) y vive
               en el jsonb del contrato: se pide al abrir la ficha, solo de estos
               contratos (paridad S6, 23-sep-2026 — antes decía «se ve en la
               clásica»). `data-cuota-reserva` lo rellena pintaFicha. */
            return H.nota('Solo tiene Carta(s) de Reserva: el precio final de la villa lo fija el contrato que la sustituya. Lo exigible hoy es la cuota de reserva.') +
              H.dato('Cuota de reserva', '<span data-cuota-reserva="' + esc(suyos.map(function (x) { return x.id; }).join(',')) + '" style="color:#75786e">Cargando…</span>', { html: 1 }) +
              H.dato('Cobrado', fmt(cobrado, moneda));
          }
          var precio = sumables.reduce(function (a, x) { return a + (Number(x.precio_total) || 0); }, 0);
          var pendiente = precio - cobrado;
          /* Avance por proyecto (paridad S6): con contratos en más de un
             proyecto, la cifra total no dice cuál va retrasado. Mismo cálculo
             que la suma de abajo, partido por proyecto. */
          var porProy = {};
          sumables.forEach(function (x) {
            var k = x.proyecto_nombre || '—';
            var p = porProy[k] = porProy[k] || { precio: 0, cobrado: 0 };
            p.precio += Number(x.precio_total) || 0;
            p.cobrado += cobId[x.id] || 0;
          });
          var nombresProy = Object.keys(porProy);
          var tablaProy = nombresProy.length > 1
            ? '<div style="margin-top:10px">' + H.tabla(['Proyecto', 'Precio', 'Cobrado', 'Pendiente'], nombresProy.map(function (k) {
                var p = porProy[k];
                return [esc(k), esc(fmt(p.precio, moneda)), esc(fmt(p.cobrado, moneda)), esc(fmt(p.precio - p.cobrado, moneda))];
              })) + '</div>'
            : '';
          return '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;text-align:center">' +
            ['Precio pactado', 'Cobrado', 'Pendiente'].map(function (etq, i) {
              var v = [precio, cobrado, pendiente][i];
              var color = i === 1 ? '#3F5230' : (i === 2 && pendiente > 0 ? '#9E2F26' : '#2E3437');
              return '<div><div style="font-size:10.5px;letter-spacing:.08em;text-transform:uppercase;color:#75786e">' + etq + '</div>' +
                '<div style="font-size:18px;font-weight:700;color:' + color + '">' + esc(fmt(v, moneda)) + '</div></div>';
            }).join('') + '</div>' +
            '<p style="margin:6px 0 0;font-size:11.5px;color:#75786e">Solo cuenta como cobrado el recibí — una factura o proforma es lo que se debe, no lo pagado.' +
            (sumables.length !== suyos.length ? ' El precio no cuenta las Cartas de Reserva.' : '') + '</p>' + tablaProy;
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
              toastMal('No se pudo leer la ficha completa: se enseña lo que hay en el listado.');
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
            H.seccion('Contratos (' + vins.length + ')', contratos, 'contratos') +
            H.seccion('Estado de cuentas', seccionEstadoCuentas(vins, H), 'cuentas') +
            H.seccion('Facturas', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'facturas') +
            H.seccion('Documentación KYC', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'docs') +
            H.seccion('Registro de envíos', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'envios') +
            H.seccion('Soporte', '<p style="margin:0;font-size:12.5px;color:#75786e">Cargando…</p>', 'soporte') +
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
                  if (r.error) { toastMal(lwErrorHumano(r.error)); return; }
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
          /* LA FICHA DICE LO QUE NO ENSEÑA — 22-sep-2026, decisión del owner.
             Dos closers pueden tener contrato con la misma persona; `vins` solo
             trae los que la RLS te deja ver, y el «Estado de cuentas» de arriba
             los suma como si fueran todos. `comprador_contratos_resumen()` da
             TODOS sus contratos (tipo, proyecto, autor, firmado; sin importes ni
             número) y marca cuáles ves. Se pide DESPUÉS de abrir: es una nota,
             no un requisito. Calcado de /intranet/compradores/. */
          sb.rpc('comprador_contratos_resumen', { p_client_id: c2.id }).then(function (r) {
            if (r.error) { console.warn('[v4 datos] comprador_contratos_resumen', r.error); return; }
            var todos = r.data || [];
            var ajenos = todos.filter(function (x) { return !x.visible; });
            if (!ajenos.length || !cj.cuerpo) return;
            var sc = cj.cuerpo.querySelector('[data-cajon-sec="contratos"] > div');
            if (sc) {
              var lis = ajenos.map(function (x) {
                return '<li>' + esc(tipoC(x.tipo)) + ' · ' + esc(x.proyecto_nombre || '—') + ' · de <b>' +
                  esc(nombreEquipo[String(x.autor || '').toLowerCase()] || x.autor || 'nadie (sin autor)') + '</b> · ' +
                  (x.bloqueado ? H.tag('Firmado', 'ok') : H.tag('Sin firmar', 'neutro')) + '</li>';
              }).join('');
              sc.insertAdjacentHTML('beforeend',
                H.nota('Esta persona tiene <b>' + todos.length + '</b> contratos en total; aquí ves <b>' + (todos.length - ajenos.length) + '</b>. ' +
                       'Los que no ves son de otro comercial: sus cifras no entran en esta ficha.', true) +
                '<ul style="margin:0 0 0 18px;padding:0;font-size:12.5px;color:#2E3437;display:grid;gap:4px">' + lis + '</ul>' +
                (ajenos.some(function (x) { return x.bloqueado; })
                  ? H.nota('Un contrato firmado, sea de quien sea, congela esta ficha: desde entonces solo la corrige un administrador.')
                  : ''));
            }
            var h4 = cj.cuerpo.querySelector('[data-cajon-sec="cuentas"] > h4');
            if (h4) h4.textContent = 'Estado de cuentas de tus contratos';
            var scu = cj.cuerpo.querySelector('[data-cajon-sec="cuentas"] > div');
            if (scu) scu.insertAdjacentHTML('afterbegin', H.nota('Solo suma tus contratos: los de otros comerciales no entran en estas cifras.'));
          });

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
                  if (r.error) { toastMal(lwErrorHumano(r.error, 'No se pudo traspasar')); return; }
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

          /* ── Paridad S6 con /intranet/compradores/ (23-sep-2026): lo que la
             primera pasada dejó fuera a propósito. Todo se pide al ABRIR y
             solo de esta persona, como el resto de secciones del cajón. */

          // Cuota de reserva: solo si seccionEstadoCuentas dejó el hueco (solo Cartas)
          var huecoCuota = cj.cuerpo.querySelector('[data-cuota-reserva]');
          if (huecoCuota) {
            var preIds = huecoCuota.getAttribute('data-cuota-reserva').split(',').filter(Boolean);
            sb.rpc('contratos_equipo').select('id,numero,precio_total,moneda,precio_reserva:datos->fields->>precio_reserva').in('id', preIds).then(function (rc) {
              if (rc.error) { huecoCuota.textContent = 'no se pudo leer'; huecoCuota.style.color = '#9E2F26'; return; }
              huecoCuota.style.color = '';
              // sin cuota fijada, el precio del documento como aproximación — mismo criterio que la clásica
              huecoCuota.textContent = (rc.data || []).map(function (x) {
                var imp = x.precio_reserva ? x.precio_reserva + ' ' + (x.moneda || '') : fmt(Number(x.precio_total) || 0, x.moneda || 'EUR') + ' (sin cuota fijada: importe del documento)';
                return (x.numero || 'sin nº') + ': ' + imp;
              }).join(' · ') || '—';
            });
          }

          /* Registro de envíos: `correos_enviados` de SUS contratos y facturas.
             Desde el 23-sep la RLS solo deja leer los envíos de contratos que
             la sesión puede ver (Legal, 19-sep) — la condición que se puso
             para enseñarlo aquí. */
          (function () {
            if (!ids.length) return pinta('envios', H.nota('Sin contratos enlazados: no hay envíos que atarle.'));
            sb.from('correos_enviados').select('para,asunto,via,enviado_por,enviado_en,contrato_id,factura_id')
              .in('contrato_id', ids).order('enviado_en', { ascending: false }).limit(200).then(function (re) {
                if (re.error) return pinta('envios', H.nota('No se pudo leer el registro de envíos: ' + re.error.message));
                var filas = re.data || [];
                if (!filas.length) return pinta('envios', H.nota('Sin correos registrados para sus contratos. El registro existe desde el 18-ago-2026: los envíos anteriores no dejaron rastro.'));
                var via = function (v) { return typeof lwViaCorreo === 'function' ? lwViaCorreo(v) : (v || '—'); };
                pinta('envios', H.tabla(['Cuándo', 'Contrato', 'Para', 'Vía', 'Quién'], filas.map(function (x) {
                  var k = porC[x.contrato_id];
                  return [esc(fFecha(x.enviado_en)), esc((k && k.numero) || '—') + (x.factura_id ? '<div style="font-size:11px;color:#75786e">con factura</div>' : ''),
                    esc(x.para || '—'), esc(via(x.via)), esc(x.enviado_por || 'Automático')];
                })));
              });
          })();

          /* Soporte: un RESUMEN (cuántos abiertos, el último mensaje) y el
             enlace a su bandeja en Soporte v4 — el hilo completo vive allí; repetirlo
             aquí sería la duplicación que ya se cerró el 1-sep en la clásica. */
          Promise.all([
            sb.from('mensajes_comprador').select('de,texto,creado_en').eq('client_id', c2.id).order('creado_en', { ascending: false }).limit(1),
            sb.from('hilo_soporte').select('estado,actualizado_en').eq('client_id', c2.id)
          ]).then(function (rs) {
            if (rs[0].error || rs[1].error) return pinta('soporte', H.nota('No se pudo leer Soporte: ' + (rs[0].error || rs[1].error).message));
            var ultimo = (rs[0].data || [])[0], hilos = rs[1].data || [];
            if (!ultimo && !hilos.length) return pinta('soporte', H.nota('Sin mensajes desde el área de clientes.'));
            var abiertos = hilos.filter(function (h) { return h.estado === 'abierto'; }).length;
            pinta('soporte',
              '<p style="margin:0 0 6px;font-size:12.5px">' + (abiertos ? H.tag(abiertos + (abiertos === 1 ? ' abierto' : ' abiertos'), 'espera') : H.tag('Todo resuelto', 'ok')) +
              ' <span style="color:#75786e;margin-left:6px">' + hilos.length + ' ticket' + (hilos.length === 1 ? '' : 's') + ' en total' + (ultimo ? ' · último mensaje ' + esc(fFecha(ultimo.creado_en)) : '') + '</span></p>' +
              (ultimo ? '<p style="margin:0 0 8px;font-size:13px;color:#2E3437">' + esc((ultimo.de === 'equipo' ? 'Equipo: ' : 'Comprador: ') + ultimo.texto) + '</p>' : '') +
              H.enlace('/intranet/v4/soporte/?id=' + encodeURIComponent(c2.id), 'Ver sus tickets en Soporte →'));
          });

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
            /* Con un contrato FIRMADO, su documentación KYC solo la retira un super
               admin (trigger trg_documents_kyc_firmado, 23-sep-2026, Legal): no se
               ofrece un botón que la base va a rechazar. Mira los contratos que
               la sesión ve; la base mira todos. */
            var puedeBorrarDoc = window.LW_V4.esSuperAdmin || (window.LW_V4.esAdmin &&
              !vins.some(function (v) { return porC[v.contrato_id] && porC[v.contrato_id].bloqueado; }));
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
                    (puedeBorrarDoc ? '<button type="button" data-doc-borrar="' + esc(d.id) + '" style="margin-left:6px;padding:4px 10px;border-radius:999px;border:1px solid #9E2F26;background:#fff;font-size:12px;cursor:pointer;color:#9E2F26;font-weight:600">Borrar</button>' : '');
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
                /* Alerta KYC (paridad S6, 23-sep-2026) — misma regla que
                   `alerta()` de la clásica: el PEOR documento con caducidad
                   manda. Caducado invalida el KYC; a 60 días o menos, avisa. */
                var peor = null;
                ds.forEach(function (d) {
                  if (!d.caduca_el) return;
                  var dd = Math.round((new Date(d.caduca_el + 'T00:00:00') - hoy) / 86400000);
                  if (peor === null || dd < peor) peor = dd;
                });
                var alertaKyc = peor === null ? ''
                  : peor < 0 ? H.nota('Hay un documento caducado: el KYC de esta persona no vale hasta renovarlo.')
                  : peor <= 60 ? H.nota('Un documento caduca en ' + peor + ' día' + (peor === 1 ? '' : 's') + ': conviene pedir el nuevo ya.')
                  : '';
                pinta('docs', alertaKyc + tablaDocs + formSubida);

                /* Bucket privado: enlace temporal de 5 minutos, nunca una URL fija
                   — igual que la herramienta clásica. */
                cj.cuerpo.querySelectorAll('[data-doc-path]').forEach(function (b) {
                  b.addEventListener('click', function () {
                    b.disabled = true;
                    sb.storage.from('kyc').createSignedUrl(b.getAttribute('data-doc-path'), 300).then(function (ru) {
                      b.disabled = false;
                      if (ru.error || !(ru.data && ru.data.signedUrl)) return toastMal('No se pudo abrir el documento' + (ru.error ? ': ' + ru.error.message : ''));
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
                    if (up.error) { bSub.disabled = false; bSub.textContent = 'Subir documento'; toastMal(lwErrorHumano(up.error, 'No se pudo subir')); return; }
                    // el fichero ya subió: si el insert falla no se reintenta el upload, se avisa igual
                    sb.from('documents').insert({ client_id: c2.id, doc_type: tipoDoc, storage_path: path, status: 'pending', caduca_el: caduca }).then(function (ins) {
                      bSub.disabled = false; bSub.textContent = 'Subir documento';
                      if (ins.error) { toastMal(lwErrorHumano(ins.error, 'El fichero se subió pero no se pudo registrar en la ficha')); return; }
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
                window.open('/intranet/v4/soporte/?id=' + encodeURIComponent(c2.id), '_blank', 'noopener');
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
        /* Sin tope de filas (23-sep-2026). Había `slice(0, 200)` con un pie que
           decía «usa el buscador para el resto», pero el buscador filtra las
           filas PINTADAS: la ficha 201 no la encontraba nadie. Con 197 fichas
           ese día faltaban tres altas para que el buscador empezara a mentir. */
        cs.forEach(function (c2) {
          var d = deCliente[c2.id];
          fila(pl, [
            c2.full_name,
            (c2.email || '—') + (c2.nationality ? ' · ' + c2.nationality : ''),
            c2.tipo === 'empresa' ? 'Empresa' : 'Persona física',
            d ? Object.keys(d.proys).join(' · ') || (d.n + (d.n === 1 ? ' contrato' : ' contratos')) : '—',
            d && d.inv ? fmt(d.inv, 'EUR') : (d && d.otras ? 'otra moneda' : '—'),
            d && d.inv ? fmt(d.pag, 'EUR') + ' · ' + Math.round(d.pag / d.inv * 100) + '%' : (d ? fmt(d.pag, 'EUR') : '—'),
            (KYC[c2.kyc_status || 'pending'] || [c2.kyc_status])[0],
            '',
            ''
          ]);
          var tr = pl.tbody.lastElementChild;
          // quién dio de alta la ficha (`propietario`, un email) — el mismo resolutor que el resto de la v4
          var tdAlta = tr.querySelectorAll('td')[7];
          if (tdAlta) tdAlta.innerHTML = htmlAutor(nombreEquipo, c2.propietario);
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

        /* El buscador de la cabecera: nombre, email, nacionalidad o teléfono.
           El teléfono se compara por DÍGITOS (`telefonoCasa`, compradores.js):
           el mismo móvil está guardado como «+34 687 95 95 09» y como
           «+34687959509», y comparar el texto tal cual no encontraba al
           comprador tecleando 687959509 (closer, 23-sep-2026). */
        var busca = document.getElementById('buyerSearch');
        if (busca) busca.addEventListener('input', function () {
          var qq = busca.value.trim().toLowerCase();
          pl.tbody.querySelectorAll('tr[data-id]').forEach(function (tr) {
            var c2 = porId[tr.getAttribute('data-id')] || {};
            var pajar = [c2.full_name, c2.email, c2.nationality, c2.phone].join(' ').toLowerCase();
            var casa = !qq || pajar.indexOf(qq) !== -1 || (typeof telefonoCasa === 'function' && telefonoCasa(c2.phone, qq));
            tr.style.display = casa ? '' : 'none';
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
      /* REHECHA el 22-sep-2026 a petición del owner («el panel de operaciones
         de la v4 no tiene mucho sentido o no lo entiendo»). Medido en
         producción ANTES de tocar nada: 261 filas de las que 96 eran contratos
         HIJOS («cuelga de…»), una tabla de 10 columnas y 2.230 px dentro de
         una caja de 632 (el dinero y la situación quedaban fuera de pantalla),
         un panel lateral «Expediente» que duplicaba la ficha en cajón y traía
         dos botones que el owner acababa de retirar («Emitir recibí», «Abrir
         proforma»), y el vocabulario del mockup (Listado transaccional,
         Desembolsado, Estructura contractual…).

         Ahora:
         · UNA FILA POR OPERACIÓN — la raíz y su cadena (Carta → Bloqueo →
           Construcción), exactamente como la clásica /intranet/operaciones/.
         · Carga con `lwOperacionesCargar` (operaciones-cuentas.js), el MISMO
           cargador que la clásica: sin una segunda lista de consultas que se
           separe sola (Regla 0). Dinero por `cuentaGrupo`, etapa por
           `etapaOperacion` — las dos compartidas.
         · Tabla a todo el ancho, sin panel lateral: la ficha es el cajón
           compartido (fichaContrato), que ya trae la cadena, los cobros, el
           calendario, la reserva y el cierre de la venta.
         · KPIs y totales sobre LO QUE SE VE (filtro y buscador), como el
           resumen de la clásica: una sola cifra que cambia con el filtro, no
           dos que se contradicen. */
      var T = function (s) { return (typeof lwT === 'function') ? lwT(s) : s; };
      var caja = document.getElementById('lw-ops-caja');
      var tbody = document.getElementById('lw-ops-lista');
      if (!tbody) return;
      if (typeof lwOperacionesCargar !== 'function' || typeof cuentaGrupo !== 'function' || typeof etapaOperacion !== 'function') {
        fallo('operaciones', 'operaciones-cuentas.js no cargó (Regla 0: el cargador es el compartido)', caja);
        return;
      }
      var avisos = [];
      vig(lwOperacionesCargar(sb, function (m) { avisos.push(m); })).then(function (r) {
        var OPS = r.ops || [];
        avisos.forEach(function (m) { bandaNota(m, '#8A6A34'); });
        /* Recorte por tope: se DICE en fijo (mismo criterio que la clásica):
           unos totales parciales que no avisan son un número que miente. */
        if (r.recortes && r.recortes.length) {
          bandaNota(T('La lista está recortada al tope de') + ' ' + r.recortes.map(function (n) { return r.topes[n] + ' ' + T(n); }).join(', ') +
            ' — ' + T('los totales son parciales. Pide a Desarrollo subir el tope.'), '#93000a');
        }
        var porId = {}; OPS.forEach(function (o) { porId[o.id] = o; });
        window.LW_V4 = window.LW_V4 || {}; window.LW_V4.contratosLista = porId;
        var raices = OPS.filter(function (o) { return !o.padre; });
        // email → nombre, sin distinguir mayúsculas (creado_por guarda el email tal cual se tecleó)
        var nombreEquipo = {};
        Object.keys(r.equipo || {}).forEach(function (e) { nombreEquipo[e.toLowerCase()] = r.equipo[e]; });
        var operadorDe = function (c) { return c.creado_por ? (nombreEquipo[c.creado_por.toLowerCase()] || c.creado_por) : '—'; };

        var cadena = function (o) { return (typeof cadenaOperacion === 'function') ? cadenaOperacion(o) : [o].concat(o.hijos || []); };
        var firmaViva = function (c) { return (c.firmas || []).some(function (f) { return f.estado === 'pendiente' && !firmaCaducada(f); }); };
        /* estado de UNA pieza de la cadena, para la columna «Contratos» */
        function estadoPieza(c) {
          if (c.liberado_en) return [T('liberada'), 'mal'];
          if (c.bloqueado) return [T('firmado'), 'ok'];
          if (firmaViva(c)) return [T('en firma'), 'espera'];
          if (c.pdf_firmado_path) return [T('reabierto'), 'espera'];
          return [T('borrador'), ''];
        }
        var ETQ = {};
        (typeof ETAPAS !== 'undefined' ? ETAPAS : []).forEach(function (e) { ETQ[e[0]] = e[1]; });
        var TONO = { sin_firmar: 'espera', firma_viva: 'espera', cobro_pend: 'mal', cobro_ok: 'ok', liberada: '' };
        ETQ.liberada = T('Reserva liberada');   // etapaOperacion la devuelve; no es columna del tablero clásico
        var lim48 = Date.now() + 48 * 3600e3;
        function facturaViva(o) {
          // Solo una FACTURA cuenta (Administración, consulta de deploy 22-sep): un
          // recibí es dinero recibido, no factura emitida — justo el caso fiscal
          // que este chip existe para cazar (RP00025: 39.220 € por recibí y cero facturas).
          return cadena(o).some(function (c) { return (c.facturas || []).some(function (f) { return !f.anulada && f.tipo === 'factura'; }); });
        }
        function firmadaAlguna(o) { return cadena(o).some(function (c) { return c.bloqueado && !c.liberado_en; }); }
        function faltaFicha(o) { return typeof fichasQueFaltan === 'function' && cadena(o).some(function (c) { return fichasQueFaltan(c) > 0; }); }

        /* Avisos de la operación (además de la etapa): lo que en la v4 anterior
           vivía solo en su `ETQ` y no podía perderse al pasar a la etapa
           compartida — Legal (19-sep): una reserva firmada sin señal cobrada
           bloquea parcela sin contraprestación; un «sin importe» firmado solo
           es legítimo en un poder. Y la firma que caduca en menos de 48 h. */
        function avisosDe(o) {
          var out = [], cg = cuentaGrupo(o), p = (typeof piezaActiva === 'function') ? piezaActiva(o) : o;
          if (p.liberado_en) return out;   // cadena liberada: ningún aviso pide acción sobre una reserva muerta
          if (faltaFicha(o)) out.push([T('Falta ficha'), 'mal']);
          // Sobre CUALQUIER Carta firmada viva de la cadena, no sobre la pieza activa
          // (Legal, consulta de deploy 22-sep): con el borrador del Bloqueo creado la
          // pieza activa es el borrador y el aviso desaparecía en el paso normal del flujo.
          if (cadena(o).some(function (c) { return c.bloqueado && !c.liberado_en && esPreliminar(c); }) && !(cg.facturado > 0)) out.push([T('Reserva sin señal cobrada'), 'mal']);
          if (p.bloqueado && !cg.precio && p.tipo !== 'poa') out.push([T('Falta precio'), 'espera']);
          if (cadena(o).some(function (c) { return (c.firmas || []).some(function (f) { return f.estado === 'pendiente' && f.expira_en && new Date(f.expira_en).getTime() < lim48 && new Date(f.expira_en).getTime() > Date.now(); }); })) out.push([T('Firma caduca en < 48 h'), 'mal']);
          return out;
        }

        /* ---- filas ---- */
        var celdaNum = function (n, m, fuerte) {
          if (n == null) return '<span class="text-stone-sand">—</span>';
          return '<span class="' + (fuerte ? 'font-bold ' : '') + 'whitespace-nowrap">' + esc(fmt(n, m)) + '</span>';
        };
        raices.sort(function (a, b) { return String(b.created_at).localeCompare(String(a.created_at)); });
        tbody.innerHTML = raices.map(function (o) {
          var cg = cuentaGrupo(o), e = etapaOperacion(o), piezas = cadena(o);
          var p = (typeof piezaActiva === 'function') ? piezaActiva(o) : o;
          var lib = e === 'liberada';   // cadena liberada: nada exigible, el pendiente no se afirma
          var parcelas = []; piezas.forEach(function (c) { if (c.parcela_codigo && parcelas.indexOf(c.parcela_codigo) === -1) parcelas.push(c.parcela_codigo); });
          var pzHtml = piezas.map(function (c) {
            var st = estadoPieza(c);
            return '<span class="inline-flex items-center gap-1 whitespace-nowrap">' +
              '<a href="#" data-lw-ficha-contrato="' + esc(c.id) + '" title="' + esc(tipoC(c.tipo)) + '" class="font-label-md font-semibold text-deep-lagoon underline decoration-deep-lagoon/30">' + esc(c.numero || T('sin nº')) + '</a>' +
              pill(st[0], st[1]) + '</span>';
          }).join('');
          var avs = avisosDe(o);
          var firmada = firmadaAlguna(o);
          return '<tr data-lw-fila data-lw-id="' + esc(o.id) + '" data-lw-etapa="' + esc(e) + '" data-lw-firmada="' + (firmada ? 1 : 0) +
            '" data-lw-sinfactura="' + (firmada && !facturaViva(o) ? 1 : 0) + '" data-lw-faltaficha="' + (faltaFicha(o) ? 1 : 0) +
            '" data-lw-proyecto="' + esc(o.proyecto_nombre || '') +
            '" data-lw-pajar="' + esc(piezas.map(function (c) { return [c.numero, c.comprador_nombre, c.proyecto_nombre, c.parcela_codigo, tipoC(c.tipo), c.creado_por, operadorDe(c)].join(' '); }).join(' ').toLowerCase()) +
            '" class="hover:bg-surface-alt/50 transition-colors cursor-pointer align-top">' +
            '<td class="py-3 px-4 font-label-md font-bold text-deep-lagoon whitespace-nowrap">' + esc(o.numero || T('sin nº')) + '</td>' +
            '<td class="py-3 px-4 font-label-md text-volcanic-ash font-semibold">' + esc(o.comprador_nombre || '—') +
              (avs.length ? '<div class="mt-1 flex flex-wrap gap-1">' + avs.map(function (a) { return pill(a[0], a[1]); }).join('') + '</div>' : '') + '</td>' +
            '<td class="py-3 px-4 text-volcanic-ash">' + esc(o.proyecto_nombre || '—') + (parcelas.length ? '<div class="text-[11px] text-stone-sand">' + esc(parcelas.join(', ')) + '</div>' : '') + '</td>' +
            '<td class="py-3 px-4"><div class="flex flex-wrap gap-x-3 gap-y-1">' + pzHtml + '</div></td>' +
            '<td class="py-3 px-4 text-right font-kpi-number text-volcanic-ash">' + (cg.precio ? celdaNum(cg.precio, cg.moneda) : '<span class="text-stone-sand text-[12px]">' + T('sin fijar') + '</span>') + '</td>' +
            '<td class="py-3 px-4 text-right font-kpi-number text-territorial-green">' + celdaNum(cg.facturado, cg.moneda) + '</td>' +
            '<td class="py-3 px-4 text-right font-kpi-number text-volcanic-ash">' + (cg.pendiente != null && !lib ? celdaNum(cg.pendiente, cg.moneda, cg.pendiente > 0) : '<span class="text-stone-sand">—</span>') + '</td>' +
            '<td class="py-3 px-4 whitespace-nowrap">' + pill(ETQ[e] || e, TONO[e] || '') +
              (piezas.length > 1 ? '<div class="text-[11px] text-stone-sand mt-1">' + esc(p.numero || '') + '</div>' : '') + '</td>' +
            '<td class="py-3 px-4 text-on-surface-variant text-[12px]" title="' + esc(o.creado_por || '') + '">' + esc(operadorDe(o)) + '</td>' +
            '</tr>';
        }).join('') || '<tr><td class="py-8 px-6 text-center text-stone-sand" colspan="9">' + T('Todavía no hay operaciones.') + '</td></tr>';

        tbody.addEventListener('click', function (ev) {
          var a = ev.target.closest && ev.target.closest('[data-lw-ficha-contrato]');
          if (a) { ev.preventDefault(); ev.stopPropagation(); var x = porId[a.getAttribute('data-lw-ficha-contrato')]; if (x) fichaContrato(sb, x, { sinExpediente: true, cadena: cadena(x) }); return; }
          var tr = ev.target.closest && ev.target.closest('tr[data-lw-id]'); if (!tr) return;
          ev.stopPropagation();
          var o = porId[tr.getAttribute('data-lw-id')]; if (o) fichaContrato(sb, o, { sinExpediente: true, cadena: cadena(o) });
        });

        /* ---- KPIs y pie: sobre lo VISIBLE ---- */
        var estado = {}, texto = '', filtroTexto = T('Todas');
        function pintaTotales() {
          var vis = [], n = 0;
          Array.prototype.forEach.call(tbody.querySelectorAll('tr[data-lw-id]'), function (tr) {
            if (tr.style.display === 'none') return;
            n++; var o = porId[tr.getAttribute('data-lw-id')]; if (o) vis.push(o);
          });
          var precio = 0, cobrado = 0, pendiente = 0, otras = 0, firmadas = 0, sinCartas = 0;
          vis.forEach(function (o) {
            var cg = cuentaGrupo(o);
            // liberada: lo cobrado es dinero real (señal no reembolsable) pero el precio ya no es un trato
            if (etapaOperacion(o) === 'liberada') { if ((cg.moneda || 'EUR') === 'EUR') cobrado += cg.facturado || 0; return; }
            if (firmadaAlguna(o)) firmadas++;
            if (cg.soloPreliminar) sinCartas++;
            if ((cg.moneda || 'EUR') !== 'EUR') { otras++; return; }
            precio += cg.precio || 0; cobrado += cg.facturado || 0;
            if (firmadaAlguna(o) && cg.pendiente != null && cg.pendiente > 0) pendiente += cg.pendiente;
          });
          pon2('p-desde', String(n)); pon2('p-total', String(raices.length)); pon2('p-vis', n + ' ' + T('visibles'));
          pon2('k-ops', String(n));
          pon2('k-ops-pie', firmadas + ' ' + T('con contrato firmado') + ' · ' + (n - firmadas) + ' ' + T('sin firmar') +
            (filtroTexto !== T('Todas') || estado.proyecto && estado.proyecto.valor !== '*' ? ' · ' + T('filtro') + ': ' + filtroTexto + (estado.proyecto && estado.proyecto.valor !== '*' ? ' · ' + estado.proyecto.valor : '') : ''));
          pon2('k-precio', fmt(precio, 'EUR'));
          pon2('k-precio-pie', T('Suma en euros de lo que ves. Las Cartas de Reserva no suman precio.') + (otras ? ' ' + otras + ' ' + T('en otra moneda quedan fuera.') : ''));
          pon2('k-cobrado', fmt(cobrado, 'EUR'));
          var pct = precio ? Math.round(cobrado / precio * 1000) / 10 : 0;
          pon2('k-cobrado-pie', precio ? pct + ' % ' + T('del precio, por recibís') : T('sin precio con el que comparar'));
          var barra = document.querySelector('[data-lw-barra="k-cobrado"]'); if (barra) barra.style.width = Math.min(100, pct) + '%';
          pon2('k-pendiente', fmt(pendiente, 'EUR'));
          pon2('k-pendiente-pie', T('Lo que falta por cobrar de las operaciones con contrato firmado.'));
        }
        var aplicar = function () {
          aplicaFiltros(tbody, estado, ['estado', 'proyecto'], texto, function () { pintaTotales(); });
        };
        var nDe = function (fn) { return raices.filter(fn).length; };
        var ops = [
          { clave: '*', texto: T('Todas'), n: raices.length },
          { clave: 'sin_firmar', atributo: 'etapa', texto: ETQ.sin_firmar || T('Sin firmar'), n: nDe(function (o) { return etapaOperacion(o) === 'sin_firmar'; }) },
          { clave: 'firma_viva', atributo: 'etapa', texto: ETQ.firma_viva || T('Firma enviada'), n: nDe(function (o) { return etapaOperacion(o) === 'firma_viva'; }) },
          { clave: '1', atributo: 'firmada', texto: T('Firmadas'), n: nDe(firmadaAlguna) },
          { clave: 'cobro_pend', atributo: 'etapa', texto: ETQ.cobro_pend || T('Cobro pendiente'), n: nDe(function (o) { return etapaOperacion(o) === 'cobro_pend'; }) },
          { clave: 'cobro_ok', atributo: 'etapa', texto: ETQ.cobro_ok || T('Cobro completo'), n: nDe(function (o) { return etapaOperacion(o) === 'cobro_ok'; }) },
          // «Firmadas sin facturar» y no «Sin facturar» a secas (owner, 22-sep):
          // un borrador sin factura es lo normal; la que pide acción es la firmada.
          { clave: '1', atributo: 'sinfactura', texto: T('Firmadas sin facturar'), n: nDe(function (o) { return firmadaAlguna(o) && !facturaViva(o); }) },
          { clave: '1', atributo: 'faltaficha', texto: T('Falta ficha'), n: nDe(faltaFicha) },
          { clave: 'liberada', atributo: 'etapa', texto: T('Liberadas'), n: nDe(function (o) { return etapaOperacion(o) === 'liberada'; }) }
        ];
        var contChips = document.querySelector('[data-lw-chips="estado"]');
        chipsReales(contChips, 'estado', ops, estado, function () {
          var on = contChips && contChips.querySelector('button.bg-primary');
          filtroTexto = on ? on.textContent.replace(/\s\d+$/, '').trim() : T('Todas');
          aplicar();
        });
        buscadorDe(aplicar, function (v) { texto = v; });
        var sel = document.querySelector('main select');
        if (sel) {
          var proys = {}; raices.forEach(function (o) { if (o.proyecto_nombre) proys[o.proyecto_nombre] = (proys[o.proyecto_nombre] || 0) + 1; });
          sel.innerHTML = '<option value="*">' + T('Todos los proyectos') + '</option>' + Object.keys(proys).sort().map(function (p) { return '<option value="' + esc(p) + '">' + esc(p) + ' (' + proys[p] + ')</option>'; }).join('');
          sel.setAttribute('data-real', '');
          sel.addEventListener('change', function () { estado.proyecto = { attr: 'proyecto', valor: sel.value }; aplicar(); });
        }
        var bAct = botonConTexto(/Actualizar$/i);
        if (bAct) { bAct.setAttribute('data-real', ''); bAct.addEventListener('click', function (ev) { ev.stopPropagation(); location.reload(); }); }
        pintaTotales();

        /* ?filtro= — claves de la clásica (FILTROS) y las del Home; el alias
           `firma_viva` lo sigue usando el Home CLÁSICO (intranet/index.html). */
        var filtro = new URLSearchParams(location.search).get('filtro');
        var IDX = { sin_firmar: 1, firma: 2, firma_viva: 2, firmado: 3, firmadas: 3, debe: 4, pendiente: 4, cobro_pend: 4, cobrado: 5, cobro_ok: 5, sin_factura: 6, falta_ficha: 7 };
        if (filtro && contChips && IDX[filtro]) {
          var bs = contChips.querySelectorAll('button'); if (bs[IDX[filtro]]) bs[IDX[filtro]].click();
        }
        /* ?contrato=NUM abre la ficha de ESE contrato (raíz o pieza de una
           cadena) — es el enlace que usan la ficha desde Contratos («Ver en
           Operaciones»), Vencimientos y el Home. */
        var pedido = new URLSearchParams(location.search).get('contrato');
        if (pedido) {
          // por número o por id: los avisos de la campana (avisos.js) llevan el id
          var el0 = OPS.filter(function (c) { return c.numero === pedido || c.id === pedido; })[0];
          if (el0) fichaContrato(sb, el0, { sinExpediente: true, cadena: cadena(el0) });
          else if (typeof toastMal === 'function') toastMal(T('No encuentro el contrato') + ' ' + pedido + ' ' + T('entre los cargados.'));
        }
      }, function (e) { fallo('operaciones', e, caja); });
    },
    vencimientos: function (sb) {
      /* S15 (22-sep-2026): el owner revirtió el recorte del 19-sep (096369ef,
         "KPIs + CSV + redirect a la herramienta clásica para el detalle") y
         pidió portar el detalle completo — cascada paginada, chips empresa/
         moneda/sin-firmar, «Cubierto» como columna, por proyecto con «quién
         debe», facturas con vencimiento propio. Todo sobre `logica.js`
         (compartido, sin duplicar) y `entities.js` (empresa) — sin RPC ni
         escritura nueva: el editor de fecha por hito sigue siendo el de
         editores.js (`ata(/Registrar hito/i, ...)`), no se toca aquí. */
      if (typeof modeloFinanciero !== 'function') {
        fallo('vencimientos', 'logica.js no cargada: el cuerpo se queda en maqueta');
        return;
      }
      // Fecha LOCAL, no UTC (Bali es UTC+8): `toISOString()` cerca de
      // medianoche adelanta o atrasa el día un vencimiento entero, y esta
      // pantalla tiene que decidir "vencido" exactamente igual que la clásica
      // (misma cascada, mismo hoy — hallazgo de la revisión de este build).
      var hoyD = new Date();
      var hoy = hoyD.getFullYear() + '-' + String(hoyD.getMonth() + 1).padStart(2, '0') + '-' + String(hoyD.getDate()).padStart(2, '0');

      var SIN_FIRMAR = (function () {
        try { return localStorage.getItem('lw_venc_sin_firmar') === '1'; }
        catch (_) { /* MUDO A PROPOSITO: sin localStorage cae al valor por defecto (apagado) */ return false; }
      })();
      var EMPRESA = (function () {
        try { return localStorage.getItem('lw_venc_empresa') || 'todas'; }
        catch (_) { /* MUDO A PROPOSITO: sin localStorage cae a "todas" */ return 'todas'; }
      })();
      var MONEDA = 'EUR', FILTRO = 'atencion', PAGINA = 0;
      var POR_PAGINA = 25;
      var RAW = null, MODELO = null, FACTURAS = [];

      // Mismos 5 tramos que la clásica (index.html:586-591) — pura lectura de
      // `f`, sin aritmética nueva.
      var FILTROS = [
        ['atencion', 'Necesitan atención', function (f) { return f.estado === 'vencido' || f.estado === 'sin_fecha' || f.estado === 'parcial'; }],
        ['vencido', 'Vencidos', function (f) { return f.estado === 'vencido'; }],
        ['proximos', 'Próximos 90 días', function (f) { return f.fecha && f.pendiente > 0 && f.fecha >= hoy && diasEntre(hoy, f.fecha) <= 90; }],
        ['sin_fecha', 'Sin fecha', function (f) { return f.estado === 'sin_fecha'; }],
        ['todos', 'Todos', function () { return true; }]
      ];
      var ESTADO_TAG = { vencido: ['Vencido', 'mal'], parcial: ['Parcial', 'espera'], pendiente: ['Pendiente', ''], cobrado: ['Cobrado', 'ok'], sin_fecha: ['Sin fecha', 'espera'] };

      /* Las sociedades ANTES del modelo: `empresasFinancieras()`/`filtraEmpresa()`
         de logica.js llaman a `lwSociedadContrato` (entities.js), y sin
         SOCIEDADES cargado los chips de empresa enseñarían la clave cruda.
         Si esta consulta falla, se sigue igual (sin chip de empresa, no en
         blanco) — el resto del panel no depende de ella. */
      (typeof cargarSociedades === 'function' ? cargarSociedades(sb) : Promise.resolve())
        .catch(function (e) { fallo('sociedades', e); })
        .then(function () {
          return Promise.all([
            // `soc`: la sociedad firmante guardada en el contrato, igual que la clásica (index.html:335).
            q(sb.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,bloqueado,contrato_padre_id,created_at,soc:datos->fields->>sociedad_firmante').limit(1000), 'contratos'),
            vig(sb.rpc('contratos_cobrado_equipo')).then(function (r) { if (r.error) { fallo('cobrado', r.error); return null; } return r.data || []; }),
            q(sb.from('contrato_vencimientos').select('id,contrato_id,orden,descripcion,pct,monto,fecha,ajustado,nota,factura_id,no_facturar').limit(3000), 'vencimientos'),
            // Facturas con vencimiento propio (criterio S15): mismo `venc` calculado que la clásica (index.html:338).
            q(sb.rpc('facturas_equipo').select('numero,tipo,sociedad,cliente_nombre,total,moneda,anulada,created_at,venc:datos->fields->>fecha_vencimiento').limit(1000), 'facturas de vencimiento propio')
          ]);
        })
        .then(function (r) {
          if (!r) return;
          var cs = r[0], cb = r[1], vs = r[2], fs = r[3];
          if (!cs || !vs) return;
          var cobradoPorId = {};
          (cb || []).forEach(function (x) { cobradoPorId[x.contrato_id] = Number(x.cobrado) || 0; });
          FACTURAS = (fs || []).filter(function (f) { return !f.anulada && f.venc && f.tipo !== 'recibi'; });
          RAW = { hoyISO: hoy, contratos: cs, cobradoPorId: cobradoPorId, vencimientos: vs };

          recalcula();
          var monedas0 = Object.keys(MODELO).sort(function (a, b) { return MODELO[b].cartera - MODELO[a].cartera; });
          MONEDA = monedas0[0] || 'EUR';
          pintarTodo();

          // «Exportar previsión de caja»: CSV de la cascada. Se lee MODELO/MONEDA
          // EN EL MOMENTO DEL CLIC (no una `m` capturada al cargar): tras cambiar
          // un chip, el CSV tiene que exportar lo que se está viendo, no lo de la
          // carga inicial.
          var bExp = botonConTexto(/Exportar previsi/i);
          if (bExp) {
            bExp.setAttribute('data-real', '');
            bExp.addEventListener('click', function (ev) {
              ev.stopPropagation();
              var m2 = MODELO[MONEDA]; if (!m2) return;
              var filas = m2.filas.filter(function (f) { return f.estado !== 'cobrado'; })
                .sort(function (a, b) { return (a.fecha || '9999') < (b.fecha || '9999') ? -1 : 1; })
                .map(function (f) {
                  return [f.fecha || 'sin fecha', f.descripcion || 'Hito', f.contrato.numero, tipoC(f.contrato.tipo), f.contrato.proyecto_nombre || '', f.contrato.comprador_nombre || '',
                    f.importe != null ? f.importe : '', f.pendiente != null ? f.pendiente : '', MONEDA, f.estado, f.contrato.bloqueado ? 'firmado' : 'borrador'];
                });
              exportaCSV('prevision_caja_' + hoy + '.csv', ['Fecha', 'Hito', 'Contrato', 'Tipo', 'Proyecto', 'Comprador', 'Importe', 'Pendiente', 'Moneda', 'Estado', 'Contrato firmado'], filas);
            });
          }
        })
        // Hallazgo del code-review de esta subtarea: todas las consultas de
        // arriba pasan por `q()`/`vig()`, que absorben el `.error` de la RESPUESTA
        // — pero si el propio fetch de supabase-js LANZA (red caída, típico en
        // Bali), la cadena entera de `.then` no se ejecuta y sin este `.catch`
        // la pantalla se queda para siempre en "Trayendo los vencimientos…" sin
        // ni un error en pantalla ni una llamada a fallo().
        .catch(function (e) { fallo('vencimientos', e); });

      /* ── EL camino de recálculo, uno solo (mismo motivo que la clásica:
         "cerrar una salida no cierra a sus hermanas", 9-sep-2026) ────────── */
      function recalcula() {
        var emps = (typeof empresasFinancieras === 'function') ? empresasFinancieras(RAW, FACTURAS) : [];
        if (EMPRESA !== 'todas' && emps.indexOf(EMPRESA) === -1) EMPRESA = 'todas';
        var entrada = (typeof filtraEmpresa === 'function') ? filtraEmpresa(RAW, EMPRESA) : RAW;
        MODELO = modeloFinanciero({ hoyISO: RAW.hoyISO, contratos: entrada.contratos, cobradoPorId: RAW.cobradoPorId, vencimientos: RAW.vencimientos, incluirSinFirmar: SIN_FIRMAR });
        if (!MODELO[MONEDA]) {
          var mm = Object.keys(MODELO).sort(function (a, b) { return MODELO[b].cartera - MODELO[a].cartera; });
          if (mm.length) MONEDA = mm[0];
        }
      }

      function modeloVacio() { return { cartera: 0, cobrado: 0, pendiente: 0, vencido: 0, proximos30: 0, proximos90: 0, nSinFecha: 0, filas: [], porProyecto: {}, avisos: [], fuera: { sinFirmar: 0 } }; }

      function pintarTodo() {
        var m = MODELO[MONEDA] || modeloVacio();
        pintarChipsEmpresa();
        pintarChipsMoneda();
        pintarAvisos(m);
        pintarKpis(m);
        pintarChipsEstado(m);
        pintarTabla(m);
        pintarProyectos(m);
        pintarFacturas();
      }

      /* ── empresa: los chips salen de los DATOS, no del catálogo ─────────── */
      function pintarChipsEmpresa() {
        var cont = document.querySelector('[data-lw-chips="empresa"]'); if (!cont) return;
        while (cont.children.length > 1) cont.lastElementChild.remove();
        var emps = (typeof empresasFinancieras === 'function') ? empresasFinancieras(RAW, FACTURAS) : [];
        if (emps.length < 2) return;
        var nombreDe = function (k) { return (typeof SOCIEDADES !== 'undefined' && SOCIEDADES[k] && SOCIEDADES[k].razon) || k; };
        var opciones = [{ clave: 'todas', texto: 'Todas' }].concat(emps.map(function (e) { return { clave: e, texto: nombreDe(e) }; }));
        opciones.forEach(function (o) {
          var b = document.createElement('button');
          b.type = 'button'; b.setAttribute('data-real', '');
          b.className = 'px-4 py-1.5 rounded-full font-label-md text-label-md transition-colors ' + (o.clave === EMPRESA ? 'bg-deep-lagoon text-on-secondary font-semibold shadow-sm' : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high');
          b.textContent = o.texto;
          b.addEventListener('click', function (ev) {
            ev.stopPropagation();
            EMPRESA = o.clave;
            try { localStorage.setItem('lw_venc_empresa', EMPRESA); }
            catch (_) { /* MUDO A PROPOSITO: sin localStorage no se recuerda la empresa elegida */ }
            PAGINA = 0; recalcula(); pintarTodo();
          });
          cont.appendChild(b);
        });
      }

      /* ── moneda: cada agregado va por moneda, quien mira elige cuál ─────── */
      function pintarChipsMoneda() {
        var cont = document.querySelector('[data-lw-chips="moneda"]'); if (!cont) return;
        while (cont.children.length > 1) cont.lastElementChild.remove();
        var monedas = Object.keys(MODELO).sort(function (a, b) { return MODELO[b].cartera - MODELO[a].cartera; });
        if (monedas.length < 2) return;
        monedas.forEach(function (mm) {
          var b = document.createElement('button');
          b.type = 'button'; b.setAttribute('data-real', '');
          b.className = 'px-4 py-1.5 rounded-full font-label-md text-label-md transition-colors ' + (mm === MONEDA ? 'bg-deep-lagoon text-on-secondary font-semibold shadow-sm' : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high');
          b.textContent = mm + ' ' + fmt(MODELO[mm].cartera, '');
          b.addEventListener('click', function (ev) { ev.stopPropagation(); MONEDA = mm; PAGINA = 0; pintarTodo(); });
          cont.appendChild(b);
        });
      }

      /* ── estado (5 tramos) + «Incluir sin firmar» junto a ellos ─────────── */
      function pintarChipsEstado(m) {
        var cont = document.querySelector('[data-lw-chips="estado"]'); if (!cont) return;
        while (cont.children.length > 1) cont.lastElementChild.remove();
        FILTROS.forEach(function (entrada) {
          var clave = entrada[0], texto = entrada[1], fn = entrada[2];
          var n = m.filas.filter(fn).length;
          var b = document.createElement('button');
          b.type = 'button'; b.setAttribute('data-real', '');
          b.className = 'px-4 py-1.5 rounded-full font-label-md text-label-md transition-colors ' + (clave === FILTRO ? 'bg-deep-lagoon text-on-secondary font-semibold shadow-sm' : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high');
          b.textContent = texto + ' ' + n;
          b.addEventListener('click', function (ev) {
            ev.stopPropagation();
            FILTRO = clave; PAGINA = 0;
            pintarChipsEstado(MODELO[MONEDA]); pintarTabla(MODELO[MONEDA]);
          });
          cont.appendChild(b);
        });
        var chipSF = document.getElementById('venc-chip-sinfirmar');
        if (chipSF) {
          var f = m.fuera || { sinFirmar: 0 };
          chipSF.hidden = !(f.sinFirmar || SIN_FIRMAR);
          chipSF.textContent = 'Incluir sin firmar' + (f.sinFirmar ? ' ' + f.sinFirmar : '');
          chipSF.className = 'px-4 py-1.5 rounded-full font-label-md text-label-md transition-colors ' + (SIN_FIRMAR ? 'bg-deep-lagoon text-on-secondary font-semibold shadow-sm' : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high');
          chipSF.setAttribute('data-real', '');
          chipSF.onclick = function (ev) {
            ev.stopPropagation();
            SIN_FIRMAR = !SIN_FIRMAR;
            try { localStorage.setItem('lw_venc_sin_firmar', SIN_FIRMAR ? '1' : '0'); }
            catch (_) { /* MUDO A PROPOSITO: sin localStorage no se recuerda el interruptor */ }
            recalcula(); pintarTodo();
          };
        }
      }

      /* ── avisos: lo que impide vigilar de verdad ─────────────────────────── */
      function pintarAvisos(m) {
        var cont = document.getElementById('venc-avisos'); if (!cont) return;
        var partes = [];
        if (m.nSinFecha) partes.push(m.nSinFecha + ' vencimiento(s) sin fecha — no se pueden vigilar; usa el filtro «Sin fecha»');
        var sinCal = (m.avisos || []).filter(function (a) { return a.tipo === 'sin_calendario'; });
        if (sinCal.length) partes.push(sinCal.length + (sinCal.length === 1 ? ' contrato con precio y sin calendario de pagos' : ' contratos con precio y sin calendario de pagos'));
        // pct_no_100 (hallazgo del code-review de esta subtarea): modeloFinanciero()
        // ya calcula este aviso — logica.js lo empuja a m.avisos igual que sin_calendario
        // — pero se filtraba aquí y se perdía en silencio. Mismo texto que la clásica.
        var pctMal = (m.avisos || []).filter(function (a) { return a.tipo === 'pct_no_100'; });
        if (pctMal.length) partes.push(pctMal.length + (pctMal.length === 1 ? ' contrato cuyos hitos no suman 100%' : ' contratos cuyos hitos no suman 100%'));
        /* «Fuera de este panel» (hallazgo del code-review, gravedad alta): sin esto
           se reproduce en silencio el incidente del 26-ago-2026 (Sumba Hills, 46
           contratos y solo 2 firmados+preliminares → el panel salía VACÍO y nadie
           sabía por qué, «aquí no hay dinero», la lectura peligrosa). `m.fuera` es
           el contador que logica.js escribió justo para poder decirlo — no se
           puede quitar del panel «detalle completo», es la mitad de por qué existe. */
        var f = m.fuera || { sinFirmar: 0, preliminares: 0, proyectos: {}, importe: 0 };
        if (f.sinFirmar || f.preliminares) {
          var trozos = [];
          if (f.sinFirmar) trozos.push(f.sinFirmar + ' sin firmar');
          if (f.preliminares) trozos.push(f.preliminares + (f.preliminares === 1 ? ' Carta de Reserva' : ' Cartas de Reserva'));
          var top = Object.keys(f.proyectos || {}).map(function (p) { return [p, f.proyectos[p]]; })
            .sort(function (a, b) { return b[1] - a[1]; }).slice(0, 3)
            .map(function (par) { return par[0] + ' (' + par[1] + ')'; }).join(', ');
          partes.push('Fuera de este panel: ' + trozos.join(' y ')
            + (f.importe ? ' — ' + fmt(f.importe, '') + ' de precio' : '')
            + (top ? '. Sobre todo en ' + top : '')
            + '. Aquí solo entran contratos firmados que no sean preliminares' + (SIN_FIRMAR ? ' (salvo los sin firmar, ya incluidos con el interruptor encendido)' : ''));
        }
        cont.innerHTML = partes.length
          ? '<p class="text-body-sm font-body-sm px-3 py-2 rounded-lg bg-soft-canopy/15 text-territorial-green" role="status">' + esc(partes.join(' · ')) + '</p>'
          : '';
      }

      /* ── KPIs (5: 90 días, críticos 7d, vencido, cobrado, cartera) ──────── */
      function pintarKpis(m) {
        pon2('k-prevision', fmt(m.proximos90, MONEDA));
        pon2('k-prevision-chip', 'previsto en el trimestre');
        var d7d = new Date(hoyD.getTime() + 7 * 864e5);
        var d7 = d7d.getFullYear() + '-' + String(d7d.getMonth() + 1).padStart(2, '0') + '-' + String(d7d.getDate()).padStart(2, '0');
        var semana = m.filas.filter(function (f) { return f.estado !== 'vencido' && f.estado !== 'cobrado' && f.fecha && f.fecha >= hoy && f.fecha <= d7; });
        var sumaCrit = semana.reduce(function (a, f) { return a + (f.pendiente != null ? f.pendiente : (f.importe || 0)); }, 0);
        pon2('k-criticos', semana.length + (semana.length === 1 ? ' cobro' : ' cobros'));
        pon2('k-criticos-total', 'Total: ' + fmt(sumaCrit, MONEDA));
        var venc = m.filas.filter(function (f) { return f.estado === 'vencido'; }).sort(function (a, b) { return (a.fecha || '') < (b.fecha || '') ? -1 : 1; });
        var nCon = {}; venc.forEach(function (f) { nCon[f.contrato_id] = 1; });
        var nc = Object.keys(nCon).length;
        pon2('k-vencidos-n', nc + (nc === 1 ? ' contrato' : ' contratos'));
        pon2('k-vencidos-total', 'Total: ' + fmt(m.vencido, MONEDA));
        pon2('k-vencidos-chip', venc.length ? 'el más antiguo, del ' + fFecha(venc[0].fecha) : 'nada vencido');
        // `m.cobrado` (logica.js) SUMA también lo cobrado de preliminares sueltos
        // y —si «Incluir sin firmar» está encendido— de contratos sin firmar: no
        // es "solo recibís de firmados" (hallazgo del code-review de esta
        // subtarea: el texto viejo de esta pantalla lo daba por hecho y mentía
        // en cuanto había una Carta de Reserva o el interruptor encendido).
        // Mismo texto que la clásica: solo el % sobre la cartera, o nada.
        pon2('k-cobrado', fmt(m.cobrado, MONEDA));
        pon2('k-cobrado-pie', m.cartera ? Math.round(m.cobrado / m.cartera * 100) + '% de la cartera' : '');
        pon2('k-cartera', fmt(m.cartera, MONEDA));
        pon2('k-cartera-pie', 'contratos firmados, sin contar las Cartas de Reserva');
      }

      /* ── la tabla: cascada completa, paginada de verdad (25/página) ─────── */
      function pintarTabla(m) {
        var entrada = FILTROS.filter(function (x) { return x[0] === FILTRO; })[0] || FILTROS[4];
        var filas = m.filas.filter(entrada[2]);
        var titulo = document.getElementById('venc-tabla-titulo');
        if (titulo) titulo.textContent = entrada[1] + ' · ' + filas.length;
        var tbody = document.getElementById('venc-tbody');
        var pager = document.getElementById('venc-pager');
        var resumen = document.getElementById('venc-resumen');
        if (!tbody) return;
        if (!filas.length) {
          tbody.innerHTML = '<tr><td class="py-8 px-5 text-center text-control-border" colspan="8">Nada con este filtro.</td></tr>';
          if (pager) pager.hidden = true;
          if (resumen) resumen.textContent = '0 de 0';
          return;
        }
        var totalPaginas = Math.max(1, Math.ceil(filas.length / POR_PAGINA));
        if (PAGINA >= totalPaginas) PAGINA = totalPaginas - 1;
        var desde = PAGINA * POR_PAGINA;
        var pagina = filas.slice(desde, desde + POR_PAGINA);
        var texto = (desde + 1) + '–' + (desde + pagina.length) + ' de ' + filas.length;
        if (resumen) resumen.textContent = texto;
        if (pager) pager.hidden = filas.length <= POR_PAGINA;
        var pInfo = document.getElementById('venc-pag-info');
        var pAntes = document.getElementById('venc-pag-antes');
        var pDespues = document.getElementById('venc-pag-despues');
        if (pInfo) pInfo.textContent = texto;
        if (pAntes) pAntes.disabled = PAGINA === 0;
        if (pDespues) pDespues.disabled = PAGINA >= totalPaginas - 1;
        tbody.innerHTML = pagina.map(function (f) {
          var tag = ESTADO_TAG[f.estado] || [f.estado, ''];
          var estadoHtml = pill(tag[0], tag[1])
            + (f.factura_id ? ' ' + pill('Facturada', 'ok') : '')
            + (f.no_facturar ? ' ' + pill('Sin auto', '') : '');
          var cubiertoHtml = f.cubierto ? esc(fmt(f.cubierto, MONEDA)) : '<span class="text-control-border">—</span>';
          var fechaTxt = f.fecha ? esc(fFecha(f.fecha)) : '<span class="text-control-border">sin fecha</span>';
          return '<tr class="hover:bg-surface-container-low/70 transition-colors border-t border-surface-container-high/40 cursor-pointer" data-vid="' + esc(f.id) + '">'
            + '<td class="py-4 px-5 text-control-border">' + fechaTxt + (f.ajustado ? ' <span class="text-control-border" title="Fecha ajustada a mano">·aj</span>' : '') + '</td>'
            + '<td class="py-4 px-4"><span class="font-label-md font-semibold text-deep-lagoon">' + esc(f.contrato.numero || 'sin nº') + '</span> <span class="text-on-surface-variant">' + esc(tipoC(f.contrato.tipo)) + '</span></td>'
            + '<td class="py-4 px-4">' + esc(f.contrato.comprador_nombre || 'sin nombre') + '</td>'
            + '<td class="py-4 px-4">' + esc(f.descripcion || 'Hito ' + f.orden) + (f.pct ? ' <span class="text-on-surface-variant">' + esc(f.pct) + '%</span>' : '') + '</td>'
            + '<td class="py-4 px-4 text-right font-kpi-number font-semibold text-deep-lagoon text-[15px]">' + esc(fmt(f.importe, MONEDA)) + '</td>'
            + '<td class="py-4 px-4 text-right">' + cubiertoHtml + '</td>'
            + '<td class="py-4 px-4 text-right font-semibold">' + (f.pendiente != null ? esc(fmt(f.pendiente, MONEDA)) : '—') + '</td>'
            + '<td class="py-4 px-5">' + estadoHtml + '</td>'
            + '</tr>';
        }).join('');
      }
      var tbodyEl = document.getElementById('venc-tbody');
      if (tbodyEl) tbodyEl.addEventListener('click', function (ev) {
        var tr = ev.target.closest && ev.target.closest('tr[data-vid]'); if (!tr) return;
        ev.stopPropagation();
        var m2 = MODELO && MODELO[MONEDA]; if (!m2) return;
        var vid = tr.getAttribute('data-vid');
        var f = m2.filas.filter(function (x) { return x.id === vid; })[0];
        if (f) fichaContrato(sb, f.contrato);   // la ficha del contrato, en el cajón
      });
      var pAntesBtn = document.getElementById('venc-pag-antes');
      if (pAntesBtn) { pAntesBtn.setAttribute('data-real', ''); pAntesBtn.addEventListener('click', function (ev) { ev.stopPropagation(); if (PAGINA > 0) { PAGINA--; pintarTabla(MODELO[MONEDA]); } }); }
      var pDespuesBtn = document.getElementById('venc-pag-despues');
      if (pDespuesBtn) { pDespuesBtn.setAttribute('data-real', ''); pDespuesBtn.addEventListener('click', function (ev) { ev.stopPropagation(); PAGINA++; pintarTabla(MODELO[MONEDA]); }); }

      /* ── por proyecto, con «quién debe» plegado por comprador ──────────── */
      function pintarProyectos(m) {
        var tbody = document.getElementById('venc-tproy'); if (!tbody) return;
        var filas = Object.keys(m.porProyecto || {}).map(function (p) { return [p, m.porProyecto[p]]; })
          .sort(function (a, b) { return b[1].cartera - a[1].cartera; });
        if (!filas.length) { tbody.innerHTML = '<tr><td class="py-8 px-5 text-center text-control-border" colspan="5">Sin contratos en esta moneda.</td></tr>'; return; }
        var html = '';
        filas.forEach(function (par) {
          var p = par[0], d = par[1];
          html += '<tr class="border-t border-surface-container-high/40">'
            + '<td class="py-4 px-5 font-label-md font-semibold text-on-surface">' + esc(p) + '</td>'
            + '<td class="py-4 px-4 text-right">' + esc(fmt(d.cartera, MONEDA)) + '</td>'
            + '<td class="py-4 px-4 text-right">' + esc(fmt(d.cobrado, MONEDA)) + '</td>'
            + '<td class="py-4 px-4 text-right">' + (d.proximos90 ? esc(fmt(d.proximos90, MONEDA)) : '<span class="text-control-border">—</span>') + '</td>'
            + '<td class="py-4 px-5 text-right">' + (d.vencido ? pill(fmt(d.vencido, MONEDA), 'mal') : '<span class="text-control-border">—</span>') + '</td>'
            + '</tr>';
          var personas = Object.keys(d.personas || {}).map(function (n) { return [n, d.personas[n]]; })
            .filter(function (par2) { return par2[1].precio > 0 || par2[1].pendiente > 0; })
            .sort(function (a, b) { return b[1].pendiente - a[1].pendiente; });
          if (personas.length) {
            html += '<tr class="border-t border-surface-container-high/40"><td colspan="5" class="p-0 bg-surface-container">'
              + '<details class="px-5 py-2.5"><summary class="cursor-pointer text-body-sm font-body-sm text-control-border select-none">'
              + personas.length + (personas.length === 1 ? ' comprador' : ' compradores') + ' · quién debe qué</summary>'
              + '<table class="w-full text-left mt-2"><tbody>' + personas.map(function (par2) {
                var n = par2[0], v = par2[1];
                return '<tr class="border-t border-surface-container-high/40">'
                  + '<td class="py-2 px-2 text-body-sm">' + esc(n) + (v.firmados === 0 ? ' ' + pill('sin firmar', 'neutro') : '') + '</td>'
                  + '<td class="py-2 px-2 text-body-sm text-right">' + esc(fmt(v.precio, MONEDA)) + '</td>'
                  + '<td class="py-2 px-2 text-body-sm text-right">' + esc(fmt(v.cobrado, MONEDA)) + '</td>'
                  + '<td class="py-2 px-2 text-body-sm text-right font-semibold">' + (v.pendiente > 0.005 ? esc(fmt(v.pendiente, MONEDA)) : '<span class="text-control-border">Cobrado</span>') + '</td>'
                  + '</tr>';
              }).join('') + '</tbody></table></details></td></tr>';
          }
        });
        tbody.innerHTML = html;
      }

      /* ── facturas con vencimiento propio: mismos chips de empresa/moneda
         que el resto del panel — no un segundo filtro (igual que la clásica,
         que filtra `pintarFacturas()` con las mismas variables globales). ── */
      function pintarFacturas() {
        var tbody = document.getElementById('venc-tfact'); if (!tbody) return;
        var filas = FACTURAS.filter(function (f) {
          return (f.moneda || 'EUR') === MONEDA
            && (EMPRESA === 'todas' || (typeof lwSociedadContrato === 'function' && lwSociedadContrato(f.sociedad, f.tipo) === EMPRESA));
        }).sort(function (a, b) { return a.venc < b.venc ? -1 : 1; }).slice(0, 40);
        if (!filas.length) { tbody.innerHTML = '<tr><td class="py-8 px-5 text-center text-control-border" colspan="5">Ninguna factura con fecha de vencimiento en esta moneda.</td></tr>'; return; }
        tbody.innerHTML = filas.map(function (f) {
          var pasada = f.venc < hoy;
          return '<tr class="border-t border-surface-container-high/40">'
            + '<td class="py-4 px-5 text-control-border">' + esc(fFecha(f.venc)) + '</td>'
            + '<td class="py-4 px-4"><span class="font-label-md font-semibold text-deep-lagoon">' + esc(f.numero || 'sin nº') + '</span> <span class="text-on-surface-variant">' + esc(tipoDoc(f.tipo)) + '</span></td>'
            + '<td class="py-4 px-4">' + esc(f.cliente_nombre || '') + '</td>'
            // MONEDA, no f.moneda: las filas ya están filtradas a la moneda activa
            // (f.moneda||'EUR')===MONEDA — una factura con `moneda` vacía en base
            // pasaba el filtro por el `||'EUR'` pero se pintaba sin sufijo de
            // divisa si se usaba el campo crudo (hallazgo del code-review).
            + '<td class="py-4 px-4 text-right font-kpi-number font-semibold text-deep-lagoon text-[15px]">' + esc(fmt(Number(f.total), MONEDA)) + '</td>'
            + '<td class="py-4 px-5">' + pill(pasada ? 'Vencida' : 'En plazo', pasada ? 'mal' : '') + '</td>'
            + '</tr>';
        }).join('');
      }
    },
    proyectos: function (sb) {
      var $ = function (k, raiz) { return (raiz || document).querySelector('[data-lw="' + k + '"]'); };
      var pon = function (k, v, raiz) { var e = $(k, raiz); if (e) e.textContent = v; };
      /* SIN DECIMALES en toda esta pantalla (23-sep-2026, owner: «quita
         decimales, son irrelevantes aquí, en todos lados»). Es un resumen de
         cartera, no un documento: los céntimos de 4 millones son ruido. Se
         tapan `fmt` y `fmtConEstimado` SOLO dentro de este módulo — el resto
         de la v4 (facturas, recibos…) sigue con los céntimos de su moneda — y
         el redondeo lo hace lwFormatoImporte (dinero.js), no un formateador
         nuevo. Los porcentajes, también enteros. La exportación CSV no pasa
         por aquí: sigue con dos decimales porque es un dato para Excel. */
      function fmt(n, m) { return (typeof lwFormatoImporte === 'function') ? lwFormatoImporte(n, m, { decimales: 0 }) : (Math.round(Number(n) || 0) + ' ' + (m || '')); }
      function fmtConEstimado(n, moneda) {
        if (n == null) return '—';
        if ((moneda || 'EUR') === 'EUR') return fmt(n, 'EUR');
        return fmt(n, moneda) + ' (≈ ' + fmt(estimaEUR(n), 'EUR') + ')';
      }
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
      // 24 por página (antes 9) y tarjetas compactas: 23-sep-2026, owner
      // «quiero ver más proyectos». 24 llena filas enteras a 2, 3 y 4 columnas.
      var PAGE_SIZE = 24;
      /* `vista`: rejilla / tabla / carpetas (23-sep-2026). Se recuerda en la
         sesión del navegador (sessionStorage, como la herramienta clásica):
         quien trabaja en Tabla no quiere volver a elegirla en cada recarga,
         pero al día siguiente se empieza por la rejilla. */
      var CLAVE_VISTA = 'lawang_v4_proyectos_vista';
      var VISTAS = ['rejilla', 'tabla', 'carpetas'];
      var vistaGuardada = null;
      try { vistaGuardada = sessionStorage.getItem(CLAVE_VISTA); } catch (_) {}
      var EST = { q: '', chipP: 'todos', chipU: 'todas', pag: 1, vista: VISTAS.indexOf(vistaGuardada) !== -1 ? vistaGuardada : 'rejilla' };
      var PS = [], POR_P = {}, COB_P = {}, DOC_P = {}, EQUIPO_NOMBRE = {}, MGRS = [];
      // FAM_P: firmado/cobrado por proyecto y familia (parcela/obra). FIRM_P:
      // firmado combinado por proyecto (para la barra sencilla de la tarjeta).
      // COVER_P: URL firmada de la foto de portada, si hay una subida.
      var FAM_P = {}, FIRM_P = {}, COVER_P = {};
      // COMPRADOR_ID_POR_CONTRATO: contrato_id -> client_id del Adquiriente I,
      // para el enlace directo a /compradores/ de cada parcela (11-sep-2026).
      var COMPRADOR_ID_POR_CONTRATO = {};
      var MOLDE = null, MOLDE_ENLACE = null, MOLDE_FAQ = null, MOLDE_DOC = null, MOLDE_UNIDAD = null;
      // Las unidades del proyecto abierto, por id, tal y como se pintaron.
      // Es lo que lee el editor del parcelario (editores.js) para abrir el
      // formulario ya relleno. Se vacía en cada repintado del cajón.
      var UNIDADES_CAJON = {};
      // Mismo patrón, para los enlaces/documentos/FAQ del proyecto abierto
      // (S11.1, 22-sep-2026): el editor de editores.js lee de aquí para abrir
      // "Editar enlace"/"Editar FAQ" con la fila ya rellena, sin una consulta
      // nueva por cada clic.
      var DOCUMENTOS_CAJON = {};
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
        pon('d-pct', d.cartera ? '(' + Math.round(cob / d.cartera * 100) + '%)' : '(—)');
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
          el.textContent = Math.round(pct) + '% de ' + umbral + '%' +
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
          pon('d-' + clave + '-pct', cartera ? Math.round(firmPct) + '% firmado' + (vePropio ? '' : ' (tuyo)') : 'sin cartera registrada');
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
          pon('d-pct2', 'Recaudado ' + (d.cartera ? Math.round(cob / d.cartera * 100) : 0) + '%' + (vePropio ? '' : ' (tuyo)'));
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
        /* S11.5 (22-sep-2026): 'portada' (la foto de fondo de la tarjeta, ya se
           ve en el Expediente de arriba y en la propia rejilla) queda fuera de
           las tres listas — antes colaba como si fuera un enlace de
           documentación, sin ningún enlace real detrás. Y un documento SUBIDO
           como fichero (tiene `path`; el CHECK de la tabla exige que `path` y
           `url` sean mutuamente excluyentes salvo en una FAQ) se separa de los
           enlaces de verdad, en su propia pestaña "Documentos" — antes se
           mezclaban indistinguibles y sin forma de abrirse (ver S11.2).
           Los `general` (documentos de la EMPRESA sin proyecto real detrás —
           NPWP, Akta…, 18-sep-2026) quedan fuera A PROPÓSITO: este cajón es la
           documentación DE ESTE proyecto; mostrarlos aquí los repetiría
           idénticos en cada proyecto de la cartera sin ningún dato que los
           distinga. Siguen viéndose en /intranet/documentacion/, que no cambia. */
        var noPortada = docsEl.filter(function (d2) { return d2.categoria !== 'portada'; });
        var enl = noPortada.filter(function (d2) { return d2.categoria !== 'faq' && !d2.path; });
        var docs = noPortada.filter(function (d2) { return d2.categoria !== 'faq' && !!d2.path; });
        var faq = noPortada.filter(function (d2) { return d2.categoria === 'faq'; });
        /* Lo que "Editar enlace"/"Editar FAQ" (editores.js) necesita para abrir
           con la fila ya rellena, sin una consulta nueva por cada clic — mismo
           patrón que UNIDADES_CAJON/window.LW_V4.unidades, arriba. */
        DOCUMENTOS_CAJON = {};
        docsEl.forEach(function (d2) { DOCUMENTOS_CAJON[d2.id] = d2; });
        window.LW_V4.documentos = DOCUMENTOS_CAJON;
        /* Quién ve editar/borrar en cada fila (S11.1): editar pide
           puede('documentacion') (misma llave que el alta), borrar pide
           es_super_admin() — la policy DELETE de `documentos_proyecto` es más
           estricta que la de UPDATE. Pintarlo mal no abre un agujero (RLS
           sigue mandando), pero un botón que va a fallar SIEMPRE por permiso
           es peor que no pintarlo: parece un fallo del sistema, no un límite
           de rol. */
        var fichaDoc = window.LW_V4.ficha;
        var puedeEditarDoc = !!fichaDoc && (fichaDoc.rol === 'super_admin' || (fichaDoc.herramientas || []).indexOf('documentacion') !== -1);
        var puedeBorrarDoc = !!window.LW_V4.esSuperAdmin;
        var pintaAccionesDoc = function (f) {
          var be = f.querySelector('[data-doc-editar]'), bb = f.querySelector('[data-doc-borrar]');
          if (be) be.classList.toggle('hidden', !puedeEditarDoc);
          if (bb) bb.classList.toggle('hidden', !puedeBorrarDoc);
        };
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
            f.setAttribute('data-doc-id', d2.id);
            var p3 = function (k, v2) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v2; };
            p3('en-titulo', d2.titulo || 'Enlace');
            p3('en-meta', (d2.categoria || '—') + (d2.visible_portal ? ' · visible al comprador' : '') + (d2.confidencial ? ' · confidencial' : ''));
            var a2 = f.querySelector('a');
            if (a2) { if (d2.url) a2.href = d2.url; else { a2.removeAttribute('href'); a2.style.cursor = 'default'; } }
            pintaAccionesDoc(f);
            cajaE.appendChild(f);
          });
        }
        /* Documentos SUBIDOS como fichero (S11.2/S11.5): sin edición/borrado
           desde aquí a propósito (fuera del alcance de S11 — hoy no hay alta
           de fichero suelto en v4, solo la portada del proyecto), pero SÍ con
           forma de abrirse: `createSignedUrl` al pulsar, TTL corto, mismo
           patrón que ya usa esta pantalla para las portadas de la rejilla
           (createSignedUrls en lote, más abajo). El bucket 'documentacion' es
           privado — nunca se marca público para "arreglar" un 403. */
        var cajaD = document.getElementById('d-documentos');
        if (!MOLDE_DOC && cajaD && cajaD.firstElementChild) MOLDE_DOC = cajaD.firstElementChild.cloneNode(true);
        if (cajaD && MOLDE_DOC) {
          var mD = MOLDE_DOC.cloneNode(true);
          cajaD.innerHTML = '';
          if (!docs.length) cajaD.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Este proyecto no tiene documentos subidos.</p>';
          docs.forEach(function (d2) {
            var f = mD.cloneNode(true);
            f.setAttribute('data-doc-id', d2.id);
            var p3 = function (k, v2) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v2; };
            p3('dc-titulo', d2.titulo || 'Documento');
            var tam = (typeof d2.bytes === 'number' && d2.bytes > 0) ? ' · ' + Math.round(d2.bytes / 1024) + ' KB' : '';
            p3('dc-meta', (d2.categoria || '—') + tam + (d2.confidencial ? ' · confidencial' : ''));
            cajaD.appendChild(f);
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
            f.setAttribute('data-doc-id', d2.id);
            var p3 = function (k, v2) { var e = f.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v2; };
            p3('fq-pregunta', d2.titulo || 'Pregunta');
            p3('fq-respuesta', d2.descripcion || '—');
            pintaAccionesDoc(f);
            // Legal (revisión previa, 23-sep-2026): fuera de la caja de cuentas
            // se ven más — cada una dice que es interna, y si falta respuesta
            var marca = document.createElement('span');
            marca.style.cssText = 'display:inline-block;margin-top:4px;font-size:10.5px;font-weight:600;letter-spacing:.04em;color:#8A6A34';
            marca.textContent = (d2.descripcion ? '' : 'Sin responder · ') + 'Confidencial — interno, no compartir con compradores';
            var det = f.querySelector('details'); if (det) det.appendChild(marca);
            cajaF.appendChild(f);
          });
        }
        pintaDeckFaq(sb, elegido);
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
            uu.forEach(function (u, idxUnidad) {
              var f = base.cloneNode(true);
              // Orden NATURAL (S10.5, 22-sep-2026): `uu` ya llega ordenada por
              // `codigo_orden` desde la base — se guarda el índice para poder
              // volver a él tras ordenar por otro criterio, sin una segunda
              // consulta ni reordenar a mano por texto (SH-10 antes que SH-2).
              f.setAttribute('data-orden-natural', idxUnidad);
              // `data-estado` con la CLAVE cruda (S10.5, hallazgo de code-review
              // 22-sep-2026): ordenar por "estado" tiene que seguir el orden
              // lógico de ESTADO_ETIQUETA (disponible→…→no_disponible), no el
              // alfabético del texto ya en mayúsculas que pinta la pastilla —
              // localeCompare sobre "BLOQUEADA/COBRADA/DISPONIBLE…" mezclaría
              // el progreso de venta con el orden del diccionario.
              f.setAttribute('data-estado', u.estado || '');
              pon('u-codigo', u.codigo, f);
              pon('u-tipo', u.modelo || tipoUnidad(u), f);
              /* Estado destacado (11-sep-2026) y reforzado el 14-sep-2026: la
                 pastilla sola no bastaba para leer una columna de parcelas de un
                 vistazo, así que el mismo color entra también por el filo
                 izquierdo de la tarjeta — que es lo que se ve al recorrer la
                 lista sin pararse a leer. Color y nombre salen de la fuente
                 única de arriba, la misma que pinta el punto de los chips. */
              var estadoColor = colorEstado(u.estado);
              var nota = f.querySelector('[data-lw="u-nota"]');
              if (nota) nota.textContent = etiquetaEstado(u.estado).toUpperCase();
              /* Tarjeta «B · banda de estado» (23-sep-2026, owner): el color del
                 estado pinta la cabecera entera, no una pastilla + filo. Todos los
                 colores de ESTADO_COLOR son oscuros: el texto blanco se lee. */
              var banda = f.querySelector('[data-lw="u-banda"]');
              if (banda) banda.style.background = estadoColor;
              else f.style.borderLeft = '4px solid ' + estadoColor;
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
            // S10.5: cambiar de proyecto reinicia el filtro/orden — si no, el
            // texto buscado en el proyecto anterior dejaría el nuevo con la
            // rejilla vacía en silencio, sin que nadie entienda por qué.
            var buscadorUds = document.getElementById('d-unidades-buscar');
            var ordenUds = document.getElementById('d-unidades-orden');
            if (buscadorUds) buscadorUds.value = '';
            if (ordenUds) ordenUds.value = 'codigo';
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
        pon('dp-tipo', u.modelo || tipoUnidad(u));
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
        /* El proyecto NO se oculta (23-sep-2026, owner): la parcela abre en un panel
           estrecho encima (estilo en proyectos/index.html) y el parcelario sigue
           detrás, en su sitio. Solo se sube el scroll del PANEL, no el del proyecto. */
        vd.classList.remove('hidden');
        vd.scrollTop = 0;
        var niebla = document.getElementById('cajon-niebla-parcela');
        if (niebla) niebla.classList.remove('hidden');
      }
      function volverAProyecto() {
        var vp = document.getElementById('cajon-vista-proyecto');
        var vd = document.getElementById('cajon-vista-parcela');
        if (vd) vd.classList.add('hidden');
        if (vp) vp.classList.remove('hidden');
        var niebla = document.getElementById('cajon-niebla-parcela');
        if (niebla) niebla.classList.add('hidden');
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

      /* Las cifras de UN proyecto tal y como las enseñan las tres vistas
         (rejilla, tabla, carpetas). Un solo sitio que las calcula: si la tabla
         las sacara por su cuenta, el día que cambie el criterio de la rejilla
         las dos dirían cosas distintas del mismo proyecto. */
      function cifrasProyecto(p) {
        var d = POR_P[p.nombre] || { t: 0, disp: 0, vend: 0, cartera: 0, porEstado: {} };
        var cob = COB_P[p.nombre] || 0;
        var firmado = FIRM_P[p.nombre] || 0;
        var cobPct = d.cartera ? Math.min(100, cob / d.cartera * 100) : 0;
        var firmPct = d.cartera ? Math.min(100, firmado / d.cartera * 100) : 0;
        return {
          d: d, cob: cob, cobPct: cobPct, firmPct: firmPct,
          pctTxt: d.cartera ? Math.round(cob / d.cartera * 100) + '% cobrado' + (esMiProyecto(p) ? '' : ' (tuyo)') : 'sin cartera',
          badge: d.t === 0 ? 'Sin inventario' : (d.disp ? 'Con disponibles' : 'Todo asignado'),
          /* Color de la etiqueta (owner 23-sep-2026: «todas tienen el mismo color»). La
             plantilla traía bg-territorial-green fijo. Sale de la paleta única de estados
             de parcela: con disponibles = disponible, todo asignado = vendida, sin
             inventario = fuera de venta. */
          badgeColor: d.t === 0 ? ESTADO_COLOR.no_disponible : (d.disp ? ESTADO_COLOR.disponible : ESTADO_COLOR.vendida)
        };
      }
      // Barra de dos colores (oscuro = cobrado, claro = firmado sin cobrar) en
      // HTML, para las vistas que se pintan por cadena (tabla, carpetas).
      function barraHtml(c, alto) {
        return '<div class="w-full bg-surface-container-high rounded-full overflow-hidden flex" style="height:' + (alto || 6) + 'px">' +
          '<div class="bg-fiduciary-green h-full" style="width:' + c.cobPct + '%"></div>' +
          '<div class="bg-soft-canopy h-full" style="width:' + Math.max(0, c.firmPct - c.cobPct) + '%"></div></div>';
      }
      function vacioHtml(extra) {
        return '<p class="' + extra + ' p-6 text-[14px] text-outline">' +
          esc(PS.length ? 'Ningún proyecto coincide con el filtro.' : 'Todavía no hay proyectos dados de alta.') + '</p>';
      }

      /* Vista TABLA (23-sep-2026): una fila por proyecto con las mismas cifras
         que la tarjeta. Es la vista densa — la de «ver muchos a la vez». */
      function renderizarTabla(lista) {
        var caja = document.getElementById('projects-tabla');
        if (!caja) return;
        if (!lista.length) { caja.innerHTML = vacioHtml(''); return; }
        var th = function (t, der) {
          return '<th class="px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wider text-outline whitespace-nowrap ' +
            (der ? 'text-right' : 'text-left') + '">' + esc(t) + '</th>';
        };
        caja.innerHTML = '<table class="w-full text-[13px] tabular-nums">' +
          '<thead class="bg-surface-container-low border-b border-warm-border"><tr>' +
            th('Proyecto') + th('Ubicación') + th('Estado') + th('Parcelas', 1) + th('Vendidas', 1) + th('Disp.', 1) +
            th('Cartera', 1) + th('Cobrado', 1) + th('Pendiente', 1) + th('Recaudación') +
          '</tr></thead><tbody>' +
          lista.map(function (p) {
            var c = cifrasProyecto(p), d = c.d;
            return '<tr class="border-b border-warm-border/60 last:border-0 hover:bg-surface-container-low cursor-pointer" data-proy="' + esc(p.nombre) + '">' +
              '<td class="px-3 py-2 max-w-[260px]"><div class="font-semibold text-deep-lagoon truncate" title="' + esc(p.nombre) + '">' + esc(p.nombre) + '</div>' +
                '<div class="text-[11px] text-outline truncate">' + esc(p.parcela_master ? 'Máster ' + p.parcela_master : 'Sin parcela máster') + '</div></td>' +
              '<td class="px-3 py-2 text-on-surface-variant max-w-[180px] truncate" title="' + esc(p.resort || '') + '">' + esc(p.resort || '—') + '</td>' +
              '<td class="px-3 py-2"><span class="inline-block px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wide text-white whitespace-nowrap" style="background:' +
                colorProyEstado(p.estado) + '">' + esc(etiquetaProyEstado(p.estado)) + '</span></td>' +
              '<td class="px-3 py-2 text-right font-semibold text-volcanic-ash">' + d.t + '</td>' +
              '<td class="px-3 py-2 text-right" style="color:' + colorEstado('vendida') + '">' + d.vend + '</td>' +
              '<td class="px-3 py-2 text-right" style="color:' + colorEstado('disponible') + '">' + d.disp + '</td>' +
              '<td class="px-3 py-2 text-right whitespace-nowrap text-volcanic-ash">' + esc(fmt(d.cartera, 'EUR')) + '</td>' +
              '<td class="px-3 py-2 text-right whitespace-nowrap font-semibold text-fiduciary-green">' + esc(fmt(c.cob, 'EUR')) + '</td>' +
              '<td class="px-3 py-2 text-right whitespace-nowrap text-on-surface-variant">' + esc(fmt(d.cartera - c.cob, 'EUR')) + '</td>' +
              '<td class="px-3 py-2 min-w-[140px]"><div class="flex items-center gap-2"><div class="flex-1">' + barraHtml(c, 6) + '</div>' +
                '<span class="text-[11px] text-fiduciary-green font-semibold whitespace-nowrap">' +
                esc(d.cartera ? Math.round(c.cob / d.cartera * 100) + '%' : '—') + '</span></div></td>' +
            '</tr>';
          }).join('') + '</tbody></table>';
      }

      /* Vista CARPETAS (23-sep-2026): los proyectos agrupados por UBICACIÓN
         (`proyectos.resort`), una carpeta por sitio con su total. La rejilla ya
         es «una tarjeta por proyecto»; repetirla con otro icono no aportaba
         nada — lo que no se ve en ninguna otra vista es cuánto hay en cada
         sitio. Orden de las carpetas: el del primer proyecto de cada una en PS
         (W, S, G…, lwOrdenProyectos), y dentro, ese mismo orden. */
      function renderizarCarpetas(lista) {
        var caja = document.getElementById('projects-carpetas');
        if (!caja) return;
        if (!lista.length) { caja.innerHTML = vacioHtml('col-span-full'); return; }
        var grupos = [], porClave = {};
        lista.forEach(function (p) {
          var k = (p.resort || '').trim() || 'Sin ubicación asignada';
          if (!porClave[k]) { porClave[k] = { nombre: k, ps: [], t: 0, disp: 0, cartera: 0, cob: 0 }; grupos.push(porClave[k]); }
          var g = porClave[k], c = cifrasProyecto(p);
          g.ps.push(p); g.t += c.d.t; g.disp += c.d.disp; g.cartera += c.d.cartera; g.cob += c.cob;
        });
        caja.innerHTML = grupos.map(function (g) {
          return '<section class="bg-surface-container-lowest rounded-xl border border-warm-border shadow-sm overflow-hidden min-w-0">' +
            '<header class="px-4 py-3 bg-surface-container-low border-b border-warm-border flex items-start justify-between gap-3">' +
              '<div class="flex items-center gap-2 min-w-0"><span class="material-symbols-outlined text-[20px] text-territorial-green shrink-0">folder_open</span>' +
                '<div class="min-w-0"><div class="font-semibold text-[15px] text-deep-lagoon truncate" title="' + esc(g.nombre) + '">' + esc(g.nombre) + '</div>' +
                '<div class="text-[11px] text-outline">' + g.ps.length + (g.ps.length === 1 ? ' proyecto' : ' proyectos') +
                  ' · ' + g.t + ' parcelas · ' + g.disp + ' disp.</div></div></div>' +
              '<div class="text-right shrink-0 tabular-nums"><div class="text-[13px] font-bold text-fiduciary-green">' + esc(fmt(g.cob, 'EUR')) + '</div>' +
                '<div class="text-[11px] text-outline">de ' + esc(fmt(g.cartera, 'EUR')) + '</div></div>' +
            '</header>' +
            '<ul class="divide-y divide-warm-border/60">' + g.ps.map(function (p) {
              var c = cifrasProyecto(p);
              return '<li class="px-4 py-2 hover:bg-surface-container-low cursor-pointer flex items-center gap-3 min-w-0" data-proy="' + esc(p.nombre) + '">' +
                '<div class="min-w-0 flex-1"><div class="text-[13px] font-semibold text-volcanic-ash truncate" title="' + esc(p.nombre) + '">' + esc(p.nombre) + '</div>' +
                  '<div class="text-[11px] text-outline truncate">' + c.d.t + ' uds · ' + c.d.vend + ' vendidas · ' + c.d.disp + ' disp.</div></div>' +
                '<div class="w-28 shrink-0">' + barraHtml(c, 5) +
                  '<div class="text-[10px] text-right text-fiduciary-green font-semibold mt-0.5 whitespace-nowrap">' + esc(c.pctTxt) + '</div></div>' +
              '</li>';
            }).join('') + '</ul></section>';
        }).join('');
      }

      function pintaResumen(filtrados, desde, hasta) {
        var resumen = document.getElementById('resumen-listado');
        if (!resumen) return;
        resumen.textContent = filtrados.length
          ? 'Mostrando ' + (desde + 1) + '–' + hasta + ' de ' + filtrados.length +
            (filtrados.length !== PS.length ? ' proyectos (filtrado de ' + PS.length + ' en total)' : (filtrados.length === 1 ? ' proyecto activo' : ' proyectos activos'))
          : (PS.length ? 'Ningún proyecto coincide con este filtro (' + PS.length + ' en total).' : 'Todavía no hay proyectos.');
      }

      /* Rejilla + resumen + paginación de la página actual, sobre el filtro
         vigente — o la tabla o las carpetas, según EST.vista (esas dos enseñan
         TODO lo filtrado, sin paginar: son las vistas para ver muchos). Nunca
         vuelve a pedir datos: PS/POR_P/COB_P ya están en memoria desde la
         carga inicial. */
      function renderizar() {
        var grid = document.getElementById('projects-grid');
        if (!grid) return;
        if (!MOLDE) MOLDE = grid.firstElementChild ? grid.firstElementChild.cloneNode(true) : null;
        if (!MOLDE) return;

        var filtrados = proyectosFiltrados();
        var vista = EST.vista;
        grid.classList.toggle('hidden', vista !== 'rejilla');
        var cajaT = document.getElementById('projects-tabla'), cajaC = document.getElementById('projects-carpetas');
        if (cajaT) cajaT.classList.toggle('hidden', vista !== 'tabla');
        if (cajaC) cajaC.classList.toggle('hidden', vista !== 'carpetas');
        var pagEl = document.getElementById('paginacion');
        if (pagEl) pagEl.classList.toggle('hidden', vista !== 'rejilla');
        if (vista === 'tabla' || vista === 'carpetas') {
          if (vista === 'tabla') renderizarTabla(filtrados); else renderizarCarpetas(filtrados);
          pintaResumen(filtrados, 0, filtrados.length);
          return;
        }

        var totalPaginas = Math.max(1, Math.ceil(filtrados.length / PAGE_SIZE));
        if (EST.pag > totalPaginas) EST.pag = totalPaginas;
        var desde = (EST.pag - 1) * PAGE_SIZE;
        var pagina = filtrados.slice(desde, desde + PAGE_SIZE);

        grid.innerHTML = '';
        if (!pagina.length) grid.innerHTML = vacioHtml('col-span-full');
        pagina.forEach(function (p) {
          var c = MOLDE.cloneNode(true);
          var cf = cifrasProyecto(p), d = cf.d;
          var sub = p.parcela_master ? 'Parcela máster ' + p.parcela_master + (p.parcela_master_m2 ? ' · ' + p.parcela_master_m2 + ' m²' : '') : 'Sin parcela máster registrada';
          pon('nombre', p.nombre, c);
          pon('sitio', p.resort || 'Sin ubicación asignada', c);
          pon('sub', sub, c);
          // title con el texto entero: la tarjeta lo corta con «…» (truncate)
          // para que nada se salga, y así no se pierde al pasar el ratón.
          [['nombre', p.nombre], ['sitio', p.resort || ''], ['sub', sub]].forEach(function (x) {
            var e = $(x[0], c); if (e && x[1]) e.title = x[1];
          });
          pon('badge', cf.badge, c);
          var eBadge = $('badge', c); if (eBadge) eBadge.style.backgroundColor = cf.badgeColor;
          pon('uds', String(d.t), c);
          pon('vendidas', d.vend + ' vendidas', c);
          pon('disp', d.disp + ' disp.', c);
          pon('cobrado', fmt(cf.cob, 'EUR'), c);
          pon('pend', fmt(d.cartera - cf.cob, 'EUR'), c);
          pon('total', 'de ' + fmt(d.cartera, 'EUR'), c);
          // LAW-186: "tuyo" avisa de que cob es SOLO lo cobrado por quien mira,
          // no lo del proyecto entero, cuando no es su manager ni admin — ver
          // esMiProyecto() más arriba.
          pon('pct', cf.pctTxt, c);
          // Dos colores en la misma barra (11-sep-2026): oscuro = cobrado,
          // claro = firmado (bloqueado=true) pero todavía sin cobrar. FIRM_P
          // es el firmado de Parcela+Construcción combinado — el desglose por
          // familia vive en el cajón, donde hay sitio para dos barras.
          var bCob = c.querySelector('[data-barra="cobrado"]'), bFir = c.querySelector('[data-barra="firmado"]');
          if (bCob) bCob.style.width = cf.cobPct + '%';
          if (bFir) bFir.style.width = Math.max(0, cf.firmPct - cf.cobPct) + '%';
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

        pintaResumen(filtrados, desde, Math.min(desde + PAGE_SIZE, filtrados.length));
        var cajaPag = document.getElementById('pag-paginas');
        if (cajaPag) {
          cajaPag.innerHTML = '';
          for (var i = 1; i <= totalPaginas; i++) {
            (function (n) {
              var b = document.createElement('button');
              b.type = 'button'; b.textContent = String(n);
              b.setAttribute('data-real', '');
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

      /* Filtro/orden de unidades DENTRO del cajón (S10.5, 22-sep-2026):
         100% client-side sobre las filas que ya pintó abrirCajon() — sin
         consulta nueva. Los dos controles son DOM estático (no dependen de
         qué proyecto esté abierto), así que se cablean UNA vez, igual que
         wireTabsDoc/wireControles; cada disparo relee `#d-unidades` en el
         momento, así que siempre actúa sobre lo que esté pintado entonces. */
      function wireFiltroUnidadesCajon() {
        var caja = document.getElementById('d-unidades');
        var buscador = document.getElementById('d-unidades-buscar');
        var orden = document.getElementById('d-unidades-orden');
        if (!caja || !buscador || !orden) return;
        var textoDeFila = function (f) {
          var t = function (k) { var e = f.querySelector('[data-lw="' + k + '"]'); return e ? e.textContent : ''; };
          return (t('u-codigo') + ' ' + t('u-tipo') + ' ' + t('u-comprador-link') + ' ' + t('u-contrato-link') + ' ' + t('u-agente')).toLowerCase();
        };
        var aplicaFiltro = function () {
          var q2 = buscador.value.toLowerCase().trim();
          Array.prototype.forEach.call(caja.children, function (f) {
            if (!f.querySelector) return;
            f.classList.toggle('hidden', !!q2 && textoDeFila(f).indexOf(q2) === -1);
          });
        };
        var aplicaOrden = function () {
          var criterio = orden.value;
          var filas = Array.prototype.slice.call(caja.children).filter(function (f) { return f.hasAttribute && f.hasAttribute('data-orden-natural'); });
          var val = function (f, k) { var e = f.querySelector('[data-lw="' + k + '"]'); return e ? e.textContent.trim() : ''; };
          if (criterio === 'codigo') {
            // Vuelve al orden con el que abrirCajon() las pintó (codigo_orden
            // de la base, orden NATURAL — no alfabético): guardado en cada
            // fila al pintarla, para no reordenar por texto (SH-10 antes que
            // SH-2 es el fallo que esto evita).
            filas.sort(function (a, b) { return Number(a.getAttribute('data-orden-natural')) - Number(b.getAttribute('data-orden-natural')); });
          } else if (criterio === 'estado') {
            // Orden LÓGICO (disponible→reservada→bloqueada→vendida→cobrada→
            // no_disponible, el mismo de ESTADO_ETIQUETA y de los chips de
            // arriba), no alfabético del texto ya en mayúsculas de la
            // pastilla — corregido en code-review (22-sep-2026): ordenar por
            // texto mezclaba BLOQUEADA/COBRADA/DISPONIBLE sin seguir el
            // progreso real de venta.
            var claves = Object.keys(ESTADO_ETIQUETA);
            var rango = function (f) {
              var i = claves.indexOf(f.getAttribute('data-estado') || '');
              return i === -1 ? claves.length : i;
            };
            filas.sort(function (a, b) { return rango(a) - rango(b); });
          } else if (criterio === 'comprador') {
            filas.sort(function (a, b) { return val(a, 'u-comprador-link').localeCompare(val(b, 'u-comprador-link')); });
          }
          filas.forEach(function (f) { caja.appendChild(f); });
        };
        buscador.oninput = aplicaFiltro;
        orden.onchange = function () { aplicaOrden(); aplicaFiltro(); };
      }

      /* Abrir un documento SUBIDO como fichero (S11.2, 22-sep-2026): mismo
         patrón que ya usa esta pantalla para el PDF firmado y el justificante
         (`createSignedUrl`, TTL corto, `window.open` dentro del `.then`) —
         nunca el bucket 'documentacion' hecho público. Delegado en el
         contenedor ESTÁTICO (`#d-documentos`): datos.js reemplaza sus filas
         en cada apertura del cajón, así que un listener por fila se perdería
         al abrir el siguiente proyecto. */
      function wireDocumentosAbrir(sb) {
        var caja = document.getElementById('d-documentos');
        if (!caja) return;
        caja.addEventListener('click', function (ev) {
          var f = ev.target.closest && ev.target.closest('[data-doc-abrir]');
          if (!f) return;
          var id = f.getAttribute('data-doc-id');
          var d2 = DOCUMENTOS_CAJON[id];
          if (!d2 || !d2.path) return;
          var meta = f.querySelector('[data-lw="dc-meta"]');
          var metaOrig = meta ? meta.textContent : '';
          if (meta) meta.textContent = 'Abriendo…';
          sb.storage.from('documentacion').createSignedUrl(d2.path, 300).then(function (u) {
            if (meta) meta.textContent = metaOrig;
            if (u.error || !u.data) { toastMal('No se pudo abrir: ' + (u.error && u.error.message || 'sin URL')); return; }
            window.open(u.data.signedUrl, '_blank', 'noopener');
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
        /* Rejilla / Tabla / Carpetas (23-sep-2026). Mismo patrón que los chips:
           las clases de activo/inactivo se leen del propio HTML. */
        var contV = document.getElementById('vistas-proyectos');
        var clasesV = chipClases(contV);
        marcaChip(contV, 'data-vista', EST.vista, clasesV);
        if (contV) contV.querySelectorAll('[data-vista]').forEach(function (b) {
          b.addEventListener('click', function (ev) {
            ev.stopPropagation();
            EST.vista = b.getAttribute('data-vista');
            try { sessionStorage.setItem(CLAVE_VISTA, EST.vista); } catch (_) {}
            marcaChip(contV, 'data-vista', EST.vista, clasesV);
            renderizar();
          });
        });
        // Tabla y carpetas se repintan enteras en cada filtro: el clic se
        // delega en su contenedor (estático), nunca en la fila.
        ['projects-tabla', 'projects-carpetas'].forEach(function (id) {
          var caja = document.getElementById(id);
          if (caja) caja.addEventListener('click', function (ev) {
            var fila = ev.target.closest('[data-proy]');
            if (fila) abrirCajon(fila.getAttribute('data-proy'), { mostrar: true });
          });
        });
        /* Escape cierra el proyecto abierto (23-sep-2026): a pantalla completa
           ya no hay velo al que pulsar fuera. Si hay un editor o un diálogo
           encima, Escape es suyo (dialogo.js lo frena con stopPropagation; el
           editor de editores.js solo existe en el DOM mientras está abierto). */
        document.addEventListener('keydown', function (ev) {
          if (ev.key !== 'Escape' || ev.defaultPrevented) return;
          if (document.getElementById('lw-editor') || document.querySelector('.lw-dlg-fondo.abierto')) return;
          var cajon = document.getElementById('cajon-detalle');
          if (!cajon || cajon.classList.contains('translate-x-full')) return;
          var vd = document.getElementById('cajon-vista-parcela');
          if (vd && !vd.classList.contains('hidden')) { volverAProyecto(); return; }
          cajon.classList.add('translate-x-full');
          var velo = document.getElementById('cajon-backdrop'); if (velo) velo.classList.add('hidden');
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
        // `slug` (22-sep-2026, S10.3): lo lee y lo escribe el editor nativo del
        // Investor Deck — sin él "Investor Deck" no podría mostrar la URL
        // pública ni ofrecer cambiarlo.
        q(sb.from('proyectos').select('id,nombre,slug,resort,parcela_master,parcela_master_m2,fecha_entrega_estimada_proyecto,fecha_entrega_estimada_fijada_en,estado,pct_minimo_inicio').eq('activo', true).order('nombre'), 'proyectos'),
        q(sb.from('unidades').select('proyecto,estado,moneda,precio,precio_suelo,precio_construccion'), 'unidades'),
        /* La RPC de EQUIPO, nunca `.from('facturas')`. `facturas` tiene RLS por
           agente (`es_suyo`), así que una lectura directa devuelve solo «lo mío»
           —menos filas, sin ningún error— y el cobrado de la cartera saldría
           bajo para todo el que no sea super admin. Está avisado en la cabecera
           de este fichero y aun así caí en ello al escribir esta pantalla. */
        q(sb.rpc('facturas_equipo').select('proyecto_id,proyecto_nombre,tipo,total,moneda,anulada'), 'facturas'),
        // `path` (S11.2/S11.5, 22-sep-2026): sin ella no hay forma de distinguir
        // un documento SUBIDO (con fichero, sin `url`) de un enlace, ni de
        // abrirlo — el cajón los mezclaba indistinguibles y sin forma de
        // abrirse. `mime`/`bytes` solo para el meta de la fila (S11.2).
        // `general` (18-sep-2026): documentos de la EMPRESA sin proyecto real
        // detrás (NPWP, Akta…) — sin este campo `d2.proyecto === elegido.nombre`
        // los deja fuera siempre, invisibles en TODOS los proyectos.
        q(sb.from('documentos_proyecto').select('id,proyecto,categoria,titulo,descripcion,url,path,mime,bytes,carpeta,visible_portal,confidencial,publicado_investor_deck,general,creado_en'), 'documentación'),
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
        pon('k-cobrado-pie', facturado ? Math.round(cobrado / facturado * 100) + '% de lo facturado (' + fmt(facturado, 'EUR') + ')' : 'sin facturas emitidas');
        pon('k-pendiente', fmt(tot.cartera - cobrado, 'EUR'));
        pon('k-pendiente-pie', 'Cartera menos lo cobrado');
        pon('k-suelo-v', fmt(tot.suelo, 'EUR'));
        pon('k-obra', fmt(tot.obra, 'EUR'));
        // pintaMixSueloObra (23-sep-2026): el peso de cada familia es la cifra
        // grande y la barra; los importes, debajo de su lado.
        var base = tot.suelo + tot.obra;
        var pctSuelo = base ? Math.round(tot.suelo / base * 100) : 0;
        pon('k-suelo-pct', base ? pctSuelo + '%' : '—');
        pon('k-obra-pct', base ? (100 - pctSuelo) + '%' : '—');
        var bS = document.querySelector('[data-barra="k-suelo"]'), bO = document.querySelector('[data-barra="k-obra"]');
        if (bS) bS.style.width = (base ? tot.suelo / base * 100 : 0) + '%';
        if (bO) bO.style.width = (base ? tot.obra / base * 100 : 0) + '%';

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
        wireFiltroUnidadesCajon();
        wireDocumentosAbrir(sb);
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
        q(sb.from('modelos').select('id,slug,nombre,dormitorios,banos,villa_m2,terraza_m2,descripcion,precio_construccion,moneda,publicado,activo,renders_pendientes,alcance,acabados,notas,orden').order('orden', { ascending: true, nullsFirst: false }), 'modelos'),
        // `modelo` (texto): para avisar de las unidades que NOMBRAN un modelo sin estar
        // enlazadas a él (revisión previa #56: 81 «Dream» de Sumba Hills).
        q(sb.from('unidades').select('modelo_id,modelo,proyecto,proyecto_id'), 'unidades por modelo'),
        q(sb.from('modelo_documentos').select('id,modelo_id,nombre,path,tipo,tamano_bytes,subido_en,visible_portal,techo_clave'), 'documentos de modelo'),
        // «Sin catalogar» (S12, 22-sep-2026): view ya existente (migración
        // 20260907053801) que agrupa unidades cuyo texto libre `modelo` no
        // enlaza a ningún modelo_id — se enseña, no se «arregla» sola.
        q(sb.from('modelos_sin_catalogar').select('*'), 'modelos sin catalogar'),
        /* LAW-273 (23-sep-2026): lo que hace falta para avisar de que la
           «inversión base» de una previsión del deck se ha quedado vieja —
           mismo cálculo que la clásica: suelo de la parcela más barata del
           proyecto + construcción del modelo allí (modelos_villa, y si no, el
           del catálogo). El aviso va en la FILA del proyecto, no dentro del
           formulario: nadie abre doce fichas a comprobar. */
        q(sb.from('deck_forecast').select('modelo_id,proyecto_id,inversion_base'), 'previsiones del deck'),
        q(sb.from('modelos_villa').select('id,modelo_id,modelo,proyecto,proyecto_id,precio_construccion,moneda'), 'precios por proyecto'),
        q(sb.from('unidades').select('id,proyecto,precio_suelo').not('precio_suelo', 'is', null), 'suelo del inventario'),
        /* Fotos del deck (23-sep-2026, owner: «no puedo ver sus fotos»): la
           tarjeta y la ficha enseñan las que ya hay. Bucket `deck` PÚBLICO (lo
           que se sube ahí ya está publicado, ver deck_fotos.js), así que la URL
           pública es la correcta, no una firmada. Gestionarlas sigue siendo
           «Fotos del deck» (pieza compartida, no se duplica aquí). */
        q(sb.from('deck_fotos').select('modelo_id,path,uso,orden').eq('ambito', 'modelo').order('uso').order('orden'), 'fotos del deck'),
        // Ficha por bloques (23-sep-2026): techos y extras se VEN en la ficha,
        // no solo dentro del editor. Tablas pequeñas: se cargan enteras.
        q(sb.from('modelo_techos').select('id,modelo_id,clave,nombre,precio_ahora,precio_2027,orden'), 'techos'),
        q(sb.from('extras').select('id,nombre,orden').eq('activo', true).order('orden', { ascending: true, nullsFirst: false }), 'extras'),
        q(sb.from('modelo_extras').select('id,modelo_id,extra_id,precio,moneda,disponible'), 'extras por modelo')
      ]).then(function (r) {
        var ms = r[0], us = r[1] || [], ds = r[2] || [], sinCat = r[3] || [];
        var FC = r[4] || [], MV = r[5] || [], SUELO = r[6] || [], FOTOS = r[7] || [];
        var TECHOS = r[8] || [], EXTRAS = r[9] || [], MEX = r[10] || [];
        var fotosModelo = {};
        FOTOS.forEach(function (f) { if (f.modelo_id && f.path) (fotosModelo[f.modelo_id] = fotosModelo[f.modelo_id] || []).push(f); });
        var urlFoto = function (path) { return sb.storage.from('deck').getPublicUrl(path).data.publicUrl; };
        window.LW_V4 = window.LW_V4 || {};
        /* Compartida con el editor de la previsión (editores.js): una sola
           cuenta de «lo que debería ser» la base, no dos. */
        window.LW_V4.baseDeberia = function (m, proyectoNombre) {
          var ps = SUELO.filter(function (u) { return u.proyecto === proyectoNombre; });
          if (!ps.length) return null;
          var ref = ps.reduce(function (a, u) { return Number(u.precio_suelo) < Number(a.precio_suelo) ? u : a; });
          var mv = MV.filter(function (x) { return x.modelo_id === m.id && x.proyecto === proyectoNombre && x.precio_construccion != null; })[0];
          var c = mv ? Number(mv.precio_construccion) : (m.precio_construccion != null ? Number(m.precio_construccion) : null);
          if (c == null) return null;
          return { valor: Number(ref.precio_suelo) + c, refId: ref.id };
        };
        if (!ms) return;

        /* «Sin ficha tecnica» es el dato que de verdad manda en esta pantalla:
           un modelo sin dormitorios, banos ni superficie no puede heredar nada a
           la unidad ni publicarse. Se define por lo que falta, no por un estado
           que la tabla no tiene. */
        var sinFicha = function (m) {
          return m.dormitorios == null && m.banos == null && m.villa_m2 == null && m.terraza_m2 == null;
        };
        /* Estado con COLOR PROPIO (23-sep-2026, owner: «haz diferencia entre
           publicado, sin ficha, etc.»): antes los cuatro salían en la misma
           pastilla gris. Se decide en este orden — lo que más bloquea primero:
           inactivo (fuera del catálogo) > sin ficha (no puede heredar nada) >
           publicado (lo ve el comprador) > borrador. Los colores son los de los
           chips de filtro de arriba: lagoon = publicado, rojo = sin ficha. */
        var ESTADOS = {
          inactivo:  { t: 'Inactivo',  bg: 'transparent', fg: '#75786e', bd: '#c5c8bc' },
          sinficha:  { t: 'Sin ficha', bg: '#ffdad6',     fg: '#93000a', bd: '#ffdad6' },
          publicado: { t: 'Publicado', bg: '#104C4F',     fg: '#ffffff', bd: '#104C4F' },
          borrador:  { t: 'Borrador',  bg: '#F1EBDD',     fg: '#6b5a3a', bd: '#E4DCCB' }
        };
        var estadoDe = function (m) {
          return !m.activo ? 'inactivo' : sinFicha(m) ? 'sinficha' : m.publicado ? 'publicado' : 'borrador';
        };
        var pintaEstado = function (nodo, m) {
          if (!nodo) return;
          var e = ESTADOS[estadoDe(m)];
          nodo.textContent = e.t;
          nodo.style.background = e.bg; nodo.style.color = e.fg; nodo.style.border = '1px solid ' + e.bd;
          nodo.title = '';
        };
        var porModelo = {}, proyModelo = {}, proyModeloId = {};
        us.forEach(function (u) {
          if (!u.modelo_id) return;
          porModelo[u.modelo_id] = (porModelo[u.modelo_id] || 0) + 1;
          var d = proyModelo[u.modelo_id] = proyModelo[u.modelo_id] || {};
          var k = u.proyecto || 'Sin proyecto';
          d[k] = (d[k] || 0) + 1;
          // Previsión del deck (S12): id del proyecto para poder abrir su
          // editor — `deck_forecast` se guarda por (proyecto_id, modelo_id),
          // nunca por el nombre en texto.
          if (u.proyecto_id) {
            var pid = proyModeloId[u.modelo_id] = proyModeloId[u.modelo_id] || {};
            pid[k] = u.proyecto_id;
          }
        });
        var docsModelo = {};
        ds.forEach(function (d) { (docsModelo[d.modelo_id] = docsModelo[d.modelo_id] || []).push(d); });

        var activos = ms.filter(function (m) { return m.activo; }).length;
        var publicados = ms.filter(function (m) { return m.publicado; }).length;
        var faltan = ms.filter(sinFicha).length;
        /* «Sin fotos» se DERIVA de las fotos del deck (owner, 23-sep-2026). La
           columna `renders_pendientes` no es eso: en la web permite publicar la
           página de un modelo sin fotos (modelo/lib.php), y Trinity la tenía
           marcada con 11 fotos. */
        var sinFotos = function (m) { return !(fotosModelo[m.id] || []).length; };
        var sinRender = ms.filter(sinFotos).length;
        var enlazadas = Object.keys(porModelo).reduce(function (a, k) { return a + porModelo[k]; }, 0);

        pon('k-activos', String(activos));
        pon('k-total', String(ms.length));
        pon('k-activos-pie', enlazadas + ' unidades enlazadas a un modelo');
        pon('k-publicados', String(publicados));
        pon('k-publicados-pie', publicados ? 'los unicos que ve un comprador en la web' : 'ninguno visible fuera');
        pon('k-sinficha', String(faltan));
        pon('k-sinficha-pie', faltan ? 'sin dormitorios, banos ni superficie: no pueden heredar nada' : 'todos con ficha completa');
        pon('k-sinrender', String(sinRender));
        pon('k-sinrender-pie', sinRender ? 'sin ninguna foto en el deck' : 'todos tienen fotos');
        var bExp = botonConTexto(/Exportar cat[aá]logo/i);
        if (bExp) {
          bExp.setAttribute('data-real', '');
          bExp.addEventListener('click', function (ev) {
            ev.stopPropagation();
            exportaCSV('catalogo_modelos.csv',
              ['Modelo', 'Slug', 'Dormitorios', 'Baños', 'Villa m²', 'Terraza m²', 'Precio construcción', 'Moneda', 'Publicado', 'Activo', 'Publicar sin fotos', 'Fotos del deck', 'Unidades enlazadas'],
              ms.map(function (m) { return [m.nombre, m.slug, m.dormitorios, m.banos, m.villa_m2, m.terraza_m2, m.precio_construccion, m.moneda, m.publicado ? 'sí' : 'no', m.activo ? 'sí' : 'no', m.renders_pendientes ? 'sí' : 'no', (fotosModelo[m.id] || []).length, porModelo[m.id] || 0]; }));
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
          pintaEstado($('m-estado', c), m);
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
          c.setAttribute('data-sinrender', sinFotos(m) ? '1' : '0');
          // Buscador (S12): nombre/slug en minúsculas, listos para comparar
          // sin normalizar en cada tecla.
          c.setAttribute('data-nombre', (m.nombre || '').toLowerCase());
          c.setAttribute('data-slug', (m.slug || '').toLowerCase());
          var fs = fotosModelo[m.id] || [];
          var cab = c.firstElementChild;
          if (fs.length && cab) {
            cab.innerHTML = '';
            cab.style.cssText = 'padding:0;overflow:hidden;position:relative';
            var im = document.createElement('img');
            im.src = urlFoto(fs[0].path); im.alt = m.nombre || ''; im.loading = 'lazy';
            im.style.cssText = 'width:100%;height:100%;object-fit:cover;display:block';
            cab.appendChild(im);
            var nf = document.createElement('span');
            nf.textContent = fs.length + (fs.length === 1 ? ' foto' : ' fotos');
            nf.style.cssText = 'position:absolute;right:10px;bottom:10px;padding:2px 10px;border-radius:999px;background:rgba(27,28,25,.62);color:#fff;font:600 11px/18px sans-serif';
            cab.appendChild(nf);
          }
          /* «Sin fotos» se SOLAPA con los estados (un modelo puede estar
             publicado y sin fotos a la vez): va aparte, sobre la imagen. */
          if (sinFotos(m) && cab) {
            cab.style.position = 'relative';
            var sr = document.createElement('span');
            sr.textContent = 'Sin fotos';
            sr.style.cssText = 'position:absolute;left:10px;top:10px;padding:2px 10px;border-radius:999px;background:#BEB3A5;color:#2E3437;font:600 11px/18px sans-serif';
            cab.appendChild(sr);
          }
          if (!m.activo) c.style.opacity = '.6';   // fuera del catálogo: se ve, pero apagado
          c.setAttribute('data-modelo-id', m.id);
          c.style.cursor = 'pointer';
          /* Mismo flujo que /v4/proyectos/ (23-sep-2026, owner): la tarjeta
             —o su botón «Editar»— abre la FICHA DEL MODELO en el cajón
             lateral, sin recargar; editar datos, fotos y documentos están en su
             pie. La URL lleva ?modelo= para compartirla o recargar. Los
             editores leen LW_V4.modelo al hacer click, así que siguen al
             modelo abierto. */
          c.addEventListener('click', function (ev) { ev.stopPropagation(); abrirFicha(m); });
          grid.appendChild(c);
        });

        var chipsModelos = ['todos', 'publicados', 'sinficha', 'sinrender'].map(function (k) {
          var sp = document.querySelector('[data-lw="c-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);

        /* Chips + buscador (S12, 22-sep-2026): UN solo cableado, no dos que
           pisen su propio resultado. `cablearChipsFiltro` (usada en el resto
           de la suite) filtra solo por chip; aquí hace falta chip Y texto a
           la vez, así que en vez de llamarla y AÑADIR un segundo listener por
           encima (dos pasadas por la rejilla en cada click, y el resultado
           dependiendo de qué listener corra segundo — hallazgo de la
           autorevisión, 22-sep-2026), se cablea directo: un único listener
           por chip que pinta el estado activo y llama a la MISMA función de
           filtrado que usa el buscador. */
        var buscadorModelos = document.querySelector('input[type="search"]');
        var chipActivaModelos = 'todos';
        var aplicaFiltroModelos = function () {
          var texto = ((buscadorModelos && buscadorModelos.value) || '').trim().toLowerCase();
          Array.prototype.forEach.call(grid.children, function (fila) {
            if (!fila.getAttribute) return;
            var chipOk = chipActivaModelos === 'todos' || fila.getAttribute('data-' + chipActivaModelos) === '1';
            var nombre = fila.getAttribute('data-nombre') || '', slug = fila.getAttribute('data-slug') || '';
            var textoOk = !texto || nombre.indexOf(texto) !== -1 || slug.indexOf(texto) !== -1;
            fila.style.display = (chipOk && textoOk) ? '' : 'none';
          });
        };
        if (buscadorModelos) buscadorModelos.addEventListener('input', aplicaFiltroModelos);
        chipsModelos.forEach(function (btn) {
          btn.addEventListener('click', function (ev) {
            ev.stopPropagation();   // si no, maqueta.js la ve pasar y avisa «sin cablear»
            chipsModelos.forEach(function (b) {
              var on = b === btn;
              b.classList.toggle('bg-primary-container', on);
              b.classList.toggle('text-on-primary', on);
              b.classList.toggle('bg-surface-container-low', !on);
              b.classList.toggle('text-on-surface-variant', !on);
            });
            chipActivaModelos = btn.getAttribute('data-chip-clave') || 'todos';
            aplicaFiltroModelos();
          });
        });

        /* Aviso «sin catalogar» (S12, 22-sep-2026): unidades cuyo texto
           libre `modelo` no enlaza a ningún modelo_id — visible, no
           silencioso (mismo criterio que la clásica, sin «arreglarlo» solo:
           puede ser un modelo real pendiente de dar de alta). */
        if (sinCat.length) {
          var totalSinCat = sinCat.reduce(function (a, x) { return a + Number(x.unidades || 0); }, 0);
          var detalleSinCat = sinCat.map(function (x) {
            return x.proyecto + ' — «' + x.nombra_a + '»: ' + x.unidades + (x.unidades === 1 ? ' unidad' : ' unidades');
          }).join('; ');
          bandaNota(totalSinCat + (totalSinCat === 1 ? ' unidad nombra' : ' unidades nombran') +
            ' un modelo que no está en este catálogo (' + detalleSinCat + '). No suman en ninguna cifra de esta pantalla.', '#8A6A34');
        }

        /* --- ficha: la de ?modelo= o la que mas unidades arrastra --- */
        var pedido = new URLSearchParams(location.search).get('modelo');
        var elInicial = ms.filter(function (m) { return m.slug === pedido || m.nombre === pedido; })[0] ||
                 ms.slice().sort(function (a, b) { return (porModelo[b.id] || 0) - (porModelo[a.id] || 0); })[0];
        if (!elInicial) return;
        pintaFicha(elInicial);
        // Llegando con ?modelo= (enlace compartido, o recarga tras guardar) se
        // abre ESA ficha; una carga a secas deja el cajón cerrado, como Proyectos.
        if (pedido && elInicial && (elInicial.slug === pedido || elInicial.nombre === pedido)) mueveCajon(true);

        function mueveCajon(abrir) {
          var cajon = document.getElementById('cajon-detalle'), velo = document.getElementById('cajon-backdrop');
          if (cajon) cajon.classList.toggle('translate-x-full', !abrir);
          if (velo) velo.classList.toggle('hidden', !abrir);
          if (!abrir) { try { history.replaceState(null, '', location.pathname); } catch (e) {} }
        }
        function abrirFicha(m) {
          pintaFicha(m);
          var cuerpo = document.getElementById('cajon-cuerpo'); if (cuerpo) cuerpo.scrollTop = 0;
          try { history.replaceState(null, '', '?modelo=' + encodeURIComponent(m.slug || m.nombre)); } catch (e) {}
          mueveCajon(true);
        }
        var btnCerrar = document.querySelector('[data-lw-cerrar-cajon]');
        if (btnCerrar) btnCerrar.addEventListener('click', function (ev) { ev.stopPropagation(); mueveCajon(false); });
        var veloFicha = document.getElementById('cajon-backdrop');
        if (veloFicha) veloFicha.addEventListener('click', function () { mueveCajon(false); });
        /* Escape cierra la ficha, salvo que haya algo abierto ENCIMA (el editor,
           un diálogo o el gestor de fotos): ese Escape es suyo. */
        document.addEventListener('keydown', function (ev) {
          if (ev.key !== 'Escape' || ev.defaultPrevented) return;
          // `lw-cajon` es el panel de «Fotos del deck» (editores.js): su propio
          // Escape lo quita, por eso este listener va en CAPTURA — así se mira
          // antes de que desaparezca y no se cierran los dos de un golpe.
          if (document.getElementById('lw-editor') || document.getElementById('lw-cajon') || document.querySelector('.lw-dlg-fondo.abierto')) return;
          var cajon = document.getElementById('cajon-detalle');
          if (!cajon || cajon.classList.contains('translate-x-full')) return;
          mueveCajon(false);
        }, true);

        /* La ficha se pinta aquí y al pinchar una tarjeta (sin recargar). La
           cabecera es de esta pantalla; el cuerpo —los bloques editables— lo
           pinta ficha_modelo.js con los datos ya cargados (ninguna consulta
           más). */
        // Función y no `var`: pintaFicha() se llama más arriba (ficha inicial)
        // antes de que una `var` de aquí se hubiera asignado.
        function ctxFicha() {
          return {
            sb: sb, fmt: fmt, fFecha: fFecha, FC: FC, sinFicha: sinFicha,
            baseDeberia: window.LW_V4.baseDeberia,
            D: { villas: MV, techos: TECHOS, extras: EXTRAS, modeloExtras: MEX, docs: ds, fotos: fotosModelo, unidades: us }
          };
        }
        function pintaFicha(el) {
          window.LW_V4 = window.LW_V4 || {}; window.LW_V4.modelo = el;
          pintaGaleria(el);
          pon('d-nombre', el.nombre || '—');
          pon('d-slug', el.slug ? '/modelo/' + el.slug : 'sin dirección web');
          pintaEstado($('d-estado'), el);
          if (window.lwFichaModelo) window.lwFichaModelo.pintar(el, ctxFicha());
          else console.error('[v4] modelos: ficha_modelo.js no ha cargado');
        }

        /* Tira de fotos del deck en la ficha: solo mirar. Añadir, ordenar o
           borrar es «Fotos del deck» (deck_fotos.js); al cerrarlo, recargar
           la página trae lo nuevo. */
        function pintaGaleria(el) {
          var gal = document.getElementById('d-fotos');
          if (!gal) return;
          gal.innerHTML = '';
          var fs = fotosModelo[el.id] || [];
          if (!fs.length) {
            gal.innerHTML = '<p style="font:500 13px/1.5 sans-serif;color:#75786e;margin:0">Este modelo no tiene fotos en el deck. Súbelas con «Fotos del deck».</p>';
            return;
          }
          fs.forEach(function (f) {
            var a = document.createElement('a');
            a.href = urlFoto(f.path); a.target = '_blank'; a.rel = 'noopener';
            a.style.cssText = 'flex:0 0 auto;display:block;width:168px;height:112px;border-radius:12px;overflow:hidden;background:#efeee8';
            var im = document.createElement('img');
            im.src = a.href; im.alt = (el.nombre || '') + ' · ' + (f.uso || 'foto'); im.loading = 'lazy';
            im.style.cssText = 'width:100%;height:100%;object-fit:cover;display:block';
            a.appendChild(im);
            gal.appendChild(a);
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
        /* SIN `limit` (S16, 23-sep-2026): el 60 de antes dejaba unidades con
           fase fuera sin decirlo — mismo fallo que ya se quitó en Soporte y
           Comisiones. `id` para abrir ESA unidad en la viva; contrato y fotos
           son columnas que la viva enseña y aquí faltaban. */
        q(sb.from('unidades_estado').select('id,codigo,proyecto,modelo,estado,contrato_numero,obra_fase,obra_fecha_entrega,obra_actualizado,comprador_nombre').not('obra_fase', 'is', null).order('obra_actualizado', { ascending: false }), 'unidades en obra'),
        q(sb.from('proyectos').select('id,nombre,estado').order('nombre'), 'proyectos'),
        cnt(sb, 'unidades_estado', function (qq) { return qq.not('obra_fecha_entrega', 'is', null); }),
        cnt(sb, 'obra_partes_trabajo'),
        q(sb.from('obra_partes_trabajo').select('fase_masterplan,zona_masterplan,fase_anterior,fase_nueva,fecha,autor,nota,dias_offset,proyecto_id').order('creado_en', { ascending: false }).limit(6), 'últimos partes de trabajo'),
        q(sb.from('obra_fases').select('clave,es').order('orden'), 'fases de obra'),
        // solo la columna para contar: las fotos se ven y se gestionan en la viva
        q(sb.from('obra_fotos').select('unidad_id'), 'fotos de obra')
      ]).then(function (r) {
        var us = r[0], proys = r[1] || [], nEntregas = r[2], nPartes = r[3], ultimosPartes = r[4], fases = r[5];
        if (us == null) return;
        // null = la consulta de fotos falló (ya avisada por q()): «? fotos», nunca un 0 que miente
        var nFotos = r[6] == null ? null : {};
        (r[6] || []).forEach(function (f) { nFotos[f.unidad_id] = (nFotos[f.unidad_id] || 0) + 1; });
        var urlUnidad = function (u) { return '/intranet/obra/?id=' + encodeURIComponent(u.id); };

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
          var nf = nFotos == null ? null : (nFotos[u.id] || 0);
          return itemPanel(esc(u.codigo) + ' · ' + esc(u.proyecto || '—'),
            esc(u.modelo || '—') + ' · ' +
            (u.contrato_numero ? esc(u.contrato_numero) + ' · ' + esc(u.comprador_nombre || 'sin comprador') : 'sin contrato') +
            ' · ' + (nf == null ? '? fotos' : nf === 1 ? '1 foto' : nf + ' fotos') +
            ' · entrega ' + (u.obra_fecha_entrega ? fFecha(u.obra_fecha_entrega) : 'sin fecha') +
            ' · actualizado ' + (u.obra_actualizado ? fFecha(u.obra_actualizado) : '—'),
            esc(nombreFase[u.obra_fase] || u.obra_fase || '—'));
        }), 'Ninguna unidad con fase de obra abierta todavía. Se abre una desde «Registrar avance técnico».', '/intranet/obra/', us.map(urlUnidad));

        pintaListaObra('proximas-entregas', conFecha.slice(0, 5).map(function (u) {
          return itemPanel(esc(u.codigo) + ' · ' + esc(u.proyecto || '—'), fFecha(u.obra_fecha_entrega), '');
        }), 'Ninguna unidad con fecha de entrega futura.', '/intranet/obra/', conFecha.slice(0, 5).map(urlUnidad));

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

        /* ---- Frenos saltados — LAW-71 (paridad 21-sep-2026 con /intranet/usuarios/) ----
           Dos fuentes en una caja: `privilegios_ejercidos` (quién se saltó qué
           freno y por qué) y cuántas filas guarda la caja negra `borrados`, lo
           que queda de un contrato o una factura eliminados. Es una vista de
           EQUIPO (no de una ficha), y solo la ve super_admin — un peldaño por
           encima del esAdmin+puedeH que ya filtra el resto de lo sensible de
           esta pantalla (Editar permisos, Herramientas), mismo criterio que
           la clásica (YO.rol === 'super_admin').
           El candado REAL de estas dos tablas lo cierra Datos en paralelo
           (RLS de `contrato_eventos`/`privilegios_ejercidos`/`borrados`, hoy
           legibles por SDK directo sin pasar por ninguna pantalla) — esto de
           aquí es el gate de UI sobre el mismo criterio, no la seguridad. */
        var cajaFrenos = document.getElementById('lwFrenos');
        var cuerpoFrenos = document.getElementById('lwFrenosCuerpo');
        if (cajaFrenos && cuerpoFrenos && window.LW_V4 && window.LW_V4.esSuperAdmin) {
          cajaFrenos.hidden = false;
          var diaHora = function (s) {
            var d = new Date(s);
            return isNaN(d) ? String(s) : d.toLocaleString('es-ES', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
          };
          var pintaFalloFrenos = function () {
            cuerpoFrenos.innerHTML = '<p class="text-[12.5px] mt-1" style="color:#C8791F">'
              + '<b>No se ha podido leer el registro de privilegios.</b> Esto NO quiere decir que '
              + 'nadie se haya saltado nada: quiere decir que no se ha mirado. Recarga la página.</p>';
          };
          Promise.all([
            sb.from('privilegios_ejercidos').select('cuando,quien,evento,contrato,detalle')
              .order('cuando', { ascending: false }).limit(50),
            sb.from('borrados').select('id', { count: 'exact', head: true })
          ]).then(function (r) {
            var priv = r[0] || {}, borr = r[1] || {};
            var fallo = priv.error ? (priv.error.message || 'no se ha podido leer') : null;
            var filas = priv.data || [];
            /* Claves EXACTAS de `registra_privilegio()` (supabase/migrations/
               20260819045000_law71_frenos_saltables_con_rastro.sql) — no las
               que "suenan bien". Dos de las seis no casaban con lo que la
               base escribe de verdad (`factura_sin_bloquear`, no
               `facturado_sin_bloquear`; `comprador_sin_ficha`, no
               `guardado_sin_ficha`), copiadas tal cual de un bug ya existente
               en /intranet/usuarios/ (hallazgo de code-review, 21-sep-2026):
               sin la clave correcta el fallback `|| f.evento` enseñaba la
               jerga cruda de la base al super_admin en vez de la frase. */
            var NOMBRE = {
              desbloqueado: 'desbloqueó un contrato firmado',
              editado_estando_firmado: 'editó un contrato firmado',
              factura_sin_bloquear: 'facturó un contrato sin firmar',
              cobro_a_otro_comprador: 'aplicó un cobro al comprador de otro contrato',
              cobro_a_factura_huerfana: 'aplicó un cobro a una factura sin contrato',
              comprador_sin_ficha: 'guardó un contrato sin ficha de comprador'
            };
            var cabecera = '<div class="flex items-center justify-between mb-2">' +
              '<span class="text-[11px] tracking-[0.12em] uppercase text-on-surface-variant font-bold">Registro</span>' +
              '<span class="text-[11.5px] text-on-surface-variant">' +
              (borr.error ? 'caja negra: no se ha podido leer'
                : esc(String(borr.count || 0)) + ((borr.count || 0) === 1
                  ? ' documento borrado guardado en la caja negra' : ' documentos borrados guardados en la caja negra')) +
              '</span></div>';
            var cuerpo;
            if (fallo) {
              // «no se ha podido leer» y «nadie se ha saltado nada» SE PARECEN
              // mucho en pantalla y son afirmaciones distintas — la lección del
              // 21-ago-2026 en la clásica: la alarma rota no se pinta igual que
              // la alarma tranquila.
              cuerpo = '<p class="text-[12.5px] mt-1" style="color:#C8791F"><b>No se ha podido leer el registro de privilegios.</b> Esto NO quiere decir que nadie se haya saltado nada: quiere decir que no se ha mirado. Recarga la página.</p>';
            } else if (!filas.length) {
              cuerpo = '<p class="font-body-sm text-body-sm text-on-surface-variant mt-1">Mirado ahora mismo: <b>nadie se ha saltado ningún freno</b> todavía.</p>';
            } else {
              cuerpo = '<div class="overflow-x-auto mt-2"><table class="w-full text-left" style="font-size:12.5px;border-collapse:collapse">' +
                '<tbody>' + filas.map(function (f) {
                  return '<tr class="border-t border-outline-variant/30">' +
                    '<td class="py-1.5 pr-3 whitespace-nowrap text-on-surface-variant">' + esc(diaHora(f.cuando)) + '</td>' +
                    '<td class="py-1.5 pr-3">' + esc(f.quien || '—') + '</td>' +
                    '<td class="py-1.5 pr-3"><b>' + esc(NOMBRE[f.evento] || f.evento) + '</b>' + (f.contrato ? ' · ' + esc(f.contrato) : '') + '</td>' +
                    '<td class="py-1.5 text-on-surface-variant">' + esc((f.detalle && (f.detalle.motivo || f.detalle.razon)) || '') + '</td></tr>';
                }).join('') + '</tbody></table></div>';
            }
            cuerpoFrenos.innerHTML = cabecera + cuerpo;
          }, function (e) {
            // Sin este segundo brazo, un RECHAZO (no un `.error` en la
            // respuesta — un throw de red/timeout) dejaba el "Cargando…"
            // inicial para siempre: exactamente la alarma-que-parece-viva
            // que este panel existe para evitar (hallazgo de code-review,
            // 21-sep-2026). Mismo motivo por el que `q()`/`cnt()` de este
            // fichero siempre llevan los dos brazos del `.then` — esto no
            // pasaba por esos helpers, así que se le había quedado corto.
            console.error('[v4 datos] frenos saltados:', e);
            pintaFalloFrenos();
          });
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

        /* Estados: el CHECK de `hilo_soporte.estado` solo admite 'abierto' y
           'resuelto' (verificado en la base el 23-sep-2026). El chip y la KPI
           «En espera» del diseño contaban un estado que la base no puede
           guardar — siempre 0 — y se retiraron (S16). La KPI pasa a
           compradores distintos con algún ticket abierto: uno puede tener
           varios a la vez, así que no es lo mismo que «Abiertos». */
        var abiertos = hs.filter(function (h) { return h.estado === 'abierto'; });
        var resueltos = hs.filter(function (h) { return h.estado === 'resuelto'; });
        pon2('k-abiertos', String(abiertos.length));
        pon2('k-abiertos-pie', 'de ' + hs.length + ' hilos en total');
        var compAb = {}; abiertos.forEach(function (h) { compAb[h.client_id] = 1; });
        var nComp = Object.keys(compAb).length;
        var sinResp = hs.filter(function (h) {
          var u = ultimo[h.id] || ultimo[h.client_id];
          return h.estado === 'abierto' && u && u.de !== 'equipo';   // el último mensaje lo escribió el comprador
        });
        pon2('k-compradores', String(nComp));
        pon2('k-compradores-pie', nComp ? 'un comprador puede tener varios tickets a la vez' : 'ningún comprador tiene un ticket abierto');
        pon2('k-sinresp', String(sinResp.length));
        pon2('k-sinresp-pie', sinResp.length ? 'abiertos cuyo último mensaje es del comprador' : 'ningún hilo abierto espera respuesta del equipo');
        pon2('k-resueltos', String(resueltos.length));
        pon2('k-resueltos-pie', 'de ' + hs.length + ' hilos en total');
        pon2('c-todos', 'Todos (' + hs.length + ')');
        pon2('c-abiertos', 'Abiertos (' + abiertos.length + ')');
        pon2('c-resueltos', 'Resueltos (' + resueltos.length + ')');
        pon2('n-hilos', abiertos.length + ' activos');

        /* --- el ticket elegido, ANTES de pintar la bandeja: decide el chip de
           arranque ---
           · ?hilo=<id>: el clic de una fila de esta misma pantalla.
           · ?id=<client_id>: lo que mandan los avisos por email al equipo
             (igual que la viva). Un comprador puede tener varios tickets: se
             abre el más reciente (`hs` viene por actualizado_en DESC — casi
             seguro el que disparó el aviso) y la bandeja se filtra por su
             nombre para que se vean también los demás.
           · sin nada: el abierto más reciente; si no hay abiertos, el último. */
        // «el más reciente» no puede colgar del orden en que llegue la consulta
        hs.sort(function (a, b) { var x = a.actualizado_en || '', y = b.actualizado_en || ''; return x < y ? 1 : x > y ? -1 : 0; });
        abiertos = hs.filter(function (h) { return h.estado === 'abierto'; });
        var params = new URLSearchParams(location.search);
        var pedido = params.get('hilo'), pedidoCli = params.get('id');
        var el = null, buscaCli = '';
        if (pedido) el = hs.filter(function (h) { return String(h.id) === pedido; })[0] || null;
        if (!el && pedidoCli) {
          el = hs.filter(function (h) { return String(h.client_id) === pedidoCli; })[0] || null;
          if (el) buscaCli = (cli[el.client_id] || {}).full_name || '';
          else toast('Ese comprador no tiene ningún ticket de soporte.');
        }
        if (!el) el = abiertos[0] || hs[0];
        /* Arranca en «Abiertos», como la viva. La única excepción: un ticket
           PEDIDO por URL que ya está resuelto — en «Abiertos» su propia fila
           no saldría en la bandeja y parecería que el enlace no funciona. */
        var estadoF = (el && el.estado !== 'abierto' && (pedido || pedidoCli)) ? 'todos' : 'abiertos';

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
          f.setAttribute('data-ts', h.actualizado_en || '');
          f.setAttribute('data-nombre', c.full_name || '');
          f.setAttribute('data-cat', h.categoria || '');
          f.setAttribute('data-lw-pajar', [c.full_name, c.email, h.categoria, u && u.texto].join(' ').toLowerCase());
          f.style.cursor = 'pointer';
          f.addEventListener('click', function () { location.search = '?hilo=' + encodeURIComponent(h.id); });
          lista.appendChild(f);
        });
        var vacioF = null;
        if (hs.length) {
          vacioF = document.createElement('p');
          vacioF.style.cssText = 'font:500 13px/1.5 sans-serif;color:#75786e;margin:0;padding:6px 2px;display:none';
          vacioF.textContent = 'Nada que enseñar con este filtro.';
          lista.appendChild(vacioF);
        }

        /* Chip de estado + buscador + orden en UNA sola pasada. Antes eran dos
           listeners sueltos y el buscador volvía a enseñar filas que el chip
           había escondido (salían resueltos estando en «Abiertos»). El orden
           es el de la viva (comprador, categoría, estado, cuándo), con «más
           recientes» de arranque y de desempate. */
        var inpS = document.querySelector('main input[placeholder^="Buscar"]');
        var selOrden = document.querySelector('[data-lw="orden-hilos"]');
        if (inpS && buscaCli) inpS.value = buscaCli;
        function aplicarSoporte() {
          var v = inpS ? inpS.value.trim().toLowerCase() : '';
          var modo = selOrden ? selOrden.value : 'reciente';
          var filas = Array.prototype.slice.call(lista.querySelectorAll('[data-estado-hilo]'));
          filas.sort(function (a, b) {
            var A = a.dataset, B = b.dataset, r = 0;
            if (modo === 'antiguo') return A.ts < B.ts ? -1 : A.ts > B.ts ? 1 : 0;
            if (modo === 'nombre') r = (A.nombre || '').localeCompare(B.nombre || '', 'es', { sensitivity: 'base' });
            else if (modo === 'categoria') r = (A.cat || '').localeCompare(B.cat || '', 'es', { sensitivity: 'base' });
            else if (modo === 'estado' && A.estadoHilo !== B.estadoHilo) r = A.estadoHilo === 'abierto' ? -1 : 1;
            return r || (A.ts < B.ts ? 1 : A.ts > B.ts ? -1 : 0);
          });
          var vistas = 0;
          filas.forEach(function (f) {
            var e = f.getAttribute('data-estado-hilo') || '';
            var okE = estadoF === 'todos' || (estadoF === 'abiertos' ? e === 'abierto' : e === 'resuelto');
            var okQ = !v || (f.getAttribute('data-lw-pajar') || '').indexOf(v) !== -1;
            f.style.display = (okE && okQ) ? '' : 'none';
            if (okE && okQ) vistas++;
            lista.insertBefore(f, vacioF);
          });
          if (vacioF) vacioF.style.display = vistas ? 'none' : '';
        }
        var chipsSoporte = ['abiertos', 'resueltos', 'todos'].map(function (k) {
          var sp = document.querySelector('[data-lw="c-' + k + '"]'); var b = sp && sp.closest('button');
          if (b) b.setAttribute('data-chip-clave', k);
          return b;
        }).filter(Boolean);
        function pintaChip(btn, on) {
          btn.classList.toggle('bg-primary', on);
          btn.classList.toggle('text-on-primary', on);
          btn.classList.toggle('font-semibold', on);
          btn.classList.toggle('bg-surface-container-low', !on);
          btn.classList.toggle('text-on-surface-variant', !on);
          btn.classList.toggle('hover:bg-surface-container-high', !on);
          btn.classList.toggle('transition-colors', !on);
        }
        chipsSoporte.forEach(function (btn) {
          pintaChip(btn, btn.getAttribute('data-chip-clave') === estadoF);
          btn.addEventListener('click', function (ev) {
            ev.stopPropagation();   // si no, maqueta.js la ve pasar y avisa «sin cablear»
            estadoF = btn.getAttribute('data-chip-clave');
            chipsSoporte.forEach(function (b) { pintaChip(b, b === btn); });
            aplicarSoporte();
          });
        });
        if (inpS) inpS.addEventListener('input', aplicarSoporte);
        if (selOrden) selOrden.addEventListener('change', aplicarSoporte);
        aplicarSoporte();

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
  var ETIQUETA_EQ = { pendiente: 'Pendiente', pagada: 'Pagada', en_disputa: 'En disputa', anulada: 'Anulada' };
  /* Un color por estado (23-sep-2026, owner), de la paleta única LW_TONOS.
     Anulada va en gris y no en rojo: es «sin efecto» por decisión nuestra, y en
     rojo se confundía con rechazada. */
  var TONO_SP = { pendiente: 'espera', aprobada: 'curso', pagada: 'ok', rechazada: 'mal', anulada: 'neutro' };
  var TONO_EQ = { pendiente: 'espera', pagada: 'ok', en_disputa: 'mal', anulada: 'neutro' };

  function miembroActivo(em, hoyISO) { return em.desde <= hoyISO && (!em.hasta || em.hasta >= hoyISO); }

  /* `opts.soloEquipo`: la pantalla «Reparto de equipo» del panel «Mi equipo»
     (intranet/v4/reparto/, 23-sep-2026) — la misma pestaña, sin «A Lawang»:
     no se consulta solicitudes_pago. */
  REG.comisiones = function (sb, opts) {
    opts = opts || {};
    var tabla = document.getElementById('lw-filas');
    var caja = tabla ? tabla.closest('section') : null;
    var tablaEq = document.getElementById('lw-filas-equipo');
    var cajaEq = tablaEq ? tablaEq.closest('section') : null;

    Promise.all([
      /* `id` y los campos de la ficha (vence_el, nota, resolución…): sin `id` cada fila
         salía con data-id="" y el clic no abría nada — no se podía editar ninguna
         (23-sep-2026). */
      opts.soloEquipo ? Promise.resolve(null) : q(sb.from('solicitudes_pago').select('id,numero,concepto,importe,moneda,vence_el,nota,estado,motivo_rechazo,pago_referencia,creado_en,creado_por,resuelto_por,resuelto_en,pagado_por,pagado_en,beneficiario_email,origen,contrato_id,importe_editado_por,motivo_ajuste').order('creado_en', { ascending: false }), 'solicitudes de pago', caja),
      q(sb.from('contratos').select('id,numero,tipo,proyecto_nombre,contrato_padre_id'), 'contratos'),
      /* Si la RLS de `usuarios` solo deja leer la propia ficha, el mapa se queda
         corto y el fallback pinta «—»: no es un fallo, es lo que esa sesion ve. */
      q(sb.from('usuarios').select('user_id,nombre,email'), 'usuarios'),
      q(sb.from('comisiones_devengadas').select('id,contrato_raiz_id,beneficiario_email,nivel,importe,importe_ajustado,ajuste_motivo,anulado_motivo,moneda,estado,disparado_en,pagado_por,pagado_en').eq('nivel', 'closer').order('disparado_en', { ascending: false }), 'reparto de equipo', cajaEq),
      q(sb.from('equipos_venta').select('id,nombre,manager_email,activo'), 'equipos de venta'),
      q(sb.from('equipo_miembros').select('equipo_id,closer_email,desde,hasta'), 'miembros de equipo'),
      /* De qué parcela sale cada comisión (23-sep-2026, owner): las unidades cuelgan
         de la RAÍZ de la venta (`unidades.contrato_id`), igual que las lee el motor. */
      q(sb.from('unidades').select('codigo,codigo_orden,contrato_id').not('contrato_id', 'is', null), 'parcelas')
    ]).then(function (r) {
      var ss = r[0], contratosRows = r[1] || [], usuariosRows = r[2] || [], cd = r[3], eqs = r[4] || [], miembros = r[5] || [], unidadesRows = r[6] || [];
      var ct = {}; contratosRows.forEach(function (c) { ct[c.id] = c; });
      var parcelasDe = {};
      unidadesRows.slice().sort(function (a, b) { return String(a.codigo_orden || a.codigo || '').localeCompare(String(b.codigo_orden || b.codigo || '')); })
        .forEach(function (u) { if (u.codigo) (parcelasDe[u.contrato_id] = parcelasDe[u.contrato_id] || []).push(u.codigo); });
      // parcela(s) de una venta a partir de cualquier contrato de la cadena
      function parcelas(contratoId) {
        var c = ct[contratoId]; var raiz = c && c.contrato_padre_id ? c.contrato_padre_id : contratoId;
        return (parcelasDe[raiz] || []).join(', ');
      }
      var us = {}; usuariosRows.forEach(function (u) { us[u.user_id] = u; });
      var porEmail = {}; usuariosRows.forEach(function (u) { if (u.email) porEmail[u.email.toLowerCase()] = u; });

      /* PAGOS DE LAWANG, SOLO LO SUYO (23-sep-2026, paso 2 del plan del owner:
         «no todos ven lo de todos, sólo lo suyo»). Para quien no es admin, esta
         pestaña es «tu comisión»: las solicitudes a su nombre o que creó él.
         Desde la migración 20260923220000 la base tampoco le da otras (se quitó
         la rama es_manager_de); el filtro se queda por si acaso. */
      if (ss && !(window.LW_V4 && window.LW_V4.esAdmin)) {
        var yoMail = ((window.LW_V4 && window.LW_V4.miEmail) || '').toLowerCase();
        var yoId = (window.LW_V4 && window.LW_V4.miId) || '';
        ss = ss.filter(function (x) {
          return (x.beneficiario_email && x.beneficiario_email.toLowerCase() === yoMail) || (yoId && x.creado_por === yoId);
        });
        var subP = document.querySelector('main h1') && document.querySelector('main h1').parentNode.querySelector('p');
        if (subP) subP.textContent = 'Tu comisión, venta a venta: lo que Lawang te debe y lo que ya te ha pagado. La aprueba y la paga Lawang.';
      }
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

        var porId = {}; ss.forEach(function (x) { porId[x.id] = x; });
        /* Quién COBRA es `beneficiario_email`, no `creado_por`: en una automática
           `creado_por` es quien registró el recibí que la disparó (Administración,
           casi siempre), y la columna enseñaba a esa persona como cobradora
           (23-sep-2026). En una manual coinciden: el trigger de alta pone
           beneficiario = el email de quien la crea. */
        function quienCobra(x) {
          var b = (x.beneficiario_email || '').toLowerCase();
          var u = (b && porEmail[b]) || us[x.creado_por];
          return u ? (u.nombre || u.email) : (x.beneficiario_email || '—');
        }
        /* El motor escribe un concepto de auditoría larguísimo («Comisión estándar —
           tramo 1 (pct_cobrado_suelo 50%) — 2,5% s/ precio total… — importe BRUTO…»).
           En la tabla va el titular; en la ficha, entero. */
        function tipoAuto(x) {
          var m = x.origen === 'comision_automatica' && /^Comisión (manager|estándar)/.exec(x.concepto || '');
          return m ? m[1] : null;
        }
        function conceptoCorto(x) {
          var m = x.origen === 'comision_automatica' && /^(Comisión \S+) — tramo (\d+)/.exec(x.concepto || '');
          return m ? m[1] + ' · tramo ' + m[2] : (x.concepto || '—');
        }
        function claveCobra(x) { return (x.beneficiario_email || '').toLowerCase() || x.creado_por || ''; }

        /* ---------- ficha en cajon (S8, 22-sep-2026) ----------
           Mismo patron que Usuarios/Compradores (`abreFicha` + `window.lwCajon`):
           datos.js es SOLO LECTURA (cabecera del fichero), asi que esta funcion
           solo PINTA la ficha y llama a lo que editores.js deja en
           `window.LW_V4.*Solicitud` — nunca escribe por su cuenta. */
        function quitaId() {
          var u2 = new URL(location.href);
          if (u2.searchParams.has('id')) { u2.searchParams.delete('id'); history.replaceState(null, '', u2.href); }
        }
        function abreFicha(x) {
          var H = window.lwCajonHtml;
          if (!(window.lwCajon && H)) { toast('La ficha aún no ha cargado — prueba de nuevo en un segundo.'); return; }
          var c = ct[x.contrato_id]; var u = us[x.creado_por];
          var miId = (window.LW_V4 && window.LW_V4.miId) || '';
          var soyAdmin = !!(window.LW_V4 && window.LW_V4.esAdmin);
          var mia = !!(miId && x.creado_por === miId);

          var cuerpo = H.seccion('La solicitud',
            H.dato('Quién cobra', quienCobra(x)) +
            (x.origen === 'comision_automatica' && u ? H.dato('Disparada al registrar el cobro', u.nombre || u.email) : '') +
            H.dato('Concepto', x.concepto) +
            H.dato('Importe', fmt(x.importe, x.moneda || 'EUR')) +
            (x.importe_editado_por ? H.dato('Importe cambiado a mano', ((us[x.importe_editado_por] && (us[x.importe_editado_por].nombre || us[x.importe_editado_por].email)) || '—') + (x.motivo_ajuste ? ' — ' + x.motivo_ajuste : '')) : '') +
            H.dato('De la venta', c ? [c.numero, tipoC(c.tipo), c.proyecto_nombre].filter(Boolean).join(' · ') : null) +
            H.dato('Parcela', x.contrato_id ? (parcelas(x.contrato_id) || 'sin parcela asignada') : null) +
            H.dato('Fecha límite', x.vence_el ? fFecha(x.vence_el) : null) +
            H.dato('Nota', x.nota) +
            H.dato('Pedida', fFecha(x.creado_en)) +
            // beneficiario_email/origen los fuerza el trigger de alta, nunca esta
            // pantalla (correccion #5 de Administracion, revision previa #37):
            // aqui solo se ENSEÑAN, no hay campo editable para ninguno de los dos.
            H.dato('Origen', x.origen === 'comision_automatica'
              ? (tipoAuto(x) === 'manager' ? 'Comisión automática de manager'
                : tipoAuto(x) === 'estándar' ? 'Comisión automática estándar (agente sin equipo)'
                : 'Comisión automática') : 'Manual'));

          if (x.estado !== 'pendiente') {
            var tonoEstado = TONO_SP[x.estado];
            cuerpo += H.seccion('Resolución',
              H.dato('Estado', H.tag(ETIQUETA[x.estado] || x.estado, tonoEstado), { html: 1 }) +
              H.dato('Motivo', x.motivo_rechazo) +
              H.dato('Resuelta por', x.resuelto_por ? ((us[x.resuelto_por] && (us[x.resuelto_por].nombre || us[x.resuelto_por].email)) || x.resuelto_por) + ' · ' + fFecha(x.resuelto_en) : null) +
              H.dato('Pagada por', x.pagado_por ? ((us[x.pagado_por] && (us[x.pagado_por].nombre || us[x.pagado_por].email)) || x.pagado_por) + ' · ' + fFecha(x.pagado_en) : null) +
              // opcional en la base (`solicitud_pagada_con_sello` solo exige
              // `pagado_en`, nunca `pago_referencia`) — correccion #2: se enseña
              // tal cual, sin fingir que siempre hay una.
              H.dato('Referencia del pago', x.pago_referencia));
          }

          var acciones = [];
          var miEmailF = ((window.LW_V4 && window.LW_V4.miEmail) || '').toLowerCase();
          var cobroYo = !!(x.beneficiario_email && x.beneficiario_email.toLowerCase() === miEmailF);
          var editeYo = !!(miId && x.importe_editado_por === miId);
          var auto = x.origen === 'comision_automatica';
          function llama(fn) {
            return function () {
              if (window.LW_V4[fn]) window.LW_V4[fn](x);
              else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
            };
          }
          // Quien cambió el importe no aprueba ni paga (la base lo exige igual).
          if (x.estado === 'pendiente' && soyAdmin && !editeYo && !cobroYo) acciones.push({ texto: 'Aprobar', tono: 'primario', onClick: llama('aprobarSolicitud') });
          if (x.estado === 'pendiente' && soyAdmin) acciones.push({ texto: 'Rechazar…', onClick: llama('rechazarSolicitud') });
          /* Editar: la tuya manual pendiente, o cualquier pendiente si eres admin y
             no la cobras tú (23-sep-2026, owner: «siempre permíteme editar o borrar»). */
          if (x.estado === 'pendiente' && ((mia && !auto) || (soyAdmin && !cobroYo))) acciones.push({ texto: 'Editar', onClick: llama('abreAltaSolicitud') });
          // Anular = borrar con rastro. Pendiente: la tuya manual, o admin que no la
          // cobra. Aprobada: admin que no la cobra. Pagada: nunca.
          if ((x.estado === 'pendiente' && ((mia && !auto) || (soyAdmin && !cobroYo))) ||
              (x.estado === 'aprobada' && soyAdmin && !cobroYo)) {
            acciones.push({ texto: 'Anular', tono: 'peligro', onClick: llama('anularSolicitud') });
          }
          if (x.estado === 'aprobada' && soyAdmin && !editeYo && !cobroYo) acciones.push({ texto: 'Marcar pagada…', tono: 'primario', onClick: llama('pagarSolicitud') });
          if (auto && x.contrato_id && ['pendiente', 'anulada', 'rechazada'].indexOf(x.estado) !== -1 &&
              window.LW_V4.esSuperAdmin && !cobroYo) {
            acciones.push({ texto: 'Recalcular venta…', onClick: llama('recalcularComision') });
          }
          if (editeYo && (x.estado === 'pendiente' || x.estado === 'aprobada')) {
            cuerpo += H.nota('Cambiaste tú el importe: la aprueba y la paga otro administrador.');
          }
          acciones.push({ texto: 'Cerrar', cerrar: true });

          var cj = window.lwCajon({
            sub: 'SP-' + x.numero + ' · ' + (ETIQUETA[x.estado] || x.estado),
            titulo: quienCobra(x),
            bajoTitulo: 'El pago se hace fuera de la suite (transferencia, Wise…); aquí queda pedido, aprobado y pagado.',
            cuerpo: cuerpo, acciones: acciones, alCerrar: quitaId
          });
          var u2 = new URL(location.href);
          u2.searchParams.set('id', x.id);
          history.replaceState(null, '', u2.href);

          /* Correccion #1 de Administracion (revision previa #37, ALTA): la
             comision del manager (comisiones_devengadas con solicitud_id=esta
             fila) no tiene ningun trigger que sincronice su estado cuando ESTA
             solicitud pasa a pagada — riesgo de que quede «pendiente» con el
             pago ya hecho. No se arregla el trigger que falta aqui (otra tarea):
             solo se hace VISIBLE, y solo para las nacidas de una comision
             automatica (las manuales no tienen fila que vincular). */
          if (x.origen === 'comision_automatica' && cj && cj.cuerpo) {
            sb.from('comisiones_devengadas').select('estado,pagado_en,importe,importe_ajustado,moneda')
              // manager Y estándar (22-sep-2026): las dos las paga Lawang y llevan solicitud
              .eq('solicitud_id', x.id).in('nivel', ['manager', 'estandar']).maybeSingle()
              .then(function (rcd) {
                if (!cj.cuerpo.isConnected) return;   // el cajon ya se cerro
                var html;
                if (rcd.error || !rcd.data) {
                  html = H.seccion('Comisión vinculada',
                    H.nota('No se encuentra la fila de comisiones_devengadas de esta comisión automática (o tu sesión no puede verla) — no hay sincronización automática entre las dos: compruébalo a mano si hace falta.'));
                } else {
                  var cd = rcd.data;
                  var tonoCd = TONO_EQ[cd.estado] || 'espera';
                  var diverge = (x.estado === 'pagada') !== (cd.estado === 'pagada');
                  html = H.seccion('Comisión vinculada',
                    H.dato('Estado en comisiones_devengadas', H.tag(cd.estado, tonoCd), { html: 1 }) +
                    H.dato('Calculado por el motor', fmt(cd.importe, cd.moneda || 'EUR')) +
                    (cd.importe_ajustado != null ? H.dato('Ajustado a mano', fmt(cd.importe_ajustado, cd.moneda || 'EUR')) : '') +
                    (diverge
                      ? H.nota('⚠ Diverge de esta solicitud: nada sincroniza los dos estados automáticamente al marcar esta pagada. Si ya se pagó por un lado, revisa el otro a mano.')
                      : ''));
                }
                cj.cuerpo.insertAdjacentHTML('beforeend', html);
              });
          }
        }
        window.LW_V4 = window.LW_V4 || {};
        window.LW_V4.abreFichaSolicitud = function (id) { var x = porId[id]; if (x) abreFicha(x); };

        if (!tabla) return;
        if (!ss.length) {
          tabla.innerHTML = '<tr><td colspan="9" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Ninguna solicitud registrada.</td></tr>';
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
          var venta = c ? [c.numero, tipoC(c.tipo), c.proyecto_nombre].filter(Boolean).join(' · ') : '';
          var pajar = ['SP-' + x.numero, x.concepto, quienCobra(x), venta, x.contrato_id ? parcelas(x.contrato_id) : ''].join(' ').toLowerCase();
          return '<tr class="border-b border-outline-variant/30" style="cursor:pointer" data-id="' + esc(x.id) + '" data-estado="' + esc(x.estado) + '" data-creado-por="' + esc(claveCobra(x)) + '" data-pajar="' + esc(pajar) + '">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface whitespace-nowrap"><b>SP-' + esc(x.numero) + '</b></td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(quienCobra(x)) + '</td>' +
            '<td class="px-5 py-4">' + origenHtml + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + esc(conceptoCorto(x)) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface whitespace-nowrap">' + esc(fmt(x.importe, x.moneda || 'EUR')) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(venta || '—') + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc((x.contrato_id && parcelas(x.contrato_id)) || '—') + '</td>' +
            '<td class="px-5 py-4 whitespace-nowrap">' + pill(ETIQUETA[x.estado] || x.estado, TONO_SP[x.estado]) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline text-right">' + esc(fFecha(x.creado_en)) + ' · ' + diasDesde(x.creado_en) + ' d</td>' +
            '</tr>';
        }).join('');

        // una fila = una ficha (mismo patron que Usuarios/Compradores): delegado
        // en el tbody porque los filtros de abajo esconden/enseñan filas.
        tabla.addEventListener('click', function (ev) {
          var tr = ev.target.closest && ev.target.closest('tr[data-id]');
          if (!tr) return;
          ev.preventDefault(); ev.stopPropagation();
          var x = porId[tr.getAttribute('data-id')];
          if (x) abreFicha(x);
        });

        /* ---------- filtros: chip de estado + agente (solo admin) + buscador ----------
           Tres criterios independientes sobre las MISMAS filas — cablearChipsFiltro
           es de una sola dimension y no basta con agente+buscador a la vez, asi que
           aqui se combinan a mano sobre atributos `data-*` ya puestos en cada <tr>. */
        var filtroEstado = 'todas', filtroAgente = '';
        function aplicaFiltrosLawang() {
          var buscadorEl = document.getElementById('lw-buscar');
          var qTxt = ((buscadorEl && buscadorEl.value) || '').toLowerCase();
          tabla.querySelectorAll('tr[data-id]').forEach(function (tr) {
            var okEstado = filtroEstado === 'todas' ? true
              : filtroEstado === 'resueltas' ? RESUELTAS.indexOf(tr.getAttribute('data-estado')) >= 0
              : tr.getAttribute('data-estado') === filtroEstado;
            var okAgente = !filtroAgente || tr.getAttribute('data-creado-por') === filtroAgente;
            var okTexto = !qTxt || (tr.getAttribute('data-pajar') || '').indexOf(qTxt) !== -1;
            tr.style.display = (okEstado && okAgente && okTexto) ? '' : 'none';
          });
        }
        var chipsComisiones = Array.prototype.slice.call(document.querySelectorAll('[data-chip-clave]'))
          .filter(function (b) { return ['todas', 'pendiente', 'aprobada', 'resueltas'].indexOf(b.getAttribute('data-chip-clave')) !== -1; });
        chipsComisiones.forEach(function (btn) {
          btn.addEventListener('click', function (ev) {
            ev.stopPropagation();   // si no, maqueta.js la ve pasar y avisa «sin cablear»
            filtroEstado = btn.getAttribute('data-chip-clave');
            chipsComisiones.forEach(function (b) {
              var on = b === btn;
              b.classList.toggle('bg-primary-container', on);
              b.classList.toggle('text-on-primary', on);
              b.classList.toggle('bg-surface-container-low', !on);
              b.classList.toggle('text-on-surface-variant', !on);
            });
            aplicaFiltrosLawang();
          });
        });
        var buscador = document.getElementById('lw-buscar');
        if (buscador) buscador.addEventListener('input', aplicaFiltrosLawang);

        // filtro por agente: SOLO admin (un agente ya ve solo lo suyo) y solo si
        // hay mas de uno entre lo que la RLS dejo ver — mismo criterio que
        // pintarFiltroAgente() en /intranet/solicitudes/.
        var selAgente = document.getElementById('lw-fAgente');
        if (selAgente) {
          if (window.LW_V4 && window.LW_V4.esAdmin) {
            var vistos = [];
            // por quien COBRA (misma clave que data-creado-por de cada fila)
            var ejemplo = {};
            ss.forEach(function (x) { var k = claveCobra(x); if (k && vistos.indexOf(k) === -1) { vistos.push(k); ejemplo[k] = x; } });
            if (vistos.length > 1) {
              var opcionesAg = vistos.map(function (k) {
                return { uid: k, nombre: quienCobra(ejemplo[k]) };
              }).sort(function (a, b) { return a.nombre.localeCompare(b.nombre, 'es'); });
              selAgente.innerHTML = '<option value="">Todos los agentes</option>' +
                opcionesAg.map(function (o) { return '<option value="' + esc(o.uid) + '">' + esc(o.nombre) + '</option>'; }).join('');
              selAgente.hidden = false;
              selAgente.addEventListener('change', function () { filtroAgente = selAgente.value; aplicaFiltrosLawang(); });
            }
          }
        }

        // ?id= abre la ficha directamente (enlace desde la campana, o tras
        // guardar un editor que recarga la pagina).
        var pedidoId = new URLSearchParams(location.search).get('id');
        if (pedidoId && porId[pedidoId]) setTimeout(function () { abreFicha(porId[pedidoId]); }, 0);
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
          tablaEq.innerHTML = '<tr><td colspan="8" style="padding:18px;text-align:center;font:400 13px \'Neue Kabel\',sans-serif;color:#8A8474">Nada que repartir todavía — aquí aparecerá cada comisión de closer en cuanto se devengue una.</td></tr>';
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
          var soyElCloser = email.toLowerCase() === miEmail;
          var puedeMarcar = x.estado === 'pendiente' && !soyElCloser && (esAdminSesion || misCloserEmails[email.toLowerCase()]);
          // ajustar/anular: admin que ni la cobra ni la paga (la RPC lo exige igual)
          var puedeAjustar = x.estado === 'pendiente' && esAdminSesion && !soyElCloser && !misCloserEmails[email.toLowerCase()];
          var efectivo = x.importe_ajustado != null ? x.importe_ajustado : x.importe;
          window.LW_V4.comisionesPorId[x.id].importe = efectivo;
          window.LW_V4.comisionesPorId[x.id].moneda = x.moneda || 'EUR';
          var bEst = 'padding:7px 14px;border-radius:999px;font:600 12px \'Neue Kabel\',sans-serif;cursor:pointer;';
          var botones = [];
          if (puedeMarcar) botones.push('<button type="button" data-eq-pagar="' + esc(x.id) + '" style="' + bEst + 'border:0;background:#104C4F;color:#fff">Marcar pagada</button>');
          if (puedeAjustar) {
            botones.push('<button type="button" data-eq-ajustar="' + esc(x.id) + '" style="' + bEst + 'border:1px solid #8A8474;background:transparent;color:#1b1c19">Ajustar</button>');
            botones.push('<button type="button" data-eq-anular="' + esc(x.id) + '" style="' + bEst + 'border:1px solid #ba1a1a;background:transparent;color:#ba1a1a">Anular</button>');
          }
          var accion = botones.length
            ? '<span style="display:inline-flex;gap:6px;flex-wrap:nowrap;justify-content:flex-end;white-space:nowrap">' + botones.join('') + '</span>'
            : '<span style="font:500 12px \'Neue Kabel\',sans-serif;color:#8A8474">—</span>';
          var notaFila = x.estado === 'anulada' && x.anulado_motivo ? x.anulado_motivo
            : x.importe_ajustado != null ? 'Motor: ' + fmt(x.importe, x.moneda || 'EUR') + (x.ajuste_motivo ? ' · ' + x.ajuste_motivo : '') : '';
          return '<tr class="border-b border-outline-variant/30" data-eq-estado="' + esc(x.estado) + '" data-eq-equipo="' + esc(equipoNombre) + '">' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant whitespace-nowrap">' + esc(etiqueta) + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline whitespace-nowrap">' + esc(equipoNombre) + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface whitespace-nowrap">' + esc(fmt(efectivo, x.moneda || 'EUR')) +
              (notaFila ? '<div style="font:500 11px \'Neue Kabel\',sans-serif;color:#8A8474;white-space:normal;max-width:220px">' + esc(notaFila) + '</div>' : '') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(c ? [c.numero, tipoC(c.tipo), c.proyecto_nombre].filter(Boolean).join(' · ') : '—') + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(parcelas(x.contrato_raiz_id) || '—') + '</td>' +
            '<td class="px-5 py-4 whitespace-nowrap">' + pill(ETIQUETA_EQ[x.estado] || x.estado, TONO_EQ[x.estado]) + '</td>' +
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
          var bAj = ev.target.closest && ev.target.closest('[data-eq-ajustar],[data-eq-anular]');
          if (bAj) {
            ev.preventDefault(); ev.stopPropagation();
            var idA = bAj.getAttribute('data-eq-ajustar') || bAj.getAttribute('data-eq-anular');
            var infoA = (window.LW_V4.comisionesPorId && window.LW_V4.comisionesPorId[idA]) || {};
            var fnA = bAj.hasAttribute('data-eq-ajustar') ? 'ajustarComisionEquipo' : 'anularComisionEquipo';
            if (typeof window.LW_V4[fnA] === 'function') window.LW_V4[fnA](idA, infoA.etiqueta || '', infoA.importe, infoA.moneda);
            else toast('El editor de comisiones aún no ha cargado — prueba de nuevo en un segundo.');
            return;
          }
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

  /* Owner, 22-sep-2026: manager de equipo, closer de miembro y override de
     condición se ELIGEN entre los usuarios de la intranet, no se teclean.
     Las dos pantallas ya bajaban `usuarios` para pintar nombres; esto deja
     la misma consulta a disposición de los selects de editores.js
     (`opsUsuarios`), sin otra petición. Solo activos y ordenados por nombre:
     a un usuario de baja no se le da de alta en un equipo — si ya estaba, el
     editor conserva su valor y lo marca. */
  function publicaUsuariosLista(usuarios) {
    window.LW_V4.usuariosLista = (usuarios || [])
      .filter(function (u) { return u.email && u.activo !== false; })
      .sort(function (a, b) { return String(a.nombre || a.email).localeCompare(String(b.nombre || b.email), 'es'); })
      .map(function (u) {
        var em = u.email.toLowerCase();
        return [em, (u.nombre ? u.nombre + ' · ' : '') + em + (u.rol && u.rol !== 'agente' ? ' (' + u.rol + ')' : '')];
      });
  }

  /* ---------- Equipos de venta y Condiciones de comisión (14-sep-2026) ----------
     Dos pantallas SOLO admin/super_admin: nav.js ya las esconde del menú para
     cualquier otra sesión, y aquí se repite el gate (defensa en profundidad,
     no el candado — ese es `es_admin()` en la RLS de las cuatro tablas,
     verificado con sesión no-admin simulada). Las acciones de escritura viven
     en editores.js (ED['equipos-venta'] / ED.condiciones, expuestas en
     `window.LW_V4`); aquí solo se lee y se pinta. */
  REG['equipos-venta'] = function (sb) {
    /* Sales manager (23-sep-2026, owner: «el Sales Manager entra a su panel y
       configura cuánto van a cobrar sus closers… no todos ven lo de todos,
       sólo lo suyo»): ve SOLO los equipos que dirige y sus miembros, sin
       ningún botón — dar de alta equipos y miembros sigue siendo de
       administración. La base ya le recorta la lectura (policies de
       equipos_venta / equipo_miembros); el filtro de aquí es por si acaso. */
    var esAdmEq = !!(window.LW_V4 && window.LW_V4.esAdmin);
    var rolEq = (window.LW_V4 && window.LW_V4.ficha && window.LW_V4.ficha.rol) || '';
    var miEmailEq = ((window.LW_V4 && window.LW_V4.miEmail) || '').toLowerCase();
    if (!esAdmEq && rolEq !== 'sales_manager') { notaSoloAdmin(); return; }
    if (!esAdmEq) document.querySelectorAll('main button').forEach(function (b) {
      if (/Nuevo equipo/i.test(b.textContent || '')) b.style.display = 'none';
    });
    var cuerpoEq = document.getElementById('lw-equipos-filas');
    var cuerpoMi = document.getElementById('lw-miembros-filas');
    var selEq = document.getElementById('lw-mi-equipo');
    var hoy = new Date().toISOString().slice(0, 10);

    Promise.all([
      q(sb.from('equipos_venta').select('id,nombre,manager_email,activo,created_at').order('nombre'), 'equipos de venta', cuerpoEq),
      q(sb.from('equipo_miembros').select('id,equipo_id,closer_email,desde,hasta').order('desde', { ascending: false }), 'miembros de equipo', cuerpoMi),
      q(sb.from('usuarios').select('email,nombre,rol,activo'), 'usuarios')
    ]).then(function (r) {
      var equipos = r[0], miembros = r[1] || [], usuarios = r[2] || [];
      if (!equipos) return;
      if (!esAdmEq) {
        equipos = equipos.filter(function (e) { return (e.manager_email || '').toLowerCase() === miEmailEq; });
        var misIds = equipos.map(function (e) { return e.id; });
        miembros = miembros.filter(function (m) { return misIds.indexOf(m.equipo_id) !== -1; });
        var avisoEq = document.querySelector('[data-lw-aviso-admin] p');
        if (avisoEq) avisoEq.innerHTML = equipos.length
          ? 'Este es tu equipo: <b class="text-on-surface">' + esc(equipos.map(function (e) { return e.nombre; }).join(', ')) + '</b>. Las altas y bajas de closers las hace administración; lo que cobra cada uno lo configuras tú en <a href="../condiciones/" class="underline text-deep-lagoon">Condiciones</a>.'
          : 'Todavía no diriges ningún equipo de venta. Cuando administración te asigne uno, aparecerá aquí con sus closers.';
      }
      // el editor de miembro ofrece el equipo en un select: la lista es esta, no otra consulta
      window.LW_V4.equiposLista = equipos.map(function (e) { return [e.id, e.nombre + (e.activo ? '' : ' (de baja)')]; });
      publicaUsuariosLista(usuarios);
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
            '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-2">' + (!esAdmEq ? '' :
            '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-edita-equipo="' + esc(e.id) + '" data-lw-nombre="' + esc(e.nombre) + '" data-lw-manager="' + esc(e.manager_email || '') + '">Editar</button>' +
            '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-miembro="' + esc(e.id) + '" data-lw-nombre="' + esc(e.nombre) + '">+ Miembro</button>' +
            '<button type="button" class="px-3 py-1 rounded-full text-burnt-earth hover:bg-surface-container-high font-label-md text-[12px]" data-lw-toggle-equipo="' + esc(e.id) + '" data-lw-nombre="' + esc(e.nombre) + '" data-lw-activo="' + (e.activo ? '1' : '0') + '">' +
            (e.activo ? 'Desactivar' : 'Reactivar') + '</button>') +
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
            '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-2">' + (!esAdmEq ? '' :
            '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" data-lw-edita-miembro="' + esc(m.id) + '" data-lw-equipo="' + esc(m.equipo_id) + '" data-lw-email="' + esc(m.closer_email) + '" data-lw-desde="' + esc(m.desde || '') + '" data-lw-hasta="' + esc(m.hasta || '') + '">Editar</button>' +
            (activo
              ? '<button type="button" class="px-3 py-1 rounded-full text-error hover:bg-error-container/40 font-label-md text-[12px]" data-lw-baja="' + esc(m.id) + '" data-lw-email="' + esc(m.closer_email) + '">Dar de baja</button>'
              : '')) + '</div></td></tr>';
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
    /* 23-sep-2026 (owner): «damos de alta el equipo de un Sales Manager y le
       asignamos comisión, y él configura en cada proyecto lo que quiera a sus
       closers». Administración ve todo; un manager, solo su equipo (la RLS ya
       lo recorta) y solo escribe el nivel closer — lo exige la base. */
    var esAdmC = !!(window.LW_V4 && window.LW_V4.esAdmin);
    var miEmailC = ((window.LW_V4 && window.LW_V4.miEmail) || '').toLowerCase();
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
      q(sb.from('condiciones_comision').select('id,equipo_id,proyecto_id,nivel,closer_email,pct_comision,base_calculo,importe_fijo,activo,vigente_desde,created_at').order('created_at', { ascending: false }), 'condiciones de comisión', cuerpo),
      q(sb.from('equipos_venta').select('id,nombre,manager_email,activo'), 'equipos de venta'),
      q(sb.from('proyectos').select('id,nombre'), 'proyectos'),
      q(sb.from('condicion_tramos').select('id,condicion_id,orden,disparador_tipo,umbral,pct_tramo').order('orden'), 'tramos de comisión'),
      q(sb.from('usuarios').select('email,nombre,rol,activo'), 'usuarios')
    ]).then(function (r) {
      var conds = r[0], equipos = r[1] || [], proyectos = r[2] || [], tramos = r[3] || [], usuarios = r[4] || [];
      if (!conds) return;
      if (!esAdmC) {
        var mios = equipos.filter(function (e) { return e.activo && (e.manager_email || '').toLowerCase() === miEmailC; });
        if (!mios.length) { notaSoloAdmin(); if (cuerpo) cuerpo.innerHTML = ''; return; }
        var idsMios = mios.map(function (e) { return e.id; });
        conds = conds.filter(function (c) { return c.equipo_id && idsMios.indexOf(c.equipo_id) !== -1; });
        equipos = mios;
        document.querySelectorAll('[data-lw-aviso-admin]').forEach(function (el) {
          el.querySelector('p').innerHTML = 'Eres el manager de <b class="text-on-surface">' + esc(mios.map(function (e) { return e.nombre; }).join(', ')) +
            '</b>: aquí configuras lo que pagas a tus closers — para todos los proyectos o para uno concreto, y si quieres a una persona en particular. Tu propia comisión la fija administración. Lo comprueba la base, no solo esta pantalla.';
        });
      }
      publicaUsuariosLista(usuarios);
      var equipoDe = {}; equipos.forEach(function (e) { equipoDe[e.id] = e.nombre; });
      var proyectoDe = {}; proyectos.forEach(function (p) { proyectoDe[p.id] = p.nombre; });
      var nombrePorEmail = {}; usuarios.forEach(function (u) { if (u.email) nombrePorEmail[u.email.toLowerCase()] = u.nombre || u.email; });
      var tramosDe = {}; tramos.forEach(function (t) { (tramosDe[t.condicion_id] = tramosDe[t.condicion_id] || []).push(t); });
      window.LW_V4.condicionesLista = {}; conds.forEach(function (c) { window.LW_V4.condicionesLista[c.id] = c; });
      window.LW_V4.tramosDe = tramosDe;   // los lee «Editar condición» (editores.js) para precargar los tramos

      pon2('k-cond-activas', String(conds.filter(function (c) { return c.activo; }).length));
      pon2('k-cond-total', String(conds.length));
      pon2('k-cond-manager', String(conds.filter(function (c) { return c.nivel === 'manager'; }).length));
      pon2('k-cond-closer', String(conds.filter(function (c) { return c.nivel === 'closer'; }).length));

      if (selEquipo) selEquipo.innerHTML = '<option value="">Todos los equipos</option>' +
        (esAdmC ? '<option value="__estandar__">Estándar de Lawang (sin equipo)</option>' : '') +
        equipos.map(function (e) { return '<option value="' + esc(e.id) + '">' + esc(e.nombre) + '</option>'; }).join('');
      if (selProyecto) selProyecto.innerHTML = '<option value="">Todos los proyectos</option>' +
        proyectos.map(function (p) { return '<option value="' + esc(p.id) + '">' + esc(p.nombre) + '</option>'; }).join('');

      function pinta() {
        if (!cuerpo) return;
        var fe = selEquipo ? selEquipo.value : '', fp = selProyecto ? selProyecto.value : '';
        var lista = conds.filter(function (c) {
          var okEquipo = !fe || (fe === '__estandar__' ? !c.equipo_id : c.equipo_id === fe);
          // una condición «todos los proyectos» aplica también al proyecto filtrado
          var okProyecto = !fp || c.proyecto_id === fp || !c.proyecto_id;
          return okEquipo && okProyecto;
        });
        cuerpo.innerHTML = lista.length ? lista.map(function (c) {
          var t = (tramosDe[c.id] || []).slice().sort(function (a, b) { return a.orden - b.orden; });
          var resumenTramos = t.length
            ? t.map(function (x) { return x.pct_tramo + '% ' + etiquetaDe(window.LW_V4.DISPARADORES, x.disparador_tipo); }).join(' · ')
            : '—';
          /* Estándar de Lawang (22-sep-2026, owner): equipo NULL = se aplica a
             quien cierra sin equipo, la paga Lawang; proyecto NULL = todos. */
          var estandar = !c.equipo_id;
          var quien = estandar
            ? (c.closer_email ? esc(nombrePorEmail[c.closer_email.toLowerCase()] || c.closer_email) + ' (override)' : 'quien cierre sin equipo · paga Lawang')
            : c.nivel === 'closer'
              ? (c.closer_email ? esc(nombrePorEmail[c.closer_email.toLowerCase()] || c.closer_email) + ' (override)' : 'todo el equipo · closer')
              : 'manager';
          var importeOBase = c.base_calculo === 'importe_fijo' ? fmt(c.importe_fijo, 'EUR') : (c.pct_comision + '%');
          var vigencia = c.vigente_desde && c.vigente_desde > '1900-01-01' ? '<br><span class="text-outline text-[11px]">desde ' + esc(fFecha(c.vigente_desde)) + '</span>' : '';
          return '<tr class="border-b border-outline-variant/30">' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + (estandar ? 'Estándar de Lawang' : esc(equipoDe[c.equipo_id] || '—')) + vigencia + '</td>' +
            '<td class="px-5 py-4 font-body-md text-body-md text-on-surface-variant">' + (c.proyecto_id ? esc(proyectoDe[c.proyecto_id] || '—') : 'Todos los proyectos') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + quien + '</td>' +
            '<td class="px-5 py-4 font-label-md text-label-md text-on-surface">' + esc(importeOBase) +
              '<br><span class="text-outline text-[11px]">' + esc(etiquetaDe(window.LW_V4.BASES_CALCULO, c.base_calculo)) + '</span></td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline max-w-xs">' + esc(resumenTramos) + '</td>' +
            '<td class="px-5 py-4"><span class="inline-flex items-center px-2.5 py-0.5 rounded-full font-label-md text-[11px] uppercase tracking-wider ' +
              (c.activo ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-surface-container-high text-on-surface-variant') + '">' +
              (c.activo ? 'Activa' : 'Inactiva') + '</span></td>' +
            (!esAdmC && c.nivel !== 'closer'
              ? '<td class="px-5 py-4 text-right font-body-sm text-body-sm text-outline">la fija administración</td></tr>'
              : '<td class="px-5 py-4 text-right"><div class="flex justify-end gap-2">' +
              /* Editar (22-sep-2026, owner): %, base, importe fijo, override y —si
                 no ha devengado— los tramos. Equipo, proyecto y nivel no: son la
                 identidad de la condición. */
              '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
              'data-lw-edita-cond="' + esc(c.id) + '" data-lw-etq="' + esc((estandar ? 'Estándar de Lawang' : (equipoDe[c.equipo_id] || '')) + ' · ' + (c.proyecto_id ? (proyectoDe[c.proyecto_id] || '') : 'Todos los proyectos')) + '">Editar</button>' +
              '<button type="button" class="px-3 py-1 rounded-full text-deep-lagoon hover:bg-surface-container-high font-label-md text-[12px]" ' +
              'data-lw-toggle-cond="' + esc(c.id) + '" data-lw-etq="' + esc((estandar ? 'Estándar de Lawang' : (equipoDe[c.equipo_id] || '')) + ' · ' + (c.proyecto_id ? (proyectoDe[c.proyecto_id] || '') : 'Todos los proyectos')) + '" data-lw-activo="' + (c.activo ? '1' : '0') + '">' +
              (c.activo ? 'Desactivar' : 'Reactivar') + '</button>' +
              /* Borrar solo la que ya esta desactivada (Seguridad, revision previa
                 18-sep): una activa puede estar aplicandose a contratos firmados
                 sin devengo todavia, y borrarla se llevaria sus tramos sin rastro.
                 Primero se desactiva —que deja de aplicarse— y entonces se borra. */
              (c.activo ? '' :
              '<button type="button" class="px-3 py-1 rounded-full text-error hover:bg-error-container/40 font-label-md text-[12px]" ' +
              'data-lw-borra-cond="' + esc(c.id) + '" data-lw-etq="' + esc((estandar ? 'Estándar de Lawang' : (equipoDe[c.equipo_id] || '')) + ' · ' + (c.proyecto_id ? (proyectoDe[c.proyecto_id] || '') : 'Todos los proyectos')) + '">Borrar</button>') +
              '</div></td></tr>');
        }).join('') : '<tr><td colspan="7" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">Ninguna condición para este filtro.</td></tr>';
      }
      pinta();
      if (selEquipo) selEquipo.addEventListener('change', pinta);
      if (selProyecto) selProyecto.addEventListener('change', pinta);

      if (cuerpo) cuerpo.addEventListener('click', function (ev) {
        var bE = ev.target.closest && ev.target.closest('[data-lw-edita-cond]');
        if (bE) {
          ev.preventDefault(); ev.stopPropagation();
          if (window.LW_V4 && window.LW_V4.abreEditaCondicion) window.LW_V4.abreEditaCondicion(bE);
          else toast('El editor aún no ha cargado — prueba de nuevo en un segundo.');
          return;
        }
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
  /* Ajustes (22-sep-2026): la tabla `parametros`, clave a clave. Cualquier
     admin la ve; guardar pasa por `parametro_set` (super admin en la base, con
     el rango de cada ajuste). No se guarda casilla a casilla: un botón por
     fila, para que un valor a medio teclear no llegue a la base. */
  /* RESERVAS POR VENCER (23-sep-2026, owner: «necesito una sección exclusiva
     para reservas por vencer, alta prio»). Lee `reservas_vencimiento()`, la
     MISMA función que usa el cron libera-reservas-vencidas: lo que se ve aquí
     es lo que el automatismo va a hacer, sin aritmética propia de plazos
     (vence = base + prórrogas lo calcula la base). La regla de días copia la
     del cron: el día que vence ya cuenta como vencida, y se libera sola el
     día vence + `reservas.dias_gracia`. SECURITY INVOKER: cada sesión ve solo
     los contratos que su RLS le deja (agente los suyos, manager su proyecto,
     admin todo). Solo lectura: prorrogar y liberar viven en la ficha de
     Operaciones con sus candados — aquí no se duplican. */
  REG['reservas'] = function (sb) {
    var lista = document.getElementById('lw-res-lista');
    var buscar = document.getElementById('lw-res-buscar');
    if (!lista) return;
    var T = function (x) { return (typeof lwT === 'function') ? lwT(x) : x; };
    var hoy = new Date().toISOString().slice(0, 10);
    function masDias(iso, n) { var d = new Date(iso + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
    function entre(a, b) { return Math.round((new Date(b + 'T00:00:00Z') - new Date(a + 'T00:00:00Z')) / 864e5); }
    function fecha(iso) { return iso ? new Date(iso + 'T00:00:00Z').toLocaleDateString('es-ES', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }) : '—'; }
    function pon(k, v) { var e = document.querySelector('[data-lw="' + k + '"]'); if (e) e.textContent = v; }
    Promise.all([
      q(sb.rpc('reservas_vencimiento'), 'reservas por vencer', lista),
      q(sb.from('parametros').select('clave,valor').eq('clave', 'reservas.dias_gracia'), 'días de gracia'),
      // autor de cada Carta: `reservas_vencimiento()` no lo trae y no se
      // amplía la función por esto — se lee del propio contrato (misma RLS).
      vig(sb.rpc('contratos_equipo').select('id,creado_por')).then(function (x) { return x.error ? [] : (x.data || []); }),
      autores(sb)
    ]).then(function (r) {
      var filas = r[0], AUT = r[3] || {}, autorDe = {};
      (r[2] || []).forEach(function (x) { autorDe[x.id] = x.creado_por; });
      if (filas == null) return;
      var g = (r[1] || [])[0], gracia = (g && typeof g.valor === 'number' && isFinite(g.valor)) ? g.valor : 3;
      pon('rk-gracia-nota', T('Tras vencer, el sistema espera') + ' ' + gracia + ' ' + T('días (margen interno, no es plazo del comprador) antes de liberar la parcela. Prorrogar o liberar: desde la ficha de la operación.'));
      // la función da una fila por PARCELA; aquí se lee por contrato
      var porC = {}, orden = [];
      filas.forEach(function (x) {
        var c = porC[x.contrato_id];
        if (!c) {
          c = porC[x.contrato_id] = { id: x.contrato_id, numero: x.numero, tipo: x.tipo, comprador: x.comprador_nombre,
            proyecto: x.proyecto_nombre || x.proyecto, vence: x.vence_el ? String(x.vence_el).slice(0, 10) : null,
            prorrogas: x.n_prorrogas || 0, parcelas: [], autor: autorDe[x.contrato_id] || null };
          orden.push(c);
        }
        if (x.codigo && c.parcelas.indexOf(x.codigo) === -1) c.parcelas.push(x.codigo);
      });
      orden.forEach(function (c) {
        c.parcelas.sort(function (a, b) { return String(a).localeCompare(String(b), 'es', { numeric: true }); });
        c.dias = c.vence ? entre(hoy, c.vence) : null;
        c.liberaEl = c.vence ? masDias(c.vence, gracia) : null;
        c.banda = c.vence == null ? 'sin' : c.dias <= 0 ? 'gracia' : c.dias <= 7 ? 'semana' : 'luego';
      });
      orden.sort(function (a, b) { return (a.vence || '9999') < (b.vence || '9999') ? -1 : (a.vence || '9999') > (b.vence || '9999') ? 1 : String(a.numero).localeCompare(String(b.numero)); });
      pon('rk-gracia', orden.filter(function (c) { return c.banda === 'gracia'; }).length);
      pon('rk-2d', orden.filter(function (c) { return c.dias != null && c.dias >= 1 && c.dias <= 2; }).length);
      pon('rk-7d', orden.filter(function (c) { return c.banda === 'semana'; }).length);
      pon('rk-total', orden.length);

      function estado(c) {
        if (c.dias == null) return pill(T('Sin fecha'), 'neutro');
        if (c.dias < 0) return pill(T('Venció hace') + ' ' + (-c.dias) + ' d', 'mal');
        if (c.dias === 0) return pill(T('Vence hoy'), 'mal');
        if (c.dias === 1) return pill(T('Vence mañana'), 'mal');
        return pill(c.dias + ' ' + T('días'), c.dias <= 2 ? 'mal' : c.dias <= 7 ? 'espera' : 'neutro');
      }
      function fila(c) {
        var extra = c.banda === 'gracia'
          ? (hoy >= c.liberaEl ? T('Se libera en la próxima pasada del sistema') : T('Se libera sola el') + ' ' + fecha(c.liberaEl))
          : '';
        var href = '/intranet/v4/operaciones/?contrato=' + encodeURIComponent(c.id);
        return '<a href="' + esc(href) + '" class="lw-res-fila">' +
          '<div class="lw-res-id"><span class="lw-res-num">' + esc(c.numero) + '</span>' +
            '<span class="lw-res-tipo">' + esc(tipoC(c.tipo)) + '</span></div>' +
          '<div class="lw-res-quien"><span class="lw-res-comp">' + esc(c.comprador || '—') + '</span>' +
            '<span class="lw-res-proy">' + esc(c.proyecto || '—') + (c.parcelas.length ? ' · ' + esc(T(c.parcelas.length > 1 ? 'Parcelas' : 'Parcela')) + ' ' + esc(c.parcelas.join(', ')) : '') + '</span>' +
            '<span class="lw-res-proy">' + esc(T('Creado por')) + ' ' + htmlAutor(AUT, c.autor) + '</span></div>' +
          '<div class="lw-res-vence"><span class="lw-res-lbl">' + esc(T('Vence')) + '</span><span>' + esc(fecha(c.vence)) + '</span>' +
            (c.prorrogas ? '<span class="lw-res-lbl">' + c.prorrogas + ' ' + esc(T(c.prorrogas > 1 ? 'prórrogas' : 'prórroga')) + '</span>' : '') + '</div>' +
          '<div class="lw-res-est">' + estado(c) + (extra ? '<span class="lw-res-extra">' + esc(extra) + '</span>' : '') + '</div>' +
          '<span class="lw-res-abrir">' + esc(T('Abrir')) + ' →</span></a>';
      }
      var BANDAS = [
        ['gracia', 'Vencidas — pendientes de liberar', 'mal'],
        ['semana', 'Vencen esta semana', 'espera'],
        ['luego', 'Más adelante', 'neutro'],
        ['sin', 'Sin fecha de vencimiento', 'neutro']
      ];
      function pinta() {
        var t = (buscar && buscar.value || '').trim().toLowerCase();
        var vis = !t ? orden : orden.filter(function (c) {
          return [c.numero, c.comprador, c.proyecto, c.parcelas.join(' '), c.autor, nombreAutor(AUT, c.autor)].join(' ').toLowerCase().indexOf(t) !== -1;
        });
        if (!orden.length) { lista.innerHTML = '<p class="font-body-md text-body-md text-on-surface-variant">' + esc(T('No hay Cartas de Reserva vivas pendientes de Bloqueo.')) + '</p>'; return; }
        if (!vis.length) { lista.innerHTML = '<p class="font-body-md text-body-md text-on-surface-variant">' + esc(T('Nada coincide con la búsqueda.')) + '</p>'; return; }
        lista.innerHTML = BANDAS.map(function (b) {
          var cs = vis.filter(function (c) { return c.banda === b[0]; });
          if (!cs.length) return '';
          var tono = LW_TONOS[b[2]];
          return '<div class="lw-res-banda"><h2 style="color:' + tono.tinta + '"><span class="lw-res-punto" style="background:' + tono.borde + '"></span>' +
            esc(T(b[1])) + ' <span class="lw-res-cuenta">' + cs.length + '</span></h2>' + cs.map(fila).join('') + '</div>';
        }).join('');
      }
      if (!document.getElementById('lw-res-css')) {
        var st = document.createElement('style'); st.id = 'lw-res-css';
        st.textContent =
          '.lw-res-banda{display:flex;flex-direction:column;gap:8px}' +
          '.lw-res-banda h2{display:flex;align-items:center;gap:8px;margin:0 0 4px;font:700 13px "Neue Kabel",sans-serif;letter-spacing:.06em;text-transform:uppercase}' +
          '.lw-res-punto{width:8px;height:8px;border-radius:999px;display:inline-block}' +
          '.lw-res-cuenta{font-weight:600;color:#8A8474}' +
          '.lw-res-fila{display:grid;grid-template-columns:minmax(120px,.8fr) minmax(0,2fr) minmax(120px,.9fr) minmax(150px,1.1fr) auto;gap:16px;align-items:center;' +
            'padding:14px 16px;border:1px solid #E4E0D6;border-radius:10px;background:#fff;text-decoration:none;color:#2E3437;font:500 13px "Neue Kabel",sans-serif;transition:background .15s,border-color .15s}' +
          '.lw-res-fila:hover{background:#FAF8F3;border-color:#C9C3B4}' +
          '.lw-res-id,.lw-res-quien,.lw-res-vence,.lw-res-est{display:flex;flex-direction:column;gap:3px;min-width:0}' +
          '.lw-res-num{font-weight:700;color:#104C4F;font-size:14px}' +
          '.lw-res-tipo,.lw-res-lbl,.lw-res-proy,.lw-res-extra{color:#8A8474;font-size:12px}' +
          '.lw-res-comp{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
          '.lw-res-proy{overflow:hidden;text-overflow:ellipsis}' +
          '.lw-res-est{align-items:flex-start}' +
          '.lw-res-abrir{font-weight:600;font-size:12px;color:#104C4F;text-decoration:underline;white-space:nowrap}' +
          '@media (max-width:900px){.lw-res-fila{grid-template-columns:1fr 1fr;gap:10px 14px}.lw-res-quien{grid-column:1/-1;order:-1}.lw-res-abrir{grid-column:1/-1}}';
        document.head.appendChild(st);
      }
      pinta();
      if (buscar) buscar.addEventListener('input', pinta);
    });
  };

  REG.reparto = function (sb) { return REG.comisiones(sb, { soloEquipo: true }); };

  REG['ajustes'] = function (sb) {
    if (!(window.LW_V4 && window.LW_V4.esAdmin)) { notaSoloAdmin(); return; }
    var cuerpo = document.getElementById('lw-ajustes-lista');
    var soloLee = !(window.LW_V4 && window.LW_V4.esSuperAdmin);
    function fFechaHora(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x).slice(0, 10) : d.toLocaleString('es-ES'); }
    function pinta() {
      q(sb.from('parametros').select('*').order('grupo').order('orden'), 'ajustes', cuerpo).then(function (rows) {
        if (!rows) return;
        if (!rows.length) { cuerpo.innerHTML = '<tr><td colspan="4" class="px-5 py-8 text-center font-body-md text-body-md text-on-surface-variant">No hay ajustes dados de alta.</td></tr>'; return; }
        cuerpo.innerHTML = rows.map(function (r) {
          var esNum = typeof r.valor === 'number';
          var rango = esNum && (r.minimo != null || r.maximo != null) ? ' <span class="text-outline">(' + (r.minimo != null ? r.minimo : '…') + ' – ' + (r.maximo != null ? r.maximo : '…') + ')</span>' : '';
          return '<tr class="border-b border-outline-variant/30" data-clave="' + esc(r.clave) + '">' +
            '<td class="px-5 py-4"><div class="font-label-md text-label-md text-on-surface">' + esc(r.etiqueta) + '</div>' +
              (r.ayuda ? '<div class="font-body-sm text-body-sm text-outline mt-1">' + esc(r.ayuda) + '</div>' : '') +
              '<div class="font-body-sm text-[11px] text-outline mt-1"><code>' + esc(r.clave) + '</code>' + rango + '</div></td>' +
            '<td class="px-5 py-4">' + (esNum
              ? '<input type="number" step="1" data-k="valor" value="' + esc(r.valor) + '"' + (r.minimo != null ? ' min="' + esc(r.minimo) + '"' : '') + (r.maximo != null ? ' max="' + esc(r.maximo) + '"' : '') + (soloLee ? ' disabled' : '') +
                ' style="width:110px;padding:8px 10px;border:1px solid #E4DCCB;border-radius:10px;font:inherit">'
              : '<code>' + esc(JSON.stringify(r.valor)) + '</code>') + '</td>' +
            '<td class="px-5 py-4 font-body-sm text-body-sm text-outline">' + esc(fFechaHora(r.actualizado_en)) + (r.actualizado_por ? '<br>' + esc(r.actualizado_por) : '') + '</td>' +
            '<td class="px-5 py-4 text-right">' + (esNum && !soloLee
              ? '<button type="button" data-guardar="1" class="px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">Guardar</button>'
              : '') + '</td></tr>';
        }).join('');
      });
    }
    pinta();
    if (cuerpo && !cuerpo._wired) {
      cuerpo._wired = true;
      cuerpo.addEventListener('click', function (ev) {
        var b = ev.target.closest && ev.target.closest('[data-guardar]');
        if (!b) return;
        ev.preventDefault(); ev.stopPropagation();
        var tr = b.closest('tr'); var clave = tr.getAttribute('data-clave');
        var inp = tr.querySelector('[data-k="valor"]');
        var n = parseInt(inp.value, 10);
        if (!isFinite(n)) { toast('Pon un número entero.'); return; }
        b.disabled = true;
        sb.rpc('parametro_set', { p_clave: clave, p_valor: n }).then(function (rr) {
          b.disabled = false;
          if (rr.error) { toast('No se guardó: ' + (rr.error.message || 'sin detalle')); return; }
          toast('Guardado: ' + clave + ' = ' + n + '. Se aplica desde ahora (la próxima pasada del automatismo, la próxima prórroga).');
          pinta();
        });
      });
    }
    var aviso = document.getElementById('lw-ajustes-solo-lectura');
    if (aviso) aviso.hidden = !soloLee;
  };

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
      /* El banderín «V4 · DATOS EN VIVO» se retiró con el de «Maqueta» de
         nav.js (S17, 23-sep-2026): era un aviso de maqueta, y lo que queda
         en pantalla ya son datos reales. */

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
      // el uuid de sesion (auth.uid()): lo necesita cualquier pantalla que
      // compare contra `creado_por` u otra columna de autoria, que es un uuid
      // y no un email (S8, Comisiones/Solicitudes).
      window.LW_V4.miId = (aut.session && aut.session.user && aut.session.user.id) || '';
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

      campanaV4(aut, rol);
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
