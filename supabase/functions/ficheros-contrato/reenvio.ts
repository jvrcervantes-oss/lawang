// reenvio.ts — cuándo se puede reenviar un enlace de firma CADUCADO sin pasar por el generador (17-oct-2026, mejora 5b
// de la intranet: «Reenviar todas» en el cajón «Firmas caducadas» de Hoy toca). Lo usa ficheros-contrato → reenvia_caducada,
// para la vista previa (`ver`) y para el envío con la MISMA regla: lo que la pantalla enseña es lo que el servidor hará.
// Sin imports a propósito: así lo prueba node (reenvio.test.js) sin Deno ni red.
//
// Revisión previa del 17-oct (Backend + Seguridad, plan en el relevo de lawang-mejoras-ux):
//   · el firmante (nombre, email, rol, orden) sale de la fila caducada, nunca del navegador;
//   · solo si esa fila es la ÚNICA `pendiente` del contrato y ya caducó (una lista vieja en otra pestaña no puede anular un
//     enlace vivo) y no hay ninguna firma `procesando` (a medias de estampar, firma-submit);
//   · el contrato, ni bloqueado ni liberado (contrato_firma_estado no mira `liberado_en`: hasta hoy solo lo filtraba la pantalla);
//   · el documento es el FIJO `pendientes/<id>.html` y su sha256 tiene que ser el `snapshot_hash` de la fila caducada: se
//     reenvía exactamente lo que se envió. Sin huella (enlaces de antes del 26-sep) o si no casa, al generador.

export type FilaFirma = {
  id: string;
  estado: string;
  expira_en: string | null;
  firmante_nombre: string | null;
  firmante_email: string | null;
  firmante_rol: string | null;
  orden: number | null;
  snapshot_hash: string | null;
  creado_en?: string | null;
};
export type ContratoReenvio = { bloqueado: boolean | null; liberado_en: string | null } | null;
export type Decision = { ok: true; fila: FilaFirma } | { ok: false; motivo: string };

// Tope por persona: reenvíos hechos con esta acción en la ventana. La cola manda los enlaces de firma (prioridad 1) sin
// pausa entre correos y Hostinger ya bloqueó admin@ por una ráfaga (app.html, «Asunto con el número del documento»).
// 20 en 15 min: decisión por defecto del 17-oct (Backend propuso 20 por pulsación); se cambia aquí.
export const TOPE_REENVIOS = 20;
export const VENTANA_TOPE_MIN = 15;

/** La regla. `ahora` en ms. No mira el documento: eso es `documentoCasa`, con el hash que calcula la edge. */
export function decideReenvio(c: ContratoReenvio, filas: FilaFirma[], ahora: number): Decision {
  if (!c) return { ok: false, motivo: 'contrato_no_encontrado' };
  if (c.bloqueado === true) return { ok: false, motivo: 'bloqueado' };
  if (c.liberado_en) return { ok: false, motivo: 'liberado' };
  if (filas.some((f) => f.estado === 'procesando')) return { ok: false, motivo: 'firma_a_medias' };
  const pend = filas.filter((f) => f.estado === 'pendiente');
  if (!pend.length) return { ok: false, motivo: 'sin_enlace_pendiente' };
  if (pend.length > 1) return { ok: false, motivo: 'varios_pendientes' };
  const f = pend[0];
  const exp = f.expira_en ? Date.parse(f.expira_en) : NaN;
  if (!Number.isFinite(exp) || exp > ahora) return { ok: false, motivo: 'enlace_vivo' };
  if (filas.some((x) => x.estado === 'firmado' && x.firmante_rol === f.firmante_rol)) return { ok: false, motivo: 'ya_firmo' };
  if (!/^[0-9a-f]{64}$/.test(f.snapshot_hash ?? '')) return { ok: false, motivo: 'sin_huella' };
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test((f.firmante_email ?? '').trim())) return { ok: false, motivo: 'sin_email' };
  if (!/^adquiriente_[0-9]+$/.test(f.firmante_rol ?? '') || !((f.orden ?? 0) >= 1)) return { ok: false, motivo: 'firmante_raro' };
  return { ok: true, fila: f };
}

/** El documento fijo es el mismo que se mandó a firmar con el enlace caducado. */
export function documentoCasa(hashFijo: string, fila: FilaFirma): boolean {
  return /^[0-9a-f]{64}$/.test(hashFijo) && hashFijo === fila.snapshot_hash;
}

/** `hechos` = enlaces que esta persona ha sustituido en la ventana: filas de contrato_firmas con `anulado_por` = su email y
 *  `anulado_motivo` = 'nuevo_enlace' (lo apunta contrato_envia_firma). Cuenta también los del generador: nadie regenera 20
 *  contratos en un cuarto de hora a mano, y así el freno vive en la base y no en la memoria de la edge. */
export function superaTope(hechos: number): boolean {
  return hechos >= TOPE_REENVIOS;
}
