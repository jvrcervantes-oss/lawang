-- Reversion del BLOQUE 1 del cierre de empresas (8-oct-2026): proyectos, parcelas, contratos y reservas por empresa.
-- Devuelve cada funcion a la definicion viva de ANTES (parches inversos con el mismo contador de apariciones; las que se reescribieron enteras, con su texto anterior).
-- Valida mientras nadie tenga rol de empresa. Se puede ejecutar entera o por partes (PARTE 1 = migracion 20261008100000; PARTE 2 = migracion 20261008100100, mas abajo).
-- Ensayada: migracion + reversion + comparacion del md5 de cada definicion con el de antes (ver bitacora del encargo).
-- destructivo-ok: reversion de funciones; drop de proyecto_alta(text,text) para volver a proyecto_alta(text); sin tocar datos
begin;

create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'reversion f2_b1: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;

-- ===================== PARTE 1: proyectos y parcelas =====================
create or replace function public.es_manager_de(p_proyecto_id uuid)
 returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and u.rol = 'project_manager'
         and p_proyecto_id = any (u.proyectos_supervisados))
  end
$$;

select pg_temp.parchea('public._puede_editar_proyectos()'::regprocedure,
  $q$u.rol in ('project_manager', 'admin_empresa', 'super_admin_empresa'))$q$,
  $q$u.rol = 'project_manager')$q$);

select pg_temp.parchea('public.trg_proyecto_empresa()'::regprocedure,
  $q$if (select auth.uid()) is null then return new; end if;
  if tg_op = 'INSERT' and not public.es_admin() and public.es_admin_de(new.empresa) then return new; end if;$q$,
  $q$if (select auth.uid()) is null then return new; end if;$q$);

drop function public.proyecto_alta(text, text);
create function public.proyecto_alta(p_nombre text)
 returns uuid language plpgsql security definer set search_path = '' as $$
declare v uuid; v_nom text := btrim(coalesce(p_nombre, ''));
begin
  if not public.es_admin() then raise exception 'Dar de alta un proyecto es cosa de un administrador. Pídeselo a dirección.' using errcode = '42501'; end if;
  if v_nom = '' or length(v_nom) > 120 then raise exception 'El nombre no puede quedar vacío' using errcode = '22023'; end if;
  if v_nom ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos p where lower(p.nombre) = lower(v_nom)) then
    raise exception 'Ya existe un proyecto con ese nombre.' using errcode = '23505';
  end if;
  insert into public.proyectos (nombre, creado_por) values (v_nom, (select auth.email())) returning id into v;
  return v;
end $$;
revoke all on function public.proyecto_alta(text) from public, anon;
grant execute on function public.proyecto_alta(text) to authenticated, service_role;

select pg_temp.parchea('public.proyecto_cambiar_estado(uuid,text,boolean,text)'::regprocedure,
  $q$if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then$q$, $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.proyecto_fijar_plazo(uuid,integer,integer)'::regprocedure,
  $q$if not public.es_admin_de(public.empresa_de_proyecto(p_proyecto_id)) then$q$, $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.proyecto_guarda(uuid,jsonb)'::regprocedure,
  $q$if not public.es_admin_de(public.empresa_de_proyecto(p_id)) then$q$, $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.renombrar_proyecto(text,text)'::regprocedure,
  $q$if not public.es_admin_de((select pr.empresa from public.proyectos pr where pr.nombre = p_antiguo)) then$q$, $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.renombrar_proyecto(text,text)'::regprocedure,
  $q$raise exception 'Solo un administrador puede renombrar un proyecto' using errcode = '42501';$q$,
  $q$raise exception 'Solo un administrador puede renombrar un proyecto';$q$);

select pg_temp.parchea('public.unidad_guarda(uuid,jsonb,text)'::regprocedure,
  $q$v_admin boolean := public.es_admin_de(public.empresa_de_unidad(p_id));$q$, $q$v_admin boolean := public.es_admin();$q$);
