-- Corrección de fondo tras `/code-review high` (17-sep-2026): doble cómputo
-- cuando UNA Carta con varias parcelas se traspasa a VARIOS Bloqueos por
-- separado (no todas a un único Bloqueo multi-parcela).
-- ════════════════════════════════════════════════════════════════════════════
-- EL FALLO ORIGINAL. `contrato_cobrado(carta_id)` devuelve el TOTAL cobrado
-- en la Carta, sin memoria de si ese dinero ya se aplicó a un Bloqueo
-- anterior. El trigger AFTER (`sincroniza_unidad_contrato`) solo fija
-- `contrato_padre_id` en la Carta la PRIMERA vez (`where c.contrato_padre_id
-- is null`), así que una Carta con 3 parcelas (p.ej. CR00025: B9/B15/B16)
-- puede traspasar cada una a un Bloqueo distinto en fechas distintas, y CADA
-- Bloqueo vería el 100% de lo cobrado en la Carta y lo descontaría entero —
-- el mismo abono aplicado dos o tres veces, en documentos firmables
-- independientes. Real en este dominio (Cartas multi-parcela existen en
-- producción, CP00002/CR00025), no cubierto por ninguna regla ya cerrada del
-- owner (que hablaban de "varias Cartas hacia UN Bloqueo", no de "una Carta
-- hacia varios Bloqueos" secuenciales).
--
-- ARREGLO (sin tabla nueva): cada Bloqueo que reclama dinero de una Carta
-- ahora escribe también `fields.carta_cobrado_detalle`, un array
-- `[{carta_id, numero, importe}]` con CUÁNTO reclamó de CADA Carta de
-- origen. El siguiente Bloqueo que mire la MISMA Carta resta lo que YA
-- reclamaron sus hermanos antes de calcular su propio descuento — el
-- "disponible" de cada Carta, no su total bruto. El sobrante NUNCA se anota
-- como reclamado.
--
-- ESTA VERSIÓN añade tres correcciones de la consulta de deploy sobre la
-- primera versión (aplicada como 20260917151710, ya en producción — esto la
-- reemplaza con CREATE OR REPLACE, no es una migración nueva desde cero):
--
-- 1) [ALTA, Legal] `carta_cobrado_numeros` citaba TODAS las Cartas que
--    ocupan la parcela por coincidencia de parcela+moneda, no solo las que
--    de verdad aportaron algo al descuento. Si la Carta A ya estaba agotada
--    por un Bloqueo anterior y solo la Carta B aportó el resto, el
--    documento firmado decía igualmente "conforme a la Carta de Reserva A,
--    B" — citando a A como origen de un abono que no puso nada en ESTE
--    reparto. Arreglo: `carta_cobrado_numeros` se construye ahora a partir
--    de las Cartas que SÍ entran en `carta_cobrado_detalle`, no de la lista
--    bruta de la consulta inicial.
--
-- 2) [ALTA, Administración + Seguridad — mismo hallazgo desde dos ángulos]
--    `carta_cobrado_detalle` solo lo escribe el trigger en el INSERT y
--    nunca se protege en el UPDATE. Dos formas de perderlo:
--      (a) Uso normal: reabrir y volver a guardar un Bloqueo ya creado
--          (`guardarContrato()` hace `.update(payload)` con el `datos`
--          ENTERO reconstruido desde `collect()`+`CAMPOS_HEREDADOS`, que
--          nunca carga `carta_cobrado_detalle` — administración, confirmado
--          por grep: cero referencias a ese campo fuera del SQL) — el
--          re-guardado lo borra sin que nadie lo pida, y el siguiente
--          Bloqueo sobre la misma Carta vuelve a ver "disponible" completo.
--      (b) Manipulación directa: un agente con permiso de UPDATE sobre su
--          propio Bloqueo (antes de firma) puede mandar un PATCH crudo a
--          Supabase —sin pasar por la UI— y borrar su propia entrada del
--          ledger, o inyectar una entrada falsa apuntando al `carta_id` de
--          una Carta ajena para poner su disponible a cero.
--    Ambos caminos reabren el doble cómputo que esta migración existe para
--    cerrar. Arreglo: nuevo trigger BEFORE UPDATE que congela los 4 campos
--    `carta_cobrado_*` a su valor de INSERT — cualquier UPDATE, venga de
--    donde venga, los repone desde `old`, ignorando lo que traiga `new`.
--    Coherente con la regla 3 del encargo original ("frozen, never
--    recalculated even across later edits"): esto es CERRAR ese mandato
--    para el camino de escritura que se quedó sin cubrir, no una regla
--    nueva.
--
-- 3) [MEDIA, Seguridad + Administración] Sin lock entre dos Bloqueos
--    insertándose a la vez sobre la MISMA Carta: ambos podrían leer
--    "disponible" completo antes de que ninguno confirme su claim.
--    Arreglo de una línea: `pg_advisory_xact_lock` por Carta, liberado solo
--    al terminar la transacción — serializa sin tocar el resto del sistema.
-- ════════════════════════════════════════════════════════════════════════════
--
-- DECISIÓN DEL OWNER, 18-sep-2026: el reparto "quien se guarda primero, se
-- lleva primero" (arriba, "disponible por Carta") se queda SIN cláusula que
-- lo explique en el documento. Legal lo había marcado como punto abierto tras
-- el 17-sep; el owner respondió que el Bloqueo YA admite varias parcelas en
-- un solo documento (chips de `parcela_codigo`, ver `parcela_inventario.js`),
-- así que el camino esperado es una Carta multi-parcela → UN Bloqueo que se
-- lleva todas de una vez — no el reparto secuencial que motivó esta migración.
-- Ese reparto sigue existiendo (CR00025 lo usa de verdad) y sigue siendo
-- financieramente seguro (el ledger de arriba impide el doble cómputo pase lo
-- que pase), pero es el caso raro, no el flujo que hay que documentar en la
-- plantilla. No añadir cláusula para esto salvo que el owner lo pida explícito.

