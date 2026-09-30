-- F2 · arreglos del revisor y de Datos/Administracion + estandar 10 % (30-sep-2026) · encargo 20260930_lawang_equipos_venta_asistente.
-- Una transaccion. Construido sobre el cuerpo VIVO de las cuatro funciones (md5 comprobado abajo). El recalculo automatico
-- de comisiones esta ENCENDIDO: por eso la migracion comprueba dentro que no crea devengos ni solicitudes.
--
-- 1. Owner 30-sep, sobre las 39 ventas de Carmen (sales@, 23-jul..22-sep; su equipo existe desde el 24-sep y no tiene
--    condiciones): «Se quedan como hoy». Hoy el motor las trata como del equipo «Carmen» (equipo de hoy) y no generan
--    comision. Se CONGELAN en ese equipo antes de cambiar el ancla, para que el paso 2 no las mueva. La SP-47 no se toca.
-- 2. Una sola fecha de la venta: el motor buscaba el equipo de una venta no congelada a HOY y el congelado a la creacion
--    de la raiz; ahora los dos (y la condicion) a coalesce(fecha_venta, creacion de la raiz en hora de Bali).
-- 3. equipo_miembro_guarda: el solape miraba solo OTROS equipos (una persona podia quedar dos veces en el mismo equipo
--    con rangos solapados); ahora mira cualquier fila de la persona salvo la propia. Mensaje distinto, mismo 23P01.
--    Sin exclusion por rango: btree_gist no esta instalado.
-- 4. Owner 30-sep: «A partir de hoy, si un closer vende sin equipo es 10 %, si vende en equipo lo que tenga asignado.»
--    La estandar 2,5 % se CIERRA con vigente_hasta = 29-sep (no se desactiva ni se edita otra cosa: sus devengos siguen
--    colgando de ella) y nace una estandar 10 % desde el 30-sep con los mismos tramos. Los overrides individuales
--    (p. ej. 0 % de hello@) siguen mandando: el motor ordena primero las condiciones con closer_email.
-- Verificacion antes/despues (reconciliacion, simulacion de las 134 no congeladas, huellas): informe de F2.
-- Prueba: contracts/sql/prueba_f2_equipos.sql. Inversa: re-aplicar los cuerpos de 20260930030300/030450 y del volcado
-- de equipo_miembro_guarda; vigente_hasta = null en la 2,5 % y borrar la 10 % (solo si no tiene devengos).

do $g$
begin
  if md5(replace(pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure), E'\r', '')) <> '1a95de75912d6634bb99c9e89b296058'
     or md5(replace(pg_get_functiondef('public._venta_congela_equipo(uuid)'::regprocedure), E'\r', '')) <> '1492df5e4702362b1bbd4ce1b93755cb'
     or md5(replace(pg_get_functiondef('public._equipo_recongela_sin_equipo(text,date,date)'::regprocedure), E'\r', '')) <> 'b3520c3bb2806c25d8568c8d2505aa56'
     or md5(replace(pg_get_functiondef('public.equipo_miembro_guarda(uuid,uuid,text,date,date)'::regprocedure), E'\r', '')) <> 'c1b913c2783fda79b36048d8a71af21c' then
    raise exception 'F2 arreglos: una funcion viva ya no es la del volcado del 30-sep: rehacer sobre la nueva';
  end if;
end $g$;

create temporary table _f2_cuenta on commit drop as
  select (select count(*) from public.comisiones_devengadas) nd, (select count(*) from public.solicitudes_pago) ns;

