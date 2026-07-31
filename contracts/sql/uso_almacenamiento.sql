-- ============================================================================
-- Métricas de almacenamiento — 31-jul-2026
-- ----------------------------------------------------------------------------
-- Pregunta del owner: "¿cuál es el límite de Supabase? ¿qué pasa si se llena?"
-- Lo que pasa es que las SUBIDAS EMPIEZAN A FALLAR. Supabase no borra nada ni
-- avisa por su cuenta con antelación útil: rechaza la escritura. En esta suite
-- eso significa que una firma se completa, el PDF no se puede guardar y el
-- contrato queda sin sellar — por eso hace falta verlo venir, no enterarse.
--
-- La función es SECURITY DEFINER porque `pg_database_size` y el conteo sobre
-- `storage.objects` no están al alcance del rol `authenticated`; el filtro de
-- quién puede llamarla lo pone `es_agente()` dentro, no el GRANT.
--
-- LÍMITES: los del plan Free (1 GB de ficheros, 500 MB de base de datos), que es
-- lo que indica la evidencia — las tres organizaciones tienen un proyecto cada
-- una y ninguna tenía copia de seguridad automática, que el plan Pro sí incluye.
-- Si se sube de plan, se cambian aquí los dos valores por defecto y ya.
-- ============================================================================

create or replace function public.uso_almacenamiento(
  limite_ficheros bigint default 1073741824,   -- 1 GB  (Free)
  limite_base     bigint default 524288000     -- 500 MB (Free)
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ficheros bigint;
  n_ficheros bigint;
  base bigint;
  detalle jsonb;
  ritmo numeric;
begin
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  select coalesce(sum((o.metadata->>'size')::bigint), 0), count(*)
    into ficheros, n_ficheros
    from storage.objects o;

  select pg_catalog.pg_database_size(pg_catalog.current_database()) into base;

  -- MB/día sobre la ventana REAL: desde el primer fichero, con un tope de 90
  -- días para que un histórico largo no diluya el ritmo de ahora, y un suelo de
  -- 1 día para no dividir entre cero el día que se sube el primero.
  select round(
           coalesce(sum((o.metadata->>'size')::bigint), 0) / 1048576.0
           / greatest(1, extract(epoch from (now() - min(o.created_at))) / 86400.0)
         , 2)
    into ritmo
    from storage.objects o
   where o.created_at > now() - interval '90 days';

  select jsonb_agg(x order by x->>'bytes' desc) into detalle from (
    select jsonb_build_object(
             'bucket', b.id,
             'ficheros', count(o.id),
             'bytes', coalesce(sum((o.metadata->>'size')::bigint), 0)
           ) as x
      from storage.buckets b
      left join storage.objects o on o.bucket_id = b.id
     group by b.id
  ) t;

  return jsonb_build_object(
    'medido_en', now(),
    'ficheros', jsonb_build_object(
      'bytes', ficheros, 'n', n_ficheros, 'limite', limite_ficheros,
      'pct', round((ficheros::numeric / nullif(limite_ficheros,0)) * 100, 1)),
    'base', jsonb_build_object(
      'bytes', base, 'limite', limite_base,
      'pct', round((base::numeric / nullif(limite_base,0)) * 100, 1)),
    'buckets', coalesce(detalle, '[]'::jsonb),
    -- Lo que importa no es el % de hoy sino cuánto margen queda AL RITMO REAL.
    -- Se divide entre los días que de verdad lleva habiendo ficheros, no entre
    -- 90 fijos: el sistema arrancó el 17-jul, así que dividir entre 90 daba un
    -- ritmo seis veces menor del real — y en un aviso, equivocarse hacia el lado
    -- optimista es no avisar.
    'ritmo_mb_dia', ritmo,
    'dias_de_margen', case when ritmo > 0
      then floor((limite_ficheros - ficheros) / 1048576.0 / ritmo) end
  );
end;
$$;

revoke all on function public.uso_almacenamiento(bigint, bigint) from public, anon;
grant execute on function public.uso_almacenamiento(bigint, bigint) to authenticated;

-- ⚠️ Al poner `search_path=''` en una función hay que comprobar que SIGUE
-- EJECUTANDO, no solo que el linter se calla: si revienta, el panel se queda sin
-- métricas y el aviso no salta nunca — en verde. (Lección de `es_agente()`, 28-jul.)
