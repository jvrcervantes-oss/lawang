// 13-oct-2026, petición del cliente (vía owner), dos reglas de pantalla que fija este test:
//   1. Recibí: antes de guardar_recibi se pregunta «¿Ha llegado ya el dinero?»; «Todavía no» no llama a la base.
//   2. Alta de cliente: el documento de identidad es obligatorio y se valida ANTES de subir nada. Desde LAW-557
//      (13-oct, owner: «alta y pasaporte juntos») ficha y documento entran en UNA operación de la edge ficheros-kyc
//      (alta_subida_url → alta): con el interruptor ya no se llama a cliente_guarda ni existe «ficha sin documento».
// Lee el código fuente (como correo_anulado.test.js): las dos viven dentro de cierres que no se pueden cargar sueltos.
// Corre con: node intranet/v4/assets/recibi_llegada_alta_documento.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const ed = leer('intranet', 'v4', 'assets', 'editores.js');
const i18n = leer('contracts', 'assets', 'i18n.js');
const inst = leer('contracts', 'assets', 'instancia.js');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };
const tramo = (desde, hasta) => { const i = ed.indexOf(desde), f = ed.indexOf(hasta, i + 1); assert.ok(i > 0 && f > i, 'no encuentro el tramo ' + desde); return ed.slice(i, f); };

