/* ═══════════════════════════════════════════════════════════════════════════
   UN COMPRADOR PUEDE SER UNA EMPRESA — 19-ago-2026 (encargo del owner)
   `node comprador_empresa.test.js`. Lo corre `tools/test.py`, y con él el gate
   de push.
   ═══════════════════════════════════════════════════════════════════════════
   QUÉ AFIRMA, Y POR QUÉ NINGUNO DE ESTOS FALLOS DA ERROR AL COMETERLO:

   1. Cada plantilla con párrafo de comprador tiene las DOS redacciones
      (persona y empresa) y la de persona sigue siendo la que sale por defecto.
      Si alguien retoca una plantilla y se lleva por delante un `if:`, el
      documento saldría SIN párrafo de Segunda Parte: un contrato sin comprador
      identificado, impreso y enviado sin que nada proteste.
   2. Los campos que usa la redacción de empresa están declarados en
      tokens.json. Un marcador sin campo se imprime VACÍO — el contrato saldría
      con «sociedad de forma jurídica ____ constituida conforme a las leyes de
      ____» y nadie se enteraría hasta leerlo en papel.
   3. La cláusula histórica de PT PMA sigue en pie. CR00018, CC00020 y RP00046
      son contratos reales con esos campos rellenos; borrar el bloque cambiaría
      lo que imprimen tres documentos ya entregados.
   4. El motor de plantillas sigue entendiendo `if:` y `opt:` como este test
      supone. Las dos expresiones de abajo son COPIA de app.html, así que se
      comprueba que allí siguen tal cual: si el motor cambia y esta copia no,
      el test estaría dando por bueno un render que ya no ocurre.
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

const app = leer('app.html');
const tokens = JSON.parse(leer('tokens.json'));
const CAMPOS_COMPRADOR = new Set(
  (tokens.sections.find(s => s.id === 'comprador') || { fields: [] }).fields.map(f => f[0]));

/* ── el motor, tal cual está en app.html ───────────────────────────────────── */
const RE_OPT = /<!--opt:([a-z0-9_]+)-->[\s\S]*?<!--\/opt:\1-->/g;
const RE_IF = /<!--if:([a-z0-9_]+)=([a-z0-9_]+)-->[\s\S]*?<!--\/if:\1-->/g;
afirma('el motor de app.html sigue siendo el que este test copia',
  app.includes("html=html.replace(/<!--opt:([a-z0-9_]+)-->[\\s\\S]*?<!--\\/opt:\\1-->/g")
  && app.includes("html=html.replace(/<!--if:([a-z0-9_]+)=([a-z0-9_]+)-->[\\s\\S]*?<!--\\/if:\\1-->/g"),
  'si cambian esas dos líneas, hay que traer el cambio aquí antes de fiarse del resto');

function renderBloques(html, data) {
  return html
    .replace(RE_OPT, (m, k) => (k in data && data[k] !== '') ? m : '')
    .replace(RE_IF, (m, k, v) => (data[k] === v) ? m : '');
}

/* ── 1) las dos redacciones, en cada plantilla que las necesita ────────────── */
const CON_COMPRADOR = ['carta_reserva', 'carta_reserva_ampliada',
                       'ppjb_parcela', 'ppjb_construccion', 'ppjb_reserva'];

CON_COMPRADOR.forEach(slug => {
  const html = leer('templates', slug + '.html');
  const persona = renderBloques(html, { adq1_tipo: 'persona' });
  const empresa = renderBloques(html, { adq1_tipo: 'empresa' });
  const viejo   = renderBloques(html, { adq1_tipo: 'persona', comp_razon: 'PT BEMY GUEST INVESTMENTS',
                                        comp_npwp: '1000 0000 0914 0751' });

  afirma(slug + ': persona imprime SU párrafo y no el de empresa',
    persona.includes('{{adq1_nombre}}') && !persona.includes('{{adq1_forma_juridica}}'));
  afirma(slug + ': empresa imprime SU párrafo y no el de persona',
    empresa.includes('{{adq1_forma_juridica}}') && empresa.includes('{{adq1_rep_nombre}}'));
  afirma(slug + ': ningún tipo se queda sin párrafo de comprador',
    persona.includes('{{adq1_nombre}}') && empresa.includes('{{adq1_nombre}}'));
  afirma(slug + ': la cláusula histórica de PT PMA solo sale si el contrato la trae',
    !persona.includes('{{comp_razon}}') && viejo.includes('{{comp_razon}}'));
});

/* ── 1b) el nº de registro desaparece si no lo hay ─────────────────────────
   19-ago, visto en CR00035 (ABJ ASENATH ADMINISTRACIÓN SL, sin registro
   mercantil puesto): el contrato imprimía «nº de registro e identificación
   fiscal B47711270», que se lee como si el NIF fuera también el número de
   registro. No es un hueco feo, es un documento firmado diciendo algo que no
   es. Va envuelto en `opt:` como {{prom_marca}} en la Primera Parte. */
