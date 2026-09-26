-- destructivo-ok: el unico DELETE vive dentro de factura_borra y esta migracion lo RESTRINGE (solo proformas); no borra ninguna fila.
-- LAW-341, decisiones del owner 26-sep-2026 (recomendación de Administración):
-- (a) Una FACTURA ya enviada no se edita en nada (cliente, empresa, fecha, concepto ni importes):
--     se corrige con una rectificativa. En una PROFORMA enviada (sin valor fiscal) sigue bloqueado
--     solo el importe, como hasta hoy.
-- (b) Solo se BORRAN proformas. Facturas y recibís numerados se ANULAN: borrarlos deja un hueco en
--     la serie fiscal. Sustituye a la decisión del 31-jul (admins podían borrar con aviso).
-- Verificado: ni un super admin borra una factura; cambiar el cliente de una enviada da 42501;
-- anular una enviada sigue funcionando.
do $$
declare def text;
  viejo text := $v$    if v_old.enviada and (v_total is distinct from v_old.total$v$;
  nuevo text := $n$    if v_old.enviada and v_old.tipo = 'factura' then
      raise exception 'La factura % ya se envió: no se edita (ni cliente, ni empresa, ni fecha, ni importes). Se corrige con una rectificativa.', v_old.numero
        using errcode = '42501';
    end if;
    if v_old.enviada and (v_total is distinct from v_old.total$n$;
begin
  def := pg_get_functiondef('public.factura_guarda(uuid, jsonb)'::regprocedure);
  if position(viejo in def) = 0 then
    raise exception 'factura_guarda no tiene el bloque esperado: no se parchea a ciegas';
  end if;
  execute replace(def, viejo, nuevo);
end $$;

create or replace function public.factura_borra(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  -- LAW-341: una factura o un recibí numerados no se borran nunca; se anulan.
  if v_old.tipo <> 'proforma' then
    raise exception '% no se puede borrar: una factura o un recibí numerados se ANULAN (borrarlos deja un hueco en la numeración)', v_old.numero
      using errcode = '42501';
  end if;
  if not (not coalesce(v_old.enviada, false)
          and (public.es_super_admin()
               or (public.es_admin() and not coalesce(v_old.anulada, false)
                   and not exists (select 1 from public.recibi_aplicaciones ra
                                    where ra.factura_id = v_old.id or ra.recibi_id = v_old.id)))) then
    raise exception 'No puedes borrar esta proforma (enviada, con cobros aplicados, o sin permiso). Anúlala.'
      using errcode = '42501';
  end if;
  delete from public.facturas f where f.id = p_id;
end $$;
