/* node contracts/propios_emision.test.js
   Encargo «editor de textos de contrato» · E9 · EMITIR un contrato PROPIO de una empresa (8-oct-2026).

   Un contrato propio no está entre los 17 de CONTRACT_TIPO (que NO se tocan: los vigila listas.test.js): se compone en tiempo de ejecución desde la
   base (RPC plantilla_contratos_propios_activos) y su `contratos.tipo` es su slug. Este test ejecuta el código REAL de contracts/app.html (el bloque
   de los propios y `puedeEmitir`, extraídos por marcadores) y de contracts/assets/entidades_pago.js (applyPromotor) contra una base de mentira, y afirma:

     1. el tipo de un propio es su slug; los 17 siguen igual; lo desconocido no es nada;
     2. la lista sale de la RPC por empresa, una empresa que contesta 42501 no rompe a las demás, y un propio nunca pisa uno de los 17 ni una plantilla fija;
     3. el permiso (puedeEmitir) sigue siendo «el slug está en tipos_contrato» para un agente, y un admin pasa;
     4. LA SOCIEDAD: un propio firma con la de SU empresa y NUNCA cae en Tepi Sun Gai; si no se puede saber con certeza, NO se emite y se dice en llano;
     5. el proyecto tiene que ser de la empresa del contrato (la base lo rechaza si no; aquí se dice antes);
     6. abrir un propio guardado no cae en otra plantilla (se recompone) y un tipo con forma rara no se registra;
     7. el nombre viene de la base: nunca entra sin escapar en un innerHTML;
     8. los puntos de decisión de app.html usan tipoDeSlug/slugDeTipo y no el mapa fijo. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const leer = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8');
const app = leer('contracts', 'app.html');
const vocab = leer('contracts', 'assets', 'vocabulario.js');
const pago = leer('contracts', 'assets', 'entidades_pago.js');
let n = 0;
const ok = (c, msg) => { assert.ok(c, msg); n++; };
const eq = (a, b, msg) => { assert.deepStrictEqual(a, b, msg); n++; };

function entre(txt, ini, fin) {
  const a = txt.indexOf(ini); assert.ok(a >= 0, 'no encuentro el inicio: ' + ini);
  const b = txt.indexOf(fin, a); assert.ok(b > a, 'no encuentro el final: ' + fin);
  return txt.slice(a, b);
}
// el código real: puedeEmitir + estaArchivada + el bloque de propios, hasta plantillasOfrecidas incluida
const codigo = entre(app, 'function puedeEmitir(slug){', 'const TIPO_PREFIX = {');
const escFn = entre(app, 'function esc(v,k){', '\n');

function mundo(opc = {}) {
  const log = { rpc: [], from: [] };
  const empresas = opc.empresas || [
    { clave: 'lawang', nombre: 'Lawang', sociedad_clave: 'tepi_sungai' },
    { clave: 'sandal_woods', nombre: 'Sandal Woods', sociedad_clave: 'san_dal_woods' }];
  const propios = opc.propios || { lawang: [{ slug: 'lawang_contrato_de_obra', nombre: 'Contrato de obra' }], sandal_woods: 'NO' };
  const tablaPlantillas = opc.tablaPlantillas || {};
  const sb = {
    from(t) {
      log.from.push(t);
      const q = { _t: t, _f: {} };
      const api = {
        select() { return api; }, eq(k, v) { q._f[k] = v; return api; }, not() { return api; }, order() { return Promise.resolve({ data: t === 'empresas' ? empresas : [], error: null }); },
        maybeSingle() { return Promise.resolve({ data: tablaPlantillas[q._f.slug] || null, error: null }); },
        then(res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); },
      };
      return api;
    },
    rpc(nombre, args) {
      log.rpc.push([nombre, args]);
      const v = propios[args.p_empresa];
      if (v === 'NO') return Promise.resolve({ data: null, error: { code: '42501', message: 'No tienes acceso a los contratos de esa empresa' } });
      return Promise.resolve({ data: v || [], error: null });
    },
  };
  const ctx = {
    sb, log, console,
    TEMPLATES: [{ slug: 'carta_reserva', file: 'templates/carta_reserva.html', name: { es: 'Carta de Reserva' } },
                { slug: 'estatutos', file: 'templates/estatutos.html', name: { es: 'Estatutos' } }],
    CURRENT: null, MI_FICHA: opc.ficha || null, PLANTILLA_VER: opc.ver === undefined ? { empresa: 'lawang', hash: 'h' } : opc.ver,
    PROYECTOS_DB: opc.proyectos || [{ id: 'p1', nombre: 'Villa A', empresa: 'lawang' }, { id: 'p2', nombre: 'Villa B', empresa: 'sandal_woods' }],
    SOCIEDADES: opc.sociedades || { tepi_sungai: { razon: 'PT Tepi' }, san_dal_woods: { razon: 'PT San Dal' } },
    PLANTILLAS_PAGO: [], proyectoIdActual: () => opc.proyectoId || '', lwT: (s, h) => { let v = s; for (const k in h || {}) v = v.split('%' + k).join(h[k]); return v; },
  };
  vm.createContext(ctx);
  vm.runInContext(vocab.replace(/\bconst (CONTRACT_TIPO|TIPO_SLUG)\b/g, 'var $1'), ctx);
  vm.runInContext(codigo.replace(/\bconst (PROPIOS|esPropio|tipoDeSlug|slugDeTipo|plantillasOfrecidas)\b/g, 'var $1').replace(/\blet (EMPRESAS_CAT)\b/g, 'var $1'), ctx);
  vm.runInContext(escFn.replace('function esc', 'var esc = function'), ctx);
  return ctx;
}
const run = (ctx, expr) => vm.runInContext(expr, ctx);

(async () => {
  // ---- 1. el tipo
  let c = mundo();
  eq(run(c, "tipoDeSlug('ppjb_parcela')"), 'reserva_parcela', 'los 17 siguen por CONTRACT_TIPO');
  eq(run(c, "tipoDeSlug('lawang_contrato_de_obra')"), undefined, 'un propio no cargado todavía no es nada');
  eq(run(c, "tipoDeSlug('estatutos')"), undefined, 'Estatutos no se guarda ni numera: sigue sin tipo');
  await run(c, 'cargarPropios()');
  eq(run(c, "tipoDeSlug('lawang_contrato_de_obra')"), 'lawang_contrato_de_obra', 'un propio cargado: el tipo es SU slug');
  eq(run(c, "slugDeTipo('lawang_contrato_de_obra')"), 'lawang_contrato_de_obra');
  eq(run(c, "slugDeTipo('reserva_parcela')"), 'ppjb_parcela', 'los 17 por TIPO_SLUG');
  eq(run(c, "slugDeTipo('tipo_que_no_existe')"), undefined);
  eq(run(c, "Object.keys(CONTRACT_TIPO).length"), 17, 'CONTRACT_TIPO no se ha tocado: sigue con 17');
  eq(run(c, "Object.keys(CONTRACT_TIPO).includes('lawang_contrato_de_obra')"), false, 'y el propio NO se ha metido dentro');

  // ---- 2. la lista
  eq(c.log.rpc.map(r => r[0] + ':' + r[1].p_empresa), ['plantilla_contratos_propios_activos:lawang', 'plantilla_contratos_propios_activos:sandal_woods'], 'una llamada por empresa');
  const t = run(c, "TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')");
  ok(t && t.propio === true && t.file === null && t.empresa === 'lawang', 'entra en TEMPLATES sin fichero y con su empresa');
  eq(t.name.es, 'Contrato de obra');
  ok(/^#[0-9a-f]{6}$/i.test(t.cover), 'lleva color de portada (el diseño lo lee)');
  eq(run(c, "TEMPLATES.length"), 3, 'la empresa que contestó 42501 se saltó sin añadir ni romper nada');
  eq(run(c, "registraPropio('ppjb_parcela','x','lawang')"), null, 'un propio nunca pisa uno de los 17');
  eq(run(c, "registraPropio('estatutos','x','lawang')"), null, 'ni una plantilla fija del estudio');
  eq(run(c, "registraPropio('Con-Guion','x','lawang')"), null, 'ni un slug con forma rara');
  eq(run(c, "registraPropio('ab','x','lawang')"), null, 'ni uno demasiado corto');
  eq(run(c, "TEMPLATES.length"), 3);
  // sin empresas legibles: los 17 siguen, no se rompe nada
  c = mundo({ propios: { lawang: 'NO', sandal_woods: 'NO' } });
  await run(c, 'cargarPropios()');
  eq(run(c, "TEMPLATES.length"), 2, 'todas las empresas fuera de alcance: la lista de siempre');

  // ---- 3. el permiso
  c = mundo({ ficha: { rol: 'agente', tipos_contrato: ['reserva_parcela'] } });
  await run(c, 'cargarPropios()');
  eq(run(c, "puedeEmitir('lawang_contrato_de_obra')"), false, 'un agente sin el slug en tipos_contrato NO lo ofrece');
  eq(run(c, "plantillasOfrecidas().some(x => x.slug === 'lawang_contrato_de_obra')"), false);
  c = mundo({ ficha: { rol: 'agente', tipos_contrato: ['lawang_contrato_de_obra'] } });
  await run(c, 'cargarPropios()');
  eq(run(c, "puedeEmitir('lawang_contrato_de_obra')"), true, 'con el slug concedido, sí');
  eq(run(c, "puedeEmitir('ppjb_parcela')"), false, 'y sigue sin poder lo que no tiene');
  eq(run(c, "plantillasOfrecidas().map(x => x.slug)"), ['estatutos', 'lawang_contrato_de_obra'], 'el selector lo ofrece (Estatutos no tiene tipo y pasa siempre, como hoy)');
  c = mundo({ ficha: { rol: 'admin', tipos_contrato: [] } });
  await run(c, 'cargarPropios()');
  eq(run(c, "puedeEmitir('lawang_contrato_de_obra')"), true, 'un admin pasa (el control de verdad es el trigger)');

  // ---- 4. la sociedad
  c = mundo();
  await run(c, 'cargarPropios()');
  eq(run(c, "sociedadDePropio('lawang_contrato_de_obra')"), 'tepi_sungai', 'la sociedad sale de la empresa del contrato');
  run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'carta_reserva')");
  eq(run(c, 'sociedadPropiaDe()'), null, 'un contrato de los de siempre: la regla de siempre (null = no aplica)');
  run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')");
  eq(run(c, 'sociedadPropiaDe()'), 'tepi_sungai');
  // empresa SIN sociedad asignada, o con una que el catálogo no tiene: ''  (= no se sabe)
  c = mundo({ empresas: [{ clave: 'lawang', nombre: 'Lawang', sociedad_clave: null }] });
  await run(c, 'cargarPropios()'); run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')");
  eq(run(c, 'sociedadPropiaDe()'), '', 'sin sociedad en la empresa NO se cae a Tepi Sun Gai: se dice que no se sabe');
  c = mundo({ empresas: [{ clave: 'lawang', nombre: 'Lawang', sociedad_clave: 'sociedad_que_no_esta' }] });
  await run(c, 'cargarPropios()'); run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')");
  eq(run(c, 'sociedadPropiaDe()'), '', 'una sociedad que no está en el catálogo tampoco');
  // y lo que imprime el documento: applyPromotor
  const aplica = entre(pago, 'function applyPromotor(data){', '/* etiqueta legible del régimen');
  function promotor(ctx, data) {
    ctx.FIRMANTES_CRED = {}; ctx.SOCIEDAD_DEFAULT = { ppjb_reserva: 'san_dal_woods' };
    ctx.SOCIEDADES = { tepi_sungai: { razon: 'TEPI', domicilio: 'd', npwp: '1', rep: 'r' }, san_dal_woods: { razon: 'SANDAL', domicilio: 'd', npwp: '2', rep: 'r' } };
    vm.runInContext(aplica.replace('function applyPromotor', 'var applyPromotor = function'), ctx);
    ctx.__d = data; vm.runInContext('applyPromotor(__d)', ctx); return ctx.__d;
  }
  c = mundo({ empresas: [{ clave: 'lawang', nombre: 'Lawang', sociedad_clave: 'san_dal_woods' }] });
  await run(c, 'cargarPropios()'); run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')");
  eq(promotor(c, { sociedad_firmante: 'tepi_sungai' }).prom_razon, 'SANDAL', 'un propio imprime la sociedad de su empresa AUNQUE el dato diga otra');
  eq(promotor(c, {}).prom_razon, 'SANDAL', 'y sin dato, la de su empresa; nunca Tepi Sun Gai');
  c = mundo({ empresas: [{ clave: 'lawang', nombre: 'Lawang', sociedad_clave: null }] });
  await run(c, 'cargarPropios()'); run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')");
  c.templateHTML = '<p>{{prom_razon}}</p>';
  assert.throws(() => promotor(c, {}), /qué sociedad firma/, 'sin sociedad cierta el documento que imprime al promotor NO sale con la identidad de otro'); n++;
  c.templateHTML = '<p>Elige el proyecto</p>';
  eq(promotor(c, {}).prom_razon, undefined, 'pero un texto que no imprime al promotor (el aviso previo al proyecto) no revienta la vista');
  c = mundo();
  run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'carta_reserva')");
  eq(promotor(c, {}).prom_razon, 'TEPI', 'los 17 siguen con su default de siempre');
  eq(promotor(c, { sociedad_firmante: 'san_dal_woods' }).prom_razon, 'SANDAL');

  // ---- 5. el proyecto y el motivo en llano
  const motivo = async (opc) => { const w = mundo(opc); await run(w, 'cargarPropios()'); run(w, "CURRENT = TEMPLATES.find(x => x.slug === 'lawang_contrato_de_obra')"); return run(w, 'motivoPropioNoEmite()'); };
  eq(await motivo({ proyectoId: 'p1' }), '', 'proyecto de su empresa + texto leído + sociedad conocida: se puede emitir');
  ok(/elige el proyecto/.test(await motivo({ proyectoId: '' })), 'sin proyecto lo dice en llano');
  const otra = await motivo({ proyectoId: 'p2' });
  ok(/no es de Lawang/.test(otra), 'un proyecto de otra empresa: se dice antes de que la base rechace (23514). Fue: ' + otra);
  ok(/no se ha podido leer/.test(await motivo({ proyectoId: 'p1', ver: null })), 'sin texto de la base no se emite (no hay fichero de respaldo)');
  ok(/qué sociedad firma/.test(await motivo({ proyectoId: 'p1', empresas: [{ clave: 'lawang', nombre: 'Lawang', sociedad_clave: null }] })), 'sin sociedad cierta no se emite y dice por qué');
  c = mundo(); run(c, "CURRENT = TEMPLATES.find(x => x.slug === 'carta_reserva')");
  eq(run(c, 'motivoPropioNoEmite()'), '', 'un contrato de los 17 no pasa por estas reglas');

  // ---- 6. abrir uno guardado
  c = mundo({ propios: { lawang: [] }, tablaPlantillas: { lawang_contrato_viejo: { slug: 'lawang_contrato_viejo', nombre: 'Contrato viejo', empresa: 'lawang' } } });
  eq(await run(c, "slugDeTipoGuardado('reserva_parcela')"), 'ppjb_parcela', 'un tipo de los 17 por TIPO_SLUG, sin tocar la base');
  eq(await run(c, "slugDeTipoGuardado('lawang_contrato_viejo')"), 'lawang_contrato_viejo', 'un propio que hoy no se ofrece (archivado) se recompone para reabrirlo');
  eq(run(c, "TEMPLATES.find(x => x.slug === 'lawang_contrato_viejo').name.es"), 'Contrato viejo');
  eq(await run(c, "slugDeTipoGuardado('Tipo Raro!')"), undefined, 'una forma que no es de slug se rechaza');
  eq(await run(c, "slugDeTipoGuardado('contrato_que_no_existe')"), undefined, 'sin fila de plantilla NO se inventa un propio fantasma (sin empresa ni sociedad): tipo desconocido');
  eq(run(c, "TEMPLATES.some(x => x.slug === 'contrato_que_no_existe')"), false);

  // ---- 7. el nombre viene de la base: escapado
  const sucio = '<img src=x onerror=alert(1)>"&';
  c = mundo({ propios: { lawang: [{ slug: 'lawang_malo', nombre: sucio }] } });
  await run(c, 'cargarPropios()');
  const salida = run(c, "esc(L_(TEMPLATES.find(x => x.slug === 'lawang_malo').name))".replace('L_', '(n => n.es)'));
  ok(!/[<>"]/.test(salida.replace(/&quot;/g, '')) && salida.includes('&lt;img'), 'esc() neutraliza el nombre: ' + salida);
  ok(!/\$\{L\(t\.name\)\}/.test(app), 'ningún innerHTML de app.html mete ${L(t.name)} sin escapar');
  ok(/\$\{esc\(L\(t\.name\)\)\}/.test(app), 'el selector de plantilla escapa el nombre');
  ok(/\$\{esc\(L\(CURRENT\.name\)\)\}/.test(leer('contracts', 'assets', 'documento_diseno.js')), 'el panel de diseño escapa el nombre');

  // ---- 8. los puntos de decisión usan los helpers
  ok(/await Promise\.all\(EMPRESAS_CAT\.map\(async e =>/.test(app), 'las empresas se consultan en paralelo');
  ok(/tipo: tipoDeSlug\(CURRENT\.slug\)/.test(app), 'el payload guarda el tipo con tipoDeSlug');
  ok(/const slug = await slugDeTipoGuardado\(data\.tipo\)/.test(app), 'abrir un guardado recompone el propio');
  ok(!/tipo: CONTRACT_TIPO\[CURRENT\.slug\]/.test(app), 'el payload ya no usa el mapa fijo');
  ok(!/const tipo = CONTRACT_TIPO\[CURRENT\.slug\];/.test(app), 'ningún punto de decisión (tipo) usa el mapa fijo a secas');
  ok(/plantillasOfrecidas\(\)\.find\(t => tipoDeSlug\(t\.slug\)\)/.test(app) && /some\(t => tipoDeSlug\(t\.slug\)\)/.test(app), 'el arranque busca tipos con tipoDeSlug');
  ok(/const motivoPropio = motivoPropioNoEmite\(\)/.test(app), 'guardarContrato consulta si un propio puede emitirse');
  ok(/if\(socPropia\) data\.sociedad_firmante = socPropia/.test(app), 'el contrato propio se guarda con su sociedad escrita');
  ok(/&& !CURRENT\.propio\)\{\s*const campo = \['sociedad_firmante'/.test(app), 'un propio no ofrece elegir otra sociedad');
  ok(/if\(t\.propio\) return \{ html:/.test(app), 'un propio sin texto de la base no cae a un fichero inexistente');
  ok(!/propio[^\n]*fetch\(t\.file/.test(app), 'y nunca hace fetch de un fichero');
  // el selector de proyecto de un propio existe aunque su texto no lleve {{proyecto_nombre}} (deriveSections lo fuerza) y se filtra por su empresa
  // LAW-36 (11-oct-2026): preguntarlo y cargar la lista salen de UNA función; escrita dos veces, 13 de 21 plantillas lo preguntaban sin lista
  ok(/function preguntaProyecto\(\)\{\s*return !!CURRENT && CURRENT\.slug !== 'poa_notario';/.test(app), 'el campo proyecto se pregunta en toda plantilla salvo el Poder (una sola condición)');
  ok(/if\(preguntaProyecto\(\)\)\{\s*inDoc\.add\('proyecto_nombre'\)/.test(app), 'deriveSections fuerza el campo con esa condición');
  ok(/includes\('\{\{proyecto_nombre\}\}'\) \|\| preguntaProyecto\(\)\) await cargarProyectos\(\)/.test(app), 'y loadTemplate carga los proyectos con la misma (un propio nunca es el Poder: carga aunque su texto no lleve el marcador)');
  ok(!/CURRENT\.slug !== 'poa_notario'\)\{\s*inDoc\.add\('proyecto_nombre'\)/.test(app), 'la condición no vuelve a escribirse suelta en deriveSections');
  ok(/CURRENT\.propio \? deMiAlcance\.filter\(p => p\.empresa === CURRENT\.empresa/.test(app), 'y el desplegable solo ofrece proyectos de su empresa');

  console.log('OK propios_emision.test.js — ' + n + ' comprobaciones');
})().catch(e => { console.error(e); process.exit(1); });
