// LAW-37 (11-oct-2026): las pantallas no ofrecen «Enviar por email» sobre un documento ANULADO (botón desactivado con el
// motivo), y la frase del 409 de send-contract-email tiene traducción. La edge lo rechaza igual (anulado.test.js); esto
// fija que la pantalla no llegue a pedirlo. Corre con: node intranet/v4/assets/correo_anulado.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const fac = leer('intranet', 'facturas', 'index.html');
const ed = leer('intranet', 'v4', 'assets', 'editores.js');
const i18n = leer('contracts', 'assets', 'i18n.js');
const edge = leer('contracts', 'edge', 'send-contract-email', 'index.ts');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// ── facturas (clásico) ──────────────────────────────────────────────────────────────────────────────────────────
ok(/let ANULADA_EN_PANTALLA = false;/.test(fac), 'facturas: existe la marca de documento anulado en pantalla');
ok(/razon\(\$\('#btnMail'\), !ANULADA_EN_PANTALLA && /.test(fac), 'facturas: #btnMail se desactiva con un anulado en pantalla');
ok(/ANULADA_EN_PANTALLA \? 'Este documento está anulado/.test(fac), 'facturas: el motivo del anulado gana a «Guarda primero»');
ok(/SAVED = f\.anulada \? null : [^\n]+\n  ANULADA_EN_PANTALLA = !!f\.anulada;/.test(fac), 'facturas: abrir() fija la marca desde la fila');
ok(/SAVED = \{ id:data\.id[^\n]+\n    ANULADA_EN_PANTALLA = false;/.test(fac), 'facturas: guardar la limpia (la copia ya es un documento nuevo)');
ok(/function nuevoDocumento\(tipo\)\{\n  SAVED = null; CONTRATO_ID = null; ANULADA_EN_PANTALLA = false;/.test(fac), 'facturas: «Nueva» la limpia');
ok(/if\(SAVED && SAVED\.id === an\.dataset\.anular\)\{ ANULADA_EN_PANTALLA = true; render\(\); \}/.test(fac), 'facturas: anular desde el listado la que está abierta la marca');
{ const i = fac.indexOf("$('#mailSend').onclick"), g = fac.indexOf('if(ANULADA_EN_PANTALLA)', i), f = fac.indexOf("fetch(window.lwEdge('send-contract-email')", i);
  ok(i > 0 && g > i && g < f, 'facturas: el envío se corta antes de llamar a la edge'); }
ok(/toastMal\(res\.error \? lwT\(res\.error\)/.test(fac), 'facturas: la frase de la edge pasa por lwT');
ok(/SAVED\.numero && !SAVED\.enviada\) && !ANULADA_EN_PANTALLA/.test(fac), 'facturas: «Marcar como enviada» tampoco se ofrece sobre un anulado');
ok(/data-anular="\$\{f\.id\}"/.test(fac) && /id="btnMail"/.test(fac), 'facturas: engancha por id y data-anular, no por rótulo');

// ── v4 (editores.js) ────────────────────────────────────────────────────────────────────────────────────────────
{ const i = ed.indexOf('function enviaDocMail('), g = ed.indexOf('if (saved.anulada) return aviso(', i), f = ed.indexOf("window.lwEdge('send-contract-email')", i);
  ok(i > 0 && g > i && g < f, 'v4: enviaDocMail se corta con un anulado antes de la edge (cubre a todos los que llaman)'); }
ok(/razon\(bMail, !anulada && total > 0 && num, anulada \? 'Este documento está anulado/.test(ed), 'v4: el botón de la barra se desactiva con su motivo');
ok(/var anulada = !!\(ctx\.saved && ctx\.saved\.anulada\);/.test(ed), 'v4: la barra lee saved.anulada');
ok((ed.match(/emisor: existente\.datos && existente\.datos\.emisor, anulada: !!existente\.anulada \}/g) || []).length === 2,
   'v4: los dos editores (documento y recibí) pasan anulada a la barra');
ok(/sb\.from\('facturas'\)\.select\('id,numero,tipo,contrato_id,contrato_numero,client_id,creado_por,anulada,/.test(ed), 'v4: el editor de documento lee anulada');
ok(/\.eq\('tipo', 'recibi'\)/.test(ed) && /select\('id,numero,tipo,contrato_id,contrato_numero,client_id,creado_por,anulada,enviada,datos,justificantes'\)/.test(ed), 'v4: el editor de recibí lee anulada');
ok(/facturas_equipo'\)\.select\('id,numero,tipo,contrato_id,cliente_nombre,anulada,datos'\)/.test(ed) && /anulada: !!f\.anulada \} \};/.test(ed),
   'v4: cargaDocGuardado (ficha y visor) lee y pasa anulada');
ok(/toastMal\(res && res\.error \? edT\(res\.error\)/.test(ed), 'v4: la frase de la edge pasa por lwT');

// ── la frase del 409 (y la del 413) traducida, con la clave EXACTA que manda la edge ──────────────────────────────
for (const cod of ['documento_anulado', 'pdf_demasiado_grande']) {
  const m = edge.match(new RegExp("codigo: '" + cod + "',\\s*error: '([^']+)'"));
  ok(m, 'la edge manda ' + cod + ' con frase');
  ok(i18n.includes("'" + m[1] + "':"), 'i18n tiene la frase de ' + cod + ' tal cual la manda la edge');
}
ok(i18n.includes("'Este documento está anulado: no se envía al cliente.':"), 'i18n tiene el aviso de la pantalla');
console.log('OK correo_anulado.test.js — ' + n + ' comprobaciones: facturas y v4 no ofrecen enviar un anulado, cortan antes de la edge, y las frases de la edge están en el diccionario');
