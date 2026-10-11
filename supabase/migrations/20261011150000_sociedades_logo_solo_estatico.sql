-- AXW-253 (11-oct-2026, Backend; revisión previa de Seguridad #264) · el logo de una sociedad emisora es un fichero estático
-- de /contracts/assets/brand/; nunca una URL. Gemela de erp/migraciones/20261011150000_sociedades_logo_solo_estatico.sql del
-- maestro (misma regla en las dos bases: arreglo compartido Lawang↔maestro).
--
-- Por qué: `sociedad_guarda` (cuerpo de 20260930210000 l.108-111; 20261008970100 solo le cambió la puerta de rol por
-- sustitución sobre la definición viva, su l.14; medido en vivo el 11-oct: la definición sigue nombrando object/public/sociedades)
-- admite dos formas de logo: la ruta estática y la URL PÚBLICA del bucket
-- `sociedades` de este proyecto. Pero el bucket es PRIVADO (medido el 11-oct-2026: public=false, 0 objetos, ninguna política),
-- así que una URL de esa forma se guardaría y saldría rota en cada factura y PDF, sin error. Quien las producía, la clase
-- `sociedad_logo` de la edge `ficheros`, se retira en este mismo commit (su pantalla, ajustes-sociedades.js, se quitó el 7-oct
-- en 7b685aa0). Las 3 sociedades de hoy usan ruta estática (lawang-logo-v3-dark.png, sandalwoods-lockup.png ×2): no cambian.
-- La regla va en un trigger de la COLUMNA, no en la RPC, para que tampoco se la salte un update con service_role. Expresión
-- idéntica a la de la RPC: en el nombre no caben `/`, `%`, `?`, `#` ni espacios (sin salto de carpeta ni query string).
-- Mira solo el valor que CAMBIA; antes cuenta las filas que ya no cumplen y, si hay alguna, PARA y las nombra.
-- El bucket `sociedades` queda reservado para S9 (subir el logo desde Ajustes; encargos/20260930_erp_ajustes_pantalla.md;
-- 11-oct-2026): privado, sin políticas, solo service_role. No se borra aquí.
--
-- Dueño del dato: `sociedades.logo` es de la sociedad (lo escribe `sociedad_guarda`, solo el propietario); facturas y PDF lo
-- LEEN vivo (cosmética, intranet/facturas/documento.js l.147-163). Los contratos no leen esta columna: firma-submit
-- usa SOCIEDADES solo para la factura (documentoPagina, supabase/functions/firma-submit/index.ts l.551 y l.680) y el PDF del contrato
-- sale de su diseño (contracts/assets/documento_diseno.js, logos de assets/brand/).
--
-- Y en `sociedad_guarda` (sustitución exacta sobre la definición viva, como 20261008970100): quita la rama de la URL pública
-- (y su constante v_url_logo) y el texto «subida desde Ajustes» del error, y añade una línea que nombra al trigger: las dos
-- copias de la regla se nombran entre sí (contexto/suite_lawang.md, LAW-51/LAW-50 punto 5). Medido en vivo el 11-oct: cada
-- texto sustituido aparece exactamente 1 vez en la definición.
-- NO SE APLICA sin el OK del orquestador (límite del owner del 11-oct; fila AXW-253 de contexto/pendientes.md). Hasta entonces
-- tools/salud_lawang.py la cuenta como «fichero sin registrar»: es lo esperado.
--
-- REVERTIR: drop trigger sociedades_logo_valida on public.sociedades; drop function public._sociedades_logo_valida();
--   todo junto (trigger, función y la sustitución inversa en sociedad_guarda): supabase/reversion_f2/REVERSION_axw253_20261011150000.sql
-- PRUEBA tras aplicarla: contracts/sql/prueba_axw253_logo.sql, entera en execute_sql (prueba_ajustes_sociedades.sql está desfasada
-- desde el bloque 12 y no llega al final: fila LAW-535).

do $do$
declare v_malas text;
begin
  if exists (select 1 from storage.buckets where id = 'sociedades' and public) then
    raise exception 'El bucket «sociedades» es PÚBLICO en esta base: hazlo privado antes (los logos se sirven como ficheros estáticos)';
  end if;
  select string_agg(format('%s=%s', s.clave, s.logo), ', ' order by s.clave) into v_malas
    from public.sociedades s
   where s.logo is not null and s.logo !~* '^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\.(png|jpe?g|webp)$';
  if v_malas is not null then
    raise exception 'Sociedades con un logo que no es un fichero de /contracts/assets/brand/: %', v_malas
      using hint = 'Corrígelas a mano (decisión de quien conoce la marca) y vuelve a aplicar.';
  end if;
end $do$;

create or replace function public._sociedades_logo_valida() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Misma regla que sociedad_guarda (su bloque del logo): si cambia una, cambia la otra.
  if new.logo is not null
     and (tg_op = 'INSERT' or new.logo is distinct from old.logo)
     and new.logo !~* '^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\.(png|jpe?g|webp)$' then
    raise exception 'El logo tiene que ser una imagen PNG, JPEG o WebP de /contracts/assets/brand/ (nunca una dirección de fuera)'
      using errcode = '22023', hint = 'logo_no_admitido';
  end if;
  return new;
end $$;
revoke all on function public._sociedades_logo_valida() from public, anon, authenticated;

create or replace trigger sociedades_logo_valida before insert or update of logo on public.sociedades
  for each row execute function public._sociedades_logo_valida();

-- sociedad_guarda: la regla del logo, igual que el trigger. Sustitución exacta sobre la definición viva (1 coincidencia o PARA).
do $m$
declare d text; viejo text; nuevo text; n int;
begin
  d := pg_get_functiondef('public.sociedad_guarda(text,jsonb,boolean)'::regprocedure);
  viejo := E'  if n_logo is distinct from s.logo and n_logo is not null and not (\n'
        || E'       n_logo ~* ''^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\\.(png|jpe?g|webp)$''\n'
        || E'       or n_logo ~ (v_url_logo || v_clave || ''/[0-9a-f]{64}\\.(png|jpg|webp)$'')) then\n'
        || E'    raise exception ''El logo tiene que ser una imagen PNG, JPEG o WebP subida desde Ajustes (nunca un SVG ni una dirección cualquiera)''';
  nuevo := E'  -- Misma regla que el trigger sociedades_logo_valida (20261011150000, AXW-253): si cambia una, cambia la otra.\n'
        || E'  if n_logo is distinct from s.logo and n_logo is not null and not (\n'
        || E'       n_logo ~* ''^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\\.(png|jpe?g|webp)$'') then\n'
        || E'    raise exception ''El logo tiene que ser una imagen PNG, JPEG o WebP de /contracts/assets/brand/ (nunca un SVG ni una dirección de fuera)''';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'sociedad_guarda (logo): se esperaba 1 coincidencia y hay %', n; end if;
  d := replace(d, viejo, nuevo);
  viejo := E'  v_url_logo constant text := ''^https://vtulllundrfennhjddhc\\.supabase\\.co/storage/v1/object/public/sociedades/'';\n';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'sociedad_guarda (v_url_logo): se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, '');
end $m$;
