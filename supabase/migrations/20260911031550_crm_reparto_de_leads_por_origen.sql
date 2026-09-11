-- destructivo-ok: dos avisos del guardarrail, ninguno destruye nada.
--   1. "UPDATE sin WHERE" es el `on conflict ... do update` de `crm_reparto_origen_set`, que
--      por definicion afecta a UNA fila (la que colisiona con la clave primaria). Es el falso
--      positivo ya registrado como EST-32 en pendientes.
--   2. "DELETE de filas" es `delete from reparto_closer where source = ... and closer_email = ...`,
--      acotado por la clave primaria compuesta: quita a UN closer de UN origen, que es como se
--      desmarca una casilla en el panel. Queda su fila en `reparto_log` con motivo
--      'config_baja'. Ninguna tabla existente se toca: las tres se crean aqui mismo.
--
-- CRM de leads — REPARTO AUTOMATICO POR ORIGEN. 11-sep-2026. Fase 3.
-- Revision previa: Datos + Seguridad. Los dos tumbaron cosas del plan; esto es lo que queda.
--
-- ⚠️ NACE INERTE, Y ESO ES CORRECTO. Datos midio que hoy solo 2 de los 24 usuarios activos
-- tienen 'leads', y que SEIS de los siete closers con ventas atribuidas no son elegibles.
-- Con eso el reparto caeria sobre una o dos personas. El owner reparte las casillas a mano
-- cuando lo tenga hablado con su equipo; hasta entonces esto no asigna a nadie y lo dice en
-- el registro (motivo 'sin_candidatos'), en vez de repartir mal en silencio.
--
-- LA CLAVE ES EL ORIGEN, NO LA CAMPANA. Medido: de los 5 origenes, el QR del aeropuerto (31
-- leads) y la web (1) NO tienen `campaign_id` ninguno. Con la campana como clave, 32 de 108
-- leads se quedarian fuera del reparto. `source` los cubre todos.
--
-- LA CUOTA NO SE CONFIGURA, SE DERIVA DEL RANKING. El #1 por dinero cobrado se lleva 2 por
-- cada 1 de los demas. Asi se ajusta sola cuando cambia el ranking y no hay una lista mas
-- que mantener. Y no es una cascada: en una cascada pura, con 2 leads/dia el primero se lo
-- lleva TODO y nadie mas genera datos nunca (el owner ya habia descartado eso al elegir
-- "capacidad con sesgo al que rinde", pero su propuesta de tope+salto acababa ahi).
--
-- ⚠️ EL MOTOR DE ESTE FICHERO SE SUSTITUYO EL MISMO DIA por 20260911031659: llamaba por
-- dentro a `crm_ranking_closers()`, que revalida permiso, y eso lo hacia reventar cuando lo
-- llamaba R13 (service_role, sin sesion). Ver el porque en ese fichero. Lo de aqui se deja
-- tal cual se aplico, no se reescribe: el historial es lo que paso, no lo que deberia.

-- ============== 1. CONFIGURACION ==============
create table if not exists public.reparto_origen (
  source             text primary key,
  activo             boolean not null default false,
  tope_sin_contactar int not null default 4,
  -- CADUCIDAD (hallazgo de Datos): sin esto el tope se atasca EN SILENCIO. Hoy los 108 leads
  -- estan en 'nuevo' y nadie ha sacado ninguno nunca; con tope 4 y sin caducidad, en tres
  -- dias todos los closers estarian llenos y todo caeria a "sin dueno" sin que nadie
  -- entendiera por que. Un lead parado mas de N dias deja de ocupar hueco.
  dias_caducidad     int not null default 7,
  actualizado_por    text,
  actualizado_en     timestamptz not null default now(),
  constraint reparto_tope_sano check (tope_sin_contactar between 1 and 50),
  constraint reparto_dias_sano check (dias_caducidad between 1 and 90)
);

create table if not exists public.reparto_closer (
  source       text not null,
  closer_email text not null,
  anadido_por  text not null,
  anadido_en   timestamptz not null default now(),
  primary key (source, closer_email)
);

-- Fila inmutable por reparto (Seguridad): una comision disputada dentro de seis meses no se
-- reconstruye con los logs de hoy, porque `cobrado` cambia solo y la config no tenia
-- historial. Aqui queda congelado el instante: quienes se consideraron, su cuota y su puesto
-- ENTONCES, a quien se eligio y por que se descarto a cada uno de los demas.
create table if not exists public.reparto_log (
  id        uuid primary key default gen_random_uuid(),
  lead_id   uuid references public.leads(id) on delete set null,
  source    text,
  elegido   text,
  motivo    text not null,
  autor     text not null,
  cuando    timestamptz not null default now(),
  detalle   jsonb not null default '{}'::jsonb
);
create index if not exists reparto_log_por_lead on public.reparto_log (lead_id, cuando desc);

alter table public.reparto_origen enable row level security;
alter table public.reparto_closer enable row level security;
alter table public.reparto_log    enable row level security;
revoke all on public.reparto_origen from anon, authenticated;
revoke all on public.reparto_closer from anon, authenticated;
revoke all on public.reparto_log    from anon, authenticated;

