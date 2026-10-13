-- «Obra firmada» sale SOLO de un hijo de obra firmado (13-oct-2026).
--
-- Por qué: el owner fijó el orden de la venta 1 Bloqueo (reserva_parcela) · 2 Construcción · 3 Hak Sewa ·
-- 4 Poder, y desde el commit 749e661a5 de Frontend un Hak Sewa nuevo se guarda con contrato_padre_id = su
-- Bloqueo. Las tres funciones que dicen «la obra está firmada» contaban CUALQUIER hijo firmado del Bloqueo:
--   - unidad_parte_cobrada_split (la lee la vista unidades_estado → barra de obra del inventario,
--     intranet/v4/assets/datos.js:5096): todo hijo que no sea de etapa 'reserva'. Un hak_sewa_notario
--     (etapa 'contrato') o un poa contaban como obra. Medido hoy: SH-144 sale «obra firmada» solo por el
--     Poder PA00010 de RP00170.
--   - unidad_parte_cobrada_interno (la usan unidad_cumple_estado y comisiones_evaluar_contrato): todo hijo
--     que no sea 'carta_reserva'. Medido hoy: B2, B3, B4, B6, B7 de Mejan Village S7 salen «obra firmada»
--     por la Carta PMA CP00002, y SH-144 por el Poder.
--   - comisiones_evaluar_contrato (v_obra_firmada): cualquier hijo firmado, Cartas incluidas. Medido hoy:
--     12 raíces a true sin obra firmada (9 Bloqueos con Carta: RP00040, 045, 198, 202, 203, 204, 259, 262,
--     264; RP00159 por la CP; HS00003 y RP00170 por un Poder). Hoy hay 0 tramos con
--     disparador_tipo = 'obra_firmada', así que no movía dinero; sí iba al snapshot del devengo (14 devengos
--     congelados con obra_firmada = true, 1 de ellos sin obra firmada: NO se toca, es historia).
--
-- Qué es «de obra»: tipo in ('construccion', 'cc00014_timon'). cc00014_timon es una Construcción de
-- ejemplar único, serie CC: contracts/assets/vocabulario.js:59 la rotula «Construcción · CC00014 Timon» y
-- su único contrato (CC00088) cuelga del Bloqueo RP00026 como cualquier Construcción. OJO: la nota de
-- contrato_tipo_etapa la llama «Contrato de compra (ejemplar propio)»; la etapa ('contrato') es la misma,
-- la nota es la que está mal. No hay columna que marque «es obra»: la lista vive en las tres funciones de
-- aquí abajo y en ningún otro sitio.
--
-- Qué NO cambia: el reparto de COBROS (cobrado_suelo / cobrado_obra). Eso es dinero y lo decide el
-- owner con Administración. Medido sin aplicar el 13-oct: los 10.000 EUR de CP00002 (Carta PMA) la pantalla
-- (_split) los cuenta como suelo y estado/comisiones (_interno) como obra; ninguna unidad cambiaría de
-- estado ni ningún tramo dispararía si se igualasen. El cálculo de «asignadas» (qué parcela tiene ya su
-- Construcción) tampoco cambia: hoy solo las Construcciones llevan unidad_id.
--
-- Cómo: parche de función viva con marca de UNA línea (pg_get_functiondef → replace → execute), que exige
-- encontrar la marca exactamente una vez. CREATE OR REPLACE conserva SECURITY DEFINER, search_path y los
-- grants. Idempotente: si la función ya lleva el cambio, la salta.
--
-- Vuelta atrás: el mismo bloque con las parejas (marca, nuevo) invertidas.

do $$
declare
  p   record;
  def text;
  n   int;
begin
  for p in
    select * from (values
      -- 1) _interno: obra_firmada solo de hijos de obra (hijos lleva la columna tipo)
      ('public.unidad_parte_cobrada_interno(uuid)'::regprocedure,
       'select exists (select 1 from hijos_obra hj where hj.bloqueado = true',
       'select exists (select 1 from hijos hj where hj.tipo in (''construccion'', ''cc00014_timon'') and hj.bloqueado = true'),
      -- 2a) _split: el CTE hijos no traía el tipo; se añade (columna extra, nadie la suma)
      ('public.unidad_parte_cobrada_split(uuid)'::regprocedure,
       'select h.id, h.unidad_id, h.bloqueado, coalesce(public.contrato_cobrado(h.id), 0) as cobrado',
       'select h.id, h.unidad_id, h.bloqueado, h.tipo, coalesce(public.contrato_cobrado(h.id), 0) as cobrado'),
      -- 2b) _split: obra_firmada solo de hijos de obra
      ('public.unidad_parte_cobrada_split(uuid)'::regprocedure,
       'where hj.bloqueado = true',
       'where hj.bloqueado = true and hj.tipo in (''construccion'', ''cc00014_timon'')'),
      -- 3) comisiones: v_obra_firmada solo de hijos de obra
      ('public.comisiones_evaluar_contrato(uuid)'::regprocedure,
       'where h.contrato_padre_id = v_raiz_id and h.bloqueado',
       'where h.contrato_padre_id = v_raiz_id and h.bloqueado and h.tipo in (''construccion'', ''cc00014_timon'')')
    ) as t(fn, marca, nuevo)
  loop
    def := pg_get_functiondef(p.fn);
    if position(p.nuevo in def) > 0 then
      continue;  -- ya aplicado
    end if;
    n := (length(def) - length(replace(def, p.marca, ''))) / length(p.marca);
    if n <> 1 then
      raise exception 'obra_firmada: la marca «%» aparece % veces en % (se esperaba 1)', p.marca, n, p.fn;
    end if;
    execute replace(def, p.marca, p.nuevo);
  end loop;
end
$$;
