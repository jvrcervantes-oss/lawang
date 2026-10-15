// nota_correo.ts (LAWANG) — la regla de la nota libre del admin en los correos de la ficha de parcela («Reclamar pago», «Invitar al portal»).
// ESPEJO de public._nota_correo_limpia (migración 20261015101500_invitacion_portal_parcela.sql): la nota llega ya validada de la base; la
// edge la vuelve a mirar por si una fila vieja o una función nueva se la saltan (Seguridad, revisión previa #357, 15-oct-2026).
// Fichero aparte y no en plantillas_fabrica.ts: la firma exportada de aquel se compara con la del maestro (erp/test_canon_envia_correo.py),
// y el maestro no tiene estos correos.
import { tieneControl } from './valida.ts';

/** Cuenta o teléfono escondido: 6 dígitos o más aunque vayan separados por espacio, punto, guion o barra («BCA 123 456 7890»,
 *  «0812-3456-7890»: Seguridad 15-oct, la regla de «6 seguidos» se saltaba con separadores). Antes se apartan las fechas
 *  (15/10/2026, 15-10-26) y los importes con los miles agrupados (25.000.000, 1.500,50), para que Reclamar pago siga admitiendo
 *  «quedan 25.000.000 IDR». Residual aceptado: un número escrito como importe agrupado pasa. Las mismas tres expresiones que la base. */
export function numeroLargo(nota: string): boolean {
  const d = nota
    .replace(/(^|[^0-9])[0-9]{1,2}[\/.-][0-9]{1,2}[\/.-]((19|20)[0-9]{2}|[0-9]{2})(?![0-9])/g, '$1#')
    .replace(/(^|[^0-9])[0-9]{1,3}([.,][0-9]{3})+([.,][0-9]{1,2})?(?![0-9])/g, '$1#');
  return /[0-9]([ .\/-]?[0-9]){5,}/.test(d);
}

/** Texto plano de hasta 300 caracteres, sin @, http, www, nada con forma de dominio (Gmail lo convierte en enlace), ningún número
 *  largo (numeroLargo) ni caracteres de control. Se le pasa la nota ya normalizada (espacios colapsados, recortada). */
export function notaCorreoValida(nota: string): boolean {
  return [...nota].length <= 300 && !tieneControl(nota) && !/(http|www\.|@)/i.test(nota) &&
    !/[a-z0-9-]\.[a-z]{2,}/i.test(nota) && !numeroLargo(nota);
}
