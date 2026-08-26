/* Importación de inventario por CSV — pieza compartida de la suite. 26-ago-2026.

   POR QUÉ EXISTE AQUÍ Y NO DENTRO DE UNA PANTALLA
   -----------------------------------------------
   Esto no es «parsear un CSV»: son reglas de negocio que costaron tres
   incidentes seguidos, cada uno perdiendo columnas EN SILENCIO —el aviso decía
   «columnas ignoradas» y nadie lo lee fila a fila—. Están todas anotadas abajo,
   junto a la línea que las arregla.

   Cuando la v3 de Proyectos pidió el mismo botón, la salida fácil era copiar
   estas 100 líneas. Sería la copia número dos de una lista de alias que ya ha
   crecido tres veces por sorpresa: el día que llegue un CSV con una cabecera
   nueva, se añadiría el alias en una pantalla y no en la otra, y la que no lo
   tuviera volvería a perder la columna sin decir nada. Aquí está una vez.

   NO TOCA EL DOM. Recibe el texto y el catálogo, devuelve el análisis. Cada
   pantalla lo pinta a su manera — esa parte sí es suya.
   ========================================================================== */

/* El tope es de BYTES y se comprueba antes de leer nada. Contar filas exige
   haber parseado (un salto de línea dentro de un campo entrecomillado no es una
   fila), así que ese límite llega después — con los 5 MB ya acotados, parsear de
   más cuesta milisegundos, no es una vía de DoS. */
const LW_CSV_MAX_BYTES = 5 * 1024 * 1024;
const LW_CSV_MAX_FILAS = 5000;

/* Cabecera del CSV (minúsculas, sin acentos) → columna real de `unidades`.
   ⚠️ NINGUNA clave de este mapa es `estado` ni `contrato_id`, a propósito: esos
   dos los mueve el flujo de contratos, y dejar que un CSV los pisara sería
   marcar una parcela como vendida desde una hoja de cálculo. Tienen su camino
   manual en el formulario de la unidad, que es donde debe estar.

   🔴 7-ago-2026 — los exports de Notion del cliente vienen en inglés: «Type»
   (el modelo de villa), «Land»/«Villa» (los dos precios). Sin estos alias esas
   tres columnas se ignoraban enteras y el modelo y los dos precios desaparecían
   al importar, en silencio.
   🔴 10-ago-2026 — el mismo fallo otra vez con otra cabecera: el CSV «SUMBA
   PLOTS» traía «Modelo de villa»/«Precio de suelo»/«Precio de construcción»
   (con preposición), que no casaban con ningún alias. Añadidos.
   `fase`/`zone` van a `fase_masterplan`/`zona_masterplan`, NUNCA a `obra_fase`:
   esa es la fase de OBRA de una unidad concreta, un concepto distinto que por
   casualidad se llama igual en el lenguaje del negocio. */
const LW_CSV_COLUMNAS = {
  codigo:'codigo', proyecto:'proyecto', tipo:'tipo', modelo:'modelo', type:'modelo', modelo_de_villa:'modelo',
  superficie:'superficie_m2', superficie_m2:'superficie_m2', m2:'superficie_m2',
  precio_suelo:'precio_suelo', suelo:'precio_suelo', land:'precio_suelo', precio_de_suelo:'precio_suelo',
  precio_construccion:'precio_construccion', construccion:'precio_construccion', villa:'precio_construccion',
  precio_de_construccion:'precio_construccion',
  precio:'precio', precio_total:'precio', total:'precio',
  moneda:'moneda', notas:'notas',
  fase:'fase_masterplan', zone:'zona_masterplan', zona:'zona_masterplan',
};

/* Quita acentos y todo lo que no sea letra/número: «Superficie (m2)» y
   «superficie_m2» casan igual. De la puntuación exacta no puede depender que una
   columna se reconozca o se pierda.
   🔴 «m²» (U+00B2) se colaba: NFD descompone letras acentuadas, no superíndices,
   así que sobrevivía al normalize y la limpieza lo dejaba en «m» — que no es
   ninguna clave, y la columna se perdía entera. Se sustituye ANTES. */
const lwCsvNormCab = s => String(s == null ? '' : s).replace(/²/g,'2').replace(/³/g,'3')
  .normalize('NFD').replace(/[̀-ͯ]/g,'')
  .toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^_+|_+$/g,'');

/* Mitigación estándar de CSV/formula injection (OWASP): un valor que empieza por
   = + - @ o tab/CR se ejecuta como fórmula al reabrir la celda en Excel/Sheets, y
   el estudio reexporta estos datos. Se antepone una comilla: se sigue leyendo
   igual, deja de ejecutarse. */
const lwCsvAntiFormula = s => {
  /* Tabulador y retorno de carro dentro del valor se normalizan a espacio ANTES
     de mirar el primer carácter: si no, un valor que empieza por tabulador se
     colaba —el tabulador también abre fórmula en Sheets— y además reventaba la
     celda al reexportar. Es la implementación que ya tenía `proyectos/index.html`;
     aquí no se reescribe, se muda. */
  const v = String(s == null ? '' : s).replace(/[\t\r]/g, ' ').trim();
  return /^[=+\-@]/.test(v) ? "'" + v : v;
};

/* Parser propio (RFC4180: comillas, comas y saltos dentro de un campo
   entrecomillado, "" como comilla escapada). Ninguna herramienta de la suite
   carga una librería para esto y el caso cabe en quince líneas. */