// ── 1. Recibí ───────────────────────────────────────────────────────────────────────────────────────────────────────
const fnPregunta = tramo('function confirmaLlegadaDinero(', '/* ---------- Recibí de cobro: crear o editar ---------- */');
ok(/titulo: '¿Ha llegado ya el dinero\?'/.test(fnPregunta), 'recibí: el diálogo lleva el título acordado');
ok(/confirmar: 'Sí, ya está en la cuenta', cancelar: 'Todavía no'/.test(fnPregunta), 'recibí: los dos botones (el foco lo pone lwConfirmar en el de cancelar)');
ok(/return ok === true;/.test(fnPregunta), 'recibí: solo un «sí» explícito sigue');
ok(/window\.confirm\(/.test(fnPregunta), 'recibí: sin dialogo.js hay pregunta igual (confirm), nunca se emite sin preguntar');

const guardado = tramo("if (pre.soloLectura) return { error: { message: 'Este recibí se abre solo para consultarlo.' } };", "pielClasica: true, sinRecarga: true, sub: pre.soloLectura ? 'Recibí'");
const iJust = guardado.indexOf("Adjunta el justificante de pago.");
const iImp = guardado.lastIndexOf("solo tiene %p pendiente");
const iPreg = guardado.indexOf('var llegada = preguntaLlegada ? confirmaLlegadaDinero(');
const iCorta = guardado.indexOf('if (!ok) throw { silencioso: true };');
const iRpc = guardado.indexOf("sb.rpc('guardar_recibi'");
ok(iJust > 0 && iImp > iJust && iPreg > iImp, 'recibí: se pregunta DESPUÉS de todas las validaciones');
ok(iPreg > 0 && iCorta > iPreg && iRpc > iCorta, 'recibí: «Todavía no» corta antes de llamar a guardar_recibi');
ok((guardado.match(/sb\.rpc\('guardar_recibi'/g) || []).length === 1, 'recibí: una sola llamada a guardar_recibi, la de detrás de la pregunta');
ok(/var preguntaLlegada = !!\(window\.LW_INSTANCIA && window\.LW_INSTANCIA\.recibi_confirma_llegada === true\) && cambiaCifra;/.test(guardado),
   'recibí: va tras el interruptor de la instancia');
ok(/var cambiaCifra = !existente \|\| Math\.abs\(\(Number\(existente\.total\) \|\| 0\) - \(Number\(t\.total\) \|\| 0\)\) > 0\.005/.test(guardado),
   'recibí: al editar pregunta otra vez si cambia el importe');
ok(/creado_por,anulada,enviada,total,datos,justificantes'[\s\S]{0,300}?\)\.eq\('id', pre\.id\)\.eq\('tipo', 'recibi'\)/.test(ed), 'recibí: el editor lee el total guardado para comparar');

const mClasico = tramo('function modalClasico(', '\n  function ');
ok(/if \(e && e\.silencioso\) return;\n\s+muestraError\(tS\('No se pudo guardar: '\)/.test(mClasico), 'modalClasico: una cancelación a propósito no pinta error');

// ── 2. Alta de cliente ──────────────────────────────────────────────────────────────────────────────────────────────
const alta = tramo('function abreAltaComprador() {', '/* EDITAR una ficha, desde su cajon');
ok(/var exigeDoc = !!\(window\.LW_INSTANCIA && window\.LW_INSTANCIA\.alta_exige_documento === true\);/.test(alta), 'alta: va tras el interruptor de la instancia');
ok(/persona: \{ etq: 'Foto del pasaporte', tipo: 'passport'/.test(alta) && /empresa: \{ etq: 'Documento de identificación de la empresa', tipo: 'other'/.test(alta),
   'alta: tipos de documento que admite documento_kyc_registra');
{ const s = alta.indexOf("form.addEventListener('submit'"), d = alta.indexOf("if (docMal) malos.push(['doc_identidad', docMal]);", s),
        r = alta.indexOf('if (malos.length) {', s), g = alta.indexOf('exigeDoc ? altaConDocumento(v) : guardaAltaComprador(v)', s);
  ok(s > 0 && d > s && r > d && g > r, 'alta: el documento se valida ANTES de subir nada ni crear la ficha'); }
ok(/Promise\.resolve\(exigeDoc \? altaConDocumento\(v\) : guardaAltaComprador\(v\)\)/.test(alta), 'alta: con el interruptor va por la vía con documento; sin él, la de siempre');
// LAW-557: ficha y documento en UNA operación del servidor; el estado «ficha creada, falta el documento» ya no existe
ok(!/creadoId|modoReintento|_alCerrarAlta|docOk/.test(alta), 'alta: fuera la máquina vieja (creadoId/modoReintento/_alCerrarAlta)');
{ const f = tramo('function altaConDocumento(v) {', 'function falloAlta(e) {');
  ok(/faltanDatosComprador\(v\)/.test(f) && /telefonoRepetidoSigue\(telAlta, null\)/.test(f), 'alta con documento: mismas comprobaciones previas que el alta de siempre');
  ok(!/sb\.rpc\('cliente_guarda'/.test(f), 'alta con documento: no llama a cliente_guarda');
  ok(/if \(pathDe\(f\)\) return null;/.test(f), 'alta con documento: lo ya subido no se vuelve a subir');
  ok(/window\.lwKycAltaSube\(sb, altaId, f\)/.test(f), 'alta con documento: sube a la carpeta de alta pendiente que da el servidor');
  const iSube = f.indexOf('window.lwKycAltaSube('), iAlta = f.indexOf("window.lwKyc(sb, 'alta', pide)");
  ok(iSube > 0 && iAlta > iSube, 'alta con documento: primero se sube todo, después UNA llamada a `alta`');
  ok(/datos: datosAltaComprador\(v, telAlta\), paths: fs\.map\(pathDe\)/.test(f), 'alta con documento: manda los mismos datos que el alta de siempre y los paths');
  ok(!/doc_type|tipoDoc/.test(f), 'alta con documento: el tipo de documento lo decide el servidor, no la pantalla'); }
ok((ed.match(/function datosAltaComprador\(/g) || []).length === 1 && /sb\.rpc\('cliente_guarda', \{ p_id: null, p_datos: datosAltaComprador\(v, telAlta\) \}\)/.test(ed),
   'alta: los datos del alta se escriben UNA vez y los comparten las dos vías');
{ const f = tramo('function falloAlta(e) {', 'function listo(r) {');
  ok(/if \(enDuda && !clave\)/.test(f) && /duda: true/.test(f), 'alta: sin respuesta del servidor es DUDA (reenviar es seguro), no error');
  ok(/clave === 'el_fichero_no_es_lo_que_dice_ser' \|\| clave === 'el_fichero_no_ha_llegado'/.test(f) && /quitaSubido\(e\.path\)/.test(f),
     'alta: un fichero rechazado sale de lo subido y se pide otro');
  ok(/clave === 'alta_no_valida'/.test(f), 'alta: una carpeta caducada o ajena se olvida y el reenvío empieza limpio'); }
ok(/function descartaAlta\(\)/.test(alta) && /window\.lwKyc\(sb, 'alta_descarta', \{ alta_id: id \}\)/.test(alta) && /if \(!altaId \|\| hecho\) return Promise\.resolve\(\);/.test(alta),
   'alta: al cerrar sin terminar se descarta la carpeta pendiente (nunca después de crear la ficha)');
ok(/w\._alCerrar = function \(\) \{ document\.removeEventListener\('keydown', teclas\); if \(exigeDoc\) alCerrarAlta\(\); \};/.test(alta), 'alta: el descarte va en TODAS las salidas del panel');
ok(/var cerrar = function \(\) \{ if \(!ocupado\(\)\) cierraModal\(\); \};/.test(alta) && /e\.key === 'Escape' && !ocupado\(\)/.test(alta),
   'alta: no se cierra con el alta o la subida en marcha');
// guard.js: la pieza de subida del alta, una sola copia
{ const g = leer('contracts', 'assets', 'guard.js');
  ok(/fija\('lwKycAltaSube', function \(sb, altaId, f\)/.test(g) && /if \(altaId\) pide\.alta_id = altaId;/.test(g), 'guard.js: lwKycAltaSube nunca inventa un alta_id');
  ok(/window\.lwKyc\(sb, 'alta_subida_url', pide\)/.test(g) && /type: u\.content_type/.test(g), 'guard.js: sube con el tipo que decide el servidor');
  ['alta_no_disponible', 'alta_no_valida', 'demasiadas_altas_abiertas', 'demasiados_ficheros', 'faltan_ficheros'].forEach(function (k) {
    ok(new RegExp('\\n\\s+' + k + ': \'').test(g), 'guard.js: falta el texto del error ' + k);
  }); }
// CRM de leads: con el interruptor, una ficha NUEVA no nace desde aquí
{ const l = leer('intranet', 'leads', 'leads.js');
  ok(/const altaEnClientes = !!\(window\.LW_INSTANCIA && window\.LW_INSTANCIA\.alta_exige_documento === true\)\n\s+&& d\.email && !d\.ficha_existente;/.test(l),
     'leads: el interruptor solo cambia el caso sin ficha previa');
  ok(/altaEnClientes \? `<a class="btn pri" href="\/intranet\/v4\/compradores\/\?nuevo=1"/.test(l), 'leads: sin ficha, enlaza al alta de Clientes en vez de crearla'); }
ok(/if \(fs\.length > DOC_MAX\)/.test(alta) && /fs\[i\]\.size > 20 \* 1024 \* 1024/.test(alta) && /DOC_EXT = \/\\\.\(pdf\|jpe\?g\|png\|webp\|hei\[cf\]\)\$\/i/.test(alta),
   'alta: tipo, tamaño (tope del archivo KYC) y número de ficheros');

// Aviso al titular (condición de Legal para pedir la copia): botón en el alta con el texto de la instancia, en los tres idiomas
ok(/var avisoDoc = exigeDoc && window\.LW_INSTANCIA\.aviso_documento_alta/.test(alta) && /data-e="aviso-doc"/.test(alta), 'alta: botón del aviso de privacidad');
ok(/bloque\('Español', avisoDoc\.es\) \+ bloque\('English', avisoDoc\.en\) \+ bloque\('Bahasa Indonesia', avisoDoc\.id\)/.test(alta), 'alta: el aviso sale en los tres idiomas');
ok(/aviso_documento_alta: Object\.freeze\(\{\n\s+es: 'Aviso sobre sus datos\./.test(inst) && /\n\s+en: 'About your data\./.test(inst) && /\n\s+id: 'Tentang data Anda\./.test(inst),
   'instancia.js: el aviso de Lawang en es/en/id');
ok(!/balian/i.test(inst), 'instancia.js: sin el rastro que aborta el build de instancia');
// LAW-558 (Legal, 13-oct): los meses que promete el aviso son los que siembra la base; si alguien cambia uno, este test
// obliga a cambiar el otro (y a que Legal relea el aviso).
{ const mig = leer('supabase', 'migrations', '20261013235338_law557_558_alta_con_documento_y_retencion_kyc.sql');
  const m = /values \('kyc_meses_retencion', '(\d+)'::jsonb/.exec(mig);
  ok(m, 'la migración siembra kyc_meses_retencion');
  const aviso = inst.slice(inst.indexOf('aviso_documento_alta: Object.freeze({'), inst.indexOf('})', inst.indexOf('aviso_documento_alta: Object.freeze({')));
  ok(aviso.indexOf('pasan ' + m[1] + ' meses') > 0 && aviso.indexOf(m[1] + ' months pass') > 0 && aviso.indexOf(m[1] + ' bulan berlalu') > 0,
     'el aviso (es/en/id) dice los mismos meses que siembra la base (' + m[1] + ')');
  ok(/la copia no se borra automáticamente/.test(aviso) && /the copy is not deleted automatically/.test(aviso) && /salinan tidak dihapus secara otomatis/.test(aviso),
     'el aviso cubre el caso en que hay registros y no se borra (Legal, 13-oct)'); }
ok(/else if \(nuevoId\) location\.href = location\.pathname \+ '\?id=' \+ encodeURIComponent\(nuevoId\);/.test(alta),
   'alta: al terminar se abre la ficha recién creada (?id=), no la lista sin aviso (recorrido de un agente, 14-oct)');
ok(/var nuevoId = r && typeof r\.data === 'string' && \/\^\[0-9a-f-\]\{36\}\$\/i\.test\(r\.data\) \? r\.data : null;/.test(alta),
   'alta: a la URL solo va el uuid que devolvió el servidor');
ok(!/lawangproperties|Lawang Properties/.test(ed.slice(ed.indexOf('function abreAltaComprador() {'), ed.indexOf('/* EDITAR una ficha, desde su cajon'))), 'alta: el nombre y el correo del cliente no viven en editores.js');

// ── Interruptores y textos ──────────────────────────────────────────────────────────────────────────────────────────
ok(/alta_exige_documento: true,/.test(inst) && /recibi_confirma_llegada: true/.test(inst), 'instancia.js: los dos interruptores encendidos en este cliente');
['¿Ha llegado ya el dinero?', 'Vas a emitir un recibí por %i.', 'Sí, ya está en la cuenta', 'Todavía no', 'Foto del pasaporte',
 'Adjunta la foto del pasaporte.', 'Elige otro fichero.', 'Vuelve a pulsar «Dar de alta».', 'Este lead todavía no tiene ficha de cliente.',
 'Dar de alta en Clientes'].forEach(function (k) {
  ok(i18n.indexOf("    '" + k + "': ") > 0, 'i18n: falta la traducción de «' + k + '»');
});

console.log('recibi_llegada_alta_documento.test.js OK (' + n + ' comprobaciones)');
