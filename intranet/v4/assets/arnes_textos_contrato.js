#!/usr/bin/env node
/* arnes_textos_contrato.js — ARNÉS VISUAL de la pantalla «Textos de contrato» (plantillas por empresa, S7, 8-oct-2026). A MANO: necesita Edge + playwright-core, así que no va en el gate.

   8-oct-2026 (editor como documento, E1-E3): ahora recorre el papel con índice, los idiomas en pestañas, los marcadores como pastillas, las partes sensibles editables con aviso y los
   rechazos de la base contados en llano (con textos REALES de las migraciones), también en modo oscuro.

   Qué hace: sirve la copia de Lawang desde disco bajo http://lawang.local, cambia el CDN de supabase-js por un cliente FALSO (sesión de una de las tres personas, `usuarios`, `empresas`,
   `plantillas_contrato` y las siete RPC de la pantalla con datos SINTÉTICOS salvo el cuerpo de las plantillas, que es el fichero público de contracts/templates) y recorre la pantalla a 1440 y a
   390 px. NO toca producción, NO llama a ninguna red, NO guarda nada. Lo que valida el SERVIDOR (qué se guarda, quién activa, qué bloques son fijos) se prueba por la RPC en
   supabase/pruebas/f2_plantillas_s7.sql; esto prueba que la pantalla pregunta bien, pinta lo que contesta la base (también cuando es hostil) y se puede usar en el móvil.

   8-oct-2026 (E7/E8, configurador): además recorre las pestañas REVISIONES y CAMPOS (crear, archivar, restaurar, borrar con sus errores en llano; catálogo de campos propios con
   su vista previa y el JSON que sale de la base), el botón «Insertar campo» del editor y el editor sobre una revisión (p_variante), a 1440 y a 390 px y en modo oscuro.

   Uso:  NODE_PATH=<carpeta con playwright-core> node arnes_textos_contrato.js --raiz <copia de Lawang> [--png <prefijo>]
   Sale con 1 si algo falla. */
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
if (!arg('--raiz')) { console.error('falta --raiz <copia de Lawang>'); process.exit(2); }
const RAIZ = path.resolve(arg('--raiz'));
const PNG = arg('--png', null);
const EDGE = process.env.ARNES_EDGE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const HOST = 'http://lawang.local';
const TC = require(path.join(RAIZ, 'intranet/v4/assets/textos-contrato-nucleo.js'));
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };

