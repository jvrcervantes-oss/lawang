#!/usr/bin/env python3
"""Pruebas de permisos de LAW-78 (anexos de contrato en Storage) contra la base REAL,
dentro de UNA transacción que termina SIEMPRE en ROLLBACK. Mismo patrón que
tools/flujos_lawang.py de la agencia: este script no se conecta; imprime un bloque SQL
que se pega en `mcp__supabase-lawang__execute_sql` (o en el SQL Editor).

    python contracts/tools/anexos_rpc_test.py                 # el bloque, con la migración ya aplicada
    python contracts/tools/anexos_rpc_test.py --con-migracion # antepone la migración (probar ANTES de aplicarla)
    python contracts/tools/anexos_rpc_test.py --selftest       # añade un caso que DEBE salir en rojo

Cada caso corre con el ROL REAL (`set local role authenticated` + claims), porque el MCP
corre como `postgres` (bypassrls): sin cambiar de rol ninguna policy se evalúa. El caso
A0 (canario) comprueba que el cambio de rol surtió efecto; si está en rojo, nada vale.
Las identidades y contratos se resuelven DESDE LA BASE: el repo es público, aquí no hay
ni un uid ni un email. Los objetos de Storage que se usan son filas falsas de
storage.objects creadas dentro de la transacción (mueren en el ROLLBACK).
Salida: (caso, ok, detalle) sin PII. Cualquier ok=false es una regresión.
"""
import os
import sys

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MIGRACIONES = [os.path.join(RAIZ, 'supabase', 'migrations', f) for f in (
    '20260927220000_law78_anexos_contrato_storage.sql', '20260927220500_law78_anexos_barrido_y_paso.sql')]

UUID1 = '11111111-1111-4111-8111-111111111111'
UUID2 = '22222222-2222-4222-8222-222222222222'
SHA = 'a' * 64

MONTAJE = r"""
-- identidades y contratos, resueltos como postgres
select set_config('t.autor_sub', u.user_id::text, true), set_config('t.autor_email', lower(u.email), true)
  from public.usuarios u
 where u.activo and u.rol = 'agente' and 'contratos' = any(u.herramientas)
   and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0
 order by (select count(*) from public.contratos c where lower(c.creado_por) = lower(u.email)
             and not coalesce(c.bloqueado, false) and not public.contrato_firma_viva(c.id)) desc
 limit 1;
select set_config('t.ajeno_sub', u.user_id::text, true), set_config('t.ajeno_email', lower(u.email), true)
  from public.usuarios u
 where u.activo and u.rol = 'agente' and 'contratos' = any(u.herramientas)
   and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0
   and lower(u.email) <> current_setting('t.autor_email')
 order by u.creado_en limit 1;
select set_config('t.super_sub', u.user_id::text, true), set_config('t.super_email', lower(u.email), true)
  from public.usuarios u where u.activo and u.rol = 'super_admin' order by u.creado_en limit 1;
select set_config('t.a', c.id::text, true) from public.contratos c
 where lower(c.creado_por) = current_setting('t.autor_email')
   and not coalesce(c.bloqueado, false) and not public.contrato_firma_viva(c.id)
 order by c.created_at desc limit 1;
select set_config('t.b', c.id::text, true) from public.contratos c where coalesce(c.bloqueado, false) order by c.created_at desc limit 1;
select set_config('t.c', c.id::text, true) from public.contratos c
 where not coalesce(c.bloqueado, false) and public.contrato_firma_viva(c.id) order by c.created_at desc limit 1;
-- objetos falsos en el bucket (mueren en el rollback)
insert into storage.objects (bucket_id, name, metadata) values
  ('contratos-anexos', current_setting('t.a') || '/UUID1/1.jpg', '{"size": 1000}'),
  ('contratos-anexos', current_setting('t.a') || '/UUID1/2.jpg', '{"size": 1000}'),
  ('contratos-anexos', current_setting('t.a') || '/UUID2/1.jpg', '{"size": 1000}'),
  ('contratos-anexos', current_setting('t.b') || '/UUID1/1.jpg', '{"size": 1000}'),
  ('contratos-anexos', current_setting('t.c') || '/UUID1/1.jpg', '{"size": 1000}');
""".replace('UUID1', UUID1).replace('UUID2', UUID2)

