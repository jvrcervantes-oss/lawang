#!/usr/bin/env python3
"""
THE COLLECTION v2 · F4 — migra las fichas VISIBLES de data.json (PRODUCCIÓN) a `fichas_publicas`. 2-oct-2026.
Encargo: encargos/20261002_lawang_thecollection_v2.md (F4) y _F1.md (dueño de cada clave, mapeo ficha → proyecto).
Tabla destino: supabase/migrations/20261002120000_thecollection_fichas_publicas.sql (F2).

POR QUÉ existe: hasta hoy `data.json` (escrito por admin.html → api/save.php) es el único dueño de lo que muestra The Collection y
la intranet no lo sabe. La v2 lee de la intranet («el dato tiene un dueño»). Este script lleva ESE contenido a su sitio, una vez y
de forma repetible, sin tocar `data.json`, `admin.html` ni `save.php` (el congelado es decisión posterior del CEO).

Qué hace y qué NO hace (cada decisión con su porqué):
  · Lee el data.json de PRODUCCIÓN (con cache-bust), nunca el del repo: el del repo está en .gitignore y difiere en 6 fichas (F1 §0).
  · Migra solo las `visible: true`. Los esqueletos `land` (todos ocultos, precio 0, sin imágenes) y las ocultas (joglo-kembar-ii) NO se
    migran. Una ficha visible que no esté en MAPEO PARA el script con error: alta nueva = decisión consciente, no un efecto lateral.
  · Escribe SOLO lo que el contrato F0 admite: columnas tipadas de `fichas_publicas`, textos EN/ES en `textos`, el resto en `ficha`.
    Nada de notas, contratos, cuotas, comisiones ni precios internos: no existen en data.json y la lista blanca de abajo no los lee.
  · PRECIO: signature = precio_modo 'fijo' con data.json.priceEUR; villa (Palm Field: casa + parcela elegibles) = 'desde' con el
    priceEUR actual como respaldo hasta que F5b lo derive de `unidades`. Va SOLO a fichas_publicas: unidades.precio no se toca.
  · Lo que ya tiene dueño en la intranet NO se copia (galería = deck_fotos; configurador = unidades/modelos/extras; unitsAvailable/Total
    = conteo de unidades). Excepción deliberada: las 4 casas dadas de alta en F2 (tirta-hikari, cube, river, aqua) no tienen galería en
    `deck_fotos` todavía (hay que subir webp al bucket, escritura en Storage fuera de F4): sus rutas actuales van a ficha.imagenes.
  · IDEMPOTENTE: upsert por slug; el trigger de sello de la tabla convierte una escritura idéntica en no-op (ni actualizado_en ni fila
    en fichas_publicas_log). Y NO PISA ediciones humanas: solo actualiza filas cuyo `actualizado_por` sea de sistema ('sistema:…'),
    de modo que re-ejecutarlo después de que un admin edite una ficha (F3) no deshace su cambio; esas filas se cuentan como `omitidas`.
  · NUNCA borra: una ficha que ya no esté en data.json se queda como está.

Uso (el SQL se ejecuta por execute_sql del MCP supabase-lawang, o psql como postgres; el script no tiene credenciales):
  python supabase/datos/fichas_publicas_desde_datajson.py sql prueba   > prueba.sql   # acaba en `raise exception 'RES: …'` = ROLLBACK
  python supabase/datos/fichas_publicas_desde_datajson.py sql real     > real.sql     # escribe de verdad y devuelve contadores
  python supabase/datos/fichas_publicas_desde_datajson.py lectura      > lectura.sql  # SELECT de lo migrado (para el diff)
  python supabase/datos/fichas_publicas_desde_datajson.py diff lectura.json           # data.json(prod) vs lo leído de la base
  Opciones: --origen <url|fichero> (por defecto producción). Salida del diff ≠ 0 si hay diferencias.
ROLLBACK de los datos: delete from fichas_publicas where actualizado_por like 'sistema:%' and slug in (…); el log queda (es de solo-añadir).
"""
import argparse
import json
import re
import sys
import time
import urllib.request

ORIGEN_PROD = "https://lawangproperties.com/data.json"

