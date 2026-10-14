#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Prueba de la VUELTA ATRAS de la migracion 20261014101500 «espejo_cliente_visible» (14-oct-2026, Backend).

SOLO EN RAMA: la llama erp/rama_prueba.py (de la agencia) con la rama de esa ejecucion y la migracion YA aplicada:

    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261014101500_espejo_cliente_visible.sql \
           --prueba espejo_cliente_visible.sql,espejo_vuelta.py

Por que es un .py y no un .sql: `--aplica` solo busca en supabase/migrations y corre ANTES de las pruebas, asi que la reversion
(supabase/reversion_espejo_cliente_visible/) no se puede nombrar ahi; y un .sql tendria que llevar una COPIA de la reversion, con lo
que se probaria la copia y no el fichero que se ejecutaria de verdad. Este modulo LEE el fichero real y lo ejecuta, en una sola
transaccion que termina en raise (rollback): la rama se queda con la migracion aplicada, como estaba.

Que afirma (una linea «→ ok» / «→ FALLA» cada una), para las 7 funciones que toca la migracion:
  - que la migracion estaba aplicada (su texto no era el del vivo): si no, la reversion no probaria nada;
  - que tras la reversion md5(pg_get_functiondef) es EL DEL VIVO SIN MIGRAR. Los md5 de abajo se leyeron del catalogo vivo de Lawang
    el 14-oct-2026 (solo lectura; Postgres 17.6, cuerpos en LF). Si alguien cambia una de esas funciones en el vivo despues de esa
    fecha, el md5 de aqui queda viejo: se vuelve a leer, no se «arregla» la reversion;
  - que los permisos quedan como en el vivo, rol por rol (no comparando proacl: revoke + grant lo reordena);
y ademas que el trigger de tipo vuelve a saltar solo en INSERT, que las 3 funciones nuevas ya no existen y que el espejo responde.
No toca datos. No necesita filas (la rama no trae ninguna).

MEDIDO en rama el 14-oct-2026 11:04-11:08 (estructura del volcado lawang_20261014_0931, migracion aplicada, rama borrada): 20/20.
Lo que NO prueba: la reversion sobre una base con contratos guardados mientras la migracion estuvo aplicada (no toca datos, pero
aqui no hay ninguno), ni volver a aplicar la migracion despues de revertir.
"""
import os
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
REVERSION = os.path.normpath(os.path.join(AQUI, '..', 'reversion_espejo_cliente_visible', 'REVERSION_espejo_cliente_visible.sql'))

# (funcion, md5 de pg_get_functiondef en el vivo SIN la migracion, authenticated tiene EXECUTE en el vivo)
# Leidos el 14-oct-2026; anon y public sin EXECUTE y service_role con EXECUTE en las siete.
VIVO = [
    ('public.espeja_comprador(jsonb)',        'cc92681173d7d1d32211f7b3c3d277ff', False),
    ('public.sincronizar_compradores(uuid)',  '5d728f296ae1668fea3eedeca38129d2', False),
    ('public.contratos_tipo_permitido()',     '62b3e49068ea2432e5297b3864cf9481', True),
    ('public.contrato_guarda(uuid,jsonb)',    '0e498f541c55d71651882c6866caaac7', True),
    ('public.comprador_ficha(uuid)',          '509282e58c3f2c22aec3af25bfdac67c', True),
    ('public.trg_espejo_comprador()',         'bbe93a24dd78b50f42e8f1ebb34c0ecb', False),
    ('public.trg_cliente_actualizado()',      'dafee300019a9954d0ce507c8dd4bf8a', False),
]

ANTES = r"""-- Prueba de la vuelta atras de espejo_cliente_visible (montada por espejo_vuelta.py): foto de ANTES, la reversion REAL y las comprobaciones.
-- destructivo-ok: ejecuta la reversion (reemplaza funciones y borra las 2 nuevas) en una transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(coalesce(t, '(texto nulo)'), E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create temp table _vf as
  select t.f, t.md5_vivo, t.authenticated_x, md5(pg_get_functiondef(t.f::regprocedure)) as md5_migrada
    from (values %s) as t(f, md5_vivo, authenticated_x);
do $guardia$ begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS VUELTA ATRAS ESPEJO:%%', E'\nV0 esta prueba ejecuta DDL (la reversion): solo corre en rama → FALLA';
  end if;
end $guardia$;
-- ============================================================ AQUI VA, TAL CUAL, supabase/reversion_espejo_cliente_visible/REVERSION_espejo_cliente_visible.sql
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
  select pg_get_triggerdef(t.oid) into d from pg_trigger t
   where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_tipo_permitido' and t.tgenabled = 'O';
  r := r || pg_temp.l(d ~ 'BEFORE INSERT ON public\.contratos FOR EACH ROW' and d !~ 'UPDATE',
         'V4 el trigger de tipo vuelve a saltar solo en INSERT (' || coalesce(d, 'no existe o esta apagado') || ')');
  r := r || pg_temp.l(to_regprocedure('public._cliente_ficha_visible(uuid)') is null and to_regprocedure('public._contrato_clientes_comprueba(uuid,jsonb)') is null
                      and to_regprocedure('public._espejo_autor_ve(uuid,text)') is null,
         'V5 las 3 funciones que creo la migracion ya no existen');
  r := r || pg_temp.l((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and (p.prosrc ~ '_cliente_ficha_visible' or p.prosrc ~ '_contrato_clientes_comprueba' or p.prosrc ~ '_espejo_autor_ve')) = 0,
         'V6 ninguna funcion de public las nombra ya (no queda una llamada colgando)');
  r := r || pg_temp.l(public.espeja_comprador('{"fields": {"adq1_nombre": "ZZ-VUELTA"}}'::jsonb) = '{"fields": {"adq1_nombre": "ZZ-VUELTA"}}'::jsonb,
         'V7 el espejo restaurado responde (sin ficha devuelve los datos tal cual)');
  raise exception 'FIN DE PRUEBAS VUELTA ATRAS ESPEJO (se deshace todo; la rama sigue con la migracion aplicada):%%', r;
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
        return ['V0 espejo_vuelta.py: %s: %s → FALLA' % (type(e).__name__, str(e)[:400])]
