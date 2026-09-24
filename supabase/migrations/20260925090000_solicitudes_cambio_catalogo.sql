-- destructivo-ok: redefine resolver_solicitud_cambio(), que ya contenía el DELETE de una ficha
-- aprobada por el owner, y añade los de un documento aprobado. Esta migración no borra ninguna
-- fila: la tabla tiene 0 filas (verificado antes de aplicar) y solo cambia CHECK/GRANT/funciones.
-- ============================================================================
-- SOLICITUDES v2 — /asistente/ con catálogo de acciones (25-sep-2026)
-- Encargo 20260924_lawang_solicitudes_cambio_telegram.md (sección v2) · revisión previa #74
-- (Seguridad, Datos, Administración). Owner: «las peticiones pueden ser de mucha índole: desde
-- cambia este dato a borra esta factura o anúlame esta operación. Lo que sea debe estar en
-- /asistente/». La IA (edge `asistente-peticiones`) solo INTERPRETA; esta base decide y ejecuta.
--
-- Lo que cambia respecto a la v1 (y por qué):
--   · `accion` es un catálogo cerrado; `tabla` la deriva el trigger, nunca el navegador.
--   · Cada acción valida EN LA BASE al pedir (visibilidad con la RLS del que pide, vía la
--     policy de INSERT; precondiciones) y guarda una HUELLA de lo que el owner va a aprobar.
--     Al aprobar se recalcula: si difiere en algo → `fallida`, no se ejecuta (TOCTOU).
--   · Ejecutar = CANDADOS ESCRITOS AQUÍ, no «los de la UI por ser super_admin»: Seguridad
--     verificó que con las claims del owner `borrar_operacion` deja de parar en contratos
--     firmados o ajenos, y el DML directo de una SECURITY DEFINER se salta la policy que
--     impide borrar una factura enviada. Por eso: operación con algo firmado, recibís vivos
--     o comisión blindada → no se pide (va como «manual»); documento «enviado» por
--     CUALQUIERA de las tres señales (enviada · fecha_envio · correos_enviados) → no se borra.
--   · «Borrar» un documento solo si no está enviado, no tiene cobros aplicados ni correos y
--     es del mes en curso (Administración: si no, deja hueco en la serie de un periodo que
--     puede estar declarado — se anula). Una proforma suelta no se anula por aquí.
--   · `manual`: texto libre; aprobar solo cambia el estado («hecho»). Nunca ejecuta nada.
--   · Aprobador: fila en `aprobadores_telegram` (telegram id → usuario super_admin activo),
--     nunca una constante. Claims fijadas en la transacción y RESTAURADAS al terminar;
--     autoría `SC-n · pedido por X · aprobado por Y` + GUC `app.solicitud_cambio`.
-- ============================================================================

-- ── Tabla ──────────────────────────────────────────────────────────────────
alter table public.solicitudes_cambio drop constraint sc_tabla_permitida;
alter table public.solicitudes_cambio drop constraint sc_accion_valida;
alter table public.solicitudes_cambio alter column fila_id drop not null;
alter table public.solicitudes_cambio alter column tabla drop default;
alter table public.solicitudes_cambio alter column tabla drop not null;
alter table public.solicitudes_cambio add column texto text;
alter table public.solicitudes_cambio add column resultado jsonb;

alter table public.solicitudes_cambio add constraint sc_accion_valida check (accion in
  ('editar_comprador','borrar_comprador','anular_documento','borrar_documento','borrar_operacion','manual'));
alter table public.solicitudes_cambio add constraint sc_tabla_segun_accion check (
  (accion = 'manual' and tabla is null and fila_id is null) or
  (accion in ('editar_comprador','borrar_comprador') and tabla = 'clients' and fila_id is not null) or
  (accion in ('anular_documento','borrar_documento') and tabla = 'facturas' and fila_id is not null) or
  (accion = 'borrar_operacion' and tabla = 'contratos' and fila_id is not null));