# ficha de data.json → (slug del proyecto de la intranet, código de la unidad única | None, ¿lleva ficha.imagenes?)
# Fuente: _F1.md §4.2 (+ las 4 altas de F2). riverfront-ii-big y -small comparten proyecto. palm-field-bali: el proyecto se llama
# «Palm Field W5» (slug palmfield). modelo_id queda NULL en todas: una columna no puede guardar los 3 modelos de Palm Field; los
# modelos se leen por modelos_villa (F5b), no por esta FK.
MAPEO = {
    "tirta-hikari":        ("tirta-hikari",     "Villa 1", True),
    "cube":                ("cube",             "Villa 1", True),
    "river":               ("river",            "Villa 1", True),
    "aqua":                ("aqua",             "Villa 1", True),
    "riverfront-i":        ("riverfront-i",     None, False),
    "riverfront-ii-big":   ("riverfront-ii",    None, False),
    "riverfront-ii-small": ("riverfront-ii",    None, False),
    "riverfront-iii":      ("riverfront-iii",   None, False),
    "tangkuban-village":   ("tangkuban-village", None, False),
    "pura-dalem":          ("pura-dalem",       None, False),
    "rurung-anyar":        ("rurung-anyar",     None, False),
    "palm-field-bali":     ("palmfield",        None, False),
}

# Claves de data.json que NO se migran, y por qué (el diff exige que, si traen valor en una ficha visible, esté aquí).
NO_MIGRADAS = {
    "images": "galería = deck_fotos (dueño intranet); solo las 4 casas sin proyecto la llevan en ficha.imagenes",
    "landOptions": "derivadas de unidades.superficie_m2 / precio_suelo (F5b)",
    "homeModels": "derivados de modelos / modelos_villa / modelo_extras (F5b); la intranet manda en el precio",
    "extras": "extras / modelo_extras (existen en la intranet)",
    "unitsAvailable": "derivada: conteo de unidades por estado",
    "unitsTotal": "derivada: conteo de unidades por estado",
    "nightlyRate": "descartada (0 en las 44)",
    "showLandOptions": "descartada: nadie la lee", "showHomeModels": "descartada: nadie la lee", "showExtras": "descartada: nadie la lee",
    "territory": "descartada: vacía", "principles": "descartada: vacía",
    "masterplanProject": "sustituida por la FK proyecto_id",
}
PLACEHOLDERS_HANDOVER = {"", "-", "–", "—"}  # «—» = «sin dato» en data.json: no se migra («nada con placeholders»)


def vacio(v):
    return v in (None, "", [], {}, 0, False) or (isinstance(v, dict) and all(vacio(x) for x in v.values()))


def lee_origen(origen):
    if origen.startswith("http"):
        url = origen + ("&" if "?" in origen else "?") + "cb=%d&x=1" % int(time.time())
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    with open(origen, encoding="utf-8") as f:
        return json.load(f)


def nuevo_prefijo(v, prefijo):
    v = (v or "").strip()
    return v[len(prefijo):] if v.startswith(prefijo) else v


def normaliza(p, orden):
    """Una ficha de data.json → una fila de fichas_publicas (columnas + textos + ficha)."""
    slug = p["id"]
    proy, unidad, con_imagenes = MAPEO[slug]
    signature = p["line"] == "signature"
    precio = p.get("priceEUR") or 0
    if signature:
        modo = "fijo" if precio else "consultar"
    else:
        modo = "desde" if precio else "consultar"
    textos = {}
    for k_orig, k in (("title", "title"), ("sub", "sub"), ("desc", "desc"), ("metaText", "meta"),
                      ("splitTitle", "split_title"), ("splitSub", "split_sub")):
        v = p.get(k_orig)
        if isinstance(v, dict) and not vacio(v):
            textos[k] = {"en": v.get("en") or "", "es": v.get("es") or ""}
    equip = {k: p[k] for k in ("pool", "poolType", "garage", "garageDesc", "furnished", "style") if not vacio(p.get(k))}
    diseno = {k: p[k] for k in ("splitImage", "bleedImage", "plan3dImage", "tabs", "logo", "isotype", "landColor") if not vacio(p.get(k))}
    ficha = {}
    if equip:
        ficha["equipamiento"] = equip
    for k_orig, k in (("view", "view"), ("highlights", "highlights"), ("techSpecs", "tech_specs"), ("downloads", "downloads"),
                      ("paymentPlan", "payment_plan"), ("videos", "videos"), ("aerial", "aerial"),
                      ("mapImage", "mapa_url"), ("masterplanImage", "masterplan_imagen"), ("masterplanPlots", "masterplan_pins")):
        if not vacio(p.get(k_orig)):
            ficha[k] = p[k_orig]
    if (p.get("handover") or "").strip() not in PLACEHOLDERS_HANDOVER:
        ficha["handover"] = p["handover"].strip()
    if diseno:
        ficha["diseno"] = diseno
    if con_imagenes and p.get("images"):
        ficha["imagenes"] = p["images"]
    return {
        "slug": slug, "linea": p["line"], "region_key": p["regionKey"], "region": p.get("region") or None,
        "publicada_web": bool(p.get("visible")), "en_coleccion": bool(p.get("inCollection")),
        "destacada": bool(p.get("featured")), "destacada_home": bool(p.get("homeFeatured")), "orden": orden,
        "proyecto_slug": proy, "unidad_codigo": unidad,
        "precio_modo": modo, "precio_eur": precio if precio else None,
        "tenure": nuevo_prefijo(p.get("tenure"), "tenure.") or None,
        "lease_years": p.get("leaseYears") or None,
        "estado_obra": nuevo_prefijo(p.get("status"), "status.") or None,
        "dormitorios": p.get("beds") or None, "banos": p.get("baths") or None,
        "construido_m2": p.get("built") or None, "parcela_m2": p.get("land") or None,
        "textos": textos, "ficha": ficha,
    }


