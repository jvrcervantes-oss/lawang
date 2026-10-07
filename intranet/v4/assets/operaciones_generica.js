/* Operaciones GENÉRICAS del ERP maestro (desacople del núcleo comercial, corte C: subtareas 5a y 5b, 5-oct-2026).
 * Encargo: encargos/20261005_erp_desacople_nucleo_comercial.md. Decisión del estudio (2-oct): pantalla y ficha NUEVAS en
 * ficheros propios, no `fichaContrato` con una bandera.
 *
 * QUÉ ES. La pantalla `operaciones` de la v4 es contractual: carga con `lwOperacionesCargar` (contratos_equipo,
 * contrato_firmas_equipo…) y una fila es la raíz de una cadena de contratos. Un ERP sin contratos la veía vacía. Esta pieza
 * lista las operaciones que existen en `operaciones_equipo()` y abre su ficha con las cifras de `operacion_cifras()` y sus
 * facturas de `facturas_equipo()`. NO toca contratos: ni los pide ni los nombra.
 *
 * CUÁNDO SE USA. Solo en el maestro con `contratos` apagado: el elegido es `REG['operaciones']` al final de datos.js
 * (`AXW_NUCLEO_OPERACION && !contratosActivo()`, tras esperar a `AXW_MODULOS_LISTOS`). Lawang no pasa nunca por aquí.
 *
 * LO QUE DECIDE LA BASE, no esta pantalla (contexto/patrones_tecnicos.md → «Frontera frontend / backend»):
 *  · qué operaciones ve cada usuario: `operaciones_equipo()` y su política de lectura (`operacion_visible`). Un usuario de
 *    rol bajo recibe solo las suyas; esta pantalla no filtra nada por su cuenta.
 *  · todos los importes: `importe_total` es la columna de la operación; facturado, cobrado y pendiente salen de
 *    `operacion_cifras` y el pendiente de cada factura de `facturas_pendiente_equipo`. Aquí NO se suma ni se resta un solo
 *    importe: se pintan tal cual llegan. Una cifra que la base no da se pinta «—», nunca «0».
 *  · `operacion_cifras` devuelve CERO filas (no un error) cuando la operación no existe o no es visible: se dice
 *    «no visible», y entonces no se pide ni una factura (facturas_equipo es más ancha que la visibilidad de la operación).
 * SIN escrituras: ni insert, ni update, ni delete, ni RPC que escriba. «Borrar operación» no se ofrece (subtarea 5c).
 * SIN lectura directa de tablas: solo RPC.
 *
 * Se engancha por `data-accion` / `data-opsg-*`, nunca por un rótulo. Todo dato que viene de la base entra con `esc()`.
 * Lo que necesita de datos.js (`vig`, `esc`, `fmt`, `fallo`, el cajón) llega en `ayudas`/globales: aquí no se copia.
 */
