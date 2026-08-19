/* ═══════════════════════════════════════════════════════════════════════════
   REGLAS DE LA PANTALLA DE CONTRATOS — 19-ago-2026
   `node contrato_reglas.test.js`. Lo corre `tools/test.py`, y con él el gate de
   push. (Nació como `ficha_solo_compradores.test.js`; se renombró al sumar los
   frenos de permisos, que son la misma clase de fallo.)
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE ESTE TEST. El 18-ago se construyó «el comprador sale de su
   ficha» y, de paso, se le dio al contrato la capacidad de CREAR el cliente
   («Crear ficha de cliente nuevo») y de CORREGIRLO («Corregir ficha», que
   escribía en `clients`). Parecía una comodidad. El owner lo tumbó al día
   siguiente: si dos pantallas pueden crear a la misma persona, la identidad
   vuelve a tener dos dueños — que es exactamente el problema que el cambio del
   18 venía a resolver.

   La norma está escrita en `contexto/suite_lawang.md` («Una persona se da de
   alta en UN solo sitio: Compradores»). Esto es su peldaño mecánico: una regla
   escrita se olvida, y este fallo no da error al cometerlo — el botón funciona
   perfectamente, solo que crea clientes desde donde no debe.

   Lo que afirma, sobre `app.html`:
     1. No hay ninguna escritura a `clients` (insert/update/upsert/delete).
     2. No vuelven los identificadores de los botones que se quitaron.
     3. El buscador sigue existiendo: quitar el alta no puede llevarse por
        delante la forma de ELEGIR a alguien, o el contrato queda sin comprador.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8');
let fallos = 0;

function afirma(titulo, ok, detalle) {
  if (ok) { console.log('  ok   ' + titulo); return; }
  fallos++;
  console.log('  FALLA ' + titulo + (detalle ? '\n         ' + detalle : ''));
}

/* 1) ninguna escritura a `clients` desde el contrato ------------------------
   Se busca la tabla y el verbo por separado y luego se comprueba que no van
   juntos: `.from('clients')` seguido de un método que escribe, en la misma
   cadena. Un `select` sí puede (y debe) seguir existiendo. */
const escrituras = [];
const re = /from\(\s*['"]clients['"]\s*\)\s*\n?\s*\.?\s*(\w+)/g;
let m;
while ((m = re.exec(app)) !== null) {
  if (/^(insert|update|upsert|delete)$/.test(m[1])) {
    const linea = app.slice(0, m.index).split('\n').length;
    escrituras.push(m[1] + '() en la línea ' + linea);
  }
}
afirma('app.html no escribe en `clients`', escrituras.length === 0, escrituras.join(' · '));

/* 2) los botones que se quitaron no vuelven -------------------------------- */
// `cliNuevo` NO está en la lista a propósito: ese id sobrevive como el ENLACE a
// Compradores. Lo que no puede volver es la función que escribía.
const prohibidos = ['crearFichaComprador', 'guardarCorreccionFicha', 'cliCorregir', 'CORRIGIENDO_FICHA'];
const vueltos = prohibidos.filter(p => app.includes(p));
afirma('no vuelven «Crear ficha» ni «Corregir ficha»', vueltos.length === 0, vueltos.join(' · '));
afirma('el enlace de alta apunta a Compradores',
  app.includes('/compradores/?nuevo=1'),
  'sin ese enlace, el aviso de «este comprador no tiene ficha» no dice dónde se da de alta');

/* 3) elegir cliente sigue siendo posible ----------------------------------- */
afirma('el buscador de clientes sigue en pie',
  app.includes('wireClienteBuscador(') && app.includes('enlazarFicha('));
afirma('los adquirientes II+ tienen su propio buscador',
  app.includes('data-cli-buscar'));

/* 4) una sola definición de «esta plantilla exige ficha» -------------------- */
const usos = (app.match(/plantillaExigeFicha\(\)/g) || []).length;
afirma('`plantillaExigeFicha()` es la única definición y se reutiliza', usos >= 2,
  'aparece ' + usos + ' vez/veces: el candado y el freno del guardado tienen que compartirla');

/* 5) el bloque de elegir comprador es UNO, no dos ---------------------------
   El 19-ago el owner preguntó por qué el buscador del Adquiriente I y el de los
   adicionales eran distintos. Lo eran porque había dos marcados para la misma
   acción. Ahora los pinta `bloqueElegirComprador()`; esto afirma que no vuelve
   a haber un segundo marcado suelto que pueda derivar del primero. */
const llamadas = (app.match(/bloqueElegirComprador\(/g) || []).length;
afirma('el bloque de elegir comprador se pinta desde una sola función',
  llamadas >= 3, 'aparece ' + llamadas + ' vez/veces (1 definición + 2 usos como mínimo)');
const literales = (app.match(/class="cli-pedir"/g) || []).length;
afirma('no hay un segundo marcado `cli-pedir` a mano', literales === 1,
  'aparece ' + literales + ' veces: si son dos, ya pueden separarse otra vez');

/* 6) «Diseño / Marca» es de admin, y detrás de un botón ---------------------
   19-ago, encargo del owner: mismo criterio que «Editar texto». El panel
   cambia el color de portada, el logo y la marca de agua, y su botón de
   guardar los deja fijados para TODOS los agentes. Que se cuele a un agente
   no da error: simplemente puede cambiar la marca de los contratos. */
afirma('el panel de Diseño solo se construye para admin',
  /if\(!CAN_EDIT_TEXT\) return '';/.test(app),
  'buildDesignPanel() tiene que salirse antes de pintar nada si no es admin');
afirma('el botón de Diseño se enseña con la misma llave que «Editar texto»',
  /dsgBtn\.style\.display = \(CAN_EDIT_TEXT && !LOCKED\)/.test(app));
afirma('el panel nace escondido y lo abre el botón',
  app.includes('id="designPanel" hidden') && app.includes("$('#btnDesign').addEventListener"));

console.log(fallos ? '\n' + fallos + ' fallo(s)' : '\nLas reglas de la pantalla de contratos se sostienen.');
process.exit(fallos ? 1 : 0);
