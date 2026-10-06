-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 2 (OK del owner 6-oct-2026) · G3 + Sumba Hills: escribe datos.fields.sociedad_firmante en 7 contratos SIN FIRMAR.
-- destructivo-ok: añade una clave a datos de 9 filas; no borra nada; aborta si cambia cualquier otra cosa. No apaga triggers.
--   san_dal_woods: CG00005 (plantilla ppjb_reserva = su default de pantalla), RP00009 (Sumba Hills, decisión del owner),
--                  CR00048 (Sumba Hills, sin firmar, sin hijos y sin documentos).
--   tepi_sungai  : CO00004, HS00006, HS00007, RP00007 (lo que ya imprimen hoy).
-- Se tolera que el trigger trg_contrato_cuenta_es_escrow ESTAMPE datos.fields.cuenta_es_escrow ('si'/'no', derivado de la cuenta) en cada UPDATE:
-- es su comportamiento normal en cualquier guardado. Cualquier otra clave que cambie (p. ej. precio_lista_suelo) aborta.
-- RP00012 QUEDA FUERA: al tocarla el trigger trg_contrato_lista_suelo le estampa precio_lista_suelo=54.000 (hoy vacío): sería un cambio de precio.
-- CG00004 QUEDA FUERA: reclama la parcela A5 de Bonian, que ya tiene RP00012; el trigger sincroniza_unidad_contrato lanza 23505 ante
-- cualquier UPDATE de CG00004 (también desde la pantalla). Hay que decidir cuál de los dos conserva A5 antes de poder tocarlo.
-- NO se tocan: los 6 firmados (C200003, CC00006, HS00003/4/5, PA00006), CR00011 y CR00021 (firmados) y, por la regla del owner
-- «si hay hijos o facturas de otra sociedad, parar»: RP00082+CC00043, RP00125+CC00080 (hijos y documentos Tepi sin enviar) y
-- RP00170, RP00180 (tienen una solicitud de firma pendiente en contrato_firmas).
do $$
declare
  r record; n_mal int := 0;
begin
  create temp table _g3_obj (numero text primary key, nueva text not null) on commit drop;
  insert into _g3_obj values
    ('CG00005','san_dal_woods'),('RP00009','san_dal_woods'),('CR00048','san_dal_woods'),
    ('CO00004','tepi_sungai'),('HS00006','tepi_sungai'),('HS00007','tepi_sungai'),('RP00007','tepi_sungai');

  create temp table _g3_antes on commit drop as
    select c.id, c.numero, o.nueva, md5(((c.datos #- '{fields,sociedad_firmante}') #- '{fields,cuenta_es_escrow}')::text) md5_sin_clave_antes,
           (select md5(coalesce(string_agg(cc.client_id::text||cc.rol::text, ',' order by cc.client_id, cc.rol::text), '')) from public.contrato_compradores cc where cc.contrato_id = c.id) comp_antes,
           c.precio_total, c.bloqueado, c.contrato_padre_id, c.unidad_id, c.moneda, c.tipo
      from public.contratos c join _g3_obj o on o.numero = c.numero;

  if (select count(*) from _g3_antes) <> 7 then raise exception 'G3: se esperaban 7 contratos y hay %', (select count(*) from _g3_antes); end if;
  -- candado propio: nada firmado, nada con solicitudes de firma, nada ya relleno; CR00048 sin hijos ni documentos
  if exists (select 1 from public.contratos c join _g3_antes a on a.id=c.id where c.bloqueado
             or exists (select 1 from public.contrato_firmas f where f.contrato_id = c.id)
             or coalesce(c.datos->'fields'->>'sociedad_firmante','') <> (case when a.numero = 'CR00048' then 'tepi_sungai' else '' end)) then
    raise exception 'G3: algún contrato está firmado, tiene firmas o no tiene la sociedad previa esperada (vacía; CR00048: tepi_sungai); se para';
  end if;
  if exists (select 1 from _g3_antes a where a.numero='CR00048' and (
        exists (select 1 from public.contratos h where h.contrato_padre_id = a.id)
     or exists (select 1 from public.facturas f where f.contrato_id = a.id)
     or a.contrato_padre_id is not null)) then
    raise exception 'G3: CR00048 tiene hijos, documentos o padre; se para';
  end if;

  update public.contratos c
     set datos = jsonb_set(c.datos, '{fields,sociedad_firmante}', to_jsonb(a.nueva), true)
    from _g3_antes a where a.id = c.id;

  for r in
    select a.numero,
           (md5(((c.datos #- '{fields,sociedad_firmante}') #- '{fields,cuenta_es_escrow}')::text) is distinct from a.md5_sin_clave_antes) cambio_otra_cosa,
           (c.datos->'fields'->>'cuenta_es_escrow' is not null and c.datos->'fields'->>'cuenta_es_escrow' not in ('si','no')) escrow_raro,
           (c.datos->'fields'->>'sociedad_firmante') is distinct from a.nueva clave_mal,
           (c.datos_fields->>'sociedad_firmante') is distinct from a.nueva espejo_mal,
           (select md5(coalesce(string_agg(cc.client_id::text||cc.rol::text, ',' order by cc.client_id, cc.rol::text), '')) from public.contrato_compradores cc where cc.contrato_id = c.id) is distinct from a.comp_antes compradores_cambian,
           (c.precio_total, c.bloqueado, c.contrato_padre_id, c.unidad_id, c.moneda, c.tipo) is distinct from (a.precio_total, a.bloqueado, a.contrato_padre_id, a.unidad_id, a.moneda, a.tipo) columnas_cambian
      from public.contratos c join _g3_antes a on a.id = c.id
  loop
    if r.cambio_otra_cosa or r.escrow_raro or r.clave_mal or r.espejo_mal or r.compradores_cambian or r.columnas_cambian then
      n_mal := n_mal + 1; raise warning 'G3 %: %', r.numero, to_jsonb(r);
    end if;
  end loop;
  if n_mal > 0 then raise exception 'G3: % contratos con efectos secundarios; se aborta', n_mal; end if;
  -- y exactamente 9 filas con la clave puesta entre las 9
  if (select count(*) from public.contratos c join _g3_obj o on o.numero=c.numero where c.datos->'fields'->>'sociedad_firmante' = o.nueva) <> 7 then
    raise exception 'G3: no quedaron las 7 claves puestas';
  end if;
end $$;
-- REVERTIR (mismos triggers; CR00048 vuelve a tepi_sungai, que es lo que tenía; los otros 6 estaban sin la clave y sin cuenta_es_escrow):
--   update public.contratos set datos = (datos #- '{fields,sociedad_firmante}') #- '{fields,cuenta_es_escrow}'
--    where numero in ('CG00005','CO00004','HS00006','HS00007','RP00007','RP00009');
--   update public.contratos set datos = jsonb_set(datos #- '{fields,cuenta_es_escrow}', '{fields,sociedad_firmante}', '"tepi_sungai"') where numero = 'CR00048';
