// AXW-202 C2 (5-oct-2026): firma-submit encola el correo del enlace de la cadena en vez de mandarlo, SOLO con el interruptor
// `correo_cola_firma_submit` = «cola»; apagado = el envío directo de siempre (v63). Este test fija la regla leyendo la fuente y
// EJECUTANDO las dos funciones nuevas contra una base falsa. Corre con: node contracts/edge/firma-submit/cola_correo.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const dir = __dirname;
const raiz = path.join(dir, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const src = leer('contracts', 'edge', 'firma-submit', 'index.ts');
assert.strictEqual(src, leer('supabase', 'functions', 'firma-submit', 'index.ts'), 'contracts/edge y supabase/functions de firma-submit han divergido');

// ── 1. las dos funciones, ejecutadas ─────────────────────────────────────────────────────────────────────────────
function extrae(nombre) {
  const i = src.indexOf('async function ' + nombre);
  assert.ok(i >= 0, 'no se encuentra ' + nombre);
  const f = src.indexOf('\n}\n', i);
  return src.slice(i, f + 2)
    .replace(/\): Promise<boolean>/g, ')').replace(/firmaId: string, numero: string/, 'firmaId, numero')
    .replace(/\(data as any\)/g, '(data)').replace(/\(e as Error\)/g, '(e)').replace(/catch \(_\)/, 'catch (_e)');
}
const fabrica = (sb) => new Function('sb', 'console', extrae('colaCorreoActiva') + '\n' + extrae('encolarEnlaceCadena') +
  '\nreturn { colaCorreoActiva, encolarEnlaceCadena };');
