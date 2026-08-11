/* ============================================================================
   Identidad de Lawang (y el cargador de las cuentas de cobro) — FUENTE ÚNICA
   ----------------------------------------------------------------------------
   Lo usan `contracts/app.html` (contratos) y `facturas/index.html` (facturas).
   Vivía inline en app.html hasta el 27-jul-2026; se saca aquí porque un número
   de cuenta duplicado en dos herramientas se corrige en una y se queda viejo en
   la otra — y ahí el fallo es dinero enviado al sitio equivocado.

   Define dos globales: CUENTAS_BANCARIAS y SOCIEDADES. Sin módulos a propósito:
   las dos apps son HTML plano con <script> clásico.

   Los textos que llevan palabras van como {es,en,id} porque los contratos se
   imprimen en tres idiomas; las facturas usan solo `es`/`en`.
   ========================================================================== */

/* ---------- cuentas de cobro — YA NO VIVEN AQUÍ (6-ago-2026) ----------
   Los 15 números de cuenta estaban escritos en este fichero, y este fichero es
   PÚBLICO por dos caminos a la vez: se sirve con 200 sin login (lo cargan las
   nueve herramientas de la suite y el portal del comprador) y está en el repo
   `jvrcervantes-oss/lawang`, que es público, legible en crudo desde el 27-jul.
   Unas coordenadas bancarias abiertas son la materia prima de un fraude de
   transferencia, y a diferencia de una contraseña **un número de cuenta no se
   rota**: la única salida es que dejen de publicarse.

   Ahora viven en la tabla `public.cuentas_bancarias` con RLS: SELECT solo para
   `authenticated`, ni lectura ni escritura para `anon` (verificado con un GET
   anónimo al REST: 401, no un `[]` ambiguo). El repo se queda público a
   propósito — de él depende el auto-deploy de Hostinger; lo que sale del repo
   son las cuentas, no el hosting.

   SOCIEDADES se queda: es la identidad que ya va impresa en todo contrato y
   factura que el comprador tiene en la mano, así que ocultarla no protege nada.

   Cómo se usa: `await cargarCuentasBancarias(sb)` una vez al arrancar, antes de
   pintar el select de cuentas o de imprimir un documento. Quien lea
   CUENTAS_BANCARIAS después lo hace igual que siempre. */
const CUENTAS_BANCARIAS = {};
let CUENTAS_PROMESA = null;

/* Rellena el objeto EN SU SITIO (Object.assign, nunca reasignar): `firma-submit`
   y `facturas/documento.test.js` publican esta misma referencia en su `caja`
   evaluando los cuatro ficheros compartidos de una vez, así que cambiar el
   objeto por otro los dejaría leyendo uno vacío para siempre.
   Si la consulta falla, LANZA y deja la promesa a null para poder reintentar: un
   fallo silencioso aquí imprime un contrato sin datos de pago, que es
   exactamente el error que este fichero existe para evitar. */
function cargarCuentasBancarias(sb){
  if(CUENTAS_PROMESA) return CUENTAS_PROMESA;
  CUENTAS_PROMESA = (async () => {
    const { data, error } = await sb.from('cuentas_bancarias')
      .select('clave,label,titular,banco,cuenta,codigo,direccion,extra')
      .eq('activa', true).order('orden');
    if(error){ CUENTAS_PROMESA = null; throw error; }
    (data || []).forEach(r => {
      CUENTAS_BANCARIAS[r.clave] = { label:r.label, titular:r.titular, banco:r.banco,
        cuenta:r.cuenta, codigo:r.codigo, direccion:r.direccion, extra:r.extra };
    });
    return CUENTAS_BANCARIAS;
  })();
  return CUENTAS_PROMESA;
}

/* ---------- sociedades emisoras ----------
   `razon`/`marca`/`domicilio`/`npwp`/`rep` alimentan tanto los marcadores
   {{prom_*}} de las plantillas de contrato como la cabecera del emisor en las
   facturas. `cred` (nacionalidad + documento del representante) solo la usan
   los contratos.

   Identidad del documento por sociedad (30-jul-2026) — cada sociedad emite con
   su marca, no con la de Lawang, y una factura de PT SAN DAL WOODS con el logo
   de Lawang dice que la emite otra empresa:
     `logo`      cabecera del documento
     `logoAlto`  alto del logo (por defecto 15mm)
     `logo2`     segundo logo debajo del primero (el lockup de palabra), opcional
     `logo2Ancho` ancho de ese segundo logo
     `folio`     color del papel
     `tinta`     {primary, deep} = todo lo coloreado del documento
   Lo usan hoy las facturas (los contratos llevan su logo fijo en cada
   plantilla). Añadir una sociedad = un bloque más aquí, nada más. */
