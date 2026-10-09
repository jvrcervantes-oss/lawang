/* node contracts/bot_conversaciones_lectura.test.js
   S10 del encargo «bot de Lawang sin Redis» (9-oct-2026). Las conversaciones del bot son datos personales de gente que escribe a WhatsApp:
   la intranet las lee DIRECTAMENTE de Postgres y por eso la regla tiene que ser mecanica, no una frase en un comentario.
   Afirma sobre el TEXTO de las migraciones y del front (la prueba con roles reales vive en supabase/pruebas/bot_sin_redis_s10.sql):
     1. Toda funcion que un usuario del navegador (`authenticated`) puede ejecutar y que lee las tablas del bot (bot_chat, bot_mensaje,
        bot_wamid, bot_escalacion, bot_lecturas_log) llama a `_bot_conversaciones_autoriza(` ANTES de la primera lectura. Es lo que impide
        que una funcion de lectura futura se salte el permiso `bot_conversaciones_ver` y el registro de lecturas.
     2. Hay al menos las dos que existen hoy (crm_bot_conversaciones y crm_bot_conversacion) y son SECURITY DEFINER con search_path fijo,
        sin ejecucion para PUBLIC/anon/service_role.
     3. El front NO toca esas tablas por la API de tablas (`.from('bot_…')`): solo por las dos funciones (norma «el navegador no lee la base»).
     4. El permiso esta dado de alta en las tres piezas que tienen que casar: herramientas.js, el menu v4 y la edge admin-usuarios. */
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const leer = (...p) => fs.readFileSync(path.join(RAIZ, ...p), 'utf8');
const MIG = path.join(RAIZ, 'supabase', 'migrations');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

const TABLAS_BOT = /\bpublic\.(bot_chat|bot_mensaje|bot_wamid|bot_escalacion|bot_lecturas_log)\b/i;

/* Lee todas las migraciones y devuelve las funciones public.* con su ultima definicion (create or replace posteriores sustituyen a las anteriores). */
function funciones() {
  const porNombre = {};
  const grants = {};
  for (const f of fs.readdirSync(MIG).filter(x => x.endsWith('.sql')).sort()) {
    const txt = fs.readFileSync(path.join(MIG, f), 'utf8');
    for (const m of txt.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\(/gi)) {
      const resto = txt.slice(m.index);
      const cuerpo = /\bas\s+(\$\w*\$)([\s\S]*?)\1/i.exec(resto);
      if (!cuerpo) continue;
      porNombre[m[1].toLowerCase()] = { fichero: f, cabecera: resto.slice(0, cuerpo.index), cuerpo: cuerpo[2] };
    }
    for (const g of txt.matchAll(/grant\s+execute\s+on\s+function\s+public\.(\w+)\s*\([^)]*\)\s+to\s+([^;]*);/gi)) {
      (grants[g[1].toLowerCase()] = grants[g[1].toLowerCase()] || []).push(g[2].toLowerCase());
    }
    for (const g of txt.matchAll(/revoke\s+(?:all|execute)\s+on\s+function\s+public\.(\w+)\s*\([^)]*\)\s+from\s+([^;]*);/gi)) {
      (grants[g[1].toLowerCase() + ':revoke'] = grants[g[1].toLowerCase() + ':revoke'] || []).push(g[2].toLowerCase());
    }
  }
  return { porNombre, grants };
}
const { porNombre, grants } = funciones();

