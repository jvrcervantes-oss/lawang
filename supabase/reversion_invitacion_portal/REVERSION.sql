-- destructivo-ok: REVERSION de 20261015101500_invitacion_portal_parcela.sql («Invitar al portal», 15-oct-2026). Borra SOLO lo que esa
-- migracion creo (filas de cola y del libro de tipo invitacion_portal, la plantilla invitacion_portal, la columna tipo y su FK compuesta, los
-- indices nuevos, las funciones nuevas) y restaura las definiciones anteriores de 9 funciones COPIADAS LITERALMENTE de sus migraciones
-- (20261010070000 y 20260908013953), que el 15-oct-2026 coincidian con produccion (pg_get_functiondef, md5 abajo). Los correos YA enviados
-- quedan en correos_enviados: se reetiquetan a 'manual' antes de estrechar el CHECK, no se borran.
-- ANTES DE APLICAR: comprobar que la viva sigue con las definiciones de 20261015101500 (si otra migracion las toco despues, esta reversion
-- las pisaria). md5(pg_get_functiondef) en produccion el 15-oct-2026, ANTES de aplicar 20261015101500:
--   _correo_cola_regla 129f9cbd1e372ac082d9a6d29e1cbe46 · _reclamo_pago_candidatos d6102130b500c796870033251f6cb0a2
--   _reclamo_pago_vigente 451c462b80e8558582d7cdcf480d45cc · portal_autoservicio feebfff511b8df06d12f00c440ba0ba6
--   reclamo_pago_datos dc4d0950b3b2192f46fd909bcf3f7992 · reclamo_pago_destinatarios 35554096720304368d204f85d9859c7a
--   reclamo_pago_encolar b843918da7fa46ab6b94c69a531e0778 · reclamo_pago_historial 52a877d1aa33d8c8487caa12763523c7
--   reclamo_pago_prueba c67cb6eb8e2bb81208baf411ecdf9e8f
-- Aplicar solo con el OK del owner. El trigger de sellado de correo_plantillas impide borrar la fila: se desactiva un instante.

-- 1. filas que dependen de lo nuevo
delete from public.correos_cola where clave = 'invitacion_portal';
delete from public.reclamos_pago where tipo = 'invitacion_portal';
update public.correos_enviados set via = 'manual', plantilla = null, plantilla_version = null
 where via = 'invitacion_portal' or plantilla = 'invitacion_portal';

-- 2. funciones como estaban (create or replace conserva sus permisos; portal_autoservicio los repite abajo)
create or replace function public._correo_cola_regla(p_clave text)
returns table (ancla text, soportada boolean, tope_horas int, prioridad smallint, max_intentos int,
               via text, asunto_registro text, editables text[])
language sql immutable set search_path = '' as $$
  select r.ancla, r.soportada, r.tope_horas, r.prioridad, r.max_intentos, r.via, r.asunto_registro, r.editables
    from (values
      ('enlace_firma_cadena',     'firma_id',    true,   24, 1::smallint, 10, 'enlace_firma',   'Documento para firmar',        array[]::text[]),
      ('aviso_anulacion',         'firma_id',    true,   72, 5::smallint, 10, 'aviso_anulacion','Actualización del documento',  array[]::text[]),
      ('copia_firmada_comprador', 'contrato_id', false, 720, 5::smallint, 10, 'copia_firmada',  'Contrato firmado',             array['nombre']),
      ('copia_firmada_portal',    'contrato_id', false, 720, 5::smallint, 10, 'copia_firmada',  'Contrato firmado',             array['nombre']),
      ('copia_firmada_manual',    'contrato_id', false, 720, 5::smallint, 10, 'copia_firmada',  'Contrato firmado',             array['nombre']),
      ('factura_primer_hito',     'factura_id',  false, 720, 5::smallint, 10, 'factura',        'Factura',                      array['nombre']),
      ('proforma_total',          'factura_id',  false, 720, 5::smallint, 10, 'proforma',       'Factura proforma',             array['nombre']),
      ('factura_vencimiento',     'factura_id',  false, 720, 5::smallint, 10, 'factura_auto',   'Factura',                      array['nombre']),
      ('reclamo_pago',            'reclamo_id',  false,  24, 7::smallint,  3, 'reclamo_pago',   'Recordatorio de pago',         array[]::text[])
    ) as r(clave, ancla, soportada, tope_horas, prioridad, max_intentos, via, asunto_registro, editables)
   where r.clave = p_clave
