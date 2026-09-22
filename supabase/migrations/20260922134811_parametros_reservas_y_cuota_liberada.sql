-- ════════════════════════════════════════════════════════════════════════════
-- PARÁMETROS DE RESERVAS CONFIGURABLES · DESCUENTO CON CARTA LIBERADA · RECÁLCULO
-- 22-sep-2026 (segunda tanda del mismo encargo; owner: «¿en el panel de control
-- podemos controlar los días de gracia, los datos de las prórrogas, los techos,
-- todo lo que sea configurable?» y «la cuota se retiene pero se puede imputar a
-- otra unidad, no se devuelve»)
-- ════════════════════════════════════════════════════════════════════════════
-- 1. `parametros`: la prueba de la suite («¿puede el cliente cambiar de opinión
--    sin llamarnos?») dice que días de gracia, nº de prórrogas y techos de días
--    son datos de la BASE, no constantes. Una tabla clave→valor con su rango,
--    lectura para el equipo, escritura solo super admin vía parametro_set().
--    prorroga_reserva() y la edge los leen en cada llamada.
-- 2. El descuento del Bloqueo cuenta también la Carta LIBERADA del mismo
--    comprador (misma parcela o no): la cuota «se retiene y se imputa». Hoy
--    RP00198 (C1, Bonian) nació sin descontar los 1.000 de CR00060 porque el
--    cron la había liberado a las 04:00 y ya no ocupaba la parcela.
-- 3. carta_cobrado_recalcula(): un admin puede volver a calcular el abono en un
--    Bloqueo en borrador (sin firma) — la única salida para el caso anterior sin
--    borrar y rehacer el contrato.
-- destructivo-ok: los drop policy/trigger if exists + create son el idiom
-- idempotente del repo; no se borra ningún dato.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Parámetros ───────────────────────────────────────────────────────────
create table if not exists public.parametros (
  clave           text primary key,
  valor           jsonb not null,
  etiqueta        text not null,
  ayuda           text,
  minimo          numeric,
  maximo          numeric,
  grupo           text not null default 'reservas',
  orden           int  not null default 100,
  actualizado_en  timestamptz not null default now(),
  actualizado_por text
);
comment on table public.parametros is
  'Ajustes de la intranet que el owner cambia sin tocar código (22-sep-2026). Escribe solo parametro_set() (super admin); leen prorroga_reserva(), la edge libera-reservas-vencidas y /intranet/v4/ajustes/.';
alter table public.parametros enable row level security;
revoke all on public.parametros from public, anon, authenticated;
grant select on public.parametros to authenticated;
drop policy if exists parametros_select on public.parametros;
create policy parametros_select on public.parametros for select to authenticated using (public.es_agente());

insert into public.parametros (clave, valor, etiqueta, ayuda, minimo, maximo, orden) values
  ('reservas.dias_gracia', '3', 'Días de gracia al vencer una reserva',
   'El día que vence, aviso a managers; la parcela se libera sola pasados estos días si nadie prorroga o libera. 0 = se libera el mismo día.', 0, 30, 10),
  ('reservas.aviso_dias_antes', '1', 'Aviso previo (días antes del vencimiento)',
   'Cuántos días antes de vencer se avisa a los managers. 0 = sin aviso previo.', 0, 15, 20),
  ('reservas.prorrogas_max_manager', '2', 'Prórrogas que puede dar un sales manager',
   'Por Carta de Reserva. A partir de ahí, solo un admin.', 0, 10, 30),
  ('reservas.prorroga_dias_max_manager', '30', 'Días máximos por prórroga (sales manager)', null, 1, 365, 40),
  ('reservas.prorroga_dias_max_admin', '180', 'Días máximos por prórroga (admin)', null, 1, 730, 50),
  ('reservas.prorroga_dias_defecto', '15', 'Días propuestos al prorrogar',
   'Lo que trae el formulario de prórroga antes de tocarlo.', 1, 365, 60)
on conflict (clave) do nothing;

create or replace function public.parametro(p_clave text)
returns jsonb language sql stable security definer set search_path to '' as $$
  select valor from public.parametros where clave = p_clave
$$;
revoke execute on function public.parametro(text) from public, anon;
grant execute on function public.parametro(text) to authenticated, service_role;

