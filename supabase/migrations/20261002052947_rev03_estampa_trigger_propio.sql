-- Cláusulas negociadas REV03: las claves derivadas, en su propio trigger y en su sitio.
--
-- 2-oct-2026, segunda ronda del revisor de código sobre 20261002052529:
--  1. Postgres dispara los BEFORE por orden alfabético: estampando dentro de
--     trg_clausulas_negociadas_rol, rev03_dni se calculaba con el adq1_tipo que
--     mandaba el navegador, ANTES de que trg_espejo_comprador lo corrija con la
--     ficha. Ahora lo hace trg_rev03_estampa, que va detrás de trg_espejo_* y
--     delante de zz_contrato_datos_fields (la regla de 20260926210000).
--  2. Reescribía datos entero en cada guardado de cualquier contrato (TOAST:
--     537 kB de media, medido el 26-sep). Ahora solo asigna si el valor cambia o
--     si hay claves que quitar, y el trigger es UPDATE OF datos.
-- El trigger de rol vuelve a ser solo de rol.
--
-- Seguro: reemplaza la función de hoy y crea un trigger nuevo; sin DDL destructivo.

-- 1. El trigger de rol vuelve a ser SOLO de rol (como 20261002051803).
create or replace function public.clausulas_negociadas_rol()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rol text;
  v_new text := coalesce(nullif(trim(new.datos->'fields'->>'clausulas_negociadas'), ''), '');
  v_old text := '';
begin
  if (select auth.uid()) is null then return new; end if;
  if tg_op = 'UPDATE' then
    v_old := coalesce(nullif(trim(old.datos->'fields'->>'clausulas_negociadas'), ''), '');
  end if;
  if v_new is not distinct from v_old then return new; end if;
  select u.rol into v_rol from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
  if v_rol in ('super_admin', 'admin') then return new; end if;
  raise exception 'Las cláusulas negociadas solo las activan o retiran dirección (admin).'
    using errcode = '42501';
end
$function$;

revoke execute on function public.clausulas_negociadas_rol() from public, anon, authenticated;

comment on function public.clausulas_negociadas_rol() is
  'BEFORE INSERT OR UPDATE en contratos: solo super_admin/admin cambian datos.fields.clausulas_negociadas (REV03 negociado con un comprador). Sin sesión no aplica. Las claves derivadas las estampa trg_rev03_estampa. 2-oct-2026, owner.';

-- 2. Claves derivadas, en su propio trigger y en su sitio del orden.
create or replace function public.rev03_estampa()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  f jsonb := new.datos->'fields';
  v_dni text;
  v_hgb text;
begin
  if jsonb_typeof(f) is distinct from 'object' then return new; end if;
  if coalesce(f->>'clausulas_negociadas', '') = 'si' then
    v_dni := case when f->>'adq1_tipo' = 'persona' then 'si' else '' end;
    v_hgb := case when f->>'regimen_tenencia' = 'leasehold' then 'si' else '' end;
    if (f->>'rev03_dni') is distinct from v_dni then
      new.datos := jsonb_set(new.datos, '{fields,rev03_dni}', to_jsonb(v_dni));
    end if;
    if (f->>'rev03_hgb') is distinct from v_hgb then
      new.datos := jsonb_set(new.datos, '{fields,rev03_hgb}', to_jsonb(v_hgb));
    end if;
  elsif f ? 'rev03_dni' or f ? 'rev03_hgb' then
    new.datos := new.datos #- '{fields,rev03_dni}' #- '{fields,rev03_hgb}';
  end if;
  return new;
end
$function$;

revoke execute on function public.rev03_estampa() from public, anon, authenticated;

create trigger trg_rev03_estampa
  before insert or update of datos on public.contratos
  for each row execute function public.rev03_estampa();

comment on function public.rev03_estampa() is
  'BEFORE INSERT OR UPDATE OF datos en contratos: estampa rev03_dni (REV03 y persona) y rev03_hgb (REV03 y leasehold) desde los campos ya corregidos por trg_espejo_comprador (va detrás por orden alfabético y delante de zz_contrato_datos_fields). Solo escribe datos si algo cambia. 2-oct-2026.';
