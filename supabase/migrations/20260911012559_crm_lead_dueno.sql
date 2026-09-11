-- destructivo-ok: hay tres cosas que el guardarrail ve como destructivas y ninguna borra
-- informacion que alguien necesite:
--   1. `drop function if exists crm_leads()` -> se recrea acto seguido con tres columnas mas.
--      Postgres no deja cambiar el tipo de retorno con `create or replace`. Es funcion de
--      LECTURA: no guarda nada. Se vuelven a conceder sus grants al final.
--   2. `alter table lead_acceso_log drop constraint ... que_check` -> se repone MAS ANCHA
--      (anade el motivo 'contacto_ajeno'). Ensanchar un CHECK no se puede de otra forma.
--   3. El UPDATE que vacia `lead_estado.responsable` en TRES filas. APROBADO POR EL OWNER
--      el 11-sep-2026 tras ensenarle exactamente cuales: los tres son de su propia cuenta
--      (jvr.cervantes@gmail.com), del 10-sep, los tres leads movidos y devueltos a 'nuevo'
--      -- arrastres de prueba del dia que se construyo el tablero. Con la regla nueva
--      quedarian como duenos de verdad para siempre. Se limpian con su rastro en
--      `lead_dueno_log`, no en silencio.
--
-- CRM de leads — EL DUENO DEL LEAD. 11-sep-2026.
-- Revision previa: Datos + Seguridad. Los dos, por separado, propusieron la misma forma de
-- permiso (tres ramas), que es lo que mas confianza da de que es la correcta.
--
-- EL PROBLEMA QUE ARREGLA. `lead_estado.responsable` existia desde el 9-sep, pero
-- `crm_lead_mover` hacia `set responsable = v_quien` en CADA movimiento: arrastrar la
-- tarjeta de otro te transferia el lead en silencio. Con 11 agentes activos eso no es un
-- detalle, es una comision. Por eso hoy la columna no significa "quien lleva este lead"
-- sino "quien lo toco el ultimo", y por eso no se puede filtrar por ella.
--
-- LO QUE CAMBIO LA REVISION, y merece quedar escrito:
-- · Datos tumbo la idea de "el primero que lo arrastra lo reclama, si esta libre".
--   Arrastrar no es PEDIR. Esa mecanica implicita es exactamente la que fabrico el estado
--   actual, y dejarla aunque fuera solo para huerfanos la habria reproducido. La propiedad
--   se adquiere SOLO por peticion explicita. `mover` deja de escribir `responsable` nunca.
-- · El sello "quien asigno" no tenia donde vivir, y `lead_estado_log` NO vale: es un log de
--   ETAPAS (`de`/`a` son estados del embudo). Meter ahi cambios de dueno corromperia el
--   historial del kanban y cualquier calculo de tiempo en etapa. Va tabla aparte.
-- · El dueno muere con el usuario: ya hay 1 de 25 cuentas inactivas. Si no se comprueba al
--   LEER, el lead de alguien desactivado desaparece de todos los "mis leads" y nadie lo
--   puede reclamar. De ahi `dueno_activo`.

-- ══════════════ 1. DONDE VIVE EL SELLO ══════════════
alter table public.lead_estado add column if not exists asignado_por text;
alter table public.lead_estado add column if not exists asignado_en  timestamptz;

create table if not exists public.lead_dueno_log (
  id       uuid primary key default gen_random_uuid(),
  lead_id  uuid not null references public.leads(id) on delete cascade,
  de       text,
  a        text,
  autor    text not null,
  cuando   timestamptz not null default now()
);
create index if not exists lead_dueno_log_por_lead on public.lead_dueno_log (lead_id, cuando desc);

alter table public.lead_dueno_log enable row level security;
revoke all on public.lead_dueno_log from anon, authenticated;
grant select on public.lead_dueno_log to authenticated;
drop policy if exists "quien ve leads ve el historial de dueno" on public.lead_dueno_log;
create policy "quien ve leads ve el historial de dueno" on public.lead_dueno_log
  for select to authenticated using (public.puede('leads'));

