#!/usr/bin/env python3
"""Pruebas de LAW-406 (envío a firma + constancia «sin anexo» en UNA transacción) y LAW-400 (el servidor
comprueba las fichas de anexo automático `axauto-<doc>` de un contrato) contra la base REAL, dentro de UNA
transacción que termina SIEMPRE en ROLLBACK. Mismo patrón que contracts/tools/anexos_rpc_test.py: este script
no se conecta; imprime un bloque SQL que se pega en `mcp__supabase-lawang__execute_sql` (o en el SQL Editor).

    python contracts/tools/envio_y_fichas_rpc_test.py A                 # bloque A (LAW-406), migraciones ya aplicadas
    python contracts/tools/envio_y_fichas_rpc_test.py B                 # bloque B (LAW-400)
    python contracts/tools/envio_y_fichas_rpc_test.py A --con-migracion # las antepone (probar ANTES de aplicarlas)
    python contracts/tools/envio_y_fichas_rpc_test.py B --selftest      # añade un caso que DEBE salir en rojo

DOS BLOQUES independientes, cada uno con su begin/rollback y `statement_timeout` de 50 s (28-sep-2026: en un solo
bloque se pasó del tiempo del MCP con la base cargada y hubo que cancelarlo). A = migraciones de LAW-406 (la de
envío y la diferida de retirada) + P1-P3 + F1-FB + F9. B = trigger de LAW-400 + L1-LF. Si uno se pasa del tiempo:
mirar pg_stat_activity y cancelar el pid; nunca dejar colgada una transacción con el drop de contrato_envia_firma
o el ALTER de contrato_eventos.

LAW-406 corre con el ROL REAL (`set local role authenticated` + claims del autor del contrato): el MCP corre como
`postgres` y contrato_firma_estado mira la sesión. El canario A0 comprueba que el cambio de rol surtió efecto.
LAW-400 es un trigger: corre igual con cualquier rol, así que se prueba como postgres sobre un contrato de obra
REAL sin bloquear (el más pequeño con techo) tocando SOLO `datos.annexes`; los documentos de Modelos de prueba se
crean dentro de la transacción. Identidades y contratos se resuelven DESDE LA BASE (el repo es público: aquí no hay
ni un uid ni un email). Salida: (caso, ok, detalle) sin PII. Cualquier ok=false es una regresión.

OJO: el caso F9 (atomicidad) cambia el CHECK de contrato_eventos dentro de la transacción, lo que bloquea esa
tabla hasta el ROLLBACK: va el ÚLTIMO para que el bloqueo dure lo mínimo (menos de un segundo).
"""
import os
import sys

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MIGRACIONES = {
    'A': [os.path.join(RAIZ, 'supabase', 'migrations', '20260928120000_law406_envia_firma_con_constancia.sql'),
          # paso 3, aplicado el 28-sep tras redesplegar ficheros-contrato (v6)
          os.path.join(RAIZ, 'supabase', 'migrations', '20260928024744_law406_retira_envio_sin_anexo.sql')],
    'B': [os.path.join(RAIZ, 'supabase', 'migrations', '20260928121000_law400_fichas_anexo_auto_servidor.sql')],
}

# Los montajes se ACOTAN antes de mirar `datos` o llamar a funciones por fila: primero los 60 contratos sin bloquear
# más recientes (columnas baratas), y solo sobre esos lo caro (28-sep, revisor: ordenar todos por pg_column_size y
# un jsonb_path_exists sobre toda la tabla detoastaban `datos` entero).
RECIENTES = ("(select c0.id from public.contratos c0 where not coalesce(c0.bloqueado, false) "
             "order by c0.created_at desc limit 60)")

