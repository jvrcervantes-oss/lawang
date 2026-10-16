-- destructivo-ok: solo construye. Cuatro CHECK que se SUSTITUYEN por otros más anchos o se añaden (correos_cola_un_ancla gana un quinto ancla, correo_plantillas_clave_check la clave 'aviso_ia_conexion', ia_conexiones_revocada_motivo_check el motivo 'sin_aviso'; ninguna fila deja de cumplirlos: 13 filas en la cola y 0 conexiones, medidas el 16-oct), dos columnas nuevas sin datos, dos índices, una fila de plantilla inactiva, dos triggers y funciones nuevas o redefinidas desde su definición viva. Ningún dato se borra ni se modifica. Reversión: supabase/reversion_mcp/vuelta_atras_p6.sql.
-- ============================================================================
-- LAWANG — MCP F1 · P6 — CORREO A LA PERSONA EN CADA CONEXIÓN NUEVA DE UN ASISTENTE (16-oct-2026, sesión mcp-abre)
-- ----------------------------------------------------------------------------
-- Condición de Seguridad para abrir la entrada del puente (LAW-642): una conexión de un asistente sobrevive a cerrar sesión y a
-- «cerrar todas las sesiones», así que la persona tiene que enterarse de cada conexión nueva. Va ANTES de la propuesta
-- 20261016140000 (la que deja crear conexiones): sin ella esta migración no tiene llamador, porque no nace ninguna conexión.
-- Revisión previa #404 (Seguridad + Base de datos), plegada aquí.
--
-- QUÉ: al nacer una fila en public.ia_conexiones (solo la crea public.ia_conexion_autoriza; medido en catálogo y repo el 16-oct)
-- un trigger encola un correo a la persona por la cola de siempre (correos_cola → cola-correos-envio → envia-correo): qué asistente,
-- cuándo (hora de Bali) y el enlace a «Apps conectadas» (intranet/v4/ia/) para quitarla. Molde: invitacion_portal (20261015071004).
--
-- SI EL AVISO NO LLEGA, LA CONEXIÓN NO VIVE (Seguridad #404, punto 1). Encolar no es avisar: la fila puede acabar en error por
-- tope de antigüedad (24 h), por agotar sus 5 intentos o sin destinatario, o quedarse esperando. Cuando la fila del aviso acaba en
-- `error` o `cancelado`, el trigger correos_cola_aviso_ia_fallido revoca la conexión con motivo 'sin_aviso' en la misma sentencia.
-- Y como con los envíos EN PAUSA nadie llama a correo_cola_reclamar (la edge vuelve antes; Seguridad, diff de P6, 16-oct), el tope
-- de antigüedad no lo aplicaría la cola: lo aplica también la regla única del puente, privado.ia_conexion_motivo (puerta, refresca,
-- canjea, comprueba): una conexión sin avisada_en pasadas las tope_horas de su regla (24) se corta con 'sin_aviso' en su siguiente
-- uso, sin cron ni cola. Una conexión viva sin aviso solo existe mientras el correo está en camino, y como mucho 24 h.
--
-- TOPE DE ALTAS (Seguridad #404, punto 2). max_conexiones cuenta solo las vivas: crear, cortar y crear otra vez mandaría correos sin
-- fin por el buzón de la marca (cuya cuota comparten los enlaces de firma y las facturas). El trigger del alta cuenta TODAS las
-- altas de la última hora, cortadas incluidas: 5 por persona y 20 en toda la base (bajo un candado fijo, como la invitación al
-- portal). Pasarlo lanza 'demasiadas_altas' y la conexión no nace; la edge `mcp` lo traduce a ese código para la página.
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md):
--   · a quién se avisa       -> auth.users.email del usuario_id de la conexión, resuelto AL ENVIAR y en UN sitio
--                               (privado.ia_aviso_destino): lo usan reclamar (el `para` de la fila) y la RPC de datos, y envia-correo
--                               rechaza el envío si no coinciden. Nunca usuarios.email: es una copia y hoy 1 de 35 ya no coincide
--                               con auth (Base de datos #404). Nada viaja del navegador; vars de la fila = '{}' (CHECK).
--   · qué asistente          -> ia_clientes (asistente, de lista cerrada, y nombre), leído al enviar por public.ia_aviso_conexion_datos.
--                               El nombre pasa por la regla de las notas de correo (_nota_correo_limpia): una regla, no otra.
--   · que la persona fue avisada -> ia_conexiones.avisada_en, que pone correo_cola_ok. La fila `ok` de la cola no basta: la purga
--                               de la cola borra las `ok` a los 90 días. correos_enviados NO: es el registro de los correos de un
--                               contrato o una factura (su CHECK correos_con_ancla lo exige) y esta fila no tiene ni uno ni otra.
--   · la clave va atada a su ancla -> CHECK correos_cola_ia_clave: ninguna otra clave lleva ia_conexion_id y el aviso no sale sin él.
--
-- LO QUE NO HACE: no avisa de refrescos (no insertan en ia_conexiones) ni de revocaciones; no avisa al super admin (para cuando
-- se abra al equipo); revocar la conexión antes de que salga el correo NO lo cancela (quien la crea y la quita al momento no la
-- esconde). Falla cerrado: el trigger del alta va en la misma transacción; si no se puede encolar, la conexión no nace.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado):
--   privado.ia_aviso_conexion()          <- trigger ia_conexiones_aviso. Sin EXECUTE para nadie (un trigger no lo pide al disparar).
--   privado.ia_aviso_fallido()           <- trigger correos_cola_aviso_ia_fallido. Sin EXECUTE para nadie.
--   privado.ia_aviso_destino(uuid)       <- public.correo_cola_reclamar y public.ia_aviso_conexion_datos (DEFINER de postgres).
--   privado.ia_aviso_nombre(text)        <- public.ia_aviso_conexion_datos. Sin EXECUTE para nadie.
--   public.ia_aviso_conexion_datos(uuid) <- edge envia-correo (service_role). Solo service_role.
--   public._correo_cola_regla(text)      <- EXECUTE nuevo a ia_puente_rol; su llamador: privado.ia_conexion_motivo (§7b).
--
-- MD5 DE LAS DEFINICIONES VIVAS DE LAS QUE PARTE (md5(pg_get_functiondef), Lawang, 16-oct; volver a medir antes de aplicar):
--   correo_cola_reclamar 51e48bd6aa431d3f85f44ad9b4e56af7 · correo_cola_ok cb7e41223cea6f9d834b361e9c015697
--   _correo_cola_regla 9edf5cf203bf902ed68077521e3e93ac · privado.ia_conexion_motivo 3c7260d0910a6216d5051f227d904845
-- ============================================================================

set local lock_timeout = '5s';

-- ── 1. la conexión: rastro del aviso, motivo de corte nuevo y el índice del tope ──────────────────
alter table public.ia_conexiones add column avisada_en timestamptz;
comment on column public.ia_conexiones.avisada_en is
  'Cuándo salió el correo «asistente conectado» a la persona (lo pone correo_cola_ok). null = aún en camino; si el aviso falla, la conexión se revoca con motivo sin_aviso. No se borra con la purga de la cola.';

-- 'sin_aviso' = el correo que avisa de la conexión no salió (lo pone privado.ia_aviso_fallido). Lo lee intranet/v4/assets/ia-conexiones.js.
alter table public.ia_conexiones drop constraint ia_conexiones_revocada_motivo_check;
alter table public.ia_conexiones add constraint ia_conexiones_revocada_motivo_check check (revocada_motivo in ('persona', 'admin', 'asistente', 'reuso_codigo', 'reuso_refresco',
                                                  'contrasena', 'permiso', 'apagado', 'usuario_inactivo', 'cliente', 'sin_aviso')) not valid;
alter table public.ia_conexiones validate constraint ia_conexiones_revocada_motivo_check;

-- el tope global cuenta las altas de la última hora (el de persona usa ia_conexiones_usuario)
create index ia_conexiones_creada on public.ia_conexiones (creada_en);

-- el nombre del asistente sale en un correo: sin caracteres de control ya al guardarlo (ia_cliente_guarda solo hace btrim)
alter table public.ia_clientes add constraint ia_clientes_nombre_limpio check (nombre !~ '[[:cntrl:]]') not valid;
alter table public.ia_clientes validate constraint ia_clientes_nombre_limpio;

-- ── 2. la cola gana su quinto ancla, atado a su clave ────────────────────────
alter table public.correos_cola
  add column ia_conexion_id uuid references public.ia_conexiones (id) on delete cascade;
comment on column public.correos_cola.ia_conexion_id is
  'Ancla del correo «asistente conectado» (MCP, 16-oct). Solo con la clave aviso_ia_conexion y vars vacío (CHECK correos_cola_ia_clave). CASCADE como las otras anclas: SET NULL rompería correos_cola_un_ancla.';
-- un aviso por conexión; cubre además la FK (mismo molde que correos_cola_reclamo_uno)
create unique index correos_cola_ia_conexion_uno on public.correos_cola (ia_conexion_id) where ia_conexion_id is not null;

alter table public.correos_cola drop constraint correos_cola_un_ancla;
alter table public.correos_cola add constraint correos_cola_un_ancla
  check (num_nonnulls(firma_id, contrato_id, factura_id, reclamo_id, ia_conexion_id) = 1) not valid;
alter table public.correos_cola validate constraint correos_cola_un_ancla;

alter table public.correos_cola add constraint correos_cola_ia_clave
  check ((ia_conexion_id is not null) = (clave = 'aviso_ia_conexion')
         and (ia_conexion_id is null or vars = '{}'::jsonb)) not valid;
alter table public.correos_cola validate constraint correos_cola_ia_clave;

-- ── 3. la clave nueva en el CHECK que las lista (definición viva del 16-oct + la clave) ─────
alter table public.correo_plantillas drop constraint correo_plantillas_clave_check;
alter table public.correo_plantillas add constraint correo_plantillas_clave_check check (clave = any (array[
  'enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
  'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago','invitacion_portal','aviso_ia_conexion'])) not valid;
alter table public.correo_plantillas validate constraint correo_plantillas_clave_check;

-- La fila de plantilla (la cola la referencia por FK). Nace inactiva y sin texto: sale el texto de fábrica de plantillas_fabrica.ts.
-- El catálogo queda SELLADO tras el insert. Obligatorias del cuerpo (Seguridad #404, punto 4): el asistente, cuándo, el enlace
-- para quitarla y las dos frases «si no has sido tú» (aviso_en / aviso_es): un texto editado en Ajustes › Correo no puede quitar
-- el aviso de seguridad.
insert into public.correo_plantillas (clave, activa, variables, version)
values ('aviso_ia_conexion', false,
        '{"permitidas":["saludo_en","saludo_es","asistente","cuando","enlace","aviso_en","aviso_es"],"obligatorias":{"asunto":[],"cuerpo":["asistente","cuando","enlace","aviso_en","aviso_es"],"cuerpo_alt":[]},"variantes":1}'::jsonb, 0)
on conflict (clave) do nothing;

-- ── 4. reglas por clave (definición viva + la fila; soportada=false: correo_encolar la rechaza, solo entra por el trigger) ──
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
      ('reclamo_pago',            'reclamo_id',  false,  24, 7::smallint,  3, 'reclamo_pago',   'Recordatorio de pago',         array[]::text[]),
      ('invitacion_portal',       'reclamo_id',  false,  72, 7::smallint,  3, 'invitacion_portal', 'Invitación al portal',      array[]::text[]),
      ('aviso_ia_conexion',       'ia_conexion_id', false, 24, 2::smallint, 5, 'aviso_ia_conexion', 'Asistente conectado',     array[]::text[])
    ) as r(clave, ancla, soportada, tope_horas, prioridad, max_intentos, via, asunto_registro, editables)
   where r.clave = p_clave
$$;

-- ── 5. a quién se avisa: el correo con el que entra la persona, al enviar, en UN sitio ───────
-- INVOKER: la llaman correo_cola_reclamar e ia_aviso_conexion_datos (DEFINER de postgres), que ya pueden leer auth.users.
-- Solo el correo: nada más de Auth. Misma forma de correo válido que _correo_cola_destino y _reclamo_pago_destino.
create or replace function privado.ia_aviso_destino(p_conexion uuid)
returns text language sql stable security invoker set search_path = '' as $$
  select case when s.e ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and char_length(s.e) <= 254 then s.e end
    from (select lower(btrim(u.email)) as e
            from public.ia_conexiones c join auth.users u on u.id = c.usuario_id
           where c.id = p_conexion) s
$$;
alter function privado.ia_aviso_destino(uuid) owner to postgres;

-- el nombre que el super admin le puso al asistente, por la regla de las notas de correo (sin enlaces, correos ni números largos;
-- hasta 60, el tope de ia_cliente_guarda). Si no la pasa, null: el correo dice solo el asistente de la lista cerrada.
create or replace function privado.ia_aviso_nombre(p_nombre text)
returns text language plpgsql stable security invoker set search_path = '' as $$
declare v text;
begin
  if p_nombre is null or char_length(p_nombre) > 60 or p_nombre ~ '[<>]' then return null; end if;
  begin
    v := public._nota_correo_limpia(p_nombre);
  exception when sqlstate '22023' then
    return null;
  end;
  return v;
end $$;
alter function privado.ia_aviso_nombre(text) owner to postgres;

-- ── 6. el alta: tope y aviso en la misma transacción ────────────────
create or replace function privado.ia_aviso_conexion()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- tope de altas (cuenta también las cortadas y esta misma fila, que ya está insertada: AFTER)
  perform pg_advisory_xact_lock(hashtext('ia_conexiones_tope_altas'));
  if (select count(*) from public.ia_conexiones c where c.usuario_id = new.usuario_id and c.creada_en > now() - interval '1 hour') > 5
     or (select count(*) from public.ia_conexiones c where c.creada_en > now() - interval '1 hour') > 20 then
    raise exception 'demasiadas_altas' using errcode = 'P0001',
      hint = 'Tope de altas de conexiones de asistentes: 5 por persona y 20 en toda la base por hora (cortadas incluidas).';
  end if;
  insert into public.correos_cola (clave, ia_conexion_id, vars, prioridad)
  values ('aviso_ia_conexion', new.id, '{}'::jsonb, (select r.prioridad from public._correo_cola_regla('aviso_ia_conexion') r));
  perform public._correos_cola_despierta();   -- no lanza: si no despierta, lo recoge el cron
  return null;
end $$;
alter function privado.ia_aviso_conexion() owner to postgres;

drop trigger if exists ia_conexiones_aviso on public.ia_conexiones;
create trigger ia_conexiones_aviso after insert on public.ia_conexiones
  for each row execute function privado.ia_aviso_conexion();

-- ── 7. el aviso no salió: la conexión se corta ────────────────
-- `error` es final para esta clave (correo_encolar, el único que reabre una fila en error, la rechaza) y `cancelado` no llega por la
-- vigencia (siempre verdadera), pero se cubre igual: cualquier camino que deje el aviso sin enviar corta la conexión.
create or replace function privado.ia_aviso_fallido()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform privado.ia_revoca(new.ia_conexion_id, 'sin_aviso');
  return null;
end $$;
alter function privado.ia_aviso_fallido() owner to postgres;

drop trigger if exists correos_cola_aviso_ia_fallido on public.correos_cola;
create trigger correos_cola_aviso_ia_fallido after update of estado on public.correos_cola
  for each row
  when (new.ia_conexion_id is not null and new.estado in ('error', 'cancelado') and old.estado is distinct from new.estado)
  execute function privado.ia_aviso_fallido();

-- ── 7b. y si la cola no corre, el puente corta igual (definición viva del 16-oct, md5 3c7260d0910a6216d5051f227d904845, + una regla) ──
-- Detrás de revocada y caducada, delante de «apagado»: cortar es seguro también con la IA apagada. Las horas salen de la regla de la
-- clave (una sola fuente con la cola). create or replace conserva dueño (ia_puente_rol) y EXECUTE (solo ia_puente_rol).
create or replace function privado.ia_conexion_motivo(p_conexion uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare c public.ia_conexiones; a public.ia_ajustes; u jsonb; h integer;
begin
  select * into c from public.ia_conexiones where id = p_conexion;
  if c.id is null then return 'sin_conexion'; end if;
  if c.revocada_en is not null then return 'revocada'; end if;
  if c.expira_en <= now() then return 'caducada'; end if;
  if c.avisada_en is null then
    -- sin la regla de la clave (una redefinición futura que la pierda) se corta: sin tope no hay aviso que esperar (Seguridad, 2.ª vuelta)
    select r.tope_horas into h from public._correo_cola_regla('aviso_ia_conexion') r;
    if h is null or c.creada_en < now() - make_interval(hours => h) then
      perform privado.ia_revoca(c.id, 'sin_aviso'); return 'sin_aviso';
    end if;
  end if;
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
end $$;
-- su llamador nuevo: ia_conexion_motivo corre como ia_puente_rol y lee las horas de la regla (VALUES fijos, sin datos)
grant execute on function public._correo_cola_regla(text) to ia_puente_rol;

-- ── 8. reclamar: vigencia y destino del aviso (definición viva del 16-oct + las ramas ia_conexion_id) ──
create or replace function public.correo_cola_reclamar(p_max integer default 5)
returns table(id uuid, clave text, firma_id uuid, contrato_id uuid, factura_id uuid, vars jsonb, para text, prioridad smallint, intentos integer)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  -- el aviso de conexión es SIEMPRE vigente: sale aunque la conexión ya esté revocada
  update public.correos_cola q set estado = 'cancelado', error = 'hecho_no_vigente', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and not (case when q.ia_conexion_id is not null then true
                   when q.reclamo_id is not null then public._reclamo_pago_vigente(q.reclamo_id)
                   else public._correo_cola_vigente(q.clave, q.firma_id, q.contrato_id, q.factura_id) end);

  update public.correos_cola q set estado = 'error', error = 'tope_antiguedad', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and q.encolado_en + make_interval(hours => (select r.tope_horas from public._correo_cola_regla(q.clave) r)) < now();

  update public.correos_cola q set estado = 'error', error = 'sin_destinatario', reclamado_hasta = null
   where (q.estado = 'pendiente' or (q.estado = 'enviando' and q.reclamado_hasta <= now()))
     and (case when q.ia_conexion_id is not null then privado.ia_aviso_destino(q.ia_conexion_id)
               when q.reclamo_id is not null then public._reclamo_pago_destino(q.reclamo_id)
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
            case when q.ia_conexion_id is not null then privado.ia_aviso_destino(q.ia_conexion_id)
                 when q.reclamo_id is not null then public._reclamo_pago_destino(q.reclamo_id)
                 else public._correo_cola_destino(q.clave, q.firma_id, q.contrato_id, q.factura_id) end,
            q.prioridad, q.intentos;
end $$;

-- ── 9. cerrar: el aviso deja su rastro en la conexión y NO entra en correos_enviados (definición viva + la rama) ──
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
  returning q.clave, q.firma_id, q.contrato_id, q.factura_id, q.reclamo_id, q.ia_conexion_id into r;
  if not found then return false; end if;
  if r.ia_conexion_id is not null then
    update public.ia_conexiones c set avisada_en = now() where c.id = r.ia_conexion_id and c.avisada_en is null;
    return true;
  end if;
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

-- ── 10. lo que la edge necesita para componer UN aviso (y nada más). Filtra por clave: otro id de la cola no sirve ──
create or replace function public.ia_aviso_conexion_datos(p_cola uuid)
returns table (conexion_id uuid, para text, nombre text, asistente text, nombre_asistente text, creada_en timestamptz)
language sql stable security definer set search_path = '' as $$
  select c.id, privado.ia_aviso_destino(c.id), privado.ia_aviso_nombre(us.nombre), k.asistente, privado.ia_aviso_nombre(k.nombre), c.creada_en
    from public.correos_cola q
    join public.ia_conexiones c on c.id = q.ia_conexion_id
    join public.ia_clientes k on k.id = c.cliente_id
    left join public.usuarios us on us.user_id = c.usuario_id
   where q.id = p_cola and q.clave = 'aviso_ia_conexion'
$$;

-- ── 11. permisos: EXECUTE llega por PUBLIC y por los default privileges de Supabase si no se revoca ──
revoke all on function privado.ia_aviso_conexion(), privado.ia_aviso_fallido(), privado.ia_aviso_destino(uuid), privado.ia_aviso_nombre(text)
  from public, anon, authenticated, service_role;
revoke all on function public.ia_aviso_conexion_datos(uuid) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    execute 'revoke all on function privado.ia_aviso_conexion(), privado.ia_aviso_fallido(), privado.ia_aviso_destino(uuid),
               privado.ia_aviso_nombre(text), public.ia_aviso_conexion_datos(uuid) from lw_lector';
  end if;
end $$;
grant execute on function public.ia_aviso_conexion_datos(uuid) to service_role;
