/* cierre.js — modo mantenimiento de la INTRANET (owner, 23-sep-2026: «quiero
   que la intranet pueda entrar en modo mantenimiento»).

   Con la intranet cerrada solo entran admin y super_admin; el resto del equipo
   ve una pantalla de mantenimiento con el motivo. Se cierra y reabre en
   /intranet/v4/ajustes/ (RPC `mantenimiento_intranet`, solo admin).

   ⚠️ ES UNA PUERTA DE INTERFAZ, NO UN CANDADO DE DATOS. La RLS no cambia con el
   cierre: una pestaña abierta, la consola o una llamada REST directa siguen
   pudiendo escribir con los permisos de siempre. Sirve para que el equipo no
   trabaje mientras se toca algo; no para proteger nada.
   Revisión previa Seguridad+Datos, 23-sep.

   UNA SOLA PIEZA PARA LAS DOS PUERTAS. `guard.js` (todas las herramientas) y el
   hub `/intranet/` (que tiene su propio control de sesión) llaman a
   `lwCierre.puerta()`. La lógica vive aquí y no dentro de guard.js porque el hub
   no puede cargar guard.js — es la página de login — y escribirla dos veces es
   justo la divergencia que contexto/suite_lawang.md persigue (Regla 0).
   Se carga SIN defer, justo antes de guard.js, para que exista cuando la
   puerta la busque. Si una página se olvida la etiqueta, guard.js lo dice por
   consola y deja pasar: sin esta pieza no se sabe si está cerrada.

   Tres decisiones de la revisión, que no son de gusto:
   · El estado se lee con `intranet_estado()`, no de la tabla: la tabla la puede
     leer cualquier sesión, compradores del portal incluidos, y el motivo lo
     escribe un admin pensando en el equipo.
   · Si la lectura FALLA se deja pasar (null = no se sabe). Cerrar por un fallo
     de red dejaría a todo el equipo fuera por nada.
   · A quien ya está dentro no se le tapa la pantalla de golpe: se le avisa y se
     cierra a los 3 minutos, para que guarde lo que tenga a medias. Se vuelve a
     mirar al volver a la pestaña y cada 5 minutos con la pestaña visible —
     nunca en caliente cada pocos segundos: el interruptor se toca pocas veces
     al año. */
