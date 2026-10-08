-- Portal: Facturas enseña el ESTADO de pago de cada factura y qué recibí la salda (8-oct-2026, owner:
-- «llévalo al portal real», sobre el artifact «Lawang Facturas v2»).
--
-- Revisión previa (Seguridad + Administración, 8-oct, #226):
--  · `aplicado` por factura = public.factura_aplicado(), la misma suma que usa la intranet
--    (facturas_pendiente_equipo). Solo en tipo 'factura': una proforma no se cobra y un recibí no se debe.
--  · `salda` por recibí = las facturas a las que se aplicó, con su importe. Sale del MISMO conjunto que la
--    lista (`mis_facturas`): hoy hay aplicaciones sobre facturas anuladas y que cruzan contratos, y un filtro
--    escrito dos veces acabaría enseñando el número de una factura ajena o de una proforma sin enviar.
--  · factura_aplicado() era un oráculo: SECURITY DEFINER, ejecutable por `authenticated` y sin mirar de quién
--    es la factura — un comprador del portal podía preguntar lo cobrado de cualquier uuid. Ningún front la
--    llama, pero no se puede revocar (la usan facturas_pendiente_equipo y finanzas_resumen_semanal, que corren
--    como quien llama). Se le pone la guarda: para un usuario del portal que NO es del equipo, solo sus
--    facturas; si no, null. Hay cuentas que son del equipo y también del portal (20260922150315): sin el
--    `not es_agente()` les devolvería null en facturas ajenas, el pendiente de la intranet saldría null y el
--    disparador factura_anulada_solo_cambia_autor dejaría reactivar un recibí sin mirar el tope de la factura
--    (revisor de código, 8-oct). Para el equipo, las cuentas mixtas y el cron no cambia nada.
--
-- Parche sobre la definición en vivo, como las migraciones anteriores de portal_situacion (17-sep, 7-oct):
-- cada sustitución tiene que encontrar su texto o la migración falla — nunca se aplica a medias.

create or replace function public.factura_aplicado(p_factura uuid)
returns numeric
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if public.es_portal() and not public.es_agente() and not exists (
       select 1
         from public.facturas f
         join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
         join public.portal_accesos pa on pa.client_id = cc.client_id
        where f.id = p_factura
          and pa.activo
          and pa.email = lower(coalesce(auth.email(), ''))) then
    return null;
  end if;
  return (select coalesce(sum(ra.importe_aplicado), 0)
            from public.recibi_aplicaciones ra
            join public.facturas r on r.id = ra.recibi_id
           where ra.factura_id = p_factura
             and not coalesce(r.anulada, false));
end
$function$;

do $mig$
declare
  d text;
  sustituye text[][] := array[
    -- 1) el conjunto de facturas visibles, una sola vez
    array[
$m$      join mis_clientes mc on mc.client_id = cc.client_id
  )
  select jsonb_build_object($m$,
$m$      join mis_clientes mc on mc.client_id = cc.client_id
  ),
  mis_facturas as (
    select f.id
      from public.facturas f
     where f.contrato_id in (select id from mis_ids)
       and not coalesce(f.anulada, false)
       and (f.tipo <> 'proforma' or f.enviada)
  )
  select jsonb_build_object($m$],
    -- 2) estado de pago y aplicaciones
    array[
$m$        'emisor',          f.datos->'emisor'$m$,
$m$        'emisor',          f.datos->'emisor',
        'aplicado',        case when f.tipo = 'factura' then public.factura_aplicado(f.id) end,
        'salda',           case when f.tipo = 'recibi' then coalesce((
                             select jsonb_agg(jsonb_build_object('numero', fa.numero, 'importe', ra.importe_aplicado)
                                              order by fa.fecha_emision, fa.numero)
                               from public.recibi_aplicaciones ra
                               join public.facturas fa on fa.id = ra.factura_id
                              where ra.recibi_id = f.id
                                and fa.id in (select id from mis_facturas)), '[]'::jsonb) end$m$],
    -- 3) la lista lee del mismo conjunto
    array[
$m$     where f.contrato_id in (select id from mis_ids)
       and not coalesce(f.anulada, false)
       and (f.tipo <> 'proforma' or f.enviada)), '[]'::jsonb),$m$,
$m$     where f.id in (select id from mis_facturas)), '[]'::jsonb),$m$]
  ];
  i int;
begin
  select pg_get_functiondef(p.oid) into strict d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where p.proname = 'portal_situacion';

  if position('mis_facturas' in d) > 0 then
    raise notice 'portal_situacion ya proyecta el estado de pago';
    return;
  end if;

  for i in 1 .. array_length(sustituye, 1) loop
    if position(sustituye[i][1] in d) = 0 then
      raise exception 'portal_situacion: no encuentro el texto de la sustitución %', i;
    end if;
    d := replace(d, sustituye[i][1], sustituye[i][2]);
  end loop;

  execute d;
end $mig$;
