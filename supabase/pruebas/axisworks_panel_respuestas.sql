-- destructivo-ok: prueba REVERTIDA. Crea la tabla y la funcion de la migracion dentro de este mismo DO, que acaba en
-- raise exception (se deshace entero); los DELETE y TRUNCATE de abajo van contra esa tabla recien creada y su objetivo es
-- comprobar que se RECHAZAN. No toca ninguna fila real.
-- Prueba de supabase/migrations/20261011050000_axisworks_panel_respuestas.sql (S4 panel visual, 11-oct-2026).
-- Correr con execute_sql (MCP supabase-lawang) o psql ANTES de aplicar la migracion: si la tabla ya existiera, el
-- create table if not exists la reutilizaria y las sondas mirarian la real.
-- Resultado esperado: «PRUEBA_PANEL_RESPUESTAS_OK n=<casos>». Despues, to_regclass('public.axisworks_panel_respuestas')
-- y to_regprocedure('public.axisworks_panel_respuestas_guarda()') deben seguir en null.
-- Medido el 11-oct-2026 SIN aplicar la migracion: PRUEBA_PANEL_RESPUESTAS_OK n=33, y despues tabla y funcion en null.
-- El bloque entre las marcas «COPIA DE LA MIGRACION» es copia LITERAL de la migracion desde «create table» hasta el
-- final: si cambia la migracion, se rehace esta copia en el mismo commit.
do $prueba$
declare
  n int := 0;
  fallos text := '';
  priv text;
  q1 uuid; q2 uuid;
  nonce1 text; nonce2 text;
  filas int;
  r record;
  ops constant jsonb := '[{"id":"a","texto":"Opcion A"},{"id":"b","texto":"Opcion B"}]';
  ops2 constant jsonb := '[{"id":"x","texto":"Opcion X"},{"id":"y","texto":"Opcion Y"}]';
begin
  -- ===================== COPIA DE LA MIGRACION (inicio) =====================
create table if not exists public.axisworks_panel_respuestas (
  id             uuid primary key default gen_random_uuid(),
  encargo        text not null default '' check (length(encargo) <= 120),
  sesion         text not null default '' check (length(sesion) <= 80),
  titulo         text not null check (length(btrim(titulo)) between 3 and 140),
  en_llano       text not null check (length(btrim(en_llano)) between 10 and 400),
  opciones       jsonb not null check (jsonb_typeof(opciones) = 'array'
                                       and jsonb_array_length(opciones) between 2 and 4),
  tipo           text not null check (tipo in ('decision', 'hard_stop')),
  categoria      text check (categoria in ('precio', 'live', 'borrar', 'enviar_tercero', 'gasto',
                                           'credenciales', 'entregar', 'irreversible')),
  recomendada    text,
  nonce          text not null default replace(gen_random_uuid()::text, '-', ''),
  creada_en      timestamptz not null default now(),
  opcion         text,
  confirmado     boolean,
  respondida_en  timestamptz,
  leida_en       timestamptz,
  leida_por      text check (length(leida_por) <= 80),
  -- una hard_stop SIEMPRE lleva categoria y NUNCA recomendada; una decision al reves
  constraint axw_resp_tipo_fijo check (
    (tipo = 'hard_stop' and categoria is not null and recomendada is null)
    or (tipo = 'decision' and categoria is null and recomendada is not null)),
  constraint axw_resp_respondida check ((opcion is null) = (respondida_en is null)),
  constraint axw_resp_leida check (leida_en is null or respondida_en is not null),
  constraint axw_resp_hard_confirmada check (
    tipo <> 'hard_stop' or opcion is null or confirmado is true)
);

create index if not exists axisworks_panel_respuestas_abiertas
  on public.axisworks_panel_respuestas (creada_en) where respondida_en is null;
create index if not exists axisworks_panel_respuestas_sin_leer
  on public.axisworks_panel_respuestas (respondida_en) where respondida_en is not null and leida_en is null;

create or replace function public.axisworks_panel_respuestas_guarda()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  ids text[];
  o jsonb;
