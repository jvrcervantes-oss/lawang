/* Modo mantenimiento de ENVÍOS (owner, 23-sep-2026, urgente).
 *
 * El candado de verdad NO está aquí: está en la base (`mantenimiento`,
 * `envios_pausados()`) y en contracts/api/send_email.php, por donde sale todo
 * correo de la intranet. Esta pieza solo:
 *  · pinta una franja roja arriba de la página mientras los envíos están en pausa;
 *  · en /v4/ajustes/ (si existe #lw-mant-panel) pinta el interruptor
 *    Pausar / Reanudar, que llama a mantenimiento_envios() — solo admin, lo
 *    comprueba la base.
 */
(function () {
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function fecha(x) { if (!x) return '—'; var d = new Date(x); return isNaN(d) ? String(x) : d.toLocaleString('es-ES'); }
  function aviso(t) { if (typeof toast === 'function') toast(t); else console.log(t); }   // toast: const global de suite-comun.js, no cuelga de window

  var sb = null, estado = null;

  function franja() {
    var f = document.getElementById('lw-mant-franja');
    if (!(estado && estado.envios_pausados)) { if (f) f.remove(); return; }
    var main = document.querySelector('main');
    if (!main) return;
    if (!f) {
      f = document.createElement('div');
      f.id = 'lw-mant-franja';
      f.setAttribute('role', 'alert');
      f.className = 'mb-6 rounded-xl border border-error/40 bg-error-container px-5 py-4 flex items-start gap-3';
      main.insertBefore(f, main.firstChild);
    }
    f.innerHTML = '<span class="material-symbols-outlined text-[22px] text-error shrink-0">block</span>' +
      '<div class="flex flex-col gap-0.5"><span class="font-label-md text-label-md text-on-error-container">Envíos de correo en pausa (modo mantenimiento). No sale ningún email de la intranet.</span>' +
      (estado.motivo ? '<span class="font-body-sm text-body-sm text-on-error-container">' + esc(estado.motivo) + '</span>' : '') +
      '<span class="font-body-sm text-[12px] text-on-error-container/80">Desde ' + esc(fecha(estado.cambiado_en)) + '. Se reanuda en Ajustes.</span></div>';
  }

  function panel() {
    var p = document.getElementById('lw-mant-panel');
    if (!p) return;
    var pausa = !!(estado && estado.envios_pausados);
    p.innerHTML =
      '<div class="flex flex-col gap-1">' +
        '<span class="font-label-md text-label-md ' + (pausa ? 'text-error' : 'text-on-surface') + '">' +
          (pausa ? 'EN PAUSA: no sale ningún correo de la intranet.' : 'Activos: la intranet envía correos con normalidad.') + '</span>' +
        (estado && estado.motivo ? '<span class="font-body-sm text-body-sm text-on-surface-variant">' + esc(estado.motivo) + '</span>' : '') +
        '<span class="font-body-sm text-[12px] text-outline">Último cambio: ' + esc(fecha(estado && estado.cambiado_en)) + '</span>' +
      '</div>' +
      (pausa
        ? '<button type="button" id="lw-mant-reanudar" class="shrink-0 px-5 py-2.5 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">Reanudar envíos</button>'
        : '<div class="flex flex-col md:flex-row gap-3 md:items-center">' +
            '<input id="lw-mant-motivo" maxlength="300" placeholder="Motivo (lo verá todo el equipo)" class="w-full md:w-80 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md">' +
            '<button type="button" id="lw-mant-pausar" class="shrink-0 px-5 py-2.5 rounded-full bg-error text-on-error hover:opacity-90 font-label-md text-label-md">Pausar todos los envíos</button>' +
          '</div>');
    var bp = document.getElementById('lw-mant-pausar'), br = document.getElementById('lw-mant-reanudar');
    if (bp) bp.addEventListener('click', function () { cambia(true, (document.getElementById('lw-mant-motivo').value || '').trim(), bp); });
    if (br) br.addEventListener('click', function () {
      var pregunta = window.lwConfirmar
        ? window.lwConfirmar({ titulo: 'Reanudar los envíos', cuerpo: 'Vuelven a salir todos los correos de la intranet, y lo que quedó en cola de Comunicación sale ya. ¿Seguro que el correo funciona de nuevo?', confirmar: 'Reanudar' })
        : Promise.resolve(true);
      pregunta.then(function (si) { if (si) cambia(false, null, br); });
    });
  }

  function cambia(pausar, motivo, b) {
    b.disabled = true;
    sb.rpc('mantenimiento_envios', { p_pausar: pausar, p_motivo: motivo || (pausar ? 'Envíos pausados por administración.' : null) }).then(function (r) {
      b.disabled = false;
      if (r.error) { aviso('No se pudo cambiar: ' + (r.error.message || 'sin detalle')); return; }
      aviso(pausar ? 'Envíos en pausa: no sale ningún correo.' : 'Envíos reanudados.');
      carga();
    });
  }

  function carga() {
    return sb.from('mantenimiento').select('envios_pausados,motivo,cambiado_en').eq('id', 1).maybeSingle().then(function (r) {
      if (r.error) { console.error('[mantenimiento]', r.error); return; }
      estado = r.data || { envios_pausados: false };
      franja(); panel();
    });
  }

  function arranca() {
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      if (!aut || !aut.sb) return;
      sb = aut.sb;
      carga();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