function lwCsvParse(texto){
  const filas = []; let fila = []; let campo = ''; let enComillas = false;
  const t = String(texto).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  for(let i = 0; i < t.length; i++){
    const c = t[i];
    if(enComillas){
      if(c === '"'){ if(t[i+1] === '"'){ campo += '"'; i++; } else enComillas = false; }
      else campo += c;
    }else if(c === '"'){ enComillas = true; }
    else if(c === ','){ fila.push(campo); campo = ''; }
    else if(c === '\n'){ fila.push(campo); filas.push(fila); fila = []; campo = ''; }
    else campo += c;
  }
  if(campo !== '' || fila.length){ fila.push(campo); filas.push(fila); }
  return filas.filter(f => f.some(c => c.trim() !== ''));
}

/* EL ANÁLISIS COMPLETO. Devuelve SIEMPRE un objeto; un fichero que no sirve se
   dice con `error`, nunca lanzando — quien llama está pintando una pantalla.

   ctx = { tipos:[clave…], proyectos:[nombre…], existentes:Set('Proyecto codigo'),
           parseImporte }
   `parseImporte` se INYECTA en vez de importarse: es la de `dinero.js`, que ya
   es la única forma de leer un importe en la suite, y así esta pieza no impone
   un orden de carga a quien la use. */
function lwCsvAnaliza(texto, ctx){
  const c = ctx || {};
  const parseImporte = c.parseImporte || (v => Number(String(v).replace(',', '.')) || 0);
  const filas = lwCsvParse(texto);
  if(!filas.length) return { error: 'El fichero está vacío.' };
  if(filas.length - 1 > LW_CSV_MAX_FILAS)
    return { error: `El fichero trae ${filas.length - 1} filas — el máximo son ${LW_CSV_MAX_FILAS}. Pártelo en varios.` };

  const cabecera = filas[0].map(lwCsvNormCab);
  const mapa = cabecera.map(x => LW_CSV_COLUMNAS[x] || null);
  const ignoradas = cabecera.filter((x, i) => !mapa[i]);
  if(!mapa.includes('codigo') || !mapa.includes('proyecto'))
    return { error: 'El CSV necesita al menos las columnas `codigo` y `proyecto`.' };

  const tiposOk = new Set(c.tipos || []);
  const proyectos = c.proyectos || [];
  const existentes = c.existentes || new Set();
  const num = v => { const n = parseImporte(v); return v && n ? n : null; };

  const analizadas = filas.slice(1).map((cols, idx) => {
    const d = {}; mapa.forEach((campo, i) => { if(campo) d[campo] = (cols[i] == null ? '' : cols[i]).trim(); });
    const errores = [];
    const codigo = lwCsvAntiFormula(d.codigo || '');
    const proyectoCsv = d.proyecto || '';
    /* Mismo criterio de coincidencia que `public.mismo_proyecto()` en Supabase:
       el nombre no siempre casa exacto entre sitios — típicamente entre lo que
       exporta Notion («Bonian Village by Balian Hills») y el catálogo («Bonian
       Village», desde que el 7-ago se separó el Resort del nombre). Si coincide
       por contención se usa el nombre TAL CUAL vive en el catálogo, nunca el del
       CSV: si no, se crearía una segunda variante del mismo proyecto. */
    const proyectoCat = proyectoCsv
      ? proyectos.find(p => { const a = p.toLowerCase(), b = proyectoCsv.toLowerCase();
                              return a === b || a.includes(b) || b.includes(a); })
      : null;
    const proyecto = proyectoCat || proyectoCsv;
    const tipo = (d.tipo || 'parcela').toLowerCase().trim();
    if(!codigo) errores.push('sin código');
    if(!proyectoCsv) errores.push('sin proyecto');
    else if(!proyectoCat) errores.push(`proyecto "${proyectoCsv}" no está en el catálogo — créalo primero con «+ Nuevo proyecto»`);
    if(!tiposOk.has(tipo)) errores.push(`tipo "${tipo}" no está en el catálogo`);
    return {
      fila: idx + 2,                       // +2: encabezado + base-1
      codigo, proyecto, tipo,
      modelo: d.modelo ? lwCsvAntiFormula(d.modelo) : null,
      superficie_m2: num(d.superficie_m2), precio_suelo: num(d.precio_suelo),
      precio_construccion: num(d.precio_construccion), precio: num(d.precio),
      moneda: (d.moneda || 'EUR').toUpperCase(),
      notas: d.notas ? lwCsvAntiFormula(d.notas) : null,
      fase_masterplan: d.fase_masterplan ? lwCsvAntiFormula(d.fase_masterplan) : null,
      zona_masterplan: d.zona_masterplan ? lwCsvAntiFormula(d.zona_masterplan) : null,
      esAlta: codigo && proyecto ? !existentes.has(proyecto + ' ' + codigo) : null,
      errores,
    };
  });

  const validas = analizadas.filter(f => !f.errores.length);
  return {
    analizadas, validas, ignoradas,
    /* Qué columnas trajo ESTE CSV. Al confirmar NO se manda una clave que el
       fichero nunca trajo: «sin dato» no es lo mismo que «vacío a propósito», y
       una actualización no debe borrar una columna que el CSV ni menciona. */
    camposPresentes: new Set(mapa.filter(Boolean)),
    altas: validas.filter(f => f.esAlta).length,
    actualiza: validas.filter(f => !f.esAlta).length,
    conError: analizadas.length - validas.length,
  };
}

if(typeof module !== 'undefined' && module.exports)
  module.exports = { lwCsvParse, lwCsvNormCab, lwCsvAntiFormula, lwCsvAnaliza,
                     LW_CSV_COLUMNAS, LW_CSV_MAX_BYTES, LW_CSV_MAX_FILAS };
