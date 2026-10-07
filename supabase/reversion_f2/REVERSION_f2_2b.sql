-- Reversion del paso 2B (Fase 2 empresas, 7-oct-2026). Devuelve las funciones y policies a la version viva de antes del 2B.
-- Valida mientras nadie tenga rol de empresa ni empresas marcadas. La columna cuentas_bancarias.empresa se queda (inofensiva, nula = como antes) salvo que se pida quitarla (ultima linea).
begin;
alter policy "cuentas: agentes" on public.cuentas_bancarias using (public.es_agente());
alter policy "sociedades: agentes" on public.sociedades using (public.es_agente());

create or replace function public.cuentas_cobro_visibles()
 returns table(clave text, label text, titular text, banco text, cuenta text, codigo text, direccion text, extra jsonb, es_escrow boolean, orden integer)
 language sql stable security definer set search_path = '' as $$
  select c.clave, c.label, c.titular, c.banco, c.cuenta, c.codigo, c.direccion, c.extra, c.es_escrow, c.orden
    from public.cuentas_bancarias c
   where c.activa and (
         public.es_agente()
      or (public.es_portal() and c.clave in (
            select f.datos->'fields'->>'cuenta'
              from public.facturas f
              join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
              join public.portal_accesos pa on pa.client_id = cc.client_id and pa.activo
                                            and pa.email = lower(coalesce((select auth.email()), ''))
             where not coalesce(f.anulada, false))))
   order by c.orden $$;

create or replace function public.sociedades_visibles()
 returns table(clave text, label text, razon text, marca text, npwp text, npwp_label text, nib text, domicilio text, rep text, logo text, logo_alto text, emisor_debajo boolean, folio text, tinta jsonb, es_indonesia boolean, orden integer)
 language sql stable security definer set search_path = '' as $$
  select s.clave, s.label, s.razon, s.marca, s.npwp, s.npwp_label, s.nib, s.domicilio, s.rep,
         s.logo, s.logo_alto, s.emisor_debajo, s.folio, s.tinta, s.es_indonesia, s.orden
    from public.sociedades s
   where s.activa and (
         public.es_agente()
      or (public.es_portal() and s.clave in (
            select x.k from public.facturas f
              join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
              join public.portal_accesos pa on pa.client_id = cc.client_id and pa.activo
                                            and pa.email = lower(coalesce((select auth.email()), ''))
              cross join lateral (values (f.sociedad), (f.datos->'fields'->>'sociedad')) x(k)
             where not coalesce(f.anulada, false))))
   order by s.orden $$;

create or replace function public.compradores_lista()
 returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, kyc_status text, propietario text, created_at timestamp with time zone, passport_hint text)
 language sql stable security definer set search_path = '' as $$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.kyc_status, c.propietario, c.created_at,
         case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end
    from public.clients c where public.es_agente() $$;

create or replace function public.compradores_numeros()
 returns table(id uuid, numero_cliente text)
 language sql stable security definer set search_path = '' as $$ select c.id, c.numero_cliente from public.clients c where public.es_agente() $$;

create or replace function public.comprador_contratos_resumen(p_client_id uuid)
 returns table(contrato_id uuid, rol text, tipo text, proyecto_nombre text, autor text, bloqueado boolean, visible boolean)
 language sql stable security definer set search_path = '' as $$
  select case when v.visible then c.id end,
         cc.rol, c.tipo, c.proyecto_nombre, c.creado_por,
         coalesce(c.bloqueado, false), v.visible
    from public.contrato_compradores cc
    join public.contratos c on c.id = cc.contrato_id
    cross join lateral (
      select public.puede_ver_contrato(c.id) as visible) v
   where public.es_agente() and cc.client_id = p_client_id
   order by c.created_at $$;

