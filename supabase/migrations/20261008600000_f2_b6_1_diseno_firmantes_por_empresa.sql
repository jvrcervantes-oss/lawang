-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 6 · migracion 1 (8-oct-2026): lo que es de CADA empresa en la familia «plantilla de contrato».
--   Decision del owner (7-oct): «cada empresa tiene los suyos… duplicando». Aqui:
--   (1) DISENO DEL DOCUMENTO por empresa (logo, portada, colores de cada tipo de contrato). Capa NUEVA `contratos_diseno_empresa` con una COPIA por empresa de los 3 disenos de hoy.
--       La tabla vieja `contratos_diseno` NO se toca (la lee el generador vivo con contrato_diseno_datos): sigue siendo lo que ve el codigo actual. Un trigger la mantiene en sincronia con las copias
--       que nadie ha personalizado (si una empresa edita la suya, deja de seguir a la comun). Las RPC nuevas las llamara la pantalla de diseno (contracts/assets/documento_diseno.js, bloque 7).
--   (2) FIRMANTES y APODERADOS: ya no se duplican (copiar el NIK/pasaporte de un apoderado de Lawang como si fuera de Sandal Woods seria un dato falso): llevan `empresa` y la lee cada empresa solo lo suyo.
--       Evidencia: sociedades.rep (Pablo Cantero = PT SAN DAL WOODS = sandal_woods; I Wayan Eka Aryawan = PT TEPI SUN GAI = lawang); I Made Monjong fue el representante anterior de tepi_sungai (entities.js);
--       los 2 apoderados del Hak Sewa / Poder Notarial son de Tepi Sun Gai (contracts/sql/apoderado_poa_ni_luh_gede.sql). Una fila sin empresa NACE CERRADA para quien tiene alcance por empresa.
--   NO se tocan: plantillas_contrato / plantilla_cuentas (tipos de contrato y cuentas por defecto: las leen bot-agentes, firma-submit y factura-vencimiento con .maybeSingle() por slug; duplicar filas
--   rompe el bot; ademas el reparto de cuentas es del bloque 2), bloques_legales (texto legal comun, sin escritor), correo_plantillas (plantillas de correo, solo super global).
-- destructivo-ok: tabla nueva, columnas nuevas, ALTER POLICY; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b6.sql (PARTE 1)

-- 1. Diseno por empresa ------------------------------------------------------------------------------------
create table public.contratos_diseno_empresa (
  empresa    text        not null references public.empresas (clave),
  slug       text        not null check (slug ~ '^[a-z0-9_-]{2,60}$'),
  design     jsonb       not null,
  updated_at timestamptz not null default now(),
  primary key (empresa, slug)
);
comment on table public.contratos_diseno_empresa is
  'Diseno del documento (logo, portada, colores) de cada tipo de contrato, UNA COPIA POR EMPRESA (owner 7-oct-2026). contratos_diseno (sin empresa) es lo que lee el generador antiguo; esta es la capa nueva.';
alter table public.contratos_diseno_empresa enable row level security;
revoke all on table public.contratos_diseno_empresa from public, anon, authenticated;
grant select on table public.contratos_diseno_empresa to lw_lector;
create policy "diseno por empresa: agentes de su alcance" on public.contratos_diseno_empresa
  for select to lw_lector
  using (public.es_agente() and public.empresa_en_alcance(empresa));

-- la copia: mismos contenidos para las dos empresas (duplicado)
insert into public.contratos_diseno_empresa (empresa, slug, design, updated_at)
select e.clave, d.slug, d.design, d.updated_at
  from public.empresas e cross join public.contratos_diseno d
 where e.activa;

-- la tabla vieja sigue mandando mientras el generador no cambie: sus cambios llegan a las copias que nadie ha personalizado
create function public._trg_diseno_a_copias()
 returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.contratos_diseno_empresa (empresa, slug, design, updated_at)
      select e.clave, new.slug, new.design, new.updated_at from public.empresas e where e.activa
    on conflict (empresa, slug) do nothing;
  else
    update public.contratos_diseno_empresa c
       set design = new.design, updated_at = new.updated_at
     where c.slug = new.slug and c.design = old.design;
  end if;
  return null;
