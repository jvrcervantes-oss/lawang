-- ═══════════════════════════════════════════════════════════════════════════
-- GASTOS Y PROVEEDORES (24-sep-2026) — módulo `gastos` del AxisWorks ERP.
-- Encargo: encargos/20260924_lawang_dashboard_finanzas.md (tabla B, 1.º).
-- Revisión previa #64 (Administración + Datos + Seguridad), plegada aquí:
--  · Puerta = es_admin() AND puede('gastos'): el rol recorta, la casilla de
--    Usuarios muestra (como Comisiones). Nace visible solo para super_admin.
--  · En esta base los default privileges NO dan nada a `authenticated`: los
--    GRANT de abajo son lo que hace funcionar la pantalla. Sin DELETE ni
--    TRUNCATE para nadie: un gasto se ANULA con motivo, no se borra.
--  · PPh retenido al proveedor (23 / 4(2) / 21 / 26): lo pagado al proveedor
--    es total − pph_retenido; la retención es una salida pendiente a la DJP
--    hasta `pph_ingresado_el`. Ese ingreso NO se apunta después como gasto
--    nuevo (sería contarlo dos veces).
--  · Nunca se paga un gasto desde una cuenta de escrow: ese dinero es de paso,
--    no de la sociedad (trigger, abajo).
--  · Log append-only de INSERT y UPDATE (calca sociedades_log), SECURITY
--    DEFINER; un gasto anulado ya no se toca.
--  · Nada de datos reales en este fichero: el repo es público. Solo la
--    semilla del catálogo de categorías.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── catálogo de categorías ────────────────────────────────────────────────
create table public.gasto_categorias (
  clave      text primary key check (clave ~ '^[a-z0-9_]+$'),
  nombre     text not null,
  -- `suelo` es INVERSIÓN (existencias), no gasto de explotación: se enseña en
  -- su propio renglón (Administración, #64).
  grupo      text not null check (grupo in ('suelo','construccion','comercial','marketing','personal','general','impuestos','financiero')),
  orden      int  not null default 100,
  activa     boolean not null default true,
  creado_en  timestamptz not null default now()
);
insert into public.gasto_categorias (clave, nombre, grupo, orden) values
  ('compra_suelo',        'Compra de suelo',                 'suelo',        10),
  ('notaria_registro',    'Notaría y registro',              'suelo',        20),
  ('licencias_permisos',  'Licencias y permisos (PBG, SLF)', 'construccion', 30),
  ('construccion',        'Construcción (contratista)',      'construccion', 40),
  ('materiales',          'Materiales',                      'construccion', 50),
  ('arquitectura_diseno', 'Arquitectura, ingeniería y diseño','construccion', 60),
  ('agencias_externas',   'Agencias y comisiones externas',  'comercial',    70),
  ('publicidad',          'Publicidad y marketing',          'marketing',    80),
  ('sueldos',             'Sueldos y personal',              'personal',     90),
  ('oficina',             'Oficina, alquiler y suministros', 'general',     100),
  ('software',            'Software y suscripciones',        'general',     110),
  ('asesoria',            'Asesoría legal y fiscal',         'general',     120),
  ('impuestos_tasas',     'Impuestos y tasas (no retenciones)','impuestos', 130),
  ('bancario',            'Comisiones bancarias',            'financiero',  140),
  ('otros',               'Otros',                           'general',     900);

-- ── proveedores ───────────────────────────────────────────────────────────
create table public.proveedores (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null check (btrim(nombre) <> ''),
  tipo            text not null default 'proveedor' check (tipo in ('constructora','proveedor','profesional','administracion','otro')),
  npwp            text,
  contacto        text,
  email           text,
  telefono        text,
  notas           text,
  activo          boolean not null default true,
  creado_por      uuid default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid,
  actualizado_en  timestamptz
);
create unique index proveedores_nombre_unico on public.proveedores (lower(btrim(nombre)));

-- ── gastos ────────────────────────────────────────────────────────────────
create table public.gastos (
  id              uuid primary key default gen_random_uuid(),
  sociedad        text not null references public.sociedades(clave),
  proyecto_id     uuid references public.proyectos(id),          -- null = gasto general de la sociedad
  proveedor_id    uuid references public.proveedores(id),
  categoria       text not null references public.gasto_categorias(clave),
  concepto        text not null check (btrim(concepto) <> ''),
  referencia      text,                                          -- nº de factura del proveedor
  fecha           date not null,                                 -- fecha de la factura (periodo del PPN)
  vence_el        date,
  base            numeric(18,2) not null check (base >= 0),
  impuesto        numeric(18,2) not null default 0 check (impuesto >= 0),   -- PPN/IVA soportado
  total           numeric(18,2) generated always as (base + impuesto) stored,
  pph_retenido    numeric(18,2) not null default 0 check (pph_retenido >= 0),
  pph_tipo        text check (pph_tipo in ('pph23','pph4_2','pph21','pph26','otro')),
  pph_ingresado_el date,                                         -- cuándo se ingresó la retención en la DJP
  moneda          text not null default 'EUR' check (moneda ~ '^[A-Z]{3}$'),
  estado          text not null default 'pendiente' check (estado in ('pendiente','pagado','anulado')),
  pagado_el       date,
  cuenta_pago     text references public.cuentas_bancarias(clave),
  justificantes   jsonb not null default '[]'::jsonb check (jsonb_typeof(justificantes) = 'array'),
  anulado_motivo  text,
  notas           text,
  creado_por      uuid default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid,
  actualizado_en  timestamptz,
  constraint gastos_pagado_con_fecha  check (estado <> 'pagado'  or pagado_el is not null),
  constraint gastos_anulado_con_motivo check (estado <> 'anulado' or nullif(btrim(anulado_motivo), '') is not null),
  constraint gastos_pph_con_tipo      check (pph_retenido = 0 or pph_tipo is not null),
  constraint gastos_pph_no_supera     check (pph_retenido <= base + impuesto)
);
create index gastos_fecha_idx     on public.gastos (fecha desc);
create index gastos_proyecto_idx  on public.gastos (proyecto_id);
create index gastos_proveedor_idx on public.gastos (proveedor_id);
create index gastos_estado_idx    on public.gastos (estado);

-- ── log append-only ───────────────────────────────────────────────────────
create table public.gastos_log (
  id        bigint generated always as identity primary key,
  gasto_id  uuid not null,
  accion    text not null,            -- insert | update
  antes     jsonb,                    -- la fila anterior (null en insert)
  despues   jsonb not null,
  quien     uuid,
  cuando    timestamptz not null default now()
);
create index gastos_log_gasto_idx on public.gastos_log (gasto_id, cuando desc);

-- ── triggers ──────────────────────────────────────────────────────────────
-- Autoría y guardas ANTES de escribir. La autoría la pone la base, no el
-- navegador (sin grant a esas columnas): un log que rellena el propio
-- auditado no es un log.
-- SECURITY DEFINER: mira es_escrow aunque la RLS de cuentas_bancarias no
-- dejara leerla a quien guarda (si no, la guarda fallaría en abierto).
create or replace function public._gastos_antes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_escrow boolean;
begin
  if tg_op = 'UPDATE' then
    if old.estado = 'anulado' then
      raise exception 'Este gasto está anulado: ya no se puede modificar.' using errcode = '23514';
    end if;
    new.creado_por := old.creado_por;
    new.creado_en  := old.creado_en;
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
  else
    new.creado_por := coalesce((select auth.uid()), new.creado_por);
    new.creado_en  := now();
    new.actualizado_por := null;
    new.actualizado_en  := null;
  end if;
  if new.cuenta_pago is not null then
    select es_escrow into v_escrow from public.cuentas_bancarias where clave = new.cuenta_pago;
    if coalesce(v_escrow, false) then
      raise exception 'No se paga un gasto desde una cuenta de depósito en garantía (escrow): ese dinero no es de la sociedad.' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
revoke all on function public._gastos_antes() from public, anon, authenticated;
create trigger gastos_antes before insert or update on public.gastos
  for each row execute function public._gastos_antes();

create or replace function public._gastos_log()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.gastos_log (gasto_id, accion, antes, despues, quien)
  values (new.id, lower(tg_op), case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new), (select auth.uid()));
  return null;
