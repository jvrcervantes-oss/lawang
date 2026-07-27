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
  sandalwoods_danamon_eur: { label:'PT San Dal Woods — Bank Danamon, EUR (Badung)',
    titular:'PT San Dal Woods', banco:'PT Bank Danamon Indonesia, Tbk — sucursal Badung Kerobokan', cuenta:'3692536026',
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
   los contratos. Añadir una sociedad = un bloque más aquí, nada más. */
const SOCIEDADES = {
  tepi_sungai: {
    label: 'PT Tepi Sungai (marca «Lawang Tropical Properties»)',
    razon: 'PT TEPI SUNGAI', marca: 'LAWANG TROPICAL PROPERTIES',
    domicilio: 'Jalan Gunung Tangkuban Perahu, Gg. Dewi Sri Dusun Tegal Buah RT. 000 RW. 000, Padangsambian Kelod, Denpasar Barat, Kota Denpasar, Bali 80117 Indonesia',
    npwp: '1000.0000.0619.8026', rep: 'I Made Monjong Adhi Nugruah',
    cred: { es: 'de nacionalidad Indonesia, con documento de identidad indonesio ID 5171021704720002',
            en: 'Indonesian nationality, holder of Indonesian identity document ID 5171021704720002',
            id: 'berkewarganegaraan Indonesia, dengan dokumen identitas Indonesia ID 5171021704720002' } },
  san_dal_woods: {
    label: 'PT San Dal Woods',
    razon: 'PT SAN DAL WOODS', marca: '',
    domicilio: 'Jl. Sunset Road No. 89, Pertokoan Sunset Indah I, No. 3B RT. 000 RW. 000, Kuta, Kuta, Kab. Badung, Bali',
    npwp: '1000.0000.0012.5018', rep: 'Pablo Cantero Gambín',
    cred: { es: 'de nacionalidad española, con pasaporte español nº PAL648254',
            en: 'Spanish nationality, holder of Spanish passport no. PAL648254',
            id: 'berkewarganegaraan Spanyol, dengan paspor Spanyol no. PAL648254' } },
};
