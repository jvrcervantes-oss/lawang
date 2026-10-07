-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 12 · migracion 2 (7-oct-2026): SOCIEDADES EMISORAS SOLO PARA EL PROPIETARIO.
--   Orden del owner (7-oct-2026): las sociedades emisoras no van en Ajustes («creo que no hace falta que este») y su pantalla propia es solo del propietario.
--   * `sociedad_guarda` (editar y dar de alta): es_propietario(). Se retira el permiso que el bloque 2 dio al super de empresa para editar la sociedad de su empresa
--     y el que tenia cualquier super global (Andrea, Pepito): la sociedad es lo que imprime cada documento.
--   * `sociedades_ajustes_datos` (la lista con el recuento de documentos de cada sociedad): es_propietario(). Mismo contrato de salida (`puede_escribir`, `sociedades`);
--     `puede_escribir` es true para quien entra (solo entra el propietario) y se retira `puede_escribir_esta`.
--   * `sociedades_log` (historial de cambios): lo lee el propietario. Con eso `sociedad_super_de` se queda sin llamador y se retira.
--   NO cambia (lo necesitan los documentos y la emision): `sociedades_visibles()`, la policy «sociedades: agentes», `sociedad_en_alcance`, `empresa_de_sociedad`,
--   `_empresa_sociedad`, los emisores de facturas/recibis ni la edge `ficheros` (logo y firma: sigue pidiendo es_super_admin con el JWT del usuario).
-- destructivo-ok: drop function sociedad_super_de(text) (sin llamador tras alter policy; la reversion la recrea); create or replace de 2 funciones; alter policy x1
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b12.sql

-- sociedad_guarda: solo cambia la puerta (el bloque entero de comprobacion de rol); sustitucion exacta sobre la definicion viva.
do $m$
declare d text; viejo text; nuevo text; n int;
begin
  d := pg_get_functiondef('public.sociedad_guarda(text,jsonb,boolean)'::regprocedure);
  viejo := E'  perform public._super_o_empresa();\n'
        || E'  if not public.es_super_admin() then\n'
        || E'    -- super_admin_empresa: solo EDITA la sociedad ligada a su empresa; dar de alta una sociedad nueva es global (no tiene empresa a la que ligarse)\n'
        || E'    if p_nueva or public._empresa_sociedad(v_clave) is null or not public.es_super_admin_de(public._empresa_sociedad(v_clave)) then\n'
        || E'      raise exception ''Solo puedes editar la sociedad de tu empresa; las demas y las altas son del propietario o de un super admin global'' using errcode = ''42501'';\n'
        || E'    end if;\n'
        || E'  end if;';
  nuevo := E'  if not public.es_propietario() then\n'
        || E'    raise exception ''Las sociedades emisoras solo las edita el propietario'' using errcode = ''42501'';\n'
        || E'  end if;';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'sociedad_guarda: se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, nuevo);
end $m$;

create or replace function public.sociedades_ajustes_datos() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  v jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'sociedades_ajustes_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.es_propietario() then
    raise exception 'Las sociedades emisoras son solo del propietario.' using errcode = '42501';
  end if;
  with d as (
    select f.clave, jsonb_build_object('total', sum(f.total)::int, 'abiertos', sum(f.abiertos)::int,
             'detalle', jsonb_object_agg(f.tabla, jsonb_build_object('total', f.total, 'abiertos', f.abiertos))) as j
      from public._sociedad_docs_filas(null) f group by f.clave)
  select coalesce(jsonb_agg(to_jsonb(s)
           || jsonb_build_object('documentos', coalesce(d.j, jsonb_build_object('total', 0, 'abiertos', 0, 'detalle', '{}'::jsonb)))
           order by s.orden, s.clave), '[]'::jsonb)
    into v
    from public.sociedades s left join d on d.clave = s.clave;
  return jsonb_build_object('puede_escribir', true, 'sociedades', v);
end $function$;

alter policy "sociedades_log: leer solo super" on public.sociedades_log
  using (public.es_propietario());

drop function public.sociedad_super_de(text);