# Contrato L: el anexo viejo MÁS PEQUEÑO de un contrato sin bloquear y sin firma viva (se resuelve en la base).
# Sus páginas se «pasan al archivo» con filas cuyo sha se calcula EN SQL de la página vieja, como hará el script.
BARRIDO_Y_PASO = r'''
select set_config('t.l', x.id::text, true), set_config('t.lid', x.aid, true)
  from (select c.id, a->>'id' as aid
          from public.contratos c
          cross join lateral jsonb_array_elements(case when jsonb_typeof(c.datos->'annexes') = 'array'
                                                  then c.datos->'annexes' else '[]'::jsonb end) a
         where not coalesce(c.bloqueado, false) and not public.contrato_firma_viva(c.id)
           and a->>'auto' is null and jsonb_typeof(a->'pages') = 'array' and jsonb_array_length(a->'pages') > 0
         order by pg_column_size(c.datos) limit 1) x;
insert into public.contrato_anexo_paginas (contrato_id, anexo_id, n, path, sha256, bytes)
select current_setting('t.l')::uuid, v.aid, g.n, current_setting('t.l') || '/' || gen_random_uuid() || '/' || g.n || '.jpg',
       case when v.aid = 'ax-malo' then repeat('b', 64) else encode(sha256(decode(split_part(g.pag, ',', 2), 'base64')), 'hex') end,
       octet_length(decode(split_part(g.pag, ',', 2), 'base64'))
  from public.contratos c
  cross join lateral jsonb_array_elements(c.datos->'annexes') a
  cross join lateral jsonb_array_elements_text(a->'pages') with ordinality g(pag, n)
  cross join (values ('ax-migrado'), ('ax-malo')) v(aid)
 where c.id = current_setting('t.l')::uuid and a->>'id' = current_setting('t.lid');
update public.contrato_anexo_paginas set created_at = now() - interval '3 days' where anexo_id = 'ax-malo';
insert into storage.objects (bucket_id, name, created_at) values
  ('contratos-anexos', current_setting('t.l') || '/33333333-3333-4333-8333-333333333333/1.jpg', now() - interval '3 days'),
  ('contratos-anexos', current_setting('t.l') || '/44444444-4444-4444-8444-444444444444/1.jpg', now());
set local role service_role;
do $$ begin perform public.contrato_anexos_pasa_a_archivo(current_setting('t.l')::uuid,
                     jsonb_build_object(current_setting('t.lid'), jsonb_build_object('id', 'ax-malo')));
  insert into _t values ('M1 paso con una huella que no cuadra DEBE parar', false, 'no paro');
exception when others then insert into _t values ('M1 paso con una huella que no cuadra DEBE parar', sqlstate = '22023', sqlstate || ' ' || left(sqlerrm, 90)); end $$;
do $$ begin perform public.contrato_anexos_pasa_a_archivo(current_setting('t.b')::uuid, '{"ax1": {"id": "ax-x"}}');
  insert into _t values ('M2 paso en contrato bloqueado DEBE parar', false, 'no paro');
exception when others then insert into _t values ('M2 paso en contrato bloqueado DEBE parar', sqlstate = '23514', sqlstate || ' ' || left(sqlerrm, 90)); end $$;
do $$ begin perform public.contrato_anexos_pasa_a_archivo(current_setting('t.l')::uuid, '{"ax-no-existe": {"id": "ax-x"}}');
  insert into _t values ('M3 paso de un anexo que no esta DEBE parar', false, 'no paro');
exception when others then insert into _t values ('M3 paso de un anexo que no esta DEBE parar', sqlstate = '22023', sqlstate || ' ' || left(sqlerrm, 90)); end $$;
do $$ declare k int; a jsonb; begin
  k := public.contrato_anexos_pasa_a_archivo(current_setting('t.l')::uuid,
         jsonb_build_object(current_setting('t.lid'), jsonb_build_object('id', 'ax-migrado')));
  select e into a from public.contratos c, jsonb_array_elements(c.datos->'annexes') e
   where c.id = current_setting('t.l')::uuid and e->>'id' = 'ax-migrado';
  insert into _t values ('M4 paso bueno: el anexo queda como ficha, sin paginas',
    k = 1 and a is not null and not (a ? 'pages') and a ? 'title'
      and not exists (select 1 from public.contratos c, jsonb_array_elements(c.datos->'annexes') e
                       where c.id = current_setting('t.l')::uuid and e->>'id' = current_setting('t.lid')),
    'k=' || k);
exception when others then insert into _t values ('M4 paso bueno: el anexo queda como ficha, sin paginas', false, sqlstate || ' ' || left(sqlerrm, 90)); end $$;
update public.contrato_anexo_paginas set created_at = now() - interval '3 days' where anexo_id = 'ax-migrado';
insert into _t
select 'H1 barrido: objeto viejo sin fila, si', count(*) filter (where h.path like '%/33333333-%') = 1, count(*)::text
  from public.contrato_anexos_huerfanos(48) h where h.tipo = 'objeto';
insert into _t
select 'H2 barrido: objeto reciente sin fila, no', count(*) = 0, count(*)::text
  from public.contrato_anexos_huerfanos(48) h where h.path like '%/44444444-%';
insert into _t
select 'H3 barrido: filas de un anexo que nadie nombra, si', count(*) > 0, count(*)::text
  from public.contrato_anexos_huerfanos(48) h join public.contrato_anexo_paginas p on p.id = h.fila_id where p.anexo_id = 'ax-malo';
insert into _t
select 'H4 barrido: filas de un anexo en datos, no', count(*) = 0, count(*)::text
  from public.contrato_anexos_huerfanos(48) h join public.contrato_anexo_paginas p on p.id = h.fila_id where p.anexo_id = 'ax-migrado';
reset role;
set local role authenticated;
do $$ begin perform public.contrato_anexos_huerfanos(48);
  insert into _t values ('M5 el navegador no llama al barrido ni al paso', false, 'no paro');
exception when others then insert into _t values ('M5 el navegador no llama al barrido ni al paso', sqlstate = '42501', sqlstate); end $$;
reset role;
'''


