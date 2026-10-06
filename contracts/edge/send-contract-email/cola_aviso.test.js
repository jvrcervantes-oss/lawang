// AXW-202 C3 (5-oct-2026): send-contract-email manda el aviso de anulación de firma a la COLA de correos, SOLO con el interruptor
// `correo_cola_aviso_anulacion` = «cola»; apagado = el envío directo de siempre, con el texto del navegador. Fija la regla leyendo la
// fuente y EJECUTANDO la función nueva contra una base falsa. Corre con: node contracts/edge/send-contract-email/cola_aviso.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const src = leer('contracts', 'edge', 'send-contract-email', 'index.ts');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// ── 1. la función, ejecutada ─────────────────────────────────────────────────────────────────────────────────────
function extrae(nombre) {
  const i = src.indexOf('async function ' + nombre);
  assert.ok(i >= 0, 'no se encuentra ' + nombre);
  const f = src.indexOf('\n}\n', i);
  return src.slice(i, f + 2)
    .replace(/\): Promise<\{ duplicado: boolean \} \| null>/, ')').replace(/contratoId: string, to: string/, 'contratoId, to')
    .replace(/const d = data as \{[^}]*\} \| null;/, 'const d = data;').replace(/\(e as Error\)/g, '(e)');
}
const fabrica = (admin) => new Function('admin', 'console', extrae('encolaAvisoAnulacion') + '\nreturn encolaAvisoAnulacion;')(admin, { error() {} });
const base = (rpc) => { const llamadas = []; return { llamadas, admin: { async rpc(nom, a) { llamadas.push([nom, a]); if (rpc instanceof Error) throw rpc; return rpc; } } }; };
(async () => {
  { const b = base({ data: { modo: 'cola', id: 'q1', estado: 'pendiente', nuevo: true, reabierto: false }, error: null });
    const r = await fabrica(b.admin)('c-1', 'ana@cliente.test');
    ok(r && r.duplicado === false, 'encolado nuevo: duplicado=false');
    assert.deepStrictEqual(b.llamadas, [['correo_aviso_anulacion_encolar', { p_contrato: 'c-1', p_email: 'ana@cliente.test' }]]); n++; }
  { const b = base({ data: { modo: 'cola', id: 'q1', estado: 'ok', nuevo: false, reabierto: false }, error: null });
    const r = await fabrica(b.admin)('c-1', 'a@b.test'); ok(r && r.duplicado === true, 'ya había fila viva: duplicado=true (no se reenvía)'); }
  { const b = base({ data: { modo: 'cola', id: 'q1', estado: 'pendiente', nuevo: false, reabierto: true }, error: null });
    const r = await fabrica(b.admin)('c-1', 'a@b.test'); ok(r && r.duplicado === false, 'una fila en error reabierta cuenta como encolada de nuevo'); }
  for (const [rpc, m] of [[{ data: { modo: 'directo' }, error: null }, 'interruptor apagado'],
                          [{ data: { modo: 'directo', motivo: 'sin_anulacion_reciente' }, error: null }, 'sin anulación reciente'],
                          [{ data: { modo: 'directo', motivo: 'error' }, error: null }, 'la RPC no pudo encolar'],
                          [{ data: { modo: 'cola' }, error: null }, 'modo cola sin id'], [{ data: null, error: null }, 'sin datos'],
                          [{ data: null, error: { message: 'boom' } }, 'error de la RPC'], [new Error('red'), 'excepción']]) {
    ok((await fabrica(base(rpc).admin)('c-1', 'a@b.test')) === null, 'cae al envío directo: ' + m);
  }

  // ── 2. el cableado dentro del manejador ─────────────────────────────────────────────────────────────────────────
  const cabecera = "if (via === 'aviso_anulacion' && soloTexto && contratoId) {";
  ok((src.match(/encolaAvisoAnulacion\(/g) || []).length === 2, 'definida una vez y llamada una vez');
  const i = src.indexOf(cabecera);
  ok(i > 0, 'el bloque de la cola existe y solo cuando es aviso de anulación, de solo texto y con contrato');
  ok(i > src.indexOf("const { data: cv, error: eC } = await usuario.from('contratos')"), 'la cola va DESPUÉS de comprobar que el contrato es visible para quien envía');
  ok(i > src.indexOf("error: 'solo_equipo' }, 403)"), 'y después del gate de equipo');
  ok(i < src.indexOf("let pdfB64 = '';"), 'y antes de renderizar o enviar nada');
  const bloque = src.slice(i, src.indexOf('\n    }\n', i));
  ok(/const enc = await encolaAvisoAnulacion\(contratoId, to\);\s*\n\s*if \(enc\) return json\(\{ ok: true, encolado: true, duplicado: enc\.duplicado \}\);/.test(bloque),
    'si se encola responde ok+encolado; si no, sigue por la rama directa');
  ok(!/registrado/.test(bloque), 'no dice registrado:true: lo registrará la cola al enviar');
  // la rama directa intacta
  for (const frag of ["const VIAS = ['enlace_firma', 'aviso_anulacion', 'firma'];", "via: facturaId ? 'factura' : (via ?? 'manual')",
                      'JSON.stringify(soloTexto ? { to, subject, message, attach: false }']) ok(src.includes(frag), 'la rama directa cambió: ' + frag);

  // ── 3. datos duplicados: lo que pone el navegador, la migración y la plantilla tienen que decir lo mismo ───────────
  const app = leer('contracts', 'app.html');
  ok(/correoContrato\(\{ to: em, subject: asunto, attach:false, via:'aviso_anulacion'/.test(app), 'app.html manda via:aviso_anulacion con attach:false');
  ok(/rpc\('contrato_firmas_anula',\s*\n?\s*\{ p_contrato: SAVED_CONTRACT\.id, p_motivo: 'editar'/.test(app), 'el navegador anula con motivo «editar» (el que ancla la cola)');
  const migs = fs.readdirSync(path.join(raiz, 'supabase', 'migrations'));
  const mig = migs.filter((f) => /axw202_c3_aviso_anulacion_cola\.sql$/.test(f));
  ok(mig.length === 1, 'migración C3 no encontrada');
  const sql = leer('supabase', 'migrations', mig[0]);
  ok(/values \('correo_cola_aviso_anulacion', '"directo"'::jsonb,/.test(sql), 'el interruptor nace en «directo»');
  ok(!/'"cola"'::jsonb,\s*\n?\s*'AXW/.test(sql), 'la migración no enciende el interruptor');
  ok(/anulado_motivo = 'editar'/.test(sql) && /correo_encolar\('aviso_anulacion', p_firma := v_firma\)/.test(sql), 'la RPC ancla la firma anulada por «editar» y encola la clave aviso_anulacion');
  ok(/revoke execute on function public\.correo_aviso_anulacion_encolar\(uuid, text\) from public, anon, authenticated;/.test(sql)
     && /grant  execute on function public\.correo_aviso_anulacion_encolar\(uuid, text\) to service_role;/.test(sql), 'la RPC de encolar es solo de service_role');
  ok(/exception when others then[\s\S]*'modo', 'directo', 'motivo', 'error'/.test(sql), 'ante cualquier fallo la RPC devuelve directo, nunca lanza');
  const c1 = leer('supabase', 'migrations', migs.find((f) => /axw202_c1_cola_correos\.sql$/.test(f)));
  ok(/\('aviso_anulacion',\s+'firma_id',\s+true,/.test(c1), 'la cola tiene aviso_anulacion como SOPORTADA con ancla firma_id');
  const fab = leer('supabase', 'functions', 'envia-correo', 'plantillas_fabrica.ts');
  ok(fab.includes("asunto: 'Actualización del documento {{numero}} — ' + FIRMA"), 'la plantilla conserva el asunto del aviso del navegador');
  ok(app.includes("'Actualización del documento ' + numero + ' — Lawang Tropical Properties'"), 'y el navegador sigue pidiendo ese asunto');
  console.log('OK cola_aviso.test.js — ' + n + ' comprobaciones: encolar solo (contrato, correo), 7 caídas a directo, cableado detrás de la RLS del contrato, rama directa intacta, claves cruzadas con app.html, la migración y la plantilla');
})().catch((e) => { console.error(e); process.exit(1); });
