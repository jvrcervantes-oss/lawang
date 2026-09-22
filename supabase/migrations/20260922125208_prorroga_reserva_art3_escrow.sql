-- ════════════════════════════════════════════════════════════════════════════
-- PRÓRROGA DE CARTA DE RESERVA + GRACIA · ART. 3 DEL BLOQUEO · ESCROW · DESCUENTO
-- 22-sep-2026 — revisión previa #41 (Legal + Datos + Seguridad)
-- ════════════════════════════════════════════════════════════════════════════
-- Owner (22-sep-2026): «un cliente hace una carta de reserva durante X días y
-- tras eso se libera, pero el cliente tarda en pagar y el sistema libera la
-- parcela porque el Bloqueo no ha llegado a ocurrir». Decisiones tomadas:
--   · Prórroga REGISTRADA fuera de `datos` (que se congela al firmar) + 3 días
--     de gracia al vencer antes de liberar. Puede prorrogar sales_manager (de
--     su proyecto) para arriba; 2 prórrogas por Carta, la 3ª y siguientes solo
--     admin. Aviso interno, nunca al comprador (va a su favor).
--   · El vencimiento tiene UNA fuente: reserva_vence_el() / reservas_vencimiento().
--     La edge libera-reservas-vencidas y la ficha v4 la llaman; nadie vuelve a
--     sumar fecha_pago_reserva + validez a mano.
--   · La cláusula ESCROW del Bloqueo solo sale si la cuenta elegida lo es:
--     `cuenta_es_escrow` lo estampa un trigger desde cuentas_bancarias.es_escrow
--     (el cliente puede mandarlo, el servidor lo pisa — patrón carta_cobrado_*).
--   · El descuento de la Carta sobre los hitos del Bloqueo tiene UN dueño: la
--     función carta_cobrado_aplica_hitos(), que corre en INSERT y en UPDATE.
--     Antes `hitos` viajaba libre en cada guardado (hallazgo Seguridad/Datos).
--
-- Hallazgos de la revisión previa plegados aquí (los que cambian código):
--   Seguridad: gate de rol EXPLÍCITO sales_manager (es_manager_de deja pasar a
--     project_manager) · advisory lock en el tope · techo de días · tabla nueva
--     sin grants de escritura en vez de trigger-GUC · reserva_vence_el SECURITY
--     INVOKER (que no sea un oráculo de uuids invisibles) · descontado se
--     stripea y lo estampa el servidor.
--   Datos: CHECK de contrato_eventos con la lista VIVA (19 valores + el nuevo) ·
--     `pct` nunca se vacía (Σ%=100 y contrato_vencimientos lo leen) · función
--     set-returning para la edge (sin traerse `datos` de 500 contratos) ·
--     prórroga que no supere hoy no vale con gracia · índice por contrato.
--   Legal: `comunicado_al_comprador` en la prórroga (constancia si un agente se
--     lo dijo al comprador — una promesa oral sí vincula).
--
-- destructivo-ok: los tres DROP de abajo son el idiom idempotente del repo
-- (drop ... if exists + create): el CHECK se recrea con la lista viva más un
-- valor, la policy y el trigger se recrean iguales. No se borra ningún dato.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Prórrogas: tabla ──────────────────────────────────────────────────────
create table if not exists public.contrato_prorrogas (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  n           int  not null check (n >= 1),
  dias        int  not null check (dias between 1 and 180),
  desde       date not null,
  -- un solo dueño del dato: `hasta` se deriva, nunca se escribe
  hasta       date generated always as (desde + dias) stored,
  motivo      text not null check (length(btrim(motivo)) >= 6),
  comunicado_al_comprador boolean not null default false,
  quien       text,
  creado_por  uuid,
  creado_en   timestamptz not null default now(),
  unique (contrato_id, n)
);
comment on table public.contrato_prorrogas is
  'Prórrogas del plazo de una Carta de Reserva (22-sep-2026). Solo escribe prorroga_reserva(); ni la app ni nadie con sesión tiene INSERT/UPDATE/DELETE. `hasta` es columna generada (desde + dias).';
