/* node smtp_fuente.test.js — de dónde saca envia-correo el servidor SMTP y con qué remitente sale (F3.1, 7-oct-2026). Idéntico en el maestro y en
   Lawang (desde el porte del 8-oct-2026, F3). El index.ts REAL, sin Deno ni red (arnes.mjs).
   Qué fija, porque cada rama es un fallo que no da error:
   · HAY fila en Vault → manda ese servidor; los secretos SMTP_* del entorno NO se usan;
   · NO hay fila (la función contesta null) o la función no existe aún (404 PGRST202, base sin migrar) → los secretos de entorno de siempre;
   · fila que no se puede LEER (500, red, forma rara, 404 de otro código, puerto ≠ 465) → 500 en voz alta y NUNCA cae al entorno;
   · fila + el envío falla → 500 con sus códigos, UN solo intento (sin reintento con el entorno);
   · remitente: `email_from` solo si su dominio es del buzón o de la instancia; si no, el buzón y una línea de log con el CÓDIGO (no la dirección);
   · «responder a» solo si es un correo válido y sin saltos de línea. */
const assert = require('assert');

(async () => {
  const A = await import('./arnes.mjs');
  const { reinicia, cargaEdge, llama, estado, CONFIG_BASE } = A;
  let n = 0;
  const igual = (a, b, m) => { assert.deepStrictEqual(a, b, m); n++; };
  const ok = (c, m) => { assert.ok(c, m); n++; };
  const H = { 'content-type': 'application/json', 'x-render-secret': 'render-falso' };
  const texto = { to: 'ana@cliente.es', message: 'Hola', attach: false };
  const VAULT = { host: 'smtp.vault.com', port: 465, user: 'buzon@vault.com', pass: 'clave-de-vault', nombre: 'Marca Vault' };
  const config = (extra = []) => [...CONFIG_BASE, ...extra];
  async function envia(o = {}, cuerpo = texto) {
    reinicia({ config: config(o.config), smtpLee: o.smtpLee });
    const m = await cargaEdge(__dirname);
    const r = await llama(m, { cabeceras: H, cuerpo });
    return { r, c: estado.correo };
  }
  const lee = (cuerpo, status = 200) => () => ({ status, cuerpo });

  // ── 1. hay fila: manda Vault y el entorno no pinta nada ─────────────────────────────────────────────────────────────────────────
  let { r, c } = await envia({ smtpLee: lee(VAULT) });
  igual(r.status, 200, JSON.stringify(r.cuerpo));
  igual(c.transportes.length, 1); igual(c.transportes[0], { host: 'smtp.vault.com', port: 465, secure: true, user: 'buzon@vault.com' }, 'el servidor es el de Vault, no el de SMTP_HOST');
  igual([c.correos[0]._host, c.correos[0]._user], ['smtp.vault.com', 'buzon@vault.com']);
  igual(c.correos[0].from, { name: 'Marca Vault', address: 'buzon@vault.com' }, 'nombre de Vault y el buzón como remitente');
  ok(!JSON.stringify(c.transportes).includes('smtp.falso.test'), 'nada del entorno');

  // ── 2. no hay fila / la función no existe: entorno de siempre ───────────────────────────────────────────────────────────────────
  ({ r, c } = await envia({ smtpLee: lee(null) }));
  igual(r.status, 200); igual(c.transportes[0].host, 'smtp.falso.test', 'sin fila → SMTP_HOST'); igual(c.correos[0].from, { name: 'Acme', address: 'buzon@ejemplo.com' });
  ({ r, c } = await envia({}));   // por defecto el arnés contesta 404 PGRST202, como una base sin migrar
  igual(r.status, 200); igual(c.transportes[0].host, 'smtp.falso.test', 'función ausente (404 PGRST202) → SMTP_HOST');
  ({ r, c } = await envia({ smtpLee: lee({ code: '42883', message: 'undefined_function' }, 404) }));
  igual(r.status, 200); igual(c.transportes[0].host, 'smtp.falso.test', '404 con 42883 también es «no existe aún»');

  ({ r, c } = await envia({ smtpLee: () => ({ status: 200, cuerpo: undefined }) }).then((x) => x));
  // (cuerpo vacío del 200 = la función devolvió NULL → sin fila → entorno; antes era un error)
  igual(r.status, 200); igual(c.transportes[0].host, 'smtp.falso.test', 'cuerpo vacío = sin fila');

  // ── 3. fila que NO se puede leer: 500 y jamás el entorno ────────────────────────────────────────────────────────────────────────
  const ilegibles = [
    ['500 de la base', lee({ code: 'XX000', message: 'boom' }, 500)], ['401', lee({ code: 'PGRST301' }, 401)], ['403 sin permiso', lee({ code: '42501' }, 403)],
    ['404 de otra cosa', lee({ code: 'PGRST125', message: 'ruta' }, 404)], ['red caída', 'lanza'], ['cuerpo que no es JSON', () => ({ status: 200, cuerpo: '{no' })],
    ['sin host', lee({ ...VAULT, host: '' })], ['sin contraseña', lee({ ...VAULT, pass: '' })], ['sin usuario', lee({ ...VAULT, user: '' })],
    ['puerto 587', lee({ ...VAULT, port: 587 })], ['puerto como texto', lee({ ...VAULT, port: '465' })], ['un array', lee([VAULT])], ['un número', lee(7)],
  ];
  for (const [que, smtpLee] of ilegibles) {
    ({ r, c } = await envia({ smtpLee }));
    igual(r.status, 500, que); ok(r.cuerpo.ok === false && /servidor de correo/.test(r.cuerpo.error), que + ': ' + r.crudo);
    igual(c.transportes.length, 0, que + ': no se abre ningún SMTP (ni el de Vault ni el del entorno)'); igual(c.correos.length, 0);
    ok(!r.crudo.includes('clave-de-vault') && !r.crudo.includes('smtp.vault.com'), que + ': el error no filtra nada');
  }

  // ── 4. fila + el envío falla: 500 con códigos, UN intento, sin caer al entorno ──────────────────────────────────────────────────
  reinicia({ config: config(), smtpLee: lee(VAULT) });
  let m = await cargaEdge(__dirname);
  estado.correo.falloSmtp = Object.assign(new Error('x'), { code: 'EAUTH', responseCode: 535, response: '535 5.7.8 Username and Password not accepted' });
  r = await llama(m, { cabeceras: H, cuerpo: texto });
  igual(r.status, 500); igual([r.cuerpo.smtp_code, r.cuerpo.smtp_response_code], ['EAUTH', 535]);
  igual(estado.correo.transportes.length, 1, 'un solo intento'); igual(estado.correo.transportes[0].host, 'smtp.vault.com', 'y fue el de Vault');
  ok(!r.crudo.includes('clave-de-vault'), 'la contraseña no sale en el error');

  // ── 5. caché: dos envíos seguidos leen Vault una sola vez; un error no se cachea ────────────────────────────────────────────────
  reinicia({ config: config(), smtpLee: lee(VAULT) });
  m = await cargaEdge(__dirname);
  await llama(m, { cabeceras: H, cuerpo: texto }); await llama(m, { cabeceras: H, cuerpo: texto });
  igual(estado.llamadas.filter((x) => x.url.includes('correo_smtp_lee')).length, 1, 'caché de 30 s');
  let fallos = 0;
  reinicia({ config: config(), smtpLee: () => (fallos++ === 0 ? { status: 500, cuerpo: { code: 'XX000' } } : { status: 200, cuerpo: VAULT }) });
  m = await cargaEdge(__dirname);
  igual((await llama(m, { cabeceras: H, cuerpo: texto })).status, 500, 'el primer intento falla');
  igual((await llama(m, { cabeceras: H, cuerpo: texto })).status, 200, 'y el error no se quedó en la caché');

  // ── 6. sin credencial no se lee la base de SMTP ─────────────────────────────────────────────────────────────────────────────────
  reinicia({ config: config(), smtpLee: lee(VAULT) });
  m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: { 'content-type': 'application/json' }, cuerpo: texto });
  igual(r.status, 401); igual(estado.llamadas.filter((x) => x.url.includes('correo_smtp_lee')).length, 0, 'una petición anónima no provoca lecturas de Vault');

  // ── 7. remitente: email_from solo de dominio propio o del buzón ─────────────────────────────────────────────────────────────────
  const conFrom = async (emailFrom, smtpLee = lee(VAULT)) => {
    const x = await envia({ smtpLee, config: [['email_from', emailFrom]] });
    return { desde: x.c.correos[0] && x.c.correos[0].from.address, status: x.r.status, logs: x.r.logs };
  };
  let x = await conFrom('ventas@ejemplo.com');
  igual(x.desde, 'ventas@ejemplo.com', 'dominio de la instancia (dominio_web = ejemplo.com), aunque el buzón sea de vault.com');
  x = await conFrom('info@mail.ejemplo.com'); igual(x.desde, 'info@mail.ejemplo.com', 'subdominio de la instancia');
  x = await conFrom('otro@vault.com'); igual(x.desde, 'otro@vault.com', 'dominio del buzón');
  x = await conFrom('ceo@banco.com');
  igual(x.desde, 'buzon@vault.com', 'dominio ajeno → sale el buzón'); ok(x.logs.some((l) => l.includes('dominio_distinto')), 'y queda el código en el log');
  ok(x.logs.every((l) => !l.includes('ceo@banco.com') && !l.includes('banco.com')), 'sin la dirección en el log');
  x = await conFrom('ventas@ejemplo.com.fraude.ru'); igual(x.desde, 'buzon@vault.com', 'sufijo falso');
  x = await conFrom('ventas@ejemplo.com\nBcc: v@y.com'); igual(x.desde, 'buzon@vault.com', 'con salto de línea no se usa'); ok(x.logs.some((l) => l.includes('no_valido')));
  x = await conFrom('no-es-un-correo'); igual(x.desde, 'buzon@vault.com', 'basura'); igual(x.status, 200, 'y el envío sigue');
  x = await conFrom(''); igual(x.desde, 'buzon@vault.com', 'vacío: el buzón'); ok(x.logs.every((l) => !l.includes('email_from no se usa')), 'sin ruido');
  // el servidor de entorno (instancia sin migrar) también respeta email_from: es el arreglo de A4
  x = await conFrom('ventas@ejemplo.com', lee(null)); igual(x.desde, 'ventas@ejemplo.com', 'entorno + email_from propio: sale email_from');
  x = await conFrom('ceo@banco.com', lee(null)); igual(x.desde, 'buzon@ejemplo.com', 'entorno + ajeno: el SMTP_FROM de siempre');
  // usuario que no es un correo y sin email_from: no hay remitente → error claro, no un envío raro
  ({ r, c } = await envia({ smtpLee: lee({ ...VAULT, user: 'login-suelto' }), config: [['email_from', '']] }));
  igual([r.status, r.cuerpo.error], [500, 'Remitente de la instancia sin configurar']); igual(c.transportes.length, 0);
  ({ r, c } = await envia({ smtpLee: lee({ ...VAULT, user: 'login-suelto' }), config: [['email_from', 'ventas@ejemplo.com']] }));
  igual(r.status, 200); igual(c.correos[0].from.address, 'ventas@ejemplo.com', 'usuario que no es correo + remitente de la instancia: sirve');

  // ── 8. responder a ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ({ c } = await envia({ smtpLee: lee(VAULT), config: [['email_reply_to', 'respuestas@ejemplo.com']] }));
  igual(c.correos[0].replyTo, 'respuestas@ejemplo.com', 'email_reply_to válido');
  for (const malo of ['', 'x', 'a@x.com, b@x.com', 'a@x.com\nBcc: v@y.com']) {
    ({ r, c } = await envia({ smtpLee: lee(VAULT), config: [['email_reply_to', malo]] }));
    igual(r.status, 200, 'un «responder a» roto no para el envío'); ok(!('replyTo' in c.correos[0]), 'y no se pone: ' + JSON.stringify(malo));
  }

  // ── 9. el pie del correo lleva el remitente EFECTIVO (antes: SMTP_FROM a pelo) ───────────────────────────────────────────────────
  reinicia({ config: config([['email_from', 'ventas@ejemplo.com']]), smtpLee: lee(VAULT), sesion: true });
  m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: { 'content-type': 'application/json', authorization: 'Bearer jwt-de-sesion' }, cuerpo: { ...texto, preview: true } });
  // El pie lleva el remitente según la PIEL de cada repo (plantilla.ts es propia de cada cliente): la neutra del maestro lo pinta; la de Lawang
  // pinta admin@/sales@ del dominio y no lo pinta. Este fichero es idéntico en los dos repos, así que mira la piel que tiene al lado.
  const PIEL_PINTA_REMITENTE = /\$\{remitente\}|m\.remitente/.test(require('fs').readFileSync(__dirname + '/plantilla.ts', 'utf8'));
  igual(r.status, 200);
  if (PIEL_PINTA_REMITENTE) ok(r.cuerpo.html.includes('ventas@ejemplo.com') && !r.cuerpo.html.includes('buzon@vault.com'), 'la vista previa lleva el remitente efectivo en el pie');
  else ok(r.cuerpo.html.includes('admin@ejemplo.com') && !r.cuerpo.html.includes('buzon@vault.com'), 'piel con contacto propio: el pie no lleva el buzón de Vault');
  reinicia({ config: config(), smtpLee: lee(VAULT), sesion: true });
  m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: { 'content-type': 'application/json', authorization: 'Bearer jwt-de-sesion' }, cuerpo: { ...texto, preview: true } });
  if (PIEL_PINTA_REMITENTE) ok(r.cuerpo.html.includes('buzon@vault.com'), 'sin email_from, el buzón de Vault');
  // la vista previa no revienta si Vault no se puede leer (no envía nada): el pie cae a no-reply@<dominio>
  reinicia({ config: config(), smtpLee: lee({ code: 'XX000' }, 500), sesion: true });
  m = await cargaEdge(__dirname);
  r = await llama(m, { cabeceras: { 'content-type': 'application/json', authorization: 'Bearer jwt-de-sesion' }, cuerpo: { ...texto, preview: true } });
  igual(r.status, 200); if (PIEL_PINTA_REMITENTE) ok(r.cuerpo.html.includes('no-reply@ejemplo.com'), 'el pie de la vista previa no inventa un buzón');

  // ── 9. buzón de aviso: dominio de la instancia, de email_from o del usuario SMTP (owner, 7-oct-2026) ─────────────────────────────────────
  const sinAvisos = CONFIG_BASE.filter(([k]) => !k.startsWith('email_avisos'));
  async function aviso(to, { extra = [], smtpLee = lee(VAULT), secreto = 'av' } = {}) {
    reinicia({ env: { ENVIO_AVISO_SECRET: 'av' }, config: [...sinAvisos, ...extra], smtpLee });
    const mm = await cargaEdge(__dirname);
    const rr = await llama(mm, { cabeceras: { 'content-type': 'application/json', 'x-aviso-secret': secreto }, cuerpo: { to, message: 'Aviso', attach: false } });
    return { rr, lecturas: estado.llamadas.filter((u) => JSON.stringify(u).includes('correo_smtp_lee')).length };
  }
  x = await aviso('soporte@ejemplo.com', { extra: [['email_avisos_soporte', 'soporte@ejemplo.com']] });
  igual(x.rr.status, 200, 'dominio de la instancia');
  x = await aviso('avisos@vault.com', { extra: [['email_avisos_soporte', 'avisos@vault.com']] });
  igual(x.rr.status, 200, JSON.stringify(x.rr.cuerpo)); igual(estado.correo.correos[0]._user, 'buzon@vault.com', 'dominio del usuario SMTP (vault.com)');
  x = await aviso('avisos@desde-from.com', { extra: [['email_avisos_soporte', 'avisos@desde-from.com'], ['email_from', 'ventas@desde-from.com']] });
  igual(x.rr.status, 200, 'dominio de email_from');
  x = await aviso('avisos@ajeno.com', { extra: [['email_avisos_soporte', 'avisos@ajeno.com']] });
  igual(x.rr.status, 401, 'dominio ajeno a los tres'); igual(x.lecturas, 1, 'se lee Vault solo para decidir (secreto válido)');
  x = await aviso('avisos@sub.vault.com', { extra: [['email_avisos_soporte', 'avisos@sub.vault.com']] });
  igual(x.rr.status, 401, 'del servidor solo el dominio exacto');
  x = await aviso('avisos@vault.com', { extra: [['email_avisos_soporte', 'avisos@vault.com']], secreto: 'mal' });
  igual(x.rr.status, 401, 'secreto malo'); igual(x.lecturas, 0, 'sin secreto válido no se lee Vault');
  x = await aviso('otro@vault.com', { extra: [['email_avisos_soporte', 'avisos@vault.com']] });
  igual(x.rr.status, 401, 'un buzón que no es de aviso no pasa aunque sea del dominio del servidor');

  // 9b. correo GRATUITO (Seguridad, 8-oct-2026): el dominio de email_from o del usuario SMTP no cuenta como propio si es gmail.com & co; el de dominio_web siempre
  x = await aviso('avisos@gmail.com', { extra: [['email_avisos_soporte', 'avisos@gmail.com'], ['email_from', 'empresa@gmail.com']] });
  igual(x.rr.status, 401, 'email_from de Gmail: el buzón gmail.com NO es de aviso'); igual(x.lecturas, 1, 'cae a la comprobación del servidor, que tampoco lo admite');
  x = await aviso('avisos@hotmail.com', { extra: [['email_avisos_soporte', 'avisos@hotmail.com']], smtpLee: lee({ ...VAULT, user: 'empresa@hotmail.com' }) });
  igual(x.rr.status, 401, 'usuario SMTP de Hotmail: el buzón hotmail.com NO es de aviso');
  x = await aviso('avisos@ejemplo.com', { extra: [['email_avisos_soporte', 'avisos@ejemplo.com']], smtpLee: lee({ ...VAULT, user: 'empresa@gmail.com' }) });
  igual(x.rr.status, 200, 'el dominio de la instancia sigue valiendo aunque el servidor sea un Gmail');
  {
    const sinDom = sinAvisos.filter(([k]) => k !== 'dominio_web');
    reinicia({ env: { ENVIO_AVISO_SECRET: 'av' }, config: [...sinDom, ['dominio_web', 'gmail.com'], ['email_avisos_soporte', 'avisos@gmail.com']], smtpLee: lee(VAULT) });
    const mm = await cargaEdge(__dirname);
    const rr = await llama(mm, { cabeceras: { 'content-type': 'application/json', 'x-aviso-secret': 'av' }, cuerpo: { to: 'avisos@gmail.com', message: 'Aviso', attach: false } });
    igual(rr.status, 200, 'dominio_web=gmail.com: es el dominio de la empresa, SIEMPRE cuenta');
  }
  {   // la lista de correo gratuito es UNA: la misma en smtp.ts y en la migración de la base (si cambia una y no la otra, esto falla)
    const fs = require('fs'), path = require('path');
    const ts = fs.readFileSync(__dirname + '/smtp.ts', 'utf8');
    const lt = /CORREO_GRATUITO: readonly string\[\] = \[([^\]]+)\]/.exec(ts);
    ok(lt, 'smtp.ts declara CORREO_GRATUITO');
    const listaTs = lt[1].match(/'([^']+)'/g).map((q) => q.slice(1, -1));
    // la migración que lleva la lista: en el maestro la F3.1c, en Lawang la combinada (este fichero es el mismo en los dos repos)
    const mig = [path.join(__dirname, '..', '..', 'migraciones', '20261008141000_f31c_correo_endurece.sql'),
                 path.join(__dirname, '..', '..', 'migrations', '20261010060000_correo_ajustes_servidor_y_codigo.sql')].find((f) => fs.existsSync(f));
    ok(mig, 'se encuentra la migración que declara la lista de correo gratuito');
    const sql = fs.readFileSync(mig, 'utf8');
    const ls = /v_gratis text\[\] := array\[([^\]]+)\]/.exec(sql);
    ok(ls, 'la migración declara v_gratis');
    igual(ls[1].match(/'([^']+)'/g).map((q) => q.slice(1, -1)), listaTs, 'misma lista, mismo orden, en SQL y en TS');
    ok(listaTs.length === 17 && listaTs.includes('gmail.com') && listaTs.includes('proton.me'), 'los 17 dominios acordados');
  }

  // ── 10. caché del ÚLTIMO valor bueno (F3.1b, 8-oct-2026): fresco 30 s; si la lectura falla, vale hasta 10 min y luego 500 ────────────────
  const fuente = require('fs').readFileSync(__dirname + '/index.ts', 'utf8');
  ok(/SMTP_LECTURA_MS = 2500/.test(fuente) && /AbortSignal\.timeout\(SMTP_LECTURA_MS\)/.test(fuente), 'la lectura de Vault tiene 2,5 s de plazo (no 6)');
  ok(/SMTP_FRESCO_MS = 30_000/.test(fuente) && /SMTP_BUENO_MS = 10 \* 60_000/.test(fuente), 'fresco 30 s, último valor bueno 10 min');
  const realNow = Date.now; let ahora = realNow(); Date.now = () => ahora;
  const lecturas = () => estado.llamadas.filter((x) => x.url.includes('correo_smtp_lee')).length;
  try {
    // hay fila; pasan 2 min; la lectura FALLA (de las cuatro maneras) → sigue mandando el servidor de Vault, no el del entorno
    for (const [que, fallo] of [['500', () => ({ status: 500, cuerpo: { code: 'XX000' } })], ['red caída', Object.assign(() => ({}), { lanza: true })], ['plazo vencido', 'timeout'],
                                ['forma rara', () => ({ status: 200, cuerpo: { ...VAULT, port: 587 } })]]) {
      let fase = 'bien';
      reinicia({ config: config(), smtpLee: () => (fase === 'bien' ? { status: 200, cuerpo: VAULT } : null) });
      m = await cargaEdge(__dirname);
      estado.smtpLee = fase === 'bien' ? () => ({ status: 200, cuerpo: VAULT }) : fallo;
      ahora = realNow();
      r = await llama(m, { cabeceras: H, cuerpo: texto }); igual(r.status, 200, que + ': primera lectura buena'); igual(estado.correo.transportes[0].host, 'smtp.vault.com');
      fase = 'mal'; estado.smtpLee = fallo; estado.correo.transportes.length = 0;
      ahora += 60_000;
      r = await llama(m, { cabeceras: H, cuerpo: texto });
      igual(r.status, 200, que + ': la lectura falla pero hay último valor bueno de hace 1 min'); igual(estado.correo.transportes[0].host, 'smtp.vault.com', que + ': sigue siendo el servidor de Vault');
      ok(!JSON.stringify(estado.correo.transportes).includes('smtp.falso.test'), que + ': NUNCA el del entorno'); ok(r.logs.some((x) => x.includes('último valor bueno')), que + ': queda dicho en el log');
      ok(!r.crudo.includes('clave-de-vault'), que + ': la contraseña no sale');
      ahora += 9 * 60_000;   // 10 min exactos desde el último bueno → ya no vale
      estado.correo.transportes.length = 0;
      r = await llama(m, { cabeceras: H, cuerpo: texto });
      igual(r.status, 500, que + ': pasados 10 minutos sin una lectura buena, 500 en voz alta'); ok(/servidor de correo/.test(r.cuerpo.error)); igual(estado.correo.transportes.length, 0, que + ': no se abre ningún SMTP');
    }
    // dentro de los 30 s no se vuelve a leer (caché fresca); un fallo no se guarda como valor y la siguiente lectura buena lo sustituye
    reinicia({ config: config(), smtpLee: lee(VAULT) }); m = await cargaEdge(__dirname); ahora = realNow();
    await llama(m, { cabeceras: H, cuerpo: texto }); ahora += 10_000; await llama(m, { cabeceras: H, cuerpo: texto }); igual(lecturas(), 1, 'a los 10 s no se lee otra vez');
    ahora += 60_000; await llama(m, { cabeceras: H, cuerpo: texto }); igual(lecturas(), 2, 'a los 70 s sí');
    estado.smtpLee = lee({ ...VAULT, host: 'smtp.nuevo.com' }); ahora += 60_000; estado.correo.transportes.length = 0;
    await llama(m, { cabeceras: H, cuerpo: texto }); igual(estado.correo.transportes[0].host, 'smtp.nuevo.com', 'una lectura buena sustituye al valor guardado');
    // «sin fila» y «función ausente» son lecturas BUENAS (caen al entorno, como siempre) y también son el último valor bueno
    for (const [que, buena] of [['sin fila', lee(null)], ['función ausente', undefined]]) {
      reinicia({ config: config(), smtpLee: buena }); m = await cargaEdge(__dirname); ahora = realNow();
      r = await llama(m, { cabeceras: H, cuerpo: texto }); igual([r.status, estado.correo.transportes[0].host], [200, 'smtp.falso.test'], que + ' → entorno');
      estado.smtpLee = lee({ code: 'XX000' }, 500); ahora += 60_000; estado.correo.transportes.length = 0;
      r = await llama(m, { cabeceras: H, cuerpo: texto }); igual([r.status, estado.correo.transportes[0].host], [200, 'smtp.falso.test'], que + ' + lectura rota <10 min: el último valor bueno era «usa el entorno»');
      ahora += 11 * 60_000; estado.correo.transportes.length = 0;
      r = await llama(m, { cabeceras: H, cuerpo: texto }); igual(r.status, 500, que + ' + lectura rota >10 min: 500');
    }
    // sin ningún valor bueno previo (arranque en frío) una lectura rota es un 500 directo
    reinicia({ config: config(), smtpLee: lee({ code: 'XX000' }, 500) }); m = await cargaEdge(__dirname); ahora = realNow();
    r = await llama(m, { cabeceras: H, cuerpo: texto }); igual(r.status, 500, 'sin valor bueno previo, 500');
  } finally { Date.now = realNow; }

  console.log(`OK smtp_fuente.test.js — Vault manda si hay fila · entorno solo sin fila o sin función · lectura rota = 500 sin caer al entorno · un solo intento · caché · remitente y responder a · ${n} comprobaciones`);
})().catch((e) => { console.error(e); process.exit(1); });