-- 1 · las 39 ventas de Carmen se quedan en su equipo de hoy
-- destructivo-ok: owner 30-sep «Se quedan como hoy», fija 39 ventas de Carmen a su equipo actual para que el cambio de ancla no las mueva
do $p1$
declare v_eq uuid; v_man text; v_n int;
begin
  select ev.id, ev.manager_email into strict v_eq, v_man from public.equipos_venta ev where ev.nombre = 'Carmen' and ev.activo;
  update public.contrato_closer k
     set equipo_id = v_eq, manager_email = v_man, equipo_congelado_en = now()
    from public.contratos c, public.contratos rz
   where c.id = k.contrato_id and rz.id = coalesce(c.contrato_padre_id, c.id)
     and lower(k.closer_email) = 'sales@lawangproperties.com'
     and k.equipo_congelado_en is null
     and coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date) < date '2026-09-24';
  get diagnostics v_n = row_count;
  if v_n <> 39 then
    raise exception 'F2 paso 1: se esperaban 39 ventas de Carmen y son %: parar y revisar', v_n;
  end if;
end $p1$;

-- 2 · una sola fecha de la venta (hora de Bali) en el congelado, el re-congelado y el motor
CREATE OR REPLACE FUNCTION public._venta_congela_equipo(p_raiz uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eq uuid; v_man text;
begin
  if not exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and k.equipo_congelado_en is null) then
    return;
  end if;
  select em.equipo_id, ev.manager_email into v_eq, v_man
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
    join public.equipo_miembros em on lower(em.closer_email) = lower(k.closer_email)
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where k.contrato_id = p_raiz
     and em.desde <= coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date)
     and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date))
   order by em.created_at desc
   limit 1;
  update public.contrato_closer k
     set equipo_id = v_eq, manager_email = v_man, equipo_congelado_en = now()
   where k.contrato_id = p_raiz and k.equipo_congelado_en is null;
end $function$;

CREATE OR REPLACE FUNCTION public._equipo_recongela_sin_equipo(p_email text, p_desde date, p_hasta date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n int := 0;
begin
  for r in
    select k.contrato_id from public.contrato_closer k
      join public.contratos c on c.id = k.contrato_id
      join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
     where lower(k.closer_email) = lower(p_email)
       and k.equipo_congelado_en is not null and k.equipo_id is null
       and coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date) >= p_desde
       and (p_hasta is null or coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date) <= p_hasta)
       and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = k.contrato_id)
  loop
    update public.contrato_closer k set equipo_id = null, manager_email = null, equipo_congelado_en = null
     where k.contrato_id = r.contrato_id;
    n := n + 1;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.comisiones_evaluar_contrato(p_contrato_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  -- mismo lock que comision_recalcular y venta_propia_resolver
  perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz_id::text));

  select c.moneda, c.proyecto_id, c.bloqueado, (c.created_at at time zone 'Asia/Makassar')::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  -- la Carta de Reserva hija ya vale suelo + obra: no se suma otra vez (24-sep-2026)
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

  -- una sola fecha de la venta para equipo y condicion: fecha_venta o creacion de la raiz en hora de Bali, la misma
  -- con la que _venta_congela_equipo congela (F2, 30-sep-2026; antes el equipo de una venta no congelada se buscaba a hoy)
  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);
  v_fecha_equipo := v_raiz_creada;

  select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null)
    into v_eq_cong, v_man_cong, v_congelado
    from public.contrato_closer k where k.contrato_id = v_raiz_id;
  if coalesce(v_congelado, false) then
    v_equipo_id := v_eq_cong;   -- equipo congelado en la venta (owner, 26-sep-2026)
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

  select * into v_propia
    from public.reclamaciones_venta_propia r
   where r.contrato_raiz_id = v_raiz_id and r.estado = 'aprobada';

  if v_propia.id is not null then
    -- venta propia aprobada: solo cobra quien la reclamó, con la condición de manager de SU equipo
    if lower(v_propia.solicitante_email) <> lower(v_closer_email) then
      return 0;
    end if;
    v_equipo_id := v_propia.equipo_id;
    v_niveles := array['propia'];
  elsif v_equipo_id is not null then
    if coalesce(v_congelado, false) then
      v_manager_email := v_man_cong;   -- manager congelado en la venta
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

    elsif v_nivel = 'estandar' then
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
      -- 'manager' cobra el manager; 'propia' cobra el closer con esa misma condición
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

    if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;

    if v_condicion.base_calculo <> 'importe_fijo' and v_condicion.pct_comision = 0 then
      continue;
    end if;

    -- la primera condición que devenga manda (un override posterior no re-devenga)
    if exists (
      select 1 from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.beneficiario_email = v_beneficiario
         and d.nivel = v_nivel
         and d.condicion_id <> v_condicion.id
    ) then
      continue;
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
      if exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.beneficiario_email = v_beneficiario
      ) then
        continue;
      end if;

      -- como mucho un pago de Lawang vivo por tramo de la venta (manager | propia | estandar)
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
        v_importe := round((v_condicion.pct_comision / 100) * v_base * (v_tramo.pct_tramo / 100), 2);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue;
      end if;

      v_devengo_id := null;

      insert into public.comisiones_devengadas (
        contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
        importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
      ) values (
        v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
        v_importe, v_moneda, null,
        jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'base_calculo', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', v_condicion.pct_comision,
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
          'equipo_id', v_equipo_id,
          'reclamacion_id', v_propia.id
        )
      )
      on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
      returning id into v_devengo_id;

      if v_devengo_id is null then
        continue;
      end if;

      v_creados := v_creados + 1;

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

