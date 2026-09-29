-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); pareja IDÉNTICA de erp/migraciones/20260929100000
-- LAW-428 fase 1 — el nombre de un proyecto tiene UN dueño que lo propaga, y su slug es fijo (29-sep-2026).
-- Pareja: erp/migraciones/20260929100000_proyecto_nombre_un_dueno_slug_fijo.sql (agencia). Cuerpos IDÉNTICOS.
-- Norma del owner (29-sep): «cambiar lo que se ve no rompe lo que funciona» — contexto/patrones_tecnicos.md →
-- «Enganche por identificador estable». Revisión previa #152 (Datos, Seguridad, Desarrollo).
--
-- 1) Renombrar un proyecto lo propagaban DOS triggers (propaga_nombre_proyecto y trg_proyecto_renombrado, los dos
--    reescribían unidades) y NINGUNO tocaba modelos_villa.proyecto: tras un renombrado la ficha del proyecto, que
--    busca sus modelos por ese texto, salía sin modelos y sin un error. Queda un solo dueño, que cubre también
--    modelos_villa y documentos_proyecto (el viejo se borra en 20260929235900 del maestro (LAW-432), con el OK del owner). `unidades_borradas.proyecto` es un CONGELADO histórico (cómo se llamaba el
--    proyecto cuando se borró la unidad): no se propaga a propósito.
-- 2) El slug es el identificador PÚBLICO del proyecto (URL del Investor Deck): se genera al dar de alta si no llega,
--    es obligatorio, tiene formato, y una vez puesto NO se cambia — con error, no en silencio, para que un admin no
--    crea que lo ha cambiado. Antes solo lo frenaba un aviso de texto en la pantalla, y 2 de 29 proyectos no tenían.

-- ── 1. Un solo dueño de la propagación del nombre ─────────────────────────────────────────────────────────────
create or replace function public.trg_proyecto_renombrado()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if new.nombre is not distinct from old.nombre then return new; end if;

  -- Espejos de texto del nombre (se leen por comodidad; la relación es proyecto_id). Único sitio que los escribe.
  update public.unidades            set proyecto = new.nombre where proyecto_id = new.id;
  update public.modelos_villa       set proyecto = new.nombre where proyecto_id = new.id;
  update public.documentos_proyecto set proyecto = new.nombre where proyecto_id = new.id;
  update public.contratos           set proyecto_nombre = new.nombre where proyecto_id = new.id;
  update public.facturas
     set proyecto_nombre = replace(proyecto_nombre, old.nombre, new.nombre)
   where proyecto_id = new.id and proyecto_nombre like old.nombre || '%';

  update public.contratos c
     set datos = jsonb_set(c.datos, '{fields,proyecto_nombre}', to_jsonb(new.nombre))
   where c.proyecto_id = new.id
     and not coalesce(c.bloqueado, false)
     and c.datos #>> '{fields,proyecto_nombre}' = old.nombre
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas f
     set datos = jsonb_set(f.datos, '{fields,proyecto_nombre}',
                           to_jsonb(replace(f.datos #>> '{fields,proyecto_nombre}', old.nombre, new.nombre)))
   where f.proyecto_id = new.id
     and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)
     and f.datos #>> '{fields,proyecto_nombre}' like old.nombre || '%';

  return new;
end $function$;

-- El trigger viejo (proyectos_propaga_nombre → propaga_nombre_proyecto) se BORRA en 20260929235900 del maestro (LAW-432), aparte: el
-- abanico lo trata como destructivo y espera el OK del owner. Hasta entonces los dos corren; el viejo solo repite
-- sobre unidades y documentos_proyecto lo mismo que escribe este, así que no hay nada que se contradiga.

-- ── 2. Slug: se genera, es obligatorio y no cambia ────────────────────────────────────────────────────────────
create or replace function public.proyecto_slug_de(p_nombre text, p_id uuid)
 returns text
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  v_base text; v_slug text; n int := 1;
begin
  v_base := translate(lower(coalesce(p_nombre, '')), 'áàäâãéèëêíìïîóòöôõúùüûñç', 'aaaaaeeeeiiiiooooouuuunc');
  v_base := btrim(left(btrim(regexp_replace(v_base, '[^a-z0-9]+', '-', 'g'), '-'), 55), '-');
  if length(v_base) < 3 then v_base := 'proyecto'; end if;
  v_slug := v_base;
  while exists (select 1 from public.proyectos p where p.slug = v_slug and p.id is distinct from p_id) loop
    n := n + 1;
    v_slug := v_base || '-' || n;
  end loop;
  return v_slug;
end $function$;
revoke all on function public.proyecto_slug_de(text, uuid) from public, anon, authenticated;

create or replace function public.trg_proyecto_slug()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.slug is null or btrim(new.slug) = '' then
      new.slug := public.proyecto_slug_de(new.nombre, new.id);
    end if;
  elsif old.slug is not null and btrim(old.slug) <> '' and new.slug is distinct from old.slug then
    raise exception 'El slug de un proyecto no se cambia: es su dirección pública (/investor-deck/%/) y rompería los enlaces ya compartidos', old.slug
      using errcode = '22023';
  end if;
  return new;
end $function$;
revoke all on function public.trg_proyecto_slug() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_proyecto_slug' and tgrelid = 'public.proyectos'::regclass) then
    create trigger trg_proyecto_slug
      before insert or update of slug on public.proyectos
      for each row execute function public.trg_proyecto_slug();
  end if;
end $$;

-- Los que no tienen (2 en Lawang el 29-sep): se generan del nombre. old.slug es null → el candado los deja pasar.
update public.proyectos set slug = public.proyecto_slug_de(nombre, id) where slug is null or btrim(slug) = '';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'proyectos_slug_formato' and conrelid = 'public.proyectos'::regclass) then
    alter table public.proyectos add constraint proyectos_slug_formato check (slug ~ '^[a-z0-9-]{3,60}$');
  end if;
end $$;
alter table public.proyectos alter column slug set not null;
