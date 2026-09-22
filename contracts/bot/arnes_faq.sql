-- ============================================================================
-- ARNES — bot_faq / bot_temas / bot_respuestas_copiadas (22-sep-2026)
-- ----------------------------------------------------------------------------
-- Misma receta que `python tools/flujos_lawang.py --sql`: UNA transaccion que
-- acaba SIEMPRE en ROLLBACK, claims JWT por set_config ANTES de cambiar de rol,
-- `set local role authenticated` (el MCP corre como postgres con bypassrls: sin
-- cambiar de rol ninguna policy se evalua y todo saldria verde por el motivo
-- equivocado), tabla temporal `_arnes` con grant, `reset role` entre
-- identidades. Los casos que DEBEN parar aprueban SOLO con el texto del RAISE
-- propio (leccion C5/C8 del arnes de flujos): un fallo crudo no aprueba.
--
-- Identidades: super_admin = pepito@lawangproperties.com (fijo, como pide el
-- encargo); agente = el agente raso activo mas antiguo con contratos propios;
-- si ninguno los tiene, cualquier agente raso: el contrato ZZ-ARNES-FAQ-A de
-- abajo se crea a su nombre, asi que siempre tiene al menos uno. No se crea
-- ningun usuario: eso tocaria `auth`, y Datos no lo hace ni en una transaccion
-- revertida.
--
-- Se pega entero en mcp__supabase-lawang__execute_sql. Una fila con ok=false
-- es una regresion.
-- ============================================================================
begin;
-- destructivo-ok: arnés de bot_faq (contracts/bot/arnes_faq.sql); TODO dentro de una transacción que acaba en ROLLBACK
create temporary table _arnes(caso text, ok boolean, detalle text) on commit drop;
grant all on _arnes to authenticated, anon;

-- identidades resueltas desde la base, como postgres; solo viajan por GUCs de sesión
select set_config('arnes.admin_sub', u.user_id::text, true), set_config('arnes.admin_email', u.email, true)
  from public.usuarios u where u.activo and u.rol = 'super_admin' and u.email = 'pepito@lawangproperties.com';
select set_config('arnes.agente_sub', u.user_id::text, true), set_config('arnes.agente_email', u.email, true)
  from public.usuarios u
 where u.activo and u.rol = 'agente'
   and coalesce(array_length(u.proyectos_supervisados, 1), 0) = 0
 order by exists (select 1 from public.contratos c where c.creado_por = u.email) desc, u.creado_en
 limit 1;

-- claims del super_admin puestas ANTES de crear datos: hay triggers de contratos que miran auth.uid()
select set_config('request.jwt.claim.sub', current_setting('arnes.admin_sub'), true),
       set_config('request.jwt.claim.email', current_setting('arnes.admin_email'), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.admin_sub'),
                  'email', current_setting('arnes.admin_email'), 'role', 'authenticated')::text, true);

-- F1 como postgres: authenticated solo tiene SELECT sobre bot_temas, asi que
-- como admin pararia por 42501 antes de llegar al trigger. Aqui se prueba el
-- trigger de verdad.
do $$ begin
  insert into public.bot_temas (clave, nombre_es, nombre_en, patron, orden) values ('zz_arnes', 'zz', 'zz', '(', 99);
  insert into _arnes values ('F1 bot_temas: patron invalido DEBE parar', false, 'no paro: acepto "("');
exception when others then
  insert into _arnes values ('F1 bot_temas: patron invalido DEBE parar',
    sqlerrm like '%patrón de tema inválido%', sqlstate || ' ' || left(sqlerrm, 90));
end $$;

-- Datos de prueba, como postgres (sin RLS). Numeros explicitos: no se quema
-- ninguna secuencia real. Todo desaparece en el ROLLBACK final.
do $$
declare v_a uuid; v_b uuid; v_qa uuid; v_qb uuid;
begin
  insert into public.contratos (numero, tipo, datos, creado_por)
    values ('ZZ-ARNES-FAQ-A', 'acuerdo_comercial', '{}'::jsonb, current_setting('arnes.agente_email')) returning id into v_a;
  insert into public.contratos (numero, tipo, datos, creado_por)
    values ('ZZ-ARNES-FAQ-B', 'acuerdo_comercial', '{}'::jsonb, current_setting('arnes.admin_email')) returning id into v_b;
  -- consulta DEL AGENTE sobre SU contrato: el borrador lleva una cifra larga con separadores (1111-2222-33)
  insert into public.bot_consultas (contrato_id, preguntado_por, pregunta, respuesta, bloqueos)
    values (v_a, current_setting('arnes.agente_email'),
            '¿Cuál es el plazo de entrega de la villa y qué anexos hay?',
            '1. cita — Art. 6 Plazo de ejecución: campo `plazo_meses`. Referencia interna 1111-2222-33. Borrador generado por IA — revísalo antes de enviarlo',
            '[]'::jsonb) returning id into v_qa;
  -- consulta DEL ADMIN sobre SU contrato: el agente no debe verla ni copiar sobre ella
  insert into public.bot_consultas (contrato_id, preguntado_por, pregunta, respuesta, bloqueos)
    values (v_b, current_setting('arnes.admin_email'), 'When is the delivery date?', 'Art. 6.', '[]'::jsonb) returning id into v_qb;
  perform set_config('arnes.qa', v_qa::text, true);
  perform set_config('arnes.qb', v_qb::text, true);
  insert into _arnes values ('D datos de prueba', true, 'ok');
