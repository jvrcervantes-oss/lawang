/* ═══════════════════════════════════════════════════════════════════════════
   LA LISTA DE EVENTOS, EN UN SOLO SITIO — 19-ago-2026
   `node eventos.test.js`. Lo corre `tools/test.py`, y con él el gate de push.
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE. `contrato_eventos.evento` está limitado por un CHECK a una
   lista cerrada. Escribir en código un evento que no esté en esa lista NO da un
   error donde se comete: la escritura del evento revienta la operación ENTERA
   que la contenía, y el mensaje habla de una restricción, no de lo que estabas
   haciendo. Ha mordido TRES veces:

     · 14-ago — 'poa' estaba en la app y en la numeración pero no en el CHECK de
       `contratos.tipo`: 400 al guardar un Poder Notarial (misma familia, otra
       tabla; ficha LAW-48).
     · 18-ago — un CHECK de tabla ajena volvió a parar un guardado.
     · 19-ago — LAW-71: los cinco eventos de privilegio no estaban en el CHECK,
       así que un super admin editando un contrato firmado fallaba entero.

   Por la escalera de aprendizaje del estudio, a la tercera la regla escrita se
   promociona a guardarraíl mecánico. Esto es ese peldaño.

   NO LEE LA BASE a propósito: un test del gate de push no puede depender de la
   red. Lee la lista declarada en `sql/super_admin_poderes.sql`, que desde hoy es
   la declaración ÚNICA del CHECK, y la compara con los eventos que el código
   escribe de verdad.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');

const aqui = (...p) => path.join(__dirname, ...p);
const leer = (...p) => fs.readFileSync(aqui(...p), 'utf8');

let fallos = 0;
function afirma(titulo, ok, detalle) {
  if (ok) { console.log('  ok   ' + titulo); return; }
  fallos++;
  console.log('  FALLA ' + titulo + (detalle ? '\n         ' + detalle : ''));
}

/* ── la lista que manda: el CHECK ──────────────────────────────────────────── */
const declaracion = leer('sql', 'super_admin_poderes.sql');
const bloque = declaracion.match(
  /add constraint contrato_eventos_evento_check\s*\n?\s*check \(evento = any \(array\[([\s\S]*?)\]\)\)/);
afirma('el CHECK de eventos se declara en sql/super_admin_poderes.sql', !!bloque,
  'si se mueve de fichero, hay que traer este test con él');
const PERMITIDOS = new Set(bloque ? [...bloque[1].matchAll(/'([a-z0-9_]+)'/g)].map(m => m[1]) : []);

/* ── los que el código escribe ─────────────────────────────────────────────── */
const FUENTES = ['sql/registro_eventos.sql', 'sql/super_admin_poderes.sql',
                 'sql/parcela_traspaso_carta_a_bloqueo.sql', 'sql/traspaso_mismo_comprador_y_enlace.sql',
                 'app.html'];
const usados = new Map();   // evento → dónde
FUENTES.forEach(rel => {
  let txt;
  try { txt = leer(...rel.split('/')); } catch (_) { return; }   // fichero que ya no exista: no es este test quien lo vigila

  /* Dos formas de escribir un evento en esta suite, y solo dos. Se buscan en la
     POSICIÓN del evento, no cualquier literal suelto: `detalle` es un jsonb
     lleno de claves con guion bajo (colgado_de, campos_total…) y buscarlas
     todas daba falsos positivos que hacían inútil el test. */
  // 1) registra_privilegio(contrato, 'evento' | case … 'a' … 'b' end, detalle)
  [...txt.matchAll(/registra_privilegio\(([\s\S]{0,260}?)\)\s*;/g)].forEach(m => {
    const args = m[1];
    const corte = args.indexOf('jsonb_build_object');
    [...(corte > 0 ? args.slice(0, corte) : args).matchAll(/'([a-z0-9_]+)'/g)]
      .forEach(x => usados.set(x[1], rel));
  });
  // 2) insert into contrato_eventos … values (<contrato>, 'evento', …)
  //    o … select <contrato>, 'evento', …
  txt.split(/insert into public\.contrato_eventos/i).slice(1).forEach(t => {
    const cabeza = t.slice(0, 400);
    const v = cabeza.match(/values\s*\(\s*[^,]+,\s*'([a-z0-9_]+)'/i);
    if (v) usados.set(v[1], rel);
    const q = cabeza.match(/select\s+[^,]+,\s*'([a-z0-9_]+)'/i);
    if (q) usados.set(q[1], rel);
  });
});

afirma('se han encontrado eventos escritos en el código', usados.size > 0,
  'si esto falla, el rastreo de arriba dejó de reconocer cómo se escriben');

const huerfanos = [...usados.entries()].filter(([e]) => !PERMITIDOS.has(e));
afirma('todo evento que el código escribe está en el CHECK',
  huerfanos.length === 0,
  huerfanos.map(([e, d]) => `«${e}» en ${d}`).join(' · '));

/* ── y al revés: la lista no acumula eventos muertos ───────────────────────── */
// Informativo, no bloqueante: un evento del CHECK que ya nadie escribe puede ser
// histórico (filas viejas que hay que poder seguir leyendo), así que no falla.
const sinUsar = [...PERMITIDOS].filter(e => !usados.has(e));
if (sinUsar.length) console.log('  nota  en el CHECK y sin escribirse hoy: ' + sinUsar.join(', ')
  + ' — normal si hay filas históricas con ese evento');

console.log(fallos ? '\n' + fallos + ' fallo(s)' : '\nLa lista de eventos y el código dicen lo mismo.');
process.exit(fallos ? 1 : 0);
