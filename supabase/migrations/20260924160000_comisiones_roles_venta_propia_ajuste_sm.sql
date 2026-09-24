-- Comisiones: roles Setter y Team Lead · venta propia · el SM ajusta lo que paga él (24-sep-2026, owner).
--
-- REQUIERE aplicada antes 20260924150000_comisiones_base_sin_carta_hija.sql (este motor ya la incluye,
-- pero la corrección de los 4 devengos doblados vive allí).
--
-- Decisiones del owner (24-sep-2026):
--   A.1 Venta propia: el closer atribuido de una venta de equipo la reclama, su SM (o admin) la aprueba;
--       el agente cobra la fee ENTERA del manager (su condición), la paga Lawang con solicitud automática;
--       manager, closer, setter y team lead cobran 0 en esa venta.
--   B.1 El SM ajusta (importe / %) y anula las comisiones pendientes de SU equipo que paga él
--       (closer/setter/team_lead). Lo que paga Lawang (manager/propia/estandar) sigue solo admin.
--   Tercer rol = «Team Lead». Equipo a fecha de venta: SOLO ventas nuevas (desde 24-sep-2026);
--   las anteriores siguen con el equipo de hoy. Fiscal: igual que hoy (bruto, retención a mano).
--
-- Revisión previa #65 (Seguridad + Administración + Datos) plegada:
--   · fecha de la venta CONGELADA en contrato_closer.fecha_venta (contratos.created_at es editable)
--   · contrato_padre_id no se mueve con comisiones vivas (cambiaría la raíz)
--   · crm_contrato_closer_set se niega con reclamación viva o devengos (fabricar una venta propia)
--   · la exclusión de «propia» vive en el MOTOR (si no, el siguiente recibí regenera el equipo) + lock por raíz
--   · niveles en POSITIVO: el SM solo toca ('closer','setter','team_lead')
--   · como mucho UN pago de Lawang vivo por raíz (manager | propia | estandar); importes a 2 decimales
--   · tablas nuevas: RLS, solo SELECT a authenticated, escritura solo por DEFINER; grants explícitos

-- =============================================================== 1. niveles
alter table public.condiciones_comision drop constraint condiciones_comision_nivel_check;
alter table public.condiciones_comision add constraint condiciones_comision_nivel_check
  check (nivel in ('manager', 'closer', 'setter', 'team_lead'));

alter table public.comisiones_devengadas drop constraint comisiones_devengadas_nivel_check;
alter table public.comisiones_devengadas add constraint comisiones_devengadas_nivel_check
  check (nivel in ('manager', 'closer', 'setter', 'team_lead', 'estandar', 'propia'));

alter table public.comisiones_devengadas drop constraint comisiones_devengadas_solicitud_solo_lawang;
alter table public.comisiones_devengadas add constraint comisiones_devengadas_solicitud_solo_lawang
  check (solicitud_id is null or nivel in ('manager', 'estandar', 'propia'));

-- un solo pago de Lawang vivo por venta (manager | propia | estandar), a nivel de base
create unique index if not exists comisiones_devengadas_un_pago_lawang_por_tramo
  on public.comisiones_devengadas (contrato_raiz_id, tramo_id)
  where nivel in ('manager', 'estandar', 'propia') and estado <> 'anulada';

-- =============================================================== 2. fecha de la venta congelada
alter table public.contrato_closer add column if not exists fecha_venta date;
comment on column public.contrato_closer.fecha_venta is
  'Fecha de la venta para comisiones (equipo y vigencia de condición). La pone el sistema al atribuir la raíz y no cambia. NULL = venta anterior al 24-sep-2026: el motor usa el equipo de hoy (decisión del owner).';

update public.contrato_closer k
   set fecha_venta = c.created_at::date
  from public.contratos c
 where c.id = k.contrato_id and c.contrato_padre_id is null
   and c.created_at >= '2026-09-24' and k.fecha_venta is null;

create or replace function public._trg_contrato_closer_fecha_venta()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.fecha_venta := old.fecha_venta;
    return new;
  end if;
  select case when c.created_at >= '2026-09-24' then c.created_at::date end
    into new.fecha_venta
    from public.contratos c where c.id = new.contrato_id;
  return new;
