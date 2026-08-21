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

  d := position('.' in reverse(s)); c := position(',' in reverse(s));
  if d = 0 and c = 0 then
    sep := '';
  elsif d > 0 and (c = 0 or d < c) then
    sep := '.';
  else
    sep := ',';
  end if;

  if sep <> '' then
    resto := reverse(split_part(reverse(s), sep, 1));
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
    raise exception 'sin numero tiene que ser NULL y no 0';
  end if;
end $$;;
