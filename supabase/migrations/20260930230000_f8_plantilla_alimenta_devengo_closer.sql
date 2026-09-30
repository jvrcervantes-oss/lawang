-- F8 (reducido) · la plantilla de reparto del Sales Manager ES lo que calcula el devengo de closer.
-- Modelo del owner (30-sep): en venta de equipo Lawang paga SOLO el 10 % al SM; el 2,5 % de los closers sale de ese 10 %.
-- Hoy el devengo 'closer' es informativo (nunca genera solicitud de pago: solo manager/estandar/propia la crean) y salia de una
-- condicion fija 2,5 %. Desde aqui: pct efectivo = plantilla.closer% x condicion manager del equipo (25 % x 10 % = 2,5 %).
-- Revision previa #176 (Datos + Administracion): sin plantilla_pct = «la plantilla no aplica en esa raiz»; el pct se congela en el
-- PRIMER devengo de closer de la venta (los tramos y las reposiciones lo releen de ahi, no de la plantilla viva); condicion por
-- closer_email (Gus/Victor al 0 % como closer propio) sigue mandando; cualquier duda (varias filas closer, base distinta a la del
-- manager, importe fijo) = comportamiento de hoy CON aviso. Los devengos ya creados no se tocan. Construido sobre la version VIVA
-- del motor (pg_get_functiondef 30-sep 22:50), no sobre el repo.

-- 1 · sembrar la plantilla en los equipos activos que no la tienen (25 + 75 = 100; el trigger diferido lo comprueba)
insert into public.plantilla_reparto (equipo_id, rol_tipo, rol_nombre, pct, creado_por)
select e.id, v.tipo, v.nombre, v.pct, 'f8_siembra'
  from public.equipos_venta e
 cross join (values ('closer', 'Closer', 25::numeric), ('otro', 'Sales Manager', 75::numeric)) as v(tipo, nombre, pct)
 where e.activo
   and not exists (select 1 from public.plantilla_reparto p where p.equipo_id = e.id);

-- 2 · equipos nuevos nacen con la misma plantilla
create or replace function public._trg_equipos_venta_plantilla_defecto()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  insert into public.plantilla_reparto (equipo_id, rol_tipo, rol_nombre, pct, creado_por)
  values (new.id, 'closer', 'Closer', 25, 'f8_defecto'), (new.id, 'otro', 'Sales Manager', 75, 'f8_defecto');
  return null;
end $function$;
revoke execute on function public._trg_equipos_venta_plantilla_defecto() from public, anon, authenticated;

create or replace trigger trg_equipos_venta_plantilla_defecto
  after insert on public.equipos_venta
  for each row execute function public._trg_equipos_venta_plantilla_defecto();