end $$;
revoke execute on function public._trg_contrato_closer_fecha_venta() from public, anon, authenticated;
drop trigger if exists trg_contrato_closer_fecha_venta on public.contrato_closer;
create trigger trg_contrato_closer_fecha_venta before insert or update on public.contrato_closer
  for each row execute function public._trg_contrato_closer_fecha_venta();

-- la raíz de una venta con comisiones vivas no se cambia desde la sesión
create or replace function public._trg_contrato_padre_con_comisiones()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.contrato_padre_id is not distinct from old.contrato_padre_id then return new; end if;
  if current_user not in ('authenticated', 'anon') or public.es_super_admin() then return new; end if;
  if exists (select 1 from public.comisiones_devengadas d
              where d.estado <> 'anulada'
                and d.contrato_raiz_id in (old.id, old.contrato_padre_id, new.contrato_padre_id))
     or exists (select 1 from public.reclamaciones_venta_propia r
              where r.estado in ('pendiente', 'aprobada')
                and r.contrato_raiz_id in (old.id, old.contrato_padre_id, new.contrato_padre_id)) then
    raise exception 'esta venta ya tiene comisiones: el contrato padre solo lo cambia un super admin' using errcode = '42501';
  end if;
  return new;
end $$;
revoke execute on function public._trg_contrato_padre_con_comisiones() from public, anon, authenticated;

-- =============================================================== 3. roles por venta
create table if not exists public.contrato_roles_equipo (
  contrato_raiz_id uuid not null references public.contratos(id) on delete cascade,
  rol              text not null check (rol in ('setter', 'team_lead')),
  email            text not null check (email = lower(btrim(email)) and email <> ''),
  equipo_id        uuid not null references public.equipos_venta(id),
  asignado_por     text not null,
  asignado_en      timestamptz not null default now(),
  primary key (contrato_raiz_id, rol)
);
alter table public.contrato_roles_equipo enable row level security;
revoke all on public.contrato_roles_equipo from anon, authenticated;
grant select on public.contrato_roles_equipo to authenticated;
drop policy if exists "roles de venta: leer" on public.contrato_roles_equipo;
create policy "roles de venta: leer" on public.contrato_roles_equipo for select to authenticated
  using (email = lower((select auth.email()))
         or public.es_manager_de_equipo(equipo_id)
         or (public.es_admin() and public.puede('comisiones_reparto')));

-- =============================================================== 4. reclamaciones de venta propia
create table if not exists public.reclamaciones_venta_propia (
  id                uuid primary key default gen_random_uuid(),
  contrato_raiz_id  uuid not null references public.contratos(id),
  solicitante_email text not null,
  equipo_id         uuid not null references public.equipos_venta(id),
  manager_email     text not null,
  motivo            text not null check (btrim(motivo) <> ''),
  estado            text not null default 'pendiente'
                    check (estado in ('pendiente', 'aprobada', 'rechazada', 'retirada')),
  creado_en         timestamptz not null default now(),
  resuelto_por      text,
  resuelto_en       timestamptz,
  motivo_resolucion text,
  check (estado = 'pendiente' or resuelto_en is not null),
  check (estado <> 'rechazada' or nullif(btrim(coalesce(motivo_resolucion, '')), '') is not null)
);
create unique index if not exists reclamaciones_venta_propia_una_viva
  on public.reclamaciones_venta_propia (contrato_raiz_id) where estado in ('pendiente', 'aprobada');
alter table public.reclamaciones_venta_propia enable row level security;
revoke all on public.reclamaciones_venta_propia from anon, authenticated;
grant select on public.reclamaciones_venta_propia to authenticated;
drop policy if exists "venta propia: leer" on public.reclamaciones_venta_propia;
create policy "venta propia: leer" on public.reclamaciones_venta_propia for select to authenticated
  using (lower(solicitante_email) = lower((select auth.email()))
         or public.es_manager_de_equipo(equipo_id)
         or (public.es_admin() and public.puede('comisiones_reparto')));