def visibles(datos):
    out = []
    for i, p in enumerate(datos["properties"]):
        if p.get("visible"):
            if p["id"] not in MAPEO:
                sys.exit("ERROR: ficha visible sin mapeo (%s). Añádela a MAPEO con su proyecto, o ocúltala: no se migra a ciegas." % p["id"])
            out.append((i, p))
    return out


COLS = ["slug", "linea", "region_key", "region", "publicada_web", "en_coleccion", "destacada", "destacada_home", "orden",
        "precio_modo", "precio_eur", "tenure", "lease_years", "estado_obra", "dormitorios", "banos", "construido_m2",
        "parcela_m2", "textos", "ficha"]


def sql(modo, origen):
    filas = [normaliza(p, i) for i, p in visibles(lee_origen(origen))]
    carga = json.dumps(filas, ensure_ascii=True, separators=(",", ":"))
    assert "$f4$" not in carga
    proyectos = sorted({f["proyecto_slug"] for f in filas})
    cols_t = ", ".join(
        "%s %s" % (c, t) for c, t in [
            ("slug", "text"), ("linea", "text"), ("region_key", "text"), ("region", "text"), ("publicada_web", "boolean"),
            ("en_coleccion", "boolean"), ("destacada", "boolean"), ("destacada_home", "boolean"), ("orden", "integer"),
            ("proyecto_slug", "text"), ("unidad_codigo", "text"), ("precio_modo", "text"), ("precio_eur", "numeric"),
            ("tenure", "text"), ("lease_years", "integer"), ("estado_obra", "text"), ("dormitorios", "integer"),
            ("banos", "integer"), ("construido_m2", "numeric"), ("parcela_m2", "numeric"), ("textos", "jsonb"), ("ficha", "jsonb")])
    upsert = """insert into public.fichas_publicas as f (%(cols)s, proyecto_id, unidad_id)
select %(tcols)s,
       (select p.id from public.proyectos p where p.slug = t.proyecto_slug),
       (select u.id from public.unidades u join public.proyectos p on p.id = u.proyecto_id
         where p.slug = t.proyecto_slug and u.codigo = t.unidad_codigo)
  from _f4 t
on conflict (slug) do update set %(sets)s, proyecto_id = excluded.proyecto_id, unidad_id = excluded.unidad_id
  where f.actualizado_por like 'sistema:%%';""" % {
        "cols": ", ".join(COLS), "tcols": ", ".join("t." + c for c in COLS),
        "sets": ", ".join("%s = excluded.%s" % (c, c) for c in COLS if c != "slug")}
    cab = ("-- F4 The Collection v2 · modo %s · generado %s desde %s\n"
           "-- Un solo envío = una transacción: si algo falla no queda nada a medias.\n" % (modo, time.strftime("%Y-%m-%d %H:%M"), origen.split("?")[0]))
    guarda = """do $g$
begin
  if (select count(*) from public.proyectos where slug = any (array[%(proy)s])) <> %(nproy)d then
    raise exception 'F4: falta algún proyecto de la intranet (%(proy2)s)';
  end if;
  if exists (select 1 from _f4 t where t.unidad_codigo is not null and not exists (
      select 1 from public.unidades u join public.proyectos p on p.id = u.proyecto_id where p.slug = t.proyecto_slug and u.codigo = t.unidad_codigo)) then
    raise exception 'F4: falta una unidad de las 4 casas dadas de alta en F2';
  end if;
end $g$;""" % {"proy": ", ".join("'%s'" % x for x in proyectos), "nproy": len(proyectos), "proy2": ", ".join(proyectos)}
    cuerpo = [
        cab,
        "create temp table _f4 on commit drop as select * from jsonb_to_recordset($f4$%s$f4$::jsonb) as t(%s);" % (carga, cols_t),
        guarda,
        "create temp table _c0 on commit drop as select (select count(*) from public.fichas_publicas_log) as log_n, now() as t;",
        upsert,
        "create temp table _c1 on commit drop as select (select count(*) from public.fichas_publicas_log) as log_n, (select count(*) from public.fichas_publicas) as filas;",
        upsert,
    ]
    resumen = """jsonb_build_object(
  'candidatas', (select count(*) from _f4),
  'filas_en_tabla', (select count(*) from public.fichas_publicas),
  'publicadas_web', (select count(*) from public.fichas_publicas where publicada_web),
  'log_escrito_1a_pasada', (select c1.log_n - c0.log_n from _c0 c0, _c1 c1),
  'log_escrito_2a_pasada_debe_ser_0', (select (select count(*) from public.fichas_publicas_log) - c1.log_n from _c1 c1),
  'omitidas_por_edicion_humana', (select count(*) from _f4 t join public.fichas_publicas f using (slug) where f.actualizado_por not like 'sistema:%'),
  'sin_proyecto_vinculado', (select count(*) from public.fichas_publicas f where f.proyecto_id is null),
  'con_unidad', (select count(*) from public.fichas_publicas f where f.unidad_id is not null),
  'quien', (select coalesce(string_agg(distinct actualizado_por, ','), '') from public.fichas_publicas))"""
    if modo == "prueba":
        cuerpo.append("do $r$ begin raise exception 'RES: %%', %s; end $r$;" % resumen)
    else:
        cuerpo.append("select %s as resultado;" % resumen)
    return "\n".join(cuerpo) + "\n"


