-- «Subir firmado» (cerrar un contrato subiendo el PDF a mano) fallaba para todo
-- el que no es admin desde el 18-sep-2026 — lo notó el equipo el 25-sep con
-- CC00105 (sales_manager, contrato suyo): tres POST 400 «new row violates
-- row-level security policy for table "objects"».
--
-- POR QUE. `subirPdfFirmado()` (contracts/app.html) sube `<numero>_manual.pdf`
-- con `upsert:true` y DESPUES apunta `contratos.pdf_firmado_path` a ese fichero.
-- Con upsert, storage-api hace INSERT … ON CONFLICT DO UPDATE … RETURNING, y
-- Postgres exige que la fila nueva pase tambien la policy de SELECT. La de
-- `contratos-firmados` (20260918021400) solo reconoce un PDF cuando un contrato
-- ya apunta a el: en el momento de subir no apunta nadie → rechazo. Los admins
-- no lo veian porque `es_admin()` les abre la lectura entera. Los snapshots de
-- `pendientes/` tambien van con upsert y funcionan porque esa rama casa por id.
-- (Mismo mecanismo que reference_insert_returning_aplica_la_policy_de_select.)
--
-- ARREGLO, sin tocar la app ni ensanchar mas de lo necesario:
--   1. `agente_ve_contrato_pdf` reconoce tambien EXACTAMENTE `<numero>_manual.pdf`
--      de un contrato que el agente ya puede ver (misma guarda de propiedad).
--      Los huerfanos siguen invisibles: sin contrato con ese numero no casa nada.
--   2. Reintento: si el PDF subio pero el UPDATE del contrato fallo, el fichero
--      ya existe y el siguiente upsert toma la rama DO UPDATE, que solo tenia
--      policy para `pendientes/`. Se abre para el `_manual.pdf` de un contrato
--      propio y SIN bloquear: uno firmado no se reescribe (ademas su hash queda
--      en `contratos.pdf_firmado_hash`).
--
-- Seguro: solo `create or replace function` y `create policy` nuevas.

create or replace function public.agente_ve_contrato_pdf(p_name text)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select public.es_agente() and exists (
    select 1
      from public.contratos c
     where (c.pdf_firmado_path = p_name
            or p_name = c.numero || '_manual.pdf'
            or (p_name like 'pendientes/%'
                and c.id::text = replace(replace(p_name, 'pendientes/', ''), '.html', '')))
       and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id)))
$function$;

create or replace function public.agente_reescribe_pdf_manual(p_name text)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select public.es_agente() and exists (
    select 1
      from public.contratos c
     where p_name = c.numero || '_manual.pdf'
       and coalesce(c.bloqueado, false) = false
       and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id)))
$function$;

revoke all on function public.agente_reescribe_pdf_manual(text) from public, anon;
grant execute on function public.agente_reescribe_pdf_manual(text) to authenticated;

create policy "agentes reintentan su pdf manual sin bloquear"
  on storage.objects for update to authenticated
  using      (bucket_id = 'contratos-firmados' and name like '%\_manual.pdf' and public.agente_reescribe_pdf_manual(name))
  with check (bucket_id = 'contratos-firmados' and name like '%\_manual.pdf' and public.agente_reescribe_pdf_manual(name));
