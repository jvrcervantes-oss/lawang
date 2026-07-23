# -*- coding: utf-8 -*-
"""Auditoria de enlazado de la app de contratos Lawang.

Cruza marcadores de plantillas <-> campos de tokens.json <-> motor (app.html) y
reporta lo que no cuadra: marcadores sin resolver (imprimirian en blanco), campos
muertos (en tokens.json y nunca usados), marcadores dinamicos <!--x--> sin handler,
cuentas bancarias rotas, assets inexistentes, plantillas del array que faltan y
funciones JS huerfanas.

Relanzar tras anadir/renombrar plantillas o campos:
    python contracts/tools/auditar_enlazado.py    (desde proyectos/Lawang)

Salida "todo OK / 0 ..." = la app esta bien enlazada. Cualquier [!] es algo a mirar.
Nota: {{firma_adquiriente}} NO es un fallo aunque no tenga campo -> es la firma, el
motor la resuelve por el pad (startsWith('firma')) y la saca del form a proposito.
"""
import re, io, os, json

BASE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
def read(p): return io.open(p, encoding="utf-8").read()

tokens = json.loads(read(os.path.join(BASE, "tokens.json")))
app = read(os.path.join(BASE, "app.html"))
tpl_dir = os.path.join(BASE, "templates")
tpls = {f: read(os.path.join(tpl_dir, f)) for f in os.listdir(tpl_dir) if f.endswith(".html")}

# ---- campos declarados en tokens.json ----
token_fields = {}   # key -> (section_id, label_es)
for sec in tokens.get("sections", []):
    for f in sec.get("fields", []):
        token_fields[f[0]] = (sec["id"], f[1].get("es", "") if isinstance(f[1], dict) else str(f[1]))

# ---- uso en plantillas: {{k}}, <!--if:k=v-->, <!--opt:k--> ----
used_in_tpl = {}    # key -> set(archivos)
marker_all = {}     # {{k}} -> set(archivos)
dyn_markers = {}    # <!--nombre--> (no if/opt/cierre) -> set(archivos)
for fn, html in tpls.items():
    for k in re.findall(r"\{\{([a-z0-9_]+)\}\}", html):
        marker_all.setdefault(k, set()).add(fn); used_in_tpl.setdefault(k, set()).add(fn)
    for k in re.findall(r"<!--if:([a-z0-9_]+)=", html):
        used_in_tpl.setdefault(k, set()).add(fn)
    for k in re.findall(r"<!--opt:([a-z0-9_]+)-->", html):
        used_in_tpl.setdefault(k, set()).add(fn)
    for m in re.findall(r"<!--(/?[a-z0-9_-]+)-->", html):
        if not m.startswith(("if:", "opt:", "/")):
            dyn_markers.setdefault(m, set()).add(fn)

# marcadores que calcula el motor (no son campos de tokens) y campos que consume
# el motor sin que aparezcan como {{marcador}} literal en la plantilla
ENGINE_MARKERS = {"cov_t", "cov_t_id", "contrato_num", "firma_adquiriente"}
ENGINE_CONSUMED = {"cuenta_bancaria", "tipo_cambio_idr", "fecha_tipo_cambio", "moneda"}

def sec(title): print("=" * 70); print(title)

# A. MARCADORES SIN RESOLVER
sec("A. Marcadores {{}} en plantillas SIN campo ni handler del motor")
unresolved = [(k, files) for k, files in sorted(marker_all.items())
              if k not in token_fields and k not in ENGINE_MARKERS]
for k, files in unresolved:
    print(f"  [!] {{{{{k}}}}} -> sin campo. En: {', '.join(sorted(files))}")
if not unresolved:
    print("  OK - todo marcador tiene campo en tokens.json o lo resuelve el motor")

# B. CAMPOS MUERTOS
sec("B. Campos de tokens.json que NO se usan en ninguna plantilla")
dead = [(k, sid, lab) for k, (sid, lab) in sorted(token_fields.items())
        if k not in used_in_tpl and k not in ENGINE_CONSUMED]
for k, sid, lab in dead:
    print(f"  [!] '{k}' (seccion {sid}, '{lab}') -> no aparece en ninguna plantilla")
if not dead:
    print("  OK - todo campo de tokens.json se usa (o lo consume el motor)")

