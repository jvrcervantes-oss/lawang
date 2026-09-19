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

     ⚠️ NOTA VIEJA, corregida el 14-sep por la tarde: aqui ponia que `opts.lateral`
     anclaba el panel a la derecha y que «sin opts» salia la ventana centrada de
     siempre. Ya no hay ventana centrada — era la que el owner llamo fea y se
     retiro. `opts.lateral` no hace nada y se conserva solo para que las llamadas
     que ya lo pasaban sigan valiendo. Lo que si manda es `opts.encabezado` (un
     bloque de solo lectura arriba) y `opts.sub`, que ahora es el CINTILLO de la
     cabecera, no un subtitulo.

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
  /* ═══ LA VENTANA ES UN CAJON, Y SOLO UN CAJON (14-sep-2026, encargo del owner)
     «el pop-up de formulario es muy feo, quiero que sea el diseno de otro cajon».

     Habia dos formas: una ventana centrada —la que se veia fea— y una variante
     `lateral` que ya era un cajon pero con otra piel. Ahora hay una sola, y toma
     el lenguaje del cajon de proyecto de /v4/proyectos/, que es el que el owner
     senalo. De alli salen, MEDIDOS y no a ojo:
       · velo `rgba(0,0,0,.3)` con desenfoque de 2 px (su `bg-black/30`)
       · panel a la derecha, borde #E4DCCB y sombra larga, entrando en 300 ms
       · cabecera con banda #f5f4ee: CINTILLO arriba y titulo grande debajo — al
         reves que antes. El cajon pone el contexto primero y el nombre despues,
         y se lee mejor: «de que hablamos» antes que «cual»
       · las filas en tarjeta #f5f4ee con borde y radio 12
       · pie fijo con banda, y el primario ocupando el ancho que sobra

     LO QUE LA HACIA FEA, y que aqui no se repite: la etiqueta era un rotulo en
     mayusculas con tracking de titular, mas grande y mas oscuro que el dato que
     etiquetaba, flotando sobre un campo suelto. Ahora es pequena, en minusculas
     y DENTRO de la tarjeta de su campo. */
  var CAJ = {
    borde: '#E4DCCB', banda: '#f5f4ee', papel: '#ffffff',
    lago: '#104C4F', hoja: '#8F9B7A', apagado: '#75786e', tinta: '#2E3437'
  };

  /* Flechita de <select> (16-sep-2026, encargo del owner: "no queda claro que
     es un desplegable"). La v4 carga Tailwind Forms (`?plugins=forms`), que SI
     pinta una flecha por defecto sobre `select` — pero cada campo fija su color
     de fondo con el shorthand `background`, que resetea `background-image` a
     `none`, y el inline style siempre gana a la hoja de Tailwind por
     especificidad. Un solo SVG en base64 a nivel de modulo, para que cualquier
     <select> de este fichero (el formulario generico y los widgets a mano como
     montaTramos) lo pinte igual sin depender del CDN. */
  var flechaSelect = ";appearance:none;-webkit-appearance:none;-moz-appearance:none;" +
    "background-image:url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 20 20%22 fill=%22none%22 stroke=%22%2344483f%22 stroke-width=%222%22><path d=%22M5 7l5 5 5-5%22 stroke-linecap=%22round%22 stroke-linejoin=%22round%22/></svg>');" +
    "background-repeat:no-repeat;background-position:right 10px center;background-size:14px;padding-right:32px";

  function modal(titulo, campos, textoBoton, onGuardar, opts) {
    opts = opts || {};
    /* `lateral` se conserva como opcion muerta: las llamadas que ya lo pasaban
       siguen valiendo sin tocarlas, y ahora da igual porque TODAS son cajon. El
       que sigue mandando es `medio:1` de cada campo, que decide si ocupa media
       fila o la entera. */
    var lateral = true;
    cierraModal();
    var w = document.createElement('div');
    w.id = 'lw-editor';
    var cajaForm = 'pointer-events:auto;position:fixed;top:0;right:0;height:100%;width:min(640px,96vw);' +
      'background:' + CAJ.papel + ';border-left:1px solid ' + CAJ.borde + ';' +
      'box-shadow:0 25px 50px -12px rgba(0,0,0,.25);display:flex;flex-direction:column;' +
      'transform:translateX(100%);transition:transform .3s ease-in-out;';
    var cajaMarco = 'position:fixed;inset:0;z-index:var(--z-modal,400);pointer-events:none';
    var cajaCabecera = 'display:flex;justify-content:space-between;align-items:flex-start;gap:16px;' +
      'padding:20px 24px;background:' + CAJ.banda + ';border-bottom:1px solid ' + CAJ.borde + ';flex-shrink:0';
    var cajaCuerpo = 'flex:1;overflow:auto;padding:20px 24px;min-height:0';
    var cajaCampos = 'display:grid;grid-template-columns:1fr 1fr;gap:12px';
    var cajaPie = 'display:flex;align-items:center;gap:10px;padding:14px 24px;' +
      'border-top:1px solid ' + CAJ.borde + ';background:' + CAJ.banda + ';flex-shrink:0';

    w.innerHTML =
      '<div data-e="fondo" style="position:fixed;inset:0;background:rgba(0,0,0,.3);backdrop-filter:blur(2px);z-index:calc(var(--z-modal,400) - 1);transition:opacity .3s ease-in-out;opacity:0"></div>' +
      '<div role="dialog" aria-modal="true" style="' + cajaMarco + '">' +
      '<form data-e="form" data-lateral="1" style="' + cajaForm + FUENTE + '">' +
      '<div style="' + cajaCabecera + '">' +
      '<div style="min-width:0">' +
      (opts.sub ? '<p style="margin:0 0 5px;font-weight:600;font-size:11px;line-height:1.3;letter-spacing:.12em;text-transform:uppercase;color:' + CAJ.hoja + '">' + esc(opts.sub) + '</p>' : '') +
      "<h3 style=\"margin:0;font:700 25px/1.2 'Neue Kabel',sans-serif;letter-spacing:-.01em;color:" + CAJ.lago + "\">" + esc(titulo) + "</h3>" +
      '</div>' +
      '<button type="button" data-e="cerrar" style="border:0;background:none;font-size:20px;cursor:pointer;color:#75786e;line-height:1">×</button></div>' +
      '<div style="' + cajaCuerpo + '">' +
      (opts.encabezado || '') +
      '<div data-e="campos" style="' + cajaCampos + '"></div>' +
      /* Rojo solido y no el rosa palido de antes (14-sep-2026, misma peticion
         del owner): a 13px sobre #ffdad6 el aviso se confundia con una nota de
         ayuda. Va dentro del modal, que ya esta centrado. */
      '<p data-e="error" role="alert" style="display:none;margin:14px 0 0;padding:12px 14px;border-radius:8px;background:#9E2F26;color:#fff;font-weight:600;font-size:14px;line-height:1.4"></p>' +
      '</div>' +
      '<div style="' + cajaPie + '">' +
      /* Botones del cajon: rectangulos de radio 10, no pastillas, y el primario
         ocupa el ancho que sobra — igual que «Exportar cuentas del proyecto» en
         el cajon de /v4/proyectos/. Con el pie fijo, un boton ancho es ademas
         mas facil de acertar que una pastilla en la esquina. */
      '<button type="button" data-e="cancelar" style="flex:0 0 auto;padding:11px 20px;border-radius:10px;border:1px solid ' + CAJ.borde + ';background:' + CAJ.papel + ';color:' + CAJ.tinta + ';font-weight:600;font-size:14px;cursor:pointer">Cancelar</button>' +
      '<button type="submit" data-e="guardar" style="flex:1;padding:11px 20px;border-radius:10px;border:0;background:' + CAJ.lago + ';color:#fff;font-weight:600;font-size:14px;cursor:pointer;letter-spacing:.02em">' + esc(textoBoton || 'Guardar') + '</button>' +
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
    /* El campo va sobre BLANCO dentro de su tarjeta, que es la que lleva el
       #f5f4ee del cajon: sin ese contraste el campo se pierde dentro de la
       tarjeta y no se ve donde hay que escribir. El borde baja a `warm-border`
       —el mismo que separa las filas del cajon— en vez del #8A8474 de control,
       que a este tamano y sobre crema se leia como una caja de texto de 2005. */
    var estilo = 'width:100%;padding:9px 12px;border:1px solid ' + CAJ.borde + ';border-radius:8px;' +
      'font-weight:500;font-size:14px;color:' + CAJ.tinta + ';background-color:' + CAJ.papel + ';box-sizing:border-box';
    /* Cada campo es una FILA DEL CAJON: tarjeta con su borde y su radio 12, y la
       etiqueta dentro. Antes la etiqueta era un rotulo en mayusculas con
       tracking de titular flotando encima de un campo suelto — mas fuerte que el
       dato que nombraba, y sin nada que los atara. */
    var tarjeta = 'display:grid;gap:6px;background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde + ';' +
      'border-radius:12px;padding:12px 14px;font-weight:500;font-size:12px;line-height:1.35;color:' + CAJ.apagado + ';' +
      'text-transform:none;letter-spacing:0';
    campos.forEach(function (c) {
      var d = document.createElement('label');
      d.style.cssText = tarjeta;
      // En lateral la rejilla es de dos columnas: por defecto un campo ocupa la
      // fila entera y `medio:1` lo deja a media. En ventana no hay columnas que
      // repartir, asi que la marca se ignora sola.
      if (lateral) d.style.gridColumn = c.medio ? 'span 1' : '1 / -1';
      var inner = esc(c.label) + (c.req ? ' *' : '');
      if (c.tipo === 'check') {
        d.style.cssText = 'display:flex;gap:10px;align-items:flex-start;background:' + CAJ.banda +
          ';border:1px solid ' + CAJ.borde + ';border-radius:12px;padding:12px 14px;' +
          'font-weight:500;font-size:13px;color:' + CAJ.tinta + ';text-transform:none;letter-spacing:0';
        if (lateral) d.style.gridColumn = '1 / -1';   // cssText de arriba lo borro
        d.innerHTML = '<input type="checkbox" data-k="' + esc(c.k) + '"' + (c.valor ? ' checked' : '') + ' style="margin-top:2px">' +
          '<span>' + esc(c.label) + (c.ayuda ? '<br><small style="color:#8A6A34">' + esc(c.ayuda) + '</small>' : '') + '</span>';
      } else if (c.tipo === 'select') {
        d.innerHTML = inner + '<select data-k="' + esc(c.k) + '" style="' + estilo + flechaSelect + '">' +
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
        /* La nota NO lleva el crema de las demas tarjetas: es lo unico del
           formulario que no se rellena, y si se viste igual que un campo se lee
           como un campo bloqueado. El ambar la separa; el radio 12 la mantiene
           dentro del sistema. */
        d.style.cssText = 'display:block;font-weight:400;font-size:12.5px;line-height:1.5;text-transform:none;letter-spacing:0;' +
          'color:#8A6A34;background:#FBF3E4;border:1px solid #EBDCB4;border-radius:12px;padding:11px 14px;margin:0';
        if (lateral) d.style.gridColumn = '1 / -1';   // cssText de arriba lo borro
        d.innerHTML = esc(c.label);
      } else if (c.tipo === 'lectura') {
        // Espejo de solo lectura: se ve el valor y se entiende que no se toca
        // aquí. Tampoco lleva `data-k`, por lo mismo que 'nota'. `dataMostrar`
        // es opcional y SOLO sirve para que otro script (ej. el recalculo de
        // precio de suelo) lo encuentre y actualice su texto en vivo — nunca
        // se lee al recoger el formulario.
        d.innerHTML = inner + '<input' + (c.dataMostrar ? ' data-mostrar="' + esc(c.dataMostrar) + '"' : '') +
          ' value="' + esc(c.valor == null ? '' : c.valor) + '" readonly tabindex="-1" style="' +
          estilo + ';background-color:#f5f4ee;color:#75786e;cursor:not-allowed">';
      } else if (c.tipo === 'textarea') {
        d.innerHTML = inner + '<textarea data-k="' + esc(c.k) + '" rows="4" style="' + estilo + ';resize:vertical">' + esc(c.valor) + '</textarea>';
      } else if (c.tipo === 'file') {
        d.innerHTML = inner + '<input data-k="' + esc(c.k) + '" type="file" accept="' + esc(c.accept || '*/*') + '" style="' + estilo + ';padding:7px 10px">';
      } else if (c.tipo === 'custom') {
        /* Hueco para un widget propio que el formulario generico no sabe
           dibujar — hoy solo los tramos de Condiciones de comision, una lista
           de filas de alta/baja variable que no encaja en ningun `tipo` de
           arriba. SIN `data-k`: el colector generico de mas abajo lo ignora a
           proposito, y `c.render(d)` es quien deja preparado lo que haga
           falta (normalmente una funcion que el propio `onGuardar` llama para
           recoger el valor — ver `montaTramos()`). Nunca lleva `req`: el
           chequeo generico de "falta «X»" mira `vals[c.k]`, que aqui nunca se
           rellena, y marcaria el campo como vacio aunque este bien. */
        d.style.cssText = 'display:block;background:none;border:0;padding:0;margin:0;text-transform:none;letter-spacing:0';
        if (lateral) d.style.gridColumn = '1 / -1';
        if (typeof c.render === 'function') c.render(d);
      } else if (c.tipo === 'multicheck') {
        // `o` es un string (valor = etiqueta, como ya usaba Usuarios) o un
        // par [valor, etiqueta] — igual que ya admite 'select' — para cuando el
        // valor que hay que guardar (un id) no es lo que se quiere leer (un
        // nombre). Proyectos lo necesita para modelos y managers.
        d.innerHTML = inner + '<div data-k="' + esc(c.k) + '" style="display:grid;grid-template-columns:1fr 1fr;gap:6px;font-weight:500;font-size:13px;text-transform:none;letter-spacing:0;color:#2E3437">' +
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
        d.innerHTML += '<small style="font-weight:400;font-size:12px;text-transform:none;letter-spacing:0;color:#8A8474">' + esc(c.ayuda) + '</small>';
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
        /* Recargar es lo correcto para un editor que acaba de escribir en la
           base: la pantalla vuelve con el dato ya guardado y no hay que cablear
           un repintado por cada formulario. Pero NO para quien no guarda nada —
           los formularios de relleno de la maqueta—, que se quedarian recargando
           la pagina por haber pulsado «Guardar» en algo que no guarda. */
        if (!opts.sinRecarga) location.reload();
      }, function (e) {
        btn.disabled = false; btn.textContent = textoBoton || 'Guardar';
        muestraError('No se pudo guardar: ' + (e && e.message || e));
      });
    });
  }

  /* ---------- CAJON DE FICHA: para MIRAR, y desde ahi editar (18-sep-2026) ----------
     Owner: «prefiero que al clickar en un agente se me abra un cajeton lateral»
     (Usuarios), y en Compradores «si abro un comprador me lleva a la version
     antigua, preparalo para la v4 ya». Las dos pantallas necesitaban lo mismo:
     una ficha de solo lectura con acciones al pie, que se abre para comprobar
     un dato mucho mas a menudo que para cambiarlo (la regla «ficha que ya
     existe abre cerrada» de contexto/suite_lawang.md).

     Es OTRA funcion y no `modal()` con campos de tipo `lectura`, por tres cosas
     que no son de gusto:
       · `modal()` es un formulario: valida, recoge y guarda. Aqui no hay nada
         que guardar, y un pie con «Guardar» sobre una ficha que no se edita
         es una promesa falsa.
       · id propio (`lw-cajon`): `modal()` arranca con cierraModal(), que borra
         `#lw-editor`. Si la ficha viviera ahi, pulsar «Editar datos» la
         cerraria en vez de abrir el formulario encima.
       · z-index diez por debajo de `--z-modal`: el editor se abre ENCIMA de la
         ficha y al cerrarse la ficha sigue ahi — el mismo patron que el cajon
         de /v4/proyectos/ con su editor de parcela.

     La PIEL es la de `modal()` (CAJ, FUENTE, banda de cabecera, tarjetas de
     radio 12, pie fijo), medida del cajon de proyecto y no reinventada.

     Los clics se paran en la raiz del cajon: `maqueta.js` delega en `document`
     y anunciaria cada boton de aqui como «sin cablear» encima de lo que el
     boton ya hizo. Pararlos aqui, una vez, evita repetir `stopPropagation` en
     cada accion de cada ficha. */
  function cierraCajon() {
    var c = document.getElementById('lw-cajon');
    if (!c) return;
    var p = c.querySelector('[data-c="panel"]'), f = c.querySelector('[data-c="fondo"]');
    if (p) p.style.transform = 'translateX(100%)';
    if (f) f.style.opacity = '0';
    if (c._teclas) document.removeEventListener('keydown', c._teclas);
    var alCerrar = c._alCerrar; c._alCerrar = null;
    setTimeout(function () { if (c.parentNode) c.remove(); }, 260);
    if (typeof alCerrar === 'function') alCerrar();
  }
  function cajon(o) {
    o = o || {};
    var viejo = document.getElementById('lw-cajon');
    if (viejo) { viejo._alCerrar = null; viejo.remove(); }
    var w = document.createElement('div');
    w.id = 'lw-cajon';
    var z = 'calc(var(--z-modal,400) - 10)';
    var cajaPanel = 'position:fixed;top:0;right:0;height:100%;width:' + (o.ancho || 'min(720px,96vw)') + ';' +
      'background:' + CAJ.papel + ';border-left:1px solid ' + CAJ.borde + ';z-index:' + z + ';' +
      'box-shadow:0 25px 50px -12px rgba(0,0,0,.25);display:flex;flex-direction:column;' +
      'transform:translateX(100%);transition:transform .3s ease-in-out;' + FUENTE;
    var cajaCabecera = 'display:flex;justify-content:space-between;align-items:flex-start;gap:16px;' +
      'padding:20px 24px;background:' + CAJ.banda + ';border-bottom:1px solid ' + CAJ.borde + ';flex-shrink:0';
    var cajaCuerpo = 'flex:1;overflow:auto;padding:20px 24px;min-height:0;display:grid;gap:14px;align-content:start';
    var cajaPie = 'display:flex;flex-wrap:wrap;align-items:center;gap:10px;padding:14px 24px;' +
      'border-top:1px solid ' + CAJ.borde + ';background:' + CAJ.banda + ';flex-shrink:0';
    var estiloBoton = function (a) {
      var base = 'padding:11px 18px;border-radius:10px;font-weight:600;font-size:14px;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center;gap:6px;';
      if (a.tono === 'primario') return base + 'flex:1;justify-content:center;border:0;background:' + CAJ.lago + ';color:#fff;letter-spacing:.02em';
      if (a.tono === 'peligro') return base + 'border:1px solid #9E2F26;background:' + CAJ.papel + ';color:#9E2F26;margin-left:auto';
      return base + 'border:1px solid ' + CAJ.borde + ';background:' + CAJ.papel + ';color:' + CAJ.tinta;
    };
    w.innerHTML =
      '<div data-c="fondo" style="position:fixed;inset:0;background:rgba(0,0,0,.3);backdrop-filter:blur(2px);z-index:calc(' + z + ' - 1);transition:opacity .3s ease-in-out;opacity:0"></div>' +
      '<aside role="dialog" aria-modal="true" aria-label="' + esc(o.titulo || 'Ficha') + '" data-c="panel" style="' + cajaPanel + '">' +
      '<div style="' + cajaCabecera + '"><div style="min-width:0">' +
      (o.sub ? '<p style="margin:0 0 5px;font-weight:600;font-size:11px;line-height:1.3;letter-spacing:.12em;text-transform:uppercase;color:' + CAJ.hoja + '">' + esc(o.sub) + '</p>' : '') +
      "<h3 style=\"margin:0;font:700 25px/1.2 'Neue Kabel',sans-serif;letter-spacing:-.01em;color:" + CAJ.lago + ";overflow-wrap:anywhere\">" + esc(o.titulo || '') + '</h3>' +
      (o.bajoTitulo ? '<p style="margin:6px 0 0;font-size:13px;color:' + CAJ.apagado + '">' + esc(o.bajoTitulo) + '</p>' : '') +
      '</div><button type="button" data-c="cerrar" aria-label="Cerrar" style="border:0;background:none;font-size:22px;cursor:pointer;color:#75786e;line-height:1">×</button></div>' +
      '<div data-c="cuerpo" style="' + cajaCuerpo + '">' + (o.cuerpo || '') + '</div>' +
      '<div data-c="pie" style="' + cajaPie + '"></div></aside>';
    var pie = w.querySelector('[data-c="pie"]');
    (o.acciones || []).forEach(function (a) {
      var b;
      if (a.href) {
        b = document.createElement('a'); b.href = a.href;
        if (a.nuevaPestana) { b.target = '_blank'; b.rel = 'noopener'; }
      } else { b = document.createElement('button'); b.type = 'button'; }
      b.textContent = a.texto;
      b.style.cssText = estiloBoton(a);
      if (a.cerrar) b.addEventListener('click', cierraCajon);
      else if (typeof a.onClick === 'function') b.addEventListener('click', function (ev) { a.onClick(ev, w); });
      pie.appendChild(b);
    });
    // Un cajon sin acciones lleva al menos «Cerrar»: la X de arriba no basta
    // en movil, donde el pulgar vive abajo.
    if (!(o.acciones || []).some(function (a) { return a.cerrar; })) {
      var bc = document.createElement('button'); bc.type = 'button'; bc.textContent = 'Cerrar';
      bc.style.cssText = estiloBoton({}); bc.addEventListener('click', cierraCajon); pie.appendChild(bc);
    }
    w.querySelector('[data-c="cerrar"]').addEventListener('click', cierraCajon);
    w.querySelector('[data-c="fondo"]').addEventListener('click', cierraCajon);
    // Parar aqui lo que ya se atendio dentro (ver cabecera del bloque).
    w.addEventListener('click', function (ev) {
      if (ev.target.closest && ev.target.closest('button, a')) ev.stopPropagation();
    });
    w._alCerrar = o.alCerrar || null;
    w._teclas = function (ev) {
      // Con el editor abierto encima, Escape es del editor (que hoy no lo
      // escucha): no se le cierra la ficha por debajo sin querer.
      if (ev.key === 'Escape' && !document.getElementById('lw-editor')) cierraCajon();
    };
    document.addEventListener('keydown', w._teclas);
    document.body.appendChild(w);
    var panel = w.querySelector('[data-c="panel"]'), fondo = w.querySelector('[data-c="fondo"]');
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { panel.style.transform = 'translateX(0)'; fondo.style.opacity = '1'; });
    });
    return { el: w, cuerpo: w.querySelector('[data-c="cuerpo"]'), pie: pie, cierra: cierraCajon };
  }
  /* Piezas con las que una pantalla compone el cuerpo del cajon. Devuelven
     HTML ya escapado: el texto entra crudo y sale seguro. `html:1` en `dato`
     es la unica puerta para meter marcado (una etiqueta de estado, un
     enlace), y quien la usa escapa el mismo. */
  var CAJON_HTML = {
    seccion: function (titulo, inner, id) {
      return '<section' + (id ? ' data-cajon-sec="' + esc(id) + '"' : '') + ' style="background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde + ';border-radius:12px;padding:12px 14px">' +
        '<h4 style="margin:0 0 8px;font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:' + CAJ.hoja + '">' + esc(titulo) + '</h4>' +
        '<div style="display:grid;gap:6px">' + (inner || '') + '</div></section>';
    },
    dato: function (etq, valor, opts) {
      var v = (valor == null || valor === '') ? '<span style="color:' + CAJ.apagado + '">—</span>' : ((opts && opts.html) ? valor : esc(valor));
      return '<div style="display:flex;justify-content:space-between;gap:14px;padding:6px 0;border-bottom:1px solid rgba(228,220,203,.7);font-size:13px">' +
        '<span style="color:' + CAJ.apagado + ';font-weight:500;flex:0 0 38%">' + esc(etq) + '</span>' +
        '<span style="color:' + CAJ.tinta + ';font-weight:500;text-align:right;overflow-wrap:anywhere;min-width:0">' + v + '</span></div>';
    },
    tabla: function (cabeceras, filas) {
      return '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:12.5px"><thead><tr>' +
        cabeceras.map(function (h) { return '<th style="text-align:left;padding:6px 8px;font-size:10.5px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' + CAJ.apagado + ';border-bottom:1px solid ' + CAJ.borde + '">' + esc(h) + '</th>'; }).join('') +
        '</tr></thead><tbody>' +
        filas.map(function (f) { return '<tr>' + f.map(function (c) { return '<td style="padding:7px 8px;border-bottom:1px solid rgba(228,220,203,.7);color:' + CAJ.tinta + ';vertical-align:top">' + c + '</td>'; }).join('') + '</tr>'; }).join('') +
        '</tbody></table></div>';
    },
    tag: function (texto, tono) {
      var c = { ok: ['#E4F0DA', '#3F5230'], espera: ['#FBF3E4', '#8A6A34'], mal: ['#FFDAD6', '#93000A'] }[tono] || ['#EAE8E2', CAJ.tinta];
      return '<span style="display:inline-block;padding:2px 9px;border-radius:999px;font-size:11px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;background:' + c[0] + ';color:' + c[1] + '">' + esc(texto) + '</span>';
    },
    chips: function (lista) {
      return '<div style="display:flex;flex-wrap:wrap;gap:6px">' + lista.map(function (x) {
        return '<span style="padding:3px 10px;border-radius:999px;background:' + CAJ.papel + ';border:1px solid ' + CAJ.borde + ';font-size:12px;color:' + CAJ.tinta + '">' + esc(x) + '</span>';
      }).join('') + '</div>';
    },
    nota: function (texto, html) {
      return '<p style="margin:0;font-size:12.5px;line-height:1.5;color:#8A6A34;background:#FBF3E4;border:1px solid #EBDCB4;border-radius:10px;padding:9px 12px">' + (html ? texto : esc(texto)) + '</p>';
    },
    enlace: function (href, texto, nuevaPestana) {
      return '<a href="' + esc(href) + '"' + (nuevaPestana ? ' target="_blank" rel="noopener"' : '') + ' style="color:' + CAJ.lago + ';font-weight:600;text-decoration:underline">' + esc(texto) + '</a>';
    }
  };
  window.lwCajon = cajon;
  window.lwCierraCajon = cierraCajon;
  window.lwCajonHtml = CAJON_HTML;
  /* Un UPDATE o un DELETE que la policy filtra no da error: devuelve 0 filas y
     el editor diria «guardado» sobre nada (reference_supabase_grant_manda_
     antes_que_la_policy). Todo lo que escribe con `.select('id')` pasa por
     aqui y convierte el silencio en un mensaje. */
  function unaFila(r) {
    if (r && r.error) return r;
    if (!(r && r.data && r.data.length)) {
      return { error: { message: 'la base no ha cambiado ninguna fila — la policy no deja tocarla con tu sesión.' } };
    }
    return r;
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
  /* ADAPTADOR, ya no una segunda implementacion (14-sep-2026, encargo del owner).
     Este fichero pintaba su propio aviso, y la suite viva YA tenia uno resuelto en
     `contracts/assets/suite-comun.js` desde agosto: limpia el temporizador (el
     fallo de dos avisos pisandose), se anuncia con aria-live y lee su duracion de
     la misma variable que anima la barra. El de aqui no hacia nada de eso, y
     ademas pedia `sans-serif` a secas — era el unico elemento de la suite que no
     salia en la tipografia de marca.

     ⚠️ POR QUE CAMBIA DE NOMBRE. `toast` y `toastMal` son `const` de nivel
     superior en suite-comun.js, y un `const` de nivel superior NO queda en
     `window`: solo se alcanza como identificador suelto. Una funcion `toast()`
     aqui dentro lo TAPARIA y no habria forma de llamar a la de fuera. Por eso el
     adaptador se llama `aviso` y las 43 llamadas se renombraron con el.

     ⚠️ Y POR QUE HACE FALTA EL ADAPTADOR en vez de llamar directo: el segundo
     argumento significa cosas distintas. Aqui marcaba ERROR; en la pieza
     compartida es la DURACION en ms. Pasar un color donde va un numero daria un
     `setTimeout` de NaN y el aviso se iria en el acto. La inversion se traduce
     una sola vez, aqui. */
  function aviso(msg, color) {
    if (color) toastMal(msg); else toast(msg);
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

  /* ---------- Tramos de pago (Condiciones de comisión, 14-sep-2026) ----------
     Fila dinámica con añadir/quitar y suma en vivo. Por qué hace falta un
     constructor propio y no el 'multicheck' o el 'select' de siempre: el
     trigger `condicion_tramos_suma_100` de la base es DEFERRABLE INITIALLY
     DEFERRED, pero cada request de PostgREST es su propia transacción — así
     que un tramo insertado SOLO nunca puede sumar 100 salvo que sea el único,
     y no hay forma de "ir añadiendo tramos" contra esta tabla: hay que
     recogerlos TODOS en el formulario y escribirlos en un único INSERT
     multi-fila. Esto es el cinturón (se valida aquí, antes de tocar la base,
     con un error legible); el trigger es el tirante (si algo se escapa, la
     base lo rechaza igual — verificado con sesión admin real, suma 90 vs
     100, revisión previa Datos+Seguridad). */
  var DISPARADORES_TRAMO_FALLBACK = [
    ['contrato_firmado', 'Al firmar el contrato'],
    ['obra_firmada', 'Al firmar la obra'],
    ['pct_cobrado_suelo', '% cobrado del suelo'],
    ['pct_cobrado_obra', '% cobrado de la obra'],
    ['pct_cobrado_total', '% cobrado del total']
  ];
  var BASES_CALCULO_FALLBACK = [
    ['precio_total', 'Precio total'],
    ['precio_suelo', 'Precio de suelo'],
    ['precio_construccion', 'Precio de construcción'],
    ['importe_fijo', 'Importe fijo']
  ];
  function montaTramos(host) {
    var opciones = (window.LW_V4 && window.LW_V4.DISPARADORES) || DISPARADORES_TRAMO_FALLBACK;
    var filas = [];
    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:grid;gap:8px';
    var cab = document.createElement('div');
    cab.style.cssText = 'display:flex;justify-content:space-between;align-items:center;gap:8px';
    var tituloCab = document.createElement('span');
    tituloCab.textContent = 'Qué dispara cada pago, y qué % le toca';
    tituloCab.style.cssText = 'font-weight:500;font-size:12px;color:' + CAJ.apagado;
    var sumaBadge = document.createElement('span');
    sumaBadge.style.cssText = 'font-weight:700;font-size:12.5px;white-space:nowrap';
    cab.appendChild(tituloCab); cab.appendChild(sumaBadge);
    wrap.appendChild(cab);
    var lista = document.createElement('div');
    lista.style.cssText = 'display:grid;gap:6px';
    wrap.appendChild(lista);
    var errLinea = document.createElement('p');
    errLinea.style.cssText = 'margin:0;font-size:11.5px;color:' + CAJ.apagado;
    errLinea.textContent = 'El umbral (%) solo aplica a los disparadores «% cobrado…».';
    wrap.appendChild(errLinea);
    var btnAdd = document.createElement('button');
    btnAdd.type = 'button';
    btnAdd.textContent = '+ Añadir tramo';
    btnAdd.style.cssText = 'justify-self:start;padding:7px 12px;border-radius:8px;border:1px dashed ' +
      CAJ.hoja + ';background:transparent;color:' + CAJ.lago + ';font-weight:600;font-size:12.5px;cursor:pointer';
    wrap.appendChild(btnAdd);
    host.appendChild(wrap);

    function actualizaSuma() {
      var s = filas.reduce(function (acc, f) { return acc + (Number(f.pct.value) || 0); }, 0);
      var s2 = Math.round(s * 100) / 100;
      var ok = Math.abs(s - 100) <= 0.01;
      sumaBadge.textContent = 'Suma: ' + s2 + '%' + (ok ? ' ✓' : ' — deben sumar 100%');
      sumaBadge.style.color = ok ? '#2E5B3E' : '#9E2F26';
    }

    function quitaFila(fila) {
      if (filas.length <= 1) return;   // siempre queda al menos un tramo que rellenar
      lista.removeChild(fila.el);
      filas = filas.filter(function (f) { return f !== fila; });
      actualizaSuma();
    }

    function nuevaFila() {
      var el = document.createElement('div');
      el.style.cssText = 'display:grid;grid-template-columns:1fr 92px 84px 22px;gap:6px;align-items:center';
      var campoEstilo = 'padding:7px 8px;border:1px solid ' + CAJ.borde + ';border-radius:6px;font-size:12.5px;' +
        'color:' + CAJ.tinta + ';background-color:' + CAJ.papel + ';box-sizing:border-box;width:100%';
      var selDisp = document.createElement('select');
      selDisp.style.cssText = campoEstilo + flechaSelect;
      opciones.forEach(function (o) {
        var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; selDisp.appendChild(op);
      });
      var inpUmbral = document.createElement('input');
      inpUmbral.type = 'number'; inpUmbral.step = '0.01'; inpUmbral.min = '0'; inpUmbral.max = '100';
      inpUmbral.placeholder = 'umbral %'; inpUmbral.style.cssText = campoEstilo;
      var inpPct = document.createElement('input');
      inpPct.type = 'number'; inpPct.step = '0.01'; inpPct.min = '0'; inpPct.max = '100';
      inpPct.placeholder = '% tramo'; inpPct.style.cssText = campoEstilo;
      var btnDel = document.createElement('button');
      btnDel.type = 'button'; btnDel.textContent = '×'; btnDel.title = 'Quitar tramo';
      btnDel.style.cssText = 'border:0;background:none;color:#9E2F26;font-size:19px;line-height:1;cursor:pointer';

      var fila = { el: el, disp: selDisp, umbral: inpUmbral, pct: inpPct };

      function actualizaUmbral() {
        var necesita = /^pct_cobrado_/.test(selDisp.value);
        inpUmbral.disabled = !necesita;
        inpUmbral.style.visibility = necesita ? 'visible' : 'hidden';
        if (!necesita) inpUmbral.value = '';
      }
      selDisp.addEventListener('change', actualizaUmbral);
      actualizaUmbral();
      inpPct.addEventListener('input', actualizaSuma);
      btnDel.addEventListener('click', function () { quitaFila(fila); });

      el.appendChild(selDisp); el.appendChild(inpUmbral); el.appendChild(inpPct); el.appendChild(btnDel);
      lista.appendChild(el);
      filas.push(fila);
      actualizaSuma();
    }

    btnAdd.addEventListener('click', nuevaFila);
    nuevaFila(); nuevaFila();   // arranca con dos: lo habitual es 2+ tramos

    // getter que `onGuardar` llama para recoger el estado ACTUAL del formulario
    return function () {
      return filas.map(function (f) {
        return { disparador_tipo: f.disp.value, umbral: f.umbral.value, pct_tramo: f.pct.value };
      });
    };
  }

  /* ---------- Entrega estimada del proyecto, en trimestres (16-sep-2026) ----------
     Encargo del owner: "Q1 de 2027 es para el primer trimestre de 2027" — la
     columna `proyectos.fecha_entrega_estimada_proyecto` sigue siendo un `date`
     (no hace falta migracion nueva), pero SIEMPRE el primer dia del trimestre
     elegido, y aqui solo se edita como trimestre+año, nunca como fecha exacta.
     `tipo:'custom'` (mismo patron que montaTramos): dos <select> que no mapean
     a una sola columna, asi que el formulario generico no los sabe dibujar. */
  function montaTrimestre(host, valorFecha) {
    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:8px';
    var campoEstilo = 'padding:9px 12px;border:1px solid ' + CAJ.borde + ';border-radius:8px;' +
      'font-weight:500;font-size:14px;color:' + CAJ.tinta + ';background-color:' + CAJ.papel + ';box-sizing:border-box;width:100%';
    var selQ = document.createElement('select');
    selQ.style.cssText = campoEstilo + flechaSelect;
    [['', 'Trimestre'], ['1', 'Q1'], ['2', 'Q2'], ['3', 'Q3'], ['4', 'Q4']].forEach(function (o) {
      var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1]; selQ.appendChild(op);
    });
    var selA = document.createElement('select');
    selA.style.cssText = campoEstilo + flechaSelect;
    var opBlank = document.createElement('option'); opBlank.value = ''; opBlank.textContent = 'Año'; selA.appendChild(opBlank);
    var hoyAnio = new Date().getFullYear();
    var anioValor = null, qValor = null;
    if (valorFecha) {
      var fv = new Date(valorFecha + 'T00:00:00');
      anioValor = fv.getFullYear();
      qValor = Math.floor(fv.getMonth() / 3) + 1;
    }
    // 2 años atras (por si la estimacion ya quedo vieja/pasada, no perderla al
    // abrir el formulario) hasta 10 años adelante — de sobra para un proyecto
    // inmobiliario real.
    var desde = Math.min(hoyAnio - 2, anioValor || hoyAnio);
    for (var y = desde; y <= hoyAnio + 10; y++) {
      var opY = document.createElement('option'); opY.value = String(y); opY.textContent = String(y); selA.appendChild(opY);
    }
    if (anioValor) selA.value = String(anioValor);
    if (qValor) selQ.value = String(qValor);
    wrap.appendChild(selQ); wrap.appendChild(selA);
    host.appendChild(wrap);
    // getter que `onGuardar` llama para recoger el estado ACTUAL del formulario
    return function () {
      var q = Number(selQ.value), a = Number(selA.value);
      if (!q || !a) return null;
      var mes = (q - 1) * 3 + 1;
      return a + '-' + (mes < 10 ? '0' + mes : mes) + '-01';
    };
  }

  /* ---------- Fotos de obra (mismo bucket/optimizacion que /intranet/obra/) ----------
     Sube, titula, oculta/muestra y borra fotos de una unidad — cada accion va
     contra la base EN EL MOMENTO en que se pulsa, igual que el cajon de la
     herramienta viva: no espera al «Guardar» del formulario, que solo guarda
     fase/fecha. La optimizacion a 1600px/jpeg .82 y el bucket 'obra' son los
     MISMOS que en intranet/obra/index.html (Regla 0) — dos recompresiones que
     divergieran serian el bug de manana. */
  function montaFotosObra(host, sb, unidadId) {
    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:grid;gap:8px';
    var etiqueta = document.createElement('div');
    etiqueta.style.cssText = 'font-weight:500;font-size:12px;color:' + CAJ.apagado;
    etiqueta.textContent = 'Fotos';
    wrap.appendChild(etiqueta);
    var grid = document.createElement('div');
    grid.style.cssText = 'display:grid;grid-template-columns:repeat(auto-fill,minmax(96px,1fr));gap:8px';
    wrap.appendChild(grid);
    var caja = document.createElement('div');
    caja.textContent = '+ Subir fotos — se optimizan solas a tamaño web';
    caja.style.cssText = 'padding:10px 12px;border:1px dashed ' + CAJ.hoja + ';border-radius:8px;color:' + CAJ.lago +
      ';font-weight:600;font-size:12.5px;cursor:pointer;text-align:center';
    var input = document.createElement('input');
    input.type = 'file'; input.accept = 'image/*'; input.multiple = true; input.hidden = true;
    wrap.appendChild(caja); wrap.appendChild(input);
    host.appendChild(wrap);

    var fotos = [];

    function optimiza(file) {
      return new Promise(function (res, rej) {
        var img = new Image();
        img.onload = function () {
          var M = 1600, r = Math.min(1, M / Math.max(img.width, img.height));
          var c = document.createElement('canvas');
          c.width = Math.round(img.width * r); c.height = Math.round(img.height * r);
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          c.toBlob(function (b) { if (b) res(b); else rej(new Error('no se pudo convertir')); }, 'image/jpeg', .82);
          URL.revokeObjectURL(img.src);
        };
        img.onerror = function () { rej(new Error('imagen ilegible')); };
        img.src = URL.createObjectURL(file);
      });
    }

    function repinta() {
      grid.innerHTML = '';
      fotos.forEach(function (f) {
        var it = document.createElement('div');
        it.style.cssText = 'display:grid;gap:4px;border:1px solid ' + CAJ.borde + ';border-radius:8px;padding:6px;' +
          'background:' + CAJ.papel + (f.visible ? '' : ';opacity:.5');
        var img = document.createElement('img');
        img.style.cssText = 'width:100%;aspect-ratio:1;object-fit:cover;border-radius:6px;background:' + CAJ.banda;
        it.appendChild(img);
        sb.storage.from('obra').createSignedUrl(f.path, 1800).then(function (r) {
          if (r.data && r.data.signedUrl) img.src = r.data.signedUrl;
        });
        var titu = document.createElement('div');
        titu.textContent = f.titulo || 'Sin título';
        titu.style.cssText = 'font-size:10.5px;font-weight:600;color:' + CAJ.tinta + ';overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
        it.appendChild(titu);
        var acts = document.createElement('div');
        acts.style.cssText = 'display:flex;gap:4px;flex-wrap:wrap';
        [['Título', 'titulo'], [f.visible ? 'Ocultar' : 'Mostrar', 'visible'], ['Borrar', 'borrar']].forEach(function (par) {
          var b = document.createElement('button');
          b.type = 'button'; b.textContent = par[0];
          b.style.cssText = 'padding:2px 6px;border-radius:6px;border:1px solid ' + CAJ.borde + ';background:' + CAJ.banda +
            ';color:' + CAJ.tinta + ';font-size:10px;cursor:pointer';
          b.addEventListener('click', function () { accion(f, par[1]); });
          acts.appendChild(b);
        });
        it.appendChild(acts);
        grid.appendChild(it);
      });
    }

    function carga() {
      return sb.from('obra_fotos').select('id,path,titulo,tomada_en,visible').eq('unidad_id', unidadId)
        .order('tomada_en', { ascending: false }).then(function (r) {
          fotos = r.data || [];
          repinta();
        });
    }

    function borra(f) {
      sb.from('obra_fotos').delete().eq('id', f.id).then(function (r) {
        if (r.error) return aviso(r.error.message, '#93000a');
        // mismo tradeoff aceptado que accionFoto('borrar') en /intranet/obra/
        sb.storage.from('obra').remove([f.path]).catch(function (e) {
          /* MUDO A PROPOSITO: la fila ya se borró de obra_fotos (lo que decide
             qué ve el portal); si esto falla el blob queda huérfano en un
             bucket privado, sin efecto para nadie — solo se deja constancia
             en consola para quien audite el bucket, no hace falta interrumpir
             al agente por un archivo que ya dejó de mostrarse. */
          console.error('[v4 obra] fallo al borrar del bucket:', e);
        });
        carga();
      });
    }

    function accion(f, act) {
      if (act === 'visible') {
        sb.from('obra_fotos').update({ visible: !f.visible }).eq('id', f.id).then(function (r) {
          if (r.error) return aviso(r.error.message, '#93000a');
          carga();
        });
      } else if (act === 'titulo') {
        var t = window.prompt('Título de la foto (lo ve el comprador):', f.titulo || '');
        if (t === null) return;
        sb.from('obra_fotos').update({ titulo: t.trim() || null }).eq('id', f.id).then(function (r) {
          if (r.error) return aviso(r.error.message, '#93000a');
          carga();
        });
      } else if (act === 'borrar') {
        var ir = (typeof lwConfirmar === 'function')
          ? lwConfirmar({ titulo: 'Borrar esta foto', cuerpo: 'Se quita también del portal del comprador. Esto no se puede deshacer.', confirmar: 'Borrar', tono: 'peligro' })
          : Promise.resolve(window.confirm('Borrar esta foto — se quita también del portal del comprador.'));
        ir.then(function (seguro) { if (seguro) borra(f); });
      }
    }

    caja.addEventListener('click', function () { input.click(); });
    input.addEventListener('change', function () {
      var files = Array.prototype.slice.call(input.files);
      if (!files.length) return;
      caja.textContent = 'Subiendo…';
      var ok = 0, pend = files.length;
      files.forEach(function (file) {
        optimiza(file).then(function (blob) {
          var nombre = Date.now() + '_' + file.name.replace(/[^a-z0-9._-]/gi, '_').replace(/\.[^.]+$/, '') + '.jpg';
          var path = unidadId + '/' + nombre;
          return sb.storage.from('obra').upload(path, blob, { contentType: 'image/jpeg' }).then(function (up) {
            if (up.error) throw up.error;
            return sb.from('obra_fotos').insert({ unidad_id: unidadId, path: path }).select('id');
          });
        }).then(function (ins) {
          if (ins && ins.error) throw ins.error;
          ok++;
        }).catch(function (e) {
          aviso('«' + file.name + '»: ' + (e && e.message || e), '#93000a');
        }).then(function () {
          pend--;
          if (pend === 0) {
            caja.textContent = '+ Subir fotos — se optimizan solas a tamaño web';
            input.value = '';
            if (ok) aviso(ok + (ok === 1 ? ' foto subida' : ' fotos subidas'));
            carga();
          }
        });
      });
    });

    carga();
  }

  /* ---------- sub-tablas de «Editar datos» en Modelos ----------
     Las tres viven en el MISMO «Guardar» que el resto de la ficha — a
     diferencia de las fotos de obra, aquí no hay acción que se confirme sola:
     se recogen con un getter (mismo patrón que montaTramos) y `onGuardar` las
     escribe todas seguidas, igual que guardar() en /intranet/modelos/. */
  function fila3(host) {
    var f = document.createElement('div');
    f.style.cssText = 'display:grid;grid-template-columns:1fr 100px 100px;gap:6px;align-items:center;margin-bottom:6px';
    host.appendChild(f);
    return f;
  }
  function numIn(placeholder) {
    var i = document.createElement('input');
    i.type = 'number'; i.step = '0.01'; if (placeholder) i.placeholder = placeholder;
    i.style.cssText = 'width:100%;padding:6px 8px;border:1px solid ' + CAJ.borde + ';border-radius:6px;font-size:12.5px';
    return i;
  }
  function montaTechosModelo(host, techos) {
    if (!techos.length) {
      var p = document.createElement('p');
      p.style.cssText = 'margin:0;font-size:12px;color:' + CAJ.apagado;
      p.textContent = 'Este modelo no tiene variantes de techo.';
      host.appendChild(p);
      return function () { return []; };
    }
    var cab = fila3(host);
    ['', 'Ahora', 'Desde 2027'].forEach(function (t) {
      var s = document.createElement('span'); s.textContent = t;
      s.style.cssText = 'font-size:10.5px;font-weight:700;color:' + CAJ.apagado + ';text-transform:uppercase;letter-spacing:.06em';
      cab.appendChild(s);
    });
    var filas = techos.map(function (t) {
      var f = fila3(host);
      var nom = document.createElement('span'); nom.textContent = t.nombre; nom.style.cssText = 'font-size:13px;font-weight:600;color:' + CAJ.tinta;
      var ahora = numIn(); ahora.value = t.precio_ahora == null ? '' : t.precio_ahora;
      var y27 = numIn(); y27.value = t.precio_2027 == null ? '' : t.precio_2027;
      f.appendChild(nom); f.appendChild(ahora); f.appendChild(y27);
      return { id: t.id, ahora: ahora, y27: y27 };
    });
    return function () {
      return filas.map(function (f) {
        return { id: f.id, precio_ahora: f.ahora.value === '' ? null : Number(f.ahora.value), precio_2027: f.y27.value === '' ? null : Number(f.y27.value) };
      });
    };
  }
  function montaExtrasModelo(host, extras, existentes) {
    if (!extras.length) {
      var p = document.createElement('p');
      p.style.cssText = 'margin:0;font-size:12px;color:' + CAJ.apagado;
      p.textContent = 'No hay extras dados de alta en el catálogo.';
      host.appendChild(p);
      return function () { return []; };
    }
    var filas = extras.map(function (e) {
      var existente = existentes.filter(function (x) { return x.extra_id === e.id; })[0] || null;
      var f = document.createElement('div');
      f.style.cssText = 'display:grid;grid-template-columns:1fr 100px auto;gap:6px;align-items:center;margin-bottom:6px';
      var nom = document.createElement('span'); nom.textContent = e.nombre; nom.style.cssText = 'font-size:13px;font-weight:600;color:' + CAJ.tinta;
      var precio = numIn(); precio.value = (existente && existente.precio != null) ? existente.precio : '';
      var lab = document.createElement('label');
      lab.style.cssText = 'display:flex;align-items:center;gap:5px;font-size:11.5px;color:' + CAJ.apagado + ';white-space:nowrap';
      var chk = document.createElement('input'); chk.type = 'checkbox';
      chk.checked = !existente || existente.disponible !== false;   // sin fila = se ofrece, igual que en vivo
      lab.appendChild(chk); lab.appendChild(document.createTextNode('se ofrece'));
      f.appendChild(nom); f.appendChild(precio); f.appendChild(lab);
      host.appendChild(f);
      return { extraId: e.id, existenteId: existente ? existente.id : null, precio: precio, chk: chk };
    });
    return function () {
      return filas.map(function (f) {
        return { extraId: f.extraId, existenteId: f.existenteId, precio: f.precio.value === '' ? null : Number(f.precio.value), disponible: f.chk.checked };
      });
    };
  }
  function montaPreciosProyecto(host, filasExistentes, proyectosLibres, precioDeCatalogo) {
    var lista = document.createElement('div');
    host.appendChild(lista);
    if (!filasExistentes.length) {
      var p = document.createElement('p');
      p.style.cssText = 'margin:0 0 6px;font-size:12px;color:' + CAJ.apagado;
      p.textContent = 'Este modelo no está declarado en ningún proyecto.';
      lista.appendChild(p);
    }
    var filas = filasExistentes.map(function (r) {
      var f = document.createElement('div');
      f.style.cssText = 'display:grid;grid-template-columns:1fr 120px;gap:6px;align-items:center;margin-bottom:6px';
      var nom = document.createElement('span'); nom.textContent = r.proyecto; nom.style.cssText = 'font-size:13px;font-weight:600;color:' + CAJ.tinta;
      var precio = numIn(precioDeCatalogo != null ? 'hereda ' + precioDeCatalogo : 'hereda —');
      precio.value = r.precio_construccion == null ? '' : r.precio_construccion;
      f.appendChild(nom); f.appendChild(precio);
      lista.appendChild(f);
      return { id: r.id, precio: precio };
    });
    var sel = document.createElement('select');
    sel.style.cssText = 'width:100%;padding:7px 9px;border:1px solid ' + CAJ.borde + ';border-radius:8px;font-size:12.5px;margin-top:4px' + flechaSelect;
    var opBlank = document.createElement('option'); opBlank.value = ''; opBlank.textContent = 'Añadir a un proyecto…';
    sel.appendChild(opBlank);
    proyectosLibres.forEach(function (nombre) {
      var o = document.createElement('option'); o.value = nombre; o.textContent = nombre; sel.appendChild(o);
    });
    host.appendChild(sel);
    return function () {
      return {
        filas: filas.map(function (f) { return { id: f.id, precio: f.precio.value === '' ? null : Number(f.precio.value) }; }),
        nuevoProyecto: sel.value
      };
    };
  }

  /* Paso 2 de «Registrar avance técnico»: fase (del catálogo obra_fases, no
     texto libre — antes se podia escribir cualquier cosa) + fecha, ya con el
     valor ACTUAL de la unidad elegida, más su gestor de fotos. «Guardar» solo
     escribe fase/fecha (por obra_actualizar, igual que antes); las fotos se
     suben/borran en el momento, como en /intranet/obra/. */
  function abreAvanceUnidad(sb, u, fases) {
    if (!u) return aviso('Esa unidad ya no está en la lista — vuelve a intentarlo.', '#8A6A34');
    modal('Registrar avance técnico', [
      { k: '_ctx', tipo: 'lectura', label: 'Unidad', valor: u.codigo + ' · ' + (u.proyecto || '—') },
      { k: 'fase', label: 'Fase actual', tipo: 'select', valor: u.obra_fase || '',
        opciones: [['', '— sin empezar —']].concat(fases.map(function (f) { return [f.clave, f.orden + '. ' + f.es]; })) },
      { k: 'fecha', label: 'Entrega estimada', tipo: 'date', valor: u.obra_fecha_entrega || '' },
      { k: 'fotos', tipo: 'custom', render: function (d) { montaFotosObra(d, sb, u.id); } }
    ], 'Guardar', function (v) {
      // por la RPC de la suite, nunca UPDATE a pelo (revision previa, Datos)
      return sb.rpc('obra_actualizar', { p_unidad: u.id, p_fase: v.fase || null, p_fecha: v.fecha || null });
    });
  }

  /* ---------- Reparto de cuentas de cobro: la matriz «ofrece / precargada» ----------
     (18-sep-2026) El widget que le faltaba a la v4 para que /v4/cuentas/ deje de
     ser una pantalla de solo mirar. Lo usan los tres editores de esa pantalla —
     por contrato, por proyecto (una vez por bloque) y por cuenta— porque las tres
     son la MISMA decision leida en tres sentidos.

     Dos reglas que no se ven en el marcado y por las que esto no es un
     `multicheck` cualquiera:

     · «precargada» solo tiene sentido sobre una cuenta OFRECIDA. Al desmarcar la
       casilla, su radio se apaga; y si era la precargada, la precarga cae sola a
       «ninguna» — precargar una cuenta que el desplegable ya no ofrece imprimiria
       un destino de pago imposible de elegir.
     · «ninguna precargada» EXISTE como opcion. Un radio no se desmarca solo, y
       quitar la precarga sin quitar la cuenta es una cosa que hay que poder
       hacer (es lo correcto salvo que el documento cobre siempre en el mismo
       sitio).

     El estado no se guarda al vuelo casilla a casilla como en /intranet/cuentas/:
     aqui el cajon es un formulario y se aplica el DIFF al guardar. Es la lengua
     de la v4 —un cajon, un boton— y ademas deja cancelar. Lo que no cambia es que
     cada escritura se verifica contra las filas devueltas (`verifica`). */
  var REPARTO_N = 0;
  function montaReparto(host, items, sel, opts) {
    opts = opts || {};
    var grupo = 'lwrep' + (++REPARTO_N);
    var caja = document.createElement('div');
    caja.style.cssText = 'background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde +
      ';border-radius:12px;padding:12px 14px;margin:0 0 10px';
    var cab = '';
    if (opts.titulo) {
      cab = '<div style="font-weight:600;font-size:13px;color:' + CAJ.tinta + ';margin-bottom:2px">' + esc(opts.titulo) + '</div>';
    }
    if (opts.sub) {
      cab += '<div style="font-weight:400;font-size:12px;color:#8A8474;margin-bottom:10px">' + esc(opts.sub) + '</div>';
    }
    var filaEstilo = 'display:flex;align-items:center;gap:9px;padding:6px 0;font-weight:500;font-size:13px;color:' + CAJ.tinta;
    caja.innerHTML = cab +
      '<div data-e="filas">' + items.map(function (it) {
        var on = !!(sel.claves && sel.claves[it.clave]);
        var esDef = sel.def === it.clave;
        return '<div style="' + filaEstilo + (on ? '' : ';opacity:.6') + '" data-fila="' + esc(it.clave) + '">' +
          '<input type="checkbox" data-ofrece="' + esc(it.clave) + '"' + (on ? ' checked' : '') + '>' +
          '<span style="flex:1;min-width:0">' + esc(it.label) +
            (it.escrow ? ' <span style="font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;color:#42210B">escrow</span>' : '') +
            (it.activa === false ? ' <span style="font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;color:#8A8474">de baja</span>' : '') +
            (it.peligro ? ' <span title="' + esc(it.peligro) + '">⚠️</span>' : '') +
          '</span>' +
          '<label style="display:flex;gap:5px;align-items:center;font-size:12px;color:#8A8474;white-space:nowrap">' +
            '<input type="radio" name="' + grupo + '" data-def="' + esc(it.clave) + '"' +
              (esDef ? ' checked' : '') + (on ? '' : ' disabled') + '>precargada</label>' +
        '</div>';
      }).join('') + '</div>' +
      '<label style="' + filaEstilo + ';border-top:1px solid ' + CAJ.borde + ';margin-top:6px;padding-top:9px;color:#8A8474">' +
        '<input type="radio" name="' + grupo + '" data-def="">' +
        '<span>Ninguna precargada — se elige en cada contrato</span></label>' +
      '<p data-e="estado" style="margin:8px 0 0;font-weight:400;font-size:12px;line-height:1.45"></p>';
    host.appendChild(caja);

    var sinDef = caja.querySelector('[data-def=""]');
    if (!sel.def) sinDef.checked = true;

    function repinta() {
      var n = 0;
      caja.querySelectorAll('[data-ofrece]').forEach(function (ch) {
        var fila = ch.closest('[data-fila]');
        var rad = fila.querySelector('[data-def]');
        fila.style.opacity = ch.checked ? '' : '.6';
        rad.disabled = !ch.checked;
        if (!ch.checked && rad.checked) { rad.checked = false; sinDef.checked = true; }
        if (ch.checked) n++;
      });
      var def = caja.querySelector('[data-def]:checked');
      var p = caja.querySelector('[data-e="estado"]');
      if (!n) {
        /* El unico estado de esta pantalla que rompe un contrato de verdad: el
           agente lo abre y se encuentra vacio el desplegable donde va el destino
           del dinero. Se dice en rojo y en el sitio, no al guardar. */
        p.style.color = '#9E2F26';
        p.textContent = opts.vacioOk
          ? 'Sin ninguna marcada: hereda el reparto general (que es lo normal).'
          : 'No ofrecerá NINGUNA cuenta: quien abra el documento se encuentra el desplegable de destino de pago vacío.';
        if (opts.vacioOk) p.style.color = '#8A8474';
      } else {
        p.style.color = '#8A8474';
        p.textContent = n + (n === 1 ? ' cuenta ofrecida · ' : ' cuentas ofrecidas · ') +
          (def && def.getAttribute('data-def') ? 'precargada: ' + (nombreItem(items, def.getAttribute('data-def'))) : 'sin precargada');
      }
      if (typeof opts.alCambiar === 'function') opts.alCambiar();
    }
    caja.addEventListener('change', repinta);
    repinta();

    return function lee() {
      var claves = [];
      caja.querySelectorAll('[data-ofrece]:checked').forEach(function (ch) { claves.push(ch.getAttribute('data-ofrece')); });
      var d = caja.querySelector('[data-def]:checked');
      var def = d ? d.getAttribute('data-def') : '';
      return { claves: claves, def: def && claves.indexOf(def) !== -1 ? def : null };
    };
  }
  function nombreItem(items, clave) {
    for (var i = 0; i < items.length; i++) if (items[i].clave === clave) return items[i].label;
    return clave;
  }

  /* 0 FILAS SIN ERROR = LA RLS LO PARO EN SILENCIO, y es el desenlace caro de esta
     pantalla: sin esto, a un admin que no es super admin el cajon le diria
     «guardado» sin haber guardado nada, y se iria creyendo que la cuenta de cobro
     del comprador es otra. Medido contra la base en /intranet/cuentas/: como
     agente el update afecta 0 filas y NO lanza; como super admin afecta 1.
     `modal()` solo mira `r.error`, asi que la traduccion se hace aqui. */
  function verifica(p, queNoPaso) {
    return Promise.resolve(p).then(function (r) {
      if (r && r.error) return r;
      if (!r || !r.data || !r.data.length) {
        /* CERO filas tiene DOS causas y desde fuera no se distinguen: la RLS te
           deniega, o la fila ya no estaba (otro super admin la movio antes). Se
           dicen las dos — afirmar solo la primera mandaba a pedir permisos a quien
           ya los tiene. La pantalla se refresca al volver de aqui, asi que reabrir
           el cajon enseña como esta de verdad. */
        return { error: { message: queNoPaso + ': o no tienes permiso (el gate es la policy es_super_admin, no esta pantalla), o alguien lo cambió antes que tú. Se ha refrescado la pantalla — cierra el cajón y vuelve a abrirlo para ver cómo está ahora.' } };
      }
      return r;
    });
  }
  // encadena escrituras y se para en la primera que falle, devolviendo su error
  function enCadena(pasos) {
    return pasos.reduce(function (prev, paso) {
      return prev.then(function (acc) {
        if (acc && acc.error) return acc;
        return Promise.resolve(paso()).then(function (r) { return (r && r.error) ? r : null; });
      });
    }, Promise.resolve(null));
  }

  /* El DIFF de un reparto contra lo que hay en la base. `base` son las columnas
     que identifican el nivel (`{slug}` para plantilla_cuentas, `{proyecto_id,
     slug}` para proyecto_cuentas) y se reusan tal cual en el filtro y en el
     insert — una sola definicion, no dos listas a mano que puedan separarse. */
  function guardaReparto(sb, tabla, base, antes, ahora) {
    var antesClaves = antes.map(function (x) { return x.clave; });
    var antesDef = (antes.filter(function (x) { return x.es_default; })[0] || {}).clave || null;
    var quitar = antesClaves.filter(function (c) { return ahora.claves.indexOf(c) === -1; });
    var poner = ahora.claves.filter(function (c) { return antesClaves.indexOf(c) === -1; });
    var filtro = function (qq) {
      Object.keys(base).forEach(function (k) { qq = qq.eq(k, base[k]); });
      return qq;
    };
    var pasos = [];
    quitar.forEach(function (c) {
      pasos.push(function () {
        return verifica(filtro(sb.from(tabla).delete()).eq('clave', c).select('clave'),
                        'No se pudo quitar «' + c + '»');
      });
    });
    poner.forEach(function (c) {
      var fila = { clave: c };
      Object.keys(base).forEach(function (k) { fila[k] = base[k]; });
      pasos.push(function () {
        return verifica(sb.from(tabla).insert(fila).select('clave'), 'No se pudo añadir «' + c + '»');
      });
    });
    if (ahora.def && ahora.def !== antesDef) {
      /* El trigger (`un_solo_default_por_plantilla` / `..._por_proyecto`)
         desmarca sola a la anterior: por eso aqui no hay dos sentencias en
         orden, y por eso la garantia es un trigger y no un indice unico parcial
         (que no sirve para ON CONFLICT, 42P10). */
      pasos.push(function () {
        return verifica(filtro(sb.from(tabla).update({ es_default: true })).eq('clave', ahora.def).select('clave'),
                        'No se pudo marcar la precargada');
      });
    } else if (!ahora.def && antesDef && ahora.claves.indexOf(antesDef) !== -1) {
      /* «Ninguna precargada» va explicita y acotada a este nivel: no hay trigger
         que desmarque —el trigger solo garantiza que no haya dos—. Si la que
         estaba precargada se ha QUITADO del reparto, ya no hay fila que
         desmarcar y este paso sobra (de ahi el tercer condicional). */
      pasos.push(function () {
        return verifica(filtro(sb.from(tabla).update({ es_default: false })).eq('es_default', true).select('clave'),
                        'No se pudo quitar la precarga');
      });
    }
    if (!pasos.length) return Promise.resolve(null);
    return enCadena(pasos);
  }

  /* El mismo reparto visto DESDE LA CUENTA: aqui lo fijo es la cuenta y lo que
     varia es el contrato — al reves que `montaReparto`. No se funden en una:
     pedirian un parametro de "sentido" que habria que leer dos veces cada vez
     que se toque esto, y ademas aqui «precargada» es una casilla y no un radio
     (cada contrato tiene la suya, no compiten entre si).

     Devuelve SOLO los contratos en los que algo cambia, ya en la forma que
     `guardaReparto` espera. */
  function montaRepartoPorCuenta(host, d, clave) {
    var filasDe = function (slug) { return d.reparto.filter(function (x) { return x.slug === slug; }); };
    /* Los que cobran y se siguen ofreciendo, mas cualquiera donde esta cuenta ya
       este marcada aunque este archivado: si no, una fila que existe en la base
       desaparece de la pantalla y no hay como quitarla. */
    var pls = d.plantillas.filter(function (p) {
      var marcada = filasDe(p.slug).some(function (x) { return x.clave === clave; });
      return (p.cobra && !p.archivada) || marcada;
    });
    var caja = document.createElement('div');
    caja.style.cssText = 'background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde +
      ';border-radius:12px;padding:12px 14px;margin:0';
    var etqDe = function (cl) {
      var c = d.cuentas.filter(function (x) { return x.clave === cl; })[0];
      return c ? (c.label || c.clave) : cl;
    };
    caja.innerHTML = '<div style="font-weight:600;font-size:13px;color:' + CAJ.tinta + ';margin-bottom:10px">En qué contratos se ofrece esta cuenta</div>' +
      (!pls.length ? '<div style="font-weight:400;font-size:12px;color:#8A8474">Ningún tipo de contrato cobra. Nada que repartir.</div>'
        : pls.map(function (p) {
            var filas = filasDe(p.slug);
            var marcada = filas.some(function (x) { return x.clave === clave; });
            var esDef = filas.some(function (x) { return x.clave === clave && x.es_default; });
            var otraDef = filas.filter(function (x) { return x.es_default && x.clave !== clave; })[0];
            /* Cuantas cuentas ofrece HOY este contrato, en su propia fila: es lo
               que contesta «¿puedo quitar esta sin dejarlo sin ninguna?» sin
               abrir las otras quince fichas. */
            /* `otras` = las que ofrece SIN contar esta, para poder recalcular la
               pista en vivo al marcar y desmarcar. Antes se calculaba una sola vez
               al abrir: decia «2 cuentas» mientras la dejabas en 0, y este era el
               UNICO camino que llegaba a dejar un contrato que cobra sin ninguna
               cuenta y sin el aviso rojo que si trae `montaReparto` — justo lo que
               el panel existe para evitar, por la puerta de atras (Desarrollo,
               consulta de deploy del 18-sep). */
            var otras = filas.filter(function (x) { return x.clave !== clave; }).length;
            return '<div data-pl="' + esc(p.slug) + '" data-cobra="' + (p.cobra ? '1' : '0') + '"' +
              ' data-otras="' + otras + '" data-otradef="' + esc(otraDef ? etqDe(otraDef.clave) : '') + '"' +
              ' style="padding:8px 0;border-top:1px solid ' + CAJ.borde + '">' +
              '<div style="font-weight:500;font-size:13px;color:' + CAJ.tinta + '">' + esc(p.nombre || p.slug) +
                (p.archivada ? ' <span style="font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;color:#8A8474">archivado</span>' : '') + '</div>' +
              '<div data-e="pista" style="font-weight:400;font-size:12px;margin:1px 0 5px"></div>' +
              '<div style="display:flex;gap:16px;align-items:center;font-weight:500;font-size:12.5px;color:' + CAJ.tinta + '">' +
                '<label style="display:flex;gap:6px;align-items:center"><input type="checkbox" data-ofrece' +
                  (marcada ? ' checked' : '') + '>se ofrece aquí</label>' +
                '<label style="display:flex;gap:6px;align-items:center;color:#8A8474"><input type="checkbox" data-pre' +
                  (esDef ? ' checked' : '') + (marcada ? '' : ' disabled') + '>precargada</label>' +
              '</div></div>';
          }).join(''));
    host.appendChild(caja);

    function repintaFilas() {
      caja.querySelectorAll('[data-pl]').forEach(function (fila) {
        var of = fila.querySelector('[data-ofrece]'), pre = fila.querySelector('[data-pre]');
        pre.disabled = !of.checked;
        // precargar una cuenta que el contrato ya no ofrece imprimiria un destino
        // de pago que su propio desplegable no admite
        if (!of.checked) pre.checked = false;
        var n = Number(fila.getAttribute('data-otras')) + (of.checked ? 1 : 0);
        var cobra = fila.getAttribute('data-cobra') === '1';
        var otraDef = fila.getAttribute('data-otradef');
        var t = fila.querySelector('[data-e="pista"]');
        if (!n) {
          t.textContent = cobra
            ? 'Se quedaría sin NINGUNA cuenta: quien abra el documento encuentra vacío el desplegable de destino de pago.'
            : 'no ofrece ninguna cuenta';
          t.style.color = cobra ? '#9E2F26' : '#8A8474';
        } else {
          t.style.color = '#8A8474';
          t.textContent = n + (n === 1 ? ' cuenta · ' : ' cuentas · ') +
            (pre.checked ? 'precargada: esta' : otraDef ? 'precargada: ' + otraDef : 'sin precargada');
        }
      });
    }
    caja.addEventListener('change', repintaFilas);
    repintaFilas();

    return function lee() {
      var cambios = [];
      caja.querySelectorAll('[data-pl]').forEach(function (fila) {
        var slug = fila.getAttribute('data-pl');
        var of = fila.querySelector('[data-ofrece]').checked;
        var pre = fila.querySelector('[data-pre]').checked;
        var antes = filasDe(slug);
        var antesClaves = antes.map(function (x) { return x.clave; });
        var antesDef = (antes.filter(function (x) { return x.es_default; })[0] || {}).clave || null;
        var ahoraClaves = of
          ? (antesClaves.indexOf(clave) === -1 ? antesClaves.concat([clave]) : antesClaves)
          : antesClaves.filter(function (x) { return x !== clave; });
        var ahoraDef = pre ? clave
          : (antesDef === clave ? null : (ahoraClaves.indexOf(antesDef) !== -1 ? antesDef : null));
        if (of === (antesClaves.indexOf(clave) !== -1) && ahoraDef === antesDef) return;  // nada que hacer
        cambios.push({ slug: slug, antes: antes, ahora: { claves: ahoraClaves, def: ahoraDef } });
      });
      return cambios;
    };
  }

  /* ---------- editores por pantalla ---------- */
  var ED = {

    modelos: function (aut) {
      var sb = aut.sb, admin = esAdmin(aut.ficha);
      var soloAdmin = function () { aviso('La familia de modelos la escribe solo administración (policy es_admin) — tu sesión es de ' + ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34'); };
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
      /* «Editar datos» carga primero las CUATRO tablas hijas de la ficha
         (techos, extras del catálogo + los del modelo, precio por proyecto y
         los proyectos aún libres) y las monta como campos `custom` del MISMO
         formulario — un solo «Guardar cambios» escribe la ficha y las tres
         sub-tablas seguidas, igual que condiciones+tramos de arriba. Sin esto
         el modal solo tocaba los 9 campos planos y las funciones montaX()
         quedaban sin ningún sitio que las llamara. */
      // Evita el doble-fetch de un doble-click mientras las 5 consultas de
      // abajo siguen en vuelo — ata() no debounda y el click no da feedback.
      var cargandoFichaModelo = false;
      ata(/^Editar datos$/i, function () {
        if (!admin) return soloAdmin();
        if (cargandoFichaModelo) return;
        var m = window.LW_V4 && window.LW_V4.modelo;
        if (!m) return aviso('La ficha del modelo aún no ha cargado.', '#8A6A34');
        cargandoFichaModelo = true;
        Promise.all([
          sb.from('modelo_techos').select('id,nombre,precio_ahora,precio_2027').eq('modelo_id', m.id).order('orden', { ascending: true, nullsFirst: false }),
          sb.from('extras').select('id,nombre').eq('activo', true).order('orden', { ascending: true, nullsFirst: false }),
          sb.from('modelo_extras').select('id,extra_id,precio,disponible').eq('modelo_id', m.id),
          sb.from('modelos_villa').select('id,proyecto,precio_construccion').eq('modelo_id', m.id).order('proyecto'),
          sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre')
        ]).then(function (r) {
          cargandoFichaModelo = false;
          // Una lectura fallida NO se trata como «sin filas»: con las tablas
          // vacías por error, proyectosLibres podría ofrecer un proyecto que
          // YA tiene fila (el unique(proyecto,modelo) de modelos_villa lo
          // rechazaría con un error crudo) y techos/extras se verían vacíos
          // aunque sí tengan datos — mejor decir que no se pudo leer.
          var falloLectura = r.filter(function (x) { return x && x.error; })[0];
          if (falloLectura) {
            return aviso('No se pudo abrir «Editar datos»: ' + falloLectura.error.message, '#93000a');
          }
          var techos = r[0].data || [];
          var extras = r[1].data || [];
          var extrasExistentes = r[2].data || [];
          var villaFilas = r[3].data || [];
          var proyectos = r[4].data || [];
          var usados = {}; villaFilas.forEach(function (f) { usados[f.proyecto] = 1; });
          var proyectosLibres = proyectos.filter(function (p) { return !usados[p.nombre]; }).map(function (p) { return p.nombre; });
          var idPorProyecto = {}; proyectos.forEach(function (p) { idPorProyecto[p.nombre] = p.id; });

          var subtitulo = function (d, texto) {
            var t = document.createElement('p');
            t.style.cssText = 'margin:0 0 8px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:' + CAJ.apagado;
            t.textContent = texto;
            d.appendChild(t);
          };
          var getTechos = null, getExtras = null, getPrecios = null;
          var incluidoActual = (m.alcance && m.alcance.incluido) || [];
          var noIncluidoActual = (m.alcance && m.alcance.no_incluido) || [];

          modal('Editar «' + m.nombre + '»', [
            { k: 'dormitorios', label: 'Dormitorios', tipo: 'number', valor: m.dormitorios },
            { k: 'banos', label: 'Baños', tipo: 'number', valor: m.banos },
            { k: 'villa_m2', label: 'Villa (m²)', tipo: 'number', paso: '0.01', valor: m.villa_m2 },
            { k: 'terraza_m2', label: 'Terraza (m²)', tipo: 'number', paso: '0.01', valor: m.terraza_m2 },
            { k: 'precio', label: 'Precio de construcción (' + (m.moneda || 'EUR') + ')', tipo: 'number', paso: '0.01', valor: m.precio_construccion },
            { k: 'descripcion', label: 'Descripción (la publica la web)', tipo: 'textarea', valor: m.descripcion },
            { k: 'publicado', label: 'Publicado en la web', tipo: 'check', valor: m.publicado, ayuda: 'al marcarlo, la web pública lo enseña con esta ficha y este precio' },
            { k: 'renders_pendientes', label: 'Renders pendientes', tipo: 'check', valor: m.renders_pendientes },
            { k: 'activo', label: 'Activo en el catálogo', tipo: 'check', valor: m.activo },
            { k: 'notas', label: 'Notas internas', tipo: 'textarea', valor: m.notas, ayuda: 'nunca las ve la web' },
            { k: 'alcance_incluido', label: 'La obra incluye (una línea por punto)', tipo: 'textarea', valor: incluidoActual.join('\n'),
              ayuda: 'solo lo verificado en el anexo de obra de ESTE modelo — copiarlo de otro es inventarse un contrato' },
            { k: 'alcance_no_incluido', label: 'La obra NO incluye (una línea por punto)', tipo: 'textarea', valor: noIncluidoActual.join('\n') },
            { tipo: 'custom', render: function (d) { subtitulo(d, 'Techos — precio completo con esa variante'); getTechos = montaTechosModelo(d, techos); } },
            { tipo: 'custom', render: function (d) { subtitulo(d, 'Extras del catálogo'); getExtras = montaExtrasModelo(d, extras, extrasExistentes); } },
            { tipo: 'custom', render: function (d) { subtitulo(d, 'Precio de construcción por proyecto'); getPrecios = montaPreciosProyecto(d, villaFilas, proyectosLibres, m.precio_construccion); } }
          ], 'Guardar cambios', function (v) {
            var lineas = function (s) { return String(s || '').split('\n').map(function (x) { return x.trim(); }).filter(Boolean); };
            var incluido = lineas(v.alcance_incluido), noIncluido = lineas(v.alcance_no_incluido);
            var alcance = (incluido.length || noIncluido.length) ? { incluido: incluido, no_incluido: noIncluido } : null;
            // Valores de ANTES de este guardado — si la ficha se actualiza pero
            // alguna sub-tabla falla, se restauran para no dejar la ficha a
            // medias mientras el aviso dice «no se pudo guardar» (mismo
            // espíritu que «Nueva condición» borrando la fila huérfana cuando
            // fallan sus tramos, más arriba en este mismo fichero).
            var previo = {
              dormitorios: m.dormitorios, banos: m.banos, villa_m2: m.villa_m2, terraza_m2: m.terraza_m2,
              precio_construccion: m.precio_construccion, descripcion: m.descripcion, notas: m.notas,
              alcance: m.alcance, publicado: m.publicado, renders_pendientes: m.renders_pendientes, activo: m.activo
            };

            return sb.from('modelos').update({
              dormitorios: v.dormitorios === '' ? null : Number(v.dormitorios),
              banos: v.banos === '' ? null : Number(v.banos),
              villa_m2: v.villa_m2 === '' ? null : Number(v.villa_m2),
              terraza_m2: v.terraza_m2 === '' ? null : Number(v.terraza_m2),
              precio_construccion: v.precio === '' ? null : Number(v.precio),
              descripcion: v.descripcion || null,
              notas: v.notas || null,
              alcance: alcance,
              publicado: v.publicado, renders_pendientes: v.renders_pendientes, activo: v.activo
            }).eq('id', m.id).then(function (r0) {
              if (r0.error) return r0;
              var tareas = [];
              (getTechos ? getTechos() : []).forEach(function (t) {
                tareas.push(sb.from('modelo_techos').update({ precio_ahora: t.precio_ahora, precio_2027: t.precio_2027 }).eq('id', t.id));
              });
              (getExtras ? getExtras() : []).forEach(function (e) {
                if (e.existenteId) {
                  tareas.push(sb.from('modelo_extras').update({ precio: e.precio, disponible: e.disponible }).eq('id', e.existenteId));
                } else if (e.precio != null || !e.disponible) {
                  // sin fila = «se ofrece, precio de catálogo» (montaExtrasModelo); solo se
                  // crea fila cuando hay algo que decir que el default no cubre.
                  tareas.push(sb.from('modelo_extras').insert({ modelo_id: m.id, extra_id: e.extraId, precio: e.precio, disponible: e.disponible }));
                }
              });
              var precios = getPrecios ? getPrecios() : { filas: [], nuevoProyecto: '' };
              precios.filas.forEach(function (f) {
                tareas.push(sb.from('modelos_villa').update({ precio_construccion: f.precio }).eq('id', f.id));
              });
              if (precios.nuevoProyecto) {
                // solo `modelo_id`: trg_espejo_modelo rellena el texto `modelo` espejo
                // antes del INSERT (dispara en todo INSERT, la lista de columnas del
                // trigger solo acota los UPDATE — verificado contra la migración).
                tareas.push(sb.from('modelos_villa').insert({
                  proyecto: precios.nuevoProyecto, proyecto_id: idPorProyecto[precios.nuevoProyecto] || null,
                  modelo_id: m.id, precio_construccion: null, moneda: m.moneda || 'EUR'
                }));
              }
              return Promise.all(tareas).then(function (rs) {
                var conError = rs.filter(function (x) { return x && x.error; })[0];
                if (!conError) return { error: null };
                return sb.from('modelos').update(previo).eq('id', m.id).then(function () {
                  return { error: conError.error };
                });
              });
            });
          });
        }, function (e) {
          cargandoFichaModelo = false;
          aviso('No se pudo abrir «Editar datos»: ' + (e && e.message || e), '#93000a');
        });
      });
      ata(/^Añadir documento$/i, function () {
        // subir un fichero exige el bucket de almacenamiento: es el único paso
        // de esta pantalla que sigue en la herramienta viva, dicho en voz alta
        aviso('La subida de ficheros vive aún en /intranet/modelos/ (necesita el bucket). Todo lo demás de esta pantalla ya es nativo.', '#8A6A34');
        setTimeout(function () { location.href = '/intranet/modelos/'; }, 1600);
      });
    },

    /* Comisiones (antes «Solicitudes», renombrada 14-sep-2026). La pestaña «A
       Lawang» sigue siendo solo lectura — su escritura real vive en
       /intranet/solicitudes/, con la máquina de estados en la base. Lo único
       nativo de aquí es «Marcar pagada» en «Reparto de equipo»: un UPDATE
       directo sobre `comisiones_devengadas`, con la policy (manager del
       equipo, o admin) como único gate — esta pantalla solo la refleja
       (datos.js decide si enseñar el botón; la policy decide si el UPDATE
       cuaja). */
    comisiones: function (aut) {
      var sb = aut.sb;
      var miEmail = (aut.session && aut.session.user && aut.session.user.email) || '';
      window.LW_V4 = window.LW_V4 || {};
      window.LW_V4.marcarComisionPagada = function (id, etiqueta) {
        modal('Marcar pagada — ' + (etiqueta || 'closer'), [
          { tipo: 'nota', label: 'Confirmas que ya se le ha pagado a ' + (etiqueta || 'este closer') +
            ' POR TU CUENTA, como manager del equipo — Lawang no interviene en este pago ni lo tramita. ' +
            'Quedará registrado como pagado, con tu email y la fecha de hoy.' }
        ], 'Confirmar: pagada', function () {
          return sb.from('comisiones_devengadas').update({
            estado: 'pagada', pagado_por: miEmail, pagado_en: new Date().toISOString()
          }).eq('id', id).select('id').then(unaFila);   // 0 filas = la policy no deja (19-sep-2026)
        });
      };
    },

    proyectos: function (aut) {
      var sb = aut.sb;
      var ficha = aut.ficha;
      var esAdminP = esAdmin(ficha);
      var esSuper = !!(ficha && ficha.rol === 'super_admin');
      /* Dar de alta un proyecto es de dirección (LAW-177, 11-sep-2026): la RLS
         de INSERT en `proyectos` exige es_admin(). Se esconde el botón aquí, en
         cuanto se sabe el rol y ANTES de que nadie pueda pulsarlo — mismo patrón
         que /intranet/proyectos/ (LAW-179: esta pantalla se quedó sin el mismo
         parche el 11-sep porque la otra sesión tenía v4 en vuelo). */
      if (!esAdminP) {
        var altaP = document.getElementById('btn-nuevo-proyecto');
        if (altaP) altaP.hidden = true;
      }
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
          var p = proyecto(); if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
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
          var p = proyecto(); if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
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

      /* Estado y obra (17-sep-2026, encargo del owner). Gobierna las tres cosas
         que deciden si un proyecto puede empezar a cobrar por obra: en qué
         estado está, qué porcentaje de venta exige para arrancar, y cuántos
         días pasan entre avanzar una fase y su cobro.

         Por qué NO es un campo más de "Editar proyecto": el estado no se guarda
         con un UPDATE. Va por `proyecto_cambiar_estado()`, que valida el umbral,
         exige motivo escrito para saltárselo y deja rastro en `proyecto_eventos`.
         Meterlo en el formulario general lo convertiría en un campo cualquiera y
         se perdería todo eso. Mismo criterio que el avance de obra por RPC. */
      ata(/^Estado y obra$/i, function () {
        var p = proyectoObj();
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
        if (!esAdminP)
          return aviso('Cambiar el estado de un proyecto es cosa de admin (la policy es es_admin(), no esta pantalla).', '#8A6A34');

        Promise.all([
          sb.rpc('proyecto_pct_vendido', { p_proyecto_id: p.id }),
          sb.from('proyecto_plazo_pago').select('orden_pago,dias').eq('proyecto_id', p.id).order('orden_pago'),
          sb.from('proyecto_eventos').select('evento,detalle,quien,creado_en')
            .eq('proyecto_id', p.id).order('creado_en', { ascending: false }).limit(5)
        ]).then(function (rs) {
          var pct = Number((rs[0] && rs[0].data) || 0);
          var plazos = (rs[1] && rs[1].data) || [];
          var eventos = (rs[2] && rs[2].data) || [];
          var umbral = Number(p.pct_minimo_inicio);
          var llega = pct >= umbral;

          var ESTADOS = (window.LW_V4 && window.LW_V4.proyEstados) || {
            en_venta: 'En venta', no_disponible: 'No disponible',
            en_construccion: 'En construcción', construido: 'Construido',
            finalizado: 'Finalizado', gestionado: 'Gestionado',
            stand_by: 'Stand-by', cedido: 'Cedido'
          };
          var opciones = Object.keys(ESTADOS).map(function (k) { return [k, ESTADOS[k]]; });

          var porPago = {};
          plazos.forEach(function (x) { porPago[x.orden_pago] = x.dias; });
          var NOMBRE_PAGO = {
            1: '1 · Preparación del terreno', 2: '2 · Estructura',
            3: '3 · Instalaciones', 4: '4 · Acabados', 5: '5 · Revisión y entrega'
          };

          var campos = [
            { tipo: 'lectura', medio: 1, label: 'Vendido ahora mismo',
              valor: pct.toFixed(1).replace('.0', '') + '% (cuenta vendidas, cobradas y bloqueadas)' },
            { tipo: 'lectura', medio: 1, label: 'Hace falta para iniciar obra', valor: umbral + '%' },
            { k: 'estado', tipo: 'select', label: 'Estado del proyecto',
              opciones: opciones, valor: p.estado || 'en_venta',
              ayuda: 'Solo «En construcción» hace que un avance de obra dispare cobros.' }
          ];

          if (!llega) {
            campos.push({ tipo: 'nota', label: 'Este proyecto todavía no llega al ' + umbral +
              '% de venta. Puedes pasarlo a «En construcción» igualmente, pero hace falta escribir el motivo aquí abajo y queda registrado con tu nombre y la fecha.' });
            campos.push({ k: 'motivo', label: 'Motivo para iniciar por debajo del umbral',
              ayuda: 'Solo se usa si eliges «En construcción».' });
          }

          campos.push({ k: 'umbral', tipo: 'number', medio: 1, paso: '1',
            label: 'Cambiar el % que exige este proyecto', valor: umbral });

          for (var i = 1; i <= 5; i++) {
            campos.push({ k: 'dias' + i, tipo: 'number', medio: 1, paso: '1',
              label: 'Días hasta el cobro · pago ' + NOMBRE_PAGO[i],
              valor: porPago[i] == null ? '' : porPago[i],
              ayuda: i === 1 ? 'Días desde que se avanza la fase hasta que vence su cobro. En blanco = sin configurar; entonces habrá que escribirlo a mano en cada avance.' : '' });
          }

          if (eventos.length) {
            campos.push({ tipo: 'nota', label: 'Últimos movimientos: ' + eventos.map(function (e) {
              var d = e.detalle || {};
              var q = e.quien || 'alguien';
              if (e.evento === 'inicio_forzado_bajo_umbral')
                return '⚠ inicio forzado al ' + d.pct_vendido + '% por ' + q;
              return (ESTADOS[d.a] || d.a || e.evento) + ' por ' + q;
            }).join(' · ') });
          }

          modal('Estado y obra · ' + p.nombre, campos, 'Guardar', function (v) {
            var tareas = [];
            var nuevoEstado = v.estado || p.estado;

            if (nuevoEstado !== p.estado) {
              tareas.push(sb.rpc('proyecto_cambiar_estado', {
                p_proyecto_id: p.id,
                p_estado: nuevoEstado,
                // Forzar solo cuando de verdad hace falta: si llega al umbral,
                // la función no pide nada y este parámetro da igual.
                p_forzar: (nuevoEstado === 'en_construccion' && !llega),
                p_motivo: (v.motivo || '').trim() || null
              }));
            }

            var nuevoUmbral = Number(v.umbral);
            if (isFinite(nuevoUmbral) && nuevoUmbral !== umbral) {
              // El umbral sí es una columna normal de `proyectos` (no tiene
              // reglas propias), así que va por UPDATE como el resto de la ficha.
              tareas.push(sb.from('proyectos').update({ pct_minimo_inicio: nuevoUmbral })
                .eq('id', p.id).select('id'));
            }

            for (var j = 1; j <= 5; j++) {
              var bruto = v['dias' + j];
              if (bruto === '' || bruto == null) continue;
              var dias = Number(bruto);
              if (!isFinite(dias) || dias === porPago[j]) continue;
              tareas.push(sb.rpc('proyecto_fijar_plazo', {
                p_proyecto_id: p.id, p_orden_pago: j, p_dias: dias
              }));
            }

            if (!tareas.length) return Promise.resolve({ error: null });

            // Se devuelve el PRIMER error que aparezca: el modal ya sabe
            // pintarlo, y la función de la base trae el mensaje explicando por
            // qué (umbral sin motivo, estado desconocido, días fuera de rango).
            return Promise.all(tareas).then(function (rr) {
              for (var k = 0; k < rr.length; k++) if (rr[k] && rr[k].error) return rr[k];
              return { error: null };
            });
          });
        }, function (e) { aviso('No se pudo leer el estado del proyecto: ' + e, '#ba1a1a'); });
      });

      /* Editar proyecto (11-sep-2026, sincronizando v4 con lo nuevo de
         /proyectos/): ficha (resort/parcela máster), qué se puede construir
         aquí y sales/project manager, en el MISMO modal — igual que la ficha
         única del original. Tres escrituras independientes al guardar
         (proyectos, modelos_villa, un RPC por manager que cambió); que falle
         una no deshace las otras, mismo criterio que allí. */
      ata(/^Editar proyecto$/i, function () {
        var p = proyectoObj();
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
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

          // getter de montaTrimestre() -- se rellena al pintar el campo 'custom'
          // de abajo, y onGuardar lo llama para saber el trimestre elegido.
          var getEntrega;
          var campos = [
            { k: 'resort', label: 'Resort', valor: p.resort || '' },
            { k: 'parcela_master', label: 'Parcela máster (código)', valor: p.parcela_master || '' },
            // Fecha de entrega ESTIMADA del PROYECTO (16-sep-2026, encargo del
            // owner) — agregada, para el deck/marketing. Distinta a propósito
            // de unidades.obra_fecha_entrega (fecha real de obra por parcela,
            // se edita en "Editar unidad"); no se derivan la una de la otra.
            // En TRIMESTRES (owner, 16-sep-2026: "Q1 de 2027 es para el primer
            // trimestre de 2027") -- se sigue guardando como `date` (el primer
            // día del trimestre elegido), montaTrimestre() hace la conversión
            // en los dos sentidos.
            // `fecha_entrega_estimada_fijada_en` NO es un campo del formulario:
            // se sella sola con la fecha de HOY al guardar, si el valor cambia
            // — así la estimación siempre lleva escrito cuándo se fijó, sin
            // pedirle a nadie que recuerde marcarlo (regla del estudio: todo
            // dato volátil lleva su fecha).
            { tipo: 'custom', medio: 1, label: 'Entrega estimada (proyecto, no parcela)',
              render: function (d) {
                // 'custom' no lleva la tarjeta crema de los demas campos (ver el
                // renderizador generico): se reconstruye aqui, igual de forma y
                // color, para que no se note que es un widget aparte.
                d.style.cssText = 'display:grid;gap:6px;background:#f5f4ee;border:1px solid ' + CAJ.borde + ';' +
                  'border-radius:12px;padding:12px 14px;font-weight:500;font-size:12px;line-height:1.35;color:' + CAJ.apagado;
                var lbl = document.createElement('span');
                lbl.textContent = 'Entrega estimada (proyecto, no parcela)';
                d.appendChild(lbl);
                getEntrega = montaTrimestre(d, p.fecha_entrega_estimada_proyecto);
              } },
            { tipo: 'lectura', medio: 1, label: 'Estimación fijada el',
              valor: p.fecha_entrega_estimada_fijada_en || 'nunca — se sella sola al guardar una fecha' },
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
            var nuevaFecha = getEntrega ? getEntrega() : (p.fecha_entrega_estimada_proyecto || null);
            var cambioFecha = nuevaFecha !== (p.fecha_entrega_estimada_proyecto || null);
            var payloadProyecto = {
              resort: (v.resort || '').trim() || null,
              parcela_master: (v.parcela_master || '').trim() || null,
              fecha_entrega_estimada_proyecto: nuevaFecha,
            };
            // Se sella con HOY solo si la fecha realmente cambia — así queda
            // escrito CUÁNDO se fijó la estimación, sin pedirle a nadie que lo
            // recuerde (regla del estudio: todo dato volátil lleva su fecha).
            // Guardar sin tocar la fecha no re-sella nada.
            if (cambioFecha) {
              payloadProyecto.fecha_entrega_estimada_fijada_en = nuevaFecha ? new Date().toISOString().slice(0, 10) : null;
            }
            return sb.from('proyectos').update(payloadProyecto).eq('id', p.id).select('id').then(function (r) {
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
                  if (!rm.ok) aviso('La ficha sí, los modelos no: ' + rm.error, '#ba1a1a');
                  else if (rm.rechazadas.length) aviso('No se retiran ' + rm.rechazadas.map(function (x) { return x.modelo; }).join(', ') + ': hay parcelas que los usan', '#8A6A34');
                }));
              }
              if (puedeUsuarios && managers.length) {
                var marcados = v.managers || [];
                managers.forEach(function (m) {
                  var teniaAntes = (m.proyectos_supervisados || []).indexOf(p.id) !== -1;
                  var marcadoAhora = marcados.indexOf(m.user_id) !== -1;
                  if (teniaAntes === marcadoAhora) return;
                  trabajos.push(sb.rpc('usuario_supervisa_proyecto', { p_user_id: m.user_id, p_proyecto_id: p.id, p_asignar: marcadoAhora })
                    .then(function (rr) { if (rr.error) aviso('No se pudo actualizar el proyecto de ' + (m.nombre || m.email) + ': ' + rr.error.message, '#ba1a1a'); }));
                });
              }
              if (v.imagen) {
                var file = v.imagen;
                if (file.size > 8 * 1024 * 1024) {
                  aviso('La ficha sí, la foto no: pasa de 8 MB.', '#ba1a1a');
                } else {
                  var ext = (file.name.match(/\.[a-z0-9]+$/i) || [''])[0].toLowerCase();
                  var path = 'proyectos/' + p.id + '/' + crypto.randomUUID() + ext;
                  trabajos.push(
                    sb.storage.from('documentacion').upload(path, file, { contentType: file.type || undefined }).then(function (up) {
                      if (up.error) { aviso('La ficha sí, la foto no: ' + up.error.message, '#ba1a1a'); return; }
                      return sb.from('documentos_proyecto').insert({
                        proyecto: p.nombre, categoria: 'portada', titulo: 'Portada',
                        path: path, mime: file.type || null, bytes: file.size, confidencial: true
                      }).then(function (ri) {
                        if (ri.error) {
                          // fichero huérfano en el bucket sin fila: se retira,
                          // igual que hace subirDoc() en /intranet/modelos/.
                          sb.storage.from('documentacion').remove([path]);
                          aviso('La ficha sí, la foto no: ' + ri.error.message, '#ba1a1a');
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
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
        if (!esSuper) return aviso('Borrar un proyecto es solo para super_admin.', '#8A6A34');
        if (!window.confirm('Borrar el proyecto «' + p.nombre + '» del catálogo. Solo funciona si no le quedan unidades, modelos ni documentos colgando. ¿Seguro?')) return;
        sb.rpc('borrar_proyecto', { p_nombre: p.nombre }).then(function (r) {
          if (r.error) return aviso('No se pudo borrar: ' + r.error.message, '#ba1a1a');
          aviso('Proyecto borrado');
          setTimeout(function () { location.href = '/intranet/v4/proyectos/'; }, 1200);
        });
      });

      /* Nuevo proyecto (11-sep-2026): mismo alcance que altaProyecto() en
         /proyectos/ — solo el nombre. Resort/parcela máster se añaden después
         desde "Editar proyecto". LAW-179 (14-sep, corregido): la RLS de INSERT
         en `proyectos` exige es_admin() desde LAW-177 (11-sep) — este comentario
         decía "sin gate de rol" y estaba desactualizado. El botón ya se esconde
         arriba en cuanto se conoce el rol; este corte es el cinturón — llega
         aquí solo si alguien dispara el click sin pasar por esa pintura. */
      var bNuevoP = document.getElementById('btn-nuevo-proyecto');
      if (bNuevoP) bNuevoP.addEventListener('click', function (ev) {
        ev.stopPropagation();
        if (!esAdminP) return aviso('Dar de alta un proyecto es cosa de un administrador. Pídeselo a dirección.', '#8A6A34');
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
        aviso('Abriendo formulario…');
        Promise.all([
          sb.from('proyectos').select('nombre').eq('activo', true).order('nombre'),
          sb.from('tipos_vivienda').select('clave,etiqueta').eq('activo', true).order('etiqueta'),
          (typeof lwCargarCatalogoModelos === 'function')
            ? lwCargarCatalogoModelos(sb) : Promise.resolve({ catalogo: [], villas: [] })
        ]).then(function (rs) {
          // Hallazgo de Desarrollo en la consulta de deploy: sin este chequeo,
          // un fallo de red o de RLS abría el modal en silencio con los
          // desplegables vacíos — el botón parecía "no hacer nada".
          if (rs[0].error) return aviso('No se pudo abrir: ' + rs[0].error.message, '#ba1a1a');
          if (rs[1].error) return aviso('No se pudo abrir: ' + rs[1].error.message, '#ba1a1a');
          var proyectos = ((rs[0] && rs[0].data) || []).map(function (p) { return p.nombre; });
          var tipos = ((rs[1] && rs[1].data) || []).map(function (t) { return [t.clave, t.etiqueta]; });
          if (!proyectos.length) return aviso('No hay ningún proyecto dado de alta todavía — crea uno con «+ Nuevo proyecto» primero.', '#8A6A34');
          var actual = proyectoObj();
          var proyectoDefecto = (actual && actual.nombre) || proyectos[0];
          var cat = rs[2] || { catalogo: [], villas: [] };
          // igual que en editarUnidad(): el modelo sale del catálogo real del
          // proyecto por defecto, nunca texto libre si hay catálogo (8-sep-2026)
          var mods = (typeof lwModelosDeProyecto === 'function')
            ? lwModelosDeProyecto(proyectoDefecto, cat.villas, cat.catalogo) : { lista: [], declarados: false };
          var camposU = [
            { k: 'proyecto', label: 'Proyecto', tipo: 'select', req: 1, medio: 1, opciones: proyectos, valor: proyectoDefecto },
            { k: 'codigo', label: 'Código', req: 1, medio: 1, ayuda: 'Debe coincidir con el que se escribe en el contrato: es lo que permite cruzarlos.' },
            { k: 'tipo', label: 'Tipo', tipo: 'select', medio: 1, opciones: tipos.length ? tipos : [['parcela', 'Parcela']], valor: 'parcela' }
          ];
          if (mods.lista.length) {
            camposU.push({ k: 'modelo', label: 'Modelo de villa', tipo: 'select', medio: 1,
              opciones: [['', '— sin decidir —']].concat(mods.lista.map(function (m) { return [m.modelo, m.modelo]; })),
              ayuda: mods.declarados ? '' : 'Este proyecto no tiene modelos declarados, así que se ofrece el catálogo entero.' });
          } else {
            camposU.push({ k: 'modelo', label: 'Modelo de villa', medio: 1, ayuda: 'Dune, Dream… (opcional)' });
          }
          // fase/zona de masterplan solo existen para Sumba Hills — se ofrecen
          // ya con el proyecto por defecto marcado; si al final se elige otro
          // proyecto desde el desplegable, van vacías y no se mandan.
          if (proyectoDefecto === 'Sumba Hills') {
            camposU.push({ k: 'fase_masterplan', label: 'Fase (masterplan)', medio: 1, ayuda: 'I, II…' });
            camposU.push({ k: 'zona_masterplan', label: 'Zona', medio: 1, ayuda: '1, 2, 3…' });
          }
          camposU.push(
            { k: 'superficie_m2', label: 'Superficie (m²)', tipo: 'number', medio: 1 },
            // Precio de suelo (16-sep-2026): igual que en "Editar unidad", solo
            // lectura, calculado de superficie × precio/m² — nunca un numero
            // suelto. Sin superficie no hay como calcularlo.
            { k: 'precio_m2', label: 'Precio por m²', tipo: 'number', medio: 1,
              ayuda: 'Rellena antes la superficie — sin ella no se puede calcular el precio de suelo.' },
            { tipo: 'lectura', label: 'Precio de suelo', medio: 1, dataMostrar: 'precio-suelo-calc', valor: 'rellena la superficie primero' },
            { k: 'precio_construccion', label: 'Precio de construcción', tipo: 'number', medio: 1 },
            { tipo: 'nota', label: 'Precio de suelo = superficie × precio por m². Precio total = suelo + construcción. Ninguno de los dos se escribe a mano: los calcula siempre la base.' },
            { k: 'moneda', label: 'Moneda', tipo: 'select', medio: 1, opciones: ['EUR', 'IDR'], valor: 'EUR' },
            { k: 'notas', label: 'Notas', tipo: 'textarea' }
          );
          modal('Nueva unidad', camposU, 'Crear unidad', function (v) {
            // Campos `type:'number'` nativos: el valor ya llega en punto decimal
            // (p.ej. "1200.5"), nunca con el formato europeo de coma que usa
            // parseImporte() en /proyectos/ para sus inputs de texto libre —
            // aplicar esa transformación aquí le comería el punto y lo rompería.
            var num = function (s) { var n = parseFloat(s); return isNaN(n) ? null : n; };
            var supNueva = num(v.superficie_m2), pm2Nueva = num(v.precio_m2);
            var fila = {
              codigo: v.codigo.trim(), proyecto: v.proyecto,
              tipo: v.tipo, modelo: v.modelo ? v.modelo.trim() : null, superficie_m2: supNueva,
              precio_suelo: (supNueva && pm2Nueva != null) ? Math.round(supNueva * pm2Nueva * 100) / 100 : null,
              precio_construccion: num(v.precio_construccion),
              moneda: v.moneda, notas: v.notas.trim() || null
            };
            if (v.fase_masterplan) fila.fase_masterplan = v.fase_masterplan.trim();
            if (v.zona_masterplan) fila.zona_masterplan = v.zona_masterplan.trim();
            return sb.from('unidades').insert(fila);
          });
          var cm2N = document.querySelector('#lw-editor [data-k="precio_m2"]');
          var csupN = document.querySelector('#lw-editor [data-k="superficie_m2"]');
          var cmonN = document.querySelector('#lw-editor [data-k="moneda"]');
          var csueloMostradoN = document.querySelector('#lw-editor [data-mostrar="precio-suelo-calc"]');
          if (cm2N && csupN && csueloMostradoN) {
            // fmtM no existe en este bloque (solo lo define editarUnidad): mismo
            // respaldo que usa el resto de la suite cuando dinero.js no cargo.
            var fmtMN = function (x, m) {
              return (typeof lwFormatoImporte === 'function') ? lwFormatoImporte(x, m || 'EUR') : String(x) + ' ' + (m || 'EUR');
            };
            var recalculaN = function () {
              var m2 = parseFloat(cm2N.value), sup = parseFloat(csupN.value);
              if (!isNaN(m2) && !isNaN(sup) && sup > 0) csueloMostradoN.value = fmtMN(Math.round(m2 * sup * 100) / 100, cmonN ? cmonN.value : 'EUR');
              else csueloMostradoN.value = (!isNaN(sup) && sup > 0) ? '—' : 'rellena la superficie primero';
            };
            cm2N.addEventListener('input', recalculaN);
            csupN.addEventListener('input', recalculaN);
          }
        }, function (e) {
          aviso('No se pudo abrir: ' + (e && e.message || e), '#ba1a1a');
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
        aviso('Abriendo «' + (u.codigo || 'unidad') + '»…');
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
          if (rs[0].error) return aviso('No se pudo abrir: ' + rs[0].error.message, '#ba1a1a');
          if (rs[1].error) return aviso('No se pudo abrir: ' + rs[1].error.message, '#ba1a1a');
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
          var haySuperficie = !!Number(u.superficie_m2);
          /* Lo que se PINTA al abrir, para saber al guardar si se tocó. El €/m²
             del prefill va redondeado a 2 decimales: si se reenviara siempre,
             guardar sin tocar reescribía `precio_suelo` con sup × €/m²
             redondeado — medido el 19-sep-2026: 81 de 461 parcelas derivaban
             (hasta 5 €). Si ni la superficie ni el €/m² cambian, el suelo no
             viaja y la base conserva el que tenía. */
          var pm2Exacto = (u.precio_suelo != null && haySuperficie) ? Number(u.precio_suelo) / Number(u.superficie_m2) : null;
          var pm2Inicial = pm2Exacto != null ? Math.round(pm2Exacto * 100) / 100 : null;
          var supInicial = u.superficie_m2 == null ? null : Number(u.superficie_m2);
          campos.push(
            /* Precio de suelo (16-sep-2026, encargo del owner): deja de ser un
               campo propio y pasa a SOLO LECTURA, calculado siempre como
               superficie × precio/m² — nunca un numero suelto tecleado aparte.
               Sin superficie no hay como calcularlo, asi que se bloquea con un
               aviso en vez de dejar un hueco vacio sin explicar (decision del
               owner: mejor bloquear que dejarlo escribible como excepcion).
               `data-mostrar` (no `data-k`): es un espejo, igual que 'lectura'
               ya hace con el total — no viaja en el payload, lo recalcula
               `recalcula()` mas abajo segun se teclea. */
            { k: 'precio_m2', label: 'Precio por m²', tipo: 'number', medio: 1,
              valor: (u.precio_suelo != null && haySuperficie) ? Math.round(Number(u.precio_suelo) / Number(u.superficie_m2) * 100) / 100 : '',
              ayuda: haySuperficie ? 'El precio de suelo se calcula solo: superficie × este precio.' : 'Rellena antes la superficie (arriba) — sin ella no se puede calcular el precio de suelo.' },
            { tipo: 'lectura', label: 'Precio de suelo', medio: 1, dataMostrar: 'precio-suelo-calc',
              valor: (u.precio_suelo != null && haySuperficie) ? fmtM(u.precio_suelo, u.moneda) : (haySuperficie ? '—' : 'rellena la superficie primero') },
            { k: 'precio_construccion', label: 'Precio de construcción', tipo: 'number', medio: 1, valor: n0(u.precio_construccion) },
            { tipo: 'lectura', label: 'Precio total', medio: 1, dataMostrar: 'precio-total-calc', valor: totalDerivado ? fmtM(totalDerivado, u.moneda) : '—' },
            { tipo: 'nota', label: 'Precio de suelo = superficie × precio por m². Precio total = suelo + construcción. Ninguno de los dos se escribe a mano: los calcula siempre la base (28-ago-2026: un CSV trajo 143 parcelas con el total descuadrado de sus propias columnas).' },
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
              '<span style="font-weight:600;font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:#75786e">' + esc(dt) + '</span>' +
              '<span style="font-weight:600;font-size:13px;color:#2E3437;text-align:right">' + dd + '</span></div>';
          };
          var bloque = function (titulo, dentro) {
            return '<section style="margin:0 0 18px;padding:14px 16px;background:#f5f4ee;border:1px solid #E4DCCB;border-radius:10px">' +
              '<h4 style="margin:0 0 8px;font-weight:600;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#104C4F">' + esc(titulo) + '</h4>' +
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
                  '<br><span style="font-weight:500;font-size:11px;color:#8A8474">su parte del contrato, no el total</span>');
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
              (descuadra ? '<p style="margin:8px 0 0;font-weight:500;font-size:12px;color:#8A6A34">El total guardado (' +
                 esc(fmtM(u.precio_guardado, u.moneda)) + ') no cuadra con suelo + construcción. Manda la suma.</p>' : ''));
          }

          modal((u.codigo || 'Unidad'), campos, 'Guardar cambios', function (v) {
            var num = function (x) { var n = parseFloat(x); return isNaN(n) ? null : n; };
            var txt = function (x) { return (x || '').trim() || null; };
            // Precio de suelo (16-sep-2026): ya no llega en `v` (el campo es
            // 'lectura', sin data-k) -- se calcula aqui mismo, en el unico
            // sitio que escribe la fila, a partir de lo que se acaba de
            // teclear en superficie y precio/m². Sin superficie o sin
            // precio/m² no hay como calcularlo: se guarda null, nunca un
            // valor tecleado a mano por otra via.
            var supGuardar = num(v.superficie_m2), pm2Guardar = num(v.precio_m2);
            var fila = {
              codigo: v.codigo.trim(), proyecto: v.proyecto, tipo: v.tipo,
              modelo: txt(v.modelo), superficie_m2: supGuardar,
              precio_construccion: num(v.precio_construccion),
              moneda: v.moneda, notas: txt(v.notas)
              // `precio` no va aqui a proposito — ver la cabecera de esta funcion.
            };
            // `precio_suelo` SOLO si se tocó superficie o €/m² (ver pm2Inicial arriba)
            var tocoSuelo = (supGuardar !== supInicial) || (pm2Guardar !== pm2Inicial);
            /* Si solo cambió la superficie, el €/m² que multiplica es el EXACTO de
               la base, no el redondeado que se pintó: con el redondeado una
               medición nueva legítima arrastraba la misma deriva disfrazada de
               cambio (Administración, revisión previa 19-sep-2026). */
            var pm2Usar = (pm2Guardar === pm2Inicial && pm2Exacto != null) ? pm2Exacto : pm2Guardar;
            if (tocoSuelo) fila.precio_suelo = (supGuardar && pm2Usar != null) ? Math.round(supGuardar * pm2Usar * 100) / 100 : null;
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

          /* Precio por m² -> precio de suelo (16-sep-2026: precio_suelo ya no
             es un campo, es un espejo de solo lectura — ver el 'lectura' de
             arriba con dataMostrar:'precio-suelo-calc'). Va aqui y no dentro
             de modal() porque es la unica pantalla que lo necesita: el modal
             canonico no tiene campos que se hablen entre si, y abrirle esa
             puerta a todos por un caso es mas de lo que hace falta. modal()
             ya ha pintado el DOM cuando se llega aqui. */
          var cm2 = document.querySelector('#lw-editor [data-k="precio_m2"]');
          var csup = document.querySelector('#lw-editor [data-k="superficie_m2"]');
          var csueloMostrado = document.querySelector('#lw-editor [data-mostrar="precio-suelo-calc"]');
          var cobra = document.querySelector('#lw-editor [data-k="precio_construccion"]');
          var ctotalMostrado = document.querySelector('#lw-editor [data-mostrar="precio-total-calc"]');
          var cmodelo = document.querySelector('#lw-editor [data-k="modelo"]');
          if (cm2 && csup && csueloMostrado) {
            /* El total se recalcula EN VIVO al teclear, como `suma()` en la viva:
               un total fijo al abrir decía el precio de antes mientras se
               cambiaba la construcción (auditoría 19-sep-2026). */
            var recalcula = function () {
              var m2 = parseFloat(cm2.value), sup = parseFloat(csup.value);
              var suelo = (!isNaN(m2) && !isNaN(sup) && sup > 0) ? Math.round(m2 * sup * 100) / 100 : null;
              if (suelo != null) csueloMostrado.value = fmtM(suelo, u.moneda);
              else csueloMostrado.value = (!isNaN(sup) && sup > 0) ? '—' : 'rellena la superficie primero';
              if (ctotalMostrado) {
                var obra = cobra ? parseFloat(cobra.value) : NaN;
                var total = (suelo != null || !isNaN(obra)) ? (suelo || 0) + (isNaN(obra) ? 0 : obra) : null;
                ctotalMostrado.value = total ? fmtM(total, u.moneda) : '—';
              }
            };
            cm2.addEventListener('input', recalcula);
            csup.addEventListener('input', recalcula);
            if (cobra) cobra.addEventListener('input', recalcula);
            /* Modelo → construcción, calcado de la viva (proyectos/index.html,
               `precioModelo`): elegir un modelo del catálogo rellena la
               construcción con su precio y rehace el total; volver a «sin
               decidir» los vacía — un total que da por supuesto un modelo que
               ya no está elegido es peor que no tener total. Un modelo fuera
               del catálogo respeta lo que haya. */
            if (cmodelo && cobra && cmodelo.tagName === 'SELECT') {
              cmodelo.addEventListener('change', function () {
                if (!cmodelo.value) { cobra.value = ''; recalcula(); aviso('Sin modelo: la construcción y el total quedan sin fijar'); return; }
                var m = null;
                for (var iM2 = 0; iM2 < mods.lista.length; iM2++) { if (mods.lista[iM2].modelo === cmodelo.value) m = mods.lista[iM2]; }
                if (!m || m.precio_construccion == null) return;
                cobra.value = m.precio_construccion; recalcula();
                aviso('Precio de construcción recalculado para ' + cmodelo.value);
              });
            }
          }
        }, function (e) {
          aviso('No se pudo abrir: ' + (e && e.message || e), '#ba1a1a');
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
        if (!u) return aviso('Esa parcela ya no esta en pantalla — vuelve a abrir el proyecto.', '#8A6A34');
        editarUnidad(u);
      });

      /* Exportar informe financiero (11-sep-2026): CSV de cartera/cobrado por
         proyecto. Consulta propia en vez de leer el estado interno de
         datos.js — mismo patrón lazy-fetch que ya usa "Editar proyecto". */
      var bExport = document.getElementById('btn-exportar');
      if (bExport) bExport.addEventListener('click', function (ev) {
        ev.stopPropagation();
        aviso('Preparando el CSV…');
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
          if (fallo) return aviso('No se pudo generar el CSV: ' + fallo.message, '#ba1a1a');
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
          aviso('No se pudo generar el CSV: ' + (e && e.message || e), '#ba1a1a');
        });
      });

      /* Exportar cuentas de UN proyecto (antes decía "Descargar Balance
         Financiero (PDF)" — no hay generador de PDF en la suite; prometerlo y
         entregar otra cosa es peor que llamarlo por su nombre real). */
      var bBalance = document.getElementById('btn-balance-csv');
      if (bBalance) bBalance.addEventListener('click', function (ev) {
        ev.stopPropagation();
        var p = proyectoObj();
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
        aviso('Preparando el CSV de ' + p.nombre + '…');
        // `moneda` en su propia columna (hallazgo de Administración en la
        // consulta de deploy de este mismo cambio): un proyecto con unidades
        // en EUR e IDR a la vez (Riverfront) exportaba un "Precio" desnudo,
        // que Excel puede sumar como si fuera una sola divisa.
        sb.from('unidades_estado').select('codigo,modelo,estado,precio,moneda,contrato_numero,comprador_nombre')
          .eq('proyecto', p.nombre).order('codigo_orden').then(function (r) {
            if (r.error) return aviso('No se pudo exportar: ' + r.error.message, '#ba1a1a');
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
        aviso('El importador de CSV vive en Proyectos (la vista de tabla) — abriendo…');
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
        if (!puedeH(aut.ficha, 'vencimientos')) return aviso('Ajustar hitos exige la herramienta Vencimientos (policy puede(\'vencimientos\')).', '#8A6A34');
        /* Un hito NUEVO no se crea aqui a proposito: nacen del calendario del
           contrato (sincroniza_vencimientos) y la tabla no tiene policy de
           INSERT. Lo que si se hace aqui es AJUSTAR: fecha y nota — con
           ajustado=true, o el trigger regenera y se lo come. El importe NO se
           edita aqui a proposito: la herramienta viva tampoco lo deja tocar
           por pantalla (decision deliberada, no un descuido — 15-sep-2026),
           asi que v4 no abre una via que el equipo no queria que existiera. */
        /* Paridad con /intranet/vencimientos/ (auditoría 19-sep-2026): allí solo
           se ajusta la FECHA, solo de contratos FIRMADOS (`bloqueado`), se puede
           dejar vacía (vuelve a «Sin fecha») y la nota no se toca por pantalla.
           Y toda escritura va con `.select('id')` + unaFila: la RLS deniega con
           0 filas y sin error, y el editor decía «guardado» sobre nada. */
        Promise.all([
          sb.from('contrato_vencimientos').select('id,contrato_id,descripcion,pct,monto,fecha,factura_id').order('fecha', { ascending: true, nullsFirst: true }),
          sb.rpc('contratos_equipo').select('id,numero,bloqueado')
        ]).then(function (rs) {
          if (rs[0].error) return aviso('No se pudieron leer los hitos: ' + rs[0].error.message, '#93000a');
          var cs = (rs[1].data || []);
          var num = {}; cs.forEach(function (c) { if (c.bloqueado) num[c.id] = c.numero; });
          /* Un hito YA FACTURADO no se mueve desde aquí: su fecha viaja en la
             factura que el comprador ya recibió; se corrige anulando y
             reemitiendo desde Facturas (Administración, revisión previa 19-sep). */
          var vs = (rs[0].data || []).filter(function (v) { return !!num[v.contrato_id] && !v.factura_id; });
          var ops = vs.map(function (v) {
            return [v.id, num[v.contrato_id] + ' · ' + (v.descripcion || 'hito') + ' · ' + (v.fecha || 'SIN FECHA')];
          });
          if (!ops.length) return aviso('No hay hitos de contratos firmados que ajustar (los de contratos sin firmar no se tocan: se regeneran solos).', '#8A6A34');
          modal('Ajustar la fecha de un hito', [
            { k: 'id', label: 'Hito', tipo: 'select', opciones: ops, req: 1 },
            { k: 'fecha', label: 'Fecha', tipo: 'date', ayuda: 'Vacía = vuelve a «Sin fecha».' },
            { tipo: 'nota', label: 'Solo contratos firmados y hitos aún sin facturar (uno facturado se corrige anulando y reemitiendo desde Facturas). El importe y la nota no se editan por pantalla (decisión del 15-sep-2026, igual que en la herramienta clásica).' }
          ], 'Guardar ajuste', function (v) {
            return sb.from('contrato_vencimientos').update({ fecha: v.fecha || null, ajustado: true }).eq('id', v.id).select('id').then(unaFila);
          });
        });
      });
    },

    soporte: function (aut) {
      var sb = aut.sb;
      // mismo UPDATE directo que toggleEstado() en /intranet/soporte/ — RLS ya lo deja
      ata(/^(Marcar resuelto|Reabrir)$/i, function () {
        var hilo = window.LW_V4 && window.LW_V4.hilo;
        if (!hilo) return aviso('El hilo aún no ha cargado.', '#8A6A34');
        var nuevo = hilo.estado === 'abierto' ? 'resuelto' : 'abierto';
        sb.from('hilo_soporte').update({ estado: nuevo, actualizado_en: new Date().toISOString() }).eq('id', hilo.id).then(function (r) {
          if (r.error) return aviso('No se pudo cambiar el estado: ' + r.error.message, '#93000a');
          location.reload();
        });
      });
      ata(/^Enviar respuesta$/i, function () {
        var ta = document.querySelector('textarea');
        var hilo = window.LW_V4 && window.LW_V4.hilo;
        var quien = window.LW_V4 && window.LW_V4.hiloCliente;
        if (!hilo) return aviso('El hilo aún no ha cargado.', '#8A6A34');
        var texto = ta ? ta.value.trim() : '';
        if (!texto) return aviso('Escribe la respuesta primero.', '#8A6A34');
        if (!window.confirm('La respuesta se envía a ' + ((quien && quien.full_name) || 'el comprador') + ' y le llega TAMBIÉN por email real. ¿Enviar?')) return;
        sb.rpc('portal_enviar_mensaje', { p_hilo_id: hilo.id, p_texto: texto }).then(function (r) {
          if (r.error) return aviso('No se pudo enviar: ' + r.error.message, '#93000a');
          location.reload();
        });
      });
    },

    obra: function (aut) {
      var sb = aut.sb;
      ata(/Registrar avance/i, function () {
        // hallazgo de Desarrollo (deploy 15-sep): el gate de la UI decía
        // 'unidades', pero obra_actualizar y las policies de obra_fotos/bucket
        // obra exigen puede('obra') — con el gate viejo, un agente con
        // Unidades pero sin Obra veía el flujo entero y fallaba al guardar.
        if (!puedeH(aut.ficha, 'obra')) return aviso('El avance de obra exige la herramienta Obra (policy puede(\'obra\')).', '#8A6A34');
        Promise.all([
          sb.from('unidades_estado').select('id,codigo,proyecto,obra_fase,obra_fecha_entrega').order('codigo_orden').limit(500),
          sb.from('obra_fases').select('*').order('orden')
        ]).then(function (rs) {
          if (rs[0].error) return aviso('No se pudieron leer las unidades: ' + rs[0].error.message, '#93000a');
          var us = rs[0].data || [], fases = rs[1].data || [];
          var ops = us.map(function (u) { return [u.id, u.codigo + ' · ' + (u.proyecto || '—') + (u.obra_fase ? ' · ' + u.obra_fase : '')]; });
          // paso 1: elegir unidad — paso 2 (abajo) abre YA con su fase/fecha actuales y sus fotos,
          // igual que clicar una fila en /intranet/obra/ (aquí no hay tabla clicable todavía)
          modal('Registrar avance técnico', [
            { k: 'unidad', label: 'Unidad', tipo: 'select', opciones: ops, req: 1 }
          ], 'Continuar', function (v) {
            var u = us.filter(function (x) { return x.id === v.unidad; })[0];
            setTimeout(function () { abreAvanceUnidad(sb, u, fases); }, 300);
          }, { sinRecarga: true });
        });
      });

      /* Parte de trabajo: avanzar una fase-zona y fijar los cobros de esa fase
         (17-sep-2026, encargo del owner — encargos/20260917_lawang_vencimientos_obra.md).

         Es otra cosa que "Registrar avance técnico", que es por UNIDAD y solo
         mueve `unidades.obra_fase` + fotos. Esto mueve el cubo entero
         (proyecto + fase del masterplan + zona) y, al hacerlo, FIJA LA FECHA DE
         COBRO del pago de esa fase en todos los contratos de Construcción de ese
         cubo. O sea: dispara dinero real hacia compradores reales. De ahí que
         haya vista previa obligatoria antes de confirmar.

         El flujo lo imponen las funciones de la base, no esta pantalla:
         obra_contratos_afectados() para la previa → obra_confirmar_avance() con
         los MISMOS ids que se enseñaron (candado optimista: si la lista cambió
         mientras tanto, la base rechaza en vez de escribir sobre datos viejos). */
      ata(/Nuevo parte de trabajo/i, function () {
        if (!puedeH(aut.ficha, 'obra'))
          return aviso('Los partes de trabajo exigen la herramienta Obra (policy puede(\'obra\')).', '#8A6A34');

        Promise.all([
          sb.from('proyectos').select('id,nombre,estado').eq('estado', 'en_construccion').order('nombre'),
          sb.from('obra_fases').select('clave,es,orden').order('orden')
        ]).then(function (rs) {
          if (rs[0].error) return aviso('No se pudieron leer los proyectos: ' + rs[0].error.message, '#93000a');
          var proys = rs[0].data || [], fases = rs[1].data || [];
          // Sin proyectos en construcción no hay nada que avanzar, y el motivo
          // no es obvio: se dice entero, con el camino para resolverlo.
          if (!proys.length)
            return aviso('Ningún proyecto está «En construcción». El parte de trabajo fija cobros, así que primero hay que pasar el proyecto a ese estado desde Proyectos → Estado y obra.', '#8A6A34');

          modal('Parte de trabajo · elegir proyecto', [
            { k: 'proyecto', label: 'Proyecto en construcción', tipo: 'select', req: 1,
              opciones: proys.map(function (p) { return [p.id, p.nombre]; }) }
          ], 'Continuar', function (v) {
            var p = proys.filter(function (x) { return x.id === v.proyecto; })[0];
            setTimeout(function () { eligeFaseZona(sb, p, fases); }, 300);
          }, { sinRecarga: true });
        });
      });

      /* Paso 2 — qué cubo del masterplan avanza, y a qué fase.
         La fase siguiente NO se elige: la base solo admite avanzar un paso
         (obra_fases.orden + 1), así que ofrecerla sería ofrecer un error. */
      function eligeFaseZona(sb, proy, fases) {
        Promise.all([
          sb.from('unidades').select('fase_masterplan,zona_masterplan').eq('proyecto_id', proy.id),
          sb.from('obra_progreso_fase_zona').select('fase_masterplan,zona_masterplan,obra_fase_actual')
            .eq('proyecto_id', proy.id)
        ]).then(function (rs) {
          if (rs[0].error) return aviso('No se pudieron leer las parcelas: ' + rs[0].error.message, '#93000a');
          var uds = rs[0].data || [], prog = rs[1].data || [];

          // Cubos reales del proyecto. Una parcela sin fase o sin zona queda
          // fuera a propósito: la base rechaza avanzar un cubo con cualquiera de
          // las dos en blanco, porque NULL ahí significa "sin zonificar todavía",
          // no una zona que se llame NULL.
          // La clave del cubo va en JSON, no concatenando con un separador:
          // cualquier separador de texto puede aparecer dentro de una zona real
          // y partirla de vuelta daria datos equivocados sin dar ningun error.
          var cubos = {};
          uds.forEach(function (u) {
            if (!u.fase_masterplan || !u.zona_masterplan) return;
            var k = JSON.stringify([u.fase_masterplan, u.zona_masterplan]);
            cubos[k] = (cubos[k] || 0) + 1;
          });
          var claves = Object.keys(cubos).sort();
          if (!claves.length)
            return aviso('Este proyecto no tiene ninguna parcela con fase y zona del masterplan puestas, así que no hay cubo que avanzar.', '#8A6A34');

          var porCubo = {};
          prog.forEach(function (r) { porCubo[JSON.stringify([r.fase_masterplan, r.zona_masterplan])] = r.obra_fase_actual; });

          var etiqueta = {}, siguiente = {};
          fases.forEach(function (f) { etiqueta[f.clave] = f.es || f.clave; });

          var ops = claves.map(function (k) {
            var partes = JSON.parse(k);
            var actual = porCubo[k] || null;
            var sig = null;
            if (!actual) { sig = fases[0] && fases[0].clave; }
            else {
              for (var i = 0; i < fases.length; i++) {
                if (fases[i].clave === actual) { sig = fases[i + 1] && fases[i + 1].clave; break; }
              }
            }
            siguiente[k] = sig;
            var texto = 'Fase ' + partes[0] + ' · ' + partes[1] + ' · ' + cubos[k] + ' parcelas · ' +
              (actual ? 'ahora en ' + (etiqueta[actual] || actual) : 'sin empezar') +
              (sig ? ' → ' + (etiqueta[sig] || sig) : ' · ya terminado');
            return [k, texto];
          });

          modal('Parte de trabajo · ' + proy.nombre, [
            { k: 'cubo', label: 'Qué parte de la obra avanza', tipo: 'select', req: 1, opciones: ops,
              ayuda: 'Cada avance fija la fecha de cobro de esa fase en los contratos de esas parcelas.' }
          ], 'Ver qué se va a cobrar', function (v) {
            var sig = siguiente[v.cubo];
            if (!sig) return { error: { message: 'Ese tramo ya está en la última fase de obra: no hay paso siguiente.' } };
            var partes = JSON.parse(v.cubo);
            setTimeout(function () {
              previaAvance(sb, proy, partes[0], partes[1], sig, etiqueta[sig] || sig);
            }, 300);
          }, { sinRecarga: true });
        });
      }

      /* Paso 3 — la vista previa, y solo desde aquí se confirma.
         Enseña los contratos que van a recibir fecha de cobro Y los que se
         quedan fuera con su motivo: un contrato excluido en silencio es
         exactamente el fallo que esta pantalla tiene que evitar. */
      function previaAvance(sb, proy, fase, zona, faseNueva, faseNuevaEs) {
        Promise.all([
          sb.rpc('obra_contratos_afectados', {
            p_proyecto_id: proy.id, p_fase_masterplan: fase,
            p_zona_masterplan: zona, p_fase_nueva: faseNueva
          }),
          sb.from('proyecto_plazo_pago').select('orden_pago,dias').eq('proyecto_id', proy.id)
        ]).then(function (rs) {
          if (rs[0].error) return aviso('No se pudo calcular la previa: ' + rs[0].error.message, '#93000a');
          var filas = rs[0].data || [];
          var plazos = {};
          ((rs[1] && rs[1].data) || []).forEach(function (x) { plazos[x.orden_pago] = x.dias; });

          var elegibles = filas.filter(function (f) { return f.elegible; });
          var fuera = filas.filter(function (f) { return !f.elegible; });
          var ordenPago = filas.length ? filas[0].orden_pago : null;
          var diasPorDefecto = ordenPago != null && plazos[ordenPago] != null ? plazos[ordenPago] : '';

          var diasCalc = diasPorDefecto === '' ? 0 : Number(diasPorDefecto);
          var fechaNueva = new Date(Date.now() + diasCalc * 864e5).toISOString().slice(0, 10);

          // El importe pendiente sale de la MISMA cascada que usan el dashboard de
          // Vencimientos y la facturación automática (logica.js), nunca de pct ×
          // precio en bruto: un contrato con dinero ya cobrado debe enseñar lo que
          // queda, no el hito entero.
          pendientesDe(sb, proy, fase, zona, faseNueva, elegibles, fechaNueva).then(function (res) {
            var imp = res.imp || {};
            var MOTIVO = {
              anterior_al_mecanismo: 'contrato anterior a este mecanismo — se cobra a mano, como hasta ahora',
              calendario_manual: 'calendario a medida, no el de fábrica',
              ajustado_a_mano: 'su fecha ya se tocó a mano',
              ya_facturado: 'ese pago ya está facturado',
              sin_vencimiento_en_ese_orden: 'no tiene ese pago en su calendario'
            };

            // Total POR MONEDA, nunca uno solo: en Lawang conviven euros y rupias
            // y sumarlas sería inventar una cifra.
            var totales = {};
            elegibles.forEach(function (f) {
              var p = imp[f.contrato_id];
              if (!p || p.pendiente == null || !p.moneda) return;
              totales[p.moneda] = (totales[p.moneda] || 0) + p.pendiente;
            });
            var totalTxt = Object.keys(totales).map(function (m) {
              return (typeof lwFormatoImporte === 'function') ? lwFormatoImporte(totales[m], m) : totales[m] + ' ' + m;
            }).join('  ·  ');

            var campos = [
              { tipo: 'lectura', medio: 1, label: 'Tramo', valor: 'Fase ' + fase + ' · ' + zona },
              { tipo: 'lectura', medio: 1, label: 'Pasa a', valor: faseNuevaEs },
              { tipo: 'custom', label: 'Lo que se va a cobrar', render: function (d) {
                  d.style.cssText = 'display:grid;gap:8px;background:#f5f4ee;border:1px solid ' + CAJ.borde +
                    ';border-radius:12px;padding:12px 14px;font-size:12px;line-height:1.4;color:' + CAJ.apagado;
                  var h = document.createElement('div');

                  if (!elegibles.length) {
                    h.innerHTML = '<b style="color:#8A6A34">Ningún contrato recibe fecha de cobro con este avance.</b>' +
                      '<div style="margin-top:4px">La obra avanza igual y queda registrada, pero no se cobra nada.</div>';
                  } else {
                    var cab = elegibles.length + (elegibles.length === 1 ? ' contrato recibe' : ' contratos reciben') +
                      ' fecha de cobro';
                    h.innerHTML = '<b>' + cab + (totalTxt ? ', por ' + esc(totalTxt) : '') + ':</b>' +
                      '<div style="margin-top:2px;font-size:11px">Vencerían el <b>' + esc(fechaNueva) + '</b>' +
                      (elegibles.length > 8 ? ', repartidos de 8 en 8 en días seguidos' : '') +
                      '. El importe es el pendiente <b>a día de hoy</b>; la factura se emite al vencer, con lo cobrado entonces.</div>';
                    var ul = document.createElement('div');
                    ul.style.cssText = 'margin-top:6px;display:grid;gap:3px';
                    elegibles.forEach(function (f) {
                      var l = document.createElement('div');
                      var p = imp[f.contrato_id];
                      var cola;
                      if (!p) {
                        // Nunca en blanco: un hueco mudo se lee como "no debe nada".
                        cola = '<span style="color:#8A6A34">importe no disponible' +
                          (res.error ? '' : ' con tus permisos') + '</span>';
                      } else if (p.cubierto) {
                        // La edge salta lo que ya está cubierto por lo cobrado, así
                        // que este contrato recibe fecha pero no generará factura.
                        cola = '<span style="color:#8A6A34">ya cubierto — recibe fecha, no se facturará</span>';
                      } else {
                        cola = 'pendiente ' + esc(p.txt);
                      }
                      l.innerHTML = '· <b>' + esc(f.numero || '—') + '</b> — ' + cola;
                      ul.appendChild(l);
                    });
                    h.appendChild(ul);
                    if (res.sinLogica)
                      h.insertAdjacentHTML('beforeend',
                        '<div style="margin-top:6px;color:#8A6A34">No se pudieron calcular importes en esta pantalla; la obra avanza igual.</div>');
                  }

                  if (fuera.length) {
                    var f2 = document.createElement('div');
                    f2.style.cssText = 'margin-top:8px;padding-top:8px;border-top:1px solid ' + CAJ.borde;
                    f2.innerHTML = '<b>' + fuera.length + (fuera.length === 1 ? ' contrato se queda' : ' contratos se quedan') +
                      ' fuera</b> (siguen gestionándose a mano):';
                    var ul2 = document.createElement('div');
                    ul2.style.cssText = 'margin-top:4px;display:grid;gap:3px;color:#8A6A34';
                    fuera.forEach(function (f) {
                      var l = document.createElement('div');
                      l.textContent = '· ' + (f.numero || '—') + ' — ' + (MOTIVO[f.motivo] || f.motivo || 'sin motivo');
                      ul2.appendChild(l);
                    });
                    f2.appendChild(ul2);
                    h.appendChild(f2);
                  }

                  if (elegibles.length) {
                    // Lo que pasa DESPUÉS, dicho: a partir de aquí no hay persona.
                    var av = document.createElement('div');
                    av.style.cssText = 'margin-top:8px;padding-top:8px;border-top:1px solid ' + CAJ.borde + ';color:#8A6A34';
                    av.textContent = 'Al vencer, cada contrato recibe su factura y el aviso al comprador de forma automática: a partir de aquí no hay revisión humana.';
                    h.appendChild(av);
                  }
                  d.appendChild(h);
                } },
              { k: 'dias', tipo: 'number', paso: '1', req: 1, valor: diasPorDefecto,
                label: 'Días hasta que venza el cobro',
                ayuda: diasPorDefecto === ''
                  ? 'Este proyecto no tiene plazo configurado para este pago. Escríbelo aquí, o configúralo en Proyectos → Estado y obra. Si lo cambias, las fechas e importes de arriba se recalculan al confirmar.'
                  : 'Viene del plazo configurado en la ficha del proyecto. Puedes cambiarlo solo para este avance; si lo haces, la fecha de arriba cambia igual.' },
              { k: 'nota', tipo: 'textarea', label: 'Qué se ha hecho (queda en el histórico del parte)' }
            ];

            modal('Confirmar parte de trabajo · ' + proy.nombre, campos,
              elegibles.length ? 'Avanzar y fijar cobros' : 'Avanzar la obra', function (v) {
                var dias = Number(v.dias);
                if (!isFinite(dias) || dias < 0)
                  return { error: { message: 'Los días hasta el cobro tienen que ser un número de 0 en adelante.' } };
                return sb.rpc('obra_confirmar_avance', {
                  p_proyecto_id: proy.id,
                  p_fase_masterplan: fase,
                  p_zona_masterplan: zona,
                  p_fase_nueva: faseNueva,
                  p_dias: dias,
                  p_nota: (v.nota || '').trim() || null,
                  // Los MISMOS ids que se acaban de enseñar. Si algo cambió
                  // mientras el modal estaba abierto, la base rechaza (40001)
                  // en vez de fijar cobros sobre una lista que ya no es la vista.
                  p_contratos_esperados: elegibles.map(function (f) { return f.contrato_id; })
                }).then(function (r) {
                  // La RPC devuelve la fecha REAL de cada contrato (el reparto de
                  // 8 por día empuja a algunos hacia delante). Se dice, en vez de
                  // dejar creer que todos vencen el mismo día.
                  if (!r.error && r.data && r.data.length) {
                    var ds = {};
                    r.data.forEach(function (x) { ds[x.fecha_vencimiento] = (ds[x.fecha_vencimiento] || 0) + 1; });
                    var resumen = Object.keys(ds).sort().map(function (f) {
                      return ds[f] + (ds[f] === 1 ? ' cobro el ' : ' cobros el ') + f;
                    }).join(' · ');
                    aviso('Obra avanzada · ' + resumen);
                  }
                  return r;
                });
              });
          });
        });
      }

      /* El pendiente real de cada contrato afectado, con la cascada compartida.

         Los datos de dinero salen de `obra_datos_cobro`, que tiene EL MISMO gate
         que la lista (consulta de deploy 17-sep, Administración): antes se leían
         de contratos_equipo()/contratos_cobrado_equipo(), que son de alcance por
         agente, así que un project manager veía la lista entera de contratos y
         los importes en blanco — indistinguible de "no hay nada pendiente",
         justo antes de confirmar cobros reales. Hoy hay 6 usuarios con la
         herramienta Obra y solo 4 son admin, o sea que no era hipotético.

         `fechaNueva` es la fecha que se va a PONER, no la que hay. La cascada
         reparte lo cobrado por orden de fecha, así que calcularla con la fecha
         vieja podía enseñar un pendiente y facturar otro. */
      function pendientesDe(sb, proy, fase, zona, faseNueva, elegibles, fechaNueva) {
        if (!elegibles.length) return Promise.resolve({ imp: {}, sinPermiso: false });
        if (typeof cascada !== 'function' || typeof cobradoEfectivo !== 'function')
          return Promise.resolve({ imp: {}, sinLogica: true });

        return sb.rpc('obra_datos_cobro', {
          p_proyecto_id: proy.id, p_fase_masterplan: fase,
          p_zona_masterplan: zona, p_fase_nueva: faseNueva
        }).then(function (r) {
          if (r.error) return { imp: {}, error: r.error.message };
          var filas = r.data || [];
          var hoy = new Date().toISOString().slice(0, 10);
          var cs = filas.map(function (x) {
            return { id: x.contrato_id, numero: x.numero, precio_total: x.precio_total,
                     moneda: x.moneda, tipo: 'construccion', contrato_padre_id: null };
          });
          var cobrados = {};
          filas.forEach(function (x) { cobrados[x.contrato_id] = Number(x.cobrado) || 0; });

          var out = {};
          elegibles.forEach(function (f) {
            var fila = filas.filter(function (x) { return x.contrato_id === f.contrato_id; })[0];
            if (!fila) return;
            var c = cs.filter(function (x) { return x.id === f.contrato_id; })[0];
            // La fecha que se va a poner entra ANTES de repartir: es lo que
            // decide en qué orden absorbe cada hito el dinero ya cobrado.
            var vencs = (fila.vencimientos || []).map(function (v) {
              return v.orden === f.orden_pago
                ? { orden: v.orden, pct: v.pct, monto: v.monto, fecha: fechaNueva }
                : v;
            });
            var anot = cascada(vencs, c, cobradoEfectivo(c, cs, cobrados), hoy);
            var mio = anot.filter(function (x) { return x.orden === f.orden_pago; })[0];
            if (!mio || mio.pendiente == null) return;
            var mon = fila.moneda;
            var txt = !mon
              // Sin moneda no se supone EUR: en Lawang conviven rupias y euros, y
              // una cifra en rupias rotulada «€» no da ningún error, solo se lee mal.
              ? String(mio.pendiente) + ' (moneda sin definir)'
              : ((typeof lwFormatoImporte === 'function')
                  ? lwFormatoImporte(mio.pendiente, mon) : String(mio.pendiente) + ' ' + mon);
            out[f.contrato_id] = { pendiente: mio.pendiente, moneda: mon, txt: txt,
                                   cubierto: mio.pendiente === 0 };
          });
          return { imp: out };
        }, function (e) { return { imp: {}, error: String(e) }; });
      }

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

      /* EDITAR una ficha, desde su cajon (18-sep-2026). Quien puede lo decide la
         base, no esta pantalla: `admins actualizan clientes` (cualquier ficha) o
         `el autor corrige su ficha mientras no este firmada`. Por eso el UPDATE
         lleva `.select('id')` + unaFila: si la policy lo filtra, la base devuelve
         0 filas SIN error y sin eso el cajon diria «guardado». Al editar NO se
         exigen los seis datos del alta (decision explicita de la herramienta
         clasica: hay 200 fichas antiguas sin nacionalidad ni pasaporte). */
      /* Mismos mensajes que la viva para los tres rechazos de la base (auditoría
         19-sep-2026): el «duplicate key» crudo mandaba a mirar el correo cuando el
         choque era el pasaporte, y el 0-filas decía «tu sesión ha caducado». */
      function errorClienteHumano(r) {
        if (!(r && r.error)) return r;
        var msg = String(r.error.message || ''), code = String(r.error.code || '');
        var m = /clients_pasaporte_uniq/.test(msg)
          ? 'Ese pasaporte / NPWP ya está en otra ficha (el correo no tiene nada que ver con este aviso). Esa ficha puede ser de un compañero: búscala en el directorio antes de crear otra.'
          : /clients_email_tipo_key|clients_email_key/.test(msg)
          ? 'Ya hay otra ficha DEL MISMO TIPO con ese correo. Una persona y su empresa sí pueden compartirlo, pero dos personas (o dos empresas) no. Esa otra ficha puede ser de un compañero.'
          : /duplicate key/.test(msg)
          ? 'Ese dato ya está en otra ficha: ' + msg
          : /PGRST116/.test(code) || /ninguna fila/.test(msg)
          ? 'No se ha guardado: la base no te deja editar esta ficha. Suele ser porque no la diste de alta tú, o porque ya cuelga de un contrato firmado. Habla con un administrador — recargar no lo arregla.'
          : null;
        return m ? { error: { message: m } } : r;
      }
      var miEmailC = ((aut.session && aut.session.user && aut.session.user.email) || '').toLowerCase();
      window.LW_V4.abreEditaComprador = function (c) {
        if (!c) return aviso('La ficha aún no ha cargado.', '#8A6A34');
        /* Mismo gate de pantalla que la viva (`soloLectura`): editar es de
           admin/super_admin, o del AUTOR de la ficha. Sin `propietario` (fichas
           del backfill viejo) no es de nadie salvo para admin. El candado real
           sigue siendo la policy — si la ficha cuelga de un contrato firmado la
           base la rechaza y se dice con el mensaje de arriba. */
        var mia = !!c.propietario && String(c.propietario).toLowerCase() === miEmailC;
        if (!esAdmin(aut.ficha) && !mia) {
          return aviso('Esta ficha la dio de alta otra persona: solo un administrador (o quien la creó) puede editarla.', '#8A6A34');
        }
        var tel = /^(\+\d{1,4})\s*(.*)$/.exec(String(c.phone || '').trim());
        var esEmpresa = c.tipo === 'empresa';
        modal('Editar datos — ' + (c.full_name || ''), [
          { k: 'tipo', label: 'Tipo de comprador', tipo: 'select', medio: 1, valor: c.tipo || 'persona',
            opciones: [['persona', 'Persona física'], ['empresa', 'Empresa']] },
          { k: 'kyc_status', label: 'Estado KYC', tipo: 'select', medio: 1, valor: c.kyc_status || 'pending',
            opciones: [['pending', 'Pendiente'], ['submitted', 'En revisión'], ['verified', 'Aprobado'], ['rejected', 'Rechazado']] },
          { k: 'full_name', label: esEmpresa ? 'Razón social' : 'Nombre completo', req: 1, valor: c.full_name || '' },
          { k: 'email', label: 'Email', tipo: 'email', valor: c.email || '',
            ayuda: 'Solo de contacto: cambiarlo NO cambia con qué email entra al portal.' },
          { k: 'prefijo', label: 'Prefijo del teléfono', medio: 1, valor: tel ? tel[1] : '', ayuda: '+34, +62, +61…' },
          { k: 'telefono', label: 'Teléfono', medio: 1, valor: tel ? tel[2] : (c.phone || '') },
          { k: 'nationality', label: esEmpresa ? 'País de constitución' : 'Nacionalidad', medio: 1, valor: c.nationality || '' },
          { k: 'passport_number', label: esEmpresa ? 'Identificación fiscal' : 'Pasaporte / NPWP', medio: 1, valor: c.passport_number || '',
            ayuda: 'Es lo que se imprime en el contrato.' },
          { k: 'idioma_comunicacion', label: 'Idioma de comunicación', tipo: 'select', valor: c.idioma_comunicacion || 'es',
            opciones: [['es', 'Español'], ['en', 'English'], ['id', 'Bahasa Indonesia']] },
          { k: 'forma_juridica', label: 'Forma jurídica (solo empresa)', medio: 1, valor: c.forma_juridica || '', ayuda: 'S.L., LLC, PT PMA, GmbH…' },
          { k: 'registro_num', label: 'Nº de registro mercantil (solo empresa)', medio: 1, valor: c.registro_num || '' },
          { k: 'rep_nombre', label: 'Representante legal (solo empresa)', medio: 1, valor: c.rep_nombre || '' },
          { k: 'rep_cargo', label: 'Cargo del representante (solo empresa)', medio: 1, valor: c.rep_cargo || '' },
          { k: 'notes', label: 'Notas', tipo: 'textarea', valor: c.notes || '' },
          { tipo: 'nota', label: 'Si esta ficha cuelga de un contrato ya FIRMADO, su pasaporte y domicilio están impresos en ese documento y la base rechazará el cambio: es cosa de un administrador.' }
        ], 'Guardar datos', function (v) {
          if (v.prefijo && !/^\+\d{1,4}$/.test(v.prefijo)) return { error: { message: 'El prefijo va con «+» y solo dígitos: +34, +62…' } };
          if (v.full_name.trim().length < 2) return { error: { message: 'Falta el nombre' } };
          var patch = {
            tipo: v.tipo, kyc_status: v.kyc_status,
            // MAYÚSCULAS como la viva («el único sitio que escribe clients.full_name»):
            // el contrato y la factura enlazan esta ficha y la imprimen tal cual.
            full_name: v.full_name.trim().toUpperCase(), email: v.email.trim() || null,
            phone: v.telefono ? ((v.prefijo ? v.prefijo + ' ' : '') + v.telefono.trim()) : null,
            nationality: v.nationality.trim() || null, passport_number: v.passport_number.trim() || null,
            idioma_comunicacion: v.idioma_comunicacion || 'es',
            forma_juridica: v.tipo === 'empresa' ? (v.forma_juridica.trim() || null) : null,
            registro_num: v.tipo === 'empresa' ? (v.registro_num.trim() || null) : null,
            rep_nombre: v.tipo === 'empresa' ? (v.rep_nombre.trim() || null) : null,
            rep_cargo: v.tipo === 'empresa' ? (v.rep_cargo.trim() || null) : null,
            notes: v.notes.trim() || null
          };
          return sb.from('clients').update(patch).eq('id', c.id).select('id').then(unaFila).then(errorClienteHumano);
        });
      };
    },

    usuarios: function (aut) {
      var sb = aut.sb;
      // mismos 5 roles que /intranet/usuarios/ (ROLES) — antes solo llevaba
      // agente/admin/super_admin y sales_manager/project_manager no aparecían.
      var ETIQ_ROL = { agente: 'Agente', sales_manager: 'Sales manager', project_manager: 'Project manager', admin: 'Administrador', super_admin: 'Super admin' };
      var ROLES_ED = ['agente', 'sales_manager', 'project_manager', 'admin'].concat(aut.ficha.rol === 'super_admin' ? ['super_admin'] : []);
      var miEmail = ((aut.session && aut.session.user && aut.session.user.email) || '').toLowerCase();
      window.LW_V4 = window.LW_V4 || {};
      // una sola lista de roles: datos.js la LEE de aqui para pintar la ficha
      window.LW_V4.ETIQ_ROL = ETIQ_ROL;

      /* 18-sep-2026: ya no se atan por TEXTO a los botones del panel fijo de la
         derecha («Modificar rol» / «Cambiar contraseña»), que se retiro con el
         panel. Son funciones que abre el cajon de ficha de cada usuario
         (datos.js), con el usuario que se esta mirando — no «el primero de la
         lista», que era lo que aquel panel enseñaba sin decirlo. */
      window.LW_V4.abreEditaUsuario = function (u) {
        if (!(esAdmin(aut.ficha) && puedeH(aut.ficha, 'usuarios'))) {
          return aviso('Tocar roles exige administración con la herramienta Usuarios (la policy lo exige igual que este aviso).', '#8A6A34');
        }
        if (!u) return aviso('La ficha aún no ha cargado.', '#8A6A34');
        var yoMismo = miEmail && (u.email || '').toLowerCase() === miEmail;
        var soySuper = aut.ficha.rol === 'super_admin';
        // un admin no toca a un super_admin, y nadie se quita a sí mismo el
        // acceso por accidente desde esta pantalla — mismo candado que la
        // herramienta viva (`bloqueado`/`yoMismo` de intranet/usuarios/)
        if (u.rol === 'super_admin' && !soySuper) return aviso('Solo un super admin puede modificar la cuenta de otro super admin.', '#8A6A34');
        /* El catálogo de casillas es `LW_PERMISOS` (herramientas.js), la MISMA
           fuente que /intranet/usuarios/ — no la unión de lo que ya tienen las
           fichas: con eso una llave que nadie tuviera todavía (una herramienta
           recién dada de alta) no se podía conceder a nadie (auditoría 19-sep).
           Si la página no cargó herramientas.js se cae a la unión, y se nota. */
        Promise.all([
          (typeof LW_PERMISOS !== 'undefined') ? Promise.resolve({ data: null }) : sb.from('usuarios').select('herramientas'),
          sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre')
        ]).then(function (rs) {
          var ops;
          if (typeof LW_PERMISOS !== 'undefined') {
            ops = LW_PERMISOS.map(function (p) { return Array.isArray(p) ? [p[0], p[1]] : p; });
          } else {
            var todas = {};
            ((rs[0].data) || []).forEach(function (x) { (x.herramientas || []).forEach(function (h) { todas[h] = 1; }); });
            ops = Object.keys(todas).sort();
            aviso('Catálogo de permisos no cargado (herramientas.js): se ofrecen solo las llaves que ya tiene alguien.', '#8A6A34');
          }
          /* Si el catálogo de proyectos FALLÓ, no se ofrece la rejilla y
             `proyectos` no viaja en el patch: mandar `[]` le quitaría a esta
             persona todos sus proyectos sin que nadie lo pidiera (misma guarda
             `PROYECTOS !== null` de la herramienta viva). */
          var proyectosOk = !rs[1].error;
          var proyectos = (rs[1].data) || [];
          var tiposCat = (typeof LW_TIPO_CONTRATO === 'object' && LW_TIPO_CONTRATO)
            ? Object.keys(LW_TIPO_CONTRATO).map(function (k) { return [k, LW_TIPO_CONTRATO[k]]; }) : [];
          /* El ROL solo lo cambia un super_admin (viva: `fRol` disabled salvo
             soySuper). Un admin lo ve, no lo toca — y no viaja en el patch. */
          var rolEditable = soySuper && !yoMismo;
          var campos = [
            { k: 'nombre', label: 'Nombre', medio: 1, valor: u.nombre || '' },
            rolEditable
              ? { k: 'rol', label: 'Rol', tipo: 'select', medio: 1, opciones: ROLES_ED.map(function (r) { return [r, ETIQ_ROL[r] || r]; }), valor: u.rol }
              : { tipo: 'lectura', label: 'Rol', medio: 1, valor: ETIQ_ROL[u.rol] || u.rol || '—' }
          ];
          if (yoMismo) {
            campos.push({ tipo: 'nota', label: 'Es tu propia cuenta: para no dejarte fuera por accidente, el rol y el estado activo no se tocan desde aquí.' });
          } else {
            if (!soySuper) campos.push({ tipo: 'nota', label: 'El rol solo lo cambia un super admin.' });
            campos.push({ k: 'activo', label: 'Activo', tipo: 'check', valor: u.activo });
          }
          campos.push({ k: 'herramientas', label: 'Herramientas', tipo: 'multicheck', opciones: ops, valor: u.herramientas || [] });
          if (proyectosOk) {
            campos.push({ k: 'proyectos', label: 'Proyectos en los que trabaja', tipo: 'multicheck',
              opciones: proyectos.map(function (p) { return [p.id, p.nombre]; }), valor: u.proyectos || [],
              ayuda: 'Limita en qué proyectos puede crear y editar contratos. Sin ninguno marcado, no puede crear en ninguno.' });
          } else {
            campos.push({ tipo: 'nota', label: 'No se pudo cargar el catálogo de proyectos: los suyos se conservan tal cual (no se tocan desde aquí hasta que cargue).' });
          }
          campos.push(
            { k: 'tipos_contrato', label: 'Contratos que puede hacer', tipo: 'multicheck',
              opciones: tiposCat, valor: u.tipos_contrato || [],
              ayuda: 'Vacío = TODOS (al revés que Proyectos, arriba): no marcar nada aquí no bloquea, lo abre todo.' }
          );
          modal('Permisos de ' + (u.nombre || u.email), campos, 'Guardar permisos', function (v) {
            var patch = {
              nombre: v.nombre.trim() || null, herramientas: v.herramientas,
              tipos_contrato: v.tipos_contrato
            };
            if (proyectosOk) patch.proyectos = v.proyectos;
            if (!yoMismo) { patch.activo = v.activo; }
            if (rolEditable) { patch.rol = v.rol; }
            /* la proteccion real vive en la policy (super_admin intocable salvo
               super_admin, es_admin AND puede) — si esto falla por RLS, ese ES
               el mensaje, no un fallo del editor */
            // `.select()` + unaFila: un UPDATE que la policy filtra devuelve 0
            // filas SIN error, y el editor diria «guardado» sobre nada.
            return sb.from('usuarios').update(patch).eq('email', u.email).select('user_id').then(unaFila);
          });
        });
      };

      // mismo endpoint que cambiarPassword() en /intranet/usuarios/: la Edge
      // Function admin-usuarios, nunca auth.admin desde el navegador (no hay
      // service_role en cliente — revision previa Datos+Seguridad)
      window.LW_V4.abreCambiaPassword = function (u) {
        if (!(esAdmin(aut.ficha) && puedeH(aut.ficha, 'usuarios'))) {
          return aviso('Cambiar contraseñas exige administración con la herramienta Usuarios.', '#8A6A34');
        }
        if (!u) return aviso('La ficha aún no ha cargado.', '#8A6A34');
        if (u.rol === 'super_admin' && aut.ficha.rol !== 'super_admin') {
          return aviso('Solo un super admin puede modificar la cuenta de otro super admin.', '#8A6A34');
        }
        var p = window.prompt('Nueva contraseña para ' + u.email + ' (mínimo 10 caracteres).\nApúntala: no se puede volver a consultar.');
        if (p === null) return;
        if (p.length < 10) return aviso('Mínimo 10 caracteres.', '#8A6A34');
        sb.auth.getSession().then(function (r) {
          var token = r && r.data && r.data.session && r.data.session.access_token;
          if (!token) return aviso('No se pudo: sesión no encontrada.', '#93000a');
          fetch('https://vtulllundrfennhjddhc.supabase.co/functions/v1/admin-usuarios', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ' + token,
              'apikey': 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg'
            },
            body: JSON.stringify({ accion: 'password', user_id: u.user_id, password: p })
          }).then(function (resp) { return resp.json().catch(function () { return { error: 'respuesta ilegible del servidor' }; }); })
            .then(function (d) {
              if (d && d.ok) aviso('Contraseña cambiada');
              else aviso('No se pudo: ' + ((d && d.error) || ''), '#93000a');
            });
        });
      };
    },

    /* Equipos de venta y Condiciones (14-sep-2026, encargo del owner) — dos
       pantallas de administración pura: alta de `equipos_venta`, gestión de
       `equipo_miembros` (añadir/dar de baja con fecha) y de
       `condiciones_comision` + sus `condicion_tramos`. Las CUATRO tablas
       escriben solo con `es_admin()` en la base (RLS verificada con sesión no
       admin simulada, DO+rollback — revisión previa Datos+Seguridad,
       14-sep-2026): lo de aquí es UI, no el candado. */
    'equipos-venta': function (aut) {
      var sb = aut.sb, admin = esAdmin(aut.ficha);
      window.LW_V4 = window.LW_V4 || {};
      var soloAdmin = function () {
        return aviso('Los equipos de venta los da de alta solo administración (policy es_admin) — tu sesión es de ' +
          ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34');
      };

      ata(/^\+? ?Nuevo equipo$/i, function () {
        if (!admin) return soloAdmin();
        modal('Nuevo equipo de venta', [
          { k: 'nombre', label: 'Nombre del equipo', req: 1 },
          { k: 'manager_email', label: 'Email del manager', req: 1, ayuda: 'la persona que gestiona el reparto del equipo' }
        ], 'Crear equipo', function (v) {
          return sb.from('equipos_venta').insert({
            nombre: v.nombre.trim(), manager_email: v.manager_email.trim().toLowerCase()
          });
        });
      });

      window.LW_V4.abreAnadirMiembro = function (equipoId, equipoNombre) {
        if (!admin) return soloAdmin();
        modal('Añadir miembro — ' + (equipoNombre || ''), [
          { k: 'closer_email', label: 'Email del closer', req: 1 },
          { k: 'desde', label: 'Desde', tipo: 'date', req: 1, medio: 1, valor: new Date().toISOString().slice(0, 10) },
          { k: 'hasta', label: 'Hasta (opcional)', tipo: 'date', medio: 1, ayuda: 'vacío = sigue activo' }
        ], 'Añadir al equipo', function (v) {
          if (v.hasta && v.hasta < v.desde) return { error: { message: '«Hasta» no puede ser anterior a «Desde».' } };
          return sb.from('equipo_miembros').insert({
            equipo_id: equipoId, closer_email: v.closer_email.trim().toLowerCase(),
            desde: v.desde, hasta: v.hasta || null,
            added_by: (aut.session && aut.session.user && aut.session.user.email) || null
          });
        });
      };

      window.LW_V4.abreDarBaja = function (miembroId, closerEmail) {
        if (!admin) return soloAdmin();
        modal('Dar de baja — ' + (closerEmail || ''), [
          { k: 'hasta', label: 'Fecha de baja', tipo: 'date', req: 1, valor: new Date().toISOString().slice(0, 10) }
        ], 'Dar de baja', function (v) {
          return sb.from('equipo_miembros').update({ hasta: v.hasta }).eq('id', miembroId).select('id').then(unaFila);
        });
      };

      /* 18-sep-2026, owner: «permíteme editar equipos o closers por si puse
         algo mal». Dos UPDATE con `.select('id')` + unaFila, por lo de siempre:
         la policy `es_admin()` filtra en silencio. Los datos actuales vienen
         en los `data-*` del boton, que es lo que la fila ya sabe — sin volver
         a consultar para abrir un cajon. */
      window.LW_V4.abreEditaEquipo = function (b) {
        if (!admin) return soloAdmin();
        var id = b.getAttribute('data-lw-edita-equipo');
        modal('Editar equipo — ' + (b.getAttribute('data-lw-nombre') || ''), [
          { k: 'nombre', label: 'Nombre del equipo', req: 1, valor: b.getAttribute('data-lw-nombre') || '' },
          { k: 'manager_email', label: 'Email del manager', tipo: 'email', req: 1, valor: b.getAttribute('data-lw-manager') || '',
            ayuda: 'la persona que gestiona el reparto del equipo; cambiarlo cambia quién ve sus condiciones de nivel manager' }
        ], 'Guardar equipo', function (v) {
          return sb.from('equipos_venta').update({
            nombre: v.nombre.trim(), manager_email: v.manager_email.trim().toLowerCase()
          }).eq('id', id).select('id').then(unaFila);
        });
      };

      window.LW_V4.abreEditaMiembro = function (b) {
        if (!admin) return soloAdmin();
        var id = b.getAttribute('data-lw-edita-miembro');
        var equipos = (window.LW_V4.equiposLista || []);
        modal('Editar miembro — ' + (b.getAttribute('data-lw-email') || ''), [
          { k: 'equipo_id', label: 'Equipo', tipo: 'select', req: 1, valor: b.getAttribute('data-lw-equipo') || '', opciones: equipos },
          { k: 'closer_email', label: 'Email del closer', tipo: 'email', req: 1, valor: b.getAttribute('data-lw-email') || '',
            ayuda: 'Es la clave con la que se le atribuyen ventas y comisiones: si estaba mal escrito, corregirlo aquí las reengancha.' },
          { k: 'desde', label: 'Desde', tipo: 'date', req: 1, medio: 1, valor: b.getAttribute('data-lw-desde') || '' },
          { k: 'hasta', label: 'Hasta (opcional)', tipo: 'date', medio: 1, valor: b.getAttribute('data-lw-hasta') || '', ayuda: 'vacío = sigue activo' }
        ], 'Guardar miembro', function (v) {
          if (v.hasta && v.hasta < v.desde) return { error: { message: '«Hasta» no puede ser anterior a «Desde».' } };
          return sb.from('equipo_miembros').update({
            equipo_id: v.equipo_id, closer_email: v.closer_email.trim().toLowerCase(),
            desde: v.desde, hasta: v.hasta || null
          }).eq('id', id).select('id').then(unaFila);
        });
      };

      window.LW_V4.abreToggleEquipo = function (equipoId, nombre, activoActual) {
        if (!admin) return soloAdmin();
        var pasaA = !activoActual;
        modal((pasaA ? 'Reactivar' : 'Desactivar') + ' equipo — ' + (nombre || ''), [
          { tipo: 'nota', label: pasaA
              ? 'El equipo vuelve a estar disponible para nuevas condiciones de comisión.'
              : 'El equipo deja de ofrecerse para condiciones nuevas. Los miembros y el histórico de comisiones no se tocan.' }
        ], pasaA ? 'Reactivar' : 'Desactivar', function () {
          return sb.from('equipos_venta').update({ activo: pasaA }).eq('id', equipoId).select('id').then(unaFila);
        });
      };
    },

    condiciones: function (aut) {
      var sb = aut.sb, admin = esAdmin(aut.ficha);
      window.LW_V4 = window.LW_V4 || {};
      var soloAdmin = function () {
        return aviso('Las condiciones de comisión las da de alta solo administración (policy es_admin) — tu sesión es de ' +
          ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34');
      };

      ata(/^\+? ?Nueva condici[oó]n$/i, function () {
        if (!admin) return soloAdmin();
        Promise.all([
          sb.from('equipos_venta').select('id,nombre').eq('activo', true).order('nombre'),
          sb.from('proyectos').select('id,nombre').eq('activo', true).order('nombre')
        ]).then(function (r) {
          var equipos = (r[0] && r[0].data) || [], proyectos = (r[1] && r[1].data) || [];
          if (!equipos.length) return aviso('No hay equipos activos — crea uno primero en «Equipos de venta».', '#8A6A34');
          if (!proyectos.length) return aviso('No hay proyectos activos.', '#8A6A34');
          var getTramos = null;
          modal('Nueva condición de comisión', [
            { k: 'equipo_id', label: 'Equipo', tipo: 'select', req: 1, medio: 1,
              opciones: equipos.map(function (e) { return [e.id, e.nombre]; }) },
            { k: 'proyecto_id', label: 'Proyecto', tipo: 'select', req: 1, medio: 1,
              opciones: proyectos.map(function (p) { return [p.id, p.nombre]; }) },
            { k: 'nivel', label: 'Nivel', tipo: 'select', req: 1, medio: 1,
              opciones: [['manager', 'Manager'], ['closer', 'Closer']] },
            { k: 'closer_email', label: 'Override individual (email)', medio: 1,
              ayuda: 'solo con nivel «Closer» — vacío aplica a todo el equipo' },
            { k: 'pct_comision', label: '% de comisión', tipo: 'number', paso: '0.01', req: 1, medio: 1 },
            { k: 'base_calculo', label: 'Base de cálculo', tipo: 'select', req: 1, medio: 1,
              opciones: (window.LW_V4.BASES_CALCULO || BASES_CALCULO_FALLBACK) },
            { k: 'importe_fijo', label: 'Importe fijo', tipo: 'number', paso: '0.01', medio: 1,
              ayuda: 'solo si la base es «Importe fijo»' },
            { k: 'tramos', label: 'Tramos de pago (deben sumar 100%)', tipo: 'custom',
              render: function (d) { getTramos = montaTramos(d); } }
          ], 'Crear condición', function (v) {
            if (v.nivel === 'manager' && v.closer_email) {
              return { error: { message: 'El override individual solo aplica con nivel «Closer».' } };
            }
            var tramos = getTramos ? getTramos() : [];
            if (!tramos.length) return { error: { message: 'Añade al menos un tramo de pago.' } };
            var suma = 0;
            for (var i = 0; i < tramos.length; i++) {
              var t = tramos[i], pct = Number(t.pct_tramo);
              if (!t.disparador_tipo) return { error: { message: 'Falta el disparador del tramo ' + (i + 1) + '.' } };
              if (!(pct > 0) || pct > 100) return { error: { message: 'El tramo ' + (i + 1) + ' necesita un % entre 0 y 100.' } };
              if (/^pct_cobrado_/.test(t.disparador_tipo) && (t.umbral === '' || t.umbral == null)) {
                return { error: { message: 'El tramo ' + (i + 1) + ' necesita un umbral (%) para ese disparador.' } };
              }
              suma += pct;
            }
            // MISMA regla que el trigger `condicion_tramos_suma_100` de la base —
            // aquí ANTES de escribir nada, con un error legible y sin gastar un
            // viaje de red; el trigger es el respaldo si esto se saltara.
            if (Math.abs(suma - 100) > 0.01) {
              return { error: { message: 'Los tramos suman ' + (Math.round(suma * 100) / 100) + '% — deben sumar exactamente 100% antes de guardar.' } };
            }
            if (v.base_calculo === 'importe_fijo' && !(Number(v.importe_fijo) > 0)) {
              return { error: { message: 'La base «Importe fijo» exige un importe mayor que 0.' } };
            }
            if (v.base_calculo !== 'importe_fijo' && v.importe_fijo) {
              return { error: { message: 'El importe fijo solo aplica cuando la base es «Importe fijo».' } };
            }
            // id generado aquí (no `.select().single()` tras el insert): evita un
            // viaje de red extra y el matiz de que un INSERT sin `.select()` no
            // aplica la policy de SELECT sobre la fila nueva. Sin fallback: la
            // columna es `uuid`, y un id que no lo sea rompe el INSERT con un
            // error de cast confuso en vez de uno claro — mejor decirlo aquí.
            // `crypto.randomUUID` ya lo usa el resto de la v4 (proyectos/) sin
            // comprobar `window.crypto` antes: mismo contrato de navegador.
            if (!(window.crypto && crypto.randomUUID)) {
              return { error: { message: 'Este navegador no soporta crypto.randomUUID() — actualiza el navegador para crear condiciones.' } };
            }
            var condId = crypto.randomUUID();
            return sb.from('condiciones_comision').insert({
              id: condId, equipo_id: v.equipo_id, proyecto_id: v.proyecto_id, nivel: v.nivel,
              closer_email: v.nivel === 'closer' ? (v.closer_email ? v.closer_email.trim().toLowerCase() : null) : null,
              pct_comision: Number(v.pct_comision), base_calculo: v.base_calculo,
              importe_fijo: v.base_calculo === 'importe_fijo' ? Number(v.importe_fijo) : null
            }).then(function (r) {
              if (r.error) return r;
              var filas = tramos.map(function (t, i) {
                return {
                  condicion_id: condId, orden: i + 1, disparador_tipo: t.disparador_tipo,
                  umbral: /^pct_cobrado_/.test(t.disparador_tipo) ? Number(t.umbral) : null,
                  pct_tramo: Number(t.pct_tramo)
                };
              });
              return sb.from('condicion_tramos').insert(filas).then(function (r2) {
                if (r2.error) {
                  // condición huérfana sin tramos: se limpia sola — solo llega
                  // hasta aquí quien ya es admin, así que el DELETE no tropieza
                  // con una policy nueva.
                  return sb.from('condiciones_comision').delete().eq('id', condId).then(function () { return r2; });
                }
                return r2;
              });
            });
          });
        });
      });

      /* BORRAR (18-sep-2026, owner: «permíteme borrar condiciones que no
         quiera»). Los tramos caen en cascada (FK). Las comisiones YA devengadas
         NO: su FK es NO ACTION, asi que si las hay la base rechaza el DELETE —
         se mira antes y se dice en claro, en vez de dejar que salga el error
         de clave foranea. Sin papelera: por eso «Desactivar» sigue al lado. */
      window.LW_V4.abreBorraCondicion = function (b) {
        if (!admin) return soloAdmin();
        var id = b.getAttribute('data-lw-borra-cond'), etq = b.getAttribute('data-lw-etq') || '';
        // el boton solo sale en filas desactivadas; esto es por si alguien lo llama a mano
        var cond = ((window.LW_V4.condicionesLista || {})[id]);
        if (cond && cond.activo) return aviso('Desactiva la condición antes de borrarla: una activa puede estar aplicándose a contratos firmados.', '#8A6A34');
        sb.from('comisiones_devengadas').select('id', { count: 'exact', head: true }).eq('condicion_id', id).then(function (r) {
          var n = r.error ? 0 : (r.count || 0);
          if (n) {
            return modal('No se puede borrar — ' + etq, [
              { tipo: 'nota', label: 'Esta condición ya ha devengado ' + n + (n === 1 ? ' comisión' : ' comisiones') + ' que la citan: la base no deja borrarla. Desactívala en su lugar — deja de aplicarse a lo nuevo y lo devengado se conserva.' }
            ], 'Entendido', function () { return Promise.resolve({}); }, { sinRecarga: true });
          }
          modal('Borrar condición — ' + etq, [
            { tipo: 'nota', label: 'Se borra la condición con sus tramos. No hay papelera: si la vuelves a necesitar habrá que crearla de nuevo. Si solo quieres que deje de aplicarse, usa «Desactivar».' }
          ], 'Borrar definitivamente', function () {
            return sb.from('condiciones_comision').delete().eq('id', id).select('id').then(unaFila);
          });
        });
      };

      window.LW_V4.abreToggleCondicion = function (condId, etiqueta, activoActual) {
        if (!admin) return soloAdmin();
        var pasaA = !activoActual;
        modal((pasaA ? 'Reactivar' : 'Desactivar') + ' condición — ' + (etiqueta || ''), [
          { tipo: 'nota', label: pasaA
              ? 'Vuelve a aplicarse a las comisiones que se disparen desde ahora.'
              : 'Deja de aplicarse a comisiones nuevas. Lo ya devengado no cambia.' }
        ], pasaA ? 'Reactivar' : 'Desactivar', function () {
          return sb.from('condiciones_comision').update({ activo: pasaA }).eq('id', condId).select('id').then(unaFila);
        });
      };
    },

    /* Cuentas de cobro (15-sep-2026, encargo del owner: "fixea Cuentas en v4,
       tanto las tablas como la caja para darlas de alta"). Solo el ALTA vive
       aquí: crear una fila en `cuentas_bancarias` (RLS "cuentas: solo super
       admin crea", with_check es_super_admin() — verificado contra el
       esquema real, no supuesto). El resto del editor de /intranet/cuentas/
       —reparto por plantilla/proyecto con casillas, nota en tres idiomas,
       activar/desactivar una cuenta ya creada— se queda en la herramienta
       viva a propósito: es un master-detail de 1000+ líneas que no encaja en
       la piel de tarjetas de la v4, y portarlo entero no es lo que se pidió.
       El botón "Abrir la herramienta viva" sigue ahí para eso. */
    /* Comision de administracion — SOLO super admin, y no por gusto: la RLS de
       las dos tablas exige `es_super_admin()`, y las cuatro acciones de aqui son
       RPC que vuelven a comprobarlo en la base. Lo de esta pantalla es UI.

       Las cuatro abren el CAJON LATERAL (`modal`, que ya es lateral en toda la
       v4): editar tarifa, cambiar estado, anular y reponer.

       Por que tres de ellas son RPC y no un UPDATE suelto:
         · editar tarifa -> hay que guardar la version anterior antes de pisarla,
           o se pierde la respuesta a «que % regia el dia que entro este euro»
         · anular -> si la comision ya estaba facturada, hay que emitir el abono;
           un UPDATE se lo saltaria y dejaria dinero emitido sin contrapartida
         · reponer -> `anulada` esta fuera del grant del navegador a proposito
       Solo «cambiar estado» es un UPDATE, porque no arrastra nada detras. */
    'comision-admin': function (aut) {
      var sb = aut.sb;
      var superAdmin = !!(aut.ficha && aut.ficha.rol === 'super_admin');
      window.LW_V4 = window.LW_V4 || {};
      var hoy = new Date().toISOString().slice(0, 10);

      var soloSuper = function () {
        return aviso('La comision de administracion es solo para super_admin — tu sesion es de ' +
          ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34');
      };
      var linea = function (id) {
        return (window.LW_V4.caLineas && window.LW_V4.caLineas[id]) || {};
      };
      /* Toda RPC de este panel devuelve `{ok:false, motivo}` cuando rechaza sin
         ser un error: el modal espera `{error:{message}}`, asi que se traduce
         aqui una vez en vez de en cada llamada. */
      var rpc = function (nombre, args) {
        return sb.rpc(nombre, args).then(function (r) {
          if (r.error) return r;
          if (r.data && r.data.ok === false) return { error: { message: r.data.motivo || 'No se pudo hacer.' } };
          return r;
        });
      };

      // ── Nueva tarifa ────────────────────────────────────────────────────────
      ata(/^\+? ?Nueva tarifa$/i, function () {
        if (!superAdmin) return soloSuper();
        var cache = window.LW_V4 && window.LW_V4.tarifas;
        if (cache) return abreNuevaTarifa(cache);
        /* Si datos.js no ha resuelto todavia, se pregunta a la base en vez de
           suponer: el texto del cajon dice que % rige ahora mismo, y decirlo mal
           justo en el momento de elegir el numero nuevo es peor que tardar. */
        sb.from('comision_admin_tarifas').select('id,pct,efectivo_desde')
          .order('efectivo_desde', { ascending: false })
          .then(function (r) {
            if (r.error) return aviso('No se han podido leer las tarifas vigentes, asi que no se puede decir que % rige ahora mismo. Recarga la pantalla y prueba otra vez.', '#9E2F26');
            abreNuevaTarifa(r.data || []);
          });
      });

      function abreNuevaTarifa(tarifas) {
        var vigente = (tarifas || []).filter(function (t) { return t.efectivo_desde <= hoy; })[0] || null;
        modal('Nueva tarifa', [
          { k: 'pct', label: '% de comision', tipo: 'number', paso: '0.0001', req: 1, medio: 1,
            valor: vigente ? Number(vigente.pct) : 0.5,
            ayuda: 'sobre el dinero que entra por cada recibi' },
          { k: 'efectivo_desde', label: 'Rige desde', tipo: 'date', req: 1, medio: 1, valor: hoy },
          { k: 'nota', label: 'Por que cambia' },
          { tipo: 'nota', label: vigente
              ? ('Ahora rige el ' + Number(vigente.pct) + '% desde el ' + vigente.efectivo_desde +
                 '. La tarifa vieja NO se borra y lo ya devengado NO se recalcula: cada linea guarda congelado el % que regia su dia. Si lo que quieres es cambiar la que ya existe, cierra esto y pulsa «Editar» en su fila.')
              : 'Todavia no hay ninguna tarifa, asi que no se esta devengando nada. Esta sera la primera.' }
        ], 'Crear tarifa', function (v) {
          var pct = Number(v.pct);
          if (!(pct >= 0) || pct > 100) {
            return { error: { message: 'El porcentaje va entre 0 y 100. Ojo con el separador: medio por ciento es 0,5 — no 50.' } };
          }
          /* Freno al dedo gordo, no regla de negocio (la base acepta cualquier %
             entre 0 y 100 a proposito): 0,5 tecleado como 5 multiplica por diez
             la factura de un mes entero y nadie lo nota hasta emitirla. */
          if (pct > 5 && !window.confirm('Vas a fijar la comision en ' + pct + '%.\n\n' +
              (vigente ? 'La vigente es del ' + Number(vigente.pct) + '%. ' : '') +
              'Se aplicara a todo el dinero que entre desde el ' + v.efectivo_desde + '.\n\nSeguro?')) {
            return { error: { message: 'Cancelado: no se ha creado ninguna tarifa.' } };
          }
          return sb.from('comision_admin_tarifas').insert({
            pct: pct,
            efectivo_desde: v.efectivo_desde,
            nota: (v.nota || '').trim() || null,
            creado_por: (aut.session && aut.session.user && aut.session.user.email) || null
          }).select('id').single();
        });
      }

      // ── Editar una tarifa que ya existe ─────────────────────────────────────
      window.LW_V4.abreEditaTarifaComisionAdmin = function (btn) {
        if (!superAdmin) return soloSuper();
        var id = btn.getAttribute('data-lw-ca-tarifa');
        var t = (window.LW_V4.tarifaPorId && window.LW_V4.tarifaPorId[id]) || {};
        var lineas = (window.LW_V4.caLineas && Object.keys(window.LW_V4.caLineas).map(function (k) { return window.LW_V4.caLineas[k]; })) || [];
        var pendientes = lineas.filter(function (l) {
          return l.tarifa_id === id && l.tipo_linea === 'devengo' && l.estado === 'pendiente' && !l.anulada;
        }).length;

        modal('Editar tarifa', [
          { k: 'pct', label: '% de comision', tipo: 'number', paso: '0.0001', req: 1, medio: 1, valor: Number(t.pct) },
          { k: 'efectivo_desde', label: 'Rige desde', tipo: 'date', req: 1, medio: 1, valor: t.efectivo_desde },
          { k: 'nota', label: 'Nota', valor: t.nota || '' },
          { k: 'recalcular', label: 'Recalcular tambien las comisiones ya devengadas que siguen pendientes', tipo: 'check',
            ayuda: pendientes
              ? ('son ' + pendientes + ' linea(s); las ya facturadas o cobradas no se tocan nunca')
              : 'ahora mismo no hay ninguna pendiente con esta tarifa' },
          { tipo: 'nota', label: 'Lo que habia antes se guarda entero antes de pisarlo, asi que se puede seguir diciendo que % regia cada dia. Sin marcar la casilla, cambiar el % NO altera ni un euro de lo ya devengado: cada linea lleva congelado el suyo.' }
        ], 'Guardar tarifa', function (v) {
          var pct = Number(v.pct);
          if (!(pct >= 0) || pct > 100) {
            return { error: { message: 'El porcentaje va entre 0 y 100. Medio por ciento es 0,5 — no 50.' } };
          }
          if (v.recalcular && pendientes && !window.confirm(
              'Vas a reescribir ' + pendientes + ' comision(es) ya devengada(s) con el ' + pct + '%.\n\n' +
              'Las facturadas y cobradas no se tocan. Seguro?')) {
            return { error: { message: 'Cancelado: la tarifa no se ha tocado.' } };
          }
          return rpc('comision_admin_edita_tarifa', {
            p_tarifa_id: id, p_pct: pct, p_efectivo_desde: v.efectivo_desde,
            p_nota: (v.nota || '').trim() || null, p_recalcular: !!v.recalcular
          });
        });
      };

      // ── Estado de cobro de una linea ────────────────────────────────────────
      window.LW_V4.abreEstadoComisionAdmin = function (btn) {
        if (!superAdmin) return soloSuper();
        var id = btn.getAttribute('data-lw-ca-estado');
        var etiqueta = btn.getAttribute('data-lw-etq');
        var actual = btn.getAttribute('data-lw-actual');
        /* La nota VIENE RELLENA: el campo nacia vacio y el parche la escribia
           siempre, asi que marcar una linea como facturada borraba la unica
           explicacion de por que existe — y en un ajuste o un desanulado esa
           nota la escribio el propio sistema. */
        var notaActual = linea(id).nota || '';
        modal('Estado de la comision — ' + (etiqueta || ''), [
          { k: 'estado', label: 'Estado', tipo: 'select', req: 1, valor: actual,
            opciones: [['pendiente', 'Pendiente'], ['facturada', 'Facturada'],
                       ['cobrada', 'Cobrada'], ['exenta', 'Exenta (no se cobra)']] },
          { k: 'nota', label: 'Nota', valor: notaActual,
            ayuda: notaActual ? 'lo que hay escrito lo puso el sistema al detectar un cambio — borrarlo pierde el porque de esta linea' : '' },
          { k: 'revisar', label: 'Dejar de marcarla para revisar', tipo: 'check',
            ayuda: 'solo la bandera; si el descuadre es real sigue saliendo en el aviso de arriba, que se recalcula desde la base' },
          { tipo: 'nota', label: 'El importe, la base y el % no se tocan desde aqui: los calcula la base sobre el recibi. «Exenta» deja la linea sin cobrar sin anularla — util para una correccion, pero ojo: la tarifa acordada es sobre TODO el dinero que entra, asi que exonerar una linea es salirse de ella.' }
        ], 'Guardar', function (v) {
          var parche = { estado: v.estado };
          if ((v.nota || '').trim() !== notaActual.trim()) parche.nota = (v.nota || '').trim() || null;
          if (v.revisar) parche.revisar = false;
          /* `.select()` detras del UPDATE: un UPDATE que no toca ninguna fila NO
             da error en PostgREST, asi que sin esto una sesion sin permiso veria
             «guardado» y no habria guardado nada. */
          return sb.from('comision_admin_lineas').update(parche).eq('id', id).select('id,estado').single();
        });
      };

      // ── Anular una comision ─────────────────────────────────────────────────
      window.LW_V4.abreAnulaComisionAdmin = function (btn) {
        if (!superAdmin) return soloSuper();
        var id = btn.getAttribute('data-lw-ca-anula');
        var etiqueta = btn.getAttribute('data-lw-etq');
        var estado = btn.getAttribute('data-lw-estado');
        var l = linea(id);
        var yaEmitida = estado !== 'pendiente' && estado !== 'exenta';
        modal('Anular la comision — ' + (etiqueta || ''), [
          { tipo: 'lectura', label: 'Importe que deja de cobrarse', medio: 1,
            valor: (typeof lwFormatoImporte === 'function' ? lwFormatoImporte(l.importe, l.moneda) : (l.importe + ' ' + (l.moneda || ''))) },
          { tipo: 'lectura', label: 'Estado actual', medio: 1, valor: estado || '—' },
          { k: 'motivo', label: 'Motivo', req: 1,
            ayuda: 'queda escrito en la linea y en el rastro; es lo que explicara este hueco dentro de seis meses' },
          { tipo: 'nota', label: yaEmitida
              ? 'Esta comision YA estaba ' + estado + ', asi que anularla genera ademas una linea de ABONO por el importe neto: el libro tiene que seguir cuadrando con lo que ya se emitio. El abono queda pendiente y visible.'
              : 'La linea queda anulada y deja de contar en los totales. Sus ajustes, si los tiene, se anulan con ella. El recibi NO se toca: esto solo anula la comision, no el cobro.' }
        ], 'Anular comision', function (v) {
          return rpc('comision_admin_anula_linea', { p_linea_id: id, p_motivo: (v.motivo || '').trim() });
        });
      };

      // ── Reponer una comision anulada ────────────────────────────────────────
      window.LW_V4.abreReponeComisionAdmin = function (btn) {
        if (!superAdmin) return soloSuper();
        var id = btn.getAttribute('data-lw-ca-repone');
        var etiqueta = btn.getAttribute('data-lw-etq');
        modal('Reponer la comision — ' + (etiqueta || ''), [
          { tipo: 'nota', label: 'Vuelve a contar en los totales y queda marcada para revisar. Si el recibi sigue anulado o ya no existe, la base lo rechaza: reponerla dejaria el libro cobrando sobre dinero que no entro.' }
        ], 'Reponer', function () {
          return rpc('comision_admin_repone_devengo', { p_linea_id: id });
        });
      };
    },

    /* ---------- Cuentas de cobro y su reparto (18-sep-2026) ----------
       Hasta hoy esta pantalla solo sabia dar de ALTA una cuenta; todo lo demas
       habia que ir a hacerlo a /intranet/cuentas/. Ahora hereda las cuatro
       acciones de la herramienta viva, que es lo que Regla 0 bis de
       `contexto/suite_lawang.md` exige de una version de diseño: mismas
       funcionalidades, otra piel.

       Lo caro no son los formularios, son las reglas que llevan dentro y que se
       heredan una por una de /intranet/cuentas/:
       · `clave` NO se edita jamas: viaja dentro de cada contrato y cada factura
         ya emitidos (`datos.fields.cuenta_bancaria`). Renombrarla dejaria
         documentos firmados apuntando a algo que no existe.
       · archivar es un FLAG y nunca un borrado: `plantilla_cuentas` cuelga de
         `plantillas_contrato` con ON DELETE CASCADE, asi que borrar un tipo
         archivado se llevaria su reparto por delante sin decir una palabra, y al
         desarchivarlo volveria sin cuentas.
       · una cuenta de ESCROW nunca en el nivel `'*'` de un proyecto sin
         confirmarlo: dejaria su Carta de Reserva ofreciendo solo un deposito en
         garantia que la Carta no pacta (verificado: los contratos de obra de
         Soka cobran en la cuenta de empresa, no en su notario).
       · toda escritura se verifica contra las filas devueltas (`verifica`): la
         RLS de estas cuatro tablas deniega con CERO filas y sin error.

       Lo que NO se porta, dicho a proposito: el buscador `#qC` de la herramienta
       viva (aqui las tres tablas son cortas y se ven enteras) y el `orden` de una
       cuenta, que alli tampoco se edita — nace al final de la lista. */
    cuentas: function (aut) {
      var sb = aut.sb, superAdmin = !!(aut.ficha && aut.ficha.rol === 'super_admin');
      var soloSuper = function () {
        return aviso('Cambiar una cuenta de cobro o su reparto es solo para super_admin (policy es_super_admin) — tu sesión es de ' +
          ((aut.ficha && aut.ficha.rol) || 'agente') + '. Puedes verlo en las tablas.', '#8A6A34');
      };
      // los datos que `datos.js` ya leyo y publico: abrir un cajon no vuelve a consultar
      var D = function () { return (window.LW_V4 && window.LW_V4.cuentas) || null; };
      var recarga = function () {
        var f = window.LW_V4 && window.LW_V4.recargaCuentas;
        if (f) f(); else location.reload();
      };
      var sinDatos = function () { return aviso('Los datos de la pantalla aún no han cargado — prueba de nuevo en un segundo.', '#8A6A34'); };
      var etq = function (d, clave) {
        var c = d.cuentas.filter(function (x) { return x.clave === clave; })[0];
        return c ? (c.label || c.clave) : clave;
      };
      /* Las desactivadas no se ofrecen para marcar: estan fuera de todos los
         desplegables por definicion. Pero si alguna esta YA marcada aqui (se
         desactivo despues) se enseña, porque si no desaparece de la pantalla una
         fila que si existe en la base. */
      var candidatas = function (d, yaMarcadas) {
        return d.cuentas.filter(function (c) { return c.activa || yaMarcadas[c.clave]; })
          .map(function (c) { return { clave: c.clave, label: c.label || c.clave, escrow: c.es_escrow, activa: c.activa }; });
      };
      var marcadasDe = function (filas) {
        var m = {}; filas.forEach(function (x) { m[x.clave] = true; }); return m;
      };
      var defDe = function (filas) {
        var f = filas.filter(function (x) { return x.es_default; })[0];
        return f ? f.clave : null;
      };

      /* ═══ 1. POR CONTRATO — la vista del encargo original del owner: se abre un
         tipo de documento y se marcan sus cuentas. Aqui vive ademas el archivado,
         con la cifra de uso delante: es lo que separa la morralla de lo que se usa
         poco. */
      window.LW_V4 = window.LW_V4 || {};
      window.LW_V4.abreRepartoContrato = function (b) {
        if (!superAdmin) return soloSuper();
        var d = D(); if (!d) return sinDatos();
        var slug = b.getAttribute('data-lw-cu-contrato');
        var p = d.plantillas.filter(function (x) { return x.slug === slug; })[0];
        if (!p) return sinDatos();
        var filas = d.reparto.filter(function (x) { return x.slug === slug; });
        var u = d.usoTipo && d.usoTipo[slug];
        var lee = null;

        var encabezado = '<div style="font-weight:400;font-size:12.5px;line-height:1.5;color:#44483f">' +
          '<b>' + esc(p.slug) + '</b> · ' +
          (u ? esc(u.contratos + ' contratos emitidos, ' + u.firmados + ' firmados') +
               (u.ultimo ? ' · último ' + esc(new Date(u.ultimo).toLocaleDateString('es-ES')) : '')
             /* «no he podido mirarlo» y «no se usa» se parecen en pantalla y solo
                una es cierta: archivar un tipo creyendo que no se usa es justo la
                decision que esta cifra sostiene. */
             : (d.usoTipo === null ? '<span style="color:#93000a">no se ha podido leer cuántos contratos hay de este tipo</span>'
                                   : 'sin usar todavía')) + '</div>';

        var campos = [
          { k: 'archivada', tipo: 'check', valor: p.archivada,
            label: 'Archivado — no aparece al crear un contrato',
            ayuda: 'Solo lo retira del desplegable de «Nuevo contrato». Lo ya emitido no cambia, y un contrato guardado de este tipo se sigue abriendo, imprimiendo y firmando.' }
        ];
        if (u && u.firmados && !p.archivada) {
          campos.push({ tipo: 'nota', label: 'Tiene ' + u.firmados + ' contratos FIRMADOS. Archivarlo no los toca: se siguen abriendo e imprimiendo.' });
        }
        if (p.cobra) {
          campos.push({ tipo: 'custom', render: function (host) {
            lee = montaReparto(host, candidatas(d, marcadasDe(filas)),
              { claves: marcadasDe(filas), def: defDe(filas) },
              { titulo: 'Qué cuentas puede elegir el agente en este contrato' });
          } });
          campos.push({ tipo: 'nota', label: 'Un contrato YA GUARDADO conserva la cuenta con la que se hizo, aunque aquí la desmarques. No se reescribe nada de lo emitido.' });
        } else {
          campos.push({ tipo: 'nota', label: 'Este documento no lleva datos bancarios (no cobra), así que no hay ninguna cuenta que repartir.' });
        }

        modal(p.nombre || slug, campos, 'Guardar', function (v) {
          var pasos = [];
          if (!!v.archivada !== !!p.archivada) {
            pasos.push(function () {
              return verifica(sb.from('plantillas_contrato').update({ archivada: !!v.archivada })
                .eq('slug', slug).select('slug'), 'No se pudo cambiar el archivado');
            });
          }
          if (p.cobra && lee) {
            var ahora = lee();
            pasos.push(function () { return guardaReparto(sb, 'plantilla_cuentas', { slug: slug }, filas, ahora); });
          }
          /* `recarga()` va en las DOS ramas. Si solo fuera en la buena, tras un
             fallo a media cadena el cajon seguiria diffeando contra los datos de
             antes, y el segundo intento borraria una fila ya borrada — cero filas,
             que se leeria como «no tienes permiso». */
          return enCadena(pasos).then(function (r) {
            recarga();
            return (r && r.error) ? r : null;
          });
        }, { sub: 'Reparto por contrato', encabezado: encabezado, sinRecarga: true });
      };

      /* ═══ 2. POR PROYECTO — la EXCEPCION, no una matriz. Un proyecto que no
         aparece hereda, y eso es lo normal y lo correcto: 8 tipos × 29 proyectos
         son 232 casillas que nadie mantiene. Marcar algo aqui RESTRINGE. */
      window.LW_V4.abreRepartoProyecto = function (b) {
        if (!superAdmin) return soloSuper();
        var d = D(); if (!d) return sinDatos();
        var id = b.getAttribute('data-lw-cu-proyecto');
        var nombre = b.getAttribute('data-lw-etq') || 'Proyecto';
        var mias = d.repartoProyecto.filter(function (x) { return String(x.proyecto_id) === String(id); });

        /* Los bloques: «cualquier contrato» primero, luego los tipos que cobran y
           siguen ofreciendose, y ademas cualquier tipo que YA tenga excepcion aqui
           aunque este archivado — si no, una regla viva desaparece de la pantalla
           y no hay forma de quitarla. */
        var conRegla = {}; mias.forEach(function (x) { conRegla[x.slug] = true; });
        var bloques = [{ slug: '*', nombre: 'Cualquier contrato de este proyecto' }];
        d.plantillas.forEach(function (t) {
          if ((t.cobra && !t.archivada) || (conRegla[t.slug] && t.slug !== '*')) {
            bloques.push({ slug: t.slug, nombre: t.nombre || t.slug, archivada: t.archivada });
          }
        });

        var lectores = [];
        var campos = [
          { tipo: 'nota', label: 'Marcar una cuenta aquí RESTRINGE: ese tipo de contrato, en este proyecto, dejará de ofrecer las demás. Sin nada marcado hereda el reparto general, que es lo normal.' },
          { tipo: 'custom', render: function (host) {
            bloques.forEach(function (bl) {
              var filas = mias.filter(function (x) { return x.slug === bl.slug; });
              var marcadas = marcadasDe(filas);
              var items = candidatas(d, marcadas).map(function (it) {
                /* El aviso donde de verdad muerde, y solo ahi: una cuenta de
                   escrow en «cualquier contrato» haria que la Carta de Reserva
                   de este proyecto ofreciera un deposito en garantia que no
                   pacta. */
                if (bl.slug === '*' && it.escrow) {
                  it.peligro = 'Es una cuenta de escrow: aquí valdría para TODOS los contratos del proyecto, incluidos los que no pactan depósito en garantía.';
                }
                return it;
              });
              lectores.push({ slug: bl.slug, antes: filas,
                lee: montaReparto(host, items, { claves: marcadas, def: defDe(filas) },
                  { titulo: bl.nombre + (bl.archivada ? ' (archivado)' : ''),
                    sub: filas.length ? filas.length + ' reglas propias' : 'hereda el reparto general',
                    vacioOk: true }) });
            });
          } }
        ];

        modal(nombre, campos, 'Guardar', function () {
          var estados = lectores.map(function (L) { return { slug: L.slug, antes: L.antes, ahora: L.lee() }; });
          /* La confirmacion de peligro va ANTES de escribir nada, y con el dialogo
             de la suite (`dialogo.js`), nunca con el `confirm()` del navegador:
             arranca el foco en Cancelar y admite tono «peligro». */
          var todos = estados.filter(function (e) { return e.slug === '*'; })[0];
          var nuevasEscrow = [];
          if (todos) {
            var antesTodos = {}; todos.antes.forEach(function (x) { antesTodos[x.clave] = true; });
            todos.ahora.claves.forEach(function (cl) {
              var c = d.cuentas.filter(function (x) { return x.clave === cl; })[0];
              if (c && c.es_escrow && !antesTodos[cl]) nuevasEscrow.push(c.label || cl);
            });
          }
          var previo = !nuevasEscrow.length ? Promise.resolve(true)
            : (typeof lwConfirmar === 'function'
                ? lwConfirmar({
                    titulo: '¿Una cuenta de escrow para TODOS los contratos?',
                    cuerpo: '«' + nuevasEscrow.join('», «') + '» es una cuenta de ESCROW y la estás marcando para CUALQUIER contrato de este proyecto. Sus contratos de obra y sus cartas de reserva pasarían a ofrecer solo esa cuenta, con una cláusula de depósito en garantía que no pactan.',
                    confirmar: 'Marcarla igualmente', tono: 'peligro'
                  })
                /* Si `dialogo.js` no cargo, NO se sigue en silencio: se para y se
                   dice. Una confirmacion que se salta sola no es una confirmacion. */
                : Promise.resolve(false));

          return Promise.resolve(previo).then(function (sigo) {
            if (!sigo) return { error: { message: 'Cancelado: no se ha guardado nada. Una cuenta de escrow en «cualquier contrato» hay que confirmarla.' } };
            return enCadena(estados.map(function (e) {
              return function () {
                return guardaReparto(sb, 'proyecto_cuentas', { proyecto_id: id, slug: e.slug }, e.antes, e.ahora);
              };
            })).then(function (r) {
              recarga();                     // en las dos ramas: ver la nota de «por contrato»
              return (r && r.error) ? r : null;
            });
          });
        }, { sub: 'Excepción por proyecto', sinRecarga: true });
      };

      /* ═══ 3. POR CUENTA — mantenimiento del dato que el comprador lee en su
         contrato, y el reparto visto desde el otro lado. */
      window.LW_V4.abreEditaCuenta = function (b) {
        if (!superAdmin) return soloSuper();
        var d = D(); if (!d) return sinDatos();
        var clave = b.getAttribute('data-lw-cu-cuenta');
        var c = d.cuentas.filter(function (x) { return x.clave === clave; })[0];
        if (!c) return sinDatos();
        var nota = lwNotaCuenta.lee(c.extra);
        var u = d.uso && d.uso[clave];
        var leeRep = null;

        /* Que hay YA EMITIDO con esta cuenta, con la cifra, encima de los campos
           que se pueden cambiar. La distincion que importa es firmados / no
           firmados: un contrato sin firmar se corrige, uno firmado es un documento
           que alguien tiene en la mano. */
        var encabezado = '<div style="font-weight:400;font-size:12.5px;line-height:1.5;color:#44483f">' +
          'clave <b>' + esc(clave) + '</b> — no se cambia nunca: va dentro de cada contrato y cada factura ya emitidos.' +
          (c.actualizado_en ? '<br>última edición ' + esc(new Date(c.actualizado_en).toLocaleDateString('es-ES')) : '') +
          '</div>' +
          (d.uso === null
            /* Sin cifra NO se calla la advertencia: se edita el titular o el numero
               de una cuenta que puede estar impresa en contratos firmados. */
            ? '<div style="margin-top:8px;font-weight:400;font-size:12.5px;line-height:1.5;padding:10px 12px;border-radius:10px;' +
              'color:#93000a;background:#ffdad6;border:1px solid #f5b8b2">No se ha podido comprobar en cuántos contratos está esta cuenta ni cuántos hay firmados. Si los hay, cambiar el titular, el número o la casilla ESCROW cambia lo que imprimen al reabrirlos.</div>'
            : u && u.contratos
            ? '<div style="margin-top:8px;font-weight:400;font-size:12.5px;line-height:1.5;padding:10px 12px;border-radius:10px;' +
              (u.firmados ? 'color:#93000a;background:#ffdad6;border:1px solid #f5b8b2' : 'color:#8A6A34;background:#FBF3E4;border:1px solid #EBDCB4') + '">' +
              (u.firmados
                ? 'Está en ' + u.contratos + ' contratos, y ' + u.firmados + ' ya FIRMADOS. Si cambias el titular, el número o la casilla ESCROW, cambia lo que imprimen esos documentos cuando alguien los reabra. Para una cuenta distinta, crea una nueva en vez de reescribir esta.'
                : 'Está en ' + u.contratos + ' contratos, ninguno firmado todavía.') +
              '</div>'
            : '');

        modal(c.label || clave, [
          { k: 'label', label: 'Etiqueta (la que se ve en el desplegable)', valor: c.label, req: 1 },
          { k: 'titular', label: 'Titular', valor: c.titular, medio: 1 },
          { k: 'banco', label: 'Banco', valor: c.banco, medio: 1 },
          { k: 'cuenta', label: 'Número de cuenta', valor: c.cuenta, medio: 1 },
          { k: 'codigo', label: 'Código Swift / Routing', valor: c.codigo, medio: 1 },
          { k: 'direccion', label: 'Domicilio del banco', valor: c.direccion },
          { k: 'nota_es', tipo: 'textarea', valor: nota.es, label: 'Nota que se imprime en el contrato — ES' },
          { k: 'nota_en', tipo: 'textarea', valor: nota.en, label: 'Nota — EN', medio: 1 },
          { k: 'nota_id', tipo: 'textarea', valor: nota.id, label: 'Nota — ID', medio: 1 },
          { tipo: 'nota', label: 'Si solo rellenas ES, se imprime ese texto en los tres idiomas. En cuanto pongas EN o ID, cada idioma imprime el suyo.' },
          { k: 'es_escrow', tipo: 'check', valor: c.es_escrow, label: 'Es una cuenta ESCROW (depósito en garantía)',
            ayuda: 'Añade o quita sola en el contrato la fila «Naturaleza de la cuenta — depósito en garantía». Va en los DOS sentidos y alcanza a lo ya emitido: al reimprimir un contrato firmado con esta cuenta, marcarla le mete una cláusula que no pactó y desmarcarla le quita una que sí pactó. Tócala solo si está mal puesta.' },
          { k: 'activa', tipo: 'check', valor: c.activa, label: 'Activa',
            ayuda: '⚠️ Desactivarla la retira de todos los desplegables, y además los contratos y facturas ya emitidos con ella salen SIN el bloque de datos bancarios al reabrirlos o reimprimirlos, sin ningún aviso (verificado el 18-sep: entities.js carga solo las activas y la tabla se omite entera si falta la clave). La fila no se borra y reactivarla lo devuelve todo. Si la cuenta está en documentos emitidos, déjala activa y quítala del reparto.' },
          { tipo: 'custom', render: function (host) { leeRep = montaRepartoPorCuenta(host, d, clave); } }
        ], 'Guardar cambios', function (v) {
          /* `clave` NO va en el update, a proposito. Y cada escritura pasa por
             `verifica`: un UPDATE que la RLS deja en cero filas no devuelve error. */
          var pasos = [function () {
            return verifica(sb.from('cuentas_bancarias').update({
              label: v.label, titular: v.titular, banco: v.banco, cuenta: v.cuenta,
              codigo: v.codigo, direccion: v.direccion,
              extra: lwNotaCuenta.aJson({ es: v.nota_es, en: v.nota_en, id: v.nota_id }),
              es_escrow: !!v.es_escrow, activa: !!v.activa
            }).eq('clave', clave).select('clave'), 'No se pudo guardar la cuenta');
          }];
          if (leeRep) {
            leeRep().forEach(function (cambio) {
              pasos.push(function () {
                return guardaReparto(sb, 'plantilla_cuentas', { slug: cambio.slug }, cambio.antes, cambio.ahora);
              });
            });
          }
          /* `recarga()` va en las DOS ramas. Si solo fuera en la buena, tras un
             fallo a media cadena el cajon seguiria diffeando contra los datos de
             antes, y el segundo intento borraria una fila ya borrada — cero filas,
             que se leeria como «no tienes permiso». */
          return enCadena(pasos).then(function (r) {
            recarga();
            return (r && r.error) ? r : null;
          });
        }, { sub: 'Cuenta de cobro', encabezado: encabezado, sinRecarga: true });
      };

      /* ═══ 4. ALTA de una cuenta. La `clave` se pide una vez y no se cambia
         jamas; la cuenta nace DESACTIVADA y sin ningun contrato asignado, a
         proposito: no puede aparecer en el desplegable de un contrato antes de
         que alguien haya comprobado el numero con el justificante delante. */
      var btn = ata(/^\+? ?Nueva cuenta$/i, function () {
        if (!superAdmin) return soloSuper();
        // claves existentes + siguiente `orden`: hace falta antes de abrir el
        // formulario para validar unicidad sin ir y volver a la base al guardar.
        sb.from('cuentas_bancarias').select('clave,orden').then(function (r) {
          var existentes = (r && r.data) || [];
          var claves = {};
          existentes.forEach(function (c) { claves[c.clave] = 1; });
          var siguienteOrden = existentes.reduce(function (m, c) { return Math.max(m, c.orden || 0); }, 0) + 10;
          modal('Nueva cuenta de cobro', [
            { k: 'clave', label: 'Clave interna (no se puede cambiar después)', req: 1,
              ayuda: 'minúsculas, números y guión bajo — por ejemplo «notario_ayu_bali». Queda dentro de cada contrato y factura que se emitan con esta cuenta, así que no se renombra nunca.' },
            { k: 'label', label: 'Etiqueta (la que ve el agente en el desplegable)', req: 1 },
            { k: 'titular', label: 'Titular', req: 1, medio: 1 },
            { k: 'banco', label: 'Banco', medio: 1 },
            { k: 'cuenta', label: 'Número de cuenta', req: 1, medio: 1 },
            { k: 'codigo', label: 'Código Swift / Routing', medio: 1 },
            { k: 'direccion', label: 'Domicilio del banco' },
            { k: 'es_escrow', label: 'Es una cuenta ESCROW (depósito en garantía)', tipo: 'check' },
            { tipo: 'nota', label: 'Nace desactivada y sin ningún contrato asignado: no puede aparecer en el desplegable de un contrato antes de que alguien compruebe el número. Se activa y se reparte después, con el botón «Editar» de su fila en «Por cuenta».' }
          ], 'Crear cuenta', function (v) {
            var clave = v.clave.trim().toLowerCase();
            if (!/^[a-z0-9_]{3,}$/.test(clave)) {
              return { error: { message: 'La clave va en minúsculas, números y guión bajo, mínimo 3 caracteres. Sin espacios ni acentos.' } };
            }
            if (claves[clave]) return { error: { message: 'Ya existe una cuenta con la clave «' + clave + '».' } };
            /* `.select().single()` detrás del insert a propósito, igual que en
               /intranet/cuentas/: la policy de SELECT de cuentas_bancarias es
               para cualquier sesión, así que no hay riesgo de que esto
               confunda un insert bueno con uno rechazado por RLS. */
            return sb.from('cuentas_bancarias').insert({
              clave: clave, label: v.label.trim(),
              titular: v.titular.trim(), banco: v.banco.trim(), cuenta: v.cuenta.trim(),
              codigo: v.codigo.trim(), direccion: v.direccion.trim(), extra: '',
              es_escrow: !!v.es_escrow, activa: false, orden: siguienteOrden
            }).select('clave').single().then(function (rr) {
              if (rr && rr.error) return rr;
              recarga();
              return null;
            });
          }, { sinRecarga: true });
        });
      });
      // `hidden` de salida en el HTML: solo se destapa para super_admin — un
      // admin normal ni lo ve, aunque el click de todas formas lo rechazaría.
      if (btn && superAdmin) btn.hidden = false;
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

  /* LA VENTANA DE LA v4, Y YA NO HAY OTRA (14-sep-2026, encargo del owner).
     `maqueta.js` tenia la suya —misma ventana con fondo, cabecera, campos y pie,
     pero con radio 10 en vez de 14, botones rectos en vez de pastilla y sin saber
     ensenar un error— y ya habian empezado a separarse. Se queda esta, que es la
     que valida, sabe ensenar el fallo y tiene la variante lateral.

     Se EXPORTA en vez de mudarse a un fichero aparte: mudarla es operar 1.080
     lineas alrededor de los dieciseis formularios que el owner usa a diario, y el
     beneficio seria el mismo. Si algun dia la usa una tercera pieza, entonces si
     baja a `contracts/assets/` — que es donde deberia nacer lo que usan dos o mas.
     `window.lw*` y no un `const`: un `const` de nivel superior no queda en
     `window`, y esto tiene que alcanzarse desde OTRO fichero. */
  window.lwVentana = modal;
})();
