/* correo-parcela.js — núcleo de los correos que se mandan desde la ficha de parcela (Proyectos), 15-oct-2026
   ----------------------------------------------------------------------------
   QUÉ ES. «Reclamar pago» (8-oct) e «Invitar al portal» (15-oct) hacen lo mismo con otro texto:
   lista de compradores de la parcela con casilla, nota opcional, «Enviarme una prueba», cola de
   correos e historial. Ese mecanismo vive AQUÍ una sola vez (Regla 0 de contexto/suite_lawang.md:
   una copia pegada es deuda, y cada copia de esta suite acabó divergiendo). Cada correo es una
   CONFIGURACIÓN que llama a `window.lwCorreoParcela(cfg)`: reclamo-pago.js e invitacion-portal.js.

   QUIÉN DECIDE QUÉ. El servidor es la barrera: el navegador solo manda la parcela, los ids de
   cliente marcados y la nota; permiso, pertenencia, tope, anti doble clic y nota los vuelve a
   comprobar la RPC `<x>_encolar`. Aquí no se escribe en ninguna tabla: solo `sb.rpc(...)`.

   CÓMO SE ENGANCHA (norma del 29-sep-2026): por `data-accion` y `data-lw`, nunca por un rótulo.
   Cada configuración lleva su prefijo (`rp`, `ip`) y todo lo suyo se busca con él:
   data-lw="<p>-bloque|<p>-estado|<p>-historial", data-<p>-cliente, data-<p>="nota". Dos bloques en
   el mismo panel no se pisan. datos.js avisa con `lw:parcela-abierta` {id, codigo, proyecto} y
   `lw:parcela-cerrada`.

   LO QUE PONE CADA CONFIGURACIÓN (cfg):
     p, accion, accionPrueba          prefijo y data-accion del botón del panel y del de prueba
     rpc: {destinatarios, historial, encolar, prueba}
     T(s, h)                          su puente al diccionario (los literales viven en su fichero)
     txt(clave, h)                    sus frases (ver CLAVES abajo)
     motivoTxt(m)                     el porqué de quien no se puede elegir
     errorPropio(hint)                frase para los hint suyos (o null y sigue el común)
     filaExtra(f)                     HTML extra (ya escapado) bajo cada persona elegible
     cabecera(filas)                  HTML extra (ya escapado) en «A quién se envía»
     confirmaExtra(filas)             texto extra tras «Parcela X.» en la confirmación
   CLAVES de txt: titulo, enviar, nadie, histTitulo, histVacio, ultimo, avisoNota, marcaQuien,
     confirmaUno, confirmaVarios, avisoFinal, encoladoUno, encoladoVarios, sinPermiso. */
