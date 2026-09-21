create or replace function public.traspasar_cliente_con_documentos(
  p_client_id uuid,
  p_nuevo_propietario text,
  p_motivo text
)
returns table (
  propietario_anterior          text,
  contratos_movidos             int,
  contratos_omitidos_firmados   int,
  contratos_omitidos_otro_autor int,
  contratos_omitidos_sin_autor  int,
  facturas_movidas              int,
  facturas_movidas_anuladas     int,
  facturas_omitidas_otro_autor  int,
  facturas_omitidas_sin_autor   int
)
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_anterior      text;
  v_contratos     uuid[];
  v_cont_movidos  uuid[];
  v_fact_movidas  uuid[];
  v_fact_anuladas int;
  v_quien         text;
begin
  if not public.es_super_admin() then
    raise exception 'Solo super_admin puede traspasar contratos y facturas junto con la ficha'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'Falta el motivo del traspaso' using errcode = '23514';
  end if;

  if not exists (select 1 from public.usuarios u where u.email = p_nuevo_propietario and u.activo) then
    raise exception 'El nuevo propietario no es un usuario activo del equipo' using errcode = '23514';
  end if;

  v_quien := auth.email();

  select c.propietario into v_anterior from public.clients c where c.id = p_client_id;
  if not found then
    raise exception 'No existe esa ficha de comprador' using errcode = '23503';
  end if;
  if v_anterior is not distinct from p_nuevo_propietario then
    raise exception 'Esa ficha ya es de ese propietario' using errcode = '23514';
  end if;

  -- 1. la ficha
  insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
  values ('clients', p_client_id, 'propietario', v_anterior, p_nuevo_propietario, p_motivo, v_quien);

  update public.clients set propietario = p_nuevo_propietario where id = p_client_id;

  -- 2. sus contratos (cualquier rol en contrato_compradores)
  select coalesce(array_agg(distinct cc.contrato_id), '{}')
    into v_contratos
    from public.contrato_compradores cc
   where cc.client_id = p_client_id;

  select count(*) into contratos_omitidos_firmados
    from public.contratos
   where id = any(v_contratos) and creado_por = v_anterior and coalesce(bloqueado, false);

  select count(*) into contratos_omitidos_otro_autor
    from public.contratos
   where id = any(v_contratos) and creado_por is not null and creado_por is distinct from v_anterior;

  select count(*) into contratos_omitidos_sin_autor
    from public.contratos
   where id = any(v_contratos) and creado_por is null;

  set local session_replication_role = replica;

  with mov as (
    update public.contratos
       set creado_por = p_nuevo_propietario
     where id = any(v_contratos)
       and creado_por = v_anterior
       and not coalesce(bloqueado, false)
     returning id
  )
  select array_agg(id) into v_cont_movidos from mov;

  contratos_movidos := coalesce(array_length(v_cont_movidos, 1), 0);
  if v_cont_movidos is not null then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'contratos', cid, 'creado_por', v_anterior, p_nuevo_propietario, p_motivo, v_quien
      from unnest(v_cont_movidos) cid;
  end if;

  -- 3. sus facturas y recibis (misma tabla, mismo criterio)
  select count(*) into facturas_omitidas_otro_autor
    from public.facturas
   where creado_por is not null and creado_por is distinct from v_anterior
     and (contrato_id = any(v_contratos) or client_id = p_client_id);

  select count(*) into facturas_omitidas_sin_autor
    from public.facturas
   where creado_por is null
     and (contrato_id = any(v_contratos) or client_id = p_client_id);

  with mov as (
    update public.facturas
       set creado_por = p_nuevo_propietario
     where creado_por = v_anterior
       and (contrato_id = any(v_contratos) or client_id = p_client_id)
     returning id, anulada
  )
  select array_agg(id), count(*) filter (where anulada)
    into v_fact_movidas, v_fact_anuladas
    from mov;

  facturas_movidas := coalesce(array_length(v_fact_movidas, 1), 0);
  facturas_movidas_anuladas := coalesce(v_fact_anuladas, 0);
  if v_fact_movidas is not null then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'facturas', fid, 'creado_por', v_anterior, p_nuevo_propietario, p_motivo, v_quien
      from unnest(v_fact_movidas) fid;
  end if;

  propietario_anterior := v_anterior;
  return next;
end;
$$;

revoke execute on function public.traspasar_cliente_con_documentos(uuid, text, text) from public, anon;
grant  execute on function public.traspasar_cliente_con_documentos(uuid, text, text) to authenticated;

comment on function public.traspasar_cliente_con_documentos(uuid, text, text) is
  'Traspasa clients.propietario Y arrastra creado_por de sus contratos/facturas al nuevo agente (solo super_admin, motivo obligatorio, rastro en correcciones_datos). No toca contratos bloqueado=true ni contrato_closer. 17-sep-2026.';;
