-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 1 (7-oct-2026): cimientos de clientes, KYC, comunicacion y CRM/leads por empresa. SOLO aditiva: ninguna funcion viva cambia de comportamiento todavia.
--   * crm_origen_empresa: origen (source de un lead / etiqueta de campana de Meta) -> empresa. La empresa de un lead NO se guarda en la fila del lead: se deduce de su `source`,
--     asi los leads nuevos (anon, Meta) la heredan solos y no se toca ninguna escritura publica. Sin mapeo = sin empresa = solo globales (nace cerrado).
--   * comunicados.empresa: nula = comunicado global (solo administradores globales); con valor = de esa empresa.
--   * helpers de alcance sobre clientes (admin_de_cliente / super_admin_de_cliente, exclusivo o no), de usuarios por empresa y del leads por origen.
--   * portal_puede_gestionar(uuid[]): la comprueba la edge portal-invitar con el JWT de quien llama (un rol de empresa solo gestiona clientes cuyos contratos estan TODOS en sus empresas).
-- Ninguna funcion nueva da nada a anon. Las de uso interno (las llaman otras funciones DEFINER) no tienen EXECUTE para nadie mas; solo mis_contratos_admin_empresa (la llama una policy)
-- y portal_puede_gestionar (la llama la edge con el JWT del usuario) llegan a authenticated.
-- destructivo-ok: tabla nueva, columna nullable nueva y funciones nuevas; no borra ni modifica datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
create table if not exists public.crm_origen_empresa (
  clave text primary key,
  empresa text not null references public.empresas(clave),
  nota text,
  creado_en timestamptz not null default now()
);
comment on table public.crm_origen_empresa is 'Origen de leads (source) o etiqueta de campana de Meta -> empresa. Lo lee empresa_de_origen()/empresa_de_lead(); sin fila = sin empresa = solo globales. Evidencia 7-oct-2026: Sumba Hills = Sandal Woods (decision del owner 6-oct); Bali y Australia-Villas Bali = Balian Hills = Lawang.';
alter table public.crm_origen_empresa enable row level security;
revoke all on table public.crm_origen_empresa from anon, authenticated;

insert into public.crm_origen_empresa (clave, empresa, nota) values
  ('meta-sumbahills',       'sandal_woods', 'formulario Meta de la campana SUMBA HILLS - Leads EN'),
  ('sumba-hills-qr',        'sandal_woods', 'QR de Sumba Hills'),
  ('sumbahills-web',        'sandal_woods', 'web de Sumba Hills'),
  ('meta-lawang-bali',      'lawang',       'formulario Meta de la campana LAWANG - Bali - Leads EN (Balian Hills)'),
  ('meta-lawang-australia', 'lawang',       'formulario Meta de la campana LAWANG - Australia - Villas Bali'),
  ('Lawang · Sumba Hills',  'sandal_woods', 'etiqueta de campana en las tablas de Meta'),
  ('Lawang · Bali',         'lawang',       'etiqueta de campana en las tablas de Meta'),
  ('Lawang · Australia',    'lawang',       'etiqueta de campana en las tablas de Meta')
on conflict (clave) do nothing;
-- sin mapear a proposito (queda cerrado para roles de empresa hasta que el owner diga de quien es): 'Lawang · España', 'Lawang · sin uso'.

alter table public.comunicados add column if not exists empresa text references public.empresas(clave);
comment on column public.comunicados.empresa is 'Nula = comunicado global (solo administradores globales). Con valor = de esa empresa: lo gestiona un administrador de la empresa y solo llega a personas de esa empresa.';

-- origen / lead -> empresa (solo para otras funciones DEFINER)
create or replace function public.empresa_de_origen(p_clave text) returns text
language sql stable security definer set search_path = '' as $$
  select m.empresa from public.crm_origen_empresa m where m.clave = p_clave
