-- LAW-343, consulta de Seguridad (27-sep-2026). Solo añade: columnas de prueba en correos_enviados, un bucket
-- privado para la copia de lo enviado y una comprobación más en usuario_guarda_permisos. No toca filas.
--
-- 1. PRUEBA DE LO ENVIADO. send-contract-email recibe el HTML/PDF del navegador (hasta que el servidor genere
--    el PDF de la factura, LAW-354 b): un agente podía mandar al comprador un PDF con otra cuenta bancaria y el
--    sistema lo apuntaba como «la factura enviada» sin guardar qué salió. Desde hoy la edge guarda una COPIA del
--    PDF enviado (bucket privado, solo service role), su sha256, su tamaño y el mensaje, en la misma fila.
alter table public.correos_enviados
  add column if not exists mensaje text,
  add column if not exists pdf_path text,
  add column if not exists pdf_sha256 text,
  add column if not exists pdf_bytes integer;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('correos-enviados', 'correos-enviados', false, 104857600, array['application/pdf'])
on conflict (id) do nothing;
-- sin policies en storage.objects para este bucket: ni authenticated ni anon leen ni escriben; solo service role.

-- 2. REACTIVAR una cuenta con más herramientas que las tuyas era quedarte con su acceso (y luego ponerle
--    contraseña por admin-usuarios). Un admin no-super solo reactiva cuentas cuyas herramientas tiene él.
do $$
declare v_def text; v_nuevo text;
begin
  select pg_get_functiondef('public.usuario_guarda_permisos(uuid,jsonb)'::regprocedure) into v_def;
  if strpos(v_def, 'LAW-343 reactivar') > 0 then return; end if;
  v_nuevo := replace(v_def,
    '  v_rol := case when p_cambios ? ''rol'' then p_cambios->>''rol'' else v_old.rol end;',
    '  -- LAW-343 reactivar: un admin no-super solo reactiva cuentas cuyas herramientas tiene él
  if p_cambios ? ''activo'' and (p_cambios->>''activo'')::boolean and not v_old.activo and not public.es_super_admin()
     and not (coalesce(v_old.herramientas, ''{}'') <@ coalesce((select y.herramientas from public.usuarios y
                                                              where y.user_id = (select auth.uid())), ''{}'')) then
    raise exception ''Esa cuenta tiene herramientas que tú no tienes: la reactiva un super admin'' using errcode = ''42501'';
  end if;
  v_rol := case when p_cambios ? ''rol'' then p_cambios->>''rol'' else v_old.rol end;');
  if v_nuevo = v_def then raise exception 'usuario_guarda_permisos cambió: no encuentro dónde insertar la comprobación'; end if;
  execute v_nuevo;
end $$;
