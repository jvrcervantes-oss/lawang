-- destructivo-ok: solo construye. Columna nueva `tipo` (con default: las 3 filas existentes quedan 'reclamo_pago'), una UNIQUE (id, tipo), una FK compuesta nueva en correos_cola (validada aparte), tres CHECK que se SUSTITUYEN por otros mas anchos (se les añade 'invitacion_portal'; ninguna fila deja de cumplirlos), un indice que se sustituye por otro que lo cubre, una fila de plantilla y funciones nuevas o redefinidas. Ningun dato se borra ni se modifica. Reversion: supabase/reversion_invitacion_portal/REVERSION.sql.
-- ============================================================================
-- LAWANG — «INVITAR AL PORTAL» DESDE LA FICHA DE PARCELA — BASE DE DATOS (15-oct-2026)
-- ----------------------------------------------------------------------------
-- Pedido del owner (15-oct): en Proyectos → ficha de parcela, junto a «Reclamar pago», invitar a CADA comprador de la parcela
-- a su portal de cliente con un correo bilingüe EN/ES («aquí tienes la invitación…; revisa que todo está bien y, si no,
-- dínoslo»). Plan aprobado por el owner + revisión previa #357 (Seguridad + Base de datos), plegada aquí.
--
-- LA INVITACION NO CONCEDE NADA. Lleva al portal normal (/portal/) y el comprador entra con su correo: lo decide
-- portal_autoservicio() en el login, como siempre. Sin enlace mágico (caduca en ~1 h) y sin crear cuentas.
--
-- EL DATO TIENE UN DUEÑO (patrones_tecnicos.md):
--   · quién puede entrar al portal -> _portal_rechazo(email): UNA definición, la usan el login (portal_autoservicio) y esta
--                                    pantalla. Antes vivía escrita dentro de portal_autoservicio (y copiada en portal_elegible,
--                                    que NO se toca hoy: la prueba comprueba que sus tres rechazos coinciden con el helper).
--   · quién es comprador de la parcela -> contrato_compradores (la tabla con FK). Reclamar pago leía contratos.adq1_client_id,
--                                    una copia sin FK que dejaba fuera a los compradores de 15 contratos firmados (medido por
--                                    Base de datos el 15-oct): sus candidatos pasan a leer el rol 'adquiriente_1' de la tabla.
--   · el libro de envíos           -> reclamos_pago, con `tipo` ('reclamo_pago' | 'invitacion_portal'). NO tabla nueva: una
--                                    tabla nueva obligaba a un quinto ancla en correos_cola y a tocar correo_cola_reclamar y
--                                    correo_cola_ok, que mueven también los enlaces de firma. El nombre queda corto: lo dicen
--                                    los comentarios. Si llega un tercer tipo, tabla propia (envios_parcela) en dos entregas.
--   · el tipo está DOS veces (reclamos_pago.tipo y correos_cola.clave): la FK compuesta (reclamo_id, clave) → (id, tipo) las
--     obliga a coincidir. Sin ella, una funcion que insertara sin tipo apuntaria una invitacion como reclamo sin un error.
--   · la nota del admin            -> _nota_correo_limpia(): UNA regla para Reclamar pago y para la invitación (antes la
--                                    regex estaba copiada en dos funciones y la edge no la repetía). La edge la repite en espejo.
--
-- LO QUE SE COMPRUEBA AL ENVIAR, NO SOLO AL ENCOLAR (Seguridad #357, punto 1): el correo se resuelve al enviar desde la ficha
-- viva del cliente (_reclamo_pago_destino). Si la ficha cambia mientras la fila espera en la cola, la rama 'invitacion_portal'
-- de _reclamo_pago_vigente vuelve a pasar el candidato por la regla entera (sigue siendo comprador, correo válido, no del
-- equipo, no revocado, no repetido). Si no cuadra, la cola la cancela como hecho_no_vigente.
--
-- TOPES (Seguridad #357, punto 3): el formulario del portal tiene un techo GLOBAL de 30 enlaces/hora (portal_enlace_freno) y,
-- al frenarse, contesta «enviado» sin enviar. Para que una mañana invitando un proyecto entero no lo llene: 15 invitaciones
-- reales por hora en TODA la base (no por empresa: hay 2), contadas bajo un candado fijo. «Enviarme una prueba»: 5 por hora
-- por persona, en los dos correos (gasta la cuota del buzón SMTP).
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado):
--   invitacion_portal_destinatarios / _encolar / _historial / _prueba <- pantalla de la ficha de parcela (authenticated; por dentro
--                                                                       es_admin_de(empresa del proyecto de la parcela))
--   invitacion_portal_datos                                            <- edge cola-correos-envio y envia-correo (service_role)
--   _portal_rechazo, _nota_correo_limpia, _invitacion_portal_candidatos <- las funciones de arriba, portal_autoservicio y
--                                                                       _reclamo_pago_vigente. Sin grants para nadie.
-- ============================================================================

set local lock_timeout = '5s';

-- ── 1. quién puede entrar al portal: UNA definición ─────────────────────────────
-- Mismos tres rechazos, mismo orden y mismas palabras que tenía portal_autoservicio (su log y portal-acceso las leen).
-- INVOKER y sin grants: solo la llaman funciones DEFINER del propietario. Con EXECUTE para authenticated (los compradores
-- del portal lo son) serviría para preguntar qué correos son del equipo o están revocados: justo lo que la respuesta uniforme
-- de portal-acceso existe para impedir.
create or replace function public._portal_rechazo(p_email text)
returns text language sql stable security invoker set search_path = '' as $$
  select case
           when e.v !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then 'email_invalido'
           when exists (select 1 from public.usuarios u where lower(btrim(u.email)) = e.v) then 'equipo'
           when exists (select 1 from public.portal_accesos pa where pa.email = e.v and not pa.activo) then 'revocado'
         end
    from (select lower(btrim(coalesce(p_email, ''))) as v) e
$$;
comment on function public._portal_rechazo(text) is
  'Por qué un correo NO puede entrar al portal: email_invalido | equipo | revocado | null (puede). Una sola definición: la usan portal_autoservicio (login) y la invitación desde la ficha de parcela. Sin grants (oráculo de correos si se abre).';

-- portal_autoservicio: los tres IF pasan a ser una llamada. Todo lo demás, letra a letra igual que 20260908013953.
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
  v_rechazo text;
begin
  v_rechazo := public._portal_rechazo(v_email);
  if v_rechazo is not null then
    return jsonb_build_object('elegible', false, 'motivo', v_rechazo);
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

-- ── 2. la nota del admin: UNA regla ──────────────────────────────────────────
-- Texto plano de hasta 300 caracteres. Fuera: @, http, www, cualquier cosa con forma de dominio (Gmail la convierte en enlace),
-- 6 dígitos seguidos o más (cuentas, teléfonos: el fraude típico del sector) y caracteres de control. Devuelve la nota
-- normalizada (o null si viene vacía); si no vale, error con hint nota_invalida. Espejo en envia-correo/plantillas_fabrica.ts.
create or replace function public._nota_correo_limpia(p_nota text)
returns text language plpgsql immutable security invoker set search_path = '' as $$
declare v text;
begin
  v := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '[[:space:]]+', ' ', 'g')), '');
  if v is not null and (char_length(v) > 300 or v ~* '(http|www\.|@)' or v ~* '[a-z0-9-]\.[a-z]{2,}' or v ~ '[0-9]{6,}'
                        or v ~ '[[:cntrl:]]') then
    raise exception 'La nota admite hasta 300 caracteres de texto, sin enlaces, direcciones de correo ni números largos.'
      using errcode = '22023', hint = 'nota_invalida';
  end if;
  return v;
