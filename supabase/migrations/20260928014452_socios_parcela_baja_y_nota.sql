-- Socios por parcela, dos arreglos del revisor de código (28-sep-2026, sobre 20260928013142):
--  1. socios_parcelas devolvía solo socios activos pero TODAS las asignaciones: una parcela de un socio dado de baja
--     se pintaba «Sin socio» y, al guardar la ficha por otra cosa, el desplegable (sin esa opción) mandaba '' y se
--     borraba la asignación. Ahora devuelve también los socios de baja que tengan parcelas en el proyecto, con `activo`,
--     y la pantalla los enseña como «de baja» (y no los ofrece para asignar parcelas nuevas: la RPC de asignar sigue
--     exigiendo socio activo).
--  2. Cambiar el socio desde la ficha (p_nota null) pisaba la nota anterior sin rastro: el log guarda ahora `nota_antes`.
-- Pendiente conocido (BAJA): no hay enlace proyecto→sociedad, así que la lista ofrece los socios de cualquier sociedad.
-- Hoy solo una tiene socios; el día que haya dos, se añade ese enlace y el filtro aquí.
-- erp-ok: dato interno propio de Lawang, misma pieza que socios_parcela
-- destructivo-ok: el único DELETE vive DENTRO de unidad_socio_asigna (quitar el socio de una parcela, queda en el log); esta migración no borra filas
-- create or replace conserva dueño (postgres) y grants de las dos RPC.

alter table public.unidad_socio_log add column nota_antes text;

create or replace function public.socios_parcelas(p_proyecto_id uuid)
  returns jsonb
  language plpgsql stable security definer set search_path to ''
  as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then raise exception 'Solo un administrador ve los socios' using errcode = '42501'; end if;
  return jsonb_build_object(
    'socios', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'numero', s.numero, 'nombre', s.nombre,
                                                            'tipo', s.tipo, 'sociedad', s.sociedad, 'activo', s.activo)
                                         order by s.nombre)
                          from public.socios s
                         where s.activo
                            or exists (select 1 from public.unidad_socio us join public.unidades u on u.id = us.unidad_id
                                        where us.socio_id = s.id and u.proyecto_id = p_proyecto_id)), '[]'::jsonb),
    'asignaciones', coalesce((select jsonb_agg(jsonb_build_object('unidad_id', us.unidad_id, 'socio_id', us.socio_id,
                                                                  'nota', us.nota))
                                from public.unidad_socio us
                                join public.unidades u on u.id = us.unidad_id
                               where u.proyecto_id = p_proyecto_id), '[]'::jsonb));
end $$;

create or replace function public.unidad_socio_asigna(p_unidad uuid, p_socio uuid, p_nota text default null)
  returns void
  language plpgsql volatile security definer set search_path to ''
  as $$
declare
  v_cod text; v_antes public.unidad_socio%rowtype; v_nom_antes text; v_nom_despues text;
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
  v_por text := (select auth.email());
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then raise exception 'Solo un administrador asigna socios' using errcode = '42501'; end if;
  if length(v_nota) > 500 then raise exception 'La nota no puede pasar de 500 caracteres' using errcode = '22023'; end if;

  select u.codigo into v_cod from public.unidades u where u.id = p_unidad for update;
  if not found then raise exception 'No encuentro esa parcela' using errcode = '22023'; end if;
  if p_socio is not null then
    select s.nombre into v_nom_despues from public.socios s where s.id = p_socio and s.activo;
    if not found then raise exception 'Ese socio no existe o está dado de baja' using errcode = '22023'; end if;
  end if;

  select * into v_antes from public.unidad_socio us where us.unidad_id = p_unidad;
  if found then select s.nombre into v_nom_antes from public.socios s where s.id = v_antes.socio_id; end if;
  if v_antes.socio_id is not distinct from p_socio and v_antes.nota is not distinct from v_nota then return; end if;

  if p_socio is null then
    delete from public.unidad_socio where unidad_id = p_unidad;
  else
    insert into public.unidad_socio (unidad_id, socio_id, nota, asignado_por)
    values (p_unidad, p_socio, v_nota, v_por)
    on conflict (unidad_id) do update
      set socio_id = excluded.socio_id, nota = excluded.nota, asignado_en = now(), asignado_por = excluded.asignado_por;
  end if;

  insert into public.unidad_socio_log (unidad_id, unidad_codigo, socio_antes, socio_antes_nombre,
                                       socio_despues, socio_despues_nombre, nota_antes, nota, por)
  values (p_unidad, v_cod, v_antes.socio_id, v_nom_antes, p_socio, v_nom_despues, v_antes.nota, v_nota, v_por);
end $$;
