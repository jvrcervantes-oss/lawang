-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el gemelo del maestro (erp/migraciones/20261013223000) necesita el mismo arreglo
-- Sin DROP: create or replace con la misma firma y columnas (conserva el ACL: postgres, service_role, authenticated; nada para anon). No toca filas.
--
-- TRASPASO: SE MUEVE SOLO LO DEL CLIENTE, Y LA PUERTA MIRA LO MISMO QUE SE MUEVE (13-oct-2026, hallazgos del revisor sobre 20261013143832;
--   la del receptor ya va en 20261013150447).
--
--   · COCOMPRADORES. El contrato compartido se sigue moviendo entero (orden del owner: «el traspaso SIEMPRE arrastra todo»), pero una factura o recibi
--     cuyo client_id es de OTRO cliente NO se mueve: es del agente del otro comprador. Se mueven las del cliente (client_id = el) y las que cuelgan de
--     sus contratos sin cliente (client_id NULL). Medido hoy: 3 documentos en ese caso, todos de la misma empresa que su contrato: INV00061 (anulada,
--     RP00071), PRO00218 (RP00208) y PRO00223 (CC00117).
--     Se devuelven en facturas_omitidas_otro_autor, que en Lawang pasa a significar «de otro comprador» (la firma no se puede ampliar sin DROP, y un DROP
--     en Lawang solo lo abre el owner). Lo de otro comprador es, literalmente, de otro dueno; en el maestro esa columna vale 0 siempre.
--   · LA PUERTA, SOBRE LO MISMO QUE SE MUEVE. admin_de_cliente(…, true) solo comprueba las facturas con client_id = el cliente; las de client_id NULL
--     que cuelgan de sus contratos se escapaban. Ahora, para cada contrato y cada factura que se van a mover, quien traspasa tiene que ser
--     es_admin_de(empresa) (empresa_de_contrato / empresa_de_factura: proyecto_id o sociedad). Empresa NULL → solo el admin global. 42501 con el numero.
--   · El receptor (de 20261013150447) se comprueba ahora sobre el mismo conjunto (sin las facturas de otro comprador).
--   · Pureza: tras el UPDATE se comprueba tambien que creado_por = el nuevo (un BEFORE que lo deshiciera ya no pasa por «movido»).
--   · NO se toca la marca app.via_traspaso_autor (decision de Seguridad, 13-oct): una guarda «current_user no es authenticated» dentro de los cuatro
--     triggers no protege nada (son SECURITY DEFINER, current_user es postgres; medido: dentro de un DEFINER llamado como authenticated,
--     current_user = postgres y current_setting('role') = authenticated). Lo que protege es que authenticated no escribe en contratos ni facturas,
--     ninguna funcion de public hace set_config con nombre variable y la comprobacion de fila pura.
--
-- REVERTIR: reaplicar el cuerpo de traspasar_cliente_con_documentos de 20261013150447 (create or replace, misma firma). No hay datos que deshacer.

