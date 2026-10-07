-- Prueba del tope por rol del descuento comercial en el Bloqueo de Parcela (7-oct-2026): admin 50 %, sales_manager 15 %,
-- super_admin sin tope. Se ejecuta por execute_sql con la migración 20261008980000 pegada delante (el raise final lo
-- deshace todo: 0 rastro). La lista del suelo la pone el servidor desde el inventario, así que los importes se calculan
-- sobre ella: ajustarlos si cambia el suelo del contrato elegido (28.275 el 7-oct, RP00257).
-- Esperado: S admin 50 % PASA · S admin >50 % RECHAZA · S sales 15 % PASA · S sales >15 % RECHAZA · S super 70 % PASA.
do $t$
declare out text := ''; res text; extra text; u_ad uuid; u_sa uuid; u_sm uuid; cs public.contratos%rowtype; cl text; i int;
  sc text[][] := array[['S admin 50%','ad','14137.50','14137.50','PASA'],['S admin >50%','ad','14200','14075','RECHAZA'],['S sales 15%','sm','4241.25','24033.75','PASA'],['S sales >15%','sm','4300','23975','RECHAZA'],['S super 70%','sa','20000','8275','PASA']];
begin
  select user_id into u_ad from public.usuarios where activo and rol='admin' limit 1;
  select user_id into u_sa from public.usuarios where activo and rol='super_admin' limit 1;
  select user_id into u_sm from public.usuarios where activo and rol='sales_manager' limit 1;
  select * into cs from public.contratos c where tipo='reserva_parcela' and not exists (select 1 from public.contrato_firmas f where f.contrato_id=c.id) order by created_at desc limit 1;
  for i in 1..array_length(sc,1) loop
    begin
      cl := json_build_object('sub', case sc[i][2] when 'ad' then u_ad when 'sa' then u_sa else u_sm end, 'role','authenticated')::text;
      perform set_config('request.jwt.claims', cl, true);
      update public.contratos set datos = jsonb_set(jsonb_set(datos,'{fields,descuento_comercial}', to_jsonb(sc[i][3]::text)),'{fields,descuento_comercial_motivo}', to_jsonb('prueba'::text)), precio_total = sc[i][4]::numeric where id = cs.id;
      raise exception '__PASO__';
    exception when others then res := case when sqlerrm like '\_\_PASO\_\_%' then 'PASA' else 'RECHAZA' end; extra := left(sqlerrm,130); end;
    out := out || sc[i][1] || ' => ' || res || ' (esp ' || sc[i][5] || ') ' || case when res=sc[i][5] then 'ok' else 'FALLO' end || ' · ' || extra || E'\n';
  end loop;
  raise exception E'RESULTADOS (contrato %)\n%', cs.numero, out;
end $t$;
