-- Alta de colaboradores desde la guía /formacion/ (24-sep-2026).
--
-- Decisión del owner tras la revisión previa #61 (Seguridad + Legal + Datos):
--   · COMERCIAL (5 %): deja sus datos con un código por email → queda una SOLICITUD
--     → el owner la activa con un clic en Usuarios (edge admin-usuarios,
--     accion 'activar_solicitud'). Nadie entra a la intranet sin ese clic: cualquier
--     fila activa de `usuarios` pasa es_agente() y puede LEER el directorio de
--     compradores, así que las herramientas no bastan como barrera.
--   · REFERIDO (1 %): NO tiene intranet. Registra a su contacto desde un formulario
--     público y queda guardado a su nombre en `referidos_contactos`.
--
-- Las tres tablas las escribe SOLO la edge `alta-colaborador` / `admin-usuarios`
-- (service_role). RLS activada, sin GRANT a anon; authenticated solo LEE solicitudes
-- y contactos si es admin con la herramienta «usuarios».

-- ── Códigos de verificación por email (tabla propia, no la del investor deck: un
--    código de un circuito no debe servir para el otro) ──────────────────────────
create table if not exists public.colaboradores_verificaciones (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  codigo_hash text not null,
  intentos    int  not null default 0,
  usado       boolean not null default false,
  expira_at   timestamptz not null,
  ip_hash     text,
  creado_at   timestamptz not null default now()
);
create index if not exists colaboradores_verif_email_idx on public.colaboradores_verificaciones (lower(email), creado_at desc);
create index if not exists colaboradores_verif_ip_idx on public.colaboradores_verificaciones (ip_hash, creado_at desc);
alter table public.colaboradores_verificaciones enable row level security;
revoke all on public.colaboradores_verificaciones from anon, authenticated;

-- ── Solicitudes de alta de comerciales ──────────────────────────────────────────
create table if not exists public.solicitudes_colaborador (
  id           uuid primary key default gen_random_uuid(),
  email        text not null,
  nombre       text not null,
  telefono     text,
  pais         text,
  mensaje      text,
  estado       text not null default 'pendiente' check (estado in ('pendiente','activada','descartada')),
  user_id      uuid,
  revisado_por text,
  revisado_en  timestamptz,
  creado_at    timestamptz not null default now()
);
-- una sola solicitud pendiente por email: repetir el formulario no crea otra
create unique index if not exists solicitudes_colaborador_pendiente_uq
  on public.solicitudes_colaborador (lower(email)) where estado = 'pendiente';
alter table public.solicitudes_colaborador enable row level security;
revoke all on public.solicitudes_colaborador from anon, authenticated;
grant select on public.solicitudes_colaborador to authenticated;
create policy "admins con usuarios ven solicitudes" on public.solicitudes_colaborador
  for select to authenticated using (public.es_admin() and public.puede('usuarios'));

-- ── Contactos que registra un referido ─────────────────────────────────────────
-- El referido NO tiene cuenta: su identidad es el email que verificó con el código.
-- `referido_email` es la atribución de su 1 %; no se sobrescribe nunca.
create table if not exists public.referidos_contactos (
  id                uuid primary key default gen_random_uuid(),
  referido_email    text not null,
  referido_nombre   text not null,
  referido_telefono text,
  cliente_nombre    text not null,
  cliente_email     text,
  cliente_telefono  text,
  cliente_pais      text,
  interes           text,
  consentimiento    boolean not null default false,
  estado            text not null default 'nuevo' check (estado in ('nuevo','en_crm','descartado')),
  revisado_por      text,
  revisado_en       timestamptz,
  creado_at         timestamptz not null default now()
);
create index if not exists referidos_contactos_ref_idx on public.referidos_contactos (lower(referido_email), creado_at desc);
alter table public.referidos_contactos enable row level security;
revoke all on public.referidos_contactos from anon, authenticated;
grant select on public.referidos_contactos to authenticated;
create policy "admins con usuarios ven referidos" on public.referidos_contactos
  for select to authenticated using (public.es_admin() and public.puede('usuarios'));

comment on table public.solicitudes_colaborador is 'Solicitudes de alta de comerciales desde /formacion/. Solo las escribe service_role (edge alta-colaborador); las activa un admin con admin-usuarios accion activar_solicitud.';
comment on table public.referidos_contactos is 'Contactos que registra un referido (1 %) desde /formacion/, sin cuenta. referido_email = atribución. Solo los escribe service_role.';
comment on table public.colaboradores_verificaciones is 'Códigos de 6 dígitos por email para el alta de colaboradores. Solo service_role.';
