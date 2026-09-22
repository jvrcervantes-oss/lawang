-- Condición ESTÁNDAR de comisión para quien cierra sin equipo — 22-sep-2026, owner
-- ----------------------------------------------------------------------------
-- HECHO: el motor (comisiones_evaluar_contrato) buscaba el equipo vigente del
-- closer y, sin equipo, devolvía 0. Solo 4 de las 18 personas que han cerrado
-- ventas raíz están en un equipo: el 75% de las ventas no devengaría nada.
--
-- DECISIÓN DEL OWNER: una condición estándar de Lawang —2,5% sobre precio
-- total, todos los proyectos, un tramo: 100% al cobrar el 50% de la parcela—
-- para cualquiera que cierre sin equipo, sea cual sea su rol. La paga Lawang
-- directamente al agente: genera solicitud de pago como el nivel manager.
-- Se afina por persona con el override individual (closer_email), que manda
-- sobre la general. Quien SÍ tiene equipo sigue con las condiciones de su
-- equipo; el estándar no se le aplica.
--
-- Lo que la revisión previa (#45, Seguridad + Administración) cambió del plan:
--  · vigente_desde en la condición: sin fecha de corte, ventas antiguas ya
--    liquidadas fuera del sistema devengarían al siguiente recibí (Admin:
--    ~12.100 EUR a 4 personas). Solo cuenta una raíz nacida ≥ vigente_desde.
--    Las condiciones que ya existen se quedan sin corte (1900-01-01): nada
--    cambia para los equipos.
--  · La solicitud automática NO la puede retocar su beneficiario: la transición
--    pendiente→pendiente dejaba cambiar importe/moneda/beneficiario, y con el
--    estándar quien registra el recibí y quien cobra son la misma persona.
--  · Nadie aprueba ni marca pagada una solicitud a su propio nombre; nadie se
--    atribuye una venta a sí mismo (salvo super_admin, que ya tenía ese poder).
--  · El concepto de la solicitud dice %, base, valor a fecha de disparo y que
--    el importe es BRUTO: Lawang pasa a ser retenedor (PPh 21/26) al pagar
--    directo; la retención y el IDR van en pago_referencia al marcar pagada.
--  · creado_por de la solicitud con último recurso a un super_admin activo:
--    un devengo sin solicitud quedaba en silencio (warning). Invariante nuevo
--    en tools/salud_lawang.py.
--  · El motor usa unidad_parte_cobrada_interno() (sin gate de sesión): con la
--    variante _split, si el recibí lo registraba alguien que no era autor ni
--    manager del contrato, el cobrado salía 0 y el tramo no disparaba nunca.
--    El motor es DEFINER y decide él quién cobra; el gate es del front.
-- destructivo-ok: se reemplazan dos CHECK de comisiones_devengadas por versiones
--    que admiten el nivel 'estandar' (ningún dato se toca; revisión previa #45)

-- 1. La condición admite «sin equipo» (estándar) y «todos los proyectos».
alter table public.condiciones_comision
  alter column equipo_id drop not null,
  alter column proyecto_id drop not null,
  add column vigente_desde date not null default '1900-01-01';
alter table public.condiciones_comision alter column vigente_desde set default current_date;

alter table public.condiciones_comision
  add constraint condiciones_comision_estandar_es_closer
    check (equipo_id is not null or nivel = 'closer'),
  add constraint condiciones_comision_equipo_con_proyecto
    check (equipo_id is null or proyecto_id is not null);

-- una sola estándar general activa por ámbito, y una sola override activa por
-- persona y ámbito (lower(): el motor compara emails sin distinguir mayúsculas)
create unique index condiciones_comision_estandar_unica
  on public.condiciones_comision (
    coalesce(proyecto_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(lower(closer_email), ''))
  where equipo_id is null and activo;

comment on column public.condiciones_comision.equipo_id is
  'NULL = condición ESTÁNDAR de Lawang: se aplica a quien cierra sin equipo vigente (22-sep-2026)';
comment on column public.condiciones_comision.proyecto_id is
  'NULL (solo en la estándar) = todos los proyectos';
comment on column public.condiciones_comision.vigente_desde is
  'Solo cuenta una venta (contrato raíz) creada en o después de esta fecha. Evita devengar ventas ya liquidadas fuera del sistema';

-- 2. El devengo estándar existe y lleva solicitud de pago (la paga Lawang).
alter table public.comisiones_devengadas
  drop constraint comisiones_devengadas_nivel_check,
  add constraint comisiones_devengadas_nivel_check
    check (nivel in ('manager', 'closer', 'estandar')),
  drop constraint comisiones_devengadas_solicitud_solo_manager,
  add constraint comisiones_devengadas_solicitud_solo_lawang
    check (solicitud_id is null or nivel in ('manager', 'estandar'));

-- 3. El motor.
create or replace function public.comisiones_evaluar_contrato(p_contrato_id uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_raiz_id              uuid;
  v_raiz_creada          date;
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
  v_equipo_id            uuid;
  v_manager_email        text;
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

  -- 1) la RAÍZ, subiendo un nivel (p_contrato_id puede ser ya la raíz o un hijo)
  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0; -- el contrato no existe
  end if;

  select c.moneda, c.proyecto_id, c.bloqueado, c.created_at::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  -- 2) precio_total de la cadena entera (raíz + hijos directos)
  select coalesce(sum(x.precio_total), 0)
    into v_precio_total
    from public.contratos x
   where x.id = v_raiz_id or x.contrato_padre_id = v_raiz_id;

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado
  );

  -- 3) precio_suelo/precio_construccion y cobrado_suelo/cobrado_obra: SIEMPRE
  --    la misma fuente que unidades_estado, sobre todas las unidades enlazadas
  --    a la raíz. Variante _interno: este motor es DEFINER y decide él quién
  --    cobra; el gate de sesión de _split es del front (22-sep-2026).
  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_interno(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  -- 4) closer de la RAÍZ y su equipo vigente HOY. Sin equipo → nivel estándar.
  select k.closer_email into v_closer_email
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0; -- sin closer atribuido: nada que devengar todavía
  end if;

  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.activo
     and em.desde <= current_date
     and (em.hasta is null or em.hasta >= current_date)
   order by em.created_at desc
   limit 1;

  if v_proyecto_id is null or v_moneda is null then
    return 0; -- sin proyecto o sin moneda: no hay sobre qué evaluar
  end if;

  if v_equipo_id is not null then
    select ev.manager_email into v_manager_email
      from public.equipos_venta ev
     where ev.id = v_equipo_id;
    v_niveles := array['manager', 'closer'];
  else
    if not public.crm_usuario_activo(v_closer_email) then
      return 0; -- el estándar solo paga a alguien activo en la intranet
    end if;
    v_niveles := array['estandar'];
  end if;

  -- 5) el recibi ancla: el más reciente que toca la cadena entera, por las DOS
  --    mismas vías que ya usa contrato_cobrado. SIN colchón de espera.
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
    return 0; -- ningún recibi vivo sostiene todavía un devengo
  end if;

  -- 6) cada nivel con su condición y sus tramos
  foreach v_nivel in array v_niveles
  loop
    if v_nivel = 'closer' then
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and c.proyecto_id = v_proyecto_id
         and c.nivel = 'closer'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and lower(c.closer_email) = lower(v_closer_email)
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and c.proyecto_id = v_proyecto_id
           and c.nivel = 'closer'
           and c.activo
           and c.vigente_desde <= v_raiz_creada
           and c.closer_email is null
         limit 1;
      end if;

    elsif v_nivel = 'estandar' then
      v_beneficiario := v_closer_email;

      -- prioridad: override de la persona en el proyecto > override global de
      -- la persona > general del proyecto > general de todos los proyectos
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
      v_beneficiario := v_manager_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and c.proyecto_id = v_proyecto_id
         and c.nivel = 'manager'
         and c.activo
         and c.vigente_desde <= v_raiz_creada
         and c.closer_email is null
       limit 1;
    end if;

    -- (cada nivel hace su propio SELECT INTO: sin fila, v_condicion queda a NULL)
    if v_condicion.id is null or v_beneficiario is null then
      continue; -- sin condición configurada (o sin manager_email): nada que devengar en este nivel
    end if;

    -- LA PRIMERA CONDICIÓN QUE DEVENGA SOBRE UNA VENTA ES LA QUE MANDA. El UNIQUE
    -- es por tramo, y un override creado DESPUÉS trae tramos nuevos: sin esto,
    -- una venta ya devengada con la general volvería a devengar entera con el
    -- override al siguiente recibí (mismo riesgo entre general y override de
    -- equipo). Los tramos pendientes de ESA misma condición siguen disparando.
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
        v_importe := v_condicion.importe_fijo * v_tramo.pct_tramo / 100;
      else
        if v_base is null then
          continue;
        end if;
        v_importe := (v_condicion.pct_comision / 100) * v_base * (v_tramo.pct_tramo / 100);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue; -- una solicitud exige importe > 0 (CHECK); un devengo a 0 no dice nada
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
          'contrato_firmado', v_contrato_firmado
        )
      )
      on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
      returning id into v_devengo_id;

      if v_devengo_id is null then
        continue; -- una sesión concurrente lo devengó primero
      end if;

      v_creados := v_creados + 1;

      -- manager y estándar: dinero de Lawang → solicitud de pago automática
      if v_nivel in ('manager', 'estandar') then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) and u.activo limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) and u.activo limit 1),
          (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1)
        );

        v_concepto := 'Comisión ' || case when v_nivel = 'manager' then 'manager' else 'estándar' end
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
$$;

