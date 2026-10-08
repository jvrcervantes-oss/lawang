-- Reversion de 20261010050000 (arreglos de la revision de codigo E7-E9): vuelve a las definiciones de 20261010000000 / 010000 / 020000. Sin filas que tocar.
-- OJO: deshacer el punto 1 reabre la laguna (fijar una revision de otra empresa). Solo para un rollback urgente.
-- destructivo-ok: reemplaza funciones por su version anterior; no toca filas
begin;
create or replace function public.plantilla_contrato_fija(p_contrato uuid, p_version uuid default null) returns void language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_tipo text; v_proy uuid; v_emp text; v_slug text; v_vid uuid; v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public._puede_herr_o_super_empresa('contratos') and public.puede_ver_contrato(p_contrato)) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  select c.tipo, c.proyecto_id into v_tipo, v_proy from public.contratos c where c.id = p_contrato;
  v_slug := case when v_tipo is null then null else public._plantilla_slug_de_tipo(v_tipo) end;
  v_vid := p_version;
  if v_vid is null then
    -- sin elegir: vale solo si no hay revisiones activas aparte de la estandar (el comportamiento de siempre); si las hay, hay que elegir
    v_emp := case when v_proy is null then null else public.empresa_de_proyecto(v_proy) end;
    if v_emp is null or v_slug is null then raise exception 'El contrato no tiene empresa o plantilla' using errcode = '22023'; end if;
    if exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = v_emp and a.slug = v_slug and a.estado = 'activa' and a.variante <> 'estandar' and a.borrada_en is null) then
      raise exception 'Esta plantilla tiene varias revisiones activas: elige cual usa el contrato' using errcode = '22023';
    end if;
    select x.id into v_vid from public.plantilla_contrato_versiones x
     where x.empresa = v_emp and x.slug = v_slug and x.borrada_en is null and ((x.estado = 'activa' and x.variante = 'estandar') or (x.origen = 'semilla' and x.version = 1))
     order by (x.estado = 'activa') desc limit 1;
  end if;
  -- FOR SHARE: se serializa con archivar/borrar la misma revision (que toman FOR UPDATE) y se vuelve a leer su estado
  select * into v from public.plantilla_contrato_versiones x where x.id = v_vid for share;
  if not found then raise exception 'Version no valida' using errcode = '22023'; end if;
  if v.borrada_en is not null then raise exception 'Esa revision se ha borrado' using errcode = '22023'; end if;
  if v_tipo is null or v_slug is distinct from v.slug then
    raise exception 'Esa version es de otra plantilla que la del contrato' using errcode = '22023';
  end if;
  if not (v.estado = 'activa'
          or (v.origen = 'semilla' and v.version = 1
              and not exists (select 1 from public.plantilla_contrato_versiones a where a.empresa = v.empresa and a.slug = v.slug and a.variante = 'estandar' and a.estado = 'activa' and a.borrada_en is null))) then
    raise exception 'Solo se fija una revision activa de la empresa (o, mientras la estandar no tenga ninguna, su semilla v1)' using errcode = '22023';
  end if;
  insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (p_contrato, v.id, v_autor)
  on conflict (contrato_id) do update set version_id = excluded.version_id, fijado_en = now(), fijado_por = excluded.fijado_por;
end $$;

create or replace function public._trg_contrato_campos_propios() returns trigger language plpgsql security definer set search_path = '' as $$
declare f jsonb := new.datos -> 'fields'; of_ jsonb; k text; v jsonb; c public.plantilla_campos_propios%rowtype; r jsonb; emp text; sale jsonb := null;
begin
  if f is null or jsonb_typeof(f) <> 'object' then return new; end if;
  if not exists (select 1 from jsonb_object_keys(f) kk where kk like 'cx\_%') then return new; end if;     -- camino rapido: todos los contratos de hoy
  if tg_op = 'UPDATE' then of_ := old.datos -> 'fields'; end if;
  emp := case when new.proyecto_id is null then null else public.empresa_de_proyecto(new.proyecto_id) end;
  for k in select kk from jsonb_object_keys(f) kk where kk like 'cx\_%' loop
    v := f -> k;
    if of_ is not null and jsonb_typeof(of_) = 'object' and (of_ -> k) is not distinct from v then continue; end if;      -- sin cambio: un valor viejo nunca bloquea otro guardado
    if v is null or jsonb_typeof(v) = 'null' or v = '""'::jsonb then continue; end if;                                       -- vaciar siempre se puede
    if k !~ '^cx_[a-z0-9_]{1,40}$' then raise exception 'Campo propio con forma no permitida: %', left(k, 60) using errcode = '22023'; end if;
    if emp is null then raise exception 'Este contrato no tiene empresa: no admite campos propios (%)', k using errcode = '22023'; end if;
    select * into c from public.plantilla_campos_propios x where x.empresa = emp and x.clave = k;
    if not found then raise exception 'El campo % no esta en el catalogo de campos de esta empresa', k using errcode = '22023'; end if;
    if c.archivado then raise exception 'El campo % esta archivado: ya no admite valores nuevos', k using errcode = '22023'; end if;
    r := public._cx_valor(c.tipo, c.opciones, v);
    if not (r ->> 'ok')::boolean then raise exception 'Valor no valido en %: %', k, r ->> 'err' using errcode = '22023'; end if;
    if to_jsonb(r ->> 'v') is distinct from v then sale := jsonb_set(coalesce(sale, new.datos), array['fields', k], to_jsonb(r ->> 'v')); end if;   -- forma canonica
  end loop;
  if sale is not null then new.datos := sale; end if;
  return new;
end $$;

create or replace function public._plantilla_base_edicion(p_empresa text, p_slug text, p_variante text) returns text language sql stable security definer set search_path = '' as $$
  select c.cuerpo_html
    from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = p_empresa and v.slug = p_slug and v.variante = coalesce(p_variante, 'estandar') and v.borrada_en is null
   order by (v.estado = 'borrador' and v.origen = 'empresa') desc, (v.estado = 'activa') desc, v.version desc
   limit 1
$$;

alter function public._plantilla_texto(text, boolean) stable;
alter function public._plantilla_analiza(text, boolean) stable;
alter function public._plantilla_valida(text, text, boolean) stable;
alter function public.plantilla_cuerpo_valida(text, text) stable;
alter function public.plantilla_cuerpo_valida_semilla(text, text) stable;
alter function public._plantilla_exige_bloques(text, text, text, text) stable;
alter function public.plantilla_contrato_revisa(text, text, text, text) stable;
commit;
