-- El Bloqueo de Parcela descuenta lo que la Carta de Reserva ya cobró —
-- 17-sep-2026, revisión previa #24 (Legal + Administración + Seguridad).
-- ════════════════════════════════════════════════════════════════════════════
-- QUÉ RESUELVE. Cuando una Carta de Reserva (cualquier variante, todas con
-- prefijo `carta_reserva_%`) transfiere de verdad su parcela a un Bloqueo
-- (`sincroniza_unidad_contrato()`, ver abajo por qué NO se toca), el cliente
-- ya pagó algo en la Carta y el Bloqueo debe reflejarlo y descontarlo — no
-- puede pedirle el 100% del suelo otra vez.
--
-- ⚠️ HALLAZGO ANTES DE ESCRIBIR ESTO (verificado, no supuesto): el plan
-- original decía "dentro (o al lado, mismo trigger BEFORE) de
-- sincroniza_unidad_contrato()", asumiendo que ese trigger ya es BEFORE.
-- Comprobado contra producción (`pg_trigger`): `trg_sincroniza_unidad` es
-- AFTER INSERT OR UPDATE. Escribir en `new.datos` dentro de un trigger AFTER
-- no tiene efecto — el executor descarta cualquier NEW devuelto por un
-- trigger AFTER, no se persiste ni lo ven los triggers AFTER siguientes.
--
-- Y NO se puede arreglar pasando `trg_sincroniza_unidad` a BEFORE: esa
-- función hace `update unidades set contrato_id = new.id` y
-- `update contratos set contrato_padre_id = new.id`, y `unidades.contrato_id`
-- tiene FK NOT DEFERRABLE contra `contratos.id` (comprobado:
-- `select condeferrable from pg_constraint where conname =
-- 'unidades_contrato_id_fkey'` → false). En BEFORE INSERT la fila de
-- `contratos` todavía no existe en el heap — ese UPDATE reventaría la FK en
-- CADA Bloqueo con parcela, no solo en los que traspasan.
--
-- SOLUCIÓN: un trigger BEFORE INSERT nuevo y aparte, que NO escribe en
-- `unidades` ni en `contratos.contrato_padre_id` (eso lo sigue haciendo
-- solo `sincroniza_unidad_contrato`, AFTER, sin tocar) — solo LEE quién
-- ocupa hoy cada parcela y, si es una Carta de Reserva, calcula y estampa el
-- descuento en `new.datos` antes de que la fila se escriba. La comprobación
-- de que el traspaso es LEGÍTIMO (mismo comprador — LAW-51) la sigue haciendo
-- en exclusiva `sincroniza_unidad_contrato()` (AFTER, misma transacción): si
-- rechaza el traspaso, revienta con su excepción de siempre y esa excepción
-- deshace el INSERT COMPLETO — incluido lo que este trigger nuevo estampó.
-- Este trigger BEFORE es deliberadamente más permisivo en su lectura (no
-- comprueba identidad del comprador) precisamente porque el AFTER es quien
-- tiene la última palabra y puede abortarlo todo.
--
-- Dos triggers BEFORE INSERT sobre la MISMA fila, cada uno con su mitad de la
-- misma pregunta, no es ideal — pero es más seguro que una tercera copia de
-- la comprobación de "mismo comprador" (ya van dos: el trigger AFTER y
-- `estadoTraspaso()` en parcela_inventario.js) o que tocar la FK.
--
-- REGLAS DEL CÁLCULO (owner, ya cerradas — ver el encargo completo):
--   1) UNA vez, solo en INSERT (columna `datos.fields`, foto fija).
--   2) El cliente NUNCA manda este número: cualquier carta_cobrado_* que
--      llegue en el INSERT se ignora y se recalcula de cero aquí. Nunca se
--      expone `contrato_cobrado()` a un RPC del navegador (sería un oráculo:
--      cualquier agente autenticado podría leer el cobrado de cualquier
--      contrato ajeno con solo pasar su uuid).
--   3) Tope: el descuento nunca supera `precio_total` del propio Bloqueo (el
--      suelo, no la villa que declaraba la Carta). El sobrante sin aplicar
--      se anota aparte, nunca desaparece en silencio.
--   4) Reparto en cascada sobre los hitos que YA traiga el INSERT, en el
--      orden en que estén — nunca un monto por debajo de 0.
--   5) Si el cobrado de todas las Cartas de origen suma 0: no se escribe
--      ninguna clave nueva y el Bloqueo se guarda exactamente como hoy.
--
-- FORMATO DEL IMPORTE: el mismo que ya usa `datos.fields.precio_total`
-- (comprobado contra filas reales — RP00164: "54.204"; el separador de
-- miles solo aparece a partir de 10.000, un numero de 4 cifras se imprime
-- sin punto: "27.102" pero también hay legado sin canonicalizar como
-- "5000"/"20000" en RP00161/RP00162, de antes de que el cálculo automático
-- existiera). Se replica `lwImporteCanonico()` (contracts/assets/dinero.js)
-- con `lw_importe_texto()` más abajo, con la MISMA tabla de casos.
--
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) ESCRIBIR un importe en el formato canónico de la suite ──────────────
-- Gemelo de `lw_importe()` (dinero_no_es_texto.sql, que LEE), y de
-- `lwImporteCanonico()` (contracts/assets/dinero.js, que hace lo mismo en el
-- navegador). Locale-independiente a propósito (no usa 'G'/'D' de to_char,
-- que dependen de lc_numeric del servidor) — se construye el agrupado a
-- mano para no heredar la configuración regional de quien ejecute esto.
create or replace function public.lw_importe_texto(n numeric)
returns text
language plpgsql
immutable
as $$
declare
  v numeric;
  neg boolean;
  mostrar_decimales boolean;
  entero bigint;
  centimos int;
  entero_txt text;
  resto text;
  agrupado text;
  out_txt text;
