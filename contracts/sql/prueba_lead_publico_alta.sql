-- PRUEBA de lead_publico_alta (27-sep-2026, cierre global de escrituras). Todo se revierte: el bloque acaba en
-- `raise exception 'RES: …'`. Cada línea debe decir «ok». Ejecutar como postgres (execute_sql o
-- `npx supabase db query --linked -f`); el bloque cambia a rol anon como el formulario de Sumba Hills.
do $$
declare r text := ''; n int; v record; e text := 'prueba.lead.' || floor(random() * 1e9)::text || '@example.invalid';
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  -- 1 alta normal
  perform public.lead_publico_alta(e, 'Ana Prueba', '+62 812-000', 'sumbahills-folleto', 'Sumba Hills', '203.0.113.7');
  reset role;
  select l.* into v from public.leads l where l.email = e;
  r := r || '1 alta=' || (v.id is not null) || ' campaign_id_null=' || (v.campaign_id is null) || ' whatsapp=' || coalesce(v.whatsapp, '-') || '; ';
  set local role anon;
  -- 2 email inválido
  begin perform public.lead_publico_alta('no-es-un-email', null, null, null, null, '203.0.113.7'); r := r || '2 FALLO email invalido; ';
  exception when others then r := r || '2 ok(' || sqlstate || '); '; end;
  -- 3 ritmo por email: 3 por hora
  perform public.lead_publico_alta(e, null, null, null, null, '203.0.113.8');
  perform public.lead_publico_alta(e, null, null, null, null, '203.0.113.9');
  begin perform public.lead_publico_alta(e, null, null, null, null, '203.0.113.10'); r := r || '3 FALLO 4a alta mismo email; ';
  exception when others then r := r || '3 ok(' || sqlstate || '); '; end;
  -- 4 canal en lista cerrada: un canal real pasa; uno inventado o que imita a Meta queda como «desconocido»
  perform public.lead_publico_alta('canal1.' || e, null, null, 'sumbahills-web', null, null);
  perform public.lead_publico_alta('canal2.' || e, null, null, 'meta-sumbahills', null, null);
  reset role;
  r := r || '4 web=' || (select source from public.leads where email = 'canal1.' || e)
          || ' meta_falso=' || (select source from public.leads where email = 'canal2.' || e) || '; ';
  set local role anon;
  -- 5 anon ya no inserta a pelo (tras 20260927172500) — antes del cierre esto pasa
  begin
    insert into public.leads (email, campaign_id) values ('directo.' || e, 'falsa');
    r := r || '5 INSERT directo de anon SIGUE ABIERTO (esperado solo antes de 172500); ';
  exception when others then r := r || '5 ok cerrado(' || sqlstate || '); '; end;
  -- 6 authenticated no ejecuta la RPC
  reset role;
  set local role authenticated;
  begin perform public.lead_publico_alta('auth.' || e); r := r || '6 FALLO authenticated la ejecuta; ';
  exception when others then r := r || '6 ok(' || sqlstate || '); '; end;
  raise exception 'RES: %', r;
end $$;
