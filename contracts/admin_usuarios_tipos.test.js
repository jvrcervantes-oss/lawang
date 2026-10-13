/* node admin_usuarios_tipos.test.js — 13-oct-2026: la edge admin-usuarios acepta los contratos PROPIOS de una empresa
   (slug de `plantillas_contrato` con empresa) además de los 17, preguntando a la base; lo que no da lo devuelve en
   `tipos_no_dados` en vez de tirarlo en silencio; y un admin que no es super solo da los propios que tiene él.
   Dos partes: (1) se ejecuta `tiposConcedibles` de verdad (con el alcance de quien llama, revisión de Seguridad del 13-oct), sacada del fichero de la edge, contra una base simulada;
   (2) prueba estática de que las dos altas la usan ANTES de crear la cuenta (como admin_usuarios_herramientas.test.js).
   Lo que la base impone por su cuenta (empresa de la persona, alcance de quien concede) lo prueba
   supabase/pruebas/contrato_propio_permiso_agente.sql. Node >= 23.6 (quita los tipos de TypeScript solo). */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');

const src = fs.readFileSync(path.join(__dirname, 'edge', 'admin-usuarios', 'index.ts'), 'utf8');
const trozo = (desde, hasta) => {
  const i = src.indexOf(desde);
  assert.ok(i >= 0, 'no encuentro ' + desde);
  const j = src.indexOf(hasta, i);
  assert.ok(j > i, 'no encuentro el final de ' + desde);
  return src.slice(i, j + hasta.length);
};
const lista = trozo('const TIPOS_CONTRATO = [', '];');
const funcion = trozo('async function tiposConcedibles(', '\n}');