def claims(p):
    return ("select set_config('request.jwt.claim.sub', current_setting('t.%(p)s_sub'), true),\n"
            "       set_config('request.jwt.claim.email', current_setting('t.%(p)s_email'), true),\n"
            "       set_config('request.jwt.claims', json_build_object('sub', current_setting('t.%(p)s_sub'),\n"
            "         'email', current_setting('t.%(p)s_email'), 'role', 'authenticated')::text, true);\n"
            "set local role authenticated;\n" % {'p': p})


def caso_rpc(nombre, uid, contrato, path, espera, n=1, bytes_=1000, anexo='ax-prueba'):
    llamada = ("public.contrato_anexo_registra(current_setting('t.%s_sub')::uuid, %s::uuid, '%s', %d, %s, '%s', %d, 800, 1100)"
               % (uid, contrato, anexo, n, path, SHA, bytes_))
    if espera == 'ok':
        return ("do $$ declare v uuid; begin v := %s;\n"
                "  insert into _t values ('%s', v is not null, 'registrada');\n"
                "exception when others then insert into _t values ('%s', false, sqlstate || ' ' || left(sqlerrm, 90)); end $$;"
                % (llamada, nombre, nombre))
    return ("do $$ begin perform %s;\n"
            "  insert into _t values ('%s', false, 'no paro');\n"
            "exception when others then insert into _t values ('%s', sqlstate = '%s', sqlstate || ' ' || left(sqlerrm, 90)); end $$;"
            % (llamada, nombre, nombre, espera))


def ruta(contrato, u, n):
    return "current_setting('t.%s') || '/%s/%d.jpg'" % (contrato, u, n)


A = "current_setting('t.a')"
B = "current_setting('t.b')"
C = "current_setting('t.c')"


