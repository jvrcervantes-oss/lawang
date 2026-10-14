-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el gemelo del maestro (erp/migraciones/20261013223000) necesita el mismo arreglo
-- Sin DROP: create or replace con la misma firma y columnas (conserva el ACL: postgres, service_role, authenticated; nada para anon). No toca filas.
--
-- TRASPASO: EL RECEPTOR TIENE QUE PODER VER LO QUE RECIBE (13-oct-2026, veredicto de Seguridad sobre 20261013143832: NO hasta cerrar esto).
--
-- QUE FALTABA. traspasar_cliente_con_documentos solo comprobaba al receptor con comparte_empresa_con(v_nuevo), y SOLO si quien traspasa no es admin
--   global: un admin/super_admin podia pasar un cliente de Lawang (con contratos firmados) a un agente que solo es de Sandal Woods. La base lo aceptaba,
--   el receptor no veia nada (puede_ver_contrato le cierra lo de otra empresa) y la ficha quedaba «de nadie que la vea». Es el sintoma del caso real
--   (RP00261 traspasado y sin ver). Medido hoy antes de esta migracion: p@pabloglobal.es (admin global) traspasa el cliente 1273c81b (Lawang, contrato
--   firmado) a david@newconcisa.com (agente solo de sandal_woods) → PASA.
--
-- QUE HACE AHORA (solo esto; el resto de hallazgos del revisor va en la migracion siguiente):
--   · Receptor: usuario_en_empresa(v_nuevo, e) para TODA empresa e de lo que se mueve = empresas de sus contratos (empresa_de_contrato) ∪ empresas de sus
--     facturas (empresa_de_factura: sale de su proyecto_id o de su sociedad, no del contrato). Una empresa NULL (contrato sin proyecto) se comprueba igual:
--     usuario_en_empresa(x, NULL) solo es cierto para un global sin empresas, lo mismo que exige puede_ver_contrato. Si no hay documentos, el conjunto son
--     las empresas del propietario actual de la ficha (sus usuarios.empresas); si tampoco hay (ficha sin dueno o dueno global sin empresas), no se exige
--     empresa. Vale TAMBIEN para el admin global (antes se saltaba la comprobacion entera). Rechazo: 22023 con el documento y la empresa.
--   · La puerta (es_admin_en_alguna_empresa + admin_de_cliente exclusivo) va ANTES del «for update» y de los errores «no es usuario activo» / «la ficha no
--     existe»: un admin_empresa ya no puede averiguar que emails estan activos ni bloquear un instante una ficha ajena. Una ficha que no existe da 42501.
--
-- REVERTIR: reaplicar el cuerpo de traspasar_cliente_con_documentos de 20261013143832 (create or replace, misma firma). No hay datos que deshacer.

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

  -- Lo que se mueve: todos los contratos del cliente (cualquier rol) y todos sus documentos, cerrados para escritura mientras dura el traspaso
  select coalesce(array_agg(distinct cc.contrato_id), '{}') into v_contratos
    from public.contrato_compradores cc where cc.client_id = p_client_id;
  perform 1 from public.contratos k where k.id = any (v_contratos) for update;
  perform 1 from public.facturas f where f.contrato_id = any (v_contratos) or f.client_id = p_client_id for update;

  -- El receptor tiene que poder ver TODO lo que recibe (vale tambien para el admin global)
  with docs as (
    select public.empresa_de_contrato(k.id) as empresa, k.numero from public.contratos k where k.id = any (v_contratos)
    union all
    select public.empresa_de_factura(f.id), f.numero from public.facturas f where f.contrato_id = any (v_contratos) or f.client_id = p_client_id
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

  -- Ya no se omite nada: las columnas de «omitidos» se quedan (la firma no cambia) y valen 0
  contratos_omitidos_firmados := 0; contratos_omitidos_otro_autor := 0; contratos_omitidos_sin_autor := 0;
  facturas_omitidas_otro_autor := 0; facturas_omitidas_sin_autor := 0;

  -- La marca solo alrededor de los dos UPDATE de autor (cabecera de 20261013143832)
  perform set_config('app.via_traspaso_autor', 'on', true);

  with mov as (
    update public.contratos k set creado_por = v_nuevo
      from (select x.id, x.numero, x.creado_por as antes, to_jsonb(x) - 'creado_por' as resto from public.contratos x
             where x.id = any (v_contratos) and lower(coalesce(x.creado_por, '')) <> v_nuevo) s
     where k.id = s.id
     returning k.id, s.numero, s.antes, (to_jsonb(k) - 'creado_por') = s.resto as puro
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
             where (x.contrato_id = any (v_contratos) or x.client_id = p_client_id)
               and lower(coalesce(x.creado_por, '')) <> v_nuevo) s
     where f.id = s.id
     returning f.id, s.numero, s.antes, coalesce(f.anulada, false) as anulada_ya, (to_jsonb(f) - 'creado_por') = s.resto as puro
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
begin
  if not (select pr.prosecdef and 'search_path=""' = any (coalesce(pr.proconfig, '{}')) from pg_proc pr
           where pr.oid = 'public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure) then
    raise exception 'traspaso: no es DEFINER con search_path vacio';
  end if;
  if has_function_privilege('anon', 'public.traspasar_cliente_con_documentos(uuid,text,text)', 'execute') then raise exception 'traspaso: anon ejecuta'; end if;
  if position('usuario_en_empresa(v_nuevo' in pg_get_functiondef('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure)) = 0 then
    raise exception 'traspaso: falta la comprobacion del receptor';
  end if;
end $$;
