-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (version y nombre exactos; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260926230000_contrato_guarda_por_servidor.sql
create or replace function public.contrato_guarda(p_id uuid, p_contrato jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_datos  jsonb := p_contrato->'datos';
  v_f      jsonb;
  v_tipo   text  := nullif(btrim(coalesce(p_contrato->>'tipo', '')), '');
  v_nrv    text;
  v_poa    text;
  v_padre  uuid;
  v_proy   text;
  v_comp   text;
  v_fecha  date;
  v_precio numeric;
  v_old    public.contratos%rowtype;
  v_row    public.contratos%rowtype;
  v_firmado boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public.puede('contratos')) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  if v_datos is null or jsonb_typeof(v_datos) <> 'object' or jsonb_typeof(v_datos->'fields') <> 'object' then
    raise exception 'Contrato sin datos' using errcode = '22023';
  end if;
  if v_tipo is null then raise exception 'Contrato sin tipo' using errcode = '22023'; end if;
  v_f := v_datos->'fields';

  v_nrv := nullif(btrim(v_f->>'num_reserva_vinculada'), '');
  v_poa := nullif(btrim(v_f->>'poa_hs_vinculado'), '');
  if v_nrv is not null then
    select c.id into v_padre from public.contratos c
     where c.numero = v_nrv and c.tipo = 'reserva_parcela' and public.contrato_visible(c.creado_por, c.proyecto_id) limit 1;
  end if;
  if v_padre is null and v_poa is not null then
    select c.id into v_padre from public.contratos c
     where c.numero = v_poa and c.tipo <> 'poa' and public.contrato_visible(c.creado_por, c.proyecto_id) limit 1;
  end if;
  v_proy := nullif(btrim(v_f->>'proyecto_nombre'), '');
  if v_proy is null and v_poa is not null then
    select c.proyecto_nombre into v_proy from public.contratos c
     where c.numero = v_poa and c.tipo <> 'poa' and public.contrato_visible(c.creado_por, c.proyecto_id) limit 1;
  end if;
  v_comp := coalesce(public.contrato_nombres_compradores(v_datos),
                     nullif(btrim(v_f->>'adq1_nombre'), ''), nullif(btrim(v_f->>'partner_nombre'), ''),
                     nullif(btrim(v_f->>'colaborador_nombre'), ''));
  begin
    v_fecha := nullif(btrim(coalesce(v_f->>'fecha_firma', '')), '')::date;
  exception when others then
    raise exception 'Rellena: la fecha de firma no es una fecha válida' using errcode = '22007';
  end;
  v_precio := public.lw_parse_importe(v_f->>'precio_total');

  if p_id is null then
    insert into public.contratos (tipo, comprador_nombre, proyecto_nombre, precio_total, moneda, fecha_firma,
                                  contrato_padre_id, unidad_id, datos)
    values (v_tipo, v_comp, v_proy, v_precio, nullif(btrim(v_f->>'moneda'), ''), v_fecha, v_padre,
            case when p_contrato ? 'unidad_id' then nullif(p_contrato->>'unidad_id', '')::uuid end, v_datos)
    returning * into v_row;
    if not (public.puede_proyecto_de(v_row.datos, v_row.proyecto_nombre, v_row.proyecto_id)
            or public.es_manager_de(v_row.proyecto_id)) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
  else
    select * into v_old from public.contratos c where c.id = p_id for update;
    if not found then raise exception 'Ese contrato ya no existe' using errcode = 'P0002'; end if;
    if not (public.es_super_admin()
            or (coalesce(v_old.bloqueado, false) = false and not public.contrato_firma_viva(v_old.id)
                and (public.es_suyo(v_old.creado_por) or public.es_manager_de(v_old.proyecto_id))
                and public.puede_proyecto_de(jsonb_build_object('fields', v_old.datos_fields),
                                             v_old.proyecto_nombre, v_old.proyecto_id))) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
    if coalesce(v_nrv, '') || '|' || coalesce(v_poa, '')
       = coalesce(nullif(btrim(v_old.datos_fields->>'num_reserva_vinculada'), ''), '') || '|'
         || coalesce(nullif(btrim(v_old.datos_fields->>'poa_hs_vinculado'), ''), '') then
      v_padre := v_old.contrato_padre_id;
    end if;
    v_firmado := coalesce(v_old.bloqueado, false)
              or exists (select 1 from public.contrato_firmas f where f.contrato_id = p_id and f.estado = 'firmado');
    update public.contratos c
       set tipo = v_tipo, comprador_nombre = v_comp, proyecto_nombre = v_proy,
           precio_total = case when v_firmado then c.precio_total else v_precio end,
           moneda = nullif(btrim(v_f->>'moneda'), ''), fecha_firma = v_fecha,
           contrato_padre_id = v_padre,
           unidad_id = case when p_contrato ? 'unidad_id' then nullif(p_contrato->>'unidad_id', '')::uuid else c.unidad_id end,
           datos = v_datos
     where c.id = p_id
    returning * into v_row;
    if not (public.es_super_admin()
            or ((public.es_suyo(v_row.creado_por) or public.es_manager_de(v_row.proyecto_id))
                and public.puede_proyecto_de(v_row.datos, v_row.proyecto_nombre, v_row.proyecto_id))) then
      raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
    end if;
  end if;

  return jsonb_build_object('id', v_row.id, 'numero', v_row.numero, 'precio_total', v_row.precio_total,
                            'fields', v_row.datos->'fields', 'hitos', v_row.datos->'hitos');
end $$;;
