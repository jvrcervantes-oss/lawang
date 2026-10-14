-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- VUELTA ATRAS de la migracion 20261014101500 «espejo_cliente_visible» (14-oct-2026, Backend).
-- REABRE el hallazgo vivo de Seguridad (un agente con la herramienta de contratos recibe la ficha entera de cualquier cliente guardando
-- un borrador) y deja el tipo de contrato sin comprobar al editar: SOLO con OK del owner, y avisando a Seguridad.
-- Deja espeja_comprador, sincronizar_compradores y contratos_tipo_permitido con el texto EXACTO que tenian (el de las migraciones
-- 20260819150732, 20260824111810 y 20260827000855, md5 igual al vivo el 14-oct), el trigger de tipo solo en INSERT, y quita de
-- contrato_guarda (las dos lineas: alta y edicion) y comprador_ficha la linea que anadio el parche, devuelve trg_espejo_comprador y
-- trg_cliente_actualizado a su texto vivo, y despues borra las tres funciones nuevas.
-- No toca datos: los contratos y enlaces guardados mientras estuvo aplicada se quedan como estan.
-- Ensayada en la misma rama que la migracion, despues de su prueba (supabase/pruebas/espejo_vuelta.py compara con el vivo).
-- destructivo-ok: reemplaza funciones y un trigger, y borra las 3 funciones que creo la migracion (sin datos)

create or replace function public.espeja_comprador(p_datos jsonb)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
    when cl.id is null then p_datos
    else jsonb_set(p_datos, '{fields}',
           coalesce(p_datos->'fields', '{}'::jsonb) ||
           jsonb_strip_nulls(jsonb_build_object(
             'adq1_nombre',         cl.full_name,
             'adq1_pasaporte',      cl.passport_number,
             'adq1_email',          cl.email,
             'adq1_telefono',       cl.phone,
             'adq1_domicilio',      cl.address,
             'adq1_nacionalidad',   cl.nationality,
             'adq1_forma_juridica', cl.forma_juridica,
             'adq1_registro',       cl.registro_num,
             'adq1_rep_nombre',     cl.rep_nombre,
             'adq1_rep_cargo',      cl.rep_cargo,
             'adq1_tipo',           cl.tipo)))
  end
  from (select 1) x
  left join public.clients cl on cl.id = nullif(p_datos->>'adq1_client_id','')::uuid;
$function$;

create or replace function public.sincronizar_compradores(p_contrato uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text; v_cid text;
  v_client uuid;
  v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_ficha text[] := '{}';
  v_roles_vivos text[] := '{}';
  v_borrados int := 0;
begin
  select datos into v_datos from public.contratos where id = p_contrato;
  if v_datos is null then return jsonb_build_object('error', 'contrato inexistente o sin datos'); end if;

  v_gente := jsonb_build_array(jsonb_build_object(
      'rol','adquiriente_1',
      'client_id',    v_datos->>'adq1_client_id',
      'nombre',       v_datos->'fields'->>'adq1_nombre',
      'pasaporte',    v_datos->'fields'->>'adq1_pasaporte',
      'email',        v_datos->'fields'->>'adq1_email',
      'telefono',     v_datos->'fields'->>'adq1_telefono',
      'nacionalidad', v_datos->'fields'->>'adq1_nacionalidad',
      'domicilio',    v_datos->'fields'->>'adq1_domicilio'))
    || coalesce((
      select jsonb_agg(jsonb_build_object(
               'rol','adquiriente_' || (ord + 1),
               'client_id', e->>'client_id',
               'nombre', e->>'nombre', 'pasaporte', e->>'pasaporte', 'email', e->>'email',
               'telefono', e->>'telefono', 'nacionalidad', e->>'nacionalidad',
               'domicilio', e->>'domicilio') order by ord)
      from jsonb_array_elements(
             case when jsonb_typeof(v_datos->'compradores') = 'array'
                  then v_datos->'compradores' else '[]'::jsonb end) with ordinality t(e, ord)
      where ord + 1 <= 9), '[]'::jsonb);

  for p in select value from jsonb_array_elements(v_gente) loop
    v_nombre := btrim(coalesce(p->>'nombre',''));
    continue when v_nombre = '';
    v_rol  := p->>'rol';
    -- Este rol EXISTE en el documento. Se apunta aunque luego no se consiga
    -- enlazar: lo que decide si una fila sobra es el documento, no el enlace.
    v_roles_vivos := v_roles_vivos || v_rol;
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));
    v_cid  := nullif(btrim(coalesce(p->>'client_id','')), '');

    v_client := null;

    if v_cid is not null then
      begin
        select id into v_client from public.clients where id = v_cid::uuid;
      exception when invalid_text_representation then
        v_client := null;
      end;
    end if;

    if v_client is null then
      if v_pas is null and v_mail is null then
        v_sin_id := v_sin_id || v_nombre;
        continue;
      end if;
      if v_pas is not null then
        select id into v_client from public.clients
         where lower(btrim(passport_number)) = lower(v_pas) limit 1;
      end if;
      if v_client is null and v_mail is not null then
        select id into v_client from public.clients
         where lower(email) = v_mail
         order by (tipo = 'persona') desc, created_at
         limit 1;
      end if;
    end if;

    if v_client is null then
      v_sin_ficha := v_sin_ficha || v_nombre;
      continue;
    end if;

    insert into public.contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  /* LOS FANTASMAS. Un contrato que paso de cuatro compradores a dos dejaba
     adquiriente_3 y adquiriente_4 enlazados a las personas de la version
     anterior, y Operaciones los seguia enseñando. Se borran los roles que el
     documento YA NO NOMBRA. Si el documento no nombra a NADIE no se borra nada:
     eso es casi siempre un `datos` a medio escribir, y vaciar la tabla por eso
     convertiria un guardado intermedio en una perdida de enlaces. */
  if array_length(v_roles_vivos, 1) is not null then
    delete from public.contrato_compradores
     where contrato_id = p_contrato
       and rol <> all(v_roles_vivos);
    get diagnostics v_borrados = row_count;
  end if;

  return jsonb_build_object('altas', 0, 'enlaces', v_enlaces,
                            'retirados', v_borrados,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'sin_ficha',         to_jsonb(v_sin_ficha));