create index if not exists contrato_prorrogas_contrato_idx on public.contrato_prorrogas (contrato_id, n desc);
alter table public.contrato_prorrogas enable row level security;
revoke all on public.contrato_prorrogas from public, anon, authenticated;
grant select on public.contrato_prorrogas to authenticated;
-- La lectura sigue al contrato — forma canónica del repo (vencimientos_select,
-- 20260922024513), no es_agente() a secas (LAW-253).
-- destructivo-ok: drop policy if exists + create, idiom idempotente
drop policy if exists prorrogas_select on public.contrato_prorrogas;
create policy prorrogas_select on public.contrato_prorrogas
  for select to authenticated
  using (public.es_agente() and exists (
           select 1 from public.contratos c
            where c.id = contrato_prorrogas.contrato_id
              and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))));

-- ── 2. El vencimiento, una sola vez ─────────────────────────────────────────
-- SECURITY INVOKER a propósito: desde el navegador lee contratos/prórrogas bajo
-- la RLS de quien pregunta (null para lo que no ve); service_role la salta.
-- Parseo defensivo: `validez_dias` y `fecha_pago_reserva` son texto de
-- formulario — "15 días" no tumba la pasada del cron, devuelve null y la edge
-- lo cuenta en `saltadas`.
create or replace function public.reserva_vence_el(p_contrato_id uuid)
returns date
language plpgsql stable security invoker set search_path to '' as $$
declare
  f      jsonb;
  fecha  date;
  dias   int;
  meses  int;
  base   date;
  ult    date;
begin
  select c.datos->'fields' into f from public.contratos c where c.id = p_contrato_id;
  if f is null then return null; end if;
  begin fecha := nullif(left(f->>'fecha_pago_reserva', 10), '')::date; exception when others then fecha := null; end;
  if fecha is null then return null; end if;
  begin dias  := nullif(btrim(f->>'validez_dias'), '')::int;  exception when others then dias  := null; end;
  begin meses := nullif(btrim(f->>'validez_meses'), '')::int; exception when others then meses := null; end;
  if dias is not null then base := fecha + dias;
  elsif meses is not null then base := (fecha + make_interval(months => meses))::date;  -- NUNCA meses*30
  else return null; end if;
  select max(p.hasta) into ult from public.contrato_prorrogas p where p.contrato_id = p_contrato_id;
  return greatest(base, coalesce(ult, base));
end $$;
revoke execute on function public.reserva_vence_el(uuid) from public, anon;
grant execute on function public.reserva_vence_el(uuid) to authenticated, service_role;

-- La lista que procesa la edge: un solo viaje, sin `datos` (LAW-78: descomprimir
-- el jsonb de 500 contratos por RPC por fila era el coste). Mismo criterio de
-- candidato que tenía la edge en TypeScript: parcela `reservada`, contrato de
-- tipo Carta (catálogo contrato_tipo_etapa, nunca lista a mano), no liberado.
create or replace function public.reservas_vencimiento()
returns table (
  unidad_id uuid, codigo text, proyecto text,
  contrato_id uuid, numero text, tipo text, proyecto_id uuid, proyecto_nombre text,
  comprador_nombre text, vence_el date, n_prorrogas int
)
language sql stable security invoker set search_path to '' as $$
  select u.id, u.codigo, u.proyecto,
         c.id, c.numero, c.tipo, c.proyecto_id, c.proyecto_nombre, c.comprador_nombre,
         public.reserva_vence_el(c.id),
         (select count(*)::int from public.contrato_prorrogas p where p.contrato_id = c.id)
    from public.unidades u
    join public.contratos c on c.id = u.contrato_id
   where u.estado = 'reservada'
     and c.liberado_en is null
     and c.tipo in (select e.tipo from public.contrato_tipo_etapa e
                     where e.etapa = 'reserva' and e.tipo <> 'reserva_parcela')
$$;
revoke execute on function public.reservas_vencimiento() from public, anon, authenticated;
grant execute on function public.reservas_vencimiento() to service_role;

