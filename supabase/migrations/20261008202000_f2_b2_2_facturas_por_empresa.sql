-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 2 (8-oct-2026): FACTURAS, RECIBIS Y PROFORMAS POR EMPRESA.
--   Un admin_empresa edita/anula/borra proformas/marca como enviado lo que un admin global, y un super_admin_empresa reactiva y salta el tope de cadena como un super global,
--   SOLO en documentos de su empresa. La empresa del documento sale de su proyecto (o del proyecto de su contrato): nunca de lo que mande la pantalla. Sin proyecto = sin empresa = solo global (LAW-E1).
--   Quien tiene alcance restringido (rol de empresa, o agente/PM con empresas marcadas) solo emite con la sociedad de la empresa del proyecto y sobre un proyecto de sus empresas:
--   el proyecto lo fija el servidor desde el contrato (el nombre que manda la pantalla se ignora), y la sociedad se exige al crear o cuando cambia (los documentos historicos de excepcion
--   —18 de Tepi en Sumba Hills, etc.— siguen editables sin tocar su sociedad).
--   Funciones: _factura_puede_editar, factura_borra, factura_reactiva, factura_anulada_solo_cambia_autor (trigger), _factura_tope_cadena, factura_guarda, guardar_recibi,
--   y la policy de recibi_aplicaciones (gana la via del admin de empresa por proyecto y la clausula de alcance que ya tiene facturas).
--   Los 34 usuarios de hoy (empresas vacias, ninguno con rol de empresa): comportamiento identico; lo prueba f2_foto_b2.sql antes y despues.
-- destructivo-ok: create or replace de funciones y alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql

create or replace function public._factura_puede_editar(f public.facturas) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_super_admin_de(public._empresa_doc(f.proyecto_id, f.contrato_id))
      or (not f.anulada and public.es_agente() and public.puede('facturas')
          and (public.es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id) or public._sm_ve_venta(f.contrato_id)
               or public.es_admin_de(public._empresa_doc(f.proyecto_id, f.contrato_id))))
$$;

