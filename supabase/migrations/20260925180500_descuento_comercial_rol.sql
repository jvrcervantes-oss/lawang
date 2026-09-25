-- Descuento comercial: quién puede ponerlo, ahora también en la base.
--
-- 25-sep-2026, owner: el descuento comercial y su motivo (Construcción y
-- Bloqueo de Parcela) pasan de admin/super_admin a admin/super_admin/
-- sales_manager (ROLES_FIJOS_ESTUDIO en contracts/app.html). Hasta hoy el rol
-- solo lo frenaba la pantalla: los triggers de 21 y 25-sep comprueban el 15% y
-- el motivo, y su propio comentario dice «NO valida el rol de quien escribe».
-- Al abrir el campo a quien negocia el precio, el candado de rol baja a la
-- base para que un agente no lo salte llamando a la API.
--
-- Qué hace: si quien escribe es un usuario con sesión y su rol NO es
-- super_admin/admin/sales_manager, rechaza CAMBIAR descuento_comercial o
-- descuento_comercial_motivo (en un insert: ponerlos no vacíos). Guardar un
-- contrato que ya traía descuento sin tocarlo sigue funcionando — hoy hay uno
-- así, creado por un agente y con el descuento puesto por dirección.
-- Sin sesión (auth.uid() null: edge functions con service role) no se aplica.
--
-- Seguro: solo crea función y trigger nuevos.

create or replace function public.descuento_comercial_rol()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rol text;
  v_dc_new numeric := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  v_mo_new text    := coalesce(nullif(trim(new.datos->'fields'->>'descuento_comercial_motivo'), ''), '');
  v_dc_old numeric := 0;
  v_mo_old text    := '';
begin
  if (select auth.uid()) is null then return new; end if;
  select u.rol into v_rol from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
  if v_rol in ('super_admin', 'admin', 'sales_manager') then return new; end if;
  if tg_op = 'UPDATE' then
    v_dc_old := coalesce(public.lw_importe(old.datos->'fields'->>'descuento_comercial'), 0);
    v_mo_old := coalesce(nullif(trim(old.datos->'fields'->>'descuento_comercial_motivo'), ''), '');
  end if;
  if v_dc_new is distinct from v_dc_old or v_mo_new is distinct from v_mo_old then
    raise exception 'El descuento comercial y su motivo solo los ponen dirección y los sales managers.'
      using errcode = '42501';
  end if;
  return new;
end
$function$;

revoke execute on function public.descuento_comercial_rol() from public, anon, authenticated;

create trigger trg_descuento_comercial_rol
  before insert or update on public.contratos
  for each row execute function public.descuento_comercial_rol();

comment on function public.descuento_comercial_rol() is
  'BEFORE INSERT OR UPDATE en contratos: solo super_admin/admin/sales_manager cambian descuento_comercial y su motivo. Sin sesión no aplica. 25-sep-2026, owner.';