alter table public.solicitudes_cambio add constraint sc_texto_largo check (texto is null or length(texto) <= 2000);

revoke insert on public.solicitudes_cambio from authenticated;
grant insert (fila_id, accion, nuevos, motivo, texto) on public.solicitudes_cambio to authenticated;

-- ── Aprobadores (telegram id → usuario). Sin policies: solo la base la lee ──
create table public.aprobadores_telegram (
  telegram_id bigint primary key,
  user_id     uuid not null references public.usuarios(user_id),
  creado_en   timestamptz not null default now()
);
alter table public.aprobadores_telegram enable row level security;
revoke all on public.aprobadores_telegram from public, anon, authenticated;
comment on table public.aprobadores_telegram is
  'Quién puede aprobar solicitudes_cambio por Telegram: from.id del botón → usuario. Debe ser super_admin activo (lo comprueba resolver_solicitud_cambio).';

-- ── Uso del asistente por persona y día (tope de interpretaciones) ──────────
create table public.asistente_uso (
  user_id uuid not null references public.usuarios(user_id),
  dia     date not null default (now() at time zone 'Asia/Makassar')::date,
  n       int  not null default 0,
  primary key (user_id, dia)
);
alter table public.asistente_uso enable row level security;
revoke all on public.asistente_uso from public, anon, authenticated;

create or replace function public.asistente_contar_uso(p_tope int default 40)
returns int
language plpgsql
security definer
set search_path to ''
as $$
declare v int;
begin
  if not public.es_agente() then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  insert into public.asistente_uso (user_id, dia, n)
  values (auth.uid(), (now() at time zone 'Asia/Makassar')::date, 1)
  on conflict (user_id, dia) do update set n = public.asistente_uso.n + 1
  returning n into v;
  if v > least(greatest(p_tope, 1), 40) then
    raise exception 'limite_dia' using errcode = 'P0001';
  end if;
  return v;
end
$$;
revoke execute on function public.asistente_contar_uso(int) from public, anon;
grant execute on function public.asistente_contar_uso(int) to authenticated;

-- ── Visibilidad CON LA RLS DEL QUE PIDE (invoker: se evalúa en la policy) ──
create or replace function public._sc_visible(p_tabla text, p_id uuid)
returns boolean
language sql
stable
security invoker
set search_path to ''
as $$
  select case p_tabla
    when 'clients'   then exists (select 1 from public.clients   where id = p_id)
    when 'facturas'  then exists (select 1 from public.facturas  where id = p_id)
    when 'contratos' then exists (select 1 from public.contratos where id = p_id)
    else false end
$$;
grant execute on function public._sc_visible(text, uuid) to authenticated;

drop policy "solicitudes_cambio: el equipo pide" on public.solicitudes_cambio;
create policy "solicitudes_cambio: el equipo pide lo que ve"
  on public.solicitudes_cambio for insert to authenticated
  with check (public.es_agente() and pedido_por = (select auth.uid())
              and (accion = 'manual' or public._sc_visible(tabla, fila_id)));

-- ── Huella: lo que el owner aprueba, calculado por la base (nunca por la IA) ──
create or replace function public._sc_enviado(p_factura uuid)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select coalesce(f.enviada, false) or f.fecha_envio is not null
         or exists (select 1 from public.correos_enviados ce where ce.factura_id = f.id)
    from public.facturas f where f.id = p_factura
$$;
revoke execute on function public._sc_enviado(uuid) from public, anon, authenticated;

create or replace function public._sc_mes_cerrado(p_fecha date)
returns boolean
language sql stable set search_path to ''
as $$
  -- mismo criterio que periodoFiscalTranscurrido() de la intranet: mes anterior al actual
  select p_fecha is not null
     and date_trunc('month', p_fecha) < date_trunc('month', (now() at time zone 'Asia/Makassar')::date)
$$;