create or replace function public.factura_borra(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $function$
declare v_old public.facturas%rowtype; v_emp text;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  -- LAW-341: una factura o un recibí numerados no se borran nunca; se anulan.
  if v_old.tipo <> 'proforma' then
    raise exception '% no se puede borrar: una factura o un recibí numerados se ANULAN (borrarlos deja un hueco en la numeración)', v_old.numero
      using errcode = '42501';
  end if;
  v_emp := public._empresa_doc(v_old.proyecto_id, v_old.contrato_id);
  if not (not coalesce(v_old.enviada, false)
          and (public.es_super_admin_de(v_emp)
               or (public.es_admin_de(v_emp) and not coalesce(v_old.anulada, false)
                   and not exists (select 1 from public.recibi_aplicaciones ra
                                    where ra.factura_id = v_old.id or ra.recibi_id = v_old.id)))) then
    raise exception 'No puedes borrar esta proforma (enviada, con cobros aplicados, o sin permiso). Anúlala.'
      using errcode = '42501';
  end if;
  delete from public.facturas f where f.id = p_id;
end $function$;

create or replace function public.factura_reactiva(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $function$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not public.es_super_admin_de(public._empresa_doc(v_old.proyecto_id, v_old.contrato_id)) then
    raise exception 'Solo un super admin puede reactivar un documento anulado' using errcode = '42501';
  end if;
  if not v_old.anulada then raise exception 'El documento % no está anulado', v_old.numero using errcode = '22023'; end if;
  update public.facturas f set anulada = false where f.id = p_id;
end $function$;

-- Dos funciones largas cambian en UNA sola linea cada una: se reescriben desde su definicion viva con una sustitucion exacta
-- (si el texto vivo no trae esa linea exactamente una vez, la migracion se para y no toca nada).
do $m$
declare d text; viejo text; nuevo text; n int;
begin
  d := pg_get_functiondef('public.factura_anulada_solo_cambia_autor()'::regprocedure);
  viejo := 'if not public.es_super_admin() then';
  nuevo := 'if not public.es_super_admin_de(public._empresa_doc(old.proyecto_id, old.contrato_id)) then';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'factura_anulada_solo_cambia_autor: se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, nuevo);

  d := pg_get_functiondef('public._factura_tope_cadena(uuid,uuid,text,numeric,text)'::regprocedure);
  viejo := 'if public.es_super_admin() then';
  nuevo := 'if public.es_super_admin_de(public._empresa_doc(null::uuid, p_contrato)) then';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception '_factura_tope_cadena: se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, nuevo);
end $m$;

create or replace function public.factura_guarda(p_id uuid, p_factura jsonb)
 returns table(id uuid, numero text, total numeric)
 language plpgsql security definer set search_path = '' as $function$
declare
  v_old public.facturas%rowtype;
  v_tipo text := coalesce(nullif(p_factura->>'tipo', ''), 'factura');
  v_contrato uuid := nullif(p_factura->>'contrato_id', '')::uuid;
  v_client uuid := nullif(p_factura->>'client_id', '')::uuid;
  v_moneda text := nullif(p_factura->>'moneda', '');
  v_datos jsonb := coalesce(p_factura->'datos', '{}'::jsonb);
  v_pantalla numeric := public.lw_parse_importe(p_factura->>'total');
  v_tot jsonb; v_total numeric; v_id uuid; v_num text; v_proy uuid; v_autor text; n int;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_pnombre text := nullif(p_factura->>'proyecto_nombre', '');
  v_pid uuid; v_emp text;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  if v_tipo = 'recibi' then
    raise exception 'Un recibí se guarda con guardar_recibi, no aquí' using errcode = '22023';
  end if;
  if v_tipo not in ('factura', 'proforma') then
    raise exception 'Tipo de documento desconocido: %', v_tipo using errcode = '22023';
  end if;
  if not public._puede_herr('facturas') then
    raise exception 'Emitir o editar facturas exige la herramienta «Facturas»' using errcode = '42501';
  end if;
  if v_contrato is not null then
    if not exists (select 1 from public.contratos c
                    where c.id = v_contrato and public.puede_ver_contrato(c.id)) then
      raise exception 'No puedes emitir un documento sobre un contrato que no ves' using errcode = '42501';
    end if;
  end if;
  if v_client is not null then
    if not (
         (v_contrato is not null and exists (select 1 from public.contrato_compradores cc
                                              where cc.contrato_id = v_contrato and cc.client_id = v_client))
      or exists (select 1 from public.clients k
                  where k.id = v_client and public.cliente_visible(k.propietario, k.id))) then
      raise exception 'Ese cliente no es comprador de este contrato ni un cliente que veas' using errcode = '42501';
    end if;
  end if;

  -- Alcance por empresa (solo quien lo tiene restringido): el proyecto lo manda el contrato, la sociedad es la de la empresa del proyecto.
  if v_rest then
    if v_contrato is not null then
      select c.proyecto_id into v_pid from public.contratos c where c.id = v_contrato;
      select pr.nombre into v_pnombre from public.proyectos pr where pr.id = v_pid;
    else
      select pr.id into v_pid from public.proyectos pr where pr.nombre = v_pnombre;
    end if;
    v_emp := public._empresa_doc(v_pid, v_contrato);
    if v_emp is null or not public.puede_empresa(v_emp) then
      raise exception 'Ese documento no es de ninguna de tus empresas: elige un contrato o un proyecto de las tuyas' using errcode = '42501';
    end if;
    if (p_id is null or (p_factura->>'sociedad') is distinct from (select f.sociedad from public.facturas f where f.id = p_id))
       and not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = p_factura->>'sociedad') then
      raise exception 'Ese documento tiene que salir por la sociedad de la empresa del proyecto' using errcode = '42501';
    end if;
  end if;

  -- AXW-45: la marca de «cuenta resuelta por el servidor» no viene nunca del navegador.
  if jsonb_typeof(v_datos->'fields') = 'object' then
    v_datos := jsonb_set(v_datos, '{fields}', (v_datos->'fields') - 'banco_de_servidor');
  end if;

  v_tot := public.factura_totales(v_datos->'lineas', v_moneda, v_datos->'fields'->>'imp_pct');
  v_total := (v_tot->>'total')::numeric;
  if (v_tot->>'pct')::numeric not between 0 and 100 then
    raise exception 'El impuesto tiene que estar entre 0 y 100 %%' using errcode = '22023';
  end if;
  if (v_tot->>'subtotal')::numeric <= 0 then
    raise exception 'El documento no tiene importe (un total negativo es una rectificativa, no una factura)'
      using errcode = '22023';
  end if;
  if v_pantalla is null then
    raise exception 'Falta el total que se ve en pantalla: recarga la página y vuelve a guardar' using errcode = '22023';
  end if;
  if abs(v_pantalla - v_total) > power(10::numeric, -public.lw_decimales(v_moneda)) then
    raise exception 'El total no cuadra: la pantalla dice % y las líneas suman %. Recarga la página y vuelve a guardar.',
      v_pantalla, v_total using errcode = '22023';
  end if;
  v_datos := jsonb_set(v_datos, '{totales}', v_tot, true);
  perform public._factura_tope_cadena(p_id, v_contrato, v_moneda, (v_tot->>'subtotal')::numeric, v_tipo);

  if p_id is null then
    insert into public.facturas as f
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id, client_id,
       total, moneda, fecha_emision, datos, justificantes)
    values
      (v_tipo, p_factura->>'sociedad', nullif(p_factura->>'cliente_nombre', ''),
       v_pnombre, nullif(p_factura->>'contrato_numero', ''),
       v_contrato, v_client, v_total, v_moneda, nullif(p_factura->>'fecha_emision', '')::date,
       v_datos, '[]'::jsonb)
    returning f.id, f.numero into v_id, v_num;
  else
    select * into v_old from public.facturas f where f.id = p_id for update;
    if not found then
      raise exception 'Ese documento ya no existe' using errcode = 'P0002';
    end if;
    if v_old.tipo = 'recibi' then
      raise exception 'Un recibí se edita con guardar_recibi, no aquí' using errcode = '22023';
    end if;
    if not public._factura_puede_editar(v_old) then
      raise exception 'No puedes editar este documento (anulado, o no es tuyo ni de tu proyecto)' using errcode = '42501';
    end if;
    if v_old.enviada and v_old.tipo = 'factura' then
      raise exception 'La factura % ya se envió: no se edita (ni cliente, ni empresa, ni fecha, ni importes). Se corrige con una rectificativa.', v_old.numero
        using errcode = '42501';
    end if;
    if v_old.enviada and (v_total is distinct from v_old.total
                          or v_moneda is distinct from v_old.moneda
                          or (v_datos->'lineas') is distinct from (v_old.datos->'lineas')) then
      raise exception 'El documento % ya se envió: sus importes no se cambian, se emite una rectificativa', v_old.numero
        using errcode = '42501';
    end if;
    update public.facturas f set
      tipo = v_tipo, sociedad = p_factura->>'sociedad',
      cliente_nombre = nullif(p_factura->>'cliente_nombre', ''),
      proyecto_nombre = v_pnombre,
      contrato_numero = nullif(p_factura->>'contrato_numero', ''),
      contrato_id = v_contrato, client_id = v_client, total = v_total, moneda = v_moneda,
      fecha_emision = nullif(p_factura->>'fecha_emision', '')::date, datos = v_datos
    where f.id = p_id
    returning f.id, f.numero, f.proyecto_id, f.creado_por into v_id, v_num, v_proy, v_autor;
    get diagnostics n = row_count;
    if n <> 1 then
      raise exception 'No se ha guardado (0 filas)' using errcode = 'P0002';
    end if;
    if not (public.es_super_admin_de(public._empresa_doc(v_proy, v_contrato))
            or (public._puede_herr('facturas')
                and (public.es_suyo(v_autor) or public.es_manager_de(v_proy) or public._sm_ve_venta(v_contrato)
                     or public.es_admin_de(public._empresa_doc(v_proy, v_contrato))))) then
      raise exception 'Con ese contrato el documento dejaría de ser tuyo o de tu proyecto' using errcode = '42501';
    end if;
  end if;
  return query select v_id, v_num, v_total;
