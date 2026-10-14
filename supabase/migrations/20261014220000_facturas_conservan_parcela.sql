-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68). El maestro no lleva trg_espejo_proyecto ni renombrar_proyecto con
--   esta forma; si un negocio del tipo Propiedades lo necesita, se porta con su prueba.
-- LAS FACTURAS, PROFORMAS Y RECIBIS CONSERVAN «<proyecto> — <parcela>» AL EDITARSE (14-oct-2026, Backend; fallo 4 de los que encontro
--   el orquestador al aplicar REC00015/REC00019: REC00019 paso de «Bonian Village — C5» a «Bonian Village» al guardarlo).
-- CAUSA: trg_espejo_proyecto (BEFORE INSERT OR UPDATE OF proyecto_id, proyecto_nombre, en contratos y en facturas) pone
--   proyecto_nombre := proyectos.nombre siempre que hay proyecto_id. En un INSERT de la pantalla corre antes de que se herede el
--   proyecto_id (orden alfabetico de los BEFORE), y el texto con la parcela sobrevive; al EDITAR (factura_guarda / guardar_recibi
--   reescriben proyecto_nombre en su UPDATE) el proyecto_id ya esta y el trigger lo pisa. El papel no cambia (se pinta desde
--   datos.fields); se pierde la COLUMNA, que usan el listado, el filtro y el buscador. Medido el 14-oct (solo lectura): 189
--   documentos guardan la parcela en la columna y 40 la perdieron al editarse.
-- QUE HACE:
--   (i) trg_espejo_proyecto: SOLO en facturas, si el texto que llega empieza por «nombre del proyecto + espacio» y lleva algo
--       detras, se conserva. Si no (otro proyecto, el nombre a secas, texto libre), se normaliza al nombre del proyecto, como hoy.
--       Contratos NO cambia: alli la parcela va en parcela_codigo y el nombre a secas es lo correcto. El texto del sufijo es libre
--       (como ya lo era en datos.fields y en cada INSERT): no decide permisos ni importes, que van por proyecto_id.
--  (ii) renombrar_proyecto: hoy solo renombra las facturas con el nombre EXACTO; las 189 con parcela se quedaban con el nombre
--       viejo. Ahora tambien cambia el prefijo de las de ese proyecto_id (columna en todas; datos.fields en las no enviadas ni
--       anuladas, la misma regla que ya tenia para el nombre exacto) y las cuenta en `facturas`. Se acota por proyecto_id para no
--       tocar otro proyecto cuyo nombre empiece igual («Sumba Hills» / «Sumba Hills by ...»).
-- LO QUE NO HACE: no recoloca los 40 documentos que ya perdieron la parcela (es un UPDATE de datos reales, con su fichero de vuelta
--   atras, aparte). La pantalla del recuento de «Renombrar» (editores.js) se corrige en la misma copia.
-- Las dos se REESCRIBEN ENTERAS desde su definicion viva, con este md5 de pg_get_functiondef (sin retorno de carro) medido en el vivo
--   el 14-oct-2026 en la sesion 1014-2147 (solo lectura):
--     trg_espejo_proyecto()              6ddd6fbe892437e14c8d5af6347f196a
--     renombrar_proyecto(text, text)     f3a96bfd14b9ab63406eedd3a61e01eb
--   Si alguna ya no tiene ese md5 y tampoco lleva ya este arreglo, el bloque $antes$ lanza y no se aplica NADA. Idempotente.
--   create or replace conserva dueno y permisos (renombrar_proyecto: authenticated si, anon no, service_role si, medido el 14-oct);
--   el bloque $cierre$ lo comprueba.
-- REVERTIR: supabase/reversion_facturas_conservan_parcela/REVERSION.sql (los dos textos vivos de antes, tal cual).
-- Prueba: supabase/pruebas/facturas_conservan_parcela.sql (crea contratos y facturas: SOLO en rama):
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261014220000_facturas_conservan_parcela.sql
--          --prueba facturas_conservan_parcela.sql

set local lock_timeout = '5s';

-- ============================================================ 0. Marca y raise
do $antes$
declare x record;
begin
  for x in select * from (values
             ('public.trg_espejo_proyecto()',          '6ddd6fbe892437e14c8d5af6347f196a', 'se conserva (14-oct-2026)'),
             ('public.renombrar_proyecto(text,text)',  'f3a96bfd14b9ab63406eedd3a61e01eb', 'v_facturas_parcela')) t(f, m, marca)
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
  v_nombre text;
