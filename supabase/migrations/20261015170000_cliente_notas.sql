-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Notas en la ficha del cliente (owner, 15-oct-2026: «crea un apartado de notas en la ficha del cliente»).
-- Hasta hoy: un único texto `clients.notes` que se pisaba al editar (sin autor, sin fecha); 4 de 228 fichas lo usaban.
-- Ahora: un historial de notas por cliente, con autor (por id) y fecha que pone el servidor. Calco del patrón de leads
-- (lead_notas + lead_notas_retiradas), con lo que pidió la revisión previa #366 (Backend, Seguridad, Legal):
--  · RETIRAR BORRA el texto (Legal/Seguridad: ocultarlo no cumple una rectificación ni una supresión, UU PDP art. 30/43);
--    queda una traza sin texto en cliente_notas_retiradas (quién, cuándo, motivo de lista cerrada), de solo añadir.
--  · Nadie edita una nota: se retira y se escribe otra. La tabla solo deja borrar desde las dos funciones de aquí.
--  · LEER: cliente_notas_datos, DEFINER con dueño lw_lector (patrón LAW-338): la policy de cliente_notas exige ver la
--    ficha por la RLS de clients, así que la regla es la MISMA que la de la ficha por construcción, no una copia.
--  · ESCRIBIR: cliente_nota_agrega; puede quien ve la ficha completa (decisión por defecto del CEO: hoy `notes` solo lo
--    editaban admin y dueño antes de la firma; una nota solo se añade y lleva autor, así que la puerta se abre a quien ve
--    la ficha — managers, admin de empresa y el dueño también tras la firma. Revertir: endurecer la comprobación en agrega).
--  · RETIRAR: su autor mientras vea la ficha, un admin global o el admin de la empresa del cliente (Seguridad, opción a).
--  · TODOS los que escribían `clients.notes` (cliente_guarda, _cliente_crea, crm_lead_ficha_crear, solicitudes de cambio,
--    asistente de peticiones) quedan cerrados de una vez con un disparador: lo que llegue a esa columna pasa al historial
--    como nota (origen 'campo_notas', autor = quien llama) y la columna se queda vacía. No hay dos sitios con el mismo texto.
--  · Borrar una ficha (borrar_comprador, resolver_solicitud_cambio: las dos hacen delete from clients) borra sus notas y
--    deja la traza con motivo 'ficha_borrada' (Legal: viven y mueren con la ficha). La clave ajena es diferible (no
--    cascade): el borrado lo hace el disparador con traza, nunca en silencio.
--  · Retención KYC: una nota NO bloquea la retención del pasaporte (Backend: _sc_referencias_cliente la contaba como
--    referencia para siempre); cuenta como actividad (la fecha de la última nota retrasa el corte, como un documento).
--  · Las 4 notas de `clients.notes` pasan al historial con origen 'antigua', SIN autor y con la fecha de HOY (no se inventa
--    la del alta: Legal/Backend, exactitud). Un admin de Lawang las repasa una vez por si llevan datos sensibles.
-- destructivo-ok: vacía `clients.notes` SOLO después de copiar cada texto al historial en la misma transacción (4 filas
--   medidas el 15-oct); el resto solo crea tablas, funciones y disparadores nuevos y reemplaza _kyc_retencion_candidato.
-- REVERTIR: supabase/reversion_cliente_notas/REVERSION.sql (devuelve cada nota 'antigua'/'campo_notas' a clients.notes
--   antes de borrar las tablas, y repone _kyc_retencion_candidato literal).
set local lock_timeout = '5s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public._kyc_retencion_candidato(uuid,timestamptz)'::regprocedure) <> '206cb44b7784b6142164499c62b9696d' then
    raise exception '_kyc_retencion_candidato viva no es la del 15-oct (md5 206cb44b…): alguien la cambió después; revisar a mano';
  end if;
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public._sc_referencias_cliente(uuid)'::regprocedure) <> '6c0b820ddfaa73c8ac166a892e048627' then
    raise exception '_sc_referencias_cliente viva no es la del 15-oct (md5 6c0b820d…): alguien la cambió después; revisar a mano';
  end if;
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public._sc_columnas_clients()'::regprocedure) <> '76cb573a409cda72958757444ba0dcc5' then
    raise exception '_sc_columnas_clients viva no es la del 15-oct (md5 76cb573a…): alguien la cambió después; revisar a mano';
  end if;
  if exists (select 1 from public.solicitudes_cambio s where s.estado = 'pendiente' and s.nuevos ? 'notes') then
    raise exception 'hay solicitudes de cambio pendientes que tocan notes: resolverlas antes (sus notas no pasarían)';
  end if;
  if to_regclass('public.cliente_notas') is not null then
    raise exception 'cliente_notas ya existe: esta migración ya se aplicó';
  end if;
