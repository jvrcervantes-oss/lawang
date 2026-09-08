/* ═══════════════════════════════════════════════════════════════════════════
   Diccionario de la HOME de lawangproperties.com — EN / ES / ID   8-sep-2026
   Lo aplica `assets/idioma-web.js` (ver ahí el porqué de todo el sistema).
   ═══════════════════════════════════════════════════════════════════════════

   TRES REGLAS AL AÑADIR UNA CLAVE — las tres salen de la revisión previa:

   1. NO SE TRADUCE EL GLOSARIO DE TENENCIA. `freehold`, `leasehold`, `HGB`,
      `hak sewa`, `hak pakai`, `PT PMA`, `PBG`, `SLF`, `RDTR` van en su término
      de origen SIEMPRE. `freehold → hak milik` es literalmente correcto y
      jurídicamente letal: Hak Milik es solo para ciudadanos indonesios y el
      art. 26(2) UUPA anula de pleno derecho su transmisión a un extranjero.
      Escribirlo en bahasa sería ofrecer por escrito, en el idioma del
      regulador, el patrón nominee. Si hace falta glosa, la redacta Legal.

   2. NOMBRE DE LÍNEA SE QUEDA, DESCRIPTOR SE TRADUCE. Es el precedente que ya
      fijó el diccionario de `thecollection.php`: «Land Legacy» se queda igual
      en los tres idiomas y «Premium Parcels» pasa a «Parcelas premium» /
      «Kavling Premium». Igual con Signature, Riverfront II®, Tepi Sungai,
      Balian Hills, The Collection.

   3. LAS CLAVES `hero.*` Y `ct.h` SON DE DIRECCIÓN DE ARTE, NO DE TRADUCCIÓN.
      Van marcadas ✎. El H1 lleva `white-space:nowrap` y un tamaño calibrado
      para llenar el viewport exacto: una traducción literal no reflowea, se
      sale de la pantalla. Se escriben cortas para caber (2-4 palabras por
      línea), no se traducen palabra por palabra. No las rellene nadie a granel.

   Fallback duro a EN si falta una cadena: el módulo marca esos nodos con
   `lang="en"` para no incumplir WCAG 3.1.2 (Language of Parts). */