exception when others then insert into _arnes values ('D datos de prueba', false, sqlstate || ' ' || sqlerrm);
end $$;

-- Referencias para F9, como postgres: la MISMA join consulta x tema que hace
-- bot_temas_resumen(90), restringida al agente, y sin restringir.
select set_config('arnes.ref_agente',
         (select count(*)::text from public.bot_consultas q
            join public.bot_temas t on t.activo and q.pregunta ~* t.patron
           where q.preguntado_por = current_setting('arnes.agente_email')
             and q.creado_en >= now() - interval '90 days'), true),
       set_config('arnes.ref_total',
         (select count(*)::text from public.bot_consultas q
            join public.bot_temas t on t.activo and q.pregunta ~* t.patron
           where q.creado_en >= now() - interval '90 days'), true);

-- ── como super_admin autenticado ──
set local role authenticated;

do $$ begin insert into _arnes values ('F0 canario: rol y claims (super_admin)',
  current_user = 'authenticated' and auth.uid() is not null and auth.email() is not null and public.es_super_admin(),
  'current_user=' || current_user || ' uid=' || (auth.uid() is not null)::text || ' super=' || public.es_super_admin()::text);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;

do $$ begin
  insert into public.bot_faq (tema_clave, tipo_contrato, pregunta, respuesta)
    values ('anexos_planos', 'construccion', '¿Dónde pago los planos?', 'Transfiere a la cuenta 12.345.678 y listo');
  insert into _arnes values ('F2 bot_faq con cifra de 8 digitos DEBE parar', false, 'no paro');
exception when others then
  insert into _arnes values ('F2 bot_faq con cifra de 8 digitos DEBE parar',
    sqlerrm like '%cifra de 8 o más dígitos%', sqlstate || ' ' || left(sqlerrm, 90));
end $$;

do $$ begin
  insert into public.bot_faq (tema_clave, tipo_contrato, pregunta, respuesta)
    values ('quien_cobra', 'construccion', '¿A qué cuenta pago?', 'A la del promotor');
  insert into _arnes values ('F3 bot_faq sobre tema frenado (quien_cobra) DEBE parar', false, 'no paro');
exception when others then
  insert into _arnes values ('F3 bot_faq sobre tema frenado (quien_cobra) DEBE parar',
    sqlerrm like '%frenado por el asistente%', sqlstate || ' ' || left(sqlerrm, 90));
end $$;

do $$ declare ok1 boolean := false; ok2 boolean := false; ok3 boolean := false; d text := '';
begin
  -- 4a plazo_entrega nulo/nulo: para (tema frenado, y ademas sin alcance)
  begin
    insert into public.bot_faq (tema_clave, pregunta, respuesta) values ('plazo_entrega', '¿Cuándo?', 'Pronto');
    d := d || '4a:no paro ';
  exception when others then
    ok1 := sqlerrm like '%frenado por el asistente%' or sqlerrm like '%necesita proyecto o tipo%';
    d := d || '4a:' || sqlstate || ' ';
  end;
  -- 4b comunidad_gastos nulo/nulo (NO frenado): para SOLO por alcance
  begin
    insert into public.bot_faq (tema_clave, pregunta, respuesta) values ('comunidad_gastos', '¿Normas?', 'Las de siempre');
    d := d || '4b:no paro ';
  exception when others then
    ok2 := sqlerrm like '%necesita proyecto o tipo%';
    d := d || '4b:' || sqlstate || ' ';
  end;
  -- 4c documentos_expediente nulo/nulo (procedimiento): pasa
  begin
    insert into public.bot_faq (tema_clave, pregunta, respuesta) values ('documentos_expediente', '¿Dónde está mi recibo?', 'En Documentación del contrato');
    ok3 := true; d := d || '4c:ok';
  exception when others then d := d || '4c:' || sqlstate || ' ' || left(sqlerrm, 60);
  end;
  insert into _arnes values ('F4 alcance: nulo/nulo para salvo tema de procedimiento', ok1 and ok2 and ok3, d);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;

do $$ declare ok1 boolean := false; v_por text; v_en timestamptz; v_id uuid; d text := '';
begin
  begin
    insert into public.bot_faq (tema_clave, tipo_contrato, pregunta, respuesta)
      values ('anexos_planos', 'ppjb_construccion', '¿Hay planos?', 'Sí, en el anexo');
    d := d || '5a:no paro ';
  exception when others then
    ok1 := sqlerrm like '%tipo de contrato desconocido%';
    d := d || '5a:' || sqlstate || ' ';
  end;
  insert into public.bot_faq (tema_clave, tipo_contrato, pregunta, respuesta, aprobado_por, aprobado_en)
    values ('anexos_planos', 'construccion', '¿Hay planos?', 'Sí, en el anexo de especificaciones', 'otro@example.invalid', '2000-01-01')
    returning id, aprobado_por, aprobado_en into v_id, v_por, v_en;
  perform set_config('arnes.faq', v_id::text, true);
  insert into _arnes values ('F5 tipo_contrato: slug de plantilla para, contratos.tipo pasa y aprobado_por = sesion',
    ok1 and v_por = current_setting('arnes.admin_email') and v_en > now() - interval '1 minute',
    d || '5b:aprobado_por=sesion:' || (v_por = current_setting('arnes.admin_email'))::text);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;

