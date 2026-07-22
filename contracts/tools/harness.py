# -*- coding: utf-8 -*-
"""Genera _test_app.html = app.html con Supabase falseado.

La app real redirige a login.html si no hay sesión, así que no se puede
verificar con un navegador headless. Esto sustituye el <script> del CDN de
Supabase por un stub con sesión y consultas encadenables — nada más. El
resultado está gitignorado: es una herramienta de verificación, no producción.

    python tools/harness.py && python -m http.server 8891   (desde proyectos/Lawang)
    → http://localhost:8891/contracts/_test_app.html
"""
import io, os, re

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CDN = re.compile(r'<script src="https://cdn\.jsdelivr\.net/npm/@supabase[^>]*></script>')

STUB = """<script>
/* stub de Supabase — solo para verificación local, ver tools/harness.py */
window.supabase = { createClient: function(){
  var res = function(){ return Promise.resolve({ data:null, error:null }); };
  var q = {}; ['select','eq','neq','order','limit','insert','update','upsert','delete','ilike']
    .forEach(function(m){ q[m] = function(){ return q; }; });
  q.single = q.maybeSingle = res;
  q.then = function(f){ return Promise.resolve({ data:[], error:null }).then(f); };
  return {
    auth: {
      getSession: function(){ return Promise.resolve({ data:{ session:{ user:{ id:'test',
        email:'test@lawangproperties.com', user_metadata:{}, app_metadata:{agente:true} } } } }); },
      signOut: res, signInWithPassword: res
    },
    from: function(){ return q; },
    storage: { from: function(){ return { upload: res,
      createSignedUrl: function(){ return Promise.resolve({ data:{ signedUrl:'#' }, error:null }); } }; } }
  };
} };
</script>"""

with io.open(os.path.join(BASE, "app.html"), encoding="utf-8") as f:
    html = f.read()
out, n = CDN.subn(STUB, html)
assert n == 1, "no encuentro el <script> del CDN de Supabase en app.html (%d)" % n
with io.open(os.path.join(BASE, "_test_app.html"), "w", encoding="utf-8", newline="") as f:
    f.write(out)
print("_test_app.html generado")
