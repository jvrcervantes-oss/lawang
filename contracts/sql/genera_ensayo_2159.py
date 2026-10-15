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
# Series de documentos (LAW-217): las mismas que mide prueba_comisiones_1nov.sql y las tres de set_factura_numero (20260917082716:59-61)
SERIES = ['facturas_seq', 'facturas_recibi_seq', 'facturas_proforma_seq', 'solicitudes_pago_numero_seq', 'comisiones_diferencias_seq']
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
ETQ.update({'q': '$q$', 'r': '$r$', 'num': '$num2159$', 'nf': '$nf$'})   # las del propio envoltorio
for nombre, t in list(textos.items()) + [('migracion', mig)]:
    for e in ETQ.values():
        if e in t:
            para('la etiqueta %s aparece dentro de %s' % (e, nombre))
    sin_coment = re.sub(r'--[^\n]*', '', t)
    if re.search(r'(?im)^\s*(begin|commit|rollback|end)\s*;\s*$', re.sub(r'\$([a-z_0-9]*)\$.*?\$\1\$', '', sin_coment, flags=re.S)):
        para('%s trae un begin;/commit/rollback/end; de nivel superior' % nombre)


# Numeración propia (revisor de dff7e40ef, 15-oct): un alta sin número dispara nextval de la serie fiscal en trg_set_factura_numero y
# un rollback no devuelve el número. Este trigger corre ANTES (nombre «trg_00_» < «trg_00a_» < «trg_set_»: los BEFORE van por orden
# alfabético) y pone un número de prueba. Va DENTRO de cada sub-bloque: se deshace con él y el bloqueo de public.facturas se suelta al
# abortarlo, en vez de durar toda la llamada. Mismo truco que tools/flujos_lawang.py y factura_moneda_del_contrato.sql.
# Y el motor de comisiones apagado en el mismo sub-bloque (revisor de 9a839d3ce, 15-oct): un recibí o un alta sobre un contrato real
# dispara comisiones_evaluar_contrato (triggers de recibi_aplicaciones y facturas), que puede insertar una solicitud de pago (serie SP,
# identity) o, vía _comision_devengo_reponer, una diferencia (serie DIF, default con nextval): el número se toma al formar la fila,
# antes de cualquier BEFORE, así que el trigger de numeración no lo evita. Es el único camino desde estas altas (comisiones_reconciliar,
# el otro que crea SP/DIF, solo lo llama una migración puntual). El create or replace se deshace con el sub-bloque: las demás sesiones
# siguen viendo la versión buena porque nunca se confirma. Ninguna de las tres pruebas mide devengos nuevos (f2_b2 resuelve solicitudes
# que ya existen). La sección 6 queda como red de seguridad.
NUM = ("    execute $num2159$create function public.zz_e2159_num() returns trigger language plpgsql as $nf$ begin\n"
       "      if new.numero is null then new.numero := 'ZZ-E2159-' || left(gen_random_uuid()::text, 8); end if; return new; end $nf$;\n"
       "      create trigger trg_00_zz_e2159_num before insert on public.facturas for each row execute function public.zz_e2159_num();\n"
       "      create or replace function public.comisiones_evaluar_contrato(p_contrato_id uuid) returns integer language plpgsql\n"
       "        as $nf$ begin return 0; end $nf$$num2159$;\n")


def seccion(nombre, etq, texto):
    return ("  -- %s (sha256 %s)\n"
            "  begin\n%s    execute %s%s%s;\n    v := 'sin raise final (FALLA)';\n"
            "  exception when others then v := sqlstate || ' ' || sqlerrm;\n  end;\n"
            "  res := res || E'\\n== %s\\n' || pg_temp.e2159_resume(v);\n") % (nombre, sha(texto)[:16], NUM, etq, texto, etq, nombre)


def foto(destino):
    return ("  begin\n%s    execute %s%s%s;\n    %s := 'sin raise final';\n"
            "  exception when others then %s := sqlstate || ' ' || sqlerrm;\n  end;\n"
            % (NUM, ETQ[FOTO], textos[FOTO], ETQ[FOTO], destino, destino))


cuerpo = []
cuerpo.append("  perform set_config('lock_timeout', '5s', true);\n"
              "  -- series: foto de TODAS las secuencias de public antes de nada (se compara al final)\n"
              "  select coalesce(jsonb_object_agg(sequencename, last_value), '{}') into seq0 from pg_sequences where schemaname = 'public';\n")