end $pre$;

-- ── 1. tablas ─────────────────────────────────────────────────────────────────────────────────────────────────────
create table public.cliente_notas (
  id        bigint generated always as identity primary key,
  -- diferible: el disparador de clients (abajo) crea la nota en el BEFORE INSERT de una ficha que aún no está escrita
  client_id uuid not null references public.clients(id) deferrable initially deferred,
  texto     text not null check (char_length(btrim(texto)) between 1 and 4000),
  autor_id  uuid references public.usuarios(user_id),
  origen    text not null default 'nota' check (origen in ('nota', 'campo_notas', 'antigua')),
  creado_en timestamptz not null default now(),
  constraint cliente_notas_nota_con_autor check (origen <> 'nota' or autor_id is not null)
);
create index cliente_notas_client_idx on public.cliente_notas (client_id, creado_en desc);
create index cliente_notas_autor_idx  on public.cliente_notas (autor_id);

create table public.cliente_notas_retiradas (
  id              bigint generated always as identity primary key,
  cuando          timestamptz not null default now(),
  nota_id         bigint not null,   -- sin-fk-ok: la nota se borra al retirarla; la traza guarda su id (como lead_notas_retiradas)
  client_id       uuid not null,     -- sin-fk-ok: la ficha puede borrarse y la traza se queda (como lead_notas_retiradas)
  autor_id        uuid references public.usuarios(user_id),
  retirada_por_id uuid references public.usuarios(user_id),   -- null: la borró un proceso sin sesión (edge con service_role)
  motivo          text not null check (motivo in ('dato_sensible', 'rectificacion', 'oposicion', 'autoridad', 'otro', 'ficha_borrada'))
);
create index cliente_notas_retiradas_client_idx on public.cliente_notas_retiradas (client_id);
create index cliente_notas_retiradas_autor_idx  on public.cliente_notas_retiradas (autor_id);
create index cliente_notas_retiradas_por_idx    on public.cliente_notas_retiradas (retirada_por_id);

alter table public.cliente_notas           enable row level security;
alter table public.cliente_notas_retiradas enable row level security;
revoke all on public.cliente_notas, public.cliente_notas_retiradas from public, anon, authenticated, service_role, lw_lector;
revoke all on sequence public.cliente_notas_id_seq, public.cliente_notas_retiradas_id_seq from public, anon, authenticated, service_role, lw_lector;
-- solo lee lw_lector, y solo las notas de las fichas que la RLS de clients le deja ver a quien llama (patrón LAW-338)
grant select on public.cliente_notas to lw_lector;
create policy "notas: las de las fichas que ves" on public.cliente_notas for select to lw_lector
  using (exists (select 1 from public.clients c where c.id = cliente_notas.client_id));

-- inmutables: ni UPDATE ni DELETE ni TRUNCATE, salvo el borrado de las dos funciones de aquí (marca local de la transacción)
create function public._cliente_notas_inmutable() returns trigger
language plpgsql set search_path = '' as $f$
begin
  if tg_op = 'DELETE' and coalesce(current_setting('cliente_notas.borra', true), '') = 'on' then
    return old;
  end if;
  raise exception '% no se edita ni se borra a mano: una nota se retira (cliente_nota_retira)', tg_table_name using errcode = '42501';
end $f$;
revoke all on function public._cliente_notas_inmutable() from public, anon, authenticated, service_role;
create trigger trg_cliente_notas_inmutable before update or delete on public.cliente_notas
  for each row execute function public._cliente_notas_inmutable();
create trigger trg_cliente_notas_no_truncate before truncate on public.cliente_notas
  for each statement execute function public._cliente_notas_inmutable();

