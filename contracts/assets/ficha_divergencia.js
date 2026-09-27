/* ¿Este documento sigue diciendo lo que dice la ficha de su cliente?
   ────────────────────────────────────────────────────────────────────────────
   Capa compartida (19-ago-2026, encargo del owner: «he actualizado al cliente
   pero la factura no se ha actualizado, ¿cómo lo solucionamos para toda la
   suite?»).

   EL PROBLEMA que resuelve: la cadena ficha → contrato → factura viaja por
   COPIA. Corregir la ficha no arregla lo que ya salió, y hasta hoy la única
   forma de enterarse era abrir el documento y esperar a que saltara un aviso
   que además solo existía en Contratos.

   LA REGLA, decidida por el owner:
     · Documento VIVO      → sigue a la ficha: se avisa y se pueden traer los datos.
     · Documento CONGELADO → no se toca nunca. Corregirlo es reemitirlo.
   Congelado = contrato firmado, o factura enviada o anulada. No es un campo
   nuevo: es lo que cada documento ya dice de sí mismo.

   LA COMPARACIÓN NO ESTÁ AQUÍ: vive en la vista `documentos_desactualizados`
   de Postgres, y por eso las dos herramientas no pueden discrepar. Este fichero
   solo la consulta y la pinta. Detalle y los dos falsos positivos que hubo que
   quitar —multi-comprador y campo que el documento no imprime— en
   contracts/sql/documentos_al_dia_con_su_ficha.js. */

/* Devuelve un Map(id del documento → array de diferencias) para el tipo pedido.
   Solo trae los que TIENEN diferencias: la lista completa no le sirve a nadie. */
async function lwDivergencias(sb, tipo){
  const fuera = new Map();
  if(!sb) return fuera;
  const { data, error } = await sb.from('documentos_desactualizados')
    .select('id,numero,congelado,ficha,diferencias').eq('tipo', tipo);
  if(error || !data) return fuera;   // un aviso que falla no puede tumbar un listado
  data.forEach(d => {
    if(Array.isArray(d.diferencias) && d.diferencias.length) fuera.set(d.id, d);
  });
  return fuera;
}

/* El texto del aviso, uno para toda la suite. `congelado` cambia el consejo, no
   el diagnóstico: en los dos casos el documento dice algo distinto de la ficha,
   pero en uno se arregla y en el otro se reemite. */
/* Los valores son texto de la base (nombre, pasaporte, email del cliente) y esto se
   pinta como HTML en `lwConfirmar`: se escapan aquí, una vez, para las tres pantallas
   que lo usan (27-sep-2026 — hasta hoy iban crudos). */
function lwEscDivergencia(v){
  return String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[c]);
}
function lwTextoDivergencia(d){
  const e = lwEscDivergencia;
  const filas = (d.diferencias || []).map(x =>
    '<li><b>' + e(x.campo) + '</b>: aquí «' + e(x.documento) + '», en la ficha «' + e(x.ficha) + '»</li>').join('');
  return '<p>Este documento dice algo distinto de la ficha de <b>' + e(d.ficha || 'su cliente') + '</b>:</p>'
    + '<ul style="margin:0 0 10px;padding-left:18px">' + filas + '</ul>'
    + (d.congelado
        ? '<p>Está <b>cerrado</b> (firmado, enviado o anulado), así que no se toca: si el dato importa, '
        + 'hay que <b>reemitirlo</b>.</p>'
        : '<p>Todavía se puede corregir: al traer los datos de la ficha, el documento queda al día. '
        + 'Revisa y guarda.</p>');
}

if(typeof module !== 'undefined') module.exports = { lwDivergencias, lwTextoDivergencia };
