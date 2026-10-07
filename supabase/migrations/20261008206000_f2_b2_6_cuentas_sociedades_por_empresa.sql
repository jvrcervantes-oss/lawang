-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 6 (8-oct-2026): CUENTAS DE COBRO Y SOCIEDADES EDITABLES POR SU EMPRESA.
--   Un super_admin_empresa crea y edita las cuentas de cobro de SU empresa (cuentas_bancarias.empresa = la suya, fijada en el servidor; con dos empresas elige una de las suyas) y edita la sociedad
--   emisora ligada a SU empresa (empresas.sociedad_clave). Nunca toca la cuenta o la sociedad de otra empresa, ni las que no tienen empresa (terceros, escrow, sociedad HK/SG/Lux), ni da de alta sociedades
--   (una sociedad nueva no tiene empresa a la que ligarse: sigue siendo del propietario/super global). Un admin_empresa NO edita cuentas ni sociedades: igual que un admin global hoy (solo super).
--   Reparto de cuentas por proyecto/tipo (p_reparto): un rol de empresa solo reparte a nivel de PROYECTO de su empresa y solo con cuentas suyas o sin empresa; la plantilla de contrato (global) sigue siendo de los super globales.
--   cuentas_uso: cada super ve el uso de las cuentas que puede editar. sociedades_ajustes_datos: lista solo las sociedades de su empresa (un admin global, todas, con la misma forma de antes).
--   sociedades_log: lo ve el super de la sociedad.
--   Dato compartido sin empresa que queda GLOBAL a proposito (decision escrita): ajustes_config_* y ajustes_log de config_instancia (URLs y correos de sistema de TODA la instancia), solicitudes_cambio y
--   resolver_solicitud_cambio (aprobacion por Telegram de un super global; las filas llevan datos personales de clientes de las dos empresas), gasto_categorias (catalogo de lectura sin RPC de escritura).
--   Los 34 de hoy: sin cambio.
-- destructivo-ok: create or replace de funciones, funciones nuevas, alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql

create or replace function public._super_o_empresa() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_super_admin() or public._super_empresa_alguna()) then
    raise exception 'Cuentas de cobro, reparto y sociedades son solo para super_admin' using errcode = '42501';
  end if;
end $$;

create or replace function public._reparto_valida_empresa(p_niveles jsonb, p_mis text[]) returns void
language plpgsql stable security definer set search_path = '' as $$
declare n jsonb; v_proy uuid;
begin
  if p_niveles is null or jsonb_typeof(p_niveles) <> 'array' then
    raise exception 'Reparto sin niveles' using errcode = '22023';
  end if;
  for n in select * from jsonb_array_elements(p_niveles) loop
    v_proy := nullif(n->>'proyecto_id', '')::uuid;
    if v_proy is null then
      raise exception 'El reparto por tipo de contrato (plantilla) es global: lo hace un super admin global' using errcode = '42501';
    end if;
    if not exists (select 1 from public.proyectos pr where pr.id = v_proy and pr.empresa = any (p_mis)) then
      raise exception 'Ese proyecto no es de tu empresa' using errcode = '42501';
    end if;
    if jsonb_typeof(n->'claves') = 'array' and exists (
         select 1 from jsonb_array_elements_text(n->'claves') x
           join public.cuentas_bancarias c on c.clave = x
          where c.empresa is not null and not (c.empresa = any (p_mis))) then
      raise exception 'Hay una cuenta del reparto que es de otra empresa' using errcode = '42501';
    end if;
  end loop;
end $$;

revoke all on function public._super_o_empresa() from public, anon, authenticated, lw_lector;
revoke all on function public._reparto_valida_empresa(jsonb, text[]) from public, anon, authenticated, lw_lector;