const sinLog = { error() {} };
function baseFalsa({ valor, lanza = false, rpc = null }) {
  const llamadas = { lecturas: [], rpc: [] };
  const sb = {
    from(t) { return { select() { return { eq(c, v) { return { async maybeSingle() {
      llamadas.lecturas.push([t, c, v]);
      if (lanza) throw new Error('base caída');
      return { data: valor === undefined ? null : { valor }, error: null };
    } }; } }; } }; },
    async rpc(n, a) { llamadas.rpc.push([n, a]); if (rpc instanceof Error) throw rpc; return rpc; },
  };
  return { sb, llamadas };
}
(async () => {
  for (const [valor, esperado, motivo] of [['cola', true, 'cola'], ['directo', false, 'directo'], [undefined, false, 'clave ausente'],
                                           ['COLA', false, 'mayúsculas (no se interpreta)'], [true, false, 'booleano'], ['', false, 'vacío']]) {
    const { sb, llamadas } = baseFalsa({ valor });
    const f = fabrica(sb)(sb, sinLog);
    assert.strictEqual(await f.colaCorreoActiva(), esperado, 'interruptor ' + motivo);
    assert.deepStrictEqual(llamadas.lecturas, [['config_instancia', 'clave', 'correo_cola_firma_submit']], 'lee SOLO su clave, una vez');
  }
  { const { sb } = baseFalsa({ lanza: true }); assert.strictEqual(await fabrica(sb)(sb, sinLog).colaCorreoActiva(), false, 'base caída = apagado (envío directo)'); }

  { // encolar: manda SOLO la clave y el id de la firma; nada de destinatario, enlace, token ni texto
    const { sb, llamadas } = baseFalsa({ rpc: { data: { id: 'q1', estado: 'pendiente', nuevo: true }, error: null } });
    assert.strictEqual(await fabrica(sb)(sb, sinLog).encolarEnlaceCadena('f-1', 'CR1'), true);
    assert.deepStrictEqual(llamadas.rpc, [['correo_encolar', { p_clave: 'enlace_firma_cadena', p_firma: 'f-1' }]]);
  }
  for (const [rpc, motivo] of [[{ data: null, error: { message: 'clave_no_soportada_aun' } }, 'error de la RPC'], [{ data: null, error: null }, 'sin datos'],
                                [{ data: { estado: 'x' }, error: null }, 'sin id'], [new Error('red'), 'excepción']]) {
    const { sb } = baseFalsa({ rpc });
    let log = '';
    assert.strictEqual(await fabrica(sb)(sb, { error: (...a) => { log += a.join(' '); } }).encolarEnlaceCadena('f-1', 'CR1'), false, 'encolar falla: ' + motivo);
    assert.ok(/cola_correos_encolar_fallo/.test(log) && /se envía directo/.test(log), 'el fallo de encolar se dice en el log (' + motivo + ')');
  }

  // ── 2. el cableado dentro de la cadena ─────────────────────────────────────────────────────────────────────────
  const ini = src.indexOf('// 4) siguiente firmante de la cadena');
  const fin = src.indexOf('// ── ÚLTIMA firma', ini);
  assert.ok(ini > 0 && fin > ini, 'no se encuentra el bloque de la cadena');
  const cadena = src.slice(ini, fin);
  assert.strictEqual((cadena.match(/colaCorreoActiva\(\)/g) || []).length, 1, 'el interruptor se lee UNA vez por firma');
  assert.strictEqual((cadena.match(/encolarEnlaceCadena\(/g) || []).length, 1, 'se encola una sola vez por firma');
  assert.strictEqual((cadena.match(/await enviarEmail\(\{/g) || []).length, 1, 'un solo envío directo en la cadena (la rama de siempre)');
  assert.ok(/const encolado = \(await colaCorreoActiva\(\)\) \? await encolarEnlaceCadena\(insSig\.data\.id, numero\) : false;\s*\n\s*if \(!encolado\) await enviarEmail\(\{/.test(cadena),
    'el envío directo debe depender de que NO se haya encolado');
  assert.ok(cadena.indexOf('colaCorreoActiva()') > cadena.indexOf("from('contrato_firmas').insert"), 'se encola DESPUÉS de guardar la firma nueva');
  assert.ok(/\}\)\.select\('id'\)\.single\(\);\s*\n\s*if \(insSig\.error \|\| !insSig\.data\)/.test(cadena), 'el id de la firma nueva sale del insert y se comprueba');
  // la rama directa es la de la v63: mismo asunto, mismo cuerpo, mismo registro
  for (const frag of ["subject: 'Documento para firmar · ' + numero", "', aquí tienes el enlace para firmar el documento de Lawang Tropical Properties: ' + link",
                      "'\\n\\nEl enlace caduca en 30 días.\\n\\nLawang Tropical Properties'", "log: { contrato_id: claimed.contrato_id, via: 'enlace_firma' }"]) {
    assert.ok(cadena.includes(frag), 'la rama directa cambió: ' + frag);
  }
  // la firma NO toca SMTP ni texto en la ruta de la cola: lo que viaja a la RPC son solo dos claves
  const rpcs = src.match(/sb\.rpc\('correo_encolar', \{[^}]*\}\)/g) || [];
  assert.strictEqual(rpcs.length, 1, 'una sola llamada a correo_encolar');
  assert.ok(/\{ p_clave: 'enlace_firma_cadena', p_firma: firmaId \}/.test(rpcs[0]), 'correo_encolar recibe solo clave y firma_id');

  // ── 3. un solo dato en varios sitios: clave de la cola, clave del interruptor y texto de la plantilla ───────────
  const mig1 = fs.readdirSync(path.join(raiz, 'supabase', 'migrations')).filter((f) => /axw202_c1_cola_correos\.sql$/.test(f));
  assert.strictEqual(mig1.length, 1, 'migración C1 no encontrada');
  const sql1 = leer('supabase', 'migrations', mig1[0]);
  assert.ok(/\('enlace_firma_cadena',\s+'firma_id',\s+true,/.test(sql1), 'la cola debe tener enlace_firma_cadena como SOPORTADA con ancla firma_id');
  const mig2 = fs.readdirSync(path.join(raiz, 'supabase', 'migrations')).filter((f) => /axw202_c2_firma_submit_cola\.sql$/.test(f));
  assert.strictEqual(mig2.length, 1, 'migración C2 no encontrada');
  const sql2 = leer('supabase', 'migrations', mig2[0]);
  assert.ok(/values \('correo_cola_firma_submit', '"directo"'::jsonb,/.test(sql2), 'el interruptor nace en «directo»');
  assert.ok(!/'"cola"'::jsonb,\n?\s*'AXW/.test(sql2), 'la migración no puede encender el interruptor al crearlo');
  const fab = leer('supabase', 'functions', 'envia-correo', 'plantillas_fabrica.ts');
  const bloque = fab.slice(fab.indexOf('enlace_firma_cadena: {'), fab.indexOf('copia_firmada_comprador: {'));
  for (const frag of ["asunto: 'Documento para firmar · {{numero}}'", 'aquí tienes el enlace para firmar el documento de', 'El enlace caduca en 30 días.']) {
    assert.ok(bloque.includes(frag), 'la plantilla de la cola ya no dice lo mismo que el envío directo: ' + frag);
  }
  console.log('OK cola_correo.test.js — interruptor (6 valores + base caída), encolar solo clave+firma, fallo = envío directo, una lectura y un encolado por firma, rama directa intacta, claves cruzadas con C1 y la plantilla');
})().catch((e) => { console.error(e); process.exit(1); });
