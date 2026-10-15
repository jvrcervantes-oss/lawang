/* ═══════════════════════════════════════════════════════════════════════════
   OPERACIONES · CUENTAS Y ETAPAS — 26-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   LA REGLA DE NEGOCIO DEL DINERO DE UNA VENTA. Vivía dentro de
   `operaciones/index.html`; se saca aquí porque `/intranet/operaciones/v3/` necesita
   EXACTAMENTE el mismo cálculo, y copiarlo habría creado dos aritméticas del
   dinero que se separan solas. Es la familia de fallo más cara del repo («el
   dato tiene un dueño»).

   Traslado literal: no se ha cambiado una línea de la lógica, y los
   comentarios son los originales — explican los casos que costaron descubrir:
   la Carta de Reserva que no suma precio (328.000 € por una villa de 164.000),
   el POA que no es una venta, el firmado sin precio que NO se da por cobrado.

   SE QUEDA EN LA PÁGINA lo que no es cálculo: `cargarHitos()` consulta a la
   base y necesita su cliente, y `FILTROS` es del listado de esa pantalla.

   Depende de `facturas/totales.js` (parseImporte, redondear) y de
   `assets/vocabulario.js` (lwEsPreliminar), que ya cargan las dos páginas.
   ═══════════════════════════════════════════════════════════════════════════ */

/* ---------- dinero ----------
   parseImporte / fmtMoneda / redondear salen de /intranet/facturas/totales.js: la misma
   aritmética que emite las facturas, para que un total no cuadre distinto según
   dónde se mire. */
function importeHito(h, precio, moneda){
  const m = parseImporte(h.monto);
  if(m) return { n:m, exacto:true };
  const p = parseImporte(h.pct);
  if(p && precio) return { n:redondear(precio * p / 100, moneda), exacto:false };
  return { n:null, exacto:false };
}
/* Puente al diccionario compartido (`i18n.js`, 11-sep-2026), defensivo —
   ver topbar.js. */
function ocT(s) { return (typeof window !== 'undefined' && window.lwT) ? window.lwT(s) : s; }

const textoHito = h => h.es || h.en || h.id || ocT('Hito sin nombre');

/* Compradores nombrados en el contrato vs fichas realmente creadas. El alta es
   automática al guardar, pero se cae sin ruido si la persona no tiene pasaporte
   ni email, si el contrato se guardó antes de que existiera la sincronización,
   o (hasta el 29-jul) si era el cuarto adquiriente en adelante. */
/* Cuántas personas nombra el contrato. Sale del espejo `comprador_nombre`, que
   el trigger `espeja_comprador` mantiene con los nombres unidos por ' · ' — no
   de `datos`, por lo dicho arriba. Verificado contra los 112 contratos reales:
   el conteo coincide con el del documento en todos. */
function compradoresNombrados(o){
  const s = String(o.comprador_nombre || '').trim();
  if(!s) return 0;
  return s.split(' · ').filter(x => x.trim()).length;
}

/* Cómo se resume la lista de compradores en una fila estrecha. Con cuatro
   nombres, la celda los recortaba con puntos suspensivos y se leían dos: el
   owner lo reportó como «me sale como mucho 2 adquirientes». No es un tope de
   datos —el contrato admite hasta nueve y la ficha los enseña todos—, era la
   celda. Ahora se ve el primero y CUÁNTOS más hay, y el título trae la lista
   entera para el ratón. */
function resumenCompradores(o){
  const s = String(o.comprador_nombre || '').trim();
  if(!s) return { texto:ocT('Sin cliente'), extra:'', titulo:'' };
  const partes = s.split(' · ').filter(x => x.trim());
  return {
    texto: partes[0],
    extra: partes.length > 1 ? '+' + (partes.length - 1) : '',
    titulo: partes.length > 1 ? partes.length + ' compradores: ' + partes.join(' · ') : partes[0],
  };
}
const fichasQueFaltan = o => Math.max(0, compradoresNombrados(o) - (o.compradores || []).length);

