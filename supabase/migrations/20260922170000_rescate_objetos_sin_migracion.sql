-- ============================================================================
-- RESCATE: objetos de producción que NINGUNA migración del repo creaba
-- 22-sep-2026 · saneo de la intranet (revisión previa de Datos)
-- ----------------------------------------------------------------------------
-- Al comparar el catálogo vivo (pg_proc, pg_class, pg_trigger) con
-- supabase/migrations/ salieron 21 objetos que existen en producción y cuyo
-- CREATE no está en ningún fichero: nacieron desde el dashboard o por
-- execute_sql antes de que el repo guardase migraciones (agosto de 2026).
-- Su único texto estaba en contracts/sql/*.sql — copias de referencia que
-- desde hoy pasan a ser punteros — o en ningún sitio (facturas, unidades,
-- contrato_firmas, contrato_compradores, contratos_diseno, correcciones_datos,
-- plantillas_contrato).
--
-- Este fichero es el DDL tal como está HOY en producción, generado desde el
-- catálogo (format_type, pg_get_constraintdef, pg_get_indexdef, pg_policies,
-- pg_get_functiondef, pg_get_triggerdef). Se registra en
-- supabase_migrations.schema_migrations como APLICADA sin ejecutarla: no
-- cambia nada en la base, deja el repo con la definición de todo lo que vive
-- en ella. Ojo en un replay desde cero: por su número va DESPUÉS de las
-- migraciones que hacen ALTER sobre estas tablas, así que un `db reset`
-- necesitaría reordenarla como baseline. Hoy el objetivo es que el invariante
-- «objeto sin migración» de tools/salud_lawang.py quede en verde con verdad.
-- ============================================================================

-- ── Tablas ──────────────────────────────────────────────────────────────────

create table if not exists public.facturas (
  id uuid not null default gen_random_uuid(),
  numero text,
  sociedad text not null,
  cliente_nombre text,
  proyecto_nombre text,
  contrato_numero text,
  total numeric,
  moneda text,
  fecha_emision date,
  datos jsonb not null default '{}'::jsonb,
  anulada boolean not null default false,
  created_at timestamp with time zone not null default now(),
  creado_por text default auth.email(),
  tipo text not null default 'factura'::text,
  contrato_id uuid,
  enviada boolean not null default false,
  fecha_envio timestamp with time zone,
  justificante_path text,
  client_id uuid,
  proyecto_id uuid,
  justificantes jsonb not null default '[]'::jsonb
);
alter table public.facturas enable row level security;
alter table public.facturas add constraint facturas_numero_key UNIQUE (numero);
alter table public.facturas add constraint facturas_pkey PRIMARY KEY (id);
alter table public.facturas add constraint facturas_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id);
alter table public.facturas add constraint facturas_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE SET NULL;
alter table public.facturas add constraint facturas_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES proyectos(id);
alter table public.facturas add constraint facturas_sociedad_fkey FOREIGN KEY (sociedad) REFERENCES sociedades(clave);
alter table public.facturas add constraint facturas_contrato_obligatorio CHECK (((contrato_id IS NOT NULL) OR (created_at < '2026-08-12 00:00:00+00'::timestamp with time zone) OR anulada));
alter table public.facturas add constraint facturas_recibi_justificante_obligatorio CHECK (((tipo <> 'recibi'::text) OR (justificante_path IS NOT NULL) OR (created_at < '2026-08-11 00:00:00+00'::timestamp with time zone)));
alter table public.facturas add constraint facturas_tipo_check CHECK ((tipo = ANY (ARRAY['factura'::text, 'proforma'::text, 'recibi'::text])));
CREATE INDEX IF NOT EXISTS facturas_client_idx ON public.facturas USING btree (client_id);
CREATE INDEX IF NOT EXISTS facturas_contrato_id_idx ON public.facturas USING btree (contrato_id);
CREATE UNIQUE INDEX IF NOT EXISTS facturas_proforma_activa_por_contrato ON public.facturas USING btree (contrato_id) WHERE ((tipo = 'proforma'::text) AND (anulada = false) AND (contrato_id IS NOT NULL));
CREATE INDEX IF NOT EXISTS facturas_proyecto_idx ON public.facturas USING btree (proyecto_id);
create policy "agentes con la herramienta insertan facturas" on public.facturas for INSERT to authenticated with check ((es_agente() AND puede('facturas'::text)));
create policy "agentes leen sus facturas" on public.facturas for SELECT to authenticated using ((es_agente() AND (es_suyo(creado_por) OR es_manager_de(proyecto_id))));
create policy "borrar facturas" on public.facturas for DELETE to public using (((COALESCE(enviada, false) = false) AND (es_super_admin() OR (es_admin() AND (COALESCE(anulada, false) = false) AND (NOT (EXISTS ( SELECT 1 FROM recibi_aplicaciones ra WHERE ((ra.factura_id = facturas.id) OR (ra.recibi_id = facturas.id)))))))));
create policy "el autor, su manager, o un admin editan facturas no anuladas" on public.facturas for UPDATE to authenticated using ((es_super_admin() OR ((anulada = false) AND es_agente() AND puede('facturas'::text) AND (es_suyo(creado_por) OR es_manager_de(proyecto_id))))) with check ((es_super_admin() OR (es_agente() AND puede('facturas'::text) AND (es_suyo(creado_por) OR es_manager_de(proyecto_id)))));

create table if not exists public.unidades (
  id uuid not null default gen_random_uuid(),
  codigo text not null,
  proyecto text not null,
  tipo text not null default 'parcela'::text,
  superficie_m2 numeric,
  precio numeric,
  moneda text default 'EUR'::text,
  estado text not null default 'disponible'::text,
  contrato_id uuid,
  notas text,
  created_at timestamp with time zone not null default now(),
  precio_suelo numeric,
  precio_construccion numeric,
  modelo text,
  obra_fase text,
  obra_fecha_entrega date,
  obra_actualizado timestamp with time zone,
  fase_masterplan text,
  zona_masterplan text,
  proyecto_id uuid,
  modelo_id uuid,
  publicado_investor_deck boolean not null default false,
  cuota_reserva_investor_deck numeric,
  codigo_orden text default lw_orden_natural(codigo),
  contrato_liberado_id uuid
);
alter table public.unidades enable row level security;
alter table public.unidades add constraint unidades_proyecto_codigo_key UNIQUE (proyecto, codigo);
alter table public.unidades add constraint unidades_pkey PRIMARY KEY (id);
alter table public.unidades add constraint unidades_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE SET NULL;
alter table public.unidades add constraint unidades_contrato_liberado_id_fkey FOREIGN KEY (contrato_liberado_id) REFERENCES contratos(id) ON DELETE SET NULL;
alter table public.unidades add constraint unidades_modelo_id_fkey FOREIGN KEY (modelo_id) REFERENCES modelos(id);
alter table public.unidades add constraint unidades_obra_fase_fkey FOREIGN KEY (obra_fase) REFERENCES obra_fases(clave);
alter table public.unidades add constraint unidades_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES proyectos(id) ON DELETE SET NULL;
alter table public.unidades add constraint unidades_tipo_fkey FOREIGN KEY (tipo) REFERENCES tipos_vivienda(clave);
alter table public.unidades add constraint unidades_estado_check CHECK ((estado = ANY (ARRAY['disponible'::text, 'reservada'::text, 'vendida'::text, 'bloqueada'::text, 'no_disponible'::text, 'cobrada'::text])));
CREATE INDEX IF NOT EXISTS unidades_contrato_id_idx ON public.unidades USING btree (contrato_id);
CREATE INDEX IF NOT EXISTS unidades_estado_idx ON public.unidades USING btree (estado);
CREATE INDEX IF NOT EXISTS unidades_modelo_idx ON public.unidades USING btree (modelo_id);
CREATE INDEX IF NOT EXISTS unidades_proyecto_codigo_orden_idx ON public.unidades USING btree (proyecto, codigo_orden);
CREATE UNIQUE INDEX IF NOT EXISTS unidades_proyecto_id_codigo_key ON public.unidades USING btree (proyecto_id, codigo);
CREATE INDEX IF NOT EXISTS unidades_proyecto_id_idx ON public.unidades USING btree (proyecto_id);
CREATE INDEX IF NOT EXISTS unidades_proyecto_idx ON public.unidades USING btree (proyecto);
create policy "agentes con la herramienta actualizan unidades" on public.unidades for UPDATE to authenticated using ((es_agente() AND puede('unidades'::text) AND unidad_visible(proyecto_id))) with check ((es_agente() AND puede('unidades'::text) AND unidad_visible(proyecto_id)));
create policy "agentes con la herramienta crean unidades" on public.unidades for INSERT to authenticated with check ((es_agente() AND puede('unidades'::text) AND unidad_visible(proyecto_id)));
create policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades for SELECT to authenticated using ((es_agente() AND unidad_visible(proyecto_id)));

create table if not exists public.contrato_firmas (
  id uuid not null default gen_random_uuid(),
  contrato_id uuid not null,
  token_hash text not null,
  firmante_nombre text,
  firmante_email text,
  firmante_rol text,
  snapshot_path text,
  estado text not null default 'pendiente'::text,
  creado_en timestamp with time zone not null default now(),
  expira_en timestamp with time zone not null default (now() + '30 days'::interval),
  firmado_en timestamp with time zone,
  firmante_ip text,
  firmante_user_agent text,
  orden integer not null default 1,
  pdf_path text,
  pdf_hash text,
  enlace_firma text
);
alter table public.contrato_firmas enable row level security;
alter table public.contrato_firmas add constraint contrato_firmas_token_hash_key UNIQUE (token_hash);
alter table public.contrato_firmas add constraint contrato_firmas_pkey PRIMARY KEY (id);
alter table public.contrato_firmas add constraint contrato_firmas_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS contrato_firmas_contrato_idx ON public.contrato_firmas USING btree (contrato_id);
CREATE UNIQUE INDEX IF NOT EXISTS contrato_firmas_un_pendiente_por_rol ON public.contrato_firmas USING btree (contrato_id, firmante_rol) WHERE (estado = 'pendiente'::text);
-- Las policies de escritura de contrato_firmas se reescriben en
-- 20260922172000_vencimientos_y_firmas_siguen_al_contrato.sql (antes eran
-- es_agente() a secas). Aquí, las de ese momento:
create policy "agentes actualizan firmas" on public.contrato_firmas for UPDATE to authenticated using (es_agente()) with check (es_agente());
create policy "agentes borran firmas" on public.contrato_firmas for DELETE to authenticated using (es_agente());
create policy "agentes gestionan firmas (escritura)" on public.contrato_firmas for INSERT to authenticated with check (es_agente());
create policy "agentes leen firmas de sus contratos" on public.contrato_firmas for SELECT to authenticated using ((es_agente() AND (EXISTS ( SELECT 1 FROM contratos c WHERE ((c.id = contrato_firmas.contrato_id) AND (es_suyo(c.creado_por) OR es_manager_de(c.proyecto_id)))))));

create table if not exists public.contrato_compradores (
  contrato_id uuid not null,
  client_id uuid not null,
  rol text not null default 'adquiriente_1'::text,
  creado_en timestamp with time zone not null default now()
);
alter table public.contrato_compradores enable row level security;
alter table public.contrato_compradores add constraint contrato_compradores_pkey PRIMARY KEY (contrato_id, rol);
alter table public.contrato_compradores add constraint contrato_compradores_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE RESTRICT;
alter table public.contrato_compradores add constraint contrato_compradores_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE CASCADE;
alter table public.contrato_compradores add constraint contrato_compradores_rol_check CHECK (((rol ~ '^adquiriente_[1-9]$'::text) OR (rol = 'representante'::text)));
CREATE INDEX IF NOT EXISTS contrato_compradores_client_idx ON public.contrato_compradores USING btree (client_id);
create policy "agentes actualizan contrato_compradores" on public.contrato_compradores for UPDATE to authenticated using (es_agente()) with check (es_agente());
create policy "agentes borran contrato_compradores" on public.contrato_compradores for DELETE to authenticated using (es_agente());
create policy "agentes crean contrato_compradores" on public.contrato_compradores for INSERT to authenticated with check (es_agente());
create policy "agentes leen contrato_compradores" on public.contrato_compradores for SELECT to authenticated using (es_agente());

create table if not exists public.contrato_eventos (
  id uuid not null default gen_random_uuid(),
  contrato_id uuid not null,
  evento text not null,
  detalle jsonb,
  quien text,
  creado_en timestamp with time zone not null default now()
);
alter table public.contrato_eventos enable row level security;
alter table public.contrato_eventos add constraint contrato_eventos_pkey PRIMARY KEY (id);
alter table public.contrato_eventos add constraint contrato_eventos_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE CASCADE;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check CHECK ((evento = ANY (ARRAY['creado'::text, 'editado'::text, 'tipo_cambiado'::text, 'enviado_a_firma'::text, 'firma_abierta'::text, 'firma_recogida'::text, 'firma_anulada'::text, 'firmado_del_todo'::text, 'desbloqueado'::text, 'traspaso'::text, 'editado_estando_firmado'::text, 'desbloqueado_estando_firmado'::text, 'factura_sin_bloquear'::text, 'cobro_a_factura_huerfana'::text, 'cobro_a_otro_comprador'::text, 'comprador_sin_ficha'::text, 'factura_borrada'::text, 'contrato_borrado'::text, 'reserva_liberada'::text])));
CREATE INDEX IF NOT EXISTS contrato_eventos_contrato_idx ON public.contrato_eventos USING btree (contrato_id, creado_en DESC);
create policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos for SELECT to authenticated using ((es_super_admin() OR (es_agente() AND (evento <> ALL (ARRAY['editado_estando_firmado'::text, 'desbloqueado_estando_firmado'::text, 'factura_sin_bloquear'::text, 'cobro_a_factura_huerfana'::text, 'cobro_a_otro_comprador'::text, 'comprador_sin_ficha'::text])) AND (EXISTS ( SELECT 1 FROM contratos c WHERE ((c.id = contrato_eventos.contrato_id) AND (es_suyo(c.creado_por) OR es_manager_de(c.proyecto_id))))))));

create table if not exists public.contrato_vencimientos (
  id uuid not null default gen_random_uuid(),
  contrato_id uuid not null,
  orden integer not null,
  descripcion text,
  pct numeric,
  monto numeric,
  fecha date,
  ajustado boolean not null default false,
  nota text,
  actualizado_por text,
  actualizado_en timestamp with time zone,
  creado_en timestamp with time zone not null default now(),
  factura_id uuid,
  no_facturar boolean not null default false,
  origen text not null default 'manual'::text
);
alter table public.contrato_vencimientos enable row level security;
alter table public.contrato_vencimientos add constraint contrato_vencimientos_contrato_id_orden_key UNIQUE (contrato_id, orden);
alter table public.contrato_vencimientos add constraint contrato_vencimientos_pkey PRIMARY KEY (id);
alter table public.contrato_vencimientos add constraint contrato_vencimientos_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE CASCADE;
alter table public.contrato_vencimientos add constraint contrato_vencimientos_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES facturas(id) ON DELETE SET NULL;
alter table public.contrato_vencimientos add constraint contrato_vencimientos_origen_check CHECK ((origen = ANY (ARRAY['manual'::text, 'obra'::text])));
CREATE INDEX IF NOT EXISTS contrato_vencimientos_contrato_idx ON public.contrato_vencimientos USING btree (contrato_id);
CREATE INDEX IF NOT EXISTS contrato_vencimientos_fecha_idx ON public.contrato_vencimientos USING btree (fecha) WHERE (fecha IS NOT NULL);
-- Policies de ese momento (las reescribe 20260922172000_…):
create policy vencimientos_select on public.contrato_vencimientos for SELECT to authenticated using (es_agente());
create policy vencimientos_update on public.contrato_vencimientos for UPDATE to authenticated using ((es_agente() AND puede('vencimientos'::text))) with check ((es_agente() AND puede('vencimientos'::text)));

create table if not exists public.contratos_diseno (
  slug text not null,
  design jsonb not null,
  updated_at timestamp with time zone not null default now()
);
alter table public.contratos_diseno enable row level security;
alter table public.contratos_diseno add constraint contratos_diseno_pkey PRIMARY KEY (slug);
create policy "agentes autenticados escriben diseno" on public.contratos_diseno for ALL to authenticated using (es_agente()) with check (es_agente());
create policy "agentes autenticados leen diseno" on public.contratos_diseno for SELECT to authenticated using (es_agente());

create table if not exists public.correcciones_datos (
  id bigint not null,
  tabla text not null,
  fila_id uuid not null,
  campo text not null,
  valor_anterior text,
  valor_nuevo text,
  motivo text,
  corregido_en timestamp with time zone not null default now(),
  corregido_por text default auth.email()
);
alter table public.correcciones_datos enable row level security;
alter table public.correcciones_datos add constraint correcciones_datos_pkey PRIMARY KEY (id);
create policy "agentes crean correcciones" on public.correcciones_datos for INSERT to authenticated with check (es_agente());
create policy "agentes leen correcciones" on public.correcciones_datos for SELECT to authenticated using (es_agente());

create table if not exists public.correos_enviados (
  id uuid not null default gen_random_uuid(),
  contrato_id uuid,
  factura_id uuid,
  para text not null,
  asunto text not null,
  via text not null,
  enviado_por text,
  enviado_en timestamp with time zone not null default now()
);
alter table public.correos_enviados enable row level security;
alter table public.correos_enviados add constraint correos_enviados_pkey PRIMARY KEY (id);
alter table public.correos_enviados add constraint correos_enviados_contrato_id_fkey FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE CASCADE;
alter table public.correos_enviados add constraint correos_enviados_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES facturas(id) ON DELETE CASCADE;
alter table public.correos_enviados add constraint correos_con_ancla CHECK (((contrato_id IS NOT NULL) OR (factura_id IS NOT NULL)));
alter table public.correos_enviados add constraint correos_enviados_via_check CHECK ((via = ANY (ARRAY['manual'::text, 'enlace_firma'::text, 'firma'::text, 'proforma'::text, 'factura'::text, 'factura_auto'::text, 'aviso_anulacion'::text])));
CREATE INDEX IF NOT EXISTS correos_enviados_contrato_idx ON public.correos_enviados USING btree (contrato_id, enviado_en DESC);
CREATE INDEX IF NOT EXISTS correos_enviados_factura_idx ON public.correos_enviados USING btree (factura_id) WHERE (factura_id IS NOT NULL);
create policy "agentes leen correos" on public.correos_enviados for SELECT to authenticated using (es_agente());
create policy "agentes registran sus envios" on public.correos_enviados for INSERT to authenticated with check ((es_agente() AND (enviado_por = (auth.jwt() ->> 'email'::text))));

create table if not exists public.plantillas_contrato (
  slug text not null,
  nombre text not null,
  orden integer not null default 100,
  creado_en timestamp with time zone not null default now(),
  cobra boolean not null default false,
  archivada boolean not null default false
);
alter table public.plantillas_contrato enable row level security;
alter table public.plantillas_contrato add constraint plantillas_pago_pkey PRIMARY KEY (slug);
create policy "plantillas de pago: solo con sesion" on public.plantillas_contrato for SELECT to authenticated using (true);
create policy "plantillas de pago: solo super admin escribe" on public.plantillas_contrato for ALL to authenticated using (es_super_admin()) with check (es_super_admin());

-- ── Funciones ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._quien_actua()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select nullif(coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''), '')
$function$;

CREATE OR REPLACE FUNCTION public.cron_facturas_secret()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_facturas';
$function$;

CREATE OR REPLACE FUNCTION public.firma_evento_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_quien text;
  v_det   jsonb;
begin
  v_quien := public._quien_actua();
  v_det := jsonb_build_object('rol', new.firmante_rol, 'email', new.firmante_email);

  if tg_op = 'INSERT' then
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.contrato_id, 'enviado_a_firma', v_det, v_quien);
  elsif old.estado is distinct from new.estado then
    if new.estado = 'en_proceso' then
      insert into public.contrato_eventos (contrato_id, evento, detalle)
      values (new.contrato_id, 'firma_abierta', v_det);
    elsif new.estado = 'firmado' then
      insert into public.contrato_eventos (contrato_id, evento, detalle)
      values (new.contrato_id, 'firma_recogida', v_det);
    elsif new.estado = 'anulado' then
      insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
      values (new.contrato_id, 'firma_anulada', v_det, v_quien);
    end if;
  end if;

  return new;
exception when others then
  raise warning 'contrato_eventos (firmas %): %', tg_op, sqlerrm;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.sella_vencimiento()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.actualizado_por := (select auth.email());
  new.actualizado_en  := now();
  return new;
end;
$function$;

-- borrar_comprador: la versión vigente es la de
-- 20260922173000_borrar_comprador_y_proyecto_avisan_antes_de_reventar.sql
-- (esta era la anterior, sin el pre-check de facturas):
CREATE OR REPLACE FUNCTION public.borrar_comprador(p_client_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_nombre     text;
  v_contratos  text;
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
  -- destructivo-ok: es el borrado que pide el owner, tras los tres gates de arriba
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
$function$;

-- ── Triggers ────────────────────────────────────────────────────────────────

CREATE CONSTRAINT TRIGGER condicion_tramos_suma_100 AFTER INSERT OR DELETE OR UPDATE ON public.condicion_tramos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION valida_suma_tramos_comision();
CREATE TRIGGER trg_contrato_evento_log AFTER INSERT OR UPDATE ON public.contratos FOR EACH ROW EXECUTE FUNCTION contrato_evento_log();
CREATE TRIGGER trg_firma_evento_log AFTER INSERT OR UPDATE ON public.contrato_firmas FOR EACH ROW EXECUTE FUNCTION firma_evento_log();
CREATE TRIGGER trg_sella_vencimiento BEFORE UPDATE ON public.contrato_vencimientos FOR EACH ROW EXECUTE FUNCTION sella_vencimiento();
CREATE TRIGGER trg_set_factura_numero BEFORE INSERT ON public.facturas FOR EACH ROW EXECUTE FUNCTION set_factura_numero();
CREATE TRIGGER trg_sincroniza_vencimientos AFTER INSERT OR UPDATE OF datos ON public.contratos FOR EACH ROW EXECUTE FUNCTION sincroniza_vencimientos();
