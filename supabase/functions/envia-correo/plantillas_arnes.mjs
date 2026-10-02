// Base de datos FALSA para las pruebas de plantillas de correo (S5.2). Idéntica en Lawang y en el maestro.
// Contesta, dentro del fetch del arnés, las lecturas que hace la edge a PostgREST: contratos, contrato_firmas, facturas y
// correo_plantillas. Filtra por `col=eq.valor` (lo único que usa plantillas_fabrica.ts) y devuelve las filas tal cual: los alias del
// `select` (pf, venc, lineas) ya vienen puestos en las filas de prueba. Anota cada consulta en `db.lecturas`.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { reinicia, CONFIG_BASE } from './arnes.mjs';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
export const MIGRACION = '20261002100000_correo_plantillas.sql';

/** Ruta de la migración de plantillas en ESTE repo (Lawang: supabase/migrations · maestro: erp/migraciones). */
export function rutaMigracion() {
  for (const d of [path.join(AQUI, '..', '..', 'migrations'), path.join(AQUI, '..', '..', 'migraciones')]) {
    const f = path.join(d, MIGRACION);
    if (fs.existsSync(f)) return f;
  }
  throw new Error('no encuentro ' + MIGRACION + ' junto a esta edge');
}

/** El catálogo SELLADO de cada clave, leído del INSERT de la migración: ('clave', '{json}'::jsonb). Es el único dueño de ese dato. */
export function catalogosSellados() {
  const sql = fs.readFileSync(rutaMigracion(), 'utf8');
  const out = {};
  for (const m of sql.matchAll(/\('([a-z_]+)',\s*'(\{"permitidas".*?\})'::jsonb\)/g)) out[m[1]] = JSON.parse(m[2]);
  return out;
}

export const ID = {
  contrato: '11111111-1111-4111-8111-111111111111', contrato2: '12121212-1212-4121-8121-121212121212',
  firma: '22222222-2222-4222-8222-222222222222', firmaFirmada: '23232323-2323-4232-8232-232323232323', firmaAnulada: '24242424-2424-4242-8242-242424242424',
  factura: '33333333-3333-4333-8333-333333333333', proforma: '44444444-4444-4444-8444-444444444444',
};
export const SECRETO = 'envio-falso';
export const SERVICIO = { 'x-render-secret': SECRETO };

/** Filas de partida (se pueden retocar por prueba). `dominio` es el dominio_web de la config que use la prueba. */
export function baseFalsa({ dominio = 'ejemplo.com' } = {}) {
  return {
    contratos: [
      { id: ID.contrato, numero: 'CR00123', proyecto_nombre: 'Palm Field', pf: null, pdf_firmado_path: 'firmados/CR00123.pdf' },
      { id: ID.contrato2, numero: 'CR00200', proyecto_nombre: null, pf: null, pdf_firmado_path: 'firmados/CR00200.pdf' },
    ],
    contrato_firmas: [
      { id: ID.firma, contrato_id: ID.contrato, enlace_firma: `https://${dominio}/contracts/firmar.html?t=tok.abc-1`, firmante_nombre: 'Ana López',
        firmante_email: 'ana@cliente.test', estado: 'pendiente', firmado_en: null, anulado_en: null, anulado_justificacion: null },
      { id: ID.firmaFirmada, contrato_id: ID.contrato, enlace_firma: null, firmante_nombre: 'Beto Ruiz', firmante_email: 'beto@cliente.test',
        estado: 'anulada', firmado_en: '2026-09-01T10:00:00Z', anulado_en: '2026-10-01T10:00:00Z', anulado_justificacion: 'Cambia la cláusula 4' },
      { id: ID.firmaAnulada, contrato_id: ID.contrato, enlace_firma: null, firmante_nombre: 'Carla Gil', firmante_email: 'carla@cliente.test',
        estado: 'anulada', firmado_en: null, anulado_en: '2026-10-01T10:00:00Z', anulado_justificacion: null },
    ],
    facturas: [
      { id: ID.factura, numero: 'INV-2026-0007', tipo: 'factura', anulada: false, contrato_numero: 'CR00123', total: 12500.5, moneda: 'EUR',
        lineas: [{ descripcion: 'Primer pago (30% del precio acordado) — a la firma', importe: '12500.5' }], venc: '2026-11-15' },
      { id: ID.proforma, numero: 'PRO-2026-0003', tipo: 'proforma', anulada: false, contrato_numero: 'CR00123', total: 41668.33, moneda: 'EUR',
        lineas: [{ descripcion: 'Total del proyecto', importe: '41668.33' }], venc: null },
    ],
    correo_plantillas: [],
    fallos: {},          // tabla → status HTTP forzado (404 = tabla ausente, 500 = caída)
    lanza: {},           // tabla → true: el fetch lanza (red caída)
    lecturas: [],
  };
}

/** Un `extra` para `reinicia({ extra })`. */
export function contestaDb(db) {
  return async (u) => {
    const url = new URL(u);
    const m = /\/rest\/v1\/(contratos|contrato_firmas|facturas|correo_plantillas)$/.exec(url.pathname);
    if (!m) return null;
    const tabla = m[1];
    db.lecturas.push(tabla + '?' + decodeURIComponent(url.search.slice(1)));
    if (db.lanza[tabla]) throw new TypeError('red caída (prueba)');
    if (db.fallos[tabla]) return new Response(JSON.stringify({ code: 'PGRST205', message: 'tabla ausente (prueba)' }), { status: db.fallos[tabla] });
    let filas = db[tabla];
    for (const [k, v] of url.searchParams) {
      if (k === 'select' || k === 'limit') continue;
      if (v.startsWith('eq.')) filas = filas.filter((f) => String(f[k]) === v.slice(3));
    }
    return new Response(JSON.stringify(filas), { status: 200 });
  };
}

/** Deja el arnés listo con la base falsa y el secreto de entrada propio (vía «servicio»). */
export function entorno(db, { config = CONFIG_BASE, env = {}, ...resto } = {}) {
  reinicia({ env: { ENVIO_CORREO_SECRET: SECRETO, ...env }, config, extra: contestaDb(db), ...resto });
}

/** Una fila de correo_plantillas activa con texto propio (el catálogo es el sellado de la migración: se pasa tal cual). */
export function filaActiva(clave, variables, { asunto, cuerpo, cuerpo_alt = null, version = 3, activa = true } = {}) {
  return { clave, activa, asunto, cuerpo, cuerpo_alt, variables, version };
}

/** El correo que habría salido, sin la fecha del pie (cambia cada día): para comparar dos caminos. */
export function normaliza(m) {
  const f = (s) => String(s).replace(/\d{1,2} (enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) \d{4}/g, '@@FECHA@@').replace(/&copy; \d{4}/g, '&copy; @@ANIO@@');
  return { to: m.to, subject: m.subject, text: f(m.text), html: f(m.html), adjuntos: (m.attachments || []).map((a) => a.filename) };
}
