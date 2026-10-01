/* Ajustes → Empresa y marca → Sociedades emisoras (Ajustes del ERP, subtarea S3, 30-sep-2026).
 * Encargo: encargos/20260930_erp_ajustes_pantalla.md. Migración: 20260930200000_ajustes_sociedades_identidad.sql.
 *
 * Qué hace esta pieza (y solo esto): lista de sociedades con un selector, alta, edición, desactivar y logo, con una vista previa
 * hecha por el MISMO motor que imprime las facturas (`documentoHTML` de intranet/facturas/documento.js), no una maqueta.
 *
 * Lo que decide la BASE, no esta pantalla (contexto/patrones_tecnicos.md → «Frontera frontend / backend»):
 *  · quién puede escribir (`_super_o_para()` dentro de `sociedad_guarda`, 42501);
 *  · si la identidad fiscal de una sociedad se puede cambiar (trigger `trg_sociedades_identidad`): con documentos emitidos a su
 *    nombre se rechaza. Aquí solo se PINTA en solo lectura lo que la base va a rechazar, con el motivo, y se enseña el error
 *    que la base devuelva si aun así llega;
 *  · qué es un logo válido (la edge `ficheros`, clase `sociedad_logo`, mira los bytes) y qué URL puede guardarse (la RPC).
 * Lo único que esta pantalla sabe es lo que la base le CUENTA (`sociedades_ajustes_datos`): nada de contar facturas desde aquí.
 *
 * Fuera de esta ronda, a propósito: la cuenta bancaria de la sociedad. `cuentas_bancarias` no está ligada a `sociedades` (se
 * enlazan por plantilla o proyecto), así que no hay «banco de la sociedad» que editar; ver la bitácora del encargo.
 *
 * Se engancha por data-accion / data-soc-*, nunca por un rótulo.
 */