begin
  if n is null then return null; end if;
  -- decide ANTES de redondear: 99999.999 imprime "100.000,00" (con
  -- decimales) aunque tras redondear a 2 el resultado sea un entero exacto —
  -- lwImporteCanonico() decide por `v % 1`, sobre el valor SIN redondear.
  mostrar_decimales := (n <> trunc(n));
  v := round(n, 2);
  neg := v < 0;
  v := abs(v);
  entero := trunc(v)::bigint;
  centimos := round((v - trunc(v)) * 100)::int;
  if centimos = 100 then entero := entero + 1; centimos := 0; end if;

  entero_txt := entero::text;
  -- el separador de miles SOLO aparece a partir de 10.000 (5 cifras): un
  -- entero de 4 cifras se imprime sin punto, comprobado contra
  -- `Number(1234).toLocaleString('es-ES')` → "1234", no "1.234". Esto NO es
  -- "agrupar de 3 en 3 siempre": es la rareza real del locale es-ES en este
  -- runtime, y por eso el DO $$ de abajo la fija con el mismo caso.
  if length(entero_txt) >= 5 then
    resto := entero_txt; agrupado := '';
    while length(resto) > 3 loop
      agrupado := '.' || right(resto, 3) || agrupado;
      resto := left(resto, length(resto) - 3);
    end loop;
    agrupado := resto || agrupado;
  else
    agrupado := entero_txt;
  end if;

  out_txt := agrupado;
  if mostrar_decimales then out_txt := out_txt || ',' || lpad(centimos::text, 2, '0'); end if;
  if neg and (entero <> 0 or centimos <> 0) then out_txt := '-' || out_txt; end if;
  return out_txt;
end $$;

comment on function public.lw_importe_texto(numeric) is
  'Importe -> texto en el formato canónico de la suite (es-ES, punto de miles solo desde 10.000, coma decimal). Gemelo de lwImporteCanonico() en contracts/assets/dinero.js; misma tabla de casos en el DO $$ de abajo.';

-- ── autocomprobación: los MISMOS casos que dinero.test.js (lwImporteCanonico) ──
do $$
declare v record;
begin
  for v in select * from (values
      (0::numeric,            '0'),
      (1::numeric,             '1'),
      (1234::numeric,          '1234'),
      (9999::numeric,          '9999'),
      (10000::numeric,         '10.000'),
      (10001::numeric,         '10.001'),
      (54204::numeric,         '54.204'),
      (54390::numeric,         '54.390'),
      (68850::numeric,         '68.850'),
      (999999::numeric,        '999.999'),
      (1000000::numeric,       '1.000.000'),
      (1234567890::numeric,    '1.234.567.890'),
      (1.5::numeric,           '1,50'),
      (10000.5::numeric,       '10.000,50'),
      (1234.5::numeric,        '1234,50'),
      (99999.999::numeric,     '100.000,00'),
      (9999.996::numeric,      '10.000,00'),
      (9999.001::numeric,      '9999,00'),
      (0.004::numeric,         '0,00'),
      (1234567.891::numeric,   '1.234.567,89')
    ) as t(entrada, esperado)
  loop
    if public.lw_importe_texto(v.entrada) is distinct from v.esperado then
      raise exception 'lw_importe_texto(%) devuelve % y lwImporteCanonico() dice %',
        v.entrada, public.lw_importe_texto(v.entrada), v.esperado;
    end if;
  end loop;
  if public.lw_importe_texto(null) is not distinct from '0' then
    raise exception 'lw_importe_texto(null) tiene que ser NULL, no "0"';
  end if;
