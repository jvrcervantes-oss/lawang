/* emitir.js — /intranet/v4/emitir/ (AxisWorks ERP, 30-sep-2026; encargo
 * encargos/20260930_estudio_contratos_tipos_mvp.md, subtarea M5 «generador genérico»).
 *
 * Emitir un contrato desde una versión ACTIVA de una plantilla (esquema 1, texto plano). Fichero propio y no un
 * REG/ED de datos.js/editores.js: es la única pantalla que lo usa. Vive en v4/assets/ para que sella_assets.py le
 * ponga su ?v=. Solo con window.AXW_NUCLEO_OPERACION: la base de Lawang no tiene el motor de plantillas.
 *
 * LO QUE ESTA PANTALLA NO DECIDE (contrato: erp/plantillas_mvp_interfaz.md §7.1 y §7.2, del repo de la agencia):
 *  · El texto, el calendario, sus importes y sus fechas: los calcula la base (`plantilla_simula` para ver,
 *    `contrato_desde_plantilla` para emitir, el mismo motor). Aquí solo se PINTA lo que devuelve.
 *  · La emisión manda SOLO el id de la versión y los valores tecleados: {reservados{nombre_contrato, precio_total?,
 *    proyecto_id, unidad_id}, campos, firmantes[{rol, client_id}]}. Moneda y código de parcela los pone la base desde
 *    la unidad; la identidad de los firmantes, desde `clients` (D4: de un firmante la pantalla solo manda rol y
 *    client_id). Cualquier otra clave la base la rechaza.
 *  · PRECIO (owner, 30-sep-2026; contrato §7.2 «regla de precio»): si la parcela tiene precio de lista
 *    (`unidades.precio` > 0), el campo lo enseña en solo lectura y la pantalla NO manda `precio_total`: lo pone la
 *    base desde la lista. Un administrador puede desbloquearlo (data-accion emitir-precio-excepcion) y entonces se
 *    manda lo tecleado, tal cual (sin parsear ni redondear); la base lo acepta solo si es_admin() y lo registra en
 *    datos.plantilla.precio_excepcion. A un agente la base le responde `precio_distinto_lista`. Sin lista, el precio
 *    es libre. El botón solo evita ofrecer lo que la base rechazaría: quien decide es la base.
 *  · Permisos: la base (agente con «Contratos», proyecto que puede ver, cliente que puede ver, versión activa).
 *    El menú y guard.js solo evitan ofrecer lo que la base rechazaría.
 *  · Validación: la base es la única validadora (M0 §1). La pantalla no repite sus reglas: enseña sus errores.
 *
 * Lecturas: plantillas, versión y texto emitido por lwDatos (`plantillas_contrato_datos`, `plantilla_version_datos`,
 * `contrato_plantilla_texto_datos`). Proyectos, parcelas y clientes con la lectura que ya usa la suite (tablas con
 * RLS, filtradas por id). El navegador no escribe ninguna tabla: solo llama a las dos RPC.
 *
 * SIMULACIÓN: `plantilla_simula` sobre la unidad real (reservados.unidad_id), así aplica la misma regla de precio que
 * la emisión y devuelve el aviso D1. Firmantes igual que al emitir: solo {rol, client_id} (D4, §7.1); la base lee
 * la ficha de `clients` con la visibilidad de quien llama. El navegador no manda nunca la identidad de un cliente,
 * ni para ver ni para emitir; de `clients` solo lee id y nombre para pintar los desplegables.
 *
 * DOCUMENTO E IMPRESIÓN: el texto que devuelve el servidor es TEXTO PLANO sin escapar (M2 punto 4). Se compone en
 * UN solo sitio, `componDocumento`, con nodos de texto (textContent): ni el cuerpo ni ningún valor pasa nunca por
 * un sumidero de HTML en este fichero. Lo que se IMPRIME es el texto GUARDADO al emitir, leído con
 * `contrato_plantilla_texto_datos(p_contrato_id)` (§7.5), con su huella `texto_sha256` al pie; nunca se recompone con
 * datos de hoy. La simulación se enseña, pero no se imprime.
 *
 * Enganche por identificador estable: botones por data-accion (emitir-previsualizar, emitir-confirmar,
 * emitir-imprimir, emitir-precio-excepcion), bloques por data-lw, campos por data-lw-campo (la clave) y firmantes por
 * data-lw-rol. */
