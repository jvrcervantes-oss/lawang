/* node plantillas_fabrica.test.js — plantillas_fabrica.ts frente a lo que debe cumplir (S5.2). Idéntico en Lawang y en el maestro.
   Los textos de fábrica y las consultas de `resuelve` son de cada repo (fuera del canon); lo que las ata a lo común es esto:
     1. Cada clave de valida.ts → PLANTILLAS tiene texto de fábrica y fila sembrada en la migración, y nada más.
     2. `resuelve` produce TODAS las variables que el catálogo sellado (migración) permite para esa clave — si el catálogo promete una
        variable que el código no sabe rellenar, el texto del cliente saldría sin ella y el motor caería a fábrica en silencio.
     3. El texto de fábrica usa solo variables permitidas y todas las obligatorias (las mismas reglas que se exigen al texto editado).
     4. El formato del importe es EL de la suite: en Lawang se compara con `lwFormatoImporte` de contracts/assets/dinero.js (el mismo
        número, todas las monedas, una rejilla de importes); en el maestro, los decimales por moneda con public.moneda_decimales.
        Dos reglas del mismo importe son dos reglas: el día que una cambie, esto falla en lugar de mandar un importe distinto al cliente. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

(async () => {
  const P = await import('./plantillas_arnes.mjs');
  const V = await import('./valida.ts');
  const F = await import('./plantillas_fabrica.ts');
  const CAT = P.catalogosSellados();
  const CLAVES = Object.keys(V.PLANTILLAS);
  let n = 0;
  const ok = (c, m) => { assert.ok(c, m); n++; };

  // 1 + 3
  assert.deepStrictEqual(Object.keys(CAT).sort(), [...CLAVES].sort());
  for (const k of CLAVES) {
    const t = F.textoFabrica(k), c = V.catalogoDe(CAT[k]);
    ok(t && c, k + ': texto de fábrica y catálogo sellado');
    assert.deepStrictEqual(V.validaTextoPlantilla(t.asunto, 'asunto', c), [], k + ' asunto'); n++;
    assert.deepStrictEqual(V.validaTextoPlantilla(t.cuerpo, 'cuerpo', c), [], k + ' cuerpo'); n++;
    ok((t.cuerpo_alt === null) === (c.variantes === 1), k + ': cuerpo_alt de fábrica ⇔ catálogo de dos variantes');
    if (t.cuerpo_alt !== null) { assert.deepStrictEqual(V.validaTextoPlantilla(t.cuerpo_alt, 'cuerpo_alt', c), [], k + ' cuerpo_alt'); n++; }
  }
  ok(F.textoFabrica('inventada') === null && F.textoFabrica('__proto__') === null && F.textoFabrica('toString') === null, 'una clave ajena no tiene fábrica');

  // 2: resuelve produce todo lo que el catálogo permite
  const rest = (db) => async (ruta) => {
    const r = await P.contestaDb(db)('https://ref.supabase.co/rest/v1/' + ruta);
    return JSON.parse(await r.text());
  };
  const comun = { marca: 'Acme', portal: 'https://erp.ejemplo.com/portal/', dominio: 'ejemplo.com' };
  const PEDIDOS = {
    enlace_firma_cadena: ['ana@cliente.test', { contrato_id: P.ID.contrato, firma_id: P.ID.firma }],
    copia_firmada_comprador: ['x@cliente.test', { contrato_id: P.ID.contrato }], copia_firmada_portal: ['x@cliente.test', { contrato_id: P.ID.contrato }],
    copia_firmada_manual: ['x@cliente.test', { contrato_id: P.ID.contrato }],
    aviso_anulacion: ['beto@cliente.test', { contrato_id: P.ID.contrato }], factura_primer_hito: ['x@cliente.test', { factura_id: P.ID.factura }],
    proforma_total: ['x@cliente.test', { factura_id: P.ID.proforma }], factura_vencimiento: ['x@cliente.test', { factura_id: P.ID.factura }],
  };
  for (const k of CLAVES) {
    const [to, ids] = PEDIDOS[k];
    const r = await F.resuelve(k, { contrato_id: '', factura_id: '', firma_id: '', ...ids }, to, { nombre: 'Ana' }, rest(P.baseFalsa()), comun);
    ok(!V.esFallo(r), k + ': resuelve devuelve datos · ' + JSON.stringify(r));
    for (const v of V.catalogoDe(CAT[k]).permitidas) ok(typeof r.vars[v] === 'string', k + ': resuelve produce la variable permitida {{' + v + '}}');
    for (const v of Object.values(r.vars)) ok(typeof v === 'string', k + ': todas las variables son texto');
  }
  const noReconoce = await F.resuelve('inventada', { contrato_id: '', factura_id: '', firma_id: '' }, 'x@y.test', {}, rest(P.baseFalsa()), comun);
  ok(V.esFallo(noReconoce) && noReconoce.status === 400, 'una clave ajena no se resuelve');

  // 4: el importe
  const AQUI = __dirname;
  const dinero = path.join(AQUI, '..', '..', '..', 'contracts', 'assets', 'dinero.js');
  const MONEDAS = ['EUR', 'USD', 'AUD', 'IDR', 'JPY', 'KRW', 'VND', 'CLP', 'GBP', 'XXX'];
  const TOTALES = [0, 0.5, 1, 36.245, 1234.5, 12500.5, 41668.33, 999999.99, 1000000.07, 123456789.12];
  let referencia, fuente;
  if (fs.existsSync(dinero)) {
    const D = require(dinero);
    referencia = (t, m) => D.lwFormatoImporte(t, m); fuente = 'contracts/assets/dinero.js (lwFormatoImporte)';
    assert.deepStrictEqual(Object.keys(D.LW_DECIMALES).sort(), ['AUD', 'CLP', 'EUR', 'IDR', 'JPY', 'KRW', 'USD', 'VND'], 'las monedas conocidas de dinero.js: si cambian, hay que actualizar DECIMALES en plantillas_fabrica.ts'); n++;
  } else {
    const sql = fs.readdirSync(path.join(AQUI, '..', '..', 'migraciones')).map((f) => fs.readFileSync(path.join(AQUI, '..', '..', 'migraciones', f), 'utf8')).join('\n');
    const m = /moneda_decimales\(p_moneda text\)[\s\S]*?in \(([^)]*)\)\s*then 0 else 2/.exec(sql);
    ok(m, 'public.moneda_decimales está en las migraciones del maestro');
    const ceros = [...m[1].matchAll(/'([A-Z]+)'/g)].map((x) => x[1]);
    referencia = (t, mon) => new Intl.NumberFormat('de-DE', { minimumFractionDigits: ceros.includes(mon) ? 0 : 2, maximumFractionDigits: ceros.includes(mon) ? 0 : 2 }).format(t) + ' ' + mon;
    fuente = 'public.moneda_decimales (' + ceros.join(',') + ')';
  }
  for (const mon of MONEDAS) for (const t of TOTALES) {
    const db = P.baseFalsa(); db.facturas[0].total = t; db.facturas[0].moneda = mon;
    const r = await F.resuelve('factura_primer_hito', { contrato_id: '', factura_id: P.ID.factura, firma_id: '' }, 'x@y.test', {}, rest(db), comun);
    assert.strictEqual(r.vars.importe, referencia(t, mon), `importe ${t} ${mon}`); n++;
  }
  console.log(`OK plantillas_fabrica.test.js — ${CLAVES.length} claves: fábrica ⇔ catálogo sellado ⇔ lo que resuelve produce · importe igual que ${fuente} (${MONEDAS.length * TOTALES.length} combinaciones) · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