select pg_temp.parchea('public.unidad_socio_asigna(uuid,uuid,text)'::regprocedure,
  $q$if not public.es_admin_de(public.empresa_de_unidad(p_unidad)) then$q$, $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.unidad_socio_asigna(uuid,uuid,text)'::regprocedure,
  $q$if length(v_nota) > 500 then raise exception 'La nota no puede pasar de 500 caracteres' using errcode = '22023'; end if;
  if p_socio is not null and public.alcance_restringido() and not exists (
       select 1 from public.unidad_socio us join public.unidades un on un.id = us.unidad_id join public.proyectos pr on pr.id = un.proyecto_id
        where us.socio_id = p_socio and public.puede_empresa(pr.empresa)) then
    raise exception 'Ese socio no esta asignado todavia en tus empresas: la primera asignacion la hace un administrador global' using errcode = '42501';
  end if;$q$,
  $q$if length(v_nota) > 500 then raise exception 'La nota no puede pasar de 500 caracteres' using errcode = '22023'; end if;$q$);
select pg_temp.parchea('public.unidad_parte_cobrada_split(uuid)'::regprocedure,
  $q$or public.es_admin_de(public.empresa_de_unidad(p_unidad))) as ok$q$, $q$or public.es_admin()) as ok$q$);
select pg_temp.parchea('public.trg_valida_unidad_id_contrato()'::regprocedure,
  $q$and not public.es_admin_de(public.empresa_de_contrato(new.id)) then$q$, $q$and not public.es_admin() then$q$);

create or replace function public.socios_parcelas(p_proyecto_id uuid)
 returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_admin() then raise exception 'Solo un administrador ve los socios' using errcode = '42501'; end if;
  return jsonb_build_object(
    'socios', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'numero', s.numero, 'nombre', s.nombre,
                                                            'tipo', s.tipo, 'sociedad', s.sociedad, 'activo', s.activo)
                                         order by s.nombre)
                          from public.socios s
                         where s.activo
                            or exists (select 1 from public.unidad_socio us join public.unidades u on u.id = us.unidad_id
                                        where us.socio_id = s.id and u.proyecto_id = p_proyecto_id)), '[]'::jsonb),
    'asignaciones', coalesce((select jsonb_agg(jsonb_build_object('unidad_id', us.unidad_id, 'socio_id', us.socio_id,
                                                                  'nota', us.nota))
                                from public.unidad_socio us
                                join public.unidades u on u.id = us.unidad_id
                               where u.proyecto_id = p_proyecto_id), '[]'::jsonb));
end $$;

select pg_temp.parchea('public.borrar_proyecto(text)'::regprocedure,
  $q$if not public.es_super_admin_de((select pr.empresa from public.proyectos pr where pr.nombre = p_nombre)) then$q$, $q$if not public.es_super_admin() then$q$);
select pg_temp.parchea('public.borrar_unidad(uuid)'::regprocedure,
  $q$if not public.es_super_admin_de(public.empresa_de_unidad(p_id)) then$q$, $q$if not public.es_super_admin() then$q$);

-- ===================== PARTE 2: contratos y reservas (migracion 20261008100100) =====================
alter policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos
  using (
    ((select es_super_admin() as es_super_admin)
     or ((select es_agente() as es_agente)
         and (evento <> all (array['editado_estando_firmado'::text, 'desbloqueado_estando_firmado'::text, 'factura_sin_bloquear'::text,
                                   'cobro_a_factura_huerfana'::text, 'cobro_a_otro_comprador'::text, 'comprador_sin_ficha'::text]))
         and (contrato_id is not null)
         and ((select es_admin() as es_admin) or (contrato_id = any ((select mis_contratos_visibles() as mis_contratos_visibles)::uuid[]))))));
select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$if not (coalesce(v_super, false) or public.es_super_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre))) then$q$,
  $q$if not coalesce(v_super, false) then$q$);
select pg_temp.parchea('public.descuento_comercial_suelo_valido()'::regprocedure,
  $q$if not (coalesce(v_super, false) or public.es_super_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre))) then$q$,
  $q$if not coalesce(v_super, false) then$q$);
select pg_temp.parchea('public.descuento_comercial_rol()'::regprocedure,
  $q$if v_rol in ('super_admin', 'admin', 'sales_manager') or public.es_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre)) then return new; end if;$q$,
  $q$if v_rol in ('super_admin', 'admin', 'sales_manager') then return new; end if;$q$);
