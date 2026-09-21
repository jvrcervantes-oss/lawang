-- FAQ estándar del investor-deck aplicada a los 28 proyectos que aún no tenían
-- ninguna (Palm Field W5 conserva su set propio, ya revisado por Legal el 9-sep,
-- sin tocar). Decisión del owner, 15-sep: tenencia = Hak Sewa o HGB vía PT PMA
-- propia del comprador (nunca compartida — sería el patrón nominee que LAW-186
-- señaló como riesgo penal bajo la Perda Bali 4/2026), sin comprometer
-- disponibilidad de HGB por parcela (se confirma en due diligence) ni tocar
-- fiscalidad (fuera de alcance, LAW-191). Referencia a LawangRWA retirada de la
-- pregunta "¿es un producto de inversión?" a petición del owner.
-- Inerte hasta que cada proyecto active su deck (deck_proyecto_abierto mira
-- unidades.publicado_investor_deck).

insert into public.deck_faq (proyecto_id, pregunta, respuesta, orden, publicado)
select p.id, v.pregunta, v.respuesta, v.orden, true
from public.proyectos p
cross join (
  values
    (
      0,
      '{"en":"What tenure do I acquire?","es":"¿Qué derecho adquiero?","id":"Hak apa yang saya peroleh?"}'::jsonb,
      '{"en":"Depending on the plot and project, you acquire Hak Sewa (long-term leasehold under Indonesian law, the standard route for foreign investors) or, where applicable, HGB (Hak Guna Bangunan) rights through your own PT PMA — in that case you don''t hold the HGB title personally, but own the Indonesian company that is the registered titleholder. Our team confirms which route applies to your specific plot, and its exact terms, before reservation.","es":"Según la parcela y el proyecto, adquieres Hak Sewa (arrendamiento de largo plazo del derecho indonesio, la vía estándar para inversores extranjeros) o, cuando aplica, un derecho HGB (Hak Guna Bangunan) a través de tu propia PT PMA — en ese caso no adquieres el HGB a tu nombre personal, sino la propiedad de la sociedad indonesia que es la titular registral. Nuestro equipo confirma qué vía aplica a tu parcela concreta y sus condiciones exactas antes de la reserva.","id":"Tergantung kavling dan proyeknya, Anda memperoleh Hak Sewa (leasehold jangka panjang menurut hukum Indonesia, jalur standar bagi investor asing) atau, jika berlaku, hak HGB (Hak Guna Bangunan) melalui PT PMA milik Anda sendiri — dalam hal ini Anda tidak memegang sertifikat HGB atas nama pribadi, melainkan memiliki perusahaan Indonesia yang menjadi pemegang hak terdaftar. Tim kami akan mengonfirmasi jalur mana yang berlaku untuk kavling spesifik Anda, beserta ketentuan pastinya, sebelum pemesanan."}'::jsonb
    ),
    (
      1,
      '{"en":"What does the reservation fee cover?","es":"¿Qué cubre la cuota de reserva?","id":"Apa yang dicakup biaya pemesanan?"}'::jsonb,
      '{"en":"It reserves the selected plot, held in the notary''s escrow account, for the validity period stated in the Letter of Reservation, while you complete due diligence. It is not the deed of sale and does not transfer any right over the land. If you withdraw, or the reservation lapses, the fee is refunded per the terms in the document you receive.","es":"Reserva la parcela elegida, en la cuenta escrow del notario, durante el plazo de validez que indica la Carta de Reserva, mientras completas tu due diligence. No es la escritura de compraventa y no transmite ningún derecho sobre el suelo. Si desistes, o la reserva caduca, la cuota se devuelve según las condiciones del documento que recibes.","id":"Biaya ini memesan kavling yang dipilih, ditahan di rekening escrow notaris, selama masa berlaku yang tercantum dalam Surat Pemesanan, sementara Anda menyelesaikan uji tuntas. Ini bukan akta jual beli dan tidak mengalihkan hak apa pun atas tanah. Jika Anda mundur, atau pemesanan kedaluwarsa, biaya dikembalikan sesuai ketentuan dalam dokumen yang Anda terima."}'::jsonb
    ),
    (
      2,
      '{"en":"Are the prices shown final?","es":"¿Los precios mostrados son definitivos?","id":"Apakah harga yang ditampilkan final?"}'::jsonb,
      '{"en":"No — land and construction prices shown are reference prices per the current catalogue, confirmed in the Plot Lock / construction agreement. They are not a binding offer.","es":"No — los precios de suelo y construcción son precios de referencia del catálogo vigente, y se confirman en el acuerdo de Plot Lock / construcción. No son una oferta vinculante.","id":"Tidak — harga tanah dan konstruksi adalah harga referensi sesuai katalog saat ini, dikonfirmasi dalam perjanjian Plot Lock / konstruksi. Bukan penawaran yang mengikat."}'::jsonb
    ),
    (
      3,
      '{"en":"Is this an investment product?","es":"¿Es un producto de inversión?","id":"Apakah ini produk investasi?"}'::jsonb,
      '{"en":"No. This is the direct purchase of a real-estate asset — a land plot under Hak Sewa, or ownership of the titleholding company under the HGB route — not a security, fund, or tokenised instrument.","es":"No. Es la compra directa de un activo inmobiliario — una parcela en Hak Sewa, o la propiedad de la sociedad titular en la vía HGB — no un valor, un fondo ni un instrumento tokenizado.","id":"Bukan. Ini adalah pembelian langsung aset properti — kavling tanah dengan Hak Sewa, atau kepemilikan perusahaan pemegang hak pada jalur HGB — bukan efek, reksa dana, atau instrumen tokenisasi."}'::jsonb
    ),
    (
      4,
      '{"en":"How are construction-stage payments protected?","es":"¿Cómo se protegen los pagos por hitos de obra?","id":"Bagaimana pembayaran tahap konstruksi dilindungi?"}'::jsonb,
      '{"en":"Construction payments are not made upfront in full — they are split into stages tied to verified progress on site (foundations, structure, enclosures, installations, finishes and handover), per your construction agreement.","es":"Los pagos de construcción no se abonan por adelantado en su totalidad — se reparten en hitos ligados a avance verificado en obra (cimentación, estructura, cerramientos, instalaciones, acabados y entrega), según tu contrato de construcción.","id":"Pembayaran konstruksi tidak dibayar penuh di muka — dibagi menjadi tahapan yang terikat pada progres terverifikasi di lokasi (pondasi, struktur, dinding, instalasi, finishing, dan serah terima), sesuai perjanjian konstruksi Anda."}'::jsonb
    ),
    (
      5,
      '{"en":"Can I resell, transfer or leave the plot to my heirs?","es":"¿Puedo revender, transmitir o dejar la parcela en herencia?","id":"Bisakah saya menjual kembali, mengalihkan, atau mewariskan kavling?"}'::jsonb,
      '{"en":"Yes. Under Hak Sewa, rights are transferable, sellable and heritable within the registered lease term. Under HGB, the transfer is made by selling the shares of your titleholding PT PMA. Exact terms and costs depend on the route chosen and your specific contract — our team can walk you through the process for your situation.","es":"Sí. En la vía Hak Sewa, los derechos son transmisibles, vendibles y heredables dentro del plazo inscrito. En la vía HGB, la transmisión se realiza vendiendo las participaciones de tu PT PMA titular. Las condiciones y costes exactos dependen de la vía elegida y de tu contrato concreto — nuestro equipo puede explicarte el proceso en tu caso.","id":"Bisa. Pada jalur Hak Sewa, hak dapat dialihkan, dijual, dan diwariskan dalam jangka sewa terdaftar. Pada jalur HGB, pengalihan dilakukan dengan menjual saham PT PMA pemegang hak Anda. Ketentuan dan biaya pastinya tergantung jalur yang dipilih dan perjanjian spesifik Anda — tim kami dapat memandu prosesnya sesuai situasi Anda."}'::jsonb
    ),
    (
      6,
      '{"en":"What happens after I reserve a plot?","es":"¿Qué pasa después de reservar una parcela?","id":"Apa yang terjadi setelah saya memesan kavling?"}'::jsonb,
      '{"en":"You receive the Letter of Reservation by email with payment instructions for the reservation fee. Our team follows up to move the process to the next stage — formalising the chosen tenure route (Hak Sewa deed or incorporation of your PT PMA) — within the reservation''s validity period.","es":"Recibes la Carta de Reserva por email con las instrucciones de pago de la cuota. Nuestro equipo hace el seguimiento para avanzar a la siguiente fase — formalización de la vía de tenencia elegida (escritura de Hak Sewa o constitución de tu PT PMA) — dentro del plazo de validez de la reserva.","id":"Anda menerima Surat Pemesanan lewat email beserta instruksi pembayaran biaya pemesanan. Tim kami menindaklanjuti untuk melanjutkan ke tahap berikutnya — memformalkan jalur kepemilikan yang dipilih (akta Hak Sewa atau pendirian PT PMA Anda) — dalam masa berlaku pemesanan."}'::jsonb
    )
) as v(orden, pregunta, respuesta)
where p.nombre <> 'Palm Field W5'
  and not exists (select 1 from public.deck_faq f where f.proyecto_id = p.id);
;