CON_COMPRADOR.forEach(slug => {
  const html = leer('templates', slug + '.html');
  const conRegistro = renderBloques(html, { adq1_tipo: 'empresa', adq1_registro: 'RM-1' });
  const sinRegistro = renderBloques(html, { adq1_tipo: 'empresa' });
  afirma(slug + ': el nº de registro solo se imprime si el contrato lo trae',
    conRegistro.includes('{{adq1_registro}}') && !sinRegistro.includes('{{adq1_registro}}'));
  afirma(slug + ': sin registro, la frase no encadena con la identificación fiscal',
    !/registro\s*(<[^>]*>\s*)*(e|and|dan)\s+identificaci|register no\.\s*(<[^>]*>\s*)*and\s+tax/i
      .test(sinRegistro.replace(/\s+/g, ' ')));
});

/* ── 2) los campos de la redacción de empresa existen como campo ───────────── */
const DE_EMPRESA = ['adq1_forma_juridica', 'adq1_registro', 'adq1_rep_nombre',
                    'adq1_rep_cargo', 'adq1_domicilio'];
DE_EMPRESA.forEach(k => afirma('`' + k + '` está declarado en tokens.json',
  CAMPOS_COMPRADOR.has(k), 'sin campo, el marcador se imprime en blanco'));

/* ── 3) la sección tecleada a mano ya no existe ────────────────────────────── */
afirma('la sección «firma como sociedad (PT PMA)» no vuelve al formulario',
  !tokens.sections.some(s => s.id === 'sociedad'),
  'los datos de la sociedad salen de su ficha, no se teclean por contrato');

/* ── 3b) NINGÚN campo derivado se cuela en el formulario ────────────────────
   21-ago-2026, lo vio el owner: «han aparecido un montón de campos nuevos en los
   contratos: comp razon, comp domicilio, comp nib, comp npwp y adq1_tipo».

   Qué pasó. El 19-ago se retiró de tokens.json la sección «el adquiriente firma
   como sociedad (PT PMA)», pero sus marcadores siguen dentro de CINCO plantillas
   (CR00018, CC00020 y RP00046 los llevan rellenos). Y deriveSections tiene un
   cajón automático: todo marcador de la plantilla que NO esté declarado cae en
   «Otros campos» con el nombre en crudo. O sea que quitar la declaración es
   exactamente lo que los soltó ahí — la cura fue la enfermedad.

   Y el test de abajo lo dejó pasar porque comprobaba QUE NO ESTUVIERA LA SECCIÓN,
   que es otra cosa que lo que había que comprobar: que no se vieran los CAMPOS.
   Un test puede estar en verde y no cubrir nada.

   Esto mira lo que de verdad pasa: reconstruye el cajón de «otros» para cada
   plantilla, leyendo de app.html las mismas exclusiones que aplica el programa
   (así no hay una segunda lista que se quede vieja), y exige que ningún campo
   DERIVADO —los que el programa rellena solo— aparezca en él. */
{
  const DERIVADOS = /^(comp_|prom_)|^adq1_tipo$/;   // los rellena el programa, nunca se teclean

  // las exclusiones tal y como las escribe app.html, no copiadas a mano
  const borrados = new Set([...app.matchAll(/inDoc\.delete\('([a-z0-9_]+)'\)/g)].map(m => m[1]));
  const prefijos = [...app.matchAll(/k\.startsWith\('([a-z0-9_]+)'\)\)\s*inDoc\.delete\(k\)/g)].map(m => m[1]);
  const anadidos = new Set([...app.matchAll(/inDoc\.add\('([a-z0-9_]+)'\)/g)].map(m => m[1]));
  afirma('el test sigue reconociendo cómo app.html excluye campos',
    borrados.size > 3 && prefijos.length > 0,
    'si deriveSections cambia de forma, esta lectura deja de ver nada y el test se vuelve decorativo');

  const declarados = new Set(tokens.sections.flatMap(s => (s.fields || []).map(f => f[0])));

  fs.readdirSync(aqui('templates')).filter(f => f.endsWith('.html') && !f.startsWith('_')).forEach(f => {
    const html = leer('templates', f);
    const enDoc = new Set([
      ...[...html.matchAll(/\{\{([a-z0-9_]+)\}\}/g)].map(m => m[1]),
      ...[...html.matchAll(/<!--if:([a-z0-9_]+)=/g)].map(m => m[1]),
    ]);
    anadidos.forEach(k => enDoc.add(k));
    const enOtros = [...enDoc].filter(k =>
      !declarados.has(k) && !borrados.has(k) && !prefijos.some(p => k.startsWith(p)));
    const colados = enOtros.filter(k => DERIVADOS.test(k));
    afirma(f + ': ningún campo derivado acaba en «Otros campos»',
      colados.length === 0,
      colados.join(', ') + ' — se preguntarían a mano, y el programa ya los rellena');
  });
}

/* ── 4) app.html: quién decide el tipo ─────────────────────────────────────── */
afirma('`adq1_tipo` sale de la ficha enlazada y por defecto es persona',
  /data\.adq1_tipo = \(ADQ1_CLIENT && ADQ1_CLIENT\.tipo === 'empresa'\) \? 'empresa' : 'persona'/.test(app));
afirma('un contrato guardado conserva los campos que su plantilla ya no pregunta',
  app.includes('CAMPOS_HEREDADOS'),
  'sin eso, abrir CR00018/CC00020/RP00046 borraría su cláusula de sociedad');

console.log(fallos ? '\n' + fallos + ' fallo(s)' : '\nPersona y empresa, cada una con su redacción.');
process.exit(fallos ? 1 : 0);
