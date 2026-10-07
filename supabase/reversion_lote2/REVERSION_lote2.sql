-- REVERSIÓN lote 2 (6-oct-2026). Los dos bloques de F7 se probaron en una transacción con rollback: devuelven el md5 de la definición previa
-- (usuario_guarda_permisos: 24bdfadc9e7331973db4b99658f05067 · usuario_supervisa_proyecto: 64e79ebca59107528981c3f06affa857 ·
--  contrato_sociedad_existe: d07b5092c892e9501ff933ef8ce9d2ec).
-- F7
do $$ declare v text; begin
  v := pg_get_functiondef('public.usuario_guarda_permisos(uuid,jsonb)'::regprocedure);
  execute replace(v, $b$  -- F7-alcance
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
$b$, '');
  v := pg_get_functiondef('public.usuario_supervisa_proyecto(uuid,uuid,boolean)'::regprocedure);
  execute replace(v, $b$  -- F7-alcance
  if p_asignar and not public.es_super_admin()
     and not exists (select 1 from public.usuarios y where y.user_id = (select auth.uid()) and p_proyecto_id = any (y.proyectos)) then
    raise exception 'Solo puedes asignar proyectos que son tuyos' using errcode = '42501';
  end if;
$b$, '');
end $$;
-- F8a (policy previa: using (public.es_agente()))
drop policy "agentes ven accesos del portal" on public.portal_accesos;
create policy "agentes ven accesos del portal" on public.portal_accesos for select to authenticated, lw_lector using (public.es_agente());
-- G3: ver REVERTIR al final de supabase/migrations/20261006122314_lote2_g3_sociedad_firmante_7_sin_firmar.sql
-- G2/G6: ver REVERTIR en la cabecera de supabase/migrations/20261006143748_lote2_g2_g6_sociedad_coherente.sql
-- F6 (edge admin-usuarios): git revert del commit y redeploy; versión desplegada antes: 32 (sha256 29c196496b36abeab48dac7efdad92d5fad83c9911e2e6dc010f11dd3f3228ea).
