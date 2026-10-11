-- Reversión de 20261011150000_sociedades_logo_solo_estatico (AXW-253, 11-oct-2026): quita el trigger que exige un logo de
-- /contracts/assets/brand/ y devuelve a `sociedad_guarda` la rama de la URL pública del bucket `sociedades` (con su constante
-- v_url_logo y el texto «subida desde Ajustes»), por la sustitución inversa sobre la definición viva (1 coincidencia o PARA).
-- Solo tiene sentido si se vuelve a servir el logo desde el bucket como URL pública, y el bucket es PRIVADO desde el 1-oct.
-- destructivo-ok: drop del trigger y de su función (no guardan datos); reescribe sociedad_guarda; no toca filas.
begin;

drop trigger if exists sociedades_logo_valida on public.sociedades;
drop function if exists public._sociedades_logo_valida();

do $m$
declare d text; viejo text; nuevo text; n int;
begin
  d := pg_get_functiondef('public.sociedad_guarda(text,jsonb,boolean)'::regprocedure);
  viejo := E'  -- Misma regla que el trigger sociedades_logo_valida (20261011150000, AXW-253): si cambia una, cambia la otra.\n'
        || E'  if n_logo is distinct from s.logo and n_logo is not null and not (\n'
        || E'       n_logo ~* ''^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\\.(png|jpe?g|webp)$'') then\n'
        || E'    raise exception ''El logo tiene que ser una imagen PNG, JPEG o WebP de /contracts/assets/brand/ (nunca un SVG ni una dirección de fuera)''';
  nuevo := E'  if n_logo is distinct from s.logo and n_logo is not null and not (\n'
        || E'       n_logo ~* ''^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\\.(png|jpe?g|webp)$''\n'
        || E'       or n_logo ~ (v_url_logo || v_clave || ''/[0-9a-f]{64}\\.(png|jpg|webp)$'')) then\n'
        || E'    raise exception ''El logo tiene que ser una imagen PNG, JPEG o WebP subida desde Ajustes (nunca un SVG ni una dirección cualquiera)''';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'reversión sociedad_guarda (logo): se esperaba 1 coincidencia y hay %', n; end if;
  d := replace(d, viejo, nuevo);
  -- la constante iba justo delante de v_hex (20260930210000 l.14-15; medido en vivo el 11-oct: v_hex 1 vez, detrás de v_url_logo)
  viejo := E'  v_hex constant text := ';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'reversión sociedad_guarda (v_hex): se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo,
    E'  v_url_logo constant text := ''^https://vtulllundrfennhjddhc\\.supabase\\.co/storage/v1/object/public/sociedades/'';\n' || viejo);
end $m$;

commit;
