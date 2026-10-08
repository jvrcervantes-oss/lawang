-- destructivo-ok: solo construye (tabla nueva reclamos_pago vacia, funciones nuevas, una fila de plantilla, una columna nueva). Los tres "drop constraint" SUSTITUYEN un CHECK por otro mas ancho (correo_plantillas_clave_check, correos_enviados_via_check/plantilla_check: se les añade 'reclamo_pago') y el de correos_cola_un_ancla (se le añade reclamo_id); ninguna fila existente deja de cumplirlos. Ningun dato se borra ni se modifica. Reversion: supabase/reversion_reclamo_pago/REVERSION.sql.
-- ============================================================================
-- LAWANG — «RECLAMAR PAGO» DESDE LA FICHA DE PARCELA — BASE DE DATOS (8-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261008_lawang_reclamo_pago_parcela.md (plan + revision previa #230 + decisiones del owner).
-- Subtarea 1 (Datos): libro, destinatarios, encolar, historial y los ganchos SQL de la cola de correos.
-- La edge (cola-correos-envio), la plantilla de texto y la pantalla son de las subtareas 2-4.
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md) — que se guarda aqui y que NO:
--   · quien es, su correo, su idioma  -> dueño: clients. NO se copia: el destinatario se resuelve al enviar.
--   · contrato, parcela, proyecto     -> dueños: contratos / unidades / proyectos. El libro guarda solo ids.
--   · empresa y sociedad del correo   -> sociedad = la del CONTRATO (datos_fields.sociedad_firmante); debe coincidir
--                                        con empresas.sociedad_clave de la empresa del proyecto. Si es nula o no coincide, NO se encola.
--   · la nota del cliente             -> dueño: reclamos_pago.nota (el texto no viaja en correos_cola.vars: ese campo
--                                        rechaza '@' y corta a 120). La edge la lee con reclamo_pago_datos().
--   · estado del envio                -> dueño: correos_cola. El historial lo lee de alli (cola_id).
--
-- DESVIACIONES DEL PLAN, A PROPOSITO (el CEO las ve en el informe):
--   1. correos_cola.reclamo_id es un ancla NUEVA (cuarta). Anclar a contrato_id habria hecho que el indice
--      unico correos_cola_uno (clave, documento) tragara cada reclamo posterior al primero de un contrato
--      (una fila `ok` sigue contando como viva hasta la purga de 90 dias) y el owner decidio SIN limite de
--      frecuencia. Con ancla reclamo_id la clave del indice queda NULL y los NULL no chocan entre si.
--   2. No se llama a correo_encolar: es de firma/factura (rechaza las claves que no soporta y su ON CONFLICT
--      es el que tragaria el reintento) y añadirle un argumento crearia un sobrecargado que haria ambiguas las
--      llamadas de firma-submit. reclamo_pago_encolar inserta en correos_cola con la misma forma y despierta
--      la edge con _correos_cola_despierta(). _correo_cola_regla lo marca soportada=false para que correo_encolar
--      siga rechazando 'reclamo_pago' si alguien lo intenta por la puerta equivocada.
--   3. Destinatarios: contratos.unidad_id solo llega a 77 de 146 parcelas con contrato; unidades.contrato_id
--      llega a las 146. Se usa la UNION de las dos (nunca parcela_codigo, que es texto). Medido 8-oct-2026.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado):
--   reclamo_pago_destinatarios / _encolar / _historial / _prueba  <- pantalla de la ficha de parcela (authenticated;
--                                                                                   por dentro: es_admin_de(empresa del proyecto de la parcela))
--   reclamo_pago_datos                                                          <- edge cola-correos-envio (service_role)
--   _reclamo_pago_candidatos/_vigente/_destino                                  <- las RPC de arriba y correo_cola_reclamar. Sin grants.
--   reclamos_pago (tabla)                                                       <- nadie directo: RLS activa, sin policies, sin grants.
-- ============================================================================

-- ── 1. el libro ──────────────────────────────────────────────────────────────
create table public.reclamos_pago (
  id           uuid primary key default gen_random_uuid(),
  unidad_id    uuid not null references public.unidades (id) on delete cascade,
  contrato_id  uuid not null references public.contratos (id) on delete cascade,
  client_id    uuid not null references public.clients (id) on delete cascade,
  nota         text check (nota is null or char_length(nota) <= 300),
  creado_por   text not null check (char_length(creado_por) between 3 and 254),
  creado_por_uid uuid,
  creado_en    timestamptz not null default now(),
  cola_id      uuid,
  prueba       boolean not null default false
);
comment on table public.reclamos_pago is
  'Libro de «Reclamar pago» (8-oct-2026). Una fila por persona y pulsacion: quien lo pidio (de la sesion, nunca del navegador), cuando, a quien (ids; el correo vive en clients) y la nota. El estado del envio lo da correos_cola via cola_id. Solo se escribe desde reclamo_pago_encolar y reclamo_pago_prueba. prueba=true: «Enviarme una prueba» (el destinatario es creado_por, nunca el comprador; no cuenta como reclamo).';