begin
  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'axisworks_panel_respuestas es de solo añadir: no se borra';
  end if;

  if tg_op = 'INSERT' then
    -- opciones: 2-4 objetos {id, texto}; id corto y unico; texto 1-120
    ids := array[]::text[];
    for o in select value from jsonb_array_elements(new.opciones) loop
      if jsonb_typeof(o) <> 'object'
         or coalesce(o->>'id', '') !~ '^[a-z0-9_]{1,20}$'
         or length(btrim(coalesce(o->>'texto', ''))) not between 1 and 120
         or (select count(*) from jsonb_object_keys(o)) <> 2 then
        raise exception 'opcion mal formada: cada opcion es {id, texto}';
      end if;
      if (o->>'id') = any(ids) then
        raise exception 'opcion repetida: %', o->>'id';
      end if;
      ids := ids || (o->>'id');
    end loop;
    if new.recomendada is not null and not (new.recomendada = any(ids)) then
      raise exception 'la recomendada no esta entre las opciones';
    end if;
    -- lo que pone la base, venga lo que venga
    new.nonce := replace(gen_random_uuid()::text, '-', '');
    new.creada_en := now();
    new.opcion := null; new.confirmado := null; new.respondida_en := null;
    new.leida_en := null; new.leida_por := null;
    return new;
  end if;

  -- UPDATE: lo que fija la pregunta no se toca nunca
  if new.id is distinct from old.id or new.encargo is distinct from old.encargo
     or new.sesion is distinct from old.sesion or new.titulo is distinct from old.titulo
     or new.en_llano is distinct from old.en_llano or new.opciones is distinct from old.opciones
     or new.tipo is distinct from old.tipo or new.categoria is distinct from old.categoria
     or new.recomendada is distinct from old.recomendada or new.nonce is distinct from old.nonce
     or new.creada_en is distinct from old.creada_en then
    raise exception 'la pregunta no se edita: se publica otra';
  end if;

  if old.opcion is null and new.opcion is not null then
    -- responder (una sola vez)
    if new.leida_en is not null or new.leida_por is not null then
      raise exception 'no se responde y se lee en el mismo paso';
    end if;
    if not exists (select 1 from jsonb_array_elements(old.opciones) e where e->>'id' = new.opcion) then
      raise exception 'opcion fuera de la pregunta';
    end if;
    if old.tipo = 'hard_stop' and new.confirmado is not true then
      raise exception 'una hard_stop exige confirmacion aparte';
    end if;
    new.respondida_en := now();
    return new;
  end if;

  if old.opcion is not null and old.leida_en is null and new.leida_en is not null then
    -- marcar leida (una sola vez); la respuesta no cambia
    if new.opcion is distinct from old.opcion or new.confirmado is distinct from old.confirmado
       or new.respondida_en is distinct from old.respondida_en then
      raise exception 'la respuesta no se edita';
    end if;
    if length(btrim(coalesce(new.leida_por, ''))) = 0 then
      raise exception 'marcar leida exige leida_por (quien la leyo)';
    end if;
    new.leida_en := now();
    return new;
  end if;

  raise exception 'cambio no permitido en axisworks_panel_respuestas';
end;
$$;

revoke all on function public.axisworks_panel_respuestas_guarda() from public, anon, authenticated;

-- Idempotente sin «drop trigger if exists» (no_destruir.py frenaria el DROP al aplicar): cada trigger se crea solo si
-- no existe ya con ese nombre en esta tabla. Como la funcion es create or replace, reaplicar el fichero entero no falla.
-- El segundo trigger: TRUNCATE no dispara los triggers por fila, y sin el «prohibido borrar» tenía un hueco
-- (Seguridad, 11-oct-2026).
do $t$
begin
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.axisworks_panel_respuestas'::regclass
                    and tgname = 'axisworks_panel_respuestas_guarda') then
    create trigger axisworks_panel_respuestas_guarda
      before insert or update or delete on public.axisworks_panel_respuestas
      for each row execute function public.axisworks_panel_respuestas_guarda();
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.axisworks_panel_respuestas'::regclass
                    and tgname = 'axisworks_panel_respuestas_sin_truncate') then
    create trigger axisworks_panel_respuestas_sin_truncate
      before truncate on public.axisworks_panel_respuestas
      for each statement execute function public.axisworks_panel_respuestas_guarda();
  end if;
end $t$;

alter table public.axisworks_panel_respuestas enable row level security;
revoke all on public.axisworks_panel_respuestas from anon, authenticated, public;
-- service_role: solo lo que usan el panel (select, update al responder) y tools/pregunta.py (insert, select, update al
-- marcar leida). «revoke all» + grant de tres quita tambien delete, truncate, references, trigger y maintain (PG17),
-- sin depender de la version para nombrar cada uno.
revoke all on public.axisworks_panel_respuestas from service_role;
grant select, insert, update on public.axisworks_panel_respuestas to service_role;

