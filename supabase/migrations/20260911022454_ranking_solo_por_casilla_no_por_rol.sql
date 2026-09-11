-- destructivo-ok: el unico DELETE esta DENTRO del cuerpo de `crm_contrato_closer_set`,
-- acotado por `where k.contrato_id = p_contrato` (clave primaria: una fila como mucho), y es
-- como se QUITA la atribucion de una venta cuando el desplegable se deja en «sin atribuir».
-- No es un borrado masivo ni toca datos de cliente; cada cambio queda en contrato_closer_log.
-- El cuerpo es identico al que ya estaba desplegado: lo unico que cambia es el permiso.
--
-- El ranking de closers pasa a exigir SOLO la casilla `ranking`, no el rol de admin.
-- 11-sep-2026, decision del owner.
--
-- La version anterior aceptaba `puede('ranking') or es_admin()`, y eso metia a los cuatro
-- admins en la tabla de comisiones por el hecho de ser admin — entre ellos la operadora de
-- marketing, que no tiene por que ver cuanto factura cada comercial. Y al reves: los sales
-- managers, que si gestionan ventas, se quedaban fuera hasta que alguien les marcara la
-- casilla. `puede()` ya deja pasar al super_admin por su cuenta, asi que quitar `es_admin()`
-- no deja al owner fuera de su propia herramienta.
--
-- Cambiar solo el `hidden` de la pestana NO habria servido: la pestana es cosmetica y estas
-- funciones se pueden llamar igual desde la consola. La puerta es esta.

create or replace function public.crm_contrato_closer_set(
  p_contrato uuid, p_email text, p_previo text default null
)
returns table (contrato_id uuid, closer_email text, asignado_por text, asignado_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien   text := coalesce((select auth.email()), '');
  v_destino text := nullif(btrim(coalesce(p_email, '')), '');
  v_actual  text;
  v_ahora   timestamptz := now();
begin
  if not public.puede('ranking') then
    raise exception 'Sin permiso para atribuir ventas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then
    raise exception 'Ese contrato no existe' using errcode = 'PT404';
  end if;
  if v_destino is not null and not exists (
    select 1 from public.usuarios u where lower(u.email) = lower(v_destino) and u.activo
  ) then
    raise exception 'Esa persona no esta activa en la intranet' using errcode = 'PT400';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_contrato::text, 2));

  select k.closer_email into v_actual
    from public.contrato_closer k where k.contrato_id = p_contrato;

  if v_actual is distinct from p_previo then
    raise exception 'La atribucion de este contrato ya no es la que tenias'
      using errcode = 'PT409';
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

-- ══════════════ 3. LA PANTALLA DEL BACKFILL ══════════════
-- Los 51 firmados con lo que hace falta para atribuirlos: quien los creo (como PISTA, no
-- como verdad), su comprador, su importe y si ya tienen closer. `sin_closer_primero` los
-- ordena para que la tarea se vea acabar.
create or replace function public.crm_contratos_para_atribuir(p_solo_pendientes boolean default true)
returns table (
  contrato_id uuid, numero text, tipo text, comprador text, proyecto text,
  precio_total numeric, moneda text, cobrado numeric,
  creado_por text, closer_email text, es_hijo boolean
)
language sql stable security definer set search_path to ''
as $$
  select c.id, c.numero, c.tipo, c.comprador_nombre, c.proyecto_nombre,
         c.precio_total, c.moneda,
         public.contrato_cobrado(c.id),
         c.creado_por, k.closer_email,
         c.contrato_padre_id is not null
    from public.contratos c
    left join public.contrato_closer k on k.contrato_id = c.id
   where public.puede('ranking')
     and coalesce(c.bloqueado, false)
     and c.precio_total is not null
     and (not coalesce(p_solo_pendientes, true) or k.closer_email is null)
   order by k.closer_email nulls first, c.numero;
$$;

-- ══════════════ 4. EL RANKING ══════════════
-- QUIEN VE QUE (Seguridad, y decision del estudio por ser la opcion reversible): con 8
-- comerciales agregar NO anonimiza -- ticket medio x numero devuelve el importe exacto, y
-- quien tiene un solo contrato ES ese contrato. Asi que la tabla completa la ven direccion
-- y quien tenga `ranking`; un comercial ve SU fila y SU puesto, y nada de los demas.
-- El puesto se calcula siempre sobre el conjunto entero: saber que eres el 4o no revela
-- cuanto factura el 3o.
create or replace function public.crm_ranking_closers(
  p_solo_raices boolean default false
)
returns table (
  closer_email text, closer_nombre text, puesto int,
  contratos int, encadenados int,
  firmado numeric, cobrado numeric, ticket_medio numeric,
  es_tuyo boolean
)
language plpgsql stable security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_todo  boolean := public.puede('ranking');
begin
  if not (v_todo or public.puede('leads')) then
    raise exception 'Sin permiso' using errcode = 'PT403';
  end if;

  return query
  with ventas as (
    select coalesce(k.closer_email, '(sin atribuir)') as quien,
           c.precio_total,
           public.contrato_cobrado(c.id) as cobrado,
           c.contrato_padre_id is not null as encadenado
      from public.contratos c
      left join public.contrato_closer k on k.contrato_id = c.id
     where coalesce(c.bloqueado, false)
       and c.precio_total is not null
       -- `p_solo_raices` existe porque la regla de negocio de las cadenas NO esta fijada:
       -- 17 de 51 son hijos y la diferencia entre contar todo o solo raices son 1,5 M EUR.
       -- La funcion no elige por el owner; le deja verlo de las dos maneras.
       and (not coalesce(p_solo_raices, false) or c.contrato_padre_id is null)
  ), agregado as (
    select v.quien,
           count(*)::int as contratos,
           count(*) filter (where v.encadenado)::int as encadenados,
           sum(v.precio_total) as firmado,
           sum(v.cobrado) as cobrado,
           round(avg(v.precio_total)) as ticket_medio
      from ventas v group by v.quien
  ), conpuesto as (
    select a.*,
           -- El puesto se ordena por COBRADO (decision del owner, 11-sep): de lo firmado
           -- solo ha entrado el 4,7%, y premiar la firma es premiar papel sin pagar.
           rank() over (order by a.cobrado desc, a.firmado desc)::int as puesto
      from agregado a
     where a.quien <> '(sin atribuir)'
     union all
    -- La cesta de lo no atribuido se ensena SIEMPRE y sin puesto: esconderla haria
    -- parecer que el reparto cuadra cuando no cuadra (Administracion).
    select a.*, null::int from agregado a where a.quien = '(sin atribuir)'
  )
  select p.quien,
         u.nombre,
         p.puesto, p.contratos, p.encadenados, p.firmado, p.cobrado, p.ticket_medio,
         lower(p.quien) = lower(v_quien)
    from conpuesto p
    left join public.usuarios u on lower(u.email) = lower(p.quien)
   where v_todo or lower(p.quien) = lower(v_quien)
   order by p.puesto nulls last;
end;
$$;

-- ══════════════ 5. PERMISOS ══════════════
revoke execute on function public.crm_contrato_closer_set(uuid, text, text) from public, anon;
revoke execute on function public.crm_contratos_para_atribuir(boolean) from public, anon;
revoke execute on function public.crm_ranking_closers(boolean) from public, anon;

grant execute on function public.crm_contrato_closer_set(uuid, text, text) to authenticated;
grant execute on function public.crm_contratos_para_atribuir(boolean) to authenticated;
grant execute on function public.crm_ranking_closers(boolean) to authenticated;
