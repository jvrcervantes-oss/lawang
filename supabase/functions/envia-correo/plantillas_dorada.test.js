/* node plantillas_dorada.test.js — PRUEBA DORADA de las plantillas de Lawang (S5.2): para cada una de las 8 claves, lo que sale de la edge
   por `plantilla` + ids tiene que ser IDÉNTICO, byte a byte (asunto, texto plano y HTML), a lo que sale hoy por el camino libre con el
   asunto y el mensaje que componen los LLAMANTES. Solo Lawang (el maestro no tiene esos llamantes).

   Cómo es «la salida actual», sin repuntar ningún llamante (S5.3):
     · copia_firmada_manual y aviso_anulacion: se EJECUTAN las funciones reales de contracts/app.html (copiaMensaje, mensajeAnulacion),
       extraídas de la página y corridas con `vm`; el asunto de cada una es un literal de esa misma página.
     · el resto vive inline dentro de firma-submit y factura-vencimiento (no se pueden importar sin su runtime): aquí están TRANSCRITAS
       tal cual, y cada literal de texto que usa la transcripción tiene que seguir existiendo en el código de los llamantes —si alguien
       cambia una frase allí, esta prueba falla y obliga a decidir si cambia también el texto de fábrica o no—. El importe sale de la
       función real (contracts/assets/dinero.js → lwFormatoImporte).
     · el envío es el camino REAL: el index.ts de la edge con el SMTP falso, comparando lo que habría mandado nodemailer.
   La prueba se prueba a sí misma: al final copia la edge a un directorio temporal, ROMPE a propósito un texto de fábrica y exige que la
   misma comparación se ponga en ROJO. Sin eso, una dorada que nunca falla no mide nada. */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const RAIZ = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(RAIZ, ...p), 'utf8').replace(/\r\n/g, '\n');
const FIRMA_SUBMIT = leer('contracts', 'edge', 'firma-submit', 'index.ts');
const FACTURA_VENC = leer('contracts', 'edge', 'factura-vencimiento', 'index.ts');
const APP = leer('contracts', 'app.html');
const FUENTES = FIRMA_SUBMIT + '\n' + FACTURA_VENC + '\n' + APP;
const D = require(path.join(RAIZ, 'contracts', 'assets', 'dinero.js'));

