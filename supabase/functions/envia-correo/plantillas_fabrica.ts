// plantillas_fabrica.ts (LAWANG) — textos de fábrica de las 8 plantillas de correo + lectura de los datos de cada una.
// Encargo encargos/20260930_erp_ajustes_pantalla.md → «Plan de S5», S5.2 (2-oct-2026).
//
// FUERA del canon (.canon_hash solo cubre index.ts y valida.ts): los TEXTOS son de cada cliente y las consultas son de su
// esquema. Lo que sí es común es la FIRMA exportada (funciones, parámetros y tipos), porque index.ts la importa:
// erp/test_canon_envia_correo.py la compara con la del maestro.
//
// Qué es de quién (el dato tiene un dueño):
//   · el TEXTO que se manda es de la tabla `correo_plantillas` si la clave está activa y su texto es válido; si no (inactiva,
//     inválida, tabla ausente) manda ESTE texto de fábrica, que es exactamente el que los llamantes componían a mano hasta hoy.
//     Mientras no se repunte S5.3, estos textos duplican los de los llamantes (firma-submit, factura-vencimiento, contracts/app.html):
//     plantillas_fabrica.test.js los compara con la salida de cada uno y falla si se separan.
//   · los DATOS (número de contrato, importe, fechas, enlace de firma) los lee `resuelve` de la base con la clave de servicio a
//     partir de los ids. Del llamante solo llega `nombre` (con quién se saluda), nunca un importe, un total ni un enlace.
//   · el catálogo de variables permitidas/obligatorias de cada clave vive SELLADO en `correo_plantillas.variables` (migración
//     20261002100000); este fichero tiene que producir todas las permitidas (lo comprueba plantillas_fabrica.test.js).
import { type Fallo, CTA_FIRMA_TEXTO, ctaPermitida } from './valida.ts';

export type Vars = Record<string, string>;
export type Ids = { contrato_id: string; factura_id: string; firma_id: string };
export type Rest = (ruta: string) => Promise<unknown>;
export type Comun = { marca: string; portal: string; dominio: string };
export type Boton = { url: string; texto: string };
export type Resuelto = { vars: Vars; variante: 'principal' | 'alt'; cta: Boton | null };
export type TextoFabrica = { asunto: string; cuerpo: string; cuerpo_alt: string | null };

const FIRMA = 'Lawang Tropical Properties';
const GUARDALO = 'Guárdalo: es el documento con el registro de firma electrónica que acredita la operación.';
const ADJUNTO = 'El documento firmado va adjunto a este correo.';

