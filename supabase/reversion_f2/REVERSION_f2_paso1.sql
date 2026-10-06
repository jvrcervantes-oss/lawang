-- REVERSION del paso 1 de la Fase 2 (empresas). Capturada ANTES de aplicar (7-oct-2026). Orden: triggers -> funciones -> constraints -> columnas -> rol_check.
-- Solo vale mientras ningun usuario tenga rol de empresa (si lo hay: primero cambiarle el rol a 'agente' y borrar ambito/empresas).
drop trigger usuarios_empresas_validas on public.usuarios;
drop trigger usuarios_candado_alta on public.usuarios;
drop trigger usuarios_candado_baja on public.usuarios;
drop function public.usuarios_empresas_validas(), public.usuarios_candado_alta(), public.usuarios_candado_baja();
-- trigger de cambios: definicion anterior, tal cual estaba en produccion el 7-oct-2026
create or replace function public.usuarios_bloquea_cambio_rol_herramientas() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.rol is distinct from old.rol or new.herramientas is distinct from old.herramientas)
     and not public.es_super_admin() then
    raise exception 'Solo un super_admin puede cambiar el rol o las herramientas de un usuario'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
drop function public.es_propietario(), public.es_admin_de(text), public.es_super_admin_de(text), public.puede_empresa(text), public.mi_alcance();
alter table public.usuarios drop constraint usuarios_propietario_check, drop constraint usuarios_ambito_rol_check;
alter table public.usuarios drop column ambito, drop column empresas, drop column es_propietario;
alter table public.usuarios drop constraint usuarios_rol_check;
alter table public.usuarios add constraint usuarios_rol_check check (rol = any (array['super_admin'::text, 'admin'::text, 'agente'::text, 'sales_manager'::text, 'project_manager'::text]));
