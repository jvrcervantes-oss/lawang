"""Genera contracts/sql/ensayo_2159_viva.sql: el ensayo deshecho de 20261014223000 en la viva de Lawang en UNA llamada.

Uso: python genera_ensayo_2159.py <copia Lawang> <agencia>   (escribe el fichero en la copia e imprime las huellas)
Para (sys.exit) si: un texto incrustado no es idéntico a su fuente, una etiqueta del envoltorio aparece dentro de un texto,
queda un begin;/commit/rollback de nivel superior, o pglast no parsea un bloque o el fichero entero.
"""
import hashlib
import os
import re
import subprocess
import sys

COPIA, AGENCIA = sys.argv[1], sys.argv[2]
MIG = 'supabase/migrations/20261014223000_recibi_total_suma_y_exento.sql'
MIG_SHA = '08c84d8112cfe3f545f86f99c819ab5d0e756062a20ccfd10f17b82013be3c75'
PRUEBAS = ['factura_moneda_del_contrato', 'facturas_tope_cadena_y_recibi_pendiente', 'f2_b2_empresas']
FOTO = 'f2_foto_b2'
SALIDA = os.path.join(COPIA, 'contracts', 'sql', 'ensayo_2159_viva.sql')


def lee(rel):
    return open(os.path.join(COPIA, rel), encoding='utf-8', newline='').read()


def sha(t):
    return hashlib.sha256(t.encode('utf-8')).hexdigest()


def para(msg):
    sys.exit('PARA: ' + msg)


mig = lee(MIG)
if sha(mig) != MIG_SHA:
    para('la migración no es la sellada (%s)' % sha(mig))
textos = {p: lee('supabase/pruebas/%s.sql' % p) for p in PRUEBAS + [FOTO]}

# flujos: el bloque de flujos_lawang.py --sql SIN su begin; inicial, su select final de _arnes ni su rollback;
fl = subprocess.run([sys.executable, os.path.join(AGENCIA, 'tools', 'flujos_lawang.py'), '--sql'], capture_output=True,
                    text=True, encoding='utf-8', cwd=AGENCIA)
if fl.returncode != 0:
    para('flujos_lawang.py --sql falló: %s' % fl.stderr[-300:])
flujos_crudo = fl.stdout
flujos = re.sub(r'^\s*begin;\s*\n', '', flujos_crudo, count=1)
flujos, n1 = re.subn(r'\n\s*select caso, ok, detalle from _arnes order by caso;\s*\n\s*rollback;\s*$', '\n', flujos)
if n1 != 1:
    para('el final de flujos_lawang.py --sql no es el esperado (select de _arnes + rollback)')
textos['flujos'] = flujos

ETQ = {'ens': '$ens2159$', 'mig': '$mig2159$', 'fl': '$fl2159$'}
ETQ.update({p: '$p2159_%d$' % i for i, p in enumerate(PRUEBAS + [FOTO])})
ETQ.update({'q': '$q$', 'r': '$r$'})   # las del propio envoltorio (lectura de _arnes y pg_temp.e2159_resume)
for nombre, t in list(textos.items()) + [('migracion', mig)]:
    for e in ETQ.values():
        if e in t:
            para('la etiqueta %s aparece dentro de %s' % (e, nombre))
    sin_coment = re.sub(r'--[^\n]*', '', t)
    if re.search(r'(?im)^\s*(begin|commit|rollback|end)\s*;\s*$', re.sub(r'\$([a-z_0-9]*)\$.*?\$\1\$', '', sin_coment, flags=re.S)):
        para('%s trae un begin;/commit/rollback/end; de nivel superior' % nombre)


def seccion(nombre, etq, texto):
    return ("  -- %s (sha256 %s)\n"
            "  begin\n    execute %s%s%s;\n    v := 'sin raise final';\n"
            "  exception when others then v := sqlstate || ' ' || sqlerrm;\n  end;\n"
            "  res := res || E'\\n== %s\\n' || pg_temp.e2159_resume(v);\n") % (nombre, sha(texto)[:16], etq, texto, etq, nombre)


cuerpo = []
cuerpo.append("  -- 0 · foto de lo que ve cada usuario ANTES de la migración (misma transacción: no hay datos que cambien entre las dos)\n"
              "  begin execute %s%s%s; exception when others then antes := sqlstate || ' ' || sqlerrm; end;\n"
              % (ETQ[FOTO], textos[FOTO], ETQ[FOTO]))
cuerpo.append("  -- 1 · la migración, FUERA de sub-bloque: si su $antes$ o una guarda lanza, para todo (sha256 %s)\n"
              "  execute %s%s%s;\n" % (MIG_SHA[:16], ETQ['mig'], mig, ETQ['mig']))
for p in PRUEBAS:
    cuerpo.append(seccion(p, ETQ[p], textos[p]))