-- usuario_guarda_permisos: version de antes del 2B (sin roles de empresa en la lista protegida ni validacion proyectos<=empresas)
create or replace function public.usuario_guarda_permisos(p_user_id uuid, p_cambios jsonb)
 returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.usuarios%rowtype; v_yo boolean; v_rol text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'Solo un administrador con la herramienta Usuarios gestiona permisos' using errcode = '42501';
  end if;
  select * into v_old from public.usuarios u where u.user_id = p_user_id for update;
  if not found or (v_old.rol = 'super_admin' and not public.es_super_admin()) then
    raise exception 'No encuentro ese usuario entre los que puedes gestionar' using errcode = '42501';
  end if;
  v_yo := p_user_id = (select auth.uid());
  if not v_yo and not public.es_super_admin() then
    if v_old.rol in ('admin','super_admin') then
      raise exception 'Un admin no gestiona a otro admin: lo hace un super admin' using errcode = '42501';
    end if;
    if p_cambios ? 'proyectos' and not (
         array(select (jsonb_array_elements_text(p_cambios->'proyectos'))::uuid except select unnest(coalesce(v_old.proyectos, '{}')))
         <@ coalesce((select y.proyectos from public.usuarios y where y.user_id = (select auth.uid())), '{}')) then
      raise exception 'No puedes dar proyectos que no tienes tú' using errcode = '42501';
    end if;
    if p_cambios ? 'tipos_contrato' and not (
         array(select jsonb_array_elements_text(p_cambios->'tipos_contrato') except select unnest(coalesce(v_old.tipos_contrato, '{}')))
         <@ coalesce((select y.tipos_contrato from public.usuarios y where y.user_id = (select auth.uid())), '{}')) then
      raise exception 'No puedes dar tipos de contrato que no tienes tú' using errcode = '42501';
    end if;
  end if;
  if v_yo and not public.es_super_admin()
     and (p_cambios - 'nombre') <> '{}'::jsonb then
    raise exception 'Sobre tu propia ficha solo puedes cambiar el nombre' using errcode = '42501';
  end if;
  if v_yo and (p_cambios ? 'activo' or p_cambios ? 'rol') then
    raise exception 'Nadie se desactiva ni se cambia el rol a sí mismo' using errcode = '42501';
  end if;
  if p_cambios ? 'activo' and (p_cambios->>'activo')::boolean and not v_old.activo and not public.es_super_admin()
     and not (coalesce(v_old.herramientas, '{}') <@ coalesce((select y.herramientas from public.usuarios y
                                                              where y.user_id = (select auth.uid())), '{}')) then
    raise exception 'Esa cuenta tiene herramientas que tú no tienes: la reactiva un super admin' using errcode = '42501';
  end if;
  v_rol := case when p_cambios ? 'rol' then p_cambios->>'rol' else v_old.rol end;
  if v_rol = 'super_admin' and not public.es_super_admin() then
    raise exception 'Solo un super admin da el rol super_admin' using errcode = '42501';
  end if;
  update public.usuarios u
     set nombre         = case when p_cambios ? 'nombre' then nullif(btrim(coalesce(p_cambios->>'nombre', '')), '') else u.nombre end,
         herramientas   = case when p_cambios ? 'herramientas'
                               then coalesce(array(select jsonb_array_elements_text(p_cambios->'herramientas')), '{}') else u.herramientas end,
         tipos_contrato = case when p_cambios ? 'tipos_contrato'
                               then coalesce(array(select jsonb_array_elements_text(p_cambios->'tipos_contrato')), '{}') else u.tipos_contrato end,
         proyectos      = case when p_cambios ? 'proyectos'
                               then coalesce(array(select (jsonb_array_elements_text(p_cambios->'proyectos'))::uuid), '{}') else u.proyectos end,
         activo         = case when p_cambios ? 'activo' then (p_cambios->>'activo')::boolean else u.activo end,
         rol            = v_rol
   where u.user_id = p_user_id;
end $$;

drop function if exists public.sociedad_en_alcance(text);
drop function if exists public.empresa_en_alcance(text);
commit;
-- Opcional (solo si se quiere quitar la columna): alter table public.cuentas_bancarias drop column empresa;
