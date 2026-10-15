-- Prueba de la VUELTA ATRAS de 20261015075011_cliente_notas (15-oct-2026; la pidio Base de datos: nunca se habia ejecutado).
-- Siembra fichas con notas, ejecuta el texto de supabase/reversion_cliente_notas/REVERSION.sql TAL CUAL (copiado abajo por
-- el autor; si la REVERSION cambia, se vuelve a copiar) y comprueba: las notas vuelven a clients.notes, las tablas y funciones
-- nuevas desaparecen y las tres funciones reescritas vuelven a su md5 de la viva del 15-oct.
--    python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261015075011_cliente_notas.sql --prueba cliente_notas_reversion.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-CR.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create temp table _cr (et text primary key, id uuid);
do $siembra$
declare c1 uuid; c2 uuid;
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS REVERSION NOTAS:%', E'\nR0 esta prueba borra tablas: solo corre en rama → FALLA';
  end if;
  insert into public.clients (full_name, email, notes) values ('ZZ-CR UNO', 'zz-cr-1@prueba.invalid', 'ZZ-CR primera') returning id into c1;
  update public.clients set notes = 'ZZ-CR segunda' where id = c1;
  insert into public.clients (full_name, email) values ('ZZ-CR DOS', 'zz-cr-2@prueba.invalid') returning id into c2;
  insert into _cr values ('c1', c1), ('c2', c2);
end $siembra$;

-- ======================== desde aqui, copia literal de supabase/reversion_cliente_notas/REVERSION.sql ========================
-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015075011_cliente_notas.sql (15-oct-2026, sesion notas-cliente).
-- ORDEN: 1) front de la ficha a su version anterior (git revert del commit de las notas: vuelve el campo «Notas» al editor),
-- 2) ESTE fichero, en una transaccion. Al reves, la pantalla llamaria a funciones que ya no existen.
-- Antes de borrar las tablas, cada ficha recupera en clients.notes sus notas (todas las que tenga, la mas reciente arriba,
-- separadas por una linea en blanco): ninguna nota escrita entre medias se pierde. La traza de retiradas se pierde con su
-- tabla (no tiene texto). _kyc_retencion_candidato vuelve LITERAL a la viva del 15-oct (md5(prosrc) 206cb44b7784b6142164499c62b9696d).
-- destructivo-ok: borra las tablas y funciones que creo la migracion despues de devolver su texto a clients.notes
set local lock_timeout = '5s';
-- la FK de cliente_notas.client_id es diferible: si en esta misma transacción quedan comprobaciones pendientes, DROP TABLE
-- falla («pending trigger events»; lo cazó la prueba de la vuelta atrás, 15-oct). Se resuelven ahora.
set constraints all immediate;

do $pre$
begin
  if to_regclass('public.cliente_notas') is null then
    raise exception 'cliente_notas no existe: no hay nada que revertir';
  end if;
end $pre$;

drop trigger if exists trg_clients_notas_a_historial on public.clients;
-- _sc_columnas_clients vuelve LITERAL a la viva del 15-oct (md5(prosrc) 76cb573a409cda72958757444ba0dcc5)
CREATE OR REPLACE FUNCTION public._sc_columnas_clients()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array['tipo','kyc_status','full_name','email','phone','nationality','passport_number',
               'idioma_comunicacion','forma_juridica','registro_num','rep_nombre','rep_cargo','notes']
