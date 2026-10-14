-- Traspaso de ficha: bloquea TODOS los contratos candidatos antes de clasificar, y un contrato que ya es del nuevo dueno no cuenta como
-- compartido con otro agente (14-oct-2026, hallazgos del revisor sobre 20261014000241 + 20261014001411).
--
-- POR QUE (regla del owner del 14-oct, intacta: un contrato compartido con un comprador cuya ficha es de OTRO agente no se mueve; se avisa):
--   1. Carrera. 000241 clasificaba los contratos SIN bloquearlos y solo hacia FOR UPDATE de los que se mueven. Entre la clasificacion y el
--      commit, otra sesion podia dar de alta un comprador de otro agente en un contrato ya clasificado como «se mueve», y el contrato se iba
--      igual: justo lo que la regla del owner prohibe. Ahora se hace FOR UPDATE de TODOS los candidatos (los contratos del cliente en
--      contrato_compradores, cualquier rol), por id, ANTES del FOR SHARE de las fichas y de clasificar. Un alta concurrente de comprador en
--      uno de ellos espera (la FK contrato_compradores.contrato_id -> contratos pide FOR KEY SHARE, que choca con FOR UPDATE), y un alta del
--      propio cliente en un contrato nuevo espera por la ficha, que ya esta FOR UPDATE (FK client_id -> clients). El FOR UPDATE posterior
--      «solo de lo que se mueve» se quita: ya esta cubierto.
--   2. Un contrato que YA es del nuevo dueno (lower(creado_por) = v_nuevo) no cuenta como compartido-excluido aunque lo comparta con la
--      ficha de otro agente: no hay nada que quitarle a nadie. Antes contaba en contratos_omitidos_otro_autor, sus facturas del propio
--      cliente se quedaban con el autor viejo y, si no habia nada mas, el 22023 decia «revisalos a mano» sin motivo. Ahora entra en el
--      conjunto (no se reescribe: el UPDATE ya salta lo que es del nuevo dueno) y sus facturas del cliente se mueven. Al entrar en el
--      conjunto pasa por la puerta por documento y por la comprobacion del receptor, como todo lo que se mueve. Consecuencia aceptada
--      (CEO por defecto, 14-oct; reversible): si ese contrato lleva una factura sin cliente de OTRA empresa, la puerta por documento para el
--      traspaso aunque la factura ya sea del receptor (prueba U3). Medido el 14-oct en Lawang: 0 facturas sin cliente de otra empresa que la
--      de su contrato (1 sin cliente en total).
--   Bloqueos: el orden es ficha (FOR UPDATE) -> contratos candidatos (FOR UPDATE, por id) -> fichas de los otros compradores (FOR SHARE, por
--   id) -> facturas (FOR UPDATE). Dos traspasos simultaneos de dos compradores del mismo contrato pueden seguir acabando en 40P01: Postgres
--   aborta uno. Aceptado por el CEO por defecto el 14-oct (sin reintentos en servidor); la pantalla de Clientes (intranet/v4/assets/datos.js)
--   lo cuenta en llano: «Otra persona esta traspasando a otro comprador de un mismo contrato. Espera unos segundos y repitelo.»
-- QUE NO CAMBIA: firma, columnas devueltas, puertas, rastro, marca app.via_traspaso_autor y el resto del cuerpo (= 000241 + 001411).
-- REVERTIR (manda ESTA linea; la linea REVERTIR de 20261014000241 que dice «copia en el volcado diario de respaldo_instancia» es FALSA:
--   Lawang NO entra en el volcado diario (erp/instancias.json, lawang.respaldo.en_todas=false, medido 14-oct; solo copias a mano
--   supervisadas, retencion 3+1), asi que no hay tal copia de donde sacar el cuerpo anterior):
--   · al estado anterior a esta migracion: reaplicar 20261014000241 y luego 20261014001411 (en ese orden);
--   · al estado sin la regla de compartidos (13-oct): reaplicar 20261013150901, luego 20261013153444 y luego 20261013154657 (en ese orden).
--   Sin datos que deshacer: no escribe nada al aplicarse. Prueba: supabase/pruebas/traspaso_arrastra_todo.sql (casos L, U y T1/S1 nuevos).
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

  -- 14-oct (revisor): TODOS los contratos candidatos, FOR UPDATE y por id, ANTES de mirar las fichas de los otros compradores y de
  -- clasificar: un alta concurrente de comprador en uno de ellos espera (FK contrato_compradores.contrato_id -> contratos) y lo que se
  -- clasifica no cambia hasta el commit. Incluye los que luego se excluyen. (Un alta del cliente en otro contrato espera por la ficha.)
  perform 1 from public.contratos k
   where k.id in (select cc.contrato_id from public.contrato_compradores cc where cc.client_id = p_client_id)
   order by k.id for update;

  -- 14-oct (owner): las fichas de los OTROS compradores de sus contratos, quietas mientras se decide (FOR SHARE; ver cabecera, 40P01)
  perform 1 from public.clients oc
   where oc.id in (select o.client_id from public.contrato_compradores o
                    where o.client_id <> p_client_id
                      and o.contrato_id in (select cc.contrato_id from public.contrato_compradores cc where cc.client_id = p_client_id))
   order by oc.id for share;

  -- Lo que se mueve, calculado UNA vez: los contratos del cliente (cualquier rol) MENOS los compartidos con un comprador cuya ficha es de
  -- otro agente (propietario no nulo y distinto del nuevo dueno), que se quedan con su autor (v_compartidos). Un contrato que YA es del
  -- nuevo dueno no es compartido-excluido (14-oct, revisor): entra en el conjunto y sus facturas del cliente se mueven.
  select coalesce(array_agg(k.id order by k.id) filter (where not k.compartido), '{}'),
         coalesce(array_agg(k.id order by k.id) filter (where k.compartido), '{}')
    into v_contratos, v_compartidos
    from (select c.id,
                 (lower(coalesce(c.creado_por, '')) <> v_nuevo
                  and exists (select 1 from public.contrato_compradores o join public.clients oc on oc.id = o.client_id
                               where o.contrato_id = c.id and o.client_id <> p_client_id
                                 and nullif(btrim(oc.propietario), '') is not null
                                 and lower(btrim(oc.propietario)) <> v_nuevo)) as compartido
            from public.contratos c
           where c.id in (select cc.contrato_id from public.contrato_compradores cc where cc.client_id = p_client_id)) k;
  -- (sin segundo for update de contratos: todos los candidatos ya estan bloqueados arriba)
  -- Facturas: las del cliente (salvo las que cuelgan de un contrato excluido: van con su contrato) y las sin cliente de los contratos
  -- que se mueven. Las de OTRO cliente (cocomprador) se quedan con su dueno.
  select coalesce(array_agg(s.id), '{}') into v_facturas
    from (select f.id from public.facturas f
           where (f.client_id = p_client_id and (f.contrato_id is null or not (f.contrato_id = any (v_compartidos))))
              or (f.contrato_id = any (v_contratos) and f.client_id is null)
              -- 14-oct: y las de OTRO comprador del contrato que se mueve cuya ficha ya es del nuevo dueno
              or (f.contrato_id = any (v_contratos) and f.client_id <> p_client_id and exists (select 1 from public.contrato_compradores o join public.clients oc on oc.id = o.client_id where o.contrato_id = f.contrato_id and o.client_id = f.client_id and lower(btrim(oc.propietario)) = v_nuevo))
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

-- Comprobacion al aplicar: sigue DEFINER con search_path vacio, anon no la ejecuta, y el cuerpo lleva los dos arreglos
do $mig$
declare d text := pg_get_functiondef('public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure);
begin
  if not (select pr.prosecdef and 'search_path=""' = any (coalesce(pr.proconfig, '{}')) from pg_proc pr
           where pr.oid = 'public.traspasar_cliente_con_documentos(uuid,text,text)'::regprocedure) then
    raise exception 'traspaso: no es DEFINER con search_path vacio';
  end if;
  if has_function_privilege('anon', 'public.traspasar_cliente_con_documentos(uuid,text,text)', 'execute') then
    raise exception 'traspaso: anon ejecuta';
  end if;
  if position('(lower(coalesce(c.creado_por, '''')) <> v_nuevo' in d) = 0 or position('order by k.id for update;' in d) = 0
     or position('for update SOLO de lo que se mueve' in d) > 0 then
    raise exception 'traspaso: falta el bloqueo de todos los candidatos o el filtro del contrato ya del nuevo dueno';
  end if;
end
$mig$;