create or replace function public.cuenta_bancaria_guarda(p_clave text, p_datos jsonb, p_nueva boolean default false, p_reparto jsonb default null) returns text
language plpgsql security definer set search_path = '' as $function$
declare
  v_clave text := lower(btrim(coalesce(p_clave, '')));
  v_extra jsonb := case when p_datos ? 'extra' and jsonb_typeof(p_datos->'extra') <> 'null' then p_datos->'extra' else '""'::jsonb end;
  v_propia boolean := case when jsonb_typeof(p_datos->'es_propia') = 'boolean' then (p_datos->>'es_propia')::boolean end;
  v_n int;
  v_rest boolean := not public.es_super_admin();
  v_mis text[]; v_emp text; v_old_emp text; v_hay boolean;
begin
  perform public._super_o_empresa();
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Faltan los datos de la cuenta' using errcode = '22023'; end if;
  if v_rest then
    select u.empresas into v_mis from public.usuarios u where u.user_id = (select auth.uid());
  end if;
  if p_nueva then
    if v_clave !~ '^[a-z0-9_]{3,}$' then
      raise exception 'La clave va en minúsculas, números y guión bajo, mínimo 3 caracteres' using errcode = '22023';
    end if;
    if exists (select 1 from public.cuentas_bancarias where clave = v_clave) then
      raise exception 'Ya existe una cuenta con la clave «%»', v_clave using errcode = '23505';
    end if;
    if btrim(coalesce(p_datos->>'label', '')) = '' or btrim(coalesce(p_datos->>'titular', '')) = ''
       or btrim(coalesce(p_datos->>'cuenta', '')) = '' then
      raise exception 'Hacen falta la etiqueta, el titular y el número de cuenta' using errcode = '22023';
    end if;
    if v_rest then
      -- la empresa de una cuenta nueva la fija el servidor: la unica de quien tiene una, o una de las suyas si tiene varias
      v_emp := case when cardinality(v_mis) = 1 then v_mis[1] else nullif(btrim(coalesce(p_datos->>'empresa', '')), '') end;
      if v_emp is null or not (v_emp = any (v_mis)) then
        raise exception 'Elige la empresa de la cuenta (una de las tuyas)' using errcode = '42501';
      end if;
    end if;
    insert into public.cuentas_bancarias (clave, label, titular, banco, cuenta, codigo, direccion, extra,
                                          es_escrow, activa, orden, es_propia, empresa)
    values (v_clave, btrim(p_datos->>'label'), btrim(p_datos->>'titular'), btrim(coalesce(p_datos->>'banco', '')),
            btrim(p_datos->>'cuenta'), btrim(coalesce(p_datos->>'codigo', '')), btrim(coalesce(p_datos->>'direccion', '')),
            v_extra, coalesce((p_datos->>'es_escrow')::boolean, false), false,
            (select coalesce(max(orden), 0) + 10 from public.cuentas_bancarias), v_propia, v_emp);
  else
    if v_rest then
      select c.empresa, true into v_old_emp, v_hay from public.cuentas_bancarias c where c.clave = v_clave;
      if coalesce(v_hay, false) and (v_old_emp is null or not (v_old_emp = any (v_mis))) then
        raise exception 'Esa cuenta no es de tu empresa' using errcode = '42501';
      end if;
    end if;
    update public.cuentas_bancarias c set
      label     = case when p_datos ? 'label'     then btrim(coalesce(p_datos->>'label', ''))     else c.label end,
      titular   = case when p_datos ? 'titular'   then btrim(coalesce(p_datos->>'titular', ''))   else c.titular end,
      banco     = case when p_datos ? 'banco'     then btrim(coalesce(p_datos->>'banco', ''))     else c.banco end,
      cuenta    = case when p_datos ? 'cuenta'    then btrim(coalesce(p_datos->>'cuenta', ''))    else c.cuenta end,
      codigo    = case when p_datos ? 'codigo'    then btrim(coalesce(p_datos->>'codigo', ''))    else c.codigo end,
      direccion = case when p_datos ? 'direccion' then btrim(coalesce(p_datos->>'direccion', '')) else c.direccion end,
      extra     = case when p_datos ? 'extra'     then v_extra                                    else c.extra end,
      es_escrow = case when p_datos ? 'es_escrow' then coalesce((p_datos->>'es_escrow')::boolean, false) else c.es_escrow end,
      activa    = case when p_datos ? 'activa'    then coalesce((p_datos->>'activa')::boolean, false)    else c.activa end,
      es_propia = case when p_datos ? 'es_propia' then v_propia                                 else c.es_propia end
    where c.clave = v_clave;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Esa cuenta ya no existe' using errcode = 'P0002'; end if;
    if exists (select 1 from public.cuentas_bancarias where clave = v_clave and btrim(label) = '') then
      raise exception 'La etiqueta no puede quedar vacía: es lo que se lee en el desplegable del contrato' using errcode = '22023';
    end if;
  end if;
  if p_reparto is not null then
    if v_rest then perform public._reparto_valida_empresa(p_reparto, v_mis); end if;
    perform public._reparto_aplica(p_reparto);
  end if;
  return v_clave;
