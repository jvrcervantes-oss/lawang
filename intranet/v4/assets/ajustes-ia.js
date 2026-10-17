/* Ajustes › IA (MCP de Lawang F1-P4, 16-oct-2026): el interruptor mínimo para que el super admin encienda la conexión con asistentes
 * de IA sin el estudio (máxima 2: nada del ERP fuera de su base). Encargo: encargos/20261015_erp_mcp.md (agencia), fila «Lawang F1-P4».
 * Servidor: supabase/migrations/20261016073530_mcp_f1_p4_ajustes.sql.
 *
 * Qué hace esta pieza (y solo esto), solo para el super administrador GLOBAL:
 *  · lee todo de una vez por `ia_ajustes_ver` (interruptor y topes, asistentes, equipo con su permiso y su uso de hoy, conexiones vivas);
 *  · encender/apagar y los tres topes → `ia_ajustes_guarda` (solo lo que cambió: la base admite un subconjunto);
 *  · un cliente por asistente (Claude, ChatGPT) con sus direcciones de vuelta → `ia_cliente_guarda`; nace APAGADO (lo nuevo nace cerrado);
 *  · quién puede conectar → `ia_permiso_guarda` (quitarlo corta sus conexiones en el acto: se avisa ANTES);
 *  · cortar cualquier conexión viva → `ia_conexion_revoca` (LW_IA.cortar, compartido con /v4/ia/).
 * Lo que NO hace: decidir quién puede. La base lo comprueba en cada función (es_super_admin(): 42501 si no); aquí la pestaña solo se
 * destapa para quien la base va a dejar, y en una instancia del ERP no se destapa (allí las ia_* no existen). No valida rangos por su
 * cuenta: los rangos y las direcciones de vuelta los decide la base, y esta pantalla dice en llano el motivo que devuelve.
 * Formularios de 1-3 campos por paso (owner, 15-oct-2026). Todo se pinta con createElement/textContent: nombres de personas y de
 * asistentes vienen de la base. Enganche por data-accion / data-ia-* (ids de fila), nunca por rótulo.
 */