-- ── 3. El evento nuevo (lista VIVA de pg_get_constraintdef + el nuevo) ──────
-- destructivo-ok: se recrea el CHECK con los 19 valores vivos + 'reserva_prorrogada'
alter table public.contrato_eventos drop constraint if exists contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array['creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta',
    'firma_recogida','firma_anulada','firmado_del_todo','desbloqueado','traspaso',
    'editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear',
    'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha','factura_borrada',
    'contrato_borrado','reserva_liberada','reserva_prorrogada']));

-- ── 4. La prórroga ──────────────────────────────────────────────────────────
-- Techo de días: 30 para sales_manager, 180 para admin (el owner fijó el tope
-- de NÚMERO —2 y la 3ª solo admin—; el de días es del estudio, para que una
-- prórroga de 3650 días no sea "una sola fila" que retiene la parcela sin venta).
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

  -- Rol: EL MISMO bloque que libera_reserva() por desistimiento — explícito,
  -- porque es_manager_de() sola también deja pasar a project_manager.
  v_es_admin := public.es_admin();
  v_es_sm := exists (select 1 from public.usuarios uu
                      where uu.user_id = (select auth.uid()) and uu.activo and uu.rol = 'sales_manager')
             and public.es_manager_de(c.proyecto_id);
  if not (v_es_admin or v_es_sm) then
    raise exception 'No tienes permiso para prorrogar esta reserva.' using errcode = '42501';
  end if;
  if p_dias is null or p_dias < 1 or p_dias > (case when v_es_admin then 180 else 30 end) then
    raise exception 'La prórroga va de 1 a % días.', (case when v_es_admin then 180 else 30 end) using errcode = '22023';
  end if;

  -- una prórroga a la vez por contrato: el nº y el tope no admiten carreras
  perform pg_advisory_xact_lock(hashtext('prorroga:' || p_contrato_id::text));
  select coalesce(max(n), 0) + 1 into v_n from public.contrato_prorrogas where contrato_id = p_contrato_id;
  if v_n >= 3 and not v_es_admin then
    raise exception 'Esta Carta ya tiene 2 prórrogas: la tercera solo la puede dar un admin.' using errcode = '42501';
  end if;

  v_desde := public.reserva_vence_el(p_contrato_id);
  if v_desde is null then
    raise exception 'La Carta no tiene fecha de pago de la reserva o plazo de validez: no hay vencimiento que prorrogar.' using errcode = '22023';
  end if;
  v_hasta := v_desde + p_dias;
  -- con 3 días de gracia, una prórroga que no pase de hoy no cambia nada:
  -- se liberaría igual en la próxima pasada
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
revoke all on function public.prorroga_reserva(uuid, int, text, boolean) from public, anon;
grant execute on function public.prorroga_reserva(uuid, int, text, boolean) to authenticated;

-- ── 5. cuenta_es_escrow lo estampa la base ──────────────────────────────────
-- BEFORE INSERT OR UPDATE OF datos. Sin cuenta → 'no' (Legal: un Bloqueo nunca
-- sale sin decir dónde se paga). En UPDATE sin cambio real de `datos` no toca
-- nada: si añadiera la clave a un contrato firmado, contrato_no_editable_en_firma
-- (que corre después, por orden alfabético) vería `datos` distinto y reventaría.
create or replace function public.contrato_cuenta_es_escrow()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
  v_clave text;
  v_val   text := 'no';
begin
  if jsonb_typeof(new.datos->'fields') <> 'object' then return new; end if;
  if tg_op = 'UPDATE' and new.datos is not distinct from old.datos then return new; end if;
  v_clave := nullif(btrim(coalesce(new.datos->'fields'->>'cuenta_bancaria', '')), '');
  if v_clave is not null then
    select case when cb.es_escrow then 'si' else 'no' end into v_val
      from public.cuentas_bancarias cb where cb.clave = v_clave;
    v_val := coalesce(v_val, 'no');
  end if;
  new.datos := jsonb_set(new.datos, '{fields,cuenta_es_escrow}', to_jsonb(v_val), true);
  return new;
