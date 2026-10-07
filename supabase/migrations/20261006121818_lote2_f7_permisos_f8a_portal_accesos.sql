-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 2 (OK del owner 6-oct-2026) · F7 + F8a.
-- F7: usuario_guarda_permisos / usuario_supervisa_proyecto -> un admin no-super no toca a otro admin y solo añade lo que él mismo tiene. Quitar siempre vale.
-- F8a: portal_accesos solo se ve si ves la ficha del comprador (clients tiene RLS propia).
-- destructivo-ok: solo cambia cuerpos de función y una policy de SELECT; no toca filas.
do $$
declare v text; a1 text; a2 text;
begin
  v := pg_get_functiondef('public.usuario_guarda_permisos(uuid,jsonb)'::regprocedure);
  a1 := E'  v_yo := p_user_id = (select auth.uid());\n';
  if position(a1 in v) = 0 then raise exception 'ancla F7a no encontrada'; end if;
  if position('F7-alcance' in v) = 0 then
    v := replace(v, a1, a1 ||
E'  -- F7-alcance\n' ||
E'  if not v_yo and not public.es_super_admin() then\n' ||
E'    if v_old.rol in (''admin'',''super_admin'') then\n' ||
E'      raise exception ''Un admin no gestiona a otro admin: lo hace un super admin'' using errcode = ''42501'';\n' ||
E'    end if;\n' ||
E'    if p_cambios ? ''proyectos'' and not (\n' ||
E'         array(select (jsonb_array_elements_text(p_cambios->''proyectos''))::uuid except select unnest(coalesce(v_old.proyectos, ''{}'')))\n' ||
E'         <@ coalesce((select y.proyectos from public.usuarios y where y.user_id = (select auth.uid())), ''{}'')) then\n' ||
E'      raise exception ''No puedes dar proyectos que no tienes tú'' using errcode = ''42501'';\n' ||
E'    end if;\n' ||
E'    if p_cambios ? ''tipos_contrato'' and not (\n' ||
E'         array(select jsonb_array_elements_text(p_cambios->''tipos_contrato'') except select unnest(coalesce(v_old.tipos_contrato, ''{}'')))\n' ||
E'         <@ coalesce((select y.tipos_contrato from public.usuarios y where y.user_id = (select auth.uid())), ''{}'')) then\n' ||
E'      raise exception ''No puedes dar tipos de contrato que no tienes tú'' using errcode = ''42501'';\n' ||
E'    end if;\n' ||
E'  end if;\n');
    execute v;
  end if;

  v := pg_get_functiondef('public.usuario_supervisa_proyecto(uuid,uuid,boolean)'::regprocedure);
  a2 := E'  if p_asignar and v_rol <> ''project_manager'' then';
  if position(a2 in v) = 0 then raise exception 'ancla F7b no encontrada'; end if;
  if position('F7-alcance' in v) = 0 then
    v := replace(v, a2,
E'  -- F7-alcance\n' ||
E'  if p_asignar and not public.es_super_admin()\n' ||
E'     and not exists (select 1 from public.usuarios y where y.user_id = (select auth.uid()) and p_proyecto_id = any (y.proyectos)) then\n' ||
E'    raise exception ''Solo puedes asignar proyectos que son tuyos'' using errcode = ''42501'';\n' ||
E'  end if;\n' || a2);
    execute v;
  end if;
end $$;

drop policy "agentes ven accesos del portal" on public.portal_accesos;
create policy "agentes ven accesos del portal" on public.portal_accesos
  for select to authenticated, lw_lector
  using (public.es_agente() and exists (select 1 from public.clients c where c.id = portal_accesos.client_id));
