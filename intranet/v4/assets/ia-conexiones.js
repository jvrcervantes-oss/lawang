/* «Apps conectadas» y lo común de las conexiones de IA (MCP de Lawang F1-P4, 16-oct-2026).
 * Encargo: encargos/20261015_erp_mcp.md (agencia), fila «Lawang F1-P4». Servidor: supabase/migrations/20261016073530_mcp_f1_p4_ajustes.sql
 * (ia_mis_conexiones) y 20261016073011_mcp_f1_p1_base.sql (ia_conexion_revoca).
 *
 * Dos usos, un solo fichero (Regla 0 de la suite: lo que usan dos pantallas nace compartido):
 *  · window.LW_IA — lo que comparten /v4/ia/ (las conexiones de la persona) y Ajustes › IA (ajustes-ia.js, las de todos):
 *    nombre del asistente, estado de una conexión, el motivo de un corte en llano, la dirección del conector, cortar una
 *    conexión (confirmar → RPC → aviso) y el texto de los errores de la base.
 *  · la pantalla /v4/ia/ («Apps conectadas»), solo si la página tiene #lw-ia-apps. Es de CUALQUIER persona del equipo: ve y
 *    corta SOLO las suyas (la base lo decide: ia_mis_conexiones filtra por la sesión e ia_conexion_revoca da 42501 si no es suya
 *    ni es super admin).
 * Lo que NO hace: escribir en una tabla. Lee y corta por RPC; el navegador no decide nada (máxima del owner, 26-sep-2026).
 * Todo lo que viene de la base (el nombre del asistente lo pone el super admin) se pinta con textContent. Se engancha por
 * data-accion / data-ia-conexion (el id de la fila), nunca por un rótulo.
 * Tres estados que NUNCA se leen igual: «no he podido mirar» (r.error: red o permiso), «la base dice que no» (r.data.error) y
 * «no hay ninguna» (lista vacía, con cómo se conecta).
 */
