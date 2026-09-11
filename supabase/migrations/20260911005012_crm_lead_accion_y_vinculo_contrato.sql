-- destructivo-ok: los tres DROP de este fichero son de DEFINICION, no de datos, y los tres se
-- reconstruyen dentro de la misma transaccion, unas lineas mas abajo:
--   1. `alter table lead_acceso_log drop constraint lead_acceso_log_que_check` -> se vuelve a
--      poner ACTO SEGUIDO mas ancha (anade el motivo 'contrato' a los tres que ya admitia).
--      Ensanchar un CHECK no se puede hacer de otra forma en Postgres. Cero filas tocadas.
--   2. `drop policy if exists` sobre lead_accion y lead_contrato -> son las dos tablas que
--      esta misma migracion acaba de crear; el `if exists` esta solo para que la migracion se
--      pueda repetir sin reventar. No hay ni una fila que proteger todavia.
--   3. `drop function if exists crm_leads()` -> se recrea inmediatamente con dos columnas mas.
--      Postgres NO deja cambiar el tipo de retorno con `create or replace`, asi que no hay
--      alternativa. Es una funcion de LECTURA: no guarda nada que se pueda perder. Lo unico
--      que se cae con ella son sus grants, y por eso se vuelven a conceder al final.
-- No hace falta backup de datos porque ninguna fila de ninguna tabla se modifica ni se borra
-- aqui. Verificado antes de aplicar: lead_accion y lead_contrato no existian todavia.
--
-- CRM de leads — proximo paso con fecha y vinculo explicito con el contrato. 11-sep-2026.
-- Revision previa: Seguridad + Datos + Desarrollo. Los hallazgos van plegados aqui abajo,
-- cada uno junto a la linea que lo aplica.
--
-- 1. PROXIMO PASO EN TABLA PROPIA, nunca una columna en `leads`: esa tabla la mantiene R13
--    cada 4 h y el mismo motivo llevo el estado y las notas a tablas aparte el 9-sep.
--    ⚠️ Matiz que corrigio Datos y conviene no perder: R13 hace `on_conflict=meta_lead_id`
--    SIN mandar `id` y sin borrar, asi que `leads.id` es estable y una clave ajena aguanta
--    las pasadas. El peligro real no es R13, es el `on delete cascade` el dia que se fusionen
--    los 7 duplicados que hay hoy: se llevaria por delante estado, notas y estas acciones.
--    Se deja la cascada (es lo correcto al borrar un lead de verdad) y queda dicho que la
--    fusion tendra que MOVER estas filas al superviviente antes de borrar.
--
-- 2. UNA SOLA ACCION VIVA POR LEAD, y la unicidad se impone en la BASE (indice parcial), no
--    en la pantalla: dos comerciales con permiso pueden crear dos a la vez y la vista "hoy"
--    los duplicaria. El alta se resuelve dentro de la funcion y no con `on conflict`, porque
--    un indice `unique ... where` no vale como arbitro de `on conflict` (42P10, ya mordio).
--
-- 3. LA FECHA ES `date` Y "HOY" ES HORA DE BALI. El equipo vive en WITA (UTC+8). Con un
--    instante en UTC, "vencidas + hoy" mentiria ocho horas al dia. Hallazgo de Datos.
--
-- 4. VINCULO LEAD -> CONTRATO EN TABLA PUENTE, no en una columna de `contratos`: la policy de
--    escritura de `contratos` exige `bloqueado = false` y los contratos que interesan aqui son
--    justo los FIRMADOS, asi que sellar por columna no daria error -- tocaria cero filas y se
--    perderia en silencio (hallazgo de Datos). La tabla puente admite ademas que un lead acabe
--    con varios contratos encadenados (reserva -> construccion), que una columna no admite.
--
-- 5. LA HEURISTICA DEL EMAIL PASA A SUPLENTE, EN SUS DOS COPIAS. Estaba escrita dos veces
--    -- dentro de `crm_leads()` y en la vista `lead_sugerencia` que consume `lead_tablero` --
--    y adivina cruzando el email del lead con los identificadores del contrato. Falla en los
--    dos sentidos: quien firma con otro correo se queda en "Nuevo" para siempre (caso PT PMA,
--    LAW-133) y hoy hay 4 leads distintos cruzando con el MISMO contrato porque son duplicados.
--    Se alinean LAS DOS aqui: si hay vinculo explicito, la heuristica calla. Tocar solo una
--    dejaria tres verdades conviviendo.
--
-- 6. NADA ESCRIBE POR POLICY. Las dos tablas nuevas nacen con RLS y con una unica policy de
--    SELECT tras `puede('leads')`; toda escritura pasa por funciones `crm_*` SECURITY DEFINER
--    con `search_path` vacio, igual que `lead_estado`. En Supabase una tabla recien creada
--    llega con los grants a `anon`/`authenticated` puestos: se revocan explicitamente.