$$;
create or replace function public.empresa_de_lead(p_lead uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.empresa from public.leads l join public.crm_origen_empresa m on m.clave = l.source where l.id = p_lead
$$;

-- ¿esta persona (por email) pertenece a esa empresa? Sin empresa (null) solo cuenta quien no tiene restriccion alguna.
create or replace function public.usuario_en_empresa(p_email text, p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.usuarios u
     where lower(u.email) = lower(btrim(coalesce(p_email, ''))) and u.activo
       and (case when p_empresa is null then (u.ambito = 'global' and cardinality(u.empresas) = 0)
                 else ((u.ambito = 'global' and (cardinality(u.empresas) = 0 or p_empresa = any (u.empresas)))
                    or (u.ambito = 'empresa' and p_empresa = any (u.empresas))) end))
$$;
-- ¿comparte alguna de MIS empresas esa persona? (quien llama debe tener empresas marcadas)
create or replace function public.comparte_empresa_con(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.usuarios me
     where me.user_id = (select auth.uid()) and me.activo and cardinality(me.empresas) > 0
       and exists (select 1 from unnest(me.empresas) e where public.usuario_en_empresa(p_email, e)))
$$;

-- ¿el propietario de una ficha es de alguna de las empresas del administrador de empresa que llama?
create or replace function public._propietario_en_mis_empresas(p_propietario text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_propietario is not null and exists (
    select 1 from public.usuarios me
      join public.usuarios pr on lower(pr.email) = lower(p_propietario)
     where me.user_id = (select auth.uid()) and me.activo and me.ambito = 'empresa'
       and me.rol in ('admin_empresa', 'super_admin_empresa')
       and pr.activo and pr.empresas && me.empresas)
$$;

-- Un rol de empresa y un cliente. No exclusivo = lo VE por alguna via (lo lleva el, lo lleva alguien de su empresa, o tiene un contrato en sus empresas).
-- Exclusivo = TODO lo del cliente (contratos y facturas) esta en sus empresas, y si no tiene contratos lo lleva el o alguien de su empresa.
-- Es la regla para lo que no se deshace (retirar KYC, traspasar, invitar al portal): un cliente en las dos empresas lo toca solo un administrador global.
create or replace function public._cliente_en_empresas(p_client uuid, p_exclusivo boolean, p_roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
      from public.usuarios u
      join public.clients c on c.id = p_client
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
       and u.rol = any (p_roles) and cardinality(u.empresas) > 0
       and (case when p_exclusivo then
              (exists (select 1 from public.contrato_compradores cc where cc.client_id = c.id)
               or lower(coalesce(c.propietario, '')) = lower(u.email)
               or public._propietario_en_mis_empresas(c.propietario))
              and not exists (select 1 from public.contrato_compradores cc
                                join public.contratos k on k.id = cc.contrato_id
                                left join public.proyectos pr on pr.id = k.proyecto_id
                               where cc.client_id = c.id and not coalesce(pr.empresa = any (u.empresas), false))
              and not exists (select 1 from public.facturas f
                               where f.client_id = c.id
                                 and not coalesce(public.empresa_de_factura(f.id) = any (u.empresas), false))
            else
              lower(coalesce(c.propietario, '')) = lower(u.email)
              or public._propietario_en_mis_empresas(c.propietario)
              or exists (select 1 from public.contrato_compradores cc
                           join public.contratos k on k.id = cc.contrato_id
                           join public.proyectos pr on pr.id = k.proyecto_id
                          where cc.client_id = c.id and pr.empresa = any (u.empresas))
            end))
$$;
create or replace function public.admin_de_cliente(p_client uuid, p_exclusivo boolean default false) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin() or public._cliente_en_empresas(p_client, p_exclusivo, array['admin_empresa', 'super_admin_empresa'])
$$;
create or replace function public.super_admin_de_cliente(p_client uuid, p_exclusivo boolean default true) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_super_admin() or public._cliente_en_empresas(p_client, p_exclusivo, array['super_admin_empresa'])
$$;
-- ¿tiene el rol de administrador de alguna empresa (o es admin global)? Para las puertas de entrada de las funciones de ficha: el detalle lo decide admin_de_cliente.
create or replace function public.es_admin_en_alguna_empresa() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin() or exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
       and u.rol in ('admin_empresa', 'super_admin_empresa') and cardinality(u.empresas) > 0)
$$;

-- contratos de las empresas de un administrador de empresa (array, para usarlo como initPlan en una policy sin evaluar nada por fila)
create or replace function public.mis_contratos_admin_empresa() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce((select array_agg(c.id)
                     from public.usuarios u
                     join public.proyectos p on p.empresa = any (u.empresas)
                     join public.contratos c on c.proyecto_id = p.id
                    where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
                      and u.rol in ('admin_empresa', 'super_admin_empresa')), '{}'::uuid[])
$$;

-- la llama la edge portal-invitar con el JWT de quien invita. Global: sin cambio. Rol de empresa: cada ficha con contrato y todo en sus empresas.
create or replace function public.portal_puede_gestionar(p_ids uuid[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin() or not exists (
    select 1 from unnest(coalesce(p_ids, '{}'::uuid[])) i(id)
     where not (exists (select 1 from public.contrato_compradores cc where cc.client_id = i.id)
                and public._cliente_en_empresas(i.id, true, array['admin_empresa', 'super_admin_empresa'])))
$$;

-- empresa de un comunicado nuevo: el administrador global la elige (o lo deja global); un rol de empresa, la suya (si tiene una sola) o la que elija entre las suyas
create or replace function public._comunicado_empresa_alta(p_datos jsonb) returns text
language plpgsql stable security definer set search_path = '' as $$
declare v_emp text := nullif(btrim(coalesce(p_datos->>'empresa', '')), '');
begin
  if public.es_admin() then return v_emp; end if;
  if v_emp is null then
    select u.empresas[1] into v_emp from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and cardinality(u.empresas) = 1;
  end if;
  if v_emp is null then raise exception 'Elige la empresa del comunicado' using errcode = '22023'; end if;
  if not public.es_admin_de(v_emp) then raise exception 'Ese comunicado es de otra empresa' using errcode = '42501'; end if;
  return v_emp;
end $$;

revoke all on function public.empresa_de_origen(text), public.empresa_de_lead(uuid), public.usuario_en_empresa(text, text),
  public.comparte_empresa_con(text), public._propietario_en_mis_empresas(text), public._cliente_en_empresas(uuid, boolean, text[]),
  public.admin_de_cliente(uuid, boolean), public.super_admin_de_cliente(uuid, boolean), public.es_admin_en_alguna_empresa(),
  public._comunicado_empresa_alta(jsonb), public.mis_contratos_admin_empresa(), public.portal_puede_gestionar(uuid[])
  from public, anon, authenticated;
grant execute on function public.mis_contratos_admin_empresa() to authenticated, lw_lector;
grant execute on function public.portal_puede_gestionar(uuid[]) to authenticated;