-- ══════════════ 2. LIMPIAR LOS TRES DE PRUEBA ══════════════
-- Aprobado por el owner (ver la cabecera). Se deja rastro: un tablero que se limpia solo y
-- sin constancia es justo lo que esta migracion viene a impedir.
insert into public.lead_dueno_log (lead_id, de, a, autor)
  select e.lead_id, e.responsable, null, 'migracion 11-sep: arrastre de prueba, no una asignacion'
    from public.lead_estado e
   where e.responsable is not null and e.asignado_por is null;

update public.lead_estado e
   set responsable = null
 where e.responsable is not null and e.asignado_por is null;

-- ══════════════ 3. MOVER DEJA DE TOCAR AL DUENO ══════════════
-- Unico cambio respecto a la version del 9-sep: desaparece `responsable = v_quien` del
-- update y del insert. Verificado por Datos que esta es la UNICA funcion que escribia esa
-- columna, asi que con esto la salida queda cerrada entera.
create or replace function public.crm_lead_mover(
  p_lead uuid, p_estado text, p_desde timestamptz
)
returns table (lead_id uuid, estado text, estado_desde timestamptz, responsable text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien  text := coalesce((select auth.email()), '');
  v_actual text;
  v_desde  timestamptz;
  v_alta   timestamptz;
  v_ahora  timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if p_estado not in ('nuevo','contactado','visita','reserva','contrato','perdido') then
    raise exception 'Estado desconocido: %', p_estado using errcode = 'PT400';
  end if;

  select l.created_at into v_alta from public.leads l where l.id = p_lead;
  if v_alta is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  select e.estado, e.estado_desde into v_actual, v_desde
    from public.lead_estado e where e.lead_id = p_lead;
  v_actual := coalesce(v_actual, 'nuevo');
  v_desde  := coalesce(v_desde, v_alta);

  if p_desde is null or v_desde is distinct from p_desde then
    raise exception 'La tarjeta la ha movido otra persona' using errcode = 'PT409';
  end if;

  if v_actual = p_estado then
    return query select p_lead, v_actual, v_desde,
                        (select e.responsable from public.lead_estado e where e.lead_id = p_lead);
    return;
  end if;

  update public.lead_estado e
     set estado = p_estado, estado_desde = v_ahora, actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, estado_desde, actualizado)
         values (p_lead, p_estado, v_ahora, v_ahora);
  end if;

  insert into public.lead_estado_log (lead_id, de, a, autor)
       values (p_lead, v_actual, p_estado, v_quien);

  return query
    select e.lead_id, e.estado, e.estado_desde, e.responsable
      from public.lead_estado e where e.lead_id = p_lead;
end;
$$;

