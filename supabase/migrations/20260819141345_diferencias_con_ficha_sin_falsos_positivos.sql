-- Primera versión: 44 documentos "desactualizados", y casi todos falsos.
-- Dos clases de ruido, las dos por diseño:
--   1. MULTI-COMPRADOR. Desde el 19-ago un documento de varios adquirientes dice
--      «A · B» y lleva «A: P1 · B: P2» en identidad — correcto. Compararlo con la
--      ficha del adquiriente I lo marcaba como divergente SIEMPRE.
--   2. CAMPO QUE EL DOCUMENTO NO IMPRIME. Que la ficha sepa el domicilio y el
--      documento no lo lleve no es una contradicción: es que ahí no va.
-- Lo que de verdad importa es que el documento diga algo DISTINTO, no que calle.
-- Un aviso que salta siempre se ignora, y entonces no sirve para el caso real.
create or replace function public.diferencias_con_ficha(p_doc jsonb, p_ficha jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(jsonb_build_object('campo', k, 'documento', d, 'ficha', f)
                            order by k), '[]'::jsonb)
    from (
      select k,
             nullif(btrim(p_doc->>k), '')   as d,
             nullif(btrim(p_ficha->>k), '') as f
        from jsonb_object_keys(p_ficha) k
    ) t
   where f is not null
     and d is not null                              -- el documento que calla no contradice
     and d not like '%' || chr(183) || '%'          -- «A · B»: varios compradores, es correcto
     and lower(regexp_replace(d, '[^a-z0-9@.]', '', 'gi'))
      is distinct from lower(regexp_replace(f, '[^a-z0-9@.]', '', 'gi'));
$$;;
