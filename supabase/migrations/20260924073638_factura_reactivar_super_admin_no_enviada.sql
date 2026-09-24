-- 24-sep-2026 (owner, opción 1): se anuló INV00165 por despiste y solo se pudo
-- deshacer desde la base. Una factura anulada sigue siendo inmutable, con UNA
-- excepción: el super_admin puede devolverla a activa si NUNCA se envió
-- (enviada=false y sin fecha_envio), sin tocar ningún otro campo, y si no hay
-- ya una factura viva que la sustituya (misma operación, tipo e importe,
-- emitida después: la «copia» que ofrece la ficha). Queda en contrato_eventos.
create or replace function public.factura_anulada_solo_cambia_autor()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_sustituta text;
begin
  if (select auth.uid()) is null then
    return new;
  end if;

  if coalesce(old.anulada, false) then
    -- Reactivar: anulada true -> false y nada más cambia.
    if not coalesce(new.anulada, false)
       and (to_jsonb(new) - 'anulada') is not distinct from (to_jsonb(old) - 'anulada') then
      if not public.es_super_admin() then
        raise exception 'Solo un super admin puede reactivar una factura anulada'
          using errcode = '42501';
      end if;
      if coalesce(old.enviada, false) or old.fecha_envio is not null then
        raise exception 'La factura % ya se envio: no se reactiva, se emite una nueva', old.numero
          using errcode = '42501';
      end if;
      if old.tipo = 'factura' and old.contrato_id is null then
        raise exception 'La factura % no tiene contrato: no se puede reactivar', old.numero
          using errcode = '23514';
      end if;
      select f.numero into v_sustituta
        from public.facturas f
       where f.id <> old.id
         and f.contrato_id is not distinct from old.contrato_id
         and f.tipo = old.tipo
         and f.total is not distinct from old.total
         and not coalesce(f.anulada, false)
         and f.created_at > old.created_at
       limit 1;
      if v_sustituta is not null then
        raise exception 'Ya existe % que sustituye a %: reactivarla duplicaria el cobro', v_sustituta, old.numero
          using errcode = '23514';
      end if;
      perform public.registra_privilegio(old.contrato_id, 'factura_reactivada',
        jsonb_build_object('factura', old.numero, 'total', old.total, 'moneda', old.moneda));
      return new;
    end if;

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
$function$;
