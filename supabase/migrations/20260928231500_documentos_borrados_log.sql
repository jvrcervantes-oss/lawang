-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
--
-- Traza de cada documento borrado de la documentación (consulta de Seguridad, 28-sep-2026: al pasar el borrado de
-- 1 super admin a los admins con Documentación, «la ampliación no debe quedarse sin traza»). Una copia de la ficha
-- (enlace incluido, así un enlace borrado por error se puede recuperar; de un fichero queda la ruta, el bucket no
-- tiene versionado) + quién y cuándo. En la misma transacción que el delete: si no se registra, no se borra.
-- No es proyecto_eventos porque aquel exige proyecto_id y los documentos generales de la empresa no lo tienen.
-- Nace cerrada: RLS sin policies y sin grants a anon/authenticated; solo la escribe la función (definer).

create table if not exists public.documentos_proyecto_borrados_log (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null,
  ficha jsonb not null,
  quien_uid uuid,
  quien text,
  borrado_en timestamptz not null default now()
);
alter table public.documentos_proyecto_borrados_log enable row level security;
revoke all on table public.documentos_proyecto_borrados_log from anon, authenticated;
comment on table public.documentos_proyecto_borrados_log is
  'Copia de cada documento/enlace borrado de documentos_proyecto y quién lo borró. La escribe documento_proyecto_borra. Sin acceso desde el navegador.';

-- destructivo-ok: el DELETE es el cuerpo ya existente de la función (borra UNA fila cuando la llama la edge); aplicar esto no borra nada
create or replace function public.documento_proyecto_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false)
returns text
language plpgsql security definer set search_path = '' as $$
declare v_d public.documentos_proyecto%rowtype;
begin
  perform public._actua_como(p_uid);
  if not (public.es_admin() and public.puede('documentacion')) then
    raise exception 'Borrar documentación lo hace administración con la herramienta «Documentación»' using errcode = '42501';
  end if;
  select * into v_d from public.documentos_proyecto d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
  if not (v_d.general or public.puede_proyecto(v_d.proyecto, v_d.proyecto_id)) then
    raise exception 'Ese documento no es de tus proyectos' using errcode = '42501';
  end if;
  if not coalesce(p_solo_comprobar, false) then
    insert into public.documentos_proyecto_borrados_log (documento_id, ficha, quien_uid, quien)
    values (v_d.id, to_jsonb(v_d), p_uid, (select u.email from public.usuarios u where u.user_id = p_uid));
    delete from public.documentos_proyecto where id = p_id;
  end if;
  return v_d.path;
end $$;
