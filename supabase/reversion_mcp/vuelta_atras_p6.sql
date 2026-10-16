-- destructivo-ok: VUELTA ATRÁS de 20261016135900_mcp_f1_p6_aviso_conexion.sql (el correo en cada conexión nueva del MCP de Lawang).
-- Quita los dos disparadores y las funciones de P6 y deja las tres funciones de la cola y privado.ia_conexion_motivo EXACTAMENTE como estaban en la viva el
-- 16-oct (texto sacado con pg_get_functiondef; el md5 de cada una va encima y se comprueba al final: si no casa, ROLLBACK).
-- ANTES: apagar la IA (Ajustes › IA › Apagado) o deshacer la propuesta 20261016140000. Sin P6 una conexión nueva ya no avisa a
-- nadie: con la IA encendida esto deja abierta la puerta que P6 cierra.
-- No borra datos: las columnas (ia_conexiones.avisada_en, correos_cola.ia_conexion_id), las restricciones, el índice y la fila
-- de plantilla se quedan (quitarlas es destructivo y lo decide el owner). Un aviso que aún no había salido se cancela y, como
-- dice P6, su conexión se corta (sin_aviso): se hace CON los disparadores todavía puestos, para que nadie quede conectado sin aviso.
begin;
set local lock_timeout = '5s';

-- 0. la condición de arriba, comprobada: con la IA encendida y la entrada abierta a anon no se quita el aviso (Seguridad, 2.ª vuelta)
do $g$
begin
  if coalesce((select encendido from public.ia_ajustes where id), false)
     and has_function_privilege('anon', 'public.ia_puente(text,jsonb)', 'execute') then
    raise exception 'vuelta_atras_p6: primero apagar la IA (Ajustes › IA) o deshacer la 20261016140000; no se aplica nada';
  end if;
  -- la 20261016230000 lee la regla con el EXECUTE que esto quita: se deshace ella antes (vuelta_atras_mis_conexiones.sql)
  if pg_get_functiondef('public.ia_mis_conexiones()'::regprocedure) like '%_correo_cola_regla%' then
    raise exception 'vuelta_atras_p6: primero vuelta_atras_mis_conexiones.sql (la 20261016230000 usa la regla del aviso); no se aplica nada';
  end if;
end $g$;

-- 1. lo que quedaba por enviar se cancela; el disparador de P6 corta su conexión
update public.correos_cola q set estado = 'cancelado', error = 'vuelta_atras_p6', reclamado_hasta = null
 where q.ia_conexion_id is not null and q.estado in ('pendiente', 'enviando');

-- 2. los disparadores
drop trigger if exists ia_conexiones_aviso on public.ia_conexiones;
drop trigger if exists correos_cola_aviso_ia_fallido on public.correos_cola;

-- 3. las tres funciones de la cola, como en la viva antes de P6
-- _correo_cola_regla: md5 de pg_get_functiondef en la viva el 16-oct = 9edf5cf203bf902ed68077521e3e93ac
CREATE OR REPLACE FUNCTION public._correo_cola_regla(p_clave text)
 RETURNS TABLE(ancla text, soportada boolean, tope_horas integer, prioridad smallint, max_intentos integer, via text, asunto_registro text, editables text[])
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
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
      ('reclamo_pago',            'reclamo_id',  false,  24, 7::smallint,  3, 'reclamo_pago',   'Recordatorio de pago',         array[]::text[]),
      ('invitacion_portal',       'reclamo_id',  false,  72, 7::smallint,  3, 'invitacion_portal', 'Invitación al portal',      array[]::text[])
    ) as r(clave, ancla, soportada, tope_horas, prioridad, max_intentos, via, asunto_registro, editables)
   where r.clave = p_clave
$function$;

-- correo_cola_reclamar: md5 de pg_get_functiondef en la viva el 16-oct = 51e48bd6aa431d3f85f44ad9b4e56af7
CREATE OR REPLACE FUNCTION public.correo_cola_reclamar(p_max integer DEFAULT 5)
 RETURNS TABLE(id uuid, clave text, firma_id uuid, contrato_id uuid, factura_id uuid, vars jsonb, para text, prioridad smallint, intentos integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

-- correo_cola_ok: md5 de pg_get_functiondef en la viva el 16-oct = cb7e41223cea6f9d834b361e9c015697
CREATE OR REPLACE FUNCTION public.correo_cola_ok(p_id uuid, p_para text, p_version text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

-- 3b. la regla única del puente, como en la viva antes de P6 (sin el corte sin_aviso; dueño y EXECUTE no cambian)
-- privado.ia_conexion_motivo: md5 de pg_get_functiondef en la viva el 16-oct = 3c7260d0910a6216d5051f227d904845
CREATE OR REPLACE FUNCTION privado.ia_conexion_motivo(p_conexion uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.ia_conexiones; a public.ia_ajustes; u jsonb;
begin
  select * into c from public.ia_conexiones where id = p_conexion;
  if c.id is null then return 'sin_conexion'; end if;
  if c.revocada_en is not null then return 'revocada'; end if;
  if c.expira_en <= now() then return 'caducada'; end if;
  select * into a from public.ia_ajustes where id;
  if not coalesce(a.encendido, false) then return 'apagado'; end if;
  if not exists (select 1 from public.ia_clientes k where k.id = c.cliente_id and k.activo) then
    perform privado.ia_revoca(c.id, 'cliente'); return 'cliente';
  end if;
  if not exists (select 1 from public.ia_permisos p where p.usuario_id = c.usuario_id and p.quitado_en is null) then
    perform privado.ia_revoca(c.id, 'permiso'); return 'permiso';
  end if;
  u := privado.ia_auth_usuario(c.usuario_id);
  if u is null or not coalesce((u ->> 'activo')::boolean, false) or coalesce((u ->> 'baneado')::boolean, true) then
    perform privado.ia_revoca(c.id, 'usuario_inactivo'); return 'usuario_inactivo';
  end if;
  if (u ->> 'huella') is distinct from c.huella then
    perform privado.ia_revoca(c.id, 'contrasena'); return 'contrasena';
  end if;
  return null;
end $function$;
revoke execute on function public._correo_cola_regla(text) from ia_puente_rol;

-- 4. las funciones de P6 (ya nadie las llama: reclamar vuelve a no conocer ia_conexion_id)
drop function if exists public.ia_aviso_conexion_datos(uuid);
drop function if exists privado.ia_aviso_conexion();
drop function if exists privado.ia_aviso_fallido();
drop function if exists privado.ia_aviso_destino(uuid);
drop function if exists privado.ia_aviso_nombre(text);

-- 5. comprobación: el texto restaurado es el de antes, byte a byte
do $c$
begin
  if md5(pg_get_functiondef('public._correo_cola_regla(text)'::regprocedure)) <> '9edf5cf203bf902ed68077521e3e93ac'
     or md5(pg_get_functiondef('public.correo_cola_reclamar(integer)'::regprocedure)) <> '51e48bd6aa431d3f85f44ad9b4e56af7'
     or md5(pg_get_functiondef('public.correo_cola_ok(uuid,text,text)'::regprocedure)) <> 'cb7e41223cea6f9d834b361e9c015697'
     or md5(pg_get_functiondef('privado.ia_conexion_motivo(uuid)'::regprocedure)) <> '3c7260d0910a6216d5051f227d904845'
     or has_function_privilege('ia_puente_rol', 'public._correo_cola_regla(text)', 'execute') then
    raise exception 'vuelta_atras_p6: el texto restaurado no es el de la viva del 16-oct; no se aplica nada';
  end if;
end $c$;
commit;