MONTAJE_A = r"""
-- LAW-406: un agente con la herramienta de contratos y un contrato suyo, sin bloquear, sin firma viva ni firmada
select set_config('t.a', x.id::text, true), set_config('t.autor_email', x.email, true), set_config('t.autor_sub', x.user_id::text, true)
  from (select c.id, lower(u.email) as email, u.user_id
          from public.contratos c join public.usuarios u on lower(u.email) = lower(c.creado_por)
         where c.id in RECIENTES and u.activo and u.rol = 'agente' and 'contratos' = any(u.herramientas)
           and not public.contrato_firma_viva(c.id)
           and not exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id and f.estado = 'firmado')
         order by c.created_at desc limit 1) x;
select set_config('t.ajeno_email', lower(u.email), true), set_config('t.ajeno_sub', u.user_id::text, true)
  from public.usuarios u
 where u.activo and u.rol = 'agente' and 'contratos' = any(u.herramientas)
   and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0 and lower(u.email) <> current_setting('t.autor_email')
 order by u.creado_en limit 1;
""".replace('RECIENTES', RECIENTES)

MONTAJE_B = r"""
-- LAW-400: el contrato de obra sin bloquear más pequeño con techo (no sintético) de un modelo con dos techos o más
select set_config('t.k', x.id::text, true), set_config('t.m', x.mid::text, true), set_config('t.t1', x.techo, true),
       set_config('t.t2', (select min(t.clave) from public.modelo_techos t where t.modelo_id = x.mid and t.clave <> x.techo), true)
  from (select c.id, m.id as mid, c.datos->'techo'->>'clave' as techo
          from public.contratos c join public.modelos m on lower(btrim(m.nombre)) = lower(btrim(c.datos->'fields'->>'tipologia_construccion'))
         where c.id in RECIENTES and not public.contrato_firma_viva(c.id)
           and (c.datos->'techo'->>'sintetico') is distinct from 'true'
           and exists (select 1 from public.modelo_techos t where t.modelo_id = m.id and t.clave = c.datos->'techo'->>'clave')
           and (select count(*) from public.modelo_techos t where t.modelo_id = m.id) >= 2
         order by pg_column_size(c.datos) limit 1) x;
select set_config('t.otro_m', (select m.id::text from public.modelos m where m.id <> current_setting('t.m')::uuid order by m.id limit 1), true);
-- documentos de Modelos de prueba (mueren en el rollback). Ningún plano: no chocan con el índice de un plano por techo.
insert into public.modelo_documentos (id, modelo_id, nombre, path, tipo, techo_clave, en_contrato, orden) values
  ('c0000000-0000-4000-8000-000000000001', current_setting('t.m')::uuid, 'sin techo', current_setting('t.m') || '/c0000000-0000-4000-8000-000000000001.pdf', 'calidades', null, true, 901),
  ('c0000000-0000-4000-8000-000000000002', current_setting('t.m')::uuid, 'techo del contrato', current_setting('t.m') || '/c0000000-0000-4000-8000-000000000002.pdf', 'ficha', current_setting('t.t1'), true, 902),
  ('c0000000-0000-4000-8000-000000000003', current_setting('t.m')::uuid, 'otro techo', current_setting('t.m') || '/c0000000-0000-4000-8000-000000000003.pdf', 'ficha', current_setting('t.t2'), true, 903),
  ('c0000000-0000-4000-8000-000000000004', current_setting('t.m')::uuid, 'sin marcar', current_setting('t.m') || '/c0000000-0000-4000-8000-000000000004.pdf', 'render', null, false, 0),
  ('c0000000-0000-4000-8000-000000000005', current_setting('t.otro_m')::uuid, 'otro modelo', current_setting('t.otro_m') || '/c0000000-0000-4000-8000-000000000005.pdf', 'calidades', null, true, 905);
""".replace('RECIENTES', RECIENTES)

DOC = "c0000000-0000-4000-8000-00000000000%d"
HASH = "repeat('a', 64)"


def claims(p):
    return ("select set_config('request.jwt.claim.sub', current_setting('t.%(p)s_sub'), true),\n"
            "       set_config('request.jwt.claim.email', current_setting('t.%(p)s_email'), true),\n"
            "       set_config('request.jwt.claims', json_build_object('sub', current_setting('t.%(p)s_sub'),\n"
            "         'email', current_setting('t.%(p)s_email'), 'role', 'authenticated')::text, true);\n"
            "set local role authenticated;\n" % {'p': p})


