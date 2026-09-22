-- ============================================================================
-- BORRAR COMPRADOR / PROYECTO: avisar con palabras, no con un 23503 crudo
-- 22-sep-2026 · saneo de la intranet (misma familia que el bug de hoy)
-- ----------------------------------------------------------------------------
-- borrar_operacion() reventaba esta mañana con un CHECK de facturas que nadie
-- había previsto. Al repasar los otros tres borrados por RPC salió el mismo
-- patrón sin arreglar:
--   · borrar_comprador comprobaba contratos, portal y reservations, pero NO
--     facturas.client_id (FK NO ACTION): un comprador con factura a su nombre
--     revienta con «update or delete on table "clients" violates foreign key
--     constraint» — el usuario ve inglés de Postgres y no sabe qué hacer.
--   · borrar_proyecto comprobaba unidades, modelos y documentos, pero NO
--     contratos.proyecto_id, facturas.proyecto_id, condiciones_comision,
--     obra_partes_trabajo ni obra_progreso_fase_zona (todas NO ACTION).
-- Se añaden los pre-checks con el mismo estilo que los existentes (errcode
-- 23503, mensaje en castellano que dice qué hacer). borrar_unidad ya cubría
-- las dos FKs que le apuntan (contratos.unidad_id, obra_fotos.unidad_id).
--
-- El resto del cuerpo es idéntico al vigente (pg_get_functiondef, 22-sep).
-- ============================================================================

