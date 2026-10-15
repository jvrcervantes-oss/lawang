/* ═══════════════════════════════════════════════════════════════════════════
   EL HAK SEWA CUELGA DE SU VENTA — 13-oct-2026
   `node hak_sewa_vinculo.test.js`. Lo corre `tools/test.py`, y con él el gate.
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE. Orden del owner (13-oct-2026): «El contrato de 'Hak Sewa -
   Notario' sigue después de un contrato de construcción, no venta nueva.
   1 Reserva o Bloqueo · 2 Contrato de construcción · 3 Hak Sewa y 4 poder
   notarial». Hasta hoy el asistente lo ofrecía como venta nueva y TODOS los
   Hak Sewa se guardaban como venta raíz (sin contrato_padre_id).

   CÓMO SE ENLAZA. Sin tocar SQL: el Hak Sewa lleva un campo de gestión no
   impreso con la clave `num_reserva_vinculada`, que `contrato_guarda` ya
   resuelve a contrato_padre_id contra un `reserva_parcela`. Cuelga de la RAÍZ
   (el Bloqueo) aunque se haga desde su Construcción: nada de nietos.

   Esto afirma, ejecutando el código real donde se puede:
     1. Asistente: el Hak Sewa ya no es venta nueva; en «Seguir una venta» sale
        desde un Bloqueo (Le toca si tiene obra; sin obra se puede igual), desde
        una Construcción con Bloqueo (Le toca) y apagado CON motivo si la obra
        no tiene Bloqueo, si no se pudo mirar o si aún se está mirando. Nunca se
        apaga por tener ya uno (tres de 30 años es lo normal).
     2. montaExistente pone en el campo el número del BLOQUEO (también desde la
        Construcción) y no monta nada si no lo sabe.
     3. Editor: el campo se inyecta solo en el Hak Sewa, es opcional SOLO ahí
        (en la Construcción sigue obligatorio), la lista se carga y se refresca,
        y lo que lee la clave pensando en la obra sigue acotado a Construcción.
     4. Servidor: la definición vigente de contrato_guarda enlaza por esa clave
        a un reserva_parcela sin mirar el tipo del contrato que se guarda.
     5. Operaciones: un nieto (Poder → Hak Sewa → Bloqueo) cuelga de la raíz y
        no desaparece de la lista; y lo que ACOMPAÑA a la venta (Hak Sewa,
        Poder, Adenda) no decide su etapa ni pinta «Falta precio».
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

let n = 0;
const ok = (msg, cond) => { assert(cond, msg); n++; };
const lee = rel => fs.readFileSync(path.join(__dirname, rel), 'utf8');
const trozo = (src, desde, hasta, quien) => {
  const i = src.indexOf(desde), j = src.indexOf(hasta, i + 1);
  assert(i >= 0 && j > i, quien + ': no encuentro «' + desde + '» … «' + hasta + '»');
  return src.slice(i, j);
};

const asi = lee('assets/asistente-contrato.js');
const app = lee('app.html');
const inv = lee('assets/parcela_inventario.js');
const opsSrc = lee('assets/operaciones-cuentas.js');

const CONTRACT_TIPO = { ppjb_parcela: 'reserva_parcela', ppjb_construccion: 'construccion', hak_sewa_notario: 'hak_sewa_notario',
  poa_notario: 'poa', adenda: 'adenda', carta_reserva: 'carta_reserva' };
const TIPO_SLUG = Object.fromEntries(Object.entries(CONTRACT_TIPO).map(([s, t]) => [t, s]));

async function main() {
/* ── 1 · el asistente ─────────────────────────────────────────────────────── */
{
  const m = asi.match(/var SIGUE_A_VENTA = (\[[^\]]*\]);/);
  ok('asistente: SIGUE_A_VENTA no se encuentra', !!m);
  const sigue = JSON.parse(m[1].replace(/'/g, '"'));
  ok('el Hak Sewa sigue a una venta (no sale como venta nueva)', sigue.includes('hak_sewa_notario'));
  ok('Construcción, Poder y Adenda siguen donde estaban', ['construccion', 'poa', 'adenda'].every(t => sigue.includes(t)));
  ok('el texto de «venta nueva» ya no nombra el Hak Sewa', !/'Carta de Reserva, Bloqueo de Parcela directo, Hak Sewa/.test(asi));
  ok('el texto de «seguir una venta» sí lo nombra', asi.includes("T('Construcción de un Bloqueo, Hak Sewa tras la Construcción, pasar una Carta a Bloqueo, Poder Notarial o Adenda.')"));
  // Desde el 15-oct-2026 (busqueda sin tildes) buscaVentas pide las ventas al servidor con contratos_busca: el padre lo
  // tiene que devolver ESA funcion (su `returns table` en la migracion vigente que la define), no un .select de la pantalla.
  const defsBusca = fs.readdirSync(path.join(__dirname, '..', 'supabase', 'migrations')).sort()
    .filter(f => /create or replace function public\.contratos_busca\(/i.test(fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', f), 'utf8')));
  const sqlBusca = defsBusca.length ? fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', defsBusca[defsBusca.length - 1]), 'utf8') : '';
  const retBusca = (sqlBusca.match(/function public\.contratos_busca\([\s\S]*?returns table\(([\s\S]*?)\)\s*\n/i) || [])[1] || '';
  ok('buscaVentas trae el padre de cada venta',
     (/buscaVentas[\s\S]{0,400}\.select\('[^']*contrato_padre_id/.test(asi))
     || (/buscaVentas[\s\S]{0,600}sb\.rpc\('contratos_busca'/.test(asi) && /\bcontrato_padre_id\s+uuid\b/.test(retBusca)));

  const codigo = trozo(asi, '  function opcionesExistente()', '  /* ── pintar', 'asistente');
  const ctx = {
    S: null, RT: {}, T: x => x, CONTRACT_TIPO, TEMPLATES: [],
    lwEsPreliminar: t => /^carta_reserva/.test(String(t || '')),
    tipoDe: s => (s ? CONTRACT_TIPO[s] : null), slugDeTipo: t => TIPO_SLUG[t], nombre: s => 'N:' + s,
    permitidas: null, ofrecida: s => !ctx.permitidas || ctx.permitidas.includes(s)
  };
  vm.createContext(ctx);
  vm.runInContext(codigo + '\nthis.opcionesExistente = opcionesExistente; this.bloqueoDelHakSewa = bloqueoDelHakSewa;', ctx);
  const hsDe = (venta, rt) => { ctx.S = { venta }; ctx.RT = rt || {}; return ctx.opcionesExistente().find(o => o.slug === 'hak_sewa_notario'); };

  const rp = { id: 'rp1', numero: 'RP00001', tipo: 'reserva_parcela', parcela_codigo: 'A1, A2', bloqueado: true };
  let o = hsDe(rp, { construcciones: 0 });
  ok('Bloqueo sin obra: se ofrece el Hak Sewa, encendido y sin «Le toca»', o && !o.off && !o.toca);
  o = hsDe(rp, { construcciones: 1 });
  ok('Bloqueo con obra: «Le toca»', o && !o.off && o.toca);
  o = hsDe(rp, { construcciones: 'fallo' });
  ok('Bloqueo sin poder contar la obra: se ofrece igual, sin «Le toca»', o && !o.off && !o.toca);
  ctx.S = { venta: rp }; ctx.RT = { construcciones: 2 };
  const lista = ctx.opcionesExistente();
  const prim = lista.find(x => x.toca && !x.off);
  ok('Bloqueo con una obra por parcela: lo primero que toca es el Hak Sewa', prim && prim.slug === 'hak_sewa_notario');
  ok('…y va detrás de la Construcción y delante del Poder',
    lista.map(x => x.slug).join(',') === 'ppjb_construccion,hak_sewa_notario,poa_notario,adenda');
  ok('desde el Bloqueo, cuelga del propio Bloqueo', ctx.bloqueoDelHakSewa().numero === 'RP00001');

  const cc = { id: 'cc1', numero: 'CC00001', tipo: 'construccion', contrato_padre_id: 'rp1' };
  o = hsDe(cc, { padre: { id: 'rp1', numero: 'RP00001', tipo: 'reserva_parcela' } });
  ok('Construcción con Bloqueo: «Le toca»', o && !o.off && o.toca);
  ok('…y cuelga del BLOQUEO, no de la obra', ctx.bloqueoDelHakSewa().numero === 'RP00001');
  o = hsDe(cc, {});
  ok('Construcción mientras se lee su Bloqueo: apagado con motivo', o && /Comprobando/.test(o.off || ''));
  o = hsDe(cc, { padre: { id: 'rp1', fallo: true } });
  ok('Construcción sin poder leer su Bloqueo: apagado diciendo que no se pudo (no «no tiene»)', o && /No se ha podido/.test(o.off || ''));
  o = hsDe(cc, { padre: { id: 'rp1', invisible: true } });
  ok('Bloqueo que quien pregunta no ve: apagado con motivo (el servidor no lo enlazaría)', o && /no está entre los contratos que ves/.test(o.off || ''));
  o = hsDe(cc, { padre: { id: 'rp1', numero: 'CR00009', tipo: 'carta_reserva' } });
  ok('Construcción colgada de algo que no es un Bloqueo: apagado nombrándolo', o && /CR00009/.test(o.off || ''));
  o = hsDe({ ...cc, contrato_padre_id: null }, {});
  ok('Construcción sin Bloqueo: apagado con motivo', o && /no está enlazada/.test(o.off || ''));
  o = hsDe({ ...cc, contrato_padre_id: undefined }, {});
  ok('estado guardado antes de hoy (sin padre): «comprobando», no «sin Bloqueo»', o && /Comprobando/.test(o.off || ''));
  o = hsDe({ ...cc, contrato_padre_id: undefined }, { padre: { invisible: true } });
  ok('…y si esa Construcción ya no se ve, lo dice (no «recarga la página» para siempre)', o && /ya no está entre los contratos que ves/.test(o.off || ''));

  // «Venta nueva»: el paso «tipo» NO deja avanzar con el Hak Sewa (se ejecuta el listo() real); el Bloqueo sí
  {
    const listoSrc = trozo(asi, '  function listo(k) {', '  function opcionesExistente()', 'asistente');
    const c8 = Object.assign({}, ctx, { SIGUE_A_VENTA: sigue });
    vm.createContext(c8);
    vm.runInContext(listoSrc + '\nthis.listo = listo; this.opcionesExistente = function () { return []; };', c8);
    c8.S = { camino: 'nueva', slug: 'hak_sewa_notario' };
    ok('venta nueva: el Hak Sewa no pasa el paso «tipo»', c8.listo('tipo') === false);
    c8.S = { camino: 'nueva', slug: 'ppjb_parcela' };
    ok('venta nueva: el Bloqueo de Parcela sí lo pasa', c8.listo('tipo') === true);
  }

  ok('desde una Carta no se ofrece (antes pasa a Bloqueo)', !hsDe({ id: 'c', numero: 'CR1', tipo: 'carta_reserva' }, {}));
  ok('desde un Poder no se ofrece', !hsDe({ id: 'p', numero: 'PA1', tipo: 'poa' }, {}));
  ctx.permitidas = ['poa_notario'];
  o = hsDe(rp, { construcciones: 1 });
  ok('sin permiso para el Hak Sewa: apagado «No lo tienes permitido.»', o && o.off === 'No lo tienes permitido.');
  ctx.permitidas = null;

  /* ── 2 · montaExistente ──────────────────────────────────────────────── */
  const monta = trozo(asi, '  async function montaExistente()', '  async function monta()', 'asistente');
  const corre = async (venta, rt, opts) => {
    opts = opts || {};
    const reg = { abierto: null, derivado: null, puesto: {}, malos: [] };
    const campo = opts.sinCampo ? null : { value: '' };
    const c2 = Object.assign({}, ctx, {
      S: { venta, slug: 'hak_sewa_notario' }, RT: rt, SAVED_CONTRACT: null,
      VINCULABLES: opts.vinculables || [{ numero: 'RP00001' }], VINCULABLES_POA: [],
      openSavedContract: async id => { reg.abierto = id; c2.SAVED_CONTRACT = { id }; },
      derivarContrato: async s => { reg.derivado = s; },
      populateForm: f => { Object.assign(reg.puesto, f); if (campo && f.num_reserva_vinculada) campo.value = f.num_reserva_vinculada; },
      document: { querySelector: q => (q === '[name="num_reserva_vinculada"]' ? campo : null) },
      avisaMal: m => reg.malos.push(m), avisa: () => {}, aplicarReglasCampos: () => {}, montaCondiciones: async () => {}
    });
    vm.createContext(c2);
    vm.runInContext(codigo + '\n' + monta + '\nthis.montaExistente = montaExistente;', c2);
    reg.ok = await c2.montaExistente();
    return reg;
  };
  {
    let r = await corre(rp, { construcciones: 1 });
    ok('desde el Bloqueo: abre la venta, deriva a Hak Sewa y pone el Bloqueo', r.ok && r.abierto === 'rp1' && r.derivado === 'hak_sewa_notario' && r.puesto.num_reserva_vinculada === 'RP00001' && !r.malos.length);
    r = await corre(cc, { padre: { id: 'rp1', numero: 'RP00001', tipo: 'reserva_parcela' } });
    ok('desde la Construcción: abre la obra pero el vínculo es su BLOQUEO', r.ok && r.abierto === 'cc1' && r.puesto.num_reserva_vinculada === 'RP00001');
    r = await corre({ ...cc, contrato_padre_id: null }, {});
    ok('sin Bloqueo conocido no abre ni crea nada, y lo dice', r.ok === false && r.abierto === null && r.malos.length === 1);
    r = await corre(rp, { construcciones: 1 }, { vinculables: [] });
    ok('Bloqueo fuera de la lista cargada: se pone igual y se avisa', r.ok && r.puesto.num_reserva_vinculada === 'RP00001' && /lista de vinculables/.test(r.malos[0] || ''));
    r = await corre(rp, { construcciones: 1 }, { sinCampo: true });
    ok('si el editor no pintó el campo, se avisa en vez de callar', r.ok && /No se ha podido poner la venta vinculada/.test(r.malos[0] || ''));
  }
}

/* ── 3 · el editor (app.html) ─────────────────────────────────────────────── */
{
  ok('app.html: el Hak Sewa es el tipo que cuelga de su Bloqueo', /const TIPOS_CUELGAN_DE_BLOQUEO = \['hak_sewa_notario'\];/.test(app));
  ok('app.html: la lista de Bloqueos se carga también para el Hak Sewa (no lleva marcador)',
    /if\(templateHTML\.includes\('\{\{num_reserva_vinculada\}\}'\) \|\| cuelgaDeBloqueo\(CURRENT\.slug\)\) await cargarVinculables\(\);/.test(app));
  const inyecta = trozo(app, '  if(cuelgaDeBloqueo(CURRENT.slug)){', '  /* AQUI NO VA EL SELECTOR DEL PODER', 'deriveSections');
  ok('deriveSections inyecta el campo num_reserva_vinculada en «Gestión del contrato»', /aGestion\(opts\.length \? \['num_reserva_vinculada', etiqueta, 'select', opts\]/.test(inyecta)
    && /\['num_reserva_vinculada', etiqueta, 'text'\], true\)/.test(inyecta) && /const aGestion = [^\n]*\n\s*const g = SECTIONS\.find\(s=>s\.id==='gestion'\);/.test(app));
  // derivar a Hak Sewa desde una Construcción: manda el padre REAL de la fila, no el número tecleado (se ejecuta el trozo real)
  {
    const t = trozo(app, '  if(cuelgaDeBloqueo(slug) && CONTRACT_TIPO[CURRENT.slug] === \'construccion\'', '  // A cualquier otro tipo destino', 'derivarContrato');
    const prueba = (padre, tecleado) => {
      const c = { CONTRACT_TIPO, CURRENT: { slug: 'ppjb_construccion' }, cuelgaDeBloqueo: s => s === 'hak_sewa_notario', slug: 'hak_sewa_notario',
        SAVED_CONTRACT: { id: 'cc1', numero: 'CC1', padre }, VINCULABLES: [{ id: 'rpA', numero: 'RP-A' }, { id: 'rpB', numero: 'RP-B' }],
        f: { num_reserva_vinculada: tecleado } };
      vm.createContext(c); vm.runInContext(t, c); return c.f.num_reserva_vinculada;
    };
    ok('derivar: con padre real distinto del tecleado, manda el padre real', prueba('rpB', 'RP-A') === 'RP-B');
    ok('derivar: obra sin padre → Hak Sewa suelto (no hereda un número tecleado)', prueba(null, 'RP-A') === undefined);
    ok('derivar: recién guardada (padre desconocido) → queda el tecleado', prueba(undefined, 'RP-A') === 'RP-A');
    ok('al abrir un contrato se guarda su padre real', /SAVED_CONTRACT = \{ id:data\.id, numero:data\.numero, padre: data\.contrato_padre_id \|\| null \};/.test(app));
  }
  ok('…y no por inDoc (cogería la sección y la etiqueta de la Construcción)', !/inDoc\.add\('num_reserva_vinculada'\)/.test(app));
  ok('el contrato_padre_id de la pantalla sale de esa misma clave', /contrato_padre_id: \(\(VINCULABLES\|\|\[\]\)\.find\(c=>c\.numero===data\.num_reserva_vinculada\)\|\|\{\}\)\.id/.test(app));
  ok('derivar a Hak Sewa refresca la lista de Bloqueos', /if\(slug === 'ppjb_construccion' \|\| cuelgaDeBloqueo\(slug\)\) VINCULABLES = null;/.test(app));
  ok('derivar desde un Bloqueo a Hak Sewa deja el vínculo puesto', /if\(\(slug==='ppjb_construccion' \|\| cuelgaDeBloqueo\(slug\)\) && SAVED_CONTRACT && SAVED_CONTRACT\.numero/.test(app));

  // opcional SOLO en el Hak Sewa: se ejecuta la definición real
  const def = trozo(app, 'const CAMPOS_OPCIONALES_POR_TIPO', 'const SECCIONES_OPCIONALES', 'campoOpcional');
  const c3 = { CONTRACT_TIPO, CAMPOS_OPCIONALES: new Set(['nombre_contrato']), CURRENT: { slug: 'hak_sewa_notario' } };
  vm.createContext(c3);
  vm.runInContext(def + '\nthis.campoOpcional = campoOpcional;', c3);
  ok('en el Hak Sewa el vínculo es opcional (suelto sigue valiendo)', c3.campoOpcional('num_reserva_vinculada') === true);
  c3.CURRENT = { slug: 'ppjb_construccion' };
  ok('en la Construcción sigue obligatorio', c3.campoOpcional('num_reserva_vinculada') === false);
  ok('los opcionales globales siguen valiendo', c3.campoOpcional('nombre_contrato') === true);
  ok('el asterisco y el candado «Faltan por rellenar» usan la misma regla',
    /const reqCls = campoOpcional\(key\) \? '' : ' req';/.test(app) && /if\(type==='readonly' \|\| campoOpcional\(key\)\) return;/.test(app));

  // lo que lee la clave pensando en la OBRA sigue acotado a Construcción
  ok('syncPrecioObraVinculada solo corre en Construcción', /async function syncPrecioObraVinculada\(\)\{\s*\n\s*if\(CONTRACT_TIPO\[CURRENT\.slug\] !== 'construccion' \|\| !sb\) return;/.test(inv));
  ok('syncUnidadConstruccion solo corre en Construcción', /async function syncUnidadConstruccion\(\)\{\s*\n[^\n]*\n\s*if\(CONTRACT_TIPO\[CURRENT\.slug\] !== 'construccion' \|\| !sb\)/.test(inv));
  ok('el desplegable genérico solo actúa si la plantilla imprime el marcador', /if\(inDoc\.has\('num_reserva_vinculada'\) && \(VINCULABLES\|\|\[\]\)\.length\)\{/.test(app));
  ok('la plantilla del Hak Sewa no imprime el vínculo', !lee('templates/hak_sewa_notario.html').includes('{{num_reserva_vinculada}}'));
}

/* ── 4 · el servidor enlaza por esa clave sin mirar el tipo del que se guarda ── */
{
  const dir = path.join(__dirname, '..', 'supabase', 'migrations');
  const defs = fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort()
    .filter(f => /create or replace function public\.contrato_guarda\(/i.test(fs.readFileSync(path.join(dir, f), 'utf8')));
  ok('hay una definición de contrato_guarda en las migraciones', defs.length > 0);
  const sql = fs.readFileSync(path.join(dir, defs[defs.length - 1]), 'utf8');
  const cuerpo = sql.slice(sql.search(/create or replace function public\.contrato_guarda\(/i));
  ok('contrato_guarda (' + defs[defs.length - 1] + ') resuelve el padre por num_reserva_vinculada contra un reserva_parcela',
    /v_nrv := nullif\(btrim\(v_f->>'num_reserva_vinculada'\), ''\);\s*\n\s*v_poa[^\n]*\n\s*if v_nrv is not null then\s*\n\s*select c\.id into v_padre from public\.contratos c\s*\n\s*where c\.numero = v_nrv and c\.tipo = 'reserva_parcela' and public\.puede_ver_contrato\(c\.id\) limit 1;/.test(cuerpo));
}

/* ── 5 · Operaciones: un nieto cuelga de la raíz ───────────────────────────── */
{
  const bloque = trozo(opsSrc, '  const porId = {};', '\n\n', 'operaciones-cuentas');
  const OPS = [
    { id: 'rp', contrato_padre_id: null }, { id: 'cc', contrato_padre_id: 'rp' },
    { id: 'hs', contrato_padre_id: 'rp' }, { id: 'pa', contrato_padre_id: 'hs' },
    { id: 'x', contrato_padre_id: 'y' }, { id: 'y', contrato_padre_id: 'x' },   // un ciclo no cuelga el bucle
    { id: 'suelto', contrato_padre_id: 'no-cargado' }
  ];
  const c5 = { OPS };
  vm.createContext(c5);
  vm.runInContext(bloque, c5);
  const por = Object.fromEntries(OPS.map(o => [o.id, o]));
  ok('el Poder de un Hak Sewa colgado de su Bloqueo cuelga de la RAÍZ', por.pa.padre === por.rp);
  ok('la raíz trae a hijos y nietos', ['cc', 'hs', 'pa'].every(k => por.rp.hijos.includes(por[k])) && !por.hs.hijos.length);
  ok('la lista de Operaciones (raíces = sin padre) no pierde a nadie de la venta',
    OPS.filter(o => !o.padre).map(o => o.id).includes('rp') && ['cc', 'hs', 'pa'].every(k => !!por[k].padre));
  ok('un padre no cargado deja la pieza como fila propia', por.suelto.padre === null);

  // La etapa de la venta no la decide un documento que la acompaña (Hak Sewa en borrador meses después de la obra)
  const fn = trozo(opsSrc, 'function cadenaOperacion(o){', '\n\n\n', 'operaciones-cuentas');
  const c6 = { cuentaGrupo: () => ({ precio: 100, pendiente: 40 }) };
  vm.createContext(c6);
  vm.runInContext(fn + '\nthis.piezaActiva = piezaActiva; this.etapaOperacion = etapaOperacion;', c6);
  const rp = { tipo: 'reserva_parcela', bloqueado: true, created_at: '1' }, cc = { tipo: 'construccion', bloqueado: true, created_at: '2' },
        hs = { tipo: 'hak_sewa_notario', bloqueado: false, created_at: '3', firmas: [] };
  rp.hijos = [cc, hs];
  ok('un Hak Sewa en borrador no es la pieza activa: lo es la obra firmada', c6.piezaActiva(rp) === cc);
  ok('…y la venta sigue en «Cobro pendiente», no en «Sin firmar»', c6.etapaOperacion(rp) === 'cobro_pend');
  const hsSolo = { tipo: 'hak_sewa_notario', bloqueado: true, created_at: '1', hijos: [] };
  c6.cuentaGrupo = () => ({ precio: null, pendiente: null });
  ok('un Hak Sewa suelto firmado (sin precio de venta) no queda «cobro pendiente» para siempre', c6.piezaActiva(hsSolo) === hsSolo && c6.etapaOperacion(hsSolo) === 'cobro_ok');

  // Los otros dos que acompañan (Poder, Adenda) tampoco deciden; la venta sigue en su pieza de dinero
  c6.cuentaGrupo = () => ({ precio: 100, pendiente: 40 });
  const pa = { tipo: 'poa', bloqueado: false, created_at: '4', firmas: [] }, ad = { tipo: 'adenda', bloqueado: false, created_at: '5', firmas: [] };
  rp.hijos = [cc, hs, pa, ad];
  ok('Poder y Adenda en borrador, detrás de la obra firmada: la pieza activa sigue siendo la obra', c6.piezaActiva(rp) === cc && c6.etapaOperacion(rp) === 'cobro_pend');
  c6.cuentaGrupo = () => ({ precio: 100, pendiente: 0 });
  ok('…y con todo cobrado la venta es «Cobro completo» aunque el Hak Sewa siga en borrador', c6.etapaOperacion(rp) === 'cobro_ok');
  // una obra sin firmar SÍ decide (es pieza de dinero): un Hak Sewa ya firmado no la tapa
  const ccBorr = { tipo: 'construccion', bloqueado: false, created_at: '2', firmas: [{ estado: 'pendiente', expira_en: null }] },
        hsFirm = { tipo: 'hak_sewa_notario', bloqueado: true, created_at: '3' };
  rp.hijos = [ccBorr, hsFirm];
  ok('obra con firma enviada y Hak Sewa firmado: manda la obra («Firma enviada»)', c6.piezaActiva(rp) === ccBorr && c6.etapaOperacion(rp) === 'firma_viva');
  // la obra liberada (anulada) deja de contar; manda el Bloqueo vivo, no el Hak Sewa
  const ccLib = { tipo: 'construccion', bloqueado: true, created_at: '2', liberado_en: '2026-10-01' };
  rp.hijos = [ccLib, hs];
  c6.cuentaGrupo = () => ({ precio: 100, pendiente: 40 });
  ok('obra liberada + Hak Sewa en borrador: la pieza activa es el Bloqueo vivo', c6.piezaActiva(rp) === rp && c6.etapaOperacion(rp) === 'cobro_pend');
  // venta entera liberada con un documento VIVO colgando: se enseña ese documento, no se esconde como «liberada»
  const rpLib = { tipo: 'reserva_parcela', bloqueado: true, created_at: '1', liberado_en: '2026-10-01' };
  rpLib.hijos = [ccLib, hs];
  ok('Bloqueo y obra liberados con un Hak Sewa vivo: decide el Hak Sewa (no sale «liberada»)', c6.piezaActiva(rpLib) === hs && c6.etapaOperacion(rpLib) === 'sin_firmar');
  rpLib.hijos = [ccLib, { tipo: 'hak_sewa_notario', bloqueado: false, created_at: '3', liberado_en: '2026-10-02', firmas: [] }];
  ok('…y con todo liberado, Hak Sewa incluido, sí sale «liberada»', c6.etapaOperacion(rpLib) === 'liberada');
  // solo documentos que acompañan (Hak Sewa suelto en borrador, con un Poder): deciden ellos, el último vivo
  const hsSuelto = { tipo: 'hak_sewa_notario', bloqueado: false, created_at: '1', firmas: [] };
  hsSuelto.hijos = [{ tipo: 'poa', bloqueado: true, created_at: '2' }];
  ok('sin pieza de dinero en la cadena: decide el último documento vivo', c6.piezaActiva(hsSuelto) === hsSuelto.hijos[0]);

  // etapa() de UNA pieza (tablero clásico) usa la misma lista
  const fnEtapa = trozo(opsSrc, 'function etapa(o){', '\n\n/* ---------- la OPERACIÓN', 'operaciones-cuentas');
  const c7 = { cuenta: () => ({ precio: null, pendiente: null }) };
  vm.createContext(c7);
  vm.runInContext(fnEtapa + '\n' + fn + '\nthis.etapa = etapa;', c7);
  ok('etapa(): Hak Sewa firmado sin precio = «Cobro completo»', c7.etapa({ tipo: 'hak_sewa_notario', bloqueado: true }) === 'cobro_ok');
  ok('etapa(): Adenda firmada sin precio = «Cobro completo»', c7.etapa({ tipo: 'adenda', bloqueado: true }) === 'cobro_ok');
  ok('etapa(): una Construcción firmada sin precio sigue «Cobro pendiente» (no se afirma cobrado)', c7.etapa({ tipo: 'construccion', bloqueado: true }) === 'cobro_pend');
  c7.cuenta = () => ({ precio: 500, pendiente: 100 });
  ok('etapa(): un Hak Sewa CON precio y pendiente cae al flujo normal', c7.etapa({ tipo: 'hak_sewa_notario', bloqueado: true }) === 'cobro_pend');

  // cuentaGrupo: un hijo que acompaña no suma precio (gemela de _cadena_saldo, 20261013062339); una raíz pieza sí
  {
    const cg = trozo(opsSrc, 'function cuentaGrupo(op){', '\n}\n', 'operaciones-cuentas') + '\n}';
    const c9 = { PIEZAS_ACOMPANAN: ['poa', 'hak_sewa_notario', 'adenda'], lwEsPreliminar: t => /^carta_reserva/.test(t || ''),
      parseImporte: v => (v == null ? null : Number(v)), redondear: v => Math.round(v * 100) / 100 };
    vm.createContext(c9);
    vm.runInContext(cg + '\nthis.cuentaGrupo = cuentaGrupo;', c9);
    const raiz = { tipo: 'reserva_parcela', precio_total: 1000, cobrado: 100, moneda: 'EUR' };
    raiz.hijos = [{ tipo: 'construccion', precio_total: 5000, cobrado: 0, moneda: 'EUR' }, { tipo: 'hak_sewa_notario', precio_total: 900000000, cobrado: 0, moneda: 'EUR' },
      { tipo: 'adenda', precio_total: 200, cobrado: 0, moneda: 'EUR' }, { tipo: 'poa', precio_total: null, cobrado: 0, moneda: 'EUR' }];
    const r = c9.cuentaGrupo(raiz);
    ok('cuentaGrupo: Hak Sewa, Adenda y Poder hijos no suman al precio de la venta', r.precio === 6000 && r.pendiente === 5900);
    const suelto = { tipo: 'hak_sewa_notario', precio_total: 750, cobrado: 0, hijos: [{ tipo: 'poa', precio_total: 30, cobrado: 0 }] };
    ok('cuentaGrupo: un Hak Sewa suelto (raíz) sí cuenta su precio, su Poder no', c9.cuentaGrupo(suelto).precio === 750);
    const mixta = { tipo: 'reserva_parcela', precio_total: 1000, cobrado: 0, moneda: 'EUR',
      hijos: [{ tipo: 'construccion', precio_total: 5000, cobrado: 0, moneda: 'IDR' }, { tipo: 'construccion', precio_total: 300, cobrado: 0, moneda: null },
              { tipo: 'construccion', precio_total: 2000, cobrado: 0, moneda: 'EUR' }] };
    ok('cuentaGrupo: un hijo en otra moneda o sin moneda no suma (como _cadena_saldo)', c9.cuentaGrupo(mixta).precio === 3000);
    const sinMon = { tipo: 'reserva_parcela', precio_total: 1000, cobrado: 0, hijos: [{ tipo: 'construccion', precio_total: 2000, cobrado: 0 }] };
    ok('cuentaGrupo: raíz e hijo sin moneda los dos sí suman (null = null)', c9.cuentaGrupo(sinMon).precio === 3000);
  }

  // datos.js (Operaciones v4): «Falta precio» no se pinta para lo que acompaña, y la lista es la de operaciones-cuentas.js
  const datos = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'assets', 'datos.js'), 'utf8');
  ok('datos.js: «Falta precio» excluye PIEZAS_ACOMPANAN, sin una segunda lista de respaldo',
    /if \(p\.bloqueado && !cg\.precio && PIEZAS_ACOMPANAN\.indexOf\(p\.tipo\) === -1\) out\.push\(\[T\('Falta precio'\)/.test(datos)
    && !/\['poa'\]\)\.indexOf\(p\.tipo\)/.test(datos));
  ok('datos.js: esa línea va detrás de la guarda que sale si operaciones-cuentas.js no cargó',
    datos.indexOf("operaciones-cuentas.js no cargó") > 0 && datos.indexOf("operaciones-cuentas.js no cargó") < datos.indexOf("PIEZAS_ACOMPANAN.indexOf(p.tipo)"));
  const pagOps = fs.readFileSync(path.join(__dirname, '..', 'intranet', 'v4', 'operaciones', 'index.html'), 'utf8');
  const iOc = pagOps.indexOf('/contracts/assets/operaciones-cuentas.js'), iDa = pagOps.indexOf('../assets/datos.js');
  ok('Operaciones v4 carga operaciones-cuentas.js ANTES que datos.js (si no, la lista sería la de reserva)', iOc > 0 && iDa > iOc);
}

console.log('hak_sewa_vinculo.test.js: ' + n + ' comprobaciones en verde');
}
main().catch(e => { console.error('FALLA ' + e.message); process.exit(1); });
