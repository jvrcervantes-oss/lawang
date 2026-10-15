/* reclamo-pago.js — «Reclamar pago» en la ficha de parcela (Proyectos), 8-oct-2026
   ----------------------------------------------------------------------------
   QUÉ HACE. En el panel estrecho de la parcela (#cajon-vista-parcela de
   /intranet/v4/proyectos/) añade el botón «Reclamar pago»: un correo amistoso al
   comprador, marcado a mano, con una nota opcional. Debajo, el historial de
   recordatorios de esa parcela. NO depende de Vencimientos.

   DESDE EL 15-OCT ES SOLO UNA CONFIGURACIÓN. El mecanismo (lista, diálogo, nota,
   prueba, historial, errores por `hint`) vive en correo-parcela.js, compartido con
   «Invitar al portal» (invitacion-portal.js). Aquí quedan las frases y lo que es
   solo del recordatorio: el aviso de idioma y la sociedad en cuyo nombre se envía.

   QUIÉN DECIDE QUÉ. Todo el servidor es la barrera (encargos/20261008_lawang_reclamo_pago_parcela.md):
   · el navegador solo manda la parcela, los ids de cliente marcados y la nota;
   · el permiso (es_admin_de la empresa de la parcela), que cada persona sea
     compradora de ESA parcela, la sociedad, el tope de 10, el anti doble clic y
     la validez de la nota los comprueba la RPC `reclamo_pago_encolar`;
   · aquí no se escribe en ninguna tabla: solo `sb.rpc(...)`. Las comprobaciones
     de este fichero (nota ≤ 300, sin enlaces) son comodidad para no hacer viajar
     un texto que la base va a rechazar: la base las repite.

   CÓMO SE ENGANCHA (norma del 29-sep-2026): por `data-accion` y `data-lw`, nunca por
   un rótulo. datos.js avisa con el evento `lw:parcela-abierta` {id, codigo, proyecto}
   y `lw:parcela-cerrada`; este fichero no toca nada de datos.js más que eso.

   LA VENTANA es `window.lwVentana` (editores.js, la misma de todos los formularios
   de la v4) y la confirmación `lwConfirmar` (dialogo.js): ninguna pieza nueva.

   «ENVIARME UNA PRUEBA» llama a `RPC_PRUEBA`. Esa RPC la entrega la subtarea de
   cola y plantilla (el texto aprobado se renderiza allí); si todavía no existe en
   el servidor, el botón lo dice con todas las letras, no finge. */
(function () {
  'use strict';

  if (typeof window.lwCorreoParcela !== 'function') { console.error('reclamo-pago.js: falta correo-parcela.js antes que este fichero'); return; }
  var esc = window.lwCorreoParcela.esc;

  /* Puente al diccionario (i18n.js): nombre propio para no pisar `window.lwT`. */
  function rpT(s, h) { return window.lwT ? window.lwT(s, h) : rpSub(s, h); }
  function rpSub(s, h) { return h ? String(s).replace(/%(\w+)/g, function (m, k) { return h[k] != null ? h[k] : m; }) : s; }

  /* ---------- textos de la base → palabras ---------- */
  function motivoTxt(m) {
    switch (m) {
      case 'sin_ficha': return rpT('No tiene ficha de cliente');
      case 'sin_email': return rpT('Su ficha no tiene un correo válido');
      case 'sin_firmar': return rpT('Su contrato aún no está firmado');
      case 'sociedad_nula': return rpT('Su contrato no tiene sociedad firmante');
      case 'sociedad_discordante': return rpT('La sociedad de su contrato no coincide con la de la empresa del proyecto');
      default: return rpT('No disponible (%m)', { m: m || '—' });
    }
  }
  /* Las frases propias del recordatorio (claves: cabecera de correo-parcela.js). */
  function txt(k, h) {
    switch (k) {
      case 'titulo': return rpT('Reclamar pago');
      case 'enviar': return rpT('Enviar recordatorio');
      case 'nadie': return rpT('Ahora mismo nadie de esta parcela puede recibir el recordatorio:');
      case 'histTitulo': return rpT('Recordatorios enviados');
      case 'histVacio': return rpT('Aún no se ha enviado ningún recordatorio desde aquí.');
      case 'ultimo': return rpT('Último recordatorio: %f · %e', h);
      case 'avisoNota': return rpT('Este correo es un recordatorio, no una notificación formal de mora.');
      case 'marcaQuien': return rpT('Marca a quién va el recordatorio. Cada persona recibe su propio correo.');
      case 'confirmaUno': return rpT('Enviar el recordatorio a 1 persona');
      case 'confirmaVarios': return rpT('Enviar el recordatorio a %n personas', h);
      case 'avisoFinal': return rpT('Es un recordatorio amistoso, no una notificación formal de mora. Una vez enviado no se puede retirar.');
      case 'encoladoUno': return rpT('Recordatorio en cola para 1 persona. Sale en unos instantes.');
      case 'encoladoVarios': return rpT('Recordatorio en cola para %n personas. Sale en unos instantes.', h);
      case 'sinPermiso': return rpT('No tienes permiso para reclamar pagos de esta parcela.');
      default: return k;
    }
  }
  /* El error de una RPC con `hint` propio del recordatorio → una frase (los comunes los pone correo-parcela.js). */
  function errorPropio(h) {
    switch (h) {
      case 'sociedad_proyecto_sin_definir': return rpT('La empresa de este proyecto no tiene sociedad definida: no se puede enviar el recordatorio.');
      case 'doble_clic': return rpT('Ya se envió un recordatorio a una de las personas marcadas hace unos segundos: no se repite.');
      case 'sin_identidad': return rpT('No se pudo identificar quién envía el recordatorio. Vuelve a entrar.');
      case 'sin_ficha': case 'sin_email': case 'sin_firmar': case 'sociedad_nula': case 'sociedad_discordante':
        return rpT('Una de las personas marcadas ya no puede recibir el recordatorio (%m): no se envía nada. Cierra este panel y ábrelo de nuevo.', { m: motivoTxt(h) });
      default: return null;
    }
  }


  function sociedadDe(filas) {
    var primera = filas.filter(function (f) { return f.seleccionable; })[0];
    return primera && primera.sociedad ? primera.sociedad : '';
  }

  window.lwCorreoParcela({
    p: 'rp', accion: 'reclamar-pago', accionPrueba: 'reclamo-prueba',
    rpc: { destinatarios: 'reclamo_pago_destinatarios', historial: 'reclamo_pago_historial',
           encolar: 'reclamo_pago_encolar', prueba: 'reclamo_pago_prueba' },
    txt: txt, motivoTxt: motivoTxt, errorPropio: errorPropio,
    /* El correo sale en español a todos (en/id pendientes de Legal + nativo): se avisa a quien no tiene «es». */
    filaExtra: function (f) {
      var idioma = f.idioma ? String(f.idioma).toLowerCase() : '';
      return idioma !== 'es'
        ? '<div class="rp-meta" style="color:#8A6A34" data-lw="rp-idioma">' +
          esc(idioma ? rpT('Este comprador recibirá el correo en español.') : rpT('Esta persona no tiene idioma en su ficha: recibirá el correo en español.')) + '</div>' : '';
    },
    cabecera: function (filas) {
      var s = sociedadDe(filas);
      return s ? '<p class="rp-txt" data-lw="rp-sociedad">' + esc(rpT('Se envía en nombre de %s.', { s: s })) + '</p>' : '';
    },
    confirmaExtra: function (filas) {
      var s = sociedadDe(filas);
      return s ? rpT('Se envía en nombre de %s.', { s: s }) : '';
    }
  });
})();
