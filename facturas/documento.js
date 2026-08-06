/* ============================================================================
   El DOCUMENTO de la factura — FUENTE ÚNICA de su maquetación
   ----------------------------------------------------------------------------
   Devuelve el HTML del papel (cabecera, cliente, conceptos, totales, banco,
   notas, pie). Lo usan DOS sitios y por eso vive aquí:

     · `facturas/index.html`  — la vista previa viva y el PDF que imprime el
       navegador cuando alguien emite a mano.
     · `contracts/edge/firma-submit` — la factura del primer hito que sale sola
       al cerrarse la firma de un contrato. La Edge Function se BAJA este mismo
       fichero y lo ejecuta, así que no hay una segunda versión del documento
       que se quede vieja: si aquí cambia una fila, cambia en los dos.

   Los estilos van en `documento.css`, también compartido. Aquí solo el marcado.

   Sin módulos ES a propósito (mismo criterio que entities.js y totales.js):
   index.html es HTML plano con <script> clásico, y la Edge Function evalúa el
   texto de este fichero. El `module.exports` del final es para el test en node.

   Depende de globales que ponen los otros ficheros compartidos:
     SOCIEDADES, CUENTAS_BANCARIAS (entities.js) · calcTotales, fmtMoneda,
     parseImporte (totales.js).
   ========================================================================== */

/* Rótulos del tipo de documento. Cada uno lleva su propia serie en base de
   datos (INV / PRO / REC): una proforma no es documento fiscal y no puede
   consumir números de la serie de facturas. */
var TIPOS_DOC = {
  factura:  { es:'Factura',          en:'Invoice',          serie:'INV' },
  proforma: { es:'Factura proforma', en:'Proforma invoice', serie:'PRO' },
  recibi:   { es:'Recibí',           en:'Receipt',          serie:'REC' },
};

function escDoc(s){
  return String(s == null ? '' : s).replace(/[&<>"]/g,
    c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c]));
}

/* Datos bancarios en DOS columnas: en una sola, seis filas de etiqueta/valor
   comían 44mm de folio y empujaban la factura a la segunda página con solo dos
   conceptos. Los cuatro datos cortos van en dos columnas y los dos largos
   (dirección del banco y nota) a ancho completo, que en media columna se
   partían en tres líneas y no ahorraban nada.

   `cuenta === 'otros'` = cuenta escrita a mano en el formulario, para cobrar por
   una que no está dada de alta en entities.js sin frenar la emisión. Se arma un
   objeto con la misma forma para que el resto no tenga que distinguir. */
function bancoDocHTML(d){
  var c = d.cuenta === 'otros'
    ? { titular:d.banco_titular, banco:d.banco_nombre, cuenta:d.banco_cuenta,
        codigo:d.banco_codigo, direccion:d.banco_direccion, extra:d.banco_extra }
    : (typeof CUENTAS_BANCARIAS !== 'undefined' ? CUENTAS_BANCARIAS[d.cuenta] : null);
  var txt = v => (v && typeof v === 'object') ? (v.es || '') : (v || '');
  // Sin ningún dato relleno no se imprime el bloque: una cabecera "Datos
  // bancarios" con seis guiones es peor que no ponerla.
  if(!c || !Object.keys(c).some(k => txt(c[k]))) return '';
  var dato = (l, v, ancho) => txt(v)
    ? '<div class="' + (ancho ? 'ancho' : '') + '"><span>' + l + '</span>' + escDoc(txt(v)) + '</div>' : '';
  return '<h3>Datos bancarios · Bank details</h3>' +
    '<div class="banco">' +
      dato('Titular · Holder', c.titular) +
      dato('Banco · Bank', c.banco) +
      dato('Cuenta · Account', c.cuenta) +
      dato('Swift / Routing', c.codigo) +
      dato('Dirección · Address', c.direccion, true) +
      dato('Nota · Note', c.extra, true) +
    '</div>';
}

/* Variables de tinta del documento. Todo lo coloreado (filete de cabecera,
   titulares, rótulos, cabecera de tabla y línea del total) sale de aquí, así que
   cambiarlas repinta el documento entero. Cadena vacía = se borra el override y
   vuelve el verde/lagoon de brand.css.
   `--folio` es el color del PAPEL y va en `.sheet`, que está FUERA de `.doc`:
   ponerlo en `.doc` pintaría solo bajo el contenido y dejaría blancos los
   márgenes. */