create or replace function public.carta_cobrado_al_bloquear()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
  v_hitos            jsonb;
  v_restante         numeric;
  v_monto            numeric;
  v_resta            numeric;
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

  -- mismo criterio de moneda que ya se corrigió; ahora en orden por numero
  -- para que cartas_ids/cartas_nums queden alineados de forma determinista
  -- (los necesito emparejados para el reparto en cascada de más abajo).
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

  -- disponible por Carta = cobrado real − lo que otros Bloqueos ya reclamaron
  -- de ESA misma Carta (su propio carta_cobrado_detalle, nunca el sobrante).
  -- Lock consultivo por Carta ANTES de leer: serializa dos Bloqueos que se
  -- insertan a la vez sobre la misma Carta (corrección 3 de la nota de
  -- arriba) — se libera solo al terminar esta transacción.
  for i in 1 .. array_length(cartas_ids, 1) loop
    perform pg_advisory_xact_lock(hashtext(cartas_ids[i]::text));
    v_ya := coalesce((
      select sum(public.lw_importe(d->>'importe'))
        from public.contratos c2,
             jsonb_array_elements(coalesce(c2.datos->'fields'->'carta_cobrado_detalle', '[]'::jsonb)) d
       where c2.tipo = 'reserva_parcela'
         and c2.id <> new.id
         and (d->>'carta_id')::uuid = cartas_ids[i]
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
    -- reparto del descuento EN CASCADA sobre lo disponible de cada Carta, en
    -- el mismo orden. v_nums_aportantes se construye AQUÍ, con las Cartas
    -- que de verdad se llevaron algo — no con la lista bruta de arriba
    -- (corrección 1 de la nota grande: citar una Carta agotada como origen
    -- del abono es el documento firmado declarando algo que no pasó).
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
  end if;

  if v_sobrante > 0 then
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_sobrante}',
                            to_jsonb(public.lw_importe_texto(v_sobrante)), true);
  end if;

  if v_descuento > 0 then
    v_restante := v_descuento;
    v_hitos := new.datos->'hitos';
    if jsonb_typeof(v_hitos) = 'array' then
      for i in 0 .. jsonb_array_length(v_hitos) - 1 loop
        exit when v_restante <= 0;
        v_monto := coalesce(public.lw_importe(v_hitos->i->>'monto'), 0);
        if v_monto > 0 then
          v_resta := least(v_monto, v_restante);
          v_hitos := jsonb_set(v_hitos, array[i::text, 'monto'],
                                to_jsonb(public.lw_importe_texto(v_monto - v_resta)), true);
          v_restante := v_restante - v_resta;
        end if;
      end loop;
      new.datos := jsonb_set(new.datos, '{hitos}', v_hitos, true);
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.carta_cobrado_al_bloquear() from public, anon, authenticated;

