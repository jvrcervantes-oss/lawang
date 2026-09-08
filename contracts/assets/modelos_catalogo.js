/* El catálogo de modelos, para las tres pantallas que lo usan — 8-sep-2026.

   POR QUÉ EXISTE
   --------------
   «Qué casas se pueden construir en este proyecto» no es un dato nuevo: son las
   filas de `modelos_villa`, que además llevan el precio de obra pactado para ese
   proyecto. Lo consultan tres sitios y cada uno lo estaba resolviendo a su
   manera:

   · `intranet/proyectos/` — el desplegable «Modelo de villa» de cada parcela.
     Ya leía `modelos_villa` y resolvía la herencia de precio, dentro de la
     pantalla.
   · `intranet/modelos/`   — declarar un modelo en un proyecto («Añadir a un
     proyecto…»). El INSERT vivía dentro del `guardar()` de esa pantalla.
   · `contracts/app.html`  — la Tipología del contrato de Construcción. No leía
     ni una cosa ni la otra: `tokens.json` tenía SEIS nombres a mano y `MODELOS_DB`
     los sustituía por los `distinct unidades.modelo`, o sea el texto libre del
     inventario en vez del catálogo.

   El owner pidió el 8-sep que las tres bebieran de Modelos y poder elegir desde
   el proyecto qué se construye en él. Con la lógica repartida, eso eran tres
   copias de la misma regla — y la regla de esta suite es que una lista escrita a
   mano en dos sitios ES el bug, no la causa del bug. Aquí está una vez.

   NO TOCA EL DOM y NO IMPONE UN ORDEN DE CARGA: las funciones de lectura son
   PURAS y reciben los datos ya cargados (`intranet/proyectos/` los pide en la
   misma tanda que el resto de su pantalla, y no va a dejar de hacerlo para usar
   esto). Quien no los tenga, tiene `lwCargarCatalogoModelos()`.
   ========================================================================== */

/* Los modelos que se pueden construir en un proyecto, con el precio de obra ya
   resuelto.

   LA HERENCIA SE RESUELVE AQUÍ Y EN NINGÚN OTRO SITIO. `precio_construccion` a
   NULL en `modelos_villa` significa HEREDA del catálogo, no «sin precio»
   (cascada del 7-sep: catálogo → proyecto → unidad). El día que Palm Field pasó
   a heredar, la pantalla de Proyectos enseñó sus dos modelos SIN precio porque
   leía la columna a pelo. Con tres lectores era cuestión de tiempo que uno se
   olvidara; con uno, no puede.
   Y la MONEDA viaja con el precio y del MISMO nivel que lo dio: un proyecto en
   rupias heredando una cifra en euros del catálogo no es un detalle, es un error
   de tres órdenes de magnitud (Riverfront va en IDR).

   🔴 CUANDO EL PROYECTO NO TIENE NINGUNO DECLARADO SE OFRECE EL CATÁLOGO ENTERO,
   avisando de ello (`declarados:false`). No es una concesión: hoy 16 de los 29
   proyectos activos no tienen ni una fila en `modelos_villa`, así que filtrar a
   secas dejaría el desplegable VACÍO y no se podría ni dar de alta la parcela ni
   hacer el contrato. Es el mismo pez que se mordía la cola que ya pasó con los
   resorts el 27-ago —no se podía elegir uno nuevo hasta que un proyecto lo
   usara, y para asignárselo había que poder elegirlo—, y se resuelve igual: la
   restricción aprieta cuando hay algo con lo que apretar. */
function lwModelosDeProyecto(proyecto, villas, catalogo){
  const cat = catalogo || [];
  const declarados = (villas || []).filter(v => v.proyecto === proyecto);
  if(declarados.length){
    const lista = declarados.map(v => {
      const c = cat.find(x => x.id === v.modelo_id) || null;
      const heredado = v.precio_construccion == null && c && c.precio_construccion != null;
      return {
        modelo: v.modelo,
        modelo_id: v.modelo_id,
        precio_construccion: heredado ? Number(c.precio_construccion)
                             : (v.precio_construccion != null ? Number(v.precio_construccion) : null),
        moneda: heredado ? (c.moneda || v.moneda) : v.moneda,
        heredado: !!heredado,
        ficha: c,
      };
    });
    lista.sort((a, b) => String(a.modelo).localeCompare(String(b.modelo)));
    return { lista, declarados: true };
  }
  return {
    lista: cat.map(c => ({
      modelo: c.nombre, modelo_id: c.id,
      precio_construccion: c.precio_construccion != null ? Number(c.precio_construccion) : null,
      moneda: c.moneda, heredado: false, ficha: c,
    })),
    declarados: false,
  };
}

