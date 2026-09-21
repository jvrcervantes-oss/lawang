-- Candado de base para rol/herramientas de usuarios (Seguridad, revisión previa 19-sep-2026,
-- encargos/20260919_lawang_v4_paridad_lanzamiento.md → Decisiones).
--
-- Motivo: la policy UPDATE de public.usuarios es
--   qual/with_check: es_admin() AND puede('usuarios') AND (rol <> 'super_admin' OR es_super_admin())
-- que solo impide ASCENDER a alguien a super_admin. No impide que cualquier admin (no super) con
-- el permiso 'usuarios' ascienda un agente a admin, ni que cambie el array `herramientas` de sí
-- mismo o de cualquier otro, vía API directa (sin pasar por la UI ni por la edge admin-usuarios).
-- «Solo el super_admin reparte poder» lo cumplía la edge al CREAR, no la base al EDITAR.
--
-- Este trigger cierra ese hueco: cualquier UPDATE que toque rol o herramientas sin ser
-- es_super_admin() falla. No toca la policy existente (sigue haciendo su parte) ni ninguna otra
-- columna de usuarios.

create or replace function public.usuarios_bloquea_cambio_rol_herramientas()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if (new.rol is distinct from old.rol or new.herramientas is distinct from old.herramientas)
     and not public.es_super_admin() then
    raise exception 'Solo un super_admin puede cambiar el rol o las herramientas de un usuario'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

-- destructivo-ok: DROP TRIGGER IF EXISTS solo por idempotencia — verificado antes de escribir esta
-- migración que public.usuarios no tenía ningún trigger propio (pg_trigger vacío); no borra datos,
-- solo re-crea limpio si esta migración se reaplicase.
drop trigger if exists usuarios_candado_rol_herramientas on public.usuarios;

create trigger usuarios_candado_rol_herramientas
before update on public.usuarios
for each row
execute function public.usuarios_bloquea_cambio_rol_herramientas();