create or replace function public.parametro_num(p_clave text, p_defecto numeric)
returns numeric language plpgsql stable security definer set search_path to '' as $$
declare v jsonb; n numeric;
begin
  select valor into v from public.parametros where clave = p_clave;
  if v is null or jsonb_typeof(v) <> 'number' then return p_defecto; end if;
  n := (v#>>'{}')::numeric;
  return n;
end $$;
revoke execute on function public.parametro_num(text, numeric) from public, anon, authenticated;
grant execute on function public.parametro_num(text, numeric) to service_role;

create or replace function public.parametro_set(p_clave text, p_valor jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r public.parametros%rowtype; n numeric;
begin
  if not public.es_super_admin() then
    raise exception 'Cambiar un ajuste exige super admin.' using errcode = '42501';
  end if;
  select * into r from public.parametros where clave = p_clave;
  if r.clave is null then raise exception 'Ajuste desconocido: %', p_clave using errcode = 'P0002'; end if;
  if jsonb_typeof(r.valor) = 'number' then
    if jsonb_typeof(p_valor) <> 'number' then
      raise exception '«%» es un número.', r.etiqueta using errcode = '22023';
    end if;
    n := (p_valor#>>'{}')::numeric;
    if n <> trunc(n) then raise exception '«%» es un número entero.', r.etiqueta using errcode = '22023'; end if;
    if (r.minimo is not null and n < r.minimo) or (r.maximo is not null and n > r.maximo) then
      raise exception '«%» va de % a %.', r.etiqueta, r.minimo, r.maximo using errcode = '22023';
    end if;
  end if;
  update public.parametros
     set valor = p_valor, actualizado_en = now(),
         actualizado_por = coalesce(public._quien_actua(), (select auth.uid())::text)
   where clave = p_clave;
  return p_valor;
end $$;
revoke all on function public.parametro_set(text, jsonb) from public, anon;
grant execute on function public.parametro_set(text, jsonb) to authenticated;

-- ── 2. prorroga_reserva lee los topes de `parametros` ───────────────────────
create or replace function public.prorroga_reserva(
  p_contrato_id uuid, p_dias int, p_motivo text, p_comunicado boolean default false
)
returns date
language plpgsql security definer set search_path to '' as $$
declare
  c          public.contratos%rowtype;
  v_n        int;
  v_desde    date;
  v_hasta    date;
  v_quien    text;
  v_es_admin boolean;
  v_es_sm    boolean;
  v_max_n    int := public.parametro_num('reservas.prorrogas_max_manager', 2)::int;
  v_max_dias int;
begin
  if p_motivo is null or length(btrim(p_motivo)) < 6 then
    raise exception 'Prorrogar exige un motivo (para el histórico del contrato).' using errcode = '23514';
  end if;
  select * into c from public.contratos where id = p_contrato_id;
  if c.id is null then raise exception 'Contrato no encontrado.' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.contrato_tipo_etapa e
                  where e.tipo = c.tipo and e.etapa = 'reserva' and e.tipo <> 'reserva_parcela') then
    raise exception 'Solo se prorroga una Carta de Reserva.' using errcode = '22023';
  end if;
  if c.liberado_en is not null then
    raise exception 'La reserva ya está liberada; no se puede prorrogar.' using errcode = '22023';
  end if;

  v_es_admin := public.es_admin();
  v_es_sm := exists (select 1 from public.usuarios uu
                      where uu.user_id = (select auth.uid()) and uu.activo and uu.rol = 'sales_manager')
             and public.es_manager_de(c.proyecto_id);
  if not (v_es_admin or v_es_sm) then
    raise exception 'No tienes permiso para prorrogar esta reserva.' using errcode = '42501';
  end if;
  v_max_dias := (case when v_es_admin then public.parametro_num('reservas.prorroga_dias_max_admin', 180)
                      else public.parametro_num('reservas.prorroga_dias_max_manager', 30) end)::int;
  if p_dias is null or p_dias < 1 or p_dias > v_max_dias then
    raise exception 'La prórroga va de 1 a % días.', v_max_dias using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('prorroga:' || p_contrato_id::text));
  select coalesce(max(n), 0) + 1 into v_n from public.contrato_prorrogas where contrato_id = p_contrato_id;
  if v_n > v_max_n and not v_es_admin then
    raise exception 'Esta Carta ya tiene % prórroga(s): la siguiente solo la puede dar un admin.', v_max_n using errcode = '42501';
  end if;

  v_desde := public.reserva_vence_el(p_contrato_id);
  if v_desde is null then
    raise exception 'La Carta no tiene fecha de pago de la reserva o plazo de validez: no hay vencimiento que prorrogar.' using errcode = '22023';
  end if;
  v_hasta := v_desde + p_dias;
  if v_hasta <= current_date then
    raise exception 'Con % días la reserva seguiría vencida (venció el %): pon más días.', p_dias, v_desde using errcode = '22023';
  end if;

  v_quien := coalesce(public._quien_actua(), (select auth.uid())::text);
  insert into public.contrato_prorrogas (contrato_id, n, dias, desde, motivo, comunicado_al_comprador, quien, creado_por)
  values (p_contrato_id, v_n, p_dias, v_desde, btrim(p_motivo), coalesce(p_comunicado, false), v_quien, (select auth.uid()));
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'reserva_prorrogada',
          jsonb_build_object('n', v_n, 'dias', p_dias, 'desde', v_desde, 'hasta', v_hasta,
                             'motivo', btrim(p_motivo), 'comunicado_al_comprador', coalesce(p_comunicado, false)),
          v_quien);
  return v_hasta;