create index reclamos_pago_unidad_idx on public.reclamos_pago (unidad_id, creado_en desc);
create index reclamos_pago_client_idx on public.reclamos_pago (client_id);
alter table public.reclamos_pago enable row level security;
revoke all on public.reclamos_pago from public, anon, authenticated, lw_lector, service_role;

-- ── 2. la cola gana un ancla: el reclamo ─────────────────────────────────────
alter table public.correos_cola add column reclamo_id uuid references public.reclamos_pago (id) on delete cascade;
alter table public.reclamos_pago add constraint reclamos_pago_cola_fk foreign key (cola_id) references public.correos_cola (id) on delete set null;
alter table public.correos_cola drop constraint correos_cola_un_ancla;
alter table public.correos_cola add constraint correos_cola_un_ancla check (num_nonnulls(firma_id, contrato_id, factura_id, reclamo_id) = 1);
create unique index correos_cola_reclamo_uno on public.correos_cola (reclamo_id) where reclamo_id is not null;

-- ── 3. la clave nueva en los CHECK que la listan ─────────────────────────────
alter table public.correo_plantillas drop constraint correo_plantillas_clave_check;
alter table public.correo_plantillas add constraint correo_plantillas_clave_check check (clave = any (array[
  'enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
  'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago']));

alter table public.correos_enviados drop constraint correos_enviados_via_check;
alter table public.correos_enviados add constraint correos_enviados_via_check check (via = any (array[
  'manual','enlace_firma','firma','proforma','factura','factura_auto','aviso_anulacion','copia_firmada','reclamo_pago']));
