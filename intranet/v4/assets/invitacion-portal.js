/* invitacion-portal.js — «Invitar al portal» en la ficha de parcela (Proyectos), 15-oct-2026
   ----------------------------------------------------------------------------
   QUÉ HACE. En el panel de la parcela, debajo de «Reclamar pago», el bloque «Portal del
   cliente»: un correo personal (inglés y español en el mismo mensaje, owner 15-oct) a cada
   comprador marcado de esa parcela —copropietarios incluidos— con el enlace al portal y el
   ruego de que revise que todo está bien. Encargo: plan aprobado por el owner el 15-oct.

   LA INVITACIÓN NO CONCEDE NADA. Lleva al portal normal (/portal/) y el cliente entra con su
   correo: quién puede entrar lo decide la base (`_portal_rechazo`, la misma regla que el login
   del portal), y quien no podría entrar sale en la lista sin casilla y con su motivo. Por eso
   no hay enlace mágico (caduca en ~1 h) ni se crea ninguna cuenta.

   ES UNA CONFIGURACIÓN de correo-parcela.js (el mismo mecanismo que «Reclamar pago»). Aquí
   solo van sus frases y lo suyo: si la persona ya ha entrado alguna vez en el portal. */
(function () {
  'use strict';

  if (typeof window.lwCorreoParcela !== 'function') { console.error('invitacion-portal.js: falta correo-parcela.js antes que este fichero'); return; }
  var esc = window.lwCorreoParcela.esc;

  /* Puente al diccionario (i18n.js): nombre propio para no pisar `window.lwT`. */
  function ipT(s, h) { return window.lwT ? window.lwT(s, h) : ipSub(s, h); }
  function ipSub(s, h) { return h ? String(s).replace(/%(\w+)/g, function (m, k) { return h[k] != null ? h[k] : m; }) : s; }

  function motivoTxt(m) {
    switch (m) {
      case 'sin_ficha': return ipT('No tiene ficha de cliente');
      case 'sin_email': return ipT('Su ficha no tiene un correo válido');
      case 'correo_equipo': return ipT('Su correo es de alguien del equipo: no puede entrar al portal con él');
      case 'acceso_revocado': return ipT('Tiene el acceso al portal revocado: vuelve a dárselo desde Compradores');
      case 'correo_repetido': return ipT('Comparte correo con otra persona de esta parcela: le llega a ella');
      default: return ipT('No disponible (%m)', { m: m || '—' });
    }
  }

  function txt(k, h) {
    switch (k) {
      case 'titulo': return ipT('Invitar al portal');
      case 'enviar': return ipT('Enviar invitación');
      case 'nadie': return ipT('Ahora mismo nadie de esta parcela puede recibir la invitación:');
      case 'histTitulo': return ipT('Invitaciones enviadas');
      case 'histVacio': return ipT('Aún no se ha enviado ninguna invitación desde aquí.');
      case 'ultimo': return ipT('Última invitación: %f · %e', h);
      case 'avisoNota': return ipT('La invitación no da acceso nuevo: le lleva al portal y entra con su correo. Va en inglés y en español.');
      case 'marcaQuien': return ipT('Marca a quién invitar. Cada persona recibe su propio correo.');
      case 'confirmaUno': return ipT('Enviar la invitación a 1 persona');
      case 'confirmaVarios': return ipT('Enviar la invitación a %n personas', h);
      case 'avisoFinal': return ipT('Le pedimos que revise sus datos, su contrato y sus pagos, y que nos responda si algo no cuadra. Una vez enviada no se puede retirar.');
      case 'encoladoUno': return ipT('Invitación en cola para 1 persona. Sale en unos instantes.');
      case 'encoladoVarios': return ipT('Invitación en cola para %n personas. Sale en unos instantes.', h);
      case 'sinPermiso': return ipT('No tienes permiso para invitar al portal desde esta parcela.');
      default: return k;
    }
  }

  function errorPropio(h) {
    switch (h) {
      case 'doble_clic': return ipT('Ya se invitó a una de las personas marcadas hace unos segundos: no se repite.');
      case 'sin_identidad': return ipT('No se pudo identificar quién envía la invitación. Vuelve a entrar.');
      case 'tope_hora': return ipT('Ya se han enviado muchas invitaciones en la última hora. Espera un poco: así a todos les llega el enlace de acceso del portal.');
      case 'sin_contrato_valido': return ipT('Esta parcela no tiene a nadie a quien se pueda invitar: no se puede componer la prueba.');
      case 'sin_ficha': case 'sin_email': case 'correo_equipo': case 'acceso_revocado': case 'correo_repetido':
        return ipT('Una de las personas marcadas ya no puede recibir la invitación (%m): no se envía nada. Cierra este panel y ábrelo de nuevo.', { m: motivoTxt(h) });
      default: return null;
    }
  }

  window.lwCorreoParcela({
    p: 'ip', accion: 'invitar-portal', accionPrueba: 'invitacion-prueba',
    rpc: { destinatarios: 'invitacion_portal_destinatarios', historial: 'invitacion_portal_historial',
           encolar: 'invitacion_portal_encolar', prueba: 'invitacion_portal_prueba' },
    txt: txt, motivoTxt: motivoTxt, errorPropio: errorPropio,
    /* Lo que ayuda a decidir: si ya ha entrado alguna vez (portal_accesos por client_id) y si es copropietario. */
    filaExtra: function (f) {
      var dentro = f.ultimo_acceso
        ? ipT('Ya ha entrado al portal (última vez: %f)', { f: window.lwCorreoParcela.fecha(f.ultimo_acceso) })
        : ipT('Aún no ha entrado al portal');
      return '<div class="rp-meta" data-lw="ip-portal">' + esc(dentro) + '</div>' +
        (f.firmado === false ? '<div class="rp-meta" data-lw="ip-sin-firmar">' + esc(ipT('Su contrato aún no está firmado: lo verá como pendiente de firma.')) + '</div>' : '');
    },
    cabecera: function () { return ''; },
    confirmaExtra: function () { return ''; }
  });
})();
