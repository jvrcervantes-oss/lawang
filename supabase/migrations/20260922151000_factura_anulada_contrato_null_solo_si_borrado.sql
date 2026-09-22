-- Hallazgo MEDIA de Seguridad: la excepción añadida en
-- 20260922140000_factura_anulada_permite_contrato_id_a_null permitía que
-- CUALQUIER contrato_id->NULL pasara en una factura anulada, sin comprobar
-- que fuera de verdad el ON DELETE SET NULL de un contrato borrado -- la
-- policy de UPDATE de facturas exime a es_super_admin() de "anulada=false",
-- así que un super_admin podía desvincular a mano cualquier factura anulada
-- de su contrato, fuera de borrar_operacion(), sin dejar registrado el motivo.
--
-- Decisión del owner (22-sep-2026): acotar la excepción a que el contrato
-- referenciado YA NO EXISTA. Es exactamente el caso real (borrar_operacion
-- borra el contrato Y ENTONCES el ON DELETE SET NULL corre) y cierra la vía
-- manual/silenciosa: un super_admin ya no puede desvincular una factura
-- anulada de un contrato que sigue vivo.
create or replace function public.factura_anulada_solo_cambia_autor()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;

  if coalesce(old.anulada, false) then
    if new.contrato_id is distinct from old.contrato_id then
      if old.contrato_id is null
         or new.contrato_id is not null
         or exists (select 1 from public.contratos c where c.id = old.contrato_id) then
        raise exception 'Una factura anulada es inmutable: lo unico que se puede cambiar es su autor'
          using errcode = '42501';
      end if;
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