def lectura():
    """SELECT de todo lo migrado, con los vínculos resueltos a slug/código (para el diff)."""
    cols = ", ".join("f.%s" % c for c in COLS)
    return ("select coalesce(jsonb_agg(to_jsonb(x) order by x.orden), '[]'::jsonb) as filas from (\n"
            "  select %s, p.slug as proyecto_slug, u.codigo as unidad_codigo, f.modelo_id, f.actualizado_por\n"
            "    from public.fichas_publicas f\n"
            "    left join public.proyectos p on p.id = f.proyecto_id\n"
            "    left join public.unidades u on u.id = f.unidad_id\n"
            "   where f.publicada_web) x;\n" % cols)


def carga_lectura(ruta):
    """Acepta el JSON puro o el envoltorio que devuelve el MCP ({"result": "...<untrusted-data-…>[…]</untrusted-data-…>..."})."""
    txt = open(ruta, encoding="utf-8").read()
    try:
        o = json.loads(txt)
        if isinstance(o, dict) and "result" in o:
            txt = o["result"]
        elif isinstance(o, list):
            return o[0]["filas"] if o and isinstance(o[0], dict) and "filas" in o[0] else o
    except ValueError:
        pass
    m = re.search(r"<untrusted-data-[^>]+>\s*(.*?)\s*</untrusted-data-", txt, re.S)
    o = json.loads(m.group(1) if m else txt)
    if isinstance(o, list) and o and isinstance(o[0], dict) and "filas" in o[0]:
        o = o[0]["filas"]
    return o


