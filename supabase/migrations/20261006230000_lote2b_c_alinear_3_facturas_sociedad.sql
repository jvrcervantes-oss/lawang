-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 2b (OK del owner 6-oct-2026, decision C) · alinea la sociedad emisora de 3 documentos SIN ENVIAR con la de su contrato:
--   INV00005 san_dal_woods -> tepi_sungai (contrato CR00011, Tepi, firmado) · PRO00110 tepi_sungai -> san_dal_woods (RP00102)
--   PRO00223 tepi_sungai -> san_dal_woods (CC00117).
-- destructivo-ok: cambia 2 valores (facturas.sociedad y datos.fields.sociedad) en 3 filas; el trigger congela_emisor_factura re-congela datos.emisor
--   desde public.sociedades (comportamiento normal de un cambio de sociedad). No toca nada mas: aborta si cambia cualquier otra cosa o si los
--   conteos de comision_admin_lineas / comisiones_devengadas / avisos / notificaciones se mueven (los triggers de facturas tragan errores).
-- REVERTIR: supabase/reversion_lote2/REVERSION_lote2b.sql (bloque C).
do $$
declare
  r record; n_mal int := 0; v_ant jsonb; v_des jsonb;
begin
  create temp table _c_obj (numero text primary key, nueva text not null) on commit drop;
  insert into _c_obj values ('INV00005','tepi_sungai'),('PRO00110','san_dal_woods'),('PRO00223','san_dal_woods');

  create temp table _c_antes on commit drop as
    select f.id, f.numero, o.nueva, f.sociedad sociedad_antes,
           md5((to_jsonb(f) - 'sociedad' - 'datos' - 'enviada')::text || ((f.datos #- '{fields,sociedad}') #- '{emisor}')::text) md5_resto
      from public.facturas f join _c_obj o on o.numero = f.numero;
  if (select count(*) from _c_antes) <> 3 then raise exception 'C: se esperaban 3 documentos y hay %', (select count(*) from _c_antes); end if;
  -- candado propio: sin enviar, sin anular, tipo factura/proforma, contrato con la sociedad nueva
  if exists (select 1 from public.facturas f join _c_antes a on a.id=f.id
              left join public.contratos c on c.id = f.contrato_id
             where coalesce(f.enviada,false) or f.fecha_envio is not null or f.anulada or f.tipo not in ('factura','proforma')
                or c.id is null or coalesce(c.datos_fields->>'sociedad_firmante','') <> a.nueva or f.sociedad = a.nueva) then
    raise exception 'C: algun documento esta enviado/anulado, ya alineado o su contrato no es de la sociedad esperada; se para';
  end if;

  v_ant := jsonb_build_object(
    'lineas',(select count(*) from public.comision_admin_lineas), 'lineas_log',(select count(*) from public.comision_admin_lineas_log),
    'devengadas',(select count(*) from public.comisiones_devengadas), 'diferencias',(select count(*) from public.comisiones_diferencias),
    'ajustes_log',(select count(*) from public.comisiones_ajustes_log), 'notif',(select count(*) from public.notificaciones),
    'av_reserva',(select count(*) from public.avisos_reserva), 'av_soporte',(select count(*) from public.avisos_soporte_equipo),
    'md5_lineas',(select md5(coalesce(string_agg(l::text, '|' order by l.id),'')) from public.comision_admin_lineas l),
    'md5_dev',(select md5(coalesce(string_agg(d::text, '|' order by d.id),'')) from public.comisiones_devengadas d));

  update public.facturas f
     set sociedad = a.nueva,
         datos = jsonb_set(f.datos, '{fields,sociedad}', to_jsonb(a.nueva), true)
    from _c_antes a where a.id = f.id;

  v_des := jsonb_build_object(
    'lineas',(select count(*) from public.comision_admin_lineas), 'lineas_log',(select count(*) from public.comision_admin_lineas_log),
    'devengadas',(select count(*) from public.comisiones_devengadas), 'diferencias',(select count(*) from public.comisiones_diferencias),
    'ajustes_log',(select count(*) from public.comisiones_ajustes_log), 'notif',(select count(*) from public.notificaciones),
    'av_reserva',(select count(*) from public.avisos_reserva), 'av_soporte',(select count(*) from public.avisos_soporte_equipo),
    'md5_lineas',(select md5(coalesce(string_agg(l::text, '|' order by l.id),'')) from public.comision_admin_lineas l),
    'md5_dev',(select md5(coalesce(string_agg(d::text, '|' order by d.id),'')) from public.comisiones_devengadas d));
  if v_ant is distinct from v_des then raise exception 'C: cambiaron comisiones/avisos: antes % despues %', v_ant, v_des; end if;

  for r in
    select a.numero,
      (md5((to_jsonb(f) - 'sociedad' - 'datos' - 'enviada')::text || ((f.datos #- '{fields,sociedad}') #- '{emisor}')::text) is distinct from a.md5_resto) cambio_otra_cosa,
      f.sociedad is distinct from a.nueva sociedad_mal,
      (f.datos->'fields'->>'sociedad') is distinct from a.nueva espejo_mal,
      (f.datos->'emisor'->>'clave') is distinct from a.nueva emisor_mal,
      coalesce(f.enviada,false) enviada_ahora
      from public.facturas f join _c_antes a on a.id = f.id
  loop
    if r.cambio_otra_cosa or r.sociedad_mal or r.espejo_mal or r.emisor_mal or r.enviada_ahora then
      n_mal := n_mal + 1; raise warning 'C %: %', r.numero, to_jsonb(r);
    end if;
  end loop;
  if n_mal > 0 then raise exception 'C: % documentos con efectos secundarios; se aborta', n_mal; end if;
end $$;
