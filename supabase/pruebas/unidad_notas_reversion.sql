-- Prueba de la VUELTA ATRAS de 20261016001810_unidad_notas (15-oct-2026; calco de cliente_notas_reversion.sql).
-- Siembra parcelas con notas, ejecuta el texto de supabase/reversion_unidad_notas/REVERSION.sql TAL CUAL (copiado abajo por
-- el autor; si la REVERSION cambia, se vuelve a copiar) y comprueba: las notas vuelven a unidades.notas (la mas reciente
-- arriba), el check y los disparadores de unidades desaparecen, las tablas y funciones nuevas tambien, y cliente_notas_datos
-- vuelve a su md5 de la viva del 15-oct con su dueño y su permiso.
--    python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261016001810_unidad_notas.sql --prueba unidad_notas_reversion.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-UR.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _ur (et text primary key, id uuid);
do $siembra$
declare p uuid; u1 uuid; u2 uuid;
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS REVERSION NOTAS DE PARCELA:%', E'\nR0 esta prueba borra tablas: solo corre en rama → FALLA';
  end if;
  perform set_config('request.jwt.claims', '', true);
  insert into public.empresas (clave, nombre) values ('zz_ur', 'ZZ-UR Empresa');
  insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-UR Proyecto', 'zz-ur-proyecto', 'zz_ur', true) returning id into p;
  -- catálogos vacíos en la rama (estructura del volcado): sin esta fila, unidades_tipo_fkey da 23503 (ensayo 16-oct)
  insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, estado, notas)
    values ('ZZ-UR-1', 'ZZ-UR Proyecto', p, 'parcela', 'disponible', 'ZZ-UR primera') returning id into u1;
  update public.unidades set notas = 'ZZ-UR segunda' where id = u1;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, estado) values ('ZZ-UR-2', 'ZZ-UR Proyecto', p, 'parcela', 'disponible') returning id into u2;
  if (select count(*) from public.unidad_notas where unidad_id = u1) <> 2 or (select notas from public.unidades where id = u1) is not null then
    raise exception 'FIN DE PRUEBAS REVERSION NOTAS DE PARCELA:%', E'\nR0 la siembra no dejo 2 notas en el historial y la columna vacia → FALLA';
  end if;
  insert into _ur values ('u1', u1), ('u2', u2);
end $siembra$;

-- ======================== desde aqui, copia literal de supabase/reversion_unidad_notas/REVERSION.sql ========================
-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261016001810_unidad_notas.sql (15-oct-2026, sesion notas-parcela).
-- ORDEN: 1) front a su version anterior (git revert de los commits de la pantalla: vuelve el campo «Notas» al editor de la
-- parcela, a la importacion y a la plantilla CSV, y la ficha del cliente vuelve a su codigo propio), 2) ESTE fichero, en una
-- transaccion. Al reves, la pantalla llamaria a funciones que ya no existen.
-- Antes de borrar las tablas, cada parcela recupera en unidades.notas sus notas (todas las que tenga, la mas reciente arriba,
-- separadas por una linea en blanco): ninguna nota escrita entre medias se pierde. La traza de retiradas se pierde con su
-- tabla (no tiene texto). El check y el disparador de unidades se quitan ANTES de devolver el texto: con el disparador
-- puesto, el update las volveria a meter en el historial y dejaria la columna vacia.
-- cliente_notas_datos vuelve LITERAL a la viva del 15-oct (md5(prosrc) 4942e7bd0e0f91a49ef479929711e4d5); CREATE OR REPLACE
-- conserva su dueño lw_lector y sus grants.
-- destructivo-ok: borra las tablas, funciones, disparadores y el check que creo la migracion despues de devolver su texto a unidades.notas
set local lock_timeout = '5s';
-- la FK de unidad_notas.unidad_id es diferible: si en esta misma transacción quedan comprobaciones pendientes, DROP TABLE
-- falla («pending trigger events»; lo cazó la prueba de la vuelta atrás de cliente_notas, 15-oct). Se resuelven ahora.
set constraints all immediate;

do $pre$
begin
  if to_regclass('public.unidad_notas') is null then
    raise exception 'unidad_notas no existe: no hay nada que revertir';
  end if;
  -- reponer cliente_notas_datos solo si sigue siendo la de esta migración: si alguien la cambió después, reponer la del
  -- 15-oct borraría ese cambio sin avisar (Base de datos, consulta de deploy 15-oct). Sin \r por si se aplicó desde Windows.
  if (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p
       where p.oid = 'public.cliente_notas_datos(uuid)'::regprocedure) <> '13d9b562da34fd5fbe627a7c6efe273f' then
    raise exception 'cliente_notas_datos viva no es la de 20261016001810 (md5 13d9b562…): alguien la cambió después; revisar a mano';
  end if;
  -- devolver el texto a unidades.notas dispara trg_unidad_precio_suma en cada parcela con notas: si alguna tuviera precio
  -- distinto de suelo + construcción, revertir se lo recalcularía sin avisar (Backend, consulta de deploy 15-oct; misma guarda
  -- que la ida)
  if exists (select 1 from public.unidades u
              where exists (select 1 from public.unidad_notas n where n.unidad_id = u.id)
                and (u.precio_suelo is not null or u.precio_construccion is not null)
                and u.precio is distinct from coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0)) then
    raise exception 'hay parcelas con notas cuyo precio no es suelo + construcción: devolverles las notas lo recalcularía';
  end if;