drop trigger if exists trg_contrato_padre_con_comisiones on public.contratos;
create trigger trg_contrato_padre_con_comisiones before update of contrato_padre_id on public.contratos
  for each row execute function public._trg_contrato_padre_con_comisiones();

-- equipo de una venta: el del closer atribuido en la fecha de la venta (o hoy si es anterior al 24-sep)
create or replace function public._equipo_de_venta(p_raiz uuid)
returns table(equipo_id uuid, manager_email text, closer_email text, fecha date)
language sql stable security definer set search_path = '' as $$
  select em.equipo_id, lower(ev.manager_email), lower(k.closer_email), coalesce(k.fecha_venta, current_date)
    from public.contrato_closer k
    join public.equipo_miembros em on lower(em.closer_email) = lower(k.closer_email)
    join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
   where k.contrato_id = p_raiz
     and em.desde <= coalesce(k.fecha_venta, current_date)
     and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
   order by em.created_at desc
   limit 1
$$;
revoke execute on function public._equipo_de_venta(uuid) from public, anon, authenticated;

-- =============================================================== 5. motor
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
  v_tramo                record;
  v_base                 numeric;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_concepto             text;
  v_creados              integer := 0;
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

  select c.moneda, c.proyecto_id, c.bloqueado, c.created_at::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  -- la Carta de Reserva hija ya vale suelo + obra: no se suma otra vez (24-sep-2026)
  select coalesce(sum(x.precio_total), 0)
    into v_precio_total
    from public.contratos x
   where (x.id = v_raiz_id or x.contrato_padre_id = v_raiz_id)
     and not (x.contrato_padre_id is not null and x.tipo like 'carta_reserva%');

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

  -- fecha congelada (ventas desde 24-sep-2026); las anteriores, equipo de hoy (owner)
  v_fecha_equipo := coalesce(v_fecha_venta, current_date);
  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);

  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.activo
     and em.desde <= v_fecha_equipo
     and (em.hasta is null or em.hasta >= v_fecha_equipo)
   order by em.created_at desc
   limit 1;

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
    select ev.manager_email into v_manager_email
      from public.equipos_venta ev
     where ev.id = v_equipo_id;
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
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and lower(c.closer_email) = lower(v_beneficiario)
       order by (c.proyecto_id is not null) desc
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = v_nivel
           and c.activo
           and c.vigente_desde <= v_raiz_creada
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc
         limit 1;
      end if;

    elsif v_nivel = 'estandar' then
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id is null
         and c.nivel = 'closer'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = lower(v_closer_email))
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc
       limit 1;

    else
      -- 'manager' cobra el manager; 'propia' cobra el closer con esa misma condición
      v_beneficiario := case when v_nivel = 'propia' then v_closer_email else v_manager_email end;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc
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
        when 'pct_cobrado_total' then
          v_precio_total > 0 and (v_cobrado_total / v_precio_total * 100) >= v_tramo.umbral
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
revoke execute on function public.comisiones_evaluar_contrato(uuid) from public, anon, authenticated;

