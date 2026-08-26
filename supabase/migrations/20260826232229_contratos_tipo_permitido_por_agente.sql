-- El permiso de verdad vive AQUÍ, no en el desplegable. Filtrar el selector en
-- el navegador esconde la opción; no impide un POST a PostgREST con el tipo que
-- sea. Es la misma regla que ya rige para RLS en esta suite.
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
  -- Sin sesión (service role, edges, cron) no se comprueba: esos caminos ya
  -- tienen su propia puerta y bloquearlos aquí rompería la firma automática.
  if auth.uid() is null then
    return new;
  end if;

  select rol, tipos_contrato into v_rol, v_tipos
    from public.usuarios where user_id = auth.uid();

  -- Solo aplica a AGENTES, igual que la restricción por proyectos: un
  -- administrador trabaja con todos los tipos por definición, y así además
  -- nadie puede dejarse a sí mismo sin poder emitir nada.
  if v_rol is distinct from 'agente' then
    return new;
  end if;

  -- Array vacío = sin restricción (ver el comentario de la columna).
  if v_tipos is null or cardinality(v_tipos) = 0 then
    return new;
  end if;

  if not (new.tipo = any(v_tipos)) then
    raise exception 'No tienes permiso para emitir contratos de tipo "%". Pídeselo a un administrador en Usuarios.', new.tipo
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- Solo al CREAR. Editar un contrato que ya existe no puede empezar a fallar
-- porque se haya cambiado un permiso después: el documento ya está emitido.
drop trigger if exists trg_contratos_tipo_permitido on public.contratos;
create trigger trg_contratos_tipo_permitido
  before insert on public.contratos
  for each row execute function public.contratos_tipo_permitido();
