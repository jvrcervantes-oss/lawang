/* ═══════════════════════════════════════════════════════════════════════════
   EL CONTRATO NI CREA NI EDITA FICHAS — 19-ago-2026 (corrección del owner)
   `node ficha_solo_compradores.test.js`. Lo corre `tools/test.py`, y con él el
   gate de push.
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

console.log(fallos ? '\n' + fallos + ' fallo(s)' : '\nEl contrato no crea ni edita fichas.');
process.exit(fallos ? 1 : 0);
