// 13-oct-2026, petición del cliente (vía owner), dos reglas de pantalla que fija este test:
//   1. Recibí: antes de guardar_recibi se pregunta «¿Ha llegado ya el dinero?»; «Todavía no» no llama a la base.
//   2. Alta de cliente: el documento de identidad es obligatorio y se valida ANTES de crear la ficha; si la subida
//      falla, el reintento no vuelve a llamar a cliente_guarda.
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
ok(/creado_por,anulada,enviada,total,datos,justificantes'\)\.eq\('id', pre\.id\)\.eq\('tipo', 'recibi'\)/.test(ed), 'recibí: el editor lee el total guardado para comparar');

const mClasico = tramo('function modalClasico(', '\n  function ');
ok(/if \(e && e\.silencioso\) return;\n\s+muestraError\(tS\('No se pudo guardar: '\)/.test(mClasico), 'modalClasico: una cancelación a propósito no pinta error');

// ── 2. Alta de cliente ──────────────────────────────────────────────────────────────────────────────────────────────
const alta = tramo('function abreAltaComprador() {', '/* EDITAR una ficha, desde su cajon');
ok(/var exigeDoc = !!\(window\.LW_INSTANCIA && window\.LW_INSTANCIA\.alta_exige_documento === true\);/.test(alta), 'alta: va tras el interruptor de la instancia');
ok(/persona: \{ etq: 'Foto del pasaporte', tipo: 'passport'/.test(alta) && /empresa: \{ etq: 'Documento de identificación de la empresa', tipo: 'other'/.test(alta),
   'alta: tipos de documento que admite documento_kyc_registra');
{ const s = alta.indexOf("form.addEventListener('submit'"), d = alta.indexOf("if (docMal) malos.push(['doc_identidad', docMal]);", s),
        r = alta.indexOf('if (malos.length) {', s), g = alta.indexOf('guardaAltaComprador(v)', s);
  ok(s > 0 && d > s && r > d && g > r, 'alta: el documento se valida ANTES de crear la ficha'); }
ok(/Promise\.resolve\(creadoId \? \{ data: creadoId \} : guardaAltaComprador\(v\)\)/.test(alta), 'alta: el reintento NO vuelve a llamar a cliente_guarda');
ok(/creadoId = id;\n\s+return subeDocs\(id, v\.doc_caduca \|\| null\)/.test(alta), 'alta: se apunta la ficha creada antes de subir');
ok(/window\.lwKycSube\(sb, id, f, tipoDoc, caduca\)\.then\(function \(\) \{ subidos\.push\(f\); \}\)/.test(alta), 'alta: sube por lwKycSube y apunta lo subido (sin duplicar al reintentar)');
ok(/return docsElegidos\(\)\.filter\(function \(f\) \{ return subidos\.indexOf\(f\) < 0; \}\);/.test(alta), 'alta: el reintento sube solo lo que falta');
ok(/then\(function \(\) \{ docOk = true; listo\(r\); \}/.test(alta) && /if \(!creadoId \|\| docOk\) return;/.test(alta),
   'alta: el aviso al cerrar depende de que TODO subiera, no de lo que haya en el selector');
ok(/var cerrar = function \(\) \{ if \(!ocupado\(\)\) cierraModal\(\); \};/.test(alta) && /e\.key === 'Escape' && !ocupado\(\)/.test(alta),
   'alta: no se cierra con el alta o la subida en marcha');
ok(/if \(fs\.length > DOC_MAX\)/.test(alta) && /fs\[i\]\.size > 20 \* 1024 \* 1024/.test(alta) && /DOC_EXT = \/\\\.\(pdf\|jpe\?g\|png\|webp\|hei\[cf\]\)\$\/i/.test(alta),
   'alta: tipo, tamaño (tope del archivo KYC) y número de ficheros');

// Aviso al titular (condición de Legal para pedir la copia): botón en el alta con el texto de la instancia, en los tres idiomas
ok(/var avisoDoc = exigeDoc && window\.LW_INSTANCIA\.aviso_documento_alta/.test(alta) && /data-e="aviso-doc"/.test(alta), 'alta: botón del aviso de privacidad');
ok(/bloque\('Español', avisoDoc\.es\) \+ bloque\('English', avisoDoc\.en\) \+ bloque\('Bahasa Indonesia', avisoDoc\.id\)/.test(alta), 'alta: el aviso sale en los tres idiomas');
ok(/aviso_documento_alta: Object\.freeze\(\{\n\s+es: 'Aviso sobre sus datos\./.test(inst) && /\n\s+en: 'About your data\./.test(inst) && /\n\s+id: 'Tentang data Anda\./.test(inst),
   'instancia.js: el aviso de Lawang en es/en/id');
ok(!/balian/i.test(inst), 'instancia.js: sin el rastro que aborta el build de instancia');
ok(!/lawangproperties|Lawang Properties/.test(ed.slice(ed.indexOf('function abreAltaComprador() {'), ed.indexOf('/* EDITAR una ficha, desde su cajon'))), 'alta: el nombre y el correo del cliente no viven en editores.js');

// ── Interruptores y textos ──────────────────────────────────────────────────────────────────────────────────────────
ok(/alta_exige_documento: true,/.test(inst) && /recibi_confirma_llegada: true/.test(inst), 'instancia.js: los dos interruptores encendidos en este cliente');
['¿Ha llegado ya el dinero?', 'Vas a emitir un recibí por %i.', 'Sí, ya está en la cuenta', 'Todavía no', 'Foto del pasaporte',
 'Adjunta la foto del pasaporte.', 'Reintentar la subida', 'Falta el documento de identidad'].forEach(function (k) {
  ok(i18n.indexOf("    '" + k + "': ") > 0, 'i18n: falta la traducción de «' + k + '»');
});

console.log('recibi_llegada_alta_documento.test.js OK (' + n + ' comprobaciones)');
