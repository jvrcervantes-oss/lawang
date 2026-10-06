-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 2c (decision explicita del owner, 6-oct-2026): pasa a san_dal_woods las familias RP00082+CC00043 y RP00125+CC00080 de Sumba Hills:
--   4 contratos SIN FIRMAR, sus 7 documentos sin enviar (INV00073 PRO00072 PRO00147 INV00178 PRO00071 INV00118 PRO00146)
--   y los 3 recibis ya cobrados (REC00055 25.000 EUR, REC00134 20.000 EUR, REC00084 10.000 EUR). La cuenta de cobro contractor_sumba_eur
--   es de un tercero (Achmad Zaeni, es_propia=false), no de ninguna sociedad del estudio: el cambio de emisor no contradice donde entro el dinero.
-- NO se tocan: RP00170, RP00180 (firma pendiente), CG00004, RP00012.
-- destructivo-ok: cambia datos.fields.sociedad_firmante en 4 contratos y facturas.sociedad + datos.fields.sociedad en 10 documentos;
--   los triggers re-congelan datos.emisor y, en los 3 recibis, comision_admin_lineas.sociedad (devengo pendiente) pasa a san_dal_woods:
--   efecto esperado y medido en ensayo (importes y conteos iguales). Aborta si cambia cualquier otra cosa. No apaga triggers.
-- Se tolera que contrato_lista_suelo_servidor ESTAMPE datos.fields.precio_lista_suelo en las 2 reservas (hoy vacio) SOLO si vale lo mismo que su precio_total
--   (25.000 = 25000): es el precio de lista del suelo que el trigger deriva de la parcela en cualquier guardado, no un cambio de precio.
-- Orden: contratos (reservas y luego construcciones, por la herencia del padre) -> documentos no-recibi -> recibis.
-- REVERTIR: supabase/reversion_lote2/REVERSION_lote2c.sql
do $$
declare
  r record; n_mal int := 0; v_ant jsonb; v_des jsonb;
  v_ctr text[] := array['RP00082','CC00043','RP00125','CC00080'];
  v_docs text[] := array['INV00073','PRO00072','PRO00147','INV00178','PRO00071','INV00118','PRO00146'];
  v_recs text[] := array['REC00055','REC00134','REC00084'];
  v_nueva constant text := 'san_dal_woods';
