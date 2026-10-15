#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Prueba de la VUELTA ATRAS de la migracion 20261014210000 «cf_borrar_cierre_anula_solo_admin» (14-oct-2026, Backend, bloque B).

SOLO EN RAMA: la llama erp/rama_prueba.py (de la agencia) con la rama de esa ejecucion y la migracion YA aplicada:

    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261014210000_cf_borrar_cierre_anula_solo_admin.sql \
           --prueba cf_borrar_cierre_anula.sql,cf_vuelta.py

Calcada de espejo_vuelta.py (mismo porque): `--aplica` solo busca en supabase/migrations, y un .sql tendria que llevar una COPIA de la
reversion, con lo que se probaria la copia y no el fichero que se ejecutaria de verdad. Este modulo LEE el fichero real
(supabase/reversion_cf_borrar_cierre_anula/REVERSION.sql) y lo ejecuta en una transaccion que termina en raise (rollback): la rama se
queda con la migracion aplicada, como estaba.

Que afirma, para las 3 funciones: que la migracion estaba aplicada (su texto no era el del vivo); que tras la reversion
md5(pg_get_functiondef) es EL DEL VIVO SIN MIGRAR (leido del catalogo vivo de Lawang el 14-oct-2026, solo lectura, cuerpos en LF; si
alguien cambia una de esas funciones en el vivo despues, el md5 de aqui queda viejo: se vuelve a leer, no se «arregla» la reversion);
y que los permisos quedan como en el vivo, rol por rol. Ademas, que ya no queda ninguna de las marcas del arreglo. No toca datos.
"""
import os
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
REVERSION = os.path.normpath(os.path.join(AQUI, '..', 'reversion_cf_borrar_cierre_anula', 'REVERSION.sql'))

# (funcion, md5 de pg_get_functiondef en el vivo SIN la migracion, authenticated tiene EXECUTE en el vivo)
# Leidos el 14-oct-2026; anon y public sin EXECUTE y service_role con EXECUTE en las tres.
VIVO = [
    ('public.borrar_operacion(uuid)',                '3b410ba14fd7280ae5699df39640c126', True),
    ('public.agente_escribe_fichero_contrato(text)', 'c7f561a699d8bb464c50132bf6546101', True),
    ('public.factura_anula(uuid)',                   '56a267446fea46f99b941a299806c8ba', True),
]

ANTES = r"""-- Prueba de la vuelta atras de cf_borrar_cierre_anula (montada por cf_vuelta.py): foto de ANTES, la reversion REAL y las comprobaciones.
-- destructivo-ok: ejecuta la reversion (reemplaza tres funciones) en una transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(coalesce(t, '(texto nulo)'), E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create temp table _vf as
  select t.f, t.md5_vivo, t.authenticated_x, md5(pg_get_functiondef(t.f::regprocedure)) as md5_migrada
    from (values %s) as t(f, md5_vivo, authenticated_x);
do $guardia$ begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS VUELTA ATRAS CF:%%', E'\nV0 esta prueba ejecuta DDL (la reversion): solo corre en rama → FALLA';
  end if;
end $guardia$;
-- ============================================================ AQUI VA, TAL CUAL, supabase/reversion_cf_borrar_cierre_anula/REVERSION.sql
"""

DESPUES = r"""
-- ============================================================ FIN de la reversion real; comprobaciones
do $comprueba$
declare r text := ''; x record; o oid; m text; d text; au boolean;
begin
  for x in select * from _vf order by f loop
    o := x.f::regprocedure;
    d := pg_get_functiondef(o);
    m := md5(d);
    r := r || pg_temp.l(x.md5_migrada <> x.md5_vivo, 'V1 ' || x.f || ': la migracion estaba aplicada (su texto no era el del vivo)');
    r := r || pg_temp.l(m = x.md5_vivo, 'V2 ' || x.f || ': tras la reversion tiene el texto del vivo sin migrar (md5 ' || m || ', esperado ' || x.md5_vivo
           || '; largo ' || length(d) || '; con retorno de carro: ' || (position(E'\r' in d) > 0)::text || ')');
    au := has_function_privilege('authenticated', o, 'execute');
    r := r || pg_temp.l(au = x.authenticated_x and not has_function_privilege('anon', o, 'execute') and not has_function_privilege('public', o, 'execute')
                        and has_function_privilege('service_role', o, 'execute'),
           'V3 ' || x.f || ': permisos como en el vivo (authenticated ' || au::text || ', esperado ' || x.authenticated_x::text || '; anon y public no; service_role si)');
  end loop;
  r := r || pg_temp.l((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and (p.prosrc ~ 'solo la puede borrar un administrador de su empresa'
                             or p.prosrc ~ 'es_admin_de\(public\._empresa_doc\(null, c\.id\)\)'
                             or p.prosrc ~ 'v_chk\.anulada := false')) = 0,
         'V4 ninguna funcion de public lleva ya las marcas del arreglo');
  raise exception 'FIN DE PRUEBAS VUELTA ATRAS CF (se deshace todo; la rama sigue con la migracion aplicada):%%', r;
end $comprueba$;
"""


def _ejecuta(rama, texto):
    """Por fichero UTF-8 (como argumento, psql en Windows manda las tildes en cp1252)."""
    t = tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False, encoding='utf-8', newline='\n')
    t.write(texto)
    t.close()
    try:
        return rama.psql(fichero=t.name)
    finally:
        os.unlink(t.name)


def corre(rama, di):
    """Interfaz de erp/rama_prueba.py para las pruebas .py: devuelve las lineas «… → ok» / «… → FALLA»."""
    try:
        import corre as C   # el armazon de erp/pruebas/corre.py (rama_prueba ya lo tiene en su sys.path)
        if not os.path.isfile(REVERSION):
            return ['V0 no existe el fichero de la reversion (%s) → FALLA' % os.path.basename(REVERSION)]
        reversion = open(REVERSION, encoding='utf-8', newline='').read()
        valores = ',\n                 '.join("('%s', '%s', %s)" % (f, m, 'true' if a else 'false') for f, m, a in VIVO)
        texto = (ANTES % valores) + reversion + (DESPUES % ())
        t = tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False, encoding='utf-8', newline='\n')
        t.write(texto)
        t.close()
        try:
            # mismo armazon y mismo criterio que una prueba .sql: transaccion, erp.en_rama, «FIN DE PRUEBAS» y rollback
            lineas, error = C.corre('lawang', t.name, '', False, None, None, ejecuta=lambda x: _ejecuta(rama, x), en_rama=True)
        finally:
            os.unlink(t.name)
        if error:
            return ['V0 la reversion real se ejecuta entera en la rama: %s → FALLA' % ' | '.join(error)[:600]]
        di('reversion ejecutada desde %s (%d bytes, con retorno de carro: %s) y deshecha' % (
            os.path.basename(REVERSION), len(reversion.encode('utf-8')), '\r' in reversion))
        return ['V0 la reversion real se ejecuta entera en la rama, sin error → ok'] + lineas
    except Exception as e:   # un fallo de este modulo no tumba el arnes ni se calla: sale como aserción en rojo
        return ['V0 cf_vuelta.py: %s: %s → FALLA' % (type(e).__name__, str(e)[:400])]