end $$;
revoke all on function public._gastos_log() from public, anon, authenticated;
create trigger gastos_log_trg after insert or update on public.gastos
  for each row execute function public._gastos_log();

create or replace function public._proveedores_autoria()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.creado_por := old.creado_por; new.creado_en := old.creado_en;
    new.actualizado_por := (select auth.uid()); new.actualizado_en := now();
  else
    new.creado_por := coalesce((select auth.uid()), new.creado_por); new.creado_en := now();
    new.actualizado_por := null; new.actualizado_en := null;
  end if;
  return new;
end $$;
create trigger proveedores_autoria before insert or update on public.proveedores
  for each row execute function public._proveedores_autoria();

-- Segunda defensa aunque nadie tenga DELETE: si algún día se borra (a mano,
-- con service_role), queda copia en `borrados` como el resto de tablas de dinero.
create trigger trg_guarda_antes_de_borrar before delete on public.gastos
  for each row execute function public.trg_guarda_antes_de_borrar();
create trigger trg_guarda_antes_de_borrar before delete on public.proveedores
  for each row execute function public.trg_guarda_antes_de_borrar();

-- ── RLS ───────────────────────────────────────────────────────────────────
alter table public.gasto_categorias enable row level security;
alter table public.proveedores      enable row level security;
alter table public.gastos           enable row level security;
alter table public.gastos_log       enable row level security;