end $$;

-- ── 2) el trigger nuevo, BEFORE INSERT y solo lectura sobre unidades/contratos ──
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

  -- Regla 2: el cliente nunca manda este cálculo. Se limpia SIEMPRE en
  -- cuanto se sabe que es un INSERT de Bloqueo, antes de cualquier `return`
  -- por falta de parcela/proyecto — si no, un Bloqueo sin traspaso real
  -- podría colar un carta_cobrado_importe inventado sin que este trigger
  -- llegara nunca a pisarlo.
  new.datos := new.datos #- '{fields,carta_cobrado_importe}'
                         #- '{fields,carta_cobrado_numeros}'
                         #- '{fields,carta_cobrado_sobrante}';

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then
    return new;
  end if;

  -- Solo LECTURA: qué Carta de Reserva ocupa hoy cada parcela de este
  -- Bloqueo. `like 'carta_reserva%'` — el mismo criterio que
  -- sincroniza_unidad_contrato desde el 10-sep (LAW-48: la lista a mano de
  -- tres tipos se quedó corta dos veces), cubre las cinco variantes de hoy y
  -- cualquiera que se dé de alta mañana. NO comprueba que el comprador
  -- coincida: esa autoridad es del trigger AFTER (ver la nota grande de
  -- arriba) y si no coincide, revienta y deshace este INSERT entero.
  select coalesce(array_agg(distinct c.id), '{}'),
         coalesce(array_agg(distinct c.numero), '{}')
    into cartas_ids, cartas_nums
    from public.unidades u
    join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = any(cods)
     and c.tipo like 'carta_reserva%';

  if coalesce(array_length(cartas_ids, 1), 0) = 0 then
    return new;
  end if;

  -- Suma del cobrado REAL (solo recibís con justificante, nunca un importe
  -- supuesto) de TODAS las Cartas de origen distintas — multi-parcela puede
  -- traer más de una.
  select coalesce(sum(public.contrato_cobrado(cid)), 0) into v_cobrado
    from unnest(cartas_ids) as cid;

  if v_cobrado <= 0 then
    return new;   -- regla 5: nada cobrado, nada que escribir
  end if;

  -- Tope: nunca más que el precio_total de ESTE Bloqueo (el suelo).
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

  -- Reparto en cascada sobre los hitos que YA traiga el INSERT (los que
  -- calculó recalcularMontosHitos() en el navegador con el 50/50 normal —
  -- ver hitos_fechas.js), EN EL ORDEN EN QUE ESTÁN. Nunca un monto negativo.
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

-- destructivo-ok: DROP defensivo de un trigger que hoy NO existe en producción
-- (comprobado con list_migrations antes de escribir esto) — solo por si esta
-- migración se reaplica alguna vez; no borra nada que exista.
drop trigger if exists trg_carta_cobrado_al_bloquear on public.contratos;
create trigger trg_carta_cobrado_al_bloquear
  before insert on public.contratos
  for each row execute function public.carta_cobrado_al_bloquear();

comment on function public.carta_cobrado_al_bloquear() is
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero cobrado, descuenta ese abono del propio Bloqueo (fields.carta_cobrado_*, hitos en cascada). Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción) y si falla deshace este INSERT entero. 17-sep-2026, revisión previa #24.';

-- ── comprobación tras aplicar ────────────────────────────────────────────────
--   select tgname, tgtype from pg_trigger
--    where tgrelid = 'public.contratos'::regclass and tgname = 'trg_carta_cobrado_al_bloquear';
--   -- tgtype impar (BEFORE) y solo INSERT.
--   select proname from pg_proc where proname in ('lw_importe_texto','carta_cobrado_al_bloquear');