def caso(nombre, llamada, espera, verifica='true', detalle_fallo="''"):
    """`llamada` es una expresión SQL; espera 'ok' (y `verifica` tiene que ser cierto) o un sqlstate, y entonces
    `verifica` se evalúa DESPUÉS del error (lo que tiene que haber quedado igual)."""
    if espera == 'ok':
        return ("do $$ begin perform %s;\n"
                "  insert into _t values ('%s', %s, 'hecho ' || %s);\n"
                "exception when others then insert into _t values ('%s', false, sqlstate || ' ' || left(sqlerrm, 110)); end $$;"
                % (llamada, nombre, verifica, detalle_fallo, nombre))
    return ("do $$ begin perform %s;\n"
            "  insert into _t values ('%s', false, 'no paro');\n"
            "exception when others then insert into _t values ('%s', sqlstate = '%s' and (%s), sqlstate || ' ' || left(sqlerrm, 110)); end $$;"
            % (llamada, nombre, nombre, espera, verifica))


def envia(sin_anexo=None):
    extra = '' if sin_anexo is None else ', p_sin_anexo => %s' % sin_anexo
    return ("public.contrato_envia_firma(p_contrato => current_setting('t.a')::uuid, p_nombre => 'Prueba', "
            "p_email => 'prueba@example.com', p_rol => 'adquiriente_1', p_orden => 1, p_snapshot_hash => %s%s)" % (HASH, extra))


# Las comprobaciones leen como postgres (funciones temporales SECURITY DEFINER): el agente no ve contrato_eventos por
# RLS, y un conteo a 0 por no poder mirar se leería como «no se apuntó nada».
LECTORES = r"""
create function pg_temp.t_eventos() returns bigint language sql security definer as $f$
  select count(*) from public.contrato_eventos e where e.contrato_id = current_setting('t.a')::uuid
     and e.evento = 'envio_sin_anexo_confirmado' and e.creado_en >= now() $f$;
create function pg_temp.t_pendiente() returns uuid language sql security definer as $f$
  select f.id from public.contrato_firmas f where f.contrato_id = current_setting('t.a')::uuid and f.estado = 'pendiente' $f$;
create function pg_temp.t_pendientes() returns bigint language sql security definer as $f$
  select count(*) from public.contrato_firmas f where f.contrato_id = current_setting('t.a')::uuid and f.estado = 'pendiente' $f$;
create function pg_temp.t_estado(p uuid) returns text language sql security definer as $f$
  select f.estado from public.contrato_firmas f where f.id = p $f$;
create function pg_temp.t_constancia_f2() returns boolean language sql security definer as $f$
  select exists (select 1 from public.contrato_eventos e where e.contrato_id = current_setting('t.a')::uuid
     and e.evento = 'envio_sin_anexo_confirmado' and e.quien = current_setting('t.autor_email')
     and e.detalle->>'motivo' = 'fallo' and e.detalle->'faltan'->>0 = 'Apendice A bx/b'
     and (e.detalle->>'firma_id')::uuid = pg_temp.t_pendiente()) $f$;
"""
EVENTOS = "pg_temp.t_eventos()"
PENDIENTE = "pg_temp.t_pendiente()"


def ficha(n, auto="'Prueba'"):
    return "jsonb_build_object('id', 'axauto-%s', 'auto', %s, 'title', 'doc %d', 'on', true, 'pages', '[]'::jsonb)" % (DOC % n, auto, n)


def guarda(*fichas):
    """Update del contrato k tocando SOLO datos.annexes (lista entera)."""
    return ("update public.contratos set datos = jsonb_set(datos, '{annexes}', jsonb_build_array(%s)) "
            "where id = current_setting('t.k')::uuid" % ', '.join(fichas))