-- 3 · solape de miembros tambien dentro del mismo equipo
CREATE OR REPLACE FUNCTION public.equipo_miembro_guarda(p_id uuid, p_equipo uuid, p_email text, p_desde date, p_hasta date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.equipo_miembros%rowtype; v_id uuid; v_n int := 0; v_choca uuid;
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if not public.es_admin() then raise exception 'Los equipos de venta los gestiona administración' using errcode = '42501'; end if;
  if v_email is null or not public._usuario_activo(v_email) then
    raise exception 'El miembro tiene que ser un usuario activo de la intranet' using errcode = '22023';
  end if;
  if v_email = lower(coalesce((select auth.email()), '')) and not public.es_super_admin() then
    raise exception 'Nadie se añade a sí mismo a un equipo' using errcode = '42501';
  end if;
  if p_desde is null then raise exception 'Falta la fecha «Desde»' using errcode = '22023'; end if;
  if p_hasta is not null and p_hasta < p_desde then raise exception '«Hasta» no puede ser anterior a «Desde».' using errcode = '22023'; end if;
  if not exists (select 1 from public.equipos_venta e where e.id = p_equipo) then
    raise exception 'Ese equipo no existe' using errcode = 'P0002';
  end if;
  -- solape de rangos con CUALQUIER otra fila de la persona, tambien del mismo equipo; una fila con «hasta» futura cuenta
  select em.equipo_id into v_choca from public.equipo_miembros em
   where lower(em.closer_email) = v_email
     and (p_id is null or em.id <> p_id)
     and em.desde <= coalesce(p_hasta, 'infinity'::date)
     and p_desde <= coalesce(em.hasta, 'infinity'::date)
   order by (em.equipo_id = p_equipo) desc
   limit 1;
  if found then
    if v_choca = p_equipo then
      raise exception 'Esa persona ya está en este equipo en esas fechas: edita su fila en vez de añadir otra' using errcode = '23P01';
    end if;
    raise exception 'Esa persona ya está en otro equipo en esas fechas: dale de baja allí primero' using errcode = '23P01';
  end if;
  if p_id is null then
    v_n := public._equipo_congela_ventas(p_equipo, v_email);
    insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by)
    values (p_equipo, v_email, p_desde, p_hasta, (select auth.email())) returning id into v_id;
    insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
    select 'equipo_miembros', v_id, null, to_jsonb(m), v_n from public.equipo_miembros m where m.id = v_id;
    return v_id;
  end if;
  select * into v_old from public.equipo_miembros m where m.id = p_id for update;
  if not found then raise exception 'Ese miembro no existe' using errcode = 'P0002'; end if;
  v_n := public._equipo_congela_ventas(v_old.equipo_id, v_old.closer_email)
       + public._equipo_congela_ventas(p_equipo, v_email);
  update public.equipo_miembros
     set equipo_id = p_equipo, closer_email = v_email, desde = p_desde, hasta = p_hasta
   where id = p_id;
  insert into public.equipos_log (tabla, fila_id, antes, despues, ventas_congeladas)
  select 'equipo_miembros', p_id, to_jsonb(v_old), to_jsonb(m), v_n from public.equipo_miembros m where m.id = p_id;
  return p_id;
