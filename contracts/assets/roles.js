/* roles.js — UN SOLO PUNTO DE VERDAD DE «QUIÉN ES QUIÉN» PARA LA PANTALLA (empresas de Lawang, 7-oct-2026).
   Publica `window.LW_ROL`. Se carga ANTES de cierre.js y de guard.js en todas las páginas con sesión (también en el hub, que no
   carga guard.js); lo usan guard.js, herramientas.js, topbar.js, cierre.js y las pantallas de la intranet. Sin dependencias. */
(function () {
/* UN SOLO PUNTO DE VERDAD DE «QUIÉN ES QUIÉN» PARA LA PANTALLA (empresas de Lawang, 7-oct-2026, cierre bloque 7).
   Hay dos roles que solo valen dentro de su empresa: `admin_empresa` (hace lo de un admin) y `super_admin_empresa` (lo de
   un super admin). Para MOSTRAR cuentan como admin / super admin; la cerradura sigue siendo la base (`es_admin_de(empresa)`,
   RLS): nada de lo que decide la pantalla se cree el servidor. Antes cada pantalla comparaba `ficha.rol === 'admin'` a mano
   (unas 100 veces) y un rol de empresa caía en la vista de agente. Ahora se pregunta aquí:
     esAdmin(f)        admin, super_admin o un rol de empresa            (¿enseño las pantallas de administración?)
     esSuperAdmin(f)   super_admin o super_admin_empresa                 (¿enseño lo de un super?)
     esSuperGlobal(f)  SOLO el super_admin global                        (herramientas sin casilla, ajustes de la instancia)
     esPropietario(f)  SOLO el propietario (super global con es_propietario) (Sociedades emisoras; la base lo decide con es_propietario())
     esEmpresa(f)      rol de empresa o ámbito 'empresa'
     esGlobal(f)       lo contrario: lo que es de toda la instancia (Ajustes, mantenimiento, tarifa 0,5 %, tablero CRM…)
     rolReal(f)        el rol tal cual está en la ficha (para pintar una etiqueta o la pantalla de Usuarios)
     empresas(f)       las empresas marcadas en la ficha ([] = sin acotar)
     puedeHerr(f,h)    ¿tiene la casilla `h`? Solo el super global se salta las casillas (igual que `puede()` en la base)
   Cada ficha trae `ambito` y `empresas` si la base los tiene; si no, se deducen del rol (una instancia sin esas columnas
   se comporta como siempre: todo global). */
var ROL_EMPRESA = { admin_empresa: 'admin', super_admin_empresa: 'super_admin' };
var LW_ROL = {
  rolReal: function (f) { return (f && f.rol) || ''; },
  efectivo: function (f) { var r = (f && f.rol) || ''; return ROL_EMPRESA[r] || r; },
  esAdmin: function (f) { var r = LW_ROL.efectivo(f); return r === 'admin' || r === 'super_admin'; },
  esSuperAdmin: function (f) { return LW_ROL.efectivo(f) === 'super_admin'; },
  esSuperGlobal: function (f) { return !!f && f.rol === 'super_admin'; },
  esPropietario: function (f) { return !!f && f.rol === 'super_admin' && f.es_propietario === true && f.ambito !== 'empresa'; },
  esEmpresa: function (f) { return !!f && (!!ROL_EMPRESA[f.rol] || f.ambito === 'empresa'); },
  esGlobal: function (f) { return !!f && !LW_ROL.esEmpresa(f); },
  empresas: function (f) { return (f && Array.isArray(f.empresas)) ? f.empresas : []; },
  puedeHerr: function (f, h) { return !!f && (f.rol === 'super_admin' || (f.herramientas || []).indexOf(h) !== -1); },
  /* ── Empresas para ELEGIR (selectores de las pantallas) ─────────────────────────────────────────────────────────
     catalogo()          las empresas activas [{clave, nombre}], leídas una vez por página
     misEmpresas(f)      las que puede elegir esta persona: las de su ficha, o todas si no está acotada (Promise)
     elegirEmpresa(f,o)  Promise<{ok, empresa}>: con UNA (o ninguna) no pregunta; con varias abre el selector de la suite
                         (lwElegir). `o.titulo`, `o.sinEmpresa` (ofrece «Sin empresa» y devuelve empresa:null).
                         ok:false = cerró el selector sin elegir.
     reintentaConEmpresa(f, llamar, o)   llama `llamar(null)`; si la base contesta 22023 «Elige/indica la empresa»,
                         pregunta y repite con `llamar(clave)`. La empresa la valida SIEMPRE el servidor: lo elegido aquí
                         solo dice cuál de las suyas quiere. */
  catalogo: function () {
    if (!catalogoP) {
      catalogoP = (window.LW_SB ? Promise.resolve(window.LW_SB.from('empresas').select('clave,nombre,orden,activa'))
                                : Promise.reject(new Error('sin cliente')))
        .then(function (r) {
          return (r && !r.error && r.data) ? r.data.filter(function (e) { return e.activa !== false; })
            .sort(function (a, b) { return (a.orden || 0) - (b.orden || 0); }) : [];
        }, function () { return []; })
        .then(function (l) { if (!l.length) catalogoP = null; return l; });   // sin lista (red) no se memoriza
    }
    return catalogoP;
  },
  misEmpresas: function (f) {
    var mias = LW_ROL.empresas(f);
    return LW_ROL.catalogo().then(function (cat) {
      return mias.length ? cat.filter(function (e) { return mias.indexOf(e.clave) !== -1; }) : cat;
    });
  },
  elegirEmpresa: function (f, o) {
    o = o || {};
    return LW_ROL.misEmpresas(f).then(function (lista) {
      if (!o.sinEmpresa && lista.length <= 1) return { ok: true, empresa: lista.length ? lista[0].clave : null };
      if (typeof window.lwElegir !== 'function') return { ok: false };
      var ops = lista.map(function (e) { return { valor: e.clave, texto: e.nombre }; });
      if (o.sinEmpresa) ops.push({ valor: '__ninguna', texto: (window.lwT || function (x) { return x; })('Sin empresa (solo la ve la dirección)') });
      return window.lwElegir({ titulo: o.titulo || (window.lwT || function (x) { return x; })('¿De qué empresa?'), opciones: ops }).then(function (v) {
        if (v == null) return { ok: false };
        return { ok: true, empresa: v === '__ninguna' ? null : v };
      });
    });
  },
  reintentaConEmpresa: function (f, llamar, o) {
    return Promise.resolve(llamar(null)).then(function (r) {
      var e = r && r.error;
      if (!e || (e.code !== '22023' && e.code !== '42501') || !/(elige|indica) la empresa|varias empresas/i.test(e.message || '')) return r;
      return LW_ROL.elegirEmpresa(f, o).then(function (el) {
        if (!el.ok || !el.empresa) return { error: { code: 'cancelado', message: 'No has elegido empresa' }, cancelado: true };
        return llamar(el.empresa);
      });
    });
  }
};
var catalogoP = null;

  try { Object.defineProperty(window, 'LW_ROL', { value: Object.freeze(LW_ROL), writable: false, configurable: false, enumerable: true }); } catch (e) { /* MUDO A PROPOSITO: una segunda carga del fichero no pisa la primera */ }
})();
