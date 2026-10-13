-- destructivo-ok: VUELTA ATRÁS de 20261013073950_editor_ia_redacta.sql (E10, «contrato entero desde una frase»), 13-oct-2026.
-- Solo a mano, con OK del owner y su válvula (tools/no_destruir.py), y con copia previa:
--   python erp/respaldo_instancia.py lawang --previa "antes de revertir E10 contrato desde una frase"
--
-- PASO 1 — PARAR (no borra nada; basta casi siempre). El asistente entero se apaga en Ajustes → Servicios de AxisWorks (margen vacío,
-- o encendido = false por empresa). Sin margen o apagado, la reserva de redacta/redacta_traduce ya rechaza y la caja de la pantalla solo
-- enseña el motivo. Para quitar solo la caja: retirar textos-contrato-redacta.js de textos-contrato/index.html (y la sección #tc-rd).
--
-- PASO 2 — QUITAR LA PIEZA, en este orden:
--   0. ANTES de tocar la base: desplegar la función editor-ia sin las acciones redacta/redacta_traduce (o con E10 retirado de motor.js) y
--      dejar el margen vacío. Si no, entre la vuelta de las funciones de dinero y el borrado, una redacción se podría reservar sin contar
--      contra el tope (consulta de Datos, 13-oct). El bloque de abajo PARA si el margen sigue puesto.
--   1. Ejecutar TODO el bloque begin…commit de abajo de una vez. Dentro, en el hueco marcado (a), pegar las versiones anteriores de las
--      funciones que la migración sustituyó, copiadas de su migración y cambiando `create function` por `create or replace function`
--      (dos de ellas se crearon con `create function` y darían «ya existe»):
--        _editor_ia_peso(editor_ia_uso)                    20261013063935_servicios_axisworks_reserva_colgada.sql
--        _servicios_gasto_mes, _editor_ia_caduca           20261013060136_servicios_axisworks_editor_ia.sql
--        editor_ia_estado, servicios_axisworks_datos       20261013062302_servicios_axisworks_correcciones.sql
--        _plantilla_esqueleto_en_blanco                    20261010030000_f2_editor_e9_contrato_nuevo.sql
--      Si se olvida pegarlas, la guarda de después para el bloque entero (rollback) sin borrar nada.
-- Las filas de editor_ia_redaccion son parte del extracto que se factura (importe, quién aceptó): con filas, el bloque PARA. Exportar el
-- extracto (Ajustes → Servicios de AxisWorks) y decidir con el owner antes de quitar esa guarda.
-- Los contratos ya creados con el asistente NO se tocan: son contratos propios normales (su nombre acaba en « (IA)»).
begin;
do $previo$
begin
  if exists (select 1 from public.servicios_axisworks_ajustes where margen_pct is not null) then
    raise exception 'El asistente sigue con margen: vacíalo (y despliega editor-ia sin redacta) antes de revertir';
  end if;
  if exists (select 1 from public.editor_ia_redaccion) then
    raise exception 'editor_ia_redaccion tiene filas (parte del extracto que se factura): exportar y decidir con el owner antes de borrarla';
  end if;
end $previo$;
-- (b) deshacer el parche del tope por minuto de editor_ia_reserva (la línea tiene que estar exactamente una vez)
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

-- (a) ═══ PEGAR AQUÍ las cinco versiones anteriores, con `create or replace function` (ver la lista de arriba) ═══

-- Guarda: ninguna función que se queda puede seguir nombrando lo de E10. Si (a) no se pegó, o se pegó a medias, PARA aquí: borrar la tabla
-- dejaría el editor entero sin funcionar (las funciones `language sql` no registran dependencias, así que el drop no avisaría).
do $guarda$
declare v_quedan text;
begin
  select string_agg(p.proname, ', ' order by p.proname) into v_quedan
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
     and p.proname not in ('plantilla_contrato_crea_desde_asistente', '_plantilla_cuerpo_asistente', 'editor_ia_redaccion_paso',
                           'editor_ia_redaccion_reserva', '_editor_ia_huella_redaccion', '_editor_ia_peso_r', '_editor_ia_peso_de')
     and (pg_catalog.pg_get_functiondef(p.oid) ~ 'editor_ia_redaccion|_editor_ia_peso_r|_editor_ia_peso_de|lw\.esqueleto_asistente');
  if v_quedan is not null then
    raise exception 'Paso (a) sin hacer: estas funciones siguen nombrando lo de E10: %', v_quedan;
  end if;
end $guarda$;
-- (c) borrar lo nuevo
drop function if exists public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean);
drop function if exists public._plantilla_cuerpo_asistente(text, text[], text, jsonb);
drop function if exists public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text);
drop function if exists public.editor_ia_redaccion_reserva(text, text, uuid, text, text);
drop function if exists public._editor_ia_huella_redaccion(jsonb, text);
drop function if exists public._editor_ia_peso_r(public.editor_ia_redaccion);
drop function if exists public._editor_ia_peso_de(text, timestamptz, timestamptz, numeric, numeric);   -- tras (a): _editor_ia_peso ya no la usa
drop table if exists public.editor_ia_redaccion;
commit;