-- ══════════════ 4. ASIGNAR / RECLAMAR / SOLTAR ══════════════
-- TRES RAMAS, y las propusieron Datos y Seguridad por separado con las mismas fronteras:
--   · lead SIN dueno  -> lo coge cualquiera con 'leads'. Son 104 de 107: es el dia a dia,
--                        no es apropiarse de nada.
--   · el lead ES MIO  -> puedo cederlo a quien sea. Dar no es robar.
--   · lead DE OTRO    -> solo `es_admin()`. Esta es la unica rama por la que se pierde una
--                        comision, y es la unica que necesita un tercero.
-- `p_email = null` suelta el lead (lo devuelve al monton) con las mismas reglas.
-- El testigo `p_previo` es el dueno que el navegador tenia pintado: sin el, dos agentes que
-- reclaman el mismo huerfano a la vez no chocan -- gana el ultimo, y "robar" se reduce a
-- recargar mas rapido (hallazgo de Seguridad). Mismo cerrojo (semilla 0) que `mover`, para
-- que reclamar y arrastrar no se interleaven (precision de Datos).
create or replace function public.crm_lead_asignar(
  p_lead uuid, p_email text, p_previo text default null
)
returns table (lead_id uuid, responsable text, asignado_por text, asignado_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien   text := coalesce((select auth.email()), '');
  v_destino text := nullif(btrim(coalesce(p_email, '')), '');
  v_actual  text;
  v_ahora   timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  -- A quien se asigna tiene que poder VERLO. Un lead en manos de quien no abre el tablero
  -- se apaga en silencio, que es peor que dejarlo sin dueno (hallazgo de Seguridad).
  if v_destino is not null then
    if not exists (
      select 1 from public.usuarios u
       where lower(u.email) = lower(v_destino) and u.activo
         and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
    ) then
      raise exception 'Esa persona no esta activa o no tiene acceso al CRM de leads'
        using errcode = 'PT400';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  select e.responsable into v_actual from public.lead_estado e where e.lead_id = p_lead;

  if v_actual is distinct from p_previo then
    raise exception 'Este lead ya no esta como lo tenias: alguien lo ha cambiado'
      using errcode = 'PT409';
  end if;

  -- la rama del medio: quitarselo a otro solo lo hace un admin
  if v_actual is not null
     and lower(v_actual) <> lower(v_quien)
     and not public.es_admin() then
    raise exception 'Ese lead lo lleva otra persona. Solo un administrador puede reasignarlo'
      using errcode = 'PT403';
  end if;

  update public.lead_estado e
     set responsable = v_destino, asignado_por = v_quien, asignado_en = v_ahora,
         actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, estado_desde, actualizado,
                                    responsable, asignado_por, asignado_en)
         values (p_lead, 'nuevo',
                 (select l.created_at from public.leads l where l.id = p_lead),
                 v_ahora, v_destino, v_quien, v_ahora);
  end if;

  insert into public.lead_dueno_log (lead_id, de, a, autor)
       values (p_lead, v_actual, v_destino, v_quien);

  return query
    select e.lead_id, e.responsable, e.asignado_por, e.asignado_en
      from public.lead_estado e where e.lead_id = p_lead;
end;
$$;

-- ══════════════ 5. LA TAREA HEREDA AL DUENO ══════════════
-- Dos cambios sobre la version de ayer:
--   a) `p_responsable` se VALIDA contra `usuarios`. Ayer llegaba libre del navegador y se
--      guardaba tal cual -- agujero que abri yo y que caza Seguridad hoy; su hermana
--      `crm_lead_asignar_closer` si validaba desde el primer dia.
--   b) el defecto pasa a ser el DUENO del lead, y solo si no hay, el closer.
--      ⚠️ Seguridad prefería dejar el defecto en el closer y no cambiarlo sin decision
--      explicita. Se desvia a proposito y aqui queda el motivo: una tarea ("mandar el
--      dossier", "llamar") es gestion del dia a dia y le toca a quien LLEVA el lead; el
--      closer es quien hace la llamada de venta y ve su grabacion, que es otra cosa. Ademas
--      hoy `lead_closer` tiene 0 filas, asi que en la practica no mueve la agenda de nadie:
--      si algun dia hay closer distinto del dueno y molesta, se cambia una linea.
create or replace function public.crm_lead_accion_poner(
  p_lead uuid, p_que text, p_cuando date, p_responsable text default null
)
returns table (id uuid, lead_id uuid, que text, cuando date, responsable text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_que   text := btrim(coalesce(p_que, ''));
  v_resp  text := nullif(btrim(coalesce(p_responsable, '')), '');
  v_id    uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_que = '' then
    raise exception 'La accion esta vacia' using errcode = 'PT400';
  end if;
  if length(v_que) > 280 then
    raise exception 'La accion es demasiado larga' using errcode = 'PT400';
  end if;
  if p_cuando is null then
    raise exception 'Falta la fecha de la accion' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  if v_resp is not null then
    if not exists (
      select 1 from public.usuarios u
       where lower(u.email) = lower(v_resp) and u.activo
         and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
    ) then
      raise exception 'Esa persona no esta activa o no tiene acceso al CRM de leads'
        using errcode = 'PT400';
    end if;
  else
    select e.responsable into v_resp from public.lead_estado e where e.lead_id = p_lead;
    if v_resp is null then
      select lc.closer_email into v_resp from public.lead_closer lc where lc.lead_id = p_lead;
    end if;
    v_resp := coalesce(v_resp, v_quien);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 1));

  update public.lead_accion a
     set que = v_que, cuando = p_cuando, responsable = v_resp
   where a.lead_id = p_lead and a.completada_en is null
   returning a.id into v_id;

  if v_id is null then
    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por)
         values (p_lead, v_que, p_cuando, v_resp, v_quien)
      returning lead_accion.id into v_id;
  end if;

  return query
    select a.id, a.lead_id, a.que, a.cuando, a.responsable
      from public.lead_accion a where a.id = v_id;