$$;

create or replace function public._reclamo_pago_candidatos(p_unidad uuid)
returns table (contrato_id uuid, client_id uuid, nombre text, email text, idioma text, seleccionable boolean, motivo text,
               empresa_nombre text, sociedad_clave text, sociedad_razon text, parcela text, proyecto text, orden int)
language sql stable security definer set search_path = '' as $$
  with b as (
    select c.id as cid, c.adq1_client_id as cl, c.fecha_firma as ffirma, c.created_at as ccreado,
           nullif(btrim(c.datos_fields->>'sociedad_firmante'), '') as soc_c,
           k.full_name as k_nombre, lower(btrim(k.email)) as k_email, k.idioma_comunicacion as k_idioma,
           e.nombre as e_nombre, e.sociedad_clave as soc_p, u.codigo as u_codigo, p.nombre as p_nombre
      from public.unidades u
      join public.proyectos p on p.id = u.proyecto_id
      left join public.empresas e on e.clave = p.empresa
      join public.contratos c on c.liberado_en is null and c.proyecto_id = u.proyecto_id
                             and (c.unidad_id = u.id or c.id = u.contrato_id)
      left join public.clients k on k.id = c.adq1_client_id
     where u.id = p_unidad),
  m as (
    select b.*, s.razon as s_razon,
           case when b.cl is null or b.k_nombre is null then 'sin_ficha'
                when b.k_email is null or b.k_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or char_length(b.k_email) > 254 then 'sin_email'
                when b.ffirma is null then 'sin_firmar'
                when b.soc_c is null then 'sociedad_nula'
                when b.soc_p is null or b.soc_c <> b.soc_p then 'sociedad_discordante'
           end as motivo_
      from b left join public.sociedades s on s.clave = b.soc_c)
  select m.cid, m.cl, m.k_nombre, m.k_email, m.k_idioma, (m.motivo_ is null), m.motivo_, m.e_nombre, m.soc_c, m.s_razon, m.u_codigo, m.p_nombre,
         (row_number() over (partition by coalesce(m.cl, m.cid)
                             order by (m.motivo_ is null) desc, m.ffirma desc nulls last, m.ccreado desc, m.cid))::int
    from m
$$;

create or replace function public._reclamo_pago_vigente(p_reclamo uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.reclamos_pago r
      join public.unidades u on u.id = r.unidad_id
      join public.proyectos p on p.id = u.proyecto_id
      join public.empresas e on e.clave = p.empresa
      join public.contratos c on c.id = r.contrato_id and c.liberado_en is null and c.proyecto_id = u.proyecto_id
                             and (c.unidad_id = u.id or c.id = u.contrato_id)
                             and c.adq1_client_id = r.client_id and c.fecha_firma is not null
     where r.id = p_reclamo and e.sociedad_clave is not null
       and nullif(btrim(c.datos_fields->>'sociedad_firmante'), '') = e.sociedad_clave)
$$;

create or replace function public.reclamo_pago_datos(p_cola uuid)
returns table (reclamo_id uuid, para text, nombre text, idioma text, parcela text, proyecto text,
               empresa_razon text, sociedad_clave text, nota text, contrato_id uuid)
language sql stable security definer set search_path = '' as $$
  select r.id, public._reclamo_pago_destino(r.id), k.full_name, k.idioma_comunicacion, u.codigo, p.nombre,
         s.razon, s.clave, r.nota, r.contrato_id
    from public.correos_cola q
    join public.reclamos_pago r on r.id = q.reclamo_id
    join public.clients k on k.id = r.client_id
    join public.unidades u on u.id = r.unidad_id
    join public.proyectos p on p.id = u.proyecto_id
    join public.contratos c on c.id = r.contrato_id
    left join public.sociedades s on s.clave = nullif(btrim(c.datos_fields->>'sociedad_firmante'), '')
   where q.id = p_cola and q.clave = 'reclamo_pago'
$$;

