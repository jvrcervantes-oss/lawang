-- VUELTA ATRÁS de 20261016230000_ia_mis_conexiones_clientes.sql («apps conectadas» con los asistentes con los que se conecta).
-- Deja public.ia_mis_conexiones() EXACTAMENTE como estaba en la viva el 16-oct (texto de pg_get_functiondef; md5 al final: si no
-- casa, no se aplica nada). No destruye nada: solo deja de devolver `clientes` y `duracion_dias`; la web vuelve sola a decir
-- dónde está el identificador. create or replace conserva dueño (ia_puente_rol) y EXECUTE (authenticated).
begin;
set local lock_timeout = '5s';

-- md5 de pg_get_functiondef en la viva el 16-oct = 10ef7d0dd885301fa142208a764b1f2d
CREATE OR REPLACE FUNCTION public.ia_mis_conexiones()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'encendido', coalesce((select encendido from public.ia_ajustes where id), false),
    'permiso', exists (select 1 from public.ia_permisos x where x.usuario_id = privado.ia_pantalla_uid() and x.quitado_en is null),
    'conexiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'asistente', k.asistente, 'nombre', k.nombre, 'creada_en', c.creada_en, 'expira_en', c.expira_en,
               'viva', c.revocada_en is null and c.expira_en > now(), 'revocada_en', c.revocada_en,
               'revocada_motivo', c.revocada_motivo,
               'ultima_llamada', (select max(l.creado_en) from public.ia_llamadas l where l.conexion_id = c.id),
               'llamadas', (select count(*) from public.ia_llamadas l where l.conexion_id = c.id and l.resultado = 'ok'))
             order by c.creada_en desc)
        from public.ia_conexiones c join public.ia_clientes k on k.id = c.cliente_id
       where c.usuario_id = privado.ia_pantalla_uid() and c.creada_en > now() - interval '30 days'), '[]'::jsonb));
$function$;

do $c$
begin
  if md5(pg_get_functiondef('public.ia_mis_conexiones()'::regprocedure)) <> '10ef7d0dd885301fa142208a764b1f2d' then
    raise exception 'vuelta_atras_mis_conexiones: el texto restaurado no es el de la viva del 16-oct; no se aplica nada';
  end if;
end $c$;
commit;
