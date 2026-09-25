-- Previsión de la comisión de administración — 25-sep-2026, owner: «una casilla
-- que sea como una previsión de lo que cobraré si se paga todo lo que hay
-- lanzado». «Lanzado» = contratos FIRMADOS + EN FIRMA (decisión del owner, el
-- mismo día, entre tres opciones: solo firmados · firmados + en firma · facturas
-- emitidas sin cobrar).
--
-- QUÉ SUMA, contrato a contrato: precio_total − lo cobrado (contrato_cobrado(),
-- el mismo criterio de "dinero que entra" que el libro: recibís vivos) − lo que
-- la Carta de Reserva de origen ya cobró y el Bloqueo descuenta
-- (datos.fields.carta_cobrado_importe). Ese dinero de la Carta YA devengó su
-- comisión en su propio recibí: contarlo aquí lo prevería dos veces. Nunca
-- negativo por contrato (un sobrepago no resta de otro contrato).
--
-- QUÉ DEJA FUERA, a propósito:
--   · Cartas de Reserva (tipo carta_reserva*): su precio_total declara la villa
--     ENTERA, que ya cubren su Bloqueo + su Construcción. Sumarla contaría la
--     misma villa dos veces (el mismo fallo que LW_TIPOS_PRELIMINARES evita en
--     Operaciones y Proyectos).
--   · Contratos liberados (liberado_en): la venta se cayó.
--   · Borradores sin enviar a firma: no están "lanzados".
--
-- POR MONEDA, nunca sumadas entre sí (misma regla que el resto del panel).
-- La tarifa es la VIGENTE hoy: es una previsión, no un devengo — cada recibí
-- real congelará la tarifa que rija el día que entre.
-- Solo super_admin, igual que la pantalla y que las dos tablas del libro.
create or replace function public.comision_admin_prevision()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_pct numeric;
  v_out jsonb;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_prevision: solo super_admin';
  end if;

  select t.pct into v_pct
    from public.comision_admin_tarifas t
   where t.efectivo_desde <= current_date
   order by t.efectivo_desde desc
   limit 1;

  with vivos as (
    select coalesce(c.moneda, 'EUR') as moneda,
           c.bloqueado as firmado,
           greatest(coalesce(c.precio_total, 0)
                    - public.contrato_cobrado(c.id)
                    - coalesce(public.lw_importe(c.datos->'fields'->>'carta_cobrado_importe'), 0), 0) as pendiente
      from public.contratos c
     where c.liberado_en is null
       and c.tipo not like 'carta_reserva%'
       and coalesce(c.precio_total, 0) > 0
       and (c.bloqueado or public.contrato_firma_viva(c.id))
  ), por_moneda as (
    select moneda,
           count(*) filter (where firmado)                          as n_firmados,
           coalesce(sum(pendiente) filter (where firmado), 0)       as pend_firmados,
           count(*) filter (where not firmado)                      as n_en_firma,
           coalesce(sum(pendiente) filter (where not firmado), 0)   as pend_en_firma
      from vivos group by moneda
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', moneda,
           'n_firmados', n_firmados, 'pendiente_firmados', pend_firmados,
           'n_en_firma', n_en_firma, 'pendiente_en_firma', pend_en_firma,
           'pendiente', pend_firmados + pend_en_firma,
           'comision', case when v_pct is null then null
                            else round((pend_firmados + pend_en_firma) * v_pct / 100, 2) end,
           'comision_firmados', case when v_pct is null then null
                            else round(pend_firmados * v_pct / 100, 2) end
         ) order by moneda), '[]'::jsonb)
    into v_out
    from por_moneda;

  return jsonb_build_object('pct', v_pct, 'monedas', v_out);
end;
$$;

revoke all on function public.comision_admin_prevision() from public, anon, authenticated;
grant execute on function public.comision_admin_prevision() to authenticated;

comment on function public.comision_admin_prevision() is
  'Previsión de la comisión de administración (solo super_admin): tarifa vigente × lo que falta por cobrar de los contratos firmados + en firma (sin Cartas de Reserva ni liberados), por moneda. 25-sep-2026, owner.';
