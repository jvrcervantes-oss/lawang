-- Mismo criterio que contratos_equipo()/facturas_equipo() (7-ago): Operaciones
-- necesita ver el "cobrado" de TODO el equipo, no solo de sus propios
-- documentos. Devuelve una fila por contrato con dinero (recibí) asociado.
create or replace function public.contratos_cobrado_equipo()
returns table(contrato_id uuid, cobrado numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, public.contrato_cobrado(c.id)
    from public.contratos c
   where public.es_agente();
$$;

revoke all on function public.contratos_cobrado_equipo() from public, anon;
grant execute on function public.contratos_cobrado_equipo() to authenticated;
;
