/* ============================================================================
   Identidad de Lawang (y el cargador de las cuentas de cobro) — FUENTE ÚNICA
   ----------------------------------------------------------------------------
   Lo usan `contracts/app.html` (contratos) y `facturas/index.html` (facturas).
   Vivía inline en app.html hasta el 27-jul-2026; se saca aquí porque un número
   de cuenta duplicado en dos herramientas se corrige en una y se queda viejo en
   la otra — y ahí el fallo es dinero enviado al sitio equivocado.

   Define tres globales: CUENTAS_BANCARIAS, SOCIEDADES y APODERADOS_HAK_SEWA.
   Sin módulos a propósito: las dos apps son HTML plano con <script> clásico.

   Los textos que llevan palabras van como {es,en,id} porque los contratos se
   imprimen en tres idiomas; las facturas usan solo `es`/`en`.
   ========================================================================== */

/* ---------- cuentas de cobro — YA NO VIVEN AQUÍ (6-ago-2026) ----------
   Los 15 números de cuenta estaban escritos en este fichero, y este fichero es
   PÚBLICO por dos caminos a la vez: se sirve con 200 sin login (lo cargan las
   nueve herramientas de la suite y el portal del comprador) y está en el repo
   `jvrcervantes-oss/lawang`, que es público, legible en crudo desde el 27-jul.
   Unas coordenadas bancarias abiertas son la materia prima de un fraude de
   transferencia, y a diferencia de una contraseña **un número de cuenta no se
   rota**: la única salida es que dejen de publicarse.

   Ahora viven en la tabla `public.cuentas_bancarias` con RLS: SELECT solo para
   `authenticated`, ni lectura ni escritura para `anon` (verificado con un GET
   anónimo al REST: 401, no un `[]` ambiguo). El repo se queda público a
   propósito — de él depende el auto-deploy de Hostinger; lo que sale del repo
   son las cuentas, no el hosting.

   SOCIEDADES se queda: es la identidad que ya va impresa en todo contrato y
   factura que el comprador tiene en la mano, así que ocultarla no protege nada.

   Cómo se usa: `await cargarCuentasBancarias(sb)` una vez al arrancar, antes de
   pintar el select de cuentas o de imprimir un documento. Quien lea
   CUENTAS_BANCARIAS después lo hace igual que siempre. */
const CUENTAS_BANCARIAS = {};
let CUENTAS_PROMESA = null;

/* Rellena el objeto EN SU SITIO (Object.assign, nunca reasignar): `firma-submit`
   y `facturas/documento.test.js` publican esta misma referencia en su `caja`
   evaluando los cuatro ficheros compartidos de una vez, así que cambiar el
   objeto por otro los dejaría leyendo uno vacío para siempre.
   Si la consulta falla, LANZA y deja la promesa a null para poder reintentar: un
   fallo silencioso aquí imprime un contrato sin datos de pago, que es
   exactamente el error que este fichero existe para evitar. */
function cargarCuentasBancarias(sb){
  if(CUENTAS_PROMESA) return CUENTAS_PROMESA;
  CUENTAS_PROMESA = (async () => {
    const { data, error } = await sb.from('cuentas_bancarias')
      .select('clave,label,titular,banco,cuenta,codigo,direccion,extra,es_escrow')
      .eq('activa', true).order('orden');
    if(error){ CUENTAS_PROMESA = null; throw error; }
    (data || []).forEach(r => {
      CUENTAS_BANCARIAS[r.clave] = { label:r.label, titular:r.titular, banco:r.banco,
        cuenta:r.cuenta, codigo:r.codigo, direccion:r.direccion, extra:r.extra,
        // `es_escrow` (14-sep-2026): lo dice la CUENTA, ya no su nombre. Antes
        // `tablaCuentaHTML` decidía imprimir la declaración de depósito en
        // garantía mirando si la clave empezaba por `notario_`. Esa convención
        // se sostenía mientras las cuentas nacían escribiendo SQL a mano; desde
        // que el super admin puede crearlas desde /intranet/cuentas/, no hay
        // nada que la garantice — y el fallo sería mudo: una cláusula de escrow
        // que no sale, o que sale en un contrato que no la pactó.
        es_escrow: !!r.es_escrow };
    });
    return CUENTAS_BANCARIAS;
  })();
  return CUENTAS_PROMESA;
}

