-- ════════════════════════════════════════════════════════════════════════════
-- REGISTRO DE CORREOS ENVIADOS — 18-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del owner tras el incidente CR00025: un contrato se "envió" a un
-- email con typo (dominio inexistente) y nadie pudo responder "¿a qué dirección
-- salió y cuándo?" — porque NINGÚN punto de envío dejaba rastro. send_email.php
-- no registra nada a propósito (es un relé sin base), así que el log vive donde
-- viven los datos: una fila por correo REALMENTE entregado a Hostinger, escrita
-- por quien lo envió justo después del envío exitoso.
--
-- Quién escribe aquí (los 4 caminos de correo de la suite, censo 18-ago-2026):
--   · Edge send-contract-email  → botón "Enviar por email" de Contratos y el
--     "Enviar" de Facturas (service_role, salta RLS).
--   · Edge firma-submit         → circuito de firma: enlace al siguiente
--     firmante, contrato firmado, proforma (service_role).
--   · Edge factura-vencimiento  → facturas D-3 del cron (service_role).
--   · app.html fmMail           → email con el enlace de firma: es el ÚNICO
--     envío que sale directo del navegador a send_email.php, por eso el insert
--     lo hace el navegador y hace falta la policy de INSERT para agentes.
--
-- El log es de HECHOS, no de intenciones: se inserta tras el ok del envío,
-- nunca antes. Y es inmutable desde la app: sin policy de update/delete —
-- un registro que se puede editar no sirve para responder a un cliente.
-- Si el insert falla, el correo YA salió: el que envía loguea el fallo en
-- consola y NO revienta el envío (perder una fila de log < repetir un email).

create table if not exists public.correos_enviados (
  id          uuid primary key default gen_random_uuid(),
  -- on delete cascade, no set null: si el contrato se borra (RPC de borrado,
  -- que ya exige super_admin y frenos), una fila huérfana sin contrato no
  -- responde ninguna pregunta y sí retiene el email del destinatario.
  contrato_id uuid references public.contratos(id) on delete cascade,
  factura_id  uuid references public.facturas(id)  on delete cascade,
  para        text not null,
  asunto      text not null,
  -- de qué camino salió (los 4 de arriba + proforma, que firma-submit manda
  -- como email separado del contrato firmado por decisión del owner 17-ago,
  -- + aviso_anulacion: el correo que avisa al comprador de que su enlace ha
  --   dejado de valer porque el documento se va a cambiar, 18-ago)
  via         text not null check (via in
                ('manual','enlace_firma','firma','proforma','factura','factura_auto',
                 'aviso_anulacion')),
  -- email del agente que pulsó el botón; null = lo mandó un automatismo (cron)
  enviado_por text,
  enviado_en  timestamptz not null default now(),
  -- un correo sin ancla no se puede enseñar en ninguna ficha
  constraint correos_con_ancla check (contrato_id is not null or factura_id is not null)
);

create index if not exists correos_enviados_contrato_idx on public.correos_enviados (contrato_id, enviado_en desc);
create index if not exists correos_enviados_factura_idx  on public.correos_enviados (factura_id) where factura_id is not null;

alter table public.correos_enviados enable row level security;

-- Lectura: cualquier agente — el registro existe para responder "¿salió o no?"
-- y esa pregunta la hace quien atiende al cliente, no solo quien envió.
drop policy if exists "agentes leen correos" on public.correos_enviados;
create policy "agentes leen correos" on public.correos_enviados
  for select to authenticated using (public.es_agente());

-- Escritura: solo el camino del navegador la necesita (fmMail); las edges
-- entran por service_role. with check exige el es_agente de siempre y que
-- el navegador firme la fila con su propio email (enviado_por), para que un
-- insert manual no pueda atribuir el envío a otro.
drop policy if exists "agentes registran sus envios" on public.correos_enviados;
create policy "agentes registran sus envios" on public.correos_enviados
  for insert to authenticated
  with check (public.es_agente() and enviado_por = (auth.jwt() ->> 'email'));

-- ── Comprobación (la del catálogo, nunca el "ya lo mandé") ──────────────────
--   select relrowsecurity from pg_class where relname='correos_enviados';   → t
--   select polname, polcmd from pg_policy
--    where polrelid='public.correos_enviados'::regclass;                    → r + a, nada más
--   \d public.correos_enviados                                              → CHECK de via y de ancla