end $function$;

create or replace function public.contratos_tipo_permitido()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_rol    text;
  v_tipos  text[];
begin
  -- Sin sesión (service role, edges, cron) no se comprueba: esos caminos ya
  -- tienen su propia puerta y bloquearlos aquí rompería la firma automática.
  if auth.uid() is null then
    return new;
  end if;

  select rol, tipos_contrato into v_rol, v_tipos
    from public.usuarios where user_id = auth.uid();

  -- Solo aplica a AGENTES: un administrador trabaja con todos los tipos por
  -- definición, y así además nadie puede dejarse a sí mismo sin poder emitir.
  if v_rol is distinct from 'agente' then
    return new;
  end if;

  if v_tipos is null or cardinality(v_tipos) = 0 then
    raise exception 'No tienes ningún tipo de contrato asignado. Pídelo a un administrador en Usuarios.'
      using errcode = '42501';
  end if;

  if not (new.tipo = any(v_tipos)) then
    raise exception 'No tienes permiso para emitir contratos de tipo "%". Pídeselo a un administrador en Usuarios.', new.tipo
      using errcode = '42501';
  end if;

  return new;
end;
$function$;
create or replace trigger trg_contratos_tipo_permitido before insert on public.contratos
  for each row execute function public.contratos_tipo_permitido();
grant execute on function public.contratos_tipo_permitido() to authenticated;

-- contrato_guarda y comprador_ficha: se deshace el parche sobre la definicion viva (lanza si no encuentra lo que puso la migracion)
do $vuelta$
declare
  v_def text;
  c_alta  constant text := 'perform public._contrato_clientes_comprueba(p_id, v_datos);' || E'\n    '
                            || 'insert into public.contratos (tipo, comprador_nombre, proyecto_nombre, precio_total, moneda, fecha_firma,';
  c_edic  constant text := E'\n    perform public._contrato_clientes_comprueba(p_id, v_datos);';
  c_nueva constant text := 'if not public\._cliente_ficha_visible\(p_id\) then\s+return;\s+end if;';