-- ============== 2. CONFIGURAR (permiso propio `reparto`) ==============
-- POR QUE `reparto` Y NO `ranking` (Seguridad). Quien tiene `ranking` edita `contrato_closer`,
-- o sea mueve a quien se atribuye cada venta, o sea mueve el ranking por cobrado, o sea mueve
-- su PROPIA cuota. Si ademas configurase quien entra en cada origen, cerraria el circulo:
-- decidiria que el #1 es el y que el #1 se lleva el doble. Dos llaves distintas.
create or replace function public.crm_reparto_origen_set(
  p_source text, p_activo boolean, p_tope int default null, p_dias int default null
)
returns table (source text, activo boolean, tope_sin_contactar int, dias_caducidad int)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_src   text := nullif(btrim(coalesce(p_source, '')), '');
begin
  if not public.puede('reparto') then
    raise exception 'Sin permiso para configurar el reparto' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_src is null then
    raise exception 'Falta el origen' using errcode = 'PT400';
  end if;

  insert into public.reparto_origen (source, activo, tope_sin_contactar, dias_caducidad,
                                     actualizado_por, actualizado_en)
       values (v_src, coalesce(p_activo, false), coalesce(p_tope, 4), coalesce(p_dias, 7),
               v_quien, now())
  on conflict on constraint reparto_origen_pkey do update
     set activo = coalesce(p_activo, public.reparto_origen.activo),
         tope_sin_contactar = coalesce(p_tope, public.reparto_origen.tope_sin_contactar),
         dias_caducidad = coalesce(p_dias, public.reparto_origen.dias_caducidad),
         actualizado_por = v_quien, actualizado_en = now();

  insert into public.reparto_log (lead_id, source, elegido, motivo, autor, detalle)
       values (null, v_src, null, 'config_origen', v_quien,
               jsonb_build_object('activo', p_activo, 'tope', p_tope, 'dias', p_dias));

  return query select o.source, o.activo, o.tope_sin_contactar, o.dias_caducidad
    from public.reparto_origen o where o.source = v_src;
end;
$$;

-- NADIE SE CONFIGURA A SI MISMO (Seguridad). Un manager que ademas cierra podria meterse en
-- los origenes que mejor convierten. La regla va aqui y no en la pantalla: una pantalla se
-- salta con la consola del navegador.
create or replace function public.crm_reparto_closer_set(
  p_source text, p_email text, p_incluir boolean
)
returns table (source text, closer_email text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_src   text := nullif(btrim(coalesce(p_source, '')), '');
  v_mail  text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  if not public.puede('reparto') then
    raise exception 'Sin permiso para configurar el reparto' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_src is null or v_mail is null then
    raise exception 'Falta el origen o la persona' using errcode = 'PT400';
  end if;
  if v_mail = lower(v_quien) and not public.es_super_admin() then
    raise exception 'No puedes anadirte a ti mismo a un origen: que lo haga otra persona'
      using errcode = 'PT403';
  end if;
  if coalesce(p_incluir, false) and not exists (
    select 1 from public.usuarios u where lower(u.email) = v_mail and u.activo
      and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
  ) then
    raise exception 'Esa persona no esta activa o no tiene acceso al CRM de leads'
      using errcode = 'PT400';
  end if;

  if coalesce(p_incluir, false) then
    insert into public.reparto_closer (source, closer_email, anadido_por)
         values (v_src, v_mail, v_quien)
    on conflict on constraint reparto_closer_pkey do nothing;
  else
    delete from public.reparto_closer k where k.source = v_src and k.closer_email = v_mail;
  end if;

  insert into public.reparto_log (lead_id, source, elegido, motivo, autor, detalle)
       values (null, v_src, v_mail,
               case when coalesce(p_incluir,false) then 'config_alta' else 'config_baja' end,
               v_quien, '{}'::jsonb);

  return query select k.source, k.closer_email
    from public.reparto_closer k where k.source = v_src order by k.closer_email;
end;
$$;

-- ============== 3. LO QUE VE EL PANEL ==============
-- Los origenes salen de los leads REALES y no de una tabla de catalogo: `source` es texto
-- libre, asi que una campana nueva estrena origen sin que nadie lo de de alta. Sacandolos de
-- los propios leads, un origen nuevo aparece solo en la pantalla como "sin configurar" en vez
-- de tragarse los leads en silencio (hallazgo de Datos).
create or replace function public.crm_reparto_config()
returns table (
  source text, leads_totales bigint, leads_sin_dueno bigint,
  activo boolean, tope_sin_contactar int, dias_caducidad int,
  closers text[]
)
language sql stable security definer set search_path to ''
as $$
  select l.source,
         count(*),
         count(*) filter (where e.responsable is null),
         coalesce(o.activo, false),
         coalesce(o.tope_sin_contactar, 4),
         coalesce(o.dias_caducidad, 7),
         coalesce((select array_agg(k.closer_email order by k.closer_email)
                     from public.reparto_closer k where k.source = l.source), '{}')
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join public.reparto_origen o on o.source = l.source
   where public.puede('reparto')
   group by l.source, o.activo, o.tope_sin_contactar, o.dias_caducidad
   order by count(*) desc;
$$;

-- ============== 4. EL MOTOR (sustituido por 20260911031659) ==============
-- Esta primera version llamaba a `crm_ranking_closers()` desde dentro y por eso reventaba
-- con R13. Se deja aqui por fidelidad historica; la version viva esta en la migracion
-- siguiente. Solo se conserva el `grant`, que no cambia.

-- ============== 5. PERMISOS ==============
revoke execute on function public.crm_reparto_origen_set(text, boolean, int, int) from public, anon;
revoke execute on function public.crm_reparto_closer_set(text, text, boolean) from public, anon;
revoke execute on function public.crm_reparto_config() from public, anon;

grant execute on function public.crm_reparto_origen_set(text, boolean, int, int) to authenticated;
grant execute on function public.crm_reparto_closer_set(text, text, boolean) to authenticated;
grant execute on function public.crm_reparto_config() to authenticated;