cuerpo.append("  -- 4 · la misma foto DESPUÉS\n"
              "  begin execute %s%s%s; exception when others then despues := sqlstate || ' ' || sqlerrm; end;\n"
              "  res := res || E'\\n== f2_foto_b2: ' || case when antes is null or despues is null then 'SIN FOTO (FALLA)'\n"
              "         when substring(antes from 'MD5=([0-9a-f]{32})') = substring(despues from 'MD5=([0-9a-f]{32})') then 'MD5 igual antes y despues → ok'\n"
              "         else 'MD5 DISTINTO antes/despues → FALLA' end;\n"
              % (ETQ[FOTO], textos[FOTO], ETQ[FOTO]))
cuerpo.append("  -- 5 · flujos críticos (tools/flujos_lawang.py --sql, sha256 %s): se leen las filas de _arnes antes de deshacer\n"
              "  begin\n    execute %s%s%s;\n"
              "    execute $q$select count(*) filter (where ok), count(*), coalesce(string_agg(caso || ' → FALLA ' || coalesce(detalle, ''), E'\\n' order by caso)\n"
              "                filter (where not ok), '') from _arnes$q$ into n_ok, n_tot, v;\n"
              "    res := res || E'\\n== flujos_lawang ' || n_ok || '/' || n_tot || case when n_ok = n_tot then ' → ok' else E'\\n' || v end;\n"
              "    raise exception 'deshaz_flujos';\n"
              "  exception when others then\n"
              "    if sqlerrm <> 'deshaz_flujos' then res := res || E'\\n== flujos_lawang: ' || pg_temp.e2159_resume(sqlstate || ' ' || sqlerrm); end if;\n"
              "  end;\n" % (sha(flujos)[:16], ETQ['fl'], flujos, ETQ['fl']))

cabecera = """-- destructivo-ok: ensayo deshecho de 20261014223000 en la viva; todo termina en raise (rollback), nada queda escrito
-- ENSAYO DE 2159 EN UNA LLAMADA (15-oct-2026, lawang-cola-2, generado por contracts/sql/genera_ensayo_2159.py; NO se edita a mano).
-- Qué hace, en UNA transacción que acaba en `raise exception 'RES 2159 …'` (se deshace todo):
--   0. f2_foto_b2 antes · 1. la migración 20261014223000 tal cual (sha256 %s) · 2. tres pruebas en sub-bloques que
--   capturan su resultado · 4. f2_foto_b2 después (mismo MD5 = la migración no cambia lo que ve nadie) · 5. flujos_lawang.
-- ESPERADO para aplicar (cualquier otra cosa = PARAR y pasar el RES entero a lawang-cola-2):
--   factura_moneda_del_contrato: ninguna línea con FALLA (b1 incluido) · facturas_tope_cadena_y_recibi_pendiente: resultados sin error
--   f2_b2_empresas: FALLOS=0 · f2_foto_b2: «MD5 igual antes y despues → ok» · flujos_lawang N/N → ok
--   Un 55P03 (lock_timeout) en cualquier sección = tabla ocupada: REINTENTAR más tarde, no es un fallo.
-- f2_foto_b2_ab NO va (decisión por defecto, revertible añadiéndola como sección): compara funciones de gastos contra una instantánea,
-- no guardar_recibi; el A/B de 2159 es la foto antes/después de la sección 0/4, en la misma transacción.
-- Huellas: migración %s · flujos %s · %s
""" % (MIG_SHA[:16], MIG_SHA, sha(flujos), ' · '.join('%s %s' % (p, sha(textos[p])[:16]) for p in PRUEBAS + [FOTO]))

resume = """create or replace function pg_temp.e2159_resume(t text) returns text language sql as $r$
  -- cuenta las líneas y deja solo las que no dicen ok (el RES entero de 140 KB lo corta el cliente)
  select (select count(*) from regexp_split_to_table(coalesce(t, ''), E'\\n') l where l ~ '(→ ok|: ok|\\mok\\M)')::text || ' ok · '
      || coalesce((select string_agg(l, E'\\n') from regexp_split_to_table(coalesce(t, ''), E'\\n') l
                    where l !~ '(→ ok|: ok|\\mok\\M)' and btrim(l) <> ''), '')
$r$;
"""

fichero = (cabecera + "select set_config('lock_timeout', '5s', true);\n" + resume
           + "do %s\ndeclare res text := ''; v text; antes text; despues text; n_ok int; n_tot int;\nbegin\n" % ETQ['ens']
           + ''.join(cuerpo)
           + "  raise exception E'RES 2159%%', res;\nend %s;\n" % ETQ['ens'])

# los textos van idénticos dentro del fichero
for nombre, t in list(textos.items()) + [('migracion', mig)]:
    if fichero.count(t) < 1:
        para('%s no está byte a byte dentro del fichero' % nombre)

import pglast  # noqa: E402
for nombre, t in list(textos.items()) + [('migracion', mig), ('fichero', fichero)]:
    try:
        pglast.parse_sql(t)
    except Exception as e:  # noqa: BLE001
        para('pglast no parsea %s: %s' % (nombre, str(e)[:200]))
open(SALIDA, 'w', encoding='utf-8', newline='\n').write(fichero)
print('OK %s · %d bytes · sha256 %s' % (SALIDA, len(fichero.encode('utf-8')), sha(fichero)))
print('flujos sha256 %s' % sha(flujos))
