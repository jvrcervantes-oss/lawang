/* cabecera.js — la cabecera de la v4: usuario de la sesión y campana de avisos
 * (27-sep-2026, extraído de datos.js sin cambiar lo que hace allí).
 *
 * Por qué fuera de datos.js: el CRM (/intranet/leads/) lleva desde hoy el menú
 * y la cabecera de la v4 (owner: «que el menú y top bar sean los de la v4 y
 * nada más») sin ser una pantalla de /intranet/v4/: no carga datos.js (651 KB
 * de pantallas que no son la suya). La campana y el usuario tenían que existir
 * en un solo sitio para los dos, no copiados. Quién llama:
 *  · datos.js, en las pantallas de la v4: `campana(aut, rol, { cajon: true })`;
 *  · nav-montaje.js, en las páginas a las que MONTA la cabecera (el CRM):
 *    `campana(aut, rol)`, que abre la lista en un desplegable.
 *
 * También vive aquí la PALETA ÚNICA (window.LW_TONOS): la usan la campana y
 * datos.js/editores.js, que cargan DESPUÉS de este fichero (va delante de
 * datos.js en cada pantalla; nav.test.js lo comprueba). */
(function () {
  'use strict';
  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML.replace(/"/g, '&quot;'); }
  /* Textos del marco por lwT (i18n.js, LAW-388, 28-sep-2026): la campana salía en
     español con la intranet en inglés. Se traduce al PINTAR, no al cargar: i18n.js
     llega con `defer` en algunas pantallas. Los títulos y detalles de cada aviso
     son datos (nombres, números de contrato) y vienen hechos de avisos.js. */
  function T(s) { return typeof window.lwT === 'function' ? window.lwT(s) : s; }
  function locale() { return typeof window.lwLocale === 'function' ? window.lwLocale() : 'es-ES'; }

  /* PALETA ÚNICA DE ESTADOS DE LA V4 (23-sep-2026, owner: «¿usamos los mismos
     colores en toda la suite? que facturas tenga el mismo color en todos
     lados»). Había dos copias idénticas (pill() de datos.js y H.tag en editores.js)
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
        '<span class="material-symbols-outlined" style="font-size:15px">' + t.icono + '</span>' + n + ' ' + esc(T(texto)) + '</span>' : '';
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
      return d.toLocaleDateString(locale(), d.getFullYear() === hoyAnio ? { day: 'numeric', month: 'short' } : { day: 'numeric', month: 'short', year: 'numeric' });
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
          '<span style="padding:1px 8px;border-radius:999px;background:' + t.fondo + ';color:' + t.tinta + ';font-size:10.5px;line-height:18px;font-weight:700;letter-spacing:.04em;text-transform:uppercase">' + esc(T(a.etiqueta || 'Aviso')) + '</span>' +
          (a.nuevo && a.clase !== 'alerta' ? '<span style="padding:1px 8px;border-radius:999px;background:#2E3437;color:#fff;font-size:10.5px;line-height:18px;font-weight:700;letter-spacing:.04em;text-transform:uppercase">' + esc(T('Nuevo')) + '</span>' : '') +
        '</span>' +
        '<span class="lw-av-t" style="font-weight:' + (a.nuevo || a.clase === 'alerta' ? '700' : '500') + '">' + esc(a.titulo) + '</span>' +
        '<span class="lw-av-d">' + esc(a.detalle || '') + '</span>' +
        '<span class="lw-av-f">' + esc(fechaCorta(a.cuando)) + '</span>' +
      '</a>';
    };
    var bloque = function (titulo, lista) {
      return lista.length ? '<section style="display:grid;gap:6px">' +
        '<h4 style="margin:6px 0 2px;font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:#75786e">' + esc(T(titulo)) + ' (' + lista.length + ')</h4>' +
        '<div class="lw-av-cab"><span></span><span>' + esc(T('Estado')) + '</span><span>' + esc(T('Aviso')) + '</span><span>' + esc(T('Detalle')) + '</span><span style="text-align:right">' + esc(T('Fecha')) + '</span></div>' +
        lista.map(fila).join('') + '</section>' : '';
    };
    return css + resumen + bloque('Requiere atención', alertas) + bloque('Actividad reciente', hechos);
  }

  /* `opciones.cajon`: la lista se abre en el cajón compartido (`lwCajon`, de
     editores.js) — las pantallas de /intranet/v4/ (datos.js). Sin él, en un
     desplegable bajo la campana: el CRM (/intranet/leads/) lleva el cromo v4
     pero no editores.js (658 KB y su propio arranque por pantalla), y un cajón
     propio sería la segunda copia de aquel. Mismo contenido (pintaAvisos) y
     misma regla de «vistos» en los dos. */
  function campana(aut, rol, opciones) {
    var conCajon = !!(opciones && opciones.cajon);
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
      if (typeof lwAvisos !== 'function') { console.error('[v4 cabecera] falta contracts/assets/avisos.js'); pintaContador(null); return Promise.resolve(null); }
      var ficha = aut.ficha || {};
      var email = (aut.session && aut.session.user && aut.session.user.email) || '';
      return lwAvisos(aut.sb, { esAdmin: LW_ROL.esAdmin(ficha), email: email, vistoHasta: ficha.notif_visto_hasta || null })
        .then(function (out) { ULTIMO = out; pintaContador(out.sinLeer, out.avisos); return out; },
              function (e) { console.error('[v4 cabecera] avisos:', e); pintaContador(null); return null; });
    }
    /* NOVEDADES (30-sep-2026, owner): el pop-up de novedades sale una vez al entrar y aquí se
       vuelve a ver cuando se quiera. La fila solo existe si novedades.js ya cargó y a esta
       persona le toca alguna noticia (window.lwNovedades). Por `data-accion`, no por el rótulo. */
    function filaNovedades() {
      if (!window.lwNovedades || typeof window.lwNovedades.abre !== 'function') return '';
      return '<button type="button" data-accion="ver-novedades" style="display:flex;align-items:center;gap:12px;width:100%;text-align:left;padding:12px 14px;border-radius:10px;border:1px solid #DCEAE7;background:#F1F7F5;color:#104C4F;cursor:pointer;font:inherit">' +
        '<span class="material-symbols-outlined" style="font-size:22px">auto_awesome</span>' +
        '<span style="display:grid;gap:1px"><span style="font-size:14px;font-weight:700">' + esc(T('Novedades')) + '</span>' +
        '<span style="font-size:12.5px;color:#44483f">' + esc(T('Repasa lo último que ha llegado a la intranet.')) + '</span></span></button>';
    }
    document.addEventListener('click', function (ev) {
      var b = ev.target && ev.target.closest && ev.target.closest('[data-accion="ver-novedades"]');
      if (!b || !window.lwNovedades) return;
      if (typeof window.lwCierraCajon === 'function') window.lwCierraCajon();
      cierraDesplegable();
      setTimeout(function () { window.lwNovedades.abre(); }, 360);   // deja recogerse al cajón y sale de la campana
    }, true);   // en captura: el cajón corta la propagación de los clics de dentro
    var TITULO = 'Avisos', BAJO = 'Lo que ha pasado y lo que vence en los próximos 15 días.';
    function abre() {
      if (conCajon && typeof window.lwCajon !== 'function') {
        if (typeof toast === 'function') toast(T('El panel aún no ha cargado — prueba de nuevo en un segundo.'));
        return;
      }
      if (!conCajon && cierraDesplegable()) return;          // segundo clic en la campana: cierra
      var nota = conCajon ? window.lwCajonHtml.nota : notaSimple;
      var pinta = function (out) {
        var cuerpo;
        // una consulta caída no se lee como «nada nuevo»: la nota va antes que la lista, haya lista o no
        var notaFallo = (out && out.fallos) ? nota(T(out.cobroSinComprobar ? 'No se pudo comprobar lo cobrado: las facturas por vencer no se muestran.' : 'Alguna de las consultas de avisos falló: la lista puede estar incompleta.')) : '';
        if (!out) cuerpo = nota(T('No se pudieron cargar los avisos. Prueba a recargar la página.'));
        else if (!out.avisos.length) cuerpo = notaFallo + '<p style="margin:0;font-size:13px;color:#8A8474">' + esc(T('Nada nuevo.')) + '</p>';
        else cuerpo = notaFallo + pintaAvisos(out.avisos, aV4);
        cuerpo = filaNovedades() + cuerpo;
        // ancho de siempre (owner: «que fuese muy amplia nunca fue un problema»);
        // `desde`: el cajón crece desde la campana y se recoge hacia ella
        // el 60% de siempre en escritorio; en móvil, pantalla entera como todo
        // cajón (regla común en shell.css, 24-sep-2026 — antes se parcheaba aquí)
        if (conCajon) window.lwCajon({ titulo: T(TITULO), bajoTitulo: T(BAJO), cuerpo: cuerpo, desde: boton });
        else abreDesplegable(cuerpo);
      };
      // abrir = dar los hechos por vistos (las alertas de ≤5 días siguen contando, como en la viva)
      if (ULTIMO && ULTIMO.sinLeer) {
        aut.sb.rpc('marcar_notificaciones_leidas').then(function (r) { if (r && r.error) console.error('[v4 cabecera] marcar avisos:', r.error); });
        pintaContador(0);
      }
      if (ULTIMO) pinta(ULTIMO); else carga().then(pinta);
    }

    /* EL DESPLEGABLE (sin cajón). Forma del buscador de herramientas de nav.js
       (fijo bajo la cabecera, a la derecha); se cierra con Escape, pulsando fuera
       o con la propia campana. Por debajo del cajón de ficha del CRM (z 60) y por
       encima de la cabecera (40) y el menú (50). */
    var caja = null;
    function notaSimple(t) {
      return '<p style="margin:0;padding:8px 12px;border-radius:8px;background:#FBF3E4;color:#8A6A34;font-size:13px">' + esc(t) + '</p>';
    }
    function fuera(ev) { if (caja && !caja.contains(ev.target) && !(boton && boton.contains(ev.target))) cierraDesplegable(); }
    function tecla(ev) { if (ev.key === 'Escape' && caja) { cierraDesplegable(); if (boton) boton.focus(); } }
    function cierraDesplegable() {
      if (!caja) return false;
      caja.remove(); caja = null;
      document.removeEventListener('click', fuera, true);
      document.removeEventListener('keydown', tecla);
      if (boton) boton.setAttribute('aria-expanded', 'false');
      return true;
    }
    function abreDesplegable(cuerpo) {
      cierraDesplegable();
      caja = document.createElement('div');
      caja.setAttribute('role', 'dialog');
      caja.setAttribute('aria-label', T(TITULO));
      caja.style.cssText = 'position:fixed;top:60px;right:16px;z-index:58;width:640px;max-width:calc(100vw - 32px);box-sizing:border-box;' +
        'max-height:calc(100vh - 80px);overflow-y:auto;background:#fff;border:1px solid #E7E4DC;border-radius:12px;' +
        'box-shadow:0 18px 40px -12px rgba(30,37,34,.22),0 2px 6px rgba(30,37,34,.06);padding:16px;display:grid;gap:12px;' +
        "font-family:'Neue Kabel','Jost',sans-serif;color:#1b1c19";
      caja.innerHTML = '<div><div style="font-size:18px;font-weight:600;color:#104C4F">' + esc(T(TITULO)) + '</div>' +
        '<div style="font-size:13px;color:#75786e">' + esc(T(BAJO)) + '</div></div>' + cuerpo;
      document.body.appendChild(caja);
      document.addEventListener('click', fuera, true);
      document.addEventListener('keydown', tecla);
      if (boton) boton.setAttribute('aria-expanded', 'true');
    }

    if (boton) {
      boton.setAttribute('data-real', '');   // maqueta.js deja en paz lo cableado
      if (!conCajon) { boton.setAttribute('aria-haspopup', 'dialog'); boton.setAttribute('aria-expanded', 'false'); }
      boton.addEventListener('click', function (ev) { ev.stopPropagation(); abre(); });
    }
    carga();
  }

  /* La topbar enseñaba un nombre REAL del equipo hardcodeado por Stitch
     (venía copiado de las capturas). El usuario de sesión se pinta aquí,
     nunca en el HTML: este repo es público. */
  function pintaUsuario(aut) {
    var quien = (aut.ficha && aut.ficha.nombre) ||
                ((aut.session && aut.session.user && aut.session.user.email || '').split('@')[0]) || T('Sesión activa');
    var rol = (aut.ficha && aut.ficha.rol) || '—';
    document.querySelectorAll('[data-lw-user]').forEach(function (e) { e.textContent = quien; });
    document.querySelectorAll('[data-lw-rol]').forEach(function (e) { e.textContent = rol; });
  }

  window.LW_CABECERA = { campana: campana, pintaUsuario: pintaUsuario, pintaAvisos: pintaAvisos, tonoAviso: tonoAviso };
})();