/* ---------- QUÉ CUENTAS SE OFRECEN EN CADA PLANTILLA (14-sep-2026) ----------
   Esto vivía en cuatro listas escritas a mano en JavaScript: `BANCO_UNICO`,
   `BANCOS_CONSTRUCCION` y `BANCOS_CC00014_TIMON` en `entidades_pago.js`, y
   `CUENTA_DEFAULT` en `contracts/app.html`. Cambiar en qué cuenta cobra la
   Carta de Reserva era una edición de código y un despliegue — y el owner lo
   pidió al revés: «no son editables ni marcables lo que quiero que aparezca en
   cada una».

   Ahora manda `public.plantilla_cuentas`, que el super admin edita desde
   /intranet/cuentas/. Lee cualquier sesión del equipo (el generador necesita el
   mapeo para pintar su selector); escribe SOLO el super admin, por RLS.

   Igual que `cargarCuentasBancarias`, y por el mismo motivo: si la consulta
   falla LANZA y deja la promesa a null para poder reintentar. Un fallo callado
   aquí deja el selector vacío y acaba en un contrato sin destino de pago, que es
   exactamente el error que esta familia de ficheros existe para evitar. */
const PLANTILLA_CUENTAS = {};   // { slug: { claves:[...], porDefecto:'clave'|'' } }
/* El catálogo entero de plantillas, para el panel y para el picker de «Nuevo
   contrato»: [{ slug, nombre, orden, cobra, archivada }]. Se llama PAGO por
   historia (nació con las 8 que cobran) y hoy trae las 20 — quien filtre por
   `cobra` o por `archivada` lo hace donde lo necesita, no aquí: el cargador
   NUNCA esconde una plantilla archivada, porque un contrato ya guardado de ese
   tipo tiene que poder reabrirse. */
const PLANTILLAS_PAGO = [];
let PLANTILLA_CUENTAS_PROMESA = null;
function cargarPlantillaCuentas(sb){
  if(PLANTILLA_CUENTAS_PROMESA) return PLANTILLA_CUENTAS_PROMESA;
  PLANTILLA_CUENTAS_PROMESA = (async () => {
    const [cat, map] = await Promise.all([
      // `plantillas_contrato` (antes `plantillas_pago`): desde el 14-sep-2026 es el
      // catálogo COMPLETO —las 20 plantillas— y no solo las 8 que cobran, porque
      // de aquí sale también qué tipos están archivados. `cobra` distingue a las
      // que pintan selector de cuenta; `archivada`, las que no se ofrecen al crear.
      sb.from('plantillas_contrato').select('slug,nombre,orden,cobra,archivada').order('orden'),
      sb.from('plantilla_cuentas').select('slug,clave,es_default')
    ]);
    if(cat.error){ PLANTILLA_CUENTAS_PROMESA = null; throw cat.error; }
    if(map.error){ PLANTILLA_CUENTAS_PROMESA = null; throw map.error; }
    // EN SU SITIO, nunca reasignando: mismo motivo que CUENTAS_BANCARIAS —
    // quien ya tenga la referencia (las pruebas, la edge de firma) se quedaría
    // leyendo un objeto vacío para siempre.
    PLANTILLAS_PAGO.length = 0;
    (cat.data || []).forEach(r => PLANTILLAS_PAGO.push(r));
    Object.keys(PLANTILLA_CUENTAS).forEach(k => delete PLANTILLA_CUENTAS[k]);
    /* Solo las que COBRAN entran en el mapa, y el matiz importa: tener entrada
       aquí significa «esta plantilla tiene un reparto definido», y una entrada
       con la lista vacía significa «se desmarcaron todas» — que `bankOptionsFor`
       respeta ofreciendo cero. Si se inicializaran las 20, las 12 que no cobran
       pasarían de «sin reparto» (→ se ofrecen todas, la degradación segura) a
       «reparto vacío» (→ ninguna), y eso cambiaría el significado de la lista
       vacía, que es el caso que este código distingue con más cuidado. */
    (cat.data || []).filter(r => r.cobra)
      .forEach(r => { PLANTILLA_CUENTAS[r.slug] = { claves: [], porDefecto: '' }; });
    (map.data || []).forEach(r => {
      const e = PLANTILLA_CUENTAS[r.slug] || (PLANTILLA_CUENTAS[r.slug] = { claves: [], porDefecto: '' });
      e.claves.push(r.clave);
      if(r.es_default) e.porDefecto = r.clave;
    });
    return PLANTILLA_CUENTAS;
  })();
  return PLANTILLA_CUENTAS_PROMESA;
}

