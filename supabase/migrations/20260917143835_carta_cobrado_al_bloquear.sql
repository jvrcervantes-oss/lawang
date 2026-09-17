-- El Bloqueo de Parcela descuenta lo que la Carta de Reserva ya cobró —
-- 17-sep-2026, revisión previa #24 (Legal + Administración + Seguridad).
-- Ver contracts/sql/carta_cobrado_al_bloquear.sql para la nota completa.

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
  mostrar_decimales := (n <> trunc(n));
  v := round(n, 2);
  neg := v < 0;
  v := abs(v);
  entero := trunc(v)::bigint;
  centimos := round((v - trunc(v)) * 100)::int;
  if centimos = 100 then entero := entero + 1; centimos := 0; end if;

  entero_txt := entero::text;
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
  'Importe -> texto en el formato canónico de la suite (es-ES, punto de miles solo desde 10.000, coma decimal). Gemelo de lwImporteCanonico() en contracts/assets/dinero.js; misma tabla de casos en el DO $$ de la migración original.';

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

  new.datos := new.datos #- '{fields,carta_cobrado_importe}'
                         #- '{fields,carta_cobrado_numeros}'
                         #- '{fields,carta_cobrado_sobrante}';

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then
    return new;
  end if;

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

-- destructivo-ok: DROP defensivo de un trigger que hoy NO existe en producción
-- (comprobado con list_migrations antes de escribir esto) — solo por si esta
-- migración se reaplica alguna vez; no borra nada que exista.
drop trigger if exists trg_carta_cobrado_al_bloquear on public.contratos;
create trigger trg_carta_cobrado_al_bloquear
  before insert on public.contratos
  for each row execute function public.carta_cobrado_al_bloquear();

comment on function public.carta_cobrado_al_bloquear() is
  'BEFORE INSERT en contratos: si este Bloqueo de Parcela (reserva_parcela) traspasa de verdad su parcela desde una Carta de Reserva con dinero cobrado, descuenta ese abono del propio Bloqueo (fields.carta_cobrado_*, hitos en cascada). Solo lectura sobre unidades/contratos — la validación de que el traspaso es legítimo (mismo comprador) la hace en exclusiva sincroniza_unidad_contrato() (AFTER, misma transacción) y si falla deshace este INSERT entero. 17-sep-2026, revisión previa #24.';