def caso_update(nombre, sentencia, espera):
    if espera == 'ok':
        return ("do $$ begin %s;\n  insert into _t values ('%s', true, 'hecho');\n"
                "exception when others then insert into _t values ('%s', false, sqlstate || ' ' || left(sqlerrm, 110)); end $$;"
                % (sentencia, nombre, nombre))
    return ("do $$ begin %s;\n  insert into _t values ('%s', false, 'no paro');\n"
            "exception when others then insert into _t values ('%s', sqlstate = '%s' and sqlerrm like 'El anexo %%', "
            "sqlstate || ' ' || left(sqlerrm, 110)); end $$;" % (sentencia, nombre, nombre, espera))


def sql(bloque, con_migracion=False, selftest=False):
    p = ['-- destructivo-ok: pruebas de LAW-406/LAW-400 (contracts/tools/envio_y_fichas_rpc_test.py, bloque %s); TODO acaba en ROLLBACK' % bloque,
         'begin;', "set local statement_timeout = '50s';"]
    if con_migracion:
        for m in MIGRACIONES[bloque]:
            with open(m, encoding='utf-8') as f:
                p.append(f.read())
    p += ['create temporary table _t(caso text, ok boolean, detalle text) on commit drop;',
          'grant all on _t to authenticated, anon, service_role;']
    if bloque == 'A':
        p += [LECTORES.strip(), MONTAJE_A.strip(),
              "insert into _t values ('A1 montaje: contrato y agentes resueltos', current_setting('t.a', true) <> '' "
              "and current_setting('t.ajeno_sub', true) <> '', '');"]
        bloque_a(p)
    else:
        p += [MONTAJE_B.strip(),
              "insert into _t values ('B1 montaje: contrato de obra y modelo resueltos', current_setting('t.k', true) <> '' "
              "and current_setting('t.t2', true) <> '', '');"]
        bloque_b(p)
    if selftest:
        p.append("insert into _t values ('ZZ selftest: esto DEBE salir en rojo', 1 = 2, 'si sale verde el arnes esta roto');")
    p += ['select caso, ok, detalle from _t order by caso;', 'rollback;']
    return '\n'.join(p) + '\n'


