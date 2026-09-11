/* ═══════════════════════════════════════════════════════════════════════════
   Investor deck de Palm Field — idioma (EN/ES/ID) y divisa (EUR/USD/AUD/IDR)
   11-sep-2026
   ═══════════════════════════════════════════════════════════════════════════

   POR QUÉ ASÍ. No se inventa un sistema nuevo (Regla 0):
   · La elección de idioma comparte clave con el resto de la web pública,
     `lawang_lang` — la misma que usan `assets/idioma-web.js` y la home. Quien
     entra al deck desde la web en español lo ve en español, sin repetir la
     elección. NO se toca `lawang_idioma_ui` (intranet) ni `lw_portal_lang`
     (portal del comprador): son otros sistemas.
   · La traducción casa por TEXTO COMPLETO en inglés, igual que
     `assets/i18n-landing.js`, y no por claves `data-i18n`. Motivo: así no hay
     que tocar 170 etiquetas del HTML, y funciona igual sobre lo que pinta el
     JS (catálogo, parcelas, galería) siempre que se aplique después.
   · Símbolos y tipos de cambio salen de `assets/lawang-card.js` (`SYMS` /
     `DEFAULT_RATES`), que es donde ya vivían.

   ───────────────────────────────────────────────────────────────────────────
   ⚠️ GLOSARIO QUE NO SE TRADUCE (misma revisión de Legal que idioma-web.js)
   ───────────────────────────────────────────────────────────────────────────
   `Hak Sewa`, `Hak Milik`, `freehold`, `leasehold`, `PT PMA`, `PPAT`, `PBG`,
   `SLF`, `RDTR`, `SIMBG`, `LSD/LP2B` se dejan en el término de origen.
   NO es pereza: `freehold → hak milik` es la traducción literal correcta y
   jurídicamente letal — Hak Milik es solo para ciudadanos indonesios y el
   art. 26(2) UUPA declara NULO DE PLENO DERECHO cualquier acto que lo
   transfiera a un extranjero.

   ⚠️ PENDIENTE: el texto legal en ES/ID de este fichero lo escribió el
   estudio, NO Legal. Antes de promocionarlo a definitivo tiene que pasar
   revisión de Legal (LAW — ver contexto/pendientes.md). El inglés es el que
   está auditado (consulta legal 9-sep-2026).

   ⚠️ TIPOS DE CAMBIO: fijos, con fecha. El contrato SIEMPRE va en EUR; la
   conversión es orientativa. Mismo criterio que la landing australiana
   («the contract figure is the euro one»).
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var IDIOMAS = ['en', 'es', 'id'];
  var CLAVE_LANG = 'lawang_lang';          // compartida con la web pública
  var CLAVE_CUR = 'lw_deck_cur';           // propia del deck

  // ── Divisa ────────────────────────────────────────────────────────────────
  var SYMS = { EUR: '€', USD: '$', AUD: 'A$', IDR: 'Rp ' };
  var RATES = { EUR: 1, USD: 1.08, AUD: 1.65, IDR: 17500 };
  var RATES_FECHA = '11 Sep 2026';
  var MONEDAS = ['EUR', 'USD', 'AUD', 'IDR'];

  function valida(v, lista) { return lista.indexOf(v) !== -1 ? v : null; }

  function leeUrl(re) {
    try { var m = re.exec(location.search); return m ? m[1] : null; } catch (e) { return null; }
  }

  var LANG = valida((leeUrl(/[?&]lang=([a-zA-Z-]{2,5})/) || '').toLowerCase().slice(0, 2), IDIOMAS);
  if (!LANG) { try { LANG = valida(localStorage.getItem(CLAVE_LANG), IDIOMAS); } catch (e) {} }
  LANG = LANG || 'en';

  var CUR = valida((leeUrl(/[?&]cur=([a-zA-Z]{3})/) || '').toUpperCase(), MONEDAS);
  if (!CUR) { try { CUR = valida(localStorage.getItem(CLAVE_CUR), MONEDAS); } catch (e) {} }
  CUR = CUR || 'EUR';

  document.documentElement.setAttribute('lang', LANG);
  document.documentElement.setAttribute('data-lang', LANG);

  /* Redondeo por divisa: en rupias, céntimos no significan nada y un
     "Rp 840.000.000,37" parece un error de software. */
  function fmtEUR(eur, cur) {
    var v = (Number(eur) || 0) * (RATES[cur] || 1);
    var dec = 0;
    if (cur === 'IDR') v = Math.round(v / 1000) * 1000;
    else v = Math.round(v);
    return (SYMS[cur] || '€') + v.toLocaleString('en-GB', { maximumFractionDigits: dec });
  }
  window.lwMoney = function (eur) { return fmtEUR(eur, CUR); };
  window.lwCur = function () { return CUR; };
  window.lwLang = function () { return LANG; };
  window.lwRatesFecha = RATES_FECHA;

  /* ── Diccionario ──────────────────────────────────────────────────────────
     Clave = el texto inglés EXACTO tal y como sale en pantalla. */
  var D = {
    /* — navegación y cabecera — */
    'Project & Photos': { es: 'Proyecto y fotos', id: 'Proyek & Foto' },
    'Villa Models': { es: 'Modelos de villa', id: 'Model Villa' },
    'Masterplan & Plots': { es: 'Masterplan y parcelas', id: 'Masterplan & Kavling' },
    'Financial Forecast': { es: 'Previsión financiera', id: 'Proyeksi Keuangan' },
    'Legal Security': { es: 'Seguridad jurídica', id: 'Keamanan Hukum' },
    'FAQ': { es: 'Preguntas', id: 'FAQ' },
    /* El CTA de cabecera dejo de pedir el dossier por formulario (11-sep): ahora
       o descarga el documento que el proyecto tenga publicado, o no sale. */
    'Download dossier': { es: 'Descargar dosier', id: 'Unduh dosir' },
    'Questions? WhatsApp': { es: '¿Dudas? WhatsApp', id: 'Ada pertanyaan? WhatsApp' },
    'Ask about Palm Field on WhatsApp': { es: 'Preguntar por Palm Field por WhatsApp', id: 'Tanya tentang Palm Field lewat WhatsApp' },
    'Previous photos': { es: 'Fotos anteriores', id: 'Foto sebelumnya' },
    'More photos': { es: 'Más fotos', id: 'Foto lainnya' },
    'Dossier': { es: 'Dossier', id: 'Dosir' },

    /* — portada — */
    'Investor Deck · Due Diligence': { es: 'Dossier de inversión · Due diligence', id: 'Dosir Investor · Uji Tuntas' },
    'Balian Hills · Bali': { es: 'Balian Hills · Bali', id: 'Balian Hills · Bali' },
    'Palm Field, by PT SAN DAL WOODS': { es: 'Palm Field, de PT SAN DAL WOODS', id: 'Palm Field, oleh PT SAN DAL WOODS' },
    'A land-plot development in the': { es: 'Una promoción de parcelas en el', id: 'Pengembangan kavling tanah di' },
    'Balian river valley.': { es: 'valle del río Balian.', id: 'lembah sungai Balian.' },
    'Held under': { es: 'En régimen de', id: 'Dipegang dalam skema' },
    'Hak Sewa': { es: 'Hak Sewa', id: 'Hak Sewa' },
    'with a notarial escrow account — not a security or investment product. Real documentation, live plot inventory and a Year-1 forecast, for your own due diligence.':
      { es: 'con cuenta escrow notarial — no es un valor ni un producto de inversión. Documentación real, inventario de parcelas en vivo y una previsión de Año 1, para tu propia due diligence.',
        id: 'dengan rekening escrow notaris — bukan efek maupun produk investasi. Dokumentasi nyata, ketersediaan kavling secara langsung, dan proyeksi Tahun ke-1, untuk uji tuntas Anda sendiri.' },
    'Palm Field · Balian Hills': { es: 'Palm Field · Balian Hills', id: 'Palm Field · Balian Hills' },
    'Hak Sewa · Notarial Escrow': { es: 'Hak Sewa · Escrow notarial', id: 'Hak Sewa · Escrow Notaris' },
    'Delivered villas on a neighbouring phase, Balian river valley, southwest Bali.':
      { es: 'Villas ya entregadas en una fase contigua, valle del río Balian, suroeste de Bali.',
        id: 'Villa yang telah diserahterimakan di fase sebelah, lembah sungai Balian, Bali barat daya.' },

    /* — KPIs — */
    'Land Managed': { es: 'Suelo gestionado', id: 'Lahan Dikelola' },
    'm² under segregable title management': { es: 'm² bajo gestión de título segregable', id: 'm² dalam pengelolaan sertifikat yang dapat dipecah' },
    'Track Record': { es: 'Trayectoria', id: 'Rekam Jejak' },
    '6+ Years': { es: '6+ años', id: '6+ Tahun' },
    'Continuous operation in Indonesia': { es: 'De operación continua en Indonesia', id: 'Beroperasi terus-menerus di Indonesia' },
    'Investors': { es: 'Inversores', id: 'Investor' },
    'International owners across the portfolio': { es: 'Propietarios internacionales en toda la cartera', id: 'Pemilik internasional di seluruh portofolio' },
    'Permits': { es: 'Licencias', id: 'Perizinan' },
    'PBG & SLF occupancy certification in order': { es: 'Certificación PBG y SLF de ocupación en regla', id: 'Sertifikasi PBG & SLF laik fungsi lengkap' },

    /* — catálogo — */
    /* Sin numero: la seccion la llena la intranet y el numero cambia sola
       (hoy son 4, no 3 — el titular llevaba tiempo mintiendo). */
    'Villa Typologies': { es: 'Tipologías de villa', id: 'Tipologi Villa' },
    'Upon request': { es: 'Consultar', id: 'Atas permintaan' },
    'Renders in progress': { es: 'Renders en camino', id: 'Render sedang dibuat' },
    'We could not load the villa models right now. Please contact':
      { es: 'Ahora mismo no hemos podido cargar los modelos de villa. Escríbenos a',
        id: 'Saat ini kami tidak dapat memuat model villa. Silakan hubungi' },

    /* — panel de due diligence del hero (11-sep-2026) — */
    'Documentation & FAQ': { es: 'Documentación y preguntas', id: 'Dokumentasi & FAQ' },
    'Everything you need to start your due diligence, on this screen.':
      { es: 'Todo lo necesario para empezar tu due diligence, en esta pantalla.',
        id: 'Semua yang Anda perlukan untuk memulai uji tuntas, dalam satu layar.' },
    'The full detail, further down:': { es: 'El detalle completo, más abajo:', id: 'Detail lengkapnya, di bawah:' },
    'Prices below are': { es: 'Los precios de abajo son', id: 'Harga di bawah ini adalah' },
    'construction only': { es: 'solo de construcción', id: 'hanya konstruksi' },
    '— land price depends on the plot chosen in the masterplan.': { es: '— el precio del suelo depende de la parcela elegida en el masterplan.', id: '— harga tanah tergantung kavling yang dipilih di masterplan.' },
    'Built': { es: 'Construido', id: 'Terbangun' },
    'Terrace & pool': { es: 'Terraza y piscina', id: 'Teras & kolam' },
    'Bedrooms': { es: 'Dormitorios', id: 'Kamar tidur' },
    'Bathrooms': { es: 'Baños', id: 'Kamar mandi' },
    'Construction from': { es: 'Construcción desde', id: 'Konstruksi mulai' },
    '+ land price, per plot chosen below': { es: '+ precio del suelo, según la parcela elegida abajo', id: '+ harga tanah, sesuai kavling yang dipilih di bawah' },
    'View model & floor plan': { es: 'Ver modelo y plano', id: 'Lihat model & denah' },
    'Most requested': { es: 'El más pedido', id: 'Paling diminati' },

    /* — masterplan — */
    'Masterplan & Plot Availability': { es: 'Masterplan y disponibilidad', id: 'Masterplan & Ketersediaan Kavling' },
    "Individually cadastred plots. Live inventory read directly from Palm Field's records — sizes, prices and status are informational and confirmed at Plot Lock.":
      { es: 'Parcelas catastradas una a una. El inventario se lee en vivo de los registros de Palm Field — superficies, precios y estado son orientativos y se confirman en el Plot Lock.',
        id: 'Kavling tersertifikasi satu per satu. Ketersediaan dibaca langsung dari catatan Palm Field — luas, harga, dan status bersifat informatif dan dikonfirmasi saat Plot Lock.' },
    'Available': { es: 'Disponible', id: 'Tersedia' },
    'Reserved': { es: 'Reservada', id: 'Dipesan' },
    'Sold / Blocked': { es: 'Vendida / bloqueada', id: 'Terjual / Diblokir' },
    'Sold': { es: 'Vendida', id: 'Terjual' },
    'Blocked': { es: 'Bloqueada', id: 'Diblokir' },
    'Not available': { es: 'No disponible', id: 'Tidak tersedia' },
    'Masterplan': { es: 'Masterplan', id: 'Masterplan' },
    'Tap an available plot to reserve it. Status is live; surface areas are confirmed by survey at Plot Lock.':
      { es: 'Toca una parcela disponible para reservarla. El estado es en vivo; las superficies se confirman por levantamiento topográfico en el Plot Lock.',
        id: 'Ketuk kavling yang tersedia untuk memesannya. Status bersifat langsung; luas dikonfirmasi lewat survei saat Plot Lock.' },
    'Live plot inventory': { es: 'Inventario en vivo', id: 'Ketersediaan Langsung' },
    'Reservation Protocol': { es: 'Protocolo de reserva', id: 'Protokol Pemesanan' },
    '1. Reservation deposit': { es: '1. Depósito de reserva', id: '1. Deposit pemesanan' },
    '2. 10-day validity': { es: '2. Validez de 10 días', id: '2. Berlaku 10 hari' },
    'Due-diligence window; refundable per the Letter of Reservation.': { es: 'Ventana de due diligence; reembolsable según la Carta de Reserva.', id: 'Jendela uji tuntas; dapat dikembalikan sesuai Surat Pemesanan.' },
    '3. Notarial signature': { es: '3. Firma notarial', id: '3. Penandatanganan notaris' },
    'Hak Sewa deed and Power of Attorney before a PPAT notary.': { es: 'Escritura de Hak Sewa y poder notarial ante un notario PPAT.', id: 'Akta Hak Sewa dan Surat Kuasa di hadapan notaris PPAT.' },
    'Reserve': { es: 'Reservar', id: 'Pesan' },
    'Contact us': { es: 'Escríbenos', id: 'Hubungi kami' },

    /* — previsión financiera — */
    'Average': { es: 'Medio', id: 'Rata-rata' },
    'Optimal': { es: 'Óptimo', id: 'Optimal' },
    'ADR': { es: 'Precio medio/noche', id: 'Tarif rata-rata' },
    'Occupancy': { es: 'Ocupación', id: 'Okupansi' },
    'Gross villa income': { es: 'Ingreso bruto de la villa', id: 'Pendapatan kotor villa' },
    'Management fee (20%)': { es: 'Gestión (20%)', id: 'Biaya pengelolaan (20%)' },
    'Maintenance (5%)': { es: 'Mantenimiento (5%)', id: 'Pemeliharaan (5%)' },
    'Rental tax (10%)': { es: 'Impuesto de alquiler (10%)', id: 'Pajak sewa (10%)' },
    'Net income': { es: 'Ingreso neto', id: 'Pendapatan bersih' },
    'ROI': { es: 'ROI', id: 'ROI' },
    'Investment (construction):': { es: 'Inversión (construcción):', id: 'Investasi (konstruksi):' },

    /* — seguridad jurídica — */
    'Hak Sewa With Notarial Escrow vs. Informal Leasehold': { es: 'Hak Sewa con escrow notarial frente al leasehold informal', id: 'Hak Sewa dengan Escrow Notaris vs. Leasehold Informal' },
    "Much of Bali's foreign-facing market runs on private, unregistered lease agreements with no escrow and no notarial oversight. Palm Field is structured as":
      { es: 'Buena parte del mercado de Bali dirigido a extranjeros funciona con contratos de arrendamiento privados, sin registrar, sin escrow y sin control notarial. Palm Field se estructura como',
        id: 'Sebagian besar pasar Bali yang menyasar orang asing berjalan dengan perjanjian sewa privat, tidak terdaftar, tanpa escrow dan tanpa pengawasan notaris. Palm Field disusun sebagai' },
    '(long-term Indonesian lease tenure) directly between the landowner and the buyer, with funds held in a':
      { es: '(arrendamiento de largo plazo del derecho indonesio) directamente entre el propietario del suelo y el comprador, con los fondos depositados en una',
        id: '(hak sewa jangka panjang menurut hukum Indonesia) langsung antara pemilik tanah dan pembeli, dengan dana ditahan di' },
    'notarial escrow account': { es: 'cuenta escrow notarial', id: 'rekening escrow notaris' },
    'until the agreed conditions are met — not Hak Milik, which Indonesian law reserves for Indonesian citizens.':
      { es: 'hasta que se cumplen las condiciones pactadas — no Hak Milik, que la ley indonesia reserva a los ciudadanos indonesios.',
        id: 'sampai syarat yang disepakati terpenuhi — bukan Hak Milik, yang oleh hukum Indonesia hanya untuk warga negara Indonesia.' },
    'Legal & registry aspect': { es: 'Aspecto jurídico y registral', id: 'Aspek hukum & pendaftaran' },
    'Palm Field: Hak Sewa + escrow': { es: 'Palm Field: Hak Sewa + escrow', id: 'Palm Field: Hak Sewa + escrow' },
    'Common practice: informal lease': { es: 'Práctica habitual: arrendamiento informal', id: 'Praktik umum: sewa informal' },
    'Payment security': { es: 'Seguridad del pago', id: 'Keamanan pembayaran' },
    'Notarial escrow (PPAT)': { es: 'Escrow notarial (PPAT)', id: 'Escrow notaris (PPAT)' },
    'Reservation and stage payments held in an escrow account managed by the notary, released against agreed conditions.':
      { es: 'La reserva y los pagos por hitos quedan en una cuenta escrow gestionada por el notario, y se liberan contra las condiciones pactadas.',
        id: 'Pemesanan dan pembayaran bertahap ditahan di rekening escrow yang dikelola notaris, dilepas sesuai syarat yang disepakati.' },
    'Funds paid directly to a private landowner or intermediary, with no third-party custody.':
      { es: 'El dinero se paga directamente a un propietario particular o a un intermediario, sin custodia de un tercero.',
        id: 'Dana dibayarkan langsung ke pemilik tanah atau perantara, tanpa kustodian pihak ketiga.' },
    'Term & registration': { es: 'Plazo y registro', id: 'Jangka waktu & pendaftaran' },
    'Hak Sewa, Indonesian law': { es: 'Hak Sewa, derecho indonesio', id: 'Hak Sewa, hukum Indonesia' },
    'Registered lease term (legal maximum 30 years per grant, renewable with a new term), transferable and heritable.':
      { es: 'Plazo de arrendamiento inscrito (máximo legal de 30 años por otorgamiento, renovable con un plazo nuevo), transmisible y heredable.',
        id: 'Jangka sewa terdaftar (maksimum menurut hukum 30 tahun per pemberian, dapat diperpanjang dengan jangka baru), dapat dialihkan dan diwariskan.' },
    'Unregistered private agreement with no guaranteed renewal and limited transferability.':
      { es: 'Acuerdo privado sin inscribir, sin renovación garantizada y con transmisibilidad limitada.',
        id: 'Perjanjian privat tanpa pendaftaran, tanpa jaminan perpanjangan dan dengan pengalihan terbatas.' },
    'Building permits (PBG / SLF)': { es: 'Licencias de obra (PBG / SLF)', id: 'Izin bangunan (PBG / SLF)' },
    'Government portal (SIMBG)': { es: 'Portal del gobierno (SIMBG)', id: 'Portal pemerintah (SIMBG)' },
    'Approved ahead of construction, with occupancy certification (SLF) enabling legal short-term rental.':
      { es: 'Aprobadas antes de construir, con certificado de ocupación (SLF) que habilita el alquiler de corta estancia legal.',
        id: 'Disetujui sebelum konstruksi, dengan sertifikat laik fungsi (SLF) yang memungkinkan sewa jangka pendek secara legal.' },
    'Frequently started without permits or with permits pending, exposed to government closure.':
      { es: 'Se empieza a menudo sin licencia o con la licencia pendiente, expuesto al cierre administrativo.',
        id: 'Sering dimulai tanpa izin atau dengan izin yang masih diproses, berisiko ditutup pemerintah.' },
    'Land zoning (RDTR)': { es: 'Calificación del suelo (RDTR)', id: 'Zonasi lahan (RDTR)' },
    'Official urban classification': { es: 'Clasificación urbanística oficial', id: 'Klasifikasi tata ruang resmi' },
    'Zoned for tourism / residential use, legally enabled for short-stay rental income.':
      { es: 'Calificado para uso turístico / residencial, habilitado legalmente para ingresos por alquiler de corta estancia.',
        id: 'Berzonasi pariwisata / hunian, secara hukum boleh menghasilkan pendapatan sewa jangka pendek.' },
    'Often sited on green or agricultural-protection land (LSD/LP2B), not legally buildable.':
      { es: 'A menudo sobre suelo verde o de protección agrícola (LSD/LP2B), no edificable legalmente.',
        id: 'Sering berada di lahan hijau atau lahan pertanian dilindungi (LSD/LP2B), yang secara hukum tidak boleh dibangun.' },
    'Official Notarial Signature (PPAT)': { es: 'Firma notarial oficial (PPAT)', id: 'Penandatanganan Notaris Resmi (PPAT)' },
    "Each transfer is formalised before a state-appointed Land Deed Official (PPAT), with a Power of Attorney for the buyer's representative in Indonesia.":
      { es: 'Cada transmisión se formaliza ante un funcionario público de escrituras de suelo (PPAT), con poder notarial para el representante del comprador en Indonesia.',
        id: 'Setiap pengalihan diformalkan di hadapan Pejabat Pembuat Akta Tanah (PPAT), dengan Surat Kuasa bagi perwakilan pembeli di Indonesia.' },
    'Regulated Escrow Account': { es: 'Cuenta escrow regulada', id: 'Rekening Escrow Teregulasi' },
    'Funds are held in an escrow account managed by the notary and released only against verified construction milestones.':
      { es: 'Los fondos quedan en una cuenta escrow gestionada por el notario y solo se liberan contra hitos de obra verificados.',
        id: 'Dana ditahan di rekening escrow yang dikelola notaris dan hanya dilepas setelah tahapan konstruksi terverifikasi.' },
    'Direct, Documented Transaction': { es: 'Operación directa y documentada', id: 'Transaksi Langsung dan Terdokumentasi' },
    'The lease is agreed directly between the landowner and the buyer — no nominee arrangement, no undisclosed intermediary holding title on your behalf.':
      { es: 'El arrendamiento se pacta directamente entre el propietario del suelo y el comprador — sin figura de nominee, sin intermediario oculto que ostente el título en tu nombre.',
        id: 'Sewa disepakati langsung antara pemilik tanah dan pembeli — tanpa skema nominee, tanpa perantara tersembunyi yang memegang hak atas nama Anda.' },

    /* — FAQ — */
    'Frequently Asked Questions': { es: 'Preguntas frecuentes', id: 'Pertanyaan yang Sering Diajukan' },
    'What tenure do I acquire?': { es: '¿Qué derecho adquiero?', id: 'Hak apa yang saya peroleh?' },
    '(long-term leasehold under Indonesian law) — the standard route for foreign investors on this project, not Hak Milik, which is reserved for Indonesian citizens. Exact terms are confirmed in the Plot Lock agreement that follows a reservation.':
      { es: '(leasehold de largo plazo del derecho indonesio) — la vía estándar para inversores extranjeros en este proyecto, no Hak Milik, reservado a ciudadanos indonesios. Las condiciones exactas se confirman en el acuerdo de Plot Lock posterior a la reserva.',
        id: '(leasehold jangka panjang menurut hukum Indonesia) — jalur standar bagi investor asing di proyek ini, bukan Hak Milik yang hanya untuk warga negara Indonesia. Ketentuan pastinya dikonfirmasi dalam perjanjian Plot Lock setelah pemesanan.' },
    'What does the reservation fee cover?': { es: '¿Qué cubre la cuota de reserva?', id: 'Apa yang dicakup biaya pemesanan?' },
    "It reserves the selected plot, held in the notary's escrow account, for the validity period stated in the Letter of Reservation, while you complete due diligence. It is":
      { es: 'Reserva la parcela elegida, en la cuenta escrow del notario, durante el plazo de validez que indica la Carta de Reserva, mientras completas tu due diligence. No es',
        id: 'Biaya ini memesan kavling yang dipilih, ditahan di rekening escrow notaris, selama masa berlaku yang tercantum dalam Surat Pemesanan, sementara Anda menyelesaikan uji tuntas. Ini' },
    'not': { es: 'no es', id: 'bukan' },
    'the deed of sale and does not transfer any right over the land. If you withdraw, or the reservation lapses, the fee is refunded per the terms in the document you receive.':
      { es: 'la escritura de compraventa y no transmite ningún derecho sobre el suelo. Si desistes, o la reserva caduca, la cuota se devuelve según las condiciones del documento que recibes.',
        id: 'akta jual beli dan tidak mengalihkan hak apa pun atas tanah. Jika Anda mundur, atau pemesanan kedaluwarsa, biaya dikembalikan sesuai ketentuan dalam dokumen yang Anda terima.' },
    'Are the prices shown final?': { es: '¿Los precios mostrados son definitivos?', id: 'Apakah harga yang ditampilkan final?' },
    'No — land and construction prices shown are reference prices per the current catalogue, confirmed in the Plot Lock / construction agreement. They are not a binding offer.':
      { es: 'No — los precios de suelo y construcción son precios de referencia del catálogo vigente, y se confirman en el acuerdo de Plot Lock / construcción. No son una oferta vinculante.',
        id: 'Tidak — harga tanah dan konstruksi adalah harga referensi sesuai katalog saat ini, dikonfirmasi dalam perjanjian Plot Lock / konstruksi. Bukan penawaran yang mengikat.' },
    'Is this an investment product?': { es: '¿Es un producto de inversión?', id: 'Apakah ini produk investasi?' },
    'No. This is the direct purchase of a real-estate asset (a land plot under Hak Sewa), not a security, fund, or tokenised instrument. Lawang separately operates a distinct project for tokenised real-estate exposure (LawangRWA) — Palm Field is not part of it.':
      { es: 'No. Es la compra directa de un activo inmobiliario (una parcela en Hak Sewa), no un valor, un fondo ni un instrumento tokenizado. Lawang opera aparte un proyecto distinto de exposición inmobiliaria tokenizada (LawangRWA) — Palm Field no forma parte de él.',
        id: 'Bukan. Ini pembelian langsung aset properti (kavling tanah dengan Hak Sewa), bukan efek, reksa dana, atau instrumen tokenisasi. Lawang secara terpisah menjalankan proyek lain untuk eksposur properti tertokenisasi (LawangRWA) — Palm Field bukan bagian darinya.' },
    'How are construction-stage payments protected?': { es: '¿Cómo se protegen los pagos por hitos de obra?', id: 'Bagaimana pembayaran tahap konstruksi dilindungi?' },
    'Construction payments are not made upfront in full — they are split into stages tied to verified progress on site (foundations, structure, enclosures, installations, finishes and handover), per your construction agreement.':
      { es: 'Los pagos de construcción no se abonan por adelantado en su totalidad — se reparten en hitos ligados a avance verificado en obra (cimentación, estructura, cerramientos, instalaciones, acabados y entrega), según tu contrato de construcción.',
        id: 'Pembayaran konstruksi tidak dibayar penuh di muka — dibagi menjadi tahapan yang terikat pada progres terverifikasi di lokasi (pondasi, struktur, dinding, instalasi, finishing, dan serah terima), sesuai perjanjian konstruksi Anda.' },
    'Can I resell, transfer or leave the plot to my heirs?': { es: '¿Puedo revender, transmitir o dejar la parcela en herencia?', id: 'Bisakah saya menjual kembali, mengalihkan, atau mewariskan kavling?' },
    'Yes — Hak Sewa rights are transferable, sellable and heritable within the registered lease term, subject to the conditions of your specific Hak Sewa agreement. Our team can walk you through the process for your situation.':
      { es: 'Sí — los derechos de Hak Sewa son transmisibles, vendibles y heredables dentro del plazo inscrito, sujeto a las condiciones de tu contrato concreto de Hak Sewa. Nuestro equipo puede explicarte el proceso en tu caso.',
        id: 'Bisa — hak dalam Hak Sewa dapat dialihkan, dijual, dan diwariskan dalam jangka sewa terdaftar, tunduk pada ketentuan perjanjian Hak Sewa Anda. Tim kami dapat memandu prosesnya sesuai situasi Anda.' },
    'What happens after I reserve a plot?': { es: '¿Qué pasa después de reservar una parcela?', id: 'Apa yang terjadi setelah saya memesan kavling?' },
    "You receive the Letter of Reservation by email with payment instructions for the reservation fee. Our team follows up to move the process to the next stage (Plot Lock / Hak Sewa deed) within the reservation's validity period.":
      { es: 'Recibes la Carta de Reserva por email con las instrucciones de pago de la cuota. Nuestro equipo hace el seguimiento para pasar a la siguiente fase (Plot Lock / escritura de Hak Sewa) dentro del plazo de validez de la reserva.',
        id: 'Anda menerima Surat Pemesanan lewat email beserta instruksi pembayaran biaya pemesanan. Tim kami menindaklanjuti untuk melanjutkan ke tahap berikutnya (Plot Lock / akta Hak Sewa) dalam masa berlaku pemesanan.' },

    /* — galería — */
    'Site & Delivered Villas': { es: 'El sitio y las villas entregadas', id: 'Lokasi & Villa Terbangun' },
    'Plots, surrounding land and villa models already delivered on neighbouring phases.':
      { es: 'Parcelas, entorno y modelos de villa ya entregados en fases contiguas.',
        id: 'Kavling, lingkungan sekitar, dan model villa yang sudah diserahterimakan di fase sebelah.' },
    'Plot — aerial view': { es: 'Parcela — vista aérea', id: 'Kavling — tampak udara' },
    'The plot': { es: 'La parcela', id: 'Kavlingnya' },
    'The view': { es: 'Las vistas', id: 'Pemandangannya' },
    'The villas — Balian river': { es: 'Las villas — río Balian', id: 'Villa — sungai Balian' },
    'Balian coast': { es: 'Costa de Balian', id: 'Pesisir Balian' },
    'Balian sunset': { es: 'Atardecer en Balian', id: 'Senja di Balian' },
    'Volcano & ocean': { es: 'Volcán y océano', id: 'Gunung & laut' },
    'Jungle canopy': { es: 'Dosel de selva', id: 'Kanopi hutan' },
    'Dali model': { es: 'Modelo Dali', id: 'Model Dali' },
    'Dune model — exterior': { es: 'Modelo Dune — exterior', id: 'Model Dune — eksterior' },
    'Dune model — interior': { es: 'Modelo Dune — interior', id: 'Model Dune — interior' },
    'Dune model — floor plan': { es: 'Modelo Dune — plano', id: 'Model Dune — denah' },
    'Dream model — evening': { es: 'Modelo Dream — de noche', id: 'Model Dream — malam' },
    'Dream model — day': { es: 'Modelo Dream — de día', id: 'Model Dream — siang' },
    'Dream model — floor plan': { es: 'Modelo Dream — plano', id: 'Model Dream — denah' },

    /* — CTA y formulario — */
    'Palm Field · 2026': { es: 'Palm Field · 2026', id: 'Palm Field · 2026' },
    'Request the Executive Dossier': { es: 'Pide el dossier ejecutivo', id: 'Minta Dosir Eksekutif' },
    'Not ready to reserve a specific plot yet? Tell us your interest and our team will follow up with the full documentation.':
      { es: '¿Todavía no quieres reservar una parcela concreta? Dinos qué te interesa y nuestro equipo te hará llegar la documentación completa.',
        id: 'Belum siap memesan kavling tertentu? Beri tahu minat Anda dan tim kami akan mengirimkan dokumentasi lengkap.' },
    'Lawang Properties': { es: 'Lawang Properties', id: 'Lawang Properties' },
    'Palm Field · Balian Hills, Bali': { es: 'Palm Field · Balian Hills, Bali', id: 'Palm Field · Balian Hills, Bali' },
    'Your data is processed only to manage this request.': { es: 'Tus datos se tratan solo para gestionar esta solicitud.', id: 'Data Anda hanya diproses untuk menangani permintaan ini.' },
    'Full name *': { es: 'Nombre completo *', id: 'Nama lengkap *' },
    'Email *': { es: 'Email *', id: 'Email *' },
    'Phone / WhatsApp': { es: 'Teléfono / WhatsApp', id: 'Telepon / WhatsApp' },
    'Interest': { es: 'Interés', id: 'Minat' },
    'Not sure yet': { es: 'Aún no lo sé', id: 'Belum yakin' },
    'Land plot only': { es: 'Solo parcela', id: 'Hanya kavling' },
    'Multiple plots / portfolio': { es: 'Varias parcelas / cartera', id: 'Beberapa kavling / portofolio' },
    'Notes': { es: 'Notas', id: 'Catatan' },
    'Request dossier': { es: 'Pedir dossier', id: 'Minta dosir' },
    'Lawang Properties — Palm Field': { es: 'Lawang Properties — Palm Field', id: 'Lawang Properties — Palm Field' },
    'Balian Hills, Bali. Developed by PT SAN DAL WOODS.': { es: 'Balian Hills, Bali. Promueve PT SAN DAL WOODS.', id: 'Balian Hills, Bali. Dikembangkan oleh PT SAN DAL WOODS.' },
    'This page does not replace legal or financial advice. Nothing here is an offer to sell securities or a solicitation of investment.':
      { es: 'Esta página no sustituye al asesoramiento jurídico ni financiero. Nada de lo aquí publicado es una oferta de venta de valores ni una solicitud de inversión.',
        id: 'Halaman ini tidak menggantikan nasihat hukum atau keuangan. Tidak ada di sini yang merupakan penawaran penjualan efek atau ajakan berinvestasi.' },

    /* — modal de reserva — */
    'Reserve plot': { es: 'Reservar parcela', id: 'Pesan kavling' },
    "We'll email you a one-time verification code before anything is issued.": { es: 'Te enviaremos por email un código de verificación de un solo uso antes de emitir nada.', id: 'Kami akan mengirimkan kode verifikasi sekali pakai ke email Anda sebelum apa pun diterbitkan.' },
    'Full name': { es: 'Nombre completo', id: 'Nama lengkap' },
    'Passport number': { es: 'Número de pasaporte', id: 'Nomor paspor' },
    'Email': { es: 'Email', id: 'Email' },
    'Phone': { es: 'Teléfono', id: 'Telepon' },
    'Nationality': { es: 'Nacionalidad', id: 'Kewarganegaraan' },
    'Address': { es: 'Domicilio', id: 'Alamat' },
    "I have read and agree to the reservation terms and Lawang's privacy policy, and consent to my data being processed to manage this reservation.":
      { es: 'He leído y acepto las condiciones de reserva y la política de privacidad de Lawang, y consiento el tratamiento de mis datos para gestionar esta reserva.',
        id: 'Saya telah membaca dan menyetujui ketentuan pemesanan serta kebijakan privasi Lawang, dan menyetujui data saya diproses untuk menangani pemesanan ini.' },
    'Cancel': { es: 'Cancelar', id: 'Batal' },
    'Send verification code': { es: 'Enviar código', id: 'Kirim kode verifikasi' },
    'Enter your code': { es: 'Introduce tu código', id: 'Masukkan kode Anda' },
    'We sent a 6-digit code to your email. It expires in 10 minutes.': { es: 'Hemos enviado un código de 6 dígitos a tu email. Caduca en 10 minutos.', id: 'Kami mengirim kode 6 digit ke email Anda. Berlaku 10 menit.' },
    'Verification code': { es: 'Código de verificación', id: 'Kode verifikasi' },
    'Back': { es: 'Atrás', id: 'Kembali' },
    'Confirm reservation': { es: 'Confirmar reserva', id: 'Konfirmasi pemesanan' },
    'Close': { es: 'Cerrar', id: 'Tutup' },
    'Reservation confirmed': { es: 'Reserva confirmada', id: 'Pemesanan dikonfirmasi' },

    /* — mensajes de error del flujo — */
    'Please fill in your name, passport number and email.': { es: 'Rellena tu nombre, número de pasaporte y email.', id: 'Mohon isi nama, nomor paspor, dan email Anda.' },
    'Please accept the reservation terms and privacy policy to continue.': { es: 'Acepta las condiciones de reserva y la política de privacidad para continuar.', id: 'Mohon setujui ketentuan pemesanan dan kebijakan privasi untuk melanjutkan.' },
    'Enter the code we emailed you.': { es: 'Introduce el código que te hemos enviado.', id: 'Masukkan kode yang kami kirim ke email Anda.' },
    'That code is invalid or has expired. Please go back and request a new one.': { es: 'Ese código no es válido o ha caducado. Vuelve atrás y pide uno nuevo.', id: 'Kode tidak valid atau sudah kedaluwarsa. Silakan kembali dan minta yang baru.' },
    'This plot is no longer available. Please choose another one.': { es: 'Esta parcela ya no está disponible. Elige otra.', id: 'Kavling ini sudah tidak tersedia. Silakan pilih yang lain.' },
    'Please accept the reservation terms to continue.': { es: 'Acepta las condiciones de reserva para continuar.', id: 'Mohon setujui ketentuan pemesanan untuk melanjutkan.' },
    'Some required information is missing.': { es: 'Falta información obligatoria.', id: 'Ada informasi wajib yang belum diisi.' },
    'Please wait a moment before trying again.': { es: 'Espera un momento antes de volver a intentarlo.', id: 'Mohon tunggu sebentar sebelum mencoba lagi.' },
    'We could not reach the server. Please try again in a moment.': { es: 'No hemos podido conectar con el servidor. Inténtalo de nuevo en un momento.', id: 'Kami tidak dapat menghubungi server. Coba lagi sebentar.' },
    'Please fill in your name and email.': { es: 'Rellena tu nombre y tu email.', id: 'Mohon isi nama dan email Anda.' },
    'Thank you — our team will be in touch shortly with the full dossier.': { es: 'Gracias — nuestro equipo te escribirá en breve con el dossier completo.', id: 'Terima kasih — tim kami akan segera menghubungi Anda dengan dosir lengkap.' },
    'Sending…': { es: 'Enviando…', id: 'Mengirim…' },
    'Confirming…': { es: 'Confirmando…', id: 'Mengonfirmasi…' },
    'Loading…': { es: 'Cargando…', id: 'Memuat…' },
    'Loading live plot data…': { es: 'Cargando parcelas en vivo…', id: 'Memuat data kavling langsung…' },
    'No plots published yet.': { es: 'Todavía no hay parcelas publicadas.', id: 'Belum ada kavling yang dipublikasikan.' },

    /* Fragmentos: el importe va envuelto en <span data-eur>, asi que la frase
       llega al walker partida en dos nodos de texto. */
    'Formal plot lock with': { es: 'Bloqueo formal de la parcela con', id: 'Penguncian resmi kavling dengan' },
    "in the notary's escrow account.": { es: 'en la cuenta escrow del notario.', id: 'di rekening escrow notaris.' },

    'A first-year operating forecast under two scenarios (Average / Optimal occupancy). This is a forecast, not a guarantee — actual results depend on the rental operator, market conditions and property management agreement in force.':
      { es: 'Previsión operativa de primer año bajo dos escenarios (ocupación media / óptima). Es una previsión, no una garantía — el resultado real depende del operador de alquiler, de las condiciones de mercado y del contrato de gestión vigente.',
        id: 'Proyeksi operasional tahun pertama dalam dua skenario (okupansi rata-rata / optimal). Ini proyeksi, bukan jaminan — hasil sebenarnya bergantung pada operator sewa, kondisi pasar, dan perjanjian pengelolaan yang berlaku.' },

    /* Cabecera de cada tarjeta de forecast */
    'Construction:': { es: 'Construcción:', id: 'Konstruksi:' },
    'Total investment (ROI base):': { es: 'Inversión total (base del ROI):', id: 'Total investasi (basis ROI):' },

    /* Sellos del plano: van en MAYUSCULAS y la busqueda distingue mayusculas */
    'RESERVED': { es: 'RESERVADA', id: 'DIPESAN' },
    'SOLD': { es: 'VENDIDA', id: 'TERJUAL' },

    'We could not load live plot data right now. Please contact': { es: 'Ahora mismo no hemos podido cargar las parcelas en vivo. Escríbenos a', id: 'Saat ini kami tidak dapat memuat data kavling langsung. Silakan hubungi' },
    'We could not reach the server. Please try again in a moment or email sales@lawangproperties.com directly.': { es: 'No hemos podido conectar con el servidor. Inténtalo de nuevo en un momento o escríbenos a sales@lawangproperties.com.', id: 'Kami tidak dapat menghubungi server. Coba lagi sebentar atau kirim email ke sales@lawangproperties.com.' },

    /* Atributos: placeholder y alt. El alt lo lee un lector de pantalla y sale
       cuando la imagen no carga, asi que tambien se traduce. */
    'Timeframe, budget range, Bali vs Sumba…': { es: 'Plazos, presupuesto aproximado, Bali o Sumba…', id: 'Jangka waktu, kisaran anggaran, Bali atau Sumba…' },
    'Palm Field villas stepped down the Balian river valley at dusk': { es: 'Villas de Palm Field escalonadas sobre el valle del río Balian al atardecer', id: 'Villa Palm Field bertingkat menuruni lembah sungai Balian saat senja' },
    'Palm Field masterplan showing every plot code and surface area': { es: 'Masterplan de Palm Field con el código y la superficie de cada parcela', id: 'Masterplan Palm Field dengan kode dan luas setiap kavling' },

    /* — selector — */
    'Contract in EUR. Other currencies are indicative, converted at a fixed rate of':
      { es: 'El contrato va en EUR. Las demás divisas son orientativas, a un tipo fijo de',
        id: 'Kontrak dalam EUR. Mata uang lain bersifat indikatif, dikonversi pada kurs tetap' }
  };

  /* Frases con una CIFRA dentro: se casan por patrón y el número se conserva
     tal cual ($1). Mismo criterio que assets/i18n-landing.js. */
  var PAT = [
    /* 'Type 01', 'Type 02'... eran tres entradas a mano en D. La seccion la
       llena ahora la intranet, asi que el cuarto modelo ya existia y el cuarto
       'Tipo 04' no. Un patron cubre la clase entera y no hay que volver aqui. */
    { re: /^Type (\d{2})$/, es: 'Tipo $1', id: 'Tipe $1' },
    { re: /^Formal plot lock with (\S+) in the notary's escrow account\.$/,
      es: 'Bloqueo formal de la parcela con $1 en la cuenta escrow del notario.',
      id: 'Penguncian resmi kavling dengan $1 di rekening escrow notaris.' },
    { re: /^(\d+) of (\d+) plots available$/,
      es: '$1 de $2 parcelas disponibles', id: '$1 dari $2 kavling tersedia' },
    { re: /^(.+) m² · Reference price (.+)$/,
      es: '$1 m² · Precio de referencia $2', id: '$1 m² · Harga referensi $2' },
    { re: /^Dune · 1 bedroom$/, es: 'Dune · 1 dormitorio', id: 'Dune · 1 kamar tidur' },
    { re: /^Dream · 2 bedrooms$/, es: 'Dream · 2 dormitorios', id: 'Dream · 2 kamar tidur' },
    { re: /^Dali · 1 bedroom$/, es: 'Dali · 1 dormitorio', id: 'Dali · 1 kamar tidur' },
    { re: /^Year-1 Rental Forecast — (.+)$/,
      es: 'Previsión de alquiler Año 1 — $1', id: 'Proyeksi Sewa Tahun ke-1 — $1' },
    { re: /^Reserve plot (\S+)$/, es: 'Reservar parcela $1', id: 'Pesan kavling $1' },
    { re: /^(\S+) villa model$/, es: 'Modelo de villa $1', id: 'Model villa $1' }
  ];

  /* Textos largos con <b>/<br> dentro: se traducen por innerHTML sobre el
     elemento entero, porque el walker de nodos de texto los vería partidos. */
  var HTML_BLOQUES = [
    { sel: '#forecast-nota',
      es: 'Las cifras son una previsión operativa de Año 1 facilitada por Lawang, no una rentabilidad garantizada ni histórica. El ROI se calcula sobre la inversión total (construcción más suelo) que indica cada tarjeta; la parte de suelo depende de la parcela elegida. Los porcentajes de gestión, mantenimiento e impuesto de alquiler son los del contrato de gestión vigente y pueden cambiar.',
      id: 'Angka-angka ini adalah proyeksi operasional Tahun ke-1 dari Lawang, bukan imbal hasil yang dijamin maupun historis. ROI dihitung atas total investasi (konstruksi ditambah tanah) yang tertera di setiap kartu; bagian tanah tergantung kavling yang dipilih. Persentase pengelolaan, pemeliharaan, dan pajak sewa mengikuti perjanjian pengelolaan yang berlaku dan dapat berubah.' }
  ];

  // Atributos visibles que también se traducen
  var ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];

  function aplicaPatron(txt, lang) {
    for (var i = 0; i < PAT.length; i++) {
      var m = PAT[i].re.exec(txt);
      if (m) {
        var out = PAT[i][lang];
        if (typeof out === 'function') return out(m);
        return out.replace(/\$(\d)/g, function (_, n) { return m[+n]; });
      }
    }
    return null;
  }

  function tr(txt, lang) {
    var k = txt.replace(/\s+/g, ' ').trim();
    if (!k) return null;
    var e = D[k];
    if (e && e[lang]) return e[lang];
    return aplicaPatron(k, lang);
  }
  window.lwT = tr;

  /* Los iconos de Material Symbols se pintan con LIGADURAS: su texto es
     "gavel", "verified"… Traducirlo rompe el icono. Se saltan siempre. */
  function saltar(nodo) {
    var p = nodo.parentNode;
    while (p && p.nodeType === 1) {
      var c = p.className;
      if (typeof c === 'string' && c.indexOf('material-symbols') !== -1) return true;
      var t = p.tagName;
      if (t === 'SCRIPT' || t === 'STYLE' || t === 'NOSCRIPT') return true;
      if (p.hasAttribute && p.hasAttribute('data-no-i18n')) return true;
      p = p.parentNode;
    }
    return false;
  }

  function traduceArbol(raiz, lang) {
    if (lang === 'en') return;
    var it = document.createTreeWalker(raiz, NodeFilter.SHOW_TEXT, null, false);
    var pend = [], n;
    while ((n = it.nextNode())) pend.push(n);
    pend.forEach(function (nodo) {
      if (saltar(nodo)) return;
      var t = tr(nodo.nodeValue, lang);
      if (t != null) {
        // se respeta el espaciado original de los lados
        var pre = /^\s*/.exec(nodo.nodeValue)[0];
        var post = /\s*$/.exec(nodo.nodeValue)[0];
        nodo.nodeValue = pre + t + post;
      }
    });
    ATTRS.forEach(function (a) {
      var els = raiz.querySelectorAll ? raiz.querySelectorAll('[' + a + ']') : [];
      Array.prototype.forEach.call(els, function (el) {
        var t = tr(el.getAttribute(a), lang);
        if (t != null) el.setAttribute(a, t);
      });
    });
    HTML_BLOQUES.forEach(function (b) {
      var el = document.querySelector(b.sel);
      if (el && b[lang]) el.innerHTML = b[lang];
    });
  }

  /* ── Dinero en el HTML estático ───────────────────────────────────────────
     Cualquier elemento con data-eur se repinta al cambiar de divisa. Así el
     importe no queda congelado en euros dentro del marcado. */
  function repintaDinero() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-eur]'), function (el) {
      var v = parseFloat(el.getAttribute('data-eur'));
      if (isNaN(v)) return;
      var neg = v < 0;
      el.textContent = (neg ? '−' : '') + fmtEUR(Math.abs(v), CUR);
    });
    var nota = document.getElementById('fx-nota');
    if (nota) {
      nota.style.display = CUR === 'EUR' ? 'none' : '';
      var lbl = document.getElementById('fx-nota-txt');
      if (lbl) {
        lbl.textContent = (tr('Contract in EUR. Other currencies are indicative, converted at a fixed rate of', LANG) ||
          'Contract in EUR. Other currencies are indicative, converted at a fixed rate of') +
          ' ' + RATES[CUR].toLocaleString('en-GB') + ' ' + CUR + '/EUR (' + RATES_FECHA + ').';
      }
    }
  }
  window.lwRepintaDinero = repintaDinero;


  /* ── Selector, con el aspecto del de la landing ───────────────────────────
     Reutiliza las MISMAS clases y los mismos estilos que `montaSelector` de
     `assets/idioma-web.js` (boton + desplegable `.lw-lang`), para que el deck
     no tenga un control distinto al del resto de la web.
     No se carga aquel modulo directamente porque traduce por claves
     `data-i18n` y este deck casa por texto completo: cargarlo haria que dos
     motores de idioma se pisaran (velo antidestello, data-i18n-listo y la
     resolucion de LANG por duplicado). Se comparte la pieza visual y la clave
     `lawang_lang`, no el motor. Si algun dia se unifican, el sitio natural es
     ese fichero — mismas clases a proposito. */
  function ponEstilos() {
    if (document.getElementById('lw-lang-css')) return;
    var st = document.createElement('style');
    st.id = 'lw-lang-css';
    st.textContent =
      '.lw-lang{position:relative;display:inline-flex;flex:none}' +
      '.lw-lang__btn{display:inline-flex;align-items:center;gap:6px;background:none;border:0;cursor:pointer;' +
        'font-family:var(--lw-lang-font,inherit);font-size:var(--lw-lang-size,11px);font-weight:500;' +
        'letter-spacing:.12em;text-transform:uppercase;color:var(--lw-lang-ink,currentColor);' +
        'min-height:24px;padding:4px 6px;line-height:1;border-radius:999px}' +
      '.lw-lang__btn:hover{opacity:.75}' +
      '.lw-lang__btn:focus-visible{outline:2px solid var(--lw-lang-ink,currentColor);outline-offset:2px}' +
      '.lw-lang__caret{font-size:.8em;opacity:.7}' +
      '.lw-lang__menu{position:absolute;top:calc(100% + 8px);right:0;z-index:120;margin:0;padding:6px;' +
        'list-style:none;min-width:150px;display:none;' +
        'background:var(--lw-lang-bg,#1a160f);border:1px solid var(--lw-lang-line,rgba(255,255,255,.18));' +
        'border-radius:10px;box-shadow:0 12px 34px rgba(0,0,0,.34)}' +
      '.lw-lang__menu.is-open{display:block}' +
      '.lw-lang__menu li{display:flex;align-items:center;min-height:36px;padding:8px 12px;cursor:pointer;' +
        'border-radius:7px;font-family:var(--lw-lang-font,inherit);font-size:13px;' +
        'color:var(--lw-lang-menu-ink,#f5f0e6);white-space:nowrap}' +
      '.lw-lang__menu li:hover{background:var(--lw-lang-hover,rgba(255,255,255,.1))}' +
      '.lw-lang__menu li.is-on{font-weight:700}' +
      '@media print{.lw-lang{display:none}}';
    document.head.appendChild(st);
  }

  var NOMBRE_LANG = { en: 'English', es: 'Español', id: 'Bahasa' };
  var NOMBRE_CUR = { EUR: 'EUR  €', USD: 'USD  $', AUD: 'AUD  A$', IDR: 'IDR  Rp' };

  function monta(host, opciones, actual, etiqueta, corto, alElegir) {
    var cont = typeof host === 'string' ? document.querySelector(host) : host;
    if (!cont) return;
    ponEstilos();
    var wrap = document.createElement('div');
    wrap.className = 'lw-lang';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'lw-lang__btn';
    btn.setAttribute('aria-haspopup', 'listbox');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', etiqueta);
    btn.innerHTML = '<span class="lw-lang__cur"></span><span class="lw-lang__caret" aria-hidden="true">▾</span>';
    btn.querySelector('.lw-lang__cur').textContent = corto[actual];

    var ul = document.createElement('ul');
    ul.className = 'lw-lang__menu';
    ul.setAttribute('role', 'listbox');
    opciones.forEach(function (c) {
      var li = document.createElement('li');
      li.setAttribute('role', 'option');
      li.setAttribute('data-val', c);
      li.setAttribute('aria-selected', c === actual ? 'true' : 'false');
      if (c === actual) li.className = 'is-on';
      li.textContent = NOMBRE_LANG[c] || NOMBRE_CUR[c] || c;
      ul.appendChild(li);
    });

    wrap.appendChild(btn); wrap.appendChild(ul); cont.appendChild(wrap);
    function cierra() { ul.classList.remove('is-open'); btn.setAttribute('aria-expanded', 'false'); }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      // solo un desplegable abierto a la vez
      Array.prototype.forEach.call(document.querySelectorAll('.lw-lang__menu.is-open'), function (o) {
        if (o !== ul) o.classList.remove('is-open');
      });
      var abierto = ul.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', abierto ? 'true' : 'false');
    });
    ul.addEventListener('click', function (e) {
      var li = e.target.closest ? e.target.closest('li[data-val]') : null;
      if (li) alElegir(li.getAttribute('data-val'));
    });
    document.addEventListener('click', function (e) { if (!wrap.contains(e.target)) cierra(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') cierra(); });
  }

  /* ── Selector ─────────────────────────────────────────────────────────────
     Recargar la página al cambiar es deliberado: el catálogo, las parcelas y
     la galería los pinta el JS, y volver a pintarlos a mano dejaría estados a
     medias. Una recarga con ?lang=&cur= es más barata y siempre coherente. */
  function recarga(lang, cur) {
    try { localStorage.setItem(CLAVE_LANG, lang); } catch (e) {}
    try { localStorage.setItem(CLAVE_CUR, cur); } catch (e) {}
    var u = location.pathname + '?lang=' + lang + '&cur=' + cur + location.hash;
    location.href = u;
  }

  window.lwDeck = {
    lang: LANG, cur: CUR, idiomas: IDIOMAS, monedas: MONEDAS,
    montaSelectores: function (host) {
      var etiq = { en: 'Language', es: 'Idioma', id: 'Bahasa' }[LANG];
      var etiqCur = { en: 'Currency', es: 'Moneda', id: 'Mata uang' }[LANG];
      monta(host, IDIOMAS, LANG, etiq, { en: 'EN', es: 'ES', id: 'ID' }, function (v) { recarga(v, CUR); });
      monta(host, MONEDAS, CUR, etiqCur, { EUR: 'EUR', USD: 'USD', AUD: 'AUD', IDR: 'IDR' }, function (v) { recarga(LANG, v); });
    },
    traduce: function (raiz) { traduceArbol(raiz || document.body, LANG); },
    setLang: function (v) { if (valida(v, IDIOMAS)) recarga(v, CUR); },
    setCur: function (v) { if (valida(v, MONEDAS)) recarga(LANG, v); }
  };
})();
