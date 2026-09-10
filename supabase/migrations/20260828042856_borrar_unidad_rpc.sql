-- destructivo-ok: crea una FUNCION (constructivo) y una tabla de auditoria. El
-- DELETE que hay dentro esta detras de un gate de rol (solo super_admin) y de
-- un bloqueo si la parcela tiene un contrato o fotos de obra colgando -- mismo
-- patron que borrar_proyecto, que ya dejaba escrito "borralas o muevelas
-- primero" sin que existiera esta funcion. Peticion del owner (28-ago-2026).

create table public.unidades_borradas (
  id uuid primary key default gen_random_uuid(),
  unidad_id uuid not null,
  codigo text,
  proyecto text,
  tipo text,
  precio numeric,
  moneda text,
  borrado_por text not null,
  borrado_en timestamptz not null default now()
);

alter table public.unidades_borradas enable row level security;

create policy "unidades borradas: solo con sesion"
  on public.unidades_borradas for select
  to authenticated
  using (true);

revoke all on public.unidades_borradas from public, anon, authenticated;
grant select on public.unidades_borradas to authenticated;

create or replace function public.borrar_unidad(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_codigo text; v_proyecto text; v_tipo text; v_precio numeric; v_moneda text;
  v_contratos int; v_fotos int;
begin
  if not public.es_super_admin() then
    raise exception 'solo un super_admin puede borrar una parcela' using errcode = '42501';
  end if;

  select codigo, proyecto, tipo, precio, moneda
    into v_codigo, v_proyecto, v_tipo, v_precio, v_moneda
    from public.unidades where id = p_id;
  if not found then
    raise exception 'no existe una parcela con ese id' using errcode = '23503';
  end if;

  select count(*) into v_contratos from public.contratos where unidad_id = p_id;
  if v_contratos > 0 then
    raise exception 'la parcela tiene % contrato(s) -- sueltala del contrato o borralo primero', v_contratos using errcode = '23503';
  end if;

  select count(*) into v_fotos from public.obra_fotos where unidad_id = p_id;
  if v_fotos > 0 then
    raise exception 'la parcela tiene % foto(s) de obra -- borralas primero', v_fotos using errcode = '23503';
  end if;

  -- destructivo-ok: rastro ANTES de borrar, mismo criterio que
  -- proyectos_borrados (hallazgo Legal, 12-ago) -- quien y cuando.
  insert into public.unidades_borradas (unidad_id, codigo, proyecto, tipo, precio, moneda, borrado_por)
  values (p_id, v_codigo, v_proyecto, v_tipo, v_precio, v_moneda,
          coalesce((select auth.email()), (select auth.uid())::text));

  -- destructivo-ok: DELETE de UNA fila, detras del gate de super_admin y de
  -- los dos bloqueos de arriba (contrato / fotos de obra) -- el borrado que
  -- pidio el owner, no un borrado masivo.
  delete from public.unidades where id = p_id;
end;
$$;

revoke all on function public.borrar_unidad(uuid) from public, anon;
grant execute on function public.borrar_unidad(uuid) to authenticated;;
