-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- destructivo-ok: retira la firma de 3 argumentos de equipo_venta_guarda (la reemplaza la de 4, con p_empresa opcional); no toca datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b9.sql
-- Fase 2 · bloque 9 (7-oct-2026): `equipo_venta_guarda` con empresa elegible al crear un equipo nuevo.
--   Una sola funcion (nada de sobrecarga: dos firmas con defaults solapados dan PGRST203): (p_id, p_nombre, p_manager_email, p_empresa text default null).
--   La llamada de 3 argumentos sigue valiendo. Con p_empresa nulo: igual que hoy (editar = la empresa del equipo; nuevo = la unica del llamador;
--   nuevo y global = lawang) salvo que quien llama gestiona VARIAS empresas: 22023 «indica en cual».
--   Con p_empresa informado (equipo nuevo): tiene que ser una empresa que existe y que el llamador gobierna (es_admin_de, que es la puerta de siempre),
--   y el manager tiene que poder vender en ella (regla 4 del bloque 4). Al editar, la empresa del equipo no se cambia: si no coincide, 22023.
--   Llamador con nombre: intranet/v4/assets/editores.js (nuevo-equipo y editar equipo). EXECUTE solo authenticated.
drop function if exists public.equipo_venta_guarda(uuid, text, text);

create or replace function public.equipo_venta_guarda(p_id uuid, p_nombre text, p_manager_email text, p_empresa text default null)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v_old public.equipos_venta%rowtype; v_id uuid; v_n int := 0;
  v_man text := nullif(lower(btrim(coalesce(p_manager_email, ''))), '');
  v_nom text := nullif(btrim(coalesce(p_nombre, '')), '');
  v_pide text := nullif(btrim(coalesce(p_empresa, '')), '');
  v_emp text; v_mias text[];
begin
  v_emp := public.empresa_de_equipo(p_id);
  if p_id is not null and v_emp is not null then
    if v_pide is not null and v_pide <> v_emp then
      raise exception 'La empresa de un equipo no se cambia' using errcode = '22023';
    end if;
  elsif v_pide is not null then
    if not exists (select 1 from public.empresas e where e.clave = v_pide) then
      raise exception 'Esa empresa no existe' using errcode = '22023';
    end if;
    v_emp := v_pide;
  else
    select coalesce(u.empresas, '{}') into v_mias from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
    if cardinality(coalesce(v_mias, '{}')) = 1 then v_emp := v_mias[1];
    elsif cardinality(coalesce(v_mias, '{}')) > 1 and not public.es_admin() then
      raise exception 'Gestionas varias empresas: indica en cuál va el equipo' using errcode = '22023';
    else v_emp := 'lawang';
    end if;
  end if;
  if not public.es_admin_de(v_emp) then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_man is not null and exists (select 1 from public.usuarios u where lower(u.email) = v_man and u.activo
                                    and cardinality(coalesce(u.empresas, '{}')) > 0 and not (v_emp = any (u.empresas))) then
    raise exception 'El manager no vende en la empresa de este equipo' using errcode = '22023';
  end if;
  if v_nom is null then raise exception 'Falta el nombre del equipo' using errcode = '22023'; end if;
  if v_man is null or not public._usuario_activo(v_man) then
    raise exception 'El manager tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if v_man = lower(coalesce((select auth.email()), '')) and not public.es_super_admin_de(v_emp) then
    raise exception 'Nadie se pone a sí mismo de manager de un equipo' using errcode = '42501';
  end if;
  if p_id is null then
    insert into public.equipos_venta (nombre, manager_email, empresa) values (v_nom, v_man, v_emp) returning id into v_id;
    insert into public.equipos_log (tabla, fila_id, antes, despues)
    select 'equipos_venta', v_id, null, to_jsonb(e) from public.equipos_venta e where e.id = v_id;
    return v_id;
  end if;
  select * into v_old from public.equipos_venta e where e.id = p_id for update;
  if not found then raise exception 'Ese equipo no existe' using errcode = 'P0002'; end if;
  if lower(v_old.manager_email) is distinct from v_man then
    v_n := public._equipo_congela_ventas(p_id, null);
  end if;
  update public.equipos_venta set nombre = v_nom, manager_email = v_man where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  select 'equipos_venta', p_id, to_jsonb(v_old), to_jsonb(e), v_n from public.equipos_venta e where e.id = p_id;
  return p_id;
end $function$;

revoke all on function public.equipo_venta_guarda(uuid, text, text, text) from public, anon;
grant execute on function public.equipo_venta_guarda(uuid, text, text, text) to authenticated;
