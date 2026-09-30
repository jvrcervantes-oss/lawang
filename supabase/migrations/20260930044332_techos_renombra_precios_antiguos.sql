-- destructivo-ok: solo renombra dos columnas SIN USO (no borra datos). Se aplica DESPUÉS de aterrizar el JS que ya no las lee.
-- Techos como suplemento (30-sep-2026): precio_ahora/precio_2027 de modelo_techos dejaron de ser fuente en
-- 20260930044032. Se renombran para que cualquier lector olvidado falle alto en vez de enseñar un precio viejo.
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
              where s.nspname = 'public' and p.prosrc ~ '\mprecio_(ahora|2027)\M') then
    raise exception 'ABORTA: alguna función sigue leyendo precio_ahora/precio_2027';
  end if;
end $$;
alter table public.modelo_techos rename column precio_ahora to precio_ahora_antiguo;
alter table public.modelo_techos rename column precio_2027 to precio_2027_antiguo;
comment on column public.modelo_techos.precio_ahora_antiguo is 'SIN USO desde el 30-sep-2026: el techo es un suplemento (suplemento_ahora). Se conserva hasta que el owner autorice borrarla.';
comment on column public.modelo_techos.precio_2027_antiguo is 'SIN USO desde el 30-sep-2026: el techo es un suplemento (suplemento_2027). Se conserva hasta que el owner autorice borrarla.';