def diff(ruta, origen):
    leidas = {r["slug"]: r for r in carga_lectura(ruta)}
    errores, avisos, n = [], [], 0
    for _, p in visibles(lee_origen(origen)):
        n += 1
        slug = p["id"]
        r = leidas.get(slug)
        if not r:
            errores.append("%s: no está en fichas_publicas (publicada_web)" % slug)
            continue
        esp = normaliza(p, r["orden"])   # misma regla; abajo se comprueba además, campo a campo, contra el data.json en crudo

        def igual(campo, a, b):
            if a != b and not (vacio(a) and vacio(b)):
                errores.append("%s.%s: data.json=%r base=%r" % (slug, campo, str(a)[:80], str(b)[:80]))

        t, f = r["textos"], r["ficha"]
        igual("id", slug, r["slug"]); igual("line", p["line"], r["linea"]); igual("regionKey", p["regionKey"], r["region_key"])
        igual("region", p.get("region"), r["region"]); igual("visible", bool(p.get("visible")), r["publicada_web"])
        igual("inCollection", bool(p.get("inCollection")), r["en_coleccion"]); igual("featured", bool(p.get("featured")), r["destacada"])
        igual("homeFeatured", bool(p.get("homeFeatured")), r["destacada_home"])
        igual("priceEUR", p.get("priceEUR") or 0, float(r["precio_eur"] or 0))
        igual("precio_modo", "fijo" if p["line"] == "signature" else "desde", r["precio_modo"])
        igual("tenure", nuevo_prefijo(p.get("tenure"), "tenure."), r["tenure"] or "")
        igual("leaseYears", p.get("leaseYears") or 0, r["lease_years"] or 0)
        igual("status", nuevo_prefijo(p.get("status"), "status."), r["estado_obra"] or "")
        for k_o, k_b in (("beds", "dormitorios"), ("baths", "banos"), ("built", "construido_m2"), ("land", "parcela_m2")):
            igual(k_o, p.get(k_o) or 0, float(r[k_b] or 0))
        for k_o, k in (("title", "title"), ("sub", "sub"), ("desc", "desc"), ("metaText", "meta"), ("splitTitle", "split_title"), ("splitSub", "split_sub")):
            v = p.get(k_o) or {}
            igual(k_o, {"en": v.get("en") or "", "es": v.get("es") or ""} if not vacio(v) else {}, t.get(k, {}))
        eq = f.get("equipamiento", {})
        for k in ("pool", "poolType", "garage", "garageDesc", "furnished", "style"):
            igual(k, p.get(k), eq.get(k))
        for k_o, k in (("view", "view"), ("highlights", "highlights"), ("techSpecs", "tech_specs"), ("downloads", "downloads"),
                       ("paymentPlan", "payment_plan"), ("videos", "videos"), ("aerial", "aerial"), ("mapImage", "mapa_url"),
                       ("masterplanImage", "masterplan_imagen"), ("masterplanPlots", "masterplan_pins")):
            igual(k_o, p.get(k_o), f.get(k))
        ho = (p.get("handover") or "").strip()
        igual("handover", "" if ho in PLACEHOLDERS_HANDOVER else ho, f.get("handover"))
        for k in ("splitImage", "bleedImage", "plan3dImage", "tabs", "logo", "isotype", "landColor"):
            igual(k, p.get(k), f.get("diseno", {}).get(k))
        if MAPEO[slug][2]:
            igual("images", p.get("images"), f.get("imagenes"))
        elif "imagenes" in f:
            errores.append("%s: lleva ficha.imagenes pero su galería es de deck_fotos" % slug)
        igual("proyecto", MAPEO[slug][0], r["proyecto_slug"]); igual("unidad", MAPEO[slug][1], r["unidad_codigo"])
        if r.get("modelo_id"):
            avisos.append("%s: modelo_id puesto (no lo pone F4)" % slug)
        # Coherencia con la normalización (detecta deriva entre las dos lecturas del mismo dato)
        for c in COLS:
            if c in ("orden",):
                continue
            a, b = esp[c], r[c]
            if c in ("precio_eur", "construido_m2", "parcela_m2") and a is not None and b is not None:
                a, b = float(a), float(b)
            if a != b:
                errores.append("%s.%s (normalizado): %r != %r" % (slug, c, str(a)[:60], str(b)[:60]))
        # Claves con valor que NO se migran: deben estar justificadas
        for k, v in p.items():
            if not vacio(v) and k in NO_MIGRADAS:
                avisos.append("%s.%s no migrada (%s)" % (slug, k, NO_MIGRADAS[k]))
    extra = set(leidas) - {p["id"] for _, p in visibles(lee_origen(origen))}
    for s in sorted(extra):
        errores.append("%s: publicada en la base y no visible en data.json" % s)
    print("fichas comparadas: %d · en la base (publicadas): %d" % (n, len(leidas)))
    print("DIFERENCIAS: %d" % len(errores))
    for e in errores:
        print("  ✗", e)
    if "-v" in sys.argv:
        for a in avisos:
            print("  ·", a)
    else:
        print("no migradas con valor (por diseño): %d (ver -v)" % len(avisos))
    return 1 if errores else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("accion", choices=["sql", "lectura", "diff"])
    ap.add_argument("arg", nargs="?", help="sql: prueba|real · diff: fichero con la lectura")
    ap.add_argument("--origen", default=ORIGEN_PROD)
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if a.accion == "sql":
        if a.arg not in ("prueba", "real"):
            ap.error("sql necesita prueba|real")
        sys.stdout.write(sql(a.arg, a.origen))
    elif a.accion == "lectura":
        sys.stdout.write(lectura())
    else:
        if not a.arg:
            ap.error("diff necesita el fichero de lectura")
        sys.exit(diff(a.arg, a.origen))


if __name__ == "__main__":
    main()