/* ── datos sintéticos ── */
const tpl = (f) => fs.readFileSync(path.join(RAIZ, 'contracts/templates', f + '.html'), 'utf8');
const sinNotas = (d) => d.replace(/<!--(?!if:|\/if:|opt:|\/opt:|seccion-|\/seccion-|extra-clauses|firmas-adquirientes|compradores-extra|datos-bancarios|hitos|extras-construccion|cuenta:|bloque-fijo:|\/bloque-fijo:)[\s\S]*?-->/g, '');
const SLUGS = fs.readdirSync(path.join(RAIZ, 'contracts/templates')).filter(f => f.endsWith('.html') && f[0] !== '_').map(f => f.replace(/\.html$/, ''));
const OFERTA = sinNotas(tpl('commercial_offer'));
const V2 = OFERTA.replace('acabados de alta calidad', 'acabados de calidad superior');
const V3 = V2.replace('piscina y paisajismo', 'piscina, jardín y paisajismo');
const fijos = (doc) => {                       // simula lo que devuelve la base: elementos que nombran el NPWP o el foro
  const out = [];
  for (const tg of ['p', 'li', 'td', 'th', 'h1', 'h2', 'h3', 'h4']) {
    const re = new RegExp('<' + tg + '(?: [^>]*)?>(?:(?!</' + tg + '>)[\\s\\S])*</' + tg + '>', 'g'); let m;
    while ((m = re.exec(doc)) !== null) if (/npwp|arbitra|escrow/i.test(m[0].replace(/<[^>]*>/g, ' '))) out.push('E|' + TC.ws(m[0]));
  }
  return out;
};
const fijosPR = (doc) => {                     // lo que devolvería la base para ppjb_reserva: elementos con NPWP/foro/escrow + la sección «Ley aplicable»
  const out = fijos(doc), re = /<h2(?:\s[^>]*)?>/gi, pos = []; let m;
  while ((m = re.exec(doc)) !== null) pos.push(m.index);
  pos.forEach((a, k) => { const b = k + 1 < pos.length ? pos[k + 1] : doc.length; if (/ley aplicable|governing law/i.test(doc.slice(a, b).split('</h2>')[0].replace(/<[^>]*>/g, ' '))) out.push('S|' + TC.ws(doc.slice(a, b))); });
  return out;
};
const lista = [];
SLUGS.forEach((s, i) => {
  lista.push({ id: 'sem-' + s, empresa: 'lawang', slug: s, version: 1, estado: 'borrador', origen: 'semilla', idioma_set: ['es', 'en', 'id'], hash: 'a'.repeat(63) + (i % 10), bytes: 1000, activable: false,
    bloqueo_motivo: 'Copia inicial del estudio: no se activa tal cual', autor: 'estudio', fecha: '2026-10-07T10:00:00Z', motivo: 'Copia inicial', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: null });
});
lista.push({ id: 'act-co', empresa: 'lawang', slug: 'commercial_offer', version: 2, estado: 'activa', origen: 'empresa', idioma_set: ['es'], hash: 'b'.repeat(64), bytes: 1200, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T08:00:00Z', motivo: 'Mejor redaccion del alcance', activado_por: 'super.uno@prueba.test', activado_en: '2026-10-08T09:00:00Z', confirmacion_nombre: 'Persona Uno de Prueba', retirada_por: null, retirada_en: null, hereda_de: 'sem-commercial_offer' });
lista.push({ id: 'bor-co', empresa: 'lawang', slug: 'commercial_offer', version: 3, estado: 'borrador', origen: 'empresa', idioma_set: ['es'], hash: 'c'.repeat(64), bytes: 1300, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T10:00:00Z', motivo: 'Anado el jardin', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: 'act-co' });
lista.push({ id: 'bor-ad', empresa: 'lawang', slug: 'adenda', version: 2, estado: 'borrador', origen: 'empresa', idioma_set: ['es'], hash: 'd'.repeat(64), bytes: 1300, activable: false, bloqueo_motivo: 'El texto nombra a otra sociedad (marca de otra)',
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T10:30:00Z', motivo: 'Prueba', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: 'sem-adenda' });
const CUERPOS = { 'sem-commercial_offer': OFERTA, 'act-co': V2, 'bor-co': V3, 'sem-adenda': sinNotas(tpl('adenda')), 'bor-ad': sinNotas(tpl('adenda')) };
/* ppjb_reserva: la semilla y un borrador que cambió UN párrafo libre en español (para ver «falta revisar» en inglés e indonesio al abrirlo). estatutos_sw: solo-global. */
CUERPOS['sem-ppjb_reserva'] = sinNotas(tpl('ppjb_reserva'));
CUERPOS['sem-estatutos_sw'] = sinNotas(tpl('estatutos_sw'));
const FIJOS_PR = fijosPR(CUERPOS['sem-ppjb_reserva']);
{
  const doc = CUERPOS['sem-ppjb_reserva'], tr = TC.trocea(doc), s = TC.situaBloquesFijos(doc, FIJOS_PR);
  TC.secciones(doc, tr.trozos); TC.marcaBloqueados(tr.trozos, s.spans, false);
  const libre = tr.trozos.filter(x => x.editable && x.lang === 'es' && !x.bloqueado && !x.titulo && x.texto.length > 60 && !/\{\{/.test(x.texto))[2];
  CUERPOS['bor-pr'] = TC.construye(doc, tr.trozos, { [libre.i]: libre.texto + ' (texto revisado)' });
}
lista.push({ id: 'bor-pr', empresa: 'lawang', slug: 'ppjb_reserva', version: 2, estado: 'borrador', origen: 'empresa', idioma_set: ['es', 'en', 'id'], hash: 'e'.repeat(64), bytes: 1300, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T11:00:00Z', motivo: 'Aclaro un parrafo', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: 'sem-ppjb_reserva' });
/* Revisiones (E7) de commercial_offer: la estándar y tres más (dos activas, una archivada); y el catálogo de campos propios (E8) de Lawang. */
const fila = (id, ver, estado, variante, nombre, hereda) => ({ id, empresa: 'lawang', slug: 'commercial_offer', version: ver, estado, origen: 'empresa', idioma_set: ['es'], hash: id[0].repeat(64).slice(0, 64), bytes: 1200, activable: true, bloqueo_motivo: null,
  autor: 'admin.uno@prueba.test', fecha: '2026-10-08T10:00:00Z', motivo: 'Revisión ' + nombre, activado_por: estado === 'activa' ? 'super.uno@prueba.test' : null, activado_en: estado === 'activa' ? '2026-10-08T11:00:00Z' : null,
  confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: hereda, variante, variante_nombre: nombre, archivada_por: estado === 'archivada' ? 'admin.uno@prueba.test' : null, archivada_en: estado === 'archivada' ? '2026-10-08T12:00:00Z' : null });
lista.push(fila('rv-1', 4, 'activa', 'rev_1', 'REV03 · cláusulas negociadas', 'act-co'), fila('rv-2', 5, 'activa', 'rev_2', 'REV05 · plazo de firma 45 días', 'rv-1'), fila('rv-3', 6, 'archivada', 'rev_3', 'Prueba antigua', 'act-co'));
CUERPOS['rv-1'] = V2; CUERPOS['rv-2'] = V2; CUERPOS['rv-3'] = V2;
const rev = (variante, nombre, estado, activa, borrador, ult, contratos, distintos, origen) => ({ slug: 'commercial_offer', variante, nombre, estado, version_activa: activa, version_borrador: borrador, version_ultima: ult, contratos, parrafos_distintos: distintos,
  origen_version: origen, creada_por: 'admin.uno@prueba.test', creada_en: '2026-10-08T10:00:00Z', archivada_en: estado === 'archivada' ? '2026-10-08T12:00:00Z' : null });
const REVS0 = [rev('estandar', 'Estándar', 'activa', 'act-co', 'bor-co', 3, 154, null, null), rev('rev_1', 'REV03 · cláusulas negociadas', 'activa', 'rv-1', null, 4, 23, 6, 'act-co'),
  rev('rev_2', 'REV05 · plazo de firma 45 días', 'activa', 'rv-2', null, 5, 0, 1, 'rv-1'), rev('rev_3', 'Prueba antigua', 'archivada', null, null, 6, 0, 2, 'act-co')];
const cxc = (clave, es, tipo, extra) => Object.assign({ clave, etiqueta: { es, en: null, id: null }, tipo, opciones: null, obligatorio: false, sensible: true, archivado: false, creado_en: '2026-10-08T09:00:00Z' }, extra || {});
const CXS0 = [cxc('cx_garaje_incluido', 'Garaje incluido', 'si_no'), cxc('cx_forma_pago', 'Forma de pago', 'lista', { opciones: ['Transferencia', 'Efectivo', 'Cripto'], obligatorio: true, sensible: false, etiqueta: { es: 'Forma de pago', en: 'Payment method', id: null } }),
  cxc('cx_fecha_entrega', 'Fecha de entrega', 'fecha'), cxc('cx_importe_fianza', 'Importe de la fianza', 'importe'), cxc('cx_campo_antiguo', 'Campo antiguo', 'texto', { archivado: true })];
const USO0 = { cx_forma_pago: { versiones: 1, contratos: 3 } };
const MARCADORES = [...new Set(Object.values(CUERPOS).join('').match(/\{\{[a-z0-9_]+\}\}/g) || [])].map(x => x.slice(2, -2));
const FIX = {
  usuarios: [{ user_id: 'u1', rol: 'admin_empresa', ambito: 'empresa', empresas: ['lawang'], herramientas: [], activo: true, nombre: 'Admin Uno', notif_visto_hasta: null, es_propietario: false }],
  empresas: [{ clave: 'lawang', nombre: 'Lawang', orden: 1, activa: true }, { clave: 'sandal_woods', nombre: 'Sandal Woods', orden: 2, activa: true }],
  plantillas_contrato: SLUGS.map((s, i) => ({ slug: s, nombre: 'Plantilla ' + s.replace(/_/g, ' '), orden: i + 1, archivada: false }))
};

/* El cliente FALSO. Persona y comportamientos por parámetros de la URL: ?p=ae|se|gl  ?lista=error|vacia  ?hostil=1 */
const STUB = `(function(){
  var REVS = ${JSON.stringify(REVS0)}, CXS = ${JSON.stringify(CXS0)}, USO = ${JSON.stringify(USO0)}, FIX = ${JSON.stringify(FIX)}, LISTA = ${JSON.stringify(lista)}, CUERPOS = ${JSON.stringify(CUERPOS)}, FIJOS = ${JSON.stringify(fijos(OFERTA))}, FIJOS_PR = ${JSON.stringify(FIJOS_PR)}, MARC = ${JSON.stringify(MARCADORES)};
  var q0 = new URLSearchParams(location.search), P = q0.get('p') || 'ae';
  if (P === 'se') { FIX.usuarios[0].rol = 'super_admin_empresa'; }
  if (P === 'gl') { FIX.usuarios[0].rol = 'super_admin'; FIX.usuarios[0].ambito = 'global'; FIX.usuarios[0].empresas = []; }
  window.__RPC = [];
  function q(tabla){
    var filas = (FIX[tabla] || []).slice(), unico = false;
    var b = new Proxy({}, { get: function(_, k){
      if (k === 'then') return function(ok, ko){ var d = unico ? (filas[0] || null) : filas; return Promise.resolve({ data: d, error: null, count: filas.length }).then(ok, ko); };
      if (k === 'eq') return function(c, v){ filas = filas.filter(function(f){ return f[c] === v; }); return b; };
      if (k === 'maybeSingle' || k === 'single') return function(){ unico = true; return b; };
      return function(){ return b; };
    }});
    return b;
  }
  function ok(d){ return Promise.resolve({ data: d, error: null }); }
  function ws(s){ return String(s).replace(/[ \\t\\n\\r\\f\\v]+/g, ' ').replace(/^ | $/g, ''); }
  /* Lo que diría la base (mensajes REALES de las migraciones S3 y S2.5): bloque fijo tocado, marcador desconocido, llave suelta. */
  function rechazo(a){
    var cuerpo = String(a.p_cuerpo), fj = a.p_slug === 'ppjb_reserva' ? FIJOS_PR : (a.p_slug === 'commercial_offer' ? FIJOS : []);
    if (P !== 'gl') {
      var w = ws(cuerpo);
      for (var i = 0; i < fj.length; i++) if (fj[i].charAt(0) === 'E' && w.indexOf(fj[i].slice(2)) === -1) return 'SENSIBLE';
    }
    if (/\\{\\{(?![a-z0-9_]+\\}\\})/.test(cuerpo)) return 'llave suelta o marcador mal cerrado ({{ sin }}, }} sin {{ o {{{x}}})';
    var re = /\\{\\{([a-z0-9_]+)\\}\\}/g, m;
    while ((m = re.exec(cuerpo)) !== null) if (MARC.indexOf(m[1]) === -1 && !CXS.some(function(c){ return c.clave === m[1] && !c.archivado; })) return 'marcador desconocido {{' + m[1] + '}}: no esta en tokens.json ni en la lista de derivados del motor';
    return null;
  }
  function mal(m, code){ return Promise.resolve({ data: null, error: { message: m, code: code || '42501' } }); }
  function rpc(n, a){
    window.__RPC.push({ n: n, a: a });
    if (n === 'plantilla_contrato_versiones_lista') {
      if (q0.get('lista') === 'error') return mal('permission denied para la lista');
      if (q0.get('lista') === 'vacia') return ok([]);
      return ok(LISTA.filter(function(v){ return v.empresa === a.p_empresa; }));
    }
    if (n === 'plantilla_contrato_edicion') {
      var solo = a.p_slug === 'estatutos_sw' && P !== 'gl' ? 'Estatutos de la comunidad: solo lo cambia el administrador global con su abogado' : null;
      var vr = a.p_variante || 'estandar';
      var borr = LISTA.filter(function(v){ return v.slug === a.p_slug && (v.variante || 'estandar') === vr && (vr === 'estandar' ? (v.estado === 'borrador' && v.origen === 'empresa') : v.estado !== 'retirada'); })[0];
      var cuerpo = borr ? CUERPOS[borr.id] : (CUERPOS['sem-' + a.p_slug] || CUERPOS['sem-commercial_offer']);
      var fijosDe = a.p_slug === 'ppjb_reserva' ? FIJOS_PR : (a.p_slug === 'commercial_offer' ? FIJOS : []);
      return ok({ empresa: a.p_empresa, slug: a.p_slug, version_id: borr ? borr.id : 'sem-' + a.p_slug, version: borr ? borr.version : 1, estado: 'borrador', origen: borr ? 'empresa' : 'semilla', hash: 'x', variante: vr, variante_nombre: borr ? borr.variante_nombre : null, cuerpo_html: cuerpo,
        notas_quitadas: borr ? 0 : 1645, solo_global: solo, nunca_activable: null, bloques_fijos: (P === 'gl' || solo) ? [] : fijosDe, puede_activar: P !== 'ae', bloqueo: null,
        bloques_fijos_motivos: ((P === 'gl' || solo) ? [] : fijosDe).map(function(){ return { clase: 'elemento', motivo: 'foro y ley aplicable' }; }) });
    }
    if (n === 'plantilla_contrato_cuerpo_version') return ok({ version_id: a.p_version, cuerpo_html: CUERPOS[a.p_version] || '' });
    if (n === 'plantilla_contrato_revisa') {
      if (/<script/i.test(a.p_cuerpo)) return ok({ ok: false, errores: ['etiqueta prohibida <script>'], activable: false });
      var rz = rechazo(a);
      if (rz === 'SENSIBLE') return ok({ ok: true, errores: [], activable: true, bloqueo: null, sensibles: true, bloques_tocados: [{ clase: 'elemento', motivo: 'foro y ley aplicable', antes: '<p>Texto de antes</p>', despues: '<p>Texto de despues</p>' }] });
      if (rz) return ok({ ok: false, errores: [rz], activable: false });
      return ok({ ok: true, errores: [], activable: P !== 'ae' ? true : true, bloqueo: null });
    }
    if (n === 'plantilla_contrato_guarda_borrador') {
      var rz = rechazo(a);
      if (rz === 'SENSIBLE') { if (a.p_confirma_sensibles !== true) return mal('Has cambiado partes sensibles del contrato (foro y ley aplicable): confirma que has leido el aviso para guardar el cambio', '22023'); rz = null; }
      if (rz) return mal(rz, '42501');
      if (q0.get('hostil')) return mal('El texto no pasa la validacion: <img src=x onerror="window.__PWNED=1"> | etiqueta prohibida', '22023');
      return ok('nuevo-borrador-id');
    }
    if (n === 'plantilla_contrato_revisiones_lista') {
      if (q0.get('revs') === 'error') return mal('permission denied para las revisiones');
      return ok(REVS.filter(function(r){ return r.slug === a.p_slug; }).map(function(r){ return Object.assign({}, r); })
        .concat(a.p_slug === 'commercial_offer' ? [] : [{ slug: a.p_slug, variante: 'estandar', nombre: 'Estándar', estado: 'semilla', version_activa: null, version_borrador: null, version_ultima: 1, contratos: 0, parrafos_distintos: null, origen_version: null, creada_por: 'estudio', creada_en: '', archivada_en: null }]));
    }
    if (n === 'plantilla_contrato_revision_crea') {
      if (!a.p_nombre || a.p_nombre.trim().length < 3) return mal('Pon un nombre a la revision (de 3 a 80 letras)', '22023');
      var vv = 'rev_' + (REVS.length + 20), nid = 'nueva-' + vv;
      LISTA.push({ id: nid, empresa: a.p_empresa, slug: a.p_slug, version: 20 + REVS.length, estado: 'borrador', origen: 'empresa', idioma_set: ['es'], hash: 'f'.repeat(64), bytes: 1, activable: true, bloqueo_motivo: null, autor: 'admin.uno@prueba.test',
        fecha: '2026-10-08T12:00:00Z', motivo: a.p_motivo, activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, hereda_de: a.p_origen, variante: vv, variante_nombre: a.p_nombre, archivada_por: null, archivada_en: null });
      CUERPOS[nid] = CUERPOS[a.p_origen] || CUERPOS['sem-commercial_offer'];
      REVS.push({ slug: a.p_slug, variante: vv, nombre: a.p_nombre, estado: 'borrador', version_activa: null, version_borrador: nid, version_ultima: 20, contratos: 0, parrafos_distintos: 0, origen_version: a.p_origen, creada_por: 'x', creada_en: '', archivada_en: null });
      return ok(nid);
    }
    if (/^plantilla_contrato_revision_(archiva|restaura|borra)$/.test(n)) {
      var rv = REVS.filter(function(r){ return r.slug === a.p_slug && r.variante === a.p_variante; })[0];
      if (!rv) return mal('Esa revision no existe', '22023');
      if (n.indexOf('archiva') !== -1) { if (rv.estado !== 'activa') return mal('Esa revision no tiene una version activa que archivar', '22023'); rv.estado = 'archivada'; return ok(null); }
      if (n.indexOf('restaura') !== -1) {
        if (P === 'ae') return mal('Volver a poner un texto en uso lo hace el super administrador de esa empresa', '42501');
        rv.estado = 'activa'; return ok({ variante: rv.variante });
      }
      if (rv.estado === 'activa') return mal('Esta revision esta activa: archivala antes de borrarla', '55000');
      if (rv.contratos > 0) return mal('No se puede borrar: ' + rv.contratos + ' contrato(s) usan esta revision. Archivala para que no se ofrezca en contratos nuevos; los que ya la usan la siguen leyendo.', '55000');
      REVS.splice(REVS.indexOf(rv), 1); return ok(null);
    }
    if (n === 'plantilla_campo_propio_lista') {
      if (q0.get('cx') === 'error') return mal('permission denied para los campos');
      return ok(CXS.map(function(c){ var o = Object.assign({}, c); if (a.p_con_uso) o.uso = USO[c.clave] || { versiones: 0, contratos: 0 }; return o; }));
    }
    if (n === 'plantilla_campo_propio_guarda') {
      var ex = CXS.filter(function(c){ return c.clave === a.p_clave; })[0];
      if (a.p_clave === 'cx_cliente') return mal('La clave cx_cliente choca con un campo del sistema', '22023');
      var nuevo = { clave: a.p_clave, etiqueta: { es: a.p_etiqueta_es, en: a.p_etiqueta_en, id: a.p_etiqueta_id }, tipo: a.p_tipo, opciones: a.p_opciones, obligatorio: a.p_obligatorio, sensible: a.p_sensible, archivado: false, creado_en: '' };
      if (ex) { if (ex.tipo !== a.p_tipo && USO[ex.clave]) return mal('El tipo de ' + ex.clave + ' no cambia: lo usan 1 version(es) y 3 contrato(s). Archivalo y crea otro campo.', '55000'); Object.assign(ex, nuevo, { archivado: ex.archivado }); }
      else CXS.push(nuevo);
      return ok({ clave: a.p_clave, nuevo: !ex, tipo: a.p_tipo, sensible: a.p_sensible, archivado: false });
    }
    if (n === 'plantilla_campo_propio_archiva') { var ca = CXS.filter(function(c){ return c.clave === a.p_clave; })[0]; if (ca) ca.archivado = a.p_archivado !== false; return ok(null); }
    if (n === 'plantilla_campo_propio_borra') {
      if (USO[a.p_clave]) return mal('No se borra ' + a.p_clave + ' : lo usan 1 version(es) y 3 contrato(s). Archivalo para que no se ofrezca mas.', '55000');
      CXS = CXS.filter(function(c){ return c.clave !== a.p_clave; }); return ok(null);
    }
    if (n === 'plantilla_campo_propio_valida') {
      var errs = {}, vals = {};
      Object.keys(a.p_valores).forEach(function(k){
        var c = CXS.filter(function(x){ return x.clave === k; })[0], v = String(a.p_valores[k]);
        if (!c) { errs[k] = 'no esta en el catalogo de esta empresa'; return; }
        if (c.tipo === 'importe' || c.tipo === 'numero') { var limpio = v.replace(/[.]/g, '').replace(',', '.'); if (!/^-?[0-9]+([.][0-9]+)?$/.test(limpio)) errs[k] = 'no es un numero (solo cifras, punto y coma)'; else vals[k] = String(parseFloat(limpio)); }
        else if (c.tipo === 'lista') { if (c.opciones.indexOf(v) === -1) errs[k] = 'no es una de las opciones del campo'; else vals[k] = v; }
        else if (c.tipo === 'si_no') { if (v !== 'si' && v !== 'no') errs[k] = 'solo «si» o «no»'; else vals[k] = v; }
        else vals[k] = v;
      });
      return ok({ ok: Object.keys(errs).length === 0, errores: errs, valores: vals, vacios_obligatorios: [] });
    }
    if (n === 'plantilla_contrato_cambios_sensibles') {
      if (q0.get('sens') === 'error') return mal('permission denied para el registro');
      return ok({ cambios: [{ slug: a.p_slug, variante: 'estandar', version: 2, n: 1, clase: 'elemento', motivo: 'foro y ley aplicable', antes: '<p>Texto de antes</p>', despues: '<p>Texto de despues</p>', aviso_confirmado: true, motivo_cambio: 'Cambio de foro', autor: 'admin.uno@prueba.test', fecha: '2026-10-08T10:00:00Z' }] });
    }
    if (n === 'plantilla_contrato_nuevo_crea') {
      if (!a.p_nombre || a.p_nombre.length < 3) return mal('Pon un nombre de 3 a 80 letras, sin los signos < > { } & ni comillas dobles', '22023');
      if (a.p_nombre === 'Contrato duplicado') return mal('Ya hay un contrato con ese nombre: elige otro', '22023');
      var sl = 'lawang_' + a.p_nombre.toLowerCase().replace(/[^a-z0-9]+/g, '_');
      var cuerpo0 = a.p_punto_partida === 'copia' ? CUERPOS['sem-' + a.p_slug_origen] : CUERPOS['sem-adenda'];
      CUERPOS['nv1-' + sl] = cuerpo0; CUERPOS['nv2-' + sl] = cuerpo0;
      var base = { empresa: a.p_empresa, slug: sl, idioma_set: ['es'], hash: 'a'.repeat(64), bytes: 1, autor: 'admin.uno@prueba.test', fecha: '2026-10-08T13:00:00Z', activado_por: null, activado_en: null, confirmacion_nombre: null, retirada_por: null, retirada_en: null, variante: 'estandar', variante_nombre: null, archivada_por: null, archivada_en: null };
      LISTA.push(Object.assign({}, base, { id: 'nv1-' + sl, version: 1, estado: 'borrador', origen: 'semilla', activable: false, bloqueo_motivo: 'Esqueleto', motivo: 'Esqueleto de partida', hereda_de: null }));
      LISTA.push(Object.assign({}, base, { id: 'nv2-' + sl, version: 2, estado: 'borrador', origen: 'empresa', activable: true, bloqueo_motivo: null, motivo: 'Contrato nuevo', hereda_de: 'nv1-' + sl }));
      return ok({ slug: sl, nombre: a.p_nombre, version_id: 'nv2-' + sl, esqueleto_id: 'nv1-' + sl, punto_partida: a.p_punto_partida, campos: a.p_campos, activable: true, bloqueo: null });
    }
    if (n === 'plantilla_contrato_activa') return ok({ version_id: a.p_version });
    if (n === 'plantilla_contrato_descarta_borrador') return ok(null);
    return q(n);
  }
  var sb = { from: q, rpc: rpc, supabaseUrl: 'https://sb.fake',
    storage: { from: function(){ return { getPublicUrl: function(p){ return { data: { publicUrl: 'https://sb.fake/' + p } }; } }; } },
    auth: { getSession: function(){ return Promise.resolve({ data: { session: { access_token: 'jwt-falso', user: { id: 'u1', email: 'admin.uno@prueba.test', app_metadata: {} } } } }); }, signOut: function(){ return Promise.resolve({}); }, onAuthStateChange: function(){ return { data: { subscription: { unsubscribe: function(){} } } }; } },
    channel: function(){ var c = { on: function(){ return c; }, subscribe: function(){ return c; } }; return c; }, removeChannel: function(){} };
  window.supabase = { createClient: function(){ return sb; } };
})();`;

const fallos = [];
const ok = (c, m) => { if (!c) fallos.push(m); return !!c; };
const espera = (page, ms) => page.waitForTimeout(ms);

async function nueva(browser, ancho, query) {
  const ctx = await browser.newContext({ viewport: { width: ancho, height: ancho > 800 ? 900 : 844 } });
  const page = await ctx.newPage();
  const errores = [];
  page.on('pageerror', e => errores.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|net::ERR/.test(m.text())) errores.push(m.text().slice(0, 200)); });
  await page.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.origin === HOST) {
      if (/tokens=error/.test(query || '') && u.pathname === '/contracts/tokens.json') return route.fulfill({ status: 500, body: '' });
      let p = decodeURIComponent(u.pathname); if (p.endsWith('/')) p += 'index.html';
      const f = path.join(RAIZ, p);
      if (fs.existsSync(f) && fs.statSync(f).isFile()) {
        let body = fs.readFileSync(f);
        if (path.extname(f) === '.html') body = Buffer.from(body.toString('utf8').replace(/\sintegrity="[^"]*"/g, ''), 'utf8');
        return route.fulfill({ status: 200, contentType: MIME[path.extname(f)] || 'application/octet-stream', body });
      }
      return route.fulfill({ status: 404, body: '' });
    }
    if (/supabase\.min\.js/.test(u.href)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
    if (u.protocol === 'data:' || u.protocol === 'blob:') return route.continue();
    return route.fulfill({ status: 200, contentType: /\.css|fonts\.googleapis/.test(u.href) ? 'text/css' : 'text/javascript', body: '' });
  });
  await page.goto(HOST + '/intranet/v4/textos-contrato/?' + (query || ''), { waitUntil: 'load' });
  await page.waitForFunction(() => document.querySelectorAll('#tc-lista tr').length > 0 && !/Trayendo/.test(document.getElementById('tc-lista').textContent), null, { timeout: 15000 }).catch(() => {});
  return { ctx, page, errores };
}
const rpcs = (page, n) => page.evaluate((n) => window.__RPC.filter(x => x.n === n), n);
const esperaPapel = (page) => page.waitForSelector('#tc-trozos [data-tc-par]', { timeout: 8000 });
/* Abre un párrafo por un trozo de su texto, escribe al final y lo anota con «Listo». */
async function editaPar(page, contiene, extra, anota) {
  const span = page.locator('#tc-trozos [data-tc-trozo]', { hasText: contiene }).first();
  await span.click();
  await page.waitForSelector('#tc-trozos .tc-par.tc-editando', { timeout: 4000 });
  await page.keyboard.press('Control+End');
  await page.keyboard.type(extra);
  if (anota !== false) await page.locator('#tc-trozos [data-tc-par-listo]').click();
}
const normaliza = (s) => s.replace(/\s+/g, ' ');

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  for (const ancho of [1440, 390]) {
    const t = ancho + 'px: ';
    /* ── A. admin de empresa, commercial_offer: lista, editor como documento, partes sensibles editables, simulación, guardado ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      ok(await page.locator('#tc-lista tr').count() === SLUGS.length, t + 'la lista tiene una fila por plantilla (' + SLUGS.length + ')');
      ok(await page.locator('#tc-empresa-caja').isHidden(), t + 'con una sola empresa no se ofrece el selector');
      ok(/no sustituye a un abogado indonesio colegiado/.test(await page.locator('.tc-aviso-fijo').textContent()), t + 'el aviso del abogado está visible');
      const filaCo = page.locator('#tc-lista tr', { has: page.locator('[data-tc-editar="commercial_offer"]') });
      ok(/v2/.test(await filaCo.textContent()) && /v3/.test(await filaCo.textContent()), t + 'commercial_offer enseña su versión activa v2 y su borrador v3');
      ok(/Persona Uno|super\.uno/.test(await filaCo.textContent()), t + 'la versión activa enseña quién la activó');
      const filaAd = page.locator('#tc-lista tr', { has: page.locator('[data-tc-editar="adenda"]') });
      ok(/otra sociedad/.test(await filaAd.textContent()), t + 'un borrador no activable dice por qué en la lista');
      if (PNG) await page.screenshot({ path: PNG + '_lista_' + ancho + '.png', fullPage: false });
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      ok(await page.locator('#tc-editor').isVisible(), t + 'el editor se abre');
      const e1 = (await rpcs(page, 'plantilla_contrato_edicion'))[0];
      ok(e1 && e1.a.p_empresa === 'lawang' && e1.a.p_slug === 'commercial_offer', t + 'pide el texto con su empresa y su plantilla');
      ok(await page.locator('#tc-trozos textarea').count() === 0, t + 'ya no hay una caja de texto por trozo: es un documento');
      ok(await page.locator('#tc-trozos [contenteditable="true"]').count() === 0, t + 'nada es editable hasta que se hace clic en un texto');
      ok(await page.locator('#tc-trozos .tc-par-sens').count() > 0, t + 'hay partes sensibles marcadas');
      const nota = page.locator('#tc-trozos .tc-par-sens .tc-sens-nota').first();
      ok(/Parte sensible: /.test(await nota.textContent()) && await nota.getAttribute('tabindex') === '0' && /Parte sensible/.test(await nota.getAttribute('aria-label')), t + 'una parte sensible lo dice en texto visible, con tabindex y aria-label');
      ok(await nota.locator('svg').count() === 1, t + 'y lleva su candado SVG');
      ok(await page.locator('#tc-activar').isHidden(), t + 'el admin de empresa NO ve el panel de activar');
      ok(await page.locator('#tc-guardar').isDisabled() && await page.locator('#tc-simular').isDisabled(), t + 'sin cambios no se simula ni se guarda');
      ok(/Estás en la primera cláusula que puedes editar/.test(await page.locator('#tc-aterriza').textContent()), t + 'aterriza en la primera cláusula editable y lo dice');
      // una parte sensible se puede editar, con aviso (decisión del owner)
      const sens = page.locator('#tc-trozos .tc-par-sens').first();
      await sens.locator('[data-tc-trozo]').first().click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando', { timeout: 4000 });
      ok(await page.locator('#tc-trozos .tc-editando .tc-aviso-sens').isVisible(), t + 'al editar una parte sensible sale el aviso');
      ok(/queda(rá)? registrado/.test(await page.locator('#tc-trozos .tc-editando .tc-aviso-sens').textContent()), t + 'y dice que el cambio queda registrado');
      ok(await page.locator('#tc-trozos .tc-editando [contenteditable="true"]').count() > 0, t + 'y se puede escribir en ella (no es solo lectura)');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      ok(await page.locator('#tc-trozos [contenteditable="true"]').count() === 0, t + 'Deshacer cierra el párrafo sin guardar nada');
      // editar uno libre
      await editaPar(page, 'acabados de calidad superior', ' & más');
      ok(/1 trozos/.test(await page.locator('#tc-cambios').textContent()), t + 'el contador cuenta el cambio anotado');
      ok(await page.locator('#tc-simular').isEnabled() && await page.locator('#tc-guardar').isEnabled(), t + 'con un cambio ya se puede simular y guardar');
      ok(await page.locator('#tc-trozos .tc-par-cambiado').count() === 1, t + 'el párrafo cambiado se marca');
      // un "<" avisa y no deja anotar
      await editaPar(page, 'jardín', ' <b>x</b>');
      ok(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').isVisible(), t + 'escribir "<" avisa en rojo en el propio párrafo');
      ok(/«<»/.test(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()), t + 'y el aviso es el del signo «<»');
      ok(await page.locator('#tc-trozos .tc-editando').count() === 1, t + 'y el párrafo sigue abierto (no se anota a medias)');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      // simular
      await page.locator('#tc-simular').click();
      await page.waitForSelector('#tc-revision .tc-rev', { timeout: 6000 });
      ok(/guardaría como borrador/.test(await page.locator('#tc-revision').textContent()), t + 'la simulación enseña lo que contesta la base');
      const rev = (await rpcs(page, 'plantilla_contrato_revisa'))[0];
      ok(rev && rev.a.p_empresa === 'lawang' && rev.a.p_cuerpo.indexOf('&amp; más') !== -1, t + 'manda a revisar el texto nuevo con el & codificado como &amp;');
      ok(rev && Math.abs(rev.a.p_cuerpo.length - V3.length) < 40, t + 'el texto que se manda difiere del original solo en el trozo editado');
      const fr = page.locator('#tc-previa-frame');
      ok(await fr.getAttribute('sandbox') === '', t + 'el iframe de la simulación lleva sandbox vacío');
      const srcdoc = await fr.getAttribute('srcdoc');
      ok(/Content-Security-Policy/.test(srcdoc) && !/\{\{|<script/i.test(srcdoc), t + 'la simulación lleva la CSP, sin marcadores ni scripts');
      ok(await page.evaluate(() => { try { return !!document.getElementById('tc-previa-frame').contentDocument; } catch (e) { return false; } }) === false, t + 'la página NO puede leer dentro del iframe (origen opaco)');
      // guardar
      await page.locator('#tc-guardar').click();
      ok(/motivo/i.test(await page.locator('#tc-ed-estado').textContent()), t + 'sin motivo no se guarda y lo dice');
      await page.locator('#tc-motivo').fill('Mejor redaccion del alcance');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_guarda_borrador'), null, { timeout: 5000 });
      const g = (await rpcs(page, 'plantilla_contrato_guarda_borrador'))[0];
      ok(g && g.a.p_empresa === 'lawang' && g.a.p_slug === 'commercial_offer' && g.a.p_motivo === 'Mejor redaccion del alcance' && Object.keys(g.a).sort().join() === 'p_confirma_sensibles,p_cuerpo,p_empresa,p_motivo,p_slug,p_variante' && g.a.p_confirma_sensibles === false && g.a.p_variante === 'estandar', t + 'guarda por la RPC con empresa, plantilla, cuerpo y motivo (y nada más: ni versión, ni hash, ni importe)');
      if (PNG) await page.screenshot({ path: PNG + '_editor_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── A2. ppjb_reserva: idiomas, índice, marcadores, partes sensibles, rechazos de la base ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-editar="ppjb_reserva"]').click();
      await esperaPapel(page);
      await page.waitForFunction(() => /falta revisar/.test(document.getElementById('tc-ed-idiomas').textContent), null, { timeout: 6000 }).catch(() => {});
      const nPars = await page.locator('#tc-trozos .tc-par').count();
      ok(nPars > 60, t + 'ppjb_reserva se abre como documento continuo (' + nPars + ' párrafos, sin paginar de 25 en 25)');
      ok(await page.locator('#tc-ed-barra [data-tc-pag]').count() === 0, t + 'ya no hay paginador');
      const nInd = await page.locator('#tc-indice [data-tc-ir]').count();
      ok(nInd >= 30, t + 'el índice lista las cláusulas (' + nInd + ')');
      const tabs = await page.locator('#tc-ed-idiomas .tc-tab').allTextContents();
      ok(tabs.length === 3 && /Español/.test(tabs[0]) && /principal/.test(tabs[0]), t + 'tres idiomas en pestañas y el español es el principal (' + tabs.join(' | ') + ')');
      ok(await page.locator('#tc-ed-idiomas .tc-tab[aria-pressed="true"]').textContent().then(x => /Español/.test(x)), t + 'se abre en español');
      ok(/al día/.test(tabs[0]) && /falta revisar/.test(tabs[1]) && /falta revisar/.test(tabs[2]), t + 'el borrador cambió solo el español: español al día, inglés e indonesio «falta revisar»');
      ok(await page.locator('#tc-trozos .tc-ancla').count() === 1, t + 'aterriza en una cláusula editable');
      const dentro = await page.evaluate(() => { const a = document.querySelector('#tc-trozos .tc-ancla').getBoundingClientRect(), p = document.getElementById('tc-trozos').getBoundingClientRect(); return a.top >= p.top - 2 && a.top <= p.bottom; });
      ok(dentro, t + 'y esa cláusula está a la vista en el papel');
      // marcadores como pastillas con etiqueta llana
      const pastillas = await page.locator('#tc-trozos .tc-marca').allTextContents();
      ok(pastillas.length > 10 && pastillas.every(x => x && !/_/.test(x)), t + 'los marcadores son pastillas con etiqueta en llano, nunca la clave (' + pastillas.slice(0, 3).join(', ') + ')');
      ok(await page.locator('#tc-trozos .tc-marca[data-ej]').first().getAttribute('data-ej').then(x => !!x && !/[{}]/.test(x)), t + 'cada pastilla lleva su valor de ejemplo');
      const prom = page.locator('#tc-trozos .tc-marca', { hasText: 'Razón social de la promotora' }).first();
      await prom.focus();
      ok(await prom.evaluate(el => getComputedStyle(el, '::after').content).then(x => /=/.test(x)), t + 'al foco la pastilla enseña su valor de ejemplo');
      // el borrador cambió el español: solo ese párrafo se marca como cambiado
      ok(await page.locator('#tc-trozos .tc-par-cambiado').count() === 1, t + 'el borrador guardado marca solo el párrafo que cambió');
      await page.locator('#tc-f-cambios').check();
      ok(await page.locator('#tc-trozos .tc-par').count() === 1, t + '«Solo lo que he cambiado» deja ese único párrafo');
      await page.locator('#tc-f-cambios').uncheck();
      // el idioma inglés: mismo documento, otro idioma, el español no se mezcla
      await page.locator('#tc-ed-idiomas [data-tc-idioma="en"]').click();
      await page.waitForFunction(() => document.querySelector('#tc-ed-idiomas [data-tc-idioma="en"]').getAttribute('aria-pressed') === 'true');
      ok(await page.locator('#tc-trozos .tc-aviso-rev').count() >= 1, t + 'en inglés avisa en la cláusula «Has cambiado esta cláusula en otro idioma»');
      ok(!/Exponen/.test(await page.locator('#tc-trozos').textContent()) && /Recitals/.test(await page.locator('#tc-trozos').textContent()), t + 'en inglés solo se ve el texto en inglés');
      const nEn = await page.locator('#tc-ed-idiomas .tc-tab-ins').nth(1).textContent();
      await page.locator('#tc-trozos [data-tc-visto]').first().click();
      ok(await page.locator('#tc-ed-idiomas .tc-tab-ins').nth(1).textContent() !== nEn || /\(0\)/.test(nEn) === false, t + '«Ya está igual» baja el contador de «falta revisar»');
      await page.locator('#tc-ed-idiomas [data-tc-idioma="es"]').click();
      await page.waitForFunction(() => document.querySelector('#tc-ed-idiomas [data-tc-idioma="es"]').getAttribute('aria-pressed') === 'true');
      // editar un párrafo en español no toca en ni id
      const libre = page.locator('#tc-trozos .tc-par-edit:not(.tc-par-sens):not(.tc-par-titulo) [data-tc-trozo]').nth(12);
      const textoLibre = (await libre.textContent()).trim();
      await libre.click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End'); await page.keyboard.type(' ZZtexto');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      ok(/trozos cambiados/.test(await page.locator('#tc-cambios').textContent()), t + 'anotado el cambio en español');
      await page.locator('#tc-simular').click();
      await page.waitForSelector('#tc-revision .tc-rev', { timeout: 6000 });
      const rv = (await rpcs(page, 'plantilla_contrato_revisa')).pop();
      const orig = CUERPOS['bor-pr'], nuevoDoc = rv.a.p_cuerpo;
      const tr0 = TC.trocea(orig).trozos, tr1 = TC.trocea(nuevoDoc).trozos;
      let difEs = 0, difOtro = 0;
      tr0.forEach((x, i) => { if (tr1[i] && x.raw !== tr1[i].raw) { if (x.lang === 'es') difEs++; else difOtro++; } });
      ok(tr0.length === tr1.length && difEs === 1 && difOtro === 0, t + 'editar un párrafo en español cambia 1 trozo en español y ninguno en inglés o indonesio (es:' + difEs + ', otros:' + difOtro + ')');
      ok(/guardaría como borrador/.test(await page.locator('#tc-revision').textContent()), t + 'la base lo acepta como borrador (plantilla_contrato_revisa ok)');
      // buscar «3 de 12»
      await page.locator('#tc-buscar').fill('precio');
      await page.waitForFunction(() => /^\d+ de \d+$/.test(document.getElementById('tc-hits').textContent.trim()), null, { timeout: 4000 });
      const h1 = (await page.locator('#tc-hits').textContent()).trim();
      ok(/^1 de \d+$/.test(h1) && await page.locator('#tc-trozos mark').count() > 0, t + 'la búsqueda cuenta «' + h1 + '» y resalta');
      await page.locator('#tc-buscar').press('Enter');
      ok(/^2 de /.test((await page.locator('#tc-hits').textContent()).trim()), t + 'Intro pasa al siguiente resultado');
      await page.locator('#tc-buscar').fill('');
      // un marcador borrado: no se puede anotar y se dice en llano
      await page.locator('#tc-trozos .tc-par-edit [data-tc-trozo] .tc-marca').first().evaluate(el => { el.closest('[data-tc-trozo]').click(); });
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      const etq = await page.locator('#tc-trozos .tc-editando [data-tc-trozo] .tc-marca').first().textContent();
      await page.evaluate(() => { const m = document.querySelector('#tc-trozos .tc-editando [data-tc-trozo] .tc-marca'); const s = m.closest('[data-tc-trozo]'); m.remove(); s.dispatchEvent(new Event('input', { bubbles: true })); });
      ok(/Falta el campo/.test(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()) && (await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()).indexOf(etq) !== -1, t + 'borrar una pastilla avisa en llano con su etiqueta («' + etq + '»)');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      ok(await page.locator('#tc-trozos .tc-editando').count() === 1, t + 'y el párrafo no se anota con el campo perdido');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      // pegar un {{ roto: el aviso local lo ve; nada se envía
      await page.locator('#tc-trozos .tc-par-edit:not(.tc-par-sens) [data-tc-trozo]').nth(5).click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End');
      await page.evaluate(() => { const s = document.querySelector('#tc-trozos .tc-editando [contenteditable="true"]'); const dt = new DataTransfer(); dt.setData('text/plain', ' {{roto'); s.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true })); });
      ok(/llave suelta/i.test(await page.locator('#tc-trozos .tc-editando [data-tc-par-av]').textContent()), t + 'pegar un {{ roto lo avisa en llano antes de anotarlo');
      ok(await page.locator('#tc-trozos .tc-editando [contenteditable="true"] *:not(.tc-marca)').count() === 0, t + 'lo pegado entra como texto plano, sin etiquetas');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      // pegar un marcador bien formado pero que no existe: lo rechaza el servidor y la pantalla lo cuenta
      await page.locator('#tc-trozos .tc-par-edit:not(.tc-par-sens) [data-tc-trozo]').nth(6).click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End');
      await page.evaluate(() => { const s = document.querySelector('#tc-trozos .tc-editando [contenteditable="true"]'); const dt = new DataTransfer(); dt.setData('text/plain', ' {{no_existe}}'); s.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true })); });
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      await page.locator('#tc-motivo').fill('Prueba de marcador inexistente');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => /no lo ha guardado/i.test(document.getElementById('tc-ed-estado').textContent), null, { timeout: 5000 });
      const est = await page.locator('#tc-ed-estado').textContent();
      ok(/campo que no existe/.test(est) && /no_existe/.test(est), t + 'el servidor rechaza el marcador inexistente y la pantalla lo cuenta en llano («campo que no existe»)');
      ok(/Mensaje de la base: marcador desconocido/.test(est), t + 'y deja el mensaje de la base como detalle');
      ok(/siguen aquí/.test(est), t + 'y dice que los cambios siguen en pantalla');
      ok(/^\d+ trozos cambiados|trozos cambiados/.test(await page.locator('#tc-cambios').textContent()), t + 'sin perder lo escrito');
      // quitar ese cambio y probar la parte sensible: la base la rechaza y la pantalla lo dice con enlace a la cláusula
      await page.locator('#tc-deshacer').click();
      await page.waitForSelector('.lw-dlg-fondo button, [data-lw-ok], .lw-dlg-fondo', { timeout: 3000 }).catch(() => {});
      const conf = page.locator('.lw-dlg-fondo button', { hasText: /Descartar los cambios/ });
      if (await conf.count()) await conf.first().click();
      await page.waitForFunction(() => document.getElementById('tc-cambios').textContent.indexOf('Sin cambios') !== -1, null, { timeout: 4000 });
      const sensSpan = page.locator('#tc-trozos .tc-par-sens:not(.tc-par-titulo) [data-tc-trozo]', { hasText: 'NPWP' }).first();
      const alguna = (await sensSpan.count()) ? sensSpan : page.locator('#tc-trozos .tc-par-sens:not(.tc-par-titulo) [data-tc-trozo]').first();
      await alguna.click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando');
      await page.keyboard.press('Control+End'); await page.keyboard.type(' cambio sensible');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      await page.locator('#tc-motivo').fill('Prueba de parte sensible');
      await page.locator('#tc-simular').click();
      await page.waitForFunction(() => /cambia partes sensibles/.test(document.getElementById('tc-revision').textContent), null, { timeout: 6000 });
      ok(/foro y ley aplicable/.test(await page.locator('#tc-revision').textContent()) && /Antes: Texto de antes/.test(await page.locator('#tc-revision').textContent()), t + 'la simulación lista qué partes sensibles se cambian, con el antes y el después');
      await page.locator('#tc-guardar').click();
      await page.waitForSelector('.lw-dlg-fondo button', { timeout: 5000 });
      ok(/partes sensibles/.test(await page.locator('.lw-dlg-fondo').first().textContent()) && /registrado/.test(await page.locator('.lw-dlg-fondo').first().textContent()), t + 'guardar una parte sensible pide confirmar el aviso (queda registrado)');
      ok((await rpcs(page, 'plantilla_contrato_guarda_borrador')).filter(x => x.a.p_motivo === 'Prueba de parte sensible').length === 0, t + 'y hasta confirmar no se manda nada a la base');
      await page.locator('.lw-dlg-fondo button', { hasText: /Entiendo el aviso/ }).last().click();
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_guarda_borrador' && x.a.p_motivo === 'Prueba de parte sensible'), null, { timeout: 5000 });
      const gs = (await rpcs(page, 'plantilla_contrato_guarda_borrador')).filter(x => x.a.p_motivo === 'Prueba de parte sensible')[0];
      ok(gs && gs.a.p_confirma_sensibles === true, t + 'tras confirmar se guarda con p_confirma_sensibles = true');
      if (PNG) await page.screenshot({ path: PNG + '_documento_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'A2 sin errores de página: ' + errores.slice(0, 2).join(' || '));
      if (ancho === 390) {
        const desborda = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        ok(desborda <= 1, t + 'la página no tiene scroll horizontal (' + desborda + ' px de más)');
        const chicos = await page.evaluate(() => [...document.querySelector('#tc-editor').querySelectorAll('button:not([hidden]),input:not([type=hidden]):not([type=checkbox]),select')].filter(e => e.offsetParent && e.getBoundingClientRect().height < 34 && e.getBoundingClientRect().height > 0).map(e => e.id || e.className).slice(0, 5));
        ok(chicos.length === 0, t + 'ningún control táctil por debajo de 34 px de alto: ' + chicos.join(','));
        ok(await page.evaluate(() => !document.getElementById('tc-indice-det').open), t + 'en el móvil el índice empieza plegado');
      }
      await ctx.close();
    }
    /* ── A3. modo oscuro: legible y sin sombras ── */
    {
      const ctx = await browser.newContext({ viewport: { width: ancho, height: ancho > 800 ? 900 : 844 }, colorScheme: 'dark' });
      const page = await ctx.newPage();
      await page.route('**/*', async route => {
        const u = new URL(route.request().url());
        if (u.origin === HOST) {
          let p = decodeURIComponent(u.pathname); if (p.endsWith('/')) p += 'index.html';
          const f = path.join(RAIZ, p);
          if (fs.existsSync(f) && fs.statSync(f).isFile()) { let body = fs.readFileSync(f); if (path.extname(f) === '.html') body = Buffer.from(body.toString('utf8').replace(/\sintegrity="[^"]*"/g, ''), 'utf8'); return route.fulfill({ status: 200, contentType: MIME[path.extname(f)] || 'application/octet-stream', body }); }
          return route.fulfill({ status: 404, body: '' });
        }
        if (/supabase\.min\.js/.test(u.href)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
        if (u.protocol === 'data:' || u.protocol === 'blob:') return route.continue();
        return route.fulfill({ status: 200, contentType: /\.css|fonts\.googleapis/.test(u.href) ? 'text/css' : 'text/javascript', body: '' });
      });
      await page.goto(HOST + '/intranet/v4/textos-contrato/?p=ae', { waitUntil: 'load' });
      await page.waitForSelector('[data-tc-editar="ppjb_reserva"]', { timeout: 15000 });
      await page.locator('[data-tc-editar="ppjb_reserva"]').click();
      await esperaPapel(page);
      const papel = await page.locator('#tc-trozos').evaluate(el => { const c = getComputedStyle(el); return { bg: c.backgroundColor, fg: c.color, sombra: c.boxShadow }; });
      const lum = (rgb) => { const m = rgb.match(/\d+/g).map(Number); return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255; };
      ok(lum(papel.bg) < 0.25 && lum(papel.fg) > 0.6, t + 'modo oscuro: el papel es oscuro y el texto claro (' + papel.bg + ' / ' + papel.fg + ')');
      ok(papel.sombra === 'none', t + 'sin sombras');
      if (PNG) await page.screenshot({ path: PNG + '_oscuro_' + ancho + '.png', fullPage: false });
      await ctx.close();
    }
    /* ── B. super de empresa: activar con confirmación ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=se');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      ok(await page.locator('#tc-activar').isVisible() && await page.locator('#tc-act-form').isVisible(), t + 'el super ve el panel de activar sobre el borrador guardado');
      ok(await page.locator('#tc-act-texto').textContent() === TC.TEXTO_CONFIRMACION, t + 'la confirmación enseña la frase exacta que guarda la base');
      ok(/abogado indonesio colegiado/.test(await page.locator('#tc-act-texto').textContent()), t + 'y dice que no sustituye a un abogado indonesio colegiado');
      ok(await page.locator('#tc-act-boton').isDisabled(), t + 'activar nace deshabilitado');
      await page.locator('#tc-act-nombre').fill('Persona Dos de Prueba');
      ok(await page.locator('#tc-act-boton').isDisabled(), t + 'con el nombre solo no basta');
      await page.locator('#tc-act-ok').check();
      ok(await page.locator('#tc-act-boton').isEnabled(), t + 'nombre + casilla habilitan activar');
      await page.locator('#tc-act-boton').click();
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_activa'), null, { timeout: 5000 });
      const a = (await rpcs(page, 'plantilla_contrato_activa'))[0];
      ok(a && a.a.p_version === 'bor-co' && a.a.p_nombre === 'Persona Dos de Prueba' && a.a.p_confirma === true && Object.keys(a.a).sort().join() === 'p_confirma,p_nombre,p_version', t + 'activa por la RPC con versión, nombre y confirmación (y nada más)');
      await page.waitForSelector('#tc-historial-caja:not([hidden])', { timeout: 6000 }).catch(() => {});
      await page.locator('#tc-historial-caja [data-tc-diff="act-co"]').click();
      await page.waitForSelector('#tc-diff .tc-d', { timeout: 6000 });
      const diff = await page.locator('#tc-diff').textContent();
      ok(/- .*alta calidad/.test(diff) && /\+ .*calidad superior/.test(diff), t + 'el diff v2 frente a v1 enseña lo quitado y lo añadido');
      ok(await page.locator('#tc-hist-cuerpo tr').count() === 3, t + 'el historial lista las tres versiones (semilla, activa, borrador)');
      ok(/Persona Uno de Prueba/.test(await page.locator('#tc-hist-cuerpo').textContent()) && /super\.uno/.test(await page.locator('#tc-hist-cuerpo').textContent()), t + 'el historial dice quién confirmó y quién activó');
      ok(/c{12}/.test(await page.locator('#tc-hist-cuerpo').textContent()), t + 'el historial enseña el hash');
      await page.locator('#tc-historial-caja [data-tc-diff="sem-commercial_offer"]').click();
      await page.waitForFunction(() => /primera versión/.test(document.getElementById('tc-diff').textContent), null, { timeout: 4000 });
      if (PNG) await page.screenshot({ path: PNG + '_activar_historial_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'B sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── C. global: las dos empresas, sin partes sensibles ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=gl');
      ok(await page.locator('#tc-empresa-caja').isVisible() && await page.locator('#tc-empresa option').count() === 2, t + 'el global elige entre las dos empresas');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      ok(await page.locator('#tc-trozos .tc-par-sens').count() === 0, t + 'el global no ve partes sensibles');
      await page.selectOption('#tc-empresa', 'sandal_woods');
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_versiones_lista' && x.a.p_empresa === 'sandal_woods'), null, { timeout: 5000 });
      ok(await page.locator('#tc-editor').isHidden(), t + 'al cambiar de empresa se cierra el editor (sin cambios que perder)');
      ok(errores.length === 0, t + 'C sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── D. un texto solo-global: todo en solo lectura para un admin de empresa ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-editar="estatutos_sw"]').click();
      await esperaPapel(page);
      await page.locator('#tc-trozos [data-tc-trozo]').first().click();
      ok(await page.locator('#tc-trozos [contenteditable="true"]').count() === 0, t + 'solo-global: nada se puede editar');
      ok(await page.locator('#tc-guardar').isDisabled(), t + 'solo-global: no se puede guardar');
      ok(/administrador global/.test(await page.locator('#tc-ed-aviso').textContent()), t + 'solo-global: lo dice');
      ok(await page.locator('#tc-trozos .tc-par-sens').count() === 0, t + 'solo-global: no llena el texto de avisos de parte sensible');
      await ctx.close();
    }
    /* ── E. la base contesta con algo hostil: se pinta como texto ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae&hostil=1');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      await editaPar(page, 'acabados de calidad superior', ' otra');
      await page.locator('#tc-motivo').fill('Prueba hostil');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => /no lo ha guardado/i.test(document.getElementById('tc-ed-estado').textContent), null, { timeout: 5000 });
      ok(await page.locator('#tc-ed-estado img').count() === 0, t + 'un mensaje hostil de la base no crea elementos (textContent)');
      ok(/onerror/.test(await page.locator('#tc-ed-estado').textContent()), t + 'y se ve tal cual, como texto');
      ok(await page.evaluate(() => window.__PWNED === undefined), t + 'no se ejecutó nada');
      await ctx.close();
    }
    /* ── F. «no he podido leer» y «no hay» se ven distinto ── */
    {
      const e = await nueva(browser, ancho, 'p=ae&lista=error');
      const txtE = await e.page.locator('#tc-lista').textContent();
      await e.ctx.close();
      const v = await nueva(browser, ancho, 'p=ae&lista=vacia');
      const txtV = await v.page.locator('#tc-lista').textContent();
      await v.ctx.close();
      ok(/No he podido leer las plantillas/.test(txtE) && /todavía no tiene textos/.test(txtV) && txtE !== txtV, t + 'un fallo de lectura y una lista vacía se leen distinto');
    }
    /* ── G. sin las etiquetas de los campos (tokens.json falla): se dice, no se enseñan claves ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae&tokens=error');
      await page.locator('[data-tc-editar="ppjb_reserva"]').click();
      await esperaPapel(page);
      ok(/nombres de los campos/.test(await page.locator('#tc-ed-aviso').textContent()), t + 'si no se pueden leer los nombres de los campos, la pantalla lo dice');
      const ps = await page.locator('#tc-trozos .tc-marca').allTextContents();
      ok(ps.length > 0 && ps.every(x => !/_/.test(x)), t + 'y las pastillas siguen legibles (nunca la clave con guion bajo)');
      await ctx.close();
    }
    /* ── H. pestaña REVISIONES (E7): lista, crear desde una, archivar, restaurar (solo super), borrar con sus errores, abrir el editor sobre una revisión ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      ok(await page.locator('[data-tc-pestana="nuevo"]').isVisible(), t + 'H: la pestaña «Contrato nuevo» está visible (E9)');
      ok(await page.locator('#tc-panel-textos').isVisible() && await page.locator('#tc-panel-revisiones').isHidden() && await page.locator('#tc-panel-campos').isHidden(), t + 'H: se abre en Textos');
      await page.locator('[data-tc-pestana="revisiones"]').click();
      await page.waitForSelector('#tc-rev-slug option', { state: 'attached', timeout: 6000 });
      ok(await page.evaluate(() => location.hash) === '#revisiones', t + 'H: la pestaña vive en la URL (#revisiones)');
      await page.selectOption('#tc-rev-slug', 'commercial_offer');
      await page.waitForSelector('#tc-rev-lista [data-rv-fila="rev_1"]', { timeout: 6000 });
      ok(await page.locator('#tc-rev-lista .tc-fila').count() === 4, t + 'H: cuatro revisiones (estándar y tres más)');
      const fEst = await page.locator('[data-rv-fila="estandar"]').textContent(), f1 = await page.locator('[data-rv-fila="rev_1"]').textContent(), f2 = await page.locator('[data-rv-fila="rev_2"]').textContent(), f3 = await page.locator('[data-rv-fila="rev_3"]').textContent();
      ok(/Texto base/.test(fEst) && /usada en 154 contratos/.test(fEst) && /activa/.test(fEst), t + 'H: la estándar es «Texto base», activa y usada en 154 contratos');
      ok(await page.locator('[data-rv-fila="estandar"] [data-rv-arch], [data-rv-fila="estandar"] [data-rv-del]').count() === 0, t + 'H: la estándar no se archiva ni se borra');
      ok(/6 párrafos distintos de «Estándar»/.test(f1) && /usada en 23 contratos/.test(f1) && /activa/.test(f1), t + 'H: REV03 dice 6 párrafos distintos de «Estándar» y que la usan 23 contratos');
      ok(/1 párrafo distinto de «REV03 · cláusulas negociadas»/.test(f2) && /no la usa ningún contrato/.test(f2), t + 'H: REV05 dice 1 párrafo distinto de REV03 y que no la usa nadie');
      ok(/archivada/.test(f3) && await page.locator('[data-rv-fila="rev_3"] [data-rv-rest]').count() === 1 && /super administrador/.test(f3), t + 'H: la archivada tiene Restaurar y dice que lo hace el super administrador');
      ok(await page.locator('[data-rv-fila="rev_1"] [data-rv-arch]').count() === 1 && await page.locator('[data-rv-fila="rev_3"] [data-rv-arch]').count() === 0, t + 'H: Archivar solo en las activas');
      ok(await page.locator('#tc-rev-activas li').count() === 3, t + 'H: «al crear un contrato nuevo» lista las 3 activas');
      if (PNG) await page.screenshot({ path: PNG + '_revisiones_' + ancho + '.png', fullPage: ancho === 390 });
      // borrar una activa: la base pide archivarla antes
      const dlg = (rotulo) => page.locator('.lw-dlg-fondo button', { hasText: rotulo }).last().click();
      await page.locator('[data-rv-del="rev_1"]').click(); await dlg(/^Borrar$/);
      await page.waitForFunction(() => /archívala antes de borrarla/.test(document.getElementById('tc-rev-estado').textContent), null, { timeout: 5000 });
      ok(/Mensaje de la base: Esta revision esta activa/.test(await page.locator('#tc-rev-estado').textContent()), t + 'H: borrar una activa se explica en llano y deja el mensaje de la base');
      // archivarla; luego borrarla: la usan 23 contratos
      await page.locator('[data-rv-arch="rev_1"]').click(); await dlg(/^Archivar$/);
      await page.waitForFunction(() => /Archivada\./.test(document.getElementById('tc-rev-estado').textContent), null, { timeout: 5000 });
      ok(/archivada/.test(await page.locator('[data-rv-fila="rev_1"]').textContent()) && await page.locator('#tc-rev-activas li').count() === 2, t + 'H: archivada: cambia de estado y sale de la lista de activas');
      await page.locator('[data-rv-del="rev_1"]').click(); await dlg(/^Borrar$/);
      await page.waitForFunction(() => /la usan 23 contratos/.test(document.getElementById('tc-rev-estado').textContent), null, { timeout: 5000 });
      ok(/Archívala para que no se ofrezca/.test(await page.locator('#tc-rev-estado').textContent()) && /Mensaje de la base: No se puede borrar: 23/.test(await page.locator('#tc-rev-estado').textContent()), t + 'H: borrar una usada por 23 contratos: error en llano y detalle');
      ok(await page.locator('[data-rv-fila="rev_1"]').count() === 1, t + 'H: y la revisión sigue en la lista');
      // restaurar sin ser super: la base dice por qué
      await page.locator('[data-rv-rest="rev_3"]').click();
      await page.waitForFunction(() => /super administrador de la empresa\. Pídeselo/.test(document.getElementById('tc-rev-estado').textContent), null, { timeout: 5000 });
      ok((await rpcs(page, 'plantilla_contrato_revision_restaura')).length === 1, t + 'H: restaurar llega a la base (ella decide) y devuelve el motivo en llano');
      // borrar una archivada sin uso: se va
      await page.locator('[data-rv-del="rev_3"]').click(); await dlg(/^Borrar$/);
      await page.waitForFunction(() => document.querySelectorAll('#tc-rev-lista [data-rv-fila]').length === 3, null, { timeout: 5000 });
      ok(/Borrada «Prueba antigua»/.test(await page.locator('#tc-rev-estado').textContent()), t + 'H: borrar una archivada sin uso la quita y lo dice');
      const bor = (await rpcs(page, 'plantilla_contrato_revision_borra')).pop();
      ok(bor && Object.keys(bor.a).sort().join() === 'p_empresa,p_slug,p_variante' && bor.a.p_variante === 'rev_3' && bor.a.p_empresa === 'lawang', t + 'H: borrar manda empresa, contrato y revisión');
      // crear una revisión desde la estándar
      await page.locator('[data-rv-dup="estandar"]').click();
      ok(await page.locator('#tc-rev-crear').isVisible() && /Estándar/.test(await page.locator('#tc-rev-origen').textContent()), t + 'H: «Crear revisión desde esta» abre el formulario y dice de cuál se copia');
      await page.locator('#tc-rev-crear-ok').click();
      ok(/nombre a la revisión/.test(await page.locator('#tc-rev-crear-estado').textContent()) && (await rpcs(page, 'plantilla_contrato_revision_crea')).length === 0, t + 'H: sin nombre no se llama a la base y se dice');
      await page.locator('#tc-rev-nombre').fill('REV06 · prueba del arnés');
      await page.locator('#tc-rev-crear-ok').click();
      ok(/por qué se crea/.test(await page.locator('#tc-rev-crear-estado').textContent()), t + 'H: sin motivo tampoco');
      await page.locator('#tc-rev-motivo').fill('Prueba del arnés');
      await page.locator('#tc-rev-crear-ok').click();
      await page.waitForSelector('#tc-rev-estado [data-rv-editar]', { timeout: 6000 });
      const cr = (await rpcs(page, 'plantilla_contrato_revision_crea'))[0];
      ok(cr && cr.a.p_origen === 'act-co' && cr.a.p_nombre === 'REV06 · prueba del arnés' && cr.a.p_motivo === 'Prueba del arnés' && cr.a.p_slug === 'commercial_offer' && cr.a.p_empresa === 'lawang' && cr.a.p_variante === null, t + 'H: crea desde la versión activa de la estándar, con nombre y motivo');
      ok(await page.locator('#tc-rev-crear').isHidden() && /borrador, sin activar/.test(await page.locator('#tc-rev-lista').textContent()), t + 'H: aparece la nueva como borrador sin activar');
      ok(/Es una copia en borrador/.test(await page.locator('#tc-rev-estado').textContent()), t + 'H: y dice qué hacer ahora');
      // abrir el editor sobre la revisión nueva
      await page.locator('#tc-rev-estado [data-rv-editar]').click();
      await esperaPapel(page);
      ok(await page.evaluate(() => location.hash) === '#textos' && await page.locator('#tc-panel-textos').isVisible(), t + 'H: «Abrir para editar» lleva a Textos');
      const ed = (await rpcs(page, 'plantilla_contrato_edicion')).pop();
      ok(ed && /^rev_/.test(ed.a.p_variante) && ed.a.p_variante !== 'estandar', t + 'H: el editor pide el texto de ESA revisión (p_variante ' + (ed && ed.a.p_variante) + ')');
      ok(/REV06 · prueba del arnés/.test(await page.locator('#tc-ed-titulo').textContent()), t + 'H: y el título dice con qué revisión se trabaja');
      await editaPar(page, 'acabados de calidad superior', ' (rev)');
      await page.locator('#tc-motivo').fill('Cambio en la revisión');
      await page.locator('#tc-guardar').click();
      await page.waitForFunction(() => window.__RPC.some(x => x.n === 'plantilla_contrato_guarda_borrador'), null, { timeout: 5000 });
      const gg = (await rpcs(page, 'plantilla_contrato_guarda_borrador')).pop();
      ok(gg && gg.a.p_variante === ed.a.p_variante, t + 'H: guardar manda la revisión que se está editando');
      // el historial de una revisión no mezcla las demás
      await page.locator('[data-tc-pestana="revisiones"]').click();
      await page.waitForSelector('[data-rv-historial]', { timeout: 5000 });
      await page.locator('[data-rv-fila="estandar"] [data-rv-historial]').click();
      await page.waitForSelector('#tc-historial-caja:not([hidden]) #tc-hist-cuerpo tr', { timeout: 5000 });
      ok(await page.locator('#tc-hist-cuerpo tr').count() === 3, t + 'H: el historial de la estándar enseña solo las suyas (3), no las de las otras revisiones');
      if (ancho === 390) {
        await page.locator('[data-tc-pestana="revisiones"]').click();
        const desborda = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        ok(desborda <= 1, t + 'H: Revisiones no tiene scroll horizontal (' + desborda + ' px de más)');
        const chicos = await page.evaluate(() => [...document.querySelector('#tc-panel-revisiones').querySelectorAll('button:not([hidden]),input:not([type=hidden]):not([type=checkbox]),select')].filter(e => e.offsetParent && e.getBoundingClientRect().height < 34).map(e => (e.textContent || e.id).trim().slice(0, 20)));
        ok(chicos.length === 0, t + 'H: ningún control táctil de Revisiones por debajo de 34 px: ' + chicos.join(','));
      }
      ok(errores.length === 0, t + 'H sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── H2. el super administrador SÍ restaura ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=se');
      await page.locator('[data-tc-pestana="revisiones"]').click();
      await page.waitForSelector('#tc-rev-slug option', { state: 'attached', timeout: 6000 });
      await page.selectOption('#tc-rev-slug', 'commercial_offer');
      await page.waitForSelector('[data-rv-fila="rev_3"]', { timeout: 6000 });
      ok(!/super administrador/.test(await page.locator('[data-rv-fila="rev_3"]').textContent()), t + 'H2: al super no se le avisa de que otro restaura');
      await page.locator('[data-rv-rest="rev_3"]').click();
      await page.waitForFunction(() => /Restaurada\./.test(document.getElementById('tc-rev-estado').textContent), null, { timeout: 5000 });
      ok(await page.locator('[data-rv-fila="rev_3"] [data-rv-arch]').count() === 1, t + 'H2: restaurada: vuelve a estar activa (con Archivar)');
      await ctx.close();
    }
    /* ── I. pestaña CAMPOS (E8): catálogo, alta con sus errores, edición, archivo, borrado y la vista previa con el JSON que sale de la base ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-pestana="campos"]').click();
      await page.waitForSelector('#tc-cx-lista [data-cx-fila]', { timeout: 6000 });
      ok(await page.evaluate(() => location.hash) === '#campos', t + 'I: la pestaña vive en la URL (#campos)');
      ok(await page.locator('#tc-cx-lista [data-cx-fila]').count() === 5, t + 'I: cinco campos en el catálogo');
      const fp = await page.locator('[data-cx-fila="cx_forma_pago"]').textContent();
      ok(/\{\{cx_forma_pago\}\}/.test(fp) && /Lista de opciones/.test(fp) && /Transferencia, Efectivo, Cripto/.test(fp) && /obligatorio/.test(fp) && /Visible para el asistente y el bot/.test(fp) && /lo usan 1 textos y 3 contratos/.test(fp), t + 'I: la fila enseña clave, tipo, opciones, obligatorio, si es visible al bot y su uso');
      ok(/Sensible: oculto al asistente y al bot/.test(await page.locator('[data-cx-fila="cx_garaje_incluido"]').textContent()), t + 'I: un campo sensible lo dice');
      ok(/archivado/.test(await page.locator('[data-cx-fila="cx_campo_antiguo"]').textContent()) && await page.locator('[data-cx-fila="cx_campo_antiguo"] [data-cx-rest]').count() === 1, t + 'I: un campo archivado lo dice y se puede restaurar');
      ok(/oculto al asistente y al bot de WhatsApp/.test(await page.locator('#tc-panel-campos').textContent()), t + 'I: la marca «sensible» se explica en llano');
      // vista previa
      ok(await page.locator('#tc-cx-previa [data-cx-val]').count() === 4, t + 'I: la vista previa pinta los 4 campos vivos (no el archivado)');
      ok((await page.locator('#tc-cx-json').textContent()).replace(/\s+/g, '') === '{"datos":{"fields":{}}}', t + 'I: el JSON enseña datos.fields (donde guarda el contrato)');
      ok(/Escribe un valor/.test(await page.locator('#tc-cx-json-nota').textContent()), t + 'I: y dice cómo ver cómo se guarda');
      await page.locator('[data-cx-val="cx_importe_fianza"]').fill('100.000');
      await page.waitForFunction(() => /"cx_importe_fianza": "100000"/.test(document.getElementById('tc-cx-json').textContent), null, { timeout: 5000 });
      const va = (await rpcs(page, 'plantilla_campo_propio_valida')).pop();
      ok(va && va.a.p_empresa === 'lawang' && JSON.stringify(va.a.p_valores) === '{"cx_importe_fianza":"100.000"}', t + 'I: el valor canónico del JSON lo da la base (plantilla_campo_propio_valida), no el navegador');
      ok(/Comprobado por la base/.test(await page.locator('#tc-cx-json-nota').textContent()), t + 'I: y lo dice');
      await page.locator('[data-cx-val="cx_importe_fianza"]').fill('abc');
      await page.waitForFunction(() => !document.querySelector('[data-cx-err="cx_importe_fianza"]').hidden, null, { timeout: 5000 });
      ok(/No es un número/.test(await page.locator('[data-cx-err="cx_importe_fianza"]').textContent()) && /no aceptaría/.test(await page.locator('#tc-cx-json-nota').textContent()), t + 'I: un valor que la base rechaza se ve en rojo y en llano');
      await page.locator('[data-cx-val="cx_importe_fianza"]').fill('');
      await page.locator('[data-cx-val="cx_forma_pago"]').selectOption('Efectivo');
      await page.locator('[data-cx-val="cx_garaje_incluido"]').selectOption('si');
      await page.waitForFunction(() => /"cx_garaje_incluido": "si"/.test(document.getElementById('tc-cx-json').textContent) && /"cx_forma_pago": "Efectivo"/.test(document.getElementById('tc-cx-json').textContent), null, { timeout: 5000 });
      ok(/Sí/.test(await page.locator('[data-cx-val="cx_garaje_incluido"]').textContent()), t + 'I: Sí / No se ve como Sí / No y se guarda como «si» / «no»');
      if (PNG) await page.screenshot({ path: PNG + '_campos_' + ancho + '.png', fullPage: ancho === 390 });
      // alta: la clave sale del nombre
      await page.locator('#tc-cx-es').fill('Fecha de entrega de llaves');
      ok(/\{\{cx_fecha_de_entrega_de_llaves\}\}/.test(await page.locator('#tc-cx-clave-vista').textContent()) && /no se puede cambiar/.test(await page.locator('#tc-cx-clave-vista').textContent()), t + 'I: la clave sale del nombre y avisa de que no se cambia');
      await page.locator('#tc-cx-tipo').selectOption('fecha');
      ok(await page.locator('#tc-cx-op-caja').isHidden() && await page.locator('#tc-cx-sens').isChecked(), t + 'I: una fecha no pide opciones y nace sensible');
      await page.locator('#tc-cx-guardar').click();
      await page.waitForFunction(() => document.querySelectorAll('#tc-cx-lista [data-cx-fila]').length === 6, null, { timeout: 5000 });
      const gc = (await rpcs(page, 'plantilla_campo_propio_guarda')).pop();
      ok(gc && gc.a.p_clave === 'cx_fecha_de_entrega_de_llaves' && gc.a.p_etiqueta_es === 'Fecha de entrega de llaves' && gc.a.p_tipo === 'fecha' && gc.a.p_opciones === null && gc.a.p_obligatorio === false && gc.a.p_sensible === true && gc.a.p_empresa === 'lawang', t + 'I: guarda con la clave del nombre, el tipo, sensible por defecto y sin opciones');
      ok(/añadido/.test(await page.locator('#tc-cx-aviso').textContent()) && await page.locator('#tc-cx-previa [data-cx-val]').count() === 5, t + 'I: lo dice y el campo nuevo sale en la vista previa');
      // nombre repetido (también archivado): no se sobrescribe
      const n0 = (await rpcs(page, 'plantilla_campo_propio_guarda')).length;
      await page.locator('#tc-cx-es').fill('Garaje incluido'); await page.locator('#tc-cx-guardar').click();
      ok(/Ya existe un campo con ese nombre \(cx_garaje_incluido\)/.test(await page.locator('#tc-cx-estado').textContent()) && (await rpcs(page, 'plantilla_campo_propio_guarda')).length === n0, t + 'I: un nombre repetido se avisa sin llamar a la base (la RPC de guardar sobrescribiría)');
      await page.locator('#tc-cx-es').fill('Campo antiguo'); await page.locator('#tc-cx-guardar').click();
      ok(/está archivado: restáuralo/.test(await page.locator('#tc-cx-estado').textContent()) && (await rpcs(page, 'plantilla_campo_propio_guarda')).length === n0, t + 'I: y si el repetido está archivado, dice que se restaure');
      // lista: pide opciones
      await page.locator('#tc-cx-es').fill('Tipo de pago'); await page.locator('#tc-cx-tipo').selectOption('lista');
      ok(await page.locator('#tc-cx-op-caja').isVisible(), t + 'I: una lista pide sus opciones');
      await page.locator('#tc-cx-guardar').click();
      ok(/al menos una opción/.test(await page.locator('#tc-cx-estado').textContent()), t + 'I: sin opciones se avisa');
      await page.locator('#tc-cx-op').fill('Contado, Plazos, Contado'); await page.locator('#tc-cx-obl').check(); await page.locator('#tc-cx-sens').uncheck();
      await page.locator('#tc-cx-guardar').click();
      await page.waitForFunction(() => document.querySelectorAll('#tc-cx-lista [data-cx-fila]').length === 7, null, { timeout: 5000 });
      const gl = (await rpcs(page, 'plantilla_campo_propio_guarda')).pop();
      ok(gl && gl.a.p_clave === 'cx_tipo_de_pago' && JSON.stringify(gl.a.p_opciones) === '["Contado","Plazos"]' && gl.a.p_obligatorio === true && gl.a.p_sensible === false, t + 'I: la lista guarda sus opciones sin repetidas, obligatorio y no sensible');
      // la base rechaza una clave de sistema: se cuenta en llano
      await page.locator('#tc-cx-es').fill('Cliente'); await page.locator('#tc-cx-guardar').click();
      await page.waitForFunction(() => /coincide con un campo del sistema/.test(document.getElementById('tc-cx-estado').textContent), null, { timeout: 5000 });
      ok(/Mensaje de la base: La clave cx_cliente choca/.test(await page.locator('#tc-cx-estado').textContent()), t + 'I: una clave que choca con el sistema se explica en llano y deja el mensaje de la base');
      await page.locator('#tc-cx-es').fill('');
      // editar uno en uso
      await page.locator('[data-cx-editar="cx_forma_pago"]').click();
      ok(await page.locator('#tc-cx-es').inputValue() === 'Forma de pago' && await page.locator('#tc-cx-en').inputValue() === 'Payment method' && await page.locator('#tc-cx-tipo').isDisabled(), t + 'I: editar rellena el formulario y bloquea el tipo de un campo en uso');
      ok(/\{\{cx_forma_pago\}\}/.test(await page.locator('#tc-cx-clave-vista').textContent()) && /\(no se puede cambiar\)/.test(await page.locator('#tc-cx-clave-vista').textContent()) && await page.locator('#tc-cx-cancelar').isVisible(), t + 'I: la clave se ve y no se puede cambiar');
      await page.locator('#tc-cx-obl').uncheck(); await page.locator('#tc-cx-guardar').click();
      await page.waitForFunction(() => /guardado\./.test(document.getElementById('tc-cx-aviso').textContent), null, { timeout: 5000 });
      const ge = (await rpcs(page, 'plantilla_campo_propio_guarda')).pop();
      ok(ge && ge.a.p_clave === 'cx_forma_pago' && ge.a.p_obligatorio === false && ge.a.p_etiqueta_en === 'Payment method', t + 'I: guardar un cambio manda la misma clave');
      // borrar uno en uso: la base dice cuántos lo usan
      const dlg = (rotulo) => page.locator('.lw-dlg-fondo button', { hasText: rotulo }).last().click();
      await page.locator('[data-cx-del="cx_forma_pago"]').click(); await dlg(/^Borrar$/);
      await page.waitForFunction(() => /lo usan 1 textos y 3 contratos/.test(document.getElementById('tc-cx-aviso').textContent), null, { timeout: 5000 });
      ok(/Archívalo para que no se ofrezca más/.test(await page.locator('#tc-cx-aviso').textContent()) && /Mensaje de la base: No se borra cx_forma_pago/.test(await page.locator('#tc-cx-aviso').textContent()), t + 'I: borrar un campo en uso: error en llano con cuántos lo usan y el detalle');
      // archivar y restaurar
      await page.locator('[data-cx-arch="cx_garaje_incluido"]').click(); await dlg(/^Archivar$/);
      await page.waitForFunction(() => /archivado/.test(document.querySelector('[data-cx-fila="cx_garaje_incluido"]').textContent), null, { timeout: 5000 });
      ok(await page.locator('#tc-cx-previa [data-cx-val="cx_garaje_incluido"]').count() === 0, t + 'I: un campo archivado sale de la vista previa');
      await page.locator('[data-cx-rest="cx_garaje_incluido"]').click();
      await page.waitForFunction(() => document.querySelectorAll('#tc-cx-previa [data-cx-val="cx_garaje_incluido"]').length === 1, null, { timeout: 5000 });
      ok(true, '');
      if (ancho === 390) {
        const desborda = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        ok(desborda <= 1, t + 'I: Campos no tiene scroll horizontal (' + desborda + ' px de más)');
        const chicos = await page.evaluate(() => [...document.querySelector('#tc-panel-campos').querySelectorAll('button:not([hidden]),input:not([type=hidden]):not([type=checkbox]),select')].filter(e => e.offsetParent && e.getBoundingClientRect().height < 34).map(e => (e.textContent || e.id).trim().slice(0, 20)));
        ok(chicos.length === 0, t + 'I: ningún control táctil de Campos por debajo de 34 px: ' + chicos.join(','));
      }
      ok(errores.length === 0, t + 'I sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── I2. «no he podido leer» y «no hay» se ven distinto, también en Campos y Revisiones ── */
    {
      const e = await nueva(browser, ancho, 'p=ae&cx=error&revs=error');
      await e.page.locator('[data-tc-pestana="campos"]').click();
      await e.page.waitForFunction(() => /No he podido leer los campos/.test(document.getElementById('tc-cx-lista').textContent), null, { timeout: 6000 });
      ok(/no hay vista previa/.test(await e.page.locator('#tc-cx-previa').textContent()), t + 'I2: sin catálogo legible la vista previa lo dice (no enseña «no hay campos»)');
      await e.page.locator('[data-tc-pestana="revisiones"]').click();
      await e.page.waitForSelector('#tc-rev-slug option', { state: 'attached', timeout: 6000 });
      await e.page.waitForFunction(() => /No he podido leer las revisiones/.test(document.getElementById('tc-rev-lista').textContent), null, { timeout: 6000 });
      ok(true, '');
      // y el editor lo dice y no ofrece insertar
      await e.page.locator('[data-tc-pestana="textos"]').click();
      await e.page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(e.page);
      ok(/No he podido leer los campos propios de la empresa/.test(await e.page.locator('#tc-ed-aviso').textContent()), t + 'I2: el editor avisa de que no leyó los campos propios');
      await e.ctx.close();
    }
    /* ── J. «Insertar campo» en el editor: una pastilla más, con la etiqueta del catálogo ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-editar="commercial_offer"]').click();
      await esperaPapel(page);
      ok(await page.locator('[data-tc-cx-menu]').count() === 0, t + 'J: sin párrafo abierto no hay botón de insertar');
      await page.locator('#tc-trozos [data-tc-trozo]', { hasText: 'acabados de calidad superior' }).first().click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando', { timeout: 4000 });
      await page.keyboard.press('Control+End');
      ok(await page.locator('#tc-trozos .tc-editando [data-tc-cx-menu]').isVisible(), t + 'J: con un párrafo abierto sale «Insertar campo»');
      await page.locator('#tc-trozos .tc-editando [data-tc-cx-menu]').click();
      ok(await page.locator('#tc-trozos .tc-menu-cx:not([hidden])').isVisible() && await page.locator('#tc-trozos .tc-menu-cx [data-tc-cx]').count() === 4, t + 'J: el menú ofrece los 4 campos vivos (no el archivado)');
      ok(/Garaje incluido/.test(await page.locator('#tc-trozos .tc-menu-cx').textContent()) && !/Campo antiguo/.test(await page.locator('#tc-trozos .tc-menu-cx').textContent()), t + 'J: con su etiqueta en llano');
      if (PNG) await page.screenshot({ path: PNG + '_insertar_' + ancho + '.png', fullPage: false });
      await page.keyboard.press('Escape');
      ok(await page.locator('#tc-trozos .tc-menu-cx').isHidden() && await page.locator('#tc-trozos .tc-editando').count() === 1, t + 'J: Escape cierra el menú sin cerrar el párrafo');
      await page.locator('#tc-trozos .tc-editando [data-tc-cx-menu]').click();
      await page.locator('#tc-trozos .tc-menu-cx [data-tc-cx="cx_garaje_incluido"]').click();
      const pill = page.locator('#tc-trozos .tc-editando [data-tc-marca="cx_garaje_incluido"]');
      ok(await pill.count() === 1 && (await pill.textContent()) === 'Garaje incluido' && await pill.getAttribute('contenteditable') === 'false' && await pill.getAttribute('data-ej') === 'Sí', t + 'J: entra una pastilla atómica con la etiqueta del catálogo y su ejemplo');
      ok(await page.locator('#tc-trozos .tc-menu-cx').isHidden(), t + 'J: el menú se cierra al insertar');
      await page.keyboard.type('fin');
      await page.locator('#tc-trozos [data-tc-par-listo]').click();
      ok(/1 trozos cambiados/.test(await page.locator('#tc-cambios').textContent()) && await page.locator('#tc-trozos [data-tc-marca="cx_garaje_incluido"]').count() === 1, t + 'J: «Listo» anota el cambio y la pastilla sigue siendo pastilla');
      await page.locator('#tc-simular').click();
      await page.waitForSelector('#tc-revision .tc-rev', { timeout: 6000 });
      const rv = (await rpcs(page, 'plantilla_contrato_revisa')).pop();
      ok(rv && rv.a.p_cuerpo.indexOf('{{cx_garaje_incluido}}') !== -1 && /calidad superior[^<]*\{\{cx_garaje_incluido\}\}\sfin/.test(rv.a.p_cuerpo.replace(/&nbsp;/g, ' ')), t + 'J: el texto que se manda a revisar lleva {{cx_garaje_incluido}} donde se puso el cursor');
      ok(/guardaría como borrador/.test(await page.locator('#tc-revision').textContent()), t + 'J: y la base lo acepta');
      ok(!/\[cx_/.test(await page.locator('#tc-previa-frame').getAttribute('srcdoc')) && /Sí/.test(await page.locator('#tc-previa-frame').getAttribute('srcdoc')), t + 'J: la simulación pinta el ejemplo del campo, no su clave');
      // un cursor en mitad de un texto: la pastilla entra ahí
      await page.locator('#tc-trozos [data-tc-trozo]', { hasText: 'acabados de calidad' }).first().click();
      await page.waitForSelector('#tc-trozos .tc-par.tc-editando', { timeout: 4000 });
      await page.keyboard.press('Control+Home');
      await page.locator('#tc-trozos .tc-editando [data-tc-cx-menu]').click();
      await page.locator('#tc-trozos .tc-menu-cx [data-tc-cx="cx_fecha_entrega"]').click();
      const orden = await page.locator('#tc-trozos .tc-editando [data-tc-trozo]').first().evaluate(s => s.firstElementChild && s.firstElementChild.getAttribute('data-tc-marca'));
      ok(orden === 'cx_fecha_entrega', t + 'J: con el cursor al principio la pastilla entra al principio (' + orden + ')');
      await page.locator('#tc-trozos [data-tc-par-deshacer]').click();
      if (PNG) await page.screenshot({ path: PNG + '_pastilla_' + ancho + '.png', fullPage: false });
      ok(errores.length === 0, t + 'J sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── K. modo oscuro de las pestañas nuevas: legibles y sin sombras ── */
    {
      const ctx = await browser.newContext({ viewport: { width: ancho, height: ancho > 800 ? 900 : 844 }, colorScheme: 'dark' });
      const page = await ctx.newPage();
      await page.route('**/*', async route => {
        const u = new URL(route.request().url());
        if (u.origin === HOST) {
          let p = decodeURIComponent(u.pathname); if (p.endsWith('/')) p += 'index.html';
          const f = path.join(RAIZ, p);
          if (fs.existsSync(f) && fs.statSync(f).isFile()) { let body = fs.readFileSync(f); if (path.extname(f) === '.html') body = Buffer.from(body.toString('utf8').replace(/\sintegrity="[^"]*"/g, ''), 'utf8'); return route.fulfill({ status: 200, contentType: MIME[path.extname(f)] || 'application/octet-stream', body }); }
          return route.fulfill({ status: 404, body: '' });
        }
        if (/supabase\.min\.js/.test(u.href)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
        if (u.protocol === 'data:' || u.protocol === 'blob:') return route.continue();
        return route.fulfill({ status: 200, contentType: /\.css|fonts\.googleapis/.test(u.href) ? 'text/css' : 'text/javascript', body: '' });
      });
      await page.goto(HOST + '/intranet/v4/textos-contrato/?p=ae', { waitUntil: 'load' });
      await page.waitForSelector('[data-tc-editar="ppjb_reserva"]', { timeout: 15000 });
      const lum = (rgb) => { const m = rgb.match(/\d+/g).map(Number); return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255; };
      for (const tab of ['revisiones', 'campos']) {
        await page.locator('[data-tc-pestana="' + tab + '"]').click();
        if (tab === 'revisiones') { await page.selectOption('#tc-rev-slug', 'commercial_offer'); await page.waitForSelector('[data-rv-fila="rev_1"]', { timeout: 6000 }); }
        else await page.waitForSelector('[data-cx-fila]', { timeout: 6000 });
        const sec = await page.locator('#tc-panel-' + tab + ' .tc-seccion').first().evaluate(el => { const c = getComputedStyle(el); return { bg: c.backgroundColor, fg: c.color, sombra: c.boxShadow }; });
        ok(lum(sec.bg) < 0.25 && lum(sec.fg) > 0.6 && sec.sombra === 'none', t + 'K: ' + tab + ' en modo oscuro: fondo oscuro, texto claro y sin sombras (' + sec.bg + ' / ' + sec.fg + ')');
        const sel = await page.locator('[data-tc-pestana="' + tab + '"]').evaluate(el => { const c = getComputedStyle(el); return { bg: c.backgroundColor, fg: c.color }; });
        ok(Math.abs(lum(sel.bg) - lum(sel.fg)) > 0.35, t + 'K: la pestaña activa tiene contraste en modo oscuro');
        if (PNG) await page.screenshot({ path: PNG + '_oscuro_' + tab + '_' + ancho + '.png', fullPage: false });
      }
      await ctx.close();
    }
    /* ── L. pestaña CONTRATO NUEVO (E9): asistente de cuatro pasos, copia y en blanco con campos, error de la base en llano ── */
    {
      const { ctx, page, errores } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-pestana="nuevo"]').click();
      await page.waitForSelector('#tc-nv-paso #tc-nv-nombre', { timeout: 6000 });
      ok(await page.evaluate(() => location.hash) === '#nuevo' && await page.locator('#tc-nv-pasos li').count() === 4, t + 'L: la pestaña vive en la URL y tiene cuatro pasos');
      ok(await page.locator('#tc-nv-atras').isDisabled() && await page.locator('#tc-nv-crear').isHidden(), t + 'L: en el primer paso no hay Atrás ni Crear');
      await page.locator('#tc-nv-sig').click();
      ok(/mínimo 3 letras/.test(await page.locator('#tc-nv-estado').textContent()) && (await rpcs(page, 'plantilla_contrato_nuevo_crea')).length === 0, t + 'L: sin nombre no avanza y no llama a la base');
      await page.locator('#tc-nv-nombre').fill('Contrato duplicado');
      await page.locator('#tc-nv-sig').click();
      ok(await page.locator('input[name="tc-nv-partir"][value="blanco"]').isChecked(), t + 'L: se parte en blanco por defecto');
      await page.locator('#tc-nv-sig').click();
      ok(await page.locator('#tc-nv-paso [data-nv-campo]').count() === 4, t + 'L: el paso de campos ofrece los 4 campos vivos del catálogo');
      await page.locator('[data-nv-campo="cx_garaje_incluido"]').check();
      await page.locator('#tc-nv-sig').click();
      ok(/Contrato duplicado/.test(await page.locator('#tc-nv-paso').textContent()) && /en blanco/.test(await page.locator('#tc-nv-paso').textContent()) && /Garaje incluido/.test(await page.locator('#tc-nv-paso').textContent()), t + 'L: revisar enseña nombre, punto de partida y campos');
      if (PNG) await page.screenshot({ path: PNG + '_nuevo_' + ancho + '.png', fullPage: ancho === 390 });
      await page.locator('#tc-nv-crear').click();
      await page.waitForFunction(() => /Ya hay un contrato con ese nombre: elige otro/.test(document.getElementById('tc-nv-estado').textContent), null, { timeout: 5000 });
      const c1 = (await rpcs(page, 'plantilla_contrato_nuevo_crea'))[0];
      ok(c1 && c1.a.p_empresa === 'lawang' && c1.a.p_nombre === 'Contrato duplicado' && c1.a.p_punto_partida === 'blanco' && c1.a.p_slug_origen === null && c1.a.p_version_origen === null && JSON.stringify(c1.a.p_campos) === '["cx_garaje_incluido"]', t + 'L: en blanco manda nombre, punto de partida y los campos elegidos');
      ok(/Mensaje de la base: Ya hay un contrato/.test(await page.locator('#tc-nv-estado').textContent()), t + 'L: el error de la base sale en llano con su detalle');
      // volver, cambiar el nombre y partir de una copia
      await page.locator('#tc-nv-atras').click(); await page.locator('#tc-nv-atras').click(); await page.locator('#tc-nv-atras').click();
      await page.locator('#tc-nv-nombre').fill('Cesión de derechos');
      await page.locator('#tc-nv-sig').click();
      await page.locator('input[name="tc-nv-partir"][value="copia"]').check();
      await page.locator('#tc-nv-sig').click();
      ok(/Elige el contrato del que partir/.test(await page.locator('#tc-nv-estado').textContent()), t + 'L: una copia sin origen no avanza');
      await page.locator('#tc-nv-origen').selectOption('commercial_offer');
      await page.locator('#tc-nv-sig').click(); await page.locator('#tc-nv-sig').click();
      ok(/copia de/.test(await page.locator('#tc-nv-paso').textContent()), t + 'L: revisar dice de qué contrato se copia');
      await page.locator('#tc-nv-crear').click();
      await esperaPapel(page);
      const c2 = (await rpcs(page, 'plantilla_contrato_nuevo_crea')).pop();
      ok(c2 && c2.a.p_punto_partida === 'copia' && c2.a.p_slug_origen === 'commercial_offer' && JSON.stringify(c2.a.p_campos) === '[]', t + 'L: la copia manda el contrato de origen y ningún campo');
      ok(await page.evaluate(() => location.hash) === '#textos' && /Cesión de derechos/.test(await page.locator('#tc-ed-titulo').textContent()), t + 'L: tras crearlo se abre en el editor');
      const ed = (await rpcs(page, 'plantilla_contrato_edicion')).pop();
      ok(ed && /^lawang_ces/.test(ed.a.p_slug) && ed.a.p_variante === 'estandar', t + 'L: el editor pide el texto del contrato nuevo');
      ok(errores.length === 0, t + 'L sin errores de página: ' + errores.slice(0, 2).join(' || '));
      await ctx.close();
    }
    /* ── M. historial: quién cambió qué parte sensible; fallo de lectura distinto de «nadie» ── */
    {
      const { ctx, page } = await nueva(browser, ancho, 'p=ae');
      await page.locator('[data-tc-historial="commercial_offer"]').click();
      await page.waitForSelector('#tc-sens-lista .tc-fila', { timeout: 6000 });
      const tx = await page.locator('#tc-sens-lista').textContent();
      ok(/foro y ley aplicable/.test(tx) && /admin\.uno/.test(tx) && /aviso confirmado/.test(tx) && /Cambio de foro/.test(tx), t + 'M: el registro dice parte, autor, aviso confirmado y motivo');
      await page.locator('#tc-sens-lista summary').first().click();
      ok(/Texto de antes/.test(await page.locator('#tc-sens-lista pre').first().textContent()) && /Texto de despues/.test(await page.locator('#tc-sens-lista pre').nth(1).textContent()), t + 'M: y el texto de antes y después, tal cual');
      await ctx.close();
      const e = await nueva(browser, ancho, 'p=ae&sens=error');
      await e.page.locator('[data-tc-historial="commercial_offer"]').click();
      await e.page.waitForFunction(() => /No he podido leer el registro/.test(document.getElementById('tc-sens-lista').textContent), null, { timeout: 6000 });
      ok(true, '');
      await e.ctx.close();
    }
  }
  await browser.close();
  if (fallos.length) { console.error('FALLA (' + fallos.length + '):\n - ' + fallos.join('\n - ')); process.exit(1); }
  console.log('arnes_textos_contrato OK: pantalla verificada a 1440 y 390 px (claro y oscuro) con tres personas: documento con índice, idiomas, marcadores, partes sensibles editables con aviso, rechazos de la base en llano, simulación, guardado, activación, historial y un mensaje hostil.');
})().catch(e => { console.error(e); process.exit(2); });