-- ═══════════════════════════════ 1. PROXIMO PASO ═══════════════════════════════
create table if not exists public.lead_accion (
  id             uuid primary key default gen_random_uuid(),
  lead_id        uuid not null references public.leads(id) on delete cascade,
  que            text not null,
  cuando         date not null,
  responsable    text not null,
  creada_por     text not null,
  creada_en      timestamptz not null default now(),
  completada_en  timestamptz,
  completada_por text,
  constraint lead_accion_que_no_vacio check (btrim(que) <> ''),
  constraint lead_accion_que_cabe     check (length(que) <= 280)
);

create unique index if not exists lead_accion_una_viva
  on public.lead_accion (lead_id) where completada_en is null;
create index if not exists lead_accion_agenda
  on public.lead_accion (cuando) where completada_en is null;

alter table public.lead_accion enable row level security;
revoke all on public.lead_accion from anon, authenticated;
grant select on public.lead_accion to authenticated;

drop policy if exists "quien ve leads ve sus acciones" on public.lead_accion;
create policy "quien ve leads ve sus acciones" on public.lead_accion
  for select to authenticated using (public.puede('leads'));

-- ═══════════════════════════════ 2. VINCULO ═══════════════════════════════
-- Clave primaria compuesta: un lead puede acabar en varios contratos (reserva y luego
-- construccion) y un contrato puede venir de mas de un lead duplicado. Lo que no puede
-- haber es la misma pareja dos veces.
create table if not exists public.lead_contrato (
  lead_id     uuid not null references public.leads(id) on delete cascade,
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  origen      text not null default 'crm',
  quien       text not null,
  cuando      timestamptz not null default now(),
  primary key (lead_id, contrato_id)
);
create index if not exists lead_contrato_por_contrato on public.lead_contrato (contrato_id);

alter table public.lead_contrato enable row level security;
revoke all on public.lead_contrato from anon, authenticated;
grant select on public.lead_contrato to authenticated;

drop policy if exists "quien ve leads ve el vinculo" on public.lead_contrato;
create policy "quien ve leads ve el vinculo" on public.lead_contrato
  for select to authenticated using (public.puede('leads'));

-- ═════════════════ 3. EL MOTIVO DE ACCESO 'contrato' ═════════════════
-- La lista de motivos estaba en DOS sitios (la validacion de `crm_lead_contacto` y este
-- CHECK). Se amplian los dos: abrir el editor de contratos desde un lead entrega su nombre
-- y su contacto, y eso tiene que dejar el mismo rastro que pulsar "Ver contacto".
alter table public.lead_acceso_log drop constraint if exists lead_acceso_log_que_check;
alter table public.lead_acceso_log add constraint lead_acceso_log_que_check
  check (que = any (array['contacto'::text, 'whatsapp'::text, 'email'::text, 'contrato'::text]));

-- ═════════════════ 4. FUNCIONES DEL PROXIMO PASO ═════════════════
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

  -- Por defecto la tarea es del closer asignado; si no hay, de quien la escribe.
  if v_resp is null then
    select lc.closer_email into v_resp from public.lead_closer lc where lc.lead_id = p_lead;
    v_resp := coalesce(v_resp, v_quien);
  end if;

  -- Cerrojo de aviso por lead: dos comerciales que guardan a la vez se serializan en vez
  -- de chocar contra el indice parcial. Semilla distinta a la de `crm_lead_mover` para que
  -- mover una tarjeta y ponerle tarea no se bloqueen entre si.
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