function documentoVars(soc){
  soc = soc || {};
  return {
    hoja: { '--folio': soc.folio || '' },
    doc: {
      '--brand-primary': (soc.tinta && soc.tinta.primary) || '',
      '--brand-deep':    (soc.tinta && soc.tinta.deep)    || '',
      '--logo-alto':     soc.logoAlto   || '',
      '--logo2-ancho':   soc.logo2Ancho || '',
    },
  };
}

/* `d` = los campos del formulario (collect()). `opts.numero` = el número ya
   emitido; sin él la línea no se pinta, porque un documento sin número es uno
   que todavía no se ha emitido. `opts.base` antepone el host a las rutas de los
   logos: en pantalla sobran, pero el renderizador de PDF carga el HTML desde
   otro sitio y una ruta relativa no resolvería. */
function documentoHTML(d, opts){
  opts = opts || {};
  var base = opts.base || '';
  var numero = opts.numero || '';
  var soc = (typeof SOCIEDADES !== 'undefined' && SOCIEDADES[d.sociedad]) ||
            (typeof SOCIEDADES !== 'undefined' && SOCIEDADES.tepi_sungai) || {};
  var t = calcTotales(d.lineas, d.moneda, { pct: d.imp_pct });
  var tipo = TIPOS_DOC[d.tipo] || TIPOS_DOC.factura;
  var linea = v => v ? escDoc(v) : '<span class="vacio">—</span>';
  var fecha = f => f
    ? new Date(f + 'T00:00:00').toLocaleDateString('es-ES', { day:'2-digit', month:'long', year:'numeric' })
    : '';
  var url = u => (u && base && u.charAt(0) === '/') ? base.replace(/\/$/, '') + u : u;

  var filas = d.lineas.map(l => (l.descripcion || l.importe)
      ? '<tr><td>' + escDoc(l.descripcion) + '</td><td class="imp">' +
        fmtMoneda(parseImporte(l.importe), d.moneda) + '</td></tr>' : ''
    ).join('') || '<tr><td class="vacio">Sin conceptos</td><td class="imp vacio">—</td></tr>';

  /* Sin `logo` en la sociedad NO se pinta ninguno, y a propósito: el fallback al
     de Lawang que había aquí convirtió un entities.js cacheado en una factura de
     PT SAN DAL WOODS con la marca de otra empresa, sin que se notara. Un
     documento sin logo salta a la vista; uno con el logo equivocado, no. */
  return '' +
  '<div class="head">' +
    '<div class="emisor-bloque' + (soc.emisorDebajo ? ' apilado' : '') + '">' +
      '<div class="marcas">' +
        (soc.logo  ? '<img src="' + escDoc(url(soc.logo)) + '" alt="">' : '') +
        (soc.logo2 ? '<img class="logo2" src="' + escDoc(url(soc.logo2)) + '" alt="">' : '') +
      '</div>' +
      '<div class="emisor">' +
        '<b>' + escDoc(soc.razon) + '</b>' +
        (soc.marca ? '<span class="marca">' + escDoc(soc.marca) + '</span>' : '') +
        '<div>' + escDoc(soc.domicilio) + '</div>' +
        '<div>NPWP ' + escDoc(soc.npwp) + '</div>' +
      '</div>' +
    '</div>' +
    '<div class="titulo">' +
      '<h2>' + escDoc(tipo.es) + '</h2>' +
      '<div class="titulo-en">' + escDoc(tipo.en) + '</div>' +
      (numero ? '<div class="num">' + escDoc(numero) + '</div>' : '') +
      '<div class="meta">' +
        (d.fecha_emision ? 'Fecha · Date: ' + escDoc(fecha(d.fecha_emision)) + '<br>' : '') +
        (d.fecha_vencimiento ? 'Vencimiento · Due: ' + escDoc(fecha(d.fecha_vencimiento)) + '<br>' : '') +
        (d.contrato_numero ? 'Contrato · Contract: ' + escDoc(d.contrato_numero) : '') +
      '</div>' +
    '</div>' +
  '</div>' +

  '<h3>Facturar a · Bill to</h3>' +
  '<div class="cliente">' +
    '<b>' + linea(d.cliente_nombre) + '</b><br>' +
    (d.cliente_documento ? escDoc(d.cliente_documento) + '<br>' : '') +
    (d.cliente_domicilio ? escDoc(d.cliente_domicilio).replace(/\n/g, '<br>') + '<br>' : '') +
    (d.cliente_email ? escDoc(d.cliente_email) : '') +
    (d.proyecto_nombre ? '<div style="margin-top:2mm">Proyecto · Project: <b>' + escDoc(d.proyecto_nombre) + '</b></div>' : '') +
  '</div>' +

  '<h3>Conceptos · Items</h3>' +
  '<table><thead><tr><th>Descripción · Description</th><th class="imp">Importe · Amount</th></tr></thead>' +
    '<tbody>' + filas + '</tbody></table>' +

  '<table class="totales"><tbody>' +
    '<tr><td>Subtotal</td><td class="imp">' + fmtMoneda(t.subtotal, d.moneda) + '</td></tr>' +
    (t.pct ? '<tr><td>' + escDoc(d.imp_etiqueta || 'Impuesto · Tax') + ' (' + escDoc(String(t.pct)) + '%)</td>' +
             '<td class="imp">' + fmtMoneda(t.impuesto, d.moneda) + '</td></tr>' : '') +
    '<tr class="total"><td>Total</td><td class="imp">' + fmtMoneda(t.total, d.moneda) + '</td></tr>' +
  '</tbody></table>' +

  bancoDocHTML(d) +
  (d.notas ? '<h3>Notas · Notes</h3><div class="notas">' + escDoc(d.notas) + '</div>' : '') +

  '<div class="pie">' + escDoc(soc.razon) + (soc.marca ? ' · ' + escDoc(soc.marca) : '') +
    ' · NPWP ' + escDoc(soc.npwp) + ' · ' + escDoc(soc.domicilio) + '</div>';
}