end $pre$;

alter table public.unidades drop constraint if exists unidades_notas_al_historial;
drop trigger if exists trg_unidades_notas_a_historial on public.unidades;
drop trigger if exists trg_unidades_notas_al_borrar on public.unidades;

update public.unidades u
   set notas = s.texto
  from (select n.unidad_id, string_agg(n.texto, E'\n\n' order by n.creado_en desc, n.id desc) as texto
          from public.unidad_notas n group by n.unidad_id) s
 where s.unidad_id = u.id;

-- cliente_notas_datos vuelve LITERAL a la viva del 15-oct (md5(prosrc) 4942e7bd0e0f91a49ef479929711e4d5)
CREATE OR REPLACE FUNCTION public.cliente_notas_datos(p_client uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'cliente_notas_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'texto', x.texto, 'origen', x.origen, 'creado_en', x.creado_en,
                                               'autor_id', x.autor_id, 'autor_email', x.autor_email)
                            order by x.rn) filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
    into v, n
    from (select cn.id, cn.texto, cn.origen, cn.creado_en, cn.autor_id, u.email as autor_email,
                 row_number() over (order by cn.creado_en desc, cn.id desc) as rn
            from public.cliente_notas cn
            left join public.usuarios u on u.user_id = cn.autor_id
           where cn.client_id = p_client
           order by cn.creado_en desc, cn.id desc limit 501) x;
  return jsonb_build_object('notas', v, 'recortado', n > 500);
end $function$;

drop function if exists public._unidades_notas_a_historial();
drop function if exists public._unidades_notas_al_borrar();
drop function if exists public.unidad_notas_datos(uuid);
drop function if exists public.unidad_nota_agrega(uuid, text);
drop function if exists public.unidad_nota_retira(bigint, text);
drop function if exists public._unidad_notas_editor(uuid);
drop function if exists public._unidad_notas_admin(uuid);
drop function if exists public._cliente_notas_admin(uuid);
drop table if exists public.unidad_notas_retiradas;
drop table if exists public.unidad_notas;
drop function if exists public._unidad_ficha_ve(uuid);
drop function if exists public._unidad_notas_inmutable();
drop function if exists public._unidad_notas_retiradas_solo_anade();
-- ======================== fin de la copia ========================
do $todo$
declare
  r text := '';
  u1 uuid := (select id from _ur where et = 'u1');
  u2 uuid := (select id from _ur where et = 'u2');
  c_fin constant text := 'FIN DE PRUEBAS REVERSION NOTAS DE PARCELA (se deshace todo):%';
  v text;
begin
  r := r || E'\n' || 'R1 la parcela con dos notas las recupera en notas, la mas reciente arriba' ||
       case when (select notas from public.unidades where id = u1) = 'ZZ-UR segunda' || E'\n\n' || 'ZZ-UR primera' then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R2 la parcela sin notas sigue con notas vacio' ||
       case when (select notas from public.unidades where id = u2) is null then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R3 las tablas unidad_notas y unidad_notas_retiradas ya no existen' ||
       case when to_regclass('public.unidad_notas') is null and to_regclass('public.unidad_notas_retiradas') is null then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R4 las funciones nuevas ya no existen' ||
       case when not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                               and p.proname in ('unidad_notas_datos', 'unidad_nota_agrega', 'unidad_nota_retira', '_unidad_ficha_ve',
                                                 '_unidad_notas_editor', '_unidad_notas_admin', '_cliente_notas_admin',
                                                 '_unidades_notas_a_historial', '_unidades_notas_al_borrar', '_unidad_notas_inmutable',
                                                 '_unidad_notas_retiradas_solo_anade')) then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R5 el check y los dos disparadores de unidades ya no existen' ||
       case when not exists (select 1 from pg_constraint where conrelid = 'public.unidades'::regclass and conname = 'unidades_notas_al_historial')
                 and not exists (select 1 from pg_trigger where tgrelid = 'public.unidades'::regclass
                                   and tgname in ('trg_unidades_notas_a_historial', 'trg_unidades_notas_al_borrar')) then ' → ok' else ' → FALLA' end;
  select md5(p.prosrc) || '|' || pg_get_userbyid(p.proowner) || '|' || has_function_privilege('authenticated', p.oid, 'execute')::text
                       || '|' || has_function_privilege('anon', p.oid, 'execute')::text
    into v from pg_proc p where p.oid = 'public.cliente_notas_datos(uuid)'::regprocedure;
  r := r || E'\n' || 'R6 cliente_notas_datos vuelve a su md5 de la viva, con dueño lw_lector, authenticated si y anon no (' || coalesce(v, 'null') || ')' ||
       case when v = '4942e7bd0e0f91a49ef479929711e4d5|lw_lector|true|false' then ' → ok' else ' → FALLA' end;
  update public.unidades set notas = 'ZZ-UR tras revertir' where id = u2;
  r := r || E'\n' || 'R7 sin el disparador ni el check, unidades.notas vuelve a guardarse como antes' ||
       case when (select notas from public.unidades where id = u2) = 'ZZ-UR tras revertir' then ' → ok' else ' → FALLA' end;
  raise exception using message = replace(c_fin, '%', r);
end $todo$;
