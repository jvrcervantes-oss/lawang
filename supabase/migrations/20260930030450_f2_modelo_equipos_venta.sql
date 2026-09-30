-- F2 · modelo de datos de equipos de venta (30-sep-2026) · encargo 20260930_lawang_equipos_venta_asistente.
-- SOLO construye: columnas nuevas nullable o con default constante (ningun trigger de fila salta, ninguna fila existente
-- cambia de valor), una tabla nueva cerrada y el motor con la eleccion de condicion por vigencia. Nadie escribe aun en
-- lo nuevo: sin grants a authenticated (F5/F6 le pondran llamador; «reducir la exposicion»).
--
-- 1. condiciones_comision.vigente_hasta (fin de vigencia, inclusivo). Las 6 condiciones de 1900 NO se tocan: siguen
--    activas y sin fin. Porque: sin fecha de fin, cambiar una condicion re-devenga lo ya pagado (Datos #162).
-- 2. Motor comisiones_evaluar_contrato (construido sobre el cuerpo VIVO, md5 comprobado): la condicion se elige por
--    vigencia a la fecha de la venta — vigente_desde <= fecha <= vigente_hasta — y a igual especificidad gana la de
--    vigente_desde mas reciente (antes: `limit 1` sin ese orden). `activo` sigue valiendo para una condicion SIN
--    vigente_hasta (apagarla la saca); una condicion CERRADA con vigente_hasta sigue aplicando a las ventas de su
--    ventana aunque se desactive, que es lo que evita re-devengar el pasado. Nada mas cambia en el motor.
-- 3. contrato_closer.modo ('equipo' | 'propia'), NULL = sin declarar (nunca 'equipo' por defecto; las 188 filas quedan
--    NULL) + origen de la venta propia en lista cerrada + quien y cuando lo declaro. Lo escribira contrato_guarda (F5).
-- 4. equipo_miembros.rol (tipo fijo closer|setter|otro, D4) + rol_nombre (lo pone el SM) + indice unico: una persona,
--    un equipo activo.
-- 5. plantilla_reparto: herramienta del SM para repartir SU bote. NUNCA es una solicitud de pago de Lawang ni entra en
--    solicitudes_pago, comisiones_diferencias ni la conciliacion: el SM es el UNICO perceptor (D3 + Admin #162: si
--    Lawang guarda y fija el reparto, la DJP puede tratarla como pagador de cada closer). Suma 100 por equipo.
-- 6. equipos_venta.closers_ven_comision (default true = lo de hoy; el SM lo apagara en F6; F4 lo aplica).
-- 7. contrato_roles_equipo.pct + rol_nombre: copia congelada del reparto del dia de la venta (sin rellenar).
-- 8. reclamaciones_venta_propia: sin cambio de forma (solo comentario, ver abajo).
-- Inversa: contracts/sql/inversa_f2_modelo_equipos_20260930.sql

do $g$
begin
  if md5(replace(pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure), E'\r', '')) <> '1e0c897e64b2a547a90239f32cd4f212' then
    raise exception 'F2: el motor vivo ya no es el del volcado del 30-sep: rehacer sobre el nuevo';
  end if;
end $g$;

-- 1 · vigencia de las condiciones
alter table public.condiciones_comision add column vigente_hasta date;
alter table public.condiciones_comision add constraint condiciones_comision_vigencia_coherente
  check (vigente_hasta is null or vigente_hasta >= vigente_desde);
comment on column public.condiciones_comision.vigente_hasta is
  'Ultimo dia (inclusivo) en que la condicion aplica a una venta, por la fecha de la venta (fecha_venta o creacion de la raiz). NULL = sin fin. Una condicion vieja se CIERRA con esto, nunca se edita ni se desactiva: si no, re-devenga lo pagado (F2, 30-sep-2026).';

-- 3 · modo de la venta (equipo / por su cuenta)
alter table public.contrato_closer
  add column modo text,
  add column modo_origen text,
  add column modo_origen_texto text,
  add column modo_declarado_por text,
  add column modo_declarado_en timestamptz;
alter table public.contrato_closer
  add constraint contrato_closer_modo_check check (modo is null or modo in ('equipo', 'propia')),
  add constraint contrato_closer_modo_origen_check
    check (modo_origen is null or modo_origen in ('contacto_personal', 'referido_cliente', 'redes_propias', 'otro')),
  add constraint contrato_closer_modo_origen_solo_propia check (modo_origen is null or modo = 'propia');
comment on column public.contrato_closer.modo is
  'equipo | propia (venta por su cuenta). NULL = sin declarar: las ventas anteriores a F2 quedan NULL y NUNCA se leen como equipo por defecto. Dueno: la fila de la RAIZ; los hijos lo leen de ella. Lo escribe contrato_guarda (F5), nadie mas.';
comment on column public.contrato_closer.modo_origen is
  'Origen declarado de una venta por su cuenta (lista cerrada): contacto_personal | referido_cliente | redes_propias | otro (con modo_origen_texto).';

-- 4 · rol vigente del miembro + un equipo activo por persona
alter table public.equipo_miembros
  add column rol text not null default 'closer',
  add column rol_nombre text;