create or replace function public.reclamo_pago_destinatarios(p_unidad uuid)
returns table (contrato_id uuid, client_id uuid, nombre text, email_oculto text, idioma text, seleccionable boolean, motivo text,
               empresa text, sociedad text, parcela text, proyecto text,
               ultimo_reclamo_en timestamptz, ultimo_estado text, ultimo_enviado_en timestamptz, contrato_numero text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_emp text;
  v_hay boolean;
begin
  select p.empresa into v_emp
    from public.unidades u join public.proyectos p on p.id = u.proyecto_id where u.id = p_unidad;
  v_hay := found;
  if not public.es_admin_de(v_emp) then
    raise exception 'No tienes permiso sobre esta parcela.' using errcode = '42501', hint = 'sin_permiso';
  end if;
  if not v_hay then
    raise exception 'La parcela no existe.' using errcode = '22023', hint = 'unidad_no_existe';
  end if;
  return query
  select c.contrato_id, c.client_id, c.nombre,
         regexp_replace(c.email, '^(.).*(@.*)$', '\1***\2'),
         c.idioma, c.seleccionable, c.motivo, c.empresa_nombre, c.sociedad_razon, c.parcela, c.proyecto,
         (select r.creado_en from public.reclamos_pago r
           where r.unidad_id = p_unidad and r.client_id = c.client_id and not r.prueba order by r.creado_en desc limit 1),
         (select case when q.id is null then 'archivado'
                      when q.estado in ('pendiente', 'enviando') then 'pendiente'
                      when q.estado = 'ok' then 'enviado' else q.estado end
            from public.reclamos_pago r left join public.correos_cola q on q.id = r.cola_id
           where r.unidad_id = p_unidad and r.client_id = c.client_id and not r.prueba order by r.creado_en desc limit 1),
         (select max(q.enviado_en) from public.reclamos_pago r join public.correos_cola q on q.id = r.cola_id and q.estado = 'ok'
           where r.unidad_id = p_unidad and r.client_id = c.client_id and not r.prueba),
         (select k.numero from public.contratos k where k.id = c.contrato_id)
    from public._reclamo_pago_candidatos(p_unidad) c
   where c.orden = 1
   order by c.seleccionable desc, c.nombre nulls last, c.contrato_id;
end $$;

create or replace function public.reclamo_pago_encolar(p_unidad uuid, p_clients uuid[], p_nota text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_emp   text;
  v_soc   text;
  v_hay   boolean;
  v_ids   uuid[];
  v_id    uuid;
  v_c     record;
  v_nota  text;
  v_quien text;
  v_rec   uuid;
  v_cola  uuid;
  v_out   jsonb := '[]'::jsonb;
begin
  -- 1. permiso: la empresa sale de la parcela (nunca de un parametro)
  select p.empresa, e.sociedad_clave into v_emp, v_soc
    from public.unidades u join public.proyectos p on p.id = u.proyecto_id
    left join public.empresas e on e.clave = p.empresa
   where u.id = p_unidad;
  v_hay := found;
  if not public.es_admin_de(v_emp) then
    raise exception 'No tienes permiso sobre esta parcela.' using errcode = '42501', hint = 'sin_permiso';
  end if;
  if not v_hay then
    raise exception 'La parcela no existe.' using errcode = '22023', hint = 'unidad_no_existe';
  end if;
  if v_soc is null then
    raise exception 'La empresa de este proyecto no tiene sociedad definida: no se puede enviar el recordatorio.'
      using errcode = '22023', hint = 'sociedad_proyecto_sin_definir';
  end if;

  -- 2. lote: sin repetidos, entre 1 y 10
  select coalesce(array_agg(x order by x), '{}') into v_ids from (select distinct u from unnest(coalesce(p_clients, '{}')) u where u is not null) d(x);
  if cardinality(v_ids) = 0 then
    raise exception 'Marca al menos una persona.' using errcode = '22023', hint = 'sin_destinatarios';
  end if;
  if cardinality(v_ids) > 10 then
    raise exception 'Como máximo 10 personas por envío.' using errcode = '22023', hint = 'demasiados_destinatarios';
  end if;

  -- 3. nota: texto plano, recortado, sin enlaces ni correos
  v_nota := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '[[:space:]]+', ' ', 'g')), '');
  if v_nota is not null and (char_length(v_nota) > 300 or v_nota ~* 'http|www\.|@|[a-z0-9-]\.(com|net|org|info|biz|io|co|id|es|app|xyz|top|link|click|online|site|ru|cn|me)([^a-z]|$)' or v_nota ~ '[[:cntrl:]]') then
    raise exception 'La nota admite hasta 300 caracteres de texto, sin enlaces ni direcciones de correo.'
      using errcode = '22023', hint = 'nota_invalida';
  end if;

  -- 4. anti doble clic: un candado por (parcela, persona), en orden fijo para no cruzarse
  foreach v_id in array v_ids loop
    perform pg_advisory_xact_lock(hashtextextended('reclamo_pago:' || p_unidad::text || ':' || v_id::text, 0));
  end loop;

  -- 5. cada persona debe ser un destinatario valido de ESTA parcela; si una no cuadra, se rechaza el lote entero
  foreach v_id in array v_ids loop
    select * into v_c from public._reclamo_pago_candidatos(p_unidad) c where c.client_id = v_id and c.orden = 1;
    if not found then
      raise exception 'Una de las personas marcadas no es compradora de esta parcela: no se envía nada.'
        using errcode = '22023', hint = 'destinatario_ajeno_a_la_parcela';
    end if;
    if not v_c.seleccionable then
      raise exception '%', case v_c.motivo
          when 'sin_ficha' then 'Una de las personas marcadas no tiene ficha de cliente: no se envía nada.'
          when 'sin_email' then 'Una de las personas marcadas no tiene un correo válido en su ficha: no se envía nada.'
          when 'sin_firmar' then 'El contrato de una de las personas marcadas aún no está firmado: no se envía nada.'
          when 'sociedad_nula' then 'El contrato de una de las personas marcadas no tiene sociedad firmante definida: no se envía nada.'
          else 'La sociedad del contrato de una de las personas marcadas no coincide con la de la empresa del proyecto: no se envía nada.' end
        using errcode = '22023', hint = v_c.motivo;
    end if;
    if exists (select 1 from public.reclamos_pago r
                where r.unidad_id = p_unidad and r.client_id = v_id and not r.prueba and r.creado_en > clock_timestamp() - interval '10 seconds') then
      raise exception 'Ya se ha enviado un recordatorio a una de las personas marcadas hace unos segundos: no se repite.'
        using errcode = '22023', hint = 'doble_clic';
    end if;
  end loop;

  -- 6. quien lo pide: de la sesion
  v_quien := lower(coalesce(nullif(btrim(coalesce(auth.email(), '')), ''),
                            (select u.email from public.usuarios u where u.user_id = (select auth.uid()))));
  if v_quien is null then
    raise exception 'No se pudo identificar quién envía el recordatorio.' using errcode = '42501', hint = 'sin_identidad';
  end if;

  -- 7. libro + cola (una fila de cada una por persona; un correo por persona, sin CC)
  foreach v_id in array v_ids loop
    select * into v_c from public._reclamo_pago_candidatos(p_unidad) c where c.client_id = v_id and c.orden = 1;
    insert into public.reclamos_pago (unidad_id, contrato_id, client_id, nota, creado_por, creado_por_uid)
    values (p_unidad, v_c.contrato_id, v_id, v_nota, v_quien, (select auth.uid()))
    returning id into v_rec;
    insert into public.correos_cola (clave, reclamo_id, prioridad)
    values ('reclamo_pago', v_rec, (select r.prioridad from public._correo_cola_regla('reclamo_pago') r))
    returning id into v_cola;
    update public.reclamos_pago set cola_id = v_cola where id = v_rec;
    v_out := v_out || jsonb_build_object('reclamo_id', v_rec, 'client_id', v_id);
  end loop;

  perform public._correos_cola_despierta();
  return jsonb_build_object('n', cardinality(v_ids), 'reclamos', v_out);