/* "facturado" (11-ago, reforma del modelo de facturación): ya NO es sumar
   las facturas del contrato — eso es lo que se DEBE, no lo que se ha
   cobrado. Viene de contrato_cobrado() en Supabase (solo recibís, ver
   facturas/sql/contrato_cobrado.sql), precargado en op.cobrado por cargar().
   El nombre del campo se mantiene ("facturado") para no tocar cada sitio
   que ya lo lee — lo que cambió es CÓMO se calcula, no cómo se usa. */
function cuenta(op){
  const moneda = op.moneda || 'EUR';
  const precio = parseImporte(op.precio_total);
  const hitos  = Array.isArray(op.hitos) ? op.hitos : [];
  const facturado = redondear(op.cobrado || 0, moneda);
  return { moneda, precio, hitos, facturado, pendiente: precio ? redondear(precio - facturado, moneda) : null };
}

/* Estado de cuenta COMBINADO (11-ago, petición del owner): un mismo comprador
   con dos contratos vinculados (contrato_padre_id — típico parcela ↔
   construcción) hasta ahora obligaba a abrir cada uno y sumar a mano. El
   grupo es el mismo que ya arma "Documentos de la operación" (padre + sus
   hijos, o el propio si no tiene ninguno) — mismo criterio de vinculación,
   una sola vez. Sin hijos ni padre, `grupo` es solo `[op]` y el resultado es
   idéntico al de cuenta(op): esta función generaliza esa, no la sustituye. */
