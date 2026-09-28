/* Puerta de acceso de las herramientas internas de Lawang — 28-jul-2026.
   Regla del estudio: ninguna herramienta se sirve sin sesión. Antes se cumplía
   a mano y tres páginas se habían quedado fuera (el maquetador de dossiers, el
   constructor de diseño y la portada), públicas para cualquiera con la URL.

   Se carga en el <head>, DESPUÉS del CDN de supabase-js y sin `defer`:
     <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
     <script src="/contracts/assets/guard.js"></script>

   ⚠️ Esto es una PUERTA, no el candado. Una página estática siempre se puede
   leer con el navegador apagando el JS: lo que de verdad protege los datos es
   la RLS de Supabase. Sirve para páginas que no traen datos propios (el dossier
   trabaja contra JSON local).

   DESDE EL 4-ago-2026 PASAN POR AQUÍ LAS NUEVE, Contratos y Facturas incluidas,
   pero esas dos SIN `data-herramienta`. El motivo: su permiso lo comprueban
   ellas y lo comprueban MEJOR —Facturas exime al modo `?vista=1`, con el que el
   visor de Operaciones embebe un documento ya emitido para consultarlo, y eso
   guard.js no lo sabe—. Lo que sí aporta la puerta aquí es lo que faltaba:
   sesión, cuenta activa y UN SOLO cliente de Supabase por página, publicado en
   `LW_SB`. Sin eso, la barra compartida (panel de usuario y campana) no tenía de
   dónde colgarse y no salía en las dos herramientas más usadas.

   Falla CERRADA a propósito: si el CDN no carga o la sesión no se puede
   comprobar, se va al login. Un fallo de red no debe abrir la herramienta.

   La página queda oculta hasta confirmar sesión — si no, la herramienta se
   pinta entera durante un instante antes de redirigir, y eso se lee y se
   fotografía.

   PERMISO POR HERRAMIENTA (29-jul-2026). Declararlo en la propia etiqueta:
     <script src="/contracts/assets/guard.js" data-herramienta="contratos"></script>
   Si el usuario tiene ficha en `public.usuarios` y esa herramienta no está en
   su lista, se le devuelve a la intranet. **Sin ficha ya NO se permite**
   (8-sep-2026): esa compatibilidad con las cuentas anteriores al panel dejaba
   entrar a cualquier sesión que no fuera del equipo — ver la nota junto al
   `if (!ficha)`. Las funciones SQL conservan la suya; ésta era la puerta.
   ⚠️ Esto decide lo que se VE. Lo que de verdad impide escribir es la RLS
   (`puede('herramienta')` en las policies) — esto solo evita enseñar una
   herramienta que luego fallaría al guardar.

   VARIAS HERRAMIENTAS, con coma (7-ago-2026): `data-herramienta="dossier,creatividades"`
   deja pasar con CUALQUIERA de las dos. Lo usa el visor de /intranet/creatividades/,
   que enlaza a Dossier y a Creatividades de redes sin ser ninguna de las
   dos — bloquearlo a una sola dejaría fuera a quien solo tiene la otra.
   Con un solo valor se comporta exactamente igual que antes. */