(function () {
  'use strict';
  function T(s, h) { if (window.lwT) return window.lwT(s, h); var v = String(s); for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) v = v.split('%' + k).join(h[k]); return v; }

  /* La dirección de vuelta que cada asistente usa hoy (la que su documentación pide registrar). Es una PROPUESTA editable al crear el
     cliente, no una regla: lo que vale lo decide privado.ia_redirect_valida en la base (https y el dominio de su asistente). */
  var VUELTA = {
    claude: 'https://claude.ai/api/mcp/auth_callback',
    chatgpt: 'https://chatgpt.com/connector_platform_oauth_redirect'
  };

  var IA = null, sb = null, D = null, filtro = '';
  var C_PEQ = 'font-body-sm text-body-sm text-outline';
  var C_BTN = 'shrink-0 px-5 py-2.5 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md';
  var C_INPUT = 'w-full rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md';
  var N = 0;   // ids únicos para <label for>

  function el(t, c, x) { return IA.el(t, c, x); }
  function campo(etiqueta, ayuda, input) {
    var id = 'lw-ia-c' + (++N);
    var f = el('div', 'flex flex-col gap-1');
    var l = el('label', 'font-label-md text-label-md text-on-surface', etiqueta); l.htmlFor = id;
    input.id = id;
    f.appendChild(l); f.appendChild(input);
    if (ayuda) f.appendChild(el('span', C_PEQ, ayuda));
    return f;
  }
  function numero(clave, valor, min, max) {
    var i = el('input', C_INPUT + ' md:w-40'); i.type = 'number'; i.step = '1'; i.min = String(min); i.max = String(max); i.inputMode = 'numeric';
    i.value = valor == null ? '' : String(valor); i.setAttribute('data-ia-tope', clave); i.setAttribute('data-ia-antes', i.value);
    return i;
  }
  var UM = {};   // usuarios por id: se construye UNA vez por carga (pinta), no en cada fila
  function clientePorId() { var m = {}; (D.clientes || []).forEach(function (k) { m[k.id] = k; }); return m; }
  function nombrePersona(id) {
    var u = UM[id];
    return u ? (u.nombre || T('(sin nombre)')) : T('Usuario fuera del equipo activo (%i…)', { i: String(id || '').slice(0, 8) });
  }
  function vivasDe(campoId, id) { return (D.conexiones || []).filter(function (c) { return c[campoId] === id; }).length; }

  /* ── guardar: un solo camino para las tres escrituras (botón quieto mientras va, frase de la base, recarga) ─────────── */
  function guarda(rpc, args, err, b, hecho, prefijo) {
    if (b) b.disabled = true;
    var no = function (m) { if (b) b.disabled = false; IA.mal(T(prefijo || 'No se ha guardado: %m', { m: m })); return false; };
    return sb.rpc(rpc, args).then(function (r) {
      var e = IA.textoError(r, err);
      if (e) return no(e);
      if (b) b.disabled = false;
      IA.bien(hecho || T('Guardado.'));
      carga();
      return true;
    }, function (x) { return no((x && x.message) || T('sin respuesta')); });
  }
  function guardaAjustes(datos, b) {
    var ERR = {
      campo_desconocido: function (d) { return T('La base no reconoce el campo «%c».', { c: String(d.campo || '') }); },
      fuera_de_rango: 'Algún valor se sale de su rango: consultas al día de 0 a 5000, días de 1 a 30 y conexiones de 1 a 10.',
      datos_invalidos: 'Escribe números enteros, sin decimales.',
      falta_tope: datos.encendido === true
        ? 'Fija primero cuántas consultas al día por persona: con 0 no se puede encender.'
        : 'Con la IA encendida el tope de consultas al día no puede ser 0: pon un número o apágala antes.'
    };
    return guarda('ia_ajustes_guarda', { p_datos: datos }, ERR, b);
  }

  var ERR_CLIENTE = {
    asistente: 'Elige Claude o ChatGPT.',
    nombre: 'El nombre tiene que tener entre 1 y 60 letras.',
    redirect_uris: 'Pon entre 1 y 3 direcciones de vuelta, una por línea.',
    redirect_uri: function (d) {
      return T('Esta dirección de vuelta no vale: %u. Tiene que empezar por https:// y ser de claude.ai o claude.com (Claude), o de chatgpt.com o chat.openai.com (ChatGPT), sin puerto ni «?».', { u: String(d.uri || '') });
    },
    no_existe: 'Ese asistente ya no existe. Recarga la página.'
  };
  function guardaCliente(id, asistente, nombre, uris, activo, b, hecho) {
    return guarda('ia_cliente_guarda', { p_id: id, p_asistente: asistente, p_nombre: nombre, p_redirect_uris: uris, p_activo: activo }, ERR_CLIENTE, b, hecho);
  }
  /* Una dirección por línea: se quitan los blancos y las líneas vacías. Lo demás (https, dominio, longitud) lo decide la base. */
  function lineas(txt) { return String(txt || '').split(/\r?\n/).map(function (s) { return s.trim(); }).filter(Boolean); }

  /* ── 1. interruptor ──────────────────────────────────────────────────────────────────────────────────────────────── */
  function bloqueInterruptor(raiz) {
    var A = D.ajustes || {};
    var s = IA.seccion('', T('Conexión con asistentes de IA'),
      T('Encendida, las personas con permiso pueden consultar Lawang desde Claude o ChatGPT: cada una ve solo lo que ya ve en la intranet, y cada consulta queda registrada. Apagada, ningún asistente puede consultar nada.'));
    s.s.setAttribute('data-ia-bloque', 'interruptor');
    var enc = A.encendido === true;
    var st = el('p', 'font-body-md text-body-md ' + (enc ? 'text-on-surface' : 'text-on-surface-variant'),
      enc ? T('Encendida.') : T('Apagada.'));
    st.setAttribute('data-ia-encendido', enc ? '1' : '0');
    s.c.appendChild(st);
    if (A.actualizado_en) {
      s.c.appendChild(el('p', C_PEQ, T('Último cambio: %f, por %q.', { f: IA.fecha(A.actualizado_en), q: A.actualizado_por ? nombrePersona(A.actualizado_por) : '—' })));
    }
    // Lo que conviene tener antes de encender. Solo el tope lo exige la base (falta_tope); lo demás se avisa, no se impone.
    var activos = (D.clientes || []).filter(function (k) { return k.activo; }).length;
    var conPermiso = (D.usuarios || []).filter(function (u) { return u.permiso; }).length;
    var lista = el('ul', 'flex flex-col gap-1');
    [[Number(A.tope_dia) > 0, Number(A.tope_dia) > 0 ? T('Tope fijado: %n consultas al día por persona.', { n: A.tope_dia }) : T('Falta el tope de consultas al día (paso de abajo): sin él no se enciende.')],
     [activos > 0, activos > 0 ? T('Asistentes encendidos: %n.', { n: activos }) : T('Ningún asistente encendido todavía: nadie podría conectarse.')],
     [conPermiso > 0, conPermiso > 0 ? T('Personas con permiso: %n.', { n: conPermiso }) : T('Nadie tiene permiso todavía para conectar.')]
    ].forEach(function (x) {
      var li = el('li', 'flex items-start gap-2 font-body-sm text-body-sm ' + (x[0] ? 'text-on-surface' : 'text-burnt-earth'));
      var ic = el('span', 'material-symbols-outlined text-[18px] shrink-0', x[0] ? 'check_circle' : 'error'); ic.setAttribute('aria-hidden', 'true');
      li.appendChild(ic); li.appendChild(el('span', '', x[1]));
      lista.appendChild(li);
    });
    s.c.appendChild(lista);
    var b = IA.boton(enc ? T('Apagar la IA') : T('Encender la IA'), enc ? 'ia-apagar' : 'ia-encender', enc ? null : C_BTN);
    b.addEventListener('click', function () {
      if (!enc && !(Number(A.tope_dia) > 0)) {
        IA.mal(T('Fija primero cuántas consultas al día por persona: con 0 no se puede encender.'));
        var t = raiz.querySelector('[data-ia-tope="tope_dia"]'); if (t) t.focus();
        return;
      }
      var q = window.lwConfirmar ? window.lwConfirmar(enc ? {
        titulo: T('¿Apagar la IA?'),
        cuerpo: '<p>' + IA.esc(T('Desde ahora ningún asistente podrá consultar nada. Las conexiones no se borran: si la vuelves a encender antes de que caduquen, siguen funcionando. Para cortar una del todo, usa «Cortar» en Conexiones vivas.')) + '</p>',
        confirmar: T('Sí, apagar'), tono: 'peligro'
      } : {
        titulo: T('¿Encender la IA?'),
        cuerpo: '<p>' + IA.esc(T('Las personas con permiso podrán consultar Lawang desde su asistente, con un máximo de %n consultas al día cada una.', { n: A.tope_dia })) + '</p>',
        confirmar: T('Sí, encender')
      }) : Promise.resolve(false);
      q.then(function (si) { if (si) guardaAjustes({ encendido: !enc }, b); });
    });
    var pie = el('div', 'flex'); pie.appendChild(b); s.c.appendChild(pie);
    raiz.appendChild(s.s);
  }

  /* ── 2. topes (tres campos, un paso) ──────────────────────────────────────────────────────────────────────────────── */
  function bloqueTopes(raiz) {
    var A = D.ajustes || {};
    var s = IA.seccion('', T('Topes'), T('Cuánto puede usar cada persona. Se guardan solo los que cambies.'));
    s.s.setAttribute('data-ia-bloque', 'topes');
    var malla = el('div', 'grid grid-cols-1 md:grid-cols-3 gap-5');
    malla.appendChild(campo(T('Consultas al día por persona'), T('De 0 a 5000. Con 0 nadie puede consultar, y la IA no se enciende.'), numero('tope_dia', A.tope_dia, 0, 5000)));
    malla.appendChild(campo(T('Días que dura una conexión'), T('De 1 a 30. Pasado ese tiempo, el asistente pide otra vez el usuario de Lawang.'), numero('duracion_dias', A.duracion_dias, 1, 30)));
    malla.appendChild(campo(T('Conexiones a la vez por persona'), T('De 1 a 10 (por ejemplo, Claude en el ordenador y ChatGPT en el móvil son dos).'), numero('max_conexiones', A.max_conexiones, 1, 10)));
    s.c.appendChild(malla);
    var b = IA.boton(T('Guardar los topes'), 'ia-guardar-topes', C_BTN);
    b.addEventListener('click', function () {
      var c = {}, n = 0, malo = null;
      [].forEach.call(s.c.querySelectorAll('[data-ia-tope]'), function (i) {
        if (malo) return;
        var v = i.value.trim();
        if (v === i.getAttribute('data-ia-antes')) return;
        // vacío, decimales o letras: no se manda. Hasta 6 cifras: más desborda el integer de la base y volvería como
        // datos_invalidos («sin decimales»), que no es el motivo; con 6 la base dice fuera_de_rango, que sí lo es.
        if ((i.validity && i.validity.badInput) || !/^\d{1,6}$/.test(v)) { malo = i; return; }
        c[i.getAttribute('data-ia-tope')] = Number(v); n++;
      });
      if (malo) { IA.mal(T('Escribe un número entero dentro de su rango; no se ha guardado nada.')); malo.focus(); return; }
      if (!n) { IA.mal(T('No has cambiado nada.')); return; }
      guardaAjustes(c, b);
    });
    var pie = el('div', 'flex'); pie.appendChild(b); s.c.appendChild(pie);
    // En reposo no hay nada que guardar: el botón sale al cambiar un tope y se va si vuelve a su valor (ajustes-ux, 17-oct-2026).
    // Va con display, no con [hidden]: la clase flex de Tailwind le gana a [hidden] en esta página.
    var mira = function () {
      var cambia = [].some.call(s.c.querySelectorAll('[data-ia-tope]'), function (i) { return i.value.trim() !== i.getAttribute('data-ia-antes'); });
      pie.hidden = !cambia; pie.style.display = cambia ? '' : 'none';
    };
    s.c.addEventListener('input', mira);
    mira();
    raiz.appendChild(s.s);
  }

  /* ── 3. asistentes (un cliente por asistente) ─────────────────────────────────────────────────────────────────────── */
  function formCliente(caja, k, asistente) {
    // Paso con 2 campos: nombre y direcciones de vuelta (una por línea, hasta 3). El asistente ya se eligió (o es el del cliente).
    caja.textContent = '';
    var f = el('div', 'flex flex-col gap-4 rounded-xl border border-outline-variant/60 p-4');
    f.setAttribute('data-ia-form-cliente', k ? k.id : 'nuevo');
    f.appendChild(el('p', 'font-label-md text-label-md text-on-surface', k ? T('Editar %n', { n: k.nombre }) : T('Nuevo cliente para %a', { a: IA.asistenteTexto(asistente) })));
    var nom = el('input', C_INPUT); nom.type = 'text'; nom.maxLength = 60; nom.autocomplete = 'off';
    nom.value = k ? (k.nombre || '') : IA.asistenteTexto(asistente);
    f.appendChild(campo(T('Nombre'), T('Cómo lo verá la persona al conectarse y en «Apps conectadas».'), nom));
    var dir = el('textarea', C_INPUT + ' font-mono'); dir.rows = 3; dir.spellcheck = false; dir.autocomplete = 'off';
    dir.value = k ? (k.redirect_uris || []).join('\n') : (VUELTA[asistente] || '');
    f.appendChild(campo(T('Direcciones de vuelta'), T('Una por línea, hasta 3. Va propuesta la que usa hoy este asistente; cámbiala solo si su documentación dice otra.'), dir));
    var pie = el('div', 'flex flex-wrap gap-2');
    var ok = IA.boton(k ? T('Guardar') : T('Crear el cliente'), k ? 'ia-cliente-guardar' : 'ia-cliente-crear', C_BTN);
    ok.addEventListener('click', function () {
      var uris = lineas(dir.value);
      if (!nom.value.trim()) { IA.mal(T('El nombre tiene que tener entre 1 y 60 letras.')); nom.focus(); return; }
      if (!uris.length) { IA.mal(T('Pon entre 1 y 3 direcciones de vuelta, una por línea.')); dir.focus(); return; }
      guardaCliente(k ? k.id : null, k ? k.asistente : asistente, nom.value.trim(), uris, k ? !!k.activo : false, ok,
        k ? T('Guardado.') : T('Cliente creado. Nace apagado: enciéndelo cuando hayas pegado su identificador en el asistente.'));
    });
    var no = IA.boton(T('Cancelar'), 'ia-cliente-cancelar');
    no.addEventListener('click', function () { caja.textContent = ''; if (!k) caja.appendChild(botonNuevo(caja)); });
    pie.appendChild(ok); pie.appendChild(no); f.appendChild(pie);
    caja.appendChild(f);
    nom.focus();
  }
  function botonNuevo(caja) {
    var b = IA.boton(T('Nuevo cliente'), 'ia-cliente-nuevo', C_BTN);
    b.addEventListener('click', function () {
      // Paso 1 (un campo): qué asistente. Paso 2: nombre y dirección de vuelta, ya propuestos.
      caja.textContent = '';
      var p = el('div', 'flex flex-col gap-3 rounded-xl border border-outline-variant/60 p-4');
      p.setAttribute('data-ia-paso', 'asistente');
      p.appendChild(el('p', 'font-label-md text-label-md text-on-surface', T('¿Para qué asistente?')));
      var fila = el('div', 'flex flex-wrap gap-2');
      Object.keys(VUELTA).forEach(function (a) {
        var x = IA.boton(IA.asistenteTexto(a), 'ia-cliente-elige');
        x.setAttribute('data-ia-asistente', a);
        x.addEventListener('click', function () { formCliente(caja, null, a); });
        fila.appendChild(x);
      });
      var no = IA.boton(T('Cancelar'), 'ia-cliente-cancelar');
      no.addEventListener('click', function () { caja.textContent = ''; caja.appendChild(botonNuevo(caja)); });
      fila.appendChild(no);
      p.appendChild(fila);
      caja.appendChild(p);
    });
    return b;
  }
  function bloqueCliente(k) {
    var t = el('div', 'flex flex-col gap-3 py-4 border-b border-outline-variant/30');
    t.setAttribute('data-ia-cliente', k.id);
    var cab = el('div', 'flex flex-wrap items-center gap-2');
    var tipo = IA.asistenteTexto(k.asistente), nom = k.nombre || tipo;
    cab.appendChild(el('span', 'font-label-md text-label-md text-on-surface break-words', nom));
    if (String(nom).trim().toLowerCase() !== String(tipo).trim().toLowerCase()) cab.appendChild(el('span', C_PEQ, tipo));   // sin «Claude Claude»
    var pa = el('span', 'inline-flex items-center px-3 py-1 rounded-full font-label-md text-[12px] ' + (k.activo ? 'bg-primary-fixed text-on-primary-fixed' : 'bg-surface-container text-on-surface-variant'),
      k.activo ? T('Encendido') : T('Apagado'));
    cab.appendChild(pa);
    t.appendChild(cab);
    t.appendChild(IA.copiable(T('Identificador del cliente (OAuth Client ID)'), k.id, 'ia-copiar-cliente'));
    var dv = el('div', 'flex flex-col gap-1');
    dv.appendChild(el('span', 'font-label-md text-label-md text-on-surface', T('Direcciones de vuelta')));
    (k.redirect_uris || []).forEach(function (u) { dv.appendChild(el('code', 'break-all font-body-sm text-body-sm text-on-surface-variant', u)); });
    t.appendChild(dv);
    var caja = el('div', '');
    var botones = el('div', 'flex flex-wrap gap-2');
    var ed = IA.boton(T('Editar'), 'ia-cliente-editar');
    ed.setAttribute('data-ia-cliente-id', k.id);
    ed.addEventListener('click', function () { formCliente(caja, k, k.asistente); });
    var act = IA.boton(k.activo ? T('Apagar este asistente') : T('Encender este asistente'), 'ia-cliente-activo', k.activo ? null : C_BTN);
    act.setAttribute('data-ia-cliente-id', k.id);
    act.addEventListener('click', function () {
      var n = vivasDe('cliente_id', k.id);
      var q = !k.activo ? Promise.resolve(true) : (window.lwConfirmar ? window.lwConfirmar({
        titulo: T('¿Apagar %n?', { n: k.nombre }),
        cuerpo: '<p>' + IA.esc(n ? (n === 1 ? T('Su única conexión viva se corta en el acto, y nadie podrá conectarlo hasta que lo enciendas.')
                                         : T('Sus %c conexiones vivas se cortan en el acto, y nadie podrá conectarlo hasta que lo enciendas.', { c: n }))
                                : T('Nadie podrá conectarlo hasta que lo enciendas.')) + '</p>',
        confirmar: T('Sí, apagar'), tono: 'peligro'
      }) : Promise.resolve(false));
      q.then(function (si) {
        if (si) guardaCliente(k.id, k.asistente, k.nombre, k.redirect_uris || [], !k.activo, act, k.activo ? T('Asistente apagado.') : T('Asistente encendido.'));
      });
    });
    botones.appendChild(ed); botones.appendChild(act);
    t.appendChild(botones);
    t.appendChild(caja);
    return t;
  }
  function bloqueClientes(raiz) {
    var s = IA.seccion('', T('Asistentes'),
      T('Un cliente por asistente. Para conectar, cada persona pega en Claude o en ChatGPT la dirección del conector y el identificador del cliente (OAuth Client ID). Un cliente apagado no deja conectar a nadie.'));
    s.s.setAttribute('data-ia-bloque', 'clientes');
    s.c.appendChild(IA.copiable(T('Dirección del conector'), IA.urlConector(), 'ia-copiar-conector'));
    var lista = el('div', 'flex flex-col');
    if (!(D.clientes || []).length) lista.appendChild(el('p', 'font-body-md text-body-md text-on-surface-variant', T('Todavía no hay ningún cliente. Crea uno para Claude, para ChatGPT o para los dos.')));
    (D.clientes || []).forEach(function (k) { lista.appendChild(bloqueCliente(k)); });
    s.c.appendChild(lista);
    var caja = el('div', 'w-full'); caja.appendChild(botonNuevo(caja));   // bloque, no fila flex: el formulario ocupa el ancho de la sección
    s.c.appendChild(caja);
    raiz.appendChild(s.s);
  }

  /* ── 4. quién puede conectar ───────────────────────────────────────────────────────────────────────────────────────── */
  var ERR_PERMISO = {
    usuario_inactivo: 'Ese usuario está desactivado: actívalo antes en Usuarios.',
    datos_invalidos: 'Faltan datos: recarga la página.'
  };
  function filaPersona(u) {
    var f = el('div', 'flex flex-col sm:flex-row sm:items-center justify-between gap-2 py-3 border-b border-outline-variant/30');
    f.setAttribute('data-ia-usuario-fila', u.user_id);
    var izq = el('div', 'flex flex-col min-w-0');
    izq.appendChild(el('span', 'font-label-md text-label-md text-on-surface break-words', u.nombre || T('(sin nombre)')));
    var linea = u.rol ? T(window.LW_ROL ? LW_ROL.etiqueta(u.rol) : u.rol) : '—';
    if (u.permiso) linea += ' · ' + (Number(u.uso_hoy) === 1 ? T('hoy, 1 consulta') : T('hoy, %n consultas', { n: Number(u.uso_hoy) || 0 }));
    izq.appendChild(el('span', C_PEQ, linea));
    f.appendChild(izq);
    var b = IA.boton(u.permiso ? T('Quitar el permiso') : T('Dar permiso'), u.permiso ? 'ia-permiso-quitar' : 'ia-permiso-dar');
    b.setAttribute('data-ia-usuario', u.user_id);
    b.setAttribute('aria-label', u.permiso ? T('Quitar el permiso a %n', { n: u.nombre || '' }) : T('Dar permiso a %n', { n: u.nombre || '' }));
    b.addEventListener('click', function () {
      var n = vivasDe('usuario_id', u.user_id);
      var q = !u.permiso ? Promise.resolve(true) : (window.lwConfirmar ? window.lwConfirmar({
        titulo: T('¿Quitar el permiso a %n?', { n: u.nombre || '' }),
        cuerpo: '<p>' + IA.esc(T('Deja de poder conectar asistentes de IA.') + (n ? ' ' + (n === 1 ? T('Su conexión viva se corta en el acto.') : T('Sus %c conexiones vivas se cortan en el acto.', { c: n })) : '')) + '</p>',
        confirmar: T('Sí, quitar'), tono: 'peligro'
      }) : Promise.resolve(false));
      q.then(function (si) {
        if (si) guarda('ia_permiso_guarda', { p_usuario: u.user_id, p_concede: !u.permiso }, ERR_PERMISO, b,
          u.permiso ? T('Permiso quitado.') : T('Permiso concedido.'), 'No se ha cambiado el permiso: %m');
      });
    });
    f.appendChild(b);
    return f;
  }
  function pintaPersonas(lista) {
    lista.textContent = '';
    var q = filtro;
    var hay = (D.usuarios || []).filter(function (u) {
      // la pieza común sin tildes (vocabulario.js, que Ajustes carga sin defer); sin ella no se filtra: mejor de más que esconder a alguien
      return typeof window.lwBuscaEn === 'function' ? window.lwBuscaEn([u.nombre, u.rol], q) : true;
    });
    if (!hay.length) { lista.appendChild(el('p', C_PEQ, (D.usuarios || []).length ? T('Nadie con ese nombre.') : T('No hay nadie activo en el equipo.'))); return; }
    hay.forEach(function (u) { lista.appendChild(filaPersona(u)); });
  }
  /* «Dar permiso a todo el equipo» (17-oct-2026, sesión mcp-ventana; owner: «todos desde hoy»). No hay función nueva en la base: es la
     misma ia_permiso_guarda persona a persona, y cada llamada la autoriza la base. Una a una y en orden (34 personas: segundos), para
     decir al final quién no ha podido y por qué; las que fallan quedan sin permiso y se ven en la lista. Quien entre después al
     equipo necesita su «Dar permiso» (no hay «todos los futuros»: encargo, «Para después»). */
  function botonTodos(sin) {
    var b = IA.boton(T('Dar permiso a todo el equipo (%n)', { n: sin.length }), 'ia-permiso-dar-todos');
    b.addEventListener('click', function () {
      var q = window.lwConfirmar ? window.lwConfirmar({
        titulo: T('¿Dar permiso a %n personas?', { n: sin.length }),
        cuerpo: '<p>' + IA.esc(T('Podrán conectar su asistente de IA con su propio usuario. Cada una verá solo lo que ya ve en la intranet, con el tope de consultas al día de cada persona.')) + '</p>',
        confirmar: T('Sí, dar permiso')
      }) : Promise.resolve(false);
      q.then(function (si) {
        if (!si) return;
        b.disabled = true;
        var mal = [], hechos = 0;
        var una = function (i) {
          if (i >= sin.length) {
            b.disabled = false;
            if (mal.length) IA.mal(T('Permiso dado a %h de %t. Sin permiso: %l', { h: hechos, t: sin.length, l: mal.join(' · ') }));
            else IA.bien(T('Permiso dado a %t personas.', { t: hechos }));
            carga();
            return;
          }
          var u = sin[i];
          var falla = function (m) { mal.push((u.nombre || T('(sin nombre)')) + ' (' + m + ')'); una(i + 1); };
          sb.rpc('ia_permiso_guarda', { p_usuario: u.user_id, p_concede: true }).then(function (r) {
            var e = IA.textoError(r, ERR_PERMISO);
            if (e) return falla(e);
            hechos++; una(i + 1);
          }, function (x) { falla((x && x.message) || T('sin respuesta')); });
        };
        una(0);
      });
    });
    return b;
  }
  function bloquePermisos(raiz) {
    var us = D.usuarios || [];
    var con = us.filter(function (u) { return u.permiso; }).length;
    var s = IA.seccion('', T('Quién puede conectar'),
      T('Solo quien tenga permiso puede conectar un asistente, y el asistente ve solo lo que esa persona ve. Quitar el permiso corta en el acto sus conexiones.'));
    s.s.setAttribute('data-ia-bloque', 'permisos');
    s.c.appendChild(el('p', C_PEQ, T('%n de %t personas del equipo pueden conectar.', { n: con, t: us.length })));
    var sin = us.filter(function (u) { return !u.permiso; });
    if (sin.length) s.c.appendChild(botonTodos(sin));
    var bus = el('input', C_INPUT + ' md:w-80'); bus.type = 'search'; bus.autocomplete = 'off'; bus.value = filtro;
    bus.setAttribute('data-ia-buscar', '');
    s.c.appendChild(campo(T('Buscar persona'), null, bus));
    var lista = el('div', 'flex flex-col'); lista.setAttribute('data-ia-personas', '');
    bus.addEventListener('input', function () { filtro = bus.value; pintaPersonas(lista); });
    pintaPersonas(lista);
    s.c.appendChild(lista);
    raiz.appendChild(s.s);
  }

  /* ── 5. conexiones vivas (de todos) ────────────────────────────────────────────────────────────────────────────────── */
  function bloqueConexiones(raiz) {
    var s = IA.seccion('', T('Conexiones vivas'), T('Las de todo el equipo que todavía no han caducado ni se han cortado.'));
    s.s.setAttribute('data-ia-bloque', 'conexiones');
    var cs = D.conexiones || [], K = clientePorId();
    if (!cs.length) s.c.appendChild(el('p', 'font-body-md text-body-md text-on-surface-variant', T('Ninguna conexión viva ahora mismo.')));
    cs.forEach(function (c) {
      var f = el('div', 'flex flex-col md:flex-row md:items-center justify-between gap-2 py-3 border-b border-outline-variant/30');
      f.setAttribute('data-ia-conexion-fila', c.id);
      var izq = el('div', 'flex flex-col min-w-0');
      var k = K[c.cliente_id];
      var quien = nombrePersona(c.usuario_id);
      var con = k ? (k.nombre || IA.asistenteTexto(k.asistente)) : T('asistente borrado');
      izq.appendChild(el('span', 'font-label-md text-label-md text-on-surface break-words', T('%p con %a', { p: quien, a: con })));
      izq.appendChild(el('span', C_PEQ, T('Conectada el %f · caduca el %g', { f: IA.fecha(c.creada_en), g: IA.fecha(c.expira_en) }) +
        (c.aal === 'aal2' ? ' · ' + T('entró con doble factor') : '')));
      f.appendChild(izq);
      var b = IA.boton(T('Cortar'), 'ia-cortar');
      b.setAttribute('data-ia-conexion', c.id);
      b.setAttribute('aria-label', T('Cortar la conexión de %p con %a', { p: quien, a: con }));
      b.addEventListener('click', function () {
        IA.cortar(sb, c.id, T('%p con %a', { p: quien, a: con }), b).then(function (ok) { if (ok) carga(); });
      });
      f.appendChild(b);
      s.c.appendChild(f);
    });
    raiz.appendChild(s.s);
  }

  function pinta() {
    var raiz = document.getElementById('lw-ia-aj'); if (!raiz) return;
    raiz.textContent = '';
    UM = {}; (D.usuarios || []).forEach(function (u) { UM[u.user_id] = u; });
    bloqueInterruptor(raiz);
    bloqueTopes(raiz);
    bloqueClientes(raiz);
    bloquePermisos(raiz);
    bloqueConexiones(raiz);
  }

  function carga() {
    var raiz = document.getElementById('lw-ia-aj'); if (!raiz) return Promise.resolve();
    var p = sb.rpc('ia_ajustes_ver');   // no es una *_datos de lw_lector: lwDatos no la admite (20261016080111)
    return Promise.resolve(p).then(function (r) {
      var e = IA.textoError(r, null);
      if (e || !r.data || !r.data.ajustes) {
        raiz.textContent = '';
        var x = el('p', 'px-8 py-6 font-body-md text-body-md text-error',
          r && r.error && r.error.code === '42501' ? T('Solo el super admin puede ver y cambiar la IA: lo comprueba la base de datos.')
            : T('No se han podido leer los ajustes de la IA: %m. Recarga la página.', { m: e || T('respuesta sin datos') }));
        x.setAttribute('role', 'alert'); x.setAttribute('data-ia-error', '');
        raiz.appendChild(x);
        return;
      }
      D = r.data; pinta();
    }, function (x) {
      raiz.textContent = '';
      var p2 = el('p', 'px-8 py-6 font-body-md text-body-md text-error', T('No se han podido leer los ajustes de la IA: %m. Recarga la página.', { m: (x && x.message) || T('sin respuesta') }));
      p2.setAttribute('role', 'alert'); p2.setAttribute('data-ia-error', '');
      raiz.appendChild(p2);
    });
  }

  function arranca() {
    var bt = document.querySelector('[data-lw-tab="ia"]');
    IA = window.LW_IA;
    if (!bt || !IA || !window.LW_AUTH || window.AXW_NUCLEO_OPERACION) return;   // en una instancia del ERP las ia_* no existen
    window.LW_AUTH.then(function (aut) {
      if (!aut || !aut.sb || !window.LW_ROL || !window.LW_ROL.esSuperGlobal(aut.ficha)) return;   // es_super_admin() = rol 'super_admin'
      sb = aut.sb;
      bt.hidden = false;
      // la pestaña estaba oculta cuando ajustes.js leyó el #: si la URL ya pedía esta, que se abra ahora
      if (location.hash === '#ia') window.dispatchEvent(new HashChangeEvent('hashchange'));
      carga();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