const TEXTOS: Record<string, TextoFabrica> = {
  enlace_firma_cadena: {
    asunto: 'Documento para firmar · {{numero}}',
    cuerpo: '{{saludo}}, aquí tienes el enlace para firmar el documento de ' + FIRMA + ': {{enlace}}\n\nEl enlace caduca en 30 días.\n\n' + FIRMA,
    cuerpo_alt: null,
  },
  copia_firmada_comprador: {
    asunto: 'Tu contrato firmado · {{numero}}',
    cuerpo: '{{saludo}},\n\nHemos recibido tu firma. Aquí tienes tu copia del contrato {{contrato_proyecto}}, ya firmado.\n\n' + GUARDALO +
      '\n\n' + ADJUNTO + '\n\n' + FIRMA,
    cuerpo_alt: null,
  },
  copia_firmada_portal: {
    asunto: 'Tu contrato firmado · {{numero}}',
    cuerpo: '{{saludo}},\n\nHemos recibido tu firma. Tu copia del contrato {{contrato_proyecto}}, ya firmado, está en tu portal de cliente: {{portal}}' +
      '\n\nEntra con este mismo correo: te enviaremos un enlace de acceso.\n\n' + GUARDALO + '\n\n' + FIRMA,
    cuerpo_alt: null,
  },
  copia_firmada_manual: {
    asunto: 'Tu contrato firmado · {{numero}}',
    cuerpo: '{{saludo}},\n\nTe enviamos tu copia del contrato {{numero}}, ya firmado.\n\n' + GUARDALO + '\n\n' + ADJUNTO + '\n\n\n' + FIRMA,
    cuerpo_alt: null,
  },
  aviso_anulacion: {
    asunto: 'Actualización del documento {{numero}} — ' + FIRMA,
    // principal: el firmante aún no había firmado · alt: ya había firmado (su firma deja de valer)
    cuerpo: '{{saludo}},\n\nVamos a actualizar el documento {{numero}} que te enviamos para firmar, así que el enlace que recibiste ya no está activo.' +
      '\n\nEn cuanto la nueva versión esté lista te enviaremos un enlace nuevo.\n\nNo tienes que hacer nada por ahora.\n\n' + FIRMA,
    cuerpo_alt: '{{saludo}},\n\nVamos a actualizar el documento {{numero}} que firmaste. Como el texto cambia, la firma que diste sobre la versión anterior ' +
      'deja de ser válida y el enlace que recibiste ya no está activo.\n\n{{bloque_motivo}}En cuanto la nueva versión esté lista te enviaremos un ' +
      'enlace nuevo para que puedas firmarla. Sentimos la molestia.\n\nNo tienes que hacer nada por ahora.\n\n' + FIRMA,
  },
  factura_primer_hito: {
    asunto: 'Factura {{factura}} · {{numero}}',
    cuerpo: '{{saludo}},\n\nAdjuntamos la factura {{factura}} correspondiente al primer pago del contrato {{numero}}.\n\nConcepto: {{concepto}}\nImporte: {{importe}}' +
      '\n\nLos datos para la transferencia están en la propia factura.\n\n\n' + FIRMA,
    cuerpo_alt: null,
  },
  proforma_total: {
    asunto: 'Factura proforma {{factura}} · {{numero}}',
    cuerpo: '{{saludo}},\n\nAdjuntamos la factura proforma {{factura}} con el importe total del proyecto contratado en {{numero}}.\n\nImporte total: {{importe}}' +
      '\n\nEs un documento informativo, sin validez fiscal: el cobro de cada pago se factura aparte, a medida que vence.\n\n\n' + FIRMA,
    cuerpo_alt: null,
  },
  factura_vencimiento: {
    asunto: 'Factura {{factura}} · vencimiento del {{fecha}} · {{numero}}',
    cuerpo: '{{saludo}},\n\nEl próximo pago de tu contrato {{numero}} vence el {{fecha}}. Adjuntamos la factura {{factura}} para que puedas realizarlo con tiempo.' +
      '\n\nConcepto: {{concepto}}\nImporte: {{importe}}\n\nLos datos para la transferencia están en la propia factura. Si el pago ya está en camino, ignora este aviso.' +
      '\n\n\n' + FIRMA,
    cuerpo_alt: null,
  },
};

export function textoFabrica(clave: string): TextoFabrica | null {
  return Object.prototype.hasOwnProperty.call(TEXTOS, clave) ? TEXTOS[clave] : null;
}