alter table public.correos_enviados drop constraint correos_enviados_plantilla_check;
alter table public.correos_enviados add constraint correos_enviados_plantilla_check check (
  (plantilla is null and plantilla_version is null)
  or (plantilla is not null and plantilla_version is not null
      and plantilla = any (array['enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
                                 'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago'])
      and plantilla_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$'));

-- La fila de plantilla (la cola la referencia por FK). Nace inactiva y sin texto, como las otras ocho; el texto
-- aprobado lo pone la subtarea 2. OJO: el catalogo de variables queda SELLADO tras el insert (_trg_correo_plantillas_sellado):
-- saludo, parcela, proyecto, empresa, nota, enlace, marca, firma.
insert into public.correo_plantillas (clave, activa, variables, version)
values ('reclamo_pago', false,
        '{"permitidas":["saludo","parcela","proyecto","empresa","nota","enlace","marca","firma"],"obligatorias":{"asunto":["parcela"],"cuerpo":["parcela","enlace"],"cuerpo_alt":[]},"variantes":1}'::jsonb, 0)
on conflict (clave) do nothing;

-- ── 4. reglas por clave: la fila nueva (soportada=false: correo_encolar la rechaza) ─────────────────
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

-- ── 5. candidatos: UNA sola definicion de «quien puede recibir el reclamo de esta parcela» ──────────
-- Una fila por contrato vivo de la parcela (union de contratos.unidad_id y unidades.contrato_id, mismo proyecto,
-- liberado_en nulo). `orden` = 1 para el contrato que representa a cada persona (prefiere el que se puede enviar,
-- luego el firmado mas reciente). motivo nulo = seleccionable.
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

-- ── 6. la cola sabe resolver un reclamo: vigente y destinatario, desde la base ──────────────────────
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

create or replace function public._reclamo_pago_destino(p_reclamo uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case when s.e ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and char_length(s.e) <= 254 then s.e end
    from (select case when r.prueba then lower(btrim(r.creado_por)) else lower(btrim(k.email)) end as e
            from public.reclamos_pago r join public.clients k on k.id = r.client_id
           where r.id = p_reclamo) s
$$;

-- Reclamar (mismo contrato de salida que antes): para las filas de reclamo, vigencia y destino salen del libro.
create or replace function public.correo_cola_reclamar(p_max int default 5)
returns table (id uuid, clave text, firma_id uuid, contrato_id uuid, factura_id uuid,
               vars jsonb, para text, prioridad smallint, intentos int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  update public.correos_cola q set estado = 'cancelado', error = 'hecho_no_vigente', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and not (case when q.reclamo_id is not null then public._reclamo_pago_vigente(q.reclamo_id)
                   else public._correo_cola_vigente(q.clave, q.firma_id, q.contrato_id, q.factura_id) end);

  update public.correos_cola q set estado = 'error', error = 'tope_antiguedad', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and q.encolado_en + make_interval(hours => (select r.tope_horas from public._correo_cola_regla(q.clave) r)) < now();

  update public.correos_cola q set estado = 'error', error = 'sin_destinatario', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and (case when q.reclamo_id is not null then public._reclamo_pago_destino(q.reclamo_id)
               else public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id) end) is null;

  update public.correos_cola q set estado = 'error', error = 'agotado', reclamado_hasta = null
   where q.estado = 'enviando' and q.reclamado_hasta <= now()
     and q.intentos >= (select r.max_intentos from public._correo_cola_regla(q.clave) r);

  return query
  with cand as (
    select x.id as cid
      from public.correos_cola x
     where (x.estado = 'pendiente' and x.proximo_intento_en <= now())
        or (x.estado = 'enviando' and x.reclamado_hasta <= now())
     order by x.prioridad, x.encolado_en
     limit least(greatest(coalesce(p_max, 5), 1), 10)
     for update of x skip locked)
  update public.correos_cola q
     set estado = 'enviando', reclamado_hasta = now() + interval '4 minutes', intentos = q.intentos + 1
    from cand
   where q.id = cand.cid
  returning q.id, q.clave, q.firma_id,
            coalesce(q.contrato_id,
                     (select f.contrato_id from public.contrato_firmas f where f.id = q.firma_id),
                     (select x.contrato_id from public.reclamos_pago x where x.id = q.reclamo_id)),
            q.factura_id, q.vars,
            case when q.reclamo_id is not null then public._reclamo_pago_destino(q.reclamo_id)
                 else public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id) end,
            q.prioridad, q.intentos;
end $$;

-- Cerrar ok: el contrato del registro sale tambien del libro cuando la fila es un reclamo.
create or replace function public.correo_cola_ok(p_id uuid, p_para text, p_version text)
returns boolean language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  r  record;
  g  record;
begin
  update public.correos_cola q
     set estado = 'ok', error = null, enviado_en = now(), reclamado_hasta = null
   where q.id = p_id and q.estado = 'enviando'
  returning q.clave, q.firma_id, q.contrato_id, q.factura_id, q.reclamo_id into r;
  if not found then return false; end if;
  -- una PRUEBA de «Reclamar pago» llega solo a quien la pidio: no deja registro de «correo enviado» en el contrato
  if r.reclamo_id is not null and exists (select 1 from public.reclamos_pago x where x.id = r.reclamo_id and x.prueba) then
    return true;
  end if;
  select * into g from public._correo_cola_regla(r.clave);

  insert into public.correos_enviados
         (contrato_id, factura_id, para, asunto, via, enviado_por, mensaje, plantilla, plantilla_version)
  values (coalesce(r.contrato_id,
                   (select f.contrato_id from public.contrato_firmas f where f.id = r.firma_id),
                   (select x.contrato_id from public.reclamos_pago x where x.id = r.reclamo_id)),
          r.factura_id, lower(btrim(p_para)), g.asunto_registro, g.via, null, null,
          case when p_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$' then r.clave end,
          case when p_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$' then p_version end);
  return true;
end $$;

-- Lo que la edge necesita para componer el correo de una fila de la cola (y nada mas).
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

-- ── 7. RPC de cara a la pantalla ─────────────────────────────────────────────
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
  if v_nota is not null and (char_length(v_nota) > 300 or v_nota ~* 'http|www\.|@' or v_nota ~ '[[:cntrl:]]') then
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

-- Prueba: el mismo correo, solo para quien pulsa. El destinatario NO es un parametro: es el correo de la sesion
-- (auth.email(), o usuarios.email), guardado en creado_por; _reclamo_pago_destino lo usa cuando prueba=true.
-- La sociedad (marca/firma) sale del primer contrato valido de la parcela, igual que en un reclamo real, pero la fila
-- lleva prueba=true: no cuenta como reclamo en destinatarios/doble clic, el historial la rotula 'prueba' y
-- correo_cola_ok no escribe en correos_enviados del contrato. Sin anti doble clic por comprador (no hay comprador).
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
  if v_nota is not null and (char_length(v_nota) > 300 or v_nota ~* 'http|www\.|@' or v_nota ~ '[[:cntrl:]]') then
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

-- ── 8. permisos: EXECUTE llega por PUBLIC y por los default privileges de Supabase si no se revoca ──
revoke all on function public._reclamo_pago_candidatos(uuid), public._reclamo_pago_vigente(uuid), public._reclamo_pago_destino(uuid)
  from public, anon, authenticated, lw_lector, service_role;
revoke all on function public.reclamo_pago_destinatarios(uuid), public.reclamo_pago_encolar(uuid, uuid[], text), public.reclamo_pago_historial(uuid),
  public.reclamo_pago_prueba(uuid, text)
  from public, anon, authenticated, lw_lector, service_role;
revoke all on function public.reclamo_pago_datos(uuid) from public, anon, authenticated, lw_lector;
grant execute on function public.reclamo_pago_destinatarios(uuid), public.reclamo_pago_encolar(uuid, uuid[], text), public.reclamo_pago_historial(uuid), public.reclamo_pago_prueba(uuid, text) to authenticated;
grant execute on function public.reclamo_pago_datos(uuid) to service_role;
