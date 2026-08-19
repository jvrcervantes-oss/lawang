-- ════════════════════════════════════════════════════════════════════════════
-- EL DINERO DEJA DE SER TEXTO — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- `contrato_vencimientos.monto` y `.pct` eran `text`, y son las DOS únicas
-- columnas de dinero de toda la base que lo eran. Dentro conviven «5000» y
-- «22.250»: qué significa ese punto depende de quién lo lea, y eso ya ha
-- costado dinero en este estudio (el depósito a 500 en la web y a 1.000 en el
-- motor del bot, cobrando el doble durante una semana).
--
-- QUÉ SIGNIFICA EL PUNTO AQUÍ, comprobado contra la aritmética del contrato y
-- no a ojo — RP00012 tiene monto «42.215» con pct 100 sobre un precio_total de
-- 42.215 €, y CC00029 «17.592» con 32,58% sobre 54.000 (= 17.593). Es
-- SEPARADOR DE MILES en los 13 casos que lo llevan. Ninguno es decimal.
--
-- ⚠️ POR QUÉ NO BASTA CON UN `::numeric`: Postgres castea '22.250' a 22,25 sin
-- rechistar. Convertir a lo bruto habría dividido esos importes por mil y nada
-- habría dado error. Se convierte con la MISMA regla que usa la interfaz.

-- ── la regla de leer un importe, gemela de lwParseImporte ───────────────────
-- ⚠️ Es la SEGUNDA copia de esa regla, y eso normalmente está prohibido aquí.
-- Se acepta porque los dos lados leen lo mismo desde sitios distintos —el
-- navegador lee lo que el agente teclea, la base lee lo que quedó guardado— y
-- porque el bloque de autocomprobación de abajo lleva LOS MISMOS CASOS que
-- `assets/dinero.test.js`: si una de las dos deriva, esta migración no aplica.
create or replace function public.lw_importe(p_txt text)
returns numeric
language plpgsql
immutable
as $$
declare
  v_bruto text := coalesce(p_txt, '');
  v_neg   boolean := left(btrim(v_bruto), 1) = '-';
  s       text;
  d       int; c int; sep text; resto text;
begin
  s := regexp_replace(v_bruto, '[^0-9.,]', '', 'g');
  if s !~ '[0-9]' then return null; end if;

  d := length(s) - length(regexp_replace(reverse(s), '^[^.]*', '')) ;  -- posición del último '.'
  d := position('.' in reverse(s)); c := position(',' in reverse(s));
  -- en la cadena invertida, el que aparece ANTES es el que estaba más a la derecha
  if d = 0 and c = 0 then
    sep := '';
  elsif d > 0 and (c = 0 or d < c) then
    sep := '.';
  else
    sep := ',';
  end if;

  if sep <> '' then
    resto := split_part(reverse(s), sep, 1);
    resto := reverse(resto);
    -- separador repetido = miles · exactamente 3 dígitos detrás = miles
    if array_length(string_to_array(s, sep), 1) > 2 or resto ~ '^[0-9]{3}$' then
      sep := '';
    end if;
  end if;

  if sep = '' then
    s := regexp_replace(s, '[.,]', '', 'g');
  else
    s := replace(replace(s, case when sep = '.' then ',' else '.' end, ''), sep, '.');
  end if;

  if s !~ '^[0-9]*\.?[0-9]*$' or s in ('', '.') then return null; end if;
  return case when v_neg then -s::numeric else s::numeric end;
end $$;

revoke all on function public.lw_importe(text) from public, anon;
grant execute on function public.lw_importe(text) to authenticated;

-- ── autocomprobación: los MISMOS casos que assets/dinero.test.js ───────────
do $$
declare
  v record;
begin
  for v in select * from (values
      ('-5.000',      -5000::numeric),
      ('1.2345',       1.2345),
      ('12.34.56',     123456),
      ('1,2,3',        123),
      ('164.000',      164000),
      ('1,500',        1500),
      ('79.000,50',    79000.50),
      ('1.500,50',     1500.50),
      ('1.000.000',    1000000),
      ('5,00',         5),
      ('.5',           0.5),
      (',75',          0.75),
      ('€ 79.000',     79000),
      ('1 500',        1500),
      ('0',            0),
      ('22.250',       22250),
      ('17.592',       17592)
    ) as t(entrada, esperado)
  loop
    if public.lw_importe(v.entrada) is distinct from v.esperado then
      raise exception 'lw_importe(%) devuelve % y la interfaz dice %',
        v.entrada, public.lw_importe(v.entrada), v.esperado;
    end if;
  end loop;
  if public.lw_importe('') is not null or public.lw_importe('abc') is not null
     or public.lw_importe(null) is not null then
    raise exception 'sin numero tiene que ser NULL y no 0: un contrato sin precio no es un contrato de 0 EUR';
  end if;
end $$;

-- ── la conversión ──────────────────────────────────────────────────────────
alter table public.contrato_vencimientos
  alter column monto type numeric using public.lw_importe(monto),
  alter column pct   type numeric using public.lw_importe(pct);

comment on column public.contrato_vencimientos.monto is
  'Importe del hito, NUMERIC desde el 19-ago-2026. Era text y convivian «5000» y «22.250»: que significaba ese punto dependia de quien lo leyera.';

-- Y el trigger que las escribe aplica la regla al copiar del contrato. Es el
-- ÚNICO que puede: no hay GRANT de INSERT ni de UPDATE sobre estas columnas
-- para nadie (ver vencimientos.sql), así que aquí es donde tiene que estar.
-- El hito del contrato lo teclea una persona y sigue siendo texto, como debe.
--   … public.lw_importe(h.value->>'pct'), public.lw_importe(h.value->>'monto') …

-- ── verificado ─────────────────────────────────────────────────────────────
-- Ensayo antes de convertir, fila por fila: 16 filas cambian y las 16 son
-- separador de miles — 13.690→13690 · 15.000→15000 · 17.592→17592 ·
-- 20.000→20000 · 22.250→22250 · 25.000→25000 · 42.215→42215 · 9.000→9000.
-- Ningún `pct` cambia de valor.
--
-- Y en pantalla, después de migrar: Vencimientos da **cartera 452.170 € y
-- cobrado 263.132 €**, exactamente las mismas cifras que antes. La conversión
-- es transparente para la interfaz porque `lwParseImporte` lee igual de bien un
-- número que el texto que había.
