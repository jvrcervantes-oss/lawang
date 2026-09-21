-- destructivo-ok: CREATE OR REPLACE FUNCTION es sustitucion/adicion, no retirada. Sin DELETE/TRUNCATE/RLS off.
-- ════════════════════════════════════════════════════════════════════════════
-- ASIGNAR/QUITAR UN PROYECTO A UN MANAGER, DE FORMA ATOMICA — 11-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Hallazgo de Seguridad en la consulta de deploy (capa 1) sobre
-- intranet/proyectos/index.html: el guardado de managers desde la ficha del
-- proyecto calculaba el array `proyectos` nuevo sobre una copia cacheada al
-- abrir la ficha y lo sobrescribia entero. Si el mismo manager se tocaba casi
-- a la vez desde otra pantalla (/usuarios/ u otra ficha de proyecto), la
-- escritura que llegara segunda pisaba sin aviso la de la primera -- perdida
-- silenciosa de una asignacion o una revocacion, sobre una columna que
-- decide autorizacion.
--
-- Arreglo: un RPC que hace el array_append/array_remove EN LA BASE, en una
-- sola sentencia -- no hay lectura-modificacion-escritura en el cliente que
-- pueda quedarse atrasada. SECURITY DEFINER porque necesita escribir en
-- `usuarios` de otra persona (el propio permiso ya lo exige la policy real,
-- verificado en produccion: "admin edita, pero no toca fila super_admin sin
-- serlo" = es_admin() AND puede('usuarios') AND (rol<>'super_admin' OR
-- es_super_admin())) -- y por eso la funcion REPITE esa misma comprobacion a
-- mano: un SECURITY DEFINER se salta la RLS de la tabla, asi que si la
-- funcion no comprueba nada, cualquiera con EXECUTE tendria via libre.
create or replace function public.usuario_asigna_proyecto(
  p_user_id uuid, p_proyecto_id uuid, p_asignar boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare v_rol text;
begin
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  select rol into v_rol from public.usuarios where user_id = p_user_id;
  if v_rol is null then
    raise exception 'usuario no encontrado' using errcode = '22023';
  end if;
  if v_rol = 'super_admin' and not public.es_super_admin() then
    raise exception 'no autorizado' using errcode = '42501';
  end if;

  if p_asignar then
    update public.usuarios
       set proyectos = (
         select array(select distinct unnest(coalesce(proyectos, '{}'::uuid[]) || array[p_proyecto_id]))
       )
     where user_id = p_user_id;
  else
    update public.usuarios
       set proyectos = array_remove(coalesce(proyectos, '{}'::uuid[]), p_proyecto_id)
     where user_id = p_user_id;
  end if;
end;
$$;
revoke execute on function public.usuario_asigna_proyecto(uuid, uuid, boolean) from public, anon;
grant execute on function public.usuario_asigna_proyecto(uuid, uuid, boolean) to authenticated;

-- Comprobacion (catalogo): select proname from pg_proc where proname='usuario_asigna_proyecto';
;
