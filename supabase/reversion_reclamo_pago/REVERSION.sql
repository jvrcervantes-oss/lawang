-- destructivo-ok: REVERSION de 20261010070000_reclamo_pago_parcela.sql. Borra SOLO lo que esa migracion creo (libro reclamos_pago y sus filas, filas de cola con clave reclamo_pago, la plantilla reclamo_pago, la columna reclamo_id, 5+3 funciones (incluida reclamo_pago_prueba)) y restaura las definiciones anteriores byte a byte (copiadas de produccion el 8-oct-2026 con pg_get_functiondef). Los correos YA enviados quedan en correos_enviados (via = reclamo_pago): se reetiquetan a 'manual' antes de estrechar el CHECK, no se borran.
-- Orden: 1) cola y registro, 2) funciones viejas, 3) CHECKs, 4) columna, 5) tabla, 6) funciones nuevas.
-- Aplicar solo con el OK del owner. El trigger de sellado de correo_plantillas impide borrar la fila: se desactiva un instante.

-- 1. filas que dependen de lo nuevo
delete from public.correos_cola where reclamo_id is not null or clave = 'reclamo_pago';
update public.correos_enviados set via = 'manual', plantilla = null, plantilla_version = null where via = 'reclamo_pago' or plantilla = 'reclamo_pago';

-- 2. funciones como estaban (create or replace conserva sus permisos)
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
      ('factura_vencimiento',     'factura_id',  false, 720, 5::smallint, 10, 'factura_auto',   'Factura',                      array['nombre'])
    ) as r(clave, ancla, soportada, tope_horas, prioridad, max_intentos, via, asunto_registro, editables)
   where r.clave = p_clave
$$;

create or replace function public.correo_cola_reclamar(p_max int default 5)
returns table (id uuid, clave text, firma_id uuid, contrato_id uuid, factura_id uuid,
               vars jsonb, para text, prioridad smallint, intentos int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  update public.correos_cola q set estado = 'cancelado', error = 'hecho_no_vigente', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and not public._correo_cola_vigente(q.clave, q.firma_id, q.contrato_id, q.factura_id);

  update public.correos_cola q set estado = 'error', error = 'tope_antiguedad', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and q.encolado_en + make_interval(hours => (select r.tope_horas from public._correo_cola_regla(q.clave) r)) < now();

  update public.correos_cola q set estado = 'error', error = 'sin_destinatario', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id) is null;

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
            coalesce(q.contrato_id, (select f.contrato_id from public.contrato_firmas f where f.id = q.firma_id)),
            q.factura_id, q.vars,
            public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id),
            q.prioridad, q.intentos;
end $$;

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
  returning q.clave, q.firma_id, q.contrato_id, q.factura_id into r;
  if not found then return false; end if;
  select * into g from public._correo_cola_regla(r.clave);

  insert into public.correos_enviados
         (contrato_id, factura_id, para, asunto, via, enviado_por, mensaje, plantilla, plantilla_version)
  values (coalesce(r.contrato_id, (select f.contrato_id from public.contrato_firmas f where f.id = r.firma_id)),
          r.factura_id, lower(btrim(p_para)), g.asunto_registro, g.via, null, null,
          case when p_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$' then r.clave end,
          case when p_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$' then p_version end);
  return true;
end $$;

-- 3. CHECKs como estaban
alter table public.correos_enviados drop constraint correos_enviados_plantilla_check;
alter table public.correos_enviados add constraint correos_enviados_plantilla_check check (
  (plantilla is null and plantilla_version is null)
  or (plantilla is not null and plantilla_version is not null
      and plantilla = any (array['enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
                                 'factura_primer_hito','proforma_total','factura_vencimiento'])
      and plantilla_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$'));
alter table public.correos_enviados drop constraint correos_enviados_via_check;
alter table public.correos_enviados add constraint correos_enviados_via_check check (via = any (array[
  'manual','enlace_firma','firma','proforma','factura','factura_auto','aviso_anulacion','copia_firmada']));

alter table public.correo_plantillas disable trigger correo_plantillas_sellado;
delete from public.correo_plantillas where clave = 'reclamo_pago';
alter table public.correo_plantillas enable trigger correo_plantillas_sellado;
alter table public.correo_plantillas drop constraint correo_plantillas_clave_check;
alter table public.correo_plantillas add constraint correo_plantillas_clave_check check (clave = any (array[
  'enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
  'factura_primer_hito','proforma_total','factura_vencimiento']));

-- 4-5. columna, ancla y tabla
drop index if exists public.correos_cola_reclamo_uno;
alter table public.correos_cola drop constraint correos_cola_un_ancla;
alter table public.correos_cola drop column reclamo_id;
alter table public.correos_cola add constraint correos_cola_un_ancla check (num_nonnulls(firma_id, contrato_id, factura_id) = 1);
drop table public.reclamos_pago;

-- 6. funciones nuevas
drop function public.reclamo_pago_destinatarios(uuid);
drop function public.reclamo_pago_encolar(uuid, uuid[], text);
drop function public.reclamo_pago_historial(uuid);
drop function public.reclamo_pago_prueba(uuid, text);
drop function public.reclamo_pago_datos(uuid);
drop function public._reclamo_pago_candidatos(uuid);
drop function public._reclamo_pago_vigente(uuid);
drop function public._reclamo_pago_destino(uuid);