end $$;

create or replace function public.reclamo_pago_historial(p_unidad uuid)
returns table (reclamo_id uuid, creado_en timestamptz, creado_por text, client_id uuid, nombre text,
               estado text, enviado_en timestamptz, error text, nota text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_emp text;
  v_hay boolean;
begin
  select p.empresa into v_emp
    from public.unidades u join public.proyectos p on p.id = u.proyecto_id where u.id = p_unidad;
  v_hay := found;
  if not public.es_admin_de(v_emp) then
    raise exception 'No tienes permiso sobre esta parcela.' using errcode = '42501', hint = 'sin_permiso';
  end if;
  if not v_hay then
    raise exception 'La parcela no existe.' using errcode = '22023', hint = 'unidad_no_existe';
  end if;
  return query
  select r.id, r.creado_en, r.creado_por, r.client_id, k.full_name,
         case when r.prueba then 'prueba'
              when q.id is null then 'archivado'
              when q.estado in ('pendiente', 'enviando') then 'pendiente'
              when q.estado = 'ok' then 'enviado' else q.estado end,
         q.enviado_en, q.error, r.nota
    from public.reclamos_pago r
    left join public.clients k on k.id = r.client_id
    left join public.correos_cola q on q.id = r.cola_id
   where r.unidad_id = p_unidad
   order by r.creado_en desc, r.id
   limit 200;
end $$;

create or replace function public.reclamo_pago_prueba(p_unidad uuid, p_nota text default null)
returns text language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_emp   text;
  v_soc   text;
  v_hay   boolean;
  v_c     record;
  v_nota  text;
  v_quien text;
  v_rec   uuid;
  v_cola  uuid;
begin
  select p.empresa, e.sociedad_clave into v_emp, v_soc
    from public.unidades u join public.proyectos p on p.id = u.proyecto_id
    left join public.empresas e on e.clave = p.empresa
   where u.id = p_unidad;
  v_hay := found;
  if not public.es_admin_de(v_emp) then
    raise exception 'No tienes permiso sobre esta parcela.' using errcode = '42501', hint = 'sin_permiso';
  end if;
  if not v_hay then
    raise exception 'La parcela no existe.' using errcode = '22023', hint = 'unidad_no_existe';
  end if;
  if v_soc is null then
    raise exception 'La empresa de este proyecto no tiene sociedad definida: no se puede enviar el recordatorio.'
      using errcode = '22023', hint = 'sociedad_proyecto_sin_definir';
  end if;

  v_nota := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '[[:space:]]+', ' ', 'g')), '');
  if v_nota is not null and (char_length(v_nota) > 300 or v_nota ~* 'http|www\.|@|[a-z0-9-]\.(com|net|org|info|biz|io|co|id|es|app|xyz|top|link|click|online|site|ru|cn|me)([^a-z]|$)' or v_nota ~ '[[:cntrl:]]') then
    raise exception 'La nota admite hasta 300 caracteres de texto, sin enlaces ni direcciones de correo.'
      using errcode = '22023', hint = 'nota_invalida';
  end if;

  -- sociedad: la del primer contrato valido de la parcela
  select * into v_c from public._reclamo_pago_candidatos(p_unidad) c
   where c.orden = 1 and c.seleccionable order by c.contrato_id limit 1;
  if not found then
    raise exception 'Esta parcela no tiene ningún contrato firmado y válido con el que componer la prueba.'
      using errcode = '22023', hint = 'sin_contrato_valido';
  end if;

  v_quien := lower(coalesce(nullif(btrim(coalesce(auth.email(), '')), ''),
                            (select u.email from public.usuarios u where u.user_id = (select auth.uid()))));
  if v_quien is null or v_quien !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or char_length(v_quien) > 254 then
    raise exception 'No se pudo identificar a quién enviar la prueba.' using errcode = '42501', hint = 'sin_identidad';
  end if;

  insert into public.reclamos_pago (unidad_id, contrato_id, client_id, nota, creado_por, creado_por_uid, prueba)
  values (p_unidad, v_c.contrato_id, v_c.client_id, v_nota, v_quien, (select auth.uid()), true)
  returning id into v_rec;
  insert into public.correos_cola (clave, reclamo_id, prioridad)
  values ('reclamo_pago', v_rec, (select r.prioridad from public._correo_cola_regla('reclamo_pago') r))
  returning id into v_cola;
  update public.reclamos_pago set cola_id = v_cola where id = v_rec;
  perform public._correos_cola_despierta();
  return regexp_replace(v_quien, '^(.).*(@.*)$', '\1***\2');