function cuentaGrupo(op){
  const grupo = op.padre ? [op.padre, ...op.padre.hijos] : [op, ...op.hijos];
  const moneda = op.moneda || 'EUR';
  /* La Carta de Reserva NO suma precio: declara el mismo importe de la villa que
     luego repite el contrato real que la sustituye (`lwEsPreliminar`, en
     assets/suite-comun.js, con el porqué). Compradores ya lo hacía desde el
     12-ago; aquí no hacía falta porque la Carta era una operación aparte. Desde
     que cuelga de su Bloqueo (LAW-50, 14-ago) sí entra en el grupo, y sin esta
     línea el precio salía DOBLE — Juan José Carbajo Pinal, 328.000 € por una
     villa de 164.000.
     Si el grupo es SOLO preliminar (una Carta que todavía no tiene su Bloqueo),
     se cuenta igualmente: si no, la operación diría 0 € y leería como que no se
     ha pactado nada, cuando la cuota de reserva sí es exigible. */
  /* Un HIJO que acompaña a la venta (PIEZAS_ACOMPANAN: Poder, Hak Sewa, Adenda) tampoco suma, tenga o no precio:
     la Adenda no lleva precio porque se contaría dos veces, y el del Hak Sewa va en hsn_precio_rp. Gemela de la
     regla del servidor (_cadena_saldo, migración 20261013062339, 13-oct-2026); una raíz que es ella misma la pieza
     (Hak Sewa suelto) sí cuenta, como allí. Y como allí, un hijo en otra moneda que la raíz (o sin moneda bajo una
     raíz con ella) no suma: precio y facturado van en la misma moneda (`is distinct from`, nulos incluidos). */
  const raiz = grupo[0];
  const otraMoneda = o => o !== raiz && (o.moneda || null) !== (raiz.moneda || null);
  /* Solo la obra VIGENTE suma (15-oct-2026). Gemela de public._venta_obras_vigentes, la regla del servidor que pone el
     precio de la venta y el tope de facturar (migración 20261015171500): un contrato de obra (construccion,
     cc00014_timon, adenda…; los tipos con es_obra del catálogo contrato_tipo_etapa) solo cuenta si es el vigente de su
     parcela: los FIRMADOS si hay alguno; si no, el borrador más reciente. Liberados, sin precio y de otra moneda, fuera.
     Sin esto, un borrador sustituido sumaba dos veces la obra: RP00101 (CC00062 borrador + CC00102 firmada) decía
     113.000 de precio cuando son 69.000. Las obras sin unidad forman su propio grupo. Diferencia con el servidor: allí se
     agrupa por las parcelas DE ESTA VENTA (una obra que apunta a la parcela de otra va al grupo sin parcela); aquí no hay
     inventario y se agrupa por unidad_id tal cual (el 15-oct no hay ninguna así). Si la pieza no trae unidad_id (una
     consulta que no lo pide), no se puede agrupar y la obra cuenta como antes: mejor de más que una parcela de menos. */
  const esObra = o => o.tipo === 'construccion' || o.tipo === 'cc00014_timon' || /^adenda/.test(o.tipo || '');
  const vigentes = new Set();
  const porParcela = {};
  grupo.forEach(o => {
    if(!esObra(o) || o.liberado_en || !((parseImporte(o.precio_total) || 0) > 0) || (o.moneda || null) !== (raiz.moneda || null)) return;
    if(!('unidad_id' in o)){ vigentes.add(o); return; }
    const k = o.unidad_id || '-';
    (porParcela[k] = porParcela[k] || []).push(o);
  });
  Object.keys(porParcela).forEach(k => {
    const firmadas = porParcela[k].filter(o => o.bloqueado);
    if(firmadas.length){ firmadas.forEach(o => vigentes.add(o)); return; }
    vigentes.add(porParcela[k].slice().sort((x, y) =>
      String(y.created_at || '').localeCompare(String(x.created_at || '')) || String(y.id || '').localeCompare(String(x.id || '')))[0]);
  });
  const obraNoVigente = o => esObra(o) && !vigentes.has(o);
  const sumables = grupo.filter(o => !lwEsPreliminar(o.tipo) && !(o !== raiz && PIEZAS_ACOMPANAN.indexOf(o.tipo) !== -1) && !otraMoneda(o) && !obraNoVigente(o));
  const base = sumables.length ? sumables : grupo;
  const precio = base.reduce((a, o) => a + (parseImporte(o.precio_total) || 0), 0) || null;
  // el cobrado sí cuenta TODO el grupo: un recibí contra la Carta es dinero real
  // que entró, y al pasar a Bloqueo hay que descontárselo al cliente.
  const facturado = redondear(grupo.reduce((a, o) => a + (o.cobrado || 0), 0), moneda);
  return { moneda, precio, facturado, pendiente: precio ? redondear(precio - facturado, moneda) : null,
           grupo, soloPreliminar: !sumables.length };
}

/* ---------- ETAPAS del embudo (Kanban) ----------
   🔴 Los FILTROS de arriba NO sirven como columnas, y esto es el fondo del
   asunto: son predicados que se SOLAPAN. Una misma operación está a la vez «sin
   firmar», «con pendiente» y «falta ficha». Una columna de tablero exige que cada
   tarjeta esté en UNA sola, o el total de las columnas no cuadra con el total de
   operaciones y el tablero deja de ser de fiar.
   Así que la etapa es una ESCALERA y se resuelve por orden, no una lista de
   pruebas independientes:
     1. Sin firmar      — no firmado y sin enlace de firma vivo
     2. Firma enviada   — no firmado y CON enlace esperando (el balón está en el
                          comprador; es distinto de no haber empezado)
     3. Cobro pendiente — firmado y queda dinero por facturar
     4. Cobro completo  — firmado y no queda nada
   El orden importa: un contrato firmado no puede estar en «firma enviada» aunque
   le quede un enlace pendiente sin barrer.
   ⚠️ Firmado SIN precio fijado cae en «Cobro pendiente», no en «completo». No se
   sabe cuánto falta, y afirmar que está cobrado cuando no se sabe es el único
   error de los dos que cuesta dinero. La tarjeta lo dice: «sin fijar». */
