-- PRUEBA — «falta por firmar» en comision_trazabilidad (migración 20261012230000, owner 12-oct-2026).
-- Se ejecuta ENTERA en una llamada con execute_sql (MCP) o psql como postgres, con la migración ya aplicada (o
-- dentro de la misma transacción, antes de este bloque). NO ESCRIBE NADA: cada caso va en un sub-bloque que acaba
-- en excepción (Postgres deshace lo que hizo, rol y claims incluidos) y el bloque entero termina en
-- `raise exception 'RES: …'`. Cada caso debe decir «ok».
-- Datos reales de Lawang a 12-oct-2026 (si cambian, el caso lo dice en vez de dar un falso «ok»):
--   C5 RP00140  solo la reserva firmada (41.200), sin contrato de construcción, parcela 41.200 + 66.000
--   B6 RP00202  CC00135 (71.000) sin firmar
--   C8 RP00209  CC00114 y CC00122 sin firmar, sustituidos por CC00123 firmado
--   C7 RP00046  descuento pactado: firmado 76.500 frente a 79.000 de la parcela
-- Casos: 1 C5 obra sin contrato · 2 B6 contrato pendiente · 3 C8 borrador sustituido · 4 C7 descuento no es falta ·
-- 5 C5 con base distinta de precio_total · 6 C8 sin el firmado: dos borradores del mismo tipo cuentan una vez ·
-- 7 vista sin operación completa: solo falta_algo, sin cifras.

do $$
declare
  r text := ''; v_t text; v_j jsonb;
  v_adm record; v_ben record;
  d_c5 uuid; d_b6 uuid; d_c8 uuid; d_c7 uuid; v_cond uuid; v_cc123 uuid;
begin
  select d.id, d.condicion_id into d_c5, v_cond from public.comisiones_devengadas d join public.contratos c on c.id = d.contrato_raiz_id
   where c.numero = 'RP00140' and d.nivel = 'manager' and d.estado <> 'anulada' limit 1;
  select d.id into d_b6 from public.comisiones_devengadas d join public.contratos c on c.id = d.contrato_raiz_id
   where c.numero = 'RP00202' and d.nivel = 'manager' and d.estado <> 'anulada' limit 1;
  select d.id into d_c8 from public.comisiones_devengadas d join public.contratos c on c.id = d.contrato_raiz_id
   where c.numero = 'RP00209' and d.nivel = 'manager' and d.estado <> 'anulada' limit 1;
  select d.id into d_c7 from public.comisiones_devengadas d join public.contratos c on c.id = d.contrato_raiz_id
   where c.numero = 'RP00046' and d.nivel = 'manager' and d.estado <> 'anulada' limit 1;
  select id into v_cc123 from public.contratos where numero = 'CC00123';
  select u.user_id, lower(u.email) e into v_adm from public.usuarios u
   where u.rol = 'super_admin' and u.activo
     and lower(u.email) not in (select lower(beneficiario_email) from public.comisiones_devengadas)
   order by u.email limit 1;
  if d_c5 is null or d_b6 is null or d_c8 is null or d_c7 is null or v_cc123 is null or v_adm.user_id is null then
    raise exception 'RES: falta base (C5 %, B6 %, C8 %, C7 %, CC00123 %, admin %)',
      d_c5 is not null, d_b6 is not null, d_c8 is not null, d_c7 is not null, v_cc123 is not null, v_adm.user_id is not null;
  end if;

  -- 1 · C5: la obra no tiene contrato → falta 66.000, todo a la vista del admin
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_c5);
    raise exception '%', format('%s/%s/%s/%s', v_j->>'falta_por_firmar', v_j->>'sin_contrato_obra', v_j->>'falta_algo', jsonb_array_length(v_j->'por_firmar'));
  exception when others then r := r || '1 C5=' || sqlerrm || case when sqlerrm = '66000/66000/true/0' then ' ok; ' else ' FALLO; ' end; end;

  -- 2 · B6: CC00135 sin firmar → falta 71.000 y aparece en por_firmar
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_b6);
    raise exception '%', format('%s/%s/%s', v_j->>'falta_por_firmar', v_j->'por_firmar'->0->>'numero', coalesce(v_j->>'sin_contrato_obra', 'null'));
  exception when others then r := r || '2 B6=' || sqlerrm || case when sqlerrm = '71000/CC00135/null' then ' ok; ' else ' FALLO; ' end; end;

  -- 3 · C8: los borradores sustituidos por el firmado no cuentan
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_c8);
    raise exception '%', format('%s/%s', v_j->>'falta_por_firmar', v_j->>'falta_algo');
  exception when others then r := r || '3 C8=' || sqlerrm || case when sqlerrm = '0/false' then ' ok; ' else ' FALLO; ' end; end;

  -- 4 · C7: un descuento pactado no es «falta por firmar»
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_c7);
    raise exception '%', format('%s/%s', v_j->>'falta_por_firmar', v_j->>'falta_algo');
  exception when others then r := r || '4 C7=' || sqlerrm || case when sqlerrm = '0/false' then ' ok; ' else ' FALLO; ' end; end;

  -- 5 · C5 con la condición sobre precio de suelo: firmar no sube la comisión → no avisa
  begin
    update public.condiciones_comision set base_calculo = 'precio_suelo' where id = v_cond;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_c5);
    raise exception '%', format('%s/%s', v_j->>'falta_por_firmar', v_j->>'falta_algo');
  exception when others then r := r || '5 base suelo=' || sqlerrm || case when sqlerrm = '0/false' then ' ok; ' else ' FALLO; ' end; end;

  -- 6 · C8 sin firmar CC00123: quedan tres borradores de construcción → cuenta uno (el más reciente, 51.000) y,
  --     como hay contrato de obra (aunque sea borrador), la obra de la parcela no se suma otra vez.
  --     (Se quita la firma y no se libera: un trigger deja sin efecto, en silencio, liberar un contrato firmado.)
  begin
    update public.contratos set bloqueado = false where id = v_cc123;
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm.user_id, 'email', v_adm.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_c8);
    raise exception '%', format('%s/%s/%s', v_j->>'falta_por_firmar', jsonb_array_length(v_j->'por_firmar'), coalesce(v_j->>'sin_contrato_obra', 'null'));
  exception when others then r := r || '6 C8 dos borradores=' || sqlerrm || case when sqlerrm = '51000/1/null' then ' ok; ' else ' FALLO; ' end; end;

  -- 7 · vista sin operación completa (el beneficiario de C5 si no tiene reparto): solo falta_algo, ninguna cifra
  begin
    select u.user_id, lower(u.email) e into v_ben from public.usuarios u
     where lower(u.email) = (select lower(beneficiario_email) from public.comisiones_devengadas where id = d_c5);
    perform set_config('request.jwt.claims', json_build_object('sub', v_ben.user_id, 'email', v_ben.e, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_j := public.comision_trazabilidad(d_c5);
    if (v_j->>'completa')::boolean then
      raise exception 'n/a (el beneficiario ve la operación completa)';
    end if;
    raise exception '%', format('%s/%s/%s/%s', v_j->>'falta_algo', coalesce(v_j->>'falta_por_firmar', 'null'),
                                coalesce(v_j->>'sin_contrato_obra', 'null'), (v_j->'por_firmar' = '[]'::jsonb)::text);
  exception when others then r := r || '7 sin vista completa=' || sqlerrm
    || case when sqlerrm = 'true/null/null/true' then ' ok; ' when sqlerrm like 'n/a%' then ' (sin perfil para el caso); ' else ' FALLO; ' end; end;

  raise exception 'RES: %', r;
end $$;
