-- AXW-66 S4 (28-sep-2026, Desarrollo; encargo encargos/20260928_lawang_deck_fotos_privadas.md, revisión previa #139 SEG4).
-- deck_foto_registra deja de exigir el objeto en `deck` fijo: lo exige en su bucket DEBIDO (deck_bucket_debido,
-- 20260928101000 en Lawang / 20260928140000 en el maestro): modelo o proyecto con deck abierto → `deck`; proyecto
-- cerrado → `deck-privado`. La edge `ficheros` (clase deck_foto) sube al mismo bucket con la misma función: la regla
-- vive UNA vez, en la base. Misma firma, mismos grants (solo service_role), mismo resto del cuerpo.
-- deck_foto_borra no cambia: devuelve la ruta y la edge quita el objeto de los DOS buckets antes de borrar la fila.
-- Gemela byte a byte: supabase/migrations/20260928151500_deck_foto_registra_bucket_debido.sql (Lawang) y
-- erp/migraciones/20260928151500_deck_foto_registra_bucket_debido.sql (maestro).
--
-- ORDEN EN LAWANG (no aplicar antes): front de S4 aterrizado → esta migración → edge `ficheros` desplegada desde la
-- misma copia. Con la edge vieja (sube siempre a `deck`) esta función rechazaría las fotos de proyectos cerrados.

CREATE OR REPLACE FUNCTION public.deck_foto_registra(p_uid uuid, p_ambito text, p_ref uuid, p_path text, p_nombre text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_pie text; v_orden int;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;
  if p_ambito not in ('proyecto', 'modelo') then raise exception 'Ámbito de foto no válido' using errcode = '22023'; end if;
  if p_ambito = 'proyecto' and not exists (select 1 from public.proyectos p where p.id = p_ref) then raise exception 'Ese proyecto no existe' using errcode = '22023'; end if;
  if p_ambito = 'modelo' and not exists (select 1 from public.modelos m where m.id = p_ref) then raise exception 'Ese modelo no existe' using errcode = '22023'; end if;
  if p_path is null or p_path !~ ('^' || p_ambito || '/' || p_ref::text || '/[0-9a-f-]{36}\.webp$') then
    raise exception 'Ruta de foto no válida' using errcode = '22023';
  end if;
  -- AXW-66: el objeto tiene que estar en su bucket DEBIDO exacto en este momento (revisión #139, SEG4): público solo
  -- si es de un modelo o de un proyecto con el deck abierto; si no, en `deck-privado`.
  if not exists (select 1 from storage.objects o
                  where o.bucket_id = public.deck_bucket_debido(p_ambito, p_ref) and o.name = p_path) then
    raise exception 'La foto no ha llegado al archivo: vuelve a subirla' using errcode = '22023';
  end if;
  v_pie := left(btrim(regexp_replace(regexp_replace(regexp_replace(coalesce(p_nombre, ''), '\.[A-Za-z0-9]+$', ''), '[_-]+', ' ', 'g'), '[[:cntrl:]<>]', '', 'g')), 200);
  if v_pie = '' then v_pie := 'Photo'; end if;
  select coalesce(max(f.orden), -1) + 1 into v_orden from public.deck_fotos f
   where (p_ambito = 'proyecto' and f.proyecto_id = p_ref) or (p_ambito = 'modelo' and f.modelo_id = p_ref);
  begin
    insert into public.deck_fotos (ambito, proyecto_id, modelo_id, uso, tipo, path, pie, orden, creado_por)
    values (p_ambito, case when p_ambito = 'proyecto' then p_ref end, case when p_ambito = 'modelo' then p_ref end,
            'galeria', 'foto', p_path, jsonb_build_object('en', v_pie), v_orden, (select auth.email()))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Esa foto ya está registrada' using errcode = '23505';
  end;
  return v_id;
end $function$;
revoke all on function public.deck_foto_registra(uuid, text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.deck_foto_registra(uuid, text, uuid, text, text) to service_role;
