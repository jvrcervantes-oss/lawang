/* campos_propios_config.test.js — los campos propios de la empresa ({{cx_algo}}) en el configurador y en el formulario del contrato (E8, 8-oct-2026).
   `node contracts/campos_propios_config.test.js` desde la raíz de Lawang (lo recoge tools/test.py).

   Qué afirma, y por qué cada cosa:
   · LO QUE VIVE EN DOS SITIOS no se separa. La forma de la clave (cx_[a-z0-9_]{1,40}), la lista de tipos y los mensajes de la base que el navegador reconoce se
     leen de la migración E8 (supabase/migrations/20261010010000_f2_editor_e8_campos_propios.sql): si alguien cambia el CHECK o reescribe un mensaje, esto falla antes
     de que la pantalla deje de entenderlo.
   · EL NAVEGADOR NO INTERPRETA NÚMEROS: cx_campos.js no tiene un segundo lector de importes (lw_importe del servidor es el único) y los números/importes usan la casilla de
     dinero, no <input type=number> (donde «1.500» vale 1,5 y el servidor lo lee como 1500).
   · EL FORMULARIO DEL CONTRATO (contracts/app.html) carga el catálogo, monta su sección sin dejar los cx_ como texto libre, y pregunta a la base ANTES de guardar. */
'use strict';
const fs = require('fs');
const path = require('path');
const CX = require('./assets/cx_campos.js');

const RAIZ = path.join(__dirname, '..');
const leer = (...r) => fs.readFileSync(path.join(RAIZ, ...r), 'utf8');
const errores = [];
const falla = (m) => errores.push(m);
const igual = (a, b, m) => { if (a !== b) falla(m + ' — esperado ' + JSON.stringify(String(b).slice(0, 80)) + ', recibido ' + JSON.stringify(String(a).slice(0, 80))); };

const sql = leer('supabase', 'migrations', '20261010010000_f2_editor_e8_campos_propios.sql');

/* ── la clave sale del nombre ── */
igual(CX.claveDeNombre('Garaje incluido'), 'cx_garaje_incluido', 'clave: minúsculas y guiones bajos');
igual(CX.claveDeNombre('Fecha de entrega de llaves'), 'cx_fecha_de_entrega_de_llaves', 'clave: varias palabras');
igual(CX.claveDeNombre('  Número de Habitación  nº 2 '), 'cx_numero_de_habitacion_n_2', 'clave: sin tildes, sin espacios sobrantes');
igual(CX.claveDeNombre('Año de construcción'), 'cx_ano_de_construccion', 'clave: la ñ pierde la tilde');
igual(CX.claveDeNombre('¡¡¡'), null, 'clave: sin letras ni cifras no hay clave');
igual(CX.claveDeNombre(''), null, 'clave: vacío no hay clave');
{
  const larga = CX.claveDeNombre('Un nombre larguísimo para un campo que no cabe en cuarenta caracteres de ninguna manera');
  igual(CX.claveValida(larga), true, 'clave: un nombre largo se recorta a una clave válida');
  igual(larga.length <= 43, true, 'clave: como mucho cx_ + 40');
}
// la forma de la clave es la del CHECK de la base
{
  const m = /constraint campo_propio_clave\s+check \(clave ~ '([^']+)'\)/.exec(sql);
  if (!m) falla('no encuentro el CHECK campo_propio_clave en la migración E8');
  else {
    const re = new RegExp(m[1]);
    ['cx_a', 'cx_' + 'a'.repeat(40), 'cx_a_1'].forEach((k) => igual(re.test(k) && CX.claveValida(k), true, k.slice(0, 12) + ': válida para la base y para el navegador'));
    ['cx_', 'cx_' + 'a'.repeat(41), 'CX_a', 'cx_A', 'cx_a-b', 'x_a'].forEach((k) => igual(!re.test(k) && !CX.claveValida(k), true, k.slice(0, 12) + ': inválida para los dos'));
  }
}

/* ── los tipos son los de la base ── */
{
  const m = /constraint campo_propio_tipo\s+check \(tipo in \(([^)]*)\)\)/.exec(sql);
  if (!m) falla('no encuentro el CHECK campo_propio_tipo en la migración E8');
  else igual(CX.TIPOS.map((t) => t[0]).sort().join(), [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort().join(), 'los tipos del configurador == los del CHECK de la base');
}

/* ── opciones de una lista ── */
{
  const o = CX.opcionesDeTexto('Transferencia, Efectivo ,Cripto,\nEfectivo');
  igual(o.opciones.join('|'), 'Transferencia|Efectivo|Cripto', 'opciones: separadas por comas o saltos, sin repetidas');
  igual(o.errores.length, 0, 'opciones: sin avisos');
  igual(CX.opcionesDeTexto('').errores.length, 1, 'opciones: vacío se avisa');
  igual(CX.opcionesDeTexto('a, <b>').errores.length, 1, 'opciones: < > { } se avisan');
  igual(CX.opcionesDeTexto(Array.from({ length: 51 }, (_, i) => 'o' + i).join(',')).errores.length, 1, 'opciones: más de 50 se avisa');
  igual(CX.opcionesDeTexto('x'.repeat(81)).errores.length, 1, 'opciones: más de 80 letras se avisa');
}