const ETAPAS = [
  ['sin_firmar', ocT('Sin firmar'),      'espera'],
  ['firma_viva', ocT('Firma enviada'),   'info'],
  ['cobro_pend', ocT('Cobro pendiente'), 'alerta'],
  ['cobro_ok',   ocT('Cobro completo'),  'ok'],
];
/* Color de cada etapa en la cabecera de columna, la barra de progreso y la
   leyenda (mockup 4a) — DISTINTO del `.tag` de dentro de la tarjeta a
   propósito: "Cobro pendiente" es el estado normal de mitad de proceso, no
   una alarma, así que aquí va gris y no el rojo de `.tag.alerta` (ese rojo
   se queda para avisos de verdad, como "Falta ficha"). Cambiar esto NO toca
   los `.tag` compartidos con el resto de la suite. */
const ETAPA_COLOR = { sin_firmar:'#8C5E10', firma_viva:'#104C4F', cobro_pend:'#5A6062', cobro_ok:'#3F5230' };
function etapa(o){
  if(!o.bloqueado) return o.firmas.some(f => f.estado === 'pendiente') ? 'firma_viva' : 'sin_firmar';
  const c = cuenta(o);
  // POA no es una venta y nunca va a tener precio — sin este corte se queda para
  // siempre en "Cobro pendiente" como si le debieran dinero al estudio (hallazgo
  // de Administración, 10-ago). Blindado contra precio (mismo hallazgo, revisión
  // del propio fix): si algún día un 'poa' SÍ tuviera precio_total — reutilización
  // de tipo por error, o un POA que además cobrara algo — cae al flujo normal en
  // vez de darlo por cobrado sin comprobarlo.
  if(PIEZAS_ACOMPANAN.indexOf(o.tipo) !== -1 && !c.precio) return 'cobro_ok';   // y el Hak Sewa y la Adenda (13-oct-2026): ver PIEZAS_ACOMPANAN
  if(c.precio == null || !c.precio) return 'cobro_pend';   // firmado sin precio: no se afirma que esté cobrado
  return (c.pendiente != null && c.pendiente > 0) ? 'cobro_pend' : 'cobro_ok';
}

/* ---------- la OPERACIÓN entera (22-sep-2026, v4/operaciones) ----------
   `etapa(o)` mira UNA pieza. Una operación es la cadena (Carta → Bloqueo →
   Construcción), y su situación es la de la pieza donde está el trabajo hoy:
   la última creada que no esté liberada. El dinero, en cambio, es de TODA la
   cadena (`cuentaGrupo`): un Bloqueo recién firmado con la señal de la Carta
   ya cobrada no «debe» el precio entero. Vive aquí, junto a `etapa()`, para
   que la clásica pueda usarla el día que enseñe la cadena en su tablero — no
   como una segunda copia en datos.js. */
function cadenaOperacion(o){
  const raiz = o.padre || o;
  return [raiz, ...(raiz.hijos || [])].slice().sort((a, b) => String(a.created_at || '').localeCompare(String(b.created_at || '')));
}
/* Documentos que ACOMPAÑAN a la venta sin ser una pieza de su dinero (13-oct-2026, revisor de código): el Hak
   Sewa se firma ante notario meses después de la obra, y el Poder o la Adenda cuando toque. Si contaran como «la
   última pieza», un Hak Sewa en borrador pasaría la venta de «Cobro pendiente» a «Sin firmar» mientras se cobra la
   obra. Siguen en la lista de documentos de la operación; solo no deciden su etapa mientras quede viva una pieza
   de dinero. Si todas las de dinero están liberadas y queda viva una que acompaña (un Hak Sewa de 30 años sobre
   una venta anulada), decide ESA: es justo lo que Operaciones tiene que enseñar, no esconderlo como «liberada»
   (revisor de código, 13-oct-2026). */
