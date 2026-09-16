/* GATE: ninguna pantalla pide `.order('codigo')` a Postgres. `node orden_codigo.test.js`.
   ============================================================================
   `.order('codigo')` es orden de TEXTO: SH-1, SH-10, SH-100, SH-101… y la SH-2 cien
   filas más abajo. El owner lo vio dos veces: el 26-ago-2026 (se corrigió en el
   cliente con suiOrdenarPorCodigo) y el 16-sep-2026 en /intranet/v4/proyectos/, que
   no carga suite.js y además cortaba con `.limit(60)` — así que la SH-2 ni siquiera
   llegaba al navegador. Segunda reincidencia de la misma regla escrita: escalera de
   aprendizaje, de regla a guardrail.

   Desde el 16-sep-2026 el orden lo pone la base: `unidades.codigo_orden` es una
   columna generada con la clave natural (migración
   20260916120000_unidades_codigo_orden_natural.sql) y la vista `unidades_estado`
   la expone. Se ordena por ELLA. Este test recorre el repo y falla con fichero:línea
   si alguien vuelve a escribir `.order('codigo')`.

   Se ignoran: comentarios (este mismo motivo está documentado en varios sitios),
   Backups/, node_modules/, y los stubs `_qa*`/`_test*`/`_verify*`/`_diag*`, que son
   copias congeladas para QA y no se sirven a nadie. */
const fs = require('fs');
const path = require('path');

const RAIZ = path.resolve(__dirname, '..');
const SALTA_DIR = new Set(['node_modules', 'Backups', '.git', 'dist', 'build']);
const STUB = /^_(qa|test|verify|diag)/;
const EXT = /\.(js|html|php)$/i;
const PATRON = /\.order\(\s*['"]codigo['"]\s*\)/g;

function sinComentarios(src){
  // Bloques /* … */ y <!-- … -->, y líneas que empiezan por // o --
  return src
    .replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
    .replace(/<!--[\s\S]*?-->/g, m => m.replace(/[^\n]/g, ' '))
    .replace(/^\s*(\/\/|--).*$/gm, '');
}

function recorre(dir, out){
  for(const nombre of fs.readdirSync(dir)){
    const ruta = path.join(dir, nombre);
    const st = fs.statSync(ruta);
    if(st.isDirectory()){
      if(!SALTA_DIR.has(nombre)) recorre(ruta, out);
    }else if(EXT.test(nombre) && !STUB.test(nombre) && !/\.test\.js$/.test(nombre)){
      out.push(ruta);
    }
  }
  return out;
}

let fallos = 0;
for(const f of recorre(RAIZ, [])){
  const limpio = sinComentarios(fs.readFileSync(f, 'utf8'));
  const lineas = limpio.split('\n');
  lineas.forEach((l, i) => {
    if(PATRON.test(l)){
      fallos++;
      console.error(`  FALLA  ${path.relative(RAIZ, f)}:${i + 1}  .order('codigo') es orden de texto — usa .order('codigo_orden')`);
    }
    PATRON.lastIndex = 0;
  });
}

if(fallos){
  console.error(`\n${fallos} consulta(s) ordenan parcelas como texto. La columna generada unidades.codigo_orden existe desde el 16-sep-2026: ordena por ella.`);
  process.exit(1);
}
console.log('orden_codigo: ninguna consulta ordena parcelas por texto');