def sql(con_migracion=False, selftest=False):
    p = ['begin;',
         '-- destructivo-ok: pruebas de LAW-78 (contracts/tools/anexos_rpc_test.py); TODO acaba en ROLLBACK']
    if con_migracion:
        for m in MIGRACIONES:
            with open(m, encoding='utf-8') as f:
                p.append(f.read())
    p += ['create temporary table _t(caso text, ok boolean, detalle text) on commit drop;',
          'grant all on _t to authenticated, anon, service_role;',
          MONTAJE.strip()]

    # ── como service_role: la Edge registrando, con el usuario de la sesión en p_uid ──
    p.append('set local role service_role;')
    p.append(caso_rpc('R1 autor, ruta buena: registra', 'autor', A, ruta('a', UUID1, 1), 'ok'))
    p.append(caso_rpc('R2 misma ruta otra vez: 23505', 'autor', A, ruta('a', UUID1, 1), '23505', anexo='ax-otro'))
    p.append(caso_rpc('R3 mismo anexo y pagina con otra ruta: 23505', 'autor', A, ruta('a', UUID2, 1), '23505'))
    p.append(caso_rpc('R4 agente ajeno: 42501', 'ajeno', A, ruta('a', UUID1, 2), '42501', n=2))
    p.append(caso_rpc('R5 contrato bloqueado (super admin tampoco): 23514', 'super', B, ruta('b', UUID1, 1), '23514'))
    p.append(caso_rpc('R6 contrato con firma viva (super admin tampoco): 23514', 'super', C, ruta('c', UUID1, 1), '23514'))
    p.append(caso_rpc('R7 ruta de OTRO contrato: 22023', 'super', A, ruta('b', UUID1, 1), '22023', anexo='ax-r7'))
    p.append(caso_rpc('R8 ruta con ..: 22023', 'autor', A,
                      "current_setting('t.a') || '/%s/../%s/1.jpg'" % (UUID1, UUID2), '22023', anexo='ax-r8'))
    p.append(caso_rpc('R9 n distinto del de la ruta: 22023', 'autor', A, ruta('a', UUID1, 2), '22023', n=3, anexo='ax-r9'))
    p.append(caso_rpc('R10 objeto que no esta en el bucket: 22023', 'autor', A, ruta('a', UUID1, 9), '22023', n=9, anexo='ax-r10'))
    p.append(caso_rpc('R11 tamano distinto del objeto: 22023', 'autor', A, ruta('a', UUID1, 2), '22023', n=2, bytes_=999, anexo='ax-r11'))
    p.append(caso_rpc('R12 anexo_id con inyeccion: 22023', 'autor', A, ruta('a', UUID1, 2), '22023', n=2, anexo="ax/../x"))
    p.append(caso_rpc('R13 contrato inexistente: 42501', 'autor', "'%s'" % UUID2, ruta('a', UUID1, 2), '42501', n=2))
    p.append(caso_rpc('R14 autor, pagina 2 del mismo anexo: registra', 'autor', A, ruta('a', UUID1, 2), 'ok', n=2))
    p.append('reset role;')

    # ── como el autor autenticado ──
    p.append(claims('autor'))
    p.append("insert into _t values ('A0 canario: rol y claims', current_user = 'authenticated' and auth.uid() is not null "
             "and lower(auth.email()) = current_setting('t.autor_email'), 'current_user=' || current_user);")
    p.append("insert into _t values ('A1 puede: autor sobre su contrato = ok', public.contrato_anexo_puede(%s::uuid) = 'ok', "
             "public.contrato_anexo_puede(%s::uuid));" % (A, A))
    p.append("insert into _t values ('A2 autor ve sus 2 paginas', (select count(*) from public.contrato_anexo_paginas "
             "where contrato_id = %s::uuid) = 2, (select count(*) from public.contrato_anexo_paginas where contrato_id = %s::uuid)::text);" % (A, A))
    p.append("insert into _t values ('A3 autor lee el objeto registrado y no el suelto', "
             "(select count(*) from storage.objects where bucket_id = 'contratos-anexos' and name like %s || '/%%') = 2, "
             "(select count(*) from storage.objects where bucket_id = 'contratos-anexos' and name like %s || '/%%')::text);" % (A, A))
    p.append("do $$ begin insert into public.contrato_anexo_paginas (contrato_id, anexo_id, n, path, sha256, bytes) "
             "values (current_setting('t.a')::uuid, 'ax-dir', 1, 'x', '%s', 1);\n"
             "  insert into _t values ('A4 insert directo en la tabla DEBE parar', false, 'no paro');\n"
             "exception when others then insert into _t values ('A4 insert directo en la tabla DEBE parar', sqlstate = '42501', sqlstate); end $$;" % SHA)
    p.append("do $$ begin perform public.contrato_anexo_registra(auth.uid(), current_setting('t.a')::uuid, 'ax-x', 1, 'x', '%s', 1, 1, 1);\n"
             "  insert into _t values ('A5 la RPC de registro desde el navegador DEBE parar', false, 'no paro');\n"
             "exception when others then insert into _t values ('A5 la RPC de registro desde el navegador DEBE parar', sqlstate = '42501', sqlstate); end $$;" % SHA)
    p.append("do $$ begin delete from public.contrato_anexo_paginas where contrato_id = current_setting('t.a')::uuid;\n"
             "  insert into _t values ('A6 borrar desde el navegador no borra nada', "
             "(select count(*) from public.contrato_anexo_paginas where contrato_id = current_setting('t.a')::uuid) = 2, 'sin error: 0 filas');\n"
             "exception when others then insert into _t values ('A6 borrar desde el navegador no borra nada', sqlstate = '42501', sqlstate); end $$;")
    p.append("do $$ begin insert into storage.objects (bucket_id, name) values ('contratos-anexos', current_setting('t.a') || '/x/1.jpg');\n"
             "  insert into _t values ('A7 subir directo a storage.objects DEBE parar', false, 'no paro');\n"
             "exception when others then insert into _t values ('A7 subir directo a storage.objects DEBE parar', sqlstate = '42501', sqlstate); end $$;")
    if selftest:
        p.append("insert into _t values ('ZZ selftest: esto DEBE salir en rojo', 1 = 2, 'si sale verde el arnes esta roto');")
    p.append('reset role;')

    # ── como el agente ajeno ──
    p.append(claims('ajeno'))
    p.append("insert into _t values ('J1 puede: ajeno sobre contrato ajeno = no_visible', public.contrato_anexo_puede(%s::uuid) = 'no_visible', "
             "public.contrato_anexo_puede(%s::uuid));" % (A, A))
    p.append("insert into _t values ('J2 ajeno no ve las filas', (select count(*) from public.contrato_anexo_paginas where contrato_id = %s::uuid) = 0, '');" % A)
    p.append("insert into _t values ('J3 ajeno no lee los objetos', (select count(*) from storage.objects where bucket_id = 'contratos-anexos' "
             "and name like %s || '/%%') = 0, '');" % A)
    p.append('reset role;')

    # ── como super admin: bloqueado ──
    p.append(claims('super'))
    p.append("insert into _t values ('S1 puede: bloqueado = bloqueado (tambien super admin)', public.contrato_anexo_puede(%s::uuid) = 'bloqueado', "
             "public.contrato_anexo_puede(%s::uuid));" % (B, B))
    p.append('reset role;')

    # ── barrido y paso al archivo (service_role: los scripts) ──
    p.append(BARRIDO_Y_PASO.strip())

    # ── anónimo ──
    p.append('set local role anon;')
    p.append("do $$ begin perform public.contrato_anexo_puede(current_setting('t.a')::uuid);\n"
             "  insert into _t values ('N1 anon no llama a contrato_anexo_puede', false, 'no paro');\n"
             "exception when others then insert into _t values ('N1 anon no llama a contrato_anexo_puede', sqlstate = '42501', sqlstate); end $$;")
    p.append("do $$ declare k int; begin select count(*) into k from public.contrato_anexo_paginas;\n"
             "  insert into _t values ('N2 anon no lee la tabla', k = 0, k::text);\n"
             "exception when others then insert into _t values ('N2 anon no lee la tabla', sqlstate = '42501', sqlstate); end $$;")
    p.append('reset role;')
    p += ['select caso, ok, detalle from _t order by caso;', 'rollback;']
    return '\n'.join(p) + '\n'


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    print(sql('--con-migracion' in sys.argv, '--selftest' in sys.argv))