create policy "gastos: leer"       on public.gastos for select to authenticated using ((select public.es_admin()) and (select public.puede('gastos')));
create policy "gastos: crear"      on public.gastos for insert to authenticated with check ((select public.es_admin()) and (select public.puede('gastos')));
create policy "gastos: editar"     on public.gastos for update to authenticated using ((select public.es_admin()) and (select public.puede('gastos'))) with check ((select public.es_admin()) and (select public.puede('gastos')));
create policy "proveedores: leer"  on public.proveedores for select to authenticated using ((select public.es_admin()) and (select public.puede('gastos')));
create policy "proveedores: crear" on public.proveedores for insert to authenticated with check ((select public.es_admin()) and (select public.puede('gastos')));
create policy "proveedores: editar" on public.proveedores for update to authenticated using ((select public.es_admin()) and (select public.puede('gastos'))) with check ((select public.es_admin()) and (select public.puede('gastos')));
create policy "categorias: leer"   on public.gasto_categorias for select to authenticated using ((select public.es_admin()) and (select public.puede('gastos')));
create policy "categorias: crear"  on public.gasto_categorias for insert to authenticated with check ((select public.es_admin()) and (select public.puede('gastos')));
create policy "categorias: editar" on public.gasto_categorias for update to authenticated using ((select public.es_admin()) and (select public.puede('gastos'))) with check ((select public.es_admin()) and (select public.puede('gastos')));
create policy "gastos_log: leer"   on public.gastos_log for select to authenticated using ((select public.es_admin()) and (select public.puede('gastos')));

-- ── GRANTS (explícitos: aquí nada llega por defecto a authenticated) ─────
revoke all on public.gasto_categorias, public.proveedores, public.gastos, public.gastos_log from anon, authenticated;
grant select on public.gasto_categorias, public.proveedores, public.gastos, public.gastos_log to authenticated;
grant insert (clave, nombre, grupo, orden, activa) on public.gasto_categorias to authenticated;
grant update (nombre, grupo, orden, activa)        on public.gasto_categorias to authenticated;
grant insert (nombre, tipo, npwp, contacto, email, telefono, notas, activo) on public.proveedores to authenticated;
grant update (nombre, tipo, npwp, contacto, email, telefono, notas, activo) on public.proveedores to authenticated;
grant insert (sociedad, proyecto_id, proveedor_id, categoria, concepto, referencia, fecha, vence_el, base, impuesto,
              pph_retenido, pph_tipo, pph_ingresado_el, moneda, estado, pagado_el, cuenta_pago, justificantes, anulado_motivo, notas)
  on public.gastos to authenticated;
grant update (sociedad, proyecto_id, proveedor_id, categoria, concepto, referencia, fecha, vence_el, base, impuesto,
              pph_retenido, pph_tipo, pph_ingresado_el, moneda, estado, pagado_el, cuenta_pago, justificantes, anulado_motivo, notas)
  on public.gastos to authenticated;

-- ── STORAGE: bucket privado propio ────────────────────────────────────────
-- No se reutiliza `justificantes` (lo leen los agentes): una factura de
-- proveedor es confidencial. Límites EN EL BUCKET, no solo en el navegador.
-- Sin UPDATE (no se sobrescribe) ni DELETE (la factura es la prueba del gasto;
-- quitarla de la lista `justificantes` ya deja rastro en gastos_log).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gastos', 'gastos', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp']);

create policy "gastos: leer justificantes" on storage.objects for select to authenticated
  using (bucket_id = 'gastos' and (select public.es_admin()) and (select public.puede('gastos')));
-- Solo dentro de la carpeta de un gasto que existe: nada de ficheros sueltos.
create policy "gastos: subir justificantes" on storage.objects for insert to authenticated
  with check (bucket_id = 'gastos' and (select public.es_admin()) and (select public.puede('gastos'))
              and exists (select 1 from public.gastos g where g.id::text = (storage.foldername(name))[1] and g.estado <> 'anulado'));
