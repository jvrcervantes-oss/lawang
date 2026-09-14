/* editores.js — v4 fase C (8-sep-2026). Los editores NATIVOS de la v4.
 *
 * Decision del owner: la v4 sustituira a la intranet, asi que crear/editar deja
 * de abrir el formulario vivo y pasa a resolverse aqui — pero SIEMPRE por las
 * MISMAS vias que las herramientas vivas (revision previa Datos+Seguridad):
 *  · soporte responde por la RPC portal_enviar_mensaje (un INSERT directo falla
 *    por RLS, y cada mensaje manda un email REAL al comprador: se confirma);
 *  · obra escribe por la RPC obra_actualizar, nunca UPDATE a pelo;
 *  · un hito de vencimientos solo se AJUSTA (UPDATE con ajustado=true — si no,
 *    el trigger sincroniza_vencimientos lo regenera y se come la edicion);
 *  · unidades.precio jamas va en un payload: lo calcula su trigger;
 *  · todo gate que este UI ensena existe ya como policy (es_admin, puede(...));
 *    aqui solo se refleja — nunca se ensancha una policy para que el editor
 *    "funcione".
 * Un fallo de RLS se ensena tal cual: significa que ese usuario no puede, y
 * disimularlo seria mentir dos veces.
 *
 * Los botones que este fichero atiende se marcan y se escuchan en DIRECTO con
 * stopPropagation: maqueta.js delega en document (burbuja) y llegaria despues;
 * asi el editor nativo gana sin tocar la capa de maqueta. */