cuerpo.append("  -- 0 · foto de lo que ve cada usuario ANTES de la migración\n" + foto('antes'))
cuerpo.append("  -- 1 · la migración, FUERA de sub-bloque: si su $antes$ o una guarda lanza, para todo (sha256 %s)\n"
              "  execute %s%s%s;\n" % (MIG_SHA[:16], ETQ['mig'], mig, ETQ['mig']))
for p in PRUEBAS:
    cuerpo.append(seccion(p, ETQ[p], textos[p]))
cuerpo.append("  -- 4 · la misma foto DESPUÉS\n" + foto('despues') +
              "  res := res || E'\\n== f2_foto_b2: ' || case\n"
              "         when substring(antes from 'MD5=([0-9a-f]{32})') is null or substring(despues from 'MD5=([0-9a-f]{32})') is null\n"
              "           then 'SIN FOTO (FALLA) · antes: ' || left(coalesce(antes, '-'), 160) || ' · despues: ' || left(coalesce(despues, '-'), 160)\n"
              "         when substring(antes from 'MD5=([0-9a-f]{32})') = substring(despues from 'MD5=([0-9a-f]{32})') then 'MD5 igual antes y despues → ok'\n"
              "         else 'MD5 DISTINTO antes/despues (FALLA salvo dato real cambiado entre las dos: repetir una vez)' end;\n")
cuerpo.append("  -- 5 · flujos críticos (tools/flujos_lawang.py --sql, sha256 %s): se leen las filas de _arnes antes de deshacer\n"
              "  begin\n    execute %s%s%s;\n"
              "    execute $q$select count(*) filter (where ok), count(*), coalesce(string_agg(caso || ' → FALLA ' || coalesce(detalle, ''), E'\\n' order by caso)\n"
              "                filter (where not ok), '') from _arnes$q$ into n_ok, n_tot, v;\n"
              "    res := res || E'\\n== flujos_lawang ' || n_ok || '/' || n_tot || case when n_tot > 0 and n_ok = n_tot then ' → ok'\n"
              "                                                                     when n_tot = 0 then ' → FALLA (ningún caso)' else E'\\n' || v end;\n"
              "    raise exception 'deshaz_flujos';\n"
              "  exception when others then\n"
              "    if sqlerrm <> 'deshaz_flujos' then res := res || E'\\n== flujos_lawang: ' || pg_temp.e2159_resume(sqlstate || ' ' || sqlerrm); end if;\n"
              "  end;\n" % (sha(flujos)[:16], ETQ['fl'], flujos, ETQ['fl']))
cuerpo.append("  -- 6 · series: ninguna secuencia de documentos puede haberse movido\n"
              "  select coalesce(jsonb_object_agg(sequencename, last_value), '{}') into seq1 from pg_sequences where schemaname = 'public';\n"
              "  select string_agg(a.key || ' ' || coalesce(a.value, 'null') || '→' || coalesce(b.value, 'null')\n"
              "                    || case when a.key in (%s) then ' SERIE FISCAL MOVIDA (FALLA)'\n"
              "                            when a.key ~ '^(contratos_.*_seq|clients_numero_cliente_seq)$' then ' serie visible no fiscal (apuntar)'\n"
              "                            else ' (id interno)' end, E'\\n' order by a.key)\n"
              "    into v from jsonb_each_text(seq0) a join jsonb_each_text(seq1) b using (key) where a.value is distinct from b.value;\n"
              "  res := res || E'\\n== series: ' || coalesce(E'\\n' || v, 'ninguna secuencia movida → ok');\n"
              % ', '.join("'%s'" % s for s in SERIES))