/* ---------- Y LA EXCEPCIÓN POR PROYECTO (14-sep-2026) ----------
   Encargo del owner el mismo día que lo de arriba: «en carta de reserva esta
   cuenta bancaria pero si seleccionas Palm Field puede ser esta otra».

   No es una matriz proyecto × tipo —232 casillas que nadie mantendría— sino una
   EXCEPCIÓN sobre el reparto general: un proyecto declara solo en qué se sale de
   la norma, y lo que no diga lo hereda.

   `PROYECTO_CUENTAS` queda indexado por `proyecto_id` y, dentro, por slug de
   plantilla, con `'*'` para «cualquier tipo de contrato de este proyecto»:
     { <uuid>: { 'ppjb_parcela': {claves:[…], porDefecto:'…'},
                 '*':            {claves:[…], porDefecto:'…'} } }
   Quien resuelve la cascada es `bankOptionsFor` (entidades_pago.js); aquí solo
   se carga. Lanza si falla, igual que sus dos hermanas y por lo mismo. */
const PROYECTO_CUENTAS = {};
let PROYECTO_CUENTAS_PROMESA = null;
function cargarProyectoCuentas(sb){
  if(PROYECTO_CUENTAS_PROMESA) return PROYECTO_CUENTAS_PROMESA;
  PROYECTO_CUENTAS_PROMESA = (async () => {
    const { data, error } = await sb.from('proyecto_cuentas')
      .select('proyecto_id,slug,clave,es_default');
    if(error){ PROYECTO_CUENTAS_PROMESA = null; throw error; }
    Object.keys(PROYECTO_CUENTAS).forEach(k => delete PROYECTO_CUENTAS[k]);   // en su sitio, nunca reasignar
    (data || []).forEach(r => {
      const p = PROYECTO_CUENTAS[r.proyecto_id] || (PROYECTO_CUENTAS[r.proyecto_id] = {});
      const e = p[r.slug] || (p[r.slug] = { claves: [], porDefecto: '' });
      e.claves.push(r.clave);
      if(r.es_default) e.porDefecto = r.clave;
    });
    return PROYECTO_CUENTAS;
  })();
  return PROYECTO_CUENTAS_PROMESA;
}

/* ---------- apoderados de la serie Hak Sewa — MISMO MOTIVO que las cuentas ----------
   El NIK (identificador nacional indonesio) y la dirección de un apoderado son
   datos personales de un PARTICULAR, no de una sociedad — a diferencia del
   representante de SOCIEDADES (nombre+pasaporte, ya público por registro
   mercantil), esto no tiene ese mismo colchón. Vivían en tokens.json, que se
   sirve igual de público que este fichero (hallazgo Seguridad, 12-ago-2026).
   Ahora en `public.apoderados_hak_sewa` con la misma RLS que cuentas_bancarias
   (SELECT solo `authenticated`). tokens.json se queda solo con los NOMBRES
   (las opciones del <select>), que hacen falta para pintar el formulario. */
