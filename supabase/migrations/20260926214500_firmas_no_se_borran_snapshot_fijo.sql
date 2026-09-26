-- destructivo-ok: retira la policy «agentes borran firmas» y el DELETE de contrato_firmas a authenticated (quita un permiso de borrar firmas que ninguna pantalla usa); no borra ninguna fila.
-- Consulta de deploy de Seguridad sobre 20260926213000 (26-sep-2026, dos MEDIA):
-- 1) Un agente podía BORRAR una firma ya hecha de su contrato —sin rastro: firma_evento_log no mira
--    DELETE— y, sin firmas, volver a reescribir el snapshot que el comprador ya firmó. Ninguna pantalla
--    borra firmas (medido; borrar_operacion es DEFINER). Las firmas no se borran: se anulan.
-- 2) `snapshot_path` llegaba del navegador: una firma de un contrato propio podía apuntar al documento
--    de otro y firma-get/firma-submit (service_role) lo servían. Ahora el servidor la fija a
--    `pendientes/<contrato_id>.html`, que es lo que ya mandaba app.html.
drop policy if exists "agentes borran firmas" on public.contrato_firmas;
revoke delete on public.contrato_firmas from anon, authenticated;

create or replace function public._firma_solo_servidor() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    new.estado := 'pendiente';
    new.firmado_en := null; new.firmante_ip := null; new.firmante_user_agent := null;
    new.pdf_path := null; new.pdf_hash := null;
    new.creado_en := now(); new.expira_en := now() + interval '30 days';
    new.snapshot_path := 'pendientes/' || new.contrato_id::text || '.html';
    return new;
  end if;
  if (to_jsonb(new) - 'estado') is distinct from (to_jsonb(old) - 'estado')
     or (new.estado is distinct from old.estado and new.estado <> 'anulado') then
    raise exception 'Una firma solo se puede anular desde aquí; firmarla o cambiar sus datos lo hace el servidor'
      using errcode = '42501';
  end if;
  return new;
end $$;
