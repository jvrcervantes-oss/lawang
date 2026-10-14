-- «Primero la parcela, luego la obra» — 5.ª parte (14-oct-2026): 3.ª vuelta del revisor de código.
--
-- COMISIONES: «% COBRADO DE OBRA» NO DISPARA CON EL BLOQUEO SIN FIRMAR. Lo cobrado en obra (`v_cobrado_obra`) sale de
-- la cascada, que topa la parcela en el precio del Bloqueo raíz esté firmado o no (decisión del owner, 14-oct). Bajar
-- ese borrador pasa dinero de parcela a obra y adelantaría un tramo `pct_cobrado_obra`; un devengo pagado no se
-- revierte. Misma guarda que Administración escribió para el régimen del 1-nov (siguiente_comisiones_1nov.sql, CTE
-- `g`): con la raíz de la venta = un Bloqueo de Parcela sin firmar, ese disparador no cuenta. No toca
-- `v_cobrado_total` (pct_cobrado_total), ni la obra de una venta cuya raíz no es un Bloqueo, ni `pct_cobrado_suelo`
-- (bajar el borrador solo lo retrasa: el denominador es el firmado, 20261014040310).
-- Medido el 14-oct: 0 tramos vivos con `pct_cobrado_obra`; la pantalla de condiciones lo sigue ofreciendo.
-- Marca de UNA línea sobre el cuerpo vivo, con guarda de md5 del cuerpo de partida (el de 20261014042207).
--
-- Vuelta atrás: supabase/vivo/20261014_cobro_primero_parcela/vuelta.sql. Prueba: T8 y C5.
do $parche$
declare
  v_def text; v_src text;
  m1 text := 'v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral';
  r1 text := 'v_precio_construccion > 0 and (v_contrato_firmado or not exists (select 1 from public.contratos rz where rz.id = v_raiz_id and rz.tipo = ''reserva_parcela'')) and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral';
begin
  select pg_get_functiondef(p.oid), p.prosrc into v_def, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'comisiones_evaluar_contrato';
  if v_def is null then
    raise exception 'cobro_primero_parcela_5: no existe public.comisiones_evaluar_contrato';
  end if;
  if position(r1 in v_def) > 0 then
    return;   -- ya aplicado
  end if;
  if md5(v_src) <> '953634cddf32305588dd3f31ff25ced0' then
    raise exception 'cobro_primero_parcela_5: comisiones_evaluar_contrato no es el cuerpo de partida (md5 %); revisar a mano', md5(v_src);
  end if;
  if (length(v_def) - length(replace(v_def, m1, ''))) / length(m1) <> 1 then
    raise exception 'cobro_primero_parcela_5: comisiones_evaluar_contrato no tiene la marca una vez; revisar a mano';
  end if;
  execute replace(v_def, m1, r1);
end
$parche$;
