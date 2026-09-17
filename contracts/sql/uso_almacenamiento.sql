-- ============================================================================
-- Métricas de almacenamiento — 31-jul-2026
-- ----------------------------------------------------------------------------
-- Pregunta del owner: "¿cuál es el límite de Supabase? ¿qué pasa si se llena?"
-- Lo que pasa es que las SUBIDAS EMPIEZAN A FALLAR. Supabase no borra nada ni
-- avisa por su cuenta con antelación útil: rechaza la escritura. En esta suite
-- eso significa que una firma se completa, el PDF no se puede guardar y el
-- contrato queda sin sellar — por eso hace falta verlo venir, no enterarse.
--
-- DOS FUNCIONES, no una (añadido 31-jul-2026, migración *_interno): el cálculo
-- vive en `_uso_almacenamiento()`, sin permisos — la llaman el panel (a través
-- del wrapper) y el cron nocturno de `revisar_almacenamiento()`
-- (aviso_almacenamiento.sql), que corre como `postgres` y no tiene JWT, así
-- que compartir la función con el guard de `es_agente()` dentro la dejaría
-- fallando en silencio todas las noches. `uso_almacenamiento()` es el wrapper
-- con permiso que llama el panel — mismo resultado, con el filtro de quién
-- puede pedirlo. `pg_database_size` y el conteo sobre `storage.objects` no
-- están al alcance del rol `authenticated`, por eso las dos son SECURITY
-- DEFINER.
--
-- LÍMITES: los del plan contratado — Pro desde el 15-sep-2026 (100 GB de
-- ficheros, 8 GB de base de datos; antes Free, 1 GB / 500 MB). Si se sube de
-- plan otra vez, se cambian aquí los DOS valores por defecto de las DOS
-- funciones (los cuatro números) y ya — no hay forma de leer el plan de
-- facturación desde SQL ni desde el MCP de este entorno, así que es un
-- número escrito a mano y hay que acordarse de tocarlo (17-sep-2026: el panel
-- llevaba dos días diciendo el límite del Free con el Pro ya pagado).
-- ============================================================================

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

  -- MB/día sobre la ventana REAL: desde el primer fichero, con un tope de 90
  -- días para que un histórico largo no diluya el ritmo de ahora, y un suelo de
  -- 1 día para no dividir entre cero el día que se sube el primero.
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
    -- Lo que importa no es el % de hoy sino cuánto margen queda AL RITMO REAL.
    'ritmo_mb_dia', ritmo,
    'dias_de_margen', case when ritmo > 0
      then floor((limite_ficheros - ficheros) / 1048576.0 / ritmo) end);
end;
$$;
revoke all on function public._uso_almacenamiento(bigint, bigint) from public, anon, authenticated;

-- El wrapper que llama el panel: mismo resultado, con el filtro de quién puede.
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

-- ⚠️ Al poner `search_path=''` en una función hay que comprobar que SIGUE
-- EJECUTANDO, no solo que el linter se calla: si revienta, el panel se queda sin
-- métricas y el aviso no salta nunca — en verde. (Lección de `es_agente()`, 28-jul.)