const PIEZAS_ACOMPANAN = ['poa', 'hak_sewa_notario', 'adenda'];
function piezaActiva(o){
  const cad = cadenaOperacion(o);
  const ultima = l => l[l.length - 1];
  const vivas = cad.filter(c => !c.liberado_en);
  const principalesVivas = vivas.filter(c => PIEZAS_ACOMPANAN.indexOf(c.tipo) === -1);
  return ultima(principalesVivas.length ? principalesVivas : vivas.length ? vivas : cad);
}
function etapaOperacion(o){
  const p = piezaActiva(o);
  /* Toda la cadena liberada (hallazgo Desarrollo, consulta de deploy 22-sep):
     no se debe nada ni hay firma que esperar. Quinto valor, FUERA de ETAPAS a
     proposito — el tablero de la clasica no lo pinta como columna. */
  if(p.liberado_en) return 'liberada';
  const caducada = f => f.expira_en && new Date(f.expira_en).getTime() < Date.now();
  if(!p.bloqueado) return (p.firmas || []).some(f => f.estado === 'pendiente' && !caducada(f)) ? 'firma_viva' : 'sin_firmar';
  const c = cuentaGrupo(o.padre || o);
  if(PIEZAS_ACOMPANAN.indexOf(p.tipo) !== -1 && !c.precio) return 'cobro_ok';
  if(!c.precio) return 'cobro_pend';
  return (c.pendiente != null && c.pendiente > 0) ? 'cobro_pend' : 'cobro_ok';
}


/* ═══════════════════════════════════════════════════════════════════════════
   EL CARGADOR — 26-ago-2026
   ═══════════════════════════════════════════════════════════════════════════
   Mismo motivo que el bloque de arriba: `/intranet/operaciones/v3/` lee EXACTAMENTE
   los mismos datos, y dos listas de consultas se separan solas. Se ha vuelto
   pura —ni globales, ni DOM, ni toast— para que la use cualquiera:

       const { ops, equipo, recortes, topes } =
             await lwOperacionesCargar(SB, msg => toast(msg));

   Los avisos y el recorte por tope se DEVUELVEN; quien llame decide dónde
   ponerlos en pantalla.
   ═══════════════════════════════════════════════════════════════════════════ */
/* Los topes viajan con las consultas que los aplican: un tope que se lee en un
   fichero y se usa en otro es un número que nadie recuerda que existe hasta que
   los totales salen cortos. */
/* TOPE_CONTRATOS 300 → 900 (22-sep-2026): producción iba por 261 contratos
   con el alta de histórico en marcha; a 300 el recorte habría dejado los
   totales parciales en semanas. Nunca ≥ 1000: el `+1` que detecta el
   recorte muere en el tope de filas de PostgREST. Medido el 24-ago: la
   consulta sin tocar `datos` cuesta 0,37 ms — el volumen no es el coste. */
const TOPE_CONTRATOS = 900, TOPE_FACTURAS = 500, TOPE_FIRMAS = 300;

