-- REVERSION del BLOQUE 11.2 (migracion 20261008960100): devuelve comprador_ficha al texto de antes (7-oct-2026): alcance acotado solo ve lo visible; sin alcance acotado, cualquier ficha por id.
-- destructivo-ok: solo reemplaza 1 funcion de lectura por su texto anterior
create or replace function public.comprador_ficha(p_id uuid)
 returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, passport_number text, date_of_birth date, address text, forma_juridica text, registro_num text, rep_nombre text, rep_cargo text, kyc_status text, propietario text, created_at timestamp with time zone)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid()); v_n int;
begin
  if not public.es_agente() then return; end if;
  if (select public.alcance_restringido())
     and not exists (select 1 from public.clients c0 where c0.id = p_id and public.cliente_visible(c0.propietario, c0.id)) then
    return;
  end if;
  if not public.es_admin_en_alguna_empresa() then
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
end $function$;
