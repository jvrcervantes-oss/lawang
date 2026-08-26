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
const textoHito = h => h.es || h.en || h.id || 'Hito sin nombre';

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
  if(!s) return { texto:'Sin comprador', extra:'', titulo:'' };
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
  const sumables = grupo.filter(o => !lwEsPreliminar(o.tipo));
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
  ['sin_firmar', 'Sin firmar',      'espera'],
  ['firma_viva', 'Firma enviada',   'info'],
  ['cobro_pend', 'Cobro pendiente', 'alerta'],
  ['cobro_ok',   'Cobro completo',  'ok'],
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
  if(o.tipo === 'poa' && !c.precio) return 'cobro_ok';
  if(c.precio == null || !c.precio) return 'cobro_pend';   // firmado sin precio: no se afirma que esté cobrado
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
const TOPE_CONTRATOS = 300, TOPE_FACTURAS = 500, TOPE_FIRMAS = 300;

async function lwOperacionesCargar(SB, avisar){
  /* `let` y no `const`: el cuerpo reasigna estas cuatro — venían de ser
     globales de la página, donde eso era legal. Con `const` la carga entera
     muere en «Assignment to constant variable» y la tabla dice «No se
     pudieron cargar» sin más pista. */
  let RECORTES = [], POR_CLIENTE = {}, EQUIPO = {}, OPS = [];
  const [c, f, s, cc, dc, eq, cb, pe] = await Promise.all([
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
    SB.rpc('contratos_equipo').select('id,numero,tipo,comprador_nombre,proyecto_nombre,precio_total,moneda,fecha_firma,bloqueado,pdf_firmado_path,contrato_padre_id,created_at,creado_por').order('created_at',{ascending:false}).limit(TOPE_CONTRATOS + 1),
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
  if(pe.error) avisar('No se pudo calcular lo pendiente por factura: ' + pe.error.message);
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
  if(f.error) avisar('No se pudieron leer las facturas: ' + f.error.message);
  if(s.error) avisar('No se pudieron leer las firmas: ' + s.error.message);
  if(cb.error) avisar('No se pudo calcular lo cobrado: ' + cb.error.message);

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
  OPS.forEach(o => {
    const p = o.contrato_padre_id && porId[o.contrato_padre_id];
    if(p && p !== o){ o.padre = p; p.hijos.push(o); }
  });

  return { ops:OPS, equipo:EQUIPO, porCliente:POR_CLIENTE, recortes:RECORTES, topes };
}