end $$;

create or replace function public.portal_autoservicio(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_creadas int  := 0;
  v_activos int  := 0;
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('elegible', false, 'motivo', 'email_invalido');
  end if;

  if exists (select 1 from public.usuarios u where lower(btrim(u.email)) = v_email) then
    return jsonb_build_object('elegible', false, 'motivo', 'equipo');
  end if;

  if exists (select 1 from public.portal_accesos pa where pa.email = v_email and not pa.activo) then
    return jsonb_build_object('elegible', false, 'motivo', 'revocado');
  end if;

  insert into public.portal_accesos (email, client_id, activo, creado_por)
  select v_email, c.id, true, 'autoservicio'
    from public.clients c
   where lower(btrim(coalesce(c.email, ''))) = v_email
     and exists (select 1 from public.contrato_compradores cc where cc.client_id = c.id)
  on conflict (email, client_id) do nothing;
  get diagnostics v_creadas = row_count;

  select count(*) into v_activos
    from public.portal_accesos pa where pa.email = v_email and pa.activo;

  if v_activos = 0 then
    return jsonb_build_object('elegible', false, 'motivo', 'sin_ficha');
  end if;

  return jsonb_build_object('elegible', true, 'creadas', v_creadas, 'accesos', v_activos);
end
$$;

revoke execute on function public.portal_autoservicio(text) from public, anon, authenticated;
grant  execute on function public.portal_autoservicio(text) to service_role;

-- 3. funciones nuevas
drop function if exists public.invitacion_portal_destinatarios(uuid);
drop function if exists public.invitacion_portal_encolar(uuid, uuid[], text);
drop function if exists public.invitacion_portal_historial(uuid);
drop function if exists public.invitacion_portal_prueba(uuid, text);
drop function if exists public.invitacion_portal_datos(uuid);
drop function if exists public._invitacion_portal_candidatos(uuid);
drop function if exists public._nota_correo_limpia(text);
drop function if exists public._portal_rechazo(text);

-- 4. CHECKs como estaban (sin invitacion_portal)
alter table public.correo_plantillas drop constraint correo_plantillas_clave_check;
alter table public.correo_plantillas add constraint correo_plantillas_clave_check check (clave = any (array[
  'enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
  'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago'])) not valid;
alter table public.correos_enviados drop constraint correos_enviados_via_check;
alter table public.correos_enviados add constraint correos_enviados_via_check check (via = any (array[
  'manual','enlace_firma','firma','proforma','factura','factura_auto','aviso_anulacion','copia_firmada','reclamo_pago'])) not valid;
alter table public.correos_enviados drop constraint correos_enviados_plantilla_check;
alter table public.correos_enviados add constraint correos_enviados_plantilla_check check (
  (plantilla is null and plantilla_version is null)
  or (plantilla is not null and plantilla_version is not null
      and plantilla = any (array['enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
                                 'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago'])
      and plantilla_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$')) not valid;

-- 5. la plantilla (sellada: el trigger se apaga solo para esto)
alter table public.correo_plantillas disable trigger correo_plantillas_sellado;
delete from public.correo_plantillas where clave = 'invitacion_portal';
alter table public.correo_plantillas enable trigger correo_plantillas_sellado;
alter table public.correo_plantillas validate constraint correo_plantillas_clave_check;
alter table public.correos_enviados validate constraint correos_enviados_via_check;
alter table public.correos_enviados validate constraint correos_enviados_plantilla_check;

-- 6. el libro vuelve a su forma
alter table public.correos_cola drop constraint if exists correos_cola_reclamo_tipo_fk;
alter table public.reclamos_pago drop constraint if exists reclamos_pago_id_tipo_uq;
drop index if exists public.reclamos_pago_unidad_tipo_idx;
drop index if exists public.reclamos_pago_contrato_idx;
drop index if exists public.reclamos_pago_cola_idx;
drop index if exists public.reclamos_pago_tipo_creado_idx;
alter table public.reclamos_pago drop column tipo;
create index if not exists reclamos_pago_unidad_idx on public.reclamos_pago (unidad_id, creado_en desc);
comment on column public.correos_cola.reclamo_id is null;
comment on table public.reclamos_pago is
  'Libro de «Reclamar pago» (8-oct-2026). Una fila por persona y pulsacion: quien lo pidio (de la sesion, nunca del navegador), cuando, a quien (ids; el correo vive en clients) y la nota. El estado del envio lo da correos_cola via cola_id. Solo se escribe desde reclamo_pago_encolar y reclamo_pago_prueba. prueba=true: «Enviarme una prueba» (el destinatario es creado_por, nunca el comprador; no cuenta como reclamo).';
