/* Cómo va de cobrado un contrato — pieza compartida de la suite. 27-ago-2026.

   POR QUÉ EXISTE
   --------------
   Esto no es una función de pintar: son las REGLAS DE DINERO que deciden si un
   contrato «solo tiene proforma», «está facturado y sin cobrar» o «tiene cobro
   sin factura que lo respalde». Nacieron dentro del `<style>`… perdón, dentro
   del `<script>` de `intranet/facturas/`, y hoy hacían falta también en la v3.

   Copiarlas allí habría sido garantizar que se separen, y estas se separan
   CARAS: dos de ellas ya nacieron mal y se corrigieron con dinero delante —
   «solo proforma» marcaba como «aquí no ha pasado nada» dos contratos con
   190.620 € cobrados, y el porcentaje recortado a 100 convertía un 277 % en un
   contrato cerrado. Una regla que ya falló una vez no se copia: se saca.

   NO SE INVENTA NADA AQUÍ. Los importes se suman con `lwSumaPorMoneda` y se
   escriben con `lwFormatoImporte` (dinero.js), que es la única forma de leer y
   escribir dinero en esta suite.

   USO
   ---
       <script src="/contracts/assets/dinero.js"></script>
       <script src="/contracts/assets/facturas_contratos.js"></script>
       const grupos = lwAgrupaPorContrato(documentosVisibles);

   Devuelve un array ordenado por actividad más reciente. Cada grupo trae sus
   documentos, sus sumas POR MONEDA y las tres banderas de estado.           */

function lwAgrupaPorContrato(docs){
  const g = new Map();
  docs.forEach(f => {
    const k = f.contrato_id ? (f.contrato_numero || f.contrato_id) : '\u0000sin';
    if(!g.has(k)) g.set(k, { clave:k, numero:f.contrato_numero || null, sinContrato:!f.contrato_id,
                             cliente:f.cliente_nombre, proyecto:f.proyecto_nombre, docs:[] });
    /* Si en la bolsa de «sin contrato» caen clientes distintos, NO se queda con
       el del primero: no hay un cliente de ese grupo. */
    const gr = g.get(k);
    if(gr.sinContrato && gr.cliente && f.cliente_nombre !== gr.cliente) gr.variosClientes = true;
    g.get(k).docs.push(f);
  });
  const suma = (l, t) => lwSumaPorMoneda(l.filter(f => f.tipo === t && !f.anulada),
                                          f => Number(f.total) || 0, f => f.moneda || 'EUR');
  return [...g.values()].map(c => {
    c.facturado = suma(c.docs, 'factura');
    c.cobrado   = suma(c.docs, 'recibi');
    c.proforma  = suma(c.docs, 'proforma');
    const monedas = new Set([...Object.keys(c.facturado), ...Object.keys(c.cobrado)]);
    /* El porcentaje SOLO si hay una moneda. Con dos, dividir mezcla divisas y
       da una cifra que no existe — el fallo que costó el arreglo de Proyectos
       esta misma mañana. Sin porcentaje se enseñan las sumas y ya. */
    c.unaMoneda = monedas.size === 1 ? [...monedas][0] : null;
    const F = c.unaMoneda ? (c.facturado[c.unaMoneda] || 0) : 0;
    const C = c.unaMoneda ? (c.cobrado[c.unaMoneda]   || 0) : 0;
    /* 🔴 NO se recorta a 100. Cobrar MÁS de lo facturado es una noticia —falta
       una factura, o hay un cobro duplicado—, y un `Math.min(100, …)` la
       convierte en un contrato perfectamente cerrado. Se enseña el número real
       y lo que se limita es solo el ANCHO de la barra, que es dibujo. */
    c.pct = F ? Math.max(0, C / F * 100) : 0;
    c.totalFacturado = Object.values(c.facturado).reduce((a, b) => a + b, 0);
    c.totalCobrado   = Object.values(c.cobrado).reduce((a, b) => a + b, 0);
    /* 🔴 «Solo proforma» EXIGE que tampoco se haya cobrado (26-ago-2026). Sin
       esa condición marcaba como «solo proforma» dos contratos con 190.620 €
       ya cobrados: proforma emitida, recibí firmado y factura nunca hecha. El
       cartel decía que allí no había pasado nada. */
    c.soloProforma      = c.totalFacturado === 0 && c.totalCobrado === 0 && Object.keys(c.proforma).length > 0;
    /* Y ese caso merece su propio nombre, porque no es un descuido de papeleo:
       es dinero entrado sin factura que lo respalde. Son dos hoy. */
    c.cobradoSinFactura = c.totalFacturado === 0 && c.totalCobrado > 0;
    c.sinRecibi         = c.totalFacturado > 0 && c.totalCobrado === 0;
    /* El más reciente manda el orden, igual que en la lista plana: el operador
       no cambia de modelo mental al cambiar de vista. */
    c.ultima = c.docs.map(f => f.fecha_emision || '').sort().slice(-1)[0] || '';
    return c;
  }).sort((a, b) => (b.ultima || '').localeCompare(a.ultima || ''));
}

/* Node lo necesita para el test; el navegador lo ignora. */
if(typeof module !== 'undefined' && module.exports)
  module.exports = { lwAgrupaPorContrato };