create or replace function public._sc_raiz_operacion(p_contrato uuid)
returns uuid
language plpgsql stable security definer set search_path to ''
as $$
declare v uuid := p_contrato; p uuid; i int := 0;
begin
  loop
    select contrato_padre_id into p from public.contratos where id = v;
    exit when p is null or i > 10;
    v := p; i := i + 1;
  end loop;
  return v;
end
$$;
revoke execute on function public._sc_raiz_operacion(uuid) from public, anon, authenticated;

create or replace function public._sc_huella(p_accion text, p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare
  f   public.facturas;
  ids uuid[];
begin
  if p_accion in ('anular_documento','borrar_documento') then
    select * into f from public.facturas where id = p_id;
    if not found then return null; end if;
    return jsonb_build_object(
      'numero', f.numero, 'tipo', f.tipo, 'total', f.total, 'moneda', f.moneda,
      'fecha', f.fecha_emision, 'sociedad', f.sociedad, 'contrato', f.contrato_numero,
      'anulada', coalesce(f.anulada, false),
      'enviado', public._sc_enviado(f.id),
      'aplicaciones', (select count(*) from public.recibi_aplicaciones ra where ra.factura_id = f.id or ra.recibi_id = f.id),
      'mes_cerrado', public._sc_mes_cerrado(f.fecha_emision));
  elsif p_accion = 'borrar_operacion' then
    -- MISMO alcance que borrar_operacion(): el contrato y sus hijos directos
    select array_agg(c.id order by c.id) into ids
      from public.contratos c where c.id = p_id or c.contrato_padre_id = p_id;
    if ids is null then return null; end if;
    return jsonb_build_object(
      'raiz', (select numero from public.contratos where id = p_id),
      'contratos', (select jsonb_agg(jsonb_build_object('id', c.id, 'numero', c.numero, 'tipo', c.tipo,
                                                         'firmado', coalesce(c.bloqueado, false)) order by c.id)
                      from public.contratos c where c.id = any(ids)),
      'firmados', (select count(*) from public.contratos c where c.id = any(ids) and coalesce(c.bloqueado, false)),
      'recibis_vivos', (select count(*) from public.facturas x
                         where x.contrato_id = any(ids) and x.tipo = 'recibi' and not coalesce(x.anulada, false)),
      'comision_blindada', exists (
         select 1 from public.comisiones_devengadas d
           left join public.solicitudes_pago sp on sp.id = d.solicitud_id
          where d.contrato_raiz_id = any(ids)
            and (d.estado in ('pagada','en_disputa') or sp.estado in ('pagada','aprobada'))),
      'documentos', (select coalesce(jsonb_agg(jsonb_build_object(
                        'numero', x.numero, 'tipo', x.tipo, 'total', x.total, 'moneda', x.moneda,
                        'fecha', x.fecha_emision, 'sociedad', x.sociedad,
                        'mes_cerrado', public._sc_mes_cerrado(x.fecha_emision)) order by x.numero), '[]'::jsonb)
                       from public.facturas x
                      where x.contrato_id = any(ids) and not coalesce(x.anulada, false)));
  elsif p_accion = 'borrar_comprador' then
    return jsonb_build_object('referencias', public._sc_referencias_cliente(p_id));
  end if;
  return null;
end
$$;
revoke execute on function public._sc_huella(text, uuid) from public, anon, authenticated;

-- ── Alta: el navegador decide QUÉ pide; la base decide si se puede pedir ────
create or replace function public._trg_solicitud_cambio_alta()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_fila   jsonb;
  v_prop   text;
  v_k      text;
  v_v      jsonb;
  v_txt    text;
  v_limpio jsonb := '{}'::jsonb;
  v_antes  jsonb := '{}'::jsonb;
  h        jsonb;
begin
  new.estado := 'pendiente';
  new.pedido_por := auth.uid();
  new.pedido_en := now();
  new.error := null; new.resuelto_en := null; new.resuelto_via := null; new.resultado := null;
  new.telegram_msg_id := null; new.avisado_en := null; new.purgado_en := null;
  new.texto := nullif(btrim(coalesce(new.texto, '')), '');
  new.motivo := left(btrim(coalesce(nullif(btrim(coalesce(new.motivo, '')), ''), new.texto, '')), 1000);
  new.tabla := case
    when new.accion in ('editar_comprador','borrar_comprador') then 'clients'
    when new.accion in ('anular_documento','borrar_documento') then 'facturas'
    when new.accion = 'borrar_operacion' then 'contratos'
    else null end;

  if new.accion = 'manual' then
    if new.texto is null then
      raise exception 'escribe qué necesitas' using errcode = '22023';
    end if;
    new.fila_id := null; new.nuevos := null; new.antes := null; new.ficha_nombre := null;
    return new;
  end if;
  if new.fila_id is null then
    raise exception 'falta a qué ficha o documento se refiere' using errcode = '22023';
  end if;

  -- ── comprador ──
  if new.tabla = 'clients' then
    select to_jsonb(c), c.propietario into v_fila, v_prop from public.clients c where c.id = new.fila_id;
    if v_fila is null or not public.cliente_visible(v_prop, new.fila_id) then
      raise exception 'esa ficha no existe o no la puedes ver' using errcode = '42501';
    end if;
    new.ficha_nombre := v_fila->>'full_name';
    if new.accion = 'borrar_comprador' then
      new.nuevos := null;
      new.antes := public._sc_huella('borrar_comprador', new.fila_id);
      if (new.antes->'referencias') <> '{}'::jsonb then
        raise exception 'esa ficha no se puede borrar: tiene cosas enlazadas (%)', new.antes->'referencias' using errcode = '23503';
      end if;
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
        v_txt := upper(v_txt);
      elsif v_k = 'tipo' and v_txt not in ('persona','empresa') then
        raise exception 'tipo no válido' using errcode = '22023';
      elsif v_k = 'kyc_status' and v_txt not in ('pending','submitted','verified','rejected') then
        raise exception 'estado KYC no válido' using errcode = '22023';
      elsif v_k = 'idioma_comunicacion' and v_txt not in ('es','en','id') then
        raise exception 'idioma no válido' using errcode = '22023';
      end if;
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
  end if;

  new.nuevos := null;

  -- ── documento (factura / recibí / proforma) ──
  if new.tabla = 'facturas' then
    h := public._sc_huella(new.accion, new.fila_id);
    if h is null then
      raise exception 'ese documento no existe' using errcode = '22023';
    end if;
    new.ficha_nombre := (select cliente_nombre from public.facturas where id = new.fila_id);
    if (h->>'anulada')::boolean then
      raise exception 'el documento % ya está anulado', h->>'numero' using errcode = '22023';
    end if;
    if h->>'tipo' = 'proforma' then
      raise exception 'una proforma no se anula ni se borra suelta (la genera su contrato): mándalo como petición manual' using errcode = '22023';
    end if;
    if new.accion = 'borrar_documento' then
      if (h->>'enviado')::boolean then
        raise exception 'el documento % ya se envió al comprador: no se borra, se anula', h->>'numero' using errcode = '22023';
      elsif (h->>'aplicaciones')::int > 0 then
        raise exception 'el documento % tiene cobros aplicados: no se borra, se anula', h->>'numero' using errcode = '22023';
      elsif (h->>'mes_cerrado')::boolean then
        raise exception 'el documento % es de un mes ya cerrado: no se borra (dejaría un hueco en la serie), se anula', h->>'numero' using errcode = '22023';
      end if;
    end if;
    new.antes := h;
    return new;
  end if;

  -- ── operación (contrato raíz + hijos directos) ──
  new.fila_id := public._sc_raiz_operacion(new.fila_id);
  h := public._sc_huella('borrar_operacion', new.fila_id);
  if h is null then
    raise exception 'esa operación no existe' using errcode = '22023';
  end if;
  new.ficha_nombre := (select comprador_nombre from public.contratos where id = new.fila_id);
  if (h->>'firmados')::int > 0 then
    raise exception 'la operación % tiene contratos firmados: no se borra sola, mándalo como petición manual', h->>'raiz' using errcode = '22023';
  elsif (h->>'recibis_vivos')::int > 0 then
    raise exception 'la operación % tiene % recibí(s) de dinero cobrado: ¿devolución o error? mándalo como petición manual', h->>'raiz', h->>'recibis_vivos' using errcode = '22023';
  elsif (h->>'comision_blindada')::boolean then
    raise exception 'la operación % tiene una comisión pagada o aprobada: mándalo como petición manual', h->>'raiz' using errcode = '22023';
  end if;
  new.antes := h;
  return new;
end
$$;
revoke execute on function public._trg_solicitud_cambio_alta() from public, anon, authenticated;

-- ── Lo que el panel necesita para componer el aviso: SOLO datos de la base ──
drop function public.solicitudes_cambio_por_avisar();
create or replace function public.solicitudes_cambio_por_avisar()
returns table (id uuid, numero bigint, accion text, campos text[], motivo text, texto text,
               pedido_por_nombre text, ficha_iniciales text, huella jsonb,
               contratos_borrador bigint, facturas_abiertas bigint,
               cambia_identidad boolean, referencias jsonb)
language sql
stable
security definer
set search_path to ''
as $$
  select s.id, s.numero, s.accion,
         coalesce((select array_agg(k order by k) from jsonb_object_keys(s.nuevos) k), '{}'),
         s.motivo, s.texto,
         coalesce(u.nombre, u.email, 'Alguien del equipo'),
         (select string_agg(left(w, 1), '.') || '.'
            from regexp_split_to_table(coalesce(s.ficha_nombre, '?'), '\s+') w where w <> ''),
         case when s.accion = 'editar_comprador' then null else s.antes end,
         case when s.accion = 'editar_comprador' then
           (select count(*) from public.contratos c
             where c.adq1_client_id = s.fila_id and not coalesce(c.bloqueado, false)) end,
         case when s.accion = 'editar_comprador' then
           (select count(*) from public.facturas f
             where f.client_id = s.fila_id and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)) end,
         coalesce(s.nuevos ?| array['passport_number','email'], false),
         case when s.accion = 'borrar_comprador' then s.antes->'referencias' end
    from public.solicitudes_cambio s
    left join public.usuarios u on u.user_id = s.pedido_por
   where s.estado = 'pendiente' and s.telegram_msg_id is null
   order by s.numero
   limit 10
