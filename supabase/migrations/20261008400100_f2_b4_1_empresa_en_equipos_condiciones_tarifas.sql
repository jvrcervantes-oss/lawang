-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 4 (comisiones, equipos de venta y condiciones) · migracion 1 (8-oct-2026): CADA EMPRESA TIENE LOS SUYOS.
--   Decision del owner (7-oct): equipos de venta, condiciones/tramos de comision, plantillas de reparto y tarifas de administracion se SEPARAN por
--   empresa y, donde hoy servian a las dos, se DUPLICAN (mismos valores) para sandal_woods. Lo que ya esta devengado NO se recalcula ni se mueve.
--   * equipos_venta.empresa (NOT NULL): los 5 existentes quedan 'lawang' (76 de las 90 ventas con equipo son de Lawang). plantilla_reparto y condicion_tramos
--     cuelgan de su equipo/condicion: su empresa es la de su padre (un dato, un dueño), sin columna propia.
--   * equipo_miembros.empresa (copia del equipo, la pone un trigger): el indice «un equipo activo por persona» pasa a ser «uno POR EMPRESA».
--   * condiciones_comision.empresa (NOT NULL): la de su equipo; las estandar (sin equipo) llevan la suya. Un trigger la mantiene coherente con equipo y proyecto.
--   * comision_admin_tarifas.empresa (NOT NULL) y UNIQUE (empresa, efectivo_desde). Los fees, lineas y cobros del libro de administracion ya llevan `sociedad`:
--     su empresa es la de su sociedad (empresas.sociedad_clave), sin columna nueva.
--   * COPIA para sandal_woods de: los 3 equipos ACTIVOS (miembros, plantilla, condiciones y tramos), las 3 condiciones estandar y la tarifa.
--     Las condiciones atadas a un proyecto de Lawang (Palm Field W5) NO se copian. Los equipos inactivos (Carmen, Gus) no se copian: solo guardan historia.
--   * Los triggers que CONGELAN ventas al tocar un miembro (trg_equipo_miembros_congela / _recongela) y el que mete la plantilla por defecto se desactivan SOLO
--     durante la copia: sin eso, copiar miembros reescribiria contrato_closer. Se reactivan al final (misma transaccion).
--   Ninguna venta, devengo ni solicitud cambia: la migracion 2 hace que la eleccion de equipo y de condicion estandar mire la empresa del proyecto de la venta.
-- destructivo-ok: add column con default, drop+create de dos indices unicos (mas permisivos: añaden empresa a la clave) y de la unique de tarifas (idem); inserta copias; sin borrar ni actualizar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b4.sql

-- ---------------------------------------------------------------- 1. columnas (antes que los ayudantes: empresa_de_equipo es sql y se valida al crearla) (default 'lawang' = como estaba; luego sin default: lo nuevo nace con empresa explicita)
alter table public.equipos_venta        add column if not exists empresa text not null default 'lawang' references public.empresas(clave);
alter table public.equipo_miembros      add column if not exists empresa text not null default 'lawang' references public.empresas(clave);
alter table public.condiciones_comision add column if not exists empresa text not null default 'lawang' references public.empresas(clave);
alter table public.comision_admin_tarifas add column if not exists empresa text not null default 'lawang' references public.empresas(clave);
alter table public.equipos_venta        alter column empresa drop default;
alter table public.equipo_miembros      alter column empresa drop default;
alter table public.condiciones_comision alter column empresa drop default;
alter table public.comision_admin_tarifas alter column empresa drop default;