// Decimales por moneda: la MISMA tabla que contracts/assets/dinero.js (LW_DECIMALES) y public.moneda_decimales. plantillas_fabrica.test.js
// compara este formateo con el de dinero.js para todas las monedas: dos reglas del mismo importe son dos reglas.
const DECIMALES: Record<string, number> = { EUR: 2, USD: 2, AUD: 2, IDR: 0, JPY: 0, KRW: 0, VND: 0, CLP: 0 };
function fmtMoneda(n: unknown, moneda: string): string {
  const d = DECIMALES[moneda] ?? 2;
  return new Intl.NumberFormat('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d }).format(Number(n) || 0) + (moneda ? ' ' + moneda : '');
}

const linea = (s: unknown) => String(s ?? '').replace(/\s+/g, ' ').trim();

/** Lee de la base lo que cada plantilla necesita a partir de los ids y devuelve las variables (todas texto), la variante del
 *  cuerpo y el botón. Un 400 (Fallo) si los ids no cuadran con el destinatario o con el estado del documento. Si la lectura
 *  falla (red, permisos) `rest` lanza y la edge responde 502: sin los datos no hay correo. */
export async function resuelve(clave: string, ids: Ids, to: string, vars: Vars, rest: Rest, comun: Comun): Promise<Resuelto | Fallo> {
  const mal = (error: string): Fallo => ({ error, status: 400 });
  const uno = async (ruta: string) => {
    const f = await rest(ruta);
    return Array.isArray(f) && f.length === 1 ? f[0] as Record<string, unknown> : null;
  };
  const primero = (n: unknown) => String(n ?? '').trim().split(/\s+/)[0];
  const saludo = (n: unknown) => 'Hola' + (primero(n) ? ' ' + primero(n) : '');
  const marca = comun.marca;

  if (clave === 'enlace_firma_cadena') {
    const f = await uno('contrato_firmas?select=contrato_id,enlace_firma,firmante_nombre,firmante_email,estado&id=eq.' + ids.firma_id);
    if (!f || f.contrato_id !== ids.contrato_id) return mal('La firma no pertenece a ese contrato');
    if (String(f.firmante_email ?? '').trim().toLowerCase() !== to.toLowerCase()) return mal('El destinatario no es el firmante de ese enlace');
    if (f.estado !== 'pendiente') return mal('El enlace de firma ya no está vivo');
    const enlace = String(f.enlace_firma ?? '');
    if (!/^https:\/\/[A-Za-z0-9.-]+\/contracts\/firmar[.]html[?]t=[A-Za-z0-9._-]+$/.test(enlace) || !ctaPermitida(enlace, comun.dominio)) {
      return mal('El enlace de firma guardado no es válido');
    }
    const ct = await uno('contratos?select=numero&id=eq.' + ids.contrato_id);
    if (!ct || !ct.numero) return mal('Contrato no encontrado');
    return { vars: { saludo: saludo(f.firmante_nombre), numero: String(ct.numero), enlace, marca }, variante: 'principal',
             cta: { url: enlace, texto: CTA_FIRMA_TEXTO } };
  }

  if (clave === 'copia_firmada_comprador' || clave === 'copia_firmada_portal' || clave === 'copia_firmada_manual') {
    const ct = await uno('contratos?select=numero,proyecto_nombre,pf:datos->fields->>proyecto_nombre,pdf_firmado_path&id=eq.' + ids.contrato_id);
    if (!ct || !ct.numero) return mal('Contrato no encontrado');
    if (!ct.pdf_firmado_path) return mal('El contrato no tiene PDF firmado');
    const numero = String(ct.numero);
    const proyecto = String(ct.proyecto_nombre ?? ct.pf ?? '');
    return { vars: { saludo: saludo(vars.nombre), numero, contrato_proyecto: numero + (proyecto ? ' (' + proyecto + ')' : ''),
                     portal: comun.portal, marca }, variante: 'principal', cta: null };
  }

  if (clave === 'aviso_anulacion') {
    const ct = await uno('contratos?select=numero&id=eq.' + ids.contrato_id);
    if (!ct || !ct.numero) return mal('Contrato no encontrado');
    const filas = await rest('contrato_firmas?select=firmante_nombre,firmante_email,firmado_en,anulado_en,anulado_justificacion&limit=100&contrato_id=eq.' + ids.contrato_id);
    const mias = (Array.isArray(filas) ? filas as Record<string, unknown>[] : [])
      .filter((f) => String(f.firmante_email ?? '').trim().toLowerCase() === to.toLowerCase());
    if (!mias.some((f) => f.anulado_en)) return mal('Ese firmante no tiene una firma anulada en el contrato');
    const firmada = mias.find((f) => f.firmado_en);
    const fila = firmada ?? mias[0];
    const motivo = firmada ? String(firmada.anulado_justificacion ?? '').trim() : '';
    return { vars: { saludo: saludo(fila.firmante_nombre), numero: String(ct.numero), bloque_motivo: motivo ? 'Motivo: ' + motivo + '\n\n' : '', marca },
             variante: firmada ? 'alt' : 'principal', cta: null };
  }

  if (clave === 'factura_primer_hito' || clave === 'proforma_total' || clave === 'factura_vencimiento') {
    const f = await uno('facturas?select=numero,tipo,anulada,contrato_numero,total,moneda,lineas:datos->lineas,venc:datos->fields->>fecha_vencimiento&id=eq.' + ids.factura_id);
    if (!f) return mal('Factura no encontrada');
    if (f.anulada === true) return mal('La factura está anulada');
    if (f.tipo !== (clave === 'proforma_total' ? 'proforma' : 'factura')) return mal('La factura no es del tipo que pide esta plantilla');
    const lineas = Array.isArray(f.lineas) ? f.lineas as Record<string, unknown>[] : [];
    const concepto = linea(lineas[0]?.descripcion);
    const fecha = String(f.venc ?? '').trim();
    if (clave !== 'proforma_total' && !concepto) return mal('La factura no tiene concepto');
    if (clave === 'factura_vencimiento' && !fecha) return mal('La factura no tiene fecha de vencimiento');
    return { vars: { saludo: saludo(vars.nombre), factura: String(f.numero ?? ''), numero: String(f.contrato_numero ?? ''), concepto, fecha,
                     importe: fmtMoneda(f.total, String(f.moneda ?? 'EUR')), marca }, variante: 'principal', cta: null };
  }

  return mal('Plantilla no reconocida');
}