end $$;

-- ── 3. el libro gana su tipo, atado a la clave de la cola ─────────────────────
alter table public.reclamos_pago
  add column tipo text not null default 'reclamo_pago' check (tipo in ('reclamo_pago', 'invitacion_portal'));
alter table public.reclamos_pago add constraint reclamos_pago_id_tipo_uq unique (id, tipo);
alter table public.correos_cola
  add constraint correos_cola_reclamo_tipo_fk foreign key (reclamo_id, clave)
      references public.reclamos_pago (id, tipo) on delete cascade not valid;
alter table public.correos_cola validate constraint correos_cola_reclamo_tipo_fk;

comment on table public.reclamos_pago is
  'Libro de los correos que se mandan desde la ficha de parcela (8-oct «Reclamar pago»; 15-oct «Invitar al portal», columna tipo). Una fila por persona y pulsación: quién lo pidió (de la sesión, nunca del navegador), cuándo, a quién (ids; el correo vive en clients) y la nota. El estado del envío lo da correos_cola vía cola_id. Solo se escribe desde reclamo_pago_encolar/_prueba e invitacion_portal_encolar/_prueba. prueba=true: «Enviarme una prueba» (el destinatario es creado_por, nunca el comprador).';
comment on column public.reclamos_pago.tipo is
  'reclamo_pago | invitacion_portal. Debe coincidir con correos_cola.clave de su fila (FK compuesta correos_cola_reclamo_tipo_fk). Toda lectura del libro filtra por tipo.';