create or replace function public.borrar_comprador(p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre     text;
  v_contratos  text;
  v_facturas   text;
  v_portal     int;
  v_reservas   int;
  v_rutas      text[];
  v_docs       int;
begin
  if not public.es_super_admin() then
    raise exception 'Solo un super admin puede borrar una ficha de comprador' using errcode = '42501';
  end if;

  select c.full_name into v_nombre from public.clients c where c.id = p_client_id;
  if v_nombre is null and not exists (select 1 from public.clients c2 where c2.id = p_client_id) then
    raise exception 'Esa ficha de comprador no existe';
  end if;

  select string_agg(distinct coalesce(ct.numero, 'sin nº'), ', ') into v_contratos
    from public.contrato_compradores cc
    join public.contratos ct on ct.id = cc.contrato_id
   where cc.client_id = p_client_id;
  if v_contratos is not null then
    raise exception 'La ficha de % está vinculada a los contratos % — no se borra una ficha con contratos. Si es el duplicado, desvincúlalo primero desde el contrato; si dudas, es que no es el duplicado.',
      coalesce(v_nombre, 'este comprador'), v_contratos using errcode = '23503';
  end if;

  -- NUEVO (22-sep): facturas.client_id es FK sin ON DELETE. Una factura (o
  -- recibí, o proforma) a nombre de esta ficha bloquea el borrado en Postgres;
  -- aquí se dice con palabras y con los números, para poder ir a buscarlas.
  select string_agg(coalesce(f.numero, 'sin nº'), ', ' order by f.numero) into v_facturas
    from public.facturas f where f.client_id = p_client_id;
  if v_facturas is not null then
    raise exception 'La ficha de % tiene documentos a su nombre (%). Reasígnalos a la ficha buena desde Facturas antes de borrar esta.',
      coalesce(v_nombre, 'este comprador'), v_facturas using errcode = '23503';
  end if;

  select count(*) into v_portal from public.portal_accesos pa where pa.client_id = p_client_id;
  if v_portal > 0 then
    raise exception 'La ficha de % tiene acceso al portal (%). Revócaselo desde la propia ficha y vuelve a intentarlo.',
      coalesce(v_nombre, 'este comprador'), v_portal using errcode = '23503';
  end if;

  select count(*) into v_reservas from public.reservations r where r.client_id = p_client_id;
  if v_reservas > 0 then
    raise exception 'La ficha de % tiene % fila(s) en reservations (esquema antiguo) — se mira a mano antes de borrar.',
      coalesce(v_nombre, 'este comprador'), v_reservas using errcode = '23503';
  end if;

  select array_agg(d.storage_path) filter (where d.storage_path is not null), count(*)
    into v_rutas, v_docs
    from public.documents d where d.client_id = p_client_id;
  -- destructivo-ok: el borrado que pide el owner, detrás del gate de super_admin y de los cinco pre-checks
  delete from public.documents where client_id = p_client_id;
  delete from public.clients   where id = p_client_id;

  return jsonb_build_object(
    'borrado', true,
    'nombre', v_nombre,
    'documentos', coalesce(v_docs, 0),
    'rutas_kyc', coalesce(to_jsonb(v_rutas), '[]'::jsonb),
    'por', (select auth.email())
  );
end;
$$;

create or replace function public.borrar_proyecto(p_nombre text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_unidades int; v_modelos int; v_documentos int; v_resort text;
  v_contratos text; v_facturas text; v_condiciones int; v_obra int;
begin
  if not public.es_super_admin() then
    raise exception 'solo un super_admin puede borrar un proyecto' using errcode = '42501';
  end if;

  select id, resort into v_id, v_resort from public.proyectos where nombre = p_nombre;
  if v_id is null then
    raise exception 'no existe un proyecto con ese nombre' using errcode = '23503';
  end if;

  select count(*) into v_unidades from public.unidades where proyecto = p_nombre or proyecto_id = v_id;
  if v_unidades > 0 then
    raise exception 'el proyecto tiene % unidad(es) dadas de alta — bórralas o muévelas primero', v_unidades using errcode = '23503';
  end if;

  select count(*) into v_modelos from public.modelos_villa where proyecto = p_nombre or proyecto_id = v_id;
  if v_modelos > 0 then
    raise exception 'el proyecto tiene % modelo(s) de villa — bórralos primero', v_modelos using errcode = '23503';
  end if;

  select count(*) into v_documentos from public.documentos_proyecto where proyecto = p_nombre or proyecto_id = v_id;
  if v_documentos > 0 then
    raise exception 'el proyecto tiene % documento(s) subido(s) — bórralos primero', v_documentos using errcode = '23503';
  end if;

  -- NUEVO (22-sep): las FKs sin ON DELETE que apuntan a proyectos. Antes
  -- reventaban con el mensaje inglés de Postgres.
  select string_agg(c.numero, ', ' order by c.numero) into v_contratos
    from public.contratos c where c.proyecto_id = v_id;
  if v_contratos is not null then
    raise exception 'el proyecto tiene contratos (%) — un proyecto con contratos no se borra, se marca como cerrado', v_contratos using errcode = '23503';
  end if;

  select string_agg(coalesce(f.numero, 'sin nº'), ', ' order by f.numero) into v_facturas
    from public.facturas f where f.proyecto_id = v_id;
  if v_facturas is not null then
    raise exception 'el proyecto tiene documentos de facturación (%) — no se borra un proyecto con facturas', v_facturas using errcode = '23503';
  end if;

  select count(*) into v_condiciones from public.condiciones_comision cc where cc.proyecto_id = v_id;
  if v_condiciones > 0 then
    raise exception 'el proyecto tiene % condición(es) de comisión — bórralas desde Comisiones primero', v_condiciones using errcode = '23503';
  end if;

  select (select count(*) from public.obra_partes_trabajo o where o.proyecto_id = v_id)
       + (select count(*) from public.obra_progreso_fase_zona o where o.proyecto_id = v_id)
    into v_obra;
  if v_obra > 0 then
    raise exception 'el proyecto tiene % registro(s) de obra (partes o avance) — no se borra un proyecto con obra', v_obra using errcode = '23503';
  end if;

  -- destructivo-ok: rastro ANTES de borrar (hallazgo Legal, 12-ago) — quién y
  -- cuándo, para poder explicar más adelante por qué un contrato antiguo
  -- nombra un proyecto que ya no está en el catálogo.
  insert into public.proyectos_borrados (nombre, resort, borrado_por)
  values (p_nombre, v_resort, coalesce((select auth.email()), (select auth.uid())::text));

  delete from public.proyectos where id = v_id;
end;
$$;