comment on function public.carta_cobrado_al_bloquear() is
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero DISPONIBLE (cobrado real menos lo ya reclamado por otros Bloqueos de la misma Carta, fields.carta_cobrado_detalle) en la MISMA MONEDA que el propio Bloqueo, descuenta ese abono (fields.carta_cobrado_*, hitos en cascada). carta_cobrado_numeros solo cita Cartas que de verdad aportaron. El sobrante nunca se anota como reclamado. pg_advisory_xact_lock por Carta serializa Bloqueos concurrentes. Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción). 17-sep-2026, revisión previa #24 + code-review + consulta de deploy (numeros mal atribuidos, ledger sin proteger en UPDATE, sin lock entre inserts concurrentes).';

-- ── trigger nuevo: congela carta_cobrado_* frente a CUALQUIER UPDATE ────────
-- Corrección 2 de la nota grande: sin esto, reabrir y volver a guardar un
-- Bloqueo (uso normal) o mandar un PATCH crudo (manipulación) borra o
-- falsea el ledger que el trigger de arriba acaba de blindar. Repone los 4
-- campos desde `old` SIEMPRE que el contrato sea reserva_parcela,
-- ignorando lo que traiga `new` — sea lo que sea, venga de quien venga.
-- No toca `hitos`: ESE sigue recalculándose en cada edición de precio_total
-- (regla 7 del encargo, hitos_fechas.js) reaplicando el importe ya congelado
-- que este trigger protege.
create or replace function public.carta_cobrado_congelado_en_update()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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

  return new;
end;
$$;

revoke execute on function public.carta_cobrado_congelado_en_update() from public, anon, authenticated;

-- destructivo-ok: DROP defensivo de un trigger que hoy NO existe en producción
-- (mismo patrón ya usado en la migración original de esta feature) — solo
-- por si esta migración se reaplica alguna vez; no borra nada que exista.
drop trigger if exists trg_carta_cobrado_congelado_en_update on public.contratos;
create trigger trg_carta_cobrado_congelado_en_update
  before update on public.contratos
  for each row execute function public.carta_cobrado_congelado_en_update();

comment on function public.carta_cobrado_congelado_en_update() is
  'BEFORE UPDATE en contratos: si es un Bloqueo de Parcela (reserva_parcela), repone fields.carta_cobrado_importe/numeros/sobrante/detalle al valor que tenían ANTES del UPDATE, pase lo que pase en new — cierra el hueco por el que un re-guardado normal (UI) o un PATCH directo podía borrar o falsear el ledger que carta_cobrado_al_bloquear() escribe una sola vez en el INSERT. 17-sep-2026, consulta de deploy (hallazgo ALTA de Administración y de Seguridad, mismo problema desde dos ángulos distintos).';

-- ── comprobación tras aplicar ────────────────────────────────────────────────
-- 1) Probe de cero huella (repite el de la versión anterior, debe seguir
--    dando el mismo resultado): dos Bloqueos secuenciales sobre CR00025
--    (multi-parcela, cobrado real 5000 EUR) — el segundo debe ver
--    "disponible" en 3000, no 5000.
-- 2) Probe NUEVO — congelación en UPDATE: tras el INSERT del primer Bloqueo
--    de arriba, un UPDATE que intente poner `carta_cobrado_detalle` a '[]'
--    (simulando un re-guardado normal que lo "olvida", o un PATCH que lo
--    borra a propósito) debe dejar el campo EXACTAMENTE como estaba.
-- Ambos dentro de un DO $$ con RAISE EXCEPTION final — rollback total, cero
-- huella en producción.
