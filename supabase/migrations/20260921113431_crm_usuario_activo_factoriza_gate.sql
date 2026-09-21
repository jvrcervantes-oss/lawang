-- Factoriza el gate "es un usuario activo real" — code-review lo cazó duplicado
-- verbatim entre `crm_contrato_closer_semilla()` (el trigger de alta,
-- 20260921111614) y `crm_contrato_closer_set()` (20260911020137): la misma
-- comprobación `exists (select 1 from usuarios u where lower(u.email)=lower(...)
-- and u.activo)` copiada en dos sitios distintos que solo iban a divergir en
-- silencio el día que la regla de negocio cambiara (excluir un rol, un estado
-- "activo pero suspendido", normalizar dominios...). Se saca a una función y
-- las dos llamadas la usan.
--
-- destructivo-ok: el `delete from public.contrato_closer` de más abajo, dentro
-- del cuerpo de `crm_contrato_closer_set`, YA vive en producción sin cambios
-- (migración 20260911020137) — se re-escribe entero solo porque CREATE OR
-- REPLACE exige el cuerpo completo de la función; el único cambio real de esa
-- función es sustituir su `exists (...)` inline por `crm_usuario_activo(...)`.
create or replace function public.crm_usuario_activo(p_email text)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select exists (
    select 1 from public.usuarios u
     where lower(u.email) = lower(coalesce(p_email, '')) and u.activo
  );
$$;

revoke execute on function public.crm_usuario_activo(text) from public, anon;
grant execute on function public.crm_usuario_activo(text) to authenticated;

-- El trigger de alta pasa a usar la función compartida (mismo comportamiento,
-- ninguna regla nueva).
create or replace function public.crm_contrato_closer_semilla()
returns trigger
language plpgsql volatile security definer set search_path to ''
as $$
begin
  if NEW.contrato_padre_id is not null then
    return NEW;
  end if;

  if NEW.creado_por is null then
    return NEW;
  end if;

  if not public.crm_usuario_activo(NEW.creado_por) then
    return NEW;
  end if;

  insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
       values (NEW.id, NEW.creado_por, 'sistema:alta', now())
  on conflict (contrato_id) do nothing;

  if found then
    insert into public.contrato_closer_log (contrato_id, de, a, autor)
         values (NEW.id, null, NEW.creado_por, 'sistema:alta');
  end if;

  return NEW;
end;
$$;

-- crm_contrato_closer_set (11-sep) pasa a usar la misma función compartida.
-- CREATE OR REPLACE conserva los grants existentes: no hace falta re-otorgar
-- EXECUTE a authenticated, ya lo tenía.
create or replace function public.crm_contrato_closer_set(
  p_contrato uuid, p_email text, p_previo text default null
)
returns table (contrato_id uuid, closer_email text, asignado_por text, asignado_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien   text := coalesce((select auth.email()), '');
  v_destino text := nullif(btrim(coalesce(p_email, '')), '');
  v_actual  text;
  v_ahora   timestamptz := now();
begin
  if not (public.puede('ranking') or public.es_admin()) then
    raise exception 'Sin permiso para atribuir ventas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then
    raise exception 'Ese contrato no existe' using errcode = 'PT404';
  end if;
  if v_destino is not null and not public.crm_usuario_activo(v_destino) then
    raise exception 'Esa persona no esta activa en la intranet' using errcode = 'PT400';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_contrato::text, 2));

  select k.closer_email into v_actual
    from public.contrato_closer k where k.contrato_id = p_contrato;

  if v_actual is distinct from p_previo then
    raise exception 'La atribucion de este contrato ya no es la que tenias'
      using errcode = 'PT409';
  end if;

  if v_destino is null then
    delete from public.contrato_closer k where k.contrato_id = p_contrato;
  else
    update public.contrato_closer k
       set closer_email = v_destino, asignado_por = v_quien, asignado_en = v_ahora
     where k.contrato_id = p_contrato;
    if not found then
      insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
           values (p_contrato, v_destino, v_quien, v_ahora);
    end if;
  end if;

  insert into public.contrato_closer_log (contrato_id, de, a, autor)
       values (p_contrato, v_actual, v_destino, v_quien);

  return query
    select k.contrato_id, k.closer_email, k.asignado_por, k.asignado_en
      from public.contrato_closer k where k.contrato_id = p_contrato;
end;
$$;
;