-- 3 · el motor
create or replace function public.comisiones_evaluar_contrato(p_contrato_id uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz_id              uuid;
  v_raiz_creada          date;
  v_fecha_equipo         date;
  v_moneda               text;
  v_proyecto_id          uuid;
  v_contrato_firmado     boolean := false;
  v_obra_firmada         boolean := false;
  v_precio_total         numeric := 0;
  v_precio_suelo         numeric := 0;
  v_precio_construccion  numeric := 0;
  v_cobrado_suelo        numeric := 0;
  v_cobrado_obra         numeric := 0;
  v_cobrado_total        numeric := 0;
  v_closer_email         text;
  v_fecha_venta          date;
  v_equipo_id            uuid;
  v_manager_email        text;
  v_propia               public.reclamaciones_venta_propia;
  v_niveles              text[];
  v_ultimo_recibi_id     uuid;
  v_ultimo_recibi_en     timestamptz;
  v_nivel                text;
  v_beneficiario         text;
  v_condicion            record;
  v_cond_fija            uuid;
  v_prev                 public.comisiones_devengadas;
  v_snap                 jsonb;
  v_tramo                record;
  v_base                 numeric;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_concepto             text;
  v_creados              integer := 0;
  v_eq_cong              uuid;
  v_man_cong             text;
  v_congelado            boolean := false;
  v_modo                 text;
  v_espera               timestamptz;
  v_propia_modo          boolean := false;
  v_pct_efectivo         numeric;
  v_plt_pct              numeric;
  v_plt_n                integer;
  v_prev_snap            jsonb;
  v_man_id               uuid;
  v_man_pct              numeric;
  v_man_base             text;
begin
  if p_contrato_id is null then
    return 0;
  end if;

  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0;
  end if;

  perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz_id::text));

  select c.moneda, c.proyecto_id, c.bloqueado, (c.created_at at time zone 'Asia/Makassar')::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  v_precio_total := public._comisiones_precio_total(v_raiz_id);

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado
  );

  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_interno(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  select k.closer_email, k.fecha_venta into v_closer_email, v_fecha_venta
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0;
  end if;

  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);
  v_fecha_equipo := v_raiz_creada;

  select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null), k.modo, k.modo_espera_hasta
    into v_eq_cong, v_man_cong, v_congelado, v_modo, v_espera
    from public.contrato_closer k where k.contrato_id = v_raiz_id;
  if coalesce(v_congelado, false) then
    v_equipo_id := v_eq_cong;
  else
  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.activo
     and em.desde <= v_fecha_equipo
     and (em.hasta is null or em.hasta >= v_fecha_equipo)
   order by em.created_at desc
   limit 1;
  end if;

  if v_proyecto_id is null or v_moneda is null then
    return 0;
  end if;

  if v_modo is null then
    select * into v_propia
      from public.reclamaciones_venta_propia r
     where r.contrato_raiz_id = v_raiz_id and r.estado = 'aprobada' and r.tipo = 'reclamacion';
  end if;

  if v_modo = 'propia' and v_equipo_id is not null then
    if (v_espera is not null and v_espera > now())
       or exists (select 1 from public.reclamaciones_venta_propia r
                   where r.contrato_raiz_id = v_raiz_id and r.tipo = 'objecion' and r.estado = 'pendiente') then
      return 0;
    end if;
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_propia_modo := true;
    v_niveles := array['propia'];
  elsif v_modo = 'propia' then
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  elsif v_propia.id is not null then
    if lower(v_propia.solicitante_email) <> lower(v_closer_email) then
      return 0;
    end if;
    v_equipo_id := v_propia.equipo_id;
    v_niveles := array['propia'];
  elsif v_equipo_id is not null then
    if coalesce(v_congelado, false) then
      v_manager_email := v_man_cong;
    else
      select ev.manager_email into v_manager_email from public.equipos_venta ev where ev.id = v_equipo_id;
    end if;
    v_niveles := array['manager', 'closer', 'setter', 'team_lead'];
  else
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  end if;

  select r.id, r.created_at
    into v_ultimo_recibi_id, v_ultimo_recibi_en
    from public.facturas r
   where r.tipo = 'recibi'
     and not coalesce(r.anulada, false)
     and (
       r.contrato_id = v_raiz_id
       or r.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id)
       or exists (
            select 1
              from public.recibi_aplicaciones ra
              join public.facturas f on f.id = ra.factura_id
             where ra.recibi_id = r.id
               and not coalesce(f.anulada, false)
               and (f.contrato_id = v_raiz_id
                    or f.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id))
          )
     )
   order by r.created_at desc
   limit 1;

  if v_ultimo_recibi_id is null then
    return 0;
  end if;

  foreach v_nivel in array v_niveles
  loop
    v_beneficiario := null;
    v_pct_efectivo := null;
    v_plt_pct := null;

    if v_nivel in ('closer', 'setter', 'team_lead') then
      if v_nivel = 'closer' then
        v_beneficiario := v_closer_email;
      else
        select re.email into v_beneficiario
          from public.contrato_roles_equipo re
         where re.contrato_raiz_id = v_raiz_id and re.rol = v_nivel and re.equipo_id = v_equipo_id;
      end if;
      if v_beneficiario is null then
        continue;
      end if;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and lower(c.closer_email) = lower(v_beneficiario)
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_raiz_creada
           and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;

    elsif v_nivel = 'estandar' or (v_nivel = 'propia' and v_propia_modo) then
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = lower(v_closer_email))
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

    else
      v_beneficiario := case when v_nivel = 'propia' then v_closer_email else v_manager_email end;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
    end if;

    v_cond_fija := null;
    if v_beneficiario is not null then
      select d.condicion_id into v_cond_fija
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and lower(d.beneficiario_email) = lower(v_beneficiario)
         and d.nivel = v_nivel
       order by d.created_at, d.id
       limit 1;
      if v_cond_fija is not null then
        select * into v_condicion from public.condiciones_comision c where c.id = v_cond_fija;
      end if;
    end if;

    if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;

    if v_condicion.base_calculo <> 'importe_fijo' and v_condicion.pct_comision = 0 then
      continue;
    end if;

    -- F8: el devengo del closer de equipo sale de la plantilla del SM (% del bote del manager), no de una cifra suelta.
    -- Solo la condicion generica del equipo (closer_email null): una por closer (p. ej. 0 % propio) sigue mandando.
    if v_nivel = 'closer' and v_equipo_id is not null and v_condicion.equipo_id = v_equipo_id
       and v_condicion.closer_email is null and v_condicion.base_calculo <> 'importe_fijo' then
      select d.disparado_por_snapshot into v_prev_snap
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.nivel = 'closer'
         and lower(d.beneficiario_email) = lower(v_beneficiario)
       order by d.created_at, d.id
       limit 1;
      if found then
        -- ya hay primer devengo: se relee SU congelado (sin plantilla_pct = la plantilla no aplica en esta raiz)
        v_plt_pct := nullif(v_prev_snap->>'plantilla_pct', '')::numeric;
      else
        select count(*), max(p.pct) into v_plt_n, v_plt_pct
          from public.plantilla_reparto p
         where p.equipo_id = v_equipo_id and p.rol_tipo = 'closer';
        if v_plt_n <> 1 then
          if v_plt_n > 1 then
            raise warning 'comisiones_evaluar_contrato: el equipo % tiene % filas closer en su plantilla; se usa la condicion de closer (raiz %)', v_equipo_id, v_plt_n, v_raiz_id;
          end if;
          v_plt_pct := null;
        end if;
      end if;

      if v_plt_pct is not null then
        -- la condicion manager con la que la venta devengo (fija) o, si aun no hay, la vigente
        select d.condicion_id into v_man_id
          from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id and d.nivel = 'manager'
         order by d.created_at, d.id
         limit 1;
        if v_man_id is null then
          select c.id into v_man_id
            from public.condiciones_comision c
           where c.equipo_id = v_equipo_id
             and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
             and c.nivel = 'manager'
             and (c.activo or c.vigente_hasta is not null)
             and c.vigente_desde <= v_raiz_creada
             and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
             and c.closer_email is null
           order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
           limit 1;
        end if;
        select c.pct_comision, c.base_calculo into v_man_pct, v_man_base
          from public.condiciones_comision c where c.id = v_man_id;
        if v_man_pct is null or v_man_base is distinct from v_condicion.base_calculo then
          raise warning 'comisiones_evaluar_contrato: la condicion manager del equipo % no casa con la de closer (base o falta); se usa la condicion de closer (raiz %)', v_equipo_id, v_raiz_id;
          v_plt_pct := null;
        else
          v_pct_efectivo := least(v_plt_pct, 100) / 100 * v_man_pct;
        end if;
      end if;
    end if;

    v_base := case v_condicion.base_calculo
      when 'precio_total'        then v_precio_total
      when 'precio_suelo'        then v_precio_suelo
      when 'precio_construccion' then v_precio_construccion
      else null
    end;

    for v_tramo in
      select * from public.condicion_tramos
       where condicion_id = v_condicion.id
       order by orden
    loop
      v_prev := null;
      select * into v_prev
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.tramo_id = v_tramo.id
         and d.beneficiario_email = v_beneficiario;
      if v_prev.id is not null and (v_prev.estado <> 'anulada' or not v_prev.anulado_por_modo) then
        continue;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') and exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.nivel in ('manager', 'estandar', 'propia')
           and d.estado <> 'anulada'
      ) then
        continue;
      end if;

      if not (case v_tramo.disparador_tipo
        when 'pct_cobrado_suelo' then
          v_precio_suelo > 0 and (v_cobrado_suelo / v_precio_suelo * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra' then
          v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral
        when 'pct_cobrado_total' then public._comisiones_precio_total_todos(v_raiz_id) > 0 and (v_cobrado_total / public._comisiones_precio_total_todos(v_raiz_id) * 100) >= v_tramo.umbral
        when 'obra_firmada' then v_obra_firmada
        when 'contrato_firmado' then v_contrato_firmado
        else false
      end) then
        continue;
      end if;

      if v_condicion.base_calculo = 'importe_fijo' then
        v_importe := round(v_condicion.importe_fijo * v_tramo.pct_tramo / 100, 2);
      else
        if v_base is null then
          continue;
        end if;
        v_importe := round((coalesce(v_pct_efectivo, v_condicion.pct_comision) / 100) * v_base * (v_tramo.pct_tramo / 100), 2);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue;
      end if;

      v_snap := jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'base_calculo', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', coalesce(v_pct_efectivo, v_condicion.pct_comision),
          'plantilla_pct', case when v_pct_efectivo is not null then v_plt_pct end,
          'vigente_desde', v_condicion.vigente_desde,
          'precio_total', v_precio_total,
          'precio_suelo', v_precio_suelo,
          'precio_construccion', v_precio_construccion,
          'cobrado_suelo', v_cobrado_suelo,
          'cobrado_obra', v_cobrado_obra,
          'cobrado_total', v_cobrado_total,
          'obra_firmada', v_obra_firmada,
          'contrato_firmado', v_contrato_firmado,
          'fecha_venta', v_fecha_venta,
          'equipo_id', case when v_propia_modo then null else v_equipo_id end,
          'reclamacion_id', v_propia.id,
          'modo', v_modo,
          'condicion_fijada', v_cond_fija is not null
        );

      v_devengo_id := null;

      if v_prev.id is not null then
        v_creados := v_creados + 1;
        if public._comision_devengo_reponer(v_prev.id, v_importe, v_snap,
                                            'La venta vuelve a «' || coalesce(v_modo, 'equipo') || '»')
           or v_nivel not in ('manager', 'estandar', 'propia') then
          continue;
        end if;
        v_devengo_id := v_prev.id;
      else
        insert into public.comisiones_devengadas (
          contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
          importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
        ) values (
          v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
          v_importe, v_moneda, null, v_snap
        )
        on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
        returning id into v_devengo_id;

        if v_devengo_id is null then
          continue;
        end if;

        v_creados := v_creados + 1;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) and u.activo limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) and u.activo limit 1),
          (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1)
        );

        v_concepto := 'Comisión ' || case v_nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end
          || ' — tramo ' || v_tramo.orden || ' (' || v_tramo.disparador_tipo
          || case when v_tramo.umbral is not null then ' ' || v_tramo.umbral || '%' else '' end || ')'
          || case when v_condicion.base_calculo = 'importe_fijo'
               then ' — importe fijo ' || v_condicion.importe_fijo
               else ' — ' || v_condicion.pct_comision || '% s/ ' || replace(v_condicion.base_calculo, '_', ' ')
                    || ' a fecha de disparo: ' || round(v_base, 2) || ' ' || v_moneda
             end
          || ' × ' || v_tramo.pct_tramo || '% del tramo — importe BRUTO (retención al pagar)';

        if v_creado_por is null then
          raise warning 'comisiones_evaluar_contrato: sin creado_por resoluble para la solicitud de % (raiz %) -- devengo % sin solicitud',
            v_beneficiario, v_raiz_id, v_devengo_id;
        else
          v_sp_id := null;
          begin
            insert into public.solicitudes_pago (
              contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por
            ) values (
              v_raiz_id, v_concepto, v_importe, v_moneda, 'comision_automatica', v_beneficiario, v_creado_por
            )
            returning id into v_sp_id;

            update public.comisiones_devengadas
               set solicitud_id = v_sp_id
             where id = v_devengo_id;
          exception when others then
            raise warning 'comisiones_evaluar_contrato: fallo creando la solicitud de pago de % (raiz %, tramo %): % -- devengo % sin solicitud',
              v_beneficiario, v_raiz_id, v_tramo.id, sqlerrm, v_devengo_id;
          end;
        end if;
      end if;
    end loop;
  end loop;

  return v_creados;
end;
$function$;
