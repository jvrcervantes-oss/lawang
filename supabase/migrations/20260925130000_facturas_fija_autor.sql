-- Facturas: el autor y la fecha de alta los pone la base, no quien escribe. 25-sep-2026, OK del owner (AXW-15).
-- Hueco cazado por Seguridad (revisión previa #73 del ERP): `authenticated` puede escribir `creado_por` y
-- `created_at` en `facturas`, así que un agente podía atribuirse facturas de otro, o saltarse el contrato
-- obligatorio (`facturas_contrato_obligatorio` exime `created_at < 2026-08-12`) poniendo una fecha antigua.
-- Probado antes en la demo del ERP (erp/pruebas/operacion_nucleo.sql, 3c) con agentes reales.
--
-- Por trigger y no quitando el permiso de columna: una pantalla que mande el campo no se rompe, solo no manda.
-- Quedan fuera, como hasta hoy: admin/super_admin (traspasar_cliente_con_documentos reasigna autores siendo
-- super_admin), service_role y lo que corre sin sesión (migraciones, rellenos). Respaldo previo de facturas y
-- recibi_aplicaciones en ~/AxisWorks_Backups/lawang_manual/antes_fija_autor_20260924_2259.sql.
create or replace function public.fija_autor() returns trigger
  language plpgsql security definer set search_path to '' as $$
declare v_email text := (select auth.email());
begin
  if (select auth.role()) = 'service_role' or v_email is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if not public.es_admin() then
      new.creado_por := v_email;
      new.created_at := now();
    end if;
    new.creado_por := coalesce(new.creado_por, v_email);
  else
    if new.creado_por is distinct from old.creado_por and not public.es_admin() then
      new.creado_por := old.creado_por;
    end if;
    if new.created_at is distinct from old.created_at then
      new.created_at := old.created_at;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.fija_autor() from public, anon, authenticated;

-- `trg_00_`: los BEFORE van por orden alfabético y este tiene que ser el primero.
create or replace trigger trg_00_fija_autor before insert or update on public.facturas
  for each row execute function public.fija_autor();