async function lwOperacionesCargar(SB, avisar){
  /* `let` y no `const`: el cuerpo reasigna estas cuatro — venían de ser
     globales de la página, donde eso era legal. Con `const` la carga entera
     muere en «Assignment to constant variable» y la tabla dice «No se
     pudieron cargar» sin más pista. */
  let RECORTES = [], POR_CLIENTE = {}, EQUIPO = {}, OPS = [];
  const [c, f, s, cc, dc, eq, cb, pe, ro] = await Promise.all([
    /* ⚠️ NADA QUE SALGA DE `datos` EN ESTA CONSULTA. Medido el 24-ago-2026
       sobre la tabla real: pedir `hitos:datos->hitos` la deja en **3.852 ms**;
       la misma consulta sin tocar `datos`, en **0,37 ms**. Diez mil veces.

       El motivo no es el tamaño de lo que se pide, es TOAST: `contratos` guarda
       70 MB de jsonb en 112 filas (anexos en base64), y nombrar cualquier rama
       —`datos->hitos`, aunque sean 200 bytes— obliga a Postgres a descomprimir
       el valor ENTERO de cada fila. Paginar no lo arregla: 25 filas seguirían
       siendo ~15 MB de descompresión.

       Lo que se pedía de aquí y de dónde sale ahora:
       · `hitos`  → solo lo usa la ficha de UNA operación (`pintarDetalle`), así
                    que se carga al abrirla, no para las 112.
       · `adq1` + `compradores` → solo servían para contar cuántas personas
                    nombra el contrato. Ese número ya está en el espejo
                    `comprador_nombre`, que es texto plano. Comprobado contra la
                    base antes de fiarse: en los 112 contratos el conteo del
                    espejo coincide con el del documento, 112 de 112.

       La cura de fondo (sacar los base64 del jsonb) es otra tarea, y está
       registrada como pendiente con esta medición al lado. */
    // Va por la función `contratos_equipo()` (7-ago) y no por `.from('contratos')`
    // directo: desde que la RLS de SELECT filtra por autor, una lectura directa
    // dejaría a un agente normal viendo solo SUS contratos aquí — y Operaciones
    // existe justo para cruzar los de todo el equipo. Mismo dato, sin el filtro.
    SB.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,parcela_codigo,precio_total,moneda,fecha_firma,bloqueado,pdf_firmado_path,contrato_padre_id,created_at,creado_por,liberado_en,unidad_id' + (window.AXW_NUCLEO_OPERACION ? ',operacion_id' : '')).order('created_at',{ascending:false}).limit(TOPE_CONTRATOS + 1),
    // `created_at` va en el select aunque no se pinte: PostgREST exige que la
    // columna del `order` esté proyectada cuando el origen es una función (a
    // diferencia de una tabla/vista, donde ordenar por una columna no
    // seleccionada es normal) — hallazgo del verificador tras el push, 42703.
    SB.rpc('facturas_equipo').select('id,numero,tipo,contrato_id,contrato_numero,cliente_nombre,total,moneda,fecha_emision,anulada,created_at,venc:datos->fields->>fecha_vencimiento').order('created_at',{ascending:false}).limit(TOPE_FACTURAS + 1),
    // `snapshot_path` se pide solo para poder limpiar el almacenamiento al
    // borrar una operación: ver borrarOperacion().
    SB.rpc('contrato_firmas_equipo').select('id,contrato_id,firmante_nombre,firmante_email,firmante_rol,estado,creado_en,expira_en,firmado_en,snapshot_path').order('creado_en',{ascending:false}).limit(TOPE_FIRMAS + 1),
    // fichas reales de comprador. Si la tabla todavía no existe (migración sin
    // correr), esto falla solo y la ficha cae al nombre suelto del contrato.
    SB.from('contrato_compradores').select('contrato_id,rol,clients(id,full_name,email,phone,passport_number,kyc_status)'),
    // documentación del comprador (KYC). Se ata por `client_id`, no por
    // contrato: el pasaporte es de la persona, no de una venta, y sirve para
    // todas las que tenga.
    SB.from('documents').select('id,client_id,contrato_id,doc_type,storage_path,status,uploaded_at,caduca_el'),
    // email → nombre del equipo, solo para ENSEÑAR quién creó la operación.
    // `contratos.creado_por` guarda el email y así se queda: es la identidad con
    // la que la RLS decide quién edita lo suyo. Ojo: la RLS de `usuarios` deja
    // ver todas las fichas al admin y solo la propia al resto — a un agente le
    // saldrá el email en vez del nombre, que sigue identificando igual.
    SB.from('usuarios').select('email,nombre'),
    // "cobrado" real (11-ago, reforma del modelo de facturación): solo el
    // recibí prueba dinero recibido, una factura es lo que se debe — ver
    // facturas/sql/contrato_cobrado.sql. Se trae YA calculado en vez de
    // sumar aquí `facturas` a mano, para no tener dos copias de esa lógica.
    SB.rpc('contratos_cobrado_equipo'),
    // pendiente REAL por factura (no por contrato): la pestaña Vencimientos
    // (más abajo, pintarVencimientos) reclamaba el TOTAL de cada factura sin
    // restar lo ya cobrado por recibí — una factura saldada al 100% seguía
    // saliendo "vencida" en rojo para siempre. Misma función que ya usa
    // Facturas para lo mismo (facturas/sql/facturas_pendiente_equipo.sql):
    // una sola fuente para "cuánto queda de esta factura", no una segunda
    // resta a mano aquí.
    SB.rpc('facturas_pendiente_equipo'),
    // Operación del núcleo (ver más abajo): en paralelo con lo demás, no en una vuelta de red más.
    window.AXW_NUCLEO_OPERACION ? SB.rpc('operaciones_equipo').select('id,referencia,estado,client_id,moneda')
                                : Promise.resolve({ data: null, error: null }),
  ]);
  if(c.error) throw c.error;

  /* ¿Alguna consulta llegó a su tope? Va AQUÍ ARRIBA y no más abajo: `facturas` y
     `firmas` se leen dos líneas más adelante, y recortar después de eso dejaría a
     esas dos con la fila de sobra dentro — una factura fantasma en los totales.
     Se mira ANTES de descartarla, que es la única prueba de que hay más. */
  RECORTES = [];
  const recorta = (r, tope, nombre) => {
    if(r.error || !r.data || r.data.length <= tope) return r.data || [];
    RECORTES.push(nombre);
    return r.data.slice(0, tope);
  };
  c.data = recorta(c, TOPE_CONTRATOS, 'contratos');
  f.data = recorta(f, TOPE_FACTURAS,  'facturas');
  s.data = recorta(s, TOPE_FIRMAS,    'firmas');

  const facturas = f.error ? [] : (f.data || []);
  const firmas   = s.error ? [] : (s.data || []);
  const vinculos = cc.error ? [] : (cc.data || []);
  const docsKyc  = dc.error ? [] : (dc.data || []);
  const COBRADO = {};
  (cb.error ? [] : (cb.data || [])).forEach(x => { COBRADO[x.contrato_id] = Number(x.cobrado) || 0; });
  // pendiente real por factura (ver la nota junto a la consulta, más arriba):
  // se ata a cada factura aquí para que pintarVencimientos() lo lea de f.pendiente
  // sin tener que buscarlo en un mapa aparte.
  if(pe.error) avisar(ocT('No se pudo calcular lo pendiente por factura: ') + pe.error.message);
  const PENDIENTE = {};
  (pe.error ? [] : (pe.data || [])).forEach(x => { PENDIENTE[x.factura_id] = Number(x.pendiente) || 0; });
  facturas.forEach(x => { x.pendiente = x.id in PENDIENTE ? PENDIENTE[x.id] : parseImporte(x.total); });
  EQUIPO = {};
  (eq.error ? [] : (eq.data || [])).forEach(u => { if(u.nombre) EQUIPO[u.email] = u.nombre; });

  /* Qué contratos tiene cada persona. Un comprador encadena reserva, PPJB y
     obra: estando en uno hace falta saltar a los otros sin volver al listado.
     Se calcula una vez aquí, no por ficha. */
  POR_CLIENTE = {};
  vinculos.forEach(v => {
    if(!v.clients) return;
    (POR_CLIENTE[v.clients.id] = POR_CLIENTE[v.clients.id] || []).push(v.contrato_id);
  });
  if(f.error) avisar(ocT('No se pudieron leer las facturas: ') + f.error.message);
  if(s.error) avisar(ocT('No se pudieron leer las firmas: ') + s.error.message);
  if(cb.error) avisar(ocT('No se pudo calcular lo cobrado: ') + cb.error.message);

  /* Y si algo se recortó, se DICE. No con un toast, que se va en cuatro segundos:
     con una marca fija en la pantalla, porque mientras el tope siga alcanzado los
     totales de esta vista son parciales y hay que verlo cada vez que se entra.
     Cuando este aviso salga de verdad, ese es el momento de mover la agregación a
     una vista de Postgres — no antes. */
  /* El recorte por tope se DEVUELVE, no se pinta: quien llama decide dónde
     ponerlo. Decirlo no es opcional — unos totales parciales que no avisan
     de que son parciales son un número que miente. */
  const topes = { contratos:TOPE_CONTRATOS, facturas:TOPE_FACTURAS, firmas:TOPE_FIRMAS };


  OPS = (c.data || []).map(ct => ({
    ...ct,
    cobrado: COBRADO[ct.id] || 0,
    // las facturas viejas no tienen contrato_id (la columna es del 28-jul):
    // se enlazan también por el nº impreso para no perderlas de vista
    facturas: facturas.filter(x => x.contrato_id ? x.contrato_id === ct.id
                                                 : (x.contrato_numero && ct.numero && x.contrato_numero === ct.numero)),
    firmas: firmas.filter(x => x.contrato_id === ct.id),
    compradores: vinculos.filter(v => v.contrato_id === ct.id && v.clients)
                         .sort((a,b) => String(a.rol).localeCompare(String(b.rol))),
    // documentos de SUS compradores + los atados expresamente a este contrato
    docs: (() => {
      const suyos = vinculos.filter(v => v.contrato_id === ct.id && v.clients).map(v => v.clients.id);
      return docsKyc.filter(d => d.contrato_id === ct.id || suyos.includes(d.client_id));
    })(),
  }));

  /* Contratos vinculados (contratos.contrato_padre_id, puesto en Contratos al
     elegir la reserva/PPJB desde la Construcción): la misma venta deja de salir
     como dos filas. El hijo desaparece de la lista y vive dentro de la ficha
     del padre; si el padre no está entre los cargados, el hijo se queda como
     fila normal antes que desaparecer de la vista. */
  const porId = {};
  OPS.forEach(o => { porId[o.id] = o; o.hijos = []; o.padre = null; });
  /* `padre` es la RAÍZ de la venta, no el contrato inmediato (13-oct-2026): un Poder hecho desde un Hak Sewa que
     cuelga de su Bloqueo es nieto (PA → HS → RP; hoy ya existe PA00014 → CC00135 → RP00202). Con un solo nivel
     el nieto colgaba de un hijo, la lista lo quitaba por tener padre y el grupo de la raíz no lo traía: desaparecía
     de Operaciones. Se sube mientras el padre esté cargado; el tope y el «!== o» cortan un ciclo. */
  OPS.forEach(o => {
    let p = o.contrato_padre_id && porId[o.contrato_padre_id], n = 0;
    while(p && p !== o && p.contrato_padre_id && porId[p.contrato_padre_id] && porId[p.contrato_padre_id] !== o && n++ < 10)
      p = porId[p.contrato_padre_id];
    if(p && p !== o){ o.padre = p; p.hijos.push(o); }
  });

  /* AxisWorks ERP · la OPERACIÓN del núcleo (25-sep-2026, encargos/20260924_estudio_erp_modular.md). Cada fila
     cuelga de su operación: referencia OP-AAAA-NNNN y estado (en borrador = falta el comprador principal).
     SOLO con `window.AXW_NUCLEO_OPERACION`, que hoy enciende únicamente la demo del ERP: la base de Lawang aún no
     tiene la tabla `operaciones`, y sin la bandera este bloque no existe — ni una petición de más. Si la lectura
     falla, las filas se quedan como estaban: la operación es un dato de más, nunca una razón para no pintar. */
  if(window.AXW_NUCLEO_OPERACION){
    if(ro.error){ avisar(ocT('No se pudieron leer las operaciones: ') + ro.error.message); }
    else {
      const porOp = {};
      (ro.data || []).forEach(x => { porOp[x.id] = x; });
      OPS.forEach(o => { o.operacion = (o.operacion_id && porOp[o.operacion_id]) || null; });
    }
  }

  return { ops:OPS, equipo:EQUIPO, porCliente:POR_CLIENTE, recortes:RECORTES, topes };
}
