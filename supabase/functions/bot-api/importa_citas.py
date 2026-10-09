#!/usr/bin/env python3
"""importa_citas.py — importacion UNICA (y repetible) de las citas vivas de Redis a Postgres. S5 del encargo del bot de Lawang.

    # 1. baja las citas del bot (GET /admin/api/appts, solo lectura) y prepara el SQL; NO toca la base
    python supabase/functions/bot-api/importa_citas.py --servicio infraestructura/bot-whatsapp --salida <carpeta fuera del repo>
    # 2. quien tiene el propietario de la base ejecuta el .sql que sale (MCP execute_sql o psql): devuelve (ref, resultado) por cita
    # 3. con ese resultado guardado en un .json ([{"ref":"redis:..","resultado":".."}]), el informe de lo que no casó
    python supabase/functions/bot-api/importa_citas.py --servicio infraestructura/bot-whatsapp --salida <carpeta> --resultados resultados.json

POR QUÉ ASÍ (9-oct-2026). La clave de Redis vive solo en Railway y es interna (`redis.railway.internal`): desde fuera no se llega. El propio
bot ya lista sus citas con `GET /admin/api/appts` (lo que leía la pestaña Agenda), así que se usa ESE camino, con la clave de admin leída
dentro de este proceso (`railway variables`) y nunca impresa ni escrita. Nada de esto toca la base: el SQL lo ejecuta una persona.
La función de la base (`public._bot_importa_citas`, migración 20261010100100) casa cada cita con su lead por teléfono normalizado y NO elige
cuando hay 0 o más de 1; es repetible (clave `ref_origen` = 'redis:<id>'). Se ejecuta ahora y otra vez justo antes de encender BOT_CRM=on.

Lo que escribe en `--salida` lleva TELÉFONOS Y NOMBRES REALES: esa carpeta debe estar FUERA del repo. El script se niega a escribir dentro de uno.
Por stdout solo salen recuentos.
"""
import argparse
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

BOT = "https://lawang-bot-production.up.railway.app"


def dentro_de_un_repo(carpeta: Path) -> bool:
    for p in [carpeta, *carpeta.parents]:
        if (p / ".git").exists():
            return True
    return False


def clave_admin(servicio: Path) -> str:
    out = subprocess.run(["railway", "variables", "--kv"], cwd=servicio, capture_output=True, text=True, shell=(sys.platform == "win32"))
    if out.returncode != 0:
        sys.exit("railway variables ha fallado (código %d): ¿está enlazado el servicio?" % out.returncode)
    for linea in out.stdout.splitlines():
        if linea.startswith("ADMIN_PASSWORD="):
            return linea.split("=", 1)[1]
    sys.exit("el servicio no tiene ADMIN_PASSWORD")


def citas_del_bot(servicio: Path):
    req = urllib.request.Request(BOT + "/admin/api/appts", headers={"x-admin-key": clave_admin(servicio)})
    with urllib.request.urlopen(req, timeout=30) as r:
        datos = json.load(r)
    if not isinstance(datos, list):
        sys.exit("el bot no devolvió una lista de citas")
    return datos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--servicio", required=True, help="carpeta del servicio lawang-bot enlazado a Railway")
    ap.add_argument("--salida", required=True, help="carpeta FUERA de cualquier repo donde dejar el .sql y el informe")
    ap.add_argument("--resultados", help="json con las filas (ref, resultado) que devolvió la base: genera el informe de lo no importado")
    a = ap.parse_args()
    salida = Path(a.salida).resolve()
    if dentro_de_un_repo(salida):
        sys.exit("--salida está dentro de un repo: lleva teléfonos reales y no puede acabar commiteada")
    salida.mkdir(parents=True, exist_ok=True)
    servicio = Path(a.servicio).resolve()

    citas = citas_del_bot(servicio)
    payload = [{"id": c.get("id", ""), "phone": c.get("phone", ""), "when": c.get("when", ""), "title": c.get("title", ""),
                "closer": c.get("closer", ""), "notes": c.get("notes", "")} for c in citas]
    print(f"citas en Redis (por el bot): {len(citas)}")

    if not a.resultados:
        if "$j$" in json.dumps(payload):
            sys.exit("una cita lleva el delimitador $j$ dentro: revisar a mano")
        sql = "select ref, resultado from public._bot_importa_citas($j$" + json.dumps(payload, ensure_ascii=False) + "$j$::jsonb);\n"
        (salida / "importa_citas.sql").write_text(sql, encoding="utf-8")
        print(f"SQL listo en {salida / 'importa_citas.sql'} (ejecutarlo como propietario de la base)")
        return

    filas = json.loads(Path(a.resultados).read_text(encoding="utf-8"))
    por_ref = {f["ref"]: f["resultado"] for f in filas}
    cuenta = {}
    informe = []
    for c in citas:
        ref = "redis:" + str(c.get("id", ""))
        res = por_ref.get(ref, "SIN_RESULTADO")
        cuenta[res] = cuenta.get(res, 0) + 1
        if res not in ("importada", "ya_importada"):
            informe.append(f"{res}\t{ref}\t{c.get('name','')}\t{c.get('phone','')}\t{c.get('when','')}\t{c.get('title','')}")
    (salida / "informe_citas_no_importadas.txt").write_text("\n".join(informe) + ("\n" if informe else ""), encoding="utf-8")
    print("resultados:", json.dumps(cuenta, sort_keys=True))
    print(f"no importadas: {len(informe)} (detalle en {salida / 'informe_citas_no_importadas.txt'})")


if __name__ == "__main__":
    main()