$function$;
-- _sc_referencias_cliente vuelve LITERAL a la viva del 15-oct (md5(prosrc) 6c0b820ddfaa73c8ac166a892e048627)
CREATE OR REPLACE FUNCTION public._sc_referencias_cliente(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  n bigint;
  v jsonb := '{}'::jsonb;
begin
  for r in
    select c.conrelid::regclass::text as tabla, a.attname as col
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
     where c.contype = 'f' and c.confrelid = 'public.clients'::regclass
  loop
    execute format('select count(*) from %s where %I = $1', r.tabla, r.col) into n using p_id;
    if n > 0 then v := v || jsonb_build_object(r.tabla, n); end if;
  end loop;
  select count(*) into n from public.contratos where adq1_client_id = p_id;
  if n > 0 then v := v || jsonb_build_object('contratos', n); end if;
  return v;
end
$function$;
drop trigger if exists trg_clients_notas_al_borrar on public.clients;

update public.clients c
   set notes = s.texto
  from (select n.client_id, string_agg(n.texto, E'\n\n' order by n.creado_en desc, n.id desc) as texto
          from public.cliente_notas n group by n.client_id) s
 where s.client_id = c.id;

drop function if exists public._clients_notas_a_historial();
drop function if exists public._clients_notas_al_borrar();
drop function if exists public.cliente_notas_datos(uuid);
drop function if exists public.cliente_nota_agrega(uuid, text);
drop function if exists public.cliente_nota_retira(bigint, text);
drop function if exists public._cliente_ficha_ve(uuid);
drop table if exists public.cliente_notas_retiradas;
drop table if exists public.cliente_notas;
drop function if exists public._cliente_notas_inmutable();
drop function if exists public._cliente_notas_retiradas_solo_anade();

CREATE OR REPLACE FUNCTION public._kyc_retencion_candidato(p_id uuid, p_corte timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ult timestamptz;
begin
  if not exists (select 1 from public.documents d where d.client_id = p_id and d.retirado_el is null
                   and d.doc_type in ('passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'other')) then
    return false;
  end if;
  if exists (select 1 from public.documents d where d.client_id = p_id
               and (d.doc_type = 'signed_contract' or d.contrato_id is not null or d.reservation_id is not null)) then
    return false;
  end if;
  select greatest(c.created_at, c.kyc_verificado_el,
                  (select max(d.uploaded_at) from public.documents d where d.client_id = c.id),
                  (select max(cd.corregido_en) from public.correcciones_datos cd where cd.tabla = 'clients' and cd.fila_id = c.id))
    into v_ult from public.clients c where c.id = p_id;
  if v_ult is null or v_ult >= p_corte then return false; end if;
  return (public._sc_referencias_cliente(p_id) - 'public.documents') = '{}'::jsonb;
end $function$;

-- ======================== fin de la copia ========================
do $todo$
declare
  r text := '';
  c1 uuid := (select id from _cr where et = 'c1');
  c2 uuid := (select id from _cr where et = 'c2');
  c_fin constant text := 'FIN DE PRUEBAS REVERSION NOTAS (se deshace todo):%';
  md5f text;
begin
  r := r || E'\n' || 'R1 la ficha con dos notas las recupera en notes, la mas reciente arriba' ||
       case when (select notes from public.clients where id = c1) = 'ZZ-CR segunda' || E'\n\n' || 'ZZ-CR primera' then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R2 la ficha sin notas sigue con notes vacio' ||
       case when (select notes from public.clients where id = c2) is null then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R3 las tablas cliente_notas y cliente_notas_retiradas ya no existen' ||
       case when to_regclass('public.cliente_notas') is null and to_regclass('public.cliente_notas_retiradas') is null then ' → ok' else ' → FALLA' end;
  r := r || E'\n' || 'R4 las funciones nuevas ya no existen' ||
       case when not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                               and p.proname in ('cliente_notas_datos','cliente_nota_agrega','cliente_nota_retira','_cliente_ficha_ve',
                                                 '_clients_notas_a_historial','_clients_notas_al_borrar','_cliente_notas_inmutable',
                                                 '_cliente_notas_retiradas_solo_anade')) then ' → ok' else ' → FALLA' end;
  select string_agg(p.proname || '=' || md5(p.prosrc), ',' order by p.proname) into md5f from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('_kyc_retencion_candidato','_sc_referencias_cliente','_sc_columnas_clients');
  r := r || E'\n' || 'R5 las tres reescritas vuelven a su md5 de la viva (' || coalesce(md5f, 'null') || ')' ||
       case when md5f = '_kyc_retencion_candidato=206cb44b7784b6142164499c62b9696d,_sc_columnas_clients=76cb573a409cda72958757444ba0dcc5,'
                        || '_sc_referencias_cliente=6c0b820ddfaa73c8ac166a892e048627' then ' → ok' else ' → FALLA' end;
  update public.clients set notes = 'ZZ-CR tras revertir' where id = c2;
  r := r || E'\n' || 'R6 sin el disparador, clients.notes vuelve a guardarse como antes' ||
       case when (select notes from public.clients where id = c2) = 'ZZ-CR tras revertir' then ' → ok' else ' → FALLA' end;
  raise exception using message = replace(c_fin, '%', r);
end $todo$;
