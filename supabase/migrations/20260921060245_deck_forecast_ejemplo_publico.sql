/*
 * deck_forecast_ejemplo_publico() -- RPC publica para la seccion "Snapshot financiero"
 * de /modelo/<id> (21-sep-2026, restyle Modo calco de la landing de modelo).
 *
 * MOTIVO: `deck_forecast` y `deck_forecast_proyecto` viven detras de RLS a
 * es_agente()/es_admin() -- son el investor deck privado, un visitante anonimo de la web
 * publica no puede leerlas. La landing necesita UN solo ejemplo economico fijo (Villa Dali
 * en Palm Field W5, decision del owner), no acceso al resto de proyectos/modelos. Abrir la
 * tabla entera a `anon` filtrando por `publicado` habria expuesto tambien la economia de
 * TODOS los demas proyectos a cualquier visitante -- en vez de eso, esta funcion
 * SECURITY DEFINER fija los dos UUID en el propio SQL y NO acepta parametros: no hay forma
 * de pedirle otro proyecto. Mismo patron que catalogo_publico() (columnas elegidas a mano,
 * nunca `select *`).
 *
 * EL DATO TIENE UN DUENO: `deck_forecast`/`deck_forecast_proyecto` los edita el equipo
 * desde el investor deck privado de la intranet. Esta funcion es una VENTANA de solo
 * lectura sobre esas dos filas, nunca una copia -- si el ADR o los porcentajes cambian ahi,
 * la landing lo ve en el siguiente fetch (cache de 5 min en modelo/datos.php), sin tocar
 * codigo ni desplegar nada.
 */
create or replace function public.deck_forecast_ejemplo_publico()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
    'proyecto',           pr.nombre,
    'modelo',              m.nombre,
    'moneda',             df.moneda,
    'adr_medio',          df.adr_medio,
    'adr_optimo',         df.adr_optimo,
    'ocupacion_media',    df.ocupacion_media,
    'ocupacion_optima',   df.ocupacion_optima,
    'inversion_base',     df.inversion_base,
    'pct_gestion',        dfp.pct_gestion,
    'pct_mantenimiento',  dfp.pct_mantenimiento,
    'pct_impuesto',       dfp.pct_impuesto
  )
  from public.deck_forecast df
  join public.deck_forecast_proyecto dfp on dfp.proyecto_id = df.proyecto_id
  join public.proyectos pr on pr.id = df.proyecto_id
  join public.modelos m on m.id = df.modelo_id
  where df.proyecto_id = 'ee279df3-43f9-4299-a9dc-7daf4df6f6d6'::uuid
    and df.modelo_id   = '2ced5a54-5c76-4f9e-a031-45353d7f2e40'::uuid
    and df.publicado
    and dfp.publicado
  limit 1;
$$;

revoke all on function public.deck_forecast_ejemplo_publico() from public;
grant execute on function public.deck_forecast_ejemplo_publico() to anon, authenticated;

comment on function public.deck_forecast_ejemplo_publico() is
  'Ejemplo economico fijo (Villa Dali / Palm Field W5) para la seccion "Snapshot financiero" de /modelo/<id>. Sin parametros a proposito: no se puede pedir otro proyecto ni enumerar el resto del deck. 21-sep-2026.';
;