comment on column public.correos_cola.reclamo_id is
  'Ancla de los correos de la ficha de parcela (libro reclamos_pago, cualquiera de sus tipos). Con clave forma la FK compuesta al (id, tipo) del libro.';

drop index if exists public.reclamos_pago_unidad_idx;
create index reclamos_pago_unidad_tipo_idx on public.reclamos_pago (unidad_id, tipo, creado_en desc);
create index reclamos_pago_contrato_idx on public.reclamos_pago (contrato_id);
create index reclamos_pago_cola_idx on public.reclamos_pago (cola_id);
create index reclamos_pago_tipo_creado_idx on public.reclamos_pago (tipo, creado_en desc) where not prueba;

-- ── 4. la clave nueva en los CHECK que la listan (definiciones vivas medidas el 15-oct + la clave) ─────
alter table public.correo_plantillas drop constraint correo_plantillas_clave_check;
alter table public.correo_plantillas add constraint correo_plantillas_clave_check check (clave = any (array[
  'enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
  'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago','invitacion_portal'])) not valid;
alter table public.correo_plantillas validate constraint correo_plantillas_clave_check;

alter table public.correos_enviados drop constraint correos_enviados_via_check;
alter table public.correos_enviados add constraint correos_enviados_via_check check (via = any (array[
  'manual','enlace_firma','firma','proforma','factura','factura_auto','aviso_anulacion','copia_firmada','reclamo_pago',
  'invitacion_portal'])) not valid;
alter table public.correos_enviados validate constraint correos_enviados_via_check;
alter table public.correos_enviados drop constraint correos_enviados_plantilla_check;
alter table public.correos_enviados add constraint correos_enviados_plantilla_check check (
  (plantilla is null and plantilla_version is null)
  or (plantilla is not null and plantilla_version is not null
      and plantilla = any (array['enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion',
                                 'factura_primer_hito','proforma_total','factura_vencimiento','reclamo_pago','invitacion_portal'])
      and plantilla_version ~ '^(v[0-9]{1,6}|f:[0-9a-f]{8})$')) not valid;
alter table public.correos_enviados validate constraint correos_enviados_plantilla_check;

-- La fila de plantilla (la cola la referencia por FK). Nace inactiva y sin texto, como reclamo_pago en producción (medido
-- 15-oct): sale el texto de fábrica de plantillas_fabrica.ts. OJO: el catálogo queda SELLADO tras el insert, por eso va
-- completo (cuerpo_alt y variantes incluidos) y casa con el texto de fábrica.
insert into public.correo_plantillas (clave, activa, variables, version)
values ('invitacion_portal', false,
        '{"permitidas":["saludo_en","saludo_es","parcela","proyecto","nota","enlace"],"obligatorias":{"asunto":[],"cuerpo":["enlace"],"cuerpo_alt":[]},"variantes":1}'::jsonb, 0)
on conflict (clave) do nothing;

-- ── 5. reglas por clave: la fila nueva (soportada=false: correo_encolar la rechaza; solo entra por invitacion_portal_encolar) ──
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
      ('invitacion_portal',       'reclamo_id',  false,  72, 7::smallint,  3, 'invitacion_portal', 'Invitación al portal',      array[]::text[])
    ) as r(clave, ancla, soportada, tope_horas, prioridad, max_intentos, via, asunto_registro, editables)
   where r.clave = p_clave
$$;

-- ── 6. Reclamar pago: el comprador sale de contrato_compradores (no de la copia adq1_client_id) ─────────
-- Misma salida que 20261010070000; solo cambia de dónde sale el titular: rol 'adquiriente_1' de contrato_compradores
-- (FK, 0 repetidos por contrato medido el 15-oct). Donde adq1_client_id estaba relleno coincidía siempre (0 discrepancias).
create or replace function public._reclamo_pago_candidatos(p_unidad uuid)
returns table (contrato_id uuid, client_id uuid, nombre text, email text, idioma text, seleccionable boolean, motivo text,
               empresa_nombre text, sociedad_clave text, sociedad_razon text, parcela text, proyecto text, orden int)
