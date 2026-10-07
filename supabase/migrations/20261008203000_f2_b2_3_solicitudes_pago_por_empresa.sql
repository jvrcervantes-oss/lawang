-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 3 (8-oct-2026): SOLICITUDES DE PAGO Y RETENCIONES POR EMPRESA.
--   La empresa de una solicitud sale de su contrato (empresa_de_contrato); sin contrato = sin empresa = solo global. Un admin_empresa aprueba/rechaza/marca pagada/anula las de su empresa
--   con las mismas reglas de siempre (nadie aprueba ni paga la suya; quien cambio el importe no la aprueba), y un super_admin_empresa lo mismo sin necesitar la casilla Comisiones.
--   Retenciones (PPh): la puerta carga primero la solicitud y decide por su empresa; la sociedad retenedora de un rol restringido tiene que ser la de la empresa de la solicitud.
--   Policies de lectura de solicitudes_pago y de solicitudes_pago_retencion por empresa (envoltorios con EXECUTE de la migracion 1).
--   Los 34 usuarios de hoy: sin cambio (lo prueba f2_foto_b2.sql).
-- destructivo-ok: create or replace de funciones, alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql

create or replace function public._solicitud_puede_tocar(s public.solicitudes_pago) returns boolean
language sql stable security definer set search_path = '' as $$
  -- = policy «solicitudes: admin resuelve, el creador toca la suya pendiente» (USING); la automática no es «suya»
  select public._puede_admin_de(public.empresa_de_contrato(s.contrato_id), 'comisiones')
      or (s.creado_por = (select auth.uid()) and s.estado = 'pendiente'
          and s.origen is distinct from 'comision_automatica')
$$;

create or replace function public._retencion_puerta(p_solicitud uuid) returns public.solicitudes_pago
language plpgsql security definer set search_path = '' as $function$
declare s public.solicitudes_pago%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public._puede_herr_admin('comisiones') then
    raise exception 'Solo un administrador con la casilla Comisiones registra retenciones' using errcode = '42501';
  end if;
  -- primero se lee (sin bloquear) para saber de que empresa es; despues se decide; despues se bloquea
  select * into s from public.solicitudes_pago sp where sp.id = p_solicitud;
  if not found then raise exception 'Esa solicitud ya no existe' using errcode = 'P0002'; end if;
  if not public._puede_admin_de(public.empresa_de_contrato(s.contrato_id), 'comisiones') then
    raise exception 'Solo un administrador con la casilla Comisiones registra retenciones' using errcode = '42501';
  end if;
  select * into s from public.solicitudes_pago sp where sp.id = p_solicitud for update;
  if s.estado <> 'pagada' then
    raise exception 'La retención se registra sobre una solicitud pagada (esta está %)', s.estado using errcode = '22023';
  end if;
  return s;
end $function$;

-- Dos funciones largas cambian en pocas lineas: sustitucion exacta sobre la definicion viva (si el texto no coincide el numero de veces esperado, la migracion se para sin tocar nada).
do $m$
declare d text; viejo text; nuevo text; n int;
begin
  -- trigger de transiciones de solicitudes_pago: cada «es administrador» pasa a «es administrador de la empresa del contrato de ESTA solicitud»
  d := pg_get_functiondef('public._trg_solicitud_pago_transicion()'::regprocedure);
  viejo := 'public.es_admin()';
  nuevo := 'public.es_admin_de(public.empresa_de_contrato(old.contrato_id))';
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 5 then raise exception '_trg_solicitud_pago_transicion: se esperaban 5 coincidencias de es_admin() y hay %', n; end if;
  execute replace(d, viejo, nuevo);

  -- retencion: un rol restringido solo retiene con la sociedad de la empresa de la solicitud
  d := pg_get_functiondef('public.solicitud_pago_retencion_guarda(uuid,jsonb)'::regprocedure);
  viejo := '  if v_base > s.importe then';
  nuevo := E'  if public.alcance_restringido() and not public.es_admin()\n'
        || E'     and not exists (select 1 from public.empresas e where e.clave = public.empresa_de_contrato(s.contrato_id) and e.sociedad_clave = v_ent) then\n'
        || E'    raise exception ''La sociedad retenedora tiene que ser la de la empresa de la solicitud'' using errcode = ''42501'';\n'
        || E'  end if;\n'
        || viejo;
  n := (length(d) - length(replace(d, viejo, ''))) / length(viejo);
  if n <> 1 then raise exception 'solicitud_pago_retencion_guarda: se esperaba 1 coincidencia y hay %', n; end if;
  execute replace(d, viejo, nuevo);
end $m$;

alter policy "solicitudes: cada uno lee las suyas, admin con casilla todas" on public.solicitudes_pago
  using (public.solicitud_admin_de_contrato(contrato_id)
         or ((creado_por = (select auth.uid())) and (origen is distinct from 'comision_automatica'::text))
         or (beneficiario_email = (select auth.email())));

alter policy "retencion: admin con casilla todas, el perceptor la suya" on public.solicitudes_pago_retencion
  using (public.retencion_admin_de_solicitud(solicitud_id)
         or (perceptor_user_id = (select auth.uid())));
