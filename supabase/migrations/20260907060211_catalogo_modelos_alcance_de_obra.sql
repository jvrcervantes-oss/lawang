/* Alcance de obra y acabados al catálogo — 7-sep-2026.
   Fichero canónico: supabase/migrations/<version>_catalogo_modelos_alcance_de_obra.sql

   POR QUÉ. La web pasa a leer el catálogo (decisión del owner: fuente única
   desde el día 1), y `modelo/modelos.php` publica dos cosas que el catálogo
   todavía no sabía: `alcance` (qué incluye y qué no incluye la obra) y
   `acabados`. Sustituir el fichero sin traérselas dejaría la ficha de Dali sin
   su alcance de obra — una regresión con otra piel, que es justo lo que prohíbe
   la Regla 0 bis de contexto/suite_lawang.md.

   Solo Dali las tiene, y eso NO se extrapola: el comentario de modelos.php dice
   que `acabados`/`alcance` solo se rellenan con lo verificado en el anexo de
   obra del modelo, y hoy solo existe el de Dali. Copiar su alcance a los otros
   cuatro sería inventarse un contrato.

   jsonb y no tablas hijas a propósito: son listas editoriales que nadie cruza
   ni agrega — nada hace un join contra «Exterior terrace». Una tabla por línea
   de texto sería estructura sin ninguna pregunta que responda.

   -- destructivo-ok: `drop policy` no aparece; el único DROP es implícito en el
   `create or replace function` de catalogo_publico(), que sustituye la función
   por una versión que devuelve DOS claves más y ninguna menos. Verificado
   contra la anterior campo a campo antes de aplicar. */

alter table public.modelos add column if not exists alcance  jsonb;
alter table public.modelos add column if not exists acabados jsonb;

comment on column public.modelos.alcance is
  'Qué incluye y qué no incluye la obra, tal y como lo publica la ficha: {incluido:[...], no_incluido:[...]}. Solo se rellena con lo verificado en el ANEXO DE OBRA de ese modelo — extrapolarlo de otro modelo es inventarse un contrato.';
comment on column public.modelos.acabados is
  'Acabados descritos en la ficha: [{n, d}]. Misma regla que `alcance`: solo lo verificado en el anexo de obra del propio modelo.';

update public.modelos
   set alcance = jsonb_build_object(
         'incluido', jsonb_build_array(
           'Main building per the project design',
           'Roof in the finish you choose',
           'Overflow pool in sukabumi stone',
           'Exterior terrace',
           'Air conditioning and hot water',
           'PLN 3,500W electrical connection',
           'Structure, architecture and installations'),
         'no_incluido', jsonb_build_array(
           'Interior furniture: beds, wardrobes, kitchen, tables',
           'Decor and textiles')),
       acabados = jsonb_build_array(jsonb_build_object(
         'n', 'Alang-alang',
         'd', 'Traditional Balinese thatch roofing. The look most integrated into the tropical setting.'))
 where slug = 'dali';

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
               'extras', (select jsonb_object_agg(e.clave, me.precio)
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
  'Lo único del catálogo que ve un anónimo: modelos publicados, con specs, techos, extras, alcance de obra y acabados. Nunca notas, ni precios por proyecto (modelos_villa), ni nada de unidades. Declarada en departamentos/seguridad/rls_publico.txt.';;
