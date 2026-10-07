-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Correccion puntual (OK del owner Lawang 7-oct-2026: «INV00157 de PT MOVENTUM CONSULTING BALI es de Tamarind Rise, de Tepi Sun Gai, corrigelo»):
--   INV00157 (factura 20.000 EUR, sin enviar, sin anular) esta en el proyecto Tamarind Rise (lawang) pero enlazada al contrato CC00084 (Sumba Hills,
--   san_dal_woods) y con sociedad san_dal_woods. Pasa a: contrato CC00085 (Tamarind Rise, tepi_sungai, mismo cliente) y sociedad tepi_sungai.
-- destructivo-ok: cambia en UNA fila (INV00157) sociedad, contrato_id, contrato_numero y, en el jsonb, fields.sociedad / fields.contrato_numero / fields.proyecto_nombre
--   (espejos: el documento imprimia Sumba Hills); el trigger congela_emisor_factura re-congela datos.emisor desde public.sociedades. NO toca proyecto_id, cuenta, PRO00157 ni contratos.
--   Aborta si cambia cualquier otra columna, si se mueven comisiones/avisos/notificaciones/unidades/contratos, o si el documento esta enviado/anulado o tiene dependientes.
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_inv00157.sql
do $$
declare
  v_id uuid; v_old_c uuid; v_new_c uuid; v_ant jsonb; v_des jsonb; v_md5 text; v_f public.facturas%rowtype;