do $$ declare ok1 boolean := false; n int; ok3 boolean := false; d text := '';
begin
  begin
    update public.bot_faq set respuesta = 'otra' where id = current_setting('arnes.faq')::uuid;
    d := d || '6a:no paro ';
  exception when others then ok1 := sqlerrm like '%no se edita%'; d := d || '6a:' || sqlstate || ' ';
  end;
  update public.bot_faq set activo = false where id = current_setting('arnes.faq')::uuid;
  get diagnostics n = row_count;
  d := d || '6b:retiradas=' || n || ' ';
  begin
    update public.bot_faq set activo = true where id = current_setting('arnes.faq')::uuid;
    d := d || '6c:no paro';
  exception when others then ok3 := sqlerrm like '%no se edita%'; d := d || '6c:' || sqlstate;
  end;
  insert into _arnes values ('F6 bot_faq: editar para, retirar pasa, reactivar para', ok1 and n = 1 and ok3, d);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;

reset role;
-- ── como agente raso autenticado ──
select set_config('request.jwt.claim.sub', current_setting('arnes.agente_sub'), true),
       set_config('request.jwt.claim.email', current_setting('arnes.agente_email'), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('arnes.agente_sub'),
                  'email', current_setting('arnes.agente_email'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$ begin
  -- tema de procedimiento y nulo/nulo: el trigger pasa entero, lo que para es la policy
  insert into public.bot_faq (tema_clave, pregunta, respuesta) values ('documentos_expediente', '¿Recibo?', 'En Documentación');
  insert into _arnes values ('F7 agente raso no aprueba FAQ', false, 'no paro');
exception when others then
  insert into _arnes values ('F7 agente raso no aprueba FAQ', sqlstate = '42501', sqlstate || ' ' || left(sqlerrm, 90));
end $$;

do $$ declare okc boolean := false; okb boolean := false; oka boolean := false; n int; d text := '';
begin
  -- 8c cifra que NO esta en el borrador
  begin
    insert into public.bot_respuestas_copiadas (consulta_id, texto, copiado_por)
      values (current_setting('arnes.qa')::uuid, 'Paga a la cuenta 98765432', current_setting('arnes.agente_email'));
    d := d || '8c:no paro ';
  exception when others then okc := sqlerrm like '%cifra que no está en el borrador%'; d := d || '8c:' || sqlstate || ' ';
  end;
  -- 8b consulta de otro
  begin
    insert into public.bot_respuestas_copiadas (consulta_id, texto, copiado_por)
      values (current_setting('arnes.qb')::uuid, 'Art. 6.', current_setting('arnes.agente_email'));
    d := d || '8b:no paro ';
  exception when others then okb := sqlstate = '42501'; d := d || '8b:' || sqlstate || ' ';
  end;
  -- 8a consulta propia, con la cifra del borrador (1111-2222-33) reescrita sin guiones
  insert into public.bot_respuestas_copiadas (consulta_id, texto, copiado_por)
    values (current_setting('arnes.qa')::uuid, 'Art. 6: campo plazo_meses. Ref 1111 2222 33.', current_setting('arnes.agente_email'));
  select count(*) into n from public.bot_respuestas_copiadas where consulta_id = current_setting('arnes.qa')::uuid;
  oka := n = 1;
  d := d || '8a:guardadas_y_visibles=' || n;
  insert into _arnes values ('F8 copia: cifra ajena para, consulta ajena para, la propia pasa', okc and okb and oka, d);
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;

do $$ declare v_total bigint; v_frenado boolean; v_filas int;
begin
  select coalesce(sum(r.consultas), 0), bool_or(r.frenado) filter (where r.tema_clave = 'quien_cobra'), count(*)
    into v_total, v_frenado, v_filas
    from public.bot_temas_resumen(90) r;
  insert into _arnes values ('F9 bot_temas_resumen(90) como agente = solo sus consultas',
    v_total = current_setting('arnes.ref_agente')::bigint
      and v_total < current_setting('arnes.ref_total')::bigint
      and v_frenado and v_filas = 9,
    format('agente=%s ref_agente=%s ref_total=%s quien_cobra_frenado=%s filas=%s',
           v_total, current_setting('arnes.ref_agente'), current_setting('arnes.ref_total'), v_frenado, v_filas));
exception when others then insert into _arnes values ('(reventó)', false, sqlstate || ' ' || sqlerrm); end $$;

reset role;
select caso, ok, detalle from _arnes order by caso;
rollback;
