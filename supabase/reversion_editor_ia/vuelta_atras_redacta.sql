-- destructivo-ok: VUELTA ATRÁS de 20261013235000_editor_ia_redacta.sql (E10, «contrato entero desde una frase»), 13-oct-2026.
-- Solo a mano, con OK del owner y su válvula (tools/no_destruir.py), y con copia previa:
--   python erp/respaldo_instancia.py lawang --previa "antes de revertir E10 contrato desde una frase"
--
-- PASO 1 — PARAR (no borra nada; basta casi siempre). El asistente entero se apaga en Ajustes → Servicios de AxisWorks (encendido = false
-- por empresa). Sin margen o apagado, la reserva de redacta/redacta_traduce ya rechaza y la caja de la pantalla solo enseña el motivo.
-- Para quitar solo la caja: retirar textos-contrato-redacta.js de textos-contrato/index.html (y la sección #tc-rd).
--
-- PASO 2 — QUITAR LA PIEZA. Con filas en editor_ia_redaccion: PARA y pregunta (es parte del extracto que se factura: exportarlo antes).
-- Los contratos ya creados con el asistente NO se tocan: son contratos propios normales (su nombre acaba en « (IA)»).
-- Orden: (a) devolver las funciones que la migración sustituyó a su versión anterior, ejecutando de nuevo SOLO su bloque
-- `create or replace` de la migración que se indica (copiado de ese fichero, tal cual):
--     _editor_ia_peso(editor_ia_uso)          20261013230000_servicios_axisworks_reserva_colgada.sql
--     _servicios_gasto_mes, _editor_ia_caduca  20261013210000_servicios_axisworks_editor_ia.sql
--     editor_ia_estado, servicios_axisworks_datos   20261013220000_servicios_axisworks_correcciones.sql
--     _plantilla_esqueleto_en_blanco          20261010030000_f2_editor_e9_contrato_nuevo.sql
--   (b) deshacer el parche del tope por minuto de editor_ia_reserva (abajo, misma regla: la línea tiene que estar una vez);
--   (c) borrar lo nuevo (abajo). Antes de (c), la edge editor-ia desplegada sin redacta (o con E10 retirado de motor.js).
begin;
do $deshace$
declare
  d text := pg_catalog.pg_get_functiondef('public.editor_ia_reserva'::regproc);
  nuevo constant text := 'select (select count(*) from public.editor_ia_uso u where u.usuario = v_uid and u.fecha > now() - interval ''1 minute'') + (select count(*) from public.editor_ia_redaccion r where r.usuario = v_uid and r.fecha > now() - interval ''1 minute'') into v_min;';
  viejo constant text := 'select count(*) into v_min from public.editor_ia_uso u where u.usuario = v_uid and u.fecha > now() - interval ''1 minute'';';
begin
  if (length(d) - length(replace(d, nuevo, ''))) / length(nuevo) <> 1 then
    raise exception 'editor_ia_reserva no tiene la linea parcheada exactamente una vez: revisar a mano';
  end if;
  execute replace(d, nuevo, viejo);
end $deshace$;
-- (c) solo DESPUÉS de (a): las versiones anteriores ya no nombran editor_ia_redaccion
drop function if exists public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean);
drop function if exists public._plantilla_cuerpo_asistente(text, text[], text, jsonb);
drop function if exists public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text);
drop function if exists public.editor_ia_redaccion_reserva(text, text, uuid, text, text);
drop function if exists public._editor_ia_huella_redaccion(jsonb, text);
drop function if exists public._editor_ia_peso_r(public.editor_ia_redaccion);
drop function if exists public._editor_ia_peso_de(text, timestamptz, timestamptz, numeric, numeric);   -- tras (a): _editor_ia_peso ya no la usa
drop table if exists public.editor_ia_redaccion;
commit;
