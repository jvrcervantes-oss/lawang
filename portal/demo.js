/* demo.js — el portal de clientes con datos FICTICIOS, sin tocar la base (7-oct-2026, owner).
 *
 * Para que un compañero pueda retocar el estilo del portal con todo relleno, sin usuario real ni datos de ningún
 * cliente. Solo se carga si la dirección lleva `?demo` (index.html lo inyecta justo después de supabase-js) y
 * sustituye `supabase.createClient` por un cliente falso: el cliente REAL no llega a crearse, así que no hay
 * sesión, ni clave, ni llamada a la base, ni RLS de por medio. Mientras dure el modo demo, cualquier petición a
 * *.supabase.co se bloquea aquí mismo.
 *
 * Lo que el portal usa del cliente es solo `auth` (getSession, onAuthStateChange, signInWithPassword, signOut,
 * updateUser), `rpc` y `storage`; es lo único que se simula. Las escrituras (abrir ticket, enviar mensaje, avisos,
 * preferencias) modifican la memoria de esta pestaña y se pierden al recargar.
 *
 * El usuario y la contraseña de demo están escritos aquí a propósito: no protegen nada, los datos son inventados.
 * Una cinta fija «Demo · datos ficticios» se ve siempre, para que nadie confunda esto con el portal real.
 * Las fechas son relativas a hoy, así que la campana siempre tiene avisos y el próximo pago siempre vence pronto. */
