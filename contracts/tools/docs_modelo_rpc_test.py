#!/usr/bin/env python3
"""Pruebas de la casilla «Se incluye automáticamente en el contrato» (modelo_documentos.en_contrato / orden,
tipo 'dosier') contra la base REAL, dentro de UNA transacción que termina SIEMPRE en ROLLBACK. Mismo patrón que
contracts/tools/anexos_rpc_test.py (LAW-78): este script no se conecta; imprime un bloque SQL que se pega en
`mcp__supabase-lawang__execute_sql` (o en el SQL Editor).

    python contracts/tools/docs_modelo_rpc_test.py                 # con la migración ya aplicada
    python contracts/tools/docs_modelo_rpc_test.py --con-migracion # antepone la migración (probar ANTES de aplicarla)
    python contracts/tools/docs_modelo_rpc_test.py --selftest      # añade un caso que DEBE salir en rojo

Cada caso corre con el ROL REAL (`set local role authenticated` + claims): el MCP corre como `postgres`. El
canario A0 comprueba que el cambio de rol surtió efecto. Identidades y modelo se resuelven DESDE LA BASE (el repo
es público: aquí no hay ni un uid ni un email). Los documentos y objetos de prueba se crean dentro de la
transacción y mueren en el ROLLBACK. Salida: (caso, ok, detalle) sin PII. Cualquier ok=false es una regresión.

B1/B2 (backfill) solo tienen sentido con --con-migracion: comparan, por modelo y techo, lo que adjuntaba la regla
VIEJA (el plano del techo o, si no hay, el genérico) con lo que adjunta la NUEVA (marcados del techo + sin techo).
"""
import os
import sys

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MIGRACION = os.path.join(RAIZ, 'supabase', 'migrations', '20260927230000_modelo_documentos_en_contrato_dosier.sql')

# La regla VIEJA, calculada ANTES de la migración (por modelo y techo, '' = sin techo).
FOTO_VIEJA = r"""
create temporary table _vieja on commit drop as
select m.id as modelo_id, t.clave as techo,
       coalesce((select d.id from public.modelo_documentos d where d.modelo_id = m.id and d.tipo = 'plano' and d.techo_clave = t.clave
                  order by d.subido_en desc limit 1),
                (select d.id from public.modelo_documentos d where d.modelo_id = m.id and d.tipo = 'plano' and d.techo_clave is null
                  order by d.subido_en desc limit 1)) as doc
  from public.modelos m
  cross join lateral (select x.clave from public.modelo_techos x where x.modelo_id = m.id union all select '') t;
"""