(async () => {
  if (!(process.features && process.features.typescript)) {
    console.log('admin_usuarios_tipos.test.js: parte (1) SALTADA — este Node (' + process.version + ') no quita tipos de TypeScript; la parte estática sí corre');
  } else {
  // base simulada: tres contratos propios existen (uno sin versión activa); el lector es la sesión de quien llama y solo ve
  // las empresas de su alcance (plantilla_contratos_propios_activos contesta 42501 fuera de él)
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tipos-'));
  const fichero = path.join(tmp, 'tipos.mts');
  fs.writeFileSync(fichero, `
    export const llamadas: any[] = [];
    let fallar = false;
    export const falla = (x: boolean) => { fallar = x; };
    const PROPIOS: Record<string, string> = { lawang_furniture_x: 'lawang', lawang_sin_activa: 'lawang', sandal_woods_otro: 'sandal_woods' };
    const ACTIVOS = ['lawang_furniture_x', 'sandal_woods_otro'];
    const admin = { from(t: string) {
      const q: any = { t, slugs: [] as string[], noNulo: '' };
      q.select = () => q;
      q.in = (_c: string, v: string[]) => { q.slugs = v; return q; };
      q.not = (c: string, op: string, v: unknown) => { q.noNulo = c + ' ' + op + ' ' + v; llamadas.push(q);
        return Promise.resolve(fallar ? { data: null, error: { message: 'column empresa does not exist' } }
          : { data: q.slugs.filter((s: string) => s in PROPIOS).map((slug: string) => ({ slug, empresa: PROPIOS[slug] })), error: null }); };
      return q;
    } };
    export const lector = (alcance: string[]) => ({ rpc(nombre: string, a: any) {
      llamadas.push({ rpc: nombre, empresa: a.p_empresa });
      if (!alcance.includes(a.p_empresa)) return Promise.resolve({ data: null, error: { code: '42501' } });
      return Promise.resolve({ data: ACTIVOS.filter((s) => PROPIOS[s] === a.p_empresa).map((slug) => ({ slug, nombre: slug })), error: null });
    } });
    ${lista}
    export ${funcion}
  `);
  const m = await import(pathToFileURL(fichero).href);
  const todo = m.lector(['lawang', 'sandal_woods']);

  let r = await m.tiposConcedibles(['carta_reserva', 'lawang_furniture_x', 'inventado_x', 'carta_reserva'], null, todo);
  assert.deepStrictEqual(r.dados, ['carta_reserva', 'lawang_furniture_x'], 'super: los 17 y el propio activo de su alcance');
  assert.deepStrictEqual(r.no_dados, ['inventado_x'], 'lo que no existe vuelve en no_dados, sin duplicados');
  const q = m.llamadas.find((x) => x.t);
  assert.strictEqual(q.t, 'plantillas_contrato', 'pregunta a plantillas_contrato de qué empresa es');
  assert.deepStrictEqual(q.slugs, ['lawang_furniture_x', 'inventado_x'], 'solo pregunta por lo que no es de los 17');
  assert.strictEqual(q.noNulo, 'empresa is null', 'solo cuenta los que tienen empresa (.not(empresa, is, null))');
  assert.ok(m.llamadas.some((x) => x.rpc === 'plantilla_contratos_propios_activos' && x.empresa === 'lawang'), 'y decide con la RPC de la sesión de quien llama');

  // Seguridad 13-oct: super admin global con empresas marcadas (alcance solo lawang) NO da el propio de otra empresa
  r = await m.tiposConcedibles(['carta_reserva', 'lawang_furniture_x', 'sandal_woods_otro'], null, m.lector(['lawang']));
  assert.deepStrictEqual(r.dados, ['carta_reserva', 'lawang_furniture_x'], 'alcance restringido: solo los propios de sus empresas');
  assert.deepStrictEqual(r.no_dados, ['sandal_woods_otro'], 'el de otra empresa vuelve en no_dados');

  r = await m.tiposConcedibles(['lawang_sin_activa'], null, todo);
  assert.deepStrictEqual(r.dados, [], 'un propio sin versión activa no se da (no serviría para emitir)');

  r = await m.tiposConcedibles(['carta_reserva', 'lawang_furniture_x', 'sandal_woods_otro'], ['carta_reserva', 'lawang_furniture_x'], todo);
  assert.deepStrictEqual(r.dados, ['carta_reserva', 'lawang_furniture_x'], 'admin no super: solo los propios que tiene él');
  assert.deepStrictEqual(r.no_dados, ['sandal_woods_otro']);

  r = await m.tiposConcedibles(['carta_reserva', 'ppjb_parcela'], null, todo);
  assert.deepStrictEqual(r.dados, ['carta_reserva'], 'una plantilla del estudio (sin empresa) no es un tipo');

  const antes = m.llamadas.length;
  r = await m.tiposConcedibles(['carta_reserva', "x'; drop", 'A-B'], null, todo);
  assert.strictEqual(m.llamadas.length, antes, 'un texto que no tiene forma de slug ni se pregunta a la base');
  assert.deepStrictEqual(r.no_dados, ["x'; drop", 'A-B']);

  m.falla(true);
  r = await m.tiposConcedibles(['carta_reserva', 'lawang_furniture_x'], null, todo);
  assert.deepStrictEqual(r.dados, ['carta_reserva'], 'si la consulta falla (instancia del ERP sin la columna), no se da ningún propio');
  assert.deepStrictEqual(r.no_dados, ['lawang_furniture_x']);
  fs.rmSync(tmp, { recursive: true, force: true });
  }

  // (2) las dos altas usan la función, antes de crear la cuenta, y devuelven lo que no dieron
  const rama = (accion) => {
    const i = src.indexOf("accion === '" + accion + "'");
    assert.ok(i > 0, 'no encuentro la acción ' + accion);
    const j = src.indexOf("if (accion === '", i + 10);
    return src.slice(i, j > 0 ? j : undefined);
  };
  for (const a of ['crear', 'activar_solicitud']) {
    const b = rama(a);
    assert.ok(b.includes('await tiposConcedibles('), a + ': usa tiposConcedibles');
    assert.ok(b.indexOf('tiposConcedibles(') < b.indexOf('createUser'), a + ': antes de crear la cuenta');
    assert.ok(/json\(\{ ok: true[^}]*tipos_no_dados/.test(b), a + ': devuelve tipos_no_dados');
    assert.ok(!/\.filter\(\(t: string\) => TIPOS_CONTRATO\.includes\(t\)\)/.test(b), a + ': ya no filtra en silencio contra los 17');
  }
  assert.ok(/soySuper \|\| esEmpresa \? null : \(\(ficha\.tipos_contrato[^\n]*, usuario\);/.test(rama('crear')), 'crear: un admin global no super, solo los suyos; y decide la sesión de quien llama');
  assert.ok(/soySuper \? null : \(\(ficha\.tipos_contrato[^\n]*, usuario\);/.test(rama('activar_solicitud')), 'activar_solicitud: un admin no super, solo los suyos; y decide la sesión de quien llama');
  assert.ok(/select\('rol, activo, herramientas, tipos_contrato'\)/.test(src), 'la ficha de quien llama trae sus tipos');
  console.log('admin_usuarios_tipos.test.js OK');
})().catch((e) => { console.error(e); process.exit(1); });
