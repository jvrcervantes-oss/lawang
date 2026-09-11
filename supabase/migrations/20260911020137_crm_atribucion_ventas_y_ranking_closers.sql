-- CRM de leads — ATRIBUCION DE VENTAS Y RANKING DE CLOSERS. 11-sep-2026. Fase 1 de 5.
-- Revision previa: Administracion + Datos + Seguridad. Los tres tumbaron el plan original
-- y esto es lo que quedo despues de plegarlos.
--
-- POR QUE NO SE USA `contratos.creado_por`, QUE ERA EL PLAN.
-- No es el closer: es quien pulso "crear" en la intranet. Probado sobre datos reales
-- (Administracion, re-verificado despues): RP00040 lo creo jvr.cervantes y su hijo CR00019
-- lo creo sales@ -- mismo comprador, mismo negocio, dos autores. Un ranking sobre esa
-- columna mide quien usa mas la intranet.
-- Y hay un motivo peor, de Seguridad: QUIEN ES MEDIDO PUEDE EDITAR LA MEDIDA. Sobre un
-- contrato aun no bloqueado, el `with check` de la policy no protege `creado_por`, y
-- `es_suyo(NULL)` devuelve TRUE, asi que un contrato sin autor lo puede reclamar cualquiera.
-- En cuanto eso alimenta comisiones son campos retributivos sin auditoria.
--
-- QUE SE HACE EN SU LUGAR: la atribucion vive en su propia tabla, se sella a mano una vez
-- sobre el historico (decision del owner: backfill de los 51) y se registra cada cambio.
-- No se toca `contratos` -- ni una columna nueva: esa tabla ya tiene RLS por agente, tres
-- escritores distintos y una familia de incidentes con vistas que congelan columnas.
--
-- LO QUE CUENTA COMO VENTA. Solo `bloqueado = true` (asi define "firmado" este estudio;
-- `fecha_firma` esta desacreditada: 137 contratos del historico la llevan sin estar
-- firmados) y solo los que tienen `precio_total`. Eso deja fuera solo los 5 documentos que
-- no son ventas (poder notarial, hak sewa de notaria, PPJB sin precio) SIN mantener una
-- lista de tipos a mano -- en este repo una lista a mano acaba siendo el fallo.
--
-- LAS CADENAS SIGUEN SIN REGLA, Y ESO SE ENSENA EN VEZ DE DISIMULARSE. 17 de los 51 son
-- contratos hijos (una construccion colgando de su reserva). Sumando todo salen 3.402.725
-- EUR; contando solo raices, 1.850.365. Cual es la buena es una regla de NEGOCIO que el
-- owner todavia no ha fijado, asi que la funcion no elige: acepta `p_solo_raices` y ademas
-- devuelve cuantos de cada closer son encadenados, para que la distorsion se vea.
--
-- FIRMADO Y COBRADO, SIEMPRE LOS DOS (decision del owner, 11-sep). De los 3,4 M firmados
-- solo ha entrado un 4,7%, y el podio cambia: gusabellan es 3o por firmado y ULTIMO por
-- cobrado (0 EUR de 417.670). El sesgo del reparto automatico de la fase 3 ira sobre
-- cobrado; el panel ensena las dos.

-- ══════════════ 1. QUIEN CERRO CADA VENTA ══════════════
create table if not exists public.contrato_closer (
  contrato_id  uuid primary key references public.contratos(id) on delete cascade,
  closer_email text not null,
  asignado_por text not null,
  asignado_en  timestamptz not null default now()
);

create table if not exists public.contrato_closer_log (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  de          text,
  a           text,
  autor       text not null,
  cuando      timestamptz not null default now()
);
create index if not exists contrato_closer_log_por_contrato
  on public.contrato_closer_log (contrato_id, cuando desc);

alter table public.contrato_closer     enable row level security;
alter table public.contrato_closer_log enable row level security;
revoke all on public.contrato_closer     from anon, authenticated;
revoke all on public.contrato_closer_log from anon, authenticated;

-- Ni siquiera SELECT directo: todo pasa por las funciones de abajo, que deciden si a quien
-- pregunta le corresponde ver la tabla entera o solo su fila.
drop policy if exists "nadie lee la atribucion directamente" on public.contrato_closer;
drop policy if exists "nadie lee el log directamente" on public.contrato_closer_log;

-- ══════════════ 2. SELLAR QUIEN CERRO ══════════════
-- Exige `ranking`, que es permiso PROPIO y no cuelga de `leads` (Seguridad): el dia que se
-- le de el CRM a un comercial no se le regala de paso la tabla de comisiones de todos.
-- `p_previo` es el testigo: si alguien cambio la atribucion entre medias, esto falla en vez
-- de pisarla -- la misma cautela que en el dueno del lead, y aqui pesa mas porque esto
-- decide dinero.
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
  if not (public.puede('ranking') or public.es_admin()) then
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
   where (public.puede('ranking') or public.es_admin())
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
  v_todo  boolean := public.puede('ranking') or public.es_admin();
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