const SOCIEDADES = {
  /* ⚠️ La CLAVE es `tepi_sungai` y NO se toca: va guardada dentro de cada
     contrato (`sociedad_firmante`) y de cada factura, y las plantillas la miran
     en `<!--if:sociedad_firmante=tepi_sungai-->`. Renombrarla dejaría a los
     contratos ya emitidos apuntando a una sociedad que no existe y sin logo.
     Lo que se corrige el 31-jul-2026 es el nombre que se IMPRIME: la sociedad
     está inscrita como «PT TEPI SUN GAI», separado, y lo emitíamos junto. Es lo
     mismo que reclamaba el memorándum del abogado del comprador sobre CR00003.
     Ojo al leerlo: «tepi sungai» junto es riverbank en indonesio y es el nombre
     de la colección en la web pública — ese sí va junto y no hay que tocarlo. */
  tepi_sungai: {
    label: 'PT Tepi Sun Gai (marca «Lawang Tropical Properties»)',
    razon: 'PT TEPI SUN GAI', marca: 'LAWANG TROPICAL PROPERTIES',
    logo: '/contracts/assets/brand/lawang-logo-v3-dark.png',
    /* Este lockup es una tira de 7,2:1: al lado del emisor no cabe grande sin
       dejarle una columna de 52mm en la que el domicilio se parte en nueve
       líneas. Decisión del owner (30-jul, 17:10h): aquí el logo va GRANDE y el
       emisor DEBAJO, que es lo que aprovecha el ancho de una tira. San Dal
       Woods, cuyo lockup es 2,1:1, se queda con el emisor al lado. */
    logoAlto: '14mm',            // 14mm × 7,2:1 = 100,7mm de ancho
    emisorDebajo: true,
    // verde claro: el equivalente en la gama de marca al crema de SAN DAL WOODS.
    // Historia del ajuste (30-jul, owner): #F3F7F0 → #DAE6D0 (-10% de
    // luminosidad) se pasó de fuerte, así que se queda a MEDIO camino, en -5%.
    // El crema de San Dal Woods sí se queda con el -10%: el verde carga más a
    // la vista que el crema al mismo nivel de luminosidad.
    folio: '#E6EFE0',
    domicilio: 'Jalan Gunung Tangkuban Perahu, Gg. Dewi Sri Dusun Tegal Buah RT. 000 RW. 000, Padangsambian Kelod, Denpasar Barat, Kota Denpasar, Bali 80117 Indonesia',
    npwp: '1000.0000.0619.8026',
    /* ⚠️ EL REPRESENTANTE DE ESTA SOCIEDAD ES I WAYAN EKA ARYAWAN (desde
       11-ago-2026, petición del owner — sustituye a I Made Monjong Adhi
       Nugruah). Identificación (NIK) tomada del mismo catálogo que ya usa el
       apoderado de la serie Hak Sewa (`apoderadosHakSewa` en tokens.json).
       El 4-ago-2026 cambié este campo a Pablo Cantero Gambín leyendo mal al
       owner: dijo «en este caso mete a Pablo Cantero» refiriéndose SOLO al
       PPJB de Bonian C2, y lo apliqué aquí, que es la ficha de la que beben
       las NUEVE plantillas. Revertido el mismo día.
       Si algún documento concreto lo firma otra persona, va escrito EN ESE
       documento —como está hoy en `templates/ppjb_bonian_c2.html`—, no aquí. */
    rep: 'I Wayan Eka Aryawan',
    // NIB y NPWP personal del firmante: los pide el PPJB de Bonian Beach en sus
    // antecedentes. Van aquí y no en la plantilla porque son identidad de la
    // sociedad, y la identidad tiene una sola fuente (este fichero). Opcionales:
    // la plantilla los envuelve en <!--opt:--> y la frase se cierra sola si una
    // sociedad no los tiene, en vez de imprimir el marcador.
    // ⚠️ `rep_npwp` es el del representante que figura ARRIBA en `rep`. Si se
    // cambia uno hay que cambiar el otro: son la misma persona.
    // `rep_npwp` va VACÍO: el NPWP 53.045.376.0-905.000 que trae el PPJB de
    // Bonian es el de Pablo Cantero, y aquí el representante es I Wayan Eka
    // Aryawan. Poner uno con el nombre del otro es peor que no poner ninguno
    // — la frase se cierra sola gracias al <!--opt:-->.
    nib: '2410250046282', rep_npwp: '',
    cred: { es: 'de nacionalidad Indonesia, con documento de identidad indonesio ID 5102010606870001',
            en: 'Indonesian nationality, holder of Indonesian identity document ID 5102010606870001',
            id: 'berkewarganegaraan Indonesia, dengan dokumen identitas Indonesia ID 5102010606870001' } },
  san_dal_woods: {
    label: 'PT SAN DAL WOODS',
    razon: 'PT SAN DAL WOODS', marca: '',
    /* Lockup único: el owner juntó isotipo y palabra en una sola imagen
       (`swnewlogo.png`, 30-jul 15:40h). Se sirve una copia con el FONDO QUITADO:
       el original viene con el crema viejo (#F8F7F2) opaco, que sobre el folio
       actual (#E7E3D2) se veía como un rectángulo más claro pegado encima; el
       multiply tampoco lo salva, porque ese crema no es blanco y tiñe.
       La copia va además RECORTADA a la tinta (el original traía 20px de aire
       por lado): así el alto que se pide aquí es el alto que se ve, y el logo se
       puede alinear con el título del documento sin adivinar el margen interno.
       479×227 px (ratio 2,11): a 24mm de alto son 50,6mm de ancho, lo que cabe
       al lado de los datos del emisor. Subirlo es una línea, pero cada mm de
       alto se lo come el presupuesto de UNA página (facturas/index.html). */
    logo: '/contracts/assets/brand/sandalwoods-lockup.png',
    logoAlto: '24mm',
    folio: '#E7E3D2',              // crema, +10% de fuerza sobre el #f8f7f2 inicial (-10% de luminosidad)
    // Tinta del documento cuando emite esta sociedad. `primary` es el marrón
    // exacto del SWlogo (muestreado del PNG: #662906) y `deep` el Burnt Earth
    // de la guía de marca, más oscuro, para los titulares. Sin `tinta` el
    // documento se queda con el verde/lagoon de Lawang (brand.css).
    tinta: { primary:'#662906', deep:'#42210B' },
    domicilio: 'Jl. Sunset Road No. 89, Pertokoan Sunset Indah I, No. 3B RT. 000 RW. 000, Kuta, Kuta, Kab. Badung, Bali',
    npwp: '1000.0000.0012.5018', rep: 'Pablo Cantero Gambín',
    cred: { es: 'de nacionalidad española, con pasaporte español nº PAL648254',
            en: 'Spanish nationality, holder of Spanish passport no. PAL648254',
            id: 'berkewarganegaraan Spanyol, dengan paspor Spanyol no. PAL648254' } },
};

/* ---------- etiqueta humana de `contratos.tipo` ----------
   Copiado a propósito, no movido: ya vivía inline en operaciones/index.html
   (TIPO_ES) desde el 5-ago y ese sitio sigue funcionando — sacarlo de ahí para
   esta tarea habría sido tocar un fichero que nadie pidió cambiar. Esta copia
   la usa `facturas/index.html` para el prefijo "[Parcela]"/"[Construcción]"
   cuando combina conceptos de dos contratos vinculados (7-ago-2026). Si diverge
   de la de operaciones, unificarlas aquí sería el momento — no antes. */
const TIPO_ES = { reserva_parcela:'Parcela', construccion:'Construcción', contrato_general:'Contrato General',
  commercial_offer:'Oferta Comercial', carta_reserva:'Carta de Reserva',
  carta_reserva_ampliada:'Carta de Reserva ampliada', acuerdo_comercial:'Acuerdo Comercial',
  protocolo_operativo:'Protocolo Operativo', ppjb_bonian:'PPJB Bonian Beach',
  poa:'POA (Poder Notarial)' };
