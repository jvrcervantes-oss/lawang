/* ═══════════════════════════════════════════════════════════════════════════
   Idioma de las LANDINGS de Lawang — /modelo, /dali, /palmfield.  8-sep-2026
   EN / ES / ID.  Depende de `assets/idioma-web.js`.
   ═══════════════════════════════════════════════════════════════════════════

   POR QUÉ NO LLEVA `data-i18n` COMO LA HOME. Las tres landings son PHP con
   valores calculados incrustados por todas partes (precios, modelos, tamaños de
   parcela, tipo de cambio). Meter un atributo por nodo en tres ficheros de 1.000
   a 2.600 líneas es mucha superficie para tocar y cada `<?= ?>` mal cortado es
   una página en blanco. Aquí se traduce por COINCIDENCIA EXACTA del texto
   original: se recorre el árbol y solo se sustituye un nodo de texto cuando su
   contenido completo, normalizado, está literalmente en este diccionario.
     · Lo que no está en el diccionario se queda en inglés. No hay adivinación.
     · No se toca el marcado: es imposible romper la maquetación o el PHP.
     · Un texto con un valor calculado dentro (un precio) no casa nunca y por
       tanto no se toca — que es justo lo que se quiere.

   ⚠️ GLOSARIO QUE NO SE TRADUCE (Legal, revisión previa): freehold, leasehold,
   HGB, hak sewa, hak pakai, PT PMA, PBG, SLF, PLN, EPC, Pariwisata. Ver el
   encabezado de `assets/idioma-web.js` para el porqué completo.

   ⚠️ ADVERTENCIA REGISTRADA (LAW-122). `/dali` y `/palmfield` publican
   «100% Freehold / perpetual title» y «14–18% ROI» por decisión expresa del
   owner, con el hallazgo de Legal delante y por escrito («línea ASIC / ACL s18
   para público australiano»). Este fichero TRADUCE esas frases, no las juzga:
   traducirlas las repite en dos idiomas más, y el español y el bahasa alcanzan
   audiencias distintas de la australiana para la que se aceptó ese riesgo.
   Revertirlo es del owner, igual que LAW-122. */
