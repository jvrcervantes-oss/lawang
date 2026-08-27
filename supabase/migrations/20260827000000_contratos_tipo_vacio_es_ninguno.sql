-- 27-ago-2026, owner: «ya actualicé los permisos de los contratos. quita lo de
-- que nada marcado da acceso a todo».
--
-- El «vacío = todos» existía por una razón concreta y ya CADUCADA: la columna se
-- añadió sobre un sistema en marcha, y con la semántica estricta el despliegue
-- habría dejado a los diez agentes sin poder emitir un contrato sin que nadie lo
-- pidiera. Ahora que están configurados —9 de 10— esa protección solo sirve para
-- que un permiso sin rellenar parezca configurado. Vacío = NINGUNO, igual que
-- `proyectos`, y así las dos listas del panel se leen igual.
--
-- ⚠️ Deja fuera al agente que siga con la lista vacía: al aplicarla era uno solo
-- (blueiestates@gmail.com, 0 contratos creados). No se le rellena aquí a
-- escondidas: un permiso se concede en el panel, a la vista, no en una migración.
create or replace function public.contratos_tipo_permitido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_tipos  text[];
begin
  if auth.uid() is null then
    return new;
  end if;

  select rol, tipos_contrato into v_rol, v_tipos
    from public.usuarios where user_id = auth.uid();

  if v_rol is distinct from 'agente' then
    return new;
  end if;

  if v_tipos is null or cardinality(v_tipos) = 0 then
    raise exception 'No tienes ningún tipo de contrato asignado. Pídelo a un administrador en Usuarios.'
      using errcode = '42501';
  end if;

  if not (new.tipo = any(v_tipos)) then
    raise exception 'No tienes permiso para emitir contratos de tipo "%". Pídeselo a un administrador en Usuarios.', new.tipo
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on column public.usuarios.tipos_contrato is
  'Tipos de contrato que esta persona puede emitir. Array VACÍO = NINGUNO, igual que `proyectos`. Se comprueba en el trigger `contratos_tipo_permitido`, no solo en el navegador. Solo afecta al rol `agente`.';