(function (raiz) {
  'use strict';
  function T(s, h) { if (raiz.lwT) return raiz.lwT(s, h); var v = String(s); for (var k in h) if (Object.prototype.hasOwnProperty.call(h, k)) v = v.split('%' + k).join(h[k]); return v; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  /* toast y toastMal son `const` de primer nivel de suite-comun.js: viven en el ámbito global de los scripts, NO en window. Por eso se
     llaman por su nombre suelto, como en el resto de la suite; con raiz.toast no salía ningún aviso de Ajustes › IA ni de las apps
     conectadas (revisor, 17-oct-2026). raiz.* queda para el arnés, que los pone en window. */
  function avisa(m, error) {
    var f = error && typeof toastMal === 'function' ? toastMal : (typeof toast === 'function' ? toast : null);
    if (!f) f = error && typeof raiz.toastMal === 'function' ? raiz.toastMal : (typeof raiz.toast === 'function' ? raiz.toast : null);
    if (f) f(m);
  }
  function bien(m) { avisa(m, false); }
  function mal(m) { avisa(m, true); }

  /* ── lógica pura (la prueba la usa sin navegador) ──────────────────────────────────────────────────────────────────── */
  var ASISTENTES = { claude: 'Claude', chatgpt: 'ChatGPT' };   // la lista cerrada de la base (ia_clientes.asistente)
  function asistenteTexto(a) { return ASISTENTES[a] || String(a || '—'); }

  /* revocada_motivo: los 10 valores del CHECK de ia_conexiones. Uno que no esté aquí se enseña como «cortada» a secas. */
  var MOTIVOS = {
    persona: 'la cortaste tú',
    admin: 'la cortó el super admin',
    asistente: 'la desconectó el propio asistente',
    reuso_codigo: 'se cortó por seguridad: alguien intentó usar dos veces el mismo código de entrada',
    reuso_refresco: 'se cortó por seguridad: alguien intentó usar una credencial ya gastada',
    contrasena: 'se cortó porque cambiaron los datos de acceso de la cuenta (contraseña, correo o doble factor)',
    permiso: 'se cortó porque se quitó el permiso para conectar asistentes',
    apagado: 'se cortó porque se apagó la IA en la intranet',
    usuario_inactivo: 'se cortó porque el usuario está desactivado',
    cliente: 'se cortó porque el super admin apagó ese asistente'
  };
  function motivoTexto(m) { return MOTIVOS[m] ? T(MOTIVOS[m]) : T('cortada'); }

  /* activa · pausada (viva, pero la IA está apagada: la base no la revoca, solo niega cada consulta) · caducada · cortada */
  function estado(c, encendido) {
    if (!c) return 'cortada';
    if (c.revocada_en) return 'cortada';
    if (c.viva === false) return 'caducada';
    return encendido === false ? 'pausada' : 'activa';
  }
  function separa(conexiones, encendido) {
    var vivas = [], pasadas = [];
    (conexiones || []).forEach(function (c) {
      var e = estado(c, encendido);
      (e === 'activa' || e === 'pausada' ? vivas : pasadas).push(c);
    });
    return { vivas: vivas, pasadas: pasadas };
  }
  /* Qué enseña /v4/ia/ antes de la lista. Un aviso que NO se va (no un toast): es lo que hay que ver cada vez que se entra. */
  function aviso(d) {
    if (!d || d.encendido !== true) return 'apagado';
    if (d.permiso !== true) return 'sin_permiso';
    return null;
  }

  function fecha(x) {
    if (!x) return '—';
    var d = new Date(x);
    return isNaN(d) ? String(x) : d.toLocaleString(raiz.lwLocale ? raiz.lwLocale() : 'es-ES', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  /* La dirección del conector es la de la edge `mcp` de ESTA instalación: la construye guard.js (lwEdge) con su sb_url, nunca un
     literal aquí. (El valor que la base guarda es ia_ajustes.recurso; ia_ajustes_ver no lo devuelve todavía.) */
  function urlConector() {
    try { return typeof raiz.lwEdge === 'function' ? raiz.lwEdge('mcp') : ''; }
    catch (e) { return ''; }   // MUDO A PROPÓSITO: sin guard.js no hay dirección que enseñar; quien la pinta dice «no disponible»
  }

  /* El texto de un error de la base. `r` es la respuesta de supabase-js ({data, error}). Devuelve null si no hay error.
     `mapa` traduce los códigos de negocio (r.data.error) de cada pantalla; el resto cae a un texto general. */
  function textoError(r, mapa) {
    if (!r) return T('Sin respuesta del servidor.');
    if (r.error) {
      if (r.error.code === '42501') return T('No tienes permiso para esto: lo comprueba la base de datos.');
      return T('No ha llegado al servidor: %m', { m: r.error.message || T('sin detalle') });
    }
    var d = r.data;
    if (d && typeof d === 'object' && d.error) {
      if (mapa && mapa[d.error]) return typeof mapa[d.error] === 'function' ? mapa[d.error](d) : T(mapa[d.error]);
      return T('La base no lo ha aceptado (%c).', { c: String(d.error) });
    }
    return null;
  }

  /* ── cortar una conexión (las dos pantallas) ──────────────────────────────────────────────────────────────────────── */
  var ERR_CORTAR = {
    no_existe: 'Esa conexión ya no existe. Recarga la página.'
  };
  /* Pregunta, corta y avisa. Devuelve una promesa: true si la base la cortó. `quien` es lo que se nombra en el diálogo. */
  function cortar(sb, id, quien, boton) {
    var q = raiz.lwConfirmar ? raiz.lwConfirmar({
      titulo: T('¿Cortar esta conexión?'),
      cuerpo: '<p>' + esc(T('%n deja de poder consultar Lawang en el acto. Para volver a usarlo hay que conectarlo otra vez desde el asistente.', { n: quien || T('Este asistente') })) + '</p>',
      confirmar: T('Sí, cortar'), tono: 'peligro'
    }) : Promise.resolve(false);   // sin el diálogo de la suite no se corta nada (nunca el diálogo nativo del navegador)
    return q.then(function (si) {
      if (!si) return false;
      if (boton) boton.disabled = true;
      return sb.rpc('ia_conexion_revoca', { p_conexion: id }).then(function (r) {
        if (boton) boton.disabled = false;
        var e = textoError(r, ERR_CORTAR);
        if (e) { mal(T('No se ha cortado: %m', { m: e })); return false; }
        bien(T('Conexión cortada.'));
        return true;
      }, function (x) {
        if (boton) boton.disabled = false;
        mal(T('No se ha cortado: %m', { m: (x && x.message) || T('sin respuesta') }));
        return false;
      });
    });
  }

  /* ── piezas de pantalla ─────────────────────────────────────────────────────────────────────────────────────────────── */
  var C_PEQ = 'font-body-sm text-body-sm text-outline';
  var C_BTN2 = 'shrink-0 px-4 py-2 rounded-full border border-outline-variant text-on-surface hover:bg-surface-container font-label-md text-label-md';
  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  function boton(txt, accion, cls) {
    var b = el('button', cls || C_BTN2, txt); b.type = 'button';
    b.setAttribute('data-accion', accion); b.setAttribute('data-real', '');   // maqueta.js deja en paz lo cableado
    return b;
  }
  /* La pastilla del estado: el color dice el estado y el texto lo repite (nunca solo color). */
  function pastilla(e) {
    var txt = { activa: T('Activa'), pausada: T('En pausa: la IA está apagada'), caducada: T('Caducada'), cortada: T('Cortada') }[e];
    var cls = e === 'activa' ? 'bg-primary-fixed text-on-primary-fixed' : e === 'pausada' ? 'bg-surface-alt text-burnt-earth' : 'bg-surface-container text-on-surface-variant';
    var p = el('span', 'inline-flex items-center px-3 py-1 rounded-full font-label-md text-[12px] ' + cls, txt);
    p.setAttribute('data-ia-estado', e);
    return p;
  }
  function seccion(etq, titulo, texto) {
    var s = el('section', 'bg-surface-container-lowest rounded-xl shadow-sm overflow-hidden');
    var h = el('div', 'px-5 md:px-8 pt-6 md:pt-8 pb-4 flex flex-col gap-1 border-b border-outline-variant/40');
    if (etq) h.appendChild(el('span', 'font-label-md text-[11px] tracking-[0.16em] uppercase text-outline font-bold', etq));
    h.appendChild(el('h2', 'font-headline-sm text-headline-sm text-deep-lagoon tracking-tight', titulo));
    if (texto) h.appendChild(el('p', C_PEQ, texto));
    s.appendChild(h);
    var c = el('div', 'px-5 md:px-8 py-6 flex flex-col gap-4'); s.appendChild(c);
    return { s: s, c: c };
  }
  /* Una línea «Etiqueta: valor» que se puede copiar (la dirección del conector, el identificador de un cliente). */
  function copiable(etiqueta, valor, accion) {
    var f = el('div', 'flex flex-col gap-1');
    f.appendChild(el('span', 'font-label-md text-label-md text-on-surface', etiqueta));
    var fila = el('div', 'flex flex-col sm:flex-row sm:items-center gap-2');
    var v = el('code', 'min-w-0 break-all rounded-lg bg-surface-container-low px-3 py-2 font-body-sm text-body-sm text-on-surface', valor || T('No disponible en esta página: recárgala.'));
    fila.appendChild(v);
    if (valor) {
      var b = boton(T('Copiar'), accion);
      b.addEventListener('click', function () {
        var hecho = function () { bien(T('Copiado.')); };
        var falla = function () { mal(T('No se ha podido copiar: selecciónalo y cópialo a mano.')); };
        try { if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(valor).then(hecho, falla); else falla(); }
        catch (e) { falla(); }
      });
      fila.appendChild(b);
    }
    f.appendChild(fila);
    return f;
  }

  /* Qué bloques enseña «Cómo se conecta»: con la lista de la base, solo los asistentes activos; sin ella, los dos (decisión del owner del 15-oct). */
  function bloques(d) {
    var clientes = Array.isArray(d && d.clientes) ? d.clientes : null;
    var de = function (a) { return clientes ? clientes.filter(function (k) { return k && k.asistente === a; }) : null; };
    return { conLista: !!clientes, claude: de('claude'), chatgpt: de('chatgpt'), vacio: !!clientes && !clientes.length };
  }

  raiz.LW_IA = {
    asistenteTexto: asistenteTexto, motivoTexto: motivoTexto, estado: estado, separa: separa, aviso: aviso, fecha: fecha, bloques: bloques,
    urlConector: urlConector, textoError: textoError, cortar: cortar,
    el: el, boton: boton, pastilla: pastilla, seccion: seccion, copiable: copiable, esc: esc, T: T, bien: bien, mal: mal,
    MOTIVOS: MOTIVOS
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = raiz.LW_IA;

  /* ── la pantalla /v4/ia/ ────────────────────────────────────────────────────────────────────────────────────────────── */
  if (typeof document === 'undefined') return;
  var sb = null, esSuperSesion = false, lectura = 0;

  function tarjeta(c, encendido, pintar) {
    var e = estado(c, encendido);
    var t = el('div', 'flex flex-col md:flex-row md:items-center justify-between gap-3 py-4 border-b border-outline-variant/30 last:border-b-0');
    t.setAttribute('data-ia-conexion-fila', c.id);
    var izq = el('div', 'flex flex-col gap-1 min-w-0');
    var cab = el('div', 'flex flex-wrap items-center gap-2');
    cab.appendChild(el('span', 'font-label-md text-label-md text-on-surface break-words', c.nombre || asistenteTexto(c.asistente)));
    cab.appendChild(el('span', C_PEQ, asistenteTexto(c.asistente)));
    cab.appendChild(pastilla(e));
    izq.appendChild(cab);
    var linea = T('Conectada el %f', { f: fecha(c.creada_en) });
    if (e === 'cortada') linea += ' · ' + T('cortada el %f: %m', { f: fecha(c.revocada_en), m: motivoTexto(c.revocada_motivo) });
    else if (e === 'caducada') linea += ' · ' + T('caducó el %f', { f: fecha(c.expira_en) });
    else linea += ' · ' + T('caduca el %f', { f: fecha(c.expira_en) });
    izq.appendChild(el('p', C_PEQ, linea));
    var n = Number(c.llamadas) || 0;
    izq.appendChild(el('p', C_PEQ, (n === 1 ? T('1 consulta') : T('%n consultas', { n: n })) + ' · ' +
      (c.ultima_llamada ? T('la última, el %f', { f: fecha(c.ultima_llamada) }) : T('ninguna todavía'))));
    t.appendChild(izq);
    if (e === 'activa' || e === 'pausada') {
      var b = boton(T('Cortar'), 'ia-cortar');
      b.setAttribute('data-ia-conexion', c.id);
      b.setAttribute('aria-label', T('Cortar la conexión de %n', { n: c.nombre || asistenteTexto(c.asistente) }));
      b.addEventListener('click', function () {
        cortar(sb, c.id, c.nombre || asistenteTexto(c.asistente), b).then(function (ok) { if (ok) pintar(); });
      });
      t.appendChild(b);
    }
    return t;
  }

  /* «Cómo se conecta» en pasos (16-oct-2026, sesión mcp-aviso; lo abre la invitación de la cabecera, aviso-ia.js). Los pasos son
     de Claude, por la decisión del owner del 15-oct (Claude desde el principio; ChatGPT solo en planes Business o Enterprise).
     El identificador del cliente (ia_clientes.id): si la base dice qué asistentes están activos (`clientes`, propuesta
     supabase/migrations/20261017015203_ia_mis_conexiones_clientes.sql), sale aquí con su botón Copiar y solo se enseñan los
     pasos de los asistentes activos; mientras no lo diga, se dice dónde está (Ajustes › IA), con el enlace si quien mira es el
     super admin. Nada de rutas de menú de ChatGPT sin comprobar. */
  function paso(n, texto) {
    var f = el('li', 'flex gap-3');
    var num = el('span', 'shrink-0 w-7 h-7 rounded-full bg-surface-container flex items-center justify-center font-label-md text-label-md text-deep-lagoon', String(n));
    num.setAttribute('aria-hidden', 'true');
    var cuerpo = el('div', 'flex flex-col gap-2 min-w-0 flex-1 pt-1');
    cuerpo.appendChild(el('p', 'font-body-md text-body-md text-on-surface', texto));
    f.appendChild(num); f.appendChild(cuerpo);
    return { li: f, c: cuerpo };
  }
  /* Mientras la base no devuelva los asistentes activos: dónde está el identificador, nunca un dato inventado. */
  function dondeIdentificador(esSuper) {
    var f = el('p', 'font-body-sm text-body-sm text-on-surface-variant');
    f.setAttribute('data-ia-identificador', 'ajustes');
    if (esSuper) {
      f.appendChild(document.createTextNode(T('Lo tienes en Ajustes › IA, en la lista de asistentes.') + ' '));
      var a = el('a', 'text-deep-lagoon underline', T('Abrir Ajustes › IA'));
      a.href = '/intranet/v4/ajustes/#ia';
      a.setAttribute('data-accion', 'ia-abrir-ajustes');
      a.setAttribute('data-real', '');
      f.appendChild(a);
    } else {
      f.textContent = T('Está en Ajustes › IA: pídeselo al super admin.');
    }
    return f;
  }
  function comoConectar(c, d, esSuper) {
    var b = bloques(d);
    if (b.vacio) {
      var nada = el('p', 'font-body-md text-body-md text-on-surface-variant', T('Todavía no hay ningún asistente activado para conectar. Lo activa el super admin en Ajustes › IA.'));
      nada.setAttribute('data-ia-sin-clientes', '');
      c.appendChild(nada);
      return;
    }
    var dias = Number(d && d.duracion_dias) > 0 ? Number(d.duracion_dias) : 0;
    c.appendChild(el('p', 'font-body-md text-body-md text-on-surface-variant', dias
      ? T('Tu asistente podrá LEER, con tu usuario, lo que tú ves en la intranet de Dirección y Contabilidad. No ve pasaportes ni documentos de los compradores. Cada consulta queda registrada y la conexión dura %n días.', { n: dias })
      : T('Tu asistente podrá LEER, con tu usuario, lo que tú ves en la intranet de Dirección y Contabilidad. No ve pasaportes ni documentos de los compradores. Cada consulta queda registrada y la conexión caduca sola: la fecha sale junto a cada una.')));

    if (!b.conLista || b.claude.length) {
      var h = el('h3', 'font-label-md text-label-md text-on-surface pt-2', T('En Claude'));
      h.setAttribute('data-ia-pasos', 'claude');
      c.appendChild(h);
      var ol = el('ol', 'flex flex-col gap-4');
      ol.appendChild(paso(1, T('En Claude, abre Ajustes › Conectores y pulsa «Añadir conector personalizado».')).li);
      var p2 = paso(2, T('Ponle un nombre (por ejemplo, Lawang) y pega esta dirección:'));
      p2.c.appendChild(copiable(T('Dirección del conector'), urlConector(), 'ia-copiar-conector'));
      ol.appendChild(p2.li);
      var p3 = paso(3, T('En la configuración avanzada, pega el identificador del cliente (OAuth Client ID):'));
      if (b.conLista) b.claude.forEach(function (k) { p3.c.appendChild(copiable(T('Identificador de %n', { n: k.nombre || 'Claude' }), String(k.id || ''), 'ia-copiar-cliente')); });
      else p3.c.appendChild(dondeIdentificador(esSuper));
      ol.appendChild(p3.li);
      ol.appendChild(paso(4, T('Pulsa «Conectar». Claude te trae a Lawang para que entres con tu usuario y tu contraseña; al volver, la conexión sale arriba, en esta página.')).li);
      c.appendChild(ol);
      c.appendChild(el('p', 'font-body-sm text-body-sm text-on-surface-variant', T('Si no ves «Añadir conector personalizado», tu plan de Claude o quien administra tu organización en Claude no lo permite.')));
    }
    if (!b.conLista || b.chatgpt.length) {
      var g = el('h3', 'font-label-md text-label-md text-on-surface pt-2', T('En ChatGPT'));
      g.setAttribute('data-ia-pasos', 'chatgpt');
      c.appendChild(g);
      c.appendChild(el('p', 'font-body-md text-body-md text-on-surface-variant', T('Solo con un plan Business o Enterprise de ChatGPT, que no entrenan con tus datos. Se añade como conector con la misma dirección y el identificador de ChatGPT, y después entras con tu usuario de Lawang igual que en Claude.')));
      if (b.conLista) b.chatgpt.forEach(function (k) { c.appendChild(copiable(T('Identificador de %n', { n: k.nombre || 'ChatGPT' }), String(k.id || ''), 'ia-copiar-cliente')); });
    }
  }

  function pinta(d, esSuper) {
    var r = document.getElementById('lw-ia-apps'); if (!r) return;
    r.textContent = '';
    var a = aviso(d);
    if (a) {
      var av = el('div', 'rounded-xl border border-burnt-earth/30 bg-surface-alt px-5 py-4 flex items-start gap-3');
      av.setAttribute('role', 'status'); av.setAttribute('data-ia-aviso', a);
      var ic = el('span', 'material-symbols-outlined text-[20px] text-burnt-earth shrink-0', a === 'apagado' ? 'power_off' : 'lock');
      ic.setAttribute('aria-hidden', 'true');
      av.appendChild(ic);
      av.appendChild(el('p', 'font-body-sm text-body-sm text-on-surface-variant', a === 'apagado'
        ? T('La conexión con asistentes de IA está apagada en esta intranet. Cuando el super admin la encienda (Ajustes › IA) podrás conectar Claude o ChatGPT; mientras tanto ningún asistente puede consultar nada.')
        : T('Todavía no tienes permiso para conectar un asistente de IA. Lo concede el super admin en Ajustes › IA: pídeselo si lo necesitas.')));
      r.appendChild(av);
    }
    var p = separa(d.conexiones, d.encendido);
    var s = seccion(null, T('Conectadas ahora'), null);
    s.s.setAttribute('data-ia-bloque', 'vivas');
    if (p.vivas.length) {
      var lista = el('div', 'flex flex-col');
      p.vivas.forEach(function (c) { lista.appendChild(tarjeta(c, d.encendido, carga)); });
      s.c.appendChild(lista);
    } else {
      var v = el('div', 'flex flex-col gap-3'); v.setAttribute('data-ia-vacio', '');
      v.appendChild(el('p', 'font-body-md text-body-md text-on-surface', T('No tienes ningún asistente de IA conectado.')));
      s.c.appendChild(v);
    }
    r.appendChild(s.s);
    if (!a) {
      var cc = seccion(null, T('Cómo se conecta'), null);
      cc.s.setAttribute('data-ia-bloque', 'como');
      comoConectar(cc.c, d, esSuper);
      r.appendChild(cc.s);
    }
    if (p.pasadas.length) {
      var h = seccion(null, T('Cortadas o caducadas (últimos 30 días)'), T('Ya no pueden consultar nada. Se enseñan para que sepas qué pasó con cada una.'));
      h.s.setAttribute('data-ia-bloque', 'pasadas');
      var l2 = el('div', 'flex flex-col');
      p.pasadas.forEach(function (c) { l2.appendChild(tarjeta(c, d.encendido, carga)); });
      h.c.appendChild(l2);
      r.appendChild(h.s);
    }
  }

  function carga() {
    var r = document.getElementById('lw-ia-apps'); if (!r || !sb) return Promise.resolve();
    /* Al volver a la pestaña puede haber dos lecturas en vuelo: solo pinta la última, nunca una respuesta vieja encima de la nueva. */
    var n = ++lectura;
    return sb.rpc('ia_mis_conexiones').then(function (res) {
      if (n !== lectura) return;
      var e = textoError(res, null);
      if (e || !res.data || !Array.isArray(res.data.conexiones)) {
        r.textContent = '';
        var p = el('p', 'font-body-md text-body-md text-error', T('No se han podido leer tus conexiones: %m. Esto no quiere decir que no tengas ninguna: recarga la página.', { m: e || T('respuesta sin datos') }));
        p.setAttribute('role', 'alert'); p.setAttribute('data-ia-error', '');
        r.appendChild(p);
        return;
      }
      pinta(res.data, esSuperSesion);
    }, function (x) {
      if (n !== lectura) return;
      r.textContent = '';
      var p = el('p', 'font-body-md text-body-md text-error', T('No se han podido leer tus conexiones: %m. Esto no quiere decir que no tengas ninguna: recarga la página.', { m: (x && x.message) || T('sin respuesta') }));
      p.setAttribute('role', 'alert'); p.setAttribute('data-ia-error', '');
      r.appendChild(p);
    });
  }

  function arranca() {
    if (!document.getElementById('lw-ia-apps') || !raiz.LW_AUTH) return;
    raiz.LW_AUTH.then(function (aut) {
      if (!aut || !aut.sb) return;
      sb = aut.sb;
      esSuperSesion = !!(aut.ficha && (raiz.LW_ROL && raiz.LW_ROL.esSuperGlobal ? raiz.LW_ROL.esSuperGlobal(aut.ficha) : aut.ficha.rol === 'super_admin'));
      carga();
      /* Quien conecta lo hace en la pestaña de su asistente: al volver aquí, la lista se lee otra vez sin recargar (#403). */
      document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') carga(); });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})(typeof window !== 'undefined' ? window : globalThis);