(function () {
  'use strict';

  var NOTA_MAX = 300;

  /* Puente al diccionario (i18n.js) para las frases comunes: nombre propio para no pisar `window.lwT`. */
  function cpT(s, h) { return window.lwT ? window.lwT(s, h) : cpSub(s, h); }
  function cpSub(s, h) { return h ? String(s).replace(/%(\w+)/g, function (m, k) { return h[k] != null ? h[k] : m; }) : s; }

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function sbPromesa() {
    return window.LW_AUTH ? window.LW_AUTH.then(function (a) { return a.sb; })
                          : Promise.reject(new Error('Sin sesión'));
  }
  function aviso(msg, mal) {
    if (mal && typeof toastMal === 'function') toastMal(msg);
    else if (typeof toast === 'function') toast(msg);
  }

  function estadoTxt(e) {
    switch (e) {
      case 'enviado': return cpT('Enviado');
      case 'pendiente': return cpT('En cola');
      case 'error': return cpT('Con error');
      case 'archivado': return cpT('Archivado');
      case 'prueba': return cpT('Prueba de envío');
      default: return e ? String(e) : '—';
    }
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

  /* La nota: mismas reglas que la base (public._nota_correo_limpia), para no mandar lo que va a rechazar. */
  function notaLimpia(t) { return String(t == null ? '' : t).replace(/\s+/g, ' ').trim(); }
  function notaError(t) {
    var n = notaLimpia(t);
    if (n.length > NOTA_MAX) return cpT('La nota admite hasta 300 caracteres.');
    if (/http|www\.|@/i.test(n) || /[a-z0-9-]\.[a-z]{2,}/i.test(n)) return cpT('La nota no puede llevar enlaces ni direcciones de correo.');
    if (/[0-9]{6,}/.test(n)) return cpT('La nota no puede llevar números largos (cuentas, teléfonos).');
    return null;
  }

  /* ---------- estilos propios (sin sombras, un acento: el verde lago). Comunes a los dos bloques. ---------- */
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

  window.lwCorreoParcela = function (cfg) {
    var P = cfg.p, R = cfg.rpc, X = cfg.txt;

    /* Estado de la parcela abierta. `tok` descarta respuestas viejas: se abre la A,
       luego la B enseguida, y lo de A no puede pintarse en B. */
    var cur = { id: null, codigo: '', proyecto: '', tok: 0 };

    /* El error de una RPC → una frase. Se lee el `hint` (estable), nunca el mensaje en español. */
    function errorTxt(e, porDefecto) {
      var h = e && e.hint;
      var propio = h ? cfg.errorPropio(h) : null;
      if (propio) return propio;
      switch (h) {
        case 'sin_permiso': return X('sinPermiso');
        case 'unidad_no_existe': return cpT('La parcela ya no existe. Recarga la pantalla.');
        case 'sin_destinatarios': return cpT('Marca al menos una persona.');
        case 'demasiados_destinatarios': return cpT('Como máximo 10 personas por envío.');
        case 'nota_invalida': return cpT('La nota admite hasta 300 caracteres de texto, sin enlaces, direcciones de correo ni números largos.');
        case 'tope_pruebas': return cpT('Ya te has mandado 5 pruebas en la última hora. Espera un poco.');
        case 'destinatario_ajeno_a_la_parcela': return cpT('Una de las personas marcadas ya no es compradora de esta parcela: no se envía nada. Cierra este panel y ábrelo de nuevo.');
        default: break;
      }
      var m = e && (e.message || e.details);
      return (porDefecto || cpT('No se pudo completar la operación')) + (m ? ': ' + m : '.');
    }

    /* ---------- panel de la parcela ---------- */
    function q(sel) { return document.querySelector(sel); }
    function refs() {
      return {
        bloque: q('[data-lw="' + P + '-bloque"]'), boton: q('[data-accion="' + cfg.accion + '"]'),
        estado: q('[data-lw="' + P + '-estado"]'), hist: q('[data-lw="' + P + '-historial"]')
      };
    }
    function pintaHistorial(r, filas) {
      if (!r.hist) return;
      var t = '<h5 class="rp-bloque-t">' + esc(X('histTitulo')) + '</h5>';
      if (!filas.length) {
        r.hist.innerHTML = t + '<p class="rp-txt">' + esc(X('histVacio')) + '</p>';
        return;
      }
      r.hist.innerHTML = t + '<ul class="rp-lista">' + filas.slice(0, 20).map(function (h) {
        var cls = h.estado === 'enviado' ? ' rp-e-enviado' : (h.estado === 'error' ? ' rp-e-error' : '');
        var cuando = h.estado === 'enviado' && h.enviado_en ? h.enviado_en : h.creado_en;
        return '<li class="rp-fila" data-lw="' + P + '-hist-fila"><div class="rp-fila-1"><span class="rp-quien">' + esc(h.nombre || '—') + '</span>' +
          '<span class="rp-pastilla' + cls + '">' + esc(estadoTxt(h.estado)) + '</span></div>' +
          '<div class="rp-meta">' + esc(fechaTxt(cuando)) + ' · ' + esc(cpT('por %s', { s: h.creado_por || '—' })) + '</div>' +
          (h.nota ? '<div class="rp-nota">' + esc(cpT('Nota: %s', { s: h.nota })) + '</div>' : '') +
          (h.estado === 'error' && h.error ? '<div class="rp-meta">' + esc(h.error) + '</div>' : '') + '</li>';
      }).join('') + '</ul>' +
        (filas.length > 20 ? '<p class="rp-txt">' + esc(cpT('Se muestran los 20 más recientes.')) + '</p>' : '');
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
          sb.rpc(R.destinatarios, { p_unidad: id }),
          sb.rpc(R.historial, { p_unidad: id })
        ]);
      }).then(function (res) {
        if (tok !== cur.tok) return;                      // ya hay otra parcela abierta
        var d = res[0], h = res[1];
        if (d.error) {
          if (sinPermiso(d.error)) return;                // quien no administra la empresa no ve el bloque
          r.bloque.classList.remove('hidden');
          r.estado.innerHTML = '<p class="rp-mal" role="alert" data-lw="' + P + '-error">' +
            esc(cpT('No se pudo comprobar a quién se puede escribir: %e. Cierra la parcela y ábrela de nuevo para reintentar.', { e: d.error.message || d.error.code || '—' })) + '</p>';
          return;
        }
        var filas = d.data || [];
        if (!filas.length) return;                        // parcela sin contrato vivo: nada que enviar
        r.bloque.classList.remove('hidden');
        var sel = filas.filter(function (f) { return f.seleccionable; });
        r.boton.hidden = !sel.length;
        if (!sel.length) {
          r.estado.innerHTML = '<p class="rp-aviso" data-lw="' + P + '-nadie">' + esc(X('nadie')) + '</p>' +
            '<ul class="rp-lista">' + filas.map(function (f) {
              return '<li class="rp-fila rp-no"><span class="rp-quien">' + esc(f.nombre || '—') + '</span><div class="rp-meta">' + esc(cfg.motivoTxt(f.motivo)) + '</div></li>';
            }).join('') + '</ul>';
        }
        if (h.error) {
          r.hist.innerHTML = '<p class="rp-mal" role="alert" data-lw="' + P + '-hist-error">' +
            esc(cpT('No se pudo cargar el historial: %e', { e: h.error.message || h.error.code || '—' })) + '</p>';
        } else if (sel.length || (h.data || []).length) {
          pintaHistorial(r, h.data || []);
        }
      }).then(null, function (e) {
        if (tok !== cur.tok) return;
        r.bloque.classList.remove('hidden');
        r.estado.innerHTML = '<p class="rp-mal" role="alert" data-lw="' + P + '-error">' +
          esc(cpT('No se pudo comprobar a quién se puede escribir: %e. Cierra la parcela y ábrela de nuevo para reintentar.', { e: (e && e.message) || '—' })) + '</p>';
      });
    }

    /* ---------- el diálogo ---------- */
    /* Número de contrato: si la base lo devuelve como `contrato_numero`, sale; nunca se enseña el uuid. */
    function contratoTxt(f) {
      return f.contrato_numero ? '<div class="rp-meta" data-lw="' + P + '-contrato">' + esc(cpT('Contrato %n', { n: f.contrato_numero })) + '</div>' : '';
    }
    function filaDestinatario(f) {
      if (!f.seleccionable) {
        return '<li class="rp-fila rp-no" data-lw="' + P + '-dest-no"><span class="rp-quien">' + esc(f.nombre || '—') + '</span>' + contratoTxt(f) +
          '<div class="rp-meta">' + esc(cpT('No se le puede escribir: %m', { m: cfg.motivoTxt(f.motivo) })) + '</div></li>';
      }
      var ultimo = f.ultimo_reclamo_en
        ? '<div class="rp-meta" data-lw="' + P + '-ultimo">' + esc(X('ultimo', { f: fechaTxt(f.ultimo_reclamo_en), e: estadoTxt(f.ultimo_estado) })) + '</div>' : '';
      return '<li class="rp-fila"><label class="rp-sel"><input type="checkbox" data-' + P + '-cliente="' + esc(f.client_id) + '">' +
        '<span class="rp-cuerpo"><span class="rp-quien">' + esc(f.nombre || '—') + '</span>' +
        '<div class="rp-meta">' + esc(f.email_oculto || '') + '</div>' + contratoTxt(f) + cfg.filaExtra(f) + ultimo + '</span></label></li>';
    }

    function abreDialogo(filas) {
      if (typeof window.lwVentana !== 'function') return aviso(cpT('El formulario aún no ha cargado — prueba de nuevo en un segundo.'), true);
      cssUnaVez();
      var porId = {};
      filas.forEach(function (f) { if (f.seleccionable) porId[f.client_id] = f; });
      var id = cur.id, codigo = cur.codigo;
      var NOTA = '[data-' + P + '="nota"]', CUENTA = '[data-' + P + '="cuenta"]', NOTA_ERR = '[data-' + P + '="nota-error"]',
          PRUEBA_MSG = '[data-' + P + '="prueba-msg"]';
      /* La ventana (#lw-editor) no existe todavía cuando se montan los campos: se busca al usarla. */
      function marco() { return document.getElementById('lw-editor'); }
      function nodo(sel) { var m = marco(); return m ? m.querySelector(sel) : null; }
      function marcados() {
        var m = marco();
        return m ? Array.prototype.map.call(m.querySelectorAll('[data-' + P + '-cliente]:checked'), function (i) { return i.getAttribute('data-' + P + '-cliente'); }) : [];
      }
      function notaTexto() { var t = nodo(NOTA); return t ? t.value : ''; }
      function ponMsg(sel, txt, cls) {
        var m = nodo(sel); if (!m) return;
        m.className = cls || 'rp-txt'; m.textContent = txt || ''; m.hidden = !txt;
      }

      var campos = [
        { tipo: 'nota', label: X('avisoNota') },
        { tipo: 'custom', render: function (d) {
          d.innerHTML = '<div class="rp-gap" data-lw="' + P + '-destinatarios">' +
            '<div><p class="rp-bloque-t">' + esc(cpT('A quién se envía')) + '</p>' +
            '<p class="rp-txt">' + esc(X('marcaQuien')) + '</p></div>' +
            cfg.cabecera(filas) +
            '<ul class="rp-lista">' + filas.map(filaDestinatario).join('') + '</ul></div>';
        } },
        { tipo: 'custom', render: function (d) {
          d.innerHTML = '<div class="rp-gap">' +
            '<div><p class="rp-bloque-t">' + esc(cpT('Nota para el comprador (opcional)')) + '</p>' +
            '<p class="rp-txt">' + esc(cpT('Si la escribes, aparece en el correo. Si la dejas vacía, el correo es el genérico.')) + '</p></div>' +
            '<textarea class="rp-area" data-' + P + '="nota" maxlength="' + NOTA_MAX + '" rows="3" aria-label="' + esc(cpT('Nota para el comprador (opcional)')) + '"></textarea>' +
            '<div class="rp-pie"><span>' + esc(cpT('No escribas datos de pago, cuentas ni enlaces.')) + '</span><span data-' + P + '="cuenta">' + esc(cpT('%n de 300', { n: 0 })) + '</span></div>' +
            '<p class="rp-mal" role="alert" data-' + P + '="nota-error" hidden></p>' +
            '<div><button type="button" class="rp-btn2" data-accion="' + cfg.accionPrueba + '">' + esc(cpT('Enviarme una prueba')) + '</button>' +
            '<p class="rp-txt" style="margin-top:6px">' + esc(cpT('Te llega un correo de prueba solo a ti, con este mismo texto. No se envía a ningún comprador.')) + '</p>' +
            '<p class="rp-txt" role="status" data-' + P + '="prueba-msg" hidden></p></div></div>';
          var area = d.querySelector(NOTA);
          area.addEventListener('input', function () {
            d.querySelector(CUENTA).textContent = cpT('%n de 300', { n: notaLimpia(area.value).length });
            ponMsg(NOTA_ERR, notaError(area.value), 'rp-mal');
          });
          d.querySelector('[data-accion="' + cfg.accionPrueba + '"]').addEventListener('click', function (ev) {
            ev.preventDefault();
            var b = ev.currentTarget, e = notaError(area.value);
            ponMsg(PRUEBA_MSG, '');
            if (e) return ponMsg(NOTA_ERR, e, 'rp-mal');
            b.disabled = true;
            sbPromesa().then(function (sb) {
              return sb.rpc(R.prueba, { p_unidad: id, p_nota: notaLimpia(area.value) || null });
            }).then(function (r) {
              b.disabled = false;
              if (r.error) {
                ponMsg(PRUEBA_MSG, funcionNoExiste(r.error)
                  ? cpT('El envío de pruebas todavía no está disponible en el servidor. No se ha enviado nada.')
                  : errorTxt(r.error, cpT('No se mandó la prueba')), 'rp-mal');
                return;
              }
              var destino = typeof r.data === 'string' ? r.data : '—';
              ponMsg(PRUEBA_MSG, cpT('Prueba en camino a %s.', { s: destino }), 'rp-aviso');
            }).then(null, function (x) {
              b.disabled = false;
              ponMsg(PRUEBA_MSG, errorTxt(x, cpT('No se mandó la prueba')), 'rp-mal');
            });
          });
        } }
      ];

      function falla(msg) { var e = new Error(msg); e.sinPrefijo = true; return e; }

      window.lwVentana(X('titulo') + ' · ' + codigo, campos, X('enviar'), function () {
        var ids = marcados();
        if (!ids.length) return Promise.reject(falla(cpT('Marca al menos una persona.')));
        var nota = notaLimpia(notaTexto());
        var e = notaError(nota);
        if (e) return Promise.reject(falla(e));
        if (typeof window.lwConfirmar !== 'function') return Promise.reject(falla(cpT('El diálogo aún no ha cargado — prueba de nuevo en un segundo.')));
        var n = ids.length;
        var extra = cfg.confirmaExtra(filas);
        return window.lwConfirmar({
          titulo: n === 1 ? X('confirmaUno') : X('confirmaVarios', { n: n }),
          cuerpo: '<p>' + esc(cpT('Parcela %p.', { p: codigo })) + (extra ? ' ' + esc(extra) : '') + '</p>' +
            '<p>' + esc(cpT('Recibe un correo cada persona marcada:')) + '</p>' +
            '<ul>' + ids.map(function (c) { return '<li>' + esc((porId[c] && porId[c].nombre) || c) + '</li>'; }).join('') + '</ul>' +
            '<p>' + esc(nota ? cpT('Con tu nota: «%s»', { s: nota }) : cpT('Sin nota: sale el correo genérico.')) + '</p>' +
            '<p>' + esc(X('avisoFinal')) + '</p>',
          confirmar: n === 1 ? cpT('Enviar a 1 persona') : cpT('Enviar a %n personas', { n: n })
        }).then(function (si) {
          if (!si) { var c = new Error(''); c.silencioso = true; throw c; }
          return sbPromesa();
        }).then(function (sb) {
          return sb.rpc(R.encolar, { p_unidad: id, p_clients: ids, p_nota: nota || null });
        }).then(function (r) {
          if (r.error) throw falla(errorTxt(r.error, cpT('No se pudo enviar')));
          aviso(n === 1 ? X('encoladoUno') : X('encoladoVarios', { n: n }));
          if (cur.id === id) refresca();
          return r.data;
        });
      }, { sub: cur.proyecto, ancho: '640px', sinRecarga: true });

      var ok = document.querySelector('#lw-editor .las-ok');
      if (ok) ok.textContent = cpT('Enviado ✓');
    }

    function alPulsar(btn) {
      if (!cur.id) return;
      btn.disabled = true;
      sbPromesa().then(function (sb) {
        return sb.rpc(R.destinatarios, { p_unidad: cur.id });
      }).then(function (r) {
        btn.disabled = false;
        if (r.error) return aviso(errorTxt(r.error, cpT('No se pudo comprobar a quién se puede escribir')), true);
        var filas = r.data || [];
        if (!filas.some(function (f) { return f.seleccionable; })) {
          aviso(cpT('Ya no hay nadie a quien se pueda escribir en esta parcela.'), true);
          return refresca();
        }
        abreDialogo(filas);
      }).then(null, function (e) {
        btn.disabled = false;
        aviso(errorTxt(e, cpT('No se pudo comprobar a quién se puede escribir')), true);
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
      var b = ev.target.closest && ev.target.closest('[data-accion="' + cfg.accion + '"]');
      if (b) { ev.preventDefault(); alPulsar(b); }
    });
  };

  /* Para las configuraciones: el mismo escape, sin copiarlo. */
  window.lwCorreoParcela.esc = esc;
})();
