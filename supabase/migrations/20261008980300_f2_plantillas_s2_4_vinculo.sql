-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S2 · migracion 4/4 (7-oct-2026): FIJAR LA VERSION DE UN CONTRATO.
--   plantilla_contrato_fija(contrato, version) -> void. Llamador: el generador al GUARDAR un contrato (S5), mismo permiso que contrato_guarda (herramienta «contratos» o super de empresa)
--   y poder ver el contrato. Solo se fija una version ACTIVA de la empresa del proyecto del contrato; cambiar de version es llamarla otra vez (acto explicito).
--   Un contrato bloqueado o con alguna fila en contrato_firmas no cambia nunca: lo impide el trigger de la tabla, tambien para postgres. `contratos` no se toca (R3).
--   La carga de los 203 borradores a la v1 semilla (S4) la hace un script como postgres directamente sobre la tabla, con las mismas guardas del trigger.
-- destructivo-ok: solo crea una funcion nueva
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s2.sql
create function public.plantilla_contrato_fija(p_contrato uuid, p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.plantilla_contrato_versiones%rowtype; v_autor text := coalesce((select auth.email()), (select auth.uid())::text);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesion: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_agente() and public._puede_herr_o_super_empresa('contratos') and public.puede_ver_contrato(p_contrato)) then
    raise exception 'No tienes permiso para guardar este contrato.' using errcode = '42501';
  end if;
  select * into v from public.plantilla_contrato_versiones x where x.id = p_version;
  if not found or v.estado <> 'activa' then raise exception 'Solo se fija una version activa' using errcode = '22023'; end if;
  insert into public.contrato_plantilla_version (contrato_id, version_id, fijado_por) values (p_contrato, p_version, v_autor)
  on conflict (contrato_id) do update set version_id = excluded.version_id, fijado_en = now(), fijado_por = excluded.fijado_por;
end $$;
revoke all on function public.plantilla_contrato_fija(uuid, uuid) from public, anon, service_role;
grant execute on function public.plantilla_contrato_fija(uuid, uuid) to authenticated;
