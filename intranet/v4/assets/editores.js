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
    var alCerrar = m._alCerrar; m._alCerrar = null;
    if (typeof alCerrar === 'function') setTimeout(alCerrar, 0);
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
    // `opts.alCerrar` (22-sep-2026): quien abre el editor en modo lectura tras
    // emitir quiere recargar el listado al cerrarlo, igual que hacía el visor.
    w._alCerrar = typeof opts.alCerrar === 'function' ? opts.alCerrar : null;
    var cajaForm = 'pointer-events:auto;position:fixed;top:0;right:0;height:100%;width:' + (opts.ancho || 'min(640px,96vw)') + ';' +
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
          }).join('') + '</div>' +
          /* Atajos OPT-IN por campo (21-sep-2026, LAW-71/paridad de Usuarios):
             solo se pintan si el campo trae `c.atajos` — no se enciende por
             defecto en los demas multicheck de la suite (Equipos, el propio
             «Herramientas» de este mismo formulario...) sin que lo pidan. Cada
             entrada es {texto, valor}: `valor` es el estado (true/false) al
             que deja TODAS las casillas del campo al pulsarlo. El TEXTO y si
             "vaciar" tiene sentido lo decide quien define el campo, no esta
             funcion generica — en Usuarios, `tipos_contrato` vacio significa
             TODOS, así que ahí un botón "Ninguno" mentiría y no se ofrece. */
          (Array.isArray(c.atajos) && c.atajos.length
            ? '<div style="display:flex;gap:8px;margin-top:8px">' + c.atajos.map(function (a) {
                return '<button type="button" data-atajo="1" style="padding:5px 12px;border-radius:8px;border:1px solid ' + CAJ.borde + ';background:' + CAJ.papel + ';color:' + CAJ.tinta + ';font-weight:600;font-size:12px;cursor:pointer">' + esc(a.texto) + '</button>';
              }).join('') + '</div>'
            : '');
      } else {
        d.innerHTML = inner + '<input data-k="' + esc(c.k) + '" type="' + (c.tipo || 'text') + '" value="' + esc(c.valor == null ? '' : c.valor) + '"' +
          (c.paso ? ' step="' + esc(c.paso) + '"' : '') + ' style="' + estilo + '">';
      }
      if (c.ayuda && c.tipo !== 'check') {
        d.innerHTML += '<small style="font-weight:400;font-size:12px;text-transform:none;letter-spacing:0;color:#8A8474">' + esc(c.ayuda) + '</small>';
      }
      cont.appendChild(d);
      // Los botones de atajo se cablean DESPUES de appendChild: la linea de
      // `c.ayuda` de arriba hace `d.innerHTML +=`, que reserializa y reparsea
      // TODO el subarbol — cualquier listener puesto antes se perderia.
      if (c.tipo === 'multicheck' && Array.isArray(c.atajos) && c.atajos.length) {
        var cajaMC = d.querySelector('[data-k="' + c.k + '"]');
        var botonesMC = d.querySelectorAll('[data-atajo]');
        botonesMC.forEach(function (btn, ai) {
          btn.addEventListener('click', function (ev) {
            ev.preventDefault();
            var on = !!c.atajos[ai].valor;
            if (cajaMC) cajaMC.querySelectorAll('input').forEach(function (i) { i.checked = on; });
          });
        });
      }
    });
    /* `visibleSi: { k, valores }` — un campo que solo tiene sentido con cierto
       valor de OTRO campo (22-sep-2026, owner: «'Importe fijo' que aparezca
       cuando seleccione la base correspondiente. Igual con 'Override
       individual'»). Se esconde la tarjeta entera y, al esconderse, se VACÍA:
       si no, un valor tecleado y luego ocultado viajaría igual en `vals` y la
       validación de `onGuardar` lo rechazaría sin que se viera el campo. */
    campos.forEach(function (c, i) {
      if (!c.visibleSi || !c.visibleSi.k) return;
      var propia = cont.children[i];
      var amo = cont.querySelector('[data-k="' + c.visibleSi.k + '"]');
      if (!propia || !amo) return;
      var valores = [].concat(c.visibleSi.valores || []);
      // la tarjeta lleva `display:grid` en línea, así que `hidden` no la esconde
      var displayPropio = propia.style.display;
      function aplica() {
        var v = amo.type === 'checkbox' ? amo.checked : amo.value;
        var ver = valores.indexOf(v) !== -1;
        propia.style.display = ver ? displayPropio : 'none';
        if (!ver) propia.querySelectorAll('[data-k]').forEach(function (el) {
          if (el.type === 'checkbox') el.checked = false; else if (el.tagName !== 'DIV') el.value = '';
        });
      }
      amo.addEventListener('change', aplica);
      aplica();
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
    var cajaPanel = 'position:fixed;top:0;right:0;height:100%;width:' + (o.ancho || 'min(60vw,96vw)') + ';' +
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
      // `disabled`/`title` (22-sep-2026, S10.3): el botón «Activar deck» nace
      // deshabilitado sin título guardado — mismo criterio que la clásica
      // (nunca activar un deck vacío), y `title` dice por qué sin un tooltip
      // aparte.
      if (a.disabled) { b.disabled = true; if (b.tagName === 'BUTTON') b.style.opacity = '.5'; }
      if (a.title) b.title = a.title;
      if (a.cerrar) b.addEventListener('click', cierraCajon);
      else if (typeof a.onClick === 'function') b.addEventListener('click', function (ev) { a.onClick(ev, w); });
      pie.appendChild(b);
    });
    // Un cajon sin acciones lleva al menos «Cerrar»: la X de arriba no basta
    // en movil, donde el pulgar vive abajo. `pieExtra` (HTML crudo, para el
    // shim de suiAbrirCajon/deck_fotos.js) ya trae el suyo — no se duplica.
    if (!o.pieExtra && !(o.acciones || []).some(function (a) { return a.cerrar; })) {
      var bc = document.createElement('button'); bc.type = 'button'; bc.textContent = 'Cerrar';
      bc.style.cssText = estiloBoton({}); bc.addEventListener('click', cierraCajon); pie.appendChild(bc);
    }
    /* `pieExtra` — puente para código que compone su PROPIO pie como HTML
       crudo en vez del array `acciones` (hoy solo deck_fotos.js, vía el shim
       suiAbrirCajon de más abajo: su pie trae un botón con
       id="df-cerrar" al que engancha `onclick = suiCerrarCajon` DESPUÉS de
       abrir, y necesita existir de verdad en el DOM). */
    if (o.pieExtra) pie.insertAdjacentHTML('beforeend', o.pieExtra);
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

  /* ═══ SHIM suiAbrirCajon/suiCerrarCajon PARA LA v4 (S10.2, 22-sep-2026) ═══
     `contracts/assets/deck_fotos.js` es una pieza COMPARTIDA de la suite
     (Regla 0 de contexto/suite_lawang.md — la usan /proyectos/ y /modelos/
     clásicos) que llama a `suiAbrirCajon`/`suiCerrarCajon` (contracts/assets/
     suite.js) como identificadores GLOBALES sueltos, sin `window.` delante.
     La v4 no carga suite.js (tiene su propio cajón, `cajon()` de arriba) ni
     `#suiVelo`/`#suiCajon` en el DOM — sin este puente, abrir "Fotos del
     deck" desde v4 lanzaría un ReferenceError en la primera línea de
     `deck_fotos.js`.

     La solución NO es traer suite.js + suite.css (harían falta también las
     variables de brand.css, que la v4 no define — su Tailwind vive en otro
     sistema de tokens) ni reescribir deck_fotos.js (es la pieza que la Regla
     0 prohíbe copiar/repetir). Es dar a esos dos nombres globales una
     implementación que abre el MISMO cajón de esta pantalla (`cajon()`),
     reusando su `pieExtra` para el HTML crudo que trae `deck_fotos.js` en
     `opts.pie` (con su propio botón `#df-cerrar`, al que engancha
     `onclick = suiCerrarCajon` justo después de llamar a `suiAbrirCajon`).
     El CSS de sus clases (`.sui-bloque`, `.sui-btn`, `.campo`…) vive en
     shell.css, traducido a la paleta CAJ — mismo patrón que ya usó S6 con
     las clases de dialogo.js. */
  window.suiAbrirCajon = function (opts) {
    opts = opts || {};
    return cajon({
      titulo: opts.titulo, sub: opts.sub, cuerpo: opts.cuerpo,
      pieExtra: opts.pie, alCerrar: opts.onCerrar
    });
  };
  window.suiCerrarCajon = function () { cierraCajon(); };

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

  /* Owner, 22-sep-2026: «me pide el email del closer pero eso está mal,
     debería salirme el listado de Usuarios dados de alta en la intranet. Al
     igual que el dar de alta el equipo: deben ser usuarios ya creados».
     El manager de un equipo, el closer de un miembro y el override de una
     condición se ELIGEN de `usuarios` (la lista la deja datos.js en
     `window.LW_V4.usuariosLista` al pintar la pantalla), nunca se teclean:
     el email es la clave con la que se atribuyen ventas y comisiones, y uno
     mal escrito no falla — deja las comisiones huérfanas en silencio.
     `actual` (el valor ya guardado al editar) se conserva aunque no esté en
     la lista —usuario dado de baja o un email tecleado antes de este cambio—
     para que abrir el cajón no lo pierda; se marca para que se vea. */
  function opsUsuarios(actual, textoVacio) {
    var lista = ((window.LW_V4 && window.LW_V4.usuariosLista) || []).slice();
    var a = (actual || '').trim().toLowerCase();
    if (a && !lista.some(function (o) { return o[0] === a; })) lista.push([a, a + ' (no está en Usuarios)']);
    return [['', textoVacio || '— elige un usuario —']].concat(lista);
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
  /* `iniciales` (22-sep-2026): tramos ya guardados, para EDITAR una condición.
     Sin ellos arranca con dos filas vacías, como siempre. */
  function montaTramos(host, iniciales) {
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

    function nuevaFila(valores) {
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
      // el botón «+ Añadir tramo» llama a nuevaFila con el evento: no es un tramo
      if (valores && typeof valores === 'object' && !(valores instanceof Event)) {
        if (valores.disparador_tipo) selDisp.value = valores.disparador_tipo;
        if (valores.umbral != null) inpUmbral.value = valores.umbral;
        if (valores.pct_tramo != null) inpPct.value = valores.pct_tramo;
      }

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
    if (Array.isArray(iniciales) && iniciales.length) iniciales.forEach(nuevaFila);
    else { nuevaFila(); nuevaFila(); }   // arranca con dos: lo habitual es 2+ tramos

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

  /* ═══════════════════════════════════════════════════════════════════════
     EMISIÓN DE FACTURAS · PROFORMAS · RECIBÍS DENTRO DE v4 (21-sep-2026)
     ═══════════════════════════════════════════════════════════════════════
     Encargo del owner: "crear una factura o un recibí en la v4 apunta a la
     version antigua". Hasta hoy "Nuevo documento" (/v4/facturas/) y
     "+ Emitir recibi de cobro" (/v4/recibos/) no tenian handler propio: caian
     en maqueta.js (FORM_REAL), que los mandaba a /intranet/facturas/. Este
     bloque los cablea DE VERDAD, dentro de v4, con el mismo patron de cajon
     lateral que Usuarios/Compradores (18-sep) — nunca un componente nuevo.

     DOS CAMINOS DE GUARDADO REALES (revision previa 21-sep, Datos+Seguridad+
     Legal, verificados contra la base VIVA con execute_sql, no contra un .sql
     que puede estar desfasado):
       · Factura/proforma -> INSERT/UPDATE directo sobre `facturas`, protegido
         por RLS + `trg_set_factura_numero` (numeracion atomica, SECURITY
         DEFINER) + `trg_congela_emisor` (congela sociedad/razon/NPWP en
         `datos.emisor` al crear). Nunca se manda `numero` ni
         `justificante_path`: el GRANT de columnas no los concede a
         `authenticated` (migracion 20260917161500_facturas_emisor_congelado_y_permisos.sql).
       · Recibi -> RPC `guardar_recibi(p_id, p_factura, p_aplicaciones)`. Exige
         `es_agente() and puede('facturas')`, un contrato, un justificante YA
         subido a storage `justificantes` (se valida contra `storage.objects`)
         y al menos una aplicacion a una factura del MISMO comprador
         (`contratos_mismo_comprador`, LAW-41(2), REC00019 aplicado a otro
         cliente) — la base es el tirante, este formulario es el cinturon.
         Reeditar un recibi ya guardado pasa por el MISMO rpc con `p_id`, y la
         base lo rechaza si no es tuyo o esta anulado (`es_suyo`) — 42501.

     El `datos.fields`/`datos.lineas`/`datos.totales` que se guarda tiene que
     tener EXACTAMENTE la forma que lee `/intranet/facturas/documento.js`
     (mismo `payload()` de esa pantalla, leido linea a linea): es el fichero
     que pinta el documento y lo reutiliza tambien la Edge de firma. Un campo
     de menos aqui no rompe el guardado, rompe el PAPEL — por eso este bloque
     no reescribe el render: ver un documento ya emitido abre un cajon con un
     <iframe> a `/intranet/facturas/?id=<id>&vista=1` (mismo origen, misma
     sesion, sin exigir el permiso de emitir — lineas 996-1016 de esa
     pantalla). Es la unica forma de no duplicar documento.css/documento.js.

     `entidades_pago.js` NO se carga aqui (corregido contra el repo, 21-sep):
     `cargarCuentasBancarias` vive en `entities.js`, y la herramienta clasica
     de facturas tampoco carga `entidades_pago.js` — ofrece TODAS las cuentas
     activas a proposito (su comentario ~1163: "si el contrato pacto cobrar en
     una cuenta concreta, la factura tiene que decir esa misma"). La cascada
     plantilla_cuentas/proyecto_cuentas de `entidades_pago.js` es del
     GENERADOR DE CONTRATOS, no de facturas.

     MODULOS COMPARTIDOS QUE ESTA PANTALLA TAL VEZ NO TRAE. "Emitir recibi"
     tambien se abre desde la ficha de Contratos/Operaciones/Home (18-sep), y
     esas paginas hoy NO cargan entities.js/compradores.js/dialogo.js/
     totales.js — nunca lo necesitaron antes de este build. Tocar esas cinco
     HTML para un handler que solo dispara si alguien pulsa "Emitir recibi"
     seria la Regla 0 al reves: se piden solo cuando hacen falta (ver
     aseguraModulosDoc), nunca se copia su contenido. dinero.js YA esta en las
     16 pantallas (comprobado), asi que no entra en la lista. */
  var MODULOS_DOC = {
    entities: { src: '/contracts/assets/entities.js?v=e015c66a', listo: function () { return typeof SOCIEDADES !== 'undefined'; } },
    compradores: { src: '/contracts/assets/compradores.js?v=7eb94ab0', listo: function () { return typeof compradoresDeContrato === 'function'; } },
    dialogo: { src: '/contracts/assets/dialogo.js?v=cefc9e4e', listo: function () { return typeof window.lwElegir === 'function'; } },
    totales: { src: '/intranet/facturas/totales.js', listo: function () { return typeof calcTotales === 'function'; } },
    // El MISMO motor que pinta la vista previa y la impresión del clásico y
    // que arma el PDF que se manda solo al firmar (22-sep-2026, split en
    // vivo pedido por el owner) — nunca una segunda plantilla del documento.
    documento: { src: '/intranet/facturas/documento.js', listo: function () { return typeof documentoHTML === 'function'; } },
    // Reglas de dinero por contrato (facturado/cobrado/%), las mismas del
    // listado y del clásico — para «cuánto lleva cobrado» del recibí.
    facturasContratos: { src: '/contracts/assets/facturas_contratos.js', listo: function () { return typeof lwAgrupaPorContrato === 'function'; } },
    // Fotos del Investor Deck (S10.2, 22-sep-2026) — pieza compartida de la
    // suite (Regla 0), usada hoy por Proyectos aquí y previsiblemente por
    // Modelos v4 más adelante; se carga bajo demanda igual que el resto.
    deckFotos: { src: '/contracts/assets/deck_fotos.js?v=442fb967', listo: function () { return !!window.lwDeckFotos; } }
  };
  var modPromesasDoc = {};
  function cargaModuloDoc(nombre) {
    var m = MODULOS_DOC[nombre];
    if (!m || m.listo()) return Promise.resolve();
    if (modPromesasDoc[nombre]) return modPromesasDoc[nombre];
    modPromesasDoc[nombre] = new Promise(function (res, rej) {
      var s = document.createElement('script');
      s.src = m.src;
      s.onload = function () { res(); };
      s.onerror = function () { delete modPromesasDoc[nombre]; rej(new Error('no se pudo cargar ' + nombre)); };
      document.head.appendChild(s);
    });
    return modPromesasDoc[nombre];
  }
  function aseguraModulosDoc(nombres) {
    return nombres.reduce(function (p, n) { return p.then(function () { return cargaModuloDoc(n); }); }, Promise.resolve());
  }

  function opcionesContratoPickerDoc(cs) {
    return (cs || []).map(function (c) {
      return { valor: c.id, texto: (c.numero || '—') + ' · ' + (c.comprador_nombre || '—'), nota: c.proyecto_nombre || '' };
    });
  }
  /* `created_at` VA EN EL SELECT aunque no se pinte (22-sep-2026, owner: «el
     buscar por contrato no funciona»): sobre un recurso de FUNCIÓN PostgREST
     exige que la columna del order() esté proyectada — sin ella responde
     42703 «column contratos.created_at does not exist» (verificado contra el
     REST vivo). El clásico lo tenía documentado en cargarContratos() y
     operaciones/ ya lo había pagado antes: esta era la segunda vez. Y el
     error ya no se traga: `r.data || []` dejaba el picker en «Nada coincide»
     sin decir por qué. Sin `numero` no se ofrece, igual que el clásico. */
  function listaContratosLigeraDoc(sb) {
    return sb.rpc('contratos_equipo').select('id,numero,comprador_nombre,proyecto_nombre,created_at')
      .order('created_at', { ascending: false }).limit(500)
      .then(function (r) {
        if (r.error) {
          toastMal(lwErrorHumano(r.error, 'No se pudo cargar la lista de contratos'));
          return { data: [] };
        }
        return { data: (r.data || []).filter(function (c) { return c.numero; }) };
      });
  }
  /* Facturas pendientes de TODO el equipo, sin filtrar por comprador — el
     estado de arranque de «Factura que se cobra» cuando el recibí aún no
     sabe de quién es (mismo camino que `cargarFacturasAbiertas()` del
     clásico cuando `CONTRATO_ID` es null: 27-ago-2026, «sin contrato
     elegido, todas»). En cuanto se elige una factura, el contrato — y por
     tanto el comprador — ya se sabe, y las siguientes cargas usan
     `contratos_del_mismo_comprador` para acotar, igual que siempre. */
  function cargaTodasAbiertasRecibiDoc(sb, moneda) {
    return Promise.all([
      sb.rpc('facturas_equipo').select('id,numero,contrato_id,contrato_numero,cliente_nombre,total,tipo,anulada,moneda'),
      sb.rpc('facturas_pendiente_equipo')
    ]).then(function (rs) {
      if (rs[0].error || rs[1].error) return [];
      var pend = {}; (rs[1].data || []).forEach(function (x) { pend[x.factura_id] = Number(x.pendiente) || 0; });
      return (rs[0].data || [])
        .filter(function (x) { return x.tipo === 'factura' && !x.anulada && (pend[x.id] || 0) > 0.005 && x.contrato_id; })
        .filter(function (x) { return (x.moneda || 'EUR') === moneda; })
        .map(function (x) { return { id: x.id, numero: x.numero, contrato_id: x.contrato_id, contrato_numero: x.contrato_numero, cliente_nombre: x.cliente_nombre, pendiente: pend[x.id], moneda: x.moneda }; });
    });
  }
  function opcionesSociedadDoc() {
    return Object.keys(SOCIEDADES).map(function (k) { return [k, SOCIEDADES[k].label]; });
  }
  function opcionesCuentaDoc(sinOtros) {
    var out = [['', '— sin datos bancarios —']];
    Object.keys(CUENTAS_BANCARIAS).map(function (k) { return [k, CUENTAS_BANCARIAS[k].label]; })
      .sort(function (a, b) { return a[1].localeCompare(b[1], 'es'); })
      .forEach(function (o) { out.push(o); });
    if (!sinOtros) out.push(['otros', 'Otros — escribir la cuenta a mano']);
    return out;
  }
  function campoDeDoc(k) { return document.querySelector('#lw-editor [data-k="' + k + '"]'); }
  function ponCampoDoc(k, valor) { var el = campoDeDoc(k); if (el) el.value = valor || ''; }
  /* Calco de bloquear()/soltarCampos() del clásico (22-sep-2026, owner:
     «había campos que bloqueábamos al cargarlos desde el contrato»). Se
     bloquea SOLO lo que el contrato ha rellenado de verdad — un hueco
     bloqueado no protege nada y deja una factura que no se puede completar.
     `readonly` y no `disabled`: disabled no entra en el `vals` del modal. Un
     <select> no tiene readonly: se le quita el puntero y el tab. Y se pinta
     distinto (crema, tinta apagada) con su porqué en el title: un campo gris
     sin explicación se lee como una pantalla rota. */
  function bloqueaCampoDoc(k, si) {
    var el = campoDeDoc(k); if (!el) return;
    if (el.tagName === 'SELECT') { el.style.pointerEvents = si ? 'none' : ''; el.tabIndex = si ? -1 : 0; }
    else el.readOnly = !!si;
    el.style.backgroundColor = si ? '#F1EBDD' : CAJ.papel;
    el.style.color = si ? '#4A5052' : CAJ.tinta;
    el.title = si ? 'Traído del contrato: se cambia en el contrato, no aquí' : '';
    if (si) el.setAttribute('data-del-contrato', '1'); else el.removeAttribute('data-del-contrato');
  }
  function sueltaCamposDoc() {
    Array.prototype.forEach.call(document.querySelectorAll('#lw-editor [data-del-contrato="1"]'), function (el) { bloqueaCampoDoc(el.getAttribute('data-k'), false); });
  }

  /* Trae el contrato COMPLETO y rellena identidad/proyecto/moneda/sociedad/
     cuenta por el MISMO camino protegido que usa la ficha del contrato
     (RPC `contratos_equipo`, nunca un segundo fetch a `clients`) — mismo
     patron que `traerContrato()` de /intranet/facturas/, linea a linea:
     los campos de IDENTIDAD se VACIAN cuando el contrato nuevo no los trae
     (auditoria 21-ago: dejar el dato del contrato ANTERIOR es peor que un
     hueco), y moneda/sociedad/cuenta NUNCA se vacian, solo se rellenan si
     el contrato trae algo que exista en el catalogo cargado. */
  function aplicaContratoDoc(sb, id) {
    return sb.rpc('contratos_equipo')
      .select('numero,tipo,moneda,precio_total,proyecto_id,contrato_padre_id,campos:datos->fields,hitos:datos->hitos,extras:datos->compradores,ficha:datos->>adq1_client_id')
      .eq('id', id).maybeSingle()
      .then(function (r) {
        if (r.error || !r.data) return { error: r.error || { message: 'contrato no encontrado' } };
        var data = r.data, f = data.campos || {};
        var compradores = compradoresDeContrato(f, data.extras);
        var nombres = nombresFactura(compradores);
        var docs = documentosFactura(compradores);
        var email = primerDato(compradores, 'email');
        var unidad = [f.proyecto_nombre, f.parcela_codigo || f.villa_nombre || f.tipologia_villa].filter(Boolean).join(' — ');
        var puesto = [];
        // Se sueltan TODOS antes de poner: si no, al cambiar de contrato un
        // campo que el nuevo no trae se quedaría gris y sin poder escribir.
        sueltaCamposDoc();
        function poner(k, v, etq) { if (v) { ponCampoDoc(k, v); puesto.push(etq); bloqueaCampoDoc(k, true); } else { ponCampoDoc(k, ''); bloqueaCampoDoc(k, false); } }
        poner('contrato_numero', data.numero, 'nº de contrato');
        poner('cliente_nombre', nombres, 'nombre');
        poner('cliente_documento', docs, 'documento');
        poner('cliente_email', email, 'email');
        poner('proyecto_nombre', unidad, 'proyecto');
        if (data.moneda || f.moneda) { ponCampoDoc('moneda', data.moneda || f.moneda); if (campoDeDoc('moneda')) { puesto.push('moneda'); bloqueaCampoDoc('moneda', true); } }
        if (f.sociedad_firmante && SOCIEDADES[f.sociedad_firmante]) { ponCampoDoc('sociedad', f.sociedad_firmante); if (campoDeDoc('sociedad')) { puesto.push('sociedad'); bloqueaCampoDoc('sociedad', true); } }
        if (f.cuenta_bancaria && CUENTAS_BANCARIAS[f.cuenta_bancaria]) { ponCampoDoc('cuenta', f.cuenta_bancaria); if (campoDeDoc('cuenta')) { puesto.push('cuenta de cobro'); bloqueaCampoDoc('cuenta', true); } }
        return {
          id: id, numero: data.numero, comprador: nombres, clienteId: data.ficha || null,
          proyectoId: data.proyecto_id || null, moneda: data.moneda || f.moneda, puesto: puesto,
          clienteNombre: nombres, clienteDocumento: docs, clienteEmail: email, proyectoNombre: unidad,
          // para el bloque «Del contrato» (hitos, total, encadenados)
          precio: data.precio_total || f.precio_total, hitos: data.hitos || [], tipoContrato: data.tipo || '',
          padreId: data.contrato_padre_id || null, nCompradores: compradores.length
        };
      }, function (e) { return { error: e }; });
  }

  /* Conceptos (líneas) de factura/proforma — {descripcion,importe}, misma
     forma que `LINEAS` de /intranet/facturas/. */
  /* ═══ «DEL CONTRATO»: hitos, total del proyecto, encadenados (22-sep-2026)
     Owner: «falta toda la parte de saber qué hitos están en el contrato…
     trae absolutamente todo lo que tiene la versión estándar». Calco, función
     a función, de pintarOpcionesContrato / marcarHitosUsados /
     cargarHitosOtraFactura / precargarConceptos / soltarPrecargaAlCambiarTipo
     / pintarVinculados / traerVinculado de /intranet/facturas/. Las
     DESCRIPCIONES de línea son las mismas cadenas que allí (descHito,
     «Precio total del contrato N», «[Tipo] hito», «Tipo — precio total del
     contrato N»): es por ellas por lo que un hito facturado en el clásico se
     ve tachado aquí y al revés. Los porqués de cada regla están en el
     clásico y no se repiten: aquí solo lo que cambia de sitio. */
  var estiloDelContratoPuesto = false;
  function aseguraEstiloDelContrato() {
    if (estiloDelContratoPuesto) return; estiloDelContratoPuesto = true;
    var s = document.createElement('style'); s.id = 'lw-doc-contrato-css';
    s.textContent = '.lw-dc{margin-top:4px;padding:11px 12px;border:1px solid ' + CAJ.borde + ';border-radius:11px;background:#f7f4ea}' +
      '.lw-dc:empty{display:none}.lw-dc.lw-dc-vinc{padding:0;border:0;background:none;margin-top:0}' +
      '.lw-dc .t{font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:' + CAJ.apagado + '}' +
      '.lw-dc .arrastrado{font-size:12px;color:' + CAJ.apagado + ';margin:5px 0 0;line-height:1.5}' +
      '.lw-dc .pregunta{margin:11px 0 7px;font-size:13px;font-weight:600;color:' + CAJ.tinta + '}' +
      '.lw-dc .hitos{display:flex;flex-wrap:wrap;gap:6px;margin-top:9px}' +
      '.lw-dc .hito{font:inherit;font-size:12px;text-align:left;background:' + CAJ.papel + ';border:1px solid ' + CAJ.borde + ';border-radius:9px;padding:6px 10px;cursor:pointer;color:' + CAJ.tinta + '}' +
      '.lw-dc .hito:hover{border-color:' + CAJ.lago + ';color:' + CAJ.lago + '}.lw-dc .hito b{color:' + CAJ.lago + '}' +
      '.lw-dc .hito.usado,.lw-dc .hito:disabled{opacity:.45;text-decoration:line-through;cursor:not-allowed}' +
      '.lw-dc .hito-todo{display:block;width:100%;text-align:left;cursor:pointer;padding:11px 13px;border:1px solid ' + CAJ.hoja + ';border-radius:11px;background:' + CAJ.papel + ';font:inherit;color:' + CAJ.tinta + '}' +
      '.lw-dc .hito-todo .q{display:block;font-size:12.5px;font-weight:600;letter-spacing:-.01em}' +
      '.lw-dc .hito-todo .n{display:block;margin-top:1px;font-size:19px;font-weight:700;letter-spacing:-.02em;font-variant-numeric:tabular-nums}' +
      '.lw-dc .hito-todo .p{display:block;margin-top:2px;font-size:11.5px;color:' + CAJ.apagado + '}' +
      '.lw-dc .hito-todo:hover{background:' + CAJ.banda + '}' +
      '.lw-dc .hito-todo.usado,.lw-dc .hito-todo:disabled{opacity:.5;cursor:not-allowed;border-style:dashed}' +
      '.lw-dc .hito-todo.doble{background:rgba(255,255,255,.55);margin:8px 0 9px}' +
      '.lw-dc .excepcion{margin-top:12px}.lw-dc .excepcion>summary{cursor:pointer;font-size:11.5px;color:' + CAJ.apagado + ';list-style:none}' +
      '.lw-dc .excepcion>summary::-webkit-details-marker{display:none}.lw-dc .excepcion>summary::before{content:"＋ ";font-size:10px}.lw-dc .excepcion[open]>summary::before{content:"− "}' +
      '.lw-dc .vinc{margin-top:8px;padding:10px 12px;border:1px solid ' + CAJ.lago + ';border-left-width:3px;border-radius:10px;background:#EEF3EA}' +
      '.lw-dc .vinc.malo{border-color:#9E2F26;background:#FBF3F1}' +
      '.lw-dc .vinc-t{font-size:12.5px;font-weight:600;color:' + CAJ.lago + ';margin-bottom:3px}.lw-dc .vinc.malo .vinc-t{color:#9E2F26}' +
      '.lw-dc .vinc p{margin:0;font-size:12px;color:#4A5052;line-height:1.45}' +
      '.lw-dc .vinc-btn{margin-top:9px;font:inherit;font-size:12.5px;font-weight:500;padding:6px 11px;border-radius:999px;border:1px solid ' + CAJ.lago + ';background:' + CAJ.papel + ';color:' + CAJ.lago + ';cursor:pointer}' +
      '.lw-dc .vinc-btn.usado,.lw-dc .vinc-btn:disabled{opacity:.5;cursor:not-allowed}' +
      '.lw-dc .hito,.lw-dc .hito-todo{transition:transform .1s ease-out,background-color .12s ease-out,border-color .12s ease-out}' +
      '.lw-dc .hito:active:not(:disabled),.lw-dc .hito-todo:active:not(:disabled){transform:scale(.98)}';
    document.head.appendChild(s);
  }
  function descHitoDoc(h) {
    return [h.texto, h.pct ? '(' + h.pct + '% del precio acordado)' : ''].filter(Boolean).join(' ') + (h.timing ? ' — ' + h.timing : '');
  }
  function hitosDeDoc(crudos, precio, moneda) {
    return (crudos || []).map(function (h, idx) {
      var pct = parseImporte(h.pct);
      var monto = parseImporte(h.monto) || (pct && precio ? redondear(precio * pct / 100, moneda) : 0);
      // `orden` = ordinalidad en datos.hitos, ANTES del filtro: es la clave
      // con la que contrato_vencimientos guarda la fecha de ese hito.
      return { texto: h.es || h.en || '', pct: pct, monto: monto, timing: h.timing || '', orden: idx + 1 };
    }).filter(function (h) { return h.texto || h.monto; });
  }
  function importeTxtDoc(n) { return String(n).replace('.', ','); }
  // Fecha LOCAL, no UTC (hoyLocalISO del clásico): de noche en Bali
  // toISOString() ya es mañana o todavía ayer, según el lado.
  function hoyLocalDoc() { var d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }
  /* ctx: { sb, lineas (api de montaLineasDoc), repinta, tipoActual(),
     monedaActual(), sociedadActual(), esNuevo, propioId }. Devuelve
     { pon(res), repinta(), marca(), alCambiarTipo(), limpia() }. */
  function montaDelContratoDoc(host, ctx) {
    aseguraEstiloDelContrato();
    var caja = document.createElement('div'); caja.className = 'lw-dc';
    var cajaV = document.createElement('div'); cajaV.className = 'lw-dc lw-dc-vinc';
    host.appendChild(caja); host.appendChild(cajaV);
    var C = null, DESC_TOTAL = '', DESC_UNIDAD = '', otraFactura = {}, huella = null, numPorId = {}, venc = {};
    /* Calendario de pagos del contrato (contrato_vencimientos, una fila por
       hito con su fecha y, si ya se facturó, su factura_id). Dos usos
       (22-sep-2026, owner): al pulsar un hito se rellena el vencimiento de
       la factura con la fecha del calendario — SOLO en parcela: «para
       construcción no, los vencimientos de la casa se dispararán cuando se
       dé inicio la obra»; y un hito que el calendario ya enlaza a una
       factura sale tachado por ese enlace real, no solo por comparar textos. */
    function cargaVencimientos() {
      venc = {};
      if (!C || ctx.esRecibi) return Promise.resolve();
      return ctx.sb.from('contrato_vencimientos').select('orden,fecha,factura_id').eq('contrato_id', C.id).then(function (r) {
        if (r.error) { console.error('calendario de pagos:', r.error.message); return; }
        (r.data || []).forEach(function (v) { venc[v.orden] = v; });
        C.hitos.forEach(function (h) {
          var v = venc[h.orden];
          if (v && v.factura_id && v.factura_id !== ctx.propioId) {
            var d = descHitoDoc(h); if (!otraFactura[d]) otraFactura[d] = numPorId[v.factura_id] || 'otra factura';
          }
        });
      });
    }
    var TE = function () { return (typeof TIPO_ES !== 'undefined') ? TIPO_ES : {}; };
    var prelim = function (t) { return typeof lwEsPreliminar === 'function' && lwEsPreliminar(t); };
    function filas() { return ctx.lineas ? ctx.lineas.todas() : []; }
    function txt(l) { return (l.descripcion || '').trim(); }
    function enBlanco() { return !filas().some(function (l) { return txt(l) || (l.importe || '').trim(); }); }
    function anade(l) { ctx.lineas.anade(l); ctx.repinta(); }
    function pon(ls) { ctx.lineas.pon(ls); ctx.repinta(); }
    function cargaOtraFactura(contratoId) {
      otraFactura = {}; numPorId = {};
      if (!contratoId) return Promise.resolve();
      return ctx.sb.from('facturas').select('id,numero,tipo,anulada,datos')
        .eq('contrato_id', contratoId).eq('tipo', 'factura').eq('anulada', false).then(function (r) {
          if (r.error) { console.error('hitos ya facturados:', r.error.message); return; }
          (r.data || []).forEach(function (f) {
            numPorId[f.id] = f.numero;
            if (f.id === ctx.propioId) return;
            (((f.datos || {}).lineas) || []).forEach(function (l) {
              var d = (l.descripcion || '').trim(); if (d && !otraFactura[d]) otraFactura[d] = f.numero || 'otra factura';
            });
          });
        });
    }
    function marca() {
      var L = filas();
      var hayTotal = !!DESC_TOTAL && L.some(function (l) { return txt(l) === DESC_TOTAL; });
      var hayHito = L.some(function (l) { var d = txt(l); return d && d !== DESC_TOTAL; });
      var botones = Array.prototype.slice.call(caja.querySelectorAll('[data-h]')).concat(Array.prototype.slice.call(cajaV.querySelectorAll('[data-vh]')));
      botones.forEach(function (b) {
        var desc = b.getAttribute('data-desc');
        var usado = L.some(function (l) { return txt(l) === desc; });
        var otra = !usado && otraFactura[desc];
        b.disabled = usado || !!otra || hayTotal;
        b.classList.toggle('usado', usado || !!otra);
        b.title = usado ? 'Ya está en este documento'
          : otra ? 'Ya facturado en ' + otra + ' — facturarlo otra vez lo cobraría dos veces'
          : hayTotal ? 'Este documento factura el contrato entero: un hito encima cobraría de más' : '';
      });
      var bt = caja.querySelector('[data-todo]');
      if (bt) { bt.disabled = hayTotal; bt.classList.toggle('usado', hayTotal); bt.title = hayTotal ? 'Ya está en este documento' : hayHito ? 'Sustituirá los conceptos que ya hay' : ''; }
      Array.prototype.forEach.call(cajaV.querySelectorAll('[data-unidad],[data-vinc]'), function (b) {
        var otra = b.getAttribute('data-otra');
        var otraPuesta = !!otra && L.some(function (l) { return txt(l) === otra; });
        if (b.hasAttribute('data-unidad')) {
          var completa = otraPuesta && hayTotal;
          b.disabled = completa; b.classList.toggle('usado', completa);
          b.title = completa ? 'Ya está en este documento' : (hayHito || hayTotal ? 'Sustituirá los conceptos que ya hay' : '');
        } else {
          b.disabled = otraPuesta; b.classList.toggle('usado', otraPuesta);
          b.title = otraPuesta ? 'Su precio total ya está en este documento: sus hitos encima lo cobrarían dos veces' : '';
        }
      });
    }
    function pinta() {
      if (!C) { caja.innerHTML = ''; return; }
      var esProforma = ctx.tipoActual() === 'proforma';
      var precio = C.precio, moneda = C.moneda, hitos = C.hitos;
      caja.innerHTML = '<div class="t">Del contrato ' + esc(C.numero || '') + '</div>' +
        '<p class="arrastrado">' + (C.puesto.length ? 'Traído del contrato y <b>bloqueado</b>: ' + esc(C.puesto.join(', ')) + '.' : 'El contrato no tenía datos de cliente que traer.') +
          (C.nCompradores > 1 ? ' Contrato a <b>' + C.nCompradores + ' nombres</b>.' : '') +
          (precio ? ' Precio del contrato: <b>' + esc(fmtMoneda(precio, moneda)) + '</b>.' : '') + '</p>' +
        ((precio || hitos.length) ? '<p class="pregunta">' + (esProforma ? 'Esta proforma declara el total del proyecto' : '¿Qué cobras en este documento?') + '</p>' : '') +
        ((precio && esProforma) ? '<button type="button" class="hito-todo" data-todo="1"><span class="q">Total del proyecto</span>' +
          '<span class="n">' + esc(fmtMoneda(precio, moneda)) + '</span><span class="p">Lo que se le comunica al cliente. Informativo: no factura ni vence</span></button>' : '') +
        ((hitos.length && !esProforma) ? '<div class="hitos">' + hitos.map(function (h, i) {
            return '<button type="button" class="hito" data-h="' + i + '">' + (h.pct ? '<b>' + esc(String(h.pct)) + '%</b> · ' : '') +
              esc(h.texto || 'Hito ' + (i + 1)) + (h.monto ? ' · ' + esc(fmtMoneda(h.monto, moneda)) : '') + '</button>';
          }).join('') + '</div><p class="arrastrado">Se factura el hito que se haya alcanzado.</p>' : '') +
        ((precio && !esProforma) ? '<details class="excepcion"><summary>El proyecto se factura de una vez</summary>' +
          '<button type="button" class="hito-todo" data-todo="1"><span class="q">Todo el contrato</span><span class="n">' + esc(fmtMoneda(precio, moneda)) + '</span>' +
          '<span class="p">Una sola factura por el importe completo, sin hitos</span></button></details>' : '');
      DESC_TOTAL = 'Precio total del contrato ' + (C.numero || '');
      var bt = caja.querySelector('[data-todo]');
      if (bt) {
        bt.setAttribute('data-desc', DESC_TOTAL);
        bt.addEventListener('click', function () {
          if (bt.disabled) return;
          var sigue = enBlanco() ? Promise.resolve(true) : lwConfirmar({
            titulo: 'Sustituir los conceptos',
            cuerpo: '<p>El documento ya tiene conceptos. Poner <b>todo el contrato</b> los reemplaza por una sola línea con el importe completo.</p>' +
              '<p>Se hace así a propósito: dejar los dos cobraría el total <b>y</b> el hito, y el documento saldría creíble.</p>',
            confirmar: 'Sustituir por el total', cancelar: 'Dejarlo como está' });
          sigue.then(function (ok) {
            if (!ok) return;
            pon([{ descripcion: DESC_TOTAL, importe: importeTxtDoc(precio) }]);
            toast((ctx.tipoActual() === 'proforma' ? 'Proforma' : 'Factura') + ' por el total del contrato: ' + fmtMoneda(precio, moneda));
          });
        });
      }
      Array.prototype.forEach.call(caja.querySelectorAll('[data-h]'), function (b) {
        var h = hitos[+b.getAttribute('data-h')];
        b.setAttribute('data-desc', descHitoDoc(h));
        b.addEventListener('click', function () {
          if (b.disabled) return;
          anade({ descripcion: b.getAttribute('data-desc'), importe: h.monto ? importeTxtDoc(h.monto) : '' });
          var v = venc[h.orden], fv = campoDeDoc('fecha_vencimiento');
          var conFecha = !!(v && v.fecha && fv && C.tipoContrato !== 'construccion');
          if (conFecha) { fv.value = v.fecha; ctx.repinta(); }
          toast((h.monto ? 'Concepto añadido' : 'Concepto añadido — el contrato no fijaba importe, ponlo a mano') +
            (conFecha ? ' · vence el ' + v.fecha.split('-').reverse().join('/') + ' según el calendario del contrato' : ''));
        });
      });
      marca();
    }
    function traeVinculado(c) {
      var etiqueta = TE()[c.tipo] || c.tipo || 'Vinculado', moneda = C.moneda;
      var precio = parseImporte(c.precio_total || (c.campos || {}).precio_total);
      var hitos = hitosDeDoc(c.hitos, precio, moneda);
      if (!hitos.length) { toastMal('Ese contrato no tiene hitos de pago que traer'); return; }
      var box = document.createElement('div'); box.className = 'hitos';
      box.innerHTML = hitos.map(function (h, i) {
        return '<button type="button" class="hito" data-vh="' + i + '">[' + esc(etiqueta) + '] ' + (h.pct ? '<b>' + esc(String(h.pct)) + '%</b> · ' : '') +
          esc(h.texto || 'Hito ' + (i + 1)) + (h.monto ? ' · ' + esc(fmtMoneda(h.monto, moneda)) : '') + '</button>';
      }).join('');
      cajaV.appendChild(box);
      Array.prototype.forEach.call(box.querySelectorAll('[data-vh]'), function (b) {
        var h = hitos[+b.getAttribute('data-vh')], desc = '[' + etiqueta + '] ' + descHitoDoc(h);
        b.setAttribute('data-desc', desc);
        b.addEventListener('click', function () {
          if (b.disabled) return;
          anade({ descripcion: desc, importe: h.monto ? importeTxtDoc(h.monto) : '', origen_contrato_id: c.id });
          toast(h.monto ? 'Concepto añadido' : 'Concepto añadido — el contrato no fijaba importe, ponlo a mano');
        });
      });
      marca();
      var btn = cajaV.querySelector('[data-vinc="' + c.id + '"]'); if (btn) btn.remove();
    }
    function pintaVinculados() {
      cajaV.innerHTML = '';
      if (!C) return Promise.resolve();
      var ors = ['contrato_padre_id.eq.' + C.id]; if (C.padreId) ors.push('id.eq.' + C.padreId);
      return ctx.sb.rpc('contratos_equipo').select('id,numero,tipo,precio_total,campos:datos->fields,hitos:datos->hitos').or(ors.join(',')).then(function (r) {
        if (r.error || !r.data || !r.data.length) return;
        var data = r.data, sociedadP = ctx.sociedadActual(), monedaP = C.moneda;
        cajaV.innerHTML = data.map(function (c) {
          var socC = (c.campos || {}).sociedad_firmante || '';
          var compatible = !socC || !sociedadP || socC === sociedadP;
          var etiqueta = TE()[c.tipo] || c.tipo || 'Vinculado';
          var precioC = parseImporte(c.precio_total || (c.campos || {}).precio_total);
          var monedaC = (c.campos || {}).moneda || monedaP;
          var sumable = compatible && precioC && C.precio && !prelim(c.tipo) && !prelim(C.tipoContrato) && monedaC === monedaP;
          var totalUnidad = sumable ? C.precio + precioC : 0;
          return compatible
            ? '<div class="vinc" role="status"><div class="vinc-t">Este contrato va encadenado con ' + esc(c.numero) + '</div>' +
              '<p>La venta está en dos contratos: <b>' + esc(etiqueta) + '</b> es el otro. Puedes cobrar los dos en este mismo documento.</p>' +
              (sumable ? '<button type="button" class="hito-todo doble" data-unidad="' + esc(c.id) + '"><span class="q">Toda la unidad · los dos contratos</span>' +
                '<span class="n">' + esc(fmtMoneda(totalUnidad, monedaP)) + '</span><span class="p">' + esc(fmtMoneda(C.precio, monedaP)) + ' de este + ' +
                esc(fmtMoneda(precioC, monedaP)) + ' de ' + esc(c.numero) + '</span></button>' : '') +
              '<button type="button" class="vinc-btn" data-vinc="' + esc(c.id) + '">Traer los conceptos de ' + esc(c.numero) + '</button></div>'
            : '<div class="vinc malo" role="status"><div class="vinc-t">' + esc(c.numero) + ' (' + esc(etiqueta) + ') va encadenado con este</div>' +
              '<p>Pero lo emite <b>otra sociedad</b>, así que no se puede combinar en la misma factura: sería una sociedad cobrando el ingreso de otra.</p></div>';
        }).join('');
        Array.prototype.forEach.call(cajaV.querySelectorAll('[data-vinc]'), function (b) {
          var c = data.filter(function (x) { return x.id === b.getAttribute('data-vinc'); })[0];
          b.addEventListener('click', function () { if (!b.disabled) traeVinculado(c); });
        });
        Array.prototype.forEach.call(cajaV.querySelectorAll('[data-unidad]'), function (b) {
          var c = data.filter(function (x) { return x.id === b.getAttribute('data-unidad'); })[0];
          var precioC = parseImporte(c.precio_total || (c.campos || {}).precio_total), total = C.precio + precioC;
          DESC_UNIDAD = 'Precio total del contrato ' + (C.numero || '');
          var descOtro = (TE()[c.tipo] || c.tipo || 'Vinculado') + ' — precio total del contrato ' + c.numero;
          b.setAttribute('data-otra', descOtro);
          var btnTraer = cajaV.querySelector('[data-vinc="' + c.id + '"]'); if (btnTraer) btnTraer.setAttribute('data-otra', descOtro);
          b.addEventListener('click', function () {
            if (b.disabled) return;
            var sigue = enBlanco() ? Promise.resolve(true) : lwConfirmar({
              titulo: 'Facturar la unidad completa',
              cuerpo: '<p>Sustituye los conceptos por <b>dos líneas</b>: el precio total de cada uno de los dos contratos.</p>' +
                '<p>Dos líneas y no una a propósito: son dos relaciones jurídicas con el mismo comprador, y fundirlas borra a qué contrato corresponde cada euro.</p>',
              confirmar: 'Sustituir por los dos', cancelar: 'Dejarlo como está' });
            sigue.then(function (ok) {
              if (!ok) return;
              pon([{ descripcion: DESC_UNIDAD, importe: importeTxtDoc(C.precio) }, { descripcion: descOtro, importe: importeTxtDoc(precioC) }]);
              toast('Factura por la unidad completa: ' + fmtMoneda(total, monedaP));
            });
          });
        });
        marca();
      });
    }
    function precarga() {
      if (!ctx.esNuevo || ctx.tipoActual() !== 'proforma' || !enBlanco()) return;
      var auto = caja.querySelector('[data-todo]'); if (!auto || auto.disabled) return;
      auto.click();
      setTimeout(function () { huella = JSON.stringify(filas()); }, 60);
      setTimeout(function () { toast('Proforma precargada con el total del proyecto'); }, 350);
    }
    function sueltaPrecarga() {
      if (!huella || ctx.tipoActual() === 'proforma') return;
      if (JSON.stringify(filas()) !== huella) { huella = null; return; }
      huella = null; pon([{ descripcion: '', importe: '' }]);
      toast('Conceptos vaciados: el total del proyecto es de la proforma, no de una factura');
    }
    /* Variante RECIBÍ (paraRecibi del clásico): lo traído y bloqueado, y
       cuánto lleva cobrado ESTE contrato — la pregunta de verdad cuando
       entra un pago parcial. Con lwAgrupaPorContrato, las mismas reglas de
       dinero que el listado; nunca una segunda forma de sumar lo cobrado. */
    function pintaRecibi() {
      caja.innerHTML = '<div class="t">Del contrato ' + esc(C.numero || '') + '</div>' +
        '<p class="arrastrado">' + (C.puesto.length ? 'Traído del contrato y <b>bloqueado</b>: ' + esc(C.puesto.join(', ')) + '.' : 'El contrato no tenía datos de cliente que traer.') +
          (C.nCompradores > 1 ? ' Contrato a <b>' + C.nCompradores + ' nombres</b>.' : '') + '</p>' +
        '<p class="arrastrado" data-cobrado>Calculando cuánto lleva cobrado este contrato…</p>';
      var caj = caja.querySelector('[data-cobrado]');
      return ctx.sb.rpc('facturas_equipo').select('id,tipo,total,moneda,anulada,contrato_id,contrato_numero,cliente_nombre,proyecto_nombre,fecha_emision')
        .eq('contrato_id', C.id).then(function (r) {
          if (r.error) { caj.textContent = 'No se pudo calcular lo cobrado: ' + r.error.message; return; }
          var docs = r.data || [];
          if (!docs.length) { caj.textContent = 'Este contrato no tiene todavía ninguna factura ni recibí.'; return; }
          if (typeof lwAgrupaPorContrato !== 'function' || typeof lwSumaTexto !== 'function') { caj.textContent = ''; return; }
          var g = lwAgrupaPorContrato(docs)[0];
          var pct = g.unaMoneda && g.totalFacturado ? ' · ' + g.pct.toFixed(0) + ' %' : '';
          caj.innerHTML = 'De este contrato hay <b>' + esc(lwSumaTexto(g.cobrado)) + '</b> cobrado' +
            (g.totalFacturado ? ' sobre ' + esc(lwSumaTexto(g.facturado)) + ' facturado' + pct : '') + '.';
        });
    }
    return {
      pon: function (res) {
        var moneda = ctx.monedaActual() || res.moneda || 'EUR', precio = parseImporte(res.precio);
        C = { id: res.id, numero: res.numero, tipoContrato: res.tipoContrato, padreId: res.padreId, puesto: res.puesto || [],
              nCompradores: res.nCompradores || 0, precio: precio, moneda: moneda, hitos: hitosDeDoc(res.hitos, precio, moneda) };
        caja.innerHTML = '<div class="t">Cargando contrato…</div>';
        if (ctx.esRecibi) return pintaRecibi();
        return cargaOtraFactura(res.id).then(cargaVencimientos).then(pinta).then(pintaVinculados).then(precarga);
      },
      repinta: function () { if (!C) return; if (ctx.esRecibi) pintaRecibi(); else pinta(); },
      marca: function () { if (!ctx.esRecibi) marca(); },
      alCambiarTipo: function () { if (ctx.esRecibi) return; sueltaPrecarga(); if (C) pinta(); },
      limpia: function () { C = null; caja.innerHTML = ''; cajaV.innerHTML = ''; }
    };
  }

  function montaLineasDoc(host, iniciales, alCambiar) {
    var filas = (iniciales && iniciales.length)
      ? iniciales.map(function (l) { return { descripcion: l.descripcion || '', importe: l.importe || '' }; })
      : [{ descripcion: '', importe: '' }];
    var wrap = document.createElement('div'); wrap.style.cssText = 'display:grid;gap:6px';
    var lista = document.createElement('div'); lista.style.cssText = 'display:grid;gap:6px'; wrap.appendChild(lista);
    var btnAdd = document.createElement('button'); btnAdd.type = 'button'; btnAdd.textContent = '+ Añadir concepto';
    btnAdd.style.cssText = 'justify-self:start;padding:7px 12px;border-radius:8px;border:1px dashed ' + CAJ.hoja +
      ';background:transparent;color:' + CAJ.lago + ';font-weight:600;font-size:12.5px;cursor:pointer';
    wrap.appendChild(btnAdd);
    host.appendChild(wrap);
    function repinta() {
      lista.innerHTML = '';
      filas.forEach(function (f, i) {
        var el = document.createElement('div');
        el.style.cssText = 'display:grid;grid-template-columns:1fr 130px 22px;gap:6px;align-items:center';
        var campoEstilo = 'padding:7px 8px;border:1px solid ' + CAJ.borde + ';border-radius:6px;font-size:12.5px;' +
          'color:' + CAJ.tinta + ';background-color:' + CAJ.papel + ';box-sizing:border-box;width:100%';
        var inpDesc = document.createElement('input'); inpDesc.type = 'text'; inpDesc.placeholder = 'Descripción';
        inpDesc.value = f.descripcion; inpDesc.style.cssText = campoEstilo;
        var inpImp = document.createElement('input'); inpImp.type = 'text'; inpImp.inputMode = 'decimal';
        inpImp.placeholder = 'Importe'; inpImp.value = f.importe; inpImp.style.cssText = campoEstilo;
        var btnDel = document.createElement('button'); btnDel.type = 'button'; btnDel.textContent = '×'; btnDel.title = 'Quitar concepto';
        btnDel.style.cssText = 'border:0;background:none;color:#9E2F26;font-size:19px;line-height:1;cursor:pointer';
        inpDesc.addEventListener('input', function () { f.descripcion = inpDesc.value; });
        inpImp.addEventListener('input', function () { f.importe = inpImp.value; });
        inpImp.addEventListener('blur', function () {
          var n = lwParseImporte(inpImp.value);
          var txt = lwImporteCanonico(n);
          inpImp.value = txt; f.importe = txt;
        });
        btnDel.addEventListener('click', function () {
          if (filas.length <= 1) filas = [{ descripcion: '', importe: '' }]; else filas.splice(i, 1);
          repinta();
        });
        el.appendChild(inpDesc); el.appendChild(inpImp); el.appendChild(btnDel);
        lista.appendChild(el);
      });
      if (alCambiar) alCambiar();
    }
    repinta();
    btnAdd.addEventListener('click', function () { filas.push({ descripcion: '', importe: '' }); repinta(); });
    var api = function () { return filas.filter(function (f) { return (f.descripcion || '').trim() || (f.importe || '').trim(); }); };
    // Para el bloque «Del contrato» (22-sep-2026): los hitos y el total del
    // contrato ESCRIBEN líneas, igual que LINEAS en el clásico. `anade` quita
    // la única línea en blanco antes de meter la primera, como allí.
    api.todas = function () { return filas; };
    api.pon = function (nuevas) { filas = (nuevas || []).map(function (l) { return Object.assign({}, l); }); if (!filas.length) filas = [{ descripcion: '', importe: '' }]; repinta(); };
    api.anade = function (l) {
      if (filas.length === 1 && !(filas[0].descripcion || '').trim() && !(filas[0].importe || '').trim()) filas = [];
      filas.push(Object.assign({}, l)); repinta();
    };
    return api;
  }

  /* Justificantes de un recibí — mismo bucket ('justificantes'), misma
     convención de ruta (UUID+extensión; el NOMBRE ORIGINAL va dentro del
     jsonb, nunca en la ruta — revisión previa Seguridad) y mismo tope (8,
     10 MB) que /intranet/facturas/: `guardar_recibi()` valida cada `path`
     contra `storage.objects`, así que hay que subir ANTES de llamar al RPC
     y con la misma convención, o el RPC rechaza el recibí entero. */
  /* `iniciales` (22-sep-2026): al EDITAR, los justificantes que el recibí ya
     tiene se conservan y se ofrecen con «Ver» (URL firmada de 5 min, como
     el clásico) y «Quitar» — quitar es de la lista, nunca del bucket. Antes
     la v4 obligaba a resubirlos todos al guardar cambios. */
  function montaJustificantesDoc(host, sb, iniciales) {
    var lista = (iniciales || []).filter(function (j) { return j && j.path; }).map(function (j) { return Object.assign({}, j); });
    var wrap = document.createElement('div'); wrap.style.cssText = 'display:grid;gap:8px';
    var input = document.createElement('input'); input.type = 'file'; input.multiple = true;
    input.accept = 'image/jpeg,image/png,image/webp,application/pdf';
    input.style.cssText = 'padding:7px 10px;border:1px solid ' + CAJ.borde + ';border-radius:8px;font-size:12.5px;background:' + CAJ.papel;
    var estado = document.createElement('div'); estado.style.cssText = 'display:grid;gap:4px;font-size:12.5px';
    var hint = document.createElement('p');
    hint.style.cssText = 'margin:0;font-size:11.5px;color:' + CAJ.apagado;
    hint.textContent = 'Hasta 8, 10 MB cada uno. Se puede adjuntar más de uno: un pago real llega a veces en el resguardo y la captura del banco.';
    wrap.appendChild(input); wrap.appendChild(estado); wrap.appendChild(hint);
    host.appendChild(wrap);
    function repinta() {
      estado.innerHTML = lista.map(function (j, i) {
        return '<div style="display:flex;justify-content:space-between;gap:8px;align-items:center">' +
          '<span>✓ ' + esc(j.nombre || 'Justificante adjunto') + '</span>' +
          '<span style="display:flex;gap:10px;align-items:center">' +
          '<button type="button" data-ver="' + i + '" style="all:unset;cursor:pointer;font-size:12px;font-weight:600;color:' + CAJ.lago + ';text-decoration:underline">Ver</button>' +
          '<button type="button" data-quitar="' + i + '" title="Quitar de este recibí" style="border:0;background:none;color:#9E2F26;cursor:pointer;font-size:16px;line-height:1">×</button></span></div>';
      }).join('');
    }
    estado.addEventListener('click', function (ev) {
      var v = ev.target.closest('[data-ver]');
      if (v) {
        var j = lista[Number(v.getAttribute('data-ver'))]; if (!j || !j.path) return;
        sb.storage.from('justificantes').createSignedUrl(j.path, 300).then(function (u) {
          if (u.error || !u.data) return toastMal(lwErrorHumano(u.error || {}, 'No se pudo abrir el justificante'));
          window.open(u.data.signedUrl, '_blank', 'noopener');
        });
        return;
      }
      var b = ev.target.closest('[data-quitar]'); if (!b) return;
      lista.splice(Number(b.getAttribute('data-quitar')), 1); repinta();
    });
    repinta();
    input.addEventListener('change', function () {
      var elegidos = Array.prototype.slice.call(input.files); input.value = '';
      if (!elegidos.length) return;
      if (lista.length + elegidos.length > 8) { toastMal('Un recibí admite hasta 8 justificantes (ya lleva ' + lista.length + ')'); return; }
      elegidos.reduce(function (p, f) {
        return p.then(function () {
          if (f.size > 10 * 1024 * 1024) { toastMal(f.name + ' supera los 10 MB: no se ha subido'); return; }
          var ext = (f.name.match(/\.[a-z0-9]+$/i) || [''])[0].toLowerCase();
          var path = crypto.randomUUID() + ext;
          return sb.storage.from('justificantes').upload(path, f, { upsert: false, contentType: f.type || 'application/octet-stream' })
            .then(function (up) {
              if (up.error) { toastMal(lwErrorHumano(up.error, 'No se pudo subir ' + f.name)); return; }
              lista.push({ path: path, nombre: f.name, subido_en: new Date().toISOString() }); repinta();
            });
        });
      }, Promise.resolve());
    });
    return function () { return lista; };
  }

  /* Ver un documento ya emitido: cajón con un <iframe> a la herramienta
     clásica en modo `?vista=1` (mismo origen, misma sesión, sin exigir el
     permiso de emitir). Nunca se reescribe el render aquí. */
  /* ═══ ACCIONES DEL DOCUMENTO — la barra de la previa del clásico (22-sep-2026)
     Owner: «te faltan todos los botones de herramientas que había en la
     intranet antigua». Son los de `.pv-bar` de /intranet/facturas/: Descargar
     PDF · Enviar por email · Crear recibí · 📨 Registro (Guardar ya es el
     «Emitir» del pie del cajón). Viven en TRES sitios con el mismo código:
     la barra de la previa de los dos editores (factura y recibí), el visor
     que se abre al emitir, y la ficha de factura de datos.js (via
     window.LW_V4.*). Reglas de activación calcadas de `razon()` del clásico,
     con su porqué: sin número no hay PDF ni email (9-sep-2026, owner: se
     pudo descargar un documento que no existía en la base y no se
     distinguía de uno emitido); el recibí solo nace de una FACTURA guardada.
     El diálogo del email y el registro van en `lwConfirmar` (dialogo.js):
     es lo único que se apila por encima del cajón del editor — `modal()`
     cierra el anterior al abrirse y `cajon()` queda por debajo. */
  function limpiaNombreDoc(s) {
    return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '_');
  }
  function tipoDocEs(vals) {
    return ((typeof TIPOS_DOC !== 'undefined' && TIPOS_DOC[vals.tipo]) || { es: 'Factura' }).es;
  }
  // La MISMA página que arma el renderizador de PDF (correo, factura
  // automática de la firma): lo que se descarga es lo que recibe el comprador.
  function paginaDoc(vals, saved) {
    return documentoPagina(vals, { numero: (saved && saved.numero) || '', emisor: (saved && saved.emisor) || null, base: location.origin });
  }
  function totalDoc(vals) {
    try { return calcTotales(vals.lineas || [], vals.moneda, { pct: vals.imp_pct }).total || 0; } catch (e) { return 0; }
  }
  /* PDF: lo genera el navegador, igual que en el clásico (window.print), pero
     sobre un iframe oculto con la página del documento — la v4 no puede
     imprimir su propia página (saldría la intranet entera). El título del
     iframe y el de la página son el nombre del PDF que propone el navegador. */
  function imprimeDoc(vals, saved) {
    var rotulo = (saved && saved.numero) || limpiaNombreDoc(tipoDocEs(vals));
    var titulo = (rotulo + '_' + (limpiaNombreDoc(vals.cliente_nombre) || 'SIN_NOMBRE')).toUpperCase();
    var html = paginaDoc(vals, saved).replace('<head>', '<head><title>' + esc(titulo) + '</title>');
    var fr = document.createElement('iframe');
    fr.setAttribute('aria-hidden', 'true'); fr.title = titulo;
    fr.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden';
    var antes = document.title, hecho = false;
    var quita = function () { if (hecho) return; hecho = true; document.title = antes; if (fr.parentNode) fr.parentNode.removeChild(fr); };
    fr.onload = function () {
      var w = fr.contentWindow, d = fr.contentDocument;
      var listo = (d && d.fonts && d.fonts.ready) ? d.fonts.ready : Promise.resolve();
      listo.then(function () {
        setTimeout(function () {
          document.title = titulo;
          try { w.addEventListener('afterprint', function () { setTimeout(quita, 300); }); w.focus(); w.print(); }
          catch (e) { quita(); toastMal('No se pudo abrir la impresión: ' + (e && e.message || e)); }
          setTimeout(quita, 180000);
        }, 200);
      });
    };
    document.body.appendChild(fr);
    fr.srcdoc = html;
  }
  /* Email: mismo endpoint y mismo payload que el clásico — la Edge
     send-contract-email renderiza el PDF vía Railway (fuera del WAF de
     Hostinger, LAW-30) y deja la fila en `correos_enviados` con factura_id.
     Al confirmar se marca `facturas.enviada` (Administración, 11-ago: sin
     esto el envío manual no congelaba la factura). El botón lo pulsa una
     persona: mandar un correo a un tercero real no se automatiza. */
  function enviaDocMail(sb, vals, saved, alEnviado) {
    if (!(saved && saved.numero)) return aviso('Guarda el documento primero: sin número no se envía, porque no queda registrado como emitido.', '#8A6A34');
    var tipo = tipoDocEs(vals);
    var estiloIn = 'width:100%;box-sizing:border-box;padding:9px 12px;border:1px solid ' + CAJ.borde + ';border-radius:8px;font:500 14px/1.4 inherit;color:' + CAJ.tinta + ';background:#fff;margin-top:4px';
    var campo = function (id, label, tag, attrs, valor) {
      return '<label style="display:block;margin:0 0 10px;font-size:12px;color:' + CAJ.apagado + '">' + esc(label) +
        (tag === 'textarea'
          ? '<textarea id="' + id + '" ' + attrs + ' style="' + estiloIn + ';resize:vertical">' + esc(valor) + '</textarea>'
          : '<input id="' + id + '" ' + attrs + ' value="' + esc(valor) + '" style="' + estiloIn + '">') + '</label>';
    };
    var cuerpo = '<p style="margin:0 0 12px;font-size:12.5px;line-height:1.5;color:#8A6A34">Se adjunta ' + esc(saved.numero) + ' en PDF, tal y como se ve en la vista previa.</p>' +
      campo('lw-mail-para', 'Para', 'input', 'type="email" autocomplete="off" placeholder="cliente@email.com"', vals.cliente_email || '') +
      campo('lw-mail-asunto', 'Asunto', 'input', 'type="text"', tipo + ' ' + saved.numero + ' — Lawang Tropical Properties') +
      // Firmante del CORREO: siempre la marca, nunca la sociedad emisora (owner, 8-sep-2026)
      campo('lw-mail-msg', 'Mensaje', 'textarea', 'rows="6"', 'Buenos días' + (vals.cliente_nombre ? ' ' + vals.cliente_nombre : '') + ',\n\n' +
        'Adjunto ' + tipo.toLowerCase() + ' ' + saved.numero + ' para su revisión.\n\nUn saludo,\nLawang Tropical Properties');
    lwConfirmar({ titulo: 'Enviar por email — ' + saved.numero, cuerpo: cuerpo, confirmar: 'Enviar' }).then(function (ok) {
      if (!ok) return;
      var v = function (id) { var el = document.getElementById(id); return el ? el.value.trim() : ''; };
      var para = v('lw-mail-para'), asunto = v('lw-mail-asunto'), msg = v('lw-mail-msg');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(para)) { toastMal('Email de destinatario no válido'); return; }
      if (!asunto) { toastMal('Falta el asunto'); return; }
      toast('Enviando a ' + para + '…');
      sb.auth.getSession().then(function (r) {
        var tok = r && r.data && r.data.session && r.data.session.access_token;
        return fetch('https://vtulllundrfennhjddhc.supabase.co/functions/v1/send-contract-email', {
          method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + (tok || '') },
          body: JSON.stringify({
            to: para, subject: asunto, message: msg,
            filename: (saved.numero + '_' + (limpiaNombreDoc(vals.cliente_nombre) || 'CLIENTE') + '.pdf').toUpperCase(),
            factura_id: saved.id, contrato_id: saved.contrato_id || null,
            html: paginaDoc(vals, saved)
          })
        });
      }).then(function (r) { return r.json().catch(function () { return { ok: false, error: 'Respuesta inválida del servidor' }; }); })
        .then(function (res) {
          if (!(res && res.ok)) { toastMal((res && res.error) || 'No se pudo enviar'); return; }
          return sb.from('facturas').update({ enviada: true, fecha_envio: new Date().toISOString() }).eq('id', saved.id).then(function (m) {
            if (m.error) console.error('factura', saved.numero, 'enviada pero SIN marcar enviada=true:', m.error.message);
            toast('Enviado a ' + para);
            if (alEnviado) alEnviado();
          });
        }, function (err) { toastMal('Error: ' + (err && err.message || err)); });
    });
  }
  /* Registro de envíos: `correos_enviados` por factura_id, como el clásico
     (31-ago-2026, owner: «ver qué hemos hecho con cada documento»). */
  function registroEnviosDoc(sb, saved) {
    if (!(saved && saved.id)) return aviso('Guarda el documento para ver su registro.', '#8A6A34');
    var H = window.lwCajonHtml;
    var via = function (x) { return typeof lwViaCorreo === 'function' ? lwViaCorreo(x) : (x || '—'); };
    var fecha = function (iso) { return iso ? new Date(iso).toLocaleString('es-ES', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'; };
    sb.from('correos_enviados').select('para,asunto,via,enviado_por,enviado_en')
      .eq('factura_id', saved.id).order('enviado_en', { ascending: false }).limit(200).then(function (r) {
        var cuerpo = r.error ? H.nota('No se pudo cargar el registro: ' + r.error.message)
          : (r.data || []).length
            ? H.tabla(['Cuándo', 'Para', 'Vía', 'Quién', 'Asunto'], r.data.map(function (m) {
                return [esc(fecha(m.enviado_en)), esc(m.para), esc(via(m.via)), esc(m.enviado_por || 'Automático'), esc(m.asunto)];
              }))
            : H.nota('Sin correos registrados para este documento.');
        lwConfirmar({ titulo: 'Registro de envíos — ' + (saved.numero || ''), cuerpo: cuerpo, confirmar: 'Cerrar', cancelar: false });
      });
  }
  function creaRecibiDesdeDoc(saved) {
    lwConfirmar({
      titulo: 'Crear un recibí de ' + (saved.numero || 'esta factura'),
      cuerpo: '<p style="margin:0">Esta factura ya está guardada, así que no se pierde. Se abre un recibí nuevo enganchado a ella.</p>',
      confirmar: 'Crear recibí'
    }).then(function (ok) {
      if (!ok) return;
      // El visor se cierra SIN su alCerrar (que recarga la página): el recibí
      // se abre encima y una recarga aquí lo mataría a medio rellenar.
      var cajonAbierto = document.getElementById('lw-cajon'); if (cajonAbierto) cajonAbierto._alCerrar = null;
      // Y el editor en modo lectura tampoco dispara el suyo (recargaría la
      // página encima del recibí recién abierto).
      var editorAbierto = document.getElementById('lw-editor'); if (editorAbierto) editorAbierto._alCerrar = null;
      cierraModal(); cierraCajon();
      abrirEditorRecibiDoc({ contrato_id: saved.contrato_id, factura_id: saved.id });
    });
  }
  /* La barra, montada sobre `piezas.barra` del split. `ctx`: { sb, getVals,
     saved: {id, numero, tipo, contrato_id, emisor}, esRecibi, alEnviado }.
     Devuelve `repasa()`, que cada editor llama tras repintar la previa: el
     total cambia con cada tecla y con él lo que se puede hacer. Un botón
     apagado no está `disabled` (un disabled no enseña su `title` al pasar
     el ratón): se atenúa y, al pulsarlo, dice POR QUÉ no — que es lo que
     el clásico ponía en el title. */
  function montaBarraDoc(piezas, ctx) {
    var barra = piezas.barra; if (!barra) return function () {};
    var sp = document.createElement('span'); sp.style.cssText = 'flex:1 1 auto'; barra.appendChild(sp);
    barra.style.flexWrap = 'wrap';
    var base = 'padding:6px 12px;border-radius:999px;border:1px solid ' + CAJ.borde + ';background:' + CAJ.papel + ';color:' + CAJ.lago +
      ';font-weight:600;font-size:12px;cursor:pointer;white-space:nowrap;line-height:1.3';
    function btn(texto, onClick) {
      var b = document.createElement('button'); b.type = 'button'; b.textContent = texto; b.style.cssText = base;
      b.addEventListener('click', function (ev) {
        ev.preventDefault();
        if (b.getAttribute('aria-disabled') === 'true') return aviso(b.getAttribute('data-porque') || 'No disponible todavía.', '#8A6A34');
        onClick();
      });
      barra.appendChild(b); return b;
    }
    function razon(b, ok, porque) {
      if (!b) return;
      b.setAttribute('aria-disabled', ok ? 'false' : 'true');
      b.setAttribute('data-porque', ok ? '' : porque); b.title = ok ? '' : porque;
      b.style.opacity = ok ? '1' : '.45';
    }
    /* «Emitir» pequeño y junto a «Vista previa» (owner, 22-sep-2026): el
       submit del modal se MUEVE aquí (sigue dentro del <form>, así que
       sigue siendo el submit y el modal lo sigue encontrando por data-e) y
       el pie del cajón se esconde — la × de la cabecera cierra. */
    if (ctx.principal) {
      var pie = ctx.principal.parentNode;
      ctx.principal.style.cssText = 'flex:0 0 auto;padding:6px 16px;border-radius:999px;border:0;background:' + CAJ.lago +
        ';color:#fff;font-weight:600;font-size:12.5px;cursor:pointer;white-space:nowrap;line-height:1.3;margin-left:6px';
      barra.insertBefore(ctx.principal, sp);
      // El pie se esconde solo en escritorio (regla en aseguraEstiloSplitDoc):
      // ≤860px la previa se apila BAJO el formulario y Emitir quedaría debajo
      // de veinte campos — ahí el pie vuelve y el botón de la barra se oculta.
      if (pie) pie.classList.add('lw-doc-pie-movido');
      ctx.principal.classList.add('lw-doc-emitir-barra');
    }
    var bPdf = btn('Descargar PDF', function () { imprimeDoc(ctx.getVals(), ctx.saved); });
    var bMail = btn('Enviar por email', function () { enviaDocMail(ctx.sb, ctx.getVals(), ctx.saved, ctx.alEnviado); });
    var bRec = ctx.esRecibi ? null : btn('Crear recibí', function () { creaRecibiDesdeDoc(ctx.saved); });
    var bReg = btn('📨 Registro', function () { registroEnviosDoc(ctx.sb, ctx.saved); });
    function repasa() {
      var vals = ctx.getVals(), total = totalDoc(vals), num = !!(ctx.saved && ctx.saved.numero);
      razon(bPdf, total > 0 && num, !(total > 0) ? 'Todavía no hay ningún importe: el PDF saldría con el total a cero.'
        : 'Guarda primero: sin guardar no hay número, y el PDF saldría idéntico a uno emitido sin existir en la base.');
      razon(bMail, total > 0 && num, !(total > 0) ? 'Todavía no hay ningún importe que cobrar.'
        : 'Guarda primero: sin guardar no hay número, y el comprador recibiría un documento que no existe en la base.');
      razon(bRec, vals.tipo === 'factura' && num, vals.tipo !== 'factura' ? 'Solo se crea un recibí a partir de una factura.' : 'Guarda primero esta factura.');
      bReg.style.display = (ctx.saved && ctx.saved.id) ? '' : 'none';
    }
    repasa();
    return repasa;
  }
  // Un documento ya guardado, en la forma que las acciones esperan: `vals`
  // (fields + lineas, lo que lee documentoHTML) y `saved` (identidad +
  // emisor congelado). facturas_equipo(): el documento pudo emitirlo otro
  // agente del equipo; rpc + eq + maybeSingle, sin order (42703 sobre RPC).
  function cargaDocGuardado(sb, id) {
    return sb.rpc('facturas_equipo').select('id,numero,tipo,contrato_id,cliente_nombre,datos').eq('id', id).maybeSingle().then(function (r) {
      if (r.error || !r.data) return { error: (r.error && r.error.message) || 'No se encontró ese documento.' };
      var f = r.data, datos = f.datos || {};
      var vals = Object.assign({}, datos.fields || {}, { lineas: datos.lineas || [] });
      if (!vals.tipo) vals.tipo = f.tipo || 'factura';
      if (!vals.cliente_nombre) vals.cliente_nombre = f.cliente_nombre || '';
      return { vals: vals, saved: { id: f.id, numero: f.numero, tipo: f.tipo, contrato_id: f.contrato_id, emisor: datos.emisor || null } };
    });
  }
  function conDocGuardado(id, cb) {
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      aseguraModulosDoc(['entities', 'totales', 'dialogo', 'documento']).then(function () {
        return cargarSociedades(aut.sb).then(null, function () { return null; });
      }).then(function () { return cargaDocGuardado(aut.sb, id); })
        .then(function (d) { if (d.error) return toastMal(d.error); cb(aut, d); },
              function (e) { toastMal('No se pudo preparar el documento: ' + (e && e.message || e)); });
    });
  }
  // Para la ficha de factura (datos.js): las tres acciones sobre un id.
  window.LW_V4 = window.LW_V4 || {};
  window.LW_V4.imprimirDocumento = function (id) { conDocGuardado(id, function (aut, d) { imprimeDoc(d.vals, d.saved); }); };
  window.LW_V4.enviarDocumento = function (id) {
    conDocGuardado(id, function (aut, d) {
      if (!puedeH(aut.ficha, 'facturas')) return aviso('Enviar documentos exige la herramienta «Facturas» — pídesela a un administrador.', '#8A6A34');
      enviaDocMail(aut.sb, d.vals, d.saved, function () { location.reload(); });
    });
  };
  window.LW_V4.registroEnvios = function (id) { conDocGuardado(id, function (aut, d) { registroEnviosDoc(aut.sb, d.saved); }); };

  /* El visor que se abre al emitir: el documento tal cual lo pinta el clásico
     (iframe ?vista=1, mismo origen) y, en el pie, las mismas acciones que la
     barra de la previa — es donde el usuario aterriza con el número recién
     asignado, así que es donde de verdad descarga y envía. */
  /* «Abrir el documento» y el visor tras emitir (22-sep-2026, owner: «la
     vista que usamos para Nuevo documento es la que debemos usar para Abrir
     documento»): el MISMO editor a pantalla completa, en modo lectura —
     formulario inerte con lo guardado, la hoja al lado y la barra con PDF,
     email, recibí y registro. El iframe ?vista=1 de la herramienta clásica
     se retira: era otra vista. `alCerrar` llega al modal (recarga el listado
     tras emitir, o vuelve a la ficha). */
  function abreDocumentoViewerDoc(id, alCerrar) {
    if (!id || !window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      aut.sb.rpc('facturas_equipo').select('id,tipo').eq('id', id).maybeSingle().then(function (r) {
        if (r.error || !r.data) return toastMal('No se encontró ese documento' + (r.error ? ': ' + r.error.message : '.'));
        if (r.data.tipo === 'recibi') abrirEditorRecibiDoc({ id: id, soloLectura: true, alCerrar: alCerrar });
        else abrirEditorFacturaDoc({ id: id, soloLectura: true, alCerrar: alCerrar });
      });
    });
  }
  // Deja el editor recién abierto en modo lectura: clase para el CSS (botones
  // fuera, campos inertes) + readOnly real (la clase quita el ratón, no el
  // teclado) + fuera el submit y el pie. Idempotente: se repite tras cada
  // repintado de líneas/aplicaciones, que crea campos nuevos.
  function dejaSoloLecturaDoc() {
    var ed = document.getElementById('lw-editor'); if (!ed) return;
    ed.classList.add('lw-doc-lectura');
    Array.prototype.forEach.call(ed.querySelectorAll('.lw-doc-split>div:first-child input,.lw-doc-split>div:first-child textarea,.lw-doc-split>div:first-child select'), function (el) {
      if (el.tagName === 'SELECT') el.tabIndex = -1; else el.readOnly = true;
    });
    var g = ed.querySelector('[data-e="guardar"]');
    if (g) { var pie = g.parentNode; g.remove(); if (pie) pie.classList.add('lw-doc-pie-oculto'); }
  }

  /* ---------- calco estructural del formulario clásico (21-sep-2026) ----------
     Owner, al ver el editor de arriba: «no me vale esto, necesito la misma
     estructura antigua pero con nuevo restyling». Medido de verdad contra
     /intranet/facturas/ (capturas 1440 y 390, factura y recibí) — no de
     memoria. Estos cinco ayudantes son el ÚNICO sitio que dibuja una sección:
     tarjeta con barra + rótulo (Documento, Fechas, Conceptos, Lo que se ha
     cobrado) o tarjeta plegable con +/− (Emisor, Cliente, Impuesto, Notas),
     fila de dos columnas fija (Moneda+Nº, Fecha+Vencimiento — medido: el
     clásico NO las apila a 390, así que aquí tampoco hace falta breakpoint),
     y un campo simple con su etiqueta. Con esto un solo campo `custom` de
     `modal()` pinta la sección entera — cero cambios en `modal()` mismo, así
     que los otros 15 editores que lo usan no se tocan ni hay que
     reverificarlos. Piel: los mismos tokens CAJ de siempre, NUNCA
     documento.css ni clases del clásico. */
  function tituloBarraDoc(texto) {
    return '<div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">' +
      '<span style="width:3px;height:13px;background:' + CAJ.lago + ';border-radius:2px;display:inline-block;flex:0 0 auto"></span>' +
      '<span style="font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' + CAJ.tinta + '">' + esc(texto) + '</span></div>';
  }
  function seccionFijaDoc(host, titulo) {
    var card = document.createElement('div');
    card.style.cssText = 'background:' + CAJ.papel + ';border:1px solid ' + CAJ.borde + ';border-radius:12px;padding:14px 16px;margin-bottom:12px;display:grid;gap:12px';
    card.innerHTML = tituloBarraDoc(titulo);
    host.appendChild(card);
    return card;
  }
  // Plegable con +/− a mano (no <details>: control total del marcador sin
  // colar una hoja de estilos global). Abierta por defecto en Emisor/Cliente,
  // cerrada en Impuesto/Notas — igual que el clásico.
  /* `resumen` (22-sep-2026, owner: «Emisor y Cliente pueden venir cerrados y
     mostrar la info al ladito sin tener que abrirlo»): calco de
     montarPlegables/repasaPlegables/RESUMEN_DE del clásico. Una sección con
     resumen se PLIEGA SOLA cuando todos sus campos tienen valor y enseña el
     resumen en su cabecera; con un hueco se queda abierta — plegar un hueco
     es esconder trabajo pendiente. Lo que el operador abre o cierra a mano
     (`forzado`) no se le vuelve a tocar. La regla corre en repintaSplitDoc,
     que ya corre en cada tecla. */
  var plegablesDocActivos = [];
  function seccionPlegableDoc(host, titulo, abierta, opts) {
    opts = opts || {};
    var card = document.createElement('div');
    card.style.cssText = 'background:' + CAJ.papel + ';border:1px solid ' + CAJ.borde + ';border-radius:12px;padding:14px 16px;margin-bottom:12px';
    var btn = document.createElement('button'); btn.type = 'button'; btn.setAttribute('data-lw-plegable', '1');
    btn.style.cssText = 'all:unset;box-sizing:border-box;cursor:pointer;display:flex;align-items:center;gap:8px;' +
      'font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' + CAJ.tinta + ';width:100%';
    var marca = document.createElement('span'); marca.style.cssText = 'width:11px;color:' + CAJ.apagado + ';flex:0 0 auto';
    marca.textContent = abierta ? '−' : '+';
    var lbl = document.createElement('span'); lbl.textContent = titulo; lbl.style.flex = '0 0 auto';
    var res = document.createElement('span');
    res.style.cssText = 'margin-left:auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right;' +
      'font-size:12.5px;font-weight:500;letter-spacing:0;text-transform:none;color:' + CAJ.apagado;
    btn.appendChild(marca); btn.appendChild(lbl); btn.appendChild(res);
    var body = document.createElement('div');
    body.style.cssText = 'display:' + (abierta ? 'grid' : 'none') + ';gap:12px;margin-top:12px';
    var estado = { body: body, res: res, marca: marca, resumen: opts.resumen, forzado: false };
    function pon(plegado) {
      body.style.display = plegado ? 'none' : 'grid';
      marca.textContent = plegado ? '+' : '−';
      res.textContent = (plegado && estado.resumen) ? (estado.resumen() || '') : '';
      btn.setAttribute('aria-expanded', String(!plegado));
    }
    estado.pon = pon;
    btn.addEventListener('click', function () { estado.forzado = true; pon(body.style.display !== 'none'); });
    card.appendChild(btn); card.appendChild(body);
    host.appendChild(card);
    if (opts.resumen) plegablesDocActivos.push(estado);
    return body;
  }
  function repasaPlegablesDoc() {
    plegablesDocActivos.forEach(function (p) {
      if (!p.body.isConnected) return;
      if (!p.forzado) {
        var campos = Array.prototype.filter.call(p.body.querySelectorAll('input,select,textarea'), function (el) {
          if (el.type === 'hidden') return false;
          for (var n = el.parentElement; n && n !== p.body; n = n.parentElement) { if (n.style.display === 'none') return false; }
          return true;
        });
        var completa = campos.length > 0 && campos.every(function (el) { return String(el.value || '').trim(); });
        p.pon(completa);
      } else {
        p.res.textContent = (p.body.style.display === 'none' && p.resumen) ? (p.resumen() || '') : '';
      }
    });
  }
  // Los resúmenes de Emisor y Cliente, como RESUMEN_DE del clásico: leen el
  // formulario vivo (campoDeDoc), así que valen para factura y recibí.
  function resumenEmisorDoc() {
    var soc = campoDeDoc('sociedad'), cta = campoDeDoc('cuenta');
    var s = soc && soc.selectedOptions && soc.selectedOptions[0] ? soc.selectedOptions[0].text.split(' (')[0] : '';
    var c = cta && cta.value ? (cta.selectedOptions[0] ? cta.selectedOptions[0].text : '') : '';
    return [s, (!c || /sin datos bancarios/i.test(c)) ? '⚠️ sin cuenta' : c].filter(Boolean).join(' · ');
  }
  function resumenClienteDoc() {
    var nEl = campoDeDoc('cliente_nombre'), pEl = campoDeDoc('proyecto_nombre');
    var n = (nEl && nEl.value || '').trim(), p = (pEl && pEl.value || '').trim();
    var partes = n.split('·').map(function (x) { return x.trim(); }).filter(Boolean);
    var quien = partes.length > 1 ? partes[0] + ' +' + (partes.length - 1) : (n || 'sin nombre');
    return [quien, p].filter(Boolean).join(' · ');
  }
  function filaDosDoc(host) {
    var row = document.createElement('div');
    row.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:12px';
    host.appendChild(row);
    return row;
  }
  // Campo simple: etiqueta pequeña + control, SIN la tarjeta crema de
  // `modal()` — la tarjeta ya la pone la sección que lo envuelve, y una
  // segunda capa se leía como campo dentro de campo.
  function campoSimpleDoc(host, cfg) {
    var wrap = document.createElement('div'); wrap.style.cssText = 'display:grid;gap:5px;min-width:0';
    var lbl = document.createElement('label'); lbl.style.cssText = 'font-size:12px;color:' + CAJ.apagado + ';font-weight:500';
    lbl.textContent = cfg.label + (cfg.req ? ' *' : '');
    wrap.appendChild(lbl);
    var estilo = 'width:100%;padding:9px 12px;border:1px solid ' + CAJ.borde + ';border-radius:8px;font-weight:500;font-size:14px;' +
      'color:' + (cfg.readonly ? CAJ.apagado : CAJ.tinta) + ';background-color:' + (cfg.readonly ? CAJ.banda : CAJ.papel) + ';box-sizing:border-box';
    var el;
    if (cfg.tipo === 'select') {
      el = document.createElement('select'); el.style.cssText = estilo + flechaSelect;
      (cfg.opciones || []).forEach(function (o) {
        var vv = typeof o === 'string' ? [o, o] : o;
        var op = document.createElement('option'); op.value = vv[0]; op.textContent = vv[1];
        if (String(cfg.valor) === String(vv[0])) op.selected = true;
        el.appendChild(op);
      });
    } else if (cfg.tipo === 'textarea') {
      el = document.createElement('textarea'); el.rows = cfg.rows || 4; el.style.cssText = estilo + ';resize:vertical'; el.value = cfg.valor || '';
    } else {
      el = document.createElement('input'); el.type = cfg.tipo || 'text'; el.value = cfg.valor == null ? '' : cfg.valor;
      el.style.cssText = estilo + (cfg.readonly ? ';cursor:not-allowed' : '');
      if (cfg.readonly) { el.readOnly = true; el.tabIndex = -1; }
      if (cfg.placeholder) el.placeholder = cfg.placeholder;
    }
    if (cfg.k) el.setAttribute('data-k', cfg.k);
    wrap.appendChild(el);
    if (cfg.ayuda) { var s = document.createElement('small'); s.style.cssText = 'font-size:11.5px;color:' + CAJ.apagado; s.textContent = cfg.ayuda; wrap.appendChild(s); }
    host.appendChild(wrap);
    return el;
  }

  /* ---------- split en vivo (22-sep-2026, calco estructural — paso 2) ----------
     Owner: quiere el visor partido EN VIVO como el clásico — formulario a la
     izquierda, factura pintándose a la derecha mientras se rellena, no solo
     el iframe post-guardado. Medido en /intranet/facturas/: `.stage` es un
     grid `minmax(400px,500px) 1fr` que a ≤900px apila a una columna (medido:
     NO esconde la previa detrás de un FAB — el "Vista previa ⤢" es solo un
     atajo para bajar hasta ella, la pila entera es visible); repinta en
     CADA evento `input` del formulario (`$('#form').addEventListener('input',
     render)`), sin debounce; usa documentoHTML()/documentoVars() de
     documento.js — el MISMO motor del iframe post-guardado y del PDF que se
     manda solo al firmar, nunca reimplementado aquí. */
  var estiloSplitDocPuesto = false;
  function aseguraEstiloSplitDoc() {
    if (estiloSplitDocPuesto) return;
    estiloSplitDocPuesto = true;
    var s = document.createElement('style'); s.id = 'lw-doc-split-css';
    // grid-template-columns medido: mismo reparto que el clásico
    // (formulario acotado, previa se lleva el resto), a escala del cajón,
    // que es más estrecho que la página completa. ≤860px apila una columna
    // — mismo comportamiento que .stage del clásico a ≤900px, nunca oculta.
    // `min-width:0` en las dos columnas: sin esto un grid item toma como
    // mínimo el min-content de lo que lleva dentro —aquí una opción larga
    // del selector o el texto fijo "Lo asigna la base al guardar"— y la
    // columna se ensancha por su cuenta aunque el track sea 1fr, sacando
    // scroll horizontal del cajón. Medido a 390px: sin esto desbordaba.
    /* CALCO del clásico (22-sep-2026, owner: «copia el diseño de la factura»
       + «que se abra en pantalla completa como la versión en producción»):
       · reparto `minmax(400px,500px) 1fr` = `.stage` de /intranet/facturas/;
       · la previa (`.lw-doc-prev`) se queda PEGADA arriba mientras el
         formulario se desplaza por debajo — son los dos paneles con scroll
         propio del clásico, dentro del único scroll del cajón; el 180px es
         cabecera (91) + pie (69) + relleno superior del cuerpo (20), medidos
         en un arnés a 1440×900: Chrome pega el sticky al borde de CONTENIDO
         del scroller, no al de relleno, así que sin ese 20 la hoja se
         recortaba 22px por abajo;
       · `.lw-doc-pv` = `.pane-preview` + `.pv-scroll` del clásico, mismo
         fondo #eae5d8 y mismo centrado;
       · `.sheet` = la hoja del clásico LITERAL: A4 (210×297mm), 15mm 16mm,
         `zoom:.78` para que quepa en el panel, sombra, folio de la
         sociedad. Y la tipografía/tinta que el clásico pone en `body` y
         que aquí es Neue Kabel: sin `font-family` la factura salía en la
         fuente de la intranet, no en Jost (mismo fallo que el correo del
         6-ago, ver documentoPagina()). `zoom:.58` y scroll lateral ≤560px,
         como el móvil del clásico (31-jul). */
    // minmax(480px,600px) y no los 400-500 del clásico: owner, 22-sep-2026,
    // «la parte de escribir documentación que ocupe un 20% más».
    s.textContent = '.lw-doc-split{display:grid;grid-template-columns:minmax(480px,600px) 1fr;gap:18px;align-items:start;min-width:0}' +
      '.lw-doc-split>div{min-width:0}' +
      '.lw-doc-split>.lw-doc-prev{position:sticky;top:0;max-height:calc(100vh - 180px);display:flex;flex-direction:column}' +
      '.lw-doc-pv{flex:1 1 auto;min-height:0;overflow:auto;background:#eae5d8;padding:22px 0 60px;display:flex;justify-content:center}' +
      '.lw-doc-pv .sheet{flex:0 0 auto;width:210mm;min-height:297mm;background:var(--folio,#fff);padding:15mm 16mm;box-sizing:border-box;zoom:.78;' +
        'box-shadow:0 10px 40px rgba(46,52,55,.16);font-family:var(--font-body,\'Jost\',sans-serif);color:var(--ink,#2E3437)}' +
      // !important: el pie de modal() lleva su display:flex EN LÍNEA (cajaPie),
      // y una clase sin !important no le gana. Medido en el arnés: sin esto el
      // pie seguía visible con Emitir ya movido a la barra.
      // ≤1366px el formulario cede a 560 (sigue +12% sobre el clásico): medido a
      // 1280, con 600 la hoja de 619px no cabía en la previa (599) y se
      // recortaba 18px por la izquierda. La hoja no se encoge: es el calco.
      '@media screen and (max-width:1366px){.lw-doc-split{grid-template-columns:minmax(480px,560px) 1fr}}' +
      '.lw-doc-pie-movido{display:none !important}' +
      /* MODO LECTURA (22-sep-2026, owner: «la vista que usamos para Nuevo
         documento es la que debemos usar para Abrir documento»): la misma
         pantalla, con el formulario inerte. Los botones del formulario se
         esconden salvo los de plegar/desplegar, «Ver» justificante y el
         del contrato/factura (inerte, enseña el elegido); los campos no
         se tocan; sin Emitir ni pie. La barra de la previa (PDF, email,
         recibí, registro) sigue viva: es para lo que se abre. */
      '.lw-doc-pie-oculto{display:none !important}' +
      '.lw-doc-lectura .lw-doc-split>div:first-child button:not([data-lw-plegable]):not([data-ver]):not([data-lw-lectura-inerte]){display:none !important}' +
      '.lw-doc-lectura .lw-doc-split>div:first-child [data-lw-lectura-inerte]{pointer-events:none}' +
      '.lw-doc-lectura .lw-doc-split>div:first-child input[type=file]{display:none !important}' +
      '.lw-doc-lectura .lw-doc-split>div:first-child :is(input,select,textarea){pointer-events:none;background-color:#F1EBDD !important;color:#4A5052 !important}' +
      '@media screen and (max-width:860px){.lw-doc-split{grid-template-columns:1fr}.lw-doc-split>.lw-doc-prev{position:static;max-height:none}' +
        '.lw-doc-pie-movido{display:flex !important}.lw-doc-emitir-barra{display:none !important}}' +
      '@media screen and (max-width:560px){.lw-doc-pv .sheet{zoom:.58}.lw-doc-pv{overflow-x:auto;justify-content:flex-start;padding:16px 10px 60px}}';
    document.head.appendChild(s);
    /* Lo que el clásico carga en su <head> y la v4 no: los TOKENS de marca
       (brand.css: --brand-primary/--brand-deep/--font-body/--ink que
       documento.css consume; solo `:root{}`, sin solape con shell.css —
       comprobado con comm), las fuentes Jost + Cormorant Garamond del
       documento, y documento.css por si la pantalla que abre el editor
       (Home, Contratos, Operaciones también emiten recibís) no lo trae. Se
       inyectan aquí, UNA vez, y no en cada HTML: es el editor quien los
       necesita, no la pantalla. */
    [
      ['lw-doc-fonts', 'https://fonts.googleapis.com/css2?family=Jost:wght@300;400;500;600&family=Cormorant+Garamond:wght@400;500;600&display=swap'],
      ['lw-doc-brand', '/contracts/assets/brand.css'],
      ['lw-doc-css', '/intranet/facturas/documento.css']
    ].forEach(function (par) {
      if (document.getElementById(par[0])) return;
      if (par[0] !== 'lw-doc-fonts' && document.querySelector('link[href*="' + par[1].split('/').pop() + '"]')) return;
      var l = document.createElement('link'); l.id = par[0]; l.rel = 'stylesheet'; l.href = par[1];
      document.head.appendChild(l);
    });
  }
  // Construye el split y devuelve las piezas para que cada editor (factura,
  // recibí) escriba su propio repintado — la FORMA del documento difiere
  // (Conceptos vs. aplicaciones), el maquetado del split no.
  function montaSplitDoc(host) {
    aseguraEstiloSplitDoc();
    plegablesDocActivos = [];   // cada editor empieza con sus propias secciones plegables
    var wrap = document.createElement('div'); wrap.className = 'lw-doc-split';
    var colForm = document.createElement('div');
    var colPrev = document.createElement('div'); colPrev.className = 'lw-doc-prev';
    wrap.appendChild(colForm); wrap.appendChild(colPrev);
    host.appendChild(wrap);
    var barra = document.createElement('div');
    barra.style.cssText = 'display:flex;align-items:center;gap:8px;margin-bottom:10px;flex:0 0 auto';
    barra.innerHTML = '<span style="width:3px;height:13px;background:' + CAJ.lago + ';border-radius:2px;display:inline-block;flex:0 0 auto"></span>' +
      '<span style="font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' + CAJ.tinta + '">Vista previa</span>';
    colPrev.appendChild(barra);
    // El panel y la hoja son los del clásico (`.lw-doc-pv` ≡ .pane-preview +
    // .pv-scroll; `.sheet` A4 al 78%), pintados por aseguraEstiloSplitDoc():
    // aquí NO hay estilo inline — el que había (radio 4, 12mm, sin ancho de
    // folio) era una interpretación, y el owner pidió el diseño de la
    // factura, no uno parecido. DENTRO, `.doc` es documento.css tal cual.
    var pv = document.createElement('div'); pv.className = 'lw-doc-pv';
    var sheetWrap = document.createElement('div'); sheetWrap.className = 'sheet';
    var docEl = document.createElement('div'); docEl.className = 'doc';
    sheetWrap.appendChild(docEl);
    pv.appendChild(sheetWrap);
    colPrev.appendChild(pv);
    return { colForm: colForm, colPrev: colPrev, docEl: docEl, sheetWrap: sheetWrap, wrap: wrap, barra: barra };
  }
  // Pinta el documento con el MISMO motor que el clásico. `vals` es la forma
  // de `collect()`: los campos planos + `.lineas`. `numero` solo cuando ya
  // existe (un documento sin número es uno que aún no se ha emitido — igual
  // que en /intranet/facturas/).
  function repintaSplitDoc(piezas, vals, numero) {
    var soc = (typeof SOCIEDADES !== 'undefined' && SOCIEDADES[vals.sociedad]) || {};
    var v = documentoVars(soc);
    Object.keys(v.doc).forEach(function (k) { piezas.docEl.style.setProperty(k, v.doc[k]); });
    Object.keys(v.hoja).forEach(function (k) { piezas.sheetWrap.style.setProperty(k, v.hoja[k]); });
    piezas.docEl.innerHTML = documentoHTML(vals, { numero: numero || '' });
    repasaPlegablesDoc();
  }

  /* ---------- Factura / proforma: crear o editar ---------- */
  function abrirEditorFacturaDoc(pre) {
    pre = pre || {};
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      var sb = aut.sb;
      if (!puedeH(aut.ficha, 'facturas')) {
        return aviso('Emitir facturas exige la herramienta «Facturas» — pídesela a un administrador.', '#8A6A34');
      }
      var esEdicion = !!pre.id;
      aseguraModulosDoc(['entities', 'compradores', 'totales', 'dialogo', 'documento']).then(function () {
        return Promise.all([
          cargarSociedades(sb).then(function () { return true; }, function () { return false; }),
          cargarCuentasBancarias(sb).then(function () { return true; }, function () { return false; }),
          listaContratosLigeraDoc(sb),
          esEdicion
            ? sb.from('facturas').select('id,numero,tipo,contrato_id,contrato_numero,client_id,creado_por,anulada,enviada,datos').eq('id', pre.id).maybeSingle()
            : pre.copia_de
              // la anulada pudo emitirla otro del equipo: facturas_equipo, rpc + eq, sin order
              ? sb.rpc('facturas_equipo').select('id,numero,tipo,contrato_id,contrato_numero,client_id,datos').eq('id', pre.copia_de).maybeSingle()
              : Promise.resolve({ data: null })
        ]);
      }).then(function (r) {
        var sociedadesOk = r[0], cuentasOk = r[1];
        var contratos = r[2].data || [];
        var existente = esEdicion ? r[3].data : null;
        if (esEdicion && !existente) return aviso('No se encontró ese documento.', '#93000a');
        var copia = (!esEdicion && pre.copia_de) ? r[3].data : null;
        if (pre.copia_de && !copia) return aviso('No se encontró la factura que quieres copiar.', '#93000a');
        if (esEdicion && !pre.soloLectura) {
          if (existente.tipo === 'proforma') return aviso('La proforma la genera el contrato al guardarse y la actualiza la firma: se consulta, no se edita.', '#8A6A34');
          if (existente.anulada) return aviso('Ese documento está anulado: no se edita — emite una copia desde su ficha.', '#8A6A34');
          if (existente.enviada) return aviso('Ya se envió al cliente: no se edita. Anúlalo y emite otro si hace falta corregirlo.', '#8A6A34');
          var miEmail = ((aut.session && aut.session.user && aut.session.user.email) || '').toLowerCase();
          if (!esAdmin(aut.ficha) && (existente.creado_por || '').toLowerCase() !== miEmail) {
            return aviso('Este documento lo emitió otra persona: solo esa persona o un administrador puede editarlo.', '#8A6A34');
          }
        }
        construye(sociedadesOk, cuentasOk, contratos, existente, copia);
      }, function (e) { aviso('No se ha podido preparar el editor: ' + (e && e.message || e), '#93000a'); });

      /* `copia` («Emitir copia» de una anulada, 22-sep-2026, owner): el
         formulario nace relleno con los datos de aquella —contrato, cliente,
         conceptos— pero como documento NUEVO: sin id, número nuevo al
         guardar y fecha de hoy. Es lo que hacía abrir() del clásico con una
         anulada («se abre como borrador nuevo»). */
      function construye(sociedadesOk, cuentasOk, contratosLigeros, existente, copia) {
        var origen = existente || copia;
        var f0 = Object.assign({}, (origen && origen.datos && origen.datos.fields) || {});
        if (copia) { delete f0.fecha_emision; delete f0.fecha_vencimiento; }
        var lineas0 = (origen && origen.datos && origen.datos.lineas) || [];
        var estadoContrato = {
          id: origen ? origen.contrato_id : (pre.contrato_id || null),
          numero: (origen && origen.contrato_numero) || '',
          clienteId: (origen && origen.client_id) || null
        };
        var getLineas = null;

        var campos = [];
        if (!sociedadesOk) campos.push({ tipo: 'nota', label: 'No se ha podido cargar el catálogo de sociedades — recarga antes de emitir.' });
        if (!cuentasOk) campos.push({ tipo: 'nota', label: 'No se han podido cargar las cuentas de cobro — recarga antes de emitir.' });
        campos.push({ tipo: 'custom', label: 'Formulario', render: function (hostRaiz) {
          /* Calco estructural del clásico (21-sep-2026, ampliado 22-sep con
             el split en vivo): Documento[Contrato → fila Moneda+Nº] →
             Fechas[fila Emisión+Vencimiento] → Emisor plegable → Cliente
             plegable → Conceptos → Impuesto plegado → Notas plegado, en la
             columna izquierda; a la derecha, la factura pintándose en vivo
             con documentoHTML()/documento.css reales — nunca una segunda
             plantilla. Piel del FORMULARIO: tokens CAJ, nunca documento.css;
             la columna derecha es al revés a propósito: el marco es de v4,
             el documento de dentro es el real. */
          var piezas = montaSplitDoc(hostRaiz);
          var host = piezas.colForm;
          function recogeVals() {
            var vals = {};
            piezas.wrap.querySelectorAll('[data-k]').forEach(function (el) {
              vals[el.getAttribute('data-k')] = el.type === 'checkbox' ? el.checked : el.value;
            });
            vals.lineas = getLineas ? getLineas() : [];
            vals.tipo = tipoDocFijo;   // ya no hay selector: factura, salvo al reabrir otra cosa
            // El papel imprime «Contrato · Contract: N» desde d.contrato_numero
            // (documentoHTML). El clásico lo lleva en un input oculto; aquí no
            // hay campo, así que se pone aquí — sin esto la línea no salía.
            vals.contrato_numero = estadoContrato.numero || '';
            return vals;
          }
          var repasaBarra = null, delC = null;
          function repintaPreview() {
            repintaSplitDoc(piezas, recogeVals(), existente ? (existente.numero || '') : '');
            if (repasaBarra) repasaBarra();
            if (delC) delC.marca();
            if (pre.soloLectura) dejaSoloLecturaDoc();
          }
          piezas.wrap.addEventListener('input', repintaPreview);
          piezas.wrap.addEventListener('change', repintaPreview);
          // Los botones de la barra de la previa del clásico (22-sep-2026).
          // Sobre un documento NUEVO todos explican que primero hay que
          // emitir: las acciones reales llegan en el visor que abre «Emitir».
          repasaBarra = montaBarraDoc(piezas, {
            sb: sb, getVals: recogeVals, esRecibi: false,
            principal: pre.soloLectura ? null : document.querySelector('#lw-editor [data-e="guardar"]'),
            saved: existente
              ? { id: existente.id, numero: existente.numero, tipo: existente.tipo, contrato_id: existente.contrato_id, emisor: existente.datos && existente.datos.emisor }
              : { tipo: 'factura' },
            alEnviado: function () { cierraModal(); location.reload(); }
          });

          /* SIN selector de tipo (22-sep-2026, owner: «la proforma es algo
             automático, no deberíamos poder elegirla: solo emitir facturas»).
             Medido en la base: 176 de 187 proformas las crea el generador de
             contratos al guardar un Bloqueo/Construcción («Total del
             proyecto») y la firma las actualiza; una proforma editada a mano
             la pisaría la firma. Aquí solo se emiten facturas; la proforma
             se consulta desde el listado (PDF, email, registro), no se edita
             (abrirEditorFacturaDoc lo corta antes de llegar aquí). */
          var tipoDocFijo = existente ? (existente.tipo || 'factura') : 'factura';

          var secDoc = seccionFijaDoc(host, 'Documento');
          var lblC = document.createElement('div'); lblC.textContent = 'Contrato';
          lblC.style.cssText = 'font-size:12px;color:' + CAJ.apagado;
          var btnC = document.createElement('button'); btnC.type = 'button'; btnC.setAttribute('data-lw-lectura-inerte', '1');
          btnC.style.cssText = 'width:100%;text-align:left;padding:9px 12px;border:1px solid ' + CAJ.borde +
            ';border-radius:8px;font-weight:500;font-size:14px;color:' + CAJ.tinta + ';background-color:' + CAJ.papel + ';cursor:pointer';
          btnC.textContent = estadoContrato.numero ? estadoContrato.numero : '— elige un contrato —';
          var notaC = document.createElement('p'); notaC.style.cssText = 'margin:0;font-size:12px;color:' + CAJ.apagado;
          secDoc.appendChild(lblC); secDoc.appendChild(btnC); secDoc.appendChild(notaC);
          function contratoCargado(id, res) {
            estadoContrato.id = id; estadoContrato.numero = res.numero; estadoContrato.clienteId = res.clienteId;
            btnC.textContent = res.numero + ' · ' + (res.comprador || '—');
            notaC.textContent = '';
            repintaPreview();
            delC.pon(res).then(repintaPreview);
          }
          btnC.addEventListener('click', function () {
            lwElegir({ titulo: 'Elige un contrato', buscarPh: 'Número, comprador o proyecto…', opciones: opcionesContratoPickerDoc(contratosLigeros), valor: estadoContrato.id })
              .then(function (id) {
                if (id === null) return;
                var antes = btnC.textContent; btnC.disabled = true; btnC.textContent = 'Cargando…';
                aplicaContratoDoc(sb, id).then(function (res) {
                  btnC.disabled = false;
                  if (res.error) { toastMal(lwErrorHumano(res.error, 'No se pudo cargar el contrato')); btnC.textContent = antes; return; }
                  contratoCargado(id, res);
                });
              });
          });
          // SOLO para un documento NUEVO (code-review 21-sep): al editar uno ya
          // guardado, `estadoContrato.numero` puede venir vacío si el propio
          // documento nunca trajo `contrato_numero`, y este refresco automático
          // pisaría en silencio los datos ya guardados con lo que diga HOY el
          // contrato. Cambiar el contrato SÍ trae datos — pero solo con un clic.
          /* Con contrato ya conocido —documento guardado que se reabre, o
             proforma que llega desde la ficha del contrato— se carga IGUAL
             que al elegirlo: como abrir() → traerContrato() del clásico, el
             panel de hitos se repinta para ESTE contrato y los campos que
             trae quedan bloqueados (auditoría 19-ago: si no, se quedaba el
             panel del documento anterior). Va al final del render, cuando
             todos los campos ya existen — `poner` escribe en ellos. */
          var contratoInicial = estadoContrato.id;
          var filaDM = filaDosDoc(secDoc);
          campoSimpleDoc(filaDM, { k: 'moneda', label: 'Moneda', tipo: 'select', valor: f0.moneda || 'EUR', opciones: ['EUR', 'USD', 'AUD', 'IDR'] });
          campoSimpleDoc(filaDM, { label: 'Nº de documento', readonly: 1, valor: existente ? (existente.numero || '') : 'Lo asigna la base al guardar' });
          // «Del contrato»: hitos, total, encadenados — DEBAJO de Moneda y Nº,
          // como #delContrato/#delVinculado en el clásico (27-ago-2026, owner:
          // moneda y nº «pegados al contrato, juntos y arriba», el bloque de
          // hitos después). `ctxDelC.lineas` se rellena cuando existen las
          // líneas, que se montan más abajo.
          var ctxDelC = {
            sb: sb, lineas: null, repinta: repintaPreview, esNuevo: !existente, propioId: existente ? existente.id : null,
            tipoActual: function () { return tipoDocFijo; },
            monedaActual: function () { var m = campoDeDoc('moneda'); return m ? m.value : 'EUR'; },
            sociedadActual: function () { var s = campoDeDoc('sociedad'); return s ? s.value : ''; }
          };
          delC = montaDelContratoDoc(secDoc, ctxDelC);

          var secFechas = seccionFijaDoc(host, 'Fechas');
          var filaF = filaDosDoc(secFechas);
          campoSimpleDoc(filaF, { k: 'fecha_emision', label: 'Fecha de emisión', tipo: 'date', valor: f0.fecha_emision || hoyLocalDoc() });
          campoSimpleDoc(filaF, { k: 'fecha_vencimiento', label: 'Vencimiento (opcional)', tipo: 'date', valor: f0.fecha_vencimiento || '' });

          var secEmisor = seccionPlegableDoc(host, 'Emisor', true, { resumen: resumenEmisorDoc });
          campoSimpleDoc(secEmisor, { k: 'sociedad', label: 'Sociedad que factura', tipo: 'select', req: 1, valor: f0.sociedad || '', opciones: [['', '— elige —']].concat(opcionesSociedadDoc()) });
          var selCuenta = campoSimpleDoc(secEmisor, { k: 'cuenta', label: 'Cuenta donde se cobra', tipo: 'select', valor: f0.cuenta || '', opciones: opcionesCuentaDoc() });
          var hintCuenta = document.createElement('p'); hintCuenta.style.cssText = 'margin:0;font-size:11.5px;color:' + CAJ.apagado;
          hintCuenta.textContent = 'Sin cuenta, el documento no imprime datos bancarios.';
          secEmisor.appendChild(hintCuenta);
          // Los datos de «Otros» solo se enseñan con esa cuenta elegida —
          // medido: el clásico los esconde igual (toggleCuentaOtros()).
          var wrapOtros = document.createElement('div'); wrapOtros.style.cssText = 'display:grid;gap:12px';
          secEmisor.appendChild(wrapOtros);
          campoSimpleDoc(wrapOtros, { k: 'banco_titular', label: 'Titular', valor: f0.banco_titular || '' });
          campoSimpleDoc(wrapOtros, { k: 'banco_nombre', label: 'Banco', valor: f0.banco_nombre || '' });
          campoSimpleDoc(wrapOtros, { k: 'banco_cuenta', label: 'Nº de cuenta', valor: f0.banco_cuenta || '' });
          campoSimpleDoc(wrapOtros, { k: 'banco_codigo', label: 'Swift / Routing', valor: f0.banco_codigo || '' });
          campoSimpleDoc(wrapOtros, { k: 'banco_direccion', label: 'Dirección del banco', valor: f0.banco_direccion || '' });
          campoSimpleDoc(wrapOtros, { k: 'banco_extra', label: 'Nota de la cuenta', valor: f0.banco_extra || '' });
          function actualizaOtros() { wrapOtros.style.display = selCuenta.value === 'otros' ? 'grid' : 'none'; }
          selCuenta.addEventListener('change', actualizaOtros); actualizaOtros();

          var secCliente = seccionPlegableDoc(host, 'Cliente', true, { resumen: resumenClienteDoc });
          campoSimpleDoc(secCliente, { k: 'cliente_nombre', label: 'Nombre o razón social', req: 1, valor: f0.cliente_nombre || '' });
          campoSimpleDoc(secCliente, { k: 'cliente_documento', label: 'Pasaporte / NPWP / NIF', valor: f0.cliente_documento || '' });
          campoSimpleDoc(secCliente, { k: 'cliente_email', label: 'Email', tipo: 'email', valor: f0.cliente_email || '' });
          campoSimpleDoc(secCliente, { k: 'proyecto_nombre', label: 'Proyecto / unidad', valor: f0.proyecto_nombre || '', placeholder: 'Ej. Palm Field — Cabana 2BR S2' });

          var secConceptos = seccionFijaDoc(host, 'Conceptos');
          getLineas = montaLineasDoc(secConceptos, lineas0, repintaPreview);
          ctxDelC.lineas = getLineas;

          // Plegados salvo que traigan algo (abrirLoQueTengaContenido del
          // clásico): un dato que está en el papel y no se ve en el
          // formulario es la forma más fácil de reemitir algo sin enterarse.
          var secImp = seccionPlegableDoc(host, 'Impuesto (opcional)', !!(f0.imp_etiqueta || f0.imp_pct));
          campoSimpleDoc(secImp, { k: 'imp_etiqueta', label: 'Impuesto — etiqueta', valor: f0.imp_etiqueta || '', ayuda: 'Ej. PPN' });
          campoSimpleDoc(secImp, { k: 'imp_pct', label: 'Impuesto — porcentaje', valor: f0.imp_pct || '' });

          var secNotas = seccionPlegableDoc(host, 'Notas (opcional)', !!f0.notas);
          campoSimpleDoc(secNotas, { k: 'notas', label: 'Notas', tipo: 'textarea', valor: f0.notas || '' });

          repintaPreview();
          // En modo lectura NO se recarga el contrato: se enseña lo GUARDADO
          // tal cual, no lo que el contrato diga hoy.
          if (contratoInicial && !pre.soloLectura) {
            btnC.textContent = 'Cargando…';
            aplicaContratoDoc(sb, contratoInicial).then(function (res) {
              if (res.error) { btnC.textContent = estadoContrato.numero || '— elige un contrato —'; toastMal(lwErrorHumano(res.error, 'No se pudo cargar el contrato')); return; }
              contratoCargado(contratoInicial, res);
            });
          }
        } });

        modal(pre.soloLectura ? (existente.numero || 'Documento') : existente ? 'Editar ' + (existente.numero || 'documento') : (copia ? 'Nuevo documento — copia de ' + (copia.numero || '') : 'Nuevo documento'), campos,
          existente ? 'Guardar cambios' : 'Emitir', function (v) {
            if (pre.soloLectura) return { error: { message: 'Este documento se abre solo para consultarlo.' } };
            if (!estadoContrato.id) return { error: { message: 'Elige el contrato al que corresponde este documento.' } };
            if (!v.sociedad) return { error: { message: 'Falta «Sociedad que factura».' } };
            if (!v.cliente_nombre) return { error: { message: 'Falta «Nombre o razón social».' } };
            var lineas = getLineas ? getLineas() : [];
            var d = v; d.lineas = lineas;
            d.contrato_numero = estadoContrato.numero || '';   // lo que imprime el papel, como el input oculto del clásico
            var t = calcTotales(lineas, d.moneda, { pct: d.imp_pct });
            if (!t.subtotal) return { error: { message: 'El documento no tiene importe.' } };
            var payload = {
              tipo: d.tipo || 'factura', sociedad: d.sociedad, cliente_nombre: d.cliente_nombre || null,
              proyecto_nombre: d.proyecto_nombre || null, contrato_numero: estadoContrato.numero || null,
              contrato_id: estadoContrato.id, client_id: estadoContrato.clienteId,
              total: t.total, moneda: d.moneda || null, fecha_emision: d.fecha_emision || null,
              justificantes: [], datos: { fields: d, lineas: lineas, totales: t }
            };
            var q = existente
              ? sb.from('facturas').update(payload).eq('id', existente.id).select('id,numero').single()
              : sb.from('facturas').insert(payload).select('id,numero').single();
            return q.then(function (res) {
              if (res.error) return { error: res.error };
              toast((existente ? 'Actualizada como ' : 'Guardada como ') + res.data.numero);
              abreDocumentoViewerDoc(res.data.id, function () { location.reload(); });
              return {};
            });
          /* `ancho:'100vw'` (22-sep-2026, owner): el editor de factura ocupa la
             pantalla entera, como `pantalla('documento')` del clásico — un
             A4 al 78% más un formulario de 400-500px no caben en un cajón de
             1180 sin que la hoja se recorte. El recibí sigue en su cajón. */
          }, { sinRecarga: true, sub: pre.soloLectura ? 'Documento' : (existente ? 'Editar documento' : 'Facturación'), ancho: '100vw', alCerrar: pre.alCerrar });
        if (pre.soloLectura) dejaSoloLecturaDoc();
      }
    });
  }

  /* ---------- Recibí de cobro: crear o editar ---------- */
  function abrirEditorRecibiDoc(pre) {
    pre = pre || {};
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      var sb = aut.sb;
      if (!puedeH(aut.ficha, 'facturas')) {
        return aviso('Emitir recibís exige la herramienta «Facturas» — pídesela a un administrador.', '#8A6A34');
      }
      var esEdicion = !!pre.id;
      aseguraModulosDoc(['entities', 'compradores', 'totales', 'dialogo', 'documento', 'facturasContratos']).then(function () {
        return Promise.all([
          cargarSociedades(sb).then(function () { return true; }, function () { return false; }),
          cargarCuentasBancarias(sb).then(function () { return true; }, function () { return false; }),
          listaContratosLigeraDoc(sb),
          esEdicion
            ? sb.from('facturas').select('id,numero,tipo,contrato_id,contrato_numero,client_id,creado_por,anulada,enviada,datos,justificantes').eq('id', pre.id).eq('tipo', 'recibi').maybeSingle()
            : Promise.resolve({ data: null })
        ]);
      }).then(function (r) {
        var sociedadesOk = r[0], cuentasOk = r[1], contratos = r[2].data || [];
        var existente = esEdicion ? r[3].data : null;
        if (esEdicion && !existente) return aviso('No se encontró ese recibí.', '#93000a');
        if (esEdicion && !pre.soloLectura) {
          if (existente.anulada) return aviso('Ese recibí está anulado: no se edita — se emite uno nuevo.', '#8A6A34');
          if (existente.enviada) return aviso('Ya se envió al cliente: no se edita. Anúlalo y emite otro si hace falta corregirlo.', '#8A6A34');
          var miEmail = ((aut.session && aut.session.user && aut.session.user.email) || '').toLowerCase();
          if (!esAdmin(aut.ficha) && (existente.creado_por || '').toLowerCase() !== miEmail) {
            return aviso('Este recibí lo emitió otra persona: solo esa persona o un administrador puede editarlo (la base lo rechazaría igual).', '#8A6A34');
          }
        }
        construye(sociedadesOk, cuentasOk, contratos, existente);
      }, function (e) { aviso('No se ha podido preparar el editor: ' + (e && e.message || e), '#93000a'); });

      function construye(sociedadesOk, cuentasOk, contratosLigeros, existente) {
        var f0 = (existente && existente.datos && existente.datos.fields) || {};
        var estadoContrato = {
          id: existente ? existente.contrato_id : (pre.contrato_id || null),
          numero: (existente && existente.contrato_numero) || '',
          clienteId: (existente && existente.client_id) || null,
          moneda: f0.moneda || 'EUR',
          clienteNombre: f0.cliente_nombre || '', clienteDocumento: f0.cliente_documento || '',
          clienteEmail: f0.cliente_email || '', proyectoNombre: f0.proyecto_nombre || ''
        };
        var aplicaciones = [];   // [{factura_id, numero, pendiente, importe}]
        var facturasAbiertasCache = [], facturasOtraMoneda = 0, delC = null;
        var getJustificantes = null;
        var repintaAplic = function () {};
        var pintaBtnF = function () {};
        // code-review 21-sep: al EDITAR, la primera carga tiene que RESTAURAR
        // las aplicaciones que el recibí ya tenía en `recibi_aplicaciones` —
        // si no, guardar borra sin darse cuenta el reparto real de un cobro ya
        // registrado (guardar_recibi() hace DELETE+INSERT sobre esa tabla en
        // cada edición). Esta bandera hace que la restauración ocurra UNA vez.
        var aplicacionesRestauradas = false;

        // Facturas pendientes DEL COMPRADOR de estadoContrato.id — solo tiene
        // sentido llamarla una vez ese contrato (y por tanto el comprador) ya
        // se conoce. Mismo camino que cargarFacturasAbiertas() del clásico
        // cuando CONTRATO_ID ya está fijado.
        function cargaAbiertas() {
          if (!estadoContrato.id) return Promise.resolve([]);
          return Promise.all([
            sb.rpc('facturas_equipo').select('id,numero,contrato_id,contrato_numero,cliente_nombre,total,tipo,anulada,moneda'),
            sb.rpc('facturas_pendiente_equipo'),
            sb.rpc('contratos_del_mismo_comprador', { p_contrato_id: estadoContrato.id })
          ]).then(function (rs) {
            if (rs[0].error || rs[1].error || rs[2].error) return [];
            var pend = {}; (rs[1].data || []).forEach(function (x) { pend[x.factura_id] = Number(x.pendiente) || 0; });
            var suyos = {};
            (rs[2].data || []).forEach(function (x) { suyos[(x && typeof x === 'object') ? Object.values(x)[0] : x] = 1; });
            var delComprador = (rs[0].data || [])
              .filter(function (x) { return x.tipo === 'factura' && !x.anulada && (pend[x.id] || 0) > 0.005 && x.contrato_id && suyos[x.contrato_id]; });
            // «no tiene ninguna pendiente» y «tiene, pero en otra moneda» son
            // dos situaciones distintas (FACTURAS_OTRA_MONEDA del clásico)
            facturasOtraMoneda = delComprador.filter(function (x) { return (x.moneda || 'EUR') !== estadoContrato.moneda; }).length;
            return delComprador
              .filter(function (x) { return (x.moneda || 'EUR') === estadoContrato.moneda; })
              .map(function (x) { return { id: x.id, numero: x.numero, contrato_numero: estadoContrato.numero, cliente_nombre: estadoContrato.clienteNombre, pendiente: pend[x.id], moneda: x.moneda }; });
          });
        }

        var campos = [];
        if (!sociedadesOk) campos.push({ tipo: 'nota', label: 'No se ha podido cargar el catálogo de sociedades — recarga antes de emitir.' });
        if (!cuentasOk) campos.push({ tipo: 'nota', label: 'No se han podido cargar las cuentas de cobro — recarga antes de emitir.' });
        campos.push({ tipo: 'custom', label: 'Formulario', render: function (hostRaiz) {
          /* Calco estructural del clásico (21-sep-2026, ampliado 22-sep con
             el split en vivo), medido en modo recibí de /intranet/facturas/
             a 1440 y 390: Documento[«Factura que se cobra» → fila
             Moneda+Nº] → Fechas[fila Emisión+Vencimiento — el clásico la
             enseña igual que en factura, aunque el vencimiento no pinte
             nada en un cobro: se calca tal cual, hallazgo aparte] → Emisor
             plegable → Cliente plegable (visible también en recibí,
             medido) → «Lo que se ha cobrado» → Justificante → Impuesto
             plegado → Notas plegado, en la columna izquierda; a la derecha,
             el recibí pintándose en vivo con el motor real
             (documentoHTML()/documento.css — nunca una segunda plantilla).

             El picker YA NO elige un contrato: elige la FACTURA que se
             cobra, igual que `elegirFacturaDelRecibi()` del clásico — el
             contrato y el comprador se DERIVAN de ella. Antes el editor
             pedía el contrato primero, que es una vía distinta a la medida.
             Piel del formulario: tokens CAJ, nunca documento.css. */
          var piezas = montaSplitDoc(hostRaiz);
          var host = piezas.colForm;
          // Las «líneas» de un recibí, para el motor de render, son las
          // facturas que salda — mismo texto que ya usa onGuardar más abajo
          // («Aplicado a factura X»), no una segunda descripción inventada.
          function lineasDeAplicaciones() {
            return aplicaciones.map(function (a) { return { descripcion: 'Aplicado a factura ' + a.numero, importe: a.importe }; });
          }
          function recogeVals() {
            var vals = {};
            piezas.wrap.querySelectorAll('[data-k]').forEach(function (el) {
              vals[el.getAttribute('data-k')] = el.type === 'checkbox' ? el.checked : el.value;
            });
            vals.lineas = lineasDeAplicaciones();
            vals.cliente_nombre = vals.cliente_nombre || estadoContrato.clienteNombre;
            vals.cliente_documento = vals.cliente_documento || estadoContrato.clienteDocumento;
            vals.cliente_email = vals.cliente_email || estadoContrato.clienteEmail;
            vals.proyecto_nombre = vals.proyecto_nombre || estadoContrato.proyectoNombre;
            vals.contrato_numero = estadoContrato.numero;
            // Sin `tipo` propio en el formulario de recibí (a diferencia de
            // factura, que sí trae el selector): documentoHTML() cae a
            // TIPOS_DOC.factura si no se lo dice, y el papel salía
            // rotulado "Factura" en vez de "Recibí".
            vals.tipo = 'recibi';
            return vals;
          }
          var repasaBarra = null;
          function repintaPreview() {
            repintaSplitDoc(piezas, recogeVals(), existente ? (existente.numero || '') : '');
            if (repasaBarra) repasaBarra();
            if (pre.soloLectura) dejaSoloLecturaDoc();
          }
          piezas.wrap.addEventListener('input', repintaPreview);
          piezas.wrap.addEventListener('change', repintaPreview);
          // Barra de la previa del clásico (22-sep-2026): PDF, email y
          // registro; «Crear recibí» no, que de un recibí no sale otro.
          repasaBarra = montaBarraDoc(piezas, {
            sb: sb, getVals: recogeVals, esRecibi: true,
            principal: pre.soloLectura ? null : document.querySelector('#lw-editor [data-e="guardar"]'),
            saved: existente
              ? { id: existente.id, numero: existente.numero, tipo: 'recibi', contrato_id: existente.contrato_id, emisor: existente.datos && existente.datos.emisor }
              : { tipo: 'recibi' },
            alEnviado: function () { cierraModal(); location.reload(); }
          });

          var secDoc = seccionFijaDoc(host, 'Documento');
          var lblF = document.createElement('div'); lblF.textContent = 'Factura que se cobra';
          lblF.style.cssText = 'font-size:12px;color:' + CAJ.apagado;
          var btnF = document.createElement('button'); btnF.type = 'button'; btnF.setAttribute('data-lw-lectura-inerte', '1');
          btnF.style.cssText = 'width:100%;text-align:left;padding:9px 12px;border:1px solid ' + CAJ.borde +
            ';border-radius:8px;font-weight:500;font-size:14px;color:' + CAJ.tinta + ';background-color:' + CAJ.papel + ';cursor:pointer';
          btnF.textContent = '— elige la factura que cobras —';
          secDoc.appendChild(lblF); secDoc.appendChild(btnF);

          pintaBtnF = function () {
            if (!aplicaciones.length) { btnF.textContent = '— elige la factura que cobras —'; }
            else {
              var f0a = aplicaciones[0];
              btnF.textContent = f0a.numero + (aplicaciones.length > 1 ? ' y ' + (aplicaciones.length - 1) + ' más' : '') +
                (estadoContrato.clienteNombre ? ' — ' + estadoContrato.clienteNombre : '');
            }
            repintaPreview();
          };

          // Aplica una factura YA ELEGIDA: el contrato, el comprador y el
          // pendiente salen de ella — mismo camino que aplicarFacturaAlRecibi().
          function aplicaFactura(f) {
            var cambioContrato = f.contrato_id && f.contrato_id !== estadoContrato.id;
            (cambioContrato ? aplicaContratoDoc(sb, f.contrato_id).then(function (res) {
              if (res.error) { toastMal(lwErrorHumano(res.error, 'No se pudo cargar el contrato de esa factura')); return; }
              estadoContrato.id = f.contrato_id; estadoContrato.numero = res.numero; estadoContrato.clienteId = res.clienteId;
              estadoContrato.moneda = res.moneda || estadoContrato.moneda;
              estadoContrato.clienteNombre = res.clienteNombre; estadoContrato.clienteDocumento = res.clienteDocumento;
              estadoContrato.clienteEmail = res.clienteEmail; estadoContrato.proyectoNombre = res.proyectoNombre;
              if (delC) delC.pon(res);   // «Del contrato»: traído y bloqueado + cuánto lleva cobrado
              var selMoneda = campoDeDoc('moneda'); if (selMoneda) selMoneda.value = estadoContrato.moneda;
            }) : Promise.resolve()).then(function () { return cargaAbiertas(); }).then(function (abs) {
              facturasAbiertasCache = abs;
              aplicaciones.push({ factura_id: f.id, numero: f.numero, pendiente: f.pendiente, importe: '' });
              pintaBtnF(); repintaAplic();
              toast('Factura ' + f.numero + ' — escribe cuánto se ha cobrado');
            });
          }

          function abreBuscador() {
            var yaElegidas = {}; aplicaciones.forEach(function (a) { yaElegidas[a.factura_id] = 1; });
            var fuente = estadoContrato.id ? cargaAbiertas() : cargaTodasAbiertasRecibiDoc(sb, estadoContrato.moneda);
            fuente.then(function (abs) {
              if (estadoContrato.id) facturasAbiertasCache = abs;
              var libres = abs.filter(function (x) { return !yaElegidas[x.id]; });
              if (!libres.length) { toastMal(abs.length ? 'Todas las facturas pendientes ya están en este recibí.' : 'No hay ninguna factura pendiente de cobro.'); return; }
              lwElegir({
                titulo: 'Factura que se cobra', buscarPh: 'Número, comprador o contrato…',
                opciones: libres.map(function (f) {
                  return { valor: f.id, texto: (f.numero || 'sin nº') + ' — ' + (f.cliente_nombre || 'sin nombre'),
                    nota: 'pendiente ' + fmtMoneda(f.pendiente, f.moneda || estadoContrato.moneda) + (f.contrato_numero ? ' · ' + f.contrato_numero : '') };
                })
              }).then(function (id) {
                if (!id) return;
                var f = libres.filter(function (x) { return x.id === id; })[0]; if (!f) return;
                aplicaFactura(f);
              });
            });
          }
          btnF.addEventListener('click', abreBuscador);

          if (existente) {
            // EDITAR: no se pide elegir — se restaura de `recibi_aplicaciones`
            // (código de más abajo, code-review 21-sep) sin vaciar nada antes.
            btnF.textContent = 'Cargando…';
            // En modo lectura se enseña lo GUARDADO: no se recarga el contrato,
            // solo se restauran las facturas que este recibí saldó.
            (pre.soloLectura ? Promise.resolve({ error: null, omitido: true }) : aplicaContratoDoc(sb, estadoContrato.id)).then(function (res) {
              if (!res.error && !res.omitido) {
                estadoContrato.numero = res.numero; estadoContrato.clienteId = res.clienteId;
                estadoContrato.moneda = res.moneda || estadoContrato.moneda;
                estadoContrato.clienteNombre = res.clienteNombre; estadoContrato.clienteDocumento = res.clienteDocumento;
                estadoContrato.clienteEmail = res.clienteEmail; estadoContrato.proyectoNombre = res.proyectoNombre;
              if (delC) delC.pon(res);   // «Del contrato»: traído y bloqueado + cuánto lleva cobrado
              }
              cargaAbiertas().then(function (abs) {
                facturasAbiertasCache = abs;
                aplicacionesRestauradas = true;
                sb.from('recibi_aplicaciones').select('factura_id,importe_aplicado').eq('recibi_id', existente.id)
                  .then(function (rr) {
                    if (rr.error) { toastMal(lwErrorHumano(rr.error, 'No se pudieron traer las facturas que este recibí ya saldaba')); pintaBtnF(); repintaAplic(); return; }
                    (rr.data || []).forEach(function (row) {
                      var abierta = facturasAbiertasCache.filter(function (x) { return x.id === row.factura_id; })[0];
                      aplicaciones.push({
                        factura_id: row.factura_id,
                        numero: abierta ? abierta.numero : row.factura_id,
                        pendiente: (abierta ? abierta.pendiente : 0) + Number(row.importe_aplicado),
                        importe: lwImporteCanonico(Number(row.importe_aplicado))
                      });
                    });
                    pintaBtnF(); repintaAplic();
                  }, function (e) { toastMal(lwErrorHumano(e, 'No se pudieron traer las facturas que este recibí ya saldaba')); pintaBtnF(); repintaAplic(); });
              });
            });
          } else if (pre.contrato_id) {
            // Atajo desde la ficha de un contrato: se precarga sola la lista
            // de pendientes de ese comprador y, si solo hay una, se aplica —
            // es el caso normal (un hito facturado, pendiente de cobro).
            btnF.textContent = 'Cargando…';
            aplicaContratoDoc(sb, estadoContrato.id).then(function (res) {
              if (res.error) { toastMal(lwErrorHumano(res.error, 'No se pudo cargar el contrato')); btnF.textContent = '— elige la factura que cobras —'; return; }
              estadoContrato.numero = res.numero; estadoContrato.clienteId = res.clienteId;
              estadoContrato.moneda = res.moneda || estadoContrato.moneda;
              estadoContrato.clienteNombre = res.clienteNombre; estadoContrato.clienteDocumento = res.clienteDocumento;
              estadoContrato.clienteEmail = res.clienteEmail; estadoContrato.proyectoNombre = res.proyectoNombre;
              if (delC) delC.pon(res);   // «Del contrato»: traído y bloqueado + cuánto lleva cobrado
              var selMoneda = campoDeDoc('moneda'); if (selMoneda) selMoneda.value = estadoContrato.moneda;
              cargaAbiertas().then(function (abs) {
                facturasAbiertasCache = abs;
                // «Crear recibí» desde una factura concreta (22-sep-2026): se
                // aplica ESA, como crearRecibiDesdeFactura() del clásico. Si ya
                // no tiene saldo o está anulada no está entre las abiertas y
                // se dice, en vez de aplicar otra en silencio.
                if (pre.factura_id) {
                  var laFactura = abs.filter(function (x) { return x.id === pre.factura_id; })[0];
                  if (laFactura) { aplicaFactura(laFactura); return; }
                  toastMal('Esa factura ya no tiene saldo pendiente, o está anulada — no hay nada que cobrar en un recibí.');
                }
                if (abs.length === 1) { aplicaFactura(abs[0]); return; }
                pintaBtnF(); repintaAplic();
              });
            });
          }

          var filaDM = filaDosDoc(secDoc);
          var selMonedaR = campoSimpleDoc(filaDM, { k: 'moneda', label: 'Moneda', tipo: 'select', valor: estadoContrato.moneda, opciones: ['EUR', 'USD', 'AUD', 'IDR'] });
          campoSimpleDoc(filaDM, { label: 'Nº de documento', readonly: 1, valor: existente ? (existente.numero || '') : 'Lo asigna la base al guardar' });
          // Cambiar la moneda a mitad refresca qué facturas se pueden saldar y
          // quita las que dejan de valer (refrescarAplicablesDelRecibi del
          // clásico): la base rechaza mezclar monedas (recibi_no_mezcla_moneda).
          selMonedaR.addEventListener('change', function () {
            estadoContrato.moneda = selMonedaR.value || 'EUR';
            if (!estadoContrato.id) return;
            cargaAbiertas().then(function (abs) {
              facturasAbiertasCache = abs;
              var validas = {}; abs.forEach(function (x) { validas[x.id] = 1; });
              var fuera = aplicaciones.filter(function (a) { return !validas[a.factura_id]; });
              if (fuera.length) {
                aplicaciones = aplicaciones.filter(function (a) { return validas[a.factura_id]; });
                toast('Quitad' + (fuera.length === 1 ? 'a ' : 'as ') + fuera.length + ' factura' + (fuera.length === 1 ? '' : 's') +
                  ' que no son de esta moneda: ' + fuera.map(function (a) { return a.numero; }).join(', '));
              }
              pintaBtnF(); repintaAplic();
            });
          });
          // «Del contrato» en su variante de recibí (pintarOpcionesContrato con
          // paraRecibi): qué se trajo y quedó bloqueado, y cuánto lleva cobrado
          // el contrato — sin hitos ni totales, que en un recibí insertaban
          // importes en una sección que nadie ve (27-ago-2026).
          delC = montaDelContratoDoc(secDoc, {
            sb: sb, lineas: null, esRecibi: true, repinta: repintaPreview, esNuevo: !existente, propioId: existente ? existente.id : null,
            tipoActual: function () { return 'recibi'; },
            monedaActual: function () { return estadoContrato.moneda; },
            sociedadActual: function () { var s = campoDeDoc('sociedad'); return s ? s.value : ''; }
          });

          var secFechas = seccionFijaDoc(host, 'Fechas');
          var filaF = filaDosDoc(secFechas);
          campoSimpleDoc(filaF, { k: 'fecha_emision', label: 'Fecha de emisión', tipo: 'date', valor: f0.fecha_emision || hoyLocalDoc() });
          campoSimpleDoc(filaF, { k: 'fecha_vencimiento', label: 'Vencimiento (opcional)', tipo: 'date', valor: f0.fecha_vencimiento || '' });

          var secEmisor = seccionPlegableDoc(host, 'Emisor', true, { resumen: resumenEmisorDoc });
          campoSimpleDoc(secEmisor, { k: 'sociedad', label: 'Sociedad que cobra', tipo: 'select', req: 1, valor: f0.sociedad || '', opciones: [['', '— elige —']].concat(opcionesSociedadDoc()) });
          campoSimpleDoc(secEmisor, { k: 'cuenta', label: 'Cuenta donde se cobró', tipo: 'select', valor: f0.cuenta || '', opciones: opcionesCuentaDoc(true) });
          var hintCuenta = document.createElement('p'); hintCuenta.style.cssText = 'margin:0;font-size:11.5px;color:' + CAJ.apagado;
          hintCuenta.textContent = 'Sin cuenta, el documento no imprime datos bancarios.';
          secEmisor.appendChild(hintCuenta);

          var secCliente = seccionPlegableDoc(host, 'Cliente', true, { resumen: resumenClienteDoc });
          campoSimpleDoc(secCliente, { k: 'cliente_nombre', label: 'Nombre o razón social', valor: estadoContrato.clienteNombre });
          campoSimpleDoc(secCliente, { k: 'cliente_documento', label: 'Pasaporte / NPWP / NIF', valor: estadoContrato.clienteDocumento });
          campoSimpleDoc(secCliente, { k: 'cliente_email', label: 'Email', tipo: 'email', valor: estadoContrato.clienteEmail });
          campoSimpleDoc(secCliente, { k: 'proyecto_nombre', label: 'Proyecto / unidad', valor: estadoContrato.proyectoNombre, placeholder: 'Ej. Palm Field — Cabana 2BR S2' });

          var secAplic = seccionFijaDoc(host, 'Lo que se ha cobrado');
          /* Una TARJETA por factura y el total en una franja (22-sep-2026,
             owner: «la sección queda rara, hazla más clara y legible»). Antes
             era una fila de tres columnas con el número en pequeño, el
             importe sin rótulo y «cobrarlo entero» como enlace subrayado
             debajo del número: no se leía qué era cada cosa. Ahora: número
             grande arriba, «Pendiente de esta factura» debajo, y el importe
             con su rótulo y «Cobrar todo» al lado, que es la mitad barata de
             nacer en blanco (el importe sigue naciendo vacío: 27-ago-2026, el
             caso normal es un cobro parcial). */
          var lista = document.createElement('div'); lista.style.cssText = 'display:grid;gap:8px'; secAplic.appendChild(lista);
          var totalAplic = document.createElement('div');
          totalAplic.style.cssText = 'display:none;justify-content:space-between;align-items:baseline;gap:12px;padding:10px 12px;border-radius:10px;background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde;
          secAplic.appendChild(totalAplic);
          var btnAdd = document.createElement('button'); btnAdd.type = 'button'; btnAdd.textContent = '+ Añadir otra factura';
          btnAdd.style.cssText = 'justify-self:start;padding:7px 12px;border-radius:8px;border:1px dashed ' + CAJ.hoja +
            ';background:transparent;color:' + CAJ.lago + ';font-weight:600;font-size:12.5px;cursor:pointer';
          secAplic.appendChild(btnAdd);
          var avisoAplic = document.createElement('p'); avisoAplic.style.cssText = 'margin:0;font-size:11.5px;line-height:1.5;color:' + CAJ.apagado;
          secAplic.appendChild(avisoAplic);
          function repinta() {
            var usadas = {}; aplicaciones.forEach(function (a) { usadas[a.factura_id] = 1; });
            var libres = facturasAbiertasCache.filter(function (x) { return !usadas[x.id]; });
            btnAdd.hidden = !estadoContrato.id;
            avisoAplic.textContent = !estadoContrato.id ? 'Elige arriba la factura que se cobra.'
              : libres.length ? 'Hay ' + libres.length + ' factura' + (libres.length === 1 ? '' : 's') + ' pendiente' + (libres.length === 1 ? '' : 's') + ' más de este comprador, incluidas las de sus otros contratos.'
              : facturasOtraMoneda ? 'Este comprador tiene ' + facturasOtraMoneda + ' factura' + (facturasOtraMoneda === 1 ? '' : 's') + ' pendiente' + (facturasOtraMoneda === 1 ? '' : 's') + ', pero en otra moneda — un recibí no puede saldar una factura en una moneda distinta a la suya.'
              : 'No le queda ninguna otra factura pendiente a este comprador.';
            var suma = aplicaciones.reduce(function (s, a) { return s + (lwParseImporte(a.importe) || 0); }, 0);
            totalAplic.style.display = aplicaciones.length ? 'flex' : 'none';
            totalAplic.innerHTML = '<span style="font-size:12.5px;font-weight:600;color:' + CAJ.tinta + '">Total del recibí <span style="font-weight:500;color:' + CAJ.apagado + '">· ' +
              aplicaciones.length + ' factura' + (aplicaciones.length === 1 ? '' : 's') + '</span></span>' +
              '<span style="font-size:16px;font-weight:700;letter-spacing:-.01em;font-variant-numeric:tabular-nums;color:' + CAJ.lago + '">' + esc(fmtMoneda(suma, estadoContrato.moneda)) + '</span>';
            lista.innerHTML = '';
            aplicaciones.forEach(function (a, i) {
              var el = document.createElement('div');
              el.style.cssText = 'display:grid;gap:8px;padding:12px 14px;border:1px solid ' + CAJ.borde + ';border-radius:10px;background:' + CAJ.papel;
              var cab = document.createElement('div'); cab.style.cssText = 'display:flex;justify-content:space-between;align-items:flex-start;gap:10px';
              var num = document.createElement('div');
              num.innerHTML = '<div style="font-size:14px;font-weight:700;color:' + CAJ.tinta + ';letter-spacing:-.01em">' + esc(a.numero) + '</div>' +
                '<div style="font-size:12px;color:' + CAJ.apagado + ';margin-top:2px">Pendiente de esta factura: <b style="color:' + CAJ.tinta + ';font-weight:600">' + esc(fmtMoneda(a.pendiente, estadoContrato.moneda)) + '</b></div>';
              var btnDel = document.createElement('button'); btnDel.type = 'button'; btnDel.textContent = '×'; btnDel.title = 'Quitar esta factura del recibí';
              btnDel.style.cssText = 'border:0;background:none;color:#9E2F26;font-size:20px;line-height:1;cursor:pointer;flex:0 0 auto;padding:0 2px';
              cab.appendChild(num); cab.appendChild(btnDel);
              var lbl = document.createElement('div'); lbl.style.cssText = 'font-size:12px;color:' + CAJ.apagado + ';font-weight:500'; lbl.textContent = 'Importe cobrado';
              var fila = document.createElement('div'); fila.style.cssText = 'display:flex;gap:8px;align-items:center;flex-wrap:wrap';
              var inpImp = document.createElement('input'); inpImp.type = 'text'; inpImp.inputMode = 'decimal'; inpImp.placeholder = '¿cuánto ha entrado?';
              inpImp.value = a.importe;
              inpImp.style.cssText = 'flex:1 1 160px;min-width:0;padding:9px 12px;border:1px solid ' + CAJ.borde + ';border-radius:8px;font-size:14px;font-weight:500;color:' + CAJ.tinta + ';background:' + CAJ.papel + ';box-sizing:border-box';
              var pend = document.createElement('button'); pend.type = 'button';
              pend.style.cssText = 'flex:0 0 auto;padding:7px 12px;border-radius:999px;border:1px solid ' + CAJ.lago + ';background:' + CAJ.papel + ';color:' + CAJ.lago + ';font-weight:600;font-size:12px;cursor:pointer;white-space:nowrap';
              pend.textContent = 'Cobrar todo';
              pend.title = 'Pone ' + fmtMoneda(a.pendiente, estadoContrato.moneda) + ', lo que queda pendiente';
              pend.addEventListener('click', function () { a.importe = lwImporteCanonico(a.pendiente); repinta(); });
              inpImp.addEventListener('input', function () { a.importe = inpImp.value; });
              inpImp.addEventListener('blur', function () { var n = lwParseImporte(inpImp.value); var txt = lwImporteCanonico(n); inpImp.value = txt; a.importe = txt; repinta(); });
              btnDel.addEventListener('click', function () { aplicaciones.splice(i, 1); pintaBtnF(); repinta(); });
              fila.appendChild(inpImp); fila.appendChild(pend);
              el.appendChild(cab); el.appendChild(lbl); el.appendChild(fila);
              lista.appendChild(el);
            });
            repintaPreview();
          }
          repintaAplic = repinta;
          btnAdd.addEventListener('click', abreBuscador);
          repinta();

          var secJust = seccionFijaDoc(host, 'Justificante de pago (obligatorio)');
          getJustificantes = montaJustificantesDoc(secJust, sb, existente && Array.isArray(existente.justificantes) ? existente.justificantes : []);

          var secImp = seccionPlegableDoc(host, 'Impuesto (opcional)', false);
          campoSimpleDoc(secImp, { k: 'imp_etiqueta', label: 'Impuesto — etiqueta', valor: f0.imp_etiqueta || '', ayuda: 'Ej. PPN' });
          campoSimpleDoc(secImp, { k: 'imp_pct', label: 'Impuesto — porcentaje', valor: f0.imp_pct || '' });

          var secNotas = seccionPlegableDoc(host, 'Notas (opcional)', false);
          campoSimpleDoc(secNotas, { k: 'notas', label: 'Notas', tipo: 'textarea', valor: f0.notas || '' });

          repintaPreview();
        } });

        modal(pre.soloLectura ? (existente.numero || 'Recibí') : existente ? 'Editar ' + (existente.numero || 'recibí') : 'Emitir recibí de cobro', campos,
          existente ? 'Guardar cambios' : 'Emitir recibí', function (v) {
            if (pre.soloLectura) return { error: { message: 'Este recibí se abre solo para consultarlo.' } };
            if (!estadoContrato.id) return { error: { message: 'Elige la factura que se cobra.' } };
            if (!aplicaciones.length) return { error: { message: 'Elige al menos una factura que salde este recibí.' } };
            if (!v.sociedad) return { error: { message: 'Falta «Sociedad que cobra».' } };
            var justificantes = getJustificantes ? getJustificantes() : [];
            if (!justificantes.length) return { error: { message: 'Adjunta el justificante de pago.' } };
            for (var i = 0; i < aplicaciones.length; i++) {
              var imp = lwParseImporte(aplicaciones[i].importe);
              if (!imp || imp <= 0) return { error: { message: 'Falta el importe aplicado a ' + aplicaciones[i].numero } };
              if (imp > aplicaciones[i].pendiente + 0.01) return { error: { message: aplicaciones[i].numero + ' solo tiene ' + aplicaciones[i].pendiente + ' pendiente' } };
            }
            var lineas = aplicaciones.map(function (a) { return { descripcion: 'Aplicado a factura ' + a.numero, importe: a.importe }; });
            var d = v; d.tipo = 'recibi'; d.lineas = lineas;
            d.cliente_nombre = v.cliente_nombre || estadoContrato.clienteNombre;
            d.cliente_documento = v.cliente_documento || estadoContrato.clienteDocumento;
            d.cliente_email = v.cliente_email || estadoContrato.clienteEmail;
            d.proyecto_nombre = v.proyecto_nombre || estadoContrato.proyectoNombre;
            d.contrato_numero = estadoContrato.numero;
            var t = calcTotales(lineas, d.moneda, {});
            var pFactura = {
              sociedad: d.sociedad, cliente_nombre: d.cliente_nombre || null, proyecto_nombre: d.proyecto_nombre || null,
              contrato_numero: d.contrato_numero || null, contrato_id: estadoContrato.id,
              total: t.total, moneda: d.moneda || null, fecha_emision: d.fecha_emision || null,
              justificantes: justificantes, datos: { fields: d, lineas: lineas, totales: t }
            };
            var pAplicaciones = aplicaciones.map(function (a) { return { factura_id: a.factura_id, importe: lwParseImporte(a.importe) }; });
            return sb.rpc('guardar_recibi', { p_id: (existente && existente.id) || null, p_factura: pFactura, p_aplicaciones: pAplicaciones })
              .then(function (res) {
                if (res.error) return { error: res.error };
                toast((existente ? 'Actualizado como ' : 'Guardado como ') + res.data.numero);
                abreDocumentoViewerDoc(res.data.id, function () { location.reload(); });
                return {};
              });
          // Pantalla entera, como el de factura (owner, 22-sep-2026: «haz lo
          // mismo con el panel de recibís»).
          }, { sinRecarga: true, sub: pre.soloLectura ? 'Recibí' : (existente ? 'Editar recibí' : 'Recibí de cobro'), ancho: '100vw', alCerrar: pre.alCerrar });
        if (pre.soloLectura) dejaSoloLecturaDoc();

        // code-review 21-sep: la Moneda es libre (mismo comprador puede tener
        // contratos en monedas distintas) pero nada volvía a comprobar la
        // lista de facturas si se tocaba DESPUÉS de elegir la factura — se
        // podía elegir una factura en EUR y guardar el recibí en USD. Mismo
        // guardarraíl que `$('#fa-moneda').addEventListener('change', …)` en
        // /intranet/facturas/: cambiar la moneda vacía lo ya elegido (ya no
        // es válido en la divisa nueva).
        var selMonedaWire = campoDeDoc('moneda');
        if (selMonedaWire) {
          selMonedaWire.addEventListener('change', function () {
            estadoContrato.moneda = selMonedaWire.value || 'EUR';
            aplicaciones = [];
            pintaBtnF();
            if (estadoContrato.id) cargaAbiertas().then(function (abs) { facturasAbiertasCache = abs; repintaAplic(); });
            else repintaAplic();
          });
        }
      }
    });
  }

  window.LW_V4 = window.LW_V4 || {};
  window.LW_V4.abreVerDocumento = abreDocumentoViewerDoc;
  window.LW_V4.abrirEditorFactura = abrirEditorFacturaDoc;
  // «Abrir el documento» de la ficha (22-sep-2026, owner: «abrir recibís me
  // lleva a la intranet antigua»): el visor v4 —el papel con PDF, email,
  // recibí y registro—, nunca la navegación a /intranet/facturas/.
  window.LW_V4.verDocumento = abreDocumentoViewerDoc;
  window.LW_V4.abrirEditorRecibi = abrirEditorRecibiDoc;
  /* Exportado (S14, 21-sep-2026): datos.js -- otra IIFE, otro cierre -- necesita
     el MISMO chequeo de «0 filas = la policy lo denegó» para anular/borrar desde
     la ficha en cajón. Reescribirlo allí a mano es la reincidencia que esto
     existe para evitar (reference_supabase_grant_manda_antes_que_la_policy). */
  window.LW_V4.unaFila = unaFila;

  /* ---------- editores por pantalla ---------- */
  var ED = {

    modelos: function (aut) {
      var sb = aut.sb, admin = esAdmin(aut.ficha);
      var soloAdmin = function () { aviso('La familia de modelos la escribe solo administración (policy es_admin) — tu sesión es de ' + ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34'); };
      var SLUG_VALIDO = /^[a-z0-9-]+$/;
      ata(/^\+? ?Nuevo modelo$/i, function () {
        if (!admin) return soloAdmin();
        modal('Nuevo modelo', [
          { k: 'nombre', label: 'Nombre', req: 1 },
          { k: 'slug', label: 'Slug', ayuda: 'vacío = se genera del nombre; es la URL pública /modelo/<slug> — solo minúsculas, números y guiones' },
          { k: 'moneda', label: 'Moneda', tipo: 'select', opciones: ['EUR', 'IDR'], valor: 'EUR' },
          { k: 'precio', label: 'Precio de construcción', tipo: 'number', paso: '0.01', ayuda: 'se puede dejar vacío y ponerlo al completar la ficha' }
        ], 'Crear modelo', function (v) {
          var slug = (v.slug || '').trim().toLowerCase() || slugDe(v.nombre);
          /* Validación de FORMATO (S12, 22-sep-2026): la `unique` de la base
             ya impide un slug duplicado de verdad — esto es solo para no
             dejar pasar lo que la base va a rechazar igual, y para traducir
             el 23505 crudo de Postgres al mismo aviso amable que la clásica
             (intranet/modelos/index.html:928), en vez de dejarlo pasar tal
             cual. */
          if (!SLUG_VALIDO.test(slug)) {
            return { error: { message: 'el slug solo admite minúsculas, números y guiones' } };
          }
          return sb.from('modelos').insert({
            nombre: v.nombre, slug: slug, moneda: v.moneda,
            precio_construccion: v.precio === '' ? null : Number(v.precio),
            activo: true, publicado: false
          }).then(function (r) {
            var msg = (r.error && r.error.message) || '';
            if (r.error && /duplicate key|unique constraint/i.test(msg) && /slug/i.test(msg)) {
              return { error: { message: 'Ya hay un modelo en esa dirección (' + slug + ') — elige otra.' } };
            }
            return r;
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
          // `moneda` en el SELECT (S12, 22-sep-2026, regresión corregida): sin
          // ella una fila de extra escrita desde aquí quedaba sin moneda —
          // modelo_extras.moneda existe y la clásica ya la lee y la escribe
          // (intranet/modelos/index.html:651-652).
          sb.from('modelo_extras').select('id,extra_id,precio,moneda,disponible').eq('modelo_id', m.id),
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
            /* Nombre/slug/moneda (S12, 22-sep-2026): antes no estaban en este
               modal. Mismo orden que la clásica (intranet/modelos/index.html:
               608-620): ficha primero, specs después. */
            { k: 'nombre', label: 'Nombre', req: 1, valor: m.nombre, medio: 1 },
            { k: 'slug', label: 'Slug', req: 1, valor: m.slug, medio: 1, ayuda: '/modelo/<slug> — solo minúsculas, números y guiones; cambiarlo rompe los enlaces ya publicados' },
            { k: 'moneda', label: 'Moneda', tipo: 'select', opciones: ['EUR', 'IDR'], valor: m.moneda || 'EUR', medio: 1 },
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

            var nombreNuevo = (v.nombre || '').trim();
            var slugNuevo = (v.slug || '').trim().toLowerCase();
            var monedaNueva = v.moneda || m.moneda || 'EUR';
            if (!nombreNuevo) return Promise.resolve({ error: { message: 'el nombre no puede quedar vacío' } });
            if (!SLUG_VALIDO.test(slugNuevo)) return Promise.resolve({ error: { message: 'el slug solo admite minúsculas, números y guiones' } });

            // Valores de ANTES de este guardado — si la ficha se actualiza pero
            // alguna sub-tabla falla, se restauran para no dejar la ficha a
            // medias mientras el aviso dice «no se pudo guardar» (mismo
            // espíritu que «Nueva condición» borrando la fila huérfana cuando
            // fallan sus tramos, más arriba en este mismo fichero).
            var previo = {
              nombre: m.nombre, slug: m.slug, moneda: m.moneda,
              dormitorios: m.dormitorios, banos: m.banos, villa_m2: m.villa_m2, terraza_m2: m.terraza_m2,
              precio_construccion: m.precio_construccion, descripcion: m.descripcion, notas: m.notas,
              alcance: m.alcance, publicado: m.publicado, renders_pendientes: m.renders_pendientes, activo: m.activo
            };

            /* Renombrar (S12, 22-sep-2026): `trg_modelo_renombrado` (AFTER
               UPDATE OF nombre) propaga el nombre nuevo a `unidades.modelo` y
               `modelos_villa.modelo` — el aviso PREVIO dice a cuántas filas,
               mismo criterio que la clásica (intranet/modelos/index.html:
               596-608): «se avisa de cuántas filas se van a mover ANTES».
               Nunca se pregunta si el nombre no cambia. */
            var pasoRenombrar = (nombreNuevo === m.nombre)
              ? Promise.resolve(true)
              : aseguraModulosDoc(['dialogo']).then(function () {
                  return Promise.all([
                    sb.from('unidades').select('id', { count: 'exact', head: true }).eq('modelo_id', m.id),
                    sb.from('modelos_villa').select('id', { count: 'exact', head: true }).eq('modelo_id', m.id)
                  ]);
                }).then(function (rs) {
                  var falloConteo = (rs[0] && rs[0].error) || (rs[1] && rs[1].error);
                  if (falloConteo) {
                    // Hallazgo de la autorevisión (22-sep-2026): sin este
                    // chequeo, un conteo fallido caía a 0 en silencio y el
                    // aviso decía «ninguna fila todavía» aunque el rename SÍ
                    // fuera a mover filas — mentir en el aviso previo es peor
                    // que no preguntar. Se para aquí, antes de confirmar nada.
                    return Promise.reject(new Error('no se ha podido calcular a cuántas filas afecta el renombrado: ' + falloConteo.message));
                  }
                  var nUd = (rs[0] && rs[0].count) || 0, nMv = (rs[1] && rs[1].count) || 0;
                  var radio = [nUd ? nUd + ' unidad(es)' : '', nMv ? nMv + ' precio(s) por proyecto' : ''].filter(Boolean).join(' y ');
                  return lwConfirmar({
                    titulo: 'Renombrar «' + m.nombre + '» a «' + nombreNuevo + '»',
                    cuerpo: '<p>El nombre nuevo se propaga solo a <b>' + (radio || 'ninguna fila todavía') +
                      '</b>. Lo ya impreso en un documento firmado no se toca.</p>',
                    confirmar: 'Renombrar'
                  });
                });

            return pasoRenombrar.then(function (ok) {
              if (!ok) return { error: { message: 'Cancelado: el modelo conserva su nombre.' } };
              // `.select('id')` + `verifica()` (hallazgo de la autorevisión, 22-sep-2026;
              // corregido tras probarlo en el navegador real — `unaFila()` espera un
              // resultado YA resuelto, no una promesa; `verifica()` es la que envuelve
              // la consulta, mismo patrón que ya usa `abrirPrevisionDeck()` más abajo):
              // sin esto un UPDATE denegado por RLS con 0 filas se leía como éxito. De
              // paso, parar AQUÍ si la ficha no se guardó deja de tocar las sub-tablas —
              // el rollback de `previo` de abajo ya no hace falta para esta rama, solo
              // para cuando la ficha SÍ se guarda pero una sub-tabla falla después.
              return verifica(sb.from('modelos').update({
                nombre: nombreNuevo, slug: slugNuevo, moneda: monedaNueva,
                dormitorios: v.dormitorios === '' ? null : Number(v.dormitorios),
                banos: v.banos === '' ? null : Number(v.banos),
                villa_m2: v.villa_m2 === '' ? null : Number(v.villa_m2),
                terraza_m2: v.terraza_m2 === '' ? null : Number(v.terraza_m2),
                precio_construccion: v.precio === '' ? null : Number(v.precio),
                descripcion: v.descripcion || null,
                notas: v.notas || null,
                alcance: alcance,
                publicado: v.publicado, renders_pendientes: v.renders_pendientes, activo: v.activo,
                actualizado_en: new Date().toISOString()
              }).eq('id', m.id).select('id'), 'No se ha guardado la ficha del modelo').then(function (r0) {
                if (r0.error) {
                  var msg = r0.error.message || '';
                  if (/duplicate key|unique constraint/i.test(msg) && /slug/i.test(msg)) {
                    return { error: { message: 'Ya hay un modelo en esa dirección (' + slugNuevo + ') — elige otra.' } };
                  }
                  return r0;
                }
                var tareas = [];
                (getTechos ? getTechos() : []).forEach(function (t) {
                  tareas.push(verifica(sb.from('modelo_techos').update({ precio_ahora: t.precio_ahora, precio_2027: t.precio_2027 }).eq('id', t.id).select('id'), 'No se ha guardado un techo'));
                });
                (getExtras ? getExtras() : []).forEach(function (e) {
                  if (e.existenteId) {
                    tareas.push(verifica(sb.from('modelo_extras').update({ precio: e.precio, moneda: monedaNueva, disponible: e.disponible }).eq('id', e.existenteId).select('id'), 'No se ha guardado un extra'));
                  } else if (e.precio != null || !e.disponible) {
                    // sin fila = «se ofrece, precio de catálogo» (montaExtrasModelo); solo se
                    // crea fila cuando hay algo que decir que el default no cubre.
                    // `moneda` (S12, 22-sep-2026): regresión corregida — sin ella una fila
                    // nueva de modelo_extras quedaba sin moneda (default 'EUR' de la base,
                    // que miente si el modelo es IDR).
                    tareas.push(verifica(sb.from('modelo_extras').insert({ modelo_id: m.id, extra_id: e.extraId, precio: e.precio, moneda: monedaNueva, disponible: e.disponible }).select('id'), 'No se ha guardado un extra'));
                  }
                });
                var precios = getPrecios ? getPrecios() : { filas: [], nuevoProyecto: '' };
                precios.filas.forEach(function (f) {
                  tareas.push(verifica(sb.from('modelos_villa').update({ precio_construccion: f.precio }).eq('id', f.id).select('id'), 'No se ha guardado el precio por proyecto'));
                });
                if (precios.nuevoProyecto) {
                  // solo `modelo_id`: trg_espejo_modelo rellena el texto `modelo` espejo
                  // antes del INSERT (dispara en todo INSERT, la lista de columnas del
                  // trigger solo acota los UPDATE — verificado contra la migración).
                  tareas.push(verifica(sb.from('modelos_villa').insert({
                    proyecto: precios.nuevoProyecto, proyecto_id: idPorProyecto[precios.nuevoProyecto] || null,
                    modelo_id: m.id, precio_construccion: null, moneda: monedaNueva
                  }).select('id'), 'No se ha guardado el precio por proyecto'));
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
          });
        }, function (e) {
          cargandoFichaModelo = false;
          aviso('No se pudo abrir «Editar datos»: ' + (e && e.message || e), '#93000a');
        });
      });
      /* Subir/descargar documento (S12, 22-sep-2026): antes esta pantalla
         solo LEÍA `modelo_documentos` (datos.js) y el botón redirigía a la
         clásica «porque hace falta el bucket». El bucket ya existe
         (`modelos`, privado, migración 20260907053801) y la policy de
         escritura es `es_agente()` — mismo patrón de subida que `subirDoc()`
         de intranet/modelos/index.html: recodificar NO hace falta aquí (no
         es una imagen del deck), solo subir el fichero tal cual y anotar la
         fila; si la fila falla, el fichero huérfano se retira. */
      ata(/^Añadir documento$/i, function () {
        var m = window.LW_V4 && window.LW_V4.modelo;
        if (!m) return aviso('La ficha del modelo aún no ha cargado.', '#8A6A34');
        modal('Añadir documento · ' + m.nombre, [
          { k: 'tipo', label: 'Tipo', tipo: 'select', opciones: [
              ['plano', 'Plano · anexo del contrato'], ['calidades', 'Memoria de calidades'],
              ['ficha', 'Ficha'], ['render', 'Render'], ['otro', 'Otro']
            ], valor: 'otro' },
          { k: 'file', label: 'Fichero', tipo: 'file', req: 1, accept: 'application/pdf,image/jpeg,image/png,image/webp',
            ayuda: 'PDF o imagen, hasta 50 MB. Nace privado; el de tipo «plano» es el que el contrato de Construcción adjunta al elegir este modelo.' }
        ], 'Subir', function (v) {
          var file = v.file;
          if (!file) return { error: { message: 'elige un fichero' } };
          if (file.size > 52428800) return { error: { message: 'el fichero pasa de 50 MB' } };
          var ext = (file.name.match(/\.[a-z0-9]+$/i) || [''])[0].toLowerCase();
          var path = m.id + '/' + crypto.randomUUID() + ext;
          return sb.storage.from('modelos').upload(path, file, { contentType: file.type || undefined }).then(function (up) {
            if (up.error) return { error: up.error };
            return sb.from('modelo_documentos').insert({
              modelo_id: m.id, nombre: file.name, path: path, tipo: v.tipo || 'otro', tamano_bytes: file.size,
              // `subido_por` (hallazgo de la autorevisión, 22-sep-2026): la clásica lo manda
              // (YO.id) — sin él, la columna (nullable) se queda sin quién subió el fichero.
              subido_por: (aut.session && aut.session.user && aut.session.user.id) || null
            }).then(function (r) {
              if (r.error) {
                // fichero huérfano en el bucket sin fila: se retira, igual que
                // subirDoc() en /intranet/modelos/ — un objeto sin fila no lo
                // ve nadie y no lo borra nadie.
                // LÍMITE CONOCIDO (hallazgo de la autorevisión, 22-sep-2026,
                // ya presente en subirDoc() de la clásica, no una regresión
                // de aquí): «modelos bucket: subir» es es_agente() pero
                // «modelos bucket: borrar» es es_admin() — un agente no-admin
                // cuyo INSERT falle no puede limpiar su propio huérfano; el
                // remove() se deniega en silencio y el fichero se queda en el
                // bucket PRIVADO (no expuesto, solo desaprovechando espacio).
                // Arreglarlo de raíz es tocar la policy de borrado, fuera del
                // alcance de esta pantalla.
                sb.storage.from('modelos').remove([path]);
              }
              return r;
            });
          });
        });
      });

      /* Fotos del Investor Deck (S12, 22-sep-2026): pieza COMPARTIDA de la
         suite (contracts/assets/deck_fotos.js, Regla 0) — ya la usan
         /proyectos/ y /modelos/ clásicos, y v4/proyectos/ desde S10.2; se
         engancha TAL CUAL para v4/modelos/, nunca se reescribe. */
      ata(/^Fotos del deck$/i, function () {
        var m = window.LW_V4 && window.LW_V4.modelo;
        if (!m) return aviso('La ficha del modelo aún no ha cargado.', '#8A6A34');
        aseguraModulosDoc(['dialogo', 'deckFotos']).then(function () {
          if (!window.lwDeckFotos) return aviso('No se ha podido cargar el gestor de fotos del deck.', '#ba1a1a');
          window.lwDeckFotos.abrir({
            SB: sb, ambito: 'modelo', modeloId: m.id, esAdmin: admin,
            titulo: 'Fotos públicas del deck', sub: m.nombre
          });
        }, function (e) { aviso('No se ha podido cargar el gestor de fotos del deck: ' + (e && e.message || e), '#ba1a1a'); });
      });

      /* Abrir un documento subido (S12, 22-sep-2026): mismo patrón que S11.2
         (`wireDocumentosAbrir`, Documentación de Proyectos) — createSignedUrl
         de vida corta, TTL 300s, delegado en el contenedor ESTÁTICO porque
         datos.js reemplaza sus filas (clona/renderiza) en cada carga de la
         ficha — un listener por fila se perdería al abrir el siguiente
         modelo. */
      (function wireDocumentosAbrirModelo() {
        var caja = document.getElementById('d-docs');
        if (!caja) return;
        caja.addEventListener('click', function (ev) {
          var f = ev.target.closest && ev.target.closest('[data-doc-abrir]');
          if (!f) return;
          var path = f.getAttribute('data-doc-path');
          if (!path) return;
          var meta = f.querySelector('[data-lw="doc-meta"]');
          var metaOrig = meta ? meta.textContent : '';
          if (meta) meta.textContent = 'Abriendo…';
          sb.storage.from('modelos').createSignedUrl(path, 300).then(function (u) {
            if (meta) meta.textContent = metaOrig;
            if (u.error || !u.data) { aviso('No se pudo abrir: ' + (u.error && u.error.message || 'sin URL'), '#ba1a1a'); return; }
            window.open(u.data.signedUrl, '_blank', 'noopener');
          });
        });
      })();

      /* Previsión del deck (S12, 22-sep-2026): editor de `deck_forecast`
         (por par proyecto+modelo) y `deck_forecast_proyecto` (gastos, por
         proyecto). Botón por fila en «Unidades que lo usan», delegado en
         `#d-proyectos` por el mismo motivo que el de arriba — datos.js
         reconstruye esas filas en cada apertura. Solo admin: mismo gate que
         el resto de esta pantalla, y es_admin() manda igual en la RLS. */
      (function wireForecastModelo() {
        var caja = document.getElementById('d-proyectos');
        if (!caja) return;
        caja.addEventListener('click', function (ev) {
          var f = ev.target.closest && ev.target.closest('[data-forecast-proyecto]');
          if (!f) return;
          ev.stopPropagation();
          var fila = f.closest('[data-proyecto-fila]');
          var proyectoNombre = fila && fila.getAttribute('data-proyecto-nombre');
          var proyectoId = fila && fila.getAttribute('data-proyecto-id');
          if (!admin) return soloAdmin();
          var m = window.LW_V4 && window.LW_V4.modelo;
          if (!m || !proyectoNombre || !proyectoId) return aviso('Este proyecto aún no ha cargado.', '#8A6A34');
          abrirPrevisionDeck(m, proyectoNombre, proyectoId);
        });
      })();

      /* La previsión del deck (Year-1 Rental Forecast) NO es cosmética:
         `deck_forecast_ejemplo_publico()` la expone a un inversor externo en
         el siguiente fetch (caché 5 min, allowlist fija de 3 pares, decisión
         del owner 21-sep-2026 — esa allowlist no se toca aquí). Por eso lleva
         la MISMA doble validación numérica que la clásica
         (intranet/modelos/index.html:389-479): el CHECK de la base es el
         tirante, esto es el cinturón — evita ofrecer lo que va a fallar al
         guardar, y dice CUÁL es el motivo.

         DEJADO FUERA A PROPÓSITO (LAW-273, contexto/pendientes.md): el aviso
         de desfase de la clásica (inversión base vs. construcción + parcela
         más barata del proyecto, `unidad_referencia_id`) no se porta aquí —
         el alcance de esta pasada era la doble validación, no el detector de
         envejecimiento. `unidad_referencia_id` no viaja en el payload. */
      function abrirPrevisionDeck(m, proyectoNombre, proyectoId) {
        Promise.all([
          sb.from('deck_forecast').select('adr_medio,adr_optimo,ocupacion_media,ocupacion_optima,inversion_base,destacado,publicado').eq('proyecto_id', proyectoId).eq('modelo_id', m.id).maybeSingle(),
          sb.from('deck_forecast_proyecto').select('pct_gestion,pct_mantenimiento,pct_impuesto,contrato_vigente,publicado').eq('proyecto_id', proyectoId).maybeSingle()
        ]).then(function (rs) {
          var falloLectura = rs.filter(function (x) { return x && x.error; })[0];
          if (falloLectura) return aviso('No se pudo abrir la previsión: ' + falloLectura.error.message, '#ba1a1a');
          var f = (rs[0] && rs[0].data) || {};
          var cfg = (rs[1] && rs[1].data) || {};
          var pct = function (val, def) { return val == null ? def : Math.round(val * 1000) / 10; };
          modal('Previsión del deck', [
            { k: 'adr_medio', label: 'Precio medio/noche · escenario medio (€)', tipo: 'number', paso: '0.01', valor: f.adr_medio, medio: 1 },
            { k: 'adr_optimo', label: 'Precio medio/noche · óptimo (€)', tipo: 'number', paso: '0.01', valor: f.adr_optimo, medio: 1 },
            { k: 'ocupacion_media', label: 'Ocupación media (%)', tipo: 'number', paso: '0.1', valor: pct(f.ocupacion_media, ''), medio: 1 },
            { k: 'ocupacion_optima', label: 'Ocupación óptima (%)', tipo: 'number', paso: '0.1', valor: pct(f.ocupacion_optima, ''), medio: 1 },
            { k: 'inversion_base', label: 'Inversión total, base del ROI (€)', tipo: 'number', paso: '0.01', valor: f.inversion_base,
              ayuda: 'explícita, no derivada — si es un precio de paquete pactado, que sea a propósito' },
            { k: 'destacado', label: 'Marcar como «El más solicitado» en el deck', tipo: 'check', valor: !!f.destacado },
            { k: 'publicado', label: 'Publicar en el deck público', tipo: 'check', valor: !!f.publicado, ayuda: 'sin esta casilla el modelo no sale en el forecast — nace apagada a propósito' },
            { tipo: 'nota', label: 'Gastos de «' + proyectoNombre + '»: son del CONTRATO de gestión de alquiler, no de este modelo — cambiarlos mueve la tarjeta de TODOS los modelos de este proyecto.' },
            { k: 'pct_gestion', label: 'Gestión (%)', tipo: 'number', paso: '0.1', valor: pct(cfg.pct_gestion, 20), medio: 1 },
            { k: 'pct_mantenimiento', label: 'Mantenimiento (%)', tipo: 'number', paso: '0.1', valor: pct(cfg.pct_mantenimiento, 5), medio: 1 },
            { k: 'pct_impuesto', label: 'Impuesto de alquiler (%)', tipo: 'number', paso: '0.1', valor: pct(cfg.pct_impuesto, 10), medio: 1 },
            { k: 'contrato_vigente', label: 'Contrato de gestión que los fija', valor: cfg.contrato_vigente, medio: 1, ayuda: 'ej. CG-2026-01' },
            { k: 'publicado_proyecto', label: 'Publicar el forecast de este proyecto', tipo: 'check', valor: !!cfg.publicado, ayuda: 'si se apaga, el deck de este proyecto se queda sin bloque de previsión entero' }
          ], 'Guardar', function (v) {
            var num = function (s) { var t = String(s == null ? '' : s).trim().replace(',', '.'); return t === '' ? null : Number(t); };
            var frac = function (s) { var n = num(s); return n == null ? null : n / 100; };
            var fila = {
              proyecto_id: proyectoId, modelo_id: m.id,
              adr_medio: num(v.adr_medio), adr_optimo: num(v.adr_optimo),
              ocupacion_media: frac(v.ocupacion_media), ocupacion_optima: frac(v.ocupacion_optima),
              inversion_base: num(v.inversion_base),
              destacado: v.destacado, publicado: v.publicado,
              actualizado_en: new Date().toISOString()
            };
            for (var i = 0, camposNum = [['adr_medio', 'el precio medio/noche'], ['adr_optimo', 'el precio óptimo'],
                 ['ocupacion_media', 'la ocupación media'], ['ocupacion_optima', 'la ocupación óptima'],
                 ['inversion_base', 'la inversión base']]; i < camposNum.length; i++) {
              var k = camposNum[i][0];
              if (fila[k] == null || !(fila[k] > 0)) return { error: { message: 'Falta o no es válido: ' + camposNum[i][1] } };
            }
            if (fila.ocupacion_media > 1 || fila.ocupacion_optima > 1) {
              return { error: { message: 'La ocupación es un porcentaje: no puede pasar de 100.' } };
            }
            var cf = {
              proyecto_id: proyectoId,
              pct_gestion: frac(v.pct_gestion), pct_mantenimiento: frac(v.pct_mantenimiento), pct_impuesto: frac(v.pct_impuesto),
              contrato_vigente: (v.contrato_vigente || '').trim() || null,
              publicado: v.publicado_proyecto,
              actualizado_en: new Date().toISOString()
            };
            for (var j = 0, clavesPct = ['pct_gestion', 'pct_mantenimiento', 'pct_impuesto']; j < clavesPct.length; j++) {
              var kk = clavesPct[j];
              if (cf[kk] == null || cf[kk] < 0 || cf[kk] > 1) return { error: { message: 'Los porcentajes van entre 0 y 100.' } };
            }
            if (cf.pct_gestion + cf.pct_mantenimiento + cf.pct_impuesto >= 1) {
              return { error: { message: 'Los tres porcentajes juntos se comen el ingreso entero: el neto saldría negativo.' } };
            }
            // `verifica()` da un mensaje de RLS escrito para sus llamadas de
            // siempre («el gate es la policy es_super_admin») — deck_forecast
            // y deck_forecast_proyecto los escribe cualquier es_admin(), no
            // solo super_admin (hallazgo de la autorevisión, 22-sep-2026): se
            // corrige el texto aquí para no mandar a un admin real a buscar
            // un permiso que ya tiene.
            var verificaAdmin = function (p, queNoPaso) {
              return verifica(p, queNoPaso).then(function (r) {
                if (r && r.error && r.error.message) {
                  r.error.message = r.error.message.replace('es_super_admin', 'es_admin');
                }
                return r;
              });
            };
            return verificaAdmin(sb.from('deck_forecast').upsert(fila, { onConflict: 'proyecto_id,modelo_id' }).select('id'), 'No se ha guardado la previsión').then(function (r1) {
              if (r1.error) return r1;
              return verificaAdmin(sb.from('deck_forecast_proyecto').upsert(cf, { onConflict: 'proyecto_id' }).select('proyecto_id'), 'La previsión sí, los gastos del proyecto no');
            });
          }, { sub: m.nombre + ' · ' + proyectoNombre });
        }, function (e) { aviso('No se pudo abrir la previsión: ' + (e && e.message || e), '#ba1a1a'); });
      }
    },

    /* Comisiones (antes «Solicitudes», renombrada 14-sep-2026).
       «Reparto de equipo»: solo «Marcar pagada» (UPDATE directo sobre
       `comisiones_devengadas`, policy = manager del equipo o admin).
       «A Lawang» (S8, 22-sep-2026, paridad con /intranet/solicitudes/): TODAS
       las transiciones van por UPDATE directo sobre `solicitudes_pago` — el
       unico candado real es el trigger `trg_solicitud_pago_transicion`
       (BEFORE UPDATE): pendiente→aprobada/rechazada exige es_admin(),
       pendiente→anulada exige creado_por=auth.uid(), aprobada→pagada exige
       es_admin(); cualquier otro salto lanza 22023. El motivo obligatorio en
       rechazo es un CHECK aparte (`solicitud_rechazo_con_motivo`), tambien
       server-side — aqui solo se refleja con `req:1`, nunca se ensancha nada.
       Sin RPC ni edge: el INSERT/UPDATE directo ya esta cubierto por la RLS
       real (revision previa #37, Seguridad VERDE). */
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

      /* ---------- alta / edición nativa (S8) ----------
         Misma funcion para las dos: `existente` trae la fila a editar, o es
         null/undefined para un alta. `beneficiario_email`/`origen`/
         `creado_por` NUNCA viajan en el payload — los fuerza el trigger de
         alta (`_trg_solicitud_pago_alta`), forzarlos aqui seria pisar lo que
         ya decide la base. Moneda: SOLO EUR/USD/IDR (`solicitud_moneda_valida`
         — correccion #4, NO las 4 de Parcelas/S1: con AUD el INSERT lo
         rechaza). */
      window.LW_V4.abreAltaSolicitud = function (existente) {
        var x = existente || {};
        sb.from('contratos').select('id,numero,tipo,proyecto_nombre').then(function (rc) {
          if (rc.error) aviso('No se pudo cargar el listado de contratos: se ofrece sin selector de venta.', '#8A6A34');
          var contratos = rc.error ? [] : (rc.data || []);
          var opsContratos = [['', '— sin venta asociada —']].concat(
            contratos.slice().sort(function (a, b) { return (a.numero || '').localeCompare(b.numero || '', 'es'); })
              .map(function (c) { return [c.id, (c.numero || 'sin nº') + (c.proyecto_nombre ? ' — ' + c.proyecto_nombre : '')]; }));
          modal(existente ? 'Editar SP-' + existente.numero : 'Nueva solicitud de pago', [
            { k: 'concepto', label: 'Concepto — qué pago estás pidiendo', req: 1, valor: x.concepto || '' },
            { k: 'importe', label: 'Importe', tipo: 'number', paso: '0.01', req: 1, medio: 1, valor: x.importe != null ? x.importe : '' },
            { k: 'moneda', label: 'Moneda', tipo: 'select', medio: 1, opciones: ['EUR', 'USD', 'IDR'], valor: x.moneda || 'EUR' },
            { k: 'contrato_id', label: 'De qué venta viene, si viene de una', tipo: 'select', valor: x.contrato_id || '', opciones: opsContratos },
            { k: 'vence_el', label: 'Fecha límite', tipo: 'date', valor: x.vence_el || '' },
            { k: 'nota', label: 'Nota para Administración', tipo: 'textarea', valor: x.nota || '' }
          ], existente ? 'Guardar cambios' : 'Crear solicitud', function (v) {
            var importe = Number(String(v.importe).replace(',', '.'));
            if (!(importe > 0)) return { error: { message: 'el importe no se entiende — escribe un número mayor que cero' } };
            var fila = {
              concepto: v.concepto.trim(), importe: importe, moneda: v.moneda,
              contrato_id: v.contrato_id || null,
              vence_el: v.vence_el || null,
              nota: v.nota.trim() || null
            };
            return (existente
              ? sb.from('solicitudes_pago').update(fila).eq('id', existente.id)
              : sb.from('solicitudes_pago').insert(fila)
            ).select('id').then(unaFila);
          });
        });
      };

      /* ---------- aprobar / rechazar / anular / marcar pagada ----------
         Cada una es un UPDATE directo de estado; el trigger decide si cuaja.
         `.select('id')` + unaFila: la policy filtra sin dar error, 0 filas
         seria un «guardado» mentiroso sobre nada. */
      function resolverSolicitud(x, cambio) {
        return sb.from('solicitudes_pago').update(cambio).eq('id', x.id).select('id').then(unaFila);
      }
      window.LW_V4.aprobarSolicitud = function (x) {
        modal('Aprobar SP-' + x.numero, [
          { tipo: 'nota', label: 'SP-' + x.numero + ' queda APROBADA — pendiente de pago. Solo la resuelve un administrador (el trigger lo exige igual que este aviso).' }
        ], 'Aprobar', function () { return resolverSolicitud(x, { estado: 'aprobada' }); });
      };
      window.LW_V4.rechazarSolicitud = function (x) {
        modal('Rechazar SP-' + x.numero, [
          { k: 'motivo', label: 'Motivo del rechazo — se le enseña al compañero tal cual', tipo: 'textarea', req: 1 }
        ], 'Rechazar la solicitud', function (v) {
          // el CHECK solicitud_rechazo_con_motivo ya lo exige server-side; esto
          // solo evita el viaje redondo cuando el campo llega vacío.
          if (!v.motivo.trim()) return { error: { message: 'el motivo es obligatorio — sin él la base no acepta el rechazo' } };
          return resolverSolicitud(x, { estado: 'rechazada', motivo_rechazo: v.motivo.trim() });
        });
      };
      window.LW_V4.anularSolicitud = function (x) {
        modal('Anular SP-' + x.numero, [
          { tipo: 'nota', label: 'SP-' + x.numero + ' quedará anulada. No se borra: el registro se queda, sin efecto. Solo quien la creó puede anularla (el trigger lo exige igual que este aviso).' }
        ], 'Anular', function () { return resolverSolicitud(x, { estado: 'anulada' }); });
      };
      window.LW_V4.pagarSolicitud = function (x) {
        modal('Marcar pagada SP-' + x.numero, [
          // opcional en la base (`solicitud_pagada_con_sello` solo exige
          // pagado_en, nunca pago_referencia — correccion #2): sin `req`.
          { k: 'referencia', label: 'Referencia del pago (opcional) — transferencia, Wise, fecha…', valor: '' }
        ], 'Confirmar: pagada', function (v) {
          return resolverSolicitud(x, { estado: 'pagada', pago_referencia: v.referencia.trim() || null });
        });
      };

      /* «+ Nueva solicitud» de la cabecera: mismo patron `ata()` que el resto
         de altas nativas de la v4 — reclama el boton por TEXTO, en directo. */
      ata(/^\+? ?Nueva solicitud$/i, function () { window.LW_V4.abreAltaSolicitud(null); });
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

      /* Categorías de un ENLACE (S11.1, 22-sep-2026): fuente ÚNICA para el
         alta y la edición — nunca las 9 del CHECK de la tabla (incluye
         `faq`/`portada`). Si se expusiera el CHECK completo en el <select> de
         edición, alguien podría reclasificar en silencio una fila protegida
         (una FAQ interna, o `publicado_investor_deck=true`) fuera de su
         categoría, sin pasar por el candado de confirmación que sí tiene el
         alta — hallazgo de la revisión previa #40 (Seguridad+Legal+Datos). */
      var CATS_ENLACE = ['comercial', 'legal', 'tecnico', 'precios'];

      /* Candado de publicación (portal / dosier de inversores) — S10.4/S11.1:
         antes eran `window.confirm()` en el alta y NADA en la edición (dos
         candados hubiera sido la Regla 0 al revés: uno se queda atrás). Ahora
         es una función, `lwConfirmar` (cargado bajo demanda), y S17 exige
         `grep -c window.confirm = 0` en el gate — este es el único punto
         donde se decide. Devuelve una promesa: { ok:true } o { ok:false, msg }. */
      function confirmaPublicacionDoc(v, nombreProyecto) {
        // El deck es PÚBLICO y sin login, así que su confirmación es más dura
        // que la del portal: aquello lo ven compradores con contrato, esto lo
        // ve internet. Esta comprobación es un candado duro, no una confirmación:
        // nunca se pregunta, se rechaza.
        if (v.publicado_investor_deck && v.confidencial) {
          return Promise.resolve({ ok: false, msg: 'un documento confidencial no puede publicarse en el dosier de inversores — desmarca una de las dos' });
        }
        if (!v.visible_portal && !v.publicado_investor_deck) return Promise.resolve({ ok: true });
        return aseguraModulosDoc(['dialogo']).then(function () {
          var pasos = Promise.resolve(true);
          if (v.visible_portal) {
            pasos = pasos.then(function (ok) {
              if (!ok) return false;
              return lwConfirmar({
                titulo: 'Publicar al portal',
                cuerpo: '<p>«' + esc(v.titulo) + '» quedará visible para TODOS los compradores de ' + esc(nombreProyecto) + ' en su portal.</p>',
                confirmar: 'Publicar'
              });
            });
          }
          if (v.publicado_investor_deck) {
            pasos = pasos.then(function (ok) {
              if (!ok) return false;
              return lwConfirmar({
                titulo: 'Publicar en el dosier de inversores',
                cuerpo: '<p>«' + esc(v.titulo) + '» quedará descargable por CUALQUIERA que abra el dosier público de ' + esc(nombreProyecto) + ', sin contraseña y sin contrato.</p>' +
                  '<p>Si el enlace es de Drive, ábrelo antes en una ventana de incógnito: si no está compartido en abierto, el inversor se choca con una pantalla de permisos.</p>',
                confirmar: 'Publicar', tono: 'peligro'
              });
            });
          }
          return pasos;
        }).then(function (ok) {
          return ok ? { ok: true } : { ok: false, msg: 'publicación cancelada — desmarca la casilla o confirma' };
        });
      }

      /* Renombrar un proyecto (S10.1, 22-sep-2026): porta el `renombrarProyecto()`
         de /intranet/proyectos/index.html:704-732 — mismo radio de impacto (5
         tablas), mismo aviso de `contracts/tokens.json` (no se actualiza
         solo), mismo RPC `renombrar_proyecto` (SECURITY DEFINER, gate
         es_admin() dentro). Nunca un UPDATE directo a `proyectos.nombre`. */
      function confirmaYRenombraProyecto(p, nuevo) {
        var cuenta = function (tabla, columna) { return sb.from(tabla).select('id', { count: 'exact', head: true }).eq(columna, p.nombre); };
        return Promise.all([
          cuenta('unidades', 'proyecto'),
          // contratos/facturas: RPC "equipo", NUNCA `.from()` a pelo (hallazgo
          // de code-review, 22-sep-2026) — la RLS de esas dos tablas escala
          // por `es_suyo()` (ver la cabecera de este fichero, líneas 5-7: "aun
          // así caí en ello al escribir esta pantalla"). Un admin real la
          // salta igual, pero un manager sin `es_admin()` vería el radio de
          // impacto incompleto justo antes de una operación que toca 5 tablas
          // — mismo patrón que ya usa el resto de esta pantalla más abajo
          // (`facturas_equipo` en el `Promise.all` principal).
          sb.rpc('contratos_equipo').select('id,proyecto_nombre'),
          sb.rpc('facturas_equipo').select('id,proyecto_nombre'),
          cuenta('documentos_proyecto', 'proyecto'),
          cuenta('modelos_villa', 'proyecto')
        ]).then(function (rs) {
          var uds = (rs[0] && rs[0].count) || 0;
          var con = ((rs[1] && rs[1].data) || []).filter(function (c) { return c.proyecto_nombre === p.nombre; }).length;
          var fac = ((rs[2] && rs[2].data) || []).filter(function (f) { return f.proyecto_nombre === p.nombre; }).length;
          var doc = (rs[3] && rs[3].count) || 0, mod = (rs[4] && rs[4].count) || 0;
          var radio = [
            uds ? uds + ' unidad(es)' : '', con ? con + ' contrato(s)' : '',
            fac ? fac + ' factura(s)' : '', doc ? doc + ' documento(s)' : '',
            mod ? mod + ' modelo(s) de villa' : ''
          ].filter(Boolean).join(', ');
          var avisoRadio = radio ? 'Se actualizará en: ' + radio + '.' : 'No hay nada vinculado a este nombre todavía.';
          return aseguraModulosDoc(['dialogo']).then(function () {
            return lwConfirmar({
              titulo: 'Renombrar «' + p.nombre + '» a «' + nuevo + '»',
              cuerpo: '<p>' + esc(avisoRadio) + '</p><p>Si este proyecto aparece en <b>contracts/tokens.json</b> (proyecto_nombre, parcelaPorProyecto, resortPorProyecto), ese archivo <b>no se actualiza solo</b> y hay que tocarlo a mano.</p>',
              confirmar: 'Renombrar'
            });
          });
        }).then(function (ok) {
          if (!ok) return { error: { message: 'Cancelado: el proyecto conserva su nombre.' } };
          return sb.rpc('renombrar_proyecto', { p_antiguo: p.nombre, p_nuevo: nuevo });
        });
      }

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
            { k: 'categoria', label: 'Categoría', tipo: 'select', opciones: CATS_ENLACE, valor: 'comercial' },
            // S11.3 (22-sep-2026): la columna ya existía (la consulta de
            // datos.js ya la traía) — solo faltaba el wiring del formulario.
            { k: 'carpeta', label: 'Carpeta (opcional)', ayuda: 'Para agrupar en la vista de la clásica. Ej. "Legal", "Planos".' },
            { k: 'descripcion', label: 'Descripción (opcional)', tipo: 'textarea' },
            { k: 'visible_portal', label: 'Visible para el comprador', tipo: 'check', ayuda: 'lo verán TODOS los compradores de ' + p + ' en su portal' },
            { k: 'confidencial', label: 'Confidencial (solo equipo)', tipo: 'check', valor: 1 },  // nace MARCADA: la tabla se diseño con default true y el formulario mandaba false explicito, asi que todo documento nuevo nacia no-confidencial y el 'cinturon y tirantes' del RPC no protegia nada
            { k: 'publicado_investor_deck', label: 'Publicar en el dosier de inversores', tipo: 'check', ayuda: 'PÚBLICO: lo ve cualquiera que abra el enlace del deck, sin contraseña y sin contrato' }
          ], 'Guardar enlace', function (v) {
            if (!/^https?:\/\//.test(v.url)) return { error: { message: 'la URL tiene que empezar por http:// o https://' } };
            return confirmaPublicacionDoc(v, p).then(function (c) {
              if (!c.ok) return { error: { message: c.msg } };
              return sb.from('documentos_proyecto').insert({
                proyecto: p, titulo: v.titulo, url: v.url, categoria: v.categoria,
                carpeta: v.carpeta.trim() || null, descripcion: v.descripcion.trim() || null,
                visible_portal: v.visible_portal, confidencial: v.confidencial,
                // Confidencial MANDA sobre publicado. La misma regla vive también en el
                // RPC `investor_deck_documentos` a propósito: una casilla del navegador
                // no es un permiso.
                publicado_investor_deck: !!v.publicado_investor_deck && !v.confidencial
              });
            });
          });
        });
        var bf = document.getElementById('btn-faq');
        if (bf) bf.addEventListener('click', function (ev) {
          ev.stopPropagation();
          var p = proyecto(); if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
          modal('Nueva pregunta frecuente · ' + p, [
            { k: 'titulo', label: 'Pregunta', req: 1 },
            // S11.4 (22-sep-2026): la respuesta pasa a opcional (igual que la
            // clásica, que guarda `.trim() || null`) — solo cambia la
            // validación de frontend, la columna ya admitía null. Y se fija
            // `carpeta: CARPETA_FAQ` al guardar, igual que la clásica, para
            // que la FAQ aparezca como su propia sección en el árbol de
            // Documentación en vez de mezclada sin carpeta.
            { k: 'descripcion', label: 'Respuesta (opcional)', tipo: 'textarea' }
          ], 'Guardar pregunta', function (v) {
            // como las seis existentes: categoria faq, solo equipo
            return sb.from('documentos_proyecto').insert({
              proyecto: p, titulo: v.titulo, descripcion: v.descripcion.trim() || null,
              categoria: 'faq', carpeta: 'Preguntas frecuentes', confidencial: true, visible_portal: false
            });
          });
        });

        /* Editar/borrar un enlace o una FAQ (S11.1, 22-sep-2026). Delegado en
           los contenedores ESTÁTICOS (#d-enlaces/#d-faqs): datos.js reemplaza
           sus filas en cada apertura del cajón, un listener por fila se
           perdería al abrir el siguiente proyecto. `window.LW_V4.documentos`
           lo llena datos.js al pintar (DOCUMENTOS_CAJON), mismo patrón que
           `window.LW_V4.unidades` para "Editar unidad". */
        function documentoDe(fila) {
          var id = fila.getAttribute('data-doc-id');
          return (window.LW_V4 && window.LW_V4.documentos && window.LW_V4.documentos[id]) || null;
        }

        /* Confirmación de publicación en la EDICIÓN: solo se pregunta si una
           casilla PASA de false a true — repreguntar en cada guardado de un
           documento que YA estaba publicado sería el aviso-que-siempre-se-
           ignora que esta suite ya aprendió a no repetir (contexto/
           suite_lawang.md, "Un fallo no se avisa igual que un guardado"). El
           candado duro (confidencial+deck a la vez) usa los valores FINALES,
           no el delta: da igual si `confidencial` es nuevo o ya lo era. */
        function confirmaPublicacionDocEdicion(v, anterior, nombreProyecto) {
          if (v.publicado_investor_deck && v.confidencial) {
            return Promise.resolve({ ok: false, msg: 'un documento confidencial no puede publicarse en el dosier de inversores — desmarca una de las dos' });
          }
          var nuevoPortal = v.visible_portal && !anterior.visible_portal;
          var nuevoDeck = v.publicado_investor_deck && !anterior.publicado_investor_deck;
          if (!nuevoPortal && !nuevoDeck) return Promise.resolve({ ok: true });
          return confirmaPublicacionDoc({ titulo: v.titulo, confidencial: v.confidencial, visible_portal: nuevoPortal, publicado_investor_deck: nuevoDeck }, nombreProyecto);
        }

        function abreEditarEnlace(d2) {
          var p = proyecto() || d2.proyecto || '';
          // Trampa cazada en revisión previa #40: una fila con `categoria`
          // fuera de las 4 restringidas (p.ej. 'fotos', subida hoy solo desde
          // la clásica) en un <select> de 4 opciones saldría con la primera
          // marcada — guardar sin tocar la reclasificaría EN SILENCIO. Si la
          // categoría actual no está en la lista restringida, se añade como
          // opción extra ya seleccionada, en vez de forzar una de las 4.
          var catsAquí = CATS_ENLACE.indexOf(d2.categoria) !== -1 ? CATS_ENLACE : CATS_ENLACE.concat([d2.categoria]);
          modal('Editar enlace', [
            { k: 'titulo', label: 'Título', req: 1, valor: d2.titulo || '' },
            { k: 'url', label: 'URL', req: 1, valor: d2.url || '', ayuda: 'https://…' },
            { k: 'categoria', label: 'Categoría', tipo: 'select', opciones: catsAquí, valor: d2.categoria || CATS_ENLACE[0] },
            { k: 'carpeta', label: 'Carpeta (opcional)', valor: d2.carpeta || '' },
            { k: 'descripcion', label: 'Descripción (opcional)', tipo: 'textarea', valor: d2.descripcion || '' },
            { k: 'visible_portal', label: 'Visible para el comprador', tipo: 'check', valor: !!d2.visible_portal, ayuda: 'lo verán TODOS los compradores de ' + p + ' en su portal' },
            { k: 'confidencial', label: 'Confidencial (solo equipo)', tipo: 'check', valor: !!d2.confidencial },
            { k: 'publicado_investor_deck', label: 'Publicar en el dosier de inversores', tipo: 'check', valor: !!d2.publicado_investor_deck, ayuda: 'PÚBLICO: lo ve cualquiera que abra el enlace del deck, sin contraseña y sin contrato' }
          ], 'Guardar cambios', function (v) {
            if (!/^https?:\/\//.test(v.url)) return { error: { message: 'la URL tiene que empezar por http:// o https://' } };
            return confirmaPublicacionDocEdicion(v, d2, p).then(function (c) {
              if (!c.ok) return { error: { message: c.msg } };
              return sb.from('documentos_proyecto').update({
                titulo: v.titulo, url: v.url, categoria: v.categoria,
                carpeta: v.carpeta.trim() || null, descripcion: v.descripcion.trim() || null,
                visible_portal: v.visible_portal, confidencial: v.confidencial,
                publicado_investor_deck: !!v.publicado_investor_deck && !v.confidencial
              }).eq('id', d2.id).select('id').then(unaFila);
            });
          });
        }

        function abreEditarFaq(d2) {
          modal('Editar pregunta frecuente', [
            { k: 'titulo', label: 'Pregunta', req: 1, valor: d2.titulo || '' },
            { k: 'descripcion', label: 'Respuesta (opcional)', tipo: 'textarea', valor: d2.descripcion || '' }
          ], 'Guardar cambios', function (v) {
            return sb.from('documentos_proyecto').update({
              titulo: v.titulo, descripcion: v.descripcion.trim() || null
            }).eq('id', d2.id).select('id').then(unaFila);
          });
        }

        /* Borrar (S11.1): la policy DELETE de `documentos_proyecto` exige
           `es_super_admin()` — más estricta que editar (`puede('documentacion')`
           a secas). datos.js ya esconde el botón para quien no lo es
           (pintaAccionesDoc); este chequeo es el cinturón, no el gate real —
           si RLS deniega, `unaFila` lo dice, nunca un "borrado" mentiroso. */
        function borraDocumento(d2, etiquetaTipo) {
          aseguraModulosDoc(['dialogo']).then(function () {
            return lwConfirmar({
              titulo: 'Borrar ' + etiquetaTipo,
              cuerpo: '<p>«' + esc(d2.titulo || etiquetaTipo) + '» se borra de la documentación del proyecto. No se puede deshacer.</p>',
              confirmar: 'Borrar', tono: 'peligro'
            });
          }).then(function (ok) {
            if (!ok) return;
            sb.from('documentos_proyecto').delete().eq('id', d2.id).select('id').then(function (r) {
              var u2 = unaFila(r);
              if (u2.error) return aviso('No se pudo borrar: ' + u2.error.message, '#ba1a1a');
              aviso('Borrado');
              location.reload();
            });
          });
        }

        [document.getElementById('d-enlaces'), document.getElementById('d-faqs')].forEach(function (caja) {
          if (!caja) return;
          caja.addEventListener('click', function (ev) {
            var bEditar = ev.target.closest && ev.target.closest('[data-doc-editar]');
            var bBorrar = ev.target.closest && ev.target.closest('[data-doc-borrar]');
            if (!bEditar && !bBorrar) return;
            ev.preventDefault(); ev.stopPropagation();
            var fila = ev.target.closest('[data-doc-id]');
            if (!fila) return;
            var d2 = documentoDe(fila);
            if (!d2) return aviso('Este elemento ya no está en pantalla — vuelve a abrir el proyecto.', '#8A6A34');
            if (bEditar) { if (d2.categoria === 'faq') abreEditarFaq(d2); else abreEditarEnlace(d2); return; }
            borraDocumento(d2, d2.categoria === 'faq' ? 'esta pregunta' : 'este enlace');
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
            // S10.1 (22-sep-2026): el modal de editar no traía `nombre` (solo
            // lo tenía el alta) — se escribe por el RPC `renombrar_proyecto`,
            // que hace el cascade atómico a unidades/contratos/facturas/
            // documentos_proyecto/modelos_villa. Nunca un UPDATE directo a
            // `proyectos.nombre` a secas: dejaría esas 5 tablas huérfanas,
            // con el nombre viejo, mientras el desplegable ya solo ofrece
            // el nuevo (ver contracts/... /renombrar_proyecto.sql).
            { k: 'nombre', label: 'Nombre', req: 1, valor: p.nombre,
              ayuda: 'Cuidado: renombrar aquí toca unidades, contratos, facturas, documentación y modelos de este proyecto — se confirma con el radio de impacto antes de guardar.' },
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
            var nombreNuevo = (v.nombre || '').trim();
            if (!nombreNuevo) return { error: { message: 'el nombre no puede quedar vacío' } };
            var renombrando = nombreNuevo !== p.nombre;
            var nombreEfectivo = renombrando ? nombreNuevo : p.nombre;

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

            // El renombrado va PRIMERO y por su propio RPC (nunca dentro del
            // UPDATE de abajo, que solo toca `proyectos` por `id`): cascadea
            // unidades/contratos/facturas/documentos_proyecto/modelos_villa,
            // y lo que sigue (modelos declarados, foto de portada) tiene que
            // escribir ya con el nombre NUEVO — si escribiera con el viejo,
            // `lwDeclaraModelosEnProyecto` y la portada quedarían colgando de
            // un nombre que `modelos_villa`/`documentos_proyecto` ya dejaron
            // de tener tras el cascade.
            var pasoRenombrar = !renombrando
              ? Promise.resolve({ error: null })
              : confirmaYRenombraProyecto(p, nombreNuevo);

            return pasoRenombrar.then(function (rr) {
              if (rr && rr.error) return rr;
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
                  trabajos.push(lwDeclaraModelosEnProyecto(sb, nombreEfectivo, v.modelos || [], {
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
                      .then(function (rr2) { if (rr2.error) aviso('No se pudo actualizar el proyecto de ' + (m.nombre || m.email) + ': ' + rr2.error.message, '#ba1a1a'); }));
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
                          proyecto: nombreEfectivo, categoria: 'portada', titulo: 'Portada',
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
                return Promise.all(trabajos).then(function () {
                  // Navegación manual en vez del reload por defecto de modal()
                  // (opts.sinRecarga, ver la llamada de abajo): tras renombrar,
                  // un `location.reload()` a secas se quedaría con
                  // `?proyecto=<nombre-viejo>` en la URL, que ya no casa con
                  // ningún proyecto — el cajón se recargaría cerrado, sin
                  // avisar de que el guardado SÍ funcionó. Se corrige el
                  // parámetro con `history.replaceState` (conserva cualquier
                  // otro query — `?qa=1` del harness incluido) y LUEGO se
                  // recarga de verdad, para traer los datos ya actualizados.
                  var u2 = new URL(location.href);
                  u2.searchParams.set('proyecto', nombreEfectivo);
                  history.replaceState(null, '', u2.href);
                  setTimeout(function () { location.reload(); }, renombrando ? 300 : 0);
                  return r;
                });
              });
            });
          }, { sinRecarga: true });
        });
      });

      /* Borrar proyecto (11-sep-2026, recuento+lwConfirmar añadidos S10.4
         22-sep-2026): botón ya solo super_admin lo ve (title lo avisa desde
         Stitch); el gate real es el RPC — es_super_admin() dentro de
         borrar_proyecto(), no esta UI. El RPC rechaza el borrado si quedan
         unidades, modelos de villa o documentos colgando (contratos/facturas
         NO bloquean — proyecto_nombre ahí es una foto impresa, no una
         consulta en vivo). El recuento de aquí es solo UX, para no pedir
         confirmar a ciegas: NUNCA sustituye la llamada al RPC, aunque dé
         cero — puede desincronizarse entre el cálculo y el clic. */
      ata(/^Borrar proyecto$/i, function () {
        var p = proyectoObj();
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
        if (!esSuper) return aviso('Borrar un proyecto es solo para super_admin.', '#8A6A34');
        var cuenta = function (tabla, columna) { return sb.from(tabla).select('id', { count: 'exact', head: true }).eq(columna, p.nombre); };
        Promise.all([
          cuenta('unidades', 'proyecto'), cuenta('modelos_villa', 'proyecto'), cuenta('documentos_proyecto', 'proyecto')
        ]).then(function (rs) {
          var uds = (rs[0] && rs[0].count) || 0, mods = (rs[1] && rs[1].count) || 0, docs = (rs[2] && rs[2].count) || 0;
          var bloquea = [
            uds ? uds + ' unidad(es)' : '', mods ? mods + ' modelo(s) de villa' : '', docs ? docs + ' documento(s)' : ''
          ].filter(Boolean).join(', ');
          return aseguraModulosDoc(['dialogo']).then(function () {
            return lwConfirmar({
              titulo: 'Borrar el proyecto «' + p.nombre + '» del catálogo',
              cuerpo: (bloquea
                ? '<p>Bloqueado ahora mismo: quedan <b>' + esc(bloquea) + '</b> colgando. El sistema rechazará el borrado hasta que se vacíen.</p>'
                : '<p>Nada de lo que bloquea el borrado ahora mismo — puede desincronizarse entre este cálculo y el clic; el RPC es quien decide de verdad.</p>') +
                '<p>Contratos y facturas que nombren este proyecto NO se tocan: quedan como documentos ya emitidos.</p>',
              confirmar: 'Borrar el proyecto', tono: 'peligro'
            });
          });
        }).then(function (ok) {
          if (!ok) return;
          sb.rpc('borrar_proyecto', { p_nombre: p.nombre }).then(function (r) {
            if (r.error) return aviso('No se pudo borrar: ' + r.error.message, '#ba1a1a');
            aviso('Proyecto borrado');
            setTimeout(function () { location.href = '/intranet/v4/proyectos/'; }, 1200);
          });
        });
      });

      /* Fotos del Investor Deck (S10.2, 22-sep-2026): pieza COMPARTIDA de la
         suite (contracts/assets/deck_fotos.js, Regla 0) que ya usan
         /proyectos/ y /modelos/ clásicos — se engancha TAL CUAL, nunca se
         reescribe. Sube = publica al instante en el bucket público 'deck',
         sin estado intermedio "sin publicar": el propio deck_fotos.js lo
         avisa en pantalla antes de dejar subir nada. dialogo.js hace falta
         para que su confirmación de "Quitar esta foto" no se salte sola. */
      ata(/^Fotos del deck$/i, function () {
        var p = proyectoObj();
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
        aseguraModulosDoc(['dialogo', 'deckFotos']).then(function () {
          if (!window.lwDeckFotos) return aviso('No se ha podido cargar el gestor de fotos del deck.', '#ba1a1a');
          window.lwDeckFotos.abrir({
            SB: sb, ambito: 'proyecto', proyectoId: p.id, esAdmin: esAdminP,
            titulo: 'Fotos públicas del deck', sub: p.nombre
          });
        }, function (e) { aviso('No se ha podido cargar el gestor de fotos del deck: ' + (e && e.message || e), '#ba1a1a'); });
      });

      /* Investor Deck (S10.3, 22-sep-2026, revisión previa #40 Seguridad+
         Legal+Datos): porta `abrirInvestorDeck()` de
         /intranet/proyectos/index.html:904-983 TAL CUAL — mismo RPC
         (`investor_deck_activar`, SECURITY DEFINER con `es_admin()` propio,
         nunca un UPDATE en bloque a `unidades` desde aquí), misma
         confirmación "Incluidas las vendidas y reservadas", mismo botón
         "Activar" deshabilitado sin título guardado. El mecanismo YA EXISTE
         en producción (Palm Field, 15-sep) — esto solo lo engancha a la v4,
         con el cajón NATIVO de este fichero (`cajon()`) en vez de
         `suiAbrirCajon`: Guardar y Activar/Desactivar son SIEMPRE dos clics
         distintos, nunca el mismo, igual que la clásica. */
      ata(/^Investor Deck$/i, function () {
        var p = proyectoObj();
        if (!p) return aviso('El proyecto aún no ha cargado.', '#8A6A34');
        Promise.all([
          sb.from('deck_config_proyecto').select('titulo,meta_desc,modelo_destacado_id').eq('proyecto_id', p.id).maybeSingle(),
          sb.from('unidades').select('id', { count: 'exact', head: true }).eq('proyecto', p.nombre).eq('publicado_investor_deck', true),
          sb.from('modelos_villa').select('modelo_id,modelo').eq('proyecto', p.nombre).not('modelo_id', 'is', null)
        ]).then(function (rs) {
          if (rs[0].error) return aviso('No se pudo abrir el Investor Deck: ' + rs[0].error.message, '#ba1a1a');
          var cfg = (rs[0] && rs[0].data) || {};
          var activo = !!((rs[1] && rs[1].count) || 0);
          var modelosDelProyecto = (rs[2] && rs[2].data) || [];
          pintaInvestorDeck(p, cfg, activo, modelosDelProyecto);
        }, function (e) { aviso('No se pudo abrir el Investor Deck: ' + (e && e.message || e), '#ba1a1a'); });
      });

      function pintaInvestorDeck(p, cfg, activo, modelosDelProyecto) {
        var tituloEn = (cfg.titulo && cfg.titulo.en) || '';
        var metaEn = (cfg.meta_desc && cfg.meta_desc.en) || '';
        var destacadoId = cfg.modelo_destacado_id || '';
        var estiloDeck = 'width:100%;padding:9px 12px;border:1px solid ' + CAJ.borde + ';border-radius:8px;font-weight:500;font-size:14px;color:' + CAJ.tinta + ';background-color:#fff;box-sizing:border-box';
        var campoDeck = function (label, valorHtml, ayuda) {
          return '<label style="display:grid;gap:6px;background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde + ';border-radius:12px;padding:12px 14px;font-weight:500;font-size:12px;color:' + CAJ.apagado + '">' +
            esc(label) + valorHtml + (ayuda ? '<small style="font-weight:400;font-size:11.5px;color:#8A8474">' + esc(ayuda) + '</small>' : '') + '</label>';
        };
        var cuerpo =
          '<p style="margin:0 0 4px;font-size:13px;color:' + CAJ.apagado + ';line-height:1.5">Página pública de due diligence para inversores, sin login. Se sirve en <code>/investor-deck/' + esc(p.slug || '<slug>') + '/</code>.</p>' +
          (!esAdminP ? '<p style="margin:0 0 4px;font-size:12.5px;color:#8A6A34">Solo un administrador puede editar o activar el Investor Deck.</p>' : '') +
          campoDeck('Slug de la URL', '<input id="id-slug" value="' + esc(p.slug || '') + '" placeholder="ej. sumba-hills" style="' + estiloDeck + '"' + (esAdminP ? '' : ' disabled') + '>', 'Se escribe una sola vez. Cambiarlo tras activar el deck rompe cualquier enlace ya compartido.') +
          campoDeck('Título (inglés)', '<input id="id-titulo" value="' + esc(tituloEn) + '" placeholder="ej. Sumba Hills — Investor Deck" style="' + estiloDeck + '"' + (esAdminP ? '' : ' disabled') + '>') +
          campoDeck('Meta description (inglés)', '<input id="id-meta" value="' + esc(metaEn) + '" style="' + estiloDeck + '"' + (esAdminP ? '' : ' disabled') + '>') +
          campoDeck('Modelo "Most requested" (opcional)',
            '<select id="id-destacado" style="' + estiloDeck + flechaSelect + '"' + (esAdminP ? '' : ' disabled') + '><option value="">— ninguno —</option>' +
            modelosDelProyecto.map(function (m) { return '<option value="' + esc(m.modelo_id) + '"' + (destacadoId === m.modelo_id ? ' selected' : '') + '>' + esc(m.modelo) + '</option>'; }).join('') +
            '</select>') +
          '<p style="margin:0;font-size:12px;color:' + CAJ.apagado + '">KPIs de cabecera y plano interactivo de parcelas no se editan aquí todavía — sin ellos, esas secciones simplemente no aparecen en la página pública (nunca placeholders).</p>' +
          '<div style="background:' + CAJ.banda + ';border:1px solid ' + CAJ.borde + ';border-radius:12px;padding:12px 14px;font-size:13px;color:' + CAJ.tinta + '">' +
            '<b>Estado: </b>' + (activo
              ? 'el deck está <b style="color:#3F5230">ACTIVO</b> — todas las unidades de este proyecto son visibles en la página pública.'
              : 'el deck está <b style="color:#9E2F26">INACTIVO</b> — nada de este proyecto es visible en la página pública.') +
          '</div>';

        var puedeActivar = esAdminP && (activo || !!tituloEn);

        var c = cajon({
          titulo: 'Investor Deck', sub: p.nombre, ancho: 'min(560px,96vw)',
          cuerpo: cuerpo,
          acciones: [
            { texto: 'Guardar', tono: 'primario', disabled: !esAdminP, onClick: guardarDeckConfig },
            { texto: activo ? 'Desactivar deck' : 'Activar deck', tono: activo ? '' : 'primario',
              disabled: !puedeActivar, title: (!activo && !tituloEn) ? 'Guarda un título primero' : '',
              onClick: toggleInvestorDeck },
            { texto: 'Cerrar', cerrar: true }
          ]
        });

        function guardarDeckConfig() {
          var slug = document.getElementById('id-slug').value.trim().toLowerCase().replace(/[^a-z0-9-]/g, '');
          var tEn = document.getElementById('id-titulo').value.trim();
          var mEn = document.getElementById('id-meta').value.trim();
          if (!tEn || !mEn) return aviso('Título y meta description son obligatorios.', '#8A6A34');
          var destId = document.getElementById('id-destacado').value || null;
          var tareas = [];
          if (slug && slug !== (p.slug || '')) {
            tareas.push(sb.from('proyectos').update({ slug: slug }).eq('id', p.id).select('id').then(unaFila));
          }
          // `.select().then(unaFila)` (hallazgo de code-review, 22-sep-2026):
          // sin esto, un upsert que la RLS deniega en silencio (`for all using
          // (es_admin())`, sesión caducada, lo que sea) devuelve sin `.error`
          // y el código seguía derecho a "Guardado" + reload — el mismo fallo
          // silencioso que este fichero ya avisa y evita en el UPDATE de
          // `proyectos` de más arriba.
          tareas.push(sb.from('deck_config_proyecto').upsert({
            proyecto_id: p.id, titulo: { en: tEn }, meta_desc: { en: mEn }, modelo_destacado_id: destId
          }, { onConflict: 'proyecto_id' }).select('proyecto_id').then(unaFila));
          Promise.all(tareas).then(function (rr) {
            var err = rr.filter(function (r) { return r && r.error; })[0];
            if (err) return aviso('No se pudo guardar: ' + (err.error.message || 'la base no ha cambiado nada — puede que el slug ya lo use otro proyecto, o que tu sesión no tenga permiso.'), '#ba1a1a');
            aviso('Guardado');
            location.reload();
          });
        }

        function toggleInvestorDeck() {
          var nuevoEstado = !activo;
          aseguraModulosDoc(['dialogo']).then(function () {
            return lwConfirmar({
              titulo: nuevoEstado ? 'Activar el Investor Deck' : 'Desactivar el Investor Deck',
              cuerpo: nuevoEstado
                ? '<p>Todas las unidades de ' + esc(p.nombre) + ' pasarán a ser visibles, sin login, en /investor-deck/. <b>Incluidas las vendidas y reservadas.</b></p>'
                : '<p>' + esc(p.nombre) + ' deja de ser visible en el Investor Deck público.</p>',
              confirmar: nuevoEstado ? 'Activar' : 'Desactivar'
            });
          }).then(function (ok) {
            if (!ok) return;
            return sb.rpc('investor_deck_activar', { p_proyecto: p.nombre, p_activo: nuevoEstado }).then(function (r) {
              if (r.error) return aviso('No se pudo cambiar el estado: ' + r.error.message, '#ba1a1a');
              aviso(nuevoEstado ? 'Deck activado' : 'Deck desactivado');
              c.cierra();
              location.reload();
            });
          });
        }
      }

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
            { k: 'moneda', label: 'Moneda', tipo: 'select', medio: 1, opciones: ['EUR', 'USD', 'AUD', 'IDR'], valor: 'EUR' },
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
                })) },
              // `avisoEstado` (S10.6, 22-sep-2026): porta el aviso de
              // /intranet/proyectos/index.html:1450-1459 — el guardia que dice
              // en voz alta lo que la base no puede saber sola (que ESTA
              // parcela ya está comprometida con OTRO contrato). Contenedor
              // 'custom' vacío al abrir; se rellena tras `modal()`, cuando los
              // <select> de estado/contrato ya existen en el DOM.
              { tipo: 'custom', render: function (d) { d.style.cssText = 'display:none;grid-column:1/-1'; d.id = 'aviso-estado-u'; } }
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
          /* avisoEstado (S10.6, 22-sep-2026) — solo existe cuando la parcela
             NO está vinculada (arriba, el campo 'custom' con id
             "aviso-estado-u" solo se pinta en ese `else`). Compara CONTRA
             `window.LW_V4.unidades`: las unidades YA CARGADAS del proyecto
             abierto en el cajón, no toda la cartera como hacía `UNIDADES` en
             la clásica — más estrecho, pero cubre el caso real (dos parcelas
             del MISMO proyecto compartiendo contrato por error), que es lo
             que este aviso existe para cazar. */
          var estSel = document.querySelector('#lw-editor [data-k="estado"]');
          var conSel = document.querySelector('#lw-editor [data-k="contrato_id"]');
          var avisoEstadoDiv = document.getElementById('aviso-estado-u');
          if (estSel && conSel && avisoEstadoDiv) {
            var actualizaAvisoEstado = function () {
              var est = estSel.value, cid = conSel.value;
              var msgs = [];
              if ((est === 'vendida' || est === 'reservada') && !cid) {
                msgs.push('Marcada como ' + etiq(est).toLowerCase() + ' pero sin contrato asociado: no se podrá saber de quién es.');
              }
              var mapaUnidades = (window.LW_V4 && window.LW_V4.unidades) || {};
              var otras = [];
              Object.keys(mapaUnidades).forEach(function (idU) {
                var uu = mapaUnidades[idU];
                if (uu && uu.contrato_id && uu.contrato_id === cid && uu.id !== u.id) otras.push(uu.codigo);
              });
              if (cid && otras.length) msgs.push('Ese contrato ya está asociado a ' + otras.join(', ') + '. Si no es una operación de varias unidades, revísalo.');
              if (msgs.length) {
                avisoEstadoDiv.style.display = 'block';
                avisoEstadoDiv.innerHTML = '<p style="margin:0;font-weight:500;font-size:12.5px;line-height:1.5;color:#8A6A34;background:#FBF3E4;border:1px solid #EBDCB4;border-radius:12px;padding:11px 14px">' +
                  msgs.map(esc).join('<br>') + '</p>';
              } else { avisoEstadoDiv.style.display = 'none'; avisoEstadoDiv.innerHTML = ''; }
            };
            estSel.addEventListener('change', actualizaAvisoEstado);
            conSel.addEventListener('change', actualizaAvisoEstado);
            actualizaAvisoEstado();
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
          /* Misma conversión estimada IDR→EUR que el cajón de unidades
             (datos.js, `estimaEUR`/`TASA_IDR_EUR_ESTIMADA`) — no una segunda
             tasa a mano: dos números "estimado" que no coincidan serían peor
             que uno solo (21-sep-2026, mismo encargo del owner sobre
             Riverfront I/II). Sin `window.LW_V4.estimaEUR` cargado (datos.js
             no llegó a tiempo), se cae al comportamiento de antes —excluir y
             contar— en vez de calcular una tasa propia aquí. */
          var estimaEUR = (window.LW_V4 && window.LW_V4.estimaEUR) || null;
          var tasaFecha = (window.LW_V4 && window.LW_V4.TASA_IDR_EUR_ESTIMADA_FECHA) || 'sin fecha';
          var porP = {};
          us.forEach(function (u) {
            var d = porP[u.proyecto || '¿?'] = porP[u.proyecto || '¿?'] || { t: 0, disp: 0, cartera: 0, estimado: 0, fueraEur: 0 };
            d.t++;
            if (u.estado === 'disponible') d.disp++;
            var moneda = u.moneda || 'EUR';
            if (moneda === 'EUR') d.cartera += Number(u.precio || 0);
            else if (moneda === 'IDR' && estimaEUR) { d.cartera += estimaEUR(u.precio); d.estimado++; }
            else d.fueraEur++;
          });
          var cobP = {};
          fs.forEach(function (f) {
            if (f.anulada || f.tipo !== 'recibi' || (f.moneda || 'EUR') !== 'EUR') return;
            var k = f.proyecto_nombre || ''; cobP[k] = (cobP[k] || 0) + Number(f.total || 0);
          });
          var filas = ps.map(function (p) {
            var d = porP[p.nombre] || { t: 0, disp: 0, cartera: 0, estimado: 0, fueraEur: 0 };
            var cob = cobP[p.nombre] || 0;
            return [p.nombre, p.resort || '', d.t, d.disp, d.cartera.toFixed(2), cob.toFixed(2), (d.cartera - cob).toFixed(2), d.estimado, d.fueraEur];
          });
          descargaCsv('lawang-proyectos-' + new Date().toISOString().slice(0, 10) + '.csv',
            ['Proyecto', 'Resort', 'Unidades', 'Disponibles', 'Cartera EUR (incl. estimado IDR, tasa del ' + tasaFecha + ')', 'Cobrado EUR', 'Pendiente EUR', 'Unidades convertidas (estimado IDR)', 'Unidades sin tasa de conversión'],
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
      /* `btnAlta` se guarda para poder disparar el alta sola con `?nuevo=1`
         (paridad 21-sep-2026): la pantalla llega desde otro sitio de la suite
         que ya sabe que quiere dar de alta, sin obligar a buscar el botón. */
      var btnAlta = ata(/Alta de comprador/i, function () {
        /* Los SEIS datos que exige un alta (owner, 14-sep-2026) — y el telefono
           partido en prefijo + numero, igual que en /intranet/compradores/, que
           es lo que pidio. Cuales son NO se decide aqui: la lista vive en
           `contracts/assets/compradores.js` (`faltanDatosComprador`), que esta
           pantalla carga, porque si se escribiera tambien aqui las dos copias
           divergirian y este editor seguiria dando de alta fichas a medias.
           El `req: 1` de cada campo es lo que pinta el asterisco y da el aviso
           en el sitio; el validador compartido es el que manda.
           Los 5 campos de debajo (idioma + los 4 "solo empresa") se añaden
           21-sep-2026 para igualar al formulario de EDITAR (abreEditaComprador
           más abajo): antes el alta pedía 7 de las 13 columnas y el resto se
           quedaba a medias hasta la primera edición. */
        modal('Alta de comprador', [
          { k: 'full_name', label: 'Nombre completo / razón social', req: 1 },
          { k: 'email', label: 'Email', tipo: 'email', req: 1 },
          { k: 'prefijo', label: 'Prefijo del teléfono', req: 1, medio: 1, ayuda: '+34, +62, +61…' },
          { k: 'telefono', label: 'Teléfono', req: 1, medio: 1 },
          { k: 'nationality', label: 'Nacionalidad', req: 1, ayuda: 'código de dos letras: ES, SG, AU…' },
          { k: 'passport_number', label: 'Pasaporte / NPWP', req: 1, ayuda: 'Es lo que se imprime en el contrato.' },
          { k: 'tipo', label: 'Tipo', tipo: 'select', opciones: [['persona', 'Persona física'], ['empresa', 'Empresa']], valor: 'persona' },
          { k: 'idioma_comunicacion', label: 'Idioma de comunicación', tipo: 'select', valor: 'es',
            opciones: [['es', 'Español'], ['en', 'English'], ['id', 'Bahasa Indonesia']] },
          { k: 'forma_juridica', label: 'Forma jurídica (solo empresa)', medio: 1, ayuda: 'S.L., LLC, PT PMA, GmbH…' },
          { k: 'registro_num', label: 'Nº de registro mercantil (solo empresa)', medio: 1 },
          { k: 'rep_nombre', label: 'Representante legal (solo empresa)', medio: 1 },
          { k: 'rep_cargo', label: 'Cargo del representante (solo empresa)', medio: 1 }
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
            // MAYÚSCULAS, igual que ya hace el UPDATE de editar (línea de abajo):
            // el contrato y la factura enlazan esta ficha y la imprimen tal cual.
            full_name: v.full_name.trim().toUpperCase(), email: v.email || null,
            phone: v.prefijo ? v.prefijo + ' ' + v.telefono : (v.telefono || null),
            nationality: v.nationality || null, passport_number: v.passport_number || null,
            tipo: v.tipo, idioma_comunicacion: v.idioma_comunicacion || 'es',
            forma_juridica: v.tipo === 'empresa' ? (v.forma_juridica || null) : null,
            registro_num: v.tipo === 'empresa' ? (v.registro_num || null) : null,
            rep_nombre: v.tipo === 'empresa' ? (v.rep_nombre || null) : null,
            rep_cargo: v.tipo === 'empresa' ? (v.rep_cargo || null) : null
          }).then(errorClienteHumano);
        });
        // Nacionalidad como picker de nombre completo, no texto libre — igual
        // que el resto de la suite (geo.js + dialogo.js, cargados en esta
        // página). `modal()` ya construyó el DOM cuando esta línea corre.
        if (window.lwPicker && typeof NACIONALIDADES !== 'undefined') {
          window.lwPicker(document.querySelector('#lw-editor [data-k="nationality"]'), NACIONALIDADES, { titulo: 'Nacionalidad' });
        }
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
        if (window.lwPicker && typeof NACIONALIDADES !== 'undefined') {
          window.lwPicker(document.querySelector('#lw-editor [data-k="nationality"]'), NACIONALIDADES, { titulo: 'Nacionalidad' });
        }
      };
      /* `?nuevo=1` abre el alta sola (paridad 21-sep-2026): quien llega desde
         otro sitio de la suite con la intención ya tomada no debería tener que
         encontrar el botón. Una sola vez, al cargar — no en cada repintado. */
      if (btnAlta && new URLSearchParams(location.search).get('nuevo') === '1') btnAlta.click();
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

      /* ---------- alta nativa (paridad 21-sep-2026) ----------
         Hasta hoy «+ Invitar miembro» redirigía a /intranet/usuarios/?nuevo=1
         (commit 023ec818, arreglo provisional del mismo día). Se sustituye por
         el mismo patrón que ya usan Compradores/Facturas/Recibos: `ata()`
         reclama el botón EN DIRECTO y su entrada en el FORM_REAL de
         maqueta.js se retira del todo (no se deja "por si acaso" — una
         redirección viva que sobreviviera a un fallo de `ata()` sería
         exactamente el escape silencioso a la herramienta vieja que este
         build vino a cerrar, mismo criterio que ya se aplicó ahí el 21-sep). */
      var esCrmAlta = function (p) { return (typeof LW_PERMISOS_CRM !== 'undefined') && LW_PERMISOS_CRM.indexOf(p[0]) !== -1; };
      var herrCrmAlta = (typeof LW_PERMISOS !== 'undefined') ? LW_PERMISOS.filter(esCrmAlta) : [];
      var herrRestoAlta = (typeof LW_PERMISOS !== 'undefined') ? LW_PERMISOS.filter(function (p) { return !esCrmAlta(p); }) : [];
      var tiposCatAlta = (typeof LW_TIPO_CONTRATO === 'object' && LW_TIPO_CONTRATO)
        ? Object.keys(LW_TIPO_CONTRATO).map(function (k) { return [k, LW_TIPO_CONTRATO[k]]; }) : [];

      var btnAlta = ata(/Invitar miembro/i, function () {
        if (!(esAdmin(aut.ficha) && puedeH(aut.ficha, 'usuarios'))) {
          return aviso('Dar de alta exige administración con la herramienta Usuarios.', '#8A6A34');
        }
        var rolInicial = 'agente';
        var soySuperAlta = aut.ficha.rol === 'super_admin';
        /* admin-usuarios (accion:'crear') rechaza con 403 cualquier rol que
           no sea 'agente' si quien crea no es super_admin (index.ts línea
           ~161: «solo_super_admin_crea_admins», y el nombre del error no
           miente pero tampoco distingue: bloquea TAMBIÉN sales_manager/
           project_manager, no solo admin). ROLES_ED no filtra eso — ofrecía
           las cuatro opciones a cualquier admin y el 403 llegaba después de
           rellenar el formulario entero (hallazgo de code-review,
           21-sep-2026). Se ofrece solo lo que de verdad se puede crear. */
        var rolesAlta = soySuperAlta ? ROLES_ED : ['agente'];
        modal('Nuevo usuario', [
          { k: 'email', label: 'Email', tipo: 'email', req: 1, medio: 1 },
          { k: 'nombre', label: 'Nombre', req: 1, medio: 1 },
          { k: 'password', label: 'Contraseña provisional', req: 1, medio: 1,
            ayuda: 'Mínimo 10 caracteres. La verá al entrar; que la cambie después. No se puede volver a consultar.' },
          soySuperAlta
            ? { k: 'rol', label: 'Rol', tipo: 'select', medio: 1, valor: rolInicial,
                opciones: rolesAlta.map(function (r) { return [r, ETIQ_ROL[r] || r]; }) }
            // Sin `k`: no viaja en el payload (mismo patrón que 'nota'/
            // 'lectura' en el resto del fichero) — el rol real lo fija
            // `rolInicial` explícito en el onGuardar de abajo, nunca el
            // default implícito de la edge.
            : { tipo: 'lectura', label: 'Rol', medio: 1, valor: ETIQ_ROL[rolInicial] || rolInicial },
          { tipo: 'nota', label: 'Se crea la cuenta y se le da acceso de inmediato. Nace sin ningún proyecto asignado — se asigna después editando la ficha ya creada.' },
          /* CRM de leads NUNCA preseleccionada, aunque el rol elegido la
             traiga por defecto en «Herramientas que verá» de abajo — decisión
             deliberada (igual que /intranet/usuarios/): Leads abre datos de
             contacto de personas reales y eso se decide una a una. */
          { k: 'herr_crm', label: 'CRM de leads', tipo: 'multicheck', opciones: herrCrmAlta, valor: [],
            ayuda: 'Nunca preseleccionada: Leads abre datos de contacto de personas reales y se decide una a una, nunca de regalo con el rol.' },
          { k: 'herr_resto', label: 'Herramientas que verá', tipo: 'multicheck', opciones: herrRestoAlta,
            valor: (typeof LW_HERR_POR_ROL === 'object' && LW_HERR_POR_ROL[rolInicial]) || [], ayuda: 'Preselección según el rol elegido arriba — editable.' },
          { k: 'tipos_contrato', label: 'Contratos que puede hacer', tipo: 'multicheck', opciones: tiposCatAlta,
            valor: (typeof LW_TIPOS_POR_ROL === 'object' && LW_TIPOS_POR_ROL[rolInicial]) || [], ayuda: 'Preselección según el rol — vacío marcado del todo equivale a "todos".' }
        ], 'Crear usuario', function (v) {
          var email = (v.email || '').trim().toLowerCase();
          if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return { error: { message: 'email no válido' } };
          if ((v.password || '').length < 10) return { error: { message: 'la contraseña necesita 10 caracteres o más' } };
          var herramientas = (v.herr_crm || []).concat(v.herr_resto || []);
          // mismo endpoint que abreCambiaPassword: la Edge Function
          // admin-usuarios, nunca auth.admin desde el navegador.
          return sb.auth.getSession().then(function (r) {
            var token = r && r.data && r.data.session && r.data.session.access_token;
            if (!token) return { error: { message: 'sesión no encontrada' } };
            return fetch('https://vtulllundrfennhjddhc.supabase.co/functions/v1/admin-usuarios', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + token,
                'apikey': 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg'
              },
              body: JSON.stringify({
                // `v.rol` explícito (soySuperAlta) o `rolInicial` ('agente':
                // sin campo `k` en el formulario, no viaja en `v`) — nunca el
                // default implícito de la edge, que es el mismo valor pero
                // por casualidad, no por diseño.
                accion: 'crear', email: email, password: v.password,
                nombre: (v.nombre || '').trim(), rol: v.rol || rolInicial,
                herramientas: herramientas, tipos_contrato: v.tipos_contrato || []
              })
            }).then(function (resp) {
              return resp.json().catch(function () { return { error: 'respuesta ilegible del servidor' }; });
            }).then(function (d) {
              if (!d || !d.ok) return { error: { message: (d && d.error) || 'no se pudo crear' } };
              // Confirmación en los DOS sentidos (17-sep-2026 en la clásica,
              // misma regla aquí): el éxito también habla, no solo el fallo —
              // sin esto quien da de alta no sabe si el correo salió o no.
              if (d.email_enviado === false) {
                aviso('Usuario creado: ' + email + '. Aviso: no se pudo enviar el correo de bienvenida — dale la contraseña a mano.', '#8A6A34');
              } else {
                aviso('Usuario creado: ' + email + ' — correo de bienvenida enviado.');
              }
              // ?u=<email> es lo que hace que la recarga de abajo reabra la
              // ficha del recién creado — mismo mecanismo que ya usa abreFicha
              // en datos.js para «Guardar permisos». Solo si vino el user_id:
              // sin él no hay ficha que abrir y no se toca la URL.
              var u2 = new URL(location.href);
              u2.searchParams.delete('nuevo');
              if (d.user_id) u2.searchParams.set('u', email); else u2.searchParams.delete('u');
              history.replaceState(null, '', u2.href);
              // Recarga DIFERIDA a propósito: con `sinRecarga` modal() no
              // recarga sola, y este hueco es lo que deja tiempo a leer el
              // aviso de arriba —sobre todo el de "no se pudo enviar el
              // correo"— antes de que la página cambie debajo.
              setTimeout(function () { location.reload(); }, 2500);
              return {};
            });
          });
        }, { sinRecarga: true });
        // Preselección de Herramientas/Tipos según el rol elegido, recalculada
        // al cambiar el select — mismo patrón que $('#nRol').on('change') en
        // /intranet/usuarios/.
        var selRol = document.querySelector('#lw-editor [data-k="rol"]');
        if (selRol) selRol.addEventListener('change', function () {
          var rol = selRol.value;
          var herr = (typeof LW_HERR_POR_ROL === 'object' && LW_HERR_POR_ROL[rol]) || [];
          var tipos = (typeof LW_TIPOS_POR_ROL === 'object' && LW_TIPOS_POR_ROL[rol]) || [];
          var cajaResto = document.querySelector('#lw-editor [data-k="herr_resto"]');
          if (cajaResto) cajaResto.querySelectorAll('input').forEach(function (i) { i.checked = herr.indexOf(i.value) !== -1; });
          var cajaTipos = document.querySelector('#lw-editor [data-k="tipos_contrato"]');
          if (cajaTipos) cajaTipos.querySelectorAll('input').forEach(function (i) { i.checked = tipos.indexOf(i.value) !== -1; });
        });
      });
      /* `?nuevo=1` abre el alta sola (paridad 21-sep-2026, mismo patrón que
         Compradores/Facturas/Proyectos): quien llega desde otro sitio de la
         suite con la intención ya tomada no debería tener que encontrar el
         botón. Una sola vez, al cargar — no en cada repintado. */
      if (btnAlta && new URLSearchParams(location.search).get('nuevo') === '1') btnAlta.click();

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
              /* Vacio SI revoca aqui (correcto, como la clasica): "Proyectos"
                 no tiene el sentido invertido de tipos_contrato de abajo. */
              atajos: [{ texto: 'Marcar todos', valor: true }, { texto: 'Ninguno', valor: false }],
              ayuda: 'Limita en qué proyectos puede crear y editar contratos. Sin ninguno marcado, no puede crear en ninguno.' });
          } else {
            campos.push({ tipo: 'nota', label: 'No se pudo cargar el catálogo de proyectos: los suyos se conservan tal cual (no se tocan desde aquí hasta que cargue).' });
          }
          campos.push(
            { k: 'tipos_contrato', label: 'Contratos que puede hacer', tipo: 'multicheck',
              opciones: tiposCat, valor: u.tipos_contrato || [],
              /* SIN "Ninguno" aquí, a propósito (revisión previa Seguridad,
                 #35, 21-sep-2026): en `tipos_contrato` el array vacío
                 significa TODOS (ver `ayuda` de abajo), así que un atajo con
                 esa etiqueta CONCEDERÍA acceso a todo — justo lo contrario de
                 lo que promete. Se deja solo "Marcar todos", que sí es
                 coherente con su etiqueta; vaciar el campo se sigue pudiendo
                 hacer a mano, casilla a casilla, con el riesgo a la vista. */
              atajos: [{ texto: 'Marcar todos', valor: true }],
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
        if (!(window.LW_V4.usuariosLista || []).length) return aviso('La lista de usuarios aún no ha cargado — espera un momento y vuelve a pulsar.', '#8A6A34');
        modal('Nuevo equipo de venta', [
          { k: 'nombre', label: 'Nombre del equipo', req: 1 },
          { k: 'manager_email', label: 'Manager', tipo: 'select', req: 1, opciones: opsUsuarios('', '— elige un usuario —'),
            ayuda: 'la persona que gestiona el reparto del equipo; tiene que estar dada de alta en Usuarios' }
        ], 'Crear equipo', function (v) {
          return sb.from('equipos_venta').insert({
            nombre: v.nombre.trim(), manager_email: v.manager_email.trim().toLowerCase()
          });
        });
      });

      window.LW_V4.abreAnadirMiembro = function (equipoId, equipoNombre) {
        if (!admin) return soloAdmin();
        if (!(window.LW_V4.usuariosLista || []).length) return aviso('La lista de usuarios aún no ha cargado — espera un momento y vuelve a pulsar.', '#8A6A34');
        modal('Añadir miembro — ' + (equipoNombre || ''), [
          { k: 'closer_email', label: 'Closer', tipo: 'select', req: 1, opciones: opsUsuarios('', '— elige un usuario —'),
            ayuda: 'solo usuarios dados de alta en la intranet: el email es la clave con la que se le atribuyen ventas y comisiones' },
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
          { k: 'manager_email', label: 'Manager', tipo: 'select', req: 1, valor: (b.getAttribute('data-lw-manager') || '').toLowerCase(),
            opciones: opsUsuarios(b.getAttribute('data-lw-manager'), '— elige un usuario —'),
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
          { k: 'closer_email', label: 'Closer', tipo: 'select', req: 1, valor: (b.getAttribute('data-lw-email') || '').toLowerCase(),
            opciones: opsUsuarios(b.getAttribute('data-lw-email'), '— elige un usuario —'),
            ayuda: 'Es la clave con la que se le atribuyen ventas y comisiones: si estaba mal puesto, elegir el usuario correcto las reengancha.' },
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

      /* Una sola validación para crear y para editar (22-sep-2026). Devuelve
         `{error}` con el mensaje, o null si todo está bien. MISMA regla de
         suma que el trigger `condicion_tramos_suma_100` de la base — aquí
         ANTES de escribir nada, con un error legible y sin gastar un viaje de
         red; el trigger es el respaldo si esto se saltara. */
      function validaCondicion(v, tramos) {
        var err = function (m) { return { error: { message: m } }; };
        if (v.nivel === 'manager' && v.closer_email) return err('El override individual solo aplica con nivel «Closer».');
        if (!tramos.length) return err('Añade al menos un tramo de pago.');
        var suma = 0;
        for (var i = 0; i < tramos.length; i++) {
          var t = tramos[i], pct = Number(t.pct_tramo);
          if (!t.disparador_tipo) return err('Falta el disparador del tramo ' + (i + 1) + '.');
          if (!(pct > 0) || pct > 100) return err('El tramo ' + (i + 1) + ' necesita un % entre 0 y 100.');
          if (/^pct_cobrado_/.test(t.disparador_tipo) && (t.umbral === '' || t.umbral == null)) {
            return err('El tramo ' + (i + 1) + ' necesita un umbral (%) para ese disparador.');
          }
          suma += pct;
        }
        if (Math.abs(suma - 100) > 0.01) {
          return err('Los tramos suman ' + (Math.round(suma * 100) / 100) + '% — deben sumar exactamente 100% antes de guardar.');
        }
        if (v.base_calculo === 'importe_fijo' && !(Number(v.importe_fijo) > 0)) return err('La base «Importe fijo» exige un importe mayor que 0.');
        if (v.base_calculo !== 'importe_fijo' && v.importe_fijo) return err('El importe fijo solo aplica cuando la base es «Importe fijo».');
        return null;
      }
      function filasTramos(condId, tramos) {
        return tramos.map(function (t, i) {
          return {
            condicion_id: condId, orden: i + 1, disparador_tipo: t.disparador_tipo,
            umbral: /^pct_cobrado_/.test(t.disparador_tipo) ? Number(t.umbral) : null,
            pct_tramo: Number(t.pct_tramo)
          };
        });
      }

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
            { k: 'closer_email', label: 'Override individual', tipo: 'select', medio: 1,
              opciones: opsUsuarios('', '— todo el equipo —'),
              visibleSi: { k: 'nivel', valores: ['closer'] },
              ayuda: '«todo el equipo» aplica a cualquier closer del equipo; una persona concreta manda sobre eso' },
            { k: 'pct_comision', label: '% de comisión', tipo: 'number', paso: '0.01', req: 1, medio: 1 },
            { k: 'base_calculo', label: 'Base de cálculo', tipo: 'select', req: 1, medio: 1,
              opciones: (window.LW_V4.BASES_CALCULO || BASES_CALCULO_FALLBACK) },
            { k: 'importe_fijo', label: 'Importe fijo', tipo: 'number', paso: '0.01', medio: 1,
              visibleSi: { k: 'base_calculo', valores: ['importe_fijo'] } },
            { k: 'tramos', label: 'Tramos de pago (deben sumar 100%)', tipo: 'custom',
              render: function (d) { getTramos = montaTramos(d); } }
          ], 'Crear condición', function (v) {
            var tramos = getTramos ? getTramos() : [];
            var mal = validaCondicion(v, tramos);
            if (mal) return mal;
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
              return sb.from('condicion_tramos').insert(filasTramos(condId, tramos)).then(function (r2) {
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

      /* EDITAR (22-sep-2026, owner: «déjame editar condiciones de comisión una
         vez ya creadas»). Equipo, proyecto y nivel NO se cambian: son la
         identidad por la que el motor busca la condición — para otra terna se
         crea otra. Sí: %, base, importe fijo, override y los tramos. Los tramos
         solo mientras la condición no haya devengado nada: `comisiones_devengadas`
         cita cada tramo por id (FK NO ACTION) con su importe congelado, así que
         reescribirlos reescribiría la historia. Con devengos se editan solo la
         cabecera y se dice por qué. */
      window.LW_V4.abreEditaCondicion = function (b) {
        if (!admin) return soloAdmin();
        var id = b.getAttribute('data-lw-edita-cond'), etq = b.getAttribute('data-lw-etq') || '';
        var cond = (window.LW_V4.condicionesLista || {})[id];
        if (!cond) return aviso('No encuentro esa condición — recarga la página.', '#8A6A34');
        var tramosAct = ((window.LW_V4.tramosDe || {})[id] || []).slice().sort(function (x, y) { return x.orden - y.orden; });
        sb.from('comisiones_devengadas').select('id', { count: 'exact', head: true }).eq('condicion_id', id).then(function (r) {
          var n = r.error ? 0 : (r.count || 0);
          var getTramos = null;
          var campos = [
            { tipo: 'lectura', label: 'Equipo · proyecto', valor: etq },
            { tipo: 'lectura', label: 'Nivel', valor: cond.nivel === 'closer' ? 'Closer' : 'Manager', medio: 1 }
          ];
          if (cond.nivel === 'closer') {
            campos.push({ k: 'closer_email', label: 'Override individual', tipo: 'select', medio: 1,
              valor: cond.closer_email || '', opciones: opsUsuarios(cond.closer_email || '', '— todo el equipo —'),
              ayuda: '«todo el equipo» aplica a cualquier closer del equipo; una persona concreta manda sobre eso' });
          }
          campos.push(
            { k: 'pct_comision', label: '% de comisión', tipo: 'number', paso: '0.01', req: 1, medio: 1, valor: cond.pct_comision },
            { k: 'base_calculo', label: 'Base de cálculo', tipo: 'select', req: 1, medio: 1, valor: cond.base_calculo,
              opciones: (window.LW_V4.BASES_CALCULO || BASES_CALCULO_FALLBACK) },
            { k: 'importe_fijo', label: 'Importe fijo', tipo: 'number', paso: '0.01', medio: 1,
              valor: cond.importe_fijo == null ? '' : cond.importe_fijo,
              visibleSi: { k: 'base_calculo', valores: ['importe_fijo'] } });
          if (n) {
            campos.push({ tipo: 'nota', label: 'Esta condición ya ha devengado ' + n + (n === 1 ? ' comisión' : ' comisiones') +
              ': sus tramos no se tocan, porque cada devengo lleva su importe congelado sobre ellos. ' +
              'Para otro calendario de pago, desactívala y crea una nueva. Tramos actuales: ' +
              tramosAct.map(function (t) { return t.pct_tramo + '% ' + t.disparador_tipo + (t.umbral != null ? ' ' + t.umbral + '%' : ''); }).join(' · ') });
          } else {
            campos.push({ k: 'tramos', label: 'Tramos de pago (deben sumar 100%)', tipo: 'custom',
              render: function (d) { getTramos = montaTramos(d, tramosAct); } });
          }
          modal('Editar condición — ' + etq, campos, 'Guardar cambios', function (v) {
            v.nivel = cond.nivel;
            var tramos = n ? tramosAct : (getTramos ? getTramos() : []);
            var mal = validaCondicion(v, tramos);
            if (mal) return mal;
            var patch = {
              pct_comision: Number(v.pct_comision), base_calculo: v.base_calculo,
              importe_fijo: v.base_calculo === 'importe_fijo' ? Number(v.importe_fijo) : null
            };
            if (cond.nivel === 'closer') patch.closer_email = v.closer_email ? v.closer_email.trim().toLowerCase() : null;
            return sb.from('condiciones_comision').update(patch).eq('id', id).select('id').then(unaFila).then(function (r1) {
              if (r1.error || n) return r1;
              /* Sin devengos nadie cita estos tramos: se sustituyen enteros. En
                 UNA transacción (RPC): el trigger de suma 100 es DEFERRED y por
                 REST un DELETE suelto moriría al cerrar con los tramos a 0. */
              return sb.rpc('condicion_tramos_reemplaza', {
                p_condicion: id,
                p_tramos: filasTramos(id, tramos).map(function (f) {
                  return { disparador_tipo: f.disparador_tipo, umbral: f.umbral, pct_tramo: f.pct_tramo };
                })
              });
            });
          });
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
    },

    /* Sociedades emisoras (21-sep-2026, S9) — SOLO super admin, y no por
       gusto: la RLS de INSERT/UPDATE de `sociedades` exige es_super_admin(),
       asi que esto es UI, no el candado real.

       Alta y edicion son la logica de la herramienta clasica
       (intranet/sociedades/, 17-sep) PORTADA, no reescrita: mismo filtro del
       historial (solo los 7 campos FISCALES cuentan como identidad), mismo
       tratamiento de `es_indonesia` (se lee la columna, nunca se deriva de
       la clave — es el bug que se corrigio el 17-sep en
       sociedades_jurisdiccion.sql) y la misma inmutabilidad de `clave`.

       El payload de UPDATE es una ALLOWLIST de EXACTAMENTE las 16 columnas
       del GRANT (verificado contra contracts/sql/sociedades.sql +
       sociedades_jurisdiccion.sql) — `clave` nunca viaja, ni deshabilitada
       en el formulario: no esta en `camposEdicion()`, asi que ni siquiera se
       recoge. Si algun dia un campo se cuela en `payloadDesdeForm` sin
       ampliar antes el GRANT del .sql, mejor que lo rechace Postgres con
       42501 a la vista que enviar algo que la base iba a tirar de todas
       formas — el candado de abajo lo deja explicito. */
    'sociedades': function (aut) {
      var sb = aut.sb;
      var superAdmin = !!(aut.ficha && aut.ficha.rol === 'super_admin');
      window.LW_V4 = window.LW_V4 || {};

      var soloSuper = function () {
        return aviso('Sociedades emisoras es solo para super_admin — tu sesion es de ' +
          ((aut.ficha && aut.ficha.rol) || 'agente') + '.', '#8A6A34');
      };

      var TEXTO_ES_INDONESIA = 'Las nueve plantillas de contrato declaran al Promotor como «sociedad de ' +
        'nacionalidad Indonesia», y para esta sociedad eso es falso. Quien la use para FIRMAR un contrato ' +
        '—no solo para facturar— tiene que corregir esa clausula a mano antes de imprimir el documento final.';
      var TEXTO_LAW_235 = 'Las tres series de numeracion (INV, PRO y REC) son GLOBALES y las comparten ' +
        'todas las sociedades: esta empresa consumira la misma numeracion que las demas, asi que su serie ' +
        'propia tendra huecos. Aplazado por el owner el 17-sep (LAW-235) SOLO mientras todas las sociedades ' +
        'son del propio grupo Lawang — en cuanto se de de alta una que no lo sea, compartir la numeracion ' +
        'deja de ser aceptable y hay que separar las series antes, no despues.';

      // Los 16 campos del GRANT UPDATE, ni uno mas.
      var CAMPOS_UPDATE = ['label', 'razon', 'marca', 'npwp', 'npwp_label', 'nib', 'domicilio', 'rep',
        'logo', 'logo_alto', 'emisor_debajo', 'folio', 'tinta', 'activa', 'orden', 'es_indonesia'];

      function payloadDesdeForm(v) {
        var fila = {
          label: (v.label || '').trim() || (v.razon || '').trim(),
          razon: (v.razon || '').trim(), marca: (v.marca || '').trim(),
          npwp: (v.npwp || '').trim() || null, npwp_label: (v.npwp_label || '').trim() || 'NPWP',
          nib: (v.nib || '').trim() || null, domicilio: (v.domicilio || '').trim(),
          rep: (v.rep || '').trim() || null, logo: (v.logo || '').trim() || null,
          logo_alto: (v.logo_alto || '').trim() || null, folio: (v.folio || '').trim() || null,
          emisor_debajo: !!v.emisor_debajo, es_indonesia: !!v.es_indonesia, activa: !!v.activa,
          orden: Number(v.orden) || 0
        };
        // Objeto o nada — nunca `{primary:'',deep:''}`: eso lo aplicaria
        // documentoVars como override en blanco, no como "hereda el de marca".
        var tp = (v.tinta_primary || '').trim(), td = (v.tinta_deep || '').trim();
        fila.tinta = (tp || td) ? { primary: tp, deep: td } : null;
        var extra = Object.keys(fila).filter(function (k) { return CAMPOS_UPDATE.indexOf(k) === -1; });
        if (extra.length) return { error: { message: 'Candado de columnas: ' + extra.join(', ') + ' no estan en el GRANT de UPDATE de sociedades.' } };
        return fila;
      }

      function camposEdicion(s) {
        var base = [
          { tipo: 'lectura', label: 'Clave', medio: 1, valor: s.clave },
          { tipo: 'nota', label: 'La clave no se edita nunca: va dentro de cada contrato y cada factura ya emitidos.' },
          { k: 'razon', label: 'Razón social', req: 1, valor: s.razon },
          { k: 'marca', label: 'Marca', medio: 1, valor: s.marca },
          { k: 'label', label: 'Nombre en el desplegable', medio: 1, valor: s.label },
          { k: 'npwp_label', label: 'Etiqueta fiscal', medio: 1, valor: s.npwp_label || 'NPWP' },
          { k: 'npwp', label: 'Identificación fiscal', medio: 1, valor: s.npwp },
          { k: 'nib', label: 'NIB', medio: 1, valor: s.nib },
          { k: 'rep', label: 'Representante', medio: 1, valor: s.rep },
          { k: 'domicilio', label: 'Domicilio', tipo: 'textarea', req: 1, valor: s.domicilio },
          { k: 'es_indonesia', label: 'Es una sociedad indonesa (las plantillas lo declaran así)', tipo: 'check', valor: s.es_indonesia !== false }
        ];
        if (s.es_indonesia === false) base.push({ tipo: 'nota', label: TEXTO_ES_INDONESIA });
        return base.concat([
          { tipo: 'nota', label: 'Corregir esto NO cambia los documentos ya emitidos: cada factura guarda dentro la identidad con la que salió.' },
          { tipo: 'nota', label: 'Aspecto del documento — esto NO cambia lo que el documento dice.' },
          { k: 'logo', label: 'Logo', valor: s.logo, ayuda: '/contracts/assets/brand/…' },
          { k: 'logo_alto', label: 'Alto del logo', medio: 1, valor: s.logo_alto, ayuda: '24mm' },
          { k: 'folio', label: 'Folio', medio: 1, valor: s.folio, ayuda: '#E7E3D2' },
          { k: 'tinta_primary', label: 'Tinta principal', medio: 1, valor: (s.tinta || {}).primary, ayuda: '#662906' },
          { k: 'tinta_deep', label: 'Tinta oscura', medio: 1, valor: (s.tinta || {}).deep, ayuda: '#42210B' },
          { k: 'emisor_debajo', label: 'El emisor va DEBAJO del logo (para logos apaisados)', tipo: 'check', valor: s.emisor_debajo },
          { tipo: 'nota', label: 'En el catálogo.' },
          { k: 'orden', label: 'Orden', tipo: 'number', medio: 1, valor: s.orden || 0 },
          { k: 'activa', label: 'Activa — se ofrece al redactar contratos y facturas', tipo: 'check', valor: s.activa !== false },
          { tipo: 'nota', label: 'Una sociedad no se borra, se desactiva: sus documentos emitidos siguen apuntando a ella.' }
        ]);
      }

      // ── Editar una sociedad que ya existe ───────────────────────────────
      window.LW_V4.abreEditaSociedad = function (btn) {
        if (!superAdmin) return soloSuper();
        var clave = btn.getAttribute ? btn.getAttribute('data-lw-soc-editar') : btn;
        var s = (window.LW_V4.sociedadesPorClave && window.LW_V4.sociedadesPorClave[clave]) || null;
        if (!s) return aviso('No se ha podido leer esta sociedad — recarga la pantalla.', '#9E2F26');

        modal('Editar sociedad — ' + s.razon, camposEdicion(s), 'Guardar cambios', function (v) {
          var fila = payloadDesdeForm(v);
          if (fila.error) return fila;

          function guarda() {
            return sb.from('sociedades').update(fila).eq('clave', s.clave).select('clave').single();
          }

          // Desactivar una sociedad YA EXISTENTE (nunca aplica en el alta):
          // antes de dejar seguir, comprobar si tiene facturas o proformas
          // sin anular. Si las tiene, bloqueante con DOBLE confirmacion — no
          // un aviso pasivo. Si no las tiene, se guarda directo.
          var desactivando = (s.activa !== false) && !fila.activa;
          if (!desactivando) return guarda();

          // `facturas` (Lawang: comprador<->contrato), NUNCA `axisworks_facturas`
          // (facturacion del propio ESTUDIO a sus clientes, tabla ajena — RLS
          // sin ninguna policy para `authenticated`, ni `sociedad` ni `tipo`
          // existen ahi. Confundir las dos bloqueaba SIEMPRE la desactivacion,
          // con un mensaje de "no se ha podido comprobar" que escondia el
          // verdadero motivo — cazado en la autorrevision de code-review.
          return aseguraModulosDoc(['dialogo']).then(function () {
            return Promise.all([
              sb.from('facturas').select('id', { count: 'exact', head: true }).eq('sociedad', s.clave).eq('anulada', false).eq('tipo', 'factura'),
              sb.from('facturas').select('id', { count: 'exact', head: true }).eq('sociedad', s.clave).eq('anulada', false).eq('tipo', 'proforma')
            ]);
          }).then(function (r) {
            if (r[0].error || r[1].error) {
              var e = r[0].error || r[1].error;
              return { error: { message: 'No se ha podido comprobar si esta sociedad tiene facturas o proformas sin anular, y por seguridad no se desactiva sin saberlo: ' + e.message } };
            }
            var nf = r[0].count || 0, np = r[1].count || 0;
            if (!nf && !np) return guarda();

            return window.lwConfirmar({
              titulo: 'Desactivar ' + s.razon,
              cuerpo: 'Esta sociedad tiene <b>' + nf + '</b> factura(s) y <b>' + np + '</b> proforma(s) sin anular. ' +
                'Desactivarla no toca los documentos ya emitidos, pero impide emitir o convertir proformas nuevas con esta clave.',
              confirmar: 'Sí, quiero desactivarla', tono: 'peligro'
            }).then(function (ok1) {
              if (!ok1) return { error: { message: 'Cancelado: la sociedad sigue activa.' } };
              return window.lwConfirmar({
                titulo: 'Confírmalo una segunda vez',
                cuerpo: 'Vas a desactivar <b>' + esc(s.razon) + '</b> con ' + nf + ' factura(s) y ' + np +
                  ' proforma(s) todavía sin anular.',
                confirmar: 'Confirmar desactivación', tono: 'peligro'
              }).then(function (ok2) {
                if (!ok2) return { error: { message: 'Cancelado: la sociedad sigue activa.' } };
                return guarda();
              });
            });
          });
        }, { sub: 'Sociedades emisoras' });
      };

      // ── Nueva sociedad ───────────────────────────────────────────────────
      var btnNueva = document.getElementById('btn-nueva-sociedad');
      if (btnNueva) {
        if (superAdmin) btnNueva.hidden = false;
        btnNueva.addEventListener('click', function () {
          if (!superAdmin) return soloSuper();
          var socs = window.LW_V4.sociedadesPorClave || {};
          var maxOrden = Object.keys(socs).reduce(function (m, k) { return Math.max(m, socs[k].orden || 0); }, 0);

          modal('Nueva sociedad', [
            { tipo: 'nota', label: 'Se dará de alta en el catálogo y aparecerá en el desplegable de sociedad firmante.' },
            { k: 'clave', label: 'Clave', req: 1,
              ayuda: 'minúsculas, números y guion bajo, sin espacios — por ejemplo mi_empresa_sa. No se puede cambiar después: nunca.' },
            { k: 'razon', label: 'Razón social', req: 1 },
            { k: 'domicilio', label: 'Domicilio', tipo: 'textarea', req: 1 },
            { k: 'marca', label: 'Marca', medio: 1 },
            { k: 'label', label: 'Nombre en el desplegable', medio: 1 },
            { k: 'npwp_label', label: 'Etiqueta fiscal', medio: 1, valor: 'NPWP' },
            { k: 'npwp', label: 'Identificación fiscal', medio: 1 },
            { k: 'nib', label: 'NIB', medio: 1 },
            { k: 'rep', label: 'Representante', medio: 1 },
            { k: 'es_indonesia', label: 'Es una sociedad indonesa (las plantillas lo declaran así)', tipo: 'check', valor: true },
            { k: 'npwp_pendiente', label: 'Sin NIF fiscal, pendiente — no apta para emitir documentos hasta completarse', tipo: 'check',
              ayuda: 'marca esto SOLO si de verdad todavía no se tiene el NPWP; la sociedad queda visible en el listado con este aviso hasta que se complete' },
            { k: 'cesion_dpa_firmado', label: 'Confirmo que el contrato de cesión y el DPA con esta sociedad ya están firmados', tipo: 'check',
              ayuda: 'obligatorio si la sociedad NO es indonesia, o en general si no es una de las 2-3 del propio grupo Lawang' },
            { tipo: 'nota', label: TEXTO_LAW_235 },
            { tipo: 'nota', label: 'Aspecto del documento.' },
            { k: 'logo', label: 'Logo', ayuda: '/contracts/assets/brand/…' },
            { k: 'logo_alto', label: 'Alto del logo', medio: 1, ayuda: '24mm' },
            { k: 'folio', label: 'Folio', medio: 1, ayuda: '#E7E3D2' },
            { k: 'tinta_primary', label: 'Tinta principal', medio: 1, ayuda: '#662906' },
            { k: 'tinta_deep', label: 'Tinta oscura', medio: 1, ayuda: '#42210B' },
            { k: 'emisor_debajo', label: 'El emisor va DEBAJO del logo (para logos apaisados)', tipo: 'check' },
            { k: 'orden', label: 'Orden', tipo: 'number', medio: 1, valor: maxOrden + 1 }
          ], 'Dar de alta', function (v) {
            var clave = (v.clave || '').toLowerCase();
            if (!/^[a-z0-9_]+$/.test(clave)) {
              return { error: { message: 'La clave solo admite minúsculas, números y guion bajo, sin espacios — por ejemplo mi_empresa_sa. No se puede cambiar después.' } };
            }
            if (socs[clave]) return { error: { message: 'Ya existe una sociedad con esa clave.' } };
            if (v.es_indonesia && !(v.npwp || '').trim() && !v.npwp_pendiente) {
              return { error: { message: 'Falta la identificación fiscal (NPWP). Si de verdad todavía no se tiene, marca la casilla «Sin NIF fiscal, pendiente».' } };
            }
            if (!v.es_indonesia && !v.cesion_dpa_firmado) {
              return { error: { message: 'Para una sociedad que no es indonesa hay que confirmar antes que el contrato de cesión y el DPA ya están firmados.' } };
            }
            var fila = payloadDesdeForm(v);
            if (fila.error) return fila;
            fila.clave = clave;
            fila.activa = true;   // nace activa siempre; desactivarla es un paso aparte, ya existiendo
            return sb.from('sociedades').insert(fila).select('clave').single();
          });
        });
      }
    },

    /* "Nuevo documento" (21-sep-2026): abre el editor nativo de factura/
       proforma — ver el bloque «EMISIÓN DE FACTURAS…» más arriba. Nunca
       navega a /intranet/facturas/. */
    facturas: function () {
      ata(/^\+? ?Nuevo documento$/i, function () { abrirEditorFacturaDoc({}); });
      /* Proforma desde contrato (S14, 21-sep-2026, revisión previa #34): la
         ficha de contrato v4 enlaza aquí con ?contrato=<uuid>&tipo=proforma en
         vez de abrir el editor ella misma -- cargar editores.js en
         contratos/index.html sería el acoplamiento cruzado que Seguridad pidió
         evitar. Se dispara una vez, al cargar esta pantalla; el listado de
         abajo (datos.js, REG.facturas) se pinta igual por debajo, sin saberlo. */
      /* Retirado el 22-sep-2026 (owner): la proforma la genera el contrato al
         guardarse; ya no se emite a mano desde ninguna pantalla. `?contrato=`
         sin tipo sigue abriendo el editor de FACTURA con ese contrato. */
      var qsContrato = new URLSearchParams(location.search);
      if (qsContrato.get('contrato') && qsContrato.get('tipo') !== 'proforma') {
        abrirEditorFacturaDoc({ contrato_id: qsContrato.get('contrato') });
      }
    },

    /* "+ Emitir recibí de cobro" (21-sep-2026): mismo bloque, camino RPC. */
    recibos: function () {
      ata(/emitir recib.*de cobro/i, function () { abrirEditorRecibiDoc({}); });
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
