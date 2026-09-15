-- Investor Deck multi-proyecto (15-sep-2026) -- pieza 3/4.
-- RPC de activacion, hallazgo de Seguridad en la revision previa: el plan
-- original colgaba "Activar" de la policy generica de `unidades`
-- ("agentes con la herramienta actualizan unidades"), que es la misma con la
-- que un agente cambia precio/estado para uso interno -- publicar el proyecto
-- entero al mundo no es "editar inventario". Aqui es una funcion propia,
-- security definer, con es_admin() explicito, que bypassa esa policy general
-- (nunca la usa: hace el UPDATE ella misma) y deja rastro en deck_publicaciones
-- (mismo hallazgo de Seguridad: la activacion se caia del sistema de auditoria
-- que ya tienen deck_faq/deck_forecast/deck_forecast_proyecto/deck_fotos).
--
-- Decision del owner (15-sep, confirmada tras 2 rondas): "Activar" marca TODAS
-- las unidades del proyecto, sin filtrar por estado (igual que ya hace hoy
-- Palm Field, ver `update unidades set publicado_investor_deck = true where
-- proyecto = 'Palm Field W5'` en 20260910025145). No es un descuido: es el
-- mismo alcance que ya esta en produccion, decidido explicitamente aqui en vez
-- de heredado en silencio.

create or replace function public.investor_deck_activar(p_proyecto text, p_activo boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_proyecto_id uuid;
  v_count integer;
begin
  if not es_admin() then
    raise exception 'solo un admin puede activar/desactivar el investor deck';
  end if;

  select id into v_proyecto_id from public.proyectos where nombre = p_proyecto;
  if v_proyecto_id is null then
    raise exception 'proyecto no encontrado: %', p_proyecto;
  end if;

  update public.unidades set publicado_investor_deck = p_activo where proyecto = p_proyecto;
  get diagnostics v_count = row_count;

  insert into public.deck_publicaciones (tabla, fila_id, accion, antes, despues)
  values (
    'investor_deck_activacion',
    v_proyecto_id,
    case when p_activo then 'alta' else 'baja' end,
    null,
    jsonb_build_object('proyecto', p_proyecto, 'unidades_afectadas', v_count, 'activo', p_activo)
  );

  return v_count;
end;
$$;

revoke all on function public.investor_deck_activar(text, boolean) from public, anon;
grant execute on function public.investor_deck_activar(text, boolean) to authenticated;

comment on function public.investor_deck_activar is
  'Unica puerta para activar/desactivar el Investor Deck publico de un proyecto. security definer + es_admin() explicito (nunca cuelga de la policy generica de unidades). Marca publicado_investor_deck en TODAS las unidades del proyecto (decision del owner, mismo alcance que ya tiene Palm Field en produccion) y deja rastro en deck_publicaciones.';
