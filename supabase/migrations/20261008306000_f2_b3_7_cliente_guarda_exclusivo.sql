-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 7 (7-oct-2026), por la consulta de Seguridad: un administrador de empresa NO reescribe la identidad ni el KYC de un cliente que tiene contratos o facturas en la otra empresa.
--   En un cliente compartido solo puede tocar `notes` e `idioma_comunicacion`; identidad (nombre, email, telefono, nacionalidad, pasaporte, tipo, datos de empresa) y kyc_status exigen que TODO el cliente sea de sus empresas (admin_de_cliente(.., true)).
--   Un administrador global y quien no es rol de empresa: sin cambio.
-- destructivo-ok: create or replace de una funcion (anade una condicion); sin tocar datos
--   Solo aplica a roles de empresa: un agente normal edita sus fichas como siempre (corregido en vivo en dos pasos el mismo dia; este fichero es el resultado final).
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
create or replace function pg_temp.f2_edita(p_fn text, p_viejo text, p_nuevo text) returns void language plpgsql as $f$
declare d text; n int;
begin
  d := pg_get_functiondef(p_fn::regprocedure);
  n := (length(d) - length(replace(d, p_viejo, ''))) / length(p_viejo);
  if n <> 1 then raise exception 'f2_edita %: el fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo, 70); end if;
  execute replace(d, p_viejo, p_nuevo);
end $f$;
select pg_temp.f2_edita('public.cliente_guarda(uuid,jsonb)',
  $v$v_kyc_antes := coalesce(v_old.kyc_status, 'pending');$v$,
  $n$v_kyc_antes := coalesce(v_old.kyc_status, 'pending');
    if public.es_admin_en_alguna_empresa() and not public.es_admin() and not public.admin_de_cliente(p_id, true)
       and exists (select 1 from jsonb_object_keys(p_datos) k where k not in ('notes', 'idioma_comunicacion')) then
      raise exception 'Este comprador tiene contratos o pagos en otra empresa: aqui solo puedes cambiar las notas y el idioma; su identidad y su KYC los toca un administrador de las dos empresas'
        using errcode = '42501';
    end if;$n$);