window.LW_I18N_HOME = {

  /* ── Navegación y cabecera ─────────────────────────────────────────────── */
  "nav.land":      { en: "The Land",      es: "El Suelo",        id: "Tanah" },
  "nav.villas":    { en: "The Villas",    es: "Las Villas",      id: "Villa" },
  "nav.soul":      { en: "The Soul",      es: "La Esencia",      id: "Jiwa" },
  "nav.portfolio": { en: "The Portfolio", es: "El Portafolio",   id: "Portofolio" },
  "cta.ask":       { en: "Ask Us Anything", es: "Pregúntanos lo que sea", id: "Tanya Apa Saja" },

  /* ── Hero ✎ dirección de arte ──────────────────────────────────────────── */
  /* EN «Turn Capital / Into Legacy». La estructura es fina+gruesa en dos
     líneas y hay que conservarla: el isotipo se apoya en el arranque de la 2ª.
     ES juega con la preposición para caber más corto que el inglés. */
  /* «Menjadi» (la forma larga de «convertirse en») MEDIDA en canvas a 390 px daba una
     segunda linea de 412 px contra 346 px utiles: se salia de la pantalla, porque el H1
     va en `white-space:nowrap` y no reflowea. «Jadi» dice lo mismo, es natural en
     titular y cabe (312 px). Esto es exactamente por que estas claves son de direccion
     de arte: la traduccion correcta no era la que cabia. */
  "hero.l1a": { en: "Turn",    es: "Del",     id: "Dari" },      // ✎
  "hero.l1b": { en: "Capital", es: "Capital", id: "Modal" },     // ✎
  "hero.l2a": { en: "Into",    es: "Al",      id: "Jadi" },      // ✎  ver nota
  "hero.l2b": { en: "Legacy",  es: "Legado",  id: "Warisan" },   // ✎
  "hero.sub1": {
    en: "We help international investors build lasting wealth in Indonesia.",
    es: "Ayudamos a inversores internacionales a construir patrimonio duradero en Indonesia.",
    id: "Kami membantu investor internasional membangun kekayaan yang bertahan di Indonesia."
  },
  "hero.sub2": {
    en: "through strategy, structure, and presence on the ground.",
    es: "con estrategia, estructura y presencia sobre el terreno.",
    id: "melalui strategi, struktur, dan kehadiran langsung di lapangan."
  },
  "hero.cta": {
    en: "Explore Tropical Territories",
    es: "Explora Territorios Tropicales",
    id: "Jelajahi Wilayah Tropis"
  },

  /* ── 2 · El ecosistema ─────────────────────────────────────────────────── */
  "eco.kicker":  { en: "The Tropical Ecosystem", es: "El Ecosistema Tropical", id: "Ekosistem Tropis" },
  "eco.title.a": { en: "Four ways,",  es: "Cuatro caminos,", id: "Empat jalan," },
  "eco.title.b": { en: "one legacy",  es: "un legado",       id: "satu warisan" },

  /* Nombre de línea intacto (regla 2), descriptor y reclamo traducidos. */
  "eco.sig.t":   { en: "Signature",          es: "Signature",              id: "Signature" },
  "eco.sig.s":   { en: "Villa Communities",  es: "Comunidades de villas",  id: "Komunitas Villa" },
  "eco.sig.c":   { en: "Elevated Living",    es: "Vivir en alto",          id: "Hunian Istimewa" },
  "eco.land.t":  { en: "Land Legacy",        es: "Land Legacy",            id: "Land Legacy" },
  "eco.land.s":  { en: "Premium Parcels",    es: "Parcelas premium",       id: "Kavling Premium" },
  "eco.land.c":  { en: "Curated Views",      es: "Vistas escogidas",       id: "Panorama Pilihan" },
  "eco.vil.t":   { en: "Villas",             es: "Villas",                 id: "Villa" },
  "eco.vil.s":   { en: "Private Residences", es: "Residencias privadas",   id: "Residensi Pribadi" },
  "eco.vil.c":   { en: "Integrated Design",  es: "Diseño integral",        id: "Desain Terpadu" },
  "eco.res.t":   { en: "Resorts",            es: "Resorts",                id: "Resort" },
  "eco.res.s":   { en: "Prime Hospitality",  es: "Hospitalidad premium",   id: "Hospitality Utama" },
  "eco.res.c":   { en: "Long-Term Value",    es: "Valor a largo plazo",    id: "Nilai Jangka Panjang" },

  /* ── 3 · La colección ──────────────────────────────────────────────────── */
  "pf.stmt1":   { en: "We don't list properties.", es: "No listamos propiedades.", id: "Kami tidak sekadar mendaftar properti." },
  "pf.stmt2":   { en: "We select them.",           es: "Las elegimos.",            id: "Kami memilihnya." },
  "pf.title":   { en: "The Collection",            es: "The Collection",           id: "The Collection" },
  "pf.viewall": { en: "See all projects",          es: "Ver todos los proyectos",  id: "Lihat semua proyek" },
  "pf.prev":    { en: "Previous properties",       es: "Propiedades anteriores",   id: "Properti sebelumnya" },
  "pf.next":    { en: "Next properties",           es: "Propiedades siguientes",   id: "Properti berikutnya" },

  /* ── 3b · Los servicios ────────────────────────────────────────────────── */
  "sv.kicker":  { en: "The Services", es: "Los Servicios", id: "Layanan Kami" },
  "sv.title.a": { en: "From land",    es: "De la tierra",  id: "Dari tanah" },
  "sv.title.b": { en: "to legacy",    es: "al legado",     id: "ke warisan" },
  "sv.sub":     { en: "Every stage of the investment journey.", es: "Cada etapa del camino de inversión.", id: "Setiap tahap perjalanan investasi." },

  "sv.1.h": { en: "<b>Territorial</b> Sourcing", es: "<b>Búsqueda</b> Territorial", id: "<b>Pencarian</b> Lahan" },
  "sv.1.p": {
    en: "Verified expansion corridors, and long-term upside.",
    es: "Corredores de expansión verificados y recorrido a largo plazo.",
    id: "Koridor ekspansi terverifikasi dengan potensi jangka panjang."
  },
  "sv.2.h": { en: "<b>Legal</b> and Structure", es: "<b>Legal</b> y Estructura", id: "<b>Legal</b> dan Struktur" },
  "sv.2.p": {
    en: "Every acquisition with full fiscal clarity.",
    es: "Cada adquisición con claridad fiscal completa.",
    id: "Setiap akuisisi dengan kejelasan fiskal penuh."
  },
  "sv.3.h": { en: "<b>Development</b> and Build", es: "<b>Desarrollo</b> y Obra", id: "<b>Pengembangan</b> dan Konstruksi" },
  "sv.3.p": {
    en: "Structural integrity and deep territorial knowledge.",
    es: "Integridad estructural y conocimiento profundo del territorio.",
    id: "Integritas struktural dan pemahaman mendalam atas wilayah."
  },
  "sv.4.h": { en: "<b>Management</b> and Returns", es: "<b>Gestión</b> y Rentabilidad", id: "<b>Pengelolaan</b> dan Hasil" },
  "sv.4.p": {
    en: "Our curated network of local management partners.",
    es: "Nuestra red seleccionada de gestores locales.",
    id: "Jaringan mitra pengelola lokal pilihan kami."
  },

  /* ── 6 · Indonesia ─────────────────────────────────────────────────────── */
  "ep.sub":   { en: "Where growth <b>is unstoppable.</b>", es: "Donde el crecimiento <b>no se detiene.</b>", id: "Tempat pertumbuhan <b>tak terbendung.</b>" },
  "ep.1.h":   { en: "The Archipelago", es: "El Archipiélago", id: "Nusantara" },
  "ep.1.p": {
    en: "is the largest economy in Southeast Asia, growing at 5%+ GDP. A G20 member. And a legal framework designed for the international investor.",
    es: "es la mayor economía del Sudeste Asiático, creciendo por encima del 5% del PIB. Miembro del G20. Y un marco legal pensado para el inversor internacional.",
    id: "adalah ekonomi terbesar di Asia Tenggara, tumbuh di atas 5% PDB. Anggota G20. Dengan kerangka hukum yang dirancang untuk investor internasional."
  },
  "ep.2.h":   { en: "Bali", es: "Bali", id: "Bali" },
  "ep.2.p": {
    en: "The island everyone chose.<br>The valley few have found.",
    es: "La isla que todos eligieron.<br>El valle que pocos han encontrado.",
    id: "Pulau yang dipilih semua orang.<br>Lembah yang jarang ditemukan."
  },
  "ep.2.cta": { en: "Explore Balian", es: "Explora Balian", id: "Jelajahi Balian" },
  "ep.3.h":   { en: "Sumba", es: "Sumba", id: "Sumba" },
  "ep.3.p": {
    en: "An island frozen in time.<br>Where the wild still decides.",
    es: "Una isla detenida en el tiempo.<br>Donde aún manda lo salvaje.",
    id: "Pulau yang membeku dalam waktu.<br>Tempat alam liar masih menentukan."
  },
  "ep.3.cta": { en: "Discover the Expedition", es: "Descubre la Expedición", id: "Temukan Ekspedisi" },

  /* ── 7 · Contacto ──────────────────────────────────────────────────────── */
  "ct.kicker": { en: "The Tropical Partner", es: "El Socio Tropical", id: "Mitra Tropis Anda" },
  /* ✎ Titular de display con `nowrap`. Mismo texto que ya usa el diccionario
     de `thecollection.php` (`own.t`) — una marca no dice dos cosas distintas
     en dos páginas. */
  "ct.h":      { en: "Own Eternity", es: "Poseer la Eternidad", id: "Miliki Keabadian" }, // ✎
  "ct.italic": {
    en: "Some places you visit. Others you keep.",
    es: "Algunos lugares se visitan. Otros se conservan.",
    id: "Sebagian tempat untuk dikunjungi. Sebagian lagi untuk dimiliki."
  },
  "ct.note": {
    en: "Share the legacy you have in mind and our advisors will return with hand-verified opportunities across Bali &amp; Sumba — no lists, only what truly fits.",
    es: "Cuéntanos qué legado tienes en mente y nuestros asesores volverán con oportunidades verificadas una a una en Bali y Sumba — sin listas, solo lo que de verdad encaja.",
    id: "Sampaikan warisan yang Anda bayangkan dan penasihat kami akan kembali dengan peluang yang diverifikasi satu per satu di Bali dan Sumba — bukan daftar panjang, hanya yang benar-benar cocok."
  },
  "ct.invest":  { en: "Investment",           es: "Inversión",            id: "Investasi" },
  "ct.advisor": { en: "Ask an Advisor",       es: "Habla con un asesor",  id: "Hubungi Penasihat" },
  "ct.dossier": { en: "Download the Dossier", es: "Descargar el dossier", id: "Unduh Dosir" },

  /* ── FAQ ───────────────────────────────────────────────────────────────── */
  /* ⚠️ PBG, SLF, IMB, HGB, PT PMA, Hak Pakai, RDTR y «freehold/leasehold» NO
     se traducen (regla 1). Se traduce la prosa que los rodea. */
  "faq.1.q": {
    en: "Do your projects have a building permit (PBG)?",
    es: "¿Vuestros proyectos tienen licencia de obra (PBG)?",
    id: "Apakah proyek Anda memiliki izin bangunan (PBG)?"
  },
  "faq.1.a": {
    en: "Yes. Every Lawang project is built under a valid <b>PBG</b> (Persetujuan Bangunan Gedung) — the building approval that replaced the old IMB in 2021. A PBG is only issued once the technical drawings comply with the local spatial plan, so it certifies that the construction is legal from day one. On completion the building also receives its <b>SLF</b> (Sertifikat Laik Fungsi), confirming it is fit for use. You never inherit an unpermitted structure.",
    es: "Sí. Todo proyecto de Lawang se construye con un <b>PBG</b> (Persetujuan Bangunan Gedung) en vigor — la aprobación de obra que sustituyó al antiguo IMB en 2021. Un PBG solo se emite cuando los planos técnicos cumplen el plan de ordenación local, así que certifica que la construcción es legal desde el primer día. Al terminarla, el edificio recibe además su <b>SLF</b> (Sertifikat Laik Fungsi), que confirma que es apta para el uso. Nunca heredas una estructura sin licencia.",
    id: "Ya. Setiap proyek Lawang dibangun dengan <b>PBG</b> (Persetujuan Bangunan Gedung) yang sah — persetujuan bangunan yang menggantikan IMB sejak 2021. PBG hanya terbit setelah gambar teknis sesuai dengan rencana tata ruang setempat, sehingga memastikan konstruksi legal sejak hari pertama. Setelah selesai, bangunan juga menerima <b>SLF</b> (Sertifikat Laik Fungsi) yang menyatakan bangunan layak difungsikan. Anda tidak pernah mewarisi bangunan tanpa izin."
  },
  "faq.2.q": {
    en: "Leasehold or freehold — what do you offer?",
    es: "Leasehold o freehold: ¿qué ofrecéis?",
    id: "Leasehold atau freehold — mana yang Anda tawarkan?"
  },
  "faq.2.a": {
    en: "We focus on <b>Freehold HGB</b> (Hak Guna Bangunan), the Right-to-Build title held through a PT&nbsp;PMA company. Unlike a leasehold — which is only a rental right for a fixed term that loses value as the years run out — HGB is a registered, certificated freehold-class title: it can be sold, inherited, mortgaged and renewed (30 years, then extendable 20 + 30). It is the most secure and most liquid way for a foreign investor to hold Bali real estate.",
    es: "Trabajamos sobre todo con <b>Freehold HGB</b> (Hak Guna Bangunan), el título de derecho de edificación que se ostenta a través de una sociedad PT&nbsp;PMA. A diferencia de un leasehold — que es solo un derecho de arrendamiento por un plazo fijo y pierde valor según se agotan los años —, el HGB es un título registrado y certificado de clase freehold: se puede vender, heredar, hipotecar y renovar (30 años, prorrogables 20 + 30). Es la forma más segura y más líquida que tiene un inversor extranjero de tener inmueble en Bali.",
    id: "Kami berfokus pada <b>Freehold HGB</b> (Hak Guna Bangunan), yaitu hak untuk mendirikan bangunan yang dipegang melalui perusahaan PT&nbsp;PMA. Berbeda dengan leasehold — yang hanya hak sewa untuk jangka waktu tertentu dan nilainya menyusut seiring berkurangnya sisa tahun — HGB adalah hak yang terdaftar dan bersertifikat: dapat dijual, diwariskan, dijaminkan, dan diperpanjang (30 tahun, lalu dapat diperpanjang 20 + 30). Ini cara paling aman dan paling likuid bagi investor asing untuk memegang properti di Bali."
  },
  "faq.3.q": {
    en: "What does the \"colour\" (zoning) of the land mean?",
    es: "¿Qué significa el «color» (zonificación) del suelo?",
    id: "Apa arti \"warna\" (zonasi) sebidang tanah?"
  },
  "faq.3.a": {
    en: "Indonesia's spatial plan (RDTR) classifies every plot by a <b>colour</b> on the official zoning map: yellow for residential areas, dedicated zones for tourism and commercial use, and <b>green for protected agricultural land where building is prohibited</b>. That colour decides whether a plot can be built on — and whether a PBG can be issued — at all. We only acquire and develop land that is correctly zoned for construction (never green/agricultural), and we verify the zoning before anything else, so your investment is buildable and compliant.",
    es: "El plan de ordenación de Indonesia (RDTR) clasifica cada parcela por un <b>color</b> en el mapa oficial de zonificación: amarillo para zonas residenciales, zonas propias para uso turístico y comercial, y <b>verde para suelo agrícola protegido, donde construir está prohibido</b>. Ese color decide si en una parcela se puede construir — y si puede emitirse un PBG — siquiera. Solo compramos y desarrollamos suelo correctamente calificado para construir (nunca verde/agrícola), y verificamos la calificación antes que nada, para que tu inversión sea edificable y conforme.",
    id: "Rencana tata ruang Indonesia (RDTR) mengklasifikasikan setiap bidang tanah dengan <b>warna</b> pada peta zonasi resmi: kuning untuk kawasan permukiman, zona khusus untuk pariwisata dan komersial, serta <b>hijau untuk lahan pertanian yang dilindungi, tempat mendirikan bangunan dilarang</b>. Warna itulah yang menentukan apakah sebidang tanah boleh dibangun — dan apakah PBG bisa diterbitkan — sama sekali. Kami hanya membeli dan mengembangkan tanah dengan zonasi yang tepat untuk konstruksi (tidak pernah hijau/pertanian), dan kami memeriksa zonasinya sebelum hal lain, agar investasi Anda layak bangun dan sesuai aturan."
  },
  "faq.4.q": {
    en: "Should I invest through a company (PT PMA) or personally?",
    es: "¿Invierto a través de una sociedad (PT PMA) o a título personal?",
    id: "Sebaiknya berinvestasi lewat perusahaan (PT PMA) atau atas nama pribadi?"
  },
  "faq.4.a": {
    en: "There are two routes. A <b>PT&nbsp;PMA</b> — a foreign-owned Indonesian company — is the vehicle that can hold Freehold HGB, operate rentals legally, repatriate income and support your residency (KITAS); it is what we recommend for investors seeking the strongest title and a real return. Investing <b>personally</b> (through leasehold or Hak Pakai with residency) is simpler and cheaper, but weaker in title strength and business use. We set up the right structure for your goals with our notaries and legal partners.",
    es: "Hay dos caminos. Una <b>PT&nbsp;PMA</b> — sociedad indonesia de capital extranjero — es el vehículo que puede ostentar Freehold HGB, explotar alquileres legalmente, repatriar rentas y sostener tu residencia (KITAS); es lo que recomendamos a quien busca el título más fuerte y un retorno real. Invertir <b>a título personal</b> (vía leasehold o Hak Pakai con residencia) es más simple y barato, pero más débil en fuerza del título y en uso empresarial. Montamos la estructura adecuada a tus objetivos con nuestros notarios y socios legales.",
    id: "Ada dua jalur. <b>PT&nbsp;PMA</b> — perusahaan Indonesia bermodal asing — adalah wadah yang dapat memegang Freehold HGB, menjalankan penyewaan secara legal, merepatriasi pendapatan, dan menopang izin tinggal Anda (KITAS); inilah yang kami sarankan bagi investor yang menginginkan hak terkuat dan imbal hasil nyata. Berinvestasi <b>atas nama pribadi</b> (lewat leasehold atau Hak Pakai dengan izin tinggal) lebih sederhana dan lebih murah, tetapi lebih lemah dari sisi kekuatan hak dan penggunaan usaha. Kami menyiapkan struktur yang tepat untuk tujuan Anda bersama notaris dan mitra hukum kami."
  },

  /* ── Pie ───────────────────────────────────────────────────────────────── */
  "ft.tag": {
    en: "Strategic asset investment, structuring and development in Indonesia. Bali · Sumba.",
    es: "Inversión, estructuración y desarrollo de activos estratégicos en Indonesia. Bali · Sumba.",
    id: "Investasi, penataan struktur, dan pengembangan aset strategis di Indonesia. Bali · Sumba."
  },
  "ft.h.portfolio": { en: "Portfolio", es: "Portafolio", id: "Portofolio" },
  "ft.h.company":   { en: "Company",   es: "Compañía",   id: "Perusahaan" },
  "ft.h.divisions": { en: "Divisions", es: "Divisiones", id: "Divisi" },
  "ft.signature":   { en: "Signature", es: "Signature",  id: "Signature" },
  "ft.land":        { en: "Land",      es: "Terrenos",   id: "Tanah" },
  "ft.villas":      { en: "Villas",    es: "Villas",     id: "Villa" },
  "ft.resorts":     { en: "Resorts",   es: "Resorts",    id: "Resort" },
  "ft.soul":        { en: "The Soul",       es: "La Esencia",        id: "Jiwa" },
  "ft.whatwedo":    { en: "What We Do",     es: "Qué hacemos",       id: "Apa yang Kami Lakukan" },
  "ft.expedition":  { en: "The Expedition", es: "La Expedición",     id: "Ekspedisi" },
  "ft.choose":      { en: "Choose your Legacy", es: "Elige tu legado", id: "Pilih Warisan Anda" },
  "ft.terms":       { en: "Terms &amp; Conditions", es: "Términos y Condiciones", id: "Syarat &amp; Ketentuan" },
  "ft.privacy":     { en: "Privacy Policy",  es: "Política de Privacidad", id: "Kebijakan Privasi" },
  "ft.cookies":     { en: "Cookie Settings", es: "Preferencias de cookies", id: "Pengaturan Cookie" },

  /* ── WhatsApp flotante ─────────────────────────────────────────────────── */
  /* El clic al WhatsApp es el evento de conversión de la página. Hasta hoy el
     visitante leía toda la web en su idioma, pulsaba, y el borrador que le
     aparecía estaba en inglés: la ruptura caía justo en el instante de
     convertir, y el comercial que lo recibía no sabía en qué idioma contestar.
     El texto lo LEE el usuario antes de enviarlo, así que se redacta por
     idioma — un bahasa de máquina aquí se nota al instante. */
  "wa.label": {
    en: "Meet Moanito! Your tropical partner",
    es: "¡Este es Moanito! Tu socio tropical",
    id: "Kenalan dengan Moanito! Mitra tropis Anda"
  },
  "wa.aria": {
    en: "Meet Moanito! Your tropical partner — chat on WhatsApp",
    es: "¡Este es Moanito! Tu socio tropical — chatea por WhatsApp",
    id: "Kenalan dengan Moanito! Mitra tropis Anda — mengobrol di WhatsApp"
  },
  "wa.msg": {
    en: "Hello LAWANG 🌿\n\nI'm exploring thoughtfully curated investment opportunities in Bali and would love to learn more about your current projects. ✨",
    es: "Hola LAWANG 🌿\n\nEstoy buscando oportunidades de inversión bien seleccionadas en Bali y me gustaría conocer vuestros proyectos actuales. ✨",
    id: "Halo LAWANG 🌿\n\nSaya sedang mencari peluang investasi pilihan di Bali dan ingin mengetahui lebih lanjut tentang proyek Anda saat ini. ✨"
  }
};