begin
  -- la regla del proyecto vive en _contrato_proyecto_de (13-oct-2026): la usan tambien _trg_contrato_tipo_valido y
  -- _trg_contrato_campos_propios, que se disparan antes que este trigger
  new.proyecto_id := public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre);

  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      -- facturas: «<proyecto> — <parcela>» se conserva (14-oct-2026): al editar, el texto con la parcela se perdia
      if tg_table_name = 'facturas'
         and left(coalesce(new.proyecto_nombre, ''), length(v_nombre) + 1) = v_nombre || ' '
         and btrim(substr(new.proyecto_nombre, length(v_nombre) + 2)) <> '' then
        null;
      else
        new.proyecto_nombre := v_nombre;
      end if;
    end if;
  end if;
  return new;
end
$function$;

-- ============================================================ (ii) renombrar_proyecto
CREATE OR REPLACE FUNCTION public.renombrar_proyecto(p_antiguo text, p_nuevo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_unidades int; v_contratos int; v_facturas int; v_documentos int; v_modelos int;
  v_pid uuid; v_facturas_parcela int;
begin
  if not public.es_admin_de((select pr.empresa from public.proyectos pr where pr.nombre = p_antiguo)) then
    raise exception 'Solo un administrador puede renombrar un proyecto' using errcode = '42501';
  end if;
  if p_antiguo is null or trim(p_antiguo) = '' or p_nuevo is null or trim(p_nuevo) = '' then
    raise exception 'Nombre de proyecto vacío';
  end if;
  if p_antiguo = p_nuevo then
    return jsonb_build_object('sin_cambios', true);
  end if;
  if length(btrim(p_nuevo)) > 120 then raise exception 'El nombre no puede pasar de 120 caracteres' using errcode = '22023'; end if;
  if btrim(p_nuevo) ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos where nombre = p_nuevo) then
    raise exception 'Ya existe un proyecto llamado "%"', p_nuevo;
  end if;

  select pr.id into v_pid from public.proyectos pr where pr.nombre = p_antiguo;
  update public.proyectos set nombre = p_nuevo where nombre = p_antiguo;

  update public.unidades set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_unidades = row_count;

  update public.contratos set proyecto_nombre = p_nuevo where proyecto_nombre = p_antiguo;
  get diagnostics v_contratos = row_count;
  update public.contratos c
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and bloqueado = false
     and datos #>> '{fields,proyecto_nombre}' = p_antiguo
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas set proyecto_nombre = p_nuevo where proyecto_nombre = p_antiguo;
  get diagnostics v_facturas = row_count;
  update public.facturas
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and not anulada and not enviada
     and datos #>> '{fields,proyecto_nombre}' = p_antiguo;

  -- «<proyecto> — <parcela>» (14-oct-2026): se cambia el prefijo, solo en los documentos de ESE proyecto
  update public.facturas
     set proyecto_nombre = p_nuevo || substr(proyecto_nombre, length(p_antiguo) + 1)
   where proyecto_id = v_pid
     and left(proyecto_nombre, length(p_antiguo) + 1) = p_antiguo || ' ';
  get diagnostics v_facturas_parcela = row_count;
  v_facturas := v_facturas + v_facturas_parcela;
  update public.facturas
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}',
                           to_jsonb(p_nuevo || substr(datos #>> '{fields,proyecto_nombre}', length(p_antiguo) + 1)))
   where proyecto_id = v_pid and not anulada and not enviada
     and left(datos #>> '{fields,proyecto_nombre}', length(p_antiguo) + 1) = p_antiguo || ' ';

  update public.documentos_proyecto set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_documentos = row_count;

  update public.modelos_villa set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_modelos = row_count;

  return jsonb_build_object(
    'unidades', v_unidades, 'contratos', v_contratos, 'facturas', v_facturas,
    'documentos_proyecto', v_documentos, 'modelos_villa', v_modelos
  );
end;
$function$;

-- ============================================================ cierre: permisos como estaban
do $cierre$
begin
  if not has_function_privilege('authenticated', 'public.renombrar_proyecto(text,text)', 'execute')
     or has_function_privilege('anon', 'public.renombrar_proyecto(text,text)', 'execute')
     or not has_function_privilege('service_role', 'public.renombrar_proyecto(text,text)', 'execute') then
    raise exception 'facturas_conservan_parcela: los permisos de renombrar_proyecto cambiaron; no se aplica';
  end if;
end $cierre$;
