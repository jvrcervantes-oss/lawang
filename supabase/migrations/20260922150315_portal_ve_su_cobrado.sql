-- El portal del comprador enseñaba «cobrado 0» — 22-sep-2026
-- ----------------------------------------------------------------------------
-- Encontrado al revisar contrato_cobrado() para el comprador compartido entre
-- closers (revisión previa #44). Su gate decía «si no eres service_role ni
-- es_agente(), devuelve 0». portal_situacion() lo llama con el JWT del propio
-- comprador, que NO es agente, así que un comprador solo-portal veía 0 en
-- «cobrado» de todos sus contratos. Verificado bajo `set local role
-- authenticated` con una cuenta solo-portal real: contrato con 30.525 cobrados
-- → el portal decía 0. Las cuentas que además son del equipo sí lo veían, y
-- por eso nadie lo notó desde dentro.
--
-- Abrir el gate a es_portal() es seguro DESDE HOY, no antes: la migración
-- 20260922145104 retiró el EXECUTE de contrato_cobrado() a authenticated, así
-- que un comprador ya no puede llamarla a mano para otro contrato; solo llega
-- a ella a través de portal_situacion(), que se limita a los suyos.
create or replace function public.contrato_cobrado(p_contrato_id uuid)
returns numeric
language plpgsql stable security definer set search_path = ''
as $function$
declare v_existe boolean;
begin
  select true into v_existe from public.contratos c where c.id = p_contrato_id;
  if not coalesce(v_existe, false) then return 0; end if;
  if (select auth.role()) <> 'service_role'
     and not (public.es_agente() or public.es_portal()) then
    return 0;
  end if;
  return coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    + coalesce((
      select sum(
        r.total - coalesce((
          select sum(ra.importe_aplicado)
            from public.recibi_aplicaciones ra
            join public.facturas f2 on f2.id = ra.factura_id
           where ra.recibi_id = r.id
             and f2.contrato_id is not null
             and not coalesce(f2.anulada, false)
        ), 0))
        from public.facturas r
       where r.tipo = 'recibi'
         and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
    ), 0);
end;
$function$;
-- CREATE OR REPLACE conserva los grants: sigue SIN EXECUTE para authenticated/anon.
