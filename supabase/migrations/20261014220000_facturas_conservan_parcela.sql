-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El maestro no lleva trg_espejo_proyecto con esta forma; si un
--   negocio del tipo Propiedades lo necesita, se porta con su prueba.
-- LAS FACTURAS, PROFORMAS Y RECIBIS GUARDAN «<proyecto> — <parcela>» DESDE EL ENLACE (14/15-oct-2026, Backend; fallo 4 de los que
--   encontro el orquestador al aplicar REC00015/REC00019: REC00019 paso de «Bonian Village — C5» a «Bonian Village» al guardarlo).
-- CAUSA: trg_espejo_proyecto (BEFORE INSERT OR UPDATE OF proyecto_id, proyecto_nombre, en contratos y en facturas) pone
--   proyecto_nombre := proyectos.nombre siempre que hay proyecto_id. Al EDITAR (factura_guarda / guardar_recibi reescriben
--   proyecto_nombre en su UPDATE) se perdia la parcela de la COLUMNA, que usan el listado, el filtro y el buscador (el papel se
--   pinta desde datos.fields y no cambia). Medido el 14-oct (solo lectura): 189 documentos con la parcela en la columna, 40 la
--   perdieron al editarse.
-- QUE HACE (2.a version, 15-oct, CAMBIOS del revisor sobre 19dd635fe): en FACTURAS la columna es un espejo construido en el
--   servidor desde los enlaces: nombre del proyecto (proyecto_id, o el del contrato) + « — » + la unidad del contrato enlazado
--   (datos.fields.parcela_codigo, si no villa_nombre, si no tipologia_villa: lo que ya pone la pantalla al elegir el contrato).
--   El texto que manda la pantalla NO cuenta (patrones_tecnicos.md → «ENLACE + ESPEJO»; principio «no te creas nada del
--   front-end»). Asi tambien: cambiar de proyecto ya no arrastra la parcela ni un prefijo parecido («X largo» → «X»); un
--   renombrado lo sigue haciendo trg_proyecto_renombrado (AFTER UPDATE en proyectos), y su UPDATE de la columna pasa por este
--   espejo, que la recompone con el nombre nuevo (no puede duplicar un sufijo). Contratos NO cambia (nombre a secas).
--   La 1.a version tocaba ademas renombrar_proyecto: SOBRABA (trg_proyecto_renombrado ya renombra por proyecto_id) y con un
--   nombre que alarga el viejo duplicaba el sufijo. Ya no se toca.
-- CAMBIO DE COMPORTAMIENTO (decision por defecto del CEO, 15-oct, reversible con la vuelta): un documento SIN contrato enlazado
--   pero con proyecto guarda el nombre a secas aunque se escriba «— C5» a mano. Solo puede pasarle a un documento ANTERIOR al
--   12-ago-2026 que se vuelva a guardar: desde entonces el CHECK facturas_contrato_obligatorio exige contrato a todo documento
--   (comprobado en la rama del 15-oct: 23514). Cuantos historicos hay asi: SIN MEDIR (lectura de produccion denegada el 15-oct).
-- LO QUE NO HACE: no rellena los ~40 que ya perdieron la parcela (decision por defecto del orquestador, 15-oct: los vivos se
--   rehacen al siguiente guardado; las enviadas y anuladas se quedan sin ella en la columna, su papel si la lleva; rellenarlos
--   es un UPDATE que dispara el recalculo de comisiones y lo decide el owner tras la congelacion).
-- Se REESCRIBE ENTERA desde su definicion viva, con este md5 de pg_get_functiondef (sin retorno de carro) medido en el vivo el
--   14-oct-2026 en la sesion 1014-2147 (solo lectura):  trg_espejo_proyecto()  6ddd6fbe892437e14c8d5af6347f196a
--   Si ya no tiene ese md5 y tampoco lleva este arreglo, el bloque $antes$ lanza y no se aplica NADA. Idempotente.
-- REVERTIR: supabase/reversion_facturas_conservan_parcela/REVERSION.sql (el texto vivo de antes, tal cual).
-- Prueba: supabase/pruebas/facturas_conservan_parcela.sql (crea contratos y facturas: SOLO en rama).

set local lock_timeout = '5s';

-- ============================================================ 0. Marca y raise
do $antes$
declare x record;
begin
  for x in select * from (values
             ('public.trg_espejo_proyecto()', '6ddd6fbe892437e14c8d5af6347f196a', 'espejo desde el enlace (15-oct-2026)')) t(f, m, marca)
  loop
    if md5(replace(pg_get_functiondef(x.f::regprocedure), chr(13), '')) <> x.m
       and position(x.marca in pg_get_functiondef(x.f::regprocedure)) = 0 then
      raise exception 'facturas_conservan_parcela: % no es la definicion viva leida el 14-oct (md5 distinto) ni lleva ya el arreglo; no se aplica nada', x.f;
    end if;
  end loop;
end $antes$;

-- ============================================================ (i) trg_espejo_proyecto
CREATE OR REPLACE FUNCTION public.trg_espejo_proyecto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_nombre text; v_unidad text; v_pid uuid;
begin
  -- la regla del proyecto vive en _contrato_proyecto_de (13-oct-2026): la usan tambien _trg_contrato_tipo_valido y
  -- _trg_contrato_campos_propios, que se disparan antes que este trigger
  new.proyecto_id := public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre);

  if tg_table_name = 'facturas' then
    -- facturas: espejo desde el enlace (15-oct-2026). La columna es «<nombre del proyecto> — <unidad del contrato>», y la
    -- unidad sale del contrato enlazado (datos.fields: parcela_codigo, si no villa_nombre, si no tipologia_villa: lo mismo
    -- que pone la pantalla al elegir el contrato). El texto que manda la pantalla no cuenta (no te creas nada del
    -- front-end). Sin proyecto_id se toma el del contrato para el TEXTO (el enlace no se toca). Sin contrato: el nombre a
    -- secas. Sin proyecto en ningun lado: el texto queda como llega, como hasta ahora.
    if new.contrato_id is not null then
      select coalesce(nullif(btrim(c.datos #>> '{fields,parcela_codigo}'), ''),
                      nullif(btrim(c.datos #>> '{fields,villa_nombre}'), ''),
                      nullif(btrim(c.datos #>> '{fields,tipologia_villa}'), '')),
             c.proyecto_id
        into v_unidad, v_pid
        from public.contratos c where c.id = new.contrato_id;
    end if;
    select p.nombre into v_nombre from public.proyectos p where p.id = coalesce(new.proyecto_id, v_pid);
    if v_nombre is not null then
      new.proyecto_nombre := v_nombre || coalesce(' — ' || v_unidad, '');
    end if;
  elsif new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      new.proyecto_nombre := v_nombre;
    end if;
  end if;
  return new;
end
$function$;