end $$;
revoke all on function public._trg_diseno_a_copias() from public, anon, authenticated, lw_lector, service_role;
create trigger trg_diseno_a_copias after insert or update of design on public.contratos_diseno
  for each row execute function public._trg_diseno_a_copias();

-- lectura (llamador: contracts/assets/documento_diseno.js, bloque 7): dueno lector, como contrato_diseno_datos
create function public.contrato_diseno_empresa_datos(p_slug text, p_empresa text)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_d jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'contrato_diseno_empresa_datos: sin sesión' using errcode = '42501';
  end if;
  if p_slug is null or btrim(p_slug) = '' or p_empresa is null or btrim(p_empresa) = '' then
    raise exception 'contrato_diseno_empresa_datos: falta la plantilla o la empresa' using errcode = '22023';
  end if;
  select d.design into v_d from public.contratos_diseno_empresa d where d.empresa = p_empresa and d.slug = p_slug;
  return jsonb_build_object('design', v_d);
end $$;

-- escritura (llamador: la pantalla de diseno, bloque 7): lo que hoy hace un admin global, ahora un admin de ESA empresa
create function public.contratos_diseno_empresa_guarda(p_empresa text, p_slug text, p_design jsonb)
 returns text language plpgsql security definer set search_path = '' as $$
begin
  if p_empresa is null or not exists (select 1 from public.empresas e where e.clave = p_empresa and e.activa) then
    raise exception 'Empresa no válida' using errcode = '22023';
  end if;
  if not public.es_admin_de(p_empresa) then
    raise exception 'El diseño de un tipo de contrato lo guarda administración de esa empresa' using errcode = '42501';
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9_-]{2,60}$' then raise exception 'Tipo de contrato no válido' using errcode = '22023'; end if;
  perform public._contratos_diseno_valida(p_design);
  insert into public.contratos_diseno_empresa (empresa, slug, design, updated_at) values (p_empresa, p_slug, p_design, now())
  on conflict (empresa, slug) do update set design = excluded.design, updated_at = excluded.updated_at;
  return p_slug;
end $$;
revoke all on function public.contratos_diseno_empresa_guarda(text, text, jsonb) from public, anon;
grant execute on function public.contratos_diseno_empresa_guarda(text, text, jsonb) to authenticated;

grant create on schema public to lw_lector;
alter function public.contrato_diseno_empresa_datos(text, text) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.contrato_diseno_empresa_datos(text, text) from public, anon, service_role;
grant execute on function public.contrato_diseno_empresa_datos(text, text) to authenticated;

-- 2. Firmantes y apoderados: de que empresa es cada uno ------------------------------------------------------
alter table public.firmantes_cred       add column empresa text references public.empresas (clave);
alter table public.apoderados_hak_sewa  add column empresa text references public.empresas (clave);
comment on column public.firmantes_cred.empresa      is 'Empresa a la que representa (sociedades.rep). Nula = solo la ve quien no tiene alcance por empresa.';
comment on column public.apoderados_hak_sewa.empresa is 'Empresa cuyo Hak Sewa / Poder Notarial firma. Nula = solo la ve quien no tiene alcance por empresa.';

update public.firmantes_cred f set empresa = 'sandal_woods' where f.nombre = 'Pablo Cantero Gambín';
update public.firmantes_cred f set empresa = 'lawang'       where f.nombre in ('I Wayan Eka Aryawan', 'I Made Monjong Adhi Nugruah');
update public.apoderados_hak_sewa a set empresa = 'lawang' where a.empresa is null;

alter policy "firmantes cred: solo con sesion" on public.firmantes_cred
  using (public.es_agente() and (not (select public.alcance_restringido()) or (empresa is not null and public.empresa_en_alcance(empresa))));
alter policy "apoderados hak sewa: solo con sesion" on public.apoderados_hak_sewa
  using (public.es_agente() and (not (select public.alcance_restringido()) or (empresa is not null and public.empresa_en_alcance(empresa))));