const APODERADOS_HAK_SEWA = {};
let APODERADOS_PROMESA = null;
function cargarApoderadosHakSewa(sb){
  if(APODERADOS_PROMESA) return APODERADOS_PROMESA;
  APODERADOS_PROMESA = (async () => {
    const { data, error } = await sb.from('apoderados_hak_sewa')
      .select('clave,edad,ocupacion,direccion,nik,ktp')
      .eq('activo', true).order('orden');
    if(error){ APODERADOS_PROMESA = null; throw error; }
    (data || []).forEach(r => {
      APODERADOS_HAK_SEWA[r.clave] = { edad:r.edad, ocupacion:r.ocupacion,
        direccion:r.direccion, nik:r.nik, ktp:r.ktp };
    });
    return APODERADOS_HAK_SEWA;
  })();
  return APODERADOS_PROMESA;
}

/* ---------- sociedades emisoras ----------
   `razon`/`marca`/`domicilio`/`npwp`/`rep` alimentan tanto los marcadores
   {{prom_*}} de las plantillas de contrato como la cabecera del emisor en las
   facturas. `cred` (nacionalidad + documento del representante) solo la usan
   los contratos.

   Identidad del documento por sociedad (30-jul-2026) — cada sociedad emite con
   su marca, no con la de Lawang, y una factura de PT SAN DAL WOODS con el logo
   de Lawang dice que la emite otra empresa:
     `logo`      cabecera del documento
     `logoAlto`  alto del logo (por defecto 15mm)
     `logo2`     segundo logo debajo del primero (el lockup de palabra), opcional
     `logo2Ancho` ancho de ese segundo logo
     `folio`     color del papel
     `tinta`     {primary, deep} = todo lo coloreado del documento
   Lo usan hoy las facturas (los contratos llevan su logo fijo en cada
   plantilla). Añadir una sociedad = un bloque más aquí, nada más. */
/* ---------- sociedades emisoras — YA NO VIVEN AQUI (17-sep-2026) ----------
   Estaban escritas a mano en este fichero: razon social, NPWP, NIB, domicilio,
   representante, logo, folio y tinta de las tres sociedades. Ahora viven en
   `public.sociedades`, con RLS (SELECT solo `authenticated`) y escritura solo
   para super admin, y se editan desde /intranet/sociedades/.

   POR QUE SE MUEVEN. No es por ocultarlas —la identidad de la emisora ya va
   impresa en cada documento que el comprador tiene en la mano— sino por la
   norma de la suite: «si el cliente lo puede dar de alta, o cambiar de opinion
   sobre ello, no puede vivir en un fichero». Cada alta o correccion exigia un
   commit y un despliegue. Y con mas de una empresa dentro de la intranet la
   lista deja de ser «lo que va impreso» y pasa a ser el censo de clientes del
   estudio, que no puede servirse sin sesion.

   `clave` (tepi_sungai, san_dal_woods, sandal_woods_ltd) NO CAMBIA NUNCA: va
   guardada dentro de cada contrato (`sociedad_firmante`) y de cada factura, y
   las plantillas la miran en `<!--if:sociedad_firmante=tepi_sungai-->`. La base
   rechaza renombrarla.

   Como se usa: `await cargarSociedades(sb)` una vez al arrancar, ANTES de
   pintar el selector de sociedad o de imprimir un documento. Quien lea
   SOCIEDADES despues lo hace igual que siempre.

   Y el emisor de un documento ya emitido no sale de aqui: desde el 17-sep cada
   factura congela su emisor dentro (`datos.emisor`) al crearse, asi que editar
   una sociedad ya no reescribe lo que reimprime un documento viejo. */
const SOCIEDADES = {};
let SOCIEDADES_PROMESA = null;

/* Rellena el objeto EN SU SITIO, nunca reasignar — mismo motivo que en
   `cargarCuentasBancarias`: `firma-submit` y los tests publican esta misma
   referencia en su `caja`, asi que cambiar el objeto por otro los dejaria
   leyendo uno vacio para siempre.
   Si la consulta falla, LANZA y deja la promesa a null para poder reintentar.
   Un fallo mudo aqui imprime un documento SIN emisor, o —peor— con el emisor
   equivocado: hasta el 17-sep-2026 habia siete sitios que, al no encontrar la
   sociedad, caian a `tepi_sungai` en silencio. Eso hacia que un contrato de
   San Dal Woods emitiera su factura con el NPWP de la otra PT. */
