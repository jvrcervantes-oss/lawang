-- Lawang · contratos — cerrar el agujero de "authenticated = cualquiera"
-- 22-jul-2026
--
-- Problema: las policies eran `to authenticated using (true)` y el registro
-- público de Supabase Auth está ABIERTO (/auth/v1/settings → disable_signup:false).
-- La publishable key está en el HTML de app.html (es pública por diseño), así que
-- cualquiera podía registrarse con su propio email, confirmarlo desde su propio
-- buzón y quedar como `authenticated` → leer TODOS los contratos guardados
-- (pasaporte, domicilio, teléfono de los compradores) y el bucket de PDFs firmados.
--
-- Fix: las policies exigen un flag en app_metadata. app_metadata solo se escribe
-- desde el servidor (service_role / dashboard); user_metadata NO vale porque lo
-- fija el propio usuario en el signUp.

create or replace function public.es_agente() returns boolean
language sql stable
as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'agente')::boolean, false) $$;

alter policy "agentes autenticados leen contratos" on public.contratos
  using (public.es_agente());
alter policy "agentes autenticados insertan contratos" on public.contratos
  with check (public.es_agente());
alter policy "agentes autenticados actualizan contratos no bloqueados" on public.contratos
  using (bloqueado = false and public.es_agente()) with check (public.es_agente());

alter policy "agentes autenticados leen diseno" on public.contratos_diseno
  using (public.es_agente());
alter policy "agentes autenticados escriben diseno" on public.contratos_diseno
  using (public.es_agente()) with check (public.es_agente());

alter policy "agentes autenticados leen pdf firmado" on storage.objects
  using (bucket_id = 'contratos-firmados' and public.es_agente());
alter policy "agentes autenticados suben pdf firmado" on storage.objects
  with check (bucket_id = 'contratos-firmados' and public.es_agente());

-- Los 5 usuarios que ya existen (creados 20-21 jul por el estudio y el cliente)
-- son los agentes legítimos. Un agente NUEVO no funciona solo con darse de alta:
-- hay que marcarlo aquí (o desde el dashboard → Authentication → el usuario →
-- Raw App Meta Data), que es justamente lo que cierra el agujero.
update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"agente":true}'::jsonb;

-- Comprobación (no modifica nada): simula un usuario recién registrado sin el flag
-- y otro con él. Debe dar 0 filas para el primero y las reales para el segundo.
--   begin;
--   set local role authenticated;
--   set local request.jwt.claims = '{"role":"authenticated","app_metadata":{}}';
--   select count(*) from public.contratos;                      -- esperado: 0
--   set local request.jwt.claims = '{"role":"authenticated","app_metadata":{"agente":true}}';
--   select count(*) from public.contratos;                      -- esperado: las reales
--   rollback;