def bloque_a(p):

    # ── LAW-406: lo que queda expuesto ──
    p.append("insert into _t values ('P1 una sola contrato_envia_firma (sin sobrecarga vieja)', "
             "(select count(*) from pg_proc where proname = 'contrato_envia_firma' and pronamespace = 'public'::regnamespace) = 1, '');")
    p.append("insert into _t values ('P2 permisos: solo authenticated (ni anon ni service_role, sin llamador)', "
             "has_function_privilege('authenticated', 'public.contrato_envia_firma(uuid,text,text,text,integer,text,jsonb)', 'execute') "
             "and not has_function_privilege('service_role', 'public.contrato_envia_firma(uuid,text,text,text,integer,text,jsonb)', 'execute') "
             "and not has_function_privilege('anon', 'public.contrato_envia_firma(uuid,text,text,text,integer,text,jsonb)', 'execute'), '');")
    p.append("insert into _t values ('P3 contrato_envio_sin_anexo retirada (reducir la exposicion)', "
             "to_regprocedure('public.contrato_envio_sin_anexo(uuid,text,jsonb)') is null, '');")

    # ── LAW-406: el autor envía ──
    p.append(claims('autor'))
    p.append("insert into _t values ('A0 canario: rol y claims del autor', current_user = 'authenticated' and auth.uid() is not null "
             "and public.es_agente(), 'current_user=' || current_user);")
    p.append(caso('F1 envio SIN constancia (llamada de 6 argumentos, edge vieja): ok y ningun evento', envia(), 'ok',
                  "%s = 0 and %s is not null" % (EVENTOS, PENDIENTE)))
    p.append("select set_config('t.f1', %s::text, true);" % PENDIENTE)
    p.append(caso('F2 envio CON constancia: evento en la misma llamada, actor de la sesion, lista saneada y firma enlazada',
                  envia("jsonb_build_object('motivo', 'fallo', 'faltan', jsonb_build_array('Apendice A <b>x</b>'))"), 'ok',
                  "pg_temp.t_constancia_f2() and pg_temp.t_estado(current_setting('t.f1')::uuid) = 'anulado'"))
    p.append("select set_config('t.f2', %s::text, true);" % PENDIENTE)
    NADA_TOCADO = "%s = current_setting('t.f2')::uuid and %s = 1" % (PENDIENTE, EVENTOS)
    p.append(caso('F3 motivo que no existe: 22023 y el enlace vivo sigue siendo el de F2', envia("'{\"motivo\": \"otro\"}'::jsonb"), '22023', NADA_TOCADO))
    p.append(caso('F4 lista con algo que no es texto: 22023, nada tocado', envia("'{\"motivo\": \"fallo\", \"faltan\": [1]}'::jsonb"), '22023', NADA_TOCADO))
    p.append(caso('F5 lista de 21: 22023, nada tocado',
                  envia("jsonb_build_object('motivo', 'fallo', 'faltan', (select jsonb_agg('x'::text) from generate_series(1, 21)))"), '22023', NADA_TOCADO))
    p.append(caso('F6 constancia que no es un objeto: 22023, nada tocado', envia("'\"ninguno\"'::jsonb"), '22023', NADA_TOCADO))
    p.append(caso('F7 null JSON = sin constancia: ok y ningun evento nuevo', envia("'null'::jsonb"), 'ok', "%s = 1" % EVENTOS))
    p.append(caso('F8 motivo sin_apendice_a sin lista: ok', envia("'{\"motivo\": \"sin_apendice_a\"}'::jsonb"), 'ok', "%s = 2" % EVENTOS))
    p.append('reset role;')
    p.append(claims('ajeno'))
    p.append(caso('FA agente ajeno con constancia: 42501 y ningun evento', envia("'{\"motivo\": \"ninguno\"}'::jsonb"), '42501', "%s = 2" % EVENTOS))
    p.append('reset role;')
    p.append('set local role anon;')
    p.append(caso('FB anon no llama a contrato_envia_firma: 42501', envia(), '42501'))
    p.append('reset role;')

    # ── LAW-406: atomicidad — si la constancia no se puede apuntar, NO sale el envío ──
    # (el último: el cambio del CHECK bloquea contrato_eventos hasta el rollback)
    p.append("alter table public.contrato_eventos drop constraint contrato_eventos_evento_check;")
    p.append("alter table public.contrato_eventos add constraint contrato_eventos_evento_check check (evento <> 'envio_sin_anexo_confirmado') not valid;")
    p.append(claims('autor'))
    p.append("select set_config('t.f8', %s::text, true);" % PENDIENTE)
    p.append(caso('F9 atomicidad: la constancia falla -> el envio se deshace (el enlace anterior sigue vivo, ninguno nuevo)',
                  envia("'{\"motivo\": \"ninguno\"}'::jsonb"), '23514',
                  "%s = current_setting('t.f8')::uuid and pg_temp.t_pendientes() = 1 and %s = 2" % (PENDIENTE, EVENTOS)))
    p.append('reset role;')