(function () {
  'use strict';
  var EMAIL = 'demo@example.invalid', PASS = 'Lawang-demo-2026', CLAVE = 'lw-demo-sesion';

  var DIA = 86400000, HOY = Date.now();
  function iso(n) { return new Date(HOY + n * DIA).toISOString(); }
  function dia(n) { return iso(n).slice(0, 10); }

  /* ───────── imágenes dibujadas (portadas y fotos de obra) ───────── */
  function svgUrl(s) { return 'data:image/svg+xml;utf8,' + encodeURIComponent(s); }
  function portada(c, v) {
    var sol = 230 + (v % 4) * 30;
    return svgUrl('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice"><rect width="400" height="300" fill="' + c[0] + '"/>' +
      '<circle cx="' + sol + '" cy="70" r="28" fill="#fbf9f4" opacity=".85"/>' +
      '<polygon points="0,190 90,128 170,176 262,112 400,190 400,300 0,300" fill="' + c[1] + '"/>' +
      '<polygon points="0,232 120,170 224,216 322,156 400,208 400,300 0,300" fill="' + c[2] + '"/>' +
      '<rect y="268" width="400" height="32" fill="' + c[3] + '"/><rect x="' + (140 + v % 3 * 20) + '" y="196" width="58" height="38" fill="' + c[0] + '" opacity=".92"/>' +
      '<rect x="' + (140 + v % 3 * 20) + '" y="190" width="58" height="7" fill="' + c[3] + '"/></svg>');
  }
  function foto(n, fase) {
    var f = ['#cdbfa6', '#bfae92', '#b09c7e'][n % 3], pilares = fase === 'cim' ? 0 : 3 + (n % 3);
    var p = '';
    for (var i = 0; i < pilares; i++) p += '<rect x="' + (60 + i * 70) + '" y="' + (120 - n % 4 * 10) + '" width="16" height="' + (130 + n % 4 * 10) + '" fill="#8A8474"/>';
    return svgUrl('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><rect width="400" height="300" fill="#e7e1d2"/><rect y="236" width="400" height="64" fill="' + f + '"/>' +
      '<rect x="40" y="228" width="320" height="14" fill="#6f6a5c"/>' + p + (fase === 'cub' ? '<rect x="44" y="104" width="312" height="14" fill="#42210B"/>' : '') + '</svg>');
  }
  var PDF_TXT = '%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n' +
    '4 0 obj<</Length 66>>stream\nBT /F1 22 Tf 72 760 Td (Documento de demostracion) Tj ET\nendstream\nendobj\n' +
    '5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF';
  var PDF_URL = null;
  function pdfUrl() {   // blob: y no data: — Chrome bloquea abrir data: en una pestaña nueva
    if (!PDF_URL) { try { PDF_URL = URL.createObjectURL(new Blob([PDF_TXT], { type: 'application/pdf' })); } catch (e) { PDF_URL = 'about:blank'; } }
    return PDF_URL;
  }

  /* ───────── los datos ───────── */
  var PAL = { pr1: ['#cfd9c4', '#8F9B7A', '#485B37', '#104C4F'], pr2: ['#e6dcc6', '#BEB3A5', '#8A8474', '#42210B'], pr3: ['#d4e1de', '#8aa9a5', '#2f6b6b', '#104C4F'], pr4: ['#e3e0d4', '#a9b3a0', '#6b7a5c', '#2E3437'] };
  var IMG = {};   // ruta → imagen
  function img(ruta, url) { IMG[ruta] = url; return ruta; }

  function datos() {
    var proyectos = [
      { id: 'pr1', nombre: 'Palm Field W5', resort: 'Balian Hills, Bali', entrega: '2027-08-15', mapa: 'https://www.google.com/maps/search/?api=1&query=Balian+Hills+Bali', portada: img('portada/pr1', portada(PAL.pr1, 1)) },
      { id: 'pr2', nombre: 'Sumba Hills', resort: 'Waikabubak, Sumba', entrega: '2028-03-01', mapa: 'https://www.google.com/maps/search/?api=1&query=Waikabubak+Sumba', portada: img('portada/pr2', portada(PAL.pr2, 2)) },
      { id: 'pr3', nombre: 'Bonian Village', resort: 'Tabanan, Bali', entrega: '2027-12-01', mapa: null, portada: img('portada/pr3', portada(PAL.pr3, 3)) },
      { id: 'pr4', nombre: 'Riverfront II', resort: 'Ubud, Bali', entrega: '2027-05-20', mapa: 'https://www.google.com/maps/search/?api=1&query=Ubud+Bali', portada: null }
    ];
    var NOMBRE = { pr1: 'Palm Field W5', pr2: 'Sumba Hills', pr3: 'Bonian Village', pr4: 'Riverfront II' };
    function doc(id, pid, titulo, cat, extra) { return Object.assign({ id: id, proyecto_id: pid, proyecto: NOMBRE[pid], titulo: titulo, categoria: cat }, extra); }
    var documentos = [
      doc('d1', 'pr1', 'Dossier del proyecto', 'comercial', { path: 'pr1/dossier.pdf', descripcion: 'Memoria, calidades y modelos de villa' }),
      doc('d2', 'pr1', 'Planos de planta P-07', 'planos', { path: 'pr1/planta.pdf', descripcion: 'Planta baja y alta' }),
      doc('d3', 'pr1', 'Plano de cotas', 'planos', { path: 'pr1/cotas.pdf' }),
      doc('d4', 'pr1', 'Memoria técnica', 'tecnico', { path: 'pr1/memoria.pdf', descripcion: 'Estructura, cimentación e instalaciones' }),
      doc('d5', 'pr1', 'Informe geotécnico', 'tecnico', { path: 'pr1/geotecnico.pdf' }),
      doc('d6', 'pr1', 'Estatutos de la comunidad', 'legal', { path: 'pr1/estatutos.pdf' }),
      doc('d7', 'pr1', 'Contrato marco', 'legal', { path: 'pr1/marco.pdf' }),
      doc('d8', 'pr1', 'Tour virtual', 'comercial', { url: 'https://example.com/tour-palm-field' }),
      doc('d9', 'pr1', 'Lista de precios de extras', 'precios', { url: 'https://example.com/precios-palm-field' }),
      doc('d10', 'pr1', 'Fotos de la parcela', 'fotos', { path: 'pr1/fotos.pdf' }),
      doc('d11', 'pr2', 'Dossier de Sumba Hills', 'comercial', { path: 'pr2/dossier.pdf' }),
      doc('d12', 'pr2', 'Masterplan', 'planos', { path: 'pr2/masterplan.pdf', descripcion: 'Zonificación y accesos' }),
      doc('d13', 'pr2', 'Modelo de contrato', 'legal', { url: 'https://example.com/modelo-contrato' }),
      doc('d14', 'pr2', 'Memoria de calidades', 'tecnico', { path: 'pr2/calidades.pdf' }),
      doc('d15', 'pr3', 'Dossier de Bonian Village', 'comercial', { path: 'pr3/dossier.pdf' }),
      doc('d16', 'pr3', 'Planos de la parcela', 'planos', { path: 'pr3/planos.pdf' }),
      doc('d17', 'pr4', 'Dossier de Riverfront II', 'comercial', { path: 'pr4/dossier.pdf' })
    ];
    function h(es, en, timing, monto) { return { es: es, en: en, timing: timing, monto: monto }; }
    function c(id, numero, tipo, pid, parcela, precio, cobrado, firmado, hitos) {
      return { id: id, numero: numero, tipo: tipo, proyecto_id: pid, proyecto: NOMBRE[pid], parcela: parcela, precio: precio, cobrado: cobrado, moneda: 'USD',
        firmado: firmado, fecha_firma: firmado ? dia(-140) : null, pdf: firmado ? 'contratos/' + numero + '.pdf' : null, hitos: hitos };
    }
    var contratos = [
      c('k1', 'P-07-BP', 'reserva_parcela', 'pr1', 'P-07', 38000, 38000, true, [h('Reserva', 'Reservation', 'A la firma', 19000), h('Escritura', 'Deed', '+90 días', 19000)]),
      c('k2', 'P-07-CO', 'construccion', 'pr1', 'P-07', 126500, 25300, true, [h('Anticipo 20 %', 'Advance 20 %', 'A la firma', 25300), h('Cimentación', 'Foundation', 'Mes 3', 37950), h('Estructura', 'Structure', 'Mes 6', 37950), h('Entrega', 'Handover', 'Mes 12', 25300)]),
      c('k3', 'SH-03-BP', 'reserva_parcela', 'pr2', 'SH-03', 52000, 52000, true, [h('Reserva', 'Reservation', 'A la firma', 52000)]),
      c('k4', 'SH-03-CO', 'construccion', 'pr2', 'SH-03', 98000, 0, false, [h('Anticipo 20 %', 'Advance 20 %', 'A la firma', 19600), h('Cimentación', 'Foundation', 'Mes 3', 29400), h('Estructura', 'Structure', 'Mes 6', 29400), h('Entrega', 'Handover', 'Mes 12', 19600)]),
      c('k5', 'BV-01-BP', 'reserva_parcela', 'pr3', 'BV-01', 30000, 3000, true, [h('Reserva', 'Reservation', 'A la firma', 3000), h('Escritura', 'Deed', '+60 días', 27000)]),
      c('k6', 'RF-02-BP', 'reserva_parcela', 'pr4', 'RF-02', 24000, 24000, true, [h('Reserva', 'Reservation', 'A la firma', 24000)]),
      // La Carta de Reserva de P-07, ya recogida en su Bloqueo y su Construcción: el caso «sustituida» de Contratos
      c('k7', 'P-07-CR', 'carta_reserva', 'pr1', 'P-07', 164500, 0, true, [h('Reserva', 'Reservation', 'A la firma', 5000)])
    ];
    var emisor = { label: 'Lawang Demo', razon: 'PT Demo Estate', domicilio: 'Jl. Demostración 1, Bali', npwp: '00.000.000.0-000.000' };
    function fac(id, numero, tipo, proy, fecha, total, contrato, concepto, extra) {
      return Object.assign({ id: id, numero: numero, tipo: tipo, proyecto: proy, fecha: fecha, total: total, moneda: 'USD', contrato_numero: contrato, emisor: emisor, lineas: [{ descripcion: concepto, importe: total }],
        fields: { sociedad: 'demo', tipo: tipo, moneda: 'USD', cliente_nombre: 'Marta Keller', cliente_email: EMAIL, fecha_emision: fecha, fecha_vencimiento: dia(6), proyecto_nombre: proy,
          contrato_numero: contrato, lineas: [{ descripcion: concepto, importe: total }] } }, extra);
    }
    var facturas = [
      fac('f1', 'LW-0142', 'factura', 'Palm Field W5', dia(-3), 37950, 'P-07-CO', 'Cimentación — Mes 3'),
      fac('f2', 'REC-2026-0057', 'recibi', 'Palm Field W5', dia(-70), 25300, 'P-07-CO', 'Pago recibido · Anticipo 20 %'),
      fac('f3', 'LW-0131', 'factura', 'Palm Field W5', dia(-75), 25300, 'P-07-CO', 'Anticipo 20 % — A la firma'),
      fac('f4', 'REC-2026-0031', 'recibi', 'Sumba Hills', dia(-125), 52000, 'SH-03-BP', 'Pago recibido · Reserva'),
      fac('f5', 'LW-0118', 'factura', 'Bonian Village', dia(-30), 3000, 'BV-01-BP', 'Reserva — A la firma'),
      fac('f6', 'PRO-2026-0007', 'proforma', 'Sumba Hills', dia(-2), 19600, 'SH-03-CO', 'Anticipo 20 % — A la firma')
    ];
    var fotosP07 = [[0, 'Estructura norte', -4], [1, 'Armado de pilares', -11], [2, 'Encofrado de losa', -18], [3, 'Cimentación terminada', -39], [4, 'Excavación', -62], [5, 'Replanteo de la parcela', -80]]
      .map(function (a) { return { path: img('obra/p07/' + a[0], foto(a[0], a[0] < 4 ? 'est' : 'cim')), titulo: a[1], fecha: dia(a[2]) }; });
    var fotosSH = [[6, 'Limpieza del terreno', -9], [7, 'Replanteo', -21]].map(function (a) { return { path: img('obra/sh03/' + a[0], foto(a[0], 'cim')), titulo: a[1], fecha: dia(a[2]) }; });
    return {
      client_id: 'demo-cliente', nombre: 'Marta Keller', email: EMAIL, telefono: '+41 79 000 00 00', pais: 'Suiza',
      prefs: { pref_email: true, pref_sms: false, notif_visto_hasta: iso(-40) },
      proyectos: proyectos, contratos: contratos, documentos: documentos, facturas: facturas,
      firma_pendiente: [{ contrato_id: 'k4', enlace: '/portal/?demo=1&t=demo', enviado_en: iso(-3), expira_en: iso(11) }],
      fases: [{ orden: 1, clave: 'cim', es: 'Cimentación', en: 'Foundation' }, { orden: 2, clave: 'est', es: 'Estructura', en: 'Structure' }, { orden: 3, clave: 'cub', es: 'Cubierta', en: 'Roof' },
              { orden: 4, clave: 'ins', es: 'Instalaciones', en: 'Utilities' }, { orden: 5, clave: 'ent', es: 'Acabados', en: 'Finishes' }],
      obra: [
        { unidad: 'P-07', proyecto: 'Palm Field W5', contrato_numero: 'P-07-CO', fase: 'est', fecha_entrega: '2027-08-15', actualizado: dia(-4), fotos: fotosP07 },
        { unidad: 'SH-03', proyecto: 'Sumba Hills', contrato_numero: 'SH-03-BP', fase: 'cim', fecha_entrega: '2028-03-01', actualizado: dia(-9), fotos: fotosSH }
      ],
      kyc: [{ tipo: 'passport', subido: iso(-200), caduca: dia(13), path: 'kyc/pasaporte' }, { tipo: 'id', subido: iso(-200), caduca: dia(420), path: 'kyc/dni' }],
      tickets: [
        { id: 't1', categoria: 'Pagos', estado: 'abierto', factura_id: 'f1', contrato_id: null, ref_numero: 'LW-0142', actualizado_en: iso(-1),
          mensajes: [{ id: 'm1', de: 'cliente', autor: null, texto: '¿Puedo pagar el hito de cimentación en dos transferencias?', creado_en: iso(-1.1) },
                     { id: 'm2', de: 'equipo', autor: 'Equipo Lawang', texto: 'Sí, sin problema. Haz la primera esta semana y la segunda antes del vencimiento; te confirmamos al recibir cada una.', creado_en: iso(-1) }] },
        { id: 't2', categoria: 'Documentación', estado: 'resuelto', factura_id: null, contrato_id: null, ref_numero: null, actualizado_en: iso(-30),
          mensajes: [{ id: 'm3', de: 'cliente', autor: null, texto: '¿Dónde descargo los planos de mi villa?', creado_en: iso(-31) },
                     { id: 'm4', de: 'equipo', autor: 'Equipo Lawang', texto: 'Los tienes en Documentos, carpeta Palm Field W5, tipo Planos.', creado_en: iso(-30) }] }
      ]
    };
  }
  var D = datos();
  var SOC = [{ clave: 'demo', label: 'Lawang Demo', razon: 'PT Demo Estate', marca: 'Lawang', domicilio: 'Jl. Demostración 1, Bali', npwp: '00.000.000.0-000.000', rep: 'Representante de demostración', logo: null, folio: 'DEMO',
    tinta: { primary: '#485B37', deep: '#104C4F' }, es_indonesia: true }];

  /* ───────── el cliente falso ───────── */
  function ok(data) { return Promise.resolve({ data: data, error: null }); }
  function thenable(data) {      // soporta .order() y .select() encadenados, como el cliente real
    var b = { order: function () { return b; }, select: function () { return b; }, then: function (a, c) { return ok(data).then(a, c); }, catch: function (f) { return ok(data).catch(f); } };
    return b;
  }
  var oyentes = [];
  function sesion() { try { return window.sessionStorage.getItem(CLAVE) === '1'; } catch (e) { return false; } }
  function marca(v) { try { if (v) window.sessionStorage.setItem(CLAVE, '1'); else window.sessionStorage.removeItem(CLAVE); } catch (e) {} }
  function sesionObj() { return { access_token: 'demo', user: { id: 'demo', email: EMAIL, app_metadata: { portal: true } } }; }
  function copia(x) { return JSON.parse(JSON.stringify(x)); }
  function refDe(a) {
    var f = a.p_factura_id && D.facturas.filter(function (x) { return x.id === a.p_factura_id; })[0];
    var k = a.p_contrato_id && D.contratos.filter(function (x) { return x.id === a.p_contrato_id; })[0];
    return { factura_id: f ? f.id : null, contrato_id: k ? k.id : null, ref_numero: f ? f.numero : (k ? k.numero : null) };
  }
  var sb = {
    auth: {
      getSession: function () { return ok({ session: sesion() ? sesionObj() : null }); },
      onAuthStateChange: function (fn) { oyentes.push(fn); return { data: { subscription: { unsubscribe: function () {} } } }; },
      signInWithPassword: function (c) {
        if (c && String(c.email || '').toLowerCase() === EMAIL && c.password === PASS) {
          marca(true); var s = sesionObj(); oyentes.forEach(function (fn) { try { fn('SIGNED_IN', s); } catch (e) { console.error('demo', e); } });
          return ok({ session: s });
        }
        return Promise.resolve({ data: null, error: { message: 'Invalid login credentials' } });
      },
      signOut: function () { marca(false); return Promise.resolve({ error: null }); },
      updateUser: function () { return ok({ user: {} }); }
    },
    rpc: function (n, a) {
      a = a || {};
      if (n === 'portal_situacion') return thenable(copia(D));
      if (n === 'sociedades_visibles') return thenable(SOC);
      if (n === 'cuentas_cobro_visibles') return thenable([]);
      if (n === 'portal_marcar_notificaciones_leidas') { D.prefs.notif_visto_hasta = new Date().toISOString(); return ok(null); }
      if (n === 'portal_set_prefs') { D.prefs.pref_email = !!a.p_pref_email; D.prefs.pref_sms = !!a.p_pref_sms; return ok(null); }
      if (n === 'portal_abrir_ticket') {
        var r = refDe(a), id = 't' + (D.tickets.length + 1) + '-' + Date.now();
        D.tickets.unshift(Object.assign({ id: id, categoria: a.p_categoria, estado: 'abierto', actualizado_en: new Date().toISOString(),
          mensajes: [{ id: 'm' + Date.now(), de: 'cliente', autor: null, texto: a.p_texto, creado_en: new Date().toISOString() }] }, r));
        return ok(id);
      }
      if (n === 'portal_enviar_mensaje') {
        var t = D.tickets.filter(function (x) { return x.id === a.p_hilo_id; })[0];
        if (t) { t.mensajes.push({ id: 'm' + Date.now(), de: 'cliente', autor: null, texto: a.p_texto, creado_en: new Date().toISOString() }); t.actualizado_en = new Date().toISOString(); }
        return ok(null);
      }
      return ok(null);
    },
    storage: { from: function (bk) {
      function url(p) {
        if (IMG[p]) return IMG[p];                                       // portadas y fotos de obra: dibujadas
        return pdfUrl();                                                   // el resto: un PDF de muestra
      }
      return {
        createSignedUrl: function (p) { return ok({ signedUrl: url(p) }); },
        createSignedUrls: function (ps) { return ok((ps || []).map(function (p) { return { path: p, signedUrl: url(p), error: null }; })); }
      };
    } }
  };
  if (window.supabase) window.supabase.createClient = function () { return sb; };
  else window.supabase = { createClient: function () { return sb; } };

  /* ───────── red: lista de DESTINOS PERMITIDOS; lo demás no sale (revisión previa de Seguridad, 7-oct-2026) ─────────
     Mismo origen, blob: y data:, jsDelivr (supabase-js, con su integridad) y Google Fonts. Cualquier otro destino
     —la base, el servicio de PDF, GoHighLevel— queda cortado para fetch, XHR, sendBeacon, WebSocket y EventSource.
     Las Edge Functions que el portal pide por fetch (portal-acceso, firma-get) se responden aquí con datos falsos. */
  var PERMITIDOS = /^(cdn\.jsdelivr\.net|fonts\.googleapis\.com|fonts\.gstatic\.com)$/;
  function permitido(u) {
    try {
      var x = new URL(String(u && u.url ? u.url : u), location.href);
      if (x.protocol === 'blob:' || x.protocol === 'data:') return true;
      return x.origin === location.origin || PERMITIDOS.test(x.hostname);
    } catch (e) { return false; }
  }
  var fetchReal = window.fetch ? window.fetch.bind(window) : null;
  function resp(j, st) { return new Response(JSON.stringify(j), { status: st || 200, headers: { 'content-type': 'application/json' } }); }
  window.fetch = function (u, o) {
    var url = String(u && u.url ? u.url : u);
    if (/\/functions\/v1\/portal-acceso/.test(url)) return Promise.resolve(resp({ ok: true }));
    if (/\/functions\/v1\/firma-get/.test(url)) return Promise.resolve(resp({ numero: 'SH-03-CO', html: '<body style="font-family:system-ui;padding:28px;color:#1b1c19"><h2>Borrador de contrato (demostración)</h2><p>Este documento es de muestra: aquí se vería el borrador real del contrato antes de firmarlo.</p><p><b>SH-03-CO</b> · Anexo de construcción · Sumba Hills</p></body>' }));
    if (!permitido(u)) return Promise.resolve(resp({ error: 'demo: destino no permitido' }, 403));
    return fetchReal ? fetchReal(u, o) : Promise.reject(new Error('sin fetch'));
  };
  try {
    var xhrAbre = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (m, u) { if (!permitido(u)) throw new Error('demo: destino no permitido'); return xhrAbre.apply(this, arguments); };
    if (navigator.sendBeacon) { var sb0 = navigator.sendBeacon.bind(navigator); navigator.sendBeacon = function (u, d) { return permitido(u) ? sb0(u, d) : false; }; }
    if (window.WebSocket) { var WS = window.WebSocket; window.WebSocket = function (u, p) { if (!permitido(u)) throw new Error('demo: destino no permitido'); return new WS(u, p); }; }
    if (window.EventSource) { var ES = window.EventSource; window.EventSource = function (u, c) { if (!permitido(u)) throw new Error('demo: destino no permitido'); return new ES(u, c); }; }
  } catch (e) { console.error('demo: no se pudo cerrar la red', e); /* si no se puede cerrar la red, el demo no sirve: falla cerrado */ throw e; }

  /* ───────── la cinta, y la ayuda en la pantalla de entrada ───────── */
  var css = '.lw-demo-cinta{position:fixed;right:12px;bottom:12px;z-index:2147483000;background:#1B1C19;color:#F5F0E6;border:1px solid #C89B5C;border-radius:999px;padding:6px 14px;font:600 12px/1.4 system-ui,sans-serif;letter-spacing:.04em;pointer-events:none}' +
    '.lw-demo-ayuda{background:#f6e8cc;color:#5a3b08;border-radius:12px;padding:12px 14px;margin:0 0 18px;font:13px/1.5 system-ui,sans-serif;text-align:left}' +
    '.lw-demo-ayuda b{font-weight:600}.lw-demo-ayuda code{background:rgba(0,0,0,.07);padding:1px 6px;border-radius:6px;font-family:ui-monospace,Consolas,monospace}' +
    '.lw-demo-ayuda button{margin-top:10px;font:600 13px system-ui,sans-serif;background:#104C4F;color:#fff;border:0;border-radius:999px;padding:8px 16px;cursor:pointer}';
  function arranca() {
    var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);
    var cinta = document.createElement('div'); cinta.className = 'lw-demo-cinta'; cinta.textContent = 'Demo · datos ficticios'; document.body.appendChild(cinta);
    var caja = document.querySelector('#vLogin .caja'); if (!caja) return;
    var ayuda = document.createElement('div'); ayuda.className = 'lw-demo-ayuda';
    ayuda.innerHTML = '<b>Portal de demostración con datos ficticios.</b><br>Usuario <code>' + EMAIL + '</code><br>Contraseña <code>' + PASS + '</code><br><button type="button" id="lwDemoEntrar">Entrar con el usuario de demo</button>';
    var rot = caja.querySelector('.rot');   // la ayuda va justo debajo de «Área de clientes»
    caja.insertBefore(ayuda, rot ? rot.nextSibling : caja.firstChild);
    document.getElementById('lwDemoEntrar').addEventListener('click', function () {
      var f = document.getElementById('fLoginPass'), toggle = document.getElementById('togglePass');
      if (f && f.hidden && toggle) toggle.click();
      document.getElementById('inEmailPass').value = EMAIL; document.getElementById('inPass').value = PASS;
      f.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();

  /* LA MARCA VA LA ÚLTIMA: index.html la usa para saber que el demo cargó ENTERO (cliente falso puesto y red cerrada). Si algo
     de lo de arriba lanza, no queda puesta y el portal falla cerrado en vez de crear el cliente real con `?demo`. */
  window.LW_DEMO = { email: EMAIL, password: PASS };
})();