language sql stable security definer set search_path = '' as $$
  with b as (
    select c.id as cid, cc.client_id as cl, c.fecha_firma as ffirma, c.created_at as ccreado,
           nullif(btrim(c.datos_fields->>'sociedad_firmante'), '') as soc_c,
           k.full_name as k_nombre, lower(btrim(k.email)) as k_email, k.idioma_comunicacion as k_idioma,
           e.nombre as e_nombre, e.sociedad_clave as soc_p, u.codigo as u_codigo, p.nombre as p_nombre
      from public.unidades u
      join public.proyectos p on p.id = u.proyecto_id
      left join public.empresas e on e.clave = p.empresa
      join public.contratos c on c.liberado_en is null and c.proyecto_id = u.proyecto_id
                             and (c.unidad_id = u.id or c.id = u.contrato_id)
      left join public.contrato_compradores cc on cc.contrato_id = c.id and cc.rol = 'adquiriente_1'
      left join public.clients k on k.id = cc.client_id
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

-- ── 7. Invitar al portal: los candidatos ─────────────────────────────────────
-- Una fila por PERSONA compradora (cualquier rol adquiriente_N) de los contratos vivos de la parcela. Su contrato de
-- referencia: el más reciente (firmado primero). motivo nulo = se le puede invitar. Firmado o no es un dato, no bloquea:
-- el portal tampoco lo exige. Además de _portal_rechazo: una cuenta de Auth del equipo con OTRO correo en usuarios (lo
-- mismo que portal-acceso mira por user_id) y dos personas con el mismo correo en la parcela (le llega a la primera).
create or replace function public._invitacion_portal_candidatos(p_unidad uuid)
returns table (contrato_id uuid, contrato_numero text, client_id uuid, nombre text, email text, rol text, firmado boolean,
               seleccionable boolean, motivo text, empresa_nombre text, parcela text, proyecto text)
language sql stable security definer set search_path = '' as $$
  with b as (
    select c.id as cid, c.numero as cnum, c.fecha_firma as ffirma, c.created_at as ccreado, cc.client_id as cl, cc.rol,
           k.full_name as k_nombre, lower(btrim(k.email)) as k_email,
           e.nombre as e_nombre, u.codigo as u_codigo, p.nombre as p_nombre
      from public.unidades u
      join public.proyectos p on p.id = u.proyecto_id
      left join public.empresas e on e.clave = p.empresa
      join public.contratos c on c.liberado_en is null and c.proyecto_id = u.proyecto_id
                             and (c.unidad_id = u.id or c.id = u.contrato_id)
      join public.contrato_compradores cc on cc.contrato_id = c.id and cc.rol like 'adquiriente\_%'
      left join public.clients k on k.id = cc.client_id
     where u.id = p_unidad),
  uno as (   -- una fila por persona: su contrato de referencia
    select distinct on (b.cl) b.*
      from b order by b.cl, (b.ffirma is not null) desc, b.ffirma desc nulls last, b.ccreado desc, b.cid),
  m as (
    select uno.*,
           case when uno.k_nombre is null then 'sin_ficha'
                when uno.k_email is null or char_length(uno.k_email) > 254
                     or uno.k_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then 'sin_email'
                else case public._portal_rechazo(uno.k_email)
                       when 'email_invalido' then 'sin_email'
                       when 'equipo' then 'correo_equipo'
                       when 'revocado' then 'acceso_revocado'
                       else case when exists (select 1 from auth.users au join public.usuarios us on us.user_id = au.id
                                               where lower(btrim(au.email)) = uno.k_email) then 'correo_equipo' end
                     end
           end as mot0,
           row_number() over (partition by uno.k_email order by uno.k_nombre nulls last, uno.cl) as rn_email
      from uno)
  select m.cid, m.cnum, m.cl, m.k_nombre, m.k_email, m.rol, (m.ffirma is not null),
         (coalesce(m.mot0, case when m.k_email is not null and m.rn_email > 1 then 'correo_repetido' end) is null),
         coalesce(m.mot0, case when m.k_email is not null and m.rn_email > 1 then 'correo_repetido' end),
         m.e_nombre, m.u_codigo, m.p_nombre
    from m
$$;

-- ── 8. la cola sabe si cada fila sigue vigente: rama por tipo ────────────────
-- reclamo_pago: la condición de 20261010070000 con el titular sacado de contrato_compradores (ver §6).
-- invitacion_portal: la persona sigue siendo invitable en esa parcela AHORA (regla entera, sobre la ficha viva). Una prueba
-- (va a quien la pidió) vale mientras la parcela exista.
create or replace function public._reclamo_pago_vigente(p_reclamo uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case
             when r.tipo = 'invitacion_portal' then
               r.prueba or exists (select 1 from public._invitacion_portal_candidatos(r.unidad_id) x
                                    where x.client_id = r.client_id and x.seleccionable)
             else exists (
               select 1 from public.unidades u
                 join public.proyectos p on p.id = u.proyecto_id
                 join public.empresas e on e.clave = p.empresa
                 join public.contratos c on c.id = r.contrato_id and c.liberado_en is null and c.proyecto_id = u.proyecto_id
                                        and (c.unidad_id = u.id or c.id = u.contrato_id) and c.fecha_firma is not null
                 join public.contrato_compradores cc on cc.contrato_id = c.id and cc.rol = 'adquiriente_1' and cc.client_id = r.client_id
                where u.id = r.unidad_id and e.sociedad_clave is not null
                  and nullif(btrim(c.datos_fields->>'sociedad_firmante'), '') = e.sociedad_clave)
           end
      from public.reclamos_pago r where r.id = p_reclamo), false)
