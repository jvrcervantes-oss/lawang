#!/usr/bin/env python3
"""activa.py — ACTIVA la edge bot-api (S4). NO LO LANZA NINGUN AGENTE SIN EL OK ESCRITO DEL OWNER: pone LOGIN y clave al rol bot_lawang
en la base de PRODUCCION de Lawang y crea los secretos reales. Hasta entonces la edge responde 401 a todo (estado seguro).

    python activa.py --agencia <ruta del clon de la agencia> --servicio <carpeta de lawang-bot en la agencia>            # SIMULA (por defecto)
    python activa.py --agencia ... --servicio ... --aplica                                                              # hace los cambios

Que hace, en este orden (si falla un paso, los anteriores no rompen nada: la edge sigue dando 401 hasta que esten los tres secretos):
  1. Genera EN MEMORIA tres secretos: clave de la BD de bot_lawang, secreto de la ruta catalogo y secreto de la ruta crm. Nunca se imprimen ni van por argv.
  2. Railway (servicio lawang-bot): BOT_API_SECRET_CATALOGO y BOT_API_SECRET_CRM por stdin, con --skip-deploys (el bot los usara en S6).
  3. Base: ALTER ROLE bot_lawang LOGIN PASSWORD '<verificador SCRAM>' CONNECTION LIMIT 5 + statement_timeout 5s (psql por stdin, nunca la clave en claro).
  4. Edge: BOT_DB_URL (pooler, puerto 6543, usuario bot_lawang.<ref>), BOT_API_SECRET_CATALOGO y BOT_API_SECRET_CRM con `supabase secrets set --env-file`
     sobre un fichero temporal que se borra siempre.
Despues: ver ACTIVACION.md (verificacion y vuelta atras).
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
    print("OK · bot_lawang LOGIN, 3 secretos sellados (valores nunca impresos). Verificar con ACTIVACION.md.")


if __name__ == "__main__":
    main()