cabecera = """-- destructivo-ok: ensayo deshecho de 20261014223000 en la viva; todo termina en raise (rollback) y no gasta números de serie fiscales (INV, REC, PRO, SP, DIF)
-- ENSAYO DE 2159 EN UNA LLAMADA (15-oct-2026, lawang-cola-2, generado por contracts/sql/genera_ensayo_2159.py; NO se edita a mano).
-- Qué hace, en UNA transacción que acaba en `raise exception 'RES 2159 …'` (se deshace todo):
--   foto de las secuencias de public · 0. f2_foto_b2 antes · 1. la migración 20261014223000 tal cual (sha256 %s) · 2. tres pruebas
--   en sub-bloques que capturan su resultado · 4. f2_foto_b2 después · 5. flujos_lawang · 6. secuencias otra vez.
-- Cada sub-bloque pone su trigger de numeración (trg_00_zz_e2159_num, antes de trg_set_factura_numero) y apaga el motor de comisiones
-- (comisiones_evaluar_contrato devuelve 0 sin crear nada): ningún alta toca INV/REC/PRO ni crea solicitudes SP o diferencias DIF.
-- Se lanza en un momento tranquilo: f2_b2_empresas bloquea filas reales de usuarios mientras dura la llamada.
--
-- APLICAR solo si el RES dice TODO esto (cualquier otra cosa = PARAR y pasar el RES entero a lawang-cola-2):
--   == factura_moneda_del_contrato: ninguna línea empieza por «MAL» ni dice «ERR», las del canario C0 incluidas (el
--      resumen solo imprime lo que no es bueno: un C0 correcto se cuenta y NO sale); «PENDIENTE» solo en g3, g4,
--      g5 y h1 (cualquier otro PENDIENTE = PARAR).
--   == facturas_tope_cadena_y_recibi_pendiente: ninguna línea con «PASO (MAL)»; ninguna línea «RECIBI pend» con MAL o ERR (la buena,
--      «RECIBI pend: ok», se cuenta y no se imprime; si «pendiente INV00184=0» la prueba no aplica). Las tres negativas del recibí (pend+500, 0, «1 sobre cobrada») tienen que decir «bloqueado», con cualquier
--      motivo: con 2159 las para la suma del recibí antes que la regla que nombran, así que el MOTIVO aquí no se prueba.
--      Las líneas de facturas (ALTA, RP00106, otra moneda, proforma, SALDO) y la de privilegios son de la migración del 5-oct, no de
--      2159, y montan sobre datos de ese día: un «ERR» en ellas no frena 2159, se apunta y se pasa a lawang-cola-2.
--   == f2_b2_empresas: «FALLOS=0».
--   == f2_foto_b2: «MD5 igual antes y despues → ok». Si sale DISTINTO, repetir la llamada UNA vez (en READ COMMITTED cada sentencia ve
--      su propia instantánea: un cambio real de otro usuario entre las dos fotos lo da); DISTINTO otra vez = PARAR.
--   == flujos_lawang N/N → ok, con N > 0.
--   == series: «ninguna secuencia movida → ok», o solo líneas «(id interno)» o «serie visible no
--      fiscal (apuntar)» (número de contrato o de cliente: flujos da de alta un cliente por pasada; deja un hueco, no frena). Una «SERIE FISCAL MOVIDA» = PARAR y avisar YA: el
--      ensayo gastó números (o entró un documento real a la vez: mirar si existe el número siguiente en facturas / solicitudes_pago).
--   Un 55P03 (lock_timeout) en cualquier sección = tabla ocupada: REINTENTAR más tarde, no es un fallo.
-- f2_foto_b2_ab NO va (decisión por defecto, revertible añadiéndola como sección): compara funciones de gastos contra una instantánea,
-- no guardar_recibi; el A/B de 2159 es la foto antes/después de las secciones 0 y 4.
-- Huellas: migración %s · flujos %s · %s
""" % (MIG_SHA[:16], MIG_SHA, sha(flujos), ' · '.join('%s %s' % (p, sha(textos[p])[:16]) for p in PRUEBAS + [FOTO]))

resume = """create or replace function pg_temp.e2159_resume(t text) returns text language sql as $r$
  -- cuenta las líneas buenas y deja TODAS las demás (el RES entero de 140 KB lo corta el cliente). Una línea con FALLA, FALLO, MAL,
  -- ERR o «PASO (MAL)» nunca se cuenta como buena aunque también diga ok (revisor de dff7e40ef: «FALLO … (esperado ok)» se perdía).
  with l as (select x from regexp_split_to_table(coalesce(t, ''), E'\\n') x where btrim(x) <> ''),
       c as (select x, x ~ '(FALLA|FALLO|\\mMAL\\M|\\mERR\\M|PASO \\(MAL\\)|PENDIENTE)' as mala, x ~* '(→ ok|: ok|\\mok\\M)' as buena from l)
  select (select count(*) from c where buena and not mala)::text || ' ok · '
      || coalesce((select string_agg(x, E'\\n') from c where mala or not buena), '')
$r$;
"""

fichero = (cabecera + resume
           + "do %s\ndeclare res text := ''; v text; antes text; despues text; n_ok int; n_tot int; seq0 jsonb; seq1 jsonb;\nbegin\n" % ETQ['ens']
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