$$;
revoke execute on function public.solicitudes_cambio_por_avisar() from public, anon, authenticated;
grant execute on function public.solicitudes_cambio_por_avisar() to service_role;

-- ── Resolver: una transacción, idempotente, atada al mensaje; candados AQUÍ ──
create or replace function public.resolver_solicitud_cambio(p_id uuid, p_msg_id bigint,
                                                            p_decision text, p_via text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  s        public.solicitudes_cambio;
  v_fila   jsonb;
  v_k      text;
  v_set    text;
  v_refs   jsonb;
  v_tg     bigint;
  v_aprob  public.usuarios;
  v_pide   text;
  v_quien  text;
  v_h      jsonb;
  v_res    jsonb;
  c_claims text := current_setting('request.jwt.claims', true);
  c_sub    text := current_setting('request.jwt.claim.sub', true);
  c_email  text := current_setting('request.jwt.claim.email', true);
  c_role   text := current_setting('request.jwt.claim.role', true);
begin
  if p_decision not in ('aprobar','rechazar') then
    raise exception 'decisión no válida' using errcode = '22023';
  end if;

  select * into s from public.solicitudes_cambio where id = p_id for update;
  if not found then
    return jsonb_build_object('estado', 'desconocida');
  end if;
  if s.telegram_msg_id is distinct from p_msg_id then
    raise exception 'el mensaje no corresponde a esta solicitud' using errcode = '42501';
  end if;
  if s.estado <> 'pendiente' then
    return jsonb_build_object('estado', s.estado, 'numero', s.numero, 'ya_resuelta', true, 'error', s.error);
  end if;

  -- quién aprueba: de la base, por el telegram id del botón; super_admin activo
  v_tg := nullif(substring(coalesce(p_via, '') from '^telegram:(\d{1,20})$'), '')::bigint;
  select u.* into v_aprob
    from public.aprobadores_telegram a join public.usuarios u on u.user_id = a.user_id
   where a.telegram_id = v_tg and u.activo and u.rol = 'super_admin';
  if v_aprob.user_id is null then
    raise exception 'ese usuario de Telegram no puede aprobar' using errcode = '42501';
  end if;

  if p_decision = 'rechazar' then
    update public.solicitudes_cambio
       set estado = 'rechazada', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'rechazada', 'numero', s.numero);
  end if;

  if s.accion = 'manual' then   -- solo estado: lo hizo el owner a mano
    update public.solicitudes_cambio
       set estado = 'ejecutada', resuelto_en = now(), resuelto_via = p_via,
           resultado = jsonb_build_object('manual', true)
     where id = p_id;
    return jsonb_build_object('estado', 'ejecutada', 'numero', s.numero, 'manual', true);
  end if;

  select coalesce(u.email, '?') into v_pide from public.usuarios u where u.user_id = s.pedido_por;
  v_quien := 'SC-' || s.numero || ' · pedido por ' || coalesce(v_pide, '?') || ' · aprobado por ' || v_aprob.email || ' vía Telegram';

  begin   -- subtransacción: cualquier fallo deshace lo hecho y deja la solicitud en «fallida»
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_aprob.user_id, 'role', 'authenticated', 'email', v_quien)::text, true);
    perform set_config('request.jwt.claim.sub', v_aprob.user_id::text, true);
    perform set_config('request.jwt.claim.email', v_quien, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('app.solicitud_cambio', 'SC-' || s.numero, true);

    if s.accion = 'editar_comprador' then
      select to_jsonb(c) into v_fila from public.clients c where c.id = s.fila_id for update;
      if v_fila is null then raise exception 'la ficha ya no existe'; end if;
      for v_k in select jsonb_object_keys(s.antes) loop
        if (v_fila->v_k) is distinct from (s.antes->v_k) then
          raise exception 'la ficha cambió mientras esperaba (%); hay que pedirlo otra vez', v_k;
        end if;
      end loop;
      select string_agg(format('%I = ($1->>%L)', k, k), ', ') into v_set
        from jsonb_object_keys(s.nuevos) k where k = any(public._sc_columnas_clients());
      if v_set is null then raise exception 'la solicitud no tiene campos aplicables'; end if;
      execute format('update public.clients set %s where id = $2', v_set) using s.nuevos, s.fila_id;
      v_res := jsonb_build_object('campos', (select jsonb_agg(k) from jsonb_object_keys(s.nuevos) k));

    else
      -- el resto: la huella de ahora tiene que ser la que el owner vio
      if s.accion = 'borrar_operacion' then
        perform 1 from public.contratos where id = s.fila_id or contrato_padre_id = s.fila_id for update;
      elsif s.tabla = 'facturas' then
        perform 1 from public.facturas where id = s.fila_id for update;
      elsif s.tabla = 'clients' then
        perform 1 from public.clients where id = s.fila_id for update;
      end if;
      v_h := public._sc_huella(s.accion, s.fila_id);
      if v_h is null then raise exception 'ya no existe'; end if;
      if v_h is distinct from s.antes then
        raise exception 'cambió algo desde que se pidió (estado, documentos o contratos): hay que pedirlo otra vez';
      end if;

      if s.accion = 'borrar_comprador' then
        -- huella igual ⇒ sigue sin nada enlazado; trg_guarda_antes_de_borrar deja la copia
        delete from public.clients where id = s.fila_id;
        v_res := jsonb_build_object('borrada', true);

      elsif s.accion = 'anular_documento' then
        -- candados de la policy de UPDATE, escritos aquí: no anulada (en la huella)
        update public.facturas set anulada = true where id = s.fila_id and not coalesce(anulada, false);
        if not found then raise exception 'no se anuló nada'; end if;
        v_res := jsonb_build_object('anulado', v_h->>'numero');

      elsif s.accion = 'borrar_documento' then
        -- candados de la policy de DELETE y de Administración, escritos aquí
        if (v_h->>'enviado')::boolean or (v_h->>'aplicaciones')::int > 0
           or (v_h->>'mes_cerrado')::boolean or (v_h->>'anulada')::boolean or v_h->>'tipo' = 'proforma' then
          raise exception 'el documento ya no se puede borrar: pide anularlo';
        end if;
        delete from public.facturas where id = s.fila_id;
        if not found then raise exception 'no se borró nada'; end if;
        v_res := jsonb_build_object('borrado', v_h->>'numero');

      elsif s.accion = 'borrar_operacion' then
        -- candados que borrar_operacion() se salta para un super_admin, escritos aquí
        if (v_h->>'firmados')::int > 0 or (v_h->>'recibis_vivos')::int > 0
           or (v_h->>'comision_blindada')::boolean then
          raise exception 'la operación ya no se puede borrar sola';
        end if;
        v_res := public.borrar_operacion(s.fila_id);
      end if;
    end if;

    update public.solicitudes_cambio
       set estado = 'ejecutada', resuelto_en = now(), resuelto_via = p_via, resultado = v_res
     where id = p_id;
  exception when others then
    v_res := jsonb_build_object('error', sqlerrm);
  end;

  -- las claims de quien llamó, como estaban
  perform set_config('request.jwt.claims', coalesce(c_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(c_sub, ''), true);
  perform set_config('request.jwt.claim.email', coalesce(c_email, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(c_role, ''), true);
  perform set_config('app.solicitud_cambio', '', true);

  if v_res ? 'error' then
    update public.solicitudes_cambio
       set estado = 'fallida', error = v_res->>'error', resuelto_en = now(), resuelto_via = p_via
     where id = p_id;
    return jsonb_build_object('estado', 'fallida', 'numero', s.numero, 'error', v_res->>'error');
  end if;
  return jsonb_build_object('estado', 'ejecutada', 'numero', s.numero, 'resultado', v_res);
end
$$;
revoke execute on function public.resolver_solicitud_cambio(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.resolver_solicitud_cambio(uuid, bigint, text, text) to service_role;

-- ── Campana del que lo pidió ───────────────────────────────────────────────
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
              'Tu petición SC-' || new.numero || ' — ' ||
                case new.estado when 'ejecutada' then 'hecha'
                                when 'rechazada' then 'rechazada'
                                else 'no se pudo hacer' end,
              case when new.estado = 'fallida' then new.error else left(new.motivo, 300) end,
              v_email, '/intranet/v4/asistente/');
    end if;
  end if;
  return new;
exception when others then
  return new;
end
$$;
revoke execute on function public._trg_solicitud_cambio_aviso() from public, anon, authenticated;

-- ── Retención: también el texto libre y el motivo (Datos + Legal) ──────────
create or replace function public.purgar_solicitudes_cambio()
returns void
language sql
security definer
set search_path to ''
as $$
  update public.solicitudes_cambio
     set antes = case when accion = 'editar_comprador'
                      then (select jsonb_object_agg(k, null) from jsonb_object_keys(antes) k) end,
         nuevos = (select jsonb_object_agg(k, null) from jsonb_object_keys(nuevos) k),
         texto = null,
         motivo = '(purgado a los 90 días)',
         ficha_nombre = null,
         purgado_en = now()
   where purgado_en is null
     and estado <> 'pendiente'
     and coalesce(resuelto_en, pedido_en) < now() - interval '90 days';
  delete from public.asistente_uso where dia < (now() at time zone 'Asia/Makassar')::date - 30;
$$;
revoke execute on function public.purgar_solicitudes_cambio() from public, anon, authenticated;