(async () => {
  const A = await import('./arnes.mjs');
  const P = await import('./plantillas_arnes.mjs');
  const V = await import('./valida.ts');
  const CLAVES = Object.keys(V.PLANTILLAS).filter((k) => !P.SOLO_LAWANG.includes(k));   // las de una sola instancia tienen su propia prueba
  const DOM = 'lawangproperties.com';
  const CONFIG = [['marca', 'Lawang'], ['dominio_web', DOM], ['url_intranet', 'https://lawangproperties.com/intranet/'],
    ['email_avisos_soporte', 'soporte@lawangproperties.com'], ['email_avisos_sistema', 'sistema@lawangproperties.com']];
  const PORTAL = 'https://lawangproperties.com/portal/';
  const SITIO = 'https://lawangproperties.com';
  const PDF = Buffer.from('%PDF-1.7 falso').toString('base64');

  // ── la transcripción de lo que componen los llamantes (cada S('…') debe seguir en su código) ─────────────────────────────
  const usadas = new Set();
  const S = (lit) => { usadas.add(lit); return lit; };
  const primero = (n) => String(n).split(' ')[0];
  const hola = (n) => 'Hola' + (n ? ' ' + primero(n) : '');
  const COLA = S('\n\nLawang Tropical Properties');
  const GUARDALO = S('\n\nGuárdalo: es el documento con el registro de firma electrónica que acredita la operación.');
  const ctx = vm.createContext({ SAVED_CONTRACT: { numero: '' } });
  const extrae = (nombre) => { const i = APP.indexOf('function ' + nombre + '('); assert.ok(i >= 0, 'no encuentro ' + nombre + ' en app.html'); return APP.slice(i, APP.indexOf('\n}\n', i) + 3); };
  vm.runInContext(extrae('mensajeAnulacion') + '\n' + extrae('copiaMensaje'), ctx);

  const LEGADO = {
    // firma-submit: enlace del siguiente firmante de la cadena
    enlace_firma_cadena: ({ nombre, numero, enlace }) => ({ subject: S('Documento para firmar · ') + numero,
      message: hola(nombre) + S(', aquí tienes el enlace para firmar el documento de Lawang Tropical Properties: ') + enlace + S('\n\nEl enlace caduca en 30 días.\n\nLawang Tropical Properties') }),
    // firma-submit: repartirFirmado, comprador, con el PDF adjunto
    copia_firmada_comprador: ({ nombre, numero, proyecto }) => ({ subject: S('Tu contrato firmado · ') + numero,
      message: hola(nombre) + ',' + S('\n\nHemos recibido tu firma. Aquí tienes tu copia del contrato ') + numero + (proyecto ? ' (' + proyecto + ')' : '') + S(', ya firmado.') +
        GUARDALO + S('\n\nEl documento firmado va adjunto a este correo.') + COLA }),
    // firma-submit: avisarSegunPlan, comprador que entra al portal
    copia_firmada_portal: ({ nombre, numero, proyecto }) => ({ subject: S('Tu contrato firmado · ') + numero,
      message: hola(nombre) + S(',\n\nHemos recibido tu firma. Tu copia del contrato ') + numero + (proyecto ? ' (' + proyecto + ')' : '') +
        S(', ya firmado, está en tu portal de cliente: ') + SITIO + '/portal/' + S('\n\nEntra con este mismo correo: te enviaremos un enlace de acceso.') + GUARDALO + COLA }),
    // contracts/app.html: copiaMensaje() (se ejecuta la real) y el asunto de copiaEnviarA()
    copia_firmada_manual: ({ nombre, numero }) => { ctx.SAVED_CONTRACT = { numero }; return { subject: S('Tu contrato firmado · ') + numero, message: ctx.copiaMensaje(nombre, {}) }; },
    // contracts/app.html: mensajeAnulacion() (se ejecuta la real) y el asunto de avisaAnulacion()
    aviso_anulacion: ({ nombre, numero, yaFirmo, motivo }) => ({ subject: S('Actualización del documento ') + numero + S(' — Lawang Tropical Properties'),
      message: ctx.mensajeAnulacion({ firmante_nombre: nombre }, numero, yaFirmo, motivo) }),
    // firma-submit: facturarPrimerHito
    factura_primer_hito: ({ nombre, factura, numero, concepto, total, moneda }) => ({ subject: S('Factura ') + factura + S(' · ') + numero,
      message: hola(nombre) + ',' + S('\n\nAdjuntamos la factura ') + factura + S(' correspondiente al primer pago del contrato ') + numero + '.' +
        S('\n\nConcepto: ') + concepto + S('\nImporte: ') + D.lwFormatoImporte(total, moneda) + S('\n\nLos datos para la transferencia están en la propia factura.') + S('\n\n\nLawang Tropical Properties') }),
    // firma-submit: enviarProformaTotal
    proforma_total: ({ nombre, factura, numero, total, moneda }) => ({ subject: S('Factura proforma ') + factura + S(' · ') + numero,
      message: hola(nombre) + ',' + S('\n\nAdjuntamos la factura proforma ') + factura + S(' con el importe total del proyecto contratado en ') + numero + '.' +
        S('\n\nImporte total: ') + D.lwFormatoImporte(total, moneda) + S('\n\nEs un documento informativo, sin validez fiscal: el cobro de cada pago se factura aparte, ') + S('a medida que vence.') + S('\n\n\nLawang Tropical Properties') }),
    // factura-vencimiento
    factura_vencimiento: ({ nombre, factura, numero, concepto, fecha, total, moneda }) => ({ subject: S('Factura ') + factura + S(' · vencimiento del ') + fecha + S(' · ') + numero,
      message: hola(nombre) + ',' + S('\n\nEl próximo pago de tu contrato ') + numero + S(' vence el ') + fecha + S('. Adjuntamos la factura ') + factura + S(' para que puedas realizarlo con tiempo.') +
        S('\n\nConcepto: ') + concepto + S('\nImporte: ') + D.lwFormatoImporte(total, moneda) +
        S('\n\nLos datos para la transferencia están en la propia factura. Si el pago ya está en camino, ignora este aviso.') + S('\n\n\nLawang Tropical Properties') }),
  };
  assert.deepStrictEqual(Object.keys(LEGADO).sort(), [...CLAVES].sort(), 'un legado por clave');

  // ── escenarios: cada uno retoca la base falsa y dice con qué entradas compondría hoy el llamante ────────────────────────────
  const dbL = () => P.baseFalsa({ dominio: DOM });
  const ESC = {
    enlace_firma_cadena: [
      ['Ana', (db) => {}, { nombre: 'Ana López', numero: 'CR00123', enlace: `https://${DOM}/contracts/firmar.html?t=tok.abc-1` }, { to: 'ana@cliente.test' }],
      ['sin nombre', (db) => { db.contrato_firmas[0].firmante_nombre = ''; }, { nombre: '', numero: 'CR00123', enlace: `https://${DOM}/contracts/firmar.html?t=tok.abc-1` }, { to: 'ana@cliente.test' }],
      ['acentos', (db) => { db.contrato_firmas[0].firmante_nombre = 'José Ñandú'; db.contratos[0].numero = 'PA00007'; }, { nombre: 'José Ñandú', numero: 'PA00007', enlace: `https://${DOM}/contracts/firmar.html?t=tok.abc-1` }, { to: 'ana@cliente.test' }],
    ],
    copia_firmada_comprador: [
      ['con proyecto', () => {}, { nombre: 'Dora Mar', numero: 'CR00123', proyecto: 'Palm Field' }, { to: 'dora@cliente.test', vars: { nombre: 'Dora Mar' } }],
      ['sin proyecto', (db) => { db.contratos[0].proyecto_nombre = null; }, { nombre: 'Dora Mar', numero: 'CR00123', proyecto: '' }, { to: 'dora@cliente.test', vars: { nombre: 'Dora Mar' } }],
      ['proyecto en datos y sin nombre', (db) => { db.contratos[0].proyecto_nombre = null; db.contratos[0].pf = 'Sumba Hills'; }, { nombre: '', numero: 'CR00123', proyecto: 'Sumba Hills' }, { to: 'dora@cliente.test', vars: {} }],
    ],
    copia_firmada_portal: [
      ['con proyecto', () => {}, { nombre: 'Dora Mar', numero: 'CR00123', proyecto: 'Palm Field' }, { to: 'dora@cliente.test', vars: { nombre: 'Dora Mar' } }],
      ['sin proyecto ni nombre', (db) => { db.contratos[0].proyecto_nombre = null; }, { nombre: '', numero: 'CR00123', proyecto: '' }, { to: 'dora@cliente.test', vars: {} }],
    ],
    copia_firmada_manual: [
      ['con nombre', () => {}, { nombre: 'Dora Mar', numero: 'CR00123' }, { to: 'dora@cliente.test', vars: { nombre: 'Dora Mar' } }],
      ['sin nombre', () => {}, { nombre: '', numero: 'CR00123' }, { to: 'dora@cliente.test', vars: {} }],
    ],
    aviso_anulacion: [
      ['quien ya firmó, con motivo', () => {}, { nombre: 'Beto Ruiz', numero: 'CR00123', yaFirmo: true, motivo: 'Cambia la cláusula 4' }, { to: 'beto@cliente.test' }],
      ['quien ya firmó, sin motivo', (db) => { db.contrato_firmas[1].anulado_justificacion = null; }, { nombre: 'Beto Ruiz', numero: 'CR00123', yaFirmo: true, motivo: '' }, { to: 'beto@cliente.test' }],
      ['quien no había firmado', () => {}, { nombre: 'Carla Gil', numero: 'CR00123', yaFirmo: false, motivo: '' }, { to: 'carla@cliente.test' }],
    ],
    factura_primer_hito: [
      ['EUR', () => {}, { nombre: 'Eva Sol', factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Primer pago (30% del precio acordado) — a la firma', total: 12500.5, moneda: 'EUR' }, { to: 'eva@cliente.test', vars: { nombre: 'Eva Sol' } }],
      ['IDR sin céntimos', (db) => { Object.assign(db.facturas[0], { total: 1250000000, moneda: 'IDR' }); }, { nombre: 'Eva Sol', factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Primer pago (30% del precio acordado) — a la firma', total: 1250000000, moneda: 'IDR' }, { to: 'eva@cliente.test', vars: { nombre: 'Eva Sol' } }],
      ['sin nombre', () => {}, { nombre: '', factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Primer pago (30% del precio acordado) — a la firma', total: 12500.5, moneda: 'EUR' }, { to: 'eva@cliente.test', vars: {} }],
    ],
    proforma_total: [
      ['EUR', () => {}, { nombre: 'Eva Sol', factura: 'PRO-2026-0003', numero: 'CR00123', total: 41668.33, moneda: 'EUR' }, { to: 'eva@cliente.test', vars: { nombre: 'Eva Sol' }, factura_id: P.ID.proforma }],
      ['USD', (db) => { Object.assign(db.facturas[1], { total: 99999.99, moneda: 'USD' }); }, { nombre: 'Eva Sol', factura: 'PRO-2026-0003', numero: 'CR00123', total: 99999.99, moneda: 'USD' }, { to: 'eva@cliente.test', vars: { nombre: 'Eva Sol' }, factura_id: P.ID.proforma }],
    ],
    factura_vencimiento: [
      ['EUR', () => {}, { nombre: 'Eva Sol', factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Primer pago (30% del precio acordado) — a la firma', fecha: '2026-11-15', total: 12500.5, moneda: 'EUR' }, { to: 'eva@cliente.test', vars: { nombre: 'Eva Sol' } }],
      ['IDR y otra fecha', (db) => { Object.assign(db.facturas[0], { total: 87500000, moneda: 'IDR', venc: '2027-01-05' }); db.facturas[0].lineas[0].descripcion = 'Hito 2 (parte ya entregada a cuenta: descontada) — vence el 2027-01-05'; },
        { nombre: 'Eva Sol', factura: 'INV-2026-0007', numero: 'CR00123', concepto: 'Hito 2 (parte ya entregada a cuenta: descontada) — vence el 2027-01-05', fecha: '2027-01-05', total: 87500000, moneda: 'IDR' }, { to: 'eva@cliente.test', vars: { nombre: 'Eva Sol' } }],
    ],
  };
  const IDS = { enlace_firma_cadena: { contrato_id: P.ID.contrato, firma_id: P.ID.firma }, copia_firmada_comprador: { contrato_id: P.ID.contrato }, copia_firmada_portal: { contrato_id: P.ID.contrato },
    copia_firmada_manual: { contrato_id: P.ID.contrato }, aviso_anulacion: { contrato_id: P.ID.contrato }, factura_primer_hito: { factura_id: P.ID.factura },
    proforma_total: { factura_id: P.ID.proforma }, factura_vencimiento: { factura_id: P.ID.factura } };

  async function manda(dir, db, cuerpo) {
    P.entorno(db, { config: CONFIG });
    const m = await A.cargaEdge(dir);
    const res = await A.llama(m, { cabeceras: P.SERVICIO, cuerpo });
    assert.strictEqual(res.status, 200, JSON.stringify(cuerpo).slice(0, 80) + ' → ' + res.crudo);
    assert.strictEqual(A.estado.correo.correos.length, 1);
    return { correo: P.normaliza(A.estado.correo.correos[0]), cuerpo: res.cuerpo };
  }

  /** Compara las 8 claves; devuelve el número de comparaciones. Lanza en cuanto una difiere. */
  async function dorada(dir) {
    let n = 0;
    for (const k of CLAVES) for (const [nombre, retoca, entrada, pet] of ESC[k]) {
      const db = dbL(); retoca(db);
      const attach = V.PLANTILLAS[k].adjunto;
      const pdf = attach ? { pdf_base64: PDF, filename: 'doc.pdf' } : {};
      const legado = LEGADO[k](entrada);
      const libre = await manda(dir, dbL(), { to: pet.to, attach, ...pdf, subject: legado.subject, message: legado.message });
      // la fila retocada solo cambia la base falsa de la ruta por plantilla: la libre no lee nada
      const nuevo = await manda(dir, db, { plantilla: k, to: pet.to, attach, ...pdf, ...IDS[k], ...(pet.factura_id ? { factura_id: pet.factura_id } : {}), ...(pet.vars ? { vars: pet.vars } : {}) });
      assert.strictEqual(nuevo.cuerpo.plantilla, k);
      assert.strictEqual(nuevo.correo.subject, libre.correo.subject, `${k} (${nombre}): el ASUNTO difiere\n  plantilla: ${nuevo.correo.subject}\n  llamante : ${libre.correo.subject}`);
      assert.strictEqual(nuevo.correo.text, libre.correo.text, `${k} (${nombre}): el TEXTO difiere\n--- plantilla ---\n${nuevo.correo.text}\n--- llamante ---\n${libre.correo.text}`);
      assert.strictEqual(nuevo.correo.html, libre.correo.html, `${k} (${nombre}): el HTML difiere`);
      assert.deepStrictEqual(nuevo.correo.adjuntos, libre.correo.adjuntos);
      n += 3;
    }
    return n;
  }

  // 1. la dorada de verdad, contra la edge de este repo
  const comparaciones = await dorada(__dirname);

  // 2. cada literal que la transcripción usa sigue en el código de los llamantes (si alguien edita una frase allí, esto avisa)
  let literales = 0;
  for (const lit of usadas) for (const trozo of lit.split('\n')) { if (trozo.trim() === '') continue; assert.ok(FUENTES.includes(trozo), 'el literal «' + trozo + '» ya no está en firma-submit, factura-vencimiento ni app.html: los llamantes cambiaron y la transcripción de esta prueba (y el texto de fábrica) hay que revisarlos'); literales++; }

  // 3. LA PRUEBA SE PRUEBA: se rompe a propósito un texto de fábrica en una copia y la misma comparación tiene que ponerse en ROJO
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dorada-plantillas-'));
  let rojos = 0;
  try {
    const rotos = [
      ['Importe: {{importe}}', 'Importe : {{importe}}'],                                  // factura_primer_hito y factura_vencimiento
      ['aquí tienes el enlace para firmar', 'aqui tienes el enlace para firmar'],         // enlace_firma_cadena
      ['Hemos recibido tu firma. Aquí tienes', 'Hemos recibido su firma. Aquí tienes'],   // copia_firmada_comprador
      ['{{bloque_motivo}}En cuanto', '{{bloque_motivo}} En cuanto'],                      // aviso_anulacion (quien firmó)
    ];
    for (const [de, a] of rotos) {
      fs.rmSync(tmp, { recursive: true, force: true }); fs.mkdirSync(tmp);
      for (const f of fs.readdirSync(__dirname)) if (/\.(ts|mjs)$/.test(f)) fs.copyFileSync(path.join(__dirname, f), path.join(tmp, f));
      const fab = path.join(tmp, 'plantillas_fabrica.ts');
      const txt = fs.readFileSync(fab, 'utf8');
      assert.ok(txt.includes(de), 'el texto a romper no está en la fábrica: ' + de);
      fs.writeFileSync(fab, txt.replace(de, a));
      let cayo = false;
      try { await dorada(tmp); } catch (e) { cayo = e instanceof assert.AssertionError; }
      assert.ok(cayo, 'ROTO A PROPÓSITO («' + de + '» → «' + a + '») y la dorada siguió en VERDE: no mide nada');
      rojos++;
    }
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }

  console.log(`OK plantillas_dorada.test.js — 8 claves × escenarios: ${comparaciones} comparaciones (asunto, texto, HTML) plantilla == llamantes, 0 diferencias · ${literales} literales presentes en los llamantes · ${rojos} roturas a propósito, las ${rojos} en ROJO`);
})().catch((e) => { console.error(e); process.exit(1); });