function cargarSociedades(sb){
  if(SOCIEDADES_PROMESA) return SOCIEDADES_PROMESA;
  SOCIEDADES_PROMESA = (async () => {
    const { data, error } = await sb.from('sociedades')
      .select('clave,label,razon,marca,npwp,npwp_label,nib,domicilio,rep,logo,logo_alto,emisor_debajo,folio,tinta')
      .eq('activa', true).order('orden');
    if(error){ SOCIEDADES_PROMESA = null; throw error; }
    (data || []).forEach(r => {
      SOCIEDADES[r.clave] = {
        label: r.label, razon: r.razon, marca: r.marca || '',
        domicilio: r.domicilio, npwp: r.npwp, rep: r.rep,
        // `npwpLabel` y `nib` solo si los trae: `documento.js` da por hecho
        // 'NPWP' cuando falta la etiqueta, y una cadena vacia no es lo mismo
        // que no tener NIB.
        ...(r.npwp_label && r.npwp_label !== 'NPWP' ? { npwpLabel: r.npwp_label } : {}),
        ...(r.nib ? { nib: r.nib } : {}),
        logo: r.logo, logoAlto: r.logo_alto,
        ...(r.emisor_debajo ? { emisorDebajo: true } : {}),
        folio: r.folio, ...(r.tinta ? { tinta: r.tinta } : {})
      };
    });
    return SOCIEDADES;
  })();
  return SOCIEDADES_PROMESA;
}

/* ---------- credenciales de quien puede aparecer como "Firmante" ----------
   El campo "Firmante" de Gestión del contrato (ver applyPromotor en app.html)
   permite imprimir en un documento a alguien distinto del representante POR
   DEFECTO de la sociedad elegida — hasta el 11-ago-2026 eso se resolvía
   buscando `data.firmante` entre los `.rep` de SOCIEDADES, lo que funcionaba
   mientras cada nombre siguiera siendo el rep actual de alguna sociedad.
   Dejó de valerse el 11-ago-2026: al cambiar tepi_sungai.rep de I Made Monjong
   Adhi Nugruah a I Wayan Eka Aryawan, cuatro contratos ya creados pero sin
   firmar (CC00020, CC00019, RP00031, CR00018) quedaron guardados con
   firmante=I Made Monjong — al reabrirlos, la búsqueda ya no encontraba a
   nadie con ese `.rep` y el documento imprimía en silencio al representante
   NUEVO, sin que nadie lo hubiera elegido (hallazgo Legal, confirmado con los
   cuatro números de contrato reales). Esta tabla desacopla "quién puede
   aparecer firmando" de "quién es HOY el rep por defecto de cada sociedad":
   añadir aquí = una entrada más, y NUNCA se borra la de alguien que ya pudo
   firmar o puede tener un contrato en vuelo con su nombre guardado.

   MISMO MOTIVO que las cuentas y los apoderados de Hak Sewa (24-ago-2026,
   revisión previa Seguridad+Legal): el número de documento (NIK/pasaporte) de
   un representante es más sensible que su nombre+cargo — permite suplantación,
   no solo identificación — y este fichero se sirve público sin login. El
   nombre+cargo (`SOCIEDADES.<x>.rep`) SÍ se queda aquí: es la misma identidad
   que ya imprime cada contrato/factura en manos del comprador, y "quién
   representa a la sociedad" es público por registro mercantil — el número de
   documento exacto no. Base legal para conservar el dato: ejecución de
   contrato, se imprime en el documento que esa persona firma. Ahora en
   `public.firmantes_cred`, misma RLS que apoderados_hak_sewa/cuentas_bancarias
   (SELECT solo `authenticated`). Clave = nombre, igual que antes. */