comment on function public.comisiones_evaluar_contrato(uuid) is
  'Motor de comisiones (22-sep-2026): con equipo vigente evalúa manager+closer; sin equipo evalúa la condición ESTÁNDAR de Lawang (equipo_id NULL) y genera solicitud de pago. vigente_desde acota por fecha de creación de la raíz.';

revoke execute on function public.comisiones_evaluar_contrato(uuid) from public, anon, authenticated;

-- 4. La solicitud automática no la retoca su beneficiario; nadie aprueba ni
--    paga la suya. (Seguridad, revisión previa #45.)
create or replace function public._trg_solicitud_pago_transicion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.numero := old.numero;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.origen := old.origen;
  new.beneficiario_email := old.beneficiario_email;

  if old.estado = 'pendiente' then
    if new.estado = 'pendiente' then
      new.resuelto_por := null; new.resuelto_en := null;
      new.pagado_por := null;   new.pagado_en := null;
      new.pago_referencia := null; new.motivo_rechazo := null;
      new.concepto := btrim(new.concepto);
      if old.origen = 'comision_automatica' then
        -- lo calculó el motor: quien la ve (que puede ser quien la cobra) solo
        -- puede anotar; el importe, la moneda, el contrato y el concepto no
        new.contrato_id := old.contrato_id; new.concepto := old.concepto;
        new.importe := old.importe;         new.moneda := old.moneda;
      end if;
      return new;
    elsif new.estado in ('aprobada','rechazada') then
      if not public.es_admin() then
        raise exception 'solo un administrador resuelve una solicitud' using errcode = '42501';
      end if;
      if new.estado = 'aprobada' and old.beneficiario_email is not null
         and lower(old.beneficiario_email) = lower(coalesce(auth.email(), '')) then
        raise exception 'nadie aprueba una solicitud de pago a su propio nombre' using errcode = '42501';
      end if;
    elsif new.estado = 'anulada' then
      if old.creado_por is distinct from auth.uid() then
        raise exception 'solo quien creó la solicitud puede anularla' using errcode = '42501';
      end if;
    else
      raise exception 'desde pendiente solo se puede aprobar, rechazar o anular' using errcode = '22023';
    end if;
    -- al resolver, lo pedido queda congelado tal cual se pidió
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.pagado_por := null; new.pagado_en := null; new.pago_referencia := null;
    new.resuelto_por := auth.uid();
    new.resuelto_en := now();
    return new;

  elsif old.estado = 'aprobada' and new.estado = 'pagada' then
    if not public.es_admin() then
      raise exception 'solo un administrador marca una solicitud como pagada' using errcode = '42501';
    end if;
    if old.beneficiario_email is not null
       and lower(old.beneficiario_email) = lower(coalesce(auth.email(), '')) then
      raise exception 'nadie marca como pagada una solicitud a su propio nombre' using errcode = '42501';
    end if;
    -- todo lo demás, congelado como quedó al aprobar; pago_referencia es lo
    -- único que entra nuevo en esta transición
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.motivo_rechazo := old.motivo_rechazo;
    new.resuelto_por := old.resuelto_por; new.resuelto_en := old.resuelto_en;
    new.pagado_por := auth.uid();
    new.pagado_en := now();
    return new;
  end if;

  raise exception 'una solicitud % no se puede editar', old.estado using errcode = '22023';
end
$$;

-- 5. Nadie se atribuye una venta a sí mismo (salvo super_admin): con el
--    estándar, la atribución pasa de ranking a dinero.
create or replace function public.crm_contrato_closer_set(p_contrato uuid, p_email text, p_previo text default null)
returns table(contrato_id uuid, closer_email text, asignado_por text, asignado_en timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quien   text := coalesce((select auth.email()), '');
  v_destino text := nullif(btrim(coalesce(p_email, '')), '');
  v_actual  text;
  v_ahora   timestamptz := now();
begin
  if not (public.puede('ranking') or public.es_admin()) then
    raise exception 'Sin permiso para atribuir ventas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then
    raise exception 'Ese contrato no existe' using errcode = 'PT404';
  end if;
  if v_destino is not null and not public.crm_usuario_activo(v_destino) then
    raise exception 'Esa persona no esta activa en la intranet' using errcode = 'PT400';
  end if;
  if v_destino is not null and lower(v_destino) = lower(v_quien) and not public.es_super_admin() then
    raise exception 'Una venta no se la atribuye uno mismo: que lo haga otro administrador' using errcode = 'PT403';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_contrato::text, 2));

  select k.closer_email into v_actual from public.contrato_closer k where k.contrato_id = p_contrato;
  if v_actual is distinct from p_previo then
    raise exception 'La atribucion de este contrato ya no es la que tenias' using errcode = 'PT409';
  end if;

  if v_destino is null then
    delete from public.contrato_closer k where k.contrato_id = p_contrato;
  else
    update public.contrato_closer k
       set closer_email = v_destino, asignado_por = v_quien, asignado_en = v_ahora
     where k.contrato_id = p_contrato;
    if not found then
      insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
      values (p_contrato, v_destino, v_quien, v_ahora);
    end if;
  end if;

  insert into public.contrato_closer_log (contrato_id, de, a, autor)
  values (p_contrato, v_actual, v_destino, v_quien);

  return query
    select k.contrato_id, k.closer_email, k.asignado_por, k.asignado_en
      from public.contrato_closer k where k.contrato_id = p_contrato;
end;
$$;
