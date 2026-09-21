-- contrato_cobrado(): recupera el EXECUTE de `authenticated` sin reabrir el
-- oráculo — incidente en vivo, 18-sep-2026
--
-- QUÉ PASÓ. La consulta de deploy de ayer (20260917145913) revocó el EXECUTE de
-- `authenticated` sobre `contrato_cobrado(uuid)` para cerrar un oráculo real:
-- cualquier sesión con rol `authenticated` (agente, o un comprador del portal
-- si comparte rol) podía pedir `rpc/contrato_cobrado` con el uuid de un contrato
-- ajeno y leer lo cobrado. Diagnóstico correcto — pero esa misma revocación
-- rompió `contratos_cobrado_equipo()` (20260911031517, SECURITY INVOKER), que
-- llama a `contrato_cobrado(c.id)` DESDE la sesión del propio agente para cada
-- fila que la RLS de `contratos` ya le dejó ver. Sin el EXECUTE, esa llamada
-- interna también revienta: "permission denied for function contrato_cobrado"
-- al abrir Facturas, Compradores o Vencimientos — lo reportó el owner en vivo.
--
-- ARREGLO. No se reabre el oráculo, se cierra DENTRO de la función: antes de
-- sumar nada, `contrato_cobrado` exige ahora `es_agente()` (mismo candado que ya
-- usan las cinco `*_equipo()` desde el 11-sep) o `auth.role() = 'service_role'`
-- (la Edge Function factura-vencimiento la llama con la service key). Un
-- comprador del portal — que no es agente — recibe 0, no la cifra real: el
-- oráculo desaparece. Un agente cualquiera sigue viendo el total COMPLETO de
-- cualquier contrato del equipo, no solo el suyo — a propósito, igual que antes
-- de hoy: el cálculo de dinero no es cuestión de propiedad de fila (ver
-- 20260911031517 — "el recibí que salda la factura pudo emitirlo otro agente"),
-- y `carta_cobrado_al_bloquear()` (17-sep) sigue necesitando sumar Cartas de
-- Reserva de OTROS agentes sobre la misma parcela para el descuento en cascada.
create or replace function public.contrato_cobrado(p_contrato_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_existe boolean;
begin
  select true into v_existe from public.contratos c where c.id = p_contrato_id;

  if not coalesce(v_existe, false) then
    return 0;
  end if;

  if (select auth.role()) <> 'service_role' and not public.es_agente() then
    return 0;
  end if;

  return
    coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    +
    coalesce((
      select sum(
               r.total - coalesce((
                 select sum(ra.importe_aplicado)
                   from public.recibi_aplicaciones ra
                   join public.facturas f2 on f2.id = ra.factura_id
                  where ra.recibi_id = r.id
                    and f2.contrato_id is not null
                    and not coalesce(f2.anulada, false)
               ), 0)
             )
        from public.facturas r
       where r.tipo = 'recibi'
         and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
    ), 0);
end;
$$;

comment on function public.contrato_cobrado(uuid) is
  'Suma lo cobrado (recibí aplicados + recibí directo sin factura) de un contrato. SECURITY DEFINER para leer facturas/recibi_aplicaciones sin las RLS del que mira — misma cifra la vea quien la vea del equipo (20260911031517). Desde el 18-sep se guarda ella misma: exige es_agente() o auth.role()=service_role antes de sumar, si no devuelve 0 — así puede tener EXECUTE para `authenticated` (lo perdió en 20260917145913 por el hallazgo de oráculo) sin que un comprador del portal pueda leer lo cobrado de un contrato ajeno pidiendo el rpc a pelo con un uuid cualquiera.';

grant execute on function public.contrato_cobrado(uuid) to authenticated;
;
