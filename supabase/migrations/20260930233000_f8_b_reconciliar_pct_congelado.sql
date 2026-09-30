-- F8 (b) · el reconciliador respeta el % congelado de la plantilla (hallazgo del revisor, 30-sep).
-- El motor (20260930230000) calcula el devengo de closer con plantilla.closer% x condicion manager y lo congela en
-- disparado_por_snapshot (pct_comision efectivo + plantilla_pct). comisiones_reconciliar recalculaba con el % de la CONDICION
-- (2,5): mientras plantilla=25 y manager=10 coincide, pero en cuanto el SM edite su plantilla, o el manager no sea 10 %, el
-- recalculo automatico veria un delta falso en el closer. Solo cambia cuando el devengo lleva plantilla_pct: el resto de
-- devengos sigue con el % de su condicion, como hasta hoy. Parche sobre la version VIVA, con ancla unica comprobada.
do $parche$
declare
  v_def text := pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure);
  v_ancla constant text := 'select d.*, c.base_calculo, c.pct_comision, c.importe_fijo, t.pct_tramo';
  v_nuevo constant text := 'select d.*, c.base_calculo, case when d.disparado_por_snapshot->>''plantilla_pct'' is not null then nullif(d.disparado_por_snapshot->>''pct_comision'', '''')::numeric else c.pct_comision end as pct_comision, c.importe_fijo, t.pct_tramo';
begin
  if position('plantilla_pct' in v_def) > 0 then
    return;   -- ya aplicado
  end if;
  if (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'comisiones_reconciliar: la ancla del parche F8(b) no aparece exactamente una vez; revisar la version viva';
  end if;
  execute replace(v_def, v_ancla, v_nuevo);
end
$parche$;

comment on table public.plantilla_reparto is
  'Plantilla con la que el Sales Manager reparte SU bote (el 10 % que Lawang le paga) entre los roles de su equipo (D5). Desde F8 (30-sep-2026) el motor la LEE: el devengo informativo del closer = plantilla.closer % x condicion manager, congelado en el primer devengo de cada venta. Sigue siendo herramienta del SM y NUNCA un pago de Lawang: no genera solicitudes_pago, ni comisiones_diferencias, ni conciliacion. Lawang paga el bote AL SM, UNICO perceptor (D3 + Admin #162). Suma 100 por equipo (trigger diferido). Sin policies y sin grants a authenticated: se lee y se guarda por RPC.';
