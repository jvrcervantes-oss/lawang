// El papel de una factura enviada por correo lo pinta send-contract-email DESDE LA FILA (15-oct-2026, revisión previa #350,
// Seguridad). Antes el navegador mandaba el HTML (o el PDF) y la edge lo enviaba tal cual: un agente podía mandar al comprador
// otra cuenta u otro importe y el sistema lo registraba como «la factura enviada».
//
// Este test EJECUTA la edge entera (index.ts sin tipos, con node:module.stripTypeScriptTypes) contra una base, un render y un
// SMTP falsos, y compara el HTML que llega al render con el que pinta LA PANTALLA (los ficheros fuente de /facturas/, con los
// cargadores reales de entities.js). Casos: factura, proforma, recibí, rectificativa (la de Lawang, que no existe y se borra;
// la del ERP, desde rectifica_id), cuenta «otros», sin emisor congelado; y los cortes 409 (cuenta sin verificar o inexistente,
// emisor de otra sociedad, total que no cuadra, impuestos colados, líneas que no son lista, sociedad que no existe). Contraprueba:
// con html/pdf/contrato_id hostiles en el cuerpo, al render llega el HTML de la fila y al registro el contrato de la fila.
// Corre con: node contracts/edge/send-contract-email/papel.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert'), modulo = require('node:module');
const raiz = path.join(__dirname, '..', '..', '..');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// ── la edge, ejecutable ─────────────────────────────────────────────────────────────────────────────────────────────
const fuenteTs = fs.readFileSync(path.join(__dirname, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
process.removeAllListeners('warning');   // stripTypeScriptTypes avisa de que es experimental
const fuenteJs = modulo.stripTypeScriptTypes(fuenteTs);
const imports = fuenteJs.match(/^import .*$/mg) || [];
ok(imports.length === 2 && imports.some((l) => /compartidos\.generated\.ts/.test(l)), 'la edge importa supabase-js y su compartidos.generated.ts, nada más');
const cuerpoEdge = fuenteJs.replace(/^import .*$/mg, '');

const TS = fs.readFileSync(path.join(__dirname, 'compartidos.generated.ts'), 'utf8');
function arrayDe(nombre) {   // mismo corte que firma-submit/compartidos.test.js
  const marca = `export const ${nombre}: string[] = [`;
  const desde = TS.indexOf(marca) + marca.length - 1;
  const hasta = TS.indexOf('\n];', desde);
  return JSON.parse('[' + TS.slice(desde + 1, hasta).replace(/\/\*[^*]*\*\//g, '').replace(/,\s*$/, '') + ']');
}
const FUENTES = arrayDe('FUENTES'), EXPORTA = arrayDe('EXPORTA');

const SITIO = 'https://lawangproperties.com';
const clona = (o) => (o == null ? o : JSON.parse(JSON.stringify(o)));
const elige = (fila, cols) => {
  if (!cols || cols.trim() === '*') return clona(fila);
  const o = {}; for (const c of cols.split(',').map((x) => x.trim())) o[c] = clona(fila[c]); return o;
};

function montaEdge(filas, opc = {}) {
  const r = { render: [], envio: [], inserts: [], rpc: [], selects: [], logs: [], errores: [], copias: [] };
  const consulta = (quien, tabla) => {
    const q = { quien, tabla, cols: null, eqs: [] };
    const b = {
      select(c) { q.cols = c; return b; }, eq(k, v) { q.eqs.push([k, v]); return b; }, order() { return b; }, limit() { return b; },
      async maybeSingle() {
        r.selects.push(q);
        if (opc.caida && opc.caida === tabla) return { data: null, error: { message: 'caída de prueba' } };
        const f = (filas[tabla] || []).find((x) => q.eqs.every(([k, v]) => String(x[k]) === String(v)));
        return { data: f ? elige(f, q.cols) : null, error: null };
      },
      insert(o) { r.inserts.push({ tabla, o: clona(o) }); return Promise.resolve({ error: null }); },
    };
    return b;
  };
  const createClient = (_url, clave) => clave === 'svc'
    ? { auth: { async getUser(jwt) { return jwt === 'tok' ? { data: { user: { id: 'u1', email: 'agente@lawang.test' } }, error: null } : { data: null, error: { message: 'x' } }; } },
        from: (t) => consulta('admin', t),
        async rpc(nom, a) { r.rpc.push(['admin', nom, a]); return { data: { modo: 'directo' }, error: null }; },
        storage: { from: () => ({ async upload(ruta) { r.copias.push(ruta); return { error: null }; } }) } }
    : { from: (t) => consulta('usuario', t),
        async rpc(nom, a) { r.rpc.push(['usuario', nom, a]); return { data: true, error: null }; } };
  const env = { SUPABASE_URL: 'https://prueba.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc', SUPABASE_ANON_KEY: 'anon',
                RENDER_SECRET: 'rs', SITIO_URL: SITIO, RENDER_URL: 'https://render.test' };
  let manejador = null;
  const Deno = { env: { get: (k) => env[k] }, serve(h) { manejador = h; } };
  const fetch = async (url, init) => {
    if (String(url).endsWith('/render-pdf')) {
      r.render.push(JSON.parse(init.body).html);
      if (opc.renderFalla) return { ok: false, status: 500 };
      return { ok: true, async arrayBuffer() { return new TextEncoder().encode('%PDF-1.4 de la fila').buffer; } };
    }
    r.envio.push({ url: String(url), cuerpo: JSON.parse(init.body) });
    return { ok: true, async text() { return '{"ok":true}'; } };
  };
  const consola = { log: (...a) => r.logs.push(a.join(' ')), error: (...a) => r.errores.push(a.join(' ')), warn() {} };
  new Function('createClient', 'FUENTES', 'EXPORTA', 'Deno', 'fetch', 'console', cuerpoEdge)(createClient, FUENTES, EXPORTA, Deno, fetch, consola);
  const pide = async (cuerpo) => {
    const res = await manejador(new Request('https://prueba.supabase.co/functions/v1/send-contract-email', {
      method: 'POST', headers: { authorization: 'Bearer tok', 'content-type': 'application/json', origin: SITIO }, body: JSON.stringify(cuerpo) }));
    return { s: res.status, o: await res.json() };
  };
  return { r, pide };
}

// ── la pantalla: los ficheros FUENTE de /facturas/ y los cargadores reales de entities.js ────────────────────────────
const FICHEROS = ['contracts/assets/dinero.js', 'contracts/assets/vocabulario.js', 'contracts/assets/entities.js',
  'intranet/facturas/totales.js', 'contracts/assets/compradores.js', 'intranet/facturas/documento.js', 'intranet/vencimientos/logica.js'];
const fuentesPantalla = FICHEROS.map((f) => fs.readFileSync(path.join(raiz, f), 'utf8'));
async function pantalla(fila, sociedades, cuentas) {
  const caja = {};
  new Function('caja', fuentesPantalla.join('\n;\n') +
    '\n;Object.assign(caja,{documentoPagina,cargarSociedades,cargarCuentasBancarias,conceptoCobroRecibi});')(caja);
  const sb = { rpc: (nom) => ({ order: async () => ({ data: clona(nom === 'sociedades_visibles' ? sociedades : cuentas), error: null }) }) };
  await caja.cargarSociedades(sb); await caja.cargarCuentasBancarias(sb);
  // lo que collect() devuelve con el documento guardado abierto: sus campos + sus líneas
  const d = { ...clona(fila.datos.fields), lineas: clona(fila.datos.lineas) };
  return caja.documentoPagina(d, { numero: fila.numero, emisor: clona(fila.datos.emisor) || null, base: SITIO });
}

// ── datos de prueba ───────────────────────────────────────────────────────────────────────────────────────────────
const F1 = '11111111-1111-4111-8111-111111111111', F0 = '00000000-0000-4000-8000-000000000000';
const C1 = '22222222-2222-4222-8222-222222222222', C_HOSTIL = '99999999-9999-4999-8999-999999999999';
const SOC = [
  { clave: 'tepi_sungai', label: 'Tepi', razon: 'PT TEPI SUNGAI', marca: 'Lawang', domicilio: 'Jl. Raya 1, Bali', npwp: '01.234.567', npwp_label: 'NPWP',
    nib: 'NIB-1', rep: 'I Wayan', logo: '/contracts/assets/brand/tepi.png', logo_alto: '14mm', emisor_debajo: false, folio: '#fbf8f2',
    tinta: { primary: '#2f5d50', deep: '#1d3b33' }, activa: true, orden: 1 },
  { clave: 'san_dal_woods', label: 'SDW', razon: 'PT SAN DAL WOODS', marca: '', domicilio: 'Jl. Sumba 2', npwp: '09.876', npwp_label: 'NIF',
    nib: '', rep: 'I Made', logo: '/contracts/assets/brand/sdw.png', logo_alto: null, emisor_debajo: true, folio: '', tinta: null, activa: true, orden: 2 },
];
const CTA = [
  { clave: 'bca_tepi', label: 'BCA Tepi', titular: 'PT TEPI SUNGAI', banco: 'BCA', cuenta: '1234567890', codigo: 'CENAIDJA',
    direccion: 'Jakarta', extra: { es: 'Indique el número de factura', en: 'Quote the invoice number' }, verificada_en: '2026-09-26T00:00:00Z',
    activa: true, es_escrow: false, orden: 1 },
  { clave: 'nueva', label: 'Nueva', titular: 'PT X', banco: 'BNI', cuenta: '555', codigo: 'BNI', direccion: '', extra: '', verificada_en: null,
    activa: false, es_escrow: false, orden: 2 },
  { clave: 'vieja', label: 'Vieja', titular: 'PT TEPI SUNGAI', banco: 'Mandiri', cuenta: '777000777', codigo: 'BMRI', direccion: '', extra: '',
    verificada_en: '2026-08-01T00:00:00Z', activa: false, es_escrow: false, orden: 3 },
];
const EMISOR = { clave: 'tepi_sungai', razon: 'PT TEPI SUNGAI', marca: 'Lawang', npwp: '01.234.567', npwp_label: 'NPWP', nib: 'NIB-1',
  domicilio: 'Jl. Raya 1, Bali', rep: 'I Wayan', congelado_en: '2026-10-14T08:00:00Z' };
const campos = (o = {}) => ({ tipo: 'factura', sociedad: 'tepi_sungai', cuenta: 'bca_tepi', fecha_emision: '2026-10-14', fecha_vencimiento: '2026-10-30',
  moneda: 'EUR', contrato_numero: 'CC00109', cliente_nombre: 'Ana Pérez', cliente_documento: 'Pasaporte X123', cliente_email: 'ana@cliente.test',
  proyecto_nombre: 'Tamarind Rise — L12', imp_etiqueta: 'PPN', imp_pct: '10', notas: 'Gracias por su confianza', ...o });
const factura = (o = {}, fields = {}, datos = {}) => {
  const lineas = datos.lineas !== undefined ? datos.lineas : [{ descripcion: 'Primer pago (10% del precio acordado)', importe: '1.000' }];
  return { id: F1, numero: 'INV-00157', tipo: 'factura', sociedad: 'tepi_sungai', moneda: 'EUR', fecha_emision: '2026-10-14', contrato_numero: 'CC00109',
    proyecto_nombre: 'Tamarind Rise — L12', cliente_nombre: 'Ana Pérez', contrato_id: C1, total: 1100, anulada: false, enviada: false,
    ...o, datos: { fields: campos(fields), lineas, emisor: EMISOR, ...datos } };
};
const base = (fila, extra = {}) => ({ facturas: [fila, ...(extra.facturas || [])], sociedades: SOC, cuentas_bancarias: CTA, config_instancia: [], contratos: [] });
const envia = (o = {}) => ({ to: 'ana@cliente.test', subject: 'Factura INV-00157', message: 'Adjunto', filename: 'INV-00157.pdf', factura_id: F1, ...o });

async function igualQuePantalla(nombre, fila, extra = {}) {
  const e = montaEdge(base(fila, extra));
  const res = await e.pide(envia({ factura_id: fila.id }));
  ok(res.s === 200 && res.o.ok === true && res.o.marcada === true, nombre + ': 200, enviada y marcada');
  ok(e.r.render.length === 1, nombre + ': un render');
  const esperado = await pantalla(fila, SOC.filter((s) => s.activa), CTA.filter((c) => c.activa));
  ok(e.r.render[0] === esperado, nombre + ': el HTML del render es EL MISMO que pinta la pantalla');
  ok(e.r.envio.length === 1 && e.r.envio[0].cuerpo.pdf_base64 === Buffer.from('%PDF-1.4 de la fila').toString('base64'), nombre + ': sale el PDF del render');
  return { e, html: e.r.render[0] };
}
async function corta(nombre, fila, codigo, cuerpo = {}) {
  const e = montaEdge(base(fila));
  const res = await e.pide(envia(cuerpo));
  ok(res.s === 409 && res.o.ok === false && res.o.codigo === codigo, nombre + ': 409 ' + codigo + ' (fue ' + res.s + ' ' + JSON.stringify(res.o) + ')');
  ok(typeof res.o.error === 'string' && !/_/.test(res.o.error), nombre + ': el error es una frase para la pantalla');
  ok(!e.r.render.length && !e.r.envio.length && !e.r.copias.length && !e.r.inserts.length, nombre + ': ni render, ni copia, ni SMTP, ni registro');
  ok(!e.r.rpc.some(([, nom]) => nom === 'factura_marca_enviada'), nombre + ': ni marca');
  return e;
}

(async () => {
  // ── 1. el papel de la fila es el de la pantalla ────────────────────────────────────────────────────────────────
  { const { e, html } = await igualQuePantalla('factura', factura());
    ok(html.includes('INV-00157') && html.includes('1234567890') && html.includes('PT TEPI SUNGAI'), 'factura: número, cuenta del catálogo y emisor');
    const reg = e.r.inserts.find((i) => i.tabla === 'correos_enviados');
    ok(reg && reg.o.factura_id === F1 && reg.o.contrato_id === C1 && reg.o.via === 'factura', 'factura: registro con la factura y el contrato DE LA FILA');
    ok(e.r.selects.some((q) => q.quien === 'usuario' && q.tabla === 'facturas' && q.cols === '*'), 'la fila se lee con la sesión del usuario');
    ok(!e.r.selects.some((q) => q.tabla === 'contratos'), 'con factura no se pregunta por el contrato del navegador'); }
  await igualQuePantalla('proforma', factura({ numero: 'PRO-0003', tipo: 'proforma', total: 55000 }, { tipo: 'proforma' },
    { lineas: [{ descripcion: 'Precio total', importe: '50.000' }] }));
  { const fila = factura({ numero: 'REC-0042', tipo: 'recibi', total: 500 }, { tipo: 'recibi', cuenta: '', imp_pct: '', imp_etiqueta: '' },
      { lineas: [{ descripcion: 'Cobro de la factura INV-00157 · Payment of invoice INV-00157', importe: '500' }] });
    const { html } = await igualQuePantalla('recibí', fila);
    ok(/Recib/.test(html) && !html.includes('Datos bancarios'), 'recibí: título de recibí y sin cuenta'); }
  { const fila = factura({}, { cuenta: 'otros', banco_titular: 'Notario Made', banco_nombre: 'BRI', banco_cuenta: '000111222', banco_codigo: 'BRINIDJA',
      banco_direccion: 'Denpasar', banco_extra: '' });
    const { html } = await igualQuePantalla('cuenta «otros»', fila);
    ok(html.includes('000111222'), 'cuenta «otros»: imprime la escrita a mano (deuda declarada aparte, #350)'); }
  { const fila = factura(); delete fila.datos.emisor;
    const { html } = await igualQuePantalla('sin emisor congelado', fila);
    ok(html.includes('PT TEPI SUNGAI') && html.includes('01.234.567'), 'sin emisor: identidad de la sociedad, como la pantalla'); }
  { const fila = factura({ sociedad: 'san_dal_woods' }, { sociedad: 'san_dal_woods' }, { emisor: { ...EMISOR, clave: 'san_dal_woods', razon: 'PT SAN DAL WOODS', npwp_label: 'NIF' } });
    await igualQuePantalla('otra sociedad (NIF, emisor debajo, sin tinta)', fila); }

  // ── 2. rectificativa ──────────────────────────────────────────────────────────────────────────────────────────────
  { // Lawang: no hay rectificativa en el servidor; rectifica_numero en datos.fields lo pudo escribir el navegador → no se imprime
    const fila = factura({}, { rectifica_numero: 'INV-00001', rectifica_fecha: '2026-01-01', rectificacion_motivo: 'inventado' });
    const e = montaEdge(base(fila));
    ok((await e.pide(envia())).s === 200, 'Lawang con rectifica_numero en los campos: se envía');
    ok(!/Rectifica a|rectificativa|INV-00001/i.test(e.r.render[0]), 'Lawang: rectifica_numero del navegador NO sale en el papel');
    const limpia = factura(); ok(e.r.render[0] === await pantalla(limpia, SOC, CTA.filter((c) => c.activa)), 'Lawang: el papel es el de la factura sin esos campos'); }
  { // ERP maestro: la R lleva rectifica_id; el número y la fecha salen de la ORIGINAL, el motivo de la columna
    const r = factura({ numero: 'R-0004', rectifica_id: F0, rectificacion_motivo: 'Importe mal escrito', rectificacion_tipo: 'diferencias', total: -200 },
      { imp_pct: '', imp_etiqueta: '', banco_de_servidor: true, banco_titular: 'PT TEPI SUNGAI', banco_nombre: 'BCA', banco_cuenta: '1234567890',
        banco_codigo: 'CENAIDJA', banco_direccion: 'Jakarta', banco_extra: { es: 'Indique el número de factura', en: 'Quote the invoice number' },
        rectifica_numero: 'INV-00100', rectifica_fecha: '2026-10-01', rectificacion_motivo: 'Importe mal escrito' },
      { lineas: [{ descripcion: 'Rectificación de INV-00100', importe: '-200' }] });
    const original = { id: F0, numero: 'INV-00100', fecha_emision: '2026-10-01', tipo: 'factura', sociedad: 'tepi_sungai' };
    const { e, html } = await igualQuePantalla('rectificativa del ERP (rectifica_id)', r, { facturas: [original] });
    ok(html.includes('Rectifica a · Corrects: <b>INV-00100</b>') && html.includes('Importe mal escrito'), 'ERP: «Rectifica a» con el número de la original');
    ok(e.r.selects.some((q) => q.quien === 'admin' && q.tabla === 'facturas' && q.eqs.some(([k, v]) => k === 'id' && v === F0)), 'ERP: lee la original por rectifica_id');
    const falsa = factura({ numero: 'R-0005', rectifica_id: F0, rectificacion_motivo: 'Importe mal escrito', total: -200 },
      { imp_pct: '', rectifica_numero: 'INV-HOSTIL' }, { lineas: [{ descripcion: 'x', importe: '-200' }] });
    const e2 = montaEdge(base(falsa, { facturas: [original] }));
    ok((await e2.pide(envia())).s === 200 && e2.r.render[0].includes('INV-00100') && !e2.r.render[0].includes('INV-HOSTIL'), 'ERP: el número de los campos no manda, manda la original');
    const huerfana = montaEdge(base(falsa));   // rectifica_id que no lleva a ninguna factura
    ok((await huerfana.pide(envia())).s === 409 && !huerfana.r.render.length, 'ERP: rectifica_id sin original → 409'); }

  // ── 3. los cortes, antes de render / copia / SMTP / registro / marca ─────────────────────────────────────────────
  await corta('cuenta sin verificar', factura({}, { cuenta: 'nueva' }), 'cuenta_no_verificada');
  await corta('cuenta inexistente', factura({}, { cuenta: 'no_existe' }), 'cuenta_no_verificada');
  { const { html } = await (async () => { const e = montaEdge(base(factura({}, { cuenta: 'vieja' }))); await e.pide(envia()); return { html: e.r.render[0] }; })();
    ok(html && html.includes('777000777'), 'cuenta verificada pero hoy desactivada: se sigue imprimiendo (no se filtra por activa)'); }
  await corta('emisor de otra sociedad', factura({}, {}, { emisor: { ...EMISOR, clave: 'san_dal_woods' } }), 'emisor_no_coincide');
  await corta('emisor sin clave', factura({}, {}, { emisor: { razon: 'PT FALSA' } }), 'emisor_no_coincide');
  await corta('emisor que no es objeto', factura({}, {}, { emisor: 'PT FALSA' }), 'emisor_no_coincide');
  await corta('total que no cuadra', factura({ total: 999 }), 'documento_incoherente');
  await corta('total nulo', factura({ total: null }), 'documento_incoherente');
  await corta('impuestos del catálogo colados en Lawang', factura({}, { impuestos_sel: [{ id: 'x', nombre: 'IVA', pct: 21, clase: 'suma' }] }), 'documento_incoherente');
  await corta('líneas que no son lista (texto)', factura({}, {}, { lineas: 'Primer pago 1000' }), 'documento_incoherente');
  await corta('líneas que no son lista (objeto)', factura({}, {}, { lineas: { 0: { descripcion: 'x', importe: '1000' } } }), 'documento_incoherente');
  await corta('líneas con un hueco nulo', factura({}, {}, { lineas: [null] }), 'documento_incoherente');
  await corta('sin líneas', factura({}, {}, { lineas: null }), 'documento_incoherente');
  { const fila = factura(); fila.datos.fields = 'texto'; await corta('campos que no son objeto', fila, 'documento_incoherente'); }
  await corta('sociedad que ya no existe', factura({ sociedad: 'borrada' }, {}, { emisor: { ...EMISOR, clave: 'borrada' } }), 'sociedad_desconocida');
  await corta('tipo desconocido', factura({ tipo: 'albaran' }), 'documento_incoherente');
  // una caída leyendo el catálogo no envía nada
  { const e = montaEdge(base(factura()), { caida: 'cuentas_bancarias' });
    const res = await e.pide(envia());
    ok(res.s === 500 && !e.r.render.length && !e.r.envio.length && !e.r.inserts.length, 'catálogo caído: 500 y no sale nada'); }

  // ── 4. contraprueba: lo que manda el navegador no llega a ningún sitio ───────────────────────────────────────────
  { const fila = factura({}, { banco_de_servidor: true, banco_cuenta: 'ES00 HOSTIL 0000', banco_titular: 'Estafador SL' });
    const e = montaEdge(base(fila));
    const res = await e.pide(envia({ html: '<h1>FACTURA FALSA</h1><p>Paga a ES00 HOSTIL</p>', pdf_base64: Buffer.from('%PDF-1.4 FALSO').toString('base64'),
      contrato_id: C_HOSTIL }));
    ok(res.s === 200, 'cuerpo hostil: se envía (el papel bueno)');
    ok(e.r.render.length === 1 && !e.r.render[0].includes('FALSA') && !e.r.render[0].includes('HOSTIL') && !e.r.render[0].includes('Estafador'),
      'cuerpo hostil: al render no llega ni el html del navegador ni los banco_* colados con banco_de_servidor');
    ok(e.r.render[0].includes('1234567890'), 'cuerpo hostil: la cuenta impresa es la del catálogo');
    const sinMarca = factura(); delete sinMarca.datos.fields.banco_de_servidor;
    ok(e.r.render[0] === await pantalla(sinMarca, SOC, CTA.filter((c) => c.activa)), 'cuerpo hostil: el HTML del render es el de la fila');
    ok(e.r.envio[0].cuerpo.pdf_base64 === Buffer.from('%PDF-1.4 de la fila').toString('base64'), 'cuerpo hostil: el PDF enviado es el del render, no el del navegador');
    const reg = e.r.inserts.find((i) => i.tabla === 'correos_enviados');
    ok(reg.o.contrato_id === C1, 'cuerpo hostil: el registro va al contrato de la fila, no al del navegador');
    ok(e.r.logs.some((l) => /ignorado/.test(l)) && !e.r.logs.concat(e.r.errores).some((l) => /FALSA|HOSTIL/.test(l)), 'cuerpo hostil: queda log de que vino html, sin su contenido'); }
  { const e = montaEdge(base(factura()), { renderFalla: true });
    const res = await e.pide(envia({ pdf_base64: Buffer.from('%PDF-1.4 FALSO').toString('base64') }));
    ok(res.s === 502 && !e.r.envio.length && !e.r.inserts.length, 'render caído con factura: 502, el PDF del navegador NO sirve de respaldo'); }
  { const e = montaEdge(base(factura()));
    const res = await e.pide(envia({ pdf_base64: Buffer.from('%PDF-1.4 FALSO').toString('base64') }));
    ok(res.s === 200 && e.r.render.length === 1 && e.r.envio[0].cuerpo.pdf_base64 === Buffer.from('%PDF-1.4 de la fila').toString('base64'),
      'solo pdf_base64 con factura: se ignora y se pinta la fila'); }
  { const e = montaEdge(base(factura()));
    ok((await e.pide(envia())).s === 200, 'factura sin html ni pdf (la pantalla de la siguiente fase): se envía'); }
  { const e = montaEdge(base(factura({ id: F0 })));
    const res = await e.pide(envia());   // la factura F1 no es visible para este usuario
    ok(res.s === 403 && res.o.error === 'factura_no_visible' && !e.r.render.length, 'factura no visible: 403 de siempre'); }

  // ── 5. los correos de contrato no cambian ─────────────────────────────────────────────────────────────────────────
  { const e = montaEdge({ facturas: [], sociedades: SOC, cuentas_bancarias: CTA, config_instancia: [], contratos: [{ id: C1 }] });
    const res = await e.pide({ to: 'ana@cliente.test', subject: 'Contrato', message: 'x', contrato_id: C1, html: '<p>contrato</p>' });
    ok(res.s === 200 && e.r.render[0] === '<p>contrato</p>', 'contrato: el html del contrato sigue llegando al render como antes');
    const e2 = montaEdge({ facturas: [], sociedades: SOC, cuentas_bancarias: CTA, config_instancia: [], contratos: [{ id: C1 }] });
    ok((await e2.pide({ to: 'ana@cliente.test', contrato_id: C1 })).s === 400, 'contrato sin html ni pdf: 400 falta_html_o_pdf, como antes'); }

  console.log('OK papel.test.js — ' + n + ' comprobaciones: el papel de la factura sale de la fila y es el de la pantalla (factura, proforma, recibí, ' +
    'rectificativa Lawang/ERP, «otros», sin emisor); 409 antes de render/SMTP/registro/marca; html/pdf/contrato del navegador ignorados');
})().catch((e) => { console.error(e); process.exit(1); });
