// nota_correo.ts (LAWANG) — la regla de la nota libre del admin en los correos de la ficha de parcela («Reclamar pago», «Invitar al portal»).
// ESPEJO de public._nota_correo_limpia (migración 20261015101500_invitacion_portal_parcela.sql): la nota llega ya validada de la base; la
// edge la vuelve a mirar por si una fila vieja o una función nueva se la saltan (Seguridad, revisión previa #357, 15-oct-2026).
// Fichero aparte y no en plantillas_fabrica.ts: la firma exportada de aquel se compara con la del maestro (erp/test_canon_envia_correo.py),
// y el maestro no tiene estos correos.
import { tieneControl } from './valida.ts';

/** Texto plano de hasta 300 caracteres, sin @, http, www, nada con forma de dominio (Gmail lo convierte en enlace), 6 dígitos
 *  seguidos (cuentas, teléfonos) ni caracteres de control. Se le pasa la nota ya normalizada (espacios colapsados, recortada). */
export function notaCorreoValida(nota: string): boolean {
  return [...nota].length <= 300 && !tieneControl(nota) && !/(http|www\.|@)/i.test(nota) &&
    !/[a-z0-9-]\.[a-z]{2,}/i.test(nota) && !/[0-9]{6,}/.test(nota);
}