end $function$;

create or replace function public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificantes jsonb;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
  v_factura_autor text;
  v_factura_proyecto uuid;
  v_importe_aplic numeric;
  v_pend_factura numeric;
  v_moneda_factura text;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_pnombre text := p_factura->>'proyecto_nombre';
  v_pid uuid; v_emp text; v_emp_fac text;
begin
  if not public._puede_herr('facturas') then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;

  -- Barrera (27-sep): el contrato del recibí tiene que ser uno que quien lo emite ve.
  if not public.es_super_admin_de(public._empresa_doc(null::uuid, v_contrato_id))
     and not exists (select 1 from public.contratos c
                      where c.id = v_contrato_id and public.puede_ver_contrato(c.id)) then
    raise exception 'No puedes emitir un recibí sobre un contrato que no ves' using errcode = '42501';
  end if;

  -- Alcance por empresa (solo restringido): el proyecto lo manda el contrato; la sociedad, la de la empresa del proyecto.
  v_emp := public._empresa_doc(null::uuid, v_contrato_id);
  if v_rest then
    select c.proyecto_id into v_pid from public.contratos c where c.id = v_contrato_id;
    select pr.nombre into v_pnombre from public.proyectos pr where pr.id = v_pid;
    if v_emp is null or not public.puede_empresa(v_emp) then
      raise exception 'Ese recibí no es de ninguna de tus empresas' using errcode = '42501';
    end if;
    if (p_id is null or (p_factura->>'sociedad') is distinct from (select f.sociedad from public.facturas f where f.id = p_id))
       and not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = p_factura->>'sociedad') then
      raise exception 'Ese recibí tiene que salir por la sociedad de la empresa del proyecto' using errcode = '42501';
    end if;
  end if;

  v_justificantes := case when jsonb_typeof(p_factura->'justificantes') = 'array'
                          then p_factura->'justificantes' else '[]'::jsonb end;
  if jsonb_array_length(v_justificantes) = 0
     and nullif(p_factura->>'justificante_path', '') is not null then
    v_justificantes := jsonb_build_array(jsonb_build_object('path', p_factura->>'justificante_path'));
  end if;

  if jsonb_array_length(v_justificantes) = 0 then
    raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
  end if;
  if jsonb_array_length(v_justificantes) > 8 then
    raise exception 'demasiados justificantes en un recibi (maximo 8)' using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_justificantes) j
     where nullif(j->>'path', '') is null
        or not exists (select 1 from storage.objects o
                        where o.bucket_id = 'justificantes' and o.name = j->>'path')
  ) then
    raise exception 'algun justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;

  if jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificantes, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', v_pnombre,
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificantes, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = v_pnombre, contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificantes = v_justificantes,
      datos = p_factura->'datos'
    where id = p_id and tipo = 'recibi' and anulada = false
      and (public.es_suyo(creado_por) or public.es_admin_de(public._empresa_doc(proyecto_id, contrato_id)))
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  perform 1 from public.facturas fl
   where fl.id in (select (a->>'factura_id')::uuid from jsonb_array_elements(p_aplicaciones) a)
   order by fl.id for update;
  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    v_factura_id := (v_aplicacion->>'factura_id')::uuid;

    select f.numero, f.contrato_id, f.creado_por, f.proyecto_id
      into v_factura_numero, v_factura_contrato, v_factura_autor, v_factura_proyecto
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;
    v_emp_fac := public._empresa_doc(v_factura_proyecto, v_factura_contrato);

    -- Barrera (27-sep): solo se cobra contra facturas que quien emite ve (mismo predicado que su lectura).
    if not public.es_super_admin_de(v_emp_fac)
       and not public.documento_visible(v_factura_autor, v_factura_proyecto, v_factura_contrato) then
      raise exception 'la factura % no es un documento que veas: no le puedes aplicar un cobro',
        coalesce(v_factura_numero, '?') using errcode = '42501';
    end if;

    if v_factura_contrato is null then
      if public.es_super_admin_de(v_emp_fac) then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_factura_huerfana',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin_de(v_emp) and public.es_super_admin_de(v_emp_fac) then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_otro_comprador',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero,
                             'importe', v_aplicacion->>'importe'));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;

    v_importe_aplic := (v_aplicacion->>'importe')::numeric;
    if v_importe_aplic is null or v_importe_aplic <= 0 then
      raise exception 'el importe que se aplica a la factura % tiene que ser mayor que cero', coalesce(v_factura_numero, '?') using errcode = '23514';
    end if;
    select f.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                 join public.facturas rc on rc.id = ra.recibi_id
                                where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0), f.moneda
      into v_pend_factura, v_moneda_factura from public.facturas f where f.id = v_factura_id;
    if v_importe_aplic > v_pend_factura + power(10::numeric, -public.lw_decimales(v_moneda_factura)) then
      raise exception 'la factura % solo tiene % pendiente de cobro y este recibí le aplica %', coalesce(v_factura_numero, '?'), v_pend_factura, v_importe_aplic using errcode = '23514';
    end if;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, v_factura_id, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$function$;

-- recibi_aplicaciones: el admin de empresa ve las de los documentos de su empresa (por proyecto, como facturas) y el alcance restringido se aplica tambien al resto de vias.
alter policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones
  using (
    (select public.es_agente()) and exists (
      select 1 from public.facturas d
       where d.id = any (array[recibi_aplicaciones.recibi_id, recibi_aplicaciones.factura_id])
         and ((select public.es_admin())
              or d.proyecto_id = any ((select public.mis_proyectos_admin_empresa())::uuid[])
              or ((coalesce(d.creado_por = (select auth.email()), false)
                   or d.proyecto_id = any ((select public.mis_proyectos_supervisados())::uuid[])
                   or d.contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))
                  and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(d.proyecto_id))))));
