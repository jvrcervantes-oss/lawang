-- Cláusulas negociadas REV03: la base estampa también las dos claves derivadas.
--
-- 2-oct-2026, hallazgo del revisor de código sobre 20261002051803: el motor de
-- <!--if--> no evalúa bloques anidados, así que dos frases REV03 van con claves
-- derivadas en vez de con clausulas_negociadas a secas:
--   rev03_dni = REV03 Y comprador persona  («o DNI», dentro del párrafo de persona)
--   rev03_hgb = REV03 Y régimen leasehold  (HGB vía PT PMA; con hgb repetiría su
--               párrafo y con hak_milik contradiría el de SHM)
-- Las calculaba solo el navegador y se guardaban tal cual: un agente podía
-- mandar rev03_dni='si' por la API y el bot (bot-agentes, que lee datos.fields)
-- lo citaba, saltándose el «solo admin». Desde aquí las pone la base en cada
-- guardado a partir de clausulas_negociadas (ya protegido por rol) y de los
-- campos del contrato; lo que mande el navegador se ignora. Sin REV03 las quita
-- (#-), así que el resto de contratos no gana claves nuevas.
--
-- Seguro: solo reemplaza la función del trigger creado hoy; sin DDL destructivo.

create or replace function public.clausulas_negociadas_rol()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rol text;
  v_new text := coalesce(nullif(trim(new.datos->'fields'->>'clausulas_negociadas'), ''), '');
  v_old text := '';
begin
  -- 1. Quién puede cambiarlo: solo admin/super_admin (sin sesión no aplica).
  if (select auth.uid()) is not null then
    if tg_op = 'UPDATE' then
      v_old := coalesce(nullif(trim(old.datos->'fields'->>'clausulas_negociadas'), ''), '');
    end if;
    if v_new is distinct from v_old then
      select u.rol into v_rol from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
      if v_rol is distinct from 'super_admin' and v_rol is distinct from 'admin' then
        raise exception 'Las cláusulas negociadas solo las activan o retiran dirección (admin).'
          using errcode = '42501';
      end if;
    end if;
  end if;

  -- 2. Claves derivadas: las pone la base, nunca el navegador.
  if jsonb_typeof(new.datos->'fields') = 'object' then
    if v_new = 'si' then
      new.datos := jsonb_set(new.datos, '{fields,rev03_dni}',
        to_jsonb(case when new.datos->'fields'->>'adq1_tipo' = 'persona' then 'si' else '' end));
      new.datos := jsonb_set(new.datos, '{fields,rev03_hgb}',
        to_jsonb(case when new.datos->'fields'->>'regimen_tenencia' = 'leasehold' then 'si' else '' end));
    else
      new.datos := new.datos #- '{fields,rev03_dni}' #- '{fields,rev03_hgb}';
    end if;
  end if;
  return new;
end
$function$;

revoke execute on function public.clausulas_negociadas_rol() from public, anon, authenticated;

comment on function public.clausulas_negociadas_rol() is
  'BEFORE INSERT OR UPDATE en contratos: solo super_admin/admin cambian datos.fields.clausulas_negociadas (REV03 negociado con un comprador; sin sesión no aplica) y la base estampa rev03_dni (REV03 y persona) y rev03_hgb (REV03 y leasehold). 2-oct-2026, owner.';