$$;

-- ── 9. Reclamar pago: sus lecturas filtran su tipo; la nota y la prueba, con la regla común ──────────
create or replace function public.reclamo_pago_datos(p_cola uuid)
returns table (reclamo_id uuid, para text, nombre text, idioma text, parcela text, proyecto text,
               empresa_razon text, sociedad_clave text, nota text, contrato_id uuid)
language sql stable security definer set search_path = '' as $$
  select r.id, public._reclamo_pago_destino(r.id), k.full_name, k.idioma_comunicacion, u.codigo, p.nombre,
         s.razon, s.clave, r.nota, r.contrato_id
    from public.correos_cola q
    join public.reclamos_pago r on r.id = q.reclamo_id and r.tipo = 'reclamo_pago'
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
           where r.unidad_id = p_unidad and r.tipo = 'reclamo_pago' and r.client_id = c.client_id and not r.prueba order by r.creado_en desc limit 1),
         (select case when q.id is null then 'archivado'
                      when q.estado in ('pendiente', 'enviando') then 'pendiente'
                      when q.estado = 'ok' then 'enviado' else q.estado end
            from public.reclamos_pago r left join public.correos_cola q on q.id = r.cola_id
           where r.unidad_id = p_unidad and r.tipo = 'reclamo_pago' and r.client_id = c.client_id and not r.prueba order by r.creado_en desc limit 1),
         (select max(q.enviado_en) from public.reclamos_pago r join public.correos_cola q on q.id = r.cola_id and q.estado = 'ok'
           where r.unidad_id = p_unidad and r.tipo = 'reclamo_pago' and r.client_id = c.client_id and not r.prueba),
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

  -- 3. nota: la regla común (texto plano, sin enlaces, correos ni números largos)
  v_nota := public._nota_correo_limpia(p_nota);

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
                where r.unidad_id = p_unidad and r.tipo = 'reclamo_pago' and r.client_id = v_id and not r.prueba
                  and r.creado_en > clock_timestamp() - interval '10 seconds') then
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
    insert into public.reclamos_pago (unidad_id, contrato_id, client_id, nota, creado_por, creado_por_uid, tipo)
    values (p_unidad, v_c.contrato_id, v_id, v_nota, v_quien, (select auth.uid()), 'reclamo_pago')
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
   where r.unidad_id = p_unidad and r.tipo = 'reclamo_pago'
   order by r.creado_en desc, r.id
   limit 200;
end $$;

-- Prueba: el mismo correo, solo para quien pulsa (ver 20261010070000). Cambia: nota con la regla común, tipo explícito y
-- tope de 5 pruebas por hora y persona (gastan la cuota del buzón SMTP).
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

  v_nota := public._nota_correo_limpia(p_nota);

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

  perform pg_advisory_xact_lock(hashtextextended('correo_parcela_prueba:' || v_quien, 0));
  if (select count(*) from public.reclamos_pago r
       where r.prueba and r.tipo = 'reclamo_pago' and r.creado_por = v_quien and r.creado_en > now() - interval '1 hour') >= 5 then
    raise exception 'Ya te has mandado 5 pruebas en la última hora. Espera un poco.' using errcode = '22023', hint = 'tope_pruebas';
  end if;

  insert into public.reclamos_pago (unidad_id, contrato_id, client_id, nota, creado_por, creado_por_uid, prueba, tipo)
  values (p_unidad, v_c.contrato_id, v_c.client_id, v_nota, v_quien, (select auth.uid()), true, 'reclamo_pago')
  returning id into v_rec;
  insert into public.correos_cola (clave, reclamo_id, prioridad)
  values ('reclamo_pago', v_rec, (select r.prioridad from public._correo_cola_regla('reclamo_pago') r))
  returning id into v_cola;
  update public.reclamos_pago set cola_id = v_cola where id = v_rec;
  perform public._correos_cola_despierta();
  return regexp_replace(v_quien, '^(.).*(@.*)$', '\1***\2');