(function () {
  if (window.lwCierre) return;

  var AJUSTES = '/intranet/v4/ajustes/';
  var GRACIA_MS = 3 * 60 * 1000;
  var SONDEO_MS = 5 * 60 * 1000;
  var FUENTE = "'Neue Kabel','Jost',system-ui,sans-serif";

  function t(s) { return typeof window.lwT === 'function' ? window.lwT(s) : s; }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function esAdmin(ficha) { return !!ficha && (ficha.rol === 'admin' || ficha.rol === 'super_admin'); }

  // { cerrada, motivo } · o null si no se ha podido saber (y entonces se pasa)
  function leer(sb) {
    try {
      return sb.rpc('intranet_estado').then(function (r) {
        return (r && !r.error && r.data) ? r.data : null;
      }, function () { return null; });
    } catch (e) { return Promise.resolve(null); }
  }

  /* ---------- pantalla completa para el equipo ----------
     Cuelga de <html> y no de <body>: guard.js tiene <html> en
     `visibility:hidden` y el hub tiene <body> oculto hasta decidir. Esta capa
     se pone `visibility:visible` propia, igual que el indicador de carga de
     guard.js. */
  function pantalla(motivo, sb) {
    var viejo = document.getElementById('lw-cierre');
    if (viejo) viejo.remove();
    var c = document.createElement('div');
    c.id = 'lw-cierre';
    c.setAttribute('role', 'alertdialog');
    c.setAttribute('aria-modal', 'true');
    c.setAttribute('aria-labelledby', 'lw-cierre-tit');
    c.style.cssText = 'visibility:visible;position:fixed;inset:0;z-index:2147483646;display:flex;' +
      'align-items:center;justify-content:center;padding:24px;background:#F5F0E6;font-family:' + FUENTE;
    c.innerHTML =
      '<div style="max-width:440px;text-align:center;display:flex;flex-direction:column;align-items:center;gap:14px">' +
        '<p style="margin:0;font:600 22px/1 ' + FUENTE + ';letter-spacing:.28em;color:#104C4F">LAWANG</p>' +
        '<h1 id="lw-cierre-tit" style="margin:18px 0 0;font:700 24px/1.25 ' + FUENTE + ';color:#2E3437">' + esc(t('La intranet está en mantenimiento')) + '</h1>' +
        (motivo ? '<p style="margin:0;font-size:15px;line-height:1.5;color:#44483f">' + esc(motivo) + '</p>' : '') +
        '<p style="margin:0;font-size:13.5px;line-height:1.5;color:#75786e">' + esc(t('Vuelve a entrar en un rato. Si es urgente, habla con un administrador.')) + '</p>' +
        '<div style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center;margin-top:10px">' +
          '<button type="button" data-c="otra" style="padding:11px 20px;border-radius:999px;border:0;background:#104C4F;color:#fff;font:600 14px ' + FUENTE + ';cursor:pointer">' + esc(t('Volver a intentar')) + '</button>' +
          '<button type="button" data-c="salir" style="padding:11px 20px;border-radius:999px;border:1px solid #E4DCCB;background:#fff;color:#2E3437;font:600 14px ' + FUENTE + ';cursor:pointer">' + esc(t('Cerrar sesión')) + '</button>' +
        '</div>' +
      '</div>';
    c.querySelector('[data-c="otra"]').addEventListener('click', function () { location.reload(); });
    c.querySelector('[data-c="salir"]').addEventListener('click', function () {
      var ir = function () { location.replace('/intranet/'); };
      try { sb.auth.signOut().then(ir, ir); } catch (e) { ir(); }
    });
    // la página de debajo no se usa ni se desplaza mientras está la capa
    document.documentElement.style.overflow = 'hidden';
    document.documentElement.appendChild(c);
    var b = c.querySelector('[data-c="otra"]'); if (b) b.focus();
  }

  /* ---------- aviso fijo abajo (franja de admin y cuenta atrás) ---------- */
  function pastilla(id, html, tono) {
    var p = document.getElementById(id);
    if (!html) { if (p) p.remove(); return; }
    if (!p) {
      p = document.createElement('div');
      p.id = id;
      p.setAttribute('role', 'status');
      p.style.cssText = 'visibility:visible;position:fixed;left:50%;bottom:18px;transform:translateX(-50%);' +
        'z-index:calc(var(--z-aviso,500) - 5);max-width:min(92vw,620px);padding:10px 18px;border-radius:999px;' +
        'font:500 13px/1.4 ' + FUENTE + ';text-align:center;box-shadow:0 8px 30px rgba(27,28,25,.2);' +
        (tono === 'rojo' ? 'background:#9E2F26;color:#fff' : 'background:#1B1C19;color:#F5F0E6;border:1px solid #C89B5C');
      document.documentElement.appendChild(p);
    }
    p.innerHTML = html;
  }
  /* El aviso de cierre NACE EN MITAD DE LA PANTALLA y, a los 4 s, baja a su
     sitio (owner, 23-sep: «ponlo en rojo en mitad de la pantalla y luego lo
     mueves a la posición donde está»). Abajo solo, en una esquina de la
     vista, se leía como un aviso más y se podía no ver. `top` se anima de 50%
     a «100% menos el margen» porque los dos son longitudes que el navegador
     sabe interpolar; `bottom:auto` hace falta para que no tire en contra.
     Con «reducir movimiento» se salta la animación: el aviso sale abajo directo. */
  function aterriza(p) {
    if (!p) return;
    var reducir = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reducir) return;
    p.style.transition = 'none';
    p.style.bottom = 'auto';
    p.style.top = '50%';
    p.style.transform = 'translate(-50%,-50%) scale(1.25)';
    p.style.boxShadow = '0 22px 60px -18px rgba(158,47,38,.55),0 0 0 8px rgba(158,47,38,.13)';
    p.offsetWidth;   // fija el punto de partida antes de animar
    setTimeout(function () {
      p.style.transition = 'top .7s cubic-bezier(.22,.8,.24,1),transform .7s cubic-bezier(.22,.8,.24,1),box-shadow .7s';
      p.style.top = 'calc(100% - 18px)';
      p.style.transform = 'translate(-50%,-100%)';
      p.style.boxShadow = '0 8px 30px rgba(27,28,25,.2)';
    }, 4000);
  }
  function franjaAdmin(estado) {
    pastilla('lw-cierre-admin', (estado && estado.cerrada)
      ? esc(t('Intranet cerrada al equipo: solo entran admins.')) +
        ' <a href="' + AJUSTES + '" style="color:#fff;font-weight:600;text-decoration:underline">' + esc(t('Reabrir en Ajustes')) + '</a>'
      : null, 'rojo');
  }

  /* ---------- con la página abierta ---------- */
  var cuentaAtras = null;
  function aplica(estado, ficha, sb) {
    if (!estado) return;                                   // no se sabe: no se toca nada
    if (esAdmin(ficha)) { franjaAdmin(estado); return; }
    if (estado.cerrada) {
      if (cuentaAtras || document.getElementById('lw-cierre')) return;
      pastilla('lw-cierre-aviso', esc(t('La intranet entra en mantenimiento en 3 minutos. Guarda lo que estés haciendo.')) +
        (estado.motivo ? ' — ' + esc(estado.motivo) : ''), 'rojo');
      aterriza(document.getElementById('lw-cierre-aviso'));
      cuentaAtras = setTimeout(function () {
        cuentaAtras = null;
        pastilla('lw-cierre-aviso', null);
        pantalla(estado.motivo, sb);
      }, GRACIA_MS);
    } else if (cuentaAtras) {                              // la reabrieron a tiempo
      clearTimeout(cuentaAtras); cuentaAtras = null;
      pastilla('lw-cierre-aviso', null);
    }
  }
  function vigilar(sb, ficha) {
    var mira = function () {
      if (document.visibilityState !== 'visible') return;
      leer(sb).then(function (e) { aplica(e, ficha, sb); });
    };
    document.addEventListener('visibilitychange', mira);
    setInterval(mira, SONDEO_MS);
  }

  /* La puerta. `estado` puede venir ya pedido (guard.js lo lanza en paralelo
     a la ficha para no sumar un viaje); si no, se pide aquí.
     Devuelve true = puede seguir; false = se ha pintado la pantalla de
     mantenimiento y la página NO debe continuar. */
  function puerta(sb, ficha, estado) {
    return Promise.resolve(estado === undefined ? leer(sb) : estado).then(function (e) {
      if (e && e.cerrada && !esAdmin(ficha)) {             // ficha ilegible + cerrada = no se puede probar que sea admin
        pantalla(e.motivo, sb);
        return false;
      }
      if (esAdmin(ficha)) franjaAdmin(e);
      vigilar(sb, ficha);
      return true;
    });
  }

  window.lwCierre = { leer: leer, puerta: puerta };
})();
