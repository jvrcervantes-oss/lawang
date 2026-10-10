-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (version y nombre exactos; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260926234500_frontera_comisiones_rpc.sql
-- destructivo-ok: reemplaza dos funciones (mismas firmas); los DELETE van dentro de funciones, no se borra ninguna fila al aplicarse.
create or replace function public.condicion_comision_guarda(p_id uuid, p_cond jsonb, p_tramos jsonb,
                                                            p_motivo text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_old    public.condiciones_comision%rowtype;
  v_id     uuid;
  v_nivel  text;
  v_equipo uuid;
  v_proy   uuid;
  v_closer text := nullif(lower(btrim(coalesce(p_cond->>'closer_email', ''))), '');
  v_pct    numeric;
  v_base   text := p_cond->>'base_calculo';
  v_fijo   numeric;
  v_desde  date;
  v_admin  boolean := public.es_admin();
  v_n      int := 0;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  begin
    v_pct   := (p_cond->>'pct_comision')::numeric;
    v_fijo  := case when v_base = 'importe_fijo' then (p_cond->>'importe_fijo')::numeric end;
    v_desde := coalesce(nullif(p_cond->>'vigente_desde', '')::date, current_date);
  exception when others then
    raise exception 'Revisa las cifras: el %%, el importe fijo o la fecha no son válidos' using errcode = '22023';
  end;
  if v_pct is null or v_pct < 0 or v_pct > 100 then raise exception 'El %% de comisión va entre 0 y 100' using errcode = '22023'; end if;

  if p_id is null then
    v_equipo := nullif(p_cond->>'equipo_id', '')::uuid;
    v_proy   := nullif(p_cond->>'proyecto_id', '')::uuid;
    v_nivel  := case when v_equipo is null then 'closer' else coalesce(p_cond->>'nivel', 'closer') end;
    if not public._condicion_es_mia(v_nivel, v_equipo) then
      raise exception 'Solo puedes crear condiciones para los closers, setters o team leads de tu equipo' using errcode = '42501';
    end if;
    if not v_admin then
      if v_desde < current_date then raise exception 'La fecha no puede ser anterior a hoy.' using errcode = '22023'; end if;
      if v_closer is not null and not public._closer_del_equipo(v_equipo, v_closer) then
        raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
      end if;
    end if;
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo,
                                             importe_fijo, vigente_desde, created_by)
    values (v_equipo, v_proy, v_nivel,
            case when v_nivel in ('closer', 'setter', 'team_lead') then v_closer end,
            v_pct, v_base, v_fijo, v_desde, (select auth.email()))
    returning id into v_id;
    perform public._condicion_tramos_pone(v_id, p_tramos);
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    select v_id, null, to_jsonb(c), v_motivo from public.condiciones_comision c where c.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  select count(*) into v_n from public.comisiones_devengadas d where d.condicion_id = p_id;
  if v_n > 0 then
    if not v_admin then
      raise exception 'Esta condición ya ha generado comisiones: no se cambian sus cifras. Desactívala y crea una nueva.' using errcode = '22023';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Esta condición ya ha generado comisiones: escribe por qué cambias sus cifras (queda registrado)' using errcode = '22023';
    end if;
    if v_desde > v_old.vigente_desde then
      raise exception 'Esta condición ya ha generado comisiones: su fecha de vigencia no se puede adelantar (dejaría sin cobrar los tramos pendientes de ventas ya empezadas)' using errcode = '22023';
    end if;
    if v_base is distinct from v_old.base_calculo then
      raise exception 'Esta condición ya ha generado comisiones: su base de cálculo no se cambia. Desactívala y crea una nueva.' using errcode = '22023';
    end if;
  end if;
  if not v_admin then
    if v_desde is distinct from v_old.vigente_desde and v_desde < current_date then
      raise exception 'la fecha de vigencia no puede quedar en el pasado' using errcode = '22023';
    end if;
    if v_closer is not null and not public._closer_del_equipo(v_old.equipo_id, v_closer) then
      raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
    end if;
  end if;

  update public.condiciones_comision c
     set pct_comision = v_pct, base_calculo = v_base, importe_fijo = v_fijo, vigente_desde = v_desde,
         closer_email = case when c.nivel in ('closer', 'setter', 'team_lead') then v_closer else c.closer_email end
   where c.id = p_id;
  if v_n = 0 then
    perform public._condicion_tramos_pone(p_id, p_tramos);
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo)
  select p_id, to_jsonb(v_old),
         to_jsonb(c) || jsonb_build_object('ventas_con_devengos',
           (select count(distinct d.contrato_raiz_id) from public.comisiones_devengadas d where d.condicion_id = p_id)),
         v_n > 0, v_motivo
    from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $$;

create or replace function public.comision_admin_linea_estado(p_id uuid, p_estado text, p_nota text,
                                                              p_toca_nota boolean, p_quitar_revisar boolean,
                                                              p_motivo text default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v public.comision_admin_lineas%rowtype;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_avanza boolean;
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  select * into v from public.comision_admin_lineas l where l.id = p_id for update;
  if not found then raise exception 'Esa comisión no existe' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'Esa comisión está anulada: su estado no se cambia' using errcode = '22023'; end if;
  if p_estado not in ('pendiente', 'facturada', 'cobrada', 'exenta') then
    raise exception 'Estado no válido' using errcode = '22023';
  end if;
  if p_estado is distinct from v.estado then
    v_avanza := (v.estado = 'pendiente' and p_estado in ('facturada', 'cobrada'))
             or (v.estado = 'facturada' and p_estado = 'cobrada');
    if not v_avanza and (v_motivo is null or length(v_motivo) < 5) then
      raise exception 'Pasar de «%» a «%» necesita un motivo (queda registrado)', v.estado, p_estado using errcode = '22023';
    end if;
    insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
    values (p_id, v.estado, p_estado, v_motivo);
  end if;
  update public.comision_admin_lineas l
     set estado = p_estado,
         nota = case when coalesce(p_toca_nota, false) then nullif(btrim(coalesce(p_nota, '')), '') else l.nota end,
         revisar = case when coalesce(p_quitar_revisar, false) then false else l.revisar end,
         actualizado_en = now()
   where l.id = p_id;
  return p_estado;
end $$;;
