create or replace function public.uso_almacenamiento(
  limite_ficheros bigint default 1073741824,
  limite_base     bigint default 524288000
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
begin
  if not public.es_agente() then
    raise exception 'no autorizado';
  end if;

  select coalesce(sum((o.metadata->>'size')::bigint), 0), count(*)
    into ficheros, n_ficheros
    from storage.objects o;

  select pg_catalog.pg_database_size(pg_catalog.current_database()) into base;

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
    'ritmo_mb_dia', (
      select round(coalesce(sum((o.metadata->>'size')::bigint), 0) / 1048576.0 / 90.0, 2)
        from storage.objects o
       where o.created_at > now() - interval '90 days')
  );
end;
$$;

revoke all on function public.uso_almacenamiento(bigint, bigint) from public, anon;
grant execute on function public.uso_almacenamiento(bigint, bigint) to authenticated;;
