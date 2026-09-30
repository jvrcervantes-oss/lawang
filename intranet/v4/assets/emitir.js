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
 *  · La emisión manda SOLO el id de la versión y los valores tecleados: {reservados{nombre_contrato, precio_total,
 *    proyecto_id, unidad_id}, campos, firmantes[{rol, client_id}]}. `precio_total` es el valor reservado que teclea
 *    quien emite (M0 §2 y D2), va tal cual se escribe (sin parsear ni redondear). Moneda y código de parcela los pone
 *    la base desde la unidad; la identidad de los firmantes, desde `clients`. Cualquier otra clave la base la rechaza.
 *  · Permisos: la base (agente con «Contratos», proyecto que puede ver, cliente que puede ver, versión activa).
 *    El menú y guard.js solo evitan ofrecer lo que la base rechazaría.
 *  · Validación: la base es la única validadora (M0 §1). La pantalla no repite sus reglas: enseña sus errores.
 *
 * Lecturas: plantillas y versión por lwDatos (`plantillas_contrato_datos`, `plantilla_version_datos`, dueño
 * erp_lector; las versiones activas las ve cualquier sesión). Proyectos, parcelas y clientes con la lectura que ya
 * usa la suite (tablas con RLS, filtradas por id). El navegador no escribe ninguna tabla: solo llama a las dos RPC.
 *
 * DOCUMENTO E IMPRESIÓN: el texto que devuelve el servidor es TEXTO PLANO sin escapar (M2 punto 4). Se compone en
 * UN solo sitio, `componDocumento`, con nodos de texto (textContent): ni el cuerpo ni ningún valor pasa nunca por
 * un sumidero de HTML (inner/outer HTML) en este fichero. Lo que se imprime es la SIMULACIÓN y lo dice arriba: la emisión no devuelve el texto
 * del contrato emitido y no hay aún una lectura que lo re-componga desde la versión y sus datos (falta una RPC
 * `*_datos`; ver el informe de M5).
 *
 * Enganche por identificador estable: botones por data-accion (emitir-previsualizar, emitir-confirmar,
 * emitir-imprimir), bloques por data-lw, campos por data-lw-campo (la clave) y firmantes por data-lw-rol. */
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
  var NO_DISPONIBLE = { vendida: 1, cobrada: 1, no_disponible: 1, bloqueada: 1 };

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
    plantilla_no_valida: 'Esta versión de la plantilla no se puede emitir desde aquí.'
  };
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
  function pintaFirmantes(firmantes) {
    var caja = $('emitir-firmantes');
    vacia(caja);
    firmantes.forEach(function (f) {
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
    if (!pid) { sel.appendChild(opcion('', T('Elige antes el proyecto'))); return; }
    sel.appendChild(opcion('', T('Trayendo las parcelas…')));
    Promise.resolve(sb.from('unidades').select('id,codigo,estado,moneda,contrato_id').eq('proyecto_id', pid).order('codigo_orden').limit(2000)).then(function (r) {
      if (yo !== tokenUnidades) return;
      if (r.error) throw r.error;
      vacia(sel);
      var lista = r.data || [];
      if (!lista.length) { sel.appendChild(opcion('', T('Este proyecto no tiene parcelas dadas de alta.'))); return; }
      sel.appendChild(opcion('', T('Elige una parcela…')));
      lista.forEach(function (u) {
        unidades[u.id] = u;
        var fuera = !!NO_DISPONIBLE[u.estado] || !u.moneda;
        sel.appendChild(opcion(u.id, u.codigo + ' · ' + (u.estado || '—') + (u.moneda ? ' · ' + u.moneda : ' · ' + T('sin moneda')), fuera));
      });
      sel.disabled = false;
    }).catch(function (e) {
      if (yo !== tokenUnidades) return;
      console.error('[emitir] parcelas', e);
      vacia(sel);
      sel.appendChild(opcion('', T('No se han podido leer las parcelas: recarga la pantalla.')));
    });
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
    return {
      nombre: $('emitir-nombre').value.trim(),
      precio: $('emitir-precio').value.trim(),
      proyecto_id: $('emitir-proyecto').value,
      unidad: uid ? unidades[uid] || null : null,
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
    boton('emitir-imprimir').disabled = !alDia;
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

  /* ── Previsualizar: plantilla_simula con datos de ejemplo tomados de la parcela y de la ficha del cliente. ─ */
  function previsualizar() {
    if (!version) return;
    var f = leeFormulario();
    if (!f.unidad) { mal(T('Elige el proyecto y la parcela antes de previsualizar: la moneda y el código salen de la parcela.')); return; }
    var huella = huellaDe(f);
    var ids = f.firmantes.map(function (x) { return x.client_id; });
    var b = boton('emitir-previsualizar');
    b.disabled = true;
    estado(T('Calculando la vista previa en la base…'));
    /* La simulación no lee `clients` (M0 §7.1): se le pasan los datos de la ficha que esta sesión ya ve. La
       emisión NO los manda: allí la base los lee ella misma por client_id. */
    var fichasP = ids.length
      ? Promise.resolve(sb.from('clients').select('id,full_name,passport_number,email,phone,nationality,address').in('id', ids))
      : Promise.resolve({ data: [] });
    fichasP.then(function (r) {
      if (r.error) throw r.error;
      var fichas = {};
      (r.data || []).forEach(function (k) { fichas[k.id] = k; });
      var firmantes = f.firmantes.map(function (x) {
        var k = fichas[x.client_id] || {};
        return sinVacios({ rol: x.rol, nombre: k.full_name, pasaporte: k.passport_number, email: k.email,
                           telefono: k.phone, nacionalidad: k.nationality, domicilio: k.address });
      });
      var valores = {
        reservados: sinVacios({ nombre_contrato: f.nombre, precio_total: f.precio,
                                moneda: f.unidad.moneda, parcela_codigo: f.unidad.codigo }),
        campos: f.campos,
        firmantes: firmantes
      };
      return sb.rpc('plantilla_simula', { p_version_id: version.id, p_valores: valores });
    }).then(function (r) {
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
      ul.appendChild(nodo('li', null, (x.mensaje || x.codigo || String(x)) + (x.campo ? ' (' + x.campo + ')' : '')));
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
     Los caracteres de control y bidi ya los rechaza la base (M0 §5). */
  function componDocumento(texto) {
    var doc = $('emitir-documento');
    vacia(doc);
    if (texto == null) {
      doc.appendChild(nodo('p', 'lw-emi-marca', T('Sin vista previa: la base no ha podido componer el texto.')));
      return;
    }
    var rotulo = T('Simulación · sin valor contractual') + ' · ' + (plantilla ? plantilla.nombre : '') +
      (version ? ' · v' + version.version : '') + (version && version.hash ? ' · ' + String(version.hash).slice(0, 12) : '');
    doc.appendChild(nodo('p', 'lw-emi-marca', rotulo));
    doc.appendChild(nodo('div', 'lw-emi-texto', texto));
  }

  function imprimir() {
    if (!ultimaSim) { mal(T('Previsualiza antes de imprimir: se imprime la vista previa que ha compuesto la base.')); return; }
    window.print();
  }

  /* ── Emitir: contrato_desde_plantilla con el id de la versión y los valores tecleados. Nada más. ────────── */
  function emitir() {
    if (!version || !ultimaSim || emitido) { mal(T('Previsualiza antes de emitir.')); return; }
    var f = leeFormulario();
    if (huellaDe(f) !== ultimaSim.huella) { invalida(); mal(T('Has cambiado datos desde la vista previa: vuelve a previsualizar antes de emitir.')); return; }
    if (typeof window.lwConfirmar !== 'function') { mal(T('El diálogo aún no ha cargado: espera un segundo y vuelve a pulsar.')); return; }
    window.lwConfirmar({
      titulo: T('¿Emitir el contrato?'),
      /* Texto fijo, sin ningún valor: `cuerpo` de lwConfirmar se pinta como HTML. */
      cuerpo: T('Se creará el contrato con los datos de la vista previa y la parcela quedará reservada a él. La base vuelve a comprobarlo todo antes de guardar.'),
      confirmar: T('Emitir')
    }).then(function (ok) {
      if (!ok) return;
      if (huellaDe(leeFormulario()) !== ultimaSim.huella) { invalida(); return; }
      var b = boton('emitir-confirmar');
      b.disabled = true;
      estado(T('Emitiendo…'));
      var valores = {
        reservados: sinVacios({ nombre_contrato: f.nombre, precio_total: f.precio,
                                proyecto_id: f.proyecto_id, unidad_id: f.unidad && f.unidad.id }),
        campos: f.campos,
        firmantes: f.firmantes
      };
      return Promise.resolve(sb.rpc('contrato_desde_plantilla', { p_version_id: version.id, p_valores: valores })).then(function (r) {
        if (r.error) throw r.error;
        emitido = true;
        pintaEmitido(r.data || {});
        eligeProyecto();   // relee las parcelas: la emitida ya no está libre (se vuelve a elegir para el siguiente)
        estado(T('Contrato emitido.'));
        bien(T('Contrato emitido') + ': ' + ((r.data && r.data.numero) || ''));
        refrescaBotones();
      }).catch(function (e) {
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
    });
  }

  /* Lo que se enseña tras emitir sale de la RESPUESTA de la base (fila insertada y contrato_vencimientos). */
  function pintaEmitido(d) {
    var sec = $('emitir-resultado'), caja = $('emitir-resultado-cuerpo');
    vacia(caja);
    caja.appendChild(nodo('p', 'font-body-md text-body-md text-on-surface',
      T('Número') + ': ' + (d.numero || '—') + ' · ' + T('Precio total') + ': ' + importe(d.precio_total, d.moneda)));
    if ((d.hitos || []).length) caja.appendChild(tablaHitos(d.hitos, d.moneda));
    if (d.numero) {
      var a = nodo('a', 'font-label-md text-label-md text-deep-lagoon', T('Abrir la ficha del contrato'));
      a.setAttribute('href', '../contratos/?contrato=' + encodeURIComponent(d.numero));
      caja.appendChild(a);
    }
    caja.appendChild(nodo('p', 'lw-emi-ayuda', T('La vista previa de abajo es la simulación con la que se emitió; no es el documento oficial del contrato.')));
    sec.hidden = false;
  }

  function cablea() {
    $('emitir-plantilla').addEventListener('change', eligePlantilla);
    $('emitir-proyecto').addEventListener('change', eligeProyecto);
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
      cablea();
      cargaClientes();
      cargaProyectos();
      cargaPlantillas();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
