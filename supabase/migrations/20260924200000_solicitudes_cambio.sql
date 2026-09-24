-- destructivo-ok: el único DELETE va DENTRO de resolver_solicitud_cambio() y solo corre
-- cuando el owner pulsa «Aprobar» en Telegram sobre una ficha sin nada enlazado;
-- trg_guarda_antes_de_borrar copia la fila a `borrados` antes. Esta migración no borra ninguna fila.
-- ============================================================================
-- SOLICITUDES DE CAMBIO — 24-sep-2026 (encargo 20260924_lawang_solicitudes_cambio_telegram.md,
-- revisión previa #71: Seguridad + Datos + Legal)
-- ----------------------------------------------------------------------------
-- Dolor: el owner recibe a diario «no puedo editar X / necesito borrar Y» y lo hace
-- a mano. Caso del día: un sales_manager no pudo añadir el teléfono a la ficha de un
-- comprador (UPDATE de `clients` = autor o admin). Decisión del owner (24-sep): NO se
-- abren permisos — lo que hoy se bloquea se PIDE, y el owner dice Sí/No en Telegram.
--
-- Forma (y por qué):
--   · El empleado solo INSERTA lo que pide (`nuevos`) y el motivo. `antes` y
--     `ficha_nombre` los pone la BASE leyendo la fila real: si los mandara el navegador,
--     alguien podría pedir un cambio sobre la ficha de otro con un nombre inventado y el
--     owner aprobaría lo que el empleado dice, no lo que hay (Seguridad + Datos).
--   · Solo se puede pedir sobre una ficha que el que pide VE (`cliente_visible`).
--   · Nadie de la app aprueba ni edita una solicitud: sin grant de UPDATE/DELETE. Anular
--     va por RPC. Resolver solo existe para service_role (el panel del estudio, tras el
--     botón de Telegram) y es UNA función en UNA transacción: bloquea solicitud y ficha
--     (`for update`), comprueba que la ficha sigue valiendo lo que valía al pedir, aplica
--     la lista blanca y cierra. Una doble pulsación encuentra la solicitud ya resuelta.
--   · La lista blanca de columnas vive AQUÍ, no solo en el panel: con la service key
--     cualquiera se salta la RLS, así que la base es la última red.
--   · Borrar: solo si NADA cuelga de la ficha. Las FKs se leen del catálogo en cada
--     ejecución (una lista a mano es el bug del día que llega la décima tabla) — seis
--     de ellas son CASCADE y un Sí se llevaría el KYC y el soporte sin avisar. Más
--     `contratos.adq1_client_id`, que apunta a `clients` sin FK.
--   · Autoría: con service_role `auth.email()` es NULL y `borrados.quien` quedaba vacío;
--     la función sella el email con el que se registra el cambio, local a la transacción.
--   · Telegram NO lleva valores (Legal: pasaporte/domicilio de compradores no están en la
--     aceptación de LAW-76). `antes`/`nuevos` se vacían a los 90 días; quién, qué campo,
--     cuándo y el resultado se quedan (responsabilidad proactiva).
-- ============================================================================

create table public.solicitudes_cambio (
  id              uuid primary key default gen_random_uuid(),
  numero          bigint generated always as identity,          -- «SC-7»
  tabla           text not null default 'clients',
  fila_id         uuid not null,
  accion          text not null,
  nuevos          jsonb,                 -- {columna: valor pedido}; lo manda el empleado
  antes           jsonb,                 -- {columna: valor real al pedir}; lo pone la base
  ficha_nombre    text,                  -- de la fila real, nunca del navegador
  motivo          text not null,
  estado          text not null default 'pendiente',
  error           text,
  pedido_por      uuid not null default auth.uid() references public.usuarios(user_id),
  pedido_en       timestamptz not null default now(),
  resuelto_en     timestamptz,
  resuelto_via    text,
  telegram_msg_id bigint,
  avisado_en      timestamptz,
  purgado_en      timestamptz,

  constraint sc_tabla_permitida check (tabla = 'clients'),
  constraint sc_accion_valida   check (accion in ('editar','borrar')),
  constraint sc_estado_valido
    check (estado in ('pendiente','ejecutada','rechazada','fallida','anulada')),
  constraint sc_motivo_no_vacio check (btrim(motivo) <> '' and length(motivo) <= 1000)
);

comment on table public.solicitudes_cambio is
  'Cambios que el equipo pide sobre fichas que no puede tocar; el owner aprueba en Telegram y resolver_solicitud_cambio() los aplica. Encargo 20260924_lawang_solicitudes_cambio_telegram.md.';

create index solicitudes_cambio_estado_idx on public.solicitudes_cambio(estado);
create index solicitudes_cambio_pedido_por_idx on public.solicitudes_cambio(pedido_por);

alter table public.solicitudes_cambio enable row level security;

revoke all on public.solicitudes_cambio from public, anon, authenticated;
grant select on public.solicitudes_cambio to authenticated;
grant insert (tabla, fila_id, accion, nuevos, motivo) on public.solicitudes_cambio to authenticated;
grant all on public.solicitudes_cambio to service_role;

create policy "solicitudes_cambio: cada uno las suyas, admin todas"
  on public.solicitudes_cambio for select to authenticated
  using (public.es_admin() or pedido_por = (select auth.uid()));

create policy "solicitudes_cambio: el equipo pide"
  on public.solicitudes_cambio for insert to authenticated
  with check (public.es_agente() and pedido_por = (select auth.uid()));

-- ── Lista blanca: columna → cómo se normaliza. Una sola fuente, la usan alta y ejecución ──
create or replace function public._sc_columnas_clients()
returns text[]
language sql immutable
set search_path to ''
as $$
  select array['tipo','kyc_status','full_name','email','phone','nationality','passport_number',
               'idioma_comunicacion','forma_juridica','registro_num','rep_nombre','rep_cargo','notes']
$$;

-- ── Alta: el navegador solo decide QUÉ pide; el resto lo pone la base ─────────
create or replace function public._trg_solicitud_cambio_alta()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_fila  jsonb;
  v_prop  text;
  v_k     text;
  v_v     jsonb;
  v_txt   text;
  v_limpio jsonb := '{}'::jsonb;
  v_antes  jsonb := '{}'::jsonb;
begin
  new.estado := 'pendiente';
  new.pedido_por := auth.uid();
  new.pedido_en := now();
  new.error := null; new.resuelto_en := null; new.resuelto_via := null;
  new.telegram_msg_id := null; new.avisado_en := null; new.purgado_en := null;
  new.motivo := btrim(new.motivo);

  if new.tabla is distinct from 'clients' then
    raise exception 'solo se pueden pedir cambios sobre fichas de comprador' using errcode = '22023';
  end if;

  select to_jsonb(c), c.propietario into v_fila, v_prop from public.clients c where c.id = new.fila_id;
  if v_fila is null or not public.cliente_visible(v_prop, new.fila_id) then
    raise exception 'esa ficha no existe o no la puedes ver' using errcode = '42501';
  end if;
  new.ficha_nombre := v_fila->>'full_name';

  if new.accion = 'borrar' then
    new.nuevos := null;
    new.antes := null;
    return new;
  end if;

  if new.nuevos is null or jsonb_typeof(new.nuevos) <> 'object' then
    raise exception 'la solicitud no dice qué cambiar' using errcode = '22023';
  end if;

  for v_k, v_v in select * from jsonb_each(new.nuevos) loop
    if not (v_k = any(public._sc_columnas_clients())) then
      raise exception 'el campo % no se puede pedir por aquí', v_k using errcode = '22023';
    end if;
    if jsonb_typeof(v_v) not in ('string','null') then
      raise exception 'valor no válido para %', v_k using errcode = '22023';
    end if;
    v_txt := nullif(btrim(v_v #>> '{}'), '');
    if v_txt is not null and length(v_txt) > (case when v_k = 'notes' then 4000 else 300 end) then
      raise exception 'el valor de % es demasiado largo', v_k using errcode = '22023';
    end if;
    if v_k = 'full_name' then
      if v_txt is null or length(v_txt) < 2 then
        raise exception 'falta el nombre' using errcode = '22023';
      end if;
      v_txt := upper(v_txt);   -- mismo criterio que el editor: el contrato lo imprime tal cual
    elsif v_k = 'tipo' and v_txt not in ('persona','empresa') then
      raise exception 'tipo no válido' using errcode = '22023';
    elsif v_k = 'kyc_status' and v_txt not in ('pending','submitted','verified','rejected') then
      raise exception 'estado KYC no válido' using errcode = '22023';
    elsif v_k = 'idioma_comunicacion' and v_txt not in ('es','en','id') then
      raise exception 'idioma no válido' using errcode = '22023';
    end if;
    -- lo que no cambia no se pide: el owner solo ve campos que de verdad se mueven
    if (v_fila->>v_k) is distinct from v_txt then
      v_limpio := v_limpio || jsonb_build_object(v_k, v_txt);
      v_antes  := v_antes  || jsonb_build_object(v_k, v_fila->v_k);
    end if;
  end loop;

  if v_limpio = '{}'::jsonb then
    raise exception 'no hay ningún cambio respecto a la ficha actual' using errcode = '22023';
  end if;
  new.nuevos := v_limpio;
  new.antes := v_antes;
  return new;
end
$$;

create trigger trg_solicitud_cambio_alta
  before insert on public.solicitudes_cambio
  for each row execute function public._trg_solicitud_cambio_alta();

-- ── Anular: solo quien la pidió y solo mientras espera ─────────────────────────
create or replace function public.anular_solicitud_cambio(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  update public.solicitudes_cambio
     set estado = 'anulada', resuelto_en = now(), resuelto_via = 'anulada por quien la pidió'
   where id = p_id and estado = 'pendiente' and pedido_por = auth.uid();
  if not found then
    raise exception 'no hay una solicitud tuya pendiente con ese id' using errcode = '22023';
  end if;
end
$$;
revoke execute on function public.anular_solicitud_cambio(uuid) from public, anon;
grant execute on function public.anular_solicitud_cambio(uuid) to authenticated;

-- ── Qué frena un borrado: todo lo que cuelga de la ficha, leído del catálogo ───
create or replace function public._sc_referencias_cliente(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
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
  loop
    execute format('select count(*) from %s where %I = $1', r.tabla, r.col) into n using p_id;
    if n > 0 then v := v || jsonb_build_object(r.tabla, n); end if;
  end loop;
  -- sin FK, pero es el comprador principal del contrato
  select count(*) into n from public.contratos where adq1_client_id = p_id;
  if n > 0 then v := v || jsonb_build_object('contratos', n); end if;
  return v;
end
$$;
revoke execute on function public._sc_referencias_cliente(uuid) from public, anon, authenticated;

-- ── Lo que el panel necesita para componer el aviso (sin valores) ─────────────
create or replace function public.solicitudes_cambio_por_avisar()
returns table (id uuid, numero bigint, accion text, campos text[], motivo text,
               pedido_por_nombre text, ficha_iniciales text,
               contratos_borrador bigint, facturas_abiertas bigint,
               cambia_identidad boolean, referencias jsonb)
language sql
stable
security definer
set search_path to ''
as $$
  select s.id, s.numero, s.accion,
         coalesce((select array_agg(k order by k) from jsonb_object_keys(s.nuevos) k), '{}'),
         s.motivo,
         coalesce(u.nombre, u.email, 'Alguien del equipo'),
         -- iniciales, nunca el nombre: el texto sale a Telegram (Legal, LAW-76)
         (select string_agg(left(w, 1), '.') || '.'
            from regexp_split_to_table(coalesce(s.ficha_nombre, '?'), '\s+') w where w <> ''),
         (select count(*) from public.contratos c
           where c.adq1_client_id = s.fila_id and not coalesce(c.bloqueado, false)),
         (select count(*) from public.facturas f
           where f.client_id = s.fila_id and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)),
         coalesce(s.nuevos ?| array['passport_number','email'], false),
         case when s.accion = 'borrar' then public._sc_referencias_cliente(s.fila_id) end
    from public.solicitudes_cambio s
    left join public.usuarios u on u.user_id = s.pedido_por
   where s.estado = 'pendiente' and s.telegram_msg_id is null
   order by s.numero
   limit 10
$$;
revoke execute on function public.solicitudes_cambio_por_avisar() from public, anon, authenticated;
grant execute on function public.solicitudes_cambio_por_avisar() to service_role;

create or replace function public.marcar_solicitud_cambio_avisada(p_id uuid, p_msg_id bigint)
returns void
language sql
security definer
set search_path to ''
as $$
  update public.solicitudes_cambio
     set telegram_msg_id = p_msg_id, avisado_en = now()
   where id = p_id and telegram_msg_id is null
$$;
revoke execute on function public.marcar_solicitud_cambio_avisada(uuid, bigint) from public, anon, authenticated;
grant execute on function public.marcar_solicitud_cambio_avisada(uuid, bigint) to service_role;

-- ── Resolver: UNA transacción, idempotente, atada al mensaje de Telegram ───────
create or replace function public.resolver_solicitud_cambio(p_id uuid, p_msg_id bigint,
                                                            p_decision text, p_via text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  s       public.solicitudes_cambio;
  v_fila  jsonb;
  v_k     text;
  v_set   text;
  v_refs  jsonb;
  v_quien text;
begin
  if p_decision not in ('aprobar','rechazar') then
    raise exception 'decisión no válida' using errcode = '22023';
  end if;

  select * into s from public.solicitudes_cambio where id = p_id for update;
  if not found then
    return jsonb_build_object('estado', 'desconocida');
  end if;
  -- un botón de un mensaje viejo o reenviado no resuelve otra solicitud
  if s.telegram_msg_id is distinct from p_msg_id then
    raise exception 'el mensaje no corresponde a esta solicitud' using errcode = '42501';
  end if;
  if s.estado <> 'pendiente' then
    return jsonb_build_object('estado', s.estado, 'numero', s.numero, 'ya_resuelta', true, 'error', s.error);
  end if;

  if p_decision = 'rechazar' then
    update public.solicitudes_cambio
       set estado = 'rechazada', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'rechazada', 'numero', s.numero);
  end if;

  select to_jsonb(c) into v_fila from public.clients c where c.id = s.fila_id for update;
  if v_fila is null then
    update public.solicitudes_cambio
       set estado = 'fallida', error = 'la ficha ya no existe', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'fallida', 'numero', s.numero, 'error', 'la ficha ya no existe');
  end if;

  -- autoría: con service_role auth.email() es NULL; lo que se registre (borrados.quien)
  -- dice quién lo pidió y por dónde se aprobó. Local a esta transacción.
  select 'SC-' || s.numero || ' · pedido por ' || coalesce(u.email, '?') || ' · aprobado vía ' || p_via
    into v_quien from public.usuarios u where u.user_id = s.pedido_por;
  perform set_config('request.jwt.claim.email', coalesce(v_quien, 'SC-' || s.numero), true);
  perform set_config('request.jwt.claims',
                     jsonb_build_object('email', coalesce(v_quien, 'SC-' || s.numero), 'role', 'service_role')::text, true);

  if s.accion = 'borrar' then
    v_refs := public._sc_referencias_cliente(s.fila_id);
    if v_refs <> '{}'::jsonb then
      update public.solicitudes_cambio
         set estado = 'fallida', resuelto_en = now(), resuelto_via = p_via,
             error = 'no se borra: tiene cosas enlazadas ' || v_refs::text
       where id = p_id;
      return jsonb_build_object('estado', 'fallida', 'numero', s.numero, 'error', 'tiene cosas enlazadas', 'referencias', v_refs);
    end if;
    delete from public.clients where id = s.fila_id;   -- trg_guarda_antes_de_borrar deja la copia en borrados
    update public.solicitudes_cambio
       set estado = 'ejecutada', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'ejecutada', 'numero', s.numero);
  end if;

  -- editar: la ficha tiene que seguir valiendo lo que valía al pedir, si no, no se pisa
  for v_k in select jsonb_object_keys(s.antes) loop
    if (v_fila->v_k) is distinct from (s.antes->v_k) then
      update public.solicitudes_cambio
         set estado = 'fallida', resuelto_en = now(), resuelto_via = p_via,
             error = 'la ficha cambió mientras esperaba (' || v_k || '); hay que pedirlo otra vez'
       where id = p_id;
      return jsonb_build_object('estado', 'fallida', 'numero', s.numero, 'error', 'la ficha cambió mientras esperaba');
    end if;
  end loop;

  select string_agg(format('%I = ($1->>%L)', k, k), ', ')
    into v_set
    from jsonb_object_keys(s.nuevos) k
   where k = any(public._sc_columnas_clients());   -- segunda capa: la alta ya lo validó
  if v_set is null then
    raise exception 'la solicitud no tiene campos aplicables' using errcode = '22023';
  end if;
  execute format('update public.clients set %s where id = $2', v_set) using s.nuevos, s.fila_id;

  update public.solicitudes_cambio
     set estado = 'ejecutada', resuelto_en = now(), resuelto_via = p_via
   where id = p_id;
  return jsonb_build_object('estado', 'ejecutada', 'numero', s.numero);
end
$$;
revoke execute on function public.resolver_solicitud_cambio(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.resolver_solicitud_cambio(uuid, bigint, text, text) to service_role;

-- ── Campana del que lo pidió cuando se resuelve ──────────────────────────────
create or replace function public._trg_solicitud_cambio_aviso()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare v_email text;
begin
  if new.estado is distinct from old.estado and new.estado in ('ejecutada','rechazada','fallida') then
    select u.email into v_email from public.usuarios u where u.user_id = new.pedido_por;
    if v_email is not null then
      insert into public.notificaciones (tipo, titulo, detalle, destinatario, enlace)
      values ('solicitud_cambio',
              'Tu solicitud SC-' || new.numero || ' — ' ||
                case new.estado when 'ejecutada' then 'hecha'
                                when 'rechazada' then 'rechazada'
                                else 'no se pudo hacer' end,
              case when new.estado = 'fallida' then new.error
                   else coalesce(new.ficha_nombre, '') || ' · ' || new.motivo end,
              v_email,
              case when new.accion = 'editar' then '/intranet/v4/compradores/' end);
    end if;
  end if;
  return new;
exception when others then
  return new;   -- la resolución ya está hecha; un fallo del aviso no la deshace
end
$$;

create trigger trg_solicitud_cambio_aviso
  after update on public.solicitudes_cambio
  for each row execute function public._trg_solicitud_cambio_aviso();

-- ── Retención (Legal): a los 90 días se vacían los VALORES; quedan campo, quién, cuándo ──
create or replace function public.purgar_solicitudes_cambio()
returns void
language sql
security definer
set search_path to ''
as $$
  update public.solicitudes_cambio
     set antes = (select jsonb_object_agg(k, null) from jsonb_object_keys(antes) k),
         nuevos = (select jsonb_object_agg(k, null) from jsonb_object_keys(nuevos) k),
         purgado_en = now()
   where purgado_en is null
     and estado <> 'pendiente'
     and coalesce(resuelto_en, pedido_en) < now() - interval '90 days'
$$;
revoke execute on function public.purgar_solicitudes_cambio() from public, anon, authenticated;

select cron.schedule('purgar_solicitudes_cambio', '17 3 * * *', 'select public.purgar_solicitudes_cambio()');
