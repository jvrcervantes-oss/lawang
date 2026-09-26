-- destructivo-ok: retira la policy de storage «agentes borran justificantes» (quita un permiso de BORRAR comprobantes de pago que ninguna pantalla usa) y sustituye tres policies de contratos-firmados por versiones más estrechas; no borra ni cambia ningún fichero ni fila.
-- LAW-336 pieza 5, ARREGLO URGENTE previo (revisión previa #120, Seguridad + Legal, 26-sep-2026).
-- Antes de sacar contratos y firmas del navegador hay tres agujeros que no pueden esperar al plan:
-- 1) contrato_firmas: la policy de UPDATE dejaba al autor/manager escribir CUALQUIER columna —
--    `estado='firmado'`, `firmado_en`, `firmante_ip`, `pdf_hash`, `token_hash`, `firmante_email`,
--    `expira_en`—: una firma se podía dar por hecha, o quedarse con un enlace vivo, sin el comprador.
--    Ahora, desde el navegador (rol authenticated) solo se CREA una firma —que nace pendiente, sin
--    firmar, con su caducidad del servidor— o se ANULA. Todo lo demás lo escribe solo firma-submit
--    (service_role) o una función del servidor.
-- 2) storage contratos-firmados: cualquier agente podía subir a cualquier ruta y reescribir o borrar el
--    snapshot de un contrato ajeno enviado a firma (lo que va a firmar el comprador). Ahora solo el autor
--    o su manager, solo en las dos rutas de SU contrato (`pendientes/<id>.html`, `<numero>_manual.pdf`),
--    con el contrato sin cerrar, y el snapshot solo mientras nadie ha firmado aún.
-- 3) storage justificantes: cualquier agente podía BORRAR cualquier comprobante de pago. Ninguna pantalla
--    borra justificantes (medido): la policy se retira.
-- Y 4) contratos: `pdf_firmado_path/hash` una vez puestos no cambian (salvo super admin), y el que pone
--    el navegador solo puede ser la ruta manual de ESE contrato.
-- `creado_por` NO necesitaba arreglo: trg_00_fija_autor ya lo impone al crear e impide cambiarlo.

create or replace function public._firma_solo_servidor() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- solo frena al navegador; firma-submit (service_role) y las funciones DEFINER (postgres) pasan
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    new.estado := 'pendiente';
    new.firmado_en := null; new.firmante_ip := null; new.firmante_user_agent := null;
    new.pdf_path := null; new.pdf_hash := null;
    new.creado_en := now(); new.expira_en := now() + interval '30 days';
    return new;
  end if;
  if (to_jsonb(new) - 'estado') is distinct from (to_jsonb(old) - 'estado')
     or (new.estado is distinct from old.estado and new.estado <> 'anulado') then
    raise exception 'Una firma solo se puede anular desde aquí; firmarla o cambiar sus datos lo hace el servidor'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public._firma_solo_servidor() from public, anon, authenticated;
create trigger trg_00_firma_solo_servidor before insert or update on public.contrato_firmas
  for each row execute function public._firma_solo_servidor();

create or replace function public._contrato_pdf_firmado_fijo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user not in ('authenticated', 'anon') or public.es_super_admin() then return new; end if;
  if tg_op = 'UPDATE' and old.pdf_firmado_path is not null
     and (new.pdf_firmado_path is distinct from old.pdf_firmado_path or new.pdf_firmado_hash is distinct from old.pdf_firmado_hash) then
    raise exception 'El PDF firmado de un contrato no se cambia' using errcode = '42501';
  end if;
  if new.pdf_firmado_path is not null
     and (tg_op = 'INSERT' or new.pdf_firmado_path is distinct from old.pdf_firmado_path)
     and new.pdf_firmado_path <> coalesce(new.numero, '') || '_manual.pdf' then
    raise exception 'Ruta de PDF firmado no válida para este contrato' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public._contrato_pdf_firmado_fijo() from public, anon, authenticated;
create trigger trg_01_contrato_pdf_firmado_fijo before insert or update on public.contratos
  for each row execute function public._contrato_pdf_firmado_fijo();

create or replace function public.agente_escribe_fichero_contrato(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and exists (
    select 1 from public.contratos c
     where coalesce(c.bloqueado, false) = false
       and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))
       and (p_name = c.numero || '_manual.pdf'
            or (p_name = 'pendientes/' || c.id::text || '.html'
                and not exists (select 1 from public.contrato_firmas f
                                 where f.contrato_id = c.id and f.estado = 'firmado'))))
$$;
revoke all on function public.agente_escribe_fichero_contrato(text) from public, anon;
grant execute on function public.agente_escribe_fichero_contrato(text) to authenticated;

drop policy if exists "agentes autenticados suben pdf firmado" on storage.objects;
create policy "agentes autenticados suben pdf firmado" on storage.objects for insert to authenticated
  with check (bucket_id = 'contratos-firmados' and public.agente_escribe_fichero_contrato(name));
drop policy if exists "agentes reescriben el snapshot pendiente" on storage.objects;
create policy "agentes reescriben el snapshot pendiente" on storage.objects for update to authenticated
  using (bucket_id = 'contratos-firmados' and name like 'pendientes/%' and public.agente_escribe_fichero_contrato(name))
  with check (bucket_id = 'contratos-firmados' and name like 'pendientes/%' and public.agente_escribe_fichero_contrato(name));
drop policy if exists "agentes borran el snapshot pendiente" on storage.objects;
create policy "agentes borran el snapshot pendiente" on storage.objects for delete to authenticated
  using (bucket_id = 'contratos-firmados' and name like 'pendientes/%' and public.agente_escribe_fichero_contrato(name));
drop policy if exists "agentes borran justificantes" on storage.objects;
