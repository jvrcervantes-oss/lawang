-- destructivo-ok: cambia quién puede EJECUTAR dos funciones (retirar documento, borrar ficha) y sustituye la firma de documento_kyc_retira; no toca filas.
-- Consulta de deploy (Seguridad, 27-sep-2026, LAW-336 bloque 2): `borrar_comprador` y `documento_kyc_retira`
-- se podían llamar desde el navegador saltándose la edge ficheros-kyc: la fila se borraba y el fichero se
-- quedaba suelto en el bucket. Reducir la exposición: las dos las llama SOLO la edge (service role) con el
-- usuario de la sesión ya validada, como documento_kyc_registra (20260927101500). Dentro se actúa como ese
-- usuario y deciden los helpers de siempre (es_admin, es_super_admin).

-- Actuar como un usuario del equipo hasta el final de la transacción. Solo service_role.
create or replace function public._actua_como(p_uid uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v_email text;
begin
  select lower(u.email) into v_email from public.usuarios u where u.user_id = p_uid and u.activo;
  if v_email is null then raise exception 'Tu usuario no es del equipo' using errcode = '42501'; end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'email', v_email, 'role', 'authenticated')::text, true);
  return v_email;
end $$;
revoke all on function public._actua_como(uuid) from public, anon, authenticated;
grant execute on function public._actua_como(uuid) to service_role;

-- retirar: misma lógica que 20260927110000, con p_uid delante
drop function if exists public.documento_kyc_retira(uuid, text);
create or replace function public.documento_kyc_retira(p_uid uuid, p_id uuid, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_d public.documents%rowtype; v_c public.clients%rowtype; v_conserva boolean;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;
  select * into v_d from public.documents d where d.id = p_id and d.retirado_el is null for update;
  if not found then raise exception 'Ese documento ya no está en la ficha' using errcode = '22023'; end if;
  select * into v_c from public.clients c where c.id = v_d.client_id for update;
  v_conserva := exists (select 1 from public.contrato_compradores cc where cc.client_id = v_d.client_id)
             or exists (select 1 from public.facturas f where f.client_id = v_d.client_id);

  if v_conserva then
    if not public.es_super_admin() then
      raise exception 'Este comprador tiene contratos o pagos a su nombre: su documentación KYC solo la retira un super admin, y el fichero se conserva.'
        using errcode = '42501';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Este comprador tiene contratos o pagos a su nombre: escribe por qué se retira el documento (queda registrado y el fichero se conserva)'
        using errcode = '22023';
    end if;
    update public.documents set retirado_el = now(), retirado_por = (select auth.email()), retirado_motivo = v_motivo
     where id = p_id;
  else
    delete from public.documents where id = p_id;
  end if;

  if v_c.kyc_status = 'verified' then
    update public.clients set kyc_status = 'submitted', kyc_verificado_por = null, kyc_verificado_el = null where id = v_c.id;
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', v_c.id, 'kyc_status', 'verified', 'submitted', 'se retiró un documento KYC', (select auth.email()));
  end if;

  return jsonb_build_object('conservado', v_conserva,
                            'borrar_fichero', not v_conserva,
                            'path', case when v_conserva then null else v_d.storage_path end,
                            'kyc_vuelve_a_revision', v_c.kyc_status = 'verified');
end $$;
revoke all on function public.documento_kyc_retira(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.documento_kyc_retira(uuid, uuid, text) to service_role;

-- borrar una ficha duplicada: la edge, como el super admin que lo pide (borrar_comprador lo comprueba dentro)
create or replace function public.borrar_comprador_edge(p_uid uuid, p_client_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public._actua_como(p_uid);
  return public.borrar_comprador(p_client_id);
end $$;
revoke all on function public.borrar_comprador_edge(uuid, uuid) from public, anon, authenticated;
grant execute on function public.borrar_comprador_edge(uuid, uuid) to service_role;
revoke execute on function public.borrar_comprador(uuid) from public, anon, authenticated;
