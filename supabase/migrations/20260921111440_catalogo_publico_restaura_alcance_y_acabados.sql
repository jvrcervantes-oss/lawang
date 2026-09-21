/*
 * Fix urgente 21-sep-2026: la migracion anterior (catalogo_publico_extras_incluye_orden)
 * reescribio catalogo_publico() partiendo de una version VIEJA de la funcion (la de
 * 20260907053801, antes de que 20260907060211_catalogo_modelos_alcance_de_obra la ampliara)
 * y se dejo fuera 'alcance'/'acabados' -- Dali se quedo sin alcance de obra en la web
 * publica. Restaura las dos claves que faltaban, conserva los extras con nombre/desc/orden.
 * Verificado campo a campo contra 20260907060211 antes de aplicar.
 */
create or replace function public.catalogo_publico()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.slug, x.ficha), '{}'::jsonb)
    from (
      select m.slug,
             jsonb_strip_nulls(jsonb_build_object(
               'nombre',             m.nombre,
               'dormitorios',        m.dormitorios,
               'banos',              m.banos,
               'villa_m2',           m.villa_m2,
               'terraza_m2',         m.terraza_m2,
               'sub',                m.descripcion,
               'moneda',             m.moneda,
               'desde',              m.precio_construccion,
               'renders_pendientes', nullif(m.renders_pendientes, false),
               'alcance',            m.alcance,
               'acabados',           m.acabados,
               'techos', (select jsonb_object_agg(t.clave, jsonb_build_object(
                                   'nombre', t.nombre, 'desc', t.descripcion,
                                   'now',    t.precio_ahora, 'y2027', t.precio_2027))
                            from public.modelo_techos t where t.modelo_id = m.id),
               'extras', (select jsonb_object_agg(e.clave, jsonb_build_object(
                                   'nombre', e.nombre, 'desc', e.descripcion,
                                   'precio', me.precio, 'orden', e.orden))
                            from public.modelo_extras me
                            join public.extras e on e.id = me.extra_id
                           where me.modelo_id = m.id and me.disponible and e.activo)
             )) as ficha
        from public.modelos m
       where m.publicado and m.activo
    ) x
$$;

revoke all on function public.catalogo_publico() from public;
grant execute on function public.catalogo_publico() to anon, authenticated;

comment on function public.catalogo_publico() is
  'Lo único del catálogo que ve un anónimo: modelos publicados, con specs, techos, extras (nombre+descripción+precio+orden), alcance de obra y acabados. Nunca notas, ni precios por proyecto (modelos_villa), ni nada de unidades. Declarada en departamentos/seguridad/rls_publico.txt.';
;
