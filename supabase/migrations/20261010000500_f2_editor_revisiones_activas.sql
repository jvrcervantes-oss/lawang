-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «editor de textos de contrato» (encargos/20261008_lawang_editor_textos_contrato.md) · E10 · selector de revision para el agente que crea contratos (8-oct-2026).
-- PROBLEMA: plantilla_contrato_revisiones_lista (E7) solo contesta a la administracion de la empresa (42501 para el resto), asi que un agente normal que redacta un contrato en
--   contracts/app.html no veia el selector de revision y siempre usaba la estandar.
-- QUE HACE: una RPC nueva de SOLO LECTURA, plantilla_contrato_revisiones_activas(p_empresa, p_slug), que devuelve unicamente {version_id, variante, nombre, version} de las
--   versiones ACTIVAS (ni archivadas, ni borradas, ni borradores) de esa empresa y plantilla. Nunca cuerpos, autores, fechas, conteos ni parrafos distintos.
--   Quien la llama: un agente con sesion y empresa_en_alcance (rol de agente incluido); otra empresa = 42501; anon no tiene EXECUTE.
-- NO toca tablas, triggers ni la RPC de administracion. Nace cerrada y se abre solo a `authenticated`; sin GRANT directo sobre las tablas.
-- Llamador con nombre: el selector de revision de contracts/app.html (cargaRevisiones).
-- destructivo-ok: solo crea una funcion nueva; ninguna fila ni funcion existente cambia
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_editor_revisiones_activas.sql

create function public.plantilla_contrato_revisiones_activas(p_empresa text, p_slug text)
 returns table(version_id uuid, variante text, nombre text, version integer)
 language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if public.uid_sesion() is null or not public.es_agente() then raise exception 'Sin sesion de agente' using errcode = '42501'; end if;
  if p_empresa is null or p_slug is null or not public.empresa_en_alcance(p_empresa) then
    raise exception 'Esa empresa no es de tu alcance' using errcode = '42501';
  end if;
  return query
    select v.id, v.variante, coalesce(v.variante_nombre, case when v.variante = 'estandar' then 'Estándar' else v.variante end), v.version
      from public.plantilla_contrato_versiones v
     where v.empresa = p_empresa and v.slug = p_slug and v.estado = 'activa' and v.borrada_en is null
     order by (v.variante = 'estandar') desc, v.variante;
end $$;

revoke all on function public.plantilla_contrato_revisiones_activas(text, text) from public, anon, service_role;
grant execute on function public.plantilla_contrato_revisiones_activas(text, text) to authenticated;
