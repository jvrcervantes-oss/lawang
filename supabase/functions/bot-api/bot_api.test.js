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
  const peticion = (ruta, { metodo = 'POST', secreto, cuerpo = {}, extra = {} } = {}) => new Request('https://ref.supabase.co/functions/v1/bot-api' + (ruta ? '/' + ruta : ''), {
    method: metodo, headers: { 'content-type': 'application/json', ...(secreto !== undefined ? { 'x-bot-secret': secreto } : {}), ...extra },
    body: metodo === 'GET' ? undefined : (typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo)),
  });
  const llama = async (req) => { const r = await MM.manejador(req); const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch { /* sin json */ } return { status: r.status, cuerpo: j, crudo: t }; };

  // la base: apunta cada llamada y contesta según `guion`
  let llamadas = [];
  let guion = () => [{ r: 'creado' }];
  M.DB.ejecuta = async (clave, args) => { llamadas.push({ clave, args }); return guion(clave, args); };

  // Doble FIEL del driver (LAW-507, 9-oct-2026): los dobles de DB.ejecuta de arriba NO ven cómo postgres.js serializa un parámetro.
  // Con `conexion.unsafe(sql, args)` postgres.js pregunta al servidor el tipo de cada $N y serializa según ese tipo: un parámetro
  // tipado jsonb pasa por JSON.stringify AUNQUE ya sea texto (queda un string JSON de un string: jsonb ESCALAR de tipo string, y
  // bot_importar_* contestaban 'forma' a todo en producción); un parámetro text va tal cual. Esto devuelve lo que vería la función SQL.
  const vistoPorLaFuncion = (sql, args) => {
    const tipos = {};
    for (const m of sql.matchAll(/\$(\d+)((?:::[a-z]+)+)/g)) { if (!(m[1] in tipos)) tipos[m[1]] = m[2].split('::').filter(Boolean); }   // 1.er cast = tipo que infiere el servidor
    return args.map((a, i) => {
      const cast = tipos[String(i + 1)];
      if (!cast) return a;
      const alCable = cast[0] === 'jsonb' ? JSON.stringify(a) : a;            // postgres.js: serializador de jsonb = JSON.stringify
      return cast.includes('jsonb') ? JSON.parse(alCable) : alCable;          // el servidor lee el texto como jsonb
    });
  };
  const jsonbDe = (sql) => [...sql.matchAll(/\$(\d+)((?:::[a-z]+)+)/g)].filter((m) => m[2].endsWith('::jsonb')).map((m) => +m[1] - 1);
  // la sentencia vieja se comporta como el bug: se prueba que el doble lo CAZA (si no, esta prueba no vale nada)
  igual(typeof vistoPorLaFuncion('select f($1::jsonb)', ['{"a":1}'])[0], 'string', 'el doble reproduce el bug de $N::jsonb');
  igual(vistoPorLaFuncion('select f($1::text::jsonb)', ['{"a":1}'])[0], { a: 1 }, 'el doble ve un objeto con $N::text::jsonb');
  // TODAS las sentencias de la edge: cada parámetro jsonb llega a la función como el objeto/array que la edge serializó
  for (const [clave, sql] of Object.entries(M.SQL)) {
    for (const i of jsonbDe(sql)) {
      const args = Array.from({ length: 8 }, () => null); args[i] = '{"k":[1,2]}';
      const visto = vistoPorLaFuncion(sql, args)[i];
      ok(visto !== null && typeof visto === 'object', `${clave}: el parámetro jsonb $${i + 1} llega como objeto, no como string doblemente codificado`);
      const arr = args.slice(); arr[i] = '[]';
      ok(Array.isArray(vistoPorLaFuncion(sql, arr)[i]), `${clave}: $${i + 1} vacío llega como array`);
    }
  }
  igual(Object.entries(M.SQL).filter(([, s]) => jsonbDe(s).length).map(([c]) => c).sort(), ['envio_humano', 'importar_chat', 'importar_config', 'mensaje_recibir', 'turno_cerrar'], 'las acciones que pasan jsonb (si aparece otra, esta lista se actualiza a conciencia)');

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

  // ═══ S2 — rutas /estado, /recordatorio y /humano ══════════════════════════════════════════════════════════
  M.DB.ejecuta = async (clave, args) => { llamadas.push({ clave, args }); return guion(clave, args); };   // el doble corriente (la sección 7 puso otro)
  const SE = 'sec-estado-falso', SRE = 'sec-recordatorio-falso', SH = 'sec-humano-falso';
  const SEC = { estado: SE, recordatorio: SRE, humano: SH };
  const RUTAS_S2 = ['estado', 'recordatorio', 'humano'];
  const todos = () => fija({ BOT_API_SECRET_CATALOGO: SC, BOT_API_SECRET_CRM: SR, BOT_API_SECRET_ESTADO: SE, BOT_API_SECRET_RECORDATORIO: SRE, BOT_API_SECRET_HUMANO: SH,
    SUPABASE_URL: 'https://ref.supabase.co', SUPABASE_ANON_KEY: 'anon-falsa' });
  const authReal = M.AUTH.usuario;
  let authLlamadas = [];
  M.AUTH.usuario = async (jwt) => { authLlamadas.push(jwt); return jwt === 'jwt-bueno' ? 'ana@lawang.com' : null; };
  const reinicia = () => { M.reiniciaRitmo(); M.reiniciaRitmoTel(); llamadas = []; authLlamadas = []; };
  const rq = (ruta, cuerpo, o = {}) => llama(peticion(ruta, { metodo: o.metodo ?? 'POST', secreto: 'secreto' in o ? o.secreto : SEC[ruta], cuerpo,
    extra: 'jwt' in o && o.jwt !== undefined ? { authorization: 'Bearer ' + o.jwt } : {} }));
  const dbCon = (r) => { guion = () => r; };
  const TEL = '34661569373', W = 'wamid.HBgM-ESTADO=1';

  // ── S2.1 401 a todo: sin secretos, secreto de otra ruta, método, y /humano sin JWT ──
  fija({});
  for (const ruta of RUTAS_S2) for (const s of [undefined, '', 'x', SE, SRE, SH, SC, SR]) {
    igual((await rq(ruta, { accion: 'pausar', tel: TEL }, { secreto: s, jwt: 'jwt-bueno' })).status, 401, `${ruta}: sin secretos configurados todo es 401`);
  }
  todos(); reinicia();
  const c401 = new Set();
  for (const ruta of RUTAS_S2) {
    const buenos = { estado: { accion: 'baja', tel: TEL, wamid: W }, recordatorio: { accion: 'citas_recordar' }, humano: { accion: 'pausar', tel: TEL, modo: 'pausar' } }[ruta];
    for (const s of [undefined, '', '   ', 'malo', ...[SE, SRE, SH, SC, SR].filter((x) => x !== SEC[ruta]), SEC[ruta] + 'x']) {
      const r = await rq(ruta, buenos, { secreto: s, jwt: 'jwt-bueno' });
      igual(r.status, 401, `${ruta} con secreto ${JSON.stringify(s)}`); c401.add(r.crudo);
    }
    igual((await rq(ruta, buenos, { jwt: 'jwt-bueno', metodo: 'GET' })).status, 401, 'GET con secreto bueno: 401');
  }
  // los secretos de las rutas viejas tampoco abren las nuevas, ni al revés
  igual((await llama(peticion('crm', { secreto: SE, cuerpo: { accion: 'lead_upsert', tel: TEL, msg_id: W } }))).status, 401);
  igual((await llama(peticion('catalogo', { secreto: SH, cuerpo: {} }))).status, 401);
  igual(c401.size, 1, 'todos los 401 (viejos y nuevos) tienen el mismo cuerpo'); ok(c401.has(JSON.stringify({ error: 'no_autorizado' })));
  igual(llamadas.length + authLlamadas.length, 0, 'ningun 401 llego a la base ni a Auth');
  // secretos en blanco configurados: nada autentica
  fija({ BOT_API_SECRET_ESTADO: '  ', BOT_API_SECRET_RECORDATORIO: '', BOT_API_SECRET_HUMANO: ' ' });
  for (const ruta of RUTAS_S2) igual((await rq(ruta, { accion: 'citas_recordar' }, { secreto: '', jwt: 'jwt-bueno' })).status, 401);
  todos(); reinicia();
  // /humano: secreto bueno sin JWT (o con basura) = 401 y sin tocar Auth ni la base
  for (const jwt of [undefined, '', 'x'.repeat(5000)]) {
    igual((await rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, { jwt })).status, 401, 'humano sin JWT utilizable: 401');
  }
  igual(authLlamadas.length + llamadas.length, 0);
  igual((await rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, { jwt: 'jwt-malo' })).status, 401, 'JWT que Auth rechaza: 401');
  igual(llamadas.length, 0, 'con JWT malo no se abre la base');

  // ── S2.2 lista cerrada y esquema cerrado ──
  reinicia();
  igual(M.ACCIONES_RUTA, {
    estado: ['mensaje_recibir', 'turno_estado', 'turno_cerrar', 'eco_operadora', 'pausar', 'baja', 'entrega_fallida', 'escalar', 'escalacion_tomar',
      'consentimiento_preguntar', 'consentimiento_enviada', 'consentimiento_responder', 'lead_resumen', 'verificar'],
    recordatorio: ['citas_recordar', 'seguimiento_candidatos', 'seguimiento_reservar', 'seguimiento_registrar', 'cita_recordatorio_res'],
    humano: ['pausar', 'enviar'],
    importar: ['chat', 'config', 'cuadre'],
  }, 'la lista cerrada de acciones es exactamente la del plan');
  for (const ruta of RUTAS_S2) {
    for (const a of ['borrar_lead', 'lead_leer', 'sql', 'lead_upsert', 'lead_nota', 'lead_cita', '__proto__', 'constructor', 'toString', 'hasOwnProperty', '', undefined, 5, ['baja']]) {
      igual((await rq(ruta, { accion: a, tel: TEL, wamid: W }, { jwt: 'jwt-bueno' })).status, 400, `${ruta}: acción fuera de lista ${String(a)}`);
    }
    // una acción de OTRA ruta nueva tampoco vale aquí
    const ajena = ruta === 'estado' ? 'citas_recordar' : ruta === 'recordatorio' ? 'baja' : 'baja';
    igual((await rq(ruta, { accion: ajena, tel: TEL, wamid: W }, { jwt: 'jwt-bueno' })).status, 400, `${ruta}: acción de otra ruta`);
    igual((await rq(ruta, '{no json', { jwt: 'jwt-bueno' })).status, 400);
    igual((await rq(ruta, '[1]', { jwt: 'jwt-bueno' })).status, 400);
  }
  igual((await rq('estado', 'x'.repeat(300000))).status, 413, 'estado: tope de cuerpo propio (262144)');
  igual((await rq('recordatorio', 'x'.repeat(2000))).status, 413);
  igual((await rq('humano', 'x'.repeat(40000), { jwt: 'jwt-bueno' })).status, 413);
  igual(llamadas.length, 0, 'ninguna petición inválida llegó a la base');
  const bien = { // un cuerpo válido por acción, para probar que UNA clave de más lo rompe
    mensaje_recibir: { accion: 'mensaje_recibir', tel: TEL, wamid: W, nombre_perfil: 'Ana', mensaje: { texto: 'hola' } },
    turno_estado: { accion: 'turno_estado', tel: TEL }, turno_cerrar: { accion: 'turno_cerrar', tel: TEL, wamid: W },
    eco_operadora: { accion: 'eco_operadora', tel: TEL, wamid: W, texto: 'hola' }, pausar: { accion: 'pausar', tel: TEL, modo: 'humano' },
    baja: { accion: 'baja', tel: TEL, wamid: W }, entrega_fallida: { accion: 'entrega_fallida', tel: TEL, codigo: '131047' },
    escalar: { accion: 'escalar', tel: TEL, pregunta: 'precio' }, escalacion_tomar: { accion: 'escalacion_tomar' },
    lead_resumen: { accion: 'lead_resumen', tel: TEL, texto: 'resumen', hasta_id: 5 },
  };
  for (const [a, cuerpo] of Object.entries(bien)) {
    for (const extra of [{ otro_tel: '34600000000' }, { lead_id: 'x' }, { usuario: 'ana@x.com' }, { tels: ['1'] }]) {
      const r = await rq('estado', { ...cuerpo, ...extra });
      igual([a, r.status, r.cuerpo.error], [a, 400, 'campo_no_permitido'], `estado/${a}: clave desconocida ${Object.keys(extra)[0]}`);
    }
  }
  for (const extra of [{ otro_tel: '1' }, { usuario: 'x' }]) {
    igual((await rq('recordatorio', { accion: 'citas_recordar', ...extra })).status, 400);
    igual((await rq('recordatorio', { accion: 'cita_recordatorio_res', accion_id: '6f1c3a52-0000-4000-8000-000000000001', resultado: 'enviado', ...extra })).status, 400);
    igual((await rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar', ...extra }, { jwt: 'jwt-bueno' })).status, 400);
  }
  // escalacion_tomar y las del recordatorio NO aceptan un tel de entrada (las dos excepciones devuelven telefonos, no los reciben)
  igual((await rq('estado', { accion: 'escalacion_tomar', tel: TEL })).status, 400, 'escalacion_tomar no acepta tel');
  igual((await rq('recordatorio', { accion: 'citas_recordar', tel: TEL })).status, 400);
  // validación de forma
  const malos = [
    ['mensaje_recibir', { tel: '12' }], ['mensaje_recibir', { tel: '+34 661' }], ['mensaje_recibir', { wamid: 'con espacio' }], ['mensaje_recibir', { wamid: undefined }],
    ['mensaje_recibir', { nombre_perfil: 5 }], ['mensaje_recibir', { mensaje: 'texto' }], ['mensaje_recibir', { mensaje: ['a'] }],
    ['mensaje_recibir', { mensaje: { texto: 5 } }], ['mensaje_recibir', { mensaje: { texto: 'a', extra: 1 } }], ['mensaje_recibir', { mensaje: { rol: 'assistant', texto: 'a' } }],
    ['mensaje_recibir', { mensaje: { media: { tipo: 'image', id: 'm1', url: 'https://x/y.jpg' } } }],
    ['mensaje_recibir', { mensaje: { media: { tipo: 'image', id: 'm1', base64: 'AAAA' } } }],
    ['mensaje_recibir', { mensaje: { media: { tipo: 'IMAGE', id: 'm1' } } }], ['mensaje_recibir', { mensaje: { media: { tipo: 'image', id: 'con espacio' } } }],
    ['mensaje_recibir', { mensaje: { media: 'm1' } }], ['mensaje_recibir', { mensaje: { ts: 'ayer' } }], ['mensaje_recibir', { mensaje: { ts: 1.5 } }],
    ['turno_estado', { testing: 'si' }], ['turno_cerrar', { wamid: undefined }], ['turno_cerrar', { salida: 'hola' }], ['turno_cerrar', { salida: new Array(11).fill({ texto: 'a' }) }],
    ['turno_cerrar', { salida: [{ texto: 'a', url: 'x' }] }], ['turno_cerrar', { salida: [{ texto: 5 }] }], ['turno_cerrar', { salida: [{ media: { tipo: 'image', id: 'm', url: 'x' } }] }],
    ['turno_cerrar', { salida: [{ texto: 'a', wamid: 'con espacio' }] }], ['turno_cerrar', { aviso: 'otro' }], ['turno_cerrar', { esperando: 'si' }], ['turno_cerrar', { cambio_tema: 1 }], ['turno_cerrar', { intent: 5 }],
    ['eco_operadora', { wamid: undefined }], ['eco_operadora', { horas: 721 }], ['eco_operadora', { horas: -1 }], ['eco_operadora', { horas: 1.5 }], ['eco_operadora', { texto: 5 }],
    ['pausar', { modo: 'pausar' }], ['pausar', { modo: undefined }], ['pausar', { horas: 'x' }],
    ['baja', { wamid: undefined }], ['entrega_fallida', { codigo: undefined }], ['entrega_fallida', { codigo: '   ' }], ['entrega_fallida', { detalle: 5 }],
    ['escalar', { pregunta: undefined }], ['escalar', { pregunta: 5 }], ['escalar', { nombre: 5 }], ['escalar', { aviso_wamid: 'con espacio' }],
    ['escalacion_tomar', { wamid: 'con espacio' }], ['escalacion_tomar', { wamid: 5 }],
    ['lead_resumen', { texto: undefined }], ['lead_resumen', { texto: '   ' }], ['lead_resumen', { hasta_id: 0 }], ['lead_resumen', { hasta_id: -3 }], ['lead_resumen', { hasta_id: '5' }], ['lead_resumen', { hasta_id: 1.5 }], ['lead_resumen', { hasta_id: 1e20 }],
  ];
  for (const [a, cambio] of malos) {
    const r = await rq('estado', { ...bien[a], ...cambio });
    igual(r.status, 400, `estado/${a} ${JSON.stringify(cambio)} debe ser 400`);
  }
  for (const cuerpo of [{ accion: 'cita_recordatorio_res', resultado: 'enviado' }, { accion: 'cita_recordatorio_res', accion_id: 'no-uuid', resultado: 'enviado' },
    { accion: 'cita_recordatorio_res', accion_id: '6f1c3a52-0000-4000-8000-000000000001', resultado: 'hecho' }, { accion: 'cita_recordatorio_res', accion_id: '6f1c3a52-0000-4000-8000-000000000001' }]) {
    igual((await rq('recordatorio', cuerpo)).status, 400, 'recordatorio: ' + JSON.stringify(cuerpo));
  }
  for (const c of [{ modo: 'borrar' }, { modo: undefined }, { tel: '12' }]) igual((await rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar', ...c }, { jwt: 'jwt-bueno' })).status, 400);
  for (const c of [{ wamid: undefined }, { texto: '', media: undefined }, { texto: '   ' }, { texto: 5 }, { media: { tipo: 'image', id: 'm', url: 'x' } }, { usuario: 'otro@x.com' }]) {
    igual((await rq('humano', { accion: 'enviar', tel: TEL, texto: 'hola', wamid: W, ...c }, { jwt: 'jwt-bueno' })).status, 400, 'humano/enviar ' + JSON.stringify(c));
  }
  igual(llamadas.length + authLlamadas.length, 0, 'ninguna petición inválida llegó a la base ni a Auth');

  // ── S2.3 lo que llega a la base y lo que sale, acción por acción ──
  const FILA = (r) => [{ r }];
  const caso = async (ruta, cuerpo, dbDevuelve, argsEsperados, clave, salida, jwt) => {
    reinicia(); dbCon(dbDevuelve);
    const r = await rq(ruta, cuerpo, { jwt });
    igual(r.status, 200, `${cuerpo.accion}: 200`);
    igual(llamadas, [{ clave, args: argsEsperados }], `${cuerpo.accion}: sentencia y argumentos`);
    igual(r.cuerpo, { ok: true, accion: cuerpo.accion, ...salida }, `${cuerpo.accion}: salida fija`);
    return r;
  };
  // mensaje_recibir: el rol no llega a la base; el texto se RECORTA a 4096 y el nombre a 200 (nunca un 400); la salida lleva solo 4 claves
  await caso('estado', { accion: 'mensaje_recibir', tel: TEL, wamid: W, nombre_perfil: 'N'.repeat(500), mensaje: { rol: 'user', texto: 'x'.repeat(10000), media: { tipo: 'image', id: 'm-1' }, ts: 1760000000 } },
    FILA({ duplicado: false, procesado: false, lead_id: 'secreto', historial: ['x'] }),
    [TEL, W, 'N'.repeat(200), JSON.stringify({ texto: 'x'.repeat(4096), media: { tipo: 'image', id: 'm-1' }, ts: 1760000000 })], 'mensaje_recibir',
    { duplicado: false, procesado: false, reproceso: false, tope: false });
  await caso('estado', bien.mensaje_recibir, FILA({ duplicado: false, procesado: false, reproceso: true }),
    [TEL, W, 'Ana', JSON.stringify({ texto: 'hola', media: null, ts: null })], 'mensaje_recibir', { duplicado: false, procesado: false, reproceso: true, tope: false });
  await caso('estado', { ...bien.mensaje_recibir, mensaje: { ts: '1760000000000' } }, FILA({ duplicado: true, procesado: true, tope: true }),
    [TEL, W, 'Ana', JSON.stringify({ texto: '', media: null, ts: '1760000000000' })], 'mensaje_recibir', { duplicado: true, procesado: true, reproceso: false, tope: true });
  await caso('estado', { accion: 'turno_estado', tel: TEL, testing: true },
    FILA({ baja: false, pausado: false, esperando: true, avisar_testing: true, primer_turno: false, otro: 1,
      historial: [{ rol: 'user', texto: 'hola', por: 'cliente', media: null, ts: 1760000000000, interno: 'x' }, { rol: 'assistant', texto: 'ey', por: 'bot', media: { tipo: 'image', id: 'm', url: 'x' }, ts: 1760000000001 }],
      config: { extra: '', bienvenida: 'Hi', pausa_horas: 0, resumen_cada_n: 30, fallos_alarma: 3, version: 2, actualizado_en: '2026-10-09T10:00:00+00:00', actualizado_por: 'x' } }),
    [TEL, 'true'], 'turno_estado',
    { baja: false, pausado: false, esperando: true, avisar_testing: true, primer_turno: false,
      historial: [{ rol: 'user', texto: 'hola', por: 'cliente', media: null, ts: 1760000000000 }, { rol: 'assistant', texto: 'ey', por: 'bot', media: { tipo: 'image', id: 'm' }, ts: 1760000000001 }],
      config: { extra: '', bienvenida: 'Hi', pausa_horas: 0, resumen_cada_n: 30, fallos_alarma: 3, version: 2, actualizado_en: '2026-10-09T10:00:00+00:00' } });
  await caso('estado', { accion: 'turno_estado', tel: TEL }, FILA({ baja: true, pausado: true, esperando: false, avisar_testing: false, primer_turno: true, historial: [],
    config: { extra: '', bienvenida: '', pausa_horas: 0, resumen_cada_n: 30, fallos_alarma: 3, version: 1, actualizado_en: '2026-10-09T10:00:00+00:00' } }),
    [TEL, 'false'], 'turno_estado', { baja: true, pausado: true, esperando: false, avisar_testing: false, primer_turno: true, historial: [],
      config: { extra: '', bienvenida: '', pausa_horas: 0, resumen_cada_n: 30, fallos_alarma: 3, version: 1, actualizado_en: '2026-10-09T10:00:00+00:00' } });
  await caso('estado', { accion: 'turno_cerrar', tel: TEL, wamid: W, salida: [{ texto: 'T'.repeat(5000), wamid: 'wamid.OUT1' }, { media: { tipo: 'image', id: 'm2' } }], intent: 'I'.repeat(60), aviso: 'booking', esperando: true, cambio_tema: true },
    FILA({ avisar: 'booking', resumir: { hasta_id: 77, mensajes: [{ rol: 'user', por: 'cliente', texto: 'a', tel: '346' }], xx: 1 }, repetido: false, otro: 1 }),
    [TEL, W, JSON.stringify([{ texto: 'T'.repeat(4096), media: null, wamid: 'wamid.OUT1' }, { texto: '', media: { tipo: 'image', id: 'm2' }, wamid: null }]), 'I'.repeat(40), 'booking', 'true', 'true'], 'turno_cerrar',
    { avisar: 'booking', resumir: { hasta_id: 77, mensajes: [{ rol: 'user', por: 'cliente', texto: 'a' }] }, repetido: false });
  await caso('estado', bien.turno_cerrar, FILA({ avisar: null, resumir: null, repetido: true }), [TEL, W, '[]', null, null, 'false', 'false'], 'turno_cerrar', { avisar: null, resumir: null, repetido: true });
  await caso('estado', { accion: 'eco_operadora', tel: TEL, wamid: W, texto: 'E'.repeat(9000), horas: 24 }, FILA({ duplicado: false, estaba_pausado: true }), [TEL, W, 'E'.repeat(4096), '24'], 'eco_operadora', { duplicado: false, estaba_pausado: true });
  await caso('estado', bien.eco_operadora, FILA({ duplicado: true, estaba_pausado: false }), [TEL, W, 'hola', null], 'eco_operadora', { duplicado: true, estaba_pausado: false });
  await caso('estado', { accion: 'pausar', tel: TEL, modo: 'humano', horas: 0 }, FILA({ pausado: true, hasta: null }), [TEL, 'humano', '0'], 'pausar', { pausado: true, hasta: null });
  await caso('estado', { accion: 'pausar', tel: TEL, modo: 'quitar' }, FILA({ pausado: false, hasta: '2026-10-10T00:00:00+00:00' }), [TEL, 'quitar', null], 'pausar', { pausado: false, hasta: '2026-10-10T00:00:00+00:00' });
  await caso('estado', bien.baja, FILA({ baja: 'nueva', pausado: true }), [TEL, W], 'baja', { baja: 'nueva', pausado: true });
  await caso('estado', bien.baja, FILA({ baja: 'ya_dada', pausado: true }), [TEL, W], 'baja', { baja: 'ya_dada', pausado: true });
  await caso('estado', { accion: 'entrega_fallida', tel: TEL, codigo: 'C'.repeat(50), detalle: 'D'.repeat(500) }, FILA('ok'), [TEL, 'C'.repeat(20), 'D'.repeat(200)], 'entrega_fallida', { resultado: 'ok' });
  await caso('estado', bien.entrega_fallida, FILA('sin_chat'), [TEL, '131047', null], 'entrega_fallida', { resultado: 'sin_chat' });
  await caso('estado', { accion: 'escalar', tel: TEL, nombre: 'Ana', pregunta: 'P'.repeat(5000), aviso_wamid: 'wamid.AV' }, FILA({ id: 12 }), [TEL, 'Ana', 'P'.repeat(2000), 'wamid.AV'], 'escalar', { id: 12 });
  await caso('estado', bien.escalar, FILA({ id: null }), [TEL, null, 'precio', null], 'escalar', { id: null });
  // escalacion_tomar: EXCEPCION 1 — devuelve el telefono de la escalacion; vacio = encontrada:false
  await caso('estado', { accion: 'escalacion_tomar', wamid: 'wamid.CITADO' }, FILA({ tel: '34600111222', nombre: 'Pedro', pregunta: 'precio?', creada_en: 'x' }), ['wamid.CITADO'], 'escalacion_tomar',
    { encontrada: true, tel: '34600111222', nombre: 'Pedro', pregunta: 'precio?' });
  await caso('estado', bien.escalacion_tomar, FILA({}), [null], 'escalacion_tomar', { encontrada: false });
  for (const res of ['ok', 'ya_hecho', 'tope', 'vacio', 'sin_lead', 'hasta_invalido', 'telefono_invalido']) {
    await caso('estado', { accion: 'lead_resumen', tel: TEL, texto: 'R'.repeat(3000), hasta_id: 9 }, FILA(res), [TEL, 'R'.repeat(2000), '9'], 'lead_resumen', { resultado: res });
  }
  // recordatorio
  const U1 = '6f1c3a52-0000-4000-8000-000000000001';
  await caso('recordatorio', { accion: 'citas_recordar' }, [
    { accion_id: U1, tel: '34600111222', tipo: 'llamada', cuando_ts: new Date('2026-10-10T10:00:00Z'), ultimo_entrante_en: null, lead_id: 'x' },
    { accion_id: U1, tel: '34600111223', tipo: 'visita', cuando_ts: '2026-10-10T11:00:00+00:00', ultimo_entrante_en: new Date('2026-10-10T09:30:00Z'), nombre: ' Ana	López ' }], [], 'citas_recordar',
    { citas: [{ accion_id: U1, tel: '34600111222', tipo: 'llamada', cuando_ts: '2026-10-10T10:00:00.000Z', ultimo_entrante_en: null, nombre: null },
      { accion_id: U1, tel: '34600111223', tipo: 'visita', cuando_ts: '2026-10-10T11:00:00+00:00', ultimo_entrante_en: '2026-10-10T09:30:00.000Z', nombre: 'Ana López' }] });
  await caso('recordatorio', { accion: 'citas_recordar' }, [], [], 'citas_recordar', { citas: [] });
  reinicia(); dbCon(new Array(30).fill({ accion_id: U1, tel: '34600111222', tipo: 'llamada', cuando_ts: '2026-10-10T10:00:00Z', ultimo_entrante_en: null }));
  igual((await rq('recordatorio', { accion: 'citas_recordar' })).cuerpo.citas.length, 20, 'citas_recordar: como mucho 20');
  for (const res of ['ok', 'no_aplica', 'resultado_invalido']) await caso('recordatorio', { accion: 'cita_recordatorio_res', accion_id: U1.toUpperCase(), resultado: 'sin_ventana' }, FILA(res), [U1.toUpperCase(), 'sin_ventana'], 'cita_recordatorio_res', { resultado: res });
  // humano: el usuario es el del JWT VERIFICADO y va el último
  await caso('humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, FILA({ pausado: true, hasta: null, otro: 1 }), [TEL, 'pausar', 'ana@lawang.com'], 'pausar_humano', { pausado: true, hasta: null }, 'jwt-bueno');
  igual(authLlamadas, ['jwt-bueno'], 'Auth recibe el JWT tal cual');
  await caso('humano', { accion: 'enviar', tel: TEL, texto: 'H'.repeat(9000), wamid: W, media: { tipo: 'document', id: 'm9' } }, FILA({ ok: true }),
    [TEL, 'H'.repeat(4096), W, JSON.stringify({ tipo: 'document', id: 'm9' }), 'ana@lawang.com'], 'envio_humano', { ok: true }, 'jwt-bueno');
  await caso('humano', { accion: 'enviar', tel: TEL, wamid: W, media: { id: 'm9' } }, FILA({ ok: true }), [TEL, '', W, JSON.stringify({ tipo: 'otro', id: 'm9' }), 'ana@lawang.com'], 'envio_humano', { ok: true }, 'jwt-bueno');
  // un `usuario` en el cuerpo NO se ignora en silencio: se rechaza (400) y nunca llega a la base; lo que llega es el del token
  reinicia();
  const rU = await rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar', usuario: 'jefe@lawang.com' }, { jwt: 'jwt-bueno' });
  igual([rU.status, rU.cuerpo.error], [400, 'campo_no_permitido']); igual([llamadas.length, authLlamadas.length], [0, 0], 'el usuario del cuerpo no llega a la base ni a Auth');
  const rU2 = await rq('humano', { accion: 'enviar', tel: TEL, texto: 'x', wamid: W, usuario: 'jefe@lawang.com' }, { jwt: 'jwt-bueno' });
  igual(rU2.status, 400); igual(llamadas.length, 0);
  ok(!JSON.stringify(llamadas).includes('jefe@lawang.com'));

  // texto de Meta con un par sustituto partido por el corte o un NUL: la base recibe texto bien formado
  reinicia(); dbCon(FILA({ duplicado: false, procesado: false }));
  await rq('estado', { ...bien.mensaje_recibir, mensaje: { texto: 'a'.repeat(4095) + '\u{1F600}' + 'z\u0000z' } });
  { const enviado = JSON.parse(llamadas.pop().args[3]).texto; ok(enviado.length === 4096 && enviado === enviado.toWellFormed() && !enviado.includes('\u0000'), 'surrogate partido y NUL fuera'); }
  await rq('estado', { ...bien.eco_operadora, texto: 'b\u0000'.repeat(10) });
  igual(llamadas.pop().args[2], 'b'.repeat(10), 'NUL fuera tambien en texto plano');

  // ── S2.4 errores de negocio, formas rotas y caídas ──
  for (const [ruta, cuerpo, errores, jwt] of [
    ['estado', bien.mensaje_recibir, ['telefono_invalido', 'wamid_invalido', 'mensaje_invalido'], undefined],
    ['estado', bien.turno_estado, ['telefono_invalido', 'sin_chat'], undefined],
    ['estado', bien.turno_cerrar, ['telefono_invalido', 'wamid_invalido', 'wamid_desconocido', 'sin_chat'], undefined],
    ['estado', bien.eco_operadora, ['telefono_invalido', 'wamid_invalido'], undefined], ['estado', bien.pausar, ['telefono_invalido', 'modo_invalido', 'sin_chat'], undefined],
    ['estado', bien.baja, ['telefono_invalido'], undefined], ['estado', bien.escalar, ['telefono_invalido', 'pregunta_vacia', 'sin_chat', 'tope'], undefined],
    ['humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, ['telefono_invalido', 'sin_usuario', 'modo_invalido', 'sin_chat'], 'jwt-bueno'],
    ['humano', { accion: 'enviar', tel: TEL, texto: 'a', wamid: W }, ['telefono_invalido', 'sin_usuario', 'mensaje_vacio', 'sin_chat'], 'jwt-bueno'],
  ]) {
    for (const e of errores) {
      reinicia(); dbCon(FILA({ error: e }));
      const r = await rq(ruta, cuerpo, { jwt });
      igual([r.status, r.cuerpo], [200, { ok: false, accion: cuerpo.accion, error: e }], `${ruta}/${cuerpo.accion}: ${e} es una respuesta normal, no un 5xx`);
    }
    reinicia(); dbCon(FILA({ error: 'relation "bot_chat" does not exist' }));
    const r = await rq(ruta, cuerpo, { jwt });
    igual([r.status, r.cuerpo], [502, { error: 'db_error' }], 'un error de negocio fuera de lista es un 502 genérico');
    ok(!/relation|bot_chat/.test(r.crudo));
  }
  // formas rotas de la base: 502, nunca reenviadas
  for (const [ruta, cuerpo, malo, jwt] of [
    ['estado', bien.mensaje_recibir, FILA({ duplicado: 'no', procesado: false }), undefined], ['estado', bien.mensaje_recibir, FILA('texto'), undefined], ['estado', bien.mensaje_recibir, [], undefined],
    ['estado', bien.mensaje_recibir, [{ r: { duplicado: false, procesado: false } }, { r: {} }], undefined],
    ['estado', bien.turno_estado, FILA({ baja: false, pausado: false, esperando: false, avisar_testing: false, primer_turno: true, historial: 'x', config: {} }), undefined],
    ['estado', bien.turno_estado, FILA({ baja: false }), undefined], ['estado', bien.baja, FILA({ baja: 'otra', pausado: true }), undefined],
    ['estado', bien.turno_cerrar, FILA({ avisar: 'otro', resumir: null, repetido: false }), undefined],
    ['estado', bien.entrega_fallida, FILA('algo_raro'), undefined], ['estado', bien.lead_resumen, FILA('ok2'), undefined], ['estado', bien.lead_resumen, [], undefined],
    ['recordatorio', { accion: 'citas_recordar' }, [{ accion_id: 'no-uuid', tel: '34600111222', tipo: 'llamada', cuando_ts: 'x', ultimo_entrante_en: null }], undefined],
    ['recordatorio', { accion: 'citas_recordar' }, [{ accion_id: U1, tel: '34600111222', tipo: 'reunion', cuando_ts: 'x', ultimo_entrante_en: null }], undefined],
    ['recordatorio', { accion: 'cita_recordatorio_res', accion_id: U1, resultado: 'fallo' }, FILA('otra'), undefined],
    ['humano', { accion: 'enviar', tel: TEL, texto: 'a', wamid: W }, FILA({ ok: false }), 'jwt-bueno'],
  ]) {
    reinicia(); dbCon(malo);
    const r = await rq(ruta, cuerpo, { jwt });
    igual([ruta, cuerpo.accion, r.status, r.cuerpo], [ruta, cuerpo.accion, 502, { error: 'db_error' }], 'forma rota = 502 sin detalle');
  }
  // la base se cae o lanza el error crudo de Postgres: nada de eso sale
  for (const [ruta, cuerpo, jwt] of [['estado', bien.baja, undefined], ['recordatorio', { accion: 'citas_recordar' }, undefined], ['humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, 'jwt-bueno']]) {
    reinicia();
    M.DB.ejecuta = async () => { throw new Error('password authentication failed postgres://bot_lawang:SECRETA@host 34661569373 relation "bot_chat" violates'); };
    const r = await rq(ruta, cuerpo, { jwt });
    igual([r.status, r.cuerpo], [500, { error: 'interno' }]); ok(!/SECRETA|34661569373|postgres|relation|bot_chat/.test(r.crudo), 'la respuesta no repite el error de Postgres');
  }
  M.DB.ejecuta = async (clave, args) => { llamadas.push({ clave, args }); return guion(clave, args); };
  // la base real caída (sin URL): 503, igual en las rutas nuevas
  delete entorno.BOT_DB_URL;
  MM = await carga(); MM.AUTH.usuario = async () => 'ana@lawang.com';
  for (const [ruta, cuerpo, jwt] of [['estado', bien.baja, undefined], ['recordatorio', { accion: 'citas_recordar' }, undefined], ['humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, 'jwt-bueno']]) {
    const r = await llama(peticion(ruta, { secreto: SEC[ruta], cuerpo, extra: jwt ? { authorization: 'Bearer ' + jwt } : {} }));
    igual([ruta, r.status, r.cuerpo], [ruta, 503, { error: 'db_conexion' }], 'sin base = 503');
  }
  MM = M;

  // ── S2.5 Auth de /humano: verificada, y si no responde, 503 sin seguir ──
  const fetchOriginal = globalThis.fetch;
  const conAuth = async (resp, fn) => {
    const visto = [];
    globalThis.fetch = async (u, init) => { visto.push({ u: String(u), h: init.headers }); if (resp instanceof Error) throw resp; return resp; };
    try { return [await fn(), visto]; } finally { globalThis.fetch = fetchOriginal; }
  };
  const resp = (status, cuerpo) => new Response(JSON.stringify(cuerpo ?? {}), { status, headers: { 'content-type': 'application/json' } });
  let [q, v] = await conAuth(resp(200, { id: 'u-1', email: ' Ana@Lawang.com ' }), () => authReal('el-jwt'));
  igual(q, 'u-1', 'usuario = id verificado (estable), no el email'); igual(v.length, 1);
  igual(v[0].u, 'https://ref.supabase.co/auth/v1/user'); igual(v[0].h, { authorization: 'Bearer el-jwt', apikey: 'anon-falsa' });
  igual((await conAuth(resp(200, { email: ' x@y.com ' }), () => authReal('t')))[0], 'x@y.com', 'sin id: el email');
  igual((await conAuth(resp(401, { msg: 'bad' }), () => authReal('t')))[0], null, '401 de Auth = token que no vale');
  igual((await conAuth(resp(403), () => authReal('t')))[0], null);
  igual((await conAuth(resp(200, { id: 'u', email: 'a@b.c', is_anonymous: true }), () => authReal('t')))[0], null, 'anónimo no vale');
  igual((await conAuth(resp(200, {}), () => authReal('t')))[0], null, 'sin id ni email no vale');
  for (const caida of [resp(500), resp(502), new Error('red')]) {
    let lanzo = null;
    await conAuth(caida, async () => { try { await authReal('t'); } catch (e) { lanzo = e; } });
    ok(lanzo && lanzo.codigo === 'auth_conexion', 'Auth caída lanza auth_conexion');
  }
  igual((await conAuth(resp(200, null), () => authReal('t')))[0], null, 'respuesta vacía de Auth: no vale');
  { delete entorno.SUPABASE_ANON_KEY; let lanzo = null; try { await authReal('t'); } catch (e) { lanzo = e; } ok(lanzo && lanzo.codigo === 'auth_conexion', 'sin apikey no se intenta'); entorno.SUPABASE_ANON_KEY = 'anon-falsa'; }
  // de punta a punta: Auth caída -> 503 y la base no se toca; usuario ficticio en la cabecera `x-usuario` o en el cuerpo no cuenta
  reinicia(); M.AUTH.usuario = authReal;
  {
    const [r1] = await conAuth(new Error('red'), () => rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, { jwt: 'jwt-bueno' }));
    igual([r1.status, r1.cuerpo], [503, { error: 'auth_conexion' }]); igual(llamadas.length, 0, 'sin usuario verificado no se sigue');
    const [r2] = await conAuth(resp(401), () => rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, { jwt: 'jwt-bueno' }));
    igual([r2.status, r2.cuerpo], [401, { error: 'no_autorizado' }]); igual(llamadas.length, 0);
    dbCon(FILA({ pausado: true, hasta: null }));
    const [r3] = await conAuth(resp(200, { id: 'u-9', email: 'real@lawang.com' }), async () => llama(new Request('https://ref.supabase.co/functions/v1/bot-api/humano', {
      method: 'POST', headers: { 'x-bot-secret': SH, authorization: 'Bearer jwt-x', 'x-usuario': 'falso@x.com', 'content-type': 'application/json' }, body: JSON.stringify({ accion: 'pausar', tel: TEL, modo: 'pausar' }) })));
    igual(r3.status, 200); igual(llamadas.pop().args, [TEL, 'pausar', 'u-9'], 'solo cuenta el usuario que Auth verifica');
  }
  M.AUTH.usuario = async (jwt) => { authLlamadas.push(jwt); return jwt === 'jwt-bueno' ? 'ana@lawang.com' : null; };

  // ── S2.6 ritmo: por ruta y por teléfono; el mapa está acotado ──
  reinicia(); dbCon(FILA({ baja: 'nueva', pausado: true })); M.AJUSTES.topeTelEstado = 3;
  const cods = [];
  for (let i = 0; i < 5; i++) cods.push((await rq('estado', bien.baja)).status);
  igual(cods, [200, 200, 200, 429, 429], 'por teléfono: pasado el tope, 429');
  const r429 = await rq('estado', bien.baja); igual(r429.cuerpo, { error: 'demasiadas_peticiones' });
  igual((await rq('estado', { ...bien.baja, tel: '34600999888' })).status, 200, 'otro teléfono no se ve afectado');
  dbCon(FILA({}));   igual((await rq('estado', { accion: 'escalacion_tomar' })).status, 200, 'las acciones sin tel no cuentan por teléfono');
  M.AJUSTES.topeTelEstado = 60;
  reinicia(); M.AJUSTES.topeEstado = 3; dbCon(FILA({ baja: 'nueva', pausado: true }));
  const c2 = []; for (let i = 0; i < 5; i++) c2.push((await rq('estado', { ...bien.baja, tel: '3460000000' + i })).status);
  igual(c2, [200, 200, 200, 429, 429], 'por ruta: pasado el tope, 429'); M.AJUSTES.topeEstado = 600;
  reinicia(); M.AJUSTES.topeRecordatorio = 2; dbCon([]);
  const c3 = []; for (let i = 0; i < 3; i++) c3.push((await rq('recordatorio', { accion: 'citas_recordar' })).status);
  igual(c3, [200, 200, 429]); M.AJUSTES.topeRecordatorio = 30;
  reinicia(); M.AJUSTES.topeTelHumano = 2; dbCon(FILA({ pausado: true, hasta: null }));
  const c4 = []; for (let i = 0; i < 3; i++) c4.push((await rq('humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }, { jwt: 'jwt-bueno' })).status);
  igual(c4, [200, 200, 429]); igual(authLlamadas.length, 2, 'una petición con 429 no llega a Auth'); M.AJUSTES.topeTelHumano = 20;
  reinicia(); M.AJUSTES.maxTelefonos = 50; M.AJUSTES.topeEstado = 100000; dbCon(FILA({ baja: 'nueva', pausado: true }));
  for (let i = 0; i < 200; i++) await rq('estado', { ...bien.baja, tel: '3470000' + String(1000 + i) });
  ok(M.tamanoRitmoTel() <= 50, 'el mapa de ritmo por teléfono está acotado: ' + M.tamanoRitmoTel());
  M.AJUSTES.maxTelefonos = 5000; M.AJUSTES.topeEstado = 600; reinicia();
  // 429 y el contrato con el bot: un 429 en mensaje_recibir NO es un fallo de la base (el bot lo trata como `tope`, nunca como 5xx a Meta)
  ok(M.AJUSTES.topeTelEstado >= 60, 'tope por teléfono de la edge (60/min) muy por encima de lo humano');

  // ── S2.7 las rutas viejas siguen igual ──
  reinicia(); dbCon(FILA('creado'));
  igual((await crm({ ...base, accion: 'lead_upsert' })).cuerpo, { ok: true, accion: 'lead_upsert', resultado: 'creado' }, 'crm no cambió');
  igual((await rq('estado', { accion: 'lead_upsert', tel: TEL, msg_id: W })).status, 400, 'lead_upsert no existe en /estado');

  // ── S2.8 el mismo dato en todos los sitios: las sentencias, las firmas, los grants, los errores y la prueba SQL ──
  {
    const fuenteS2 = leer('supabase', 'functions', 'bot-api', 'index.ts');
    const bloque = fuenteS2.slice(fuenteS2.indexOf('const SQL = {'), fuenteS2.indexOf('} as const;'));
    const sentencias = [...bloque.matchAll(/^\s+(\w+): '(select [^']*)',?/gm)].map((m) => ({ clave: m[1], sql: m[2] }));
    const s2 = sentencias.filter((s) => !['catalogo', 'lead_upsert', 'lead_nota', 'lead_cita', 'importar_chat', 'importar_config', 'importar_cuadre', 'consentimiento_preguntar', 'consentimiento_enviada', 'consentimiento_responder', 'seguimiento_candidatos', 'seguimiento_reservar', 'seguimiento_registrar', 'verificar_humano'].includes(s.clave));
    igual(s2.map((s) => s.clave), ['mensaje_recibir', 'turno_estado', 'turno_cerrar', 'eco_operadora', 'pausar', 'baja', 'entrega_fallida', 'escalar', 'escalacion_tomar', 'lead_resumen', 'citas_recordar', 'cita_recordatorio_res', 'pausar_humano', 'envio_humano'], 'las 14 sentencias de S2');
    const migF = (f) => leer('supabase', 'migrations', f);
    const migs = [migF('20261010110000_bot_sin_redis_s1_esquema.sql'), migF('20261010110100_bot_sin_redis_s1_ajustes.sql')];
    const norm = (t) => t.trim().toLowerCase().replace(/^integer$/, 'int').replace(/^int4$/, 'int');
    const defsFn = (nombre) => {   // la ULTIMA definicion entre las migraciones (escalacion_tomar, pausar y pausar_humano se redefinieron en la de ajustes)
      let ultima = null;
      for (const sql of migs) {
        const re = new RegExp('create or replace function public\\.' + nombre + '\\(([\\s\\S]*?)\\)\\s*returns', 'g');
        let m; while ((m = re.exec(sql))) ultima = { sql, args: m[1], inicio: m.index };
      }
      assert.ok(ultima, 'no encuentro la función ' + nombre);
      const fin = ultima.sql.indexOf('$f$;', ultima.inicio + 10);
      const cuerpo = ultima.sql.slice(ultima.inicio, fin);
      const params = ultima.args.trim() === '' ? [] : ultima.args.split(',').map((p) => norm(p.trim().replace(/^p_\w+\s+/, '').split(/\s+/)[0]));
      return { params, cuerpo };
    };
    const jsonErrores = {}, textoRes = {};
    for (const s of s2) {
      const nombre = /public\.(\w+)\(/.exec(s.sql)[1];
      const { params, cuerpo } = defsFn(nombre);
      const casts = [...s.sql.matchAll(/\$(\d+)((?:::\w+)+)/g)].sort((a, b) => a[1] - b[1]).map((m) => norm(m[2].split('::').pop()));   // el ULTIMO cast es el tipo de la firma ($N::text::jsonb -> jsonb)
      igual(casts, params, `${nombre}: los casts de la sentencia coinciden con la firma real`);
      const tieneGrant = migs.some((sql) => new RegExp('grant execute on function public\\.' + nombre + '\\(([^)]*)\\)\\s+to bot_lawang').test(sql) &&
        sql.match(new RegExp('grant execute on function public\\.' + nombre + '\\(([^)]*)\\)\\s+to bot_lawang'))[1].split(',').map((p) => norm(p)).filter(Boolean).join() === params.join());
      ok(tieneGrant, `${nombre}: EXECUTE concedido a bot_lawang con la misma firma`);
      jsonErrores[s.clave] = [...cuerpo.matchAll(/'error',\s*'([a-z_]+)'/g)].map((m) => m[1]);
      textoRes[s.clave] = [...cuerpo.matchAll(/return\s+(?:case when [^;]*? then )?'([a-z_]+)'/g)].map((m) => m[1])
        .concat([...cuerpo.matchAll(/then '([a-z_]+)'|else '([a-z_]+)'/g)].map((m) => m[1] || m[2]));
    }
    // cada código de negocio que la base puede devolver tiene que estar en la lista de la edge (si no, sería un 502 inexplicable)
    const defs = M.LISTA_CERRADA;
    const a2 = (ruta, acc) => defs[ruta][acc];
    const ligado = { mensaje_recibir: ['estado', 'mensaje_recibir'], turno_estado: ['estado', 'turno_estado'], turno_cerrar: ['estado', 'turno_cerrar'], eco_operadora: ['estado', 'eco_operadora'],
      pausar: ['estado', 'pausar'], baja: ['estado', 'baja'], escalar: ['estado', 'escalar'], escalacion_tomar: ['estado', 'escalacion_tomar'], pausar_humano: ['humano', 'pausar'], envio_humano: ['humano', 'enviar'] };
    for (const [clave, [ruta, acc]] of Object.entries(ligado)) {
      const d = a2(ruta, acc);
      igual(d.sql, clave, `${ruta}/${acc} usa la sentencia ${clave}`);
      for (const e of jsonErrores[clave]) ok(d.errores.includes(e), `${ruta}/${acc}: la función SQL devuelve error '${e}' y la edge no lo acepta`);
      for (const e of d.errores) ok(jsonErrores[clave].includes(e), `${ruta}/${acc}: la edge acepta error '${e}' que la función SQL no devuelve`);
    }
    for (const [clave, [ruta, acc]] of Object.entries({ entrega_fallida: ['estado', 'entrega_fallida'], lead_resumen: ['estado', 'lead_resumen'], cita_recordatorio_res: ['recordatorio', 'cita_recordatorio_res'] })) {
      const d = a2(ruta, acc);
      for (const e of new Set(textoRes[clave])) ok(d.resultados.includes(e), `${ruta}/${acc}: la función SQL devuelve '${e}' y la edge no lo acepta`);
      for (const e of d.resultados) ok(textoRes[clave].includes(e), `${ruta}/${acc}: la edge acepta '${e}' que la función SQL no devuelve`);
    }
    // la prueba contra la base real ejecuta LITERALMENTE las mismas sentencias
    const prueba = leer('supabase', 'pruebas', 'bot_api_s2.sql');
    for (const s of s2) ok(prueba.includes(s.sql), `bot_api_s2.sql ejecuta la sentencia de ${s.clave} tal cual`);
    // sin secretos, ni service_role ni PostgREST ni consola en el código nuevo (la regla de más abajo ya lo vigila en todo el fichero)
    ok(!/SERVICE_ROLE/.test(fuenteS2.replace(/\/\/.*$/gm, '')));
    ok(fuenteS2.includes("'BOT_API_SECRET_ESTADO'") && fuenteS2.includes("'BOT_API_SECRET_RECORDATORIO'") && fuenteS2.includes("'BOT_API_SECRET_HUMANO'"));
  }

  // ═══ S12 — consentimiento de seguimiento y reenganche (LAW-507) ═══════════════════════════════════════════════
  {
    todos(); reinicia();
    const VER = 'CONSENT-SEGUIMIENTO-2026-10-09-v1';
    const TXT = 'Would you like us to follow up here on WhatsApp? Please reply YES or NO.';
    // 1. el modelo/bot NO puede escribir el estado: ninguna accion de S12 acepta una clave `estado` (ni `consentimiento`, ni `si`)
    const buenosS12 = [
      ['estado', { accion: 'consentimiento_preguntar', tel: TEL, version: VER, idioma: 'en', texto: TXT }],
      ['estado', { accion: 'consentimiento_enviada', tel: TEL, wamid: W }],
      ['estado', { accion: 'consentimiento_responder', tel: TEL, wamid: W, texto: 'si' }],
      ['recordatorio', { accion: 'seguimiento_candidatos' }],
      ['recordatorio', { accion: 'seguimiento_reservar', tel: TEL, plantilla: '48h' }],
      ['recordatorio', { accion: 'seguimiento_registrar', tel: TEL, plantilla: '48h', wamid: W, resultado: 'enviado', texto: 'x' }],
    ];
    for (const [ruta, cuerpo] of buenosS12) {
      for (const extra of [{ estado: 'si' }, { consentimiento: 'si' }, { consent_estado: 'si' }, { resultado_forzado: 'si' }]) {
        const r = await rq(ruta, { ...cuerpo, ...extra });
        igual([cuerpo.accion, r.status, r.cuerpo.error], [cuerpo.accion, 400, 'campo_no_permitido'], 'una clave de estado/etiqueta del modelo es 400');
      }
    }
    igual(llamadas.length, 0, 'nada de eso llego a la base');
    // las acciones viven SOLO en su ruta
    igual((await rq('recordatorio', buenosS12[0][1])).status, 400); igual((await rq('estado', buenosS12[3][1])).status, 400);
    igual((await rq('humano', buenosS12[0][1], { jwt: 'jwt-bueno' })).status, 400, 'ni /humano ni /importar las tienen');
    // 2. validacion a fondo
    for (const c of [{ version: 'OTRA' }, { version: undefined }, { idioma: 'id' }, { idioma: 'fr' }, { texto: '' }, { texto: '   ' }, { texto: 5 }, { repregunta: 'si' }]) {
      igual((await rq('estado', { ...buenosS12[0][1], ...c })).status, 400, 'preguntar ' + JSON.stringify(c));
    }
    for (const c of [{ wamid: undefined }, { wamid: 'con espacios' }, { repregunta: 1 }]) igual((await rq('estado', { ...buenosS12[1][1], ...c })).status, 400, 'enviada ' + JSON.stringify(c));
    for (const c of [{ wamid: undefined }, { cita: 'con espacios' }, { cita: 5 }, { texto: 5 }]) igual((await rq('estado', { ...buenosS12[2][1], ...c })).status, 400, 'responder ' + JSON.stringify(c));
    for (const c of [{ plantilla: '24h' }, { plantilla: undefined }, { plantilla: '7D' }]) igual((await rq('recordatorio', { ...buenosS12[4][1], ...c })).status, 400, 'reservar ' + JSON.stringify(c));
    for (const c of [{ plantilla: '3d' }, { resultado: 'ok' }, { resultado: undefined }, { wamid: undefined }, { wamid: 'con espacios' }, { texto: 5 }]) igual((await rq('recordatorio', { ...buenosS12[5][1], ...c })).status, 400, 'registrar ' + JSON.stringify(c));
    igual((await rq('recordatorio', { accion: 'seguimiento_candidatos', tel: TEL })).status, 400, 'candidatos: sin entrada de telefono');
    igual(llamadas.length, 0, 'ningun cuerpo invalido llego a la base');
    // 3. lo que llega a la base y lo que sale
    await caso('estado', { accion: 'consentimiento_preguntar', tel: TEL, version: VER, idioma: 'es', texto: 'T'.repeat(2000), repregunta: true }, FILA({ ok: true, x: 1 }),
      [TEL, VER, 'es', 'T'.repeat(1500), 'true'], 'consentimiento_preguntar', { ok: true });
    await caso('estado', buenosS12[0][1], FILA({ ok: true }), [TEL, VER, 'en', TXT, 'false'], 'consentimiento_preguntar', { ok: true });
    await caso('estado', { ...buenosS12[1][1], repregunta: true }, FILA({ ok: true }), [TEL, W, 'true'], 'consentimiento_enviada', { ok: true });
    await caso('estado', buenosS12[1][1], FILA({ ok: true }), [TEL, W, 'false'], 'consentimiento_enviada', { ok: true });
    for (const res of ['si', 'no', 'repreguntar', 'no_cuenta', 'sin_efecto']) {
      await caso('estado', { accion: 'consentimiento_responder', tel: TEL, wamid: W, texto: 'Sí', cita: 'wamid.Q' }, FILA({ resultado: res, estado: res === 'si' ? 'si' : 'preguntado', interno: 'x' }),
        [TEL, W, 'Sí', 'wamid.Q'], 'consentimiento_responder', { resultado: res, estado: res === 'si' ? 'si' : 'preguntado' });
    }
    await caso('estado', { accion: 'consentimiento_responder', tel: TEL, wamid: W }, FILA({ resultado: 'no_cuenta', estado: 'preguntado' }), [TEL, W, '', null], 'consentimiento_responder', { resultado: 'no_cuenta', estado: 'preguntado' });
    await caso('recordatorio', { accion: 'seguimiento_reservar', tel: TEL, plantilla: '7d' }, FILA({ ok: true, idioma: 'es', nombre: ' Ana\n', otro: 1 }), [TEL, '7d'], 'seguimiento_reservar', { idioma: 'es', nombre: 'Ana' });
    await caso('recordatorio', { accion: 'seguimiento_reservar', tel: TEL, plantilla: '48h' }, FILA({ ok: true, idioma: 'fr', nombre: null }), [TEL, '48h'], 'seguimiento_reservar', { idioma: 'en', nombre: null });
    await caso('recordatorio', { accion: 'seguimiento_registrar', tel: TEL, plantilla: '48h', wamid: W, resultado: 'enviado', texto: 'x'.repeat(500) }, FILA('ok'), [TEL, '48h', W, 'enviado', 'x'.repeat(200)], 'seguimiento_registrar', { resultado: 'ok' });
    await caso('recordatorio', { accion: 'seguimiento_registrar', tel: TEL, plantilla: '7d', resultado: 'fallo' }, FILA('no_aplica'), [TEL, '7d', null, 'fallo', null], 'seguimiento_registrar', { resultado: 'no_aplica' });
    // candidatos: EXCEPCION 3, <=20 y forma fija
    await caso('recordatorio', { accion: 'seguimiento_candidatos' }, [
      { tel: '34600111222', plantilla: '48h', idioma: 'en', nombre: null, consent_texto: 'no sale' },
      { tel: '34600111223', plantilla: '7d', idioma: 'es', nombre: ' Ana\tLópez ' }], [], 'seguimiento_candidatos',
      { candidatos: [{ tel: '34600111222', plantilla: '48h', idioma: 'en', nombre: null }, { tel: '34600111223', plantilla: '7d', idioma: 'es', nombre: 'Ana López' }] });
    reinicia(); dbCon(new Array(30).fill({ tel: '34600111222', plantilla: '48h', idioma: 'en', nombre: null }));
    igual((await rq('recordatorio', { accion: 'seguimiento_candidatos' })).cuerpo.candidatos.length, 20, 'candidatos: como mucho 20');
    // 4. errores de negocio permitidos y fuera de lista
    for (const [ruta, cuerpo, errores] of [
      ['estado', buenosS12[0][1], ['telefono_invalido', 'version_desconocida', 'no_procede', 'sin_chat']],
      ['estado', buenosS12[1][1], ['telefono_invalido', 'wamid_invalido', 'no_procede', 'sin_chat']],
      ['estado', buenosS12[2][1], ['telefono_invalido', 'wamid_invalido', 'sin_chat']],
      ['recordatorio', buenosS12[4][1], ['telefono_invalido', 'plantilla_invalida', 'no_procede', 'sin_chat']],
    ]) {
      for (const e of errores) { reinicia(); dbCon(FILA({ error: e })); const r = await rq(ruta, cuerpo); igual([r.status, r.cuerpo], [200, { ok: false, accion: cuerpo.accion, error: e }], cuerpo.accion + ': ' + e); }
      reinicia(); dbCon(FILA({ error: 'relation "bot_chat" does not exist' })); const r = await rq(ruta, cuerpo);
      igual([r.status, r.cuerpo], [502, { error: 'db_error' }], cuerpo.accion + ': error crudo = 502 generico'); ok(!/relation|bot_chat/.test(r.crudo));
    }
    // formas rotas = 502
    for (const [ruta, cuerpo, mala] of [
      ['estado', buenosS12[2][1], FILA({ resultado: 'quiza', estado: 'preguntado' })], ['estado', buenosS12[2][1], FILA({ resultado: 'si', estado: 'inventado' })],
      ['estado', buenosS12[0][1], FILA({ ok: false })], ['estado', buenosS12[1][1], FILA('texto')],
      ['recordatorio', { accion: 'seguimiento_candidatos' }, [{ tel: 'abc', plantilla: '48h', idioma: 'en' }]],
      ['recordatorio', { accion: 'seguimiento_candidatos' }, [{ tel: '34600111222', plantilla: '24h', idioma: 'en' }]],
      ['recordatorio', { accion: 'seguimiento_candidatos' }, [{ tel: '34600111222', plantilla: '48h', idioma: 'id' }]],
      ['recordatorio', buenosS12[5][1], FILA('rarisimo')],
    ]) { reinicia(); dbCon(mala); const r = await rq(ruta, cuerpo); igual(r.status, 502, 'forma rota de ' + cuerpo.accion); }
    // turno_estado: el campo nuevo es OPCIONAL (base anterior a la migracion) y, si llega, solo pasa con la forma exacta
    const BASE_EST = { baja: false, pausado: false, esperando: false, avisar_testing: false, primer_turno: false, historial: [],
      config: { extra: '', bienvenida: '', pausa_horas: 0, resumen_cada_n: 30, fallos_alarma: 3, version: 1, actualizado_en: '2026-10-09T10:00:00+00:00' } };
    reinicia(); dbCon(FILA(BASE_EST));
    ok(!('consentimiento' in (await rq('estado', { accion: 'turno_estado', tel: TEL })).cuerpo), 'sin el campo en la base, la edge no lo inventa');
    reinicia(); dbCon(FILA({ ...BASE_EST, consentimiento: { estado: 'preguntado', repreguntado: false, puede_preguntar: false, x: 1 } }));
    igual((await rq('estado', { accion: 'turno_estado', tel: TEL })).cuerpo.consentimiento, { estado: 'preguntado', repreguntado: false, puede_preguntar: false }, 'consentimiento con forma fija');
    reinicia(); dbCon(FILA({ ...BASE_EST, consentimiento: { estado: 'raro', repreguntado: false, puede_preguntar: false } }));
    igual((await rq('estado', { accion: 'turno_estado', tel: TEL })).status, 502, 'estado de consentimiento fuera de lista = 502');
    // 5. el mismo dato en todos los sitios: sentencias = firmas = grants = errores de la migracion
    const mig = leer('supabase', 'migrations', '20261010170000_bot_sin_redis_s12_consentimiento.sql');
    const fuente = leer('supabase', 'functions', 'bot-api', 'index.ts');
    const bl = fuente.slice(fuente.indexOf('const SQL = {'), fuente.indexOf('} as const;'));
    const sents = [...bl.matchAll(/^\s+(\w+): '(select [^']*)',?/gm)].map((m) => ({ clave: m[1], sql: m[2] })).filter((x) => /^(consentimiento_|seguimiento_)/.test(x.clave));
    igual(sents.map((x) => x.clave), ['consentimiento_preguntar', 'consentimiento_enviada', 'consentimiento_responder', 'seguimiento_candidatos', 'seguimiento_reservar', 'seguimiento_registrar']);
    const norm = (t) => t.trim().toLowerCase();
    for (const x of sents) {
      const nombre = /public\.(\w+)\(/.exec(x.sql)[1];
      const m = new RegExp('create or replace function public\\.' + nombre + '\\(([\\s\\S]*?)\\)\\s*returns').exec(mig);
      ok(m, 'la migracion define ' + nombre);
      const params = m[1].trim() === '' ? [] : m[1].split(',').map((p) => norm(p.trim().replace(/^p_\w+\s+/, '').split(/\s+/)[0]));
      const casts = [...x.sql.matchAll(/\$(\d+)((?:::\w+)+)/g)].sort((a, b) => a[1] - b[1]).map((c) => norm(c[2].split('::').pop()));
      igual(casts, params, nombre + ': los casts coinciden con la firma real');
      const g = new RegExp('grant execute on function public\\.' + nombre + '\\(([^)]*)\\)\\s+to bot_lawang').exec(mig);
      ok(g && g[1].split(',').map(norm).join() === params.join(), nombre + ': EXECUTE solo para bot_lawang con la misma firma');
      ok(new RegExp('revoke all on function public\\.' + nombre + '\\([^)]*\\)\\s+from public, anon, authenticated, service_role').test(mig), nombre + ': REVOKE a PUBLIC');
      const cuerpo = mig.slice(m.index, mig.indexOf('$f$;', m.index + 10));
      ok(/security definer set search_path = ''/.test(cuerpo.replace(/\s+/g, ' ').replace('language plpgsql volatile', 'language plpgsql')), nombre + ': DEFINER con search_path fijo');
    }
    // los errores del SQL = los de la edge
    const erroresSql = (nombre) => { const m = new RegExp('create or replace function public\\.' + nombre + '\\(').exec(mig); const c = mig.slice(m.index, mig.indexOf('$f$;', m.index + 10)); return new Set([...c.matchAll(/'error',\s*'([a-z_]+)'/g)].map((x) => x[1])); };
    for (const [ruta, acc, sqlN] of [['estado', 'consentimiento_preguntar', 'bot_consentimiento_preguntar'], ['estado', 'consentimiento_enviada', 'bot_consentimiento_enviada'],
      ['estado', 'consentimiento_responder', 'bot_consentimiento_responder'], ['recordatorio', 'seguimiento_reservar', 'bot_seguimiento_reservar']]) {
      const d = M.LISTA_CERRADA[ruta][acc]; const sql = erroresSql(sqlN);
      for (const e of sql) ok(d.errores.includes(e), `${acc}: la funcion SQL devuelve '${e}' y la edge no lo acepta`);
      for (const e of d.errores) ok(sql.has(e), `${acc}: la edge acepta '${e}' que la funcion SQL no devuelve`);
    }
    // ninguna funcion SQL del consentimiento tiene un parametro `estado`
    ok(!/function public\.bot_(consentimiento|seguimiento)_\w+\([^)]*estado/.test(mig), 'ninguna funcion recibe un estado');
    // la prueba contra la base real ejecuta las mismas funciones
    const prueba = leer('supabase', 'pruebas', 'bot_sin_redis_s12.sql');
    for (const x of sents) ok(prueba.includes(/public\.(\w+)\(/.exec(x.sql)[1]), 'bot_sin_redis_s12.sql prueba ' + x.clave);
    ok(!/SERVICE_ROLE/.test(fuente.replace(/\/\/.*$/gm, '')));
  }

  // ═══ verificar (10-oct-2026) — ¿esta PERSONA (JWT) tiene la casilla bot_escribir? Acción de /estado con JWT ══════════════════════
  {
    todos(); reinicia();
    const V = { accion: 'verificar', permiso: 'bot_escribir' };
    const authSalvado = M.AUTH.usuario;
    // 1. 401 sin secreto, con el de OTRA ruta, sin JWT utilizable, con JWT que Auth rechaza; ninguno toca la base
    for (const s of [undefined, '', 'malo', SH, SRE, SC, SR, SE + 'x']) igual((await rq('estado', V, { secreto: s, jwt: 'jwt-bueno' })).status, 401, 'verificar con secreto ' + JSON.stringify(s));
    igual((await rq('humano', V, { jwt: 'jwt-bueno' })).status, 400, 'verificar vive SOLO en /estado (en /humano no existe)');
    igual((await rq('recordatorio', V, { jwt: 'jwt-bueno' })).status, 400);
    for (const jwt of [undefined, '', 'x'.repeat(5000)]) igual((await rq('estado', V, { jwt })).status, 401, 'verificar sin JWT utilizable: 401');
    igual((await rq('estado', V, { jwt: 'jwt-falso' })).status, 401, 'JWT que Auth rechaza: 401');
    igual(llamadas.length, 0, 'ningún 401 llegó a la base');
    // 2. el usuario NUNCA viaja en el cuerpo; esquema cerrado; el permiso es una lista de UNO
    reinicia();
    for (const extra of [{ usuario: 'jefe@lawang.com' }, { email: 'a@b.c' }, { user_id: 'u-1' }, { tel: TEL }, { herramientas: ['bot_escribir'] }]) {
      const r = await rq('estado', { ...V, ...extra }, { jwt: 'jwt-bueno' });
      igual([r.status, r.cuerpo.error], [400, 'campo_no_permitido'], 'verificar: clave de más ' + Object.keys(extra)[0]);
    }
    for (const permiso of [undefined, '', 'leads', 'bot_configurar', 'super_admin', ['bot_escribir'], 5, 'bot_escribir ']) {
      igual((await rq('estado', { accion: 'verificar', permiso }, { jwt: 'jwt-bueno' })).status, 400, 'permiso fuera de lista ' + JSON.stringify(permiso));
    }
    igual([llamadas.length, authLlamadas.length], [0, 0], 'ningún cuerpo inválido llegó a la base ni a Auth');
    // 3. lo que llega a la base (usuario VERIFICADO primero, permiso después) y lo que sale (solo permitido + email)
    reinicia(); dbCon(FILA({ permitido: true, email: 'ana@lawang.com', herramientas: ['x'], rol: 'super_admin' }));
    let r = await rq('estado', V, { jwt: 'jwt-bueno' });
    igual(llamadas, [{ clave: 'verificar_humano', args: ['ana@lawang.com', 'bot_escribir'] }], 'sentencia y argumentos: el usuario del JWT va primero');
    igual(r.cuerpo, { ok: true, accion: 'verificar', permitido: true, email: 'ana@lawang.com' }, 'salida fija: nunca herramientas ni rol');
    reinicia(); dbCon(FILA({ permitido: false, email: 'no@debe.salir' }));
    r = await rq('estado', V, { jwt: 'jwt-bueno' });
    igual([r.status, r.cuerpo], [200, { ok: true, accion: 'verificar', permitido: false, email: null }], 'sin permiso: 200 con permitido:false y SIN email');
    reinicia(); dbCon(FILA({ permitido: false, email: null }));
    igual((await rq('estado', V, { jwt: 'jwt-bueno' })).cuerpo.permitido, false, 'usuario sin ficha');
    // error de negocio de la base y formas rotas
    reinicia(); dbCon(FILA({ error: 'permiso_invalido' }));
    igual((await rq('estado', V, { jwt: 'jwt-bueno' })).cuerpo, { ok: false, accion: 'verificar', error: 'permiso_invalido' });
    for (const rota of [FILA({ permitido: 'si', email: 'a@b.c' }), FILA({ email: 'a@b.c' }), FILA({ permitido: true, email: 5 }), FILA({ error: 'relation "usuarios" does not exist' }), FILA('texto'), []]) {
      reinicia(); dbCon(rota); r = await rq('estado', V, { jwt: 'jwt-bueno' });
      igual([r.status, r.cuerpo], [502, { error: 'db_error' }], 'forma rota = 502 genérico'); ok(!/relation|usuarios/.test(r.crudo));
    }
    // base caída: 503 sin detalle (el bot falla CERRADO)
    reinicia(); delete entorno.BOT_DB_URL;
    MM = await carga(); MM.AUTH.usuario = async () => 'ana@lawang.com';
    r = await rq('estado', V, { jwt: 'jwt-bueno' }); igual([r.status, r.cuerpo], [503, { error: 'db_conexion' }], 'base caída = 503 sin detalle'); ok(!/Error|stack/.test(r.crudo));
    MM = M;
    // 4. Auth caída = 503 auth_conexion y la base no se toca; Auth que rechaza = 401; solo cuenta el usuario que Auth verifica
    M.AUTH.usuario = authReal;
    reinicia(); dbCon(FILA({ permitido: true, email: 'real@lawang.com' }));
    {
      const [r1] = await conAuth(new Error('red'), () => rq('estado', V, { jwt: 'jwt-bueno' }));
      igual([r1.status, r1.cuerpo], [503, { error: 'auth_conexion' }], 'Auth caída'); igual(llamadas.length, 0, 'sin usuario verificado no se sigue');
      const [r2] = await conAuth(resp(401), () => rq('estado', V, { jwt: 'jwt-bueno' }));
      igual([r2.status, r2.cuerpo], [401, { error: 'no_autorizado' }]); igual(llamadas.length, 0);
      const [r3] = await conAuth(resp(200, { id: 'u-9', email: 'real@lawang.com' }), async () => llama(new Request('https://ref.supabase.co/functions/v1/bot-api/estado', {
        method: 'POST', headers: { 'x-bot-secret': SE, authorization: 'Bearer jwt-x', 'x-usuario': 'falso@x.com', 'content-type': 'application/json' }, body: JSON.stringify(V) })));
      igual(r3.status, 200); igual(llamadas.pop().args, ['u-9', 'bot_escribir'], 'solo cuenta el usuario que Auth verifica');
    }
    M.AUTH.usuario = async (jwt) => { authLlamadas.push(jwt); return jwt === 'jwt-bueno' ? 'ana@lawang.com' : null; };
    // 5. ritmo propio: pasado el tope 429 y NUNCA llega a Auth; el resto de /estado no se ve afectado
    reinicia(); M.AJUSTES.topeVerificar = 2; dbCon(FILA({ permitido: true, email: 'ana@lawang.com' }));
    const cods = []; for (let i = 0; i < 4; i++) cods.push((await rq('estado', V, { jwt: 'jwt-bueno' })).status);
    igual(cods, [200, 200, 429, 429], 'tope propio de verificar'); igual(authLlamadas.length, 2, 'una petición con 429 no llega a Auth');
    dbCon(FILA({ baja: 'nueva', pausado: true })); igual((await rq('estado', { accion: 'baja', tel: TEL, wamid: W })).status, 200, 'las demás acciones de /estado siguen igual');
    M.AJUSTES.topeVerificar = 60; reinicia();
    // 6. el resto de /estado NO exige JWT (el bot sigue llamando sin él)
    dbCon(FILA({ baja: 'nueva', pausado: true })); igual((await rq('estado', { accion: 'baja', tel: TEL, wamid: W })).status, 200);
    igual(authLlamadas.length, 0, 'baja no consulta a Auth');
    // 7. el mismo dato en todos los sitios: sentencia, función SQL, grant, errores y prueba SQL
    {
      const fuente = leer('supabase', 'functions', 'bot-api', 'index.ts');
      const sentencia = /verificar_humano: '(select [^']*)'/.exec(fuente)[1];
      igual(M.SQL.verificar_humano, sentencia);
      const mig = leer('supabase', 'migrations', '20261009235701_bot_humano_verificar.sql');
      ok(/create or replace function public\.bot_humano_verificar\(p_usuario text, p_permiso text\)\s*returns jsonb/.test(mig), 'la firma de la función SQL = la sentencia (text, text)');
      ok(sentencia.includes('public.bot_humano_verificar($1::text, $2::text)'));
      ok(/security definer set search_path = ''/.test(mig), 'SECURITY DEFINER con search_path fijo');
      ok(/revoke all on function public\.bot_humano_verificar\(text, text\)\s+from public, anon, authenticated, service_role;/.test(mig), 'REVOKE de PUBLIC y de los roles de la API');
      ok(/grant execute on function public\.bot_humano_verificar\(text, text\) to bot_lawang;/.test(mig), 'EXECUTE solo para bot_lawang');
      igual((mig.match(/grant execute/g) ?? []).length, 1, 'un solo GRANT en la migración');
      const errs = [...mig.matchAll(/'error',\s*'([a-z_]+)'/g)].map((m) => m[1]);
      igual(errs, M.LISTA_CERRADA.estado.verificar.errores, 'errores de negocio: función SQL = edge');
      igual(M.LISTA_CERRADA.estado.verificar.claves, ['accion', 'permiso']);
      ok(/p_permiso is distinct from 'bot_escribir'/.test(mig), 'la función SQL solo acepta bot_escribir, igual que la edge');
      const prueba = leer('supabase', 'pruebas', 'bot_humano_verificar.sql');
      ok(prueba.includes('public.bot_humano_verificar(') && prueba.includes('_bot_humano_regla'), 'la prueba SQL ejercita la función y la regla');
      ok(!/herramientas/.test(JSON.stringify(M.LISTA_CERRADA.estado.verificar.forma({ permitido: true, email: 'a@b.c', herramientas: ['x'] }))), 'la salida no lleva herramientas');
    }
    M.AUTH.usuario = authSalvado; reinicia();
  }

  // ═══ S5-puente — ruta /importar (TEMPORAL, LAW-507): secreto propio, esquema cerrado a fondo, sin error crudo ═══════════════════
  {
    const SI = 'sec-importar-falso';
    const conI = () => fija({ BOT_API_SECRET_CATALOGO: SC, BOT_API_SECRET_CRM: SR, BOT_API_SECRET_ESTADO: SE, BOT_API_SECRET_RECORDATORIO: SRE, BOT_API_SECRET_HUMANO: SH,
      BOT_API_SECRET_IMPORTAR: SI, SUPABASE_URL: 'https://ref.supabase.co', SUPABASE_ANON_KEY: 'anon-falsa' });
    const im = (cuerpo, o = {}) => llama(peticion('importar', { metodo: o.metodo ?? 'POST', secreto: 'secreto' in o ? o.secreto : SI, cuerpo }));
    const CHAT = { nombre_perfil: 'Ana', intent: 'interested', ultimo_mensaje: 'hola', ultimo_por: 'cliente', creado_ms: 1760000000000, actualizado_ms: 1760000100000, archivado: false,
      ultimo_entrante_ms: 1760000050000, esperando: false, pausado: true, pausa_hasta_ms: null, baja_ms: null, baja_acuse: false, seguimientos: 1, aviso_nivel: 2, aviso_testing: false };
    const MSG = { rol: 'user', por: 'cliente', por_usuario: null, contenido: 'Hola', media: null, wamid: 'wamid.X1', ts_ms: 1760000000000 };
    const ESC = { nombre: 'Ana', pregunta: 'precio?', aviso_wamid: 'wamid.AV1', creada_ms: 1760000000000 };
    const bienI = {
      chat: { accion: 'chat', tel: TEL, chat: CHAT, mensajes: [MSG], escalaciones: [ESC] },
      config: { accion: 'config', config: { extra: 'x', bienvenida: 'b', pausa_horas: 12, updated_by: 'a@b.c' },
        log: [{ ts_ms: 1760000000000, by: 'a@b.c', prev: { extra: '', bienvenida: '', pausa_horas: 0 }, next: { extra: 'x', bienvenida: 'b', pausa_horas: 12 } }] },
      cuadre: { accion: 'cuadre', tel: TEL },
    };
    const RESP_CHAT = { ok: true, chat: 'creado', lead: 'sin_lead', mensajes: { recibidos: 1, insertados: 1, omitidos_posteriores: false }, escalaciones: { recibidas: 1, insertadas: 1 }, interno: 'no sale' };

    // 1. 401: sin secreto configurado, y el secreto de /importar no abre ninguna otra ruta ni al revés
    todos(); reinicia();
    for (const s of [undefined, '', 'x', SE, SRE, SH, SC, SR, SI]) igual((await im(bienI.chat, { secreto: s })).status, 401, 'sin BOT_API_SECRET_IMPORTAR configurado todo es 401');
    conI(); reinicia();
    const c401 = new Set();
    for (const s of [undefined, '', '   ', 'malo', SE, SRE, SH, SC, SR, SI + 'x']) { const r = await im(bienI.chat, { secreto: s }); igual(r.status, 401, 'importar con ' + JSON.stringify(s)); c401.add(r.crudo); }
    igual((await im(bienI.chat, { metodo: 'GET' })).status, 401, 'GET con secreto bueno: 401');
    igual(c401.size, 1); ok(c401.has(JSON.stringify({ error: 'no_autorizado' })), 'mismo cuerpo que el resto de 401');
    igual(llamadas.length, 0, 'ningun 401 llego a la base');
    for (const [ruta, cuerpo] of [['estado', { accion: 'baja', tel: TEL, wamid: W }], ['recordatorio', { accion: 'citas_recordar' }], ['crm', { accion: 'lead_upsert', tel: TEL, msg_id: W }],
      ['catalogo', {}], ['humano', { accion: 'pausar', tel: TEL, modo: 'pausar' }]]) {
      igual((await llama(peticion(ruta, { secreto: SI, cuerpo, extra: { authorization: 'Bearer jwt-bueno' } }))).status, 401, 'el secreto de /importar no abre /' + ruta);
    }
    conI(); fija({ BOT_API_SECRET_IMPORTAR: '   ' }); igual((await im(bienI.chat, { secreto: '' })).status, 401, 'secreto en blanco no autentica');
    conI(); reinicia();

    // 2. lista y esquema cerrados (cada rechazo sin tocar la base)
    for (const a of ['borrar', 'sql', 'mensaje_recibir', '__proto__', 'constructor', '', undefined, 5]) igual((await im({ ...bienI.chat, accion: a })).status, 400, 'accion fuera de lista ' + String(a));
    igual((await im('{no json')).status, 400); igual((await im('[1]')).status, 400);
    for (const [a, cuerpo] of Object.entries(bienI)) {
      igual([a, (await im({ ...cuerpo, usuario: 'x' })).cuerpo.error], [a, 'campo_no_permitido']);
    }
    const malos = [
      ['chat', { tel: 'abc' }, 'tel'], ['chat', { tel: undefined }, 'tel'], ['chat', { chat: undefined }, 'chat'], ['chat', { chat: [] }, 'chat'], ['chat', { chat: { ...CHAT, extra: 1 } }, 'chat'],
      ['chat', { chat: { ...CHAT, pausado: 'si' } }, 'chat'], ['chat', { chat: { ...CHAT, seguimientos: 'abc' } }, 'chat'], ['chat', { chat: { ...CHAT, seguimientos: 1.5 } }, 'chat'],
      ['chat', { chat: { ...CHAT, aviso_nivel: 3 } }, 'chat'], ['chat', { chat: { ...CHAT, creado_ms: -1 } }, 'chat'], ['chat', { chat: { ...CHAT, creado_ms: 1e16 } }, 'chat'],
      ['chat', { chat: { ...CHAT, baja_ms: '123' } }, 'chat'], ['chat', { chat: { ...CHAT, nombre_perfil: 5 } }, 'chat'],
      ['chat', { mensajes: 'x' }, 'mensajes'], ['chat', { mensajes: Array(101).fill(MSG) }, 'mensajes'], ['chat', { mensajes: [{ ...MSG, otra: 1 }] }, 'mensajes'], ['chat', { mensajes: [5] }, 'mensajes'],
      ['chat', { mensajes: [{ ...MSG, media: { tipo: 'image', id: 'm', url: 'http://x' } }] }, 'mensajes'], ['chat', { mensajes: [{ ...MSG, contenido: 5 }] }, 'mensajes'],
      ['chat', { mensajes: [{ ...MSG, wamid: 'con espacios' }] }, 'mensajes'], ['chat', { mensajes: [{ ...MSG, ts_ms: 'x' }] }, 'mensajes'],
      ['chat', { escalaciones: Array(21).fill(ESC) }, 'escalaciones'], ['chat', { escalaciones: [{ ...ESC, otra: 1 }] }, 'escalaciones'], ['chat', { escalaciones: [{ ...ESC, aviso_wamid: '  ' }] }, 'escalaciones'],
      ['config', { config: undefined }, 'config'], ['config', { config: { extra: 'x', bienvenida: 'b', pausa_horas: 'x' } }, 'config'], ['config', { config: { extra: 'x', bienvenida: 'b', pausa_horas: 721 } }, 'config'],
      ['config', { config: { extra: 'x', bienvenida: 'b', pausa_horas: 1, otra: 1 } }, 'config'], ['config', { config: { extra: 5, bienvenida: 'b', pausa_horas: 1 } }, 'config'],
      ['config', { log: Array(51).fill(bienI.config.log[0]) }, 'log'], ['config', { log: [{ ...bienI.config.log[0], prev: undefined }] }, 'log'], ['config', { log: [{ ...bienI.config.log[0], next: 5 }] }, 'log'],
      ['config', { log: [{ ...bienI.config.log[0], extra: 1 }] }, 'log'], ['config', { log: [{ ...bienI.config.log[0], prev: { extra: '', bienvenida: '' } }] }, 'log'],
      ['config', { log: [{ ...bienI.config.log[0], prev: { extra: '', bienvenida: '', pausa_horas: 0, updated_by: 'x' } }] }, 'log'],
      ['cuadre', { tel: '12' }, 'tel'], ['cuadre', { tel: undefined }, 'tel'], ['cuadre', { chat: {} }, 'campo_no_permitido'],
    ];
    for (const [a, parche, err] of malos) {
      const r = await im({ ...bienI[a], ...parche });
      igual([a, JSON.stringify(parche).slice(0, 60), r.status, r.cuerpo.error], [a, JSON.stringify(parche).slice(0, 60), 400, err]);
    }
    igual(llamadas.length, 0, 'ninguna peticion invalida llego a la base');
    igual((await im('x'.repeat(2_200_000))).status, 413, 'tope de cuerpo propio (2 MiB)');
    // el tope deja pasar un chat grande de verdad: 100 mensajes de 4096 caracteres de 3 bytes
    const grande = { ...bienI.chat, mensajes: Array.from({ length: 100 }, (_, i) => ({ ...MSG, wamid: 'wamid.G' + i, contenido: 'ñ'.repeat(4096), ts_ms: 1760000000000 + i })) };
    dbCon(FILA(RESP_CHAT));
    igual((await im(grande)).status, 200, 'un chat de 100 mensajes de 4096 caracteres cabe');
    reinicia();

    // 3. lo que llega a la base y lo que sale
    dbCon(FILA(RESP_CHAT));
    let r = await im(bienI.chat);
    igual(r.status, 200); igual(llamadas.map((l) => [l.clave, l.args.length, JSON.parse(l.args[0])]), [['importar_chat', 1, { tel: TEL, chat: CHAT, mensajes: [MSG], escalaciones: [ESC] }]], 'chat: una sentencia, un parametro jsonb');
    igual(vistoPorLaFuncion(M.SQL[llamadas[0].clave], llamadas[0].args)[0], { tel: TEL, chat: CHAT, mensajes: [MSG], escalaciones: [ESC] }, 'chat: la funcion SQL recibe el objeto, no un string');
    igual(r.cuerpo, { ok: true, accion: 'chat', chat: 'creado', lead: 'sin_lead', mensajes: { recibidos: 1, insertados: 1, omitidos_posteriores: false }, escalaciones: { recibidas: 1, insertadas: 1 } }, 'salida fija: sin el campo interno');
    // lo que no se reconoce no viaja, los textos se recortan, null con pausado se conserva (pausa sin caducidad) y mensajes/escalaciones ausentes = []
    reinicia(); dbCon(FILA(RESP_CHAT));
    r = await im({ accion: 'chat', tel: '+' + TEL, chat: { pausado: true, nombre_perfil: 'N'.repeat(500) }, mensajes: [{ contenido: 'x'.repeat(9000) + '\u0000', media: { id: 'm1' } }] });
    igual(r.status, 200);
    const enviado = JSON.parse(llamadas[0].args[0]);
    igual(enviado.chat.pausa_hasta_ms, null, 'pausa_hasta_ms null se conserva'); igual(enviado.chat.pausado, true); igual(enviado.chat.nombre_perfil.length, 200);
    igual(enviado.mensajes[0].contenido.length, 4096); igual(enviado.mensajes[0].media, { tipo: 'otro', id: 'm1' }); igual(enviado.escalaciones, []);
    igual(Object.keys(enviado.chat).sort(), [...Object.keys(CHAT)].sort(), 'el chat reconstruido lleva exactamente las 16 claves');
    reinicia(); dbCon(FILA({ ok: true, resultado: 'importada', log_importado: 1, secreto: 'no' }));
    r = await im(bienI.config);
    igual(r.cuerpo, { ok: true, accion: 'config', resultado: 'importada', log_importado: 1 }); igual(llamadas[0].clave, 'importar_config');
    igual(JSON.parse(llamadas[0].args[0]), { config: bienI.config.config, log: bienI.config.log });
    igual(vistoPorLaFuncion(M.SQL[llamadas[0].clave], llamadas[0].args)[0], { config: bienI.config.config, log: bienI.config.log }, 'config: la funcion SQL recibe el objeto, no un string');
    reinicia(); dbCon(FILA({ ok: true, resultado: 'ya_configurada' }));
    igual((await im(bienI.config)).cuerpo, { ok: true, accion: 'config', resultado: 'ya_configurada', log_importado: 0 });
    reinicia(); dbCon(FILA({ existe: true, n_mensajes: 3, hash_mensajes: 'a'.repeat(32), ultimo_entrante_ms: 1760000050000, pausado: true, pausa_hasta_ms: null, baja: false, aviso_nivel: 2, escalaciones_abiertas: 1, mas: 'x' }));
    r = await im(bienI.cuadre);
    igual(llamadas, [{ clave: 'importar_cuadre', args: [TEL] }]);
    igual(r.cuerpo, { ok: true, accion: 'cuadre', existe: true, n_mensajes: 3, hash_mensajes: 'a'.repeat(32), ultimo_entrante_ms: 1760000050000, pausado: true, pausa_hasta_ms: null, baja: false, aviso_nivel: 2, escalaciones_abiertas: 1 });
    reinicia(); dbCon(FILA({ existe: false }));
    igual((await im(bienI.cuadre)).cuerpo, { ok: true, accion: 'cuadre', existe: false });

    // 4. errores de negocio, formas rotas y caidas: nunca el texto de Postgres
    for (const [a, e] of [['chat', 'telefono_invalido'], ['chat', 'forma'], ['config', 'forma'], ['config', 'pausa_horas']]) {
      reinicia(); dbCon(FILA({ ok: false, error: e }));
      igual((await im(bienI[a])).cuerpo, { ok: false, accion: a, error: e }, a + ' ' + e);
    }
    for (const [a, resp] of [['chat', { ok: false, error: 'invalid input syntax for type boolean: "si"' }], ['chat', { ok: true }], ['chat', { ...RESP_CHAT, chat: 'otro' }], ['chat', { ...RESP_CHAT, lead: 'x' }],
      ['config', { ok: true, resultado: 'rara' }], ['config', { ok: false, error: 'boom' }], ['cuadre', { existe: true, hash_mensajes: 'no-es-md5' }], ['cuadre', { existe: 'si' }], ['cuadre', { existe: false, error: 'x' }]]) {
      reinicia(); dbCon(FILA(resp));
      const x = await im(bienI[a]);
      igual([a, x.status, x.cuerpo], [a, 502, { error: 'db_error' }], 'forma inesperada = 502 sin detalle');
      ok(!x.crudo.includes('boolean') && !x.crudo.includes('boom'), 'el texto de la base no sale');
    }
    // la base caida (cualquier fallo del driver) la cubre el manejador comun: aqui se comprueba que /importar lo atraviesa
    reinicia(); M.DB.ejecuta = async () => { throw new Error('connection refused postgres://bot_lawang:clave@host'); };
    const caida = await im(bienI.cuadre);
    ok(caida.status === 500 && !caida.crudo.includes('clave') && !caida.crudo.includes('postgres'), 'una caida no filtra detalle');
    M.DB.ejecuta = async (clave, args) => { llamadas.push({ clave, args }); return guion(clave, args); };
    reinicia();
  }

  // ── S5-puente: el mismo dato en todos los sitios (sentencias, grants y codigos de error de las funciones bot_importar_*) ──
  {
    const m5 = leer('supabase', 'migrations', '20261010135000_bot_sin_redis_s5_importar.sql'), m5b = leer('supabase', 'migrations', '20261010141000_bot_sin_redis_s5_importar_ajustes.sql');
    const fuente5 = leer('supabase', 'functions', 'bot-api', 'index.ts');
    const trozo = (sql, nombre) => { const i = sql.lastIndexOf('create or replace function public.' + nombre + '('); assert.ok(i >= 0, nombre); return sql.slice(i, sql.indexOf('end $f$;', i)); };
    const errs = (t) => [...new Set([...t.matchAll(/'error',\s*'([a-z_]+)'/g)].map((m) => m[1]))].sort();
    const casos = { chat: ['bot_importar_chat', 'jsonb', trozo(m5, 'bot_importar_chat') + trozo(m5b, 'bot_importar_chat')], config: ['bot_importar_config', 'jsonb', trozo(m5b, 'bot_importar_config')],
      cuadre: ['bot_importar_cuadre', 'text', trozo(m5, 'bot_importar_cuadre')] };
    for (const [acc, [fn, tipo, cuerpo]] of Object.entries(casos)) {
      const d = M.LISTA_CERRADA.importar[acc];
      ok(fuente5.includes(`'select public.${fn}($1::${tipo === 'jsonb' ? 'text::jsonb' : tipo}) as r'`), `${fn}: la sentencia de la edge coincide con la firma`);
      ok(new RegExp('grant execute on function public[.]' + fn + '[(]' + tipo + '[)]\\s+to bot_lawang').test(m5 + m5b), `${fn}: EXECUTE concedido a bot_lawang`);
      igual([...d.errores].sort(), errs(cuerpo), `${fn}: los errores que acepta la edge = los que devuelve la funcion SQL`);
    }
    ok(!/grant execute[^;]*_bot_importar_chat_nucleo/.test(m5b), 'el nucleo interno no se concede a nadie');
  }

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
