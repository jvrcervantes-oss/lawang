-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 3 · F2 paso (i) (OK del owner 6-oct-2026): ficha de comprador de una en una, con registro y freno; la lista deja de llevar el pasaporte.
-- Aditiva: compradores_directorio() NO se toca ni se borra aqui (las pantallas viejas siguen vivas hasta publicar el front nuevo).
-- destructivo-ok: solo crea una tabla de registro y tres funciones nuevas; no toca filas existentes.
-- REVERTIR: drop function public.comprador_ficha(uuid); drop function public.comprador_buscar(text); drop function public.compradores_lista(); drop table public.comprador_ficha_accesos;
-- F2 · Quitar el volcado de identidad. 3 piezas nuevas + migrar 7 llamadores + DROP de compradores_directorio().
-- Medido hoy: agente sin Compradores ni nada -> compradores_directorio() = 211 filas, 195 con pasaporte; portal = 0 (ya cerrado).
-- Decisión de diseño de 22-sep (comprador compartido entre closers) se respeta: cualquier agente PUEDE abrir una ficha ajena,
-- pero de una en una, con registro y con freno anti-volcado.

create table if not exists public.comprador_ficha_accesos (
  id bigint generated always as identity primary key,
  user_id uuid not null, client_id uuid not null, en timestamptz not null default now());
alter table public.comprador_ficha_accesos enable row level security;           -- sin policies: solo la función (DEFINER) y service_role
revoke all on public.comprador_ficha_accesos from public, anon, authenticated;
create index if not exists comprador_ficha_accesos_user_en on public.comprador_ficha_accesos(user_id, en desc);

-- 1) Lista/buscador SIN identidad sensible (lo que ya piden datos.js:2475 y editores.js:7877). Pasaporte enmascarado.
create or replace function public.compradores_lista()
returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, kyc_status text,
              propietario text, created_at timestamptz, passport_hint text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.kyc_status, c.propietario, c.created_at,
         case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end
    from public.clients c where public.es_agente() $$;
revoke all on function public.compradores_lista() from public, anon;
grant execute on function public.compradores_lista() to authenticated;

-- 2) Buscador del asistente (app.html:1586): la búsqueda por pasaporte ocurre en servidor, máx 8, devuelve pasaporte enmascarado.
create or replace function public.comprador_buscar(p_q text)
returns table(id uuid, full_name text, email text, passport_hint text, tipo text, propietario text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_agente() then return; end if;
  if length(btrim(coalesce(p_q,''))) < 3 then return; end if;
  return query
    select c.id, c.full_name, c.email, case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end,
           c.tipo, c.propietario
      from public.clients c
     where c.full_name ilike '%'||btrim(p_q)||'%' or c.email ilike '%'||btrim(p_q)||'%' or lower(c.passport_number) = lower(btrim(p_q))  -- pasaporte: igualdad exacta, no prefijo
     limit 8;
end $$;
revoke all on function public.comprador_buscar(text) from public, anon;
grant execute on function public.comprador_buscar(text) to authenticated;

-- 3) Ficha completa de UNO (las 16 columnas de hoy), con registro y freno: >20 fichas distintas en 10 min = 42501 (admin sin freno).
create or replace function public.comprador_ficha(p_id uuid)
returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, passport_number text,
              date_of_birth date, address text, forma_juridica text, registro_num text, rep_nombre text, rep_cargo text,
              kyc_status text, propietario text, created_at timestamptz)
language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_n int;
begin
  if not public.es_agente() then return; end if;
  if not public.es_admin() then
    select count(distinct a.client_id) into v_n from public.comprador_ficha_accesos a
     where a.user_id = v_uid and a.en > now() - interval '10 minutes' and a.client_id <> p_id;
    if v_n >= 20 then raise exception 'Demasiadas fichas abiertas seguidas: espera unos minutos' using errcode = '42501'; end if;
  end if;
  if exists (select 1 from public.clients c where c.id = p_id) then
    insert into public.comprador_ficha_accesos(user_id, client_id) values (v_uid, p_id);
  end if;
  return query
    select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.passport_number, c.date_of_birth, c.address,
           c.forma_juridica, c.registro_num, c.rep_nombre, c.rep_cargo, c.kyc_status, c.propietario, c.created_at
      from public.clients c where c.id = p_id;
end $$;
revoke all on function public.comprador_ficha(uuid) from public, anon;
grant execute on function public.comprador_ficha(uuid) to authenticated;

