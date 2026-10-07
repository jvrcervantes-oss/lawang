-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 6 · migracion 2 (8-oct-2026): lo que cuelga de UN PROYECTO se abre al administrador de la empresa de ese proyecto.
--   Mismo criterio que los bloques 1-4: la empresa sale SIEMPRE del proyecto en el servidor (nunca de un parametro del navegador). Un admin_empresa hace en SU empresa lo que un admin global; sin empresa (Karana, ficha sin proyecto,
--   foto de MODELO) solo pasa un admin/super global. Los 34 usuarios de hoy no cambian (es_admin_de(x) = es_admin() para ellos).
--   Convertidas: deck_config_guarda, deck_faq_guarda/borra, deck_foto_cambia/mueve/registra/borra (solo las de ambito 'proyecto'), deck_prevision_guarda, deck_transicion_empieza, investor_deck_activa_como,
--   modelos_proyecto_fija, ficha_publica_lee/guarda (una ficha NUEVA y la que no tiene proyecto siguen siendo de un global) y modelo_precios_guarda SOLO en sus ramas por proyecto (villas/altas).
--   NO se convierten (catalogo compartido por las dos empresas: Dali, Dream, Temple, Trinity y Tropical tienen unidades en ambas; duplicarlos obliga a reapuntar unidades.modelo_id): modelo_guarda, modelo_documento*,
--   modelo_extras_guarda, extra_*, extras_catalogo_guarda, modelo_techo*, el precio BASE del modelo, deck_foto_fijar_vista (foto de modelo) y tipo_vivienda_alta. Quedan en un global hasta que el owner decida (PREGUNTA del informe).
--   Ojo: la edge `ficheros` mira `es_admin` antes de subir/borrar fotos del deck, documentos de modelo y abrir/cerrar un deck; mientras no se cambie, esas tres acciones siguen siendo de un global aunque la base ya acepte al admin de empresa.
--   Funciones nuevas con llamador con nombre: _ficha_publica_puerta (ficha_publica_guarda), _modelo_precios_puerta_empresa (modelo_precios_guarda). Sin EXECUTE para nadie.
-- destructivo-ok: create or replace de funciones; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b6.sql (PARTE 2)

create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'parche f2_b6: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;

-- 0. ayudas ------------------------------------------------------------------------------------------------
-- ¿puede este admin tocar esta ficha publica? Solo una ficha que YA existe, con proyecto de una empresa suya, y sin llevarla a un proyecto/unidad de otra.
create function public._ficha_publica_puerta(p_slug text, p_cambios jsonb)
 returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_pid uuid; v_nuevo uuid; v_uni uuid;
begin
  select f.proyecto_id into v_pid from public.fichas_publicas f where f.slug = lower(btrim(coalesce(p_slug, '')));
  if v_pid is null or not public.es_admin_de(public._empresa_de_proyecto_int(v_pid)) then return false; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then return false; end if;
  if p_cambios ? 'proyecto_id' then
    v_nuevo := nullif(p_cambios->>'proyecto_id', '')::uuid;
    if v_nuevo is null or not public.es_admin_de(public._empresa_de_proyecto_int(v_nuevo)) then return false; end if;
  end if;
  if p_cambios ? 'unidad_id' then
    v_uni := nullif(p_cambios->>'unidad_id', '')::uuid;
    if v_uni is not null and not public.es_admin_de(public.empresa_de_unidad(v_uni)) then return false; end if;
  end if;
  return true;
exception when others then return false;
end $$;
revoke all on function public._ficha_publica_puerta(text, jsonb) from public, anon, authenticated, lw_lector, service_role;

-- ¿cambia este admin SOLO precios por proyecto, todos de proyectos de una empresa suya? (modelo_precios_guarda: ramas villas/altas)
create function public._modelo_precios_puerta_empresa(p_cambios jsonb)
 returns boolean language plpgsql stable security definer set search_path = '' as $$
declare e jsonb; v_emp text; n int := 0;
begin
  if jsonb_typeof(p_cambios) is distinct from 'object' then return false; end if;
  if exists (select 1 from jsonb_object_keys(p_cambios) k where k not in ('villas', 'altas')) then return false; end if;
  if jsonb_typeof(p_cambios->'villas') = 'array' then
    for e in select * from jsonb_array_elements(p_cambios->'villas') loop
      select pr.empresa into v_emp from public.modelos_villa v join public.proyectos pr on pr.id = v.proyecto_id where v.id = (e->>'id')::uuid;
      if v_emp is null or not public.es_admin_de(v_emp) then return false; end if;
      n := n + 1;
    end loop;
  end if;
  if jsonb_typeof(p_cambios->'altas') = 'array' then
    for e in select * from jsonb_array_elements(p_cambios->'altas') loop
      select pr.empresa into v_emp from public.proyectos pr where pr.id = (e->>'proyecto_id')::uuid;
      if v_emp is null or not public.es_admin_de(v_emp) then return false; end if;
      n := n + 1;
    end loop;
  end if;
  return n > 0;
exception when others then return false;
end $$;
revoke all on function public._modelo_precios_puerta_empresa(jsonb) from public, anon, authenticated, lw_lector, service_role;

-- 1. Deck: configuracion, preguntas, fotos de proyecto, prevision, abrir/cerrar ------------------------------------
select pg_temp.parchea('public.deck_config_guarda(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_faq_borra(uuid)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_faq f where f.id = p_id))) then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_faq_guarda(uuid,uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(coalesce((select f.proyecto_id from public.deck_faq f where f.id = p_id), p_proyecto_id))) then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_foto_cambia(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_foto_mueve(uuid,integer)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_foto_registra(uuid,text,uuid,text,text)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not (case when p_ambito = 'proyecto' then public.es_admin_de(public._empresa_de_proyecto_int(p_ref)) else public.es_admin() end) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_foto_borra(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_prevision_guarda(uuid,uuid,jsonb,jsonb)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.deck_transicion_empieza(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;$q$);

select pg_temp.parchea('public.investor_deck_activa_como(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;$q$);

-- 2. Que modelos se construyen en un proyecto ------------------------------------------------------------------
select pg_temp.parchea('public.modelos_proyecto_fija(uuid,uuid[])'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;$q$);

-- 3. Precio de un modelo POR PROYECTO (el precio base sigue siendo de un global) -----------------------------------
select pg_temp.parchea('public.modelo_precios_guarda(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin() then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not (public.es_admin() or public._modelo_precios_puerta_empresa(p_cambios)) then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;$q$);

-- 4. Ficha publica -----------------------------------------------------------------------------------------------
select pg_temp.parchea('public.ficha_publica_lee(uuid)'::regprocedure,
  $q$if not public.es_admin() then$q$,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then$q$);

select pg_temp.parchea('public.ficha_publica_guarda(text,jsonb,timestamp with time zone)'::regprocedure,
  $q$if not public.es_admin() then$q$,
  $q$if not (public.es_admin() or public._ficha_publica_puerta(p_slug, p_cambios)) then$q$);
