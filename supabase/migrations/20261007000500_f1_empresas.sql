-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 1 del encargo «empresas» (Sandal Woods matriz + Lawang promotora), 7-oct-2026. SOLO ETIQUETA: nadie ve ni puede nada distinto.
--   Tabla `empresas` (lawang ↔ sociedad tepi_sungai · sandal_woods ↔ san_dal_woods), `proyectos.empresa` (UN campo, nulo = cerrado),
--   reparto por `resort` (20 / 12 / 1 nulo), `empresa_de_proyecto(id)` y `proyecto_empresa_guarda` (solo super_admin).
-- Verificado antes: trg_proyecto_renombrado dispara en UPDATE OF nombre y trg_proyecto_slug en INSERT OR UPDATE OF slug; el backfill
--   hace UPDATE OF empresa, asi que NINGUNO de los dos se dispara (ensayado con md5 de facturas/contratos/unidades/comision_admin_lineas).
-- Sin indice sobre proyectos.empresa: 33 filas; se anade cuando la Fase 2 filtre por empresa.
-- No hay RPC de escritura de `empresas`: sin llamador no se expone (reducir la exposicion); las dos filas son semilla.
-- destructivo-ok: solo crea tabla/columna/funciones y rellena una columna nueva; no borra ni cambia filas existentes de otras tablas.
-- REVERTIR (en este orden):
--   drop function public.proyecto_empresa_guarda(uuid, text); drop function public.empresa_de_proyecto(uuid);
--   drop trigger trg_proyecto_empresa on public.proyectos; drop function public.trg_proyecto_empresa();
--   alter table public.proyectos drop column empresa; drop table public.empresas; drop function public.trg_empresa_clave_fija();

create table public.empresas (
  clave          text primary key check (clave ~ '^[a-z][a-z0-9_]{2,40}$'),
  nombre         text not null check (btrim(nombre) <> ''),
  sociedad_clave text unique references public.sociedades(clave),
  activa         boolean not null default true,
  orden          integer not null default 0,
  creado_en      timestamptz not null default now()
);
comment on table public.empresas is
  'Empresa que CONTROLA un proyecto (lawang = promotora, sandal_woods = matriz patrimonial). No es la sociedad que factura: sociedad_clave la enlaza con `sociedades` (lawang -> tepi_sungai, sandal_woods -> san_dal_woods). La clave no se edita nunca. '
  'PENDIENTE (Administracion, 6-oct-2026, no implementado a proposito): atributos por empresa que no deben cerrar el diseno de series y retenciones (LAW-235) -> serie/prefijo de numeracion, datos de retencion (PKP/PPh) y numeracion intercompania; hoy viven globales o en `sociedades`.';

create or replace function public.trg_empresa_clave_fija() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.clave is distinct from old.clave then
    raise exception 'La clave de una empresa no se edita nunca (la usan los proyectos)' using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public.trg_empresa_clave_fija() from public, anon, authenticated;
create trigger trg_empresa_clave_fija before update of clave on public.empresas
  for each row execute function public.trg_empresa_clave_fija();

alter table public.empresas enable row level security;
revoke all on public.empresas from public, anon, authenticated, lw_lector;
grant select on public.empresas to authenticated, lw_lector;
create policy "agentes leen empresas" on public.empresas for select to authenticated, lw_lector using (public.es_agente());

insert into public.empresas (clave, nombre, sociedad_clave, orden) values
  ('lawang',       'Lawang',       'tepi_sungai',   1),
  ('sandal_woods', 'Sandal Woods', 'san_dal_woods', 2);

-- Un campo, nulo = sin empresa = CERRADO (a futuro solo propietario/global lo vera).
alter table public.proyectos add column empresa text references public.empresas(clave);
comment on column public.proyectos.empresa is 'Empresa que controla el proyecto (empresas.clave). Nulo = sin empresa asignada: nace cerrado. Solo super_admin la cambia (trg_proyecto_empresa / proyecto_empresa_guarda).';

create or replace function public.trg_proyecto_empresa() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.empresa is null then return new; end if;
  if tg_op = 'UPDATE' and new.empresa is not distinct from old.empresa then return new; end if;
  -- Sin sesion de usuario (migraciones, service_role del backend): pasa. Un navegador siempre trae uid.
  if (select auth.uid()) is null then return new; end if;
  if not public.es_super_admin() then
    raise exception 'La empresa de un proyecto la cambia solo un super administrador' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.trg_proyecto_empresa() from public, anon, authenticated;
create trigger trg_proyecto_empresa before insert or update of empresa on public.proyectos
  for each row execute function public.trg_proyecto_empresa();

-- Reparto del owner (6-oct-2026). Karana (resort nulo) queda nula a proposito: aparcado.
do $$
declare v_l int; v_s int; v_n int;
begin
  update public.proyectos set empresa = case resort
      when 'Balian Hills' then 'lawang'
      when 'Signature project' then 'sandal_woods'
      when 'Sumba Hills' then 'sandal_woods' end
   where resort in ('Balian Hills', 'Signature project', 'Sumba Hills');
  select count(*) filter (where empresa = 'lawang'), count(*) filter (where empresa = 'sandal_woods'), count(*) filter (where empresa is null)
    into v_l, v_s, v_n from public.proyectos;
  if (v_l, v_s, v_n) is distinct from (20, 12, 1) then
    raise exception 'Reparto inesperado: lawang %, sandal_woods %, sin empresa % (esperado 20/12/1)', v_l, v_s, v_n;
  end if;
end $$;

create or replace function public.empresa_de_proyecto(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select p.empresa from public.proyectos p where p.id = p_id
$$;
revoke all on function public.empresa_de_proyecto(uuid) from public, anon;
grant execute on function public.empresa_de_proyecto(uuid) to authenticated, lw_lector, service_role;

create or replace function public.proyecto_empresa_guarda(p_id uuid, p_empresa text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_super_admin() then
    raise exception 'La empresa de un proyecto la cambia solo un super administrador' using errcode = '42501';
  end if;
  if p_empresa is not null and not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then
    raise exception 'Esa empresa no existe o esta desactivada' using errcode = '22023';
  end if;
  update public.proyectos p set empresa = p_empresa where p.id = p_id;
  if not found then raise exception 'Ese proyecto no existe' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.proyecto_empresa_guarda(uuid, text) from public, anon;
grant execute on function public.proyecto_empresa_guarda(uuid, text) to authenticated;
