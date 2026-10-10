#!/usr/bin/env python3
"""activa.py — ACTIVA la edge bot-api (S4). NO LO LANZA NINGUN AGENTE SIN EL OK ESCRITO DEL OWNER: pone LOGIN y clave al rol bot_lawang
en la base de PRODUCCION de Lawang y crea los secretos reales. Hasta entonces la edge responde 401 a todo (estado seguro).

    python activa.py --agencia <ruta del clon de la agencia> --servicio <carpeta de lawang-bot en la agencia>            # SIMULA (por defecto)
    python activa.py --agencia ... --servicio ... --aplica                                                              # hace los cambios
    python activa.py --agencia ... --servicio ... --s2 [--aplica]    # SOLO las 3 rutas de S2 (estado, recordatorio, humano); no toca el rol ni BOT_DB_URL

Que hace, en este orden (si falla un paso, los anteriores no rompen nada: la edge sigue dando 401 hasta que esten los tres secretos):
  1. Genera EN MEMORIA tres secretos: clave de la BD de bot_lawang, secreto de la ruta catalogo y secreto de la ruta crm. Nunca se imprimen ni van por argv.
  2. Railway (servicio lawang-bot): BOT_API_SECRET_CATALOGO y BOT_API_SECRET_CRM por stdin, con --skip-deploys (el bot los usara en S6).
  3. Base: ALTER ROLE bot_lawang LOGIN PASSWORD '<verificador SCRAM>' CONNECTION LIMIT 5 + statement_timeout 5s (psql por stdin, nunca la clave en claro).
  4. Edge: BOT_DB_URL (pooler, puerto 6543, usuario bot_lawang.<ref>), BOT_API_SECRET_CATALOGO y BOT_API_SECRET_CRM con `supabase secrets set --env-file`
     sobre un fichero temporal que se borra siempre.
Despues: ver ACTIVACION.txt (verificacion y vuelta atras).
"""
import importlib.util, os, subprocess, sys, tempfile
from pathlib import Path

REF, REGION, ROL = "vtulllundrfennhjddhc", "ap-southeast-1", "bot_lawang"


def main():
    a = sys.argv[1:]
    def opt(n):
        return a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else None
    ag, serv, aplica = opt("--agencia"), opt("--servicio"), "--aplica" in a
    if not ag or not serv:
        sys.exit(__doc__)
    ag = Path(ag)
    spec = importlib.util.spec_from_file_location("rs", ag / "tools" / "railway_secreto.py")
    rs = importlib.util.module_from_spec(spec); spec.loader.exec_module(rs)
    dest = Path(serv)
    if not dest.is_dir():
        sys.exit("no existe el servicio: %s" % serv)

    if "--s2" in a:
        return s2(rs, dest, aplica)
    if "--s5-importar" in a:
        return s5_importar(rs, dest, aplica)
    clave_db, sec_cat, sec_crm = rs.clave_aleatoria(), rs.clave_aleatoria(), rs.clave_aleatoria()
    verif = rs.verificador_scram(clave_db)
    secretos = [clave_db, sec_cat, sec_crm, verif]
    sql = ("begin;\nalter role %s login password '%s' connection limit 5;\n"
           "alter role %s set statement_timeout = '5s';\ncommit;\n" % (ROL, verif, ROL))
    url = "postgresql://%s.%s:%s@aws-0-%s.pooler.supabase.com:6543/postgres" % (ROL, REF, clave_db, REGION)
    if not aplica:
        print("SIMULACION (no se toca Railway, la base ni la edge):")
        print("  2. Railway %s: BOT_API_SECRET_CATALOGO, BOT_API_SECRET_CRM (%d caracteres cada una, stdin, sin redeploy)" % (serv, len(sec_cat)))
        print("  3. ALTER ROLE %s LOGIN PASSWORD '<SCRAM %d caracteres>' CONNECTION LIMIT 5; statement_timeout 5s" % (ROL, len(verif)))
        print("  4. supabase secrets set --env-file <temporal> --project-ref %s : BOT_DB_URL (usuario %s.%s), 2 secretos de ruta" % (REF, ROL, REF))
        return
    rs._railway(["variables", "--set-from-stdin", "BOT_API_SECRET_CATALOGO", "--skip-deploys"], dest, secretos, entrada=sec_cat)
    rs._railway(["variables", "--set-from-stdin", "BOT_API_SECRET_CRM", "--skip-deploys"], dest, secretos, entrada=sec_crm)
    rs._psql("lawang", sql, secretos)
    fd, ruta = tempfile.mkstemp(suffix=".env")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("BOT_DB_URL=%s\nBOT_API_SECRET_CATALOGO=%s\nBOT_API_SECRET_CRM=%s\n" % (url, sec_cat, sec_crm))
        p = subprocess.run(["cmd", "/c", "npx", "--yes", "supabase", "secrets", "set", "--env-file", ruta, "--project-ref", REF],
                           capture_output=True, text=True, timeout=180)
        if p.returncode != 0:
            sys.exit("supabase secrets set devolvio %d: %s" % (p.returncode, rs._limpia(p.stderr or "", secretos)[:300]))
    finally:
        try:
            os.remove(ruta)
        except OSError:
            pass   # MUDO A PROPOSITO: si ya no existe no hay nada que borrar
    print("OK · bot_lawang LOGIN, 3 secretos sellados (valores nunca impresos). Verificar con ACTIVACION.txt.")


