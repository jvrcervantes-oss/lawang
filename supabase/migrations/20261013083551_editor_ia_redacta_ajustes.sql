-- E10, consulta de Datos del 13-oct-2026 sobre 20261013073950_editor_ia_redacta.sql: dos ajustes, solo construye (create or replace
-- de dos funciones ya existentes, misma firma; los permisos se conservan).
--  1. plantilla_contrato_crea_desde_asistente: la lista CTRL de la base no traía U+061C (marca de letra árabe) ni U+180E (separador
--     mongol), que la función editor-ia sí rechaza (RE_BASE_NO de motor.js). El nombre del contrato es el único texto que la base recibe
--     sin huella (lo escribe la persona), así que una marca de dirección podía desordenar cómo se ve en el listado. Ahora las dos listas
--     son la misma.
--  2. editor_ia_redaccion_reserva: con 4 o 5 consultas en el último minuto, «redacta» entraba (y se cobraba) y la segunda traducción
--     chocaba con el tope de 6 por minuto. Ahora una redacción solo empieza si caben ella y sus dos traducciones (como mucho 3 en el
--     último minuto). Las traducciones y el resto siguen con 6.
-- Cada cambio es UNA línea de la función aplicada, buscada exactamente una vez (si no está, para y no toca nada). Los caracteres invisibles
-- se escriben con chr() para que no dependan de cómo se guarde este fichero.
-- Vuelta atrás: el mismo replace al revés (las dos líneas viejas están abajo).
do $parche$
declare
  d text;
  ctrl_viejo constant text := 'CTRL constant text := ''[<>\x01-\x1f\x7f' || chr(173) || chr(8203) || '-' || chr(8207) || chr(8234) || '-' || chr(8238)
                              || chr(8288) || chr(8294) || '-' || chr(8297) || chr(65279) || ']'';';
  ctrl_nuevo constant text := 'CTRL constant text := ''[<>\x01-\x1f\x7f' || chr(173) || chr(1564) || chr(6158) || chr(8203) || '-' || chr(8207) || chr(8234)
                              || '-' || chr(8238) || chr(8288) || chr(8294) || '-' || chr(8297) || chr(65279) || ']'';';
  min_viejo constant text := 'if v_min >= 6 then';
  min_nuevo constant text := 'if v_min >= (case when p_accion = ''redacta'' then 4 else 6 end) then';   -- entre paréntesis: el IF de PL/pgSQL corta en el primer THEN
begin
  d := pg_catalog.pg_get_functiondef('public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean)'::regprocedure);
  if (length(d) - length(replace(d, ctrl_viejo, ''))) / length(ctrl_viejo) <> 1 then
    raise exception 'plantilla_contrato_crea_desde_asistente: la linea CTRL no esta exactamente una vez';
  end if;
  execute replace(d, ctrl_viejo, ctrl_nuevo);
  d := pg_catalog.pg_get_functiondef('public.editor_ia_redaccion_reserva(text, text, uuid, text, text)'::regprocedure);
  if (length(d) - length(replace(d, min_viejo, ''))) / length(min_viejo) <> 1 then
    raise exception 'editor_ia_redaccion_reserva: la linea del tope por minuto no esta exactamente una vez';
  end if;
  execute replace(d, min_viejo, min_nuevo);
end $parche$;

do $comprueba$
begin
  if position(chr(1564) in pg_catalog.pg_get_functiondef('public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean)'::regprocedure)) = 0
     or position('then 4 else 6 end' in pg_catalog.pg_get_functiondef('public.editor_ia_redaccion_reserva(text, text, uuid, text, text)'::regprocedure)) = 0 then
    raise exception 'el parche no ha quedado aplicado';
  end if;
  if has_function_privilege('anon', 'public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.editor_ia_redaccion_reserva(text, text, uuid, text, text)', 'execute') then
    raise exception 'los permisos han cambiado';
  end if;
end $comprueba$;