(function () {
  'use strict';

  var T = function (s) { return typeof window.lwT === 'function' ? window.lwT(s) : s; };
  function $(clave) { return document.querySelector('[data-lw="' + clave + '"]'); }
  function boton(acc) { return document.querySelector('[data-accion="' + acc + '"]'); }
  function nodo(tag, clase, texto) {
    var n = document.createElement(tag);
    if (clase) n.className = clase;
    if (texto != null) n.textContent = String(texto);
    return n;
  }
  function vacia(el) { while (el && el.firstChild) el.removeChild(el.firstChild); }
  function opcion(valor, texto, desactivada) {
    var o = document.createElement('option');
    o.value = valor;
    o.textContent = texto;
    if (desactivada) o.disabled = true;
    return o;
  }
  function bien(m) { if (typeof toast === 'function') toast(m); }
  function mal(m) {
    if (typeof toastMal === 'function') toastMal(m);
    else console.error('[emitir]', m);
  }
  function estado(m) { var e = $('emitir-estado'); if (e) e.textContent = m || ''; }
  function importe(n, moneda) {
    if (n == null || n === '') return '—';
    return typeof lwFormatoImporte === 'function' ? lwFormatoImporte(n, moneda) : String(n) + (moneda ? ' ' + moneda : '');
  }

  /* Estado de la pantalla. */
  var sb = null;
  var plantillas = [];          // plantillas con versión activa y tipo activo
  var plantilla = null;         // la elegida
  var version = null;           // plantilla_version_datos de su versión activa
  var tokenVersion = 0, tokenUnidades = 0;
  var unidades = {};            // id -> fila de `unidades` del proyecto elegido
  var clientesP = null;         // promesa: lista de clientes que la sesión ve (o error)
  var ultimaSim = null;         // { huella, sim } de la última simulación correcta y al día
  var emitido = false;          // tras emitir, no se vuelve a emitir hasta otra vista previa válida
  var emitidoId = null;         // contrato_id del último emitido: lo único que se imprime (su texto guardado)
  var esAdmin = false;          // solo para OFRECER el botón de excepción de precio; lo decide es_admin() en la base
  var precioLibre = false;      // un admin ha desbloqueado el precio de lista de la parcela elegida
  var precioAuto = false;       // el valor del campo precio lo ha puesto la pantalla desde la lista
  /* Parcelas que no se ofrecen: estas y cualquiera con contrato_id (owner, 30-sep). Es más estricto que la base, que
     da por libre una parcela cuyo contrato está liberado; esa se libera primero en su ficha. */
  var NO_DISPONIBLE = { reservada: 1, vendida: 1, cobrada: 1, no_disponible: 1, bloqueada: 1 };
  /* Mismo criterio que esAdminSesion de nav.js y que es_admin() en la base (rol admin o super_admin). */
  function esAdminFicha(ficha) { return !!ficha && (ficha.rol === 'admin' || ficha.rol === 'super_admin'); }

  /* ── Errores de la base → palabras. Se lee el `hint` (código estable de M0 §7.4) antes que el código. ─────── */
  var POR_HINT = {
    sin_permiso: 'No tienes permiso: emitir exige ser agente con «Contratos» y poder ver ese proyecto. Lo comprueba la base.',
    version_no_activa: 'Esa versión ya no está activa: alguien ha activado otra. Recarga la pantalla y vuelve a elegir la plantilla.',
    tipo_desactivado: 'El tipo de contrato de esta plantilla está desactivado: no se emiten contratos nuevos de ese tipo.',
    unidad_ocupada: 'Esa parcela ya está asignada a otro contrato o no está disponible. Elige otra.',
    unidad_otro_proyecto: 'Esa parcela no es del proyecto elegido. Vuelve a elegir proyecto y parcela.',
    unidad_desconocida: 'Esa parcela ya no existe. Recarga la pantalla.',
    proyecto_desconocido: 'Ese proyecto ya no existe. Recarga la pantalla.',
    firmante_desconocido: 'Uno de los firmantes no existe o no es un cliente tuyo.',
    firmante_repetido: 'El mismo cliente no puede firmar en dos papeles, ni un papel llevar dos clientes.',
    campo_no_admitido: 'La pantalla ha mandado un dato que la base no admite. Recarga la pantalla; si vuelve a pasar, avisa al estudio.',
    unidad_no_enlazada: 'La base no ha podido ligar el contrato a la parcela y no ha guardado nada. Avisa al estudio.',
    hitos_suma: 'El calendario de pagos no cuadra con el precio total: revisa el precio.',
    plantilla_no_valida: 'Esta versión de la plantilla no se puede emitir desde aquí.',
    cotitular_no_soportado: 'Por ahora un contrato de plantilla admite un solo firmante; los cotitulares llegarán más adelante.',
    precio_distinto_lista: 'Esta parcela tiene precio de lista y solo un administrador puede poner otro precio. Deja el precio de lista, o pide a un administrador que emita el contrato: quedará registrado quién cambió el precio y cuándo.'
  };
  /* Códigos de la lista de errores (simulación y `detail` de la emisión) que se enseñan con palabras propias en vez
     del mensaje de la base. Solo los que no dicen nada de un campo concreto: el resto lleva su desglose. */
  var POR_CODIGO = { precio_distinto_lista: POR_HINT.precio_distinto_lista, cotitular_no_soportado: POR_HINT.cotitular_no_soportado };
  function errorTexto(e) {
    var h = (e && e.hint) || '', c = (e && e.code) || '', m = (e && e.message) || String(e || '');
    if (POR_HINT[h]) return T(POR_HINT[h]);
    if (c === '42501') return /sesi[oó]n/i.test(m) ? T('Tu sesión ha caducado: vuelve a entrar.') : T(POR_HINT.sin_permiso);
    if (c === 'P0002') return m || T('Eso ya no existe. Recarga la pantalla.');
    return m;
  }
  /* La emisión eleva los errores de validación con la lista entera en `detail` (jsonb en texto). */
  function erroresDe(e) {
    var d = e && e.details;
    if (!d) return [];
    try {
      var j = JSON.parse(d);
      return (j && Array.isArray(j.errores)) ? j.errores : [];
    } catch (x) {
      /* MUDO A PROPOSITO: un `detail` que no es JSON (un error de Postgres sin lista) se enseña por errorTexto(e),
         que es su mensaje entero; aquí solo se pierde el desglose por campo, que ese error no tiene. */
      return [];
    }
  }

  /* ── Plantillas ────────────────────────────────────────────────────────────────────────────────────────── */
  function cargaPlantillas() {
    var sel = $('emitir-plantilla');
    return Promise.resolve(window.lwDatos('plantillas_contrato_datos')).then(function (r) {
      if (r.error) throw r.error;
      var d = r.data || {};
      var tipos = {};
      (d.tipos || []).forEach(function (t) { if (t.activo) tipos[t.clave] = t.nombre || t.clave; });
      plantillas = (d.plantillas || []).filter(function (p) {
        return p.activa && p.activa.id && !p.archivada && tipos[p.tipo_contrato];
      });
      vacia(sel);
      if (!plantillas.length) {
        sel.appendChild(opcion('', T('No hay ninguna plantilla activa de un tipo de contrato activo.')));
        sel.disabled = true;
        return;
      }
      sel.appendChild(opcion('', T('Elige una plantilla…')));
      plantillas.forEach(function (p) {
        sel.appendChild(opcion(p.slug, p.nombre + ' · ' + tipos[p.tipo_contrato] + ' · v' + p.activa.version));
      });
      sel.disabled = false;
    }).catch(function (e) {
      console.error('[emitir] plantillas', e);
      vacia(sel);
      sel.appendChild(opcion('', T('No se han podido leer las plantillas: recarga la pantalla.')));
      sel.disabled = true;
      mal(errorTexto(e));
    });
  }

  function eligePlantilla() {
    var slug = $('emitir-plantilla').value;
    var info = $('emitir-plantilla-info');
    var form = $('emitir-formulario');
    invalida();
    version = null;
    emitidoId = null;   // otra plantilla: el documento emitido deja de estar a la vista y no se imprime desde aquí
    plantilla = plantillas.filter(function (p) { return p.slug === slug; })[0] || null;
    form.hidden = true;
    $('emitir-previa').hidden = true;
    $('emitir-resultado').hidden = true;
    info.textContent = '';
    if (!plantilla) return;
    var yo = ++tokenVersion;
    info.textContent = T('Trayendo la versión activa…');
    Promise.resolve(window.lwDatos('plantilla_version_datos', { p_id: plantilla.activa.id })).then(function (r) {
      if (yo !== tokenVersion) return;
      if (r.error) throw r.error;
      var v = r.data;
      if (!v || v.estado !== 'activa') { info.textContent = T('Esa versión ya no está activa: recarga la pantalla.'); return; }
      if (v.esquema !== 1) {
        info.textContent = T('Esta plantilla es de las antiguas (HTML): se emite desde el generador de contratos, no desde aquí.');
        return;
      }
      version = v;
      emitido = false;
      info.textContent = T('Versión') + ' ' + v.version + ' · ' + T('idioma del documento') + ': ' + String(v.idioma || '').toUpperCase() +
        (v.generado_ia ? ' · ' + T('texto transcrito por IA y revisado por quien lo activó') : '');
      pintaCampos(v.campos || []);
      pintaFirmantes(v.firmantes || []);
      pintaHitosPlantilla(v.hitos, v.campos || []);
      form.hidden = false;
      refrescaBotones();
    }).catch(function (e) {
      if (yo !== tokenVersion) return;
      console.error('[emitir] versión', e);
      info.textContent = T('No se ha podido leer la versión: recarga la pantalla.');
      mal(errorTexto(e));
    });
  }

  /* ── Campos de la plantilla: un control por tipo. Sin reglas propias: la base valida y aquí se enseña. ──── */
  function pintaCampos(campos) {
    var caja = $('emitir-campos');
    vacia(caja);
    if (!campos.length) { caja.appendChild(nodo('p', 'lw-emi-ayuda', T('Esta plantilla no pide datos propios.'))); return; }
    campos.forEach(function (c) {
      var id = 'lw-emi-c-' + c.clave;
      var bloque = nodo('div', 'lw-emi-campo');
      var lab = nodo('label', 'font-label-md text-label-md text-on-surface', c.etiqueta + (c.obligatorio ? ' *' : ''));
      lab.setAttribute('for', id);
      var ctrl, ayuda = null;
      if (c.tipo === 'texto' && Array.isArray(c.opciones) && c.opciones.length) {
        ctrl = document.createElement('select');
        ctrl.appendChild(opcion('', c.obligatorio ? T('Elige…') : T('— Ninguna —')));
        c.opciones.forEach(function (o) { ctrl.appendChild(opcion(o, o)); });
      } else if (c.tipo === 'texto_largo') {
        ctrl = document.createElement('textarea');
        ctrl.rows = 4;
        ctrl.maxLength = c.max_len || 4000;
      } else {
        ctrl = document.createElement('input');
        ctrl.autocomplete = 'off';
        if (c.tipo === 'fecha') ctrl.type = 'date';
        else if (c.tipo === 'email') { ctrl.type = 'email'; ctrl.maxLength = c.max_len || 254; }
        else if (c.tipo === 'numero' || c.tipo === 'importe') {
          ctrl.inputMode = 'decimal';
          ayuda = T('Con punto decimal y sin separador de miles') +
            (c.min != null || c.max != null ? ' · ' + T('entre') + ' ' + (c.min != null ? c.min : '—') + ' ' + T('y') + ' ' + (c.max != null ? c.max : '—') : '');
        } else ctrl.maxLength = c.max_len || 200;
      }
      ctrl.id = id;
      ctrl.className = 'lw-emi-ctrl';
      ctrl.setAttribute('data-lw-campo', c.clave);
      ctrl.setAttribute('data-lw-tipo', c.tipo);
      if (c.obligatorio) ctrl.required = true;
      bloque.appendChild(lab);
      bloque.appendChild(ctrl);
      if (ayuda) bloque.appendChild(nodo('p', 'lw-emi-ayuda', ayuda));
      caja.appendChild(bloque);
    });
  }

  /* ── Firmantes: un desplegable por papel, con los clientes que la sesión ve. ─────────────────────────────── */
  function cargaClientes() {
    clientesP = Promise.resolve(sb.from('clients').select('id,full_name').order('full_name').limit(5000)).then(function (r) {
      if (r.error) throw r.error;
      return { lista: r.data || [] };
    }).catch(function (e) {
      console.error('[emitir] clientes', e);
      return { error: e };
    });
  }
  /* Freno de cotitulares (owner, 30-sep; M0 §3.3 y §7.2, 20260930170000): simular y emitir admiten UN firmante, y
     con dos o más la base responde cotitular_no_soportado. La plantilla puede declarar varios: solo se ofrece el
     primero (adquiriente_1, siempre obligatorio) y un aviso fijo dice por qué faltan los demás. */
  function pintaFirmantes(firmantes) {
    var caja = $('emitir-firmantes');
    vacia(caja);
    if (firmantes.length > 1) {
      var av = nodo('p', 'lw-emi-ayuda', T('Por ahora un contrato de plantilla admite un solo firmante; los cotitulares llegarán más adelante.'));
      av.setAttribute('data-lw', 'emitir-aviso-cotitular');
      caja.appendChild(av);
    }
    firmantes.slice(0, 1).forEach(function (f) {
      var id = 'lw-emi-f-' + f.rol;
      var bloque = nodo('div', 'lw-emi-campo');
      var lab = nodo('label', 'font-label-md text-label-md text-on-surface', (f.etiqueta || f.rol) + (f.obligatorio ? ' *' : ''));
      lab.setAttribute('for', id);
      var sel = document.createElement('select');
      sel.id = id;
      sel.className = 'lw-emi-ctrl';
      sel.setAttribute('data-lw-rol', f.rol);
      sel.disabled = true;
      sel.appendChild(opcion('', T('Trayendo los clientes…')));
      bloque.appendChild(lab);
      bloque.appendChild(sel);
      caja.appendChild(bloque);
      clientesP.then(function (res) {
        vacia(sel);
        /* «No he podido mirar» y «no hay ninguno» se ven distintos (desarrollo/prompt.md). */
        if (res.error) { sel.appendChild(opcion('', T('No se han podido leer los clientes: recarga la pantalla.'))); return; }
        if (!res.lista.length) { sel.appendChild(opcion('', T('No ves ningún cliente: dalo de alta en Clientes.'))); return; }
        sel.appendChild(opcion('', f.obligatorio ? T('Elige un cliente…') : T('— Sin firmante (opcional) —')));
        res.lista.forEach(function (k) { sel.appendChild(opcion(k.id, k.full_name || '—')); });
        /* La API corta en 1000 filas: con 1000 justas la lista puede estar incompleta, y se dice. */
        if (res.lista.length >= 1000) sel.appendChild(opcion('', T('La lista se ha cortado en 1000 clientes: puede faltar alguno.'), true));
        sel.disabled = false;
      });
    });
  }

  /* ── Calendario tal como lo declara la plantilla (lo que la versión dice, sin calcular nada). ────────────── */
  function pintaHitosPlantilla(hitos, campos) {
    var caja = $('emitir-hitos-plantilla');
    vacia(caja);
    if (!hitos || !Array.isArray(hitos.lista) || !hitos.lista.length) {
      caja.appendChild(nodo('p', 'lw-emi-ayuda', T('Esta plantilla no lleva calendario de pagos.')));
      return;
    }
    var etiqueta = {};
    campos.forEach(function (c) { etiqueta[c.clave] = c.etiqueta; });
    var tabla = nodo('table', 'lw-emi-tabla');
    var cab = document.createElement('tr');
    ['Nº', 'Hito', 'Parte', 'Plazo'].forEach(function (t) { cab.appendChild(nodo('th', null, T(t))); });
    tabla.appendChild(cab);
    hitos.lista.forEach(function (h, i) {
      var tr = document.createElement('tr');
      tr.appendChild(nodo('td', null, i + 1));
      tr.appendChild(nodo('td', null, h.es || h.en || h.id || '—'));
      tr.appendChild(nodo('td', 'num', hitos.modo === 'pct' ? String(h.pct) + ' %' : String(h.monto) + ' (' + T('importe fijo') + ')'));
      var plazo = '—';
      if (h.dias != null) {
        plazo = h.dias + ' ' + T('días desde') + ' ' + (h.desde === 'emision' ? T('la emisión') : (etiqueta[h.desde] || h.desde));
      }
      tr.appendChild(nodo('td', null, plazo));
      tabla.appendChild(tr);
    });
    caja.appendChild(tabla);
    caja.appendChild(nodo('p', 'lw-emi-ayuda', T('Los importes y las fechas de cada pago los calcula la base al previsualizar.')));
  }

  /* ── Proyecto y parcela ──────────────────────────────────────────────────────────────────────────────── */
  function cargaProyectos() {
    var sel = $('emitir-proyecto');
    return Promise.resolve(sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre')).then(function (r) {
      if (r.error) throw r.error;
      vacia(sel);
      var lista = r.data || [];
      if (!lista.length) { sel.appendChild(opcion('', T('No ves ningún proyecto activo.'))); sel.disabled = true; return; }
      sel.appendChild(opcion('', T('Elige un proyecto…')));
      lista.forEach(function (p) { sel.appendChild(opcion(p.id, p.nombre)); });
      sel.disabled = false;
    }).catch(function (e) {
      console.error('[emitir] proyectos', e);
      vacia(sel);
      sel.appendChild(opcion('', T('No se han podido leer los proyectos: recarga la pantalla.')));
      sel.disabled = true;
    });
  }
  function eligeProyecto() {
    var pid = $('emitir-proyecto').value;
    var sel = $('emitir-unidad');
    var yo = ++tokenUnidades;
    unidades = {};
    vacia(sel);
    sel.disabled = true;
    eligeUnidad();   // sin parcela: el precio vuelve a ser libre y se quita el de la lista anterior
    if (!pid) { sel.appendChild(opcion('', T('Elige antes el proyecto'))); return; }
    sel.appendChild(opcion('', T('Trayendo las parcelas…')));
    Promise.resolve(sb.from('unidades').select('id,codigo,estado,moneda,precio,contrato_id').eq('proyecto_id', pid).order('codigo_orden').limit(2000)).then(function (r) {
      if (yo !== tokenUnidades) return;
      if (r.error) throw r.error;
      vacia(sel);
      var lista = r.data || [];
      if (!lista.length) { sel.appendChild(opcion('', T('Este proyecto no tiene parcelas dadas de alta.'))); return; }
      sel.appendChild(opcion('', T('Elige una parcela…')));
      lista.forEach(function (u) {
        unidades[u.id] = u;
        var conContrato = u.contrato_id != null;
        var fuera = !!NO_DISPONIBLE[u.estado] || conContrato || !u.moneda;
        sel.appendChild(opcion(u.id, u.codigo + ' · ' + (u.estado || '—') +
          (conContrato ? ' · ' + T('con contrato') : '') +
          (u.moneda ? ' · ' + u.moneda : ' · ' + T('sin moneda')) +
          (fuera ? ' · ' + T('no disponible') : ''), fuera));
      });
      sel.disabled = false;
    }).catch(function (e) {
      if (yo !== tokenUnidades) return;
      console.error('[emitir] parcelas', e);
      vacia(sel);
      sel.appendChild(opcion('', T('No se han podido leer las parcelas: recarga la pantalla.')));
    });
  }

  /* ── Precio: el de lista de la parcela, en solo lectura; otro, solo un administrador (lo decide la base). ── */
  function unidadElegida() { var uid = $('emitir-unidad').value; return uid ? unidades[uid] || null : null; }
  /* Precio de lista de la unidad tal como viene de la base (sin redondear ni formatear), o null si no tiene. */
  function precioLista(u) {
    if (!u || u.precio == null || u.precio === '') return null;
    var n = Number(u.precio);
    return isFinite(n) && n > 0 ? String(u.precio) : null;
  }
  function eligeUnidad() {
    var inp = $('emitir-precio');
    precioLibre = false;
    /* El precio que puso la pantalla desde otra parcela no se queda: sería el de lista de la parcela equivocada. */
    if (precioAuto) inp.value = '';
    precioAuto = false;
    var lista = precioLista(unidadElegida());
    if (lista) { inp.value = lista; precioAuto = true; }
    pintaPrecio();
  }
  function pintaPrecio() {
    var inp = $('emitir-precio'), nota = $('emitir-precio-nota'), b = boton('emitir-precio-excepcion');
    var u = unidadElegida(), lista = precioLista(u);
    inp.readOnly = !!(lista && !precioLibre);
    if (lista && !precioLibre) {
      nota.textContent = T('Precio de lista de la parcela') + ' ' + u.codigo + ': ' + lista + ' ' + (u.moneda || '') +
        '. ' + T('Lo pone la base desde la parcela; no se cambia aquí.');
    } else if (lista) {
      nota.textContent = T('Estás poniendo un precio distinto del de lista') + ' (' + lista + ' ' + (u.moneda || '') + '). ' +
        T('Solo lo acepta la base si eres administrador, y quedará registrado en el contrato quién lo cambió y cuándo. Para volver al de lista, vuelve a elegir la parcela.');
    } else if (u) {
      nota.textContent = T('Esta parcela no tiene precio de lista: escribe el precio.');
    } else {
      nota.textContent = '';
    }
    b.hidden = !(esAdmin && lista && !precioLibre);
  }
  function excepcionPrecio() {
    if (!esAdmin || !precioLista(unidadElegida())) return;
    precioLibre = true;
    precioAuto = false;
    pintaPrecio();
    invalida();
    $('emitir-precio').focus();
  }

  /* ── Leer el formulario. Todo cadenas, sin transformar: la base valida el formato (M0 §3.1). ───────────── */
  function leeFormulario() {
    var campos = {};
    document.querySelectorAll('[data-lw="emitir-campos"] [data-lw-campo]').forEach(function (el) {
      var v = el.getAttribute('data-lw-tipo') === 'texto_largo' ? el.value.replace(/\s+$/, '') : el.value.trim();
      if (v !== '') campos[el.getAttribute('data-lw-campo')] = v;
    });
    var firmantes = [];
    document.querySelectorAll('[data-lw="emitir-firmantes"] [data-lw-rol]').forEach(function (el) {
      if (el.value) firmantes.push({ rol: el.getAttribute('data-lw-rol'), client_id: el.value });
    });
    var uid = $('emitir-unidad').value;
    var u = uid ? unidades[uid] || null : null;
    /* Con precio de lista y sin excepción no se manda precio: lo pone la base (regla de precio, §7.2). */
    var mandaPrecio = !precioLista(u) || precioLibre;
    return {
      nombre: $('emitir-nombre').value.trim(),
      precio: mandaPrecio ? $('emitir-precio').value.trim() : '',
      proyecto_id: $('emitir-proyecto').value,
      unidad: u,
      campos: campos,
      firmantes: firmantes
    };
  }
  function huellaDe(f) {
    var c = {};
    Object.keys(f.campos).sort().forEach(function (k) { c[k] = f.campos[k]; });
    return JSON.stringify([version && version.id, f.nombre, f.precio, f.proyecto_id, f.unidad && f.unidad.id, c, f.firmantes]);
  }
  function sinVacios(o) {
    var r = {};
    Object.keys(o).forEach(function (k) { if (o[k] != null && String(o[k]) !== '') r[k] = String(o[k]); });
    return r;
  }

  function refrescaBotones() {
    var alDia = !!ultimaSim;
    boton('emitir-confirmar').disabled = !(alDia && !emitido && version);
    boton('emitir-imprimir').disabled = !emitidoId;
    boton('emitir-previsualizar').disabled = !version;
  }
  /* Cualquier cambio en el formulario deja la vista previa vieja: se dice y no se puede emitir ni imprimir. */
  function invalida() {
    if (!ultimaSim) return;
    ultimaSim = null;
    var doc = $('emitir-documento');
    if (doc && doc.firstChild) doc.firstChild.textContent = T('Vista previa caducada: has cambiado datos. Vuelve a previsualizar.');
    if (doc && doc.firstChild) doc.firstChild.classList.add('lw-emi-caduca');
    estado(T('Has cambiado datos: vuelve a previsualizar.'));
    refrescaBotones();
  }

  /* ── Previsualizar: plantilla_simula sobre la parcela real (unidad_id), con los firmantes por client_id. ───── */
  function previsualizar() {
    if (!version) return;
    var f = leeFormulario();
    if (!f.unidad) { mal(T('Elige el proyecto y la parcela antes de previsualizar: la moneda y el código salen de la parcela.')); return; }
    var huella = huellaDe(f);
    var b = boton('emitir-previsualizar');
    b.disabled = true;
    estado(T('Calculando la vista previa en la base…'));
    /* Mismo payload que la emisión (sin proyecto_id, que simula no admite): firmantes solo {rol, client_id} (D4,
       §7.1). La ficha la lee la base con la visibilidad de quien llama; un cliente que no ve = firmante_desconocido. */
    var valores = {
      /* Sobre la unidad real: moneda, parcela y precio de lista los pone la base (mandarlos = campo_no_admitido). */
      reservados: sinVacios({ nombre_contrato: f.nombre, precio_total: f.precio, unidad_id: f.unidad.id }),
      campos: f.campos,
      firmantes: f.firmantes.map(function (x) { return { rol: x.rol, client_id: x.client_id }; })
    };
    Promise.resolve(sb.rpc('plantilla_simula', { p_version_id: version.id, p_valores: valores })).then(function (r) {
      if (r.error) throw r.error;
      /* Si mientras la base respondía se cambió algo, esta respuesta ya no describe el formulario. */
      if (huellaDe(leeFormulario()) !== huella) { estado(T('Has cambiado datos mientras se calculaba: vuelve a previsualizar.')); return; }
      pintaSimulacion(r.data || {}, huella);
    }).catch(function (e) {
      console.error('[emitir] simulación', e);
      estado('');
      mal(errorTexto(e));
    }).then(function () { boton('emitir-previsualizar').disabled = !version; });
  }

  function listaMensajes(lista, clase) {
    var ul = nodo('ul', 'lw-emi-lista');
    if (clase) ul.classList.add(clase);
    lista.forEach(function (x) {
      var propio = x && x.codigo && POR_CODIGO[x.codigo];
      ul.appendChild(nodo('li', null, propio ? T(propio) : (x.mensaje || x.codigo || String(x)) + (x.campo ? ' (' + x.campo + ')' : '')));
    });
    return ul;
  }
  function tablaHitos(hitos, moneda) {
    var tabla = nodo('table', 'lw-emi-tabla');
    var cab = document.createElement('tr');
    ['Nº', 'Hito', '%', 'Importe', 'Fecha'].forEach(function (t) { cab.appendChild(nodo('th', null, T(t))); });
    tabla.appendChild(cab);
    hitos.forEach(function (h) {
      var tr = document.createElement('tr');
      tr.appendChild(nodo('td', null, h.orden));
      tr.appendChild(nodo('td', null, h.descripcion || '—'));
      tr.appendChild(nodo('td', 'num', h.pct != null ? String(h.pct) + ' %' : '—'));
      tr.appendChild(nodo('td', 'num', importe(h.monto, moneda)));
      tr.appendChild(nodo('td', null, h.fecha || '—'));
      tabla.appendChild(tr);
    });
    return tabla;
  }

  function pintaSimulacion(sim, huella) {
    var sec = $('emitir-previa'), avisos = $('emitir-avisos'), hit = $('emitir-hitos-simulados');
    sec.hidden = false;
    vacia(avisos);
    vacia(hit);
    emitidoId = null;   // la vista previa nueva sustituye al documento emitido: ya no hay nada que imprimir aquí
    if (!sim.ok) {
      ultimaSim = null;
      avisos.appendChild(nodo('p', 'font-label-md text-label-md text-on-surface', T('La base no lo acepta todavía. Corrige esto y vuelve a previsualizar:')));
      avisos.appendChild(listaMensajes(sim.errores || [], 'mal'));
      componDocumento(null);
      estado(T('Hay datos que corregir.'));
      refrescaBotones();
      return;
    }
    if ((sim.advertencias || []).length) {
      avisos.appendChild(nodo('p', 'font-label-md text-label-md text-on-surface', T('Avisos de la base:')));
      avisos.appendChild(listaMensajes(sim.advertencias));
    }
    var tot = sim.totales || {};
    if ((sim.hitos || []).length) {
      hit.appendChild(nodo('p', 'font-label-md text-label-md text-on-surface', T('Calendario de pagos calculado por la base')));
      hit.appendChild(tablaHitos(sim.hitos, tot.moneda));
      hit.appendChild(nodo('p', 'lw-emi-ayuda', T('Precio total') + ': ' + importe(tot.precio_total, tot.moneda) +
        ' · ' + T('suma de los pagos') + ': ' + importe(tot.suma_monto, tot.moneda)));
    }
    componDocumento(sim.texto);
    ultimaSim = { huella: huella, sim: sim };
    emitido = false;
    estado(T('Vista previa al día. Si cambias algo, hay que volver a previsualizar.'));
    refrescaBotones();
  }

  /* ÚNICO PUNTO DE COMPOSICIÓN DEL DOCUMENTO. El texto del servidor es texto plano sin escapar: va entero a un
     nodo de texto (textContent), nunca como HTML, así que «<», «&» o un {{token}} de un valor salen literales.
     Los caracteres de control y bidi ya los rechaza la base (M0 §5).
     `emi` (opcional) = el contrato emitido: { numero, sha, verificada: true|false|null, motivo }. Sin `emi` es la
     simulación; con `emi` es el texto GUARDADO al emitir (contrato_plantilla_texto_datos) y lleva su huella al pie. */
  function componDocumento(texto, emi) {
    var doc = $('emitir-documento');
    vacia(doc);
    if (texto == null) {
      var sinTexto = !emi ? T('Sin vista previa: la base no ha podido componer el texto.')
        : emi.motivo === 'sin_texto' ? T('El contrato') + ' ' + (emi.numero || '') + ' ' + T('no tiene texto guardado de plantilla: no se imprime desde aquí.')
        : T('Contrato emitido, pero no se ha podido leer su texto guardado: no se imprime. Ábrelo desde su ficha o recarga la pantalla.');
      doc.appendChild(nodo('p', 'lw-emi-marca', sinTexto));
      return;
    }
    var rotulo = emi
      ? T('Contrato') + ' ' + (emi.numero || '—') + ' · ' + T('texto guardado al emitir')
      : T('Simulación · sin valor contractual') + ' · ' + (plantilla ? plantilla.nombre : '') +
        (version ? ' · v' + version.version : '') + (version && version.hash ? ' · ' + String(version.hash).slice(0, 12) : '');
    doc.appendChild(nodo('p', 'lw-emi-marca', rotulo));
    doc.appendChild(nodo('div', 'lw-emi-texto', texto));
    if (emi) {
      var comprobada = !emi.sha ? T('la base no ha devuelto huella: sin comprobar')
        : emi.verificada === true ? T('comprobada en este navegador')
        : emi.verificada === false ? T('NO COINCIDE con el texto recibido: no lo imprimas y avisa al estudio')
        : T('sin comprobar en este navegador');
      doc.appendChild(nodo('p', 'lw-emi-huella', T('Huella del texto (SHA-256)') + ': ' + (emi.sha || '—') + ' · ' + comprobada));
    }
  }

  /* sha256 (hex) del texto en UTF-8, para cotejarlo con `texto_sha256` de la base. null = este navegador no puede
     calcularlo (sin crypto.subtle): se dice «sin comprobar», no se da por bueno ni por malo. */
  function huellaLocal(texto) {
    var sub = window.crypto && window.crypto.subtle;
    if (!sub || typeof TextEncoder !== 'function') return Promise.resolve(null);
    return Promise.resolve(sub.digest('SHA-256', new TextEncoder().encode(texto))).then(function (buf) {
      return Array.prototype.map.call(new Uint8Array(buf), function (x) { return ('0' + x.toString(16)).slice(-2); }).join('');
    });
  }

  /* Trae el texto GUARDADO al emitir (§7.5) y lo compone. Resuelve true si se puede imprimir: hay texto y su huella
     no contradice la de la base. Los errores de lectura se propagan: quien llama los enseña. */
  function cargaEmitido(id) {
    return Promise.resolve(window.lwDatos('contrato_plantilla_texto_datos', { p_contrato_id: id })).then(function (r) {
      if (r.error) throw r.error;
      var d = r.data || {};
      $('emitir-previa').hidden = false;
      vacia($('emitir-avisos'));
      vacia($('emitir-hitos-simulados'));
      if (d.texto == null) { componDocumento(null, { numero: d.numero, motivo: 'sin_texto' }); return false; }
      return huellaLocal(d.texto).then(function (h) {
        var sha = d.texto_sha256 ? String(d.texto_sha256).toLowerCase() : '';
        /* Sin huella de la base no hay con qué comparar: se dice («sin huella»), no se da por mala. */
        var ok = (h == null || sha === '') ? null : h === sha;
        componDocumento(d.texto, { numero: d.numero, sha: d.texto_sha256, verificada: ok });
        return ok !== false;
      });
    });
  }

  function imprimir() {
    if (!emitidoId) { mal(T('Emite el contrato antes de imprimir: se imprime el texto que la base guardó al emitir.')); return; }
    var b = boton('emitir-imprimir');
    b.disabled = true;
    estado(T('Trayendo el texto emitido…'));
    cargaEmitido(emitidoId).then(function (ok) {
      if (!ok) {
        estado(T('No se imprime: el texto guardado falta o su huella no coincide.'));
        mal(T('No se imprime: el texto guardado falta o su huella no coincide. Avisa al estudio.'));
        return;
      }
      estado('');
      window.print();
    }).catch(function (e) {
      console.error('[emitir] texto emitido', e);
      componDocumento(null, { motivo: 'error' });
      estado(T('No se ha podido leer el texto emitido: no se imprime.'));
      mal(errorTexto(e));
    }).then(function () { refrescaBotones(); });
  }

  /* ── Emitir: contrato_desde_plantilla con el id de la versión y los valores tecleados. Nada más. ────────── */
  function emitir() {
    if (!version || !ultimaSim || emitido) { mal(T('Previsualiza antes de emitir.')); return; }
    var f = leeFormulario();
    if (huellaDe(f) !== ultimaSim.huella) { invalida(); mal(T('Has cambiado datos desde la vista previa: vuelve a previsualizar antes de emitir.')); return; }
    if (typeof window.lwConfirmar !== 'function') { mal(T('El diálogo aún no ha cargado: espera un segundo y vuelve a pulsar.')); return; }
    /* D1 (owner, 30-sep): emitir deja la parcela «reservada» salvo en los contratos de construcción (misma condición
       que la advertencia de plantilla_simula). `cuerpo` de lwConfirmar se pinta como HTML: aquí solo va texto FIJO,
       con un hueco vacío; el código de la parcela se mete después en ese hueco con textContent, nunca como HTML. */
    var ocupa = !!(f.unidad && plantilla && plantilla.tipo_contrato !== 'construccion');
    var cuerpo = '<p>' + T('Se creará el contrato con los datos de la vista previa. La base vuelve a comprobarlo todo antes de guardar.') + '</p>' +
      (ocupa ? '<p>' + T('La parcela') + ' <strong data-lw="emitir-dlg-unidad"></strong> ' +
        T('pasará a «reservada» y quedará ligada a este contrato: no se podrá vender ni usar en otro contrato mientras tanto.') + '</p>' : '');
    var confirmado = window.lwConfirmar({ titulo: T('¿Emitir el contrato?'), cuerpo: cuerpo, confirmar: T('Emitir') });
    if (ocupa) {
      var hueco = document.querySelector('#lw-dlg-c [data-lw="emitir-dlg-unidad"]');
      if (hueco) hueco.textContent = f.unidad.codigo;
      else console.error('[emitir] diálogo sin hueco para el código de parcela');
    }
    confirmado.then(function (ok) {
      if (!ok) return;
      if (huellaDe(leeFormulario()) !== ultimaSim.huella) { invalida(); return; }
      var b = boton('emitir-confirmar');
      b.disabled = true;
      estado(T('Emitiendo…'));
      /* Firmantes: solo {rol, client_id} (D4); precio_total solo si no hay lista o un admin la ha desbloqueado. */
      var valores = {
        reservados: sinVacios({ nombre_contrato: f.nombre, precio_total: f.precio,
                                proyecto_id: f.proyecto_id, unidad_id: f.unidad && f.unidad.id }),
        campos: f.campos,
        firmantes: f.firmantes.map(function (x) { return { rol: x.rol, client_id: x.client_id }; })
      };
      return Promise.resolve(sb.rpc('contrato_desde_plantilla', { p_version_id: version.id, p_valores: valores })).then(function (r) {
        if (r.error) throw r.error;
        var d = r.data || {};
        emitido = true;
        ultimaSim = null;              // la vista previa ya se ha usado: la siguiente emisión pide otra
        emitidoId = d.contrato_id || null;
        pintaEmitido(d);
        eligeProyecto();   // relee las parcelas: la emitida ya no está libre (se vuelve a elegir para el siguiente)
        bien(T('Contrato emitido') + ': ' + (d.numero || ''));
        refrescaBotones();
        if (!emitidoId) {
          componDocumento(null, { motivo: 'error' });
          estado(T('Contrato emitido, pero la base no ha devuelto su id: ábrelo desde su ficha para imprimirlo.'));
          return;
        }
        estado(T('Contrato emitido. Trayendo el texto guardado…'));
        return cargaEmitido(emitidoId).then(function (okTexto) {
          estado(okTexto ? T('Contrato emitido. Abajo, el texto guardado al emitir: es lo que se imprime.')
                         : T('Contrato emitido, pero su texto guardado falta o su huella no coincide: no se imprime. Avisa al estudio.'));
        }, function (e) {
          console.error('[emitir] texto emitido', e);
          componDocumento(null, { motivo: 'error' });
          estado(T('Contrato emitido, pero no se ha podido leer su texto guardado.'));
          mal(errorTexto(e));
        });
      }, function (e) {
        console.error('[emitir] emisión', e);
        var lista = erroresDe(e);
        if (lista.length) {
          var avisos = $('emitir-avisos');
          vacia(avisos);
          avisos.appendChild(nodo('p', 'font-label-md text-label-md text-on-surface', T('La base no ha emitido el contrato:')));
          avisos.appendChild(listaMensajes(lista, 'mal'));
        }
        estado(T('No se ha emitido nada.'));
        mal(errorTexto(e));
        refrescaBotones();
      });
    }).catch(function (e) {
      console.error('[emitir] tras emitir', e);
      mal(T('Algo ha fallado en la pantalla al emitir: recarga y comprueba el contrato en Contratos antes de volver a emitir.'));
    });
  }

  /* Lo que se enseña tras emitir sale de la RESPUESTA de la base (fila insertada y contrato_vencimientos). */
  function pintaEmitido(d) {
    var sec = $('emitir-resultado'), caja = $('emitir-resultado-cuerpo');
    vacia(caja);
    caja.appendChild(nodo('p', 'font-body-md text-body-md text-on-surface',
      T('Número') + ': ' + (d.numero || '—') + ' · ' + T('Precio total') + ': ' + importe(d.precio_total, d.moneda)));
    if (d.precio_excepcion) {
      caja.appendChild(nodo('p', 'lw-emi-ayuda', T('Precio distinto del de lista') + ' (' + (d.precio_lista || '—') + '): ' +
        T('queda registrado en el contrato quién lo puso y cuándo.')));
    }
    if ((d.hitos || []).length) caja.appendChild(tablaHitos(d.hitos, d.moneda));
    if (d.numero) {
      var a = nodo('a', 'font-label-md text-label-md text-deep-lagoon', T('Abrir la ficha del contrato'));
      a.setAttribute('href', '../contratos/?contrato=' + encodeURIComponent(d.numero));
      caja.appendChild(a);
    }
    caja.appendChild(nodo('p', 'lw-emi-ayuda', T('El documento de abajo es el texto que la base guardó al emitir, con su huella: es el que se imprime.')));
    sec.hidden = false;
  }

  function cablea() {
    $('emitir-plantilla').addEventListener('change', eligePlantilla);
    $('emitir-proyecto').addEventListener('change', eligeProyecto);
    $('emitir-unidad').addEventListener('change', eligeUnidad);
    boton('emitir-precio-excepcion').addEventListener('click', function (ev) { ev.stopPropagation(); excepcionPrecio(); });
    var form = $('emitir-formulario');
    form.addEventListener('input', invalida);
    form.addEventListener('change', invalida);
    boton('emitir-previsualizar').addEventListener('click', function (ev) { ev.stopPropagation(); previsualizar(); });
    boton('emitir-confirmar').addEventListener('click', function (ev) { ev.stopPropagation(); emitir(); });
    boton('emitir-imprimir').addEventListener('click', function (ev) { ev.stopPropagation(); imprimir(); });
  }

  function arranca() {
    if (!window.AXW_NUCLEO_OPERACION) {
      $('emitir-sin-nucleo').hidden = false;
      $('emitir-paso-plantilla').hidden = true;
      return;
    }
    if (!window.LW_AUTH || typeof window.lwDatos !== 'function') { console.error('[emitir] sin guard.js'); mal(T('Falta guard.js actualizado: recarga la página')); return; }
    window.LW_AUTH.then(function (aut) {
      sb = aut && aut.sb;
      if (!sb) { mal(T('No hay sesión: vuelve a entrar.')); return; }
      esAdmin = esAdminFicha(aut.ficha);
      cablea();
      cargaClientes();
      cargaProyectos();
      cargaPlantillas();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