(function () {
  'use strict';

  var seg = location.pathname.replace(/\/(index\.html)?$/, '').split('/').pop();

  /* ---------- utilidades ---------- */
  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function slugDe(n) {
    return String(n || '').toLowerCase()
      .normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  }
  function esAdmin(f) { return !!f && (f.rol === 'admin' || f.rol === 'super_admin'); }
  function puedeH(f, h) {
    if (!f) return false;
    if (f.rol === 'super_admin') return true;
    return (f.herramientas || []).indexOf(h) !== -1;
  }

  /* ---------- editor canonico de la v4: ventana o CAJON LATERAL ----------

     Una sola funcion con dos cajas (14-sep-2026, encargo del owner: «que la
     edicion no sea un pop-up sino un desplegable desde el lateral donde la
     informacion quede mejor detallada»). El recorrido de campos, la recogida de
     valores, la validacion y el tratamiento del error de RLS son los mismos en
     los dos modos — lo unico que cambia es el marco. Dos funciones habrian sido
     dos sitios donde arreglar el proximo fallo.

     `opts.lateral` ancla el panel a la derecha, a dos columnas, con hueco para
     un bloque de solo lectura arriba (`opts.encabezado`) y un subtitulo
     (`opts.sub`). Sin `opts`, la ventana centrada de siempre: los demas
     editores de la v4 no notan este cambio.

     El z-index va por encima del cajon de proyecto de /v4/proyectos/ (z-50):
     el editor se abre ENCIMA de el, no en su lugar, para no perder de vista el
     proyecto del que cuelga la parcela. */
  var FUENTE = "font-family:'Neue Kabel','Jost',sans-serif";
  function cierraModal() {
    var m = document.getElementById('lw-editor');
    if (!m) return;
    var panel = m.querySelector('[data-e="form"]');
    // Si entro deslizando, sale deslizando; si no, se quita y ya.
    if (panel && panel.getAttribute('data-lateral')) {
      panel.style.transform = 'translateX(100%)';
      m.querySelector('[data-e="fondo"]').style.opacity = '0';
      setTimeout(function () { if (m.parentNode) m.remove(); }, 260);
    } else m.remove();
  }
  function modal(titulo, campos, textoBoton, onGuardar, opts) {
    opts = opts || {};
    var lateral = !!opts.lateral;
    cierraModal();
    var w = document.createElement('div');
    w.id = 'lw-editor';
    var cajaForm = lateral
      ? 'pointer-events:auto;position:fixed;top:0;right:0;height:100%;width:min(620px,96vw);background:#fff;border-left:1px solid #c5c8bc;box-shadow:-24px 0 48px -12px rgba(0,0,0,.25);display:flex;flex-direction:column;transform:translateX(100%);transition:transform .26s ease-in-out;'
      : 'pointer-events:auto;background:#fff;border:1px solid #c5c8bc;border-radius:14px;box-shadow:0 24px 48px -12px rgba(0,0,0,.25);width:min(520px,92vw);max-height:88vh;overflow:auto;padding:26px 28px;';
    var cajaMarco = lateral
      ? 'position:fixed;inset:0;z-index:var(--z-modal,400);pointer-events:none'
      : 'position:fixed;inset:0;display:grid;place-items:center;z-index:var(--z-modal,400);pointer-events:none';
    var cajaCabecera = lateral
      ? 'display:flex;justify-content:space-between;align-items:flex-start;gap:12px;padding:22px 26px 16px;border-bottom:1px solid #E4DCCB;flex-shrink:0'
      : 'display:flex;justify-content:space-between;align-items:baseline;gap:12px;margin-bottom:16px';
    var cajaCuerpo = lateral ? 'flex:1;overflow:auto;padding:20px 26px;min-height:0' : '';
    var cajaCampos = lateral
      ? 'display:grid;grid-template-columns:1fr 1fr;gap:14px'
      : 'display:grid;gap:14px';
    var cajaPie = lateral
      ? 'display:flex;justify-content:flex-end;gap:10px;padding:16px 26px;border-top:1px solid #E4DCCB;background:#f5f4ee;flex-shrink:0'
      : 'display:flex;justify-content:flex-end;gap:10px;margin-top:20px';
    w.innerHTML =
      '<div data-e="fondo" style="position:fixed;inset:0;background:rgba(27,28,25,.45);backdrop-filter:blur(2px);z-index:calc(var(--z-modal,400) - 1);transition:opacity .26s ease-in-out' + (lateral ? ';opacity:0' : '') + '"></div>' +
      '<div role="dialog" aria-modal="true" style="' + cajaMarco + '">' +
      '<form data-e="form"' + (lateral ? ' data-lateral="1"' : '') + ' style="' + cajaForm + FUENTE + '">' +
      '<div style="' + cajaCabecera + '">' +
      '<div style="min-width:0">' +
      '<h3 style="margin:0;font:600 22px \'Neue Kabel\',sans-serif;color:#104C4F">' + esc(titulo) + '</h3>' +
      (opts.sub ? '<p style="margin:4px 0 0;font:500 12.5px inherit;color:#75786e">' + esc(opts.sub) + '</p>' : '') +
      '</div>' +
      '<button type="button" data-e="cerrar" style="border:0;background:none;font-size:20px;cursor:pointer;color:#75786e;line-height:1">×</button></div>' +
      (lateral ? '<div style="' + cajaCuerpo + '">' : '') +
      (opts.encabezado || '') +
      '<div data-e="campos" style="' + cajaCampos + '"></div>' +
      /* Rojo solido y no el rosa palido de antes (14-sep-2026, misma peticion
         del owner): a 13px sobre #ffdad6 el aviso se confundia con una nota de
         ayuda. Va dentro del modal, que ya esta centrado. */
      '<p data-e="error" role="alert" style="display:none;margin:14px 0 0;padding:12px 14px;border-radius:8px;background:#9E2F26;color:#fff;font:600 14px/1.4 inherit"></p>' +
      (lateral ? '</div>' : '') +
      '<div style="' + cajaPie + '">' +
      '<button type="button" data-e="cancelar" style="padding:10px 18px;border-radius:999px;border:1px solid #8A8474;background:none;color:#2E3437;font:600 14px inherit;cursor:pointer">Cancelar</button>' +
      '<button type="submit" data-e="guardar" style="padding:10px 20px;border-radius:999px;border:0;background:#104C4F;color:#fff;font:600 14px inherit;cursor:pointer;letter-spacing:.04em">' + esc(textoBoton || 'Guardar') + '</button>' +
      '</div></form></div>';
    document.body.appendChild(w);
    if (lateral) {
      // Dos fotogramas: con uno solo el navegador colapsa el estado inicial y
      // el panel aparece de golpe en vez de deslizarse.
      var panelN = w.querySelector('[data-e="form"]'), fondoN = w.querySelector('[data-e="fondo"]');
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { panelN.style.transform = 'translateX(0)'; fondoN.style.opacity = '1'; });
      });
    }
    var cont = w.querySelector('[data-e="campos"]');
    var estilo = 'width:100%;padding:9px 12px;border:1px solid #8A8474;border-radius:8px;font:500 14px inherit;color:#2E3437;background:#fff;box-sizing:border-box';
    campos.forEach(function (c) {
      var d = document.createElement('label');
      d.style.cssText = 'display:grid;gap:5px;font:600 11px inherit;letter-spacing:.12em;text-transform:uppercase;color:#75786e';
      // En lateral la rejilla es de dos columnas: por defecto un campo ocupa la
      // fila entera y `medio:1` lo deja a media. En ventana no hay columnas que
      // repartir, asi que la marca se ignora sola.
      if (lateral) d.style.gridColumn = c.medio ? 'span 1' : '1 / -1';
      var inner = esc(c.label) + (c.req ? ' *' : '');
      if (c.tipo === 'check') {
        d.style.cssText = 'display:flex;gap:9px;align-items:flex-start;font:500 13px inherit;color:#2E3437;text-transform:none;letter-spacing:0';
        if (lateral) d.style.gridColumn = '1 / -1';   // cssText de arriba lo borro
        d.innerHTML = '<input type="checkbox" data-k="' + esc(c.k) + '"' + (c.valor ? ' checked' : '') + ' style="margin-top:2px">' +
          '<span>' + esc(c.label) + (c.ayuda ? '<br><small style="color:#8A6A34">' + esc(c.ayuda) + '</small>' : '') + '</span>';
      } else if (c.tipo === 'select') {
        d.innerHTML = inner + '<select data-k="' + esc(c.k) + '" style="' + estilo + '">' +
          (c.opciones || []).map(function (o) {
            var vv = typeof o === 'string' ? [o, o] : o;
            return '<option value="' + esc(vv[0]) + '"' + (String(c.valor) === String(vv[0]) ? ' selected' : '') + '>' + esc(vv[1]) + '</option>';
          }).join('') + '</select>';
      } else if (c.tipo === 'nota') {
        /* Texto explicativo dentro del formulario. Sin `data-k`: no es un campo,
           no se recoge y no viaja en el payload. Hace falta para poder decir en
           el sitio lo que la herramienta viva dice ahí — la escalera de estados
           la lleva el contrato, el total lo calcula la base — en vez de dejar
           un campo bloqueado sin explicación, que solo parece un fallo. */
        d.style.cssText = 'display:block;font:400 12px/1.5 inherit;text-transform:none;letter-spacing:0;color:#8A6A34;background:#FBF3E4;border-radius:8px;padding:9px 11px;margin:-4px 0 0';
        if (lateral) d.style.gridColumn = '1 / -1';   // cssText de arriba lo borro
        d.innerHTML = esc(c.label);
      } else if (c.tipo === 'lectura') {
        // Espejo de solo lectura: se ve el valor y se entiende que no se toca
        // aquí. Tampoco lleva `data-k`, por lo mismo que 'nota'.
        d.innerHTML = inner + '<input value="' + esc(c.valor == null ? '' : c.valor) + '" readonly tabindex="-1" style="' +
          estilo + ';background:#f5f4ee;color:#75786e;cursor:not-allowed">';
      } else if (c.tipo === 'textarea') {
        d.innerHTML = inner + '<textarea data-k="' + esc(c.k) + '" rows="4" style="' + estilo + ';resize:vertical">' + esc(c.valor) + '</textarea>';
      } else if (c.tipo === 'file') {
        d.innerHTML = inner + '<input data-k="' + esc(c.k) + '" type="file" accept="' + esc(c.accept || '*/*') + '" style="' + estilo + ';padding:7px 10px">';
      } else if (c.tipo === 'multicheck') {
        // `o` es un string (valor = etiqueta, como ya usaba Usuarios) o un
        // par [valor, etiqueta] — igual que ya admite 'select' — para cuando el
        // valor que hay que guardar (un id) no es lo que se quiere leer (un
        // nombre). Proyectos lo necesita para modelos y managers.
        d.innerHTML = inner + '<div data-k="' + esc(c.k) + '" style="display:grid;grid-template-columns:1fr 1fr;gap:6px;font:500 13px inherit;text-transform:none;letter-spacing:0;color:#2E3437">' +
          (c.opciones || []).map(function (o) {
            var vv = typeof o === 'string' ? [o, o] : o;
            return '<label style="display:flex;gap:7px;align-items:center"><input type="checkbox" value="' + esc(vv[0]) + '"' +
              ((c.valor || []).indexOf(vv[0]) !== -1 ? ' checked' : '') + '>' + esc(vv[1]) + '</label>';
          }).join('') + '</div>';
      } else {
        d.innerHTML = inner + '<input data-k="' + esc(c.k) + '" type="' + (c.tipo || 'text') + '" value="' + esc(c.valor == null ? '' : c.valor) + '"' +
          (c.paso ? ' step="' + esc(c.paso) + '"' : '') + ' style="' + estilo + '">';
      }
      if (c.ayuda && c.tipo !== 'check') {
        d.innerHTML += '<small style="font:400 12px inherit;text-transform:none;letter-spacing:0;color:#8A8474">' + esc(c.ayuda) + '</small>';
      }
      cont.appendChild(d);
    });
    var muestraError = function (msg) {
      var e = w.querySelector('[data-e="error"]');
      e.textContent = msg; e.style.display = 'block';
    };
    w.querySelector('[data-e="cerrar"]').addEventListener('click', cierraModal);
    w.querySelector('[data-e="cancelar"]').addEventListener('click', cierraModal);
    w.querySelector('[data-e="fondo"]').addEventListener('click', cierraModal);
    w.querySelector('[data-e="form"]').addEventListener('submit', function (ev) {
      ev.preventDefault();
      var vals = {};
      cont.querySelectorAll('[data-k]').forEach(function (el) {
        var k = el.getAttribute('data-k');
        if (el.tagName === 'DIV') {
          vals[k] = Array.prototype.map.call(el.querySelectorAll('input:checked'), function (x) { return x.value; });
        } else if (el.type === 'checkbox') vals[k] = el.checked;
        else if (el.type === 'file') vals[k] = el.files && el.files[0] ? el.files[0] : null;
        else vals[k] = el.value.trim();
      });
      for (var i = 0; i < campos.length; i++) {
        if (campos[i].req && !vals[campos[i].k]) { muestraError('Falta «' + campos[i].label + '».'); return; }
      }
      var btn = w.querySelector('[data-e="guardar"]');
      btn.disabled = true; btn.textContent = 'Guardando…';
      Promise.resolve(onGuardar(vals)).then(function (r) {
        if (r && r.error) {
          btn.disabled = false; btn.textContent = textoBoton || 'Guardar';
          muestraError('No se pudo guardar: ' + (r.error.message || r.error) +
            (/policy|permission|row-level/i.test(String(r.error.message)) ? ' — tu usuario no tiene ese permiso; el gate es la policy, no esta pantalla.' : ''));
          return;
        }
        cierraModal();
        location.reload();
      }, function (e) {
        btn.disabled = false; btn.textContent = textoBoton || 'Guardar';
        muestraError('No se pudo guardar: ' + (e && e.message || e));
      });
    });
  }

  /* Owner, 14-sep-2026: «si da algun error el pop up ponlo en el centro y en
     rojo, que destaque que ha habido algun problema».

     El segundo argumento YA marcaba el problema: sin color es un aviso normal
     («Abriendo formulario…»), y con color es un fallo — rojo (#ba1a1a, #93000a)
     o ambar (#8A6A34, «no tienes ese permiso»). Asi que no hace falta ninguna
     lista de frases: se usa la señal que ya estaba. Cualquier llamada CON color
     sale ahora en el centro, en el rojo del estudio (#9E2F26, el mismo que la
     intranet y el portal) y dura mas — el matiz ambar se pierde a proposito: al
     usuario le da igual si no puede por permiso o porque fallo la consulta, lo
     que necesita es enterarse de que no ha pasado.

     `role=alert` en el de error y `status` en el normal, por lo mismo que en
     `suite-comun.js`: un fallo debe cortar al lector de pantalla. */
  function toast(msg, color) {
    var mal = !!color;
    var t = document.createElement('div');
    t.style.cssText = mal
      ? 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:10002;background:#9E2F26;color:#fff;' +
        'padding:18px 26px;border-radius:12px;font:600 15px/1.35 sans-serif;max-width:min(560px,88vw);' +
        'box-shadow:0 22px 60px -18px rgba(158,47,38,.55),0 0 0 6px rgba(158,47,38,.13)'
      : 'position:fixed;bottom:60px;left:50%;transform:translateX(-50%);z-index:10002;background:#104C4F;color:#fff;padding:10px 18px;border-radius:999px;font:600 13px sans-serif;max-width:80vw';
    t.setAttribute('role', mal ? 'alert' : 'status');
    t.setAttribute('aria-live', mal ? 'assertive' : 'polite');
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, mal ? 7000 : 5200);
  }

  /* Descarga de CSV en el navegador (11-sep-2026, exportes de Proyectos).
     `lwCsvAntiFormula` (contracts/assets/proyectos_csv.js) antepone una comilla
     a un valor que empieza por = + - @: mitigación estándar de CSV/formula
     injection, la misma que ya usa el import de unidades — un nombre de
     proyecto es texto libre y esto se reabre en Excel. */
  function descargaCsv(nombreArchivo, cabeceras, filas) {
    var af = (typeof lwCsvAntiFormula === 'function') ? lwCsvAntiFormula : function (s) { return s; };
    var celda = function (v) {
      var s = af(v == null ? '' : String(v));
      if (/[",\n;]/.test(s)) s = '"' + s.replace(/"/g, '""') + '"';
      return s;
    };
    var lineas = [cabeceras.map(celda).join(',')].concat(filas.map(function (f) { return f.map(celda).join(','); }));
    var blob = new Blob(['﻿' + lineas.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = nombreArchivo;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
  }

  /* ---------- captura de botones por texto, en directo ---------- */
  function textoDe(btn) {
    var c = btn.cloneNode(true);
    c.querySelectorAll('.material-symbols-outlined').forEach(function (x) { x.remove(); });
    return (c.textContent || '').replace(/\s+/g, ' ').trim();
  }
  function ata(rx, fn) {
    var botones = document.querySelectorAll('button, a');
    for (var i = 0; i < botones.length; i++) {
      var b = botones[i];
      if (b.getAttribute('data-e-nativo')) continue;
      if (rx.test(textoDe(b))) {
        b.setAttribute('data-e-nativo', '1');
        b.addEventListener('click', function (ev) { ev.preventDefault(); ev.stopPropagation(); fn(this); });
        return b;
      }
    }
    return null;
  }

  /* ---------- editores por pantalla ---------- */
  var ED = {

    modelos: function (aut) {
      var sb = aut.sb, admin = esAdmin(aut.ficha);
      var soloAdmin = function () { toast('La familia de modelos la escribe solo administración (policy es_admin) — tu sesión es de ' + ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34'); };
      ata(/^\+? ?Nuevo modelo$/i, function () {
        if (!admin) return soloAdmin();
        modal('Nuevo modelo', [
          { k: 'nombre', label: 'Nombre', req: 1 },
          { k: 'slug', label: 'Slug', ayuda: 'vacío = se genera del nombre; es la URL pública /modelo/<slug>' },
          { k: 'moneda', label: 'Moneda', tipo: 'select', opciones: ['EUR', 'IDR'], valor: 'EUR' },
          { k: 'precio', label: 'Precio de construcción', tipo: 'number', paso: '0.01', ayuda: 'se puede dejar vacío y ponerlo al completar la ficha' }
        ], 'Crear modelo', function (v) {
          return sb.from('modelos').insert({
            nombre: v.nombre, slug: v.slug || slugDe(v.nombre), moneda: v.moneda,
            precio_construccion: v.precio === '' ? null : Number(v.precio),
            activo: true, publicado: false
          });
        });
      });
      ata(/^Editar datos$/i, function () {
        if (!admin) return soloAdmin();
        var m = window.LW_V4 && window.LW_V4.modelo;
        if (!m) return toast('La ficha del modelo aún no ha cargado.', '#8A6A34');
        modal('Editar «' + m.nombre + '»', [
          { k: 'dormitorios', label: 'Dormitorios', tipo: 'number', valor: m.dormitorios },
          { k: 'banos', label: 'Baños', tipo: 'number', valor: m.banos },
          { k: 'villa_m2', label: 'Villa (m²)', tipo: 'number', paso: '0.01', valor: m.villa_m2 },
          { k: 'terraza_m2', label: 'Terraza (m²)', tipo: 'number', paso: '0.01', valor: m.terraza_m2 },
          { k: 'precio', label: 'Precio de construcción (' + (m.moneda || 'EUR') + ')', tipo: 'number', paso: '0.01', valor: m.precio_construccion },
          { k: 'descripcion', label: 'Descripción (la publica la web)', tipo: 'textarea', valor: m.descripcion },
          { k: 'publicado', label: 'Publicado en la web', tipo: 'check', valor: m.publicado, ayuda: 'al marcarlo, la web pública lo enseña con esta ficha y este precio' },
          { k: 'renders_pendientes', label: 'Renders pendientes', tipo: 'check', valor: m.renders_pendientes },
          { k: 'activo', label: 'Activo en el catálogo', tipo: 'check', valor: m.activo }
        ], 'Guardar cambios', function (v) {
          return sb.from('modelos').update({
            dormitorios: v.dormitorios === '' ? null : Number(v.dormitorios),
            banos: v.banos === '' ? null : Number(v.banos),
            villa_m2: v.villa_m2 === '' ? null : Number(v.villa_m2),
            terraza_m2: v.terraza_m2 === '' ? null : Number(v.terraza_m2),
            precio_construccion: v.precio === '' ? null : Number(v.precio),
            descripcion: v.descripcion || null,
            publicado: v.publicado, renders_pendientes: v.renders_pendientes, activo: v.activo
          }).eq('id', m.id);
        });
      });
      ata(/^Añadir documento$/i, function () {
        // subir un fichero exige el bucket de almacenamiento: es el único paso
        // de esta pantalla que sigue en la herramienta viva, dicho en voz alta
        toast('La subida de ficheros vive aún en /intranet/modelos/ (necesita el bucket). Todo lo demás de esta pantalla ya es nativo.', '#8A6A34');
        setTimeout(function () { location.href = '/intranet/modelos/'; }, 1600);
      });
    },

    proyectos: function (aut) {
      var sb = aut.sb;
      var ficha = aut.ficha;
      var esAdminP = esAdmin(ficha);
      var esSuper = !!(ficha && ficha.rol === 'super_admin');
      // Mismo criterio que PUEDE_USUARIOS en /proyectos/: admin (o super_admin,
      // que puedeH ya deja pasar siempre) CON la herramienta 'usuarios' — sin
      // ella la RLS de `usuarios` rechaza igual, así que no se ofrece el control.
      var puedeUsuarios = esAdminP && puedeH(ficha, 'usuarios');
      var proyectoObj = function () { return window.LW_V4 && window.LW_V4.proyecto; };

      // enlaces/FAQ exigen 'documentacion': gate LOCAL, ya no aborta toda la
      // pantalla — editar/borrar proyecto son otro permiso y siguen abajo.
      if (puedeH(ficha, 'documentacion')) {
        ['btn-enlace', 'btn-faq'].forEach(function (id) {
          var b = document.getElementById(id); if (b) b.classList.remove('hidden');
        });
        var proyecto = function () { var p = proyectoObj(); return p && p.nombre; };
        var be = document.getElementById('btn-enlace');
        if (be) be.addEventListener('click', function (ev) {
          ev.stopPropagation();
          var p = proyecto(); if (!p) return toast('El proyecto aún no ha cargado.', '#8A6A34');
          modal('Nuevo enlace · ' + p, [
            { k: 'titulo', label: 'Título', req: 1 },
            { k: 'url', label: 'URL', req: 1, ayuda: 'https://…' },
            { k: 'categoria', label: 'Categoría', tipo: 'select', opciones: ['comercial', 'legal', 'tecnico', 'precios'], valor: 'comercial' },
            { k: 'visible_portal', label: 'Visible para el comprador', tipo: 'check', ayuda: 'lo verán TODOS los compradores de ' + p + ' en su portal' },
            { k: 'confidencial', label: 'Confidencial (solo equipo)', tipo: 'check', valor: 1 },  // nace MARCADA: la tabla se diseño con default true y el formulario mandaba false explicito, asi que todo documento nuevo nacia no-confidencial y el 'cinturon y tirantes' del RPC no protegia nada
            { k: 'publicado_investor_deck', label: 'Publicar en el dosier de inversores', tipo: 'check', ayuda: 'PÚBLICO: lo ve cualquiera que abra el enlace del deck, sin contraseña y sin contrato' }
          ], 'Guardar enlace', function (v) {
            if (!/^https?:\/\//.test(v.url)) return { error: { message: 'la URL tiene que empezar por http:// o https://' } };
            if (v.visible_portal && !window.confirm('«' + v.titulo + '» quedará visible para TODOS los compradores de ' + p + ' en su portal. ¿Publicarlo?')) {
              return { error: { message: 'publicación al portal cancelada — desmarca la casilla o confirma' } };
            }
            // El deck es PÚBLICO y sin login, así que su confirmación es más dura que la
            // del portal: aquello lo ven compradores con contrato, esto lo ve internet.
            if (v.publicado_investor_deck && v.confidencial) {
              return { error: { message: 'un documento confidencial no puede publicarse en el dosier de inversores — desmarca una de las dos' } };
            }
            if (v.publicado_investor_deck && !window.confirm('«' + v.titulo + '» quedará descargable por CUALQUIERA que abra el dosier público de ' + p + ', sin contraseña y sin contrato.\n\nSi el enlace es de Drive, ábrelo antes en una ventana de incógnito: si no está compartido en abierto, el inversor se choca con una pantalla de permisos.\n\n¿Publicarlo?')) {
              return { error: { message: 'publicación al dosier cancelada — desmarca la casilla o confirma' } };
            }
            return sb.from('documentos_proyecto').insert({
              proyecto: p, titulo: v.titulo, url: v.url, categoria: v.categoria,
              visible_portal: v.visible_portal, confidencial: v.confidencial,
              // Confidencial MANDA sobre publicado. La misma regla vive también en el
              // RPC `investor_deck_documentos` a propósito: una casilla del navegador
              // no es un permiso.
              publicado_investor_deck: !!v.publicado_investor_deck && !v.confidencial
            });
          });
        });
        var bf = document.getElementById('btn-faq');
        if (bf) bf.addEventListener('click', function (ev) {
          ev.stopPropagation();
          var p = proyecto(); if (!p) return toast('El proyecto aún no ha cargado.', '#8A6A34');
          modal('Nueva pregunta frecuente · ' + p, [
            { k: 'titulo', label: 'Pregunta', req: 1 },
            { k: 'descripcion', label: 'Respuesta', tipo: 'textarea', req: 1 }
          ], 'Guardar pregunta', function (v) {
            // como las seis existentes: categoria faq, solo equipo
            return sb.from('documentos_proyecto').insert({
              proyecto: p, titulo: v.titulo, descripcion: v.descripcion,
              categoria: 'faq', confidencial: true, visible_portal: false
            });
          });
        });
      }

      /* Editar proyecto (11-sep-2026, sincronizando v4 con lo nuevo de
         /proyectos/): ficha (resort/parcela máster), qué se puede construir
         aquí y sales/project manager, en el MISMO modal — igual que la ficha
         única del original. Tres escrituras independientes al guardar
         (proyectos, modelos_villa, un RPC por manager que cambió); que falle
         una no deshace las otras, mismo criterio que allí. */
      ata(/^Editar proyecto$/i, function () {
        var p = proyectoObj();
        if (!p) return toast('El proyecto aún no ha cargado.', '#8A6A34');
        Promise.all([
          sb.from('modelos').select('id,nombre,precio_construccion,moneda').eq('activo', true),
          sb.from('modelos_villa').select('id,proyecto,modelo,modelo_id').eq('proyecto', p.nombre),
          sb.from('unidades').select('modelo').eq('proyecto', p.nombre),
          puedeUsuarios
            ? sb.from('usuarios').select('user_id,email,nombre,rol,proyectos_supervisados,activo')
                .in('rol', ['sales_manager', 'project_manager']).order('nombre')
            : Promise.resolve({ data: [] })
        ]).then(function (rs) {
          var catalogo = (rs[0] && rs[0].data) || [];
          var villas = (rs[1] && rs[1].data) || [];
          var unidadesModelo = (rs[2] && rs[2].data) || [];
          var managers = (rs[3] && rs[3].data) || [];
          var enUso = {};
          unidadesModelo.forEach(function (u) { if (u.modelo) enUso[u.modelo] = (enUso[u.modelo] || 0) + 1; });
          var declarados = villas.map(function (v) { return v.modelo_id; }).filter(Boolean);

          var campos = [
            { k: 'resort', label: 'Resort', valor: p.resort || '' },
            { k: 'parcela_master', label: 'Parcela máster (código)', valor: p.parcela_master || '' },
            { k: 'parcela_master_m2', label: 'Superficie bruta (m²)', tipo: 'number', valor: p.parcela_master_m2 == null ? '' : p.parcela_master_m2 },
            // Foto de portada (11-sep-2026, encargo del owner): va al bucket
            // 'documentacion' que ya usan Enlaces/FAQ — nunca una columna
            // imagen_url en `proyectos` (Regla 0, "si el cliente lo puede dar
            // de alta no vive en un fichero/campo suelto"). Opcional: dejar en
            // blanco no borra la que ya hubiera.
            { k: 'imagen', label: 'Foto de portada (opcional)', tipo: 'file', accept: 'image/*', ayuda: 'Aparece como fondo de la tarjeta y en el Expediente. Dejar en blanco mantiene la que ya hay.' }
          ];
          // Solo se ofrece a quien la policy va a dejar guardar (es_admin() en
          // `modelos_villa`) — mismo criterio que ES_ADMIN en /proyectos/.
          if (esAdminP && catalogo.length) {
            campos.push({
              k: 'modelos', tipo: 'multicheck',
              label: 'Qué se puede construir aquí (sin nada marcado, el catálogo entero)',
              opciones: catalogo.map(function (m) {
                var v = villas.find(function (x) { return x.modelo_id === m.id; });
                var usado = v && enUso[v.modelo];
                return [m.id, m.nombre + (usado ? ' · en uso, no se retira' : '')];
              }),
              valor: declarados
            });
          }
          if (puedeUsuarios && managers.length) {
            campos.push({
              k: 'managers', tipo: 'multicheck',
              label: 'Sales manager / Project manager de este proyecto',
              opciones: managers.map(function (m) {
                return [m.user_id, (m.nombre || m.email) + ' · ' + (m.rol === 'sales_manager' ? 'Sales manager' : 'Project manager') + (m.activo ? '' : ' (desactivado)')];
              }),
              valor: managers.filter(function (m) { return (m.proyectos_supervisados || []).indexOf(p.id) !== -1; })
                             .map(function (m) { return m.user_id; })
            });
          }

          modal('Editar proyecto · ' + p.nombre, campos, 'Guardar', function (v) {
            return sb.from('proyectos').update({
              resort: (v.resort || '').trim() || null,
              parcela_master: (v.parcela_master || '').trim() || null,
              parcela_master_m2: v.parcela_master_m2 === '' ? null : Number(v.parcela_master_m2)
            }).eq('id', p.id).select('id').then(function (r) {
              if (r.error) return r;
              // La RLS de `proyectos` exige es_admin() para UPDATE: un no-admin
              // no da error, da 0 filas (mismo aviso que /proyectos/ desde el
              // 12-ago). Sin este chequeo la ficha no se guarda y aun así se
              // cierra el modal como si hubiera ido bien — un fallo silencioso
              // (hallazgo de Desarrollo en la revisión de este mismo despliegue).
              if (!r.data || !r.data.length) {
                return { error: { message: 'no tienes permiso para editar la ficha del proyecto (solo admin)' } };
              }
              var trabajos = [];
              if (esAdminP && catalogo.length) {
                trabajos.push(lwDeclaraModelosEnProyecto(sb, p.nombre, v.modelos || [], {
                  catalogo: catalogo, villas: villas, enUso: new Set(Object.keys(enUso)), proyecto_id: p.id
                }).then(function (rm) {
                  if (!rm.ok) toast('La ficha sí, los modelos no: ' + rm.error, '#ba1a1a');
                  else if (rm.rechazadas.length) toast('No se retiran ' + rm.rechazadas.map(function (x) { return x.modelo; }).join(', ') + ': hay parcelas que los usan', '#8A6A34');
                }));
              }
              if (puedeUsuarios && managers.length) {
                var marcados = v.managers || [];
                managers.forEach(function (m) {
                  var teniaAntes = (m.proyectos_supervisados || []).indexOf(p.id) !== -1;
                  var marcadoAhora = marcados.indexOf(m.user_id) !== -1;
                  if (teniaAntes === marcadoAhora) return;
                  trabajos.push(sb.rpc('usuario_supervisa_proyecto', { p_user_id: m.user_id, p_proyecto_id: p.id, p_asignar: marcadoAhora })
                    .then(function (rr) { if (rr.error) toast('No se pudo actualizar el proyecto de ' + (m.nombre || m.email) + ': ' + rr.error.message, '#ba1a1a'); }));
                });
              }
              if (v.imagen) {
                var file = v.imagen;
                if (file.size > 8 * 1024 * 1024) {
                  toast('La ficha sí, la foto no: pasa de 8 MB.', '#ba1a1a');
                } else {
                  var ext = (file.name.match(/\.[a-z0-9]+$/i) || [''])[0].toLowerCase();
                  var path = 'proyectos/' + p.id + '/' + crypto.randomUUID() + ext;
                  trabajos.push(
                    sb.storage.from('documentacion').upload(path, file, { contentType: file.type || undefined }).then(function (up) {
                      if (up.error) { toast('La ficha sí, la foto no: ' + up.error.message, '#ba1a1a'); return; }
                      return sb.from('documentos_proyecto').insert({
                        proyecto: p.nombre, categoria: 'portada', titulo: 'Portada',
                        path: path, mime: file.type || null, bytes: file.size, confidencial: true
                      }).then(function (ri) {
                        if (ri.error) {
                          // fichero huérfano en el bucket sin fila: se retira,
                          // igual que hace subirDoc() en /intranet/modelos/.
                          sb.storage.from('documentacion').remove([path]);
                          toast('La ficha sí, la foto no: ' + ri.error.message, '#ba1a1a');
                        }
                      });
                    })
                  );
                }
              }
              return Promise.all(trabajos).then(function () { return r; });
            });
          });
        });
      });

      /* Borrar proyecto (11-sep-2026): botón ya solo super_admin lo ve
         (title lo avisa desde Stitch); el gate real es el RPC —
         es_super_admin() dentro de borrar_proyecto(), no esta UI. Rechaza el
         borrado solo si quedan unidades, modelos o documentos colgando. */
      ata(/^Borrar proyecto$/i, function () {
        var p = proyectoObj();
        if (!p) return toast('El proyecto aún no ha cargado.', '#8A6A34');
        if (!esSuper) return toast('Borrar un proyecto es solo para super_admin.', '#8A6A34');
        if (!window.confirm('Borrar el proyecto «' + p.nombre + '» del catálogo. Solo funciona si no le quedan unidades, modelos ni documentos colgando. ¿Seguro?')) return;
        sb.rpc('borrar_proyecto', { p_nombre: p.nombre }).then(function (r) {
          if (r.error) return toast('No se pudo borrar: ' + r.error.message, '#ba1a1a');
          toast('Proyecto borrado');
          setTimeout(function () { location.href = '/intranet/v4/proyectos/'; }, 1200);
        });
      });

      /* Nuevo proyecto (11-sep-2026): mismo alcance que altaProyecto() en
         /proyectos/ — solo el nombre. Resort/parcela máster se añaden después
         desde "Editar proyecto". Sin gate de rol: la RLS de INSERT en
         `proyectos` exige es_agente()+puede('unidades'), el mismo permiso que
         ya hace falta para ver esta página entera. */
      var bNuevoP = document.getElementById('btn-nuevo-proyecto');
      if (bNuevoP) bNuevoP.addEventListener('click', function (ev) {
        ev.stopPropagation();
        modal('Nuevo proyecto', [
          { k: 'nombre', label: 'Nombre', req: 1, ayuda: 'Con cuidado: un "Palm Field" y un "Palm Field " con espacio conviven como dos proyectos distintos.' }
        ], 'Crear proyecto', function (v) {
          var nombre = v.nombre.trim();
          if (!nombre) return { error: { message: 'el nombre no puede quedar vacío' } };
          return sb.from('proyectos').insert({ nombre: nombre }).then(function (r) {
            if (r.error && /duplicate key|proyectos_nombre_key/.test(r.error.message || '')) {
              return { error: { message: 'ya existe un proyecto con ese nombre' } };
            }
            return r;
          });
        });
      });

      /* Nueva unidad (11-sep-2026): mismo payload que guardar() en /proyectos/
         — `precio` JAMÁS se manda (lo calcula el trigger suelo+construcción),
         y `estado`/`contrato_id` tampoco: una unidad nueva no tiene contrato
         todavía, y la base ya la da de alta 'disponible' por defecto. */
      var bNuevaU = document.getElementById('btn-nueva-unidad');
      if (bNuevaU) bNuevaU.addEventListener('click', function (ev) {
        ev.stopPropagation();
        toast('Abriendo formulario…');
        Promise.all([
          sb.from('proyectos').select('nombre').eq('activo', true).order('nombre'),
          sb.from('tipos_vivienda').select('clave,etiqueta').eq('activo', true).order('etiqueta')
        ]).then(function (rs) {
          // Hallazgo de Desarrollo en la consulta de deploy: sin este chequeo,
          // un fallo de red o de RLS abría el modal en silencio con los
          // desplegables vacíos — el botón parecía "no hacer nada".
          if (rs[0].error) return toast('No se pudo abrir: ' + rs[0].error.message, '#ba1a1a');
          if (rs[1].error) return toast('No se pudo abrir: ' + rs[1].error.message, '#ba1a1a');
          var proyectos = ((rs[0] && rs[0].data) || []).map(function (p) { return p.nombre; });
          var tipos = ((rs[1] && rs[1].data) || []).map(function (t) { return [t.clave, t.etiqueta]; });
          if (!proyectos.length) return toast('No hay ningún proyecto dado de alta todavía — crea uno con «+ Nuevo proyecto» primero.', '#8A6A34');
          var actual = proyectoObj();
          modal('Nueva unidad', [
            { k: 'proyecto', label: 'Proyecto', tipo: 'select', req: 1, opciones: proyectos, valor: (actual && actual.nombre) || proyectos[0] },
            { k: 'codigo', label: 'Código', req: 1, ayuda: 'Debe coincidir con el que se escribe en el contrato: es lo que permite cruzarlos.' },
            { k: 'tipo', label: 'Tipo', tipo: 'select', opciones: tipos.length ? tipos : [['parcela', 'Parcela']], valor: 'parcela' },
            { k: 'superficie_m2', label: 'Superficie (m²)', tipo: 'number' },
            { k: 'precio_suelo', label: 'Precio de suelo', tipo: 'number' },
            { k: 'precio_construccion', label: 'Precio de construcción', tipo: 'number' },
            { k: 'moneda', label: 'Moneda', tipo: 'select', opciones: ['EUR', 'IDR'], valor: 'EUR' },
            { k: 'notas', label: 'Notas', tipo: 'textarea' }
          ], 'Crear unidad', function (v) {
            // Campos `type:'number'` nativos: el valor ya llega en punto decimal
            // (p.ej. "1200.5"), nunca con el formato europeo de coma que usa
            // parseImporte() en /proyectos/ para sus inputs de texto libre —
            // aplicar esa transformación aquí le comería el punto y lo rompería.
            var num = function (s) { var n = parseFloat(s); return isNaN(n) ? null : n; };
            return sb.from('unidades').insert({
              codigo: v.codigo.trim(), proyecto: v.proyecto,
              tipo: v.tipo, superficie_m2: num(v.superficie_m2),
              precio_suelo: num(v.precio_suelo), precio_construccion: num(v.precio_construccion),
              moneda: v.moneda, notas: v.notas.trim() || null
            });
          });
        }, function (e) {
          toast('No se pudo abrir: ' + (e && e.message || e), '#ba1a1a');
        });
      });

      /* EDITAR UNA PARCELA del parcelario del cajon (14-sep-2026, encargo del
         owner: «necesito poder editar el parcelario»). Hasta hoy la lista de
         unidades del cajon era de solo lectura: para corregir una superficie o
         un precio habia que salir de la v4 e ir a la herramienta viva.

         PARIDAD (Regla 0 bis de contexto/suite_lawang.md): este formulario
         hereda los campos y, sobre todo, LAS REGLAS del cajon de unidad de
         /intranet/proyectos/ — que es donde se aprendieron a base de fallos:
           · `precio` NUNCA viaja: lo calcula el trigger trg_unidad_precio_suma
             como suelo + construccion (28-ago-2026, un CSV dejo 143 parcelas
             con el total descuadrado de sus propias partes). Se enseña de solo
             lectura, que informa sin escribir.
           · `estado` y `contrato_id` SOLO se mandan si la parcela no esta
             vinculada a un contrato. Mandarlos siempre fue el fallo que, al
             corregirle el precio a una parcela reservada, la desvinculaba y la
             devolvia a «disponible»: esos dos campos tienen un dueño, y es el
             contrato (trigger sincroniza_unidad_contrato).
           · fase/zona de masterplan solo existen para Sumba Hills, y solo se
             mandan si el campo se pinto.
           · La RLS no da error al denegar: devuelve CERO filas. Por eso se pide
             .select('id') y se trata el vacio como falta de permiso.

         LO QUE NO HEREDA, dicho en voz alta como pide la Regla 0 bis: el alta
         en linea de «+ Nuevo proyecto…» y «+ Nuevo tipo…» (se hacen desde la
         herramienta viva o desde «+ Nueva unidad»), el bloque de escenarios de
         precio, y el boton de Borrar unidad — que es de super admin, va por la
         RPC borrar_unidad y no tiene sitio en una tarjeta de listado. */
      function editarUnidad(u) {
        var vinculada = !!u.contrato_id;
        toast('Abriendo «' + (u.codigo || 'unidad') + '»…');
        Promise.all([
          sb.from('proyectos').select('nombre').eq('activo', true).order('nombre'),
          sb.from('tipos_vivienda').select('clave,etiqueta').eq('activo', true).order('etiqueta'),
          (typeof lwCargarCatalogoModelos === 'function')
            ? lwCargarCatalogoModelos(sb) : Promise.resolve({ catalogo: [], villas: [] }),
          // Los contratos solo hacen falta si la parcela esta libre: si ya tiene
          // uno, el desplegable no se pinta y traerlos seria gasto por nada.
          vinculada ? Promise.resolve({ data: [] })
                    : sb.from('contratos').select('id,numero,comprador_nombre').order('created_at', { ascending: false })
        ]).then(function (rs) {
          // Mismo chequeo que «+ Nueva unidad»: sin esto, un fallo de red o de
          // RLS abria el modal en silencio con los desplegables vacios.
          if (rs[0].error) return toast('No se pudo abrir: ' + rs[0].error.message, '#ba1a1a');
          if (rs[1].error) return toast('No se pudo abrir: ' + rs[1].error.message, '#ba1a1a');
          var proyectos = ((rs[0] && rs[0].data) || []).map(function (p) { return p.nombre; });
          if (u.proyecto && proyectos.indexOf(u.proyecto) === -1) proyectos.unshift(u.proyecto);
          var tipos = ((rs[1] && rs[1].data) || []).map(function (t) { return [t.clave, t.etiqueta]; });
          var tieneTipo = false;
          for (var iT = 0; iT < tipos.length; iT++) { if (tipos[iT][0] === u.tipo) tieneTipo = true; }
          if (u.tipo && !tieneTipo) tipos.unshift([u.tipo, u.tipo]);
          var cat = rs[2] || { catalogo: [], villas: [] };
          var mods = (typeof lwModelosDeProyecto === 'function')
            ? lwModelosDeProyecto(u.proyecto, cat.villas, cat.catalogo) : { lista: [], declarados: false };
          var contratos = ((rs[3] && rs[3].data) || []);

          var estadosMapa = (window.LW_V4 && window.LW_V4.estados) || {
            disponible: 'Disponible', reservada: 'Reservada', bloqueada: 'Bloqueada',
            vendida: 'Vendida', cobrada: 'Cobrada', no_disponible: 'No disponible'
          };
          var estados = Object.keys(estadosMapa).map(function (k) { return [k, estadosMapa[k]]; });
          var etiq = (window.LW_V4 && window.LW_V4.estadoEtiqueta) || function (e) { return e || '—'; };
          var n0 = function (x) { return x == null ? '' : x; };
          /* Ningun importe de la suite se imprime con toLocaleString: `dinero.js`
             es la unica forma de leer Y de escribir un importe (decimales por
             moneda — las rupias no llevan). El respaldo solo actua si la pagina
             no lo cargo, y se nota a proposito. */
          var fmtM = function (x, m) {
            return (typeof lwFormatoImporte === 'function')
              ? lwFormatoImporte(x, m || 'EUR') : String(x) + ' ' + (m || 'EUR');
          };
          var totalDerivado = (Number(u.precio_suelo) || 0) + (Number(u.precio_construccion) || 0);

          var campos = [
            { k: 'codigo', label: 'Código', req: 1, valor: n0(u.codigo),
              ayuda: 'Debe coincidir con el que se escribe en el contrato: es lo que permite cruzarlos.' },
            { k: 'proyecto', label: 'Proyecto', tipo: 'select', req: 1, medio: 1, opciones: proyectos, valor: u.proyecto },
            { k: 'tipo', label: 'Tipo', tipo: 'select', medio: 1, opciones: tipos.length ? tipos : [['parcela', 'Parcela']], valor: u.tipo }
          ];
          /* Modelo de villa: el catalogo real, nunca texto libre si hay catalogo
             — por ahi entraban los modelos inventados que luego no casan con
             nada (8-sep-2026). Si el proyecto no declara ninguno se ofrece el
             catalogo entero y se dice que lo es. */
          if (mods.lista.length) {
            var opsM = [['', '— sin decidir —']].concat(mods.lista.map(function (m) {
              return [m.modelo, m.modelo + (m.precio_construccion != null ? ' · ' + m.precio_construccion + ' ' + (m.moneda || 'EUR') : '')];
            }));
            var tieneModelo = false;
            for (var iM = 0; iM < mods.lista.length; iM++) { if (mods.lista[iM].modelo === u.modelo) tieneModelo = true; }
            if (u.modelo && !tieneModelo) opsM.push([u.modelo, u.modelo + ' · fuera del catálogo']);
            campos.push({ k: 'modelo', label: 'Modelo de villa', tipo: 'select', opciones: opsM, valor: n0(u.modelo),
              ayuda: mods.declarados ? '' : 'Este proyecto no tiene modelos declarados, así que se ofrece el catálogo entero.' });
          } else {
            campos.push({ k: 'modelo', label: 'Modelo de villa', valor: n0(u.modelo), ayuda: 'Dune, Dream…' });
          }
          campos.push({ k: 'superficie_m2', label: 'Superficie (m²)', tipo: 'number', medio: 1, valor: n0(u.superficie_m2) });
          if (u.proyecto === 'Sumba Hills') {
            campos.push({ k: 'fase_masterplan', label: 'Fase (masterplan)', medio: 1, valor: n0(u.fase_masterplan), ayuda: 'I, II…' });
            campos.push({ k: 'zona_masterplan', label: 'Zona', medio: 1, valor: n0(u.zona_masterplan), ayuda: '1, 2, 3…' });
          }
          campos.push(
            { k: 'precio_m2', label: 'Precio por m²', tipo: 'number', medio: 1,
              valor: (u.precio_suelo != null && Number(u.superficie_m2)) ? Math.round(Number(u.precio_suelo) / Number(u.superficie_m2) * 100) / 100 : '',
              ayuda: 'Con la superficie, rellena el suelo solo. No se guarda: lo que se guarda es el suelo.' },
            { k: 'precio_suelo', label: 'Precio de suelo', tipo: 'number', medio: 1, valor: n0(u.precio_suelo) },
            { k: 'precio_construccion', label: 'Precio de construcción', tipo: 'number', medio: 1, valor: n0(u.precio_construccion) },
            { tipo: 'lectura', label: 'Precio total', medio: 1, valor: totalDerivado ? fmtM(totalDerivado, u.moneda) : '—' },
            { tipo: 'nota', label: 'El total es siempre suelo + construcción y lo calcula la base — ya no se puede escribir un valor distinto (28-ago-2026): un CSV trajo 143 parcelas con el total descuadrado de sus propias columnas.' },
            { k: 'moneda', label: 'Moneda', tipo: 'select', medio: 1, opciones: ['EUR', 'USD', 'AUD', 'IDR'], valor: u.moneda || 'EUR' }
          );
          if (vinculada) {
            campos.push(
              { tipo: 'lectura', label: 'Estado', medio: 1, valor: etiq(u.estado) + ' · lo lleva el contrato' },
              { tipo: 'lectura', label: 'Contrato asociado', medio: 1, valor: u.contrato_numero || 'vinculado' },
              { tipo: 'nota', label: 'Esta parcela está vinculada a un contrato, así que su estado y su contrato no se tocan desde aquí: los lleva el contrato y el dinero. Una Carta de Reserva la deja reservada; un Bloqueo de Parcela firmado, bloqueada; el primer recibí real la pasa a vendida, y el 100% cobrado a cobrada. Para soltarla, quítale la parcela al contrato o bórralo, y volverá a disponible sola.' }
            );
          } else {
            campos.push(
              { k: 'estado', label: 'Estado', tipo: 'select', medio: 1, opciones: estados, valor: u.estado || 'disponible' },
              { k: 'contrato_id', label: 'Contrato asociado', tipo: 'select', valor: '',
                opciones: [['', '— sin contrato —']].concat(contratos.map(function (c) {
                  return [c.id, (c.numero || 'sin nº') + ' — ' + (c.comprador_nombre || 'sin nombre')];
                })) }
            );
          }
          campos.push({ k: 'notas', label: 'Notas', tipo: 'textarea', valor: n0(u.notas) });

          /* El bloque de SOLO LECTURA que corona el panel. Es de solo lectura a
             proposito, igual que en la herramienta viva: el vinculo con el
             contrato lo pone el contrato al guardarse (trigger), no una persona
             desde aqui — si se pudiera cambiar en los dos sitios, en cuanto no
             coincidieran no habria forma de saber cual manda.

             «Cobrado de esta unidad» NO es el total cobrado del contrato: con un
             contrato de varias parcelas es LA PARTE de esta, ya partida por la
             base (unidad_parte_cobrada_split). Decirlo en el sitio evita que se
             sume dos veces el mismo dinero, que es un fallo que ya paso. */
          var cob = (Number(u.cobrado_suelo) || 0) + (Number(u.cobrado_obra) || 0);
          var pct = totalDerivado ? Math.min(100, Math.round(cob / totalDerivado * 100)) : null;
          var fila = function (dt, dd) {
            return '<div style="display:flex;justify-content:space-between;gap:14px;padding:5px 0;border-bottom:1px solid #efeee8">' +
              '<span style="font:600 11px inherit;letter-spacing:.1em;text-transform:uppercase;color:#75786e">' + esc(dt) + '</span>' +
              '<span style="font:600 13px inherit;color:#2E3437;text-align:right">' + dd + '</span></div>';
          };
          var bloque = function (titulo, dentro) {
            return '<section style="margin:0 0 18px;padding:14px 16px;background:#f5f4ee;border:1px solid #E4DCCB;border-radius:10px">' +
              '<h4 style="margin:0 0 8px;font:600 11px inherit;letter-spacing:.12em;text-transform:uppercase;color:#104C4F">' + esc(titulo) + '</h4>' +
              dentro + '</section>';
          };
          var encabezado = '';
          if (vinculada) {
            var dentroOp = fila('Contrato', esc(u.contrato_numero || 'vinculado') +
                  ' <span style="color:#75786e;font-weight:500">· ' + (u.contrato_firmado ? 'firmado' : 'sin firmar') + '</span>') +
              (u.comprador_nombre ? fila('Comprador', esc(u.comprador_nombre)) : '') +
              (u.contrato_creado_por ? fila('Agente', esc(
                 ((window.LW_V4 && window.LW_V4.equipoNombre) || {})[u.contrato_creado_por] || u.contrato_creado_por)) : '') +
              fila('Cobrado de esta parcela', esc(fmtM(cob, u.moneda)) +
                  (pct != null ? ' <span style="color:#75786e;font-weight:500">· ' + pct + '%</span>' : '') +
                  '<br><span style="font:500 11px inherit;color:#8A8474">su parte del contrato, no el total</span>');
            if (pct != null) {
              dentroOp += '<div style="margin-top:10px;height:6px;border-radius:999px;background:#e4e2dd;overflow:hidden">' +
                '<div style="height:100%;width:' + pct + '%;background:#3F5230"></div></div>';
            }
            encabezado += bloque('Operación', dentroOp);
          }
          if (u.precio_suelo != null || u.precio_construccion != null) {
            var descuadra = (u.precio_guardado != null && totalDerivado &&
                             Math.abs(Number(u.precio_guardado) - totalDerivado) > 0.5);
            encabezado += bloque('Desglose de precio',
              fila('Suelo', esc(u.precio_suelo != null ? fmtM(u.precio_suelo, u.moneda) : '—')) +
              fila('Construcción', esc(u.precio_construccion != null ? fmtM(u.precio_construccion, u.moneda) : '—')) +
              fila('Total', '<b>' + esc(fmtM(totalDerivado, u.moneda)) + '</b>') +
              (descuadra ? '<p style="margin:8px 0 0;font:500 12px inherit;color:#8A6A34">El total guardado (' +
                 esc(fmtM(u.precio_guardado, u.moneda)) + ') no cuadra con suelo + construcción. Manda la suma.</p>' : ''));
          }

          modal((u.codigo || 'Unidad'), campos, 'Guardar cambios', function (v) {
            var num = function (x) { var n = parseFloat(x); return isNaN(n) ? null : n; };
            var txt = function (x) { return (x || '').trim() || null; };
            var fila = {
              codigo: v.codigo.trim(), proyecto: v.proyecto, tipo: v.tipo,
              modelo: txt(v.modelo), superficie_m2: num(v.superficie_m2),
              precio_suelo: num(v.precio_suelo), precio_construccion: num(v.precio_construccion),
              moneda: v.moneda, notas: txt(v.notas)
              // `precio` no va aqui a proposito — ver la cabecera de esta funcion.
            };
            if ('fase_masterplan' in v) fila.fase_masterplan = txt(v.fase_masterplan);
            if ('zona_masterplan' in v) fila.zona_masterplan = txt(v.zona_masterplan);
            if (!vinculada) { fila.estado = v.estado; fila.contrato_id = v.contrato_id || null; }
            return sb.from('unidades').update(fila).eq('id', u.id).select('id').then(function (r) {
              if (r.error) {
                // El codigo es unico POR PROYECTO: decirlo con esas palabras evita
                // el "duplicate key value violates unique constraint".
                return /unidades_proyecto_codigo_key|duplicate key/.test(r.error.message || '')
                  ? { error: { message: 'ya hay una unidad con ese código en ese proyecto.' } } : r;
              }
              if (!r.data || !r.data.length) {
                return { error: { message: 'tu usuario no puede guardar esta parcela. La policy de unidades pide la herramienta «unidades» y que el proyecto esté entre los tuyos.' } };
              }
              return r;
            });
          }, {
            lateral: true,
            sub: (u.proyecto || 'sin proyecto') + ' · ' + etiq(u.estado),
            encabezado: encabezado
          });

          /* Precio por m² -> precio de suelo, como en la herramienta viva. Va
             aqui y no dentro de modal() porque es la unica pantalla que lo
             necesita: el modal canonico no tiene campos que se hablen entre si,
             y abrirle esa puerta a todos por un caso es mas de lo que hace
             falta. modal() ya ha pintado el DOM cuando se llega aqui. */
          var cm2 = document.querySelector('#lw-editor [data-k="precio_m2"]');
          var csup = document.querySelector('#lw-editor [data-k="superficie_m2"]');
          var csuelo = document.querySelector('#lw-editor [data-k="precio_suelo"]');
          if (cm2 && csup && csuelo) {
            var recalcula = function () {
              var m2 = parseFloat(cm2.value), sup = parseFloat(csup.value);
              if (!isNaN(m2) && !isNaN(sup) && sup > 0) csuelo.value = Math.round(m2 * sup * 100) / 100;
            };
            cm2.addEventListener('input', recalcula);
            csup.addEventListener('input', recalcula);
          }
        }, function (e) {
          toast('No se pudo abrir: ' + (e && e.message || e), '#ba1a1a');
        });
      }

      /* Delegado en el CONTENEDOR, que es estatico: datos.js reemplaza las
         tarjetas enteras en cada repintado del cajon, asi que un listener por
         tarjeta se perderia en cuanto se abre otro proyecto. stopPropagation
         para que maqueta.js (que delega en document) no lo trate ademas como un
         clic en la tarjeta. */
      var cajaU = document.getElementById('d-unidades');
      if (cajaU) cajaU.addEventListener('click', function (ev) {
        var b = ev.target && ev.target.closest && ev.target.closest('[data-lw-accion="editar-unidad"]');
        if (!b) return;
        ev.preventDefault(); ev.stopPropagation();
        var u = ((window.LW_V4 && window.LW_V4.unidades) || {})[b.getAttribute('data-uid')];
        if (!u) return toast('Esa parcela ya no esta en pantalla — vuelve a abrir el proyecto.', '#8A6A34');
        editarUnidad(u);
      });

      /* Exportar informe financiero (11-sep-2026): CSV de cartera/cobrado por
         proyecto. Consulta propia en vez de leer el estado interno de
         datos.js — mismo patrón lazy-fetch que ya usa "Editar proyecto". */
      var bExport = document.getElementById('btn-exportar');
      if (bExport) bExport.addEventListener('click', function (ev) {
        ev.stopPropagation();
        toast('Preparando el CSV…');
        Promise.all([
          sb.from('proyectos').select('nombre,resort').eq('activo', true).order('nombre'),
          sb.from('unidades').select('proyecto,estado,moneda,precio'),
          sb.rpc('facturas_equipo').select('proyecto_nombre,tipo,total,moneda,anulada')
        ]).then(function (rs) {
          // Hallazgo de Desarrollo en la consulta de deploy: sin este chequeo,
          // un fallo en cualquiera de las tres consultas generaba igual el CSV
          // con datos incompletos o a cero, sin avisar — y esto es un informe
          // financiero saliendo de la intranet.
          var fallo = rs[0].error || rs[1].error || rs[2].error;
          if (fallo) return toast('No se pudo generar el CSV: ' + fallo.message, '#ba1a1a');
          var ps = (rs[0] && rs[0].data) || [], us = (rs[1] && rs[1].data) || [], fs = (rs[2] && rs[2].data) || [];
          var porP = {};
          us.forEach(function (u) {
            var d = porP[u.proyecto || '¿?'] = porP[u.proyecto || '¿?'] || { t: 0, disp: 0, cartera: 0, fueraEur: 0 };
            d.t++;
            if (u.estado === 'disponible') d.disp++;
            if ((u.moneda || 'EUR') === 'EUR') d.cartera += Number(u.precio || 0); else d.fueraEur++;
          });
          var cobP = {};
          fs.forEach(function (f) {
            if (f.anulada || f.tipo !== 'recibi' || (f.moneda || 'EUR') !== 'EUR') return;
            var k = f.proyecto_nombre || ''; cobP[k] = (cobP[k] || 0) + Number(f.total || 0);
          });
          var filas = ps.map(function (p) {
            var d = porP[p.nombre] || { t: 0, disp: 0, cartera: 0, fueraEur: 0 };
            var cob = cobP[p.nombre] || 0;
            return [p.nombre, p.resort || '', d.t, d.disp, d.cartera.toFixed(2), cob.toFixed(2), (d.cartera - cob).toFixed(2), d.fueraEur];
          });
          descargaCsv('lawang-proyectos-' + new Date().toISOString().slice(0, 10) + '.csv',
            ['Proyecto', 'Resort', 'Unidades', 'Disponibles', 'Cartera EUR', 'Cobrado EUR', 'Pendiente EUR', 'Unidades fuera de EUR'],
            filas);
        }, function (e) {
          toast('No se pudo generar el CSV: ' + (e && e.message || e), '#ba1a1a');
        });
      });

      /* Exportar cuentas de UN proyecto (antes decía "Descargar Balance
         Financiero (PDF)" — no hay generador de PDF en la suite; prometerlo y
         entregar otra cosa es peor que llamarlo por su nombre real). */
      var bBalance = document.getElementById('btn-balance-csv');
      if (bBalance) bBalance.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var p = proyectoObj();
        if (!p) return toast('El proyecto aún no ha cargado.', '#8A6A34');
        toast('Preparando el CSV de ' + p.nombre + '…');
        // `moneda` en su propia columna (hallazgo de Administración en la
        // consulta de deploy de este mismo cambio): un proyecto con unidades
        // en EUR e IDR a la vez (Riverfront) exportaba un "Precio" desnudo,
        // que Excel puede sumar como si fuera una sola divisa.
        sb.from('unidades_estado').select('codigo,modelo,estado,precio,moneda,contrato_numero,comprador_nombre')
          .eq('proyecto', p.nombre).order('codigo').then(function (r) {
            if (r.error) return toast('No se pudo exportar: ' + r.error.message, '#ba1a1a');
            var filas = (r.data || []).map(function (u) {
              return [u.codigo, u.modelo || '', u.estado || '', u.precio != null ? u.precio : '', u.moneda || '', u.contrato_numero || '', u.comprador_nombre || ''];
            });
            descargaCsv('lawang-' + slugDe(p.nombre) + '-cuentas.csv',
              ['Código', 'Modelo', 'Estado', 'Precio', 'Moneda', 'Contrato', 'Comprador'], filas);
          });
      });

      /* Ver contratos: no hay un filtro por proyecto en /intranet/operaciones/
         (revisado antes de escribir esto) — se abre sin filtrar en vez de
         fingir uno que no existe. */
      var bVerCon = document.getElementById('btn-ver-contratos');
      if (bVerCon) bVerCon.addEventListener('click', function (ev) {
        ev.stopPropagation();
        location.href = '/intranet/operaciones/';
      });

      /* Importar CSV y las otras dos vistas (Tabla financiera / Carpetas):
         viven de verdad en /intranet/proyectos/ — la tabla ancha editable y su
         importador ya existen ahí, con vista previa antes de escribir nada.
         Reconstruir un segundo importador aquí sería duplicar sin necesidad,
         justo lo que la v4 evita en todo lo demás. */
      var bCsv = document.getElementById('btn-importar-csv');
      if (bCsv) bCsv.addEventListener('click', function (ev) {
        ev.stopPropagation();
        toast('El importador de CSV vive en Proyectos (la vista de tabla) — abriendo…');
        setTimeout(function () { location.href = '/intranet/proyectos/'; }, 900);
      });
      var bTabla = document.getElementById('btn-vista-tabla');
      if (bTabla) bTabla.addEventListener('click', function (ev) { ev.stopPropagation(); location.href = '/intranet/proyectos/'; });
      var bCarpetas = document.getElementById('btn-vista-carpetas');
      if (bCarpetas) bCarpetas.addEventListener('click', function (ev) { ev.stopPropagation(); location.href = '/intranet/proyectos/'; });
    },

    vencimientos: function (aut) {
      var sb = aut.sb;
      ata(/Registrar hito/i, function () {
        if (!puedeH(aut.ficha, 'vencimientos')) return toast('Ajustar hitos exige la herramienta Vencimientos (policy puede(\'vencimientos\')).', '#8A6A34');
        /* Un hito NUEVO no se crea aqui a proposito: nacen del calendario del
           contrato (sincroniza_vencimientos) y la tabla no tiene policy de
           INSERT. Lo que si se hace aqui es AJUSTAR: fecha, importe y nota —
           con ajustado=true, o el trigger regenera y se lo come. */
        Promise.all([
          sb.from('contrato_vencimientos').select('id,contrato_id,descripcion,pct,monto,fecha,nota').order('fecha', { ascending: true, nullsFirst: true }).limit(400),
          sb.rpc('contratos_equipo').select('id,numero')
        ]).then(function (rs) {
          if (rs[0].error) return toast('No se pudieron leer los hitos: ' + rs[0].error.message, '#93000a');
          var vs = rs[0].data || [], cs = (rs[1].data || []);
          var num = {}; cs.forEach(function (c) { num[c.id] = c.numero; });
          var ops = vs.map(function (v) {
            return [v.id, (num[v.contrato_id] || '¿?') + ' · ' + (v.descripcion || 'hito') + ' · ' + (v.fecha || 'SIN FECHA')];
          });
          if (!ops.length) return toast('No hay hitos que ajustar.', '#8A6A34');
          modal('Ajustar un hito', [
            { k: 'id', label: 'Hito', tipo: 'select', opciones: ops, req: 1 },
            { k: 'fecha', label: 'Fecha', tipo: 'date' },
            { k: 'monto', label: 'Importe (vacío = manda el %)', ayuda: 'texto libre como en la herramienta: 15.000,00' },
            { k: 'nota', label: 'Nota', tipo: 'textarea' }
          ], 'Guardar ajuste', function (v) {
            var patch = { ajustado: true };
            if (v.fecha) patch.fecha = v.fecha;
            if (v.monto !== '') patch.monto = v.monto;
            if (v.nota !== '') patch.nota = v.nota;
            return sb.from('contrato_vencimientos').update(patch).eq('id', v.id);
          });
        });
      });
    },

    soporte: function (aut) {
      var sb = aut.sb;
      ata(/^Enviar respuesta$/i, function () {
        var ta = document.querySelector('textarea');
        var hilo = window.LW_V4 && window.LW_V4.hilo;
        var quien = window.LW_V4 && window.LW_V4.hiloCliente;
        if (!hilo) return toast('El hilo aún no ha cargado.', '#8A6A34');
        var texto = ta ? ta.value.trim() : '';
        if (!texto) return toast('Escribe la respuesta primero.', '#8A6A34');
        if (!window.confirm('La respuesta se envía a ' + ((quien && quien.full_name) || 'el comprador') + ' y le llega TAMBIÉN por email real. ¿Enviar?')) return;
        sb.rpc('portal_enviar_mensaje', { p_hilo_id: hilo.id, p_texto: texto }).then(function (r) {
          if (r.error) return toast('No se pudo enviar: ' + r.error.message, '#93000a');
          location.reload();
        });
      });
    },

    obra: function (aut) {
      var sb = aut.sb;
      ata(/Registrar avance/i, function () {
        if (!puedeH(aut.ficha, 'unidades')) return toast('El avance de obra exige la herramienta Unidades (policy puede(\'unidades\')).', '#8A6A34');
        sb.from('unidades_estado').select('id,codigo,proyecto,obra_fase').order('codigo').limit(500).then(function (r) {
          if (r.error) return toast('No se pudieron leer las unidades: ' + r.error.message, '#93000a');
          var us = r.data || [];
          var ops = us.map(function (u) { return [u.id, u.codigo + ' · ' + (u.proyecto || '—') + (u.obra_fase ? ' · ' + u.obra_fase : '')]; });
          modal('Registrar avance técnico', [
            { k: 'unidad', label: 'Unidad', tipo: 'select', opciones: ops, req: 1 },
            { k: 'fase', label: 'Fase de obra', req: 1, ayuda: 'p. ej. «Estructura», «Cubierta», «Acabados»' },
            { k: 'fecha', label: 'Fecha de entrega prevista', tipo: 'date' }
          ], 'Registrar', function (v) {
            // por la RPC de la suite, nunca UPDATE a pelo (revision previa, Datos)
            return sb.rpc('obra_actualizar', { p_unidad: v.unidad, p_fase: v.fase, p_fecha: v.fecha || null });
          });
        });
      });
    },

    compradores: function (aut) {
      var sb = aut.sb;
      ata(/Alta de comprador/i, function () {
        /* Los SEIS datos que exige un alta (owner, 14-sep-2026) — y el telefono
           partido en prefijo + numero, igual que en /intranet/compradores/, que
           es lo que pidio. Cuales son NO se decide aqui: la lista vive en
           `contracts/assets/compradores.js` (`faltanDatosComprador`), que esta
           pantalla carga, porque si se escribiera tambien aqui las dos copias
           divergirian y este editor seguiria dando de alta fichas a medias.
           El `req: 1` de cada campo es lo que pinta el asterisco y da el aviso
           en el sitio; el validador compartido es el que manda. */
        modal('Alta de comprador', [
          { k: 'full_name', label: 'Nombre completo / razón social', req: 1 },
          { k: 'email', label: 'Email', tipo: 'email', req: 1 },
          { k: 'prefijo', label: 'Prefijo del teléfono', req: 1, medio: 1, ayuda: '+34, +62, +61…' },
          { k: 'telefono', label: 'Teléfono', req: 1, medio: 1 },
          { k: 'nationality', label: 'Nacionalidad', req: 1, ayuda: 'código de dos letras: ES, SG, AU…' },
          { k: 'passport_number', label: 'Pasaporte / NPWP', req: 1, ayuda: 'Es lo que se imprime en el contrato.' },
          { k: 'tipo', label: 'Tipo', tipo: 'select', opciones: [['persona', 'Persona física'], ['empresa', 'Empresa']], valor: 'persona' }
        ], 'Dar de alta', function (v) {
          if (typeof faltanDatosComprador === 'function') {
            var faltan = faltanDatosComprador(v);
            // Se devuelve con la forma de un error de Supabase: `modal()` ya
            // sabe enseñar eso en su aviso rojo, sin tocar su flujo.
            if (faltan.length) return { error: { message: 'faltan datos obligatorios — ' + faltan.join(', ') } };
          }
          /* el alta la puede hacer cualquier agente; EDITAR una ficha ya creada
             es de administracion (policy es_admin) — asimetria deliberada de la
             suite (migracion 7-ago), que este editor respeta y no "arregla" */
          return sb.from('clients').insert({
            full_name: v.full_name, email: v.email || null,
            phone: v.prefijo ? v.prefijo + ' ' + v.telefono : (v.telefono || null),
            nationality: v.nationality || null, passport_number: v.passport_number || null,
            tipo: v.tipo
          });
        });
      });
    },

    usuarios: function (aut) {
      var sb = aut.sb;
      ata(/^Modificar rol$/i, function () {
        if (!(esAdmin(aut.ficha) && puedeH(aut.ficha, 'usuarios'))) {
          return toast('Tocar roles exige administración con la herramienta Usuarios (la policy lo exige igual que este aviso).', '#8A6A34');
        }
        var u = window.LW_V4 && window.LW_V4.usuario;
        if (!u) return toast('El perfil aún no ha cargado.', '#8A6A34');
        // el catalogo de herramientas sale de las fichas reales, no de una lista a mano
        sb.from('usuarios').select('herramientas').then(function (r) {
          var todas = {};
          ((r.data) || []).forEach(function (x) { (x.herramientas || []).forEach(function (h) { todas[h] = 1; }); });
          var ops = Object.keys(todas).sort();
          modal('Permisos de ' + (u.nombre || u.email), [
            { k: 'rol', label: 'Rol', tipo: 'select', opciones: ['agente', 'admin'].concat(aut.ficha.rol === 'super_admin' ? ['super_admin'] : []), valor: u.rol },
            { k: 'activo', label: 'Activo', tipo: 'check', valor: u.activo },
            { k: 'herramientas', label: 'Herramientas', tipo: 'multicheck', opciones: ops, valor: u.herramientas || [] }
          ], 'Guardar permisos', function (v) {
            /* la proteccion real vive en la policy (super_admin intocable salvo
               super_admin, es_admin AND puede) — si esto falla por RLS, ese ES
               el mensaje, no un fallo del editor */
            return sb.from('usuarios').update({ rol: v.rol, activo: v.activo, herramientas: v.herramientas })
              .eq('email', u.email);
          });
        });
      });
    }
  };

  function arranca() {
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      var fn = ED[seg];
      /* MUDO A PROPOSITO: si el editor de UNA seccion revienta al montarse, el
         resto de la pagina (listado, barra, navegacion) tiene que seguir en pie
         — es una maqueta de exploracion y aqui un fallo de montaje deja la
         seccion sin editor, no datos a medias: no hay nada guardado que pueda
         quedar inconsistente. El error va a consola con su prefijo para poder
         reproducirlo. */
      if (fn) { try { fn(aut); } catch (e) { console.error('[v4 editores]', e); } }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