begin
  select id into v_id from public.facturas where numero='INV00157' and tipo='factura';
  select id into v_old_c from public.contratos where numero='CC00084';
  select id into v_new_c from public.contratos where numero='CC00085';
  if v_id is null or v_old_c is null or v_new_c is null then raise exception 'INV00157: falta factura o contratos'; end if;
  select * into v_f from public.facturas where id=v_id;
  -- candado propio: estado esperado exacto, sin enviar, sin anular
  if coalesce(v_f.enviada,false) or v_f.fecha_envio is not null or v_f.anulada
     or v_f.sociedad <> 'san_dal_woods' or v_f.contrato_id <> v_old_c or v_f.contrato_numero <> 'CC00084'
     or v_f.proyecto_id <> '9b199eae-6497-4f41-b189-0a68d85af5cd' or v_f.client_id <> '9a554662-f102-4582-a1ee-749a79690d24' or v_f.total <> 20000 then
    raise exception 'INV00157: no esta en el estado esperado (enviada/anulada/ya corregida); se para';
  end if;
  -- el contrato nuevo encaja: de Tamarind Rise, firmante tepi_sungai, mismo cliente
  if not exists (select 1 from public.contratos c where c.id=v_new_c and c.proyecto_id=v_f.proyecto_id
                  and c.datos_fields->>'sociedad_firmante'='tepi_sungai' and c.adq1_client_id=v_f.client_id) then
    raise exception 'INV00157: CC00085 no es de Tamarind Rise / tepi_sungai / mismo cliente; se para';
  end if;
  -- sin dependientes
  if exists (select 1 from public.recibi_aplicaciones where factura_id=v_id or recibi_id=v_id)
     or exists (select 1 from public.contrato_vencimientos where factura_id=v_id)
     or exists (select 1 from public.correos_enviados where factura_id=v_id)
     or exists (select 1 from public.correos_cola where factura_id=v_id)
     or exists (select 1 from public.comision_admin_lineas where recibi_id=v_id)
     or exists (select 1 from public.hilo_soporte where factura_id=v_id) then
    raise exception 'INV00157: tiene aplicaciones/vencimientos/correos/comision/hilo vinculados; se para';
  end if;

  v_md5 := md5((to_jsonb(v_f) - 'sociedad' - 'contrato_id' - 'contrato_numero' - 'datos')::text
               || ((v_f.datos #- '{fields,sociedad}' #- '{fields,contrato_numero}' #- '{fields,proyecto_nombre}') #- '{emisor}')::text);
  v_ant := jsonb_build_object(
    'lineas',(select count(*) from public.comision_admin_lineas), 'lineas_log',(select count(*) from public.comision_admin_lineas_log),
    'devengadas',(select count(*) from public.comisiones_devengadas), 'diferencias',(select count(*) from public.comisiones_diferencias),
    'ajustes_log',(select count(*) from public.comisiones_ajustes_log), 'notif',(select count(*) from public.notificaciones),
    'av_reserva',(select count(*) from public.avisos_reserva), 'av_soporte',(select count(*) from public.avisos_soporte_equipo),
    'md5_lineas',(select md5(coalesce(string_agg(l::text, '|' order by l.id),'')) from public.comision_admin_lineas l),
    'md5_dev',(select md5(coalesce(string_agg(d::text, '|' order by d.id),'')) from public.comisiones_devengadas d),
    'md5_unidades',(select md5(coalesce(string_agg(u::text, '|' order by u.id),'')) from public.unidades u),
    'md5_contratos',(select md5(coalesce(string_agg(c::text, '|' order by c.id),'')) from public.contratos c),
    'md5_otras_facturas',(select md5(coalesce(string_agg(f::text, '|' order by f.id),'')) from public.facturas f where f.id<>v_id));

  update public.facturas f
     set sociedad = 'tepi_sungai', contrato_id = v_new_c, contrato_numero = 'CC00085',
         datos = jsonb_set(jsonb_set(jsonb_set(f.datos, '{fields,sociedad}', '"tepi_sungai"', true),
                                     '{fields,contrato_numero}', '"CC00085"', true),
                                     '{fields,proyecto_nombre}', to_jsonb(f.proyecto_nombre), true)
   where f.id = v_id;

  v_des := jsonb_build_object(
    'lineas',(select count(*) from public.comision_admin_lineas), 'lineas_log',(select count(*) from public.comision_admin_lineas_log),
    'devengadas',(select count(*) from public.comisiones_devengadas), 'diferencias',(select count(*) from public.comisiones_diferencias),
    'ajustes_log',(select count(*) from public.comisiones_ajustes_log), 'notif',(select count(*) from public.notificaciones),
    'av_reserva',(select count(*) from public.avisos_reserva), 'av_soporte',(select count(*) from public.avisos_soporte_equipo),
    'md5_lineas',(select md5(coalesce(string_agg(l::text, '|' order by l.id),'')) from public.comision_admin_lineas l),
    'md5_dev',(select md5(coalesce(string_agg(d::text, '|' order by d.id),'')) from public.comisiones_devengadas d),
    'md5_unidades',(select md5(coalesce(string_agg(u::text, '|' order by u.id),'')) from public.unidades u),
    'md5_contratos',(select md5(coalesce(string_agg(c::text, '|' order by c.id),'')) from public.contratos c),
    'md5_otras_facturas',(select md5(coalesce(string_agg(f::text, '|' order by f.id),'')) from public.facturas f where f.id<>v_id));
  if v_ant is distinct from v_des then raise exception 'INV00157: cambiaron comisiones/avisos/unidades/contratos/otras facturas: antes % despues %', v_ant, v_des; end if;

  select * into v_f from public.facturas where id=v_id;
  if v_f.sociedad <> 'tepi_sungai' or v_f.contrato_id <> v_new_c or v_f.contrato_numero <> 'CC00085'
     or v_f.datos->'fields'->>'sociedad' <> 'tepi_sungai' or v_f.datos->'fields'->>'contrato_numero' <> 'CC00085'
     or v_f.datos->'emisor'->>'clave' <> 'tepi_sungai' or coalesce(v_f.enviada,false) or v_f.anulada
     or v_f.datos->'fields'->>'cuenta' <> 'sandalwoods_dbs_sg'
     or v_f.proyecto_id <> '9b199eae-6497-4f41-b189-0a68d85af5cd'
     or md5((to_jsonb(v_f) - 'sociedad' - 'contrato_id' - 'contrato_numero' - 'datos')::text
            || ((v_f.datos #- '{fields,sociedad}' #- '{fields,contrato_numero}' #- '{fields,proyecto_nombre}') #- '{emisor}')::text) is distinct from v_md5 then
    raise exception 'INV00157: resultado distinto del esperado o cambio otra columna; se aborta';
  end if;
end $$;