end $$;

-- ── 10. Invitar al portal: lo que pide la pantalla ───────────────────────────
-- Las mismas columnas que reclamo_pago_destinatarios donde significan lo mismo (ultimo_reclamo_en/ultimo_estado = última
-- invitación): el núcleo de pantalla (correo-parcela.js) es uno. ultimo_acceso: la última entrada al portal de ESA ficha
-- (portal_accesos por client_id, con FK; nunca cruzando por correo).
create or replace function public.invitacion_portal_destinatarios(p_unidad uuid)
returns table (contrato_id uuid, contrato_numero text, client_id uuid, nombre text, email_oculto text, rol text, firmado boolean,
               seleccionable boolean, motivo text, parcela text, proyecto text,
               ultimo_reclamo_en timestamptz, ultimo_estado text, ultimo_acceso timestamptz)
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
  select c.contrato_id, c.contrato_numero, c.client_id, c.nombre,
         regexp_replace(c.email, '^(.).*(@.*)$', '\1***\2'),
         c.rol, c.firmado, c.seleccionable, c.motivo, c.parcela, c.proyecto,
         (select r.creado_en from public.reclamos_pago r
           where r.unidad_id = p_unidad and r.tipo = 'invitacion_portal' and r.client_id = c.client_id and not r.prueba
           order by r.creado_en desc limit 1),
         (select case when q.id is null then 'archivado'
                      when q.estado in ('pendiente', 'enviando') then 'pendiente'
                      when q.estado = 'ok' then 'enviado' else q.estado end
            from public.reclamos_pago r left join public.correos_cola q on q.id = r.cola_id
           where r.unidad_id = p_unidad and r.tipo = 'invitacion_portal' and r.client_id = c.client_id and not r.prueba
           order by r.creado_en desc limit 1),
         (select max(pa.ultimo_acceso) from public.portal_accesos pa where pa.client_id = c.client_id and pa.activo)
    from public._invitacion_portal_candidatos(p_unidad) c
   order by c.seleccionable desc, c.nombre nulls last, c.client_id;
end $$;

