-- bot_faq por RPC (27-sep-2026, cierre global de escrituras): era la única tabla que la edge `bot-agentes` escribía con
-- el JWT del usuario (candado = policy «solo super_admin»). Ahora dos RPC SECURITY DEFINER con el permiso DENTRO; los
-- triggers de siempre siguen mandando (bot_faq_frena: cifras, temas frenados, alcance, tipo, y `aprobado_por` desde la
-- sesión; bot_faq_inmutable: una FAQ no se edita, se retira). Además, aprobar una FAQ que sustituye a otra y retirar
-- la anterior va en UNA transacción (antes, si retirar fallaba, quedaban las dos activas).
-- Tras desplegar la edge nueva, la migración 20260927171500 quita a `authenticated` el INSERT/UPDATE directo.

create or replace function public.bot_faq_aprobar(p_id uuid, p_tema text, p_proyecto uuid, p_tipo text,
                                                 p_pregunta text, p_respuesta text, p_sustituye uuid default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_ret boolean := null;
begin
  if not public.es_super_admin() then
    raise exception 'Aprobar respuestas del asistente lo hace un super admin' using errcode = '42501';
  end if;
  if p_id is null then raise exception 'Falta el identificador de la FAQ' using errcode = '22023'; end if;
  insert into public.bot_faq (id, tema_clave, proyecto_id, tipo_contrato, pregunta, respuesta, sustituye_a)
  values (p_id, p_tema, p_proyecto, p_tipo, p_pregunta, p_respuesta, p_sustituye);
  if p_sustituye is not null then
    update public.bot_faq set activo = false where id = p_sustituye and activo;
    v_ret := found;
  end if;
  return jsonb_build_object('id', p_id, 'anterior_retirada', v_ret);
end $$;
revoke all on function public.bot_faq_aprobar(uuid, text, uuid, text, text, text, uuid) from public, anon;
grant execute on function public.bot_faq_aprobar(uuid, text, uuid, text, text, text, uuid) to authenticated;

create or replace function public.bot_faq_retirar(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_super_admin() then
    raise exception 'Retirar respuestas del asistente lo hace un super admin' using errcode = '42501';
  end if;
  update public.bot_faq set activo = false where id = p_id and activo;
  return found;
end $$;
revoke all on function public.bot_faq_retirar(uuid) from public, anon;
grant execute on function public.bot_faq_retirar(uuid) to authenticated;