const FIRMANTES_CRED = {};
let FIRMANTES_PROMESA = null;
function cargarFirmantesCred(sb){
  if(FIRMANTES_PROMESA) return FIRMANTES_PROMESA;
  FIRMANTES_PROMESA = (async () => {
    /* Las sociedades PRIMERO: mas abajo se recorre SOCIEDADES para repoblar
       `soc.cred`/`soc.rep_npwp`, y desde el 17-sep-2026 ese objeto nace vacio y
       lo llena `cargarSociedades`. Sin esta espera el bucle no encontraria
       ninguna sociedad y las credenciales se quedarian sin enganchar EN
       SILENCIO — el contrato saldria sin el documento del representante. */
    await cargarSociedades(sb);
    const { data, error } = await sb.from('firmantes_cred')
      .select('nombre,rep_npwp,cred_es,cred_en,cred_id');
    if(error){ FIRMANTES_PROMESA = null; throw error; }
    (data || []).forEach(r => {
      FIRMANTES_CRED[r.nombre] = { rep_npwp: r.rep_npwp,
        cred: { es: r.cred_es, en: r.cred_en, id: r.cred_id } };
    });
    // Repuebla soc.cred/soc.rep_npwp de cada sociedad a partir de su rep POR
    // DEFECTO — san_dal_woods y sandal_woods_ltd comparten representante
    // (misma persona real), así que esto también los deja consistentes entre
    // sí sin duplicar el dato dos veces en la tabla.
    Object.values(SOCIEDADES).forEach(soc => {
      const c = FIRMANTES_CRED[soc.rep];
      if(c){ soc.cred = c.cred; soc.rep_npwp = c.rep_npwp; }
    });
    return FIRMANTES_CRED;
  })();
  return FIRMANTES_PROMESA;
}

/* ---------- etiqueta humana de `contratos.tipo` ----------
   Copiado a propósito, no movido: ya vivía inline en operaciones/index.html
   (TIPO_ES) desde el 5-ago y ese sitio sigue funcionando — sacarlo de ahí para
   esta tarea habría sido tocar un fichero que nadie pidió cambiar. Esta copia
   la usa `facturas/index.html` para el prefijo "[Parcela]"/"[Construcción]"
   cuando combina conceptos de dos contratos vinculados (7-ago-2026). Si diverge
   de la de operaciones, unificarlas aquí sería el momento — no antes. */
const TIPO_ES = { reserva_parcela:'Parcela', construccion:'Construcción', contrato_general:'Contrato General',
  commercial_offer:'Oferta Comercial', carta_reserva:'Carta de Reserva',
  carta_reserva_ampliada:'Carta de Reserva ampliada', acuerdo_comercial:'Acuerdo Comercial',
  protocolo_operativo:'Protocolo Operativo', ppjb_bonian:'PPJB Bonian Beach',
  poa:'POA (Poder Notarial)' };

/* ---------- sociedad firmante: default por plantilla y RESOLVER ----------
   Movido aquí desde contracts/app.html el 9-sep-2026 (revisión previa de
   Datos y Desarrollo): el panel de Vencimientos necesita la MISMA regla para
   atribuir cada contrato a su sociedad, y dos copias de una regla de negocio
   divergen en silencio — el día que una plantilla nueva cambie su default,
   el dinero aparecería bajo la sociedad equivocada sin ningún error.

   El porqué del único default especial (escrito el 8-sep en app.html, se
   conserva): ppjb_reserva llevaba NPWP/domicilio de SAN DAL WOODS (bajo el
   nombre inexistente "PT Lawang Tropical Properties"), así que arranca en
   SAN DAL WOODS para no alterar su identidad real. El resto de plantillas
   cae en Tepi Sun Gai, que es el default global de projectDefaults. */
const SOCIEDAD_DEFAULT = { ppjb_reserva: 'san_dal_woods' };

/* La sociedad de un contrato o factura YA GUARDADO: manda lo elegido; vacío,
   el default de su plantilla; sin plantilla con default, Tepi Sun Gai — que
   es exactamente lo que imprime el documento emitido (pdef() del generador).
   Quien filtre o agrupe por sociedad llama AQUÍ, nunca reimplementa. */
function lwSociedadContrato(campo, tipo){
  const v = String(campo || '').trim();
  return v || SOCIEDAD_DEFAULT[tipo] || 'tepi_sungai';
}