(function () {
  'use strict';

  var TOPE = 1000;                       // el límite por defecto de la API de Supabase es 1000: pedir más no trae más y el aviso no saltaría nunca. Si se alcanza, se DICE (una lista parcial que no avisa miente)
  var TROZO_CLIENTES = 80;               // ids por petición al resolver nombres (la URL de PostgREST no es infinita)
  var CAMPOS = 'id,referencia,client_id,tipo,estado,importe_total,moneda,creado_por,created_at';
  var ESTADOS = [['borrador', 'Borrador', 'espera'], ['abierta', 'Abierta', 'neutro'], ['cerrada', 'Cerrada', 'ok'], ['cancelada', 'Cancelada', 'mal']];
  var TIPOS = { venta: 'Venta', alquiler: 'Alquiler', servicio: 'Servicio' };
  var CLS_CHIP_BASE = 'px-3.5 py-1.5 rounded-full font-label-md text-body-sm shrink-0';
  var CLS_CHIP_ON = 'bg-primary text-on-primary shadow-sm';
  var CLS_CHIP_OFF = 'bg-surface-container-low text-on-surface-variant hover:bg-surface-container transition-colors';

  var A = null;                          // ayudas de datos.js
  var E = null;                          // estado de la pantalla

  function esc(s) { return A && A.esc ? A.esc(s) : String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function T(x) { return (typeof lwT === 'function') ? lwT(x) : x; }
  function vig(p) { return A && A.vig ? A.vig(p) : p; }
  function activo(m) { return window.axwModuloActivo ? window.axwModuloActivo(m) : true; }
  function ok(t) { if (typeof toast === 'function') toast(t); }
  function mal(t) { if (typeof toastMal === 'function') toastMal(t); else ok(t); }
  function dinero(n, m) {
    if (n == null || n === '') return '—';
    if (A && A.fmt) return A.fmt(n, m);
    return new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 }).format(Math.round(Number(n) || 0)) + (m ? ' ' + m : '');
  }
  function fecha(x) {
    if (!x) return '—';
    var d = new Date(x);
    return isNaN(d) ? '—' : d.toLocaleDateString('es-ES', { day: '2-digit', month: 'short', year: 'numeric' });
  }
  function infoEstado(e) { for (var i = 0; i < ESTADOS.length; i++) if (ESTADOS[i][0] === e) return ESTADOS[i]; return [e, e || '—', 'neutro']; }
  function etiqueta(texto, tono) {
    var H = window.lwCajonHtml;
    if (H && H.tag) return H.tag(texto, tono);
    return '<span>' + esc(texto) + '</span>';
  }
  function msgError(e) { return e && e.message ? e.message : (e && e.code ? String(e.code) : 'sin detalle'); }

  /* ---------------- la pantalla ---------------- */

  function oculta(el) { if (el) el.style.display = 'none'; }
  function seccionDe(sel) { var e = document.querySelector(sel); return e && e.closest ? e.closest('section') : null; }

  /* En modo genérico se OCULTAN las piezas contractuales de la pantalla vieja (tarjetas con sumas, filtros, tabla); el
     marcado y los selectores de la vieja no cambian. «Nueva operación» llevaba a /contracts/app.html (módulo apagado). */
  function preparaPantalla() {
    oculta(seccionDe('[data-lw="k-ops"]'));
    oculta(seccionDe('[data-lw="buscador"]'));
    oculta(document.getElementById('lw-ops-caja'));
    oculta(document.querySelector('main [data-accion="nueva-operacion"]'));
    var p = document.querySelector('main .lw-cabecera p');
    if (p) p.textContent = T('Las operaciones de tu ERP, con su cliente, su importe pactado y sus facturas. Pulsa una fila para abrir su ficha.');
    var caja = document.getElementById('lw-ops-caja');
    var sec = document.getElementById('lw-opsg');
    if (!sec && caja && caja.parentNode) {
      sec = document.createElement('section');
      sec.id = 'lw-opsg';
      sec.className = 'bg-surface-container-lowest rounded-xl shadow-sm overflow-hidden';
      caja.parentNode.insertBefore(sec, caja.nextSibling);
    }
    return sec;
  }

  /* Estilos PROPIOS de esta pantalla (prefijo opsg-), inyectados aquí y no en tw*.css: esos CSS los comparten todas las
     páginas de Lawang y una regla nueva allí cambiaría el aspecto de pantallas ya publicadas. Mismos valores que las
     utilidades que sustituyen (ancho del buscador, placeholder, divisores y pie con superficie al 40 %, hover, foco, cabecera en fila). */
  function inyectaEstilos() {
    if (document.getElementById('lw-opsg-css')) return;
    var st = document.createElement('style'); st.id = 'lw-opsg-css';
    st.textContent =
      '.opsg-buscar::placeholder{color:rgb(190 179 165)}' +
      '.opsg-filas>:not([hidden])~:not([hidden]){border-color:rgb(233 232 227/.4)}' +
      '.opsg-pie{padding-top:.875rem;padding-bottom:.875rem;background-color:rgb(245 244 238/.4)}' +
      '.opsg-buscar:focus{outline:2px solid transparent;outline-offset:2px}' +
      '.opsg-act:hover{color:rgb(46 52 55)}' +
      '@media (min-width:1024px){.opsg-cab{flex-direction:row;align-items:center}.opsg-buscabox{width:auto}.opsg-buscar{width:20rem}}';
    document.head.appendChild(st);
  }

  function pintaEsqueleto(sec) {
    inyectaEstilos();
    sec.innerHTML =
      '<div class="px-6 py-4 bg-surface-container-low/60 opsg-cab flex flex-col justify-between gap-4">' +
        '<div class="flex items-center gap-3"><span class="font-label-md text-volcanic-ash text-body-sm uppercase tracking-wider font-bold">' + esc(T('Operaciones')) + '</span>' +
        '<span class="px-2 py-0.5 rounded-full bg-surface-container text-stone-sand text-[11px] font-label-md" data-opsg-cuenta>…</span></div>' +
        '<div class="opsg-buscabox flex items-center gap-2 w-full"><input data-opsg-buscar type="text" class="opsg-buscar w-full px-4 py-2 bg-surface-container-low rounded-full font-body-sm text-volcanic-ash shadow-sm" placeholder="' + esc(T('Buscar referencia, cliente, tipo o autor…')) + '">' +
        '<button type="button" data-real data-accion="opsg-actualizar" class="opsg-act flex items-center gap-1 text-stone-sand text-body-sm font-label-md shrink-0"><span class="material-symbols-outlined text-[16px]">refresh</span><span>' + esc(T('Actualizar')) + '</span></button></div>' +
      '</div>' +
      '<div class="px-6 py-3 flex items-center gap-1.5 overflow-x-auto" data-opsg-chips></div>' +
      '<div data-opsg-aviso></div>' +
      '<div class="overflow-x-auto"><table class="w-full text-left border-collapse"><thead><tr class="bg-surface-container-low text-on-surface-variant font-label-md text-[11px] tracking-wider uppercase">' +
        '<th class="py-3 px-4 font-bold">' + esc(T('Referencia')) + '</th><th class="py-3 px-4 font-bold">' + esc(T('Cliente')) + '</th><th class="py-3 px-4 font-bold">' + esc(T('Tipo')) + '</th>' +
        '<th class="py-3 px-4 font-bold">' + esc(T('Situación')) + '</th><th class="py-3 px-4 font-bold text-right">' + esc(T('Importe pactado')) + '</th>' +
        '<th class="py-3 px-4 font-bold">' + esc(T('Creada')) + '</th><th class="py-3 px-4 font-bold">' + esc(T('Autor')) + '</th></tr></thead>' +
        '<tbody class="opsg-filas divide-y text-body-sm font-body-sm" data-opsg-lista><tr><td class="py-8 px-6 text-center text-stone-sand" colspan="7">' + esc(T('Trayendo las operaciones…')) + '</td></tr></tbody></table></div>' +
      '<div class="opsg-pie px-6 text-body-sm text-stone-sand" data-opsg-pie></div>';
  }

  function nombreDe(o) {
    if (!o.client_id) return null;
    return E.nombres[o.client_id] || null;
  }

  function filaHtml(o) {
    var et = infoEstado(o.estado), nom = nombreDe(o);
    return '<tr data-opsg-fila data-accion="abrir-operacion" data-op-id="' + esc(o.id) + '" class="hover:bg-surface-alt/50 transition-colors cursor-pointer align-top">' +
      '<td class="py-3 px-4 font-label-md font-bold text-deep-lagoon whitespace-nowrap">' + esc(o.referencia || '—') + '</td>' +
      '<td class="py-3 px-4 font-label-md text-volcanic-ash font-semibold">' + (nom ? esc(nom) : '<span class="text-stone-sand">' + (o.client_id ? esc(T('Cliente sin nombre legible')) : esc(T('Sin cliente'))) + '</span>') + '</td>' +
      '<td class="py-3 px-4 text-volcanic-ash">' + esc((TIPOS[o.tipo] ? T(TIPOS[o.tipo]) : (o.tipo || '—'))) + '</td>' +
      '<td class="py-3 px-4 whitespace-nowrap">' + etiqueta(T(et[1]), et[2]) + '</td>' +
      '<td class="py-3 px-4 text-right font-kpi-number text-volcanic-ash whitespace-nowrap">' + (o.importe_total == null ? '<span class="text-stone-sand text-[12px]">' + esc(T('sin fijar')) + '</span>' : esc(dinero(o.importe_total, o.moneda))) + '</td>' +
      '<td class="py-3 px-4 text-on-surface-variant whitespace-nowrap">' + esc(fecha(o.created_at)) + '</td>' +
      '<td class="py-3 px-4 text-on-surface-variant text-[12px]">' + esc(o.creado_por || '—') + '</td></tr>';
  }

  function visibles() {
    var t = E.texto, est = E.estado;
    return E.lista.filter(function (o) {
      if (est !== '*' && o.estado !== est) return false;
      if (!t) return true;
      var pajar = [o.referencia, nombreDe(o), o.tipo, o.creado_por].join(' ').toLowerCase();
      return pajar.indexOf(t) !== -1;
    });
  }

  function pintaLista() {
    var sec = E.sec, tbody = sec.querySelector('[data-opsg-lista]');
    var v = visibles();
    tbody.innerHTML = v.length ? v.map(filaHtml).join('') :
      '<tr><td class="py-8 px-6 text-center text-stone-sand" colspan="7">' + esc(T(E.lista.length ? 'Ninguna operación coincide con el filtro.' : 'Todavía no hay operaciones.')) + '</td></tr>';
    var c = sec.querySelector('[data-opsg-cuenta]'); if (c) c.textContent = v.length + ' ' + T('visibles');
    var pie = sec.querySelector('[data-opsg-pie]');
    if (pie) pie.textContent = T('Mostrando') + ' ' + v.length + ' ' + T('de') + ' ' + E.lista.length + ' ' + T('operaciones');
  }

  function pintaChips() {
    var cont = E.sec.querySelector('[data-opsg-chips]');
    var cuenta = {}; E.lista.forEach(function (o) { cuenta[o.estado] = (cuenta[o.estado] || 0) + 1; });
    var ops = [['*', T('Todas'), E.lista.length]];
    ESTADOS.forEach(function (e) { if (cuenta[e[0]]) ops.push([e[0], T(e[1]), cuenta[e[0]]]); });
    cont.innerHTML = ops.map(function (x) {
      return '<button type="button" data-real data-opsg-estado="' + esc(x[0]) + '" class="' + CLS_CHIP_BASE + ' ' + (E.estado === x[0] ? CLS_CHIP_ON : CLS_CHIP_OFF) + '">' + esc(x[1]) + ' ' + x[2] + '</button>';
    }).join('');
  }

  function aviso(html) {
    var a = E.sec.querySelector('[data-opsg-aviso]');
    if (a) a.innerHTML = html || '';
  }
  function banda(texto, rojo) {
    return '<div style="margin:0 24px 12px;padding:10px 14px;border-radius:8px;font:500 13px \'Neue Kabel\',sans-serif;' +
      (rojo ? 'background:#ffdad6;color:#93000a' : 'background:#f4ecd8;color:#6b5420') + '">' + esc(texto) + '</div>';
  }

  /* ---------------- carga ---------------- */

  function nombresClientes(sb, ids) {
    if (!ids.length) return Promise.resolve({ mapa: {}, fallo: null });
    if (!activo('compradores')) return Promise.resolve({ mapa: {}, fallo: null, omitido: true });
    var trozos = [];
    for (var i = 0; i < ids.length; i += TROZO_CLIENTES) trozos.push(ids.slice(i, i + TROZO_CLIENTES));
    return Promise.all(trozos.map(function (t) {
      return vig(sb.rpc('compradores_directorio').select('id,full_name').in('id', t)).then(function (r) { return r; }, function (e) { return { error: e }; });
    })).then(function (rs) {
      var mapa = {}, fallo = null;
      rs.forEach(function (r) {
        if (r.error) { fallo = fallo || r.error; return; }
        (r.data || []).forEach(function (c) { mapa[c.id] = c.full_name; });
      });
      return { mapa: mapa, fallo: fallo };
    });
  }

  function carga() {
    var sb = E.sb;
    aviso('');
    return vig(sb.rpc('operaciones_equipo').select(CAMPOS).order('created_at', { ascending: false }).limit(TOPE))
      .then(function (r) { return r; }, function (e) { return { error: e }; })
      .then(function (r) {
        if (r.error) {
          console.error('[v4 operaciones] operaciones_equipo no cargó', r.error);
          E.lista = []; E.cargado = false;
          E.sec.querySelector('[data-opsg-lista]').innerHTML = '<tr><td class="py-8 px-6 text-center" colspan="7" style="color:#93000a">' +
            esc(T('No se han podido cargar las operaciones')) + ' (' + esc(msgError(r.error)) + '). ' + esc(T('No es que no haya ninguna: la consulta ha fallado.')) + '</td></tr>';
          var c = E.sec.querySelector('[data-opsg-cuenta]'); if (c) c.textContent = '—';
          var pie = E.sec.querySelector('[data-opsg-pie]'); if (pie) pie.textContent = '';
          pintaChips();
          return null;
        }
        E.lista = r.data || []; E.cargado = true;
        var ids = []; E.lista.forEach(function (o) { if (o.client_id && ids.indexOf(o.client_id) === -1) ids.push(o.client_id); });
        return nombresClientes(sb, ids).then(function (n) {
          E.nombres = n.mapa;
          var av = '';
          if (E.lista.length >= TOPE) av += banda(T('La lista está recortada al tope de') + ' ' + TOPE + ' ' + T('operaciones: pide a Desarrollo subir el tope.'), true);
          if (n.fallo) { console.error('[v4 operaciones] compradores_directorio no cargó', n.fallo); av += banda(T('No se han podido leer los nombres de los clientes: las operaciones se enseñan sin ellos.'), true); }
          else if (n.omitido) av += banda(T('El módulo de clientes no está activado en este ERP: las operaciones se enseñan sin nombre de cliente.'), false);
          aviso(av);
          pintaChips(); pintaLista();
          return E.lista;
        });
      });
  }

  /* ---------------- ficha (5b) ---------------- */

  function cifraHtml(v, m) { return v == null ? '<span style="opacity:.6">—</span>' : esc(dinero(v, m)); }

  function estadoFactura(f) {
    if (f.anulada) return [T('Anulada'), 'mal'];
    if (f.rectifica_id) return [T('Rectificativa'), 'espera'];
    return [T('Vigente'), 'ok'];
  }
  function tipoFactura(t) { return t === 'recibi' ? T('Recibí') : t === 'proforma' ? T('Proforma') : T('Factura'); }

  function fichaOperacion(o) {
    var H = window.lwCajonHtml;
    if (!(window.lwCajon && H)) { mal(T('La ficha aún no ha cargado — prueba de nuevo en un segundo.')); return; }
    var sb = E.sb, et = infoEstado(o.estado), nom = nombreDe(o);
    var caj = window.lwCajon({
      sub: T('Operación'),
      estado: [T(et[1]), et[2]],
      titulo: o.referencia || '',
      bajoTitulo: nom || (o.client_id ? T('Cliente sin nombre legible') : T('Sin cliente')),
      cuerpo: '<p style="margin:0;font-size:13px;color:#8A8474">' + esc(T('Trayendo la ficha…')) + '</p>',
      acciones: [{ texto: T('Cerrar'), cerrar: true }]
    });
    var cuerpoOp = H.seccion(T('Operación'),
      H.dato(T('Referencia'), o.referencia) +
      H.dato(T('Tipo'), (TIPOS[o.tipo] ? T(TIPOS[o.tipo]) : (o.tipo || '—'))) +
      H.dato(T('Situación'), etiqueta(T(et[1]), et[2]), { html: 1 }) +
      H.dato(T('Cliente'), o.client_id ? H.enlace('/intranet/v4/compradores/?id=' + encodeURIComponent(o.client_id), nom || T('Ficha de cliente')) : null, { html: !!o.client_id }) +
      H.dato(T('Importe pactado'), o.importe_total == null ? null : dinero(o.importe_total, o.moneda)) +
      H.dato(T('Creada'), fecha(o.created_at)) +
      H.dato(T('Autor'), o.creado_por));

    vig(sb.rpc('operacion_cifras', { p_op: o.id }).maybeSingle()).then(function (r) { return r; }, function (e) { return { error: e }; }).then(function (rc) {
      if (!document.getElementById('lw-cajon')) return;               // la cerraron antes de que llegara
      if (rc.error) {
        console.error('[v4 operaciones] operacion_cifras no cargó', rc.error);
        caj.cuerpo.innerHTML = cuerpoOp + H.nota(T('No se han podido leer las cifras de la operación') + ' (' + esc(msgError(rc.error)) + '). ' + T('No se enseñan facturas hasta saber que puedes ver esta operación.'));
        return;
      }
      var c = rc.data;
      if (!c) {
        /* CERO filas = la base no la da: no existe o no es visible para este usuario. Nunca se pinta como ceros y no se
           pide ni una factura (facturas_equipo es más ancha que la visibilidad de la operación). */
        caj.cuerpo.innerHTML = cuerpoOp + H.nota(T('La base no devuelve cifras para esta operación: no existe o no tienes acceso a ella.'));
        return;
      }
      var m = o.moneda;
      var cuerpoCifras = H.seccion(T('Cifras'),
        H.cifras([
          [T('Contratado'), cifraHtml(c.contratado, m), c.contratado == null ? T('sin importe pactado') : ''],
          [T('Facturado'), cifraHtml(c.facturado, m)],
          [T('Cobrado'), cifraHtml(c.cobrado, m)],
          [T('Pendiente de facturar'), cifraHtml(c.pendiente_facturar, m)],
          [T('Pendiente de cobro'), cifraHtml(c.pendiente_cobro, m)],
          [T('A cuenta del cliente'), cifraHtml(c.a_cuenta_cliente, m)]
        ]));
      caj.cuerpo.innerHTML = cuerpoOp + cuerpoCifras + H.seccion(T('Facturas'), '<p style="margin:0;font-size:13px;color:#8A8474">' + esc(T('Trayendo las facturas…')) + '</p>');
      if (!activo('facturas')) {
        caj.cuerpo.innerHTML = cuerpoOp + cuerpoCifras + H.seccion(T('Facturas'), H.nota(T('El módulo de facturas no está activado en este ERP.')));
        return;
      }
      vig(sb.rpc('facturas_equipo').select('id,numero,tipo,total,moneda,anulada,fecha_emision,created_at,rectifica_id').eq('operacion_id', o.id).order('created_at'))
        .then(function (r) { return r; }, function (e) { return { error: e }; }).then(function (rf) {
          if (!document.getElementById('lw-cajon')) return;
          var seccion;
          if (rf.error) {
            console.error('[v4 operaciones] facturas_equipo no cargó', rf.error);
            seccion = H.seccion(T('Facturas'), H.nota(T('No se han podido leer las facturas de esta operación') + ' (' + esc(msgError(rf.error)) + ').'));
            caj.cuerpo.innerHTML = cuerpoOp + cuerpoCifras + seccion;
            return;
          }
          var fs = rf.data || [];
          if (!fs.length) {
            caj.cuerpo.innerHTML = cuerpoOp + cuerpoCifras + H.seccion(T('Facturas'), H.nota(T('Esta operación aún no tiene facturas.')));
            return;
          }
          var ids = fs.filter(function (f) { return f.tipo === 'factura' && !f.anulada && !f.rectifica_id; }).map(function (f) { return f.id; });
          var pPend = ids.length ? vig(sb.rpc('facturas_pendiente_equipo').select('factura_id,pendiente').in('factura_id', ids)).then(function (r) { return r; }, function (e) { return { error: e }; }) : Promise.resolve({ data: [] });
          pPend.then(function (rp) {
            if (!document.getElementById('lw-cajon')) return;
            var pend = {}; (rp.data || []).forEach(function (x) { pend[x.factura_id] = x.pendiente; });
            if (rp.error) console.error('[v4 operaciones] facturas_pendiente_equipo no cargó', rp.error);
            var filas = fs.map(function (f) {
              var es = estadoFactura(f);
              var pen = (rp.error && ids.indexOf(f.id) !== -1) ? '—' : (pend[f.id] == null ? '—' : esc(dinero(pend[f.id], f.moneda)));
              return [esc(f.numero || '—'), esc(tipoFactura(f.tipo)), etiqueta(es[0], es[1]), esc(f.total == null ? '—' : dinero(f.total, f.moneda)), pen,
                '<button type="button" data-real data-accion="abrir-factura" data-factura-id="' + esc(f.id) + '" class="las-btn2">' + esc(T('Abrir')) + '</button>'];
            });
            caj.cuerpo.innerHTML = cuerpoOp + cuerpoCifras + H.seccion(T('Facturas') + ' (' + fs.length + ')',
              H.tabla([T('Número'), T('Tipo'), T('Estado'), T('Importe'), T('Pendiente'), ''], filas) +
              (rp.error ? H.nota(T('No se ha podido leer lo pendiente de cada factura.')) : ''));
          });
        });
    });
    caj.cuerpo.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-accion="abrir-factura"]');
      if (!b) return;
      ev.preventDefault();
      var id = b.getAttribute('data-factura-id');
      if (window.LW_V4 && typeof window.LW_V4.verDocumento === 'function') window.LW_V4.verDocumento(id, function () { fichaOperacion(o); });
      else location.href = '/intranet/v4/facturas/?id=' + encodeURIComponent(id);
    });
  }

  /* ---------------- arranque ---------------- */

  function enlaza(sec) {
    sec.addEventListener('click', function (ev) {
      var t = ev.target;
      var chip = t.closest && t.closest('[data-opsg-estado]');
      if (chip) { ev.stopPropagation(); E.estado = chip.getAttribute('data-opsg-estado'); pintaChips(); pintaLista(); return; }
      var act = t.closest && t.closest('[data-accion="opsg-actualizar"]');
      if (act) { ev.stopPropagation(); carga(); return; }
      var fila = t.closest && t.closest('[data-accion="abrir-operacion"]');
      if (fila) {
        ev.stopPropagation();
        var id = fila.getAttribute('data-op-id');
        var o = E.lista.filter(function (x) { return x.id === id; })[0];
        if (o) fichaOperacion(o);
      }
    });
    sec.addEventListener('input', function (ev) {
      var i = ev.target;
      if (i && i.hasAttribute && i.hasAttribute('data-opsg-buscar')) { E.texto = String(i.value || '').trim().toLowerCase(); pintaLista(); }
    });
  }

  window.lwOperacionesGenerica = function (sb, ayudas) {
    A = ayudas || {};
    var sec = preparaPantalla();
    if (!sec) { if (A.fallo) A.fallo('operaciones', 'no encuentro dónde pintar las operaciones', document.getElementById('lw-ops-caja')); return; }
    E = { sb: sb, sec: sec, lista: [], nombres: {}, texto: '', estado: '*', cargado: false };
    pintaEsqueleto(sec);
    enlaza(sec);
    return carga().then(function (lista) {
      if (!lista) return;
      /* ?operacion=<id>: abre esa ficha si está entre las que la base da a ESTE usuario. Una ajena no aparece aquí y no se
         intenta rescatar por otro camino. */
      var pedido = new URLSearchParams(location.search).get('operacion');
      if (!pedido) return;
      var o = lista.filter(function (x) { return x.id === pedido; })[0];
      if (o) fichaOperacion(o); else mal(T('No encuentro esa operación entre las que puedes ver.'));
    });
  };
})();
