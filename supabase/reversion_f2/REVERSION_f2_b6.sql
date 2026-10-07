-- Reversion del BLOQUE 6 (Fase 2 empresas, 8-oct-2026): datos compartidos que se separan por empresa.
-- Devuelve las funciones y policies a su texto de antes (cada edicion se deshace con la misma aserción: si el texto vivo ya no es el que dejo la migracion, aborta en vez de pisar nada)
-- y quita lo creado (tabla de disenos por empresa, funciones nuevas, columnas `empresa` de firmantes y apoderados).
-- Valida mientras nadie haya personalizado el diseno de una empresa (si lo hay, la PARTE 1 aborta para no perder esa personalizacion: guardala antes).
-- Orden inverso al de aplicar (5, 4, 3, 2, 1). Con guardas.
-- destructivo-ok: reversion de este mismo encargo; solo quita objetos creados por el (contratos_diseno_empresa, columnas empresa de firmantes/apoderados y funciones nuevas), con guarda si ya hay datos propios
-- REVERTIR: es la reversion
begin;
create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'reversion f2_b6: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;


-- PARTE 5 · ficheros de creatividades
select pg_temp.parchea('privado.creatividad_ve_fichero(text)'::regprocedure,
  $q$and public.creatividad_puede_ver(c.tipo, c.estado)
       and (not public.alcance_restringido() or (c.proyecto_id is not null and public.proyecto_en_alcance(c.proyecto_id)))$q$,
  $q$and public.creatividad_puede_ver(c.tipo, c.estado)$q$);

-- PARTE 4 · documentos, obra, uso de plantillas
select pg_temp.parchea('public.plantillas_uso()'::regprocedure,
  $q$where public.es_super_admin_de(public._empresa_de_contrato_int(ct.id))$q$,
  $q$where public.es_super_admin()$q$);
select pg_temp.parchea('public.agente_ve_proyecto_obra(uuid)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
select pg_temp.parchea('public.obra_datos_cobro(uuid,text,text,text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
select pg_temp.parchea('public.obra_contratos_afectados(uuid,text,text,text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
select pg_temp.parchea('public.obra_confirmar_avance(uuid,text,text,text,integer,text,uuid[])'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
select pg_temp.parchea('public.obra_actualizar(uuid,text,date)'::regprocedure,
  $q$and public._puede_herr_o_super_empresa('obra')$q$,
  $q$and puede('obra')$q$);
select pg_temp.parchea('public.obra_puede(uuid)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('obra')$q$,
  $q$public.puede('obra')$q$);
select pg_temp.parchea('public.documento_proyecto_borra(uuid,uuid,boolean)'::regprocedure,
  $q$if not public._puede_admin_de(public._empresa_de_proyecto_int((select d.proyecto_id from public.documentos_proyecto d where d.id = p_id)), 'documentacion') then$q$,
  $q$if not (public.es_admin() and public.puede('documentacion')) then$q$);
select pg_temp.parchea('public.documento_proyecto_registra(uuid,uuid,text,jsonb)'::regprocedure,
  $q$if v_pub and not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto)) then$q$,
  $q$if v_pub and not public.es_admin() then$q$);
select pg_temp.parchea('public.documento_proyecto_registra(uuid,uuid,text,jsonb)'::regprocedure,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$);
select pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not (v_admin or public.es_admin_de(public._empresa_de_proyecto_int(v_old.proyecto_id)))$q$,
  $q$if p_id is not null and coalesce(v_old.publicado_investor_deck, false) and not v_admin$q$);
select pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not (v_admin or public.es_admin_de(public._empresa_de_proyecto_int(v.proyecto_id))) then$q$,
  $q$if v.publicado_investor_deck is distinct from coalesce(v_old.publicado_investor_deck, false) and not v_admin then$q$);
