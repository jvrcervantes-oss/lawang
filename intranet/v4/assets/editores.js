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

  /* ---------- modal canonico del editor ---------- */
  var FUENTE = "font-family:'Neue Kabel','Jost',sans-serif";
  function cierraModal() { var m = document.getElementById('lw-editor'); if (m) m.remove(); }
  function modal(titulo, campos, textoBoton, onGuardar) {
    cierraModal();
    var w = document.createElement('div');
    w.id = 'lw-editor';
    w.innerHTML =
      '<div data-e="fondo" style="position:fixed;inset:0;background:rgba(27,28,25,.45);backdrop-filter:blur(2px);z-index:10000"></div>' +
      '<div role="dialog" aria-modal="true" style="position:fixed;inset:0;display:grid;place-items:center;z-index:10001;pointer-events:none">' +
      '<form data-e="form" style="pointer-events:auto;background:#fff;border:1px solid #c5c8bc;border-radius:14px;box-shadow:0 24px 48px -12px rgba(0,0,0,.25);width:min(520px,92vw);max-height:88vh;overflow:auto;padding:26px 28px;' + FUENTE + '">' +
      '<div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px;margin-bottom:16px">' +
      '<h3 style="margin:0;font:600 22px \'The Seasons\',\'Cormorant Garamond\',serif;color:#104C4F">' + esc(titulo) + '</h3>' +
      '<button type="button" data-e="cerrar" style="border:0;background:none;font-size:20px;cursor:pointer;color:#75786e">×</button></div>' +
      '<div data-e="campos" style="display:grid;gap:14px"></div>' +
      '<p data-e="error" style="display:none;margin:14px 0 0;padding:10px 12px;border-radius:8px;background:#ffdad6;color:#93000a;font-size:13px"></p>' +
      '<div style="display:flex;justify-content:flex-end;gap:10px;margin-top:20px">' +
      '<button type="button" data-e="cancelar" style="padding:10px 18px;border-radius:999px;border:1px solid #8A8474;background:none;color:#2E3437;font:600 14px inherit;cursor:pointer">Cancelar</button>' +
      '<button type="submit" data-e="guardar" style="padding:10px 20px;border-radius:999px;border:0;background:#104C4F;color:#fff;font:600 14px inherit;cursor:pointer;letter-spacing:.04em">' + esc(textoBoton || 'Guardar') + '</button>' +
      '</div></form></div>';
    document.body.appendChild(w);
    var cont = w.querySelector('[data-e="campos"]');
    var estilo = 'width:100%;padding:9px 12px;border:1px solid #8A8474;border-radius:8px;font:500 14px inherit;color:#2E3437;background:#fff;box-sizing:border-box';
    campos.forEach(function (c) {
      var d = document.createElement('label');
      d.style.cssText = 'display:grid;gap:5px;font:600 11px inherit;letter-spacing:.12em;text-transform:uppercase;color:#75786e';
      var inner = esc(c.label) + (c.req ? ' *' : '');
      if (c.tipo === 'check') {
        d.style.cssText = 'display:flex;gap:9px;align-items:flex-start;font:500 13px inherit;color:#2E3437;text-transform:none;letter-spacing:0';
        d.innerHTML = '<input type="checkbox" data-k="' + esc(c.k) + '"' + (c.valor ? ' checked' : '') + ' style="margin-top:2px">' +
          '<span>' + esc(c.label) + (c.ayuda ? '<br><small style="color:#8A6A34">' + esc(c.ayuda) + '</small>' : '') + '</span>';
      } else if (c.tipo === 'select') {
        d.innerHTML = inner + '<select data-k="' + esc(c.k) + '" style="' + estilo + '">' +
          (c.opciones || []).map(function (o) {
            var vv = typeof o === 'string' ? [o, o] : o;
            return '<option value="' + esc(vv[0]) + '"' + (String(c.valor) === String(vv[0]) ? ' selected' : '') + '>' + esc(vv[1]) + '</option>';
          }).join('') + '</select>';
      } else if (c.tipo === 'textarea') {
        d.innerHTML = inner + '<textarea data-k="' + esc(c.k) + '" rows="4" style="' + estilo + ';resize:vertical">' + esc(c.valor) + '</textarea>';
      } else if (c.tipo === 'multicheck') {
        d.innerHTML = inner + '<div data-k="' + esc(c.k) + '" style="display:grid;grid-template-columns:1fr 1fr;gap:6px;font:500 13px inherit;text-transform:none;letter-spacing:0;color:#2E3437">' +
          (c.opciones || []).map(function (o) {
            return '<label style="display:flex;gap:7px;align-items:center"><input type="checkbox" value="' + esc(o) + '"' +
              ((c.valor || []).indexOf(o) !== -1 ? ' checked' : '') + '>' + esc(o) + '</label>';
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

  function toast(msg, color) {
    var t = document.createElement('div');
    t.style.cssText = 'position:fixed;bottom:60px;left:50%;transform:translateX(-50%);z-index:10002;background:' + (color || '#104C4F') + ';color:#fff;padding:10px 18px;border-radius:999px;font:600 13px sans-serif;max-width:80vw';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 5200);
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
      if (!puedeH(aut.ficha, 'documentacion')) return;   // sin la herramienta, sin botones: mismo gate que la policy
      ['btn-enlace', 'btn-faq'].forEach(function (id) {
        var b = document.getElementById(id); if (b) b.classList.remove('hidden');
      });
      var proyecto = function () { return window.LW_V4 && window.LW_V4.proyecto && window.LW_V4.proyecto.nombre; };
      var be = document.getElementById('btn-enlace');
      if (be) be.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var p = proyecto(); if (!p) return toast('El proyecto aún no ha cargado.', '#8A6A34');
        modal('Nuevo enlace · ' + p, [
          { k: 'titulo', label: 'Título', req: 1 },
          { k: 'url', label: 'URL', req: 1, ayuda: 'https://…' },
          { k: 'categoria', label: 'Categoría', tipo: 'select', opciones: ['comercial', 'legal', 'tecnico', 'precios'], valor: 'comercial' },
          { k: 'visible_portal', label: 'Visible para el comprador', tipo: 'check', ayuda: 'lo verán TODOS los compradores de ' + p + ' en su portal' },
          { k: 'confidencial', label: 'Confidencial (solo equipo)', tipo: 'check' }
        ], 'Guardar enlace', function (v) {
          if (!/^https?:\/\//.test(v.url)) return { error: { message: 'la URL tiene que empezar por http:// o https://' } };
          if (v.visible_portal && !window.confirm('«' + v.titulo + '» quedará visible para TODOS los compradores de ' + p + ' en su portal. ¿Publicarlo?')) {
            return { error: { message: 'publicación al portal cancelada — desmarca la casilla o confirma' } };
          }
          return sb.from('documentos_proyecto').insert({
            proyecto: p, titulo: v.titulo, url: v.url, categoria: v.categoria,
            visible_portal: v.visible_portal, confidencial: v.confidencial
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
        modal('Alta de comprador', [
          { k: 'full_name', label: 'Nombre completo / razón social', req: 1 },
          { k: 'email', label: 'Email', tipo: 'email' },
          { k: 'phone', label: 'Teléfono' },
          { k: 'nationality', label: 'Nacionalidad', ayuda: 'código de dos letras: ES, SG, AU…' },
          { k: 'tipo', label: 'Tipo', tipo: 'select', opciones: [['persona', 'Persona física'], ['empresa', 'Empresa']], valor: 'persona' }
        ], 'Dar de alta', function (v) {
          /* el alta la puede hacer cualquier agente; EDITAR una ficha ya creada
             es de administracion (policy es_admin) — asimetria deliberada de la
             suite (migracion 7-ago), que este editor respeta y no "arregla" */
          return sb.from('clients').insert({
            full_name: v.full_name, email: v.email || null, phone: v.phone || null,
            nationality: v.nationality || null, tipo: v.tipo
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
      if (fn) { try { fn(aut); } catch (e) { console.error('[v4 editores]', e); } }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
