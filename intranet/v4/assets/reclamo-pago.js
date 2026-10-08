/* reclamo-pago.js — «Reclamar pago» en la ficha de parcela (Proyectos), 8-oct-2026
   ----------------------------------------------------------------------------
   QUÉ HACE. En el panel estrecho de la parcela (#cajon-vista-parcela de
   /intranet/v4/proyectos/) añade el botón «Reclamar pago»: un correo amistoso al
   comprador, marcado a mano, con una nota opcional. Debajo, el historial de
   recordatorios de esa parcela. NO depende de Vencimientos.

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

  var RPC_PRUEBA = 'reclamo_pago_prueba';
  var NOTA_MAX = 300;

  /* Puente al diccionario (i18n.js): nombre propio para no pisar `window.lwT`. */
  function rpT(s, h) { return window.lwT ? window.lwT(s, h) : rpSub(s, h); }
  function rpSub(s, h) { return h ? String(s).replace(/%(\w+)/g, function (m, k) { return h[k] != null ? h[k] : m; }) : s; }

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* Estado de la parcela abierta. `tok` descarta respuestas viejas: se abre la A,
     luego la B enseguida, y lo de A no puede pintarse en B. */
  var cur = { id: null, codigo: '', proyecto: '', tok: 0 };

  function sbPromesa() {
    return window.LW_AUTH ? window.LW_AUTH.then(function (a) { return a.sb; })
                          : Promise.reject(new Error('Sin sesión'));
  }
  function aviso(msg, mal) {
    if (mal && typeof toastMal === 'function') toastMal(msg);
    else if (typeof toast === 'function') toast(msg);
  }

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
  function estadoTxt(e) {
    switch (e) {
      case 'enviado': return rpT('Enviado');
      case 'pendiente': return rpT('En cola');
      case 'error': return rpT('Con error');
      case 'archivado': return rpT('Archivado');
      case 'prueba': return rpT('Prueba de envío');
      default: return e ? String(e) : '—';
    }
  }
  /* El error de una RPC → una frase. Se lee el `hint` (estable), nunca el mensaje en español. */
  function errorTxt(e, porDefecto) {
    var h = e && e.hint;
    switch (h) {
      case 'sin_permiso': return rpT('No tienes permiso para reclamar pagos de esta parcela.');
      case 'unidad_no_existe': return rpT('La parcela ya no existe. Recarga la pantalla.');
      case 'sociedad_proyecto_sin_definir': return rpT('La empresa de este proyecto no tiene sociedad definida: no se puede enviar el recordatorio.');
      case 'sin_destinatarios': return rpT('Marca al menos una persona.');
      case 'demasiados_destinatarios': return rpT('Como máximo 10 personas por envío.');
      case 'nota_invalida': return rpT('La nota admite hasta 300 caracteres de texto, sin enlaces ni direcciones de correo.');
      case 'destinatario_ajeno_a_la_parcela': return rpT('Una de las personas marcadas ya no es compradora de esta parcela: no se envía nada. Cierra este panel y ábrelo de nuevo.');
      case 'doble_clic': return rpT('Ya se envió un recordatorio a una de las personas marcadas hace unos segundos: no se repite.');
      case 'sin_identidad': return rpT('No se pudo identificar quién envía el recordatorio. Vuelve a entrar.');
      case 'sin_ficha': case 'sin_email': case 'sin_firmar': case 'sociedad_nula': case 'sociedad_discordante':
        return rpT('Una de las personas marcadas ya no puede recibir el recordatorio (%m): no se envía nada. Cierra este panel y ábrelo de nuevo.', { m: motivoTxt(h) });
      default: break;
    }
    var m = e && (e.message || e.details);
    return (porDefecto || rpT('No se pudo completar la operación')) + (m ? ': ' + m : '.');
  }
  function sinPermiso(e) { return !!e && (e.hint === 'sin_permiso' || e.code === '42501'); }
  function funcionNoExiste(e) { return !!e && (e.code === 'PGRST202' || e.code === '42883'); }

  function fechaTxt(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '—';
    return d.toLocaleString(window.lwLocale ? window.lwLocale() : 'es-ES',
      { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  /* La nota: mismas reglas que la base, para no mandar lo que va a rechazar. */
  function notaLimpia(t) { return String(t == null ? '' : t).replace(/\s+/g, ' ').trim(); }
  function notaError(t) {
    var n = notaLimpia(t);
    if (n.length > NOTA_MAX) return rpT('La nota admite hasta 300 caracteres.');
    if (/http|www\.|@/i.test(n)) return rpT('La nota no puede llevar enlaces ni direcciones de correo.');
    return null;
  }

  /* ---------- estilos propios (sin sombras, un acento: el verde lago) ---------- */
  function cssUnaVez() {
    if (document.getElementById('rp-css')) return;
    var s = document.createElement('style');
    s.id = 'rp-css';
    s.textContent =
      '.rp-btn{width:100%;padding:9px 16px;border:0;border-radius:12px;background:#104C4F;color:#fff;font:600 13px/1.2 inherit;cursor:pointer}' +
      '.rp-btn[disabled]{opacity:.55;cursor:default}' +
      '.rp-btn2{padding:8px 14px;border-radius:10px;border:1px solid #E4DCCB;background:#fff;color:#2E3437;font:600 12.5px/1.2 inherit;cursor:pointer}' +
      '.rp-btn2[disabled]{opacity:.55;cursor:default}' +
      '.rp-txt{margin:0;color:#75786e;font-size:12px;line-height:1.45}' +
      '.rp-aviso{margin:0;padding:9px 12px;border-radius:10px;background:#FBF3E4;border:1px solid #EBDCB4;color:#8A6A34;font-size:12px;line-height:1.45}' +
      '.rp-mal{margin:0;padding:9px 12px;border-radius:10px;background:#9E2F26;color:#fff;font-size:12.5px;font-weight:600;line-height:1.4}' +
      '.rp-lista{list-style:none;margin:0;padding:0;display:grid;gap:8px}' +
      '.rp-fila{padding:9px 11px;border:1px solid #E4DCCB;border-radius:10px;background:#fff}' +
      '.rp-fila-1{display:flex;justify-content:space-between;align-items:baseline;gap:10px}' +
      '.rp-quien{font-weight:600;font-size:12.5px;color:#2E3437;min-width:0;overflow-wrap:anywhere}' +
      '.rp-meta{margin-top:2px;font-size:11px;color:#75786e;line-height:1.4;overflow-wrap:anywhere}' +
      '.rp-nota{margin-top:3px;font-size:11.5px;color:#2E3437;line-height:1.4;overflow-wrap:anywhere}' +
      '.rp-pastilla{flex:0 0 auto;padding:1px 8px;border-radius:999px;font-size:10.5px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;background:#f5f4ee;color:#75786e}' +
      '.rp-e-enviado{background:#E7EFE3;color:#2F5D3A}.rp-e-error{background:#F6E1DE;color:#9E2F26}' +
      '.rp-sel{display:flex;gap:10px;align-items:flex-start;cursor:pointer}' +
      '.rp-sel input{margin-top:3px;flex:0 0 auto}' +
      '.rp-no{opacity:.75;background:#f5f4ee}' +
      '.rp-cuerpo{min-width:0;flex:1}' +
      '.rp-area{width:100%;box-sizing:border-box;min-height:84px;padding:9px 12px;border:1px solid #E4DCCB;border-radius:8px;font:500 14px/1.4 inherit;color:#2E3437;background:#fff;resize:vertical}' +
      '.rp-pie{display:flex;justify-content:space-between;gap:10px;font-size:11px;color:#75786e}' +
      '.rp-bloque-t{margin:0 0 4px;font-size:12px;font-weight:700;color:#2E3437}' +
      '.rp-gap{display:grid;gap:10px}';
    document.head.appendChild(s);
  }

  /* ---------- panel de la parcela ---------- */
  function q(sel) { return document.querySelector(sel); }
  function refs() {
    return {
      bloque: q('[data-lw="rp-bloque"]'), boton: q('[data-accion="reclamar-pago"]'),
      estado: q('[data-lw="rp-estado"]'), hist: q('[data-lw="rp-historial"]')
    };
  }
  function pintaHistorial(r, filas) {
    if (!r.hist) return;
    var t = '<h5 class="rp-bloque-t">' + esc(rpT('Recordatorios enviados')) + '</h5>';
    if (!filas.length) {
      r.hist.innerHTML = t + '<p class="rp-txt">' + esc(rpT('Aún no se ha enviado ningún recordatorio desde aquí.')) + '</p>';
      return;
    }
    r.hist.innerHTML = t + '<ul class="rp-lista">' + filas.slice(0, 20).map(function (h) {
      var cls = h.estado === 'enviado' ? ' rp-e-enviado' : (h.estado === 'error' ? ' rp-e-error' : '');
      var cuando = h.estado === 'enviado' && h.enviado_en ? h.enviado_en : h.creado_en;
      return '<li class="rp-fila" data-lw="rp-hist-fila"><div class="rp-fila-1"><span class="rp-quien">' + esc(h.nombre || '—') + '</span>' +
        '<span class="rp-pastilla' + cls + '">' + esc(estadoTxt(h.estado)) + '</span></div>' +
        '<div class="rp-meta">' + esc(fechaTxt(cuando)) + ' · ' + esc(rpT('por %s', { s: h.creado_por || '—' })) + '</div>' +
        (h.nota ? '<div class="rp-nota">' + esc(rpT('Nota: %s', { s: h.nota })) + '</div>' : '') +
        (h.estado === 'error' && h.error ? '<div class="rp-meta">' + esc(h.error) + '</div>' : '') + '</li>';
    }).join('') + '</ul>' +
      (filas.length > 20 ? '<p class="rp-txt">' + esc(rpT('Se muestran los 20 más recientes.')) + '</p>' : '');
  }

  function refresca() {
    var r = refs();
    if (!r.bloque || !cur.id) return;
    var tok = ++cur.tok, id = cur.id;
    r.bloque.classList.add('hidden');
    r.boton.hidden = true;
    r.estado.innerHTML = ''; r.hist.innerHTML = '';
    sbPromesa().then(function (sb) {
      return Promise.all([
        sb.rpc('reclamo_pago_destinatarios', { p_unidad: id }),
        sb.rpc('reclamo_pago_historial', { p_unidad: id })
      ]);
    }).then(function (res) {
      if (tok !== cur.tok) return;                      // ya hay otra parcela abierta
      var d = res[0], h = res[1];
      if (d.error) {
        if (sinPermiso(d.error)) return;                // quien no administra la empresa no ve el bloque
        r.bloque.classList.remove('hidden');
        r.estado.innerHTML = '<p class="rp-mal" role="alert" data-lw="rp-error">' +
          esc(rpT('No se pudo comprobar a quién se puede escribir: %e. Cierra la parcela y ábrela de nuevo para reintentar.', { e: d.error.message || d.error.code || '—' })) + '</p>';
        return;
      }
      var filas = d.data || [];
      if (!filas.length) return;                        // parcela sin contrato vivo: nada que reclamar
      r.bloque.classList.remove('hidden');
      var sel = filas.filter(function (f) { return f.seleccionable; });
      r.boton.hidden = !sel.length;
      if (!sel.length) {
        r.estado.innerHTML = '<p class="rp-aviso" data-lw="rp-nadie">' + esc(rpT('Ahora mismo nadie de esta parcela puede recibir el recordatorio:')) + '</p>' +
          '<ul class="rp-lista">' + filas.map(function (f) {
            return '<li class="rp-fila rp-no"><span class="rp-quien">' + esc(f.nombre || '—') + '</span><div class="rp-meta">' + esc(motivoTxt(f.motivo)) + '</div></li>';
          }).join('') + '</ul>';
      }
      if (h.error) {
        r.hist.innerHTML = '<p class="rp-mal" role="alert" data-lw="rp-hist-error">' +
          esc(rpT('No se pudo cargar el historial: %e', { e: h.error.message || h.error.code || '—' })) + '</p>';
      } else if (sel.length || (h.data || []).length) {
        pintaHistorial(r, h.data || []);
      }
    }).then(null, function (e) {
      if (tok !== cur.tok) return;
      r.bloque.classList.remove('hidden');
      r.estado.innerHTML = '<p class="rp-mal" role="alert" data-lw="rp-error">' +
        esc(rpT('No se pudo comprobar a quién se puede escribir: %e. Cierra la parcela y ábrela de nuevo para reintentar.', { e: (e && e.message) || '—' })) + '</p>';
    });
  }

  /* ---------- el diálogo ---------- */
  /* Número de contrato: reclamo_pago_destinatarios aún no lo devuelve (solo contrato_id); si la base lo añade como
     `contrato_numero`, sale solo. Mientras tanto no se muestra nada: nunca se enseña el uuid. */
  function contratoTxt(f) {
    return f.contrato_numero ? '<div class="rp-meta" data-lw="rp-contrato">' + esc(rpT('Contrato %n', { n: f.contrato_numero })) + '</div>' : '';
  }
  function filaDestinatario(f) {
    if (!f.seleccionable) {
      return '<li class="rp-fila rp-no" data-lw="rp-dest-no"><span class="rp-quien">' + esc(f.nombre || '—') + '</span>' + contratoTxt(f) +
        '<div class="rp-meta">' + esc(rpT('No se le puede escribir: %m', { m: motivoTxt(f.motivo) })) + '</div></li>';
    }
    var idioma = f.idioma ? String(f.idioma).toLowerCase() : '';
    var otroIdioma = idioma !== 'es'
      ? '<div class="rp-meta" style="color:#8A6A34" data-lw="rp-idioma">' +
        esc(idioma ? rpT('Este comprador recibirá el correo en español.') : rpT('Esta persona no tiene idioma en su ficha: recibirá el correo en español.')) + '</div>' : '';
    var ultimo = f.ultimo_reclamo_en
      ? '<div class="rp-meta" data-lw="rp-ultimo">' + esc(rpT('Último recordatorio: %f · %e', { f: fechaTxt(f.ultimo_reclamo_en), e: estadoTxt(f.ultimo_estado) })) + '</div>' : '';
    return '<li class="rp-fila"><label class="rp-sel"><input type="checkbox" data-rp-cliente="' + esc(f.client_id) + '">' +
      '<span class="rp-cuerpo"><span class="rp-quien">' + esc(f.nombre || '—') + '</span>' +
      '<div class="rp-meta">' + esc(f.email_oculto || '') + '</div>' + contratoTxt(f) + otroIdioma + ultimo + '</span></label></li>';
  }

  function abreDialogo(filas) {
    if (typeof window.lwVentana !== 'function') return aviso(rpT('El formulario aún no ha cargado — prueba de nuevo en un segundo.'), true);
    cssUnaVez();
    var porId = {};
    filas.forEach(function (f) { if (f.seleccionable) porId[f.client_id] = f; });
    var primera = filas.filter(function (f) { return f.seleccionable; })[0];
    var sociedad = primera && primera.sociedad ? primera.sociedad : '';
    var id = cur.id, codigo = cur.codigo;
    /* La ventana (#lw-editor) no existe todavía cuando se montan los campos: se busca al usarla. */
    function marco() { return document.getElementById('lw-editor'); }
    function nodo(sel) { var m = marco(); return m ? m.querySelector(sel) : null; }
    function marcados() {
      var m = marco();
      return m ? Array.prototype.map.call(m.querySelectorAll('[data-rp-cliente]:checked'), function (i) { return i.getAttribute('data-rp-cliente'); }) : [];
    }
    function notaTexto() { var t = nodo('[data-rp="nota"]'); return t ? t.value : ''; }
    function ponMsg(sel, txt, cls) {
      var m = nodo(sel); if (!m) return;
      m.className = cls || 'rp-txt'; m.textContent = txt || ''; m.hidden = !txt;
    }

    var campos = [
      { tipo: 'nota', label: rpT('Este correo es un recordatorio, no una notificación formal de mora.') },
      { tipo: 'custom', render: function (d) {
        d.innerHTML = '<div class="rp-gap" data-lw="rp-destinatarios">' +
          '<div><p class="rp-bloque-t">' + esc(rpT('A quién se envía')) + '</p>' +
          '<p class="rp-txt">' + esc(rpT('Marca a quién va el recordatorio. Cada persona recibe su propio correo.')) + '</p></div>' +
          (sociedad ? '<p class="rp-txt" data-lw="rp-sociedad">' + esc(rpT('Se envía en nombre de %s.', { s: sociedad })) + '</p>' : '') +
          '<ul class="rp-lista">' + filas.map(filaDestinatario).join('') + '</ul></div>';
      } },
      { tipo: 'custom', render: function (d) {
        d.innerHTML = '<div class="rp-gap">' +
          '<div><p class="rp-bloque-t">' + esc(rpT('Nota para el comprador (opcional)')) + '</p>' +
          '<p class="rp-txt">' + esc(rpT('Si la escribes, aparece en el correo. Si la dejas vacía, el correo es el genérico.')) + '</p></div>' +
          '<textarea class="rp-area" data-rp="nota" maxlength="' + NOTA_MAX + '" rows="3" aria-label="' + esc(rpT('Nota para el comprador (opcional)')) + '"></textarea>' +
          '<div class="rp-pie"><span>' + esc(rpT('No escribas datos de pago, cuentas ni enlaces.')) + '</span><span data-rp="cuenta">' + esc(rpT('%n de 300', { n: 0 })) + '</span></div>' +
          '<p class="rp-mal" role="alert" data-rp="nota-error" hidden></p>' +
          '<div><button type="button" class="rp-btn2" data-accion="reclamo-prueba">' + esc(rpT('Enviarme una prueba')) + '</button>' +
          '<p class="rp-txt" style="margin-top:6px">' + esc(rpT('Te llega un correo de prueba solo a ti, con este mismo texto. No se envía a ningún comprador.')) + '</p>' +
          '<p class="rp-txt" role="status" data-rp="prueba-msg" hidden></p></div></div>';
        var area = d.querySelector('[data-rp="nota"]');
        area.addEventListener('input', function () {
          d.querySelector('[data-rp="cuenta"]').textContent = rpT('%n de 300', { n: notaLimpia(area.value).length });
          ponMsg('[data-rp="nota-error"]', notaError(area.value), 'rp-mal');
        });
        d.querySelector('[data-accion="reclamo-prueba"]').addEventListener('click', function (ev) {
          ev.preventDefault();
          var b = ev.currentTarget, e = notaError(area.value);
          ponMsg('[data-rp="prueba-msg"]', '');
          if (e) return ponMsg('[data-rp="nota-error"]', e, 'rp-mal');
          b.disabled = true;
          sbPromesa().then(function (sb) {
            return sb.rpc(RPC_PRUEBA, { p_unidad: id, p_nota: notaLimpia(area.value) || null });
          }).then(function (r) {
            b.disabled = false;
            if (r.error) {
              ponMsg('[data-rp="prueba-msg"]', funcionNoExiste(r.error)
                ? rpT('El envío de pruebas todavía no está disponible en el servidor. No se ha enviado nada.')
                : errorTxt(r.error, rpT('No se mandó la prueba')), 'rp-mal');
              return;
            }
            var destino = typeof r.data === 'string' ? r.data : '—';
            ponMsg('[data-rp="prueba-msg"]', rpT('Prueba en camino a %s.', { s: destino }), 'rp-aviso');
          }).then(null, function (x) {
            b.disabled = false;
            ponMsg('[data-rp="prueba-msg"]', errorTxt(x, rpT('No se mandó la prueba')), 'rp-mal');
          });
        });
      } }
    ];

    function falla(msg) { var e = new Error(msg); e.sinPrefijo = true; return e; }

    window.lwVentana(rpT('Reclamar pago') + ' · ' + codigo, campos, rpT('Enviar recordatorio'), function () {
      var ids = marcados();
      if (!ids.length) return Promise.reject(falla(rpT('Marca al menos una persona.')));
      var nota = notaLimpia(notaTexto());
      var e = notaError(nota);
      if (e) return Promise.reject(falla(e));
      if (typeof window.lwConfirmar !== 'function') return Promise.reject(falla(rpT('El diálogo aún no ha cargado — prueba de nuevo en un segundo.')));
      var n = ids.length;
      return window.lwConfirmar({
        titulo: n === 1 ? rpT('Enviar el recordatorio a 1 persona') : rpT('Enviar el recordatorio a %n personas', { n: n }),
        cuerpo: '<p>' + esc(rpT('Parcela %p.', { p: codigo })) + (sociedad ? ' ' + esc(rpT('Se envía en nombre de %s.', { s: sociedad })) : '') + '</p>' +
          '<p>' + esc(rpT('Recibe un correo cada persona marcada:')) + '</p>' +
          '<ul>' + ids.map(function (c) { return '<li>' + esc((porId[c] && porId[c].nombre) || c) + '</li>'; }).join('') + '</ul>' +
          '<p>' + esc(nota ? rpT('Con tu nota: «%s»', { s: nota }) : rpT('Sin nota: sale el correo genérico.')) + '</p>' +
          '<p>' + esc(rpT('Es un recordatorio amistoso, no una notificación formal de mora. Una vez enviado no se puede retirar.')) + '</p>',
        confirmar: n === 1 ? rpT('Enviar a 1 persona') : rpT('Enviar a %n personas', { n: n })
      }).then(function (si) {
        if (!si) { var c = new Error(''); c.silencioso = true; throw c; }
        return sbPromesa();
      }).then(function (sb) {
        return sb.rpc('reclamo_pago_encolar', { p_unidad: id, p_clients: ids, p_nota: nota || null });
      }).then(function (r) {
        if (r.error) throw falla(errorTxt(r.error, rpT('No se pudo enviar')));
        aviso(n === 1 ? rpT('Recordatorio en cola para 1 persona. Sale en unos instantes.')
                      : rpT('Recordatorio en cola para %n personas. Sale en unos instantes.', { n: n }));
        if (cur.id === id) refresca();
        return r.data;
      });
    }, { sub: cur.proyecto, ancho: '640px', sinRecarga: true });

    var ok = document.querySelector('#lw-editor .las-ok');
    if (ok) ok.textContent = rpT('Enviado ✓');
  }

  function alPulsar(btn) {
    if (!cur.id) return;
    btn.disabled = true;
    sbPromesa().then(function (sb) {
      return sb.rpc('reclamo_pago_destinatarios', { p_unidad: cur.id });
    }).then(function (r) {
      btn.disabled = false;
      if (r.error) return aviso(errorTxt(r.error, rpT('No se pudo comprobar a quién se puede escribir')), true);
      var filas = r.data || [];
      if (!filas.some(function (f) { return f.seleccionable; })) {
        aviso(rpT('Ya no hay nadie a quien se pueda escribir en esta parcela.'), true);
        return refresca();
      }
      abreDialogo(filas);
    }).then(null, function (e) {
      btn.disabled = false;
      aviso(errorTxt(e, rpT('No se pudo comprobar a quién se puede escribir')), true);
    });
  }

  /* ---------- arranque ---------- */
  document.addEventListener('lw:parcela-abierta', function (ev) {
    var d = (ev && ev.detail) || {};
    cur.id = d.id || null; cur.codigo = d.codigo || ''; cur.proyecto = d.proyecto || '';
    cssUnaVez();
    refresca();
  });
  document.addEventListener('lw:parcela-cerrada', function () {
    cur.id = null; cur.tok++;
  });
  document.addEventListener('click', function (ev) {
    var b = ev.target.closest && ev.target.closest('[data-accion="reclamar-pago"]');
    if (b) { ev.preventDefault(); alPulsar(b); }
  });
})();