create or replace function public.invitacion_portal_encolar(p_unidad uuid, p_clients uuid[], p_nota text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  c_tope_hora constant int := 15;   -- invitaciones reales por hora en TODA la base (techo global del portal: 30/h)
  v_emp   text;
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
  select p.empresa into v_emp
    from public.unidades u join public.proyectos p on p.id = u.proyecto_id where u.id = p_unidad;
  v_hay := found;
  if not public.es_admin_de(v_emp) then
    raise exception 'No tienes permiso sobre esta parcela.' using errcode = '42501', hint = 'sin_permiso';
  end if;
  if not v_hay then
    raise exception 'La parcela no existe.' using errcode = '22023', hint = 'unidad_no_existe';
  end if;

  -- 2. lote: sin repetidos, entre 1 y 10
  select coalesce(array_agg(x order by x), '{}') into v_ids from (select distinct u from unnest(coalesce(p_clients, '{}')) u where u is not null) d(x);
  if cardinality(v_ids) = 0 then
    raise exception 'Marca al menos una persona.' using errcode = '22023', hint = 'sin_destinatarios';
  end if;
  if cardinality(v_ids) > 10 then
    raise exception 'Como máximo 10 personas por envío.' using errcode = '22023', hint = 'demasiados_destinatarios';
  end if;

  -- 3. nota: la regla común
  v_nota := public._nota_correo_limpia(p_nota);

  -- 4. tope global por hora (candado fijo: dos admins de dos empresas cuentan en serie) y anti doble clic por persona
  perform pg_advisory_xact_lock(hashtextextended('invitacion_portal:tope_hora', 0));
  if (select count(*) from public.reclamos_pago r
       where r.tipo = 'invitacion_portal' and not r.prueba and r.creado_en > now() - interval '1 hour') + cardinality(v_ids) > c_tope_hora then
    raise exception 'Ya se han enviado muchas invitaciones en la última hora: espera un poco para que a todos les llegue el enlace de acceso.'
      using errcode = '22023', hint = 'tope_hora';
  end if;
  foreach v_id in array v_ids loop
    perform pg_advisory_xact_lock(hashtextextended('invitacion_portal:' || p_unidad::text || ':' || v_id::text, 0));
  end loop;

  -- 5. cada persona debe ser invitable en ESTA parcela; si una no cuadra, se rechaza el lote entero
  foreach v_id in array v_ids loop
    select * into v_c from public._invitacion_portal_candidatos(p_unidad) c where c.client_id = v_id;
    if not found then
      raise exception 'Una de las personas marcadas no es compradora de esta parcela: no se envía nada.'
        using errcode = '22023', hint = 'destinatario_ajeno_a_la_parcela';
    end if;
    if not v_c.seleccionable then
      raise exception 'Una de las personas marcadas ya no se puede invitar al portal: no se envía nada.'
        using errcode = '22023', hint = v_c.motivo;
    end if;
    if exists (select 1 from public.reclamos_pago r
                where r.unidad_id = p_unidad and r.tipo = 'invitacion_portal' and r.client_id = v_id and not r.prueba
                  and r.creado_en > clock_timestamp() - interval '10 seconds') then
      raise exception 'Ya se ha invitado a una de las personas marcadas hace unos segundos: no se repite.'
        using errcode = '22023', hint = 'doble_clic';
    end if;
  end loop;

  -- 6. quien lo pide: de la sesion
  v_quien := lower(coalesce(nullif(btrim(coalesce(auth.email(), '')), ''),
                            (select u.email from public.usuarios u where u.user_id = (select auth.uid()))));
  if v_quien is null then
    raise exception 'No se pudo identificar quién envía la invitación.' using errcode = '42501', hint = 'sin_identidad';
  end if;

  -- 7. libro + cola (un correo por persona, sin CC)
  foreach v_id in array v_ids loop
    select * into v_c from public._invitacion_portal_candidatos(p_unidad) c where c.client_id = v_id;
    insert into public.reclamos_pago (unidad_id, contrato_id, client_id, nota, creado_por, creado_por_uid, tipo)
    values (p_unidad, v_c.contrato_id, v_id, v_nota, v_quien, (select auth.uid()), 'invitacion_portal')
    returning id into v_rec;
    insert into public.correos_cola (clave, reclamo_id, prioridad)
    values ('invitacion_portal', v_rec, (select r.prioridad from public._correo_cola_regla('invitacion_portal') r))
    returning id into v_cola;
    update public.reclamos_pago set cola_id = v_cola where id = v_rec;
    v_out := v_out || jsonb_build_object('invitacion_id', v_rec, 'client_id', v_id);
  end loop;

  perform public._correos_cola_despierta();
  return jsonb_build_object('n', cardinality(v_ids), 'invitaciones', v_out);
end $$;

create or replace function public.invitacion_portal_historial(p_unidad uuid)
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
   where r.unidad_id = p_unidad and r.tipo = 'invitacion_portal'
   order by r.creado_en desc, r.id
   limit 200;
end $$;

-- Prueba: el mismo correo, solo para quien pulsa; los nombres de parcela y proyecto, del primer invitable de la parcela.
create or replace function public.invitacion_portal_prueba(p_unidad uuid, p_nota text default null)
returns text language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_emp   text;
  v_hay   boolean;
  v_c     record;
  v_nota  text;
  v_quien text;
  v_rec   uuid;
  v_cola  uuid;
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

  v_nota := public._nota_correo_limpia(p_nota);

  select * into v_c from public._invitacion_portal_candidatos(p_unidad) c
   where c.seleccionable order by c.client_id limit 1;
  if not found then
    raise exception 'Esta parcela no tiene a nadie a quien se pueda invitar: no se puede componer la prueba.'
      using errcode = '22023', hint = 'sin_contrato_valido';
  end if;

  v_quien := lower(coalesce(nullif(btrim(coalesce(auth.email(), '')), ''),
                            (select u.email from public.usuarios u where u.user_id = (select auth.uid()))));
  if v_quien is null or v_quien !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or char_length(v_quien) > 254 then
    raise exception 'No se pudo identificar a quién enviar la prueba.' using errcode = '42501', hint = 'sin_identidad';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('correo_parcela_prueba:' || v_quien, 0));
  if (select count(*) from public.reclamos_pago r
       where r.prueba and r.tipo = 'invitacion_portal' and r.creado_por = v_quien and r.creado_en > now() - interval '1 hour') >= 5 then
    raise exception 'Ya te has mandado 5 pruebas en la última hora. Espera un poco.' using errcode = '22023', hint = 'tope_pruebas';
  end if;

  insert into public.reclamos_pago (unidad_id, contrato_id, client_id, nota, creado_por, creado_por_uid, prueba, tipo)
  values (p_unidad, v_c.contrato_id, v_c.client_id, v_nota, v_quien, (select auth.uid()), true, 'invitacion_portal')
  returning id into v_rec;
  insert into public.correos_cola (clave, reclamo_id, prioridad)
  values ('invitacion_portal', v_rec, (select r.prioridad from public._correo_cola_regla('invitacion_portal') r))
  returning id into v_cola;
  update public.reclamos_pago set cola_id = v_cola where id = v_rec;
  perform public._correos_cola_despierta();
  return regexp_replace(v_quien, '^(.).*(@.*)$', '\1***\2');
