/* ============================================================================
   i18n.js — la interfaz de la suite en inglés (11-sep-2026)
   ----------------------------------------------------------------------------
   POR QUÉ EXISTE
   El interruptor ES/EN se montó el 12-ago-2026 (`idioma.js` + el botón de
   `topbar.js`) porque hay agentes de habla inglesa, y el encargo de entonces
   decía «que se aplique a las nueve herramientas». Se aplicó a UNA:
   `intranet/Documentacion/`. Las demás cargaban el interruptor y seguían en
   español. Esto lo termina.

   POR QUÉ LA CLAVE ES EL PROPIO TEXTO EN ESPAÑOL, y no un nombre inventado
   (`btnGuardar`) como en el piloto de Documentación:

   1. **El español no puede romperse.** `lwT()` devuelve su entrada tal cual
      cuando el idioma es español. No hay un valor `es:` que pueda tener una
      errata, ni una clave que pueda quedarse huérfana e imprimir
      «btnGuardar» en pantalla. Con ~900 frases, el riesgo de estropear la
      vista española al traducir deja de existir por construcción — no por
      revisión.
   2. **Una frase, un sitio.** «Guardar cambios» sale en siete herramientas.
      Con claves propias serían siete entradas `{es,en}` que divergen; con el
      texto como clave es una. Es la regla que esta suite ya tiene escrita:
      una lista a mano en dos sitios ES el bug (`contexto/suite_lawang.md`).
   3. **Se lee.** `data-t` en el HTML no esconde el texto: el HTML sigue
      diciendo «Guardar cambios» y el atributo solo marca que hay que
      traducirlo.

   El piloto de `Documentacion/` sigue con su mecanismo propio a propósito:
   funciona y ya está en inglés. Migrarlo es limpieza opcional, no parte de
   esto — cambiar lo que ya sirve para que se parezca a lo nuevo es riesgo
   sin beneficio para nadie.

   QUÉ **NO** SE TRADUCE, nunca: los DATOS del negocio. Nombre de un
   proyecto, de un comprador, de una carpeta, el texto de un mensaje, el
   concepto de una factura, y sobre todo las CLAVES guardadas en la base
   (`abierto`, `resuelto`, `hak_sewa`…). Se traduce el marco: botones,
   cabeceras, filtros, avisos, mensajes de error. Si una etiqueta visible
   sale de una clave de la base, se traduce la etiqueta y se deja la clave.

   CARGA: en `<head>`, justo detrás de `idioma.js` y SIN `defer` — igual que
   aquél y por el mismo motivo: el <script> propio de cada herramienta tiene
   que encontrar `lwT` ya definido cuando arranca.
   ========================================================================== */
