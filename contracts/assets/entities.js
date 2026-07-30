/* ============================================================================
   Identidad y cuentas de cobro de Lawang — FUENTE ÚNICA
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

/* ---------- cuentas de cobro ----------
   En contratos: el agente elige la cuenta en el select 'cuenta_bancaria' y
   datosBancariosHTML la resuelve a la tabla completa. Sin selección no imprime
   nada — nunca un valor por defecto adivinado en algo tan sensible como una
   cuenta de pago. */
const CUENTAS_BANCARIAS = {
  sandalwoods_dbs: { label:'Sandal Woods Limited — DBS Bank (Hong Kong)',
    titular:'SANDAL WOODS LIMITED', banco:'DBS Bank (Hong Kong) Limited', cuenta:'478798116354',
    codigo:'DHBKHKHH', direccion:"11th Floor, The Center, 99 Queen's Road Central, Central, Hong Kong",
    extra:{es:'Código de banco: 016',en:'Bank code: 016',id:'Kode bank: 016'} },
  sandalwoods_dbs_sg: { label:'Sandal Woods Limited — DBS Bank Ltd (Singapur)',
    titular:'Sandal Woods Limited', banco:'DBS Bank Ltd', cuenta:'885571532066',
    codigo:'DBSSSGSG', direccion:'12 Marina Boulevard, DBS Asia Central, Marina Bay Financial Centre Tower 3, Singapore 018982',
    extra:{es:'Código de banco: 7171',en:'Bank code: 7171',id:'Kode bank: 7171'} },
  /* `titular` se IMPRIME en los datos bancarios del documento: va con la grafía
     registrada, tres palabras y en mayúsculas (confirmada por el owner el
     30-jul-2026). Un titular que no coincide con el de la cuenta es una
     transferencia devuelta. */
  sandalwoods_danamon_eur: { label:'PT SAN DAL WOODS — Bank Danamon, EUR (Badung)',
    titular:'PT SAN DAL WOODS', banco:'PT Bank Danamon Indonesia, Tbk — sucursal Badung Kerobokan', cuenta:'3692536026',
    codigo:'BDINIDJAXXX', direccion:'Jalan Raya Kerobokan No. 24, Banjar Taman Kerobokan, Badung, Bali, Indonesia 80361',
    extra:{es:'Código de banco: 011 · Código de sucursal: 0380',en:'Bank code: 011 · Branch code: 0380',id:'Kode bank: 011 · Kode cabang: 0380'} },
  contractor_lawang: { label:'Contratista — Lawang (I Putu Hady Diyatmika · BCA)',
    titular:'I Putu Hady Diyatmika, ST', banco:'Bank Central Asia (BCA)', cuenta:'1420040632',
    codigo:'CENAIDJA', direccion:'Menara BCA, Grand Indonesia, Jl. MH Thamrin No. 1, Jakarta 10310, Indonesia', extra:'' },
  land_balian_usd: { label:'Terreno — Balian Hills, USD (Lead Bank)',
    titular:'Santiago del Cerro Villena', banco:'Lead Bank', cuenta:'212789850974',
    codigo:'101019644 (ABA Routing)', direccion:'1801 Main St., Kansas City, MO 64108, USA', extra:{es:'Tipo de cuenta: Checking',en:'Account type: Checking',id:'Jenis rekening: Checking'} },
  land_balian_eur: { label:'Terreno — Balian Hills, EUR (OCBC)',
    titular:'PT Balian Hills Resort', banco:'OCBC', cuenta:'160800028963',
    codigo:'NISPIDJA', direccion:'Bank OCBC Branch Denpasar Teuku Umar, Jl. Teuku Umar No.2-4, Denpasar Barat, Denpasar, Bali 80114, Indonesia', extra:'' },
  notario_sandy_sumba: { label:'Notario — Sandy Tandean, Sumba (BNI)',
    titular:'BPK SANDY TANDEAN', banco:'Bank Negara Indonesia (BNI)', cuenta:'0044860851',
    codigo:'BNINIDJA', direccion:'Jl. Sumatera No.33, Todekisar, Kec. Kota Lama, 85111, Kota Kupang, Nusa Tenggara Timur, Indonesia', extra:'' },
  contractor_sumba_eur: { label:'Constructor — Sumba, EUR (Achmad Zaeni · Bank Mandiri)',
    titular:'ACHMAD ZAENI', banco:'Bank Mandiri — sucursal Waingapu, Sumba Timur', cuenta:'1810004920345',
    codigo:'BMRIIDJAXXX', direccion:'Jl. Ahmad Yani No. 75, Kamalaputi, Kota Waingapu, 87116, Sumba Timur, Nusa Tenggara Timur, Indonesia',
    extra:{es:'Teléfono del beneficiario: +62 818 558 667 · Teléfono del banco: +62 387 61111',en:'Beneficiary phone: +62 818 558 667 · Bank phone: +62 387 61111',id:'Telepon penerima: +62 818 558 667 · Telepon bank: +62 387 61111'} },
  contractor_tepisungai: { label:'Contratista — Tepi Sungai (OCBC)',
    titular:'PT Tepi Sungai', banco:'OCBC', cuenta:'167800024140',
    codigo:'NISPIDJA', direccion:'Bank OCBC Branch Denpasar Teuku Umar, Jl. Teuku Umar No.2-4, Denpasar, Bali, Indonesia', extra:'' },
  notario_ayu_wulandari: { label:'Notario — Anak Agung Ayu Wulandari (BCA)',
    titular:'An. Anak Agung Ayu Wulandari', banco:'Bank Central Asia (BCA)', cuenta:'1420857361',
    codigo:'CENAIDJA', direccion:'Menara BCA, Grand Indonesia, Jl. MH Thamrin No.1, Jakarta 10310, Indonesia', extra:'' },
  land_sumbahills_plots: { label:'Terreno — Sumba Hills Plots (BNI)',
    titular:'Bpk Sandy Tandean', banco:'Bank Negara Indonesia (BNI)', cuenta:'0044860851',
    codigo:'BNINIDJAXXX', direccion:'Jl. Sumatera 33, Todekisar, Kota Kupang, Nusa Tenggara Timur 85118, Indonesia', extra:'' },
  suite_sumbahills: { label:'Suite — Sumba Hills (Bank Mandiri)',
    titular:'Achmad Zaeni', banco:'Bank Mandiri', cuenta:'181 000 120 5641',
    codigo:'BMRIIDJA', direccion:'Jl. Ahmad Yani No. 75, Kamalaputi, Kota Waingapu 87116, Indonesia', extra:'Tel: +62 818 558 667' },
  notario_ayu_satya: { label:'Notario — Ida Ayu Satya Dewi (BNI)',
    titular:'Ida Ayu Satya Dewi', banco:'Bank Negara Indonesia (BNI)', cuenta:'1427191719',
    codigo:'BNINIDJADPS', direccion:'BNI Building, Floor 7, Jl Jenderal Sudirman 1, Jakarta 10220, Indonesia', extra:'' },
  notario_nyoman_wiryasa: { label:'Notario — I Nyoman Wiryasa Birawantara (BRI)',
    titular:'I Nyoman Wiryasa Birawantara', banco:'Bank Rakyat Indonesia (BRI)', cuenta:'478501009326538',
    codigo:'BRINIDJAXXX', direccion:'Jl Kediri Gang IV, Rt.002/001, Jembrana, Negara, Bali 82211, Indonesia', extra:'' },
  notario_putu_kartika: { label:'Notario — A.A. Putu Kartika Adi (Mandiri)',
    titular:'A.A. Putu Kartika Adi', banco:'Bank Mandiri', cuenta:'1750038383831',
    codigo:'BMRIIDJAXXX', direccion:'Jalan Jenderal Sudirman Kav 54-55, Jakarta 12190, Indonesia', extra:'' },
};

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
  tepi_sungai: {
    label: 'PT Tepi Sungai (marca «Lawang Tropical Properties»)',
    razon: 'PT TEPI SUNGAI', marca: 'LAWANG TROPICAL PROPERTIES',
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
    npwp: '1000.0000.0619.8026', rep: 'I Made Monjong Adhi Nugruah',
    cred: { es: 'de nacionalidad Indonesia, con documento de identidad indonesio ID 5171021704720002',
            en: 'Indonesian nationality, holder of Indonesian identity document ID 5171021704720002',
            id: 'berkewarganegaraan Indonesia, dengan dokumen identitas Indonesia ID 5171021704720002' } },
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