MONTAJE = r"""
select set_config('t.admin_sub', u.user_id::text, true), set_config('t.admin_email', lower(u.email), true)
  from public.usuarios u where u.activo and u.rol in ('admin', 'super_admin') order by (u.rol = 'admin') desc, u.creado_en limit 1;
select set_config('t.agente_sub', u.user_id::text, true), set_config('t.agente_email', lower(u.email), true)
  from public.usuarios u where u.activo and u.rol = 'agente' order by u.creado_en limit 1;
-- un modelo con al menos dos techos
select set_config('t.m', x.modelo_id::text, true), set_config('t.t1', x.c1, true), set_config('t.t2', x.c2, true)
  from (select modelo_id, min(clave) c1, max(clave) c2 from public.modelo_techos group by modelo_id having count(*) >= 2
         order by modelo_id limit 1) x;
-- documentos de prueba (mueren en el rollback): uno de cada, sin marcar, y dos planos marcados sin techo repetido
delete from public.modelo_documentos where modelo_id = current_setting('t.m')::uuid;   -- el modelo empieza limpio DENTRO de la transacción
insert into public.modelo_documentos (id, modelo_id, nombre, path, tipo, techo_clave, en_contrato, orden, subido_en) values
  ('a0000000-0000-4000-8000-000000000001', current_setting('t.m')::uuid, 'otro', current_setting('t.m') || '/a0000000-0000-4000-8000-000000000001.pdf', 'otro', null, false, 0, now() - interval '5 days'),
  ('a0000000-0000-4000-8000-000000000002', current_setting('t.m')::uuid, 'plano t1', current_setting('t.m') || '/a0000000-0000-4000-8000-000000000002.pdf', 'plano', current_setting('t.t1'), true, 1, now() - interval '4 days'),
  ('a0000000-0000-4000-8000-000000000003', current_setting('t.m')::uuid, 'plano t2', current_setting('t.m') || '/a0000000-0000-4000-8000-000000000003.pdf', 'plano', current_setting('t.t2'), true, 2, now() - interval '3 days'),
  ('a0000000-0000-4000-8000-000000000004', current_setting('t.m')::uuid, 'dosier', current_setting('t.m') || '/a0000000-0000-4000-8000-000000000004.pdf', 'dosier', null, false, 0, now() - interval '2 days'),
  ('a0000000-0000-4000-8000-000000000005', current_setting('t.m')::uuid, 'plano libre', current_setting('t.m') || '/a0000000-0000-4000-8000-000000000005.pdf', 'plano', null, false, 0, now() - interval '1 days');
insert into storage.objects (bucket_id, name, metadata) values
  ('modelos', current_setting('t.m') || '/b0000000-0000-4000-8000-000000000001.pdf', '{"size": 1000}'),
  ('modelos', current_setting('t.m') || '/b0000000-0000-4000-8000-000000000002.pdf', '{"size": 1000}'),
  ('modelos', current_setting('t.m') || '/b0000000-0000-4000-8000-000000000003.pdf', '{"size": 1000}'),
  ('modelos', current_setting('t.m') || '/b0000000-0000-4000-8000-000000000004.pdf', '{"size": 1000}'),
  ('modelos', current_setting('t.m') || '/b0000000-0000-4000-8000-000000000005.pdf', '{"size": 1000}');
"""


def claims(p):
    return ("select set_config('request.jwt.claim.sub', current_setting('t.%(p)s_sub'), true),\n"
            "       set_config('request.jwt.claim.email', current_setting('t.%(p)s_email'), true),\n"
            "       set_config('request.jwt.claims', json_build_object('sub', current_setting('t.%(p)s_sub'),\n"
            "         'email', current_setting('t.%(p)s_email'), 'role', 'authenticated')::text, true);\n"
            "set local role authenticated;\n" % {'p': p})


def caso(nombre, llamada, espera, verifica='true'):
    """`llamada` es una expresión SQL; espera 'ok' (y entonces `verifica` tiene que ser cierto) o un sqlstate."""
    if espera == 'ok':
        return ("do $$ begin perform %s;\n"
                "  insert into _t values ('%s', %s, 'hecho');\n"
                "exception when others then insert into _t values ('%s', false, sqlstate || ' ' || left(sqlerrm, 90)); end $$;"
                % (llamada, nombre, verifica, nombre))
    return ("do $$ begin perform %s;\n"
            "  insert into _t values ('%s', false, 'no paro');\n"
            "exception when others then insert into _t values ('%s', sqlstate = '%s', sqlstate || ' ' || left(sqlerrm, 90)); end $$;"
            % (llamada, nombre, nombre, espera))


def cambia(doc, cambios):
    return "public.modelo_documento_cambia('a0000000-0000-4000-8000-00000000000%d'::uuid, '%s'::jsonb)" % (doc, cambios)


def doc(n, campo):
    return "(select %s from public.modelo_documentos where id = 'a0000000-0000-4000-8000-00000000000%d')" % (campo, n)


def registra(uid, obj, tipo, techo='null', en=None):
    extra = '' if en is None else ', p_en_contrato => %s' % en
    return ("public.modelo_documento_registra(p_uid => current_setting('t.%s_sub')::uuid, p_modelo => current_setting('t.m')::uuid, "
            "p_path => current_setting('t.m') || '/b0000000-0000-4000-8000-00000000000%d.pdf', p_nombre => 'prueba', p_tipo => '%s', "
            "p_techo_clave => %s%s)" % (uid, obj, tipo, techo, extra))