end $function$;

-- 4 · estandar 10 % desde el 30-sep (la 2,5 % se cierra el 29-sep)
-- El indice de «una estandar activa por proyecto/closer» no conocia vigente_hasta (F2 la añadio sin tocarlo) e impedia
-- que convivieran la cerrada y la nueva. Pasa a «una estandar activa SIN FIN»: sigue impidiendo dos estandar abiertas,
-- y deja las cerradas por fecha (el motor ya elige por vigencia). Ninguna funcion usa este indice en un ON CONFLICT.
drop index public.condiciones_comision_estandar_unica;
create unique index condiciones_comision_estandar_unica on public.condiciones_comision
  (coalesce(proyecto_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(lower(closer_email), ''::text))
  where equipo_id is null and activo and vigente_hasta is null;

do $p4$
declare v_vieja uuid; v_nueva uuid; v_n int;
begin
  select c.id into strict v_vieja from public.condiciones_comision c
   where c.equipo_id is null and c.proyecto_id is null and c.nivel = 'closer' and c.closer_email is null
     and c.pct_comision = 2.5 and c.activo and c.vigente_hasta is null;
  select count(*) into v_n
    from public.comisiones_devengadas d
    join public.contrato_closer k on k.contrato_id = d.contrato_raiz_id
    join public.contratos rz on rz.id = d.contrato_raiz_id
   where d.nivel = 'estandar'
     and coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date) >= date '2026-09-30';
  if v_n > 0 then
    raise exception 'F2 paso 4: % devengos estandar con venta del 30-sep o posterior: parar', v_n;
  end if;
  update public.condiciones_comision set vigente_hasta = date '2026-09-29' where id = v_vieja;
  insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, importe_fijo, activo, created_by, vigente_desde)
  select null, null, 'closer', null, 10, c.base_calculo, c.importe_fijo, true, 'owner 30-sep-2026 (F2): venta sin equipo 10 %', date '2026-09-30'
    from public.condiciones_comision c where c.id = v_vieja
  returning id into v_nueva;
  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
  select v_nueva, t.orden, t.disparador_tipo, t.umbral, t.pct_tramo from public.condicion_tramos t where t.condicion_id = v_vieja;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'F2 paso 4: la estandar vieja no tenia tramos';
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo)
  values (v_vieja, jsonb_build_object('vigente_hasta', null), jsonb_build_object('vigente_hasta', '2026-09-29'),
          exists (select 1 from public.comisiones_devengadas d where d.condicion_id = v_vieja),
          'owner 30-sep-2026: a partir de hoy, venta sin equipo 10 %; la 2,5 % se cierra el 29-sep y sigue valiendo para las ventas anteriores');
  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
  select v_nueva, null, to_jsonb(c), 'owner 30-sep-2026: si un closer vende sin equipo es 10 % (mismos tramos que la 2,5 %)'
    from public.condiciones_comision c where c.id = v_nueva;
end $p4$;

-- ningun devengo ni solicitud nuevos dentro de la migracion
do $fin$
begin
  if (select nd from _f2_cuenta) <> (select count(*) from public.comisiones_devengadas)
     or (select ns from _f2_cuenta) <> (select count(*) from public.solicitudes_pago) then
    raise exception 'F2 arreglos: la migracion ha creado devengos o solicitudes: parar';
  end if;
end $fin$;
