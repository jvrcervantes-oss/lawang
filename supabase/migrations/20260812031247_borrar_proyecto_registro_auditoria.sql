-- destructivo-ok: la función sustituida (CREATE OR REPLACE) sigue teniendo un
-- DELETE dentro — es la misma función ya en producción (borrar_proyecto),
-- detrás del mismo gate de rol + bloqueo por dependientes de siempre. Este
-- migration solo AÑADE la tabla de auditoría y el INSERT que deja rastro
-- antes de borrar; no cambia qué se puede borrar ni quién puede hacerlo.
--
-- Hallazgos Legal (12-ago, sobre borrar_proyecto): sin rastro de quién borró
-- y cuándo, y nada impide reutilizar el mismo nombre después dejando
-- contratos/facturas antiguos indistinguibles de una operación nueva con el
-- mismo nombre. Se añade un log de solo-lectura (no bloquea el borrado, deja
-- rastro) — la reutilización del nombre sigue permitida a propósito: bloquearla
-- no se pidió y un proyecto puede legítimamente reaparecer más adelante.

create table public.proyectos_borrados (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  resort text,
  borrado_por text not null,
  borrado_en timestamptz not null default now()
);

alter table public.proyectos_borrados enable row level security;

create policy "proyectos borrados: solo con sesion"
  on public.proyectos_borrados for select
  to authenticated
  using (true);

revoke all on public.proyectos_borrados from public, anon, authenticated;
grant select on public.proyectos_borrados to authenticated;

create or replace function public.borrar_proyecto(p_nombre text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unidades int; v_modelos int; v_documentos int; v_resort text;
begin
  if not public.es_super_admin() then
    raise exception 'solo un super_admin puede borrar un proyecto' using errcode = '42501';
  end if;

  select count(*) into v_unidades from public.unidades where proyecto = p_nombre;
  if v_unidades > 0 then
    raise exception 'el proyecto tiene % unidad(es) dadas de alta — bórralas o muévelas primero', v_unidades using errcode = '23503';
  end if;

  select count(*) into v_modelos from public.modelos_villa where proyecto = p_nombre;
  if v_modelos > 0 then
    raise exception 'el proyecto tiene % modelo(s) de villa — bórralos primero', v_modelos using errcode = '23503';
  end if;

  select count(*) into v_documentos from public.documentos_proyecto where proyecto = p_nombre;
  if v_documentos > 0 then
    raise exception 'el proyecto tiene % documento(s) subido(s) — bórralos primero', v_documentos using errcode = '23503';
  end if;

  select resort into v_resort from public.proyectos where nombre = p_nombre;

  -- destructivo-ok: rastro ANTES de borrar (hallazgo Legal, 12-ago) — quién y
  -- cuándo, para poder explicar más adelante por qué un contrato antiguo
  -- nombra un proyecto que ya no está en el catálogo.
  insert into public.proyectos_borrados (nombre, resort, borrado_por)
  values (p_nombre, v_resort, coalesce((select auth.email()), (select auth.uid())::text));

  delete from public.proyectos where nombre = p_nombre;
  if not found then
    raise exception 'no existe un proyecto con ese nombre' using errcode = '23503';
  end if;
end;
$$;

revoke all on function public.borrar_proyecto(text) from public, anon;
grant execute on function public.borrar_proyecto(text) to authenticated;;