/* ── de un campo del catálogo a la casilla del formulario ── */
{
  const c = (tipo, extra) => Object.assign({ clave: 'cx_x', tipo, etiqueta: { es: 'Uno', en: 'One', id: null } }, extra || {});
  const t = (x) => CX.tipoForm(x, { si: 'Sí', no: 'No' });
  igual(t(c('texto'))[2], 'text', 'texto → casilla de texto');
  igual(t(c('fecha'))[2], 'date', 'fecha → casilla de fecha');
  igual(t(c('importe'))[2], 'money', 'importe → casilla de dinero (no <input type=number>)');
  igual(t(c('numero'))[2], 'money', 'número → casilla de dinero: lo lee el servidor, no el navegador');
  igual(t(c('lista', { opciones: ['A', 'B'] }))[3].join(), 'A,B', 'lista → select con sus opciones');
  igual(JSON.stringify(t(c('si_no'))[3]), JSON.stringify([['si', 'Sí'], ['no', 'No']]), 'sí/no → valores «si» / «no» (los que acepta la base) y rótulos traducidos');
  igual(t(c('texto'))[1].es + '|' + t(c('texto'))[1].en + '|' + t(c('texto'))[1].id, 'Uno|One|Uno', 'etiqueta: cada idioma, y el español donde falta');
  igual(CX.etiqueta(c('texto'), 'en'), 'One', 'etiqueta en inglés');
  igual(CX.etiqueta({ clave: 'cx_q' }, 'es'), 'cx_q', 'etiqueta: sin nombre, la clave (nunca vacío)');
  igual(CX.paraDocumento(c('si_no'), 'si', 'es'), 'Sí', 'documento: sí');
  igual(CX.paraDocumento(c('si_no'), 'no', 'en'), 'No', 'documento: no');
  igual(CX.paraDocumento(c('importe'), '100000', 'es'), '100000', 'documento: un importe se imprime como lo dejó la base');
  igual(CX.ejemplo(c('lista', { opciones: ['Z'] })), 'Z', 'ejemplo de una lista: su primera opción');
}
// el módulo no lee números ni fechas: eso es del servidor
{
  const src = leer('contracts', 'assets', 'cx_campos.js');
  if (/parseFloat|parseInt|Number\(|Date\.parse|new Date|lwParseImporte|parseImporte/.test(src.replace(/\/\*[\s\S]*?\*\//g, ''))) falla('cx_campos.js interpreta un número o una fecha: lo único que los lee es el servidor');
  if (/\.rpc\(|fetch\(|XMLHttpRequest|localStorage|document\./.test(src.replace(/\/\*[\s\S]*?\*\//g, ''))) falla('cx_campos.js debe ser puro: sin red, sin DOM, sin almacenamiento');
}

/* ── los mensajes de la base que reconoce el navegador siguen en la migración ── */
{
  const literal = {
    admin: 'Los campos propios de una empresa los escribe su administracion', sesion: 'Sin sesion: vuelve a entrar', clave: 'La clave de un campo propio empieza por cx_',
    tipo_invalido: 'Tipo de campo no valido', lista: 'Una lista lleva de 1 a 50 opciones', solo_lista: 'Solo una lista lleva opciones', choque: 'choca con un campo del sistema',
    tope: 'Una empresa puede tener como mucho 200 campos propios', tipo_en_uso: 'no cambia: lo usan', opciones_en_uso: 'solo se pueden anadir opciones',
    borrar_en_uso: 'No se borra %', no_existe: 'Ese campo propio no existe', etiqueta: 'campo_propio_etiquetas'
  };
  igual(Object.keys(literal).sort().join(), CX.PREFIJOS_BASE.map((x) => x[0]).sort().join(), 'cada clase de error de un campo tiene su mensaje comprobado');
  Object.keys(literal).forEach((k) => { if (sql.indexOf(literal[k]) === -1) falla('el mensaje de la base «' + literal[k] + '» ya no está en la migración E8: la pantalla dejaría de reconocer «' + k + '»'); });
  igual(CX.clasificaError('La clave de un campo propio empieza por cx_ y sigue con hasta 40 letras').tipo, 'clave', 'clasifica una clave inválida');
  igual(CX.clasificaError('Los campos propios de una empresa los escribe su administracion').tipo, 'admin', 'clasifica el permiso');
  igual(CX.clasificaError('El tipo de cx_x no cambia: lo usan 1 version(es) y 2 contrato(s). Archivalo').tipo, 'tipo_en_uso', 'clasifica el tipo en uso');
  igual(CX.clasificaError('No se borra cx_x : lo usan 1 version(es) y 2 contrato(s). Archivalo').tipo, 'borrar_en_uso', 'clasifica el borrado de un campo en uso');
  igual(CX.clasificaError('En cx_x solo se pueden anadir opciones: ya lo usan 1 version(es) y 2 contrato(s)').tipo, 'opciones_en_uso', 'clasifica las opciones de un campo en uso');
  igual(CX.clasificaError('new row for relation "plantilla_campos_propios" violates check constraint "campo_propio_etiquetas"').tipo, 'etiqueta', 'clasifica una etiqueta inválida');
  igual(JSON.stringify(CX.usoDeError('No se borra cx_x : lo usan 1 version(es) y 2 contrato(s). Archivalo')), JSON.stringify({ versiones: 1, contratos: 2 }), 'saca el uso del mensaje');
  igual(CX.usoDeError('otra cosa'), null, 'sin uso, null');
  // los errores de UN valor (los que devuelve _cx_valor / plantilla_campo_propio_valida)
  const valores = {
    no_numero: 'no es un numero (solo cifras, punto y coma)', demasiado_grande: 'numero demasiado grande', importe_negativo: 'un importe no es negativo',
    importe_decimales: 'un importe lleva como mucho 2 decimales', fecha_forma: 'la fecha va como AAAA-MM-DD', fecha_rango: 'fecha fuera de rango (1900-2200) o que no existe',
    lista_opcion: 'no es una de las opciones del campo', si_no: 'solo «si» o «no»', largo: 'mas de 200 caracteres', signos: 'no admite los signos < > { }',
    tipo_valor: 'el valor debe ser un texto o un numero', sin_catalogo: 'no esta en el catalogo de esta empresa', archivado: 'campo archivado: ya no admite valores nuevos',
    clave_forma: 'no es una clave de campo propio'
  };
  igual(Object.keys(valores).sort().join(), Object.keys(CX.FRASES_VALOR).sort().join(), 'cada frase en llano de un valor tiene su mensaje de la base');
  Object.keys(valores).forEach((k) => {
    if (sql.indexOf(valores[k]) === -1) falla('el mensaje de valor «' + valores[k] + '» ya no está en la migración E8');
    igual(CX.clasificaValor(valores[k]), k, 'clasificaValor reconoce «' + valores[k] + '»');
  });
  igual(CX.clasificaValor('algo raro'), null, 'un error de valor desconocido no se traduce (se enseña tal cual)');
}

/* ── el formulario del contrato (contracts/app.html) ── */
{
  const app = leer('contracts', 'app.html');
  const i = (txt, m) => igual(app.indexOf(txt) !== -1, true, m);
  i('<script src="assets/cx_campos.js', 'app.html carga cx_campos.js');
  igual(app.indexOf('assets/cx_campos.js') < app.indexOf('async function cargarCamposCx'), true, 'cx_campos.js se carga antes de usarse');
  i("sb.rpc('plantilla_campo_propio_lista', { p_empresa: emp, p_con_uso: false })", 'carga el catálogo con la lista entera (también los sensibles: el formulario los necesita)');
  igual(/plantilla_campos_cx_publicos/.test(app), false, 'el formulario no usa la lista pública: esa quita los sensibles');
  i('await cargarCamposCx();', 'loadTemplate carga el catálogo antes de montar el formulario');
  igual(app.indexOf('await cargarCamposCx();') < app.indexOf('function deriveSections') + 100000 && app.indexOf('await cargarCamposCx();') > app.indexOf('async function loadTemplate'), true, 'y lo hace dentro de loadTemplate');
  i("id:'campos_propios'", 'los cx_ tienen su propia sección');
  i('const cxClaves = CX_CAT ? missingTodos.filter', 'los cx_ no caen en «Otros campos» cuando hay catálogo');
  i("CAMPOS_OPCIONALES[c.obligatorio ? 'delete' : 'add'](k)", 'obligatorio / opcional se refleja en el candado de campos sin rellenar');
  i('LW_CX.tipoForm(c, siNo)', 'el tipo de casilla sale de LW_CX.tipoForm (una sola definición)');
  // se pregunta a la base antes de guardar
  const iVal = app.indexOf("sb.rpc('plantilla_campo_propio_valida'"), iOk = app.indexOf('let guardadoOk = false;'), iIns = app.indexOf('await sb.from(\'contratos\')');
  igual(iVal > -1 && iVal < iOk, true, 'guardarContrato pregunta a plantilla_campo_propio_valida ANTES de empezar a guardar');
  igual(/rv\.ok === false/.test(app) && /avisoNoGuardado\(lwT\('Revisa los campos de la empresa\. '\)/.test(app), true, 'y si la base dice que no, se para y se dice en llano');
  igual(/MUDO A PROPOSITO: sin la comprobación previa decide el trigger/.test(app), true, 'el catch silencioso de la pregunta dice por qué');
  // el trigger de la base es el que manda de verdad
  igual(/create trigger trg_contrato_campos_propios before insert or update of datos on public\.contratos/.test(sql), true, 'la base comprueba los valores en un trigger de contratos, no solo el navegador');
  void iIns;
}

if (errores.length) { console.error('campos_propios_config.test.js FALLA:\n - ' + errores.join('\n - ')); process.exit(1); }
console.log('campos_propios_config.test.js OK');