(function () {
  'use strict';

  var sb = null, estado = { lista: [], puede: false, sel: null, nueva: false, cargado: false };
  var logoNuevo = null;          // URL pública devuelta por la edge, aún sin guardar en la sociedad
  var modulos = null;            // promesa de la carga de los módulos del documento

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function T(x) { return (typeof lwT === 'function') ? lwT(x) : x; }
  function aviso(t) { if (typeof toast === 'function') toast(t); }
  function $(sel, raiz) { return (raiz || document).querySelector(sel); }
  function raiz() { return document.getElementById('lw-aj-sociedades'); }

  // Errores de la edge de ficheros para el logo, en llano. La pantalla decide por el código, nunca por el texto.
  var ERR_LOGO = {
    solo_super_admin: 'Solo el super admin puede cambiar el logo.',
    sociedad_invalida: 'La clave de la sociedad no es válida: recarga la pantalla.',
    sociedad_inexistente: 'Esa sociedad todavía no existe: guárdala antes de subirle el logo.',
    logo_invalido: 'No se ha podido leer el fichero.',
    logo_vacio: 'El fichero está vacío.',
    logo_demasiado_grande: 'El logo pesa más de 512 KB: reduce su tamaño.',
    logo_tipo_no_admitido: 'Solo se admiten imágenes PNG, JPEG o WebP (nunca SVG).',
    logo_ilegible: 'La imagen está dañada o incompleta.',
    logo_demasiado_pequeno: 'El logo es demasiado pequeño (mínimo 16 px por lado).',
    logo_dimensiones_excesivas: 'El logo es demasiado grande (máximo 2000 px por lado).',
    no_se_pudo_subir: 'El servidor no ha podido guardar la imagen: prueba otra vez.',
    accion_desconocida: 'La subida de logos todavía no está activada en el servidor.',
    clase_desconocida: 'La subida de logos todavía no está activada en el servidor.'
  };

  /* ── Utilidades ───────────────────────────────────────────────────────────────────────────────────────────── */
  var RE_HEX = /^#[0-9A-Fa-f]{6}$/;
  // Clave propuesta desde la razón social: sin acentos, sin «PT»/«Ltd», minúsculas y guion bajo. El usuario puede retocarla
  // hasta que guarda; después no se cambia nunca (trigger de la tabla).
  function proponClave(razon) {
    var t = String(razon || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
    t = t.replace(/\b(pt|cv|ltd|llc|sl|sa|sas|inc|co)\b/g, ' ').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    if (t && !/^[a-z]/.test(t)) t = 's_' + t;
    return t.slice(0, 40);
  }
  function claveError(c) {
    if (!/^[a-z][a-z0-9_]{2,39}$/.test(c)) return T('La clave va en minúsculas, números y guion bajo, empieza por letra y tiene entre 3 y 40 caracteres.');
    if (estado.lista.some(function (s) { return s.clave === c; })) return T('Ya existe una sociedad con esa clave.');
    return '';
  }
  function actual() {
    if (estado.nueva) return null;
    return estado.lista.filter(function (s) { return s.clave === estado.sel; })[0] || null;
  }
  function textoDocs(detalle, soloAbiertos) {
    var partes = [];
    Object.keys(detalle || {}).sort().forEach(function (k) {
      var n = Number((detalle[k] || {})[soloAbiertos ? 'abiertos' : 'total']) || 0;
      if (n > 0) partes.push(n + ' ' + k.replace(/_/g, ' '));
    });
    return partes.join(', ');
  }

  /* ── Módulos del documento (los mismos que la pantalla de facturas), bajo demanda ──────────────────────────── */
  var MODS = [
    { src: '/contracts/assets/dinero.js', listo: function () { return typeof lwFormatoImporte === 'function'; } },
    { src: '/contracts/assets/entities.js', listo: function () { return typeof SOCIEDADES !== 'undefined'; } },
    { src: '/intranet/facturas/totales.js', listo: function () { return typeof calcTotales === 'function'; } },
    { src: '/intranet/facturas/documento.js', listo: function () { return typeof documentoHTML === 'function'; } }
  ];
  function cargaModulos() {
    if (modulos) return modulos;
    modulos = MODS.reduce(function (p, m) {
      return p.then(function () {
        if (m.listo()) return;
        return new Promise(function (res, rej) {
          var s = document.createElement('script');
          s.src = m.src;
          s.onload = function () { res(); };
          s.onerror = function () { rej(new Error(m.src)); };
          document.head.appendChild(s);
        });
      });
    }, Promise.resolve()).catch(function (e) { modulos = null; throw e; });
    return modulos;
  }

  /* ── Lo que hay en el formulario ahora mismo ─────────────────────────────────────────────────────────────── */
  function campo(nombre) { var el = $('[data-soc-campo="' + nombre + '"]', raiz()); return el; }
  function val(nombre) { var el = campo(nombre); return el ? (el.type === 'checkbox' ? el.checked : el.value) : undefined; }
  function borrador() {
    var s = actual() || {};
    var tp = String(val('tinta_primary') || '').trim(), td = String(val('tinta_deep') || '').trim();
    return {
      clave: estado.nueva ? String(val('clave') || '').trim() : s.clave,
      label: String(val('label') || '').trim(), razon: String(val('razon') || '').trim(), marca: String(val('marca') || '').trim(),
      npwp_label: String(val('npwp_label') || '').trim(), npwp: String(val('npwp') || '').trim(), nib: String(val('nib') || '').trim(),
      rep: String(val('rep') || '').trim(), domicilio: String(val('domicilio') || '').trim(), es_indonesia: !!val('es_indonesia'),
      logo: logoNuevo !== null ? logoNuevo : (s.logo || ''), logo_alto: String(val('logo_alto') || '').trim(),
      folio: String(val('folio') || '').trim(), tinta_primary: tp, tinta_deep: td, emisor_debajo: !!val('emisor_debajo'),
      orden: String(val('orden') || '').trim(), activa: estado.nueva ? true : !!val('activa')
    };
  }

  /* ── Vista previa: documentoHTML con una factura de ejemplo y la sociedad TAL COMO está en el formulario ──── */
  function pintaVista() {
    var caja = document.getElementById('lw-soc-vista');
    if (!caja) return;
    cargaModulos().then(function () {
      var b = borrador();
      var hoy = new Date().toISOString().slice(0, 10);
      var tinta = (b.tinta_primary || b.tinta_deep) ? { primary: RE_HEX.test(b.tinta_primary) ? b.tinta_primary : '', deep: RE_HEX.test(b.tinta_deep) ? b.tinta_deep : '' } : null;
      var ficha = {
        label: b.label, razon: b.razon || '—', marca: b.marca, domicilio: b.domicilio || '—', npwp: b.npwp || '—', rep: b.rep,
        logo: b.logo || '', logoAlto: /^[0-9]{1,3}(\.[0-9]{1,2})?mm$/.test(b.logo_alto) ? b.logo_alto : '',
        folio: RE_HEX.test(b.folio) ? b.folio : '', tinta: tinta || undefined
      };
      if (b.npwp_label && b.npwp_label !== 'NPWP') ficha.npwpLabel = b.npwp_label;
      if (b.emisor_debajo) ficha.emisorDebajo = true;
      var d = {
        sociedad: '__vista_previa__', tipo: 'factura', moneda: 'IDR', fecha_emision: hoy, cliente_nombre: T('Cliente de ejemplo'),
        proyecto_nombre: T('Proyecto de ejemplo'), contrato_numero: '',
        lineas: [{ descripcion: T('Concepto de ejemplo'), importe: '12500000' }, { descripcion: T('Otro concepto de ejemplo'), importe: '4300000' }]
      };
      var html, vars;
      SOCIEDADES.__vista_previa__ = ficha;
      try { html = documentoHTML(d, { numero: 'INV-00000', emisor: ficha }); vars = documentoVars(ficha); }
      finally { delete SOCIEDADES.__vista_previa__; }
      var hoja = Object.keys(vars.hoja).filter(function (k) { return vars.hoja[k]; }).map(function (k) { return k + ':' + vars.hoja[k]; }).join(';');
      var doc = Object.keys(vars.doc).filter(function (k) { return vars.doc[k]; }).map(function (k) { return k + ':' + vars.doc[k]; }).join(';');
      caja.innerHTML = '<div style="zoom:.48;width:210mm;box-sizing:border-box;padding:15mm 16mm;background:var(--folio,#fff);' + esc(hoja) + '">' +
        '<div class="doc" style="' + esc(doc) + '">' + html + '</div></div>';
    }).catch(function (e) {
      caja.innerHTML = '<p class="font-body-sm text-body-sm text-error" role="alert">' + esc(T('No se ha podido cargar la vista previa')) + ': ' + esc((e && e.message) || '') + '</p>';
    });
  }

  /* ── Pintado ──────────────────────────────────────────────────────────────────────────────────────────────── */
  function filaTxt(nombre, etiqueta, valor, o) {
    o = o || {};
    var id = 'lw-soc-' + nombre;
    var bloq = o.bloqueado || !estado.puede;
    return '<div class="flex flex-col gap-1' + (o.ancho ? ' lw-soc-span2' : '') + '">' +
      '<label for="' + id + '" class="font-label-md text-label-md text-on-surface">' + esc(T(etiqueta)) + (o.req ? ' *' : '') + '</label>' +
      (o.area
        ? '<textarea id="' + id + '" rows="3" maxlength="' + (o.max || 500) + '" data-soc-campo="' + nombre + '"' + (bloq ? ' disabled' : '') + ' class="rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md"></textarea>'
        : '<input id="' + id + '" type="text" maxlength="' + (o.max || 200) + '" autocomplete="off" spellcheck="false" data-soc-campo="' + nombre + '"' +
            (o.ph ? ' placeholder="' + esc(o.ph) + '"' : '') + (bloq ? ' disabled' : '') +
            ' class="rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md">') +
      (o.ayuda ? '<span class="font-body-sm text-body-sm text-outline">' + esc(T(o.ayuda)) + '</span>' : '') +
      '</div>';
  }
  function filaColor(nombre, etiqueta, ph) {
    var id = 'lw-soc-' + nombre, bloq = !estado.puede;
    return '<div class="flex flex-col gap-1"><label for="' + id + '" class="font-label-md text-label-md text-on-surface">' + esc(T(etiqueta)) + '</label>' +
      '<div class="flex items-center gap-2">' +
        '<input type="color" data-soc-color="' + nombre + '" aria-label="' + esc(T(etiqueta)) + '"' + (bloq ? ' disabled' : '') + ' class="h-10 w-12 rounded border border-control-border/50 bg-surface-container-lowest p-1">' +
        '<input id="' + id + '" type="text" maxlength="7" autocomplete="off" spellcheck="false" data-soc-campo="' + nombre + '" placeholder="' + esc(ph) + '"' + (bloq ? ' disabled' : '') +
          ' style="width:8rem" class="rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md">' +
      '</div></div>';
  }
  function filaCheck(nombre, etiqueta, ayuda, bloqueado) {
    var id = 'lw-soc-' + nombre, bloq = bloqueado || !estado.puede;
    return '<div class="flex flex-col gap-1 lw-soc-span2"><label class="flex items-start gap-3 font-body-md text-body-md text-on-surface">' +
      '<input id="' + id + '" type="checkbox" data-soc-campo="' + nombre + '"' + (bloq ? ' disabled' : '') + ' class="mt-1 h-4 w-4"><span>' + esc(T(etiqueta)) + '</span></label>' +
      (ayuda ? '<span class="font-body-sm text-body-sm text-outline pl-7">' + esc(ayuda) + '</span>' : '') + '</div>';
  }

  function pinta() {
    var cont = raiz();
    if (!cont) return;
    if (!estado.cargado) return;
    var s = actual();
    var nueva = estado.nueva;
    var docs = (s && s.documentos) || { total: 0, abiertos: 0, detalle: {} };
    var bloqueada = !nueva && Number(docs.total) > 0;
    var noDesactivable = !nueva && s && s.activa !== false && Number(docs.abiertos) > 0;
    logoNuevo = null;

    var chips = estado.lista.map(function (x) {
      var on = !nueva && x.clave === estado.sel;
      return '<button type="button" data-accion="soc-elegir" data-soc-clave="' + esc(x.clave) + '" aria-pressed="' + on + '" class="px-4 py-2 rounded-full font-label-md text-[13px] transition-colors ' +
        (on ? 'bg-primary-container text-on-primary' : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high') + '">' +
        esc(x.razon || x.clave) + (x.activa === false ? ' <span class="opacity-70">(' + esc(T('inactiva')) + ')</span>' : '') + '</button>';
    }).join('') + (estado.puede
      ? '<button type="button" data-accion="soc-nueva" aria-pressed="' + nueva + '" class="px-4 py-2 rounded-full font-label-md text-[13px] border lw-soc-punteado ' +
        (nueva ? 'bg-primary-container text-on-primary' : 'text-on-surface-variant hover:bg-surface-container') + '">+ ' + esc(T('Nueva sociedad')) + '</button>' : '');

    var banner = '';
    if (bloqueada) {
      banner = '<div class="rounded-xl border border-burnt-earth/30 bg-surface-alt px-5 py-4 flex items-start gap-3" role="status" data-soc-bloqueada>' +
        '<span class="material-symbols-outlined text-[20px] text-burnt-earth shrink-0">lock</span>' +
        '<p class="font-body-sm text-body-sm text-on-surface-variant">' + esc(T('Esta sociedad ya tiene documentos emitidos a su nombre')) + ' (' + esc(textoDocs(docs.detalle, false)) + '). ' +
        esc(T('Su identidad fiscal —razón social, identificación fiscal, NIB, domicilio, representante y marca— no se puede cambiar desde aquí: reescribiría lo ya firmado y emitido. Para cambiarla, pídeselo al estudio.')) + '</p></div>';
    }

    var fiscalTitulo = (s && s.npwp_label) || 'NPWP';
    cont.innerHTML =
      '<div class="px-8 pt-8 pb-4 flex flex-col gap-1 border-b border-outline-variant/40 border-t">' +
        '<span class="font-label-md text-[11px] tracking-[0.16em] uppercase text-outline font-bold">' + esc(T('Sociedades emisoras')) + '</span>' +
        '<h2 class="font-headline-sm text-headline-sm text-deep-lagoon tracking-tight">' + esc(T('Cada sociedad, con su identidad y el diseño de su factura')) + '</h2>' +
        '<p class="font-body-sm text-body-sm text-outline">' + esc(T('Contratos y facturas se emiten a nombre de una sociedad. El documento sale con la identidad, el logo y la tinta de quien emite. Las series de numeración de las facturas son compartidas por todas las sociedades.')) + '</p>' +
      '</div>' +
      '<div class="px-8 py-5 flex flex-wrap gap-2" role="group" aria-label="' + esc(T('Sociedad')) + '">' + chips + '</div>' +
      (banner ? '<div class="px-8 pb-4">' + banner + '</div>' : '') +
      (!estado.puede ? '<p class="px-8 pb-4 font-body-sm text-body-sm text-outline">' + esc(T('Solo lectura: cambiar las sociedades exige super admin.')) + '</p>' : '') +
      '<div class="px-8 pb-6 grid grid-cols-1 xl:grid-cols-2 gap-8 lw-soc-form" data-soc-form>' +
        '<div class="flex flex-col gap-5">' +
          (nueva
            ? '<div class="rounded-xl bg-surface-container-low px-4 py-3 font-body-sm text-body-sm text-on-surface-variant">' + esc(T('Nueva sociedad. Se da de alta activa. La clave interna se fija ahora y no se puede cambiar nunca: va dentro de cada contrato y factura que emita.')) + '</div>' +
              '<div class="grid grid-cols-1 md:grid-cols-2 gap-4">' + filaTxt('clave', 'Clave interna', '', { req: 1, max: 40, ph: 'mi_empresa_sa', ayuda: 'Se propone desde la razón social. Minúsculas, números y guion bajo.' }) + '<div></div></div>'
            : '<div class="font-body-sm text-body-sm text-outline">' + esc(T('Clave interna')) + ': <code>' + esc(s ? s.clave : '') + '</code> — ' + esc(T('no se cambia nunca.')) + '</div>') +
          '<div class="grid grid-cols-1 md:grid-cols-2 gap-4">' +
            filaTxt('razon', 'Razón social inscrita', '', { req: 1, bloqueado: bloqueada, ayuda: 'Es lo que se imprime en contratos y facturas.', ancho: 1 }) +
            filaTxt('marca', 'Marca comercial', '', { bloqueado: bloqueada, ayuda: 'Opcional. Sale bajo la razón social.' }) +
            filaTxt('label', 'Nombre en los desplegables', '', { ayuda: 'Cómo se elige esta sociedad al redactar un contrato o una factura.' }) +
            filaTxt('npwp_label', 'Tipo de identificador fiscal', '', { bloqueado: bloqueada, max: 20, ph: 'NPWP', ayuda: 'NPWP en Indonesia, CRN en Hong Kong, NIF en España…' }) +
            filaTxt('npwp', 'Identificador fiscal (' + fiscalTitulo + ')', '', { bloqueado: bloqueada, max: 60 }) +
            filaTxt('nib', 'NIB', '', { bloqueado: bloqueada, max: 40, ayuda: 'Opcional.' }) +
            filaTxt('rep', 'Representante', '', { bloqueado: bloqueada, ayuda: 'Solo el nombre.' }) +
            filaTxt('domicilio', 'Domicilio', '', { req: 1, area: 1, bloqueado: bloqueada, ancho: 1 }) +
            filaCheck('es_indonesia', 'Es una sociedad indonesia (las plantillas de contrato lo declaran así)', '', bloqueada) +
          '</div>' +
          '<div id="lw-soc-aviso-indo" class="font-body-sm text-body-sm text-burnt-earth" hidden>' + esc(T('Las nueve plantillas de contrato declaran al Promotor «sociedad de nacionalidad Indonesia». Para una sociedad que no lo es, esa cláusula hay que corregirla a mano antes de imprimir el contrato final.')) + '</div>' +
          '<div class="border-t border-outline-variant/40 pt-4 font-label-md text-label-md text-on-surface">' + esc(T('Aspecto del documento')) + ' <span class="text-outline font-body-sm text-body-sm">— ' + esc(T('esto no cambia lo que el documento dice')) + '</span></div>' +
          '<div class="grid grid-cols-1 md:grid-cols-2 gap-4">' +
            '<div class="flex flex-col gap-2 lw-soc-span2"><span class="font-label-md text-label-md text-on-surface">' + esc(T('Logo')) + '</span>' +
              '<div class="flex flex-wrap items-center gap-3">' +
                '<img id="lw-soc-logo-img" alt="" class="h-12 bg-surface-container-low rounded" style="max-width:10rem;object-fit:contain" hidden>' +
                '<span id="lw-soc-logo-sin" class="font-body-sm text-body-sm text-outline" hidden>' + esc(T('Sin logo')) + '</span>' +
                (estado.puede && !nueva
                  ? '<label class="px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md cursor-pointer">' + esc(T('Subir logo')) +
                      '<input type="file" accept="image/png,image/jpeg,image/webp" data-soc-logo-fichero class="sr-only"></label>' +
                    '<button type="button" data-accion="soc-logo-quitar" class="px-4 py-2 rounded-full border border-control-border/50 text-on-surface-variant hover:bg-surface-container font-label-md text-label-md">' + esc(T('Quitar logo')) + '</button>'
                  : '') +
              '</div>' +
              '<span class="font-body-sm text-body-sm text-outline" id="lw-soc-logo-estado" role="status" aria-live="polite">' +
                esc(nueva ? T('Guarda la sociedad primero; después podrás subirle el logo.') : T('PNG, JPEG o WebP, hasta 512 KB y 2000 px por lado. Nunca SVG. Se sube al pulsar «Guardar cambios».')) + '</span></div>' +
            filaTxt('logo_alto', 'Alto del logo', '', { max: 8, ph: '24mm', ayuda: 'En milímetros, por ejemplo 24mm.' }) +
            filaColor('folio', 'Color del papel (folio)', '#E7E3D2') + filaColor('tinta_primary', 'Tinta principal', '#662906') + filaColor('tinta_deep', 'Tinta oscura', '#42210B') +
            filaCheck('emisor_debajo', 'Los datos del emisor van DEBAJO del logo (para logos apaisados)') +
            filaTxt('orden', 'Orden en los desplegables', '', { max: 5, ph: '1' }) +
            (nueva ? '' : filaCheck('activa', 'Activa: se ofrece al redactar contratos y facturas',
              noDesactivable ? T('No se puede desactivar ahora: tiene documentos abiertos o en curso') + ' (' + textoDocs(docs.detalle, true) + '). ' + T('Ciérralos o anúlalos antes.') : '',
              noDesactivable)) +
          '</div>' +
          (estado.puede
            ? '<div class="flex flex-col md:flex-row md:items-center gap-3 pt-2">' +
                '<label for="lw-soc-motivo" class="font-label-md text-label-md text-on-surface">' + esc(T('Motivo del cambio')) + ' <span class="text-outline">(' + esc(T('opcional')) + ')</span></label>' +
                '<input id="lw-soc-motivo" type="text" maxlength="500" autocomplete="off" data-soc-motivo placeholder="' + esc(T('Queda en el registro de cambios')) + '" class="w-full md:w-72 rounded-lg border border-control-border/50 bg-surface-container-lowest px-3 py-2.5 font-body-md text-body-md">' +
              '</div>' +
              '<div class="flex flex-wrap items-center gap-3">' +
                '<button type="button" data-accion="soc-guardar" data-real class="px-5 py-2.5 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">' + esc(nueva ? T('Dar de alta') : T('Guardar cambios')) + '</button>' +
                (nueva ? '<button type="button" data-accion="soc-cancelar" class="px-5 py-2.5 rounded-full border border-control-border/50 text-on-surface-variant hover:bg-surface-container font-label-md text-label-md">' + esc(T('Cancelar')) + '</button>' : '') +
                '<span id="lw-soc-estado" class="font-body-sm text-body-sm text-outline" role="status" aria-live="polite"></span>' +
              '</div>' +
              '<p class="font-body-sm text-body-sm text-outline">' + esc(T('Una sociedad no se borra: se desactiva. Sus documentos emitidos siguen apuntando a ella. La cuenta bancaria de cada sociedad se gestionará en su propia acción, con contraseña otra vez, en una fase posterior.')) + '</p>'
            : '') +
        '</div>' +
        '<div class="flex flex-col gap-2"><span class="font-label-md text-label-md text-on-surface">' + esc(T('Así sale una factura de esta sociedad')) + '</span>' +
          '<div id="lw-soc-vista" class="rounded-xl bg-surface-container-low" style="max-height:78vh;overflow:auto;padding:12px"><p class="font-body-sm text-body-sm text-outline">' + esc(T('Preparando la vista previa…')) + '</p></div></div>' +
      '</div>';

    // valores por .value/.checked (nunca dentro del HTML: lo que llegue de la base no se interpreta como marcado)
    var v = s || { activa: true, orden: Math.max.apply(null, [0].concat(estado.lista.map(function (x) { return Number(x.orden) || 0; }))) + 1, es_indonesia: true, npwp_label: 'NPWP', emisor_debajo: false };
    function pon(n, x) { var el = campo(n); if (!el) return; if (el.type === 'checkbox') el.checked = !!x; else el.value = x == null ? '' : String(x); }
    ['razon', 'marca', 'label', 'npwp_label', 'npwp', 'nib', 'rep', 'domicilio', 'logo_alto', 'folio', 'emisor_debajo', 'orden', 'activa', 'es_indonesia'].forEach(function (n) { pon(n, v[n]); });
    pon('tinta_primary', (v.tinta || {}).primary); pon('tinta_deep', (v.tinta || {}).deep);
    ['folio', 'tinta_primary', 'tinta_deep'].forEach(function (n) { sincronizaColor(n); });
    pintaLogo(v.logo || '');
    avisoIndo();
  }

  function sincronizaColor(n) {
    var t = campo(n), c = $('[data-soc-color="' + n + '"]', raiz());
    if (t && c && RE_HEX.test(t.value)) c.value = t.value.toLowerCase();
  }
  function pintaLogo(url) {
    var img = document.getElementById('lw-soc-logo-img'), sin = document.getElementById('lw-soc-logo-sin');
    if (!img || !sin) return;
    if (url) { img.src = url; img.hidden = false; sin.hidden = true; } else { img.removeAttribute('src'); img.hidden = true; sin.hidden = false; }
  }
  function avisoIndo() {
    var a = document.getElementById('lw-soc-aviso-indo'), c = campo('es_indonesia');
    if (a && c) a.hidden = !!c.checked;
  }
  function estadoTxt(id, texto, mal) {
    var el = document.getElementById(id);
    if (!el) return;
    el.className = 'font-body-sm text-body-sm ' + (mal ? 'text-error' : 'text-on-surface');
    el.textContent = texto;
  }

  /* ── Datos ────────────────────────────────────────────────────────────────────────────────────────────────── */
  function carga(seleccionar) {
    return window.lwDatos('sociedades_ajustes_datos').then(function (r) {
      var cont = raiz();
      if (r.error || !r.data) {
        console.error('[ajustes-sociedades]', r.error);
        var sin = r.error && (r.error.code === '42501' || /42501/.test(String(r.error.message)));
        if (cont) cont.innerHTML = '<div class="px-8 py-6 flex flex-col md:flex-row md:items-center justify-between gap-3 border-t border-outline-variant/40" role="alert">' +
          '<span class="font-body-md text-body-md text-error">' + esc(sin ? T('Las sociedades emisoras son de administración: tu sesión no tiene acceso.') : T('No se han podido leer las sociedades') + ': ' + ((r.error && r.error.message) || T('sin respuesta'))) + '</span>' +
          (sin ? '' : '<button type="button" data-accion="soc-recargar" class="shrink-0 px-4 py-2 rounded-full bg-primary-container text-on-primary hover:bg-primary font-label-md text-label-md">' + esc(T('Reintentar')) + '</button>') + '</div>';
        return;
      }
      estado.lista = r.data.sociedades || [];
      estado.puede = !!r.data.puede_escribir;
      estado.cargado = true;
      estado.nueva = false;
      var quiere = seleccionar || estado.sel;
      estado.sel = estado.lista.some(function (s) { return s.clave === quiere; }) ? quiere : (estado.lista[0] ? estado.lista[0].clave : null);
      pinta();
      pintaVista();
    });
  }

  function errorLegible(e) {
    if (!e) return T('sin detalle');
    if (e.code === '42501') return T('Solo el super admin puede cambiar las sociedades.');
    return e.message || T('sin detalle');
  }

  function guarda(btn) {
    var b = borrador(), s = actual(), nueva = estado.nueva;
    var motivoEl = $('[data-soc-motivo]', raiz());
    var motivo = motivoEl ? motivoEl.value.trim() : '';
    var datos = {};
    var tinta = (b.tinta_primary || b.tinta_deep) ? { primary: b.tinta_primary, deep: b.tinta_deep } : null;
    if (nueva) {
      var ce = claveError(b.clave);
      if (ce) return estadoTxt('lw-soc-estado', ce, true);
      if (!b.razon || !b.domicilio) return estadoTxt('lw-soc-estado', T('La razón social y el domicilio son obligatorios: los imprime cada documento.'), true);
      if (b.es_indonesia && !b.npwp) return estadoTxt('lw-soc-estado', T('Falta el identificador fiscal. Si es una sociedad indonesa, sin él no debería emitir documentos.'), true);
      if (!b.es_indonesia && typeof window.confirm === 'function' &&
          !window.confirm(T('Para una sociedad que no es indonesa, confirma que el contrato de cesión y el DPA con ella ya están firmados.'))) return;
      datos = { label: b.label, razon: b.razon, marca: b.marca, npwp_label: b.npwp_label || 'NPWP', npwp: b.npwp, nib: b.nib, rep: b.rep, domicilio: b.domicilio,
                es_indonesia: b.es_indonesia, logo_alto: b.logo_alto, folio: b.folio, tinta: tinta, emisor_debajo: b.emisor_debajo, orden: b.orden === '' ? 0 : b.orden };
    } else {
      // solo viaja lo que CAMBIA: el registro dice exactamente qué se tocó, y la identidad bloqueada ni se envía
      var docs = (s.documentos || {}), bloq = Number(docs.total) > 0;
      var ident = ['razon', 'marca', 'npwp_label', 'npwp', 'nib', 'rep', 'domicilio', 'es_indonesia'];
      var otros = ['label', 'logo_alto', 'folio', 'emisor_debajo', 'orden', 'activa'];
      var norm = function (x) { return x == null ? '' : String(x).trim(); };
      ident.concat(otros).forEach(function (k) {
        if (bloq && ident.indexOf(k) >= 0) return;
        if (norm(b[k]) !== norm(s[k]) && !(typeof b[k] === 'boolean' && b[k] === !!s[k])) datos[k] = b[k];
      });
      if ('orden' in datos && datos.orden === '') delete datos.orden;
      var tp0 = (s.tinta || {}).primary || '', td0 = (s.tinta || {}).deep || '';
      if (b.tinta_primary !== tp0 || b.tinta_deep !== td0) datos.tinta = tinta;
      if (b.logo !== (s.logo || '')) datos.logo = b.logo || null;
      if (!Object.keys(datos).length) return estadoTxt('lw-soc-estado', T('Sin cambios: no hay nada distinto que guardar.'), false);
    }
    if (motivo) datos.motivo = motivo;
    btn.disabled = true;
    estadoTxt('lw-soc-estado', T('Guardando…'), false);
    Promise.resolve(sb.rpc('sociedad_guarda', { p_clave: nueva ? b.clave : s.clave, p_datos: datos, p_nueva: nueva })).then(function (r) {
      btn.disabled = false;
      if (r.error) {
        var msg = errorLegible(r.error);
        estadoTxt('lw-soc-estado', T('No se guardó') + ': ' + msg, true);
        aviso(T('No se guardó') + ': ' + msg);
        return;
      }
      aviso(nueva ? T('Sociedad dada de alta') : T('Guardado'));
      return carga(nueva ? b.clave : s.clave).then(function () { estadoTxt('lw-soc-estado', T('Guardado. Queda en el registro de cambios.'), false); });
    });
  }

  function subeLogo(fichero) {
    var s = actual();
    if (!s || !fichero) return;
    if (!/^image\/(png|jpeg|webp)$/.test(fichero.type)) return estadoTxt('lw-soc-logo-estado', T(ERR_LOGO.logo_tipo_no_admitido), true);
    if (fichero.size > 512 * 1024) return estadoTxt('lw-soc-logo-estado', T(ERR_LOGO.logo_demasiado_grande), true);
    estadoTxt('lw-soc-logo-estado', T('Subiendo el logo…'), false);
    var lector = new FileReader();
    lector.onerror = function () { estadoTxt('lw-soc-logo-estado', T(ERR_LOGO.logo_invalido), true); };
    lector.onload = function () {
      var b64 = String(lector.result).replace(/^data:[^,]*,/, '');
      window.lwFichero(sb, 'sociedad_logo', 'sube', { clave: s.clave, datos_b64: b64 }).then(function (r) {
        logoNuevo = r.url;
        pintaLogo(r.url);
        estadoTxt('lw-soc-logo-estado', T('Logo subido') + ' (' + r.ancho + '×' + r.alto + ' px). ' + T('Pulsa «Guardar cambios» para usarlo en los documentos.'), false);
        pintaVista();
      }, function (e) {
        var c = e && e.clave;
        estadoTxt('lw-soc-logo-estado', T(ERR_LOGO[c] || (e && e.message) || 'No se pudo subir el logo'), true);
      });
    };
    lector.readAsDataURL(fichero);
  }

  /* ── Arranque ─────────────────────────────────────────────────────────────────────────────────────────────── */
  function arranca() {
    if (!raiz()) return;   // otra página con este script: nada que hacer
    document.addEventListener('click', function (ev) {
      var b = ev.target.closest && ev.target.closest('[data-accion^="soc-"]');
      if (!b || !raiz() || !raiz().contains(b)) return;
      var a = b.getAttribute('data-accion');
      ev.stopPropagation();
      if (a === 'soc-elegir') { estado.sel = b.getAttribute('data-soc-clave'); estado.nueva = false; pinta(); pintaVista(); }
      else if (a === 'soc-nueva') { estado.nueva = true; pinta(); pintaVista(); }
      else if (a === 'soc-cancelar') { estado.nueva = false; pinta(); pintaVista(); }
      else if (a === 'soc-guardar') guarda(b);
      else if (a === 'soc-recargar') carga();
      else if (a === 'soc-logo-quitar') { logoNuevo = ''; pintaLogo(''); estadoTxt('lw-soc-logo-estado', T('Se quitará el logo al pulsar «Guardar cambios».'), false); pintaVista(); }
    }, true);
    document.addEventListener('input', function (ev) {
      var el = ev.target;
      if (!raiz() || !raiz().contains(el)) return;
      var col = el.getAttribute && el.getAttribute('data-soc-color');
      if (col) { var t = campo(col); if (t) t.value = el.value.toUpperCase(); pintaVista(); return; }
      var n = el.getAttribute && el.getAttribute('data-soc-campo');
      if (!n) return;
      if (n === 'razon' && estado.nueva) {
        var c = campo('clave');
        if (c && !c.dataset.tocada) c.value = proponClave(el.value);
        var l = campo('label');
        if (l && !l.dataset.tocada) l.value = el.value;
      }
      if ((n === 'clave' || n === 'label') && el.dataset) el.dataset.tocada = '1';
      if (n === 'folio' || n === 'tinta_primary' || n === 'tinta_deep') sincronizaColor(n);
      if (n === 'es_indonesia') avisoIndo();
      pintaVista();
    });
    document.addEventListener('change', function (ev) {
      var el = ev.target;
      if (el && el.hasAttribute && el.hasAttribute('data-soc-logo-fichero')) { var f = el.files && el.files[0]; el.value = ''; subeLogo(f); }
      else if (el && el.getAttribute && el.getAttribute('data-soc-campo') === 'es_indonesia') { avisoIndo(); pintaVista(); }
      else if (el && el.getAttribute && (el.getAttribute('data-soc-campo') === 'emisor_debajo')) pintaVista();
    });
    if (!window.LW_AUTH) return;
    window.LW_AUTH.then(function (aut) {
      if (!aut || !aut.sb) return;
      sb = aut.sb;
      carga();
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', arranca); else arranca();
})();