create or replace function public.crm_lead_accion_completar(p_accion uuid)
returns table (id uuid, lead_id uuid, completada_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  return query
    update public.lead_accion a
       set completada_en = now(), completada_por = v_quien
     where a.id = p_accion and a.completada_en is null
    returning a.id, a.lead_id, a.completada_en;
end;
$$;

-- Lo que toca hoy: vencidas y de hoy, en hora de Bali. `p_solo_mias` deja al comercial
-- ver su propia lista sin perder la del equipo, que es lo que mira quien coordina.
create or replace function public.crm_agenda(p_solo_mias boolean default false)
returns table (
  accion_id uuid, lead_id uuid, nombre text, source text,
  que text, cuando date, responsable text, dias_de_retraso int
)
language sql stable security definer set search_path to ''
as $$
  select a.id, a.lead_id, l.name, l.source, a.que, a.cuando, a.responsable,
         ((now() at time zone 'Asia/Makassar')::date - a.cuando)::int
    from public.lead_accion a
    join public.leads l on l.id = a.lead_id
   where public.puede('leads')
     and a.completada_en is null
     and a.cuando <= (now() at time zone 'Asia/Makassar')::date
     and (not coalesce(p_solo_mias, false) or a.responsable = (select auth.email()))
   order by a.cuando asc;
$$;

-- ═════════════════ 5. FUNCIONES DEL VINCULO ═════════════════
-- Lo que necesita el dialogo de "crear contrato": los datos que el propio lead escribio en
-- el formulario, si ya existe una ficha con ese correo, y cuantas otras tarjetas son la misma
-- persona. Deja rastro, como cualquier otra entrega de contacto de esta herramienta.
create or replace function public.crm_lead_para_contrato(p_lead uuid)
returns table (
  nombre text, email text, whatsapp text,
  ficha_existente uuid, ficha_existente_nombre text, otros_leads_igual int
)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_email text;
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

  insert into public.lead_acceso_log (lead_id, quien, que) values (p_lead, v_quien, 'contrato');

  select lower(btrim(coalesce(l.email, ''))) into v_email from public.leads l where l.id = p_lead;

  return query
    select l.name,
           nullif(btrim(coalesce(l.email, '')), ''),
           nullif(btrim(coalesce(l.whatsapp, '')), ''),
           f.id,
           f.full_name,
           (select count(*)::int from public.leads o
             where o.id <> l.id and v_email <> ''
               and lower(btrim(coalesce(o.email, ''))) = v_email)
      from public.leads l
      left join public.clients f
        on v_email <> '' and lower(f.email) = v_email and f.tipo = 'persona'
     where l.id = p_lead;
end;
$$;

-- Crea la ficha de comprador a partir del lead. El alta la confirma una persona desde el CRM
-- (decision del owner, 11-sep-2026) y por eso existe esta puerta: el muro de `contracts/app.html`
-- impide guardar un contrato cuyo comprador no tenga ficha, y el trigger que las crea corre
-- DESPUES de guardar -- sin esto el comercial rellenaria un contrato inguardable.
-- No teclea nadie: los datos son los que la propia persona escribio en el formulario, que es
-- justo lo que el muro del 18-ago venia a proteger (erratas al copiar a mano).
create or replace function public.crm_lead_ficha_crear(p_lead uuid)
returns table (client_id uuid, ya_existia boolean)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_nombre text; v_email text; v_tel text;
  v_id uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  select btrim(coalesce(l.name, '')),
         nullif(lower(btrim(coalesce(l.email, ''))), ''),
         nullif(btrim(coalesce(l.whatsapp, '')), '')
    into v_nombre, v_email, v_tel
    from public.leads l where l.id = p_lead;

  if v_nombre is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;
  if v_nombre = '' then
    raise exception 'Ese lead no tiene nombre: no se puede abrir una ficha sin nombre' using errcode = 'PT400';
  end if;
  if v_email is null then
    raise exception 'Ese lead no dejo email: la ficha necesita un identificador' using errcode = 'PT400';
  end if;

  -- Si ya hay ficha con ese correo, se devuelve esa. Nunca se crea una segunda: el indice
  -- unico (lower(email), tipo) lo impediria de todos modos, y el error crudo de Postgres es
  -- justo lo que se llevo por delante las altas de familias que comparten correo.
  select c.id into v_id from public.clients c
   where c.email is not null and lower(c.email) = v_email and c.tipo = 'persona';
  if v_id is not null then
    return query select v_id, true;
    return;
  end if;

  insert into public.clients (full_name, email, phone, tipo, kyc_status, propietario, notes)
       values (upper(v_nombre), v_email, v_tel, 'persona', 'pending', v_quien,
               'Ficha abierta desde el CRM de leads el ' || to_char(now(), 'DD-MM-YYYY'))
    returning clients.id into v_id;

  return query select v_id, false;
end;
$$;

-- El sello lo pone el servidor. Si el `lead_id` viajara en el payload de guardar el contrato
-- seria un parametro del navegador: atribucion falsificable y sin rastro (hallazgo Seguridad).
create or replace function public.crm_lead_contrato_sellar(p_lead uuid, p_contrato uuid)
returns table (lead_id uuid, contrato_id uuid, cuando timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
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
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then
    raise exception 'Ese contrato no existe' using errcode = 'PT404';
  end if;

  insert into public.lead_contrato (lead_id, contrato_id, origen, quien)
       values (p_lead, p_contrato, 'crm', v_quien)
  on conflict (lead_id, contrato_id) do nothing;

  return query
    select k.lead_id, k.contrato_id, k.cuando
      from public.lead_contrato k
     where k.lead_id = p_lead and k.contrato_id = p_contrato;
end;
$$;

-- ═════════════════ 6. LA HEURISTICA, SUPLENTE EN SUS DOS COPIAS ═════════════════
create or replace view public.lead_sugerencia
with (security_invoker = on) as
  select l.id as lead_id,
         case when bool_or(e.etapa = 'contrato') then 'contrato'
              when bool_or(e.etapa = 'reserva')  then 'reserva' end as etapa,
         min(c.numero) as contrato_numero
    from public.leads l
    join public.contratos c on coalesce(c.bloqueado, false) = true
    join lateral unnest(public.contrato_identificadores(c.datos)) ident(ident) on true
    join public.contrato_tipo_etapa e on e.tipo = c.tipo and e.etapa <> 'ninguna'
   where nullif(btrim(l.email), '') is not null
     and lower(btrim(ident.ident)) = lower(btrim(l.email))
     -- suplente: en cuanto hay vinculo explicito, esta adivinanza se calla
     and not exists (select 1 from public.lead_contrato k where k.lead_id = l.id)
   group by l.id;

-- `crm_leads()` gana columnas (la accion viva y el vinculo real), y eso obliga a recrearla:
-- Postgres no deja cambiar el tipo de retorno con `create or replace`. Se vuelven a conceder
-- los permisos justo debajo, que es lo que se pierde al recrearla.
drop function if exists public.crm_leads();
create function public.crm_leads()
returns table (
  id uuid, created_at timestamptz, source text, name text, campaign_id text,
  respuestas jsonb, tiene_email boolean, tiene_whatsapp boolean,
  estado text, estado_desde timestamptz, responsable text, notas bigint,
  sugerencia text, sugerencia_contrato text,
  accion_id uuid, accion_que text, accion_cuando date, accion_responsable text,
  contrato_id uuid, contrato_numero text
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
         v.contrato_id, v.numero
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join public.lead_sugerencia s on s.lead_id = l.id
    left join public.lead_accion a on a.lead_id = l.id and a.completada_en is null
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

-- El hilo del lead enseña tambien las tareas: ponerlas y cumplirlas es actividad, y si no
-- sale aqui nadie sabe que se hizo ni cuando.
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
   order by 2 asc;
$$;

-- `crm_lead_contacto` acepta tambien el motivo nuevo (la otra mitad de la lista que estaba
-- duplicada: la validacion de la funcion y el CHECK de la tabla).
create or replace function public.crm_lead_contacto(p_lead uuid, p_que text default 'contacto')
returns table (email text, whatsapp text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
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

  insert into public.lead_acceso_log (lead_id, quien, que) values (p_lead, v_quien, p_que);

  return query
    select nullif(btrim(coalesce(l.email, '')), ''),
           nullif(btrim(coalesce(l.whatsapp, '')), '')
      from public.leads l
     where l.id = p_lead;
end;
$$;

-- ═════════════════ 7. PERMISOS ═════════════════
revoke execute on function public.crm_leads() from public, anon;
revoke execute on function public.crm_lead_hilo(uuid) from public, anon;
revoke execute on function public.crm_lead_contacto(uuid, text) from public, anon;
revoke execute on function public.crm_lead_accion_poner(uuid, text, date, text) from public, anon;
revoke execute on function public.crm_lead_accion_completar(uuid) from public, anon;
revoke execute on function public.crm_agenda(boolean) from public, anon;
revoke execute on function public.crm_lead_para_contrato(uuid) from public, anon;
revoke execute on function public.crm_lead_ficha_crear(uuid) from public, anon;
revoke execute on function public.crm_lead_contrato_sellar(uuid, uuid) from public, anon;

grant execute on function public.crm_leads() to authenticated;
grant execute on function public.crm_lead_hilo(uuid) to authenticated;
grant execute on function public.crm_lead_contacto(uuid, text) to authenticated;
grant execute on function public.crm_lead_accion_poner(uuid, text, date, text) to authenticated;
grant execute on function public.crm_lead_accion_completar(uuid) to authenticated;
grant execute on function public.crm_agenda(boolean) to authenticated;
grant execute on function public.crm_lead_para_contrato(uuid) to authenticated;
grant execute on function public.crm_lead_ficha_crear(uuid) to authenticated;
grant execute on function public.crm_lead_contrato_sellar(uuid, uuid) to authenticated;
