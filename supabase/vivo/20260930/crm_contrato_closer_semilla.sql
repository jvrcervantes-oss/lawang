-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.crm_contrato_closer_semilla).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.crm_contrato_closer_semilla()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if NEW.contrato_padre_id is not null then
    return NEW;
  end if;

  if NEW.creado_por is null then
    return NEW;
  end if;

  if not public.crm_usuario_activo(NEW.creado_por) then
    return NEW;
  end if;

  insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
       values (NEW.id, NEW.creado_por, 'sistema:alta', now())
  on conflict (contrato_id) do nothing;

  if found then
    insert into public.contrato_closer_log (contrato_id, de, a, autor)
         values (NEW.id, null, NEW.creado_por, 'sistema:alta');
  end if;

  return NEW;
end;
$function$