-- ---------------------------------------------------------------- 2. ayudantes internos (sin EXECUTE para nadie salvo los que llama una policy)
create or replace function public._empresa_de_proyecto_int(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.proyectos pr where pr.id = p_id
$$;
create or replace function public._empresa_de_contrato_int(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id where c.id = p_id
$$;
create or replace function public.empresa_de_equipo(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select e.empresa from public.equipos_venta e where e.id = p_id
$$;
create or replace function public.puede_reparto_de(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  -- el «administrador con el reparto de comisiones» de UNA empresa: admin de esa empresa con la casilla comisiones_reparto, o super de esa empresa
  -- (el super global ya pasa puede() solo; el super de empresa no, por eso se pide aparte). Empresa nula: solo los globales (nace cerrado).
  select public.es_admin_de(p_empresa) and (public.puede('comisiones_reparto') or public.es_super_admin_de(p_empresa))
$$;
-- la llaman policies de comision_admin_*: EXECUTE para authenticated y lw_lector (leccion G1)
create or replace function public.empresa_de_sociedad(p_sociedad text) returns text
language sql stable security definer set search_path = '' as $$
  select e.clave from public.empresas e where e.sociedad_clave = p_sociedad limit 1
$$;
revoke all on function public._empresa_de_proyecto_int(uuid), public._empresa_de_contrato_int(uuid), public.empresa_de_equipo(uuid),
                       public.puede_reparto_de(text), public.empresa_de_sociedad(text) from public, anon, authenticated, lw_lector;
grant execute on function public.empresa_de_sociedad(text) to authenticated, lw_lector;

-- ---------------------------------------------------------------- 3. triggers de coherencia
create or replace function public._trg_equipo_miembro_empresa() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.empresa := (select e.empresa from public.equipos_venta e where e.id = new.equipo_id);
  return new;
end $$;
create or replace function public._trg_equipo_empresa_fija() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.empresa is distinct from old.empresa then
    raise exception 'La empresa de un equipo no se cambia: crea otro equipo en la otra empresa' using errcode = '22023';
  end if;
  return new;
end $$;
create or replace function public._trg_condicion_empresa() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_eq text; v_pr text;
begin
  if new.equipo_id is not null then
    select e.empresa into v_eq from public.equipos_venta e where e.id = new.equipo_id;
    new.empresa := v_eq;   -- una condicion de equipo es de la empresa de su equipo, diga lo que diga quien inserta
  end if;
  if new.empresa is null then
    raise exception 'Una condicion de comision necesita empresa' using errcode = '22023';
  end if;
  if new.proyecto_id is not null then
    select pr.empresa into v_pr from public.proyectos pr where pr.id = new.proyecto_id;
    if v_pr is distinct from new.empresa then
      raise exception 'La condicion es de % y su proyecto es de %: tienen que ser de la misma empresa', new.empresa, coalesce(v_pr, '(sin empresa)') using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public._trg_equipo_miembro_empresa(), public._trg_equipo_empresa_fija(), public._trg_condicion_empresa() from public, anon, authenticated, lw_lector;

drop trigger if exists trg_equipo_miembros_empresa on public.equipo_miembros;
create trigger trg_equipo_miembros_empresa before insert or update of equipo_id on public.equipo_miembros
  for each row execute function public._trg_equipo_miembro_empresa();
drop trigger if exists trg_equipos_venta_empresa_fija on public.equipos_venta;
create trigger trg_equipos_venta_empresa_fija before update of empresa on public.equipos_venta
  for each row execute function public._trg_equipo_empresa_fija();
drop trigger if exists trg_condicion_empresa on public.condiciones_comision;
create trigger trg_condicion_empresa before insert or update of empresa, equipo_id, proyecto_id on public.condiciones_comision
  for each row execute function public._trg_condicion_empresa();

-- ---------------------------------------------------------------- 4. indices unicos con empresa (mas permisivos que los de antes: lo que era unico sigue siendolo dentro de su empresa)
drop index if exists public.equipo_miembros_un_equipo_activo;
create unique index equipo_miembros_un_equipo_activo on public.equipo_miembros (lower(closer_email), empresa) where hasta is null;
drop index if exists public.condiciones_comision_estandar_unica;
create unique index condiciones_comision_estandar_unica on public.condiciones_comision
  (empresa, coalesce(proyecto_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(lower(closer_email), ''::text))
  where equipo_id is null and activo and vigente_hasta is null;
alter table public.comision_admin_tarifas drop constraint if exists comision_admin_tarifas_efectivo_desde_key;
alter table public.comision_admin_tarifas add constraint comision_admin_tarifas_empresa_desde_key unique (empresa, efectivo_desde);

-- ---------------------------------------------------------------- 5. COPIA para sandal_woods (con los triggers de congelado apagados solo aqui)
alter table public.equipo_miembros disable trigger trg_equipo_miembros_congela, disable trigger trg_equipo_miembros_recongela;
alter table public.equipos_venta   disable trigger trg_equipos_venta_plantilla_defecto;

create temp table _b4_mapa_cond (viejo uuid primary key, nuevo uuid not null) on commit drop;

do $copia$
declare e record; c record; v_eq uuid; v_c uuid;
begin
  -- 5a. equipos activos de lawang -> su gemelo de sandal_woods
  for e in select * from public.equipos_venta where activo and empresa = 'lawang' order by created_at loop
    insert into public.equipos_venta (nombre, manager_email, activo, closers_ven_comision, empresa)
    values (e.nombre, e.manager_email, e.activo, e.closers_ven_comision, 'sandal_woods') returning id into v_eq;
    insert into public.equipo_miembros (equipo_id, closer_email, desde, hasta, added_by, rol, rol_nombre, created_at)
      select v_eq, m.closer_email, m.desde, m.hasta, coalesce(m.added_by, 'f2_b4_empresas'), m.rol, m.rol_nombre, m.created_at
        from public.equipo_miembros m where m.equipo_id = e.id;
    insert into public.plantilla_reparto (equipo_id, rol_tipo, rol_nombre, pct, creado_por)
      select v_eq, p.rol_tipo, p.rol_nombre, p.pct, 'f2_b4_empresas' from public.plantilla_reparto p where p.equipo_id = e.id;
    insert into public.equipos_log (tabla, fila_id, antes, despues)
      select 'equipos_venta', v_eq, null, to_jsonb(x) || jsonb_build_object('copiado_de', e.id, 'motivo', 'copia por separacion de empresas (bloque 4)')
        from public.equipos_venta x where x.id = v_eq;
    -- 5b. sus condiciones (menos las atadas a un proyecto de otra empresa)
    for c in select k.* from public.condiciones_comision k
              where k.equipo_id = e.id and (k.proyecto_id is null or exists (select 1 from public.proyectos pr where pr.id = k.proyecto_id and pr.empresa = 'sandal_woods'))
              order by k.created_at loop
      insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, importe_fijo, activo, created_by,
                                               vigente_desde, vigente_hasta, empresa, created_at)
      values (v_eq, c.proyecto_id, c.nivel, c.closer_email, c.pct_comision, c.base_calculo, c.importe_fijo, c.activo, 'f2_b4_empresas',
              c.vigente_desde, c.vigente_hasta, 'sandal_woods', c.created_at) returning id into v_c;
      insert into _b4_mapa_cond values (c.id, v_c);
      insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
        select v_c, t.orden, t.disparador_tipo, t.umbral, t.pct_tramo from public.condicion_tramos t where t.condicion_id = c.id;
    end loop;
  end loop;

  -- 5c. condiciones estandar (sin equipo) de lawang -> las suyas en sandal_woods (la cadena entera, para que una venta antigua sin devengo encuentre la suya)
  for c in select k.* from public.condiciones_comision k
            where k.equipo_id is null and k.empresa = 'lawang'
              and (k.proyecto_id is null or exists (select 1 from public.proyectos pr where pr.id = k.proyecto_id and pr.empresa = 'sandal_woods'))
            order by k.created_at loop
    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, importe_fijo, activo, created_by,
                                             vigente_desde, vigente_hasta, empresa, created_at)
    values (null, c.proyecto_id, c.nivel, c.closer_email, c.pct_comision, c.base_calculo, c.importe_fijo, c.activo, 'f2_b4_empresas',
            c.vigente_desde, c.vigente_hasta, 'sandal_woods', c.created_at) returning id into v_c;
    insert into _b4_mapa_cond values (c.id, v_c);
    insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
      select v_c, t.orden, t.disparador_tipo, t.umbral, t.pct_tramo from public.condicion_tramos t where t.condicion_id = c.id;
  end loop;

  -- 5d. las sustituciones (A -> B) se copian apuntando a la copia
  update public.condiciones_comision n set sustituye_a = m2.nuevo
    from _b4_mapa_cond m1
    join public.condiciones_comision o on o.id = m1.viejo
    join _b4_mapa_cond m2 on m2.viejo = o.sustituye_a
   where n.id = m1.nuevo and o.sustituye_a is not null;

  insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    select m.nuevo, null, to_jsonb(x) || jsonb_build_object('copiada_de', m.viejo), 'copia por separacion de empresas (bloque 4)'
      from _b4_mapa_cond m join public.condiciones_comision x on x.id = m.nuevo;

  -- 5e. tarifa de administracion: la de sandal_woods, con los mismos valores
  insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por, empresa)
    select t.pct, t.efectivo_desde, t.nota, 'f2_b4_empresas', 'sandal_woods' from public.comision_admin_tarifas t where t.empresa = 'lawang';
end $copia$;

alter table public.equipo_miembros enable trigger trg_equipo_miembros_congela, enable trigger trg_equipo_miembros_recongela;
alter table public.equipos_venta   enable trigger trg_equipos_venta_plantilla_defecto;