(function () {
  'use strict';

  /* Frases sin traducción encontradas en modo inglés. Es la lista de lo que
     falta, y se lee desde la consola (`[...LW_T_MISSES]`) al verificar una
     herramienta: comprobar la traducción deja de ser mirar la pantalla a ojo
     y pasa a ser una lista. Vacía en español, que no traduce nada. */
  window.LW_T_MISSES = (typeof Set === 'function') ? new Set() : null;

  /* ==========================================================================
     EL DICCIONARIO — clave: el texto en español, exactamente como se escribe
     en el código. Ordenado por temas para poder leerlo, no alfabéticamente.

     · `%n`, `%s`, `%x`… son huecos que rellena el segundo argumento de
       `lwT()`. Se usan SIEMPRE que el texto lleve un número o un nombre
       dentro: `'Hay %n tickets'` y no `'Hay ' + n + ' tickets'`, porque lo
       segundo parte la frase en trozos que no se pueden traducir (en inglés
       el orden de las palabras no es el mismo).
     · Singular y plural son DOS claves enteras, no una con cirugía de
       cadenas: hay idiomas donde no basta con una «s».
     · `frase~contexto` desambigua cuando la misma palabra española es dos
       cosas distintas en inglés. Lo que se imprime en español es siempre lo
       de antes del `~`.
     ========================================================================== */
  var EN = {
    /* ── Bancos y conciliación (/v4/bancos/, 24-sep-2026) ── */
    'Saldo de cada cuenta según su extracto': 'Balance of each account per its statement',
    'Abrir Bancos': 'Open Banks',
    'los bancos': 'the banks',
    'Falta la casilla «Bancos»: los saldos bancarios no se ven.': 'The «Bancos» permission is missing: bank balances are not visible.',
    'Entra en el año': 'In this year',
    'Sale en el año': 'Out this year',
    'sin saldo': 'no balance',
    'Entradas y salidas sin contar los traspasos entre cuentas propias. En rojo, extractos de hace más de 7 días.': 'Inflows and outflows exclude transfers between own accounts. In red, statements older than 7 days.',
    'A medias': 'Partly',
    'Abono / entrada': 'Credit / money in',
    'Antes, marca en Cuentas qué cuentas son de la sociedad: solo esas se pueden importar.': 'First, mark in Accounts which accounts belong to the company: only those can be imported.',
    'Aportación de capital': 'Capital contribution',
    'Bancos': 'Banks',
    'Bancos y conciliación': 'Banks and reconciliation',
    'Buscar en el concepto o la referencia': 'Search the description or reference',
    'Cada línea del extracto y qué la explica': 'Every statement line and what explains it',
    'Cargo / salida': 'Debit / money out',
    'Columna': 'Column',
    'Columnas': 'Columns',
    'Comisión del banco': 'Bank fee',
    'Comisión pagada': 'Commission paid',
    'Con «Otro» hace falta explicar qué es en la nota.': 'With «Other» you must explain what it is in the note.',
    'Concepto / descripción': 'Description',
    'Conciliado': 'Reconciled',
    'Conciliados': 'Reconciled',
    'Conciliando…': 'Reconciling…',
    'Conciliar': 'Reconcile',
    'Conciliar a mano': 'Reconcile manually',
    'Cuenta': 'Account',
    'Cuál': 'Which one',
    'Descarga el extracto en CSV desde la banca online (Statrys, DBS, OCBC…). La primera vez que importes una cuenta, indica qué columna es cada cosa: se recuerda para las siguientes.': 'Download the statement as CSV from online banking (Statrys, DBS, OCBC…). The first time you import an account, say which column is which: it is remembered for next time.',
    'Deshacer': 'Undo',
    'Deshacer esta línea': 'Undo this line',
    'Deshecho aquí, pero no en la otra cuenta': 'Undone here, but not in the other account',
    'Detectar': 'Detect',
    'Diferencia con': 'Difference with',
    'Día / mes / año': 'Day / month / year',
    'El extracto no trae saldo': 'The statement has no balance',
    'El fichero no trae filas que se puedan leer.': 'The file has no readable rows.',
    'El fichero pasa de 5 MB: exporta un periodo más corto.': 'The file is over 5 MB: export a shorter period.',
    'El importe del documento no es válido.': 'The document amount is not valid.',
    'El importe no es válido.': 'The amount is not valid.',
    'El movimiento vuelve a quedar por conciliar en esa parte. La línea no se borra: queda anulada en el historial.': 'That part of the transaction goes back to unreconciled. The line is not deleted: it stays voided in the history.',
    'El traspaso quedó apuntado en esta cuenta, pero no en la otra': 'The transfer was recorded in this account, but not in the other one',
    'Elige el documento.': 'Choose the document.',
    'Empieza con «Importar extracto».': 'Start with «Import statement».',
    'En el banco': 'In the bank',
    'En el documento': 'In the document',
    'En la banca online, exporta los movimientos en formato CSV. Si solo te deja Excel, ábrelo y guárdalo como CSV.': 'In online banking, export the transactions as CSV. If it only offers Excel, open it and save it as CSV.',
    'Ese fichero no es CSV. Ábrelo en Excel y usa «Guardar como» → CSV.': 'That file is not CSV. Open it in Excel and use «Save as» → CSV.',
    'Extracto en CSV': 'Statement in CSV',
    'Extracto hasta': 'Statement up to',
    'Extractos con más de 7 días': 'Statements older than 7 days',
    'Falta el fichero.': 'The file is missing.',
    'Falta el importe (o cargo y abono).': 'The amount (or debit and credit) is missing.',
    'Falta la columna de la fecha.': 'The date column is missing.',
    'Falta por explicar': 'Still to explain',
    'Fecha del movimiento': 'Transaction date',
    'Fecha valor': 'Value date',
    'Fila de los títulos': 'Header row',
    'Formato de la fecha': 'Date format',
    'Gasto pagado': 'Expense paid',
    'Ignorado': 'Ignored',
    'Ignorados': 'Ignored',
    'Ignorar': 'Ignore',
    'Ignorar movimiento': 'Ignore transaction',
    'Importar': 'Import',
    'Importar extracto': 'Import statement',
    'Importe (con signo)': 'Amount (signed)',
    'Importe de esta línea en el banco (sin signo)': 'Amount of this line in the bank (unsigned)',
    'Importe en la moneda del documento': 'Amount in the document currency',
    'Indica qué columna del extracto es cada cosa. Se guarda para esta cuenta y la próxima vez sale solo. Hace falta la fecha y, o bien una columna de importe con signo, o bien cargo y abono.': 'Say which statement column is which. It is saved for this account and filled in next time. You need the date and either a signed amount column or debit and credit.',
    'Las columnas no se han podido guardar: la próxima vez habrá que indicarlas otra vez.': 'The columns could not be saved: next time they will have to be set again.',
    'Llegó': 'Received',
    'Lo explica': 'Explained by',
    'Lo que ha pasado después no está aquí: importa el extracto nuevo.': 'Anything after that is not here: import the new statement.',
    'Los extractos de las cuentas de la sociedad, y cada movimiento enlazado con lo que lo explica: un recibí, un gasto, una comisión o un traspaso entre cuentas propias. Lo que no cuadra se ve aquí.': 'The statements of the company accounts, with every transaction linked to what explains it: a receipt, an expense, a commission or a transfer between own accounts. Whatever does not match shows up here.',
    'Mes / día / año': 'Month / day / year',
    'Moneda (columna)': 'Currency (column)',
    'Moneda si no hay columna': 'Currency if there is no column',
    'Movimiento': 'Transaction',
    'Movimiento de otra cuenta': 'Transaction in another account',
    'Movimiento interno de tesorería': 'Internal treasury movement',
    'Movimientos': 'Transactions',
    'Máximo 5.000 movimientos por importación: exporta el extracto por meses.': 'Maximum 5,000 transactions per import: export the statement month by month.',
    'Nada por conciliar con estos filtros.': 'Nothing to reconcile with these filters.',
    'Nada todavía.': 'Nothing yet.',
    'Ningún documento con el mismo importe y fecha cercana. Concílialo a mano.': 'No document with the same amount and a close date. Reconcile it manually.',
    'Ningún movimiento con estos filtros.': 'No transactions with these filters.',
    'No cargaron las piezas de la pantalla (bancos.js / editores.js). Recarga la página; si sigue, avisa a Desarrollo.': 'Parts of the page did not load (bancos.js / editores.js). Reload the page; if it persists, tell Development.',
    'No hay ninguna cuenta marcada como propia de la sociedad. Ve a Cuentas, da de alta la cuenta (por ejemplo la de Statrys) y marca «De la sociedad». Luego vuelve aquí.': 'No account is marked as belonging to the company. Go to Accounts, add the account (for example Statrys) and tick «De la sociedad». Then come back here.',
    'No hay ningún movimiento que importar con estas columnas.': 'There are no transactions to import with these columns.',
    'No se pudieron leer los bancos': 'The banks could not be read',
    'No se pudieron volver a leer los bancos': 'The banks could not be read again',
    'No se pudo deshacer': 'Could not undo',
    'No se pudo importar': 'Could not import',
    'No se pudo quitar la marca': 'Could not remove the mark',
    'No ves las comisiones: para enlazar con una hace falta la casilla de Comisiones.': 'You cannot see commissions: linking to one needs the Commissions permission.',
    'No ves los gastos: las salidas no se podrán enlazar con un gasto hasta que te marquen «Gastos y proveedores» en Usuarios.': 'You cannot see expenses: outflows cannot be linked to an expense until «Gastos y proveedores» is ticked for you in Users.',
    'No ves los gastos: para enlazar con uno hace falta la casilla «Gastos y proveedores».': 'You cannot see expenses: linking to one needs the «Gastos y proveedores» permission.',
    'Pago entre sociedades': 'Payment between companies',
    'Para movimientos que no hay que explicar con ningún documento (por ejemplo, un cargo devuelto el mismo día). Queda con su motivo y se puede deshacer.': 'For transactions that need no document (for example, a charge reversed the same day). It keeps its reason and can be undone.',
    'Por conciliar': 'To reconcile',
    'Préstamo entre sociedades': 'Loan between companies',
    'Quitar «ignorado»': 'Remove «ignored»',
    'Qué es este traspaso': 'What this transfer is',
    'Qué lo explica': 'What explains it',
    'Recarga la página.': 'Reload the page.',
    'Referencia': 'Reference',
    'Reimportar un extracto que se solapa con otro no duplica nada: los movimientos ya importados se reconocen y se saltan.': 'Re-importing an overlapping statement duplicates nothing: transactions already imported are recognised and skipped.',
    'Retención de': 'Withholding on',
    'Retención ingresada (PPh)': 'Withholding paid (PPh)',
    'Retención que nos aplicaron': 'Tax withheld from us',
    'Saldo': 'Balance',
    'Saldo que da el banco a': 'Balance given by the bank on',
    'Saldo tras el movimiento': 'Balance after the transaction',
    'Si el traspaso va a una cuenta de otra sociedad del grupo, elige si es capital, préstamo o pago: cuenta para el reporting entre sociedades.': 'If the transfer goes to an account of another group company, choose whether it is capital, a loan or a payment: it counts for intercompany reporting.',
    'Si eres admin, pide que te marquen «Bancos» en Usuarios.': 'If you are an admin, ask to have «Bancos» ticked in Users.',
    'Siguiente': 'Next',
    'Solo se importan cuentas marcadas como propias en Cuentas. Si falta una (por ejemplo Statrys), dala de alta en Cuentas y márcala «De la sociedad».': 'Only accounts marked as own in Accounts can be imported. If one is missing (for example Statrys), add it in Accounts and tick «De la sociedad».',
    'Solo si el documento está en otra moneda.': 'Only if the document is in another currency.',
    'Sugerencias': 'Suggestions',
    'Supera lo que falta por explicar de este movimiento': 'It exceeds what is left to explain in this transaction',
    'Todas las cuentas': 'All accounts',
    'Todavía no hay movimientos. Importa el extracto de una cuenta.': 'No transactions yet. Import an account statement.',
    'Todavía no hay ningún extracto importado.': 'No statement imported yet.',
    'Todo conciliado': 'All reconciled',
    'Traspaso entre cuentas propias': 'Transfer between own accounts',
    'Trayendo los movimientos…': 'Loading transactions…',
    'Trayendo los saldos…': 'Loading balances…',
    'Tu usuario no ve los bancos: hace falta ser admin y tener «Bancos» marcado en Usuarios.': 'Your user cannot see the banks: you need to be an admin and have «Bancos» ticked in Users.',
    'al': 'to',
    'cambio': 'rate',
    'columnas ya guardadas': 'columns already saved',
    'del': 'from',
    'diferencia': 'difference',
    'días de antigüedad': 'days old',
    'día de diferencia': 'day apart',
    'días': 'days',
    'días de diferencia': 'days apart',
    'el concepto lo nombra': 'named in the description',
    'entra': 'in',
    'error desconocido': 'unknown error',
    'falta': 'missing',
    'filas no se pueden leer y NO se importarán': 'rows cannot be read and will NOT be imported',
    'filas sin leer': 'rows not read',
    'formato de fecha': 'date format',
    'línea': 'line',
    'menos en el banco': 'less in the bank',
    'mismo día': 'same day',
    'movimiento': 'transaction',
    'movimiento por conciliar': 'transaction to reconcile',
    'movimientos': 'transactions',
    'movimientos leídos': 'transactions read',
    'movimientos nuevos': 'new transactions',
    'movimientos por conciliar': 'transactions to reconcile',
    'más en el banco': 'more in the bank',
    'pendiente de': 'outstanding of',
    'sale': 'out',
    'sin contar traspasos entre cuentas propias': 'excluding transfers between own accounts',
    'ya estaban importados': 'were already imported',
    '— ninguna —': '— none —',
    /* ── Gastos y proveedores (/v4/gastos/, 24-sep-2026) ── */
    'A pagar': 'To pay',
    'A quién se paga': 'Who gets paid',
    'Activo (se ofrece al apuntar un gasto)': 'Active (offered when recording an expense)',
    'Al proveedor': 'To the supplier',
    'Al proveedor se le paga': 'The supplier is paid',
    'Alta': 'Created',
    'Anulados': 'Voided',
    'Anular este gasto': 'Void this expense',
    'Anular gasto': 'Void expense',
    'Añadir justificante': 'Add receipt',
    'Base': 'Base',
    'Base (sin impuesto)': 'Base (before tax)',
    'Buscar concepto, proveedor o referencia': 'Search description, supplier or reference',
    'Caja del año': 'Cash this year',
    'Caja neta': 'Net cash',
    'Cambio de datos': 'Data change',
    'Cancelado.': 'Cancelled.',
    'Categoría': 'Category',
    'Comisiones pagadas a closers': 'Commissions paid to closers',
    'Comisiones pagadas: falta la casilla «Reparto a closers»; no están restadas.': 'Commissions paid: the «Reparto a closers» permission is missing; they are not deducted.',
    'Con justificante': 'With receipt',
    'Constructora': 'Builder',
    'Desde la cuenta': 'From account',
    'Editar gasto': 'Edit expense',
    'Editar proveedor': 'Edit supplier',
    'El fichero pasa de 10 MB.': 'The file is over 10 MB.',
    'El gasto sí se ha guardado: sube el justificante desde su ficha.': 'The expense was saved: upload the receipt from its record.',
    'El importe retenido no es válido': 'The withheld amount is not valid',
    'El impuesto no es un importe válido': 'The tax is not a valid amount',
    'En el año': 'This year',
    'En qué se va el dinero': 'Where the money goes',
    'Entradas (recibís)': 'Inflows (receipts)',
    'Es caja, no resultado: no descuenta amortizaciones ni lo que aún no se ha registrado en Gastos.': 'This is cash, not profit: it does not deduct depreciation or anything not yet recorded in Expenses.',
    'Facturas de proveedores por pagar': 'Supplier invoices to pay',
    'Falta la casilla «Gastos y proveedores» en Usuarios: sin ella no se ve lo que sale.': 'The «Gastos y proveedores» permission is missing in Users: without it outflows are not visible.',
    'Falta la casilla «Gastos y proveedores»: las facturas de proveedores no están sumadas.': 'The «Gastos y proveedores» permission is missing: supplier invoices are not included.',
    'Fecha de la factura': 'Invoice date',
    'Gasto': 'Expense',
    'Gastos': 'Expenses',
    'Gastos del año': 'Expenses this year',
    'Gastos y proveedores': 'Expenses and suppliers',
    'Gastos: esta sesión no tiene la casilla «Gastos y proveedores». Los saldos bancarios todavía no se registran.': 'Expenses: this session does not have the «Gastos y proveedores» permission. Bank balances are not recorded yet.',
    'Gastos: solo los que se apuntan en Gastos (el módulo existe desde el 24-sep-2026). Los saldos bancarios todavía no se registran.': 'Expenses: only those recorded in Expenses (the module exists since 24-Sep-2026). Bank balances are not recorded yet.',
    'General': 'General',
    'General (sin proyecto)': 'General (no project)',
    'Guardar gasto': 'Save expense',
    'Importe retenido': 'Amount withheld',
    'Importes': 'Amounts',
    'Impuesto soportado': 'Input tax',
    'Impuesto soportado (PPN/IVA)': 'Input tax (PPN/VAT)',
    'Ingresada el': 'Paid to tax office on',
    'Inversión en suelo (no es gasto de explotación)': 'Land investment (not an operating expense)',
    'Justificante (PDF o imagen, máx. 10 MB)': 'Receipt (PDF or image, max. 10 MB)',
    'Justificantes': 'Receipts',
    'La base no es un importe válido': 'The base is not a valid amount',
    'La compra de suelo es inversión, no gasto de explotación: Finanzas la enseña aparte. Nunca se paga un gasto desde una cuenta de escrow.': 'Buying land is an investment, not an operating expense: Finance shows it separately. An expense is never paid from an escrow account.',
    'La retención no puede ser mayor que el total de la factura.': 'The withholding cannot exceed the invoice total.',
    'Las comisiones de los closers no se apuntan aquí: salen solas de Comisiones y ya cuentan en Finanzas.': 'Closer commissions are not recorded here: they come from Commissions and already count in Finance.',
    'Las comisiones no se reparten por sociedad.': 'Commissions are not split by company.',
    'Libro de gastos': 'Expense ledger',
    'Lo que ha entrado menos lo que ha salido': 'What came in minus what went out',
    'Lo que paga la empresa: cada factura de proveedor con su sociedad, su proyecto, su categoría, la retención de PPh y su justificante. Un gasto no se borra: se anula con motivo, y cada cambio queda registrado.': 'What the company pays: each supplier invoice with its company, project, category, PPh withholding and receipt. An expense is never deleted: it is voided with a reason, and every change is logged.',
    'Marcar como pagado': 'Mark as paid',
    'Marcar pagado': 'Mark paid',
    'Neto': 'Net',
    'Ninguno con la fecha de pago pasada': 'None past its payment date',
    'Ningún gasto con estos filtros.': 'No expenses match these filters.',
    'Ningún gasto de explotación registrado este año.': 'No operating expenses recorded this year.',
    'No cargaron las piezas de la pantalla (finanzas.js / editores.js). Recarga la página; si sigue, avisa a Desarrollo.': 'The screen components did not load (finanzas.js / editores.js). Reload the page; if it persists, tell Development.',
    'No crees otro gasto por este ingreso: ya cuenta aquí.': 'Do not create another expense for this payment: it already counts here.',
    'No se pudieron leer las solicitudes y comisiones.': 'Could not read the requests and commissions.',
    'No se pudieron leer los gastos': 'Could not read the expenses',
    'No se pudieron leer los gastos.': 'Could not read the expenses.',
    'No se pudo abrir el justificante': 'Could not open the receipt',
    'No se pudo anotar el justificante': 'Could not record the receipt',
    'No se pudo anular': 'Could not void',
    'No se pudo guardar': 'Could not save',
    'No se pudo guardar el gasto': 'Could not save the expense',
    'No se pudo guardar el proveedor': 'Could not save the supplier',
    'No se pudo leer el historial.': 'Could not read the history.',
    'No se pudo marcar como pagado': 'Could not mark as paid',
    'No se pudo subir el justificante': 'Could not upload the receipt',
    'No se puede deshacer.': 'This cannot be undone.',
    'No, pendiente de pagar': 'No, pending payment',
    'Nuevo gasto': 'New expense',
    'Nuevo proveedor': 'New supplier',
    'Nº de factura': 'Invoice no.',
    'Nº de factura del proveedor': 'Supplier invoice no.',
    'Otra': 'Other',
    'PDF o imagen, máx. 10 MB': 'PDF or image, max. 10 MB',
    'PPh': 'PPh',
    'PPh 21 (persona física)': 'PPh 21 (individual)',
    'PPh 23 (servicios)': 'PPh 23 (services)',
    'PPh 26 (no residente)': 'PPh 26 (non-resident)',
    'PPh 4(2) (construcción, alquiler)': 'PPh 4(2) (construction, rent)',
    'PPh retenido a proveedores que aún no se ha ingresado en Hacienda.': 'PPh withheld from suppliers not yet paid to the tax office.',
    'Pagado a proveedores y retenciones': 'Paid to suppliers and withholdings',
    'Pagado el': 'Paid on',
    'Pagado este mes': 'Paid this month',
    'Pagados': 'Paid',
    'Pago': 'Payment',
    'Pendiente de pagar': 'Pending payment',
    'Pendientes y pagados': 'Pending and paid',
    'Persona de contacto': 'Contact person',
    'Por la base, sin el impuesto soportado: el PPN se compensa y no es coste.': 'By base, without input tax: PPN is offset and is not a cost.',
    'Profesional': 'Professional',
    'Proveedor': 'Supplier',
    'Proveedores': 'Suppliers',
    'Retenciones PPh por ingresar': 'PPh withholdings to pay',
    'Retenciones por ingresar': 'Withholdings to pay',
    'Retención': 'Withholding',
    'Retención PPh': 'PPh withholding',
    'Retención ingresada': 'Withholding paid',
    'Retención ingresada en Hacienda': 'Withholding paid to the tax office',
    'Se paga al proveedor el total menos esto; la retención se ingresa luego en Hacienda.': 'The supplier is paid the total minus this; the withholding is later paid to the tax office.',
    'Si eres admin, pide que te marquen «Gastos y proveedores» en Usuarios.': 'If you are an admin, ask to have «Gastos y proveedores» ticked in Users.',
    'Si se retiene PPh al proveedor, se apunta en el propio gasto. Cuando se ingresa en Hacienda se marca «Retención ingresada»; no se crea otro gasto por ese ingreso.': 'If PPh is withheld from the supplier, record it in the expense itself. When it is paid to the tax office, mark «Withholding paid»; do not create another expense for that payment.',
    'Sin justificante todavía.': 'No receipt yet.',
    'Sin la casilla «Gastos y proveedores» el gráfico enseña solo lo que entra.': 'Without the «Gastos y proveedores» permission the chart shows only inflows.',
    'Sin permiso para ver lo que se debe pagar: no es que no se deba nada, es que esta sesión no lo puede ver.': 'No permission to see what is owed: it does not mean nothing is owed, this session cannot see it.',
    'Sin retención': 'No withholding',
    'Sociedad que paga': 'Paying company',
    'Solicitudes de pago vivas, comisiones devengadas que aún no tienen solicitud, facturas de proveedores por pagar y retenciones por ingresar. Una comisión con solicitud se cuenta una sola vez.': 'Open payment requests, accrued commissions with no request yet, supplier invoices to pay and withholdings to pay. A commission with a request is counted only once.',
    'Subir': 'Upload',
    'Sí, ya pagado': 'Yes, already paid',
    'Todas las categorías': 'All categories',
    'Todavía no hay ningún gasto. Empieza con «Nuevo gasto».': 'No expenses yet. Start with «New expense».',
    'Todavía no hay proveedores. Empieza con «Nuevo proveedor».': 'No suppliers yet. Start with «New supplier».',
    'Trayendo los gastos…': 'Loading expenses…',
    'Trayendo los proveedores…': 'Loading suppliers…',
    'Tu usuario no ve el catálogo de categorías: hace falta ser admin y tener «Gastos y proveedores» marcado en Usuarios. La base no enseña nada sin ese permiso.': 'Your user cannot see the category catalogue: you need to be an admin and have «Gastos y proveedores» ticked in Users. The database shows nothing without that permission.',
    'Un gasto anulado deja de contar en todo y ya no se puede editar. No se borra: queda en el libro con su motivo.': 'A voided expense stops counting anywhere and can no longer be edited. It is not deleted: it stays in the ledger with its reason.',
    'Un proveedor no se borra: se desactiva y deja de ofrecerse al apuntar un gasto nuevo. Sus gastos siguen ahí.': 'A supplier is never deleted: it is deactivated and no longer offered for new expenses. Its expenses remain.',
    'Una fila por factura de proveedor': 'One row per supplier invoice',
    'Vence el': 'Due on',
    'Vencido sin pagar': 'Overdue, unpaid',
    'Ver en Gastos': 'See in Expenses',
    'Ya existe un proveedor con ese nombre.': 'A supplier with that name already exists.',
    'con la fecha de pago pasada': 'past their payment date',
    'gastos': 'expenses',
    'gasto': 'expense',
    'gastos por pagar': 'expenses to pay',
    'los gastos': 'the expenses',
    'neto de caja en': 'net cash in',
    'total menos la retención': 'total minus the withholding',
    'total sin anulados': 'total excluding voided',
    '¿No está? Créalo en la pestaña Proveedores.': 'Not listed? Create it in the Suppliers tab.',
    '¿Ya está pagado?': 'Already paid?',
    '— elige —': '— choose —',
    '— sin indicar —': '— not specified —',
    '— sin proveedor —': '— no supplier —',
    /* ── Finanzas (/v4/finanzas/, 24-sep-2026) ── */
    'El closer se asigna a la operación entera: su Carta, su Bloqueo y su Construcción cuentan para quien la cerró. Cobrado es todo lo que pagaron sus compradores en el año, vaya a la cuenta que vaya.': 'The closer is assigned to the whole deal: its Reservation Letter, Plot Block and Construction count for whoever closed it. Collected is everything their buyers paid this year, whichever account it went to.',
    'Imprimir / PDF': 'Print / PDF',
    'Informe de finanzas': 'Finance report',
    'Lo que ha cerrado cada uno y lo cobrado': 'What each one closed and what was collected',
    'Ninguna venta firmada en': 'No signed sales in',
    'No se pudo leer quién cerró cada venta.': 'Could not read who closed each sale.',
    'Por closer': 'By closer',
    'Sin permiso: ver quién cierra cada venta exige la casilla «Ranking» en Usuarios.': 'No permission: seeing who closes each sale requires the «Ranking» permission in Users.',
    'incluye sin firmar': 'includes unsigned',
    'Cobrado = recibís emitidos, por su fecha, solo los que entraron en cuentas de la sociedad o aún sin clasificar (lo cobrado en cuentas de terceros o de escrow no es caja y sale en «Caja del año»). Previsto = lo que falta por cobrar de los hitos con fecha de los contratos firmados, una vez descontado lo ya cobrado. Lo vencido no aparece como previsto: está en su tarjeta.': 'Collected = receipts issued, by date, only those paid into company accounts or not yet classified (money paid into third-party or escrow accounts is not cash and appears in «Cash this year»). Expected = what is still to be collected from dated milestones of signed contracts, after deducting what has been collected. Overdue amounts are not shown as expected: they have their own card.',
    'Cobrado en cuentas de escrow (notario)': 'Collected into escrow accounts (notary)',
    'Cobrado en cuentas de terceros': 'Collected into third-party accounts',
    'Cobrado en cuentas de terceros (contratista, vendedor de suelo)': 'Collected into third-party accounts (contractor, land seller)',
    'Entradas en cuentas de la sociedad': 'Inflows into company accounts',
    'Entradas sin clasificar (cuenta sin marcar o recibí sin cuenta)': 'Unclassified inflows (unmarked account or receipt without account)',
    'Entró en la sociedad': 'Came into the company',
    'Hay entradas sin clasificar: el neto las cuenta como de la sociedad. Marca en Cuentas de quién es cada cuenta para que la cifra sea exacta.': 'There are unclassified inflows: the net counts them as company cash. Mark in Accounts who owns each account to make the figure exact.',
    'Ir a Cuentas': 'Go to Accounts',
    'No es caja de la sociedad (no entra en el neto):': 'Not company cash (excluded from the net):',
    'Pagado desde la cuenta': 'Paid from account',
    'Para indicar desde qué cuenta se paga, marca en Cuentas cuáles son de la sociedad.': 'To record which account pays, mark in Accounts which ones belong to the company.',
    'Contratado por cobrar': 'Contracted, to collect',
    'El stock no se reparte por sociedad: una unidad no tiene sociedad hasta que se vende. Quita el filtro para verlo.': 'Stock is not split by company: a unit has no company until it is sold. Remove the filter to see it.',
    'El stock y las comisiones no se reparten por sociedad.': 'Stock and commissions are not split by company.',
    'Incluye contratos SIN FIRMAR: la cartera y la previsión suman borradores, que todavía no son un compromiso. Útil mientras dure el alta de histórico.': 'Includes UNSIGNED contracts: the portfolio and forecast add drafts, which are not a commitment yet. Useful while the historical data is being loaded.',
    'Las comisiones no se reparten por sociedad. Quita el filtro para verlas.': 'Commissions are not split by company. Remove the filter to see them.',
    'No se pudo leer la sociedad de los contratos: el filtro no está disponible.': 'Could not read the company of the contracts: the filter is not available.',
    'Solo contratos firmados. Un proyecto sin ventas firmadas aparece igual si tiene unidades disponibles. Pulsa un proyecto para ver quién debe.': 'Signed contracts only. A project with no signed sales still appears if it has available units. Click a project to see who owes.',
    'Viendo solo': 'Showing only',
    'contratados': 'contracted',
    'más: la lista completa sale en el CSV.': 'more: the full list is in the CSV.',
    '% cobrado': '% collected',
    '(sin sociedad)': '(no company)',
    'Al día': 'Not yet due',
    'Antigüedad desde el vencimiento de la factura': 'Age counted from the invoice due date',
    'Bloqueada': 'Blocked',
    'Cada sociedad es una empresa distinta: la suma solo sirve de referencia, no es la caja de ninguna.': "Each company is a separate business: the total is only a reference, it is nobody's cash.",
    'Caja': 'Cash',
    'Calculando…': 'Calculating…',
    'Cartas de Reserva: su precio lo repite el contrato que las sustituye; su cobro sí cuenta.': 'Reservation Letters: their price is repeated by the contract that replaces them; what they collected does count.',
    'Cobrado = recibís emitidos, por su fecha. Previsto = lo que falta por cobrar de los hitos con fecha de los contratos firmados, una vez descontado lo ya cobrado. Lo vencido no aparece como previsto: está en su tarjeta.': 'Collected = receipts issued, by date. Expected = what is still to be collected from dated milestones of signed contracts, after deducting what has been collected. Overdue amounts are not shown as expected: they have their own card.',
    'Cobrado en el año': 'Collected this year',
    'Cobrado en el año por cada empresa': 'Collected this year by company',
    'Cobrado este mes': 'Collected this month',
    'Cobrado por mes y previsto por calendario': 'Collected per month and expected per schedule',
    'Comisiones sin solicitud todavía': 'Commissions with no payment request yet',
    'Cuándo toca cobrar lo pendiente': 'When the outstanding amount is due',
    'De 31 a 90 días': '31 to 90 days',
    'De ello,': 'Of this,',
    'Disponible': 'Available',
    'El dinero de la empresa en una pantalla: lo que ha entrado, lo firmado que falta por cobrar y cuándo toca, lo facturado sin cobrar, lo que queda por vender y lo que ya se debe pagar. Solo lectura: cada cifra sale de las mismas cuentas que Vencimientos, Facturas y Operaciones.': "The company's money on one screen: what has come in, what is signed and still to be collected and when, what is invoiced and unpaid, what is left to sell and what is already owed. Read only: every figure comes from the same calculations as Due dates, Invoices and Operations.",
    'Esta pantalla es de dirección (admin).': 'This screen is for management (admin).',
    'Exportar CSV': 'Export CSV',
    'Facturado sin cobrar': 'Invoiced, not collected',
    'Facturas emitidas que siguen abiertas': 'Issued invoices still open',
    'Falló el cálculo del panel. Avisa a Desarrollo.': 'The panel calculation failed. Tell Development.',
    'Falta la casilla «Pagos de Lawang»: las solicitudes de pago no están sumadas.': 'The «Pagos de Lawang» permission is missing: payment requests are not included.',
    'Falta la casilla «Reparto a closers»: las comisiones sin solicitud no están sumadas.': 'The «Reparto a closers» permission is missing: commissions without a request are not included.',
    'Finanzas': 'Finance',
    'Resumen': 'Overview',
    // Creatividades · rediseño A (24-sep-2026)
    '← Biblioteca': '← Library',
    'Nueva pieza': 'New piece',
    'Piezas y dossiers hechos con las fotos y los datos de cada proyecto. Lo aprobado lo pueden descargar los comerciales.': 'Pieces and dossiers made from each project’s photos and data. Sales agents can download what is approved.',
    'Piezas y dossiers': 'Pieces and dossiers',
    'Solo piezas': 'Pieces only',
    'Solo dossiers': 'Dossiers only',
    'Esperan tu aprobación': 'Waiting for your approval',
    'Enviadas a aprobar': 'Sent for approval',
    'Las reglas de Legal ya pasaron al guardar: falta tu visto bueno.': 'Legal’s rules were checked on save: it only needs your approval.',
    'Un admin las revisa. Mientras tanto no se pueden editar.': 'An admin reviews them. Until then they cannot be edited.',
    'Devolver': 'Send back',
    'Para aprobar': 'For approval',
    'Borradores': 'Drafts',
    'Archivo': 'Archive',
    'Publicadas': 'Published',
    'Aprobadas': 'Approved',
    'Enviar a aprobar': 'Send for approval',
    '¿Devolver «': 'Send back «',
    'Vuelve a borrador para que se corrija y se envíe otra vez. Los comerciales no la ven.': 'It goes back to draft to be fixed and sent again. Sales agents cannot see it.',
    'sin material': 'without material',
    'solo con render': 'render only',
    'modelos sin imágenes': 'models without images',
    'todo con material': 'everything has material',
    'Nueva, sin guardar': 'New, not saved',
    'Elige primero el proyecto.': 'Choose the project first.',
    'Encuadre': 'Framing',
    'Usar una imagen de mi ordenador': 'Use an image from my computer',
    'Solo para descargar: una imagen suelta no se puede guardar en la biblioteca porque no se sabe de qué proyecto es.': 'Download only: a loose image cannot be saved to the library because its project is unknown.',
    'Titular, precio y WhatsApp': 'Headline, price and WhatsApp',
    'Lugar (antetítulo)': 'Place (kicker)',
    'Precio, contacto y pie': 'Price, contact and footer',
    'Mostrar precio': 'Show price',
    'El precio va vacío a propósito: escríbelo solo si el dato está confirmado.': 'The price is empty on purpose: only fill it in if the figure is confirmed.',
    'Línea de texto (la foto manda)': 'Text line (the photo leads)',
    'Botón verde de WhatsApp': 'Green WhatsApp button',
    'Texto del contacto': 'Contact text',
    'Revisión': 'Review',
    'Elige una foto para medir el contraste real.': 'Choose a photo to measure the real contrast.',
    'Se comprueba mientras escribes. Lo de Legal bloquea guardar y descargar; la legibilidad avisa.': 'Checked as you type. Legal issues block saving and downloading; legibility only warns.',
    'Arrastra el texto sobre la pieza para colocarlo.': 'Drag the text on the piece to place it.',
    'No has elegido ninguna foto: la pieza saldría sin imagen.': 'You have not chosen a photo: the piece would have no image.',
    'Antes de publicar': 'Before publishing',
    'sin elegir': 'not chosen',
    'Ver en la biblioteca': 'View in the library',
    '¿Enviar a aprobar?': 'Send for approval?',
    'Se guarda tal como está y un admin la revisa. Mientras espera no se puede editar; si hay que cambiar algo, te la devuelve.': 'It is saved as it is and an admin reviews it. While it waits it cannot be edited; if something needs changing, it is sent back to you.',
    'Se guarda tal como está y un admin lo revisa. Mientras espera no se puede editar; si hay que cambiar algo, te lo devuelve.': 'It is saved as it is and an admin reviews it. While it waits it cannot be edited; if something needs changing, it is sent back to you.',
    'Enviada a aprobar.': 'Sent for approval.',
    'Enviada a aprobar': 'Sent for approval',
    'Enviado a aprobar ✓': 'Sent for approval ✓',
    'cambios sin guardar': 'unsaved changes',
    'Guardar como copia': 'Save as a copy',
    '+ «Cómo se compra»': '+ «How to buy»',
    'Abrir un fichero…': 'Open a file…',
    'Descargar como fichero': 'Download as a file',
    'Lo que sale en rojo bloquea guardar y exportar. Las páginas de Legal no se revisan: nombran lo prohibido para negarlo.': 'Anything in red blocks saving and exporting. Legal’s pages are not checked: they name what is forbidden in order to rule it out.',
    'Falta': 'Missing',
    'Bien': 'OK',
    'Sin frases que Legal no deja': 'No phrases Legal forbids',
    'Habla de la titularidad: añade «Cómo se compra» (menú Insertar).': 'It mentions ownership: add «How to buy» (Insert menu).',
    '«Cómo se compra» incluida': '«How to buy» included',
    'Sin «Cómo se compra»: no hace falta mientras no hable de la titularidad.': 'No «How to buy»: not needed while it does not mention ownership.',
    'Pie de precios con fecha': 'Dated price footer',
    'Hay precios sin el pie de precios con fecha (contraportada)': 'There are prices without the dated price footer (back cover)',
    'El dossier habla de la titularidad: añade la página «Cómo se compra» (menú Insertar), que explica las dos rutas.': 'The dossier mentions ownership: add the «How to buy» page (Insert menu), which explains the two routes.',
    // Creatividades v4 (24-sep-2026): generador, dossier desde la base y biblioteca.
    'En la biblioteca: ': 'In the library: ',
    '. Al guardar se crea una copia.': '. Saving creates a copy.',
    'No se pudieron cargar los proyectos: ': 'Could not load the projects: ',
    'No se pudieron cargar las fotos: ': 'Could not load the photos: ',
    ': al guardar se crea una copia nueva.': ': saving creates a new copy.',
    ': al guardar se crea una copia.': ': saving creates a copy.',
    '¿Sustituir el dossier abierto?': 'Replace the open dossier?',
    'Abrir la biblioteca': 'Open the library',
    'Añadir «Cómo se compra»': 'Add «How to buy»',
    'Anuncio': 'Ad',
    'Archivada': 'Archived',
    'Arriba va la foto REAL del proyecto: elige una foto, no un render.': 'The top half is the project\'s REAL photo: pick a photo, not a render.',
    'Biblioteca': 'Library',
    'Borrador abierto.': 'Draft opened.',
    'Borrador actualizado ✓': 'Draft updated ✓',
    'Borrador actualizado.': 'Draft updated.',
    'Corrígelo y vuelve a intentarlo.': 'Fix it and try again.',
    'Creatividades ▾': 'Creative ▾',
    'descargar': 'download',
    'Dossier ': 'Dossier ',
    'Dossier montado desde la base ✓': 'Dossier built from the database ✓',
    'El 70 % del feed de Lawang': '70% of Lawang\'s feed',
    'El dossier habla de la titularidad: añade la página «Cómo se compra» (menú Creatividades), que explica las dos rutas.': 'The dossier talks about ownership: add the «How to buy» page (Creative menu), which explains both routes.',
    'Elige la foto de la intranet': 'Pick the photo from the intranet',
    'Elige un proyecto.': 'Pick a project.',
    'Elige un proyecto…': 'Pick a project…',
    'Ese dossier no tiene páginas.': 'That dossier has no pages.',
    'Esta pieza no se puede ': 'This piece cannot be ',
    'Esta pieza ya está ': 'This piece is already ',
    'Este dossier no se puede ': 'This dossier cannot be ',
    'Este proyecto no tiene fotos dadas de alta. Súbelas desde Proyectos.': 'This project has no photos yet. Upload them from Projects.',
    'Este proyecto no tiene ningún render dado de alta: «Hoy y proyecto» necesita los dos.': 'This project has no render yet: «Today and project» needs both.',
    'Falta el texto de Legal «Cómo se compra» en la base.': 'Legal\'s «How to buy» text is missing from the database.',
    'Foto de la intranet': 'Photo from the intranet',
    'foto real': 'real photo',
    'Foto real': 'Real photo',
    'Foto real arriba, render abajo': 'Real photo on top, render below',
    'Foto real y render del mismo proyecto': 'Real photo and render of the same project',
    'Foto y una línea': 'Photo and one line',
    'Fotos reales': 'Real photos',
    'Frases que Legal no deja': 'Phrases Legal does not allow',
    'Guardada como borrador.': 'Saved as a draft.',
    'Guardada en Creatividades': 'Saved to Creative',
    'Guardado en Creatividades ✓': 'Saved to Creative ✓',
    'guardar': 'saved',
    'Guardar en Creatividades': 'Save to Creative',
    'Hoy y proyecto': 'Today and project',
    'Idioma de las etiquetas legales': 'Language of the legal labels',
    'Idioma del dossier': 'Dossier language',
    'Imágenes de modelo': 'Model images',
    'Imágenes de proyecto': 'Project images',
    'Ir a la biblioteca': 'Go to the library',
    'Las fotos se suben desde Proyectos. «Solo render» se puede usar, pero la pieza sale marcada como imagen ilustrativa.': 'Photos are uploaded from Projects. «Render only» can be used, but the piece is marked as an illustrative image.',
    'Las páginas actuales se reemplazan por las que salen de la base. Si quieres conservarlas, guárdalo antes.': 'The current pages are replaced by the ones built from the database. To keep them, save it first.',
    'Las páginas salen de lo dado de alta en la intranet: fotos del proyecto, parcelas disponibles, modelos con su precio «desde» y la página «Cómo se compra» de Legal. Sustituye el dossier abierto.': 'The pages come from what is in the intranet: project photos, available plots, models with their «from» price and Legal\'s «How to buy» page. It replaces the open dossier.',
    'Las piezas y los dossiers guardados, con su estado. Lo aprobado lo descargan los comerciales.': 'Saved pieces and dossiers, with their status. Sales agents download what is approved.',
    'Material por proyecto': 'Material by project',
    'Modelos que se ofrecen': 'Models on offer',
    'Montar': 'Build',
    'Montar desde la base': 'Build from the database',
    'Montar desde la base…': 'Build from the database…',
    'No se pudo abrir el dossier: ': 'Could not open the dossier: ',
    'No se pudo abrir la pieza: ': 'Could not open the piece: ',
    'No se pudo montar: ': 'Could not build it: ',
    'no se puede hacer ninguna pieza': 'no piece can be made',
    'Nueva pieza para redes': 'New social piece',
    'Nuevo dossier': 'New dossier',
    'O sube una imagen (solo para descargar)': 'Or upload an image (download only)',
    'Página «Cómo se compra» añadida ✓': '«How to buy» page added ✓',
    'Parcela marcada sobre la aérea': 'Plot marked on the aerial',
    'Piezas': 'Pieces',
    'Piezas para redes y dossiers de cada proyecto, hechos con las fotos y los datos dados de alta en la intranet. Lo aprobado lo pueden descargar los comerciales.': 'Social pieces and dossiers for each project, made with the photos and data in the intranet. Sales agents can download what is approved.',
    'Plano anotado': 'Annotated plan',
    'Portada': 'Cover',
    'proyectos sin una foto real': 'projects without a real photo',
    'Publicada': 'Published',
    'Renders': 'Renders',
    'sin ficha': 'no data sheet',
    'Sin material': 'No material',
    'Solo con render': 'Render only',
    'Tipo de pieza': 'Piece type',
    'Titular grande sobre la foto': 'Big headline over the photo',
    'Titular, precio y botón de WhatsApp': 'Headline, price and WhatsApp button',
    'Todo': 'All',
    'Trayendo la biblioteca…': 'Loading the library…',
    'Una imagen subida a mano se puede descargar, pero no guardar: de un fichero suelto no se sabe de qué proyecto es. Elige la foto en «Foto de la intranet».': 'A hand-uploaded image can be downloaded but not saved: a loose file does not say which project it belongs to. Pick the photo under «Photo from the intranet».',
    'Ver en Creatividades': 'See it in Creative',
    'Ya tiene la página «Cómo se compra».': 'It already has the «How to buy» page.',
    'Abrir para imprimir': 'Open to print',
    'Marcar publicada': 'Mark as published',
    'Archivar': 'Archive',
    'Con render': 'With render',
    'Pieza': 'Piece',
    'del repositorio': 'from the repository',
    'Hecho: ': 'Done: ',
    'Todavía no hay piezas aprobadas para descargar.': 'There are no approved pieces to download yet.',
    'Nada con estos filtros.': 'Nothing with these filters.',
    'La biblioteca está vacía. Crea la primera pieza o monta un dossier desde la base.': 'The library is empty. Create the first piece or build a dossier from the database.',
    'No se pudo leer la biblioteca: ': 'Could not read the library: ',
    'No se pudo leer el material de los proyectos.': 'Could not read the project material.',
    'Listo': 'Ready',
    'Solo render': 'Render only',
    'Modelos sin ninguna imagen (no pueden salir en un dossier): ': 'Models without any image (they cannot appear in a dossier): ',
    'Todos los modelos activos tienen imágenes.': 'All active models have images.',
    'fotos reales': 'real photos',
    'renders': 'renders',
    'modelos con imágenes': 'models with images',
    '¿Archivar «': 'Archive «',
    '¿Aprobar «': 'Approve «',
    'Deja de estar disponible para los comerciales. Las copias que ya se descargaron no se pueden retirar: si es por un motivo legal, avísales.': 'It stops being available to sales agents. Copies already downloaded cannot be withdrawn: if it is for a legal reason, tell them.',
    'Al aprobarla, los comerciales con acceso la pueden descargar y enviar. Ya no se podrá editar: un cambio será una copia nueva.': 'Once approved, sales agents with access can download and send it. It can no longer be edited: a change will be a new copy.',
    'No se pudo descargar: ': 'Could not download: ',
    'No se pudo descargar.': 'Could not download.',
    'Falta la capa de Creatividades en esta página.': 'The Creative layer is missing on this page.',
    'La pieza de siempre: titular, subtítulo, precio opcional y botón de WhatsApp.': 'The usual piece: headline, subtitle, optional price and WhatsApp button.',
    'Foto a sangre con una línea encima, sin botón: en un anuncio el botón lo pone Meta debajo.': 'Full-bleed photo with one line on top, no button: in an ad, Meta adds the button below.',
    'Titular grande. El «Lugar» sale encima como antetítulo.': 'Big headline. The «Place» goes above it as a kicker.',
    'Arriba la foto real; abajo, en gris, el render del MISMO proyecto, marcado como ilustrativo.': 'The real photo on top; below, in grey, the render of the SAME project, marked as illustrative.',
    'Arrastra los cuatro puntos para marcar la parcela. Sale con «plano orientativo, no a escala».': 'Drag the four points to mark the plot. It carries «indicative plan, not to scale».',
    'Firmado por cobrar': 'Signed, to collect',
    'Firmado, cobrado y lo que queda por vender': 'Signed, collected and what is left to sell',
    'Gastos, costes de obra y saldos bancarios: la intranet todavía no los registra.': 'Expenses, construction costs and bank balances: the intranet does not record them yet.',
    'Hay importes en': 'There are amounts in',
    'Hitos sin fecha': 'Milestones without a date',
    'Incluye lo vencido del trimestre en curso. Lo vencido de trimestres anteriores está en «Vencido».': 'Includes what is overdue in the current quarter. Overdue amounts from earlier quarters are under «Overdue».',
    'Lo que debe entrar cada trimestre': 'What should come in each quarter',
    'Lo que este panel no cuenta': 'What this panel does not count',
    'Lo que ha entrado y lo que toca cobrar': 'What has come in and what is due',
    'Lo que ya se debe pagar': 'What is already owed',
    'Los bloques que dependen de eso lo dicen; el resto es correcto.': 'The blocks that depend on it say so; the rest is correct.',
    'Los hitos prometen': 'The milestones promise',
    'Los tramos suman el total: son el mismo dinero repartido por fecha de su hito, no importes distintos.': 'The bands add up to the total: the same money split by milestone date, not separate amounts.',
    'Mes': 'Month',
    'Mes anterior': 'Previous month',
    'Mismo tramo de': 'Same period of',
    'Más adelante': 'Later',
    'Más de 90': 'Over 90',
    'Nada pendiente de pagar en': 'Nothing pending payment in',
    'Ninguna factura en': 'No invoice in',
    'Ninguna unidad con precio en': 'No unit priced in',
    'Ningún cobro este año en': 'No collections this year in',
    'Ningún hito con la fecha pasada': 'No milestone past its date',
    'Ningún proyecto con contratos firmados ni stock en': 'No project with signed contracts or stock in',
    'No cargó el cálculo de finanzas (finanzas.js / logica.js). Recarga la página; si sigue, avisa a Desarrollo.': 'The finance calculation did not load (finanzas.js / logica.js). Reload the page; if it persists, tell Development.',
    'No disponible': 'Not available',
    'No es dinero por entrar: es lo que queda por vender. No se suma con lo firmado.': 'This is not incoming money: it is what is left to sell. It is not added to what is signed.',
    'No hay contratos firmados en': 'No signed contracts in',
    'No hay nada firmado pendiente de cobro en': 'Nothing signed pending collection in',
    'No se convierten ni se suman entre sí: elige la moneda arriba.': 'They are not converted or added together: choose the currency above.',
    'No se pudieron leer': 'Could not read',
    'No se pudieron leer los recibís': 'Could not read the receipts',
    'No se pudo calcular la cartera': 'Could not calculate the portfolio',
    'No se pudo cargar': 'Could not load',
    'No se pudo cargar el panel. Recarga la página; si sigue, avisa a Desarrollo.': 'Could not load the panel. Reload the page; if it persists, tell Development.',
    'No se pudo cargar la cartera ni las unidades.': 'Could not load the portfolio or the units.',
    'Por cobrar': 'To collect',
    'Por trimestre': 'By quarter',
    'Previsto': 'Expected',
    'Previsto por calendario': 'Expected per schedule',
    'Próximos 30 días': 'Next 30 days',
    'Recarga la página; si sigue, avisa a Desarrollo.': 'Reload the page; if it persists, tell Development.',
    'Reservada': 'Reserved',
    'Salidas comprometidas': 'Committed outflows',
    'Se solapa con «Firmado por cobrar» (una factura reclama un hito): no se suman.': 'Overlaps with «Signed, to collect» (an invoice claims a milestone): do not add them.',
    'Sin calendario firmado en': 'No signed schedule in',
    'Sin calendario que lo explique': 'Not covered by a schedule',
    'Sin cobros en el mismo tramo de': 'No collections in the same period of',
    'Sin permiso para ver esta cifra: hace falta tener asignadas «Pagos de Lawang» y «Reparto a closers» en Usuarios. No es que no se deba nada: es que esta sesión no lo puede ver.': 'No permission to see this figure: it needs «Pagos de Lawang» and «Reparto a closers» assigned in Users. It does not mean nothing is owed: this session cannot see it.',
    'Sin sesión: no se carga nada.': 'No session: nothing is loaded.',
    'Solicitudes de pago vivas': 'Open payment requests',
    'Solicitudes de pago vivas y comisiones devengadas que aún no tienen solicitud. Una comisión con solicitud se cuenta una sola vez.': 'Open payment requests and accrued commissions that have no request yet. A commission with a request is counted only once.',
    'Solo contratos firmados. Un proyecto sin ventas firmadas aparece igual si tiene unidades disponibles.': 'Signed contracts only. A project with no signed sales still appears if it has available units.',
    'Stock': 'Stock',
    'Stock disponible': 'Available stock',
    'Trayendo los cobros…': 'Loading collections…',
    'Unidades': 'Units',
    'Unidades por estado, a precio de lista': 'Units by status, at list price',
    'Valor de lista': 'List value',
    'Vencido sin cobrar': 'Overdue, not collected',
    'Vendida': 'Sold',
    'Ver en Comisiones': 'See in Commissions',
    'Ver hito a hito': 'See each milestone',
    'Ver los datos en tabla': 'See the data as a table',
    'calendarios cuyos porcentajes no suman 100 %.': 'schedules whose percentages do not add up to 100 %.',
    'contratos firmados sin calendario de pagos: su pendiente sale en «Sin calendario que lo explique».': 'signed contracts without a payment schedule: their outstanding amount is under «Not covered by a schedule».',
    'contratos firmados y liberados (venta caída), por': 'signed and released contracts (sale fell through), for',
    'contratos sin firmar: todavía no son un compromiso y no suman a lo firmado (lo que ya cobraron sí cuenta).': 'unsigned contracts: not a commitment yet and not added to what is signed (what they have collected does count).',
    'el calendario': 'the schedule',
    'en curso': 'in progress',
    'factura': 'invoice',
    'facturas': 'invoices',
    'firmados': 'signed',
    'hito con la fecha pasada': 'milestone past its date',
    'hitos': 'milestones',
    'hitos con la fecha pasada': 'milestones past their date',
    'hitos no tienen importe ni porcentaje y no se pueden sumar.': 'milestones have no amount or percentage and cannot be added.',
    'la cartera': 'the portfolio',
    'las solicitudes y comisiones': 'the requests and commissions',
    'las unidades': 'the units',
    'lo pendiente de las facturas': 'the outstanding invoice amounts',
    'lo que queda': 'remaining',
    'los recibís': 'the receipts',
    'más de lo que queda por cobrar: algún calendario no descuenta lo ya pagado. La previsión está inflada en esa cifra; revisa los calendarios en Vencimientos.': 'more than what is left to collect: some schedule does not deduct what has been paid. The forecast is inflated by that amount; check the schedules in Due dates.',
    'no se le deben a nadie.': 'nobody owes them.',
    'o desde su emisión si no lo tiene': 'or from its issue date if it has none',
    'queda por cobrar.': 'is left to collect.',
    'son de contratos todavía sin firmar, que no cuentan en «Firmado por cobrar».': 'belong to contracts not yet signed, which do not count in «Signed, to collect».',
    'unidades sin precio no suman valor.': 'units without a price add no value.',
    'ene': 'Jan', 'feb': 'Feb', 'mar': 'Mar', 'abr': 'Apr', 'may': 'May', 'jun': 'Jun',
    'jul': 'Jul', 'ago': 'Aug', 'sep': 'Sep', 'oct': 'Oct', 'nov': 'Nov', 'dic': 'Dec',

    /* ---------- acciones: los botones de toda la suite ---------- */
    'Guardar': 'Save',
    'Guardar cambios': 'Save changes',
    'Guardar en base de datos': 'Save to database',
    'Cancelar': 'Cancel',
    'Cerrar': 'Close',
    'Borrar': 'Delete',
    'Editar': 'Edit',
    'Editar datos': 'Edit details',
    'Editar nombre': 'Edit name',
    'Enviar': 'Send',
    'Enviar por email': 'Send by email',
    'Descargar': 'Download',
    'Descargar PDF': 'Download PDF',
    'Descargar borrador': 'Download draft',
    'PDF para que el comprador lo revise: sello de borrador, sin firmas ni datos bancarios': 'PDF for the buyer to review: draft stamp, no signatures or bank details',
    'El contrato está firmado: ya no hay borrador, descarga el PDF firmado': 'The contract is signed: there is no draft any more, download the signed PDF',
    'Volver': 'Back',
    'Aceptar': 'OK',
    'Añadir': 'Add',
    'Quitar': 'Remove',
    'Duplicar': 'Duplicate',
    'Buscar': 'Search',
    'Ver': 'View',
    'Abrir': 'Open',
    'Copiar': 'Copy',
    'Copiado': 'Copied',
    'Continuar': 'Continue',
    'Reintentar': 'Try again',

    /* ---------- estados y palabras de tabla que se repiten ---------- */
    'Estado': 'Status',
    'Tipo': 'Type',
    'Fecha': 'Date',
    'Cuándo': 'When',
    'Importe': 'Amount',
    'Total': 'Total',
    'Nombre': 'Name',
    'Email': 'Email',
    'Teléfono': 'Phone',
    'Proyecto': 'Project',
    'Unidad': 'Unit',
    'Comprador': 'Buyer',
    'Compradores': 'Buyers',
    'Contrato': 'Contract',
    'Contratos': 'Contracts',
    'Notas': 'Notes',
    'Nota': 'Note',
    'Todos': 'All',
    'Todas': 'All',
    'Ninguno': 'None',
    'Ninguna': 'None',
    'Otros': 'Other',
    'Sin nombre': 'No name',
    'sin nombre': 'no name',
    'Sin fecha': 'No date',
    'sin fecha': 'no date',
    'sin proyecto': 'no project',
    'sin comprador': 'no buyer',
    'sin nº': 'no number',
    'no se sabe': 'unknown',
    'Cargando…': 'Loading…',
    'Pendiente': 'Pending',
    'Pagado': 'Paid',
    'Vencido': 'Overdue',
    'Abierto': 'Open',
    'Abiertos': 'Open',
    'Resuelto': 'Resolved',
    'Resueltos': 'Resolved',
    'Sin firmar': 'Unsigned',
    'Firmado': 'Signed',
    'Contrato firmado': 'Signed contract',

    /* ---------- mensajes de error y de confirmación compartidos ----------
       El sufijo «: » va DENTRO de la clave porque el mensaje de la base se
       concatena después; sin él la frase en inglés quedaría sin puntuación. */
    'No se pudo guardar: ': 'Could not save: ',
    'No se pudo guardar:': 'Could not save:',
    'No se pudo borrar: ': 'Could not delete: ',
    'No se pudo borrar:': 'Could not delete:',
    'No se pudo enviar: ': 'Could not send: ',
    'No se pudo enviar:': 'Could not send:',
    'No se pudo cerrar: ': 'Could not close: ',
    'No se pudo cambiar el estado: ': 'Could not change the status: ',
    'No se pudo cargar: ': 'Could not load: ',
    'No se pudo: ': 'Could not: ',
    'Guardado': 'Saved',
    'Borrado': 'Deleted',
    'Enviado': 'Sent',
    'Nada que enseñar con este filtro.': 'Nothing to show with this filter.',
    'Prueba a quitar algún filtro.': 'Try removing a filter.',
    'Esto no se puede deshacer.': 'This cannot be undone.',
    'Tu sesión ha caducado. Vuelve a entrar.': 'Your session has expired. Please log in again.',

    /* ---------- toast de guardarContrato() al traspasar Carta de Reserva
       (17-sep-2026) — mismo vocabulario que el .sui-aviso persistente de
       hitos_fechas.js ("paid under the Letter", "left over", "cannot
       absorb"), aquí como fragmentos porque el toast se concatena con el
       importe/número reales, no una frase entera. Hallazgo code-review: la
       primera versión no tenía entrada EN y se quedaba en español para un
       agente en inglés. */
    'se ha descontado': 'deducted',
    'Esa fecha no existe (¿31 de un mes de 30 días?): el hito se queda sin vencimiento hasta que la corrijas': 'That date does not exist (the 31st of a 30-day month?): the milestone has no due date until you fix it',
    'ya cobrado en': 'already paid under',
    'sobran': 'left over:',
    'cobrados en la Carta que este Bloqueo no puede absorber': 'paid under the Letter, which this Deed cannot absorb',

    /* ---------- dialogo.js: parar al usuario y elegir de una lista ---------- */
    '¿Seguimos?': 'Are you sure?',
    'Elige una opción': 'Choose an option',
    'Escribe para buscar…': 'Type to search…',
    'Pulsa para elegir': 'Click to choose',
    'Nada coincide con «%q»': 'Nothing matches “%q”',

    /* ---------- topbar.js: lo que le quedaba suelto ---------- */
    'Plegar o desplegar el menú': 'Collapse or expand the menu',
    'Buscar herramienta…': 'Search tools…',

    /* ---------- herramientas.js: grupos del menú y del hub ---------- */
    'Seguimiento': 'Pipeline',
    'Administración': 'Administration',
    'Base de datos': 'Database',
    'Base de Datos': 'Database',           // así la escribió Stitch en la cabecera de la sidebar v4
    'Sociedades emisoras': 'Issuing companies',
    'Equipo': 'Team',

    /* ---------- herramientas.js: nombre de cada herramienta ---------- */
    'CRM': 'CRM',
    'Ranking de closers': 'Closer leaderboard',
    'Reparto de leads': 'Lead routing',
    'Agenda de cierre': 'Closing calendar',
    'Operaciones': 'Deals',
    'Soporte': 'Support',
    'Vencimientos': 'Payment schedule',
    'Creatividades': 'Creative',
    'Documentación': 'Documents',
    'Facturas': 'Invoices',
    'Recibos': 'Receipts',
    'Solicitudes': 'Payment requests',
    'Proyectos': 'Projects',
    'Proyectos (nueva vista)': 'Projects (new view)',
    'Modelos': 'House models',
    'Obra': 'Construction',
    'Usuarios': 'Users',
    /* Herramientas nacidas en la v4 (21-sep-2026, S20): «Comisiones» del
       equipo de ventas, y el grupo «Panel de control» (Cuentas, Equipos de
       venta, Condiciones, Comisión de administración) — nav.js las inyecta
       por texto, herramientas.js ya trae el nombre canónico de las dos
       últimas (líneas 187 y 254), aquí solo faltaba la traducción. */
    'Comisiones': 'Commissions',
    'Panel de control': 'Control panel',
    'Cuentas': 'Accounts',
    'Equipos de venta': 'Sales teams',
    'Condiciones': 'Terms',
    'Comisión de administración': 'Administration commission',
    'Idioma': 'Language',
    'Cerrar Sesión': 'Log out',
    'Notificaciones': 'Notifications',
    /* ---------- v4/operaciones/ rehecha (22-sep-2026): una fila por operación ---------- */
    'Una fila por venta: la Carta de Reserva, el Bloqueo de Parcela y la Construcción del mismo comprador van juntas, con el dinero de toda la cadena. Pulsa una fila para abrir su ficha.':
      'One row per sale: the Reservation Letter, the Plot Blocking and the Construction contract of the same buyer go together, with the money of the whole chain. Click a row to open its sheet.',
    'Nueva operación': 'New deal',
    'Pendiente de cobro': 'Outstanding',
    'Buscar comprador, nº de contrato, proyecto o parcela…': 'Search buyer, contract no., project or plot…',
    'Trayendo las operaciones…': 'Loading the operations…',
    'Mostrando': 'Showing',
    'de': 'of',
    'operaciones': 'operations',
    'visibles': 'shown',
    'con contrato firmado': 'with a signed contract',
    'filtro': 'filter',
    'Suma en euros de lo que ves. Las Cartas de Reserva no suman precio.': 'Sum in euros of what you see. Reservation Letters add no price.',
    'en otra moneda quedan fuera.': 'in another currency are left out.',
    'del precio, por recibís': 'of the price, by receipts',
    'sin precio con el que comparar': 'no price to compare against',
    'Lo que falta por cobrar de las operaciones con contrato firmado.': 'What is still to be collected on operations with a signed contract.',
    'Firmadas sin facturar': 'Signed, not invoiced',
    'Reserva liberada': 'Reservation released',
    'Liberadas': 'Released',
    'Reserva sin señal cobrada': 'Reservation, deposit not collected',
    'Falta precio': 'Price missing',
    'Firma caduca en < 48 h': 'Signature expires in < 48 h',
    'liberada': 'released',
    'en firma': 'out for signature',
    'reabierto': 'reopened',
    'Todavía no hay operaciones.': 'No operations yet.',
    'La lista está recortada al tope de': 'The list is capped at',
    'los totales son parciales. Pide a Desarrollo subir el tope.': 'totals are partial. Ask Development to raise the cap.',
    'No encuentro el contrato': 'Cannot find contract',
    'entre los cargados.': 'among those loaded.',
    'Ver en Operaciones': 'See in Operations',
    'Maqueta v4 · datos ficticios': 'v4 mockup · sample data',

    /* ---------- v4/comision-admin/: la pantalla entera ya llevaba data-lwt
       de antes de S20, solo faltaba el diccionario ---------- */
    'Un porcentaje sobre todo el dinero que entra por la intranet, sin excepciones. Se devenga solo, recibí a recibí, y cada línea guarda congelado el porcentaje que le tocó: editar la tarifa no reescribe lo ya devengado salvo que se pida. No tiene nada que ver con la comisión del equipo de ventas.':
      'A percentage of every euro that comes in through the intranet, no exceptions. It accrues on its own, receipt by receipt, and each line keeps the percentage that applied to it frozen: editing the rate does not rewrite what has already accrued unless asked to. It has nothing to do with the sales team commission.',
    'Nueva tarifa': 'New rate',
    'Tarifa vigente': 'Current rate',
    'Devengado este mes': 'Accrued this month',
    'Pendiente de facturar': 'Pending invoicing',
    'Para revisar': 'To review',
    'Tarifas': 'Rates',
    'El porcentaje y desde cuándo rige': 'The percentage and since when it applies',
    'Se puede editar una tarifa o añadir otra con su fecha. Editar guarda antes la versión anterior, así que siempre se puede decir qué porcentaje regía el día que entró cada euro.':
      'A rate can be edited or a new one added with its date. Editing keeps the previous version first, so it is always possible to tell which percentage applied the day each euro came in.',
    'Rige desde': 'In effect since',
    'Acción': 'Action',
    'Trayendo las tarifas…': 'Loading the rates…',
    'Por sociedad': 'By company',
    'Cada empresa, su propia cuenta': 'Each company, its own account',
    'Cada sociedad es un deudor distinto y se le factura por separado. Nunca se suman entre sí, ni tampoco entre monedas.':
      'Each company is a separate debtor and is invoiced separately. They are never added together, nor across currencies.',
    'Sociedad': 'Company',
    'Entradas': 'Entries',
    'Dinero entrado': 'Money in',
    'Comisión devengada': 'Commission accrued',
    'Trayendo el reparto por sociedad…': 'Loading the split by company…',
    'Libro': 'Ledger',
    'Una línea por cada entrada de dinero': 'One line per money-in entry',
    'Todas las sociedades': 'All companies',
    'Todos los estados': 'All statuses',
    'Cobrada': 'Collected',
    'Exenta': 'Exempt',
    'Todos los meses': 'All months',
    'Comisión': 'Commission',
    'Trayendo el libro…': 'Loading the ledger…',
    'Los importes son brutos, antes de cualquier retención. Un abono (importe negativo) es la vuelta de una comisión cuyo recibí se anuló o se borró; un ajuste es la diferencia cuando el recibí cambió de importe después de facturarse.':
      'Amounts are gross, before any withholding. A credit (negative amount) is the reversal of a commission whose receipt was voided or deleted; an adjustment is the difference when the receipt changed amount after being invoiced.',

    /* ---------- Soporte ---------- */
    'Buscar comprador…': 'Search buyer…',
    'Ticket': 'Ticket',
    'Último mensaje': 'Last message',
    'No se pudieron leer los tickets: ': 'Could not load the tickets: ',
    'Tú: ': 'You: ',
    'Equipo': 'Team',
    'Responder…': 'Reply…',
    'Marcar resuelto': 'Mark as resolved',
    'Reabrir': 'Reopen',
    'Marcado como resuelto': 'Marked as resolved',
    'Reabierto': 'Reopened',
    'Escribe a través de la intranet, igual que él ve tu respuesta en su área de clientes.':
      'You are writing through the intranet, the same way they see your reply in their client area.',

    /* ---------- Obra ----------
       El NOMBRE de cada fase no está aquí: `obra_fases` ya tiene columna `en`
       con las siete rellenas, y el dato manda sobre el diccionario. */
    'Buscar código, proyecto o contrato…': 'Search code, project or contract…',
    'Todos los proyectos': 'All projects',
    'Código': 'Code',
    'Fase': 'Stage',
    'Fase actual': 'Current stage',
    'Entrega est.': 'Est. handover',
    'Entrega estimada': 'Estimated handover',
    'Fotos': 'Photos',
    'Fotos (%n)': 'Photos (%n)',
    'Actualizado': 'Updated',
    'En obra': 'Under construction',
    'Con contrato': 'With contract',
    'sin empezar': 'not started',
    '— sin empezar —': '— not started —',
    'Contrato %n': 'Contract %n',
    'Lo que marques aquí lo ve el comprador en su portal.':
      'Whatever you set here is what the buyer sees in their portal.',
    'Sin contrato vinculado: aún no lo ve ningún comprador.':
      'No contract linked: no buyer can see this yet.',
    'Subir fotos — se optimizan solas a tamaño web':
      'Upload photos — they are resized for web automatically',
    'Puedes documentar la obra igualmente: cuando la unidad se vincule a un contrato, el comprador verá el histórico completo.':
      'You can document the work anyway: once the unit is linked to a contract, the buyer will see the full history.',
    'Sin título': 'Untitled',
    'Título': 'Title',
    'Ocultar': 'Hide',
    'Mostrar': 'Show',
    'no se pudo convertir': 'could not be converted',
    'imagen ilegible': 'unreadable image',
    'sin permiso para la herramienta Obra': 'no permission for the Construction tool',
    '%n foto subida': '%n photo uploaded',
    '%n fotos subidas': '%n photos uploaded',
    'Título de la foto (lo ve el comprador):': 'Photo title (the buyer sees it):',
    'Borrar esta foto': 'Delete this photo',
    'Se quita también del portal del comprador. Esto no se puede deshacer.':
      'It is removed from the buyer portal too. This cannot be undone.',

    /* ---------- Solicitudes de pago ----------
       Ojo con el vocabulario: aquí «solicitud» es una PETICIÓN DE COBRO del
       agente a Lawang (comisión, pago acordado), no una solicitud de compra.
       En inglés eso es «payment request», nunca «application». */
    'Nueva solicitud': 'New request',
    'Nueva solicitud de pago': 'New payment request',
    'Editar SP-%n': 'Edit SP-%n',
    'Buscar concepto, contrato o compañero…': 'Search description, contract or colleague…',
    'Nº': 'No.',
    'Quién pide': 'Requested by',
    'Concepto': 'Description',
    'De la venta': 'From sale',
    'Moneda': 'Currency',
    'Pendientes': 'Pending',
    'Por pagar': 'To pay',
    'Aprobada': 'Approved',
    'Rechazada': 'Rejected',
    'Anulada': 'Cancelled',
    'Pagada': 'Paid',
    'Aprobar': 'Approve',
    'Rechazar…': 'Reject…',
    'Anular': 'Cancel request',
    'Marcar pagada…': 'Mark as paid…',
    'Crear solicitud': 'Create request',
    'Todos los agentes': 'All agents',
    'No se pudieron leer las solicitudes: ': 'Could not load the requests: ',
    'Tú': 'You',
    'contrato': 'contract',
    '%n pendiente de resolver': '%n awaiting your decision',
    '%n pendientes de resolver': '%n awaiting your decision',
    '%n aprobada por pagar': '%n approved, unpaid',
    '%n aprobadas por pagar': '%n approved, unpaid',
    'hace %n d': '%n d ago',
    'Fecha límite': 'Due date',
    'Fecha límite (opcional)': 'Due date (optional)',
    'Pedida': 'Requested',
    'Resolución': 'Decision',
    'Motivo': 'Reason',
    'Motivo del rechazo': 'Reason for rejection',
    'Resuelta por': 'Decided by',
    'Pagada por': 'Paid by',
    'Referencia del pago': 'Payment reference',
    'el pago se hace fuera (transferencia); aquí queda pedido, aprobado y pagado.':
      'the payment happens outside (bank transfer); this records the request, the approval and the payment.',
    'Solicitud aprobada — queda por pagar': 'Request approved — pending payment',
    'Marcada como pagada': 'Marked as paid',
    'Solicitud rechazada': 'Request rejected',
    'Solicitud anulada': 'Request cancelled',
    'Se le enseña al compañero tal cual — di qué falta o por qué no procede':
      'Your colleague sees this as written — say what is missing or why it does not apply',
    'Rechazar la solicitud': 'Reject the request',
    'El motivo es obligatorio: sin él la base no acepta el rechazo.':
      'A reason is required: without one the database will not accept the rejection.',
    'Cómo se ha pagado — transferencia, Wise, fecha… (opcional, pero al compañero le llega en el aviso)':
      'How it was paid — bank transfer, Wise, date… (optional, but your colleague gets it in the notification)',
    'Confirmar: pagada': 'Confirm: paid',
    'Anular la solicitud': 'Cancel the request',
    'SP-%n quedará anulada. No se borra: el registro se queda, sin efecto.':
      'SP-%n will be cancelled. It is not deleted: the record stays, with no effect.',
    'Pide un pago a Lawang — una comisión, un pago acordado. Administración lo aprueba y lo paga.':
      'Request a payment from Lawang — a commission, an agreed payment. Administration approves and pays it.',
    'Concepto — qué pago estás pidiendo': 'Description — what payment you are requesting',
    'Comisión venta W3.1-D1 · pago acordado septiembre…':
      'Commission on sale W3.1-D1 · agreed payment September…',
    'De qué venta viene, si viene de una (opcional)': 'Which sale it comes from, if any (optional)',
    'Elegir contrato…': 'Choose a contract…',
    '— Sin venta asociada —': '— No sale linked —',
    'La venta de la que viene el pago': 'The sale this payment comes from',
    'Nota para Administración (opcional)': 'Note for Administration (optional)',
    'El concepto no puede quedar vacío': 'The description cannot be empty',
    'El importe no se entiende — escribe un número mayor que cero':
      'The amount is not valid — enter a number greater than zero',
    'Solicitud actualizada': 'Request updated',
    'Solicitud creada — Administración ya tiene el aviso':
      'Request created — Administration has been notified',
    'Resueltas': 'Closed',

    /* ---------- Modelos (catálogo de tipos de vivienda) ----------
       Vocabulario fijado aquí y reutilizado por Proyectos y por Contratos:
       modelo = house model · techo = roof type · extra = add-on ·
       alcance de obra = scope of work · precio de catálogo = catalogue price.
       «Villa» y «Terraza» se quedan igual: son las mismas palabras en inglés
       y ya se usan así en la web pública. */
    'Nuevo modelo': 'New model',
    'Buscar modelo…': 'Search model…',
    'Publicados y no publicados': 'Published and unpublished',
    'Solo publicados en la web': 'Published on the website only',
    'Solo sin publicar': 'Unpublished only',
    '%n modelo': '%n model',
    '%n modelos': '%n models',
    '%n publicado en la web': '%n published on the website',
    '%n publicados en la web': '%n published on the website',
    '%n en la vista': '%n in view',
    'Ningún modelo con ese filtro.': 'No model matches that filter.',
    '%n dorm': '%n bed',
    '%n baños': '%n baths',
    'sin specs': 'no specs',
    'sin precio de catálogo': 'no catalogue price',
    'en la web': 'live',
    'sin publicar': 'unpublished',
    '%n proyecto': '%n project',
    '%n proyectos': '%n projects',
    '%n doc': '%n doc',
    '%n docs': '%n docs',
    'Publicado en /modelo/%s': 'Published at /modelo/%s',
    'No sale en la web': 'Not on the website',
    'renders pendientes': 'renders pending',
    'Ficha': 'Details',
    'Dormitorios': 'Bedrooms',
    'Baños': 'Bathrooms',
    'Villa': 'Villa',
    'Terraza': 'Terrace',
    'Villa (m²)': 'Villa (m²)',
    'Terraza (m²)': 'Terrace (m²)',
    'Descripción': 'Description',
    'Dirección en la web': 'Website address',
    '— cambiarla rompe los enlaces que ya estén publicados.':
      '— changing it breaks any links already published.',
    'Precio de construcción (catálogo)': 'Construction price (catalogue)',
    'Precio de catálogo': 'Catalogue price',
    'Construcción': 'Construction',
    'Techos': 'Roof types',
    'desde 2027: ': 'from 2027: ',
    'Sin variantes de techo. El precio de catálogo es el único.':
      'No roof variants. The catalogue price is the only one.',
    'Cuál de los dos precios está vigente lo decide el reloj del servidor, nunca un ajuste a mano.':
      'Which of the two prices applies is decided by the server clock, never by a manual switch.',
    'Este modelo no tiene variantes de techo.': 'This model has no roof variants.',
    'Primera columna: precio de hoy. Segunda: desde el 1-ene-2027.':
      'First column: today’s price. Second: from 1 Jan 2027.',
    'Precio de %s ahora': 'Price of %s now',
    'Precio de %s desde 2027': 'Price of %s from 2027',
    'Precio de %s': 'Price of %s',
    'Precio en %s': 'Price in %s',
    'Extras': 'Add-ons',
    'Extras disponibles': 'Available add-ons',
    'Ninguno dado de alta todavía.': 'None added yet.',
    'se ofrece': 'offered',
    'Sin precio, el extra no se ofrece en la web: no se estima a ojo.':
      'With no price the add-on is not offered on the website: it is never estimated by eye.',
    'Alcance de obra': 'Scope of work',
    'Incluido': 'Included',
    'No incluido': 'Not included',
    'Sin alcance de obra. Solo se rellena con lo verificado en el':
      'No scope of work. It is only filled in from what is verified in the',
    'anexo de obra de este modelo': 'construction annex of this model',
    ': copiarlo de otro es publicar un contrato que nadie ha firmado.':
      ': copying it from another one means publishing a contract nobody signed.',
    'Una línea por punto. Es lo que la ficha publica como «Included» y «Not included», así que':
      'One line per item. This is what the website publishes as “Included” and “Not included”, so',
    'solo se escribe lo que diga el anexo de obra de ESTE modelo':
      'only write what the construction annex of THIS model says',
    '. Copiarlo de otro modelo es publicar un contrato que nadie ha firmado.':
      '. Copying it from another model means publishing a contract nobody signed.',
    'Precio por proyecto': 'Price by project',
    'Vacío significa': 'Empty means',
    'hereda del catálogo': 'inherits the catalogue price',
    ', no «sin dato». Solo se rellena cuando ese proyecto tiene un precio propio pactado.':
      ', not “no data”. Fill it in only when that project has its own agreed price.',
    'heredado': 'inherited',
    'propio': 'own price',
    'Este modelo no está declarado en ningún proyecto todavía.':
      'This model is not declared in any project yet.',
    'Este modelo no está declarado en ningún proyecto.':
      'This model is not declared in any project.',
    'Dejar vacío = hereda el precio de catálogo. Rellenar solo si ese proyecto tiene precio propio pactado.':
      'Leave empty = inherits the catalogue price. Fill it in only if that project has its own agreed price.',
    'hereda %s': 'inherits %s',
    'Añadir a un proyecto…': 'Add to a project…',
    'Declararlo en un proyecto es lo que hace que aparezca en el desplegable de sus parcelas.':
      'Declaring it in a project is what makes it appear in that project’s plot dropdown.',
    'Es el nivel 1 de la cascada: lo heredan todos los proyectos que no tengan precio propio, y es lo que publica la web como «desde».':
      'This is level 1 of the cascade: every project without its own price inherits it, and it is what the website publishes as “from”.',
    'Documentos': 'Documents',
    'visible para el comprador': 'visible to the buyer',
    'Sin planos ni memoria de calidades todavía.':
      'No floor plans or specification sheets yet.',
    'Tipo de documento': 'Document type',
    'Plano · anexo del contrato': 'Floor plan · contract annex',
    'Memoria de calidades': 'Specification sheet',
    'Render': 'Render',
    'Otro': 'Other',
    'Añadir documento': 'Add document',
    'PDF o imagen, hasta 50 MB. Nace privado: que lo vea el comprador se decide fichero a fichero.':
      'PDF or image, up to 50 MB. Private by default: whether the buyer sees it is decided file by file.',
    'El de tipo': 'The one of type',
    'es el que el contrato de Construcción adjunta solo al elegir este modelo (el más reciente si hay varios). Sin ninguno, se sigue usando el PDF que el estudio tenga en el repo.':
      'is the one the Construction contract attaches automatically when this model is chosen (the most recent one if there are several). With none, the PDF held in the studio repo is used instead.',
    'Subiendo…': 'Uploading…',
    'Documento añadido': 'Document added',
    'El fichero pasa de 50 MB': 'The file is over 50 MB',
    'No se ha subido:': 'Not uploaded:',
    'No se ha guardado la ficha del documento:': 'The document record was not saved:',
    'No se ha podido abrir:': 'Could not open:',
    'sin enlace': 'no link',
    'No se ha podido cargar: ': 'Could not load: ',
    'Publicación': 'Publishing',
    'Activo (si se desmarca, deja de ofrecerse en toda la suite)':
      'Active (unchecked, it stops being offered across the whole suite)',
    'Renders pendientes — la ficha dirá «Renders in progress» en vez de enseñar una foto de otro modelo':
      'Renders pending — the page will say “Renders in progress” instead of showing a photo of another model',
    'Notas internas': 'Internal notes',
    'No sale nunca en la web: el RPC público no las devuelve.':
      'Never shown on the website: the public RPC does not return them.',
    'Editar datos': 'Edit details',
    'Los precios y las specs los edita un administrador. Tú sí puedes subir documentos.':
      'Prices and specs are edited by an administrator. You can still upload documents.',
    'Renombrar': 'Rename',
    'Renombrar «%a» a «%b»': 'Rename “%a” to “%b”',
    'El nombre nuevo se propaga solo a': 'The new name propagates on its own to',
    '%n unidad': '%n unit',
    '%n unidades': '%n units',
    'y a sus precios por proyecto. Lo ya impreso en un documento firmado no se toca.':
      'and to its per-project prices. Anything already printed on a signed document is untouched.',
    'El nombre no puede quedar vacío': 'The name cannot be empty',
    'La dirección solo admite minúsculas, números y guiones':
      'The address only accepts lowercase letters, numbers and hyphens',
    'Ya hay un modelo en esa dirección': 'There is already a model at that address',
    'No se ha guardado: ': 'Not saved: ',
    'No se ha guardado: cambiar precios y specs es de administrador.':
      'Not saved: changing prices and specs is for administrators.',
    'Dar de alta un modelo es de administrador': 'Creating a model is for administrators',
    'Tu ficha entra en Modelos para consultar y para subir documentos. Crear un modelo o cambiar un precio lo hace un administrador.':
      'Your account can open Models to look things up and to upload documents. Creating a model or changing a price is done by an administrator.',
    'Entendido': 'Got it',
    'Nace sin publicar. Las specs, los techos y los extras se rellenan después.':
      'It starts unpublished. Specs, roof types and add-ons are filled in afterwards.',
    'Dune, Granada…': 'Dune, Granada…',
    'Se rellena sola desde el nombre. Solo minúsculas, números y guiones.':
      'Filled in automatically from the name. Lowercase letters, numbers and hyphens only.',
    'IDR solo para los proyectos que llevan el inventario en rupias (Riverfront).':
      'IDR only for the projects whose inventory is kept in rupiah (Riverfront).',
    'Si el inventario ya usa este nombre, las unidades que lo nombran se enganchan solas al guardar: el enlace lo ata el propio trigger de la base.':
      'If the inventory already uses this name, the units naming it link themselves on save: the database trigger ties the link.',
    'Hacen falta el nombre y la dirección': 'The name and the address are required',
    'Crear': 'Create',
    'No se ha creado: ': 'Not created: ',
    'No se ha creado: dar de alta un modelo es de administrador.':
      'Not created: creating a model is for administrators.',
    'Modelo creado. Ahora sus datos.': 'Model created. Now its details.',
    'Se resuelve dando de alta el modelo con ese nombre, o corrigiendo el nombre en Proyectos. Mientras tanto se quedan como están, que es lo correcto.':
      'Fix it by creating the model under that name, or by correcting the name in Projects. In the meantime they stay as they are, which is the right thing.',

    /* ---------- Usuarios ----------
       Los nombres de rol se traducen como ROTULO; la clave (`agente`,
       `sales_manager`…) es la de la base y la de la edge `admin-usuarios`, y
       no aparece aquí a propósito. «Sales manager» y «Project manager» ya
       estaban en inglés en el original: el equipo los llama así. */
    'Buscar nombre, email o rol…': 'Search name, email or role…',
    'Nuevo usuario': 'New user',
    'Elige un usuario': 'Choose a user',
    'Nadie con «%q».': 'Nobody matching “%q”.',
    'por %s': 'by %s',
    'Agente': 'Agent',
    'Sales manager': 'Sales manager',
    'Project manager': 'Project manager',
    'Administrador': 'Administrator',
    'Super admin': 'Super admin',
    'Rol': 'Role',
    'Identidad y rol': 'Identity and role',
    'Acceso': 'Access',
    'Activo': 'Active',
    'Desactivado — no entra a la suite': 'Deactivated — cannot enter the suite',
    'Desactivar es lo contrario de borrar: la persona deja de entrar pero se conserva qué documentos creó. Nunca se borra un usuario.':
      'Deactivating is the opposite of deleting: the person can no longer log in, but the record of what they created is kept. A user is never deleted.',
    'Esta es tu propia cuenta. Para no dejarte fuera por accidente, no puedes desactivarte ni cambiarte el rol desde aquí.':
      'This is your own account. So you cannot lock yourself out by accident, you cannot deactivate yourself or change your own role here.',
    'Solo un super admin puede modificar la cuenta de otro super admin.':
      'Only a super admin can modify another super admin’s account.',
    'Un': 'A',
    'Nace': 'Starts as',
    've las herramientas que le marques abajo (igual que un agente, no todas por defecto) y puede editar los documentos de cualquiera dentro de ellas. Un':
      'sees the tools you tick below (like an agent — not all of them by default) and can edit anyone’s documents inside them. A',
    've, crea y corrige contratos y facturas de': 'sees, creates and corrects contracts and invoices for',
    'vende él mismo': 'sells directly too',
    'sin ningún proyecto asignado': 'with no project assigned',
    'se marca desde la ficha de cada proyecto en': 'is set from each project’s record in',
    'todavía.': 'yet.',
    '. Solo un': '. Only a',
    '. La consulta de datos ya emitidos sigue abierta a todo el equipo: Operaciones cruza contratos, facturas y firmas, y filtrarlas por herramienta la dejaría en blanco.':
      '. Reading data already issued stays open to the whole team: Deals cross-references contracts, invoices and signatures, and filtering it by tool would leave it blank.',
    'Herramientas que ve': 'Tools they see',
    'Herramientas que verá': 'Tools they will see',
    'Controla lo que aparece en la intranet y lo que puede':
      'Controls what appears in the intranet and what they can',
    'Permisos actualizados': 'Permissions updated',
    'CRM de leads': 'Lead CRM',
    'Cuatro llaves distintas y a propósito:': 'Four separate keys, on purpose:',
    'Leads': 'Leads',
    'abre los datos de contacto de las personas que dejan su teléfono;':
      'opens the contact details of the people who leave their phone number;',
    'Ranking': 'Leaderboard',
    ', las cifras de cada comercial;': ', each rep’s figures;',
    'Reparto': 'Routing',
    ', quién atiende cada campaña;': ', who handles each campaign;',
    'Agenda': 'Calendar',
    ', las llamadas de venta. Quien tenga Ranking y Reparto a la vez puede mover el número que decide el reparto':
      ', the sales calls. Anyone holding both Leaderboard and Routing can move the very number that decides the routing',
    'el reparto — dáselas juntas solo si es a conciencia.':
      'the routing — give them together only deliberately.',
    'De salida no viene marcada ninguna, y es deliberado:': 'None is ticked by default, deliberately:',
    'abre los datos de contacto de personas reales y eso se decide una a una, nunca de regalo con el rol.':
      'opens the contact details of real people, and that is decided one by one — never thrown in with a role.',
    'Proyectos en los que trabaja': 'Projects they work on',
    'Proyectos que supervisa': 'Projects they supervise',
    'Marcar todos': 'Tick all',
    'Limita': 'Limits',
    'en qué proyectos puede crear y editar contratos':
      'which projects they can create and edit contracts in',
    'este usuario, sea agente o manager — un sales manager o project manager también vende. Sin ninguno marcado no puede crear contratos en ningún proyecto':
      'for this user, agent or manager — a sales manager or project manager sells too. With none ticked they cannot create contracts in any project',
    'pero': 'but',
    'a este usuario no le afecta': 'this user is not affected',
    'los administradores trabajan en todos los proyectos por definición':
      'administrators work across every project by definition',
    'No cambia lo que ve en Operaciones ni en Vencimientos, que siguen mostrando la actividad del equipo.':
      'It does not change what they see in Deals or in the Payment schedule, which keep showing the team’s activity.',
    'Esto no es de qué proyectos es encargado': 'This is not which projects they are in charge of',
    'eso es la lista de abajo.': 'that is the list below.',
    ', no aquí: lo de abajo es otra cosa, en qué proyectos':
      ', not here: the list below is a different thing — which projects',
    'De esto sí ve y corrige TODO lo que hagan sus agentes — contratos, facturas, obra, clientes, solicitudes — sea cual sea quien lo creó, y por eso':
      'Here they do see and correct EVERYTHING their agents do — contracts, invoices, construction, clients, requests — whoever created it, and that is why it',
    'se asigna desde la ficha de cada proyecto': 'is assigned from each project’s record',
    '(Proyectos → el lápiz junto a su carpeta), no desde aquí. Esto de abajo es solo un espejo de lo ya asignado, para verlo sin salir de esta ficha.':
      '(Projects → the pencil next to its folder), not from here. The list below only mirrors what is already assigned, so you can see it without leaving this record.',
    'Contratos que puede hacer': 'Contracts they can issue',
    'A este usuario': 'This user',
    'no le afecta': 'is not affected',
    'un sales manager o project manager no crea ni edita contratos, solo los lee.':
      'a sales manager or project manager does not create or edit contracts, only reads them.',
    'Sin ninguno marcado no puede emitir ningún contrato':
      'With none ticked they cannot issue any contract',
    'igual que en «Proyectos», arriba.': 'the same as in “Projects”, above.',
    'Lo comprueba la': 'It is checked by the',
    'base de datos': 'database',
    'al guardar, no solo el desplegable: esconder una opción no es impedirla.':
      'on save, not just by the dropdown: hiding an option is not the same as preventing it.',
    'un administrador emite cualquier tipo por definición.':
      'an administrator issues every type by definition.',
    'Preselección según el rol elegido arriba — sigue siendo editable.':
      'Preselected from the role chosen above — still editable.',
    'Preselección según el rol —': 'Preselected from the role —',
    'vacío marcado del todo equivale a "todos"': 'nothing ticked means “all”',
    ', así que conviene dejarlo tal cual salvo que sepas que este usuario necesita algo distinto.':
      ', so leave it as it is unless you know this user needs something different.',
    'Guardando…': 'Saving…',
    'Creando…': 'Creating…',
    'Crear usuario': 'Create user',
    'Datos de acceso': 'Login details',
    'Nombre y apellidos': 'Full name',
    'Contraseña provisional (mínimo 10 caracteres)': 'Temporary password (at least 10 characters)',
    'La verá al entrar; que la cambie después': 'They will see it on login; have them change it afterwards',
    'Mínimo 10 caracteres': 'At least 10 characters',
    'La contraseña necesita 10 caracteres o más': 'The password needs 10 characters or more',
    'Email no válido': 'Invalid email',
    'La contraseña se muestra en claro a propósito: hay que poder copiarla para dársela a la persona. No queda guardada en ningún sitio consultable.':
      'The password is shown in the clear on purpose: you have to be able to copy it to hand it over. It is not stored anywhere you can look it up again.',
    'Se crea la cuenta y se le da acceso de inmediato.': 'The account is created and access granted immediately.',
    'Usuario creado:': 'User created:',
    'No se pudo crear:': 'Could not create:',
    'Cambiar contraseña': 'Change password',
    'Nueva contraseña para %s (mínimo 10 caracteres).': 'New password for %s (at least 10 characters).',
    'Apúntala: no se puede volver a consultar.': 'Write it down: it cannot be looked up again.',
    'Contraseña cambiada': 'Password changed',
    'respuesta ilegible del servidor': 'unreadable response from the server',
    'No se pudo cargar el catálogo de proyectos. Vuelve a abrir el panel: sin él, guardar dejaría a esta persona sin ningún proyecto.':
      'Could not load the project catalogue. Reopen the panel: without it, saving would leave this person with no project at all.',
    'No tienes activada la herramienta «Usuarios». Pídesela a un super admin.':
      'You do not have the “Users” tool enabled. Ask a super admin for it.',
    'Solo un administrador gestiona usuarios': 'Only an administrator manages users',
    'tu rol es «%r»': 'your role is “%r”',
    /* Frenos saltados: el registro de quién se saltó qué. Se traduce el verbo,
       nunca la clave del evento (`desbloqueado`, `facturado_sin_bloquear`…). */
    'Frenos saltados': 'Overrides used',
    'Mirado ahora mismo:': 'Checked just now:',
    'nadie se ha saltado ningún freno': 'nobody has overridden anything',
    'no se ha podido leer': 'could not be read',
    'No se ha podido leer el registro de privilegios.': 'The override log could not be read.',
    'Esto NO quiere decir que nadie se haya saltado nada: quiere decir que no se ha mirado. Recarga la página.':
      'This does NOT mean nobody overrode anything: it means nothing was checked. Reload the page.',
    'desbloqueó un contrato firmado': 'unlocked a signed contract',
    'editó un contrato firmado': 'edited a signed contract',
    'facturó un contrato sin firmar': 'invoiced an unsigned contract',
    'aplicó un cobro al comprador de otro contrato': 'applied a payment to another contract’s buyer',
    'aplicó un cobro a una factura sin contrato': 'applied a payment to an invoice with no contract',
    'guardó un contrato sin ficha de comprador': 'saved a contract with no buyer record',
    'caja negra: no se ha podido leer': 'black box: could not be read',
    '%n documento borrado guardado en la caja negra': '%n deleted document kept in the black box',
    '%n documentos borrados guardados en la caja negra': '%n deleted documents kept in the black box',
    've el tablero y los datos de contacto de los leads': 'see the board and the leads’ contact details',
    'ver el tablero y los datos de contacto de los leads': 'see the board and the leads’ contact details',
    'ver y corregir cuánto firma y cobra cada comercial':
      'see and correct how much each rep signs and earns',
    'decidir qué closers atienden cada campaña': 'decide which closers handle each campaign',
    'la agenda de llamadas de venta': 'the sales-call calendar',

    /* ---------- Vencimientos (la caja de la empresa por fechas) ----------
       «Vencimiento» aquí es una fecha en la que ENTRA dinero, no un impago:
       payment / payment due. «Cartera» es el portfolio de contratos firmados.
       Los cuatro tramos del aging y los «Sin proyecto/Sin comprador» salen de
       `logica.js`, que llama al diccionario por su propio puente `vT`. */
    'Sin proyecto': 'No project',
    'Sin comprador': 'No buyer',
    '1–30 días': '1–30 days',
    '31–60 días': '31–60 days',
    '61–90 días': '61–90 days',
    '+90 días': '90+ days',
    'Parcial': 'Partial',
    'Cobrado': 'Collected',
    'Cartera': 'Portfolio',
    'Vence': 'Due',
    'Vence en 30 días': 'Due in 30 days',
    'Vence en 90 días': 'Due in 90 days',
    'pendiente con la fecha pasada': 'outstanding past its date',
    'nada con la fecha pasada': 'nothing past its date',
    'previsto en el próximo mes': 'expected next month',
    'previsto en el trimestre': 'expected this quarter',
    '%p% de la cartera': '%p% of the portfolio',
    'contratos firmados, sin contar las Cartas de Reserva':
      'signed contracts, Reservation Letters excluded',
    '%n contrato con precio y sin calendario de pagos':
      '%n contract with a price and no payment schedule',
    '%n contratos con precio y sin calendario de pagos':
      '%n contracts with a price and no payment schedule',
    '%n contrato cuyos hitos no suman 100%': '%n contract whose milestones do not add up to 100%',
    '%n contratos cuyos hitos no suman 100%': '%n contracts whose milestones do not add up to 100%',
    'El Bloqueo de Parcela necesita al menos un hito en el calendario de pagos: el Artículo 3 remite a él.': 'The Plot Hold Agreement needs at least one milestone in the payment schedule: Article 3 refers to it.',
    'Ajustes': 'Settings',
    'Los números que el sistema aplica solo: cuántos días de gracia tiene una reserva al vencer, cuántas prórrogas puede dar un sales manager y de cuántos días, y qué propone el formulario. Cambiarlos aquí vale desde ese momento, sin tocar código.': 'The numbers the system applies on its own: how many grace days a reservation gets when it expires, how many extensions a sales manager may grant and for how many days, and what the form proposes. Changing them here takes effect immediately, with no code change.',
    'Tu sesión no es super admin: puedes mirar, no cambiar.': 'Your session is not super admin: you can look, not change.',
    'Comunicación': 'Communication',
    'Escribe un comunicado para el equipo y mándalo por email a los usuarios de la intranet que elijas. Sale con la plantilla de marca de Lawang. Una vez enviado queda en el registro tal como salió: para cambiarlo, duplícalo.': 'Write an announcement for the team and email it to the intranet users you choose. It goes out with the Lawang brand template. Once sent it stays in the log exactly as it went out: to change it, duplicate it.',
    'Nuevo comunicado': 'New announcement',
    'Comunicado': 'Announcement',
    'Asunto del email': 'Email subject',
    'Título dentro del email (opcional)': 'Heading inside the email (optional)',
    'Texto': 'Text',
    'Texto normal: los saltos de línea se respetan tal cual. Para listas, empieza la línea con «•».': 'Plain text: line breaks are kept as they are. For lists, start the line with “•”.',
    'Texto del botón': 'Button text',
    'Enlace del botón': 'Button link',
    'El botón solo puede llevar a lawangproperties.com, a un email o a WhatsApp. Si lo dejas vacío, lleva a la intranet.': 'The button can only point to lawangproperties.com, an email or WhatsApp. If left empty, it points to the intranet.',
    'Enviarme una prueba': 'Send me a test',
    'Borrar borrador': 'Delete draft',
    'Así lo verá quien lo reciba': 'This is how recipients will see it',
    'Destinatarios': 'Recipients',
    'Solo usuarios activos de la intranet. A quien ya lo recibió no se le vuelve a enviar.': 'Active intranet users only. Anyone who already received it will not get it again.',
    'Persona': 'Person',
    'Comunicados': 'Announcements',
    'Trayendo los comunicados…': 'Loading announcements…',
    'Reservas': 'Reservations',
    'Vencimiento, gracia y prórrogas de las Cartas de Reserva': 'Expiry, grace and extensions of Reservation Letters',
    'Ajuste': 'Setting',
    'Valor': 'Value',
    'Último cambio': 'Last change',
    'Trayendo los ajustes…': 'Fetching the settings…',
    'El automatismo que libera reservas corre cada día a las 04:00 UTC y lee estos valores en cada pasada; la prórroga los lee al pulsar «Prorrogar» en la ficha de la Carta.': 'The automation that releases reservations runs daily at 04:00 UTC and reads these values on every run; the extension reads them when you press "Extend" on the Letter sheet.',
    '%n sin firmar': '%n unsigned',
    '%n Carta de Reserva': '%n Reservation Letter',
    '%n Cartas de Reserva': '%n Reservation Letters',
    'Fuera de este panel:': 'Outside this panel:',
    'y': 'and',
    'de precio': 'in price',
    'Sobre todo en %s': 'Mostly in %s',
    'Aquí solo entran contratos firmados que no sean preliminares':
      'Only signed, non-preliminary contracts are counted here',
    'Previsión de caja por mes: cobrado, pendiente y vencido':
      'Cash forecast by month: collected, outstanding and overdue',
    'línea discontinua = mes actual': 'dashed line = current month',
    'Solo vencimientos con fecha: lo «sin fecha» no está aquí — está en su alerta.':
      'Only dated payments: anything “no date” is not here — it is in its own alert.',
    'Composición de la cartera': 'Portfolio breakdown',
    'Composición de la cartera: cobrado, pendiente y vencido':
      'Portfolio breakdown: collected, outstanding and overdue',
    'Sin cartera en esta moneda.': 'No portfolio in this currency.',
    'Dinero por trimestre (pendiente)': 'Money by quarter (outstanding)',
    'Pendiente por trimestre': 'Outstanding by quarter',
    'Pendiente sin vencer': 'Outstanding, not yet due',
    'en %n vencimiento': 'across %n payment',
    'en %n vencimientos': 'across %n payments',
    'Vencido por antigüedad': 'Overdue by age',
    'Vencido por antigüedad del retraso': 'Overdue by how late it is',
    '%e de retraso': '%e late',
    'Nada vencido en esta moneda. Que siga así.': 'Nothing overdue in this currency. Long may it last.',
    'Por proyecto': 'By project',
    'Sin proyectos en esta moneda.': 'No projects in this currency.',
    'cobrado': 'collected',
    'pendiente': 'outstanding',
    'vencido': 'overdue',
    'Cubierto': 'Covered',
    'Barra = cartera del proyecto, al ancho relativo del mayor. Verde cobrado · teal pendiente · rojo vencido':
      'Bar = the project’s portfolio, scaled to the largest. Green collected · teal outstanding · red overdue',
    'se enseñan los 8 mayores': 'the 8 largest are shown',
    'Necesitan atención': 'Need attention',
    'Vencidos': 'Overdue',
    'Próximos 90 días': 'Next 90 days',
    'Todos los vencimientos': 'All payments',
    'Incluir sin firmar': 'Include unsigned',
    'Mientras se da de alta el histórico, «sin firmar» significa «aún no marcado», no «aún no acordado»':
      'While the historical backlog is being loaded, “unsigned” means “not marked yet”, not “not agreed yet”',
    'Nada con este filtro.': 'Nothing with this filter.',
    'sin firmar': 'unsigned',
    'Cliente': 'Client',
    'Hito': 'Milestone',
    'Cambiar la fecha de este vencimiento': 'Change this payment’s date',
    'Fecha ajustada a mano': 'Date adjusted by hand',
    'Facturada': 'Invoiced',
    'El sistema ya emitió y envió la factura de este vencimiento':
      'The system already issued and sent the invoice for this payment',
    'Sin auto': 'No auto',
    'Este vencimiento no recibe factura automática': 'This payment gets no automatic invoice',
    'Nueva fecha de vencimiento': 'New due date',
    'Vencimiento el %f': 'Due on %f',
    'Fecha quitada — vuelve a «Sin fecha»': 'Date removed — back to “No date”',
    'Sin contratos en esta moneda.': 'No contracts in this currency.',
    'Factura': 'Invoice',
    'Facturas con vencimiento propio': 'Invoices with their own due date',
    'Vencida': 'Overdue',
    'En plazo': 'On time',
    'Ninguna factura con fecha de vencimiento en esta moneda.':
      'No invoice with a due date in this currency.',
    'No se pudieron leer los contratos:': 'Could not load the contracts:',
    'No se pudieron leer los vencimientos:': 'Could not load the payments:',
    'No se pudo calcular lo cobrado:': 'Could not calculate what has been collected:',
    'No se pudo guardar la fecha:': 'Could not save the date:',

    /* ---------- El hub (`/intranet/`) y el catálogo (`herramientas.js`) ----------
       `nombre`, `para` y `grupo` del catálogo siguen escritos en español: ese
       fichero es la FUENTE. Lo que se traduce es el rótulo al pintarlo, aquí
       y en el menú lateral de `topbar.js`. Las palabras de búsqueda (`claves`)
       no están en este diccionario: se AMPLIARON con el inglés en el propio
       catálogo, porque el buscador mira una sola cadena y tiene que encontrar
       lo mismo se escriba «facturas» o «invoices». */
    'Intranet': 'Intranet',
    'Herramientas': 'Tools',
    'Buenos días': 'Good morning',
    'Buenas tardes': 'Good afternoon',
    'Buenas noches': 'Good evening',
    'Esto es lo que necesita tu atención.': 'Here is what needs your attention.',
    'Esto es lo que necesita tu atención hoy,': 'Here is what needs your attention today,',
    'Acceso restringido: cada herramienta exige esta misma sesión.':
      'Restricted access: every tool requires this same session.',
    'Ninguna herramienta coincide con «%q».': 'No tool matches “%q”.',
    'No tienes acceso a «%h».': 'You do not have access to “%h”.',
    'Pídeselo a un administrador: en tu ficha se activa herramienta por herramienta.':
      'Ask an administrator for it: it is enabled tool by tool on your account.',
    'Tu cuenta está desactivada. Habla con un administrador.':
      'Your account is deactivated. Talk to an administrator.',
    'Correo': 'Email',
    'Contraseña': 'Password',
    'Entrar': 'Log in',
    'Salir': 'Log out',
    'Credenciales incorrectas': 'Wrong email or password',
    'Entra por el área de clientes →': 'Go to the client area →',
    /* cifras del hub */
    'Firmas esperando': 'Signatures waiting',
    'pendientes de que el comprador firme': 'waiting on the buyer to sign',
    'ninguna pendiente': 'none pending',
    '%n aún editables': '%n still editable',
    'Facturas emitidas': 'Invoices issued',
    'Unidades libres': 'Units available',
    'de %n en inventario': 'of %n in inventory',
    'con fase abierta': 'with an open stage',
    'sin unidades en obra': 'no units under construction',
    'la base no contestó': 'the database did not answer',
    '%n herramienta sin cifra: la base no contestó y no se inventa un cero.':
      '%n tool with no figure: the database did not answer, and a zero is not invented.',
    '%n herramientas sin cifra: la base no contestó y no se inventa un cero.':
      '%n tools with no figure: the database did not answer, and a zero is not invented.',
    'Cifras al día de %h.': 'Figures as of %h.',
    /* últimas operaciones */
    'Operaciones recientes': 'Recent activity',
    'Editable': 'Editable',
    'Recibí': 'Receipt',
    'Proforma': 'Proforma',
    'Anulada': 'Voided',
    'Emitida': 'Issued',
    /* riel de avisos */
    'Firmas que necesitan atención': 'Signatures needing attention',
    'Cadena parada': 'Chain stalled',
    'Sin email': 'No email',
    'Enlace caducado': 'Link expired',
    'Sin documento': 'No document',
    'aviso más': 'more alert',
    'avisos más': 'more alerts',
    'Una cadena parada deja el contrato editable después de firmado. Ábrelo en Contratos y genera el enlace que falta.':
      'A stalled chain leaves the contract editable after signing. Open it in Contracts and generate the missing link.',
    'las firmas pendientes': 'the pending signatures',
    'los vencimientos': 'the payment schedule',
    'Próximos vencimientos': 'Upcoming payments',
    'Nada a la vista': 'Nothing on the horizon',
    'No se ha podido comprobar': 'Could not be checked',
    'Esto NO quiere decir que no haya nada: quiere decir que no se ha mirado.':
      'This does NOT mean there is nothing: it means nothing was checked.',
    'Recarga la página; si sigue igual, avisa a desarrollo.':
      'Reload the page; if it persists, tell development.',
    /* cifras de cada tarjeta del catálogo */
    '%n sin contactar': '%n not contacted',
    'Todos contestados': 'Everyone answered',
    '%n firma esperando': '%n signature waiting',
    '%n firmas esperando': '%n signatures waiting',
    'Sin firmas pendientes': 'No signatures pending',
    '%n ticket abierto': '%n open ticket',
    '%n tickets abiertos': '%n open tickets',
    'Sin tickets abiertos': 'No open tickets',
    '%n sin fecha que vigilar': '%n with no date to watch',
    'Calendario al día': 'Schedule up to date',
    '%g guardados · %e editables': '%g saved · %e editable',
    'Sin documentos todavía': 'No documents yet',
    '%d documentos · %p proyectos': '%d documents · %p projects',
    '%n emitidas': '%n issued',
    '%n anuladas': '%n voided',
    '%n emitidos': '%n issued',
    '%n por resolver o pagar': '%n to decide or pay',
    'Sin solicitudes en vuelo': 'No requests in flight',
    'Sin inventario cargado': 'No inventory loaded',
    '%u unidades · %l disponibles': '%u units · %l available',
    '%n sin precio de catalogo': '%n with no catalogue price',
    '%m modelos · %p en la web': '%m models · %p live',
    'Sin unidades en obra': 'No units under construction',
    '%n en obra': '%n under construction',
    '%n fichas': '%n records',
    '%n con acceso': '%n with access',
    '%n desactivados': '%n deactivated',
    /* descripciones del catálogo (`para`) */
    'Los leads que entran por Meta y por la web: en qué punto está cada uno y quién lo lleva.':
      'The leads coming in from Meta and from the website: where each one stands and who owns it.',
    'Cuánto firma y cuánto cobra cada comercial, y a quién se atribuye cada venta.':
      'How much each rep signs and earns, and who each sale is credited to.',
    'Que closers atienden cada campana, su tope de leads sin contactar y el reparto automatico.':
      'Which closers handle each campaign, their cap on uncontacted leads, and automatic routing.',
    'La agenda de llamadas de venta del closer, dentro del CRM.':
      'The closer’s sales-call calendar, inside the CRM.',
    'Cómo va cada venta: estado de cuenta, documentos, firmas y vencimientos.':
      'How each sale is going: statement of account, documents, signatures and payments.',
    'Los tickets de los compradores desde su área de clientes, en una bandeja.':
      'Buyer tickets from their client area, in one inbox.',
    'Qué dinero debe entrar, cuándo, y cuál se está retrasando: la caja de la empresa por fechas.':
      'What money is due, when, and what is running late: the company’s cash by date.',
    'Reservas, PPJB, construcción y anexos.': 'Reservations, PPJB, construction and annexes.',
    'Dossiers de producto y piezas de pauta para Instagram y Facebook, con la revisión de legibilidad incorporada.':
      'Product brochures and paid-social assets for Instagram and Facebook, with the legibility check built in.',
    'Precios, planos y material de cada proyecto, en el almacén privado.':
      'Pricing, floor plans and material for each project, in the private store.',
    'Facturas, proformas y recibís, cada tipo con su serie.':
      'Invoices, proformas and receipts, each type with its own series.',
    'Justificantes de pago y señales.': 'Proof of payment and deposits.',
    'Pagos que piden los comerciales — comisiones y acordados: quién pide qué, y en qué quedó cada uno.':
      'Payments the reps request — commissions and agreed payments: who asked for what, and how each one ended.',
    'Inventario de parcelas y villas con su estado de venta, por proyecto.':
      'Inventory of plots and villas with their sales status, by project.',
    'La misma base de parcelas y villas, en tarjetas por proyecto con el estado de cuentas. En pruebas junto a Proyectos.':
      'The same plot and villa data, as cards per project with the account status. Under test alongside Projects.',
    'Que se puede construir: habitaciones, metros, precio, techos, extras y planos de cada tipo de vivienda.':
      'What can be built: rooms, square metres, price, roof types, add-ons and floor plans for each house model.',
    'Fase, fecha de entrega y fotos de cada unidad — lo que ve el comprador en su portal.':
      'Stage, handover date and photos for each unit — what the buyer sees in their portal.',
    'Ficha del comprador y documentación KYC, con caducidades.':
      'Buyer record and KYC documents, with expiry dates.',
    'Quién entra, con qué rol y qué herramientas ve cada uno.':
      'Who logs in, with what role, and which tools each of them sees.',

    /* ---------- Operaciones (el seguimiento de cada venta) ----------
       «Operación» aquí es UNA VENTA con todo lo que cuelga de ella: contrato,
       facturas, firmas y obra. En inglés es «deal», no «operation». */
    'Buscar comprador, proyecto, operador o nº…': 'Search buyer, project, agent or no.…',
    'Tabla': 'Table',
    'Embudo': 'Funnel',
    'Operador': 'Agent',
    'Precio': 'Price',
    'Precio pactado': 'Agreed price',
    'Situación': 'Where it stands',
    'Firmadas': 'Signed',
    'Con pendiente': 'With balance',
    'Firma enviada': 'Signature sent',
    'Sin facturar': 'Not invoiced',
    'Falta ficha': 'Record missing',
    'Quitar los filtros': 'Clear the filters',
    'Nada aquí': 'Nothing here',
    'Esta vista no lo está sumando todo: hay más de %l, y solo se han leído los más recientes. Los totales de abajo son parciales.':
      'This view is not adding everything up: there are more than %l, and only the most recent were read. The totals below are partial.',
    'y más de': 'and more than',
    'Contratos y facturación de esta venta, juntos.': 'Contracts and invoicing for this sale, together.',
    'Contratos de la operación': 'Contracts on this deal',
    'Documentos de la operación': 'Documents on this deal',
    'Documentación del comprador': 'Buyer documentation',
    'Hito de pago': 'Payment milestone',
    'Cargando los hitos de pago…': 'Loading the payment milestones…',
    'El contrato no fijó hitos de pago.': 'The contract set no payment milestones.',
    'No se pudieron cargar los hitos de pago:': 'Could not load the payment milestones:',
    'sin importe': 'no amount',
    'sin fijar': 'not set',
    'no calculable': 'cannot be calculated',
    'Sin precio total en el contrato no se puede calcular el pendiente ni convertir los hitos en %. Se rellena en Contratos.':
      'Without a total price on the contract, the balance cannot be calculated nor the milestones turned into %. It is filled in under Contracts.',
    'No suma': 'Not counted',
    'No cuenta %l — una Carta de Reserva declara el mismo importe que luego reparten el Bloqueo y la Construcción.':
      'Excludes %l — a Reservation Letter declares the same amount that the Plot Block and the Construction contract later split.',
    'Facturación': 'Invoicing',
    'Solo el recibí cuenta como cobrado — una factura o una proforma son lo que se debe, no lo pagado.':
      'Only the receipt counts as collected — an invoice or a proforma is what is owed, not what was paid.',
    'Cobros — documentos con vencimiento': 'Collections — documents with a due date',
    'Solo salen las que llevan vencimiento Y todavía tienen algo pendiente; es un campo opcional en Facturas, y una factura ya saldada por recibí no reclama nada.':
      'Only those with a due date AND something still outstanding appear; it is an optional field in Invoices, and an invoice already settled by a receipt claims nothing.',
    'Ninguna factura con vencimiento tiene algo pendiente de cobrar.':
      'No invoice with a due date has anything left to collect.',
    'Firmas': 'Signatures',
    'Firmas — enlaces pendientes': 'Signatures — pending links',
    'Firmante': 'Signer',
    'No hay enlaces de firma pendientes.': 'There are no pending signature links.',
    'No se ha enviado a firma remota.': 'It has not been sent for remote signing.',
    'Un enlace caducado no se recupera: se genera otro desde Contratos.':
      'An expired link cannot be recovered: generate another one from Contracts.',
    'Caduca': 'Expires',
    'Caducado': 'Expired',
    'Anulado': 'Voided',
    'Clase': 'Kind',
    'De': 'From',
    'Vía': 'Via',
    'Quién': 'Who',
    'Aviso': 'Notice',
    'Subido': 'Uploaded',
    'borrador': 'draft',
    'Ver documento': 'View document',
    'Ver PDF firmado': 'View signed PDF',
    'PDF firmado': 'Signed PDF',
    'Abrir en Contratos': 'Open in Contracts',
    'No se pudo abrir el PDF:': 'Could not open the PDF:',
    'Ese contrato ya no existe': 'That contract no longer exists',
    'Datos actualizados': 'Data updated',
    'El pasaporte y el KYC son de la': 'The passport and the KYC belong to the',
    ', no de una venta: salen en todas sus operaciones. Se suben desde':
      ', not to a sale: they show up on all of their deals. They are uploaded from',
    'Ningún documento subido todavía para este comprador.': 'No document uploaded yet for this buyer.',
    'Ningún documento subido todavía para estos compradores.': 'No document uploaded yet for these buyers.',
    'Sin ficha de comprador enlazada no hay documentación que mostrar.':
      'With no buyer record linked there is no documentation to show.',
    'Pulsa un nombre para abrir su ficha y su documentación.':
      'Click a name to open their record and their documents.',
    'Pulsa un número de contrato para ver su operación completa.':
      'Click a contract number to see the whole deal.',
    'Sus otros contratos': 'Their other contracts',
    'Adquiriente': 'Buyer',
    'sin pasaporte': 'no passport',
    'siempre que el comprador tenga pasaporte o email.': 'as long as the buyer has a passport or an email.',
    '(abierta)': '(open)',
    'firmado y bloqueado': 'signed and locked',
    'Borrar operación': 'Delete deal',
    'Borrar la operación': 'Delete the deal',
    'Borrar la operación de %c': 'Delete %c’s deal',
    'el contrato %n': 'contract %n',
    '%n enlace de firma quedará ANULADO': '%n signature link will be VOIDED',
    '%n enlaces de firma quedarán ANULADOS': '%n signature links will be VOIDED',
    '%n factura quedará ANULADA (no se borra: la serie no puede tener huecos)':
      '%n invoice will be VOIDED (not deleted: the series cannot have gaps)',
    '%n facturas quedarán ANULADAS (no se borran: la serie no puede tener huecos)':
      '%n invoices will be VOIDED (not deleted: the series cannot have gaps)',
    'La parcela vinculada vuelve a estar disponible.': 'The linked plot becomes available again.',
    'Operación borrada ·': 'Deal deleted ·',
    'No hay papelera.': 'There is no undo.',

    /* ---------- Compradores (ficha + KYC + portal del cliente) ---------- */
    'Buscar nombre, email o pasaporte…': 'Search name, email or passport…',
    'Contacto': 'Contact',
    'Nacionalidad': 'Nationality',
    'Pasaporte': 'Passport',
    'Docs.': 'Docs',
    'Agente': 'Agent',
    'Idioma de comunicación': 'Communication language',
    'Español': 'Spanish',
    'Bahasa Indonesia': 'Indonesian',
    'Identidad': 'Identity',
    'Tipo de comprador': 'Buyer type',
    'Persona física': 'Individual',
    'Empresa': 'Company',
    'Nombre completo': 'Full name',
    'Pasaporte / identificación fiscal': 'Passport / tax ID',
    'Pasaporte / NPWP': 'Passport / NPWP',
    'Domicilio': 'Address',
    'Fecha de nacimiento': 'Date of birth',
    'Razón social': 'Registered name',
    'País de constitución': 'Country of incorporation',
    'Identificación fiscal (NIF, NPWP, EIN…)': 'Tax ID (NIF, NPWP, EIN…)',
    'Domicilio social': 'Registered address',
    'Forma jurídica': 'Legal form',
    'Nº de registro mercantil': 'Company registration no.',
    'Representante legal': 'Legal representative',
    'Cargo del representante': 'Representative’s role',
    'Una empresa y su dueño pueden compartir correo: son dos fichas distintas y las dos son válidas.':
      'A company and its owner can share an email: they are two separate records and both are valid.',
    'Este correo es solo de contacto — cambiarlo NO cambia con qué email entra al portal. Eso se gestiona aparte, en «Portal del comprador» más abajo.':
      'This email is for contact only — changing it does NOT change which email they use to log in to the portal. That is handled separately, under “Buyer portal” below.',
    'Prefijo del país': 'Country code',
    'Estado KYC': 'KYC status',
    'Caduca el (opcional)': 'Expires on (optional)',
    'Fichero': 'File',
    'Elige un fichero': 'Choose a file',
    'El fichero supera los 20 MB': 'The file is over 20 MB',
    'Van a un bucket privado. Al abrirlos se genera un enlace temporal de 5 minutos, no una URL fija.':
      'They go to a private bucket. Opening one generates a temporary 5-minute link, not a fixed URL.',
    'Los documentos se suben después de crear la ficha.': 'Documents are uploaded after the record is created.',
    'Sin documentos todavía.': 'No documents yet.',
    'Documento subido': 'Document uploaded',
    'No se pudo subir:': 'Could not upload:',
    'No se pudieron leer los documentos:': 'Could not load the documents:',
    'Documento del comprador': 'Buyer document',
    'Se retira': 'Removing',
    'de la ficha, y su fichero del archivo privado.': 'from the record, and its file from the private archive.',
    'No hay papelera: si el documento sigue haciendo falta habrá que volver a subirlo.':
      'There is no undo: if the document is still needed it will have to be uploaded again.',
    'Retirar el documento': 'Remove the document',
    'Dejarlo': 'Leave it',
    'Retirando…': 'Removing…',
    'No se pudo retirar: ': 'Could not remove: ',
    'No se ha retirado: tu usuario no tiene permiso para borrar documentos.':
      'Not removed: your account has no permission to delete documents.',
    'Documento retirado de la ficha, pero su fichero sigue en el archivo (':
      'Document removed from the record, but its file is still in the archive (',
    'No se han retirado': 'Not removed',
    'Borrar la ficha de %c': 'Delete %c’s record',
    'este comprador': 'this buyer',
    'y sus': 'and its',
    '%n documento KYC': '%n KYC document',
    '%n documentos KYC': '%n KYC documents',
    'del archivo privado': 'from the private archive',
    'y te dice cuál — esta acción es para': 'and tells you which — this action is for',
    'duplicados sueltos': 'stray duplicates',
    'Borrar la ficha': 'Delete the record',
    'Borrando…': 'Deleting…',
    'Borrar comprador': 'Delete buyer',
    'Ficha borrada, pero': 'Record deleted, but',
    'Ese comprador ya no existe': 'That buyer no longer exists',
    'Ficha de': 'Record of',
    'Ficha actualizada': 'Record updated',
    'Comprador creado': 'Buyer created',
    'Ese teléfono ya está en otra ficha': 'That phone number is already on another record',
    'Si es la misma persona, no la crees otra vez: búscala en la lista por su teléfono y usa esa ficha.': 'If it is the same person, do not create them again: search the list by phone number and use that record.',
    'Si de verdad comparten teléfono —un matrimonio que compra junto, una persona y su propia empresa— puedes seguir.': 'If they really share a phone —a couple buying together, a person and their own company— you can go ahead.',
    'Guardar igualmente': 'Save anyway',
    'No guardar': 'Don’t save',
    'Ese pasaporte / NPWP ya está en otra ficha (el correo no tiene nada que ver con este aviso). Desde el 11-sep cada uno ve solo los compradores que dio de alta, así que esa ficha puede existir y NO aparecerte en la lista: no crees una segunda: pide a un administrador que te la traspase o que la enlace a tu contrato.':
      'That passport / NPWP is already on another record (this warning has nothing to do with the email). Since 11 Sep each person only sees the buyers they created, so that record may exist and NOT show up in your list: do not create a second one: ask an administrator to transfer it to you or to link it to your contract.',
    'Ya hay otra ficha DEL MISMO TIPO con ese correo. Una persona y su empresa sí pueden compartirlo, pero dos personas (o dos empresas) no. Ojo: esa otra ficha puede ser de un compañero y no aparecerte en la lista — si es la misma persona, pide que te la traspasen en vez de crearla otra vez; si es una familia que comparte buzón, deja el correo en una sola e identifica a las demás por su pasaporte.':
      'Another record OF THE SAME TYPE already uses that email. A person and their company may share one, but two people (or two companies) may not. Careful: that other record may belong to a colleague and not show up in your list — if it is the same person, ask for it to be transferred to you instead of creating it again; if it is a family sharing one mailbox, keep the email on a single record and identify the others by passport.',
    'Ese dato ya está en otra ficha: ': 'That value is already on another record: ',
    /* Directorio de compradores + el autor corrige lo suyo (14-sep-2026). */
    'No se pudo leer el directorio de compradores: ': 'Could not read the buyer directory: ',
    'Su actividad': 'Their activity',
    /* Traspaso de ficha de comprador (14-sep-2026). */
    'Responsable de la ficha': 'Who owns this record',
    'La dio de alta ': 'Created by ',
    ' (tú)': ' (you)',
    'Nadie.': 'Nobody.',
    'Es una de las fichas antiguas que se quedaron sin autor: hoy solo la puede editar un administrador.':
      'This is one of the older records left without an author: for now only an administrator can edit it.',
    'Pasar la ficha a': 'Hand the record over to',
    'Traspasar': 'Hand over',
    'Quien la reciba podrá abrirla y corregirla (mientras no cuelgue de un contrato firmado); los demás la seguirán viendo en el directorio, solo de consulta. Sin marcar la casilla de arriba, los contratos y las facturas NO se mueven: el traspaso es solo de la ficha.':
      'Whoever receives it will be able to open and correct it (as long as it does not hang off a signed contract); everyone else will keep seeing it in the directory, read-only. Without ticking the box above, contracts and invoices do NOT move: only the record changes hands.',
    'Pasar la ficha de %n a %d': 'Hand the record of %n over to %d',
    'Podrá abrirla y corregirla. Sus contratos y sus facturas no se mueven.':
      'They will be able to open and correct it. Their contracts and invoices do not move.',
    'Esa ficha ya es suya.': 'That record is already theirs.',
    'No se pudo traspasar: ': 'Could not hand it over: ',
    'Ficha traspasada a ': 'Record handed over to ',
    /* Arrastrar contratos/facturas en el traspaso — 17-sep-2026, solo super_admin. */
    'Arrastrar también sus contratos y facturas (solo los que sean de %n)':
      'Also drag along their contracts and invoices (only the ones that belong to %n)',
    'Ej. Ana deja el equipo, sus clientes pasan a Carmen': 'E.g. Ana is leaving the team, her clients move to Carmen',
    'Escribe el motivo: es lo que explica el traspaso dentro de un año.':
      'Write the reason: it is what explains the transfer a year from now.',
    'Se traspasarán también los contratos y las facturas de %n. Lo que ya sea de otra persona, o esté firmado o anulado, no se mueve y queda a la vista para revisarlo a mano.':
      'The contracts and invoices of %n will also be transferred. Anything that already belongs to someone else, or is signed or voided, does not move and stays visible to review by hand.',
    'Traspaso de %n': 'Transfer of %n',
    'Contratos: %m movidos · %f firmados sin tocar · %o de otro autor · %s sin autor.':
      'Contracts: %m moved · %f signed, left untouched · %o belong to someone else · %s have no author.',
    'Facturas y recibís: %m movidas (%a anuladas incluidas) · %o de otro autor · %s sin autor.':
      'Invoices and receipts: %m moved (including %a voided) · %o belong to someone else · %s have no author.',
    'Contratos, pagos, facturas, documentos y portal de esta persona NO se muestran aquí: son del compañero que lleva la ficha. Que no aparezcan no significa que no existan.':
      'This person’s contracts, payments, invoices, documents and portal are NOT shown here: they belong to the colleague who owns the record. Their absence does not mean they do not exist.',
    'de otro': 'someone else’s',
    'De otro compañero: solo consulta': 'A colleague’s record: read-only',
    'Esta ficha la dio de alta ': 'This record was created by ',
    'nadie (ficha antigua sin autor)': 'nobody (old record with no author)',
    ', así que aquí solo ves quién es. No crees una segunda: para trabajar con ella pide que te la traspasen, o ponla en tu contrato por su pasaporte — el generador la encuentra igual.':
      ', so here you only see who they are. Do not create a second one: to work with it ask for it to be transferred to you, or put it on your contract by passport — the generator finds it anyway.',
    'Esta ficha cuelga de un contrato ya FIRMADO: su pasaporte y su domicilio están impresos dentro de ese documento, así que no se cambian desde aquí. Si hay un error real en el documento, es cosa de un administrador.':
      'This record hangs off an already SIGNED contract: its passport and address are printed inside that document, so they are not changed from here. If there is a real error in the document, that is for an administrator.',
    'No se ha guardado: la base no te deja editar esta ficha. Suele ser porque no la diste de alta tú, o porque ya cuelga de un contrato firmado. Habla con un administrador — recargar no lo arregla.':
      'Not saved: the database will not let you edit this record. Usually because you did not create it, or because it already hangs off a signed contract. Talk to an administrator — reloading will not fix it.',
    'Crear comprador': 'Create buyer',
    'Guardando…': 'Saving…',
    'Subiendo…': 'Uploading…',
    'Subir documento': 'Upload document',
    'Falta el nombre': 'The name is missing',
    'Falta el email de acceso': 'The login email is missing',
    'Tu sesión ha caducado a mitad de guardar. Recarga la página, entra de nuevo y repite el cambio — no se ha guardado.':
      'Your session expired mid-save. Reload the page, log in again and redo the change — nothing was saved.',
    'Solo un administrador puede editar estos datos. Puedes consultarlos y gestionar la documentación de más abajo.':
      'Only an administrator can edit these details. You can read them and manage the documents below.',
    'Puedes editar los datos de la ficha': 'You can edit the record’s details',
    'Estado de cuentas': 'Account status',
    'Contratos firmados': 'Signed contracts',
    // comprador compartido entre closers (22-sep-2026): la ficha dice lo que no enseña
    'Estado de cuentas de tus contratos': 'Account status of your contracts',
    'Esta persona tiene %n contratos en total; aquí ves %v.': 'This person has %n contracts in total; you can see %v here.',
    'Los que no ves son de otro comercial: sus cifras no entran en esta ficha.': 'The ones you can’t see belong to another agent: their figures are not part of this record.',
    'de %a': 'by %a',
    'No se pudo leer la ficha del comprador: ': 'Could not read the buyer’s record: ',
    'nadie (sin autor)': 'nobody (no author)',
    'Solo suma tus contratos: los de otros comerciales no entran en estas cifras.': 'Adds up only your contracts: other agents’ contracts are not included in these figures.',
    'Un contrato firmado, sea de quien sea, congela esta ficha: desde entonces solo la corrige un administrador.': 'A signed contract, whoever made it, freezes this record: from then on only an administrator can correct it.',
    'Contrato · unidad': 'Contract · unit',
    'Avance de pago por proyecto': 'Payment progress by project',
    'Solo cuenta como cobrado el recibí — una factura o proforma es lo que se debe, no lo pagado.':
      'Only the receipt counts as collected — an invoice or proforma is what is owed, not what was paid.',
    'Ninguna factura emitida todavía en sus contratos.': 'No invoice issued yet on their contracts.',
    'Ninguna vigente: todas sus facturas están anuladas.': 'None live: all their invoices are voided.',
    'Ninguno enlazado todavía. El enlace se crea solo al guardar un contrato con su pasaporte o su email.':
      'None linked yet. The link is created automatically when a contract is saved with their passport or their email.',
    'Sin contrato enlazado todavía.': 'No contract linked yet.',
    'Sin contrato enlazado todavía, no hay a qué factura atarla.':
      'No contract linked yet, so there is nothing to attach an invoice to.',
    'Crear contrato': 'Create contract',
    'No se pudieron leer las facturas:': 'Could not load the invoices:',
    'No se pudo leer la cuota de reserva:': 'Could not read the reservation fee:',
    'Registro de envíos': 'Send log',
    'No se pudo leer el registro de envíos:': 'Could not read the send log:',
    'Sin correos registrados para sus contratos y facturas. El registro existe desde el 18-ago-2026: los envíos anteriores no dejaron rastro.':
      'No emails logged for their contracts and invoices. The log exists since 18 Aug 2026: earlier sends left no trace.',
    'Para': 'To',
    'Sin mensajes desde el área de clientes.': 'No messages from the client area.',
    'No se pudo leer Soporte:': 'Could not read Support:',
    'Todo resuelto': 'All resolved',
    '%n abierto': '%n open',
    '%n abiertos': '%n open',
    'Portal del comprador': 'Buyer portal',
    'Email de acceso': 'Login email',
    'correo de acceso': 'login email',
    'correo en la ficha': 'email on the record',
    'Acceso activo para': 'Active access for',
    '. Ve sus contratos, pagos, facturas y obra en /portal/.':
      '. They can see their contracts, payments, invoices and construction at /portal/.',
    'Sin acceso todavía. La entrada automática pide': 'No access yet. Automatic entry requires',
    'al menos un contrato': 'at least one contract',
    'o para darle acceso': 'or, to grant access',
    'con otro correo': 'with a different email',
    'Invitar al portal': 'Invite to the portal',
    'Reenviar enlace': 'Resend link',
    'Invitar a %e al portal': 'Invite %e to the portal',
    'Se le envía un': 'They are sent a',
    'y podrá ver en el portal todo lo de esta ficha: contratos, pagos, facturas y obra.':
      'and will be able to see everything on this record in the portal: contracts, payments, invoices and construction.',
    'Enviar la invitación': 'Send the invitation',
    'Invitación enviada': 'Invitation sent',
    'Acceso creado, pero el correo no salió: reenvía en un rato':
      'Access created, but the email did not go out: resend in a while',
    'Ponerle contraseña': 'Set a password',
    'Apúntala: no se puede volver a consultar, solo cambiar por otra.':
      'Write it down: it cannot be looked up again, only replaced.',
    'Contraseña puesta. Pásasela tú: no queda guardada en ningún sitio consultable.':
      'Password set. Hand it over yourself: it is not stored anywhere you can look it up.',
    'Revocar acceso': 'Revoke access',
    'Revocar el acceso': 'Revoke the access',
    'Revocar el acceso de %e': 'Revoke %e’s access',
    'Dejará de ver': 'They will stop seeing',
    'las fichas vinculadas a ese email, no solo ésta.': 'the records linked to that email, not just this one.',
    '. Se puede volver a invitar desde aquí — mientras haya una fila revocada, la entrada automática NO se la devuelve.':
      '. You can invite them again from here — while a revoked row exists, automatic entry will NOT give it back.',
    'Acceso revocado': 'Access revoked',
    'Invitar o revocar lo hace un administrador.': 'Inviting or revoking is done by an administrator.',
    'No se pudieron leer los accesos al portal:': 'Could not read the portal accounts:',
    'No se pudo generar el enlace': 'Could not generate the link',
    'mandarle el enlace ahora': 'send them the link now',
    'Entra': 'Logs in',
    'sin caducidad': 'no expiry',
    'sin estrenar': 'never used',

    /* ---------- Proyectos (inventario de parcelas y villas) ---------- */
    'Buscar código, proyecto o modelo…': 'Search code, project or model…',
    'Rejilla': 'Grid',
    'Carpetas': 'Folders',
    'Todavía no hay proyectos': 'No projects yet',
    'Da de alta uno con «+ Nuevo proyecto», arriba.': 'Create one with “+ New project”, above.',
    'Créala con «+ Nueva unidad», o cárgalas de la tabla de precios del proyecto.':
      'Create one with “+ New unit”, or load them from the project’s price table.',
    'sin modelo': 'no model',
    'Sin modelo decidido': 'No model chosen',
    'sin decidir': 'undecided',
    'Zona': 'Zone',
    '%n documento': '%n document',
    '%n documentos': '%n documents',
    'sin documentación': 'no documents',
    'Ficha del proyecto': 'Project record',
    'Resort': 'Resort',
    'Parcela máster (código)': 'Master plot (code)',
    'Ej. Balian Hills': 'e.g. Balian Hills',
    'Ej. W5': 'e.g. W5',
    'Ej. A12': 'e.g. A12',
    'Dune, Dream…': 'Dune, Dream…',
    'La ficha sí, los modelos no:': 'The record yes, the models no:',
    'no se tocan desde aquí': 'are not edited from here',
    'Para cambiar el': 'To change the',
    'del proyecto usa «Renombrar…» abajo — es otra operación, porque esa sí se propaga a unidades, contratos, facturas… y estos tres campos no.':
      'of the project use “Rename…” below — that is a different operation, because it does propagate to units, contracts, invoices… and these three fields do not.',
    'No tienes permiso para editar la ficha del proyecto (solo admin).':
      'You do not have permission to edit the project record (admins only).',
    'Qué se puede construir aquí': 'What can be built here',
    'de catálogo': 'catalogue',
    'lo usa %n parcela, no se puede retirar': 'used by %n plot, cannot be removed',
    'lo usan %n parcelas, no se puede retirar': 'used by %n plots, cannot be removed',
    'El catálogo de modelos está vacío o no tienes permiso para leerlo.':
      'The model catalogue is empty, or you have no permission to read it.',
    'Solo un administrador puede cambiar esta lista.': 'Only an administrator can change this list.',
    'Este proyecto no tiene modelos declarados, así que se ofrece el catálogo entero. Para acotarlo, «Qué se puede construir aquí» en la ficha del proyecto.':
      'This project has no models declared, so the whole catalogue is offered. To narrow it down, use “What can be built here” in the project record.',
    'Sales manager / Project manager de este proyecto': 'Sales manager / Project manager for this project',
    'A quien marques aquí es el': 'Whoever you tick here is the',
    '(su parte del contrato)': '(their side of the contract)',
    'Si este proyecto aparece en': 'If this project also appears under',
    ', que es en qué proyectos puede crear contratos él mismo: un encargado de este proyecto no tiene por qué vender aquí, y viceversa.':
      ', which is which projects they can create contracts in themselves: someone in charge of this project need not sell here, and vice versa.',
    'Todavía no hay ningún sales manager ni project manager dado de alta. Se crean desde':
      'No sales manager or project manager exists yet. They are created from',
    'Solo un administrador con la herramienta «usuarios» puede asignar managers.':
      'Only an administrator with the “users” tool can assign managers.',
    'desactivado': 'deactivated',
    'Renombrar…': 'Rename…',
    'Se actualizará en: %r.': 'It will be updated in: %r.',
    'No hay nada vinculado a este nombre todavía.': 'Nothing is linked to this name yet.',
    'Escribe un nombre': 'Type a name',
    'Proyecto renombrado': 'Project renamed',
    'No se pudo renombrar:': 'Could not rename:',
    'No se pudo actualizar el proyecto de:': 'Could not update the project of:',
    'Proyecto creado:': 'Project created:',
    'Nombre del proyecto nuevo:': 'Name of the new project:',
    'Borrar el proyecto': 'Delete the project',
    'Borrar el proyecto «%p» del catálogo': 'Delete the project “%p” from the catalogue',
    'Solo se puede si no tiene unidades, modelos de villa ni documentos subidos. Si tiene algo, el sistema lo rechaza y dice qué queda por vaciar.':
      'Only possible if it has no units, villa models or uploaded documents. If it has any, the system refuses and says what is left to clear.',
    'Proyecto borrado': 'Project deleted',
    'Nueva unidad': 'New unit',
    'Crear unidad': 'Create unit',
    'Unidad creada': 'Unit created',
    'El código es el mismo texto que imprime el contrato.': 'The code is the same text the contract prints.',
    'Debe coincidir con el que se escribe en el contrato: es lo que permite cruzarlos.':
      'It must match the one written on the contract: that is what lets them be cross-referenced.',
    'El código no puede quedar vacío': 'The code cannot be empty',
    'Ya hay una unidad con ese código en ese proyecto.': 'There is already a unit with that code in that project.',
    'no tienes permiso para guardar unidades': 'you have no permission to save units',
    'Elige un proyecto (o da uno de alta con «+ Nuevo proyecto…»)':
      'Choose a project (or create one with “+ New project…”)',
    '+ Nuevo proyecto…': '+ New project…',
    '+ Nuevo tipo…': '+ New type…',
    'Da de alta el tipo nuevo antes de guardar': 'Create the new type before saving',
    'Nombre del proyecto': 'Project name',
    'Nombre del tipo': 'Type name',
    'Modelo': 'Model',
    'Modelo de villa': 'Villa model',
    'Fase (masterplan)': 'Phase (masterplan)',
    'Superficie (m²)': 'Area (m²)',
    'Superficie bruta (m²)': 'Gross area (m²)',
    'Precio por m²': 'Price per m²',
    'Con la superficie, calcula el suelo solo': 'With the area, it works out the land price itself',
    'Desglose de precio': 'Price breakdown',
    'Precio de suelo': 'Land price',
    'Precio de construcción': 'Construction price',
    'Precio total': 'Total price',
    'Suelo': 'Land',
    'Precio según el modelo': 'Price from the model',
    'Precio recalculado para': 'Price recalculated for',
    'Lo que cambia entre modelos es la construcción; el suelo es de la parcela.':
      'What changes between models is the construction; the land belongs to the plot.',
    'el suelo (%s) es lo único fijo.': 'the land (%s) is the only fixed part.',
    'Sin modelo: la construcción y el total quedan sin fijar':
      'No model: construction and total are left unset',
    'El total no cuadra con suelo + construcción. Revisa cuál de los tres es el bueno.':
      'The total does not match land + construction. Check which of the three is right.',
    'Contrato asociado': 'Linked contract',
    'Operación': 'Deal',
    'Cobrado de esta unidad': 'Collected on this unit',
    '— elegir —': '— choose —',
    '— sin contrato —': '— no contract —',
    '— sin decidir —': '— undecided —',
    '· del catálogo': '· from the catalogue',
    '· elegido': '· chosen',
    'sin precio': 'no price',
    'sin código': 'no code',
    'Marcada como %e pero sin contrato asociado: no se podrá saber de quién es.':
      'Marked as %e but with no contract linked: there will be no way to know whose it is.',
    'Ese contrato ya está asociado a %u. Si no es una operación de varias unidades, revísalo.':
      'That contract is already linked to %u. Unless this is a multi-unit deal, check it.',
    'El estado lo lleva el contrato y el dinero, no una persona: una Carta de Reserva deja la parcela':
      'The status is driven by the contract and the money, not by a person: a Reservation Letter leaves the plot',
    '(firmarla no la mueve); un Bloqueo de Parcela firmado la deja':
      '(signing it does not move it); a signed Plot Block leaves it',
    '; el primer recibí real la pasa a': '; the first real receipt moves it to',
    ', y el 100% cobrado a': ', and 100% collected to',
    '. Si se le quita la parcela al contrato o se borra, vuelve a disponible sola.':
      '. If the plot is unlinked from the contract, or the contract is deleted, it goes back to available on its own.',
    'Esta parcela está vinculada a un contrato, así que su estado y su contrato':
      'This plot is linked to a contract, so its status and its contract',
    'no se actualiza solo': 'does not update on its own',
    'y hay que tocarlo a mano.': 'and has to be set by hand.',
    ': los lleva el contrato. Para soltarla, quítale la parcela al contrato o bórralo, y volverá a estar disponible sola.':
      ': the contract drives them. To free it, unlink the plot from the contract or delete it, and it will become available again on its own.',
    'Borrar la parcela': 'Delete the plot',
    'Borrar la parcela «%c»': 'Delete plot “%c”',
    'Solo se puede si no tiene un contrato ni fotos de obra colgando. Si tiene algo, el sistema lo rechaza y dice qué queda por soltar.':
      'Only possible if it has no contract and no construction photos attached. If it has any, the system refuses and says what is left to free.',
    'No se puede deshacer desde aquí.': 'It cannot be undone from here.',
    'Parcela borrada': 'Plot deleted',
    'Importar CSV': 'Import CSV',
    'Importar unidades desde CSV': 'Import units from CSV',
    'Leyendo…': 'Reading…',
    'Fila': 'Row',
    'filas leídas': 'rows read',
    'actualizan una unidad existente': 'update an existing unit',
    'con error, no se importan': 'with an error, not imported',
    'Alta nueva': 'New entry',
    'Actualiza': 'Updates',
    'Confirmar importación': 'Confirm import',
    'Confirmar importación (%n)': 'Confirm import (%n)',
    'Nada que importar': 'Nothing to import',
    'Importando…': 'Importing…',
    'Añadido': 'Added',


    /* ---------- KYC y documentos del comprador: un solo juego de rótulos ----------
       Los usan Operaciones y Compradores, cada uno con su mapa, y las claves
       (`pending`, `passport`, `proof_of_funds`…) son las de la base. */
    'En revisión': 'Under review',
    'Aprobado': 'Approved',
    'Rechazado': 'Rejected',
    'Visado': 'Visa',
    'Justificante de fondos': 'Proof of funds',
    'Justificante de domicilio': 'Proof of address',
    'Documento': 'Document',

    /* ---------- Portal del comprador: los motivos que devuelve la edge ---------- */
    'Ese correo ya es de un usuario del equipo. Una misma cuenta no puede ser del equipo y del portal a la vez.':
      'That email already belongs to a team user. One account cannot be both team and portal.',
    'Para probar el portal, usa otro correo (con Gmail vale tucorreo+portal@gmail.com: llega al mismo buzón y cuenta como distinto).':
      'To test the portal, use another email (with Gmail, youraddress+portal@gmail.com works: it lands in the same inbox and counts as different).',
    'Ese correo no tiene una forma válida.': 'That email is not a valid address.',
    'No se ha podido saber a qué ficha dar acceso. Recarga la página e inténtalo otra vez.':
      'Could not tell which record to grant access to. Reload the page and try again.',
    'Hace falta ser administrador para invitar o revocar accesos.':
      'You must be an administrator to invite or revoke access.',
    'La contraseña necesita 10 caracteres o más.': 'The password needs 10 characters or more.',
    'Ese email no tiene acceso al portal todavía — invítalo primero.':
      'That email has no portal access yet — invite them first.',


    'Desactivado': 'Deactivated',
    'Alcance': 'Scope',


    /* ---------- Facturas, proformas y recibís ----------
       VOCABULARIO, y conviene que no se mueva de aquí:
         factura  = invoice     (lo que se debe, con su serie INV)
         proforma = proforma    (informativa: anuncia el total, no factura)
         recibí   = receipt     (dinero que YA ha entrado, serie REC)
       El error caro de esta herramienta fue sumar las tres como si fueran lo
       mismo; que en inglés se llamen distinto es parte de que no vuelva a
       pasar. «Recibí» NUNCA es «received»: es el documento. */
    'Nuevo documento': 'New document',
    'Nueva factura': 'New invoice',
    'Crear recibí': 'Create receipt',
    'Factura proforma': 'Proforma invoice',
    'Tipo de documento': 'Document type',
    'Cada tipo lleva su propia serie: INV, PRO, REC': 'Each type has its own series: INV, PRO, REC',
    'Buscar nº, cliente, proyecto o contrato…': 'Search no., client, project or contract…',
    'Vigentes': 'Live',
    'Con anuladas': 'Including voided',
    'Lista': 'List',
    'Por contrato': 'By contract',
    'Nº de documento': 'Document no.',
    'Lo asigna la base al guardar': 'The database assigns it on save',
    'Fechas': 'Dates',
    'Fecha de emisión': 'Issue date',
    'Vencimiento (opcional)': 'Due date (optional)',
    'Emisor': 'Issuer',
    'Sociedad que factura': 'Invoicing company',
    'Cuenta donde se cobra': 'Account to be paid into',
    'Sin cuenta, el documento no imprime datos bancarios.':
      'With no account, the document prints no bank details.',
    'Otros — escribir la cuenta a mano': 'Other — type the account by hand',
    '— sin datos bancarios —': '— no bank details —',
    'Titular · Holder': 'Titular · Holder',
    'Banco · Bank': 'Banco · Bank',
    'Cuenta · Account': 'Cuenta · Account',
    'Swift / Routing': 'Swift / Routing',
    'Dirección del banco · Address': 'Dirección del banco · Address',
    'Nota · Note (opcional)': 'Nota · Note (optional)',
    'Si esta cuenta se va a repetir, pídenos darla de alta en la lista.':
      'If this account is going to come up again, ask us to add it to the list.',
    'Nombre o razón social': 'Name or registered name',
    'Pasaporte / NPWP / NIF': 'Passport / NPWP / tax ID',
    'Proyecto / unidad': 'Project / unit',
    'Ej. Palm Field — Cabana 2BR S2': 'e.g. Palm Field — Cabana 2BR S2',
    'Ábrelo para traer los datos de la ficha.': 'Open it to pull in the details from the record.',
    'Conceptos': 'Line items',
    '+ Añadir concepto': '+ Add line item',
    '+ Añadir otra factura': '+ Add another invoice',
    'Lo que se ha cobrado': 'What has been collected',
    'Importe cobrado': 'Amount collected',
    'Justificante de pago (obligatorio)': 'Proof of payment (required)',
    'Adjunta el justificante de pago': 'Attach the proof of payment',
    'Sin justificante': 'No proof of payment',
    'Un recibí admite hasta 8 justificantes (ya lleva ': 'A receipt takes up to 8 proofs of payment (it already has ',
    'Etiqueta': 'Label',
    'Ej. PPN': 'e.g. PPN',
    'Porcentaje': 'Percentage',
    'Ej. 11': 'e.g. 11',
    'En blanco, el documento no lleva impuesto.': 'Left blank, the document carries no tax.',
    'Condiciones de pago, referencia de transferencia…': 'Payment terms, transfer reference…',
    'Vista previa': 'Preview',
    'Asunto': 'Subject',
    '— elige un contrato —': '— choose a contract —',
    'Sin contrato': 'No contract',
    'Cargando contrato…': 'Loading contract…',
    'Elige el contrato al que corresponde este documento': 'Choose the contract this document belongs to',
    'Ese contrato no tiene hitos de pago que traer': 'That contract has no payment milestones to pull in',
    'De este contrato hay': 'On this contract there are',
    'Facturado': 'Invoiced',
    'Sin hitos facturados': 'No milestones invoiced',
    'Cobrado sin factura': 'Collected without an invoice',
    'Sin recibí': 'No receipt',
    '· Cobrado': '· Collected',
    'Abre el listado una vez para ver aquí cuánto lleva cobrado este contrato.':
      'Open the list once to see here how much has been collected on this contract.',
    'Total del proyecto': 'Project total',
    'El proyecto se factura de una vez': 'The project is invoiced in one go',
    'Una sola factura por el importe completo, sin hitos': 'A single invoice for the full amount, no milestones',
    'Se factura el hito que se haya alcanzado.': 'The milestone that has been reached is invoiced.',
    'Lo que se le comunica al cliente. Informativo: no factura ni vence':
      'What the client is told. Informational: it does not invoice and does not fall due',
    'Proforma precargada con el total del proyecto': 'Proforma preloaded with the project total',
    'Conceptos vaciados: el total del proyecto es de la proforma, no de una factura':
      'Line items cleared: the project total belongs on the proforma, not on an invoice',
    'El documento ya tiene conceptos. Poner': 'The document already has line items. Setting',
    'Sustituye los conceptos por': 'Replace the line items with',
    'los reemplaza por una sola línea con el importe completo.':
      'replaces them with a single line for the full amount.',
    'Toda la unidad · los dos contratos': 'The whole unit · both contracts',
    'Todo el contrato': 'The whole contract',
    'todo el contrato': 'the whole contract',
    'La venta está en dos contratos:': 'The sale sits across two contracts:',
    ': el precio total de cada uno de los dos contratos.': ': the total price of each of the two contracts.',
    'Dos líneas y no una a propósito: son dos relaciones jurídicas con el mismo comprador, y fundirlas borra a qué contrato corresponde cada euro.':
      'Two lines and not one, on purpose: they are two legal relationships with the same buyer, and merging them erases which contract each euro belongs to.',
    'dos líneas': 'two lines',
    'no son un contrato: no se suman entre sí': 'are not a contract: they do not add up together',
    'Se hace así a propósito: dejar los dos cobraría el total':
      'It is done this way on purpose: leaving both would charge the total',
    'Lo normal es': 'The usual thing is',
    'Quitad': 'Remove',
    'es el otro. Puedes cobrar los dos en este mismo documento.':
      'is the other. You can collect both on this same document.',
    '— pulsa para cobrarlo entero.': '— click to collect it in full.',
    'Factura por la unidad completa: ': 'Invoice for the whole unit: ',
    'Pero lo emite': 'But it is issued by',
    ', así que no se puede combinar en la misma factura: sería una sociedad cobrando el ingreso de otra.':
      ', so it cannot be combined on the same invoice: that would be one company collecting another’s income.',
    'Hay más de ': 'There are more than ',
    'Elige al menos una factura que salde este recibí': 'Choose at least one invoice this receipt settles',
    'Falta el importe aplicado a ': 'The amount applied to ',
    'Esa factura ya no tiene saldo pendiente, o está anulada — no hay nada que cobrar en un recibí.':
      'That invoice has no balance left, or is voided — there is nothing for a receipt to collect.',
    'Falta el nombre del cliente': 'The client’s name is missing',
    'El documento no tiene importe': 'The document has no amount',
    'Guardada como ': 'Saved as ',
    'El número': 'The number',
    'no se reutiliza': 'is not reused',
    'y ya no se podrá editar.': 'and it can no longer be edited.',
    'Factura ': 'Invoice ',
    'Factura anulada': 'Invoice voided',
    'Factura anulada: se abre como borrador nuevo': 'Invoice voided: it opens as a fresh draft',
    'La factura se queda en el registro marcada como anulada, así que el rastro no se pierde.':
      'The invoice stays in the record marked as voided, so the trail is not lost.',
    ': así queda el rastro y la serie no pierde un número.':
      ': that way the trail is kept and the series does not lose a number.',
    'Factura borrada': 'Invoice deleted',
    'Borrarla deja un': 'Deleting it leaves a',
    'hueco en la numeración': 'gap in the numbering',
    'que habrá que explicarle a un contable. No hay papelera.':
      'that will have to be explained to an accountant. There is no undo.',
    'No tienes permiso para borrar facturas': 'You do not have permission to delete invoices',
    'No se pudo anular: ': 'Could not void: ',
    'No se pudo anular: no es tuya o ya está anulada': 'Could not void: it is not yours, or it is already voided',
    'Esta factura ya está guardada, así que no se pierde. Se abre un recibí nuevo enganchado a ella.':
      'This invoice is already saved, so nothing is lost. A new receipt opens attached to it.',
    'Guarda la factura antes de crear un recibí desde ella': 'Save the invoice before creating a receipt from it',
    'El documento que tienes abierto ya está guardado, así que no se pierde. Se limpia el formulario para empezar otro.':
      'The document you have open is already saved, so nothing is lost. The form is cleared to start another.',
    'Guarda el documento antes de enviarlo': 'Save the document before sending it',
    'Guarda el documento para ver su registro': 'Save the document to see its log',
    'Sin correos registrados para este documento.': 'No emails logged for this document.',
    'Email de destinatario no válido': 'Invalid recipient email',
    'Enviada': 'Sent',
    'Enviado a ': 'Sent to ',
    'el hito, y el documento saldría creíble.': 'the milestone, and the document would come out looking plausible.',
    'Autor reasignado a ': 'Author reassigned to ',
    'No se encontró ese documento': 'That document was not found',
    'No se han podido cargar las cuentas de cobro: ': 'Could not load the collection accounts: ',
    'No se pudieron cargar las facturas abiertas: ': 'Could not load the open invoices: ',
    'No se pudo comprobar de quién son las facturas: ': 'Could not check whose the invoices are: ',
    'No se pudo cargar la lista de contratos: ': 'Could not load the contract list: ',
    'No se pudo abrir el justificante: ': 'Could not open the proof of payment: ',
    'No se pudo subir ': 'Could not upload ',
    'Error: ': 'Error: ',


    /* ---------- CRM de leads ----------
       Un «lead» es un lead en los dos idiomas: el equipo ya lo llama así y
       traducirlo a «prospect» solo añadiría una palabra que nadie usa.
       «Closer» y «Setter» igual. Lo que sí se traduce es todo lo demás. */
    'Mis leads': 'My leads',
    'Todo el equipo': 'Whole team',
    'Solo mías': 'Mine only',
    'tuyas': 'yours',
    'tú': 'you',
    'Lead': 'Lead',
    '%n lead': '%n lead',
    '%n leads': '%n leads',
    'Buscar por nombre, email o teléfono…': 'Search by name, email or phone…',
    'Buscar en la bandeja…': 'Search the inbox…',
    'Ningún lead con ese filtro.': 'No lead matches that filter.',
    'Todavía no ha entrado ningún lead.': 'No lead has come in yet.',
    'Todavía no ha entrado ningún lead, así que no hay campañas que configurar.':
      'No lead has come in yet, so there are no campaigns to configure.',
    /* las seis columnas del embudo */
    'Nuevo': 'New',
    'Acaba de entrar, nadie lo ha tocado': 'Just arrived, nobody has touched it',
    'Contactado': 'Contacted',
    'Se le ha escrito o llamado': 'They have been written to or called',
    'Visita': 'Visit',
    'Ha visto el terreno o la villa': 'They have seen the land or the villa',
    'Reserva': 'Reservation',
    'Carta de reserva firmada': 'Reservation letter signed',
    'Contrato de compraventa firmado': 'Sale contract signed',
    'Perdido': 'Lost',
    'No sigue adelante': 'Not going ahead',
    'Sin contactar': 'Not contacted',
    'Sin tocar': 'Untouched',
    'sin origen': 'no source',
    'Origen': 'Source',
    'Campaña': 'Campaign',
    '%n campañas': '%n campaigns',
    'todos los canales': 'all channels',
    'De un formulario de Meta a una tarjeta en el pipeline.':
      'From a Meta form to a card on the pipeline.',
    /* tarjeta y ficha del lead */
    'Sin dueño': 'Unowned',
    'Es mío': 'Mine',
    'Soltarlo': 'Release it',
    'Asignar': 'Assign',
    'Asignar a otra persona': 'Assign to someone else',
    'Pasárselo a': 'Hand it to',
    'Pasárselo a otra persona': 'Hand it to someone else',
    'Quién lo lleva': 'Who owns it',
    'Ya es tuyo.': 'It is yours now.',
    'Asignado a %q': 'Assigned to %q',
    'Lead devuelto al montón.': 'Lead returned to the pool.',
    'Nadie lo lleva todavía. Si lo coges, tus tareas y tu «mis leads» lo incluyen.':
      'Nobody owns it yet. If you take it, it joins your tasks and your “my leads”.',
    'Lo lleva otra persona. Para cambiarlo, habla con un administrador.':
      'Someone else owns it. To change that, talk to an administrator.',
    'Este lead está huérfano de hecho: conviene reasignarlo a alguien que lo trabaje.':
      'This lead is effectively orphaned: it should be reassigned to someone who will work it.',
    'Esa tarjeta la ha movido otra persona. Recargo la lista.':
      'Someone else moved that card. Reloading the list.',
    'Ese lead ha cambiado de manos mientras mirabas. Recargo.':
      'That lead changed hands while you were looking. Reloading.',
    'Ver contacto': 'View contact',
    'Acciones registradas': 'Logged actions',
    'Sin actuaciones registradas.': 'No actions logged.',
    'Última actividad': 'Last activity',
    'Última actuación': 'Last action',
    'Lo que han hecho': 'What they have done',
    'Qué hizo': 'What they did',
    'Cargando actividad…': 'Loading activity…',
    'Qué contestó en el formulario': 'What they answered on the form',
    'Presupuesto': 'Budget',
    'Cuándo compra': 'When they buy',
    'Para qué': 'What for',
    'Este lead no dejó email.': 'This lead left no email.',
    'Este lead no dejó ni email ni teléfono.': 'This lead left neither email nor phone.',
    'Queda registrado quién consulta los datos de contacto y cuándo.':
      'Who looks up contact details, and when, is logged.',
    'Nombre del lead': 'Lead name',
    'Teléfono del lead': 'Lead phone',
    'Notas del equipo': 'Team notes',
    'Notas del bot': 'Bot notes',
    'Añadir nota': 'Add note',
    'Sin notas.': 'No notes.',
    'No se pudo guardar la nota: ': 'Could not save the note: ',
    'Etiquetas': 'Tags',
    'Objeciones': 'Objections',
    'Por qué': 'Why',
    'Próximo paso': 'Next step',
    'Poner próximo paso': 'Set next step',
    'Próximo paso guardado.': 'Next step saved.',
    'Qué hay que hacer': 'What needs doing',
    'Escribe qué hay que hacer.': 'Write what needs doing.',
    'Falta la fecha.': 'The date is missing.',
    'Hecho': 'Done',
    'Hecho. Pon el siguiente paso cuando lo tengas.': 'Done. Set the next step when you have it.',
    'Lo que toca hoy': 'What is due today',
    'Para hoy': 'For today',
    'Con retraso': 'Overdue',
    'deberían estar hechas': 'should already be done',
    'de todo el equipo': 'of the whole team',
    'Prueba a mirar las de todo el equipo.': 'Try looking at the whole team’s.',
    'El próximo paso se pone desde la ficha de cada lead.':
      'The next step is set from each lead’s record.',
    'Vencidas y de hoy. El próximo paso de cada lead se pone desde su ficha.':
      'Overdue and due today. Each lead’s next step is set from its record.',
    '%n día de retraso': '%n day late',
    '%n días de retraso': '%n days late',
    'Abrir ficha': 'Open record',
    'Abrir el contrato': 'Open the contract',
    'hoy': 'today',
    'ayer': 'yesterday',
    'mañana': 'tomorrow',
    'Hoy': 'Today',
    'Mañana': 'Tomorrow',
    'En 3 días': 'In 3 days',
    'En una semana': 'In a week',
    '7 días': '7 days',
    'en %n días': 'in %n days',
    '%n días': '%n days',
    /* alcance y avisos */
    'Todavía no tienes ninguna campaña asignada.': 'You have no campaign assigned yet.',
    'aparece vacía: verás los leads en cuanto dirección te asigne una. No es un fallo de la herramienta.':
      'looks empty: you will see leads as soon as management assigns you one. It is not a fault in the tool.',
    'Ves los leads de tu campaña': 'You see the leads from your campaign',
    'Ves los leads de tus %n campañas': 'You see the leads from your %n campaigns',
    'Los de otras campañas los llevan otras personas.': 'The ones from other campaigns are owned by other people.',
    'Hay tipos de contrato sin columna asignada.': 'There are contract types with no column assigned.',
    'no aparecerá sugerido en Reserva ni en Contrato: ':
      'will not be suggested under Reservation or Contract: ',
    'Se arregla desde el estudio, añadiendo su fila en':
      'It is fixed from the studio, by adding its row in',
    'han firmado y siguen en otra columna': 'have signed and are still in another column',
    'Reserva o contrato': 'Reservation or contract',
    'Este lead está enlazado a su contrato de verdad, no por parecido de correo.':
      'This lead is linked to its real contract, not by a similar-looking email.',
    'Crear contrato para este lead': 'Create a contract for this lead',
    'Se abre su ficha de comprador (con los datos que dejó él) y de ahí el contrato.':
      'Their buyer record opens (with the details they left) and the contract from there.',
    'Una ficha de comprador necesita un identificador, así que hay que darla de alta a mano en':
      'A buyer record needs an identifier, so it has to be created by hand in',
    'Ya existe una ficha con ese correo: ': 'A record with that email already exists: ',
    'No se pudieron leer los leads: ': 'Could not load the leads: ',
    'No se pudo abrir la ficha.': 'Could not open the record.',
    'No se pudo abrir la ficha: ': 'Could not open the record: ',
    'No se pudo leer el lead.': 'Could not read the lead.',
    'No se pudo leer el contacto.': 'Could not read the contact details.',
    'No se pudo leer la actividad.': 'Could not read the activity.',
    'No se pudo leer la lista. Recarga la página.': 'Could not read the list. Reload the page.',
    'No se pudo leer.': 'Could not read it.',
    'No se pudo guardar el cambio: ': 'Could not save the change: ',
    'No se pudo cambiar el dueño: ': 'Could not change the owner: ',
    /* bandeja del bot de WhatsApp */
    'Conversaciones': 'Conversations',
    'Conversaciones del bot': 'Bot conversations',
    'con el bot de WhatsApp': 'with the WhatsApp bot',
    'Los mensajes del bot con cada lead, tal y como los ve el cliente.':
      'The bot’s messages with each lead, exactly as the client sees them.',
    'El bot de WhatsApp de Lawang, en vivo. Pausar detiene la IA para ese lead: a partir de ahí responde una persona.':
      'Lawang’s WhatsApp bot, live. Pausing stops the AI for that lead: from then on a person replies.',
    'Elige una conversación': 'Choose a conversation',
    'Sin conversaciones todavía.': 'No conversations yet.',
    'Sin mensajes.': 'No messages.',
    'No se pudo leer la conversación.': 'Could not read the conversation.',
    'La IA está atendiendo esta conversación.': 'The AI is handling this conversation.',
    'Pausa la IA': 'Pause the AI',
    'Pausada': 'Paused',
    'En pausa': 'Paused',
    'IA pausada para ese lead.': 'AI paused for that lead.',
    'IA reanudada para ese lead.': 'AI resumed for that lead.',
    'El bot todavía no ha sacado datos de esta conversación.':
      'The bot has not extracted any data from this conversation yet.',
    'Baja (STOP)': 'Opted out (STOP)',
    'Este lead pidió la baja (STOP). El sistema no le enviará nada más, ni bot ni persona.':
      'This lead opted out (STOP). The system will send them nothing further, bot or person.',
    'Frenada (testing)': 'Held back (testing)',
    'en solo lectura': 'read-only',
    'Escribir': 'Write',
    'Respuesta del equipo': 'Team reply',
    'arriba si quieres contestar tú.': 'above if you want to reply yourself.',
    'Elige una plantilla…': 'Choose a template…',
    'Cargando plantillas…': 'Loading templates…',
    'No hay ninguna plantilla aprobada todavía': 'There is no approved template yet',
    'No se pudieron leer las plantillas': 'Could not read the templates',
    'Rellena todos los datos de la plantilla.': 'Fill in all the template’s fields.',
    'Plantilla enviada.': 'Template sent.',
    'Enviado.': 'Sent.',
    'Explorando': 'Exploring',
    'Interesado': 'Interested',
    'Quiere reservar': 'Wants to book',
    'Escalado': 'Escalated',
    'Intención': 'Intent',
    'País': 'Country',
    'Fecha de viaje': 'Travel date',
    'Primer contacto': 'First contact',
    'Seguimientos enviados': 'Follow-ups sent',
    /* agenda de cierre */
    'Citas': 'Appointments',
    'Citas agendadas': 'Appointments booked',
    '%n cita agendada': '%n appointment booked',
    '%n citas agendadas': '%n appointments booked',
    'Sin citas agendadas.': 'No appointments booked.',
    'Sin citas agendadas todavía.': 'No appointments booked yet.',
    'Ninguna agendada.': 'None booked.',
    'nada agendado por delante': 'nothing booked ahead',
    'Nueva cita': 'New appointment',
    'Agendar llamada': 'Book a call',
    'Agenda la llamada de venta de un lead con su closer.':
      'Book a lead’s sales call with their closer.',
    'Llamada': 'Call',
    'Llamada de venta': 'Sales call',
    'Llamada de venta (Fathom.ai)': 'Sales call (Fathom.ai)',
    'Próxima llamada': 'Next call',
    'Próximas llamadas': 'Upcoming calls',
    'Fecha y hora': 'Date and time',
    'Falta la fecha y hora.': 'The date and time are missing.',
    'Contexto para quien atienda la llamada': 'Context for whoever takes the call',
    'Cita agendada.': 'Appointment booked.',
    'Cita actualizada.': 'Appointment updated.',
    'Cita borrada.': 'Appointment deleted.',
    'Borrar esta cita': 'Delete this appointment',
    'Si tiene evento de Calendar, se borra también.': 'If it has a Calendar event, that is deleted too.',
    'Cancelar edición': 'Cancel editing',
    'No se pudieron leer las citas: ': 'Could not read the appointments: ',
    'No se pudo guardar la cita: ': 'Could not save the appointment: ',
    'Rellena la fecha y guarda: el teléfono y el nombre ya van puestos.':
      'Fill in the date and save: the phone and the name are already filled in.',
    'Con Meet listo': 'With Meet ready',
    'Por confirmar': 'To confirm',
    'sin enlace todavía': 'no link yet',
    'El enlace de Google Meet se genera solo en cuanto el estudio active el acceso de Google Workspace. Hasta entonces, la cita se agenda igual — el closer comparte su propio enlace con el lead.':
      'The Google Meet link is generated automatically as soon as the studio enables Google Workspace access. Until then, the appointment is booked all the same — the closer shares their own link with the lead.',
    'Ver grabación': 'View recording',
    'Sin llamadas registradas todavía.': 'No calls logged yet.',
    'Unirse': 'Join',
    /* ranking de closers */
    'A quién se atribuye cada venta': 'Who each sale is credited to',
    'Quién vende': 'Who sells',
    'Closer': 'Closer',
    'Comercial': 'Rep',
    'Comerciales': 'Reps',
    'Venta': 'Sale',
    'Ventas': 'Sales',
    'Ticket medio': 'Average ticket',
    'Conversión': 'Conversion',
    'Solo contratos raíz': 'Root contracts only',
    'Todo lo firmado': 'Everything signed',
    'Contando solo el contrato raíz de cada cadena. El puesto lo decide el dinero cobrado.':
      'Counting only the root contract of each chain. The ranking is decided by money collected.',
    'Contando todo lo firmado, cadenas incluidas. El puesto lo decide el dinero cobrado.':
      'Counting everything signed, chains included. The ranking is decided by money collected.',
    'de cadena': 'from a chain',
    'con al menos una venta atribuida': 'with at least one sale credited',
    'El ranking todavía no está completo.': 'The leaderboard is not complete yet.',
    'Todavía no hay ninguna venta atribuida.': 'No sale has been credited yet.',
    'Todas las ventas están atribuidas.': 'Every sale is credited.',
    'Sin atribuir': 'Unattributed',
    '— sin atribuir —': '— unattributed —',
    '%n venta sin atribuir': '%n sale unattributed',
    '%n ventas sin atribuir': '%n sales unattributed',
    '%n ventas firmadas en total': '%n signed sales in total',
    'Quién lo cerró': 'Who closed it',
    'Otra persona ha cambiado esa atribución. Recargo.':
      'Someone else changed that attribution. Reloading.',
    'Cambiar': 'Change',
    'leads con contrato firmado': 'leads with a signed contract',
    /* reparto de leads */
    'Quién atiende cada campaña': 'Who handles each campaign',
    'Reparto automático': 'Automatic routing',
    'Reparto automático encendido.': 'Automatic routing on.',
    'Reparto automático apagado.': 'Automatic routing off.',
    'Tope guardado.': 'Cap saved.',
    'Reparto encendido pero sin nadie asignado.': 'Routing on but nobody assigned.',
    'Sus leads se quedarán sin dueño.': 'Its leads will be left unowned.',
    'todas con reparto automático': 'all with automatic routing',
    '%n sin reparto automático': '%n without automatic routing',
    'Cargando el equipo…': 'Loading the team…',
    'No hay nadie más con acceso al CRM.': 'Nobody else has access to the CRM.',
    'nadie tiene acceso al CRM todavía': 'nobody has access to the CRM yet',
    'Un administrador tiene que marcar la casilla «Leads» en':
      'An administrator has to tick the “Leads” box in',
    'antes de poder repartir leads.': 'before leads can be routed.',
    'Esa cuenta está desactivada.': 'That account is deactivated.',
    'vacío = tú mismo': 'empty = yourself',
    'las lleva una persona': 'a person handles them',
    /* campañas */
    'Rendimiento por campaña': 'Performance by campaign',
    'Leads recibidos': 'Leads received',
    'Leads recibidos frente a lo invertido en Meta. El gasto lo trae el vigilante cada 4 h.':
      'Leads received against what was spent on Meta. The spend is brought in by the watchdog every 4 h.',
    'Leads y gasto, semana a semana': 'Leads and spend, week by week',
    'Invertido': 'Spent',
    'Clics': 'Clicks',
    'Coste por lead': 'Cost per lead',
    'Coste/lead': 'Cost/lead',
    'Aún no hay datos de campañas.': 'No campaign data yet.',
    'Todavía no hay cifras de gasto.': 'No spend figures yet.',
    'Sin datos todavía.': 'No data yet.',
    /* detalle de campaña (objetivo, targeting, rendimiento por conjunto — 17-sep-2026) */
    'Objetivo no disponible': 'Objective not available',
    'Datos de %f': 'Data as of %f',
    'Conjuntos de anuncios': 'Ad sets',
    'Todavía no hay foto de esta campaña. La trae el vigilante en su próxima vuelta.':
      'No snapshot of this campaign yet. The watchdog brings it on its next pass.',
    'A quién apunta:': 'Who it targets:',
    '%n–%m años': '%n–%m years old',
    'sin filtro de público (audiencia amplia)': 'no audience filter (broad audience)',
    'Presupuesto/día': 'Budget/day',
    'Invertido (14 días)': 'Spent (14 days)',
    'Leads (14 días)': 'Leads (14 days)',
    'Coste/lead (14 días)': 'Cost/lead (14 days)',
    'Clics (14 días)': 'Clicks (14 days)',
    'Generación de leads': 'Lead generation',
    'Mensajes / interacción': 'Messages / engagement',
    'Tráfico': 'Traffic',
    'Reconocimiento de marca': 'Brand awareness',
    'Ventas': 'Sales',
    'Promoción de app': 'App promotion',
    'Activo': 'Active',
    'Pausado': 'Paused',
    'Borrado': 'Deleted',
    'Archivado': 'Archived',
    'En revisión': 'In review',
    'Rechazado': 'Rejected',
    'Pausado (por su campaña)': 'Paused (by its campaign)',
    /* automatismos */
    'Reglas activas': 'Active rules',
    'El flujo': 'The flow',
    'se revisan cada 4 horas': 'checked every 4 hours',
    'las últimas que constan': 'the latest on record',
    'Hay': 'There are',
    'Ojo:': 'Careful:',
    'Comprobando…': 'Checking…',
    'Pidiendo…': 'Requesting…',
    '· Dirección': '· Leadership',
    '· WhatsApp Bot': '· WhatsApp Bot',
    'WhatsApp': 'WhatsApp',


    'Ya existe una ficha con ese correo:': 'A record with that email already exists:',
    'El lead': 'The lead',



    /* Lo que faltaba del CRM de leads: pestañas, KPIs, la vista de
       Automatismos entera, el chat del Setter y los errores de Meta
       (14-sep-2026). */
    'Refrescar': 'Refresh',
    'Pipeline': 'Pipeline',
    'Bandeja': 'Inbox',
    'Campañas': 'Campaigns',
    'Automatismos': 'Automations',
    'Setter IA': 'AI Setter',
    'Closers': 'Closers',
    /* Trazabilidad del CRM (23-sep-2026): cruce con las cuentas GoHighLevel de los sales managers. */
    'Elige uno…': "Choose one…",
    'Solo lectura: nunca se escribe en la cuenta del sales manager. Una cuenta nace apagada hasta que la actives.': "Read-only: nothing is ever written to the sales manager's account. An account starts switched off until you activate it.",
    'Ninguna cuenta activa.': "No active account.",
    'Trazabilidad': "Traceability",
    'Personas en más de un funnel': "People in more than one funnel",
    'Sincronizar ahora': "Sync now",
    'Cuentas GoHighLevel conectadas': "Connected GoHighLevel accounts",
    'Location ID': "Location ID",
    'Etiqueta de contactos Lawang': "Tag for Lawang contacts",
    'Token (pit-…) con permiso solo de lectura de contactos': "Token (pit-…) with contacts read-only permission",
    'Conectar cuenta': "Connect account",
    'Una coincidencia es una señal para revisar, no un veredicto: que alguien esté en dos funnels no prueba que juegue a dos bandas. El descuento se decide con la política de siempre.': "A match is a signal to review, not a verdict: being in two funnels does not prove someone is playing both sides. Discounts follow the usual policy.",
    'La sincronización respondió %s': "Sync responded %s",
    'Sin ficha en Lawang': "No Lawang record",
    'En más de un funnel': "In more than one funnel",
    'personas': "people",
    'Ya compradores': "Already buyers",
    'con ficha de comprador en Lawang': "with a Lawang buyer record",
    'En dos sales managers': "With two sales managers",
    'en las cuentas de dos o más': "in the accounts of two or more",
    'Cuentas activas': "Active accounts",
    'cuentas GoHighLevel': "GoHighLevel accounts",
    'Última sincronización: %f': "Last sync: %f",
    'Todavía no se ha sincronizado ninguna cuenta': "No account has been synced yet",
    'teléfono': "phone",
    '%n funnels': "%n funnels",
    'Nadie aparece en más de un funnel.': "Nobody appears in more than one funnel.",
    'Sin cuentas activas todavía: no hay nada que cruzar.': "No active accounts yet: nothing to cross-check.",
    'Última pasada': "Last run",
    '%c contactos · %m con Lawang': "%c contacts · %m with Lawang",
    'falló': "failed",
    'Apagada': "Off",
    'Probar': "Test",
    'Apagar': "Switch off",
    'Activar': "Activate",
    'Cambiar token': "Change token",
    'Ninguna cuenta conectada.': "No accounts connected.",
    'Leyendo la cuenta… puede tardar un minuto.': "Reading the account… this may take a minute.",
    'Prueba en seco': "Dry run",
    '%c contactos leídos con la etiqueta. %m coinciden con leads o compradores de Lawang. No se ha guardado nada.': "%c contacts read with the tag. %m match Lawang leads or buyers. Nothing was saved.",
    'Apagar la cuenta': "Switch off the account",
    'Se dejan de leer sus contactos y se borran sus coincidencias guardadas.': "Its contacts stop being read and its saved matches are deleted.",
    'Cuenta apagada.': "Account switched off.",
    'Cuenta activada. Entra en la próxima sincronización.': "Account activated. It will be included in the next sync.",
    'Cambiar token de %n': "Change token for %n",
    'Pega el token nuevo (pit-…). Se comprueba contra GoHighLevel antes de guardarlo.': "Paste the new token (pit-…). It is checked against GoHighLevel before saving.",
    'Token cambiado. %c contactos con la etiqueta.': "Token changed. %c contacts with the tag.",
    'Borrar la cuenta': "Delete the account",
    'Se borran su token y todas sus coincidencias. No se puede deshacer.': "Its token and all its matches are deleted. This cannot be undone.",
    'Cuenta borrada.': "Account deleted.",
    'Faltan datos: sales manager, Location ID, etiqueta y token.': "Missing data: sales manager, Location ID, tag and token.",
    'Cuenta conectada (apagada). %c contactos con la etiqueta.': "Account connected (off). %c contacts with the tag.",
    'Sincronizando… puede tardar un minuto.': "Syncing… this may take a minute.",
    'Alguna cuenta falló: se conserva la pasada anterior.': "An account failed: the previous run is kept.",
    'Sincronizado.': "Synced.",
    'Agendar': 'Schedule',
    'Parados +14d': 'Stalled +14d',
    'Estos automatismos los ejecuta AxisWorks sobre las campañas de Lawang, cada 4 horas.':
      'AxisWorks runs these automations on Lawang\'s campaigns, every 4 hours.',
    'Aquí se ven': 'Here you see them',
    ': qué vigila cada regla y qué ha hecho de verdad.':
      ': what each rule watches and what it has actually done.',
    'Para cambiar un umbral o un tope de gasto, habla con el estudio.':
      'To change a threshold or a spending cap, talk to the studio.',
    '%n contratos': '%n contracts',
    '%p% de lo firmado ha entrado': '%p% of what was signed has come in',
    '(%s firmados) que no cuentan para nadie. Se asignan abajo, en «A quién se atribuye cada venta».':
      '(%s signed) that count for nobody. They are assigned below, under “Who each sale is credited to”.',
    '%n de cadena': '%n from chains',
    '%p% de lo suyo': '%p% of their own',
    'lo creó %s': 'created by %s',
    'No se pudo leer la agenda: ': 'Could not read the schedule: ',
    'Nada pendiente para hoy.': 'Nothing due today.',
    'Por eso esta pantalla': 'That is why this screen',
    '%n llevan más de %d días parados': '%n stalled for more than %d days',
    'de %n leads': 'of %n leads',
    'llegan a firmar': 'go on to sign',
    'Quien firme uno de esos': 'Whoever signs one of those',
    'cuenta desactivada': 'account deactivated',
    'Firmó': 'Signed',
    'mover ahí': 'move it there',
    'Entró %f': 'Came in %f',
    'Lo lleva': 'Handled by',
    'Qué ha pasado con este lead…': 'What happened with this lead…',
    'Llamar para confirmar presupuesto': 'Call to confirm budget',
    'No se pudo comprobar: ': 'Could not check: ',
    'Se usará esa, no se crea otra.': 'That one will be used, no new record is created.',
    'hay %n tarjeta más con este mismo correo.': 'there is %n more card with this same email.',
    'hay %n tarjetas más con este mismo correo.':
      'there are %n more cards with this same email.',
    'Puede que sea la misma persona duplicada.': 'It may be the same person, duplicated.',
    'Entró por': 'Came in through',
    'Pasó de %a a %b': 'Moved from %a to %b',
    '%n en los últimos 7 días': '%n in the last 7 days',
    'de las campañas medidas': 'across the measured campaigns',
    'sin datos de gasto todavía': 'no spend data yet',
    'pendiente de la primera vuelta': 'waiting for the first pass',
    'Las trae el vigilante de AxisWorks en su próxima vuelta (cada 4 horas). Los leads de abajo sí son reales y están completos.':
      'The AxisWorks watchdog brings them on its next pass (every 4 hours). The leads below are real and complete.',
    '%n campañas con datos · última actualización %f':
      '%n campaigns with data · last updated %f',
    'Sin datos de campaña todavía.': 'No campaign data yet.',
    'Leads y gasto por semana': 'Leads and spend by week',
    'gasto': 'spend',
    'leads por semana': 'leads per week',
    'invertido en Meta': 'spent on Meta',
    'el gasto aparecerá cuando el vigilante haga su primera vuelta':
      'spend will appear once the watchdog makes its first pass',
    'sin registro': 'no record',
    'Qué mira cada una y qué puede hacer.': 'What each one watches and what it can do.',
    'Las %n últimas actuaciones sobre las campañas de Lawang.':
      'The last %n actions on Lawang\'s campaigns.',
    'Todavía no consta ninguna actuación.': 'No action on record yet.',
    'Recogida de leads': 'Lead collection',
    'Baja a este CRM los leads de los formularios de Meta que estén en anuncios activos.':
      'Pulls into this CRM the leads from Meta forms on active ads.',
    'Escribe la ficha del lead. Nunca toca su estado ni sus notas.':
      'Writes the lead record. It never touches its stage or its notes.',
    'Freno por sequía': 'Dry-spell brake',
    'Un conjunto de anuncios que lleva días sin traer un solo lead.':
      'An ad set that has gone days without bringing in a single lead.',
    'Lo pausa para no seguir gastando en algo que no convierte.':
      'Pauses it so money stops going into something that is not converting.',
    'Reparto del presupuesto': 'Budget split',
    'Compara el coste por lead de cada conjunto dentro de su tope mensual.':
      'Compares each ad set\'s cost per lead within its monthly cap.',
    'Sube o baja el presupuesto diario, y reactiva lo que él mismo pausó cuando vuelve a caber.':
      'Raises or lowers the daily budget, and switches back on what it paused itself once it fits again.',
    'Tope de gasto': 'Spending cap',
    'El gasto acumulado del mes contra el tope acordado.':
      'The month\'s accumulated spend against the agreed cap.',
    'Pausa la campaña al cruzarlo. Es la jaula: ninguna otra regla puede saltársela.':
      'Pauses the campaign when it is crossed. It is the cage: no other rule can get past it.',
    'Limpieza de público': 'Audience cleanup',
    'máx. 1 cada 7 días': 'max. 1 every 7 days',
    'Franjas de edad y género con clics y gasto suficientes y cero leads.':
      'Age and gender brackets with enough clicks and spend and zero leads.',
    'Las excluye del público. Reversible y anotado.':
      'Excludes them from the audience. Reversible and logged.',
    'Anuncio en Meta': 'Meta ad',
    'Facebook e Instagram': 'Facebook and Instagram',
    'Formulario instantáneo': 'Instant form',
    'El lead deja sus datos': 'The lead leaves their details',
    'Recogida automática': 'Automatic collection',
    'Cada 4 h, sin tocar nada': 'Every 4 h, hands off',
    'Entra en «Nuevo»': 'Lands in “New”',
    'Y de ahí lo mueve una persona': 'And from there a person moves it',
    'El bot respondió %s': 'The bot replied %s',
    'El puente con el bot todavía no está activado por el estudio.':
      'The bridge to the bot has not been switched on by the studio yet.',
    'No se pudo leer el bot: ': 'Could not read the bot: ',
    'IA activa': 'AI on',
    'respondiendo sola ahora mismo': 'answering on their own right now',
    'Volver a la lista': 'Back to the list',
    'Mostrar u ocultar la ficha del lead': 'Show or hide the lead record',
    'Escribe tu respuesta…': 'Write your reply…',
    'Dato %n': 'Value %n',
    'Han pasado más de 24 h desde su último mensaje: ya solo se le puede escribir con una plantilla.':
      'More than 24 h have passed since their last message: only a template can be sent now.',
    'Ese número no tiene WhatsApp.': 'That number is not on WhatsApp.',
    'Tipo de mensaje no admitido.': 'Message type not supported.',
    'La plantilla espera otro número de datos.':
      'The template expects a different number of values.',
    'Esa plantilla no existe en este idioma.': 'That template does not exist in this language.',
    'Un dato de la plantilla tiene un formato que Meta no acepta.':
      'One of the template values has a format Meta does not accept.',
    'Esa plantilla está pausada por Meta por baja calidad.':
      'That template is paused by Meta for low quality.',
    'Esa plantilla está deshabilitada por Meta.': 'That template has been disabled by Meta.',
    'La cuenta de WhatsApp está restringida por facturación: no sale ningún mensaje.':
      'The WhatsApp account is restricted over billing: no message goes out.',
    'La cuenta de WhatsApp está suspendida.': 'The WhatsApp account is suspended.',
    'El token de WhatsApp ha caducado. Avisa al estudio.':
      'The WhatsApp token has expired. Tell the studio.',
    'Demasiados mensajes seguidos. Espera un momento.':
      'Too many messages in a row. Wait a moment.',
    'Este lead pidió la baja (STOP). No se le puede escribir.':
      'This lead opted out (STOP). They cannot be written to.',
    'Ese teléfono no es un lead de este bot.': 'That phone is not a lead of this bot.',
    'quedan %n h': '%n h left',
    'queda menos de 1 h': 'less than 1 h left',
    'Ventana de WhatsApp abierta —': 'WhatsApp window open —',
    'para escribir texto libre.': 'to write free text.',
    'Han pasado más de 24 h desde su último mensaje.':
      'More than 24 h have passed since their last message.',
    'Este lead nunca ha escrito al bot.': 'This lead has never written to the bot.',
    'WhatsApp solo permite contactarle con una': 'WhatsApp only allows contacting them with an',
    'plantilla aprobada': 'approved template',
    'Ganado': 'Won',
    'No se presentó': 'No-show',
    '%n todavía por llegar': '%n still to come',
    '%n sin enlace automático': '%n with no automatic link',

    'Acceso~puerta': 'Sign in',
    'Soy del equipo': 'I am staff',
    'Soy cliente': 'I am a client',


    /* ---------- Contratos (el generador) ----------
       ⚠️ SOLO LA INTERFAZ. El TEXTO DEL DOCUMENTO no está aquí ni puede
       estarlo: su idioma lo decide `LANG` (ES/EN/ID guardado con cada
       contrato), no la preferencia de quien lo emite. En `app.html` esa
       frontera está marcada con `/* lwT:no-tocar *​/`. */
    'Contratos guardados': 'Saved contracts',
    'Buscar por número, comprador, proyecto o autor…': 'Search by number, buyer, project or author…',
    'Creado': 'Created',
    'Creado por': 'Created by',
    'Dado de alta por': 'Added by',
    'sin registrar': 'not recorded',
    'Documento anterior al registro de autor': 'Created before authors were recorded',
    'Detalle': 'Detail',
    'Qué': 'What',
    'quién': 'who',
    'cuándo': 'when',
    'Copia': 'Copy',
    'Cobro': 'Billing',
    'Rastro': 'Trail',
    'Contrato ': 'Contract ',
    'Tipo de contrato desconocido': 'Unknown contract type',
    'Es de tipología': 'It is of type',
    'No tienes ningún tipo de contrato asignado. Pídeselo a un administrador antes de empezar.':
      'You have no contract type assigned. Ask an administrator for one before you start.',
    'Plantilla no encontrada.': 'Template not found.',
    'Supabase no disponible': 'Supabase unavailable',
    'No se pudo abrir el contrato': 'Could not open the contract',
    'Esa ficha de cliente ya no existe: empieza el contrato buscándolo':
      'That client record no longer exists: start the contract by searching for them',
    'Ese resultado no tiene ficha: elige un cliente registrado':
      'That result has no record: choose a registered client',
    'El comprador de un contrato sale de su ficha de': 'A contract’s buyer comes from their record in',
    'búscalo': 'find them',
    'Si ya está registrado,': 'If they are already registered,',
    'Pon el nombre del comprador': 'Enter the buyer’s name',
    'Pon un email válido del comprador': 'Enter a valid email for the buyer',
    'Ponle el email en «Adquirientes adicionales» y vuelve a intentarlo.':
      'Put their email under “Additional buyers” and try again.',
    'Estos compradores están escritos a mano y no salen de ninguna ficha:':
      'These buyers were typed by hand and come from no record:',
    ', pero el enlace que hay en la base apunta a otra ficha.':
      ', but the link in the database points to a different record.',
    'Contrato nuevo para ': 'New contract for ',
    'Contrato nuevo con los datos de ': 'New contract using the details of ',
    'Nuevo contrato con estos datos': 'New contract with these details',
    /* edición del texto de la plantilla */
    'Edición ON · reescribe el texto libre; lo resaltado en dorado son campos del formulario y no se toca aquí':
      'Editing ON · rewrite the free text; anything highlighted in gold is a form field and is not edited here',
    'Texto original restaurado': 'Original text restored',
    'Se pierden': 'You lose',
    'tus ediciones de texto': 'your text edits',
    'en esta plantilla. Los campos rellenos y las cláusulas no se tocan.':
      'on this template. Filled-in fields and clauses are untouched.',
    'OJO: ': 'CAREFUL: ',
    'Ese campo está vacío en este contrato — no hay nada que imprima todavía':
      'That field is empty on this contract — there is nothing it prints yet',
    'Los Artículos 2 y 3 remiten a los Apéndices (planos y especificaciones), así que el comprador firmaría un contrato que se refiere a documentos que no están.':
      'Articles 2 and 3 refer to the Appendices (plans and specifications), so the buyer would be signing a contract that points to documents that are not there.',
    'y no lleva anexos adjuntos.': 'and carries no attached annexes.',
    'Espera: se está preparando el anexo de ': 'Hold on: the annex is being prepared for ',
    /* guardar */
    'Contrato bloqueado, no se puede guardar': 'Contract locked, it cannot be saved',
    'Este contrato está enviado a firma: pulsa «Editar (anula la firma)» para poder guardarlo':
      'This contract has been sent for signing: click “Edit (voids the signature)” to be able to save it',
    'Elige a qué parcela pertenece esta Construcción antes de guardarla':
      'Choose which plot this Construction contract belongs to before saving it',
    'Elige el contrato al que acompaña este Poder Notarial antes de guardarlo':
      'Choose the contract this Power of Attorney goes with before saving it',
    'El poder se guarda, pero sin pasaporte ni email del otorgante no se puede saber qué contratos cubre':
      'The power of attorney is saved, but without the grantor’s passport or email there is no way to tell which contracts it covers',
    'Contrato guardado, pero la proforma automática no se pudo crear: ':
      'Contract saved, but the automatic proforma could not be created: ',
    'Guardado, pero no se pudo enlazar con su lead: ': 'Saved, but it could not be linked to its lead: ',
    'Guardado, pero no se pudo registrar el salto: ': 'Saved, but the override could not be logged: ',
    'Las facturas y las unidades': 'The invoices and the units',
    'se borran: se quedan sin el vínculo.': 'are not deleted: they are left without the link.',
    'Se van con él': 'They go with it',
    'sus firmas y sus compradores enlazados': 'its signatures and its linked buyers',
    'Fecha guardada en formato antiguo en: ': 'Date stored in the old format in: ',
    'No se han podido cargar los campos del formulario (': 'Could not load the form fields (',
    'No se han podido cargar los datos del apoderado: ': 'Could not load the attorney-in-fact’s details: ',
    'No se han podido cargar las credenciales del firmante: ': 'Could not load the signer’s credentials: ',
    /* firma electrónica */
    'Firma automática': 'Electronic signature',
    'Enviar a firma': 'Send for signing',
    'El comprador firma desde el enlace. El PDF firmado entra solo y bloquea el contrato.':
      'The buyer signs from the link. The signed PDF comes in by itself and locks the contract.',
    'Generar enlace de firma': 'Generate signing link',
    'Genera primero el enlace': 'Generate the link first',
    'Enlace de firma generado': 'Signing link generated',
    'Enlaces de firma': 'Signing links',
    'Enlace copiado': 'Link copied',
    'Copiar enlace': 'Copy link',
    'Caduca en 30 días.': 'Expires in 30 days.',
    'Expira / Firmado': 'Expires / Signed',
    'En cuanto firme el anterior,': 'As soon as the previous one signs,',
    'la cadena se parará ahí': 'the chain will stop there',
    'El contrato no tiene ningún firmante con nombre': 'The contract has no named signer',
    'Guarda el contrato antes de enviarlo a firma': 'Save the contract before sending it for signing',
    'Guarda el contrato antes de enviarlo': 'Save the contract before sending it',
    'Guarda el contrato antes de subir el firmado': 'Save the contract before uploading the signed copy',
    'Guarda el contrato para ver su registro': 'Save the contract to see its log',
    /* Qué se ve y qué se apaga en el generador (pintaAcciones, 23-sep-2026):
       el motivo que sale al pasar por encima de un botón apagado. */
    'El contrato está firmado y bloqueado': 'The contract is signed and locked',
    'Hay firmas en curso: anúlalas primero': 'Signatures are in progress: cancel them first',
    'Guarda primero: para guardar hay que rellenarlo entero': 'Save first: to save, every field has to be filled in',
    'Rellena el nombre del proyecto antes de guardar': 'Fill in the project name before saving',
    'Descarga o envía el PDF primero: no se puede subir firmado algo que no ha salido':
      'Download or send the PDF first: you cannot upload a signed copy of something that never went out',
    'Aún no hay registro: el contrato no está guardado': 'No log yet: the contract is not saved',
    'Aún no hay PDF firmado': 'No signed PDF yet',
    // cara v4 del generador (generador-v4.js): grupos y estado
    'Firma': 'Signing',
    'Sin guardar': 'Not saved',
    'En firma': 'Out for signing',
    'Taller del documento': 'Document workshop',
    'No hay firmas en curso que anular': 'There are no signatures in progress to cancel',
    'Solo se desbloquea un contrato firmado': 'Only a signed contract can be unlocked',
    'No se pudo comprobar si el PDF ya salió: «Subir firmado» queda apagado hasta descargarlo':
      'Could not check whether the PDF has gone out: «Upload signed» stays off until you download it',
    'El PDF se ha descargado, pero no se pudo apuntar en el registro':
      'The PDF was downloaded, but it could not be recorded in the log',
    'Guarda primero: sin guardar no hay número, y el PDF saldría idéntico a uno emitido sin existir en la base.':
      'Save first: unsaved there is no number, and the PDF would look identical to one issued without existing in the database.',
    'No se pudo generar: ': 'Could not generate: ',
    'No se pudo generar el enlace de descarga': 'Could not generate the download link',
    'No se pudo comprobar si este contrato está enviado a firma':
      'Could not check whether this contract has been sent for signing',
    'No se pudo comprobar el estado de las firmas: ': 'Could not check the status of the signatures: ',
    'Este contrato ya no tiene firmas vivas': 'This contract no longer has live signatures',
    'Hay': 'There are',
    'La copia de lo que se firmó se conserva como prueba. No se borra nada.':
      'The copy of what was signed is kept as evidence. Nothing is deleted.',
    'Desmárcalo si todavía no habían recibido el enlace.': 'Untick it if they had not received the link yet.',
    'Ningún firmante tiene email en el contrato: no se puede avisar a nadie.':
      'No signer has an email on the contract: nobody can be notified.',
    'No se pudieron anular las firmas: ': 'Could not void the signatures: ',
    'Firmas anuladas · ya puedes editar': 'Signatures voided · you can edit now',
    'Aviso enviado a ': 'Notice sent to ',
    'Avisado': 'Notified',
    'Aviso:': 'Notice:',
    'Reabre el modal de firma': 'Reopen the signing dialog',
    'Guarda el contrato antes de enviarlo a firma: se ha retirado un anexo subido a mano':
      'Save the contract before sending it for signature: a manually uploaded annex has been removed',
    'Sin el Anexo Maestro no se puede enviar a firma. Pídeselo a administración (Modelos → Documentos, tipo Plano) o actívalo en Anexos.':
      'It cannot be sent for signature without the Master Annex. Ask administration for it (Models → Documents, type Plan) or switch it on in Annexes.',
    'Este contrato está': 'This contract is',
    'firmado y cerrado': 'signed and closed',
    'Queda registrado en el historial del contrato:': 'It is recorded in the contract’s history:',
    'lo desbloqueó y': 'unlocked it and',
    'Como super admin': 'As a super admin',
    'No se pudo desbloquear: ': 'Could not unlock: ',
    'Contrato desbloqueado y registrado': 'Contract unlocked and logged',
    /* PDF firmado a mano */
    'El archivo debe ser un PDF': 'The file must be a PDF',
    'El PDF supera los 100MB': 'The PDF is over 100 MB',
    'No se pudo bloquear: ': 'Could not lock: ',
    'Contrato bloqueado · PDF firmado guardado': 'Contract locked · signed PDF saved',
    'Cerrado, pero no se pudieron anular los enlaces de firma vivos: ':
      'Closed, but the live signing links could not be voided: ',
    'Enlace(s) de firma pendientes anulados al cerrar': 'Pending signing link(s) voided on closing',
    'Contrato cerrado. No se pudo abrir el aviso de copias: ':
      'Contract closed. The copies notice could not be opened: ',
    /* copias del contrato firmado */
    'Copias del contrato firmado': 'Copies of the signed contract',
    'El contrato ya está cerrado. ¿Se les manda ahora la copia del PDF firmado a los compradores?':
      'The contract is now closed. Should the signed PDF be sent to the buyers now?',
    'Se manda una copia del PDF firmado a:': 'A copy of the signed PDF is sent to:',
    'Copia enviada a ': 'Copy sent to ',
    'No salió a: ': 'Did not go out to: ',
    'Se puede hacer luego desde «Registro» → Copias del contrato firmado.':
      'It can be done later from “Log” → Copies of the signed contract.',
    'No hay PDF firmado guardado en este contrato, así que no hay copia que mandar.':
      'There is no signed PDF stored on this contract, so there is no copy to send.',
    'Este contrato no tiene ni firmas electrónicas ni compradores con datos, así que no hay a quién mandarle una copia.':
      'This contract has neither electronic signatures nor buyers with details, so there is nobody to send a copy to.',
    'Este contrato se cerró subiendo el PDF firmado a mano, no por firma electrónica: los destinatarios son los compradores del contrato, y nada se les ha mandado solo.':
      'This contract was closed by uploading the signed PDF by hand, not by electronic signature: the recipients are the contract’s buyers, and nothing has been sent to them automatically.',
    'Todos los firmantes de este contrato han firmado ya': 'Every signer on this contract has already signed',
    'Todos constan como ya avisados: esto es un': 'All are on record as already notified: this is a',
    'reenvío': 'resend',
    'Este contrato se firmó antes de que se registraran estos envíos: lo más probable es que ya recibieran su copia, así que esto es un':
      'This contract was signed before these sends were logged: they most likely already received their copy, so this is a',
    'Este contrato se firmó antes del 24-ago-2026, cuando el reparto automático todavía no dejaba registro. Lo más probable es que las copias salieran; aquí no se puede confirmar.':
      'This contract was signed before 24 Aug 2026, when automatic distribution left no log yet. The copies most likely went out; it cannot be confirmed here.',
    /* registro de envíos */
    'Registro de envíos': 'Send log',
    'Enlaces de firma de este contrato y a qué correos se ha enviado':
      'This contract’s signing links and which addresses they were sent to',
    'Correos enviados': 'Emails sent',
    'Sin registro': 'No log',
    'No consta enviada': 'No record of it being sent',
    'Enviada a ': 'Sent to ',
    'Email enviado a ': 'Email sent to ',
    'Enlace enviado a ': 'Link sent to ',
    'Sin correos registrados. El registro existe desde el 18-ago-2026: los envíos anteriores no dejaron rastro.':
      'No emails logged. The log exists since 18 Aug 2026: earlier sends left no trace.',
    'Este contrato no se ha enviado a firma electrónica.': 'This contract has not been sent for electronic signing.',
    'El enlace activo no se puede mostrar aquí (solo se guarda su huella, no el enlace). Para reenviarlo: «✍︎ Enviar a firma» → Enviar por email.':
      'The live link cannot be shown here (only its fingerprint is stored, not the link). To resend it: “✍︎ Send for signing” → Send by email.',
    'Selecciona y copia a mano': 'Select and copy by hand',
    'Sin eventos registrados.': 'No events logged.',
    'Historial del contrato': 'Contract history',
    'Está guardado con': 'It is saved with',
    'en papel': 'on paper',
    'Sin dirección': 'No address',
    'Avisa al estudio': 'Tell the studio',
    /* envío por email */
    'El mensaje está vacío': 'The message is empty',
    'El mensaje ya no incluye el enlace de firma': 'The message no longer includes the signing link',
    'Se envía la vista previa tal cual.': 'The preview is sent exactly as it looks.',
    'O adjúntalo tú mismo (opcional)': 'Or attach it yourself (optional)',
    'Descarga el PDF y hazlo llegar por el canal que corresponda.':
      'Download the PDF and get it to them through whichever channel applies.',
    'Generar': 'Generate',
    /* barra de la vista previa */
    'Vista previa del contrato': 'Contract preview',
    'Editar el texto fijo del contrato': 'Edit the contract’s fixed text',
    'Color de portada, logo y marca de agua': 'Cover colour, logo and watermark',
    'Restaurar texto original de la plantilla': 'Restore the template’s original text',
    'Genera otro contrato reutilizando estos datos': 'Generate another contract reusing these details',
    'Guarda el contrato en la base de datos': 'Save the contract to the database',
    'Enlace para que el comprador firme a distancia': 'Link for the buyer to sign remotely',
    'Anula el enlace y las firmas ya dadas, y desbloquea el formulario para editar':
      'Voids the link and any signatures given, and unlocks the form for editing',
    'Descargar el PDF ya firmado': 'Download the signed PDF',
    'Solo super admin: devuelve el contrato a editable. Queda registrado':
      'Super admin only: returns the contract to editable. It is logged',
    'PDF a mano': 'PDF by hand',
    'Sube el PDF firmado y bloquea el contrato': 'Upload the signed PDF and lock the contract',
    'Facturar': 'Invoice',
    'Abre Facturas con este contrato ya elegido': 'Opens Invoices with this contract already selected',
    'El contrato siempre incluye Bahasa Indonesia': 'The contract always includes Bahasa Indonesia',


    /* ---------- Creatividades y el constructor de dossiers ----------
       «Creatividad» en publicidad no es «creativity»: es una PIEZA, un
       creative. Los nombres de fuente (Jost, Cormorant) y los formatos de
       Meta (Feed 4:5, Story 9:16) no se traducen: son nombres propios. */
    'Creatividades de redes': 'Social creatives',
    'Dossiers': 'Brochures',
    'Todo lo que se produce para presentar un proyecto o venderlo: dossiers de producto y piezas de pauta para redes.':
      'Everything produced to present a project or sell it: product brochures and paid-social creatives.',
    'Documento de producto en A4 apaisado: portada, planos, especificaciones y galería, listo para exportar a PDF.':
      'Product document in A4 landscape: cover, floor plans, specifications and gallery, ready to export to PDF.',
    'Piezas para Instagram y Facebook con la revisión de legibilidad incorporada: contraste, tamaño mínimo y zona segura.':
      'Assets for Instagram and Facebook with the legibility check built in: contrast, minimum size and safe zone.',
    /* piezas de redes */
    'Formato y foto': 'Format and photo',
    'Story 9:16': 'Story 9:16',
    'Feed 4:5': 'Feed 4:5',
    'Imagen de fondo': 'Background image',
    'Textos': 'Text',
    'Titular — lo que pongas entre *asteriscos* sale en beige':
      'Headline — anything you put between *asterisks* comes out in beige',
    'Subtítulo': 'Subhead',
    'Cifra': 'Figure',
    'Lugar (burbuja)': 'Location (bubble)',
    'Botón': 'Button',
    'Dominio': 'Domain',
    'El precio va vacío a propósito: no hay precio propio cerrado y la landing tampoco lo publica. Escríbelo solo si el dato está confirmado.':
      'The price is left empty on purpose: there is no agreed price of its own and the landing page does not publish one either. Only write it in if the figure is confirmed.',
    'Arrastra el bloque de texto o el de contacto en la pieza para colocarlos. Los velos se recalculan solos: no son un degradado fijo, se dimensionan con el texto que tienen que sostener.':
      'Drag the text block or the contact block on the creative to place them. The scrims recalculate themselves: they are not a fixed gradient, they are sized to the text they have to carry.',
    'Revisión de legibilidad': 'Legibility check',
    'Sube una imagen para medir el contraste real.': 'Upload an image to measure the real contrast.',
    'se solapan': 'overlap',
    'sin subir': 'not uploaded',
    'Descargar PNG': 'Download PNG',
    'Sale a 1080 px de ancho, el tamaño que pide Meta, con el grano de marca aplicado.':
      'It comes out 1080 px wide, the size Meta asks for, with the brand grain applied.',
    'Descargada a ': 'Downloaded at ',
    /* constructor de dossiers */
    'Páginas': 'Pages',
    'Página ▾': 'Page ▾',
    'Añadir página': 'Add page',
    '+ Añadir página': '+ Add page',
    'Página añadida: ': 'Page added: ',
    'Añade antes una página': 'Add a page first',
    'Fila ': 'Row ',
    'Cargar': 'Load',
    'Ese archivo no es un dossier válido': 'That file is not a valid brochure',
    'Exportar': 'Export',
    'Exportar PDF': 'Export PDF',
    'Exportar a PDF': 'Export to PDF',
    'Guardar como PDF': 'Save as PDF',
    'Abrir diálogo de impresión': 'Open the print dialog',
    'Se abre el diálogo de impresión del navegador. Con estos tres ajustes el PDF sale idéntico a lo que ves:':
      'The browser’s print dialog opens. With these three settings the PDF comes out identical to what you see:',
    'No se pudo exportar: ': 'Could not export: ',
    'Elemento de plantilla': 'Template element',
    '— libéralo para poder moverlo': '— release it to be able to move it',
    'Liberado ✓ ya se mueve, gira, redimensiona y borra':
      'Released ✓ it now moves, rotates, resizes and deletes',
    'Ese hueco está vacío: ponle una imagen antes de liberarla':
      'That slot is empty: put an image in it before releasing it',
    'Ese texto está vacío: escríbelo antes de liberarlo':
      'That text is empty: write it before releasing it',
    'Imagen': 'Image',
    'Fondo': 'Background',
    'Color': 'Colour',
    'Relleno': 'Fill',
    'Rellenar': 'Fill',
    'Ajustar': 'Fit',
    'Encaje': 'Fitting',
    'Opacidad': 'Opacity',
    'Giro': 'Rotation',
    'Interl.': 'Leading',
    'Track': 'Tracking',


    /* ---------- Previsión y fotos del investor deck (11-sep-2026) ----------
       Bloques nuevos de Modelos y Proyectos, escritos hoy por la otra sesión
       del estudio y ya envueltos en `lwT`: aquí solo faltaba su traducción.
       Vocabulario del deck público: forecast, ROI, ADR — se dejan como los
       llama el propio deck, que sale en inglés. */
    'Previsión del deck': 'Deck forecast',
    'Previsión del investor deck': 'Investor deck forecast',
    'Previsión guardada': 'Forecast saved',
    'sin previsión': 'no forecast',
    'publicada': 'published',
    'Publicar en el deck público': 'Publish on the public deck',
    'Publicar el forecast de este proyecto': 'Publish this project’s forecast',
    'Sin esta casilla el modelo no sale en el forecast. Nace apagada a propósito: que un campo esté relleno no puede significar «publícalo».':
      'Without this box the model does not appear in the forecast. It starts off on purpose: a filled-in field cannot mean “publish it”.',
    'Si se apaga, el deck de este proyecto se queda sin bloque de previsión entero: el neto y el ROI salen de restar estos tres.':
      'If it is off, this project’s deck loses the whole forecast block: the net and the ROI come from subtracting these three.',
    'Lo que sale en «Year-1 Rental Forecast» del deck público de cada proyecto. Un modelo sin previsión publicada no aparece ahí — no se enseña media tarjeta.':
      'What appears under “Year-1 Rental Forecast” on each project’s public deck. A model with no published forecast does not show up there — half a card is never shown.',
    'Este modelo, en este proyecto': 'This model, in this project',
    'Este modelo no está declarado en ningún proyecto, así que no puede tener previsión.':
      'This model is not declared in any project, so it cannot have a forecast.',
    'Precio medio/noche · escenario medio (€)': 'Average nightly rate · mid scenario (€)',
    'Precio medio/noche · óptimo (€)': 'Average nightly rate · best case (€)',
    'Ocupación media (%)': 'Average occupancy (%)',
    'Ocupación óptima (%)': 'Best-case occupancy (%)',
    'el precio medio/noche': 'the average nightly rate',
    'el precio óptimo': 'the best-case rate',
    'la ocupación media': 'the average occupancy',
    'la ocupación óptima': 'the best-case occupancy',
    'la inversión base': 'the base investment',
    'Inversión total, base del ROI (€)': 'Total investment, the ROI base (€)',
    'base': 'base',
    'La ocupación es un porcentaje: no puede pasar de 100.':
      'Occupancy is a percentage: it cannot go above 100.',
    'Los porcentajes van entre 0 y 100.': 'Percentages go between 0 and 100.',
    'Falta o no es válido: ': 'Missing or invalid: ',
    'Gastos del proyecto': 'Project costs',
    'Gestión (%)': 'Management (%)',
    'Mantenimiento (%)': 'Maintenance (%)',
    'Impuesto de alquiler (%)': 'Rental tax (%)',
    'Contrato de gestión que los fija': 'Management contract that sets them',
    'Ej. CG-2026-01': 'e.g. CG-2026-01',
    'Estos tres son del contrato de gestión de alquiler, no de este modelo: cambiarlos mueve la tarjeta de TODOS los modelos de':
      'These three come from the rental management contract, not from this model: changing them moves the card for EVERY model in',
    'Los tres porcentajes juntos se comen el ingreso entero: el neto saldría negativo.':
      'The three percentages together eat the whole income: the net would come out negative.',
    'Ojo: la base no cuadra con construcción + la parcela más barata del proyecto':
      'Careful: the base does not match construction + the cheapest plot in the project',
    'Construcción + la parcela más barata de este proyecto sale':
      'Construction + the cheapest plot in this project comes to',
    'O es un precio de paquete pactado, o se ha quedado vieja.':
      'Either it is an agreed package price, or it has gone stale.',
    'Si pones otra cifra tiene que ser porque es un paquete pactado; el deck afirma que el ROI se calcula sobre construcción más suelo y enseña el inventario real dos secciones más arriba.':
      'If you put a different figure it has to be because it is an agreed package; the deck states that the ROI is calculated on construction plus land, and it shows the real inventory two sections above.',
    'No hay parcelas con precio en este proyecto, así que no se puede contrastar la cifra con nada.':
      'There are no priced plots in this project, so the figure cannot be checked against anything.',
    'Marcar como «El más solicitado» en el deck': 'Mark as “Most requested” on the deck',
    /* fotos del deck */
    'Fotos del deck…': 'Deck photos…',
    'Fotos públicas del deck': 'Public deck photos',
    'salen en todos los proyectos donde se construya': 'appear in every project where it is built',
    'No se ha cargado el gestor de fotos del deck.': 'The deck photo manager has not loaded.',
    'Este proyecto no está en la tabla `proyectos`; no se le pueden colgar fotos.':
      'This project is not in the `proyectos` table; photos cannot be attached to it.',
    'Ese proyecto no está en la tabla `proyectos`.': 'That project is not in the `proyectos` table.',
    'No tienes permiso (solo administrador).': 'You do not have permission (administrators only).',
    'Añadir…': 'Add…',
    'Editar…': 'Edit…',


    'Este proyecto no tiene ficha en la tabla `proyectos`; no se le pueden colgar fotos.':
      'This project has no record in the `proyectos` table; photos cannot be attached to it.',


    /* ---------- Tipos de contrato (`vocabulario.js`) ----------
       Los nombres ingleses NO se inventan aquí: son los que el propio
       generador ya imprime en la portada de cada documento
       (`CONTRACT_TIPO[...].name.en` en `contracts/app.html`). Dos juegos de
       nombres para el mismo contrato —uno en la lista y otro en el papel— es
       exactamente el fallo que `vocabulario.js` existe para no repetir:
       «Bloqueo de Parcela» ya se llamó de dos formas distintas una vez. */
    'Carta de Reserva': 'Reservation Letter',
    'Carta de Reserva ampliada': 'Extended Reservation Letter',
    'Carta de Reserva (Hak Sewa)': 'Reservation Letter (Hak Sewa)',
    'Carta de Reserva Condicionada (PT PMA)': 'Conditional Reservation Letter (PT PMA)',
    'Carta de Reserva (Investor Deck)': 'Reservation Letter (Investor Deck)',
    'Bloqueo de Parcela': 'Plot Hold',
    'Construcción': 'Construction',
    'Contrato General': 'General Agreement',
    'Oferta Comercial': 'Commercial Offer',
    'Acuerdo Comercial': 'Commercial Agreement',
    'Protocolo Operativo': 'Operational Protocol',
    'PPJB Bonian Beach': 'PPJB Bonian Beach',
    'PPJB Bonian Beach · Parcela C2': 'PPJB Bonian Beach · Plot C2',
    'Hak Sewa - Notario': 'Hak Sewa - Notario',
    'Poder Notarial': 'Power of Attorney',
    'Construcción · CC00014 Timon': 'Construction · CC00014 Timon',
    'Adenda a contrato': 'Contract addendum',

    /* ---------- suite.js · visor.js · operaciones-cuentas.js ---------- */
    'Cerrar (Esc)': 'Close (Esc)',
    'Hito sin nombre': 'Unnamed milestone',
    'Cobro pendiente': 'Payment pending',
    'Cobro completo': 'Fully collected',
    'No se pudo calcular lo pendiente por factura: ': 'Could not calculate what is outstanding per invoice: ',
    'No se pudieron leer las firmas: ': 'Could not read the signatures: ',

    /* ---------- /intranet/cuentas/ · cuentas de cobro y su reparto (14-sep-2026) ----------
       Ojo con el vocabulario bancario, que aquí no es decorativo: «titular» es
       `account holder` y no `owner`; «precargada» se traduce por `preselected` y
       no por `default`, porque en la pantalla significa "viene ya elegida al
       abrir", no "la que se usa si nadie elige"; y ESCROW se queda igual en los
       dos idiomas — es el término del propio contrato. */
    'Cuentas de cobro': 'Payment accounts',
    'Por contrato': 'By contract',
    'Por cuenta': 'By account',
    'Buscar contrato…': 'Search contract…',
    'Buscar cuenta, banco, titular…': 'Search account, bank, holder…',
    'Elige un contrato': 'Pick a contract',
    'Elige una cuenta': 'Pick an account',
    'Datos de la cuenta': 'Account details',
    'Etiqueta (la que se ve en el desplegable)': 'Label (what shows in the dropdown)',
    'Titular': 'Account holder',
    'Banco': 'Bank',
    'Número de cuenta': 'Account number',
    'Código Swift / Routing': 'Swift / Routing code',
    'Domicilio del banco': 'Bank address',
    'Nota que se imprime en el contrato (opcional)': 'Note printed on the contract (optional)',
    'Si solo rellenas ES, se imprime ese texto en los tres idiomas. En cuanto pongas EN o ID, cada idioma imprime el suyo.':
      'If you only fill in ES, that text prints in all three languages. As soon as you add EN or ID, each language prints its own.',
    'Es una cuenta ESCROW (depósito en garantía)': 'This is an ESCROW account (funds held in escrow)',
    'Activa': 'Active',
    'Escrow': 'Escrow',
    'Desactivada': 'Disabled',
    'ESCROW añade sola al contrato la fila «Naturaleza de la cuenta — depósito en garantía». Márcala solo donde el documento lo pacte de verdad.':
      'ESCROW adds the row «Account type — funds held in escrow» to the contract on its own. Tick it only where the document actually agrees to escrow.',
    'Desactivar una cuenta la retira de todos los desplegables. Los contratos ya emitidos con ella la conservan impresa; no se borra nunca.':
      'Disabling an account removes it from every dropdown. Contracts already issued with it keep it printed; it is never deleted.',
    'Cuenta guardada': 'Account saved',
    'La etiqueta no puede quedar vacía: es lo que se lee en el desplegable del contrato.':
      'The label cannot be empty: it is what you read in the contract dropdown.',
    'En qué contratos se ofrece esta cuenta': 'Which contracts offer this account',
    'Qué cuentas puede elegir el agente en este contrato': 'Which accounts the agent can pick in this contract',
    'se ofrece en este contrato': 'offered in this contract',
    'precargada': 'preselected',
    'Precargada': 'Preselected',
    'precargada: %c': 'preselected: %c',
    'sin precargada': 'no preselection',
    'sin cuentas': 'no accounts',
    'cobra en %c': 'collects into %c',
    'el agente elige la cuenta': 'the agent picks the account',
    'plantilla %k': 'template %k',
    'clave %k': 'key %k',
    'última edición %f': 'last edited %f',
    '%n cuentas': '%n accounts',
    '%n contratos': '%n contracts',
    '%n cuentas ofrecidas': '%n accounts offered',
    '%n cuentas · precargada: %c': '%n accounts · preselected: %c',
    '%n cuentas · sin precargada': '%n accounts · no preselection',
    'ahora mismo no ofrece ninguna cuenta': 'right now it offers no account at all',
    'reparto no disponible': 'allocation unavailable',
    'Ninguna precargada — el agente la elige cada vez': 'No preselection — the agent picks it every time',
    '«Precargada» viene ya elegida al abrir un contrato nuevo. Sin precargada, el desplegable arranca vacío y el agente tiene que elegir — que es lo correcto salvo que este documento cobre siempre en el mismo sitio.':
      '«Preselected» comes already chosen when a new contract is opened. With no preselection the dropdown starts empty and the agent has to choose — which is the right thing unless this document always collects into the same place.',
    'Un contrato YA GUARDADO conserva la cuenta con la que se hizo, aunque aquí la desmarques. No se reescribe nada de lo emitido.':
      'A contract ALREADY SAVED keeps the account it was made with, even if you untick it here. Nothing already issued is rewritten.',
    'Este contrato no ofrece NINGUNA cuenta. Quien lo abra se encuentra el desplegable de destino de pago vacío — marca al menos una.':
      'This contract offers NO account at all. Whoever opens it finds the payment destination dropdown empty — tick at least one.',
    'Estás viendo el reparto, no puedes cambiarlo: solo un super admin edita cuentas de cobro. Es el dato que decide adónde transfiere el comprador.':
      'You are viewing the allocation, not changing it: only a super admin edits payment accounts. This is the data that decides where the buyer transfers to.',
    'No hay ningún tipo de contrato que cobre. Nada que repartir.': 'There is no contract type that collects payment. Nothing to allocate.',
    'No se ha podido leer el catálogo de contratos. Recarga la página.': 'The contract catalogue could not be read. Reload the page.',
    'No se ha podido leer el reparto. Recarga la página.': 'The allocation could not be read. Reload the page.',
    'No se ha podido leer el reparto por contrato. Recarga la página: lo que se ve arriba es correcto, esto no se sabe.':
      'The per-contract allocation could not be read. Reload the page: what you see above is correct, this part is unknown.',
    'No se ha podido leer tu ficha de usuario. Recarga la página.': 'Your user record could not be read. Reload the page.',
    'Ninguna cuenta con «%q».': 'No account matching «%q».',
    'Ningún contrato con «%q».': 'No contract matching «%q».',
    'No se pudo añadir: ': 'Could not add: ',
    'No se pudo quitar: ': 'Could not remove: ',
    'No se pudo marcar como precargada: ': 'Could not set as preselected: ',
    'No se pudo quitar la precarga: ': 'Could not clear the preselection: ',
    'Añadida a «%p»': 'Added to «%p»',
    'Quitada de «%p»': 'Removed from «%p»',
    'Quitada de «%p» — ese contrato se queda SIN cuenta precargada':
      'Removed from «%p» — that contract is left with NO preselected account',
    'Precargada en «%p»': 'Preselected in «%p»',
    '%c ya se puede elegir aquí': '%c can now be picked here',
    '%c ya no se ofrece aquí': '%c is no longer offered here',
    'Quitada — este contrato se queda SIN cuenta precargada':
      'Removed — this contract is left with NO preselected account',
    'Quitada — este contrato ya NO ofrece ninguna cuenta':
      'Removed — this contract now offers NO account at all',
    'Se precargará %c': '%c will be preselected',
    'Sin cuenta precargada — el agente la elegirá cada vez':
      'No preselected account — the agent will pick it every time',
    /* el aviso del generador de contratos cuando una plantilla se queda sin cuentas */
    'Esta plantilla no tiene ninguna cuenta de cobro habilitada. Un super admin las marca en Cuentas bancarias (Intranet).':
      'This template has no payment account enabled. A super admin ticks them in Bank accounts (Intranet).',
    'No se ha podido cargar qué cuentas corresponden a cada plantilla: ':
      'Could not load which accounts belong to each template: ',
    /* alta de una cuenta nueva */
    'Nueva cuenta': 'New account',
    'Nueva cuenta de cobro': 'New payment account',
    'Nace desactivada y sin ningún contrato asignado. Se comprueba el número y luego se activa.':
      'It starts disabled and with no contract assigned. Check the number first, then enable it.',
    'Clave interna (no se puede cambiar después)': 'Internal key (cannot be changed later)',
    'Crear cuenta': 'Create account',
    'Cuenta creada, desactivada. Comprueba los datos y actívala.':
      'Account created, disabled. Check the details and enable it.',
    'La clave va en minúsculas, números y guión bajo, mínimo 3 caracteres. Sin espacios ni acentos.':
      'The key must be lowercase letters, numbers and underscores, at least 3 characters. No spaces or accents.',
    'La clave va en minúsculas, sin espacios ni acentos (por ejemplo «notario_ayu_bali»). Queda dentro de cada contrato y cada factura que se emitan con esta cuenta, así que no se renombra nunca.':
      'The key is lowercase, with no spaces or accents (for example «notario_ayu_bali»). It is stored inside every contract and every invoice issued with this account, so it is never renamed.',
    'Titular, banco y número son lo que el comprador va a leer en su contrato. Cópialos del justificante del banco, no de memoria.':
      'Holder, bank and number are what the buyer will read on their contract. Copy them from the bank statement, not from memory.',
    'Hacen falta al menos el titular y el número de cuenta: son lo que el comprador usa para transferir.':
      'At least the account holder and the account number are required: they are what the buyer uses to transfer.',
    'Ya existe una cuenta con la clave «%k».': 'An account with key «%k» already exists.',
    /* el aviso de lo ya emitido con esta cuenta (hallazgo de la consulta de deploy) */
    'Esta cuenta está en %n contratos, ninguno firmado todavía.':
      'This account is used in %n contracts, none signed yet.',
    'Esta cuenta está en %n contratos, y %f ya FIRMADOS.':
      'This account is used in %n contracts, %f of them already SIGNED.',
    'Si cambias el titular, el número o la casilla ESCROW, cambia lo que imprimen esos documentos cuando alguien los reabra. Para una cuenta distinta, crea una nueva en vez de reescribir esta.':
      'If you change the holder, the number or the ESCROW tick, you change what those documents print when someone reopens them. For a different account, create a new one instead of rewriting this one.',
    /* un UPDATE que la RLS deja en cero filas no da error: hay que decirlo, o el
       panel anunciaria un guardado que no ha ocurrido */
    'NO se ha guardado: no tienes permiso para editar cuentas de cobro. Recarga la página.':
      'NOT saved: you do not have permission to edit payment accounts. Reload the page.',
    'NO se ha cambiado: no tienes permiso para editar cuentas de cobro.':
      'NOT changed: you do not have permission to edit payment accounts.',
    'sin respuesta': 'no response',
    /* la excepción por PROYECTO — «hereda» es el estado normal, no uno a medias:
       ojo al traducirlo, `inherits` (y no `default`) es lo que dice que ese
       proyecto usa el reparto general porque nadie ha pedido otra cosa */
    'Por proyecto': 'By project',
    'Buscar proyecto…': 'Search project…',
    'Elige un proyecto': 'Pick a project',
    'Ningún proyecto con «%q».': 'No project matching «%q».',
    'No se ha podido leer el catálogo de proyectos. Recarga la página.':
      'The project catalogue could not be read. Reload the page.',
    'Cualquier contrato de este proyecto': 'Any contract of this project',
    'cualquier contrato': 'any contract',
    'hereda': 'inherits',
    'usa las cuentas de cada tipo de contrato': 'uses the accounts of each contract type',
    'sin reglas propias — usa las cuentas de cada tipo de contrato':
      'no rules of its own — uses the accounts of each contract type',
    '%n reglas propias': '%n rules of its own',
    '%n reglas propias · lo que no se marque aquí, se hereda':
      '%n rules of its own · anything not ticked here is inherited',
    '%n cuentas propias': '%n accounts of its own',
    'Marcar una cuenta aquí RESTRINGE: ese tipo de contrato, en este proyecto, dejará de ofrecer las demás. Sin nada marcado hereda el reparto general, que es lo normal.':
      'Ticking an account here RESTRICTS: that contract type, in this project, will stop offering the rest. With nothing ticked it inherits the general allocation, which is the normal case.',
    'Sin reglas propias: este proyecto vuelve a heredar el reparto general':
      'No rules of its own: this project goes back to inheriting the general allocation',
    'Es una cuenta de escrow: aquí valdría para TODOS los contratos del proyecto, incluidos los que no pactan depósito en garantía.':
      'This is an escrow account: here it would apply to ALL contracts of the project, including those that do not agree to funds held in escrow.',
    '¿Una cuenta de escrow para TODOS los contratos?': 'An escrow account for ALL contracts?',
    'Marcarla igualmente': 'Tick it anyway',
    '«%c» es una cuenta de ESCROW y la estás marcando para CUALQUIER contrato de este proyecto. Sus contratos de obra y sus cartas de reserva pasarían a ofrecer solo esa cuenta, con una cláusula de depósito en garantía que no pactan.':
      '«%c» is an ESCROW account and you are ticking it for ANY contract of this project. Its construction contracts and reservation letters would then offer only that account, with an escrow clause they do not agree to.',
    'No se ha podido cargar la cuenta propia de cada proyecto: ':
      'Could not load the account each project uses: ',
    'Este proyecto no cobra en la cuenta que tenías elegida. Se ha dejado como estaba — cámbiala si corresponde.':
      'This project does not collect into the account you had picked. It has been left as it was — change it if appropriate.',
    /* ARCHIVAR un tipo de contrato (14-sep-2026). «archived» y no «disabled»: no
       se apaga nada, deja de ofrecerse al crear — lo emitido sigue funcionando */
    'Uso y archivo': 'Use and archiving',
    'archivado': 'archived',
    '(archivado)': '(archived)',
    'Archivado — no aparece al crear un contrato': 'Archived — does not show when creating a contract',
    'sin usar': 'unused',
    'sin usar todavía': 'not used yet',
    'último %f': 'last %f',
    '%n contratos · %f firmados': '%n contracts · %f signed',
    'no lleva cuenta de cobro': 'no payment account',
    'Este documento no lleva datos bancarios, así que no hay nada que repartir.':
      'This document carries no bank details, so there is nothing to allocate.',
    'Tiene contratos FIRMADOS. Archivarlo no los toca —se siguen abriendo, imprimiendo y firmando— solo deja de ofrecerse al crear uno nuevo.':
      'It has SIGNED contracts. Archiving does not touch them — they still open, print and sign — it only stops being offered when creating a new one.',
    'Archivar solo lo retira del desplegable de «Nuevo contrato». Lo ya emitido no cambia, y un contrato guardado de este tipo se abre igual (sale marcado como archivado).':
      'Archiving only removes it from the «New contract» dropdown. Nothing already issued changes, and a saved contract of this type opens just the same (it shows as archived).',
    '«%p» archivado: ya no aparece al crear un contrato':
      '«%p» archived: it no longer shows when creating a contract',
    '«%p» vuelve a estar disponible al crear un contrato':
      '«%p» is available again when creating a contract',
    'No se pudo cambiar: ': 'Could not change: ',

    /* ---------- El Asistente acoplado en toda la v4 (intranet/v4/assets/mascota.js, 25-sep-2026) ----------
       Se presenta una vez y luego se queda en la esquina. Habla en primera
       persona; «Assistant» y no un nombre propio: ponerle nombre es decisión
       de marca del owner. */
    'Abrir el Asistente': 'Open the Assistant',
    'Hola, %nombre. Soy el Asistente.': 'Hi %nombre, I\'m the Assistant.',
    'Hola. Soy el Asistente.': 'Hi, I\'m the Assistant.',
    'Desde hoy te acompaño por toda la intranet, aquí abajo en la esquina. Cuando necesites algo, tócame.':
      'From today I\'ll be with you across the whole intranet, down here in the corner. Whenever you need something, tap me.',
    'Lo que ya sé hacer': 'What I can do today',
    'Pídeme lo que la intranet no te deja hacer: cambiar un dato de un comprador, anular o borrar una factura o un recibí, borrar una operación. Dirección lo aprueba y se hace solo.':
      'Ask me for what the intranet won\'t let you do: change a buyer\'s details, void or delete an invoice or a receipt, delete an operation. Management approves it and it\'s done automatically.',
    'Y lo que viene': 'And what\'s coming',
    'Voy a ir aprendiendo a hacer más cosas por ti. Si me pides algo que aún no sé hacer, también le llega a dirección.':
      'I\'ll keep learning to do more for you. If you ask for something I can\'t do yet, it still reaches management.',
    'Paso %n de %t': 'Step %n of %t',
    'Entendido': 'Got it',
    'Pedirle algo': 'Ask for something',
    'Por ejemplo: «Anula la factura INV00160, el importe está mal».': 'For example: “Void invoice INV00160, the amount is wrong”.',
    'Seguir en el Asistente': 'Continue in the Assistant',
    '¿Qué sabes hacer?': 'What can you do?',
    'Esconder hasta mañana': 'Hide until tomorrow',
    '¿Qué necesitas?': 'What do you need?',
    'Avisar de un fallo': 'Report a problem',
    'Abrir el Asistente: ha notado un fallo': 'Open the Assistant: it noticed a problem',
    'Ir al Asistente': 'Go to the Assistant',
    'Hoy ya me has avisado de varios fallos': 'You\'ve already reported several problems today',
    'Para no llenarle el Telegram a dirección, por hoy no mando más avisos. Si es urgente, pídelo en el Asistente.': 'To avoid flooding management\'s Telegram, I won\'t send more reports today. If it\'s urgent, ask in the Assistant.',
    '¿Qué estabas haciendo? (opcional)': 'What were you doing? (optional)',
    '¿Qué ha pasado? Por ejemplo: «al guardar la factura no hace nada».': 'What happened? For example: “saving the invoice does nothing”.',
    '¿Qué ha pasado?': 'What happened?',
    'No hace falta': 'No need',
    'Avisar al estudio': 'Report to the studio',
    'Cuéntame qué ha pasado para poder avisar.': 'Tell me what happened so I can report it.',
    'Enviando…': 'Sending…',
    'Aviso enviado': 'Report sent',
    'Gracias. Le llega a dirección por Telegram como SC-%n y, si hace falta, pasa al estudio.': 'Thanks. Management gets it on Telegram as SC-%n and, if needed, passes it to the studio.',
    'Gracias. Le llega a dirección por Telegram y, si hace falta, pasa al estudio.': 'Thanks. Management gets it on Telegram and, if needed, passes it to the studio.',
    'No se pudo enviar el aviso. Prueba otra vez en un momento.': 'The report couldn\'t be sent. Try again in a moment.',
    'Algo ha fallado': 'Something went wrong',
    'Si no ha hecho lo que esperabas, avísame y se lo paso al estudio con los detalles técnicos. Le llega a dirección por Telegram.': 'If it didn\'t do what you expected, tell me and I\'ll pass it to the studio with the technical details. Management gets it on Telegram.',
    'Cuéntame qué ha pasado y se lo paso al estudio. Le llega a dirección por Telegram.': 'Tell me what happened and I\'ll pass it to the studio. Management gets it on Telegram.',
    'Dime de qué se trata —el comprador, la factura o el contrato— y por qué. Lo revisas en el Asistente antes de enviarlo.':
      'Tell me what it\'s about — the buyer, the invoice or the contract — and why. You\'ll review it in the Assistant before sending.',

    /* ---------- Asistente de respuestas (/intranet/v4/asistente/, 22-sep-2026) ----------
       Un BORRADOR de respuesta a la pregunta de un comprador citando su contrato
       (encargos/20260922_lawang_bot_apoyo_agentes.md, S5). «Draft» y no
       «reply»/«answer» en todo el bloque: Legal exige que se lea como algo que
       el agente revisa antes de reenviar, nunca como una respuesta ya dada.
       Los mensajes de error son los códigos de la Edge Function bot-agentes
       puestos en palabras; el catálogo de códigos vive en el index.ts. */
    'Asistente': 'Assistant',
    'Contratos y asistente': 'Contracts & assistant',
    'Asistente de respuestas': 'Reply assistant',
    'Un borrador de respuesta a la duda de un comprador, citando solo su contrato. Lo revisas y lo mandas tú.':
      'A draft reply to a buyer\'s question, citing only their contract. You review it and send it yourself.',
    'Redacta un BORRADOR de respuesta a la pregunta de un comprador citando solo su contrato. Tú lo revisas, lo corriges si hace falta y se lo reenvías: desde aquí no se envía nada.':
      'It drafts a DRAFT reply to a buyer\'s question citing only their contract. You review it, fix it if needed and forward it yourself: nothing is sent from here.',
    'Cita solo el ejemplar del contrato elegido. Lo que no esté en él lo marca como pendiente, y una contraoferta comercial la deja para el promotor: no rellenes ninguno de los dos huecos con algo plausible.':
      'It cites only the chosen contract. Anything not in it is flagged as pending, and a commercial counter-offer is left to the developer: do not fill either gap with something plausible.',
    'Consulta': 'Query',
    'Qué contrato y qué pregunta': 'Which contract and which question',
    'Elige el contrato del comprador': 'Pick the buyer\'s contract',
    'Contrato del comprador': 'Buyer\'s contract',
    'Cargando tus contratos…': 'Loading your contracts…',
    'No tienes ningún contrato a la vista: sin contrato no hay nada que citar.':
      'You have no contract in sight: without a contract there is nothing to cite.',
    'No se han podido cargar los contratos: ': 'Could not load the contracts: ',
    'El selector de contratos no ha cargado — recarga la página.': 'The contract picker did not load — reload the page.',
    '1 contrato a tu alcance': '1 contract within your reach',
    '%n contratos a tu alcance': '%n contracts within your reach',
    'firmado': 'signed',
    'Pregunta del comprador (pégala tal cual)': 'Buyer\'s question (paste it as is)',
    'Pega aquí el mensaje del comprador, sin resumirlo ni corregirlo.': 'Paste the buyer\'s message here, without summarising or correcting it.',
    '%n / %m': '%n / %m',
    'Redactar borrador': 'Write draft',
    'Redactando…': 'Drafting…',
    'Elige primero el contrato del comprador.': 'Pick the buyer\'s contract first.',
    'Pega la pregunta del comprador antes de redactar.': 'Paste the buyer\'s question before drafting.',
    'Resultado': 'Result',
    'Borrador para revisar': 'Draft to review',
    'Punto pendiente: ': 'Pending point: ',
    'La plantilla ha cambiado desde la firma: contrasta con el PDF firmado':
      'The template has changed since signing: check against the signed PDF',
    'Comprobado por la fecha de la plantilla, no por su texto: el texto articulado no está en la base.':
      'Checked by the template\'s date, not its wording: the articled text is not in the database.',
    'Borrador generado por IA — revísalo antes de enviarlo': 'AI-generated draft — review it before sending',
    'Fuentes consultadas (%n)': 'Sources consulted (%n)',
    'El servidor no ha citado ninguna fuente.': 'The server cited no sources.',
    'El borrador aparecerá aquí: elige el contrato, pega la pregunta y pulsa «Redactar borrador».':
      'The draft will appear here: pick the contract, paste the question and press "Write draft".',
    'Cuenta de cobro': 'Payment account',
    'Documento del contrato': 'Contract document',
    'Documento del proyecto': 'Project document',
    'Documento del modelo': 'Model document',
    'Plantilla': 'Template',
    'Reglas del asistente': 'Assistant rules',
    'Copiar borrador': 'Copy draft',
    'Borrador copiado.': 'Draft copied.',
    'Comprobado por la fecha de publicación de la plantilla, no por su texto.': 'Checked by the template\'s publication date, not by its text.',
    // Historial del asistente (22-sep-2026)
    'Historial': 'History',
    'Consultas anteriores': 'Previous queries',
    'Las consultas se guardan 90 días: cada agente ve las de los contratos a su alcance.': 'Queries are kept for 90 days: each agent sees those of the contracts within their reach.',
    'Buscar por contrato, comprador o texto': 'Search by contract, buyer or text',
    'Actualizar': 'Refresh',
    'Cargando el historial…': 'Loading history…',
    'No se ha podido cargar el historial: ': 'Could not load the history: ',
    'Ninguna consulta coincide con el filtro.': 'No query matches the filter.',
    'Todavía no hay consultas guardadas. Se conservan 90 días.': 'No queries saved yet. They are kept for 90 days.',
    '%n consultas (se conservan 90 días)': '%n queries (kept for 90 days)',
    'Borrador': 'Draft',
    'Descartado': 'Discarded',
    '%n pendientes': '%n pending',
    'tú': 'you',
    'Ver': 'View',
    'Reutilizar pregunta': 'Reuse question',
    'Consulta del %f · %c': 'Query from %f · %c',
    'Esta consulta se descartó: no hay borrador, solo los puntos pendientes.': 'This query was discarded: no draft, only the pending points.',
    'Pregunta cargada en el formulario: revísala y vuelve a redactar.': 'Question loaded into the form: review it and draft again.',
    'No hay borrador que copiar.': 'There is no draft to copy.',
    'No se pudo copiar: selecciona el texto y cópialo a mano.': 'Could not copy: select the text and copy it by hand.',
    'Sin sesión: recarga la página o vuelve a entrar.': 'No session: reload the page or sign in again.',
    'No hay conexión con el asistente: comprueba la red y vuelve a intentarlo.':
      'No connection to the assistant: check the network and try again.',
    'No se pudo redactar el borrador (%e).': 'Could not write the draft (%e).',
    /* códigos de error de la edge */
    'Tu sesión ha caducado: vuelve a entrar.': 'Your session has expired: sign in again.',
    'El contrato elegido no es válido: vuelve a elegirlo.': 'The chosen contract is not valid: pick it again.',
    'La pregunta supera los 4.000 caracteres: recórtala.': 'The question exceeds 4,000 characters: trim it.',
    'Ese contrato no está a tu alcance: no se ha redactado nada.': 'That contract is not within your reach: nothing was drafted.',
    'El asistente no está configurado todavía: avisa a administración.': 'The assistant is not set up yet: tell administration.',
    'El modelo no responde ahora mismo: vuelve a intentarlo en un minuto.': 'The model is not responding right now: try again in a minute.',
    'No se ha podido leer el expediente del contrato: no se ha redactado nada.': 'Could not read the contract file: nothing was drafted.',
    'No se pudo registrar la consulta, y sin registro no hay borrador.': 'Could not log the query, and without a log there is no draft.',
    'No se pudo comprobar tu límite de consultas: vuelve a intentarlo.': 'Could not check your query limit: try again.',
    'Un freno del asistente está mal escrito: avisa a administración.': 'One of the assistant\'s brakes is misspelt: tell administration.',
    'Has alcanzado el límite de consultas por hora': 'You have reached the hourly query limit',
    'Has alcanzado el límite de consultas de hoy': 'You have reached today\'s query limit',
    /* borrador descartado por el post-chequeo del servidor o por el modelo */
    'Borrador descartado: %m': 'Draft discarded: %m',
    'Borrador descartado: contenía una cifra que no está en el contrato.': 'Draft discarded: it contained a figure that is not in the contract.',
    'Borrador descartado: tocaba un punto que solo decide el promotor.': 'Draft discarded: it touched a point only the developer decides.',
    'Borrador descartado: un freno del asistente está mal escrito.': 'Draft discarded: one of the assistant\'s brakes is misspelt.',
    'Borrador descartado: el modelo no quiso responder a esa pregunta.': 'Draft discarded: the model declined to answer that question.',
    'Borrador descartado: la respuesta salió cortada. Prueba con una pregunta más corta.': 'Draft discarded: the reply came out cut off. Try a shorter question.',
    'Borrador descartado: el modelo no devolvió texto.': 'Draft discarded: the model returned no text.',
    /* FAQ aprobadas, respuestas copiadas y temas frecuentes (22-sep-2026, noche 4).
       «Approved reply» para la FAQ: es lo único de esta pantalla que SÍ es una
       respuesta dada (la aprueba un super administrador); el borrador sigue
       siendo «draft». */
    'Respuestas aprobadas para este contrato': 'Approved replies for this contract',
    'Buscando respuestas aprobadas…': 'Looking for approved replies…',
    'Ninguna respuesta aprobada para este proyecto': 'No approved reply for this project',
    '%n respuestas aprobadas': '%n approved replies',
    '%n respuestas aprobadas que el asistente ha tenido en cuenta': '%n approved replies the assistant took into account',
    '(respuesta no cargada: vuelve a elegir el contrato)': '(reply not loaded: pick the contract again)',
    'No se han podido leer las respuestas aprobadas': 'Could not read the approved replies',
    'Borrador para el comprador (editable)': 'Draft for the buyer (editable)',
    'Solo los puntos que el asistente ha podido contestar. Corrígelo aquí si hace falta: «Copiar» se lleva lo que quede escrito.':
      'Only the points the assistant could answer. Fix it here if needed: "Copy" takes whatever is written.',
    'Todos los puntos han quedado pendientes: no hay texto que mandar al comprador todavía.':
      'Every point is pending: there is no text for the buyer yet.',
    'No se ha guardado la copia': 'The copy was not saved',
    'Copiada': 'Copied',
    'Texto copiado el %f': 'Text copied on %f',
    'Fijar como respuesta aprobada': 'Set as approved reply',
    'Fijar respuesta aprobada': 'Set approved reply',
    'Ver consultas': 'View queries',
    'Tema: %t': 'Topic: %t',
    'Quitar el filtro de tema': 'Remove the topic filter',
    '%n consultas del tema «%t» (de las %m guardadas)': '%n queries on the topic "%t" (out of %m saved)',
    'No se ha podido aplicar el filtro de ese tema.': 'Could not apply that topic filter.',
    // Temas frecuentes
    'Temas': 'Topics',
    'Temas frecuentes': 'Frequent topics',
    'Qué preguntan los compradores, por tema, y en cuántas consultas el asistente tuvo que retirar un punto o descartar el borrador.':
      'What buyers ask, by topic, and in how many queries the assistant had to withdraw a point or discard the draft.',
    'Ventana de días': 'Day window',
    '30 días': '30 days',
    '90 días': '90 days',
    'Cargando los temas…': 'Loading topics…',
    'No hay temas definidos todavía.': 'No topics defined yet.',
    'No se ha podido cargar el resumen por temas': 'Could not load the summary by topic',
    '%n consultas en los últimos %d días, por tema': '%n queries in the last %d days, by topic',
    'Tema': 'Topic',
    'Consultas': 'Queries',
    'Con puntos retirados': 'With withdrawn points',
    'Descartadas': 'Discarded',
    'hueco del contrato → adenda, no FAQ': 'gap in the contract → addendum, not FAQ',
    // Administración de respuestas aprobadas (solo super_admin)
    'Respuestas aprobadas': 'Approved replies',
    'Lo que el asistente puede dar por bueno además del contrato: una pregunta y su respuesta, acotadas a un proyecto o a un tipo de contrato. Las lee cualquier agente; solo un super administrador las aprueba o las retira.':
      'What the assistant may take as given besides the contract: a question and its reply, scoped to a project or a contract type. Any agent reads them; only a super administrator approves or withdraws them.',
    'Un tema frenado por el asistente no admite respuesta aprobada: es un hueco del contrato y se resuelve con una adenda. Y ninguna respuesta lleva una cifra de 8 o más dígitos seguidos (cuenta, teléfono, pasaporte).':
      'A topic the assistant brakes on takes no approved reply: it is a gap in the contract and is solved with an addendum. And no reply carries a figure of 8 or more consecutive digits (account, phone, passport).',
    'Elige el tema': 'Pick the topic',
    'Proyecto (opcional)': 'Project (optional)',
    'Cualquier proyecto': 'Any project',
    'Tipo de contrato (opcional)': 'Contract type (optional)',
    'Cualquier tipo': 'Any type',
    'Pregunta (como la haría el comprador)': 'Question (as the buyer would ask it)',
    '¿Qué documentos recibo al firmar?': 'Which documents do I get on signing?',
    'Respuesta aprobada': 'Approved reply',
    'Lo que el asistente puede dar por bueno. Sin cifras largas ni datos de un comprador concreto.':
      'What the assistant may take as given. No long figures and no data of a specific buyer.',
    'Limpiar': 'Clear',
    'Guardar respuesta aprobada': 'Save approved reply',
    'Respuestas vigentes': 'Current replies',
    'Cargando las respuestas aprobadas…': 'Loading approved replies…',
    'No se han podido cargar las respuestas aprobadas': 'Could not load the approved replies',
    'Todavía no hay ninguna respuesta aprobada.': 'There is no approved reply yet.',
    '%n respuestas vigentes': '%n current replies',
    'cualquier proyecto': 'any project',
    'cualquier tipo': 'any type',
    'proyecto sin acceso': 'project not accessible',
    'procedimiento: vale para todos los contratos': 'procedure: applies to every contract',
    'Sustituir': 'Replace',
    'Retirar': 'Withdraw',
    'Retirar la respuesta aprobada «%p»': 'Withdraw the approved reply «%p»',
    'Sustituye a «%p»: al guardar, la anterior queda retirada.': 'Replaces «%p»: on saving, the previous one is withdrawn.',
    'Elige el tema de la respuesta aprobada.': 'Pick the topic of the approved reply.',
    'Ese tema está frenado por el asistente: es un hueco del contrato y se resuelve con adenda, no con una respuesta aprobada.':
      'That topic is braked by the assistant: it is a gap in the contract and is solved with an addendum, not with an approved reply.',
    'Escribe la pregunta tal y como la haría el comprador.': 'Write the question as the buyer would ask it.',
    'Escribe la respuesta aprobada.': 'Write the approved reply.',
    'Ese proyecto no está en la lista: elígelo del desplegable.': 'That project is not on the list: pick it from the dropdown.',
    'Ese tipo de contrato no está en la lista: elígelo del desplegable.': 'That contract type is not on the list: pick it from the dropdown.',
    'Una respuesta aprobada necesita proyecto o tipo de contrato (solo los temas de procedimiento valen para todos).':
      'An approved reply needs a project or a contract type (only procedure topics apply to all).',
    'Respuesta aprobada guardada: el asistente la tiene en cuenta desde ahora.': 'Approved reply saved: the assistant takes it into account from now on.',
    'Respuesta guardada, pero la anterior sigue activa: retírala a mano.': 'Reply saved, but the previous one is still active: withdraw it by hand.',
    'Respuesta aprobada retirada: el asistente deja de tenerla en cuenta.': 'Approved reply withdrawn: the assistant no longer takes it into account.',
    'No se han podido cargar los temas': 'Could not load the topics',
    'No se han podido cargar los proyectos': 'Could not load the projects',
    /* códigos de error de la edge para faq_guardar / faq_retirar */
    'La respuesta contiene una cifra de 8 o más dígitos seguidos (cuenta, teléfono, pasaporte): no se guarda.':
      'The reply contains a figure of 8 or more consecutive digits (account, phone, passport): it is not saved.',
    'Respuesta frenada por el asistente: %m': 'Reply braked by the assistant: %m',
    'Falta un dato de la respuesta aprobada (%c).': 'A field of the approved reply is missing (%c).',
    'Has alcanzado el límite de respuestas aprobadas por hora: vuelve a intentarlo más tarde.': 'You have reached the hourly limit of approved replies: try again later.',
    'Solo un super administrador puede aprobar o retirar respuestas.': 'Only a super administrator can approve or withdraw replies.',
    'Esa respuesta aprobada ya no existe o ya estaba retirada.': 'That approved reply no longer exists or was already withdrawn.',
    'No se pudo guardar la respuesta aprobada.': 'Could not save the approved reply.',
    'No se pudo retirar la respuesta aprobada.': 'Could not withdraw the approved reply.',
    'No se pudo guardar la respuesta aprobada (%e).': 'Could not save the approved reply (%e).',

  };

  window.LW_EN = EN;

  /* `es-ES` estaba escrito a mano en cada `toLocaleDateString` de la suite, y
     con la interfaz en inglés eso imprime «11 sept 2026» debajo de una
     cabecera que dice «Date». Una sola forma de pedir el locale. Se queda en
     `en-GB` y no `en-US`: el equipo y los compradores son europeos y
     asiáticos, y 03/09 tiene que seguir siendo 3 de septiembre. */
  window.lwLocale = function () {
    return window.LW_IDIOMA === 'en' ? 'en-GB' : 'es-ES';
  };

  /* ==========================================================================
     lwT(texto, huecos) — la única forma de traducir.

     En español devuelve su entrada: la vista española es IDÉNTICA a la de
     antes de envolver el texto, y no por haberlo comprobado sino porque no
     hay otro camino posible por el código.
     ========================================================================== */
  window.lwT = function (s, huecos) {
    if (s == null) return s;
    var base = String(s);
    var corte = base.indexOf('~');          // 'Documentación~grupo' → se imprime 'Documentación'
    var visible = corte === -1 ? base : base.slice(0, corte);

    if (window.LW_IDIOMA === 'en') {
      var v = Object.prototype.hasOwnProperty.call(EN, base) ? EN[base] : null;

      /* Segunda oportunidad: la MISMA frase con blanco de sobra a los lados.
         `'No se pudo guardar: '` lleva su espacio final porque detrás se le
         concatena el mensaje de error, y esa frase es la misma que
         `'No se pudo guardar:'`. Sin esto haría falta una entrada por cada
         variante de espaciado — dos entradas para una frase, que es la clase
         de duplicado que este diccionario existe para evitar. El blanco se
         devuelve tal cual estaba, así que la concatenación sigue igual. */
      if (v == null) {
        var trozos = base.match(/^(\s*)([\s\S]*?)(\s*)$/);
        var nucleo = trozos && trozos[2];
        if (nucleo && nucleo !== base &&
            Object.prototype.hasOwnProperty.call(EN, nucleo)) {
          v = trozos[1] + EN[nucleo] + trozos[3];
        }
      }

      if (v == null) {
        if (window.LW_T_MISSES) window.LW_T_MISSES.add(base);
      } else {
        visible = v;
      }
    }

    if (huecos) {
      for (var k in huecos) {
        if (Object.prototype.hasOwnProperty.call(huecos, k)) {
          visible = visible.split('%' + k).join(huecos[k]);
        }
      }
    }
    return visible;
  };

  /* ==========================================================================
     lwIdiomaAplicar(raiz) — traduce la HTML que ya está escrita en la página.

     El marcado estático (botones de la barra, cabeceras de tabla, buscador)
     ya está en el DOM cuando arranca el script de la herramienta. En vez de
     generarlo por JS se marca en el HTML y se reescribe aquí una vez:

       <th data-lwt>Comprador</th>                  ← la clave es su texto
       <th data-lwt="Estado~unidad">Estado</th>     ← clave explícita
       <input data-lwt-ph placeholder="Buscar…">    ← el placeholder
       <button data-lwt-title title="Borrar">       ← el title
       <span data-lwt-aria aria-label="Cerrar">     ← el aria-label

     **`data-lwt` y no `data-t`**, que sería lo natural: `data-t` YA estaba
     cogido en este repo para dos cosas distintas, y las dos habrían roto.
     `intranet/vencimientos/` guarda en `data-t` las CIFRAS de cada barra del
     gráfico (`mes.dataset.t.split('·')`): traducirlo le habría borrado los
     `<span>` de los segmentos, o sea el gráfico entero, y solo en inglés.
     `intranet/facturas/v3/` lo usa para la clave del chip de tipo. Y el
     piloto de `Documentacion/` lo usa para SU diccionario, con claves
     inventadas: si algún día carga también este fichero, los dos applier se
     pisarían. Un atributo con dos significados es la misma familia de fallo
     que una lista escrita a mano en dos sitios.

     En ESPAÑOL sale sin tocar el DOM: no se normaliza ni un espacio en
     blanco. En inglés escribe la clave derivada en el atributo antes de
     sustituir, así que volver a llamarla sobre el mismo nodo es inofensivo
     (una herramienta que repinte su cabecera no se queda en inglés a medias).

     No traduce HTML, solo texto: el marcado dentro de una frase no se mete
     en el diccionario. Si una frase lleva negrita, se parte en nodos o se
     compone con %huecos.
     ========================================================================== */
  window.lwIdiomaAplicar = function (raiz) {
    if (window.LW_IDIOMA !== 'en') return;
    var r = raiz || document;

    r.querySelectorAll('[data-lwt]').forEach(function (el) {
      var k = el.dataset.lwt || el.textContent.trim();
      if (!k) return;
      el.dataset.lwt = k;
      el.textContent = window.lwT(k);
    });
    r.querySelectorAll('[data-lwt-ph]').forEach(function (el) {
      var k = el.dataset.lwtPh || el.getAttribute('placeholder') || '';
      if (!k) return;
      el.dataset.lwtPh = k;
      el.setAttribute('placeholder', window.lwT(k));
    });
    r.querySelectorAll('[data-lwt-title]').forEach(function (el) {
      var k = el.dataset.lwtTitle || el.getAttribute('title') || '';
      if (!k) return;
      el.dataset.lwtTitle = k;
      el.setAttribute('title', window.lwT(k));
    });
    r.querySelectorAll('[data-lwt-aria]').forEach(function (el) {
      var k = el.dataset.lwtAria || el.getAttribute('aria-label') || '';
      if (!k) return;
      el.dataset.lwtAria = k;
      el.setAttribute('aria-label', window.lwT(k));
    });

    /* El título de la pestaña. Todas las páginas de la suite se llaman
       «Lawang · ⟨herramienta⟩», así que basta traducir el último tramo — y
       el nombre de cada herramienta ya está en el diccionario porque lo
       necesita el menú. Sin esto, con ocho pestañas abiertas en inglés
       todas siguen rotuladas en español, que es justo donde se distinguen. */
    if (document.title.indexOf(' · ') !== -1) {
      var tramos = document.title.split(' · ');
      var ultimo = tramos.pop();
      document.title = tramos.concat(window.lwT(ultimo)).join(' · ');
    }

    /* El idioma del documento, para el lector de pantalla y el corrector del
       navegador. Una página que dice `lang="es"` y enseña inglés se lee con
       la voz equivocada. */
    if (document.documentElement) document.documentElement.lang = 'en';
  };
})();