select pg_temp.parchea('public.clausulas_negociadas_rol()'::regprocedure,
  $q$if v_rol in ('super_admin', 'admin') or public.es_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre)) then return new; end if;$q$,
  $q$if v_rol in ('super_admin', 'admin') then return new; end if;$q$);
select pg_temp.parchea('public._contrato_pdf_firmado_fijo()'::regprocedure,
  $q$or public.es_super_admin_de((select pr.empresa from public.proyectos pr where pr.id = new.proyecto_id or pr.nombre = new.proyecto_nombre order by (pr.id = new.proyecto_id) desc limit 1)) then return new;$q$,
  $q$or public.es_super_admin() then return new;$q$);
select pg_temp.parchea('public.borrar_operacion(uuid)'::regprocedure,
  $q$if not (public.es_super_admin() or not exists (
       select 1 from public.contratos c2 left join public.proyectos p2 on p2.id = c2.proyecto_id
        where c2.id = any (ids) and not public.es_super_admin_de(p2.empresa))) then$q$,
  $q$if not public.es_super_admin() then$q$);
select pg_temp.parchea('public._contrato_anexo_check(uuid)'::regprocedure,
  $q$public.es_super_admin_de(public.empresa_de_contrato(p_contrato))$q$,
  $q$public.es_super_admin()$q$, 2);
select pg_temp.parchea('public.contrato_saldo(uuid)'::regprocedure,
  $q$if not (public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) or$q$,
  $q$if not (public.es_super_admin() or$q$);
select pg_temp.parchea('public.contrato_poder_vincula(uuid)'::regprocedure,
  $q$(public.es_super_admin_de(public.empresa_de_contrato(c.id))$q$,
  $q$(public.es_super_admin()$q$);
select pg_temp.parchea('public.contrato_firmas_anula(uuid,text,boolean,text)'::regprocedure,
  $q$if not public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) then$q$,
  $q$if not public.es_super_admin() then$q$);
select pg_temp.parchea('public.contrato_desbloquea(uuid)'::regprocedure,
  $q$if not public.es_super_admin_de(public.empresa_de_contrato(p_id)) then$q$,
  $q$if not public.es_super_admin() then$q$);
select pg_temp.parchea('public.contrato_guarda(uuid,jsonb)'::regprocedure,
  $q$public.es_super_admin_de(public.empresa_de_contrato(coalesce(v_row.id, v_old.id)))$q$,
  $q$public.es_super_admin()$q$, 3);
select pg_temp.parchea('public.contrato_calendario_aplica(jsonb,jsonb,numeric,date,uuid)'::regprocedure,
  $q$v_admin   boolean := public.es_admin_de(coalesce(public.empresa_de_contrato(p_contrato_id), (select pr.empresa from public.proyectos pr where pr.nombre = p_datos->'fields'->>'proyecto_nombre' limit 1)));$q$,
  $q$v_admin   boolean := public.es_admin();$q$);
select pg_temp.parchea('public.carta_cobrado_recalcula(uuid)'::regprocedure,
  $q$if not public.es_admin_de(public.empresa_de_contrato(p_contrato_id)) then$q$,
  $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.deshace_liberacion(uuid,text,integer,boolean)'::regprocedure,
  $q$if not public.es_admin_de(public.empresa_de_contrato(p_contrato_id)) then$q$,
  $q$if not public.es_admin() then$q$);
select pg_temp.parchea('public.prorroga_reserva(uuid,integer,text,boolean)'::regprocedure,
  $q$v_es_admin := public.es_admin_de(public.empresa_de_contrato(p_contrato_id));$q$,
  $q$v_es_admin := public.es_admin();$q$);
select pg_temp.parchea('public.libera_reserva(uuid,uuid,text,text)'::regprocedure,
  $q$public.es_admin_de(public.empresa_de_contrato(p_contrato_id))$q$,
  $q$public.es_admin()$q$);
drop function public.super_de_contrato(uuid);
drop function public._empresa_fila_contrato(uuid, text);

commit;
