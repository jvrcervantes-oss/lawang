/* Vocabulario de negocio de la suite — 14-ago-2026
   ----------------------------------------------------------------------------
   Cómo se LLAMAN las cosas y qué SIGNIFICAN, en un solo sitio.

   Fichero aparte de suite-comun.js a propósito, y no por gusto de separar:
   contracts/app.html define su propio `esc()` —con un segundo parámetro que
   suite-comun.js no tiene, así que no son intercambiables— y dos `const esc` en
   el ámbito global revientan la página entera con «Identifier has already been
   declared». Metiendo esto en un módulo sin colisiones, la herramienta más
   grande de la suite puede usar el vocabulario compartido sin tocar sus 36
   llamadas a `esc`.

   POR QUÉ EXISTE. El nombre de un tipo de contrato estaba escrito en dos sitios
   —`TIPO_ES` en operaciones/ y `TIPO_LABEL` en contracts/app.html— y no decían
   lo mismo. Encontrado el 14-ago comparándolos contra los datos de producción:

     · `reserva_parcela` salía «Bloqueo de Parcela» en Operaciones y «Parcela» en
       Contratos. Son 21 contratos con dos nombres distintos según dónde mires, y
       el bueno es el primero: el cliente pidió ese nombre el 24-jul.
     · `commercial_offer` salía «Oferta Comercial» en una y «Commercial Offer» en
       la otra.
     · `poa` salía «POA (Poder Notarial)» y «Poder Notarial».
     · Y a Operaciones le FALTABAN tres tipos, así que enseñaba la clave cruda de
       la base de datos: `hak_sewa_notario` (3 contratos), `ppjb_bonian_c2` (2) y
       `carta_reserva_hak_sewa` (1). Seis documentos reales enseñando jerga.

   Es el mismo fallo que ya se arregló una vez en app.html («faltaba: el listado
   enseñaba "poa" en crudo») y que volvió en la herramienta de al lado, porque la
   lista estaba copiada. Copiada otra vez, vuelve otra vez.

   AL AÑADIR UN TIPO DE CONTRATO hay que tocar cuatro sitios, no uno: la app
   (`CONTRACT_TIPO`), la numeración (`set_contrato_numero`), la restricción
   `contratos_tipo_check` de Postgres, y este diccionario. Los tres primeros
   rompen ruidosamente; éste no: se limita a enseñar la clave cruda. */

/* Nombre visible de cada tipo de contrato. La clave es el valor real de
   `contratos.tipo`. En español porque es el idioma de trabajo de la suite; la
   versión inglesa la resuelve idioma.js donde haga falta, no este fichero. */
const LW_TIPO_CONTRATO = {
  carta_reserva:          'Carta de Reserva',
  carta_reserva_ampliada: 'Carta de Reserva ampliada',
  carta_reserva_hak_sewa: 'Carta de Reserva (Hak Sewa)',
  reserva_parcela:        'Bloqueo de Parcela',
  construccion:           'Construcción',
  contrato_general:       'Contrato General',
  commercial_offer:       'Oferta Comercial',
  acuerdo_comercial:      'Acuerdo Comercial',
  protocolo_operativo:    'Protocolo Operativo',
  ppjb_bonian:            'PPJB Bonian Beach',
  ppjb_bonian_c2:         'PPJB Bonian Beach · Parcela C2',
  hak_sewa_notario:       'Hak Sewa - Notario',
  poa:                    'Poder Notarial',
  cc00014_timon:          'Construcción · CC00014 Timon',
};
/* Cae a la clave si el tipo es nuevo y nadie lo añadió aquí. Enseñar
   `ppjb_bonian_c2` es feo, pero mentir con el nombre de otro documento es peor:
   el fallback nunca adivina. */
const lwTipoContrato = t => LW_TIPO_CONTRATO[t] || t || '—';

/* ---------------------------------------------------------------------------
   Qué contratos NO suman precio
   ---------------------------------------------------------------------------
   Una Carta de Reserva es un documento PRELIMINAR: reserva la operación mientras
   se hace el due diligence (15 días o un mes) y luego o se sigue o se devuelve el
   dinero. El precio que declara NO es de fiar —unos agentes ponen la villa
   entera, otros solo la parcela— y además es el mismo importe que luego reparten
   el Bloqueo de Parcela (suelo) y la Construcción (obra). Sumarla cuenta la misma
   villa dos veces.

   Vivía SOLO en compradores/ (12-ago: una Carta + Construcción de 76.500 € daba
   153.000 € por la misma villa). El 14-ago la Carta pasó a colgar de su Bloqueo y
   Operaciones —que suma el grupo y no tenía la regla— empezó a dar el doble:
   328.000 € por una villa de 164.000.

   Lo ÚNICO que se hereda de una Carta es cuánto pagó el cliente: el COBRADO sí
   suma todo el grupo, para descontárselo al pasar a Bloqueo sin duplicarlo. */
const LW_TIPOS_PRELIMINARES = ['carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa'];
const lwEsPreliminar = t => LW_TIPOS_PRELIMINARES.includes(t);
