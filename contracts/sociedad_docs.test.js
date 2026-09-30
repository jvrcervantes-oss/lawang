/* node contracts/sociedad_docs.test.js — la regla «a qué sociedad pertenece un contrato sin sociedad elegida» vive en DOS sitios
   y este test los ata (Ajustes del ERP, S3, 30-sep-2026):
     · el navegador, `lwSociedadContrato` en contracts/assets/entities.js (SOCIEDAD_DEFAULT + el respaldo final);
     · el servidor, `_sociedad_docs_filas` en la migración 20260930200000, que cuenta los contratos de cada sociedad para bloquear su
       identidad fiscal cuando ya tiene documentos.
   Si una plantilla nueva cambia su sociedad por defecto en el JS y no en SQL, un contrato se imprimiría con la identidad de una
   sociedad que el servidor cree sin documentos: se podría editar su NPWP con un contrato ya emitido. Aquí salta antes de subir. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const js = fs.readFileSync(path.join(__dirname, 'assets', 'entities.js'), 'utf8');
const sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260930200000_ajustes_sociedades_identidad.sql'), 'utf8');

// JS: const SOCIEDAD_DEFAULT = { ppjb_reserva: 'san_dal_woods' };  ...  return v || SOCIEDAD_DEFAULT[tipo] || 'tepi_sungai';
const mDef = js.match(/const SOCIEDAD_DEFAULT\s*=\s*\{([^}]*)\}/);
assert.ok(mDef, 'entities.js ya no declara SOCIEDAD_DEFAULT: revisa _sociedad_docs_filas');
const jsPares = {};
for (const m of mDef[1].matchAll(/(\w+)\s*:\s*'([a-z0-9_]+)'/g)) jsPares[m[1]] = m[2];
const mResp = js.match(/SOCIEDAD_DEFAULT\[tipo\]\s*\|\|\s*'([a-z0-9_]+)'/);
assert.ok(mResp, 'entities.js ya no tiene el respaldo final de lwSociedadContrato');

// SQL: case k.tipo when 'ppjb_reserva' then 'san_dal_woods' else 'tepi_sungai' end
const mCase = sql.match(/case k\.tipo((?:\s+when\s+'[a-z0-9_]+'\s+then\s+'[a-z0-9_]+')+)\s+else\s+'([a-z0-9_]+)'\s+end/);
assert.ok(mCase, 'la migración ya no tiene el CASE de la sociedad por defecto en _sociedad_docs_filas');
const sqlPares = {};
for (const m of mCase[1].matchAll(/when\s+'([a-z0-9_]+)'\s+then\s+'([a-z0-9_]+)'/g)) sqlPares[m[1]] = m[2];

assert.deepStrictEqual(sqlPares, jsPares, 'SOCIEDAD_DEFAULT (JS) y el CASE de _sociedad_docs_filas (SQL) tienen que decir lo mismo');
assert.strictEqual(mCase[2], mResp[1], 'el respaldo final (JS) y el ELSE del CASE (SQL) tienen que ser la misma sociedad');

// El SQL cubre TODAS las tablas que apuntan a sociedades (la prueba SQL lo comprueba contra pg_constraint; aquí, lo declarado)
for (const t of ['facturas', 'contratos', 'gastos', 'comision_admin_fees', 'comision_admin_lineas', 'solicitudes_pago_retencion', 'socios']) {
  assert.ok(new RegExp('public\\.' + t + '\\b').test(sql.split('-- ── 2.')[0]), 'falta la fuente ' + t + ' en _sociedad_docs_filas');
}
console.log('sociedad_docs.test.js: OK');