/* Para quien no tenga ya cargados los dos: Contratos. Devuelve SIEMPRE un objeto
   —nunca lanza— porque quien llama está pintando un formulario; sin red se
   queda con las listas vacías y cada pantalla decide su respaldo. */
async function lwCargarCatalogoModelos(sb){
  if(!sb) return { catalogo: [], villas: [], error: 'sin conexión' };
  const [c, v] = await Promise.all([
    sb.from('modelos')
      .select('id, slug, nombre, dormitorios, banos, villa_m2, terraza_m2, precio_construccion, moneda')
      .eq('activo', true).order('nombre'),
    sb.from('modelos_villa').select('id, proyecto, proyecto_id, modelo, modelo_id, precio_construccion, moneda'),
  ]);
  if(c.error || v.error)
    return { catalogo: [], villas: [], error: ((c.error || v.error) || {}).message || 'error' };
  return { catalogo: c.data || [], villas: v.data || [] };
}

/* DECLARAR / RETIRAR modelos en un proyecto. La escritura vivía dentro de
   `intranet/modelos/index.html`; se muda aquí porque desde hoy la hace también
   Proyectos, y una copia pegada de otra herramienta es deuda, no reutilización.

   `seleccion` = ids del catálogo que deben quedar declarados en ese proyecto.
   `enUso` = nombres de modelo que YA usa alguna parcela de ese proyecto: esos no
   se retiran aunque se desmarquen — quitar la declaración dejaría a la unidad
   nombrando un modelo que su propio proyecto dice que no se construye, que es
   justo la incoherencia que este encargo viene a cerrar. Se devuelven en
   `rechazadas` para que la pantalla diga POR QUÉ, no solo que no se pudo.

   El alta va por `upsert` con `onConflict: 'proyecto,modelo'` porque la unicidad
   de la tabla es esa —`UNIQUE (proyecto, modelo)`, sobre el TEXTO y no sobre los
   ids—, así que declarar dos veces lo mismo no revienta ni duplica.
   ⚠️ Y todas las filas del lote llevan LAS MISMAS CLAVES a propósito: un upsert
   en lote manda una sola sentencia con la unión de las claves de todo el array y
   pone NULL donde a una fila le falte alguna. Mezclar formas aquí borraría el
   precio propio de un proyecto en silencio (8-sep-2026, el fallo del import CSV
   de unidades — ver `proyectos_csv.js`). */
async function lwDeclaraModelosEnProyecto(sb, proyecto, seleccion, ctx){
  const c = ctx || {};
  const catalogo = c.catalogo || [];
  const villas = (c.villas || []).filter(v => v.proyecto === proyecto);
  const enUso = c.enUso || new Set();
  const quiere = new Set(seleccion || []);

  const altas = [...quiere]
    .filter(id => !villas.some(v => v.modelo_id === id))
    .map(id => catalogo.find(x => x.id === id))
    .filter(Boolean)
    .map(m => ({
      proyecto, proyecto_id: c.proyecto_id || null,
      modelo: m.nombre, modelo_id: m.id,
      precio_construccion: null, moneda: m.moneda || 'EUR',
      notas: 'Declarado desde la ficha del proyecto el ' + new Date().toISOString().slice(0, 10)
             + '. Hereda el precio de catálogo.',
    }));

  const bajasTodas = villas.filter(v => v.modelo_id && !quiere.has(v.modelo_id));
  const rechazadas = bajasTodas.filter(v => enUso.has(v.modelo));
  const bajas = bajasTodas.filter(v => !enUso.has(v.modelo));

  if(altas.length){
    const e = await sb.from('modelos_villa').upsert(altas, { onConflict: 'proyecto,modelo' });
    if(e.error) return { ok: false, error: e.error.message, altas: 0, bajas: 0, rechazadas };
  }
  if(bajas.length){
    const e = await sb.from('modelos_villa').delete().in('id', bajas.map(b => b.id));
    if(e.error) return { ok: false, error: e.error.message, altas: altas.length, bajas: 0, rechazadas };
  }
  return { ok: true, altas: altas.length, bajas: bajas.length, rechazadas };
}

if(typeof module !== 'undefined' && module.exports)
  module.exports = { lwModelosDeProyecto, lwCargarCatalogoModelos, lwDeclaraModelosEnProyecto };