-- =============================================================== 6. asignar setter / team lead
create or replace function public.comision_rol_asignar(p_raiz uuid, p_rol text, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_yo    text := lower(coalesce(auth.email(), ''));
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_eq    record;
  v_prev  text;
begin
  if v_yo = '' then raise exception 'sesión sin identidad' using errcode = '42501'; end if;
  if p_rol not in ('setter', 'team_lead') then raise exception 'rol desconocido' using errcode = '22023'; end if;
  if not exists (select 1 from public.contratos c where c.id = p_raiz and c.contrato_padre_id is null) then
    raise exception 'esa venta no existe (o no es la raíz)' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select * into v_eq from public._equipo_de_venta(p_raiz);
  if v_eq.equipo_id is null then
    raise exception 'esta venta no es de ningún equipo: no lleva setter ni team lead' using errcode = '22023';
  end if;
  if not (public.es_manager_de_equipo(v_eq.equipo_id) or (public.es_admin() and public.puede('comisiones_reparto'))) then
    raise exception 'solo el manager del equipo o un administrador asigna los roles de una venta' using errcode = '42501';
  end if;
  if v_email is not null and v_email = v_yo and not public.es_super_admin() then
    raise exception 'un rol de la venta no se lo asigna uno mismo' using errcode = '42501';
  end if;
  if v_email is not null and not exists (
       select 1 from public.equipo_miembros em
        where em.equipo_id = v_eq.equipo_id and lower(em.closer_email) = v_email
          and em.desde <= v_eq.fecha and (em.hasta is null or em.hasta >= v_eq.fecha)) then
    raise exception 'esa persona no estaba en el equipo en la fecha de la venta' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r
              where r.contrato_raiz_id = p_raiz and r.estado = 'aprobada') then
    raise exception 'esta venta es venta propia aprobada: no lleva roles de equipo' using errcode = '22023';
  end if;

  select re.email into v_prev from public.contrato_roles_equipo re where re.contrato_raiz_id = p_raiz and re.rol = p_rol;
  if v_prev is not distinct from v_email then return; end if;
  if v_prev is not null and exists (
       select 1 from public.comisiones_devengadas d
        where d.contrato_raiz_id = p_raiz and d.nivel = p_rol and lower(d.beneficiario_email) = v_prev
          and d.estado <> 'anulada') then
    raise exception 'ese rol ya ha generado comisión a su nombre: anúlala primero (con motivo) y vuelve a asignarlo' using errcode = '22023';
  end if;

  if v_email is null then
    delete from public.contrato_roles_equipo where contrato_raiz_id = p_raiz and rol = p_rol;
  else
    insert into public.contrato_roles_equipo (contrato_raiz_id, rol, email, equipo_id, asignado_por)
    values (p_raiz, p_rol, v_email, v_eq.equipo_id, v_yo)
    on conflict (contrato_raiz_id, rol) do update
      set email = excluded.email, equipo_id = excluded.equipo_id,
          asignado_por = excluded.asignado_por, asignado_en = now();
  end if;

  -- si la venta ya cumple el tramo, el rol devenga ya
  perform public.comisiones_evaluar_contrato(p_raiz);
end $$;
revoke execute on function public.comision_rol_asignar(uuid, text, text) from public, anon;
grant execute on function public.comision_rol_asignar(uuid, text, text) to authenticated;

-- =============================================================== 7. venta propia: reclamar / retirar / resolver
create or replace function public.venta_propia_reclamar(p_raiz uuid, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_eq  record;
  v_id  uuid;
begin
  if v_yo = '' then raise exception 'sesión sin identidad' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'explica por qué es venta tuya (de dónde viene el cliente)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_raiz and c.contrato_padre_id is null) then
    raise exception 'esa venta no existe (o no es la raíz)' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_raiz::text, 2));
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select * into v_eq from public._equipo_de_venta(p_raiz);
  if v_eq.closer_email is distinct from v_yo then
    raise exception 'solo el closer atribuido de la venta puede reclamarla como propia' using errcode = '42501';
  end if;
  if v_eq.equipo_id is null then
    raise exception 'esta venta no es de ningún equipo: ya cobras la comisión estándar' using errcode = '22023';
  end if;
  if v_eq.manager_email = v_yo then
    raise exception 'eres el manager de este equipo: tu venta ya cobra la fee de manager' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r
              where r.contrato_raiz_id = p_raiz and r.estado in ('pendiente', 'aprobada')) then
    raise exception 'esta venta ya tiene una reclamación abierta o aprobada' using errcode = '23505';
  end if;

  insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo)
  values (p_raiz, v_yo, v_eq.equipo_id, v_eq.manager_email, btrim(p_motivo))
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.venta_propia_reclamar(uuid, text) from public, anon;
grant execute on function public.venta_propia_reclamar(uuid, text) to authenticated;

