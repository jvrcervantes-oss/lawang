-- 14-sep-2026. Copia íntegra en el repo:
-- proyectos/Lawang/supabase/migrations/20260914_directorio_de_compradores_y_el_autor_corrige_lo_suyo.sql
-- Directorio de identidad de compradores para todo el equipo (sin `notes`, sin
-- abrir la ficha) + el autor corrige la ficha que creó mientras no esté firmada.

create or replace function public.compradores_directorio()
returns table (
  id              uuid,
  full_name       text,
  tipo            text,
  email           text,
  phone           text,
  nationality     text,
  passport_number text,
  date_of_birth   date,
  address         text,
  forma_juridica  text,
  registro_num    text,
  rep_nombre      text,
  rep_cargo       text,
  kyc_status      text,
  propietario     text,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path to ''
as $function$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality,
         c.passport_number, c.date_of_birth, c.address,
         c.forma_juridica, c.registro_num, c.rep_nombre, c.rep_cargo,
         c.kyc_status, c.propietario, c.created_at
    from public.clients c
   where public.es_agente()
$function$;

comment on function public.compradores_directorio() is
  'Directorio de identidad de TODOS los compradores, para cualquiera del equipo (14-sep-2026). No incluye `notes`. Abrir la ficha, editarla o subirle documentos sigue mandandolo la RLS de `clients`.';

revoke execute on function public.compradores_directorio() from public, anon;
grant  execute on function public.compradores_directorio() to authenticated;

create or replace function public.cliente_con_contrato_firmado(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.contrato_compradores cc
      join public.contratos c on c.id = cc.contrato_id
     where cc.client_id = p_client_id
       and coalesce(c.bloqueado, false)
  )
$function$;

comment on function public.cliente_con_contrato_firmado(uuid) is
  'true si esta ficha de comprador cuelga de algun contrato ya firmado (`bloqueado`). DEFINER a proposito: la pregunta es del sistema, no del que mira.';

revoke execute on function public.cliente_con_contrato_firmado(uuid) from public, anon;
grant  execute on function public.cliente_con_contrato_firmado(uuid) to authenticated;

create policy "el autor corrige su ficha mientras no este firmada"
  on public.clients for update to authenticated
  using (
    public.es_agente()
    and public.es_suyo(propietario)
    and not public.cliente_con_contrato_firmado(id)
  )
  with check (
    public.es_agente()
    and public.es_suyo(propietario)
    and not public.cliente_con_contrato_firmado(id)
  );;