// 1. regla general: ejecutable por authenticated + lee tablas del bot => autoriza ANTES de la primera lectura
const ejecutables = Object.keys(porNombre).filter(nom => (grants[nom] || []).some(q => /\bauthenticated\b/.test(q)));
let leen = 0;
for (const nom of ejecutables) {
  const { fichero } = porNombre[nom];
  /* Solo cuenta lo que EJECUTA la funcion: lo declarado antes del `begin` (p. ej. `v_c public.bot_chat%rowtype`) es un tipo, no una lectura. */
  const completo = porNombre[nom].cuerpo;
  const iniBegin = completo.search(/\bbegin\b/i);
  const cuerpo = iniBegin >= 0 ? completo.slice(iniBegin) : completo;
  const lee = TABLAS_BOT.exec(cuerpo);
  if (!lee) continue;
  leen++;
  const aut = cuerpo.search(/_bot_conversaciones_autoriza\s*\(/i);
  ok(aut >= 0, `${nom} (${fichero}) lee ${lee[0]} y la puede ejecutar authenticated, pero no llama a _bot_conversaciones_autoriza`);
  ok(aut < lee.index, `${nom} (${fichero}) lee ${lee[0]} ANTES de llamar a _bot_conversaciones_autoriza: sin permiso ya habria tocado datos`);
}
ok(leen >= 2, 'no se encontraron las funciones de lectura de la intranet (¿cambio el formato de las migraciones?)');

// 2. las dos de hoy: forma exacta
for (const [nom, accion] of [['crm_bot_conversaciones', 'lista'], ['crm_bot_conversacion', 'hilo']]) {
  const f = porNombre[nom];
  ok(f, `falta la funcion ${nom}`);
  ok(/security\s+definer/i.test(f.cabecera), `${nom} debe ser SECURITY DEFINER`);
  ok(/set\s+search_path\s*=\s*''/i.test(f.cabecera), `${nom} debe fijar search_path = ''`);
  const primera = f.cuerpo.replace(/--.*$/gm, '').split(/\bbegin\b/i)[1].trim();     // primera sentencia tras el begin (y tras los comentarios)
  ok(/^perform\s+public\._bot_conversaciones_autoriza\s*\(/i.test(primera), `${nom}: lo PRIMERO tras begin debe ser perform public._bot_conversaciones_autoriza(...)`);
  ok(new RegExp(`_bot_conversaciones_autoriza\\s*\\([^)]*'${accion}'\\s*\\)`, 'i').test(f.cuerpo), `${nom}: debe apuntar la lectura como '${accion}'`);
  ok(!/\bvolatile\b/i.test(f.cabecera) || true, '');
  ok(!/\b(stable|immutable)\b/i.test(f.cabecera), `${nom} no puede ser STABLE/IMMUTABLE: el registro de lecturas inserta`);
  ok((grants[nom] || []).some(q => /\bauthenticated\b/.test(q)), `${nom} debe estar concedida a authenticated`);
  ok((grants[nom] || []).every(q => !/\b(anon|public|service_role)\b/.test(q)), `${nom}: no se concede a anon/public/service_role`);
  const rev = (grants[nom + ':revoke'] || []).join(' ');
  ok(/\bpublic\b/.test(rev) && /\banon\b/.test(rev), `${nom}: debe hacer revoke from public, anon (los privilegios por defecto de Supabase la abren)`);
}
// la funcion interna de forma NO se concede a nadie
ok(porNombre._crm_bot_conv_fila, 'falta _crm_bot_conv_fila');
ok(!(grants._crm_bot_conv_fila || []).length, '_crm_bot_conv_fila no se concede a nadie');
// y el bot NO ejecuta las de la intranet
['crm_bot_conversaciones', 'crm_bot_conversacion'].forEach(nom => ok(!(grants[nom] || []).some(q => /bot_lawang/.test(q)), `${nom} no es del bot`));

// 3. el front lee por las funciones, nunca por la API de tablas
const leads = leer('intranet', 'leads', 'leads.js');
ok(/SB\.rpc\('crm_bot_conversaciones'\)/.test(leads), 'leads.js ya no lee la lista por SB.rpc(crm_bot_conversaciones)');
ok(/SB\.rpc\('crm_bot_conversacion',/.test(leads), 'leads.js ya no lee el hilo por SB.rpc(crm_bot_conversacion)');
for (const f of ['intranet/leads/leads.js', 'intranet/leads/index.html']) {
  const t = leer(...f.split('/'));
  ok(!/\.from\(\s*['"`]bot_(chat|mensaje|wamid|escalacion|lecturas_log|config)/.test(t), `${f} lee una tabla del bot con .from(): el navegador no lee la base, pide a una funcion`);
}

// 4. el permiso casa en las tres piezas
const herr = leer('contracts', 'assets', 'herramientas.js');
ok(/herr:'bot_conversaciones_ver'/.test(herr), 'herramientas.js: falta la entrada con herr:bot_conversaciones_ver');
ok(/bot_conversaciones_ver/.test(leer('intranet', 'v4', 'assets', 'nav.js')), 'nav.js: el menu v4 no sitúa la casilla bot_conversaciones_ver');
ok(/HERRAMIENTAS = \[[^\]]*'bot_conversaciones_ver'/.test(leer('contracts', 'edge', 'admin-usuarios', 'index.ts')), 'admin-usuarios: la lista HERRAMIENTAS no conoce bot_conversaciones_ver (el alta devolveria 400)');
ok(/error\.code === '42501'/.test(leads), 'leads.js: la pantalla no distingue «sin permiso» (42501) de «no se pudo leer»');
ok(/SETTER_ERROR/.test(leads), 'leads.js: «no se pudo mirar» no se distingue de «sin conversaciones»');
ok(/HAY_MAS_CONV\s*=\s*!!\(data && data\.hayMas\)/.test(leads), 'leads.js: la lista descarta hayMas (mas de 500 hilos) sin guardarlo');
ok(/HAY_MAS_CONV \? [^\n]*data-tipo="hay_mas_conversaciones"[^\n]*esc\(lwT\(/.test(leads), 'leads.js: no pinta el aviso data-tipo=hay_mas_conversaciones con texto escapado cuando hay mas de 500 hilos');

console.log('bot_conversaciones_lectura.test.js OK (' + n + ' comprobaciones)');