create or replace function public.venta_propia_retirar(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_yo text := lower(coalesce(auth.email(), ''));
begin
  update public.reclamaciones_venta_propia
     set estado = 'retirada', resuelto_por = v_yo, resuelto_en = now()
   where id = p_id and estado = 'pendiente' and lower(solicitante_email) = v_yo;
  if not found then
    raise exception 'solo quien la pidió retira una reclamación pendiente' using errcode = '42501';
  end if;
end $$;
revoke execute on function public.venta_propia_retirar(uuid) from public, anon;
grant execute on function public.venta_propia_retirar(uuid) to authenticated;

create or replace function public.venta_propia_resolver(p_id uuid, p_aprobar boolean, p_motivo text)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_yo     text := lower(coalesce(auth.email(), ''));
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  r        public.reclamaciones_venta_propia;
  v_closer text;
  d        record;
  n        integer := 0;
begin
  if v_yo = '' then raise exception 'sesión sin identidad' using errcode = '42501'; end if;
  select * into r from public.reclamaciones_venta_propia where id = p_id;
  if not found then raise exception 'no existe esa reclamación' using errcode = 'P0002'; end if;

  perform pg_advisory_xact_lock(hashtextextended(r.contrato_raiz_id::text, 2));
  perform pg_advisory_xact_lock(hashtext('comisiones:' || r.contrato_raiz_id::text));
  select * into r from public.reclamaciones_venta_propia where id = p_id for update;

  if r.estado <> 'pendiente' then
    raise exception 'esta reclamación ya está %', r.estado using errcode = '22023';
  end if;
  if not (lower(r.manager_email) = v_yo or (public.es_admin() and public.puede('comisiones_reparto'))) then
    raise exception 'la resuelve el manager del equipo o un administrador' using errcode = '42501';
  end if;
  if lower(r.solicitante_email) = v_yo then
    raise exception 'nadie resuelve su propia reclamación' using errcode = '42501';
  end if;

  if not p_aprobar then
    if v_motivo is null then raise exception 'rechazar exige un motivo' using errcode = '22023'; end if;
    update public.reclamaciones_venta_propia
       set estado = 'rechazada', resuelto_por = v_yo, resuelto_en = now(), motivo_resolucion = v_motivo
     where id = r.id;
    return 0;
  end if;

  -- sigue siendo el mismo closer que reclamó
  select lower(k.closer_email) into v_closer from public.contrato_closer k where k.contrato_id = r.contrato_raiz_id;
  if v_closer is distinct from lower(r.solicitante_email) then
    raise exception 'el closer de esta venta ha cambiado desde que se pidió: no se aprueba' using errcode = '22023';
  end if;
  -- nada del equipo ya aprobado, pagado o en disputa
  if exists (
       select 1 from public.comisiones_devengadas cd
         left join public.solicitudes_pago sp on sp.id = cd.solicitud_id
        where cd.contrato_raiz_id = r.contrato_raiz_id
          and cd.estado <> 'anulada'
          and (cd.estado in ('pagada', 'en_disputa') or sp.estado in ('aprobada', 'pagada'))) then
    raise exception 'hay comisiones de esta venta ya aprobadas, pagadas o en disputa: la venta propia la resuelve Administración a mano' using errcode = '22023';
  end if;

  update public.reclamaciones_venta_propia
     set estado = 'aprobada', resuelto_por = v_yo, resuelto_en = now(), motivo_resolucion = v_motivo
   where id = r.id;

  -- anula lo del equipo que estuviera pendiente (con rastro)
  perform set_config('app.via_venta_propia', 'on', true);
  update public.solicitudes_pago sp
     set estado = 'anulada', motivo_ajuste = 'Venta propia aprobada de ' || r.solicitante_email
   where sp.estado = 'pendiente'
     and sp.id in (select cd.solicitud_id from public.comisiones_devengadas cd
                    where cd.contrato_raiz_id = r.contrato_raiz_id and cd.nivel = 'manager' and cd.solicitud_id is not null);
  perform set_config('app.via_venta_propia', 'off', true);

  for d in select * from public.comisiones_devengadas cd
            where cd.contrato_raiz_id = r.contrato_raiz_id and cd.estado = 'pendiente'
              and cd.nivel in ('manager', 'closer', 'setter', 'team_lead') loop
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
    values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe),
            d.estado, 'anulada', 'Venta propia aprobada de ' || r.solicitante_email);
    update public.comisiones_devengadas
       set estado = 'anulada', anulado_motivo = 'Venta propia aprobada de ' || r.solicitante_email,
           anulado_por = auth.uid(), anulado_en = now()
     where id = d.id;
  end loop;

  n := public.comisiones_evaluar_contrato(r.contrato_raiz_id);
  return coalesce(n, 0);
