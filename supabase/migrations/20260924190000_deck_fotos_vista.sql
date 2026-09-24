-- 24-sep-2026 · Vista de cada foto de MODELO en su ficha pública (/modelo/<slug>).
--
-- Por qué: la ficha elegía la planta, el techo de bambú, la cocina… buscando texto en
-- el pie («top view», «bamboo exterior»). Los pies reales variaban y /modelo/dune
-- enseñaba la vista aérea como planta y la planta como techo de bambú. Ahora quien
-- gestiona las fotos marca en la intranet qué vista es cada una; el pie queda solo
-- como respaldo para las fotos sin marcar.

alter table public.deck_fotos add column vista text;

alter table public.deck_fotos add constraint deck_fotos_vista_check
  check (vista in ('planta','techo_bambu','techo_sirap','interior','cocina','bano','aerea'));

-- Solo las fotos de un modelo tienen ficha pública donde salir.
alter table public.deck_fotos add constraint deck_fotos_vista_solo_modelo
  check (vista is null or ambito = 'modelo');

-- Una foto por vista y modelo: dos «plantas» obligarían a la web a adivinar otra vez.
create unique index deck_fotos_vista_unica
  on public.deck_fotos (modelo_id, vista) where vista is not null;

comment on column public.deck_fotos.vista is
  'Qué vista es esta foto en la ficha pública del modelo. Una por modelo; se cambia con deck_foto_fijar_vista() para que la anterior la pierda en la misma transacción.';

-- Relleno inicial desde los pies de hoy. «sirap» y no «ulin»: el techo de bambú se
-- llama «Bamboo & Ulin Shingle». Las «Top View» de Dali y Tropical se miraron una a una:
-- son plantas vistas desde arriba. Si dos fotos casan, gana la de menor orden.
with c as (
  select id, modelo_id, orden,
         case
           when pie->>'en' ilike '%aerea%'                                     then 'aerea'
           when pie->>'en' ilike '%floor plan%' or pie->>'en' ilike '%top view%' then 'planta'
           when pie->>'en' ilike '%sirap%'                                     then 'techo_sirap'
           when pie->>'en' ilike '%bamboo%'                                    then 'techo_bambu'
           when pie->>'en' ilike '%living room%'                               then 'interior'
           when pie->>'en' ilike '%kitchen%'                                   then 'cocina'
           when pie->>'en' ilike '%toilet%' or pie->>'en' ilike '%bathroom%'   then 'bano'
         end as v
    from public.deck_fotos
   where ambito = 'modelo'
), r as (
  select id, v, row_number() over (partition by modelo_id, v order by orden, id) as n
    from c where v is not null
)
update public.deck_fotos d set vista = r.v from r where r.id = d.id and r.n = 1;

-- Cambiar la vista de una foto quitándosela a la que la tuviera, todo o nada.
-- SECURITY INVOKER: manda la RLS de deck_fotos (escribir = es_admin()).
create or replace function public.deck_foto_fijar_vista(p_foto uuid, p_vista text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_modelo uuid;
begin
  select modelo_id into v_modelo
    from public.deck_fotos
   where id = p_foto and ambito = 'modelo';
  if v_modelo is null then
    raise exception 'La foto no existe o no es de un modelo';
  end if;

  if p_vista is not null then
    update public.deck_fotos set vista = null
     where modelo_id = v_modelo and vista = p_vista and id <> p_foto;
  end if;

  update public.deck_fotos set vista = p_vista where id = p_foto;
  if not found then
    -- La RLS filtra sin error: 0 filas es «no tienes permiso», nunca «guardado».
    raise exception 'No tienes permiso (solo administrador)';
  end if;
end;
$$;

revoke all on function public.deck_foto_fijar_vista(uuid, text) from public, anon;
grant execute on function public.deck_foto_fijar_vista(uuid, text) to authenticated;

-- La web pública recibe también la vista (misma firma y retorno: se conservan owner y grants).
create or replace function public.modelo_fotos_publico()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce(jsonb_object_agg(x.slug, x.fotos), '{}'::jsonb)
    from (
      select m.slug,
             (select jsonb_agg(jsonb_build_object(
                       'path',  df.path,
                       'pie',   df.pie ->> 'en',
                       'tipo',  df.tipo,
                       'orden', df.orden,
                       'vista', df.vista
                     ) order by df.orden)
                from public.deck_fotos df
               where df.ambito = 'modelo' and df.modelo_id = m.id
             ) as fotos
        from public.modelos m
       where m.publicado and m.activo
    ) x
   where x.fotos is not null
$function$;