CREATE OR REPLACE FUNCTION public.traspasar_cliente_con_documentos(p_client_id uuid, p_nuevo_propietario text, p_motivo text)
 RETURNS TABLE(propietario_anterior text, contratos_movidos integer, contratos_omitidos_firmados integer, contratos_omitidos_otro_autor integer,
               contratos_omitidos_sin_autor integer, facturas_movidas integer, facturas_movidas_anuladas integer, facturas_omitidas_otro_autor integer,
               facturas_omitidas_sin_autor integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_anterior  text;
  v_nuevo     text;
  v_motivo    text := left(btrim(coalesce(p_motivo, '')), 500);
  v_quien     text := (select auth.email());
  v_contratos uuid[];
  v_facturas  uuid[];
  v_ficha     boolean;
  v_impuro    text;
  v_falta     record;
begin
  -- Puerta PRIMERO (antes de leer, bloquear o contestar nada de la ficha o del receptor)
  if not public.es_admin_en_alguna_empresa() then
    raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501';
  end if;
  if not public.admin_de_cliente(p_client_id, true) then
    raise exception 'Traspasar una ficha lo hace un administrador de las empresas de este comprador' using errcode = '42501';
  end if;
  if char_length(v_motivo) < 3 then
    raise exception 'Escribe el motivo del traspaso: es lo que lo explica dentro de un año' using errcode = '22023';
  end if;
  select c.propietario into v_anterior from public.clients c where c.id = p_client_id for update;
  if not found then raise exception 'Esa ficha de comprador no existe' using errcode = '22023'; end if;
  select lower(u.email) into v_nuevo from public.usuarios u
   where lower(u.email) = lower(btrim(coalesce(p_nuevo_propietario, ''))) and u.activo limit 1;
  if v_nuevo is null then
    raise exception 'El nuevo propietario no es un usuario activo del equipo' using errcode = '22023';
  end if;
  if not public.es_admin() and not public.comparte_empresa_con(v_nuevo) then
    raise exception 'El nuevo propietario debe ser de tu empresa' using errcode = '22023';
  end if;

  -- Lo que se mueve, calculado UNA vez: todos los contratos del cliente (cualquier rol) y las facturas/recibis del cliente o sin cliente colgadas de
  -- esos contratos. Las de OTRO cliente (cocomprador) se quedan con su dueno.
  select coalesce(array_agg(distinct cc.contrato_id), '{}') into v_contratos
    from public.contrato_compradores cc where cc.client_id = p_client_id;
  perform 1 from public.contratos k where k.id = any (v_contratos) for update;
  select coalesce(array_agg(f.id), '{}') into v_facturas
    from public.facturas f
   where f.client_id = p_client_id or (f.contrato_id = any (v_contratos) and f.client_id is null);
  perform 1 from public.facturas f where f.id = any (v_facturas) for update;

  -- Quien traspasa es admin de la empresa de CADA cosa que se mueve (el admin global, de todas)
  with docs as (
    select public.empresa_de_contrato(k.id) as empresa, k.numero from public.contratos k where k.id = any (v_contratos)
    union all
    select public.empresa_de_factura(f.id), f.numero from public.facturas f where f.id = any (v_facturas)
  )
  select d.empresa, d.numero into v_falta from docs d where not public.es_admin_de(d.empresa) order by d.numero limit 1;
  if found then
    raise exception 'Traspasar % lo hace un administrador de su empresa («%»)', v_falta.numero, coalesce(v_falta.empresa, 'sin empresa')
      using errcode = '42501';
  end if;

  -- El receptor tiene que poder ver TODO lo que recibe (vale tambien para el admin global; de 20261013150447)
  with docs as (
    select public.empresa_de_contrato(k.id) as empresa, k.numero from public.contratos k where k.id = any (v_contratos)
    union all
    select public.empresa_de_factura(f.id), f.numero from public.facturas f where f.id = any (v_facturas)
  ), conjunto as (
    select d.empresa, min(d.numero) as numero from docs d group by d.empresa
    union all
    select e, null from public.usuarios u, unnest(u.empresas) e
     where not exists (select 1 from docs) and lower(u.email) = lower(coalesce(v_anterior, ''))
  )
  select c.empresa, c.numero into v_falta from conjunto c where not public.usuario_en_empresa(v_nuevo, c.empresa) order by c.numero nulls last limit 1;
  if found then
    raise exception 'No se puede traspasar a %: no podria ver lo que recibe (% es de la empresa «%» y esa persona no es de ella)',
      v_nuevo, coalesce(v_falta.numero, 'la ficha'), coalesce(v_falta.empresa, 'sin empresa') using errcode = '22023';
  end if;

  v_ficha := lower(coalesce(v_anterior, '')) is distinct from v_nuevo;

  -- Omitidos: solo las facturas de OTRO comprador colgadas de sus contratos (columna facturas_omitidas_otro_autor = «de otro comprador»)
  contratos_omitidos_firmados := 0; contratos_omitidos_otro_autor := 0; contratos_omitidos_sin_autor := 0; facturas_omitidas_sin_autor := 0;
  select count(*)::int into facturas_omitidas_otro_autor from public.facturas f
   where f.contrato_id = any (v_contratos) and f.client_id is not null and f.client_id <> p_client_id;

  -- La marca solo alrededor de los dos UPDATE de autor (cabecera de 20261013143832)
  perform set_config('app.via_traspaso_autor', 'on', true);

  with mov as (
    update public.contratos k set creado_por = v_nuevo
      from (select x.id, x.numero, x.creado_por as antes, to_jsonb(x) - 'creado_por' as resto from public.contratos x
             where x.id = any (v_contratos) and lower(coalesce(x.creado_por, '')) <> v_nuevo) s
     where k.id = s.id
     returning k.id, s.numero, s.antes, ((to_jsonb(k) - 'creado_por') = s.resto and k.creado_por is not distinct from v_nuevo) as puro
  ), rastro as (
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'contratos', m.id, 'creado_por', m.antes, v_nuevo, v_motivo, v_quien from mov m
    returning 1
  )
  select count(*)::int, min(m.numero) filter (where not m.puro)
    into contratos_movidos, v_impuro
    from mov m;
  if v_impuro is not null then
    raise exception 'Traspaso parado: al cambiar el autor de % cambiaria algo mas que el autor. No se ha movido nada; avisa al estudio.', v_impuro
      using errcode = '55000';
  end if;

  with mov as (
    update public.facturas f set creado_por = v_nuevo
      from (select x.id, x.numero, x.creado_por as antes, to_jsonb(x) - 'creado_por' as resto from public.facturas x
             where x.id = any (v_facturas) and lower(coalesce(x.creado_por, '')) <> v_nuevo) s
     where f.id = s.id
     returning f.id, s.numero, s.antes, coalesce(f.anulada, false) as anulada_ya,
               ((to_jsonb(f) - 'creado_por') = s.resto and f.creado_por is not distinct from v_nuevo) as puro
  ), rastro as (
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'facturas', m.id, 'creado_por', m.antes, v_nuevo, v_motivo, v_quien from mov m
    returning 1
  )
  select count(*)::int, (count(*) filter (where m.anulada_ya))::int, min(m.numero) filter (where not m.puro)
    into facturas_movidas, facturas_movidas_anuladas, v_impuro
    from mov m;
  if v_impuro is not null then
    raise exception 'Traspaso parado: al cambiar el autor de % cambiaria algo mas que el autor. No se ha movido nada; avisa al estudio.', v_impuro
      using errcode = '55000';
  end if;

  perform set_config('app.via_traspaso_autor', 'off', true);

  -- La ficha (sus triggers corren normal: la marca ya esta apagada)
  if v_ficha then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', p_client_id, 'propietario', v_anterior, v_nuevo, v_motivo, v_quien);
    update public.clients set propietario = v_nuevo where id = p_client_id;
  elsif contratos_movidos = 0 and facturas_movidas = 0 then
    raise exception 'Esa ficha y todos sus contratos y facturas ya son de esa persona' using errcode = '22023';
  end if;

  propietario_anterior := v_anterior;
  return next;
end;
$function$;

do $$
declare d text := pg_get_functiondef('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure);
begin
  if not (select pr.prosecdef and 'search_path=""' = any (coalesce(pr.proconfig, '{}')) from pg_proc pr
           where pr.oid = 'public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure) then
    raise exception 'traspaso: no es DEFINER con search_path vacio';
  end if;
  if has_function_privilege('anon', 'public.traspasar_cliente_con_documentos(uuid,text,text)', 'execute') then raise exception 'traspaso: anon ejecuta'; end if;
  if position('usuario_en_empresa(v_nuevo' in d) = 0 or position('es_admin_de(d.empresa)' in d) = 0 or position('f.client_id <> p_client_id' in d) = 0 then
    raise exception 'traspaso: falta la comprobacion del receptor, la puerta por documento o el filtro de cocompradores';
  end if;
end $$;