end $$;
revoke execute on function public.venta_propia_resolver(uuid, boolean, text) from public, anon;
grant execute on function public.venta_propia_resolver(uuid, boolean, text) to authenticated;

-- la solicitud del manager se anula desde venta_propia_resolver (su SM no es admin): marca de transacción
do $$
declare d text; m text; n text;
begin
  d := pg_get_functiondef('public._trg_solicitud_pago_transicion()'::regprocedure);
  if position('app.via_venta_propia' in d) = 0 then
    m := E'    elsif new.estado = ''anulada'' then\n      if old.origen = ''comision_automatica'' or old.creado_por is distinct from auth.uid() then';
    n := E'    elsif new.estado = ''anulada'' then\n      if coalesce(current_setting(''app.via_venta_propia'', true), '''') <> ''on''\n         and (old.origen = ''comision_automatica'' or old.creado_por is distinct from auth.uid()) then';
    if position(m in d) = 0 then
      raise exception '_trg_solicitud_pago_transicion: marca de anular no encontrada';
    end if;
    execute replace(d, m, n);
  end if;
end $$;

-- =============================================================== 8. el SM ajusta lo que paga él
create or replace function public._comision_devengo_admin_puede(p_id uuid)
returns public.comisiones_devengadas language plpgsql security definer set search_path = '' as $$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), ''));
begin
  select * into d from public.comisiones_devengadas where id = p_id for update;
  if not found then raise exception 'no existe esa comisión' using errcode = 'P0002'; end if;
  -- en positivo: solo lo que paga el manager de su bolsillo (24-sep-2026, owner B.1)
  if d.nivel not in ('closer', 'setter', 'team_lead') then
    raise exception 'esta comisión la paga Lawang: se ajusta desde su solicitud de pago' using errcode = '22023';
  end if;
  if not ((public.es_admin() and public.puede('comisiones_reparto'))
          or public.es_manager_de_equipo(public._equipo_de_condicion_comision(d.condicion_id))) then
    raise exception 'la ajusta el manager que la paga o un administrador' using errcode = '42501';
  end if;
  if d.estado <> 'pendiente' then
    raise exception 'solo se ajusta una comisión pendiente (esta está %)', d.estado using errcode = '22023';
  end if;
  if lower(d.beneficiario_email) = v_yo then
    raise exception 'no puedes ajustar una comisión a tu nombre' using errcode = '42501';
  end if;
  return d;
end $$;
revoke execute on function public._comision_devengo_admin_puede(uuid) from public, anon, authenticated;

create or replace function public.comision_devengo_ajustar(p_id uuid, p_importe numeric, p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
declare d public.comisiones_devengadas; v_imp numeric := round(p_importe, 2);
begin
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'el ajuste exige un motivo' using errcode = '22023';
  end if;
  if v_imp is null or v_imp <= 0 then
    raise exception 'el importe tiene que ser mayor que cero (para dejarla en cero, anúlala)' using errcode = '22023';
  end if;
  d := public._comision_devengo_admin_puede(p_id);
  insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
  values ('comisiones_devengadas', d.id, 'editar_importe', coalesce(d.importe_ajustado, d.importe), v_imp, d.estado, d.estado, btrim(p_motivo));
  update public.comisiones_devengadas
     set importe_ajustado = v_imp, ajuste_motivo = btrim(p_motivo), ajustado_por = auth.uid(), ajustado_en = now()
   where id = d.id;
end $$;

-- =============================================================== 9. policies a los tres roles de equipo
drop policy if exists "comisiones_devengadas: leer" on public.comisiones_devengadas;
create policy "comisiones_devengadas: leer" on public.comisiones_devengadas for select to authenticated
  using ((public.es_admin() and public.puede('comisiones_reparto'))
         or lower(beneficiario_email) = lower((select auth.email()))
         or (nivel in ('closer', 'setter', 'team_lead')
             and public.es_manager_de_equipo(public._equipo_de_condicion_comision(condicion_id))));

drop policy if exists "comisiones_devengadas: el manager del equipo cierra el cobro de" on public.comisiones_devengadas;
create policy "comisiones_devengadas: el manager del equipo cierra el cobro de" on public.comisiones_devengadas
  for update to authenticated
  using (nivel in ('closer', 'setter', 'team_lead')
         and ((public.es_admin() and public.puede('comisiones_reparto'))
              or public.es_manager_de_equipo(public._equipo_de_condicion_comision(condicion_id))))
  with check (nivel in ('closer', 'setter', 'team_lead')
         and ((public.es_admin() and public.puede('comisiones_reparto'))
              or public.es_manager_de_equipo(public._equipo_de_condicion_comision(condicion_id))));

drop policy if exists "condiciones: el manager configura a sus closers" on public.condiciones_comision;
create policy "condiciones: el manager configura a sus closers" on public.condiciones_comision for all to authenticated
  using (nivel in ('closer', 'setter', 'team_lead') and equipo_id is not null and public.es_manager_de_equipo(equipo_id))
  with check (nivel in ('closer', 'setter', 'team_lead') and equipo_id is not null and public.es_manager_de_equipo(equipo_id)
              and (closer_email is null or exists (
                select 1 from public.equipo_miembros em
                 where em.equipo_id = condiciones_comision.equipo_id
                   and lower(em.closer_email) = lower(condiciones_comision.closer_email)
                   and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))));

drop policy if exists "condiciones_comision: leer" on public.condiciones_comision;
create policy "condiciones_comision: leer" on public.condiciones_comision for select to authenticated
  using (public.es_admin()
         or (nivel in ('closer', 'setter', 'team_lead')
             and (closer_email = (select auth.email())
                  or (closer_email is null and exists (
                        select 1 from public.equipo_miembros em
                         where em.equipo_id = condiciones_comision.equipo_id
                           and em.closer_email = (select auth.email())
                           and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date)))))
         or (nivel = 'manager' and exists (
               select 1 from public.equipos_venta ev
                where ev.id = condiciones_comision.equipo_id and ev.manager_email = (select auth.email()))));

drop policy if exists "condicion_tramos: leer" on public.condicion_tramos;
create policy "condicion_tramos: leer" on public.condicion_tramos for select to authenticated
  using (exists (select 1 from public.condiciones_comision c
                  where c.id = condicion_tramos.condicion_id
                    and (public.es_admin()
                         or (c.nivel in ('closer', 'setter', 'team_lead')
                             and (c.closer_email = (select auth.email())
                                  or (c.closer_email is null and exists (
                                        select 1 from public.equipo_miembros em
                                         where em.equipo_id = c.equipo_id and em.closer_email = (select auth.email())
                                           and em.desde <= current_date and (em.hasta is null or em.hasta >= current_date)))))
                         or (c.nivel = 'manager' and exists (
                               select 1 from public.equipos_venta ev
                                where ev.id = c.equipo_id and ev.manager_email = (select auth.email()))))));

drop policy if exists "tramos: el manager configura los de sus closers" on public.condicion_tramos;
create policy "tramos: el manager configura los de sus closers" on public.condicion_tramos for all to authenticated
  using (exists (select 1 from public.condiciones_comision c
                  where c.id = condicion_tramos.condicion_id and c.nivel in ('closer', 'setter', 'team_lead')
                    and c.equipo_id is not null and public.es_manager_de_equipo(c.equipo_id)
                    and not exists (select 1 from public.comisiones_devengadas d where d.condicion_id = c.id)))
  with check (exists (select 1 from public.condiciones_comision c
                  where c.id = condicion_tramos.condicion_id and c.nivel in ('closer', 'setter', 'team_lead')
                    and c.equipo_id is not null and public.es_manager_de_equipo(c.equipo_id)
                    and not exists (select 1 from public.comisiones_devengadas d where d.condicion_id = c.id)));

-- =============================================================== 10. cambiar el closer con comisiones vivas
do $$
declare d text; m text; n text;
begin
  d := pg_get_functiondef('public.crm_contrato_closer_set(uuid,text,text)'::regprocedure);
  if position('reclamaciones_venta_propia' in d) = 0 then
    m := E'  if v_destino is null then\n    delete from public.contrato_closer k';
    n := E'  if not public.es_super_admin() and (\n'
      || E'       exists (select 1 from public.reclamaciones_venta_propia r\n'
      || E'                where r.contrato_raiz_id = p_contrato and r.estado in (''pendiente'', ''aprobada''))\n'
      || E'    or exists (select 1 from public.comisiones_devengadas d\n'
      || E'                where d.contrato_raiz_id = p_contrato and d.estado <> ''anulada'')) then\n'
      || E'    raise exception ''Esta venta ya tiene comisiones o una reclamacion de venta propia: el closer solo lo cambia un super admin'' using errcode = ''PT409'';\n'
      || E'  end if;\n\n' || m;
    if position(m in d) = 0 then
      raise exception 'crm_contrato_closer_set: marca del borrado no encontrada';
    end if;
    execute replace(d, m, n);
  end if;
end $$;

-- =============================================================== 11. ventas de equipo para la pantalla
create or replace function public.comisiones_ventas_equipo()
returns table(
  raiz_id uuid, numero text, proyecto_nombre text, creada date, fecha_venta date,
  equipo_id uuid, equipo_nombre text, manager_email text,
  closer_email text, setter_email text, team_lead_email text,
  reclamacion_id uuid, reclamacion_estado text, reclamacion_solicitante text,
  reclamacion_motivo text, reclamacion_resolucion text, reclamacion_en timestamptz,
  soy_manager boolean)
language sql stable security definer set search_path = '' as $$
  with yo as (select lower(coalesce(auth.email(), '')) as e,
                     (public.es_admin() and public.puede('comisiones_reparto')) as admin),
  ventas as (
    select c.id, c.numero, c.proyecto_nombre, c.created_at::date as creada, k.fecha_venta,
           lower(k.closer_email) as closer,
           (select em.equipo_id from public.equipo_miembros em
              join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
             where lower(em.closer_email) = lower(k.closer_email)
               and em.desde <= coalesce(k.fecha_venta, current_date)
               and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
             order by em.created_at desc limit 1) as equipo_id
      from public.contratos c
      join public.contrato_closer k on k.contrato_id = c.id
     where c.contrato_padre_id is null
  )
  select v.id, v.numero, v.proyecto_nombre, v.creada, v.fecha_venta,
         coalesce(r.equipo_id, v.equipo_id), ev.nombre, lower(ev.manager_email),
         v.closer, st.email, tl.email,
         r.id, r.estado, r.solicitante_email, r.motivo, r.motivo_resolucion, coalesce(r.resuelto_en, r.creado_en),
         lower(ev.manager_email) = yo.e
    from ventas v
    cross join yo
    left join lateral (select * from public.reclamaciones_venta_propia r0
                        where r0.contrato_raiz_id = v.id
                        order by (r0.estado in ('pendiente', 'aprobada')) desc, r0.creado_en desc limit 1) r on true
    join public.equipos_venta ev on ev.id = coalesce(r.equipo_id, v.equipo_id)
    left join public.contrato_roles_equipo st on st.contrato_raiz_id = v.id and st.rol = 'setter'
    left join public.contrato_roles_equipo tl on tl.contrato_raiz_id = v.id and tl.rol = 'team_lead'
   where yo.e <> ''
     and (yo.admin or lower(ev.manager_email) = yo.e or v.closer = yo.e
          or st.email = yo.e or tl.email = yo.e)
   order by v.creada desc
$$;
revoke execute on function public.comisiones_ventas_equipo() from public, anon;
grant execute on function public.comisiones_ventas_equipo() to authenticated;