def sql(con_migracion=False, selftest=False):
    p = ['begin;', '-- destructivo-ok: pruebas de la casilla en_contrato (contracts/tools/docs_modelo_rpc_test.py); TODO acaba en ROLLBACK']
    if con_migracion:
        p.append(FOTO_VIEJA.strip())
        with open(MIGRACION, encoding='utf-8') as f:
            p.append(f.read())
    p += ['create temporary table _t(caso text, ok boolean, detalle text) on commit drop;',
          'grant all on _t to authenticated, anon, service_role;']
    if con_migracion:
        # B1: con la regla nueva sale EXACTAMENTE lo que salía con la vieja, en todos los modelos y techos.
        p.append(r"""
insert into _t
select 'B1 backfill: por modelo y techo entra lo mismo que antes', count(*) = 0, count(*)::text || ' combinaciones distintas'
  from _vieja v
 where array(select d.id from public.modelo_documentos d where d.modelo_id = v.modelo_id and d.en_contrato
              and (d.techo_clave is null or d.techo_clave = nullif(v.techo, '')) order by d.orden, d.subido_en, d.id)
       is distinct from (case when v.doc is null then array[]::uuid[] else array[v.doc] end);
insert into _t
select 'B2 backfill: marcados = planos, y nada que no sea plano', bool_and(en_contrato = (tipo = 'plano')), count(*)::text || ' documentos'
  from public.modelo_documentos;""".strip())
    p.append(MONTAJE.strip())

    # ── agente (no admin) ──
    p.append(claims('agente'))
    p.append("insert into _t values ('A0 canario: rol, claims y agente no admin', current_user = 'authenticated' and auth.uid() is not null "
             "and public.es_agente() and not public.es_admin(), 'current_user=' || current_user);")
    p.append(caso('C01 agente marca un documento para el contrato: 42501', cambia(1, '{"en_contrato": true}'), '42501'))
    p.append(caso('C02 agente cambia el tipo de uno marcado (plano): 42501', cambia(2, '{"tipo": "otro"}'), '42501'))
    p.append(caso('C03 agente desmarca uno marcado: 42501', cambia(2, '{"en_contrato": false}'), '42501'))
    p.append(caso('C04 agente cambia el orden: 42501', cambia(1, '{"orden": 7}'), '42501'))
    p.append(caso('C05 agente retipa uno NO marcado (otro -> dosier): ok', cambia(1, '{"tipo": "dosier"}'), 'ok',
                  "%s = 'dosier' and not %s" % (doc(1, 'tipo'), doc(1, 'en_contrato'))))
    p.append(caso('C06 agente convierte algo en plano (regla del 25-sep, se conserva): 42501', cambia(1, '{"tipo": "plano"}'), '42501'))
    p.append(caso('C07 agente cambia el techo de uno NO marcado: ok',
                  "public.modelo_documento_cambia('a0000000-0000-4000-8000-000000000004'::uuid, jsonb_build_object('techo_clave', current_setting('t.t1')))",
                  'ok', "%s = current_setting('t.t1')" % doc(4, 'techo_clave')))
    p.append(caso('R01 el navegador no llama a registra: 42501', registra('agente', 1, 'otro'), '42501'))
    p.append('reset role;')

    # ── admin ──
    p.append(claims('admin'))
    p.append("insert into _t values ('A1 canario admin', current_user = 'authenticated' and public.es_admin(), 'current_user=' || current_user);")
    p.append(caso('C10 admin marca el dosier sin orden: entra el ultimo (max+1 = 3)', cambia(4, '{"en_contrato": true}'), 'ok',
                  "%s and %s = 3" % (doc(4, 'en_contrato'), doc(4, 'orden'))))
    p.append(caso('C11 admin reordena uno marcado', cambia(4, '{"orden": 0}'), 'ok', "%s = 0" % doc(4, 'orden')))
    p.append(caso('C12 admin marca un 2o plano del MISMO techo: 23505',
                  "public.modelo_documento_cambia('a0000000-0000-4000-8000-000000000005'::uuid, jsonb_build_object('en_contrato', true, 'techo_clave', current_setting('t.t1')))",
                  '23505'))
    p.append(caso('C13 admin pasa un plano marcado al techo del otro plano marcado: 23505',
                  "public.modelo_documento_cambia('a0000000-0000-4000-8000-000000000003'::uuid, jsonb_build_object('techo_clave', current_setting('t.t1')))",
                  '23505'))
    p.append(caso('C14 admin marca un plano SIN techo junto a los de techo: ok (entran los dos)', cambia(5, '{"en_contrato": true}'), 'ok',
                  "%s" % doc(5, 'en_contrato')))
    p.append(caso('C15 admin desmarca', cambia(5, '{"en_contrato": false}'), 'ok', "not %s" % doc(5, 'en_contrato')))
    p.append(caso('C16 tipo que no existe: 22023', cambia(1, '{"tipo": "folleto"}'), '22023'))
    p.append(caso('C17 casilla que no es booleano: 22023', cambia(1, '{"en_contrato": "si"}'), '22023'))
    p.append(caso('C18 orden negativo: 22023', cambia(1, '{"orden": -1}'), '22023'))
    p.append(caso('C19 orden decimal: 22023', cambia(1, '{"orden": 1.5}'), '22023'))
    p.append(caso('C20 dato que no se edita (path): 22023', cambia(1, '{"path": "x"}'), '22023'))
    p.append(caso('C21 techo de otro modelo: 22023', cambia(1, '{"techo_clave": "no-existe-zz"}'), '22023'))
    if selftest:
        p.append("insert into _t values ('ZZ selftest: esto DEBE salir en rojo', 1 = 2, 'si sale verde el arnes esta roto');")
    p.append('reset role;')

    # ── la edge registrando (service_role), con el usuario de la sesión en p_uid ──
    # La edge llega SIN claims de usuario: _actua_como pone `request.jwt.claims`, pero auth.uid() mira antes
    # `request.jwt.claim.sub`, que el bloque de admin dejó puesto. Sin limpiarlo, todo esto corre como admin
    # (pasó en la primera pasada, 27-sep: R02 salió en rojo y R03-R05 en verde por el motivo equivocado).
    p.append("select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.email', '', true), "
             "set_config('request.jwt.claims', '', true);")
    p.append('set local role service_role;')
    p.append(caso('R02 agente sube marcado: 42501', registra('agente', 1, 'dosier', en='true'), '42501'))
    p.append(caso('R03 agente sube un dosier sin marcar: ok', registra('agente', 2, 'dosier'), 'ok',
                  "exists (select 1 from public.modelo_documentos where path like '%%/b0000000-0000-4000-8000-000000000002.pdf' and tipo = 'dosier' "
                  "and not en_contrato and subido_por = current_setting('t.agente_sub')::uuid)"))
    p.append(caso('R04 llamada vieja de 6 argumentos (edge sin redesplegar) sigue resolviendo: ok', registra('agente', 3, 'otro'), 'ok'))
    p.append(caso('R08 agente sube un plano (regla del 25-sep, se conserva): 42501', registra('agente', 5, 'plano'), '42501'))
    p.append(caso('R05 admin sube marcado: entra el ultimo', registra('admin', 4, 'calidades', en='true'), 'ok',
                  "(select orden from public.modelo_documentos where path like '%%/b0000000-0000-4000-8000-000000000004.pdf') = "
                  "(select max(orden) from public.modelo_documentos where modelo_id = current_setting('t.m')::uuid and en_contrato)"))
    p.append(caso('R06 admin sube un plano marcado de un techo ya cubierto: 23505',
                  registra('admin', 5, 'plano', "current_setting('t.t2')", en='true'), '23505'))
    p.append(caso('R07 tipo que no existe: 22023', registra('admin', 5, 'folleto'), '22023'))
    p.append('reset role;')

    # ── anónimo ──
    p.append('set local role anon;')
    p.append(caso('N1 anon no llama a cambia: 42501', cambia(1, '{"tipo": "otro"}'), '42501'))
    p.append('reset role;')
    p += ['select caso, ok, detalle from _t order by caso;', 'rollback;']
    return '\n'.join(p) + '\n'


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    print(sql('--con-migracion' in sys.argv, '--selftest' in sys.argv))