/* Documento COMPLETO y autónomo, para mandarlo al renderizador de PDF (Chromium
   real en Railway) desde fuera del navegador. `base` tiene que ser absoluto: el
   servicio carga el HTML desde otro sitio y con rutas relativas ni la hoja de
   estilos ni los logos resolverían. */
function documentoPagina(d, opts){
  opts = opts || {};
  var base = (opts.base || '').replace(/\/$/, '');
  var v = documentoVars((typeof SOCIEDADES !== 'undefined' && SOCIEDADES[d.sociedad]) || {});
  var estilo = k => Object.keys(v[k]).filter(p => v[k][p]).map(p => p + ':' + v[k][p]).join(';');
  return '<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">' +
    '<base href="' + base + '/">' +
    '<link rel="preconnect" href="https://fonts.googleapis.com">' +
    '<link href="https://fonts.googleapis.com/css2?family=Jost:wght@300;400;500;600&family=Cormorant+Garamond:wght@400;500;600&display=swap" rel="stylesheet">' +
    '<link rel="stylesheet" href="' + base + '/contracts/assets/brand.css">' +
    '<link rel="stylesheet" href="' + base + '/facturas/documento.css">' +
    /* 🔴 6-ago-2026 — ESTE BLOQUE ES LA HOJA COMPLETA, no un remate.
       El documento que se manda por correo salía «con un formateo que no tiene
       nada que ver» con la vista previa de la herramienta (reportado por el
       owner), y la causa era que aquí faltaban DOS declaraciones que en
       /facturas/ las pone el <style> de la propia página:
         · `font-family` — `brand.css` define el TOKEN `--font-body` pero no lo
           aplica a `body`, y `documento.css` solo pone tipografía en el titular.
           Sin esto el documento entero salía en el serif por defecto del
           navegador (Times), no en Jost.
         · `background` en `.sheet` — `documentoVars` calcula bien el folio de
           cada sociedad y lo deja en `--folio`, pero NADIE lo consumía aquí: el
           papel salía blanco. O sea que la identidad por sociedad (30-jul) se
           perdía en TODA factura enviada por correo y en las automáticas de la
           firma, que son justo las que ve el comprador.
       Los valores llevan fallback porque esta página se renderiza fuera del
       navegador y `brand.css` podría no llegar; un documento en Jost sobre papel
       blanco es aceptable, uno en Times no.
       Lo que NO se copia de la página, y es correcto: `zoom` y `box-shadow`, que
       son de pantalla (el zoom además no se aplica dentro de @media print). */
    '<style>@page{size:A4;margin:0}html,body{margin:0}' +
    'body{font-family:var(--font-body,\'Jost\',sans-serif);color:var(--ink,#2E3437)}' +
    '.sheet{width:210mm;min-height:297mm;padding:15mm 16mm;box-sizing:border-box;' +
    'background:var(--folio,#fff)}</style>' +
    '</head><body>' +
    '<div class="sheet" style="' + estilo('hoja') + '">' +
      '<div class="doc" style="' + estilo('doc') + '">' + documentoHTML(d, opts) + '</div>' +
    '</div></body></html>';
}

if(typeof module !== 'undefined')
  module.exports = { TIPOS_DOC, escDoc, bancoDocHTML, documentoVars, documentoHTML, documentoPagina };