(function () {
  /* Base de la instancia (ERP F3, 25-sep-2026): ÚNICA fuente del host y la clave publicable. El resto de la suite
     (editores.js, datos.js, asistente…) las lee de window.LW_SB_URL / LW_SB_KEY en vez de escribirlas otra vez:
     cinco copias a mano eran cinco sitios que una instancia nueva del ERP tenía que acordarse de cambiar. Van
     ANTES del modo QA para que existan también con el doble local. */
  var FICHA = window.LW_INSTANCIA;
  if (!FICHA || !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(FICHA.sb_url || '')) {
    // sin ficha no hay base: se para aquí (la página no carga nada, igual que si faltara guard.js)
    throw new Error('[guard] falta /contracts/assets/instancia.js antes de guard.js');
  }
  var URL_SB = FICHA.sb_url;
  var KEY_SB = FICHA.sb_key;   // publicable: el candado es la RLS
  /* Solo lectura, y las edges se piden SOLO con window.lwEdge(nombre) (consulta de deploy 21c54a71, Seguridad): si
     guard.js no llegara (404, CDN viejo), llamar a lwEdge lanza ANTES de construir la petición, así que el token de
     la sesión nunca sale hacia una ruta relativa de la propia web; y un elemento con id="lwEdge"/"LW_SB_URL" inyectado
     en el HTML no se puede llamar ni pisa estas propiedades. try: si la página cargara guard.js dos veces, la segunda
     no revienta (la primera ya fijó los mismos valores). */
  function fija(k, v) { try { Object.defineProperty(window, k, { value: v, writable: false, configurable: false, enumerable: true }); } catch (e) {} }
  /* ¿Pantalla vieja? (LAW-386, 27-sep-2026): un 401/403/404 de Supabase puede ser un permiso que falta
     o una pestaña con el código de antes de un despliegue. No se decide aquí: se avisa a version.js, que
     compara la huella de la página con la del servidor. Un evento y no una llamada: guard.js no depende
     de que version.js haya cargado. */
  function sospechaVersion(st) {
    if (st !== 401 && st !== 403 && st !== 404) return;
    try { window.dispatchEvent(new CustomEvent('lw:version-vieja', { detail: { status: st } })); }
    catch (e) { /* MUDO A PROPOSITO: sin CustomEvent (navegador viejo) solo se pierde el aviso de versión; la petición sigue su curso */ }
  }
  fija('LW_SB_URL', URL_SB);
  fija('LW_SB_KEY', KEY_SB);
  fija('lwEdge', function (nombre) {
    if (!/^[a-z0-9-]+$/.test(String(nombre))) throw new Error('lwEdge: nombre de edge no válido');
    return URL_SB + '/functions/v1/' + nombre;
  });
  /* Lecturas por el servidor: window.lwDatos(nombre, args) (B10a, 28-sep-2026, revisión previa #136 Desarrollo 2;
     encargos/20260927_erp_b10_lecturas_a_la_par.md). ÚNICO punto por el que una pantalla pide una RPC `*_datos`:
     hoy va por PostgREST (`sb.rpc`), y en B10b la ficha (instancia.js) podrá mandarla por otro transporte (la puerta
     del maestro) cambiando SOLO esta función. Por eso:
       · solo nombres que acaben en `_datos` — un nombre que no, lanza ANTES de construir la petición, como lwEdge;
       · devuelve `{data, error}` tal cual, nunca filtros PostgREST encadenados (la puerta no los sabría reproducir);
       · el cliente es el único de la página (window.LW_SB); si aún no existe, espera a que la puerta lo cree. */
  fija('lwDatos', function (nombre, args) {
    if (!/^[a-z][a-z0-9_]*_datos$/.test(String(nombre))) throw new Error('lwDatos: solo RPC *_datos (' + nombre + ')');
    var cli = window.LW_SB ? Promise.resolve(window.LW_SB)
      : window.LW_AUTH ? window.LW_AUTH.then(function (a) { return a.sb; })
      : Promise.reject(new Error('lwDatos: sin cliente de Supabase en esta página'));
    return cli.then(function (sb) { return sb.rpc(nombre, args || {}); })
      .then(function (r) { return { data: r.data, error: r.error }; },
            function (e) { return { data: null, error: e }; });
  });
  /* Ficheros de contratos y cobros por la edge ficheros-contrato (26-sep-2026, LAW-336 pieza 5): la ruta
     la decide el servidor y la subida va por URL firmada; borrar borradores de firma, también el servidor.
     Una sola copia para toda la suite (facturas, operaciones, v4). Devuelve la respuesta o lanza con el error. */
  fija('lwFicheros', function (sb, accion, datos) {
    return sb.auth.getSession().then(function (s) {
      var t = s && s.data && s.data.session && s.data.session.access_token;
      return fetch(URL_SB + '/functions/v1/ficheros-contrato', { method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer ' + (t || '') },
        body: JSON.stringify(Object.assign({ accion: accion }, datos || {})) });
    }).then(function (r) {
      sospechaVersion(r.status);
      return r.json().catch(function () { return { ok: false, error: 'Respuesta inválida del servidor' }; });
    }).then(function (d) {
      if (!d.ok) throw new Error(d.error || 'error del servidor');
      return d;
    });
  });
  /* Documentos KYC de compradores por la edge ficheros-kyc (27-sep-2026, LAW-336 bloque 2): la ruta la
     decide el servidor, la subida va por URL firmada y al registrar el servidor mira los primeros bytes;
     retirar y borrar ficheros, también el servidor. Una sola copia para la clásica y la v4. Lanza un Error
     con el texto para la persona (y `.code` = el de Postgres, si lo hubo). */
  var KYC_ERR = {
    comprador_no_visible: 'No encuentro ese comprador entre los tuyos',
    tipo_de_fichero_no_admitido: 'Ese tipo de fichero no se admite: sube un PDF o una foto (JPG, PNG, WEBP, HEIC)',
    el_fichero_no_ha_llegado: 'El fichero no ha llegado al archivo: vuelve a subirlo',
    el_fichero_no_es_lo_que_dice_ser: 'El fichero no es lo que dice ser (su contenido no cuadra con la extensión): no se ha guardado',
    solo_super_admin: 'Esto solo lo hace un super admin',
    ruta_invalida: 'La subida no es válida: vuelve a elegir el fichero',
    fecha_de_caducidad_invalida: 'La fecha de caducidad no es válida',
    documento_invalido: 'Ese documento no es válido: recarga la ficha', comprador_invalido: 'Ese comprador no es válido: recarga la ficha',
    no_se_pudo_preparar_la_subida: 'No se pudo preparar la subida: prueba otra vez en un momento',
    fichero_no_borrado: 'El fichero no se pudo quitar del archivo', error_interno: 'Error del servidor: prueba otra vez en un momento',
    accion_desconocida: 'Petición no válida: recarga la página', metodo: 'Petición no válida: recarga la página',
    solo_equipo: 'Tu usuario no es del equipo',
    sin_sesion: 'Tu sesión ha caducado: vuelve a entrar', sesion_invalida: 'Tu sesión ha caducado: vuelve a entrar'
  };
  fija('lwKyc', function (sb, accion, datos) {
    return sb.auth.getSession().then(function (s) {
      var t = s && s.data && s.data.session && s.data.session.access_token;
      return fetch(URL_SB + '/functions/v1/ficheros-kyc', { method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer ' + (t || '') },
        body: JSON.stringify(Object.assign({ accion: accion }, datos || {})) });
    }).then(function (r) {
      sospechaVersion(r.status);
      return r.json().catch(function () { return { ok: false, error: 'Respuesta inválida del servidor' }; });
    }).then(function (d) {
      if (!d.ok) { var e = new Error(KYC_ERR[d.error] || d.error || 'error del servidor'); e.code = d.code; throw e; }
      return d;
    });
  });
  // Subir un documento: pedir la ruta → subir con el content-type que dice el servidor → registrarlo.
  fija('lwKycSube', function (sb, clientId, f, tipoDoc, caduca) {
    var ext = (String(f.name).match(/\.[a-z0-9]+$/i) || [''])[0].toLowerCase();
    return window.lwKyc(sb, 'subida_url', { client_id: clientId, ext: ext }).then(function (u) {
      /* Con un File, supabase-js manda el tipo QUE TRAE EL FICHERO e ignora `contentType` (storage-js,
         uploadToSignedUrl): un HEIC llega sin tipo y el bucket lo rechazaría. Se sube una copia con el
         tipo que ha decidido el servidor por la extensión. */
      var conTipo = new File([f], f.name, { type: u.content_type });
      return sb.storage.from('kyc').uploadToSignedUrl(u.path, u.token, conTipo, { contentType: u.content_type }).then(function (up) {
        if (up.error) throw up.error;
        return window.lwKyc(sb, 'registra', { client_id: clientId, path: u.path, doc_type: tipoDoc, caduca_el: caduca || null });
      });
    });
  });
  /* Ficheros por CLASE por la edge `ficheros` (27-sep-2026, LAW-336 bloque 3): documentos de modelo (bucket
     `modelos`) y fotos del Investor Deck (bucket público `deck`); en el bloque 4 se suman documentación, obra,
     creatividades y gastos como clases nuevas, con el mismo helper. La ruta la decide el servidor, el permiso
     se comprueba antes de firmar la subida y al registrar se leen los primeros bytes. Lanza un Error con el
     texto para la persona (y `.code` = el de Postgres, si lo hubo). */
  var FICH_ERR = Object.assign({}, KYC_ERR, {
    clase_desconocida: 'Petición no válida: recarga la página', id_invalido: 'Ese fichero no es válido: recarga la página',
    tipo_de_fichero_no_admitido: 'Ese tipo de fichero no se admite aquí',
    modelo_invalido: 'Ese modelo no es válido: recarga la página', modelo_no_visible: 'No encuentro ese modelo: recarga la página',
    tipo_de_documento_invalido: 'Tipo de documento no válido',
    plano_solo_admin: 'El plano solo lo sube administración',
    en_contrato_solo_admin: 'Solo administración decide qué va en el contrato: súbelo sin marcar',
    dosier_no_va_en_el_contrato: 'El dosier es comercial: no va en el contrato',
    destino_invalido: 'Destino de la foto no válido: recarga la página', destino_no_visible: 'No encuentro ese proyecto o modelo: recarga la página',
    solo_admin: 'Esto solo lo hace un administrador',
    fila_no_borrada: 'El fichero se ha quitado, pero su ficha no: vuelve a pulsar «Borrar»',
    fichero_no_borrado: 'El fichero no se pudo quitar del archivo: no se ha borrado nada, prueba otra vez',
    // bloque 4 (27-sep-2026): documentación, obra, justificantes de gasto y creatividades
    proyecto_invalido: 'Ese proyecto no es válido: recarga la página',
    proyecto_no_permitido: 'No puedes subir documentación a ese proyecto (no es de los tuyos o te falta la herramienta «Documentación»)',
    unidad_invalida: 'Esa parcela no es válida: recarga la página',
    obra_no_permitida: 'No puedes subir fotos de obra a esa parcela (no es de tus proyectos o te falta la herramienta «Obra»)',
    gasto_invalido: 'Ese gasto no es válido: recarga la página', gasto_no_visible: 'No encuentro ese gasto: recarga la página',
    gasto_anulado: 'Ese gasto está anulado: no admite justificantes',
    creatividad_invalida: 'Esa creatividad no es válida: recarga la página',
    tipo_de_creatividad_invalido: 'Tipo de creatividad no válido: recarga la página',
    sin_permiso_creatividades: 'No tienes permiso para hacer creatividades (te falta la herramienta «Creatividades»): pídeselo a administración',
    sin_permiso_dossier: 'No tienes permiso para hacer dossiers (te falta la herramienta «Dossier»): pídeselo a administración',
    creatividad_no_borrador: 'Esta creatividad ya no es un borrador: guárdala como copia para seguir cambiándola',
    rol_invalido: 'Ese fichero no va en este tipo de creatividad', falta_el_estado: 'Falta el contenido de la creatividad: vuelve a guardar',
    estado_no_valido: 'El contenido de la creatividad no se ha podido leer: no se ha guardado, prueba otra vez',
    // LAW-78 (27-sep-2026): páginas de anexos de contrato
    contrato_invalido: 'Ese contrato no es válido: recarga la página',
    contrato_no_guardado: 'No encuentro ese contrato: guárdalo primero (o no es de los tuyos)',
    contrato_bloqueado: 'Este contrato está enviado a firma o bloqueado: no admite anexos nuevos',
    sin_permiso_contrato: 'No tienes permiso para añadir anexos a este contrato',
    anexo_invalido: 'Ese anexo no es válido: recarga la página', pagina_invalida: 'Página de anexo no válida: recarga la página',
    pagina_demasiado_grande: 'Una página del anexo pesa más de 3 MB: súbelo con menos resolución',
    // AXW-66 (28-sep-2026): fotos del deck en bucket público solo si el deck está abierto
    foto_ids_invalidos: 'Petición de fotos no válida: recarga la página',
    no_se_pudieron_firmar: 'El servidor no ha podido dar las direcciones de las fotos: prueba otra vez',
    peticion_invalida: 'Petición no válida: recarga la página',
    cambio_en_curso: 'Ya hay un cambio en curso en el deck de este proyecto: espera un minuto y vuelve a mirar',
    fotos_sin_mover: 'No se han podido pasar las fotos al público: el deck sigue cerrado. Prueba otra vez',
    deck_a_medias: 'El cambio del deck ha quedado A MEDIAS (alguna foto no está donde toca). Vuelve a pulsar el botón: repetirlo es seguro',
    el_deck_cambio_durante_la_subida: 'El deck de este proyecto se ha abierto o cerrado mientras subías: vuelve a subir la foto',
    sincroniza_apagada_hasta_s4: 'El barrido de fotos del deck todavía no está encendido'
  });
  fija('lwFichero', function (sb, clase, accion, datos) {
    return sb.auth.getSession().then(function (s) {
      var t = s && s.data && s.data.session && s.data.session.access_token;
      return fetch(URL_SB + '/functions/v1/ficheros', { method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer ' + (t || '') },
        body: JSON.stringify(Object.assign({}, datos || {}, { accion: accion, clase: clase })) });
    }).then(function (r) {
      sospechaVersion(r.status);
      return r.json().catch(function () { return { ok: false, error: 'Respuesta inválida del servidor' }; });
    }).then(function (d) {
      // `.clave` = el código crudo del servidor: la pantalla decide por él, nunca por el texto traducido
      if (!d.ok) { var e = new Error(FICH_ERR[d.error] || d.error || 'error del servidor'); e.code = d.code; e.clave = d.error; e.aplicado = d.aplicado; throw e; }
      return d;
    });
  });
  /* URL de cada foto del deck, por id (AXW-66, 28-sep-2026; revisión previa #139, DES1/DES2/SEG3). Desde AXW-66 las
     fotos de proyectos SIN deck abierto viven en el bucket privado `deck-privado`: su URL es firmada (1 h) y la da el
     servidor (edge `ficheros`, acción `urls`), que saca la ruta de `deck_fotos` y el bucket de `storage.objects` —
     aquí solo viajan ids. La URL firmada NO se guarda nunca (ni en un estado, ni en localStorage): se pide al pintar.
     `fotos`: ids, o filas {id, ambito, path}. Una fila de MODELO sigue siendo pública (bucket `deck`) y se resuelve
     aquí mismo, sin ir al servidor. Lotes de 200 (el tope de la edge) en paralelo.
     Resuelve {urls: {id: url|null}, caduca_seg}; `null` = la fila existe pero su fichero no. Si el servidor falla,
     RECHAZA con `.clave = 'urls_fallan'`: la pantalla tiene que decir «no he podido pedirlas», que no es lo mismo
     que «no hay fotos». */
  fija('lwFotoUrls', function (sb, fotos) {
    var urls = {}, pedir = [];
    (fotos || []).forEach(function (f) {
      var id = typeof f === 'string' ? f : f && f.id;
      if (!id || Object.prototype.hasOwnProperty.call(urls, id)) return;
      if (f && f.ambito === 'modelo' && f.path) { urls[id] = sb.storage.from('deck').getPublicUrl(f.path).data.publicUrl; return; }
      urls[id] = null;
      pedir.push(id);
    });
    var lotes = [];
    for (var i = 0; i < pedir.length; i += 200) lotes.push(pedir.slice(i, i + 200));
    return Promise.all(lotes.map(function (l) {
      return window.lwFichero(sb, 'deck_foto', 'urls', { foto_ids: l });
    })).then(function (rs) {
      var caduca = 3600;
      rs.forEach(function (r) {
        Object.keys(r.urls || {}).forEach(function (k) { urls[k] = r.urls[k] || null; });
        if (r.caduca_seg) caduca = Math.min(caduca, Number(r.caduca_seg) || caduca);
      });
      return { urls: urls, caduca_seg: caduca };
    }, function (e) {
      var err = new Error('No se han podido pedir las direcciones de las fotos: ' + ((e && e.message) || e));
      err.clave = 'urls_fallan'; err.causa = e && e.clave;
      throw err;
    });
  });
  /* Subir un fichero de una clase: pedir la ruta → subir con el content-type que dice el servidor → registrarlo.
     `f` es un File o un Blob (las fotos del deck llegan ya recodificadas a WebP: se pasa `nombre` aparte). */
  fija('lwFicheroSube', function (sb, clase, f, datos) {
    var nombre = (datos && datos.nombre) || f.name || '';
    var ext = (datos && datos.ext) || (String(nombre).match(/\.[a-z0-9]+$/i) || [''])[0].toLowerCase();
    var base = Object.assign({}, datos || {}); delete base.ext;
    return window.lwFichero(sb, clase, 'subida_url', Object.assign({}, base, { ext: ext })).then(function (u) {
      // Con un File, supabase-js manda el tipo QUE TRAE EL FICHERO e ignora `contentType` (ver lwKycSube)
      var conTipo = new File([f], nombre || ('fichero' + ext), { type: u.content_type });
      return sb.storage.from(u.bucket).uploadToSignedUrl(u.path, u.token, conTipo, { contentType: u.content_type }).then(function (up) {
        if (up.error) throw up.error;
        return window.lwFichero(sb, clase, 'registra', Object.assign({}, base, { path: u.path, nombre: nombre }));
      });
    });
  });
  /* MODO QA (28-ago-2026) — revisión previa: Desarrollo + Datos + Seguridad,
     CEO/revisiones/estado.json. Único punto de entrada para las herramientas
     que cargan guard.js: nunca se copia este `if` en cada index.html (los
     tres departamentos lo pidieron independientemente — "una lista a mano en
     dos sitios ES el bug", ya escrito en contexto/suite_lawang.md).
     Solo se alcanza con localhost + ?qa=1; fuera de eso, código muerto. El
     doble (_qa_double_guard.js) está gitignored y nunca llega a Hostinger,
     así que fuera de localhost esto ni siquiera puede cargar. Detalle y
     límites conocidos: cabecera de _qa_double_guard.js. */
  try {
    if (location.hostname === 'localhost' &&
        new URLSearchParams(location.search).get('qa') === '1') {
      document.write('<script src="/_qa_double_guard.js"><\/script>');
      return;
    }
  } catch (e) { /* si algo falla aquí, se sigue por el camino real de abajo */ }

  /* 1-sep-2026: /intranet/ tiene login propio (antes /entrar/, puerta
     compartida con el portal del cliente, retirada como punto de entrada
     — sigue viva por si algo externo aún apunta ahí, pero nada del estudio
     enlaza a ella desde hoy). */
  var LOGIN  = '/intranet/';
  var HUB    = '/intranet/';

  var propia = document.currentScript;
  var HERRAMIENTA = propia && propia.getAttribute('data-herramienta');
  var HERRAMIENTAS_REQ = HERRAMIENTA ? HERRAMIENTA.split(',') : null;
  /* `data-rol` (23-sep-2026, LAW-275, decisión del owner): las pantallas del
     Panel de control de la v4 no son una herramienta asignable sino de
     dirección — Ajustes, Condiciones, Equipos de venta, Cuentas, Usuarios
     (`admin`) y Comisión de administración, Sociedades (`super_admin`). Hasta
     hoy el menú las escondía por rol pero la puerta dejaba pasar a cualquier
     ficha activa que tecleara la URL (los datos ya los protegía la RLS; la
     cáscara no). Se SUMA a `data-herramienta`, no la sustituye: con las dos,
     hacen falta las dos. Sin ficha legible no se entra (al revés que la regla
     general de abajo): una puerta de dirección no se abre por no poder mirar. */
  var ROL_REQ = propia && propia.getAttribute('data-rol');
  /* `data-rol` admite una LISTA separada por espacios (23-sep-2026, owner:
     «los sales manager deben tener acceso a dar de alta su equipo de ventas
     + condiciones a ellos»): `data-rol="admin sales_manager"`. El super_admin
     entra siempre; `admin` incluye al super_admin como hasta hoy; cualquier otro
     rol listado entra solo si es el suyo. Un `data-rol` sin ningún rol conocido
     se trata como `admin` (lo de siempre): nunca se abre por un typo. */
  var ROLES_REQ = (ROL_REQ || '').split(/\s+/).filter(function (x) { return x; });
  function rolBasta(ficha) {
    if (!ROL_REQ) return true;
    if (!ficha) return false;
    if (ficha.rol === 'super_admin') return true;
    if (ROLES_REQ.length === 1 && ROLES_REQ[0] === 'super_admin') return false;
    var otros = ROLES_REQ.filter(function (x) { return x !== 'admin' && x !== 'super_admin'; });
    if (ficha.rol === 'admin') return ROLES_REQ.indexOf('admin') !== -1 || !otros.length;
    return otros.indexOf(ficha.rol) !== -1;
  }

  var raiz = document.documentElement;
  raiz.style.visibility = 'hidden';

  /* Indicador de carga (11-ago-2026): la puerta hace dos viajes de red seguidos
     (sesión + ficha de usuarios.rol) antes de pintar nada, y hasta ahora esos
     ~300-600ms eran una pantalla en blanco — se leía como que la intranet iba
     lenta. No se toca el fail-closed (sigue sin pintarse NADA del contenido
     real hasta confirmar sesión): esto es un `visibility:visible` propio por
     encima del `hidden` del <html>, con la marca del estudio, nada de datos. */
  var carga = document.createElement('div');
  carga.id = 'lw-gate-carga';
  carga.style.cssText = 'visibility:visible;position:fixed;inset:0;display:flex;' +
    'align-items:center;justify-content:center;background:var(--rl,#F5F0E6);z-index:2147483647';
  carga.innerHTML = '<div style="width:32px;height:32px;border:2.5px solid rgba(16,76,79,.16);' +
    'border-top-color:var(--dl,#104C4F);border-radius:50%;animation:lw-gate-girar .75s linear infinite">' +
    '</div><style>@keyframes lw-gate-girar{to{transform:rotate(360deg)}}</style>';
  raiz.appendChild(carga);
  function quitarCarga() { if (carga.parentNode) carga.parentNode.removeChild(carga); }

  function alLogin() {
    location.replace(LOGIN + '?next=' + encodeURIComponent(location.pathname + location.search));
  }

  /* PETICIONES EN VUELO DEL CLIENTE (27-sep-2026). El velo de la v4 (datos.js)
     contaba solo las consultas que pasaban por su `vig()`: una segunda tanda
     sin envolver, o una pantalla que pinta con su propio script (Finanzas,
     Gastos, Bancos…), no contaba, el velo se iba y se veian los «—» hasta que
     llegaba el dato (lo vio el owner). Todo lo que la pagina pide a Supabase
     pasa por este cliente, asi que se cuenta aqui. Una peticion sigue contada
     hasta que alguien termina de LEER su cuerpo, no solo hasta las cabeceras:
     con 1000 contratos el cuerpo tarda, y el pintado va detras. Si nadie lo lee,
     se descuenta a los 4 s para no dejar el contador colgado (el velo se rinde a los 12). */
  var RED = window.LW_RED = window.LW_RED || { n: 0, alCero: [] };
  function fetchContado(input, init) {
    RED.n++;
    var hecho = false;
    var baja = function () {
      if (hecho) return;
      hecho = true;
      RED.n--;
      if (RED.n === 0) RED.alCero.slice().forEach(function (f) { try { f(); } catch (e) {} });
    };
    var p;
    try { p = window.fetch(input, init); } catch (e) { baja(); throw e; }
    return p.then(function (res) {
      sospechaVersion(res.status);
      // sin cuerpo que leer (los recuentos van por HEAD; 204/304): termina con las cabeceras
      var metodo = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
      if (metodo === 'HEAD' || res.status === 204 || res.status === 205 || res.status === 304) { baja(); return res; }
      ['text', 'json', 'blob', 'arrayBuffer'].forEach(function (k) {
        var orig = res[k];
        if (typeof orig !== 'function') return;
        res[k] = function () { var c = orig.apply(res, arguments); c.then(baja, baja); return c; };
      });
      setTimeout(baja, 4000);
      return res;
    }, function (e) { baja(); throw e; });
  }

  window.LW_AUTH = new Promise(function (resolve) {
    function comprobar() {
      if (!window.supabase || !window.supabase.createClient) { alLogin(); return; }
      /* UN SOLO CLIENTE POR PÁGINA (4-ago-2026). Contratos y Facturas se montaban
         el suyo además de este, y dos clientes de supabase-js sobre el mismo
         almacenamiento de sesión se pisan al refrescar el token. Se publica el de
         aquí y esas herramientas lo toman en vez de crear otro. */
      var sb = window.LW_SB || window.supabase.createClient(URL_SB, KEY_SB, { global: { fetch: fetchContado } });
      window.LW_SB = sb;
      sb.auth.getSession().then(function (r) {
        var sesion = r && r.data && r.data.session;
        if (!sesion) { alLogin(); return; }
        /* MODO MANTENIMIENTO (23-sep-2026): el estado se pide YA, en paralelo a
           la ficha, para no sumar un viaje. La lógica vive en cierre.js (la
           comparte el hub). Su lectura nunca rechaza —un fallo es `null` y se
           pasa—, así que no puede tumbar la ficha si la base no contesta. */
        var cierre = window.lwCierre;
        if (!cierre) console.error('[guard] falta /contracts/assets/cierre.js antes de guard.js: el modo mantenimiento no se aplica en esta página');
        var pEstado = cierre ? cierre.leer(sb) : Promise.resolve(null);
        function entrar(ficha) {
          var sigue = cierre ? cierre.puerta(sb, ficha, pEstado).catch(function () { return true; }) : Promise.resolve(true);
          sigue.then(function (ok) {
            quitarCarga();
            if (!ok) return;          // pantalla de mantenimiento puesta: la herramienta no arranca
            raiz.style.visibility = '';
            resolve({ sb: sb, session: sesion, ficha: ficha });
          });
        }
        // la ficha manda qué herramientas ve. La RLS de `usuarios` ya limita
        // esta consulta a la fila propia (o a todas, si es admin).
        // `notif_visto_hasta` lo usa la campana de topbar.js para saber qué es
        // nuevo. Se pide aquí y no allí porque esta consulta ya se hace: pedirla
        // dos veces sería dos viajes para la misma fila.
        /* ⚠️ 14-sep-2026 — EL CLAIM `portal` YA NO ECHA POR SI SOLO, Y EL ORDEN
           ES LO IMPORTANTE. Hasta hoy esto miraba `app_metadata.portal` ANTES
           de leer la ficha de `usuarios` y mandaba a /portal/ a cualquiera que
           lo tuviera. Con la decision del owner de que una misma cuenta pueda
           ser del equipo Y comprador (hay 8 personas del equipo con ficha de
           comprador, 6 de ellas con contrato), poner el claim a un admin lo
           habria echado de su propia intranet — un candado que se cierra por
           dentro.
           Manda la FICHA: si existe y esta activa, es del equipo y entra, tenga
           el claim o no. El claim solo decide a donde va quien NO es del equipo,
           y eso se decide abajo, ya con la ficha leida. La regla de fondo del
           8-sep no se toca: sin ficha de equipo no se entra a /intranet/. */
        sb.from('usuarios').select('rol, herramientas, activo, nombre, notif_visto_hasta')
          .eq('user_id', sesion.user.id).maybeSingle()
          .then(function (f) {
            var ficha = (f && f.data) || null;
            if (ficha && !ficha.activo) { alLogin(); return; }   // desactivado = fuera
            /* SIN FICHA = NO ES DEL EQUIPO -> FUERA (8-sep-2026, orden del owner:
               «los clientes no deben entrar nunca en /intranet/»).
               Hasta hoy aqui habia una compatibilidad heredada: «sin ficha se
               permite», pensada para las cuentas anteriores al panel de usuarios.
               El claim `portal` (que hasta el 14-sep se miraba ANTES de llegar
               aqui, ver la nota de arriba) tapaba el caso conocido, pero no el
               peligroso: una cuenta de cliente a la que le FALTE ese claim no era
               del equipo y aun asi entraba — con las herramientas vacias por RLS,
               si, pero dentro. Un cliente no debe ver ni la cascara.
               Se puede cerrar hoy porque ya no hay a quien dejar fuera: medido
               contra auth.users el 8-sep, de 43 cuentas 24 tienen ficha de equipo
               y 19 el claim del portal — CERO huerfanas.
               Cierra hacia fuera a proposito: se cierra la sesion antes de mandar
               al login, para no dejar una sesion viva rebotando entre dos puertas. */
            if (!ficha) {
              /* Sin ficha de equipo. Si trae el claim del portal es un
                 comprador: a su casa, con la sesion viva (cerrarla le obligaria
                 a volver a pedir el enlace de entrada por nada). Sin el claim no
                 es de ninguno de los dos mundos: fuera, y cerrando la sesion
                 para no dejarla rebotando entre las dos puertas. */
              if ((sesion.user.app_metadata || {}).portal) { location.replace('/portal/'); return; }
              sb.auth.signOut().then(alLogin, alLogin); return;
            }
            /* Solo el SUPER admin se salta la comprobación (18-ago-2026): un
               admin normal pasa por su lista de herramientas como cualquiera.
               Ver la nota de lwPermitida en assets/herramientas.js — y `puede()`
               en la base, que es quien lo impide de verdad. */
            var sinLimite = ficha && ficha.rol === 'super_admin';
            if (HERRAMIENTAS_REQ && ficha && !sinLimite &&
                !HERRAMIENTAS_REQ.some(function (h) { return (ficha.herramientas || []).indexOf(h) !== -1; })) {
              location.replace(HUB + '?sin_permiso=' + encodeURIComponent(HERRAMIENTA));
              return;
            }
            if (!rolBasta(ficha)) {
              location.replace(HUB + '?sin_permiso=' + encodeURIComponent('Panel de control'));
              return;
            }
            entrar(ficha);
          })
          .catch(function () {   // sin poder leer la ficha se entra igual: la RLS sigue protegiendo los datos
            if (!rolBasta(null)) { location.replace(HUB + '?sin_permiso=' + encodeURIComponent('Panel de control')); return; }
            entrar(null);         // …salvo con la intranet cerrada: sin ficha no se puede probar que sea admin
          });
      }).catch(alLogin);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', comprobar);
    else comprobar();
  });
})();