end $function$;

-- sociedad_guarda es larga y solo cambia su puerta (una linea): sustitucion exacta sobre la definicion viva.
do $m$
declare d text; viejo text; nuevo text; n int;
begin
  d := pg_get_functiondef('public.sociedad_guarda(text,jsonb,boolean)'::regprocedure);
  viejo := '  perform public._super_o_para();';
  nuevo := E'  perform public._super_o_empresa();\n'
        || E'  if not public.es_super_admin() then\n'
        || E'    -- super_admin_empresa: solo EDITA la sociedad ligada a su empresa; dar de alta una sociedad nueva es global (no tiene empresa a la que ligarse)\n'
        || E'    if p_nueva or public._empresa_sociedad(v_clave) is null or not public.es_super_admin_de(public._empresa_sociedad(v_clave)) then\n'
        || E'      raise exception ''Solo puedes editar la sociedad de tu empresa; las demas y las altas son del propietario o de un super admin global'' using errcode = ''42501'';\n'
        || E'    end if;\n'
        || E'  end if;';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'sociedad_guarda: se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, nuevo);
end $m$;

create or replace function public.cuentas_uso() returns table(clave text, contratos bigint, firmados bigint)
language sql security definer set search_path = '' as $$
  select c.clave,
         count(ct.id)                                as contratos,
         count(ct.id) filter (where ct.bloqueado)    as firmados
  from public.cuentas_bancarias c
  left join public.contratos ct
         on ct.datos->'fields'->>'cuenta_bancaria' = c.clave
  where public.es_super_admin_de(c.empresa)
  group by c.clave;
$$;

create or replace function public.sociedades_ajustes_datos() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  v jsonb; v_all boolean := public.es_admin();
begin
  if public.uid_sesion() is null then
    raise exception 'sociedades_ajustes_datos: sin sesión' using errcode = '42501';
  end if;
  if not (v_all or public._rol_empresa()) then
    raise exception 'Las sociedades emisoras son de administración.' using errcode = '42501';
  end if;
  with d as (
    select f.clave, jsonb_build_object('total', sum(f.total)::int, 'abiertos', sum(f.abiertos)::int,
             'detalle', jsonb_object_agg(f.tabla, jsonb_build_object('total', f.total, 'abiertos', f.abiertos))) as j
      from public._sociedad_docs_filas(null) f group by f.clave)
  select coalesce(jsonb_agg(to_jsonb(s)
           || jsonb_build_object('documentos', coalesce(d.j, jsonb_build_object('total', 0, 'abiertos', 0, 'detalle', '{}'::jsonb)))
           || case when v_all then '{}'::jsonb
                   else jsonb_build_object('puede_escribir_esta', public.es_super_admin_de(public._empresa_sociedad(s.clave))) end
           order by s.orden, s.clave), '[]'::jsonb)
    into v
    from public.sociedades s left join d on d.clave = s.clave
   where v_all or (public._empresa_sociedad(s.clave) is not null and public.es_admin_de(public._empresa_sociedad(s.clave)));
  return jsonb_build_object('puede_escribir', public.es_super_admin() or public._super_empresa_alguna(), 'sociedades', v);
end $function$;

alter policy "sociedades_log: leer solo super" on public.sociedades_log
  using (public.es_super_admin() or public.sociedad_super_de(clave));
