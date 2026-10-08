/* cx_campos.js — la parte PURA de los «campos propios» de cada empresa ({{cx_algo}}), 8-oct-2026.
   Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md), E8 (catálogo en la base) y su configurador.
   Sin DOM, sin red: corre igual en el navegador y en node (contracts/campos_propios_config.test.js).

   LO USAN DOS PANTALLAS, por eso vive en contracts/assets/ y no dentro de ninguna: el configurador (intranet/v4/textos-contrato/) y el formulario del
   generador (contracts/app.html). Un mismo dato en dos sitios (cómo se llama la clave, qué tipo de casilla corresponde a cada tipo) es justo lo que
   acaba divergiendo.

   QUIÉN MANDA. El navegador NO valida nada de verdad: el catálogo, los tipos, las opciones y los valores los decide la base (tabla
   plantilla_campos_propios + trigger en `contratos` + RPC plantilla_campo_propio_valida). Todo lo de aquí es AYUDA: sacar una clave del nombre, elegir qué
   casilla pintar y poner en llano lo que contesta la base. NO hay aquí un segundo lector de números: el único es el del servidor (lw_importe). */
(function (raiz) {
  'use strict';

  var CX = {};

  /* Los seis tipos que admite la base (CHECK campo_propio_tipo). El rótulo se traduce al pintarlo. */
  CX.TIPOS = [['texto', 'Texto'], ['numero', 'Número'], ['fecha', 'Fecha'], ['importe', 'Importe'], ['lista', 'Lista de opciones'], ['si_no', 'Sí / No']];

  /* Nombre → clave. `cx_` + el nombre sin tildes, en minúsculas, con guiones bajos; la base exige ^cx_[a-z0-9_]{1,40}$. Devuelve null si el nombre no da ni una letra. */
  CX.claveDeNombre = function (nombre) {
    var s = String(nombre == null ? '' : nombre).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
      .replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40).replace(/_+$/g, '');
    return s ? 'cx_' + s : null;
  };
  CX.claveValida = function (k) { return /^cx_[a-z0-9_]{1,40}$/.test(String(k)); };

  /* Las opciones de una lista, escritas separadas por comas o por saltos de línea → { opciones, errores }. Las reglas son las de la base (1-50, de 1 a 80 caracteres,
     sin < > { }); aquí solo se avisa antes de pulsar, la base dice la última palabra. Sin repetidas. */
  CX.opcionesDeTexto = function (txt) {
    var vistas = {}, out = [], errores = [];
    String(txt == null ? '' : txt).split(/[,\n;]+/).forEach(function (x) {
      var o = x.replace(/\s+/g, ' ').trim();
      if (!o || vistas[o]) return;
      vistas[o] = true; out.push(o);
    });
    if (!out.length) errores.push('Escribe al menos una opción.');
    if (out.length > 50) errores.push('Una lista admite como mucho 50 opciones.');
    if (out.some(function (o) { return o.length > 80; })) errores.push('Cada opción puede tener hasta 80 letras.');
    if (out.some(function (o) { return /[<>{}]/.test(o); })) errores.push('Las opciones no admiten los signos < > { }.');
    return { opciones: out, errores: errores };
  };

  /* La etiqueta de un campo del catálogo en el idioma pedido (la de cada idioma si la hay, si no la española). `c.etiqueta` = { es, en, id } como lo devuelve plantilla_campo_propio_lista. */
  CX.etiqueta = function (c, idioma) {
    var e = (c && c.etiqueta) || {};
    return e[idioma] || e.es || (c && c.clave) || '';
  };

  /* Un campo del catálogo → la definición que entiende el formulario del generador: [clave, {es,en,id}, tipoDeCasilla, extra].
     numero e importe usan la casilla de dinero (texto con coma o punto, no <input type=number>): en una casilla numérica del navegador «1.500» vale 1,5 y el
     servidor lo lee como 1500 — se deja que lo lea UNO solo, el del servidor. `siNo` = { si, no }: los rótulos ya traducidos; el valor guardado es siempre «si» / «no». */
  CX.tipoForm = function (c, siNo) {
    var et = { es: CX.etiqueta(c, 'es'), en: CX.etiqueta(c, 'en'), id: CX.etiqueta(c, 'id') };
    var t = c.tipo;
    if (t === 'fecha') return [c.clave, et, 'date'];
    if (t === 'numero' || t === 'importe') return [c.clave, et, 'money'];
    if (t === 'lista') return [c.clave, et, 'select', (c.opciones || []).slice()];
    if (t === 'si_no') return [c.clave, et, 'select', [['si', (siNo && siNo.si) || 'Sí'], ['no', (siNo && siNo.no) || 'No']]];
    return [c.clave, et, 'text'];
  };

  /* Valor de ejemplo para la pastilla y la simulación del texto (no es de ningún contrato). */
  CX.ejemplo = function (c) {
    switch (c && c.tipo) {
      case 'numero': return '1.000';
      case 'importe': return '100.000';
      case 'fecha': return '2030-01-01';
      case 'lista': return (c.opciones && c.opciones[0]) || 'Opción';
      case 'si_no': return 'Sí';
      default: return 'Texto de muestra';
    }
  };

  /* Cómo se imprime un valor guardado en el documento. Solo «si» / «no» cambian (se guardan sin tilde y en minúsculas, y en el documento se leen en su idioma);
     el resto se imprime tal cual lo dejó la base (forma canónica). `idioma` = es | en | id. */
  CX.paraDocumento = function (c, valor, idioma) {
    var v = valor == null ? '' : String(valor);
    if (c && c.tipo === 'si_no') {
      var m = { es: { si: 'Sí', no: 'No' }, en: { si: 'Yes', no: 'No' }, id: { si: 'Ya', no: 'Tidak' } }[idioma] || { si: 'Sí', no: 'No' };
      return Object.prototype.hasOwnProperty.call(m, v) ? m[v] : v;
    }
    return v;
  };

  /* ── lo que contesta la base, en llano ─────────────────────────────────────────────────────────────────────────────────────────── */
  /* Los mensajes de la base se reconocen por su PRINCIPIO (estable: contracts/campos_propios_config.test.js lee la migración E8 y falla si uno cambia). */
  CX.PREFIJOS_BASE = [
    ['admin', /^Los campos propios de una empresa los escribe su administracion/], ['sesion', /^Sin sesion/i],
    ['clave', /^La clave de un campo propio empieza por cx_/], ['tipo_invalido', /^Tipo de campo no valido/],
    ['lista', /^Una lista lleva de 1 a 50 opciones/], ['solo_lista', /^Solo una lista lleva opciones/],
    ['choque', /^La clave .* choca con un campo del sistema/], ['tope', /^Una empresa puede tener como mucho 200 campos propios/],
    ['tipo_en_uso', /^El tipo de .* no cambia/], ['opciones_en_uso', /^En .* solo se pueden anadir opciones/],
    ['borrar_en_uso', /^No se borra /], ['no_existe', /^Ese campo propio no existe/],
    ['etiqueta', /campo_propio_etiquetas/]
  ];
  CX.clasificaError = function (msg) {
    var m = String(msg == null ? '' : msg).trim();
    for (var i = 0; i < CX.PREFIJOS_BASE.length; i++) if (CX.PREFIJOS_BASE[i][1].test(m)) return { tipo: CX.PREFIJOS_BASE[i][0], detalle: m };
    return { tipo: 'otro', detalle: m };
  };
  /* «lo usan 2 version(es) y 3 contrato(s)» → { versiones, contratos } o null. */
  CX.usoDeError = function (msg) {
    var m = /lo usan (\d+) version\(es\) y (\d+) contrato\(s\)/.exec(String(msg || ''));
    return m ? { versiones: +m[1], contratos: +m[2] } : null;
  };

  /* El error de UN valor que devuelve plantilla_campo_propio_valida / _cx_valor → la frase en llano (clave del diccionario inglés). null = no se reconoce (se enseña el mensaje tal cual). */
  CX.FRASES_VALOR = {
    no_numero: 'No es un número. Escribe solo cifras, con punto o coma.',
    demasiado_grande: 'El número es demasiado grande.',
    importe_negativo: 'Un importe no puede ser negativo.',
    importe_decimales: 'Un importe lleva como mucho dos decimales.',
    fecha_forma: 'La fecha tiene que tener la forma año-mes-día.',
    fecha_rango: 'Esa fecha no existe o está fuera de rango.',
    lista_opcion: 'Elige una de las opciones de la lista.',
    si_no: 'Elige Sí o No.',
    largo: 'El texto es demasiado largo (200 letras como mucho).',
    signos: 'No se pueden usar los signos < > { } en un campo.',
    tipo_valor: 'El valor tiene que ser un texto o un número.',
    sin_catalogo: 'Este campo ya no está en el catálogo de campos de la empresa.',
    archivado: 'Este campo está archivado y ya no admite valores nuevos.',
    clave_forma: 'Un campo tiene una clave que no es válida.'
  };
  CX.clasificaValor = function (err) {
    var e = String(err == null ? '' : err);
    if (/^no es un numero/.test(e)) return 'no_numero';
    if (/^numero demasiado grande/.test(e)) return 'demasiado_grande';
    if (/^un importe no es negativo/.test(e)) return 'importe_negativo';
    if (/^un importe lleva como mucho 2 decimales/.test(e)) return 'importe_decimales';
    if (/^la fecha va como/.test(e)) return 'fecha_forma';
    if (/^fecha que no existe|^fecha fuera de rango/.test(e)) return 'fecha_rango';
    if (/^no es una de las opciones/.test(e)) return 'lista_opcion';
    if (/^solo .si. o .no./.test(e)) return 'si_no';
    if (/^mas de 200 caracteres/.test(e)) return 'largo';
    if (/^no admite los signos/.test(e)) return 'signos';
    if (/^el valor debe ser un texto o un numero/.test(e)) return 'tipo_valor';
    if (/^no esta en el catalogo/.test(e)) return 'sin_catalogo';
    if (/^campo archivado/.test(e)) return 'archivado';
    if (/^no es una clave de campo propio/.test(e)) return 'clave_forma';
    return null;
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = CX;
  else raiz.LW_CX = CX;
})(typeof window !== 'undefined' ? window : this);