(function () {
  var T = {

  /* ── Cabecera y cromo, comunes ─────────────────────────────────────────── */
  "Perth & Sydney Desk":            { es: "Mesa Perth y Sídney", id: "Meja Perth & Sydney" },
  "WhatsApp Desk":                  { es: "Mesa WhatsApp", id: "Meja WhatsApp" },
  "Schedule Call":                  { es: "Agendar llamada", id: "Jadwalkan Panggilan" },
  "Book Call":                      { es: "Reservar llamada", id: "Pesan Panggilan" },
  "Book a Call":                    { es: "Reservar una llamada", id: "Pesan Panggilan" },
  "Book a call":                    { es: "Reservar una llamada", id: "Pesan panggilan" },
  "Legal & privacy":                { es: "Aviso legal y privacidad", id: "Legal & privasi" },
  "Cookie preferences":             { es: "Preferencias de cookies", id: "Preferensi cookie" },
  "Instant Estimator":              { es: "Estimador instantáneo", id: "Estimator Instan" },
  "Land Ready Infrastructure":      { es: "Suelo con infraestructura lista", id: "Lahan Siap Infrastruktur" },
  "Bali vs Australia":              { es: "Bali frente a Australia", id: "Bali vs Australia" },
  "The Project":                    { es: "El proyecto", id: "Proyeknya" },
  "Plots & Villas":                 { es: "Parcelas y villas", id: "Kavling & Villa" },

  /* ── Mesa australiana / agenda ─────────────────────────────────────────── */
  "Live Australian Desk":           { es: "Mesa australiana en directo", id: "Meja Australia Langsung" },
  "Active Now":                     { es: "Activa ahora", id: "Aktif Sekarang" },
  "Sydney (AEST) & Perth (AWST) direct sync": { es: "Sincronía directa con Sídney (AEST) y Perth (AWST)", id: "Sinkron langsung Sydney (AEST) & Perth (AWST)" },
  "Sydney (AEST) & Perth (AWST)":   { es: "Sídney (AEST) y Perth (AWST)", id: "Sydney (AEST) & Perth (AWST)" },
  "WITA · Bali":                    { es: "WITA · Bali", id: "WITA · Bali" },
  "Select a day — Mon to Fri":      { es: "Elige un día — de lunes a viernes", id: "Pilih hari — Senin sampai Jumat" },
  "Real times load below":          { es: "Las horas reales se cargan abajo", id: "Jam sebenarnya dimuat di bawah" },
  "Full Name":                      { es: "Nombre y apellidos", id: "Nama Lengkap" },
  "Mobile / WhatsApp":              { es: "Móvil / WhatsApp", id: "Ponsel / WhatsApp" },
  "Email Address (for calendar invite & deed dossier)": { es: "Correo electrónico (para la invitación de calendario y el dossier de escrituras)", id: "Alamat email (untuk undangan kalender & dosir sertifikat)" },
  "Email Address (for calendar invite & plot list)":    { es: "Correo electrónico (para la invitación de calendario y la lista de parcelas)", id: "Alamat email (untuk undangan kalender & daftar kavling)" },
  "Confirm Freehold Strategy Call": { es: "Confirmar llamada de estrategia freehold", id: "Konfirmasi Panggilan Strategi Freehold" },
  "Book Your Palm Field Review":    { es: "Reserva tu revisión de Palm Field", id: "Pesan Tinjauan Palm Field Anda" },
  "No high pressure":               { es: "Sin presión de venta", id: "Tanpa tekanan" },
  "Chat on WhatsApp":               { es: "Chatea por WhatsApp", id: "Mengobrol di WhatsApp" },
  "Australian Investor Desk":       { es: "Mesa del inversor australiano", id: "Meja Investor Australia" },
  "Direct Australian Investor Desk":{ es: "Mesa directa del inversor australiano", id: "Meja Investor Australia Langsung" },
  "Australian Desk":                { es: "Mesa australiana", id: "Meja Australia" },
  "Email:":                         { es: "Correo:", id: "Email:" },
  "WhatsApp Direct:":               { es: "WhatsApp directo:", id: "WhatsApp langsung:" },
  "Direct line:":                   { es: "Línea directa:", id: "Saluran langsung:" },
  "Working Hours Sync:":            { es: "Horario de atención:", id: "Sinkron jam kerja:" },
  "8:00 AM – 7:00 PM AEST / AWST":  { es: "8:00 – 19:00 AEST / AWST", id: "08.00 – 19.00 AEST / AWST" },
  "Office:":                        { es: "Oficina:", id: "Kantor:" },

  /* ── /dali · portada y reclamos ────────────────────────────────────────── */
  /* ⚠️ Los reclamos de titularidad y rentabilidad de este bloque son los de
     LAW-122 (ver cabecera). Se traducen tal cual se publicaron. */
  "100% Freehold (Not 25-Yr Lease)": { es: "100% Freehold (no un lease de 25 años)", id: "100% Freehold (Bukan Sewa 25 Tahun)" },
  "Direct Australian Investor Gate · PMA Custody": { es: "Puerta directa del inversor australiano · Custodia PMA", id: "Gerbang Langsung Investor Australia · Kustodi PMA" },
  "Q4 2026 Release Open":           { es: "Lanzamiento Q4 2026 abierto", id: "Rilis Q4 2026 Dibuka" },
  "Freehold Villas in Bali & Sumba":{ es: "Villas freehold en Bali y Sumba", id: "Villa Freehold di Bali & Sumba" },
  "Fixed price, perpetual title, zero leases. Land prepped with power and water underground before you break ground.": { es: "Precio cerrado, título perpetuo, cero leases. Suelo preparado con luz y agua enterradas antes de que pongas la primera piedra.", id: "Harga tetap, hak perpetual, tanpa sewa. Lahan disiapkan dengan listrik dan air bawah tanah sebelum Anda mulai membangun." },
  "Perpetual Security":             { es: "Seguridad perpetua", id: "Keamanan Perpetual" },
  "100% Freehold Title":            { es: "Título 100% freehold", id: "Hak 100% Freehold" },
  "100% Perpetual Title":           { es: "Título 100% perpetuo", id: "Hak 100% Perpetual" },
  "100% Freehold Included":         { es: "100% freehold incluido", id: "100% Freehold Termasuk" },
  "100% Freehold":                  { es: "100% freehold", id: "100% Freehold" },
  "100% Freehold Bali":             { es: "100% freehold Bali", id: "100% Freehold Bali" },
  "100% Freehold — PMA Foreign Legal Custody": { es: "100% freehold — custodia legal extranjera PMA", id: "100% Freehold — Kustodi Hukum Asing PMA" },
  "Freehold — PMA Foreign Legal Custody": { es: "Freehold — custodia legal extranjera PMA", id: "Freehold — Kustodi Hukum Asing PMA" },
  "100% Freehold perpetual title guarantee": { es: "Garantía de título perpetuo 100% freehold", id: "Jaminan hak perpetual 100% freehold" },
  "Starting Turnkey":               { es: "Llave en mano desde", id: "Mulai Turnkey" },
  "Direct Flight Access":           { es: "Vuelo directo", id: "Akses Penerbangan Langsung" },
  "3.5h Perth / 6h Syd":            { es: "3,5 h Perth / 6 h Sídney", id: "3,5 jam Perth / 6 jam Sydney" },
  "Featured Design":                { es: "Diseño destacado", id: "Desain Unggulan" },
  "Villa Dali Pavilion with Sukabumi Pool": { es: "Villa Dali Pavilion con piscina de Sukabumi", id: "Villa Dali Pavilion dengan Kolam Sukabumi" },
  "Freehold deed + fixed EPC contract included": { es: "Escritura freehold + contrato EPC cerrado incluidos", id: "Sertifikat freehold + kontrak EPC harga tetap termasuk" },
  "Warm Linen & Teak":              { es: "Lino cálido y teca", id: "Linen Hangat & Jati" },
  "Bali West Coast":                { es: "Costa oeste de Bali", id: "Pantai Barat Bali" },
  "Freehold Direct":                { es: "Freehold directo", id: "Freehold Langsung" },
  "Freehold":                       { es: "Freehold", id: "Freehold" },
  "Freehold (HGB)":                 { es: "Freehold (HGB)", id: "Freehold (HGB)" },
  "Freehold · HGB":                 { es: "Freehold · HGB", id: "Freehold · HGB" },
  "HGB":                            { es: "HGB", id: "HGB" },
  "Tenure":                         { es: "Régimen", id: "Status hak" },

  /* ── Calculadora / configurador ────────────────────────────────────────── */
  "5-Step":                         { es: "5 pasos", id: "5 Langkah" },
  "3-Step":                         { es: "3 pasos", id: "3 Langkah" },
  "Instant Accurate Baseline":      { es: "Punto de partida exacto al instante", id: "Dasar Akurat Seketika" },
  "Five questions, and you'll have an exact figure": { es: "Cinco preguntas y tendrás una cifra exacta", id: "Lima pertanyaan, dan Anda dapat angka pastinya" },
  "Five questions, and you'll have a figure": { es: "Cinco preguntas y tendrás una cifra", id: "Lima pertanyaan, dan Anda dapat angkanya" },
  "Three questions. Your figure.":  { es: "Tres preguntas. Tu cifra.", id: "Tiga pertanyaan. Angka Anda." },
  "Pick an option and it moves on":  { es: "Elige una opción y avanza solo", id: "Pilih satu opsi dan lanjut sendiri" },
  "Step 1 of 5":                    { es: "Paso 1 de 5", id: "Langkah 1 dari 5" },
  "Step 1 of 3":                    { es: "Paso 1 de 3", id: "Langkah 1 dari 3" },
  "AUD ($)":                        { es: "AUD ($)", id: "AUD ($)" },
  "EUR (€)":                        { es: "EUR (€)", id: "EUR (€)" },
  "Which villa?":                   { es: "¿Qué villa?", id: "Villa yang mana?" },
  "Which villa":                    { es: "Qué villa", id: "Villa yang mana" },
  "Which roof?":                    { es: "¿Qué techo?", id: "Atap yang mana?" },
  "Which roof":                     { es: "Qué techo", id: "Atap yang mana" },
  "Which island?":                  { es: "¿Qué isla?", id: "Pulau yang mana?" },
  "Which view?":                    { es: "¿Qué vista?", id: "Pemandangan yang mana?" },
  "And which view?":                { es: "¿Y qué vista?", id: "Dan pemandangan yang mana?" },
  "How much land?":                 { es: "¿Cuánto suelo?", id: "Berapa luas tanahnya?" },
  "How much land are you after?":   { es: "¿Cuánto suelo buscas?", id: "Berapa luas tanah yang Anda cari?" },
  "Any extras?":                    { es: "¿Algún extra?", id: "Ada tambahan?" },
  "Anything else?":                 { es: "¿Algo más?", id: "Ada lagi?" },
  "Another size":                   { es: "Otro tamaño", id: "Ukuran lain" },
  "Identical German-grade engineering, sukabumi pool and ironwood decking standard across all models.": { es: "Misma ingeniería de estándar alemán, piscina de sukabumi y tarima de madera de hierro de serie en todos los modelos.", id: "Rekayasa berstandar Jerman yang sama, kolam sukabumi, dan dek kayu ulin standar di semua model." },
  "Two complete villa prices, not an add-on: the roof you choose is the price of the villa.": { es: "Dos precios completos de villa, no un suplemento: el techo que elijas es el precio de la villa.", id: "Dua harga villa yang lengkap, bukan tambahan: atap yang Anda pilih adalah harga villanya." },
  "Land is quoted per square metre and depends on where it sits.": { es: "El suelo se cotiza por metro cuadrado y depende de dónde esté.", id: "Tanah dihitung per meter persegi dan tergantung lokasinya." },
  "The land rate changes with the setting.": { es: "La tarifa del suelo cambia según el entorno.", id: "Tarif tanah berubah menurut lokasinya." },
  "Sizes taken from the plots actually available today.": { es: "Tamaños tomados de las parcelas realmente disponibles hoy.", id: "Ukuran diambil dari kavling yang benar-benar tersedia hari ini." },
  "150–1,500 m². Larger plots are quoted on the call.": { es: "150–1.500 m². Las parcelas mayores se cotizan en la llamada.", id: "150–1.500 m². Kavling yang lebih besar dihitung saat panggilan." },
  "All five models can be built on any Palm Field plot. The price shown is the villa with its cheaper roof; you pick the roof next.": { es: "Los cinco modelos se pueden construir en cualquier parcela de Palm Field. El precio que se muestra es el de la villa con su techo más económico; el techo lo eliges después.", id: "Kelima model dapat dibangun di kavling Palm Field mana pun. Harga yang ditampilkan adalah villa dengan atap termurahnya; atapnya Anda pilih berikutnya." },
  "What each finish adds over the base roof. Both are complete villa prices, not add-ons — the full figure is on the right.": { es: "Lo que suma cada acabado sobre el techo base. Los dos son precios completos de villa, no suplementos: la cifra total está a la derecha.", id: "Apa yang ditambahkan tiap finishing di atas atap dasar. Keduanya harga villa lengkap, bukan tambahan — angka totalnya ada di sebelah kanan." },
  "Optional, and none of them is needed to move in. Tick as many as you want — the figure on the right updates as you go.": { es: "Opcionales, y ninguno hace falta para entrar a vivir. Marca los que quieras: la cifra de la derecha se actualiza sola.", id: "Opsional, dan tidak satu pun diperlukan untuk mulai menempati. Centang sebanyak yang Anda mau — angka di kanan diperbarui otomatis." },
  "Optional, and priced on the call — they're not part of the figure below.": { es: "Opcionales y se cotizan en la llamada: no forman parte de la cifra de abajo.", id: "Opsional dan dihitung saat panggilan — tidak termasuk dalam angka di bawah." },
  "← Back":                         { es: "← Atrás", id: "← Kembali" },
  "Next":                           { es: "Siguiente", id: "Berikutnya" },
  "Next →":                         { es: "Siguiente →", id: "Berikutnya →" },
  "Included":                       { es: "Incluido", id: "Termasuk" },
  "Separate":                       { es: "Aparte", id: "Terpisah" },
  "None selected":                  { es: "Ninguno seleccionado", id: "Belum ada yang dipilih" },
  "Extras":                         { es: "Extras", id: "Tambahan" },
  "Priced on the call":             { es: "Se cotiza en la llamada", id: "Dihitung saat panggilan" },
  "priced on the call":             { es: "se cotiza en la llamada", id: "dihitung saat panggilan" },
  "Subject to availability":        { es: "Sujeto a disponibilidad", id: "Tergantung ketersediaan" },
  "subject to availability":        { es: "sujeto a disponibilidad", id: "tergantung ketersediaan" },
  "— choose one":                   { es: "— elige una", id: "— pilih satu" },

  /* ── /dali · resumen de la estimación ──────────────────────────────────── */
  "Live Estimate Summary":          { es: "Resumen de la estimación en vivo", id: "Ringkasan Estimasi Langsung" },
  "Villa Dali":                     { es: "Villa Dali", id: "Villa Dali" },
  "Sirap Ulin roof":                { es: "Techo Sirap Ulin", id: "Atap Sirap Ulin" },
  "Bali · Cliff":                   { es: "Bali · Acantilado", id: "Bali · Tebing" },
  "Subdivided freehold · power & water": { es: "Freehold segregado · luz y agua", id: "Freehold terpecah · listrik & air" },
  "Civil Infra & Approvals":        { es: "Obra civil y licencias", id: "Infrastruktur Sipil & Perizinan" },
  "Roads, PLN connection, building licences": { es: "Viales, acometida PLN, licencias de obra", id: "Jalan, sambungan PLN, izin bangunan" },
  "Total Freehold Investment":      { es: "Inversión freehold total", id: "Total Investasi Freehold" },
  "Fixed-price written EPC contract. No contractor escalation clauses. Notary, permits and transfer costs are quoted separately.": { es: "Contrato EPC escrito a precio cerrado. Sin cláusulas de revisión del contratista. Notaría, licencias y costes de transmisión se cotizan aparte.", id: "Kontrak EPC tertulis dengan harga tetap. Tanpa klausul kenaikan dari kontraktor. Biaya notaris, izin, dan balik nama dihitung terpisah." },
  "Lock Estimate & Book 30-Min Call": { es: "Fijar estimación y reservar llamada de 30 min", id: "Kunci Estimasi & Pesan Panggilan 30 Menit" },
  "Book a 30-Min Call on This Figure": { es: "Reservar 30 min sobre esta cifra", id: "Pesan Panggilan 30 Menit untuk Angka Ini" },
  "Perth & Sydney working hours · direct sync": { es: "Horario de Perth y Sídney · sincronía directa", id: "Jam kerja Perth & Sydney · sinkron langsung" },
  "Your Palm Field figure":         { es: "Tu cifra de Palm Field", id: "Angka Palm Field Anda" },
  "Your estimate":                  { es: "Tu estimación", id: "Estimasi Anda" },
  "Build your estimate":            { es: "Monta tu estimación", id: "Susun estimasi Anda" },
  "Villa":                          { es: "Villa", id: "Villa" },
  "Turnkey build":                  { es: "Obra llave en mano", id: "Bangun turnkey" },
  "Villa turnkey, your spec":       { es: "Villa llave en mano, a tu gusto", id: "Villa turnkey, sesuai spesifikasi Anda" },
  "Roads & approvals":              { es: "Viales y licencias", id: "Jalan & perizinan" },
  "PBG / SLF licences, PLN connection": { es: "Licencias PBG / SLF, acometida PLN", id: "Izin PBG / SLF, sambungan PLN" },
  "Freehold plot":                  { es: "Parcela freehold", id: "Kavling freehold" },

  /* ── Comparativa Australia ─────────────────────────────────────────────── */
  "Flight & Capital Benchmark":     { es: "Comparativa de vuelo y capital", id: "Tolok Ukur Penerbangan & Modal" },
  "CoreLogic 2024/2025 Data":       { es: "Datos CoreLogic 2024/2025", id: "Data CoreLogic 2024/2025" },
  "CoreLogic 2024/25":              { es: "CoreLogic 2024/25", id: "CoreLogic 2024/25" },
  "Closer than Sydney to Perth — at a Fraction of the Property Price": { es: "Más cerca que Sídney de Perth — por una fracción del precio de la vivienda", id: "Lebih dekat daripada Sydney ke Perth — dengan harga properti jauh lebih rendah" },
  "Closer than Perth. A fraction of the price.": { es: "Más cerca que Perth. Por una fracción del precio.", id: "Lebih dekat daripada Perth. Sebagian kecil dari harganya." },
  "Direct flight times from key Australian capitals and average median house price compared to a turnkey freehold villa in Bali & Sumba (AUD).": { es: "Tiempos de vuelo directo desde las principales capitales australianas y precio medio de la vivienda comparado con una villa freehold llave en mano en Bali y Sumba (AUD).", id: "Waktu penerbangan langsung dari kota-kota besar Australia dan harga rumah median rata-rata dibandingkan villa freehold turnkey di Bali & Sumba (AUD)." },
  "Zero Jetlag from WA":            { es: "Cero jet lag desde Australia Occidental", id: "Tanpa Jetlag dari WA" },
  "Perth: 0h diff · 3h 40m flight": { es: "Perth: 0 h de diferencia · 3 h 40 min de vuelo", id: "Perth: beda 0 jam · terbang 3 jam 40 menit" },
  "Entry Capital Efficiency":       { es: "Eficiencia del capital de entrada", id: "Efisiensi Modal Awal" },
  "Up to 14x less capital":         { es: "Hasta 14 veces menos capital", id: "Hingga 14x lebih sedikit modal" },
  "Rental Yield Spread":            { es: "Diferencial de rentabilidad por alquiler", id: "Selisih Imbal Hasil Sewa" },
  "14 – 18% ROI (vs ~3% AU)":       { es: "14 – 18% ROI (frente a ~3% en Australia)", id: "ROI 14 – 18% (vs ~3% AU)" },
  "Australian City":                { es: "Ciudad australiana", id: "Kota Australia" },
  "Direct Flight Time":             { es: "Tiempo de vuelo directo", id: "Waktu Penerbangan Langsung" },
  "AU Median House":                { es: "Vivienda media en Australia", id: "Rumah Median AU" },
  "Lawang Turnkey Freehold":        { es: "Lawang freehold llave en mano", id: "Lawang Turnkey Freehold" },
  "Palm Field Turnkey Freehold":    { es: "Palm Field freehold llave en mano", id: "Palm Field Turnkey Freehold" },
  "Capital Multiple":               { es: "Múltiplo de capital", id: "Kelipatan Modal" },
  "Lock Strategy Slot":             { es: "Reservar hueco de estrategia", id: "Kunci Slot Strategi" },
  "Select Strategy Slot ↑":         { es: "Elige hueco de estrategia ↑", id: "Pilih Slot Strategi ↑" },
  "Book Your Review ↑":             { es: "Reserva tu revisión ↑", id: "Pesan Tinjauan Anda ↑" },

  /* ── Los 4 pasos de infraestructura ────────────────────────────────────── */
  "Zero Bureaucratic Risk":         { es: "Cero riesgo burocrático", id: "Tanpa Risiko Birokrasi" },
  "We Buy The Land, Subdivide, Pipe Utilities & Clear Permits. You Own It Freehold.": { es: "Compramos el suelo, lo segregamos, metemos servicios y sacamos las licencias. Tú lo tienes en freehold.", id: "Kami membeli tanahnya, memecahnya, memasang utilitas, dan mengurus izinnya. Anda memilikinya secara freehold." },
  "We do the land. You own it freehold.": { es: "Nosotros hacemos el suelo. Tú lo tienes en freehold.", id: "Kami yang mengerjakan tanahnya. Anda memilikinya secara freehold." },
  "Australian investors never deal with village negotiations or missing electric poles. Groundbreaking within 14 days of contract.": { es: "El inversor australiano no negocia con el pueblo ni persigue postes de luz que faltan. Primera piedra en 14 días desde la firma.", id: "Investor Australia tidak pernah berurusan dengan negosiasi desa atau tiang listrik yang belum ada. Pembangunan dimulai dalam 14 hari sejak kontrak." },
  "01 · Title Deed":                { es: "01 · Escritura", id: "01 · Sertifikat" },
  "Clean Freehold Acquisition":     { es: "Adquisición freehold limpia", id: "Akuisisi Freehold Bersih" },
  "Purchased outright with clean notary titles. Legally subdivided and ready for direct transfer under registered PMA legal custody.": { es: "Comprado en firme con títulos notariales limpios. Segregado legalmente y listo para transmisión directa bajo custodia legal de una PMA registrada.", id: "Dibeli lunas dengan sertifikat notaris yang bersih. Dipecah secara legal dan siap dialihkan langsung di bawah kustodi hukum PMA terdaftar." },
  "Bought outright, clean notary titles, subdivided and ready to transfer under PMA custody.": { es: "Comprado en firme, títulos notariales limpios, segregado y listo para transmitir bajo custodia PMA.", id: "Dibeli lunas, sertifikat notaris bersih, dipecah dan siap dialihkan di bawah kustodi PMA." },
  "02 · Utilities":                 { es: "02 · Servicios", id: "02 · Utilitas" },
  "Underground Power & Water":      { es: "Luz y agua enterradas", id: "Listrik & Air Bawah Tanah" },
  "Subterranean PLN electricity conduits — no overhead wires spoiling sunset views — deep potable well connections, and high-capacity soakaways.": { es: "Canalizaciones eléctricas PLN enterradas — sin cables aéreos estropeando la puesta de sol —, pozos profundos de agua potable y drenajes de alta capacidad.", id: "Saluran listrik PLN di bawah tanah — tanpa kabel udara yang merusak pemandangan matahari terbenam — sambungan sumur air minum dalam, dan sumur resapan berkapasitas besar." },
  "PLN power underground — no wires across the view — plus deep potable wells.": { es: "Luz PLN enterrada — sin cables cruzando la vista — más pozos profundos de agua potable.", id: "Listrik PLN di bawah tanah — tanpa kabel melintang di pemandangan — plus sumur air minum dalam." },
  "PLN 3,500W+ Active":             { es: "PLN 3.500 W+ activo", id: "PLN 3.500W+ Aktif" },
  "03 · Civil Works":               { es: "03 · Obra civil", id: "03 · Pekerjaan Sipil" },
  "Paved Access Roads":             { es: "Viales de acceso asfaltados", id: "Jalan Akses Beraspal" },
  "Full topographic grading, cliffside retaining walls, stormwater drainage, and 5-metre wide paved access roads right up to your parcel.": { es: "Explanación topográfica completa, muros de contención en el acantilado, drenaje de pluviales y viales asfaltados de 5 metros hasta tu parcela.", id: "Perataan topografi menyeluruh, dinding penahan di sisi tebing, drainase air hujan, dan jalan akses beraspal selebar 5 meter sampai ke kavling Anda." },
  "Grading, retaining walls, drainage and paved road up to your parcel.": { es: "Explanación, muros de contención, drenaje y vial asfaltado hasta tu parcela.", id: "Perataan, dinding penahan, drainase, dan jalan beraspal sampai ke kavling Anda." },
  "Direct Heavy Vehicle Access":    { es: "Acceso directo de vehículo pesado", id: "Akses Langsung Kendaraan Berat" },
  "04 · Legal Approvals":           { es: "04 · Licencias", id: "04 · Persetujuan Hukum" },
  "PBG & SLF Building Licences":    { es: "Licencias de obra PBG y SLF", id: "Izin Bangunan PBG & SLF" },
  "Pre-approved municipal construction licences and commercial tourism zoning (Pariwisata / Komersial) for 100% legal short-term rental revenue.": { es: "Licencias municipales de obra ya aprobadas y calificación turístico-comercial (Pariwisata / Komersial) para ingresos de alquiler de corta estancia 100% legales.", id: "Izin konstruksi kota yang sudah disetujui dan zonasi pariwisata komersial (Pariwisata / Komersial) untuk pendapatan sewa jangka pendek yang 100% legal." },
  "Municipal building licences and Pariwisata tourism zoning, already approved.": { es: "Licencias municipales de obra y calificación turística Pariwisata, ya aprobadas.", id: "Izin bangunan kota dan zonasi pariwisata Pariwisata, sudah disetujui." },
  "Airbnb & Booking Ready":         { es: "Listo para Airbnb y Booking", id: "Siap untuk Airbnb & Booking" },

  /* ── Cierre ────────────────────────────────────────────────────────────── */
  "Ready to Review Freehold Coordinates & Pricing?": { es: "¿Listo para ver coordenadas freehold y precios?", id: "Siap Meninjau Koordinat Freehold & Harganya?" },
  "Ready to see your plot?":        { es: "¿Listo para ver tu parcela?", id: "Siap melihat kavling Anda?" },
  "In 30 minutes, our desk will walk you through available surveyed freehold coordinates, notary deed proofs, infrastructure videos, and exact fixed turnkey costs in AUD.": { es: "En 30 minutos te enseñamos las coordenadas freehold levantadas y disponibles, las pruebas de escritura notarial, los vídeos de infraestructura y el coste llave en mano exacto y cerrado en AUD.", id: "Dalam 30 menit, tim kami memandu Anda melihat koordinat freehold hasil survei yang tersedia, bukti sertifikat notaris, video infrastruktur, dan biaya turnkey tetap yang pasti dalam AUD." },
  "Thirty minutes: the plots still free, the notary deeds, drone footage of the site today, and your fixed turnkey cost in AUD.": { es: "Treinta minutos: las parcelas que siguen libres, las escrituras notariales, imágenes de dron del sitio hoy y tu coste llave en mano cerrado en AUD.", id: "Tiga puluh menit: kavling yang masih tersedia, sertifikat notaris, rekaman drone lokasi hari ini, dan biaya turnkey tetap Anda dalam AUD." },
  "Guaranteed fixed-price written EPC contract": { es: "Contrato EPC escrito a precio cerrado garantizado", id: "Kontrak EPC tertulis dengan harga tetap terjamin" },
  "Freehold title, transferred to you": { es: "Título freehold, transmitido a tu nombre", id: "Hak freehold, dialihkan kepada Anda" },
  "Turnkey EPC Standard":           { es: "Estándar EPC llave en mano", id: "Standar EPC Turnkey" },
  "Every project operates under guaranteed fixed-price written agreements with progress audits at each construction milestone.": { es: "Todo proyecto opera con contratos escritos a precio cerrado garantizado y auditorías de avance en cada hito de obra.", id: "Setiap proyek berjalan dengan perjanjian tertulis harga tetap terjamin dan audit kemajuan di setiap tahap konstruksi." },
  "Clean Deeds":                    { es: "Escrituras limpias", id: "Sertifikat Bersih" },
  "© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). 100% foreign freehold ownership via registered PMA structure.": { es: "© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Propiedad freehold 100% extranjera mediante estructura PMA registrada.", id: "© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Kepemilikan freehold asing 100% melalui struktur PMA terdaftar." },
  "© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Foreign freehold ownership via registered PMA structure.": { es: "© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Propiedad freehold extranjera mediante estructura PMA registrada.", id: "© 2026 Lawang Tropical Properties (PT Tepi Sun Gai). Kepemilikan freehold asing melalui struktur PMA terdaftar." },

  /* ── /palmfield ────────────────────────────────────────────────────────── */
  "Palm Field":                     { es: "Palm Field", id: "Palm Field" },
  "What could you own in Bali for the price of a Perth deposit?": { es: "¿Qué podrías tener en Bali por lo que cuesta la entrada de un piso en Perth?", id: "Apa yang bisa Anda miliki di Bali dengan harga uang muka rumah di Perth?" },
  "Palm Field starts at":           { es: "Palm Field desde", id: "Palm Field mulai dari" },
  "See Your Figure":                { es: "Ver tu cifra", id: "Lihat Angka Anda" },
  "Plot + villa from":              { es: "Parcela + villa desde", id: "Kavling + villa mulai" },
  "Handover":                       { es: "Entrega", id: "Serah terima" },
  "Masterplan · visualisation":     { es: "Plan general · infografía", id: "Masterplan · visualisasi" },
  "Palm Field, Balian Hills":       { es: "Palm Field, Balian Hills", id: "Palm Field, Balian Hills" },
  "Private pool villas between the river and the rice terraces": { es: "Villas con piscina privada entre el río y las terrazas de arroz", id: "Villa berkolam pribadi di antara sungai dan terasering sawah" },
  "The land, already worked":       { es: "El suelo, ya trabajado", id: "Tanahnya, sudah digarap" },
  "Site photo · terracing and retaining walls": { es: "Foto de obra · aterrazado y muros de contención", id: "Foto lokasi · terasering dan dinding penahan" },
  "Your own villa":                 { es: "Tu propia villa", id: "Villa milik Anda sendiri" },
  "Render · Palm Field":            { es: "Render · Palm Field", id: "Render · Palm Field" },
  "Palm Field · villa turnkey":     { es: "Palm Field · villa llave en mano", id: "Palm Field · villa turnkey" },

  /* ── /modelo ───────────────────────────────────────────────────────────── */
  "The range":                      { es: "La gama", id: "Rangkaian model" },
  "Roof":                           { es: "Techo", id: "Atap" },
  "Roof finish":                    { es: "Acabado del techo", id: "Finishing atap" },
  "WhatsApp":                       { es: "WhatsApp", id: "WhatsApp" },
  "Bali, Indonesia — New build, turnkey": { es: "Bali, Indonesia — Obra nueva, llave en mano", id: "Bali, Indonesia — Bangunan baru, turnkey" },
  "From":                           { es: "Desde", id: "Mulai" },
  "View gallery":                   { es: "Ver galería", id: "Lihat galeri" },
  "Renders in progress":            { es: "Renders en preparación", id: "Render sedang dikerjakan" },
  "Reserve before they exist — the roof price is confirmed by the developer today.": { es: "Resérvala antes de que exista — el precio del techo lo confirma hoy la promotora.", id: "Pesan sebelum wujudnya ada — harga atap dikonfirmasi oleh pengembang hari ini." },
  "Size":                           { es: "Tamaño", id: "Ukuran" },
  "Layout":                         { es: "Distribución", id: "Denah" },
  "Pool":                           { es: "Piscina", id: "Kolam renang" },
  "Price":                          { es: "Precio", id: "Harga" },
  "Nothing here is a quote. It's the same figure we'd start from on the call, so you arrive knowing the ballpark.": { es: "Nada de esto es un presupuesto. Es la misma cifra de la que partiríamos en la llamada, para que llegues sabiendo el orden de magnitud.", id: "Tidak ada di sini yang merupakan penawaran resmi. Ini angka yang sama yang akan kami pakai sebagai titik awal saat panggilan, agar Anda datang sudah tahu kisarannya." },
  "Indicative only — not a quote":  { es: "Solo orientativo — no es un presupuesto", id: "Hanya indikatif — bukan penawaran resmi" },
  "Same construction system and roof choice across the range — only the size changes the price.": { es: "Mismo sistema constructivo y misma elección de techo en toda la gama: solo el tamaño cambia el precio.", id: "Sistem konstruksi dan pilihan atap yang sama di seluruh rangkaian — hanya ukurannya yang mengubah harga." },
  "Same construction system and roof choice across the range — only the size changes the price. Pick a model to configure it below, or come back to this later.": { es: "Mismo sistema constructivo y misma elección de techo en toda la gama: solo el tamaño cambia el precio. Elige un modelo para configurarlo abajo, o vuelve a esto más tarde.", id: "Sistem konstruksi dan pilihan atap yang sama di seluruh rangkaian — hanya ukurannya yang mengubah harga. Pilih satu model untuk dikonfigurasi di bawah, atau kembali ke sini nanti." },
  "— this page":                    { es: "— esta página", id: "— halaman ini" },
  "The rest of the villa doesn't vary between the two. It's the only thing that changes the price.": { es: "El resto de la villa no varía entre las dos. Es lo único que cambia el precio.", id: "Sisa villanya tidak berbeda di antara keduanya. Hanya itu yang mengubah harga." },
  "The rest of the villa doesn't vary between the two roof options. Pick one and the estimate below updates.": { es: "El resto de la villa no varía entre las dos opciones de techo. Elige una y la estimación de abajo se actualiza.", id: "Sisa villanya tidak berbeda di antara dua pilihan atap. Pilih satu dan estimasi di bawah akan diperbarui." },
  "Where":                          { es: "Dónde", id: "Di mana" },
  "Where do you want it built?":    { es: "¿Dónde quieres construirla?", id: "Di mana Anda ingin membangunnya?" },
  "The plot rate depends on the location. We confirm real availability on the call.": { es: "La tarifa de la parcela depende de la ubicación. La disponibilidad real la confirmamos en la llamada.", id: "Tarif kavling tergantung lokasi. Ketersediaan sebenarnya kami konfirmasi saat panggilan." },
  "The plot rate depends on the location. Nothing here is a quote — we confirm real availability and exact pricing on the call.": { es: "La tarifa de la parcela depende de la ubicación. Nada de esto es un presupuesto: la disponibilidad real y el precio exacto los confirmamos en la llamada.", id: "Tarif kavling tergantung lokasi. Tidak ada di sini yang merupakan penawaran resmi — ketersediaan dan harga pastinya kami konfirmasi saat panggilan." },
  "Island":                         { es: "Isla", id: "Pulau" },
  "View":                           { es: "Vista", id: "Pemandangan" },
  "Plot size":                      { es: "Tamaño de parcela", id: "Ukuran kavling" },
  "These are the sizes that actually come up in our plot catalog. Pick the closest — the exact plot is confirmed on the call.": { es: "Estos son los tamaños que de verdad aparecen en nuestro catálogo de parcelas. Elige el más próximo: la parcela exacta se confirma en la llamada.", id: "Ini ukuran-ukuran yang benar-benar ada di katalog kavling kami. Pilih yang paling mendekati — kavling pastinya dikonfirmasi saat panggilan." },
  "Sizes below are the ones that actually come up in our plot catalog. Pick the closest — the exact plot is confirmed on the call.": { es: "Los tamaños de abajo son los que de verdad aparecen en nuestro catálogo de parcelas. Elige el más próximo: la parcela exacta se confirma en la llamada.", id: "Ukuran di bawah adalah yang benar-benar ada di katalog kavling kami. Pilih yang paling mendekati — kavling pastinya dikonfirmasi saat panggilan." },
  "Step 1 — The range":             { es: "Paso 1 — La gama", id: "Langkah 1 — Rangkaian model" },
  "Step 2 — Roof":                  { es: "Paso 2 — Techo", id: "Langkah 2 — Atap" },
  "Step 3 — Island & view":         { es: "Paso 3 — Isla y vista", id: "Langkah 3 — Pulau & pemandangan" },
  "Step 4 — Plot size & extras":    { es: "Paso 4 — Tamaño de parcela y extras", id: "Langkah 4 — Ukuran kavling & tambahan" },
  "Five models, one build system":  { es: "Cinco modelos, un sistema constructivo", id: "Lima model, satu sistem bangun" },
  "Villa price only, roof included. Plot priced separately — build your estimate below.": { es: "Solo el precio de la villa, techo incluido. La parcela se cotiza aparte — monta tu estimación abajo.", id: "Hanya harga villa, atap termasuk. Kavling dihitung terpisah — susun estimasi Anda di bawah." },
  "The roof is the only thing that changes the price": { es: "El techo es lo único que cambia el precio", id: "Atap adalah satu-satunya yang mengubah harga" },
  "Prices shown are valid through 31 December 2026 (Bali time). Villa prices rise on 1 January 2027 — plot rates are unaffected.": { es: "Los precios mostrados son válidos hasta el 31 de diciembre de 2026 (hora de Bali). El precio de las villas sube el 1 de enero de 2027 — las tarifas de parcela no cambian.", id: "Harga yang ditampilkan berlaku sampai 31 Desember 2026 (waktu Bali). Harga villa naik pada 1 Januari 2027 — tarif kavling tidak berubah." },
  "Villa prices are confirmed directly by the developer and include Indonesian VAT (PPN). Notary, permit and transfer costs are separate and are all detailed in writing before you sign.": { es: "Los precios de villa los confirma directamente la promotora e incluyen el IVA indonesio (PPN). Notaría, licencias y costes de transmisión van aparte y se detallan por escrito antes de firmar.", id: "Harga villa dikonfirmasi langsung oleh pengembang dan sudah termasuk PPN. Biaya notaris, izin, dan balik nama terpisah dan seluruhnya dirinci tertulis sebelum Anda menandatangani." },
  "From here on, this page describes": { es: "A partir de aquí, esta página describe", id: "Mulai dari sini, halaman ini menjelaskan" },
  "— switch models above to compare price and specs.": { es: "— cambia de modelo arriba para comparar precio y especificaciones.", id: "— ganti model di atas untuk membandingkan harga dan spesifikasi." },

  /* ── /modelo · las 35 cadenas que ya vivian dentro de `lw_i18n($es,$en)` ───
     El ESPAÑOL de este bloque NO se ha reescrito: es el que el estudio ya tenia
     escrito en `modelo/index.php`, del toggle ES/EN que se retiro el 2-sep. Se
     recupera tal cual en vez de traducir de nuevo el ingles, que habria dado otra
     voz para las mismas frases. `lw_i18n` sigue devolviendo ingles en servidor y
     esta capa lo cambia en cliente. */
  "Location": { es: "Ubicación", id: "Lokasi" },
  "FAQ": { es: "Preguntas", id: "FAQ" },
  "Book a call": { es: "Agendar llamada", id: "Pesan panggilan" },
  "Scope of works — what's included": { es: "Alcance de obra — Qué incluye el precio", id: "Lingkup pekerjaan — apa yang termasuk" },
  "Included": { es: "Incluido", id: "Termasuk" },
  "Not included": { es: "No incluido", id: "Tidak termasuk" },
  "The villa price includes Indonesian VAT (PPN). The plot and the closing costs on the purchase (transfer tax, notary, permits) are quoted separately and detailed in writing before signing.": { es: "El precio de la villa incluye el IVA indonesio (PPN). La parcela y los gastos de compraventa (impuesto de transmisión, notaría y licencias) se presupuestan aparte y se detallan por escrito antes de firmar.", id: "Harga villa sudah termasuk PPN. Kavling dan biaya penutupan pembelian (bea balik nama, notaris, izin) dihitung terpisah dan dirinci tertulis sebelum penandatanganan." },
  "The site": { es: "El sitio", id: "Lokasinya" },
  "You choose the plot": { es: "Tú eliges la parcela", id: "Anda yang memilih kavlingnya" },
  "The model is built on the plot you choose from our catalog on Bali's west coast. On the call, we'll tell you which plots are available and how to reach each one.": { es: "El modelo se levanta sobre la parcela que elijas de nuestro catálogo en la costa oeste de Bali. En la llamada te decimos qué parcelas quedan y cómo se llega a cada una.", id: "Model ini dibangun di kavling yang Anda pilih dari katalog kami di pantai barat Bali. Saat panggilan, kami akan memberi tahu kavling mana yang tersedia dan bagaimana mencapainya." },
  "Plot": { es: "Parcela", id: "Kavling" },
  "Chosen from the catalog": { es: "A elegir del catálogo", id: "Dipilih dari katalog" },
  "Area": { es: "Zona", id: "Kawasan" },
  "Bali's west coast": { es: "Costa oeste de Bali", id: "Pantai barat Bali" },
  "Title": { es: "Régimen", id: "Status hak" },
  "Reviewed per plot": { es: "Se revisa por parcela", id: "Ditinjau per kavling" },
  "Real drone photograph · Bali's west coast": { es: "Fotografía real con dron · Costa oeste de Bali", id: "Foto drone asli · pantai barat Bali" },
  "How it's purchased": { es: "Cómo se compra", id: "Cara pembeliannya" },
  "Call": { es: "Llamada", id: "Panggilan" },
  "Half an hour to see which plot fits, with what budget and timeline.": { es: "Media hora para ver qué parcela encaja, con qué presupuesto y en qué plazos.", id: "Setengah jam untuk melihat kavling mana yang cocok, dengan anggaran dan jangka waktu berapa." },
  "Budget & plot": { es: "Presupuesto y parcela", id: "Anggaran & kavling" },
  "Fixed price for the chosen finish, a specific plot, and a payment schedule.": { es: "Precio cerrado del acabado elegido, parcela concreta y calendario de pagos.", id: "Harga tetap untuk finishing yang dipilih, kavling tertentu, dan jadwal pembayaran." },
  "Reservation & construction": { es: "Reserva y obra", id: "Reservasi & konstruksi" },
  "Reservation contract, then the sale (PPJB) and construction contracts, and construction begins.": { es: "Contrato de reserva, después el PPJB de compraventa y el contrato de construcción, y arranca la obra.", id: "Kontrak reservasi, lalu PPJB jual beli dan kontrak konstruksi, dan pembangunan dimulai." },
  "Frequently asked questions": { es: "Preguntas frecuentes", id: "Pertanyaan yang sering diajukan" },
  "What exactly am I buying, and under what title?": { es: "¿Qué compro exactamente y en qué régimen?", id: "Apa persisnya yang saya beli, dan dengan status hak apa?" },
  "What's included in the price?": { es: "¿Qué incluye el precio?", id: "Apa saja yang termasuk dalam harga?" },
  "Can I choose where it gets built?": { es: "¿Puedo elegir dónde se construye?", id: "Bisakah saya memilih lokasi pembangunannya?" },
  "What currency is the contract in?": { es: "¿En qué moneda se firma?", id: "Kontraknya dalam mata uang apa?" },
  "How is the purchase formalized?": { es: "¿Cómo se formaliza la compra?", id: "Bagaimana pembelian diresmikan?" },
  "Who builds it?": { es: "¿Quién construye?", id: "Siapa yang membangunnya?" },
  "Next step": { es: "Siguiente paso", id: "Langkah berikutnya" },
  "Book your call": { es: "Reserva tu llamada", id: "Pesan panggilan Anda" },
  "Half an hour. We'll give you a fixed quote for the finish you're interested in and the available plots it can be built on.": { es: "Media hora. Te damos el presupuesto cerrado del acabado que te interese y las parcelas disponibles donde puede construirse.", id: "Setengah jam. Kami akan memberi Anda penawaran harga tetap untuk finishing yang Anda minati dan kavling yang tersedia untuk membangunnya." },
  "See available times": { es: "Ver horarios disponibles", id: "Lihat jadwal yang tersedia" },
  "About the model":                { es: "Sobre el modelo", id: "Tentang model ini" },

  /* ── Cazadas VERIFICANDO EN PRODUCCIÓN, no escribiendo el diccionario ─────
     Estas no salieron del volcado inicial de cadenas porque el volcado descartaba
     todo nodo que tuviera PHP dentro, y estas conviven con precios en el mismo
     bloque. Aparecieron al recorrer el DOM ya renderizado de las tres landings en
     vivo y buscar qué seguía en inglés con la página en español. Vale la pena
     anotarlo: leer el fichero fuente no bastaba. */
  "Indicative rate per m². Not a quote for a specific plot.": {
    es: "Tarifa orientativa por m². No es un presupuesto de una parcela concreta.",
    id: "Tarif indikatif per m². Bukan penawaran untuk kavling tertentu." },
  "Notary, permits and transfer costs": {
    es: "Notaría, licencias y gastos de transmisión",
    id: "Notaris, izin, dan biaya balik nama" },
  "Excludes notary, permits and transfer costs.": {
    es: "No incluye notaría, licencias ni gastos de transmisión.",
    id: "Belum termasuk notaris, izin, dan biaya balik nama." },
  "Indicative starting figure, villa + plot": {
    es: "Cifra de partida orientativa, villa + parcela",
    id: "Angka awal indikatif, villa + kavling" },
  "Not an offer or a reservation. Your final price depends on the specific plot and is confirmed in writing before you sign.": {
    es: "No es una oferta ni una reserva. El precio final depende de la parcela concreta y se confirma por escrito antes de firmar.",
    id: "Bukan penawaran maupun pemesanan. Harga akhir tergantung kavling yang dipilih dan dikonfirmasi tertulis sebelum Anda menandatangani." },
  "Book a call for the real numbers": {
    es: "Reserva una llamada para los números reales",
    id: "Pesan panggilan untuk angka sebenarnya" },
  "Today's starting figure for this roof. Your final price is confirmed by the developer in writing before you sign. Indonesian VAT (PPN) included.": {
    es: "Cifra de partida de hoy para este techo. El precio final lo confirma la promotora por escrito antes de firmar. IVA indonesio (PPN) incluido.",
    id: "Angka awal hari ini untuk atap ini. Harga akhir dikonfirmasi pengembang secara tertulis sebelum Anda menandatangani. Sudah termasuk PPN." },
  "Lawang Tropical Properties develops turnkey villas in Bali: you choose the plot and the finish, and the budget is locked in writing before you sign anything.": {
    es: "Lawang Tropical Properties desarrolla villas llave en mano en Bali: tú eliges la parcela y el acabado, y el presupuesto queda cerrado por escrito antes de que firmes nada.",
    id: "Lawang Tropical Properties membangun villa turnkey di Bali: Anda memilih kavling dan finishing-nya, dan anggarannya dikunci tertulis sebelum Anda menandatangani apa pun." },
  "The rest of the villa doesn't change between finishes: structure, architecture, and installations stay the same. Only the roof changes with the option you pick.": {
    es: "El resto de la villa no cambia entre acabados: estructura, arquitectura e instalaciones son las mismas. Lo único que cambia con la opción que elijas es el techo.",
    id: "Sisa villanya tidak berubah antar finishing: struktur, arsitektur, dan instalasinya sama. Yang berubah hanya atapnya, sesuai opsi yang Anda pilih." },
  "PT Tepi Sun Gai · Registered Developer & Property Advisory. Developing verified freehold parcels and turnkey architectural villas across Tabanan, Uluwatu and Sumba for Australian investors.": {
    es: "PT Tepi Sun Gai · Promotora registrada y asesoría inmobiliaria. Desarrollamos parcelas freehold verificadas y villas de autor llave en mano en Tabanan, Uluwatu y Sumba para inversores australianos.",
    id: "PT Tepi Sun Gai · Pengembang terdaftar & konsultan properti. Mengembangkan kavling freehold terverifikasi dan villa arsitektural turnkey di Tabanan, Uluwatu, dan Sumba untuk investor Australia." },
  /* ── Los bloques `.i-en` de /modelo — SOLO bahasa ──────────────────────────
     Aqui va `id` y NO `es` a proposito. En español estos nodos ni siquiera se ven:
     su hermano `.i-es`, con el texto que escribio el estudio, es el que se muestra
     (regla de idioma en modelo/index.php). Poner un `es` aqui seria una segunda
     version española del mismo parrafo compitiendo con la buena — dos voces para
     la misma frase, que es justo lo que se evito al recuperar el copy original.
     Sin `es`, el modulo deja el nodo intacto. */
  "The built villa and the right over the plot it stands on. In Indonesia that right doesn't work like Spanish-style ownership, and not every plot sits under the same scheme or term. We review it plot by plot on the call, document in hand, before talking numbers.": {
    id: "Bangunan villanya dan hak atas kavling tempatnya berdiri. Di Indonesia hak itu tidak bekerja seperti kepemilikan penuh ala Eropa, dan tidak semua kavling berada di bawah skema atau jangka waktu yang sama. Kami meninjaunya kavling per kavling saat panggilan, dengan dokumen di tangan, sebelum membicarakan angka." },
  "The full build with the roof finish you choose. The villa price already includes Indonesian VAT (PPN). The plot, and the closing costs on the purchase (transfer tax, notary and permits), are quoted separately and detailed in writing before you sign.": {
    id: "Pembangunan lengkap dengan finishing atap pilihan Anda. Harga villa sudah termasuk PPN. Kavling dan biaya penutupan pembelian (bea balik nama, notaris, dan izin) dihitung terpisah serta dirinci tertulis sebelum Anda menandatangani." },
  "Yes. The model stays the same and is built on the plot you choose from the catalog. The view, orientation, and land price change. Not every plot takes every model — that's confirmed on the call.": {
    id: "Ya. Modelnya tetap sama dan dibangun di kavling yang Anda pilih dari katalog. Yang berubah adalah pemandangan, orientasi, dan harga tanahnya. Tidak semua kavling cocok untuk setiap model — itu dipastikan saat panggilan." },
  "The contract is executed in Indonesian rupiah, as required by Indonesian law for transactions inside the country. Other-currency equivalents are given for reference only, at the exchange rate on the date.": {
    id: "Kontrak dibuat dalam rupiah, sebagaimana diwajibkan hukum Indonesia untuk transaksi di dalam negeri. Nilai setara dalam mata uang lain hanya sebagai rujukan, memakai kurs pada tanggal tersebut." },
  "First a reservation contract on the plot. Then the PPJB — the Indonesian sale contract — and the construction contract. All three are the developer's own documents and are reviewed before signing.": {
    id: "Pertama kontrak reservasi atas kavling. Lalu PPJB — perjanjian jual beli — dan kontrak konstruksi. Ketiganya adalah dokumen pengembang sendiri dan ditinjau sebelum ditandatangani." },
  "Lawang Tropical Properties, through the Indonesian company PT Tepi Sun Gai. On the call we show you delivered projects and the ones underway right now.": {
    id: "Lawang Tropical Properties, melalui perusahaan Indonesia PT Tepi Sun Gai. Saat panggilan kami tunjukkan proyek yang sudah diserahterimakan dan yang sedang berjalan sekarang." },
  "Availability calendar":                { id: "Kalender ketersediaan" },
  "Pick a day and time directly on the calendar.": { id: "Pilih hari dan jam langsung di kalender." },
  "Half an hour, no commitment.":         { id: "Setengah jam, tanpa komitmen." },
  "Monday to Friday. Pick a day and you'll see the times that are actually free.": {
    id: "Senin sampai Jumat. Pilih satu hari dan Anda akan melihat jam yang benar-benar kosong." },
  "© 2026 Lawang Tropical Properties. All rights reserved.": {
    es: "© 2026 Lawang Tropical Properties. Todos los derechos reservados.",
    id: "© 2026 Lawang Tropical Properties. Seluruh hak cipta dilindungi." },

  "PT Tepi Sun Gai · Registered Developer & Property Advisory. Developing verified freehold parcels and turnkey luxury architectural villas across Tabanan, Uluwatu, and Sumba for Australian investors.": {
    es: "PT Tepi Sun Gai · Promotora registrada y asesoría inmobiliaria. Desarrollamos parcelas freehold verificadas y villas de autor de lujo llave en mano en Tabanan, Uluwatu y Sumba para inversores australianos.",
    id: "PT Tepi Sun Gai · Pengembang terdaftar & konsultan properti. Mengembangkan kavling freehold terverifikasi dan villa arsitektural mewah turnkey di Tabanan, Uluwatu, dan Sumba untuk investor Australia." }
  };

  /* ── Frases CON UNA CIFRA DENTRO ───────────────────────────────────────────
     La tabla de arriba casa el texto completo, así que nunca puede tocar una frase
     que lleve incrustado un precio, un tipo de cambio o un tamaño de parcela: el
     servidor los calcula y cada modelo produce una cadena distinta. Medido en
     producción tras el primer despliegue: quedaban 7 en /palmfield, 4 en /dali y
     23 en /modelo, y casi todas eran líneas de precio.
     Aquí se casa por PATRÓN y se conserva el número tal cual viene ($1, $2…). No
     se toca ni una cifra, ni su formato, ni su moneda: solo las palabras
     alrededor. Es la única forma de traducirlas sin volver a calcular nada. */
  var P = [
    { re: /^From (€[\d.,]+)$/,
      es: "Desde $1", id: "Mulai $1" },
    { re: /^from around (€[\d.,]+)$/,
      es: "desde unos $1", id: "sekitar $1" },
    { re: /^Bamboo roof from (€[\d.,]+)$/,
      es: "Techo de bambú desde $1", id: "Atap bambu mulai $1" },
    { re: /^Bamboo & Ulin shingle roof from (€[\d.,]+)$/,
      es: "Techo de bambú y teja Ulin desde $1", id: "Atap bambu & sirap ulin mulai $1" },
    { re: /^Villa — (.+), (.+) roof$/,
      es: "Villa — $1, techo $2", id: "Villa — $1, atap $2" },
    { re: /^Plot — (.+), ([\d.,]+) m² at (€[\d.,]+\/m²)$/,
      es: "Parcela — $1, $2 m² a $3", id: "Kavling — $1, $2 m² seharga $3" },
    { re: /^Villa (\S+) \+ ([\d.,]+) m² plot$/,
      es: "Villa $1 + parcela de $2 m²", id: "Villa $1 + kavling $2 m²" },
    { re: /^Villa (\S+) \+ land included$/,
      es: "Villa $1 + suelo incluido", id: "Villa $1 + tanah termasuk" },
    { re: /^(€[\d.,]+\/m²) · sized on the call$/,
      es: "$1 · el tamaño se cierra en la llamada", id: "$1 · ukuran ditentukan saat panggilan" },
    { re: /^AUD at ([\d.,]+) \((.+?)\) · contract in EUR · plot apart$/,
      es: "AUD a $1 ($2) · el contrato va en EUR · parcela aparte",
      id: "AUD pada kurs $1 ($2) · kontrak dalam EUR · kavling terpisah" },
    { re: /^with the freehold plot included — less than the 20% deposit on a median Perth house \((.+?)\)\.$/,
      es: "con la parcela freehold incluida — menos que la entrada del 20% de una vivienda media en Perth ($1).",
      id: "sudah termasuk kavling freehold — lebih kecil dari uang muka 20% rumah median di Perth ($1)." },
    { re: /^A ([\d]+)-bedroom en-suite villa, built on the plot you choose\. Finish and budget locked in writing before you sign\.$/,
      es: "Una villa de $1 hab. con baño en suite, construida en la parcela que elijas. Acabado y presupuesto cerrados por escrito antes de firmar.",
      id: "Villa dengan $1 kamar tidur en-suite, dibangun di kavling pilihan Anda. Finishing dan anggaran dikunci tertulis sebelum Anda menandatangani." },
    { re: /^Plot rates: beachfront (€[\d.,]+\/m²), all other locations (€[\d.,]+\/m²)\. Indicative rates per m², not a quote for a specific plot\. Sumba plots are subject to availability and confirmed on the call\.$/,
      es: "Tarifas de parcela: primera línea de playa $1, resto de ubicaciones $2. Tarifas orientativas por m², no un presupuesto de una parcela concreta. Las parcelas de Sumba están sujetas a disponibilidad y se confirman en la llamada.",
      id: "Tarif kavling: tepi pantai $1, lokasi lainnya $2. Tarif indikatif per m², bukan penawaran untuk kavling tertentu. Kavling di Sumba tergantung ketersediaan dan dikonfirmasi saat panggilan." },
    { re: /^Select your villa size, roof finish, and land plot\. Prices shown in your currency at a fixed rate of ([\d.,]+) AUD\/EUR \((.+?)\) — the contract figure is the euro one\.$/,
      es: "Elige el tamaño de la villa, el acabado del techo y la parcela. Los precios se muestran en tu moneda a un tipo fijo de $1 AUD/EUR ($2) — la cifra del contrato es la que va en euros.",
      id: "Pilih ukuran villa, finishing atap, dan kavlingnya. Harga ditampilkan dalam mata uang Anda pada kurs tetap $1 AUD/EUR ($2) — angka yang mengikat dalam kontrak adalah yang dalam euro." },
    { re: /^Australian figures: CoreLogic capital city median dwelling, (.+?)\. Palm Field includes the freehold plot \(([\d.,]+) m², smallest available (.+?)\) plus the turnkey build, at ([\d.,]+) AUD\/EUR \((.+?)\)\.$/,
      es: "Cifras australianas: vivienda media de capital según CoreLogic, $1. Palm Field incluye la parcela freehold ($2 m², la más pequeña disponible a $3) más la obra llave en mano, a $4 AUD/EUR ($5).",
      id: "Angka Australia: hunian median ibu kota menurut CoreLogic, $1. Palm Field sudah termasuk kavling freehold ($2 m², terkecil yang tersedia per $3) ditambah pembangunan turnkey, pada kurs $4 AUD/EUR ($5)." }
  ];

  /* Normaliza para comparar: colapsa espacios y saltos de línea. El HTML de estas
     páginas parte frases en varias líneas con sangría, así que el texto del nodo
     trae saltos donde el diccionario tiene un espacio. */
  function norm(s) { return s.replace(/\s+/g, ' ').trim(); }

  /* Lo capturado por un patrón se conserva TAL CUAL — es un número, una fecha o un
     nombre de producto — salvo estas palabras, que son vocabulario y sí se traducen:
     el tipo de vista viaja dentro de «Plot — cliff, 160 m² at €125/m²» y dejarlo en
     inglés partía la frase por la mitad. Los nombres de techo (Sirap, Ulin, Bambú) NO
     entran aquí a propósito: son producto, no descripción. */
  var VOCAB = {
    cliff:     { es: "acantilado",     id: "tebing" },
    beach:     { es: "playa",          id: "pantai" },
    beachfront:{ es: "primera línea",  id: "tepi pantai" },
    jungle:    { es: "selva",          id: "hutan" },
    river:     { es: "río",            id: "sungai" },
    ricefield: { es: "arrozal",        id: "sawah" }
  };

  /* Devuelve la traducción por patrón, o null si ninguno casa. */
  function porPatron(txt, lang) {
    for (var i = 0; i < P.length; i++) {
      var m = P[i].re.exec(txt);
      if (m) {
        return P[i][lang].replace(/\$(\d)/g, function (_, d) {
          var cap = m[+d] || '';
          var v = VOCAB[cap.toLowerCase()];
          return v ? v[lang] : cap;
        });
      }
    }
    return null;
  }

  function traduce(lang) {
    if (lang === 'en') return;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        // Nunca dentro de <script>/<style>: ahí el "texto" es código.
        var p = n.parentNode;
        if (!p) return NodeFilter.FILTER_REJECT;
        var tag = p.nodeName;
        if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'TEXTAREA') return NodeFilter.FILTER_REJECT;
        return n.nodeValue && n.nodeValue.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      }
    });
    var n, pend = [];
    while ((n = walker.nextNode())) pend.push(n);

    for (var i = 0; i < pend.length; i++) {
      var nodo = pend[i];
      var crudo = norm(nodo.nodeValue);
      var e = T[crudo];
      // Primero la tabla exacta, que es la barata; si no casa, los patrones.
      var v = e ? e[lang] : porPatron(crudo, lang);
      if (!v) continue;                       // no está en ninguna -> se queda en inglés
      // Se conserva el espaciado de alrededor para no pegar palabras a un <b> vecino.
      var izq = /^\s*/.exec(nodo.nodeValue)[0];
      var der = /\s*$/.exec(nodo.nodeValue)[0];
      nodo.nodeValue = izq + v + der;
    }

    // Atributos que el usuario ve: marcador de campo y texto alternativo.
    var conAttr = document.querySelectorAll('[placeholder],[aria-label],[title]');
    for (var j = 0; j < conAttr.length; j++) {
      ['placeholder', 'aria-label', 'title'].forEach(function (a) {
        var val = conAttr[j].getAttribute(a);
        if (!val) return;
        var t = T[norm(val)];
        if (t && t[lang]) conAttr[j].setAttribute(a, t[lang]);
      });
    }
  }

  /* El mensaje precargado de WhatsApp. Es el evento de conversión de estas páginas y
     va en inglés duro dentro del PHP, con el arranque «Hi, I'm an Australian investor»
     — que en una página en español o en bahasa no solo está en otro idioma, es que
     además dice algo falso sobre quien escribe. Se reescribe solo el ARRANQUE conocido
     y se respeta la cola, que lleva el nombre del modelo o del proyecto resuelto por
     el servidor y no se debe tocar.
     Se hace aquí y no en el PHP porque el idioma es una elección del navegador: el
     servidor pinta la página sin saberla. */
  var WA_INICIO = [
    { en: "Hi, I'm an Australian investor interested in the ",
      es: "Hola, me interesa ", id: "Halo, saya tertarik dengan " },
    { en: "Hi, I'm an Australian investor interested in Palm Field: ",
      es: "Hola, me interesa Palm Field: ", id: "Halo, saya tertarik dengan Palm Field: " },
    { en: "Hi, I'm an Australian investor interested in Palm Field, Bali.",
      es: "Hola, me interesa Palm Field, en Bali.", id: "Halo, saya tertarik dengan Palm Field, Bali." },
    { en: "Hi, I'm an Australian investor interested in Lawang villas in Bali.",
      es: "Hola, me interesan las villas de Lawang en Bali.", id: "Halo, saya tertarik dengan villa Lawang di Bali." },
    { en: "Hi, I'm interested in the ",
      es: "Hola, me interesa ", id: "Halo, saya tertarik dengan " }
  ];

  function traduceWhatsApp(lang) {
    if (lang === 'en') return;
    var enlaces = document.querySelectorAll('a[href*="wa.me/"]');
    for (var i = 0; i < enlaces.length; i++) {
      var href = enlaces[i].getAttribute('href') || '';
      var corte = href.indexOf('text=');
      if (corte === -1) continue;
      var base = href.slice(0, corte + 5);
      var txt;
      try { txt = decodeURIComponent(href.slice(corte + 5).replace(/\+/g, ' ')); } catch (e) { continue; }
      // El más largo primero: «…interested in Palm Field: » contiene a «…interested in the »
      // como prefijo de nada, pero sí comparte arranque con la variante corta, y coger la
      // corta dejaría media frase inglesa colgando.
      var ordenados = WA_INICIO.slice().sort(function (a, b) { return b.en.length - a.en.length; });
      for (var j = 0; j < ordenados.length; j++) {
        if (txt.indexOf(ordenados[j].en) === 0) {
          txt = ordenados[j][lang] + txt.slice(ordenados[j].en.length);
          enlaces[i].setAttribute('href', base + encodeURIComponent(txt));
          break;
        }
      }
    }
  }

  function arranca() {
    var lang = window.LW_LANG || 'en';
    traduce(lang);
    traduceWhatsApp(lang);

    /* El selector va en `.nav__cta` y NO en `.nav__links`: esa lista se oculta por
       CSS a <=1080px (au-landing) y <=1100px (modelo), o sea que en móvil — que es
       donde aterriza la mayoría del tráfico de pauta — el selector desaparecería.
       Se inyecta desde el módulo compartido en vez de pegarlo en las tres páginas:
       el pendiente UNI-2 ya cuenta 9 menús a mano en la web pública y escribirlo
       aquí tres veces lo dejaría en 12. */
    if (window.lwMontaSelectorIdioma) {
      // Se prueban EN ORDEN, con una llamada por candidato. Un `querySelector` con
      // lista separada por comas NO respeta el orden escrito: devuelve el primero en
      // orden de DOCUMENTO, y como `.nav__right` vive dentro de `.nav__in`, poner los
      // dos en la misma lista habria devuelto siempre `.nav__in` y en /modelo el
      // selector habria caido fuera del grupo de acciones.
      var candidatos = ['.nav__cta', '.nav__right', '.nav__actions', '.nav__in'];
      for (var k = 0; k < candidatos.length; k++) {
        if (document.querySelector(candidatos[k])) {
          window.lwMontaSelectorIdioma(candidatos[k]);
          break;
        }
      }
    }
    document.documentElement.setAttribute('data-i18n-listo', '1');
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca);
  else arranca();
})();
