/* Ficha de ESTA instancia del ERP — AxisWorks ERP, F3 (25-sep-2026), encargos/20260924_estudio_erp_modular.md.

   No es código: son los datos que distinguen a este cliente de cualquier otro. El núcleo (guard.js y toda la suite)
   no escribe ninguno de estos valores; los lee de aquí. En cada instancia nueva del ERP el build de AxisWorks genera
   la suya (comercial/demo-erp/build.py --instancia), así que cambiar un valor de este cliente es cambiar este fichero y
   nada más.

   Se carga ANTES de guard.js en cada página de la intranet (y, en las públicas —acceso, portal, firma—, antes de
   crear el cliente de Supabase). Si falta, guard.js se para: sin base no hay nada que enseñar.
   Solo lectura: nadie puede pisarlo después en la misma página. */
(function () {
  var ficha = Object.freeze({
    sb_url: 'https://vtulllundrfennhjddhc.supabase.co',
    sb_key: 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg',   // publicable: el candado es la RLS
    marca: 'Lawang',                                             // en frases: «lo paga Lawang»
    cabecera: 'LAWANG',                                          // barra lateral, en grande
    subcabecera: 'PROPERTIES & SUITE',                           // barra lateral, debajo
    titulo: 'Lawang Intranet',                                   // pestaña del navegador: «Facturas — Lawang Intranet»
    inicio: '/intranet/v4/home/',                                // portada tras entrar (27-sep-2026, corte de la clásica,
                                                                 // LAW-257/S19): /intranet/ sigue siendo la PUERTA (login),
                                                                 // pero con sesión manda aquí. El hub clásico solo se pinta
                                                                 // ya para enseñar «?sin_permiso=» (guard.js rebota ahí)
    firma_correo: 'Lawang Tropical Properties',                  // firma de los correos: la MARCA, nunca la sociedad
                                                                 // emisora (owner, 8-sep-2026: cada factura la emite una distinta)
    // F3 lote 3 (27-sep-2026): lo que antes decidía el código con NOMBRES de proyecto de este cliente.
    // Clave = proyectos.nombre tal cual (el mismo texto que unidades.proyecto). Sin entrada, sin plano/sin campos.
    masterplans: Object.freeze({                                 // vista «Plano» de /intranet/v4/proyectos/: qué proyecto
      'Palm Field W5': '/investor-deck/masterplan/palmfield.json',  // tiene masterplan y qué fichero pinta (los MISMOS
      'Sumba Hills': '/investor-deck/masterplan/sumbahills.json'    // .json que usan los investor decks)
    }),
    proyectos_con_fases: Object.freeze(['Sumba Hills']),         // proyectos cuyas unidades llevan fase/zona de masterplan
                                                                 // (editores.js: «Nueva unidad» y «Editar unidad» las piden)
    alta_exige_documento: true,                                  // el alta de cliente pide la foto del pasaporte (o el
                                                                 // documento de la empresa) y la sube al archivo KYC
                                                                 // (13-oct-2026, petición del cliente): ficha y documento
                                                                 // entran juntos, por la edge ficheros-kyc (LAW-557); el CRM
                                                                 // de leads manda a darla de alta aquí. Sin la clave: alta de siempre
    recibi_confirma_llegada: true,                               // antes de emitir un recibí, «¿ha llegado ya el dinero?»
                                                                 // (13-oct-2026, petición del cliente). Sin la clave: no pregunta
    // Aviso al titular en el momento de recoger la copia del pasaporte (Legal, revisión previa del 13-oct-2026: es la
    // condición para pedirla en el alta). Lo enseña el agente desde el alta («Aviso de privacidad para el cliente»).
    // Dice solo lo que es verdad: el borrado a los 12 meses sin reserva ni contrato es el de LAW-558 (owner, 13-oct-2026:
    // solo los ficheros; la ficha y su nº de documento se quedan), que hace el cron diario `kyc-retencion-diario` con
    // `config_instancia.kyc_meses_retencion`; de las copias de seguridad no se promete plazo (se dejan como están). Sin
    // registro de accesos (LAW-349). Es dato de este cliente (sociedad, correo), por eso vive aquí y no en editores.js.
    aviso_documento_alta: Object.freeze({
      es: 'Aviso sobre sus datos. La sociedad de Lawang Properties que firme su reserva o contrato es responsable de la copia de su pasaporte (o del documento de su sociedad). La usamos para identificarle antes de la compraventa, como exige la normativa indonesia contra el blanqueo, y para preparar el contrato. Se guarda en un archivo privado al que solo accede el personal autorizado de Lawang (quien gestiona su operación y el equipo de administración), y el notario o las autoridades cuando la ley lo exija. Si no hay a su nombre ninguna reserva (aunque haya vencido), ningún contrato ni otro registro en nuestro sistema (por ejemplo, una factura, un pago, un mensaje, una solicitud o una cuenta en el portal) y pasan 12 meses desde el último movimiento de su expediente, la copia se borra automáticamente (su ficha, con sus datos y el número del documento, se mantiene); también la borramos antes si nos lo pide. Si existe alguno de esos registros, o si firma, la copia no se borra automáticamente: la conservamos al menos el plazo que exige la ley y puede pedirnos que la suprimamos cuando ya no estemos obligados a guardarla. Puede quedar además en las copias de seguridad del sistema, que solo se usan para restaurarlo. Para acceder, rectificar, suprimir u oponerse: sales@lawangproperties.com.',
      en: 'About your data. The Lawang Properties company that signs your reservation or contract is responsible for the copy of your passport (or your company\'s identification document). We use it to verify your identity before the sale, as Indonesian anti-money-laundering rules require, and to prepare the contract. It is kept in a private archive that only authorised Lawang staff can access (those handling your purchase and the administration team), and the notary or authorities where the law requires. If there is no reservation in your name (even an expired one), no contract and no other record in our system (for example an invoice, a payment, a message, a request or a portal account), and 12 months pass since the last activity on your file, the copy is deleted automatically (your record, with your details and the document number, is kept); we also delete it earlier if you ask. If any such record exists, or if you sign, the copy is not deleted automatically: we keep it for at least the period the law requires, and you can ask us to delete it once we are no longer required to keep it. It may also remain in the system\'s backups, which are used only to restore it. To access, correct, delete it or object: sales@lawangproperties.com.',
      id: 'Tentang data Anda. Perusahaan Lawang Properties yang menandatangani reservasi atau kontrak Anda bertanggung jawab atas salinan paspor Anda (atau dokumen identitas perusahaan Anda). Kami menggunakannya untuk memverifikasi identitas Anda sebelum jual beli, sesuai peraturan anti pencucian uang Indonesia, dan untuk menyiapkan kontrak. Salinan disimpan di arsip privat yang hanya dapat diakses staf Lawang yang berwenang (yang menangani transaksi Anda dan tim administrasi), serta notaris atau otoritas bila diwajibkan hukum. Jika tidak ada reservasi atas nama Anda (termasuk yang sudah kedaluwarsa), kontrak, maupun catatan lain di sistem kami (misalnya faktur, pembayaran, pesan, permintaan, atau akun portal), dan 12 bulan berlalu sejak aktivitas terakhir pada berkas Anda, salinan tersebut dihapus secara otomatis (berkas Anda, beserta data dan nomor dokumennya, tetap disimpan); kami juga menghapusnya lebih awal atas permintaan Anda. Jika ada salah satu catatan tersebut, atau jika Anda menandatangani, salinan tidak dihapus secara otomatis: kami menyimpannya setidaknya selama jangka waktu yang diwajibkan hukum, dan Anda dapat meminta kami menghapusnya setelah kami tidak lagi wajib menyimpannya. Salinan itu juga dapat tetap ada di cadangan sistem, yang hanya digunakan untuk memulihkannya. Untuk mengakses, memperbaiki, menghapus, atau menolak pemrosesan: sales@lawangproperties.com.'
    })
  });
  try { Object.defineProperty(window, 'LW_INSTANCIA', { value: ficha, writable: false, configurable: false, enumerable: true }); }
  catch (e) { /* cargado dos veces: la primera ya fijó la misma ficha */ }
})();
