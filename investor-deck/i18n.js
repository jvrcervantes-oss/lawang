/* ═══════════════════════════════════════════════════════════════════════════
   Investor Deck GENÉRICO — idioma (EN/ES/ID) y divisa (EUR/USD/AUD/IDR)
   15-sep-2026

   Motor y mecánica calcados de investor-deck/palmfield/i18n.js (Regla 0: no se
   inventa un sistema nuevo) — misma clave compartida `lawang_lang` con la web
   pública, misma traducción por texto inglés completo, mismos símbolos/tipos
   de cambio. Lo que cambia es el DICCIONARIO: aquí solo entran cadenas que
   cualquier deck de cualquier proyecto puede emitir. Se retiran a propósito:
   - Todo lo que nombra "Palm Field" literalmente (esa copia es del piloto).
   - Todo el flujo de reserva de autoservicio (modal, formulario, mensajes de
     error): el deck genérico es solo informativo (decisión del owner,
     15-sep-2026) — cada parcela usa "Contact us", nunca un botón "Reserve".
   - Los pies de foto y nombres de modelo concretos de Palm Field (Dali/Dune/
     Dream): en el deck genérico esos textos vienen de la base de datos con
     sus tres idiomas YA dentro de la fila (deck_fotos.pie, igual que aquí);
     no pasan por este diccionario, que solo casa texto fijo del HTML/JS.

   ⚠️ PENDIENTE: el texto legal en ES/ID de este fichero es el mismo que ya usa
   Palm Field, no ha pasado revisión de Legal aparte para "genérico" (ver
   pendiente en investor-deck/palmfield/i18n.js). El inglés es el auditado.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var IDIOMAS = ['en', 'es', 'id'];
  var CLAVE_LANG = 'lawang_lang';          // compartida con la web pública
  var CLAVE_CUR = 'lw_deck_cur';           // propia del deck

  var SYMS = { EUR: '€', USD: '$', AUD: 'A$', IDR: 'Rp ' };
  var RATES = { EUR: 1, USD: 1.08, AUD: 1.62, IDR: 17500 };
  var RATES_FECHA = '16 Sep 2026';
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

  /* Clave = el texto inglés EXACTO tal y como sale en pantalla. */
  var D = {
    /* — navegación y cabecera — */
    'Project & Photos': { es: 'Proyecto y fotos', id: 'Proyek & Foto' },
    'Villa Models': { es: 'Modelos de villa', id: 'Model Villa' },
    'Masterplan & Plots': { es: 'Masterplan y parcelas', id: 'Masterplan & Kavling' },
    'Financial Forecast': { es: 'Previsión financiera', id: 'Proyeksi Keuangan' },
    'Legal Security': { es: 'Seguridad jurídica', id: 'Keamanan Hukum' },
    'FAQ': { es: 'Preguntas', id: 'FAQ' },
    'Read Lawang’s Privacy & Terms': { es: 'Leer la política de privacidad y el aviso legal de Lawang', id: 'Baca Kebijakan Privasi & Ketentuan Lawang' },
    'Privacy & Terms': { es: 'Privacidad y aviso legal', id: 'Privasi & Ketentuan' },
    'Download dossier': { es: 'Descargar dosier', id: 'Unduh dosir' },
    'Questions? WhatsApp': { es: '¿Dudas? WhatsApp', id: 'Ada pertanyaan? WhatsApp' },
    'Previous photos': { es: 'Fotos anteriores', id: 'Foto sebelumnya' },
    'More photos': { es: 'Más fotos', id: 'Foto lainnya' },
    'Dossier': { es: 'Dossier', id: 'Dosir' },

    /* — v3 (24-sep-2026): cadenas nuevas de la composicion de la home que el deck
       generico adopta como diseño estandar. Solo rotulos y navegacion; ninguna es
       texto legal. El ES/ID sigue el mismo estado que el resto del fichero. — */
    'Menu': { es: 'Menú', id: 'Menu' },
    'Sections': { es: 'Secciones', id: 'Bagian' },
    'by Lawang Properties': { es: 'por Lawang Properties', id: 'oleh Lawang Properties' },
    'Catalog': { es: 'Catálogo', id: 'Katalog' },
    'Investment': { es: 'Inversión', id: 'Investasi' },
    'Market forecast': { es: 'Previsión de mercado', id: 'Proyeksi pasar' },
    'View model': { es: 'Ver modelo', id: 'Lihat model' },
    'Talk to us on WhatsApp': { es: 'Háblanos por WhatsApp', id: 'Hubungi kami via WhatsApp' },
    'Tap a plot to find it in the live inventory.':
      { es: 'Toca una parcela para verla en el inventario en vivo.',
        id: 'Ketuk kavling untuk melihatnya di daftar ketersediaan langsung.' },
    /* Frase de la v1 que ya salia en ingles sin traducir. ES e ID con la redaccion de
       Legal (consulta de deploy capa 1, 24-sep-2026). ⚠️ PENDIENTE: el ID lo tiene que
       revisar un hablante nativo antes de darlo por cerrado. */
    'Status is live; surface areas shown are project/design measurements, confirmed by survey at Plot Lock — not the registered legal area.':
      { es: 'El estado se actualiza en tiempo real; las superficies indicadas son medidas de proyecto/diseño, que se confirman por levantamiento topográfico en el Plot Lock, y no son la superficie legal registrada.',
        id: 'Status diperbarui secara langsung; luas yang ditampilkan adalah ukuran proyek/desain, dikonfirmasi lewat survei saat Plot Lock — bukan luas resmi yang tercatat dalam sertifikat tanah.' },

    /* — portada — */
    'Investor Deck · Due Diligence': { es: 'Dossier de inversión · Due diligence', id: 'Dosir Investor · Uji Tuntas' },
    'Not a security or investment product. Real documentation, live plot inventory and a Year-1 forecast, for your own due diligence — the land tenure structure for this specific project is confirmed by your Lawang contact.':
      { es: 'No es un valor ni un producto de inversión. Documentación real, inventario de parcelas en vivo y una previsión de Año 1, para tu propia due diligence — tu contacto en Lawang te confirma la estructura de tenencia de este proyecto en concreto.',
        id: 'Bukan efek maupun produk investasi. Dokumentasi nyata, ketersediaan kavling secara langsung, dan proyeksi Tahun ke-1, untuk uji tuntas Anda sendiri — struktur kepemilikan lahan untuk proyek ini dikonfirmasi oleh kontak Lawang Anda.' },
    'Fotografía en preparación': { es: 'Fotografía en preparación', id: 'Fotografía en preparación' },
    'Photography in preparation': { es: 'Fotografía en preparación', id: 'Foto sedang disiapkan' },

    /* — KPIs (etiquetas genéricas; el valor viene de deck_config_proyecto.kpis) — */
    'Land Managed': { es: 'Suelo gestionado', id: 'Lahan Dikelola' },
    'Track Record': { es: 'Trayectoria', id: 'Rekam Jejak' },
    'Investors': { es: 'Inversores', id: 'Investor' },
    'Permits': { es: 'Licencias', id: 'Perizinan' },

    /* — catálogo — */
    'Villa Typologies': { es: 'Tipologías de villa', id: 'Tipologi Villa' },
    'Upon request': { es: 'Consultar', id: 'Atas permintaan' },
    'Renders in progress': { es: 'Renders en camino', id: 'Render sedang dibuat' },
    'We could not load the villa models right now. Please contact':
      { es: 'Ahora mismo no hemos podido cargar los modelos de villa. Escríbenos a',
        id: 'Saat ini kami tidak dapat memuat model villa. Silakan hubungi' },

    /* — panel de due diligence del hero — */
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
    'Most requested': { es: 'El más pedido', id: 'Paling diminati' },

    /* — masterplan — */
    'Masterplan & Plot Availability': { es: 'Masterplan y disponibilidad', id: 'Masterplan & Ketersediaan Kavling' },
    'Available': { es: 'Disponible', id: 'Tersedia' },
    'Reserved': { es: 'Reservada', id: 'Dipesan' },
    'Sold / Blocked': { es: 'Vendida / bloqueada', id: 'Terjual / Diblokir' },
    'Sold': { es: 'Vendida', id: 'Terjual' },
    'Blocked': { es: 'Bloqueada', id: 'Diblokir' },
    'Not available': { es: 'No disponible', id: 'Tidak tersedia' },
    'Live plot inventory': { es: 'Inventario en vivo', id: 'Ketersediaan Langsung' },
    // Ubicación (24-sep-2026)
    'Location': { es: 'Ubicación', id: 'Lokasi' },
    'Where the Project Is': { es: 'Dónde está el proyecto', id: 'Lokasi Proyek' },
    'Open in Google Maps': { es: 'Abrir en Google Maps', id: 'Buka di Google Maps' },
    'Contact us': { es: 'Escríbenos', id: 'Hubungi kami' },
    'No plots published yet.': { es: 'Todavía no hay parcelas publicadas.', id: 'Belum ada kavling yang dipublikasikan.' },

    /* — previsión financiera — */
    'Average': { es: 'Medio', id: 'Rata-rata' },
    'Optimal': { es: 'Óptimo', id: 'Optimal' },
    'ADR': { es: 'Precio medio/noche', id: 'Tarif rata-rata' },
    'Occupancy': { es: 'Ocupación', id: 'Okupansi' },
    'Gross villa income': { es: 'Ingreso bruto de la villa', id: 'Pendapatan kotor villa' },
    'Management fee': { es: 'Gestión', id: 'Biaya pengelolaan' },
    'Maintenance': { es: 'Mantenimiento', id: 'Pemeliharaan' },
    'Rental tax': { es: 'Impuesto de alquiler', id: 'Pajak sewa' },
    'Total investment (ROI base):': { es: 'Inversión total (base del ROI):', id: 'Total investasi (dasar ROI):' },
    'Construction:': { es: 'Construcción:', id: 'Konstruksi:' },
    'Net income': { es: 'Ingreso neto', id: 'Pendapatan bersih' },
    'ROI': { es: 'ROI', id: 'ROI' },
    'We could not load the rental forecast right now. Please contact':
      { es: 'Ahora mismo no hemos podido cargar la previsión de alquiler. Escríbenos a',
        id: 'Saat ini kami tidak dapat memuat proyeksi sewa. Silakan hubungi' },
    'A first-year operating forecast under two scenarios (Average / Optimal occupancy). This is a forecast, not a guarantee — actual results depend on the rental operator, market conditions and property management agreement in force.':
      { es: 'Previsión operativa de primer año bajo dos escenarios (ocupación media / óptima). Es una previsión, no una garantía — el resultado real depende del operador de alquiler, de las condiciones de mercado y del contrato de gestión vigente.',
        id: 'Proyeksi operasional tahun pertama dalam dua skenario (okupansi rata-rata / optimal). Ini proyeksi, bukan jaminan — hasil sebenarnya bergantung pada operator sewa, kondisi pasar, dan perjanjian pengelolaan yang berlaku.' },

    /* — seguridad jurídica (metodología estándar de la cartera, no de un
       proyecto en concreto — el nombre del proyecto se inserta por JS,
       nunca aquí) — */
    'Hak Sewa With Notarial Escrow vs. Informal Leasehold': { es: 'Hak Sewa con escrow notarial frente al leasehold informal', id: 'Hak Sewa dengan Escrow Notaris vs. Leasehold Informal' },
    "Much of Bali's foreign-facing market runs on private, unregistered lease agreements with no escrow and no notarial oversight. This project is structured as":
      { es: 'Buena parte del mercado de Bali dirigido a extranjeros funciona con contratos de arrendamiento privados, sin registrar, sin escrow y sin control notarial. Este proyecto se estructura como',
        id: 'Sebagian besar pasar Bali yang menyasar orang asing berjalan dengan perjanjian sewa privat, tidak terdaftar, tanpa escrow dan tanpa pengawasan notaris. Proyek ini disusun sebagai' },
    '(long-term Indonesian lease tenure) directly between the landowner and the buyer, with funds held in a':
      { es: '(arrendamiento de largo plazo del derecho indonesio) directamente entre el propietario del suelo y el comprador, con los fondos depositados en una',
        id: '(hak sewa jangka panjang menurut hukum Indonesia) langsung antara pemilik tanah dan pembeli, dengan dana ditahan di' },
    'notarial escrow account': { es: 'cuenta escrow notarial', id: 'rekening escrow notaris' },
    'until the agreed conditions are met — not Hak Milik, which Indonesian law reserves for Indonesian citizens.':
      { es: 'hasta que se cumplen las condiciones pactadas — no Hak Milik, que la ley indonesia reserva a los ciudadanos indonesios.',
        id: 'sampai syarat yang disepakati terpenuhi — bukan Hak Milik, yang oleh hukum Indonesia hanya untuk warga negara Indonesia.' },
    'Legal & registry aspect': { es: 'Aspecto jurídico y registral', id: 'Aspek hukum & pendaftaran' },
    'Hak Sewa + escrow': { es: 'Hak Sewa + escrow', id: 'Hak Sewa + escrow' },
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

    /* — documentos del proyecto — */
    'Project documents': { es: 'Documentación del proyecto', id: 'Dokumen proyek' },
    'Commercial': { es: 'Comercial', id: 'Komersial' },
    'Legal': { es: 'Legal', id: 'Legal' },
    'Technical': { es: 'Técnico', id: 'Teknis' },
    'Plots & pricing': { es: 'Parcelas y precios', id: 'Kavling & harga' },
    'Image': { es: 'Imagen', id: 'Gambar' },
    'Document': { es: 'Documento', id: 'Dokumen' },
    'View': { es: 'Ver', id: 'Lihat' },
    'Download': { es: 'Descargar', id: 'Unduh' },

    /* — FAQ — */
    'Frequently Asked Questions': { es: 'Preguntas frecuentes', id: 'Pertanyaan yang Sering Diajukan' },
    'We could not load the questions right now. Please contact':
      { es: 'Ahora mismo no hemos podido cargar las preguntas. Escríbenos a',
        id: 'Saat ini kami tidak dapat memuat pertanyaan. Silakan hubungi' },

    /* — galería — */
    'Site & Delivered Villas': { es: 'El sitio y las villas entregadas', id: 'Lokasi & Villa Terbangun' },
    'Plots, surrounding land and villa models already delivered on neighbouring phases.':
      { es: 'Parcelas, entorno y modelos de villa ya entregados en fases contiguas.',
        id: 'Kavling, lingkungan sekitar, dan model villa yang sudah diserahterimakan di fase sebelah.' },

    /* — pie de página — */
    'This page does not replace legal or financial advice. Nothing here is an offer to sell securities or a solicitation of investment.':
      { es: 'Esta página no sustituye al asesoramiento jurídico ni financiero. Nada de lo aquí publicado es una oferta de venta de valores ni una solicitud de inversión.',
        id: 'Halaman ini tidak menggantikan nasihat hukum atau keuangan. Tidak ada di sini yang merupakan penawaran penjualan efek atau ajakan berinvestasi.' },

    /* — selector — */
    'Contract in EUR. Other currencies are indicative, converted at a fixed rate of':
      { es: 'El contrato va en EUR. Las demás divisas son orientativas, a un tipo fijo de',
        id: 'Kontrak dalam EUR. Mata uang lain bersifat indikatif, dikonversi pada kurs tetap' },

    /* — deck no activo (estado vacío honesto, decisión Diseño 15-sep) — */
    'This project does not have its Investor Deck available yet.':
      { es: 'Este proyecto todavía no tiene su Investor Deck disponible.',
        id: 'Proyek ini belum memiliki Investor Deck yang tersedia.' },
    'Please contact our team for the latest documentation and availability.':
      { es: 'Escríbenos para la documentación y disponibilidad más recientes.',
        id: 'Silakan hubungi tim kami untuk dokumentasi dan ketersediaan terbaru.' }
  };

  var PAT = [
    { re: /^Type (\d{2})$/, es: 'Tipo $1', id: 'Tipe $1' },
    { re: /^(\d+) of (\d+) plots available$/,
      es: '$1 de $2 parcelas disponibles', id: '$1 dari $2 kavling tersedia' },
    { re: /^(.+) m² · (.+)\/m² land$/,
      es: '$1 m² · $2/m² de suelo', id: '$1 m² · $2/m² tanah' },
    { re: /^Land (.+) \+ Construction (.+) = (.+) total$/,
      es: 'Suelo $1 + Construcción $2 = $3 total', id: 'Tanah $1 + Konstruksi $2 = $3 total' },
    /* v3 (24-sep): parcela sin precio de construccion → solo el suelo. Va DETRAS de la
       de arriba (gana la primera que casa). Anclado a un importe (€, $, A$, Rp): un
       "Land (.+)" suelto medio-traducia cualquier pie de foto o titulo que empezara por
       "Land " ("Land clearing" → "Suelo clearing"; code-review 24-sep). */
    { re: /^Land ((?:€|A?\$|Rp )[\d.,]+)$/, es: 'Suelo $1', id: 'Tanah $1' },
    /* v3 (24-sep): frases armadas en JS con el nombre del proyecto dentro. Misma
       traduccion que ya usa Palm Field para las suyas (palmfield/i18n.js). */
    /* WhatsApp por parcela (v3, 24-sep: mensaje prellenado y aria-label del boton). El
       codigo va perezoso (.+?) porque puede llevar espacios ("S1 - H1"). */
    { re: /^Hello LAWANG, I’m interested in plot (.+?) at (.+)\.$/,
      es: 'Hola LAWANG, me interesa la parcela $1 de $2.',
      id: 'Halo LAWANG, saya tertarik dengan kavling $1 di $2.' },
    { re: /^Talk to us on WhatsApp about plot (.+)$/,
      es: 'Háblanos por WhatsApp sobre la parcela $1', id: 'Hubungi kami via WhatsApp tentang kavling $1' },
    { re: /^Hello LAWANG, I’m looking at the (.+) investor deck and I have a few questions\.$/,
      es: 'Hola LAWANG, estoy viendo el dosier de inversores de $1 y tengo algunas preguntas.',
      id: 'Halo LAWANG, saya sedang melihat dosir investor $1 dan ada beberapa pertanyaan.' },
    /* ID de «Individually cadastred plots» corregido por Legal (24-sep): «tersertifikasi»
       afirmaba titulos ya emitidos. ⚠️ PENDIENTE revision de hablante nativo del ID. */
    { re: /^Individually cadastred plots\. Live inventory read directly from (.+)'s records — sizes, prices and status are informational and confirmed at Plot Lock\.$/,
      es: 'Parcelas catastradas una a una. El inventario se lee en vivo de los registros de $1 — superficies, precios y estado son orientativos y se confirman en el Plot Lock.',
      id: 'Kavling diukur dan dipetakan secara kadastral satu per satu. Ketersediaan dibaca langsung dari catatan $1 — luas, harga, dan status bersifat informatif dan dikonfirmasi saat Plot Lock.' },
    { re: /^Year-1 Rental Forecast — (.+)$/,
      es: 'Previsión de alquiler Año 1 — $1', id: 'Proyeksi Sewa Tahun ke-1 — $1' },
    { re: /^(\S+) villa model$/, es: 'Modelo de villa $1', id: 'Model villa $1' },
    { re: /^(\d+) bedrooms?$/, es: '$1 dormitorio(s)', id: '$1 kamar tidur' }
  ];

  var HTML_BLOQUES = [
    { sel: '#forecast-nota',
      es: 'Las cifras son una previsión operativa de Año 1 facilitada por Lawang, no una rentabilidad garantizada ni histórica. El ROI se calcula sobre la inversión total (construcción más suelo) que indica cada tarjeta; la parte de suelo depende de la parcela elegida. Los porcentajes de gestión, mantenimiento e impuesto de alquiler son orientativos y se confirman en el contrato de gestión de alquiler que se firme; pueden cambiar.',
      id: 'Angka-angka ini adalah proyeksi operasional Tahun ke-1 dari Lawang, bukan imbal hasil yang dijamin maupun historis. ROI dihitung atas total investasi (konstruksi ditambah tanah) yang tertera di setiap kartu; bagian tanah tergantung kavling yang dipilih. Persentase pengelolaan, pemeliharaan, dan pajak sewa bersifat indikatif dan dikonfirmasi dalam perjanjian pengelolaan sewa yang Anda tandatangani; dapat berubah.' }
  ];

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

  /* Selector visual: MISMAS clases que palmfield/i18n.js (no se inventa un
     segundo aspecto para el mismo control). */
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
