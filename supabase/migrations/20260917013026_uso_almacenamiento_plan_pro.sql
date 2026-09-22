-- ════════════════════════════════════════════════════════════════════════════
-- LOS DEFAULTS DE ALMACENAMIENTO PASAN A LOS DEL PLAN PRO — 17-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- El panel de Documentación (intranet/Documentacion/index.html) seguía
-- enseñando el límite del plan Free (1024 MB de ficheros, 500 MB de base de
-- datos) pese a que el owner pagó el Pro el 15-sep, al 98% de ese cupo
-- ([[project_lawang_supabase_storage_98_15sep]]). No es un bug de cálculo: la
-- función siempre leyó bien el uso real, el número que estaba mal era el
-- LÍMITE con el que compara — un argumento por defecto, escrito el 31-jul con
-- el comentario "si se sube de plan, se cambian aquí los dos valores y ya".
-- Toca hacerlo.
--
-- Cifras del plan Pro (verificadas en supabase.com/pricing y su doc de
-- pricing, 17-sep-2026): 100 GB de almacenamiento de ficheros incluidos, 8 GB
-- de base de datos incluidos. Lo que se pase de ahí se factura por uso — no
-- hay otro número "correcto" que leer desde SQL: Supabase no expone el plan de
-- facturación a `authenticated` ni al MCP de este entorno.
--
-- Lo que NO cambia: la copia "Cuando se llena, Supabase NO borra nada:
-- RECHAZA las subidas" de revisar_almacenamiento() (aviso_almacenamiento.sql)
-- sigue siendo cierta en la práctica — el Pro trae el Spend Cap ACTIVADO por
-- defecto, y con el Spend Cap activo pasarse del cupo incluido bloquea igual
-- que en el Free, no factura de más. Si el owner lo ha desactivado a mano,
-- esa frase deja de ser exacta y hay que revisarla — no hay forma de leer el
-- estado del Spend Cap desde aquí para saberlo solo.
--
-- Se recrean las DOS funciones (la interna que hace el cálculo y el wrapper
-- con permiso que llama el panel — ver contracts/sql/uso_almacenamiento.sql
-- para el porqué de la partición) porque cada una lleva sus propios defaults
-- y las dos importan: el panel llama al wrapper sin argumentos, el cron
-- nocturno (revisar_almacenamiento) llama a la interna sin argumentos.
-- Cuerpo idéntico al vigente; solo cambian los dos DEFAULT.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public._uso_almacenamiento(
  limite_ficheros bigint default 107374182400,  -- 100 GB (Pro)
  limite_base     bigint default 8589934592     -- 8 GB   (Pro)
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ficheros bigint; n_ficheros bigint; base bigint; detalle jsonb; ritmo numeric;
begin
  select coalesce(sum((o.metadata->>'size')::bigint), 0), count(*)
    into ficheros, n_ficheros from storage.objects o;

  select pg_catalog.pg_database_size(pg_catalog.current_database()) into base;

  select round(
           coalesce(sum((o.metadata->>'size')::bigint), 0) / 1048576.0
           / greatest(1, extract(epoch from (now() - min(o.created_at))) / 86400.0)
         , 2)
    into ritmo from storage.objects o
   where o.created_at > now() - interval '90 days';

  select jsonb_agg(x order by x->>'bytes' desc) into detalle from (
    select jsonb_build_object('bucket', b.id, 'ficheros', count(o.id),
             'bytes', coalesce(sum((o.metadata->>'size')::bigint), 0)) as x
      from storage.buckets b left join storage.objects o on o.bucket_id = b.id
     group by b.id) t;

  return jsonb_build_object(
    'medido_en', now(),
    'ficheros', jsonb_build_object('bytes', ficheros, 'n', n_ficheros,
      'limite', limite_ficheros,
      'pct', round((ficheros::numeric / nullif(limite_ficheros,0)) * 100, 1)),
    'base', jsonb_build_object('bytes', base, 'limite', limite_base,
      'pct', round((base::numeric / nullif(limite_base,0)) * 100, 1)),
    'buckets', coalesce(detalle, '[]'::jsonb),
    'ritmo_mb_dia', ritmo,
    'dias_de_margen', case when ritmo > 0
      then floor((limite_ficheros - ficheros) / 1048576.0 / ritmo) end);
end;
$$;
revoke all on function public._uso_almacenamiento(bigint, bigint) from public, anon, authenticated;

create or replace function public.uso_almacenamiento(
  limite_ficheros bigint default 107374182400,  -- 100 GB (Pro)
  limite_base     bigint default 8589934592     -- 8 GB   (Pro)
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.es_agente() then raise exception 'no autorizado'; end if;
  return public._uso_almacenamiento(limite_ficheros, limite_base);
end;
$$;
revoke all on function public.uso_almacenamiento(bigint, bigint) from public, anon;
grant execute on function public.uso_almacenamiento(bigint, bigint) to authenticated;
