-- destructivo-ok: CREATE OR REPLACE FUNCTION es sustitucion/adicion, no retirada. Sin DELETE/TRUNCATE/RLS off.
-- ════════════════════════════════════════════════════════════════════════════
-- ASIGNAR/QUITAR UN PROYECTO A UN MANAGER, DE FORMA ATÓMICA — 11-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Hallazgo de Seguridad en la consulta de deploy (capa 1) sobre
-- intranet/proyectos/index.html: el guardado de managers desde la ficha del
-- proyecto calculaba el array `proyectos` nuevo sobre una copia cacheada al
-- abrir la ficha y lo sobrescribía entero. Si el mismo manager se tocaba casi
-- a la vez desde otra pantalla (/usuarios/ u otra ficha de proyecto), la
-- escritura que llegara segunda pisaba sin aviso la de la primera — pérdida
-- silenciosa de una asignación o una revocación, sobre una columna que
-- decide autorización.
--
-- Arreglo: un RPC que hace el array_append/array_remove EN LA BASE, en una
-- sola sentencia — no hay lectura-modificación-escritura en el cliente que
-- pueda quedarse atrasada. SECURITY DEFINER porque necesita escribir en
-- `usuarios` de otra persona (el permiso ya lo exige la policy real,
-- verificado en producción: «admin edita, pero no toca fila super_admin sin
-- serlo» = es_admin() AND puede('usuarios') AND (rol<>'super_admin' OR
-- es_super_admin())) — y por eso la función REPITE esa misma comprobación a
-- mano: un SECURITY DEFINER se salta la RLS de la tabla, así que si la
-- función no comprueba nada, cualquiera con EXECUTE tendría vía libre.
--
-- ⚠️ Ojo con un hallazgo de la MISMA revisión que resultó ser falso positivo:
-- se citó una migración vieja (`20260811053843_...`) que decía que la policy
-- de UPDATE de `usuarios` solo exigía `es_admin()`, sin `puede()`. Verificado
-- en vivo el 11-sep: la policy real SÍ incluye `puede('usuarios')`, y
-- `puede()` solo se salta las herramientas para `es_super_admin()`, no para
-- cualquier admin. El repo tiene migraciones desincronizadas de producción
-- (precedente: 33 el 9-sep) — un hallazgo de seguridad sobre una policy se
-- verifica contra `pg_policies` en vivo, nunca contra el .sql del repo.
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

-- ── Comprobación ─────────────────────────────────────────────────────────
--   select proname from pg_proc where proname='usuario_asigna_proyecto';
-- Y de comportamiento (probado el 11-sep con DO + rollback, nunca con el MCP):
--   agente sin permiso → excepción 42501; admin/super_admin → asigna, repetir
--   no duplica (dedup por distinct/unnest), quitar sí reduce el array en 1.