alter table public.equipo_miembros
  add constraint equipo_miembros_rol_check check (rol in ('closer', 'setter', 'otro'));
create unique index equipo_miembros_un_equipo_activo on public.equipo_miembros (lower(closer_email)) where hasta is null;
comment on column public.equipo_miembros.rol is
  'Tipo de rol fijo (closer | setter | otro, D4) para ranking y atribucion; rol_nombre es el nombre que le pone el SM. Rol VIGENTE: la copia del dia de la venta vive en contrato_roles_equipo.';

-- 6 · interruptor «mis closers ven su comision»
alter table public.equipos_venta add column closers_ven_comision boolean not null default true;
comment on column public.equipos_venta.closers_ven_comision is
  'Si los closers del equipo ven su parte de comision de equipo. Default true = lo de hoy. Lo apaga el SM (F6); lo aplica comision_visible (F4). Lo vendido por su cuenta se ve siempre.';

-- 7 · copia congelada del dia de la venta
alter table public.contrato_roles_equipo
  add column pct numeric,
  add column rol_nombre text;
alter table public.contrato_roles_equipo
  add constraint contrato_roles_equipo_pct_check check (pct is null or (pct >= 0 and pct <= 100));
comment on column public.contrato_roles_equipo.pct is
  'Porcentaje del reparto del SM CONGELADO el dia de la venta (copia de plantilla_reparto, ajustable hasta el primer pago, D5). Sin rellenar en F2. OJO para quien lo rellene: la PK (contrato_raiz_id, rol) y el check rol in (setter, team_lead) no admiten aun «el equipo entero del dia» ni filas closer/otro: se cambian en la fase que la llene, no antes.';

-- 8 · la objecion del SM reutilizara esta tabla (F5)
comment on table public.reclamaciones_venta_propia is
  'Hoy: reclamacion de venta propia (24-sep-2026, 0 usos). F5 la reconvierte en la OBJECION del SM a una venta marcada «por su cuenta» (Datos #162). F2 no le cambia la forma a proposito: el motor trata CUALQUIER fila estado=aprobada como venta propia pagable, asi que una columna tipo=objecion anadida sin tocar el motor haria cobrar una objecion aprobada. F5 anade el tipo y filtra por el en el motor EN LA MISMA migracion.';

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

  select c.moneda, c.proyecto_id, c.bloqueado, c.created_at::date
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

  -- fecha congelada (ventas desde 24-sep-2026); las anteriores, equipo de hoy (owner)
  v_fecha_equipo := coalesce(v_fecha_venta, current_date);
  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);

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


-- 5 · plantilla de reparto del SM (herramienta del SM, NUNCA un pago de Lawang)
create table public.plantilla_reparto (
  id          uuid primary key default gen_random_uuid(),
  equipo_id   uuid not null references public.equipos_venta(id) on delete cascade,
  rol_tipo    text not null check (rol_tipo in ('closer', 'setter', 'otro')),
  rol_nombre  text not null check (btrim(rol_nombre) <> ''),
  pct         numeric(5,2) not null check (pct > 0 and pct <= 100),
  creado_por  text,
  creado_en   timestamptz not null default now()
);
create unique index plantilla_reparto_rol_unico on public.plantilla_reparto (equipo_id, rol_tipo, lower(btrim(rol_nombre)));
comment on table public.plantilla_reparto is
  'Plantilla con la que el Sales Manager reparte SU bote entre los roles de su equipo (D5). Es herramienta del SM: NUNCA genera ni es una solicitud de pago de Lawang y no entra en solicitudes_pago, comisiones_diferencias ni la conciliacion. Lawang paga el bote al SM, UNICO perceptor (D3 + Admin #162: si Lawang guardara y fijara el reparto, la DJP podria tratarla como pagador real de cada closer). Suma 100 por equipo (trigger diferido). RLS sin policies y sin grants a authenticated hasta F6.';

alter table public.plantilla_reparto enable row level security;
revoke all on table public.plantilla_reparto from public, anon, authenticated;

create or replace function public._trg_plantilla_reparto_suma_100()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eq uuid; v_suma numeric;
begin
  -- suma por equipo al cerrar la transaccion: 100 exacto, o el equipo sin plantilla
  foreach v_eq in array array_remove(array[case when tg_op <> 'INSERT' then old.equipo_id end,
                                           case when tg_op <> 'DELETE' then new.equipo_id end], null)
  loop
    select sum(p.pct) into v_suma from public.plantilla_reparto p where p.equipo_id = v_eq;
    if v_suma is not null and v_suma <> 100 then
      raise exception 'plantilla_reparto: el reparto del equipo % suma % y tiene que sumar 100', v_eq, v_suma
        using errcode = 'check_violation';
    end if;
  end loop;
  return null;
end $function$;
revoke execute on function public._trg_plantilla_reparto_suma_100() from public, anon, authenticated;

create constraint trigger trg_plantilla_reparto_suma_100
  after insert or update or delete on public.plantilla_reparto
  deferrable initially deferred
  for each row execute function public._trg_plantilla_reparto_suma_100();
