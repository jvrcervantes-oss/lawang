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

-- destructivo-ok: DROP TRIGGER IF EXISTS solo por idempotencia -- verificado antes de esta
-- migracion que public.usuarios no tenia ningun trigger propio (pg_trigger vacio); no borra datos.
drop trigger if exists usuarios_candado_rol_herramientas on public.usuarios;

create trigger usuarios_candado_rol_herramientas
before update on public.usuarios
for each row
execute function public.usuarios_bloquea_cambio_rol_herramientas();
;
