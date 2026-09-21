/*
 * modelo_fotos_publico() -- RPC publica para las fotos de /modelo/<id> (21-sep-2026).
 *
 * MOTIVO: la landing publica leia sus fotos con lw_modelo_imgs() escaneando
 * assets/img/buildings/<id>/web/ EN DISCO -- nadie las podia subir desde la intranet, hacia
 * falta un deploy para anadir o quitar una. La tabla real ya existe: `deck_fotos`
 * (ambito='modelo'), alimentada desde /intranet/modelos/ -> "Fotos del deck...", que ya
 * sube al bucket publico `deck` (convierte a WebP, quita EXIF/GPS, exige pie en ingles).
 * Hoy los 6 modelos publicados en la web YA tienen fotos reales ahi (comprobado 21-sep:
 * dali=8, dune=8, dream=10, temple=11, trinity=11, loftbung=2) -- Temple y Trinity no
 * tienen ninguna carpeta en disco y su ficha publica mostraba "renders en camino" pese a
 * tener 11 fotos reales cada uno sin usar.
 *
 * `deck_fotos` esta detras de RLS a es_agente() (revocada de anon): esta funcion es la
 * misma ventana de solo lectura que ya usa catalogo_publico() para `modelos` -- security
 * definer, columnas elegidas a mano, solo modelos con publicado=true. NUNCA `creado_por`
 * (interno). Las filas ambito='proyecto' (fotos de investor deck que no son de un modelo)
 * quedan FUERA a proposito: esas las sirve investor_deck_fotos, con su propio gate por
 * proyecto abierto -- mezclar los dos daria acceso a fotos de proyecto sin ese gate.
 *
 * EL DATO TIENE UN DUENO: `deck_fotos` la edita el equipo desde /intranet/modelos/. Esta
 * funcion es una ventana, nunca una copia -- una foto nueva subida ahi aparece en
 * /modelo/<id> en el siguiente fetch (cache de 5 min en modelo/datos.php, mismo patron que
 * catalogo.php), sin tocar codigo ni desplegar nada.
 *
 * URL publica de cada foto: SB_URL + '/storage/v1/object/public/deck/' + path (mismo
 * patron ya usado en contracts/assets/deck_fotos.js:367 -- el bucket `deck` es publico por
 * diseno, confirmado en la migracion 20260911093239_deck_bucket_publico.sql).
 */
create or replace function public.modelo_fotos_publico()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_object_agg(x.slug, x.fotos), '{}'::jsonb)
    from (
      select m.slug,
             (select jsonb_agg(jsonb_build_object(
                       'path',  df.path,
                       'pie',   df.pie ->> 'en',
                       'tipo',  df.tipo,
                       'orden', df.orden
                     ) order by df.orden)
                from public.deck_fotos df
               where df.ambito = 'modelo' and df.modelo_id = m.id
             ) as fotos
        from public.modelos m
       where m.publicado and m.activo
    ) x
   where x.fotos is not null
$$;

revoke all on function public.modelo_fotos_publico() from public;
grant execute on function public.modelo_fotos_publico() to anon, authenticated;

comment on function public.modelo_fotos_publico() is
  'Fotos publicas de cada modelo publicado (deck_fotos, ambito=modelo), para /modelo/<id>. Nunca creado_por, nunca filas ambito=proyecto (esas son de investor_deck_fotos). 21-sep-2026.';
;