begin
  create temp table _c_antes on commit drop as
    select c.id, c.numero, c.tipo,
           md5((((c.datos #- '{fields,sociedad_firmante}') #- '{fields,cuenta_es_escrow}') #- '{fields,precio_lista_suelo}')::text) md5_sin_clave,
           (select md5(coalesce(string_agg(cc.client_id::text||cc.rol::text, ',' order by cc.client_id, cc.rol::text), '')) from public.contrato_compradores cc where cc.contrato_id = c.id) comp,
           c.precio_total, c.bloqueado, c.contrato_padre_id, c.unidad_id, c.moneda
      from public.contratos c where c.numero = any (v_ctr);
  create temp table _d_antes on commit drop as
    select f.id, f.numero, f.tipo, f.contrato_id,
           md5((to_jsonb(f) - 'sociedad' - 'datos')::text || ((f.datos #- '{fields,sociedad}') #- '{emisor}')::text) md5_resto,
           f.total, f.moneda, f.datos->'totales' totales
      from public.facturas f where f.numero = any (v_docs || v_recs);

  -- candados
  if (select count(*) from _c_antes) <> 4 then raise exception 'C2: se esperaban 4 contratos y hay %', (select count(*) from _c_antes); end if;
  if (select count(*) from _d_antes) <> 10 then raise exception 'C2: se esperaban 10 documentos y hay %', (select count(*) from _d_antes); end if;
  if exists (select 1 from public.contratos c where c.numero = any (v_ctr)
              and (c.bloqueado or exists (select 1 from public.contrato_firmas x where x.contrato_id = c.id)
                   or coalesce(c.datos_fields->>'sociedad_firmante','') <> 'tepi_sungai')) then
    raise exception 'C2: algun contrato esta firmado, tiene solicitud de firma o ya no es de tepi_sungai; se para';
  end if;
  if (select count(*) from public.facturas f join _c_antes a on a.id = f.contrato_id) <> 10 then
    raise exception 'C2: las 4 familias tienen documentos distintos de los 10 esperados; se para';
  end if;
  if exists (select 1 from public.facturas f join _d_antes d on d.id = f.id
              where coalesce(f.enviada,false) or f.fecha_envio is not null or f.anulada or f.sociedad <> 'tepi_sungai') then
    raise exception 'C2: algun documento esta enviado, anulado o ya no es de tepi_sungai; se para';
  end if;
  if (select count(*) from public.bancos_movimientos) <> 0 then raise exception 'C2: bancos_movimientos ya no esta vacia; se para'; end if;

  v_ant := jsonb_build_object(
    'lineas',(select count(*) from public.comision_admin_lineas),
    'devengadas',(select count(*) from public.comisiones_devengadas), 'diferencias',(select count(*) from public.comisiones_diferencias),
    'ajustes_log',(select count(*) from public.comisiones_ajustes_log), 'notif',(select count(*) from public.notificaciones),
    'av_reserva',(select count(*) from public.avisos_reserva), 'av_soporte',(select count(*) from public.avisos_soporte_equipo),
    'md5_lineas_sin_soc',(select md5(coalesce(string_agg(((to_jsonb(l) - 'sociedad') - 'actualizado_en')::text, '|' order by l.id),'')) from public.comision_admin_lineas l),
    'md5_dev',(select md5(coalesce(string_agg(d::text, '|' order by d.id),'')) from public.comisiones_devengadas d));

  -- 1) contratos: reservas (padres) y luego construcciones (hijos)
  update public.contratos c set datos = jsonb_set(c.datos, '{fields,sociedad_firmante}', to_jsonb(v_nueva), true)
    from _c_antes a where a.id = c.id and a.contrato_padre_id is null;
  update public.contratos c set datos = jsonb_set(c.datos, '{fields,sociedad_firmante}', to_jsonb(v_nueva), true)
    from _c_antes a where a.id = c.id and a.contrato_padre_id is not null;
  -- 2) documentos no-recibi
  update public.facturas f set sociedad = v_nueva, datos = jsonb_set(f.datos, '{fields,sociedad}', to_jsonb(v_nueva), true)
    from _d_antes d where d.id = f.id and d.tipo <> 'recibi';
  -- 3) recibis ya cobrados
  update public.facturas f set sociedad = v_nueva, datos = jsonb_set(f.datos, '{fields,sociedad}', to_jsonb(v_nueva), true)
    from _d_antes d where d.id = f.id and d.tipo = 'recibi';

  v_des := jsonb_build_object(
    'lineas',(select count(*) from public.comision_admin_lineas),
    'devengadas',(select count(*) from public.comisiones_devengadas), 'diferencias',(select count(*) from public.comisiones_diferencias),
    'ajustes_log',(select count(*) from public.comisiones_ajustes_log), 'notif',(select count(*) from public.notificaciones),
    'av_reserva',(select count(*) from public.avisos_reserva), 'av_soporte',(select count(*) from public.avisos_soporte_equipo),
    'md5_lineas_sin_soc',(select md5(coalesce(string_agg(((to_jsonb(l) - 'sociedad') - 'actualizado_en')::text, '|' order by l.id),'')) from public.comision_admin_lineas l),
    'md5_dev',(select md5(coalesce(string_agg(d::text, '|' order by d.id),'')) from public.comisiones_devengadas d));
  if v_ant is distinct from v_des then raise exception 'C2: cambiaron comisiones/avisos mas alla de la sociedad: antes % despues %', v_ant, v_des; end if;
  -- las 3 lineas de comision admin heredan la sociedad nueva, con el mismo importe total (125+100+50)
  if (select count(*) from public.comision_admin_lineas l where l.recibi_numero = any (v_recs) and l.sociedad = v_nueva and l.estado = 'pendiente' and not l.anulada) <> 3
     or (select sum(l.importe) from public.comision_admin_lineas l where l.recibi_numero = any (v_recs)) <> 275 then
    raise exception 'C2: las lineas de comision admin de los 3 recibis no quedaron en % con importe total 275', v_nueva;
  end if;

  for r in
    select a.numero,
      (md5((((c.datos #- '{fields,sociedad_firmante}') #- '{fields,cuenta_es_escrow}') #- '{fields,precio_lista_suelo}')::text) is distinct from a.md5_sin_clave) cambio_otra_cosa,
      (c.datos->'fields'->>'sociedad_firmante') is distinct from v_nueva clave_mal,
      (c.datos_fields->>'sociedad_firmante') is distinct from v_nueva espejo_mal,
      (c.datos->'fields'->>'cuenta_es_escrow' is not null and c.datos->'fields'->>'cuenta_es_escrow' not in ('si','no')) escrow_raro,
      (select md5(coalesce(string_agg(cc.client_id::text||cc.rol::text, ',' order by cc.client_id, cc.rol::text), '')) from public.contrato_compradores cc where cc.contrato_id = c.id) is distinct from a.comp compradores_cambian,
      ((c.precio_total, c.bloqueado, c.contrato_padre_id, c.unidad_id, c.moneda) is distinct from (a.precio_total, a.bloqueado, a.contrato_padre_id, a.unidad_id, a.moneda)
        or (c.tipo = 'reserva_parcela' and public.lw_importe(c.datos->'fields'->>'precio_lista_suelo') is distinct from c.precio_total)) columnas_cambian
      from public.contratos c join _c_antes a on a.id = c.id
    union all
    select d.numero,
      (md5((to_jsonb(f) - 'sociedad' - 'datos')::text || ((f.datos #- '{fields,sociedad}') #- '{emisor}')::text) is distinct from d.md5_resto),
      f.sociedad is distinct from v_nueva,
      (f.datos->'fields'->>'sociedad') is distinct from v_nueva,
      (f.datos->'emisor'->>'clave') is distinct from v_nueva,
      coalesce(f.enviada,false) or f.anulada,
      (f.total, f.moneda, f.datos->'totales') is distinct from (d.total, d.moneda, d.totales)
      from public.facturas f join _d_antes d on d.id = f.id
  loop
    if r.cambio_otra_cosa or r.clave_mal or r.espejo_mal or r.escrow_raro or r.compradores_cambian or r.columnas_cambian then
      n_mal := n_mal + 1; raise warning 'C2 %: %', r.numero, to_jsonb(r);
    end if;
  end loop;
  if n_mal > 0 then raise exception 'C2: % filas con efectos secundarios; se aborta', n_mal; end if;
end $$;