end $$;
revoke execute on function public.contrato_cuenta_es_escrow() from public, anon, authenticated;
-- destructivo-ok: drop trigger if exists + create, idiom idempotente
drop trigger if exists trg_contrato_cuenta_es_escrow on public.contratos;
create trigger trg_contrato_cuenta_es_escrow
  before insert or update of datos on public.contratos
  for each row execute function public.contrato_cuenta_es_escrow();

-- ── 6. La cascada del descuento, un solo dueño ──────────────────────────────
-- Regla (la misma que ya aplicaba el cliente en recalcularMontosHitos, 17-sep):
--   · un hito `calculado` es una fracción del precio: su bruto se RECALCULA
--     (pct × precio_total) en cada escritura y sobre esos, en orden, se resta
--     el descuento en cascada (lwDescuentoCascada, dinero.js — misma regla).
--   · un hito manual es lo que el agente tecleó: no entra en la cascada... salvo
--     en INSERT cuando NO hay ningún hito calculado (calendarios de importes
--     fijos): ahí se descuenta una vez, como hacía el trigger desde el 17-sep,
--     y en UPDATE se respeta lo guardado.
--   · `descontado`, `monto_bruto` y `pct_original` los pone SOLO esta función:
--     lo que traiga el cliente se stripea. `pct` no se toca nunca (Σ%=100 en
--     guardarContrato y contrato_vencimientos lo leen): el documento deja la
--     celda % en blanco mirando `descontado`, no vaciando el dato.
create or replace function public.carta_cobrado_aplica_hitos(p_datos jsonb, p_modo text)
returns jsonb
language plpgsql stable set search_path to '' as $$
declare
  v_precio   numeric := greatest(coalesce(public.lw_importe(p_datos->'fields'->>'precio_total'), 0), 0);
  v_desc     numeric := coalesce(public.lw_importe(p_datos->'fields'->>'carta_cobrado_importe'), 0);
  v_hitos    jsonb := p_datos->'hitos';
  v_limpio   jsonb := '[]'::jsonb;
  v_out      jsonb := '[]'::jsonb;
  h          jsonb;
  v_calc     boolean;
  v_hay_calc boolean := false;
  v_pct      numeric;
  v_monto    numeric;
  v_restante numeric;
  v_resta    numeric;
  i          int;
begin
  if jsonb_typeof(v_hitos) <> 'array' then return p_datos; end if;

  for i in 0 .. jsonb_array_length(v_hitos) - 1 loop
    h := (v_hitos->i) - 'descontado' - 'monto_bruto' - 'pct_original';
    v_calc := coalesce((h->>'calculado')::boolean, false);
    if v_calc then
      v_hay_calc := true;
      v_pct := coalesce(public.lw_importe(h->>'pct'), 0);
      if v_pct > 0 and v_precio > 0 then
        h := h || jsonb_build_object('monto', public.lw_importe_texto(round(v_precio * v_pct / 100, 2)));
      end if;
    end if;
    v_limpio := v_limpio || h;
  end loop;

  -- UPDATE de un calendario manual: lo guardado ya está descontado, no se repite
  if v_desc <= 0 or (p_modo = 'update' and not v_hay_calc) then
    return jsonb_set(p_datos, '{hitos}', v_limpio, true);
  end if;

  v_restante := least(v_desc, v_precio);
  for i in 0 .. jsonb_array_length(v_limpio) - 1 loop
    h := v_limpio->i;
    v_calc := coalesce((h->>'calculado')::boolean, false);
    v_monto := coalesce(public.lw_importe(h->>'monto'), 0);
    if v_restante > 0 and v_monto > 0 and (v_calc or not v_hay_calc) then
      v_resta := least(v_monto, v_restante);
      h := h || jsonb_build_object('monto', public.lw_importe_texto(v_monto - v_resta),
                                   'monto_bruto', public.lw_importe_texto(v_monto),
                                   'pct_original', coalesce(h->>'pct', ''),
                                   'descontado', true);
      v_restante := v_restante - v_resta;
    end if;
    v_out := v_out || h;
  end loop;
  return jsonb_set(p_datos, '{hitos}', v_out, true);