S2 = ("BOT_API_SECRET_ESTADO", "BOT_API_SECRET_RECORDATORIO", "BOT_API_SECRET_HUMANO")
S2_RAILWAY = S2[:2]   # a Railway solo los dos del bot; el de /humano NO


def s2(rs, dest, aplica):
    """S2 (9-oct-2026): tres secretos nuevos, uno por ruta. Requiere que la activacion de S4 (rol bot_lawang con LOGIN y BOT_DB_URL) ya este hecha.
    Railway (lawang-bot: SOLO estado y recordatorio) --skip-deploys, y los secretos de la edge (son del PROYECTO: el proxy tambien los ve)."""
    vals = [rs.clave_aleatoria() for _ in S2]
    if not aplica:
        print("SIMULACION S2 (no se toca Railway ni la edge):")
        print("  Railway %s: %s (%d caracteres cada una, stdin, sin redeploy; el de /humano NO va a Railway)" % (dest, ", ".join(S2_RAILWAY), len(vals[0])))
        print("  supabase secrets set --env-file <temporal> --project-ref %s : %s" % (REF, ", ".join(S2)))
        return
    for nombre, v in zip(S2, vals):
        if nombre not in S2_RAILWAY:
            continue   # el de /humano vive solo en la edge (y en el proxy, S3/S10): una fuga del bot no puede enviar como persona
        rs._railway(["variables", "--set-from-stdin", nombre, "--skip-deploys"], dest, vals, entrada=v)
    fd, ruta = tempfile.mkstemp(suffix=".env")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("".join("%s=%s" % (n, v) + chr(10) for n, v in zip(S2, vals)))
        p = subprocess.run(["cmd", "/c", "npx", "--yes", "supabase", "secrets", "set", "--env-file", ruta, "--project-ref", REF],
                           capture_output=True, text=True, timeout=180)
        if p.returncode != 0:
            sys.exit("supabase secrets set devolvio %d: %s" % (p.returncode, rs._limpia(p.stderr or "", vals)[:300]))
    finally:
        try:
            os.remove(ruta)
        except OSError:
            pass   # MUDO A PROPOSITO: si ya no existe no hay nada que borrar
    print("OK - 3 secretos de S2 sellados (valores nunca impresos). Verificar con ACTIVACION.txt.")


def s5_importar(rs, dest, aplica):
    """S5-puente (LAW-507, 9-oct-2026): el secreto de la ruta TEMPORAL /importar. Va a Railway (lawang-bot, sin redeploy: el bot lo lee al lanzar la
    importacion) y a la edge. Se RETIRA en S9: `supabase secrets unset BOT_API_SECRET_IMPORTAR` y quitar la variable de Railway."""
    nombre = "BOT_API_SECRET_IMPORTAR"
    v = rs.clave_aleatoria()
    if not aplica:
        print("SIMULACION S5-importar (no se toca Railway ni la edge): %s (%d caracteres) en Railway %s y en la edge %s" % (nombre, len(v), dest, REF))
        return
    rs._railway(["variables", "--set-from-stdin", nombre, "--skip-deploys"], dest, [v], entrada=v)
    fd, ruta = tempfile.mkstemp(suffix=".env")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("%s=%s" % (nombre, v) + chr(10))
        p = subprocess.run(["cmd", "/c", "npx", "--yes", "supabase", "secrets", "set", "--env-file", ruta, "--project-ref", REF],
                           capture_output=True, text=True, timeout=180)
        if p.returncode != 0:
            sys.exit("supabase secrets set devolvio %d: %s" % (p.returncode, rs._limpia(p.stderr or "", [v])[:300]))
    finally:
        try:
            os.remove(ruta)
        except OSError:
            pass   # MUDO A PROPOSITO: si ya no existe no hay nada que borrar
    print("OK - %s sellado en Railway y en la edge (valor nunca impreso)." % nombre)


if __name__ == "__main__":
    main()
