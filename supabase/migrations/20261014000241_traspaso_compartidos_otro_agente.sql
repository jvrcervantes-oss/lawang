-- Traspaso de ficha: un contrato compartido con un comprador cuya ficha es de OTRO agente no se mueve; se avisa (14-oct-2026).
--
-- POR QUE: decision del owner (14-oct-2026, AskUserQuestion): «un contrato compartido con un comprador cuya ficha es de OTRO agente
-- no se mueve; se avisa». Desde 20261013143832 el traspaso movia TODOS los contratos del cliente; si uno lo comparte con otro comprador
-- que lleva otro agente, ese agente dejaba de ver el contrato de SU cliente (puede_ver_contrato mira creado_por).
-- QUE CAMBIA (sobre el cuerpo de 20261013154657; el resto es identico):
--   · Candidatos = los contratos del cliente (contrato_compradores, cualquier rol). Se EXCLUYE el que tiene otro comprador (client_id <> el
--     cliente) con propietario no nulo (ni vacio) y distinto del NUEVO dueno, en minusculas. Sin dueno, o ya del nuevo dueno: se mueve.
--   · Las facturas que cuelgan de un contrato excluido tampoco se mueven, tengan o no el client_id del cliente: van con su contrato.
--   · contratos_omitidos_otro_autor = los excluidos (en Lawang: «compartidos con otro agente»). facturas_omitidas_otro_autor = TODAS las
--     facturas colgadas de los contratos candidatos que no se mueven (las de otro comprador, como antes, y las de los excluidos). Firma igual.
--   · El for update, la puerta por documento y el receptor operan sobre el conjunto FINAL: un contrato excluido (ni sus facturas) no
--     rechaza a quien traspasa ni al receptor. OJO, limite escrito: la puerta de arriba, admin_de_cliente(p_client_id, true), sigue mirando
--     TODOS los contratos del cliente (la ficha si se mueve); no se afloja aqui, es una puerta de seguridad.
--   · Las fichas de los otros compradores se bloquean FOR SHARE antes de decidir, para que su dueno no cambie entre la decision y el
--     movimiento. Dos traspasos simultaneos de dos compradores del mismo contrato pueden acabar en 40P01 (deadlock): Postgres aborta uno
--     y se repite a mano. Aceptado: sin reintentos.
--   · Si la ficha ya es del nuevo dueno, no se mueve nada y hay excluidos, el 22023 lo dice (antes diria «todo es ya de esa persona»).
-- REVERTIR: create or replace con el cuerpo anterior (pg_get_functiondef antes de esta migracion = 20261013143832 + 150447 + 150901 +
--   153444 + 154657 aplicadas en orden; copia en el volcado diario de respaldo_instancia). Sin datos que deshacer: no escribe nada al aplicarse.
create or replace function public.traspasar_cliente_con_documentos(p_client_id uuid, p_nuevo_propietario text, p_motivo text)
 returns table(propietario_anterior text, contratos_movidos integer, contratos_omitidos_firmados integer, contratos_omitidos_otro_autor integer, contratos_omitidos_sin_autor integer, facturas_movidas integer, facturas_movidas_anuladas integer, facturas_omitidas_otro_autor integer, facturas_omitidas_sin_autor integer)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_anterior  text;
  v_nuevo     text;
  v_motivo    text := left(btrim(coalesce(p_motivo, '')), 500);
  v_quien     text := (select auth.email());
  v_contratos uuid[];
  v_compartidos uuid[];
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

  -- 14-oct (owner): las fichas de los OTROS compradores de sus contratos, quietas mientras se decide (FOR SHARE; ver cabecera, 40P01)
  perform 1 from public.clients oc
   where oc.id in (select o.client_id from public.contrato_compradores o
                    where o.client_id <> p_client_id
                      and o.contrato_id in (select cc.contrato_id from public.contrato_compradores cc where cc.client_id = p_client_id))
   order by oc.id for share;

  -- Lo que se mueve, calculado UNA vez: los contratos del cliente (cualquier rol) MENOS los compartidos con un comprador cuya ficha es de
  -- otro agente (propietario no nulo y distinto del nuevo dueno), que se quedan con su autor (v_compartidos).
  select coalesce(array_agg(k.id order by k.id) filter (where not k.compartido), '{}'),
         coalesce(array_agg(k.id order by k.id) filter (where k.compartido), '{}')
    into v_contratos, v_compartidos
    from (select c.id,
                 exists (select 1 from public.contrato_compradores o join public.clients oc on oc.id = o.client_id
                          where o.contrato_id = c.id and o.client_id <> p_client_id
                            and nullif(btrim(oc.propietario), '') is not null
                            and lower(btrim(oc.propietario)) <> v_nuevo) as compartido
            from public.contratos c
           where c.id in (select cc.contrato_id from public.contrato_compradores cc where cc.client_id = p_client_id)) k;
  -- for update SOLO de lo que se mueve
  perform 1 from public.contratos k where k.id = any (v_contratos) order by k.id for update;
  -- Facturas: las del cliente (salvo las que cuelgan de un contrato excluido: van con su contrato) y las sin cliente de los contratos
  -- que se mueven. Las de OTRO cliente (cocomprador) se quedan con su dueno.
  select coalesce(array_agg(s.id), '{}') into v_facturas
    from (select f.id from public.facturas f
           where (f.client_id = p_client_id and (f.contrato_id is null or not (f.contrato_id = any (v_compartidos))))
              or (f.contrato_id = any (v_contratos) and f.client_id is null)
           order by f.id for update of f) s;
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

  -- Omitidos: los contratos compartidos con otro agente (contratos_omitidos_otro_autor) y TODAS las facturas colgadas de los contratos
  -- del cliente que no se mueven (facturas_omitidas_otro_autor: las de otro comprador y las de los compartidos)
  contratos_omitidos_firmados := 0; contratos_omitidos_sin_autor := 0; facturas_omitidas_sin_autor := 0;
  contratos_omitidos_otro_autor := cardinality(v_compartidos);
  select count(*)::int into facturas_omitidas_otro_autor from public.facturas f
   where f.contrato_id = any (v_contratos || v_compartidos) and not (f.id = any (v_facturas));

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
  select count(*)::int, min(coalesce(m.numero, m.id::text)) filter (where not m.puro)
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
  select count(*)::int, (count(*) filter (where m.anulada_ya))::int, min(coalesce(m.numero, m.id::text)) filter (where not m.puro)
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
    if contratos_omitidos_otro_autor > 0 then
      raise exception 'Esa ficha y lo que se puede mover ya son de esa persona; % contratos compartidos con un comprador de otro agente no se mueven: revisalos a mano',
        contratos_omitidos_otro_autor using errcode = '22023';
    end if;
    raise exception 'Esa ficha y todos sus contratos y facturas ya son de esa persona' using errcode = '22023';
  end if;

  propietario_anterior := v_anterior;
  return next;
end;
$function$;
