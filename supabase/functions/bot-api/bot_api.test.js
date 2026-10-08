/* node bot_api.test.js — la edge `bot-api` (S4 del encargo bot de Lawang) con el index.ts REAL, sin Deno, sin red y sin base.
   Node >= 22.18 carga el .ts quitándole los tipos. `Deno` es un doble; la base (DB.ejecuta) es un doble que contesta lo que
   contestarían las funciones de S3. Qué fija:
   · 401 a todo sin secreto configurado (estado de despliegue), sin cabecera, con cabecera vacía, con secreto malo, con el
     secreto de OTRA ruta, con método distinto de POST y en ruta desconocida — todos con el mismo cuerpo, sin tocar la base;
   · lista cerrada de acciones y esquema cerrado (clave desconocida = 400): no hay forma de pedir otro teléfono;
   · msg_id obligatorio y pasado a la base tal cual; el teléfono llega SOLO desde el campo `tel`;
   · tope / ambiguo / sin_lead… son 200 con `resultado`; un texto no previsto o la base caída son 5xx sin detalle;
   · catálogo: solo las 8 columnas, vacío (200) y caído (503) se ven distinto;
   · la edge se niega a conectar con un usuario que no sea bot_lawang (sin importar el driver);
   · nada va a la consola (ni teléfonos ni textos);
   · el mismo dato en todos los sitios donde vive: los resultados que la edge acepta = los `return '…'` de las funciones SQL, y
     en cada función el bloqueo por teléfono va ANTES de mirar el log de idempotencia (ahí está la garantía de "un solo lead
     y una sola nota" con mensajes simultáneos; la prueba contra la base real está en supabase/pruebas/bot_api_s4.sql). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');

const entorno = {};
globalThis.Deno = { env: { get: (k) => entorno[k] }, serve: () => ({}), test: () => {} };

(async () => {
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const ok = (c, m) => { assert.ok(c, m); n++; };

  const logs = [];
  for (const k of ['log', 'warn', 'error', 'info', 'debug']) console[k] = (...a) => { logs.push(a.join(' ')); };
  const salida = (...a) => process.stdout.write(a.join(' ') + '\n');

  let veces = 0;
  const carga = async () => (await import(pathToFileURL(path.join(__dirname, 'index.ts')).href + '?t=' + (++veces)));
  const M = await carga();
  let MM = M;   // el módulo cuyo manejador atiende (ErrorBase es de cada instancia)
  const SC = 'sec-catalogo-falso', SR = 'sec-crm-falso';
  const fija = (o) => { for (const k of Object.keys(entorno)) delete entorno[k]; Object.assign(entorno, o); M.reiniciaRitmo(); };
  const peticion = (ruta, { metodo = 'POST', secreto, cuerpo = {} } = {}) => new Request('https://ref.supabase.co/functions/v1/bot-api' + (ruta ? '/' + ruta : ''), {
    method: metodo, headers: { 'content-type': 'application/json', ...(secreto !== undefined ? { 'x-bot-secret': secreto } : {}) },
    body: metodo === 'GET' ? undefined : (typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo)),
  });
  const llama = async (req) => { const r = await MM.manejador(req); const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch { /* sin json */ } return { status: r.status, cuerpo: j, crudo: t }; };

  // la base: apunta cada llamada y contesta según `guion`
  let llamadas = [];
  let guion = () => [{ r: 'creado' }];
  M.DB.ejecuta = async (clave, args) => { llamadas.push({ clave, args }); return guion(clave, args); };

  // ── 1. 401 a todo, y la base no se toca ────────────────────────────────────
  const matriz = [['catalogo', {}], ['crm', { accion: 'lead_upsert', tel: '34661569373', msg_id: 'wamid.A' }]];
  fija({});   // desplegada SIN secretos
  for (const [ruta, cuerpo] of matriz) {
    for (const s of [undefined, '', 'x', SC, SR]) {
      const r = await llama(peticion(ruta, { secreto: s, cuerpo }));
      igual([ruta, s, r.status], [ruta, s, 401], 'sin secretos configurados todo es 401');
    }
  }
  igual(llamadas.length, 0, 'sin secretos no se abre la base');
  fija({ BOT_API_SECRET_CATALOGO: SC, BOT_API_SECRET_CRM: SR });
  const cuerpos401 = new Set();
  for (const [ruta, cuerpo] of matriz) {
    const otro = ruta === 'catalogo' ? SR : SC;
    for (const s of [undefined, '', '   ', 'malo', otro, SC + 'x']) {
      const r = await llama(peticion(ruta, { secreto: s, cuerpo }));
      igual(r.status, 401, `ruta ${ruta} secreto ${JSON.stringify(s)}`);
      cuerpos401.add(r.crudo);
    }
  }
  const r405 = await llama(peticion('crm', { metodo: 'GET', secreto: SR }));
  igual(r405.status, 401, 'GET con secreto bueno: mismo 401');
  for (const ruta of ['', 'otra', 'crm/extra', 'admin']) {
    const r = await llama(peticion(ruta, { secreto: SR }));
    cuerpos401.add(r.crudo); igual(r.status, 401, 'ruta desconocida: ' + ruta);
  }
  igual(cuerpos401.size, 1, 'todos los 401 tienen el mismo cuerpo');
  igual(llamadas.length, 0, 'ningún 401 llegó a la base');
  // un secreto en blanco configurado (solo espacios) tampoco autentica
  fija({ BOT_API_SECRET_CATALOGO: '   ', BOT_API_SECRET_CRM: '' });
  igual((await llama(peticion('catalogo', { secreto: '' }))).status, 401);
  igual((await llama(peticion('crm', { secreto: '' }))).status, 401);
  fija({ BOT_API_SECRET_CATALOGO: SC, BOT_API_SECRET_CRM: SR });

  // ── 2. CRM: acciones y esquema cerrados ────────────────────────────────────
  const crm = (cuerpo) => llama(peticion('crm', { secreto: SR, cuerpo }));
  const base = { tel: '34661569373', msg_id: 'wamid.HBgM123=-_.' };
  igual(M.ACCIONES.sort(), ['lead_cita', 'lead_nota', 'lead_upsert']);
  for (const a of ['borrar_lead', 'lead_leer', 'lead_estado', 'sql', '__proto__', 'constructor', 'toString', '', undefined, 5]) {
    const r = await crm({ ...base, accion: a });
    igual(r.status, 400, 'acción fuera de lista: ' + String(a));
  }
  igual((await llama(peticion('crm', { secreto: SR, cuerpo: '{no es json' }))).status, 400);
  igual((await llama(peticion('crm', { secreto: SR, cuerpo: '[1]' }))).status, 400);
  igual((await llama(peticion('crm', { secreto: SR, cuerpo: 'x'.repeat(5000) }))).status, 413);
  for (const extra of [{ otro_tel: '34600000000' }, { lead_id: 'x' }, { tels: ['1'] }, { contrato_id: 'x' }]) {
    const r = await crm({ ...base, accion: 'lead_upsert', ...extra });
    igual(r.status, 400, 'clave desconocida: ' + Object.keys(extra)[0]); igual(r.cuerpo.error, 'campo_no_permitido');
  }
  igual(llamadas.length, 0, 'ninguna petición inválida llegó a la base');
  for (const tel of [undefined, '', '12', '34661569373; drop', ['34661569373'], { a: 1 }, 34661569373, '+34 661 569 373', 'abc', '1'.repeat(16)]) {
    igual((await crm({ ...base, accion: 'lead_upsert', tel })).status, 400, 'tel inválido: ' + JSON.stringify(tel));
  }
  for (const msg_id of [undefined, '', ' ', 'a'.repeat(121), 'con espacio', "x';--", ['a'], 5]) {
    igual((await crm({ ...base, accion: 'lead_upsert', msg_id })).status, 400, 'msg_id inválido (obligatorio): ' + JSON.stringify(msg_id));
  }
  igual((await crm({ ...base, accion: 'lead_upsert', origen: 'otro' })).status, 400);
  igual((await crm({ ...base, accion: 'lead_upsert', nombre: 'x'.repeat(201) })).status, 400);
  igual((await crm({ ...base, accion: 'lead_nota' })).status, 400, 'nota sin texto');
  igual((await crm({ ...base, accion: 'lead_nota', texto: '   ' })).status, 400);
  igual((await crm({ ...base, accion: 'lead_nota', texto: 'x'.repeat(1001) })).status, 400);
  igual((await crm({ ...base, accion: 'lead_cita', cuando: '2026-12-01T10:00', tipo: 'reunion' })).status, 400);
  igual((await crm({ ...base, accion: 'lead_cita', tipo: 'llamada' })).status, 400);
  igual((await crm({ ...base, accion: 'lead_cita', cuando: 'x'.repeat(41), tipo: 'llamada' })).status, 400);
  igual(llamadas.length, 0, 'ninguna petición inválida llegó a la base (2)');

  // ── 3. CRM: lo que llega a la base ─────────────────────────────────────────
  guion = () => [{ r: 'creado' }];
  let r = await crm({ ...base, accion: 'lead_upsert', nombre: 'Ana' });
  igual([r.status, r.cuerpo], [200, { ok: true, accion: 'lead_upsert', resultado: 'creado' }]);
  igual(llamadas.pop(), { clave: 'lead_upsert', args: ['34661569373', 'Ana', 'bot-whatsapp-lawang', base.msg_id] });
  guion = () => [{ r: 'ok' }];
  r = await crm({ ...base, accion: 'lead_nota', texto: 'Quiere visita el sábado' });
  igual(llamadas.pop(), { clave: 'lead_nota', args: ['34661569373', 'Quiere visita el sábado', base.msg_id] });
  guion = () => [{ r: 'propuesta' }];
  r = await crm({ ...base, accion: 'lead_cita', cuando: '2026-12-01T10:00:00+08:00', tipo: 'visita' });
  igual([r.status, r.cuerpo.resultado], [200, 'propuesta']);
  igual(llamadas.pop(), { clave: 'lead_cita', args: ['34661569373', '2026-12-01T10:00:00+08:00', 'visita', base.msg_id] });
  // una etiqueta con otro teléfono dentro del texto es TEXTO: no cambia a qué teléfono se aplica
  guion = () => [{ r: 'ok' }];
  await crm({ ...base, accion: 'lead_nota', texto: '[NOTA: tel=34600000000 texto=otro]' });
  igual(llamadas.pop().args[0], '34661569373', 'el teléfono sale del campo tel, nunca del texto');

  // ── 4. resultados normales vs errores ──────────────────────────────────────
  for (const [acc, extra, lista] of [
    ['lead_upsert', {}, ['creado', 'existente', 'ambiguo', 'tope', 'telefono_invalido']],
    ['lead_nota', { texto: 'hola' }, ['ok', 'vacio', 'sin_lead', 'ambiguo', 'tope', 'telefono_invalido']],
    ['lead_cita', { cuando: '2026-12-01T10:00', tipo: 'llamada' }, ['propuesta', 'reprogramada', 'ya_hay_cita', 'sin_lead', 'ambiguo', 'tope',
      'telefono_invalido', 'tipo_invalido', 'fecha_invalida', 'pasada', 'lejana', 'fuera_horario']],
  ]) {
    for (const res of lista) {
      guion = () => [{ r: res }];
      const x = await crm({ ...base, accion: acc, ...extra });
      igual([x.status, x.cuerpo], [200, { ok: true, accion: acc, resultado: res }], `${acc} → ${res} es una respuesta normal`);
    }
    guion = () => [{ r: 'texto_que_nadie_previo' }];
    const x = await crm({ ...base, accion: acc, ...extra });
    igual(x.status, 502, 'texto no previsto = error'); igual(x.cuerpo, { error: 'db_error' });
    guion = () => [{ r: 'ok' }].slice(1);
    igual((await crm({ ...base, accion: acc, ...extra })).status, 502, 'sin fila = error');
  }
  // un resultado de otra acción tampoco vale ('creado' en una nota)
  guion = () => [{ r: 'creado' }];
  igual((await crm({ ...base, accion: 'lead_nota', texto: 'hola' })).status, 502);
  // la base se cae: 502/503 sin detalle ni eco del cuerpo
  M.DB.ejecuta = async () => { throw Object.assign(new Error('password authentication failed postgres://bot_lawang:SECRETA@host 34661569373'), {}); };
  r = await crm({ ...base, accion: 'lead_upsert' });
  igual(r.status, 500, 'una excepción que no es ErrorBase es 500 genérico'); igual(r.cuerpo, { error: 'interno' });
  ok(!/SECRETA|34661569373|postgres/.test(r.crudo), 'la respuesta no repite el error de la base');

  // ── 5. catálogo ────────────────────────────────────────────────────────────
  M.DB.ejecuta = async (clave, args) => { llamadas.push({ clave, args }); return guion(clave, args); };
  llamadas = [];
  const fila = { proyecto: 'Sumba Hills', tipo: 'parcela', codigo: 'A1', superficie_m2: '500.00', precio: '100000', moneda: 'EUR', modelo: null, disponible: true };
  guion = () => [{ ...fila, contrato_id: 'c-1', comprador: 'Pedro', email: 'p@x.com', telefono: '1', notas: 'N', precio_suelo: 9, id: 'u-1' }];
  r = await llama(peticion('catalogo', { secreto: SC }));
  igual(r.status, 200);
  igual(r.cuerpo.unidades, [{ proyecto: 'Sumba Hills', tipo: 'parcela', codigo: 'A1', superficie_m2: 500, precio: 100000, moneda: 'EUR', modelo: null, disponible: true }]);
  ok(!/contrato|comprador|email|telefono|notas|precio_suelo|u-1/.test(r.crudo), 'solo las 8 columnas; lo demás no sale aunque la base lo devolviera');
  igual(llamadas.pop(), { clave: 'catalogo', args: [] });
  guion = () => [];
  r = await llama(peticion('catalogo', { secreto: SC }));
  igual([r.status, r.cuerpo.ok, r.cuerpo.unidades], [200, true, []], 'vacío = 200 con lista vacía');
  // la caída real: ErrorBase('db_conexion') → 503, distinto de vacío
  delete entorno.BOT_DB_URL;
  MM = await carga();   // la implementación REAL de DB.ejecuta, sin URL de base
  r = await llama(peticion('catalogo', { secreto: SC }));
  igual([r.status, r.cuerpo], [503, { error: 'db_conexion' }], 'caído (sin base) = 503, no "vacío"');
  // la edge no usa una URL que no sea la del rol del bot (sin llegar a importar el driver)
  for (const url of ['postgresql://postgres.abcdef:clave@aws-0-ap.pooler.supabase.com:6543/postgres', 'postgresql://service_role:x@h/db', 'basura', 'postgresql://bot_lawang_otro.ref:x@h/db']) {
    entorno.BOT_DB_URL = url;
    r = await llama(peticion('catalogo', { secreto: SC }));
    igual([r.status, r.cuerpo], [503, { error: 'db_conexion' }], 'URL que no es de bot_lawang: no se usa → ' + url.split(':')[1]);
  }
  delete entorno.BOT_DB_URL;
  MM = M;

  // ── 6. ritmo ───────────────────────────────────────────────────────────────
  M.reiniciaRitmo(); M.AJUSTES.topeCrm = 3; guion = () => [{ r: 'existente' }];
  const codigos = [];
  for (let i = 0; i < 5; i++) codigos.push((await crm({ ...base, accion: 'lead_upsert' })).status);
  igual(codigos, [200, 200, 200, 429, 429]);
  r = await llama(peticion('catalogo', { secreto: SC })); igual(r.status, 200, 'cada ruta cuenta aparte');
  M.AJUSTES.topeCrm = 90;

  // ── 7. concurrencia: mismo msg_id → la edge manda idéntico (accion, msg_id) y devuelve lo mismo ──
  M.reiniciaRitmo(); llamadas = [];
  const vistos = new Map();   // doble de la idempotencia de la base (el comportamiento real se prueba en bot_api_s4.sql)
  M.DB.ejecuta = async (clave, args) => {
    llamadas.push({ clave, args });
    await new Promise((res) => setTimeout(res, 5));
    const k = clave + '|' + args[args.length - 1];
    if (!vistos.has(k)) vistos.set(k, clave === 'lead_nota' ? 'ok' : 'creado');
    return [{ r: vistos.get(k) }];
  };
  const par = await Promise.all([1, 2, 3, 4, 5].map(() => crm({ ...base, accion: 'lead_nota', texto: 'una vez' })));
  igual(new Set(par.map((x) => x.crudo)).size, 1, 'cinco llamadas simultáneas: la misma respuesta');
  igual(new Set(llamadas.map((l) => JSON.stringify(l))).size, 1, 'y llegan con idéntico (accion, tel, msg_id)');
  igual(vistos.size, 1);

  // ── 8. consola limpia ──────────────────────────────────────────────────────
  igual(logs, [], 'nada va a la consola');

  // ── 9. el mismo dato en todos los sitios ───────────────────────────────────
  const mig = (f) => leer('supabase', 'migrations', f);
  const cuerpoFn = (sql, nombre) => {
    const i = sql.lastIndexOf('create or replace function public.' + nombre + '(');
    const j = sql.indexOf('end $f$;', i);
    assert.ok(i >= 0 && j > i, 'no encuentro ' + nombre); return sql.slice(i, j);
  };
  const m0 = mig('20261010080000_bot_catalogo_crm_s3.sql'), m1 = mig('20261010080100_bot_catalogo_crm_s3_saneo.sql'), m2 = mig('20261010080200_bot_catalogo_crm_s3_revision.sql');
  const vigente = { lead_upsert: cuerpoFn(m2, 'bot_lead_upsert'), lead_nota: cuerpoFn(m1, 'bot_lead_nota'), lead_cita: cuerpoFn(m0, 'bot_lead_cita') };
  for (const [acc, cuerpo] of Object.entries(vigente)) {
    const lits = [...new Set([...cuerpo.matchAll(/return\s+'([a-z_]+)'/g)].map((m) => m[1]))].sort();
    const aceptados = [...new Set([...cuerpo.matchAll(/return\s+'([a-z_]+)'/g)].map((m) => m[1]))];
    // los literales de la función (más lo que replay devuelve del log) han de estar todos en la lista de la edge
    for (const l of aceptados) {
      const lista = { lead_upsert: ['creado', 'existente', 'ambiguo', 'tope', 'telefono_invalido'], lead_nota: ['ok', 'vacio', 'sin_lead', 'ambiguo', 'tope', 'telefono_invalido'],
        lead_cita: ['propuesta', 'reprogramada', 'ya_hay_cita', 'sin_lead', 'ambiguo', 'tope', 'telefono_invalido', 'tipo_invalido', 'fecha_invalida', 'pasada', 'lejana', 'fuera_horario'] }[acc];
      ok(lista.includes(l), `${acc}: la función SQL devuelve '${l}' y la edge no lo acepta`);
    }
    ok(lits.length > 0);
    // el bloqueo por teléfono va ANTES de mirar el log de idempotencia
    const iLock = cuerpo.indexOf('pg_advisory_xact_lock'), iLog = cuerpo.indexOf('from public.bot_acciones_log l where l.accion');
    ok(iLock > 0 && iLog > iLock, `${acc}: el bloqueo por teléfono debe ir antes de consultar el log de idempotencia`);
  }
  // la lista de resultados de la edge está en el propio index.ts (no solo en el test): se lee y se compara
  const fuente = leer('supabase', 'functions', 'bot-api', 'index.ts');
  for (const res of ['tope', 'ambiguo', 'sin_lead', 'fuera_horario', 'ya_hay_cita']) ok(fuente.includes("'" + res + "'"), 'index.ts conoce ' + res);
  // las columnas del catálogo = las del RETURNS TABLE de la función (y ninguna prohibida)
  const ret = /create or replace function public\.bot_catalogo_leer\(\)\s*returns table \(([^)]*)\)/.exec(m0);
  ok(ret, 'RETURNS TABLE de bot_catalogo_leer');
  const colsSql = ret[1].split(',').map((c) => c.trim().split(/\s+/)[0]);
  const colsEdge = /CLAVES_CATALOGO = \[([^\]]*)\]/.exec(fuente)[1].split(',').map((c) => c.trim().replace(/'/g, ''));
  igual(colsEdge, colsSql, 'columnas del catálogo: edge = función SQL');
  ok(!colsEdge.some((c) => /contrato|comprador|cliente|telefono|email/.test(c)));
  // la edge no usa service_role ni PostgREST, y no escribe en consola
  ok(!/SERVICE_ROLE|\/rest\/v1|createClient/.test(fuente.replace(/\/\/.*$/gm, '')), 'la edge no usa service_role ni PostgREST');
  ok(!/console\./.test(fuente.replace(/\/\/.*$/gm, '')), 'sin console en el código');

  salida(`bot_api.test.js: ${n} comprobaciones OK`);
})().catch((e) => { process.stderr.write('FALLA: ' + (e && e.stack ? e.stack : e) + '\n'); process.exit(1); });
