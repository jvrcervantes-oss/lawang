/* Borrador PARA EL COMPRADOR a partir del texto del modelo. Función PURA: la
   misma copia vive en la Edge Function (contracts/edge/bot-agentes/index.ts y
   su copia supabase/functions/bot-agentes/index.ts, entre los marcadores >>> y
   <<< de borradorComprador) y borrador_comprador.test.js comprueba que son
   iguales byte a byte — mismo mecanismo que plantillaTexto y postCheck.

   POR QUÉ EXISTE. El borrador que devuelve la edge (`borrador`) es para el
   AGENTE: lleva los puntos retirados con su motivo, las frases fijas, la lista
   de fuentes y la marca de IA. Lo que el agente copia para el comprador no
   puede llevar nada de eso. En vez de dejar que cada agente lo recorte a mano
   (y se le cuele un «pendiente de confirmación por el promotor»), el servidor
   entrega ya el recorte: solo los puntos no retirados, con su cita y su
   «Fuente: …», y nada dirigido al agente.

   Dentro del bloque viven también las frases fijas y `seccionesDe`, porque
   los dos los necesitan (la edge para ensamblar; esto para quitarlos) y solo
   pueden existir una vez: un test que probara otra copia de la frase no
   probaría nada. */
// >>> borradorComprador
/* Frases fijas: las mismas que el prompt (bot_fuentes.prompt_sistema) le exige
   al modelo. El servidor las escribe en los puntos retirados (ensambla) y las
   quita del texto que va al comprador (borradorComprador). Viven en este
   bloque para que contracts/bot/borrador_comprador.js sea la MISMA copia byte
   a byte que la edge — mismo mecanismo que plantillaTexto y postCheck. */
const FRASE_PENDIENTE = 'Este punto está pendiente de confirmación por el promotor: no lo confirmes al comprador hasta tenerla.';
const FRASE_CONTRAOFERTA = 'Esto es una contraoferta comercial: la decide el promotor, no se responde desde aquí. Trasládasela y no contestes al comprador hasta tener su respuesta.';
const MARCA_IA = 'Borrador generado por IA — revísalo antes de enviarlo';

/* ── El texto del modelo, en secciones «N. …» ────────────────────────────
   El prompt le exige «N. Encabezado — Clase» por punto. Se parte por esas
   cabeceras; lo anterior a la primera es el preámbulo (aviso de plantilla
   cambiada) y las líneas «Fuentes usadas:» / marca IA se apartan para
   ponerlas al final una sola vez. Sin anotaciones de tipo: este bloque corre
   tal cual en node. */
function seccionesDe(texto) {
  const secciones = new Map();
  const pre = [];
  const cola = [];
  let actual = null;
  for (const linea of String(texto ?? '').split(/\r?\n/)) {
    if (/^\s*Fuentes usadas\s*:/i.test(linea)) { cola.push(linea.trim()); actual = null; continue; }
    if (linea.includes(MARCA_IA)) { actual = null; continue; }
    const m = linea.match(/^\s*(\d{1,2})\.\s+(.*)$/);
    if (m) { actual = [linea.trim()]; secciones.set(Number(m[1]), actual); continue; }
    if (actual) actual.push(linea);
    else if (linea.trim()) pre.push(linea.trim());
  }
  return { pre, secciones, cola };
}

/* Solo los puntos que el servidor NO retiró, numerados como el comprador, con
   el texto del modelo para cada uno (incluidas sus líneas «Fuente: …») y sin
   nada de lo que va dirigido al agente: bloques retirados, «Fuentes usadas:»,
   la marca de IA, el preámbulo (aviso de plantilla cambiada) ni las frases
   fijas — aunque el modelo las haya escrito en un punto no retirado. Si el
   modelo no siguió la numeración (mismo criterio que `ensambla`), devuelve su
   texto entero limpio de esas líneas. Un punto no retirado al que el modelo no
   respondió no aparece: el aviso «(el modelo no ha respondido…)» es para el
   agente, no para el comprador. */
function borradorComprador(puntos, textoModelo) {
  const esFraseFija = (l) => l.includes(FRASE_PENDIENTE) || l.includes(FRASE_CONTRAOFERTA);
  const esCola = (l) => /^\s*Fuentes usadas\s*:/i.test(l) || l.includes(MARCA_IA);
  const limpia = (lineas) => lineas.filter((l) => !esFraseFija(l) && !esCola(l)).join('\n').replace(/\n{3,}/g, '\n\n').trim();
  const lista = Array.isArray(puntos) ? puntos : [];
  const { secciones } = seccionesDe(textoModelo);
  const numerados = lista.filter((p) => p && p.n > 0);
  const modeloNumeroBien = numerados.length === 0 || numerados.some((p) => secciones.has(p.n));
  if (!modeloNumeroBien) return limpia(String(textoModelo ?? '').split(/\r?\n/));
  const salida = [];
  for (const p of numerados) {
    if (p.motivos && p.motivos.length) continue;
    const sec = secciones.get(p.n);
    if (!sec) continue;
    const texto = limpia(sec);
    if (texto) salida.push(texto);
  }
  return salida.join('\n\n').trim();
}
// <<< borradorComprador

if (typeof module !== 'undefined') module.exports = { borradorComprador, seccionesDe, FRASE_PENDIENTE, FRASE_CONTRAOFERTA, MARCA_IA };