# C. MARCADORES DINAMICOS SIN HANDLER
sec("C. Marcadores dinamicos <!--x--> de plantillas sin handler en app.html")
orphan_dyn = [(m, files) for m, files in sorted(dyn_markers.items()) if f"<!--{m}-->" not in app]
for m, files in orphan_dyn:
    print(f"  [!] <!--{m}--> sin handler. En: {', '.join(sorted(files))}")
if not orphan_dyn:
    print("  OK - cada marcador dinamico tiene su tratamiento en el motor")

# D. hitosDefaults <-> plantillas con <!--hitos-->
sec("D. hitosDefaults vs plantillas con <!--hitos-->")
hitos_tpls = {fn for fn, h in tpls.items() if "<!--hitos-->" in h}
tmap = dict(re.findall(r"slug:'([a-z0-9_]+)'[^}]*?file:'templates/([a-z0-9_]+\.html)'", app))
slug_by_file = {v: k for k, v in tmap.items()}
hitos_defaults = {k for k in tokens.get("hitosDefaults", {}) if not k.startswith("_")}
print(f"  Plantillas con tabla de hitos: {sorted(slug_by_file.get(f, f) for f in hitos_tpls)}")
print(f"  Slugs con hitosDefaults: {sorted(hitos_defaults)}")
for f in hitos_tpls:
    slug = slug_by_file.get(f)
    if slug and slug not in hitos_defaults:
        print(f"  [i] {slug} tiene <!--hitos--> sin hitosDefaults (usa fallback 25x4) - OK si es intencional")

# E. CUENTAS BANCARIAS
sec("E. BANCOS_CONSTRUCCION apunta a cuentas reales")
cuentas = set(re.findall(r"^\s*([a-z0-9_]+):\s*\{\s*label:", app, re.M))
bcons = re.search(r"BANCOS_CONSTRUCCION\s*=\s*\[([^\]]*)\]", app)
if bcons:
    refs = re.findall(r"'([a-z0-9_]+)'", bcons.group(1))
    missing = [r for r in refs if r not in cuentas]
    print(f"  Cuentas definidas: {len(cuentas)} | refs construccion: {refs}")
    print("  [!] refs inexistentes: " + str(missing) if missing else "  OK - todas existen")

# F. ASSETS
sec("F. Assets (img src) referenciados en plantillas que no existen")
missing_assets = [(fn, src) for fn, html in tpls.items()
                  for src in re.findall(r'src="(assets/[^"?]+)"', html)
                  if not os.path.exists(os.path.join(BASE, src))]
for fn, src in missing_assets:
    print(f"  [!] {fn}: {src} NO existe")
if not missing_assets:
    print("  OK - todos los assets referenciados existen")

# G. PLANTILLAS DEL ARRAY
sec("G. Cada plantilla del array TEMPLATES existe en disco")
missing_tpl = [(s, f) for s, f in tmap.items() if not os.path.exists(os.path.join(BASE, "templates", f))]
for s, f in missing_tpl:
    print(f"  [!] {s} -> templates/{f} NO existe")
if not missing_tpl:
    print(f"  OK - {len(tmap)} plantillas del array existen")

# H. FUNCIONES JS HUERFANAS
sec("H. Funciones JS definidas y nunca referenciadas")
full = read(os.path.join(BASE, "app.html"))
js = "\n".join(m.group(1) for m in re.finditer(r"<script>([\s\S]*?)</script>", full))
defs = set(re.findall(r"function\s+([A-Za-z_$][\w$]*)\s*\(", js))
defs |= set(re.findall(r"(?:const|let)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>", js))
orphan_fn = [n for n in sorted(defs) if len(re.findall(r"\b" + re.escape(n) + r"\b", full)) <= 1]
print(f"  Funciones definidas: {len(defs)} | huerfanas: {orphan_fn if orphan_fn else 'NINGUNA'}")

sec("Resumen")
print(f"  {len(unresolved)} marcadores sin resolver | {len(dead)} campos muertos | "
      f"{len(orphan_dyn)} dinamicos sin handler | {len(missing_assets)} assets rotos | "
      f"{len(missing_tpl)} plantillas faltantes | {len(orphan_fn)} funciones huerfanas")