create function public._cliente_notas_retiradas_solo_anade() returns trigger
language plpgsql set search_path = '' as $f$
begin
  raise exception 'cliente_notas_retiradas es de solo añadir' using errcode = '42501';
end $f$;
revoke all on function public._cliente_notas_retiradas_solo_anade() from public, anon, authenticated, service_role;
create trigger trg_cliente_notas_retiradas_solo_anade before update or delete on public.cliente_notas_retiradas
  for each row execute function public._cliente_notas_retiradas_solo_anade();
create trigger trg_cliente_notas_retiradas_no_truncate before truncate on public.cliente_notas_retiradas
  for each statement execute function public._cliente_notas_retiradas_solo_anade();

-- ── 2. ¿ve quien llama la ficha completa? La MISMA regla que la policy SELECT de clients (dueño lw_lector) ──────────────
create function public._cliente_ficha_ve(p_client uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from public.clients c where c.id = p_client)
$f$;
grant create on schema public to lw_lector;
alter function public._cliente_ficha_ve(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public._cliente_ficha_ve(uuid) from public, anon, authenticated, service_role;

-- ── 3. leer: las notas de una ficha (llamador: intranet/v4 ficha del cliente) ─────────────────────────────────────────
create function public.cliente_notas_datos(p_client uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'cliente_notas_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'texto', x.texto, 'origen', x.origen, 'creado_en', x.creado_en,
                                               'autor_id', x.autor_id, 'autor_email', x.autor_email)
                            order by x.rn) filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
    into v, n
    from (select cn.id, cn.texto, cn.origen, cn.creado_en, cn.autor_id, u.email as autor_email,
                 row_number() over (order by cn.creado_en desc, cn.id desc) as rn
            from public.cliente_notas cn
            left join public.usuarios u on u.user_id = cn.autor_id
           where cn.client_id = p_client
           order by cn.creado_en desc, cn.id desc limit 501) x;
  return jsonb_build_object('notas', v, 'recortado', n > 500);
