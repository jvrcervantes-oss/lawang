-- destructivo-ok: solo construye (renombra la funcion de la migracion 20261010135000 a un nucleo interno y pone delante un envoltorio; create or replace de bot_importar_config). No borra ni vacia datos. Reversion: supabase/reversion_bot_sin_redis_s5/REVERSION_ajustes.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS — S5-puente: dos arreglos BAJA del revisor sobre el importador (9-oct-2026)
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md (LAW-507). TEMPORAL como el resto del importador: S9 lo retira todo.
--   1. bot_importar_chat: un tipo que no es el esperado (booleano que no lo es, entero con letras o desbordado) lanzaba una excepcion con el
--      mensaje crudo de Postgres. Ahora devuelve {ok:false,error:'forma'}. Se hace SIN reescribir la funcion: la actual pasa a ser el nucleo
--      _bot_importar_chat_nucleo (sin EXECUTE para nadie) y bot_importar_chat es un envoltorio que atrapa SOLO los errores de conversion de tipo
--      (22P02 texto invalido, 22003 fuera de rango). Cualquier otro fallo (bloqueo, permisos) sigue siendo un fallo. El bloque con EXCEPTION
--      deshace lo escrito por el nucleo en ese intento: una entrada rota no deja un chat a medias.
--   2. bot_importar_config: una entrada del log sin prev o sin next (jsonb_typeof(NULL) <> 'object' es NULL, no true) no se saltaba y
--      reventaba al insertar. Ahora `is distinct from 'object'`; lo mismo con pausa_horas ausente (NULL !~ ... es NULL).
-- ============================================================================

alter function public.bot_importar_chat(jsonb) rename to _bot_importar_chat_nucleo;
revoke all on function public._bot_importar_chat_nucleo(jsonb) from public, anon, authenticated, service_role, bot_lawang;

create or replace function public.bot_importar_chat(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'error', 'forma'); end if;
  return public._bot_importar_chat_nucleo(p);
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('ok', false, 'error', 'forma');
end $f$;

create or replace function public.bot_importar_config(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  c   jsonb := p->'config';
  v_ver int;
  v_n bigint;
  v_extra text; v_bien text; v_ph int;
  e record;
  v_total int := 0;
begin
  if c is null or jsonb_typeof(c) <> 'object' or jsonb_typeof(coalesce(p->'log', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p->'log', '[]'::jsonb)) > 50 then
    return jsonb_build_object('ok', false, 'error', 'forma');
  end if;
  select b.version into v_ver from public.bot_config b where b.id for update;
  select count(*) into v_n from public.bot_config_log;
  if v_ver is distinct from 1 or v_n > 0 then
    return jsonb_build_object('ok', true, 'resultado', 'ya_configurada');          -- alguien ya la edito desde la intranet: manda lo de Postgres
  end if;
  v_extra := left(public._crm_bot_config_limpia(c->>'extra'), 2000);
  v_bien  := left(public._crm_bot_config_limpia(c->>'bienvenida'), 500);
  if coalesce((c->>'pausa_horas') !~ '^[0-9]{1,3}$', true) or (c->>'pausa_horas')::int > 720 then return jsonb_build_object('ok', false, 'error', 'pausa_horas'); end if;
  v_ph := (c->>'pausa_horas')::int;

  perform set_config('bot.importando', 'on', true);
  -- el registro primero (mas viejo primero => ids crecientes), en snake_case y con la forma completa de la fila
  for e in select x.v, x.ord from jsonb_array_elements(coalesce(p->'log', '[]'::jsonb)) with ordinality as x(v, ord) order by x.ord loop
    continue when jsonb_typeof(e.v) is distinct from 'object' or jsonb_typeof(e.v->'prev') is distinct from 'object' or jsonb_typeof(e.v->'next') is distinct from 'object';
    continue when coalesce((e.v->'prev'->>'pausa_horas') !~ '^[0-9]{1,3}$', true) or coalesce((e.v->'next'->>'pausa_horas') !~ '^[0-9]{1,3}$', true);
    continue when (e.v->'prev'->>'pausa_horas')::int > 720 or (e.v->'next'->>'pausa_horas')::int > 720;
    insert into public.bot_config_log (cuando, usuario, version, prev, next)
    values (coalesce(public._bot_importar_ms(case when (e.v->>'ts_ms') ~ '^[0-9]{1,15}$' then (e.v->>'ts_ms')::bigint end), now()),
            coalesce(nullif(left(public._bot_limpia(e.v->>'by', 120), 120), ''), 'desconocido'),
            e.ord::int,
            jsonb_build_object('id', true, 'extra', left(public._crm_bot_config_limpia(e.v->'prev'->>'extra'), 2000),
                               'bienvenida', left(public._crm_bot_config_limpia(e.v->'prev'->>'bienvenida'), 500),
                               'pausa_horas', (e.v->'prev'->>'pausa_horas')::int, 'resumen_cada_n', 30, 'fallos_alarma', 3, 'version', e.ord::int),
            jsonb_build_object('id', true, 'extra', left(public._crm_bot_config_limpia(e.v->'next'->>'extra'), 2000),
                               'bienvenida', left(public._crm_bot_config_limpia(e.v->'next'->>'bienvenida'), 500),
                               'pausa_horas', (e.v->'next'->>'pausa_horas')::int, 'resumen_cada_n', 30, 'fallos_alarma', 3, 'version', e.ord::int + 1));
    v_total := v_total + 1;
  end loop;
  update public.bot_config
     set extra = v_extra, bienvenida = v_bien, pausa_horas = v_ph,
         actualizado_por = coalesce(nullif(left(public._bot_limpia(c->>'updated_by', 120), 120), ''), 'importado de Redis')
   where id;
  perform set_config('bot.importando', 'off', true);
  return jsonb_build_object('ok', true, 'resultado', 'importada', 'log_importado', v_total);
end $f$;

-- grants: el envoltorio solo para bot_lawang; bot_importar_config conserva los suyos (create or replace no los toca)
revoke all on function public.bot_importar_chat(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.bot_importar_chat(jsonb) to bot_lawang;

-- Cierre explicito (9-oct, aviso BOT-S1): bot_importar_config conserva el ACL de la 20261010135000 (create or replace no lo toca); este revoke es idempotente y no cambia ningun permiso.
revoke all on function public.bot_importar_config(jsonb) from public, anon, authenticated, service_role;
