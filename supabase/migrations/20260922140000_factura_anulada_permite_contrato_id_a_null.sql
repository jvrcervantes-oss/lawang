-- Hallazgo del verificador tras el deploy de hoy (facturas_contrato_obligatorio_exime_anuladas):
-- el CHECK ya admite que una factura anulada tenga contrato_id NULL, pero
-- `borrar_operacion()` seguía rota — cambió de error, no de síntoma. El
-- trigger `factura_anulada_solo_cambia_autor` (LAW-71, 21-ago-2026) hace que
-- una factura anulada sea inmutable salvo por `creado_por`, y se aplica
-- siempre que `auth.uid()` no sea null — es decir, siempre que quien borra la
-- operación sea un usuario real de la intranet (el caso normal: SECURITY
-- DEFINER no vacía auth.uid(), sigue siendo el de la sesión que llama).
--
-- Verificado en vivo (verificador, con un auth.uid() real simulado): borrar
-- una operación con una factura reciente anulada revienta con
-- "Una factura anulada es inmutable..." (42501) en el momento en que el
-- DELETE del contrato dispara el ON DELETE SET NULL sobre esa misma factura
-- -- el UPDATE implícito cambia contrato_id, y el trigger lo cuenta como una
-- edición prohibida.
--
-- Fix: además de `creado_por`, se permite que `contrato_id` pase a NULL
-- (nunca a otro valor distinto) en una factura ya anulada. Es precisamente lo
-- que hace el ON DELETE SET NULL al borrar el contrato -- no reescribe
-- historia, solo refleja que el contrato de origen ya no existe. El rastro no
-- se pierde: contrato_numero queda congelado desde antes por
-- trg_facturas_congela_contrato_numero (migración de hoy, 131500) y ese
-- trigger no lo toca. Reasignar contrato_id a un valor DISTINTO de NULL
-- sigue prohibido -- eso sí sería reescribir a qué contrato pertenece un
-- documento ya anulado.
create or replace function public.factura_anulada_solo_cambia_autor()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Sin sesión no hay JWT: es mantenimiento (MCP, cron, service_role), no la
  -- pantalla. Ahí no se aplica — si no, un backfill legítimo sobre una columna
  -- nueva chocaría contra esto y el síntoma no señalaría la causa.
  if (select auth.uid()) is null then
    return new;
  end if;

  if coalesce(old.anulada, false) then
    if new.contrato_id is distinct from old.contrato_id
       and not (old.contrato_id is not null and new.contrato_id is null) then
      raise exception 'Una factura anulada es inmutable: lo unico que se puede cambiar es su autor'
        using errcode = '42501';
    end if;

    if (to_jsonb(new) - 'creado_por' - 'contrato_id')
       is distinct from (to_jsonb(old) - 'creado_por' - 'contrato_id') then
      raise exception 'Una factura anulada es inmutable: lo unico que se puede cambiar es su autor'
        using errcode = '42501';
    end if;
  end if;

  return new;
end
$$;

revoke execute on function public.factura_anulada_solo_cambia_autor() from public;