def bloque_b(p):
    # ── LAW-400: el trigger de contratos juzga las fichas automáticas ──
    p.append(caso_update('L1 fichas de un doc sin techo y otro del techo del contrato: ok', guarda(ficha(1), ficha(2)), 'ok'))
    p.append(caso_update('L2 ficha de un doc de OTRO techo: 23514', guarda(ficha(1), ficha(3)), '23514'))
    p.append(caso_update('L3 ficha de un doc NO marcado: 23514', guarda(ficha(4)), '23514'))
    p.append(caso_update('L4 ficha de un doc de OTRO modelo: 23514', guarda(ficha(5)), '23514'))
    VIEJA = "jsonb_build_object('id', 'axauto', 'auto', 'Prueba', 'title', 'vieja', 'on', %s)"
    p.append(caso_update('L5 ficha vieja axauto NUEVA (no estaba guardada): 23514', guarda(VIEJA % 'true'), '23514'))
    # compatibilidad: un contrato real sin bloquear que ya guarda la ficha vieja `axauto`
    p.append("select set_config('t.v', (select c.id::text from public.contratos c where c.id in " + RECIENTES + " "
             "and not public.contrato_firma_viva(c.id) and c.id <> current_setting('t.k')::uuid "
             "and jsonb_path_exists(c.datos->'annexes', '$[*] ? (@.id == \"axauto\")') order by pg_column_size(c.datos) limit 1), true);")
    GUARDA_V = "update public.contratos set datos = jsonb_set(datos, '{annexes}', jsonb_build_array(%s)) where id = current_setting('t.v')::uuid"
    p.append(caso_update('L5b la ficha vieja que YA estaba guardada (compatibilidad): ok', GUARDA_V % (VIEJA % 'false'), 'ok'))
    p.append(caso_update('L5c dos fichas viejas: 23514', GUARDA_V % ((VIEJA % 'true') + ', ' + (VIEJA % 'false')), '23514'))
    p.append(caso_update('L6 automatica con un id que no es axauto-<uuid>: 23514',
                         guarda("jsonb_build_object('id', 'axauto-no-es-uuid', 'auto', 'Prueba', 'title', 'x', 'on', true)"), '23514'))
    p.append(caso_update('L7 el mismo documento dos veces: 23514', guarda(ficha(1), ficha(1)), '23514'))
    p.append(caso_update('L8 manual con un auto que no es texto (true) y sin paginas: se juzga como manual, 23514',
                         guarda("jsonb_build_object('id', 'ax-00000000-0000-4000-8000-0000000000aa', 'auto', true, 'title', 'falsa', 'on', true)"), '23514'))
    p.append(caso_update('L9 manual con auto vacio y sin paginas: 23514',
                         guarda("jsonb_build_object('id', 'ax-00000000-0000-4000-8000-0000000000ab', 'auto', '', 'title', 'falsa', 'on', true)"), '23514'))
    # contrato firmado / update que no toca la lista: no se juzga aunque la ficha haya envejecido
    p.append(caso_update('LA se guarda D1 (valido)', guarda(ficha(1)), 'ok'))
    p.append("update public.modelo_documentos set en_contrato = false where id = '%s';" % (DOC % 1))
    p.append(caso_update('LB update de otra clave de datos con la ficha ya envejecida: no se juzga, ok',
                         "update public.contratos set datos = jsonb_set(datos, '{zz_prueba}', '1'::jsonb) where id = current_setting('t.k')::uuid", 'ok'))
    p.append(caso_update('LC guardar la MISMA lista: no cambia, no se juzga, ok', guarda(ficha(1)), 'ok'))
    p.append(caso_update('LD cambiar la lista con la ficha envejecida dentro: 23514', guarda(ficha(1), ficha(2)), '23514'))
    p.append(caso_update('LE la lista re-derivada (sin el desmarcado): ok', guarda(ficha(2)), 'ok'))
    # dos modelos con el mismo nombre: no se elige uno a ciegas (modelos.nombre no es único)
    p.append("insert into public.modelos (slug, nombre) values ('zz-prueba-duplicado', (select nombre from public.modelos where id = current_setting('t.m')::uuid));")
    p.append(caso_update('LF dos modelos con el nombre del contrato: 23514', guarda(ficha(2), ficha(1)), '23514'))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    bloques = [a for a in sys.argv[1:] if a in ('A', 'B')]
    if len(bloques) != 1:
        sys.exit('uso: envio_y_fichas_rpc_test.py A|B [--con-migracion] [--selftest]')
    print(sql(bloques[0], '--con-migracion' in sys.argv, '--selftest' in sys.argv))