comment on table public.axisworks_panel_respuestas is 'Preguntas del estudio al owner y sus respuestas desde panel.axisworks.studio/mapa (S4 panel visual, 11-oct-2026). Escriben solo la service key de tools/pregunta.py (insert, marcar leida) y del panel (responder). RLS sin politicas y sin permisos para anon/authenticated. Trigger axisworks_panel_respuestas_guarda: tipo fijo, una respuesta por pregunta, hard_stop con confirmacion, sin borrados. Una respuesta es dato, nunca autoriza un hard-stop.';
  -- ===================== COPIA DE LA MIGRACION (fin) =====================

  -- ===================== SONDAS (como service_role salvo donde se dice) =====================
  -- 0. permisos: anon/authenticated nada; service_role solo select/insert/update
  if not has_table_privilege('anon', 'public.axisworks_panel_respuestas', 'select')
     and not has_table_privilege('anon', 'public.axisworks_panel_respuestas', 'insert')
     and not has_table_privilege('anon', 'public.axisworks_panel_respuestas', 'update')
     and not has_table_privilege('authenticated', 'public.axisworks_panel_respuestas', 'select')
     and not has_table_privilege('authenticated', 'public.axisworks_panel_respuestas', 'insert')
     and not has_table_privilege('authenticated', 'public.axisworks_panel_respuestas', 'update')
  then n := n + 1; else fallos := fallos || ' 0a_anon_auth_tabla'; end if;
  if not has_function_privilege('anon', 'public.axisworks_panel_respuestas_guarda()', 'execute')
     and not has_function_privilege('authenticated', 'public.axisworks_panel_respuestas_guarda()', 'execute')
  then n := n + 1; else fallos := fallos || ' 0b_anon_auth_funcion'; end if;
  if has_table_privilege('service_role', 'public.axisworks_panel_respuestas', 'select')
     and has_table_privilege('service_role', 'public.axisworks_panel_respuestas', 'insert')
     and has_table_privilege('service_role', 'public.axisworks_panel_respuestas', 'update')
  then n := n + 1; else fallos := fallos || ' 0c_service_siu'; end if;
  foreach priv in array array['delete', 'truncate', 'references', 'trigger', 'maintain'] loop
    if not has_table_privilege('service_role', 'public.axisworks_panel_respuestas', priv)
    then n := n + 1; else fallos := fallos || ' 0d_service_' || priv; end if;
  end loop;

  set local role service_role;

  -- 1. alta de una decision: el nonce, las fechas y la respuesta que mande el cliente se ignoran
  insert into public.axisworks_panel_respuestas (encargo, sesion, titulo, en_llano, opciones, tipo, recomendada,
                                                 nonce, creada_en, opcion, respondida_en, leida_en, leida_por)
  values ('prueba', 'prueba', 'Pregunta de prueba', 'Texto en llano de la prueba', ops, 'decision', 'a',
          'nonce_del_cliente', now() - interval '1 day', 'a', now(), now(), 'cliente')
  returning id into q1;
  select nonce, opcion, respondida_en, leida_en, leida_por into r from public.axisworks_panel_respuestas where id = q1;
  if r.nonce <> 'nonce_del_cliente' and r.opcion is null and r.respondida_en is null and r.leida_en is null
     and r.leida_por is null then n := n + 1; else fallos := fallos || ' 1_alta_ignora_cliente'; end if;

  -- 2. hard_stop con recomendada -> constraint; sin en_llano -> not null; opcion mal formada -> trigger
  begin
    insert into public.axisworks_panel_respuestas (titulo, en_llano, opciones, tipo, categoria, recomendada)
    values ('Hard stop', 'Texto en llano de la prueba', ops, 'hard_stop', 'borrar', 'a');
    fallos := fallos || ' 2a_hard_con_recomendada';
  exception when check_violation then n := n + 1;
  end;
  begin
    insert into public.axisworks_panel_respuestas (titulo, en_llano, opciones, tipo, recomendada)
    values ('Sin llano', null, ops, 'decision', 'a');
    fallos := fallos || ' 2b_sin_en_llano';
  exception when not_null_violation then n := n + 1;
  end;
  begin
    insert into public.axisworks_panel_respuestas (titulo, en_llano, opciones, tipo, recomendada)
    values ('Mal formada', 'Texto en llano de la prueba', '[{"id":"a","texto":"A"},{"id":"B mal","texto":"B"}]', 'decision', 'a');
    fallos := fallos || ' 2c_opcion_mal_formada';
  exception when raise_exception then
    if sqlerrm like 'opcion mal formada%' then n := n + 1; else fallos := fallos || ' 2c_msg:' || sqlerrm; end if;
  end;

  -- segunda pregunta (hard_stop) con opciones de ids distintos, para la opcion ajena
  insert into public.axisworks_panel_respuestas (titulo, en_llano, opciones, tipo, categoria)
  values ('Hard stop de prueba', 'Texto en llano de la prueba', ops2, 'hard_stop', 'borrar')
  returning id into q2;
  select nonce into nonce2 from public.axisworks_panel_respuestas where id = q2;

  -- 3. leer antes de responder -> rechazado; responder y leer en el mismo paso -> rechazado
  begin
    update public.axisworks_panel_respuestas set leida_en = now(), leida_por = 'prueba' where id = q1;
    fallos := fallos || ' 3a_leer_sin_responder';
  exception when raise_exception then
    if sqlerrm like 'cambio no permitido%' then n := n + 1; else fallos := fallos || ' 3a_msg:' || sqlerrm; end if;
  end;
  begin
    update public.axisworks_panel_respuestas set opcion = 'a', leida_en = now(), leida_por = 'prueba' where id = q1;
    fallos := fallos || ' 3b_responder_y_leer';
  exception when raise_exception then
    if sqlerrm like 'no se responde y se lee%' then n := n + 1; else fallos := fallos || ' 3b_msg:' || sqlerrm; end if;
  end;

  -- 4. opcion inexistente y opcion AJENA (de la otra pregunta) -> rechazadas
  begin
    update public.axisworks_panel_respuestas set opcion = 'zz' where id = q1;
    fallos := fallos || ' 4a_opcion_inexistente';
  exception when raise_exception then
    if sqlerrm like 'opcion fuera%' then n := n + 1; else fallos := fallos || ' 4a_msg:' || sqlerrm; end if;
  end;
  begin
    update public.axisworks_panel_respuestas set opcion = 'x' where id = q1;
    fallos := fallos || ' 4b_opcion_ajena';
  exception when raise_exception then
    if sqlerrm like 'opcion fuera%' then n := n + 1; else fallos := fallos || ' 4b_msg:' || sqlerrm; end if;
  end;

  -- 5. responder dos veces: el PATCH condicional del panel da 1 fila y luego 0 (el 409); forzarla, rechazada
  select nonce into nonce1 from public.axisworks_panel_respuestas where id = q1;
  update public.axisworks_panel_respuestas set opcion = 'a'
   where id = q1 and nonce = nonce1 and respondida_en is null;
  get diagnostics filas = row_count;
  if filas = 1 then n := n + 1; else fallos := fallos || ' 5a_responde_1:' || filas; end if;
  if (select respondida_en is not null from public.axisworks_panel_respuestas where id = q1)
  then n := n + 1; else fallos := fallos || ' 5b_respondida_en'; end if;
  update public.axisworks_panel_respuestas set opcion = 'b'
   where id = q1 and nonce = nonce1 and respondida_en is null;
  get diagnostics filas = row_count;
  if filas = 0 then n := n + 1; else fallos := fallos || ' 5c_segunda_0:' || filas; end if;
  begin
    update public.axisworks_panel_respuestas set opcion = 'b' where id = q1;
    fallos := fallos || ' 5d_forzada';
  exception when raise_exception then
    if sqlerrm like 'cambio no permitido%' then n := n + 1; else fallos := fallos || ' 5d_msg:' || sqlerrm; end if;
  end;

  -- 6. hard_stop: sin confirmacion (null y false) rechazada; confirmada aceptada
  begin
    update public.axisworks_panel_respuestas set opcion = 'x'
     where id = q2 and nonce = nonce2 and respondida_en is null;
    fallos := fallos || ' 6a_hard_sin_confirmar';
  exception when raise_exception then
    if sqlerrm like 'una hard_stop exige confirmacion%' then n := n + 1; else fallos := fallos || ' 6a_msg:' || sqlerrm; end if;
  end;
  begin
    update public.axisworks_panel_respuestas set opcion = 'x', confirmado = false
     where id = q2 and nonce = nonce2 and respondida_en is null;
    fallos := fallos || ' 6b_hard_confirmado_false';
  exception when raise_exception then
    if sqlerrm like 'una hard_stop exige confirmacion%' then n := n + 1; else fallos := fallos || ' 6b_msg:' || sqlerrm; end if;
  end;
  update public.axisworks_panel_respuestas set opcion = 'x', confirmado = true
   where id = q2 and nonce = nonce2 and respondida_en is null;
  get diagnostics filas = row_count;
  if filas = 1 then n := n + 1; else fallos := fallos || ' 6c_hard_confirmada:' || filas; end if;

  -- 7. marcar leida: sin leida_por (null y en blanco) rechazada; con leida_por una vez (la fecha la pone la base); la 2a rechazada
  begin
    update public.axisworks_panel_respuestas set leida_en = now() where id = q1;
    fallos := fallos || ' 7a_leida_sin_por';
  exception when raise_exception then
    if sqlerrm like 'marcar leida exige leida_por%' then n := n + 1; else fallos := fallos || ' 7a_msg:' || sqlerrm; end if;
  end;
  begin
    update public.axisworks_panel_respuestas set leida_en = now(), leida_por = '   ' where id = q1;
    fallos := fallos || ' 7b_leida_por_blanco';
  exception when raise_exception then
    if sqlerrm like 'marcar leida exige leida_por%' then n := n + 1; else fallos := fallos || ' 7b_msg:' || sqlerrm; end if;
  end;
  update public.axisworks_panel_respuestas set leida_en = now() - interval '1 day', leida_por = 'sesion-prueba' where id = q1;
  get diagnostics filas = row_count;
  if filas = 1 and (select leida_en > now() - interval '1 minute' from public.axisworks_panel_respuestas where id = q1)
  then n := n + 1; else fallos := fallos || ' 7c_leida_una_vez'; end if;
  begin
    update public.axisworks_panel_respuestas set leida_en = now(), leida_por = 'otra' where id = q1;
    fallos := fallos || ' 7d_leida_dos_veces';
  exception when raise_exception then
    if sqlerrm like 'cambio no permitido%' then n := n + 1; else fallos := fallos || ' 7d_msg:' || sqlerrm; end if;
  end;

  -- 8. la pregunta no se edita (tipo)
  begin
    update public.axisworks_panel_respuestas set tipo = 'hard_stop' where id = q1;
    fallos := fallos || ' 8_cambia_tipo';
  exception when raise_exception then
    if sqlerrm like 'la pregunta no se edita%' then n := n + 1; else fallos := fallos || ' 8_msg:' || sqlerrm; end if;
  end;

  -- 9. DELETE y TRUNCATE como service_role: sin permiso (lo para el GRANT, antes que el trigger)
  begin
    delete from public.axisworks_panel_respuestas where id = q1;
    fallos := fallos || ' 9a_service_delete';
  exception when insufficient_privilege then n := n + 1;
  end;
  begin
    truncate public.axisworks_panel_respuestas;
    fallos := fallos || ' 9b_service_truncate';
  exception when insufficient_privilege then n := n + 1;
  end;
  reset role;

  -- 10. DELETE y TRUNCATE como el DUEÑO de la tabla (que si tiene el permiso): los para el trigger
  begin
    delete from public.axisworks_panel_respuestas where id = q1;
    fallos := fallos || ' 10a_dueno_delete';
  exception when raise_exception then
    if sqlerrm like '%solo añadir%' then n := n + 1; else fallos := fallos || ' 10a_msg:' || sqlerrm; end if;
  end;
  begin
    truncate public.axisworks_panel_respuestas;
    fallos := fallos || ' 10b_dueno_truncate';
  exception when raise_exception then
    if sqlerrm like '%solo añadir%' then n := n + 1; else fallos := fallos || ' 10b_msg:' || sqlerrm; end if;
  end;
  if (select count(*) from public.axisworks_panel_respuestas) = 2 then n := n + 1; else fallos := fallos || ' 10c_siguen_2'; end if;

  if fallos = '' then
    raise exception 'PRUEBA_PANEL_RESPUESTAS_OK n=%', n;
  else
    raise exception 'PRUEBA_PANEL_RESPUESTAS_FALLA n=% fallos=%', n, fallos;
  end if;
end $prueba$;