end;
$$;

-- ══════════════ 6. PEDIR EL CONTACTO DE UN LEAD AJENO SE REGISTRA APARTE ══════════════
-- "Mis leads" es un filtro, NO un control: `crm_leads()` y `crm_lead_contacto` siguen
-- sirviendo los 107 a cualquiera con 'leads', y eso es deliberado (el equipo tiene que poder
-- cubrirse entre si). La contrapartida barata que pidio Seguridad: que quede distinguible
-- cuando alguien saca el telefono de un lead que lleva otro. Es DETECCION, no bloqueo --
-- es lo que caza copiarse un contacto y trabajarlo fuera sin tocar la tarjeta.
alter table public.lead_acceso_log drop constraint if exists lead_acceso_log_que_check;
alter table public.lead_acceso_log add constraint lead_acceso_log_que_check
  check (que = any (array['contacto'::text, 'whatsapp'::text, 'email'::text,
                          'contrato'::text, 'contacto_ajeno'::text]));

create or replace function public.crm_lead_contacto(p_lead uuid, p_que text default 'contacto')
returns table (email text, whatsapp text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_dueno text;
  v_motivo text;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso para ver contactos de leads' using errcode = 'PT403';
  end if;
  if p_que not in ('contacto','whatsapp','email','contrato') then
    raise exception 'Motivo de acceso no valido: %', p_que using errcode = 'PT400';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  select e.responsable into v_dueno from public.lead_estado e where e.lead_id = p_lead;
  -- 'contacto_ajeno' solo sustituye al motivo generico: si alguien pidio el contacto para
  -- escribir o para abrir un contrato, ese dato es mas util que el de a quien pertenecia.
  v_motivo := case
    when p_que = 'contacto' and v_dueno is not null and lower(v_dueno) <> lower(v_quien)
      then 'contacto_ajeno' else p_que end;

  insert into public.lead_acceso_log (lead_id, quien, que) values (p_lead, v_quien, v_motivo);

  return query
    select nullif(btrim(coalesce(l.email, '')), ''),
           nullif(btrim(coalesce(l.whatsapp, '')), '')
      from public.leads l
     where l.id = p_lead;
end;
$$;

-- ══════════════ 7. EL TABLERO VE AL DUENO ══════════════
drop function if exists public.crm_leads();
create function public.crm_leads()
returns table (
  id uuid, created_at timestamptz, source text, name text, campaign_id text,
  respuestas jsonb, tiene_email boolean, tiene_whatsapp boolean,
  estado text, estado_desde timestamptz, responsable text, notas bigint,
  sugerencia text, sugerencia_contrato text,
  accion_id uuid, accion_que text, accion_cuando date, accion_responsable text,
  contrato_id uuid, contrato_numero text,
  dueno text, dueno_nombre text, dueno_activo boolean
)
language sql stable security definer set search_path to ''
as $$
  select l.id,
         l.created_at,
         l.source,
         l.name,
         l.campaign_id,
         coalesce((select jsonb_object_agg(k, v)
                     from jsonb_each(coalesce(l.respuestas, '{}'::jsonb)) as r(k, v)
                    where k in ('budget_range','buy_timeline','budget','purpose')),
                  '{}'::jsonb),
         nullif(btrim(coalesce(l.email, '')), '') is not null,
         nullif(btrim(coalesce(l.whatsapp, '')), '') is not null,
         coalesce(e.estado, 'nuevo'),
         coalesce(e.estado_desde, l.created_at),
         e.responsable,
         (select count(*) from public.lead_notas n where n.lead_id = l.id),
         s.etapa,
         s.contrato_numero,
         a.id, a.que, a.cuando, a.responsable,
         v.contrato_id, v.numero,
         e.responsable,
         u.nombre,
         -- `dueno_activo` se calcula AL LEER, no al asignar: una cuenta se desactiva despues
         -- (ya hay 1 de 25), y sin esto su lead se queda invisible para todos y sin poder
         -- reclamarse. Con el flag, la pantalla lo puede sacar como "hay que reasignarlo".
         case when e.responsable is null then null else coalesce(u.activo, false) end
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join public.lead_sugerencia s on s.lead_id = l.id
    left join public.lead_accion a on a.lead_id = l.id and a.completada_en is null
    left join public.usuarios u on lower(u.email) = lower(e.responsable)
    left join lateral (
      select k.contrato_id, c.numero
        from public.lead_contrato k
        join public.contratos c on c.id = k.contrato_id
       where k.lead_id = l.id
       order by k.cuando desc
       limit 1
    ) v on true
   where public.puede('leads');
$$;

-- El hilo enseña tambien los cambios de dueno: si la propiedad puede valer una comision,
-- tiene que poder mirarse quien la tuvo y desde cuando, en el mismo sitio que todo lo demas.
create or replace function public.crm_lead_hilo(p_lead uuid)
returns table (tipo text, cuando timestamptz, autor text, texto text, extra text)
language sql stable security definer set search_path to ''
as $$
  select 'alta', l.created_at, null::text, l.source, null::text
    from public.leads l
   where l.id = p_lead and public.puede('leads')
  union all
  select 'estado', g.cuando, g.autor, g.a, g.de
    from public.lead_estado_log g
   where g.lead_id = p_lead and public.puede('leads')
  union all
  select 'nota', n.created_at, n.autor, n.texto, null::text
    from public.lead_notas n
   where n.lead_id = p_lead and public.puede('leads')
  union all
  select 'tarea', a.creada_en, a.creada_por, a.que, to_char(a.cuando, 'DD-MM-YYYY')
    from public.lead_accion a
   where a.lead_id = p_lead and public.puede('leads')
  union all
  select 'tarea_hecha', a.completada_en, a.completada_por, a.que, null::text
    from public.lead_accion a
   where a.lead_id = p_lead and a.completada_en is not null and public.puede('leads')
  union all
  select 'dueno', d.cuando, d.autor, coalesce(d.a, ''), coalesce(d.de, '')
    from public.lead_dueno_log d
   where d.lead_id = p_lead and public.puede('leads')
   order by 2 asc;
$$;

-- ══════════════ 8. PERMISOS ══════════════
revoke execute on function public.crm_leads() from public, anon;
revoke execute on function public.crm_lead_hilo(uuid) from public, anon;
revoke execute on function public.crm_lead_contacto(uuid, text) from public, anon;
revoke execute on function public.crm_lead_mover(uuid, text, timestamptz) from public, anon;
revoke execute on function public.crm_lead_asignar(uuid, text, text) from public, anon;
revoke execute on function public.crm_lead_accion_poner(uuid, text, date, text) from public, anon;

grant execute on function public.crm_leads() to authenticated;
grant execute on function public.crm_lead_hilo(uuid) to authenticated;
grant execute on function public.crm_lead_contacto(uuid, text) to authenticated;
grant execute on function public.crm_lead_mover(uuid, text, timestamptz) to authenticated;
grant execute on function public.crm_lead_asignar(uuid, text, text) to authenticated;
grant execute on function public.crm_lead_accion_poner(uuid, text, date, text) to authenticated;