end $$;
revoke execute on function public.carta_cobrado_aplica_hitos(jsonb, text) from public, anon, authenticated;

-- UPDATE: además de congelar los 4 carta_cobrado_* (17-sep), vuelve a aplicar
-- la cascada si cambiaron los hitos o el precio. Antes `hitos` viajaba libre.
create or replace function public.carta_cobrado_congelado_en_update()
returns trigger language plpgsql security definer set search_path to '' as $$
declare
  k text;
begin
  if tg_op <> 'UPDATE' or new.tipo <> 'reserva_parcela' then
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

-- INSERT: la misma funcion del 21-sep (carta_cobrado_aplicado_tabla_lateral) con la
-- cascada de hitos delegada en carta_cobrado_aplica_hitos(). Reproducida entera
-- porque create or replace no admite parches.
create or replace function public.carta_cobrado_al_bloquear()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  moneda_bloqueo text := coalesce(nullif(btrim(new.datos->'fields'->>'moneda'), ''), 'EUR');
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
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;

  new.datos := new.datos #- '{fields,carta_cobrado_importe}'
                         #- '{fields,carta_cobrado_numeros}'
                         #- '{fields,carta_cobrado_sobrante}'
                         #- '{fields,carta_cobrado_detalle}';

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then
    return new;
  end if;

  select array_agg(x.id order by x.numero), array_agg(x.numero order by x.numero)
    into cartas_ids, cartas_nums
    from (
      select distinct c.id, c.numero
        from public.unidades u
        join public.contratos c on c.id = u.contrato_id
       where u.proyecto = proy and u.codigo = any(cods)
         and c.tipo like 'carta_reserva%'
         and coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo
    ) x;

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return new;
  end if;

  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    -- ANTES: sum(...) from contratos c2, jsonb_array_elements(c2.datos->...) -- escaneaba
    -- y descomprimia el `datos` de los 116 contratos reserva_parcela por cada carta
    -- (2.710 ms/12.722 buffers medido para UNA carta). AHORA: tabla lateral indexada.
    v_ya := coalesce((
      select sum(importe) from public.carta_cobrado_aplicado
       where carta_id = cartas_ids[i] and contrato_id <> new.id
    ), 0);
    v_disp := greatest(coalesce(public.contrato_cobrado(cartas_ids[i]), 0) - v_ya, 0);
    v_disponibles := v_disponibles || v_disp;
    v_cobrado := v_cobrado + v_disp;
  end loop;

  if v_cobrado <= 0 then
    return new;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(new.datos->'fields'->>'precio_total'), 0), 0);
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

    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_importe}',
                            to_jsonb(public.lw_importe_texto(v_descuento)), true);
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_numeros}',
                            to_jsonb(array_to_string(v_nums_aportantes, ', ')), true);
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_detalle}', v_detalle, true);

    -- Espejo indexado de lo que se acaba de reclamar, para que la PROXIMA alta no
    -- tenga que volver a escanear el `datos` de nadie -- misma fuente (v_detalle) que
    -- se acaba de congelar en el jsonb, sin recalcular ni duplicar la logica de reparto.
    insert into public.carta_cobrado_aplicado (contrato_id, carta_id, importe)
    select new.id, (elem->>'carta_id')::uuid, public.lw_importe(elem->>'importe')
      from jsonb_array_elements(v_detalle) elem
    on conflict (contrato_id, carta_id) do nothing;
  end if;

  if v_sobrante > 0 then
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_sobrante}',
                            to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  -- 22-sep-2026: la cascada sobre los hitos ya no vive aqui - vive en
  -- carta_cobrado_aplica_hitos(), que tambien corre en UPDATE (antes `hitos`
  -- viajaba libre en cada guardado y cualquier escritor deshacia el descuento).
  new.datos := public.carta_cobrado_aplica_hitos(new.datos, 'insert');

  return new;
end;
$function$;