select pg_temp.parchea('public.documento_proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$);
select pg_temp.parchea('public.documento_proyecto_puede(uuid)'::regprocedure,
  $q$public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('documentacion')$q$,
  $q$public._puede_editar_proyectos() and public.puede('documentacion')$q$);

-- PARTE 3 · creatividades, dossier, lecturas
alter policy "techo_proyectos: leer" on public.modelo_techo_proyectos using (public.es_agente());
alter policy "deck_fotos: leer" on public.deck_fotos using (public.es_agente());
alter policy "deck_forecast_proyecto: leer" on public.deck_forecast_proyecto using (public.es_agente());
alter policy "deck_forecast: leer" on public.deck_forecast using (public.es_agente());
alter policy "deck_faq: leer" on public.deck_faq using (public.es_agente());
alter policy "deck_config_proyecto: leer" on public.deck_config_proyecto using (public.es_agente());
alter policy "creatividades: leer" on public.creatividades using ((select public.creatividad_puede_ver(tipo, estado)));
select pg_temp.parchea('public.dossier_datos(uuid,uuid[])'::regprocedure,
  $q$if not (public._puede_herr_o_super_empresa('dossier') or public._puede_herr_o_super_empresa('creatividades')) then$q$,
  $q$if not (public.puede('dossier') or public.puede('creatividades')) then$q$);
select pg_temp.parchea('public.creatividad_descarga(uuid,text)'::regprocedure,
  $q$if not found or not public.creatividad_puede_ver(c.tipo, c.estado)
     or (public.alcance_restringido() and (c.proyecto_id is null or not public.proyecto_en_alcance(c.proyecto_id))) then$q$,
  $q$if not found or not public.creatividad_puede_ver(c.tipo, c.estado) then$q$);
select pg_temp.parchea('public.creatividad_guarda(uuid,uuid,text,jsonb,text,text,text,uuid[],uuid[])'::regprocedure,
  $q$if public.alcance_restringido() and (v_proy is null or not public.proyecto_en_alcance(v_proy)) then
    raise exception 'Esa creatividad tiene que ser de un proyecto de tus empresas' using errcode = '42501';
  end if;
  v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;$q$,
  $q$v_formato := case when p_datos ? 'formato' then nullif(btrim(coalesce(p_datos->>'formato', '')), '') else v.formato end;$q$);
select pg_temp.parchea('public.creatividad_estado(uuid,text)'::regprocedure,
  $q$v_admin := public.es_admin_de(public._empresa_de_proyecto_int(c.proyecto_id));$q$,
  $q$v_admin := public.es_admin();$q$);
select pg_temp.parchea('public.creatividad_estado(uuid,text)'::regprocedure,
  $q$if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;
  if public.alcance_restringido() and (c.proyecto_id is null or not public.proyecto_en_alcance(c.proyecto_id)) then
    raise exception 'No existe esa creatividad.' using errcode = 'P0002';
  end if;$q$,
  $q$if not found then raise exception 'No existe esa creatividad.' using errcode = 'P0002'; end if;$q$);
select pg_temp.parchea('public.creatividad_puede_hacer(text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('dossier')$q$,
  $q$public.puede('dossier')$q$);
select pg_temp.parchea('public.creatividad_puede_hacer(text)'::regprocedure,
  $q$public._puede_herr_o_super_empresa('creatividades')$q$,
  $q$public.puede('creatividades')$q$);
revoke execute on function public._puede_herr_o_super_empresa(text) from lw_lector;

-- PARTE 2 · deck, fichas, modelos por proyecto
select pg_temp.parchea('public.ficha_publica_guarda(text,jsonb,timestamp with time zone)'::regprocedure,
  $q$if not (public.es_admin() or public._ficha_publica_puerta(p_slug, p_cambios)) then$q$,
  $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.ficha_publica_lee(uuid)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then$q$,
  $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.modelo_precios_guarda(uuid,jsonb)'::regprocedure,
  $q$if not (public.es_admin() or public._modelo_precios_puerta_empresa(p_cambios)) then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Los precios de los modelos los cambia administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.modelos_proyecto_fija(uuid,uuid[])'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Qué modelos se construyen en un proyecto lo decide administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.investor_deck_activa_como(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'solo un admin puede activar/desactivar el investor deck' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_transicion_empieza(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Solo administración abre o cierra un deck' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_prevision_guarda(uuid,uuid,jsonb,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'La previsión del deck la cambia administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_foto_borra(uuid,uuid,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_foto_registra(uuid,text,uuid,text,text)'::regprocedure,
  $q$if not (case when p_ambito = 'proyecto' then public.es_admin_de(public._empresa_de_proyecto_int(p_ref)) else public.es_admin() end) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_foto_mueve(uuid,integer)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_foto_cambia(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_fotos f where f.id = p_id and f.ambito = 'proyecto'))) then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Las fotos del deck las cambia administración' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_faq_guarda(uuid,uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(coalesce((select f.proyecto_id from public.deck_faq f where f.id = p_id), p_proyecto_id))) then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_faq_borra(uuid)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int((select f.proyecto_id from public.deck_faq f where f.id = p_id))) then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Editar las FAQ del deck exige ser administrador' using errcode = '42501'; end if;$q$);
select pg_temp.parchea('public.deck_config_guarda(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public._empresa_de_proyecto_int(p_proyecto_id)) then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;$q$,
  $q$if not public.es_admin() then raise exception 'Solo un administrador puede editar el Investor Deck' using errcode = '42501'; end if;$q$);
drop function public._modelo_precios_puerta_empresa(jsonb);
drop function public._ficha_publica_puerta(text, jsonb);

-- PARTE 1 · diseno por empresa, firmantes y apoderados
do $$ begin
  if exists (select 1 from public.contratos_diseno_empresa c left join public.contratos_diseno d using (slug) where d.slug is null or c.design is distinct from d.design) then
    raise exception 'reversion f2_b6: hay disenos por empresa distintos del comun; guardalos antes de revertir (se perderian)';
  end if;
end $$;
alter policy "apoderados hak sewa: solo con sesion" on public.apoderados_hak_sewa using (public.es_agente());
alter policy "firmantes cred: solo con sesion" on public.firmantes_cred using (public.es_agente());
alter table public.apoderados_hak_sewa drop column empresa;
alter table public.firmantes_cred drop column empresa;
drop function public.contratos_diseno_empresa_guarda(text, text, jsonb);
drop function public.contrato_diseno_empresa_datos(text, text);
drop trigger trg_diseno_a_copias on public.contratos_diseno;
drop function public._trg_diseno_a_copias();
drop table public.contratos_diseno_empresa;
commit;