end $$;
-- la tabla `contrato_prorrogas` tiene CHECK dias between 1 and 180: se amplía al
-- techo máximo configurable (730) — el tope real lo pone el parámetro.
alter table public.contrato_prorrogas drop constraint if exists contrato_prorrogas_dias_check;
alter table public.contrato_prorrogas add constraint contrato_prorrogas_dias_check check (dias between 1 and 730);

-- ── 3. El cálculo del abono de la Carta, como FUNCIÓN (no solo trigger) ─────
-- Misma lógica que carta_cobrado_al_bloquear() del 21/22-sep, con dos cambios:
--   · entran también las Cartas LIBERADAS del mismo comprador (identificadores
--     pasaporte/email, LAW-51: el MISMO criterio que crea la ficha), estén en
--     la parcela del Bloqueo o en otra — «la cuota se retiene y se imputa a
--     otra unidad» (owner, 22-sep). Primero las de la misma parcela, luego las
--     liberadas por número.
--   · reutilizable desde carta_cobrado_recalcula() para un borrador ya creado.
create or replace function public.carta_cobrado_calcula(p_id uuid, p_datos jsonb, p_proyecto_nombre text)
returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare
  datos jsonb := p_datos;
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(p_datos->'fields'->>'parcela_codigo',''), ',')) x);
  proy text := coalesce(nullif(btrim(p_datos->'fields'->>'proyecto_nombre'), ''), p_proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(p_datos->'fields'->>'moneda'), ''), 'EUR');
  ids_yo text[] := public.contrato_identificadores(p_datos);
  cartas_ids        uuid[];
  cartas_nums        text[];
  v_disponibles      numeric[] := '{}';
  v_nums_aportantes  text[] := '{}';
  v_cobrado          numeric := 0;
  v_precio_total     numeric;
  v_descuento        numeric;
  v_sobrante         numeric;
  v_restante         numeric;
  v_detalle          jsonb := '[]'::jsonb;
  v_disp             numeric;
  v_ya               numeric;
  v_claim            numeric;
  i                  int;
begin
  datos := datos #- '{fields,carta_cobrado_importe}'
                 #- '{fields,carta_cobrado_numeros}'
                 #- '{fields,carta_cobrado_sobrante}'
                 #- '{fields,carta_cobrado_detalle}';
  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');

  if proy is null then
    return datos;
  end if;

  select array_agg(x.id order by x.misma desc, x.numero), array_agg(x.numero order by x.misma desc, x.numero)
    into cartas_ids, cartas_nums
    from (select y.id, y.numero, bool_or(y.misma) as misma from (
      -- la Carta que ocupa hoy la parcela (traspaso Carta -> Bloqueo, 17-sep)
      select distinct c.id, c.numero, true as misma
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto = proy and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
      union
      -- la Carta LIBERADA del mismo comprador (22-sep): retenida e imputable
      select c.id, c.numero, false
        from public.contratos c
       where c.tipo like 'carta_reserva%'
         and c.liberado_en is not null
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
         and coalesce(array_length(ids_yo, 1), 0) > 0
         and public.contrato_identificadores(c.datos) && ids_yo
    ) y group by y.id, y.numero) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return datos;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> p_id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return datos;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(datos->'fields'->>'precio_total'), 0), 0);
  v_descuento := least(v_cobrado, v_precio_total);
  v_sobrante  := greatest(v_cobrado - v_precio_total, 0);

  if v_descuento > 0 then
    v_restante := v_descuento;
    for i in 1 .. array_length(cartas_ids, 1) loop
      exit when v_restante <= 0;
      v_disp := v_disponibles[i];
      if v_disp > 0 then
        v_claim := least(v_disp, v_restante);
        v_detalle := v_detalle || jsonb_build_object(
          'carta_id', cartas_ids[i],
          'numero', cartas_nums[i],
          'importe', public.lw_importe_texto(v_claim));
        v_nums_aportantes := v_nums_aportantes || cartas_nums[i];
        v_restante := v_restante - v_claim;
      end if;
    end loop;

    datos := jsonb_set(datos, '{fields,carta_cobrado_importe}', to_jsonb(public.lw_importe_texto(v_descuento)), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_numeros}', to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    datos := jsonb_set(datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select p_id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    datos := jsonb_set(datos, '{fields,carta_cobrado_sobrante}', to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  datos := public.carta_cobrado_aplica_hitos(datos, 'insert');
  return datos;
