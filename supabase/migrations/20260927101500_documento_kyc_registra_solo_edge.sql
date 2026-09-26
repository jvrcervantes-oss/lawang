-- destructivo-ok: sustituye documento_kyc_registra(uuid,text,text,date) por la versión solo-edge; no toca filas.
-- Revisor de código (27-sep-2026, LAW-336 bloque 2): con la RPC concedida a `authenticated`, una llamada directa
-- desde el navegador registraba un fichero sin pasar por la comprobación de bytes de la edge ficheros-kyc. El
-- encargo lo daba por «residual aceptado» sin que nadie lo aceptara. Se cierra en vez de aceptarlo: la RPC la
-- ejecuta SOLO service_role (la edge), que pasa el usuario de la sesión ya validada; dentro se actúa como ese
-- usuario (auth.uid()/auth.email() de la transacción) para que el permiso lo sigan decidiendo cliente_visible
-- y es_agente, exactamente como antes.
drop function if exists public.documento_kyc_registra(uuid, text, text, date);

create or replace function public.documento_kyc_registra(p_uid uuid, p_client uuid, p_path text, p_tipo text, p_caduca date default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_c public.clients%rowtype; v_id uuid; v_email text;
begin
  select lower(u.email) into v_email from public.usuarios u where u.user_id = p_uid and u.activo;
  if v_email is null then raise exception 'Solo el equipo sube documentos' using errcode = '42501'; end if;
  -- actuar como ese usuario hasta el final de ESTA transacción
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'email', v_email, 'role', 'authenticated')::text, true);
  if not public.es_agente() then
    raise exception 'Solo el equipo sube documentos' using errcode = '42501';
  end if;
  select * into v_c from public.clients c where c.id = p_client;
  if not found or not public.cliente_visible(v_c.propietario, v_c.id) then
    raise exception 'No encuentro ese comprador entre los tuyos' using errcode = '42501';
  end if;
  if p_path is null or p_path !~ ('^' || p_client::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp|heic|heif)$') then
    raise exception 'Ruta de documento no válida' using errcode = '22023';
  end if;
  if p_tipo is null or p_tipo not in ('passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'signed_contract', 'other') then
    raise exception 'Tipo de documento no válido' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'kyc' and o.name = p_path) then
    raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023';
  end if;
  begin
    insert into public.documents (client_id, doc_type, storage_path, status, caduca_el, subido_por)
    values (p_client, p_tipo, p_path, 'pending', p_caduca, p_uid)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ese fichero ya está registrado en una ficha' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.documento_kyc_registra(uuid, uuid, text, text, date) from public, anon, authenticated;
grant execute on function public.documento_kyc_registra(uuid, uuid, text, text, date) to service_role;
