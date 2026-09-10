-- CRM de leads en la intranet de Lawang — 9-sep-2026.
-- Revision previa: Seguridad (sus bloqueantes recogidos aqui).
-- Clave de permiso NUEVA: 'leads'. No se reutiliza 'operaciones' porque lo que se abre
-- son los datos de contacto de 101 personas reales y eso tiene que poder decidirse
-- cuenta a cuenta, no venir de regalo con "puede aprobar pagos".
-- Las cinco tablas implicadas tenian RLS activo y CERO policies (verificado): aqui solo
-- se crean, no se reemplaza ninguna.

-- 1. TRAZA DE REVELACION DE CONTACTO ---------------------------------------------
-- lead_estado_log registra ESCRITURAS. Quien MIRA un telefono no dejaba rastro, y esta
-- familia de datos ya tiene una fuga abierta (el private/leads.csv de Sumba Hills,
-- publico del 15 al 27-jul; 8 de esos afectados estan entre estos 101). Sin esto el
-- estudio no puede responder "quien saco esta lista".
create table if not exists public.lead_acceso_log (
  id       bigserial primary key,
  lead_id  uuid not null references public.leads(id) on delete cascade,
  quien    text not null,
  que      text not null check (que in ('contacto','whatsapp','email')),
  cuando   timestamptz not null default now()
);
create index if not exists lead_acceso_log_lead_idx on public.lead_acceso_log(lead_id, cuando desc);
alter table public.lead_acceso_log enable row level security;

-- 2. SNAPSHOT DIARIO DE META ------------------------------------------------------
-- Lo escribe el vigilante del estudio (ya habla con Meta cada 4 h). El navegador no
-- puede llamar a la Graph API y una edge-proxy abriria otra via de secretos y otro
-- frente de rafagas. PK (campaign_id, fecha): el dia en curso se reescribe en cada
-- vuelta con el gasto acumulado, sin duplicar filas.
create table if not exists public.axisworks_meta_insights_dia (
  campaign_id text not null,
  fecha       date not null,
  cliente     text not null,
  nombre      text,
  gasto       numeric(14,2),
  moneda      text,
  impresiones bigint,
  clics       bigint,
  leads       integer,
  updated_at  timestamptz not null default now(),
  primary key (campaign_id, fecha)
);
alter table public.axisworks_meta_insights_dia enable row level security;

-- 3. POLICIES -----------------------------------------------------------------------
-- UNA POR COMANDO, nunca una sola "para todo": anon y authenticated tienen concedidos
-- los cuatro comandos sobre estas tablas, asi que una policy que cubriera todos daria
-- tambien la capacidad de vaciar el historico. Lo unico que las cierra hoy es no tener
-- ninguna policy.
-- `leads` NO recibe policy de lectura a proposito: lleva columna `ip` (32 filas) y una
-- policy es por fila, no por columna -- publicaria sola cualquier columna que se anada
-- manana. Se sirve por funcion, con las columnas escritas a mano (migracion siguiente).

create policy "crm ve el catalogo de etapas" on public.contrato_tipo_etapa
  for select to authenticated using (public.puede('leads'));

create policy "crm lee el estado de los leads" on public.lead_estado
  for select to authenticated using (public.puede('leads'));

create policy "crm lee las notas" on public.lead_notas
  for select to authenticated using (public.puede('leads'));

-- El historial se lee y no se toca: solo lectura para todos, admin incluido. Si se
-- pudiera reescribir, no seria traza.
create policy "crm lee el historial de estados" on public.lead_estado_log
  for select to authenticated using (public.puede('leads'));

-- La traza de accesos solo la lee un admin: es el registro de quien mira a quien.
create policy "admin lee la traza de accesos" on public.lead_acceso_log
  for select to authenticated using (public.es_admin());

-- Nadie escribe a mano en ninguna de las tres: lo hacen las funciones SECURITY DEFINER.
-- Sin mas policies, cualquier otra operacion queda denegada, que es lo que se busca.

-- 4. autor obligatorio en la traza de escritura ------------------------------------
-- Verificado antes de aplicarlo: 2 filas en lead_estado_log, ninguna con autor vacio;
-- 0 notas. Sin esto, `es_suyo()` trata un autor vacio como "tuyo".
alter table public.lead_estado_log alter column autor set not null;;
