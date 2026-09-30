-- destructivo-ok: owner 30-sep-2026 («si, aplica»): borrar 3 funciones sin llamador (fuga modelo_precio_construccion); backup datos hecho 09:51
-- 30-sep-2026 · Limpieza de superficie de la base (orden explicita del owner: «si, aplica»).
-- Auditoria de Seguridad, ya verificada. Regla: «reducir la exposicion» (CLAUDE.md): sin llamador con nombre, se revoca o se quita.
--
-- a) modelo_precio_construccion(uuid,uuid): FUGA REAL. SECURITY DEFINER sin gate: cualquier sesion leia el precio de construccion.
--    Sin llamadores (ni front, ni edges, ni otras funciones, ni policies, ni vistas). Se revoca y se borra.
-- b) modelo_ficha_guarda(...): sin llamador en el producto (solo un script de prueba). Se revoca y se borra.
-- c) _sc_visible(text,uuid): sin llamador. Se revoca y se borra.
-- d) borrar_unidad(uuid) y tipo_vivienda_alta(text,text): se REVOCA a authenticated/anon/public y NO se borran
--    (borrar_unidad la usa tools/flujos_lawang.py como postgres). La UI no las llama.
-- e) lw_orden_natural: NO se toca (la usa la columna generada unidades.codigo_orden).
-- f) crm_lead_mover: faltaba lead_a_mi_alcance(), el mismo gate que crm_lead_nota / crm_lead_accion_poner (mismo mensaje y
--    orden: primero puede('leads'), luego alcance, luego identidad). El listado del kanban (crm_leads) ya filtra por
--    lead_a_mi_alcance, asi que quien ve una tarjeta sigue pudiendo moverla; solo se cierra mover leads AJENOS por RPC.
-- Inversa: contracts/sql/inversa_limpieza_superficie_20260930.sql

revoke execute on function public.modelo_precio_construccion(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.modelo_ficha_guarda(uuid, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public._sc_visible(text, uuid) from public, anon, authenticated;
drop function public.modelo_precio_construccion(uuid, uuid);
drop function public.modelo_ficha_guarda(uuid, jsonb, jsonb, jsonb, jsonb);
drop function public._sc_visible(text, uuid);

revoke execute on function public.borrar_unidad(uuid) from public, anon, authenticated;
revoke execute on function public.tipo_vivienda_alta(text, text) from public, anon, authenticated;

create or replace function public.crm_lead_mover(p_lead uuid, p_estado text, p_desde timestamp with time zone)
 returns table(lead_id uuid, estado text, estado_desde timestamp with time zone, responsable text)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_quien  text := coalesce((select auth.email()), '');
  v_actual text;
  v_desde  timestamptz;
  v_alta   timestamptz;
  v_ahora  timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_estado, 1));

  if not exists (select 1 from public.lead_estados where clave = p_estado) then
    raise exception 'Estado desconocido: %', p_estado using errcode = 'PT400';
  end if;

  select l.created_at into v_alta from public.leads l where l.id = p_lead;
  if v_alta is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  select e.estado, e.estado_desde into v_actual, v_desde
    from public.lead_estado e where e.lead_id = p_lead;
  v_actual := coalesce(v_actual, 'nuevo');
  v_desde  := coalesce(v_desde, v_alta);

  if p_desde is null or v_desde is distinct from p_desde then
    raise exception 'La tarjeta la ha movido otra persona' using errcode = 'PT409';
  end if;

  if v_actual = p_estado then
    return query select p_lead, v_actual, v_desde,
                        (select e.responsable from public.lead_estado e where e.lead_id = p_lead);
    return;
  end if;

  update public.lead_estado e
     set estado = p_estado, responsable = v_quien,
         estado_desde = v_ahora, actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, responsable, estado_desde, actualizado)
         values (p_lead, p_estado, v_quien, v_ahora, v_ahora);
  end if;

  insert into public.lead_estado_log (lead_id, de, a, autor)
       values (p_lead, v_actual, p_estado, v_quien);

  return query
    select e.lead_id, e.estado, e.estado_desde, e.responsable
      from public.lead_estado e where e.lead_id = p_lead;
end;
$function$;