end $$;
grant create on schema public to lw_lector;
alter function public.cliente_notas_datos(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.cliente_notas_datos(uuid) from public, anon, service_role;
grant execute on function public.cliente_notas_datos(uuid) to authenticated;

-- ── 4. escribir: añadir (llamador: intranet/v4 ficha del cliente) ──────────────────────────────────────────────────
create function public.cliente_nota_agrega(p_client uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := public.uid_sesion();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id    bigint;
  v_en    timestamptz;
begin
  if v_uid is null or not public.es_agente()
     or not exists (select 1 from public.usuarios u where u.user_id = v_uid and u.activo) then
    raise exception 'Sin permiso para escribir notas' using errcode = '42501';
  end if;
  if p_client is null or not public._cliente_ficha_ve(p_client) then
    raise exception 'Esa ficha no existe o no la puedes ver' using errcode = '42501';
  end if;
  if v_texto = '' then
    raise exception 'La nota está vacía' using errcode = '22023';
  end if;
  if char_length(v_texto) > 4000 then
    raise exception 'La nota pasa de 4000 caracteres' using errcode = '22023';
  end if;
  if (select count(*) from public.cliente_notas n where n.autor_id = v_uid and n.creado_en > now() - interval '10 minutes') >= 30 then
    raise exception 'Demasiadas notas seguidas: espera unos minutos' using errcode = '54000';
  end if;
  insert into public.cliente_notas (client_id, texto, autor_id, origen)
       values (p_client, v_texto, v_uid, 'nota')
    returning id, creado_en into v_id, v_en;
  return jsonb_build_object('id', v_id, 'creado_en', v_en);
end $$;
revoke all on function public.cliente_nota_agrega(uuid, text) from public, anon, service_role;
grant execute on function public.cliente_nota_agrega(uuid, text) to authenticated;

-- ── 5. escribir: retirar = BORRAR el texto + traza sin texto (llamador: intranet/v4 ficha del cliente) ──────────────
create function public.cliente_nota_retira(p_nota bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.uid_sesion();
  v_n   public.cliente_notas;
begin
  if v_uid is null or not public.es_agente() then
    raise exception 'Sin permiso para retirar notas' using errcode = '42501';
  end if;
  if p_motivo is null or p_motivo not in ('dato_sensible', 'rectificacion', 'oposicion', 'autoridad', 'otro') then
    raise exception 'Motivo no válido' using errcode = '22023';
  end if;
  select * into v_n from public.cliente_notas n where n.id = p_nota for update;
  -- «no existe» y «no ves su ficha» dicen lo mismo: los ids son correlativos y no se pueden sondear
  if not found or not public._cliente_ficha_ve(v_n.client_id) then
    raise exception 'Esa nota no existe' using errcode = 'P0002';
  end if;
  -- coalesce: con autor_id nulo (notas antiguas, o las que entran sin sesión) «null = v_uid» es NULL y «if not NULL» no
  -- lanzaba: cualquier agente que viera la ficha la borraba (revisor de código, 15-oct)
  if not (coalesce(v_n.autor_id = v_uid, false) or public.es_admin() or public.admin_de_cliente(v_n.client_id, true)) then
    raise exception 'Solo su autor o un administrador puede retirar esta nota' using errcode = '42501';
  end if;
  perform set_config('cliente_notas.borra', 'on', true);
  delete from public.cliente_notas where id = v_n.id;
  perform set_config('cliente_notas.borra', '', true);
  insert into public.cliente_notas_retiradas (nota_id, client_id, autor_id, retirada_por_id, motivo)
       values (v_n.id, v_n.client_id, v_n.autor_id,
               (select u.user_id from public.usuarios u where u.user_id = v_uid), p_motivo);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cliente_nota_retira(bigint, text) from public, anon, service_role;
grant execute on function public.cliente_nota_retira(bigint, text) to authenticated;

-- ── 6. las 4 notas antiguas pasan al historial, ANTES del disparador de clients ──────────────────────────────────
insert into public.cliente_notas (client_id, texto, autor_id, origen)
select c.id, left(btrim(c.notes), 4000), null, 'antigua'
  from public.clients c
 where nullif(btrim(coalesce(c.notes, '')), '') is not null;
update public.clients set notes = null where notes is not null;

-- ── 7. todo lo que escriba en clients.notes pasa al historial (cierra a TODOS los escritores de una vez) ─────────────
create function public._clients_notas_a_historial() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare
  v_t   text := nullif(btrim(coalesce(new.notes, '')), '');
  v_uid uuid := public.uid_sesion();
begin
  if v_t is not null and (tg_op = 'INSERT' or new.notes is distinct from old.notes) then
    -- como cliente_nota_agrega: de más se rechaza, no se recorta en silencio (Base de datos, 15-oct)
    if char_length(v_t) > 4000 then
      raise exception 'La nota es demasiado larga (máximo 4000 caracteres).' using errcode = '22023';
    end if;
    -- el mismo tope que cliente_nota_agrega: cliente_guarda y el alta aún aceptan la clave notes (Seguridad, 15-oct)
    if v_uid is not null and (select count(*) from public.cliente_notas n
                               where n.autor_id = v_uid and n.creado_en > now() - interval '10 minutes') >= 30 then
      raise exception 'Demasiadas notas seguidas: espera unos minutos' using errcode = '54000';
    end if;
    insert into public.cliente_notas (client_id, texto, autor_id, origen)
         values (new.id, v_t, (select u.user_id from public.usuarios u where u.user_id = v_uid), 'campo_notas');
  end if;
  new.notes := null;
  return new;
end $f$;
revoke all on function public._clients_notas_a_historial() from public, anon, authenticated, service_role;
create trigger trg_clients_notas_a_historial before insert or update of notes on public.clients
  for each row execute function public._clients_notas_a_historial();

-- ── 8. borrar una ficha borra sus notas, con traza (borrar_comprador y resolver_solicitud_cambio) ─────────────────
create function public._clients_notas_al_borrar() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_uid uuid := public.uid_sesion();
begin
  insert into public.cliente_notas_retiradas (nota_id, client_id, autor_id, retirada_por_id, motivo)
  select n.id, n.client_id, n.autor_id, (select u.user_id from public.usuarios u where u.user_id = v_uid), 'ficha_borrada'
    from public.cliente_notas n where n.client_id = old.id;
  perform set_config('cliente_notas.borra', 'on', true);
  delete from public.cliente_notas where client_id = old.id;
  perform set_config('cliente_notas.borra', '', true);
  return old;
end $f$;
revoke all on function public._clients_notas_al_borrar() from public, anon, authenticated, service_role;
create trigger trg_clients_notas_al_borrar before delete on public.clients
  for each row execute function public._clients_notas_al_borrar();

-- ── 8a. las solicitudes de cambio ya no llevan notas (Seguridad, 15-oct) ──────────────────────────────────────────
-- Una nota que entraba por una solicitud dejaba su texto en solicitudes_cambio.nuevos (y en el aviso) hasta la purga de
-- 90 días: retirarla no la borraba del todo. Las notas se escriben solo en el apartado Notas (cliente_nota_agrega). La edge
-- asistente-peticiones deja de ofrecer el campo en el mismo aterrizaje. Cuerpo anterior literal en la REVERSION.
create or replace function public._sc_columnas_clients()
 returns text[]
 language sql
 immutable
 set search_path to ''
as $function$
  select array['tipo','kyc_status','full_name','email','phone','nationality','passport_number',
               'idioma_comunicacion','forma_juridica','registro_num','rep_nombre','rep_cargo']
$function$;

-- ── 8b. pedir borrar la ficha: sus notas no son «cosas enlazadas» (revisor de código, 15-oct) ──────────────────────
-- _sc_referencias_cliente cuenta TODO lo que apunta a clients leyendo el catálogo: con cliente_notas dentro,
-- _trg_solicitud_cambio_alta rechazaba con 23503 pedir el borrado de cualquier ficha con nota, y una nota añadida mientras la
-- solicitud espera cambiaba la huella (resolver_solicitud_cambio: «cambió algo»). Las notas se borran con la ficha y dejan
-- traza (trg_clients_notas_al_borrar), así que no frenan nada. Cuerpo anterior literal en la REVERSION.
create or replace function public._sc_referencias_cliente(p_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  r record;
  n bigint;
  v jsonb := '{}'::jsonb;
begin
  for r in
    select c.conrelid::regclass::text as tabla, a.attname as col
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
     where c.contype = 'f' and c.confrelid = 'public.clients'::regclass
       and c.conrelid is distinct from to_regclass('public.cliente_notas')   -- 15-oct: se borran con la ficha, con traza
  loop
    execute format('select count(*) from %s where %I = $1', r.tabla, r.col) into n using p_id;
    if n > 0 then v := v || jsonb_build_object(r.tabla, n); end if;
  end loop;
  select count(*) into n from public.contratos where adq1_client_id = p_id;
  if n > 0 then v := v || jsonb_build_object('contratos', n); end if;
  return v;
end
$function$;

-- ── 9. retención KYC: una nota es actividad, no un bloqueo para siempre ──────────────────────────────────────────
create or replace function public._kyc_retencion_candidato(p_id uuid, p_corte timestamptz)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_ult timestamptz;
begin
  if not exists (select 1 from public.documents d where d.client_id = p_id and d.retirado_el is null
                   and d.doc_type in ('passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'other')) then
    return false;
  end if;
  if exists (select 1 from public.documents d where d.client_id = p_id
               and (d.doc_type = 'signed_contract' or d.contrato_id is not null or d.reservation_id is not null)) then
    return false;
  end if;
  select greatest(c.created_at, c.kyc_verificado_el,
                  (select max(d.uploaded_at) from public.documents d where d.client_id = c.id),
                  (select max(cd.corregido_en) from public.correcciones_datos cd where cd.tabla = 'clients' and cd.fila_id = c.id),
                  (select max(n.creado_en) from public.cliente_notas n
                    where n.client_id = c.id and n.origen <> 'antigua'))   -- 15-oct: una nota es actividad; pasarlas hoy al historial, no
    into v_ult from public.clients c where c.id = p_id;
  if v_ult is null or v_ult >= p_corte then return false; end if;
  -- 15-oct: las notas tampoco bloquean (antes, una clave ajena nueva hacia clients dejaba la ficha fuera de la retención para siempre)
  return (public._sc_referencias_cliente(p_id) - 'public.documents' - 'public.cliente_notas') = '{}'::jsonb;
end $function$;
