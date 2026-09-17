-- Dos correcciones de la consulta de deploy (17-sep-2026, capa 1) sobre
-- carta_cobrado_al_bloquear.sql — ambas ALTA, las dos verificadas antes de
-- escribir esto, ninguna es una opinión.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Administración: el descuento comparaba importes sin comprobar moneda ──
-- `v_cobrado` sale de `contrato_cobrado()` — la suma de lo cobrado en la(s)
-- Carta(s) de origen, en SU moneda — y se comparaba/restaba directamente
-- contra `precio_total` del propio Bloqueo sin mirar si son la misma moneda.
-- La suite ya admite varias (EUR/USD/AUD/IDR, `lwSumaPorMoneda` en dinero.js,
-- "no hay tipo de cambio en el sistema y meter uno inventado sería peor").
-- Si la Carta y el Bloqueo declaran monedas distintas, el descuento y su
-- reparto en cascada sobre los hitos serían una cifra sin sentido, impresa
-- firmable en el documento. Arreglo: una Carta con moneda distinta a la del
-- Bloqueo se EXCLUYE del cálculo automático (no se adivina un cambio) — igual
-- que ya hace el resto del estudio ante monedas mezcladas.

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
  cartas_ids     uuid[];
  cartas_nums    text[];
  v_cobrado      numeric := 0;
  v_precio_total numeric;
  v_descuento    numeric;
  v_sobrante     numeric;
  v_hitos        jsonb;
  v_restante     numeric;
  v_monto        numeric;
  v_resta        numeric;
  i              int;
begin
  if tg_op <> 'INSERT' or new.tipo <> 'reserva_parcela' then
    return new;
  end if;

  new.datos := new.datos #- '{fields,carta_cobrado_importe}'
                         #- '{fields,carta_cobrado_numeros}'
                         #- '{fields,carta_cobrado_sobrante}';

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then
    return new;
  end if;

  -- misma moneda que el Bloqueo, o no se cuenta (arreglo de hoy) —
  -- ARRAY_AGG con FILTER, no un WHERE en el JOIN: así una Carta que sí ocupa
  -- la parcela pero en otra moneda no desaparece de la comprobación de
  -- traspaso del trigger AFTER (que no mira moneda), solo de ESTE cálculo.
  select coalesce(array_agg(distinct c.id) filter (
           where coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo), '{}'),
         coalesce(array_agg(distinct c.numero) filter (
           where coalesce(nullif(btrim(c.datos->'fields'->>'moneda'), ''), 'EUR') = moneda_bloqueo), '{}')
    into cartas_ids, cartas_nums
    from public.unidades u
    join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = any(cods)
     and c.tipo like 'carta_reserva%';

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return new;
  end if;

  select coalesce(sum(public.contrato_cobrado(cid)), 0) into v_cobrado
    from unnest(cartas_ids) as cid;

  if v_cobrado <= 0 then
    return new;
  end if;

  v_precio_total := greatest(coalesce(public.lw_importe(new.datos->'fields'->>'precio_total'), 0), 0);
  v_descuento := least(v_cobrado, v_precio_total);
  v_sobrante  := greatest(v_cobrado - v_precio_total, 0);

  if v_descuento > 0 then
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_importe}',
                            to_jsonb(public.lw_importe_texto(v_descuento)), true);
    new.datos := jsonb_set(new.datos, '{fields,carta_cobrado_numeros}',
                            to_jsonb(array_to_string(cartas_nums, ', ')), true);
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
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero cobrado EN LA MISMA MONEDA que el propio Bloqueo, descuenta ese abono (fields.carta_cobrado_*, hitos en cascada). Una Carta en otra moneda se excluye del cálculo (no hay conversión en el sistema). Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción). 17-sep-2026, revisión previa #24 + consulta de deploy (hallazgo ALTA de Administración: comparaba importes de monedas distintas).';

-- ── 2) Seguridad: contrato_cobrado() sigue GRANT a `authenticated` ─────────
-- El comentario de la migración de hoy decía "nunca se expone
-- contrato_cobrado() a un RPC del navegador (sería un oráculo)" dando por
-- hecho que ya estaba cerrado — NO lo estaba: `contrato_cobrado_fn.sql`
-- (11-ago-2026) le dio `grant execute ... to authenticated` y
-- `contrato_cobrado_no_pierde_dinero.sql` (14-ago, solo cambió el cuerpo de
-- la función) nunca lo revocó. Es SECURITY DEFINER y salta el RLS de
-- facturas/recibi_aplicaciones: cualquier rol `authenticated` (agente, y
-- cualquiera con sesión de Supabase Auth si el portal dual comparte rol)
-- podía leer `select contrato_cobrado('<uuid-ajeno>')` y ver lo cobrado de
-- CUALQUIER contrato, propio o no — el oráculo exacto que esta migración
-- decía que no existía.
-- No revocado de este trigger (postgres es su dueño y conserva acceso
-- implícito como dueño de ambas funciones — comprobado con pg_proc antes de
-- escribir esto) ni de ninguna otra función interna: solo se cierra la
-- puerta al navegador.
revoke execute on function public.contrato_cobrado(uuid) from authenticated;

-- ── comprobación tras aplicar ────────────────────────────────────────────────
--   select grantee, privilege_type from information_schema.role_routine_grants
--    where routine_name = 'contrato_cobrado' and routine_schema = 'public';
--   -- ya NO debe salir 'authenticated'.
--   -- Probe de cero huella con dos Cartas de distinta moneda antes de dar
--   -- esto por bueno (ver el hallazgo original, mismo patrón que
--   -- sql/carta_cobrado_al_bloquear.sql): INSERT + RAISE EXCEPTION en un
--   -- DO $$, revierte todo.