begin
  select pg_get_functiondef('public.contrato_guarda(uuid,jsonb)'::regprocedure) into v_def;
  if position('_contrato_clientes_comprueba' in v_def) > 0 then
    if position(c_alta in v_def) = 0 or position(c_edic in v_def) = 0 then
      raise exception 'vuelta atras: contrato_guarda nombra _contrato_clientes_comprueba pero no con las dos lineas del parche; se revisa a mano';
    end if;
    v_def := replace(v_def, c_alta, 'insert into public.contratos (tipo, comprador_nombre, proyecto_nombre, precio_total, moneda, fecha_firma,');
    v_def := replace(v_def, c_edic, '');
    if position('_contrato_clientes_comprueba' in v_def) > 0 then
      raise exception 'vuelta atras: contrato_guarda sigue nombrando _contrato_clientes_comprueba tras quitar el parche; se revisa a mano';
    end if;
    execute v_def;
  end if;

  select pg_get_functiondef('public.comprador_ficha(uuid)'::regprocedure) into v_def;
  if position('_cliente_ficha_visible' in v_def) > 0 then
    if (select count(*) from regexp_matches(v_def, c_nueva, 'g')) <> 1 then
      raise exception 'vuelta atras: comprador_ficha nombra _cliente_ficha_visible pero no con la linea del parche; se revisa a mano';
    end if;
    execute regexp_replace(v_def, c_nueva,
      E'if not exists (\n'
      || E'       select 1 from public.clients c0\n'
      || E'        where c0.id = p_id\n'
      || E'          and (public.cliente_visible(c0.propietario, c0.id)\n'
      || E'               or (not (select public.alcance_restringido())\n'
      || E'                   and exists (select 1 from public.contrato_compradores cc\n'
      || E'                                where cc.client_id = c0.id and public.puede_ver_contrato(cc.contrato_id))))) then\n'
      || E'    return;\n'
      || E'  end if;');
  end if;
end $vuelta$;

-- Los dos disparadores del espejo, con el texto EXACTO del vivo del 14-oct (md5 bbe93a24dd78b50f42e8f1ebb34c0ecb y
-- dafee300019a9954d0ce507c8dd4bf8a); sus permisos ya eran solo postgres y service_role, como los deja la migracion.
create or replace function public.trg_espejo_comprador()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if coalesce(new.bloqueado, false) then return new; end if;
  if exists (select 1 from public.contrato_firmas cf where cf.contrato_id = new.id) then return new; end if;
  new.datos := public.espeja_comprador(new.datos);
  return new;
end $function$;

create or replace function public.trg_cliente_actualizado()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if new.full_name is not distinct from old.full_name
     and new.passport_number is not distinct from old.passport_number
     and new.email          is not distinct from old.email
     and new.phone          is not distinct from old.phone
     and new.address        is not distinct from old.address
     and new.nationality    is not distinct from old.nationality
     and new.forma_juridica is not distinct from old.forma_juridica
     and new.registro_num   is not distinct from old.registro_num
     and new.rep_nombre     is not distinct from old.rep_nombre
     and new.rep_cargo      is not distinct from old.rep_cargo
     and new.tipo           is not distinct from old.tipo then
    return new;
  end if;

  -- adq1_client_id es COLUMNA generada (espejo de datos->>'adq1_client_id'):
  -- filtrar por la rama del jsonb descomprimía todos los contratos (timeout).
  update public.contratos c
     set datos = public.espeja_comprador(c.datos),
         comprador_nombre = case
           when jsonb_typeof(c.datos->'compradores') = 'array'
                and jsonb_array_length(c.datos->'compradores') > 0
             then c.comprador_nombre
           else new.full_name end
   where c.adq1_client_id = new.id
     and not coalesce(c.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas f
     set cliente_nombre = new.full_name,
         datos = jsonb_set(f.datos, '{fields}',
                   coalesce(f.datos->'fields','{}'::jsonb) ||
                   jsonb_strip_nulls(jsonb_build_object(
                     'cliente_nombre',    new.full_name,
                     'cliente_documento', new.passport_number,
                     'cliente_email',     new.email,
                     'cliente_domicilio', new.address)))
   where f.client_id = new.id
     and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)
     and coalesce(f.cliente_nombre,'') not like '%' || chr(183) || '%'
     and not exists (
       select 1 from public.contratos c
        where c.id = f.contrato_id
          and jsonb_typeof(c.datos->'compradores') = 'array'
          and jsonb_array_length(c.datos->'compradores') > 0);

  return new;
end $function$;

drop function if exists public._espejo_autor_ve(uuid, text);
drop function if exists public._contrato_clientes_comprueba(uuid, jsonb);
drop function if exists public._cliente_ficha_visible(uuid);