end;
$function$;
revoke execute on function public.carta_cobrado_calcula(uuid, jsonb, text) from public, anon, authenticated;

create or replace function public.carta_cobrado_al_bloquear()
 returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  new.datos := public.carta_cobrado_calcula(new.id, new.datos, new.proyecto_nombre);
  return new;
end $$;

-- el trigger de UPDATE deja pasar el recálculo (misma contraseña de transacción
-- que usa libera_reserva con app.via_libera_reserva)
create or replace function public.carta_cobrado_congelado_en_update()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
  k text;
begin
  if tg_op <> 'UPDATE' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  if coalesce(nullif(current_setting('app.via_carta_cobrado_recalcula', true), ''), 'off') = 'on' then
    return new;
  end if;
  foreach k in array array['carta_cobrado_importe','carta_cobrado_numeros',
                            'carta_cobrado_sobrante','carta_cobrado_detalle']
  loop
    if (old.datos->'fields') ? k then
      new.datos := jsonb_set(new.datos, array['fields', k], old.datos->'fields'->k, true);
    else
      new.datos := new.datos #- array['fields', k];
    end if;
  end loop;
  if (new.datos->'fields') ? 'carta_cobrado_importe'
     and (new.datos->'hitos' is distinct from old.datos->'hitos'
          or new.datos->'fields'->>'precio_total' is distinct from old.datos->'fields'->>'precio_total') then
    new.datos := public.carta_cobrado_aplica_hitos(new.datos, 'update');
  end if;
  return new;
end $$;

-- ── 4. Recalcular el abono en un Bloqueo en borrador (admin) ────────────────
create or replace function public.carta_cobrado_recalcula(p_contrato_id uuid)
returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  c public.contratos%rowtype;
  v_datos jsonb;
begin
  if not public.es_admin() then
    raise exception 'Recalcular el abono de la Carta exige admin.' using errcode = '42501';
  end if;
  select * into c from public.contratos where id = p_contrato_id;
  if c.id is null then raise exception 'Contrato no encontrado.' using errcode = 'P0002'; end if;
  if c.tipo <> 'reserva_parcela' then
    raise exception 'Solo se recalcula en un Bloqueo de Parcela.' using errcode = '22023';
  end if;
  if coalesce(c.bloqueado, false) or public.contrato_firma_viva(c.id) then
    raise exception 'El contrato está firmado o en firma: el abono impreso no se toca.' using errcode = '23514';
  end if;
  -- lo reclamado por este Bloqueo se suelta y se vuelve a calcular desde cero
  delete from public.carta_cobrado_aplicado where contrato_id = p_contrato_id;
  v_datos := public.carta_cobrado_calcula(c.id, c.datos, c.proyecto_nombre);
  perform set_config('app.via_carta_cobrado_recalcula', 'on', true);
  update public.contratos set datos = v_datos where id = p_contrato_id;
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'editado',
          jsonb_build_object('accion', 'carta_cobrado_recalculado',
                             'importe', v_datos->'fields'->>'carta_cobrado_importe',
                             'numeros', v_datos->'fields'->>'carta_cobrado_numeros'),
          coalesce(public._quien_actua(), (select auth.uid())::text));
  return jsonb_build_object('carta_cobrado_importe', v_datos->'fields'->>'carta_cobrado_importe',
                            'carta_cobrado_numeros', v_datos->'fields'->>'carta_cobrado_numeros',
                            'carta_cobrado_sobrante', v_datos->'fields'->>'carta_cobrado_sobrante');
end $$;
revoke all on function public.carta_cobrado_recalcula(uuid) from public, anon;
grant execute on function public.carta_cobrado_recalcula(uuid) to authenticated;
