/* node contracts/revision_texto.test.js
   Selector «Revisión del texto» (E10) de contracts/app.html: ejecuta el código REAL (fijaVersionPlantilla, cambioDeProyectoYTexto, ocultaRevisiones,
   cargaRevisiones y cambioDeRevision, extraídos por marcadores) contra una página y una base de mentira. Fija los fallos de la revisión del 8-oct-2026:
     1. cambiar de revisión restaura el proyecto Y dispara `change` (resort, cuentas y ubicación se reponen en ese evento);
     2. con una revisión elegida, cambiar a otro proyecto de la MISMA empresa no avisa de «otra empresa», no borra el borrador y conserva la revisión;
        un proyecto de OTRA empresa sí avisa y rehace;
     3. el aviso de «elige cuál» no manda a un selector que acaba de ocultarse;
     4. el Sí/No de un campo propio sale en el idioma del bloque aunque el bloque bilingüe no sea <p> ni <li> (ese caso lo prueba campos_propios_insercion.test.js). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8').replace(/\r\n/g, '\n');
const a = app.indexOf('async function fijaVersionPlantilla(');
const b = app.indexOf('async function loadTemplate(');
assert.ok(a > 0 && b > a, 'no encuentro el bloque del selector de revisión en app.html');
const codigo = app.slice(a, b);
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

function mundo(o = {}) {
  const w = { toasts: [], confirms: [], resets: 0, loads: [], builds: 0, eventos: [], rpcs: [], cuerposPedidos: [] };
  const proy = { value: o.proyecto || 'Alfa', dataset: {}, dispatchEvent(e) { w.eventos.push(e.type); if (w.alDisparar) return w.alDisparar(); } };
  const sel = { hidden: false, innerHTML: '', value: '', dataset: {}, };
  const doc = { getElementById: (id) => id === 'revPick' ? sel : null, querySelector: (q) => q === '[name="proyecto_nombre"]' ? proy : null };
  const empresaDe = o.empresaDe || { Alfa: 'E1', Beta: 'E1', Gamma: 'E2' };
  const params = ['w', 'sel', 'proy', 'doc', 'empresaDe', 'o'];
  const cuerpo = `
    const esc = (s) => String(s); const lwT = (s) => s; const window = { confirm: (m) => { w.confirms.push(m); return o.confirma !== false; } };
    const document = doc; function Event(t){ this.type = t; }
    let SAVED_CONTRACT = null, CURRENT = { slug: 'tipo_x' }, REVISION_ELEGIDA = o.revision || '', REVISION_SLUG = 'tipo_x';
    let PLANTILLA_VER = o.ver === undefined ? { empresa: 'E1', hash: 'h-rev', version_id: 'V2' } : o.ver, PLANTILLA_FIJADA = false, PLANTILLA_TOCADO = !!o.tocado;
    let templateHTML = o.html || '<rev>';
    const sb = { rpc: async (n, args) => { w.rpcs.push([n, args]); return o.rpcRes ? o.rpcRes(n, args) : { data: [], error: null }; } };
    const proyectoIdActual = () => 'pid-' + proy.value;
    const textoPlantillaBase = async (slug, c, pid, ver) => { w.cuerposPedidos.push([pid, ver]); return o.base ? o.base(pid, ver) : null; };
    const textoPlantilla = async (t, op) => o.texto(op);
    const resetBorrador = () => { w.resets++; REVISION_ELEGIDA = ''; };
    const loadTemplate = async (slug, op) => { w.loads.push(op); templateHTML = '<recargado>'; };
    const buildForm = () => { w.builds++; }; const updateSaveButton = () => {}; const editBtnIdle = () => {};
    const confirmaSoltarPendientes = () => true;
    ${codigo}
    return { fijaVersionPlantilla, cambioDeProyectoYTexto, cambioDeRevision, ocultaRevisiones,
      get REVISION() { return REVISION_ELEGIDA; }, set REVISION(v) { REVISION_ELEGIDA = v; }, get HTML() { return templateHTML; }, setSaved(x) { SAVED_CONTRACT = x; },
      get VER() { return PLANTILLA_VER; }, setVer(v) { PLANTILLA_VER = v; } };`;
  const m = new Function(...params, cuerpo)(w, sel, proy, doc, empresaDe, o);
  return { w, sel, proy, m };
}

(async () => {
  /* ── 1. cambioDeRevision restaura el proyecto Y dispara change ── */
  {
    const { w, sel, proy, m } = mundo({ revision: '', texto: async () => ({ html: '<x>', ver: null }) });
    sel.value = 'V2'; sel.dataset.previo = '';
    await m.cambioDeRevision(sel);
    ok(w.loads.length === 1, '1: cambiar de revisión rehizo el texto');
    ok(m.REVISION === 'V2', '1: la revisión elegida queda puesta');
    ok(proy.value === 'Alfa', '1: el proyecto se restaura');
    ok(w.eventos.includes('change'), '1: tras restaurar el proyecto se dispara `change` (resort/cuentas/ubicación se reponen en ese evento): ' + JSON.stringify(w.eventos));
  }
  /* ── 2. el change disparado por cambioDeRevision NO debe hacer saltar el aviso de otra empresa ni soltar la revisión ── */
  {
    const base = (pid, ver) => ({ html: ver ? '<rev>' : '<std>', ver: { empresa: 'E1', hash: ver ? 'h-rev' : 'h-std', version_id: ver || 'V1' } });
    const texto = async (op) => base(op.proyectoId, op.version);
    // 2a. revisión elegida + mismo proyecto/empresa (el change que dispara cambioDeRevision): nada que preguntar
    let mu = mundo({ revision: 'V2', tocado: true, html: '<rev>', texto });
    mu.sel.value = 'V2'; mu.proy.dataset.previo = 'Alfa';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 0, '2a: ningún aviso de «otra empresa» con el proyecto de la misma empresa: ' + JSON.stringify(mu.w.confirms));
    ok(mu.w.resets === 0 && mu.w.loads.length === 0, '2a: no se borra el borrador ni se recarga el texto');
    ok(mu.m.REVISION === 'V2' && mu.m.VER.hash === 'h-rev', '2a: la revisión elegida y su versión se conservan');
    // 2b. revisión elegida + OTRO proyecto de la MISMA empresa: tampoco hay nada que decir
    mu = mundo({ revision: 'V2', tocado: true, html: '<rev>', texto });
    mu.proy.dataset.previo = 'Alfa'; mu.proy.value = 'Beta';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 0 && mu.w.resets === 0, '2b: otro proyecto de la misma empresa no avisa ni borra');
    ok(mu.m.REVISION === 'V2' && mu.proy.dataset.previo === 'Beta', '2b: conserva la revisión y anota el proyecto');
    // 2c. un proyecto de OTRA empresa sí avisa (y rehace si se acepta)
    const texto2 = async (op) => op.proyectoId === 'pid-Gamma' ? { html: '<otra>', ver: { empresa: 'E2', hash: 'h-e2', version_id: 'W1' } } : base(op.proyectoId, op.version);
    mu = mundo({ revision: 'V2', tocado: true, html: '<rev>', texto: texto2 });
    mu.proy.dataset.previo = 'Alfa'; mu.proy.value = 'Gamma';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 1 && mu.w.resets === 1 && mu.w.loads.length === 1, '2c: otra empresa → pregunta una vez, y al aceptar rehace');
    mu = mundo({ revision: 'V2', tocado: true, html: '<rev>', texto: texto2, confirma: false });
    mu.proy.dataset.previo = 'Alfa'; mu.proy.value = 'Gamma';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.proy.value === 'Alfa' && mu.m.REVISION === 'V2' && mu.w.resets === 0, '2c: al decir que no, vuelve el proyecto y se conserva la revisión');
    // 2d. sin revisión y mismo texto: el camino de siempre
    mu = mundo({ revision: '', html: '<std>', ver: { empresa: 'E1', hash: 'h-std', version_id: 'V1' }, texto });
    mu.proy.dataset.previo = 'Alfa'; mu.proy.value = 'Beta';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 0 && mu.w.resets === 0 && mu.proy.dataset.previo === 'Beta', '2d: sin revisión y mismo texto, solo se anota el proyecto');
    // 2e. flujo completo: cambioDeRevision dispara change y ese change vuelve a entrar en cambioDeProyectoYTexto
    mu = mundo({ revision: '', tocado: false, html: '<std>', ver: { empresa: 'E1', hash: 'h-std', version_id: 'V1' }, texto });
    mu.w.alDisparar = () => mu.m.cambioDeProyectoYTexto(mu.proy);
    // loadTemplate de mentira deja el texto de la revisión y su versión
    mu.sel.value = 'V2'; mu.sel.dataset.previo = '';
    const loadReal = mu.w.loads;
    await mu.m.cambioDeRevision(mu.sel);
    await new Promise((r) => setImmediate(r));
    ok(mu.m.REVISION === 'V2', '2e: tras cambiar de revisión (con el change reentrando) la elegida no se pierde');
    ok(mu.w.confirms.length === 0, '2e: sin avisos falsos en el flujo completo');
  }
  /* ── 3. el aviso de «elige cuál» no manda a un selector oculto ── */
  {
    const { w, sel, m } = mundo({ revision: '', html: '<std>', ver: { empresa: 'E1', hash: 'h-std', version_id: null },
      base: () => ({ html: '<std>', ver: { empresa: 'E1', hash: 'h-std', version_id: null } }),
      rpcRes: async (nom) => nom === 'plantilla_contrato_fija' ? { data: null, error: { message: 'Esta plantilla tiene varias revisiones activas: elige cual usa el contrato' } } : { data: [], error: null } });
    sel.hidden = false;
    const aviso = await m.fijaVersionPlantilla('c1', true);
    ok(/OJO/.test(aviso), '3: el error se avisa');
    ok(!(sel.hidden && /Revisión del texto/.test(aviso)), '3: el aviso no remite a «Revisión del texto» con el selector oculto: «' + aviso + '» (oculto=' + sel.hidden + ')');
    // sin error: el selector se oculta (ya guardado, el texto no se cambia desde aquí)
    const ok2 = mundo({ revision: '', html: '<std>', ver: { empresa: 'E1', hash: 'h-std', version_id: 'V1' }, base: () => ({ html: '<std>', ver: { empresa: 'E1', hash: 'h-std', version_id: 'V1' } }) });
    ok2.sel.hidden = false;
    const av2 = await ok2.m.fijaVersionPlantilla('c1', true);
    ok(av2 === '' && ok2.sel.hidden === true, '3: guardado sin error, el selector se oculta');
  }
  /* ── 4. (14-oct-2026) el fichero publicado va sin notas de autor y la semilla de la base las lleva: el mismo texto no es «otra empresa» ── */
  {
    // 4a. la expresión del navegador es la de `_plantilla_sin_notas` (la base), leída de la migración: si una cambia, esto falla
    const mig = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261009010000_f2_plantillas_s7_1_pantalla.sql'), 'utf8');
    const reSql = /regexp_replace\(p_cuerpo,\s*'(<!--\(\?!.*?\)\.\*\?-->)'/s.exec(mig);
    const reJs = /const RE_NOTAS_AUTOR = \/(.*)\/g;/.exec(codigo);
    ok(reSql && reJs, '4a: encuentro las dos expresiones (SQL y app.html)');
    ok(reJs[1].replace(/\\\//g, '/') === reSql[1].replace('.*?-->', '[\\s\\S]*?-->'), '4a: RE_NOTAS_AUTOR es la misma expresión que _plantilla_sin_notas');
    const fichero = '<p>Texto</p><!--if:x-->a<!--/if:x--><!--opt:y-->b<!--/opt:y-->';
    const semilla = '<p>Texto</p><!-- NOTA de autor:\n varias lineas --><!--if:x-->a<!--/if:x--><!--opt:y-->b<!--/opt:y-->';
    // 4b. texto base en pantalla (sin versión), el proyecto trae la semilla = fichero + notas: ni aviso ni borrado
    let mu = mundo({ revision: '', tocado: true, html: fichero, ver: null, texto: async () => ({ html: semilla, ver: { empresa: 'E1', hash: 'h-sem', version_id: 'S1' } }) });
    mu.proy.dataset.previo = ''; mu.proy.value = 'Alfa';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 0 && mu.w.resets === 0, '4b: la semilla con notas no avisa de otra empresa: ' + JSON.stringify(mu.w.confirms));
    ok(mu.m.VER && mu.m.VER.version_id === 'S1', '4b: se anota de qué versión sale el texto');
    // 4c. si el texto difiere de verdad y en pantalla estaba el texto base, avisa, pero sin decir «otra empresa»
    mu = mundo({ revision: '', tocado: true, html: fichero, ver: null, texto: async () => ({ html: '<p>Otro</p>', ver: { empresa: 'E1', hash: 'h-o', version_id: 'S2' } }) });
    mu.proy.dataset.previo = ''; mu.proy.value = 'Alfa';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 1 && !/otra empresa/.test(mu.w.confirms[0]), '4c: texto distinto desde el texto base → un aviso, sin «otra empresa»: ' + JSON.stringify(mu.w.confirms));
    // 4d. con la empresa cambiando de verdad, el aviso sí dice «otra empresa» (2c lo cubre con revisión; aquí sin ella)
    mu = mundo({ revision: '', tocado: true, html: '<a>', ver: { empresa: 'E1', hash: 'h1', version_id: 'V1' }, texto: async () => ({ html: '<b>', ver: { empresa: 'E2', hash: 'h2', version_id: 'W1' } }) });
    mu.proy.dataset.previo = 'Alfa'; mu.proy.value = 'Gamma';
    await mu.m.cambioDeProyectoYTexto(mu.proy);
    ok(mu.w.confirms.length === 1 && /otra empresa/.test(mu.w.confirms[0]), '4d: empresa distinta → aviso de «otra empresa»');
    // 4e. al guardar sin versión en pantalla, la semilla con notas se fija (antes salía «se guardó SIN fijar la versión»)
    mu = mundo({ revision: '', html: fichero, ver: null, base: () => ({ html: semilla, ver: { empresa: 'E1', hash: 'h-sem', version_id: 'S1' } }) });
    const av = await mu.m.fijaVersionPlantilla('c1', true);
    ok(av === '' && mu.w.rpcs.some(([nom, ar]) => nom === 'plantilla_contrato_fija' && ar.p_version === 'S1'), '4e: se fija la semilla: «' + av + '»');
  }
  console.log('revision_texto.test.js: OK (' + n + ' comprobaciones)');
})().catch((e) => { console.error('FALLA:', e.message); process.exit(1); });