end $$;

-- Lo que la edge necesita para componer UNA invitación (y nada más). Filtra clave Y tipo: el id de una fila de la cola de
-- reclamos no sirve para componer una invitación, ni al revés.
create or replace function public.invitacion_portal_datos(p_cola uuid)
returns table (invitacion_id uuid, para text, nombre text, parcela text, proyecto text, nota text, contrato_id uuid)
language sql stable security definer set search_path = '' as $$
  select r.id, public._reclamo_pago_destino(r.id), k.full_name, u.codigo, p.nombre, r.nota, r.contrato_id
    from public.correos_cola q
    join public.reclamos_pago r on r.id = q.reclamo_id and r.tipo = 'invitacion_portal'
    join public.clients k on k.id = r.client_id
    join public.unidades u on u.id = r.unidad_id
    join public.proyectos p on p.id = u.proyecto_id
   where q.id = p_cola and q.clave = 'invitacion_portal'
$$;

-- ── 11. permisos: EXECUTE llega por PUBLIC y por los default privileges de Supabase si no se revoca ──
revoke all on function public._portal_rechazo(text), public._nota_correo_limpia(text), public._invitacion_portal_candidatos(uuid),
  public._reclamo_pago_candidatos(uuid), public._reclamo_pago_vigente(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.reclamo_pago_destinatarios(uuid), public.reclamo_pago_encolar(uuid, uuid[], text), public.reclamo_pago_historial(uuid),
  public.reclamo_pago_prueba(uuid, text),
  public.invitacion_portal_destinatarios(uuid), public.invitacion_portal_encolar(uuid, uuid[], text), public.invitacion_portal_historial(uuid),
  public.invitacion_portal_prueba(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.reclamo_pago_datos(uuid), public.invitacion_portal_datos(uuid) from public, anon, authenticated;
-- lw_lector (rol de solo lectura de la viva) no existe en una rama nueva: se le revoca solo donde está.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    execute 'revoke all on function public._portal_rechazo(text), public._nota_correo_limpia(text), public._invitacion_portal_candidatos(uuid),
               public._reclamo_pago_candidatos(uuid), public._reclamo_pago_vigente(uuid), public.reclamo_pago_destinatarios(uuid),
               public.reclamo_pago_encolar(uuid, uuid[], text), public.reclamo_pago_historial(uuid), public.reclamo_pago_prueba(uuid, text),
               public.invitacion_portal_destinatarios(uuid), public.invitacion_portal_encolar(uuid, uuid[], text),
               public.invitacion_portal_historial(uuid), public.invitacion_portal_prueba(uuid, text), public.reclamo_pago_datos(uuid),
               public.invitacion_portal_datos(uuid) from lw_lector';
  end if;
end $$;
grant execute on function public.reclamo_pago_destinatarios(uuid), public.reclamo_pago_encolar(uuid, uuid[], text), public.reclamo_pago_historial(uuid),
  public.reclamo_pago_prueba(uuid, text),
  public.invitacion_portal_destinatarios(uuid), public.invitacion_portal_encolar(uuid, uuid[], text), public.invitacion_portal_historial(uuid),
  public.invitacion_portal_prueba(uuid, text)
  to authenticated;
grant execute on function public.reclamo_pago_datos(uuid), public.invitacion_portal_datos(uuid) to service_role;
